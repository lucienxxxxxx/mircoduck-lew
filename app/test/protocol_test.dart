import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/models/robot.dart';
import 'package:microduck_lew/services/wire.dart';

void main() {
  test('Dart packets match the Python keyless JSON golden vector', () {
    final fixture = jsonDecode(File('test/wire-golden.json').readAsStringSync())
        as Map<String, dynamic>;
    final message = Map<String, dynamic>.from(fixture['message']);
    expect(utf8.decode(encodePacket(message)), fixture['wire']);
    expect(decodePacket(utf8.encode(fixture['wire'])), message);
    expect(() => decodePacket(utf8.encode('{"v":1}')), throwsFormatException);
  });
  test('old envelopes and oversized messages are rejected', () {
    expect(() => decodePacket(utf8.encode('{"p":"old","h":"mac"}')),
        throwsFormatException);
    expect(
        () => encodePacket({'v': 2, 'p': 'x' * 2000}), throwsFormatException);
  });
  test('missing telemetry stays unknown and old status loses authorization',
      () {
    final state = RobotState();
    expect(state.fresh, isFalse);
    expect(state.hz, isNull);
    expect(state.roll, isNull);
    state.status({
      'fresh': true,
      'g': [0, 0, -1],
      'mode': 'commissioning'
    });
    expect(state.fresh, isTrue);
    expect(state.roll, 0);
    expect(state.pitch, 0);
    state.jointPacket({
      'rows': [
        [20, 0, 2048, 30, 7, 1, null, true, 10]
      ]
    });
    expect(state.jointFresh(20), true);
    expect(state.jointFresh(10), false);
    state.jointReceived[20] =
        DateTime.now().subtract(const Duration(milliseconds: 700));
    state.jointPacket({
      'rows': [
        [10, 0, 2048, 30, 7, 1, null, true, 10]
      ]
    });
    expect(state.jointFresh(20),
        false); // Other packet half cannot refresh this joint.
    expect(state.jointFresh(10), true);
    state.received = DateTime.now().subtract(const Duration(milliseconds: 700));
    expect(state.fresh, isFalse);
  });
}
