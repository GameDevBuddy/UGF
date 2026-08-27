class_name InventoryComponent
extends FrameworkComponent
## The capability of carrying things.
##
## One container on one entity: a backpack, a chest, a vehicle boot, a vendor's
## stock. Which of those it is comes from its [InventoryProfile], not from a
## subclass (rule 11) — Implementation Plan 22 reuses this same component for
## vehicle storage for exactly that reason.
##
## [b]Every mutation is atomic.[/b] An operation validates the whole thing
## before changing anything, so a transfer that will not fit leaves both
## containers untouched rather than half-moving a stack and failing (rule 17).
## The alternative — mutate as you go and bail on the first problem — is how
## items get duplicated and destroyed, and neither is recoverable once a save
## is written.

## Emitted when items arrive, with the instance now held.
signal item_added(instance: ItemInstance, quantity: int)
## Emitted when items leave. The instance may already be exhausted.
signal item_removed(definition_id: StringName, quantity: int)
## Emitted after any change, for a UI that only wants to know it is stale.
signal contents_changed
## Emitted when wearing an item destroyed it, carrying what was lost.
signal item_broke(definition_id: StringName)

## Capacity and filters. Takes precedence over the definition's profile.
@export var profile_override: InventoryProfile

var _profile: InventoryProfile = null
var _items: Array[ItemInstance] = []


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()


# --- Queries --------------------------------------------------------------

func get_profile() -> InventoryProfile:
	return _profile


func get_items() -> Array[ItemInstance]:
	return _items.duplicate()


func get_used_slots() -> int:
	return _items.size()


## Free stacks, or -1 when the container has no slot limit.
func get_free_slots() -> int:
	if _profile == null or not _profile.has_slot_limit():
		return -1
	return maxi(0, _profile.slot_count - _items.size())


func get_total_weight() -> float:
	var total := 0.0
	for instance in _items:
		total += instance.get_total_weight()
	return total


func get_total_value() -> float:
	var total := 0.0
	for instance in _items:
		total += instance.get_total_value()
	return total


func is_empty() -> bool:
	return _items.is_empty()


## How many units of an item this holds, across every stack.
func count(definition_id: StringName) -> int:
	var total := 0
	for instance in _items:
		if instance.get_definition_id() == definition_id:
			total += instance.quantity
	return total


func has(definition_id: StringName, quantity: int = 1) -> bool:
	return count(definition_id) >= quantity


## The first stack of an item, or null.
func find(definition_id: StringName) -> ItemInstance:
	for instance in _items:
		if instance.get_definition_id() == definition_id:
			return instance
	return null


func find_all(definition_id: StringName) -> Array[ItemInstance]:
	var found: Array[ItemInstance] = []
	for instance in _items:
		if instance.get_definition_id() == definition_id:
			found.append(instance)
	return found


func contains(instance: ItemInstance) -> bool:
	return _items.has(instance)


# --- Capacity -------------------------------------------------------------

## Whether this container would take that kind of item at all.
##
## Distinct from having room: "does not take weapons" and "is full" are
## different refusals and a caller usually needs to say which happened.
func accepts(definition: ItemDefinition) -> bool:
	if _profile == null:
		return definition != null
	return _profile.accepts(definition)


## How many units of [param instance] would fit right now, counting space in
## existing stacks, free slots and remaining weight.
func space_for(instance: ItemInstance) -> int:
	if instance == null or instance.definition == null:
		return 0
	if not accepts(instance.definition):
		return 0

	var room := 0
	for existing in _items:
		if existing.can_stack_with(instance):
			room += existing.get_free_space()

	var free_slots := get_free_slots()
	if free_slots < 0:
		room = 0x3FFFFFFF
	else:
		room += free_slots * instance.get_max_stack()

	if _profile != null and _profile.has_weight_limit():
		var unit_weight := instance.definition.weight
		if unit_weight > 0.0:
			var remaining := _profile.max_weight - get_total_weight()
			room = mini(room, floori(remaining / unit_weight))

	return maxi(0, room)


## Whether the whole instance fits, with the reason when it does not.
func can_fit(instance: ItemInstance) -> FrameworkResult:
	if instance == null or instance.definition == null:
		return FrameworkResult.fail(
			&"inventory.null_item", "Cannot store a null item."
		)
	if not accepts(instance.definition):
		return FrameworkResult.fail(
			&"inventory.rejected",
			"This container does not accept %s." % instance.get_display_name()
		)
	if space_for(instance) < instance.quantity:
		return FrameworkResult.fail(
			&"inventory.no_room",
			"Not enough room for %d x %s." % [instance.quantity, instance.get_display_name()]
		)
	return FrameworkResult.ok(instance)


# --- Mutation -------------------------------------------------------------

## Stores an item, all of it or none of it.
##
## The instance is consumed: on success this container owns it, and the caller
## must not keep using the reference. Use [method add_up_to] when a partial
## pickup is wanted instead.
func add(instance: ItemInstance) -> FrameworkResult:
	var fits := can_fit(instance)
	if fits.is_err():
		return fits
	var stored := _store(instance, instance.quantity)
	item_added.emit(instance, stored)
	contents_changed.emit()
	return FrameworkResult.ok(stored)


## Stores as much as fits and reports how many units were taken.
##
## For a world pickup that should take what it can rather than refusing the
## lot. [param instance] is reduced by the amount stored, so what is left is
## what stays on the ground.
func add_up_to(instance: ItemInstance) -> int:
	if instance == null or instance.definition == null:
		return 0
	var room := mini(space_for(instance), instance.quantity)
	if room <= 0:
		return 0
	var stored := _store(instance, room)
	if stored > 0:
		item_added.emit(instance, stored)
		contents_changed.emit()
	return stored


## Removes units of an item. All or nothing: asking for more than is held
## removes none, rather than partially paying for something (rule 17).
func remove(definition_id: StringName, quantity: int = 1) -> FrameworkResult:
	if quantity <= 0:
		return FrameworkResult.fail(
			&"inventory.invalid_quantity", "Quantity must be positive."
		)
	if not has(definition_id, quantity):
		return FrameworkResult.fail(
			&"inventory.insufficient",
			"Only %d of '%s' held, %d requested." % [count(definition_id), definition_id, quantity]
		)

	var left := quantity
	for index in range(_items.size() - 1, -1, -1):
		if left <= 0:
			break
		var instance := _items[index]
		if instance.get_definition_id() != definition_id:
			continue
		var taken := mini(instance.quantity, left)
		instance.quantity -= taken
		left -= taken
		if instance.quantity <= 0:
			_items.remove_at(index)

	item_removed.emit(definition_id, quantity)
	contents_changed.emit()
	return FrameworkResult.ok(quantity)


## Removes one specific stack and hands it back to the caller.
## Wears an item down, and destroys it when its definition says it should be.
##
## [b]One owner for the whole transaction.[/b] Degrading and then deciding what
## to do about a broken item happened in two places before this -- gathering
## and crafting -- and neither destroyed anything, so
## [member ItemDefinition.breaks_when_worn_out] was a field read by nothing
## but its own validator. Two call sites each half-implementing a rule is how a
## flag ends up decorative (rule 4).
##
## Returns how much condition was actually lost, which is zero for an item with
## no durability. A caller wanting to know whether it broke checks
## [method ItemInstance.is_broken] before this returns, or listens to
## [signal item_broke].
func wear(instance: ItemInstance, amount: float) -> float:
	if instance == null or amount <= 0.0:
		return 0.0
	var lost := instance.degrade(amount)
	if lost <= 0.0:
		return 0.0

	if instance.is_broken() and instance.definition != null:
		if instance.definition.breaks_when_worn_out:
			var id := instance.get_definition_id()
			# Only if we are actually holding it. Wearing somebody else's tool
			# must not silently delete it from our own bag by id.
			if contains(instance):
				remove_instance(instance)
			item_broke.emit(id)
	return lost


func remove_instance(instance: ItemInstance) -> FrameworkResult:
	var index := _items.find(instance)
	if index < 0:
		return FrameworkResult.fail(
			&"inventory.not_held", "That item is not in this container."
		)
	_items.remove_at(index)
	item_removed.emit(instance.get_definition_id(), instance.quantity)
	contents_changed.emit()
	return FrameworkResult.ok(instance)


## Takes [param quantity] units out as a separate instance, leaving the rest.
func take(definition_id: StringName, quantity: int = 1) -> FrameworkResult:
	if not has(definition_id, quantity):
		return FrameworkResult.fail(
			&"inventory.insufficient",
			"Only %d of '%s' held, %d requested." % [count(definition_id), definition_id, quantity]
		)
	var source := find(definition_id)
	var taken := ItemInstance.create(source.definition, quantity)
	taken.durability = source.durability
	taken.custom_state = source.custom_state.duplicate(true)
	var removal := remove(definition_id, quantity)
	if removal.is_err():
		return removal
	return FrameworkResult.ok(taken)


## Moves items to another container, atomically across both.
##
## Both sides are validated before either is touched, so a transfer that will
## not fit leaves the source intact. Half-moving a stack and failing is how
## items get destroyed, and no amount of care at the call site fixes it.
func transfer_to(
	destination: InventoryComponent, definition_id: StringName, quantity: int = 1
) -> FrameworkResult:
	if destination == null:
		return FrameworkResult.fail(
			&"inventory.null_destination", "There is no container to transfer to."
		)
	if destination == self:
		return FrameworkResult.fail(
			&"inventory.same_container", "Cannot transfer a container into itself."
		)
	if not has(definition_id, quantity):
		return FrameworkResult.fail(
			&"inventory.insufficient",
			"Only %d of '%s' held, %d requested." % [count(definition_id), definition_id, quantity]
		)

	var source := find(definition_id)
	var probe := ItemInstance.create(source.definition, quantity)
	probe.durability = source.durability
	probe.custom_state = source.custom_state.duplicate(true)

	var fits := destination.can_fit(probe)
	if fits.is_err():
		return fits

	# Both sides have now agreed. From here nothing can fail.
	var taken := take(definition_id, quantity)
	return destination.add(taken.payload as ItemInstance)


func clear() -> void:
	if _items.is_empty():
		return
	_items.clear()
	contents_changed.emit()


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var saved: Array = []
	for instance in _items:
		saved.append(instance.capture_state())
	return {"items": saved}


## Rebuilds contents from a save, resolving definitions by id through the core.
##
## Items whose definitions are no longer registered are dropped rather than
## failing the load: a save from a build that had an item this one does not is
## a normal case for a modded or updated game, not a corrupt file.
func restore_state(data: Dictionary) -> void:
	_items.clear()
	var context := get_context()
	var core := context.core if context != null else null
	for entry in data.get("items", []):
		var instance := ItemInstance.restore_state(entry, core)
		if instance != null:
			_items.append(instance)
	contents_changed.emit()


# --- Internals ------------------------------------------------------------

## Puts [param quantity] units in, filling partial stacks before taking slots.
##
## Filling existing stacks first is what stops an inventory fragmenting into
## twenty single arrows when it had room in a stack all along.
##
## [b]The instance itself is kept where it can be.[/b] When the whole thing
## goes into one new stack -- the overwhelmingly common case, and every
## unstackable item -- the object the caller handed over is the object stored,
## not a copy of it. Copying would break every reference to it: equipment
## sources its granted modifiers on the instance's stack id, so an item that
## quietly became a different object on the way into the bag would unequip
## nothing, and a caller checking [method contains] on what it just added would
## be told no. Copies happen only when a stack genuinely has to be split.
func _store(instance: ItemInstance, quantity: int) -> int:
	var left := quantity
	for existing in _items:
		if left <= 0:
			break
		if not existing.can_stack_with(instance):
			continue
		var moved := mini(existing.get_free_space(), left)
		existing.quantity += moved
		left -= moved

	var takes_whole_instance := (
		left == quantity
		and quantity == instance.quantity
		and left <= instance.get_max_stack()
	)
	if takes_whole_instance:
		_items.append(instance)
		return quantity

	while left > 0:
		var chunk := mini(left, instance.get_max_stack())
		var stack := ItemInstance.create(instance.definition, chunk)
		stack.durability = instance.durability
		stack.modifiers = instance.modifiers.duplicate()
		stack.custom_state = instance.custom_state.duplicate(true)
		_items.append(stack)
		left -= chunk

	instance.quantity -= quantity
	return quantity


## Read by property name rather than by casting to a character definition, so a
## vehicle or a chest with its own definition type can carry an inventory
## without Inventory importing another module's types (rule 9).
func _resolve_profile() -> InventoryProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition != null and "inventory" in definition:
		var candidate: Variant = definition.get("inventory")
		if candidate is InventoryProfile:
			return candidate as InventoryProfile
	return null
