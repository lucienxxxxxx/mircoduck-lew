package com.lucien.microduck_lew

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "microduck/camera", CameraViewFactory(flutterEngine.dartExecutor.binaryMessenger))
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
