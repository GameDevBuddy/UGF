extends FrameworkEvent
## Somebody got in, somebody got out, or something got wrecked.
##
## The three vehicle facts worth carrying across features. Everything finer --
## which gear, how fast, how far -- stays a local signal, because a bus
## carrying telemetry is a bus nobody can read (rule 6).
##
## Named ids rather than node references, so an objective can match on "entered
## a police car" without Missions loading Vehicles (rule 32).
##
## No class_name: events are constructed by the adapter that publishes them and
## matched by name on the bus.

## Which vehicle. Its persistent id when it has one, its definition id
## otherwise.
var vehicle_id: StringName = &""

## What kind of vehicle, so an objective can match a class rather than one car.
var vehicle_tags: Array[StringName] = []

## Who did it. Blank for a vehicle destroyed by nobody in particular.
var actor_id: StringName = &""

## Which seat, for entry and exit.
var seat_id: StringName = &""

## Whether the occupant was the driver, which is the distinction a "steal a
## car" objective needs and a "get in the van" objective does not.
var driver: bool = false

var _name: StringName = &""


static func entered(
	p_vehicle: StringName,
	p_actor: StringName,
	p_seat: StringName,
	p_driver: bool,
	p_tags: Array[StringName] = []
) -> FrameworkEvent:
	var event := _make(GameplayNames.EVENT_VEHICLE_ENTERED, p_vehicle, p_tags)
	event.actor_id = p_actor
	event.seat_id = p_seat
	event.driver = p_driver
	return event


static func exited(
	p_vehicle: StringName,
	p_actor: StringName,
	p_seat: StringName,
	p_driver: bool,
	p_tags: Array[StringName] = []
) -> FrameworkEvent:
	var event := _make(GameplayNames.EVENT_VEHICLE_EXITED, p_vehicle, p_tags)
	event.actor_id = p_actor
	event.seat_id = p_seat
	event.driver = p_driver
	return event


static func destroyed(
	p_vehicle: StringName, p_tags: Array[StringName] = []
) -> FrameworkEvent:
	return _make(GameplayNames.EVENT_VEHICLE_DESTROYED, p_vehicle, p_tags)


static func _make(
	p_name: StringName, p_vehicle: StringName, p_tags: Array[StringName]
) -> FrameworkEvent:
	var event := (load(
		"res://addons/universal_gameplay/vehicles/vehicle_event.gd"
	) as GDScript).new()
	event._name = p_name
	event.vehicle_id = p_vehicle
	event.vehicle_tags = p_tags.duplicate()
	return event


func get_event_name() -> StringName:
	return _name


func has_vehicle_tag(tag: StringName) -> bool:
	return vehicle_tags.has(tag)
