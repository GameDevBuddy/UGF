class_name CombatAuthorityAdapter
extends Node
## Puts the server in front of the trigger.
##
## [b]Combat did not change for this either.[/b] [method CombatComponent.attack]
## already existed and already returned a [FrameworkResult]; this registers a
## handler that calls it. Every milestone's mutation API turns out to be the
## networking API, which is the payoff for having insisted on them.
##
## [b]What the server owns is the *result*, not the input.[/b] Aiming is
## client-side and must be: a shooter where turning waits for a round trip is
## unplayable. What crosses the wire is "I fired", and the server decides
## whether that hit — which is the distinction Implementation Plan 27 draws by
## calling combat *results* authority-owned.

## Where handlers are registered. Resolved from the core when not wired.
@export var authority: NetworkAuthority

## Shortest gap between two attacks from one actor, as a fraction of the
## weapon's own rate of fire. Below one allows for latency jitter; at one a
## client whose clock runs a millisecond fast is refused every other shot.
@export_range(0.1, 1.0, 0.01) var rate_tolerance: float = 0.8

var _registered: Array[StringName] = []
## Actor network id to when they last fired, in engine milliseconds.
var _last_attack: Dictionary[StringName, int] = {}


func _ready() -> void:
	install()


func _exit_tree() -> void:
	uninstall()


func install() -> void:
	if authority == null:
		return
	_register(&"combat.attack", _attack)
	_register(&"combat.reload", _reload)
	authority.register_validator(&"combat.attack", _validate_rate)


func uninstall() -> void:
	if authority == null:
		return
	for verb in _registered:
		authority.unregister_handler(verb)
	_registered.clear()
	_last_attack.clear()


func get_registered_verbs() -> Array[StringName]:
	return _registered.duplicate()


# --- Handlers -------------------------------------------------------------

func _attack(intent: NetworkIntent) -> FrameworkResult:
	var combat := _combat_of(authority.find_entity(intent.actor_id))
	if combat == null:
		return FrameworkResult.fail(&"combat.no_component", "They cannot attack.")
	_last_attack[intent.actor_id] = Time.get_ticks_msec()
	return combat.attack(bool(intent.get_argument(&"secondary", false)))


func _reload(intent: NetworkIntent) -> FrameworkResult:
	var combat := _combat_of(authority.find_entity(intent.actor_id))
	if combat == null or combat.weapon == null:
		return FrameworkResult.fail(&"combat.no_weapon", "They have nothing to reload.")
	return combat.weapon.reload()


# --- Validation -----------------------------------------------------------

## Refuses shots arriving faster than the weapon can fire them.
##
## The single most valuable server-side check in a shooter: a modified client
## sending attack forty times a frame is otherwise indistinguishable from a
## fast trigger finger, and [CombatComponent]'s own rate limit runs on the
## machine that was modified.
func _validate_rate(intent: NetworkIntent) -> FrameworkResult:
	var combat := _combat_of(authority.find_entity(intent.actor_id))
	if combat == null:
		return FrameworkResult.ok(intent)
	var minimum := get_minimum_interval(
		combat, bool(intent.get_argument(&"secondary", false))
	)
	if minimum <= 0.0:
		return FrameworkResult.ok(intent)

	# Typed explicitly: Dictionary.get() returns a Variant, so the subtraction
	# has no inferable type and the whole file fails to compile.
	var last: int = _last_attack.get(intent.actor_id, -100000)
	var since := Time.get_ticks_msec() - last
	var allowed := int(minimum * 1000.0 * rate_tolerance)
	if since < allowed:
		return FrameworkResult.fail(
			&"combat.too_fast",
			"That shot arrived %dms after the last; %dms is the minimum." % [since, allowed]
		)
	return FrameworkResult.ok(intent)


## Shortest time between two shots, in seconds.
##
## A weapon's own rate wins where there is one, because that is the number the
## component enforces locally and the two must agree. Falling back to the
## attack's phases covers unarmed and melee, where the swing itself is the
## rate limit. Zero means the attack has no timing at all and nothing here can
## be checked -- reported honestly rather than guessed at.
func get_minimum_interval(combat: CombatComponent, secondary: bool = false) -> float:
	var weapon := combat.weapon
	if weapon != null and weapon.has_weapon():
		var profile := weapon.get_profile()
		if profile != null and profile.rate_per_second > 0.0:
			return 1.0 / profile.rate_per_second
	var definition := combat.get_attack(secondary)
	if definition == null:
		return 0.0
	return definition.startup + definition.active + definition.recovery


# --- Internals ------------------------------------------------------------

func _register(verb: StringName, handler: Callable) -> void:
	if authority.register_handler(verb, handler).is_ok():
		_registered.append(verb)


func _combat_of(entity: Node) -> CombatComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is CombatComponent:
			return component as CombatComponent
	return null
