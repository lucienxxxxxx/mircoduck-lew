#!/usr/bin/env python3
"""DuckPilot board CLI. Local IPC controls and reversible NetworkManager switching."""
import argparse
import contextlib
import fcntl
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import uuid

VERSION = '0.4.0'
RUN = Path('/run/duckctl')
PENDING = RUN/'network.json'
NM_DIR = Path('/etc/NetworkManager/system-connections')
SKILLS = ('walk','sit_toggle','ground_pick','kick_left','kick_right','roulade')
SERVICES = ('robotd','mircoduck-udp','mediad','NetworkManager')


def run(argv, timeout=35):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                       env={**os.environ, 'LC_ALL':'C.UTF-8'})
    if p.returncode:
        # Do not echo arguments: a caller's configuration may contain secrets.
        raise RuntimeError((p.stderr or p.stdout).strip() or f'{argv[0]} exited {p.returncode}')
    return p.stdout.strip()


def root():
    if os.geteuid() != 0:
        raise RuntimeError('此命令需要 sudo，例如 sudo duckctl relax')


def output(value):
    print(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False))


def rpc(method, params=None, path='/run/robotd.sock'):
    with socket.socket(socket.AF_UNIX) as peer:
        peer.settimeout(15)
        peer.connect(path)
        peer.sendall((json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params or {}})+'\n').encode())
        with peer.makefile('rb') as reader:
            for _ in range(100):
                line=reader.readline(262145)
                if not line.endswith(b'\n') or len(line)>262144:
                    raise RuntimeError('robotd 返回无效或过大报文')
                reply=json.loads(line)
                if reply.get('id') != 1: continue
                if 'error' in reply: raise RuntimeError(str(reply['error']))
                result=reply.get('result')
                if isinstance(result,dict) and result.get('accepted') is False:
                    raise RuntimeError(result.get('reason','robotd 拒绝请求'))
                return result
            raise RuntimeError('robotd 未回复请求')


def state_sample(path='/run/robotd.sock'):
    with socket.socket(socket.AF_UNIX) as peer:
        peer.settimeout(3);peer.connect(path)
        peer.sendall(b'{"jsonrpc":"2.0","id":1,"method":"robot.subscribe","params":{"hz":1}}\n')
        with peer.makefile('rb') as reader:
            for _ in range(10):
                line=reader.readline(262145)
                if not line.endswith(b'\n') or len(line)>262144:
                    raise RuntimeError('状态订阅断开或报文过大')
                row=json.loads(line)
                if row.get('error'): raise RuntimeError(str(row['error']))
                if row.get('method')=='robot.state': return row['params']
        raise RuntimeError('未收到 robot.state')


@contextlib.contextmanager
def control_lease():
    """One-shot motor intent shares the same lease as phone/console."""
    root()
    with open('/run/lock/mircoduck-input.lock','a') as lease:
        try: fcntl.flock(lease,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: raise RuntimeError('手机或控制台正在控制，请先停止其输入')
        import importlib.util
        path=Path('/opt/mircoduck-lew/console/remote_input.py')
        if not path.exists(): raise RuntimeError('请安装完整 DuckPilot 接入层')
        spec=importlib.util.spec_from_file_location('duck_input',path)
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        if mod.devices(): raise RuntimeError('实体手柄已连接，请先断开手柄')
        yield


def keyfile_string(value):
    if any(ord(c)<32 or ord(c)==127 for c in value):
        raise ValueError('SSID/密码不得包含换行或控制字符')
    # GLib keyfile string escaping, including leading/trailing spaces.
    return value.replace('\\','\\\\').replace(' ','\\s')


def profile_text(mode, ssid, password, interface, ident):
    if not 1<=len(ssid.encode())<=32: raise ValueError('SSID 必须为 1–32 个 UTF-8 字节')
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,15}',interface): raise ValueError('网卡名称无效')
    if not (8<=len(password.encode())<=63 and all(32<=ord(c)<=126 for c in password)
            or re.fullmatch(r'[0-9a-fA-F]{64}',password)):
        raise ValueError('Wi-Fi 密码须为 8–63 个 ASCII 字符或 64 位十六进制 PSK')
    if mode not in ('sta','ap'): raise ValueError('网络模式无效')
    text=f'''[connection]
id=DuckPilot-{mode}-{ident[:8]}
uuid={ident}
type=wifi
interface-name={interface}
autoconnect=false
autoconnect-priority=999

[wifi]
ssid={keyfile_string(ssid)}
mode={'ap' if mode=='ap' else 'infrastructure'}
security=802-11-wireless-security
'''
    if mode=='ap': text+='band=bg\n'
    text+=f'''
[wifi-security]
key-mgmt=wpa-psk
psk={keyfile_string(password)}
psk-flags=0

[ipv4]
method={'shared' if mode=='ap' else 'auto'}
'''
    if mode=='ap': text+='address1=10.42.0.1/24\n'
    return text+'\n[ipv6]\nmethod=disabled\n'


def nm(*args, timeout=35):
    if not shutil.which('nmcli'): raise RuntimeError('需要 NetworkManager/nmcli，见 docs/CLI.md')
    return run(['nmcli','--wait','25',*args],timeout)


def interface_name(requested):
    rows=nm('-t','-f','DEVICE,TYPE,STATE','device','status').splitlines()
    wifi={r.split(':')[0]:r.split(':')[2] for r in rows if ':wifi:' in r}
    if requested is None:
        if len(wifi)!=1: raise RuntimeError('请用 --interface 指定无线网卡')
        requested=next(iter(wifi))
    if requested not in wifi or wifi[requested] in ('unmanaged','unavailable'):
        raise RuntimeError('无线网卡未由 NetworkManager 管理或不可用；不自动修改 netplan')
    return requested


def current_uuid(interface):
    value=nm('-g','GENERAL.CON-UUID','device','show',interface)
    return '' if value in ('','--') else str(uuid.UUID(value))


@contextlib.contextmanager
def network_lock():
    root();RUN.mkdir(mode=0o700,exist_ok=True)
    with (RUN/'lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        yield


def save(row):
    tmp=RUN/'network.tmp'
    with tmp.open('w',encoding='utf-8') as f:
        os.chmod(tmp,0o600);json.dump(row,f)
    tmp.replace(PENDING)


def load(token=None):
    if not PENDING.exists(): raise RuntimeError('没有待确认的网络切换')
    row=json.loads(PENDING.read_text())
    if token is not None and row['token']!=token: raise RuntimeError('切换编号不匹配')
    return row


def schedule_network(mode, args):
    root()
    interface=interface_name(args.interface)
    if mode=='ap' and nm('-g','WIFI-PROPERTIES.AP','device','show',interface)!='yes':
        raise RuntimeError('此无线网卡不支持 AP 模式')
    with network_lock():
        if PENDING.exists() and load()['phase'] in ('scheduled','applying','await-confirm'):
            raise RuntimeError('已有网络切换，请先 wifi confirm 或 wifi rollback')
        previous=current_uuid(interface)
        ident=str(uuid.uuid4()); token=uuid.uuid4().hex[:12]
        if args.profile:
            if args.ssid or args.password_stdin:
                raise ValueError('--profile 不与 --ssid/--password-stdin 同用')
            ident=str(uuid.UUID(args.profile))
            # Reuse only the selected kind of Wi-Fi profile.
            if nm('-g','connection.type','connection','show','uuid',ident)!='802-11-wireless':
                raise ValueError('--profile 必须指定 Wi-Fi UUID')
            profile_mode=nm('-g','802-11-wireless.mode','connection','show','uuid',ident)
            if profile_mode not in (('ap',) if mode=='ap' else ('','infrastructure')):
                raise ValueError('--profile 的 STA/AP 模式不匹配')
            old_auto=nm('-g','connection.autoconnect','connection','show','uuid',ident)
            old_priority=nm('-g','connection.autoconnect-priority','connection','show','uuid',ident)
            created=False
        else:
            if not args.ssid: raise ValueError('请用 --ssid 指定网络名称')
            password=sys.stdin.readline().rstrip('\r\n') if args.password_stdin else getpass.getpass('Wi-Fi 密码（隐藏输入）: ')
            content=profile_text(mode,args.ssid,password,interface,ident)
            NM_DIR.mkdir(mode=0o700,parents=True,exist_ok=True)
            path=NM_DIR/f'duckpilot-{ident}.nmconnection'
            with path.open('x',encoding='utf-8') as f:
                os.chmod(path,0o600);f.write(content)
            try: nm('connection','load',str(path))
            except Exception:
                path.unlink(missing_ok=True);raise
            old_auto='no';old_priority='999';created=True
        if ident==previous: raise RuntimeError('已经连接到目标配置，无需切换')
        row={'token':token,'interface':interface,'target':ident,'previous':previous,
             'mode':mode,'created':created,'old_auto':old_auto,'old_priority':old_priority,
             'phase':'scheduled','deadline':time.time()+123}
        save(row)
        script=str(Path(__file__).resolve())
        try:
            # Rollback exists independently of SSH and the applying worker.
            run(['systemd-run','--quiet',f'--unit=duckctl-rollback-{token}','--on-active=123s',
                 '/usr/bin/python3',script,'_network','rollback',token])
            run(['systemd-run','--quiet',f'--unit=duckctl-apply-{token}','--on-active=3s',
                 '/usr/bin/python3',script,'_network','apply',token])
        except Exception:
            rollback(row);raise
        output({'scheduled':True,'token':token,'mode':mode,'interface':interface,
                'confirm_with':f'sudo duckctl wifi confirm {token}',
                'rollback_after_seconds':123,
                'board_address':('按已有 AP 配置，wifi status 查看' if args.profile else '10.42.0.1')
                                if mode=='ap' else '由路由器 DHCP 分配'})


def rollback(row):
    if row['phase'] in ('committed','rolled-back'): return
    try:
        if row['created']:
            nm('connection','modify','uuid',row['target'],'connection.autoconnect','no')
        else:
            nm('connection','modify','uuid',row['target'],'connection.autoconnect',row['old_auto'],
               'connection.autoconnect-priority',row['old_priority'])
        if row['previous']:
            nm('connection','up','uuid',row['previous'],'ifname',row['interface'])
        elif current_uuid(row['interface'])==row['target']:
            nm('connection','down','uuid',row['target'])
        if row['created']: nm('connection','delete','uuid',row['target'])
        row['phase']='rolled-back';row.pop('error',None)
    except Exception as exc:
        row['phase']='rollback-failed';row['error']=str(exc)
    save(row)
    if row['phase']=='rollback-failed': raise RuntimeError(row['error'])


def network_action(action, token):
    with network_lock():
        row=load(token)
        if action=='rollback': rollback(row)
        elif action=='apply':
            if row['phase']!='scheduled': return
            row['phase']='applying';save(row)
            try:
                nm('connection','up','uuid',row['target'],'ifname',row['interface'])
                if current_uuid(row['interface'])!=row['target']:
                    raise RuntimeError('目标网络未激活')
                row['phase']='await-confirm';save(row)
            except Exception:
                rollback(row);raise
        elif action=='confirm':
            if row['phase']=='committed': return
            if row['phase']!='await-confirm' or time.time()>=row['deadline']:
                raise RuntimeError('切换未就绪或已过期，请检查 wifi status')
            if current_uuid(row['interface'])!=row['target']:
                raise RuntimeError('当前并非目标网络，不能确认')
            # Lower only this tool's other profiles; foreign profiles stay intact.
            for path in NM_DIR.glob('duckpilot-*.nmconnection'):
                ident=path.stem.removeprefix('duckpilot-')
                if ident!=row['target']:
                    nm('connection','modify','uuid',ident,'connection.autoconnect-priority','-999')
            nm('connection','modify','uuid',row['target'],'connection.autoconnect','yes',
               'connection.autoconnect-priority','999')
            row['phase']='committed';save(row)
        output(row)


def parser():
    p=argparse.ArgumentParser(description='DuckPilot 统一主板控制命令；卸力=释放扭矩，非关机。')
    p.add_argument('--version',action='version',version='duckctl '+VERSION)
    sub=p.add_subparsers(dest='command',required=True)
    for name in ('status','imu','joints','policies','stand','relax','stop','docs'):
        sub.add_parser(name)
    sub.add_parser('power').add_argument('state',choices=['on'])
    sub.add_parser('policy').add_argument('state',choices=['on','off'])
    sub.add_parser('skill').add_argument('name',choices=SKILLS)
    sub.add_parser('sound').add_argument('name',choices=['short'])
    s=sub.add_parser('service');s.add_argument('action',choices=['status','start','stop','restart']);s.add_argument('name',choices=SERVICES)
    s=sub.add_parser('logs');s.add_argument('name',choices=SERVICES);s.add_argument('-n',type=int,default=80);s.add_argument('-f','--follow',action='store_true')
    wifi=sub.add_parser('wifi').add_subparsers(dest='wifi',required=True)
    for name in ('status','scan','profiles'): wifi.add_parser(name)
    for mode in ('sta','ap'):
        s=wifi.add_parser(mode);s.add_argument('--ssid');s.add_argument('--interface');s.add_argument('--password-stdin',action='store_true')
        s.add_argument('--profile',help='复用相应模式的现有 Wi-Fi UUID，无需输入密码')
    for name in ('confirm','rollback'): wifi.add_parser(name).add_argument('token')
    s=sub.add_parser('_network',help=argparse.SUPPRESS);s.add_argument('action',choices=['apply','rollback']);s.add_argument('token')
    return p


def main(argv=None):
    args=parser().parse_args(argv)
    try:
        cmd=args.command
        if cmd=='docs':
            path=Path(__file__).resolve().parents[1]/'docs/CLI.md'
            print(path.read_text(encoding='utf-8'))
        elif cmd=='_network': network_action(args.action,args.token)
        elif cmd=='wifi':
            if args.wifi in ('sta','ap'): schedule_network(args.wifi,args)
            elif args.wifi in ('confirm','rollback'): network_action(args.wifi,args.token)
            elif args.wifi=='scan': print(nm('-f','IN-USE,SSID,SIGNAL,SECURITY','device','wifi','list'))
            elif args.wifi=='profiles': print(nm('-f','NAME,UUID,TYPE,AUTOCONNECT','connection','show'))
            else:
                print(nm('-f','GENERAL,IP4','device','show'))
                if os.geteuid()==0 and PENDING.exists(): output(load())
        elif cmd=='service':
            if args.action!='status':
                root()
                if args.name=='NetworkManager': raise RuntimeError('网络管理服务请在本地维护，不通过此命令停止/重启')
                if args.name=='robotd': raise RuntimeError('robotd 请通过 power on 准备；不要用重启命令代替卸力')
                print(run(['systemctl',args.action,args.name]));return 0
            result=subprocess.run(['systemctl','--no-pager','status',args.name]);return result.returncode
        elif cmd=='logs':
            if not 1<=args.n<=5000: raise ValueError('-n 范围为 1–5000')
            return subprocess.call(['journalctl','--no-pager','-u',args.name,'-n',str(args.n),*(['-f'] if args.follow else [])])
        elif cmd in ('status','imu','joints'):
            bus=rpc('robot.busStatus')
            if cmd=='status': output(bus)
            elif cmd=='joints': output((bus.get('native') or {}).get('joints') or (bus.get('last_sample') or {}).get('servos') or [])
            else:
                sample=(bus.get('last_sample') or {}).get('imu')
                native=bus.get('native') or {}
                state=state_sample() if bus.get('mode')=='motion' else {}
                output({'protocol':bus.get('imu_protocol'),'fresh':bus.get('fresh_sample'),
                        'imu':sample if sample is not None else state.get('imu'),
                        'gravity':(state.get('safety') or {}).get('gravity'),
                        'diagnostics':{k:v for k,v in native.items() if k.startswith('imu_')}})
        elif cmd=='policies': output(rpc('robot.policies'))
        elif cmd in ('relax','stop'):
            root()
            # Emergency neutral/relax is deliberately available despite another lease.
            if cmd=='relax': output(rpc('robot.relax'))
            else:
                output({'move':rpc('robot.move',{'vx':0,'vy':0,'vyaw':0}),
                        'sound':rpc('robot.sound',{'tag':'wheee','hold':False}),
                        'mouth':rpc('robot.mouth',{'open':0})})
        else:
            with control_lease():
                if cmd=='power':
                    print(run(['/bin/bash','/opt/robot/feetech-ft5-r5/service.sh','enable'],timeout=155))
                elif cmd=='stand':
                    policies=rpc('robot.policies')
                    output(rpc('robot.do',{'skill':'sit_toggle'}) if policies.get('sitting') is True else rpc('robot.init'))
                elif cmd=='policy': output(rpc('robot.enable',{'on':args.state=='on'}))
                elif cmd=='skill': output(rpc('robot.do',{'skill':args.name}))
                elif cmd=='sound': output(rpc('robot.sound',{'tag':'chirp'}))
        return 0
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as exc:
        print(f'duckctl: {exc}',file=sys.stderr);return 1


if __name__=='__main__':
    sys.exit(main())
