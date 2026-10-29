import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'robot_connection.dart';
import 'wire.dart';

class WifiRoute {
  final String id, gateway;
  const WifiRoute(this.id, this.gateway);
  String get key => '$id/$gateway';
  static WifiRoute? from(dynamic value) {
    if (value is! Map ||
        value['connected'] != true ||
        value['id'] is! String ||
        value['gateway'] is! String) {
      return null;
    }
    final ip = InternetAddress.tryParse(value['gateway']);
    if (ip == null ||
        ip.type != InternetAddressType.IPv4 ||
        ip.isLoopback ||
        ip.address == '0.0.0.0') {
      return null;
    }
    return WifiRoute(value['id'], ip.address);
  }
}

class DiscoveredBoard {
  final String host;
  final int controlPort, cameraPort;
  final bool busy;
  const DiscoveredBoard(
      this.host, this.controlPort, this.cameraPort, this.busy);
}

Future<DiscoveredBoard?> discoverBoard(String gateway,
    {int port = 20043,
    Duration timeout = const Duration(milliseconds: 800)}) async {
  final address = InternetAddress.tryParse(gateway);
  if (address == null || address.type != InternetAddressType.IPv4) return null;
  final nonce = List.generate(16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
  final peer = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final result = Completer<DiscoveredBoard?>();
  final wire = encodePacket({'v': 2, 'op': 'discover', 'nonce': nonce});
  void send() {
    try {
      peer.send(wire, address, port);
    } on SocketException {
      if (!result.isCompleted) result.complete(null);
    }
  }

  final subscription = peer.listen((event) {
    if (event != RawSocketEvent.read) return;
    Datagram? d;
    while ((d = peer.receive()) != null) {
      if (d!.address.address != address.address || d.port != port) continue;
      try {
        final m = decodePacket(d.data);
        bool validPort(dynamic v) => v is int && v >= 1 && v <= 65535;
        if (m['op'] != 'discover' ||
            m['service'] != 'mircoduck-lew' ||
            m['nonce'] != nonce ||
            !validPort(m['control_port']) ||
            !validPort(m['camera_port']) ||
            m['busy'] is! bool) {
          continue;
        }
        if (!result.isCompleted) {
          result.complete(DiscoveredBoard(
              address.address, m['control_port'], m['camera_port'], m['busy']));
        }
      } on FormatException {/* Ignore unrelated gateway responses. */}
    }
  }, onError: (Object _) {
    if (!result.isCompleted) result.complete(null);
  });
  final retry =
      Timer.periodic(const Duration(milliseconds: 250), (_) => send());
  try {
    send();
    return await result.future.timeout(timeout, onTimeout: () => null);
  } finally {
    retry.cancel();
    await subscription.cancel();
    peer.close();
  }
}

/// Foreground-only connection orchestration. Never claims input or restores axes.
class ApConnection extends ChangeNotifier {
  ApConnection(this.connection,
      {required this.onConnected,
      required this.onDisconnected,
      Future<DiscoveredBoard?> Function(String)? probe,
      this.retryInterval = const Duration(seconds: 3)})
      : probe = probe ?? discoverBoard;
  final RobotConnection connection;
  final void Function(DiscoveredBoard) onConnected;
  final VoidCallback onDisconnected;
  final Future<DiscoveredBoard?> Function(String) probe;
  final Duration retryInterval;
  static const channel = MethodChannel('microduck.wifi');
  WifiRoute? _route;
  Timer? _retry;
  bool _probing = false, _active = true, _paused = false, _disposed = false;
  int _epoch = 0;
  String message = '连接鸭子热点后自动连接';

  void _message(String value) {
    if (_disposed || message == value) return;
    message = value;
    notifyListeners();
  }

  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') {
        await networkChanged(WifiRoute.from(call.arguments));
      }
    });
    _retry = Timer.periodic(retryInterval, (_) => attempt());
    await refresh();
  }

  Future<void> refresh() async {
    try {
      await networkChanged(
          WifiRoute.from(await channel.invokeMethod<dynamic>('snapshot')));
    } on MissingPluginException {
      /* Android bridge unavailable in desktop tests. */
    } on PlatformException {
      _message('Wi-Fi 检测暂不可用，可手动连接');
    }
  }

  Future<void> networkChanged(WifiRoute? next) async {
    if (_disposed || next?.key == _route?.key) return;
    final previous = _route;
    _route = next;
    _paused = false;
    final epoch = ++_epoch;
    if (previous != null) {
      connection.stop();
      await connection.disconnect();
      if (!_disposed) onDisconnected();
    }
    if (_disposed || epoch != _epoch) return;
    _message(next == null ? '连接鸭子热点后自动连接' : '正在识别鸭子热点');
    await attempt();
  }

  void pauseForUser() {
    _paused = true;
    ++_epoch;
    _message('自动连接已暂停；切换热点后恢复');
  }

  Future<void> foreground(bool active) async {
    _active = active;
    if (!active) {
      ++_epoch;
      connection.stop();
      if (connection.link == LinkState.connecting) {
        await connection.disconnect();
      } else {
        await connection.release().catchError((Object _) {});
      }
      if (!_disposed) onDisconnected();
    } else {
      await refresh();
      await attempt();
    }
  }

  Future<void> attempt() async {
    final route = _route;
    if (_disposed ||
        !_active ||
        _paused ||
        _probing ||
        route == null ||
        connection.link != LinkState.disconnected) {
      return;
    }
    _probing = true;
    final epoch = _epoch;
    try {
      final board = await probe(route.gateway);
      if (_disposed || epoch != _epoch || !_active || _paused) return;
      if (board == null) {
        _message('未发现鸭子热点，可手动填写地址');
        return;
      }
      if (board.busy) {
        _message('鸭子已有连接，等待可用');
        return;
      }
      _message('已发现鸭子，正在连接');
      await connection.connect(board.host, board.controlPort);
      if (_disposed || epoch != _epoch || !_active || _paused) return;
      onConnected(board);
      _message('已自动连接鸭子热点');
    } on Exception {
      _message('自动连接重试中，可手动连接');
    } finally {
      _probing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _retry?.cancel();
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
