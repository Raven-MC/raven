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
	} {


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
	} {
		{0, {0x00}},
		{1, {0x01}},
		{127, {0x7F}},
		{128, {0x80, 0x01}},
		{255, {0xFF, 0x01}},
		{256, {0x80, 0x02}},
		{16383, {0xFF, 0x7F}},
		{16384, {0x80, 0x80, 0x01}},
		{2147483647, {0xFF, 0xFF, 0xFF, 0xFF, 0x07}},
		{-1, {0xFF, 0xFF, 0xFF, 0xFF, 0x0F}},
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
			for i in 0 ..< len(bytes) {
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
	cases := []Position {
		{0, 0, 0},
		{1, 64, -1},
		{-1, 127, 1},
		{33554431, 2047, 33554431}, // max  positive  26 / 12 / 26
		{-33554432, -2048, -33554432}, // min  negative  26 / 12 / 26
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
		// transmute: cast(i32→u32) is rejected for negative x values.
		x_u32 := transmute(u32)p_in.x
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

// strings_repeat avoids importing core:strings in a test file.
strings_repeat :: proc(s: string, n: int) -> string {
	out := make([]u8, len(s) * n, context.allocator)
	for i in 0 ..< n {
		copy(out[i * len(s):], s)
	}
	return string(out)
}
