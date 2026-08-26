class_name FrameworkTestRunner
extends RefCounted
## Discovers and runs [FrameworkTestCase] scripts.
##
## Discovery is by filename ([code]test_*.gd[/code]) and by method prefix
## ([code]test_*[/code]). Each test method gets a fresh instance of its case
## and a fresh scratch node, so shared state between tests is impossible
## rather than merely discouraged.

class MethodOutcome:
	extends RefCounted
	var suite: String = ""
	var method: String = ""
	var failures: Array[String] = []
	var assertions: int = 0

	func passed() -> bool:
		return failures.is_empty()


var outcomes: Array[MethodOutcome] = []
var suites_run: int = 0
var load_errors: Array[String] = []

var _tree: SceneTree = null
var _scratch_parent: Node = null


func _init(tree: SceneTree) -> void:
	_tree = tree
	_scratch_parent = Node.new()
	_scratch_parent.name = "TestScratch"
	_tree.root.add_child(_scratch_parent)


## Runs every [code]test_*.gd[/code] under [param directory], recursively.
##
## Yields one frame first. Nodes added during [method SceneTree._initialize]
## are not actually inside the tree yet: is_inside_tree() is false, _ready()
## has not run, and anything spatial silently misbehaves. One frame makes the
## tree live, after which add_child() behaves exactly as it does in a game.
func run_directory(directory: String) -> void:
	await _tree.process_frame
	var paths := _find_test_scripts(directory)
	paths.sort()
	for path in paths:
		run_script(path)


func run_script(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		load_errors.append("Could not load test script: %s" % path)
		return

	var probe: Variant = script.new()
	if not (probe is FrameworkTestCase):
		load_errors.append("%s does not extend FrameworkTestCase." % path)
		return

	var suite_name := path.get_file().get_basename()
	var method_names := _find_test_methods(probe as FrameworkTestCase)
	if method_names.is_empty():
		load_errors.append("%s contains no test_* methods." % path)
		return

	suites_run += 1
	for method_name in method_names:
		outcomes.append(_run_method(script, suite_name, method_name))


func _run_method(script: GDScript, suite_name: String, method_name: String) -> MethodOutcome:
	var outcome := MethodOutcome.new()
	outcome.suite = suite_name
	outcome.method = method_name

	# One instance and one scratch node per method: isolation by construction.
	var node_root := Node.new()
	node_root.name = "%s_%s" % [suite_name, method_name]
	_scratch_parent.add_child(node_root)

	var test_case: FrameworkTestCase = script.new()
	test_case._begin_test(_tree, node_root)

	test_case.before_each()
	test_case.call(method_name)
	test_case.after_each()

	outcome.failures = test_case.get_failures().duplicate()
	outcome.assertions = test_case.get_assertion_count()

	# A test that asserted nothing did not pass -- it either forgot to check
	# anything, or a runtime error aborted it partway. GDScript does not
	# propagate that abort, so without this check a broken test reports PASS
	# and the suite lies. This exact failure hid a fixture parse error during
	# development, which is why it is here.
	if outcome.assertions == 0 and outcome.failures.is_empty():
		outcome.failures.append(
			"Recorded no assertions. The test is either empty or aborted early "
			+ "-- check the output above for a SCRIPT ERROR."
		)

	node_root.free()
	return outcome


func _find_test_methods(test_case: FrameworkTestCase) -> Array[String]:
	var names: Array[String] = []
	for method in test_case.get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	return names


func _find_test_scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		load_errors.append("Could not open test directory: %s" % directory)
		return found

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := directory.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_find_test_scripts(full_path))
			elif entry.begins_with("test_") and entry.get_extension() == "gd":
				found.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


# --- Reporting ------------------------------------------------------------

func get_passed_count() -> int:
	return outcomes.filter(func(o: MethodOutcome) -> bool: return o.passed()).size()


func get_failed_count() -> int:
	return outcomes.size() - get_passed_count()


func get_assertion_total() -> int:
	var total := 0
	for outcome in outcomes:
		total += outcome.assertions
	return total


func is_successful() -> bool:
	return get_failed_count() == 0 and load_errors.is_empty()


func print_report() -> void:
	print("")
	print("Universal Gameplay Framework -- test run")
	print("=".repeat(60))

	var current_suite := ""
	for outcome in outcomes:
		if outcome.suite != current_suite:
			current_suite = outcome.suite
			print("\n%s" % current_suite)
		if outcome.passed():
			print("  PASS  %s (%d assertions)" % [outcome.method, outcome.assertions])
		else:
			print("  FAIL  %s" % outcome.method)
			for failure in outcome.failures:
				print("          %s" % failure)

	if not load_errors.is_empty():
		print("\nLoad errors")
		for error in load_errors:
			print("  ERROR %s" % error)

	print("")
	print("=".repeat(60))
	print(
		(
			"%d suite(s), %d test(s), %d passed, %d failed, %d assertions"
			% [
				suites_run,
				outcomes.size(),
				get_passed_count(),
				get_failed_count(),
				get_assertion_total(),
			]
		)
	)
	print("RESULT: %s" % ("PASS" if is_successful() else "FAIL"))


func cleanup() -> void:
	if is_instance_valid(_scratch_parent):
		_scratch_parent.free()
		_scratch_parent = null
