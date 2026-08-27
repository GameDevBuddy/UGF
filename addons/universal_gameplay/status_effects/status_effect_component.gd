class_name StatusEffectComponent
extends FrameworkComponent
## The capability of being buffed, poisoned, slowed or on fire.
##
## Owns the live effects on one entity: applying them, expiring them, ticking
## their periodic damage, and taking back exactly what each one added.
##
## [b]Modifiers are removed by source, never individually.[/b] Each application
## stamps its effect id onto the modifiers it applies, and expiry removes
## everything with that source. Two overlapping buffs therefore unwind
## correctly in either order, which is the failure this design exists to
## prevent -- a stat that drifts a little every time effects overlap is a bug
## nobody notices until a save comes back wrong.

## Emitted when an effect is applied for the first time.
signal effect_applied(instance: StatusEffectInstance)
## Emitted when an existing effect is refreshed or gains a stack.
signal effect_stacked(instance: StatusEffectInstance)
## Emitted when an effect ends, whether it expired or was removed.
signal effect_removed(id: StringName, expired: bool)
## Emitted on each periodic application, carrying the context that was dealt.
signal effect_ticked(instance: StatusEffectInstance, context: DamageContext)

## Stats to apply modifiers to, wired at composition time (rule 20). Absent,
## effects still run their periodic damage and state tags -- a burning crate
## with no attributes is a valid target.
@export var stats: StatsComponent

## Damage receiver for periodic damage, so a poison goes through the same
## mitigation a hit does. Absent, periodic damage is skipped rather than
## bypassing armour.
@export var damage_receiver: DamageReceiverComponent

## Semantic state to mirror effect tags onto.
@export var semantic_state: SemanticState

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

var _instances: Array[StatusEffectInstance] = []


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may have
	# initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	if stats == null:
		stats = _find(StatsComponent) as StatsComponent
	if damage_receiver == null:
		damage_receiver = _find(DamageReceiverComponent) as DamageReceiverComponent
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Applying -------------------------------------------------------------

## Applies an effect, honouring its stacking policy.
##
## Returns the live instance on success. A refused application -- an
## [constant StatusEffectDefinition.Stacking.IGNORE] effect already running --
## is a failure result rather than a silent no-op, because the caller usually
## wants to know whether the potion was wasted.
func apply(
	definition: StatusEffectDefinition, instigator: Node = null
) -> FrameworkResult:
	if definition == null:
		return FrameworkResult.fail(
			&"status.null_definition", "Cannot apply a null status effect."
		)
	if definition.id == &"":
		return FrameworkResult.fail(
			&"status.unnamed_effect",
			"A status effect with no id cannot be tracked or removed."
		)

	for removed_id in definition.removes:
		remove(removed_id)

	var existing := get_instance(definition.id)
	if existing != null:
		return _reapply(existing, definition)

	var instance := StatusEffectInstance.create(definition, instigator)
	_instances.append(instance)
	_apply_modifiers(instance)
	_apply_states(definition, true)
	effect_applied.emit(instance)
	return FrameworkResult.ok(instance)


func _reapply(
	existing: StatusEffectInstance, definition: StatusEffectDefinition
) -> FrameworkResult:
	match definition.stacking:
		StatusEffectDefinition.Stacking.IGNORE:
			return FrameworkResult.fail(
				&"status.already_active",
				"'%s' is already active and does not re-apply." % definition.id
			)
		StatusEffectDefinition.Stacking.REFRESH:
			existing.refresh()
			effect_stacked.emit(existing)
			return FrameworkResult.ok(existing)
		StatusEffectDefinition.Stacking.STACK:
			existing.refresh()
			if existing.add_stack():
				# A stack adds its modifiers again under the same source, so
				# removal still takes back all of them at once.
				_apply_modifiers(existing)
			effect_stacked.emit(existing)
			return FrameworkResult.ok(existing)
		_:
			var instance := StatusEffectInstance.create(definition, existing.instigator)
			_instances.append(instance)
			_apply_modifiers(instance)
			effect_applied.emit(instance)
			return FrameworkResult.ok(instance)


## Removes every application of an effect. Returns true if anything went.
func remove(id: StringName) -> bool:
	var removed := false
	for index in range(_instances.size() - 1, -1, -1):
		if _instances[index].get_id() != id:
			continue
		_end(_instances[index], index, false)
		removed = true
	return removed


## Removes everything. For death, cleanses, and scene teardown.
func clear() -> void:
	for index in range(_instances.size() - 1, -1, -1):
		_end(_instances[index], index, false)


# --- Queries --------------------------------------------------------------

func has_effect(id: StringName) -> bool:
	return get_instance(id) != null


func get_instance(id: StringName) -> StatusEffectInstance:
	for instance in _instances:
		if instance.get_id() == id:
			return instance
	return null


func get_instances() -> Array[StatusEffectInstance]:
	return _instances.duplicate()


func get_effect_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for instance in _instances:
		ids.append(instance.get_id())
	return ids


func get_stacks(id: StringName) -> int:
	var instance := get_instance(id)
	return instance.stacks if instance != null else 0


func is_empty() -> bool:
	return _instances.is_empty()


# --- Tick -----------------------------------------------------------------

## Advances every effect by [param delta]: durations, periodic damage, expiry.
##
## Public so a networked authority or a test can own the timing.
func tick(delta: float) -> void:
	if delta <= 0.0 or _instances.is_empty():
		return
	for index in range(_instances.size() - 1, -1, -1):
		var instance := _instances[index]
		_tick_periodic(instance, delta)
		if instance.is_permanent():
			continue
		instance.remaining -= delta
		if instance.is_expired():
			_end(instance, index, true)


func _tick_periodic(instance: StatusEffectInstance, delta: float) -> void:
	var definition := instance.definition
	if definition == null or not definition.is_periodic():
		return

	var interval := definition.tick_interval
	var amount := 0.0
	if interval <= 0.0:
		# Continuous: scale by frame time so the total over a second is the
		# authored rate whatever the frame rate.
		amount = instance.get_damage_per_second() * delta
	else:
		instance.since_tick += delta
		if instance.since_tick < interval:
			return
		var ticks := floori(instance.since_tick / interval)
		instance.since_tick -= float(ticks) * interval
		amount = instance.get_damage_per_second() * interval * float(ticks)

	if is_zero_approx(amount):
		return
	_deal(instance, amount)


## Applies one periodic application through the normal damage path.
##
## Healing effects go to health directly, because [DamagePipeline] deals in
## damage and a negative amount through mitigation would be armour making a
## heal smaller -- which is nonsense.
func _deal(instance: StatusEffectInstance, amount: float) -> void:
	if damage_receiver == null:
		return
	if amount < 0.0:
		if damage_receiver.health != null:
			damage_receiver.health.heal(-amount)
		return
	var context := DamageContext.create(
		amount, instance.instigator, null, instance.definition.damage_tags
	)
	damage_receiver.receive(context)
	effect_ticked.emit(instance, context)


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


## Saves effect ids, remaining time and stacks -- not the modifiers.
##
## Modifiers are rebuilt from the definition on restore. Persisting them too
## would apply every buff twice on load, which is the same double-application
## bug [StatsComponent] avoids by not saving them either (rule 4).
func capture_state() -> Dictionary:
	var saved: Array = []
	for instance in _instances:
		if instance.definition == null or not instance.definition.persistent:
			continue
		saved.append({
			"id": String(instance.get_id()),
			"remaining": instance.remaining,
			"stacks": instance.stacks,
		})
	return {"effects": saved}


## Rebuilds effects from a save.
##
## Definitions are resolved through the core's registry by id, which is what
## rule 32 means in practice: the save holds ids, not resource paths, so
## moving [code]effect_burning.tres[/code] does not break existing saves.
func restore_state(data: Dictionary) -> void:
	clear()
	var context := get_context()
	if context == null or context.core == null:
		return
	if not context.core.has_method("get_definition"):
		return

	for entry in data.get("effects", []):
		var id := StringName(entry.get("id", ""))
		if id == &"":
			continue
		var definition := context.core.call("get_definition", id) as StatusEffectDefinition
		if definition == null:
			continue
		var result := apply(definition)
		if result.is_err():
			continue
		var instance := result.payload as StatusEffectInstance
		instance.remaining = float(entry.get("remaining", instance.remaining))
		var target_stacks := int(entry.get("stacks", 1))
		while instance.stacks < target_stacks and instance.add_stack():
			_apply_modifiers(instance)


# --- Internals ------------------------------------------------------------

func _apply_modifiers(instance: StatusEffectInstance) -> void:
	if stats == null or instance.definition == null:
		return
	var built := instance.definition.build_modifiers()
	instance.applied_modifiers.append_array(built)
	stats.add_modifiers(built)


func _apply_states(definition: StatusEffectDefinition, active: bool) -> void:
	if semantic_state == null or definition == null:
		return
	for state in definition.applied_states:
		semantic_state.set_state(state, active)


## Ends one instance: takes back its modifiers, clears its tags, announces it.
func _end(instance: StatusEffectInstance, index: int, expired: bool) -> void:
	var id := instance.get_id()
	_instances.remove_at(index)
	if stats != null and id != &"":
		stats.remove_modifiers_from(id)
	# Only clear the state tags once no other application still wants them.
	if not has_effect(id):
		_apply_states(instance.definition, false)
	effect_removed.emit(id, expired)


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
