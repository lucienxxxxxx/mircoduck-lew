import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CameraController extends ChangeNotifier {
  MethodChannel? _channel;
  String state = 'idle', message = '连接后开启相机';
  String? _host;
  int _port = 8443, turns = 0;
  double? fps, mbps;
  int? loss;
  bool _ready = false, _disposed = false;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> attach(int id) async {
    _ready = false;
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('microduck.camera/$id');
    _channel!.setMethodCallHandler((call) async {
      if (call.method == 'event' && call.arguments is String) {
        try {
          event(jsonDecode(call.arguments as String) as Map<String, dynamic>);
        } on FormatException {
          /* Ignore malformed video diagnostics. */
        } on TypeError {/* Ignore malformed video diagnostics. */}
      }
    });
    if (await _channel!.invokeMethod<bool>('ready') == true) {
      event({'type': 'ready'});
    }
  }

  void event(Map<String, dynamic> data) {
    if (_disposed) return;
    if (data['type'] == 'ready') {
      if (_ready) return;
      _ready = true;
      _invoke('rotate', {'turns': turns});
      if (_host != null) _invoke('connect', {'host': _host, 'port': _port});
    } else if (data['type'] == 'state') {
      state = data['state'] as String? ?? 'error';
      message = data['message'] as String? ?? '';
      if (state != 'live') {
        fps = null;
        mbps = null;
        loss = null;
      }
    } else if (data['type'] == 'stats') {
      fps = (data['fps'] as num?)?.toDouble();
      mbps = (data['mbps'] as num?)?.toDouble();
      loss = (data['loss'] as num?)?.toInt();
    }
    changed();
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? fields]) async {
    if (!_ready || _channel == null) return;
    try {
      await _channel!.invokeMethod<void>(method, fields);
    } on PlatformException catch (e) {
      state = 'error';
      message = e.message ?? '相机连接失败';
      changed();
    } on MissingPluginException {
      /* Native view unavailable in desktop widget tests. */
    }
  }

  void connect(String host, int port) {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(host) ||
        port < 1 ||
        port > 65535) {
      throw const FormatException('请填写有效的相机地址和端口');
    }
    _host = host;
    _port = port;
    state = 'connecting';
    message = '正在连接相机';
    _invoke('connect', {'host': host, 'port': port});
    changed();
  }

  void rotate() {
    turns = (turns + 1) % 4;
    _invoke('rotate', {'turns': turns});
    changed();
  }

  void disconnect() {
    _host = null;
    _invoke('disconnect');
    state = 'idle';
    message = '相机未连接';
    fps = null;
    mbps = null;
    loss = null;
    changed();
  }

  @override
  void dispose() {
    disconnect();
    _disposed = true;
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}
