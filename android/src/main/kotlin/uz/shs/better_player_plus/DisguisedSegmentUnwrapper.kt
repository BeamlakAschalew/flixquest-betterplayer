package uz.shs.better_player_plus

import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.zip.DataFormatException
import java.util.zip.GZIPInputStream
import java.util.zip.Inflater

/**
 * Recovers MPEG-TS media segments that a live provider disguises as images
 * hosted on image CDNs. Browsers unwrap them in a custom hls.js loader;
 * without this, ExoPlayer hands the image bytes to TsExtractor and fails with
 * "Cannot find sync byte".
 *
 * Mirrors the provider's decoder, in the same order:
 * 1. TS stored in a WebP `EXIF` chunk.
 * 2. TS appended after a PNG's `IEND` chunk.
 * 3. gzip'd TS stored in PNG pixels, prefixed by `TIKTIKPX` and a length.
 * 4. TS after a `TIKTIKRAW` marker, gzip'd TS after a `TIKTIKTSGZ` marker, or
 *    TS behind arbitrary leading junk (non-PNG payloads only).
 */
internal object DisguisedSegmentUnwrapper {
    /** Bytes [isCandidate] needs to classify a response. */
    const val SNIFF_LENGTH = 12

    private const val TS_PACKET_SIZE = 188
    private const val TS_SYNC = 0x47

    /** Upper bound for decoded PNG pixel data, guarding against hostile IHDRs. */
    private const val MAX_PIXEL_BYTES = 64 * 1024 * 1024

    private val PNG_SIGNATURE = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    )
    private val JPEG_SIGNATURE = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())
    private val GIF_SIGNATURE = ascii("GIF8")
    private val MARKER_PREFIX = ascii("TIKTIK")
    private val RAW_MARKER = ascii("TIKTIKRAW")
    private val GZIP_MARKER = ascii("TIKTIKTSGZ")
    private val PIXEL_MAGIC = ascii("TIKTIKPX")

    /**
     * Whether a response starting with the first [length] bytes of [head] may
     * be a disguised segment. Only image containers and the provider's marker
     * qualify, so playlists, keys, subtitles and genuine media never qualify.
     */
    fun isCandidate(head: ByteArray, length: Int): Boolean =
        startsWith(head, length, PNG_SIGNATURE) ||
            isWebp(head, length) ||
            startsWith(head, length, JPEG_SIGNATURE) ||
            startsWith(head, length, GIF_SIGNATURE) ||
            startsWith(head, length, MARKER_PREFIX)

    /** Returns the hidden TS payload, or null when [bytes] hides none. */
    fun unwrap(bytes: ByteArray): ByteArray? {
        webpExifTs(bytes)?.let { return it }
        if (startsWith(bytes, bytes.size, PNG_SIGNATURE)) {
            return pngIendTs(bytes) ?: pngPixelTs(bytes)
        }
        markedRawTs(bytes)?.let { return it }
        markedGzipTs(bytes)?.let { return it }
        for (index in 0 until bytes.size - TS_PACKET_SIZE) {
            if (isTsStart(bytes, index)) return bytes.copyOfRange(index, bytes.size)
        }
        return null
    }

    private fun webpExifTs(bytes: ByteArray): ByteArray? {
        if (bytes.size < 16 || !isWebp(bytes, bytes.size)) return null
        var offset = 12
        while (offset + 8 <= bytes.size) {
            val tag = String(bytes, offset, 4, Charsets.US_ASCII)
            val length = u32le(bytes, offset + 4)
            offset += 8
            if (offset + length > bytes.size) return null
            if (tag == "EXIF") {
                val end = offset + length.toInt()
                return if (length > TS_PACKET_SIZE && isTsStart(bytes, offset)) {
                    bytes.copyOfRange(offset, end)
                } else {
                    null
                }
            }
            offset += (length + (length and 1L)).toInt()
        }
        return null
    }

    private fun pngIendTs(bytes: ByteArray): ByteArray? {
        var offset = PNG_SIGNATURE.size
        while (offset + 8 <= bytes.size) {
            val length = u32be(bytes, offset)
            if (length > bytes.size - offset - 12L) return null
            val type = String(bytes, offset + 4, 4, Charsets.US_ASCII)
            offset += 12 + length.toInt()
            if (type == "IEND") {
                return if (isTsStart(bytes, offset)) {
                    bytes.copyOfRange(offset, bytes.size)
                } else {
                    null
                }
            }
        }
        return null
    }

    private fun pngPixelTs(bytes: ByteArray): ByteArray? {
        val rgb = pngRgb(bytes) ?: return null
        if (rgb.size < 12 || !startsWith(rgb, rgb.size, PIXEL_MAGIC)) return null
        val length = u32be(rgb, 8)
        if (length < 2 || 12 + length > rgb.size) return null
        val end = 12 + length.toInt()
        if (rgb[12] != 0x1F.toByte() || rgb[13] != 0x8B.toByte()) return null
        val ts = gunzip(rgb, 12, end) ?: return null
        return if (ts.isNotEmpty() && ts[0] == TS_SYNC.toByte()) ts else null
    }

    /**
     * Decodes 8-bit, non-interlaced RGB or RGBA PNG pixels to packed RGB.
     * Decoded by hand: platform image decoders may colour-manage pixels, and a
     * single altered byte corrupts the gzip stream they carry.
     */
    private fun pngRgb(bytes: ByteArray): ByteArray? {
        var offset = PNG_SIGNATURE.size
        var width = 0L
        var height = 0L
        var depth = 0
        var colorType = 0
        var interlace = 0
        val idat = java.io.ByteArrayOutputStream()
        while (offset + 8 <= bytes.size) {
            val length = u32be(bytes, offset)
            if (length > bytes.size - offset - 12L) return null
            val type = String(bytes, offset + 4, 4, Charsets.US_ASCII)
            val data = offset + 8
            when (type) {
                "IHDR" -> {
                    if (length < 13) return null
                    width = u32be(bytes, data)
                    height = u32be(bytes, data + 4)
                    depth = bytes[data + 8].toInt() and 0xFF
                    colorType = bytes[data + 9].toInt() and 0xFF
                    interlace = bytes[data + 12].toInt() and 0xFF
                }
                "IDAT" -> idat.write(bytes, data, length.toInt())
                "IEND" -> break
            }
            offset += 12 + length.toInt()
        }
        if (width <= 0 || height <= 0 || depth != 8 || interlace != 0) return null
        if (colorType != 2 && colorType != 6) return null
        val bpp = if (colorType == 6) 4 else 3
        val stride = width * bpp
        val rawSize = height * (stride + 1)
        if (rawSize > MAX_PIXEL_BYTES) return null
        val raw = inflate(idat.toByteArray(), rawSize.toInt()) ?: return null

        val strideBytes = stride.toInt()
        val rgb = ByteArray((width * height * 3).toInt())
        var previous = ByteArray(strideBytes)
        var current = ByteArray(strideBytes)
        var source = 0
        var target = 0
        repeat(height.toInt()) {
            val filter = raw[source++].toInt() and 0xFF
            for (i in 0 until strideBytes) {
                val left = if (i >= bpp) current[i - bpp].toInt() and 0xFF else 0
                val up = previous[i].toInt() and 0xFF
                val upLeft = if (i >= bpp) previous[i - bpp].toInt() and 0xFF else 0
                val value = raw[source + i].toInt() and 0xFF
                current[i] = when (filter) {
                    0 -> value
                    1 -> value + left
                    2 -> value + up
                    3 -> value + ((left + up) shr 1)
                    4 -> value + paeth(left, up, upLeft)
                    else -> return null
                }.toByte()
            }
            source += strideBytes
            if (bpp == 3) {
                System.arraycopy(current, 0, rgb, target, strideBytes)
                target += strideBytes
            } else {
                for (i in 0 until strideBytes step 4) {
                    rgb[target++] = current[i]
                    rgb[target++] = current[i + 1]
                    rgb[target++] = current[i + 2]
                }
            }
            val swap = previous
            previous = current
            current = swap
        }
        return rgb
    }

    private fun markedRawTs(bytes: ByteArray): ByteArray? {
        var index = indexOf(bytes, RAW_MARKER, 0)
        while (index >= 0) {
            val start = index + RAW_MARKER.size
            if (start < bytes.size && bytes[start] == TS_SYNC.toByte()) {
                return bytes.copyOfRange(start, bytes.size)
            }
            index = indexOf(bytes, RAW_MARKER, index + 1)
        }
        return null
    }

    private fun markedGzipTs(bytes: ByteArray): ByteArray? {
        val index = indexOf(bytes, GZIP_MARKER, 0)
        if (index < 0) return null
        return gunzip(bytes, index + GZIP_MARKER.size, bytes.size)?.takeIf { it.isNotEmpty() }
    }

    private fun inflate(data: ByteArray, expectedSize: Int): ByteArray? {
        val inflater = Inflater()
        return try {
            inflater.setInput(data)
            val out = ByteArray(expectedSize)
            var written = 0
            while (written < expectedSize && !inflater.finished()) {
                val count = inflater.inflate(out, written, expectedSize - written)
                if (count == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
                written += count
            }
            if (written == expectedSize) out else null
        } catch (_: DataFormatException) {
            null
        } finally {
            inflater.end()
        }
    }

    private fun gunzip(bytes: ByteArray, start: Int, end: Int): ByteArray? = try {
        GZIPInputStream(ByteArrayInputStream(bytes, start, end - start)).use { it.readBytes() }
    } catch (_: IOException) {
        null
    }

    private fun paeth(left: Int, up: Int, upLeft: Int): Int {
        val estimate = left + up - upLeft
        val distanceLeft = Math.abs(estimate - left)
        val distanceUp = Math.abs(estimate - up)
        val distanceUpLeft = Math.abs(estimate - upLeft)
        return when {
            distanceLeft <= distanceUp && distanceLeft <= distanceUpLeft -> left
            distanceUp <= distanceUpLeft -> up
            else -> upLeft
        }
    }

    private fun isTsStart(bytes: ByteArray, index: Int): Boolean =
        index + TS_PACKET_SIZE < bytes.size &&
            bytes[index] == TS_SYNC.toByte() &&
            bytes[index + TS_PACKET_SIZE] == TS_SYNC.toByte()

    private fun isWebp(bytes: ByteArray, length: Int): Boolean =
        length >= 12 &&
            startsWith(bytes, length, ascii("RIFF")) &&
            String(bytes, 8, 4, Charsets.US_ASCII) == "WEBP"

    private fun startsWith(bytes: ByteArray, length: Int, prefix: ByteArray): Boolean {
        if (length < prefix.size || bytes.size < prefix.size) return false
        for (i in prefix.indices) if (bytes[i] != prefix[i]) return false
        return true
    }

    private fun indexOf(bytes: ByteArray, needle: ByteArray, from: Int): Int {
        outer@ for (i in from..bytes.size - needle.size) {
            for (j in needle.indices) if (bytes[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }

    private fun u32be(bytes: ByteArray, offset: Int): Long =
        ((bytes[offset].toLong() and 0xFF) shl 24) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 8) or
            (bytes[offset + 3].toLong() and 0xFF)

    private fun u32le(bytes: ByteArray, offset: Int): Long =
        (bytes[offset].toLong() and 0xFF) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 8) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 3].toLong() and 0xFF) shl 24)

    private fun ascii(value: String) = value.toByteArray(Charsets.US_ASCII)
}
