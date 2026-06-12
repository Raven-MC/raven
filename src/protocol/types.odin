package protocol

import "core:encoding/endian"
import "core:encoding/varint"
import "core:mem"
import "core:net"

// Protocol_Send_Error type-aliases net.TCP_Send_Error, so the protocol
// layer need to import `net` directly

// The network layer's Packet_Writer.write_* procedures return errors of
// type `net.TCP_Send_Error`
Protocol_Send_Error :: net.TCP_Send_Error
Protocol_Recv_Error :: net.TCP_Recv_Error

// Buffer_Reader reads from a known-length byte slice.  Used when
// decoding packet bodies that have already been framed off the wire.
Buffer_Reader :: struct {
	data: []u8,
	pos:  int,
}

// Buffer_Writer builds a packet body into a growable byte buffer.
Buffer_Writer :: struct {
	buf:       [dynamic]u8,
	allocator: mem.Allocator,
}

buffer_reader_init :: proc(r: ^Buffer_Reader, data: []u8) {
	r.data = data
	r.pos = 0
}

buffer_writer_init :: proc(w: ^Buffer_Writer, allocator: mem.Allocator, initial_cap := 64) {
	w.buf = make([dynamic]u8, 0, initial_cap, allocator)
	w.allocator = allocator
}

buffer_writer_destroy :: proc(w: ^Buffer_Writer) {
	delete(w.buf)
}

buffer_writer_bytes :: proc(w: ^Buffer_Writer) -> []u8 {
	return w.buf[:]
}

@(private)
_buffer_reader_eof :: proc(r: ^Buffer_Reader) -> bool {
	return r.pos >= len(r.data)
}

br_read_byte :: proc(r: ^Buffer_Reader) -> (u8, Protocol_Recv_Error) {
	if _buffer_reader_eof(r) {
		return 0, .Connection_Closed
	}
	b := r.data[r.pos]
	r.pos += 1
	return b, nil
}

br_read_bytes :: proc(r: ^Buffer_Reader, dst: []u8) -> (int, Protocol_Recv_Error) {
	if _buffer_reader_eof(r) {
		return 0, .Connection_Closed
	}
	n := min(len(dst), len(r.data) - r.pos)
	copy(dst, r.data[r.pos:r.pos + n])
	r.pos += n
	return n, nil
}

br_read_int :: proc(r: ^Buffer_Reader, $T: typeid) -> (T, Protocol_Recv_Error) {
	size := size_of(T)
	if r.pos + size > len(r.data) {
		return 0, .Connection_Closed
	}
	slice := r.data[r.pos:r.pos + size]
	r.pos += size

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
		#panic("br_read_int: unsupported type")
	}
}

bw_write_byte :: proc(w: ^Buffer_Writer, b: u8) -> Protocol_Send_Error {
	append(&w.buf, b)
	return nil
}

bw_write_bytes :: proc(w: ^Buffer_Writer, src: []u8) -> Protocol_Send_Error {
	append(&w.buf, ..src)
	return nil
}

bw_write_int :: proc(w: ^Buffer_Writer, $T: typeid, value: T) -> Protocol_Send_Error {
	size := size_of(T)
	assert(size <= 16)
	buf: [16]u8
	slice := buf[:size]

	when T == u8 || T == i8 {
		slice[0] = u8(value)
	} else when T == u16 || T == i16 {
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
		#panic("bw_write_int: unsupported type")
	}
	append(&w.buf, ..slice)
	return nil
}

bw_write_varint :: proc(w: ^Buffer_Writer, value: i64) -> Protocol_Send_Error {
	// Minecraft VarInt is signed 32-bit, encoded as unsigned LEB128
	// Take the 32-bit two's complement representation then LEB128 encode
	val32 := i32(value)
	buf: [10]u8

	// NOTE: transmute: cast(i32 -> u32) is rejected for negative values
	n, err := varint.encode_uleb128(buf[:], u128(transmute(u32)val32))
	if err != nil {
		return .Unknown
	}

	// Any valid i32 fits in 5 LEB128 bytes; more means a logic bug
	assert(n <= 5)
	append(&w.buf, ..buf[:n])
	return nil
}

bw_write_string :: proc(w: ^Buffer_Writer, s: string) -> Protocol_Send_Error {
	if err := bw_write_varint(w, i64(len(s))); err != nil {
		return err
	}
	return bw_write_bytes(w, transmute([]u8)s)
}

bw_write_position :: proc(w: ^Buffer_Writer, x, y, z: i32) -> Protocol_Send_Error {
	// Packed u64: 26 bits x, 12 bits y, 26 bits z (signed)
	val :=
		(u64(u32(x)) & 0x3FFFFFF) << 38 | (u64(u32(y)) & 0xFFF) << 26 | (u64(u32(z)) & 0x3FFFFFF)
	if err := bw_write_int(w, u64, val); err != nil {
		return err
	}
	return nil
}

bw_write_uuid :: proc(w: ^Buffer_Writer, uuid: [16]u8) -> Protocol_Send_Error {
	tmp := uuid
	return bw_write_bytes(w, tmp[:])
}

// --- Read helpers operating on Buffer_Reader ---

read_varint :: proc(r: ^Buffer_Reader) -> (i32, Protocol_Recv_Error) {
	val, size, err := varint.decode_uleb128_buffer(r.data[r.pos:])
	if err != nil {
		return 0, .Connection_Closed
	}
	if size > 5 {
		return 0, .Invalid_Argument
	}
	r.pos += size
	return i32(val), nil
}

read_ushort :: proc(r: ^Buffer_Reader) -> (u16, Protocol_Recv_Error) {
	return br_read_int(r, u16)
}

read_short :: proc(r: ^Buffer_Reader) -> (i16, Protocol_Recv_Error) {
	return br_read_int(r, i16)
}

read_int :: proc(r: ^Buffer_Reader) -> (i32, Protocol_Recv_Error) {
	return br_read_int(r, i32)
}

read_long :: proc(r: ^Buffer_Reader) -> (i64, Protocol_Recv_Error) {
	return br_read_int(r, i64)
}

read_float :: proc(r: ^Buffer_Reader) -> (f32, Protocol_Recv_Error) {
	v, err := br_read_int(r, u32)
	if err != nil {
		return 0, err
	}
	return transmute(f32)v, nil
}

read_double :: proc(r: ^Buffer_Reader) -> (f64, Protocol_Recv_Error) {
	v, err := br_read_int(r, u64)
	if err != nil {
		return 0, err
	}
	return transmute(f64)v, nil
}

read_ubyte :: proc(r: ^Buffer_Reader) -> (u8, Protocol_Recv_Error) {
	return br_read_byte(r)
}

read_byte :: proc(r: ^Buffer_Reader) -> (i8, Protocol_Recv_Error) {
	b, err := br_read_byte(r)
	return i8(b), err
}

read_boolean :: proc(r: ^Buffer_Reader) -> (bool, Protocol_Recv_Error) {
	b, err := br_read_byte(r)
	return b != 0, err
}

read_string :: proc(r: ^Buffer_Reader) -> (string, Protocol_Recv_Error) {
	length, err := read_varint(r)
	if err != nil {
		return "", err
	}
	if length < 0 || i64(length) > i64(len(r.data) - r.pos) {
		return "", .Connection_Closed
	}
	n := int(length)
	s := string(r.data[r.pos:r.pos + n])
	r.pos += n
	return s, nil
}

read_chat :: proc(r: ^Buffer_Reader) -> (string, Protocol_Recv_Error) {
	return read_string(r)
}

read_uuid :: proc(r: ^Buffer_Reader) -> ([16]u8, Protocol_Recv_Error) {
	uuid: [16]u8
	_, err := br_read_bytes(r, uuid[:])
	return uuid, err
}

read_position :: proc(r: ^Buffer_Reader) -> (Position, Protocol_Recv_Error) {
	val, err := br_read_int(r, u64)

	if err != nil {
		return {}, err
	}

	x_raw := i32(val >> 38)
	y_raw := i32((val >> 26) & 0xFFF)
	z_raw := i32(val & 0x3FFFFFF)

	x := x_raw
	if x >= 1 << 25 {
		x -= 1 << 26
	}

	y := y_raw
	if y >= 1 << 11 {
		y -= 1 << 12
	}

	z := z_raw
	if z >= 1 << 25 {
		z -= 1 << 26
	}

	return Position{x = x, y = y, z = z}, nil
}

Position :: struct {
	x: i32,
	y: i32,
	z: i32,
}

// TODO: Item_Slot is a placeholder (reads/writes item id, count, damage,
// and a TAG_End byte -- no real NBT support)
Item_Slot :: struct {
	item_id: i16,
	count:   u8,
	damage:  i16,
}

write_item_slot :: proc(w: ^Buffer_Writer, slot: Item_Slot) -> Protocol_Send_Error {
	if err := bw_write_int(w, i16, slot.item_id); err != nil {
		return err
	}
	if slot.item_id == -1 {
		return nil
	}
	if err := bw_write_byte(w, slot.count); err != nil {
		return err
	}
	if err := bw_write_int(w, i16, slot.damage); err != nil {
		return err
	}

	// TAG_End NBT marker
	return bw_write_byte(w, 0)
}

read_item_slot :: proc(r: ^Buffer_Reader) -> (Item_Slot, Protocol_Recv_Error) {
	id, e0 := br_read_int(r, i16)
	if e0 != nil {return {}, e0}
	if id == -1 {
		return Item_Slot{item_id = -1}, nil
	}
	count, e1 := br_read_byte(r)
	if e1 != nil {return {}, e1}
	damage, e2 := br_read_int(r, i16)
	if e2 != nil {return {}, e2}

	// TODO: skip NBT (TAG_End placeholder as there is no real NBT yet)
	_, e3 := br_read_byte(r)
	return Item_Slot{item_id = id, count = count, damage = damage}, e3
}

read_metadata :: proc(r: ^Buffer_Reader) -> Protocol_Recv_Error {
	// Metadata is opaque bytes terminated by 0x7F (end marker) -- skip it
	for {
		b, err := br_read_byte(r)
		if err != nil {
			return err
		}
		if b == 0x7F {
			return nil
		}
		// TODO: The proper implementation would read the typed payload
		_ = b // NOTE: metadata byte read and discarded
	}
}

write_metadata_terminator :: proc(w: ^Buffer_Writer) -> Protocol_Send_Error {
	return bw_write_byte(w, 0x7F)
}
