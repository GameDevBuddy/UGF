class_name FactionHostilityProvider
extends HostilityProvider
## Answers the AI's hostility question from faction standing.
##
## [b]This is half the M10 exit gate.[/b] AI declares the question through
## [HostilityProvider]; Factions answers it here; [FactionAIAdapter] plugs one
## into the other. No file in [code]ai/[/code] mentions a faction, and no file
## in [code]factions/[/code] mentions a brain (rule 9, rule 10).

var service: FactionService = null

## Whether something with no faction at all is treated as an enemy.
##
## False by default, and that is a real change from the bare provider: once a
## project installs factions, wildlife and scenery stop being things guards
## charge at. A project that wants the old free-for-all sets it true.
var hostile_to_unaffiliated: bool = false


static func create(
	p_service: FactionService, p_hostile_to_unaffiliated: bool = false
) -> FactionHostilityProvider:
	var provider := FactionHostilityProvider.new()
	provider.service = p_service
	provider.hostile_to_unaffiliated = p_hostile_to_unaffiliated
	return provider


func is_hostile(observer: Node, target: Node) -> bool:
	var mark := FactionComponent.find_on(observer)
	if mark == null or not mark.has_faction() or service == null:
		# An observer with no allegiance has no opinion to act on. Falling back
		# to the framework default keeps an unconfigured NPC fighting rather
		# than standing there, which matters because the shipped character
		# scene carries a faction component that most content leaves blank
		# (rule 31).
		return super(observer, target)
	if FactionComponent.find_on(target) == null:
		return hostile_to_unaffiliated
	return mark.is_hostile_to(target)


func is_ally(observer: Node, target: Node) -> bool:
	var mark := FactionComponent.find_on(observer)
	if mark == null or not mark.has_faction() or service == null:
		return false
	return mark.is_friendly_to(target)


func get_threat_scale(observer: Node, target: Node) -> float:
	var mark := FactionComponent.find_on(observer)
	if mark == null or not mark.has_faction() or service == null:
		return 1.0
	return AttitudeSolver.threat_scale(mark.get_attitude_to(target))
