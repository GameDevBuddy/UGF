class_name WeaponComponent
extends FrameworkComponent
## Everything about a weapon that changes: ammunition, reloading, and how far
## its aim has drifted.
##
## Split from [CombatComponent] deliberately. Combat owns the swing -- timing,
## geometry, damage -- and this owns the weapon's own state. A turret has one
## and no combat state machine worth the name; an unarmed brawler has a combat
## component and no weapon at all (rule 4, rule 31).
##
## [b]It never resolves a hit.[/b] Ask it whether the weapon can fire and tell
## it that it did; what the shot connected with is not its business.

## Emitted after a shot has been paid for. Presentation hangs muzzle flash and
## shell ejection here (rule 21).
signal fired(attack: AttackDefinition)
## Emitted whenever the magazine or the reserve changes.
signal ammo_changed(magazine: int, reserve: int)
## Emitted when the magazine runs dry on a shot, so a project can auto-reload.
signal magazine_emptied
signal reload_started(duration: float)
signal reload_finished(loaded: int)
signal reload_cancelled
## Emitted when the equipped weapon changes, including to nothing.
signal weapon_changed(profile: WeaponProfile)

## Emitted as a charge builds, from 0.0 to 1.0, for a UI meter.
signal charge_changed(charge: float)
## Emitted when a charge reaches full, whether or not it fires there.
signal charge_full
## Emitted when a charge is let go below the minimum and bought nothing.
signal charge_wasted(charge: float)

## Weapon used regardless of what is equipped. What a turret, a mounted gun or
## a fixed-loadout enemy sets.
@export var profile_override: WeaponProfile

## Where an equipped weapon is read from. Absent, only the override is used --
## which is a whole valid configuration, not a broken one (rule 31).
@export var equipment: EquipmentComponent

## Slot the weapon is read from.
@export var weapon_slot: StringName = &"slot.main_hand"

## Bag a reload draws from, for a weapon whose ammo is an item.
@export var inventory: InventoryComponent

## States mirrored while reloading.
@export var semantic_state: SemanticState

## Tick from [method Node._physics_process]. Off when something else owns time.
@export var auto_tick: bool = true

var _profile: WeaponProfile = null
var _weapon_id: StringName = &""
var _magazine: int = 0
var _reserve: int = 0
var _spread: float = 0.0
var _recoil: Vector2 = Vector2.ZERO
var _cooldown: float = 0.0
var _reload_remaining: float = 0.0
var _reloading: bool = false
var _charge: float = 0.0
var _charging: bool = false
## The charge the last shot was released at, so the attack that follows can be
## scaled by it. Cleared on the next press.
var _released_charge: float = 0.0


func _ready() -> void:
	# Recomputed rather than blindly disabled: a binder above this node may
	# have initialised it already (see MovementComponent for the full note).
	set_physics_process(is_initialized() and auto_tick)


func initialize(context: EntityContext) -> void:
	super(context)
	if equipment == null:
		equipment = _find(EquipmentComponent) as EquipmentComponent
	if inventory == null:
		inventory = _find(InventoryComponent) as InventoryComponent
	if semantic_state == null:
		semantic_state = _find(SemanticState) as SemanticState
	if equipment != null and not equipment.equipment_changed.is_connected(_on_equipment_changed):
		equipment.equipment_changed.connect(_on_equipment_changed)
	_adopt(_resolve_profile(), _resolve_weapon_id())
	set_physics_process(auto_tick)


func _exit_tree() -> void:
	if equipment != null and equipment.equipment_changed.is_connected(_on_equipment_changed):
		equipment.equipment_changed.disconnect(_on_equipment_changed)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- The weapon -----------------------------------------------------------

func get_profile() -> WeaponProfile:
	return _profile


## Definition id of the weapon, for kill attribution. Blank for an override
## profile that was never given one.
func get_weapon_id() -> StringName:
	return _weapon_id


func has_weapon() -> bool:
	return _profile != null


func get_attack(secondary: bool = false) -> AttackDefinition:
	return _profile.get_attack(secondary) if _profile != null else null


## Puts a weapon in this component's hands directly. What a turret does, and
## what a project with its own equipment model does instead of wiring one.
func set_profile(profile: WeaponProfile, weapon_id: StringName = &"") -> void:
	_adopt(profile, weapon_id)


# --- Ammunition -----------------------------------------------------------

func get_magazine() -> int:
	return _magazine


## Rounds available outside the magazine. Negative means unlimited.
func get_reserve() -> int:
	if _profile == null or _profile.ammo == null:
		return 0
	if _profile.ammo.has_unlimited_reserve():
		return -1
	if _profile.ammo.draws_from_inventory():
		return inventory.count(_profile.ammo.ammo_item_id) if inventory != null else 0
	return _reserve


func has_unlimited_ammo() -> bool:
	return _profile == null or _profile.ammo == null or _profile.ammo.is_infinite()


func is_magazine_empty() -> bool:
	if has_unlimited_ammo():
		return false
	return _magazine < _profile.ammo.cost_per_shot


func is_reloading() -> bool:
	return _reloading


func get_reload_remaining() -> float:
	return _reload_remaining


# --- Aim state ------------------------------------------------------------

## Current cone in degrees, handed to a delivery as its spread.
## The cone this weapon is currently shooting into, in degrees.
##
## [b]Aiming is read, not owned.[/b] Implementation Plan 13 says aim is a
## character or camera state rather than something hardcoded in each weapon, so
## the weapon asks the entity's [SemanticState] whether it is being aimed and
## applies its own profile's multiplier. Nothing here sets that state, and a
## weapon on an entity with no semantic state simply never tightens.
func get_spread() -> float:
	if is_aiming() and _profile != null and _profile.recoil != null:
		return _spread * _profile.recoil.aim_spread_multiplier
	return _spread


## Whether the entity carrying this weapon is aiming down sights.
func is_aiming() -> bool:
	return semantic_state != null and semantic_state.has_state(GameplayNames.STATE_AIMING)


## Accumulated view kick in degrees as (pitch, yaw). A camera adds this; combat
## never rotates anything itself (rule 21).
##
## Scaled by the aim multiplier for the same reason spread is.
func get_recoil() -> Vector2:
	if is_aiming() and _profile != null and _profile.recoil != null:
		return _recoil * _profile.recoil.aim_recoil_multiplier
	return _recoil


func get_cooldown_remaining() -> float:
	return _cooldown


# --- Firing ---------------------------------------------------------------

## Whether the weapon itself would allow a shot right now.
##
## Says nothing about whether the attacker can afford it or is mid-swing; that
## is [CombatComponent]'s question.
func can_fire(secondary: bool = false) -> FrameworkResult:
	if _profile == null:
		return FrameworkResult.fail(&"weapon.none", "Nothing is equipped.")
	if get_attack(secondary) == null:
		return FrameworkResult.fail(
			&"weapon.no_attack", "This weapon has no attack in that slot."
		)
	if _reloading:
		return FrameworkResult.fail(&"weapon.reloading", "Still reloading.")
	if _cooldown > 0.0:
		return FrameworkResult.fail(&"weapon.cooling_down", "Not ready to fire again.")
	if is_magazine_empty():
		return FrameworkResult.fail(&"weapon.empty", "The magazine is empty.")
	return FrameworkResult.ok(null)


## Pays for a shot: spends the round, starts the cadence timer and widens the
## cone. Call it once per attack, after [method can_fire] passed.
func consume_shot(secondary: bool = false) -> FrameworkResult:
	var allowed := can_fire(secondary)
	if allowed.is_err():
		return allowed

	if not has_unlimited_ammo():
		_magazine -= _profile.ammo.cost_per_shot
		ammo_changed.emit(_magazine, get_reserve())

	_cooldown = _profile.get_interval(secondary)
	if _profile.recoil != null:
		_spread = CombatSolver.accumulate_spread(_spread, _profile.recoil)
		_recoil = CombatSolver.accumulate_recoil(_recoil, _profile.recoil)

	fired.emit(get_attack(secondary))
	if is_magazine_empty():
		magazine_emptied.emit()
	return FrameworkResult.ok(null)


# --- Charging -------------------------------------------------------------

## How far the current charge has built, 0.0 to 1.0.
func get_charge() -> float:
	return _charge


func is_charging() -> bool:
	return _charging


## True when the charge has built far enough that releasing it fires.
func is_charge_usable() -> bool:
	if _profile == null or not _profile.is_charged():
		return false
	return _charge >= _profile.minimum_charge


## Starts building a charge. What a trigger press does on a charge weapon.
##
## Refused for the same reasons firing is refused -- empty, reloading, cooling
## down -- because a charge that builds on an empty magazine is a player
## holding a trigger for a shot that was never going to happen.
func begin_charge(secondary: bool = false) -> FrameworkResult:
	if _profile == null or not _profile.is_charged():
		return FrameworkResult.fail(
			&"weapon.not_charged", "This weapon does not charge."
		)
	var allowed := can_fire(secondary)
	if allowed.is_err():
		return allowed
	_charging = true
	_released_charge = 0.0
	return FrameworkResult.ok(null)


## Lets the charge go, and reports what it bought.
##
## The payload is the damage scale for the shot: 1.0 at the minimum, up to
## [member WeaponProfile.charge_multiplier] at full. A release below the
## minimum fails with [code]weapon.charge_too_low[/code] and costs nothing --
## no round, no cooldown -- because a tap that fired a limp shot would read as
## a wasted round rather than as a missed input.
func release_charge() -> FrameworkResult:
	if _profile == null or not _profile.is_charged():
		return FrameworkResult.fail(
			&"weapon.not_charged", "This weapon does not charge."
		)

	var held := _released_charge if _released_charge > 0.0 else _charge
	_charging = false
	_released_charge = 0.0

	var scale := _profile.get_charge_scale(held)
	if scale <= 0.0:
		charge_wasted.emit(held)
		# The charge is kept rather than dumped, so a player who taps twice in
		# quick succession accumulates towards a shot instead of starting over.
		return FrameworkResult.fail(
			&"weapon.charge_too_low",
			"Released at %.0f%%, below the %.0f%% this weapon needs."
			% [held * 100.0, _profile.minimum_charge * 100.0]
		)

	_set_charge(0.0)
	return FrameworkResult.ok(scale)


## Abandons a charge without firing. What holstering or being staggered does.
func cancel_charge() -> void:
	_charging = false
	_released_charge = 0.0
	_set_charge(0.0)


# --- Reloading ------------------------------------------------------------

## Starts a reload. Returns a failure when there is nothing to gain by it, so
## a caller can tell a refused reload from one already under way.
func reload() -> FrameworkResult:
	if _profile == null or _profile.ammo == null:
		return FrameworkResult.fail(&"weapon.none", "Nothing to reload.")
	if has_unlimited_ammo():
		return FrameworkResult.fail(
			&"weapon.no_magazine", "This weapon has no magazine."
		)
	if _reloading:
		return FrameworkResult.fail(&"weapon.already_reloading", "Already reloading.")
	if _magazine >= _profile.ammo.magazine_size:
		return FrameworkResult.fail(&"weapon.magazine_full", "The magazine is full.")
	if _available_reserve() <= 0:
		return FrameworkResult.fail(&"weapon.no_reserve", "No ammunition left.")

	_reloading = true
	_reload_remaining = _profile.ammo.reload_time
	_set_state(true)
	reload_started.emit(_reload_remaining)
	return FrameworkResult.ok(_reload_remaining)


## Abandons a reload in progress. An incremental reload keeps what it loaded,
## which is the whole reason incremental exists.
func cancel_reload() -> void:
	if not _reloading:
		return
	_reloading = false
	_reload_remaining = 0.0
	_set_state(false)
	reload_cancelled.emit()


# --- Time -----------------------------------------------------------------

## Advances cadence, aim recovery and any reload. Called for you when
## [member auto_tick] is on.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_tick_charge(delta)
	if _profile != null and _profile.recoil != null:
		_spread = CombatSolver.recover_spread(_spread, _profile.recoil, delta)
		_recoil = CombatSolver.recover_recoil(_recoil, _profile.recoil, delta)
	if _reloading:
		_tick_reload(delta)


## Advances or decays a charge.
##
## A charge builds only while the trigger is genuinely held. Letting it build
## on its own would make a weapon fire itself the moment the player stopped
## paying attention.
func _tick_charge(delta: float) -> void:
	if _profile == null or not _profile.is_charged():
		return

	if _charging:
		if _profile.charge_time <= 0.0:
			_set_charge(1.0)
		else:
			_set_charge(_charge + delta / _profile.charge_time)
		if _charge >= 1.0 and _profile.releases_at_full:
			# The weapon that would overheat. Release rather than fire: the
			# component decides charge, the caller decides shots, and a
			# component that fired by itself would be a second owner of that.
			_charging = false
			_released_charge = 1.0
		return

	if _charge > 0.0 and _profile.charge_decay_per_second > 0.0:
		_set_charge(_charge - _profile.charge_decay_per_second * delta)


func _set_charge(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _charge):
		return
	var was_full := _charge >= 1.0
	_charge = clamped
	charge_changed.emit(_charge)
	if _charge >= 1.0 and not was_full:
		charge_full.emit()


func _tick_reload(delta: float) -> void:
	_reload_remaining -= delta
	if _reload_remaining > 0.0:
		return

	var ammo := _profile.ammo
	var wanted := ammo.rounds_per_step if ammo.incremental else ammo.magazine_size - _magazine
	var loaded := _take_from_reserve(mini(wanted, ammo.magazine_size - _magazine))
	_magazine += loaded
	ammo_changed.emit(_magazine, get_reserve())

	var keep_going := (
		ammo.incremental
		and loaded > 0
		and _magazine < ammo.magazine_size
		and _available_reserve() > 0
	)
	if keep_going:
		# The shotgun: each shell is its own step, and stopping between two of
		# them keeps the ones already in.
		_reload_remaining += ammo.reload_time
		return

	_reloading = false
	_reload_remaining = 0.0
	_set_state(false)
	reload_finished.emit(loaded)


# --- Persistence ----------------------------------------------------------
#
# What is loaded and what is carried survive a save; a half-finished reload
# and the current cone do not.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"magazine": _magazine, "reserve": _reserve}


func restore_state(data: Dictionary) -> void:
	_magazine = int(data.get("magazine", _magazine))
	_reserve = int(data.get("reserve", _reserve))
	cancel_reload()
	ammo_changed.emit(_magazine, get_reserve())


# --- Internals ------------------------------------------------------------

func _adopt(profile: WeaponProfile, weapon_id: StringName) -> void:
	if profile == _profile and weapon_id == _weapon_id:
		return
	cancel_reload()
	_profile = profile
	_weapon_id = weapon_id
	_cooldown = 0.0
	_spread = _profile.recoil.spread_min if _profile != null and _profile.recoil != null else 0.0
	_recoil = Vector2.ZERO
	if _profile != null and _profile.ammo != null and not _profile.ammo.is_infinite():
		_magazine = _profile.ammo.magazine_size
		_reserve = maxi(0, _profile.ammo.reserve_capacity)
	else:
		_magazine = 0
		_reserve = 0
	weapon_changed.emit(_profile)
	ammo_changed.emit(_magazine, get_reserve())


func _available_reserve() -> int:
	var reserve := get_reserve()
	return 0x7FFFFFFF if reserve < 0 else reserve


## Removes up to [param wanted] rounds from wherever the reserve lives.
func _take_from_reserve(wanted: int) -> int:
	if wanted <= 0:
		return 0
	var ammo := _profile.ammo
	if ammo.has_unlimited_reserve():
		return wanted
	if ammo.draws_from_inventory():
		if inventory == null:
			return 0
		var available := mini(wanted, inventory.count(ammo.ammo_item_id))
		if available <= 0:
			return 0
		var taken := inventory.remove(ammo.ammo_item_id, available)
		return available if taken.is_ok() else 0
	var from_reserve := mini(wanted, _reserve)
	_reserve -= from_reserve
	return from_reserve


func _set_state(reloading: bool) -> void:
	if semantic_state != null:
		semantic_state.set_state(GameplayNames.STATE_RELOADING, reloading)


func _on_equipment_changed() -> void:
	if profile_override != null:
		return
	_adopt(_resolve_profile(), _resolve_weapon_id())


## Read by property name rather than by casting, so a vehicle or a turret with
## its own definition type can carry a weapon (rule 9).
func _resolve_profile() -> WeaponProfile:
	if profile_override != null:
		return profile_override
	var equipped := _get_equipped()
	if equipped != null and equipped.definition != null:
		return equipped.definition.weapon
	var definition := get_definition()
	if definition != null and "weapon" in definition:
		var candidate: Variant = definition.get("weapon")
		if candidate is WeaponProfile:
			return candidate as WeaponProfile
	return null


func _resolve_weapon_id() -> StringName:
	var equipped := _get_equipped()
	if equipped != null and equipped.definition != null:
		return equipped.definition.id
	return &""


func _get_equipped() -> ItemInstance:
	if equipment == null or weapon_slot == &"":
		return null
	return equipment.get_equipped(weapon_slot)


func _find(type: Variant) -> FrameworkComponent:
	var entity := get_entity()
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
