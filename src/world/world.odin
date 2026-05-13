package world

import "base:runtime"
import "core:mem"

CHUNK_SIZE   :: 16
CHUNK_HEIGHT :: 128

Block_Id      :: u8
Block_Metadata :: u8

Block :: struct {
	id:       Block_Id,
	metadata: Block_Metadata,
}

BLOCK_AIR   :: Block{}
BLOCK_STONE :: Block{id = 1}
BLOCK_GRASS :: Block{id = 2}
BLOCK_DIRT  :: Block{id = 3}

Chunk :: struct {
	x:       i32,
	z:       i32,
	blocks:  [CHUNK_SIZE][CHUNK_HEIGHT][CHUNK_SIZE]Block,
}

chunk_init :: proc(x: i32, z: i32, seed: u64) -> Chunk {
	chunk := Chunk{x = x, z = z}
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
	for x in 0..<CHUNK_SIZE {
		for z in 0..<CHUNK_SIZE {
			wx := i32(x) + chunk.x * i32(CHUNK_SIZE)
			wz := i32(z) + chunk.z * i32(CHUNK_SIZE)
			height := get_height(wx, wz, seed)
			for y in 0..<CHUNK_HEIGHT {
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
	_ = w
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
	if lx < 0 { lx += i32(CHUNK_SIZE) }
	if lz < 0 { lz += i32(CHUNK_SIZE) }
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
	if lx < 0 { lx += i32(CHUNK_SIZE) }
	if lz < 0 { lz += i32(CHUNK_SIZE) }
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
// required by the ChunkData clientbound packet.  Returns a freshly
// allocated slice that the caller is responsible for freeing.
build_chunk_packet_data :: proc(allocator: mem.Allocator, chunk: ^Chunk) -> ([]u8, mem.Allocator_Error) {
	_ = allocator
	sections_sent: u16 = 0

	// 16 sections * (1 byte block count + 4096 block bytes + 2048 meta + 2048 light)
	// plus 2048 skylight per section.  The Zig port emits 0xff skylight.
	// Estimate a generous initial capacity.
	buf: [dynamic]u8
	buf.allocator = allocator
	defer delete(buf)

	for section_y in 0..<16 {
		has_blocks := false
		for x in 0..<CHUNK_SIZE {
			if has_blocks { break }
			for z in 0..<CHUNK_SIZE {
				if has_blocks { break }
				for y in 0..<16 {
					b := get_block(chunk, x, section_y * 16 + y, z)
					if b.id != 0 {
						has_blocks = true
						break
					}
				}
			}
		}
		if !has_blocks {
			append(&buf, 0)
			continue
		}
		mask := section_bit_mask(section_y)
		sections_sent |= mask

		append(&buf, 0) // block-count byte

		// Block IDs
		for x in 0..<CHUNK_SIZE {
			for z in 0..<CHUNK_SIZE {
				for y in 0..<16 {
					b := get_block(chunk, x, section_y * 16 + y, z)
					append(&buf, b.id)
				}
			}
		}
		// Block metadata
		for x in 0..<CHUNK_SIZE {
			for z in 0..<CHUNK_SIZE {
				for y in 0..<16 {
					b := get_block(chunk, x, section_y * 16 + y, z)
					append(&buf, b.metadata)
				}
			}
		}
		// Block light (full bright)
		for _ in 0..<2048 {
			append(&buf, 0xFF)
		}
	}
	_ = sections_sent

	// Biomes: 256 bytes per chunk (1 per column).
	for _ in 0..<256 {
		append(&buf, 1) // plains
	}

	out := make([]u8, len(buf), allocator)
	copy(out, buf[:])
	return out, nil
}

@(private)
section_bit_mask :: proc(section_y: int) -> u16 {
	mask: u16 = 1 << u16(section_y)
	return mask
}

_ :: runtime.default_context
