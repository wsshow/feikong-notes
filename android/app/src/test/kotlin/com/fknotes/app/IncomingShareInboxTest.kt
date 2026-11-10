package com.fknotes.app

import android.content.ClipData
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.Shadows.shadowOf
import java.io.ByteArrayInputStream
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class IncomingShareInboxTest {
    private lateinit var context: Context
    private lateinit var inbox: IncomingShareInbox

    @Before fun setup() {
        context = object : ContextWrapper(RuntimeEnvironment.getApplication()) {
            override fun checkUriPermission(uri: Uri?, pid: Int, uid: Int, modeFlags: Int) = PackageManager.PERMISSION_GRANTED
        }
        File(context.noBackupFilesDir, "incoming_shares").deleteRecursively()
        inbox = IncomingShareInbox(context)
    }

    @After fun cleanup() { File(context.noBackupFilesDir, "incoming_shares").deleteRecursively() }

    @Test fun textPersistsUntilAcknowledgedAndAnotherShareIsNotLost() {
        inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "https://example.org"))
        val first = inbox.peek()!!
        assertEquals("https://example.org", first["text"])
        assertEquals(first["id"], IncomingShareInbox(context).peek()!!["id"])
        inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "second"))
        inbox.finish(first["id"] as String)
        assertEquals("second", inbox.peek()!!["text"])
        inbox.finish(inbox.peek()!!["id"] as String)
        assertNull(inbox.peek())
    }

    @Test fun textAndStreamAreBothPreservedAndClipDataDoesNotDuplicateStream() {
        val uri = Uri.parse("content://sender/image")
        shadowOf(context.contentResolver).registerInputStream(uri, ByteArrayInputStream(byteArrayOf(1, 2, 3)))
        val intent = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_TEXT, "caption").putExtra(Intent.EXTRA_SUBJECT, "subject")
        intent.clipData = ClipData.newRawUri("image", uri)
        inbox.receive(intent)
        val result = inbox.peek()!!
        assertNull(result["error"])
        assertEquals("caption", result["text"])
        assertEquals("subject", result["title"])
        val files = result["files"] as List<*>
        assertEquals(1, files.size)
        val file = files.single() as Map<*, *>
        assertArrayEquals(byteArrayOf(1, 2, 3), File(result["directory"] as String, file["fileName"] as String).readBytes())
    }

    @Test fun multipleStreamsAreOrderedAndDeduplicated() {
        val a = Uri.parse("content://sender/a")
        val b = Uri.parse("content://sender/b")
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).setType("*/*")
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(a, b, a))
        assertEquals(listOf(a, b), inbox.parse(intent).third)
        val clipOnly = Intent(Intent.ACTION_SEND_MULTIPLE).setType("image/*")
        clipOnly.clipData = ClipData.newRawUri("a", a).apply { addItem(ClipData.Item(b)) }
        assertEquals(listOf(a, b), inbox.parse(clipOnly).third)
    }

    @Test fun htmlAndClipTextFallbackArePlainText() {
        val html = Intent(Intent.ACTION_SEND).setType("text/html").putExtra(Intent.EXTRA_HTML_TEXT, "<b>Hello</b>")
        assertEquals("Hello", inbox.parse(html).second)
        val clip = Intent(Intent.ACTION_SEND).setType("text/plain")
        clip.clipData = ClipData.newPlainText("label", "fallback")
        assertEquals("fallback", inbox.parse(clip).second)
    }

    @Test fun browserThumbnailIsNotMistakenForSharedAttachment() {
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "https://example.org")
        intent.clipData = ClipData.newRawUri("preview", Uri.parse("content://sender/preview"))
        assertTrue(inbox.parse(intent).third.isEmpty())
    }

    @Test fun unsafeUrisAndMissingGrantsFailWithoutImportingPartialContent() {
        for (uri in listOf("file:///data/user/0/private.db", "content://${context.packageName}.fileprovider/secret")) {
            inbox.receive(Intent(Intent.ACTION_SEND).setType("*/*").putExtra(Intent.EXTRA_STREAM, Uri.parse(uri)))
            val entry = inbox.peek()!!
            assertEquals("unreadable", entry["error"])
            assertTrue((entry["files"] as List<*>).isEmpty())
            inbox.finish(entry["id"] as String)
        }
        val denied = object : ContextWrapper(context) {
            override fun checkUriPermission(uri: Uri?, pid: Int, uid: Int, modeFlags: Int) = PackageManager.PERMISSION_DENIED
        }
        IncomingShareInbox(denied).receive(Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, Uri.parse("content://sender/a")))
        assertEquals("unreadable", inbox.peek()!!["error"])
    }

    @Test fun overLimitOrEmptyContentProducesRecoverableError() {
        inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "a".repeat(IncomingShareInbox.MAX_TEXT + 1)))
        assertEquals("too_large", inbox.peek()!!["error"])
        inbox.finish(inbox.peek()!!["id"] as String)
        inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain"))
        assertEquals("empty", inbox.peek()!!["error"])
    }

    @Test fun displayNamesCannotBecomePathsAndFinishCannotEscapeInbox() {
        assertEquals("file.pdf", IncomingShareInbox.safeName("../../file.pdf"))
        assertEquals("file.pdf", IncomingShareInbox.safeName("C:\\folder\\file.pdf"))
        assertEquals("attachment", IncomingShareInbox.safeName(".."))
        assertThrows(IllegalArgumentException::class.java) { inbox.finish("../outside") }
    }

    @Test fun tooManyFilesAndInterruptedCopiesNeverProducePartialNotes() {
        val many = Intent(Intent.ACTION_SEND_MULTIPLE).setType("image/*")
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList((0..20).map { Uri.parse("content://sender/$it") }))
        inbox.receive(many)
        assertEquals("too_many", inbox.peek()!!["error"])
        inbox.finish(inbox.peek()!!["id"] as String)
        val id = java.util.UUID.randomUUID().toString()
        val interrupted = File(context.noBackupFilesDir, "incoming_shares/$id").apply { mkdirs() }
        File(interrupted, "partial.png").writeBytes(byteArrayOf(1))
        assertEquals("interrupted", inbox.peek()!!["error"])
        inbox.finish(id)
        assertFalse(interrupted.exists())
    }

    @Test fun unknownLengthStreamsStillEnforceTheByteLimit() {
        val uri = Uri.parse("content://sender/large")
        val stream = object : java.io.InputStream() {
            var remaining = IncomingShareInbox.MAX_FILE_BYTES + 1
            override fun read(): Int = if (remaining-- > 0) 0 else -1
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (remaining <= 0) return -1
                val count = minOf(length.toLong(), remaining).toInt()
                remaining -= count
                return count
            }
        }
        shadowOf(context.contentResolver).registerInputStream(uri, stream)
        inbox.receive(Intent(Intent.ACTION_SEND).setType("application/octet-stream").putExtra(Intent.EXTRA_STREAM, uri))
        val result = inbox.peek()!!
        assertEquals("too_large", result["error"])
        assertEquals(listOf("entry.json"), File(result["directory"] as String).listFiles()!!.map { it.name })
    }

    @Test fun clipDataWebLinkIsTextAndQueueOrderIsStableForRapidShares() {
        val link = Intent(Intent.ACTION_SEND).setType("text/plain")
        link.clipData = ClipData.newRawUri("link", Uri.parse("https://example.org"))
        assertEquals("https://example.org", inbox.parse(link).second)
        assertTrue(inbox.parse(link).third.isEmpty())
        for (index in 0..8) inbox.receive(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, index.toString()))
        for (index in 0..7) {
            assertEquals(index.toString(), inbox.peek()!!["text"])
            inbox.finish(inbox.peek()!!["id"] as String)
        }
        assertEquals("queue_full", inbox.peek()!!["error"])
    }
}
