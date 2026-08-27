class_name VehicleFixtures
extends RefCounted
## Builders for the cars, seats and drivers the M13 suites need.
##
## Entities are assembled by hand rather than instantiated from
## [code]vehicle.tscn[/code], because most of these tests are about the
## components rather than the scene, and a fixture that needs a physics body
## cannot run the maths (rule 33). One suite drives the shipped scene, which is
## where the composition itself is the thing under test.


# --- Profiles and definitions ---------------------------------------------

## A middling car: 30 m/s, brisk but not instant, brakes stronger than drag.
static func handling(
	max_speed: float = 30.0, acceleration: float = 10.0
) -> HandlingProfile:
	var profile := HandlingProfile.new()
	profile.max_speed = max_speed
	profile.max_reverse_speed = 8.0
	profile.acceleration = acceleration
	profile.braking = 20.0
	profile.drag = 4.0
	profile.handbrake_force = 30.0
	profile.steering_rate = 1.6
	profile.steering_falloff = 0.6
	profile.minimum_steering = 0.35
	profile.steering_threshold = 0.5
	profile.fuel_per_second = 1.0
	profile.idle_fuel_fraction = 0.2
	return profile


static func seat(
	id: StringName = &"seat.driver",
	role: SeatDefinition.Role = SeatDefinition.Role.DRIVER
) -> SeatDefinition:
	var definition := SeatDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.role = role
	return definition


## Driver plus one passenger, which is the smallest interesting cabin.
static func seats(count: int = 2) -> Array[SeatDefinition]:
	var built: Array[SeatDefinition] = [seat(&"seat.driver", SeatDefinition.Role.DRIVER)]
	for index in maxi(0, count - 1):
		built.append(
			seat(StringName("seat.passenger%d" % index), SeatDefinition.Role.PASSENGER)
		)
	return built


static func definition(
	id: StringName = &"vehicle.sedan",
	seat_count: int = 2,
	fuel_capacity: float = 50.0,
	maximum_health: float = 600.0
) -> VehicleDefinition:
	var vehicle := VehicleDefinition.new()
	vehicle.id = id
	vehicle.display_name = str(id)
	vehicle.handling = handling()
	vehicle.seats = seats(seat_count)
	vehicle.fuel_capacity = fuel_capacity
	vehicle.maximum_health = maximum_health
	var tags: Array[StringName] = [&"vehicle.car"]
	vehicle.vehicle_tags = tags
	return vehicle


# --- Entities -------------------------------------------------------------

## A drivable vehicle with no physics body: seats, fuel, health and the base
## adapter, which integrates correctly and moves nothing.
static func vehicle(
	entity_name: String = "Sedan",
	vehicle_definition: VehicleDefinition = null,
	with_ai: bool = false,
	with_driver_controls: bool = false
) -> Node3D:
	var content := vehicle_definition if vehicle_definition != null else definition()

	var entity := Node3D.new()
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = StringName("%s.instance" % entity_name.to_lower())
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)

	var adapter := VehicleControllerAdapter.new()
	adapter.name = "VehicleControllerAdapter"
	entity.add_child(adapter)

	var fuel := FuelComponent.new()
	fuel.name = "FuelComponent"
	entity.add_child(fuel)

	var cabin := SeatComponent.new()
	cabin.name = "SeatComponent"
	cabin.semantic_state = state
	entity.add_child(cabin)

	var component := VehicleComponent.new()
	component.name = "VehicleComponent"
	component.vehicle_override = content
	component.adapter = adapter
	component.fuel = fuel
	component.seats = cabin
	component.health = health
	component.semantic_state = state
	component.auto_tick = false
	entity.add_child(component)

	if with_driver_controls:
		var driver := VehicleControllerComponent.new()
		driver.name = "VehicleControllerComponent"
		driver.vehicle = component
		entity.add_child(driver)

	if with_ai:
		var brain := VehicleAIDriver.new()
		brain.name = "VehicleAIDriver"
		brain.vehicle = component
		brain.auto_tick = false
		entity.add_child(brain)
	return entity


## Somebody who can get in: an identity, a state, and optionally the things
## that make possession visible.
static func occupant(
	entity_name: String = "Driver",
	with_controller: bool = false,
	with_ai: bool = false
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = StringName("%s.instance" % entity_name.to_lower())
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	if with_controller or with_ai:
		var movement := MovementComponent.new()
		movement.name = "MovementComponent"
		movement.semantic_state = state
		movement.auto_tick = false
		entity.add_child(movement)

	if with_ai:
		var brain := AIControllerComponent.new()
		brain.name = "AIControllerComponent"
		brain.movement = entity.get_node("MovementComponent")
		brain.auto_tick = false
		entity.add_child(brain)

	if with_controller:
		var controller := CharacterController.new()
		controller.name = "CharacterController"
		controller.movement = entity.get_node("MovementComponent")
		if with_ai:
			controller.ai = entity.get_node("AIControllerComponent")
		entity.add_child(controller)
	return entity


# --- Interaction ----------------------------------------------------------

## An interaction that gets you in and out of the vehicle it is attached to.
static func enter_interaction(
	seat_id: StringName = &"", toggles: bool = true
) -> InteractionDefinition:
	var interaction := InteractionDefinition.new()
	interaction.id = &"interaction.enter_vehicle"
	interaction.display_name = "Enter"
	interaction.verb = GameplayNames.VERB_ENTER
	interaction.prompt = "Get in"
	var action := EnterVehicleAction.new()
	action.seat_id = seat_id
	action.toggles = toggles
	# Tests assemble entities outside a live physics world, so moving occupants
	# to seat offsets would teleport them and break every distance assertion.
	action.move_occupant = false
	interaction.action = action
	return interaction


static func interactable(entity: Node, interactions: Array) -> InteractionComponent:
	var component := InteractionComponent.new()
	component.name = "InteractionComponent"
	var offered: Array[InteractionDefinition] = []
	offered.assign(interactions)
	component.interactions_override = offered
	component.auto_tick = false
	component.semantic_state = find(entity, SemanticState) as SemanticState
	entity.add_child(component)
	return component


static func interactor_on(entity: Node) -> InteractorComponent:
	var component := InteractorComponent.new()
	component.name = "InteractorComponent"
	component.auto_tick = false
	entity.add_child(component)
	return component


# --- Lookups --------------------------------------------------------------

## Runs [method FrameworkComponent.initialize] over an assembled entity, the
## way a [DefinitionBinder] would.
##
## [b]The definition falls back to the vehicle's own.[/b] [SeatComponent] and
## [FuelComponent] read the [i]entity[/i] definition, not a sibling's export —
## asking the vehicle component would be exactly the sibling coupling rule 9
## forbids. In a scene the binder hands all three the same
## [VehicleDefinition]; without this fallback every fixture would have to pass
## it by hand and one that forgot would get a car with no seats and no tank,
## which is how these tests first failed.
static func assemble(
	entity: Node, core: Node = null, entity_definition: FrameworkDefinition = null
) -> void:
	var definition := entity_definition
	if definition == null:
		var component := vehicle_of(entity)
		if component != null:
			definition = component.vehicle_override
	var context := EntityContext.create(entity, definition, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


static func vehicle_of(entity: Node) -> VehicleComponent:
	return find(entity, VehicleComponent) as VehicleComponent


static func seats_of(entity: Node) -> SeatComponent:
	return find(entity, SeatComponent) as SeatComponent


static func fuel_of(entity: Node) -> FuelComponent:
	return find(entity, FuelComponent) as FuelComponent


static func adapter_of(entity: Node) -> VehicleControllerAdapter:
	return find(entity, VehicleControllerAdapter) as VehicleControllerAdapter
