import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/services/robot_connection.dart';

void main() {
  final host = Platform.environment['MICRODUCK_TEST_HOST'];
  test(
      'optional live board: real Flutter client receives fresh telemetry without a pairing key',
      () async {
    final client = RobotConnection();
    try {
      await client.connect(host!, 20043);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(client.link, LinkState.live);
      if (Platform.environment['MICRODUCK_TEST_POWER'] == '1') {
        await client.powerOn();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(client.robot.mode, 'motion');
        expect(client.robot.torque, false);
      } else {
        expect(['commissioning', 'motion'], contains(client.robot.mode));
        expect(client.robot.torque, isNotNull);
      }
      expect(client.robot.fresh, true);
      expect(client.robot.imuValid, true);
      expect(client.robot.joints.length, 15);
      expect(client.robot.joints.keys.every(client.robot.jointFresh), true);
      expect(client.acquired, false);
      await client.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await client.connect(host, 20043);
      expect(client.link, LinkState.live);
    } finally {
      await client.disconnect();
      client.dispose();
    }
  },
      skip: host == null ? 'Set explicit test host' : false,
      timeout: const Timeout(Duration(seconds: 180)));
}
