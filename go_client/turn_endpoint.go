package main

import (
	"fmt"
	"net"
	neturl "net/url"
	"strings"
)

type turnTransport string

const (
	turnTransportUDP turnTransport = "udp"
	turnTransportTCP turnTransport = "tcp"
	turnTransportTLS turnTransport = "tls"
)

type turnEndpoint struct {
	Raw       string
	Host      string
	Port      string
	Scheme    string
	Transport turnTransport
	LegacyUDP bool
}

func normalizeTURNURL(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	return raw
}

func parseTURNEndpoint(raw string) (turnEndpoint, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return turnEndpoint{}, fmt.Errorf("пустой TURN URL")
	}

	withoutQuery := raw
	rawQuery := ""
	if idx := strings.Index(withoutQuery, "?"); idx >= 0 {
		rawQuery = withoutQuery[idx+1:]
		withoutQuery = withoutQuery[:idx]
	}

	scheme := "turn"
	address := withoutQuery
	lower := strings.ToLower(withoutQuery)
	switch {
	case strings.HasPrefix(lower, "turns:"):
		scheme = "turns"
		address = withoutQuery[len("turns:"):]
	case strings.HasPrefix(lower, "turn:"):
		scheme = "turn"
		address = withoutQuery[len("turn:"):]
	}
	address = strings.TrimPrefix(address, "//")

	transport := turnTransportUDP
	values, _ := neturl.ParseQuery(rawQuery)
	if strings.EqualFold(values.Get("transport"), "tcp") {
		transport = turnTransportTCP
	}
	if scheme == "turns" {
		transport = turnTransportTLS
	}

	host, port, err := splitTURNHostPort(address, transport)
	if err != nil {
		return turnEndpoint{}, err
	}
	return turnEndpoint{
		Raw:       raw,
		Host:      host,
		Port:      port,
		Scheme:    scheme,
		Transport: transport,
	}, nil
}

func legacyUDPEndpoint(raw string) (turnEndpoint, error) {
	endpoint, err := parseTURNEndpoint(raw)
	if err != nil {
		return turnEndpoint{}, err
	}
	endpoint.Transport = turnTransportUDP
	endpoint.LegacyUDP = true
	return endpoint, nil
}

func splitTURNHostPort(address string, transport turnTransport) (string, string, error) {
	host, port, err := net.SplitHostPort(address)
	if err == nil {
		return strings.Trim(host, "[]"), port, nil
	}
	defaultPort := "3478"
	if transport == turnTransportTLS {
		defaultPort = "5349"
	}
	if ip := net.ParseIP(strings.Trim(address, "[]")); ip != nil {
		return strings.Trim(address, "[]"), defaultPort, nil
	}
	if strings.Count(address, ":") > 1 {
		return "", "", fmt.Errorf("разбор TURN URL %q: %w", address, err)
	}
	address = strings.TrimSpace(address)
	if address == "" {
		return "", "", fmt.Errorf("пустой адрес TURN")
	}
	return address, defaultPort, nil
}

func (e turnEndpoint) address() string {
	return net.JoinHostPort(e.Host, e.Port)
}

func (e turnEndpoint) key() string {
	return string(e.Transport) + "|" + strings.ToLower(e.Host) + "|" + e.Port
}

func (e turnEndpoint) label() string {
	if e.LegacyUDP {
		return "UDP"
	}
	switch e.Transport {
	case turnTransportTLS:
		return "TLS"
	case turnTransportTCP:
		return "TCP"
	default:
		return "UDP"
	}
}

func sessionTURNCandidates(rawURLs []string, sessionID int, tp *TurnParams) []turnEndpoint {
	if len(rawURLs) == 0 {
		return nil
	}
	selectedIndex := sessionID % len(rawURLs)
	if selectedIndex < 0 {
		selectedIndex = 0
	}

	result := make([]turnEndpoint, 0, len(rawURLs)+3)
	seen := make(map[string]struct{})
	add := func(endpoint turnEndpoint) {
		if tp != nil {
			if tp.Host != "" {
				endpoint.Host = tp.Host
			}
			if tp.Port != "" {
				endpoint.Port = tp.Port
			}
		}
		if endpoint.Host == "" || endpoint.Port == "" {
			return
		}
		key := endpoint.key()
		if _, exists := seen[key]; exists {
			return
		}
		seen[key] = struct{}{}
		result = append(result, endpoint)
	}

	if endpoint, err := legacyUDPEndpoint(rawURLs[selectedIndex]); err == nil {
		add(endpoint)
	}

	for offset := 1; offset < len(rawURLs); offset++ {
		idx := (selectedIndex + offset) % len(rawURLs)
		if endpoint, err := legacyUDPEndpoint(rawURLs[idx]); err == nil {
			add(endpoint)
		}
	}

	for offset := 0; offset < len(rawURLs); offset++ {
		idx := (selectedIndex + offset) % len(rawURLs)
		endpoint, err := parseTURNEndpoint(rawURLs[idx])
		if err != nil {
			continue
		}
		if endpoint.Transport == turnTransportUDP {
			continue
		}
		add(endpoint)
	}

	return result
}
