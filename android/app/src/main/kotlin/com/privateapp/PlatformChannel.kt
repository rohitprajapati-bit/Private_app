package com.privateapp

import android.view.WindowManager
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Dart <-> Kotlin bridge. Method names and error codes must match
 * lib/platform/platform_channel.dart.
 */
class PlatformChannel(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "color_match/platform"
    }

    private val biometricKeys = BiometricKeyStore(activity)
    private val galleryPicker = GalleryPicker(activity)
    private val background = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "biometricStatus" -> result.success(biometricKeys.status())
            "biometricEnable" -> biometricKeys.enable(
                masterKey = call.argument<ByteArray>("key")!!,
                title = call.argument<String>("title") ?: "",
                cancel = call.argument<String>("cancel") ?: "",
                result = result,
            )
            "biometricUnlock" -> biometricKeys.unlock(
                title = call.argument<String>("title") ?: "",
                cancel = call.argument<String>("cancel") ?: "",
                result = result,
            )
            "biometricDisable" -> {
                biometricKeys.disable()
                result.success(null)
            }
            "setSecureScreen" -> {
                if (call.argument<Boolean>("enabled") == true) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            "mediaInfo" -> {
                val path = call.argument<String>("path")!!
                val isVideo = call.argument<Boolean>("isVideo") == true
                val maxSize = call.argument<Int>("maxSize") ?: 400
                background.execute {
                    val info = try {
                        MediaThumbnailer.describe(path, isVideo, maxSize)
                    } catch (e: Exception) {
                        null
                    }
                    activity.runOnUiThread { result.success(info) }
                }
            }
            // Android decodes HEIF natively through Flutter's platform decoder; nothing to do.
            "transcodeToJpeg" -> result.success(null)
            "pickMedia" -> galleryPicker.pick(call.argument<Boolean>("video") == true, result)
            "deleteOriginals" -> galleryPicker.deleteOriginals(call.argument<List<String>>("ids") ?: emptyList(), result)
            // Android backup is disabled in the manifest.
            "excludeFromBackup" -> result.success(null)
            else -> result.notImplemented()
        }
    }
}
