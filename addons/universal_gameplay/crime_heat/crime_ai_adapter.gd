class_name CrimeAIAdapter
extends FrameworkComponent
## Teaches this entity's AI to enforce the law.
##
## The deletable file that connects Crime to AI, exactly as [FactionAIAdapter]
## connects Factions to AI. It holds an [AIControllerComponent] and a
## [HeatService] and hands the first a provider built from the second. Delete
## it and the guard goes back to its faction politics; delete Crime entirely
## and nothing in [code]ai/[/code] notices (rule 10, rule 31).
##
## It wraps whatever provider is already installed, so ordering with
## [FactionAIAdapter] does not matter as long as this one initialises after —
## which composition order in a scene decides, and which
## [method install] re-applies for a project that changes its mind.

## The controller to teach. Found among this entity's own components when it
## is not wired.
@export var controller: AIControllerComponent

## Live wanted state. Resolved from the core's registry when not wired.
@export var heat: HeatService

## Which faction's warrants this entity enforces. Blank reads the entity's own
## faction, so a policeman enforces police law without anyone authoring it.
@export var law_faction: StringName = &""

## Extra threat a wanted target carries.
@export_range(0.0, 10.0, 0.1) var wanted_threat_bonus: float = 1.0

var _provider: WantedHostilityProvider = null


func initialize(context: EntityContext) -> void:
	super(context)
	if controller == null:
		controller = _find(AIControllerComponent) as AIControllerComponent
	if heat == null:
		heat = _resolve_heat()
	install()


## Builds and installs the provider over whatever is already there. Public so
## a project that swaps the service at runtime can re-apply it.
func install() -> void:
	if controller == null:
		return
	_provider = WantedHostilityProvider.create(
		heat, _resolve_law_faction(), controller.get_hostility_provider()
	)
	_provider.wanted_threat_bonus = wanted_threat_bonus
	controller.set_hostility_provider(_provider)


## Takes the law back out, restoring whatever it wrapped. Not the framework
## default: uninstalling the law must not also uninstall an entity's faction
## politics, which is what a plain reset would do.
func uninstall() -> void:
	if controller == null or _provider == null:
		return
	var underneath := _provider.inner
	controller.set_hostility_provider(
		underneath if underneath != null else HostilityProvider.new()
	)
	_provider = null


func get_provider() -> WantedHostilityProvider:
	return _provider


func _resolve_law_faction() -> StringName:
	if law_faction != &"":
		return law_faction
	var entity := get_entity()
	if entity == null:
		return &""
	for component in DefinitionBinder.collect_components(entity):
		if component.has_method("get_faction"):
			var faction: Variant = component.call("get_faction")
			if faction is StringName and faction != &"":
				return faction
	return &""


func _resolve_heat() -> HeatService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_CRIME) as HeatService


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
