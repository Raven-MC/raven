package protocol

import "core:fmt"
import "core:mem"
import "core:net"
import "core:thread"
import "core:time"

import "../network"
import "../player"
import "../world"

DEFAULT_ONLINE_MODE :: false

// Client_Task is the data passed to the thread pool for a single client.
Client_Task :: struct {
	client:    network.Tcp_Client,
	allocator: mem.Allocator,
}

client_task_proc :: proc(task: thread.Task) {
	t := (^Client_Task)(task.data)
	handle_client(&t.client, t.allocator)
}

Position_Sync_Interval_Ns :: i64(500_000_000)  // 0.5 s
Position_Sync_Rate       :: 4                  // 4 * 0.5s = 2 s
Keep_Alive_Period_Ns     :: i64(15_000_000_000)
Client_Timeout_Ns        :: i64(30_000_000_000)

Client_State :: struct {
	rsa_priv:    Rsa,
	verify_token: [4]u8,
	username:    string,
}

json_status_response :: `{
  "version": {
    "name": "1.8.9",
    "protocol": 47
  },
  "players": {
    "max": 100,
    "online": 0,
    "sample": []
  },
  "description": {
    "text": "Arclight Odin Server"
  }
}`

handle_client :: proc(client: ^network.Tcp_Client, parent_allocator: mem.Allocator) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)

	cmd_state: Command_State = {}
	cmd_mgr := command_manager_init(allocator, &cmd_state)

	client_state: Client_State
	current_state: State = .Handshaking
	game_world: world.World
	has_world: bool
	current_player: player.Player

	keep_alive_timer: time.Stopwatch
	last_keep_alive_id: i32 = 0
	last_packet_time: i64 = 0
	have_timer := false

	defer {
		if has_world {
			world.world_destroy(&game_world)
		}
		network.tcp_client_close(client)
	}

	for {
		packet := read_packet(client, allocator) or_break // NOTE: any read error (incl. Would_Block) disconnects
		defer delete(packet.body.data, allocator)

		switch current_state {
		case .Handshaking:
			switch packet.id {
			case 0x00:
				handshake, err := read_handshake(&packet.body)
				if err != nil {
					fmt.eprintfln("handshake read error: %v", err)
					break
				}
				fmt.printfln("Handshake: protocol_version=%d, server_address=%s, server_port=%d, next_state=%d",
					handshake.protocol_version, handshake.server_address,
					handshake.server_port, handshake.next_state)
				switch handshake.next_state {
				case 1: current_state = .Status
				case 2: current_state = .Login
				case: fmt.eprintfln("Unknown next state: %d", handshake.next_state)
				}
			case 0xFE:
				fmt.println("TODO: Legacy Server List Ping received, not implemented yet.")
				return
			case:
				fmt.eprintfln("Unknown packet ID 0x%x in Handshaking state.", packet.id)
				return
			}
		case .Status:
			switch packet.id {
			case 0x00:
				fmt.println("Status Request received.")
				{
					body_buf: Buffer_Writer
					buffer_writer_init(&body_buf, allocator)
					write_status_response(&body_buf, Status_Response{json_response = json_status_response})
					send_framed(client, body_buf.buf[:])
					buffer_writer_destroy(&body_buf)
				}
				fmt.println("Sent Status Response.")
			case 0x01:
				ping, err := read_varint(&packet.body)
				if err != nil {
					fmt.eprintfln("ping read error: %v", err)
					break
				}
				fmt.printfln("Ping received with payload: %d", ping)
				{
					body_buf: Buffer_Writer
					buffer_writer_init(&body_buf, allocator)
					write_pong(&body_buf, Pong{payload = i64(ping)})
					send_framed(client, body_buf.buf[:])
					buffer_writer_destroy(&body_buf)
				}
				fmt.println("Sent Pong response.")
				return
			case:
				fmt.eprintfln("Unknown packet ID 0x%x in Status state.", packet.id)
				return
			}
		case .Login:
			switch packet.id {
			case 0x00:
				name, err := read_string(&packet.body)
				if err != nil {
					fmt.eprintfln("login start read error: %v", err)
					break
				}
				fmt.printfln("Login Start: name=%s", name)
				client_state.username = name

				if DEFAULT_ONLINE_MODE {
					fmt.println("Online mode is not fully implemented in Odin - falling back to offline")
				}

				{
					body_buf: Buffer_Writer
					buffer_writer_init(&body_buf, allocator)
					write_login_success(&body_buf, Login_Success{
						uuid     = "4566e69f-c907-48ee-8d71-d7ba5aa200d0",
						username = name,
					})
					send_framed(client, body_buf.buf[:])
					buffer_writer_destroy(&body_buf)
				}
				current_state = .Play
				complete_login(client, allocator, &game_world, &has_world, &current_player, name)
				time.stopwatch_start(&keep_alive_timer)
				have_timer = true
			case:
				fmt.eprintfln("Unknown packet ID 0x%x in Login state.", packet.id)
				return
			}
		case .Play:
			switch packet.id {
			case KEEP_ALIVE:
				ka, err := read_varint(&packet.body)
				if err == nil {
					fmt.printfln("KeepAlive received: %d", ka)
					if ka != last_keep_alive_id {
						fmt.printfln("Incorrect Keep Alive ID. Expected %d, got %d", last_keep_alive_id, ka)
					}
				}
			case CHAT_MESSAGE:
				msg, err := read_string(&packet.body)
				if err != nil {
					fmt.eprintfln("chat read error: %v", err)
					break
				}
				fmt.printfln("Chat from %s: %s", current_player.name, msg)
				if len(msg) > 0 && msg[0] == '/' {
					body_buf: Buffer_Writer
					buffer_writer_init(&body_buf, allocator)
					defer buffer_writer_destroy(&body_buf)
					cmd_err := execute(&cmd_mgr, msg[1:], current_player.name, &body_buf)
					if cmd_err != nil {
						fmt.eprintfln("command error: %v", cmd_err)
					} else {
						send_framed(client, body_buf.buf[:])
					}
				} else {
					json := fmt.aprintf(`{"text":"<%s> %s"}`, current_player.name, msg, allocator=allocator)
					echo_body: Buffer_Writer
					buffer_writer_init(&echo_body, allocator)
					write_chat_message(&echo_body, Chat_Message_CB{
						json_data = json,
						position  = 0,
					})
					delete(json, allocator)
					send_framed(client, echo_body.buf[:])
					buffer_writer_destroy(&echo_body)
				}
			case PLAYER:
				if on_ground, err := read_boolean(&packet.body); err == nil {
					current_player.on_ground = on_ground
				}
			case PLAYER_POSITION:
				pos, err := read_player_position(&packet.body)
				if err == nil {
					prev_x := current_player.x
					prev_y := current_player.y
					prev_z := current_player.z
					current_player.x = pos.x
					current_player.y = pos.feet_y
					current_player.z = pos.z
					current_player.on_ground = pos.on_ground
					current_player.velocity_x = pos.x - prev_x
					current_player.velocity_y = pos.feet_y - prev_y
					current_player.velocity_z = pos.z - prev_z
				}
			case PLAYER_LOOK:
				lk, err := read_player_look(&packet.body)
				if err == nil {
					current_player.yaw = lk.yaw
					current_player.pitch = lk.pitch
					current_player.on_ground = lk.on_ground
				}
			case PLAYER_POSITION_AND_LOOK:
				pal, err := read_player_position_and_look(&packet.body)
				if err == nil {
					prev_x := current_player.x
					prev_y := current_player.y
					prev_z := current_player.z
					current_player.x = pal.x
					current_player.y = pal.feet_y
					current_player.z = pal.z
					current_player.yaw = pal.yaw
					current_player.pitch = pal.pitch
					current_player.on_ground = pal.on_ground
					current_player.velocity_x = pal.x - prev_x
					current_player.velocity_y = pal.feet_y - prev_y
					current_player.velocity_z = pal.z - prev_z
				}
			case:
				fmt.eprintfln("Unhandled Play packet ID: 0x%x", packet.id)
			}
		}

		// Tick-rate work
		if current_state == .Play && have_timer && has_world {
			elapsed := time.stopwatch_duration(keep_alive_timer)
			now := i64(elapsed)

			if elapsed >= time.Duration(Keep_Alive_Period_Ns) {
				last_keep_alive_id += 1
				body_buf: Buffer_Writer
				buffer_writer_init(&body_buf, allocator)
				write_keep_alive(&body_buf, Keep_Alive{keep_alive_id = last_keep_alive_id})
				send_framed(client, body_buf.buf[:])
				buffer_writer_destroy(&body_buf)
				time.stopwatch_reset(&keep_alive_timer)
				time.stopwatch_start(&keep_alive_timer)
			}

			if last_packet_time != 0 && now - last_packet_time > Client_Timeout_Ns {
				fmt.println("Client timed out.")
				return
			}
			last_packet_time = now

			player.update_physics(&current_player, &game_world, 0.05)
			tick := u64(time.stopwatch_duration(keep_alive_timer)) / u64(Position_Sync_Interval_Ns)
			if tick % u64(Position_Sync_Rate) == 0 {
				body_buf: Buffer_Writer
				buffer_writer_init(&body_buf, allocator)
				write_player_position_and_look(&body_buf, Player_Position_And_Look_CB {
					x     = current_player.x,
					y     = current_player.y,
					z     = current_player.z,
					yaw   = current_player.yaw,
					pitch = current_player.pitch,
					flags = 0,
				})
				send_framed(client, body_buf.buf[:])
				buffer_writer_destroy(&body_buf)
			}
		}
	}
}

// --- helpers -------------------------------------------------------------

Packet_Frame :: struct {
	id:   i32,
	body: Buffer_Reader,
}

read_packet :: proc(client: ^network.Tcp_Client, allocator: mem.Allocator) -> (Packet_Frame, mem.Allocator_Error) {
	r := network.tcp_client_reader(client)
	packet_len, err := read_varint_streaming(&r)
	if err != nil {
		return {}, .Out_Of_Memory // NOTE: all errors mapped to Out_Of_Memory
	}
	if packet_len <= 0 {
		return {}, .Out_Of_Memory
	}
	packet_buf := make([]u8, int(packet_len), allocator)
	_, read_err := network.read_bytes(&r, packet_buf)
	if read_err != nil {
		delete(packet_buf, allocator)
		return {}, .Out_Of_Memory
	}
	packet_reader: Buffer_Reader
	buffer_reader_init(&packet_reader, packet_buf)
	id, err2 := read_varint(&packet_reader)
	if err2 != nil {
		delete(packet_buf, allocator)
		return {}, .Out_Of_Memory
	}
	// Replace the body slice with the buffer that we own.
	frame := Packet_Frame {
		id   = id,
		body = packet_reader,
	}
	// Body is still pointing at the same buffer (no copy).  We just
	// have to remember to keep `packet_buf` alive.  Re-attach to frame.
	frame.body.data = packet_buf
	frame.body.pos  = packet_reader.pos
	return frame, nil
}

read_varint_streaming :: proc(r: ^network.Packet_Reader) -> (i32, net.TCP_Recv_Error) {
	value: i32 = 0
	bytes_read: u8 = 0
	for {
		b, err := network.read_byte(r)
		if err != nil {
			if err == .Connection_Closed && bytes_read > 0 {
				return 0, .Connection_Closed
			}
			return 0, err
		}
		value |= i32(b & 0x7F) << u32(bytes_read * 7)
		bytes_read += 1
		if bytes_read > 5 {
			return 0, .Invalid_Argument
		}
		if (b & 0x80) == 0 {
			break
		}
	}
	return value, nil
}

send_packet :: proc(client: ^network.Tcp_Client, allocator: mem.Allocator, _payload: string, write_body: proc(w: ^Buffer_Writer)) { // NOTE: payload unused, kept for signature
	body_buf: Buffer_Writer
	buffer_writer_init(&body_buf, allocator)
	write_body(&body_buf)
	send_framed(client, body_buf.buf[:])
	buffer_writer_destroy(&body_buf)
}

send_framed :: proc(client: ^network.Tcp_Client, body: []u8) {
	prefix: [5]u8
	prefix_len := write_varint_bytes(body, prefix[:])
	w := network.tcp_client_writer(client)
	if err := network.write_bytes(&w, prefix[:prefix_len]); err != nil {
		fmt.eprintfln("send_framed: write prefix failed: %v", err)
		return
	}
	if err := network.write_bytes(&w, body); err != nil {
		fmt.eprintfln("send_framed: write body failed: %v", err)
		return
	}
	if err := network.flush(&w); err != nil {
		fmt.eprintfln("send_framed: flush failed: %v", err)
	}
}

write_varint_bytes :: proc(value: []u8, dst: []u8) -> int {
	length := len(value)
	v := u32(length)
	i := 0
	for {
		if (v & ~u32(0x7F)) == 0 {
			dst[i] = u8(v)
			i += 1
			return i
		}
		dst[i] = u8((v & 0x7F) | 0x80)
		i += 1
		v >>= 7
	}
}

complete_login :: proc(
	client: ^network.Tcp_Client,
	allocator: mem.Allocator,
	game_world: ^world.World,
	has_world: ^bool,
	current_player: ^player.Player,
	username: string,
) {
	game_world^ = world.world_init(allocator, 12345)
	has_world^ = true
	current_player^ = player.player_init(1, username)
	current_player.is_flying = true

	ground_y := player.get_ground_height(&current_player^, game_world)
	current_player.y = ground_y + player.PLAYER_HEIGHT

	body_buf: Buffer_Writer
	buffer_writer_init(&body_buf, allocator)
	write_join_game(&body_buf, Join_Game {
		entity_id          = 1,
		gamemode           = 1, // Creative
		dimension          = 0, // Overworld
		difficulty         = 0, // Peaceful
		max_players        = 100,
		level_type         = "default",
		reduced_debug_info = false,
	})
	send_framed(client, body_buf.buf[:])
	buffer_writer_destroy(&body_buf)

	// Send chunks in a 5x5 area around origin.
	for i in -2..=2 {
		for j in -2..=2 {
			chunk := world.world_get_chunk(game_world, i32(i), i32(j))
			chunk_data, bitmask, _ := world.build_chunk_packet_data(allocator, chunk)
			body_buf2: Buffer_Writer
			buffer_writer_init(&body_buf2, allocator)
			write_chunk_data(&body_buf2, Chunk_Data {
				chunk_x              = i32(i),
				chunk_z              = i32(j),
				ground_up_continuous = true,
				primary_bit_mask     = bitmask,
				data                 = chunk_data,
			})
			send_framed(client, body_buf2.buf[:])
			buffer_writer_destroy(&body_buf2)
			delete(chunk_data, allocator)
		}
	}

	body_buf3: Buffer_Writer
	buffer_writer_init(&body_buf3, allocator)
	write_player_position_and_look(&body_buf3, Player_Position_And_Look_CB {
		x     = current_player.x,
		y     = current_player.y,
		z     = current_player.z,
		yaw   = 0.0,
		pitch = 0.0,
		flags = 0,
	})
	send_framed(client, body_buf3.buf[:])
	buffer_writer_destroy(&body_buf3)

	w := network.tcp_client_writer(client)
	network.flush(&w)
}
