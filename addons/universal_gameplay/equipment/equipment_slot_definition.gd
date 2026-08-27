class_name EquipmentSlotDefinition
extends FrameworkDefinition
## One place an item can be worn.
##
## Head, main hand, off hand, a vehicle's turret mount. Data, so a project
## inventing a "tail" slot writes a [code].tres[/code] (rule 11).

## Item categories this slot takes. Empty accepts any category the item's own
## [EquipmentProfile] says fits here.
@export var accepted_categories: Array[StringName] = []

## Order for display, low first. Purely presentational.
@export var sort_order: int = 0


## Whether this slot would take that item, checking both directions: the item
## must name this slot, and this slot must not refuse its category.
func accepts(definition: ItemDefinition) -> bool:
	if definition == null or definition.equipment == null:
		return false
	if not definition.equipment.fits_slot(id):
		return false
	if not accepted_categories.is_empty() and not accepted_categories.has(definition.category):
		return false
	return true


func validate() -> ValidationResult:
	return super()
