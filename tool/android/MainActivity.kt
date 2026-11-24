package __PACKAGE__

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
        // تحديثات من جوه التطبيق: يفتح شاشة تثبيت الـ APK اللي اتحمّل
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eldawly/update").setMethodCallHandler { call, result ->
            when (call.method) {
                // معلومات النسخة المتثبّتة: المعالج وبصمة الـ APK (عشان نختار ملف الفرق المناسب)
                "apkInfo" -> thread {
                    try {
                        val apk = File(applicationInfo.sourceDir)
                        val info = mapOf(
                            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                            "sha256" to sha256(apk),
                            "size" to apk.length(),
                        )
                        runOnUiThread { result.success(info) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("apk_info", e.message, null) }
                    }
                }
                // يركّب النسخة الجديدة من النسخة المتثبّتة + ملف الفرق، ويتأكد إن البصمة مطابقة
                "applyPatch" -> {
                    val patch = call.argument<String>("patch")
                    val out = call.argument<String>("out")
                    val expect = call.argument<String>("sha256")
                    if (patch == null || out == null || expect == null) {
                        result.error("bad_args", "patch/out/sha256 missing", null)
                    } else {
                        thread {
                            try {
                                val sha = applyEldiff(File(applicationInfo.sourceDir), File(patch), File(out))
                                if (!sha.equals(expect, ignoreCase = true)) {
                                    File(out).delete()
                                    runOnUiThread { result.error("mismatch", "sha256 mismatch", null) }
                                } else {
                                    runOnUiThread { result.success(true) }
                                }
                            } catch (e: Exception) {
                                File(out).delete()
                                runOnUiThread { result.error("patch_failed", e.message, null) }
                            }
                        }
                    }
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path missing", null)
                    } else {
                        try {
                            result.success(installApk(File(path)))
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
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
                "saveToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val folder = call.argument<String>("folder") ?: "Studio-Eldawly"
                    if (bytes == null || name == null) {
                        result.error("bad_args", "bytes/name missing", null)
                    } else {
                        thread {
                            try {
                                val path = saveToDownloads(bytes, name, mime, folder)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("save_failed", e.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** يحفظ الملف في Download/<folder>/ (أندرويد 10+ من غير أي صلاحيات). */
    private fun saveToDownloads(bytes: ByteArray, name: String, mime: String, folder: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + folder)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert failed")
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: throw IllegalStateException("open failed")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return Environment.DIRECTORY_DOWNLOADS + "/" + folder + "/" + name
        }
        val dir = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), folder)
        dir.mkdirs()
        val f = File(dir, name)
        f.writeBytes(bytes)
        return f.absolutePath
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

    private fun installApk(file: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return "need_permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.eldawly.updates", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return "ok"
    }

    private fun sha256(f: File): String {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        f.inputStream().buffered(1 shl 16).use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun readLong(b: ByteArray, o: Int): Long {
        var v = 0L
        for (i in 7 downTo 0) v = (v shl 8) or (b[o + i].toLong() and 0xFF)
        return v
    }

    private fun readFully(input: java.io.InputStream, buf: ByteArray, n: Int) {
        var off = 0
        while (off < n) {
            val r = input.read(buf, off, n - off)
            if (r < 0) throw java.io.EOFException("patch truncated")
            off += r
        }
    }

    /** bspatch بصيغة ELDIFF01 (بلوكات zlib) — بيشتغل بالتدفق فمش محتاج ذاكرة كبيرة. يرجّع SHA-256 للناتج. */
    private fun applyEldiff(oldFile: File, patchFile: File, outFile: File): String {
        val header = ByteArray(32)
        java.io.RandomAccessFile(patchFile, "r").use { it.readFully(header) }
        if (String(header, 0, 8, Charsets.US_ASCII) != "ELDIFF01") throw IllegalStateException("bad patch")
        val ctrlLen = readLong(header, 8)
        val diffLen = readLong(header, 16)
        val newSize = readLong(header, 24)
        fun block(start: Long, len: Long?): java.io.InputStream {
            val fis = java.io.FileInputStream(patchFile)
            fis.channel.position(start)
            val raw: java.io.InputStream = if (len != null) LimitedStream(fis, len) else fis
            return java.util.zip.InflaterInputStream(raw.buffered(1 shl 16), java.util.zip.Inflater(), 1 shl 16).buffered(1 shl 16)
        }
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val ctrl = block(32, ctrlLen)
        val diff = block(32 + ctrlLen, diffLen)
        val extra = block(32 + ctrlLen + diffLen, null)
        val old = java.io.RandomAccessFile(oldFile, "r")
        val oldSize = old.length()
        val out = outFile.outputStream().buffered(1 shl 16)
        try {
            val triple = ByteArray(24)
            val buf = ByteArray(1 shl 16)
            val obuf = ByteArray(1 shl 16)
            var newPos = 0L
            var oldPos = 0L
            while (newPos < newSize) {
                readFully(ctrl, triple, 24)
                val x = readLong(triple, 0)
                val y = readLong(triple, 8)
                val z = readLong(triple, 16)
                if (x < 0 || y < 0 || newPos + x + y > newSize) throw IllegalStateException("corrupt patch")
                var left = x
                while (left > 0) {
                    val n = minOf(left, buf.size.toLong()).toInt()
                    readFully(diff, buf, n)
                    // نجمع بايتات النسخة القديمة (اللي جوه حدود الملف بس)
                    val from = maxOf(oldPos, 0L)
                    val to = minOf(oldPos + n, oldSize)
                    if (to > from) {
                        old.seek(from)
                        old.readFully(obuf, 0, (to - from).toInt())
                        val shift = (from - oldPos).toInt()
                        for (i in 0 until (to - from).toInt()) {
                            buf[shift + i] = (buf[shift + i] + obuf[i]).toByte()
                        }
                    }
                    out.write(buf, 0, n)
                    md.update(buf, 0, n)
                    left -= n
                    oldPos += n
                    newPos += n
                }
                left = y
                while (left > 0) {
                    val n = minOf(left, buf.size.toLong()).toInt()
                    readFully(extra, buf, n)
                    out.write(buf, 0, n)
                    md.update(buf, 0, n)
                    left -= n
                    newPos += n
                }
                oldPos += z
            }
        } finally {
            out.close()
            old.close()
            ctrl.close()
            diff.close()
            extra.close()
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private class LimitedStream(private val inner: java.io.InputStream, private var left: Long) : java.io.InputStream() {
        override fun read(): Int {
            if (left <= 0) return -1
            val r = inner.read()
            if (r >= 0) left--
            return r
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (left <= 0) return -1
            val r = inner.read(b, off, minOf(len.toLong(), left).toInt())
            if (r > 0) left -= r
            return r
        }

        override fun close() = inner.close()
    }
}
