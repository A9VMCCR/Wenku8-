package org.mewx.wenku8_flutter

import java.io.File
import java.io.OutputStream

/** Only generated books in the export staging tree may leave private storage. */
internal object BookExportFiles {
    fun source(root: File, path: String): File {
        val file = File(path).canonicalFile
        require(file.path.startsWith(root.canonicalPath + File.separator) && file.isFile) { "下载文件无效，请重新生成" }
        val limit = when (file.extension.lowercase()) {
            "epub" -> 512L * 1024 * 1024
            "txt" -> 128L * 1024 * 1024
            else -> error("不支持的下载格式")
        }
        require(file.length() in 1..limit) { "下载文件为空或超过格式大小限制" }
        return file
    }
    fun mime(file: File) = if (file.extension.lowercase() == "epub") "application/epub+zip" else "text/plain"
    fun copy(source: File, output: OutputStream): Long {
        val size = source.length()
        val copied = source.inputStream().use { it.copyTo(output, 64 * 1024) }
        output.flush()
        check(copied == size) { "文件未完整保存，请重新选择保存位置" }
        return copied
    }
}
