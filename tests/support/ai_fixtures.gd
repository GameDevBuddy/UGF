class_name AIFixtures
extends RefCounted
## Builders for the civilians, guards and combatants the M7 suites need.
##
## The exit gate for this milestone is that those three are one entity with
## three role resources, so these builders deliberately share [method npc]:
## if a role needed its own construction path, the gate would not be met.


# --- Profiles and roles ---------------------------------------------------

static func perception_profile(
	sight_range: float = 20.0,
	sight_angle: float = 110.0,
	notice_time: float = 0.0,
	memory_duration: float = 8.0
) -> PerceptionProfile:
	var profile := PerceptionProfile.new()
	profile.sight_range = sight_range
	profile.sight_angle = sight_angle
	profile.notice_time = notice_time
	profile.memory_duration = memory_duration
	profile.scan_interval = 0.2
	profile.hearing_range = 15.0
	profile.eye_height = 0.0
	profile.requires_line_of_sight = true
	return profile


static func brain(
	stance: RoleBrain.Stance = RoleBrain.Stance.CAUTIOUS,
	preferred_range: float = 0.0
) -> RoleBrain:
	var thinking := RoleBrain.new()
	thinking.stance = stance
	thinking.preferred_range = preferred_range
	thinking.investigate_time = 2.0
	thinking.wander_pause = 1.0
	return thinking


## The three roles of the exit gate. One builder, three configurations.
static func role(
	id: StringName,
	stance: RoleBrain.Stance,
	wander_radius: float = 0.0,
	threat: float = 1.0
) -> NPCRoleDefinition:
	var definition := NPCRoleDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.perception = perception_profile()
	definition.brain = brain(stance)
	definition.threat = threat
	definition.wander_radius = wander_radius
	return definition


static func civilian() -> NPCRoleDefinition:
	return role(&"role.civilian", RoleBrain.Stance.PASSIVE, 5.0, 0.5)


static func guard() -> NPCRoleDefinition:
	return role(&"role.guard", RoleBrain.Stance.CAUTIOUS, 3.0, 3.0)


static func combatant() -> NPCRoleDefinition:
	return role(&"role.combatant", RoleBrain.Stance.AGGRESSIVE, 0.0, 5.0)


# --- Entities -------------------------------------------------------------

## An NPC. Every role is built from this one call, which is the exit gate
## stated as code: what differs between a civilian and a guard is the role
## resource, not the composition.
static func npc(
	entity_name: String = "NPC",
	position: Vector3 = Vector3.ZERO,
	npc_role: NPCRoleDefinition = null,
	armed: bool = true
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name
	entity.position = position

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var mark := Perceivable.new()
	mark.name = "Perceivable"
	mark.semantic_state = state
	mark.threat = npc_role.threat if npc_role != null else 1.0
	entity.add_child(mark)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)

	var movement := MovementComponent.new()
	movement.name = "MovementComponent"
	movement.profile_override = _movement_profile()
	movement.semantic_state = state
	movement.auto_tick = false
	entity.add_child(movement)

	var navigation := NavigationAdapter.new()
	navigation.name = "NavigationAdapter"
	entity.add_child(navigation)

	var perception := PerceptionComponent.new()
	perception.name = "PerceptionComponent"
	perception.perceivable = mark
	perception.auto_tick = false
	entity.add_child(perception)

	if armed:
		var weapon := WeaponComponent.new()
		weapon.name = "WeaponComponent"
		weapon.profile_override = CombatFixtures.sword(25.0)
		weapon.auto_tick = false
		entity.add_child(weapon)

		var combat := CombatComponent.new()
		combat.name = "CombatComponent"
		combat.profile_override = CombatFixtures.combat_profile()
		combat.weapon = weapon
		combat.auto_tick = false
		entity.add_child(combat)

	var controller := AIControllerComponent.new()
	controller.name = "AIControllerComponent"
	controller.role_override = npc_role
	controller.auto_tick = false
	controller.think_interval = 0.0
	entity.add_child(controller)
	return entity


## Something an NPC can notice: a player, an intruder, a rival.
static func actor(
	entity_name: String = "Intruder",
	position: Vector3 = Vector3.ZERO,
	threat: float = 4.0
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name
	entity.position = position

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var mark := Perceivable.new()
	mark.name = "Perceivable"
	mark.semantic_state = state
	mark.threat = threat
	mark.focus_height = 0.0
	var concealing: Array[StringName] = [GameplayNames.STATE_CROUCHING]
	mark.concealing_states = concealing
	entity.add_child(mark)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)
	return entity


static func assemble(entity: Node, definition: FrameworkDefinition = null) -> void:
	var context := EntityContext.create(entity, definition)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


# --- Lookups --------------------------------------------------------------

static func controller_of(entity: Node) -> AIControllerComponent:
	return _find(entity, AIControllerComponent) as AIControllerComponent


static func perception_of(entity: Node) -> PerceptionComponent:
	return _find(entity, PerceptionComponent) as PerceptionComponent


static func perceivable_of(entity: Node) -> Perceivable:
	return _find(entity, Perceivable) as Perceivable


static func movement_of(entity: Node) -> MovementComponent:
	return _find(entity, MovementComponent) as MovementComponent


static func navigation_of(entity: Node) -> NavigationAdapter:
	return _find(entity, NavigationAdapter) as NavigationAdapter


static func combat_of(entity: Node) -> CombatComponent:
	return _find(entity, CombatComponent) as CombatComponent


static func health_of(entity: Node) -> HealthComponent:
	return _find(entity, HealthComponent) as HealthComponent


static func state_of(entity: Node) -> SemanticState:
	return _find(entity, SemanticState) as SemanticState


static func _movement_profile() -> MovementProfile:
	var profile := MovementProfile.new()
	profile.walk_speed = 4.0
	profile.sprint_speed = 7.0
	profile.acceleration = 40.0
	profile.deceleration = 55.0
	return profile


static func _find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
