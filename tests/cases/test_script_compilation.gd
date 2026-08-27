extends FrameworkTestCase
## Every script in the addon parses.
##
## [b]This suite exists because of a real miss.[/b] Godot parses a script when
## something references it, so a file no test touches can sit in the repository
## with a parse error and a green suite -- and the CI gate greps the test run's
## output for [code]SCRIPT ERROR[/code], which never appears for a script that
## was never loaded. [AreaTrigger] shipped a call to a method that did not
## exist and nothing noticed until the first test imported it.
##
## Loading a [GDScript] compiles it, so this walks the addon and loads every
## one. It is the cheapest possible guard against the class of mistake that is
## otherwise invisible until someone opens the editor.

const ADDON_ROOT: String = "res://addons/universal_gameplay"


func test_every_script_in_the_addon_loads() -> void:
	var paths := _collect(ADDON_ROOT)
	assert_true(paths.size() > 50, "expected the addon to have scripts to check")
	for path in paths:
		var script: Resource = load(path)
		assert_not_null(script, "%s failed to load" % path)


func test_every_scene_in_the_addon_loads() -> void:
	# A .tscn referencing a script that no longer exists fails the same silent
	# way, and the shipped scenes are the composition the framework promises.
	for path in _collect(ADDON_ROOT, ".tscn"):
		var scene: Resource = load(path)
		assert_not_null(scene, "%s failed to load" % path)
		assert_true(scene is PackedScene, "%s is not a scene" % path)


func test_every_shipped_scene_can_be_instantiated() -> void:
	for path in _collect(ADDON_ROOT, ".tscn"):
		var scene: PackedScene = load(path)
		var instance := scene.instantiate()
		assert_not_null(instance, "%s could not be instantiated" % path)
		if instance != null:
			add_test_node(instance)


func _collect(directory: String, suffix: String = ".gd") -> PackedStringArray:
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
				found.append_array(_collect(path, suffix))
		elif entry.ends_with(suffix):
			found.append(path)
		entry = handle.get_next()
	handle.list_dir_end()
	return found
