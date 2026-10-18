# Developing UnitFrames

UnitFrames targets **WoW Forever**, currently TOC Interface `16001`, with
Lua 5.1-compatible code. Forever uses modern Retail/Midnight UI APIs and
secret-value restrictions, despite the client's `_classic_beta_` directory name.

For the player-facing introduction, see [README.md](README.md).
Detailed in-game options are in [USER_GUIDE.md](USER_GUIDE.md).
Read [AGENTS.md](AGENTS.md) before changing code; it covers configuration,
lifecycle, API verification and regression-sensitive behaviour.

## Local setup

You need LuaJIT, Bash and Git to run the offline tests. The release integration
checks also need zip, unzip and jq. Library fetching uses curl, tar and
sha256sum; local installation uses rsync.

The embedded library folders are currently **ignored by Git**, so a fresh
clone or GitHub source ZIP is not a complete, installable addon. The TOCs
expect libraries under `UnitFrames/Libs/` and `UnitFrames_Media/Libs/`.

For a fresh checkout, populate the pinned test dependencies without needing
a game installation:

```sh
bash scripts/setup-test-libs.sh
```

This downloads the existing Ace3, oUF and LibEditMode revisions and
LibSharedMedia revision 176 (minor 12000002). It refuses to replace existing
library folders. LibSharedMedia files are verified with SHA-256 checksums.
The pins live in the script; change them only for an intentional dependency
update. Setup requires curl, tar and sha256sum in addition to Bash.

For an intentional library update, review and run:

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

## Build versions and development previews

The addon reads its version and build channel from TOC metadata. `/uf` prints
the version, and the Workbench title displays it. An unstamped source checkout
uses `dev`; WoW cannot read Git itself.

To stage the current working files with libraries and a version such as
`dev-0123456789ab` (or `dev-0123456789ab-dirty` for local changes), run:

```sh
bash scripts/build-dev.sh
```

The script creates a new directory under ignored `.build/` and prints its
location. You can supply a new output directory as the first argument.
It does not modify source files or install into the game. Deploy the staged
addon folders using the incremental installation guidance below. Rebuild
after changing source or HEAD; the stamped version describes that build.
Direct source symlinks retain the unstamped `dev` version.

Development builds include the Workbench's **Bars** and **Basics** component
gallery. Their settings only affect those demonstrations. Packaged releases,
including alpha/beta tags, omit these entries from navigation and registration;
unit settings, their previews, Theme, Profiles and ClickGrid remain available.
Theme controls shared appearance defaults.

Release packaging stamps all four TOCs with the version tag (without an
optional `v` prefix), the tag's full commit SHA, and the `release` channel.
The existing GitHub workflow selects the tag automatically and uploads that
same stamped ZIP to CurseForge when publishing is enabled. No version bump
in source is needed before tagging.

## Code map

| Folder | Purpose |
|---|---|
| `UnitFrames/Core/` | Bootstrap, classes, schemas, stores, configuration, profiles and sharing strings, theme, media and text formats |
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
bash scripts/run-tests.sh
```

This runs the release packaging check, the complete suite and addon Lua syntax
checks, like CI (which adds `--times -j`). The runner is also usable directly:

```sh
luajit tests/run.lua -j               # everything, one process per CPU
luajit tests/run.lua units/           # one area folder
luajit tests/run.lua shields          # spec paths containing "shields"
luajit tests/run.lua --tag shields    # tests tagged #shields in any area
luajit tests/run.lua clickgrid -t "full-health"   # tests whose name contains the text
luajit tests/run.lua --times          # per-spec durations
```

Specs live in `tests/spec/<area>/`: `core`, `contract` (API and schema
snapshots), `components`, `auras`, `units`, `workbench`, `editmode` and
`clickgrid`. A feature spec keeps a feature's live and Workbench preview tests
together. Behaviour that also has tests in other areas carries a `#tag` in its
`describe` or `it` name (for example `#shields`) so `--tag` can run all of it.

Path filters combine with "or"; a trailing `/` selects exactly one folder and
a name ending in `.lua` exactly one file. `-t` and `--tag` narrow further. A run
that selects no tests fails. The runner always checks addon Lua syntax. No
external busted installation is needed. To see where a spec spends its time,
use LuaJIT's profiler: `luajit -jp=F tests/run.lua clickgrid_spec.lua`.

### Pull request checks

The [Tests workflow](.github/workflows/tests.yml) runs for pull requests and
manual dispatches, not for pushes, so pushing a branch stays fast. It installs
LuaJIT, fetches pinned test libraries and checks out the matching Forever
Blizzard source, so API snapshot freshness is checked as well. The workflow
has read-only repository permissions and does not install anything into a
game client.

Branch protection on `main` requires the **LuaJIT test suite** check to pass
before a pull request can be merged. Run `bash scripts/run-tests.sh` locally
when you want feedback before opening or updating a pull request.

### API snapshot and client verification

The mock API is checked against `tests/fixtures/api_snapshot.lua`. With the
Blizzard source checkout present, the suite also checks that regeneration
produces the committed snapshot. After adding API usage or updating that
checkout, regenerate and review the diff:

```sh
luajit scripts/api-snapshot.lua
```

When updating the client source version, update the workflow's pinned Blizzard
checkout commit alongside the reviewed snapshot.

Add regression tests for fixes. Keep mocks faithful to native restrictions;
do not weaken them to make an implementation pass. Offline tests cannot
prove rendering, taint safety or combat behaviour. Verify relevant changes
in game, including repeated toggles, Workbench entry switching and release,
sample/live sources, combat, unit disappearance/replacement, full-health
shields and Edit Mode.

ClickGrid's [reference and validation checklist](UnitFrames_ClickGrid/README.md)
covers its additional group, binding and combat checks.

## Releases and downloads

The [Release workflow](.github/workflows/release.yml) handles version tags and
published GitHub releases. Tags may use either `1.0.0` or `v1.0.0`; prerelease
suffixes such as `1.0.0-beta.1` and `v1.0.0-alpha.1` also work:

```sh
git tag -a v0.1.0 -m 'UnitFrames 0.1.0'
git push origin v0.1.0
```

A tag push runs the full suite with pinned dependencies and the matching
Blizzard source, builds `UnitFrames-v0.1.0.zip` and its SHA-256 file, and
attaches them to a **draft** GitHub release. Review the notes and publish the
draft when ready. Publishing a release directly also builds and attaches the
ZIP, even if the tag was not previously pushed separately.

For an existing release whose packaging failed, push the repaired tooling to
`main`, then open **Actions > Release > Run workflow**. Select `main`, enter
the existing tag (for example `1.0.0`), and enable **Also upload to CurseForge**
if needed. The rebuild uses current packaging tools but tests and packages
the exact tagged addon files. It replaces the ZIP/checksum assets without
moving the tag or recreating the release. Simply rerunning an older failed
run still uses that run's old scripts.

The ZIP has four top-level addon folders, ready to extract into
`Interface/AddOns`; no additional containing project directory is used.
All four TOC versions come from the tag. Library Lua/XML, fonts, license files
and notices are included. Tests, developer scripts and reference checkouts
are excluded. The bundle validator checks TOC and nested XML references, Lua
syntax, versions, font files and license notices before the archive is created.

GitHub's generated source archives are not installable release bundles.
Releases in a **private** GitHub repository are visible only to people with
repository access. Make the repository public if GitHub should host public
downloads; CurseForge can host downloads while the GitHub repository stays private.

To package an existing tag locally, first populate the library folders and
run tests, then:

```sh
bash scripts/run-tests.sh
bash scripts/release.sh v0.1.0
```

The default output directory is ignored `.release/`; pass a second argument
to choose another directory. Existing artifacts are not overwritten. The
script packages committed addon files from the requested tag, excluding dirty
or untracked source files, and embeds the current local library copies.
Use a fresh checkout with `scripts/setup-test-libs.sh` for the pinned
dependencies used in CI. Packaging itself does not run the test suite or
install anything into a client.

### Optional CurseForge publishing

Register one WoW addon project for the entire UnitFrames bundle through the
[CurseForge author dashboard](https://authors.curseforge.com/#/projects/create/choose-game).
Use the README's feature description, the repository's
[PolyForm Noncommercial license](LICENSE) and your own project icon. If the
license is not listed, CurseForge's Custom License field can contain the
existing license text. Project creation and file approval are handled by
CurseForge; see [their submission guide](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project).

Before enabling uploads, check that CurseForge lists a compatible **Forever**
game version. Interface `16001` is not a CurseForge game-version ID. Do not
choose Retail or Classic versions just to get an upload accepted. If Forever
is not supported yet, keep CurseForge publishing disabled and distribute
through GitHub releases.

In GitHub **Settings > Secrets and variables > Actions**, configure:

| Kind | Name | Value |
|---|---|---|
| Secret | `CF_API_TOKEN` | Upload API token from the [CurseForge API token page](https://authors.curseforge.com/#/api-tokens) |
| Variable | `CF_PROJECT_ID` | Numeric ID of your registered project |
| Variable | `CF_GAME_VERSION_IDS` | Compatible numeric game-version IDs, comma-separated, without spaces |
| Variable | `CF_ENABLED` | `true`, only after the project and version mapping are ready |

The upload API's `/api/game/versions` endpoint lists version IDs; use your
token as the `X-Api-Token` header. The uploader checks that your configured IDs
exist. You must select the correct client flavour yourself. See the official
[upload API documentation](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-api).

Publishing a GitHub release uploads the same tested ZIP to CurseForge when
`CF_ENABLED` is `true`. Tag pushes only create the draft and do not upload to
CurseForge. Alpha tags upload as alpha, other prerelease tags as beta, and
stable tags as release. A release marked prerelease in GitHub uploads as beta
even without a prerelease suffix. CurseForge receives the GitHub release notes
as its changelog. Missing credentials or invalid configuration fail the upload
job, while the GitHub ZIP remains available.

To inspect upload metadata without a token or network request:

```sh
CF_PROJECT_ID=123 CF_GAME_VERSION_IDS=456,789 \
  bash scripts/publish-curseforge.sh --dry-run .release/UnitFrames-v0.1.0.zip v0.1.0
```

These IDs are examples, not actual project or compatible game-version IDs.
No project registration, release publication or CurseForge upload is done by
running the packaging tests.

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

Text slots compose single-value sources (`Core/TextSources.lua`) through one
composer (`Core/TextTemplate.lua`) used by oUF tags, live previews and samples
alike; format ids are presets over those sources (`Core/Formats.lua`). Fully
available presets bind their shared `[uf:<id>]` tag; custom slots bind a
reusable handle tag (`Units/TextTags.lua`). Sources declare what they need
(player-only values), slots receive what their frame provides as
`textContext`, and both the inspector and the compiled template use that.
`tests/fixtures/formats_golden.lua` records every preset's historical output.
See `docs/todos/04-design-text-slots.md` for the design.

ClickGrid owns refresh of all its registered previews. Its Workbench watches use
`notifyOnly` for inspector/stage updates, avoiding another style/data refresh.
Preview source transitions clear previous sample effects explicitly; missing
live units and hidden cells disable their native aura subscriptions.

## Performance verification

Run `luajit scripts/performance-probe.lua` for a deterministic mock census of
ClickGrid schemas, widgets, death/ready-check reflows, inactive-layout refreshes
and warmed preview copies. The same script can run from a baseline checkout
using unchanged libraries. Mock counts do not measure WoW CPU, native memory,
rendering or taint. The probe leaves Workbench unloaded during its runtime
census, then explicitly creates a preview for the final workload.

`/uf perf` samples coarse Lua memory outside timed operations and reports
recent profiler milliseconds per tick, session peaks and session threshold
counts. `/uf perf watch 60` reports threshold deltas and addon-owned operation
counts over one bounded observation window; it does not report a window peak
or treat ticks as rendered frames. `/uf perf measure units|clickgrid|preview|schema|auras|create`
actively runs one prepared operation outside combat and reports native elapsed
milliseconds and allocated/deallocated bytes. Cancel a watch before measuring.
Optional APIs have capability checks. Reports print separate top-15 rankings by
exclusive time and allocation; phase entries include cache hits and are distinct
from build counters. Resolution and child-config summaries show calls, builds
and shared hits. Cold schema construction, oUF driver/tag binding, native unit
spawning and Edit Mode registration have separate attribution.

Successful active measurements retain their complete phases, counters, timing,
allocations and environment/settings context under
`UnitFramesDB.global.perfMeasurements["measure units"]` (or the corresponding
operation title). Each title retains only its latest successful measurement.
`/uf perf startup` arms measurements for unit and ClickGrid startup on the next
reload; these use the `"startup units"` and `"startup clickgrid"` titles. New
TOC files require a client restart after installation before using the commands.

`/uf perf edit indicators|titles|spacing|member|target|slots|bindings` measures
one representative ClickGrid edit through the real settings store and its
callbacks, then restores the original store overrides outside the timed call.
The probes toggle the phase indicator or titles, adjust horizontal spacing,
member/target width or first-slot size by one schema step, or switch the first
friendly click action between target and assist. They require prepared ClickGrid,
enabled profiling, no active observation/suite and no combat. Reports are saved
as `"edit indicators"`, etc., including the edited path, previous effective value,
probe value, original overrides and restoration result. These costs include
store validation and synchronous callbacks; compare the same probe before and
after targeted refresh work. Restoration also runs if measurement/reporting
fails. Creating an enabled native feature can retain its widgets after restore;
use fresh reloads when comparing cold creation, independently of warm edit costs.

`/uf perf suite baseline` automates schema, unit and prepared ClickGrid refresh
measurements outside combat. Each operation runs two warmups and ten recorded
calls, at most one per frame with a minimum 0.1-second interval. Creation tests
remain separate because released engine widgets survive until reload. Keep
targets and preview state stable for comparable results. Combat, roster or
configuration changes cancel the run, as does profiler deactivation.

`/uf perf suite report` prints the latest attempt. Its structured data persists
under `UnitFramesDB.global.perfSuiteReport`, including completion status, raw
samples, timing/allocation summaries, exclusive phases, counters, environment
and settings context, and endpoint snapshots. The context also records selected
ClickGrid layout, target visibility, prepared/active frame counts and preview
count. Active frames belong to enabled layout headers; they may be hidden while
solo. Builds with missing/unknown commit metadata are labelled unidentified;
record the installed revision before comparing them. Local copies currently
retain the repository TOC metadata, so a `dev` version alone identifies no revision.

Each attempt replaces the latest report. Before replacement, an existing completed
report is automatically copied to `UnitFramesDB.global.perfSuiteBaselineReport`
if no comparison baseline exists. `/uf perf suite save` explicitly replaces that
comparison baseline with the latest completed report; `/uf perf suite saved`
prints it. Partial/failed attempts cannot be explicitly saved as baselines.
`/reload` writes diagnostics to SavedVariables; save an external copy for longer
history. Suite summaries exclude warmups and include synchronous operation costs
only. Capture a fresh baseline after attribution changes so profiler overhead
is consistent across later optimization comparisons.

Schemas returned by components are immutable metadata. Definition-created
frames explicitly share schema ownership, including row text contexts;
arbitrary caller specs retain independent dynamic schemas. Derive a definition
before construction to alter its structure. Copy a schema before editing it;
user overrides and resolved configuration remain private per instance.

ClickGrid prepares enabled portrait backends during deferred style application,
before any combat assignment, and reuses them on subsequent toggles. Other
portrait callers retain eager backends. Retained headers absent from the
selected layout disable raid eligibility, oUF elements, native aura feeds and
tags; reactivation reapplies the latest style and bindings before restoring
raid eligibility. Party and selected raid headers stay prepared even when
currently hidden by roster visibility.

Client verification still needs real combat, subgroup/flat/tank switches,
profile changes, missing/reassigned members, ready-check fades and portrait
cast coverage, sample/live/source transitions and release, Edit Mode and
full/damaged-health shields in both placements. Compare warmed S1–S8 runs at
fixed client settings; offline counts establish removed work, not FPS gains.

## Adding fonts

1. Copy a static `.ttf`/`.otf` file (one per weight) and its licence into
   `UnitFrames_Media/Fonts/`.
2. Add `{ "Name in the picker", "File.ttf" }` to the list in
   `UnitFrames_Media/Media.lua`.
3. Deploy the changed media addon using the installation guidance above,
   then restart the client.
