import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/services/robot_connection.dart';
import 'package:microduck_lew/services/wire.dart';

void main() {
  test('timed-out previous connect cannot disconnect a newer connection',
      () async {
    final server =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final firstHello = Completer<void>();
    final client = RobotConnection();
    var seq = 0;
    server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = server.receive()) != null) {
        final message = decodePacket(d!.data);
        if (message['op'] == 'hello' && !firstHello.isCompleted) {
          firstHello.complete();
          continue; // Simulate a handshake lost on the previous Wi-Fi.
        }
        server.send(
            encodePacket({
              'v': 2,
              'op': message['op'] == 'hello' ? 'hello' : 'pong',
              'sid': message['sid'],
              'seq': ++seq,
              'ticket': 'current-ticket',
              'accepted': true
            }),
            d.address,
            d.port);
      }
    });
    Object? canceled;
    try {
      final old =
          client.connect('127.0.0.1', server.port).catchError((Object e) {
        canceled = e;
      });
      await firstHello.future.timeout(const Duration(seconds: 2));
      await client.connect('127.0.0.1', server.port);
      await old;
      expect(canceled, isA<TimeoutException>());
      expect(client.link, LinkState.live);
      expect(client.error, isNull);
    } finally {
      await client.disconnect();
      client.dispose();
      server.close();
    }
  });
  test(
      'real UDP socket connects without a key, claims explicitly, and clears stale input',
      () async {
    final server =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = RobotConnection();
    Datagram? endpoint;
    String sid = '';
    int sequence = 0, frames = 0;
    bool claimed = false, publishStatus = true;
    Map<String, dynamic>? lastFrame;
    void send(Map<String, dynamic> fields) {
      final to = endpoint;
      if (to == null) return;
      server.send(
          encodePacket({
            'v': 2,
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
        final m = decodePacket(d!.data);
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
            lastFrame = Map<String, dynamic>.from(m['frame']);
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
          'torque': true,
          'claimed': claimed
        });
      }
    });
    try {
      await client.connect('127.0.0.1', server.port);
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
      client.setDrive(.5, -.5, .65);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(lastFrame!['axes']['lx'],
          0); // Horizontal motion turns, without sideways movement.
      expect(lastFrame!['axes']['ly'], -.325);
      expect(lastFrame!['axes']['rx'], .325);
      await client.startLongCall();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(lastFrame!['axes']['lt'], 1);
      client.endLongCall();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(lastFrame!['axes']['lt'], 0);
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
