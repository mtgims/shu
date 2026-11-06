package io.player.shu

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps Shu running while it downloads books with the screen off, with a notification that
 * shows how far it got and a Cancel button. Dart starts, updates and stops it through
 * MainActivity's "io.player.shu/downloads" channel.
 */
class DownloadService : Service() {
    companion object {
        private const val CHANNEL = "io.player.shu.downloads"
        private const val ID = 7
        private const val CANCEL = "cancel"

        /** Whether the service runs: updates then go straight to the notification. */
        var running = false
            private set

        /** The notification's Cancel button, passed on to Dart. */
        var onCancel: (() -> Unit)? = null

        fun show(context: Context, text: String, percent: Int?, detail: String?) {
            if (running) {
                notificationManager(context).notify(ID, notification(context, text, percent, detail))
                return
            }
            val intent = Intent(context, DownloadService::class.java)
                .putExtra("text", text)
                .putExtra("percent", percent ?: -1)
                .putExtra("detail", detail)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        // Also when not running yet: a start may be on its way.
        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }

        private fun notificationManager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        private fun notification(context: Context, text: String, percent: Int?, detail: String?) =
            NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_shu)
                .setContentTitle(text)
                .setContentText(detail)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setProgress(100, percent ?: 0, percent == null)
                .setContentIntent(
                    PendingIntent.getActivity(
                        context,
                        0,
                        context.packageManager.getLaunchIntentForPackage(context.packageName),
                        PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
                .addAction(
                    0,
                    "Cancel",
                    PendingIntent.getService(
                        context,
                        1,
                        Intent(context, DownloadService::class.java).setAction(CANCEL),
                        PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
                .build()
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    @SuppressLint("WakelockTimeout") // Released when the downloads end; Android caps the service.
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager(this).createNotificationChannel(
                NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW),
            )
        }
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Shu:downloads")
            .apply { acquire() }
        @Suppress("DEPRECATION") // The replacement (low latency) is not what a download needs.
        wifiLock = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
            .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Shu:downloads")
            .apply { acquire() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == CANCEL) {
            onCancel?.invoke()
            return START_NOT_STICKY
        }
        val percent = intent?.getIntExtra("percent", -1)?.takeIf { it >= 0 }
        ServiceCompat.startForeground(
            this,
            ID,
            notification(
                this,
                intent?.getStringExtra("text") ?: "Downloading",
                percent,
                intent?.getStringExtra("detail"),
            ),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )
        running = true
        // Gone with the app: downloads pick up again when Shu next starts.
        return START_NOT_STICKY
    }

    // Android 15 allows data sync services 6 hours a day; downloads go on at the next start.
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    override fun onDestroy() {
        running = false
        wakeLock?.release()
        wifiLock?.release()
        super.onDestroy()
    }
}
