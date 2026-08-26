class_name FrameworkTestCase
extends RefCounted
## Base class for a framework test.
##
## Deliberately dependency-free. Rule 33 wants domain logic testable without a
## live scene, and a framework whose tests need a third-party addon installed
## before they run is one most contributors will never run.
##
## Test methods are named [code]test_*[/code] and are discovered by reflection.
## [method before_each] and [method after_each] bracket every one of them, with
## a fresh instance per method, so no test can leak state into the next.

var _failures: Array[String] = []
var _assertion_count: int = 0

## SceneTree the runner is executing in. Tests needing a live Node use
## [method add_test_node]; anything not touching the tree should leave it be.
var tree: SceneTree = null
## Parent for nodes created by the current test. Freed after each method.
var _node_root: Node = null


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Runner interface -----------------------------------------------------

func _begin_test(p_tree: SceneTree, p_node_root: Node) -> void:
	tree = p_tree
	_node_root = p_node_root
	_failures.clear()
	_assertion_count = 0


func get_failures() -> Array[String]:
	return _failures


func get_assertion_count() -> int:
	return _assertion_count


# --- Node helpers ---------------------------------------------------------

## Parents [param node] under the test's scratch root so it receives
## [method Node._ready], and frees it when the test method ends.
func add_test_node(node: Node) -> Node:
	if _node_root != null:
		_node_root.add_child(node)
	return node


## Instantiates an autoload script directly and puts it in the tree.
##
## This is the payoff for autoload scripts having no [code]class_name[/code]:
## Core and the EventBus can be built fresh per test instead of tests sharing
## one global whose state bleeds between them.
##
## [b]Note:[/b] the runner executes inside [method SceneTree._initialize], and
## Godot defers [method Node._ready] to the first process frame -- so the
## returned node's _ready() has [i]not[/i] run and will not run during the
## test. That is deliberate. Framework code must not depend on _ready() for
## wiring anything a caller can reach, and testing it in this state is how
## that stays true.
func make_autoload(script_path: String, node_name: String = "") -> Node:
	var script: GDScript = load(script_path)
	var node: Node = script.new()
	if not node_name.is_empty():
		node.name = node_name
	return add_test_node(node)


# --- Assertions -----------------------------------------------------------

func fail(message: String) -> void:
	_assertion_count += 1
	_failures.append(message)


func assert_true(condition: bool, message: String = "") -> void:
	_assertion_count += 1
	if not condition:
		_failures.append(_describe("Expected true", message))


func assert_false(condition: bool, message: String = "") -> void:
	_assertion_count += 1
	if condition:
		_failures.append(_describe("Expected false", message))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_assertion_count += 1
	if actual != expected:
		_failures.append(
			_describe("Expected %s but got %s" % [_show(expected), _show(actual)], message)
		)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	_assertion_count += 1
	if actual == unexpected:
		_failures.append(
			_describe("Expected anything but %s" % _show(unexpected), message)
		)


func assert_almost_eq(
	actual: float, expected: float, tolerance: float = 0.0001, message: String = ""
) -> void:
	_assertion_count += 1
	if absf(actual - expected) > tolerance:
		_failures.append(
			_describe("Expected %f (+/- %f) but got %f" % [expected, tolerance, actual], message)
		)


func assert_null(value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if value != null:
		_failures.append(_describe("Expected null but got %s" % _show(value), message))


func assert_not_null(value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if value == null:
		_failures.append(_describe("Expected a value but got null", message))


func assert_has(collection: Variant, value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if not _contains(collection, value):
		_failures.append(
			_describe("Expected %s to contain %s" % [_show(collection), _show(value)], message)
		)


func assert_has_not(collection: Variant, value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if _contains(collection, value):
		_failures.append(
			_describe(
				"Expected %s not to contain %s" % [_show(collection), _show(value)], message
			)
		)


func assert_empty(collection: Variant, message: String = "") -> void:
	_assertion_count += 1
	if _size_of(collection) != 0:
		_failures.append(_describe("Expected empty, got %s" % _show(collection), message))


func assert_size(collection: Variant, expected: int, message: String = "") -> void:
	_assertion_count += 1
	var actual := _size_of(collection)
	if actual != expected:
		_failures.append(
			_describe("Expected %d entries but found %d" % [expected, actual], message)
		)


## Asserts a [FrameworkResult] succeeded, reporting its failure code when not.
func assert_ok(result: FrameworkResult, message: String = "") -> void:
	_assertion_count += 1
	if result == null:
		_failures.append(_describe("Expected a FrameworkResult but got null", message))
	elif result.is_err():
		_failures.append(_describe("Expected ok but got %s" % str(result), message))


## Asserts a [FrameworkResult] failed, and optionally with a specific code.
func assert_err(
	result: FrameworkResult, expected_code: StringName = &"", message: String = ""
) -> void:
	_assertion_count += 1
	if result == null:
		_failures.append(_describe("Expected a FrameworkResult but got null", message))
		return
	if result.is_ok():
		_failures.append(_describe("Expected a failure but got ok", message))
		return
	if expected_code != &"" and result.code != expected_code:
		_failures.append(
			_describe(
				"Expected failure code '%s' but got '%s'" % [expected_code, result.code],
				message
			)
		)


# --- Internals ------------------------------------------------------------

func _describe(detail: String, message: String) -> String:
	return detail if message.is_empty() else "%s -- %s" % [message, detail]


func _contains(collection: Variant, value: Variant) -> bool:
	match typeof(collection):
		TYPE_DICTIONARY:
			return (collection as Dictionary).has(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(collection).contains(str(value))
		_:
			if collection is Array or collection is PackedStringArray:
				return collection.has(value)
	return false


func _size_of(collection: Variant) -> int:
	if collection == null:
		return 0
	match typeof(collection):
		TYPE_DICTIONARY:
			return (collection as Dictionary).size()
		TYPE_STRING, TYPE_STRING_NAME:
			return str(collection).length()
		_:
			if collection is Array or collection is PackedStringArray:
				return collection.size()
	return 0


func _show(value: Variant) -> String:
	if value == null:
		return "null"
	if value is String:
		return '"%s"' % value
	return str(value)
