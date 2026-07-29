package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/cbeuw/connutil"
	"github.com/pion/dtls/v3"
	"github.com/pion/dtls/v3/pkg/crypto/selfsign"
	"github.com/pion/logging"
	"github.com/pion/turn/v5"
)

const (
	workerSendBuf                = 128
	sessionReadTimeout           = 30 * time.Second
	keepalivePongTimeout         = 75 * time.Second
	unansweredUserTrafficTimeout = 45 * time.Second
	readBufSize                  = 1600
	socketBufSize                = 625 * 1024
	keepaliveByte                = 0xFF // DTLS-level keepalive marker
	keepaliveInterval            = 15 * time.Second
	defaultHandshakeTimeout      = 20 * time.Second
	wrapHandshakeTimeout         = 8 * time.Second
)

// Handshake semaphore: limit to 3 concurrent DTLS handshakes
var handshakeSem = make(chan struct{}, 3)

func dtlsHandshakeTimeout(useWrap bool) time.Duration {
	if useWrap {
		return wrapHandshakeTimeout
	}
	return defaultHandshakeTimeout
}

// NullLoggerFactory подавляет логи pion
type NullLoggerFactory struct{}

func (n *NullLoggerFactory) NewLogger(_ string) logging.LeveledLogger { return &NullLogger{} }

type NullLogger struct{}

func (n *NullLogger) Trace(_ string)                    {}
func (n *NullLogger) Tracef(_ string, _ ...interface{}) {}
func (n *NullLogger) Debug(_ string)                    {}
func (n *NullLogger) Debugf(_ string, _ ...interface{}) {}
func (n *NullLogger) Info(_ string)                     {}
func (n *NullLogger) Infof(_ string, _ ...interface{})  {}
func (n *NullLogger) Warn(_ string)                     {}
func (n *NullLogger) Warnf(_ string, _ ...interface{})  {}
func (n *NullLogger) Error(_ string)                    {}
func (n *NullLogger) Errorf(_ string, _ ...interface{}) {}

// connectedUDPConn — обёртка для connected UDP socket → PacketConn
type connectedUDPConn struct{ *net.UDPConn }

func (c *connectedUDPConn) WriteTo(p []byte, _ net.Addr) (int, error) { return c.Write(p) }

func openTURNAllocation(
	ctx context.Context,
	endpoint turnEndpoint,
	peer *net.UDPAddr,
	creds *Credentials,
	sessionID int,
) (*turn.Client, net.PacketConn, error) {
	turnAddr := endpoint.address()

	var turnConn net.PacketConn
	switch endpoint.Transport {
	case turnTransportUDP:
		resolved, err := net.ResolveUDPAddr("udp", turnAddr)
		if err != nil {
			return nil, nil, fmt.Errorf("TURN UDP резолв %s: %w", turnAddr, err)
		}
		c, err := net.DialUDP("udp", nil, resolved)
		if err != nil {
			return nil, nil, fmt.Errorf("TURN UDP подключение %s: %w", turnAddr, err)
		}
		_ = c.SetReadBuffer(socketBufSize)
		_ = c.SetWriteBuffer(socketBufSize)
		turnConn = &connectedUDPConn{c}
	case turnTransportTCP:
		dialCtx, cancel := context.WithTimeout(ctx, 6*time.Second)
		defer cancel()
		dialer := &net.Dialer{Timeout: 6 * time.Second, KeepAlive: 30 * time.Second}
		conn, err := dialer.DialContext(dialCtx, "tcp", turnAddr)
		if err != nil {
			return nil, nil, fmt.Errorf("TURN TCP подключение %s: %w", turnAddr, err)
		}
		turnConn = turn.NewSTUNConn(conn)
	case turnTransportTLS:
		dialCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
		defer cancel()
		tlsConfig := &tls.Config{MinVersion: tls.VersionTLS12}
		if net.ParseIP(endpoint.Host) == nil {
			tlsConfig.ServerName = endpoint.Host
		}
		dialer := &tls.Dialer{
			NetDialer: &net.Dialer{Timeout: 8 * time.Second, KeepAlive: 30 * time.Second},
			Config:    tlsConfig,
		}
		conn, err := dialer.DialContext(dialCtx, "tcp", turnAddr)
		if err != nil {
			return nil, nil, fmt.Errorf("TURN TLS подключение %s: %w", turnAddr, err)
		}
		turnConn = turn.NewSTUNConn(conn)
	default:
		return nil, nil, fmt.Errorf("неподдерживаемый TURN transport: %s", endpoint.Transport)
	}

	// RequestedAddressFamily
	var addrFamily turn.RequestedAddressFamily
	if peer.IP.To4() != nil {
		addrFamily = turn.RequestedAddressFamilyIPv4
	} else {
		addrFamily = turn.RequestedAddressFamilyIPv6
	}

	tc, err := turn.NewClient(&turn.ClientConfig{
		STUNServerAddr:         turnAddr,
		TURNServerAddr:         turnAddr,
		Conn:                   turnConn,
		Username:               creds.User,
		Password:               creds.Pass,
		RequestedAddressFamily: addrFamily,
		LoggerFactory:          &NullLoggerFactory{},
	})
	if err != nil {
		_ = turnConn.Close()
		return nil, nil, fmt.Errorf("TURN %s клиент %s: %w", endpoint.label(), turnAddr, err)
	}

	if err = tc.Listen(); err != nil {
		tc.Close()
		return nil, nil, fmt.Errorf("TURN %s Listen %s: %w", endpoint.label(), turnAddr, err)
	}

	relay, err := tc.Allocate()
	if err != nil {
		if isAuthError(err) {
			handleAuthError(creds.CacheStreamID)
		}
		errStr := err.Error()
		if strings.Contains(errStr, "Quota") || strings.Contains(errStr, "486") {
			tc.Close()
			return nil, nil, fmt.Errorf("TURN квота: %w", err)
		}
		tc.Close()
		return nil, nil, fmt.Errorf("TURN %s Allocate %s: %w", endpoint.label(), turnAddr, err)
	}

	return tc, relay, nil
}

func isCredentialTURNError(err error) bool {
	if err == nil {
		return false
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "turn квота") ||
		strings.Contains(text, "turn allocate auth") ||
		strings.Contains(text, "invalid credential") ||
		strings.Contains(text, "stale nonce") ||
		strings.Contains(text, "allocation mismatch") ||
		strings.Contains(text, "attribute not found") ||
		strings.Contains(text, "error 508") ||
		strings.Contains(text, "quota")
}

func RunSession(
	ctx context.Context,
	tp *TurnParams,
	peer *net.UDPAddr,
	d *Dispatcher,
	localPort string,
	getConfig bool,
	configCh chan<- string,
	requireConfig bool,
	onConfigDelivered func(),
	sessionID int,
	creds *Credentials,
	deviceID, password, deviceInfo, transportSession string,
	stats *Stats,
) (bool, error) {
	configDelivered := false

	if len(creds.TurnURLs) == 0 {
		return false, fmt.Errorf("нет TURN URL в учетных данных")
	}
	candidates := sessionTURNCandidates(creds.TurnURLs, sessionID, tp)
	if len(candidates) == 0 {
		return false, fmt.Errorf("нет пригодных TURN URL в учетных данных")
	}

	var tc *turn.Client
	var relay net.PacketConn
	var selectedEndpoint turnEndpoint
	var lastTURNErr error
	var err error
	for idx, candidate := range candidates {
		if idx == 0 {
			log.Printf("[СЕССИЯ #%d] TURN %s (%s)", sessionID, candidate.label(), candidate.address())
		} else {
			log.Printf("[СЕССИЯ #%d] [TURN] Резервный путь %s (%s) после ошибки: %v", sessionID, candidate.label(), candidate.address(), lastTURNErr)
		}

		tc, relay, err = openTURNAllocation(ctx, candidate, peer, creds, sessionID)
		if err == nil {
			selectedEndpoint = candidate
			break
		}
		lastTURNErr = err
		if isCredentialTURNError(err) {
			return false, err
		}
	}
	if lastTURNErr != nil && relay == nil {
		return false, lastTURNErr
	}
	defer tc.Close()
	defer relay.Close()

	// Reset error count on successful allocation
	getStreamCache(creds.CacheStreamID).errorCount.Store(0)

	log.Printf("[СЕССИЯ #%d] Relay: %s через TURN %s", sessionID, relay.LocalAddr(), selectedEndpoint.label())

	// Pipe для DTLS ↔ TURN relay
	pipeA, pipeB := connutil.AsyncPacketPipe()

	sessCtx, sessCancel := context.WithCancel(ctx)
	defer sessCancel()

	// Keepalive goroutine (TURN binding request)
	var sessionWg sync.WaitGroup
	sessionWg.Add(1)
	go func() {
		defer sessionWg.Done()
		t := time.NewTicker(10 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-sessCtx.Done():
				return
			case <-t.C:
				tc.SendBindingRequest()
			}
		}
	}()

	// Relay ↔ Pipe proxy (with RTP obfuscation)
	var relayWg sync.WaitGroup
	relayWg.Add(2)

	useWrap := len(tp.WrapKey) == wrapKeyLen

	// Initialize obfs config per session
	var obfsCfg *ObfsConfig
	var obfsWriteState *ObfsState
	if useWrap {
		obfsCfg = NewObfsConfig()
		obfsWriteState = NewObfsState()
	}

	stopRelay := context.AfterFunc(sessCtx, func() {
		_ = relay.SetDeadline(time.Now())
		_ = pipeA.SetDeadline(time.Now())
	})
	defer stopRelay()

	// relay → pipeA (UNWRAP: strip RTP header + decrypt)
	go func() {
		defer relayWg.Done()
		defer sessCancel()
		// Max incoming: RTP header (12) + AEAD tag (16) + padding.
		readBufLen := readBufSize + 80
		buf := make([]byte, readBufLen)
		plain := make([]byte, readBufSize)
		for {
			n, _, readErr := relay.ReadFrom(buf)
			if readErr != nil {
				return
			}
			payload := buf[:n]
			if useWrap {
				if !obfsIsRTPPacket(payload) {
					log.Printf("[СЕССИЯ #%d] OBFS unwrap: unexpected packet (n=%d)", sessionID, n)
					continue
				}
				m, wrapErr := obfsUnwrapPacket(tp.WrapKey, payload, plain)
				if wrapErr != nil {
					log.Printf("[СЕССИЯ #%d] OBFS unwrap: %v (n=%d)", sessionID, wrapErr, n)
					continue
				}
				payload = plain[:m]
			}
			if _, writeErr := pipeA.WriteTo(payload, peer); writeErr != nil {
				return
			}
		}
	}()

	// pipeA → relay (WRAP: add RTP header + encrypt)
	go func() {
		defer relayWg.Done()
		defer sessCancel()
		b := make([]byte, readBufSize)
		for {
			n, _, readErr := pipeA.ReadFrom(b)
			if readErr != nil {
				return
			}
			out := b[:n]
			if useWrap {
				if obfsCfg != nil && obfsWriteState != nil {
					wrapped, wrapErr := obfsWrapPacket(tp.WrapKey, out, obfsCfg, obfsWriteState)
					if wrapErr != nil {
						log.Printf("[СЕССИЯ #%d] OBFS wrap: %v", sessionID, wrapErr)
						return
					}
					out = wrapped
				}
			}
			if _, writeErr := relay.WriteTo(out, peer); writeErr != nil {
				return
			}
		}
	}()

	// DTLS с поддержкой Connection ID (без SNI)
	cert, err := selfsign.GenerateSelfSigned()
	if err != nil {
		return false, fmt.Errorf("генерация сертификата: %w", err)
	}

	// Acquire handshake semaphore
	select {
	case handshakeSem <- struct{}{}:
	case <-sessCtx.Done():
		return false, sessCtx.Err()
	}

	dtlsCfg := &dtls.Config{
		Certificates:          []tls.Certificate{cert},
		InsecureSkipVerify:    true,
		ExtendedMasterSecret:  dtls.RequireExtendedMasterSecret,
		CipherSuites:          []dtls.CipherSuiteID{dtls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256},
		ConnectionIDGenerator: dtls.OnlySendCIDGenerator(),
		// No ServerName (SNI) — less detectable by DPI
	}

	dtlsConn, err := dtls.Client(pipeB, peer, dtlsCfg)
	if err != nil {
		<-handshakeSem
		return false, fmt.Errorf("DTLS клиент: %w", err)
	}
	defer dtlsConn.Close()

	hctx, hcancel := context.WithTimeout(sessCtx, dtlsHandshakeTimeout(useWrap))
	log.Printf("[ВОРКЕР #%d] [DTLS] Рукопожатие (Handshake)...", sessionID)
	err = dtlsConn.HandshakeContext(hctx)
	hcancel()
	<-handshakeSem // RELEASE SEMAPHORE IMMEDIATELY AFTER HANDSHAKE

	if err != nil {
		if useWrap {
			errStr := strings.ToLower(err.Error())
			if strings.Contains(errStr, "deadline") || strings.Contains(errStr, "timeout") {
				return false, fmt.Errorf("WRAP_AUTH_TIMEOUT: отдельный DTLS-канал не ответил вовремя")
			}
		}
		return false, fmt.Errorf("DTLS хендшейк до VPS %s не прошёл: %w", peer.String(), err)
	}
	log.Printf("[ВОРКЕР #%d] [DTLS] Соединение установлено ✓", sessionID)

	// Отмена должна прерывать и стартовый GETCONF. Раньше deadline
	// устанавливался только после получения конфига, поэтому остановка во время
	// подключения могла ждать принудительного завершения процесса на Android.
	stopDTLS := context.AfterFunc(sessCtx, func() {
		_ = dtlsConn.SetDeadline(time.Now())
	})
	defer stopDTLS()

	stats.ActiveConnections.Add(1)
	globalActiveConnections.Add(1)
	defer func() {
		stats.ActiveConnections.Add(-1)
		globalActiveConnections.Add(-1)
	}()

	// Запрос конфига
	if getConfig && configCh != nil {
		conf, confErr := RequestConfig(
			sessCtx,
			dtlsConn,
			localPort,
			deviceID,
			password,
			deviceInfo,
			transportSession,
		)
		if confErr != nil {
			if _, limited := workerPolicyLimit(confErr); limited {
				return false, confErr
			}
			errStr := confErr.Error()
			if strings.Contains(errStr, "FATAL_AUTH") {
				return false, confErr
			}
			if requireConfig {
				return false, fmt.Errorf("регистрация нового подключения: %w", confErr)
			}
			log.Printf("[ВОРКЕР #%d] Ошибка конфига: %v", sessionID, confErr)
		} else if conf != "" {
			select {
			case configCh <- conf:
				configDelivered = true
				log.Printf("[ВОРКЕР #%d] Конфиг получен", sessionID)
			default:
				configDelivered = true
				log.Printf("[ВОРКЕР #%d] Конфиг уже был доставлен другим воркером", sessionID)
			}
			if onConfigDelivered != nil {
				onConfigDelivered()
			}
		} else {
			if requireConfig {
				return false, fmt.Errorf("сервер ещё не выдал WireGuard-конфиг")
			}
			log.Printf("[ВОРКЕР #%d] Сервер ещё не выдал WireGuard-конфиг, повторим позже", sessionID)
		}
	}

	log.Printf("[ВОРКЕР #%d] [READY] Туннель готов к работе ✓", sessionID)

	// Регистрация в диспетчере
	slot := &WorkerSlot{
		ID:     sessionID,
		SendCh: make(chan []byte, workerSendBuf),
	}
	d.Register(slot)
	defer d.Unregister(slot)

	var lastServerRxAt atomic.Int64
	lastServerRxAt.Store(time.Now().UnixNano())
	var lastUserTrafficAt atomic.Int64
	var keepalivePongSeen atomic.Int32
	policyLimitCh := make(chan int, 1)

	// Proxy DTLS ↔ Dispatcher
	var proxyWg sync.WaitGroup
	proxyWg.Add(4) // writer + reader + keepalive + health monitor

	// DTLS Keepalive: prevents TURN allocation timeout and DTLS idle disconnect
	go func() {
		defer proxyWg.Done()
		defer sessCancel()
		t := time.NewTicker(keepaliveInterval)
		defer t.Stop()
		ping := []byte{keepaliveByte}
		for {
			select {
			case <-sessCtx.Done():
				return
			case <-t.C:
				_ = dtlsConn.SetWriteDeadline(time.Now().Add(5 * time.Second))
				if _, err := dtlsConn.Write(ping); err != nil {
					return
				}
			}
		}
	}()

	// Health monitor: UDP can fail silently, so expect keepalive pongs or user traffic responses.
	go func() {
		defer proxyWg.Done()
		t := time.NewTicker(10 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-sessCtx.Done():
				return
			case <-t.C:
				now := time.Now()
				lastRxUnix := lastServerRxAt.Load()
				lastRx := time.Unix(0, lastRxUnix)

				if keepalivePongSeen.Load() != 0 && now.Sub(lastRx) > keepalivePongTimeout {
					log.Printf("[ВОРКЕР #%d] [HEALTH] сервер не отвечает на keepalive %.0f сек, перезапуск воркера", sessionID, now.Sub(lastRx).Seconds())
					sessCancel()
					return
				}

				lastTxUnix := lastUserTrafficAt.Load()
				if lastTxUnix > lastRxUnix &&
					now.Sub(time.Unix(0, lastTxUnix)) > unansweredUserTrafficTimeout &&
					now.Sub(lastRx) > unansweredUserTrafficTimeout {
					log.Printf("[ВОРКЕР #%d] [HEALTH] отправлен пользовательский трафик, но ответа сервера нет %.0f сек, перезапуск воркера", sessionID, now.Sub(lastRx).Seconds())
					sessCancel()
					return
				}
			}
		}
	}()

	// Writer: dispatcher → DTLS
	go func() {
		defer proxyWg.Done()
		defer sessCancel()
		for {
			select {
			case <-sessCtx.Done():
				return
			case pkt, ok := <-slot.SendCh:
				if !ok {
					return
				}
				_ = dtlsConn.SetWriteDeadline(time.Now().Add(sessionReadTimeout))
				_, writeErr := dtlsConn.Write(pkt)
				putPktBuf(pkt)
				if writeErr != nil {
					log.Printf("[ВОРКЕР #%d] Ошибка Writer: %v", sessionID, writeErr)
					return
				}
				lastUserTrafficAt.Store(time.Now().UnixNano())
			}
		}
	}()

	// Reader: DTLS → dispatcher
	go func() {
		defer proxyWg.Done()
		defer sessCancel()
		for {
			pkt := getPktBuf(2048)
			_ = dtlsConn.SetReadDeadline(time.Now().Add(sessionReadTimeout))
			n, readErr := dtlsConn.Read(pkt)
			if readErr != nil {
				putPktBuf(pkt)
				if sessCtx.Err() != nil {
					return
				}
				if ne, ok := readErr.(net.Error); ok && ne.Timeout() {
					continue
				}
				log.Printf("[ВОРКЕР #%d] Ошибка Reader: %v", sessionID, readErr)
				return
			}

			lastServerRxAt.Store(time.Now().UnixNano())

			if _, policyErr := parseConfigResponse(string(pkt[:n])); policyErr != nil {
				if maxWorkers, limited := workerPolicyLimit(policyErr); limited {
					select {
					case policyLimitCh <- maxWorkers:
					default:
					}
					putPktBuf(pkt)
					return
				}
			}

			// Skip keepalive pong from server
			if n == 1 && pkt[0] == keepaliveByte {
				keepalivePongSeen.Store(1)
				putPktBuf(pkt)
				continue
			}

			pkt = pkt[:n]
			select {
			case d.ReturnCh <- pkt:
			case <-sessCtx.Done():
				putPktBuf(pkt)
				return
			}
		}
	}()

	proxyWg.Wait()
	sessCancel()
	relayWg.Wait()
	sessionWg.Wait()
	_ = pipeA.Close()
	_ = pipeB.Close()
	log.Printf("[СЕССИЯ #%d] Завершена", sessionID)
	select {
	case maxWorkers := <-policyLimitCh:
		return configDelivered, &workerPolicyLimitError{maxWorkers: maxWorkers}
	default:
	}
	return configDelivered, nil
}
