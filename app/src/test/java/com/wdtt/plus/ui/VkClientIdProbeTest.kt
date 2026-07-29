package com.wdtt.plus.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VkClientIdProbeTest {
    @Test
    fun legacyProbePrefersVkRuAndKeepsVkComAsCompatibilityFallback() {
        assertEquals("https://oauth.vk.ru/authorize", vkLegacyOAuthProbeEndpoints.first())
        assertEquals("https://oauth.vk.com/authorize", vkLegacyOAuthProbeEndpoints.last())
    }

    @Test
    fun acceptsLegacyOauthLoginPage() {
        assertTrue(isVkLegacyClientIdProbeSuccessful(200, "text/html; charset=utf-8"))
    }

    @Test
    fun rejectsJsonErrorsAndHttpFailures() {
        assertFalse(isVkLegacyClientIdProbeSuccessful(401, "application/json; charset=utf-8"))
        assertFalse(isVkLegacyClientIdProbeSuccessful(200, "application/json"))
        assertFalse(isVkLegacyClientIdProbeSuccessful(503, "text/html"))
        assertTrue(isVkLegacyClientIdProbeRejected(401))
        assertFalse(isVkLegacyClientIdProbeRejected(429))
        assertFalse(isVkLegacyClientIdProbeRejected(503))
    }

    @Test
    fun cachedProbeResultsKeepStatusAndTimestampSeparate() {
        val cache = parseVkClientIdCheckResults(
            """{"_probe_version":3,"_checked_at":123456,"6287487":"LegacyCompatible","8202606":"LegacyRejected"}"""
        )

        assertEquals(123456L, cache.checkedAt)
        assertEquals(
            mapOf(
                "6287487" to VkClientIdProbeStatus.LegacyCompatible,
                "8202606" to VkClientIdProbeStatus.LegacyRejected
            ),
            cache.results
        )
    }

    @Test
    fun probeCooldownBlocksRapidRepeatedChecks() {
        assertEquals(10_000L, vkClientIdProbeCooldownRemainingMillis(now = 20_000L, lastStartedAt = 20_000L))
        assertEquals(1L, vkClientIdProbeCooldownRemainingMillis(now = 29_999L, lastStartedAt = 20_000L))
        assertEquals(0L, vkClientIdProbeCooldownRemainingMillis(now = 30_000L, lastStartedAt = 20_000L))
    }

    @Test
    fun availabilitySummaryExplainsAllProbeCombinations() {
        val ids = listOf("6287487", "8202606")

        assertEquals(
            "Все встроенные Client ID доступны для резервного способа",
            vkClientIdAvailabilityMessage(
                ids,
                mapOf(
                    "6287487" to VkClientIdProbeStatus.LegacyCompatible,
                    "8202606" to VkClientIdProbeStatus.LegacyCompatible
                )
            )
        )
        assertEquals(
            "Доступны: 6287487. Не принимаются: 8202606.",
            vkClientIdAvailabilityMessage(
                ids,
                mapOf(
                    "6287487" to VkClientIdProbeStatus.LegacyCompatible,
                    "8202606" to VkClientIdProbeStatus.LegacyRejected
                )
            )
        )
        assertEquals(
            "Не удалось проверить: 6287487, 8202606.",
            vkClientIdAvailabilityMessage(
                ids,
                mapOf(
                    "6287487" to VkClientIdProbeStatus.CheckFailed,
                    "8202606" to VkClientIdProbeStatus.CheckFailed
                )
            )
        )
    }

    @Test
    fun automaticProbeUsesOnlyCredentialsForSelectedMode() {
        assertEquals(
            listOf("6287487", "8202606"),
            vkClientIdsForAutomaticProbe(false, "123456", "secret")
        )
        assertEquals(
            listOf("123456"),
            vkClientIdsForAutomaticProbe(true, "123456", "secret")
        )
        assertTrue(vkClientIdsForAutomaticProbe(true, "123456", "").isEmpty())
        assertTrue(vkClientIdsForAutomaticProbe(true, "invalid", "secret").isEmpty())
    }
}
