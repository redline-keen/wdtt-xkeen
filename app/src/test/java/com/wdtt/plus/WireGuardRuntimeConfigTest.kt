package com.wdtt.plus

import com.wireguard.config.Config
import com.wireguard.crypto.Key
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

class WireGuardRuntimeConfigTest {
    private val privateKey = Key.fromBytes(ByteArray(32) { index -> (index + 1).toByte() })
        .toBase64()
    private val publicKey = Key.fromBytes(ByteArray(32) { index -> (index + 33).toByte() })
        .toBase64()

    @Test
    fun unchangedConfigurationKeepsRunningVpnInterface() {
        val current = config(endpointPort = 9000)
        val updated = config(endpointPort = 9000)

        assertTrue(
            shouldReuseRunningWireGuard(
                tunnelUp = true,
                currentConfigFingerprint = wireGuardConfigFingerprint(current),
                updatedConfig = updated,
            )
        )
    }

    @Test
    fun changedConfigurationReplacesVpnInterface() {
        assertFalse(
            shouldReuseRunningWireGuard(
                tunnelUp = true,
                currentConfigFingerprint = wireGuardConfigFingerprint(
                    config(endpointPort = 9000)
                ),
                updatedConfig = config(endpointPort = 9001),
            )
        )
    }

    @Test
    fun stoppedVpnInterfaceIsNeverReused() {
        val config = config(endpointPort = 9000)

        assertFalse(
            shouldReuseRunningWireGuard(
                tunnelUp = false,
                currentConfigFingerprint = wireGuardConfigFingerprint(config),
                updatedConfig = config,
            )
        )
    }

    private fun config(endpointPort: Int): Config {
        val text = """
            [Interface]
            PrivateKey = $privateKey
            Address = 10.0.0.2/32
            DNS = 1.1.1.1
            MTU = 1280

            [Peer]
            PublicKey = $publicKey
            AllowedIPs = 0.0.0.0/0
            Endpoint = 127.0.0.1:$endpointPort
            PersistentKeepalive = 25
        """.trimIndent()
        return Config.parse(ByteArrayInputStream(text.toByteArray()))
    }
}
