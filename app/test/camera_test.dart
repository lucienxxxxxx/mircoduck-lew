import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/services/camera_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'video view ready handshake survives an early event and rotates without reconnecting',
      () async {
    const channel = MethodChannel('microduck.camera/42');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'ready' ? true : null;
    });
    final camera = CameraController();
    try {
      camera.connect('robot.local', 8443);
      await camera.attach(42);
      camera.event({
        'type': 'ready'
      }); // Duplicated late ready cannot create a second video session.
      for (var i = 0; i < 4; i++) {
        camera.rotate();
      }
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'connect').length, 1);
      expect(
          calls
              .where((c) => c.method == 'rotate')
              .map((c) => c.arguments['turns']),
          [0, 1, 2, 3, 0]);
      camera.event({'type': 'state', 'state': 'live', 'message': 'live'});
      camera.event({'type': 'stats', 'fps': 30, 'mbps': 3.5, 'loss': 0});
      expect(camera.fps, 30);
      camera.event(
          {'type': 'state', 'state': 'error', 'message': 'connection lost'});
      expect(camera.fps, isNull);
      camera.disconnect();
      expect(camera.state, 'idle');
    } finally {
      camera.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
