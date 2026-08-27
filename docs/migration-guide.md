# Migration guide

Two version numbers move independently in this framework, and confusing them
is the most expensive mistake available.

| Number | Where | Moves when |
| --- | --- | --- |
| Framework version | `FrameworkVersion.MAJOR/MINOR/PATCH`, `plugin.cfg` | Any release |
| Save schema | `FrameworkVersion.SAVE_SCHEMA` | The *shape* of persisted data changes |

The current framework version is **0.1.0** and the current save schema is
**1**.

Adding an optional field to a definition is a framework MINOR bump and leaves
the save schema alone: an old save loads, the new field takes its default, and
nothing needs migrating. Renaming a persisted key, changing what a value
means, or removing one is a save schema bump, and a save schema bump without a
registered migration is a shipped game that cannot load its own saves.

## Upgrading the addon

1. Replace `addons/universal_gameplay/` wholesale. Nothing in it is meant to
   be edited — if you have edited it, see *Replacing a module* below, which is
   the supported way to do what you were doing.
2. Re-enable the plugin if the editor turned it off. It re-adds the
   `EventBus` and `FrameworkCore` autoloads and registers any new default
   input actions, and it never overwrites an action you have rebound.
3. Run your project once and read the bootstrap report. `FrameworkCore`
   returns a `ValidationResult` from `bootstrap()` and stores it on
   `get_bootstrap_result()`; every content problem an upgrade introduced is in
   there, named, with the file path.
4. If `FrameworkVersion.SAVE_SCHEMA` went up, register the migrations for the
   steps you crossed before loading any existing save. See below.

Nothing about an upgrade is silent. A module that is no longer shipped fails
to resolve with its id named; a definition field that changed shape fails
validation with the resource path; a save from an older schema is refused by
`MigrationRegistry` unless a path to the current schema exists.

## The save file format changed once, before 1.0

`FileSaveBackend` used to write a save as a bare `store_var` with Godot's
`allow_objects` flag switched on, and read it back the same way. That flag
lets a save file decide which classes the game instantiates, and a decoded
object can carry a script that runs — so a save, which lives in a directory
the player can write and gets synced between machines, was a path to code
execution.

Saves are now written inside a small envelope carrying a format version, a
checksum and the payload, and objects are never decoded on the way in.

**Saves written before that change cannot be loaded.** There is no migration,
and this is the one place the framework refuses to provide one: reading an old
save means decoding it the old way, which is the vulnerability. A file with no
envelope reads as damaged, because there is no way to tell it apart from one
that is.

This is a container change, not a content change, so `SAVE_SCHEMA` does not
move and no `SaveMigration` is involved. It only matters if you shipped a
build on an earlier commit; if you are adopting the framework now, there is
nothing to do.

## Save schema migrations

`MigrationRegistry` holds one step per version transition — 1→2, 2→3 — and
walks them in order. It never jumps: a save at schema 1 in a game at schema 3
runs both steps, in sequence, and if the 2→3 step is missing the load is
refused rather than half-applied.

A migration is a `SaveMigration` subclass, so it is a Resource a project can
author, inspect and validate like anything else:

```gdscript
# res://game/migrations/wallet_migration.gd
class_name WalletMigration
extends SaveMigration


func _init() -> void:
    from_version = 1
    to_version = 2
    description = "Moves the loose gold count into the wallet's currency map."


func migrate(data: Dictionary) -> Dictionary:
    # A new dictionary, never an edit in place.
    var updated := data.duplicate(true)
    updated["wallet"] = {"currency.gold": data.get("gold", 0)}
    updated.erase("gold")
    return updated
```

```gdscript
var migrations := MigrationRegistry.new()
migrations.register(WalletMigration.new())
save_service.configure(backend, definition_registry, migrations)
```

Three rules the registry enforces, so that a bad migration fails loudly:

- **`can_migrate` is checked before anything is touched.** A save that cannot
  reach the current schema is refused whole; there is no partially-migrated
  state to debug.
- **A step never mutates its input.** Return a new dictionary. A step that
  edits in place and then fails leaves the caller holding damaged data.
- **Steps are single transitions.** `register()` refuses a migration whose
  `to_version` is not `from_version + 1`, because a step that skips a version
  leaves a hole nothing can cross — and the alternative rots: every new schema
  would need a migration from every older one.

### Schema 1

The current schema, and the first one. Nothing to migrate from yet.

Saves are written by `SaveService` walking the registered services and
persistent entities and asking each for `capture_state()`. What that means in
practice: the schema is the union of what every enabled module chooses to
persist, so a project that enables a new module gets new keys in its next save
and old saves simply lack them. That is not a schema change and needs no
migration — a module restoring from an absent key gets its defaults, which is
the same state a fresh game starts in.

## Replacing a module with your own

The supported way to change a module's behaviour is to not enable it and
register your own in its place.

```gdscript
# In your settings resource, leave module.commerce switched off.
# Then, once, at startup:
FrameworkCore.register_module(MyCommerceModule.new())
```

Your module declares the same id in its `ModuleManifest`, so every other
module's `requires` and `optional` list is satisfied by it, and
`has_feature(&"module.commerce")` is true for anything that asks. Set
`FrameworkSettings.register_enabled_modules` to `false` if you want to control
the whole registration order yourself; otherwise enable everything else
normally and register only your replacement by hand.

What you must not do is edit the addon in place. The next upgrade overwrites
it, and the edit is gone with no diff to tell you what you lost.

## When a module you relied on is not there

Every module is removable, so every integration between two modules is written
to work with the other one absent. If you are writing code against the
framework, branch on `FrameworkCore.has_feature()` and not on
`is_module_enabled()`:

```gdscript
# What actually came up.
if core.has_feature(&"module.factions"):
    ...

# What the project asked for, which says nothing about whether it worked.
if core.is_module_enabled(&"module.factions"):
    ...
```

A module can be enabled and still absent — its dependencies did not resolve,
or its registration failed — and the whole point of the distinction is that
the second question has the wrong answer in exactly the case that matters.

## Deprecations

None yet. When there are, this is where they will be listed, with the version
that deprecated the thing, the version that will remove it, and what to use
instead. A deprecated symbol keeps working for at least one MINOR release
after it is announced.
