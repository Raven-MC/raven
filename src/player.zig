const std = @import("std");
const world = @import("world/world.zig");

/// Physics constants approximating Minecraft 1.8.x values.
pub const GRAVITY: f64 = -19.6;
/// blocks/second^2
pub const JUMP_VELOCITY: f64 = 4.125;
/// blocks/second (jump height ~1.25 blocks)
pub const WALK_SPEED: f64 = 4.317;
/// blocks/second
pub const FRICTION: f64 = 0.91;
/// velocity multiplier per tick
pub const FLY_SPEED: f64 = 10.0;
/// blocks/second (creative mode)
pub const PLAYER_HEIGHT: f64 = 1.62;
/// meters (eye height)
pub const Player = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    on_ground: bool = false,

    velocity_x: f64 = 0.0,
    velocity_y: f64 = 0.0,
    velocity_z: f64 = 0.0,
    is_flying: bool = false,

    entity_id: i32,
    name: []const u8,

    pub fn init(entity_id: i32, name: []const u8) Player {
        return .{ .entity_id = entity_id, .name = name };
    }

    pub fn getGroundHeight(self: *const Player, game_world: *world.World) f64 {
        const block_x: i32 = @intFromFloat(self.x);
        const block_z: i32 = @intFromFloat(self.z);

        var check_y: i32 = 127;
        while (check_y >= 0) : (check_y -= 1) {
            const block = game_world.getBlockAt(block_x, check_y, block_z);
            if (block.id != 0) {
                return @as(f64, @floatFromInt(check_y));
            }
        }
        return 0.0;
    }

    pub fn updatePhysics(self: *Player, game_world: *world.World, dt: f64) void {
        const speed = if (self.is_flying) FLY_SPEED else WALK_SPEED;
        _ = speed;

        const ground_y = self.getGroundHeight(game_world);

        if (!self.is_flying) {
            if (!self.on_ground and self.velocity_y > -78.4) {
                self.velocity_y += GRAVITY * dt;
            }
        }

        self.velocity_x *= FRICTION;
        self.velocity_z *= FRICTION;

        const new_x = self.x + self.velocity_x * dt;
        const new_y = self.y + self.velocity_y * dt;
        const new_z = self.z + self.velocity_z * dt;

        const target_y = if (self.is_flying) new_y else ground_y + PLAYER_HEIGHT;
        _ = target_y;

        if (new_y <= ground_y + PLAYER_HEIGHT and !self.is_flying) {
            self.y = ground_y + PLAYER_HEIGHT;
            self.velocity_y = 0;
            self.on_ground = true;
        } else {
            self.y = new_y;
            self.on_ground = false;
        }

        self.x = new_x;
        self.z = new_z;
    }

    pub fn applyMovementInput(self: *Player, delta_x: f64, delta_y: f64, delta_z: f64) void {
        const yaw_rad = @as(f64, self.yaw) * std.math.pi / 180.0;

        const forward = -@sin(yaw_rad);
        const right = @cos(yaw_rad);

        self.velocity_x += (delta_x * right - delta_z * forward) * 0.1;
        self.velocity_z += (delta_x * forward + delta_z * right) * 0.1;

        if (delta_y > 0 and self.on_ground and !self.is_flying) {
            self.velocity_y = JUMP_VELOCITY;
            self.on_ground = false;
        } else if (self.is_flying) {
            self.velocity_y = delta_y * 0.5;
        }
    }
};
