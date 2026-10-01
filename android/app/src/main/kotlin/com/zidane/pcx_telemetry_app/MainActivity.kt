package com.zidane.pcx_telemetry_app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity: FlutterActivity(), TextToSpeech.OnInitListener {
    private val CHANNEL = "com.zidane.pcx_telemetry_app/tts"
    private val ACTION_CHANNEL = "com.zidane.pcx_telemetry_app/actions"
    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep screen alive 100% while app is running on motorcycle cockpit
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tts = TextToSpeech(this, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "speak") {
                val text = call.argument<String>("text") ?: ""
                if (isTtsReady && text.isNotEmpty()) {
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "pcx_alert_${System.currentTimeMillis()}")
                    result.success(true)
                } else {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }

        // Sprint 4: share the ride report and open an SMS draft.
        // Zero added dependencies -- a MethodChannel in the existing
        // MainActivity, same pattern as the TTS channel above.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheDir" -> {
                    result.success(cacheDir.absolutePath)
                }
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val subject = call.argument<String>("subject") ?: ""
                    if (path == null) {
                        result.error("no_path", "path argument is required", null)
                    } else {
                        result.success(shareFile(path, mime, subject))
                    }
                }
                "smsDraft" -> {
                    val number = call.argument<String>("number") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    result.success(openSmsDraft(number, body))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun shareFile(path: String, mime: String, subject: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false

            // FileProvider is required from Android 7 (Nougat) onward: passing a
            // file:// URI to another app throws FileUriExposedException. The
            // provider is declared in AndroidManifest.xml with a cache-path.
            val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                if (subject.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(sendIntent, "Bagikan Laporan"))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openSmsDraft(number: String, body: String): Boolean {
        return try {
            // smsto: opens the composer pre-filled. It never sends on its own,
            // which is deliberate: the crash path must always leave the rider in
            // control of whether a message actually goes out.
            val uri = Uri.parse("smsto:$number").buildUpon().appendQueryParameter("body", body).build()
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val res = tts?.setLanguage(Locale("id", "ID"))
            if (res == TextToSpeech.LANG_MISSING_DATA || res == TextToSpeech.LANG_NOT_SUPPORTED) {
                tts?.setLanguage(Locale.US)
            }
            isTtsReady = true
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
