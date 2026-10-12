# Third-party notices and release packaging

Original UnitFrames code and documentation are covered by the
[PolyForm Noncommercial License 1.0.0](LICENSE). Third-party components are
excluded from that license and retain their own terms, including commercial
permissions where applicable. A component's full license controls over the
summaries below. See [NOTICE.txt](NOTICE.txt) for copyright attribution,
license scope and the additional permission for LGPL compatibility. The
PolyForm license text is reproduced unchanged.

## Bundled components

| Component | Included in | License and notices |
|---|---|---|
| LibStub | UnitFrames, UnitFrames_Media | Public domain; preserve the credits in `Libs/LibStub/LibStub.lua`: Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel and joshborke. |
| CallbackHandler-1.0 | UnitFrames, UnitFrames_Media | Ace3 license; copyright (c) 2007, Ace3 Development Team. Full text in each addon's `Licenses/Ace3.txt`. |
| AceDB-3.0 | UnitFrames | Ace3 license; copyright (c) 2007, Ace3 Development Team. Full text in `UnitFrames/Licenses/Ace3.txt`. |
| LibSharedMedia-3.0 | UnitFrames, UnitFrames_Media | GNU LGPL 2.1; author Elkano, inspired by SurfaceLib by Haste/Otravi. Preserve the library's source header. Full LGPL and accompanying GPL text in each addon's `Licenses/`. |
| oUF | UnitFrames | MIT; copyright (c) 2006–2026 Trond A Ekseth and (c) 2016–2026 Val Voronov, Adrian L Lange and Rainrider. Full text in `UnitFrames/Libs/oUF/LICENSE.txt`. |
| LibEditMode | UnitFrames | Custom upstream license; copyright (c) 2022–2026 Adrian L Lange. Full text in `UnitFrames/Libs/LibEditMode/LICENSE.txt`. |
| Roboto Condensed Light, Regular, Medium and Bold | UnitFrames_Media | SIL Open Font License 1.1; copyright 2011 The Roboto Project Authors. Full text in `UnitFrames_Media/Fonts/RobotoCondensed-OFL.txt`; notices also appear in the font metadata. |

Ace3's license allows embedding but prohibits standalone redistribution
without prior written authorization. LibEditMode's license allows distribution
of the unmodified library as part of a WoW addon; its other redistribution and
naming conditions also apply. Do not describe either license as ordinary BSD
or MIT, or replace the full upstream notices with this summary.

LibSharedMedia is shipped as readable Lua source. Preserve that source and
allow users to modify or replace it. The additional permission in `NOTICE.txt`
permits modification for a user's own use and reverse engineering to debug LGPL library
modifications. Including GPL text alongside the LGPL does not put the original
UnitFrames code under the GPL.

## Client assets and optional external media

Blizzard Entertainment's icons, atlases, textures and client fonts are
referenced by path, atlas name or game-provided identifier. They are supplied
by the player's World of Warcraft client, not bundled as image or font files
by UnitFrames. No ownership or redistribution permission for those assets is
claimed. Do not extract or add client artwork to the release archive.

LibSharedMedia may expose media registered by other installed addons. Those
files are not part of this distribution and retain their owners' terms.
LibDataBroker, when available, is supplied by an external broker addon; it is
not bundled here.

## Preparing a release

- Include `LICENSE` and `NOTICE.txt` from every addon folder you distribute.
  Their copies must stay consistent with the repository's license and notices.
  Preserve the `Required Notice:` copyright line and the additional LGPL
  compatibility permission. Repository/source distributions also need the
  root `NOTICE.txt`.
- Include `Licenses/` in UnitFrames and UnitFrames_Media, all shipped library
  Lua/XML source and existing upstream license files in `Libs/`.
- Include `Fonts/RobotoCondensed-OFL.txt` whenever shipping the Roboto fonts.
- Preserve author, copyright and license headers. Mark any library
  modifications as required by its license; do not silently replace terms.
- Dependency refreshes must preserve these notices and be checked against the
  actual versions being released. Ace3 notice provenance is the pinned
  `40f4cc1356ae7fcc0cf71fc0a19dc7d50d6ae6c2` revision.
- Ship the addon folders, not the research/reference checkouts under
  `examples/` or the conversation history under `docs/`.

Upstream sources: [Ace3 license](https://github.com/WoWUIDev/Ace3/blob/40f4cc1356ae7fcc0cf71fc0a19dc7d50d6ae6c2/LICENSE.txt),
[LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0),
[oUF](https://github.com/oUF-wow/oUF/tree/14.2.0),
[LibEditMode](https://github.com/p3lim-wow/LibEditMode/tree/18),
[Roboto](https://github.com/googlefonts/roboto-3-classic),
[LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html).
