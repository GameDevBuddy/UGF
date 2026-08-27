class_name FactionDefinition
extends FrameworkDefinition
## A group with opinions: a town watch, a bandit clan, a corporation, a species.
##
## [b]Relations are authored one-way and per pair.[/b] The watch hating bandits
## does not make bandits hate the watch by the same amount, and a symmetric
## store cannot say that. [method get_default_relation] answers only for this
## faction's view; [FactionService] holds the live values.

## Where standing with this faction starts for a party with no history.
@export_range(-100.0, 100.0, 0.1) var default_standing: float = 0.0

@export_group("Standing bands")
## At or below this, members attack on sight.
@export_range(-100.0, 100.0, 0.1) var hostile_below: float = -50.0

## At or below this, members are wary but not fighting.
@export_range(-100.0, 100.0, 0.1) var wary_below: float = -15.0

## At or above this, members are friendly.
@export_range(-100.0, 100.0, 0.1) var friendly_above: float = 25.0

## At or above this, members will fight for you.
@export_range(-100.0, 100.0, 0.1) var allied_above: float = 70.0

@export_group("Relations")
## Other faction ids this one has an opinion about. Parallel to
## [member relation_values]; ids rather than references so a faction does not
## load every faction it has heard of (rule 32).
@export var relation_factions: Array[StringName] = []

## Standing towards the faction at the same index.
@export var relation_values: Array[float] = []

@export_group("Vocabulary")
## What kind of group this is: [code]faction.law[/code],
## [code]faction.criminal[/code]. Matched on by content, never by the
## framework.
@export var role_tags: Array[StringName] = []


## This faction's authored opinion of [param other], or its default standing
## when it has none.
func get_default_relation(other: StringName) -> float:
	var index := relation_factions.find(other)
	if index >= 0 and index < relation_values.size():
		return relation_values[index]
	if other == id:
		# A faction is allied with itself unless the content says otherwise,
		# which is what stops guards shooting each other.
		return maxf(allied_above, default_standing)
	return default_standing


func has_role_tag(tag: StringName) -> bool:
	return role_tags.has(tag)


## Which band [param standing] falls in for this faction's thresholds.
func resolve_attitude(standing: float) -> AttitudeSolver.Attitude:
	return AttitudeSolver.resolve(
		standing, hostile_below, wary_below, friendly_above, allied_above
	)


func validate() -> ValidationResult:
	var result := super()
	if relation_factions.size() != relation_values.size():
		result.add_error(
			&"faction.mismatched_relations",
			(
				"%s has %d relations and %d values; the extras on one side are "
				+ "never read."
			) % [get_debug_name(), relation_factions.size(), relation_values.size()],
			resource_path,
			"relation_values"
		)
	var ordered := (
		hostile_below <= wary_below
		and wary_below < friendly_above
		and friendly_above <= allied_above
	)
	if not ordered:
		result.add_error(
			&"faction.unordered_bands",
			(
				"%s has overlapping standing bands, so its attitudes do not "
				+ "run from hostile to allied in order."
			) % get_debug_name(),
			resource_path,
			"wary_below"
		)
	if relation_factions.has(id):
		var self_index := relation_factions.find(id)
		if self_index < relation_values.size() and relation_values[self_index] <= hostile_below:
			result.add_warning(
				&"faction.hostile_to_itself",
				"%s is hostile to its own members, who will attack each other." % get_debug_name(),
				resource_path,
				"relation_values"
			)
	for index in relation_factions.size():
		if relation_factions[index] == &"":
			result.add_warning(
				&"faction.empty_relation",
				"%s has a relation towards an unnamed faction." % get_debug_name(),
				resource_path,
				"relation_factions"
			)
	return result
