# Repository guidance

## Scope and sources of truth

- This is **UnitFrames for WoW Forever**, currently targeting TOC Interface `16001`. Use Lua 5.1-compatible code. Forever uses modern Retail/Midnight UI APIs and secret-value restrictions; do not assume Classic-era APIs work because the client directory is `_classic_beta_`.
- Read the relevant implementation and tests before changing it. `README.md` describes current features. `docs/01-investigation-api-and-libraries.md`, `docs/02-architecture-plan.md`, and `docs/03-reference-nurfed-forever.md` explain the design and API findings, but contain dated research and unimplemented plans. Current code wins when they disagree.
- `docs/WoW unit frames addon libraries.md` is the long conversation history, not a specification to implement wholesale. Search specific topics rather than loading the entire file.
- Verify unfamiliar or changing APIs against the actual client or Blizzard UI/API documentation, preferably the `forever` branch of `Gethe/wow-ui-source` cloned into `examples/wow-ui-source-forever` for local access. Never invent API signatures or texture paths.
- Preserve existing worktree changes. Do not commit, push, update dependencies, or install into the game merely because you were asked to explain or review something.

## Code map and conventions

- `UnitFrames/Core/`: namespace/bootstrap, schema, AceDB configuration, theme, media, colours and text formats. Core Lua files receive `local _, ns = ...`; the public `UnitFrames` handle exposes that namespace to companion addons.
- `UnitFrames/Components/`: reusable visual building blocks. Keep them independent of oUF bindings; their configuration and data APIs also serve previews. `UnitFrame` exposes rows and optional parts through `GetRow(key)`/`GetPart(key)` and the `Rows()`/`Parts()` iterators; add a part to `UnitFrame.PARTS` rather than adding per-part getters. Ready-check state lives in the `ReadyCheck` presenter (`GetReadyCheck()`), which also owns its settings schema.
- Classes (`Core/Class.lua`): configurable visuals extend `Component`, settings controls extend `Widget`, other stateful helpers extend `Object` (`Class:New(...)` calls `Init(...)`). Stateless calculations stay plain module tables of functions.
- `UnitFrames/Widgets/`: the shared settings toolkit and schema-driven inspector. Reuse these controls instead of introducing a separate settings framework.
- `UnitFrames/Units/Definitions.lua`: unit composition, structural specs, defaults and sample data. Current unit keys/order are `player`, `pet`, `target`, `targettarget`, `focus`, `focustarget`; XP is player-only. Derive definitions with `Units:Derive` (row overrides by key) rather than changing shared ones. Parts every unit offers come from `Units.COMMON`; a derived companion definition leaves one out by setting its key to nil.
- `UnitFrames/Units/Drivers.lua`: one data driver per frame state, row and part, declaring its oUF binding, sample feed and polled live feed together (`false` with a reason where a source is unsupported). `Units/Style.lua` (oUF style, spawning, element binding, tags and live refresh) and `Units/Preview.lua` (`Units:ShowSample`/`ShowLive`) loop over them; `Units/Elements.lua` implements custom oUF elements. A new row or part needs a driver; `drivers_spec` enforces it.
- `UnitFrames/Integration/EditMode.lua`: layout-specific positions and snapping through LibEditMode.
- `UnitFrames_Workbench/`: load-on-demand settings and previews, opened with `/uf wb`. `Entries/Units.lua` edits the real saved unit style; `Data.lua` defines preview sources. Keep static, animated and live previews consistent with runtime behaviour.
- `UnitFrames_Media/`: independently registered LibSharedMedia fonts and their licences.
- `UnitFrames_ClickGrid/`: optional healing panel companion (`/ufcg`): party/raid groups, member targets, native aura slots, status indicators and click-spell bindings, built from the same `UnitFrame` component through the public `UnitFrames` handle.
- Match nearby code: tabs, local helpers, existing component methods. New runtime files must be added to the appropriate `.toc` in dependency order; the tests load those TOCs too.
- Embedded libraries under either addon's `Libs/` are committed dependencies, not normal edit targets. Versions are recorded in `UnitFrames/Libs/VERSIONS.md`; `scripts/fetch-libs.sh` replaces library copies and should run only for an intentional dependency update.

## Configuration and lifecycle

- Define settings once in schemas so defaults, resolution, validation and generated controls agree. Resolution order is explicit config, group default overrides, inherited theme, descriptor default.
- `config` stores user overrides; `resolved` is effective configuration; `spec` is structural and fixed for an instance. Do not mutate caller config or shared schema/default tables during application.
- Component lifecycle is `New`/`OnCreate`, repeatable `Apply`/`OnApply`, `SetEnabled`, then `Release`/`OnRelease`. Applying the same config twice must be safe. Release must remove pending work and callbacks as applicable; released instances must not be used again.
- Use `Config:SetUnitValue`/`SetThemeValue`, settings stores (`Config:UnitStore`, ClickGrid's `Config.settings/styles/bindings`) and existing events rather than bypassing refresh or writing saved tables directly. Profile changes, theme changes, resets and toggles must update both live widgets and previews.
- Style is stored in AceDB `UnitFramesDB`; positions are separate, per Edit Mode layout. **Copy player settings** is a one-time independent copy of effective style, accounting for different unit defaults, excluding positions and player-only XP. Preserve theme inheritance where possible.
- When rebinding oUF, disable/re-enable elements if their widgets or prediction sub-widgets change. Updating only an element field can leave stale subscriptions. A driver's `bind` returns a signature of whatever oUF reads on enable (sub-widgets, modes); `Units.SetElement` re-enables the element when it changes.

## Secret values and protected frames

- Never do Lua arithmetic, comparisons, truth tests on secret booleans, table indexing/keying, or string parsing on live opaque unit values. Use native secret-aware StatusBars, duration objects, formatters, colour curves and prediction calculators. Arithmetic on deliberately plain sample values is fine.
- Prefer existing capability checks in `ns.Caps` for optional APIs. Do not add blanket `pcall` fallbacks that conceal incorrect API usage; the aura restyling path has a specific exception for denied access to existing buttons.
- oUF owns secure unit buttons, targeting/menu clicks, visibility watches and unit updates. Use its current unit token (`frame.__unit`) and lifecycle instead of recreating these systems. Target-of-target uses oUF polling; pet visibility/replacement updates come from oUF's pet handling.
- Respect combat lockdown. Defer protected position changes and restricted aura restyling through `ns.AfterCombat` (runs on `PLAYER_REGEN_ENABLED`); do not manipulate protected Blizzard scripts/anchors as a workaround.

## Regression-sensitive behaviour

### Auras

- Real auras use native `AuraContainer`/`CustomAuraContainerTemplate` and custom aura buttons. Blizzard owns selection, sorting, timers, counts and secret-aware dispel colouring. Buffs and debuffs have independent containers and placement settings.
- Native aura dimensions can be secret even outside combat. Never read them for addon layout arithmetic, attach an addon `OnSizeChanged` calculation, or propagate their bounds into ordinary host layout. Use known configured icon sizes and `Backdrop.ApplyToFixedSize` for icon backdrops.
- Restyling borders, duration placement and fonts must work immediately in any toggle order. Keep the artwork square; below-icon time text adds layout room, inside text does not. Centre alignment centres the whole aura block, not each wrapped row.
- Duration formatting uses a native seconds formatter with whitespace stripped (`3m`, not `3 m`); do not post-process a live secret duration string in Lua.
- Dispel tint applies to all eight border pieces through registered `PreserveAsset` textures and the custom colour map. Re-register after backdrop application, which resets vertex colours; inbound options are copied, not shared. Toggle the holder frame rather than fighting engine-controlled texture visibility/colour.
- `AuraContainer:SetUnit(nil)` asserts. Release by disabling containers and clearing pending restyles, not by setting a nil unit.
- Sample previews include buff/debuff counts, stacks, permanent buffs and all four dispel types. Keep sample styling aligned with real icons; static timers stay frozen and animated timers cycle.

### Health and shields

- Both shield placements must remain visible at full health. **Overlay health** grows inward from the bar's end without shrinking the health fill. **After health** reserves space inside the bar using native `Enum.UnitMaximumHealthMode.WithAbsorbs` when shields are enabled; otherwise use `Default`.
- Preserve `Enum.UnitDamageAbsorbClampMode.MaximumHealth`. Update both the oUF options and an already-created prediction calculator when restyling.
- An appended shield anchors directly after the health fill (`appendToFill`), not after incoming heals. Health text/percentages still use actual maximum health, not the combined health-plus-shield display scale.
- The default shield colour is blue to contrast with white priest health bars; keep user colour overrides. Verify full-health and damaged-health cases in both live bindings and previews, including disabling/re-enabling shields.

### Edit Mode, fonts and borders

- Snapping respects Blizzard's **Snap** and **Show grid** controls and uses private read-only geometry adapters around native magnetism. Do not insert addon objects into Blizzard's shared `magneticFrames` table. Snapped positions remain independent UIParent-relative coordinates, not linked anchors.
- Forever requires an empty string for no font outline, not `"NONE"`; use `Media:Outline`. Fonts are preloaded through Font objects; preserve existing fallbacks and use `Media:GetFontObject` where menu FontStrings forbid `SetFont`.
- Current borders use `BackdropTemplate`/`SetBackdrop` with LibSharedMedia edge files; `"None"` resolves to no texture, not an empty-string backdrop texture. `UnitFrames Pixel` is the existing flat-border option.
- Modern Blizzard unit-frame artwork is often an atlas, not a drop-in backdrop edge file. Confirm asset availability and rendering compatibility before adding it. Third-party border artwork requires licence/permission checks before bundling; prior resource discussions are not authorization to copy assets.

## Verification

Run from the repository root:

```sh
luajit tests/run.lua
luajit tests/run.lua shields
luajit tests/run.lua workbench
```

- The optional filter matches **spec filenames**, not individual test names. The runner includes addon Lua syntax checks. No external busted installation is needed.
- `tests/helpers.lua` loads TOCs into a fresh mocked client; `tests/mock/wow.lua` includes fake secrets and `tests/mock/ouf.lua` supplies the usual oUF stand-in. Some specs exercise embedded oUF paths explicitly.
- The mock is held to the client API through `tests/fixtures/api_snapshot.lua`, generated from Blizzard's API documentation and Lua source by `luajit scripts/api-snapshot.lua` (regenerate after adding API usage or updating the source checkout, and review the diff). `tests/mock/api.lua` enforces it on every mock call: undocumented widget methods, rejected arguments, secrets passed where addon (tainted) code may not pass them, and protected calls in combat raise errors. `tests/spec/api_contract_spec.lua` checks the mock's functions, methods, enums, restricted secret returns and our event names, and that the snapshot is current when the source checkout exists.
- Specs simulating Blizzard secure code or engine state use `Mock.SecureDelegate`/`Mock.RunUntainted` (secure delegates such as `UnitFrameUtil.UpdateUnitPvPIndicator`) and `Mock.SetEngineSize` (engine-given, possibly secret dimensions) instead of calling addon-facing APIs with values addon code could not pass.
- Add regression tests for fixes. Keep mocks faithful to native assertions/restrictions; do not weaken a mock simply to make a broken implementation pass. Add new mock API from the snapshot, not from memory.
- Offline mocks cannot prove rendering, taint safety or combat behaviour. For visual/lifecycle changes, report what still needs in-game verification: Workbench entry switching/release, repeated toggles, sample/live sources, real combat, unit disappearance/replacement, full-health shields, and Edit Mode as relevant.
- Do not hard-code a historical passing-test count as a requirement; report the current run's result.

## Local installation

- Default client AddOns directory: `/mnt/data02/Games/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/`. `scripts/install.sh` supports `WOW_DIR` overrides; validate the actual target before deploying.
- **`scripts/install.sh` removes each existing targeted addon directory before copying/linking; `--uninstall` removes it as well.** Do not run it casually. SavedVariables under `WTF/` are retained, but other files in those addon folders are replaced.
- For an authorized incremental deployment, prefer `rsync -ai UnitFrames/ "<validated AddOns directory>/UnitFrames/"` and the equivalent command for changed companion addons, without `--delete`. Check symlink targets first and use `rsync -anic` to verify copied contents. This does not remove stale files; intentional removal needs separate, validated handling.
- Request the required filesystem approval when installing outside the workspace. Never edit SavedVariables or unrelated installed addons as part of routine deployment.
- `/reload` normally picks up changed Lua. Restart the client for new TOC-listed files or new media/font assets. State clearly whether changes were installed or only edited/tested in the repository.
