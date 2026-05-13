// Package plugin is a stub.  The original Zig port kept an empty
// `bukkit.zig` cImport'ing `jni.h`; the Odin port preserves the same
// intent (plugin support is a future feature) without pulling in any
// foreign headers.  Use `core:dynlib` later if/when JNI bridging is
// needed.
package plugin

import "base:runtime"

Interface :: struct {
	allocator: runtime.Allocator,
}

interface_init :: proc(allocator: runtime.Allocator) -> Interface {
	return Interface{allocator = allocator}
}

interface_destroy :: proc(iface: ^Interface) {
	_ = iface
}
