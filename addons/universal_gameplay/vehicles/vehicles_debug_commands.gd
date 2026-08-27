class_name VehiclesDebugCommands
extends DebugCommandPack
## The plan's "enter vehicle" cheat.
##
## Goes through [method SeatComponent.enter] rather than placing the character
## in the seat directly. A cheat that bypasses the real entry path produces a
## character who is seated by every query and was never announced, never
## switched input context, and cannot get out -- which makes the console a
## source of bugs rather than a way to find them.

var _seats: SeatComponent = null
var _occupant: Node = null


func _init(seats: SeatComponent = null, occupant: Node = null) -> void:
	_seats = seats
	_occupant = occupant


func set_vehicle(seats: SeatComponent) -> void:
	_seats = seats


func set_occupant(occupant: Node) -> void:
	_occupant = occupant


func build_commands() -> Array[DebugCommand]:
	return [
		DebugCommand.create(
			&"enter", _enter, "Put the occupant in the target vehicle.", "[seat_id]", true
		),
		DebugCommand.create(
			&"exit", _exit, "Take the occupant out of the vehicle.", "", true
		),
		DebugCommand.create(
			&"seats", _list, "Show the target vehicle's seats and who is in them.", "", false
		),
	] as Array[DebugCommand]


func _enter(arguments: PackedStringArray) -> FrameworkResult:
	if _seats == null:
		return refuse("No vehicle target set.")
	if _occupant == null:
		return refuse("No occupant set.")
	var seat_id := StringName(arguments[0]) if not arguments.is_empty() else &""
	return _seats.enter(_occupant, seat_id)


func _exit(_arguments: PackedStringArray) -> FrameworkResult:
	if _seats == null:
		return refuse("No vehicle target set.")
	if _occupant == null:
		return refuse("No occupant set.")
	return _seats.exit(_occupant)


func _list(_arguments: PackedStringArray) -> FrameworkResult:
	if _seats == null:
		return refuse("No vehicle target set.")
	var lines: Array[String] = []
	for seat in _seats.get_seats():
		var occupant := _seats.get_occupant(seat.id)
		lines.append(
			"%s: %s" % [seat.id, occupant.name if occupant != null else "(empty)"]
		)
	if lines.is_empty():
		return FrameworkResult.ok("This vehicle has no seats.")
	return FrameworkResult.ok("\n".join(lines))
