import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models/robot.dart';
import 'services/robot_connection.dart';
import 'widgets/phone_stick.dart';
import 'widgets/style.dart';

class PhoneHome extends StatefulWidget {
  final RobotConnection? connection;
  const PhoneHome({super.key, this.connection});
  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> with WidgetsBindingObserver {
  late final c = widget.connection ?? RobotConnection();
  final scaffold = GlobalKey<ScaffoldState>();
  final host = TextEditingController(text: '192.168.1.100');
  final port = TextEditingController(text: '20043');
  final key = TextEditingController();
  int page = 0;
  double speed = .25;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
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
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(changed);
    if (widget.connection == null) c.dispose();
    host.dispose();
    port.dispose();
    key.dispose();
    super.dispose();
  }

  String n(double? value, [int digits = 1]) =>
      value == null ? '—' : value.toStringAsFixed(digits);
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
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

  Future<bool> confirm(String title, String body) async {
    c.stop();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> home() async {
    if (await confirm('移动到 HOME', '会使能关节并移动到默认姿态。确认机器人已摆放稳妥，周围无阻碍。')) {
      await c.action('home');
    }
  }

  Future<void> mode() async {
    c.stop();
    final next = c.robot.mode == 'motion' ? 'commissioning' : 'motion';
    if (await confirm(
      next == 'motion' ? '启用运动服务' : '切回标定服务',
      next == 'motion'
          ? '保留标定并切换正式服务。切换后需要重新接管；HOME 和模型需手动操作。'
          : '会关闭电机扭矩。请先平放或支撑好机器人。',
    )) {
      await c.action(next);
    }
  }

  Future<void> extraControls() async {
    c.stop();
    await showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AnimatedBuilder(
                      animation: c,
                      builder: (context, _) =>
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('扩展手柄 · 扳机控制嘴巴与音效',
                                style: TextStyle(color: cyan)),
                            const SizedBox(height: 12),
                            Wrap(spacing: 12, runSpacing: 12, children: [
                              for (final item in [
                                ('LT', 'lt'),
                                ('RT', 'rt'),
                                ('方向下', 'dy')
                              ])
                                Listener(
                                    onPointerDown: (_) =>
                                        c.axisButton(item.$2, true),
                                    onPointerUp: (_) =>
                                        c.axisButton(item.$2, false),
                                    onPointerCancel: (_) =>
                                        c.axisButton(item.$2, false),
                                    child: Container(
                                        width: 80,
                                        height: 56,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: panel,
                                            border: Border.all(
                                                color:
                                                    (c.axes[item.$2] ?? 0) > 0
                                                        ? cyan
                                                        : edge),
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Text(item.$1))),
                            ]),
                            TextButton(
                                onPressed: !c.acquired
                                    ? null
                                    : () async {
                                        Navigator.pop(context);
                                        if (await confirm('关闭电机扭矩',
                                            '请先平放或稳妥支撑机器人，卸力后不会保持站立。')) {
                                          await perform(
                                              () => c.action('relax'));
                                        }
                                      },
                                child: const Text('卸力（需确认）')),
                          ]))),
            ));
    c.stop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: scaffold,
        resizeToAvoidBottomInset: false,
        onEndDrawerChanged: (open) {
          if (open) {
            c.stop();
            if (c.acquired) unawaited(c.release().catchError((Object _) {}));
          }
        },
        endDrawer: Drawer(
          width: math.min(420, MediaQuery.sizeOf(context).width * .88),
          child: SafeArea(
              child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: settings(),
          )),
        ),
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.pets, color: cyan, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'MICRODUCK',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        c.error ??
                            (c.robot.modeJob.isNotEmpty
                                ? c.robot.modeJob
                                : null) ??
                            (c.link == LinkState.live
                                ? (c.robot.fresh
                                    ? '已连接 · ${c.robot.mode} · ${n(c.robot.hz, 0)} Hz'
                                    : '连接中 · 等待新鲜反馈')
                                : '未连接 · 请先配对'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.robot.fresh ? cyan : orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    for (final item in [
                      (0, Icons.sports_esports, '遥控'),
                      (1, Icons.account_tree, '关节'),
                      (2, Icons.screen_rotation_alt, 'IMU'),
                    ])
                      IconButton(
                        tooltip: item.$3,
                        onPressed: () {
                          c.stop();
                          setState(() => page = item.$1);
                        },
                        icon: Icon(item.$2,
                            color: page == item.$1 ? cyan : muted),
                      ),
                    IconButton(
                        tooltip: '扩展手柄',
                        onPressed: () => extraControls(),
                        icon: const Icon(Icons.tune)),
                    IconButton(
                      tooltip: '连接设置',
                      onPressed: () => scaffold.currentState!.openEndDrawer(),
                      icon: const Icon(Icons.settings),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: page == 0
                    ? remoteView()
                    : page == 1
                        ? jointsView()
                        : imuView(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy || !c.canOperate
                            ? null
                            : () => perform(c.acquired ? c.release : c.claim),
                        icon: Icon(c.acquired ? Icons.link_off : Icons.gamepad),
                        label: Text(c.acquired ? '释放控制' : '接管控制'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy || !c.canOperate || !c.acquired
                            ? null
                            : () => perform(home),
                        child: const Text('HOME'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy || !c.canOperate || !c.acquired
                            ? null
                            : () => perform(mode),
                        child: const Text('切换模式'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF737D),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          c.stop();
                          if (c.link == LinkState.live) {
                            unawaited(perform(c.release));
                          }
                        },
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('停止'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget remoteView() => LayoutBuilder(
        builder: (context, box) {
          final stick = math
              .min(box.maxHeight - 34, box.maxWidth * .28)
              .clamp(60.0, 280.0);
          Widget joystick(bool left) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: stick,
                    height: stick,
                    child: PhoneStick(
                      key: Key(left ? 'left-stick' : 'right-stick'),
                      enabled: c.canDrive,
                      onChanged: (v) => c.setStick(left, v.dx, v.dy, speed),
                    ),
                  ),
                  Text(
                    left ? '左杆 · 前后 / 横移' : '右杆 · 转向 / 头部',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                joystick(true),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          c.robot.realGamepad
                              ? '实体手柄已接管'
                              : c.acquired
                                  ? '手机已接管'
                                  : c.robot.mode == 'commissioning'
                                      ? '标定模式 · 扭矩关闭'
                                      : '等待接管',
                          style: const TextStyle(color: cyan, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            padButton('START', 'start'),
                            padButton('Y · 头', 'y'),
                            padButton('B · 身', 'b'),
                            padButton('A', 'a'),
                            padButton('X', 'x'),
                            padButton('LB', 'lb'),
                            padButton('RB', 'rb'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '摇杆幅度 ${(speed * 100).round()}% · ${c.robot.inputMode}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        Slider(
                          value: speed,
                          min: .1,
                          max: 1,
                          divisions: 9,
                          label: '${(speed * 100).round()}%',
                          onChanged: (v) {
                            c.stop();
                            setState(() => speed = v);
                          },
                        ),
                        Text(
                          c.robot.fresh
                              ? '反馈 ${n(c.robot.age, 0)} ms · ${c.robot.joints.length}/15 关节'
                              : '旧数据不用于授权遥控',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                joystick(false),
              ],
            ),
          );
        },
      );

  Widget padButton(String label, String button) => Semantics(
        button: true,
        label: label,
        child: Listener(
          onPointerDown: (_) => c.button(button, true),
          onPointerUp: (_) => c.button(button, false),
          onPointerCancel: (_) => c.button(button, false),
          child: Container(
            width: 64,
            height: 48,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.acquired ? panel : background,
              border:
                  Border.all(color: c.buttons.contains(button) ? cyan : edge),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(color: c.acquired ? cyan : muted, fontSize: 12),
            ),
          ),
        ),
      );

  Widget jointsView() => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Text(
            c.robot.jointsFresh ? '15 关节实时反馈' : '关节反馈待更新',
            style: const TextStyle(color: cyan),
          ),
          const Text(
            '电流为原始计数；未做 mA 标定。标定模式的位置可能仅提供编码器原始值。',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 8),
          for (final ident in jointNames.keys)
            Builder(
              builder: (context) {
                final j =
                    c.robot.jointFresh(ident) ? c.robot.joints[ident] : null;
                return ListTile(
                  dense: true,
                  leading: Text('$ident', style: const TextStyle(color: cyan)),
                  title:
                      Text('${jointNames[ident]}${j == null ? ' · 待更新' : ''}'),
                  subtitle: Text(
                    '角度 ${n(j?.degrees)}° · 编码器 ${n(j?.raw, 0)} · 温度 ${n(j?.temperature)}℃',
                  ),
                  trailing: Text(
                    '${n(j?.voltage)} V\n电流 raw ${n(j?.currentRaw, 0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                );
              },
            ),
        ],
      );

  Widget imuView() => Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Icon(Icons.screen_rotation_alt, size: 48, color: cyan),
              Text(
                'ROLL ${n(c.robot.roll)}°     PITCH ${n(c.robot.pitch)}°',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              Text(
                'IMU200 · ${c.robot.fresh && c.robot.imuValid == true ? '有效' : '过期 / 无效 / 未接入'} · 序号 ${c.robot.imuSequence ?? '—'}',
              ),
              Text(
                '角速度 rad/s：${c.robot.gyro?.map((v) => v.toStringAsFixed(3)).join(' / ') ?? '—'}',
                style: const TextStyle(color: muted),
              ),
              const Text(
                '失联会清除输入；恢复网络后需重新接管。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget settings() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '连接 Microduck',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: host,
            decoration: const InputDecoration(labelText: '主板 IP / 主机名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'UDP 端口'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: key,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '配对密钥（64 位十六进制）'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () => perform(() async {
                      await c.connect(
                        host.text,
                        int.tryParse(port.text) ?? 0,
                        key.text,
                      );
                      if (mounted) Navigator.pop(context);
                    }),
            child: Text(busy ? '连接中…' : '认证连接'),
          ),
          TextButton(
            onPressed: () => perform(c.disconnect),
            child: const Text('断开连接'),
          ),
          const Divider(),
          Text(
            '服务：${c.robot.build.isEmpty ? '尚未读取' : c.robot.build}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const Text(
            'mircoduck-lew App 0.2.0\n密钥只保存在本次 App 内存中，不写入 APK 或日志。',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 12),
          for (final line in c.logs.take(15))
            Text(line, style: const TextStyle(fontSize: 11)),
        ],
      );
}
