package protocol

import "core:fmt"
import "core:mem"
import "core:sync/chan"
import "core:time"

import "../player"
import "../world"

// State tracks which protocol phase a client is in.
State :: enum {
	Handshaking,
	Status,
	Login,
	Play,
}

// Handshaking-state serverbound packets.
Handshake :: struct {
	protocol_version: i32,
	server_address:   string,
	server_port:      u16,
	next_state:       i32,
}

read_handshake :: proc(r: ^Buffer_Reader) -> (Handshake, Protocol_Recv_Error) {
	protocol_version, err1 := read_varint(r)
	if err1 != nil {
		return {}, err1
	}
	server_address, err2 := read_string(r)
	if err2 != nil {
		return {}, err2
	}
	server_port, err3 := read_ushort(r)
	if err3 != nil {
		return {}, err3
	}
	next_state, err4 := read_varint(r)
	if err4 != nil {
		return {}, err4
	}
	return Handshake {
			protocol_version = protocol_version,
			server_address = server_address,
			server_port = server_port,
			next_state = next_state,
		},
		nil
}

// LegacyServerListPing (0xFE) is a single-byte request.
LegacyServerListPing :: struct {
	payload: u8,
}

read_legacy_ping :: proc(r: ^Buffer_Reader) -> (LegacyServerListPing, Protocol_Recv_Error) {
	b, err := read_ubyte(r)
	return LegacyServerListPing{payload = b}, err
}

// Game_State: shared world state owned by tick loop
Game_State :: struct {
	allocator:    mem.Allocator,
	world:        world.World,
	game_time:    i64,
	players:      [dynamic]Player_Info,
	has_world:    bool,
	player_count: int,
}

// Player_Info holds per-player state in the shared game state
Player_Info :: struct {
	entity_id:    i32,
	username:     string,
	player_state: player.Player,
	send_channel: chan.Chan(Server_Message),
}

// Server_Message: messages from tick loop to client handlers
Server_Message_Type :: enum {
	Game_Time_Update,
	Chat_Message,
	Player_Join,
	Player_Leave,
	Player_Position_And_Look,
}

Server_Message :: struct {
	type:    Server_Message_Type,
	payload: union {
		Game_Time_Update,
		Chat_Message,
		Player_Join,
		Player_Leave,
		Player_Position_And_Look_CB,
	},
}

Game_Time_Update :: struct {
	game_time: i64,
}

Chat_Message :: struct {
	json_data: string,
	position:  i8,
}

Player_Join :: struct {
	entity_id: i32,
	username:  string,
}

Player_Leave :: struct {
	entity_id: i32,
}

// Action: messages from client handlers to tick loop
Action_Type :: enum {
	PlayerJoin,
	PlayerLeave,
	ChatMessage,
}

Action :: struct {
	type:    Action_Type,
	payload: union {
		Player_Join_Action,
		Player_Leave_Action,
		Chat_Message_Action,
	},
}

Player_Join_Action :: struct {
	username:      string,
	reply_channel: ^chan.Chan(Server_Message),
}

Player_Leave_Action :: struct {
	entity_id: i32,
}

Chat_Message_Action :: struct {
	sender:  string,
	message: string,
}

// Tick_Task: data passed to tick loop thread
Tick_Task :: struct {
	game_state: ^Game_State,
	actions:    ^chan.Chan(Action),
}

// Tick loop procedure (entry point for tick thread)
tick_loop_proc :: proc(data: rawptr) {
	t := (^Tick_Task)(data)
	tick_loop(t.game_state, t.actions)
}

// Tick loop - runs at 20 TPS, processes actions and updates game state
tick_loop :: proc(game_state: ^Game_State, actions: ^chan.Chan(Action)) {
	game_state.world = world.world_init(game_state.allocator, WORLD_SEED)
	game_state.has_world = true
	game_state.game_time = 0

	tick_duration := time.Duration(50_000_000) // 50ms

	for {
		// Drain all pending actions (non-blocking)
		for {
			action, ok := chan.try_recv(actions^)
			if !ok {break}
			process_action(game_state, action)
		}

		// World tick
		world.world_tick(&game_state.world)

		// Increment game time and broadcast to all players
		game_state.game_time += 1
		broadcast_time_update(game_state)

		// Sleep until next tick
		time.sleep(tick_duration)
	}
}

process_action :: proc(game_state: ^Game_State, action: Action) {
	if action.type == .PlayerJoin {
		join, ok := action.payload.(Player_Join_Action)
		if !ok {return}

		eid := i32(game_state.player_count + 1)
		info := Player_Info {
			entity_id    = eid,
			username     = join.username,
			player_state = player.player_init(eid, join.username),
			send_channel = join.reply_channel^,
		}

		append(&game_state.players, info)
		game_state.player_count += 1

		fmt.printfln(
			"Player joined: %s (eid=%d, total=%d)",
			join.username,
			eid,
			game_state.player_count,
		)

	} else if action.type == .PlayerLeave {
		leave, ok := action.payload.(Player_Leave_Action)
		if !ok {return}
		_ = leave

		// Remove last player (simple approach for single-player)
		if len(game_state.players) > 0 {
			last := &game_state.players[len(game_state.players) - 1]
			chan.destroy(&last.send_channel)
			pop(&game_state.players)
			game_state.player_count -= 1
		}

		fmt.printfln("Player left (total=%d)", game_state.player_count)

	} else if action.type == .ChatMessage {
		chat, ok := action.payload.(Chat_Message_Action)
		if !ok {return}
		broadcast_chat(game_state, chat.sender, chat.message)
	}
}

broadcast_time_update :: proc(game_state: ^Game_State) {
	msg := Server_Message {
		type = .Game_Time_Update,
		payload = Game_Time_Update{game_time = game_state.game_time},
	}
	for i in 0 ..< len(game_state.players) {
		player := &game_state.players[i]
		_ = chan.try_send(player.send_channel, msg)
	}
}

broadcast_chat :: proc(game_state: ^Game_State, sender: string, message: string) {
	json_text := fmt.tprintf(`{"text":"<%s> %s"}`, sender, message)
	msg := Server_Message {
		type = .Chat_Message,
		payload = Chat_Message{json_data = json_text, position = 0},
	}
	for i in 0 ..< len(game_state.players) {
		player := &game_state.players[i]
		_ = chan.try_send(player.send_channel, msg)
	}
}

// Remove and return last element from dynamic array
@(private)
pop :: proc(arr: ^$T/[dynamic]$E) -> E {
	assert(len(arr) > 0)
	val := arr[len(arr) - 1]
	resize(arr, len(arr) - 1)
	return val
}

// World generation seed
WORLD_SEED :: 12345
