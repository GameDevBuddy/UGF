# Source documents

The two documents in this folder are the specification the framework is built from.
They are the authority; the code follows them, not the other way round.

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
