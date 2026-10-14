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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity нужен health-плагину (запрос разрешений Health Connect).
class MainActivity : FlutterFragmentActivity() {
    private val rcVideo = 7711
    private val rcStorage = 7712
    private val rcPick = 7713
    private val rcMedia = 7714
    private val rcHealthPerm = 7715

    // Ожидание ответа окна разрешений Health Connect.
    private var healthPermResult: MethodChannel.Result? = null

    // Состояние одной записи видео — живёт, пока открыта камера.
    private var videoResult: MethodChannel.Result? = null
    private var videoPendingToGallery = false
    private var videoPendingFile: File? = null
    private var videoPendingUri: Uri? = null

    // Отложенное действие, пока человек отвечает на запрос разрешения.
    private var mediaAction: (() -> Unit)? = null
    private var mediaResult: MethodChannel.Result? = null

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

        // Запрос разрешений Health Connect СВОИМ окном (решение 14.10:
        // на Realme штатный запрос пакета health шлёт новое действие
        // androidx.health.*, которого контроллер прошивки не знает — окно
        // не открывается). Классическое действие работает везде.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "workout/health")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermissions" -> {
                        if (healthPermResult != null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent("android.health.connect.action.REQUEST_HEALTH_PERMISSIONS")
                                .setPackage("com.google.android.healthconnect.controller")
                                .putExtra(
                                    "androidx.health.extra.PERMISSIONS_LIST",
                                    arrayOf(
                                        "android.permission.health.READ_STEPS",
                                        "android.permission.health.READ_HEART_RATE"
                                    )
                                )
                            healthPermResult = result
                            startActivityForResult(intent, rcHealthPerm)
                        } catch (e: Exception) {
                            healthPermResult = null
                            result.success(false)
                        }
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
                    "pick" -> withMediaPermission(result) { pickVideo(result) }
                    "open" -> {
                        val path = call.argument<String>("path") ?: ""
                        if (path.startsWith("content://")) {
                            withMediaPermission(result) { openVideo(path, result) }
                        } else {
                            openVideo(path, result)
                        }
                    }
                    "share" -> {
                        val path = call.argument<String>("path") ?: ""
                        if (path.startsWith("content://")) {
                            withMediaPermission(result) { shareVideo(path, result) }
                        } else {
                            shareVideo(path, result)
                        }
                    }
                    "delete" -> deleteVideo(call.argument<String>("path") ?: "", result)
                    else -> result.notImplemented()
                }
            }
    }

    // -----------------------------------------------------------------------
    // Видео
    // -----------------------------------------------------------------------

    /**
     * Android 13+ (и частично ниже) требует разрешение на доступ к видео
     * из Галереи. Спрашиваем один раз; пока человек отвечает — держим
     * действие, после «Разрешить» выполняем.
     */
    private fun withMediaPermission(
        result: MethodChannel.Result, action: () -> Unit
    ) {
        val needed = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (ContextCompat.checkSelfPermission(this, needed)
            == PackageManager.PERMISSION_GRANTED
        ) {
            action()
            return
        }
        if (mediaAction != null) {
            result.error("busy", "Окно уже открыто", null)
            return
        }
        mediaAction = action
        mediaResult = result
        ActivityCompat.requestPermissions(this, arrayOf(needed), rcMedia)
    }

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
        if (requestCode == rcHealthPerm) {
            val res = healthPermResult
            healthPermResult = null
            // RESULT_OK — человек выдал доступ; при отмене/«назад» всё
            // равно false — Dart перепроверит фактический доступ сам.
            res?.success(resultCode == Activity.RESULT_OK)
            return
        }
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
        if (requestCode == rcMedia) {
            val action = mediaAction
            val res = mediaResult
            mediaAction = null
            mediaResult = null
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                action?.invoke()
            } else {
                res?.error(
                    "permission",
                    "Нет разрешения читать видео из Галереи. Разрешите доступ "
                        + "к видео в настройках приложения.", null
                )
            }
            return
        }
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
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "video/*")
            }
            // Сначала пробуем «одолжить» плееру доступ (нужно для наших
            // файлов). Если система запретила (частый случай с видео из
            // Галереи) — открываем без одолжения: плеер телефона сам имеет
            // доступ к галерее.
            try {
                startActivity(
                    Intent(view).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                )
            } catch (e: SecurityException) {
                startActivity(view)
            } catch (e: ActivityNotFoundException) {
                startActivity(
                    Intent.createChooser(view, "Открыть видео")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                )
            }
            result.success(null)
        } catch (e: Exception) {
            android.util.Log.e("WorkoutVideo", "open failed", e)
            result.error("open", "Не получилось открыть видео: ${e.message}", null)
        }
    }

    private fun shareVideo(path: String, result: MethodChannel.Result) {
        try {
            val uri = pathToUri(path)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "video/*"
                putExtra(Intent.EXTRA_STREAM, uri)
            }
            try {
                startActivity(
                    Intent.createChooser(send, "Поделиться видео")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                )
            } catch (e: SecurityException) {
                startActivity(Intent.createChooser(send, "Поделиться видео"))
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("share", "Не получилось поделиться видео: ${e.message}", null)
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
