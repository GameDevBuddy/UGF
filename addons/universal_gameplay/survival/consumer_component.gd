class_name ConsumerComponent
extends FrameworkComponent
## The capability of eating, drinking and using things up.
##
## The third leg of the M12 exit gate. Split from [NeedsComponent] on purpose:
## that one owns what the meters do, this owns what an item does to them, and
## an entity can have either without the other -- a campfire restores warmth
## and eats nothing, a creature starves and cannot use items (rule 4, rule 31).

## Emitted after something has been consumed.
signal consumed(instance: ItemInstance, profile: ConsumableProfile)
## Emitted when consumption was refused, so a UI can say why without
## re-deriving it.
signal consumption_refused(instance: ItemInstance, reason: StringName)

## Meters restored. Found among this entity's own components when not wired.
@export var needs: NeedsComponent

## Health restored, so a bandage and a meal go through the same call.
@export var health: HealthComponent

## Where a consumable's status effects land.
@export var status_effects: StatusEffectComponent

## Where consumed items are taken from. A caller can pass an instance from
## anywhere; this is only the default.
@export var inventory: InventoryComponent


func initialize(context: EntityContext) -> void:
	super(context)
	if needs == null:
		needs = _find(NeedsComponent) as NeedsComponent
	if health == null:
		health = _find(HealthComponent) as HealthComponent
	if status_effects == null:
		status_effects = _find(StatusEffectComponent) as StatusEffectComponent
	if inventory == null:
		inventory = _find(InventoryComponent) as InventoryComponent


## Whether [param instance] could be consumed right now.
func can_consume(instance: ItemInstance) -> FrameworkResult:
	if instance == null or instance.definition == null:
		return FrameworkResult.fail(&"consume.nothing", "There is nothing to consume.")
	var profile := instance.definition.consumable
	if profile == null:
		return FrameworkResult.fail(
			&"consume.not_consumable", "%s cannot be consumed." % instance.get_display_name()
		)
	if instance.quantity < profile.uses:
		return FrameworkResult.fail(
			&"consume.not_enough", "There is not enough of it left."
		)
	return FrameworkResult.ok(profile)


## Consumes an item: restores what it restores, applies what it applies, and
## takes it out of the bag.
##
## Validate-then-mutate, like every other transaction in the framework: an
## item that could not be consumed is not half-eaten (rule 17).
func consume(instance: ItemInstance) -> FrameworkResult:
	var allowed := can_consume(instance)
	if allowed.is_err():
		consumption_refused.emit(instance, allowed.code)
		return allowed

	var profile: ConsumableProfile = allowed.payload
	if needs != null:
		for need in profile.restores_needs:
			needs.restore(need, profile.restores(need))
	if health != null and not is_equal_approx(profile.health, 0.0):
		if profile.health > 0.0:
			health.heal(profile.health)
		else:
			health.set_current(health.get_current() + profile.health)
	if status_effects != null:
		for effect_id in profile.effects:
			var effect := _lookup(effect_id) as StatusEffectDefinition
			if effect != null:
				status_effects.apply(effect, get_entity())

	if profile.consumed:
		_take(instance, profile.uses)
	consumed.emit(instance, profile)
	return FrameworkResult.ok(profile)


## Consumes the first matching item in this entity's bag. What a hotbar press
## calls.
func consume_by_id(item_id: StringName) -> FrameworkResult:
	if inventory == null:
		return FrameworkResult.fail(&"consume.no_inventory", "There is no bag to eat from.")
	var instance := inventory.find(item_id)
	if instance == null:
		return FrameworkResult.fail(
			&"consume.not_carried", "You are not carrying any %s." % item_id
		)
	return consume(instance)


# --- Internals ------------------------------------------------------------

func _take(instance: ItemInstance, amount: int) -> void:
	if inventory != null and inventory.contains(instance):
		inventory.remove(instance.get_definition_id(), amount)
		return
	# Not in this entity's bag: a world container, a vendor's shelf, a test.
	# Decrementing the instance is the honest fallback -- the caller owns it.
	instance.quantity = maxi(0, instance.quantity - amount)


func _lookup(id: StringName) -> FrameworkDefinition:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return null
	return core.call("get_definition", id) as FrameworkDefinition


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
