import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/main.dart';
import 'package:microduck_lew/widgets/phone_stick.dart';

void main() {
  testWidgets('phone landscape pages fit without overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: root, child: const ConsoleApp()));
    expect(tester.takeException(), isNull);
    expect(find.text('接管控制'), findsOneWidget);
    for (final label in ['关节', 'IMU', '遥控']) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    final output = Platform.environment['PREVIEW_OUTPUT'];
    await tester.tap(find.byTooltip('连接设置'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.tapAt(const Offset(10, 180));
    await tester.pumpAndSettle();
    if (output != null) {
      await tester.runAsync(() async {
        for (final entry in [
          ('Roboto', 'PREVIEW_FONT'),
          ('MaterialIcons', 'PREVIEW_MATERIAL_FONT')
        ]) {
          final path = Platform.environment[entry.$2];
          if (path != null) {
            final loader = FontLoader(entry.$1)
              ..addFont(File(path)
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)));
            await loader.load();
          }
        }
      });
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(data!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('two thumbs move independently and release recenters',
      (tester) async {
    Offset left = Offset.zero, right = Offset.zero;
    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      SizedBox(
          width: 200,
          height: 200,
          child: PhoneStick(
              key: const Key('left-stick'),
              enabled: true,
              onChanged: (v) => left = v)),
      SizedBox(
          width: 200,
          height: 200,
          child: PhoneStick(
              key: const Key('right-stick'),
              enabled: true,
              onChanged: (v) => right = v)),
    ])));
    final a = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('left-stick'))),
        pointer: 1);
    final b = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('right-stick'))),
        pointer: 2);
    await a.moveBy(const Offset(45, -35));
    await b.moveBy(const Offset(-40, 20));
    await tester.pump();
    expect(left.distance, greaterThan(.2));
    expect(right.distance, greaterThan(.2));
    await a.up();
    expect(left, Offset.zero);
    expect(right.distance, greaterThan(.2));
    await b.cancel();
    expect(right, Offset.zero);
  });
}
