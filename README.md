# UnitFrames

Modular unit frames for WoW Forever (Interface 16001). Design and research live in `docs/`.

| Folder | What |
|---|---|
| `UnitFrames/` | Core addon: components (Bar, Text, Backdrop, Castbar), widget toolkit, schema/config/theme |
| `UnitFrames_Workbench/` | Load-on-demand test mode: shows components with fake or live data |
| `tests/` | Offline tests (mocked WoW API, fake secret values) |
| `scripts/` | `install.sh`, `fetch-libs.sh` |

## Develop

```bash
scripts/install.sh          # copy both addons into the Forever client (or: --link, --uninstall)
luajit tests/run.lua        # offline tests + syntax check of all addon code
luajit tests/run.lua bar    # only spec files matching "bar"
scripts/fetch-libs.sh       # update the embedded libraries (UnitFrames/Libs/VERSIONS.md)
```

In game: `/uf wb` opens the Workbench.
