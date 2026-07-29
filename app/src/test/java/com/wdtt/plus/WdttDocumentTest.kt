package com.wdtt.plus

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WdttDocumentTest {
    @Test
    fun `profile file name always has one wdtt extension`() {
        assertEquals("WDTT-Plus-profile.wdtt", WdttDocument.fileName("WDTT-Plus-profile"))
        assertEquals("WDTT-Plus-profile.wdtt", WdttDocument.fileName("WDTT-Plus-profile.wdtt"))
    }

    @Test
    fun `picker accepts current mime and compatible legacy document types`() {
        assertArrayEquals(
            arrayOf(
                "application/vnd.wdtt.plus",
                "application/vnd.wdtt.plus.transfer",
                "application/vnd.wdtt.plus.client",
                "application/json",
                "application/octet-stream",
                "text/plain",
            ),
            WdttDocument.acceptedMimeTypes(),
        )
        assertTrue(WdttDocument.isAcceptedMimeType("application/vnd.wdtt.plus"))
        assertTrue(WdttDocument.isAcceptedMimeType("application/octet-stream"))
        assertTrue(WdttDocument.isAcceptedMimeType("text/plain; charset=utf-8"))
    }
}
