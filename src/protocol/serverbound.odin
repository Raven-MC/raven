package protocol

import "core:mem"

// Serverbound packet IDs (Play state)
KEEP_ALIVE :: 0x00
CHAT_MESSAGE :: 0x01
USE_ENTITY :: 0x02
// --- Movement packets ---
PLAYER :: 0x03
PLAYER_POSITION :: 0x04
PLAYER_LOOK :: 0x05
PLAYER_POSITION_AND_LOOK :: 0x06
// --- Block interaction ---
PLAYER_DIGGING :: 0x07
PLAYER_BLOCK_PLACEMENT :: 0x08
// --- Player action packets ---
HELD_ITEM_CHANGE :: 0x09
ANIMATION :: 0x0A
ENTITY_ACTION :: 0x0B
STEER_VEHICLE :: 0x0C
// --- Inventory packets ---
CLOSE_WINDOW :: 0x0D
CLICK_WINDOW :: 0x0E
CONFIRM_TRANSACTION :: 0x0F
CREATIVE_INVENTORY_ACTION :: 0x10
ENCHANT_ITEM :: 0x11
// --- Status / info packets ---
UPDATE_SIGN :: 0x12
PLAYER_ABILITIES :: 0x13
TAB_COMPLETE :: 0x14
CLIENT_SETTINGS :: 0x15
CLIENT_STATUS :: 0x16
PLUGIN_MESSAGE :: 0x17
SPECTATE :: 0x18
RESOURCE_PACK_STATUS :: 0x19

// --- Packet readers (Play state) ---

// Reads a keep-alive ID (0x00). The client echoes back the ID we sent.
read_keep_alive :: proc(r: ^Buffer_Reader) -> (i32, Protocol_Recv_Error) {
	return read_varint(r)
}

// Reads a chat message string (0x01) sent by the player.
read_chat_message :: proc(r: ^Buffer_Reader) -> (string, Protocol_Recv_Error) {
	return read_string(r)
}

// Sent when a player interacts with an entity (attack, interact, interact-at).
Use_Entity :: struct {
	target: i32,
	type:   i32,
	x:      f32,
	y:      f32,
	z:      f32,
}

read_use_entity :: proc(r: ^Buffer_Reader) -> (Use_Entity, Protocol_Recv_Error) {
	target, e0 := read_varint(r)
	if e0 != nil {return {}, e0}
	type_id, e1 := read_varint(r)
	if e1 != nil {return {}, e1}
	out := Use_Entity {
		target = target,
		type   = type_id,
	}
	if type_id == 2 {
		x, e2 := read_float(r)
		if e2 != nil {return {}, e2}
		y, e3 := read_float(r)
		if e3 != nil {return {}, e3}
		z, e4 := read_float(r)
		if e4 != nil {return {}, e4}
		out.x, out.y, out.z = x, y, z
	}
	return out, nil
}

// Sent when the player's on-ground state changes (0x03), with no position update.
Player :: struct {
	on_ground: bool,
}

read_player :: proc(r: ^Buffer_Reader) -> (Player, Protocol_Recv_Error) {
	on_ground, e0 := read_boolean(r)
	if e0 != nil {return {}, e0}
	return Player{on_ground = on_ground}, nil
}

Player_Position :: struct {
	x:         f64,
	feet_y:    f64,
	z:         f64,
	on_ground: bool,
}

// Reads position-only update (0x04): x, feet_y, z, on_ground.
read_player_position :: proc(r: ^Buffer_Reader) -> (Player_Position, Protocol_Recv_Error) {
	x, e0 := read_double(r)
	if e0 != nil {return {}, e0}
	feet_y, e1 := read_double(r)
	if e1 != nil {return {}, e1}
	z, e2 := read_double(r)
	if e2 != nil {return {}, e2}
	on_ground, e3 := read_boolean(r)
	if e3 != nil {return {}, e3}
	return Player_Position{x = x, feet_y = feet_y, z = z, on_ground = on_ground}, nil
}

Player_Look :: struct {
	yaw:       f32,
	pitch:     f32,
	on_ground: bool,
}

// Reads look-direction-only update (0x05): yaw, pitch, on_ground.
read_player_look :: proc(r: ^Buffer_Reader) -> (Player_Look, Protocol_Recv_Error) {
	yaw, e0 := read_float(r)
	if e0 != nil {return {}, e0}
	pitch, e1 := read_float(r)
	if e1 != nil {return {}, e1}
	on_ground, e2 := read_boolean(r)
	if e2 != nil {return {}, e2}
	return Player_Look{yaw = yaw, pitch = pitch, on_ground = on_ground}, nil
}

Player_Position_And_Look :: struct {
	x:         f64,
	feet_y:    f64,
	z:         f64,
	yaw:       f32,
	pitch:     f32,
	on_ground: bool,
}

// Reads combined position + look update (0x06): x, feet_y, z, yaw, pitch, on_ground.
read_player_position_and_look :: proc(
	r: ^Buffer_Reader,
) -> (
	Player_Position_And_Look,
	Protocol_Recv_Error,
) {
	x, e0 := read_double(r)
	if e0 != nil {return {}, e0}
	feet_y, e1 := read_double(r)
	if e1 != nil {return {}, e1}
	z, e2 := read_double(r)
	if e2 != nil {return {}, e2}
	yaw, e3 := read_float(r)
	if e3 != nil {return {}, e3}
	pitch, e4 := read_float(r)
	if e4 != nil {return {}, e4}
	on_ground, e5 := read_boolean(r)
	if e5 != nil {return {}, e5}
	return Player_Position_And_Look {
			x = x,
			feet_y = feet_y,
			z = z,
			yaw = yaw,
			pitch = pitch,
			on_ground = on_ground,
		},
		nil
}

Player_Digging :: struct {
	status:   i8,
	location: Position,
	face:     i8,
}

// Reads a dig/break action (0x07): status, block position, face.
read_player_digging :: proc(r: ^Buffer_Reader) -> (Player_Digging, Protocol_Recv_Error) {
	status, e0 := read_byte(r)
	if e0 != nil {return {}, e0}
	location, e1 := read_position(r)
	if e1 != nil {return {}, e1}
	face, e2 := read_byte(r)
	if e2 != nil {return {}, e2}
	return Player_Digging{status = status, location = location, face = face}, nil
}

Player_Block_Placement :: struct {
	location:          Position,
	face:              i8,
	held_item_slot:    i16,
	cursor_position_x: u8,
	cursor_position_y: u8,
	cursor_position_z: u8,
}

// Reads a block-place action (0x08): position, face, held item, cursor coords.
read_player_block_placement :: proc(
	r: ^Buffer_Reader,
) -> (
	Player_Block_Placement,
	Protocol_Recv_Error,
) {
	location, e0 := read_position(r)
	if e0 != nil {return {}, e0}
	face, e1 := read_byte(r)
	if e1 != nil {return {}, e1}
	held, e2 := read_short(r)
	if e2 != nil {return {}, e2}
	cx, e3 := read_ubyte(r)
	if e3 != nil {return {}, e3}
	cy, e4 := read_ubyte(r)
	if e4 != nil {return {}, e4}
	cz, e5 := read_ubyte(r)
	if e5 != nil {return {}, e5}
	return Player_Block_Placement {
			location = location,
			face = face,
			held_item_slot = held,
			cursor_position_x = cx,
			cursor_position_y = cy,
			cursor_position_z = cz,
		},
		nil
}

// Reads the selected hotbar slot (0x09) as a short.
read_held_item_change :: proc(r: ^Buffer_Reader) -> (i16, Protocol_Recv_Error) {
	return read_short(r)
}

// Reads and discards an animation packet (0x0A). The entity ID byte is consumed
// but not returned - animations are client-triggered only.
read_animation :: proc(r: ^Buffer_Reader) -> Protocol_Recv_Error {
	_, e0 := br_read_byte(r)
	if e0 != nil {return e0}
	return nil
}

Entity_Action :: struct {
	entity_id:        i32,
	action_id:        i32,
	action_parameter: i32,
}

// Reads an entity action (0x0B): entity_id, action_id, action_parameter.
read_entity_action :: proc(r: ^Buffer_Reader) -> (Entity_Action, Protocol_Recv_Error) {
	e, e0 := read_varint(r)
	if e0 != nil {return {}, e0}
	a, e1 := read_varint(r)
	if e1 != nil {return {}, e1}
	p, e2 := read_varint(r)
	if e2 != nil {return {}, e2}
	return Entity_Action{entity_id = e, action_id = a, action_parameter = p}, nil
}

Steer_Vehicle :: struct {
	sideways: f32,
	forward:  f32,
	flags:    u8,
}

// Reads vehicle steering input (0x0C): sideways, forward, flags.
read_steer_vehicle :: proc(r: ^Buffer_Reader) -> (Steer_Vehicle, Protocol_Recv_Error) {
	side, e0 := read_float(r)
	if e0 != nil {return {}, e0}
	fwd, e1 := read_float(r)
	if e1 != nil {return {}, e1}
	flags, e2 := read_ubyte(r)
	if e2 != nil {return {}, e2}
	return Steer_Vehicle{sideways = side, forward = fwd, flags = flags}, nil
}

// Reads the window ID to close (0x0D).
read_close_window :: proc(r: ^Buffer_Reader) -> (u8, Protocol_Recv_Error) {
	return read_ubyte(r)
}

Click_Window :: struct {
	window_id:     u8,
	slot:          i16,
	button:        i8,
	action_number: i16,
	mode:          i8,
	clicked_item:  Item_Slot,
}

// Reads a window click action (0x0E): slot, button, mode, clicked item.
read_click_window :: proc(r: ^Buffer_Reader) -> (Click_Window, Protocol_Recv_Error) {
	w, e0 := read_ubyte(r)
	if e0 != nil {return {}, e0}
	slot, e1 := read_short(r)
	if e1 != nil {return {}, e1}
	btn, e2 := read_byte(r)
	if e2 != nil {return {}, e2}
	act, e3 := read_short(r)
	if e3 != nil {return {}, e3}
	mode, e4 := read_byte(r)
	if e4 != nil {return {}, e4}
	item, e5 := read_item_slot(r)
	if e5 != nil {return {}, e5}
	return Click_Window {
			window_id = w,
			slot = slot,
			button = btn,
			action_number = act,
			mode = mode,
			clicked_item = item,
		},
		nil
}

Confirm_Transaction :: struct {
	window_id:     i8,
	action_number: i16,
	accepted:      bool,
}

// Reads a transaction confirmation (0x0F): window_id, action_number, accepted.
read_confirm_transaction :: proc(r: ^Buffer_Reader) -> (Confirm_Transaction, Protocol_Recv_Error) {
	w, e0 := read_byte(r)
	if e0 != nil {return {}, e0}
	a, e1 := read_short(r)
	if e1 != nil {return {}, e1}
	acc, e2 := read_boolean(r)
	if e2 != nil {return {}, e2}
	return Confirm_Transaction{window_id = w, action_number = a, accepted = acc}, nil
}

Creative_Inventory_Action :: struct {
	slot:         i16,
	clicked_item: Item_Slot,
}

// Reads a creative-mode inventory change (0x10): slot, clicked_item.
read_creative_inventory_action :: proc(
	r: ^Buffer_Reader,
) -> (
	Creative_Inventory_Action,
	Protocol_Recv_Error,
) {
	s, e0 := read_short(r)
	if e0 != nil {return {}, e0}
	item, e1 := read_item_slot(r)
	if e1 != nil {return {}, e1}
	return Creative_Inventory_Action{slot = s, clicked_item = item}, nil
}

// Reads the enchantment table slot (0x11) as a byte.
read_enchant_item :: proc(r: ^Buffer_Reader) -> (u8, Protocol_Recv_Error) {
	return read_ubyte(r)
}

Update_Sign :: struct {
	location: Position,
	text1:    string,
	text2:    string,
	text3:    string,
	text4:    string,
}

// Reads a sign text update (0x12): position + 4 lines of text.
read_update_sign :: proc(r: ^Buffer_Reader) -> (Update_Sign, Protocol_Recv_Error) {
	location, e0 := read_position(r)
	if e0 != nil {return {}, e0}
	text1, e1 := read_string(r)
	if e1 != nil {return {}, e1}
	text2, e2 := read_string(r)
	if e2 != nil {return {}, e2}
	text3, e3 := read_string(r)
	if e3 != nil {return {}, e3}
	text4, e4 := read_string(r)
	if e4 != nil {return {}, e4}
	return Update_Sign {
			location = location,
			text1 = text1,
			text2 = text2,
			text3 = text3,
			text4 = text4,
		},
		nil
}

Player_Abilities :: struct {
	flags:      u8,
	fly_speed:  f32,
	walk_speed: f32,
}

// Reads ability flags (0x13): flying, fly speed, walk speed.
read_player_abilities :: proc(r: ^Buffer_Reader) -> (Player_Abilities, Protocol_Recv_Error) {
	flags, e0 := read_ubyte(r)
	if e0 != nil {return {}, e0}
	fly_speed, e1 := read_float(r)
	if e1 != nil {return {}, e1}
	walk_speed, e2 := read_float(r)
	if e2 != nil {return {}, e2}
	return Player_Abilities{flags = flags, fly_speed = fly_speed, walk_speed = walk_speed}, nil
}

Tab_Complete :: struct {
	text:     string,
	position: i32,
}

// Reads a tab-complete request (0x14): partial text + position.
read_tab_complete :: proc(r: ^Buffer_Reader) -> (Tab_Complete, Protocol_Recv_Error) {
	text, e0 := read_string(r)
	if e0 != nil {return {}, e0}
	position, e1 := read_int(r)
	if e1 != nil {return {}, e1}
	return Tab_Complete{text = text, position = position}, nil
}

Client_Settings :: struct {
	locale:        string,
	view_distance: i8,
	chat_mode:     i8,
	chat_colors:   bool,
	skin_parts:    u8,
	main_hand:     i8,
}

// Reads client settings (0x15): locale, view distance, chat mode, skin parts, etc.
read_client_settings :: proc(r: ^Buffer_Reader) -> (Client_Settings, Protocol_Recv_Error) {
	locale, e0 := read_string(r)
	if e0 != nil {return {}, e0}
	view_distance, e1 := read_byte(r)
	if e1 != nil {return {}, e1}
	chat_mode, e2 := read_byte(r)
	if e2 != nil {return {}, e2}
	chat_colors, e3 := read_boolean(r)
	if e3 != nil {return {}, e3}
	skin_parts, e4 := read_ubyte(r)
	if e4 != nil {return {}, e4}
	main_hand, e5 := read_byte(r)
	if e5 != nil {return {}, e5}
	return Client_Settings {
			locale = locale,
			view_distance = view_distance,
			chat_mode = chat_mode,
			chat_colors = chat_colors,
			skin_parts = skin_parts,
			main_hand = main_hand,
		},
		nil
}

// Reads a client status action (0x16): respawn, stats, etc.
read_client_status :: proc(r: ^Buffer_Reader) -> (i8, Protocol_Recv_Error) {
	return read_byte(r)
}

Plugin_Message :: struct {
	channel: string,
	data:    []u8,
}

// Reads a plugin channel message (0x17): channel name + raw data.
read_plugin_message :: proc(
	r: ^Buffer_Reader,
	allocator: mem.Allocator,
) -> (
	Plugin_Message,
	Protocol_Recv_Error,
) {
	channel, e0 := read_string(r)
	if e0 != nil {return {}, e0}
	length, e1 := read_short(r)
	if e1 != nil {return {}, e1}
	if length < 0 || i32(length) > i32(len(r.data) - r.pos) {
		return {}, .Invalid_Argument
	}
	data := make([]u8, int(length), allocator)
	_, e2 := br_read_bytes(r, data)
	if e2 != nil {
		delete(data, allocator)
		return {}, e2
	}
	return Plugin_Message{channel = channel, data = data}, nil
}

Spectate :: struct {
	target_uuid: [16]u8,
}

// Reads a spectate target UUID (0x18).
read_spectate :: proc(r: ^Buffer_Reader) -> (Spectate, Protocol_Recv_Error) {
	uuid, e0 := read_uuid(r)
	if e0 != nil {return {}, e0}
	return Spectate{target_uuid = uuid}, nil
}

Resource_Pack_Status :: struct {
	hash:   string,
	result: i32,
}

// Reads a resource pack status response (0x19): hash + result code.
read_resource_pack_status :: proc(
	r: ^Buffer_Reader,
) -> (
	Resource_Pack_Status,
	Protocol_Recv_Error,
) {
	hash, e0 := read_string(r)
	if e0 != nil {return {}, e0}
	result, e1 := read_varint(r)
	if e1 != nil {return {}, e1}
	return Resource_Pack_Status{hash = hash, result = result}, nil
}
