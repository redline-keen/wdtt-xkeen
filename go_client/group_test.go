package main

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"
)

func TestTerminalGroupCredentialErrors(t *testing.T) {
	for _, message := range []string{"INVALID_JOIN_LINK", "ANON_BLOCKED", "CALL_FULL", "FATAL_AUTH"} {
		if !isTerminalGroupCredentialError(errors.New(message)) {
			t.Fatalf("%q must be terminal", message)
		}
	}
	if isTerminalGroupCredentialError(errors.New("CAPTCHA_WAIT_REQUIRED")) {
		t.Fatal("captcha wait must remain recoverable for an additional group")
	}
}

func TestManagedHashFallbackUsesOnlyHashSpecificFailures(t *testing.T) {
	for _, message := range []string{"INVALID_JOIN_LINK", "ANON_BLOCKED", "CALL_FULL"} {
		if !isHashFallbackCredentialError(errors.New(message)) {
			t.Fatalf("%q must try the next managed-profile hash", message)
		}
	}
	for _, message := range []string{"CAPTCHA_WAIT_REQUIRED", "VK HTTPS timeout", "FATAL_AUTH"} {
		if isHashFallbackCredentialError(errors.New(message)) {
			t.Fatalf("%q must not fan out across all hashes", message)
		}
	}
}

func TestHashRefreshOrderRotatesReserveAfterTurnFailure(t *testing.T) {
	got := hashRefreshOrder(0, 4, true)
	want := []int{1, 2, 3, 0}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("rotated order = %v, want %v", got, want)
	}

	got = hashRefreshOrder(2, 4, false)
	want = []int{2, 3, 0, 1}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("regular refresh order = %v, want %v", got, want)
	}
}

func TestCaptchaCredentialRetryDelay(t *testing.T) {
	if got := groupCredentialRetryDelay(errors.New("CAPTCHA_WAIT_REQUIRED")); got != 90*time.Second {
		t.Fatalf("captcha retry delay = %v", got)
	}
}

func TestWorkerPolicyRetryDelayIsBounded(t *testing.T) {
	if got := workerPolicyRetryDelay(1); got != 5*time.Second {
		t.Fatalf("first policy retry delay = %v", got)
	}
	if got := workerPolicyRetryDelay(100); got != 15*time.Second {
		t.Fatalf("maximum policy retry delay = %v", got)
	}
}

func TestWrapHandshakeRetryUsesShortDedicatedWindow(t *testing.T) {
	minDelay, maxDelay := workerRetryDelayBounds(
		errors.New("WRAP_AUTH_TIMEOUT: отдельный DTLS-канал не ответил вовремя"),
	)
	if minDelay != time.Second || maxDelay != 3*time.Second {
		t.Fatalf("WRAP retry bounds = %v..%v, want 1s..3s", minDelay, maxDelay)
	}

	minDelay, maxDelay = workerRetryDelayBounds(errors.New("TURN Allocate timeout"))
	if minDelay != 5*time.Second || maxDelay != 15*time.Second {
		t.Fatalf("regular retry bounds = %v..%v, want 5s..15s", minDelay, maxDelay)
	}
}

func TestWrapHandshakeTimeoutAllowsFourFlightsBeforeFastRetry(t *testing.T) {
	if got := dtlsHandshakeTimeout(true); got != 8*time.Second {
		t.Fatalf("WRAP handshake timeout = %v, want 8s", got)
	}
	if got := dtlsHandshakeTimeout(false); got != 20*time.Second {
		t.Fatalf("regular handshake timeout = %v, want 20s", got)
	}
}

func TestConfigFirstStartGateOnlyBlocksFollowingWorkersWhenEnabled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	regular := newConfigFirstStartGate(false)
	if err := regular.wait(ctx, 1); err != nil {
		t.Fatalf("regular start path was blocked: %v", err)
	}

	managed := newConfigFirstStartGate(true)
	if err := managed.wait(ctx, 0); err != nil {
		t.Fatalf("config worker was blocked: %v", err)
	}

	waitDone := make(chan error, 1)
	go func() {
		waitDone <- managed.wait(ctx, 1)
	}()
	select {
	case err := <-waitDone:
		t.Fatalf("following worker passed before GETCONF: %v", err)
	case <-time.After(20 * time.Millisecond):
	}

	managed.release()
	select {
	case err := <-waitDone:
		if err != nil {
			t.Fatalf("following worker failed after GETCONF: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("following worker did not start after GETCONF")
	}
}

func TestWebViewTimeoutOrdering(t *testing.T) {
	if captchaAutoWebViewTimeout <= 18*time.Second {
		t.Fatalf("Go auto timeout %v must exceed Android WebView timeout", captchaAutoWebViewTimeout)
	}
	if captchaManualWebViewTimeout <= 180*time.Second {
		t.Fatalf("Go manual timeout %v must exceed Android WebView timeout", captchaManualWebViewTimeout)
	}
	if captchaSelectedWebViewTimeout <= 270*time.Second {
		t.Fatalf("selected timeout %v must cover two auto attempts plus manual fallback", captchaSelectedWebViewTimeout)
	}
}
