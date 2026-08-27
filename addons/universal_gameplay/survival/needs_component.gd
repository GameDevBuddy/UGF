class_name NeedsComponent
extends FrameworkComponent
## Hunger, thirst, fatigue, warmth: the meters that drain while you do nothing.
##
## Owns the values and the consequences of them running out. It restores
## nothing itself -- eating is [ConsumerComponent]'s business -- because "what
## a meat pie does" and "what starving does" are different questions with
## different owners (rule 4).

## Emitted whenever a need changes.
signal need_changed(need: StringName, value: float, previous: float)
## Emitted when a need crosses into or out of its low band.
signal need_low(need: StringName, low: bool)
## Emitted when a need crosses into or out of its critical band. What a HUD
## flashes on and a brain reacts to.
signal need_critical(need: StringName, critical: bool)
## Emitted when a need hits zero.
signal need_emptied(need: StringName)

## The needs this entity has. Takes precedence over the definition's.
@export var needs_override: Array[NeedDefinition] = []

## States mirrored from thresholds. Found among this entity's own components
## when not wired.
@export var semantic_state: SemanticState

## Where empty-need damage goes, so it passes through armour and immunity like
## any other hit. Absent, an empty need does no damage rather than bypassing
## mitigation.
@export var damage_receiver: DamageReceiverComponent

## Where a critical need's status effect is applied. Absent, none is.
@export var status_effects: StatusEffectComponent

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

## Multiplier on every need's decay. What a difficulty setting moves, and what
## a sleeping or paused entity sets to zero.
@export_range(0.0, 10.0, 0.01) var decay_scale: float = 1.0

var _definitions: Dictionary[StringName, NeedDefinition] = {}
var _values: Dictionary[StringName, float] = {}
var _low: Dictionary[StringName, bool] = {}
var _critical: Dictionary[StringName, bool] = {}
## Per-need decay multipliers contributed by environment zones, by source.
var _modifiers: Dictionary[StringName, Dictionary] = {}
var _seeded: bool = false


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and not _definitions.is_empty())


func initialize(context: EntityContext) -> void:
	super(context)
	_resolve_definitions()
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	if damage_receiver == null:
		damage_receiver = _find(DamageReceiverComponent) as DamageReceiverComponent
	if status_effects == null:
		status_effects = _find(StatusEffectComponent) as StatusEffectComponent
	if not _seeded:
		_seed()
		_seeded = true
	set_physics_process(auto_tick and not _definitions.is_empty())


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Queries --------------------------------------------------------------

func has_need(need: StringName) -> bool:
	return _definitions.has(need)


func get_need(need: StringName) -> NeedDefinition:
	return _definitions.get(need)


func get_need_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_definitions.keys())
	return ids


func get_value(need: StringName) -> float:
	return _values.get(need, 0.0)


func get_fraction(need: StringName) -> float:
	var definition := get_need(need)
	return definition.get_fraction(get_value(need)) if definition != null else 0.0


func is_low(need: StringName) -> bool:
	return _low.get(need, false)


func is_critical(need: StringName) -> bool:
	return _critical.get(need, false)


func is_empty(need: StringName) -> bool:
	return get_value(need) <= 0.0


## Every need currently in its critical band. What a brain checks before
## deciding to go looking for food.
func get_critical_needs() -> Array[StringName]:
	var critical: Array[StringName] = []
	for need in _critical:
		if _critical[need]:
			critical.append(need)
	return critical


# --- Changing -------------------------------------------------------------

## Adds to a need. Negative drains it. Returns the new value.
func restore(need: StringName, amount: float) -> float:
	if not has_need(need) or is_equal_approx(amount, 0.0):
		return get_value(need)
	_apply(need, get_value(need) + amount)
	return get_value(need)


func drain(need: StringName, amount: float) -> float:
	return restore(need, -amount)


func set_value(need: StringName, value: float) -> void:
	if has_need(need):
		_apply(need, value)


func refill(need: StringName) -> void:
	var definition := get_need(need)
	if definition != null:
		_apply(need, definition.maximum)


func refill_all() -> void:
	for need in get_need_ids():
		refill(need)


# --- Environment ----------------------------------------------------------
#
# A cold zone does not drain warmth itself; it multiplies how fast warmth
# drains. Keeping it a multiplier means two overlapping zones compose, and
# leaving one restores what the other was doing -- which is the failure that
# makes entering and leaving a cave a source of drift.

## Applies a decay multiplier to one need, attributed to [param source].
## Re-applying from the same source replaces rather than stacks.
func set_decay_modifier(need: StringName, source: StringName, scale: float) -> void:
	if need == &"" or source == &"":
		return
	if not _modifiers.has(need):
		_modifiers[need] = {}
	_modifiers[need][source] = scale


func clear_decay_modifier(need: StringName, source: StringName) -> void:
	if _modifiers.has(need):
		_modifiers[need].erase(source)


## Combined multiplier on a need's decay right now, environment and the
## component's own scale together.
func get_decay_scale(need: StringName) -> float:
	var scale := decay_scale
	for source in _modifiers.get(need, {}):
		scale *= float(_modifiers[need][source])
	return scale


# --- Time -----------------------------------------------------------------

## Decays every need and applies the consequences. Called for you when
## [member auto_tick] is on.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for need in get_need_ids():
		var definition := _definitions[need]
		_apply(need, definition.decay(get_value(need), delta, get_decay_scale(need)))
		if definition.is_empty(get_value(need)):
			_apply_empty_damage(definition, delta)


# --- Persistence ----------------------------------------------------------
#
# All of it. A survival game whose hunger reset on load would be a survival
# game nobody could lose, and this is the half of the M12 exit gate that says
# "needs save/load".

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var saved: Dictionary = {}
	for need in _values:
		saved[String(need)] = _values[need]
	return {"needs": saved}


func restore_state(data: Dictionary) -> void:
	for key in data.get("needs", {}):
		var need := StringName(key)
		if has_need(need):
			_apply(need, float(data["needs"][key]))
	# A restored entity must not be topped up to its starting values on the
	# next initialize, which is how a save reload turns into a free meal.
	_seeded = true


# --- Internals ------------------------------------------------------------

## Named [code]_apply[/code] rather than [code]_set[/code]: Godot's
## [method Object._set] is a virtual with a different signature, and shadowing
## it is a parse error rather than an override. It is the most natural name in
## the world for a private setter and it has now cost this project twice.
func _apply(need: StringName, value: float) -> void:
	var definition := get_need(need)
	if definition == null:
		return
	var clamped := definition.clamp_value(value)
	var previous := get_value(need)
	if is_equal_approx(previous, clamped) and _values.has(need):
		return
	_values[need] = clamped
	need_changed.emit(need, clamped, previous)
	_update_bands(definition, clamped, previous)


func _update_bands(definition: NeedDefinition, value: float, previous: float) -> void:
	var need := definition.id
	var low := definition.is_low(value)
	if low != _low.get(need, false):
		_low[need] = low
		_set_state(definition.low_state, low)
		need_low.emit(need, low)

	var critical := definition.is_critical(value)
	if critical != _critical.get(need, false):
		_critical[need] = critical
		_set_state(definition.critical_state, critical)
		_apply_critical_effect(definition, critical)
		need_critical.emit(need, critical)

	if value <= 0.0 and previous > 0.0:
		need_emptied.emit(need)


func _apply_empty_damage(definition: NeedDefinition, delta: float) -> void:
	if definition.damage_per_second <= 0.0 or damage_receiver == null:
		return
	damage_receiver.receive_amount(
		definition.damage_per_second * delta, definition.damage_tags.duplicate()
	)


func _apply_critical_effect(definition: NeedDefinition, critical: bool) -> void:
	if definition.critical_effect == &"" or status_effects == null:
		return
	if not critical:
		status_effects.remove(definition.critical_effect)
		return
	var effect := _lookup(definition.critical_effect) as StatusEffectDefinition
	if effect != null:
		status_effects.apply(effect)


func _set_state(state: StringName, active: bool) -> void:
	if state != &"" and semantic_state != null:
		semantic_state.set_state(state, active)


func _seed() -> void:
	for need in get_need_ids():
		_values[need] = _definitions[need].clamp_value(_definitions[need].starting_value)
		_update_bands(_definitions[need], _values[need], _values[need])


## Read by property name rather than by casting, so a vehicle or a creature
## with its own definition type can have needs (rule 9).
func _resolve_definitions() -> void:
	_definitions.clear()
	var source: Array = needs_override
	if source.is_empty():
		var definition := get_definition()
		if definition != null and "needs" in definition:
			var candidate: Variant = definition.get("needs")
			if candidate is Array:
				source = candidate as Array
	for entry in source:
		if entry is NeedDefinition and (entry as NeedDefinition).id != &"":
			_definitions[(entry as NeedDefinition).id] = entry


func _lookup(id: StringName) -> FrameworkDefinition:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", id) as FrameworkDefinition


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
