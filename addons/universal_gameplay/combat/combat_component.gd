class_name CombatComponent
extends FrameworkComponent
## The capability of attacking. One command API, whoever is asking.
##
## [b]This is the M6 exit gate in one class.[/b] A player's mouse button, an AI
## behaviour tree and a test all call [method attack]; a sword and a rifle both
## arrive here as an [AttackDefinition] with a different delivery; and both
## produce the same [DamageContext] on the way out. There is no ranged path and
## no melee path, and no privileged player path an AI would have to work
## around (rule 14).
##
## [b]Timing is the state machine.[/b] Startup, active and recovery come off
## the attack definition, and the damage window resolves exactly once, when the
## active phase opens. An attack with no timing resolves the instant it is
## asked to -- which is what makes a hitscan shot and a heavy swing the same
## code path.
##
## [b]The world arrives through a seam.[/b] Hit queries go to a [HitProvider],
## so what an attack connects with is decidable in a unit test with no physics
## frame, no colliders and no scene (rule 33).

## Emitted when an attack is committed to, before any wind-up has elapsed.
signal attack_started(context: AttackContext)
## Emitted when the damage window opens, once per attack.
signal attack_window_opened(context: AttackContext)
## Emitted per connected target, after mitigation has been asked for.
signal attack_landed(hit: CombatHit, damage: DamageContext)
## Emitted when an attack finishes its recovery.
signal attack_finished(context: AttackContext)
## Emitted when an attack was cut short.
signal attack_interrupted(context: AttackContext, reason: StringName)

## How this entity fights unarmed. Takes precedence over the definition's.
@export var profile_override: CombatProfile

## The weapon in its hands. Absent, it fights unarmed, which is a whole valid
## configuration rather than a missing one (rule 31).
@export var weapon: WeaponComponent

## Stats attacks spend from. Absent, attacks are free.
@export var stats: StatsComponent

## States mirrored while attacking.
@export var semantic_state: SemanticState

## Node whose transform attacks come from: a muzzle, a camera, a shoulder.
## Absent, the entity's own transform is used at the profile's aim height.
@export var aim: Node3D

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

@export_group("Hit detection")
## Opens the damage window on an animation event instead of on the authored
## startup time.
##
## [b]The fallback is not optional.[/b] Plan 14 lists "animation event" as a
## hit-detection strategy, and the failure mode of one is a swing whose
## animation was retimed, renamed or never authored, leaving a sword that never
## connects and no error anywhere. So the authored startup still runs as a
## backstop: whichever comes first opens the window, and the window still
## resolves exactly once.
@export var window_from_animation: bool = false

## Where the animation talks back. Resolved from the entity when left null.
@export var animation_events: AnimationEventRelay

## The event name that opens the window.
@export var hit_event: StringName = &"animation.hit"

var _profile: CombatProfile = null
var _provider: HitProvider = null
var _rng: RandomNumberGenerator = null
var _swing: AttackContext = null
var _phase: CombatSolver.Phase = CombatSolver.Phase.IDLE
var _elapsed: float = 0.0
var _resolved: bool = false
var _holding: bool = false
var _holding_secondary: bool = false
var _burst_left: int = 0
var _aim_direction: Vector3 = Vector3.ZERO
var _has_aim_override: bool = false


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if weapon == null:
		weapon = _find(WeaponComponent) as WeaponComponent
	if stats == null:
		stats = _find(StatsComponent) as StatsComponent
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	if animation_events == null:
		animation_events = AnimationEventRelay.find_on(get_parent())
	if animation_events != null:
		animation_events.subscribe(hit_event, _on_animation_hit)
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	tick(delta)


func get_profile() -> CombatProfile:
	return _profile


# --- The seam -------------------------------------------------------------

## Where hit queries go. Built against this entity's world on first use, so a
## project that wants its own -- a fake for a test, a pooled or layered one --
## injects it before the first attack.
func get_hit_provider() -> HitProvider:
	if _provider == null:
		_provider = PhysicsHitProvider.for_node(_get_body())
	return _provider


func set_hit_provider(provider: HitProvider) -> void:
	_provider = provider


## Randomness for spread. Injected so a test is repeatable and a networked
## game can share one stream across clients.
func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


# --- Aim ------------------------------------------------------------------

func get_aim_origin() -> Vector3:
	if aim != null and aim.is_inside_tree():
		return aim.global_position
	var body := _get_body()
	if body == null or not body.is_inside_tree():
		return Vector3.ZERO
	var height := _profile.aim_height if _profile != null else 0.0
	return body.global_position + Vector3.UP * height


func get_aim_direction() -> Vector3:
	if _has_aim_override:
		return _aim_direction
	var source := aim if aim != null else _get_body()
	if source == null or not source.is_inside_tree():
		return Vector3.FORWARD
	return -source.global_transform.basis.z


## Points attacks at a world point. What an AI calls instead of rotating the
## whole entity, and what makes an NPC able to shoot before it has finished
## turning.
func aim_at(point: Vector3) -> void:
	var direction := point - get_aim_origin()
	if direction.is_zero_approx():
		return
	_aim_direction = direction.normalized()
	_has_aim_override = true


func set_aim_direction(direction: Vector3) -> void:
	if direction.is_zero_approx():
		clear_aim_override()
		return
	_aim_direction = direction.normalized()
	_has_aim_override = true


## Goes back to reading the aim node or the entity's own facing.
func clear_aim_override() -> void:
	_has_aim_override = false
	_aim_direction = Vector3.ZERO


# --- State ----------------------------------------------------------------

## Puts the character into or out of aim-down-sights.
##
## [b]The state lives on the character, not in the weapon.[/b] Plan 13 is
## explicit that aim is a character or camera state, and the reason is that
## three separate things read it -- the weapon tightens its cone, the camera
## narrows its field of view, the animation graph picks a different pose -- and
## none of them should have to ask a weapon. Swapping weapons mid-aim then
## keeps the character aiming, which is what a player expects and what a flag
## on the weapon would get wrong.
func set_aiming(aiming: bool) -> void:
	if semantic_state == null:
		return
	if aiming:
		semantic_state.add_state(GameplayNames.STATE_AIMING)
	else:
		semantic_state.remove_state(GameplayNames.STATE_AIMING)


func is_aiming() -> bool:
	return semantic_state != null and semantic_state.has_state(GameplayNames.STATE_AIMING)


func is_attacking() -> bool:
	return _swing != null


func get_phase() -> CombatSolver.Phase:
	return _phase


func get_attack_context() -> AttackContext:
	return _swing


## Progress through the current attack in 0..1, or zero when idle.
func get_progress() -> float:
	if _swing == null or _swing.attack == null:
		return 0.0
	var duration := _swing.attack.get_duration()
	if duration <= 0.0:
		return 1.0
	return clampf(_elapsed / duration, 0.0, 1.0)


## The attack a press would produce right now: the weapon's, or the profile's
## unarmed one. Null means this entity cannot attack at all.
func get_attack(secondary: bool = false) -> AttackDefinition:
	if weapon != null:
		var armed := weapon.get_attack(secondary)
		if armed != null:
			return armed
	if secondary:
		return null
	return _profile.unarmed if _profile != null else null


# --- Commands -------------------------------------------------------------

## Whether an attack could start right now, and why not when it could not.
func can_attack(secondary: bool = false) -> FrameworkResult:
	if is_attacking():
		return FrameworkResult.fail(&"combat.busy", "Already attacking.")
	var attack := get_attack(secondary)
	if attack == null:
		return FrameworkResult.fail(&"combat.no_attack", "Nothing to attack with.")
	if weapon != null and weapon.has_weapon():
		var ready := weapon.can_fire(secondary)
		if ready.is_err():
			return ready
	if not _can_afford(attack):
		return FrameworkResult.fail(&"combat.cost", "Not enough to spend on that.")
	return FrameworkResult.ok(attack)


## Starts one attack. The one call a player, an AI and a test all make.
## Swings, shoots or punches.
##
## [param damage_scale] multiplies this one attack's damage. A charge weapon
## passes what its release bought; everything else leaves it at one. It is an
## argument rather than state on the component because it belongs to the swing
## and has to be gone by the next one -- a field would survive into the
## following attack and turn one charged shot into a permanently charged
## weapon.
func attack(secondary: bool = false, damage_scale: float = 1.0) -> FrameworkResult:
	var allowed := can_attack(secondary)
	if allowed.is_err():
		return allowed

	var definition: AttackDefinition = allowed.payload

	# Built before the shot is paid for, because paying for it widens the cone
	# and this shot should go into the cone the weapon had when the trigger was
	# pulled. Reading spread after consuming makes the very first shot from a
	# rested weapon carry its own kick, which reads as a rifle that can never
	# hit anything at range. Building a context mutates nothing, so refusing
	# below still leaves the actor exactly as it was (rule 17).
	var context := _build_context(definition, secondary)
	context.damage_scale = damage_scale
	if weapon != null and weapon.has_weapon():
		var paid := weapon.consume_shot(secondary)
		if paid.is_err():
			return paid
	_spend(definition)

	_swing = context
	_elapsed = 0.0
	_resolved = false
	_phase = CombatSolver.Phase.STARTUP if definition.startup > 0.0 else CombatSolver.Phase.ACTIVE
	_set_state(true)
	attack_started.emit(_swing)

	if definition.startup <= 0.0:
		_open_window()
	if _elapsed >= definition.get_duration():
		_finish()
	return FrameworkResult.ok(_swing)


## Holds the trigger. Automatic weapons repeat while this is set; burst
## weapons fire their burst; single-shot weapons fire once.
func hold(secondary: bool = false) -> FrameworkResult:
	_holding = true
	_holding_secondary = secondary
	var mode := _get_fire_mode()
	if mode == WeaponProfile.FireMode.BURST:
		var count := weapon.get_profile().burst_count if weapon != null and weapon.has_weapon() else 1
		_burst_left = maxi(1, count)
	return attack(secondary)


## Releases the trigger. A burst already begun finishes; an automatic stops
## after the attack in progress.
func release() -> void:
	_holding = false


func is_holding() -> bool:
	return _holding


## Cuts an attack short. An attack marked uninterruptible ignores this unless
## [param force] is set -- that flag is what a heavy swing's commitment means.
func cancel(reason: StringName = &"cancelled", force: bool = false) -> void:
	if _swing == null:
		return
	if not force and _swing.attack != null and not _swing.attack.interruptible:
		return
	var context := _swing
	_clear_swing()
	_burst_left = 0
	attack_interrupted.emit(context, reason)


# --- Time -----------------------------------------------------------------

## Advances the attack in progress and any held trigger. Called for you when
## [member auto_tick] is on.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if _swing != null:
		_tick_swing(delta)
		return
	_tick_trigger()


func _tick_swing(delta: float) -> void:
	var definition := _swing.attack
	_elapsed += delta
	# Keyed on startup having elapsed rather than on the phase being ACTIVE.
	# A frame long enough to step over a short window would otherwise skip it
	# entirely and the attack would silently do nothing -- and the resolve
	# happens once, because a window wide enough to sweep would otherwise hit a
	# stationary target every frame it was open.
	if not _resolved and _elapsed >= definition.startup:
		_open_window()
	_phase = CombatSolver.phase_at(
		_elapsed, definition.startup, definition.active, definition.recovery
	)

	if _elapsed >= definition.get_duration():
		_finish()


func _tick_trigger() -> void:
	if _burst_left > 0:
		if can_attack(_holding_secondary).is_ok():
			attack(_holding_secondary)
		return
	if not _holding or _get_fire_mode() != WeaponProfile.FireMode.AUTOMATIC:
		return
	if can_attack(_holding_secondary).is_ok():
		attack(_holding_secondary)


# --- Internals ------------------------------------------------------------

## Resolves the damage window: what the attack connected with, and what that
## does to each of them.
## The animation says the blow lands now.
##
## Ignored when no attack is in flight, so a stray keyframe on an idle
## animation cannot make a character swing at nothing.
func _on_animation_hit(_payload: Variant) -> void:
	if not window_from_animation or _swing == null or _resolved:
		return
	_open_window()


func _open_window() -> void:
	_resolved = true
	_phase = CombatSolver.Phase.ACTIVE
	attack_window_opened.emit(_swing)

	var definition := _swing.attack
	if definition.delivery == null:
		return
	for hit in definition.delivery.resolve(_swing, get_hit_provider()):
		if hit == null or hit.target == null:
			continue
		var damage := _swing.make_damage(hit)
		var receiver := hit.get_receiver()
		if receiver != null:
			receiver.receive(damage)
		# Emitted for every hit, damageable or not: a bullet stopping on a wall
		# is what a decal and an impact sound are for.
		attack_landed.emit(hit, damage)


func _finish() -> void:
	var context := _swing
	_clear_swing()
	if _burst_left > 0:
		_burst_left -= 1
	attack_finished.emit(context)


func _clear_swing() -> void:
	_swing = null
	_elapsed = 0.0
	_resolved = false
	_phase = CombatSolver.Phase.IDLE
	_set_state(false)


func _build_context(definition: AttackDefinition, secondary: bool) -> AttackContext:
	var context := AttackContext.create(
		get_entity(), definition, get_aim_origin(), get_aim_direction()
	)
	context.source = weapon if weapon != null and weapon.has_weapon() else get_entity()
	context.weapon_id = weapon.get_weapon_id() if weapon != null else &""
	context.spread_degrees = weapon.get_spread() if weapon != null else 0.0
	context.rng = _rng
	context.world = _get_world()
	var exclude: Array[Node] = []
	if get_entity() != null:
		exclude.append(get_entity())
	context.exclude = exclude
	# Read once so a secondary attack's context reports which button made it.
	context.extras["secondary"] = secondary
	return context


func _get_fire_mode() -> WeaponProfile.FireMode:
	if weapon == null or weapon.get_profile() == null:
		return WeaponProfile.FireMode.SINGLE
	return weapon.get_profile().fire_mode


func _cost_stat(definition: AttackDefinition) -> StringName:
	if definition.cost_stat != &"":
		return definition.cost_stat
	return _profile.default_cost_stat if _profile != null else &""


func _can_afford(definition: AttackDefinition) -> bool:
	if definition.cost <= 0.0 or stats == null:
		return true
	var stat := _cost_stat(definition)
	if stat == &"" or not stats.has_stat(stat):
		return true
	return stats.can_spend(stat, definition.cost)


func _spend(definition: AttackDefinition) -> void:
	if definition.cost <= 0.0 or stats == null:
		return
	var stat := _cost_stat(definition)
	if stat != &"" and stats.has_stat(stat):
		stats.spend(stat, definition.cost)


func _set_state(attacking: bool) -> void:
	if semantic_state != null:
		semantic_state.set_state(GameplayNames.STATE_ATTACKING, attacking)


## Where a delivery that spawns something puts it: the entity's own parent, so
## a projectile is a sibling of its shooter rather than a child that would move
## with it.
func _get_world() -> Node:
	var body := _get_body()
	if body == null:
		return null
	return body.get_parent()


func _get_body() -> Node3D:
	var entity := get_entity()
	return entity as Node3D if entity is Node3D else null


func _resolve_profile() -> CombatProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "combat" in definition:
		var candidate: Variant = definition.get("combat")
		if candidate is CombatProfile:
			return candidate as CombatProfile
	return null


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
