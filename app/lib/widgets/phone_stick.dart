import 'package:flutter/material.dart';

import 'style.dart';

class PhoneStick extends StatefulWidget {
  final bool enabled;
  final ValueChanged<Offset> onChanged;
  final String label;
  const PhoneStick(
      {super.key,
      required this.enabled,
      required this.onChanged,
      this.label = '方向摇杆'});
  @override
  State<PhoneStick> createState() => _PhoneStickState();
}

class _PhoneStickState extends State<PhoneStick> {
  Offset value = Offset.zero;
  int? pointer;
  void move(Offset position, double size) {
    var v = (position - Offset(size / 2, size / 2)) / (size * .32);
    if (v.distance > 1) v = v / v.distance;
    const dead = .08;
    v = v.distance < dead
        ? Offset.zero
        : v / v.distance * ((v.distance - dead) / (1 - dead));
    setState(() => value = v);
    widget.onChanged(v);
  }

  void reset() {
    pointer = null;
    setState(() => value = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  void didUpdateWidget(covariant PhoneStick old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      value = Offset.zero;
      pointer = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final size = box.maxWidth;
          return Semantics(
            label: widget.label,
            enabled: widget.enabled,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (widget.enabled && pointer == null) {
                  pointer = e.pointer;
                  move(e.localPosition, size);
                }
              },
              onPointerMove: (e) {
                if (widget.enabled && pointer == e.pointer) {
                  move(e.localPosition, size);
                }
              },
              onPointerUp: (e) {
                if (pointer == e.pointer) reset();
              },
              onPointerCancel: (e) {
                if (pointer == e.pointer) reset();
              },
              child: CustomPaint(
                painter: _PhoneStickPainter(value, widget.enabled),
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      );
}

class _PhoneStickPainter extends CustomPainter {
  final Offset value;
  final bool enabled;
  _PhoneStickPainter(this.value, this.enabled);
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2), r = s.width * .45;
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFF18252B), Color(0xFF10171D)],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    for (final f in [1.0, .72]) {
      c.drawCircle(
        center,
        r * f,
        Paint()
          ..color = enabled ? const Color(0xFF35504E) : edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    final p = Paint()
      ..color = muted.withValues(alpha: .4)
      ..strokeWidth = 1.5;
    for (final direction in [
      const Offset(0, -1),
      const Offset(0, 1),
      const Offset(-1, 0),
      const Offset(1, 0),
    ]) {
      final a = center + direction * r * .86;
      c.drawLine(a - direction * 5, a + direction * 5, p);
    }
    final thumb = center + value * s.width * .32;
    c.drawCircle(
      thumb,
      s.width * .16,
      Paint()
        ..color =
            enabled ? cyan.withValues(alpha: .07) : const Color(0xFF16222C),
    );
    c.drawCircle(
      thumb,
      s.width * .16,
      Paint()
        ..color = enabled ? cyan : const Color(0xFF6A7D89)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawCircle(thumb, 4, Paint()..color = enabled ? cyan : muted);
    if (!enabled) {
      final text = TextPainter(
        text: const TextSpan(
          text: '待就绪',
          style: TextStyle(fontSize: 12, color: muted, fontFamily: 'Roboto'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(c, Offset(center.dx - text.width / 2, center.dy + r * .6));
    }
  }

  @override
  bool shouldRepaint(covariant _PhoneStickPainter old) =>
      old.value != value || old.enabled != enabled;
}
