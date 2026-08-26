extends FrameworkEvent
## Module-owned event fixture. Stands in for the kind of fact a feature module
## registers on the bus rather than Core declaring it.

const EVENT_NAME: StringName = &"sample_thing_happened"

var detail: String = ""


func configure(p_source: Node, p_detail: String = "") -> void:
	source = p_source
	detail = p_detail


func get_event_name() -> StringName:
	return EVENT_NAME


func describe() -> String:
	return "sample_thing_happened: %s" % detail
