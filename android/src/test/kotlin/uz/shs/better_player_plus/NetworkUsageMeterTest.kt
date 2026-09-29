package uz.shs.better_player_plus

import android.net.Uri
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.upstream.BandwidthMeter
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class NetworkUsageMeterTest {
    private val source: DataSource = ByteArrayDataSource(ByteArray(1))
    private val spec = DataSpec(Uri.parse("https://cdn.test/seg.ts"))
    private var nowMs = 0L
    private var batches = 0

    @Test fun countsNetworkBytesAndSkipsCacheReads() {
        val meter = meter()
        meter.transferListener.onBytesTransferred(source, spec, true, 1_000)
        meter.transferListener.onBytesTransferred(source, spec, false, 5_000)
        meter.transferListener.onBytesTransferred(source, spec, true, 500)
        assertEquals(1_500L, meter.drain())
    }

    @Test fun forwardsEveryTransferToTheWrappedMeter() {
        val delegate = RecordingBandwidthMeter()
        val meter = meter(delegate)
        meter.transferListener.onTransferInitializing(source, spec, true)
        meter.transferListener.onTransferStart(source, spec, true)
        meter.transferListener.onBytesTransferred(source, spec, false, 42)
        meter.transferListener.onTransferEnd(source, spec, true)
        assertEquals(listOf("init", "start", "bytes:42", "end"), delegate.calls)
        assertEquals(7_000_000L, meter.bitrateEstimate)
    }

    @Test fun asksForOneBatchOnceEnoughBytesBuildUp() {
        val meter = meter()
        meter.record(600)
        assertEquals(0, batches)
        meter.record(600)
        meter.record(600)
        assertEquals(1, batches)
        assertEquals(1_800L, meter.drain())
        meter.record(1_000)
        assertEquals(2, batches)
    }

    @Test fun asksForABatchOnceTheIntervalPasses() {
        val meter = meter()
        meter.record(10)
        assertEquals(0, batches)
        nowMs += 30_000
        meter.record(10)
        assertEquals(1, batches)
        assertEquals(20L, meter.drain())
        meter.record(10)
        assertEquals(1, batches)
    }

    @Test fun drainingEmptiesTheCount() {
        val meter = meter()
        meter.record(300)
        assertEquals(300L, meter.drain())
        assertEquals(0L, meter.drain())
    }

    private fun meter(delegate: BandwidthMeter = RecordingBandwidthMeter()) = NetworkUsageMeter(
        delegate,
        onBatchReady = { batches++ },
        batchBytes = 1_000,
        batchIntervalMs = 30_000,
        clock = { nowMs },
    )

    private class RecordingBandwidthMeter : BandwidthMeter {
        val calls = mutableListOf<String>()
        private val listener = object : TransferListener {
            override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
                calls += "init"
            }
            override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
                calls += "start"
            }
            override fun onBytesTransferred(
                source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int
            ) {
                calls += "bytes:$bytesTransferred"
            }
            override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {
                calls += "end"
            }
        }

        override fun getBitrateEstimate(): Long = 7_000_000L
        override fun getTransferListener(): TransferListener = listener
        override fun addEventListener(handler: android.os.Handler, listener: BandwidthMeter.EventListener) = Unit
        override fun removeEventListener(listener: BandwidthMeter.EventListener) = Unit
    }
}
