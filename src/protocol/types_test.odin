package protocol

import "core:testing"

@(test)
test_bw_br_round_trip_int :: proc(t: ^testing.T) {
	// Test that bw_write_int + br_read_int round-trips correctly across
	// all the supported integer types. This pins down the big-endian
	// behaviour that the wire format requires.
	cases := []struct {
		name:  string,
		value: u64,
		out:   u64,
	}{
		// u8 / i8 (1 byte)
		{"u8_0", 0x00, 0x00},
		{"u8_42", 0x2A, 0x2A},
		{"u8_255", 0xFF, 0xFF},
		{"i8_neg1_bitpat", ~u64(0) >> 56, 0xFF},
		{"i8_neg128_bitpat", 0x80, 0x80},
		// u16 / i16 (2 bytes, big-endian)
		{"u16_0", 0x0000, 0x0000},
		{"u16_1", 0x0001, 0x0001},
		{"u16_max", 0xFFFF, 0xFFFF},
		{"i16_neg1_bitpat", 0xFFFF, 0xFFFF},
		// u32 / i32 (4 bytes, big-endian)
		{"u32_1", 0x00000001, 0x00000001},
		{"u32_0x12345678", 0x12345678, 0x12345678},
		{"i32_neg1_bitpat", 0xFFFFFFFF, 0xFFFFFFFF},
		// u64 / i64 (8 bytes, big-endian)
		{"u64_1", 0x0000000000000001, 0x0000000000000001},
		{"u64_pattern", 0x0102030405060708, 0x0102030405060708},
		{"i64_neg1_bitpat", ~u64(0), ~u64(0)},
	}

	for c in cases {
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		// Write as u64 to keep the type uniform across cases.
		err := bw_write_int(&w, u64, c.value)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)

		// Hand-verify the wire bytes are big-endian by reconstructing
		// the value from the bytes and comparing. This is the property
		// that would have failed before the endian fix.
		if c.value <= 0xFF {
			testing.expect_value(t, len(bytes), 8)
			testing.expect_value(t, bytes[7], u8(c.value))
		} else if c.value <= 0xFFFF {
			testing.expect_value(t, len(bytes), 8)
			testing.expect_value(t, bytes[6], u8(c.value >> 8))
			testing.expect_value(t, bytes[7], u8(c.value & 0xFF))
		} else if c.value <= 0xFFFFFFFF {
			testing.expect_value(t, len(bytes), 8)
			testing.expect_value(t, bytes[4], u8(c.value >> 24))
			testing.expect_value(t, bytes[5], u8(c.value >> 16))
			testing.expect_value(t, bytes[6], u8(c.value >> 8))
			testing.expect_value(t, bytes[7], u8(c.value & 0xFF))
		} else {
			testing.expect_value(t, len(bytes), 8)
			testing.expect_value(t, bytes[0], u8(c.value >> 56))
			testing.expect_value(t, bytes[1], u8(c.value >> 48))
			testing.expect_value(t, bytes[2], u8(c.value >> 40))
			testing.expect_value(t, bytes[3], u8(c.value >> 32))
			testing.expect_value(t, bytes[4], u8(c.value >> 24))
			testing.expect_value(t, bytes[5], u8(c.value >> 16))
			testing.expect_value(t, bytes[6], u8(c.value >> 8))
			testing.expect_value(t, bytes[7], u8(c.value & 0xFF))
		}

		// Now read it back.
		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		v, e := br_read_int(&r, u64)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, v, c.out)

		buffer_writer_destroy(&w)
	}
}

@(test)
test_bw_br_round_trip_floats :: proc(t: ^testing.T) {
	// f32 / f64 use the same bw_write_int / br_read_int path with
	// `transmute` for bit reinterpretation.  Round-trip a few vectors.
	f32_cases := []f32{0.0, 1.0, -1.0, 3.14159, 1.0e30, -1.0e-30}
	for v in f32_cases {
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_int(&w, f32, v)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), 4)

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		got, e := br_read_int(&r, f32)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, got, v)

		buffer_writer_destroy(&w)
	}

	f64_cases := []f64{0.0, 1.0, -1.0, 3.14159265358979, 1.0e100, -1.0e-100}
	for v in f64_cases {
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_int(&w, f64, v)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), 8)

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		got, e := br_read_int(&r, f64)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, got, v)

		buffer_writer_destroy(&w)
	}
}

@(test)
test_bw_br_short_types :: proc(t: ^testing.T) {
	// Cover the u8/i8/u16/i16 branches with explicit calls (the
	// generic `bw_write_int` is monomorphised per call site).
	{
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_int(&w, i8, -42)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), 1)
		// -42 as i8 is bit pattern 0xD6.
		testing.expect_value(t, bytes[0], ~u8(41))
		buffer_writer_destroy(&w)
	}
	{
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_int(&w, u8, 200)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), 1)
		testing.expect_value(t, bytes[0], 200)
		buffer_writer_destroy(&w)
	}
	{
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_int(&w, i16, -12345)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), 2)
		// big-endian: high byte first.  Odin's `>>` on signed integers
		// is truncating division toward zero -- `i16(-12345) >> 8`
		// is -48, not -49 as an arithmetic shift would give.  And `&`
		// has lower precedence than `>>`, so `>> 8 & 0xFF` masks -48
		// and yields 208, not the high byte 0xCF.  `u16(i16(-12345))`
		// is rejected for negative values, so use `transmute`.
		v_u16 := transmute(u16)i16(-12345)
		testing.expect_value(t, bytes[0], u8(v_u16 >> 8))
		testing.expect_value(t, bytes[1], u8(v_u16 & 0xFF))

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		got, e := br_read_int(&r, i16)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, got, i16(-12345))
		buffer_writer_destroy(&w)
	}
}

@(test)
test_varint_round_trip :: proc(t: ^testing.T) {
	// Minecraft VarInt: unsigned LEB128, 5 bytes max for 32-bit values.
	// Spec-verified wire bytes from
	// https://minecraft.wiki/w/Java_Edition_protocol/Packets?oldid=2772055
	cases := []struct {
		value: i32,
		want:  []u8,
	}{
		{0,          {0x00}},
		{1,          {0x01}},
		{127,        {0x7F}},
		{128,        {0x80, 0x01}},
		{255,        {0xFF, 0x01}},
		{256,        {0x80, 0x02}},
		{16383,      {0xFF, 0x7F}},
		{16384,      {0x80, 0x80, 0x01}},
		{2147483647, {0xFF, 0xFF, 0xFF, 0xFF, 0x07}},
		{-1,         {0xFF, 0xFF, 0xFF, 0xFF, 0x0F}},
		{-2147483648, {0x80, 0x80, 0x80, 0x80, 0x08}},
	}
	for c in cases {
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_varint(&w, i64(c.value))
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), len(c.want))
		if len(bytes) == len(c.want) {
			for i in 0..<len(bytes) {
				testing.expect_value(t, bytes[i], c.want[i])
			}
		}

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		got, e := read_varint(&r)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, got, c.value)
		buffer_writer_destroy(&w)
	}
}

@(test)
test_position_round_trip :: proc(t: ^testing.T) {
	// 26/12/26 packed signed position. Test the documented ranges
	// and a few boundary values.
	cases := []Position{
		{0, 0, 0},
		{1, 64, -1},
		{-1, 127, 1},
		{33554431, 2047, 33554431},     // max  positive  26 / 12 / 26
		{-33554432, -2048, -33554432},  // min  negative  26 / 12 / 26
		{100000, 100, -100000},
	}
	for p_in in cases {
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_position(&w, p_in.x, p_in.y, p_in.z)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)
		testing.expect_value(t, len(bytes), 8)

		// Hand-verify the first byte of the packed value.  26 bits of
		// x go into bits 38..63 of the u64; the first byte (bits
		// 56..63) is therefore `u8(x_u32 >> 18)`.  y lives in bits
		// 26..37 so it does not contribute to the first byte.
		x_u32 := to_u32(p_in.x)
		testing.expect_value(t, bytes[0], u8(x_u32 >> 18))

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		p_out, e := read_position(&r)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, p_out.x, p_in.x)
		testing.expect_value(t, p_out.y, p_in.y)
		testing.expect_value(t, p_out.z, p_in.z)
		buffer_writer_destroy(&w)
	}
}

@(test)
test_string_round_trip :: proc(t: ^testing.T) {
	cases := []string{"", "hello", "with spaces and 数字"}
	for s in cases {
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_string(&w, s)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		got, e := read_string(&r)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, got, s)
		buffer_writer_destroy(&w)
	}
	// The 32K case is heap-allocated by `strings_repeat`, so it has
	// to be freed explicitly -- string literals in `cases` above are
	// static and need no cleanup.
	{
		s := strings_repeat("x", 32767)
		defer delete(s, context.allocator)
		w: Buffer_Writer
		buffer_writer_init(&w, context.allocator)
		err := bw_write_string(&w, s)
		testing.expect_value(t, err, nil)
		bytes := buffer_writer_bytes(&w)

		r: Buffer_Reader
		buffer_reader_init(&r, bytes)
		got, e := read_string(&r)
		testing.expect_value(t, e, nil)
		testing.expect_value(t, got, s)
		buffer_writer_destroy(&w)
	}
}

@(test)
test_nbt_round_trip :: proc(t: ^testing.T) {
	// Build a compound with every tag type, write it, read it back, compare.
	// Uses core:testing for structured comparison.
	nested := Nbt_Tag{
		type = NBT_TAG_COMPOUND,
		name = "nested",
		payload = Nbt_Compound{tags = make([]Nbt_Tag, 1, context.allocator)},
	}
	inner, iok := nested.payload.(Nbt_Compound)
	assert(iok)
	inner.tags[0] = Nbt_Tag{type = NBT_TAG_BYTE, name = "innerByte", payload = i8(77)}

	list_elements := make([]Nbt_Tag, 2, context.allocator)
	list_elements[0] = Nbt_Tag{type = NBT_TAG_SHORT, payload = i16(100)}
	list_elements[1] = Nbt_Tag{type = NBT_TAG_SHORT, payload = i16(-200)}

	byte_arr := make([]u8, 4, context.allocator)
	byte_arr[0] = 10; byte_arr[1] = 20; byte_arr[2] = 30; byte_arr[3] = 255

	int_arr := make([]i32, 3, context.allocator)
	int_arr[0] = -1000; int_arr[1] = 0; int_arr[2] = 1000

	long_arr := make([]i64, 2, context.allocator)
	long_arr[0] = 9223372036854775807; long_arr[1] = -9223372036854775808

	root := Nbt_Tag{
		type = NBT_TAG_COMPOUND,
		name = "root",
		payload = Nbt_Compound{tags = make([]Nbt_Tag, 12, context.allocator)},
	}
	compound, ok := root.payload.(Nbt_Compound)
	assert(ok)
	compound.tags[0]  = Nbt_Tag{type = NBT_TAG_BYTE,       name = "byte",   payload = i8(42)}
	compound.tags[1]  = Nbt_Tag{type = NBT_TAG_SHORT,      name = "short",  payload = i16(-12345)}
	compound.tags[2]  = Nbt_Tag{type = NBT_TAG_INT,        name = "int",    payload = i32(0x7FFFFFFF)}
	compound.tags[3]  = Nbt_Tag{type = NBT_TAG_LONG,       name = "long",   payload = i64(-1)}
	compound.tags[4]  = Nbt_Tag{type = NBT_TAG_FLOAT,      name = "float",  payload = f32(3.14159)}
	compound.tags[5]  = Nbt_Tag{type = NBT_TAG_DOUBLE,     name = "double", payload = f64(-2.71828)}
	compound.tags[6]  = Nbt_Tag{type = NBT_TAG_STRING,     name = "str",    payload = string("Hello, NBT!")}
	compound.tags[7]  = Nbt_Tag{type = NBT_TAG_BYTE_ARRAY, name = "ba",     payload = byte_arr}
	compound.tags[8]  = Nbt_Tag{type = NBT_TAG_LIST,       name = "list",   payload = Nbt_List{element_type = NBT_TAG_SHORT, elements = list_elements}}
	compound.tags[9]  = nested
	compound.tags[10] = Nbt_Tag{type = NBT_TAG_INT_ARRAY,  name = "ia",     payload = int_arr}
	compound.tags[11] = Nbt_Tag{type = NBT_TAG_LONG_ARRAY, name = "la",     payload = long_arr}

	w: Buffer_Writer
	buffer_writer_init(&w, context.allocator)
	werr := write_nbt(&w, root)
	testing.expect_value(t, werr, nil)
	bytes := buffer_writer_bytes(&w)

	r: Buffer_Reader
	buffer_reader_init(&r, bytes)
	got, rerr := read_nbt(&r, context.allocator)
	testing.expect_value(t, rerr, nil)
	defer nbt_destroy(&got, context.allocator)

	testing.expect_value(t, got.type, root.type)
	testing.expect_value(t, got.name, root.name)

	gc, gok := got.payload.(Nbt_Compound)
	testing.expect(t, gok, "readback root is a compound")
	testing.expect_value(t, len(gc.tags), 12)

	for i in 0..<len(gc.tags) {
		testing.expect_value(t, gc.tags[i].type, compound.tags[i].type)
		testing.expect_value(t, gc.tags[i].name, compound.tags[i].name)
	}

	// Check each tag's payload.
	b, bok := gc.tags[0].payload.(i8)
	testing.expect(t, bok, "tag[0] is i8")
	testing.expect_value(t, b, i8(42))

	s, sok := gc.tags[1].payload.(i16)
	testing.expect(t, sok, "tag[1] is i16")
	testing.expect_value(t, s, i16(-12345))

	iv, ivok := gc.tags[2].payload.(i32)
	testing.expect(t, ivok, "tag[2] is i32")
	testing.expect_value(t, iv, i32(0x7FFFFFFF))

	lv, lvok := gc.tags[3].payload.(i64)
	testing.expect(t, lvok, "tag[3] is i64")
	testing.expect_value(t, lv, i64(-1))

	fv, fvok := gc.tags[4].payload.(f32)
	testing.expect(t, fvok, "tag[4] is f32")
	testing.expect(t, abs_f32(fv - f32(3.14159)) < 1e-5, "float close enough")

	dv, dvok := gc.tags[5].payload.(f64)
	testing.expect(t, dvok, "tag[5] is f64")
	testing.expect(t, abs_f64(dv - f64(-2.71828)) < 1e-12, "double close enough")

	str, stok := gc.tags[6].payload.(string)
	testing.expect(t, stok, "tag[6] is string")
	testing.expect_value(t, str, "Hello, NBT!")

	ba, baok := gc.tags[7].payload.([]u8)
	testing.expect(t, baok, "tag[7] is []u8")
	testing.expect_value(t, len(ba), 4)
	testing.expect_value(t, ba[0], u8(10))
	testing.expect_value(t, ba[3], u8(255))

	lst, lstok := gc.tags[8].payload.(Nbt_List)
	testing.expect(t, lstok, "tag[8] is Nbt_List")
	testing.expect_value(t, lst.element_type, NBT_TAG_SHORT)
	testing.expect_value(t, len(lst.elements), 2)
	e0, eok0 := lst.elements[0].payload.(i16)
	testing.expect(t, eok0, "list[0] is i16")
	testing.expect_value(t, e0, i16(100))
	e1, eok1 := lst.elements[1].payload.(i16)
	testing.expect(t, eok1, "list[1] is i16")
	testing.expect_value(t, e1, i16(-200))

	nc, ncok := gc.tags[9].payload.(Nbt_Compound)
	testing.expect(t, ncok, "tag[9] is Nbt_Compound")
	testing.expect_value(t, len(nc.tags), 1)
	ib, ibok := nc.tags[0].payload.(i8)
	testing.expect(t, ibok, "nested.tag[0] is i8")
	testing.expect_value(t, ib, i8(77))

	ia, iaok := gc.tags[10].payload.([]i32)
	testing.expect(t, iaok, "tag[10] is []i32")
	testing.expect_value(t, len(ia), 3)
	testing.expect_value(t, ia[0], i32(-1000))

	la, laok := gc.tags[11].payload.([]i64)
	testing.expect(t, laok, "tag[11] is []i64")
	testing.expect_value(t, len(la), 2)
	testing.expect_value(t, la[0], i64(9223372036854775807))
	testing.expect_value(t, la[1], i64(-9223372036854775808))

	buffer_writer_destroy(&w)
	delete(compound.tags, context.allocator)
	delete(list_elements, context.allocator)
	delete(byte_arr, context.allocator)
	delete(int_arr, context.allocator)
	delete(long_arr, context.allocator)
	nc2, nc2ok := nested.payload.(Nbt_Compound)
	if nc2ok {
		delete(nc2.tags, context.allocator)
	}
}

abs_f32 :: proc(x: f32) -> f32 {
	return x < 0 ? -x : x
}

abs_f64 :: proc(x: f64) -> f64 {
	return x < 0 ? -x : x
}

// strings_repeat avoids importing core:strings in a test file.
strings_repeat :: proc(s: string, n: int) -> string {
	out := make([]u8, len(s) * n, context.allocator)
	for i in 0..<n {
		copy(out[i*len(s):], s)
	}
	return string(out)
}
