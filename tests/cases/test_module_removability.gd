extends FrameworkTestCase
## Rule 10: every module must be removable.
##
## The claim is about deleting a folder, not about leaving a module out of
## [member FrameworkSettings.enabled_modules] -- the addon's own source says so
## in as many words ([code]perception_solver.gd[/code]: "rule 10 says deleting
## Combat must not stop AI loading"). That makes it a claim about parsing, and
## GDScript resolves every [code]class_name[/code] a script names at parse
## time, before any module is registered and whether or not it ever is.
##
## [b]Nothing checked it.[/b] The undeclared-reference gate in the slice tests
## comes closest and deliberately stops short: it accepts a dependency written
## down in either [member ModuleManifest.requires] or
## [member ModuleManifest.optional], because rule 36 asks for the relationship
## to be recorded, not for it to be mandatory. So a module could list a
## dependency it cannot parse without as merely optional, pass that gate, and
## hand a project a folder it was told it could delete and could not. Factions
## did exactly that with Entity.
##
## This file is the other half. [member ModuleManifest.parse_requires] records
## which folders must exist, and these tests fail when a list and the source it
## describes disagree.

const ADDON_ROOT: String = "res://addons/universal_gameplay"

var _scanner: ParseDependencyScanner = null


func before_each() -> void:
	_scanner = ParseDependencyScanner.new()


# --- The lists describe the source ---------------------------------------

func test_every_module_declares_the_files_it_cannot_parse_without() -> void:
	var missing: Array[String] = []
	for id in ModuleCatalog.get_ids():
		var manifest := ModuleCatalog.get_manifest(id)
		var folder := ModuleCatalog.get_script_path(id).trim_prefix(ADDON_ROOT + "/").get_slice("/", 0)
		for dependency in _scanner.scan_folder(folder):
			if manifest.parse_requires.has(dependency):
				continue
			var reasons := _scanner.explain(folder, dependency)
			missing.append(
				(
					"%s cannot parse without %s but does not say so:\n      %s"
					% [id, dependency, "\n      ".join(reasons)]
				)
			)
	assert_empty(
		missing,
		(
			"Modules naming a sibling's classes without declaring the dependency:\n%s"
			% "\n".join(missing)
		)
	)


func test_no_module_claims_to_need_files_it_never_names() -> void:
	# The direction that rots quietly. A module drops its last reference to a
	# sibling and stays on the list forever, so a project is told it cannot
	# delete a folder that it can. Nothing breaks, which is exactly why nobody
	# would ever find it.
	var stale: Array[String] = []
	for id in ModuleCatalog.get_ids():
		var manifest := ModuleCatalog.get_manifest(id)
		var folder := ModuleCatalog.get_script_path(id).trim_prefix(ADDON_ROOT + "/").get_slice("/", 0)
		var actual := _scanner.scan_folder(folder)
		for declared in manifest.parse_requires:
			if not actual.has(declared):
				stale.append("%s lists %s, whose classes it never names" % [id, declared])
	assert_empty(stale, "Stale parse dependencies:\n%s" % "\n".join(stale))


func test_no_module_needs_its_own_files_declared() -> void:
	for id in ModuleCatalog.get_ids():
		var manifest := ModuleCatalog.get_manifest(id)
		assert_false(
			manifest.parse_requires.has(id),
			"%s lists itself among the files it cannot parse without" % id
		)


# --- What that buys a project --------------------------------------------

func test_the_modules_nothing_depends_on_are_deletable() -> void:
	# The answer a project installing the addon actually wants: which folders
	# can I remove? A module no other module names is one whose folder can go,
	# and there must be some or "every module is removable" means nothing at
	# all.
	var deletable := _deletable_modules()
	assert_true(
		deletable.size() > 0,
		"No module can be deleted without breaking another, so rule 10 holds for none of them"
	)
	# Networking is the case worth naming. A single-player game should be able
	# to delete it outright, and it is the module most likely to be dropped.
	assert_true(
		deletable.has(&"module.networking"),
		(
			"module.networking is not deletable: %s"
			% str(_dependents_of(&"module.networking"))
		)
	)


func test_deleting_a_module_is_only_safe_when_nothing_parses_against_it() -> void:
	# The other half of the same statement, and the one that keeps the list
	# honest: every module NOT reported deletable must have a named dependent.
	# Without this, a bug that returned the empty set would pass the test above
	# by making every module deletable and this one by reporting no reasons.
	var deletable := _deletable_modules()
	var unexplained: Array[String] = []
	for id in ModuleCatalog.get_ids():
		if deletable.has(id):
			continue
		if _dependents_of(id).is_empty():
			unexplained.append(str(id))
	assert_empty(
		unexplained,
		"Modules reported undeletable with no dependent to blame:\n%s" % "\n".join(unexplained)
	)


func test_entity_is_the_module_nothing_can_do_without() -> void:
	# Not an arbitrary example. Entity declares FrameworkComponent, which every
	# component in every module extends, so it is the one folder whose deletion
	# takes the framework with it. If this ever stops being true something
	# fundamental has moved and the removability story needs rereading.
	var dependents := _dependents_of(&"module.entity")
	assert_true(
		dependents.size() > 10,
		"Only %d modules parse against Entity, which is fewer than expected" % dependents.size()
	)


# --- The scanner is not lying ---------------------------------------------

func test_the_scanner_finds_a_reference_that_is_really_there() -> void:
	# FactionComponent extends FrameworkComponent, which lives in entity/.
	# This is the reference that was mislabelled optional for ten milestones,
	# so it is the one worth pinning.
	var found := _scanner.scan_folder("factions")
	assert_true(
		found.has(&"module.entity"),
		"The scanner missed factions -> entity, the reference this gate exists for"
	)
	var reasons := _scanner.explain("factions", &"module.entity")
	assert_true(
		reasons.size() > 0, "The scanner found the dependency but cannot say which file caused it"
	)


func test_the_scanner_counts_a_scene_that_attaches_a_siblings_script() -> void:
	# The half that was nearly left out. character.tscn attaches components
	# from nine other modules, so deleting one of them gives a project a
	# character scene that will not load while every character/*.gd still
	# parses. A scanner reading only GDScript would call those folders
	# deletable.
	var scanner := ParseDependencyScanner.new()
	var scene := FileAccess.get_file_as_string(
		"res://addons/universal_gameplay/character/character.tscn"
	)
	var folders := scanner._referenced_folders(scene)
	assert_true(
		folders.has("factions"),
		"The path scan did not see factions/ in character.tscn: %s" % str(folders)
	)
	assert_true(
		folders.size() > 5,
		"character.tscn composes a character from more folders than the scan found: %s"
		% str(folders)
	)
	# And the reason reaches the report, so a failure names the scene rather
	# than only the module.
	var reasons := scanner.explain("character", &"module.factions")
	var mentions_scene := false
	for reason in reasons:
		if reason.contains("character.tscn"):
			mentions_scene = true
	assert_true(
		mentions_scene, "The scene reference is found but never reported: %s" % str(reasons)
	)


func test_the_scanner_ignores_a_class_name_in_a_comment_or_a_string() -> void:
	# Both would make a folder look undeletable when it is not, and the addon's
	# documentation names sibling classes constantly.
	var scanner := ParseDependencyScanner.new()
	assert_false(
		scanner._mentions(scanner._strip("## Talks to FactionComponent about it.\n"), "FactionComponent"),
		"A class named in a doc comment was counted as a dependency"
	)
	assert_false(
		scanner._mentions(scanner._strip('\tpush_error("FactionComponent is missing")\n'), "FactionComponent"),
		"A class named inside a string literal was counted as a dependency"
	)
	assert_true(
		scanner._mentions(scanner._strip("\tvar c: FactionComponent = null\n"), "FactionComponent"),
		"A real type annotation was not counted as a dependency"
	)


# --- Helpers --------------------------------------------------------------

## Modules whose folder no other module's source names.
func _deletable_modules() -> Array[StringName]:
	var deletable: Array[StringName] = []
	for id in ModuleCatalog.get_ids():
		if _dependents_of(id).is_empty():
			deletable.append(id)
	ModuleCatalog.sort_ids(deletable)
	return deletable


## Modules that cannot parse without [param id]'s files.
##
## Read from the manifests rather than from the scanner: the tests above are
## what keep the two the same, and reading the declaration here means a wrong
## declaration shows up as a wrong answer rather than being silently corrected.
func _dependents_of(id: StringName) -> Array[StringName]:
	var dependents: Array[StringName] = []
	for other in ModuleCatalog.get_ids():
		if other == id:
			continue
		if ModuleCatalog.get_manifest(other).parse_requires.has(id):
			dependents.append(other)
	ModuleCatalog.sort_ids(dependents)
	return dependents
