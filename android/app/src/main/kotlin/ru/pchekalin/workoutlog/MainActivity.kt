package ru.pchekalin.workoutlog

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "workout/timer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    "notifyEnd" -> {
                        vibrateNow()
                        beepNow()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Две короткие вибрации, чтобы не смотреть на экран. */
    private fun vibrateNow() {
        try {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator ?: return
            if (vibrator.hasVibrator()) {
                vibrator.vibrate(VibrationEffect.createOneShot(300, 220))
                Handler(Looper.getMainLooper()).postDelayed({
                    vibrator.vibrate(VibrationEffect.createOneShot(300, 220))
                }, 450)
            }
        } catch (_: Exception) {
        }
    }

    /** Два сигнальных «бипа» через штатный генератор тонов. */
    private fun beepNow() {
        try {
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP, 250)
            Handler(Looper.getMainLooper()).postDelayed({
                tg.startTone(ToneGenerator.TONE_PROP_BEEP, 250)
                tg.release()
            }, 450)
        } catch (_: Exception) {
        }
    }
}
