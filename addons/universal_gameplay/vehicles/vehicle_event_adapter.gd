class_name VehicleEventAdapter
extends FrameworkComponent
## Promotes getting in, getting out and getting wrecked to cross-feature facts.
##
## The same seam [InventoryEventAdapter] and [FactionEventAdapter] are, and
## deletable for the same reason: [SeatComponent] and [VehicleComponent] emit
## local signals and have never heard of the bus (rule 7, rule 10). Delete this
## file and vehicles still work; missions simply stop hearing about them.
##
## With it, the plan's EnterVehicle and DriveTo objectives are content: an
## objective matching [code]vehicle_entered[/code] with
## [code]driver == true[/code] is "steal a car", and Missions never imports
## Vehicles.

## Emitted after publication, for debug tooling watching the promotion.
signal vehicle_published(event: FrameworkEvent)

## Who is aboard, wired at composition time (rule 20).
@export var seats: SeatComponent

## The vehicle, for the destruction fact and for its tags.
@export var vehicle: VehicleComponent

## Injected bus. Left null, the adapter finds the [code]EventBus[/code]
## autoload -- the same narrow exception [DefinitionBinder] makes.
@export var event_bus: Node

@export var publish_entries: bool = true
@export var publish_destruction: bool = true

const VehicleEvent := preload(
	"res://addons/universal_gameplay/vehicles/vehicle_event.gd"
)

var _bus: Node = null


func initialize(context: EntityContext) -> void:
	super(context)
	if seats == null:
		seats = _find(SeatComponent) as SeatComponent
	if vehicle == null:
		vehicle = _find(VehicleComponent) as VehicleComponent

	_bus = event_bus if event_bus != null else _find_bus()
	if _bus != null and _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_VEHICLE_ENTERED)
		_bus.call("register_event", GameplayNames.EVENT_VEHICLE_EXITED)
		_bus.call("register_event", GameplayNames.EVENT_VEHICLE_DESTROYED)

	if seats != null and not seats.occupant_entered.is_connected(_on_entered):
		seats.occupant_entered.connect(_on_entered)
		seats.occupant_exited.connect(_on_exited)
	if vehicle != null and not vehicle.destroyed.is_connected(_on_destroyed):
		vehicle.destroyed.connect(_on_destroyed)


func _exit_tree() -> void:
	if seats != null and seats.occupant_entered.is_connected(_on_entered):
		seats.occupant_entered.disconnect(_on_entered)
		seats.occupant_exited.disconnect(_on_exited)
	if vehicle != null and vehicle.destroyed.is_connected(_on_destroyed):
		vehicle.destroyed.disconnect(_on_destroyed)


func get_bus() -> Node:
	return _bus


func set_bus(bus: Node) -> void:
	event_bus = bus
	_bus = bus


# --- Internals ------------------------------------------------------------

func _on_entered(occupant: Node, seat: SeatDefinition) -> void:
	if not publish_entries:
		return
	_publish(
		VehicleEvent.entered(
			_vehicle_id(), _identity_of(occupant), seat.id, seat.is_driver(), _tags()
		)
	)


func _on_exited(occupant: Node, seat: SeatDefinition) -> void:
	if not publish_entries or seat == null:
		return
	_publish(
		VehicleEvent.exited(
			_vehicle_id(), _identity_of(occupant), seat.id, seat.is_driver(), _tags()
		)
	)


func _on_destroyed() -> void:
	if publish_destruction:
		_publish(VehicleEvent.destroyed(_vehicle_id(), _tags()))


func _publish(event: FrameworkEvent) -> void:
	if _bus == null or not _bus.has_method("publish"):
		return
	_bus.call("publish", event)
	vehicle_published.emit(event)


## The vehicle's persistent id, falling back to its definition id. A vehicle
## with neither publishes a blank, which an objective matching on a specific
## car will simply never match -- the right failure for content that named
## nothing.
func _vehicle_id() -> StringName:
	var entity := get_entity()
	if entity != null:
		for component in DefinitionBinder.collect_components(entity):
			if component is PersistentIdentity:
				var id := (component as PersistentIdentity).get_persistent_id()
				if id != &"":
					return id
	var definition := vehicle.get_vehicle() if vehicle != null else null
	return definition.id if definition != null else &""


func _tags() -> Array[StringName]:
	var definition := vehicle.get_vehicle() if vehicle != null else null
	return definition.vehicle_tags.duplicate() if definition != null else []


func _identity_of(node: Node) -> StringName:
	if node == null:
		return &""
	for component in DefinitionBinder.collect_components(node):
		if component is PersistentIdentity:
			return (component as PersistentIdentity).get_persistent_id()
	return &""


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


func _find_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus")
