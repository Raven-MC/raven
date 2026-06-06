package protocol

import "core:crypto/aes"
import "core:crypto/legacy/sha1"
import "core:encoding/hex"
import "core:fmt"
import "core:mem"
import "core:math/rand"
import "core:strings"
import "../network"

AES_BLOCK_SIZE :: 16
RSA_KEY_SIZE  :: 128
RSA_EXPONENT  :: u32(65537)

@(private)
twos_complement :: proc(bytes: ^[20]u8) {
	carry := true
	// Walk from low to high.
	for i in 0..<len(bytes) {
		j := len(bytes) - 1 - i
		bytes[j] = ~bytes[j]
		if carry {
			carry = bytes[j] == 0xff
			bytes[j] += 1
		}
	}
}

// get_sha1_digest returns the hex digest of SHA1(server_id || shared_secret || public_key)
// as the two's-complement-encoded hex string used by Mojang.
get_sha1_digest :: proc(allocator: mem.Allocator, server_id: string, shared_secret: []u8, public_key: []u8) -> (string, mem.Allocator_Error) {
	ctx: sha1.Context
	sha1.init(&ctx)
	sha1.update(&ctx, transmute([]u8)server_id)
	sha1.update(&ctx, shared_secret)
	sha1.update(&ctx, public_key)

	digest: [20]u8
	sha1.final(&ctx, digest[:])

	need_leading_dash := (digest[0] & 0x80) != 0
	if need_leading_dash {
		twos_complement(&digest)
	}

	enc, err := hex.encode(digest[:], allocator)
	if err != nil {
		return "", err
	}

	// Trim leading zeros.
	idx := 0
	for idx < len(enc) - 1 && enc[idx] == '0' {
		idx += 1
	}

	if need_leading_dash {
		return fmt.aprintf("-%s", enc[idx:], allocator=allocator), nil
	}
	return strings.clone(string(enc[idx:]), allocator), nil
}

// --- TODO: RSA stub (Odin stdlib has no RSA, random keypair) ---

Rsa_Keypair :: struct {
	n: [RSA_KEY_SIZE]u8,
	e: u32,
	d: [RSA_KEY_SIZE]u8,
	p: [RSA_KEY_SIZE / 2]u8,
	q: [RSA_KEY_SIZE / 2]u8,
}

Rsa :: struct {
	keypair: Rsa_Keypair,
}

rsa_generate :: proc() -> Rsa {
	return Rsa {
		keypair = Rsa_Keypair {
			n = random_bytes([RSA_KEY_SIZE]u8),
			e = RSA_EXPONENT,
			d = random_bytes([RSA_KEY_SIZE]u8),
			p = random_bytes([RSA_KEY_SIZE / 2]u8),
			q = random_bytes([RSA_KEY_SIZE / 2]u8),
		},
	}
}

@(private)
random_bytes :: proc($T: typeid) -> T {
	out: T
	when size_of(T) == 0 {
		return out
	} else {
		bytes_out: []u8 = out[:]
		for i in 0..<len(bytes_out) {
			bytes_out[i] = u8(rand.uint32() & 0xff)
		}
	}
	return out
}

// public_key_der returns an X.509 SubjectPublicKeyInfo DER encoding.
// The body is well-formed DER, but the modulus is random garbage.
public_key_der :: proc(rsa: ^Rsa, allocator: mem.Allocator) -> ([]u8, mem.Allocator_Error) {
	header_len :: 19
	mod_len    :: RSA_KEY_SIZE
	total_len  := header_len + mod_len + 3

	buf: [dynamic]u8
	buf.allocator = allocator
	defer delete(buf)

	append(&buf, 0x30, 0x82)
	append(&buf, u8((total_len >> 8) & 0xff), u8(total_len & 0xff))

	append(&buf, 0x30, 0x0D, 0x06, 0x09)
	append(&buf, ..[]u8{0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01})
	append(&buf, 0x05, 0x00)

	pubkey_len := mod_len + 3 + 11
	append(&buf, 0x03)
	if pubkey_len > 128 {
		append(&buf, 0x82)
	} else {
		append(&buf, 0x01)
	}
	append(&buf, u8((pubkey_len >> 8) & 0xff), u8(pubkey_len & 0xff))
	append(&buf, 0x00)

	append(&buf, 0x02, 0x81, u8(mod_len))
	append(&buf, ..rsa.keypair.n[:])

	return slice_clone(buf[:], allocator), nil
}

rsa_decrypt :: proc(_: ^Rsa, output: []u8, input: []u8) {
	// TODO: no-op stub.  Real RSA would PKCS#1-v1.5 unpad.
	if len(input) > len(output) {
		copy(output, input[:len(output)])
	} else {
		copy(output, input)
	}
}

rsa_verify_token :: proc(token: []u8, expected: []u8) -> bool {
	if len(token) != len(expected) {
		return false
	}
	for i in 0..<len(token) {
		if token[i] != expected[i] {
			return false
		}
	}
	return true
}

@(private)
slice_clone :: proc(src: []u8, allocator: mem.Allocator) -> []u8 {
	out := make([]u8, len(src), allocator)
	copy(out, src)
	return out
}

// --- AES-CFB8 (untested -- online mode disabled by default) ---

@(private)
build_key_iv :: proc(shared_secret: []u8) -> (key, iv: [16]u8) {
	n := min(16, len(shared_secret))
	copy(key[:n], shared_secret[:n])
	copy(iv[:n], shared_secret[:n])
	if len(shared_secret) < 16 {
		for i in len(shared_secret)..<16 {
			key[i] = u8(i)
			iv[i]  = u8(i)
		}
	}
	return
}

enable_encryption :: proc(state: ^network.Cipher_State, shared_secret: []u8) {
	key, iv := build_key_iv(shared_secret)
	aes.init_ecb(&state.aes_ctx, key[:])
	state.encrypt_feedback = iv
	state.decrypt_feedback = iv
}

@(private)
encrypt_cfb8 :: proc(state: ^network.Cipher_State, plaintext: u8) -> u8 {
	encrypted_block: [16]u8
	aes.encrypt_ecb(&state.aes_ctx, encrypted_block[:], state.encrypt_feedback[:])
	cipher_byte := plaintext ~ encrypted_block[0]
	state.encrypt_feedback[0] = cipher_byte
	return cipher_byte
}

decrypt_cfb8 :: proc(state: ^network.Cipher_State, ciphertext: u8) -> u8 {
	encrypted_block: [16]u8
	aes.encrypt_ecb(&state.aes_ctx, encrypted_block[:], state.decrypt_feedback[:])
	plaintext := ciphertext ~ encrypted_block[0]
	state.decrypt_feedback[0] = ciphertext
	return plaintext
}

encrypt_bytes :: proc(state: ^network.Cipher_State, src: []u8) -> []u8 {
	out := make([]u8, len(src))
	for i, b in src {
		out[i] = encrypt_cfb8(state, u8(b))
	}
	return out
}

decrypt_bytes :: proc(state: ^network.Cipher_State, src: []u8) -> []u8 {
	out := make([]u8, len(src))
	for i, b in src {
		out[i] = decrypt_cfb8(state, u8(b))
	}
	return out
}
