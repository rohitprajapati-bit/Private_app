package com.privateapp

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max

/**
 * Builds a small JPEG thumbnail plus basic metadata for a plaintext picker file.
 * Runs before the file is encrypted; the thumbnail itself is encrypted by Dart.
 */
object MediaThumbnailer {
    fun describe(path: String, isVideo: Boolean, maxSize: Int): Map<String, Any?> =
        if (isVideo) describeVideo(path, maxSize) else describeImage(path, maxSize)

    private fun describeVideo(path: String, maxSize: Int): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                width = height.also { height = width }
            }
            val frameTimeUs = if (duration != null && duration > 2000) 1_000_000L else 0L
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxSize, maxSize)
            } else {
                retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { scale(it, maxSize) }
            }
            return mapOf(
                "thumbnail" to frame?.let { jpeg(it) },
                "durationMs" to duration,
                "width" to width,
                "height" to height,
            )
        } finally {
            retriever.release()
        }
    }

    private fun describeImage(path: String, maxSize: Int): Map<String, Any?> {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)

        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // ImageDecoder handles HEIF and applies EXIF orientation itself.
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { decoder, info, _ ->
                val longest = max(info.size.width, info.size.height)
                if (longest > maxSize) decoder.setTargetSampleSize(longest / maxSize)
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }.let { scale(it, maxSize) }
        } else {
            val sample = max(1, max(bounds.outWidth, bounds.outHeight) / maxSize)
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?.let { rotateForExif(it, path) }
                ?.let { scale(it, maxSize) }
        }

        var width = bounds.outWidth.takeIf { it > 0 }
        var height = bounds.outHeight.takeIf { it > 0 }
        val orientation = runCatching {
            ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        if (orientation == ExifInterface.ORIENTATION_ROTATE_90 || orientation == ExifInterface.ORIENTATION_ROTATE_270) {
            width = height.also { height = width }
        }
        return mapOf(
            "thumbnail" to bitmap?.let { jpeg(it) },
            "durationMs" to null,
            "width" to width,
            "height" to height,
        )
    }

    private fun rotateForExif(bitmap: Bitmap, path: String): Bitmap {
        val degrees = when (
            runCatching { ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 0) }.getOrDefault(0)
        ) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
    }

    private fun scale(bitmap: Bitmap, maxSize: Int): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (longest <= maxSize) return bitmap
        val ratio = maxSize.toFloat() / longest
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * ratio).toInt(), (bitmap.height * ratio).toInt(), true)
    }

    private fun jpeg(bitmap: Bitmap): ByteArray =
        ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it)
            it.toByteArray()
        }
}
