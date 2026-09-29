package uz.shs.better_player_plus

import android.os.Handler
import android.os.SystemClock
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.upstream.BandwidthMeter
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * The player's bandwidth meter, also counting the network bytes it measures so
 * the app can report the data a viewing used.
 *
 * Bytes are counted as the meter's transfer listener sees them rather than
 * from its bandwidth samples: a sample is only published when a transfer ends,
 * and a progressive stream keeps one transfer open until a seek or release, so
 * its bytes would arrive late or be lost with the player. Cache reads are not
 * network transfers and are not counted.
 *
 * Bytes are handed over in batches: [onBatchReady] fires once enough has built
 * up, and stays quiet until the batch is taken with [drain].
 */
@UnstableApi
internal class NetworkUsageMeter(
    private val delegate: BandwidthMeter,
    private val onBatchReady: () -> Unit,
    private val batchBytes: Long = DEFAULT_BATCH_BYTES,
    private val batchIntervalMs: Long = DEFAULT_BATCH_INTERVAL_MS,
    private val clock: () -> Long = SystemClock::elapsedRealtime,
) : BandwidthMeter {
    private val pendingBytes = AtomicLong()
    private val lastDrainAtMs = AtomicLong(clock())
    private val batchRequested = AtomicBoolean()

    private val transferListener = object : TransferListener {
        override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
            delegate.transferListener?.onTransferInitializing(source, dataSpec, isNetwork)
        }

        override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
            delegate.transferListener?.onTransferStart(source, dataSpec, isNetwork)
        }

        override fun onBytesTransferred(
            source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int
        ) {
            delegate.transferListener?.onBytesTransferred(source, dataSpec, isNetwork, bytesTransferred)
            if (isNetwork) record(bytesTransferred.toLong())
        }

        override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
            delegate.transferListener?.onTransferEnd(source, dataSpec, isNetwork)
        }
    }

    override fun getBitrateEstimate(): Long = delegate.bitrateEstimate

    override fun getTimeToFirstByteEstimateUs(): Long = delegate.timeToFirstByteEstimateUs

    override fun getTransferListener(): TransferListener = transferListener

    override fun addEventListener(eventHandler: Handler, eventListener: BandwidthMeter.EventListener) {
        delegate.addEventListener(eventHandler, eventListener)
    }

    override fun removeEventListener(eventListener: BandwidthMeter.EventListener) {
        delegate.removeEventListener(eventListener)
    }

    /** Called on loader threads. */
    internal fun record(bytes: Long) {
        if (bytes <= 0) return
        val pending = pendingBytes.addAndGet(bytes)
        val batchDue = pending >= batchBytes || clock() - lastDrainAtMs.get() >= batchIntervalMs
        if (batchDue && batchRequested.compareAndSet(false, true)) onBatchReady()
    }

    /** Takes the bytes counted since the previous drain. */
    fun drain(): Long {
        lastDrainAtMs.set(clock())
        batchRequested.set(false)
        return pendingBytes.getAndSet(0)
    }

    companion object {
        const val DEFAULT_BATCH_BYTES = 16L * 1024 * 1024
        const val DEFAULT_BATCH_INTERVAL_MS = 30_000L
    }
}
