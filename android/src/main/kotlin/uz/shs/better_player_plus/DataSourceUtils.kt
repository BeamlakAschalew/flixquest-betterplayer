package uz.shs.better_player_plus

import android.net.Uri
import android.content.Context
import android.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cronet.CronetDataSource
import com.google.android.gms.net.CronetProviderInstaller
import com.google.android.gms.net.PlayServicesCronetProvider
import org.chromium.net.CronetEngine
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@UnstableApi
internal object DataSourceUtils {
    private val initializing = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "BetterPlayer-Cronet").apply { isDaemon = true }
    }
    @Volatile private var engine: CronetEngine? = null

    /** Process-wide connection pool. Installation never delays player creation. */
    fun initialize(context: Context) {
        if (!initializing.compareAndSet(false, true)) return
        val applicationContext = context.applicationContext
        try {
            CronetProviderInstaller.installProvider(applicationContext)
                .addOnSuccessListener(executor) {
                    try {
                        engine = PlayServicesCronetProvider(applicationContext).createBuilder()
                            .enableHttp2(true)
                            .enableQuic(true)
                            .enableHttpCache(CronetEngine.Builder.HTTP_CACHE_DISABLED, 0)
                            .build()
                    } catch (_: RuntimeException) {
                        Log.i("BetterPlayer", "Cronet unavailable; using platform HTTP")
                    } catch (_: LinkageError) {
                        Log.i("BetterPlayer", "Cronet unavailable; using platform HTTP")
                    }
                }
                .addOnFailureListener(executor) {
                    Log.i("BetterPlayer", "Cronet provider unavailable; using platform HTTP")
                }
        } catch (_: RuntimeException) {
            Log.i("BetterPlayer", "Cronet provider unavailable; using platform HTTP")
        } catch (_: LinkageError) {
            Log.i("BetterPlayer", "Cronet provider unavailable; using platform HTTP")
        }
    }
    private const val USER_AGENT = "User-Agent"
    private const val USER_AGENT_PROPERTY = "http.agent"

    @JvmStatic
    fun getUserAgent(headers: Map<String, String>?): String? {
        var userAgent = System.getProperty(USER_AGENT_PROPERTY)
        if (headers != null && headers.containsKey(USER_AGENT)) {
            val userAgentHeader = headers[USER_AGENT]
            if (userAgentHeader != null) {
                userAgent = userAgentHeader
            }
        }
        return userAgent
    }

    @JvmStatic
    fun getDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        val requestHeaders = headers?.toMap() ?: emptyMap()
        val fallback = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(8_000)
            .setReadTimeoutMs(12_000)
            .setDefaultRequestProperties(requestHeaders)
        return DataSource.Factory {
            // Late selection allows a source created during provider installation
            // to use Cronet for subsequent chunks. Never change a request in flight.
            val readyEngine = engine
            if (readyEngine == null) {
                fallback.createDataSource()
            } else {
                CronetDataSource.Factory(readyEngine, executor)
                    .setUserAgent(userAgent)
                    .setDefaultRequestProperties(requestHeaders)
                    .setConnectionTimeoutMs(8_000)
                    .setReadTimeoutMs(12_000)
                    .setResetTimeoutOnRedirects(false)
                    .setHandleSetCookieRequests(true)
                    .createDataSource()
            }
        }
    }

    @JvmStatic
    fun isHTTP(uri: Uri?): Boolean {
        if (uri == null || uri.scheme == null) {
            return false
        }
        val scheme = uri.scheme
        return scheme == "http" || scheme == "https"
    }
}
