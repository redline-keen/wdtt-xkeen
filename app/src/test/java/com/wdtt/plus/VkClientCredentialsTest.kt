package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VkClientCredentialsTest {
    @Test
    fun `client id normalization keeps digits only`() {
        assertEquals("123456", normalizeVkClientId(" 12-ab34 56 "))
        assertTrue(isValidVkClientId("123456"))
        assertFalse(isValidVkClientId("123-456"))
    }

    @Test
    fun `disabled custom mode never blocks built in credentials`() {
        assertNull(customVkCredentialsError(CustomVkClientCredentials(enabled = false)))
    }

    @Test
    fun `enabled custom mode requires both values`() {
        assertEquals(
            "Укажите числовой Client ID приложения VK.",
            customVkCredentialsError(CustomVkClientCredentials(enabled = true))
        )
        assertEquals(
            "Укажите защищённый ключ (Client secret) приложения VK.",
            customVkCredentialsError(CustomVkClientCredentials(enabled = true, clientId = "123456"))
        )
        assertNull(
            customVkCredentialsError(
                CustomVkClientCredentials(
                    enabled = true,
                    clientId = "123456",
                    clientSecret = "test-only-secret"
                )
            )
        )
    }
}
