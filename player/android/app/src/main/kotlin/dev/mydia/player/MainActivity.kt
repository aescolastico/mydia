package dev.mydia.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dev.mydia.player/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateProgress" -> {
                        val notificationId = call.argument<Int>("notificationId") ?: 200
                        val title = call.argument<String>("title") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        val progress = call.argument<Int>("progress") ?: 0
                        val maxProgress = call.argument<Int>("maxProgress") ?: 100
                        val indeterminate = call.argument<Boolean>("indeterminate") ?: false

                        updateProgressNotification(
                            notificationId, title, text,
                            progress, maxProgress, indeterminate
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun updateProgressNotification(
        notificationId: Int,
        title: String,
        text: String,
        progress: Int,
        maxProgress: Int,
        indeterminate: Boolean
    ) {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channelId = "mydia_downloads"

        // Ensure channel exists (required for Android O+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = notificationManager.getNotificationChannel(channelId)
            if (existing == null) {
                val channel = NotificationChannel(
                    channelId,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Shows progress while downloading media files."
                    enableVibration(false)
                    setSound(null, null)
                    setShowBadge(false)
                }
                notificationManager.createNotificationChannel(channel)
            }
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setProgress(maxProgress, progress, indeterminate)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        notificationManager.notify(notificationId, notification)
    }
}
