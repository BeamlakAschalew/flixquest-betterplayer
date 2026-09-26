package uz.shs.better_player_plus

import android.net.Uri
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.ByteArrayOutputStream

/**
 * HLS data source that serves the MPEG-TS hidden in image-disguised segments
 * (see [DisguisedSegmentUnwrapper]).
 *
 * Every other response passes through byte for byte: only a full-resource
 * request whose first bytes look like an image or the provider's marker is
 * buffered. When nothing can be recovered the original bytes are served, so
 * the failure is identical to reading [upstream] directly.
 */
@UnstableApi
internal class DisguisedSegmentDataSource(
    private val upstream: DataSource
) : DataSource {

    class Factory(private val upstream: DataSource.Factory) : DataSource.Factory {
        override fun createDataSource(): DataSource =
            DisguisedSegmentDataSource(upstream.createDataSource())
    }

    /** Bytes already read from [upstream], served before any further reads. */
    private var buffered: ByteArray? = null
    private var bufferedPosition = 0
    private var bufferedLimit = 0
    private var continueUpstream = true
    private var unwrapped = false

    override fun addTransferListener(transferListener: TransferListener) {
        upstream.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        resetState()
        val length = upstream.open(dataSpec)
        // A byte range of a disguised segment cannot be mapped onto its payload.
        if (dataSpec.position != 0L || dataSpec.length != C.LENGTH_UNSET.toLong()) {
            return length
        }

        val head = ByteArray(DisguisedSegmentUnwrapper.SNIFF_LENGTH)
        val headLength = readUpstreamFully(head)
        if (!DisguisedSegmentUnwrapper.isCandidate(head, headLength)) {
            serve(head, headLength, thenUpstream = true)
            return length
        }

        val initialCapacity =
            if (length in 1..MAX_SEGMENT_BYTES) length.toInt() else DEFAULT_CAPACITY
        val body = ByteArrayOutputStream(initialCapacity)
        body.write(head, 0, headLength)
        val chunk = ByteArray(READ_CHUNK_BYTES)
        while (true) {
            if (body.size() > MAX_SEGMENT_BYTES) {
                // Far larger than any live segment: stream it untouched.
                serve(body.toByteArray(), body.size(), thenUpstream = true)
                return length
            }
            val read = upstream.read(chunk, 0, chunk.size)
            if (read == C.RESULT_END_OF_INPUT) break
            body.write(chunk, 0, read)
        }

        val original = body.toByteArray()
        val ts = DisguisedSegmentUnwrapper.unwrap(original)
        if (ts == null) {
            Log.w(TAG, "Image-like HLS response hides no MPEG-TS; serving it unchanged")
            serve(original, original.size, thenUpstream = false)
            return original.size.toLong()
        }
        unwrapped = true
        serve(ts, ts.size, thenUpstream = false)
        return ts.size.toLong()
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        val pending = buffered
        if (pending != null && bufferedPosition < bufferedLimit) {
            val count = minOf(length, bufferedLimit - bufferedPosition)
            System.arraycopy(pending, bufferedPosition, buffer, offset, count)
            bufferedPosition += count
            return count
        }
        return if (continueUpstream) {
            upstream.read(buffer, offset, length)
        } else {
            C.RESULT_END_OF_INPUT
        }
    }

    override fun getUri(): Uri? = upstream.uri

    override fun getResponseHeaders(): Map<String, List<String>> {
        val headers = upstream.responseHeaders
        if (!unwrapped) return headers
        // The upstream Content-Type (image/png, ...) and Content-Length describe
        // the disguise, not the payload now being served.
        val result = LinkedHashMap<String, List<String>>()
        for ((name, values) in headers) {
            // HttpURLConnection reports its status line under a null name;
            // String?.equals tolerates it and the entry is kept as-is.
            if (name.equals(CONTENT_TYPE, ignoreCase = true) ||
                name.equals(CONTENT_LENGTH, ignoreCase = true)
            ) {
                continue
            }
            result[name] = values
        }
        result[CONTENT_TYPE] = listOf(MPEG_TS_MIME_TYPE)
        return result
    }

    override fun close() {
        resetState()
        upstream.close()
    }

    private fun serve(bytes: ByteArray, limit: Int, thenUpstream: Boolean) {
        buffered = bytes
        bufferedPosition = 0
        bufferedLimit = limit
        continueUpstream = thenUpstream
    }

    private fun resetState() {
        buffered = null
        bufferedPosition = 0
        bufferedLimit = 0
        continueUpstream = true
        unwrapped = false
    }

    private fun readUpstreamFully(target: ByteArray): Int {
        var count = 0
        while (count < target.size) {
            val read = upstream.read(target, count, target.size - count)
            if (read == C.RESULT_END_OF_INPUT) break
            count += read
        }
        return count
    }

    private companion object {
        const val TAG = "BetterPlayer"
        const val CONTENT_TYPE = "Content-Type"
        const val CONTENT_LENGTH = "Content-Length"
        const val MPEG_TS_MIME_TYPE = "video/mp2t"
        const val MAX_SEGMENT_BYTES = 32 * 1024 * 1024
        const val DEFAULT_CAPACITY = 1024 * 1024
        const val READ_CHUNK_BYTES = 64 * 1024
    }
}
