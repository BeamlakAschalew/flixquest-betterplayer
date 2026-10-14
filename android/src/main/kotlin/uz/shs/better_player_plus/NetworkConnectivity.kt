package uz.shs.better_player_plus

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Process-wide view of whether the device can reach the internet.
 *
 * Load-error policies read [isOnline] on ExoPlayer's playback thread to tell a
 * dropped connection (wait for it to come back) from a broken stream (give up
 * or skip). Listeners are called on the main thread when the state changes.
 */
internal object NetworkConnectivity {
    private const val TAG = "BetterPlayerNetwork"
    private const val OUTAGE_REPORT_INTERVAL_MS = 15_000L

    /** Assumed true until the platform says otherwise, so a missing permission never blocks playback. */
    @Volatile
    var isOnline: Boolean = true
        private set

    private val listeners = CopyOnWriteArraySet<(Boolean) -> Unit>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var connectivityManager: ConnectivityManager? = null
    @Volatile
    private var lastOutageReportMs = 0L

    @Synchronized
    fun initialize(context: Context) {
        if (connectivityManager != null) return
        val manager = context.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = manager
        try {
            isOnline = currentlyOnline(manager)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Default-network callbacks carry the state; querying the
                // manager from inside them races the change being reported.
                manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        manager.getNetworkCapabilities(network)?.let { update(isOnline(it)) }
                    }

                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                        update(isOnline(capabilities))

                    override fun onLost(network: Network) = update(false)
                })
            } else {
                // Any internet network may come or go here, so re-read the
                // active one instead of trusting the network in the callback.
                manager.registerNetworkCallback(
                    NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
                    object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) = update(currentlyOnline(manager))
                        override fun onLost(network: Network) = update(currentlyOnline(manager))
                    }
                )
            }
        } catch (error: RuntimeException) {
            // SecurityException without ACCESS_NETWORK_STATE, or the per-app
            // callback limit. Playback then behaves as if always online.
            isOnline = true
            Log.i(TAG, "Connectivity updates unavailable: ${error.javaClass.simpleName}")
        }
    }

    fun addListener(listener: (Boolean) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (Boolean) -> Unit) {
        listeners.remove(listener)
    }

    /**
     * Loads keep timing out on a network Android still calls validated. Ask the
     * platform to check again: if the internet really is gone it drops the
     * network's validation, [isOnline] turns false and the player waits instead
     * of failing. Rate limited, and safe to call from any thread.
     */
    fun reportSuspectedOutage() {
        val manager = connectivityManager ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastOutageReportMs < OUTAGE_REPORT_INTERVAL_MS) return
        lastOutageReportMs = now
        try {
            manager.activeNetwork?.let { manager.reportNetworkConnectivity(it, false) }
        } catch (error: RuntimeException) {
            Log.i(TAG, "Connectivity report unavailable: ${error.javaClass.simpleName}")
        }
    }

    private fun update(online: Boolean) {
        if (online == isOnline) return
        isOnline = online
        Log.i(TAG, if (online) "Network available" else "Network lost")
        mainHandler.post {
            // Drop a stale post if the state flipped back before it ran.
            if (isOnline != online) return@post
            listeners.forEach { it(online) }
        }
    }

    private fun currentlyOnline(manager: ConnectivityManager): Boolean = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            manager.activeNetworkInfo?.isConnected == true
        } else {
            manager.activeNetwork?.let(manager::getNetworkCapabilities)?.let(::isOnline) ?: false
        }
    } catch (_: RuntimeException) {
        true
    }

    /**
     * Validated means Android reached the internet over this network. VPNs do
     * not always carry their underlying network's validation, so a VPN with
     * internet access counts as online rather than waiting forever.
     */
    private fun isOnline(capabilities: NetworkCapabilities): Boolean {
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }
}
