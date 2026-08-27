class_name ProgressionEventAdapter
extends FrameworkComponent
## Promotes levelling up to a cross-feature fact.
##
## The same seam [HealthEventAdapter] is, and here for the same reasons:
## [ProgressionComponent] stays testable with no bus in existence, the bus
## stays an optional dependency, and "is this character's levelling worth
## telling the whole game about?" becomes per-entity data rather than a
## hard-coded yes.
##
## Delete it and a character still gains levels, still spends points, still
## saves. What stops is Missions hearing about it -- the right failure mode for
## a module nobody installed.

signal progression_published(event: FrameworkEvent)

## The progression to observe, wired at composition time (rule 20).
@export var progression: ProgressionComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

@export var publish_levels: bool = true

@export var publish_skills: bool = true

const LevelEvent := preload(
	"res://addons/universal_gameplay/progression/progression_event.gd"
)
const SkillEvent := preload(
	"res://addons/universal_gameplay/progression/skill_unlocked_event.gd"
)

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if progression == null:
		progression = _find_progression()
	_bus = event_bus if event_bus != null else _find_bus()
	_register_events()
	if progression == null:
		return
	if not progression.level_gained.is_connected(_on_level):
		progression.level_gained.connect(_on_level)
	if not progression.skill_unlocked.is_connected(_on_skill):
		progression.skill_unlocked.connect(_on_skill)


func _exit_tree() -> void:
	if progression == null:
		return
	if progression.level_gained.is_connected(_on_level):
		progression.level_gained.disconnect(_on_level)
	if progression.skill_unlocked.is_connected(_on_skill):
		progression.skill_unlocked.disconnect(_on_skill)


func get_bus() -> Node:
	return _bus


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus
	_register_events()


func _register_events() -> void:
	if _bus == null or not _bus.has_method("register_event"):
		return
	_bus.call("register_event", GameplayNames.EVENT_LEVEL_GAINED)
	_bus.call("register_event", GameplayNames.EVENT_SKILL_UNLOCKED)


func _on_level(track: StringName, level: int, previous: int) -> void:
	if not publish_levels or _bus == null or not _bus.has_method("publish"):
		return
	var event := LevelEvent.create(_entity_root(), track, level, previous)
	_bus.call("publish", event)
	progression_published.emit(event)


func _on_skill(skill: StringName) -> void:
	if not publish_skills or _bus == null or not _bus.has_method("publish"):
		return
	var track := &""
	var profile := progression.get_profile() if progression != null else null
	if profile != null:
		var definition := profile.get_skill(skill)
		if definition != null:
			track = definition.track_id
	var event := SkillEvent.create(_entity_root(), skill, track)
	_bus.call("publish", event)
	progression_published.emit(event)


func _entity_root() -> Node:
	var context := get_context()
	if context != null and context.entity != null:
		return context.entity
	return get_parent()


func _find_progression() -> ProgressionComponent:
	var root := get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if child is ProgressionComponent:
			return child as ProgressionComponent
	return null


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EventBus")
