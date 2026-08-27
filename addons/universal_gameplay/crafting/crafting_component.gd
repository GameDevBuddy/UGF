class_name CraftingComponent
extends FrameworkComponent
## The capability of making things.
##
## Owns the queue and the timing. Every craft is validate-then-mutate: the
## ingredients, the tools, the station and the room for the output are all
## checked before anything is consumed, so a craft that could not finish has
## not eaten the planks (rule 17).

## Emitted when a craft is queued.
signal craft_started(recipe: RecipeDefinition)
## Emitted per tick of a timed craft, with progress in 0..1.
signal craft_progressed(recipe: RecipeDefinition, progress: float)
## Emitted when a craft completes, with what came out.
signal crafted(recipe: RecipeDefinition, outputs: Array[ItemInstance])
## Emitted when a craft was refused or abandoned.
signal craft_failed(recipe: RecipeDefinition, reason: StringName)

## Where ingredients come from and outputs go. Found among this entity's own
## components when not wired.
@export var inventory: InventoryComponent

## Narrative state read for recipe availability. Optional: without it, every
## recipe with required flags is simply unknown (rule 31).
@export var narrative: NarrativeStateService

## The bench being used. Set by a project when the player walks up to one, or
## by an interaction; null means only station-free recipes can be made.
@export var station: CraftingStation

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

var _recipe: RecipeDefinition = null
var _elapsed: float = 0.0


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and is_crafting())


func initialize(context: EntityContext) -> void:
	super(context)
	if inventory == null:
		inventory = _find(InventoryComponent) as InventoryComponent
	if narrative == null:
		narrative = _resolve_narrative()
	set_physics_process(auto_tick and is_crafting())


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Queries --------------------------------------------------------------

func is_crafting() -> bool:
	return _recipe != null


func get_recipe() -> RecipeDefinition:
	return _recipe


func get_progress() -> float:
	if _recipe == null:
		return 0.0
	var duration := get_duration(_recipe)
	if duration <= 0.0:
		return 1.0
	return clampf(_elapsed / duration, 0.0, 1.0)


## How long [param recipe] takes here, after the station's speed multiplier.
func get_duration(recipe: RecipeDefinition) -> float:
	if recipe == null:
		return 0.0
	var scale := station.speed_multiplier if station != null else 1.0
	return recipe.craft_time * scale


## Puts a bench in reach. What an interaction with a workbench calls.
func set_station(bench: CraftingStation) -> void:
	station = bench


## Whether [param recipe] could be started right now.
##
## Public and side-effect free, because a crafting UI greys out a line rather
## than letting the player click it and be told no.
func can_craft(recipe: RecipeDefinition) -> FrameworkResult:
	if recipe == null:
		return FrameworkResult.fail(&"craft.no_recipe", "There is no recipe.")
	if is_crafting():
		return FrameworkResult.fail(&"craft.busy", "Something is already being made.")
	if inventory == null:
		return FrameworkResult.fail(
			&"craft.no_inventory", "There is nowhere to take materials from."
		)
	if not is_known(recipe):
		return FrameworkResult.fail(&"craft.unknown_recipe", "You do not know how.")
	if recipe.needs_station() and (station == null or not station.supports(recipe)):
		return FrameworkResult.fail(
			&"craft.wrong_station", "That cannot be made here."
		)

	for ingredient in recipe.ingredients:
		if ingredient == null:
			continue
		if _find_ingredient(ingredient) == null:
			return FrameworkResult.fail(
				&"craft.missing_ingredient", "Missing %s." % ingredient.describe()
			)

	var output := _resolve_item(recipe.output_id)
	if output == null:
		return FrameworkResult.fail(
			&"craft.unknown_output", "No item is registered as '%s'." % recipe.output_id
		)
	# Room is checked before anything is consumed. Checking after would be the
	# same bug commerce spent a milestone avoiding.
	var fits := inventory.can_fit(ItemInstance.create(output, recipe.output_quantity))
	if fits.is_err():
		return fits
	return FrameworkResult.ok(recipe)


## Whether the story has unlocked this recipe.
func is_known(recipe: RecipeDefinition) -> bool:
	if recipe == null:
		return false
	if recipe.required_flags.is_empty():
		return true
	if narrative == null:
		return false
	return narrative.has_all_flags(recipe.required_flags)


# --- Crafting -------------------------------------------------------------

## Starts a craft. Instant recipes complete before this returns.
##
## Ingredients are consumed up front, which is what makes cancelling cost
## something and what stops the same planks being spent on two benches at once.
func craft(recipe: RecipeDefinition) -> FrameworkResult:
	var allowed := can_craft(recipe)
	if allowed.is_err():
		craft_failed.emit(recipe, allowed.code)
		return allowed

	_consume(recipe)
	_recipe = recipe
	_elapsed = 0.0
	craft_started.emit(recipe)
	set_physics_process(auto_tick)

	if get_duration(recipe) <= 0.0:
		return _finish()
	return FrameworkResult.ok(recipe)


## Abandons a craft in progress. The materials are already gone, which is the
## point: cancelling a smelt should not un-melt the ore.
func cancel(reason: StringName = &"cancelled") -> void:
	if not is_crafting():
		return
	var abandoned := _recipe
	_clear()
	craft_failed.emit(abandoned, reason)


func tick(delta: float) -> void:
	if delta <= 0.0 or not is_crafting():
		return
	_elapsed += delta
	craft_progressed.emit(_recipe, get_progress())
	if _elapsed >= get_duration(_recipe):
		_finish()


# --- Persistence ----------------------------------------------------------
#
# Nothing. Ingredients were consumed when the craft started and live in the
# inventory's record; a half-finished craft restored into a world that has
# moved is worse than one that was never started.

# --- Internals ------------------------------------------------------------

func _finish() -> FrameworkResult:
	var recipe := _recipe
	_clear()

	var produced: Array[ItemInstance] = []
	for output in recipe.get_outputs():
		var definition := _resolve_item(output["item_id"])
		if definition == null:
			push_warning(
				"CraftingComponent: recipe '%s' produces unregistered item '%s'." % [
					recipe.id, output["item_id"]
				]
			)
			continue
		var instance := ItemInstance.create(definition, int(output["quantity"]))
		if inventory != null:
			inventory.add(instance)
		produced.append(instance)

	crafted.emit(recipe, produced)
	return FrameworkResult.ok(produced)


func _consume(recipe: RecipeDefinition) -> void:
	for ingredient in recipe.ingredients:
		if ingredient == null:
			continue
		var instance := _find_ingredient(ingredient)
		if instance == null:
			continue
		if ingredient.consumed:
			inventory.remove(instance.get_definition_id(), ingredient.quantity)
		elif ingredient.durability_cost > 0.0 and instance.has_durability():
			# Tools wear rather than vanish. A hammer that broke would be
			# removed by the inventory's own rules, not by crafting.
			inventory.wear(instance, ingredient.durability_cost)


## The carried stack that satisfies an ingredient, or null.
##
## A tag ingredient searches every stack, so "any hammer" finds whichever
## hammer is in the bag rather than needing one recipe per hammer.
func _find_ingredient(ingredient: RecipeIngredient) -> ItemInstance:
	if inventory == null:
		return null
	if ingredient.required_tag == &"":
		if inventory.has(ingredient.item_id, ingredient.quantity):
			return inventory.find(ingredient.item_id)
		return null
	for instance in inventory.get_items():
		if not ingredient.matches(instance.definition):
			continue
		if instance.has_durability() and instance.is_broken():
			continue
		if instance.quantity >= ingredient.quantity:
			return instance
	return null


func _clear() -> void:
	_recipe = null
	_elapsed = 0.0
	set_physics_process(auto_tick and is_crafting())


func _resolve_item(item_id: StringName) -> ItemDefinition:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", item_id) as ItemDefinition


func _resolve_narrative() -> NarrativeStateService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_NARRATIVE) as NarrativeStateService


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
