// TODO: plugin support.  Use `core:dynlib` if/when JNI bridging is needed.
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
