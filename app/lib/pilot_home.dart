import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models/robot.dart';
import 'services/robot_connection.dart';
import 'services/camera_controller.dart';
import 'widgets/camera_backdrop.dart';
import 'widgets/phone_stick.dart';
import 'widgets/style.dart';

class PhoneHome extends StatefulWidget {
  final RobotConnection? connection;
  final CameraController? camera;
  const PhoneHome({super.key, this.connection, this.camera});
  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> with WidgetsBindingObserver {
  late final c = widget.connection ?? RobotConnection();
  late final camera = widget.camera ?? CameraController();
  final scaffold = GlobalKey<ScaffoldState>();
  final host = TextEditingController(text: 'microduck.local');
  final port = TextEditingController(text: '20043');
  final cameraPort = TextEditingController(text: '8443');
  int gear = 0;
  bool busy = false;
  double get speed => [.35, .65, 1.0][gear];
  bool get connected => c.link == LinkState.live;
  bool get ready => c.canOperate && c.robot.mode == 'motion';
  String number(double? v, [int digits = 1]) =>
      v?.toStringAsFixed(digits) ?? '—';
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    camera.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      c.stop();
      unawaited(c.release().catchError((Object _) {}));
      camera.disconnect();
    } else if (connected) {
      connectCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(changed);
    camera.removeListener(changed);
    if (widget.connection == null) c.dispose();
    if (widget.camera == null) camera.dispose();
    host.dispose();
    port.dispose();
    cameraPort.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    c.stop();
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void connectCamera() {
    try {
      camera.connect(host.text.trim(), int.tryParse(cameraPort.text) ?? 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> connect() async {
    final videoPort = int.tryParse(cameraPort.text) ?? 0;
    if (videoPort < 1 || videoPort > 65535) {
      throw const FormatException('相机端口无效');
    }
    await c.connect(host.text.trim(), int.tryParse(port.text) ?? 0);
    connectCamera();
    if (mounted) Navigator.pop(context);
  }

  Future<void> power() async {
    if (c.robot.torque == true) {
      c.stop();
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('卸力'),
                  content: const Text('释放舵机扭矩，主板继续运行。请先放稳或支撑好机器人。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('确认卸力'))
                  ]));
      if (confirmed == true) {
        await c.ensureInput();
        await c.action('relax');
      }
    } else {
      await c.powerOn();
    }
  }

  String get robotLabel {
    if (!connected) return c.link == LinkState.connecting ? '连接中' : '未连接';
    if (busy && c.robot.mode != 'motion') return '上电中';
    if (!c.robot.fresh) return '反馈更新中';
    if (c.robot.realGamepad) return '实体手柄正在使用';
    if (c.robot.mode != 'motion') return '待上电';
    if (c.robot.sitting == true) return '坐下';
    if (c.robot.homed && c.robot.torque == true) return '站立';
    return '待站立';
  }

  Widget glass(Widget child,
          {double radius = 20, EdgeInsets padding = const EdgeInsets.all(8)}) =>
      Container(
          padding: padding,
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: .13))),
          child: child);
  @override
  Widget build(BuildContext context) => Scaffold(
        key: scaffold,
        resizeToAvoidBottomInset: false,
        onEndDrawerChanged: (open) {
          if (open) {
            c.stop();
            unawaited(c.release().catchError((Object _) {}));
          }
        },
        endDrawer: Drawer(
            width: math.min(400, MediaQuery.sizeOf(context).width * .8),
            child: SafeArea(
                child: Padding(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom),
                    child: settings()))),
        body: Stack(fit: StackFit.expand, children: [
          CameraBackdrop(controller: camera),
          const IgnorePointer(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Expanded(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                  Colors.black87,
                  Colors.transparent
                ])))),
                Spacer(),
                Expanded(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black87]))))
              ])),
          SafeArea(child: LayoutBuilder(builder: (context, box) {
            final side = math.min(210.0, box.maxWidth * .25);
            final stick =
                math.min(side - 12, math.max(96.0, box.maxHeight - 204));
            return Stack(children: [
              Positioned(
                  top: 8, left: 12, right: 12, height: 44, child: header()),
              Positioned(
                  left: 10,
                  top: 60,
                  bottom: 20,
                  width: side,
                  child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: stick,
                        height: stick,
                        child: PhoneStick(
                            key: const Key('left-stick'),
                            label: '前进后退与左右转向',
                            enabled: !busy && c.canStartDrive,
                            onChanged: (v) => c.setDrive(v.dx, v.dy, speed))),
                    const SizedBox(height: 4),
                    const Text('前后 · 转向',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 8),
                    glass(
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          for (var i = 0; i < 3; i++)
                            SizedBox(
                                width: 46,
                                height: 34,
                                child: TextButton(
                                    key: Key('gear-$i'),
                                    style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        foregroundColor: gear == i
                                            ? Colors.black
                                            : Colors.white70,
                                        backgroundColor: gear == i
                                            ? cyan
                                            : Colors.transparent),
                                    onPressed: () {
                                      c.stop();
                                      setState(() => gear = i);
                                    },
                                    child: Text(['慢', '中', '快'][i])))
                        ]),
                        padding: const EdgeInsets.all(4)),
                  ]))),
              Positioned(
                  right: 12,
                  top: 60,
                  bottom: 76,
                  width: math.min(178, side),
                  child: Center(child: rightKeys())),
              Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                      child: SizedBox(
                          width: math.min(440, box.maxWidth * .48),
                          height: 60,
                          child: actionsPanel()))),
            ]);
          })),
        ]),
      );

  Widget header() => Row(children: [
        Image.asset('assets/duck-head-controller.png',
            width: 44, height: 42, fit: BoxFit.contain),
        const SizedBox(width: 6),
        const Text('DuckPilot',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(
            child: Center(
                child: glass(
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle,
                          size: 7,
                          color: connected && c.robot.fresh ? cyan : orange),
                      const SizedBox(width: 6),
                      Flexible(
                          child: Text(robotLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11))),
                      const SizedBox(width: 10),
                      Flexible(
                          child: Text(
                              camera.state == 'live'
                                  ? '${number(camera.fps, 0)} FPS · ${number(camera.mbps)} Mb/s'
                                  : camera.state == 'connecting'
                                      ? '相机连接中'
                                      : '相机未连接',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.white60))),
                    ]),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9)))),
        const SizedBox(width: 6),
        icon(Icons.rotate_90_degrees_cw, '旋转画面', () => camera.rotate()),
        icon(Icons.info_outline, '参数', telemetry),
        glass(
            TextButton(
                style: TextButton.styleFrom(
                    minimumSize: const Size(58, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: busy
                    ? null
                    : () {
                        if (connected) {
                          camera.disconnect();
                          unawaited(perform(c.disconnect));
                        } else {
                          scaffold.currentState!.openEndDrawer();
                        }
                      },
                child: Text(connected ? '断开' : '连接',
                    style: const TextStyle(fontSize: 12))),
            padding: EdgeInsets.zero),
        icon(Icons.settings_outlined, '连接设置',
            () => scaffold.currentState!.openEndDrawer()),
      ]);
  Widget icon(IconData symbol, String title, VoidCallback action) => IconButton(
      tooltip: title,
      onPressed: action,
      icon: Icon(symbol, size: 21, color: Colors.white70));

  Widget rightKeys() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: keyButton(
                  Icons.power_settings_new,
                  c.robot.torque == true
                      ? '卸力'
                      : c.robot.mode == 'motion'
                          ? '已就绪'
                          : '上电',
                  !busy &&
                          c.canOperate &&
                          (c.robot.mode != 'motion' || c.robot.torque == true)
                      ? () => perform(power)
                      : null)),
          const SizedBox(width: 8),
          Expanded(
              child: keyButton(Icons.accessibility_new, '站立',
                  !busy && ready ? () => perform(c.stand) : null))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: keyButton(Icons.volume_up_outlined, '短叫',
                  !busy && ready ? () => perform(c.shortCall) : null)),
          const SizedBox(width: 8),
          Expanded(
              child: Listener(
                  onPointerDown: !busy && ready
                      ? (_) =>
                          unawaited(c.startLongCall().catchError((Object e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }))
                      : null,
                  onPointerUp: (_) => c.endLongCall(),
                  onPointerCancel: (_) => c.endLongCall(),
                  child: keyButton(Icons.graphic_eq, '长叫', null,
                      held: (c.axes['lt'] ?? 0) > 0,
                      available: !busy && ready)))
        ]),
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEE6572),
                    foregroundColor: Colors.black),
                onPressed: () {
                  c.stop();
                  if (connected) {
                    unawaited(c.release().catchError((Object _) {}));
                  }
                },
                icon: const Icon(Icons.stop_circle_outlined, size: 19),
                label: const Text('停止'))),
      ]);
  Widget keyButton(IconData symbol, String label, VoidCallback? action,
          {bool held = false, bool? available}) =>
      Semantics(
          button: true,
          enabled: available ?? action != null,
          label: label,
          child: Material(
              color: held
                  ? cyan.withValues(alpha: .35)
                  : Colors.black.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                  onTap: action,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: held
                                  ? cyan
                                  : Colors.white.withValues(alpha: .16))),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(symbol,
                                size: 22,
                                color: (available ?? action != null)
                                    ? Colors.white
                                    : Colors.white30),
                            const SizedBox(height: 3),
                            Text(label,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: (available ?? action != null)
                                        ? Colors.white
                                        : Colors.white30)),
                          ])))));

  Widget actionsPanel() => glass(
      ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          children: [
            actionCard('前滚', Icons.rotate_right, 'roulade'),
            actionCard(
                c.robot.sitting == true
                    ? '站起'
                    : c.robot.sitting == false
                        ? '坐下'
                        : '坐下 / 站起',
                Icons.airline_seat_recline_normal,
                'sit_toggle'),
            actionCard('捡拾', Icons.south, 'ground_pick'),
            actionCard('左踢', Icons.sports_soccer, 'kick_left'),
            actionCard('右踢', Icons.sports_soccer, 'kick_right'),
          ]),
      radius: 22,
      padding: const EdgeInsets.all(5));
  Widget actionCard(String label, IconData symbol, String skill) {
    final available =
        !busy && ready && c.robot.homed && c.robot.skills.contains(skill);
    return SizedBox(
        width: 94,
        child: TextButton(
            onPressed:
                available ? () => perform(() => c.runSkill(skill)) : null,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                foregroundColor: Colors.white),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(symbol, size: 18),
              const SizedBox(width: 5),
              Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)))
            ])));
  }

  void telemetry() {
    c.stop();
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .76,
                child: AnimatedBuilder(
                    animation: c,
                    builder: (context, _) =>
                        ListView(padding: const EdgeInsets.all(18), children: [
                          Text(
                              '$robotLabel · ${number(c.robot.hz, 0)} Hz · ${number(c.robot.age, 0)} ms',
                              style: const TextStyle(color: cyan)),
                          const SizedBox(height: 8),
                          Text('相机：${camera.message}'),
                          Text(
                              '画面旋转 ${camera.turns * 90}° · 丢包 ${camera.loss ?? '—'}'),
                          TextButton(
                              onPressed: connected
                                  ? () {
                                      connectCamera();
                                      Navigator.pop(ctx);
                                    }
                                  : null,
                              child: const Text('重连相机')),
                          const Divider(),
                          Text(
                              'IMU200 · ${c.robot.fresh && c.robot.imuValid == true ? '有效' : '待更新'} · 序号 ${c.robot.imuSequence ?? '—'}'),
                          Text(
                              '侧倾 ${number(c.robot.roll)}° · 俯仰 ${number(c.robot.pitch)}°'),
                          Text(
                              '角速度 rad/s：${c.robot.gyro?.map((v) => v.toStringAsFixed(3)).join(' / ') ?? '—'}'),
                          const Divider(),
                          const Text('关节反馈 · 电流为原始计数'),
                          for (final id in jointNames.keys)
                            Builder(builder: (context) {
                              final j = c.robot.jointFresh(id)
                                  ? c.robot.joints[id]
                                  : null;
                              return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                      '$id · ${jointNames[id]}${j == null ? ' · 待更新' : ''}'),
                                  subtitle: Text(
                                      '${number(j?.degrees)}° · 编码器 ${number(j?.raw, 0)} · ${number(j?.temperature)}℃'),
                                  trailing: Text(
                                      '${number(j?.voltage)} V\nraw ${number(j?.currentRaw, 0)}',
                                      style: const TextStyle(fontSize: 11)));
                            }),
                        ])))));
  }

  Widget settings() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('连接 Microduck',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        TextField(
            controller: host,
            decoration: const InputDecoration(labelText: '主板 IP / 主机名')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '控制端口'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: cameraPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '相机端口')))
        ]),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: busy ? null : () => perform(connect),
            child: Text(busy ? '连接中…' : '连接')),
        const SizedBox(height: 10),
        const Text('连接 → 上电 → 站立\n上电准备运动服务，站立使关节归位。',
            style: TextStyle(color: muted, fontSize: 12)),
        const Divider(),
        const Text('鸭控 DuckPilot 0.4.0 · 局域网直连',
            style: TextStyle(color: muted, fontSize: 11)),
        for (final line in c.logs.take(10))
          Text(line, style: const TextStyle(fontSize: 10)),
      ]);
}
