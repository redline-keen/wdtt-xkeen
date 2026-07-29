package com.wdtt.plus

import java.io.ByteArrayOutputStream
import java.io.InputStream

internal fun InputStream.readUtf8TextLimited(maxBytes: Int): String {
    require(maxBytes > 0) { "Лимит ответа должен быть положительным." }
    val output = ByteArrayOutputStream(minOf(maxBytes, DEFAULT_BUFFER_SIZE))
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var total = 0
    while (true) {
        val read = read(buffer)
        if (read < 0) break
        total += read
        require(total <= maxBytes) { "Ответ сервиса слишком большой." }
        output.write(buffer, 0, read)
    }
    return output.toString(Charsets.UTF_8.name())
}
