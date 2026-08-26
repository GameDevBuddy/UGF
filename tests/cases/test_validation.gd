extends FrameworkTestCase
## Covers ValidationIssue and ValidationResult.


func test_result_is_valid_when_empty() -> void:
	var result := ValidationResult.new()
	assert_true(result.is_valid(), "An empty result is valid")
	assert_true(result.is_empty())
	assert_false(result.has_errors())


func test_errors_invalidate_result() -> void:
	var result := ValidationResult.new()
	result.add_error(&"test.broken", "Something is broken.")
	assert_false(result.is_valid())
	assert_true(result.has_errors())
	assert_size(result.get_errors(), 1)


func test_warnings_only_fail_under_strict() -> void:
	var result := ValidationResult.new()
	result.add_warning(&"test.suspicious", "Something is odd.")
	assert_true(result.is_valid(), "Warnings pass by default")
	assert_false(result.is_valid(true), "Warnings fail under strict validation")


func test_info_never_fails() -> void:
	var result := ValidationResult.new()
	result.add_info(&"test.note", "Just so you know.")
	assert_true(result.is_valid())
	assert_true(result.is_valid(true), "Info passes even under strict validation")


func test_merge_absorbs_issues() -> void:
	var first := ValidationResult.new()
	first.add_error(&"test.a", "A")
	var second := ValidationResult.new()
	second.add_warning(&"test.b", "B")
	first.merge(second)
	assert_size(first.issues, 2)
	assert_true(first.has_errors())
	assert_true(first.has_warnings())


func test_merge_tolerates_null() -> void:
	var result := ValidationResult.new()
	result.merge(null)
	assert_true(result.is_empty(), "Merging null leaves the result untouched")


func test_counts_by_severity() -> void:
	var result := ValidationResult.new()
	result.add_error(&"a", "a")
	result.add_error(&"b", "b")
	result.add_warning(&"c", "c")
	assert_eq(result.count_of(ValidationIssue.Severity.ERROR), 2)
	assert_eq(result.count_of(ValidationIssue.Severity.WARNING), 1)
	assert_eq(result.count_of(ValidationIssue.Severity.INFO), 0)


func test_issue_reports_source_and_code() -> void:
	var issue := ValidationIssue.error(
		&"test.code", "Broken.", "res://content/thing.tres", "some_property"
	)
	var text := str(issue)
	assert_has(text, "ERROR")
	assert_has(text, "test.code")
	assert_has(text, "res://content/thing.tres")
	assert_has(text, "some_property")


func test_report_summarises_counts() -> void:
	var result := ValidationResult.new()
	result.add_error(&"a", "a")
	result.add_warning(&"b", "b")
	var report := result.format_report()
	assert_has(report, "1 error(s)")
	assert_has(report, "1 warning(s)")
