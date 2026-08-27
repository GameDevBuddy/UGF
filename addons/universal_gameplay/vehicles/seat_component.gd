class_name SeatComponent
extends FrameworkComponent
## Who is in which seat. The one authority on occupancy (rule 4).
##
## Split from [VehicleComponent] on purpose: that one owns how the vehicle
## moves, this one owns who is aboard, and the split is what lets a trailer, a
## lift and a horse have seats without having handling. Every entry is
## validate-then-mutate — a refusal leaves nobody half in a seat (rule 17).

## Emitted after somebody sits down.
signal occupant_entered(occupant: Node, seat: SeatDefinition)
## Emitted after somebody gets out.
signal occupant_exited(occupant: Node, seat: SeatDefinition)
## Emitted when entry was refused, so a prompt can say why.
signal entry_refused(occupant: Node, seat_id: StringName, reason: StringName)

## Seats this vehicle has. Takes precedence over the definition's.
@export var seats_override: Array[SeatDefinition] = []

## States mirrored while somebody is aboard. Found among this entity's own
## components when not wired.
@export var semantic_state: SemanticState

## Seats occupants must be able to reach. Absent, anybody can enter from
## anywhere, which is what a scripted sequence and a test want.
@export_range(0.0, 100.0, 0.1, "or_greater") var entry_range: float = 0.0

var _seats: Dictionary[StringName, SeatDefinition] = {}
## Seat id to occupant. The forward map; the reverse is derived rather than
## stored, because two maps that can disagree is two owners of one fact.
var _occupants: Dictionary[StringName, Node] = {}
## Ids from a restore that have not been turned back into entities yet. A save
## records who was aboard; putting them back needs the world rebuilt first.
var _pending: Dictionary[StringName, StringName] = {}


func initialize(context: EntityContext) -> void:
	super(context)
	_resolve_seats()
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState


# --- Queries --------------------------------------------------------------

func get_seats() -> Array[SeatDefinition]:
	var found: Array[SeatDefinition] = []
	found.assign(_seats.values())
	return found


func get_seat(seat_id: StringName) -> SeatDefinition:
	return _seats.get(seat_id)


func has_seat(seat_id: StringName) -> bool:
	return _seats.has(seat_id)


func get_seat_count() -> int:
	return _seats.size()


func get_occupant(seat_id: StringName) -> Node:
	var occupant: Node = _occupants.get(seat_id)
	return occupant if occupant != null and is_instance_valid(occupant) else null


func get_occupants() -> Array[Node]:
	var found: Array[Node] = []
	for seat_id in _occupants:
		var occupant := get_occupant(seat_id)
		if occupant != null:
			found.append(occupant)
	return found


func get_occupant_count() -> int:
	return get_occupants().size()


func is_empty() -> bool:
	return get_occupant_count() == 0


func is_occupied(seat_id: StringName) -> bool:
	return get_occupant(seat_id) != null


## Which seat somebody is in, or blank. The derived reverse lookup.
func get_seat_of(occupant: Node) -> StringName:
	if occupant == null:
		return &""
	for seat_id in _occupants:
		if _occupants[seat_id] == occupant:
			return seat_id
	return &""


func contains(occupant: Node) -> bool:
	return get_seat_of(occupant) != &""


func get_driver() -> Node:
	for seat_id in _seats:
		if _seats[seat_id].is_driver():
			var driver := get_occupant(seat_id)
			if driver != null:
				return driver
	return null


func has_driver() -> bool:
	return get_driver() != null


## The first free seat somebody could take, driver's seat first. What "press E
## on the car" resolves to when the player did not name a seat.
func find_free_seat(occupant: Node = null) -> SeatDefinition:
	var driver_seat := _driver_seat()
	if driver_seat != null and can_enter(occupant, driver_seat.id).is_ok():
		return driver_seat
	for seat_id in _seats:
		if can_enter(occupant, seat_id).is_ok():
			return _seats[seat_id]
	return null


# --- Entering and leaving -------------------------------------------------

## Whether [param occupant] could take [param seat_id] right now.
##
## Public and side-effect free, so a prompt can be greyed out rather than the
## player pressing a button and being told no.
func can_enter(occupant: Node, seat_id: StringName) -> FrameworkResult:
	if occupant == null:
		return FrameworkResult.fail(&"seat.no_occupant", "There is nobody to seat.")
	var seat := get_seat(seat_id)
	if seat == null:
		return FrameworkResult.fail(&"seat.no_such_seat", "There is no such seat.")
	if not seat.enabled:
		return FrameworkResult.fail(
			&"seat.disabled", "%s cannot be used." % seat.get_debug_name()
		)
	if is_occupied(seat_id):
		return FrameworkResult.fail(&"seat.occupied", "Somebody is already sitting there.")
	if contains(occupant):
		return FrameworkResult.fail(&"seat.already_aboard", "They are already aboard.")
	if not _in_range(occupant):
		return FrameworkResult.fail(&"seat.out_of_reach", "That is too far away.")

	for requirement in seat.requirements:
		if requirement == null:
			continue
		var context := InteractionContext.create(occupant, get_entity())
		var checked := requirement.check(context)
		if checked.is_err():
			return checked
	return FrameworkResult.ok(seat)


## Puts somebody in a seat. Returns the [SeatDefinition] they took.
func enter(occupant: Node, seat_id: StringName = &"") -> FrameworkResult:
	var target := seat_id
	if target == &"":
		var free := find_free_seat(occupant)
		if free == null:
			entry_refused.emit(occupant, &"", &"seat.full")
			return FrameworkResult.fail(&"seat.full", "There is nowhere to sit.")
		target = free.id

	var allowed := can_enter(occupant, target)
	if allowed.is_err():
		entry_refused.emit(occupant, target, allowed.code)
		return allowed

	var seat: SeatDefinition = allowed.payload
	_occupants[target] = occupant
	_set_state(GameplayNames.STATE_OCCUPIED, true)
	occupant_entered.emit(occupant, seat)
	return FrameworkResult.ok(seat)


## Takes somebody out. Returns the seat they were in.
func exit(occupant: Node) -> FrameworkResult:
	var seat_id := get_seat_of(occupant)
	if seat_id == &"":
		return FrameworkResult.fail(&"seat.not_aboard", "They are not aboard.")
	var seat := get_seat(seat_id)
	_occupants.erase(seat_id)
	_set_state(GameplayNames.STATE_OCCUPIED, not is_empty())
	occupant_exited.emit(occupant, seat)
	return FrameworkResult.ok(seat)


## Empties every seat. What a destroyed vehicle and a world reset call.
func eject_all(_reason: StringName = &"ejected") -> Array[Node]:
	var ejected: Array[Node] = []
	for occupant in get_occupants():
		if exit(occupant).is_ok():
			ejected.append(occupant)
	# Occupants that were freed out from under us leave stale entries behind;
	# clearing is what stops a destroyed car reporting a ghost passenger.
	_occupants.clear()
	_set_state(GameplayNames.STATE_OCCUPIED, false)
	return ejected


## Where an occupant is put down on getting out, in world space. Falls back to
## the vehicle's own position when it is not a spatial node.
func get_exit_position(seat_id: StringName) -> Vector3:
	var seat := get_seat(seat_id)
	var origin := get_entity() as Node3D
	if origin == null or not origin.is_inside_tree():
		return seat.exit_offset if seat != null else Vector3.ZERO
	if seat == null:
		return origin.global_position
	return origin.global_transform * seat.exit_offset


# --- Persistence ----------------------------------------------------------
#
# Occupancy is recorded by the occupant's persistent id, never by node path or
# instance: a save reloaded into a rebuilt scene has different nodes, and the
# whole point of rule 32 is that ids survive that.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var saved: Dictionary = {}
	for seat_id in _occupants:
		var occupant := get_occupant(seat_id)
		var id := _identity_of(occupant)
		if id != &"":
			saved[String(seat_id)] = String(id)
	return {"occupants": saved}


## Records who was aboard, without seating anybody.
##
## [b]Restoring occupancy is two steps and cannot be one.[/b] A save holds ids;
## the entities those ids name may not exist yet when the vehicle is restored,
## because load order is a spawn service's business and not a seat's. Seating a
## node this component cannot see would mean inventing one. So the ids are
## parked, and [method resolve_pending] seats each occupant as it comes back.
## A seat holding an id it never resolves stays empty, which is a state
## everything downstream already handles.
func restore_state(data: Dictionary) -> void:
	_pending = {}
	for key in data.get("occupants", {}):
		_pending[StringName(key)] = StringName(data["occupants"][key])


func get_pending_occupants() -> Dictionary:
	return _pending.duplicate()


## Seats a restored occupant, matching the id recorded in the save.
func resolve_pending(occupant: Node) -> FrameworkResult:
	var id := _identity_of(occupant)
	if id == &"":
		return FrameworkResult.fail(
			&"seat.no_identity", "That entity has no persistent id to match."
		)
	for seat_id in _pending:
		if _pending[seat_id] == id:
			var seated := enter(occupant, seat_id)
			if seated.is_ok():
				_pending.erase(seat_id)
			return seated
	return FrameworkResult.fail(
		&"seat.not_expected", "No restored seat was waiting for that entity."
	)


# --- Internals ------------------------------------------------------------

func _driver_seat() -> SeatDefinition:
	for seat_id in _seats:
		if _seats[seat_id].is_driver():
			return _seats[seat_id]
	return null


func _in_range(occupant: Node) -> bool:
	if entry_range <= 0.0:
		return true
	var here := get_entity() as Node3D
	var there := occupant as Node3D
	if here == null or there == null:
		return true
	if not here.is_inside_tree() or not there.is_inside_tree():
		return true
	return here.global_position.distance_to(there.global_position) <= entry_range


func _identity_of(node: Node) -> StringName:
	if node == null:
		return &""
	for component in DefinitionBinder.collect_components(node):
		if component is PersistentIdentity:
			return (component as PersistentIdentity).get_persistent_id()
	return &""


func _set_state(state: StringName, active: bool) -> void:
	if semantic_state != null:
		semantic_state.set_state(state, active)


## Read by property name rather than by casting, so a lift or a horse with its
## own definition type can have seats (rule 9).
func _resolve_seats() -> void:
	_seats.clear()
	var source: Array = seats_override
	if source.is_empty():
		var definition := get_definition()
		if definition != null and "seats" in definition:
			var candidate: Variant = definition.get("seats")
			if candidate is Array:
				source = candidate as Array
	for entry in source:
		if entry is SeatDefinition and (entry as SeatDefinition).id != &"":
			_seats[(entry as SeatDefinition).id] = entry


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
