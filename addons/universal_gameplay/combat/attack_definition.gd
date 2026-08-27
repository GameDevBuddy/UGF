class_name AttackDefinition
extends FrameworkDefinition
## One attack: what it costs, how long it takes, how it reaches, what it deals.
##
## A sword swing, a rifle shot, a shotgun blast, a rocket and a shove are five
## of these. The only thing that distinguishes a melee attack from a ranged one
## is its [member delivery], which is why the exit gate for this milestone --
## ranged and melee producing the same [DamageContext] -- is a statement about
## content rather than about code (rule 11, rule 13).
##
## [b]Timing is three numbers, and they are the state machine.[/b] Startup is
## the wind-up, active is the damage window, recovery is the follow-through.
## An attack with all three at zero resolves the instant it is asked to, which
## is exactly what a hitscan shot is -- so a rifle needs no special path
## through the state machine, it needs zeroes.

## Damage before mitigation. Zero is legitimate: a shove, a taunt, a scan.
@export_range(0.0, 9999.0, 0.1, "or_greater") var damage: float = 10.0

## Semantic damage vocabulary. Resistances and status effects match on these.
@export var damage_tags: Array[StringName] = []

@export_group("Timing")
## Wind-up before the damage window opens.
@export_range(0.0, 10.0, 0.01, "or_greater") var startup: float = 0.0

## How long the damage window stays open. Zero resolves on a single frame,
## which is what a shot is; a sword's window is long enough to sweep.
@export_range(0.0, 10.0, 0.01, "or_greater") var active: float = 0.0

## Follow-through the actor is committed to after the window closes.
@export_range(0.0, 10.0, 0.01, "or_greater") var recovery: float = 0.0

## Whether the attack can be cut short once begun. Off is a commitment: a
## heavy swing that lands whatever happens to the attacker mid-animation.
@export var interruptible: bool = true

@export_group("Cost")
## Stat spent to attack, e.g. [code]stat.stamina[/code]. Blank costs nothing.
@export var cost_stat: StringName = &""

@export_range(0.0, 999.0, 0.1, "or_greater") var cost: float = 0.0

@export_group("Delivery")
## How it reaches. Null resolves no hits at all, which is right for an attack
## whose effect is entirely in what listens to it.
@export var delivery: AttackDelivery

@export_group("Presentation")
## Animation this attack plays, read by an adapter. A semantic key rather than
## a resource, so Combat does not depend on a rig (rule 21, rule 32).
@export var animation_key: StringName = &""

@export_group("Combos")
## Vocabulary a project's own chaining matches on: [code]combo.light[/code],
## [code]combo.finisher[/code]. The framework carries the tags and chains
## nothing itself -- what follows what is a design decision, and rule 24 says
## an optional mechanism does not become mandatory structure.
@export var combo_tags: Array[StringName] = []


func get_duration() -> float:
	return CombatSolver.total_duration(startup, active, recovery)


## True when the attack resolves the moment it is asked to, with no window.
func is_instant() -> bool:
	return get_duration() <= 0.0


func has_cost() -> bool:
	return cost_stat != &"" and cost > 0.0


func get_reach() -> float:
	return delivery.get_maximum_range() if delivery != null else 0.0


func has_combo_tag(tag: StringName) -> bool:
	return combo_tags.has(tag)


func validate() -> ValidationResult:
	var result := super()
	if delivery == null:
		result.add_warning(
			&"attack.no_delivery",
			(
				"%s has no delivery, so it will never connect with anything. "
				+ "Correct for an attack whose whole effect is its signal."
			) % get_debug_name(),
			resource_path,
			"delivery"
		)
	else:
		result.merge(delivery.validate())
	if damage_tags.is_empty() and damage > 0.0:
		result.add_warning(
			&"attack.untagged_damage",
			(
				"%s deals damage with no tags, so no resistance or immunity can "
				+ "ever apply to it."
			) % get_debug_name(),
			resource_path,
			"damage_tags"
		)
	if cost > 0.0 and cost_stat == &"":
		result.add_warning(
			&"attack.cost_without_stat",
			"%s has a cost but names no stat to spend, so it is free." % get_debug_name(),
			resource_path,
			"cost_stat"
		)
	return result
