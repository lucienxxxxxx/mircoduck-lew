import importlib.util
import json
import os
from pathlib import Path
import sys
import unittest
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'gateway'))
from protocol import decode, encode
from server import Gateway, Telemetry, remote, ZERO

KEY = bytes(range(32))
ADDRESS = ('127.0.0.1',30000)
SID = '01'*16


class FakeControl:
    def __init__(self):
        self.real=[]; self.frames=[]; self.releases=0
    def command(self, command):
        self.frames.append(command)
        return {'accepted':not bool(self.real)}
    def release(self,takeover=False): self.releases+=1
    def expired(self): return False


class DatagramTests(unittest.TestCase):
    def setUp(self):
        self.now=10.0
        self.control=FakeControl()
        self.gateway=Gateway(KEY,self.control,None,clock=lambda:self.now)
        response=self.gateway.request(encode(KEY,{'v':1,'op':'hello','sid':SID,'seq':1}),ADDRESS)
        self.ticket=decode(KEY,response)['ticket']
        self.seq=1

    def send(self,op,**fields):
        self.seq+=1
        return self.gateway.request(encode(KEY,{'v':1,'sid':SID,'ticket':self.ticket,'seq':self.seq,'op':op,**fields}),ADDRESS)

    def test_authenticated_unicode_roundtrip_and_tamper_rejection(self):
        message={'v':1,'op':'error','reason':'实体手柄已接管'}
        wire=encode(KEY,message)
        self.assertEqual(decode(KEY,wire),message)
        envelope=json.loads(wire); envelope['p']+=' '
        with self.assertRaises(ValueError): decode(KEY,json.dumps(envelope).encode())

    def test_handshake_never_sends_actuator_intent(self):
        self.assertEqual(self.control.frames,[])
        self.assertFalse(self.gateway.session.claimed)

    def test_disconnect_releases_session_and_allows_immediate_new_handshake(self):
        self.send('claim')
        self.assertTrue(decode(KEY,self.send('release',disconnect=True))['accepted'])
        self.assertIsNone(self.gateway.session)
        result=self.gateway.request(encode(KEY,{'v':1,'op':'hello','sid':'02'*16,'seq':1}),ADDRESS)
        self.assertEqual(decode(KEY,result)['op'],'hello')
        self.assertFalse(self.gateway.session.claimed)

    def test_replayed_handshake_and_frame_are_rejected(self):
        with self.assertRaises(ValueError):
            self.gateway.request(encode(KEY,{'v':1,'sid':SID,'seq':1,'op':'hello'}),ADDRESS)
        wire=encode(KEY,{'v':1,'sid':SID,'seq':2,'ticket':self.ticket,'op':'claim'})
        self.gateway.request(wire,ADDRESS)
        with self.assertRaises(ValueError): self.gateway.request(wire,ADDRESS)
        self.assertEqual(len(self.control.frames),1)

    def test_wrong_endpoint_does_not_steal_claim(self):
        wire=encode(KEY,{'v':1,'sid':SID,'seq':2,'ticket':self.ticket,'op':'claim'})
        with self.assertRaises(ValueError): self.gateway.request(wire,('127.0.0.2',30000))
        self.assertEqual(self.control.frames,[])

    def test_expiry_releases_and_delayed_input_cannot_reacquire(self):
        self.send('claim')
        self.assertTrue(self.gateway.session.claimed)
        self.now+=.301
        self.gateway.expire()
        self.assertFalse(self.gateway.session.claimed)
        with self.assertRaises(ValueError): self.send('frame',frame={})
        self.assertGreater(self.control.releases,0)

    def test_old_server_ticket_does_not_extend_motion(self):
        self.now+=.451
        with self.assertRaises(ValueError): self.send('claim')
        self.assertEqual(self.control.frames,[])

    def test_ticket_rotation_allows_delivery_race_but_never_extends_original_lifetime(self):
        self.now+=.36
        self.gateway.session.rotate('next-ticket',self.now)
        self.assertTrue(decode(KEY,self.send('claim'))['accepted'])
        self.now+=.10
        with self.assertRaises(ValueError): self.send('frame',frame=ZERO)

    def test_real_gamepad_refuses_phone_claim(self):
        self.control.real=[{'name':'Physical Xbox'}]
        result=decode(KEY,self.send('claim'))
        self.assertFalse(result['accepted'])
        self.assertFalse(self.gateway.session.claimed)

    def test_unsupported_actions_and_unclaimed_frames_are_rejected(self):
        with self.assertRaises(ValueError): self.send('frame',frame={})
        self.send('claim')
        with self.assertRaises(ValueError): self.send('action',action='write-register')

    def test_unknown_key_and_oversize_are_rejected(self):
        with self.assertRaises(ValueError): decode(bytes(32),encode(KEY,{'v':1}))
        with self.assertRaises(ValueError): decode(KEY,b' '*1401)

    def test_telemetry_uses_native_names_and_stale_samples_stay_stale(self):
        t=Telemetry('/unused',clock=lambda:10.0)
        t.error='';t.at=9.9
        t.bus={'mode':'commissioning','updated_at_us':2000000,'last_sample':{
            'at_us':1000000,'servos':[{'id':20,'position_raw':2050}],
            'imu':{'valid':True,'gravity':[0,0,-1],'gyro_rad_s':[0,0,0],'sequence':4}}}
        packets=t.packets()
        self.assertFalse(packets[0]['fresh'])
        self.assertEqual(packets[0]['imu_seq'],4)
        self.assertEqual(packets[1]['rows'][0][2],2050)
        for packet in packets:
            self.assertLessEqual(len(encode(KEY,{'v':1,'sid':SID,'seq':1,'ticket':self.ticket,**packet})),1400)


@unittest.skipUnless(os.name=='posix', 'Linux kernel ownership locks')
class InputLeaseTests(unittest.TestCase):
    class Robot:
        def __init__(self): self.sent=[]
        def notify(self,calls): self.sent.extend(calls)
        def close(self): pass

    def test_console_and_phone_cannot_hold_the_same_kernel_lease(self):
        with tempfile.TemporaryDirectory() as directory:
            path=str(Path(directory)/'input.lock')
            a=remote.Input(self.Robot(),lease_path=path)
            b=remote.Input(self.Robot(),lease_path=path)
            try:
                self.assertTrue(a.command({'action':'state','owner':'console-0001','frame':ZERO})['accepted'])
                self.assertFalse(b.command({'action':'state','owner':'phone-000001','frame':ZERO})['accepted'])
                a.release()
                self.assertTrue(b.command({'action':'state','owner':'phone-000001','frame':ZERO})['accepted'])
            finally: a.release();b.release()

    def test_neutral_input_owner_expires_instead_of_locking_forever(self):
        with tempfile.TemporaryDirectory() as directory:
            now=[10.0]
            a=remote.Input(self.Robot(),clock=lambda:now[0],lease_path=str(Path(directory)/'input.lock'))
            try:
                a.command({'action':'state','owner':'console-0001','frame':ZERO})
                now[0]+=.7
                self.assertTrue(a.expired())
                self.assertIsNone(a.owner_lock)
                self.assertIsNone(a.owner)
            finally: a.release()


if __name__=='__main__': unittest.main()
