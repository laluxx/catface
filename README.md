# 󰄛 Catface

Catface is the fast terminal cockpit for the MonadC context category.

It is not a generic curses browser. It is a project-specific interface for answering questions like:

- What TODOs are open right now?
- Which tests verify this compiler behavior?
- Which notes are observations, decisions, or inferences?
- What source files, scripts, records, and tests are connected to this object?
- What does `reader <- @tests` or `%verifies @tests -> codegen` reveal?

Catface is optimized for live compiler work: type naturally, narrow aggressively, follow category arrows, and keep every object grounded in the context/source tree.

## Current version

**v0.7.1 — Indexed Focus**

This version focuses on making Catface feel like a serious terminal instrument:

1. **Viewport-correct navigation**: the left result stream now uses the actual terminal size instead of a fixed row count, so the selected candidate stays visible above the footer on small and large terminals.
2. **Right-pane focus mode**: when the relation pane is active, printable keys no longer edit the prompt. Use `n`/`p`, `j`/`k`, arrows, `C-n`/`C-p`, PageUp/PageDown, and `RET` to move through and open relation-tree rows. `Tab` returns to search input.
3. **Faster indexed search**: exact index hits now return without scanning approximate terms, and `=term` asks for exact-token search when you do not want fuzzy expansion.
4. **Cheaper terminal flushing**: dirty cells are flushed as contiguous changed runs instead of one cursor jump per changed cell.
5. **Performance coverage**: `zig build test` includes minimal synthetic performance smoke tests for the index, cache, tree cursor, and query catalogue.

## Build

```sh
zig build
```

## Run

From `context/category/catface`, pass the compiler repository root when you want universal search:

```sh
zig build run -- ../../../
```

Passing `../../` also works when you only want the `context/` subtree.

Run tests:

```sh
zig build test
```

Run the context integrity check:

```sh
zig build check-context
```

## CLI commands

```sh
catface [project-or-context-root]
catface --root <project-or-context-root>
catface --query <expr> [project-or-context-root]
catface --card <object-id> [project-or-context-root]
catface --check [project-or-context-root]
catface --dump-objects [project-or-context-root]
catface --help
```

Useful examples:

```sh
catface --query '@todo' ../../../
catface --query '@bugs' ../../../
catface --query '@notes reader' ../../../
catface --query '@tests -> reader' ../../../
catface --query 'reader <- @tests' ../../../
catface --query '%verifies @tests -> codegen' ../../../
catface --query '@todo -> @source' ../../../
catface --card 'monadc.context.category.index.purpose' ../../../
```

## Interface model

Catface is a two-pane terminal cockpit.

### Top rail

The top rail contains:

- the `󰄛 Catface` logo,
- corpus statistics,
- a live query line,
- quick lane hints,
- object/category counts.

Typing is search while the left pane is active. When the right pane is active, printable keys control the relation-tree cursor instead of mutating the prompt. Normal words fuzzy-search object ids, titles, paths, tags, and previews.

### Left pane: ranked object stream

The left pane shows ranked objects. Each row is a compact card:

- kind badge,
- title,
- source path and line,
- object id,
- preview text.

Use arrows, `C-n`/`C-p`, PageUp/PageDown, or the mouse wheel to move through results.

### Right pane: object text + relation tree

The right pane is split conceptually into two parts.

The **top** shows the selected object as text: what it does, why it matters, source path, preview, and kind-specific interpretation.

The **bottom** is the relation tree. It is anchored at the bottom of the pane and shows the selected object’s neighborhood:

```text
RELATION TREE
▾ OUT  Hom(object, -)  12 arrows
  ▾ [VERIFY] verifies  4
  │  ├─ [TEST] ✓ T  reader layout gap regression
  │  ├─ [OBS]  ✓ ▣  [OBS] reader accepts layout method forms
  ▸ [SUPPORT] supports  6
▾ IN   Hom(-, object)  8 arrows
  ▾ [LINK] id-link  3
  │  ├─ [NOTE] ⇢ I  reader notes
```

Interaction:

- click `OUT` or `IN` headings to collapse/expand a direction,
- click edge-kind headings like `[VERIFY]` or `[LINK]` to collapse/expand that group,
- click object rows to select that connected object,
- scroll the wheel over the right pane to scroll the relation tree,
- with the right pane active, use `n`/`p` or `C-n`/`C-p` to move the tree cursor and `RET` to open the highlighted heading or object row.
- with the left pane active, press `Enter` to pin the selected object as `?id`.

## Query language

Catface’s query language is deliberately compact. It is designed for compiler/category navigation, not SQL.

### Words

```text
reader layout
wisp define
path literal
```

Words fuzzy-search ids, titles, paths, tags, and preview text.

### Kind filters

```text
:Test
:Record
:Source
:Concept
:Todo
:Done
:Info
```

Kind filters restrict the object stream to one object type.

### Namespace lanes

```text
@todo
@bugs
@notes
@tests
@info
@source
@reader
@wisp
@codegen
@reports
@fix
@hot
@triage
@blocked
@roots
@leaves
@orphans
@obs
@dec
@inf
```

These are high-value surfaces for daily work.

Use these constantly:

```text
@todo reader
@bugs codegen
@notes wisp define
@obs path literal
@dec syntax
@inf type inference
```

### Identity filters

```text
?object-id
#object-id
```

Use these when you know the exact object id.

`Enter` on a selected result also pins that object as `?id`.

### Field filters

Use these when you know exactly where a term should match. They are intentionally simple and fast.

```text
title:reader
path:reader.c
id:monadc.context
preview:TODO
tag:tests
```

Field filters combine with normal lanes:

```text
@todo title:reader
@tests path:reader
@notes preview:OBS
```

### Exact token search

Use `=term` when you want indexed token hits without fuzzy/approximate expansion:

```text
=reader
=TODO
=needlefast
```

This is useful for performance probes and for reducing noise when a short word would otherwise fuzzy-match too broadly.

### Edge-kind filters

```text
%verifies
%supports
%blocks
%refines
%mentions
%generated-by
%id-link
%file-link
```

Edge filters ask Catface to privilege or restrict by morphism kind.

Examples:

```text
%verifies @tests
%blocks @todo
%supports @notes reader
```

### Category relation syntax

```text
lhs -> rhs
lhs <- rhs
```

`lhs -> rhs` asks for morphisms from the left object set to the right object set.

`lhs <- rhs` asks the reverse question.

Examples:

```text
@tests -> reader
reader <- @tests
%verifies @tests -> codegen
@todo -> @source
@obs -> @tests
@notes -> @todo
```

This is the query syntax that matches the category-theory model most directly: objects are searched as sets, arrows connect them, and edge kinds refine the Hom view.

### Graph operators

```text
>
<
~
proj
```

Meaning:

- `>` expands through outgoing arrows: `Hom(object, -)`.
- `<` expands through incoming arrows: `Hom(-, object)`.
- `~` expands the neighborhood in both directions.
- `proj` projects toward concepts/taxonomy objects.

Examples:

```text
reader >
reader <
reader ~
wisp define proj
```

## Keyboard reference

| Key | Action |
|---|---|
| Type | edit the live query |
| `?` | open help when query is empty |
| `Esc` | close help, then quit |
| `C-c` | quit |
| `↑` / `↓` | move result selection |
| `C-p` / `C-n` | move result selection |
| PageUp / PageDown | scroll result stream |
| `Enter` | focus selected object as `?id` |
| `Tab` | switch pane emphasis; typing still edits search |
| `C-a` / `C-e` | query start/end |
| `C-d` | delete forward |
| Backspace / `C-h` | delete backward |
| `C-k` | kill to end |
| `M-d` | kill word |
| `C-y` | yank kill ring |
| `C-l` / `C-u` | clear query |
| `Alt-b` | history back |

Quick lanes:

| Key | Query |
|---|---|
| `Alt-t` | `@todo` |
| `Alt-n` | `@notes` |
| `Alt-e` | `@tests` |
| `Alt-s` | `@source` |
| `Alt-i` | `@info` |
| `Alt-u` | `@bugs` |
| `Alt-w` | `@wisp` |
| `Alt-m` | `@reader` |
| `Alt-c` | `@codegen` |
| `Alt-r` | `:Record` |
| `Alt-v` | append `%verifies` |
| `Alt-x` | append `%blocks` |
| `Alt-o` | append `>` |
| `Alt-<` | append `<` |
| `Alt-g` | append `~` |
| `Alt-p` | append `proj` |

Mouse:

| Action | Behavior |
|---|---|
| click result row | select object |
| click right pane object row | select connected object |
| click relation heading | collapse/expand branch |
| mouse wheel over left pane | scroll results |
| mouse wheel over right pane | scroll relation tree |
| mouse release / drag | safely ignored unless mapped later |

## Performance model

Catface is designed to stay responsive on a large context corpus.

Implemented optimizations:

- one startup `SearchIndex` containing normalized text postings, kind buckets, edge-kind buckets, incoming adjacency, outgoing adjacency, and in/out degree arrays,
- indexed query path for normal words, `:Kind`, `%edge-kind`, `>`, `<`, `~`, `proj`, and relation queries with edge-kind hints,
- reference evaluator kept as a fallback and test oracle for quality,
- event-driven render loop: no full redraw every tick,
- query-result cache: queries run only when the query buffer changes,
- dirty screen flag: key/mouse/resize/cursor blink mark the UI dirty,
- dirty-cell terminal backend: `set()` tracks changed cells and `flush()` scans only dirty bounds,
- no unconditional full-screen clear in the normal draw path,
- SGR mouse handling: release/scroll sequences no longer fall through to quit,
- footer telemetry: frame/query/flush times are always visible in nanoseconds.

The footer shows:

```text
frame 430000ns  query 80000ns  flush 120000ns  redraws 42  cached 91
```

Use this while optimizing. A sluggish interaction should be visible as either query time, flush time, or frame time.

## Examples directory

The `examples/` directory contains query cookbooks you can paste directly into Catface or pass to `--query`.

Current files:

```text
examples/queries.catq      compact everyday cookbook used by tests
examples/catalogue.catq    larger feature catalogue for manual exploration
examples/perf.catq         performance probe list for timing/search regressions
```

They are organized by task:

- daily TODO/bug triage,
- notes and trust-level searches,
- tests and coverage queries,
- category relation queries,
- source-specific surfaces,
- field-specific indexed search,
- graph/projection operators,
- shape diagnostics such as roots/leaves/orphans,
- performance probes.

Try examples manually:

```sh
for f in examples/queries.catq examples/catalogue.catq examples/perf.catq; do
  echo "### $f"
  while IFS= read -r q; do
    case "$q" in ''|'#'*) continue ;; esac
    echo "--- $q"
    zig build run -- --query "$q" ../../../ | head -20
  done < "$f"
done
```

## Design principles

1. **Typing must feel normal.** Search is the main action; printable keys should not be stolen by navigation commands.
2. **Every object must be grounded.** A result should always expose id, path, line, preview, and relation context.
3. **Category operations must be visible.** `->`, `<-`, `%edge-kind`, `>`, `<`, `~`, and `proj` are first-class UI language, not hidden implementation details.
4. **The right pane should explain, not just list.** The top describes the object; the bottom shows its Hom neighborhood.
5. **Performance must be observable.** The footer timings make slowness a testable property.
6. **Mouse input must never be fatal.** Unknown escape sequences are ignored; SGR mouse release and scroll are handled safely.

## Development workflow

Before shipping a Catface change:

```sh
zig build test
zig build run -- --query '@todo' ../../../
zig build run -- --query '@tests -> reader' ../../../
zig build run -- --query '%verifies @tests -> codegen' ../../../
zig build run -- ../../../
```

Manual UI checks:

- type ordinary words like `reader`, `wisp`, `codegen`, `todo`, `q`, `j`, `k`, `n`, `p` and confirm they enter the query,
- click a result row,
- click a relation tree heading and confirm it collapses,
- click a relation tree object row and confirm selection changes,
- scroll the wheel in both panes,
- open `?` help and close it with `Esc`,
- watch footer timings while searching.

## Project shape

Important files:

```text
src/app.zig              event loop, key/mouse dispatch, dirty redraw policy
src/terminal.zig         raw terminal, SGR mouse parser, dirty-cell flush
src/render.zig           full UI rendering, object cards, relation tree, footer timings
src/query.zig            indexed/reference fuzzy/category query language
src/index.zig            startup search index: text postings, buckets, adjacency
src/tree.zig             collapsible relation tree state and actions
src/perf.zig             timing helpers and performance counters
src/model.zig            context objects and morphisms
src/org.zig              context loader
src/tests.zig            test harness importing all modules
examples/queries.catq    compact query cookbook
examples/catalogue.catq  full feature catalogue
examples/perf.catq       performance probe catalogue
```


## Performance tests

`zig build test` includes deterministic performance smoke tests. They do not rely on fragile wall-clock budgets for pass/fail; instead they assert that indexed candidate sets stay selective and print timing/candidate lines you can paste back into review.

Look for output like:

```text
catface perf: indexed candidates for needlefast = 5/320
catface perf: 64 indexed needlefast queries over 500 objects took <ns>ns
```

Those tests are intentionally small. Their job is to catch architectural regressions such as accidentally returning to full-corpus scans for common word queries.
