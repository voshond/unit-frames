# Developing UnitFrames

UnitFrames targets **WoW Forever**, currently TOC Interface `16001`, with
Lua 5.1-compatible code. Forever uses modern Retail/Midnight UI APIs and
secret-value restrictions, despite the client's `_classic_beta_` directory name.

For the player-facing introduction, see [README.md](README.md).
Detailed in-game options are in [USER_GUIDE.md](USER_GUIDE.md).
Read [AGENTS.md](AGENTS.md) before changing code; it covers configuration,
lifecycle, API verification and regression-sensitive behaviour.

## Local setup

You need LuaJIT to run the offline tests. Library fetching and installation
use Bash, Git and rsync.

The embedded library folders are currently **ignored by Git**, so a fresh
clone or GitHub source ZIP is not a complete, installable addon. The TOCs
expect libraries under `UnitFrames/Libs/` and `UnitFrames_Media/Libs/`.

To populate those folders, review and run:

```sh
scripts/fetch-libs.sh
```

This script **replaces existing library copies**. Run it only for initial
setup or an intentional dependency update. It fetches Ace3, oUF and
LibEditMode, and copies LibSharedMedia from an installed addon. Set
`LSM_SRC` to an existing LibSharedMedia-3.0 directory if automatic discovery
is unavailable. `WOW_DIR` controls which client it searches.
See the script for `ACE3_REF`, `OUF_REF` and `LEM_REF` overrides; generated
library versions are recorded in `UnitFrames/Libs/VERSIONS.md`.

Verify unfamiliar APIs against the actual client or Blizzard's UI/API
documentation. The optional local source checkout is
`examples/wow-ui-source-forever`, using Gethe/wow-ui-source's `forever` branch.

## Code map

| Folder | Purpose |
|---|---|
| `UnitFrames/Core/` | Bootstrap, classes, schemas, stores, configuration, theme, media and text formats |
| `UnitFrames/Components/` | Reusable visuals, independent of oUF bindings |
| `UnitFrames/Widgets/` | Shared settings controls and schema-driven inspector |
| `UnitFrames/Units/` | Unit definitions, oUF bindings, data elements and preview writers |
| `UnitFrames/Integration/` | Edit Mode and launcher integration |
| `UnitFrames_Workbench/` | Load-on-demand settings, component gallery and static/animated/live previews |
| `UnitFrames_ClickGrid/` | Party/raid panel, member targets, indicators, auras and click-spell bindings |
| `UnitFrames_Media/` | Additional fonts and their licences |
| `tests/` | Mocked client, API snapshot and regression specs |
| `scripts/` | Library fetching, installation and API snapshot generation |

New runtime files belong in the relevant TOC in dependency order; tests
load those TOCs too. Preserve existing worktree changes and avoid editing
embedded libraries as normal implementation targets.

Local research lives in the ignored `docs/` directory. Those notes include
dated investigations and unimplemented plans; current code takes precedence.

## Verification

Run from the repository root:

```sh
luajit tests/run.lua
luajit tests/run.lua shields
luajit tests/run.lua workbench
luajit tests/run.lua clickgrid
```

The runner also checks addon Lua syntax. Its optional filter matches spec
filenames, not individual test names. No external busted installation is needed.

The mock API is checked against `tests/fixtures/api_snapshot.lua`. With the
Blizzard source checkout present, the suite also checks that regeneration
produces the committed snapshot. After adding API usage or updating that
checkout, regenerate and review the diff:

```sh
luajit scripts/api-snapshot.lua
```

Add regression tests for fixes. Keep mocks faithful to native restrictions;
do not weaken them to make an implementation pass. Offline tests cannot
prove rendering, taint safety or combat behaviour. Verify relevant changes
in game, including repeated toggles, Workbench entry switching and release,
sample/live sources, combat, unit disappearance/replacement, full-health
shields and Edit Mode.

ClickGrid's [reference and validation checklist](UnitFrames_ClickGrid/README.md)
covers its additional group, binding and combat checks.

## Installing a local build

Validate the actual target directory first. The default client's AddOns path is:

```text
/mnt/data02/Games/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/
```

Check symlink targets before copying. For incremental updates, use
`rsync -ai` on each changed addon folder without `--delete`, then verify
with `rsync -anic`. This preserves extra files but does not remove stale ones;
intentional removals need separate handling.

`scripts/install.sh` discovers top-level addon folders from their TOCs. It
supports `WOW_DIR`, named addon arguments, `--link` and `--uninstall`.
**It removes each existing targeted addon directory before copying or linking;
`--uninstall` removes it too.** SavedVariables under `WTF/` remain intact,
but other files in those addon folders are replaced.

Use `/reload` for changed Lua in existing files. Restart the client for new
TOC-listed files or new media/font assets. Keep repository edits and game
installation distinct when reporting changes.

## Component and preview structure

Components own their children explicitly with `Own`; releasing a composition
releases its children and pending work. Theme refresh applies at composition
roots, while runtime bindings manage their own refresh. Keep visual components
independent of oUF and feed sample values through the shared row writers in
`Units/Rows.lua`; non-oUF live previews use its calculator-based live writers.

A unit frame's optional parts (portrait, castbar, auras, raid target) are
declared once in `UnitFrame.PARTS` and reached with `UnitFrame:GetPart(key)`;
edge icons, including companions', join
the frame's `DecorationStack` (`UnitFrame:GetDecorations()`); the Units layer keeps one oUF binding and
one sample feeder per part key, and Edit Mode quick settings read the unit
schema. Derive new definitions with `Units:Derive`, overriding rows by key.

`IconPlacement` shares placement descriptors and adapts the companion's flat
settings without changing saved keys. `ReadyCheck` owns the shared ready-check
timeline (`UnitFrame:GetReadyCheck()`); companions use its `Attach` / `Detach`
to lend an icon while retaining its component ownership. The Units adapter owns live
element rebinding when the attached icon's availability changes.

Settings are written through stores (`Core/Store.lua`): set, replace and reset
in one place with optional validation and one change event, plus a derived
inspector target. Work blocked by combat goes through the ordered
`Core/AfterCombat.lua` queue; casts for unit frames and live previews share
`Units/Cast.lua`.

`BuildSchema` and `UnitFrameLayout.Compute` build settings and measure unit
geometry without creating frames. Decorations use `GetLayoutContext` for
configured portrait bounds rather than reading native artwork dimensions.
`CastbarLayout.Compute` similarly measures icon/bar layout before native
anchors are applied; portrait-only settings visibility belongs to UnitFrame.
Flowing auras and ClickGrid's fixed slots share `Components/AuraIcon.lua`, but
retain their separate selection, container and lifecycle policies.

Workbench separates its controller (`Workbench.lua`), presentation (`View.lua`),
settings navigation (`Sections.lua`) and active preview lifetime
(`PreviewSession.lua`). A session owns its data cache, callbacks and teardown;
cached inspector pages dispatch through their current target. Entries declare
the events that restyle them (`refreshOn`) and build handles with
`Workbench.Composite` or `Workbench.ComponentHandle`.

Entries can declare `settingsPages` that refer to existing schema paths; the
inspector retains original defaults, visibility context, override highlighting
and writes. Generated navigation remains the default. Discarded pages release
their controls and callbacks, while cached pages remain reusable.

ClickGrid owns refresh of all its registered previews. Its Workbench watches use
`notifyOnly` for inspector/stage updates, avoiding another style/data refresh.
Preview source transitions clear previous sample effects explicitly; missing
live units and hidden cells disable their native aura subscriptions.

## Adding fonts

1. Copy a static `.ttf`/`.otf` file (one per weight) and its licence into
   `UnitFrames_Media/Fonts/`.
2. Add `{ "Name in the picker", "File.ttf" }` to the list in
   `UnitFrames_Media/Media.lua`.
3. Deploy the changed media addon using the installation guidance above,
   then restart the client.
