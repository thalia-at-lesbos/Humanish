class_name DirtyFlags
extends Reference

# Per-region invalidation bit set (§2 of ui-design).
# SimFacade sets flags on state change; the presentation host clears them
# after rebuilding the affected region each frame.

var _flags: Array  # one bool per DirtyRegion (indices 0..3; ALL=4 is meta)

func _init() -> void:
    _flags = [false, false, false, false]

func set_dirty(region: int) -> void:
    if region == IDs.DirtyRegion.ALL:
        mark_all()
        return
    if region >= 0 and region < _flags.size():
        _flags[region] = true

func is_dirty(region: int) -> bool:
    if region == IDs.DirtyRegion.ALL:
        for f in _flags:
            if f:
                return true
        return false
    if region >= 0 and region < _flags.size():
        return _flags[region]
    return false

func clear(region: int) -> void:
    if region >= 0 and region < _flags.size():
        _flags[region] = false

func clear_all() -> void:
    for i in range(_flags.size()):
        _flags[i] = false

func mark_all() -> void:
    for i in range(_flags.size()):
        _flags[i] = true
