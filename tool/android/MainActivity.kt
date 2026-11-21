package __PACKAGE__

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * Studio-Eldawly: تصدير M4A (AAC) بمشفّر أندرويد نفسه — من غير أي مكتبة خارجية.
 * القناة: eldawly/audio → encodeAac(pcm: 16-bit mono LE, sampleRate, bitrate) → bytes
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eldawly/audio").setMethodCallHandler { call, result ->
            when (call.method) {
                "encodeAac" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                    val rate = call.argument<Int>("sampleRate") ?: 48000
                    val bitrate = call.argument<Int>("bitrate") ?: 160000
                    if (pcm == null) {
                        result.error("bad_args", "pcm is null", null)
                    } else {
                        thread {
                            try {
                                val bytes = encodeAac(pcm, rate, bitrate)
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("encode_failed", e.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun encodeAac(pcm: ByteArray, sampleRate: Int, bitrate: Int): ByteArray {
        val out = File.createTempFile("eldawly", ".m4a", cacheDir)
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        val muxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        var muxing = false
        val info = MediaCodec.BufferInfo()
        var offset = 0
        var inputDone = false
        var outputDone = false
        var ptsUs = 0L
        val bytesPerSec = sampleRate * 2L
        try {
            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10000)
                    if (inIndex >= 0) {
                        val buf = codec.getInputBuffer(inIndex)!!
                        buf.clear()
                        var chunk = minOf(buf.remaining(), 8192, pcm.size - offset)
                        chunk -= chunk % 2
                        if (chunk <= 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            buf.put(pcm, offset, chunk)
                            codec.queueInputBuffer(inIndex, 0, chunk, ptsUs, 0)
                            offset += chunk
                            ptsUs = offset.toLong() * 1_000_000L / bytesPerSec
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, 10000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxing = true
                } else if (outIndex >= 0) {
                    val ob = codec.getOutputBuffer(outIndex)!!
                    if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) info.size = 0
                    if (info.size > 0 && muxing) {
                        ob.position(info.offset)
                        ob.limit(info.offset + info.size)
                        muxer.writeSampleData(track, ob, info)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                }
            }
        } finally {
            codec.stop()
            codec.release()
            if (muxing) muxer.stop()
            muxer.release()
        }
        val bytes = out.readBytes()
        out.delete()
        return bytes
    }
}
