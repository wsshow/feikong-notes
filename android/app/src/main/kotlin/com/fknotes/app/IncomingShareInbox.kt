package com.fknotes.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Process
import android.provider.OpenableColumns
import android.text.Html
import android.webkit.MimeTypeMap
import androidx.core.content.IntentCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** A private, bounded inbox; only acknowledged entries are removed. */
internal class IncomingShareInbox(private val context: Context) {
    companion object {
        const val MAX_FILES = 20
        const val MAX_TEXT = 100_000
        const val MAX_FILE_BYTES = 100L * 1024 * 1024
        const val MAX_TOTAL_BYTES = 200L * 1024 * 1024
        const val MAX_PENDING = 8
        private val validId = Regex("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")

        fun safeName(raw: String): String = raw.replace('\\', '/')
            .substringAfterLast('/').filter { !it.isISOControl() }.trim().take(160)
            .takeIf { it.isNotBlank() && it != "." && it != ".." } ?: "attachment"
    }

    private val root: File
        get() = File(context.noBackupFilesDir, "incoming_shares").apply { mkdirs() }

    fun receive(intent: Intent) {
        val entries = rootEntries()
        val order = maxOf(System.currentTimeMillis(), (entries.maxOfOrNull { read(it).optLong("order", it.lastModified()) } ?: 0L) + 1)
        val id = UUID.randomUUID().toString()
        val dir = File(root, id).apply { mkdirs() }
        val data = JSONObject().put("id", id).put("createdAt", System.currentTimeMillis()).put("order", order)
        try {
            write(dir, data.put("error", "interrupted"))
            require(entries.size < MAX_PENDING) { "queue_full" }
            val (title, text, streams) = parse(intent)
            data.put("title", title).put("text", text)
            val files = JSONArray()
            var total = 0L
            for (uri in streams) {
                val file = copy(uri, dir, intent.type, MAX_TOTAL_BYTES - total)
                total += file.getLong("byteLength")
                files.put(file)
            }
            data.remove("error")
            data.put("files", files)
        } catch (error: Exception) {
            dir.listFiles()?.filter { it.name != "entry.json" }?.forEach { it.delete() }
            val code = error.message?.takeIf { it in setOf("too_large", "too_many", "empty", "queue_full") } ?: "unreadable"
            data.put("error", code).put("files", JSONArray())
        }
        write(dir, data)
    }

    internal fun parse(intent: Intent): Triple<String, String, List<Uri>> {
        require(intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString().orEmpty()
        val html = if (text.isEmpty()) intent.getStringExtra(Intent.EXTRA_HTML_TEXT).orEmpty() else ""
        require(text.length <= MAX_TEXT && html.length <= MAX_TEXT) { "too_large" }
        var plain = if (html.isNotEmpty()) Html.fromHtml(html, Html.FROM_HTML_MODE_LEGACY).toString() else text
        val streams = linkedSetOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val extras = IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            require((extras?.size ?: 0) <= MAX_FILES) { "too_many" }
            extras?.let(streams::addAll)
        } else {
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let(streams::add)
        }
        // ClipData is a fallback, not a second copy of EXTRA_STREAM. Text-share
        // previews may contain a thumbnail URI that is not shared content.
        val clip = intent.clipData
        if (streams.isEmpty() && clip != null) {
            require(clip.itemCount <= MAX_FILES) { "too_many" }
            val texts = mutableListOf<String>()
            for (index in 0 until clip.itemCount) {
                val item = clip.getItemAt(index)
                if (plain.isEmpty() || intent.type?.startsWith("text/") != true) item.uri?.let { uri ->
                    if (uri.scheme == "https" || uri.scheme == "http") texts.add(uri.toString()) else streams.add(uri)
                }
                item.text?.toString()?.let(texts::add)
            }
            if (plain.isEmpty()) plain = texts.joinToString("\n")
        }
        require(plain.length <= MAX_TEXT) { "too_large" }
        require(streams.size <= MAX_FILES) { "too_many" }
        val title = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString().orEmpty().take(500)
        require(plain.isNotBlank() || title.isNotBlank() || streams.isNotEmpty()) { "empty" }
        return Triple(title, plain, streams.toList())
    }

    private fun copy(uri: Uri, dir: File, fallbackMime: String?, remaining: Long): JSONObject {
        require(uri.scheme == "content")
        val authority = requireNotNull(uri.authority)
        val provider = context.packageManager.resolveContentProvider(authority.substringAfter('@'), 0)
        require(authority.substringAfter('@') != "${context.packageName}.fileprovider")
        require(provider?.applicationInfo?.uid != Process.myUid())
        require(context.checkUriPermission(uri, Process.myPid(), Process.myUid(), Intent.FLAG_GRANT_READ_URI_PERMISSION) == PackageManager.PERMISSION_GRANTED)
        val resolver = context.contentResolver
        val mime = (resolver.getType(uri) ?: fallbackMime ?: "application/octet-stream")
            .substringBefore(';').lowercase().take(120)
        var name = "attachment"
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) name = safeName(cursor.getString(nameIndex).orEmpty())
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    require(cursor.getLong(sizeIndex) <= minOf(MAX_FILE_BYTES, remaining)) { "too_large" }
                }
            }
        }
        val extension = name.substringAfterLast('.', "").lowercase().takeIf { it.matches(Regex("[a-z0-9]{1,10}")) }
            ?: MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        val fileName = UUID.randomUUID().toString() + (extension?.let { ".$it" } ?: "")
        val output = File(dir, fileName)
        var bytes = 0L
        resolver.openInputStream(uri)?.use { input ->
            output.outputStream().use { sink ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    bytes += count
                    require(bytes <= minOf(MAX_FILE_BYTES, remaining)) { "too_large" }
                    sink.write(buffer, 0, count)
                }
            }
        } ?: error("unreadable")
        return JSONObject().put("name", name).put("fileName", fileName)
            .put("mimeType", mime).put("byteLength", bytes)
    }

    private fun write(dir: File, data: JSONObject) {
        val partial = File(dir, "entry.part")
        partial.writeText(data.toString())
        check(partial.renameTo(File(dir, "entry.json")))
    }

    private fun rootEntries() = root.listFiles()?.filter { it.isDirectory && validId.matches(it.name) }.orEmpty()

    private fun read(dir: File): JSONObject = try { JSONObject(File(dir, "entry.json").readText()) } catch (_: Exception) {
        JSONObject().put("id", dir.name).put("error", "interrupted")
    }

    fun peek(): Map<String, Any?>? {
        return rootEntries().map { it to read(it) }.minByOrNull { (dir, data) -> data.optLong("order", dir.lastModified()) }?.let { (dir, data) ->
            val files = data.optJSONArray("files") ?: JSONArray()
            mapOf(
                "id" to dir.name,
                "directory" to dir.canonicalPath,
                "createdAt" to data.optLong("createdAt", System.currentTimeMillis()),
                "title" to data.optString("title"),
                "text" to data.optString("text"),
                "error" to data.optString("error").ifEmpty { null },
                "files" to (0 until files.length()).map { index ->
                    val file = files.getJSONObject(index)
                    mapOf(
                        "name" to file.getString("name"),
                        "fileName" to file.getString("fileName"),
                        "mimeType" to file.getString("mimeType"),
                        "byteLength" to file.getLong("byteLength"),
                    )
                },
            )
        }
    }

    fun finish(id: String) {
        require(validId.matches(id))
        val dir = File(root, id)
        check(!dir.exists() || dir.deleteRecursively())
    }
}
