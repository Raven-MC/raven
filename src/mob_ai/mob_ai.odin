package mob_ai

// Placeholder for mob AI logic.  The Odin port keeps the same shape as
// the original Zig stub so that future code (pathfinding, hostile mob
// ticks, etc.) can be added here without changing the import path.

Mob_AI :: struct {}

mob_ai_init :: proc() -> Mob_AI {
	return {}
}

mob_ai_destroy :: proc(ai: ^Mob_AI) {
	_ = ai
}

mob_ai_tick :: proc(ai: ^Mob_AI) {
	_ = ai
}
