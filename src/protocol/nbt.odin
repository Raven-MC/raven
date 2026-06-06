package protocol

import "core:mem"

NBT_TAG_END         :: 0
NBT_TAG_BYTE        :: 1
NBT_TAG_SHORT       :: 2
NBT_TAG_INT         :: 3
NBT_TAG_LONG        :: 4
NBT_TAG_FLOAT       :: 5
NBT_TAG_DOUBLE      :: 6
NBT_TAG_BYTE_ARRAY  :: 7
NBT_TAG_STRING      :: 8
NBT_TAG_LIST        :: 9
NBT_TAG_COMPOUND    :: 10
NBT_TAG_INT_ARRAY   :: 11
NBT_TAG_LONG_ARRAY  :: 12

NBT_MAX_DEPTH :: 512

Nbt_List :: struct {
	element_type: u8,
	elements:     []Nbt_Tag,
}

Nbt_Compound :: struct {
	tags: []Nbt_Tag,
}

// Tagged union of every NBT payload variant.
// Matches NBT_TAG_BYTE..NBT_TAG_LONG_ARRAY (1..12).
Nbt_Payload :: union {
	i8,
	i16,
	i32,
	i64,
	f32,
	f64,
	[]u8,
	string,
	Nbt_List,
	Nbt_Compound,
	[]i32,
	[]i64,
}

Nbt_Tag :: struct {
	type:    u8,
	name:    string,
	payload: Nbt_Payload,
}

// --- Reader dispatch ---

read_nbt :: proc(r: ^Buffer_Reader, allocator: mem.Allocator, depth: int = 0) -> (Nbt_Tag, Protocol_Recv_Error) {
	assert(depth <= NBT_MAX_DEPTH)

	tag_type, e0 := br_read_byte(r)
	if e0 != nil { return {}, e0 }
	if tag_type == NBT_TAG_END {
		return Nbt_Tag{type = NBT_TAG_END}, nil
	}
	if tag_type > NBT_TAG_LONG_ARRAY {
		return {}, .Invalid_Argument
	}

	name_len, e1 := read_ushort(r)
	if e1 != nil { return {}, e1 }

	name_buf := make([]u8, name_len, allocator)
	_, e2 := br_read_bytes(r, name_buf)
	if e2 != nil {
		delete(name_buf, allocator)
		return {}, e2
	}

	payload, e3 := read_nbt_payload(r, allocator, tag_type, depth)
	if e3 != nil {
		delete(name_buf, allocator)
		return {}, e3
	}

	return Nbt_Tag{type = tag_type, name = string(name_buf), payload = payload}, nil
}

read_nbt_in_list :: proc(r: ^Buffer_Reader, allocator: mem.Allocator, elem_type: u8, depth: int) -> (Nbt_Tag, Protocol_Recv_Error) {
	assert(depth <= NBT_MAX_DEPTH)
	assert(elem_type >= NBT_TAG_BYTE && elem_type <= NBT_TAG_LONG_ARRAY)

	payload, e := read_nbt_payload(r, allocator, elem_type, depth)
	if e != nil { return {}, e }

	return Nbt_Tag{type = elem_type, payload = payload}, nil
}

// --- Payload readers (one per tag type) ---

@(private)
read_nbt_payload :: proc(r: ^Buffer_Reader, allocator: mem.Allocator, tag_type: u8, depth: int) -> (Nbt_Payload, Protocol_Recv_Error) {
	if tag_type == NBT_TAG_BYTE        { return _read_payload_byte(r) }
	if tag_type == NBT_TAG_SHORT       { return _read_payload_short(r) }
	if tag_type == NBT_TAG_INT         { return _read_payload_int(r) }
	if tag_type == NBT_TAG_LONG        { return _read_payload_long(r) }
	if tag_type == NBT_TAG_FLOAT       { return _read_payload_float(r) }
	if tag_type == NBT_TAG_DOUBLE      { return _read_payload_double(r) }
	if tag_type == NBT_TAG_BYTE_ARRAY  { return _read_payload_byte_array(r, allocator) }
	if tag_type == NBT_TAG_STRING      { return _read_payload_string(r, allocator) }
	if tag_type == NBT_TAG_LIST        { return _read_payload_list(r, allocator, depth) }
	if tag_type == NBT_TAG_COMPOUND    { return _read_payload_compound(r, allocator, depth) }
	if tag_type == NBT_TAG_INT_ARRAY   { return _read_payload_int_array(r, allocator) }
	if tag_type == NBT_TAG_LONG_ARRAY  { return _read_payload_long_array(r, allocator) }
	return {}, .Invalid_Argument
}

@(private)
_read_payload_byte :: proc(r: ^Buffer_Reader) -> (Nbt_Payload, Protocol_Recv_Error) {
	b, e := br_read_byte(r)
	if e != nil { return {}, e }
	return i8(b), nil
}

@(private)
_read_payload_short :: proc(r: ^Buffer_Reader) -> (Nbt_Payload, Protocol_Recv_Error) {
	v, e := read_short(r)
	if e != nil { return {}, e }
	return v, nil
}

@(private)
_read_payload_int :: proc(r: ^Buffer_Reader) -> (Nbt_Payload, Protocol_Recv_Error) {
	v, e := read_int(r)
	if e != nil { return {}, e }
	return v, nil
}

@(private)
_read_payload_long :: proc(r: ^Buffer_Reader) -> (Nbt_Payload, Protocol_Recv_Error) {
	v, e := read_long(r)
	if e != nil { return {}, e }
	return v, nil
}

@(private)
_read_payload_float :: proc(r: ^Buffer_Reader) -> (Nbt_Payload, Protocol_Recv_Error) {
	v, e := read_float(r)
	if e != nil { return {}, e }
	return v, nil
}

@(private)
_read_payload_double :: proc(r: ^Buffer_Reader) -> (Nbt_Payload, Protocol_Recv_Error) {
	v, e := read_double(r)
	if e != nil { return {}, e }
	return v, nil
}

@(private)
_read_payload_byte_array :: proc(r: ^Buffer_Reader, allocator: mem.Allocator) -> (Nbt_Payload, Protocol_Recv_Error) {
	arr_len, e0 := read_int(r)
	if e0 != nil { return {}, e0 }
	if arr_len < 0 { return {}, .Invalid_Argument }

	err: Protocol_Recv_Error
	data := make([]u8, arr_len, allocator)
	defer if err != nil { delete(data, allocator) }
	_, err = br_read_bytes(r, data)
	if err != nil { return {}, err }
	return data, nil
}

@(private)
_read_payload_string :: proc(r: ^Buffer_Reader, allocator: mem.Allocator) -> (Nbt_Payload, Protocol_Recv_Error) {
	str_len, e0 := read_ushort(r)
	if e0 != nil { return {}, e0 }

	err: Protocol_Recv_Error
	buf := make([]u8, str_len, allocator)
	defer if err != nil { delete(buf, allocator) }
	_, err = br_read_bytes(r, buf)
	if err != nil { return {}, err }
	return string(buf), nil
}

@(private)
_read_payload_list :: proc(r: ^Buffer_Reader, allocator: mem.Allocator, depth: int) -> (Nbt_Payload, Protocol_Recv_Error) {
	elem_type, e0 := br_read_byte(r)
	if e0 != nil { return {}, e0 }
	if elem_type > NBT_TAG_LONG_ARRAY { return {}, .Invalid_Argument }

	count, e1 := read_int(r)
	if e1 != nil { return {}, e1 }
	if count < 0 { return {}, .Invalid_Argument }

	err: Protocol_Recv_Error
	elements := make([]Nbt_Tag, count, allocator)
	defer if err != nil {
		for i in 0..<count {
			nbt_destroy(&elements[i], allocator)
		}
		delete(elements, allocator)
	}
	for i in 0..<count {
		elements[i], err = read_nbt_in_list(r, allocator, elem_type, depth + 1)
		if err != nil { return {}, err }
	}
	return Nbt_List{element_type = elem_type, elements = elements}, nil
}

@(private)
_read_payload_compound :: proc(r: ^Buffer_Reader, allocator: mem.Allocator, depth: int) -> (Nbt_Payload, Protocol_Recv_Error) {
	child_tags := make([dynamic]Nbt_Tag, allocator)
	defer delete(child_tags)
	for {
		child, e := read_nbt(r, allocator, depth + 1)
		if e != nil {
			for &t in child_tags { nbt_destroy(&t, allocator) }
			return {}, e
		}
		if child.type == NBT_TAG_END {
			nbt_destroy(&child, allocator)
			break
		}
		append(&child_tags, child)
	}
	out := make([]Nbt_Tag, len(child_tags), allocator)
	copy(out, child_tags[:])
	return Nbt_Compound{tags = out}, nil
}

@(private)
_read_payload_int_array :: proc(r: ^Buffer_Reader, allocator: mem.Allocator) -> (Nbt_Payload, Protocol_Recv_Error) {
	arr_len, e0 := read_int(r)
	if e0 != nil { return {}, e0 }
	if arr_len < 0 { return {}, .Invalid_Argument }

	err: Protocol_Recv_Error
	data := make([]i32, arr_len, allocator)
	defer if err != nil { delete(data, allocator) }
	for i in 0..<arr_len {
		data[i], err = read_int(r)
		if err != nil { return {}, err }
	}
	return data, nil
}

@(private)
_read_payload_long_array :: proc(r: ^Buffer_Reader, allocator: mem.Allocator) -> (Nbt_Payload, Protocol_Recv_Error) {
	arr_len, e0 := read_int(r)
	if e0 != nil { return {}, e0 }
	if arr_len < 0 { return {}, .Invalid_Argument }

	err: Protocol_Recv_Error
	data := make([]i64, arr_len, allocator)
	defer if err != nil { delete(data, allocator) }
	for i in 0..<arr_len {
		data[i], err = read_long(r)
		if err != nil { return {}, err }
	}
	return data, nil
}

// --- Writer dispatch ---

write_nbt :: proc(w: ^Buffer_Writer, tag: Nbt_Tag) -> Protocol_Send_Error {
	assert(tag.type >= NBT_TAG_END && tag.type <= NBT_TAG_LONG_ARRAY)

	if tag.type != NBT_TAG_END {
		if err := bw_write_byte(w, tag.type); err != nil {
			return err
		}
		assert(len(tag.name) <= int(max(u16)))
		if err := bw_write_int(w, u16, u16(len(tag.name))); err != nil {
			return err
		}
		if err := bw_write_bytes(w, transmute([]u8)tag.name); err != nil {
			return err
		}
	}

	if tag.type == NBT_TAG_END {
		return bw_write_byte(w, 0x00)
	}
	return write_nbt_payload(w, tag)
}

write_nbt_in_list :: proc(w: ^Buffer_Writer, tag: Nbt_Tag) -> Protocol_Send_Error {
	assert(tag.type >= NBT_TAG_BYTE && tag.type <= NBT_TAG_LONG_ARRAY)
	return write_nbt_payload(w, tag)
}

@(private)
write_nbt_payload :: proc(w: ^Buffer_Writer, tag: Nbt_Tag) -> Protocol_Send_Error {
	#partial switch v in tag.payload {
	case i8:
		return bw_write_byte(w, u8(v))
	case i16:
		return bw_write_int(w, i16, v)
	case i32:
		return bw_write_int(w, i32, v)
	case i64:
		return bw_write_int(w, i64, v)
	case f32:
		return bw_write_int(w, f32, v)
	case f64:
		return bw_write_int(w, f64, v)
	case []u8:
		return _write_payload_byte_array(w, v)
	case string:
		return _write_payload_string(w, v)
	case Nbt_List:
		return _write_payload_list(w, v)
	case Nbt_Compound:
		return _write_payload_compound(w, v)
	case []i32:
		return _write_payload_int_array(w, v)
	case []i64:
		return _write_payload_long_array(w, v)
	case:
		return .Invalid_Argument
	}
}

// --- Payload writers (one per tag type) ---

@(private)
_write_payload_byte_array :: proc(w: ^Buffer_Writer, data: []u8) -> Protocol_Send_Error {
	if err := bw_write_int(w, i32, i32(len(data))); err != nil {
		return err
	}
	return bw_write_bytes(w, data)
}

@(private)
_write_payload_string :: proc(w: ^Buffer_Writer, str: string) -> Protocol_Send_Error {
	assert(len(str) <= int(max(u16)))
	if err := bw_write_int(w, u16, u16(len(str))); err != nil {
		return err
	}
	return bw_write_bytes(w, transmute([]u8)str)
}

@(private)
_write_payload_list :: proc(w: ^Buffer_Writer, list: Nbt_List) -> Protocol_Send_Error {
	assert(list.element_type >= NBT_TAG_BYTE && list.element_type <= NBT_TAG_LONG_ARRAY)
	if err := bw_write_byte(w, list.element_type); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, i32(len(list.elements))); err != nil {
		return err
	}
	for i in 0..<len(list.elements) {
		if err := write_nbt_in_list(w, list.elements[i]); err != nil {
			return err
		}
	}
	return nil
}

@(private)
_write_payload_compound :: proc(w: ^Buffer_Writer, compound: Nbt_Compound) -> Protocol_Send_Error {
	for i in 0..<len(compound.tags) {
		if err := write_nbt(w, compound.tags[i]); err != nil {
			return err
		}
	}
	return bw_write_byte(w, 0x00)
}

@(private)
_write_payload_int_array :: proc(w: ^Buffer_Writer, data: []i32) -> Protocol_Send_Error {
	if err := bw_write_int(w, i32, i32(len(data))); err != nil {
		return err
	}
	for i in 0..<len(data) {
		if err := bw_write_int(w, i32, data[i]); err != nil {
			return err
		}
	}
	return nil
}

@(private)
_write_payload_long_array :: proc(w: ^Buffer_Writer, data: []i64) -> Protocol_Send_Error {
	if err := bw_write_int(w, i32, i32(len(data))); err != nil {
		return err
	}
	for i in 0..<len(data) {
		if err := bw_write_int(w, i64, data[i]); err != nil {
			return err
		}
	}
	return nil
}

// --- Destroy ---

nbt_destroy :: proc(tag: ^Nbt_Tag, allocator: mem.Allocator) {
	if tag.type == NBT_TAG_END {
		return
	}
	delete(tag.name, allocator)

	#partial switch v in tag.payload {
	case i8, i16, i32, i64, f32, f64:
	case string:
		delete(v, allocator)
	case []u8:
		delete(v, allocator)
	case []i32:
		delete(v, allocator)
	case []i64:
		delete(v, allocator)
	case Nbt_List:
		for &elem in v.elements {
			nbt_destroy(&elem, allocator)
		}
		delete(v.elements, allocator)
	case Nbt_Compound:
		for &t in v.tags {
			nbt_destroy(&t, allocator)
		}
		delete(v.tags, allocator)
	}
	tag.type = NBT_TAG_END
}
