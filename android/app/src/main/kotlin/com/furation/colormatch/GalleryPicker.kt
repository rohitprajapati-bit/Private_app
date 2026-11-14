package com.furation.colormatch

import android.app.Activity
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Picks photos/videos through the system document picker and can later delete the originals.
 *
 * The newer Android photo picker hands out read-only URIs that can never be deleted, so the
 * document picker is used instead: its media URIs map back to MediaStore entries, which
 * MediaStore.createDeleteRequest (Android 11+) can remove after the user confirms.
 */
class GalleryPicker(private val activity: FragmentActivity) {
    private val io = Executors.newSingleThreadExecutor()
    private val keys = AtomicInteger()

    fun pick(video: Boolean, result: MethodChannel.Result) {
        val mime = if (video) "video/*" else "image/*"
        launch(ActivityResultContracts.OpenMultipleDocuments(), arrayOf(mime)) { uris ->
            if (uris.isEmpty()) {
                result.success(emptyList<Map<String, String>>())
                return@launch
            }
            // Copying large videos can take a while: keep it off the main thread.
            io.execute {
                val picked = uris.mapNotNull { copyToCache(it, video) }
                activity.runOnUiThread { result.success(picked) }
            }
        }
    }

    fun deleteOriginals(ids: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error("unsupported", null, null)
            return
        }
        val uris = ids.mapNotNull { id ->
            // Fails for documents that are not media items (e.g. cloud files): those are kept.
            runCatching { MediaStore.getMediaUri(activity, Uri.parse(id)) }.getOrNull()
        }
        if (uris.isEmpty()) {
            result.success(0)
            return
        }
        val request = try {
            MediaStore.createDeleteRequest(activity.contentResolver, uris)
        } catch (e: Exception) {
            result.error("failed", null, null)
            return
        }
        // Android shows its own "Allow Color Match to delete N items?" dialog.
        launch(
            ActivityResultContracts.StartIntentSenderForResult(),
            IntentSenderRequest.Builder(request.intentSender).build(),
        ) { outcome ->
            if (outcome.resultCode == Activity.RESULT_OK) {
                result.success(uris.size)
            } else {
                result.error("cancelled", null, null)
            }
        }
    }

    private fun copyToCache(uri: Uri, video: Boolean): Map<String, String>? = try {
        val resolver = activity.contentResolver
        var name: String? = null
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0)
        }
        val fileName = name ?: "item.${if (video) "mp4" else "jpg"}"
        // cache/<uuid>/name — the layout startup clean-up removes after a crash.
        val dir = File(activity.cacheDir, UUID.randomUUID().toString()).apply { mkdirs() }
        val dest = File(dir, fileName.replace('/', '_'))
        resolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output -> input.copyTo(output, 1024 * 1024) }
        } ?: throw IllegalStateException("unreadable")
        mapOf(
            "path" to dest.absolutePath,
            "name" to fileName.substringBeforeLast('.'),
            "sourceId" to uri.toString(),
        )
    } catch (e: Exception) {
        null
    }

    private fun <I, O> launch(contract: ActivityResultContract<I, O>, input: I, callback: (O) -> Unit) {
        var launcher: ActivityResultLauncher<I>? = null
        launcher = activity.activityResultRegistry.register("color_match_${keys.incrementAndGet()}", contract) {
            launcher?.unregister()
            callback(it)
        }
        launcher.launch(input)
    }
}
