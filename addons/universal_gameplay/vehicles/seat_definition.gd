class_name SeatDefinition
extends Resource
## One place in a vehicle somebody can be.
##
## [b]Role, not class.[/b] Driver, passenger, turret and cargo differ in what
## the occupant may do and which input context they get, and both are data
## (Implementation Plan 22). A gun truck is a vehicle with one driver seat and
## one turret seat, not a GunTruck.

enum Role { DRIVER, PASSENGER, TURRET, CARGO }


## Stable id, so a save records which seat somebody was in rather than an index
## into an array that a later version reorders (rule 32).
@export var id: StringName = &""

@export var display_name: String = ""

@export var role: Role = Role.PASSENGER

@export_group("Placement")
## Where the occupant sits, relative to the vehicle. Presentation reads this;
## nothing in the framework requires it to be accurate.
@export var offset: Vector3 = Vector3.ZERO

## Where the occupant is put down on getting out, relative to the vehicle.
## Doors are on the left in this default, which is a guess a project overrides.
@export var exit_offset: Vector3 = Vector3(-1.8, 0.0, 0.0)

@export_group("Availability")
## Whether the occupant is exposed to damage and can be seen and shot. An open
## turret is; a sealed cabin is not.
@export var exposed: bool = false

## Whether this seat can be entered at all right now. A project turns it off
## for a locked door or a crushed side.
@export var enabled: bool = true

## Extra requirements to sit here: a licence, a rank, a faction. Reuses M5's
## requirement resources rather than inventing a second vocabulary (rule 23).
@export var requirements: Array[InteractionRequirement] = []


func is_driver() -> bool:
	return role == Role.DRIVER


## Whether the occupant of this seat should be given control of the vehicle.
## Only the driver drives; a turret gunner aims their own thing.
func controls_vehicle() -> bool:
	return role == Role.DRIVER


## The standard input context this seat implies. Driving and riding are the two
## the framework names (Implementation Plan 24); a turret is a passenger who
## also has a weapon, which is the weapon's business and not the seat's.
func get_input_context_id() -> StringName:
	if is_driver():
		return GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER
	return GameplayNames.INPUT_CONTEXT_VEHICLE_PASSENGER


func get_debug_name() -> String:
	if not display_name.is_empty():
		return "%s (%s)" % [display_name, id]
	return str(id) if id != &"" else "<unnamed seat>"


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if id == &"":
		result.add_error(
			&"seat.no_id",
			"A seat with no id cannot be saved or referred to.",
			resource_path,
			"id"
		)
	if is_driver() and not enabled:
		result.add_warning(
			&"seat.disabled_driver",
			"%s is the driver's seat and is disabled, so nobody can drive." % get_debug_name(),
			resource_path,
			"enabled"
		)
	for requirement in requirements:
		if requirement != null:
			result.merge(requirement.validate())
	return result
