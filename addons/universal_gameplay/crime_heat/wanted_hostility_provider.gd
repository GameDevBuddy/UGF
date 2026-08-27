class_name WantedHostilityProvider
extends HostilityProvider
## Makes the law hostile to people it is looking for.
##
## [b]This is the M15 exit gate in one file.[/b] "Crime can alter AI response
## without dependency cycles" is met because AI already declared the question
## in M7 — [HostilityProvider] — and Crime answers it here. No file in
## [code]ai/[/code] mentions a crime, a wanted level or a heat service, and no
## file here mentions a brain.
##
## It wraps rather than replaces. A guard is hostile to whoever its faction
## already dislikes [i]and[/i] to anybody wanted, so installing this adds the
## law to an entity's existing politics rather than overwriting them — which
## is what stops a policeman forgetting who its enemies are the moment a crime
## system is installed.

## Where wanted state comes from.
var heat: HeatService = null

## What is underneath: usually [FactionHostilityProvider]. Null falls back to
## the framework default, which is hostile to everything — right for an arena
## shooter, wrong for a city, and the caller's decision either way.
var inner: HostilityProvider = null

## Which faction's warrants this entity enforces. Blank enforces anybody's,
## which is what a vigilante and a lynch mob are.
var law_faction: StringName = &""

## Extra threat a wanted target carries, so a brain prioritises the fugitive
## over the pickpocket standing next to them.
var wanted_threat_bonus: float = 1.0


static func create(
	p_heat: HeatService,
	p_law_faction: StringName = &"",
	p_inner: HostilityProvider = null
) -> WantedHostilityProvider:
	var provider := WantedHostilityProvider.new()
	provider.heat = p_heat
	provider.law_faction = p_law_faction
	provider.inner = p_inner if p_inner != null else HostilityProvider.new()
	return provider


func is_hostile(observer: Node, target: Node) -> bool:
	if is_wanted(target):
		return true
	return inner.is_hostile(observer, target) if inner != null else false


func get_threat_scale(observer: Node, target: Node) -> float:
	var base := inner.get_threat_scale(observer, target) if inner != null else 1.0
	return base + wanted_threat_bonus if is_wanted(target) else base


## An ally who is wanted is not an ally. Otherwise a corrupt guard keeps
## covering for you after you shoot their sergeant.
func is_ally(observer: Node, target: Node) -> bool:
	if is_wanted(target):
		return false
	return inner.is_ally(observer, target) if inner != null else false


## Whether the law this provider enforces wants [param target].
##
## Public because it is the whole of the provider's own opinion, and a debug
## panel showing "why is this guard attacking me" should be able to ask.
func is_wanted(target: Node) -> bool:
	if heat == null or target == null:
		return false
	var actor := _identity_of(target)
	if actor == &"":
		return false
	if law_faction == &"":
		return heat.is_wanted_anywhere(actor)
	return heat.is_wanted(actor, law_faction)


## Duck-typed for the same reason [HeatService] duck-types it: Crime works
## with Factions uninstalled (rule 9, rule 31).
func _identity_of(node: Node) -> StringName:
	var components := DefinitionBinder.collect_components(node)
	for component in components:
		if component.has_method("get_actor_id"):
			var actor: Variant = component.call("get_actor_id")
			if actor is StringName and actor != &"":
				return actor
	for component in components:
		if component is PersistentIdentity:
			return (component as PersistentIdentity).get_persistent_id()
	return &""
