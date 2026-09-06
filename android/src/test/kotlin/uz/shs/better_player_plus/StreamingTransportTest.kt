package uz.shs.better_player_plus

import android.net.Uri
import androidx.media3.datasource.DataSpec
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class StreamingTransportTest {
    @Test fun providerUserAgentIsCaseInsensitive() {
        assertEquals("ProviderAgent", DataSourceUtils.getUserAgent(mapOf("user-agent" to "ProviderAgent")))
    }

    @Test fun platformFallbackPreservesHeadersAndByteRangesAcrossRedirects() {
        // No Play Services installation in this test: exercise the immediate
        // fallback with real HTTP requests, rather than mocking DataSource reads.
        ServerSocket(0, 2, InetAddress.getByName("127.0.0.1")).use { server ->
            server.soTimeout = 5000
            val executor = Executors.newSingleThreadExecutor()
            val requests = executor.submit<List<String>> {
                (0..1).map { index ->
                    server.accept().use { socket ->
                        socket.soTimeout = 5000
                        val reader = socket.getInputStream().bufferedReader()
                        val lines = mutableListOf<String>()
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                            lines.add(line)
                        }
                        val response = if (index == 0) {
                            "HTTP/1.1 302 Found\r\nLocation: /media\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        } else {
                            "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 2-4/6\r\nContent-Length: 3\r\nConnection: close\r\n\r\ncde"
                        }
                        socket.getOutputStream().write(response.toByteArray())
                        socket.getOutputStream().flush()
                        lines.joinToString("\n").lowercase()
                    }
                }
            }
            val headers = mutableMapOf("Referer" to "https://provider.test/", "X-Stream-Token" to "original")
            val factory = DataSourceUtils.getDataSourceFactory("ProviderAgent", headers)
            headers["X-Stream-Token"] = "mutated"
            val source = factory.createDataSource()
            try {
                val dataSpec = DataSpec.Builder()
                    .setUri(Uri.parse("http://127.0.0.1:${server.localPort}/redirect"))
                    .setPosition(2).setLength(3).build()
                assertEquals(3L, source.open(dataSpec))
                val bytes = ByteArray(3)
                var count = 0
                while (count < bytes.size) {
                    val read = source.read(bytes, count, bytes.size - count)
                    assertTrue(read > 0)
                    count += read
                }
                assertEquals("cde", String(bytes))
                val captured = requests.get(5, TimeUnit.SECONDS)
                assertEquals(2, captured.size)
                for (request in captured) {
                    assertTrue(request.contains("range: bytes=2-4"))
                    assertTrue(request.contains("user-agent: provideragent"))
                    assertTrue(request.contains("referer: https://provider.test/"))
                    assertTrue(request.contains("x-stream-token: original"))
                }
            } finally {
                source.close()
                executor.shutdownNow()
            }
        }
    }
}
