extends SceneTree
## Writes the generated reference documents.
##
## Run with:
## [codeblock]
## godot --headless --path . --script tools/generate_docs.gd
## [/codeblock]
##
## The content comes from [DocGenerator]; this script only decides where it
## goes. [code]test_documentation.gd[/code] compares the committed files
## against the same generator, so forgetting to run this fails the build
## rather than shipping a stale table.

const MODULE_REFERENCE: String = "res://docs/modules.md"
const CLASS_INDEX: String = "res://docs/api-reference.md"


func _initialize() -> void:
	_write(MODULE_REFERENCE, DocGenerator.build_module_reference())
	_write(CLASS_INDEX, DocGenerator.build_class_index())

	var undocumented := DocGenerator.find_undocumented_classes()
	if not undocumented.is_empty():
		print("")
		print("Public classes with no documentation comment:")
		for path in undocumented:
			print("  %s" % path)

	quit(0)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(content)
	file.close()
	print("Wrote %s (%d lines)" % [path, content.split("\n").size()])
