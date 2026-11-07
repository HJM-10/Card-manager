package com.example.my_app

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** No plaintext credential is written to disk. Every encrypt/decrypt operation
 * requires a strong biometric through a Keystore-backed CryptoObject. */
class BiometricVault(private val activity: FragmentActivity) {
    private val alias = "spendtrail.biometric.v1"
    private val file = AtomicFile(File(activity.noBackupFilesDir, "biometric-session.json"))
    private var pending: MethodChannel.Result? = null
    private var prompt: BiometricPrompt? = null
    private val strong = BiometricManager.Authenticators.BIOMETRIC_STRONG

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A fingerprint check is already in progress.", null)
            return
        }
        try {
            when (call.method) {
                "status" -> result.success(mapOf(
                    "available" to (BiometricManager.from(activity).canAuthenticate(strong) == BiometricManager.BIOMETRIC_SUCCESS),
                    "saved" to file.baseFile.exists()
                ))
                "clear" -> { clear(); result.success(null) }
                "save" -> {
                    val token = requireNotNull(call.argument<String>("token"))
                    val server = requireNotNull(call.argument<String>("server"))
                    require(token.length in 32..128 && server.isNotBlank())
                    clear()
                    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                    val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setUserAuthenticationRequired(true)
                        .setInvalidatedByBiometricEnrollment(true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                    } else {
                        builder.setUserAuthenticationValidityDurationSeconds(-1)
                    }
                    generator.init(builder.build())
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, generator.generateKey())
                    authenticate(cipher, result, true) { unlocked ->
                        val payload = JSONObject().put("token", token).put("server", server).toString().toByteArray(Charsets.UTF_8)
                        val ciphertext = unlocked.doFinal(payload)
                        val encoded = JSONObject().put("iv", encode(unlocked.iv)).put("ciphertext", encode(ciphertext)).toString().toByteArray(Charsets.UTF_8)
                        val output = file.startWrite()
                        try { output.write(encoded); file.finishWrite(output) }
                        catch (error: Exception) { file.failWrite(output); throw error }
                        null
                    }
                }
                "unlock" -> {
                    val server = requireNotNull(call.argument<String>("server"))
                    val saved = JSONObject(String(file.readFully(), Charsets.UTF_8))
                    val key = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.getKey(alias, null) as? SecretKey
                        ?: throw IllegalStateException("Saved fingerprint login is no longer available.")
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, decode(saved.getString("iv"))))
                    authenticate(cipher, result, false) { unlocked ->
                        val payload = JSONObject(String(unlocked.doFinal(decode(saved.getString("ciphertext"))), Charsets.UTF_8))
                        check(payload.getString("server") == server) { "The saved login belongs to a different server." }
                        payload.getString("token")
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            if (call.method == "save" || call.method == "unlock") clear()
            result.error("unavailable", "Fingerprint login is unavailable. Sign in with your password and enable it again.", null)
        }
    }

    private fun authenticate(cipher: Cipher, result: MethodChannel.Result, enrolling: Boolean, action: (Cipher) -> Any?) {
        pending = result
        prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationError(code: Int, message: CharSequence) {
                val callback = pending ?: return
                pending = null
                if (enrolling) clear()
                val cancelled = code == BiometricPrompt.ERROR_NEGATIVE_BUTTON || code == BiometricPrompt.ERROR_USER_CANCELED || code == BiometricPrompt.ERROR_CANCELED
                callback.error(if (cancelled) "cancelled" else "authentication", if (cancelled) "Fingerprint check cancelled. You can use your password." else message.toString(), null)
            }
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                val callback = pending ?: return
                pending = null
                try {
                    callback.success(action(requireNotNull(auth.cryptoObject?.cipher)))
                } catch (error: Exception) {
                    clear()
                    callback.error("unavailable", "Saved login could not be unlocked. Please use your password.", null)
                }
            }
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(if (enrolling) "Enable fingerprint login" else "Sign in to SpendTrail")
            .setSubtitle("Use your fingerprint to unlock your saved login")
            .setAllowedAuthenticators(strong)
            .setNegativeButtonText("Use password")
            .build()
        try { prompt!!.authenticate(info, BiometricPrompt.CryptoObject(cipher)) }
        catch (error: Exception) { pending = null; throw error }
    }

    private fun encode(value: ByteArray) = Base64.encodeToString(value, Base64.NO_WRAP)
    private fun decode(value: String) = Base64.decode(value, Base64.NO_WRAP)
    private fun clear() {
        file.delete()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry(alias) }
    }
    fun cancel() {
        prompt?.cancelAuthentication()
    }
}
