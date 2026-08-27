class_name VehicleDefinition
extends FrameworkDefinition
## What a vehicle is: scene, seats, handling, fuel, storage, camera, upgrades.
##
## Adding a car to a game creates a [code].tres[/code] and no GDScript
## (rule 15). Everything here is a reference or a sub-resource, and three of
## them are borrowed wholesale from other modules — storage is an
## [InventoryProfile], upgrades are a [LoadoutProfile], the camera is a
## [CameraProfile]. A vehicle's boot is not a new kind of container and its
## turbo is not a new kind of equipment (rule 23).

## What to spawn. A [PackedScene], not a path, so a missing scene is a broken
## reference the editor shows rather than a runtime surprise.
@export var scene: PackedScene

@export_group("Seats")
## Every place somebody can be. Order is presentation only; seats are addressed
## by id.
@export var seats: Array[SeatDefinition] = []

@export_group("Handling")
@export var handling: HandlingProfile

@export_group("Fuel")
## Tank size. Zero is a vehicle that never needs fuel — a bicycle, a shopping
## trolley, or a project that does not want fuel at all (rule 31).
@export_range(0.0, 1000.0, 0.1, "or_greater") var fuel_capacity: float = 60.0

## Where it starts, as a fraction of the tank.
@export_range(0.0, 1.0, 0.01) var starting_fuel_fraction: float = 1.0

@export_group("Damage")
## How much punishment it takes. Zero leaves the vehicle indestructible, which
## is right for a set piece and wrong for a getaway car.
@export_range(0.0, 100000.0, 1.0, "or_greater") var maximum_health: float = 600.0

## Armour and per-tag resistance. The same [ResistanceProfile] a character
## wears, so a bullet meets a car the way it meets a person.
@export var resistances: ResistanceProfile

@export_group("Storage")
## The boot.
##
## [b]Named [code]inventory[/code] rather than [code]storage[/code] on
## purpose.[/b] [InventoryComponent] resolves its profile by reading a property
## called [code]inventory[/code] off whatever definition it was given — that is
## how a character's bag works, and it is what lets a container serve a person,
## a crate and a car without Inventory importing any of their types (rule 9).
## Calling the field what the plan calls it would have been a field nothing
## ever read. Null is a vehicle with nowhere to put anything.
@export var inventory: InventoryProfile

@export_group("Upgrades")
## Which upgrades can be fitted and what starts fitted.
##
## A [LoadoutProfile], because "slots that accept items and grant stat
## modifiers" is the Equipment module, and a turbo is an item with an
## [EquipmentProfile] granting a stat — not a new mechanism (rule 23). Named
## [code]loadout[/code] for the same reason [member inventory] is named that:
## it is the property [EquipmentComponent] looks for.
@export var loadout: LoadoutProfile

@export_group("Presentation")
## The camera used while driving this. Null falls back to whatever the driver
## brought with them.
@export var camera: CameraProfile

@export_group("Vocabulary")
## What kind of vehicle this is, for AI, traffic and missions:
## [code]vehicle.car[/code], [code]vehicle.police[/code].
@export var vehicle_tags: Array[StringName] = []


func get_seat(seat_id: StringName) -> SeatDefinition:
	for seat in seats:
		if seat != null and seat.id == seat_id:
			return seat
	return null


func get_driver_seat() -> SeatDefinition:
	for seat in seats:
		if seat != null and seat.is_driver():
			return seat
	return null


func get_seat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for seat in seats:
		if seat != null and seat.id != &"":
			ids.append(seat.id)
	return ids


func has_fuel_tank() -> bool:
	return fuel_capacity > 0.0


func get_starting_fuel() -> float:
	return fuel_capacity * clampf(starting_fuel_fraction, 0.0, 1.0)


func is_destructible() -> bool:
	return maximum_health > 0.0


func has_vehicle_tag(tag: StringName) -> bool:
	return vehicle_tags.has(tag)


func validate() -> ValidationResult:
	var result := super()
	if handling == null:
		result.add_error(
			&"vehicle.no_handling",
			"%s has no handling profile, so it cannot move." % get_debug_name(),
			resource_path,
			"handling"
		)
	else:
		result.merge(handling.validate())

	if seats.is_empty():
		result.add_error(
			&"vehicle.no_seats",
			"%s has nowhere for anybody to sit." % get_debug_name(),
			resource_path,
			"seats"
		)
	elif get_driver_seat() == null:
		result.add_warning(
			&"vehicle.no_driver_seat",
			(
				"%s has no driver's seat, so nobody can drive it. That is right "
				+ "for a trailer and wrong for a car."
			) % get_debug_name(),
			resource_path,
			"seats"
		)

	var seen: Array[StringName] = []
	for seat in seats:
		if seat == null:
			result.add_warning(
				&"vehicle.empty_seat_slot",
				"%s has an empty seat slot." % get_debug_name(),
				resource_path,
				"seats"
			)
			continue
		if seen.has(seat.id):
			result.add_error(
				&"vehicle.duplicate_seat",
				(
					"%s has two seats called '%s', so a save cannot tell them apart."
				) % [get_debug_name(), seat.id],
				resource_path,
				"seats"
			)
		seen.append(seat.id)
		result.merge(seat.validate())

	if scene == null:
		result.add_warning(
			&"vehicle.no_scene",
			"%s has no scene, so nothing can spawn it." % get_debug_name(),
			resource_path,
			"scene"
		)
	return result
