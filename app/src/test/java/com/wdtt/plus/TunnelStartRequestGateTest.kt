package com.wdtt.plus

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelStartRequestGateTest {
    @Test
    fun `stop invalidates a delayed start`() {
        val gate = TunnelStartRequestGate()
        val request = gate.next()

        gate.invalidate()

        assertFalse(gate.isCurrent(request))
    }

    @Test
    fun `only the latest profile request may finish`() {
        val gate = TunnelStartRequestGate()
        val first = gate.next()
        val second = gate.next()

        assertFalse(gate.isCurrent(first))
        assertTrue(gate.isCurrent(second))
    }
}
