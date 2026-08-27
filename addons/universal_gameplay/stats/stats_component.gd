class_name StatsComponent
extends FrameworkComponent
## The capability of having numbers that other systems modify.
##
## Owns the base values, the modifier list, and the current value of anything
## depletable. It computes nothing itself -- [StatCalculator] does the
## arithmetic -- so what lives here is the part that genuinely needs to persist
## between frames: which modifiers are applied, who applied them, and how much
## stamina is left.
##
## [b]Removal is by source.[/b] Nothing removes "the +10 strength modifier"; a
## caller removes everything a given effect applied. That is what makes two
## overlapping buffs safe: each takes back exactly its own contribution, and
## the stat cannot drift as they expire in either order.
##
## Values are computed on demand and cached until something invalidates them,
## because rule 25 wants no work in a hot loop and a stat nobody reads should
## cost nothing to have.

## Emitted when a computed value changes, for whatever reason.
signal stat_changed(stat: StringName, value: float, previous: float)
## Emitted when a depletable stat reaches its minimum.
signal stat_depleted(stat: StringName)
## Emitted when a depletable stat returns to full.
signal stat_replenished(stat: StringName)
## Emitted when modifiers are added or removed, so an inspector can refresh.
signal modifiers_changed

## Stats configuration. Takes precedence over the definition's profile.
@export var profile_override: StatsProfile

## Regenerate depletable stats from [method Node._physics_process]. Off when
## something else owns the tick.
@export var auto_tick: bool = true

var _profile: StatsProfile = null
var _bases: Dictionary[StringName, float] = {}
var _modifiers: Array[StatModifier] = []
var _current: Dictionary[StringName, float] = {}
var _since_spent: Dictionary[StringName, float] = {}
var _cache: Dictionary[StringName, float] = {}
## Source stat to the derived stats that read it, built once at initialise.
##
## Built rather than searched, because invalidation happens on every modifier
## change and walking every definition to ask "does anything derive from this?"
## would put a scan in the hot path (rule 25).
var _dependents: Dictionary[StringName, Array] = {}
## Derived stats currently being computed, so a derivation cycle that slipped
## past validation returns a number instead of hanging the engine.
var _deriving: Dictionary[StringName, bool] = {}


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may have
	# initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _has_regenerating_stat())


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	_rebuild_from_profile()
	_build_dependents()
	set_physics_process(auto_tick and _has_regenerating_stat())


func _physics_process(delta: float) -> void:
	tick(delta)


## Maps each source stat to the derived stats that read it.
##
## Built once, here, rather than searched on every invalidation. A stat change
## is one of the most frequent things that happens in a game, and asking every
## definition "does anything derive from you?" each time would be exactly the
## hot-loop scan rule 25 forbids.
func _build_dependents() -> void:
	_dependents.clear()
	if _profile == null:
		return
	for definition in _profile.stats:
		if definition == null or definition.derivation == null:
			continue
		for source in definition.derivation.sources:
			if source == &"" or source == definition.id:
				continue
			if not _dependents.has(source):
				_dependents[source] = [] as Array[StringName]
			if not _dependents[source].has(definition.id):
				_dependents[source].append(definition.id)


# --- Reading --------------------------------------------------------------

## The computed value of a stat: base, modifiers, clamps.
##
## Returns [param fallback] for a stat this entity does not have, rather than
## inventing one. A missing stat is a legitimate state -- a crate has no
## strength -- and returning zero would let callers treat "absent" as "weak".
func get_value(stat: StringName, fallback: float = 0.0) -> float:
	if not _bases.has(stat):
		return fallback
	if _cache.has(stat):
		return _cache[stat]
	var definition := _profile.get_definition(stat) if _profile != null else null
	var minimum := definition.get_minimum() if definition != null else -INF
	var maximum := definition.get_maximum() if definition != null else INF
	var value := StatCalculator.calculate(
		_base_for(stat, definition), _modifiers, stat, minimum, maximum
	)
	_cache[stat] = value
	return value


## Whether this stat computes its base from others rather than storing one.
func is_derived(stat: StringName) -> bool:
	var definition := _profile.get_definition(stat) if _profile != null else null
	return definition != null and definition.derivation != null and not definition.derivation.is_empty()


## The base a stat's modifiers apply on top of.
##
## Authored for most stats; computed for a derived one. Note that a derived
## stat still keeps whatever is in [member _bases] -- untouched and unused --
## so turning a derivation off restores the authored number rather than
## leaving the stat at whatever it last computed.
func _base_for(stat: StringName, definition: StatDefinition) -> float:
	if definition == null or definition.derivation == null or definition.derivation.is_empty():
		return _bases[stat]

	# A cycle that got past validation would recurse forever. Returning the
	# authored base breaks it with a number rather than a crash, and content
	# validation is where the author is told about it.
	if _deriving.has(stat):
		return _bases[stat]

	_deriving[stat] = true
	var values: Dictionary = {}
	for source in definition.derivation.sources:
		if _bases.has(source):
			values[source] = get_value(source)
	_deriving.erase(stat)
	return definition.derivation.evaluate(values)


func has_stat(stat: StringName) -> bool:
	return _bases.has(stat)


func get_stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_bases.keys())
	return ids


## The unmodified base of a stat.
func get_base(stat: StringName, fallback: float = 0.0) -> float:
	return _bases.get(stat, fallback)


## Sets a base value. For progression -- levelling strength -- not for
## temporary effects, which are modifiers.
func set_base(stat: StringName, value: float) -> void:
	if not _bases.has(stat):
		return
	if is_equal_approx(_bases[stat], value):
		return
	_bases[stat] = value
	_invalidate(stat)


## Current value of a depletable stat, or its computed value when it is not
## depletable -- so a caller that does not care about the distinction can read
## either through one method.
func get_current(stat: StringName, fallback: float = 0.0) -> float:
	if _current.has(stat):
		return _current[stat]
	return get_value(stat, fallback)


func is_depletable(stat: StringName) -> bool:
	return _current.has(stat)


## Current value as a fraction of maximum, 0 to 1. The number a bar wants.
func get_fraction(stat: StringName) -> float:
	var maximum := get_value(stat)
	if maximum <= 0.0:
		return 0.0
	return clampf(get_current(stat) / maximum, 0.0, 1.0)


func is_depleted(stat: StringName) -> bool:
	return _current.has(stat) and is_zero_approx(_current[stat])


## Human-readable breakdown of how a value was reached (rule 28).
func explain(stat: StringName) -> String:
	if not _bases.has(stat):
		return "%s: not a stat of this entity" % stat
	var definition := _profile.get_definition(stat) if _profile != null else null
	return StatCalculator.explain(
		_bases[stat],
		_modifiers,
		stat,
		definition.get_minimum() if definition != null else -INF,
		definition.get_maximum() if definition != null else INF
	)


# --- Modifiers ------------------------------------------------------------

## Applies a modifier. A modifier for a stat this entity does not have is
## accepted and inert, so an effect can be written once and applied to
## anything.
func add_modifier(modifier: StatModifier) -> FrameworkResult:
	if modifier == null:
		return FrameworkResult.fail(
			&"stats.null_modifier", "Cannot add a null modifier."
		)
	_modifiers.append(modifier)
	_invalidate(modifier.stat)
	modifiers_changed.emit()
	return FrameworkResult.ok(modifier)


func add_modifiers(modifiers: Array) -> void:
	var touched: Array[StringName] = []
	for entry in modifiers:
		var modifier := entry as StatModifier
		if modifier == null:
			continue
		_modifiers.append(modifier)
		if not touched.has(modifier.stat):
			touched.append(modifier.stat)
	for stat in touched:
		_invalidate(stat)
	if not touched.is_empty():
		modifiers_changed.emit()


## Removes every modifier applied by [param source]. Returns how many went.
##
## The only removal the framework offers, deliberately: an effect takes back
## what it added, all of it, without having to hold references to the
## individual modifiers it applied.
func remove_modifiers_from(source: StringName) -> int:
	var touched: Array[StringName] = []
	var removed := 0
	for index in range(_modifiers.size() - 1, -1, -1):
		if _modifiers[index].source != source:
			continue
		if not touched.has(_modifiers[index].stat):
			touched.append(_modifiers[index].stat)
		_modifiers.remove_at(index)
		removed += 1
	for stat in touched:
		_invalidate(stat)
	if removed > 0:
		modifiers_changed.emit()
	return removed


func has_modifiers_from(source: StringName) -> bool:
	for modifier in _modifiers:
		if modifier.source == source:
			return true
	return false


func get_modifiers() -> Array[StatModifier]:
	return _modifiers.duplicate()


func get_modifiers_for(stat: StringName) -> Array[StatModifier]:
	return StatCalculator.collect_for(_modifiers, stat)


func clear_modifiers() -> void:
	if _modifiers.is_empty():
		return
	var touched := StatCalculator.affected_stats(_modifiers)
	_modifiers.clear()
	for stat in touched:
		_invalidate(stat)
	modifiers_changed.emit()


# --- Depletion ------------------------------------------------------------

## Spends from a depletable stat. Returns how much was actually spent, which
## is less than asked for when there was not enough.
func spend(stat: StringName, amount: float) -> float:
	if not _current.has(stat) or amount <= 0.0:
		return 0.0
	var available: float = _current[stat]
	var spent := minf(available, amount)
	if spent <= 0.0:
		return 0.0
	_set_current(stat, available - spent)
	_since_spent[stat] = 0.0
	return spent


## Whether a depletable stat has at least [param amount] available. Ask before
## spending when the action should be refused outright rather than partially
## paid for (rule 17).
func can_spend(stat: StringName, amount: float) -> bool:
	return _current.has(stat) and _current[stat] >= amount


func restore(stat: StringName, amount: float) -> float:
	if not _current.has(stat) or amount <= 0.0:
		return 0.0
	var maximum := get_value(stat)
	var before: float = _current[stat]
	var after := minf(maximum, before + amount)
	if is_equal_approx(before, after):
		return 0.0
	_set_current(stat, after)
	return after - before


func refill(stat: StringName) -> void:
	if _current.has(stat):
		_set_current(stat, get_value(stat))


func refill_all() -> void:
	for stat in _current.keys():
		_set_current(stat, get_value(stat))


# --- Tick -----------------------------------------------------------------

## Advances regeneration. Public so a networked authority or a test can own the
## timing.
func tick(delta: float) -> void:
	if delta <= 0.0 or _profile == null:
		return
	for stat in _current.keys():
		var definition := _profile.get_definition(stat)
		if definition == null or not definition.regenerates():
			continue
		var maximum := get_value(stat)
		if _current[stat] >= maximum:
			continue
		var regen_delta := delta
		var waited: float = _since_spent.get(stat, definition.regen_delay)
		if waited < definition.regen_delay:
			waited += delta
			_since_spent[stat] = waited
			# Spend only the part of the frame that fell after the delay
			# elapsed. Dropping the whole frame instead would lose up to one
			# frame of regeneration every time it resumed, which at a short
			# delay and a long frame is most of it.
			regen_delta = waited - definition.regen_delay
			if regen_delta <= 0.0:
				continue
		_set_current(
			stat, minf(maximum, _current[stat] + definition.regen_per_second * regen_delta)
		)


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


## Saves bases and current values, not modifiers.
##
## Modifiers come from status effects and equipment, and those modules restore
## their own state and reapply. Persisting them here too would double every
## buff on load -- the classic save bug where a character comes back stronger
## every time (rule 4: one owner per fact).
func capture_state() -> Dictionary:
	return {
		"bases": _bases.duplicate(),
		"current": _current.duplicate(),
	}


func restore_state(data: Dictionary) -> void:
	var bases: Dictionary = data.get("bases", {})
	for stat in bases:
		var id := StringName(stat)
		if _bases.has(id):
			_bases[id] = float(bases[stat])
	_cache.clear()

	var current: Dictionary = data.get("current", {})
	for stat in current:
		var id := StringName(stat)
		if _current.has(id):
			_current[id] = clampf(float(current[stat]), 0.0, get_value(id))


# --- Internals ------------------------------------------------------------

## Read by property name rather than by casting to a character definition, so
## a vehicle or a destructible with its own definition type can carry stats
## without Stats importing another module's types (rule 9).
func _resolve_profile() -> StatsProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "stats" in definition:
		var candidate: Variant = definition.get("stats")
		if candidate is StatsProfile:
			return candidate as StatsProfile
	return null


func _rebuild_from_profile() -> void:
	_bases.clear()
	_current.clear()
	_since_spent.clear()
	_cache.clear()
	_modifiers.clear()
	if _profile == null:
		return

	for definition in _profile.stats:
		if definition == null or definition.id == &"":
			continue
		_bases[definition.id] = _profile.get_base(definition.id)

	for modifier in _profile.innate_modifiers:
		if modifier != null:
			_modifiers.append(modifier)

	# Current values are seeded after modifiers, so a stat whose maximum is
	# raised by an innate modifier starts full at the raised value rather than
	# at its unmodified base.
	for definition in _profile.stats:
		if definition == null or not definition.depletable:
			continue
		var maximum := get_value(definition.id)
		_current[definition.id] = maximum if definition.starts_full else definition.get_minimum()
		_since_spent[definition.id] = definition.regen_delay


func _has_regenerating_stat() -> bool:
	if _profile == null:
		return false
	for definition in _profile.stats:
		if definition != null and definition.regenerates():
			return true
	return false


## Drops the cached value and announces the change.
##
## Also re-clamps any current value: raising max stamina should not leave the
## bar reading full at the old number, and lowering it must not leave the
## current value above the new maximum.
func _invalidate(stat: StringName) -> void:
	if stat == &"" or not _bases.has(stat):
		return
	var previous := _cache.get(stat, NAN) as float
	_cache.erase(stat)
	var value := get_value(stat)
	if _current.has(stat) and _current[stat] > value:
		_set_current(stat, value)
	if is_nan(previous) or not is_equal_approx(previous, value):
		stat_changed.emit(stat, value, previous if not is_nan(previous) else value)

	# Anything derived from this one is now stale. Without this, raising
	# strength leaves carry weight reading its old value until something else
	# happens to clear the cache -- a bug that looks like the derivation not
	# working, intermittently.
	for dependent in _dependents.get(stat, []):
		if dependent != stat:
			_invalidate(dependent)


func _set_current(stat: StringName, value: float) -> void:
	var maximum := get_value(stat)
	var clamped := clampf(value, 0.0, maximum)
	var before: float = _current[stat]
	if is_equal_approx(before, clamped):
		return
	_current[stat] = clamped
	if is_zero_approx(clamped) and not is_zero_approx(before):
		stat_depleted.emit(stat)
	elif is_equal_approx(clamped, maximum) and not is_equal_approx(before, maximum):
		stat_replenished.emit(stat)
