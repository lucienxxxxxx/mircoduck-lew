import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/services/robot_connection.dart';
import 'package:microduck_lew/services/wire.dart';

void main() {
  test(
      'real UDP socket authenticates, claims explicitly, and clears stale input',
      () async {
    final key = List<int>.generate(32, (i) => i);
    final server =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = RobotConnection();
    Datagram? endpoint;
    String sid = '';
    int sequence = 0, frames = 0;
    bool claimed = false, publishStatus = true;
    void send(Map<String, dynamic> fields) {
      final to = endpoint;
      if (to == null) return;
      server.send(
          encodePacket(key, {
            'v': 1,
            'sid': sid,
            'seq': ++sequence,
            'ticket': 'test-ticket',
            ...fields
          }),
          to.address,
          to.port);
    }

    server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = server.receive()) != null) {
        final m = decodePacket(key, d!.data);
        endpoint = d;
        sid = m['sid'];
        switch (m['op']) {
          case 'hello':
            send({'op': 'hello', 'accepted': true});
          case 'claim':
            claimed = true;
            send({
              'op': 'ack',
              'reply': m['seq'],
              'accepted': true,
              'claimed': true
            });
          case 'frame':
            frames++;
          case 'release':
            claimed = false;
            send({
              'op': 'ack',
              'reply': m['seq'],
              'accepted': true,
              'claimed': false
            });
          case 'ping':
            send({'op': 'pong', 'claimed': claimed});
        }
      }
    });
    final timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (publishStatus) {
        send({
          'op': 'status',
          'fresh': true,
          'mode': 'motion',
          'homed': true,
          'policy': true,
          'claimed': claimed
        });
      }
    });
    try {
      await client.connect('127.0.0.1', server.port,
          key.map((v) => v.toRadixString(16).padLeft(2, '0')).join());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(client.canOperate, true);
      expect(client.acquired, false);
      expect(frames, 0);
      await client.claim();
      expect(client.canDrive, true);
      client.setStick(true, .5, -.5, .25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(frames, greaterThan(1));
      expect(client.axes['ly'], -.125);
      publishStatus =
          false; // Pongs still arrive; stale robot feedback must release input.
      await Future<void>.delayed(const Duration(milliseconds: 760));
      expect(client.canOperate, false);
      expect(client.acquired, false);
      expect(client.axes.values.every((v) => v == 0), true);
    } finally {
      timer.cancel();
      await client.disconnect();
      client.dispose();
      server.close();
    }
  });
}
