extends Node
## Cross-feature fact channel. Autoloaded as [code]EventBus[/code].
##
## This script deliberately has no [code]class_name[/code]: a global class
## would collide with the autoload singleton of the same name. Tests preload
## the script and instantiate it directly.
##
## [b]What belongs here[/b] is narrow (rule 6). A fact goes on the bus only
## when the producer genuinely should not know its consumers -- something died,
## something was purchased, an objective advanced. A request aimed at a known
## target is a method call (rule 5), and a state change observed locally is a
## plain signal (rule 7). Routing everything through the bus rebuilds the
## global switchboard the architecture exists to avoid.
##
## [b]How signals get here.[/b] Core declares typed signals only for facts
## whose payload types Core already owns. Everything else is registered by the
## module that owns the fact, via [method register_event], so Commerce brings
## its own [code]item_purchased[/code] rather than Core carrying a signal for
## a module that may not be installed. The trade is deliberate: module events
## are reached through [method publish] and [method subscribe] instead of
## static signal access, which costs some compile-time checking and buys
## Core that stays tiny and modules that stay removable.

## Fires for every published event, whatever its name. This is the hook the
## debug event monitor subscribes to (Implementation Plan 29) so it can watch
## the whole bus without knowing which modules are installed.
##
## Always carries a [FrameworkEvent].
signal event_published(event)

## Fires when an actor's health reaches zero. Declared here because its payload
## is built from [DamageContext], which Core owns.
##
## Always carries an [ActorDiedEvent].
signal actor_died(event)

# NOTE: the two signals above deliberately leave their parameter untyped, and
# it is the one place this framework departs from rule 27.
#
# An object-typed signal parameter on an autoload script keeps that parameter's
# GDScript alive past the engine's resource sweep, and Godot 4.7.2 reports it
# on every exit:
#
#     WARNING: 3 ObjectDB instances were leaked at exit
#     ERROR: 2 resources still in use at exit
#
# Verified by bisection: untyping these two parameters removes it, and it
# reproduces on a normal game run, not just under the headless test harness.
# It costs nothing to give up, because GDScript does not check signal handler
# signatures at connect time anyway -- the annotation was documentation, and it
# still is, one line up.
#
# The invariant is enforced where it can actually be enforced: publish() takes
# a typed FrameworkEvent and is the only way anything reaches these signals.
#
# Builtin-typed parameters are unaffected. FrameworkCore's own
# module_registered(id: StringName) stays typed for exactly that reason.

## Event names registered by modules, tracked so [method publish] can tell
## "no module owns this fact" from "no one happens to be listening".
var _module_events: Dictionary[StringName, bool] = {}

## Set false to silence the warning when an event is published with no
## registered signal. Useful in tests that publish before modules register.
var warn_on_unregistered: bool = true


## Declares an event name a module owns. Idempotent, so a module that
## re-registers after a reload does not error.
##
## Handlers take one [FrameworkEvent] argument.
func register_event(event_name: StringName) -> FrameworkResult:
	if event_name == &"":
		return FrameworkResult.fail(
			&"event.invalid_name", "Cannot register an event with an empty name."
		)
	if has_signal(event_name):
		# Either already registered by this module, or shadowing a Core signal.
		_module_events[event_name] = true
		return FrameworkResult.ok(false)
	add_user_signal(event_name, [{"name": "event", "type": TYPE_OBJECT}])
	_module_events[event_name] = true
	return FrameworkResult.ok(true)


## Removes a module-registered event name. Core signals cannot be removed.
##
## Godot has no API to delete a user signal, so the name is dropped from the
## registry and its handlers disconnected; the signal itself remains but is
## inert. That is enough for module removal, since nothing is listening.
func unregister_event(event_name: StringName) -> bool:
	if not _module_events.has(event_name):
		return false
	if has_signal(event_name):
		for connection in get_signal_connection_list(event_name):
			disconnect(event_name, connection["callable"])
	return _module_events.erase(event_name)


func has_event(event_name: StringName) -> bool:
	return has_signal(event_name)


## Publishes [param event] on the signal named by its
## [method FrameworkEvent.get_event_name], then on [signal event_published].
##
## An event with no matching signal still reaches the firehose, so a module
## unregistering mid-flight degrades to "nobody heard it" rather than an error
## (rule 31).
func publish(event: FrameworkEvent) -> FrameworkResult:
	if event == null:
		return FrameworkResult.fail(&"event.null", "Cannot publish a null event.")

	var event_name := event.get_event_name()
	if event_name == &"":
		event_published.emit(event)
		return FrameworkResult.fail(
			&"event.unnamed",
			"Event %s returned an empty name from get_event_name()." % event.get_class()
		)

	var delivered := false
	if has_signal(event_name):
		emit_signal(event_name, event)
		delivered = true
	elif warn_on_unregistered:
		push_warning(
			"EventBus: published '%s' but no module has registered it." % event_name
		)

	event_published.emit(event)
	return FrameworkResult.ok(delivered)


## Connects [param handler] to [param event_name], registering the event first
## if no module has yet. Lets a subscriber bind before the producing module
## loads, which matters when load order is not guaranteed.
func subscribe(event_name: StringName, handler: Callable) -> FrameworkResult:
	if not handler.is_valid():
		return FrameworkResult.fail(
			&"event.invalid_handler", "Handler for '%s' is not callable." % event_name
		)
	if not has_signal(event_name):
		var registration := register_event(event_name)
		if registration.is_err():
			return registration
	if is_connected(event_name, handler):
		return FrameworkResult.ok(false)
	var error := connect(event_name, handler)
	if error != OK:
		return FrameworkResult.fail(
			&"event.connect_failed",
			"Could not connect handler to '%s' (error %d)." % [event_name, error]
		)
	return FrameworkResult.ok(true)


func unsubscribe(event_name: StringName, handler: Callable) -> bool:
	if not has_signal(event_name) or not is_connected(event_name, handler):
		return false
	disconnect(event_name, handler)
	return true


## Event names registered by modules. Core signals are not included.
func get_registered_event_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(_module_events.keys())
	return names


## Drops every module event registration and its handlers. Core signals and
## their listeners are untouched.
func reset_module_events() -> void:
	for event_name in get_registered_event_names():
		unregister_event(event_name)
	_module_events.clear()
