class_name ParseDependencyScanner
extends RefCounted
## Which modules' files each module cannot parse without.
##
## [b]Presence and enablement are two different relations, and the manifest
## only ever had words for one of them.[/b] [member ModuleManifest.requires]
## says a module must be [i]registered[/i]; [member ModuleManifest.optional]
## says another is integrated with when it is. Neither says anything about
## whether the [i]files[/i] have to be on disk, and in GDScript that is the
## relation that decides whether a script loads at all: naming a
## [code]class_name[/code] anywhere in a script body is resolved when the
## script is parsed, long before any module is registered.
##
## So [code]module.factions[/code] could truthfully declare
## [code]requires = [][/code] -- a [FactionComponent] needs nothing about
## Entity registered -- while being unable to parse without Entity, because
## [FactionComponent] extends [FrameworkComponent] and that class lives in
## [code]entity/[/code]. Both halves of the manifest were accurate. The
## vocabulary simply could not express the part that breaks a project which
## deletes a folder it was told was optional (rule 10, rule 31).
##
## This is the scanner behind both halves of the answer: the
## [member ModuleManifest.parse_requires] lists themselves were generated from
## it, and [code]test_module_removability.gd[/code] fails when a module's list
## and its source stop agreeing. One scanner, so the data and the gate that
## enforces it cannot drift apart.
##
## Lives in [code]tools/[/code] for the same reason [DocGenerator] does: it is
## build machinery, and shipping a source scanner inside the addon would put it
## in every game that installs the framework (rule 29 in spirit).

const ADDON_ROOT: String = "res://addons/universal_gameplay"

var _folders: Dictionary = {}
var _classes: Dictionary = {}
var _patterns: Dictionary = {}
var _path_pattern: RegEx = null


## Module id to the sorted ids of the modules whose files it needs on disk.
##
## Only modules appear on either side. A class declared in [code]core/[/code]
## or another shared folder is deliberately absent: those are not modules,
## cannot be deleted, and every module may know them.
func scan() -> Dictionary:
	var found: Dictionary = {}
	for folder in _module_folders():
		var id: StringName = _module_folders()[folder]
		found[id] = scan_folder(folder)
	return found


## The modules one folder's sources name, as sorted module ids.
func scan_folder(folder: String) -> Array[StringName]:
	var modules := _module_folders()
	var classes := _class_folders()
	var needed: Array[StringName] = []

	for path in _sources():
		if _folder_of(path) != folder:
			continue
		var source := FileAccess.get_file_as_string(path)
		var readable := _strip(source)
		for declared_class in classes:
			var owner_folder: String = classes[declared_class]
			if owner_folder == folder:
				continue
			var dependency: StringName = modules[owner_folder]
			if needed.has(dependency):
				continue
			if _mentions(readable, declared_class):
				needed.append(dependency)
		# The path scan reads the raw source, not the stripped copy. Every one
		# of these lives inside a string literal, and _strip removes exactly
		# those -- running the two scans over the same text would make one of
		# them find nothing.
		for referenced in _referenced_folders(source):
			if referenced == folder or not modules.has(referenced):
				continue
			var dependency: StringName = modules[referenced]
			if not needed.has(dependency):
				needed.append(dependency)

	ModuleCatalog.sort_ids(needed)
	return needed


## Every class name one folder borrows from another module, for a message that
## names the reason rather than only the conclusion.
func explain(folder: String, dependency: StringName) -> Array[String]:
	var modules := _module_folders()
	var classes := _class_folders()
	var reasons: Array[String] = []

	for path in _sources():
		if _folder_of(path) != folder:
			continue
		var source := FileAccess.get_file_as_string(path)
		var readable := _strip(source)
		for declared_class in classes:
			var owner_folder: String = classes[declared_class]
			if owner_folder == folder or modules[owner_folder] != dependency:
				continue
			if _mentions(readable, declared_class):
				var entry := "%s names %s" % [path.trim_prefix(ADDON_ROOT + "/"), declared_class]
				if not reasons.has(entry):
					reasons.append(entry)
		for referenced in _referenced_folders(source):
			if referenced == folder or modules.get(referenced, &"") != dependency:
				continue
			var entry := "%s loads a file out of %s/" % [path.trim_prefix(ADDON_ROOT + "/"), referenced]
			if not reasons.has(entry):
				reasons.append(entry)
	reasons.sort()
	return reasons


## The folder each module's script lives in, mapped to that module's id.
func _module_folders() -> Dictionary:
	if not _folders.is_empty():
		return _folders
	for id in ModuleCatalog.get_ids():
		_folders[_folder_of(ModuleCatalog.get_script_path(id))] = id
	return _folders


## Every [code]class_name[/code] declared inside a module folder, mapped to
## that folder.
func _class_folders() -> Dictionary:
	if not _classes.is_empty():
		return _classes
	var modules := _module_folders()
	for path in _files(ADDON_ROOT, "gd"):
		var folder := _folder_of(path)
		if not modules.has(folder):
			continue
		var declared := _declared_class(_strip(FileAccess.get_file_as_string(path)))
		if not declared.is_empty():
			_classes[declared] = folder
	return _classes


## Source with comment lines and string literals removed.
##
## Both go for the same reason: neither makes the engine load another script.
## A doc comment naming a sibling's class is a cross-reference, and a class
## name inside an error message is a word. Counting either would put modules on
## a list that says "these files must exist" when they need not.
func _strip(source: String) -> String:
	var quoted := RegEx.create_from_string('"[^"\\n]*"')
	var kept: Array[String] = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(quoted.sub(line, " ", true))
	return "\n".join(kept)


## Addon folders [param source] names by path.
##
## Read from the raw source rather than from [method _strip]'s output: a path
## is only ever written inside a string literal, and stripping literals is what
## the class scan needs and this scan cannot survive. Whole-line comments still
## go, so a doc comment quoting a path stays a cross-reference.
func _referenced_folders(source: String) -> Array[String]:
	if _path_pattern == null:
		# Nothing in ADDON_ROOT is a regex metacharacter, so it goes in as-is.
		_path_pattern = RegEx.create_from_string("%s/([a-z_0-9]+)/" % ADDON_ROOT)
	var found: Array[String] = []
	for hit in _path_pattern.search_all(_uncommented(source)):
		var folder := hit.get_string(1)
		if not found.has(folder):
			found.append(folder)
	return found


## Source with whole-line comments removed and string literals left alone.
func _uncommented(source: String) -> String:
	var kept: Array[String] = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _mentions(source: String, identifier: String) -> bool:
	if not source.contains(identifier):
		return false
	var pattern: RegEx = _patterns.get(identifier)
	if pattern == null:
		pattern = RegEx.create_from_string("\\b%s\\b" % identifier)
		_patterns[identifier] = pattern
	return pattern.search(source) != null


func _declared_class(source: String) -> String:
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("class_name "):
			return trimmed.substr("class_name ".length()).strip_edges()
	return ""


func _folder_of(path: String) -> String:
	return path.trim_prefix(ADDON_ROOT + "/").get_slice("/", 0)


## Scripts, scenes and resources alike.
##
## Scenes were nearly left out, on the reasoning that a [code].tscn[/code]
## attaching a sibling's script is the [i]scene's[/i] dependency rather than
## the module's. That reasoning is wrong, and checking beat arguing:
## [code]character.tscn[/code] attaches components from nine other modules, so
## deleting any one of them gives a project a character scene that will not
## load while every [code]character/*.gd[/code] still parses perfectly. A list
## of deletable folders built from scripts alone would have understated the
## cost of exactly the removals most likely to be attempted.
func _sources() -> Array[String]:
	var found: Array[String] = _files(ADDON_ROOT, "gd")
	found.append_array(_files(ADDON_ROOT, "tscn"))
	found.append_array(_files(ADDON_ROOT, "tres"))
	return found


func _files(directory: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	var handle := DirAccess.open(directory)
	if handle == null:
		return found
	handle.list_dir_begin()
	var entry := handle.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := directory.path_join(entry)
			if handle.current_is_dir():
				found.append_array(_files(path, extension))
			elif entry.get_extension() == extension:
				found.append(path)
		entry = handle.get_next()
	handle.list_dir_end()
	found.sort()
	return found
