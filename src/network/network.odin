package network

import "core:crypto/aes"
import "core:fmt"
import "core:mem"
import "core:net"

Endpoint :: net.Endpoint

// Packet_Reader reads framed bytes from a TCP connection.
Packet_Reader :: struct {
	conn:      net.TCP_Socket,
	allocator: mem.Allocator,
}

// Packet_Writer writes framed bytes to a TCP connection.
Packet_Writer :: struct {
	conn:      net.TCP_Socket,
	allocator: mem.Allocator,
}

read_byte :: proc(r: ^Packet_Reader) -> (u8, net.TCP_Recv_Error) {
	buf: [1]u8
	got, err := net.recv_tcp(r.conn, buf[:])
	if err != nil {
		return 0, err
	}
	if got == 0 {
		return 0, .Connection_Closed
	}
	return buf[0], nil
}

read_bytes :: proc(r: ^Packet_Reader, dst: []u8) -> (int, net.TCP_Recv_Error) {
	read := 0
	for read < len(dst) {
		got, err := net.recv_tcp(r.conn, dst[read:])
		if err != nil {
			return read, err
		}
		if got == 0 {
			return read, .Connection_Closed
		}
		read += got
	}
	return read, nil
}

read_int :: proc(r: ^Packet_Reader, $T: typeid) -> (T, net.TCP_Recv_Error) {
	size := size_of(T)
	buf: [16]u8
	assert(size <= 16)
	read := 0
	for read < size {
		got, err := net.recv_tcp(r.conn, buf[read:size])
		if err != nil {
			return 0, err
		}
		if got == 0 {
			return 0, .Connection_Closed
		}
		read += got
	}
	return (^T)(&buf[0])^
}

write_byte :: proc(w: ^Packet_Writer, b: u8) -> net.TCP_Send_Error {
	buf: [1]u8 = {b}
	_, err := net.send_tcp(w.conn, buf[:])
	return err
}

write_int :: proc(w: ^Packet_Writer, $T: typeid, value: T) -> net.TCP_Send_Error {
	size := size_of(T)
	buf: [16]u8
	assert(size <= 16)
	(^T)(&buf[0])^ = value
	_, err := net.send_tcp(w.conn, buf[:size])
	return err
}

write_bytes :: proc(w: ^Packet_Writer, src: []u8) -> net.TCP_Send_Error {
	written := 0
	for written < len(src) {
		wrote, err := net.send_tcp(w.conn, src[written:])
		if err != nil {
			return err
		}
		written += wrote
	}
	return nil
}

flush :: proc(w: ^Packet_Writer) -> net.TCP_Send_Error {
	// No-op: TCP writes are immediate in this minimal port.
	_ = w
	return nil
}

// Cipher_State is the AES-CFB8 stream used after online-mode handshake.
// Only `has_cipher` is checked by the rest of the server; the cipher
// state is updated by `enable_encryption`.  The `AesCfb8Stream` from the
// original Zig port is faithfully translated for completeness.
Cipher_State :: struct {
	aes_ctx:          aes.Context_ECB,
	encrypt_feedback: [16]u8,
	decrypt_feedback: [16]u8,
	encrypt_pos:      int,
	decrypt_pos:      int,
}

// Tcp_Server wraps a listening TCP socket.
Tcp_Server :: struct {
	listener:  net.TCP_Socket,
	allocator: mem.Allocator,
}

// Tcp_Client wraps a single accepted connection.
Tcp_Client :: struct {
	conn:                 net.TCP_Socket,
	allocator:            mem.Allocator,
	has_cipher:           bool,
	cipher:               Cipher_State,
	compression_threshold: i32,
}

tcp_server_init :: proc(allocator: mem.Allocator, address: string, port: int) -> (Tcp_Server, net.Network_Error) {
	ep, ok := net.parse_endpoint(endpoint_string(address, port))
	if !ok {
		return {}, net.Parse_Endpoint_Error.Bad_Address
	}
	listener, err := net.listen_tcp(ep, 1000)
	if err != nil {
		return {}, err
	}
	net.set_option(listener, .Reuse_Address, true)
	net.set_blocking(listener, false)
	return Tcp_Server{listener = listener, allocator = allocator}, nil
}

tcp_server_destroy :: proc(s: ^Tcp_Server) {
	net.close(s.listener)
}

tcp_server_accept :: proc(s: ^Tcp_Server) -> (Tcp_Client, net.Accept_Error) {
	raw, _, err := net.accept_tcp(s.listener)
	if err != nil {
		return {}, err
	}
	net.set_blocking(raw, false)
	return Tcp_Client {
		conn                 = raw,
		allocator            = s.allocator,
		compression_threshold = -1,
	}, nil
}

tcp_client_close :: proc(c: ^Tcp_Client) {
	net.close(c.conn)
}

tcp_client_reader :: proc(c: ^Tcp_Client) -> Packet_Reader {
	return Packet_Reader{conn = c.conn, allocator = c.allocator}
}

tcp_client_writer :: proc(c: ^Tcp_Client) -> Packet_Writer {
	return Packet_Writer{conn = c.conn, allocator = c.allocator}
}

endpoint_string :: proc(address: string, port: int) -> string {
	return fmt.tprintf("%s:%d", address, port)
}
