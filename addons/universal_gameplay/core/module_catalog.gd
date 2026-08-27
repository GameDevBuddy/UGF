class_name ModuleCatalog
extends RefCounted
## Every feature module the addon ships, indexed by id.
##
## This is the piece that turns a folder of scripts into an installable
## product. Without it a project wanting Inventory has to know that the module
## lives at [code]inventory/inventory_module.gd[/code], instantiate it by path,
## and work out for itself that Items and Entity have to be registered first.
## With it, the project names [code]&"module.inventory"[/code] and the
## framework knows the rest -- which is the whole of the M19 exit gate.
##
## The table is written out rather than discovered by scanning the addon
## folder. Scanning works in the editor and quietly stops working in an
## exported build: [DirAccess] over [code]res://[/code] sees only what the
## exporter packed, and scripts are remapped on the way in, so a shipped game
## would find no modules at all. A literal table exports correctly. It can
## drift from the files on disk, so [code]test_packaging.gd[/code] compares the
## two and fails when they disagree.
##
## No content lives here. The catalog knows module [i]ids[/i] and [i]script
## paths[/i]; what a module does with them is the module's business (rule 29).

## Module id to the script implementing it. Sorted by id for readability;
## registration order comes from [method resolve_order], never from this
## table.
const MODULES: Dictionary[StringName, String] = {
	&"module.ai": "res://addons/universal_gameplay/ai/ai_module.gd",
	&"module.animation": "res://addons/universal_gameplay/animation/animation_module.gd",
	&"module.camera": "res://addons/universal_gameplay/camera/camera_module.gd",
	&"module.character": "res://addons/universal_gameplay/character/character_module.gd",
	&"module.combat": "res://addons/universal_gameplay/combat/combat_module.gd",
	&"module.commerce": "res://addons/universal_gameplay/commerce/commerce_module.gd",
	&"module.crafting": "res://addons/universal_gameplay/crafting/crafting_module.gd",
	&"module.crime": "res://addons/universal_gameplay/crime_heat/crime_module.gd",
	&"module.dialogue": "res://addons/universal_gameplay/dialogue/dialogue_module.gd",
	&"module.entity": "res://addons/universal_gameplay/entity/entity_module.gd",
	&"module.equipment": "res://addons/universal_gameplay/equipment/equipment_module.gd",
	&"module.factions": "res://addons/universal_gameplay/factions/factions_module.gd",
	&"module.gathering": "res://addons/universal_gameplay/gathering/gathering_module.gd",
	&"module.health": "res://addons/universal_gameplay/health_damage/health_module.gd",
	&"module.input": "res://addons/universal_gameplay/input/input_module.gd",
	&"module.interaction": "res://addons/universal_gameplay/interaction/interaction_module.gd",
	&"module.inventory": "res://addons/universal_gameplay/inventory/inventory_module.gd",
	&"module.items": "res://addons/universal_gameplay/items/items_module.gd",
	&"module.locomotion": "res://addons/universal_gameplay/locomotion/locomotion_module.gd",
	&"module.loot": "res://addons/universal_gameplay/loot/loot_module.gd",
	&"module.missions": "res://addons/universal_gameplay/missions/missions_module.gd",
	&"module.narrative": "res://addons/universal_gameplay/narrative/narrative_module.gd",
	&"module.networking": "res://addons/universal_gameplay/networking/networking_module.gd",
	&"module.progression": "res://addons/universal_gameplay/progression/progression_module.gd",
	&"module.save": "res://addons/universal_gameplay/persistence/persistence_module.gd",
	&"module.spawn": "res://addons/universal_gameplay/spawn/spawn_module.gd",
	&"module.stats": "res://addons/universal_gameplay/stats/stats_module.gd",
	&"module.status_effects": (
		"res://addons/universal_gameplay/status_effects/status_effects_module.gd"
	),
	&"module.survival": "res://addons/universal_gameplay/survival/survival_module.gd",
	&"module.ui": "res://addons/universal_gameplay/ui/ui_module.gd",
	&"module.vehicles": "res://addons/universal_gameplay/vehicles/vehicles_module.gd",
	&"module.world_state": "res://addons/universal_gameplay/world/world_module.gd",
}


static func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(MODULES.keys())
	sort_ids(ids)
	return ids


## Sorts module ids alphabetically, in place.
##
## [b]Array[StringName].sort() does not do this.[/b] StringNames compare by
## their address in the engine's intern table, so sorting them yields the order
## those names were first created in -- which depends on which scripts the
## engine happened to load first, and therefore differs between the editor, a
## headless run and an exported build.
##
## Everywhere ordering is user-visible or has to be reproducible, that is the
## wrong order and it is wrong in the worst way: deterministic within a single
## process, so it looks stable right up until it changes between builds.
static func sort_ids(ids: Array[StringName]) -> void:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))


static func has(id: StringName) -> bool:
	return MODULES.has(id)


static func get_script_path(id: StringName) -> String:
	return MODULES.get(id, "")


## A fresh instance of the module, or null if the id is unknown.
##
## Fresh every call, deliberately. A module holds whatever its
## [method FrameworkModule.initialize] claimed, so handing the same instance to
## two cores would give them one shared set of services -- which is precisely
## the shared mutable state rule 2 exists to prevent.
static func instantiate(id: StringName) -> FrameworkModule:
	if not MODULES.has(id):
		return null
	var script: GDScript = load(MODULES[id])
	if script == null:
		return null
	return script.new() as FrameworkModule


## The manifest a module would present, without registering it.
##
## Cheap: modules are [RefCounted] and building a manifest touches nothing
## outside the module. This is what lets dependency resolution answer "what
## does Inventory need?" before anything has been instantiated for real.
static func get_manifest(id: StringName) -> ModuleManifest:
	var module := instantiate(id)
	return module.get_manifest() if module != null else null


## Ids [param requested] depends on, transitively, that were not requested.
##
## Reported rather than added silently. A project that asked for Combat and
## gets Entity, Stats, Health, Items and Inventory registered behind its back
## has a module list that no longer describes its game, and the first time one
## of those "extra" modules misbehaves there is nothing to point at. The
## bootstrapper prints this list and tells the project to add them.
static func get_implied_requirements(requested: Array[StringName]) -> Array[StringName]:
	var asked: Dictionary[StringName, bool] = {}
	for id in requested:
		asked[id] = true

	var implied: Dictionary[StringName, bool] = {}
	var pending: Array[StringName] = requested.duplicate()
	while not pending.is_empty():
		var id: StringName = pending.pop_back()
		var manifest := get_manifest(id)
		if manifest == null:
			continue
		for dependency in manifest.requires:
			if asked.has(dependency) or implied.has(dependency):
				continue
			implied[dependency] = true
			pending.append(dependency)

	var result: Array[StringName] = []
	result.assign(implied.keys())
	sort_ids(result)
	return result


## Orders [param requested] so every module comes after the modules it
## requires, and returns the order as the result payload.
##
## Fails rather than guessing when the list cannot be satisfied:
## [code]catalog.unknown_module[/code] for an id the addon does not ship,
## [code]catalog.missing_dependency[/code] when a required module is absent
## from the list, and [code]catalog.dependency_cycle[/code] when two modules
## require each other. Nothing is instantiated for real in any of those cases.
##
## Optional dependencies are ignored here on purpose. A module that works
## without another must not be ordered by it, or a project enabling both would
## be told it has a cycle over a relationship that is not one (rule 31).
static func resolve_order(requested: Array[StringName]) -> FrameworkResult:
	var unknown: Array[StringName] = []
	for id in requested:
		if not MODULES.has(id):
			unknown.append(id)
	if not unknown.is_empty():
		return FrameworkResult.fail(
			&"catalog.unknown_module",
			"The addon ships no module with id %s." % str(unknown)
		)

	var wanted: Dictionary[StringName, bool] = {}
	for id in requested:
		wanted[id] = true

	# Requirements of every requested module, filtered to the requested set.
	# Anything outside it is a missing dependency, reported before any
	# ordering happens so the message names the real problem.
	var edges: Dictionary[StringName, Array] = {}
	var missing: Array[String] = []
	for id in wanted:
		var manifest := get_manifest(id)
		var dependencies: Array[StringName] = []
		if manifest != null:
			for dependency in manifest.requires:
				if wanted.has(dependency):
					dependencies.append(dependency)
				else:
					missing.append("%s requires %s" % [id, dependency])
		edges[id] = dependencies
	if not missing.is_empty():
		missing.sort()
		return FrameworkResult.fail(
			&"catalog.missing_dependency",
			"Not every dependency is enabled: %s." % ", ".join(missing)
		)

	# Repeatedly take the modules whose dependencies are all placed. Ids are
	# sorted alphabetically within each pass -- see sort_ids -- so the order is
	# the same in every process. An order that varies between the editor and an
	# exported build turns a dependency bug into one that only reproduces after
	# shipping.
	var ordered: Array[StringName] = []
	var placed: Dictionary[StringName, bool] = {}
	while ordered.size() < wanted.size():
		var ready_now: Array[StringName] = []
		for id in edges:
			if placed.has(id):
				continue
			var satisfied := true
			for dependency in edges[id]:
				if not placed.has(dependency):
					satisfied = false
					break
			if satisfied:
				ready_now.append(id)

		if ready_now.is_empty():
			var stuck: Array[StringName] = []
			for id in edges:
				if not placed.has(id):
					stuck.append(id)
			sort_ids(stuck)
			return FrameworkResult.fail(
				&"catalog.dependency_cycle",
				"These modules require each other, directly or through others: %s." % str(stuck)
			)

		sort_ids(ready_now)
		for id in ready_now:
			placed[id] = true
			ordered.append(id)

	return FrameworkResult.ok(ordered)
