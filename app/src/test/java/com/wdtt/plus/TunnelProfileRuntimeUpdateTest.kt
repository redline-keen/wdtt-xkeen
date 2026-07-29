package com.wdtt.plus

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelProfileRuntimeUpdateTest {
    @Test
    fun activeRunningProfileRequestsRuntimeUpdate() {
        assertTrue(
            shouldRequestTunnelProfileRuntimeUpdate(
                updatedProfile = 1,
                activeTunnelProfile = 1,
                tunnelRunning = true,
                trustedWifiWaiting = false,
            )
        )
    }

    @Test
    fun inactiveProfileDoesNotTouchRunningTunnel() {
        assertFalse(
            shouldRequestTunnelProfileRuntimeUpdate(
                updatedProfile = 2,
                activeTunnelProfile = 1,
                tunnelRunning = true,
                trustedWifiWaiting = false,
            )
        )
    }

    @Test
    fun stoppedProfileDoesNotStartVpn() {
        assertFalse(
            shouldRequestTunnelProfileRuntimeUpdate(
                updatedProfile = 1,
                activeTunnelProfile = 1,
                tunnelRunning = false,
                trustedWifiWaiting = false,
            )
        )
    }

    @Test
    fun trustedWifiWaitingProfileKeepsUpdatedConfigurationForResume() {
        assertTrue(
            shouldRequestTunnelProfileRuntimeUpdate(
                updatedProfile = 1,
                activeTunnelProfile = 1,
                tunnelRunning = false,
                trustedWifiWaiting = true,
            )
        )
    }

    @Test
    fun changedConnectionParametersRequireRuntimeReplacement() {
        val current = params(peer = "old.example:56000")
        val updated = current.copy(peer = "new.example:56000")

        assertTrue(tunnelProfileRuntimeConfigurationChanged(current, updated))
    }

    @Test
    fun unchangedConnectionParametersDoNotRestartTransport() {
        val current = params(peer = "same.example:56000")

        assertFalse(tunnelProfileRuntimeConfigurationChanged(current, current.copy()))
    }

    @Test
    fun anotherProfileCannotReplaceActiveRuntimeConfiguration() {
        val current = params(peer = "old.example:56000", profileIndex = 0)
        val updated = current.copy(peer = "new.example:56000", profileIndex = 1)

        assertFalse(tunnelProfileRuntimeConfigurationChanged(current, updated))
    }

    private fun params(
        peer: String,
        profileIndex: Int = 0,
    ) = TunnelParams(
        peer = peer,
        vkHashes = "hash",
        workersPerHash = 9,
        port = 9000,
        connectionPassword = "password",
        profileIndex = profileIndex,
    )
}
