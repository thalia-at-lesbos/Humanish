# Pure helper for the economic-allocation sliders (finance/research/culture/intel).
#
# Keeps the four percentages summing to exactly 100 in a *predictable* way: when
# one slider is moved, the difference is taken from (or given to) the other three
# in a fixed round-robin order starting at the slider just after the one changed,
# in whole `step` increments. This removes the old behaviour where the imbalance
# was dumped onto whichever slider happened to be "first that can absorb it",
# which made the other values jump around unpredictably (and sometimes left the
# total off 100 so the command was silently rejected).
#
# Stateless and side-effect free so it can be unit-tested directly.

# Rebalance `vals` (an Array of 4 ints) after the slider at `changed_idx` is set
# to `new_val`. Returns a new 4-element Array of ints that sum to exactly 100,
# each in [0, 100]. The difference is absorbed by the other sliders in order
# starting from the one immediately after `changed_idx`, each fully absorbing
# what it can before the next is touched — so the closest slider reacts first.
static func rebalance(vals: Array, changed_idx: int, new_val: int) -> Array:
	var out: Array = [int(vals[0]), int(vals[1]), int(vals[2]), int(vals[3])]
	out[changed_idx] = _clampi(new_val, 0, 100)

	var excess: int = out[0] + out[1] + out[2] + out[3] - 100

	for k in range(1, 4):
		if excess == 0:
			break
		var idx: int = (changed_idx + k) % 4
		if excess > 0:
			# Remove from this slider whatever it can give.
			var take: int = excess if excess <= out[idx] else out[idx]
			out[idx] -= take
			excess -= take
		else:
			# Add to this slider up to its remaining headroom (excess is negative).
			var room: int = 100 - out[idx]
			var give: int = (-excess) if (-excess) <= room else room
			out[idx] += give
			excess += give

	return out

static func _clampi(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	return hi if v > hi else v
