import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/services/robot_connection.dart';

void main() {
  final host = Platform.environment['MICRODUCK_TEST_HOST'];
  test(
      'optional live board: real Flutter client receives commissioning telemetry',
      () async {
    final client = RobotConnection();
    try {
      final key = File(Platform.environment['MICRODUCK_TEST_KEY_FILE']!)
          .readAsStringSync()
          .trim();
      await client.connect(host!, 20043, key);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(client.link, LinkState.live);
      expect(client.robot.mode, 'commissioning');
      expect(client.robot.torque, 'off');
      expect(client.robot.fresh, true);
      expect(client.robot.imuValid, true);
      expect(client.robot.joints.length, 15);
      expect(client.robot.joints.keys.every(client.robot.jointFresh), true);
      expect(client.acquired, false);
      await client.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await client.connect(host, 20043, key);
      expect(client.link, LinkState.live);
    } finally {
      await client.disconnect();
      client.dispose();
    }
  },
      skip: host == null
          ? 'Set explicit test host and a local pairing-key file'
          : false);
}
