package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.file.Files

class BookExportFilesTest {
    @Test fun onlyCompletedGeneratedBooksCanBeSaved() {
        val parent = Files.createTempDirectory("export-policy").toFile()
        try {
            val root = parent.resolve("book-exports").apply { mkdirs() }
            val book = root.resolve("job/book.epub").apply { requireNotNull(parentFile).mkdirs(); writeBytes(byteArrayOf(1, 2, 3)) }
            assertEquals(book.canonicalFile, BookExportFiles.source(root, book.path))
            assertEquals("application/epub+zip", BookExportFiles.mime(book))
            val outside = parent.resolve("private.epub").apply { writeText("private") }
            for (bad in listOf(outside, root.resolve("missing.txt"), root.resolve("job/file.epub.part").apply { writeText("partial") }, root.resolve("job/empty.txt").apply { writeText("") })) {
                try { BookExportFiles.source(root, bad.path); fail("accepted ${bad.name}") }
                catch (_: IllegalArgumentException) {} catch (_: IllegalStateException) {}
            }
        } finally { parent.deleteRecursively() }
    }
    @Test fun transferStreamsTheCompleteGeneratedFile() {
        val root = Files.createTempDirectory("export-copy").toFile()
        try {
            val data = ByteArray(2 * 1024 * 1024 + 19) { (it % 251).toByte() }
            val book = root.resolve("book.txt").apply { writeBytes(data) }
            val output = ByteArrayOutputStream()
            assertEquals(data.size.toLong(), BookExportFiles.copy(book, output))
            assertArrayEquals(data, output.toByteArray())
            assertEquals("text/plain", BookExportFiles.mime(book))
        } finally { root.deleteRecursively() }
    }
}
