class_name CharacterController
extends FrameworkComponent
## Turns player input into movement commands. One of several possible drivers.
##
## [b]This component is not required for a character to move.[/b] That is the
## whole design. It reads an [InputRouter] and calls [method
## MovementComponent.set_move_input], [method MovementComponent.set_sprinting]
## and [method MovementComponent.request_jump] -- the same public methods an AI
## brain will call in M7, with no privileged path and nothing an AI would have
## to work around (rule 14). Delete this component from a character scene and
## the character is an NPC; add it back and it is the player. Nothing else in
## the entity changes.
##
## [b]Control is explicit.[/b] Taking control pushes the character's input
## context; releasing it removes that context again, restoring whatever was
## beneath. That is what makes possession work: entering a vehicle releases the
## character and the vehicle takes control, and leaving it puts the character's
## context back without either of them tracking what the other did
## (Implementation Plan 22).
##
## With no Input module installed, the controller is inert and the character
## still moves under any other driver. A missing optional module is a valid
## state, not an error (rule 31).

## Emitted when this controller takes or releases control.
signal control_changed(controlling: bool)

## The mover this controller drives. Wired at composition time (rule 20).
@export var movement: MovementComponent

## Optional camera, used to make movement relative to the view and to receive
## look input. Absent, movement is relative to the entity itself.
@export var camera: CameraAdapter

## Input context pushed while controlling. Takes precedence over the
## definition's; blank falls back to the standard on-foot context.
@export var context_override: InputContext

## Take control as soon as the entity is bound. The player's character sets
## this; every NPC leaves it off.
@export var control_on_bind: bool = false

## Forward mouse motion to the camera while controlling.
@export var mouse_look: bool = true

## Optional interactor, so the interact button reaches the same pipeline an AI
## uses. Absent -- a project with no Interaction module, or a character that
## never uses anything -- the button does nothing and everything else works
## (rule 31).
@export var interactor: InteractorComponent

## Optional combat, so the attack and reload buttons reach the same commands an
## AI issues. Absent, the buttons do nothing and everything else works.
@export var combat: CombatComponent

## Optional AI, switched off while a player is driving and back on when they
## let go. That handoff is the whole of possession from the AI's side: an NPC
## the player takes over stops thinking, and gets its own mind back when they
## leave (Implementation Plan 22).
@export var ai: AIControllerComponent

var _router: InputRouter = null
var _input_context: InputContext = null
var _controlling: bool = false


func _ready() -> void:
	# Recomputed rather than disabled: a binder above this node in the scene
	# may already have initialised it and taken control (see
	# MovementComponent for the full note).
	_set_ticking(_controlling)


func initialize(entity_context: EntityContext) -> void:
	super(entity_context)
	# An injected router wins: split-screen hands each controller its own, and
	# resolving over the top of one would quietly put both players back on the
	# same router.
	if _router == null:
		_router = _resolve_router()
	_input_context = _resolve_input_context()
	if control_on_bind:
		take_control()


func _exit_tree() -> void:
	if _controlling:
		release_control()


# --- Possession -----------------------------------------------------------

## Takes control: pushes this character's input context and starts driving.
func take_control() -> FrameworkResult:
	if _controlling:
		return FrameworkResult.fail(
			&"controller.already_controlling", "This controller already has control."
		)
	if movement == null:
		return FrameworkResult.fail(
			&"controller.no_movement",
			"CharacterController has no MovementComponent to drive."
		)
	if _router == null:
		_router = _resolve_router()
	if _router == null:
		return FrameworkResult.fail(
			&"controller.no_input_router",
			"No input service is available, so there is nothing to take control from."
		)

	if _input_context == null:
		_input_context = _resolve_input_context()
	var pushed := _router.push_context(_input_context)
	if pushed.is_err():
		return pushed

	_controlling = true
	_set_ticking(true)
	if ai != null:
		ai.set_active(false)
	if camera != null:
		# Taking control is what decides whose view the player sees. The scene
		# does not mark its camera current on spawn, because every NPC is built
		# from that same scene.
		camera.make_current()
	control_changed.emit(true)
	return FrameworkResult.ok(self)


## Releases control, removing this character's context from the stack and
## clearing any movement it was holding.
##
## The clear matters: without it a character handing over control mid-stride
## keeps walking, because the last intent it was given is still set.
func release_control() -> FrameworkResult:
	if not _controlling:
		return FrameworkResult.fail(
			&"controller.not_controlling", "This controller does not have control."
		)
	_controlling = false
	_set_ticking(false)
	if _router != null and _input_context != null:
		# By instance, not by id: two characters both on foot push contexts
		# with the same id, and removing by id would take whichever pushed
		# last rather than this one.
		_router.remove_context_instance(_input_context)
	if movement != null:
		movement.stop()
		movement.set_crouching(false)
	if ai != null:
		ai.set_active(true)
	control_changed.emit(false)
	return FrameworkResult.ok(self)


func is_controlling() -> bool:
	return _controlling


# --- Driving --------------------------------------------------------------

func _process(delta: float) -> void:
	drive(delta)


## Reads input once and issues the resulting commands.
##
## Public and side-effect-free beyond the commands it issues, so a test can
## step it deterministically without a frame.
func drive(delta: float) -> void:
	if not _controlling or _router == null or movement == null:
		return

	if _router.is_control_suppressed():
		# A menu or a cutscene is up. Release what is held rather than leaving
		# the character frozen mid-stride holding the last input it saw.
		movement.stop()
		if interactor != null:
			interactor.cancel(&"control_suppressed")
		if combat != null:
			combat.release()
		return

	var basis := camera.get_movement_basis() if camera != null else _get_entity_basis()
	movement.set_move_input(_router.get_move_vector(), basis)
	movement.set_sprinting(_router.is_pressed(GameplayNames.ACTION_SPRINT))
	movement.set_crouching(_router.is_pressed(GameplayNames.ACTION_CROUCH))
	if _router.was_just_pressed(GameplayNames.ACTION_JUMP):
		movement.request_jump()

	_drive_interaction()
	_drive_combat()

	if camera != null:
		camera.tick(delta)


## Interact is a press to start and a release to give up.
##
## Holding is what a timed interaction is, and treating the release as a cancel
## is the whole of it -- there is no separate "hold" input. An interaction the
## designer marked uninterruptible ignores the release and finishes.
func _drive_interaction() -> void:
	if interactor == null:
		return
	if _router.was_just_pressed(GameplayNames.ACTION_INTERACT):
		interactor.interact()
	elif interactor.is_busy() and not _router.is_pressed(GameplayNames.ACTION_INTERACT):
		interactor.cancel(&"released")


## Attack is a press to start and a release to stop, which is what makes one
## button serve a single-shot rifle, an automatic and a held melee wind-up
## without the controller knowing which it is holding.
func _drive_combat() -> void:
	if combat == null:
		return
	if _router.was_just_pressed(GameplayNames.ACTION_ATTACK):
		combat.hold()
	elif combat.is_holding() and not _router.is_pressed(GameplayNames.ACTION_ATTACK):
		combat.release()

	if _router.was_just_pressed(GameplayNames.ACTION_ATTACK_SECONDARY):
		combat.attack(true)
	if _router.was_just_pressed(GameplayNames.ACTION_RELOAD) and combat.weapon != null:
		combat.weapon.reload()


## Applies look input to the camera. Mouse motion arrives here from
## [method Node._unhandled_input]; a gamepad look stick, a touch drag or a
## test calls it directly.
##
## Look is not an InputMap action because it is not one: mouse motion is a
## relative delta with no pressed state, and forcing it through the action
## router would mean inventing four actions to describe one vector.
func add_look(look: Vector2) -> void:
	if not _controlling or camera == null:
		return
	if _router != null and _router.is_control_suppressed():
		return
	camera.add_look(look)


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_look or not _controlling:
		return
	if event is InputEventMouseMotion:
		add_look((event as InputEventMouseMotion).relative)


# --- Queries --------------------------------------------------------------

func get_router() -> InputRouter:
	return _router


func get_input_context() -> InputContext:
	return _input_context


## Injects the router directly, bypassing service lookup.
##
## For split-screen, where each player's controller needs its own router, and
## for tests. Takes effect on the next [method take_control].
func set_router(router: InputRouter) -> void:
	if _controlling:
		release_control()
	_router = router


# --- Internals ------------------------------------------------------------

func _set_ticking(active: bool) -> void:
	set_process(active)
	set_process_unhandled_input(active and mouse_look)


## Finds the input service through the context's core rather than an autoload,
## so a controller registered against a throwaway core in a test finds that
## core's router and not the game's (rule 20).
func _resolve_router() -> InputRouter:
	var context := get_context()
	if context == null or context.core == null:
		return null
	if not context.core.has_method("get_service"):
		return null
	return context.core.call("get_service", GameplayNames.SERVICE_INPUT) as InputRouter


func _resolve_input_context() -> InputContext:
	if context_override != null:
		return context_override
	var definition := get_definition()
	if definition != null and "input_context" in definition:
		var candidate: Variant = definition.get("input_context")
		if candidate is InputContext:
			return candidate as InputContext
	return InputContexts.on_foot()


## Movement basis when there is no camera: the entity's own facing, with pitch
## and roll discarded so a tilted body does not steer into the ground.
##
## Falls back to the local rotation outside the tree, because
## [member Node3D.global_rotation] is only legal inside it and an entity driven
## before it is parented should steer by what it knows rather than error.
func _get_entity_basis() -> Basis:
	var entity := get_entity() as Node3D
	if entity == null:
		return Basis.IDENTITY
	var yaw := entity.global_rotation.y if entity.is_inside_tree() else entity.rotation.y
	return CameraSolver.get_movement_basis(yaw)
