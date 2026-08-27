class_name DefenseComponent
extends FrameworkComponent
## The capability of not simply standing there being hit.
##
## Block, parry, dodge, poise and stagger -- Implementation Plan 14's Defense
## line. One component because they are one decision: a defender is doing
## exactly one of these when a blow lands, and splitting them across three
## components would need all three to agree on which (rule 4).
##
## [b]It mitigates; it never applies damage.[/b] The component answers "what
## does this hit become?" and the receiver applies whatever comes back, exactly
## as [ResistanceProfile] does. That is what keeps Health from learning what a
## parry is, and what lets this be deleted from an entity that should just take
## the hit (rule 10).
##
## [b]Stamina is optional.[/b] With no [StatsComponent] the costs are simply not
## charged and blocking never breaks, which is the right behaviour for an
## armoured NPC that has no stamina bar rather than a reason to refuse.

## Emitted when a blow was blocked, with what it was reduced to.
signal blocked(context: DamageContext, absorbed: float)
## Emitted on a successful parry, carrying who to stagger and for how long.
signal parried(attacker: Node, stagger_seconds: float)
## Emitted when a dodge made a blow miss entirely.
signal evaded(context: DamageContext)
## Emitted when stamina ran out mid-block.
signal guard_broken
## Emitted when accumulated damage broke poise.
signal poise_broken
## Emitted whenever the stagger state starts or ends.
signal stagger_changed(staggered: bool)

## Defence configuration. Takes precedence over the definition's profile.
@export var profile_override: DefenseProfile

## Where stamina is spent. Resolved from the entity when left null; absent
## means defending costs nothing.
@export var stats: StatsComponent

## Stat drawn on to block and dodge.
@export var stamina_stat: StringName = &"stat.stamina"

@export var semantic_state: SemanticState

## What the defender is facing, for the block arc. Resolved to the entity root
## when left null.
@export var facing_source: Node3D

@export var auto_tick: bool = true

var _profile: DefenseProfile = null
var _blocking: bool = false
var _block_elapsed: float = 0.0
var _dodge_elapsed: float = -1.0
var _stagger_remaining: float = 0.0
var _poise_damage: float = 0.0
var _since_hit: float = 0.0


func _ready() -> void:
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if stats == null:
		stats = _find(StatsComponent) as StatsComponent
	if semantic_state == null:
		semantic_state = _find_semantic_state()
	if facing_source == null:
		facing_source = _entity_root() as Node3D
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	tick(delta)


func get_profile() -> DefenseProfile:
	return _profile


# --- State ----------------------------------------------------------------

func is_blocking() -> bool:
	return _blocking and not is_staggered()


func is_dodging() -> bool:
	return _dodge_elapsed >= 0.0


## True during the opening frames of a dodge, when nothing connects.
func is_invulnerable() -> bool:
	return (
		_profile != null
		and _dodge_elapsed >= 0.0
		and _dodge_elapsed < _profile.dodge_invulnerable
	)


## True during the opening frames of a block, when a hit is parried instead.
func is_parrying() -> bool:
	return (
		_profile != null
		and _blocking
		and not is_staggered()
		and _block_elapsed < _profile.parry_window
	)


func is_staggered() -> bool:
	return _stagger_remaining > 0.0


func get_stagger_remaining() -> float:
	return _stagger_remaining


## Damage absorbed towards a poise break.
func get_poise_damage() -> float:
	return _poise_damage


# --- Acting ---------------------------------------------------------------

## Raises the guard. The parry window opens here and closes on its own.
func begin_block() -> FrameworkResult:
	if _profile == null:
		return FrameworkResult.fail(&"defense.none", "This entity cannot block.")
	if is_staggered():
		return FrameworkResult.fail(&"defense.staggered", "Still recovering.")
	if is_dodging():
		return FrameworkResult.fail(&"defense.dodging", "Already dodging.")
	if _blocking:
		return FrameworkResult.fail(&"defense.already_blocking", "Guard is already up.")
	_blocking = true
	_block_elapsed = 0.0
	return FrameworkResult.ok(null)


func end_block() -> void:
	_blocking = false
	_block_elapsed = 0.0


## Rolls. Refused when stamina cannot pay for it, so a caller can tell a
## refused dodge from one that happened.
func dodge() -> FrameworkResult:
	if _profile == null:
		return FrameworkResult.fail(&"defense.none", "This entity cannot dodge.")
	if is_staggered():
		return FrameworkResult.fail(&"defense.staggered", "Still recovering.")
	if is_dodging():
		return FrameworkResult.fail(&"defense.already_dodging", "Already dodging.")
	if not _can_spend(_profile.dodge_stamina_cost):
		return FrameworkResult.fail(&"defense.exhausted", "Not enough stamina to dodge.")

	_spend(_profile.dodge_stamina_cost)
	_blocking = false
	_dodge_elapsed = 0.0
	return FrameworkResult.ok(null)


## Staggers this defender for [param seconds], dropping whatever it was doing.
##
## Public because a parry staggers the attacker, and the attacker's own
## component is what has to be told.
func stagger(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var was := is_staggered()
	_stagger_remaining = maxf(_stagger_remaining, seconds)
	_blocking = false
	_dodge_elapsed = -1.0
	if not was:
		_set_state(true)
		stagger_changed.emit(true)


# --- Mitigation -----------------------------------------------------------

## What this defender does to an incoming blow.
##
## Returns the multiplier the damage should be scaled by: zero for a dodge or a
## parry, a fraction for a block, one for an undefended hit. The caller applies
## it; nothing here touches health (rule 4).
##
## [b]Order matters and is not arbitrary.[/b] Invulnerability first, because a
## dodge that still cost stamina to block through would make dodging worse than
## standing still. Then the parry window, then the block, then poise -- which
## accumulates from what actually got through, so blocking protects poise as
## well as health.
func mitigate(context: DamageContext) -> float:
	if _profile == null or context == null:
		return 1.0

	_since_hit = 0.0

	if is_invulnerable():
		evaded.emit(context)
		return 0.0

	var scale := 1.0
	if is_blocking() and _covers(context):
		if is_parrying():
			if context.instigator != null:
				parried.emit(context.instigator, _profile.parry_stagger)
			scale = 1.0 - _profile.parry_reduction
		else:
			var absorbed := context.amount * _profile.block_reduction
			var cost := absorbed * _profile.block_stamina_per_damage
			if _can_spend(cost):
				_spend(cost)
				scale = 1.0 - _profile.block_reduction
				blocked.emit(context, absorbed)
			else:
				# The guard breaks and the blow lands in full. Charging partial
				# stamina for partial mitigation would let a defender block
				# forever at a trickle, which is the failure the stamina cost
				# exists to prevent.
				_blocking = false
				guard_broken.emit()
				stagger(_profile.guard_break_stagger)

	_accumulate_poise(context.amount * scale)
	return scale


# --- Time -----------------------------------------------------------------

func tick(delta: float) -> void:
	if delta <= 0.0 or _profile == null:
		return

	if _stagger_remaining > 0.0:
		_stagger_remaining = maxf(0.0, _stagger_remaining - delta)
		if _stagger_remaining <= 0.0:
			_set_state(false)
			stagger_changed.emit(false)

	if _blocking:
		_block_elapsed += delta

	if _dodge_elapsed >= 0.0:
		_dodge_elapsed += delta
		if _dodge_elapsed >= _profile.dodge_duration:
			_dodge_elapsed = -1.0

	_since_hit += delta
	if _poise_damage > 0.0 and _since_hit >= _profile.poise_recovery_delay:
		_poise_damage = 0.0


# --- Persistence ----------------------------------------------------------
#
# Nothing. A block held, a dodge mid-roll and a stagger are all sub-second
# states, and restoring into the middle of one would put a character in a pose
# the world around it has moved past.

# --- Internals ------------------------------------------------------------

func _accumulate_poise(amount: float) -> void:
	if _profile.poise <= 0.0:
		# No poise means every hit staggers, which is right for a civilian.
		if amount > 0.0:
			stagger(_profile.poise_break_stagger)
		return
	if amount <= 0.0:
		return
	_poise_damage += amount
	if _poise_damage >= _profile.poise:
		_poise_damage = 0.0
		poise_broken.emit()
		stagger(_profile.poise_break_stagger)


func _covers(context: DamageContext) -> bool:
	if facing_source == null:
		return true
	var incoming := Vector3.ZERO
	if context.instigator is Node3D:
		incoming = (context.instigator as Node3D).global_position - facing_source.global_position
	elif context.hit_normal != Vector3.ZERO:
		incoming = -context.hit_normal
	return _profile.covers(-facing_source.global_transform.basis.z, incoming)


func _can_spend(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if stats == null or not stats.has_stat(stamina_stat):
		# No stamina bar means defending is free rather than impossible. An
		# armoured NPC with no stamina should still be able to raise a shield.
		return true
	return stats.can_spend(stamina_stat, cost)


func _spend(cost: float) -> void:
	if cost <= 0.0 or stats == null or not stats.has_stat(stamina_stat):
		return
	stats.spend(stamina_stat, cost)


func _set_state(staggered: bool) -> void:
	if semantic_state == null:
		return
	if staggered:
		semantic_state.add_state(GameplayNames.STATE_STAGGERED)
	else:
		semantic_state.remove_state(GameplayNames.STATE_STAGGERED)


func _resolve_profile() -> DefenseProfile:
	if profile_override != null:
		return profile_override
	var context := get_context()
	var definition := context.definition if context != null else null
	if definition != null and "defense" in definition:
		return definition.get("defense") as DefenseProfile
	return null


func _entity_root() -> Node:
	var context := get_context()
	if context != null and context.entity != null:
		return context.entity
	return get_parent()


func _find(type: Variant) -> FrameworkComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child as FrameworkComponent
	return null


func _find_semantic_state() -> SemanticState:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if child is SemanticState:
			return child as SemanticState
	return null
