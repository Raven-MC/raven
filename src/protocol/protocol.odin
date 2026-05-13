package protocol

import "core:mem"

// State tracks which protocol phase a client is in.
State :: enum {
	Handshaking,
	Status,
	Login,
	Play,
}

// Handshaking-state serverbound packets.
Handshake :: struct {
	protocol_version: i32,
	server_address:   string,
	server_port:      u16,
	next_state:       i32,
}

read_handshake :: proc(r: ^Buffer_Reader) -> (Handshake, Protocol_Recv_Error) {
	protocol_version, err1 := read_varint(r)
	if err1 != nil {
		return {}, err1
	}
	server_address, err2 := read_string(r)
	if err2 != nil {
		return {}, err2
	}
	server_port, err3 := read_ushort(r)
	if err3 != nil {
		return {}, err3
	}
	next_state, err4 := read_varint(r)
	if err4 != nil {
		return {}, err4
	}
	return Handshake {
		protocol_version = protocol_version,
		server_address   = server_address,
		server_port      = server_port,
		next_state       = next_state,
	}, nil
}

// LegacyServerListPing (0xFE) is a single-byte request.
LegacyServerListPing :: struct {
	payload: u8,
}

read_legacy_ping :: proc(r: ^Buffer_Reader) -> (LegacyServerListPing, Protocol_Recv_Error) {
	b, err := read_ubyte(r)
	return LegacyServerListPing{payload = b}, err
}

_ :: mem
