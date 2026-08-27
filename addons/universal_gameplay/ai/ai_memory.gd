class_name AIMemory
extends RefCounted
## Everything one NPC currently knows about everything else.
##
## A plain object rather than a component, so a brain can be tested with a
## memory built by hand and no scene at all (rule 33). [PerceptionComponent]
## owns one and feeds it; brains read it.
##
## [b]It forgets.[/b] That is the point: a memory that never decayed would give
## every guard perfect recall of everyone they ever saw, and "search where they
## went, then give up" is the behaviour that makes stealth legible.

## Emitted the first time a target is noticed, after any notice time.
signal target_noticed(entry: MemoryEntry)
## Emitted when a target that was visible stops being so.
signal target_lost(entry: MemoryEntry)
## Emitted when a target decays out of memory entirely.
signal target_forgotten(target: Node)
## Emitted the first time a target hurts us.
signal attacked_by(entry: MemoryEntry)
## Emitted when a target is seen using something.
signal interaction_witnessed(entry: MemoryEntry, interaction_id: StringName)

var _entries: Dictionary[int, MemoryEntry] = {}


func get_entries() -> Array[MemoryEntry]:
	var out: Array[MemoryEntry] = []
	out.assign(_entries.values())
	return out


func get_entry(target: Node) -> MemoryEntry:
	if target == null:
		return null
	return _entries.get(target.get_instance_id())


func knows(target: Node) -> bool:
	return get_entry(target) != null


func is_empty() -> bool:
	return _entries.is_empty()


func size() -> int:
	return _entries.size()


## Everything perceived right now.
func get_visible() -> Array[MemoryEntry]:
	return get_entries().filter(func(e: MemoryEntry) -> bool: return e.visible and e.noticed)


## Everything remembered but not currently perceived. What a search behaviour
## walks towards.
func get_remembered() -> Array[MemoryEntry]:
	return get_entries().filter(func(e: MemoryEntry) -> bool: return not e.visible and e.noticed)


## The most dangerous thing currently perceived, or null.
##
## Ties break on distance when an origin is supplied, so two identical enemies
## do not make an NPC dither between them.
func get_primary(origin: Variant = null) -> MemoryEntry:
	var best: MemoryEntry = null
	for entry in get_visible():
		if best == null or entry.threat > best.threat:
			best = entry
			continue
		if origin is Vector3 and is_equal_approx(entry.threat, best.threat):
			var here := origin as Vector3
			if here.distance_to(entry.last_known_position) < here.distance_to(
				best.last_known_position
			):
				best = entry
	return best


## The freshest thing remembered but not seen, or null.
func get_freshest_memory() -> MemoryEntry:
	var best: MemoryEntry = null
	for entry in get_remembered():
		if best == null or entry.time_since_seen < best.time_since_seen:
			best = entry
	return best


# --- Recording ------------------------------------------------------------

## Records a sighting, creating the memory if this is the first.
##
## [param notice_time] is how long the target must stay in view before
## [signal target_noticed] fires; until then the NPC has something in the
## corner of its eye and has not reacted to it.
func see(
	target: Node,
	position: Vector3,
	threat: float,
	delta: float,
	notice_time: float = 0.0
) -> MemoryEntry:
	if target == null:
		return null
	var entry := _ensure(target, threat)
	entry.see(position, threat, delta)
	if not entry.noticed and entry.time_in_view >= notice_time:
		entry.noticed = true
		target_noticed.emit(entry)
	return entry


## Records a noise at a position. Noticed immediately, and never "visible".
func hear(target: Node, position: Vector3, threat: float = 1.0) -> MemoryEntry:
	if target == null:
		return null
	var entry := _ensure(target, threat)
	var was_noticed := entry.noticed
	entry.hear(position)
	if not was_noticed:
		target_noticed.emit(entry)
	return entry


## Records being hurt by a target, creating the memory if this is the first.
##
## No sight line and no notice time: being shot is not something you gradually
## realise. [param threat] seeds the memory for a target never seen before,
## which is the case that matters -- an ambush.
func damaged_by(
	target: Node, position: Vector3, amount: float, threat: float = 1.0
) -> MemoryEntry:
	if target == null:
		return null
	var entry := _ensure(target, threat)
	var was_attacker := entry.attacked_us
	var was_noticed := entry.noticed
	entry.hurt_by(position, amount)
	if not was_noticed:
		target_noticed.emit(entry)
	if not was_attacker:
		attacked_by.emit(entry)
	return entry


## Records seeing a target use something.
##
## The plan's interaction stimulus. Unlike damage this one is only recorded by
## a caller that already established the NPC could perceive it, because
## somebody picking a lock two districts away is not a stimulus.
func witnessed_interaction(
	target: Node, position: Vector3, interaction_id: StringName, threat: float = 1.0
) -> MemoryEntry:
	if target == null:
		return null
	var entry := _ensure(target, threat)
	var was_noticed := entry.noticed
	entry.saw_interaction(position, interaction_id)
	if not was_noticed:
		target_noticed.emit(entry)
	interaction_witnessed.emit(entry, interaction_id)
	return entry


## Targets that have hurt us, most damaging first.
##
## What a brain asks when it wants to fight back rather than to investigate.
func get_attackers() -> Array[MemoryEntry]:
	var found: Array[MemoryEntry] = []
	for entry in get_entries():
		if entry.attacked_us and entry.is_valid():
			found.append(entry)
	found.sort_custom(
		func(a: MemoryEntry, b: MemoryEntry) -> bool:
			return a.damage_taken_from > b.damage_taken_from
	)
	return found


## Ages every memory not perceived this sweep and drops what has decayed.
##
## [param perceived] is what was seen this sweep; everything else ages.
func age(delta: float, perceived: Array[Node], duration: float) -> void:
	for entry in get_entries():
		if not entry.is_valid():
			_forget(entry)
			continue
		if perceived.has(entry.target):
			continue
		var was_visible := entry.visible
		entry.lose(delta)
		if was_visible:
			target_lost.emit(entry)
		if entry.is_stale(duration):
			_forget(entry)


## Drops one memory outright. What a brain calls when it has searched a last
## known position and found nothing.
func forget(target: Node) -> void:
	var entry := get_entry(target)
	if entry != null:
		_forget(entry)


func clear() -> void:
	for entry in get_entries():
		_forget(entry)


# --- Internals ------------------------------------------------------------

func _ensure(target: Node, threat: float) -> MemoryEntry:
	var key := target.get_instance_id()
	if not _entries.has(key):
		_entries[key] = MemoryEntry.create(target, threat)
	return _entries[key]


func _forget(entry: MemoryEntry) -> void:
	var target := entry.target
	_entries.erase(target.get_instance_id() if entry.is_valid() else _key_of(entry))
	target_forgotten.emit(target)


## Finds the key of an entry whose target has already been freed, so a memory
## of something that no longer exists can still be dropped.
func _key_of(entry: MemoryEntry) -> int:
	for key in _entries:
		if _entries[key] == entry:
			return key
	return 0
