class_name ValidationResult
extends RefCounted
## Accumulates [ValidationIssue]s produced while validating content.
##
## A result is valid when it holds no ERROR issues. Under strict validation
## warnings are promoted to failures, which lets a project ship with warnings
## during development and gate them in CI.

var issues: Array[ValidationIssue] = []


func add(issue: ValidationIssue) -> void:
	if issue != null:
		issues.append(issue)


func add_error(
	code: StringName, message: String, source_path: String = "", context: String = ""
) -> void:
	add(ValidationIssue.error(code, message, source_path, context))


func add_warning(
	code: StringName, message: String, source_path: String = "", context: String = ""
) -> void:
	add(ValidationIssue.warning(code, message, source_path, context))


func add_info(
	code: StringName, message: String, source_path: String = "", context: String = ""
) -> void:
	add(ValidationIssue.info(code, message, source_path, context))


## Absorbs every issue from [param other]. Used to roll subresource and
## per-definition results up into one report.
func merge(other: ValidationResult) -> void:
	if other == null:
		return
	issues.append_array(other.issues)


func count_of(severity: ValidationIssue.Severity) -> int:
	var total := 0
	for issue in issues:
		if issue.severity == severity:
			total += 1
	return total


func get_errors() -> Array[ValidationIssue]:
	return issues.filter(
		func(issue: ValidationIssue) -> bool:
			return issue.severity == ValidationIssue.Severity.ERROR
	)


func get_warnings() -> Array[ValidationIssue]:
	return issues.filter(
		func(issue: ValidationIssue) -> bool:
			return issue.severity == ValidationIssue.Severity.WARNING
	)


func has_errors() -> bool:
	return count_of(ValidationIssue.Severity.ERROR) > 0


func has_warnings() -> bool:
	return count_of(ValidationIssue.Severity.WARNING) > 0


## [param strict] promotes warnings to failures.
func is_valid(strict: bool = false) -> bool:
	if has_errors():
		return false
	return not (strict and has_warnings())


func is_empty() -> bool:
	return issues.is_empty()


func format_report() -> String:
	if issues.is_empty():
		return "No validation issues."
	var lines := PackedStringArray()
	for issue in issues:
		lines.append("  " + str(issue))
	var summary := "%d error(s), %d warning(s), %d info" % [
		count_of(ValidationIssue.Severity.ERROR),
		count_of(ValidationIssue.Severity.WARNING),
		count_of(ValidationIssue.Severity.INFO),
	]
	return summary + "\n" + "\n".join(lines)
