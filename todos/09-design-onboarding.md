# Design: Getting started (UnitFrames_Onboarding)

Status: draft; no implementation. Targets Forever Interface 16001 and Lua 5.1.
Mockups: `todos/09-onboarding/01-pick-a-look.svg` … `04-ready.svg` (generated, not pixel-exact).

## Goal

A first run that feels like a product, not a settings dump. In four short
steps a new user picks a look from live previews, nudges the few options that
change the feel most, chooses which frames exist, and leaves knowing where the
depth lives. Every step can be skipped; nothing is saved until **Apply**; the
old look stays one profile switch away.

## Packaging: its own load-on-demand addon

`UnitFrames_Onboarding/`, shipped with the others, independent of the Workbench:

```
## Interface: 16001
## Title: UnitFrames |cff4fa3ffGetting started|r
## Notes: A guided first setup with style presets. Open with /uf welcome.
## Dependencies: UnitFrames
## OptionalDeps: UnitFrames_Media, UnitFrames_ClickGrid
## LoadOnDemand: 1
```

No SavedVariables of its own. The "done" flag lives in the core's AceDB
`global.onboarding = { done = false }`, so the core decides whether to load it
without loading it. Turning the addon off in the AddOns list removes it
entirely: `C_AddOns.LoadAddOn` returns `false, "DISABLED"` (already in the API
snapshot) and the core stays silent instead of erroring.

Core touch points stay tiny (all in the always-loaded addon):

| Where | What |
| --- | --- |
| `Core/Config.lua` | `global.onboarding = { done = false }` default. |
| `Core/Commands.lua` | `ns:OpenOnboarding()` (load, then `UnitFrames.Onboarding:Open()`); `/uf welcome`. A disabled addon prints one hint line. |
| `Integration/Launcher.lua` | "Getting started" in the minimap right-click menu. |
| `Integration/Onboarding.lua` (new) | First-run trigger, below. |
| `Integration/SettingsPanel.lua` (new) | A minimal Blizzard Settings → AddOns category: version, "Open Workbench", "Getting started". This is the "via settings" entry; it costs a few frames, no options. |

The Workbench gets a "Getting started" button in its toolbar that calls
`UF:OpenOnboarding()`; no dependency between the two addons.

### First-run trigger

- **Fresh install** (`UnitFramesDB` was nil before `AceDB:New`): on
  `PLAYER_ENTERING_WORLD` with `isInitialLogin`, outside combat, open the
  wizard after a short delay (`C_Timer.After(2, …)`) so it doesn't fight the
  loading screen. In combat: wait for `PLAYER_REGEN_ENABLED` via `ns.AfterCombat`.
- **Existing install** without the flag: set `done = true` silently and print
  once: `New: /uf welcome walks you through presets.`
- Skip, Close and Apply all set `done = true`. Reopening is always manual.
- Entering combat while open hides the wizard (pending choices kept in memory),
  and it comes back on `PLAYER_REGEN_ENABLED` with a chat line if it was open.

## Visual language

Built only from `UF.Skin` colours and `UnitFrames/Media` glows, so it matches the
Workbench and needs no new art.

- **Backdrop:** a full-screen `UIParent` child at `FULLSCREEN_DIALOG`, black at
  55% alpha, mouse-enabled (clicks don't leak into the world). The world stays
  visible behind it, so the setup feels like it's happening in your game.
- **Window:** 1060×660, centred, `Skin.colors.window`, 1 px `border`, a 2 px
  accent line across the top, `GlowFrameSoft.tga` as a soft drop shadow. Esc
  closes it (`UISpecialFrames`), which counts as Skip.
- **Step rail (left, 230 px, darker):** small caps "UNITFRAMES", "Getting
  started", then four numbered nodes on a vertical line. The line's accent fill
  grows to the current step; the current node has a soft glow; finished nodes
  show a tick and are clickable to jump back. "Skip for now" and "Reopen:
  /uf welcome" sit at the bottom.
- **Type:** titles 26 px, body 13 px dim, labels 10 px small caps with letter
  spacing. Roboto Condensed through `Media:GetFontObject` when
  UnitFrames_Media is loaded, otherwise `GameFont*` objects.
- **Primary action:** one accent-filled button bottom right, labelled with the
  next step ("Next: tweaks →"). Back is a quiet outline button. A plain
  "Step n of 4" sits between them.
- **Motion** (AnimationGroups only, ~180 ms, smooth): step content slides 24 px
  and fades in; the rail line grows; a preset card scales to 1.03 on hover;
  previews cross-fade when the style changes. Nothing loops except the animated
  sample data.

## The four steps

### 1. Pick a look (`01-pick-a-look.svg`)

A big **stage** shows player (with castbar) and target, side by side and
animated: health waves, a cast filling, pending DoT stripes on the target. A
"Live preview · animated" pill sits bottom left; bottom right, a
Hostile / Friendly / Dead toggle flips the target's sample.

Under the stage, four **preset cards**, each with a mini player frame in its
own style, a name and two tags:

| Preset | Pitch | Tags |
| --- | --- | --- |
| Default | The shared style as shipped. | Balanced, 3D portraits |
| Minimal | Flat pixel border, class-coloured bars, no portraits, compact text. | Flat, No portraits |
| Classic | Bigger frames, portraits, chunky tooltip-style border, warmer colours. | Chunky, Gold trim |
| Healer | Wide health bars, deficit text, ClickGrid on when installed. | Wide bars, ClickGrid |

Clicking a card selects it (accent border, glow, tick) and cross-fades the
stage. Arrow keys move between cards; Enter goes on.

### 2. Make it yours (`02-make-it-yours.svg`)

The stage moves left and stacks player above target; a caption reads "Minimal
+ your tweaks". On the right are six controls drawn as **chips**, not dropdowns,
because you can see every option at once:

- **Font:** three curated faces, each chip rendered in its own font.
- **Bar texture:** four, from LibSharedMedia.
- **Border:** None / Pixel / Tooltip / Gold.
- **Health colour:** Class / Green / Gradient.
- **Portraits:** 3D / Class icon / Off.
- **Size:** a Compact ↔ Chunky slider that scales width and height together.

Each chip writes into the pending payload (theme or every unit) and restyles
the stage at once. The chip values are fixed lists in the presets file;
anything they don't cover is a Workbench job.

### 3. Your frames (`03-your-frames.svg`)

A **screen map**: a schematic of the game screen with ghost minimap and action
bars. Each frame is a tile at roughly its default position: Player, Pet,
Target, Target's target, Focus, Focus target, Castbar & GCD (amber), and
Party / Raid (green, ClickGrid; shown only when that addon is installed and
enabled). Click toggles; enabled tiles glow, disabled ones are dashed. Hovering
a tile highlights that frame in a small preview strip. A summary card reads
"6 frames on · 2 off". Tile positions are fixed artwork; real placement is
Edit Mode's job at the end.

### 4. Ready (`04-ready.svg`)

A centred glowing tick, "You're set.", and one line saying which profile now
holds the style ("Saved as the profile “Minimal”. Your old look is still one
click away in Profiles."). One accent button: **Place frames in Edit Mode**
(closes the wizard, opens Edit Mode).

Under it, "Dig deeper when you feel like it": six cards with a tinted icon
square, a title, one line and an arrow, each deep-linking into the Workbench
through `ns:OpenWorkbench(entryId)`:

| Card | Opens |
| --- | --- |
| Auras | `player` entry, auras page |
| Texts | `player` entry, text content page |
| Castbar & timers | castbar / timers entries |
| Party & raid | `clickgrid.panel` (hidden without ClickGrid) |
| Import a string | `profiles` entry |
| Everything else | Workbench at its last entry |

**Apply happens when Next is pressed on step 3**, so step 4 only shows the
result. A "Save as a new profile" checkbox (on by default) sits next to that
button.

## Data and application

`UnitFrames_Onboarding/Presets.lua` is pure data. Each preset is a style payload
in exactly the shape `Profiles` exports (`{ theme = {…}, units = { player = {…}, … }, clickgrid = {…}? }`)
plus `name`, `pitch`, `tags`, `profileName`. Chips and frame toggles are small
functions that write paths into a **copy** of the selected payload:
`pending = Util.Copy(preset.style)`.

Apply:

1. `local apply, dropped = UF.Profiles.kinds.style.prepare(pending)`: the same
   validation as string import. If it fails, show the reason inline and save nothing.
2. If "new profile" is ticked: `UF.Profiles:Create(uniqueName(preset.profileName))`,
   which keeps the current Edit Mode positions.
3. `apply()`; one `ThemeChanged` restyles the live frames and any open Workbench.
4. `global.onboarding.done = true`.

Expose `Profiles:Prepare(kind, data)` on the core rather than reaching into
`kinds`, so the onboarding addon uses a public seam.

## Previews without touching saved style

Preview frames come from `UF.Units:CreateFromDefinition(def, stage, unitConfig)`
with the pending unit config, and are applied with a resolved table built
against the pending theme:
`Schema.Resolve(Units:GetSchema(unit), cfg, Schema.Resolve(Theme.schema, pending.theme))`,
passed as `Component:Apply(config, resolved)`. Data comes from
`Units:ShowSample` with `Units:GetSample(unit)` plus a wave, the same way
`Entries/Units.lua` animates its samples. Previews are released on step change
and on close.

**Risk to verify first:** child components that call `ns.Config:GetTheme()`
themselves instead of using the passed `resolved` would show the live theme.
Audit `Component:ApplyChild` and the Backdrop, Text and Auras paths. If they
leak, add a scoped preview theme (e.g. `Component:SetThemeSource(fn)`)
instead of temporarily swapping the global theme.

## Files (each under 200 lines)

```
UnitFrames_Onboarding/
├── UnitFrames_Onboarding.toc
├── Init.lua          namespace, UnitFrames.Onboarding:Open/Close, combat hide
├── Presets.lua       four payloads + chip/toggle value tables
├── Pending.lua       pending payload, chip/toggle writers, Apply
├── Shell.lua         backdrop, window, rail, footer, step transitions
├── Preview.lua       sample frames from a payload, animate, release
├── Widgets.lua       Card, Chip, ChipRow, Tile, DigCard (on UF.Widgets.Widget)
└── Steps/
    ├── Look.lua
    ├── Tweaks.lua
    ├── Frames.lua
    └── Ready.lua
```

Plus `scripts/install.sh`, release packaging and `tests/helpers.lua` learning
the new TOC.

## Tests (`tests/spec/onboarding/`)

- Every preset payload passes style `prepare` with **zero dropped paths**, both
  with and without ClickGrid loaded.
- Every chip and toggle writes paths that `prepare` accepts.
- Apply with "new profile" creates and switches profiles and keeps positions;
  without it, the active style is replaced. A failed `prepare` writes nothing.
- Previews never change `Config` (snapshot before and after).
- First run: a fresh DB opens once; an existing DB only prints; done is never re-opened.
- Disabled addon: `ns:OpenOnboarding()` prints the hint and does not error.
- Opening, switching steps and closing release every preview frame.

## In-game checks offline mocks can't prove

Fresh SavedVariables auto-open after login; combat hides and restores it;
previews match what each preset applies; Esc counts as Skip; Edit Mode opens
from step 4; deep links land on the right Workbench pages; the addon disabled
in the AddOns list stays silent.

## Open questions

- Final preset contents: Classic's "gold trim" needs a border that's
  licence-clean and already shipped (AGENTS.md: no new third-party art).
- Should existing users ever get the wizard auto-opened (for example once, after a major version)?
- Do we want a fifth preset that's community-sourced (an import string shipped as data)?
