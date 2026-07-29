package com.wdtt.plus

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

internal object TunnelProfileRuntimeUpdateBus {
    private val mutableRequests = MutableSharedFlow<Int>(
        extraBufferCapacity = 3,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val requests = mutableRequests.asSharedFlow()

    fun request(profileIndex: Int) {
        if (profileIndex in 0..2) {
            mutableRequests.tryEmit(profileIndex)
        }
    }
}

internal fun shouldRequestTunnelProfileRuntimeUpdate(
    updatedProfile: Int,
    activeTunnelProfile: Int?,
    tunnelRunning: Boolean,
    trustedWifiWaiting: Boolean,
): Boolean =
    updatedProfile in 0..2 &&
        activeTunnelProfile == updatedProfile &&
        (tunnelRunning || trustedWifiWaiting)

internal fun tunnelProfileRuntimeConfigurationChanged(
    current: TunnelParams,
    updated: TunnelParams,
): Boolean =
    current.profileIndex == updated.profileIndex &&
        current != updated

internal fun requestTunnelProfileRuntimeUpdate(profileIndex: Int) {
    if (profileIndex !in 0..2) return
    if (
        !shouldRequestTunnelProfileRuntimeUpdate(
            updatedProfile = profileIndex,
            activeTunnelProfile = TunnelManager.activeTunnelProfile.value,
            tunnelRunning = TunnelManager.running.value,
            trustedWifiWaiting = TrustedWifiManager.state.value.waiting,
        )
    ) {
        return
    }
    TunnelProfileRuntimeUpdateBus.request(profileIndex)
}
