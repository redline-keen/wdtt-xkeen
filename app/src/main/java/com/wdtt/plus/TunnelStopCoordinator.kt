package com.wdtt.plus

import android.content.Context
import android.content.Intent
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

enum class TunnelStopResult {
    ALREADY_STOPPED,
    STOPPED,
    TIMED_OUT,
    FAILED;

    val succeeded: Boolean
        get() = this == ALREADY_STOPPED || this == STOPPED
}

object TunnelStopCoordinator {
    const val DEFAULT_TIMEOUT_MS = 20_000L
    const val DIRECT_NETWORK_SETTLE_MS = 1_000L

    suspend fun stopAndAwait(
        context: Context,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS,
    ): TunnelStopResult {
        val appContext = context.applicationContext
        val helper = WireGuardHelper(appContext)
        val managerActive = TunnelManager.running.value ||
            TunnelManager.transition.value != TunnelTransition.IDLE
        val wireGuardActive = runCatching { helper.isTunnelUp() }.getOrDefault(false)
        if (!managerActive && !wireGuardActive) return TunnelStopResult.ALREADY_STOPPED

        val serviceRequested = runCatching {
            appContext.startService(
                Intent(appContext, TunnelService::class.java).apply { action = "STOP" }
            )
        }.isSuccess
        if (!serviceRequested) return TunnelStopResult.FAILED

        val stopped = withTimeoutOrNull(timeoutMs.coerceAtLeast(1_000L)) {
            // The service owns foreground/lifecycle cleanup. Calling the manager as well makes
            // this operation awaitable and repairs a stale `running=false` state with a live
            // WireGuard tunnel. Both paths are idempotent behind the same start/stop mutex.
            TunnelManager.stopAndWait(
                reason = TunnelStopReason.User,
                context = appContext,
                forceVpnRelease = true,
            )
            while (
                TunnelManager.running.value ||
                TunnelManager.transition.value != TunnelTransition.IDLE ||
                helper.isTunnelUp()
            ) {
                delay(50L)
            }
            true
        } == true

        return if (stopped) TunnelStopResult.STOPPED else TunnelStopResult.TIMED_OUT
    }
}
