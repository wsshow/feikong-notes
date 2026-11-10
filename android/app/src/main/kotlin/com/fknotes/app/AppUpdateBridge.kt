package com.fknotes.app

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.floor

/** Verifies downloaded APKs before handing them to Android's package installer. */
internal class AppUpdateBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    private companion object {
        const val CHANNEL = "fknotes/app_update"
        const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var openRequested = activity.intent?.getBooleanExtra(AppUpdateDownloads.OPEN_UPDATE, false) == true

    init {
        channel.setMethodCallHandler(::handle)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    fun onIntent(intent: Intent) {
        if (!intent.getBooleanExtra(AppUpdateDownloads.OPEN_UPDATE, false)) return
        openRequested = true
        channel.invokeMethod("openUpdate", null)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumeUpdateLaunch" -> {
                result.success(openRequested)
                openRequested = false
                activity.intent?.removeExtra(AppUpdateDownloads.OPEN_UPDATE)
            }
            "startUpdateDownload", "getUpdateDownload", "materializeUpdateDownload", "clearUpdateDownload" ->
                AppUpdateDownloads.executor.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "startUpdateDownload" -> AppUpdateDownloads.start(activity.applicationContext, call.arguments)
                            "getUpdateDownload" -> AppUpdateDownloads.snapshot(activity.applicationContext)
                            "materializeUpdateDownload" -> AppUpdateDownloads.materialize(activity.applicationContext,
                                (call.arguments as Number).toLong())
                            else -> { AppUpdateDownloads.clear(activity.applicationContext); null }
                        }
                        postSuccess(result, value)
                    } catch (error: Exception) {
                        postError(result, "UPDATE_DOWNLOAD_FAILED", error.message, error)
                    }
                }
            "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "canInstallUpdates" ->
                result.success(mapOf("allowed" to canRequestPackageInstalls()))
            "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
            "verifyUpdate" -> executor.execute {
                try {
                    val update = verify(call.arguments)
                    postSuccess(
                        result,
                        mapOf(
                            "packageName" to update.packageName,
                            "versionCode" to update.versionCode,
                        ),
                    )
                } catch (error: UpdateException) {
                    postError(result, error.code, error.message)
                } catch (error: Exception) {
                    postError(
                        result,
                        "UPDATE_VERIFY_FAILED",
                        "The downloaded update could not be verified.",
                        error,
                    )
                }
            }
            "installUpdate" -> executor.execute {
                try {
                    if (!canRequestPackageInstalls()) {
                        throw UpdateException(
                            "INSTALL_PERMISSION_REQUIRED",
                            "Install permission is required.",
                        )
                    }
                    val update = verify(call.arguments)
                    launchInstaller(update, result)
                } catch (error: UpdateException) {
                    postError(result, error.code, error.message)
                } catch (error: Exception) {
                    postError(
                        result,
                        "UPDATE_INSTALL_FAILED",
                        "The update installer could not be opened.",
                        error,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || canRequestPackageInstalls()) {
            result.success(null)
            return
        }
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "INSTALL_PERMISSION_SETTINGS_FAILED",
                "The install permission settings could not be opened.",
                error.message,
            )
        }
    }

    private fun canRequestPackageInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun verify(arguments: Any?): VerifiedUpdate {
        val values = arguments as? Map<*, *>
            ?: throw UpdateException("INVALID_UPDATE_REQUEST", "Update verification data is missing.")
        val path = values["path"] as? String
        val expectedSha256 = values["sha256"] as? String
        val expectedPackageName = values["packageName"] as? String
        val expectedSize = integralLong(values["size"])
        val expectedVersionCode = integralLong(values["versionCode"])

        if (
            path.isNullOrBlank() || expectedSha256.isNullOrBlank() ||
            expectedPackageName.isNullOrBlank() || expectedSize == null || expectedSize < 1 ||
            expectedVersionCode == null || expectedVersionCode < 1
        ) {
            throw UpdateException("INVALID_UPDATE_REQUEST", "Update verification data is incomplete.")
        }
        if (!expectedSha256.matches(Regex("(?i)[0-9a-f]{64}"))) {
            throw UpdateException("INVALID_UPDATE_REQUEST", "The expected checksum is invalid.")
        }
        if (expectedPackageName != activity.packageName) {
            throw UpdateException("PACKAGE_MISMATCH", "The update package name is invalid.")
        }

        val updateFile = resolveCacheFile(path)
        if (!updateFile.isFile) {
            throw UpdateException("UPDATE_FILE_MISSING", "The downloaded update file is missing.")
        }
        if (updateFile.length() != expectedSize) {
            throw UpdateException("UPDATE_SIZE_MISMATCH", "The downloaded update size does not match.")
        }
        if (sha256(updateFile) != expectedSha256.lowercase(Locale.ROOT)) {
            throw UpdateException(
                "UPDATE_CHECKSUM_MISMATCH",
                "The downloaded update checksum does not match.",
            )
        }

        val packageManager = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        @Suppress("DEPRECATION")
        val archiveInfo = packageManager.getPackageArchiveInfo(updateFile.absolutePath, flags)
        @Suppress("DEPRECATION")
        val currentInfo = packageManager.getPackageInfo(activity.packageName, flags)
        if (archiveInfo == null || archiveInfo.packageName != expectedPackageName) {
            throw UpdateException("PACKAGE_MISMATCH", "The downloaded APK belongs to another app.")
        }

        val archiveVersionCode = versionCode(archiveInfo)
        val currentVersionCode = versionCode(currentInfo)
        if (archiveVersionCode != expectedVersionCode || archiveVersionCode <= currentVersionCode) {
            throw UpdateException(
                "VERSION_MISMATCH",
                "The downloaded APK version is not newer than this app.",
            )
        }
        if (!sameSigners(currentInfo, archiveInfo)) {
            throw UpdateException(
                "SIGNATURE_MISMATCH",
                "The downloaded APK signature does not match this app.",
            )
        }
        return VerifiedUpdate(updateFile, archiveInfo.packageName, archiveVersionCode)
    }

    private fun resolveCacheFile(value: String): File {
        val uri = Uri.parse(value)
        if (uri.scheme != null && !uri.scheme.equals("file", ignoreCase = true)) {
            throw UpdateException("INVALID_UPDATE_PATH", "Only private cache files can be installed.")
        }
        val path = if (uri.scheme == null) value else uri.path
        if (path.isNullOrBlank()) {
            throw UpdateException("INVALID_UPDATE_PATH", "The update path is invalid.")
        }
        val cacheRoot = activity.cacheDir.canonicalFile
        val candidate = File(path).canonicalFile
        val cachePrefix = cacheRoot.path + File.separator
        if (!candidate.path.startsWith(cachePrefix)) {
            throw UpdateException(
                "INVALID_UPDATE_PATH",
                "The update is outside the private cache directory.",
            )
        }
        return candidate
    }

    private fun launchInstaller(update: VerifiedUpdate, result: MethodChannel.Result) {
        val contentUri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            update.file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri("update", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(activity.packageManager) == null) {
            throw UpdateException("INSTALLER_UNAVAILABLE", "No package installer is available.")
        }
        mainHandler.post {
            try {
                activity.startActivity(intent)
                result.success(null)
            } catch (error: Exception) {
                result.error(
                    "UPDATE_INSTALL_FAILED",
                    "The update installer could not be opened.",
                    error.message,
                )
            }
        }
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(
        result: MethodChannel.Result,
        code: String,
        message: String?,
        error: Exception? = null,
    ) {
        mainHandler.post { result.error(code, message, error?.message) }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        FileInputStream(file).use { input ->
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it.toInt() and 0xff) }
    }

    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Array<Signature>? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo
            if (signingInfo != null) return signingInfo.apkContentsSigners
        }
        return info.signatures
    }

    private fun sameSigners(current: PackageInfo, archive: PackageInfo): Boolean {
        val currentSigners = signers(current) ?: return false
        val archiveSigners = signers(archive) ?: return false
        if (currentSigners.size != archiveSigners.size) return false
        return archiveSigners.all { archiveSigner ->
            currentSigners.any { currentSigner -> archiveSigner == currentSigner }
        }
    }

    private fun integralLong(value: Any?): Long? {
        val number = value as? Number ?: return null
        val doubleValue = number.toDouble()
        if (!doubleValue.isFinite() || doubleValue != floor(doubleValue)) return null
        if (doubleValue < Long.MIN_VALUE.toDouble() || doubleValue > Long.MAX_VALUE.toDouble()) {
            return null
        }
        return number.toLong()
    }

    private data class VerifiedUpdate(
        val file: File,
        val packageName: String,
        val versionCode: Long,
    )

    private class UpdateException(
        val code: String,
        message: String,
    ) : Exception(message)
}
