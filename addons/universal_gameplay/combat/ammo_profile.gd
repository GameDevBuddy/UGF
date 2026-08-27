class_name AmmoProfile
extends Resource
## What a weapon spends, where it comes from, and how it is put back.
##
## One configured resource rather than the four strategy classes Implementation
## Plan 13 sketches. Magazine-fed, reserve-fed, energy and infinite are the
## same three numbers with different values -- a magazine of zero is infinite,
## a reserve of -1 is unlimited, and drawing from an inventory instead of an
## abstract reserve is one item id (rule 23: no abstraction without
## demonstrated reuse, and here there is none to demonstrate).

## Rounds a full magazine holds. Zero means the weapon has no magazine and
## fires forever: a laser pointer, a melee weapon, a debug gun.
@export_range(0, 999) var magazine_size: int = 30

## Rounds carried outside the magazine. Negative means unlimited, which is the
## right answer for a game that tracks magazines but not backpacks.
@export_range(-1, 9999) var reserve_capacity: int = 120

## Rounds a single shot spends. Above one for a weapon that burns a cell.
@export_range(1, 99) var cost_per_shot: int = 1

@export_group("Reloading")
@export_range(0.0, 30.0, 0.01, "or_greater") var reload_time: float = 2.0

## Reload a round at a time rather than a whole magazine, so the reload can be
## interrupted and keep what it loaded. The shotgun.
@export var incremental: bool = false

## Rounds loaded per step of an incremental reload.
@export_range(1, 99) var rounds_per_step: int = 1

@export_group("Inventory")
## Item the reserve is drawn from. Blank uses the abstract reserve count, which
## is what a game with no ammo items wants. Naming an item makes the reserve
## the bag: rule 32, an id rather than a resource reference, so Combat does not
## have to load the Items content it shoots.
@export var ammo_item_id: StringName = &""


func is_infinite() -> bool:
	return magazine_size <= 0


func has_unlimited_reserve() -> bool:
	return reserve_capacity < 0


func draws_from_inventory() -> bool:
	return ammo_item_id != &""


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if is_infinite() and reload_time > 0.0:
		result.add_warning(
			&"ammo.reload_without_magazine",
			(
				"This weapon has no magazine, so its reload time will never be "
				+ "waited out."
			),
			resource_path,
			"reload_time"
		)
	if not is_infinite() and cost_per_shot > magazine_size:
		result.add_error(
			&"ammo.shot_costs_more_than_magazine",
			"A shot costs more than a full magazine holds, so it can never fire.",
			resource_path,
			"cost_per_shot"
		)
	if incremental and is_infinite():
		result.add_warning(
			&"ammo.incremental_without_magazine",
			"An incremental reload on a weapon with no magazine does nothing.",
			resource_path,
			"incremental"
		)
	return result
