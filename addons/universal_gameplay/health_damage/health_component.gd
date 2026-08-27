class_name HealthComponent
extends FrameworkComponent
## The capability of being alive, and of stopping.
##
## Owns current health and nothing else. Mitigation belongs to
## [DamageReceiverComponent], the maximum can come from [StatsComponent], and
## publishing the death to the rest of the game belongs to
## [HealthEventAdapter]. Each of those is a separate concern with a separate
## owner (rule 4), and health's is the single number that says whether this
## entity is still standing.
##
## [b]It emits a local signal and touches no bus.[/b] This is the component the
## two source documents disagree about -- Implementation Plan 45 has it publish
## [code]EventBus.actor_died[/code] directly -- and the framework takes the
## Rulebook's side. A component that reaches for an autoload cannot be built in
## a unit test, and promoting a local fact to a cross-feature one is a decision
## that belongs at a seam that can be removed. See [HealthEventAdapter], which
## is that seam.

## Emitted whenever current health changes, for any reason.
signal health_changed(current: float, maximum: float)
## Emitted once when health reaches zero. Carries the killing context, which is
## null for a death with no damage cause.
signal died(context: DamageContext)
## Emitted when something brings a dead entity back.
signal revived
## Emitted when damage arrives but is fully absorbed. A zero-damage hit still
## happened, and armour that silently eats a shot feels broken without a cue.
signal damage_absorbed(context: DamageContext)

## Maximum health when no stat supplies one.
@export var maximum_health: float = 100.0

## Stat id read for the maximum when a [StatsComponent] is wired up. Blank uses
## [member maximum_health].
@export var maximum_stat: StringName = &"stat.health.max"

## Optional stats source for the maximum, wired at composition time (rule 20).
## Absent, the exported maximum is used and nothing is broken by it.
@export var stats: StatsComponent

## Start at full. Off starts the entity damaged, which is what a wreck or a
## wounded NPC wants without a script to hurt it on spawn.
@export var starts_full: bool = true

## Whether this entity can be damaged at all. Scenery and cutscene actors set
## it false; it is not the same as being immune to a tag.
@export var damageable: bool = true

var _current: float = 0.0
var _dead: bool = false
var _initialised_health: bool = false


func initialize(context: EntityContext) -> void:
	super(context)
	if not _initialised_health:
		_current = get_maximum() if starts_full else _current
		_initialised_health = true
	if stats != null and not stats.stat_changed.is_connected(_on_stat_changed):
		stats.stat_changed.connect(_on_stat_changed)
	if get_entity() != null and get_entity().is_inside_tree():
		get_entity().add_to_group(GameplayNames.GROUP_DAMAGEABLE)


func _exit_tree() -> void:
	if stats != null and stats.stat_changed.is_connected(_on_stat_changed):
		stats.stat_changed.disconnect(_on_stat_changed)


# --- Queries --------------------------------------------------------------

func get_current() -> float:
	return _current


## Maximum health: the stat when one is available, else the exported value.
func get_maximum() -> float:
	if stats != null and maximum_stat != &"" and stats.has_stat(maximum_stat):
		return stats.get_value(maximum_stat, maximum_health)
	return maximum_health


## Health as a fraction of maximum, 0 to 1. What a health bar wants.
func get_fraction() -> float:
	var maximum := get_maximum()
	if maximum <= 0.0:
		return 0.0
	return clampf(_current / maximum, 0.0, 1.0)


func is_alive() -> bool:
	return not _dead


func is_dead() -> bool:
	return _dead


func is_full() -> bool:
	return is_equal_approx(_current, get_maximum())


# --- Commands -------------------------------------------------------------

## Applies a already-mitigated damage context.
##
## Takes the context rather than a bare amount so there is one source of truth
## for the number and so death carries its cause. Mitigation has happened by
## this point: this method subtracts, it does not negotiate.
func apply_damage(context: DamageContext) -> FrameworkResult:
	if context == null:
		return FrameworkResult.fail(&"health.null_context", "Cannot apply null damage.")
	if not damageable:
		return FrameworkResult.fail(
			&"health.not_damageable", "This entity cannot be damaged."
		)
	if _dead:
		return FrameworkResult.fail(
			&"health.already_dead", "This entity is already dead."
		)

	var landed := maxf(0.0, context.final_amount)
	if landed <= 0.0:
		damage_absorbed.emit(context)
		return FrameworkResult.ok(0.0)

	var before := _current
	_current = maxf(0.0, _current - landed)
	context.final_amount = before - _current
	context.was_lethal = is_zero_approx(_current)

	health_changed.emit(_current, get_maximum())
	if context.was_lethal:
		_die(context)
	return FrameworkResult.ok(context.final_amount)


## Restores health. Returns how much was actually restored, which is less than
## asked for at full health and zero when dead -- healing does not revive.
func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var maximum := get_maximum()
	var before := _current
	_current = minf(maximum, _current + amount)
	if is_equal_approx(before, _current):
		return 0.0
	health_changed.emit(_current, maximum)
	return _current - before


func set_current(value: float) -> void:
	var maximum := get_maximum()
	var clamped := clampf(value, 0.0, maximum)
	if is_equal_approx(clamped, _current):
		return
	_current = clamped
	health_changed.emit(_current, maximum)
	if is_zero_approx(_current) and not _dead:
		_die(null)


## Kills outright, bypassing mitigation. For scripted deaths, falls, and
## survival needs bottoming out -- causes with no damage behind them.
func kill(context: DamageContext = null) -> FrameworkResult:
	if _dead:
		return FrameworkResult.fail(
			&"health.already_dead", "This entity is already dead."
		)
	_current = 0.0
	health_changed.emit(_current, get_maximum())
	_die(context)
	return FrameworkResult.ok(null)


## Brings a dead entity back with [param fraction] of its maximum.
func revive(fraction: float = 1.0) -> FrameworkResult:
	if not _dead:
		return FrameworkResult.fail(&"health.not_dead", "This entity is not dead.")
	_dead = false
	_current = maxf(1.0, get_maximum() * clampf(fraction, 0.0, 1.0))
	_set_dead_state(false)
	health_changed.emit(_current, get_maximum())
	revived.emit()
	return FrameworkResult.ok(_current)


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"current": _current, "dead": _dead}


func restore_state(data: Dictionary) -> void:
	_initialised_health = true
	_dead = bool(data.get("dead", false))
	_current = clampf(float(data.get("current", get_maximum())), 0.0, get_maximum())
	_set_dead_state(_dead)


# --- Internals ------------------------------------------------------------

func _die(context: DamageContext) -> void:
	if _dead:
		return
	_dead = true
	_set_dead_state(true)
	died.emit(context)


## Mirrors death onto the entity's semantic state, if it has one.
##
## The tag advertises what this component owns; it is not a second authority on
## whether the entity is dead (rule 4). Found through the binder rather than
## exported, because unlike movement's stance this is a fact the whole entity
## cares about and every entity root that has one has exactly one.
func _set_dead_state(dead: bool) -> void:
	var entity := get_entity()
	if entity == null:
		return
	for component in DefinitionBinder.collect_components(entity):
		if component is SemanticState:
			(component as SemanticState).set_state(GameplayNames.STATE_DEAD, dead)
			return


## Re-clamps when the maximum changes underneath us.
##
## Losing a +50 max health buff must not leave a character above their new
## maximum. Gaining one deliberately does [i]not[/i] heal: raising the ceiling
## and filling the room are different decisions, and conflating them makes
## every buff a free heal.
func _on_stat_changed(stat: StringName, _value: float, _previous: float) -> void:
	if stat != maximum_stat:
		return
	var maximum := get_maximum()
	if _current > maximum:
		_current = maximum
		health_changed.emit(_current, maximum)
