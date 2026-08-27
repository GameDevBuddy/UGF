extends FrameworkTestCase
## Covers the shipped character.tscn.
##
## The other M2 suites test the components in isolation, which proves they
## work and proves nothing about whether the scene wires them together
## correctly. A composition-first framework (rule 3) has to test the
## composition, or the exported NodePaths in a .tscn are the one part of the
## design nobody ever checks -- and a mis-wired export fails silently, as a
## character that simply never animates.

const CHARACTER_SCENE: String = (
	"res://addons/universal_gameplay/character/character.tscn"
)

var definition: CharacterDefinition = null


func before_each() -> void:
	var movement_profile := MovementProfile.new()
	movement_profile.walk_speed = 4.0
	movement_profile.sprint_speed = 8.0

	var camera_profile := CameraProfile.new()
	camera_profile.sensitivity = 0.01

	var animation_profile := AnimationProfile.new()
	animation_profile.speed_parameter = "parameters/locomotion/blend_position"

	definition = CharacterDefinition.new()
	definition.id = &"character.scene_test"
	definition.display_name = "Scene Test"
	definition.movement = movement_profile
	definition.camera = camera_profile
	definition.animation = animation_profile


## Instantiates the scene with its definition already set, then puts it in the
## tree so the binder's own bind_on_ready path is what runs.
func _spawn() -> Node:
	var scene: PackedScene = load(CHARACTER_SCENE)
	var character := scene.instantiate()
	var binder := character.get_node("DefinitionBinder") as DefinitionBinder
	binder.definition = definition
	add_test_node(character)
	return character


func test_the_module_points_at_a_scene_that_exists() -> void:
	var module: FrameworkModule = load(
		"res://addons/universal_gameplay/character/character_module.gd"
	).new()
	assert_eq(module.CHARACTER_SCENE, CHARACTER_SCENE)
	assert_true(ResourceLoader.exists(CHARACTER_SCENE))


func test_the_root_is_a_character_body() -> void:
	var character := _spawn()
	assert_true(character is CharacterBody3D)


func test_the_scene_binds_itself_on_entering_the_tree() -> void:
	var character := _spawn()
	var binder := character.get_node("DefinitionBinder") as DefinitionBinder
	assert_true(binder.is_bound())
	assert_eq(binder.get_definition(), definition)


func test_it_is_an_entity_root() -> void:
	# A character seated in a vehicle must not have its components initialised
	# by the vehicle's binder.
	var character := _spawn()
	assert_true(DefinitionBinder.is_entity_root(character))


func test_it_carries_the_M1_entity_components() -> void:
	var character := _spawn()
	assert_not_null(character.get_node_or_null("PersistentIdentity"))
	assert_not_null(character.get_node_or_null("SemanticState"))


func test_it_has_a_save_identity() -> void:
	var character := _spawn()
	var identity := character.get_node("PersistentIdentity") as PersistentIdentity
	assert_true(identity.is_saveable())
	assert_ne(identity.get_persistent_id(), &"")


func test_the_generated_id_uses_the_definition_prefix() -> void:
	var character := _spawn()
	var identity := character.get_node("PersistentIdentity") as PersistentIdentity
	assert_true(str(identity.get_persistent_id()).begins_with("character.scene_test"))


# --- Wiring ---------------------------------------------------------------

func test_movement_is_configured_from_the_definition() -> void:
	var character := _spawn()
	var movement := character.get_node("MovementComponent") as MovementComponent
	assert_eq(movement.get_profile(), definition.movement)


func test_movement_drives_the_scene_root() -> void:
	var character := _spawn()
	var movement := character.get_node("MovementComponent") as MovementComponent
	assert_eq(movement.body, character, "the body defaulted to the entity root")


func test_movement_is_wired_to_the_semantic_state() -> void:
	# The wiring a mis-set NodePath would break silently: stance would still
	# be correct, and nothing observing the tags would ever hear about it.
	var character := _spawn()
	var movement := character.get_node("MovementComponent") as MovementComponent
	var state := character.get_node("SemanticState") as SemanticState
	assert_eq(movement.semantic_state, state)


func test_the_camera_rig_is_wired_end_to_end() -> void:
	var character := _spawn()
	var camera := character.get_node("CameraAdapter") as CameraAdapter
	assert_eq(camera.yaw_pivot, character.get_node("CameraYaw"))
	assert_eq(camera.pitch_pivot, character.get_node("CameraYaw/CameraPitch"))
	assert_eq(camera.camera, character.get_node("CameraYaw/CameraPitch/Camera3D"))
	assert_eq(camera.get_profile(), definition.camera)


func test_the_animation_adapter_observes_the_mover() -> void:
	var character := _spawn()
	var animation := character.get_node("AnimationAdapter") as AnimationAdapter
	assert_eq(animation.movement, character.get_node("MovementComponent"))
	assert_eq(animation.get_profile(), definition.animation)


func test_the_controller_is_wired_to_movement_and_camera() -> void:
	var character := _spawn()
	var controller := character.get_node("CharacterController") as CharacterController
	assert_eq(controller.movement, character.get_node("MovementComponent"))
	assert_eq(controller.camera, character.get_node("CameraAdapter"))


func test_the_controller_is_wired_to_the_interactor() -> void:
	# Another silent one: the interact button would do nothing at all, and
	# every other thing the character does would still work.
	var character := _spawn()
	var controller := character.get_node("CharacterController") as CharacterController
	assert_eq(controller.interactor, character.get_node("InteractorComponent"))


func test_the_controller_is_wired_to_combat() -> void:
	var character := _spawn()
	var controller := character.get_node("CharacterController") as CharacterController
	assert_eq(controller.combat, character.get_node("CombatComponent"))


func test_combat_is_wired_to_the_weapon_and_the_camera() -> void:
	# Aim comes off the camera rather than the body, which is what makes a
	# shot go where the player is looking rather than where their feet point.
	var character := _spawn()
	var combat := character.get_node("CombatComponent") as CombatComponent
	assert_eq(combat.weapon, character.get_node("WeaponComponent"))
	assert_eq(combat.semantic_state, character.get_node("SemanticState"))
	assert_eq(combat.aim, character.get_node("CameraYaw/CameraPitch/Camera3D"))


func test_the_weapon_is_wired_to_the_semantic_state() -> void:
	var character := _spawn()
	var weapon := character.get_node("WeaponComponent") as WeaponComponent
	assert_eq(weapon.semantic_state, character.get_node("SemanticState"))


func test_the_controller_is_wired_to_the_ai() -> void:
	var character := _spawn()
	var controller := character.get_node("CharacterController") as CharacterController
	assert_eq(controller.ai, character.get_node("AIControllerComponent"))


func test_the_ai_is_wired_to_every_capability_it_drives() -> void:
	var character := _spawn()
	var ai := character.get_node("AIControllerComponent") as AIControllerComponent
	assert_eq(ai.perception, character.get_node("PerceptionComponent"))
	assert_eq(ai.movement, character.get_node("MovementComponent"))
	assert_eq(ai.navigation, character.get_node("NavigationAdapter"))
	assert_eq(ai.combat, character.get_node("CombatComponent"))
	assert_eq(ai.interactor, character.get_node("InteractorComponent"))
	assert_eq(ai.semantic_state, character.get_node("SemanticState"))


func test_the_character_is_something_an_npc_can_notice() -> void:
	var character := _spawn()
	assert_true(character.is_in_group(GameplayNames.GROUP_PERCEIVABLE))


func test_crouching_conceals_the_character() -> void:
	# Wired in the scene rather than in code, so stealth is one exported array
	# a project can change without touching the framework.
	var character := _spawn()
	var mark := character.get_node("Perceivable") as Perceivable
	assert_almost_eq(mark.get_visibility(), 1.0)
	(character.get_node("SemanticState") as SemanticState).add_state(
		GameplayNames.STATE_CROUCHING
	)
	assert_true(mark.get_visibility() < 1.0)


func test_perception_looks_from_the_camera_pivot() -> void:
	var character := _spawn()
	var perception := character.get_node("PerceptionComponent") as PerceptionComponent
	assert_eq(perception.eyes, character.get_node("CameraYaw"))
	assert_eq(perception.perceivable, character.get_node("Perceivable"))


func test_the_dialogue_adapter_is_wired_to_the_conversation() -> void:
	var character := _spawn()
	var adapter := character.get_node("DialogueEventAdapter") as DialogueEventAdapter
	assert_eq(adapter.dialogue, character.get_node("DialogueComponent"))


func test_a_character_with_no_dialogue_simply_has_nothing_to_say() -> void:
	var character := _spawn()
	var talk := character.get_node("DialogueComponent") as DialogueComponent
	assert_null(talk.get_dialogue())
	assert_false(talk.can_talk())


func test_the_faction_adapter_is_wired_to_the_ai() -> void:
	var character := _spawn()
	var adapter := character.get_node("FactionAIAdapter") as FactionAIAdapter
	assert_eq(adapter.controller, character.get_node("AIControllerComponent"))


func test_a_character_with_no_allegiance_still_fights_everything() -> void:
	# The shipped scene carries a faction component that most content leaves
	# blank; it must not turn every NPC pacifist (rule 31).
	var character := _spawn()
	var ai := character.get_node("AIControllerComponent") as AIControllerComponent
	var stranger := add_test_node(Node3D.new())
	assert_true(ai.get_hostility_provider().is_hostile(character, stranger))


func test_a_character_with_no_role_thinks_about_nothing() -> void:
	var character := _spawn()
	var ai := character.get_node("AIControllerComponent") as AIControllerComponent
	assert_null(ai.get_role())
	assert_null(ai.get_brain())


func test_a_character_with_no_combat_profile_simply_cannot_attack() -> void:
	var character := _spawn()
	var combat := character.get_node("CombatComponent") as CombatComponent
	assert_err(combat.attack(), &"combat.no_attack")


func test_the_interactor_is_wired_to_the_semantic_state() -> void:
	var character := _spawn()
	var interactor := character.get_node("InteractorComponent") as InteractorComponent
	assert_eq(interactor.semantic_state, character.get_node("SemanticState"))
	assert_not_null(interactor.get_profile())


func test_the_scene_does_not_take_control_by_itself() -> void:
	# Every NPC in a game is this scene. Taking control on spawn would make
	# the first one instantiated the player.
	var character := _spawn()
	var controller := character.get_node("CharacterController") as CharacterController
	assert_false(controller.control_on_bind)
	assert_false(controller.is_controlling())


func test_possession_decides_which_camera_the_viewport_uses() -> void:
	# Every NPC in a game is this scene, so the scene cannot decide. Godot
	# makes the first camera in a viewport current on its own; what the
	# framework controls is which one wins after that.
	var first := _spawn()
	var second := _spawn()
	var second_adapter := second.get_node("CameraAdapter") as CameraAdapter

	assert_true(second_adapter.make_current())
	assert_true(second_adapter.is_current())
	assert_false(
		(first.get_node("CameraAdapter") as CameraAdapter).is_current(),
		"and the one that spawned first gave it up"
	)


# --- Node order ------------------------------------------------------------

func test_components_are_still_ticking_after_their_own_ready_ran() -> void:
	# Godot readies children in tree order, so a binder placed above these
	# nodes initialises them before their _ready runs. A component that
	# disabled its own processing there would be switched off by the binder
	# having done its job -- silently, and only for some node orders.
	var character := _spawn()
	var movement := character.get_node("MovementComponent") as MovementComponent
	assert_true(movement.is_initialized())
	assert_true(movement.is_physics_processing(), "it has a body, so it ticks")


func test_binding_survives_the_binder_being_moved_to_the_top() -> void:
	var scene: PackedScene = load(CHARACTER_SCENE)
	var character := scene.instantiate()
	var binder := character.get_node("DefinitionBinder") as DefinitionBinder
	binder.definition = definition
	character.move_child(binder, 0)
	add_test_node(character)

	var movement := character.get_node("MovementComponent") as MovementComponent
	assert_true(binder.is_bound())
	assert_true(movement.is_initialized())
	assert_true(movement.is_physics_processing(), "and it is not switched off")


# --- Rule 10: the parts are removable -------------------------------------

func test_a_character_with_its_controller_removed_is_an_npc() -> void:
	# Delete the controller and the character is an NPC; add it back and it is
	# the player. Nothing else in the entity changes.
	var scene: PackedScene = load(CHARACTER_SCENE)
	var character := scene.instantiate()
	var binder := character.get_node("DefinitionBinder") as DefinitionBinder
	binder.definition = definition
	var controller := character.get_node("CharacterController")
	character.remove_child(controller)
	controller.free()
	add_test_node(character)

	var movement := character.get_node("MovementComponent") as MovementComponent
	assert_true(binder.is_bound())
	movement.set_move_direction(Vector3.FORWARD)
	movement.set_sprinting(true)
	assert_eq(movement.get_profile(), definition.movement, "and it still moves")


func test_a_character_binds_with_no_definition_at_all() -> void:
	# An authored prop configured entirely in the inspector needs no content
	# behind it, and must not fail to load for the lack of it.
	var scene: PackedScene = load(CHARACTER_SCENE)
	var character := scene.instantiate()
	add_test_node(character)
	var binder := character.get_node("DefinitionBinder") as DefinitionBinder
	var movement := character.get_node("MovementComponent") as MovementComponent

	assert_true(binder.is_bound())
	assert_null(binder.get_definition())
	assert_null(movement.get_profile(), "no profile, so it does not move")
