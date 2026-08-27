class_name EnterVehicleAction
extends InteractionAction
## Gets in and gets out. The VehicleInteractionAdapter of Implementation
## Plan 39.
##
## An [InteractionAction], so a car door is opened through exactly the pipeline
## a house door is — the reach check, the requirements, the hold duration and
## the prompt are all M5's, and Vehicles adds none of its own (rule 23).
##
## [b]Possession is a handover, not an identity change.[/b] Nobody is
## reparented, nothing is hidden, no entity is destroyed and rebuilt. The
## character's controller lets go of its input context and the vehicle's takes
## one; the character's AI stops thinking and the vehicle's starts. Getting out
## is exactly the reverse, and neither side has to know what the other did
## (Implementation Plan 22).
##
## It lives in [code]vehicles/[/code] rather than [code]interaction/[/code],
## which is the direction that keeps both modules deletable (rule 10).

## Which seat to take. Blank takes the best free one, driver's seat first.
@export var seat_id: StringName = &""

## Whether pressing this while already aboard gets you out. On is one prompt
## for both, which is what most projects want; off makes leaving a separate
## interaction.
@export var toggles: bool = true

## Move the occupant to the seat, and out to the exit position on leaving.
## Off leaves placement to a project's own presentation.
@export var move_occupant: bool = true


func can_execute(context: InteractionContext) -> FrameworkResult:
	var seats := _find_seats(context)
	if seats == null:
		return FrameworkResult.fail(
			&"vehicle.no_seats", "There is nothing to get into here."
		)
	if seats.contains(context.interactor):
		if toggles:
			return FrameworkResult.ok(seats)
		return FrameworkResult.fail(&"vehicle.already_aboard", "You are already aboard.")
	if seat_id != &"":
		return seats.can_enter(context.interactor, seat_id)
	if seats.find_free_seat(context.interactor) == null:
		return FrameworkResult.fail(&"seat.full", "There is nowhere to sit.")
	return FrameworkResult.ok(seats)


func execute(context: InteractionContext) -> FrameworkResult:
	var seats := _find_seats(context)
	if seats == null:
		return FrameworkResult.fail(
			&"vehicle.no_seats", "There is nothing to get into here."
		)
	if seats.contains(context.interactor):
		if not toggles:
			return FrameworkResult.fail(
				&"vehicle.already_aboard", "You are already aboard."
			)
		return _leave(context, seats)
	return _board(context, seats)


# --- Boarding -------------------------------------------------------------

func _board(context: InteractionContext, seats: SeatComponent) -> FrameworkResult:
	var seated := seats.enter(context.interactor, seat_id)
	if seated.is_err():
		return seated
	var seat: SeatDefinition = seated.payload

	# Order matters. The character lets go first, so that at no point are two
	# controllers holding contexts for the same player -- which would leave the
	# stack one deep for the rest of the session.
	_release_character(context.interactor)
	if seat.controls_vehicle():
		_take_vehicle(context.target)
	if move_occupant:
		_place(context.interactor, seats, seat)
	return FrameworkResult.ok(seat)


func _leave(context: InteractionContext, seats: SeatComponent) -> FrameworkResult:
	var seat_taken := seats.get_seat_of(context.interactor)
	var exit_position := seats.get_exit_position(seat_taken)
	var left := seats.exit(context.interactor)
	if left.is_err():
		return left
	var seat: SeatDefinition = left.payload

	if seat != null and seat.controls_vehicle():
		_release_vehicle(context.target)
	_take_character(context.interactor)
	if move_occupant:
		_move_to(context.interactor, exit_position)
	return FrameworkResult.ok(seat)


# --- Handover -------------------------------------------------------------
#
# Each of these is "if the component is there, tell it". A character with no
# controller is an NPC and boards perfectly well; a vehicle with no controller
# is traffic and is driven by its AI. Every one of these being optional is what
# makes the pair of modules removable (rule 31).

func _release_character(occupant: Node) -> void:
	for component in DefinitionBinder.collect_components(occupant):
		if component is CharacterController:
			var controller := component as CharacterController
			if controller.is_controlling():
				controller.release_control()
		elif component is AIControllerComponent:
			(component as AIControllerComponent).set_active(false)
		elif component is MovementComponent:
			# A character walking as they get in keeps walking otherwise: the
			# last intent they were given is still set.
			(component as MovementComponent).stop()


func _take_character(occupant: Node) -> void:
	var had_controller := false
	for component in DefinitionBinder.collect_components(occupant):
		if component is CharacterController:
			had_controller = true
			(component as CharacterController).take_control()
	if had_controller:
		return
	for component in DefinitionBinder.collect_components(occupant):
		if component is AIControllerComponent:
			(component as AIControllerComponent).set_active(true)


func _take_vehicle(vehicle: Node) -> void:
	for component in DefinitionBinder.collect_components(vehicle):
		if component is VehicleControllerComponent:
			(component as VehicleControllerComponent).take_control()
		elif component is VehicleAIDriver:
			(component as VehicleAIDriver).set_active(false)


func _release_vehicle(vehicle: Node) -> void:
	for component in DefinitionBinder.collect_components(vehicle):
		if component is VehicleControllerComponent:
			var driver := component as VehicleControllerComponent
			if driver.is_controlling():
				driver.release_control()
		elif component is VehicleAIDriver:
			(component as VehicleAIDriver).set_active(true)


# --- Placement ------------------------------------------------------------

func _place(occupant: Node, seats: SeatComponent, seat: SeatDefinition) -> void:
	var vehicle := seats.get_entity() as Node3D
	if vehicle == null or not vehicle.is_inside_tree():
		return
	_move_to(occupant, vehicle.global_transform * seat.offset)


func _move_to(occupant: Node, position: Vector3) -> void:
	var spatial := occupant as Node3D
	if spatial != null and spatial.is_inside_tree():
		spatial.global_position = position


func _find_seats(context: InteractionContext) -> SeatComponent:
	if context == null or context.target == null:
		return null
	for component in DefinitionBinder.collect_components(context.target):
		if component is SeatComponent:
			return component as SeatComponent
	return null


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if seat_id == &"" and not toggles:
		result.add_info(
			&"enter_vehicle.no_exit",
			(
				"This action takes any free seat and does not toggle, so nothing "
				+ "it is attached to can be used to get out again."
			),
			resource_path,
			"toggles"
		)
	return result
