class_name Perceivable
extends FrameworkComponent
## Marks an entity as something an NPC can notice, and says how noticeable it
## is.
##
## Explicit rather than inferred. Perception could scan for anything with
## health, or anything with a controller, and both would be wrong in ways that
## only show up late: a destructible crate is not something a guard stares at,
## and a possessed vehicle is. Membership of
## [constant GameplayNames.GROUP_PERCEIVABLE] is a decision the entity's
## composition makes (Ontology Rulebook 12).
##
## It is also where stealth lives. Crouching halving your visibility is a
## multiplier on this component, not a special case inside every NPC's sight
## check -- and a project with no stealth simply never changes it.

## Emitted when this entity becomes noticeable or stops being so.
signal perceptibility_changed(perceivable: bool)

## Off hides the entity from every sweep: a ghost, a cutscene actor, a corpse
## nobody should react to any more.
@export var perceivable: bool = true

## Multiplier on the distance this entity can be seen from. Below one is
## harder to spot; above one is a lit torch.
@export_range(0.0, 4.0, 0.01) var visibility_scale: float = 1.0

## How dangerous this entity looks. A brain sorts what it can see by this
## before deciding what to do about it.
@export_range(0.0, 100.0, 0.1, "or_greater") var threat: float = 1.0

## Semantic tags a brain matches on: [code]actor.civilian[/code],
## [code]actor.law[/code]. Not faction membership, which is M10's business.
@export var tags: Array[StringName] = []

## Metres above the entity's origin that it is looked at. Chest height, so a
## sight line to a person is not a line to their feet.
@export_range(0.0, 5.0, 0.01) var focus_height: float = 1.2

## States mirrored onto visibility. While any of these is set, the entity is
## scaled by [member hidden_visibility_scale] -- crouching, prone, in cover.
@export var concealing_states: Array[StringName] = []

@export_range(0.0, 1.0, 0.01) var hidden_visibility_scale: float = 0.5

## Where concealing states are read from. Found among this entity's own
## components when it is not wired.
@export var semantic_state: SemanticState


func _ready() -> void:
	_register()


func initialize(context: EntityContext) -> void:
	super(context)
	if semantic_state == null:
		semantic_state = _find_semantic_state()
	_register()


func _exit_tree() -> void:
	var root := _get_root()
	if root != null:
		root.remove_from_group(GameplayNames.GROUP_PERCEIVABLE)


## Turns noticeability on or off at runtime.
func set_perceivable(value: bool) -> void:
	if value == perceivable:
		return
	perceivable = value
	_register()
	perceptibility_changed.emit(perceivable)


## Effective visibility multiplier right now, concealment included.
func get_visibility() -> float:
	if not perceivable:
		return 0.0
	if _is_concealed():
		return visibility_scale * hidden_visibility_scale
	return visibility_scale


## The point an observer looks at. Not the origin, which for a character is the
## floor between their feet.
func get_focus_position() -> Vector3:
	var root := _get_root()
	if root is Node3D and (root as Node3D).is_inside_tree():
		return (root as Node3D).global_position + Vector3.UP * focus_height
	return Vector3.ZERO


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## The perceivable component on [param node], or null.
static func find_on(node: Node) -> Perceivable:
	if node == null:
		return null
	if node is Perceivable:
		return node as Perceivable
	for component in DefinitionBinder.collect_components(node):
		if component is Perceivable:
			return component as Perceivable
	return null


# --- Internals ------------------------------------------------------------

func _is_concealed() -> bool:
	if semantic_state == null or concealing_states.is_empty():
		return false
	return semantic_state.has_any_state(concealing_states)


func _register() -> void:
	var root := _get_root()
	if root == null or not root.is_inside_tree():
		return
	if perceivable:
		root.add_to_group(GameplayNames.GROUP_PERCEIVABLE)
	else:
		root.remove_from_group(GameplayNames.GROUP_PERCEIVABLE)


## The entity this component speaks for. Falls back to the parent so a plain
## scene with no binder is still perceivable (rule 31).
func _get_root() -> Node:
	var entity := get_entity()
	return entity if entity != null else get_parent()


func _find_semantic_state() -> SemanticState:
	var root := _get_root()
	if root == null:
		return null
	for component in DefinitionBinder.collect_components(root):
		if component is SemanticState:
			return component as SemanticState
	return null
