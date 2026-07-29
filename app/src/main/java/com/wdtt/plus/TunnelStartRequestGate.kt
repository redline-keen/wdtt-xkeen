package com.wdtt.plus

/** Keeps delayed service starts from reviving an obsolete or explicitly stopped request. */
internal class TunnelStartRequestGate {
    private var generation: Long = 0

    @Synchronized
    fun next(): Long {
        generation += 1
        return generation
    }

    @Synchronized
    fun invalidate() {
        generation += 1
    }

    @Synchronized
    fun isCurrent(value: Long): Boolean = value == generation
}
