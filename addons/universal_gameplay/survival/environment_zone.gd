class_name EnvironmentZone
extends FrameworkComponent
## A place that changes how fast a need drains: a cave, a fire, a blizzard,
## a radiation field.
##
## [b]This is the "temperature hooks" deliverable, done generically.[/b] A cold
## zone does not drain warmth itself; it multiplies how fast warmth drains.
## That is what lets two zones overlap and compose, and what makes leaving one
## restore exactly what it was doing -- a zone that drained directly would
## leave drift behind every time the player walked in and out of a cave
## (Implementation Plan 15).
##
## Wraps an [Area3D] rather than being one, the way [AreaTrigger] and
## [NavigationAdapter] do. Works with no area at all: [method apply_to] can be
## called by a project's own volume, a weather system, or a test.

signal entity_entered(entity: Node)
signal entity_exited(entity: Node)

## Stable name this zone is attributed by, so two zones affecting the same need
## do not overwrite each other and leaving one does not clear the other. Blank
## falls back to the node's name.
@export var zone_id: StringName = &""

## Needs affected, parallel to [member decay_scales].
@export var affects_needs: Array[StringName] = []

## Multiplier applied to the matching need's decay. Two is twice as fast; zero
## suspends it; below one slows it, which is what shelter is.
@export var decay_scales: Array[float] = []

## The volume to listen to. Absent, this only reacts to explicit calls.
@export var area: Area3D

## Only affect entities in this group. Blank affects everything with needs.
@export var only_group: StringName = &""

var _inside: Dictionary[int, NeedsComponent] = {}


func initialize(context: EntityContext) -> void:
	super(context)
	_connect_area()


func _ready() -> void:
	_connect_area()


func _exit_tree() -> void:
	# Every entity still inside must have the modifier lifted, or an unloaded
	# zone would go on freezing people who walked out of the level.
	for entity_id in _inside.keys():
		var needs: NeedsComponent = _inside[entity_id]
		if needs != null and is_instance_valid(needs):
			_lift_from(needs)
	_inside.clear()
	if area == null:
		return
	if area.body_entered.is_connected(_on_body_entered):
		area.body_entered.disconnect(_on_body_entered)
	if area.body_exited.is_connected(_on_body_exited):
		area.body_exited.disconnect(_on_body_exited)


func get_zone_id() -> StringName:
	return zone_id if zone_id != &"" else StringName(name)


func get_scale_for(need: StringName) -> float:
	var index := affects_needs.find(need)
	if index < 0 or index >= decay_scales.size():
		return 1.0
	return decay_scales[index]


func contains(entity: Node) -> bool:
	return entity != null and _inside.has(entity.get_instance_id())


func get_occupant_count() -> int:
	return _inside.size()


## Puts an entity under this zone's influence. Public so a weather system or a
## test can drive it without an [Area3D].
func apply_to(entity: Node) -> bool:
	if entity == null or contains(entity) or not _accepts(entity):
		return false
	var needs := _needs_of(entity)
	if needs == null:
		return false
	_inside[entity.get_instance_id()] = needs
	var count := mini(affects_needs.size(), decay_scales.size())
	for index in count:
		needs.set_decay_modifier(affects_needs[index], get_zone_id(), decay_scales[index])
	entity_entered.emit(entity)
	return true


## Lifts this zone's influence. Only this zone's: another zone's modifier on
## the same need is untouched.
func lift_from(entity: Node) -> bool:
	if entity == null or not contains(entity):
		return false
	var needs: NeedsComponent = _inside[entity.get_instance_id()]
	_inside.erase(entity.get_instance_id())
	if needs != null and is_instance_valid(needs):
		_lift_from(needs)
	entity_exited.emit(entity)
	return true


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if affects_needs.size() != decay_scales.size():
		result.add_error(
			&"zone.mismatched_arrays",
			(
				"This zone names %d needs and %d scales; the extras on one side "
				+ "are never applied."
			) % [affects_needs.size(), decay_scales.size()],
			"",
			"decay_scales"
		)
	return result


# --- Internals ------------------------------------------------------------

func _lift_from(needs: NeedsComponent) -> void:
	for need in affects_needs:
		needs.clear_decay_modifier(need, get_zone_id())


func _accepts(entity: Node) -> bool:
	return only_group == &"" or entity.is_in_group(only_group)


func _needs_of(entity: Node) -> NeedsComponent:
	for component in DefinitionBinder.collect_components(entity):
		if component is NeedsComponent:
			return component as NeedsComponent
	return null


func _connect_area() -> void:
	if area == null:
		return
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	if not area.body_exited.is_connected(_on_body_exited):
		area.body_exited.connect(_on_body_exited)


## Walks up to the entity root, so a zone affects the character rather than its
## capsule. Upward from a known node and stopping at the first entity root: the
## bounded kind of walk, not the archaeology rule 22 forbids.
func _entity_of(body: Node) -> Node:
	var node := body
	while node != null:
		if DefinitionBinder.is_entity_root(node):
			return node
		node = node.get_parent()
	return body


func _on_body_entered(body: Node) -> void:
	apply_to(_entity_of(body))


func _on_body_exited(body: Node) -> void:
	lift_from(_entity_of(body))
