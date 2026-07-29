package com.wdtt.plus.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class VkHashBulkPasteTest {
    @Test
    fun parseBulkVkHashesAcceptsCommaSeparatedHashes() {
        assertEquals(
            listOf("hash000000000001", "hash000000000002", "hash000000000003", "hash000000000004"),
            parseBulkVkHashes("hash000000000001,hash000000000002,hash000000000003,hash000000000004")
        )
    }

    @Test
    fun parseBulkVkHashesAcceptsEncodedSpacesAndSeparators() {
        assertEquals(
            listOf("hash000000000001", "hash000000000002", "hash000000000003", "hash000000000004"),
            parseBulkVkHashes("hash000000000001%20hash000000000002%2Chash000000000003%0Ahash000000000004")
        )
    }

    @Test
    fun parseBulkVkHashesExtractsJoinLinksAndDropsDuplicates() {
        assertEquals(
            listOf("hash000000000001", "hash000000000002"),
            parseBulkVkHashes(
                "https://vk.com/call/join/hash000000000001 " +
                    "https://vk.ru/call/join/hash000000000002 " +
                    "hash000000000001"
            )
        )
    }

    @Test
    fun parseBulkVkHashesRejectsOrdinaryLongWords() {
        assertEquals(
            emptyList<String>(),
            parseBulkVkHashes("пользовательский переподключаются")
        )
    }

    @Test
    fun mergeBulkVkHashesFillsOnlyEmptySlotsWithoutOverwritingExisting() {
        val result = mergeBulkVkHashes(
            existingSlots = listOf("", "oldHash0000000002", "oldHash0000000003", ""),
            incomingHashes = listOf("newHash0000000001", "oldHash0000000002", "newHash0000000004"),
            mode = BulkVkHashPasteMode.FillEmpty
        )

        assertEquals(
            listOf("newHash0000000001", "oldHash0000000002", "oldHash0000000003", "newHash0000000004"),
            result.slots
        )
        assertEquals(2, result.insertedCount)
        assertEquals(1, result.skippedCount)
    }

    @Test
    fun mergeBulkVkHashesReplacesAllSlotsWhenRequested() {
        val result = mergeBulkVkHashes(
            existingSlots = listOf("", "oldHash0000000002", "oldHash0000000003", ""),
            incomingHashes = listOf("newHash0000000001", "newHash0000000002", "newHash0000000003", "newHash0000000004"),
            mode = BulkVkHashPasteMode.ReplaceAll
        )

        assertEquals(
            listOf("newHash0000000001", "newHash0000000002", "newHash0000000003", "newHash0000000004"),
            result.slots
        )
        assertEquals(4, result.insertedCount)
        assertEquals(0, result.skippedCount)
    }
}
