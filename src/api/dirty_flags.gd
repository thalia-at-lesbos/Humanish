# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

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
