class_name EquipmentComponent
extends FrameworkComponent
## The capability of wearing things.
##
## Holds one item per slot and applies what each grants while it is worn.
##
## [b]Modifiers are sourced per instance, not per item kind.[/b] Two identical
## rings equip to two slots and each stamps its own instance id onto the
## modifiers it grants, so taking one off removes exactly its own bonus. Source
## them by definition id instead and removing either ring strips both — a bug
## that only appears when a player happens to wear two of something, which is
## to say in the hands of players and not in a test written from the spec.
##
## Equipping and unequipping are atomic: requirements, slot availability and
## inventory space are all checked before anything moves (rule 17). A failed
## equip leaves the item in the bag and the slot as it was.

## Emitted when an item is put on.
signal equipped(slot: StringName, instance: ItemInstance)
## Emitted when an item comes off. Carries the instance so a caller can decide
## where it goes.
signal unequipped(slot: StringName, instance: ItemInstance)
## Emitted after any change, for a UI that only needs to know it is stale.
signal equipment_changed

## Slots and starting gear. Takes precedence over the definition's loadout.
@export var loadout_override: LoadoutProfile

## Stats to apply granted modifiers to, wired at composition time (rule 20).
## Absent, items still equip and simply grant nothing — which is correct for a
## mannequin or a display case.
@export var stats: StatsComponent

## Inventory items are equipped from and returned to. Absent, equipping takes
## an instance the caller already holds and unequipping hands it back.
@export var inventory: InventoryComponent

## Semantic state to mirror equipment tags onto.
@export var semantic_state: SemanticState

## Equip the loadout's starting items on initialisation.
@export var equip_starting_items: bool = true

var _loadout: LoadoutProfile = null
var _equipped: Dictionary[StringName, ItemInstance] = {}
## Slots made unavailable by an item in another slot, mapped to the slot whose
## item is blocking them. A two-handed weapon blocks the off hand.
var _blocked: Dictionary[StringName, StringName] = {}


func initialize(context: EntityContext) -> void:
	super(context)
	_loadout = _resolve_loadout()
	if stats == null:
		stats = _find(StatsComponent) as StatsComponent
	if inventory == null:
		inventory = _find(InventoryComponent) as InventoryComponent
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	if equip_starting_items:
		_equip_starting_items()


# --- Queries --------------------------------------------------------------

func get_loadout() -> LoadoutProfile:
	return _loadout


func get_slot_ids() -> Array[StringName]:
	return _loadout.get_slot_ids() if _loadout != null else [] as Array[StringName]


func has_slot(slot: StringName) -> bool:
	return _loadout != null and _loadout.has_slot(slot)


func get_equipped(slot: StringName) -> ItemInstance:
	return _equipped.get(slot)


func is_equipped(slot: StringName) -> bool:
	return _equipped.has(slot)


## Whether a slot is unusable because something in another slot occupies it.
func is_blocked(slot: StringName) -> bool:
	return _blocked.has(slot)


func get_blocking_slot(slot: StringName) -> StringName:
	return _blocked.get(slot, &"")


func is_slot_free(slot: StringName) -> bool:
	return has_slot(slot) and not is_equipped(slot) and not is_blocked(slot)


func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()


## Whether any slot holds an item of this kind.
func is_wearing(definition_id: StringName) -> bool:
	for instance in _equipped.values():
		if instance.get_definition_id() == definition_id:
			return true
	return false


## Where an item would go, given what is free. Returns the first slot it fits
## that is available, or blank when there is none.
func find_slot_for(definition: ItemDefinition) -> StringName:
	if definition == null or definition.equipment == null:
		return &""
	for slot in definition.equipment.slots:
		if is_slot_free(slot) and has_slot(slot):
			return slot
	# Nothing free: fall back to the first slot it fits, so equipping can swap.
	for slot in definition.equipment.slots:
		if has_slot(slot) and not is_blocked(slot):
			return slot
	return &""


# --- Requirements ---------------------------------------------------------

## Whether this entity meets an item's requirements, and why not when it does
## not.
##
## A stat the entity lacks entirely fails rather than being skipped: a crate
## cannot wear plate armour by virtue of having no strength.
func meets_requirements(definition: ItemDefinition) -> FrameworkResult:
	if definition == null or definition.equipment == null:
		return FrameworkResult.fail(
			&"equipment.not_equippable", "That item cannot be equipped."
		)
	var profile := definition.equipment

	for tag in profile.required_tags:
		var entity_definition := get_definition()
		if entity_definition == null or not entity_definition.has_tag(tag):
			return FrameworkResult.fail(
				&"equipment.missing_tag",
				"%s requires '%s'." % [definition.get_debug_name(), tag]
			)

	for stat in profile.stat_requirements:
		var required: float = profile.stat_requirements[stat]
		if stats == null or not stats.has_stat(stat):
			return FrameworkResult.fail(
				&"equipment.missing_stat",
				(
					"%s requires %s of %.0f, which this entity does not have."
					% [definition.get_debug_name(), stat, required]
				)
			)
		if stats.get_value(stat) < required:
			return FrameworkResult.fail(
				&"equipment.requirement_not_met",
				(
					"%s requires %s of %.0f; this entity has %.0f."
					% [definition.get_debug_name(), stat, required, stats.get_value(stat)]
				)
			)
	return FrameworkResult.ok(definition)


# --- Commands -------------------------------------------------------------

## Puts an item on. The slot is chosen when [param slot] is blank.
##
## Everything is validated first: the slot exists and is not blocked, the item
## fits it, requirements are met, and anything already there can be taken off
## and stored. Only then does anything move.
func equip(instance: ItemInstance, slot: StringName = &"") -> FrameworkResult:
	if instance == null or instance.definition == null:
		return FrameworkResult.fail(&"equipment.null_item", "There is no item to equip.")

	var definition := instance.definition
	if not definition.is_equippable():
		return FrameworkResult.fail(
			&"equipment.not_equippable",
			"%s has no equipment profile." % definition.get_debug_name()
		)

	var target := slot if slot != &"" else find_slot_for(definition)
	if target == &"":
		return FrameworkResult.fail(
			&"equipment.no_slot",
			"No slot on this entity takes %s." % definition.get_debug_name()
		)
	if not has_slot(target):
		return FrameworkResult.fail(
			&"equipment.unknown_slot", "This entity has no '%s' slot." % target
		)
	if not definition.equipment.fits_slot(target):
		return FrameworkResult.fail(
			&"equipment.wrong_slot",
			"%s does not fit in '%s'." % [definition.get_debug_name(), target]
		)

	var slot_definition := _loadout.get_slot(target)
	if slot_definition != null and not slot_definition.accepts(definition):
		return FrameworkResult.fail(
			&"equipment.slot_refuses",
			"Slot '%s' does not take %s." % [target, definition.get_debug_name()]
		)
	if is_blocked(target):
		return FrameworkResult.fail(
			&"equipment.slot_blocked",
			"Slot '%s' is occupied by whatever is in '%s'." % [target, get_blocking_slot(target)]
		)

	var requirements := meets_requirements(definition)
	if requirements.is_err():
		return requirements

	# Every slot this would block must be free or hold something we can remove.
	for blocked in definition.equipment.blocks_slots:
		if is_blocked(blocked) and get_blocking_slot(blocked) != target:
			return FrameworkResult.fail(
				&"equipment.blocks_occupied_slot",
				(
					"%s needs '%s', which is occupied by whatever is in '%s'."
					% [definition.get_debug_name(), blocked, get_blocking_slot(blocked)]
				)
			)

	# Take off what is in the way, then put the new item on. Unequipping
	# returns items to the inventory, which is why this cannot be reordered:
	# the bag needs the room before the new item leaves it.
	var displaced: Array[ItemInstance] = []
	if is_equipped(target):
		var removed := unequip(target)
		if removed.is_err():
			return removed
		displaced.append(removed.payload as ItemInstance)
	for blocked in definition.equipment.blocks_slots:
		if is_equipped(blocked):
			var removed_blocked := unequip(blocked)
			if removed_blocked.is_err():
				return removed_blocked
			displaced.append(removed_blocked.payload as ItemInstance)

	if inventory != null and inventory.contains(instance):
		inventory.remove_instance(instance)

	_equipped[target] = instance
	for blocked in definition.equipment.blocks_slots:
		_blocked[blocked] = target

	_apply_modifiers(target, instance)
	_apply_states(definition, true)
	equipped.emit(target, instance)
	equipment_changed.emit()
	return FrameworkResult.ok(instance)


## Takes an item off, returning it to the inventory when there is one.
##
## Fails when the item cannot be stored, rather than dropping it on the floor
## or deleting it: an unequip that silently destroys gear because the bag was
## full is not a recoverable mistake.
func unequip(slot: StringName) -> FrameworkResult:
	if not is_equipped(slot):
		return FrameworkResult.fail(
			&"equipment.slot_empty", "Nothing is equipped in '%s'." % slot
		)

	var instance: ItemInstance = _equipped[slot]

	if inventory != null:
		var fits := inventory.can_fit(instance)
		if fits.is_err():
			return FrameworkResult.fail(
				&"equipment.no_room_to_stow",
				(
					"Nowhere to put %s: %s" % [instance.get_display_name(), fits.message]
				)
			)

	_equipped.erase(slot)
	for blocked in _blocked.keys():
		if _blocked[blocked] == slot:
			_blocked.erase(blocked)

	_remove_modifiers(instance)
	if not is_wearing(instance.get_definition_id()):
		_apply_states(instance.definition, false)

	if inventory != null:
		inventory.add(instance)

	unequipped.emit(slot, instance)
	equipment_changed.emit()
	return FrameworkResult.ok(instance)


## Takes an item off and hands it back without storing it, for dropping.
func unequip_to_hand(slot: StringName) -> FrameworkResult:
	if not is_equipped(slot):
		return FrameworkResult.fail(
			&"equipment.slot_empty", "Nothing is equipped in '%s'." % slot
		)
	var instance: ItemInstance = _equipped[slot]
	_equipped.erase(slot)
	for blocked in _blocked.keys():
		if _blocked[blocked] == slot:
			_blocked.erase(blocked)
	_remove_modifiers(instance)
	if not is_wearing(instance.get_definition_id()):
		_apply_states(instance.definition, false)
	unequipped.emit(slot, instance)
	equipment_changed.emit()
	return FrameworkResult.ok(instance)


func unequip_all() -> void:
	for slot in _equipped.keys():
		unequip(slot)


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


## Saves what is in each slot, not the modifiers it grants.
##
## Modifiers are rebuilt from the profile on restore. Saving them too would
## apply every bonus twice on load, the same double-application
## [StatsComponent] and [StatusEffectComponent] both avoid (rule 4).
func capture_state() -> Dictionary:
	var saved: Dictionary = {}
	for slot in _equipped:
		saved[String(slot)] = (_equipped[slot] as ItemInstance).capture_state()
	return {"equipped": saved}


func restore_state(data: Dictionary) -> void:
	for slot in _equipped.keys():
		unequip_to_hand(slot)
	_equipped.clear()
	_blocked.clear()

	var context := get_context()
	var core := context.core if context != null else null
	var saved: Dictionary = data.get("equipped", {})
	for slot in saved:
		var instance := ItemInstance.restore_state(saved[slot], core)
		if instance != null:
			equip(instance, StringName(slot))


# --- Internals ------------------------------------------------------------

func _equip_starting_items() -> void:
	if _loadout == null:
		return
	for slot in _loadout.starting_items:
		var definition: ItemDefinition = _loadout.starting_items[slot]
		if definition == null:
			continue
		equip(ItemInstance.create(definition), slot)


## Modifiers are sourced by instance id, not definition id.
##
## Two identical rings must unequip independently; a shared source would mean
## removing either strips both.
func _apply_modifiers(_slot: StringName, instance: ItemInstance) -> void:
	if stats == null or instance.definition == null:
		return
	var source := instance.get_stack_id()
	var granted := instance.definition.equipment.build_modifiers(source)
	for modifier in instance.modifiers:
		if modifier == null:
			continue
		var copy := modifier.duplicate() as StatModifier
		copy.source = source
		granted.append(copy)
	stats.add_modifiers(granted)


func _remove_modifiers(instance: ItemInstance) -> void:
	if stats == null:
		return
	stats.remove_modifiers_from(instance.get_stack_id())


func _apply_states(definition: ItemDefinition, active: bool) -> void:
	if semantic_state == null or definition == null or definition.equipment == null:
		return
	for state in definition.equipment.applied_states:
		semantic_state.set_state(state, active)


## Read by property name rather than by casting to a character definition, so a
## vehicle with upgrade slots can reuse this without Equipment importing
## another module's types (rule 9).
func _resolve_loadout() -> LoadoutProfile:
	if loadout_override != null:
		return loadout_override
	var definition := get_definition()
	if definition != null and "loadout" in definition:
		var candidate: Variant = definition.get("loadout")
		if candidate is LoadoutProfile:
			return candidate as LoadoutProfile
	return null


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
