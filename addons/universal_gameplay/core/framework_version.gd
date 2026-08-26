class_name FrameworkVersion
extends RefCounted
## Version constants for the framework and every schema it persists.
##
## The framework version and the save schema version move independently
## (Implementation Plan 43): adding an optional field is a MINOR bump but
## leaves the save schema untouched.

const MAJOR: int = 0
const MINOR: int = 1
const PATCH: int = 0

## Bumped only when persisted save data changes shape. Migrations are
## registered against this integer, never against the framework version.
const SAVE_SCHEMA: int = 1

## Minimum Godot version this framework is built against.
const REQUIRED_GODOT: Array[int] = [4, 7]


static func get_version_string() -> String:
	return "%d.%d.%d" % [MAJOR, MINOR, PATCH]


static func is_godot_supported() -> bool:
	var info: Dictionary = Engine.get_version_info()
	var major: int = int(info.get("major", 0))
	var minor: int = int(info.get("minor", 0))
	if major != REQUIRED_GODOT[0]:
		return major > REQUIRED_GODOT[0]
	return minor >= REQUIRED_GODOT[1]
