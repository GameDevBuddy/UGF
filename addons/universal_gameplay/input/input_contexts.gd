class_name InputContexts
extends RefCounted
## The six standard input contexts from Implementation Plan 24.
##
## These are framework vocabulary, not game content: every genre this platform
## targets has an on-foot context and a "something modal is open" context, and
## naming them once stops six projects inventing six spellings of the same
## idea. A project is free to author its own [InputContext] resources instead
## or as well; nothing here is privileged.
##
## Static builders rather than preloaded [code].tres[/code] files, because the
## addon ships no content of its own (rule 29) and a resource on disk would be
## content a project could accidentally edit for everyone.

## Walking around: the full movement action set.
static func on_foot() -> InputContext:
	return InputContext.create(
		GameplayNames.INPUT_CONTEXT_ON_FOOT,
		[
			GameplayNames.ACTION_MOVE_LEFT,
			GameplayNames.ACTION_MOVE_RIGHT,
			GameplayNames.ACTION_MOVE_FORWARD,
			GameplayNames.ACTION_MOVE_BACK,
			GameplayNames.ACTION_JUMP,
			GameplayNames.ACTION_SPRINT,
			GameplayNames.ACTION_CROUCH,
			GameplayNames.ACTION_INTERACT,
		]
	)


## Driving. The movement actions are deliberately the same names: a vehicle
## controller reads throttle and steering from the same semantic axes the
## character reads walking from, so possession swaps the listener rather than
## the vocabulary (Implementation Plan 22).
static func vehicle_driver() -> InputContext:
	return InputContext.create(
		GameplayNames.INPUT_CONTEXT_VEHICLE_DRIVER,
		[
			GameplayNames.ACTION_MOVE_LEFT,
			GameplayNames.ACTION_MOVE_RIGHT,
			GameplayNames.ACTION_MOVE_FORWARD,
			GameplayNames.ACTION_MOVE_BACK,
			GameplayNames.ACTION_JUMP,
			GameplayNames.ACTION_INTERACT,
		]
	)


## Riding along: you may get out, and nothing else.
static func vehicle_passenger() -> InputContext:
	return InputContext.create(
		GameplayNames.INPUT_CONTEXT_VEHICLE_PASSENGER,
		[GameplayNames.ACTION_INTERACT]
	)


## A menu is open. Modal, and gameplay control is released.
static func ui() -> InputContext:
	return InputContext.create(GameplayNames.INPUT_CONTEXT_UI, [], true, true)


## A conversation is running. Interact advances it; nothing else gets through.
static func dialogue() -> InputContext:
	return InputContext.create(
		GameplayNames.INPUT_CONTEXT_DIALOGUE,
		[GameplayNames.ACTION_INTERACT],
		true,
		true
	)


## Cutscene, loading, death -- input is off entirely.
static func disabled() -> InputContext:
	return InputContext.create(GameplayNames.INPUT_CONTEXT_DISABLED, [], true, true)


## Every standard context, for a project that wants to register them all.
static func all() -> Array[InputContext]:
	return [
		on_foot(),
		vehicle_driver(),
		vehicle_passenger(),
		ui(),
		dialogue(),
		disabled(),
	] as Array[InputContext]
