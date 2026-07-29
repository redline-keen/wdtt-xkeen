package com.wdtt.plus.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class OutboundWireGuardTest {
    private val safeConfig = """
        [Interface]
        PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
        Address = 172.16.0.2/32
        DNS = 1.1.1.1
        MTU = 1280
        Table = auto

        [Peer]
        PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = engage.cloudflareclient.com:2408
        PersistentKeepalive = 25
    """.trimIndent()

    @Test
    fun importedWireGuardConfig_isSanitizedForPolicyRouting() {
        val sanitized = sanitizeWireGuardConfigForWdttExit(safeConfig)

        assertTrue("Table = off" in sanitized)
        assertTrue("MTU = 1280" in sanitized)
        assertFalse(Regex("(?im)^\\s*DNS\\s*=").containsMatchIn(sanitized))
        assertFalse("Table = auto" in sanitized)
    }

    @Test
    fun importedWireGuardConfig_rejectsCommandsAndUnknownParameters() {
        val commandConfig = safeConfig.replace("MTU = 1280", "PostUp = touch /tmp/unsafe")
        val unknownConfig = safeConfig.replace("MTU = 1280", "UnsafeOption = true")

        assertTrue(validateWireGuardConfigText(commandConfig).isFailure)
        assertTrue(validateWireGuardConfigText(unknownConfig).isFailure)
    }

    @Test
    fun importedWireGuardConfig_requiresDefaultIpv4Route() {
        val config = safeConfig.replace("0.0.0.0/0, ::/0", "10.0.0.0/8")

        assertTrue(validateWireGuardConfigText(config).isFailure)
    }

    @Test
    fun freeWarpScript_hasSafeUpdateChecksAndValidShellSyntax() {
        val script = buildFreeWarpInstallScript(1392)

        assertTrue(WGCF_VERSION == "2.2.32")
        assertTrue(THREEPROXY_VERSION == "0.9.7")
        assertTrue("WARP_MTU=1392" in script)
        assertTrue("checksums.txt" in script)
        assertTrue("sha256sum" in script)
        assertTrue("--accept-tos" in script)
        assertTrue("wdtt-warp-watchdog.timer" in script)
        assertTrue("wdtt_warp_autotune" in script)
        assertTrue("WARP_ENDPOINT_CANDIDATES" in script)
        assertTrue("engage.cloudflareclient.com:2408" in script)
        assertTrue("rollback after WARP check error" in script)
        assertTrue("trap wdtt_wg_up_cleanup 0" in script)
        assertTrue("rollback after WireGuard service start error" in script)
        assertTrue("WDTT_ERROR=wireguard_exit_service_inactive" in script)
        assertTrue("ip link delete \"${'$'}WDTT_WG_IFACE\"" in script)
        assertShellSyntax(script)
    }

    @Test
    fun directExitScript_forceCleansPartiallyStartedWireGuard() {
        val script = disableOutboundExitScript()

        assertTrue("wdtt_clear_external_out" in script)
        assertTrue("ip link delete \"${'$'}WDTT_WG_IFACE\"" in script)
        assertTrue("WDTT_ERROR=direct_cleanup_failed" in script)
        assertTrue("wdtt_write_mode \"direct\"" in script)
        assertShellSyntax(script)
    }

    @Test
    fun outboundCleanupScripts_areScopedAndHaveValidShellSyntax() {
        val localStop = stopLocalProxyScript()
        val localRemove = removeLocalProxyScript()
        val external = deleteExternalProxyScript()
        val imported = deleteImportedWireGuardExitScript()
        val currentVps = deleteWireGuardVpsCurrentScript()
        val foreignVps = deleteWireGuardVpsForeignScript()

        assertTrue("systemctl disable --now wdtt-3proxy" in localStop)
        assertTrue("local_proxy_service_still_active" in localStop)
        assertTrue("LOCAL_PROXY_PASSWORD_B64" in localRemove)
        assertTrue("local_proxy_remove_failed" in localRemove)
        assertTrue("wdtt_clear_proxy_out" in external)
        assertTrue("EXTERNAL_PROXY_PASSWORD_B64" in external)
        assertTrue("external_proxy_remove_failed" in external)
        assertTrue("OWNS_ACTIVE" in imported)
        assertTrue("wdtt_clear_wireguard_out" in imported)
        assertTrue("IMPORTED_WG_CONFIG_B64" in imported)
        assertTrue("wireguard_vps_current_remove_failed" in currentVps)
        assertTrue("WDTT_EXIT_FOREIGN" in foreignVps)
        assertTrue("foreign_wireguard_not_owned" in foreignVps)
        assertShellSyntax(localStop)
        assertShellSyntax(localRemove)
        assertShellSyntax(external)
        assertShellSyntax(imported)
        assertShellSyntax(currentVps)
        assertShellSyntax(foreignVps)
    }

    @Test
    fun protocolErrorMarker_isNotCopiedRawToUserLog() {
        assertFalse(shouldWriteRemoteErrorToUserLog("WDTT_ERROR=local_proxy_check_failed"))
        assertTrue(shouldWriteRemoteErrorToUserLog("FAIL: служба не запустилась"))
    }

    @Test
    fun serverDiagnosticsScript_hasPortableChecksAndValidShellSyntax() {
        val script = serverDiagnosticsScript()

        assertTrue("WDTT_SERVER_DIAG" in script)
        assertTrue("apt-get dnf yum zypper apk pacman" in script)
        assertTrue("wdtt_diag_install_dependencies" in script)
        assertTrue("DEBIAN_FRONTEND=noninteractive apt-get install" in script)
        assertTrue("dnf install -y" in script)
        assertTrue("yum install -y" in script)
        assertTrue("zypper --non-interactive install" in script)
        assertTrue("apk add --no-cache" in script)
        assertTrue("pacman -Sy --noconfirm --needed" in script)
        assertTrue("systemctl" in script)
        assertTrue("iptables" in script)
        assertTrue("nft" in script)
        assertTrue("VK/OK с VPS (справочно)" in script)
        assertTrue("не влияет на основной VK-вход" in script)
        assertTrue("login.vk.ru" in script)
        assertTrue("api.vk.me" in script)
        assertTrue("api.vk.ru" in script)
        assertTrue("calls.okcdn.ru" in script)
        assertTrue("Получение VK-токенов и решение капчи выполняются на телефоне" in script)
        assertFalse("обязательным узлам VK в зоне .ru" in script)
        assertTrue("api.telegram.org" in script)
        assertTrue("Бесплатный WARP" in script)
        assertTrue("engage.cloudflareclient.com" in script)
        assertTrue("wdtt_diag_wg_exit_probe" in script)
        assertTrue("Cloudflare подтвердил warp=" in script)
        assertTrue("WG_POLICY_RULE_ACTIVE" in script)
        assertTrue("WG_DEFAULT_ROUTE_ACTIVE" in script)
        assertTrue("WG_NAT_ACTIVE" in script)
        assertTrue("WireGuard-выход запущен не полностью" in script)
        assertTrue("FIREWALL_SEVERITY=\"ERROR\"" in script)
        assertTrue("NAT прямого выхода отсутствует" in script)
        assertTrue("WDTT_EXPECTED_DTLS_PORT" in script)
        assertTrue("wdtt_diag_udp_probe" in script)
        assertTrue("/dev/net/tun" in script)
        assertTrue("admin.sock" in script)
        assertFalse("PrivateKey =" in script)
        assertShellSyntax(script, shell = "sh")
    }

    @Test
    fun externalProxyTransparentCheck_doesNotCaptureRootXrayTraffic() {
        val script = outboundShellPrelude()

        assertTrue("WDTT_PROXY_TEST_SOURCE=\"${'$'}test_source\"" in script)
        assertTrue("iptables -t nat -I OUTPUT -s \"${'$'}test_source\" -p tcp -j WDTT_PROXY_TEST" in script)
        assertTrue("curl --interface \"${'$'}test_source\"" in script)
        assertFalse("iptables -t nat -I OUTPUT -p tcp -m owner --uid-owner 0 -j WDTT_PROXY_TEST" in script)
        assertShellSyntax(script)
    }

    @Test
    fun outboundSnapshot_preservesExplicitlySavedEmptyFields() {
        val script = outboundSnapshotScript()

        assertTrue("wdtt_profile_has_key" in script)
        assertTrue("if wdtt_profile_has_key LOCAL_PROXY_LOGIN_B64" in script)
        assertTrue("if wdtt_profile_has_key EXTERNAL_PROXY_HOST_B64" in script)
        assertTrue("if wdtt_profile_has_key WG_VPS_DNS_B64" in script)
        assertTrue("! wdtt_profile_has_key IMPORTED_WG_CONFIG_B64" in script)
        assertTrue("WDTT_LOCAL_PROXY_SERVICE_ENABLED" in script)
        assertTrue("WDTT_EXTERNAL_PROXY_SERVICE_ENABLED" in script)
        assertTrue("WDTT_WG_SERVICE_ENABLED" in script)
        assertShellSyntax(script)
    }

    @Test
    fun detailedOutboundStatus_reportsRoutesAndAutostart() {
        val script = outboundStatusScript()

        assertTrue("Автозапуск внешнего TCP-прокси" in script)
        assertTrue("Правило маршрутизации подсети WDTT" in script)
        assertTrue("NAT WireGuard-выхода" in script)
        assertShellSyntax(script)
    }

    @Test(expected = IllegalArgumentException::class)
    fun freeWarpScript_rejectsUnsafeMtu() {
        buildFreeWarpInstallScript(1600)
    }

    private fun assertShellSyntax(script: String, shell: String = "bash") {
        val file = File.createTempFile("wdtt-warp-", ".sh")
        try {
            file.writeText(script)
            val process = ProcessBuilder(shell, "-n", file.absolutePath)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readText()
            val code = process.waitFor()
            assertTrue("$shell -n завершился с кодом $code: $output", code == 0)
        } finally {
            file.delete()
        }
    }
}
