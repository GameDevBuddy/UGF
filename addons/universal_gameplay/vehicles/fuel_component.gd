class_name FuelComponent
extends FrameworkComponent
## What is in the tank.
##
## Its own component rather than a field on [VehicleComponent], because a
## generator, a chainsaw and a lantern burn fuel and do not drive, and a
## bicycle drives and does not burn fuel. Either without the other is a valid
## entity (rule 4, rule 31).
##
## Deliberately close in shape to [NeedsComponent] — a meter, a low band, a
## signal when it empties — but not the same class. A need decays on a clock
## and hurts when empty; fuel is spent by work and stops an engine. Sharing the
## implementation would mean one of them carrying the other's fields
## (rule 23).

## Emitted whenever the level changes.
signal fuel_changed(level: float, previous: float)
## Emitted when the level crosses into or out of the low band.
signal fuel_low(low: bool)
## Emitted when the tank runs dry.
signal fuel_emptied

## Tank size. Takes precedence over the definition's.
@export_range(0.0, 1000.0, 0.1, "or_greater") var capacity_override: float = 0.0

## Fraction at or below which the tank is "low": the warning light.
@export_range(0.0, 1.0, 0.01) var low_fraction: float = 0.15

var _capacity: float = 0.0
var _level: float = 0.0
var _low: bool = false
var _seeded: bool = false


func initialize(context: EntityContext) -> void:
	super(context)
	_resolve_capacity()
	if not _seeded:
		_level = _starting_level()
		_low = is_low()
		_seeded = true


# --- Queries --------------------------------------------------------------

func get_capacity() -> float:
	return _capacity


func get_level() -> float:
	return _level


func get_fraction() -> float:
	if _capacity <= 0.0:
		return 1.0
	return clampf(_level / _capacity, 0.0, 1.0)


func is_low() -> bool:
	return has_tank() and get_fraction() <= low_fraction


func is_empty() -> bool:
	return has_tank() and _level <= 0.0


## Whether this entity burns fuel at all. A vehicle with no tank is not broken
## — it is a bicycle, and every call here is a no-op that reports success.
func has_tank() -> bool:
	return _capacity > 0.0


func is_full() -> bool:
	return not has_tank() or _level >= _capacity


func get_free_space() -> float:
	return maxf(0.0, _capacity - _level) if has_tank() else 0.0


# --- Changing -------------------------------------------------------------

## Burns fuel. Returns how much was actually taken, which is less than asked
## for when the tank runs out mid-step.
func consume(amount: float) -> float:
	if not has_tank() or amount <= 0.0:
		return 0.0
	var taken := minf(amount, _level)
	_set_level(_level - taken)
	return taken


## Adds fuel. Returns how much went in — a jerrycan poured into a nearly full
## tank does not all fit, and the caller needs to know how much is left in it.
func refuel(amount: float) -> float:
	if not has_tank() or amount <= 0.0:
		return 0.0
	var added := minf(amount, get_free_space())
	_set_level(_level + added)
	return added


func fill() -> void:
	if has_tank():
		_set_level(_capacity)
	else:
		_seeded = true


func drain() -> void:
	_set_level(0.0)


func set_level(value: float) -> void:
	_set_level(value)


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"fuel": _level}


func restore_state(data: Dictionary) -> void:
	_set_level(float(data.get("fuel", _level)))
	# A restored vehicle must not be refilled by the next initialize, which is
	# how reloading a save becomes free petrol.
	_seeded = true


# --- Internals ------------------------------------------------------------

func _set_level(value: float) -> void:
	var clamped := clampf(value, 0.0, maxf(_capacity, 0.0))
	if is_equal_approx(clamped, _level) and _seeded:
		return
	var previous := _level
	_level = clamped
	fuel_changed.emit(_level, previous)

	var low := is_low()
	if low != _low:
		_low = low
		fuel_low.emit(low)
	if _level <= 0.0 and previous > 0.0:
		fuel_emptied.emit()


func _starting_level() -> float:
	# has_method rather than `in`: the `in` operator tests properties, and a
	# method is not one -- so `"get_starting_fuel" in definition` is false on
	# the very definition that declares it.
	var definition := get_definition()
	if definition != null and definition.has_method("get_starting_fuel"):
		var starting: Variant = definition.call("get_starting_fuel")
		if starting is float:
			return clampf(starting as float, 0.0, _capacity)
	return _capacity


## Read by property name rather than by casting, so a generator with its own
## definition type can have a tank (rule 9).
func _resolve_capacity() -> void:
	if capacity_override > 0.0:
		_capacity = capacity_override
		return
	var definition := get_definition()
	if definition != null and "fuel_capacity" in definition:
		var candidate: Variant = definition.get("fuel_capacity")
		if candidate is float:
			_capacity = maxf(0.0, candidate as float)
