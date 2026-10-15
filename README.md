# UnitFrames

Customisable unit frames for **WoW Forever**. Make your health bars, portraits
and cast bars look the way you want, with built-in previews to help you see
each change.

## What you can do

- Style your player, pet, target, target's target, focus and focus target
  separately, or copy your player style to another frame.
- Choose fonts, colours, borders, bar sizes and portraits.
- Show health, power, absorb shields, cast bars, buffs and debuffs.
- Show rogue and druid combo points on the target frame, or on the player frame.
- Add a cropped buff/debuff icon row, alongside or instead of external icons.
- Add raid markers, PvP flags, elite and rare icons, and ready check indicators.
- Fade frames when someone is out of range.
- Move your frames in the game's Edit Mode, with snapping to help line them up.

## Make it yours

Type **`/uf wb`** in chat to open the settings window, called the **Workbench**.

Choose a frame under **Unit frames**, then adjust its appearance. The preview
lets you try things like low health, shields, buffs and ready checks without
waiting for them to happen in game. Use **Static** for a still preview or
**Animated** to see changes over time. Appearance changes also update your
actual frames.

To move frames, open the game's **Edit Mode**. If you want matching frames,
start with your player and use **Copy player settings** on the others.
You can still customise each one afterward.

See the [settings guide](USER_GUIDE.md) for individual options and examples.

## Optional: ClickGrid for healing

**ClickGrid** adds a party and raid panel where you can cast spells by clicking
group members. Choose your spells and mouse buttons, including combinations
with Shift, Ctrl and Alt.

It includes member targets, buffs and debuffs, role icons and ready checks.
You assign the healing spells yourself; if you use Clique, Clique handles
the clicks instead.

- `/ufcg` — open ClickGrid settings.
- `/ufcg bindings` — choose your click spells.
- `/ufcg on` or `/ufcg off` — enable or disable the panel.

The panel normally appears when you are in a group. Turn on **Show when solo**
in its settings to try it on your own. Move it through **Edit Mode**.

ClickGrid is experimental and leaves Blizzard's party and raid frames visible.
See the [ClickGrid guide](UnitFrames_ClickGrid/README.md) for more details.

## Getting started

Download the **UnitFrames-….zip** attachment from the
[Releases page](https://github.com/voshond/unit-frames/releases). Release ZIPs
include the supporting libraries and fonts; you do not need to download
those separately. If no release is listed yet, the first bundle has not
been published.

Extract the ZIP into your Forever client's `Interface/AddOns` folder. It
contains four addon folders: `UnitFrames`, `UnitFrames_Workbench`,
`UnitFrames_Media` and `UnitFrames_ClickGrid`. Keep the first two for frames
and settings. The extra fonts and ClickGrid healing panel are optional.

Restart the game, enable the addons on the character selection screen,
then type `/uf wb` to get started.

Use the attached **UnitFrames-….zip**, rather than GitHub's **Source code**
archives or **Download ZIP** button, which contain source without dependencies.

This addon is being developed for **WoW Forever**. Other WoW versions
have not been verified.

## Working on the addon?

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup, tests, the code map and
implementation notes.

For optional performance diagnostics, `/uf perf` reports loaded addon memory
and profiler metrics. `/uf perf watch 60` observes a bounded window;
`/uf perf cancel` stops it. Outside combat, `/uf perf measure units` actively
measures a unit refresh; `clickgrid`, `preview` and `schema` are also supported.
Diagnostics do not load Workbench and stay off until requested.

## License

Original UnitFrames code and documentation are source-available under the
[PolyForm Noncommercial License 1.0.0](LICENSE). You may use, share, modify and
reuse them for noncommercial purposes, retaining the license and attribution.
Uses outside the license's permitted purposes require separate written
permission from the author. See [NOTICE.txt](NOTICE.txt) for attribution,
license scope and the additional permission for LGPL compatibility.

Bundled libraries and Roboto fonts retain their own licenses. Blizzard artwork
is supplied by the game client. See [third-party notices](THIRD_PARTY_NOTICES.md)
for credits, license locations and release packaging requirements.
