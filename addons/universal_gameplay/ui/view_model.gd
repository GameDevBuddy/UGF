class_name ViewModel
extends RefCounted
## A snapshot of something, shaped for drawing.
##
## [b]Plain data, and deliberately a copy.[/b] A view model holds numbers and
## strings, never the component it came from — because a widget handed a live
## [HealthComponent] can call [method HealthComponent.kill] on it, and then the
## health bar is a weapon. Copying is what makes "UI contains no domain
## authority" a property of the type rather than a rule people remember
## (rule 21).
##
## It is also what makes a HUD testable without a screen: a presenter's output
## is a value you can assert on.

## When this snapshot was taken, in engine milliseconds. What a widget uses to
## ignore a stale model that arrived out of order.
var captured_at_ms: int = 0

## Whether the thing being described exists at all. A HUD draws nothing rather
## than zeroes when the player has no inventory (rule 31).
var present: bool = false


func _init() -> void:
	captured_at_ms = Time.get_ticks_msec()


## Plain-data form, for a debug panel, a log, or a test that wants to compare
## whole snapshots rather than field by field.
func to_dictionary() -> Dictionary:
	return {"present": present, "captured_at_ms": captured_at_ms}


## Whether this snapshot is older than [param age_ms]. A widget that renders
## on a timer uses it to grey out rather than to show a lie.
func is_stale(age_ms: int) -> bool:
	return Time.get_ticks_msec() - captured_at_ms > age_ms
