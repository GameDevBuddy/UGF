class_name CraftEventAdapter
extends FrameworkComponent
## Promotes a finished craft to a cross-feature fact.
##
## Crafting shipped in M12 with a local [code]crafted[/code] signal and nothing
## listening. The plan's CraftItem objective is the first thing that needs it,
## and without this adapter such an objective would have to match
## [code]item_acquired[/code] -- which a purchase, a pickup and a loot drop all
## fire too, so "craft three torches" would be satisfiable by buying them.
##
## Deletable like every other event adapter: remove it and crafting still
## works, it just stops telling Missions.

signal craft_published(event: FrameworkEvent)

## The crafting to observe, wired at composition time (rule 20).
@export var crafting: CraftingComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

@export var publish_crafts: bool = true

const CraftedEvent := preload(
	"res://addons/universal_gameplay/crafting/craft_event.gd"
)

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if crafting == null:
		crafting = _find_crafting()
	_bus = event_bus if event_bus != null else _find_bus()
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_ITEM_CRAFTED)
	if crafting != null and not crafting.crafted.is_connected(_on_crafted):
		crafting.crafted.connect(_on_crafted)


func _exit_tree() -> void:
	if crafting != null and crafting.crafted.is_connected(_on_crafted):
		crafting.crafted.disconnect(_on_crafted)


func get_bus() -> Node:
	return _bus


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_ITEM_CRAFTED)


## Counts the units produced, not the number of times craft() was called.
##
## A recipe yielding three planks and run once has made three planks, and an
## objective counting planks should see three. The outputs array is what the
## component actually produced, so it is the honest source for that number.
func _on_crafted(recipe: RecipeDefinition, outputs: Array[ItemInstance]) -> void:
	if not publish_crafts or _bus == null or not _bus.has_method("publish"):
		return
	var made := 0
	for instance in outputs:
		if instance != null and instance.get_definition_id() == recipe.output_id:
			made += instance.quantity
	var event := CraftedEvent.create(_entity_root(), recipe, made)
	_bus.call("publish", event)
	craft_published.emit(event)


func _entity_root() -> Node:
	var context := get_context()
	if context != null and context.entity != null:
		return context.entity
	return get_parent()


func _find_crafting() -> CraftingComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if child is CraftingComponent:
			return child as CraftingComponent
	return null


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EventBus")
