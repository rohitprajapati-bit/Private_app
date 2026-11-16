package com.privateapp

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Wraps the vault master key with a hardware-backed Android Keystore key that can only be
 * used after a successful BiometricPrompt (CryptoObject). The wrapped blob is useless without
 * the Keystore key, which never leaves secure hardware.
 */
class BiometricKeyStore(private val activity: FragmentActivity) {
    private companion object {
        const val KEY_ALIAS = "color_match_vault_biometric"
        const val PREFS = "color_match_biometric"
        const val PREF_BLOB = "blob"
        const val PREF_IV = "iv"
        const val GCM_TAG_BITS = 128
    }

    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // Device credential + CryptoObject is only supported from Android 11.
    private val authenticators: Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BIOMETRIC_STRONG or DEVICE_CREDENTIAL
        else BIOMETRIC_STRONG

    fun status(): Map<String, Any> {
        val canAuth = BiometricManager.from(activity).canAuthenticate(authenticators)
        return mapOf(
            "available" to (canAuth == BiometricManager.BIOMETRIC_SUCCESS),
            "enabled" to (prefs.contains(PREF_BLOB) && keyStore().containsAlias(KEY_ALIAS)),
            "kind" to "biometric",
        )
    }

    fun enable(masterKey: ByteArray, title: String, cancel: String, result: MethodChannel.Result) {
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, createKey()) }
        } catch (e: Exception) {
            result.error("unavailable", null, null)
            return
        }
        authenticate(cipher, title, cancel, result) { authorized ->
            val blob = authorized.doFinal(masterKey)
            prefs.edit()
                .putString(PREF_BLOB, Base64.encodeToString(blob, Base64.NO_WRAP))
                .putString(PREF_IV, Base64.encodeToString(authorized.iv, Base64.NO_WRAP))
                .apply()
            masterKey.fill(0)
            null
        }
    }

    fun unlock(title: String, cancel: String, result: MethodChannel.Result) {
        val blob = prefs.getString(PREF_BLOB, null)
        val iv = prefs.getString(PREF_IV, null)
        val key = keyStore().getKey(KEY_ALIAS, null) as SecretKey?
        if (blob == null || iv == null || key == null) {
            result.error("notEnabled", null, null)
            return
        }
        val cipher = try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, Base64.decode(iv, Base64.NO_WRAP)))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometric enrollment changed: the key is gone for good. Password is still required.
            disable()
            result.error("invalidated", null, null)
            return
        } catch (e: Exception) {
            result.error("unavailable", null, null)
            return
        }
        authenticate(cipher, title, cancel, result) { authorized ->
            authorized.doFinal(Base64.decode(blob, Base64.NO_WRAP))
        }
    }

    fun disable() {
        prefs.edit().clear().apply()
        runCatching { keyStore().deleteEntry(KEY_ALIAS) }
    }

    private fun authenticate(
        cipher: Cipher,
        title: String,
        cancel: String,
        result: MethodChannel.Result,
        onAuthorized: (Cipher) -> ByteArray?,
    ) {
        var replied = false
        fun reply(block: () -> Unit) {
            if (!replied) {
                replied = true
                block()
            }
        }

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                val authorized = auth.cryptoObject?.cipher
                if (authorized == null) {
                    reply { result.error("failed", null, null) }
                    return
                }
                try {
                    val out = onAuthorized(authorized)
                    reply { result.success(out) }
                } catch (e: Exception) {
                    reply { result.error("failed", null, null) }
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val code = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                    else -> "failed"
                }
                reply { result.error(code, null, null) }
            }
        }

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(authenticators)
            .apply { if (authenticators and DEVICE_CREDENTIAL == 0) setNegativeButtonText(cancel) }
            .build()

        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun createKey(): SecretKey {
        keyStore().run { if (containsAlias(KEY_ALIAS)) deleteEntry(KEY_ALIAS) }
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Timeout 0 = every use of the key needs a fresh authentication.
                    setUserAuthenticationParameters(
                        0,
                        KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
                    )
                }
            }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }
            .generateKey()
    }
}
