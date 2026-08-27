class_name Presenter
extends FrameworkComponent
## Watches one part of the world and publishes snapshots of it.
##
## [b]This is the whole UI architecture.[/b] A presenter subscribes to local
## signals, builds a [ViewModel], and emits it. A widget connects to
## [signal view_changed] and draws. Nothing else passes between them — no
## component references, no service handles, no callbacks that mutate.
##
## [b]It is read-only by construction, and that is asserted.[/b] The M17 exit
## gate is "UI contains no domain authority", and a test reads every file in
## [code]ui/[/code] and fails on a call that would change the world. A health
## bar that can kill you is not a bug you find in review; it is one you find in
## a bug report six months later.
##
## The framework ships presenters and no widgets. What a health bar looks like
## is a project's decision about its own game (rule 21, rule 29) — but *when*
## it should redraw, and *what* it needs to know, is a question every project
## answers the same way, and that is what lives here.

## Emitted whenever the snapshot changes.
signal view_changed(model: ViewModel)

## Whether to publish on initialisation, so a widget connected before the
## first change has something to draw.
@export var publish_on_bind: bool = true

var _model: ViewModel = null


func initialize(context: EntityContext) -> void:
	super(context)
	observe()
	if publish_on_bind:
		refresh()


func _exit_tree() -> void:
	stop_observing()


# --- Queries --------------------------------------------------------------

## The most recent snapshot, building one if nothing has been published yet.
func get_model() -> ViewModel:
	if _model == null:
		_model = build()
	return _model


## Whether there is anything to show. A HUD hides the whole panel rather than
## drawing an empty one.
func has_subject() -> bool:
	return get_model().present


# --- Publishing -----------------------------------------------------------

## Rebuilds the snapshot and publishes it.
##
## Public because a project driving its own redraw cadence — once a frame, on a
## timer, on a menu opening — should not have to wait for a signal it may have
## missed.
func refresh() -> void:
	_model = build()
	view_changed.emit(_model)


## Builds a snapshot. Overridden by every concrete presenter; the base returns
## an absent one, which is the honest answer for a presenter watching nothing.
func build() -> ViewModel:
	return ViewModel.new()


# --- Observation ----------------------------------------------------------
#
# Split into two so a presenter can be re-pointed at a different subject at
# runtime -- a HUD following whichever character the player is possessing --
# without rebuilding the node.

## Connects to whatever this presenter watches. Overridden by concrete
## presenters; the base watches nothing.
func observe() -> void:
	pass


## Disconnects. Overridden alongside [method observe], and called on
## [method Node._exit_tree] so a presenter never outlives its connections.
func stop_observing() -> void:
	pass


## Re-points this presenter and republishes.
func rebind() -> void:
	stop_observing()
	observe()
	refresh()


# --- Internals ------------------------------------------------------------

## Connects [param handler] to [param source]'s signal if it is not already,
## which is what makes [method observe] safe to call twice.
func _watch(source: Object, signal_name: StringName, handler: Callable) -> void:
	if source == null or not is_instance_valid(source):
		return
	if source.has_signal(signal_name) and not source.is_connected(signal_name, handler):
		source.connect(signal_name, handler)


func _unwatch(source: Object, signal_name: StringName, handler: Callable) -> void:
	if source == null or not is_instance_valid(source):
		return
	if source.has_signal(signal_name) and source.is_connected(signal_name, handler):
		source.disconnect(signal_name, handler)


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
