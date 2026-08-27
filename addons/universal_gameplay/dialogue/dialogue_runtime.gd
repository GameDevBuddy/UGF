class_name DialogueRuntime
extends RefCounted
## One conversation, in progress.
##
## A plain object rather than a node, so a whole branching conversation can be
## walked in a unit test with no scene, no UI and no NPC (rule 33). The
## component that hangs it off an NPC is a thin wrapper; this is where the
## conversation actually lives.
##
## [b]It presents nothing.[/b] It says which line is current and which options
## are open, and something else draws them. That is rule 21 -- presentation
## observes, it never owns -- and it is what lets the same conversation run in
## a subtitle bar, a full-screen menu, or a test.

## Emitted when the conversation begins.
signal started(context: DialogueContext)
## Emitted when a line is reached and is waiting to be read.
signal line_shown(node: LineNode, context: DialogueContext)
## Emitted when options are open and one must be picked.
signal choices_offered(node: ChoiceNode, choices: Array[DialogueChoice])
## Emitted when an option is taken, before its actions run.
signal choice_made(choice: DialogueChoice, context: DialogueContext)
## Emitted when the conversation ends, with the outcome of the End node it
## reached, or blank when it simply ran out.
signal finished(outcome: StringName, context: DialogueContext)

const MAX_STEPS_PER_ADVANCE: int = 256

var _definition: DialogueDefinition = null
var _context: DialogueContext = null
var _current: DialogueNode = null
var _running: bool = false
var _outcome: StringName = &""
var _visited: Dictionary[StringName, int] = {}


func get_definition() -> DialogueDefinition:
	return _definition


func get_context() -> DialogueContext:
	return _context


func is_running() -> bool:
	return _running


## The node the conversation is sitting on, or null when it is not running.
func get_current_node() -> DialogueNode:
	return _current


## The line waiting to be read, or null when the conversation is on a choice
## or is not running.
func get_current_line() -> LineNode:
	return _current as LineNode


## The options open right now. Empty unless the conversation is on a choice.
func get_choices() -> Array[DialogueChoice]:
	var node := _current as ChoiceNode
	if node == null:
		var empty: Array[DialogueChoice] = []
		return empty
	return node.get_visible_choices(_context)


func is_awaiting_choice() -> bool:
	return _current is ChoiceNode


## How this conversation ended, or blank while it is running.
func get_outcome() -> StringName:
	return _outcome


## How many times a node has been entered this conversation. What a "you have
## asked me that already" line branches on.
func times_visited(node_id: StringName) -> int:
	return _visited.get(node_id, 0)


## Who is speaking the current line, falling back to the conversation's own
## default. Presentation asks this rather than reading the node.
func get_current_speaker() -> StringName:
	if _current is LineNode and (_current as LineNode).speaker != &"":
		return (_current as LineNode).speaker
	if _current is ChoiceNode and (_current as ChoiceNode).speaker != &"":
		return (_current as ChoiceNode).speaker
	return _definition.default_speaker if _definition != null else &""


# --- Running --------------------------------------------------------------

## Begins the conversation and advances to the first thing worth showing.
func start(
	definition: DialogueDefinition, context: DialogueContext
) -> FrameworkResult:
	if _running:
		return FrameworkResult.fail(
			&"dialogue.already_running", "This conversation is already running."
		)
	if definition == null:
		return FrameworkResult.fail(
			&"dialogue.no_definition", "There is no conversation to start."
		)
	if context == null:
		return FrameworkResult.fail(
			&"dialogue.no_context", "A conversation needs a context."
		)

	var start_node := definition.get_start_node()
	if start_node == null:
		return FrameworkResult.fail(
			&"dialogue.no_start_node",
			"%s has no start node." % definition.get_debug_name()
		)

	_definition = definition
	_context = context
	_context.definition = definition
	_context.set_runtime(self)
	_running = true
	_outcome = &""
	_visited.clear()

	DialogueAction.run_all(definition.start_actions, _context)
	started.emit(_context)
	_goto(start_node.id)
	return FrameworkResult.ok(_current)


## Moves past the current line. What a "continue" press calls.
##
## Refused while a choice is open: advancing past an unanswered question is
## how a conversation silently skips the branch the player was about to take.
func advance() -> FrameworkResult:
	if not _running:
		return FrameworkResult.fail(&"dialogue.not_running", "Nothing is being said.")
	if is_awaiting_choice():
		return FrameworkResult.fail(
			&"dialogue.awaiting_choice", "A choice is open and must be answered."
		)
	if _current == null:
		return _finish(&"")
	_goto(_current.get_next(_context))
	return FrameworkResult.ok(_current)


## Takes an option by its position in [method get_choices].
func choose(index: int) -> FrameworkResult:
	var visible := get_choices()
	if index < 0 or index >= visible.size():
		return FrameworkResult.fail(
			&"dialogue.no_such_choice", "There is no option %d." % index
		)
	return choose_option(visible[index])


## Takes an option by id, which is what an event-driven caller has.
func choose_id(choice_id: StringName) -> FrameworkResult:
	var node := _current as ChoiceNode
	if node == null:
		return FrameworkResult.fail(
			&"dialogue.not_awaiting_choice", "No options are open."
		)
	var choice := node.find_choice(choice_id)
	if choice == null:
		return FrameworkResult.fail(
			&"dialogue.no_such_choice", "There is no option '%s'." % choice_id
		)
	return choose_option(choice)


## Takes a specific option.
##
## An option shown but unavailable is refused here rather than being hidden
## earlier, which is what lets "[Locked] Persuade" appear and do nothing when
## clicked instead of vanishing.
func choose_option(choice: DialogueChoice) -> FrameworkResult:
	if not _running:
		return FrameworkResult.fail(&"dialogue.not_running", "Nothing is being said.")
	var node := _current as ChoiceNode
	if node == null:
		return FrameworkResult.fail(
			&"dialogue.not_awaiting_choice", "No options are open."
		)
	if choice == null or not node.choices.has(choice):
		return FrameworkResult.fail(
			&"dialogue.no_such_choice", "That option is not on offer."
		)
	if not choice.is_available(_context):
		return FrameworkResult.fail(
			&"dialogue.choice_unavailable", "That option cannot be taken."
		)

	choice_made.emit(choice, _context)
	DialogueAction.run_all(choice.actions, _context)
	_goto(choice.next)
	return FrameworkResult.ok(choice)


## Ends the conversation early: the player walked away, the NPC was killed, a
## cutscene took over. End actions still run, because leaving a conversation
## half-applied is worse than finishing it.
func stop(outcome: StringName = &"aborted") -> FrameworkResult:
	if not _running:
		return FrameworkResult.fail(&"dialogue.not_running", "Nothing is being said.")
	return _finish(outcome)


# --- Internals ------------------------------------------------------------

## Walks from a node id to the next thing that needs a human.
##
## Nodes that neither wait nor end -- an actions-only node, a branch -- are
## stepped straight through, so a conversation never sits on something with
## nothing to show. The step cap is the guard against a content loop with no
## line in it, which would otherwise hang the game rather than the conversation.
func _goto(node_id: StringName) -> void:
	var steps := 0
	var target := node_id
	while _running:
		steps += 1
		if steps > MAX_STEPS_PER_ADVANCE:
			push_warning(
				(
					"DialogueRuntime: %s looped %d nodes without reaching a line; "
					+ "ending it rather than hanging."
				) % [_definition.get_debug_name(), MAX_STEPS_PER_ADVANCE]
			)
			_finish(&"looped")
			return
		if target == &"":
			_finish(&"")
			return

		var node := _definition.find_node(target)
		if node == null:
			# A dangling jump is content that is wrong. Validation reports it
			# before the build ships; at runtime the conversation ends rather
			# than the game stopping.
			push_warning(
				"DialogueRuntime: %s jumps to '%s', which does not exist." % [
					_definition.get_debug_name(), target
				]
			)
			_finish(&"broken")
			return

		if not node.is_available(_context):
			target = node.get_next(_context)
			continue

		_current = node
		_visited[node.id] = times_visited(node.id) + 1
		DialogueAction.run_all(node.enter_actions, _context)

		if node.is_terminal():
			_finish((node as EndNode).outcome)
			return
		if node.waits_for_input():
			_announce(node)
			return
		target = node.get_next(_context)


func _announce(node: DialogueNode) -> void:
	if node is LineNode:
		line_shown.emit(node as LineNode, _context)
	elif node is ChoiceNode:
		choices_offered.emit(node as ChoiceNode, get_choices())


func _finish(outcome: StringName) -> FrameworkResult:
	_outcome = outcome
	_running = false
	_current = null
	if _definition != null and _context != null:
		DialogueAction.run_all(_definition.end_actions, _context)
	finished.emit(_outcome, _context)
	if _context != null:
		# Conversation-scoped values do not outlive the conversation. Leaving
		# them would make the next one start with the last one's answers.
		_context.locals.clear()
	return FrameworkResult.ok(_outcome)
