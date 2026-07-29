package com.wdtt.plus

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelStopCoordinatorTest {
    @Test
    fun `only completed stop outcomes allow a destructive follow-up action`() {
        assertTrue(TunnelStopResult.ALREADY_STOPPED.succeeded)
        assertTrue(TunnelStopResult.STOPPED.succeeded)
        assertFalse(TunnelStopResult.TIMED_OUT.succeeded)
        assertFalse(TunnelStopResult.FAILED.succeeded)
    }
}
