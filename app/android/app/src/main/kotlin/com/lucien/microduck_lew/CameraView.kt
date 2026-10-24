package com.lucien.microduck_lew

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

class CameraViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = CameraView(context, viewId, messenger)
}

@SuppressLint("SetJavaScriptEnabled")
class CameraView(context: Context, viewId: Int, messenger: BinaryMessenger) : PlatformView {
    private val web = WebView(context)
    private val channel = MethodChannel(messenger, "microduck.camera/$viewId")
    private var disposed = false
    private var loaded = false
    private val bridge = object {
        @JavascriptInterface
        fun postMessage(message: String) {
            if (message.length > 4096) return
            web.post {
                if (!disposed) {
                    try { if (JSONObject(message).optString("type") == "ready") loaded = true }
                    catch (_: Exception) { return@post }
                    channel.invokeMethod("event", message)
                }
            }
        }
    }
    init {
        web.setBackgroundColor(Color.BLACK)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = false
        web.settings.mediaPlaybackRequiresUserGesture = false
        web.settings.allowFileAccess = false
        web.settings.allowContentAccess = false
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = true
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
        }
        // This bridge only accepts bounded video statistics from bundled local HTML.
        // It never exposes robot commands, filesystem access, or remote navigation.
        web.addJavascriptInterface(bridge, "MicroduckVideo")
        val loader = FlutterInjector.instance().flutterLoader()
        fun asset(name: String) = context.assets.open(loader.getLookupKeyForAsset(name)).bufferedReader().use { it.readText() }
        val script = asset("assets/camera.js").replace("export class Camera", "class Camera")
        val html = asset("assets/camera.html").replace("/*CAMERA_SCRIPT*/", script)
        channel.setMethodCallHandler { call, result ->
            if (disposed) { result.error("closed", "Camera view closed", null); return@setMethodCallHandler }
            when (call.method) {
                "ready" -> result.success(loaded)
                "connect" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 8443
                    if (!Regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$").matches(host) || port !in 1..65535) {
                        result.error("address", "Invalid camera endpoint", null)
                    } else {
                        web.evaluateJavascript("connectCamera(${JSONObject.quote(host)},$port)", null)
                        result.success(null)
                    }
                }
                "rotate" -> {
                    val turns = call.argument<Int>("turns") ?: 0
                    web.evaluateJavascript("rotateView(${turns.mod(4)})", null)
                    result.success(null)
                }
                "disconnect" -> { web.evaluateJavascript("disconnectCamera()", null); result.success(null) }
                else -> result.notImplemented()
            }
        }
        web.loadDataWithBaseURL("http://127.0.0.1/", html, "text/html", "UTF-8", null)
    }
    override fun getView(): View = web
    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        web.removeJavascriptInterface("MicroduckVideo")
        web.stopLoading()
        web.loadUrl("about:blank")
        web.destroy()
    }
}
