package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Test

class BoundedInputTest {
    @Test
    fun `bounded reader stops before accepting an oversized response`() {
        assertEquals(
            "данные",
            "данные".byteInputStream().readUtf8TextLimited(32),
        )

        runCatching {
            "x".repeat(33).byteInputStream().readUtf8TextLimited(32)
        }.onSuccess {
            throw AssertionError("Oversized response must be rejected")
        }
    }
}
