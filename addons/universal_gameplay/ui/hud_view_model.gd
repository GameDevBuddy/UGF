class_name HudViewModel
extends ViewModel
## Every panel's snapshot, taken together.
##
## Keyed by presenter node name rather than by type, so a HUD with two
## inventory panels — the player's bag and the chest they opened — can tell
## them apart.

var panels: Dictionary = {}


func set_panel(panel_name: StringName, model: ViewModel) -> void:
	if model != null:
		panels[panel_name] = model


func get_panel(panel_name: StringName) -> ViewModel:
	return panels.get(panel_name)


func has_panel(panel_name: StringName) -> bool:
	return panels.has(panel_name)


func get_panel_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(panels.keys())
	return names


func get_panel_count() -> int:
	return panels.size()


func to_dictionary() -> Dictionary:
	var data := super()
	var described: Dictionary = {}
	for panel_name in panels:
		described[String(panel_name)] = (panels[panel_name] as ViewModel).to_dictionary()
	data["panels"] = described
	return data
