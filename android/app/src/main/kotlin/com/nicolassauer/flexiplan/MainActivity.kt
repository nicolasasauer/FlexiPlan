package com.nicolassauer.flexiplan

import android.media.AudioManager
import android.media.ToneGenerator
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Kleiner nativer Kanal statt zusätzlicher Plugins (Lastenheft 2.4/3.1):
/// - keepScreenOn: Display während des Workouts wach halten (Wake-Lock
///   auf Fenster-Ebene, keine Permission nötig)
/// - beep: Timer-Signale über den System-ToneGenerator (kein Audio-Asset,
///   respektiert die Medienlautstärke)
class MainActivity : FlutterActivity() {
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flexiplan/native"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    val on = call.arguments as? Boolean ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "beep" -> {
                    try {
                        val tg = toneGenerator ?: ToneGenerator(
                            AudioManager.STREAM_MUSIC, 80
                        ).also { toneGenerator = it }
                        when (call.arguments as? String) {
                            "start" -> tg.startTone(ToneGenerator.TONE_PROP_ACK, 200)
                            "end" -> tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 400)
                            else -> tg.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                        }
                    } catch (_: RuntimeException) {
                        // Kein Audio-Ausgang o. ä.: Signal einfach auslassen.
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }
}
