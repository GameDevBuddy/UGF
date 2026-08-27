extends FrameworkTestCase
## M19: the documentation describes the framework that exists.
##
## Reference documentation rots silently. Nobody notices that the module table
## is missing a module, because nobody reads a table looking for something
## that is not in it -- they read it, believe it, and act on it. So the tables
## are generated from the source and compared here, and the prose that cannot
## be generated is checked for the things that go stale first: dead links, and
## a save-schema number that moved without anyone writing down how to migrate.

const MODULES_DOC: String = "res://docs/modules.md"
const API_DOC: String = "res://docs/api-reference.md"
const MIGRATION_DOC: String = "res://docs/migration-guide.md"
const README: String = "res://README.md"
const EXAMPLES_README: String = "res://examples/README.md"

const REGENERATE: String = (
	"Run: godot --headless --path . --script tools/generate_docs.gd"
)


# --- Generated documents match their source ------------------------------

func test_the_module_reference_is_current() -> void:
	assert_eq(
		_read(MODULES_DOC),
		DocGenerator.build_module_reference(),
		"docs/modules.md no longer matches the module manifests. %s" % REGENERATE
	)


func test_the_api_reference_is_current() -> void:
	assert_eq(
		_read(API_DOC),
		DocGenerator.build_class_index(),
		"docs/api-reference.md no longer matches the addon's classes. %s" % REGENERATE
	)


func test_the_module_reference_names_every_module() -> void:
	# Belt and braces on the comparison above: if the generator itself started
	# dropping modules, both sides would agree and both would be wrong.
	var text := _read(MODULES_DOC)
	for id in ModuleCatalog.get_ids():
		assert_true(text.contains(str(id)), "docs/modules.md does not mention %s" % id)


func test_every_public_class_documents_itself() -> void:
	# A class_name with no doc comment is one a project has to read the body
	# of before it can use it, and it lands in the API reference as a blank.
	var undocumented := DocGenerator.find_undocumented_classes()
	assert_empty(undocumented, "Public classes with no documentation:\n%s" % "\n".join(undocumented))


# --- Hand-written prose ---------------------------------------------------

func test_the_migration_guide_covers_the_current_save_schema() -> void:
	# The number that must never move quietly. A save schema bump with no
	# migration note is a shipped game that cannot load its own saves.
	var text := _read(MIGRATION_DOC)
	assert_true(
		text.contains("Schema %d" % FrameworkVersion.SAVE_SCHEMA),
		(
			"docs/migration-guide.md has no section for save schema %d. "
			+ "Bumping FrameworkVersion.SAVE_SCHEMA means writing down how to get there."
		) % FrameworkVersion.SAVE_SCHEMA
	)


func test_the_migration_guide_states_the_current_framework_version() -> void:
	var text := _read(MIGRATION_DOC)
	assert_true(
		text.contains(FrameworkVersion.get_version_string()),
		"docs/migration-guide.md does not mention version %s"
		% FrameworkVersion.get_version_string()
	)


func test_the_examples_are_documented() -> void:
	var text := _read(EXAMPLES_README)
	assert_true(text.contains("adventure"), "examples/README.md skips the adventure example")
	assert_true(text.contains("survival"), "examples/README.md skips the survival example")


# --- Links ----------------------------------------------------------------

func test_no_document_links_to_a_file_that_does_not_exist() -> void:
	# The cheapest documentation bug to introduce and the most annoying to
	# meet: a link that was right when it was written.
	var broken: Array[String] = []
	for document in _documents():
		var base := document.get_base_dir()
		for target in _relative_links(_read(document)):
			var resolved := _resolve(base, target)
			if not FileAccess.file_exists(resolved) and not DirAccess.dir_exists_absolute(resolved):
				broken.append("%s links to %s" % [document, target])
	assert_empty(broken, "\n".join(broken))


# --- Helpers --------------------------------------------------------------

func _documents() -> Array[String]:
	var found: Array[String] = [README, EXAMPLES_README]
	var dir := DirAccess.open("res://docs")
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.get_extension() == "md":
			found.append("res://docs".path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


## Link targets from Markdown [code][text](target)[/code], keeping only the
## ones that point at a file in this repository.
func _relative_links(text: String) -> Array[String]:
	var found: Array[String] = []
	var search := 0
	while true:
		var open_bracket := text.find("](", search)
		if open_bracket < 0:
			break
		var close_paren := text.find(")", open_bracket + 2)
		if close_paren < 0:
			break
		var target := text.substr(open_bracket + 2, close_paren - open_bracket - 2)
		search = close_paren + 1
		if target.begins_with("http") or target.begins_with("#") or target.is_empty():
			continue
		# An anchor into another file still names a file.
		var hash_index := target.find("#")
		if hash_index >= 0:
			target = target.substr(0, hash_index)
		if not target.is_empty():
			found.append(target)
	return found


func _resolve(base: String, target: String) -> String:
	if target.begins_with("res://"):
		return target
	return base.path_join(target).simplify_path()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("Could not read %s" % path)
		return ""
	var text := file.get_as_text()
	file.close()
	return text
