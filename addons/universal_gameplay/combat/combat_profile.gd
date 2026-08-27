class_name CombatProfile
extends Resource
## How an entity fights when nothing is in its hands.
##
## Small on purpose. Almost everything about an attack belongs to the weapon;
## what belongs to the fighter is what it does unarmed, what it spends, and how
## far its aim starts from its feet.

## The attack used with no weapon equipped. Null means an unarmed entity simply
## cannot attack, which is right for a civilian.
@export var unarmed: AttackDefinition

## Metres above the entity's origin that attacks come from, when no explicit
## aim node is wired. Roughly eye height for a person.
@export_range(0.0, 5.0, 0.01) var aim_height: float = 1.6

@export_group("Cost")
## Stat attacks spend when their own [member AttackDefinition.cost_stat] is
## blank. Lets one profile put every attack on stamina without editing each.
@export var default_cost_stat: StringName = &"stat.stamina"


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if unarmed != null:
		result.merge(unarmed.validate())
	return result
