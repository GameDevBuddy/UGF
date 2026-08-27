class_name ItemInstance
extends RefCounted
## One stack of one item, with the state that belongs to it and not to its kind.
##
## The other half of rule 16. Quantity, durability and per-instance modifiers
## live here; everything shared lives in [ItemDefinition]. A hundred inventory
## entries point at one definition and each carries its own condition.
##
## [b]Every instance has a unique id.[/b] Not for persistence — the definition
## id and the state are what a save records — but because equipment removes
## stat modifiers by source, and two identical rings must unequip
## independently. Without a per-instance source, taking off one ring removes
## the other's bonus too.

## Counter feeding generated ids. Static so two instances created in the same
## microsecond cannot collide, exactly as [PersistentIdentity] does it.
static var _sequence: int = 0

## What this is an instance of.
var definition: ItemDefinition = null

## How many units this stack holds. Always at least 1 for a live instance.
var quantity: int = 1

## Current condition. Meaningless when the definition has no durability.
var durability: float = 0.0

## Modifiers this particular instance grants beyond its definition's — an
## enchantment, a scope, a mod. Applied on equip alongside the profile's.
var modifiers: Array[StatModifier] = []

## Free-form per-instance state: inscriptions, ammo loaded, who crafted it.
## Deliberately untyped and deliberately small; anything living here for long
## should become a real field on a profile.
var custom_state: Dictionary = {}

var _stack_id: StringName = &""


static func create(
	p_definition: ItemDefinition, p_quantity: int = 1
) -> ItemInstance:
	var instance := ItemInstance.new()
	instance.definition = p_definition
	instance.quantity = maxi(1, p_quantity)
	if p_definition != null:
		instance.durability = p_definition.max_durability
	return instance


## Stable id for this stack within a run. Generated lazily, for the same
## reason [PersistentIdentity] does it lazily: an instance created and used
## inside one frame must not be waiting on a later step for its identity.
##
## Named for the stack rather than the instance because [method
## Object.get_instance_id] already exists and returns an int; overriding it
## with a different type is a parse error, and shadowing engine API with a
## different meaning would be worse than the error.
func get_stack_id() -> StringName:
	if _stack_id == &"":
		_sequence += 1
		_stack_id = StringName(
			"item.%s.%d.%d" % [get_definition_id(), Time.get_ticks_usec(), _sequence]
		)
	return _stack_id


func get_definition_id() -> StringName:
	return definition.id if definition != null else &"unknown"


func get_display_name() -> String:
	if definition == null:
		return "<no definition>"
	return definition.display_name if not definition.display_name.is_empty() else str(definition.id)


# --- Stacking -------------------------------------------------------------

## Whether these two could occupy one stack.
##
## Same definition is necessary but not sufficient: two swords at different
## durability, or with different enchantments, are not interchangeable, and
## merging them would silently discard one side's state.
func can_stack_with(other: ItemInstance) -> bool:
	if other == null or other == self:
		return false
	if definition == null or other.definition == null:
		return false
	if definition != other.definition:
		return false
	if not definition.is_stackable():
		return false
	if definition.has_durability() and not is_equal_approx(durability, other.durability):
		return false
	if not modifiers.is_empty() or not other.modifiers.is_empty():
		return false
	if custom_state != other.custom_state:
		return false
	return true


func get_max_stack() -> int:
	return definition.max_stack if definition != null else 1


func get_free_space() -> int:
	return maxi(0, get_max_stack() - quantity)


func is_full() -> bool:
	return get_free_space() <= 0


## Moves as much of [param other] into this stack as fits. Returns how many
## units moved; [param other] is reduced by the same amount.
func merge_from(other: ItemInstance) -> int:
	if not can_stack_with(other):
		return 0
	var moved := mini(get_free_space(), other.quantity)
	if moved <= 0:
		return 0
	quantity += moved
	other.quantity -= moved
	return moved


## Splits [param amount] units off into a new instance, or null when that is
## not possible. The new instance inherits durability, modifiers and state.
func split(amount: int) -> ItemInstance:
	if amount <= 0 or amount >= quantity:
		return null
	var taken := ItemInstance.create(definition, amount)
	taken.durability = durability
	taken.modifiers = modifiers.duplicate()
	taken.custom_state = custom_state.duplicate(true)
	quantity -= amount
	return taken


func duplicate_instance() -> ItemInstance:
	var copy := ItemInstance.create(definition, quantity)
	copy.durability = durability
	copy.modifiers = modifiers.duplicate()
	copy.custom_state = custom_state.duplicate(true)
	return copy


# --- Weight and worth -----------------------------------------------------

func get_total_weight() -> float:
	return definition.weight * float(quantity) if definition != null else 0.0


func get_total_value() -> float:
	return definition.base_value * float(quantity) if definition != null else 0.0


# --- Durability -----------------------------------------------------------

func has_durability() -> bool:
	return definition != null and definition.has_durability()


## Condition as a fraction, 1 to 0. Items without durability report 1, so a UI
## can ask every item and get a sensible answer.
func get_condition() -> float:
	if not has_durability():
		return 1.0
	return clampf(durability / definition.max_durability, 0.0, 1.0)


func is_broken() -> bool:
	return has_durability() and durability <= 0.0


## Wears the item. Returns how much condition was actually lost.
func degrade(amount: float) -> float:
	if not has_durability() or amount <= 0.0:
		return 0.0
	var before := durability
	durability = maxf(0.0, durability - amount)
	return before - durability


func repair(amount: float) -> float:
	if not has_durability() or amount <= 0.0:
		return 0.0
	var before := durability
	durability = minf(definition.max_durability, durability + amount)
	return durability - before


# --- Persistence ----------------------------------------------------------

## Serialisable snapshot: the definition id and this instance's own state.
##
## The id, not the resource path (rule 32), so moving
## [code]item_sword.tres[/code] does not break existing saves.
func capture_state() -> Dictionary:
	var data := {
		"definition": String(get_definition_id()),
		"quantity": quantity,
	}
	if has_durability():
		data["durability"] = durability
	if not custom_state.is_empty():
		data["custom"] = custom_state.duplicate(true)
	return data


## Rebuilds an instance from a save, resolving the definition through a
## registry. Returns null when the definition is not registered, which is what
## a save from a build that had an item this one does not looks like.
static func restore_state(data: Dictionary, core: Node) -> ItemInstance:
	if core == null or not core.has_method("get_definition"):
		return null
	var id := StringName(data.get("definition", ""))
	if id == &"":
		return null
	var definition := core.call("get_definition", id) as ItemDefinition
	if definition == null:
		return null

	var instance := ItemInstance.create(definition, int(data.get("quantity", 1)))
	if instance.has_durability():
		instance.durability = float(data.get("durability", definition.max_durability))
	var custom: Dictionary = data.get("custom", {})
	if not custom.is_empty():
		instance.custom_state = custom.duplicate(true)
	return instance


func _to_string() -> String:
	if quantity > 1:
		return "%s x%d" % [get_display_name(), quantity]
	return get_display_name()
