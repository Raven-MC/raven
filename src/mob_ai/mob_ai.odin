package mob_ai

// TODO: mob AI logic (pathfinding, hostile mob ticks, etc.).

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
