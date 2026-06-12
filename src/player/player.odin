package player

import "core:math"

import "../world"

// Physics constants approximating Minecraft 1.8.x values.
GRAVITY :: -19.6
JUMP_VELOCITY :: 4.125
WALK_SPEED :: 4.317
FRICTION :: 0.91
FLY_SPEED :: 10.0
PLAYER_HEIGHT :: 1.62

// Represents a player's position, velocity, and flight state. Methods:
// player_init creates a default player; get_ground_height finds the floor;
// update_physics applies gravity/ground collision each tick;
// apply_movement_input maps WASD input to velocity (stub).
Player :: struct {
	x:          f64,
	y:          f64,
	z:          f64,
	yaw:        f32,
	pitch:      f32,
	on_ground:  bool,
	velocity_x: f64,
	velocity_y: f64,
	velocity_z: f64,
	is_flying:  bool,
	entity_id:  i32,
	name:       string,
}

// Creates a Player at the world origin with default velocity and no motion.
player_init :: proc(entity_id: i32, name: string) -> Player {
	return Player {
		x = 0.0,
		y = 0.0,
		z = 0.0,
		yaw = 0.0,
		pitch = 0.0,
		on_ground = false,
		velocity_x = 0.0,
		velocity_y = 0.0,
		velocity_z = 0.0,
		is_flying = false,
		entity_id = entity_id,
		name = name,
	}
}

// Returns the Y coordinate of the highest solid block directly below the player.
// Used by update_physics and complete_login to place the player on the ground.
get_ground_height :: proc(p: ^Player, w: ^world.World) -> f64 {
	bx := i32(p.x)
	bz := i32(p.z)
	for y: i32 = 127; y >= 0; y -= 1 {
		b := world.world_get_block_at(w, bx, y, bz)
		if b.id != 0 {
			return f64(y)
		}
	}
	return 0.0
}

// Applies gravity, friction, and ground collision to the player. Called every
// tick from the client handler. Note: dt is currently ignored (physics are
// frame-rate dependent - see the player package for constants).
update_physics :: proc(p: ^Player, w: ^world.World, dt: f64) {
	_ = dt // NOTE: physics are frame-rate dependent (dt ignored)
	ground_y := get_ground_height(p, w)

	if !p.is_flying {
		if !p.on_ground && p.velocity_y > -78.4 {
			p.velocity_y += GRAVITY * dt
		}
	}

	p.velocity_x *= FRICTION
	p.velocity_z *= FRICTION

	new_x := p.x + p.velocity_x * dt
	new_y := p.y + p.velocity_y * dt
	new_z := p.z + p.velocity_z * dt

	if new_y <= ground_y + PLAYER_HEIGHT && !p.is_flying {
		p.y = ground_y + PLAYER_HEIGHT
		p.velocity_y = 0
		p.on_ground = true
	} else {
		p.y = new_y
		p.on_ground = false
	}
	p.x = new_x
	p.z = new_z
}

// Applies WASD-style input to player velocity, accounting for yaw rotation.
// Stub - not currently wired into the packet handler.
apply_movement_input :: proc(p: ^Player, dx: f64, dy: f64, dz: f64) {
	yaw_rad := f64(p.yaw) * math.PI / 180.0
	forward := -math.sin(yaw_rad)
	right := math.cos(yaw_rad)

	p.velocity_x += (dx * right - dz * forward) * 0.1
	p.velocity_z += (dx * forward + dz * right) * 0.1

	if dy > 0 && p.on_ground && !p.is_flying {
		p.velocity_y = JUMP_VELOCITY
		p.on_ground = false
	} else if p.is_flying {
		p.velocity_y = dy * 0.5
	}
}
