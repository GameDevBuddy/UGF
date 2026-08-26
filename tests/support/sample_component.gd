extends FrameworkComponent
## Persistent component fixture, exercising the capture/restore contract.

signal value_changed(new_value: int)

var value: int = 0
var initialize_count: int = 0


func initialize(context: EntityContext) -> void:
	super(context)
	initialize_count += 1
	var definition := get_definition()
	if definition != null and definition.has_tag(&"sample.boosted"):
		value = 100


func set_value(new_value: int) -> void:
	if new_value == value:
		return
	value = new_value
	value_changed.emit(value)


func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"value": value}


func restore_state(data: Dictionary) -> void:
	# Missing keys are normal: a save written before this field existed is a
	# valid save, not a corrupt one.
	value = int(data.get("value", 0))
