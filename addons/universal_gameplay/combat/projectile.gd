class_name Projectile
extends Node3D
## Something in flight that has not hit anything yet.
##
## Steps forward and casts a ray over the distance it just covered, rather than
## moving and asking what it is inside. A grenade at 40 m/s moves two thirds of
## a metre a frame, and a thin wall is exactly the thing an overlap test skips
## straight through.
##
## Carries the [AttackContext] it was fired from, so a rocket that kills
## someone six seconds after the trigger was pulled still attributes the kill
## to whoever pulled it.

## Emitted when it connects. The context is the original attack's.
signal hit_something(hit: CombatHit, context: AttackContext)
## Emitted when it runs out of range or life without hitting anything.
signal expired

@export var speed: float = 40.0
## Metres before it gives up. Zero uses [member lifetime] alone.
@export var max_distance: float = 200.0
## Seconds before it gives up.
@export var lifetime: float = 5.0
## Metres per second of downward acceleration. Zero flies flat.
@export var gravity: float = 0.0
## Free itself on impact. Off for something that pierces or bounces, which a
## project implements by listening to [signal hit_something].
@export var free_on_hit: bool = true

var _context: AttackContext = null
var _provider: HitProvider = null
var _velocity: Vector3 = Vector3.ZERO
var _travelled: float = 0.0
var _age: float = 0.0
var _spent: bool = false


## Arms the projectile. Called by [ProjectileDelivery] before it enters the
## tree; everything it needs arrives here rather than being looked up (rule 20).
func launch(
	context: AttackContext, provider: HitProvider, direction: Vector3
) -> void:
	_context = context
	_provider = provider
	_velocity = direction.normalized() * speed


func get_attack_context() -> AttackContext:
	return _context


func is_spent() -> bool:
	return _spent


func _physics_process(delta: float) -> void:
	tick(delta)


## Advances one step. Public and deterministic, so a test can fly a projectile
## into a wall without a physics frame.
func tick(delta: float) -> void:
	if _spent or delta <= 0.0:
		return

	_age += delta
	if gravity != 0.0:
		_velocity += Vector3.DOWN * gravity * delta

	var step := _velocity * delta
	var length := step.length()
	if length > 0.0 and _provider != null:
		var exclude: Array[Node] = []
		if _context != null:
			exclude = _context.exclude
		var hit := _provider.cast_ray(global_position, step / length, length, exclude)
		if hit != null:
			global_position = hit.position
			_connect(hit)
			return

	global_position += step
	_travelled += length
	if (max_distance > 0.0 and _travelled >= max_distance) or _age >= lifetime:
		_expire()


func _connect(hit: CombatHit) -> void:
	_spent = true
	hit_something.emit(hit, _context)
	if free_on_hit:
		queue_free()


func _expire() -> void:
	_spent = true
	expired.emit()
	queue_free()
