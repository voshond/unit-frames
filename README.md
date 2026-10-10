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

Player aura settings live under **Buffs & debuffs**. Each of the **Buffs** and
**Debuffs** sections has its own side, alignment, growth direction, gap,
offsets and row/column length. Buffs default to the top, debuffs to the bottom.
The parent section controls the font, separate duration/stack sizes, and
duration placement below or inside the icon. **Icon frame** styles each
individual icon border. Centre alignment centres the whole aura block;
use offsets to separate groups when placing both on the same side.

## Adding fonts

1. Copy a static `.ttf`/`.otf` (one file per weight) into `UnitFrames_Media/Fonts/`.
2. Add `{ "Name in the picker", "File.ttf" }` to the list in `UnitFrames_Media/Media.lua`.
3. `scripts/install.sh`, then restart the game client (new files need a restart, not `/reload`).
