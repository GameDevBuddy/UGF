class_name BenchmarkHarness
extends RefCounted
## Times an operation, and compares how its cost grows with the size of what
## it operates on.
##
## [b]Wall-clock numbers are reported, never asserted.[/b] A CI runner shares
## a machine with whatever else is on it, so "this took under 3ms" is a test
## that fails on a busy afternoon and passes on a quiet one. A test that fails
## for reasons unrelated to the change gets muted, and a muted test guards
## nothing.
##
## What [i]is[/i] asserted is the shape of the curve. If a lookup is constant
## time, doing it against a hundred times more data costs about the same; if
## somebody replaces the index with a loop, it costs a hundred times more.
## Noise moves a measurement by a factor of two on a bad day. It does not move
## it by a factor of a hundred, which is why [method assert_flat] can use a
## tolerance loose enough to never fire by accident and still catch the only
## regression it is looking for.

## One timing run.
class Sample:
	extends RefCounted
	var label: String = ""
	var iterations: int = 0
	## Total microseconds across every iteration.
	var total_usec: int = 0

	func per_call_usec() -> float:
		return float(total_usec) / float(maxi(iterations, 1))

	func calls_per_second() -> float:
		var per_call := per_call_usec()
		return 1_000_000.0 / per_call if per_call > 0.0 else INF

	func describe() -> String:
		return (
			"%-46s %8d iterations  %9.3f us/call  %12s calls/sec"
			% [label, iterations, per_call_usec(), _thousands(calls_per_second())]
		)

	static func _thousands(value: float) -> String:
		if value == INF:
			return "inf"
		var text := "%d" % int(value)
		var out := ""
		var count := 0
		for index in range(text.length() - 1, -1, -1):
			out = text[index] + out
			count += 1
			if count % 3 == 0 and index > 0:
				out = "," + out
		return out


## Runs [param body] [param iterations] times and reports how long it took.
##
## A warm-up pass runs first and is thrown away. The first call into a
## GDScript method pays for lookups and allocations that no later call pays
## again, and including it would make a fast operation measured 20 times look
## slower than the same operation measured 20,000 times.
static func measure(label: String, iterations: int, body: Callable) -> Sample:
	for _warm in mini(iterations, 32):
		body.call()

	var started := Time.get_ticks_usec()
	for _index in iterations:
		body.call()
	var elapsed := Time.get_ticks_usec() - started

	var sample := Sample.new()
	sample.label = label
	sample.iterations = iterations
	sample.total_usec = elapsed
	return sample


## How much more each call costs against the larger data set.
##
## 1.0 means the size made no difference. Anything near the size ratio itself
## means the operation is walking the data.
static func growth(small: Sample, large: Sample) -> float:
	var baseline := small.per_call_usec()
	if baseline <= 0.0:
		# Too fast for the clock, which is itself a pass for a constant-time
		# operation: it cannot have walked a large collection in under a
		# microsecond.
		return 1.0
	return large.per_call_usec() / baseline


## Prints a block of samples under a heading, for the CI log.
static func report(heading: String, samples: Array) -> void:
	print("")
	print("  %s" % heading)
	print("  %s" % "-".repeat(len(heading)))
	for sample in samples:
		print("  %s" % (sample as Sample).describe())
