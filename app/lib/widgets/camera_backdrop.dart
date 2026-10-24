import 'dart:io';
import 'package:flutter/material.dart';
import '../services/camera_controller.dart';

class CameraBackdrop extends StatelessWidget {
  final CameraController controller;
  const CameraBackdrop({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Platform.isAndroid
          ? AndroidView(
              viewType: 'microduck/camera',
              onPlatformViewCreated: controller.attach)
          : const ColoredBox(color: Color(0xFF070C10)));
}
