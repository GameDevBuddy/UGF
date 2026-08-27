class_name FactionAIAdapter
extends FrameworkComponent
## Teaches this entity's AI to fight by faction instead of on sight.
##
## The seam itself, and the reason the exit gate is met without either module
## importing the other: it holds an [AIControllerComponent] and a
## [FactionService], and hands the first a provider built from the second.
## Delete it and the NPC goes back to treating everything it notices as an
## enemy, which is the correct failure mode for a project that removed
## Factions (rule 10, rule 31).

## The controller to teach. Found among this entity's own components when it
## is not wired.
@export var controller: AIControllerComponent

## Live standing. Resolved from the core's registry when not wired.
@export var service: FactionService

## Whether something with no faction is treated as an enemy. Off makes
## wildlife and scenery uninteresting to a guard.
@export var hostile_to_unaffiliated: bool = false

var _provider: FactionHostilityProvider = null


func initialize(context: EntityContext) -> void:
	super(context)
	if controller == null:
		controller = _find_controller()
	if service == null:
		service = _resolve_service()
	install()


## Builds and installs the provider. Public so a project that swaps the
## service at runtime can re-apply it without rebuilding the entity.
func install() -> void:
	if controller == null:
		return
	_provider = FactionHostilityProvider.create(service, hostile_to_unaffiliated)
	controller.set_hostility_provider(_provider)


## Puts the framework default back. What removing an entity's allegiance does.
func uninstall() -> void:
	if controller != null:
		controller.set_hostility_provider(HostilityProvider.new())
	_provider = null


func get_provider() -> FactionHostilityProvider:
	return _provider


func _find_controller() -> AIControllerComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is AIControllerComponent:
			return component as AIControllerComponent
	return null


func _resolve_service() -> FactionService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_FACTION) as FactionService
