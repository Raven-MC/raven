package world

import "core:encoding/endian"
import "core:mem"

CHUNK_SIZE :: 16
CHUNK_HEIGHT :: 128

Block_Id :: u8
Block_Metadata :: u8

Block :: struct {
	id:       Block_Id,
	metadata: Block_Metadata,
}

BLOCK_AIR :: Block{}
BLOCK_STONE :: Block {
	id = 1,
}
BLOCK_GRASS :: Block {
	id = 2,
}
BLOCK_DIRT :: Block {
	id = 3,
}

Chunk :: struct {
	x:      i32,
	z:      i32,
	blocks: [CHUNK_SIZE][CHUNK_HEIGHT][CHUNK_SIZE]Block,
}

chunk_init :: proc(x: i32, z: i32, seed: u64) -> Chunk {
	chunk := Chunk {
		x = x,
		z = z,
	}
	generate_terrain(&chunk, seed)
	return chunk
}

get_block :: proc(chunk: ^Chunk, x: int, y: int, z: int) -> Block {
	if x < 0 || x >= CHUNK_SIZE || y < 0 || y >= CHUNK_HEIGHT || z < 0 || z >= CHUNK_SIZE {
		return BLOCK_AIR
	}
	return chunk.blocks[x][y][z]
}

set_block :: proc(chunk: ^Chunk, x: int, y: int, z: int, block: Block) {
	if x < 0 || x >= CHUNK_SIZE || y < 0 || y >= CHUNK_HEIGHT || z < 0 || z >= CHUNK_SIZE {
		return
	}
	chunk.blocks[x][y][z] = block
}

@(private)
generate_terrain :: proc(chunk: ^Chunk, seed: u64) {
	for x in 0 ..< CHUNK_SIZE {
		for z in 0 ..< CHUNK_SIZE {
			wx := i32(x) + chunk.x * i32(CHUNK_SIZE)
			wz := i32(z) + chunk.z * i32(CHUNK_SIZE)
			height := get_height(wx, wz, seed)
			for y in 0 ..< CHUNK_HEIGHT {
				by := i32(y)
				switch {
				case by < height - 3:
					chunk.blocks[x][y][z] = BLOCK_STONE
				case by < height:
					chunk.blocks[x][y][z] = BLOCK_DIRT
				case by == height:
					chunk.blocks[x][y][z] = BLOCK_GRASS
				case:
					chunk.blocks[x][y][z] = BLOCK_AIR
				}
			}
		}
	}
}

@(private)
get_height :: proc(x: i32, z: i32, seed: u64) -> i32 {
	h := simple_hash(x, z, seed)
	normalized := f32(h % 10000) / 10000.0
	return i32(normalized * 20.0) + 10
}

@(private)
simple_hash :: proc(x: i32, z: i32, seed: u64) -> u64 {
	h := seed
	h = h * 31 + u64(x)
	h = h * 31 + u64(z)
	h = h * 31 + (h >> 32)
	return h & 0x7FFFFFFFFFFFFFFF
}

World :: struct {
	allocator: mem.Allocator,
	seed:      u64,
	chunks:    map[u64]Chunk,
}

world_init :: proc(allocator: mem.Allocator, seed: u64) -> World {
	w := World {
		allocator = allocator,
		seed      = seed,
		chunks    = make(map[u64]Chunk, allocator),
	}
	return w
}

world_destroy :: proc(w: ^World) {
	delete(w.chunks)
}

world_tick :: proc(w: ^World) {
	_ = w // NOTE: stub -- no world tick logic yet
}

world_get_chunk :: proc(w: ^World, x: i32, z: i32) -> ^Chunk {
	key := chunk_key(x, z)
	if c, ok := &w.chunks[key]; ok {
		return c
	}
	c := chunk_init(x, z, w.seed)
	w.chunks[key] = c
	return &w.chunks[key]
}

world_get_block_at :: proc(w: ^World, x: i32, y: i32, z: i32) -> Block {
	cx := x / i32(CHUNK_SIZE)
	cz := z / i32(CHUNK_SIZE)
	lx := x % i32(CHUNK_SIZE)
	lz := z % i32(CHUNK_SIZE)
	if lx < 0 {lx += i32(CHUNK_SIZE)}
	if lz < 0 {lz += i32(CHUNK_SIZE)}
	if y < 0 || y >= i32(CHUNK_HEIGHT) {
		return BLOCK_AIR
	}
	key := chunk_key(cx, cz)
	c, ok := &w.chunks[key]
	if !ok {
		return BLOCK_AIR
	}
	return get_block(c, int(lx), int(y), int(lz))
}

world_set_block_at :: proc(w: ^World, x: i32, y: i32, z: i32, block: Block) {
	cx := x / i32(CHUNK_SIZE)
	cz := z / i32(CHUNK_SIZE)
	lx := x % i32(CHUNK_SIZE)
	lz := z % i32(CHUNK_SIZE)
	if lx < 0 {lx += i32(CHUNK_SIZE)}
	if lz < 0 {lz += i32(CHUNK_SIZE)}
	if y < 0 || y >= i32(CHUNK_HEIGHT) {
		return
	}
	c := world_get_chunk(w, cx, cz)
	set_block(c, int(lx), int(y), int(lz), block)
}

@(private)
chunk_key :: proc(x: i32, z: i32) -> u64 {
	return (u64(u32(x))) | (u64(u32(z)) << 32)
}

// build_chunk_packet_data serialises a chunk into the byte payload
// required by the ChunkData clientbound packet (1.8 format).
// Returns the payload, a bitmask of included sections, and an allocator error.
// The caller is responsible for freeing the returned slice.
build_chunk_packet_data :: proc(
	allocator: mem.Allocator,
	chunk: ^Chunk,
) -> (
	[]u8,
	u16,
	mem.Allocator_Error,
) {
	num_sections := CHUNK_HEIGHT / 16
	buf: [dynamic]u8
	buf.allocator = allocator
	defer delete(buf)

	block_id_buf: [4096 * 2]u8
	bitmask: u16 = 0

	for section_y in 0 ..< num_sections {
		has_blocks := false
		block_count: u16 = 0

		for x in 0 ..< CHUNK_SIZE {
			for z in 0 ..< CHUNK_SIZE {
				for y in 0 ..< 16 {
					b := get_block(chunk, x, section_y * 16 + y, z)
					if b.id != 0 {
						block_count += 1
						if !has_blocks {
							has_blocks = true
						}
					}
				}
			}
		}

		if !has_blocks {
			continue
		}

		bitmask |= 1 << u16(section_y)

		// Block count (short, big-endian)
		append(&buf, u8(block_count >> 8))
		append(&buf, u8(block_count & 0xFF))

		// Block data: 4096 unsigned shorts, little-endian, packed (id<<4)|data
		idx := 0
		for x in 0 ..< CHUNK_SIZE {
			for z in 0 ..< CHUNK_SIZE {
				for y in 0 ..< 16 {
					b := get_block(chunk, x, section_y * 16 + y, z)
					packed := u16(b.id) << 4 | u16(b.metadata & 0x0F)
					endian.unchecked_put_u16le(block_id_buf[idx:], packed)
					idx += 2
				}
			}
		}
		append(&buf, ..block_id_buf[:])

		// Block light (full bright, 4 bits per block = 2048 bytes)
		for _ in 0 ..< 2048 {
			append(&buf, 0xFF)
		}

		// Sky light (full bright, 4 bits per block = 2048 bytes)
		for _ in 0 ..< 2048 {
			append(&buf, 0xFF)
		}
	}

	// Biomes: 256 bytes per chunk (1 per column) — only when ground_up_continuous=true.
	for _ in 0 ..< 256 {
		append(&buf, 1) // plains
	}

	out := make([]u8, len(buf), allocator)
	copy(out, buf[:])
	return out, bitmask, nil
}
