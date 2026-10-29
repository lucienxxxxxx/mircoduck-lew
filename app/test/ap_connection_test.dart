import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/services/ap_connection.dart';
import 'package:microduck_lew/services/robot_connection.dart';
import 'package:microduck_lew/services/wire.dart';

class Connection extends RobotConnection {
  final hosts = <String>[];
  @override
  Future<void> connect(String host, int port) async {
    hosts.add('$host:$port');
    link = LinkState.live;
  }

  @override
  Future<void> disconnect() async {
    link = LinkState.disconnected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('route parsing supports custom AP subnets without an SSID permission',
      () {
    expect(
        WifiRoute.from(
                {'connected': true, 'id': 'wifi1', 'gateway': '172.20.4.1'})
            ?.gateway,
        '172.20.4.1');
    for (final value in [
      null,
      {'connected': false},
      {'connected': true, 'id': '1', 'gateway': 'bad'},
      {'connected': true, 'id': '1', 'gateway': '0.0.0.0'}
    ]) {
      expect(WifiRoute.from(value), isNull);
    }
  });
  test(
      'UDP probe verifies service, nonce and ports without sending hello or frames',
      () async {
    final server =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final ops = <String>[];
    server.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = server.receive()) != null) {
        final m = decodePacket(d!.data);
        ops.add(m['op']);
        final response = {
          'v': 2,
          'op': 'discover',
          'nonce': m['nonce'],
          'service': 'mircoduck-lew',
          'control_port': 20043,
          'camera_port': 8443,
          'busy': false
        };
        server.send(
            encodePacket({...response, 'nonce': 'wrong'}), d.address, d.port);
        server.send(encodePacket({...response, 'service': 'router'}), d.address,
            d.port);
        server.send(
            encodePacket({...response, 'camera_port': 0}), d.address, d.port);
        server.send(encodePacket(response), d.address, d.port);
      }
    });
    try {
      final board = await discoverBoard('127.0.0.1', port: server.port);
      expect(board?.host, '127.0.0.1');
      expect(board?.cameraPort, 8443);
      expect(ops, isNotEmpty);
      expect(ops.every((op) => op == 'discover'), true);
    } finally {
      server.close();
    }
  });
  test('ordinary router timeout never establishes a control session', () async {
    final server =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      expect(
          await discoverBoard('127.0.0.1',
              port: server.port, timeout: const Duration(milliseconds: 30)),
          isNull);
    } finally {
      server.close();
    }
  });
  test(
      'AP connects automatically with returned ports; explicit disconnect stays disconnected',
      () async {
    final c = Connection();
    final found = <DiscoveredBoard>[];
    final ap = ApConnection(c,
        onConnected: found.add,
        onDisconnected: () {},
        probe: (host) async => DiscoveredBoard(host, 20044, 8444, false));
    try {
      await ap.networkChanged(const WifiRoute('wifi1', '172.20.4.1'));
      expect(c.hosts, ['172.20.4.1:20044']);
      expect(found.single.cameraPort, 8444);
      expect(c.acquired, false);
      expect(c.axes.values.every((v) => v == 0), true);
      ap.pauseForUser();
      await c.disconnect();
      await ap.attempt();
      expect(c.hosts.length, 1);
      await ap.networkChanged(const WifiRoute('wifi2', '10.42.0.1'));
      expect(c.hosts.last, '10.42.0.1:20044');
    } finally {
      ap.dispose();
      c.dispose();
    }
  });
  test('busy board does not displace another phone', () async {
    final c = Connection();
    final ap = ApConnection(c,
        onConnected: (_) => fail('must not connect'),
        onDisconnected: () {},
        probe: (host) async => DiscoveredBoard(host, 20043, 8443, true));
    try {
      await ap.networkChanged(const WifiRoute('1', '10.42.0.1'));
      expect(c.hosts, isEmpty);
    } finally {
      ap.dispose();
      c.dispose();
    }
  });
  test('late discovery from a previous network cannot connect to the old board',
      () async {
    final c = Connection();
    final old = Completer<DiscoveredBoard?>();
    final ap = ApConnection(c,
        onConnected: (_) {},
        onDisconnected: () {},
        probe: (host) => host == '10.42.0.1'
            ? old.future
            : Future.value(DiscoveredBoard(host, 20043, 8443, false)));
    try {
      final pending = ap.networkChanged(const WifiRoute('1', '10.42.0.1'));
      await ap.networkChanged(const WifiRoute('2', '172.20.4.1'));
      old.complete(const DiscoveredBoard('10.42.0.1', 20043, 8443, false));
      await pending;
      expect(c.hosts, isEmpty);
      await ap.attempt();
      expect(c.hosts, ['172.20.4.1:20043']);
    } finally {
      ap.dispose();
      c.dispose();
    }
  });
  test('backgrounding cancels pending automatic connection', () async {
    final c = Connection();
    final pending = Completer<DiscoveredBoard?>();
    final ap = ApConnection(c,
        onConnected: (_) => fail('background connect'),
        onDisconnected: () {},
        probe: (_) => pending.future);
    try {
      final changing = ap.networkChanged(const WifiRoute('1', '10.42.0.1'));
      await ap.foreground(false);
      pending.complete(const DiscoveredBoard('10.42.0.1', 20043, 8443, false));
      await changing;
      expect(c.hosts, isEmpty);
    } finally {
      ap.dispose();
      c.dispose();
    }
  });
}
