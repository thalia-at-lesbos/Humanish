class_name TileOutput

# Computes a tile's output vector per §1.3.
# Returns an Array of IDs.Output.COUNT integers: [food, production, commerce].
# All values clamped >= 0 at the end.

# compute(tile, db, player_known_techs) -> Array[int] of length 3
static func compute(tile: Tile, db: DataDB, known_techs: Array) -> Array:
	var out := [0, 0, 0]

	var terrain: Dictionary = db.get_terrain(tile.terrain_id)
	if terrain.empty():
		return out

	# 1. Terrain base output
	_add_output(out, terrain.get("base_output", {}))

	# 2. Landform adjustments (hills adjacency handled by feature, peaks block)
	# (Landform data embedded in terrain record for simplicity)

	# 3. Surface feature adjustments
	if tile.feature_id != "":
		var feature: Dictionary = db.get_feature(tile.feature_id)
		if not feature.empty():
			_add_output(out, feature.get("output_delta", {}))

	# 4. Connected resource output (gated by tech and improvement)
	if tile.resource_id != "":
		var res: Dictionary = db.get_resource(tile.resource_id)
		if not res.empty():
			var tech_req = res.get("tech_required", null)
			var imp_req = res.get("improvement_required", null)
			var tech_ok: bool = (tech_req == null or tech_req == "" or tech_req in known_techs)
			var imp_ok: bool = (imp_req == null or imp_req == "" or tile.improvement_id == imp_req)
			if tech_ok and imp_ok:
				_add_output(out, res.get("output", {}))

	# 5. Improvement output (gated by tech)
	if tile.improvement_id != "":
		var imp: Dictionary = db.get_improvement(tile.improvement_id)
		if not imp.empty():
			var tech_req = imp.get("tech_required", null)
			var tech_ok: bool = (tech_req == null or tech_req == "" or tech_req in known_techs)
			if tech_ok:
				_add_output(out, imp.get("output_delta", {}))

	# 6. Transport link output bonus
	if tile.transport_id != "":
		var tr: Dictionary = db.transport.get(tile.transport_id, {})
		if not tr.empty():
			var tech_req = tr.get("tech_required", null)
			var tech_ok: bool = (tech_req == null or tech_req == "" or tech_req in known_techs)
			if tech_ok:
				var commerce_bonus: int = int(tr.get("commerce_bonus", 0))
				out[IDs.Output.COMMERCE] += commerce_bonus

	# 7. Clamp all outputs >= 0
	for i in range(out.size()):
		out[i] = max(0, out[i])

	return out

static func _add_output(out: Array, delta: Dictionary) -> void:
	out[IDs.Output.FOOD]       += int(delta.get("food", 0))
	out[IDs.Output.PRODUCTION] += int(delta.get("production", 0))
	out[IDs.Output.COMMERCE]   += int(delta.get("commerce", 0))
