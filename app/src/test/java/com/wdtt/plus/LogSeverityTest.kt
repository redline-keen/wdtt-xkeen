package com.wdtt.plus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LogSeverityTest {
    @Test
    fun wrapHandshakeRetryMessage_doesNotBlameThePassword() {
        assertEquals(
            "[WRAP] Отдельные каналы не ответили, выполняется повтор",
            WRAP_HANDSHAKE_RETRY_MESSAGE
        )
        assertFalse(WRAP_HANDSHAKE_RETRY_MESSAGE.contains("парол", ignoreCase = true))
    }

    @Test
    fun repeatedTurnWorkerFailures_useOneRecoverableWarningKey() {
        val first = classifyRecoverableWorkerRetry(
            "[ВОРКЕР #1] Ошибка (попытка 1): TURN Allocate: all retransmissions failed for first",
            activeWorkerCount = 3
        )
        val second = classifyRecoverableWorkerRetry(
            "[ВОРКЕР #5] Ошибка (попытка 1): TURN Allocate: all retransmissions failed for second",
            activeWorkerCount = 3
        )

        assertEquals("worker_turn_allocate_retry", first?.first)
        assertEquals(first?.first, second?.first)
        assertEquals(
            "[TURN] Отдельные каналы не получили ответ на Allocate; выполняются повторы; активных=3",
            first?.second
        )
    }

    @Test
    fun fatalWorkerFailure_isNotDowngradedToWarning() {
        val result = classifyRecoverableWorkerRetry(
            "[ВОРКЕР #1] Ошибка (попытка 1): FATAL_AUTH неверный пароль"
        )

        assertNull(result)
    }

    @Test
    fun warningDoesNotCountAsUnreadError() {
        val warning = LogEntry("warning", "Повторяем", severity = LogSeverity.Warning)

        assertFalse(warning.isError)
    }

    @Test
    fun serverExpiredDenialIsRecognizedBeforeLocalizedProtocolMessage() {
        assertTrue(isExpiredAccessAuthFailure("FATAL_AUTH: DENIED:expired"))
        assertTrue(isExpiredAccessAuthFailure("FATAL_AUTH: срок действия пароля истёк"))
        assertFalse(isExpiredAccessAuthFailure("FATAL_AUTH: неверный пароль подключения"))
    }
}
