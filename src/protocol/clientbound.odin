package protocol

// Status packet IDs
CB_STATUS_RESPONSE  :: 0x00
CB_PONG             :: 0x01

// Login packet IDs
CB_LOGIN_DISCONNECT      :: 0x00
CB_ENCRYPTION_REQUEST    :: 0x01
CB_LOGIN_SUCCESS         :: 0x02
CB_SET_COMPRESSION       :: 0x03

// Play packet IDs
CB_KEEP_ALIVE               :: 0x00
CB_CHAT_MESSAGE             :: 0x02
CB_TIME_UPDATE              :: 0x03
CB_ENTITY_EQUIPMENT         :: 0x04
CB_SPAWN_POSITION           :: 0x05
CB_UPDATE_HEALTH            :: 0x06
CB_RESPAWN                  :: 0x07
CB_PLAYER_POSITION_AND_LOOK :: 0x08
CB_HELD_ITEM_CHANGE         :: 0x09
CB_ANIMATION                :: 0x0B
CB_SPAWN_PLAYER             :: 0x0C
CB_SPAWN_OBJECT             :: 0x0E
CB_SPAWN_MOB                :: 0x0F
CB_DESTROY_ENTITIES         :: 0x13
CB_ENTITY_TELEPORT          :: 0x18
CB_CHUNK_DATA               :: 0x21
CB_PLAYER_LIST_ITEM         :: 0x38

// --- Status & Login writers ---

Status_Response :: struct {
	json_response: string,
}

write_status_response :: proc(w: ^Buffer_Writer, p: Status_Response) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_STATUS_RESPONSE); err != nil {
		return err
	}
	return bw_write_string(w, p.json_response)
}

Pong :: struct {
	payload: i64,
}

write_pong :: proc(w: ^Buffer_Writer, p: Pong) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_PONG); err != nil {
		return err
	}
	return bw_write_int(w, i64, p.payload)
}

Login_Disconnect :: struct {
	reason: string,
}

write_login_disconnect :: proc(w: ^Buffer_Writer, p: Login_Disconnect) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_LOGIN_DISCONNECT); err != nil {
		return err
	}
	return bw_write_string(w, p.reason)
}

Encryption_Request :: struct {
	server_id:    string,
	public_key:   []u8,
	verify_token: []u8,
}

write_encryption_request :: proc(w: ^Buffer_Writer, p: Encryption_Request) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_ENCRYPTION_REQUEST); err != nil {
		return err
	}
	if err := bw_write_string(w, p.server_id); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(len(p.public_key))); err != nil {
		return err
	}
	if err := bw_write_bytes(w, p.public_key); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(len(p.verify_token))); err != nil {
		return err
	}
	return bw_write_bytes(w, p.verify_token)
}

Login_Success :: struct {
	uuid:     string,
	username: string,
}

write_login_success :: proc(w: ^Buffer_Writer, p: Login_Success) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_LOGIN_SUCCESS); err != nil {
		return err
	}
	if err := bw_write_string(w, p.uuid); err != nil {
		return err
	}
	return bw_write_string(w, p.username)
}

Set_Compression :: struct {
	threshold: i32,
}

write_set_compression :: proc(w: ^Buffer_Writer, p: Set_Compression) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_SET_COMPRESSION); err != nil {
		return err
	}
	return bw_write_varint(w, i64(p.threshold))
}

// --- Play writers ---

Join_Game :: struct {
	entity_id:         i32,
	gamemode:          u8,
	dimension:         i8,
	difficulty:        u8,
	max_players:       u8,
	level_type:        string,
	reduced_debug_info: bool,
}

write_join_game :: proc(w: ^Buffer_Writer, p: Join_Game) -> Protocol_Send_Error {
	if err := bw_write_varint(w, 0x01); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.entity_id); err != nil {
		return err
	}
	if err := bw_write_byte(w, u8(p.gamemode)); err != nil {
		return err
	}
	if err := bw_write_int(w, i8, p.dimension); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.difficulty); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.max_players); err != nil {
		return err
	}
	if err := bw_write_string(w, p.level_type); err != nil {
		return err
	}
	return bw_write_byte(w, p.reduced_debug_info ? 1 : 0)
}

Player_Position_And_Look_CB :: struct {
	x:     f64,
	y:     f64,
	z:     f64,
	yaw:   f32,
	pitch: f32,
	flags: u8,
}

write_player_position_and_look :: proc(w: ^Buffer_Writer, p: Player_Position_And_Look_CB) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_PLAYER_POSITION_AND_LOOK); err != nil {
		return err
	}
	if err := bw_write_int(w, f64, p.x); err != nil {
		return err
	}
	if err := bw_write_int(w, f64, p.y); err != nil {
		return err
	}
	if err := bw_write_int(w, f64, p.z); err != nil {
		return err
	}
	if err := bw_write_int(w, f32, p.yaw); err != nil {
		return err
	}
	if err := bw_write_int(w, f32, p.pitch); err != nil {
		return err
	}
	return bw_write_byte(w, p.flags)
}

Keep_Alive :: struct {
	keep_alive_id: i32,
}

write_keep_alive :: proc(w: ^Buffer_Writer, p: Keep_Alive) -> Protocol_Send_Error {
	if err := bw_write_varint(w, 0x00); err != nil {
		return err
	}
	return bw_write_varint(w, i64(p.keep_alive_id))
}

Chunk_Data :: struct {
	chunk_x:             i32,
	chunk_z:             i32,
	ground_up_continuous: bool,
	primary_bit_mask:    u16,
	data:                []u8,
}

write_chunk_data :: proc(w: ^Buffer_Writer, p: Chunk_Data) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_CHUNK_DATA); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.chunk_x); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.chunk_z); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.ground_up_continuous ? 1 : 0); err != nil {
		return err
	}
	if err := bw_write_int(w, u16, p.primary_bit_mask); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(len(p.data))); err != nil {
		return err
	}
	return bw_write_bytes(w, p.data)
}

Spawn_Player :: struct {
	entity_id:   i32,
	player_uuid: [16]u8,
	x:           i32,
	y:           i32,
	z:           i32,
	yaw:         u8,
	pitch:       u8,
	current_item: i16,
	metadata:    []u8,
}

write_spawn_player :: proc(w: ^Buffer_Writer, p: Spawn_Player) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_SPAWN_PLAYER); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.entity_id)); err != nil {
		return err
	}
	if err := bw_write_uuid(w, p.player_uuid); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.x); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.y); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.z); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.yaw); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.pitch); err != nil {
		return err
	}
	if err := bw_write_int(w, i16, p.current_item); err != nil {
		return err
	}
	return bw_write_bytes(w, p.metadata)
}

Destroy_Entities :: struct {
	entity_ids: []i32,
}

write_destroy_entities :: proc(w: ^Buffer_Writer, p: Destroy_Entities) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_DESTROY_ENTITIES); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(len(p.entity_ids))); err != nil {
		return err
	}
	for id in p.entity_ids {
		if err := bw_write_varint(w, i64(id)); err != nil {
			return err
		}
	}
	return nil
}

Entity_Teleport :: struct {
	entity_id: i32,
	x:         i32,
	y:         i32,
	z:         i32,
	yaw:       u8,
	pitch:     u8,
	on_ground: bool,
}

write_entity_teleport :: proc(w: ^Buffer_Writer, p: Entity_Teleport) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_ENTITY_TELEPORT); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.entity_id)); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.x); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.y); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.z); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.yaw); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.pitch); err != nil {
		return err
	}
	return bw_write_byte(w, p.on_ground ? 1 : 0)
}

Player_List_Item_Property :: struct {
	name:      string,
	value:     string,
	is_signed: bool,
	signature: Maybe(string),
}

Player_List_Item_Player :: struct {
	uuid:            [16]u8,
	name:            string,
	properties:      []Player_List_Item_Property,
	gamemode:        i32,
	ping:            i32,
	has_display_name: bool,
	display_name:    Maybe(string),
}

Player_List_Item :: struct {
	action:  i32,
	players: []Player_List_Item_Player,
}

write_player_list_item :: proc(w: ^Buffer_Writer, p: Player_List_Item) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_PLAYER_LIST_ITEM); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.action)); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(len(p.players))); err != nil {
		return err
	}
	for pl in p.players {
		if err := bw_write_uuid(w, pl.uuid); err != nil {
			return err
		}
		switch p.action {
		case 0: // add player
			if err := bw_write_string(w, pl.name); err != nil {
				return err
			}
			if err := bw_write_varint(w, i64(len(pl.properties))); err != nil {
				return err
			}
			for prop in pl.properties {
				if err := bw_write_string(w, prop.name); err != nil {
					return err
				}
				if err := bw_write_string(w, prop.value); err != nil {
					return err
				}
				if err := bw_write_byte(w, prop.is_signed ? 1 : 0); err != nil {
					return err
				}
				if prop.is_signed {
					sig, ok := prop.signature.?
					if !ok {
						return .Invalid_Argument
					}
					if err := bw_write_string(w, sig); err != nil {
						return err
					}
				}
			}
			if err := bw_write_varint(w, i64(pl.gamemode)); err != nil {
				return err
			}
			if err := bw_write_varint(w, i64(pl.ping)); err != nil {
				return err
			}
			if err := bw_write_byte(w, pl.has_display_name ? 1 : 0); err != nil {
				return err
			}
			if pl.has_display_name {
				dn, ok := pl.display_name.?
				if !ok {
					return .Invalid_Argument
				}
				if err := bw_write_string(w, dn); err != nil {
					return err
				}
			}
		case 1: // update gamemode
			if err := bw_write_varint(w, i64(pl.gamemode)); err != nil {
				return err
			}
		case 2: // update latency
			if err := bw_write_varint(w, i64(pl.ping)); err != nil {
				return err
			}
		case 3: // update display name
			if err := bw_write_byte(w, pl.has_display_name ? 1 : 0); err != nil {
				return err
			}
			if pl.has_display_name {
				dn, ok := pl.display_name.?
				if !ok {
					return .Invalid_Argument
				}
				if err := bw_write_string(w, dn); err != nil {
					return err
				}
			}
		case 4: // remove player
			// No payload.
		case:
			return .Invalid_Argument
		}
	}
	return nil
}

Entity_Equipment :: struct {
	entity_id: i32,
	slot:      i16,
	item:      Item_Slot,
}

write_entity_equipment :: proc(w: ^Buffer_Writer, p: Entity_Equipment) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_ENTITY_EQUIPMENT); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.entity_id)); err != nil {
		return err
	}
	if err := bw_write_int(w, i16, p.slot); err != nil {
		return err
	}
	return write_item_slot(w, p.item)
}

Spawn_Position :: struct {
	location: Position,
}

write_spawn_position :: proc(w: ^Buffer_Writer, p: Spawn_Position) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_SPAWN_POSITION); err != nil {
		return err
	}
	return bw_write_position(w, p.location.x, p.location.y, p.location.z)
}

Update_Health :: struct {
	health:           f32,
	food:             i32,
	food_saturation:  f32,
}

write_update_health :: proc(w: ^Buffer_Writer, p: Update_Health) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_UPDATE_HEALTH); err != nil {
		return err
	}
	if err := bw_write_int(w, f32, p.health); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.food)); err != nil {
		return err
	}
	return bw_write_int(w, f32, p.food_saturation)
}

Respawn :: struct {
	dimension:  i32,
	difficulty: u8,
	gamemode:   u8,
	level_type: string,
}

write_respawn :: proc(w: ^Buffer_Writer, p: Respawn) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_RESPAWN); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.dimension); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.difficulty); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.gamemode); err != nil {
		return err
	}
	return bw_write_string(w, p.level_type)
}

Held_Item_Change :: struct {
	slot: i8,
}

write_held_item_change :: proc(w: ^Buffer_Writer, p: Held_Item_Change) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_HELD_ITEM_CHANGE); err != nil {
		return err
	}
	return bw_write_int(w, i8, p.slot)
}

Animation_CB :: struct {
	entity_id:    i32,
	animation_id: u8,
}

write_animation :: proc(w: ^Buffer_Writer, p: Animation_CB) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_ANIMATION); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.entity_id)); err != nil {
		return err
	}
	return bw_write_byte(w, p.animation_id)
}

Spawn_Object :: struct {
	entity_id:  i32,
	type:       u8,
	x:          i32,
	y:          i32,
	z:          i32,
	pitch:      u8,
	yaw:        u8,
	data:       i32,
	velocity_x: Maybe(i16),
	velocity_y: Maybe(i16),
	velocity_z: Maybe(i16),
}

write_spawn_object :: proc(w: ^Buffer_Writer, p: Spawn_Object) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_SPAWN_OBJECT); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.entity_id)); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.type); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.x); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.y); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.z); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.pitch); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.yaw); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.data); err != nil {
		return err
	}
	if p.data > 0 {
		vx, okx := p.velocity_x.?
		if !okx { return .Invalid_Argument }
		vy, oky := p.velocity_y.?
		if !oky { return .Invalid_Argument }
		vz, okz := p.velocity_z.?
		if !okz { return .Invalid_Argument }
		if err := bw_write_int(w, i16, vx); err != nil { return err }
		if err := bw_write_int(w, i16, vy); err != nil { return err }
		if err := bw_write_int(w, i16, vz); err != nil { return err }
	}
	return nil
}

Spawn_Mob :: struct {
	entity_id:  i32,
	type:       u8,
	x:          i32,
	y:          i32,
	z:          i32,
	yaw:        u8,
	pitch:      u8,
	head_pitch: u8,
	velocity_x: i16,
	velocity_y: i16,
	velocity_z: i16,
	metadata:   []u8,
}

write_spawn_mob :: proc(w: ^Buffer_Writer, p: Spawn_Mob) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_SPAWN_MOB); err != nil {
		return err
	}
	if err := bw_write_varint(w, i64(p.entity_id)); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.type); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.x); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.y); err != nil {
		return err
	}
	if err := bw_write_int(w, i32, p.z); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.yaw); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.pitch); err != nil {
		return err
	}
	if err := bw_write_byte(w, p.head_pitch); err != nil {
		return err
	}
	if err := bw_write_int(w, i16, p.velocity_x); err != nil {
		return err
	}
	if err := bw_write_int(w, i16, p.velocity_y); err != nil {
		return err
	}
	if err := bw_write_int(w, i16, p.velocity_z); err != nil {
		return err
	}
	return bw_write_bytes(w, p.metadata)
}

Time_Update :: struct {
	world_age:   i64,
	time_of_day: i64,
}

write_time_update :: proc(w: ^Buffer_Writer, p: Time_Update) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_TIME_UPDATE); err != nil {
		return err
	}
	if err := bw_write_int(w, i64, p.world_age); err != nil {
		return err
	}
	return bw_write_int(w, i64, p.time_of_day)
}

Chat_Message_CB :: struct {
	json_data: string,
	position:  i8,
}

write_chat_message :: proc(w: ^Buffer_Writer, p: Chat_Message_CB) -> Protocol_Send_Error {
	if err := bw_write_varint(w, CB_CHAT_MESSAGE); err != nil {
		return err
	}
	if err := bw_write_string(w, p.json_data); err != nil {
		return err
	}
	return bw_write_int(w, i8, p.position)
}
