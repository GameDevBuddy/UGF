class_name NPCRoleDefinition
extends FrameworkDefinition
## What an NPC is for: civilian, guard, combatant, vendor, companion.
##
## [b]This definition is the M7 exit gate.[/b] A civilian, a guard and a
## combatant are three of these resources pointed at by three character
## definitions that share one scene and one component set. None of them is a
## subclass, and adding a fourth role creates a [code].tres[/code] and no
## GDScript at all (rule 11, rule 13, rule 15).

## What this NPC can notice. Null leaves it oblivious, which is correct for a
## shop mannequin and wrong for almost anything else.
@export var perception: PerceptionProfile

## How it decides. Null makes it inert: it perceives and does nothing, which is
## a useful state for a scripted actor a cutscene drives.
@export var brain: AIBrain

@export_group("Disposition")
## Semantic tags a brain and a project match on: [code]role.vendor[/code],
## [code]role.law[/code]. Not faction membership, which is M10's business and
## deliberately not declared here (rules 1 and 10).
@export var disposition_tags: Array[StringName] = []

## How dangerous this NPC looks to others. Copied onto its [Perceivable] when
## one is not authored separately.
@export_range(0.0, 100.0, 0.1, "or_greater") var threat: float = 1.0

@export_group("Movement")
## Metres per second this role moves at when it is not in a hurry. Zero uses
## the movement profile's own walk speed.
@export_range(0.0, 20.0, 0.01) var patrol_speed: float = 0.0

## Metres it will wander from where it started. Zero stands still.
@export_range(0.0, 200.0, 0.1, "or_greater") var wander_radius: float = 0.0

## Metres from its post before it turns back. Zero never leashes, which is what
## a roaming predator wants and what a doorman does not.
@export_range(0.0, 500.0, 0.1, "or_greater") var leash_radius: float = 0.0

@export_group("Interaction")
## What can be done to this NPC: talk, trade, rob. The vendor half of the role,
## and the reason a shopkeeper needs no Vendor script before M11.
@export var interactions: Array[InteractionDefinition] = []


func has_tag_of(tag: StringName) -> bool:
	return disposition_tags.has(tag)


func can_think() -> bool:
	return brain != null


func validate() -> ValidationResult:
	var result := super()
	if perception == null:
		result.add_warning(
			&"role.no_perception",
			(
				"%s has no perception profile, so it will never notice anything. "
				+ "Correct for a scripted actor; probably not for a guard."
			) % get_debug_name(),
			resource_path,
			"perception"
		)
	else:
		result.merge(perception.validate())
	if brain == null:
		result.add_warning(
			&"role.no_brain",
			"%s has no brain, so it will perceive and never act." % get_debug_name(),
			resource_path,
			"brain"
		)
	else:
		result.merge(brain.validate())
	if leash_radius > 0.0 and wander_radius > leash_radius:
		result.add_warning(
			&"role.wanders_past_its_leash",
			(
				"%s wanders further than its leash allows, so it will spend its "
				+ "time being pulled back."
			) % get_debug_name(),
			resource_path,
			"wander_radius"
		)
	for offered in interactions:
		if offered != null:
			result.merge(offered.validate())
	return result
