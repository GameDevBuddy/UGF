class_name ItemFixtures
extends RefCounted
## Builders for the item, container and loadout content the M4 suites need.
##
## Items use the addon's real pickup scene rather than a bare
## [code]PackedScene.new()[/code]. An empty PackedScene cannot instantiate, so
## fixtures built from one make the drop half of the round trip untestable --
## which is how the exit gate came to pass while [method ItemPickup.spawn] was
## still crashing on a null instantiate.
##
## Shared because three suites want the same sword and the same backpack, and
## three copies of that setup drift apart the moment one of them is edited.
## Static builders rather than [code].tres[/code] files: the addon ships no
## content of its own (rule 29), and test content on disk is content a project
## could accidentally load.


## A plain stackable item with no equipment profile.
static func pickup_scene() -> PackedScene:
	return load("res://addons/universal_gameplay/items/item_pickup.tscn")


static func stackable(
	id: StringName = &"item.arrow", max_stack: int = 20, weight: float = 0.1
) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.category = &"item.ammo"
	definition.scene = pickup_scene()
	definition.max_stack = max_stack
	definition.weight = weight
	definition.base_value = 1.0
	return definition


## A single unstackable item with no equipment profile.
static func unique(
	id: StringName = &"item.trinket", weight: float = 1.0
) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.category = &"item.misc"
	definition.scene = pickup_scene()
	definition.max_stack = 1
	definition.weight = weight
	definition.base_value = 10.0
	return definition


## An equippable weapon that grants power and takes the main hand.
static func weapon(
	id: StringName = &"item.sword",
	power: float = 5.0,
	slot: StringName = &"slot.main_hand"
) -> ItemDefinition:
	var definition := unique(id, 3.0)
	definition.category = &"item.weapon"
	definition.max_durability = 100.0

	var profile := EquipmentProfile.new()
	profile.slots = [slot]
	profile.modifiers = [StatModifier.flat(&"stat.power", power)]
	definition.equipment = profile
	return definition


## A two-handed weapon: fits the main hand and blocks the off hand.
static func two_handed(id: StringName = &"item.greatsword") -> ItemDefinition:
	var definition := weapon(id, 12.0, &"slot.main_hand")
	definition.equipment.blocks_slots = [&"slot.off_hand"]
	return definition


static func slot(id: StringName) -> EquipmentSlotDefinition:
	var definition := EquipmentSlotDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	return definition


## A loadout with a main hand and an off hand and nothing worn.
static func loadout() -> LoadoutProfile:
	var profile := LoadoutProfile.new()
	profile.slots = [slot(&"slot.main_hand"), slot(&"slot.off_hand")]
	return profile


## A container with a slot limit and no weight limit.
static func container(slots: int = 10, weight: float = 0.0) -> InventoryProfile:
	var profile := InventoryProfile.new()
	profile.slot_count = slots
	profile.max_weight = weight
	return profile


## A stats profile carrying one power stat, for equipment modifiers to land on.
static func stats_profile(base: float = 10.0) -> StatsProfile:
	var power := StatDefinition.new()
	power.id = &"stat.power"
	power.display_name = "Power"
	power.default_base = base
	power.minimum = 0.0

	var profile := StatsProfile.new()
	profile.stats = [power]
	return profile
