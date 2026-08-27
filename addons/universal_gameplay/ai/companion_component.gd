class_name CompanionComponent
extends FrameworkComponent
## Somebody who follows you and does what you tell them.
##
## Implementation Plan 21 lists Companion as "AI profile + party relation +
## follow/command hooks" -- three additive pieces, not a subclass. The plan is
## explicit one line earlier that NPC roles are additive capabilities and data
## rather than a class hierarchy, so a CompanionBrain would have been the
## obvious answer and the wrong one (rule 6). This is the party relation and
## the command hooks; the AI profile is whatever [RoleBrain] the project
## already gave the character.
##
## [b]An order outranks a stance, and nothing else changes.[/b] A companion
## told to wait waits, even a passive one; a companion with no order behaves
## exactly like any other NPC with the same role. That is the whole
## integration: [RoleBrain] asks whether there is an order before it decides
## what to do on its own, and finds nothing on every NPC that is not a
## companion.
##
## [b]Threat still wins.[/b] A companion ordered to wait still defends itself
## when something starts shooting, because an order that got a follower killed
## while it stood there is an order nobody would ever give.

## Emitted when the standing order changes.
signal order_changed(order: Order, previous: Order)
## Emitted when the leader changes, including to null.
signal leader_changed(leader: Node)

enum Order {
	## Stay near the leader. The default, and what a companion does most of
	## the time.
	FOLLOW,
	## Hold position. Survives the leader walking away, which is the point.
	WAIT,
	## Go after one specific target and keep after it.
	ENGAGE,
	## Move to a point, then revert to following.
	GO_TO,
}

## Who this companion belongs to. The party relation, as one reference rather
## than a party service: a companion has exactly one leader, and a service
## would be a registry with one row per party.
@export var leader: Node

## How close to the leader is close enough. A companion inside this does
## nothing, which is what stops it jittering against the leader's own motion.
@export_range(0.5, 50.0, 0.1, "or_greater") var follow_distance: float = 3.0

## Beyond this the companion stops whatever it was ordered to do and comes
## back. Zero disables it, which suits a companion that should hold a position
## across a whole level.
@export_range(0.0, 500.0, 1.0, "or_greater") var leash_distance: float = 30.0

## A companion under orders still fights back when attacked.
@export var defends_itself: bool = true

var _order: Order = Order.FOLLOW
var _order_target: Node = null
var _order_point: Vector3 = Vector3.ZERO


# --- Reading --------------------------------------------------------------

func get_order() -> Order:
	return _order


func get_leader() -> Node:
	if leader != null and not is_instance_valid(leader):
		leader = null
	return leader


func has_leader() -> bool:
	return get_leader() != null


## What an ENGAGE order was aimed at, or null.
func get_order_target() -> Node:
	# Validity is checked before the null comparison, not after it. A freed
	# node does not reliably compare equal to null in GDScript, and the same
	# trap cost WorldStateService a bug in M14: leading with "is it null?"
	# leaves a dangling reference looking like an absent one.
	if not is_instance_valid(_order_target):
		_order_target = null
		# An engage order whose target is gone is a finished order, not a
		# companion standing still forever waiting for a corpse to move.
		if _order == Order.ENGAGE:
			_set_order(Order.FOLLOW)
	return _order_target


func get_order_point() -> Vector3:
	return _order_point


## Where the companion should be right now, and whether it needs to move.
##
## Returns a dictionary rather than two calls because the two answers have to
## agree: asking "should I move?" and "where to?" separately invites a caller
## to act on one and not the other.
func get_movement_goal() -> Dictionary:
	var idle := {"should_move": false, "point": Vector3.ZERO}
	var body := _entity_root()
	if not (body is Node3D):
		return idle
	var here := (body as Node3D).global_position

	if _is_leashed(here):
		# Past the leash nothing else matters. A companion that kept holding a
		# position two districts behind is a companion the player has lost.
		return {"should_move": true, "point": _leader_position()}

	match _order:
		Order.WAIT:
			return idle
		Order.GO_TO:
			if here.distance_to(_order_point) <= follow_distance:
				_set_order(Order.FOLLOW)
				return idle
			return {"should_move": true, "point": _order_point}
		Order.ENGAGE:
			var target := get_order_target()
			if target is Node3D:
				return {"should_move": true, "point": (target as Node3D).global_position}
			return idle
	if not has_leader():
		return idle
	var to_leader := _leader_position()
	if here.distance_to(to_leader) <= follow_distance:
		return idle
	return {"should_move": true, "point": to_leader}


# --- Commands -------------------------------------------------------------

func order_follow() -> FrameworkResult:
	if not has_leader():
		return FrameworkResult.fail(
			&"companion.no_leader", "There is nobody to follow."
		)
	_order_target = null
	_set_order(Order.FOLLOW)
	return FrameworkResult.ok(null)


func order_wait() -> FrameworkResult:
	_order_target = null
	_set_order(Order.WAIT)
	return FrameworkResult.ok(null)


func order_engage(target: Node) -> FrameworkResult:
	if target == null or not is_instance_valid(target):
		return FrameworkResult.fail(
			&"companion.no_target", "There is nothing there to attack."
		)
	if target == _entity_root():
		return FrameworkResult.fail(
			&"companion.self_target", "A companion will not attack itself."
		)
	_order_target = target
	_set_order(Order.ENGAGE)
	return FrameworkResult.ok(target)


func order_move_to(point: Vector3) -> FrameworkResult:
	_order_target = null
	_order_point = point
	_set_order(Order.GO_TO)
	return FrameworkResult.ok(point)


func set_leader(new_leader: Node) -> void:
	leader = new_leader
	leader_changed.emit(new_leader)
	if new_leader == null and _order == Order.FOLLOW:
		# Following nobody is waiting, and saying so beats a companion that
		# reports FOLLOW while standing still.
		_set_order(Order.WAIT)


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


## Saves the order but not the leader.
##
## A leader is a live node reference, and the entity graph is rebuilt on load
## by whoever owns it. Restoring into FOLLOW with the leader reattached
## afterwards is correct; writing an instance id into a save is not (rule 32).
func capture_state() -> Dictionary:
	return {
		"order": int(_order),
		"point": [_order_point.x, _order_point.y, _order_point.z],
	}


func restore_state(data: Dictionary) -> void:
	_order = int(data.get("order", int(Order.FOLLOW))) as Order
	var point: Array = data.get("point", [0.0, 0.0, 0.0])
	if point.size() == 3:
		_order_point = Vector3(float(point[0]), float(point[1]), float(point[2]))
	_order_target = null


# --- Internals ------------------------------------------------------------

func _set_order(order: Order) -> void:
	if _order == order:
		return
	var previous := _order
	_order = order
	order_changed.emit(_order, previous)


func _is_leashed(here: Vector3) -> bool:
	if leash_distance <= 0.0 or not has_leader():
		return false
	return here.distance_to(_leader_position()) > leash_distance


func _leader_position() -> Vector3:
	var target := get_leader()
	return (target as Node3D).global_position if target is Node3D else Vector3.ZERO


func _entity_root() -> Node:
	var context := get_context()
	if context != null and context.entity != null:
		return context.entity
	return get_parent()


## Finds the companion capability on an entity, for a brain asking whether
## there is one. Returns null on every NPC that is not a companion, which is
## most of them.
static func find_on(entity: Node) -> CompanionComponent:
	if entity == null:
		return null
	for child in entity.get_children():
		if child is CompanionComponent:
			return child as CompanionComponent
	return null
