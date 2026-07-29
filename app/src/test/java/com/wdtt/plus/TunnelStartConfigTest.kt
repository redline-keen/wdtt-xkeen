package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Test

class TunnelStartConfigTest {
    @Test
    fun `tile and widgets stop both active and trusted wifi waiting tunnel`() {
        assertEquals(
            TunnelToggleAction.STOP,
            tunnelToggleAction(
                running = true,
                trustedWifiWaiting = false,
                vpnPermissionRequired = false,
            )
        )
        assertEquals(
            TunnelToggleAction.STOP,
            tunnelToggleAction(
                running = false,
                trustedWifiWaiting = true,
                vpnPermissionRequired = false,
            )
        )
    }

    @Test
    fun `tile and widgets request permission before start`() {
        assertEquals(
            TunnelToggleAction.REQUEST_VPN_PERMISSION,
            tunnelToggleAction(
                running = false,
                trustedWifiWaiting = false,
                vpnPermissionRequired = true,
            )
        )
        assertEquals(
            TunnelToggleAction.START,
            tunnelToggleAction(
                running = false,
                trustedWifiWaiting = false,
                vpnPermissionRequired = false,
            )
        )
    }

}
