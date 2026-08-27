# Universal Gameplay Framework

A reusable, data-driven gameplay platform for **Godot 4.7**.

Scenes compose entities. Typed `Resource` definitions carry content. Signals
handle local communication and a narrow event bus carries cross-feature facts.
Thirty-one feature modules — character, combat, AI, dialogue, missions,
factions, commerce, crafting, survival, vehicles, spawning, crime, saves, UI
and networking — and every one of them is optional and removable.

## Install

1. Copy this folder into your project as `addons/universal_gameplay/`.
2. Enable **Universal Gameplay Framework** under *Project → Project Settings →
   Plugins*. That adds the `EventBus` and `FrameworkCore` autoloads and gives
   the framework's semantic input actions default bindings, never overwriting
   one you have already defined.
3. Create a `FrameworkSettings` resource, tick the modules you want, and point
   `definition_paths` at your content folder.
4. Name that resource in *Project Settings → Universal Gameplay → Config →
   Settings Path*.

On the next run the framework brings up those modules in dependency order,
scans and validates your content, and reports what it did:

```gdscript
print(FrameworkCore.get_bootstrap_result().format_report())
```

Nothing starts half-built. A module list missing a required module is refused
with the missing ids named.

## What this folder does not contain

No game content. Not one `.tres`, not one named item, character, mission or
place — a test in the source repository enforces it. What ships is the
vocabulary; the nouns are yours.

## Documentation

The full reference — every module and its dependencies, every `class_name`,
the migration guide, and two worked example projects — lives in the source
repository at <https://github.com/GameDevBuddy/UGF>.

Once the plugin is enabled, every class here also documents itself in Godot's
built-in help (F1).
