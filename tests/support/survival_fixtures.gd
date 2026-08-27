class_name SurvivalFixtures
extends RefCounted
## Builders for the needs, consumables, recipes and resource nodes the M12
## suites need.
##
## Shared for the same reason [ItemFixtures] is: the crafting suite, the
## gathering suite and the exit-gate suite all want the same axe, and three
## copies of that setup drift apart the moment one of them is edited.


# --- Needs ----------------------------------------------------------------

## A meter that drains towards empty. The hunger shape.
static func need(
	id: StringName = &"need.hunger",
	decay_per_second: float = 1.0,
	maximum: float = 100.0,
	starting_value: float = 100.0
) -> NeedDefinition:
	var definition := NeedDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.maximum = maximum
	definition.starting_value = starting_value
	definition.decay_per_second = decay_per_second
	definition.low_fraction = 0.3
	definition.critical_fraction = 0.1
	definition.low_state = StringName("state.%s.low" % String(id).replace(".", "_"))
	definition.critical_state = StringName(
		"state.%s.critical" % String(id).replace(".", "_")
	)
	return definition


## A meter that drains towards a comfortable middle. The body-temperature
## shape, which is the same class with a different [member
## NeedDefinition.drains_towards].
static func temperature(
	id: StringName = &"need.warmth",
	middle: float = 50.0,
	starting_value: float = 50.0
) -> NeedDefinition:
	var definition := need(id, 1.0, 100.0, starting_value)
	definition.drains_towards = middle
	return definition


## A need that kills when empty, tagged so resistance can apply.
static func lethal_need(
	id: StringName = &"need.oxygen", damage_per_second: float = 10.0
) -> NeedDefinition:
	var definition := need(id, 5.0)
	definition.damage_per_second = damage_per_second
	var tags: Array[StringName] = [&"damage.suffocation"]
	definition.damage_tags = tags
	return definition


static func needs_component(
	definitions: Array = [], auto_tick: bool = false
) -> NeedsComponent:
	var component := NeedsComponent.new()
	component.name = "NeedsComponent"
	var typed: Array[NeedDefinition] = []
	typed.assign(definitions)
	component.needs_override = typed
	component.auto_tick = auto_tick
	return component


# --- Consumables ----------------------------------------------------------

## An item that restores needs when eaten.
static func meal(
	id: StringName = &"item.ration",
	needs: Array = [&"need.hunger"],
	amounts: Array = [40.0],
	uses: int = 1
) -> ItemDefinition:
	var definition := ItemFixtures.stackable(id, 10, 0.5)
	definition.category = &"item.consumable"
	var profile := ConsumableProfile.new()
	var typed_needs: Array[StringName] = []
	typed_needs.assign(needs)
	var typed_amounts: Array[float] = []
	typed_amounts.assign(amounts)
	profile.restores_needs = typed_needs
	profile.restore_amounts = typed_amounts
	profile.uses = uses
	definition.consumable = profile
	return definition


# --- Crafting -------------------------------------------------------------

static func ingredient(
	item_id: StringName, quantity: int = 1, consumed: bool = true
) -> RecipeIngredient:
	var entry := RecipeIngredient.new()
	entry.item_id = item_id
	entry.quantity = quantity
	entry.consumed = consumed
	return entry


## A tool ingredient: present, not spent, and worn a little.
static func tool_ingredient(
	tag: StringName, wear: float = 5.0
) -> RecipeIngredient:
	var entry := RecipeIngredient.new()
	entry.required_tag = tag
	entry.consumed = false
	entry.durability_cost = wear
	return entry


static func recipe(
	id: StringName = &"recipe.plank",
	ingredients: Array = [],
	output_id: StringName = &"item.plank",
	output_quantity: int = 1,
	craft_time: float = 0.0
) -> RecipeDefinition:
	var definition := RecipeDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	var typed: Array[RecipeIngredient] = []
	typed.assign(ingredients)
	definition.ingredients = typed
	definition.output_id = output_id
	definition.output_quantity = output_quantity
	definition.craft_time = craft_time
	return definition


static func station(
	tags: Array = [&"station.workbench"], speed: float = 1.0
) -> CraftingStation:
	var component := CraftingStation.new()
	component.name = "CraftingStation"
	var typed: Array[StringName] = []
	typed.assign(tags)
	component.station_tags = typed
	component.speed_multiplier = speed
	return component


# --- Gathering ------------------------------------------------------------

static func resource_definition(
	id: StringName = &"node.tree",
	loot_table_id: StringName = &"loot.tree",
	tool_tag: StringName = &"",
	charges: int = 1
) -> ResourceNodeDefinition:
	var definition := ResourceNodeDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.loot_table_id = loot_table_id
	definition.required_tool_tag = tool_tag
	definition.charges = charges
	definition.harvest_time = 0.0
	return definition


static func resource_node(
	definition: ResourceNodeDefinition, auto_tick: bool = false
) -> Node3D:
	var entity := Node3D.new()
	entity.name = "Tree"
	var component := ResourceNode.new()
	component.name = "ResourceNode"
	component.node_override = definition
	component.auto_tick = auto_tick
	entity.add_child(component)
	return entity


## An axe: an item carrying a tool tag and some durability to lose.
static func tool_item(
	id: StringName = &"item.axe",
	tag: StringName = &"tool.axe",
	durability: float = 100.0
) -> ItemDefinition:
	var definition := ItemFixtures.unique(id, 3.0)
	definition.category = &"item.tool"
	definition.max_durability = durability
	var tags: Array[StringName] = [tag]
	definition.tags = tags
	return definition


# --- Entities -------------------------------------------------------------

## A survivor: a bag, needs, health and the capability of eating.
static func survivor(
	entity_name: String = "Survivor", need_definitions: Array = []
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	entity.add_child(receiver)

	var effects := StatusEffectComponent.new()
	effects.name = "StatusEffectComponent"
	effects.auto_tick = false
	entity.add_child(effects)

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)

	entity.add_child(needs_component(need_definitions))

	var consumer := ConsumerComponent.new()
	consumer.name = "ConsumerComponent"
	entity.add_child(consumer)

	var crafting := CraftingComponent.new()
	crafting.name = "CraftingComponent"
	crafting.auto_tick = false
	entity.add_child(crafting)
	return entity


static func assemble(
	entity: Node, core: Node = null, definition: FrameworkDefinition = null
) -> void:
	var context := EntityContext.create(entity, definition, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
