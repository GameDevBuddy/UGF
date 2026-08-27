class_name HeatService
extends FrameworkService
## Turns reported crimes into wanted tiers, and lets them cool off.
##
## [b]It is told, never asks.[/b] Nothing here watches for crime; a witness, a
## trigger or a script builds a [CrimeContext] and calls [method report]. That
## direction is the entire reason the M15 exit gate holds: Combat does not
## depend on Crime, AI does not depend on Crime, and Crime does not reach into
## either — it subscribes to facts already on the bus and publishes its own
## (rule 5, rule 9).
##
## [b]It owns heat and tiers, and nothing else.[/b] Reputation consequences are
## [CrimeFactionAdapter]'s, which means this file has no dependency on Factions
## at all — and that a project can have a wanted level with no social system
## behind it (rule 4, rule 31).
##
## [b]The only thing law AI sees is a semantic state.[/b] A guard's brain asks
## whether somebody is [code]state.wanted[/code]; it never asks what their heat
## is, which faction is annoyed, or what they did. That is what lets the
## numbers be retuned without touching a behaviour (rule 32).

## Emitted when a crime is accepted. Rejected reports are silent here and
## reported through the return value, because "somebody got away with it" is
## not an event the world should hear.
signal crime_reported(context: CrimeContext)

## Emitted when a report was refused, with why. What a stealth HUD shows and
## what a debug panel logs.
signal crime_rejected(context: CrimeContext, reason: StringName)

## Emitted when an actor's heat with a faction changes.
signal heat_changed(actor_id: StringName, faction: StringName, heat: float)

## Emitted when an actor crosses onto a different rung. The one signal law AI
## and a wanted UI both listen to.
signal wanted_changed(actor_id: StringName, faction: StringName, tier: WantedTier)

## Emitted when an actor stops being wanted by a faction entirely.
signal cleared(actor_id: StringName, faction: StringName)

## Ladder used per law faction. Blank keys the default profile.
var _profiles: Dictionary[StringName, HeatProfile] = {}

## Actor id to faction to heat.
var _heat: Dictionary[StringName, Dictionary] = {}

## Actor id to faction to seconds since their last offence, for cooldown
## delays.
var _since_crime: Dictionary[StringName, Dictionary] = {}

## Actor id to faction to the tier they were last announced at, so a crossing
## is announced once rather than every tick.
var _tiers: Dictionary[StringName, Dictionary] = {}

## Actor id to the crime ids already counted, so a superseding offence does
## not also charge the one it outranks.
var _history: Dictionary[StringName, Array] = {}

## Crime definitions seen so far, so superseding can be resolved without a
## registry lookup. Populated as crimes are reported, which is the only way one
## can end up on a record.
var _known: Dictionary[StringName, CrimeDefinition] = {}

## Whether reports are accepted at all. What a cutscene and a debug toggle move.
var enabled: bool = true


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_CRIME


func configure(default_profile: HeatProfile) -> void:
	set_profile(&"", default_profile)


func service_stopped() -> void:
	clear()


# --- Profiles -------------------------------------------------------------

func set_profile(faction: StringName, profile: HeatProfile) -> void:
	if profile == null:
		_profiles.erase(faction)
		return
	_profiles[faction] = profile


func get_profile(faction: StringName = &"") -> HeatProfile:
	if _profiles.has(faction):
		return _profiles[faction]
	return _profiles.get(&"")


func has_profile(faction: StringName = &"") -> bool:
	return get_profile(faction) != null


# --- Reporting ------------------------------------------------------------

## Whether a crime would be accepted, without accepting it.
func can_report(context: CrimeContext) -> FrameworkResult:
	if not enabled:
		return FrameworkResult.fail(&"crime.disabled", "Crime reporting is switched off.")
	if context == null or context.definition == null:
		return FrameworkResult.fail(&"crime.no_definition", "There is no crime.")
	if context.perpetrator == null:
		return FrameworkResult.fail(&"crime.no_perpetrator", "There is nobody to blame.")
	if not context.is_reportable():
		return FrameworkResult.fail(&"crime.unwitnessed", "Nobody saw it.")

	var actor := _resolve_actor(context)
	if actor == &"":
		return FrameworkResult.fail(
			&"crime.no_identity",
			"The perpetrator has no persistent id, so nothing can be pinned on them."
		)
	var law := _resolve_law(context)
	if law == &"":
		return FrameworkResult.fail(
			&"crime.no_jurisdiction", "No faction's law covers this."
		)
	if get_profile(law) == null:
		return FrameworkResult.fail(
			&"crime.no_profile", "No heat ladder is configured for '%s'." % law
		)
	if _is_superseded(actor, context.definition):
		return FrameworkResult.fail(
			&"crime.superseded", "A worse offence already covers this one."
		)
	return FrameworkResult.ok(context)


## Accepts a crime: adds heat, spends reputation, and moves the tier if the
## total crossed a rung.
##
## Validate-then-mutate, like every other transaction here: a rejected report
## leaves no heat and costs no standing (rule 17).
func report(context: CrimeContext) -> FrameworkResult:
	var allowed := can_report(context)
	if allowed.is_err():
		crime_rejected.emit(context, allowed.code)
		return allowed

	var actor := _resolve_actor(context)
	var law := _resolve_law(context)
	context.actor_id = actor
	context.law_faction = law

	learn(context.definition)
	_remember(actor, context.definition)
	_set_since(actor, law, 0.0)
	add_heat(actor, law, context.get_heat())
	crime_reported.emit(context)
	return FrameworkResult.ok(context)


# --- Heat -----------------------------------------------------------------

func get_heat(actor_id: StringName, faction: StringName) -> float:
	return (_heat.get(actor_id, {}) as Dictionary).get(faction, 0.0)


func get_total_heat(actor_id: StringName) -> float:
	var total := 0.0
	for faction in (_heat.get(actor_id, {}) as Dictionary):
		total += (_heat[actor_id] as Dictionary)[faction]
	return total


func add_heat(actor_id: StringName, faction: StringName, amount: float) -> float:
	if actor_id == &"" or is_equal_approx(amount, 0.0):
		return get_heat(actor_id, faction)
	return _set_heat(actor_id, faction, get_heat(actor_id, faction) + amount)


func set_heat(actor_id: StringName, faction: StringName, value: float) -> float:
	return _set_heat(actor_id, faction, value)


## Wipes an actor's heat with one faction. What an arrest, a bribe, a pardon
## and a jail term all call.
func clear_heat(actor_id: StringName, faction: StringName) -> bool:
	if get_heat(actor_id, faction) <= 0.0:
		return false
	_set_heat(actor_id, faction, 0.0)
	return true


## Wipes an actor's heat everywhere. Their reputation is untouched: being
## pardoned is not being forgotten.
func clear_actor(actor_id: StringName) -> void:
	for faction in (_heat.get(actor_id, {}) as Dictionary).keys():
		_set_heat(actor_id, faction, 0.0)
	_history.erase(actor_id)


# --- Wanted state ---------------------------------------------------------

func get_tier(actor_id: StringName, faction: StringName) -> WantedTier:
	var profile := get_profile(faction)
	if profile == null:
		return null
	return profile.resolve_tier(get_heat(actor_id, faction))


## Whether [param actor_id] is wanted by [param faction] at all.
func is_wanted(actor_id: StringName, faction: StringName) -> bool:
	var tier := get_tier(actor_id, faction)
	return tier != null and tier.state != &""


## Whether [param actor_id] is wanted by anybody. What a HUD asks.
func is_wanted_anywhere(actor_id: StringName) -> bool:
	for faction in (_heat.get(actor_id, {}) as Dictionary):
		if is_wanted(actor_id, faction):
			return true
	return false


## Every semantic state this actor currently carries from the law. Plural
## because two factions can both want you, and a guard of one should not care
## about the other's warrant.
func get_wanted_states(actor_id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for faction in (_heat.get(actor_id, {}) as Dictionary):
		var tier := get_tier(actor_id, faction)
		if tier != null and tier.state != &"" and not found.has(tier.state):
			found.append(tier.state)
	return found


func get_wanted_factions(actor_id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for faction in (_heat.get(actor_id, {}) as Dictionary):
		if is_wanted(actor_id, faction):
			found.append(faction)
	return found


## How much heat until the next rung, or zero at the top.
func get_heat_to_next_tier(actor_id: StringName, faction: StringName) -> float:
	var profile := get_profile(faction)
	if profile == null:
		return 0.0
	var heat := get_heat(actor_id, faction)
	var next := profile.get_next_threshold(heat)
	return maxf(0.0, next - heat) if next > 0.0 else 0.0


func get_tracked_actors() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_heat.keys())
	return found


# --- Time -----------------------------------------------------------------

## Cools everybody down.
##
## Ticked from a low-frequency timer, never from a frame: heat is exactly the
## sort of low-rate simulation the plan's performance rules say to tick rather
## than process. The work is proportional to the number of actors carrying
## heat, which in practice is one.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for actor_id in _heat.keys():
		for faction in (_heat[actor_id] as Dictionary).keys():
			_cool(actor_id, faction, delta)


func clear() -> void:
	_heat.clear()
	_since_crime.clear()
	_tiers.clear()
	_history.clear()


# --- Persistence ----------------------------------------------------------
#
# All of it. A save that forgot the player was wanted would be the cheapest
# possible escape from the police.

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var heat: Dictionary = {}
	for actor_id in _heat:
		var per_faction: Dictionary = {}
		for faction in (_heat[actor_id] as Dictionary):
			per_faction[String(faction)] = (_heat[actor_id] as Dictionary)[faction]
		heat[String(actor_id)] = per_faction

	var history: Dictionary = {}
	for actor_id in _history:
		var ids := PackedStringArray()
		for crime_id in (_history[actor_id] as Array):
			ids.append(String(crime_id))
		history[String(actor_id)] = ids
	return {"heat": heat, "history": history}


func restore_state(data: Dictionary) -> void:
	clear()
	for actor_key in data.get("heat", {}):
		var actor_id := StringName(actor_key)
		for faction_key in data["heat"][actor_key]:
			_set_heat(
				actor_id, StringName(faction_key), float(data["heat"][actor_key][faction_key])
			)
	for actor_key in data.get("history", {}):
		var ids: Array[StringName] = []
		for crime_id in data["history"][actor_key]:
			ids.append(StringName(crime_id))
		_history[StringName(actor_key)] = ids


# --- Internals ------------------------------------------------------------

func _set_heat(actor_id: StringName, faction: StringName, value: float) -> float:
	if actor_id == &"":
		return 0.0
	var profile := get_profile(faction)
	var clamped := profile.clamp_heat(value) if profile != null else maxf(0.0, value)
	var previous := get_heat(actor_id, faction)
	if is_equal_approx(previous, clamped):
		return clamped

	if not _heat.has(actor_id):
		_heat[actor_id] = {}
	(_heat[actor_id] as Dictionary)[faction] = clamped
	heat_changed.emit(actor_id, faction, clamped)
	_announce_tier(actor_id, faction)

	if clamped <= 0.0:
		(_heat[actor_id] as Dictionary).erase(faction)
		if (_heat[actor_id] as Dictionary).is_empty():
			_heat.erase(actor_id)
		cleared.emit(actor_id, faction)
	return clamped


## Announces a rung crossing exactly once.
##
## Compared by object identity rather than by threshold, so two tiers sharing a
## threshold — which validation warns about — still cannot produce a stream of
## crossings.
func _announce_tier(actor_id: StringName, faction: StringName) -> void:
	var tier := get_tier(actor_id, faction)
	if not _tiers.has(actor_id):
		_tiers[actor_id] = {}
	var previous: WantedTier = (_tiers[actor_id] as Dictionary).get(faction)
	if previous == tier:
		return
	(_tiers[actor_id] as Dictionary)[faction] = tier
	wanted_changed.emit(actor_id, faction, tier)


func _cool(actor_id: StringName, faction: StringName, delta: float) -> void:
	var profile := get_profile(faction)
	if profile == null:
		return
	var elapsed := _get_since(actor_id, faction) + delta
	_set_since(actor_id, faction, elapsed)

	# The current rung's own patience. A murderer must not cool off by standing
	# still for four seconds, and how long "still" has to be is the tier's
	# business rather than the profile's.
	var tier := get_tier(actor_id, faction)
	if tier != null and elapsed < tier.cooldown_delay:
		return
	_set_heat(actor_id, faction, profile.decay(get_heat(actor_id, faction), delta))


func _get_since(actor_id: StringName, faction: StringName) -> float:
	return (_since_crime.get(actor_id, {}) as Dictionary).get(faction, 0.0)


func _set_since(actor_id: StringName, faction: StringName, value: float) -> void:
	if not _since_crime.has(actor_id):
		_since_crime[actor_id] = {}
	(_since_crime[actor_id] as Dictionary)[faction] = value


func _remember(actor_id: StringName, definition: CrimeDefinition) -> void:
	if not _history.has(actor_id):
		_history[actor_id] = []
	var seen: Array = _history[actor_id]
	if not seen.has(definition.id):
		seen.append(definition.id)


## Whether something already on this actor's record outranks the new offence.
##
## Reporting a murder should not also charge the assault that preceded it, and
## the direction matters: the worse crime lists what it covers, so adding an
## offence never means editing the ones below it.
func _is_superseded(actor_id: StringName, definition: CrimeDefinition) -> bool:
	for crime_id in _history.get(actor_id, []):
		if crime_id == definition.id:
			continue
		var worse := _lookup(crime_id)
		if worse != null and worse.supersedes_crime(definition.id):
			return true
	return false


func _lookup(crime_id: StringName) -> CrimeDefinition:
	return _known.get(crime_id)


## Registers a definition so superseding can find it. Called for every crime
## reported; a project can call it up front for definitions that supersede
## others without themselves being common.
func learn(definition: CrimeDefinition) -> void:
	if definition != null and definition.id != &"":
		_known[definition.id] = definition


func _resolve_actor(context: CrimeContext) -> StringName:
	if context.actor_id != &"":
		return context.actor_id
	return _identity_of(context.perpetrator)


func _resolve_law(context: CrimeContext) -> StringName:
	if context.law_faction != &"":
		return context.law_faction
	if context.definition != null and context.definition.law_faction != &"":
		return context.definition.law_faction
	return _faction_of(context.victim)


## The name the law knows an actor by.
##
## Prefers whatever answers [code]get_actor_id()[/code] — that is
## [FactionComponent], which already resolves the personal name a reputation
## accrues to — and falls back to the save id. Duck-typed rather than cast, so
## Crime works with Factions uninstalled (rule 9, rule 31).
func _identity_of(node: Node) -> StringName:
	if node == null:
		return &""
	var components := DefinitionBinder.collect_components(node)
	for component in components:
		if component.has_method("get_actor_id"):
			var actor: Variant = component.call("get_actor_id")
			if actor is StringName and actor != &"":
				return actor
	for component in components:
		if component is PersistentIdentity:
			return (component as PersistentIdentity).get_persistent_id()
	return &""


## Whose law was broken, read by duck-typing rather than by importing
## [FactionComponent], so Crime does not depend on Factions to work it out.
func _faction_of(node: Node) -> StringName:
	if node == null:
		return &""
	for component in DefinitionBinder.collect_components(node):
		if component.has_method("get_faction"):
			var faction: Variant = component.call("get_faction")
			if faction is StringName and faction != &"":
				return faction
	return &""
