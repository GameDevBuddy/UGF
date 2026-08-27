extends FrameworkTestCase
## Every module the addon ships declares a manifest that names real modules.
##
## [b]A dependency graph written as string literals rots quietly.[/b] A module
## can require [code]module.narrativee[/code] and nothing complains: the
## registry simply never resolves it, the module never loads, and the feature
## is missing in a way that looks like a content bug. Twenty-odd modules
## naming each other by hand is exactly the surface the compilation guard
## cannot see, because a typo in a StringName is not a parse error.
##
## Written as a sweep rather than one test per module so a module added in a
## later milestone is covered the moment its file lands.

const ADDON_ROOT: String = "res://addons/universal_gameplay"

## The abstract base every module extends. It matches the
## [code]*_module.gd[/code] naming and is not a module, so the sweep skips it
## by path rather than by "has no id" -- a real module that forgot its id must
## still fail.
const BASE_CONTRACT: String = (
	"res://addons/universal_gameplay/core/contracts/framework_module.gd"
)


func _modules() -> Array[FrameworkModule]:
	var modules: Array[FrameworkModule] = []
	for path in _collect(ADDON_ROOT):
		if path == BASE_CONTRACT:
			continue
		var script: GDScript = load(path)
		var instance: Variant = script.new()
		if instance is FrameworkModule:
			modules.append(instance as FrameworkModule)
	return modules


func _known_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for module in _modules():
		ids.append(module.get_manifest().id)
	return ids


func test_the_addon_ships_the_modules_the_roadmap_names() -> void:
	var ids := _known_ids()
	for expected in [
		GameplayNames.MODULE_SURVIVAL,
		GameplayNames.MODULE_CRAFTING,
		GameplayNames.MODULE_GATHERING,
	]:
		assert_has(ids, expected)
	assert_true(ids.size() >= 24, "expected the whole shipped set, got %d" % ids.size())


func test_every_module_id_is_unique() -> void:
	var seen: Array[StringName] = []
	for id in _known_ids():
		assert_has_not(seen, id, "%s is declared twice" % id)
		seen.append(id)


func test_every_manifest_validates() -> void:
	for module in _modules():
		var manifest := module.get_manifest()
		assert_false(
			manifest.validate().has_errors(),
			"%s has manifest errors" % manifest.get_debug_name()
		)


func test_every_declared_dependency_names_a_module_that_exists() -> void:
	# The whole point of the suite. A required module that is not shipped can
	# never resolve, and the failure looks like missing content rather than a
	# typo.
	var ids := _known_ids()
	for module in _modules():
		var manifest := module.get_manifest()
		for required in manifest.requires:
			assert_has(ids, required, "%s requires unknown %s" % [manifest.id, required])
		for optional in manifest.optional:
			assert_has(ids, optional, "%s optionally uses unknown %s" % [manifest.id, optional])


func test_no_module_depends_on_itself() -> void:
	for module in _modules():
		var manifest := module.get_manifest()
		assert_has_not(manifest.requires, manifest.id)
		assert_has_not(manifest.optional, manifest.id)


func test_no_module_is_both_required_and_optional_to_the_same_module() -> void:
	for module in _modules():
		var manifest := module.get_manifest()
		for required in manifest.requires:
			assert_has_not(
				manifest.optional,
				required,
				"%s lists %s as both required and optional" % [manifest.id, required]
			)


func _collect(directory: String) -> PackedStringArray:
	var found := PackedStringArray()
	var handle := DirAccess.open(directory)
	if handle == null:
		return found
	handle.list_dir_begin()
	var entry := handle.get_next()
	while entry != "":
		var path := directory.path_join(entry)
		if handle.current_is_dir():
			if not entry.begins_with("."):
				found.append_array(_collect(path))
		elif entry.ends_with("_module.gd"):
			found.append(path)
		entry = handle.get_next()
	handle.list_dir_end()
	return found
