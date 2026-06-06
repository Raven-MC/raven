package event_loop

import "core:fmt"
import "core:mem"
import "core:net"
import "core:thread"
import "core:time"

import "../config"
import "../network"
import "../protocol"

Event_Loop :: struct {
	allocator:   mem.Allocator,
	server:      network.Tcp_Server,
	thread_pool: thread.Pool,
	cfg:         config.Config,
}

init :: proc(allocator: mem.Allocator, cfg: config.Config) -> (Event_Loop, net.Network_Error) {
	server, err := network.tcp_server_init(allocator, cfg.server.address, cfg.server.port)
	if err != nil {
		return {}, err
	}
	el := Event_Loop {
		allocator = allocator,
		server    = server,
		cfg       = cfg,
	}
	thread.pool_init(&el.thread_pool, allocator, max(1, cfg.thread_pool.max_threads))
	thread.pool_start(&el.thread_pool)
	return el, nil
}

destroy :: proc(el: ^Event_Loop) {
	thread.pool_join(&el.thread_pool)
	thread.pool_destroy(&el.thread_pool)
	network.tcp_server_destroy(&el.server)
}

run :: proc(el: ^Event_Loop) -> net.Accept_Error {
	for {
		client, err := network.tcp_server_accept(&el.server)
		if err != nil {
			if err == .Would_Block {
				time.sleep(10 * time.Millisecond)
				continue
			}
			fmt.eprintfln("accept failed: %v", err)
			continue
		}

		task_ptr, alloc_err := mem.alloc(size_of(protocol.Client_Task), align_of(protocol.Client_Task), el.allocator)
		if alloc_err != nil {
			fmt.eprintfln("task allocation failed: %v", alloc_err)
			continue
		}
		task_ptr_cast := (^protocol.Client_Task)(task_ptr)
		task_ptr_cast^ = protocol.Client_Task{
			client    = client,
			allocator = el.allocator,
		}
		thread.pool_add_task(&el.thread_pool, el.allocator, protocol.client_task_proc, task_ptr_cast)
	}
}
