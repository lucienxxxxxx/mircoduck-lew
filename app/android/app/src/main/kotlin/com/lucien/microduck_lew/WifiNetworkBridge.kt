package com.lucien.microduck_lew

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

/** Current Wi-Fi route only; no SSID, location access or network scanning. */
class WifiNetworkBridge(context: Context, messenger: BinaryMessenger) {
    private val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "microduck.wifi")
    private var selected: Network? = null
    private var closed = false
    private var signature = ""
    private var current: Map<String, Any> = mapOf("connected" to false)
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { handler.post { refresh() } }
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
            handler.post { refresh() }
        }
        override fun onLost(network: Network) { handler.post { refresh() } }
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            handler.post { refresh() }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "snapshot") { refresh(); result.success(current) }
            else result.notImplemented()
        }
        manager.registerNetworkCallback(NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), callback)
        refresh()
    }

    private fun refresh() {
        if (closed) return
        val available = manager.allNetworks.filter {
            manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        val network = available.firstOrNull { it == manager.activeNetwork }
            ?: available.firstOrNull { it == selected } ?: available.firstOrNull()
        val properties = network?.let { manager.getLinkProperties(it) }
        val gateway = properties?.routes?.firstOrNull {
            it.isDefaultRoute && it.gateway is Inet4Address
        }?.gateway?.hostAddress
        // Force this App's future UDP/WebRTC sockets onto Wi-Fi, including an AP
        // without internet while mobile data remains Android's default route.
        val bound = if (network != selected) {
            manager.bindProcessToNetwork(network).also { if (it) selected = network }
        } else true
        current = if (network != null && gateway != null && bound) {
            mapOf("connected" to true, "id" to network.networkHandle.toString(), "gateway" to gateway)
        } else mapOf("connected" to false)
        val next = current.toString()
        if (next != signature) { signature = next; channel.invokeMethod("changed", current) }
    }

    fun close() {
        closed = true
        manager.unregisterNetworkCallback(callback)
        manager.bindProcessToNetwork(null)
        channel.setMethodCallHandler(null)
    }
}
