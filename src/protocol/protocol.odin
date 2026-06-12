package protocol

import "core:fmt"
import "core:mem"
import "core:sync"
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

// Reads the Handshake packet (0x00). Determines whether the client wants Status or
// Login protocol phase.
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

// Reads the legacy server list ping (0xFE). Currently logged but not responded to.
read_legacy_ping :: proc(r: ^Buffer_Reader) -> (LegacyServerListPing, Protocol_Recv_Error) {
	b, err := read_ubyte(r)
	return LegacyServerListPing{payload = b}, err
}

// Shared world state owned by the tick thread. Client handlers read fields
// (world, player_count) via a read-only pointer; mutations go through Action
// messages on the action channel. broadcast_time_update and broadcast_chat
// send to all players via their per-player reply channels. Player_Info tracks
// each connected player's entity ID, username, player state, and reply channel.
// world_mutex guards has_world and world initialisation (written from handlers
// on first login, read from tick loop every tick).
Game_State :: struct {
	allocator:    mem.Allocator,
	world:        world.World,
	game_time:    i64,
	players:      [dynamic]Player_Info,
	has_world:    bool,
	player_count: int,
	world_mutex:  sync.Mutex,
}

// Per-player entry in Game_State.players. The send_channel receives
// Server_Message values from the tick loop (time updates, chat, position sync).
Player_Info :: struct {
	entity_id:    i32,
	username:     string,
	player_state: player.Player,
	send_channel: chan.Chan(Server_Message),
}

// Tick-loop messages sent to individual client handlers via per-player
// reply channels. The handler's process_server_message writes the corresponding
// clientbound packet. Types: Game_Time_Update, Chat_Message, Player_Join,
// Player_Leave, Player_Position_And_Look.
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

// Client-handler messages sent to the tick loop via the shared action channel.
// The tick loop drains and processes them in process_action. Types: PlayerJoin
// (registers a player in Game_State), PlayerLeave (unregisters), ChatMessage
// (broadcasts to all players), GameTimeChange (modifies game_time).
Action_Type :: enum {
	PlayerJoin,
	PlayerLeave,
	ChatMessage,
	GameTimeChange,
}

Action :: struct {
	type:    Action_Type,
	payload: union {
		Player_Join_Action,
		Player_Leave_Action,
		Chat_Message_Action,
		GameTimeChange_Action,
	},
}

// Payload for Action.PlayerJoin: used by the handler to register a new player.
Player_Join_Action :: struct {
	username:      string,
	reply_channel: ^chan.Chan(Server_Message),
}

// Payload for Action.PlayerLeave: used by the handler to remove a player.
// reply_channel is transferred to the tick loop for destruction, preventing
// a use-after-free when the handler's arena is torn down.
Player_Leave_Action :: struct {
	entity_id:     i32,
	reply_channel: chan.Chan(Server_Message),
}

// Payload for Action.ChatMessage: triggers broadcast_chat in the tick loop.
Chat_Message_Action :: struct {
	sender:  string,
	message: string,
}

// Payload for Action.GameTimeChange: modifies game_time on the tick loop.
// Sent by /time command; avoids a direct write race on Game_State.game_time.
GameTimeChange_Action :: struct {
	operation: Time_Op,
	value:     i64,
}

Time_Op :: enum {
	Set,
	Add,
}

// Data passed to the tick thread on creation. Holds the shared Game_State
// pointer and the action channel that client handlers send Actions into.
Tick_Task :: struct {
	game_state: ^Game_State,
	actions:    ^chan.Chan(Action),
}

// Entry point for the tick thread. Unpacks Tick_Task and calls tick_loop.
tick_loop_proc :: proc(data: rawptr) {
	t := (^Tick_Task)(data)
	tick_loop(t.game_state, t.actions)
}

// Main loop of the tick thread (20 TPS). Drains pending actions from client
// handlers, calls world_tick, broadcasts time updates to all players, then
// sleeps for ~50ms. Owns Game_State - client handlers send mutations via actions.
// Checks actions.impl for closure as a shutdown signal from event_loop.destroy.
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

		// Shutdown check: event_loop.destroy closes the action channel to
		// signal the tick loop to exit before freeing Game_State.
		if chan.is_closed(actions.impl) {
			break
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

// Applies an Action (sent by a client handler via the action channel) to the
// shared Game_State. Handles player join, leave, chat, and time-change actions.
// PlayerLeave destroys the transferred reply_channel now owned by the tick loop.
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

		// Find the player by matching the Raw_Chan pointer of the transferred
		// reply_channel. This avoids relying on stale entity_id values.
		for i in 0 ..< len(game_state.players) {
			if game_state.players[i].send_channel.impl == leave.reply_channel.impl {
				chan.destroy(&game_state.players[i].send_channel)
				ordered_remove(&game_state.players, i)
				game_state.player_count -= 1
				break
			}
		}

		fmt.printfln("Player left (total=%d)", game_state.player_count)

	} else if action.type == .ChatMessage {
		chat, ok := action.payload.(Chat_Message_Action)
		if !ok {return}
		broadcast_chat(game_state, chat.sender, chat.message)

	} else if action.type == .GameTimeChange {
		change, ok := action.payload.(GameTimeChange_Action)
		if !ok {return}
		switch change.operation {
		case .Set:
			game_state.game_time = change.value
		case .Add:
			game_state.game_time += change.value
		}
	}
}

// Sends the current game_time to every connected player via their reply channel.
// Called every tick (20 TPS).
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

// Sends a chat message from `sender` to all connected players. Each player
// receives a JSON-formatted "<sender> message" on their reply channel.
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
