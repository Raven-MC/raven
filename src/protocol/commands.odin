package protocol

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

// Shared state between the handler and command dispatch: game time and player
// count. Stored per-client-connection; updated by time_command and the handler.
Command_State :: struct {
	game_time:    i64,
	player_count: int,
}

// Routes parsed command strings to the correct handler (help/say/time/list/me).
// Created by command_manager_init, used by execute.
Command_Manager :: struct {
	allocator: mem.Allocator,
	state:     ^Command_State,
}

command_manager_init :: proc(allocator: mem.Allocator, state: ^Command_State) -> Command_Manager {
	return Command_Manager{allocator = allocator, state = state}
}

// Parses and dispatches a command string (without leading /) to the appropriate
// handler. Writes the response as chat packet bytes into the Buffer_Writer.
execute :: proc(
	mgr: ^Command_Manager,
	input: string,
	sender_name: string,
	w: ^Buffer_Writer,
) -> Protocol_Send_Error {
	trimmed := strings.trim_space(input)
	if len(trimmed) == 0 {
		return nil
	}

	cmd_name, args := split_command(trimmed)

	switch cmd_name {
	case "help":
		return help_command(mgr, w)
	case "say":
		return say_command(mgr, args, sender_name, w)
	case "time":
		return time_command(mgr, args, w)
	case "list", "players", "online":
		return list_command(mgr, w)
	case "me":
		return me_command(mgr, args, sender_name, w)
	case:
		json := fmt.tprintf("{\"text\":\"Unknown command: %s. Type /help for help.\"}", cmd_name)
		return write_chat_message(w, Chat_Message_CB{json_data = json, position = 0})
	}
}

@(private)
// Splits "cmd args" into the command name and the arguments string.
split_command :: proc(s: string) -> (string, string) {
	idx := strings.index_byte(s, ' ')
	if idx < 0 {
		return s, ""
	}
	return s[:idx], s[idx + 1:]
}

@(private)
// Helper: sends a plain-text chat message (wrapped in JSON).
send_chat :: proc(w: ^Buffer_Writer, text: string) -> Protocol_Send_Error {
	json := fmt.tprintf("{\"text\":\"%s\"}", text)
	return write_chat_message(w, Chat_Message_CB{json_data = json, position = 0})
}

@(private)
// /help — lists available commands.
help_command :: proc(_: ^Command_Manager, w: ^Buffer_Writer) -> Protocol_Send_Error {
	return send_chat(w, "Available commands: /help, /say, /time, /list, /me")
}

@(private)
// /say <message> — broadcasts as [sender] message.
say_command :: proc(
	_: ^Command_Manager,
	args: string,
	sender_name: string,
	w: ^Buffer_Writer,
) -> Protocol_Send_Error {
	if len(args) == 0 {
		return send_chat(w, "Usage: /say <message>")
	}
	json := fmt.tprintf("{\"text\":\"[%s] %s\"}", sender_name, args)
	return write_chat_message(w, Chat_Message_CB{json_data = json, position = 0})
}

@(private)
// /time <set|add> <value> — changes the world time.
time_command :: proc(
	mgr: ^Command_Manager,
	args: string,
	w: ^Buffer_Writer,
) -> Protocol_Send_Error {
	idx := strings.index_byte(args, ' ')
	if idx <= 0 || len(args) == 0 {
		return send_chat(w, "Usage: /time <set|add> <value>")
	}
	action := args[:idx]
	value_str := args[idx + 1:]
	if len(value_str) == 0 {
		return send_chat(w, "Usage: /time <set|add> <value>")
	}
	value, ok := strconv.parse_int(value_str, 10)
	if !ok {
		return send_chat(w, "Invalid number")
	}
	switch action {
	case "set":
		mgr.state.game_time = i64(value)
		return send_chat(w, fmt.tprintf("Time set to %d", value))
	case "add":
		mgr.state.game_time += i64(value)
		return send_chat(w, fmt.tprintf("Time added %d", value))
	case:
		return send_chat(w, "Usage: /time <set|add> <value>")
	}
}

@(private)
// /list (or /players, /online) — prints the number of players online.
list_command :: proc(mgr: ^Command_Manager, w: ^Buffer_Writer) -> Protocol_Send_Error {
	return send_chat(w, fmt.tprintf("Players online: %d", mgr.state.player_count))
}

@(private)
// /me <action> — prints "* sender action" as an emote.
me_command :: proc(
	_: ^Command_Manager,
	args: string,
	sender_name: string,
	w: ^Buffer_Writer,
) -> Protocol_Send_Error {
	if len(args) == 0 {
		return send_chat(w, "Usage: /me <action>")
	}
	json := fmt.tprintf("{\"text\":\"* %s %s\"}", sender_name, args)
	return write_chat_message(w, Chat_Message_CB{json_data = json, position = 0})
}
