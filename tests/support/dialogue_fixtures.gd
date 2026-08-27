class_name DialogueFixtures
extends RefCounted
## Builders for the conversations the M8 suites need.
##
## Conversations are built in code rather than as [code].tres[/code] files
## because the addon ships no content of its own (rule 29), and because a
## conversation assembled in a test is one whose shape the test can state.


# --- Nodes ----------------------------------------------------------------

static func line(
	id: StringName, text: String, next: StringName = &""
) -> LineNode:
	var node := LineNode.new()
	node.id = id
	node.text = text
	node.next = next
	return node


static func choice(
	id: StringName, text: String, next: StringName = &""
) -> DialogueChoice:
	var option := DialogueChoice.new()
	option.id = id
	option.text = text
	option.next = next
	return option


static func choice_node(
	id: StringName, prompt: String, choices: Array
) -> ChoiceNode:
	var node := ChoiceNode.new()
	node.id = id
	node.prompt = prompt
	var typed: Array[DialogueChoice] = []
	typed.assign(choices)
	node.choices = typed
	return node


static func branch(
	id: StringName,
	conditions: Array,
	targets: Array,
	fallback: StringName = &""
) -> BranchNode:
	var node := BranchNode.new()
	node.id = id
	var typed_conditions: Array[DialogueCondition] = []
	typed_conditions.assign(conditions)
	node.branch_conditions = typed_conditions
	var typed_targets: Array[StringName] = []
	typed_targets.assign(targets)
	node.branch_targets = typed_targets
	node.fallback = fallback
	return node


static func ending(id: StringName, outcome: StringName = &"") -> EndNode:
	var node := EndNode.new()
	node.id = id
	node.outcome = outcome
	return node


## A node with no text: actions and a successor. What Implementation Plan 18
## calls an Action node and what this framework expresses as the base class.
static func action_node(
	id: StringName, actions: Array, next: StringName = &""
) -> DialogueNode:
	var node := DialogueNode.new()
	node.id = id
	var typed: Array[DialogueAction] = []
	typed.assign(actions)
	node.enter_actions = typed
	node.next = next
	return node


# --- Conditions and actions -----------------------------------------------

static func flag_is(flag: StringName, value: bool = true) -> NarrativeCondition:
	var condition := NarrativeCondition.new()
	condition.subject = NarrativeCondition.Subject.FLAG
	condition.key = flag
	condition.value = value
	return condition


static func counter_at_least(counter: StringName, amount: int) -> NarrativeCondition:
	var condition := NarrativeCondition.new()
	condition.subject = NarrativeCondition.Subject.COUNTER
	condition.key = counter
	condition.comparison = NarrativeCondition.Comparison.GREATER_OR_EQUAL
	condition.value = amount
	return condition


static func standing_at_least(
	subject: StringName, other: StringName, amount: float
) -> NarrativeCondition:
	var condition := NarrativeCondition.new()
	condition.subject = NarrativeCondition.Subject.RELATIONSHIP
	condition.key = subject
	condition.other = other
	condition.comparison = NarrativeCondition.Comparison.GREATER_OR_EQUAL
	condition.value = amount
	return condition


static func carries(item_id: StringName, quantity: int = 1) -> ItemCondition:
	var condition := ItemCondition.new()
	condition.item_id = item_id
	condition.quantity = quantity
	return condition


static func raise_flag(flag: StringName, value: bool = true) -> NarrativeAction:
	var action := NarrativeAction.new()
	action.operation = NarrativeAction.Operation.SET_FLAG
	action.key = flag
	action.value = value
	return action


static func bump(counter: StringName, amount: int = 1) -> NarrativeAction:
	var action := NarrativeAction.new()
	action.operation = NarrativeAction.Operation.INCREMENT_COUNTER
	action.key = counter
	action.value = amount
	return action


static func shift_standing(
	subject: StringName, other: StringName, amount: float
) -> NarrativeAction:
	var action := NarrativeAction.new()
	action.operation = NarrativeAction.Operation.MODIFY_RELATIONSHIP
	action.key = subject
	action.other = other
	action.value = amount
	return action


# --- Whole conversations --------------------------------------------------

static func definition(id: StringName, nodes: Array, start: StringName = &"") -> DialogueDefinition:
	var dialogue := DialogueDefinition.new()
	dialogue.id = id
	dialogue.display_name = str(id)
	var typed: Array[DialogueNode] = []
	typed.assign(nodes)
	dialogue.nodes = typed
	dialogue.start_node = start
	dialogue.default_speaker = &"speaker.npc"
	return dialogue


## Three lines and an end. The simplest conversation that is still a
## conversation.
static func linear() -> DialogueDefinition:
	return definition(
		&"dialogue.linear",
		[
			line(&"one", "Hello.", &"two"),
			line(&"two", "Nice weather.", &"three"),
			line(&"three", "Goodbye.", &"done"),
			ending(&"done", &"outcome.ended"),
		],
		&"one"
	)


## The conversation the exit gate is stated against: a question, three
## answers, two of them gated, and each ending somewhere different.
static func branching() -> DialogueDefinition:
	var accept := choice(&"choice.accept", "I'll do it.", &"accepted")
	accept.actions = _actions([raise_flag(&"flag.job_accepted"), bump(&"counter.jobs")])
	var tags: Array[StringName] = [&"choice.helpful"]
	accept.tags = tags

	var refuse := choice(&"choice.refuse", "Not interested.", &"refused")
	refuse.actions = _actions([shift_standing(&"faction.town", &"player", -10.0)])

	var bribe := choice(&"choice.bribe", "[Pay 50 gold]", &"accepted")
	bribe.conditions = _conditions([carries(&"item.gold", 50)])

	var boast := choice(&"choice.boast", "[Reputation] They know me here.", &"accepted")
	boast.conditions = _conditions([standing_at_least(&"faction.town", &"player", 20.0)])
	boast.show_when_unavailable = true
	boast.unavailable_text = "[Reputation] They don't know you well enough."

	return definition(
		&"dialogue.job",
		[
			line(&"greet", "There's a job going.", &"ask"),
			choice_node(&"ask", "Interested?", [accept, refuse, bribe, boast]),
			line(&"accepted", "Good. See the foreman.", &"end_yes"),
			line(&"refused", "Suit yourself.", &"end_no"),
			ending(&"end_yes", &"outcome.accepted"),
			ending(&"end_no", &"outcome.refused"),
		],
		&"greet"
	)


## A conversation whose first line depends on whether a flag is raised.
static func remembering() -> DialogueDefinition:
	return definition(
		&"dialogue.remembering",
		[
			branch(
				&"start",
				[flag_is(&"flag.met_before")],
				[&"again"],
				&"first_time"
			),
			line(&"first_time", "Do I know you?", &"remember"),
			action_node(&"remember", [raise_flag(&"flag.met_before")], &"finish"),
			line(&"again", "You again.", &"finish"),
			ending(&"finish"),
		],
		&"start"
	)


static func _conditions(entries: Array) -> Array[DialogueCondition]:
	var typed: Array[DialogueCondition] = []
	typed.assign(entries)
	return typed


static func _actions(entries: Array) -> Array[DialogueAction]:
	var typed: Array[DialogueAction] = []
	typed.assign(entries)
	return typed
