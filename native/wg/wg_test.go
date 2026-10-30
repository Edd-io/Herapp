package main

import (
	"bufio"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"testing"

	"golang.org/x/crypto/curve25519"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

func keypair(t *testing.T) (priv, pub []byte) {
	priv = make([]byte, 32)
	rand.Read(priv)
	pub, err := curve25519.X25519(priv, curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	return priv, pub
}

// Spins up a local "server" WireGuard peer, then checks that a plain HTTP request and a
// CONNECT tunnel go through the proxy to a service only reachable over WireGuard.
func TestTunnel(t *testing.T) {
	sPriv, sPub := keypair(t)
	cPriv, cPub := keypair(t)

	tun, snet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.9.0.1")}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	udp, _ := net.ListenPacket("udp", "127.0.0.1:0")
	port := udp.LocalAddr().(*net.UDPAddr).Port
	udp.Close()
	sdev := device.NewDevice(tun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelError, "srv: "))
	defer sdev.Close()
	if err := sdev.IpcSet(fmt.Sprintf("private_key=%s\nlisten_port=%d\npublic_key=%s\nallowed_ip=10.9.0.2/32\n",
		hex.EncodeToString(sPriv), port, hex.EncodeToString(cPub))); err != nil {
		t.Fatal(err)
	}
	sdev.Up()
	ln, err := snet.ListenTCP(&net.TCPAddr{IP: net.ParseIP("10.9.0.1"), Port: 80})
	if err != nil {
		t.Fatal(err)
	}
	go http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "pong") }))

	cfg := fmt.Sprintf(`[Interface]
PrivateKey = %s
Address = 10.9.0.2/32
# ignored comment

[Peer]
PublicKey = %s
Endpoint = 127.0.0.1:%d
AllowedIPs = 10.9.0.0/24
PersistentKeepalive = 25
`, base64.StdEncoding.EncodeToString(cPriv), base64.StdEncoding.EncodeToString(sPub), port)
	mu.Lock()
	pport, err := start(cfg)
	mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	defer WgStop()
	proxy := fmt.Sprintf("127.0.0.1:%d", pport)

	// plain HTTP relayed by the proxy
	pu, _ := url.Parse("http://" + proxy)
	cl := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
	resp, err := cl.Get("http://10.9.0.1/")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if string(body) != "pong" {
		t.Fatalf("HTTP : %q", body)
	}

	// CONNECT (the path used for HTTPS)
	c, err := net.Dial("tcp", proxy)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	fmt.Fprint(c, "CONNECT 10.9.0.1:80 HTTP/1.1\r\nHost: 10.9.0.1:80\r\n\r\n")
	br := bufio.NewReader(c)
	if r, err := http.ReadResponse(br, nil); err != nil || r.StatusCode != 200 {
		t.Fatalf("CONNECT : %v %v", r, err)
	}
	fmt.Fprint(c, "GET / HTTP/1.1\r\nHost: 10.9.0.1\r\nConnection: close\r\n\r\n")
	r, err := http.ReadResponse(br, nil)
	if err != nil {
		t.Fatal(err)
	}
	body, _ = io.ReadAll(r.Body)
	if string(body) != "pong" {
		t.Fatalf("CONNECT : %q", body)
	}
}

func TestParseErrors(t *testing.T) {
	for _, cfg := range []string{
		"",
		"[Interface]\nPrivateKey = notakey\nAddress = 10.0.0.2/32\n[Peer]\n",
		"[Interface]\nAddress = 10.0.0.2/32\n",
		"PublicKey = x\n",
	} {
		if _, err := parse(cfg); err == nil {
			t.Errorf("config wrongly accepted: %q", cfg)
		}
	}
	c, err := parse("[Interface]\nAddress = 10.0.0.2/32, fd00::2/128\nDNS = 1.1.1.1, example.lan\n[Peer]\nAllowedIPs = 0.0.0.0/0\nPublicKey = " +
		base64.StdEncoding.EncodeToString(make([]byte, 32)) + "\n")
	if err != nil {
		t.Fatal(err)
	}
	if len(c.addrs) != 2 || len(c.dns) != 1 || !strings.HasPrefix(c.uapi(), "public_key=") {
		t.Fatalf("parse : %+v / %q", c, c.uapi())
	}
}
