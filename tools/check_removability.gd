extends SceneTree
## Reports any addon script that no longer parses.
##
## Run after deleting module folders you do not want, from the project that
## installed the addon:
## [codeblock]
## godot --headless --path . --import
## godot --headless --path . --script addons/universal_gameplay/../../tools/check_removability.gd
## [/codeblock]
##
## [b]Why this exists rather than "just open the editor".[/b] A missing module
## does not announce itself. [code]--import[/code] returns success on a project
## whose scripts cannot parse, and the engine reports a missing class only when
## something actually loads the script that names it -- which, for a definition
## type, may not happen until the day you open the scene that uses it. So the
## check has to load everything and ask.
##
## The question asked of each script is [method GDScript.can_instantiate].
## Three cheaper-looking signals were tried first and all three were useless:
## [ResourceLoader] returns a non-null [GDScript] for a script whose parse
## failed, [code]--import[/code] reports nothing, and loading with
## [code]CACHE_MODE_IGNORE[/code] reports [i]every[/i] script as broken because
## reloading hundreds of scripts in isolation thrashes the resolution of the
## global class names they share.
##
## Exits non-zero when anything is broken, so it can gate a build.

const ADDON_ROOT: String = "res://addons/universal_gameplay"


func _initialize() -> void:
	var scripts := _scripts(ADDON_ROOT)
	if scripts.is_empty():
		printerr("No addon scripts found under %s -- is the path right?" % ADDON_ROOT)
		quit(1)
		return

	var broken: Array[String] = []
	for path in scripts:
		var loaded: Resource = ResourceLoader.load(path, "GDScript")
		var script := loaded as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path.trim_prefix(ADDON_ROOT + "/"))

	print("")
	print("Checked %d script(s) under %s" % [scripts.size(), ADDON_ROOT])
	if broken.is_empty():
		print("REMOVABILITY: PASS -- every remaining script parses.")
		quit(0)
		return

	print("REMOVABILITY: FAIL -- %d script(s) no longer parse:" % broken.size())
	for path in broken:
		print("  %s" % path)
	print("")
	print("Each names a class from a folder that is no longer present. docs/modules.md")
	print("lists what must be deleted together; the engine's own parse errors, above,")
	print("name the missing type.")
	quit(1)


func _scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := directory.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_scripts(path))
			elif entry.get_extension() == "gd":
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
