import 'dart:async';
import 'package:flutter/material.dart';

class StartupGate extends StatefulWidget {
  final Widget child;
  const StartupGate({super.key, required this.child});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool ready = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: ready ? widget.child : const StartupView());
}

class StartupView extends StatelessWidget {
  const StartupView({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: const Color(0xFF070C10),
      child: Center(
          child: LayoutBuilder(
              builder: (context, box) =>
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: box.maxWidth * .78,
                        height: box.maxHeight * .63,
                        child: Image.asset('assets/startup-controller.png',
                            fit: BoxFit.contain)),
                    const SizedBox(height: 12),
                    const Text('鸭控 · DuckPilot',
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none)),
                  ]))));
}
