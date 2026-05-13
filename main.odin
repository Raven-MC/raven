package main

import "core:fmt"
import "core:os"
import "core:mem"

import "./src/config"
import "./src/event_loop"

CONFIG_PATH :: "config.ini"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer mem.tracking_allocator_destroy(&track)

	cfg, cfg_err := config.load(context.allocator, CONFIG_PATH)
	if cfg_err != nil {
		fmt.eprintfln("Failed to load config: %v", cfg_err)
		os.exit(1)
	}
	defer config.destroy(cfg, context.allocator)

	el, el_err := event_loop.init(context.allocator, cfg)
	if el_err != nil {
		fmt.eprintfln("Failed to initialise event loop: %v", el_err)
		os.exit(1)
	}
	defer event_loop.destroy(&el)

	fmt.printfln("Server listening on %s:%d", cfg.server.address, cfg.server.port)
	if err := event_loop.run(&el); err != nil {
		fmt.eprintfln("Event loop failed: %v", err)
		os.exit(1)
	}
}
