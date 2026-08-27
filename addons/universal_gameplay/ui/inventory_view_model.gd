class_name InventoryViewModel
extends ViewModel
## What a bag panel draws.
##
## Rows of plain data, not [ItemInstance]s. An instance is live state — a
## widget holding one can degrade it, split it, or change its quantity — and a
## bag panel that can destroy items is exactly what rule 21 exists to prevent.

## One row per stack: id, display name, quantity, condition, weight, value.
var rows: Array[Dictionary] = []

var used_slots: int = 0
var free_slots: int = 0
var total_weight: float = 0.0
var maximum_weight: float = 0.0
var total_value: float = 0.0


func is_empty() -> bool:
	return rows.is_empty()


func get_row(item_id: StringName) -> Dictionary:
	for row in rows:
		if row["item_id"] == item_id:
			return row
	return {}


func has_item(item_id: StringName) -> bool:
	return not get_row(item_id).is_empty()


func get_quantity(item_id: StringName) -> int:
	var row := get_row(item_id)
	return int(row.get("quantity", 0))


## Weight as a fraction of the limit, for a bar. One when there is no limit,
## so an unlimited bag reads as empty rather than as full.
func get_weight_fraction() -> float:
	if maximum_weight <= 0.0:
		return 0.0
	return clampf(total_weight / maximum_weight, 0.0, 1.0)


func is_over_weight() -> bool:
	return maximum_weight > 0.0 and total_weight > maximum_weight


func to_dictionary() -> Dictionary:
	var data := super()
	data.merge({
		"rows": rows.duplicate(true),
		"used_slots": used_slots,
		"free_slots": free_slots,
		"total_weight": total_weight,
		"maximum_weight": maximum_weight,
		"total_value": total_value,
	})
	return data
