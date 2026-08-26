extends SceneTree
## Headless test entry point.
##
##     godot --headless --path . --script tests/run_tests.gd
##
## Exits non-zero when anything fails, so CI can gate on it directly.

const TEST_DIRECTORY: String = "res://tests/cases"


func _initialize() -> void:
	var runner := FrameworkTestRunner.new(self)
	runner.run_directory(TEST_DIRECTORY)
	runner.print_report()
	var success := runner.is_successful()
	runner.cleanup()
	quit(0 if success else 1)
