const std = @import("std");
const network = @import("../network/network.zig");
const protocol = @import("protocol.zig");
const serverbound = protocol.serverbound;
const clientbound = protocol.clientbound;
const player = @import("../player.zig");
const world = @import("../world/world.zig");
const crypto = @import("../protocol/crypto.zig");
const config = @import("../config.zig");
const commands = @import("./commands.zig");
const http = std.http;
const json = std.json;

/// Position sync interval in nanoseconds (0.5 seconds).
const POSITION_SYNC_INTERVAL_NS = 500_000_000;
/// Number of sync intervals between position updates (4 * 0.5s = 2 seconds).
const POSITION_SYNC_RATE = 4;

const MojangProfile = struct {
    id: []const u8,
    name: []const u8,
};

const ClientState = struct {
    rsa_priv: crypto.Rsa,
    verify_token: [4]u8,
    username: []u8,
};

fn completeLogin(g_client: *network.TcpClient, allocator: std.mem.Allocator, game_world: *?world.World, current_player: *player.Player, username: []const u8) !void {
    game_world.* = try world.World.init(allocator, 12345);
    current_player.* = player.Player.init(1, username);
    current_player.*.is_flying = true;

    const ground_y = current_player.*.getGroundHeight(&game_world.*.?);
    current_player.*.y = ground_y + player.PLAYER_HEIGHT;

    const join_game_packet = clientbound.JoinGame{
        .entity_id = 1,
        .gamemode = 1, // Creative
        .dimension = 0, // Overworld
        .difficulty = 0, // Peaceful
        .max_players = 100,
        .level_type = "default",
        .reduced_debug_info = false,
    };
    try clientbound.JoinGame.write(g_client.getWriter(), join_game_packet, allocator);

    // Send a few chunks
    var i: i32 = -2;
    while (i <= 2) : (i += 1) {
        var j: i32 = -2;
        while (j <= 2) : (j += 1) {
            const chunk_packet = try clientbound.ChunkData.init(allocator, i, j, &game_world.*);
            defer allocator.free(chunk_packet.data);
            try chunk_packet.write(g_client.getWriter(), allocator);
        }
    }

    const pos_look_packet = clientbound.PlayerPositionAndLook{
        .x = current_player.*.x,
        .y = current_player.*.y,
        .z = current_player.*.z,
        .yaw = 0.0,
        .pitch = 0.0,
        .flags = 0,
    };
    try clientbound.PlayerPositionAndLook.write(g_client.getWriter(), pos_look_packet, allocator);
    try g_client.writer_wrapper.flush();
}

fn handlePacket(
    g_client: *network.TcpClient,
    client_state: *ClientState,
    current_state: *protocol.State,
    game_world: *?world.World,
    current_player: *player.Player,
    last_keep_alive_id: *i32,
    keep_alive_timer: *?std.time.Timer,
    cmd_manager: *commands.CommandManager,
    allocator: std.mem.Allocator,
) !void {
    std.debug.print("Received packet\n", .{});

    const writer = g_client.getWriter();

    const reader_ref = g_client.getReader();
    const packet_len_info = protocol.types.readVarInt(reader_ref) catch |err| {
        if (err == error.EndOfStream) {
            std.debug.print("Client disconnected.\n", .{});
            return error.EndOfStream;
        }
        return err;
    };
    const packet_len = packet_len_info.value;

    if (packet_len <= 0) {
        return;
    }

    const packet_buffer = try allocator.alloc(u8, @as(usize, @intCast(packet_len)));
    defer allocator.free(packet_buffer);
    try reader_ref.readNoEof(packet_buffer);

    var buffer_stream = std.io.fixedBufferStream(packet_buffer);
    const buffer_reader = buffer_stream.reader();

    const packet_id_info = try protocol.types.readVarInt(buffer_reader);
    const packet_id = packet_id_info.value;

    switch (current_state.*) {
        .Handshaking => {
            switch (packet_id) {
                0x00 => { // Handshake
                    const handshake_packet = try serverbound.Handshake.read(buffer_reader, allocator);
                    std.debug.print("Handshake: protocol_version={d}, server_address={s}, server_port={d}, next_state={d}\n", .{
                        handshake_packet.protocol_version,
                        handshake_packet.server_address,
                        handshake_packet.server_port,
                        handshake_packet.next_state,
                    });

                    switch (handshake_packet.next_state) {
                        1 => current_state.* = .Status,
                        2 => current_state.* = .Login,
                        else => {
                            std.debug.print("Unknown next state: {d}\n", .{handshake_packet.next_state});
                            return error.InvalidNextState;
                        },
                    }
                },
                0xFE => { // Legacy Server List Ping
                    std.debug.print("Legacy Server List Ping received, not implemented yet.\n", .{});
                    return error.NotImplemented;
                },
                else => {
                    std.debug.print("Unknown packet ID 0x{x} in Handshaking state.\n", .{packet_id});
                    return error.UnknownPacket;
                },
            }
        },
        .Status => {
            switch (packet_id) {
                0x00 => { // Request
                    std.debug.print("Status Request received.\n", .{});
                    const response_json = "{\n  \"version\": {\n    \"name\": \"1.8.9\",\n    \"protocol\": 47\n  },\n  \"players\": {\n    \"max\": 100,\n    \"online\": 0,\n    \"sample\": []\n  },\n  \"description\": {\n    \"text\": \"Arclight Zig Server\"\n  }\n}";
                    const response_packet = clientbound.StatusResponse{ .json_response = response_json };
                    try clientbound.StatusResponse.write(writer, response_packet, allocator);
                    try g_client.writer_wrapper.flush();
                    std.debug.print("Sent Status Response.\n", .{});
                },
                0x01 => { // Ping
                    const ping_packet = try serverbound.Ping.read(buffer_reader);
                    std.debug.print("Ping received with payload: {d}\n", .{ping_packet.payload});
                    const pong_packet = clientbound.Pong{ .payload = ping_packet.payload };
                    try clientbound.Pong.write(writer, pong_packet);
                    try g_client.writer_wrapper.flush();
                    std.debug.print("Sent Pong response.\n", .{});
                    return error.EndOfStream; // Client will disconnect after this
                },
                else => {
                    std.debug.print("Unknown packet ID 0x{x} in Status state.\n", .{packet_id});
                    return error.UnknownPacket;
                },
            }
        },

        .Login => {
            switch (packet_id) {
                0x00 => { // Login Start
                    const login_start_packet = try serverbound.LoginStart.read(buffer_reader, allocator);
                    std.debug.print("Login Start: name={s}\n", .{login_start_packet.name});
                    client_state.username = try allocator.dupe(u8, login_start_packet.name);

                    if (config.default_online_mode) {
                        std.debug.print("Online mode is not fully implemented in Zig 0.15.x - falling back to offline\n", .{});
                    }

                    const login_success_packet = clientbound.LoginSuccess{
                        .uuid = "4566e69f-c907-48ee-8d71-d7ba5aa200d0",
                        .username = login_start_packet.name,
                    };
                    try clientbound.LoginSuccess.write(writer, login_success_packet, allocator);
                    current_state.* = .Play;
                    try completeLogin(g_client, allocator, game_world, current_player, login_start_packet.name);
                    keep_alive_timer.* = std.time.Timer.start() catch null;
                },
                // 0x01 => { // Encryption Response - disabled for offline mode
                //     // This code would handle online mode encryption response
                // },
                else => {
                    std.debug.print("Unknown packet ID 0x{x} in Login state.\n", .{packet_id});
                    return error.UnknownPacket;
                },
            }
        },
        .Play => {
            switch (packet_id) {
                serverbound.KeepAlive.id => {
                    const keep_alive = try serverbound.KeepAlive.read(buffer_reader);
                    std.debug.print("KeepAlive received: {d}\n", .{keep_alive.keep_alive_id});
                    if (keep_alive.keep_alive_id != last_keep_alive_id.*) {
                        std.debug.print("Incorrect Keep Alive ID. Expected {d}, got {d}\n", .{ last_keep_alive_id.*, keep_alive.keep_alive_id });
                    }
                },
                serverbound.ChatMessage.id => {
                    const chat_packet = try serverbound.ChatMessage.read(buffer_reader, allocator);
                    std.debug.print("Chat from {s}: {s}\n", .{ current_player.*.name, chat_packet.message });

                    if (chat_packet.message.len > 0 and chat_packet.message[0] == '/') {
                        try cmd_manager.execute(
                            chat_packet.message[1..],
                            current_player.*.name,
                            writer,
                            allocator,
                        );
                    } else {
                        std.debug.print("{s}: {s}\n", .{ current_player.*.name, chat_packet.message });
                    }
                },
                serverbound.Player.id => {
                    const p = try serverbound.Player.read(buffer_reader);
                    current_player.*.on_ground = p.on_ground;
                },
                serverbound.PlayerPosition.id => {
                    const p = try serverbound.PlayerPosition.read(buffer_reader);
                    const prev_x = current_player.*.x;
                    const prev_y = current_player.*.y;
                    const prev_z = current_player.*.z;
                    current_player.*.x = p.x;
                    current_player.*.y = p.feet_y;
                    current_player.*.z = p.z;
                    current_player.*.on_ground = p.on_ground;
                    current_player.*.velocity_x = p.x - prev_x;
                    current_player.*.velocity_y = p.feet_y - prev_y;
                    current_player.*.velocity_z = p.z - prev_z;
                },
                serverbound.PlayerLook.id => {
                    const p = try serverbound.PlayerLook.read(buffer_reader);
                    current_player.*.yaw = p.yaw;
                    current_player.*.pitch = p.pitch;
                    current_player.*.on_ground = p.on_ground;
                },
                serverbound.PlayerPositionAndLook.id => {
                    const p = try serverbound.PlayerPositionAndLook.read(buffer_reader);
                    const prev_x = current_player.*.x;
                    const prev_y = current_player.*.y;
                    const prev_z = current_player.*.z;
                    current_player.*.x = p.x;
                    current_player.*.y = p.feet_y;
                    current_player.*.z = p.z;
                    current_player.*.yaw = p.yaw;
                    current_player.*.pitch = p.pitch;
                    current_player.*.on_ground = p.on_ground;
                    current_player.*.velocity_x = p.x - prev_x;
                    current_player.*.velocity_y = p.feet_y - prev_y;
                    current_player.*.velocity_z = p.z - prev_z;
                },
                else => {
                    std.debug.print("Unhandled Play packet ID: 0x{x}\n", .{packet_id});
                },
            }
        },
    }
}

pub fn handleClient(client: network.TcpClient, parent_allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var g_client = client;
    defer g_client.deinit();

    var cmd_manager = commands.CommandManager.init(allocator);

    var client_state: ClientState = undefined;
    var current_state: protocol.State = .Handshaking;
    var game_world: ?world.World = null;
    var current_player: player.Player = undefined;

    var keep_alive_timer: ?std.time.Timer = null;
    var last_keep_alive_id: i32 = 0;
    var last_packet_time: u64 = 0;

    while (true) {
        const has_packet = try g_client.poll(100);

        if (has_packet) {
            last_packet_time = keep_alive_timer.?.read();
            handlePacket(&g_client, &client_state, &current_state, &game_world, &current_player, &last_keep_alive_id, &keep_alive_timer, &cmd_manager, allocator) catch |err| {
                if (err == error.EndOfStream) return;
                std.log.err("Error handling packet: {s}", .{@errorName(err)});
                return;
            };
        }

        if (current_state == .Play) {
            const elapsed = keep_alive_timer.?.read();
            if (elapsed > 15_000_000_000) { // 15 seconds in nanoseconds
                last_keep_alive_id += 1;
                const keep_alive_packet = clientbound.KeepAlive{ .keep_alive_id = last_keep_alive_id };
                try clientbound.KeepAlive.write(g_client.getWriter(), keep_alive_packet, allocator);
                try g_client.writer_wrapper.flush();
                keep_alive_timer.?.reset();
            }

            if (elapsed - last_packet_time > 30_000_000_000) { // 30 seconds timeout
                std.debug.print("Client timed out.\n", .{});
                return;
            }

            if (game_world) |*gw| {
                current_player.updatePhysics(gw, 0.05);

                const tick = @divFloor(@as(u64, @intCast(elapsed)), POSITION_SYNC_INTERVAL_NS);
                if (tick % POSITION_SYNC_RATE == 0) {
                    const pos_packet = clientbound.PlayerPositionAndLook{
                        .x = current_player.x,
                        .y = current_player.y,
                        .z = current_player.z,
                        .yaw = current_player.yaw,
                        .pitch = current_player.pitch,
                        .flags = 0,
                    };
                    try clientbound.PlayerPositionAndLook.write(g_client.getWriter(), pos_packet, allocator);
                    try g_client.writer_wrapper.flush();
                }
            }
        }
    }
}
