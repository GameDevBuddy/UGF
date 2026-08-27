class_name VehicleControllerAdapter
extends FrameworkComponent
## Where the framework hands driving commands to a physics implementation.
##
## [b]This is the boundary Implementation Plan 22 insists on.[/b] The framework
## owns identity, seats, fuel, damage, storage, upgrades, cameras and
## possession; how a vehicle actually moves is somebody else's decision.
## A project using [VehicleBody3D], a project using a kinematic
## [CharacterBody3D] and a project running a server with no physics at all
## must all be drivable through the same six calls — and traffic AI must reach
## them without knowing which it is talking to (rule 15 of the plan's
## non-negotiables).
##
## [b]This base class is not abstract.[/b] It integrates the handling profile
## itself and reports the result, moving nothing. That makes it a complete,
## honest implementation for a headless server, a test and a replay — and it
## means [VehicleComponent] has something to talk to on a bare [Node]
## (rule 33). [VehicleBodyAdapter] is the subclass that writes the answer to a
## real body.
##
## The seam is the same shape as [HitProvider] and [PerceptionProvider]: the
## module declares the question, an implementation answers it, and the one
## that touches the engine is a single deletable file.

## Emitted when the vehicle starts or stops moving.
signal motion_changed(moving: bool)

## What the vehicle is doing, for animation, audio and a HUD. Deliberately
## coarse: anything finer is presentation deciding for itself.
enum MotionState { STOPPED, ACCELERATING, CRUISING, BRAKING, REVERSING }

## Handling used by this adapter. Set by [VehicleComponent] at initialisation;
## exported so a project can drive an adapter with no vehicle component at all.
@export var handling: HandlingProfile

## The node moved. Null is valid and means "integrate but do not move
## anything", which is the headless case.
@export var body: Node3D

var _throttle: float = 0.0
var _brake: float = 0.0
var _steering: float = 0.0
var _handbrake: bool = false
var _speed: float = 0.0
var _heading: float = 0.0
var _moving: bool = false


# --- Commands -------------------------------------------------------------
#
# The six calls of the contract. A player controller, an AI driver and a
# scripted sequence all issue exactly these, which is the whole of "player and
# AI drive through the same adapter".

## Forward demand, -1..1. Negative is reverse.
func set_throttle(value: float) -> void:
	_throttle = clampf(value, -1.0, 1.0)


## Brake pedal, 0..1.
func set_brake(value: float) -> void:
	_brake = clampf(value, 0.0, 1.0)


## Steering, -1..1. Negative is left.
func set_steering(value: float) -> void:
	_steering = clampf(value, -1.0, 1.0)


func set_handbrake(active: bool) -> void:
	_handbrake = active


## Signed speed along the vehicle's heading, metres per second. Negative is
## reversing.
func get_speed() -> float:
	return _speed


func get_motion_state() -> MotionState:
	if _speed < -0.01:
		return MotionState.REVERSING
	if _brake > 0.0 or _handbrake:
		return MotionState.BRAKING if absf(_speed) > 0.01 else MotionState.STOPPED
	if absf(_speed) <= 0.01:
		return MotionState.STOPPED
	if _throttle > 0.0:
		return MotionState.ACCELERATING
	return MotionState.CRUISING


# --- Queries --------------------------------------------------------------

func get_throttle() -> float:
	return _throttle


func get_brake() -> float:
	return _brake


func get_steering() -> float:
	return _steering


func is_handbrake_on() -> bool:
	return _handbrake


## Heading in radians, wrapped to -PI..PI.
func get_heading() -> float:
	return _heading


func get_velocity() -> Vector3:
	return VehicleSolver.solve_velocity(_speed, _heading)


func is_moving() -> bool:
	return absf(_speed) > 0.01


## Speed as a fraction of what this handling profile allows, in the direction
## of travel. What a speedometer and a camera FOV blend both want.
func get_speed_fraction() -> float:
	return VehicleSolver.get_speed_fraction(_speed, handling)


## Releases every pedal. What possession changing hands calls, so a vehicle
## whose driver got out does not keep the throttle they were holding.
func release_controls() -> void:
	_throttle = 0.0
	_brake = 0.0
	_steering = 0.0
	_handbrake = false


## Stops the vehicle dead. What a restore, a teleport and a destruction call.
func halt() -> void:
	release_controls()
	_speed = 0.0
	_set_moving(false)


func set_heading(radians: float) -> void:
	_heading = wrapf(radians, -PI, PI)


## Forces the speed. For a restore and for a project driving the vehicle from
## outside — never for gameplay, which goes through the pedals.
func set_speed(value: float) -> void:
	_speed = value
	_set_moving(is_moving())


# --- Stepping -------------------------------------------------------------

## Advances one step and writes the result wherever this adapter writes it.
##
## Called by [VehicleComponent], not by [method Node._physics_process]: one
## owner for the clock (rule 4), so a paused vehicle, a replay and a network
## client all step the same way.
func step(delta: float) -> void:
	if delta <= 0.0 or handling == null:
		return
	_speed = VehicleSolver.solve_speed(
		_speed, _throttle, _brake, _handbrake, handling, delta
	)
	_heading = VehicleSolver.solve_heading(
		_heading, _speed, _steering, handling, delta
	)
	apply_motion(delta)
	_set_moving(is_moving())


## Where a subclass writes the motion. The base does nothing, which is exactly
## right for a headless integration: the speed and heading are still correct
## and still readable.
func apply_motion(_delta: float) -> void:
	pass


# --- Internals ------------------------------------------------------------

func _set_moving(moving: bool) -> void:
	if moving == _moving:
		return
	_moving = moving
	motion_changed.emit(moving)
