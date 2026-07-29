package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Test

class TunnelRecoveryPolicyTest {
    @Test
    fun firstRecoveryIsTransportOnly() {
        assertEquals(
            NetworkRecoveryAction.SoftRestart,
            stableNetworkRecoveryAction(completedAttempts = 0),
        )
    }

    @Test
    fun failedTransportRecoveryRecreatesVpnOnce() {
        assertEquals(
            NetworkRecoveryAction.RecreateVpn,
            stableNetworkRecoveryAction(completedAttempts = 1),
        )
    }

    @Test
    fun failedVpnRecreationStopsFailOpen() {
        assertEquals(
            NetworkRecoveryAction.StopVpn,
            stableNetworkRecoveryAction(completedAttempts = 2),
        )
        assertEquals(
            NetworkRecoveryAction.StopVpn,
            stableNetworkRecoveryAction(completedAttempts = 3),
        )
    }
}
