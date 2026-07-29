package main

import "testing"

func TestParseTURNEndpointPreservesTransport(t *testing.T) {
	tests := []struct {
		raw       string
		host      string
		port      string
		transport turnTransport
	}{
		{"turn:1.2.3.4:3478?transport=udp", "1.2.3.4", "3478", turnTransportUDP},
		{"turn:turn.example:443?transport=tcp", "turn.example", "443", turnTransportTCP},
		{"turns:turn.example:443?transport=tcp", "turn.example", "443", turnTransportTLS},
		{"turn.example:3478", "turn.example", "3478", turnTransportUDP},
	}
	for _, tt := range tests {
		got, err := parseTURNEndpoint(tt.raw)
		if err != nil {
			t.Fatalf("parseTURNEndpoint(%q) error: %v", tt.raw, err)
		}
		if got.Host != tt.host || got.Port != tt.port || got.Transport != tt.transport {
			t.Fatalf("parseTURNEndpoint(%q) = host=%q port=%q transport=%q", tt.raw, got.Host, got.Port, got.Transport)
		}
	}
}

func TestSessionTURNCandidatesKeepLegacyUDPFirst(t *testing.T) {
	raw := []string{
		"turns:turn.example:443?transport=tcp",
		"turn:1.2.3.4:3478?transport=udp",
		"turn:turn.example:3478?transport=tcp",
	}
	got := sessionTURNCandidates(raw, 0, nil)
	if len(got) < 3 {
		t.Fatalf("not enough candidates: %#v", got)
	}
	if got[0].Transport != turnTransportUDP || !got[0].LegacyUDP || got[0].Host != "turn.example" || got[0].Port != "443" {
		t.Fatalf("first candidate must preserve old UDP behavior, got %#v", got[0])
	}
	foundTLS := false
	foundTCP := false
	for _, endpoint := range got[1:] {
		if endpoint.Transport == turnTransportTLS {
			foundTLS = true
		}
		if endpoint.Transport == turnTransportTCP {
			foundTCP = true
		}
	}
	if !foundTLS || !foundTCP {
		t.Fatalf("expected TCP/TLS fallbacks, got %#v", got)
	}
}

func TestSessionTURNCandidatesApplyOverride(t *testing.T) {
	got := sessionTURNCandidates(
		[]string{"turn:old.example:3478?transport=udp", "turn:new.example:443?transport=tcp"},
		0,
		&TurnParams{Host: "override.example", Port: "5555"},
	)
	if len(got) == 0 {
		t.Fatal("no candidates")
	}
	for _, endpoint := range got {
		if endpoint.Host != "override.example" || endpoint.Port != "5555" {
			t.Fatalf("override not applied: %#v", endpoint)
		}
	}
}
