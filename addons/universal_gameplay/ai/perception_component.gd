class_name PerceptionComponent
extends FrameworkComponent
## The capability of noticing things. Sight, hearing, and a memory that fades.
##
## Owns one [AIMemory] and keeps it current. It decides nothing: what to do
## about the intruder belongs to a brain, and separating the two is what lets a
## guard, a civilian and a security camera share one pair of eyes (rule 4).
##
## [b]It sweeps on an interval, not every frame.[/b] Rule 26 forbids permanent
## per-frame work, and perception is the classic place it creeps in. The
## interval is content, the sweep is skipped entirely while nothing is
## registered, and a project driving perception itself turns
## [member auto_tick] off.

## Emitted when something is noticed for the first time.
signal noticed(entry: MemoryEntry)
## Emitted when something that was in view stops being so.
signal lost(entry: MemoryEntry)
## Emitted when a memory decays away entirely.
signal forgotten(target: Node)

## What this entity can notice. Takes precedence over the definition's.
@export var profile_override: PerceptionProfile

## Its own perceivability, so it does not notice itself and so a brain can read
## its own tags. Found among this entity's components when not wired.
@export var perceivable: Perceivable

## Node the senses originate from: a head bone, a camera mount. Absent, the
## entity's own transform at the profile's eye height is used.
@export var eyes: Node3D

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

var _profile: PerceptionProfile = null
var _provider: PerceptionProvider = null
var _memory: AIMemory = null
var _since_scan: float = 0.0


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick and _can_sense())


func initialize(context: EntityContext) -> void:
	super(context)
	_profile = _resolve_profile()
	if perceivable == null:
		perceivable = Perceivable.find_on(get_entity())
	_ensure_memory()
	set_physics_process(auto_tick and _can_sense())


func _physics_process(delta: float) -> void:
	tick(delta)


func get_profile() -> PerceptionProfile:
	return _profile


## Hands this component its eyes directly. What [AIControllerComponent] calls
## when a role is set at runtime, so a spawner that makes one civilian a guard
## does not have to remember to swap two things.
##
## Refuses when an override is authored: an explicit
## [member profile_override] on the component is a decision, and a role
## arriving later must not quietly undo it.
func set_profile(profile: PerceptionProfile) -> void:
	if profile_override != null:
		return
	_profile = profile
	set_physics_process(auto_tick and _can_sense() and is_initialized())


## What this entity knows. Never null, so a brain can read it before the first
## sweep has run.
func get_memory() -> AIMemory:
	_ensure_memory()
	return _memory


# --- The seam -------------------------------------------------------------

## Where sweeps and sight lines go. Built against this entity's world on first
## use; a test injects its own before the first tick.
func get_provider() -> PerceptionProvider:
	if _provider == null:
		_provider = PhysicsPerceptionProvider.for_node(_get_body())
	return _provider


func set_provider(provider: PerceptionProvider) -> void:
	_provider = provider


# --- Sensing --------------------------------------------------------------

## Where this entity looks from.
func get_eye_position() -> Vector3:
	if eyes != null and eyes.is_inside_tree():
		return eyes.global_position
	var body := _get_body()
	if body == null or not body.is_inside_tree():
		return Vector3.ZERO
	var height := _profile.eye_height if _profile != null else 0.0
	return body.global_position + Vector3.UP * height


## Which way it is facing.
func get_facing() -> Vector3:
	var source := eyes if eyes != null else _get_body()
	if source == null or not source.is_inside_tree():
		return Vector3.FORWARD
	return -source.global_transform.basis.z


## Whether [param target] can be perceived right now, ignoring memory.
##
## Public because it is the question a brain asks before committing to a shot,
## and because it is the whole of perception in one testable call.
func can_perceive(target: Node) -> bool:
	if _profile == null or target == null or target == get_entity():
		return false
	var mark := Perceivable.find_on(target)
	if mark == null:
		return false
	var visibility := mark.get_visibility()
	if visibility <= 0.0:
		return false

	var origin := get_eye_position()
	var point := mark.get_focus_position()
	var reach := PerceptionSolver.effective_range(_profile.sight_range, visibility)
	if not PerceptionSolver.is_within_cone(
		origin, get_facing(), point, _profile.sight_angle, reach
	):
		return false
	if not _profile.requires_line_of_sight:
		return true

	var ignore: Array[Node] = []
	if get_entity() != null:
		ignore.append(get_entity())
	ignore.append(target)
	return get_provider().has_line_of_sight(origin, point, ignore)


## Records a noise. Called by whatever makes them -- a gunshot, a broken
## window, a footstep -- rather than being sniffed for, because a sound is an
## event and polling for events is how you miss them.
func hear(source: Node, position: Vector3, loudness: float = 1.0) -> bool:
	if _profile == null or source == null or source == get_entity():
		return false
	if loudness <= 0.0:
		return false
	if not PerceptionSolver.noise_reaches(
		get_eye_position(), position, _profile.hearing_range, loudness
	):
		return false
	var mark := Perceivable.find_on(source)
	get_memory().hear(source, position, mark.threat if mark != null else 1.0)
	return true


# --- Time -----------------------------------------------------------------

## Advances the scan timer and ages memory. Called for you when
## [member auto_tick] is on.
func tick(delta: float) -> void:
	if delta <= 0.0 or _profile == null:
		return
	_since_scan += delta
	if _since_scan < _profile.scan_interval:
		return
	sweep(_since_scan)
	_since_scan = 0.0


## Runs one full sweep immediately. Public so a project can drive perception on
## its own schedule, and so a test can step it exactly once.
func sweep(delta: float) -> void:
	if _profile == null:
		return
	var memory := get_memory()
	var perceived: Array[Node] = []

	if _profile.can_see_at_all():
		var radius := _profile.sight_range
		for candidate in get_provider().find_candidates(get_eye_position(), radius):
			if candidate == get_entity() or not can_perceive(candidate):
				continue
			var mark := Perceivable.find_on(candidate)
			memory.see(
				candidate,
				mark.get_focus_position(),
				mark.threat,
				delta,
				_profile.notice_time
			)
			perceived.append(candidate)

	memory.age(delta, perceived, _profile.memory_duration)


# --- Internals ------------------------------------------------------------

func _ensure_memory() -> void:
	if _memory != null:
		return
	_memory = AIMemory.new()
	_memory.target_noticed.connect(func(entry: MemoryEntry) -> void: noticed.emit(entry))
	_memory.target_lost.connect(func(entry: MemoryEntry) -> void: lost.emit(entry))
	_memory.target_forgotten.connect(func(target: Node) -> void: forgotten.emit(target))


func _can_sense() -> bool:
	return _profile != null and (_profile.can_see_at_all() or _profile.hearing_range > 0.0)


func _get_body() -> Node3D:
	var entity := get_entity()
	return entity as Node3D if entity is Node3D else null


## Read by property name rather than by casting, so a turret or a camera with
## its own definition type can perceive (rule 9).
func _resolve_profile() -> PerceptionProfile:
	if profile_override != null:
		return profile_override
	var definition := get_definition()
	if definition == null:
		return null
	if "perception" in definition:
		var direct: Variant = definition.get("perception")
		if direct is PerceptionProfile:
			return direct as PerceptionProfile
	if "role" in definition:
		var role: Variant = definition.get("role")
		if role is NPCRoleDefinition:
			return (role as NPCRoleDefinition).perception
	return null
