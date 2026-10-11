package ru.pchekalin.workoutlog

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val rcVideo = 7711
    private val rcStorage = 7712
    private val rcPick = 7713

    // Состояние одной записи видео — живёт, пока открыта камера.
    private var videoResult: MethodChannel.Result? = null
    private var videoPendingToGallery = false
    private var videoPendingFile: File? = null
    private var videoPendingUri: Uri? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "workout/video")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "record" -> startRecordVideo(
                        call.argument<Boolean>("toGallery") ?: true, result
                    )
                    "pick" -> pickVideo(result)
                    "open" -> openVideo(call.argument<String>("path") ?: "", result)
                    "share" -> shareVideo(call.argument<String>("path") ?: "", result)
                    "delete" -> deleteVideo(call.argument<String>("path") ?: "", result)
                    else -> result.notImplemented()
                }
            }
    }

    // -----------------------------------------------------------------------
    // Видео
    // -----------------------------------------------------------------------

    /**
     * Открыть штатную камеру. Камера пишет в наш файл (EXTRA_OUTPUT) —
     * так сразу известен путь, ничего сканировать не надо.
     */
    private fun startRecordVideo(toGallery: Boolean, result: MethodChannel.Result) {
        if (videoResult != null) {
            result.error("busy", "Камера уже открыта", null)
            return
        }
        val intent = Intent(MediaStore.ACTION_VIDEO_CAPTURE)
        if (intent.resolveActivity(packageManager) == null) {
            result.error("no_camera", "На этом телефоне нет камеры", null)
            return
        }
        videoResult = result
        videoPendingToGallery = toGallery
        videoPendingFile = null
        videoPendingUri = null
        try {
            if (toGallery) {
                if (Build.VERSION.SDK_INT >= 29) {
                    // Android 10+: пишем через MediaStore, разрешения не нужны.
                    val values = ContentValues().apply {
                        put(
                            MediaStore.Video.Media.DISPLAY_NAME,
                            "WL_${System.currentTimeMillis()}.mp4"
                        )
                        put(
                            MediaStore.Video.Media.RELATIVE_PATH,
                            Environment.DIRECTORY_MOVIES + "/WorkoutLog"
                        )
                        put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                        put(MediaStore.Video.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values
                    )
                    if (uri == null) {
                        videoResult = null
                        result.error("storage", "Не удалось создать файл в Галерее", null)
                        return
                    }
                    videoPendingUri = uri
                    intent.putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    intent.addFlags(
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } else {
                    // Android 8-9: в общую Галерею — только с разрешением.
                    if (ContextCompat.checkSelfPermission(
                            this, Manifest.permission.WRITE_EXTERNAL_STORAGE
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                            rcStorage
                        )
                        return // продолжим в onRequestPermissionsResult
                    }
                    prepareLegacyGallery(intent)
                }
            } else {
                // Память приложения: своя папка, разрешений не просим.
                val dir = getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir
                File(dir, "WorkoutLog").mkdirs()
                val f = File(dir, "WorkoutLog/WL_${System.currentTimeMillis()}.mp4")
                videoPendingFile = f
                intent.putExtra(MediaStore.EXTRA_OUTPUT, contentUriFor(f))
                intent.addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
            startActivityForResult(intent, rcVideo)
        } catch (e: ActivityNotFoundException) {
            videoResult = null
            cleanupPending()
            result.error("no_camera", "На этом телефоне нет камеры", null)
        } catch (e: Exception) {
            videoResult = null
            cleanupPending()
            result.error("camera", e.message, null)
        }
    }

    /**
     * Выбрать уже записанное видео из Галереи. Используем ACTION_PICK по
     * MediaStore (а не документ-выборщик): тот возвращает обычный адрес
     * `content://media/...`, который телефоны открывают в плеере без
     * сучка. Сам файл не трогаем — в журнал кладём только адрес.
     */
    private fun pickVideo(result: MethodChannel.Result) {
        if (videoResult != null) {
            result.error("busy", "Окно уже открыто", null)
            return
        }
        val intent = Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI).apply {
            type = "video/*"
            putExtra(
                "android.intent.extra.MIME_TYPES",
                arrayOf("video/mp4", "video/3gpp", "video/quicktime", "video/x-matroska")
            )
        }
        videoResult = result
        try {
            startActivityForResult(intent, rcPick)
        } catch (e: ActivityNotFoundException) {
            videoResult = null
            result.error("pick", "Не получилось открыть выбор видео", null)
        }
    }

    /** Android 8-9, Галерея: готовим файл в публичной папке Movies/WorkoutLog. */
    private fun prepareLegacyGallery(intent: Intent) {
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val dir = File(base, "WorkoutLog")
        dir.mkdirs()
        val f = File(dir, "WL_${System.currentTimeMillis()}.mp4")
        videoPendingFile = f
        intent.putExtra(MediaStore.EXTRA_OUTPUT, contentUriFor(f))
        intent.addFlags(
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == rcPick) {
            val res = videoResult ?: return
            videoResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                res.success(null)
                return
            }
            try {
                // Просим долгое разрешение читать этот файл (на случай
                // перезагрузки телефона — ссылка должна остаться рабочей).
                contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Некоторые провайдеры не дают долгого разрешения —
                // файл всё равно откроется, пока телефон не перезагрузят.
            }
            res.success(uri.toString())
            return
        }
        if (requestCode != rcVideo) return
        val res = videoResult ?: return
        videoResult = null
        if (resultCode != Activity.RESULT_OK) {
            cleanupPending()
            res.success(null)
            return
        }
        try {
            val uri = videoPendingUri
            val file = videoPendingFile
            val out: String? = when {
                uri != null -> {
                    // Снимаем флаг «в процессе» — видео появится в Галерее.
                    contentResolver.update(
                        uri,
                        ContentValues().apply {
                            put(MediaStore.Video.Media.IS_PENDING, 0)
                        },
                        null, null
                    )
                    uri.toString()
                }
                file != null -> {
                    if (videoPendingToGallery) {
                        // Android 8-9: показать файл в Галерее сразу.
                        MediaScannerConnection.scanFile(
                            this, arrayOf(file.absolutePath), arrayOf("video/mp4"), null
                        )
                    }
                    file.absolutePath
                }
                else -> null
            }
            videoPendingUri = null
            videoPendingFile = null
            res.success(out)
        } catch (e: Exception) {
            res.error("save", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != rcStorage) return
        val res = videoResult ?: return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            try {
                val intent = Intent(MediaStore.ACTION_VIDEO_CAPTURE)
                prepareLegacyGallery(intent)
                startActivityForResult(intent, rcVideo)
            } catch (e: Exception) {
                videoResult = null
                res.error("camera", e.message, null)
            }
        } else {
            videoResult = null
            res.error("permission", "Нет разрешения сохранять видео в Галерею", null)
        }
    }

    /** Удалить файл, созданный, но не записанный (отмена или ошибка). */
    private fun cleanupPending() {
        try {
            videoPendingUri?.let { contentResolver.delete(it, null, null) }
            videoPendingFile?.let { if (it.exists()) it.delete() }
        } catch (_: Exception) {
        }
        videoPendingUri = null
        videoPendingFile = null
    }

    private fun openVideo(path: String, result: MethodChannel.Result) {
        try {
            val uri = pathToUri(path)
            android.util.Log.w(
                "WorkoutVideo", "open: path=$path uri=$uri exists=" +
                    (if (path.startsWith("content://")) "?" else File(path).exists().toString())
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "video/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            // Сначала пробуем открыть напрямую; если плеер сам не нашёлся —
            // показываем список приложений.
            try {
                startActivity(intent)
            } catch (e: ActivityNotFoundException) {
                startActivity(Intent.createChooser(intent, "Открыть видео"))
            }
            result.success(null)
        } catch (e: Exception) {
            android.util.Log.e("WorkoutVideo", "open failed", e)
            result.error("open", "Не получилось открыть видео: ${e.message}", null)
        }
    }

    private fun shareVideo(path: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "video/*"
                putExtra(Intent.EXTRA_STREAM, pathToUri(path))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Поделиться видео"))
            result.success(null)
        } catch (e: Exception) {
            result.error("share", "Не получилось поделиться видео", null)
        }
    }

    private fun deleteVideo(path: String, result: MethodChannel.Result) {
        try {
            val ok = if (path.startsWith("content://")) {
                contentResolver.delete(Uri.parse(path), null, null) > 0
            } else {
                val f = File(path)
                f.exists() && f.delete()
            }
            result.success(ok)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun contentUriFor(file: File): Uri =
        FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

    private fun pathToUri(path: String): Uri =
        if (path.startsWith("content://")) Uri.parse(path) else contentUriFor(File(path))

    // -----------------------------------------------------------------------
    // Таймер отдыха
    // -----------------------------------------------------------------------

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
