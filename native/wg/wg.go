// In-app WireGuard tunnel: wireguard-go + userspace network stack (gVisor),
// exposed to Dart through a local HTTP proxy. No system VPN is created.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"unsafe"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

var (
	mu  sync.Mutex
	dev *device.Device
	srv *http.Server
)

// WgStart starts the tunnel from a wg-quick config.
// Returns the local HTTP proxy port, or "error: …". Free with WgFree.
//
//export WgStart
func WgStart(cfg *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	stop()
	port, err := start(C.GoString(cfg))
	if err != nil {
		return C.CString("error: " + err.Error())
	}
	return C.CString(strconv.Itoa(port))
}

//export WgStop
func WgStop() {
	mu.Lock()
	defer mu.Unlock()
	stop()
}

//export WgFree
func WgFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func stop() {
	if srv != nil {
		srv.Close()
		srv = nil
	}
	if dev != nil {
		dev.Close() // also cuts in-flight CONNECT tunnels
		dev = nil
	}
}

type config struct {
	addrs []netip.Addr
	dns   []netip.Addr
	mtu   int
	iface []string // interface UAPI lines
	peers [][]string
}

// parse turns a wg-quick config (.conf) into netstack parameters + UAPI.
func parse(s string) (*config, error) {
	c := &config{mtu: 1420}
	section := ""
	for _, line := range strings.Split(s, "\n") {
		if i := strings.IndexByte(line, '#'); i >= 0 {
			line = line[:i]
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			section = strings.ToLower(strings.Trim(line, "[] "))
			if section == "peer" {
				c.peers = append(c.peers, nil)
			}
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			return nil, fmt.Errorf("invalid line: %q", line)
		}
		k, v = strings.ToLower(strings.TrimSpace(k)), strings.TrimSpace(v)
		var err error
		switch section + "." + k {
		case "interface.privatekey":
			err = c.addKey(&c.iface, "private_key", v)
		case "interface.listenport":
			c.iface = append(c.iface, "listen_port="+v)
		case "interface.mtu":
			c.mtu, err = strconv.Atoi(v)
		case "interface.address":
			for _, a := range list(v) {
				ip, e := netip.ParseAddr(strings.SplitN(a, "/", 2)[0]) // the mask is ignored
				if e != nil {
					return nil, fmt.Errorf("invalid Address: %q", a)
				}
				c.addrs = append(c.addrs, ip)
			}
		case "interface.dns":
			for _, a := range list(v) {
				if ip, e := netip.ParseAddr(a); e == nil { // search domains are ignored
					c.dns = append(c.dns, ip)
				}
			}
		case "peer.publickey", "peer.presharedkey", "peer.endpoint", "peer.allowedips", "peer.persistentkeepalive":
			if len(c.peers) == 0 {
				return nil, fmt.Errorf("%s outside a [Peer] section", k)
			}
			p := &c.peers[len(c.peers)-1]
			switch k {
			case "publickey":
				err = c.addKey(p, "public_key", v)
			case "presharedkey":
				err = c.addKey(p, "preshared_key", v)
			case "endpoint":
				var a *net.UDPAddr
				if a, err = net.ResolveUDPAddr("udp", v); err == nil {
					*p = append(*p, "endpoint="+a.String())
				}
			case "allowedips":
				for _, a := range list(v) {
					*p = append(*p, "allowed_ip="+a)
				}
			case "persistentkeepalive":
				*p = append(*p, "persistent_keepalive_interval="+v)
			}
		}
		if err != nil {
			return nil, fmt.Errorf("%s: %w", k, err)
		}
	}
	if len(c.addrs) == 0 {
		return nil, fmt.Errorf("missing Address in [Interface]")
	}
	if len(c.peers) == 0 {
		return nil, fmt.Errorf("no [Peer] section")
	}
	return c, nil
}

func (c *config) addKey(dst *[]string, name, b64 string) error {
	k, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(k) != 32 {
		return fmt.Errorf("invalid key")
	}
	*dst = append(*dst, name+"="+hex.EncodeToString(k))
	return nil
}

// uapi renders the config in wireguard-go IPC format; public_key must open each peer.
func (c *config) uapi() string {
	var b strings.Builder
	for _, l := range c.iface {
		b.WriteString(l + "\n")
	}
	for _, p := range c.peers {
		for _, l := range p {
			if strings.HasPrefix(l, "public_key=") {
				b.WriteString(l + "\n")
			}
		}
		for _, l := range p {
			if !strings.HasPrefix(l, "public_key=") {
				b.WriteString(l + "\n")
			}
		}
	}
	return b.String()
}

func list(v string) []string {
	var out []string
	for _, s := range strings.Split(v, ",") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

func start(cfg string) (int, error) {
	c, err := parse(cfg)
	if err != nil {
		return 0, err
	}
	tun, tnet, err := netstack.CreateNetTUN(c.addrs, c.dns, c.mtu)
	if err != nil {
		return 0, err
	}
	d := device.NewDevice(tun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelError, "wg: "))
	if err = d.IpcSet(c.uapi()); err == nil {
		err = d.Up()
	}
	if err != nil {
		d.Close()
		return 0, err
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		d.Close()
		return 0, err
	}

	dial := func(ctx context.Context, _, addr string) (net.Conn, error) {
		if len(c.dns) > 0 {
			return tnet.DialContext(ctx, "tcp", addr) // DNS resolved through the tunnel
		}
		// no DNS in the config: system resolver, connection through the tunnel
		host, port, err := net.SplitHostPort(addr)
		if err != nil {
			return nil, err
		}
		ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
		if err != nil {
			return nil, err
		}
		return tnet.DialContext(ctx, "tcp", net.JoinHostPort(ips[0].Unmap().String(), port))
	}
	tr := &http.Transport{DialContext: dial}

	s := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodConnect { // HTTPS: raw TCP tunnel
			up, err := dial(r.Context(), "tcp", r.Host)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadGateway)
				return
			}
			cl, buf, err := http.NewResponseController(w).Hijack()
			if err != nil {
				up.Close()
				return
			}
			cl.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
			go pipe(up, buf.Reader, cl)
			pipe(cl, up, up)
			return
		}
		r.RequestURI = ""
		resp, err := tr.RoundTrip(r)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		for k, v := range resp.Header {
			w.Header()[k] = v
		}
		w.WriteHeader(resp.StatusCode)
		// flush every chunk so streaming (SSE) keeps working
		rc := http.NewResponseController(w)
		b := make([]byte, 32<<10)
		for {
			n, err := resp.Body.Read(b)
			if n > 0 {
				w.Write(b[:n])
				rc.Flush()
			}
			if err != nil {
				return
			}
		}
	})}
	go s.Serve(ln)
	dev, srv = d, s
	return ln.Addr().(*net.TCPAddr).Port, nil
}

// pipe copies src to dst then closes closer to unblock the other direction.
func pipe(dst io.Writer, src io.Reader, closer io.Closer) {
	io.Copy(dst, src)
	closer.Close()
}

func main() {}
