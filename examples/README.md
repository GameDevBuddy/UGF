# Example projects

Two worked examples, each one settings resource and a folder of content.

**There is no GDScript in this directory, and that is the point.** The M19
exit gate is "a new project integrates Core plus chosen modules without
copying game-specific code", and a directory with a single helper script in it
would quietly fail that gate while looking like it passed. A test enforces the
absence ([`tests/cases/test_examples.gd`](../tests/cases/test_examples.gd)),
along with the rule that nothing here may reference a path outside
`addons/universal_gameplay/` — an example that loads something from this
repository's test folder works perfectly here and breaks the moment somebody
copies it into their own game.

## Using one

Point your project at a settings resource:

**Project → Project Settings → Universal Gameplay → Config → Settings Path**
→ `res://examples/adventure/settings.tres`

That is the whole integration. On the next run, `FrameworkCore` reads the
resource, brings up the modules it names in dependency order, scans the
content folder, validates every definition it finds, and reports what it did
through `FrameworkCore.get_bootstrap_result()`.

To do the same thing without touching Project Settings:

```gdscript
var settings: FrameworkSettings = load("res://examples/adventure/settings.tres")
var result := FrameworkCore.bootstrap(settings)
print(result.format_report())
```

## adventure

The classic loop: talk to someone, be told to fetch something, fetch it, get
credit for it.

| File | What it is |
| --- | --- |
| `settings.tres` | Eleven modules, and the content folder |
| `content/item_lantern.tres` | An `ItemDefinition` whose world form is the addon's generic pickup scene |
| `content/item_cellar_key.tres` | Another one, to show a second category |
| `content/dialogue_gatekeeper.tres` | A two-node conversation that sets a narrative flag on the way past |
| `content/mission_light_the_cellar.tres` | Two objectives, sequential, paying out a flag |

What is worth reading it for: **the mission names no module.** Its first
objective matches an event called `dialogue_completed` on a field called
`dialogue_id`; its second matches `item_acquired` on `item_id`. Missions has
no idea Dialogue or Inventory exist, and turning either off leaves the other
objective working.

The mission is also authored `sequential = true`, so the lantern does not
count until the gatekeeper has been asked. That is one field in a `.tres`, not
a branch in a script.

## survival

Gather, craft, eat.

| File | What it is |
| --- | --- |
| `settings.tres` | Eleven modules, including Crafting, Gathering and Survival |
| `content/item_kindling.tres`, `content/item_pine_resin.tres` | Stackable materials |
| `content/item_torch.tres` | The output. Note `max_stack = 1`: an item with durability cannot stack, and the framework refuses content that tries |
| `content/item_dried_berries.tres` | Carries a `ConsumableProfile` naming the need it restores and by how much |
| `content/recipe_torch.tres` | Two ingredients in, one torch out |
| `content/need_hunger.tres` | Decay rate, thresholds, the states it sets, and what it does to you at zero |

What is worth reading it for: **nothing in the recipe knows what an item is.**
`RecipeIngredient` names item ids and quantities. The berries name a need id.
The need names two semantic states. Every link between these files is a
string, which is why any of them can be replaced without touching the others
(rule 32).

## Building your own from here

The shortest honest path:

1. Copy one of these settings resources into your own project and edit the
   module list. If you get the list wrong, bootstrap tells you exactly which
   ids to add rather than half-starting.
2. Point `definition_paths` at your own content folder.
3. Author content as `.tres`. Every definition type is in
   [`docs/api-reference.md`](../docs/api-reference.md); what each module gives
   you is in [`docs/modules.md`](../docs/modules.md).
4. Read `FrameworkCore.get_bootstrap_result()` on startup during development.
   It is the framework telling you what is wrong with your content, with file
   paths, before you go looking for it in a running game.
