extends FrameworkEvent
## Event fixture that never overrides get_event_name(), so the bus has to
## handle a malformed event rather than assume every subclass is well-formed.
