class_name AttackDelivery
extends Resource
## How an attack reaches what it is aimed at.
##
## The one abstraction in Combat that earns a strategy hierarchy, because the
## three shipped implementations genuinely differ in kind rather than in
## configuration: a melee arc queries a volume, a hitscan queries a ray, a
## projectile queries nothing at all and answers later (rule 23).
##
## [b]A delivery decides geometry, not consequences.[/b] It returns
## [CombatHit]s and applies no damage. That is what lets one delivery serve a
## sword, a healing beam and a scanner, and what keeps every one of them
## testable against a fake [HitProvider].

## Resolves what this attack connects with, now.
##
## Returns an empty array for a delivery whose hits arrive later, which is not
## a miss -- a projectile in flight has hit nothing yet.
func resolve(_context: AttackContext, _provider: HitProvider) -> Array[CombatHit]:
	var empty: Array[CombatHit] = []
	return empty


## Furthest this attack can reach, for AI deciding whether to close in and for
## validation. Zero means it does not reach at all.
func get_maximum_range() -> float:
	return 0.0


func validate() -> ValidationResult:
	return ValidationResult.new()
