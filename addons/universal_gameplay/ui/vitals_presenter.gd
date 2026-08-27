class_name VitalsPresenter
extends Presenter
## Publishes health, needs and status effects as one snapshot.
##
## Every component it watches is optional. A creature with health and no needs,
## a machine with needs and no health, and a crate with neither are all valid
## subjects (rule 31) — the model simply says what is present and a widget
## hides the rest.

## Watched. Found among this entity's own components when not wired.
@export var health: HealthComponent

@export var needs: NeedsComponent

@export var effects: StatusEffectComponent


func observe() -> void:
	if health == null:
		health = _find(HealthComponent) as HealthComponent
	if needs == null:
		needs = _find(NeedsComponent) as NeedsComponent
	if effects == null:
		effects = _find(StatusEffectComponent) as StatusEffectComponent

	_watch(health, &"health_changed", _on_changed)
	_watch(health, &"died", _on_changed)
	_watch(health, &"revived", _on_refresh)
	_watch(needs, &"need_changed", _on_need)
	_watch(needs, &"need_critical", _on_critical)
	_watch(effects, &"effect_applied", _on_effect)
	_watch(effects, &"effect_removed", _on_effect_removed)


func stop_observing() -> void:
	_unwatch(health, &"health_changed", _on_changed)
	_unwatch(health, &"died", _on_changed)
	_unwatch(health, &"revived", _on_refresh)
	_unwatch(needs, &"need_changed", _on_need)
	_unwatch(needs, &"need_critical", _on_critical)
	_unwatch(effects, &"effect_applied", _on_effect)
	_unwatch(effects, &"effect_removed", _on_effect_removed)


func build() -> ViewModel:
	var model := VitalsViewModel.new()
	model.present = health != null or needs != null or effects != null

	if health != null:
		model.has_health = true
		model.health = health.get_current()
		model.maximum_health = health.get_maximum()
		model.health_fraction = health.get_fraction()
		model.alive = health.is_alive()

	if needs != null:
		for need in needs.get_need_ids():
			model.need_fractions[need] = needs.get_fraction(need)
		model.critical_needs = needs.get_critical_needs()

	if effects != null:
		model.effects = effects.get_effect_ids()
	return model


# --- Internals ------------------------------------------------------------
#
# Every handler discards its arguments and rebuilds. Rebuilding the whole
# snapshot rather than patching one field is what stops a model drifting out
# of step with the world it describes -- and at HUD rates the cost is nothing.

func _on_changed(_a: Variant = null, _b: Variant = null) -> void:
	refresh()


func _on_refresh() -> void:
	refresh()


func _on_need(_need: StringName, _value: float, _previous: float) -> void:
	refresh()


func _on_critical(_need: StringName, _critical: bool) -> void:
	refresh()


func _on_effect(_instance: StatusEffectInstance) -> void:
	refresh()


func _on_effect_removed(_id: StringName, _expired: bool) -> void:
	refresh()
