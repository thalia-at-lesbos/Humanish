class_name RNG
extends Reference

# Deterministic seeded RNG using Godot's PCG32 implementation.
# All rule randomness must draw from this single instance in pipeline order.
# Named draw categories document which phase consumes each draw.

var _rng: RandomNumberGenerator

func _init() -> void:
	_rng = RandomNumberGenerator.new()

# Initialize with a seed; same seed always yields the same sequence.
func init(seed_val: int) -> void:
	_rng.seed = seed_val

# Draw an unsigned 32-bit integer.
func randi() -> int:
	return _rng.randi()

# Draw an integer in [lo, hi] inclusive.
func randi_range(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi)

# Draw a boolean where percent (0–100) is the probability of true.
func rand_bool_percent(percent: int) -> bool:
	return _rng.randi_range(0, 99) < percent

# Draw a weighted index: weights is an Array of non-negative ints.
# Returns the index whose bucket the draw lands in.
func rand_weighted(weights: Array) -> int:
	var total: int = 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return 0
	var roll: int = _rng.randi_range(0, total - 1)
	var cumul: int = 0
	for i in range(weights.size()):
		cumul += int(weights[i])
		if roll < cumul:
			return i
	return weights.size() - 1

# Serialize state so save/load can resume the exact sequence.
# Stored as strings to survive JSON double-precision loss (64-bit ints > 2^53).
func get_state() -> Dictionary:
	return {"seed": str(_rng.seed), "state": str(_rng.state)}

func restore_state(s: Dictionary) -> void:
	_rng.seed = int(str(s["seed"]))
	_rng.state = int(str(s["state"]))
