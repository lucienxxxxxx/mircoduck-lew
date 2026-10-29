import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/robot.dart';
import 'wire.dart';

enum LinkState { disconnected, connecting, live }

class RobotConnection extends ChangeNotifier {
  RobotState robot = RobotState();
  LinkState link = LinkState.disconnected;
  bool acquired = false;
  String? error;
  final List<String> logs = [];
  RawDatagramSocket? _socket;
  InternetAddress? _address;
  int _port = 20043, _seq = 0, _receiveSeq = -1, _generation = 0;
  int _ticks = 0;
  String _sid = '', _ticket = '';
  Timer? _ticker;
  DateTime? _lastPacket, _ticketAt;
  Completer<void>? _hello;
  final Map<int, Completer<void>> _pending = {};
  final Map<String, double> axes = {
    for (final k in ['lx', 'ly', 'rx', 'ry', 'lt', 'rt', 'dx', 'dy']) k: 0,
  };
  final Set<String> buttons = {};
  bool _disposed = false;
  int _driveEpoch = 0, _callEpoch = 0;
  bool _preparingDrive = false;
  double _wantedX = 0, _wantedY = 0;
  bool get canStartDrive =>
      canOperate &&
      robot.mode == 'motion' &&
      robot.homed &&
      robot.torque == true &&
      robot.sitting != true;
  bool get canOperate =>
      link == LinkState.live && robot.fresh && !robot.realGamepad;
  bool get canDrive =>
      canOperate &&
      acquired &&
      robot.mode == 'motion' &&
      robot.homed &&
      (robot.inputMode != 'drive' || robot.policy);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void log(String message) {
    logs.insert(0, message);
    if (logs.length > 100) logs.removeLast();
    changed();
  }

  Future<void> connect(String host, int port) async {
    if (host.trim().isEmpty || port < 1 || port > 65535) {
      throw const FormatException('请填写主板地址和 UDP 端口');
    }
    await disconnect();
    final generation = ++_generation;
    link = LinkState.connecting;
    error = null;
    robot = RobotState();
    changed();
    try {
      final addresses = await InternetAddress.lookup(
        host.trim(),
        type: InternetAddressType.IPv4,
      );
      if (generation != _generation) return;
      _address = addresses.first;
      _port = port;
      _sid = List.generate(
        16,
        (_) =>
            math.Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _seq = 0;
      _receiveSeq = -1;
      _ticket = '';
      _ticketAt = null;
      final peer = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (generation != _generation) {
        peer.close();
        return;
      }
      _socket = peer;
      peer.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            Datagram? d;
            while ((d = peer.receive()) != null) {
              _receive(d!);
            }
          }
        },
        onError: (Object e) {
          if (generation == _generation) {
            error = '$e';
            unawaited(disconnect());
          }
        },
      );
      _hello = Completer<void>();
      _send('hello', allowWithoutTicket: true);
      await _hello!.future.timeout(const Duration(seconds: 3));
      if (generation != _generation) return;
      link = LinkState.live;
      _ticker = Timer.periodic(const Duration(milliseconds: 20), (_) => tick());
      log('已连接 · UDP $_port');
    } catch (e) {
      await disconnect();
      error = '$e';
      changed();
      rethrow;
    }
  }

  void _receive(Datagram d) {
    if (d.address.address != _address?.address || d.port != _port) return;
    try {
      final m = decodePacket(d.data);
      final sequence = m['seq'];
      if (m['sid'] != _sid || sequence is! int || sequence <= _receiveSeq) {
        return;
      }
      _receiveSeq = sequence;
      _lastPacket = DateTime.now();
      if (m['ticket'] is String) {
        _ticket = m['ticket'];
        _ticketAt = DateTime.now();
      }
      final op = m['op'];
      if (op == 'hello' &&
          m['accepted'] == true &&
          !(_hello?.isCompleted ?? true)) {
        _hello!.complete();
      }
      if (m['claimed'] == false) {
        acquired = false;
        _clearAxes();
      }
      if (op == 'status') {
        robot.status(m);
        if (!robot.fresh || robot.realGamepad) {
          stop();
          acquired = false;
        } else if (!canStartDrive) {
          ++_driveEpoch;
          _wantedX = _wantedY = 0;
          axes['lx'] = axes['ly'] = axes['rx'] = axes['ry'] = 0;
        }
      }
      if (op == 'joints') robot.jointPacket(m);
      if (op == 'ack') {
        final pending = _pending.remove(m['reply']);
        if (pending != null && !pending.isCompleted) {
          if (m['accepted'] == true) {
            error = null;
            acquired = m['claimed'] == true;
            pending.complete();
          } else {
            pending.completeError(
              StateError(m['reason'] as String? ?? '指令被拒绝'),
            );
          }
        }
      }
      if (op == 'error') {
        error = m['reason'] as String? ?? '指令被拒绝';
        final pending = _pending.remove(m['reply']);
        if (pending != null && !pending.isCompleted) {
          pending.completeError(StateError(error!));
        }
        log(error!);
      }
      changed();
    } on FormatException {
      /* Ignore malformed network traffic. */
    } on TypeError {
      /* A malformed status must not break the receive loop. */
    }
  }

  int _send(
    String op, {
    Map<String, dynamic> fields = const {},
    bool allowWithoutTicket = false,
  }) {
    final peer = _socket, address = _address;
    if (peer == null || address == null) return -1;
    if (!allowWithoutTicket &&
        (_ticket.isEmpty ||
            _ticketAt == null ||
            DateTime.now().difference(_ticketAt!).inMilliseconds > 450)) {
      return -1;
    }
    final sequence = ++_seq;
    peer.send(
      encodePacket({
        'v': 2,
        'sid': _sid,
        'seq': sequence,
        'op': op,
        if (!allowWithoutTicket) 'ticket': _ticket,
        ...fields,
      }),
      address,
      _port,
    );
    return sequence;
  }

  Future<void> request(
    String op, {
    Map<String, dynamic> fields = const {},
  }) async {
    final sequence = _send(op, fields: fields);
    if (sequence < 0) throw StateError('连接或票据已过期，请重新连接');
    final pending = Completer<void>();
    _pending[sequence] = pending;
    try {
      await pending.future.timeout(const Duration(milliseconds: 900));
    } finally {
      _pending.remove(sequence);
    }
  }

  void tick() {
    final now = DateTime.now();
    if (!robot.fresh && acquired) {
      stop();
      acquired = false;
      _send('release');
    }
    if (_lastPacket == null ||
        now.difference(_lastPacket!).inMilliseconds > 700) {
      acquired = false;
      _clearAxes();
      robot.serverFresh = false;
      changed();
    }
    if (_lastPacket != null && now.difference(_lastPacket!).inSeconds >= 3) {
      error = 'UDP 连接已断开；请重新连接';
      unawaited(disconnect());
      return;
    }
    if (acquired && canOperate) {
      _send(
        'frame',
        fields: {
          'frame': {'axes': axes, 'buttons': buttons.toList()},
        },
      );
    } else if (++_ticks % 5 == 0) {
      _send('ping');
    }
    changed();
  }

  void _clearAxes() {
    for (final k in axes.keys) {
      axes[k] = 0;
    }
    buttons.clear();
  }

  void stop() {
    ++_driveEpoch;
    ++_callEpoch;
    _wantedX = _wantedY = 0;
    _clearAxes();
    if (acquired) {
      _send(
        'frame',
        fields: {
          'frame': {'axes': axes, 'buttons': <String>[]},
        },
      );
    }
    changed();
  }

  Future<void> claim() async {
    if (!canOperate) throw StateError('等待新鲜反馈，或请先断开实体手柄');
    await request('claim');
  }

  Future<void> release() async {
    stop();
    acquired = false;
    try {
      await request('release');
    } finally {
      changed();
    }
  }

  Future<void> action(String action) async {
    if (!canOperate || !acquired) throw StateError('控制暂未就绪，请重新操作');
    stop();
    await request('action', fields: {'action': action});
    if (action == 'motion' || action == 'commissioning' || action == 'relax') {
      acquired = false;
    }
    log('请求已接受：$action；以实时状态为准');
  }

  Future<void> ensureInput() async {
    if (!canOperate) {
      throw StateError(robot.realGamepad ? '实体手柄正在使用' : '等待实时反馈');
    }
    if (!acquired) await claim();
  }

  Future<void> powerOn() async {
    if (robot.mode == 'motion' && robot.fresh) return;
    robot.modeJob = '';
    await ensureInput();
    await action('motion');
    final deadline = DateTime.now().add(const Duration(seconds: 155));
    while (DateTime.now().isBefore(deadline)) {
      if (link != LinkState.live) throw StateError('连接中断，上电结果待确认');
      if (robot.mode == 'motion' && robot.fresh) return;
      if (robot.modeJob.startsWith('服务切换失败')) throw StateError(robot.modeJob);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('上电等待超时，请检查主板状态');
  }

  Future<void> stand() async {
    if (robot.mode != 'motion') throw StateError('请先上电');
    if (robot.sitting == true) {
      await runSkill('sit_toggle');
      return;
    }
    await ensureInput();
    await action('home');
  }

  Future<void> enableMovement() async {
    if (!canStartDrive && robot.sitting != true) {
      throw StateError('请先站立并等待实时反馈');
    }
    await ensureInput();
    if (!robot.policy) {
      await request('action', fields: {'action': 'policy-on'});
      final end = DateTime.now().add(const Duration(seconds: 2));
      while (!robot.policy && DateTime.now().isBefore(end)) {
        if (!canOperate) throw StateError('反馈中断');
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      if (!robot.policy) throw StateError('运动尚未就绪');
    }
  }

  Future<void> runSkill(String name) async {
    stop();
    if (!robot.homed) throw StateError('请先站立');
    await enableMovement();
    await action(name);
  }

  void setDrive(double x, double y, double scale) {
    _wantedX = x * scale;
    _wantedY = y * scale;
    if (x == 0 && y == 0) {
      ++_driveEpoch;
      axes['lx'] = axes['ly'] = axes['rx'] = axes['ry'] = 0;
      if (acquired) {
        _send('frame', fields: {
          'frame': {'axes': axes, 'buttons': buttons.toList()}
        });
      }
      return;
    }
    if (!canStartDrive) return;
    if (canDrive) {
      _applyDrive();
      return;
    }
    if (_preparingDrive) return;
    _preparingDrive = true;
    final epoch = _driveEpoch;
    () async {
      try {
        await enableMovement();
        if (epoch == _driveEpoch && canDrive) _applyDrive();
      } catch (e) {
        error = '$e';
        stop();
        log(error!);
      } finally {
        _preparingDrive = false;
      }
    }();
  }

  void _applyDrive() {
    axes['lx'] = 0;
    axes['ly'] = _wantedY;
    axes['rx'] = _wantedX;
    axes['ry'] = 0;
  }

  Future<void> shortCall() async {
    await ensureInput();
    await request('action', fields: {'action': 'chirp'});
  }

  Future<void> startLongCall() async {
    final epoch = ++_callEpoch;
    await ensureInput();
    if (epoch == _callEpoch) axisButton('lt', true);
  }

  void endLongCall() {
    ++_callEpoch;
    axisButton('lt', false);
  }

  void setStick(bool left, double x, double y, double scale) {
    if (!canDrive) return;
    axes[left ? 'lx' : 'rx'] = x * scale;
    axes[left ? 'ly' : 'ry'] = y * scale;
  }

  void button(String name, bool down) {
    if (!canOperate || !acquired) return;
    if (down) {
      buttons.add(name);
    } else {
      buttons.remove(name);
    }
    _send(
      'frame',
      fields: {
        'frame': {'axes': axes, 'buttons': buttons.toList()},
      },
    );
  }

  void axisButton(String name, bool down) {
    if (!canOperate || !acquired || !['lt', 'rt', 'dy'].contains(name)) return;
    axes[name] = down ? 1 : 0;
    _send('frame', fields: {
      'frame': {'axes': axes, 'buttons': buttons.toList()}
    });
  }

  Future<void> disconnect() async {
    ++_generation;
    _ticker?.cancel();
    _ticker = null;
    if (_socket != null && _ticket.isNotEmpty) {
      _send('release', fields: {'disconnect': true});
    }
    _socket?.close();
    _socket = null;
    _clearAxes();
    acquired = false;
    link = LinkState.disconnected;
    robot.serverFresh = false;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.completeError(StateError('已断开连接'));
    }
    _pending.clear();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
