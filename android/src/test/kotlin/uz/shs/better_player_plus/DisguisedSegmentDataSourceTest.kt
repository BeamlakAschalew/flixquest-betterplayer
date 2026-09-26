package uz.shs.better_player_plus

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.Deflater
import java.util.zip.GZIPOutputStream
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class DisguisedSegmentDataSourceTest {
    private val ts = transportStream(packets = 4)

    @Test fun passesGenuineTransportStreamThrough() {
        assertPassthrough(ts)
    }

    @Test fun passesPlaylistsKeysAndShortBodiesThrough() {
        assertPassthrough("#EXTM3U\n#EXTINF:6.0,\nseg.ts\n".toByteArray())
        assertPassthrough(ByteArray(16) { (it * 17).toByte() })
        assertPassthrough(byteArrayOf(0x47, 0x00))
    }

    @Test fun passesByteRangeRequestsThroughEvenForImages() {
        val png = pixelPng(ts, colorType = 2)
        val source = DisguisedSegmentDataSource(ByteArrayDataSource(png))
        val spec = DataSpec.Builder().setUri(Uri.parse("https://cdn.test/seg")).setPosition(4).build()
        val length = source.open(spec)
        assertEquals((png.size - 4).toLong(), length)
        assertArrayEquals(png.copyOfRange(4, png.size), readAll(source))
        source.close()
    }

    @Test fun unwrapsGzipTransportStreamFromRgbPngPixels() {
        assertUnwraps(pixelPng(ts, colorType = 2))
    }

    @Test fun unwrapsGzipTransportStreamFromRgbaPngPixels() {
        assertUnwraps(pixelPng(ts, colorType = 6))
    }

    @Test fun unwrapsTransportStreamAppendedAfterPngEnd() {
        val image = png(width = 2, height = 2, colorType = 2, pixels = ByteArray(12))
        assertUnwraps(image + ts)
    }

    @Test fun unwrapsTransportStreamFromWebpExifChunk() {
        val vp8 = riffChunk("VP8 ", ByteArray(5))
        val exif = riffChunk("EXIF", ts)
        val body = "WEBP".toByteArray() + vp8 + exif
        val webp = "RIFF".toByteArray() + le32(body.size) + body
        assertUnwraps(webp)
    }

    @Test fun unwrapsRawAndGzipMarkers() {
        val jpegPrefix = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()) +
            ByteArray(40) { 7 }
        assertUnwraps(jpegPrefix + "TIKTIKRAW".toByteArray() + ts)
        assertUnwraps(jpegPrefix + "TIKTIKTSGZ".toByteArray() + gzip(ts))
        assertUnwraps("TIKTIKRAW".toByteArray() + ts)
    }

    @Test fun servesUnrecognisedImagesUnchanged() {
        val image = png(width = 4, height = 3, colorType = 2, pixels = ByteArray(36) { it.toByte() })
        val source = DisguisedSegmentDataSource(ByteArrayDataSource(image))
        assertEquals(image.size.toLong(), source.open(fullSpec()))
        assertArrayEquals(image, readAll(source))
        source.close()
    }

    @Test fun rewritesContentTypeOnlyWhenUnwrapped() {
        val imageHeaders = mapOf(
            "content-type" to listOf("image/png"),
            "Content-Length" to listOf("123"),
            "X-Cache" to listOf("HIT"),
        )
        val unwrapped = DisguisedSegmentDataSource(HeaderSource(pixelPng(ts, 2), imageHeaders))
        unwrapped.open(fullSpec())
        assertEquals(
            mapOf("X-Cache" to listOf("HIT"), "Content-Type" to listOf("video/mp2t")),
            unwrapped.responseHeaders,
        )
        unwrapped.close()

        val plainHeaders = mapOf("Content-Type" to listOf("video/mp2t"))
        val plain = DisguisedSegmentDataSource(HeaderSource(ts, plainHeaders))
        plain.open(fullSpec())
        assertEquals(plainHeaders, plain.responseHeaders)
        plain.close()
    }

    @Test fun reopeningResetsState() {
        val upstream = ByteArrayDataSource(pixelPng(ts, 2))
        val source = DisguisedSegmentDataSource(upstream)
        source.open(fullSpec())
        assertArrayEquals(ts, readAll(source))
        source.close()
        source.open(fullSpec())
        assertArrayEquals(ts, readAll(source))
        source.close()
    }

    private fun assertPassthrough(bytes: ByteArray) {
        val source = DisguisedSegmentDataSource(ByteArrayDataSource(bytes))
        assertEquals(bytes.size.toLong(), source.open(fullSpec()))
        assertArrayEquals(bytes, readAll(source))
        source.close()
    }

    private fun assertUnwraps(disguised: ByteArray) {
        val source = DisguisedSegmentDataSource(ByteArrayDataSource(disguised))
        assertEquals(ts.size.toLong(), source.open(fullSpec()))
        assertArrayEquals(ts, readAll(source))
        source.close()
    }

    private fun fullSpec() = DataSpec(Uri.parse("https://cdn.test/segment.image"))

    /** Reads with small, uneven buffers to exercise partial buffered reads. */
    private fun readAll(source: DataSource): ByteArray {
        val out = ByteArrayOutputStream()
        val chunk = ByteArray(7)
        while (true) {
            val read = source.read(chunk, 0, chunk.size)
            if (read == C.RESULT_END_OF_INPUT) break
            out.write(chunk, 0, read)
        }
        return out.toByteArray()
    }

    private class HeaderSource(
        bytes: ByteArray,
        private val headers: Map<String, List<String>>,
    ) : DataSource by ByteArrayDataSource(bytes) {
        override fun getResponseHeaders(): Map<String, List<String>> = headers
    }

    private companion object {
        fun transportStream(packets: Int): ByteArray = ByteArray(packets * 188) { index ->
            if (index % 188 == 0) 0x47 else (index * 31 + 5).toByte()
        }

        /** Mirrors the provider: `TIKTIKPX`, u32 length, gzip(TS), zero padding. */
        fun pixelPng(payload: ByteArray, colorType: Int): ByteArray {
            val gz = gzip(payload)
            val data = "TIKTIKPX".toByteArray() + be32(gz.size) + gz
            val width = 16
            val height = (data.size + width * 3 - 1) / (width * 3)
            val rgb = data.copyOf(width * height * 3)
            val pixels = if (colorType == 2) {
                rgb
            } else {
                ByteArray(width * height * 4).also { rgba ->
                    for (pixel in 0 until width * height) {
                        System.arraycopy(rgb, pixel * 3, rgba, pixel * 4, 3)
                        rgba[pixel * 4 + 3] = 0xFF.toByte()
                    }
                }
            }
            return png(width, height, colorType, pixels)
        }

        /** Encodes 8-bit pixels, cycling through all five PNG row filters. */
        fun png(width: Int, height: Int, colorType: Int, pixels: ByteArray): ByteArray {
            val bpp = if (colorType == 6) 4 else 3
            val stride = width * bpp
            val filtered = ByteArrayOutputStream()
            for (y in 0 until height) {
                val filter = y % 5
                filtered.write(filter)
                for (i in 0 until stride) {
                    val x = pixels[y * stride + i].toInt() and 0xFF
                    val a = if (i >= bpp) pixels[y * stride + i - bpp].toInt() and 0xFF else 0
                    val b = if (y > 0) pixels[(y - 1) * stride + i].toInt() and 0xFF else 0
                    val c = if (y > 0 && i >= bpp) pixels[(y - 1) * stride + i - bpp].toInt() and 0xFF else 0
                    val predictor = when (filter) {
                        0 -> 0
                        1 -> a
                        2 -> b
                        3 -> (a + b) shr 1
                        else -> paeth(a, b, c)
                    }
                    filtered.write((x - predictor) and 0xFF)
                }
            }
            val ihdr = be32(width) + be32(height) + byteArrayOf(8, colorType.toByte(), 0, 0, 0)
            return byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) +
                pngChunk("IHDR", ihdr) +
                pngChunk("IDAT", deflate(filtered.toByteArray())) +
                pngChunk("IEND", ByteArray(0))
        }

        fun paeth(a: Int, b: Int, c: Int): Int {
            val p = a + b - c
            val pa = Math.abs(p - a)
            val pb = Math.abs(p - b)
            val pc = Math.abs(p - c)
            return if (pa <= pb && pa <= pc) a else if (pb <= pc) b else c
        }

        fun pngChunk(type: String, data: ByteArray): ByteArray {
            val typeBytes = type.toByteArray()
            val crc = CRC32().apply { update(typeBytes); update(data) }.value.toInt()
            return be32(data.size) + typeBytes + data + be32(crc)
        }

        fun riffChunk(tag: String, data: ByteArray): ByteArray {
            val padding = if (data.size % 2 == 1) ByteArray(1) else ByteArray(0)
            return tag.toByteArray() + le32(data.size) + data + padding
        }

        fun deflate(data: ByteArray): ByteArray {
            val deflater = Deflater()
            deflater.setInput(data)
            deflater.finish()
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (!deflater.finished()) out.write(buffer, 0, deflater.deflate(buffer))
            deflater.end()
            return out.toByteArray()
        }

        fun gzip(data: ByteArray): ByteArray =
            ByteArrayOutputStream().also { out -> GZIPOutputStream(out).use { it.write(data) } }
                .toByteArray()

        fun be32(value: Int) = byteArrayOf(
            (value ushr 24).toByte(), (value ushr 16).toByte(), (value ushr 8).toByte(), value.toByte()
        )

        fun le32(value: Int) = byteArrayOf(
            value.toByte(), (value ushr 8).toByte(), (value ushr 16).toByte(), (value ushr 24).toByte()
        )
    }
}
