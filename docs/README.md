# Documentation

## Using the framework

| Document | What it covers |
| --- | --- |
| [`modules.md`](modules.md) | Every module the addon ships, what it requires, and what it will integrate with when present. **Generated** from the manifests. |
| [`api-reference.md`](api-reference.md) | Every `class_name` the addon defines, with the first line of its own documentation. **Generated** from the source. |
| [`migration-guide.md`](migration-guide.md) | Upgrading the addon, save schema migrations, and replacing a shipped module with your own. |

Regenerate the two generated documents after changing a manifest or a class:

```bash
godot --headless --path . --script tools/generate_docs.gd
```

`tests/cases/test_documentation.gd` fails when a committed file and the source disagree, so
forgetting this step fails the build rather than shipping a stale table.

Worked examples live in [`../examples/`](../examples/) — two projects, each one settings
resource and a folder of `.tres`, with no GDScript in either.

## Source documents

The two specification documents are the authority; the code follows them, not the other way
round.

| Document | What it covers |
| --- | --- |
| [`implementation-plan.md`](implementation-plan.md) | Platform scope, layered architecture, module catalogue, per-feature specifications, the M0–M19 milestone roadmap, and a 42-rule framework rulebook. |
| [`ontology-rulebook.md`](ontology-rulebook.md) | The ontology tree, system layers, the Godot translation table, a 30-rule rulebook, and the decision and naming guides. |

Both Markdown files are mechanical conversions of the original `.docx`, which are kept
verbatim in [`source/`](source/). The conversion preserves headings, tables, ASCII diagrams
and code blocks; no wording was changed, added or removed. Where the two documents
contradict each other, the resolution and its reasoning are recorded in the root
[`README.md`](../README.md) under *Decisions made where the source documents conflict* —
not silently in code.

Regenerate the Markdown from the `.docx` with `tools/docx_to_markdown.py`:

```bash
python3 tools/docx_to_markdown.py docs/source/implementation-plan.docx > docs/implementation-plan.md
python3 tools/docx_to_markdown.py docs/source/ontology-rulebook.docx  > docs/ontology-rulebook.md
```

## Naming note

Rulebook §17 sketches the addon folder as `addons/framework/`; Implementation Plan §32 names
it `addons/universal_gameplay/`. The code follows the Plan. The Rulebook's tree is
illustrative of shape rather than of path, and two addon roots would split the framework in
two.
