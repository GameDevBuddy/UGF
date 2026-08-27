class_name DespawnPolicy
extends Resource
## When something the world spawned is allowed to disappear again.
##
## [b]Despawn is a policy, not a rule.[/b] A pedestrian two streets behind you
## should vanish; the pedestrian you just shot should not, and neither should
## the one carrying a quest item. Making it data is what lets one project be
## generous and another aggressive without either editing the spawner
## (rule 11, rule 24).

## Distance from the observer beyond which an entity may go. Zero never
## despawns by distance.
@export_range(0.0, 100000.0, 1.0, "or_greater") var distance: float = 120.0

## Seconds an entity must have existed before it may be despawned at all,
## so something spawned just out of sight is not removed the same second.
@export_range(0.0, 3600.0, 0.1, "or_greater") var minimum_lifetime: float = 5.0

## Seconds after which it goes regardless of distance. Zero never expires.
@export_range(0.0, 86400.0, 1.0, "or_greater") var maximum_lifetime: float = 0.0

@export_group("Exemptions")
## Semantic states that keep an entity alive. An entity the player is talking
## to, fighting, or riding in is not ambient any more.
@export var protected_states: Array[StringName] = []

## Whether an entity in an active region is exempt regardless of distance.
## On is a project that streams by region and never by distance.
@export var protect_active_regions: bool = false

## Whether being visible protects an entity. The framework cannot answer that
## itself — it has no renderer — so this only takes effect when the caller
## supplies visibility.
@export var protect_visible: bool = true


func despawns_by_distance() -> bool:
	return distance > 0.0


func expires() -> bool:
	return maximum_lifetime > 0.0


## Whether an entity may be despawned now.
##
## Everything the decision needs is a parameter. No lookups, no tree walking
## and no renderer: rule 33, and the reason this is testable at all.
func allows_despawn(
	age: float, distance_to_observer: float, visible: bool = false, in_active_region: bool = false
) -> bool:
	if age < minimum_lifetime:
		return false
	if expires() and age >= maximum_lifetime:
		# An expiry is a hard deadline and outranks every exemption. Without
		# that, a protected entity in an active region lives forever and the
		# population only ever grows.
		return true
	if protect_visible and visible:
		return false
	if protect_active_regions and in_active_region:
		return false
	if not despawns_by_distance():
		return false
	return distance_to_observer >= distance


## Whether [param states] contains anything that protects the entity. Kept
## separate from [method allows_despawn] so a caller with no semantic states
## pays nothing for the feature.
func is_protected_by_state(states: Array[StringName]) -> bool:
	for state in protected_states:
		if states.has(state):
			return true
	return false


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if not despawns_by_distance() and not expires():
		result.add_warning(
			&"despawn.never",
			(
				"This policy despawns by neither distance nor age, so nothing "
				+ "using it is ever removed."
			),
			resource_path,
			"distance"
		)
	if expires() and maximum_lifetime <= minimum_lifetime:
		result.add_error(
			&"despawn.expires_before_it_may",
			(
				"This policy expires at %.1fs but protects until %.1fs, so the "
				+ "expiry fires the instant protection lifts."
			) % [maximum_lifetime, minimum_lifetime],
			resource_path,
			"maximum_lifetime"
		)
	return result
