class_name HudPresenter
extends Presenter
## Collects several presenters into one snapshot.
##
## [b]A HUD redraws once, not five times.[/b] Five presenters emitting
## independently means a frame where health has updated and the mission tracker
## has not, and a project that wants one consistent draw has to coalesce them
## itself — which every project would then do slightly differently.
##
## It owns no presenters and creates none. A project composes the ones it wants
## as children and wires them here, which is what keeps a HUD with no inventory
## panel a valid HUD (rule 31).

## The presenters to aggregate, keyed in the model by their node names. Wired
## at composition time (rule 20).
@export var presenters: Array[Presenter] = []

## Whether to publish on every child change. Off lets a project pull
## [method get_model] on its own cadence instead, which is what a HUD
## redrawing once a frame wants.
@export var publish_on_change: bool = true


func observe() -> void:
	for presenter in presenters:
		_watch(presenter, &"view_changed", _on_child_changed)


func stop_observing() -> void:
	for presenter in presenters:
		_unwatch(presenter, &"view_changed", _on_child_changed)


## Adds a presenter at runtime. What entering a vehicle or opening a shop does
## to a HUD that grows a panel.
func add_presenter(presenter: Presenter) -> bool:
	if presenter == null or presenters.has(presenter):
		return false
	presenters.append(presenter)
	_watch(presenter, &"view_changed", _on_child_changed)
	refresh()
	return true


func remove_presenter(presenter: Presenter) -> bool:
	var index := presenters.find(presenter)
	if index < 0:
		return false
	_unwatch(presenter, &"view_changed", _on_child_changed)
	presenters.remove_at(index)
	refresh()
	return true


## One presenter's model by name, for a widget that only wants its own.
func get_panel(panel_name: StringName) -> ViewModel:
	var model := get_model() as HudViewModel
	return model.get_panel(panel_name) if model != null else null


func build() -> ViewModel:
	var model := HudViewModel.new()
	model.present = not presenters.is_empty()
	for presenter in presenters:
		if presenter == null or not is_instance_valid(presenter):
			continue
		model.set_panel(StringName(presenter.name), presenter.get_model())
	return model


func _on_child_changed(_child_model: ViewModel) -> void:
	if publish_on_change:
		refresh()
