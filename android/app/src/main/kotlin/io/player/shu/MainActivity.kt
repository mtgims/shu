package io.player.shu

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// audio_service keeps the Flutter engine alive for background playback through this activity.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.player.shu/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> result.success(install(call.arguments as String))
                    // The torrent engine ships as a library: Android only runs programs there.
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
        val downloads = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.player.shu/downloads")
        DownloadService.onCancel = { downloads.invokeMethod("cancel", null) }
        downloads.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    askForNotifications()
                    try {
                        DownloadService.show(
                            applicationContext,
                            call.argument<String>("text") ?: "Downloading",
                            call.argument<Int>("percent"),
                            call.argument<String>("detail"),
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        // Android 12+ refuses to start it from the background; downloads go on.
                        result.error("service", e.message, null)
                    }
                }
                "stop" -> {
                    DownloadService.stop(applicationContext)
                    result.success(null)
                }
                // Also asked when playback starts: without it HyperOS hides the playback
                // notification, and the lock screen and quick settings controls with it.
                "askForNotifications" -> {
                    askForNotifications()
                    result.success(null)
                }
                // Driving mode: the screen stays on while it shows.
                "keepScreenOn" -> {
                    if (call.arguments as Boolean) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                // Driving mode's black screen: the backlight low (null: back to the system's).
                "screenBrightness" -> {
                    val value = (call.arguments as Number?)?.toFloat()
                    window.attributes = window.attributes.apply {
                        screenBrightness = value ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    }
                    result.success(null)
                }
                "metered" -> result.success(connectivity().isActiveNetworkMetered)
                "watchNetwork" -> {
                    watchNetwork(call.arguments as Boolean) { downloads.invokeMethod("network", null) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun connectivity() = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    /** Calls [changed] on the main thread when the network changes, while [on]. */
    private fun watchNetwork(on: Boolean, changed: () -> Unit) {
        networkCallback?.let { connectivity().unregisterNetworkCallback(it) }
        networkCallback = null
        if (!on) return
        val main = Handler(Looper.getMainLooper())
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                main.post(changed)
            }
        }.also { connectivity().registerDefaultNetworkCallback(it) }
    }

    private var askedForNotifications = false

    /** Notifications need this on Android 13+: the playback controls and the download progress. */
    private fun askForNotifications() {
        if (askedForNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedForNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    /**
     * Hands a downloaded update to the system installer. Answers "permission" when Android first
     * needs the user to allow installs from Shu (its settings page is opened for that).
     */
    private fun install(path: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            return "permission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return "started"
    }
}
