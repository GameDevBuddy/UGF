extends FrameworkDefinition
## Stand-in definition type used by the test suite.
##
## No class_name: test fixtures are preloaded, so they stay out of the
## project's global class namespace.

@export var power: float = 1.0
@export var linked_ids: Array[StringName] = []


func validate() -> ValidationResult:
	var result := super()
	if power <= 0.0:
		result.add_error(
			&"sample.invalid_power",
			"power must be greater than zero, got %f." % power,
			resource_path,
			"power"
		)
	return result
