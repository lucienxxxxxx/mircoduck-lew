#!/usr/bin/env python3
"""Microduck phone UDP adapter; actuator access goes through existing robotd IPC."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import secrets
import selectors
import socket
import subprocess
import sys
import threading
import time
from protocol import MAX_PACKET, Session, decode, encode

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('console_input', ROOT/'console/remote_input.py')
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)

SKILLS = {'walk', 'sit_toggle', 'ground_pick', 'kick_left', 'kick_right', 'roulade'}
IDS = [20,21,22,23,24,30,31,32,33,34,10,11,12,13,14]
ZERO = {'axes': {k: 0 for k in remote.AXES}, 'buttons': []}


def rounded(value):
    return round(value, 5) if type(value) in (int, float) and math.isfinite(value) else None


class Telemetry:
    def __init__(self, path, clock=time.monotonic):
        self.path, self.clock = path, clock
        self.lock = threading.Lock()
        self.bus, self.state, self.error = {}, {}, 'Waiting for robotd'
        self.at, self.state_at = 0, 0
        self.skills = []
        self.policies, self.policy_at = {}, 0
        self.stop = threading.Event()

    def start(self):
        for target in (self.poll, self.subscribe):
            threading.Thread(target=target, daemon=True).start()

    def poll(self):
        robot = remote.Robot(self.path)
        while not self.stop.is_set():
            try:
                result = robot.request('robot.busStatus')
                with self.lock:
                    self.bus, self.at, self.error = result, self.clock(), ''
                if result.get('mode') == 'motion' and self.clock()-self.policy_at > 1:
                    try:
                        policies = robot.request('robot.policies')
                        with self.lock: self.policies, self.policy_at = policies, self.clock()
                    except Exception:
                        robot.close()
                elif result.get('mode') != 'motion':
                    with self.lock: self.policies = {}
            except Exception as exc:
                robot.close()
                with self.lock: self.error = str(exc)[:160]
            self.stop.wait(.2)
        robot.close()

    def subscribe(self):
        while not self.stop.is_set():
            try:
                with socket.socket(socket.AF_UNIX) as peer:
                    peer.settimeout(2)
                    peer.connect(self.path)
                    peer.sendall(b'{"jsonrpc":"2.0","id":1,"method":"robot.subscribe","params":{"hz":10}}\n')
                    with peer.makefile('rb') as reader:
                        while not self.stop.is_set():
                            line = reader.readline(262145)
                            if not line.endswith(b'\n') or len(line) > 262144:
                                raise OSError('State subscription disconnected')
                            row = json.loads(line)
                            with self.lock:
                                if row.get('method') == 'robot.state':
                                    self.state, self.state_at = row['params'], self.clock()
                                elif row.get('id') == 1 and isinstance(row.get('result'), dict):
                                    self.skills = row['result'].get('skills', [])
            except Exception:
                self.stop.wait(.5)

    def packets(self):
        now = self.clock()
        with self.lock:
            bus, state, at, state_at, error = self.bus, self.state, self.at, self.state_at, self.error
            policies, policy_at = self.policies, self.policy_at
        commissioning = bus.get('mode') == 'commissioning'
        sample = bus.get('last_sample') or {}
        diag = bus.get('native') or bus
        sensor = (sample.get('imu') or {}) if commissioning else (state.get('imu') or {})
        gravity = sensor.get('gravity') if commissioning else (state.get('safety') or {}).get('gravity')
        local_age = (now-at)*1000 if at else None
        server_age = diag.get('sample_age_ms')
        if commissioning:
            a, b = bus.get('updated_at_us'), sample.get('at_us')
            server_age = max(0,(a-b)/1000) if type(a) in (int,float) and type(b) in (int,float) else None
        age = max(local_age or 0, (server_age or 0)+(local_age or 0)) if at and server_age is not None else None
        state_fresh = bool(state_at and now-state_at < .5)
        fresh = age is not None and age < 500 and not error and bus.get('fresh_sample') is not False
        if not commissioning: fresh = fresh and state_fresh
        status = {'op':'status','build':bus.get('build'),'mode':bus.get('mode'),
                  'phase':bus.get('phase'),'fresh':fresh,'age':rounded(age),
                  'homed':bus.get('homed') is True,'policy':bus.get('policy_enabled') is True,
                  'torque':bus.get('torque_state') if commissioning else diag.get('torque_state_confirmed'),
                  'hz':rounded(bus.get('achieved_hz') or (state.get('control_loop') or {}).get('hz')),
                  'g':gravity,'gyro':sensor.get('gyro_rad_s') if commissioning else sensor.get('gyro'),
                  'imu_valid':sensor.get('valid') if commissioning else diag.get('imu_ready'),
                  'imu_seq':sensor.get('sequence') if commissioning else diag.get('imu_sequence'),'error':error[:160],
                  'state_age':rounded((now-state_at)*1000) if state_at else None}
        status['sitting'] = policies.get('sitting') if now-policy_at < 2 else None
        available = [name for name in policies.get('skills', []) if name in SKILLS]
        for slot in policies.get('slots', []):
            if slot.get('path') and slot.get('slot') in ('sitstand', 'ground_pick'):
                available.append('sit_toggle' if slot['slot'] == 'sitstand' else 'ground_pick')
        status['skills'] = sorted(set(available)) if now-policy_at < 2 else []
        rows = sample.get('servos', []) if commissioning else diag.get('joints', [])
        by_id = {r.get('id'):r for r in rows if isinstance(r, dict)}
        targets = state.get('targets') or []
        compact = []
        for index, ident in enumerate(IDS):
            row = by_id.get(ident,{})
            row_age = age if commissioning else (rounded(row.get('sample_age_ms')) or 0)+(local_age or 0)
            row_fresh = fresh and bool(row) and (commissioning or row.get('feedback_fresh') is True) and row_age < 500
            compact.append([ident, rounded(row.get('position_rad')), row.get('position_raw'),
                            rounded(row.get('temperature_c')), rounded(row.get('voltage_v',row.get('volts'))),
                            rounded(row.get('current_raw')), rounded(targets[index]) if index < len(targets) and state_fresh else None,
                            row_fresh, rounded(row_age)])
        return [status, {'op':'joints','part':0,'rows':compact[:8]}, {'op':'joints','part':1,'rows':compact[8:]}]


class Gateway:
    def __init__(self, key, control, telemetry, clock=time.monotonic):
        self.key, self.control, self.telemetry, self.clock = key, control, telemetry, clock
        self.session = None
        self.used_sids = set()
        self.job = None
        self.job_lock = threading.Lock()
        self.reply_seq = 0
        self.reset_ipc = threading.Event()

    def close_control(self):
        self.control.release(takeover=bool(self.control.real))
        if self.session:
            self.session.claimed, self.session.input_at = False, None

    def expire(self):
        if self.reset_ipc.is_set():
            self.control.robot.close()
            self.reset_ipc.clear()
        now = self.clock()
        s = self.session
        if s and s.claimed and s.input_at is not None and now-s.input_at > .3:
            self.close_control()
        if s and now-s.seen > 2:
            self.close_control()
            self.session = None
        self.control.expired()

    def response(self, payload):
        s = self.session
        if s is None: return None
        self.reply_seq += 1
        return encode(self.key, {'v':1,'sid':s.sid,'seq':self.reply_seq,
                                 'ticket':s.ticket, **payload})

    def request(self, wire, address):
        message = decode(self.key, wire)
        now = self.clock()
        self.expire()
        if message.get('op') == 'hello':
            sid = message.get('sid')
            if not isinstance(sid,str) or len(sid) != 32 or any(c not in '0123456789abcdef' for c in sid):
                raise ValueError('Invalid session nonce')
            if sid in self.used_sids:
                raise ValueError('Replayed handshake; use a fresh nonce')
            if self.session is not None:
                raise ValueError('Another phone session is connected')
            if len(self.used_sids) > 4096:
                raise ValueError('Handshake budget exhausted; restart adapter')
            self.used_sids.add(sid)
            self.session = Session(sid, address, now, secrets.token_hex(12))
            return self.response({'op':'hello','accepted':True,'input_timeout_ms':300,
                                  'skills':sorted(SKILLS),'mapping':'r17-xbox-v1'})
        s = self.session
        if s is None: raise ValueError('Reconnect required')
        s.accept(message, address, now)
        operation = message.get('op')
        if operation == 'ping':
            return self.response({'op':'pong','reply':message['seq'],'claimed':s.claimed})
        if operation == 'release':
            self.close_control()
            reply = self.response({'op':'ack','reply':message['seq'],'accepted':True,'claimed':False})
            if message.get('disconnect') is True: self.session = None
            return reply
        if operation == 'claim':
            if self.job and self.job.is_alive(): raise ValueError('Power preparation is still running')
            result = self.control.command({'action':'state','owner':s.sid,'frame':ZERO})
            s.claimed = result.get('accepted') is True
            s.input_at = now if s.claimed else None
        elif operation == 'frame':
            if not s.claimed: raise ValueError('Explicit claim required after connection or timeout')
            result = self.control.command({'action':'state','owner':s.sid,'frame':message.get('frame')})
            if result.get('accepted') is True: s.input_at = now
            else: self.close_control()
        elif operation == 'action':
            if not s.claimed: raise ValueError('Claim control first')
            action = message.get('action')
            if action in ('motion','commissioning'):
                self.close_control()
                self.switch_mode(action)
                result = {'accepted':True,'reason':'Mode request started; observe actual status, then claim again'}
            elif action in ('home','relax','policy-off','policy-on','chirp'):
                methods = {'home':('robot.init',{}),'relax':('robot.relax',{}),
                           'policy-off':('robot.enable',{'on':False}),
                           'policy-on':('robot.enable',{'on':True}), 'chirp':('robot.sound',{'tag':'chirp'})}
                method, params = methods[action]
                result = self.control.robot.request(method, params)
                if action in ('relax','policy-off'): self.close_control()
            elif action in SKILLS or action == 'sitstand':
                result = self.control.robot.request('robot.do',{'skill':'sit_toggle' if action == 'sitstand' else action})
            else: raise ValueError('Unsupported action')
        else: raise ValueError('Unsupported operation')
        return self.response({'op':'ack','reply':message['seq'],'accepted':result.get('accepted',True),
                              'reason':str(result.get('reason',''))[:160],'claimed':s.claimed})

    def switch_mode(self, mode):
        if os.geteuid() != 0: raise ValueError('Mode switch needs the installed system service')
        if self.job and self.job.is_alive(): raise ValueError('A mode switch is already running')
        def run():
            path = '/opt/robot/feetech-ft5-r5/service.sh'
            try:
                completed = subprocess.run(['/bin/bash',path,'enable' if mode == 'motion' else 'disable'],
                                           capture_output=True,timeout=150)
                self.job_result = {'success':completed.returncode == 0,
                                   'message':completed.stderr.decode(errors='replace')[-160:]}
            except Exception as exc: self.job_result = {'success':False,'message':str(exc)[:160]}
            finally: self.reset_ipc.set()
        self.job_result = {'success':None,'message':'running'}
        self.job = threading.Thread(target=run,daemon=True)
        self.job.start()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=20043)
    parser.add_argument('--key-file', type=Path, required=True)
    parser.add_argument('--socket', default='/run/robotd.sock')
    args = parser.parse_args()
    key = bytes.fromhex(args.key_file.read_text().strip())
    if len(key) != 32: raise ValueError('Pairing key must contain 32 random bytes')
    telemetry = Telemetry(args.socket)
    control = remote.Input(remote.Robot(args.socket))
    gateway = Gateway(key, control, telemetry)
    peer = remote.monitor()
    control.hotplug(remote.devices())
    def drain():
        changed = False
        try:
            while True:
                event = peer.recv(65536)
                if len(event) == 65536: raise OSError('Truncated input event')
                if b'SUBSYSTEM=input' in event: changed = True
        except BlockingIOError: pass
        if changed:
            control.event_epoch += 1
            control.hotplug(remote.devices())
            gateway.close_control()
    control.events = drain
    telemetry.start()
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as udp, selectors.DefaultSelector() as selector:
        udp.bind((args.bind,args.port)); udp.setblocking(False)
        selector.register(udp,selectors.EVENT_READ,'udp')
        selector.register(peer,selectors.EVENT_READ,'input')
        last_status = 0
        try:
            while True:
                for selected,_ in selector.select(.02):
                    drain()
                    gateway.expire()
                    if selected.data == 'udp':
                        wire,address = udp.recvfrom(MAX_PACKET+1)
                        try:
                            reply = gateway.request(wire,address)
                            if reply: udp.sendto(reply,address)
                        except (ValueError,OSError,KeyError,TypeError) as exc:
                            s = gateway.session
                            # Bad authentication and unknown endpoints receive no reflection.
                            try:
                                verified = decode(key,wire)
                                if s and address == s.address and verified.get('sid') == s.sid:
                                    udp.sendto(gateway.response({'op':'error','reply':verified.get('seq'),'reason':str(exc)[:160],'claimed':s.claimed}),address)
                            except (ValueError,TypeError,KeyError): pass
                gateway.expire()
                now = time.monotonic()
                s = gateway.session
                if s and now-last_status >= .1:
                    # A short overlap tolerates delivery races without extending any ticket's lifetime.
                    if now-s.ticket_at > .35:
                        s.rotate(secrets.token_hex(12), now)
                    for packet in telemetry.packets():
                        packet.update(claimed=s.claimed,real_gamepad=bool(control.real),input_mode=control.mode)
                        if gateway.job: packet['mode_job'] = gateway.job_result
                        try: udp.sendto(gateway.response(packet),s.address)
                        except (ValueError,OSError): pass
                    last_status = now
        finally:
            gateway.close_control(); telemetry.stop.set(); control.robot.close(); peer.close()


if __name__ == '__main__':
    main()
