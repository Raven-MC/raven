package event_loop

import "core:fmt"
import "core:mem"
import "core:net"
import "core:sync/chan"
import "core:thread"
import "core:time"

import "../config"
import "../network"
import "../protocol"
import "../world"

TICK_DURATION_NS :: i64(50_000_000) // 50ms = 20 TPS
ACTION_CHAN_CAP :: 256

// Main handler struct. Listens on TCP, creates Game_State, runs the tick
// thread and thread pool. Init -> Run -> Destroy is the lifecycle.
Event_Loop :: struct {
	allocator:   mem.Allocator,
	server:      network.Tcp_Server,
	thread_pool: thread.Pool,
	cfg:         config.Config,
	game_state:  ^protocol.Game_State,
	action_chan: chan.Chan(protocol.Action),
}

// Creates the TCP listener, action channel, shared Game_State, and thread pool.
// Call destroy to free everything.
init :: proc(allocator: mem.Allocator, cfg: config.Config) -> (Event_Loop, net.Network_Error) {
	server, err := network.tcp_server_init(allocator, cfg.server.address, cfg.server.port)
	if err != nil {
		return {}, err
	}

	// Create action channel for client handlers -> tick loop communication
	action_chan, e1 := chan.create(chan.Chan(protocol.Action), ACTION_CHAN_CAP, allocator)
	if e1 != nil {
		fmt.eprintfln("failed to create action channel: %v", e1)
		network.tcp_server_destroy(&server)
		return {}, nil
	}

	// Create shared game state (owned by tick loop)
	game_state_raw, e2 := mem.alloc(
		size_of(protocol.Game_State),
		align_of(protocol.Game_State),
		allocator,
	)
	if e2 != nil {
		fmt.eprintfln("failed to allocate game state: %v", e2)
		chan.destroy(&action_chan)
		network.tcp_server_destroy(&server)
		return {}, nil
	}
	game_state_ptr := (^protocol.Game_State)(game_state_raw)
	game_state_ptr^ = protocol.Game_State {
		allocator    = allocator,
		game_time    = 0,
		players      = make([dynamic]protocol.Player_Info, allocator),
		has_world    = false,
		player_count = 0,
	}

	el := Event_Loop {
		allocator   = allocator,
		server      = server,
		thread_pool = thread.Pool{},
		cfg         = cfg,
		game_state  = game_state_ptr,
		action_chan = action_chan,
	}

	thread.pool_init(&el.thread_pool, allocator, max(1, cfg.thread_pool.max_threads))
	thread.pool_start(&el.thread_pool)
	return el, nil
}

// Shuts down the server: closes the action channel (signals tick loop to stop),
// joins the thread pool, frees game state, and closes the listener.
destroy :: proc(el: ^Event_Loop) {
	// Close action channel to signal tick loop to stop
	chan.close(&el.action_chan)
	thread.pool_join(&el.thread_pool)
	thread.pool_destroy(&el.thread_pool)
	network.tcp_server_destroy(&el.server)

	// Free game state
	if el.game_state != nil {
		if el.game_state^.has_world {
			world.world_destroy(&el.game_state^.world)
		}
		mem.free(el.game_state, el.allocator)
	}
	chan.destroy(&el.action_chan)
}

// Starts the tick loop thread (20 TPS), then enters the accept loop: accepts new
// connections and dispatches each to the thread pool. This call blocks forever
// (or until a fatal accept error).
run :: proc(el: ^Event_Loop) -> net.Accept_Error {
	// Start the tick loop thread (owns Game_State)
	tick_task_data, task_alloc_err := mem.alloc(
		size_of(protocol.Tick_Task),
		align_of(protocol.Tick_Task),
		el.allocator,
	)
	if task_alloc_err != nil {
		fmt.eprintfln("tick task allocation failed: %v", task_alloc_err)
		return .Insufficient_Resources
	}
	tick_task_ptr := (^protocol.Tick_Task)(tick_task_data)
	tick_task_ptr^ = protocol.Tick_Task {
		game_state = el.game_state,
		actions    = &el.action_chan,
	}
	thread.create_and_start_with_data(
		tick_task_ptr,
		protocol.tick_loop_proc,
		nil,
		thread.Thread_Priority.Normal,
		true,
	)

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

		task_raw, alloc_err := mem.alloc(
			size_of(protocol.Client_Task),
			align_of(protocol.Client_Task),
			el.allocator,
		)
		if alloc_err != nil {
			fmt.eprintfln("task allocation failed: %v", alloc_err)
			continue
		}
		task_ptr_cast := (^protocol.Client_Task)(task_raw)
		task_ptr_cast^ = protocol.Client_Task {
			client      = client,
			allocator   = el.allocator,
			action_chan = &el.action_chan,
			game_state  = el.game_state,
		}
		thread.pool_add_task(
			&el.thread_pool,
			el.allocator,
			protocol.client_task_proc,
			task_ptr_cast,
		)
	}
}
