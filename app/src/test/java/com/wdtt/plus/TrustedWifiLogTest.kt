package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Test

class TrustedWifiLogTest {
    @Test
    fun `repeated trusted wifi event updates one counter`() {
        TunnelManager.isLoggingEnabled = true
        TunnelManager.clearLogs()
        try {
            TunnelManager.noteTrustedWifiEvent("resume_wait_network", "Ждём рабочую сеть.")
            TunnelManager.noteTrustedWifiEvent("resume_wait_network", "Ждём рабочую сеть.")

            val entries = TunnelManager.logs.value.filter { it.key == "trusted_wifi_resume_wait_network" }
            assertEquals(1, entries.size)
            assertEquals(2, entries.single().count)
            assertEquals(LogSeverity.Info, entries.single().severity)
        } finally {
            TunnelManager.clearLogs()
        }
    }
}
