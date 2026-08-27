class_name WantedTier
extends Resource
## One rung of the wanted ladder: unnoticed, suspected, wanted, hunted.
##
## The tier is what law AI actually reacts to. It is a semantic state rather
## than a number, so a guard's brain asks "is this one wanted?" and never
## "is their heat above 74?" — which is what lets a project retune the numbers
## without touching a single behaviour (rule 32).

## Heat at or above which this tier applies.
@export_range(0.0, 100000.0, 1.0, "or_greater") var threshold: float = 0.0

@export var display_name: String = ""

## Semantic state set on the offender while at this tier:
## [code]state.wanted[/code]. This is the whole interface to law AI.
@export var state: StringName = &""

@export_group("Response")
## How hard the law looks. What a spawner turns into patrol density and a
## brain turns into search radius; the framework only carries the number.
@export_range(0.0, 100.0, 0.1, "or_greater") var response_strength: float = 0.0

## Whether the law attacks on sight at this tier, as opposed to approaching
## to arrest.
@export var lethal_response: bool = false

## Seconds of heat decay suppressed after the last crime at this tier, so a
## murderer cannot cool off by standing still for four seconds.
@export_range(0.0, 3600.0, 0.1, "or_greater") var cooldown_delay: float = 10.0


func get_debug_name() -> String:
	if not display_name.is_empty():
		return display_name
	return str(state) if state != &"" else "<unnamed tier>"


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if state == &"" and threshold > 0.0:
		result.add_warning(
			&"tier.no_state",
			(
				"%s sets no semantic state, so no AI can react to it."
			) % get_debug_name(),
			resource_path,
			"state"
		)
	return result
