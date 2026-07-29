package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceIdentityTest {
    @Test
    fun existingIdentityIsPreservedForActiveInstallations() {
        val existing = "android-11111111-2222-3333-4444-555555555555"

        val resolved = DeviceIdentity.resolve(
            existing = existing,
            platformId = "abcdef0123456789",
            generatedId = "android-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        )

        assertEquals(existing, resolved)
    }

    @Test
    fun freshInstallationUsesStablePlatformIdentity() {
        val resolved = DeviceIdentity.resolve(
            existing = null,
            platformId = "abcdef0123456789",
            generatedId = "android-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        )

        assertEquals("abcdef0123456789", resolved)
    }

    @Test
    fun missingPlatformIdentityUsesValidGeneratedFallback() {
        val fallback = "android-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

        val resolved = DeviceIdentity.resolve(
            existing = "broken",
            platformId = null,
            generatedId = fallback,
        )

        assertEquals(fallback, resolved)
    }

    @Test
    fun knownSharedLegacyAndroidIdentityIsRejected() {
        assertFalse(DeviceIdentity.valid("9774d56d682e549c"))
        assertFalse(DeviceIdentity.valid("unknown"))
        assertTrue(DeviceIdentity.valid("abcdef0123456789"))
    }
}
