import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microduck_lew/main.dart';
import 'package:microduck_lew/widgets/phone_stick.dart';
import 'package:microduck_lew/widgets/camera_backdrop.dart';

void main() {
  testWidgets(
      'small phone keeps a clear center and a compact scrollable action panel',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ConsoleApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('left-stick')), findsOneWidget);
    expect(find.byKey(const Key('right-stick')), findsNothing);
    final actions = find.widgetWithText(ListView, '前滚');
    expect(tester.getSize(actions).width, lessThan(400));
    await tester.drag(actions, const Offset(-220, 0));
    await tester.pump();
    expect(find.text('右踢').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('selected startup image opens into the pilot view',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = GlobalKey();
    await tester.pumpWidget(
        RepaintBoundary(key: root, child: const ConsoleApp(showStartup: true)));
    expect(find.text('鸭控 · DuckPilot'), findsOneWidget);
    final output = Platform.environment['PREVIEW_STARTUP_OUTPUT'];
    if (output != null) {
      await tester.runAsync(() async {
        final path = Platform.environment['PREVIEW_FONT'];
        if (path != null) {
          final loader = FontLoader('Roboto')
            ..addFont(
                File(path).readAsBytes().then((b) => ByteData.sublistView(b)));
          await loader.load();
        }
        await precacheImage(const AssetImage('assets/startup-controller.png'),
            root.currentContext!);
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
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('站立'), findsOneWidget);
    expect(find.text('鸭控 · DuckPilot'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('phone landscape pages fit without overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: root, child: const ConsoleApp()));
    expect(tester.takeException(), isNull);
    expect(find.text('上电'), findsOneWidget);
    expect(find.text('站立'), findsOneWidget);
    expect(find.text('长叫'), findsOneWidget);
    expect(find.text('短叫'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const Key('right-stick')), findsNothing);
    expect(find.text('接管控制'), findsNothing);
    final camera =
        tester.widget<CameraBackdrop>(find.byType(CameraBackdrop)).controller;
    await tester.tap(find.byTooltip('旋转画面'));
    await tester.pump();
    expect(camera.turns, 1);
    await tester.tap(find.text('中'));
    await tester.pump();
    await tester.tap(find.byTooltip('参数'));
    await tester.pumpAndSettle();
    expect(find.textContaining('IMU200'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
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
