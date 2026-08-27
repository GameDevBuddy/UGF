class_name CrimeFactionAdapter
extends Node
## Turns crimes into standing with the wronged faction. The
## CrimeFactionAdapter of Implementation Plan 39.
##
## [b]Every reputation consequence of crime is here, and none of it is in
## [HeatService].[/b] That service owns heat and wanted tiers and has no
## dependency on Factions at all, so a project can have a wanted level with no
## social system behind it — and one with both gets the standing consequences
## by adding this file (rule 4, rule 10).
##
## The arithmetic is Factions' own [method
## FactionService.propagate_reputation], which already spends the direct cost
## with the wronged faction, spreads a share to its allies weighted by how much
## they like it, and — because a negative relation times a negative amount is
## positive — quietly rewards its enemies. Re-deriving any of that here would
## be the same rule twice, disagreeing (rule 23).

signal consequences_applied(actor_id: StringName, faction: StringName)

@export var heat: HeatService
@export var factions: FactionService

## How far the news travels, as a fraction of the direct cost. Zero keeps the
## crime between the offender and the faction they wronged; one makes every
## faction with an opinion of that faction take it personally.
##
## The same number covers allies and enemies, because it is one propagation:
## a faction that likes the victim loses standing with the offender and one
## that hates them gains it, in proportion to how strongly they feel.
@export_range(0.0, 1.0, 0.01) var spread: float = 0.5

var _watched: HeatService = null


func _ready() -> void:
	watch(heat)


func _exit_tree() -> void:
	watch(null)


func watch(target: HeatService) -> void:
	if _watched == target:
		return
	if _watched != null and _watched.crime_reported.is_connected(_on_crime):
		_watched.crime_reported.disconnect(_on_crime)
	_watched = target
	heat = target
	if _watched != null and not _watched.crime_reported.is_connected(_on_crime):
		_watched.crime_reported.connect(_on_crime)


func _on_crime(context: CrimeContext) -> void:
	apply(context)


## Spreads the consequences of one crime. Public so a project reporting crimes
## its own way reaches the same path.
func apply(context: CrimeContext) -> void:
	if factions == null or context == null or context.definition == null:
		return
	if context.actor_id == &"" or context.law_faction == &"":
		return
	var cost := context.definition.reputation_cost
	if cost <= 0.0:
		return

	# One call. It applies the direct cost and the propagation together, which
	# is why nothing here adds the direct cost first -- doing both would charge
	# the offender twice for one crime.
	factions.propagate_reputation(
		context.law_faction, context.actor_id, -cost, spread
	)
	consequences_applied.emit(context.actor_id, context.law_faction)
