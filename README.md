# UnitFrames

Modular unit frames for WoW Forever (Interface 16001). Design and research live in `docs/`.

| Folder | What |
|---|---|
| `UnitFrames/` | Core addon: components (Bar, Text, Backdrop, Castbar), widget toolkit, schema/config/theme |
| `UnitFrames_Workbench/` | Load-on-demand test mode and settings (`/uf wb`) |
| `UnitFrames_Media/` | Extra fonts (Roboto Condensed) for every LibSharedMedia font picker |
| `UnitFrames_ClickGrid/` | Experimental healing panel: party/raid groups, member targets, native auras and modifier click spells (`/ufcg`) |
| `tests/` | Offline tests (mocked WoW API, fake secret values) |
| `scripts/` | `install.sh`, `fetch-libs.sh` |

## Develop

```bash
scripts/install.sh          # copy all addons into the Forever client (or: --link, --uninstall)
luajit tests/run.lua        # offline tests + syntax check of all addon code
luajit tests/run.lua bar    # only spec files matching "bar"
scripts/fetch-libs.sh       # update the embedded libraries (UnitFrames/Libs/VERSIONS.md)
```

In game: `/uf wb` opens the Workbench.

The player's **Resting border** slowly pulses from the configured frame border
colour to yellow while resting in an inn or city. It is enabled by default;
its colour and pulse duration (default four seconds) are configurable. A visible
frame border is required. Choose **Resting (zZz)** in a text slot's **Shows**
picker to display `zZz` while the player is resting, and empty text otherwise.
**Preview data > Resting** tests both effects: Static holds the resting colour,
while Animated pulses it. Resting is independent of accumulated rested XP.

**UnitFrames ClickGrid** is an optional companion for party/raid healing.
`/ufcg` opens its Workbench settings;
`/ufcg bindings` opens the click-spell matrix. It requires UnitFrames and uses
the same bar components, theme, inspector and Edit Mode integration.
See [the companion guide](UnitFrames_ClickGrid/README.md) for features, setup
and the in-game validation checklist. Blizzard party/raid frames are not
hidden by this experimental release.

**Unit frames** includes Player, Player pet, Target, Target of target, Focus,
and Focus target, each with independent saved settings and Edit Mode positions. Target sits opposite
the player, target-of-target beside the target, focus below the player, and
focus target beside the focus.
The new frames use oUF's secure targeting/menu clicks and unit visibility;
target-of-target and focus target refresh through oUF's polling. XP remains player-only.
Target and focus include castbars and auras; both target chains start compact,
with portrait, castbar, and auras off but available in its settings.
Player pet starts compact below/right of the player, with health, power,
shields and small aura icons. Portrait and castbar are available but off by
default. Its secure pet unit watch hides it when no pet exists; summons,
dismissals and replacements use oUF's normal pet updates. Its preview shows
a friendly wolf with focus power; the same frame supports mana-based pets.
Their previews include distinct samples and NPC reaction/classification controls.
Each new frame's **General** section has **Copy player settings** to replace
its style with the player's current settings (including sizes and enabled
extras). This is an independent, one-time copy; positions and XP are excluded.
In Edit Mode, Blizzard's **Snap** checkbox also controls our frames. With
**Show grid** enabled they snap to its lines; they can also snap to visible
UnitFrames and highlighted Blizzard frame bounds, with red alignment guides
while dragging. Positions stay independent after snapping (no linked anchors).

Under each frame's **Health > Bar > Segments > Absorb shields**, **Enabled**
controls shield visibility and **Placement** defaults to **Overlay health**.
This draws shields inward from the bar's end, so they remain visible at full
health. **After health** reserves shield space inside the existing bar by
scaling it to maximum health plus shields; the shield starts at the health
fill's end. Health numbers and percentages still refer to actual health.
Shield colour defaults to blue to contrast with white priest health bars;
colour and texture are independently configurable. The standalone
Health bar preview has the same settings; set **Health %** to 100 to test.

The **Level + class** and **Level + class or creature type** text formats
include a small PvP flag after the text when the unit is flagged. The flag
shows Alliance, Horde (accounting for mercenary mode), or free-for-all PvP
and updates when the unit's faction/PvP state changes. Enable **Health >
Small text below left** to show the default level/class line. **Preview data >
PvP flag** lets you preview each flag or **Not flagged**.

Under **Portrait > Rows to span**, choose **All rows** (the default) or
the first 1–4 visible rows from the top. Disabled rows are skipped; a castbar
in its own top/bottom row counts, while one over health does not. The span
stops at the last available row. Rows below the portrait use the full frame
width. **Width = 0** keeps the portrait square using the height of the rows
it spans; a fixed width is also supported on either side.

Each frame's **Raid target icon** section controls its marker, enabled by
default at the top border. Choose any of the eight border anchors to centre
the icon on that edge or corner, so it extends outside the frame, or the
frame centre. The two **Inside portrait** anchors keep it within the
bottom-left or bottom-right corner and hide it when the portrait is off.
Icons sharing an anchor (such as ClickGrid's status icons) form one group
that leaves no gap for absent icons: edges and the centre keep the group
centred, border corners grow inward. **Order** sets its place in the group
and **Gap to next icon** the spacing after it. Size and horizontal/vertical
offsets are independent per frame; offsets nudge only this icon, and
positive offsets move right/up. Portrait icons shrink to fit small portraits;
offsets can deliberately move them outside. **Preview data > Raid target marker** offers all eight markers and
None. Live markers follow the unit's raid target assignment automatically.

Each frame's **Out-of-range opacity** section offers an opt-in fade with
an opacity slider (0 = transparent, 1 = fully opaque; default 0.55).
**Group range** uses the game's group-member range check, normally 40 yards;
it cannot measure enemy targets. **Spell range** accepts a known spell's ID
or localised name and checks it against that frame's unit, including target,
focus and target-of-target. Choose a heal for friendly units or an attack for
enemies. Spell mode refreshes every 0.2 seconds while the frame is shown.
Missing/offline units, unknown spells and unavailable range checks stay fully
opaque. Range results go straight through native secret-aware opacity setters
so updates can run in combat without Lua inspecting the range booleans.
The whole frame and its extras fade together; its secure clicks remain intact.
**Preview data > Out of range** lets you tune the fade in either sample mode.

Aura settings live under **Buffs & debuffs**. Each of the **Buffs** and
**Debuffs** sections has its own side, alignment, growth direction, gap,
offsets and row/column length. Buffs default to the top, debuffs to the bottom.
Right-click a buff on the live player frame to cancel it, if the game permits
removing that buff. Sample preview icons remain non-interactive.
The parent section controls the font, separate duration/stack sizes, and
duration placement below or inside the icon. **Icon frame** styles each
individual icon border. Centre alignment centres the whole aura block;
use offsets to separate groups when placing both on the same side.
**Debuff border colours** customises the full frame tint for magic, curse,
disease, poison, and debuffs without a dispel type. Turn off **Colour debuff
border by type** to use **Icon frame > Border colour** for every icon.

**Preview data** includes sample buff/debuff counts. Static previews freeze
their timers; Animated previews cycle them. Samples include stacks, a
permanent buff, and all four debuff dispel types, using the saved aura style.

## Component and preview structure

Components own their children explicitly with `Own`; releasing a composition
releases its children and pending work. Theme refresh applies at composition
roots, while runtime bindings manage their own refresh. Keep visual components
independent of oUF and feed sample values through the shared row writers in
`Units/Rows.lua`; non-oUF live previews use its calculator-based live writers.

A unit frame's optional parts (portrait, castbar, auras, raid target) are
declared once in `UnitFrame.PARTS`; edge icons, including companions', join
the frame's `DecorationStack` (`UnitFrame:GetDecorations()`); the Units layer keeps one oUF binding and
one sample feeder per part key, and Edit Mode quick settings read the unit
schema. Derive new definitions with `Units:Derive`, overriding rows by key.

Settings are written through stores (`Core/Store.lua`): set, replace and reset
in one place with optional validation and one change event, plus a derived
inspector target. Work blocked by combat goes through the ordered
`Core/AfterCombat.lua` queue; casts for unit frames and live previews share
`Units/Cast.lua`.

`BuildSchema` and `UnitFrameLayout.Compute` build settings and measure unit
geometry without creating frames. Decorations use `GetLayoutContext` for
configured portrait bounds rather than reading native artwork dimensions.
Flowing auras and ClickGrid's fixed slots share `Components/AuraIcon.lua`, but
retain their separate selection, container and lifecycle policies.

Workbench separates its controller (`Workbench.lua`), presentation (`View.lua`),
settings navigation (`Sections.lua`) and active preview lifetime
(`PreviewSession.lua`). A session owns its data cache, callbacks and teardown;
cached inspector pages dispatch through their current target. Entries declare
the events that restyle them (`refreshOn`) and build handles with
`Workbench.Composite` or `Workbench.ComponentHandle`.

## Adding fonts

1. Copy a static `.ttf`/`.otf` (one file per weight) into `UnitFrames_Media/Fonts/`.
2. Add `{ "Name in the picker", "File.ttf" }` to the list in `UnitFrames_Media/Media.lua`.
3. `scripts/install.sh`, then restart the game client (new files need a restart, not `/reload`).
