# UnitFrames

Modular unit frames for WoW Forever (Interface 16001). Design and research live in `docs/`.

| Folder | What |
|---|---|
| `UnitFrames/` | Core addon: components (Bar, Text, Backdrop, Castbar), widget toolkit, schema/config/theme |
| `UnitFrames_Workbench/` | Load-on-demand test mode and settings (`/uf wb`) |
| `UnitFrames_Media/` | Extra fonts (Roboto Condensed) for every LibSharedMedia font picker |
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

**Unit frames** includes Player, Target, Target of target, and Focus, each
with independent saved settings and Edit Mode positions. Target sits opposite
the player, target-of-target beside the target, and focus below the player.
The new frames use oUF's secure targeting/menu clicks and unit visibility;
target-of-target refreshes through oUF's polling. XP remains player-only.
Target and focus include castbars and auras; target-of-target starts compact,
with portrait, castbar, and auras off but available in its settings.
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

Aura settings live under **Buffs & debuffs**. Each of the **Buffs** and
**Debuffs** sections has its own side, alignment, growth direction, gap,
offsets and row/column length. Buffs default to the top, debuffs to the bottom.
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

## Adding fonts

1. Copy a static `.ttf`/`.otf` (one file per weight) into `UnitFrames_Media/Fonts/`.
2. Add `{ "Name in the picker", "File.ttf" }` to the list in `UnitFrames_Media/Media.lua`.
3. `scripts/install.sh`, then restart the game client (new files need a restart, not `/reload`).
