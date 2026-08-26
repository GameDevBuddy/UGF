class_name FrameworkResult
extends RefCounted
## Stable outcome payload for framework operations that can legitimately fail.
##
## Returning a result instead of a bare bool is what makes rule 17 (atomic
## transactions) enforceable: an operation validates everything, and on failure
## reports [i]which[/i] check failed without having mutated anything. The
## machine-readable [member code] lets callers and tests branch on the reason
## while [member message] stays free to change.
##
## Use it for operations that fail for domain reasons -- a purchase, an equip,
## an interaction. Do not use it for simple queries.

var success: bool = false
## Machine-readable failure reason. Empty on success.
var code: StringName = &""
## Human-readable detail, for logs and debug UI. Never parse this.
var message: String = ""
## Optional operation-specific payload, e.g. the item instance that was added.
var payload: Variant = null


static func ok(p_payload: Variant = null) -> FrameworkResult:
	var result := FrameworkResult.new()
	result.success = true
	result.payload = p_payload
	return result


static func fail(p_code: StringName, p_message: String = "") -> FrameworkResult:
	var result := FrameworkResult.new()
	result.success = false
	result.code = p_code
	result.message = p_message
	return result


func is_ok() -> bool:
	return success


func is_err() -> bool:
	return not success


## True when this failed for the specific reason [param p_code].
func failed_with(p_code: StringName) -> bool:
	return not success and code == p_code


func _to_string() -> String:
	if success:
		return "FrameworkResult(ok)"
	if message.is_empty():
		return "FrameworkResult(fail: %s)" % code
	return "FrameworkResult(fail: %s - %s)" % [code, message]
