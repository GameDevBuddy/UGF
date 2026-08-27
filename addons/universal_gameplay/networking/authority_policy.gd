class_name AuthorityPolicy
extends Resource
## Which commands the server decides, and which a client may just do.
##
## [b]Both lists matter.[/b] Implementation Plan 27 names inventory, commerce,
## combat results and mission progression as authority-owned — those are the
## ones a client must not be trusted with. But routing *everything* through the
## server is how a game comes to feel like it is being played over a telephone:
## looking around, opening a menu and drawing a HUD are nobody's business but
## the client's, and a policy that made them round-trip would be correct and
## unplayable.
##
## Data, so a project can move the line without editing the framework
## (rule 11).

## Verbs only the server may execute. A client asking sends a request; a client
## executing locally is refused.
@export var authoritative_verbs: Array[StringName] = []

## Verb prefixes that are authoritative, so a module's whole command surface is
## one entry: [code]inventory.[/code] covers add, remove and transfer.
@export var authoritative_prefixes: Array[StringName] = []

## Verbs any peer may run locally regardless of the prefixes above. The escape
## hatch for the one cheap call inside an expensive namespace.
@export var local_verbs: Array[StringName] = []

## What an unlisted verb counts as.
##
## [b]Defaults to local, deliberately.[/b] The alternative — everything is
## authoritative unless allowed — is safer on paper and wrong in practice for a
## framework: a project installing networking would find every unlisted call
## silently stop working, including presentation, and would conclude the
## networking module is broken rather than that it is strict.
@export var unlisted_is_authoritative: bool = false


func is_authoritative(verb: StringName) -> bool:
	if local_verbs.has(verb):
		return false
	if authoritative_verbs.has(verb):
		return true
	for prefix in authoritative_prefixes:
		if String(verb).begins_with(String(prefix)):
			return true
	return unlisted_is_authoritative


func is_local(verb: StringName) -> bool:
	return not is_authoritative(verb)


## The policy Implementation Plan 27 describes: inventory, commerce, combat
## results and mission progression are the server's, everything else is not.
##
## A starting point rather than a rule. A project's own is expected, and the
## point of shipping this one is that "what should be authoritative?" has a
## defensible answer to argue with rather than a blank field.
static func standard() -> AuthorityPolicy:
	var policy := AuthorityPolicy.new()
	var prefixes: Array[StringName] = [
		&"inventory.", &"commerce.", &"combat.", &"mission.", &"crime.",
		&"crafting.", &"equipment.",
	]
	policy.authoritative_prefixes = prefixes
	return policy


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if authoritative_verbs.is_empty() and authoritative_prefixes.is_empty():
		if not unlisted_is_authoritative:
			result.add_warning(
				&"authority.nothing_owned",
				(
					"This policy makes nothing authoritative, so every client "
					+ "decides everything for itself."
				),
				resource_path,
				"authoritative_prefixes"
			)
	for verb in local_verbs:
		if authoritative_verbs.has(verb):
			result.add_error(
				&"authority.contradiction",
				"'%s' is listed as both local and authoritative." % verb,
				resource_path,
				"local_verbs"
			)
	return result
