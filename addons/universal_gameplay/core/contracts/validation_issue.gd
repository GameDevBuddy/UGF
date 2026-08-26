class_name ValidationIssue
extends RefCounted
## A single diagnostic produced by validating a definition or module.
##
## Issues are transient diagnostics, not content, so this is a RefCounted
## rather than a Resource. Every issue carries a machine-readable [member code]
## for tests to assert against and a human-readable [member message] with a
## source path, because a validation error the author cannot locate is not
## much better than no validation at all (Implementation Plan 28).

enum Severity {
	INFO, ## Advisory only. Never fails validation.
	WARNING, ## Suspicious but loadable. Fails only under strict validation.
	ERROR, ## Broken. Always fails validation.
}

var severity: Severity = Severity.ERROR
var code: StringName = &""
var message: String = ""
## Resource path of the offending asset, blank when not applicable.
var source_path: String = ""
## Optional extra locator, e.g. the property name inside the definition.
var context: String = ""


static func make(
	p_severity: Severity,
	p_code: StringName,
	p_message: String,
	p_source_path: String = "",
	p_context: String = ""
) -> ValidationIssue:
	var issue := ValidationIssue.new()
	issue.severity = p_severity
	issue.code = p_code
	issue.message = p_message
	issue.source_path = p_source_path
	issue.context = p_context
	return issue


static func error(
	p_code: StringName, p_message: String, p_source_path: String = "", p_context: String = ""
) -> ValidationIssue:
	return make(Severity.ERROR, p_code, p_message, p_source_path, p_context)


static func warning(
	p_code: StringName, p_message: String, p_source_path: String = "", p_context: String = ""
) -> ValidationIssue:
	return make(Severity.WARNING, p_code, p_message, p_source_path, p_context)


static func info(
	p_code: StringName, p_message: String, p_source_path: String = "", p_context: String = ""
) -> ValidationIssue:
	return make(Severity.INFO, p_code, p_message, p_source_path, p_context)


static func severity_label(p_severity: Severity) -> String:
	match p_severity:
		Severity.INFO:
			return "INFO"
		Severity.WARNING:
			return "WARNING"
		_:
			return "ERROR"


func _to_string() -> String:
	var parts := PackedStringArray()
	parts.append("[%s]" % severity_label(severity))
	if code != &"":
		parts.append("(%s)" % code)
	parts.append(message)
	if context != "":
		parts.append("<%s>" % context)
	if source_path != "":
		parts.append("at %s" % source_path)
	return " ".join(parts)
