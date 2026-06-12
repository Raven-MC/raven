package network

import "core:crypto/aes"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:time"

Endpoint :: net.Endpoint

// Reads raw bytes from a TCP socket, one byte at a time or into a buffer.
// Used by read_packet and read_varint_streaming to get data off the wire.
Packet_Reader :: struct {
	conn:      net.TCP_Socket,
	allocator: mem.Allocator,
}

// Writes bytes to a TCP socket. Used by send_framed to send packet bodies
// and their length prefixes. Also used internally by write_bytes for flush.
Packet_Writer :: struct {
	conn:      net.TCP_Socket,
	allocator: mem.Allocator,
}

// Reads a single byte from the TCP connection.
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

// Fills a buffer by reading from the TCP connection. Handles Would_Block by
// sleeping 10ms and retrying (non-blocking socket). Returns only on a real
// error (Connection_Closed, Invalid_Argument, etc.) or success.
read_bytes :: proc(r: ^Packet_Reader, dst: []u8) -> (int, net.TCP_Recv_Error) {
	read := 0
	for read < len(dst) {
		got, err := net.recv_tcp(r.conn, dst[read:])
		if err != nil {
			if err == .Would_Block {
				time.sleep(10 * time.Millisecond)
				continue
			}
			return read, err
		}
		if got == 0 {
			return read, .Connection_Closed
		}
		read += got
	}
	return read, nil
}

// Reads a big-endian integer of type T (u16/i16/u32/i32/u64/i64/f32/f64) from the
// TCP connection. Panics if T is unsupported.
read_int :: proc(r: ^Packet_Reader, $T: typeid) -> (T, net.TCP_Recv_Error) {
	size := size_of(T)
	assert(size <= 16)
	buf: [16]u8
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
	slice := buf[:size]
	when T == u16 || T == i16 {
		return T(endian.unchecked_get_u16be(slice)), nil
	} else when T == u32 || T == i32 {
		return T(endian.unchecked_get_u32be(slice)), nil
	} else when T == u64 || T == i64 {
		return T(endian.unchecked_get_u64be(slice)), nil
	} else when T == f32 {
		return transmute(f32)endian.unchecked_get_u32be(slice), nil
	} else when T == f64 {
		return transmute(f64)endian.unchecked_get_u64be(slice), nil
	} else {
		#panic("read_int: unsupported type")
	}
}

// Writes a single byte to the TCP connection.
write_byte :: proc(w: ^Packet_Writer, b: u8) -> net.TCP_Send_Error {
	buf: [1]u8 = {b}
	_, err := net.send_tcp(w.conn, buf[:])
	return err
}

// Writes a big-endian integer of type T (u16/i16/u32/i32/u64/i64/f32/f64) to the
// TCP connection. Panics if T is unsupported.
write_int :: proc(w: ^Packet_Writer, $T: typeid, value: T) -> net.TCP_Send_Error {
	size := size_of(T)
	assert(size <= 16)
	buf: [16]u8
	slice := buf[:size]
	when T == u16 || T == i16 {
		endian.unchecked_put_u16be(slice, u16(value))
	} else when T == u32 || T == i32 {
		endian.unchecked_put_u32be(slice, u32(value))
	} else when T == u64 || T == i64 {
		endian.unchecked_put_u64be(slice, u64(value))
	} else when T == f32 {
		endian.unchecked_put_u32be(slice, transmute(u32)value)
	} else when T == f64 {
		endian.unchecked_put_u64be(slice, transmute(u64)value)
	} else {
		#panic("write_int: unsupported type")
	}
	_, err := net.send_tcp(w.conn, slice)
	return err
}

// Writes a byte slice to the TCP connection. Handles partial writes (may call
// send_tcp multiple times until fully written or an error occurs).
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

// No-op in this implementation (every write_* call sends immediately).
flush :: proc(w: ^Packet_Writer) -> net.TCP_Send_Error {
	// No-op: TCP writes are immediate in this minimal port.
	_ = w
	return nil
}

// AES-CFB8 stream cipher state for online-mode encryption. Initialised by
// enable_encryption after key exchange. encrypt_cfb8/decrypt_cfb8 process
// one byte at a time; encrypt_bytes/decrypt_bytes batch whole slices.
Cipher_State :: struct {
	aes_ctx:          aes.Context_ECB,
	encrypt_feedback: [16]u8,
	decrypt_feedback: [16]u8,
	encrypt_pos:      int,
	decrypt_pos:      int,
}

// Wraps a listening TCP socket. Created by tcp_server_init and accepts new
// connections via tcp_server_accept (non-blocking). Destroy via tcp_server_destroy.
Tcp_Server :: struct {
	listener:  net.TCP_Socket,
	allocator: mem.Allocator,
}

// Represents a single accepted TCP connection. Created by tcp_server_accept.
// Read/write via tcp_client_reader / tcp_client_writer, close via tcp_client_close.
// May have an active AES-CFB8 cipher (after online-mode handshake) and/or
// compression threshold.
Tcp_Client :: struct {
	conn:                  net.TCP_Socket,
	allocator:             mem.Allocator,
	has_cipher:            bool, // true after online-mode handshake
	cipher:                Cipher_State,
	compression_threshold: i32, // -1 = disabled
}

// Opens a non-blocking TCP listener on the given address:port. Sets SO_REUSEADDR.
tcp_server_init :: proc(
	allocator: mem.Allocator,
	address: string,
	port: int,
) -> (
	Tcp_Server,
	net.Network_Error,
) {
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

// Closes the listening socket.
tcp_server_destroy :: proc(s: ^Tcp_Server) {
	net.close(s.listener)
}

// Accepts a new client connection. Returns Would_Block if no connection is pending
// (non-blocking socket). The returned client has compression disabled and no cipher.
tcp_server_accept :: proc(s: ^Tcp_Server) -> (Tcp_Client, net.Accept_Error) {
	raw, _, err := net.accept_tcp(s.listener) // NOTE: peer address discarded
	if err != nil {
		return {}, err
	}
	net.set_blocking(raw, false)
	return Tcp_Client{conn = raw, allocator = s.allocator, compression_threshold = -1}, nil
}

// Closes a client TCP connection.
tcp_client_close :: proc(c: ^Tcp_Client) {
	net.close(c.conn)
}

// Creates a Packet_Reader wrapping the client's socket.
tcp_client_reader :: proc(c: ^Tcp_Client) -> Packet_Reader {
	return Packet_Reader{conn = c.conn, allocator = c.allocator}
}

// Creates a Packet_Writer wrapping the client's socket.
tcp_client_writer :: proc(c: ^Tcp_Client) -> Packet_Writer {
	return Packet_Writer{conn = c.conn, allocator = c.allocator}
}

// Formats "address:port" for use with net.parse_endpoint.
endpoint_string :: proc(address: string, port: int) -> string {
	return fmt.tprintf("%s:%d", address, port)
}
