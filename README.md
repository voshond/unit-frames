# UnitFrames

Customisable unit frames for **WoW Forever**. Make your health bars, portraits
and cast bars look the way you want, with built-in previews to help you see
each change.

## What you can do

- Style your player, pet, target, target's target, focus and focus target
  separately, or copy your player style to another frame.
- Choose fonts, colours, borders, bar sizes and portraits.
- Show health, power, absorb shields, cast bars, buffs and debuffs.
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

UnitFrames is still in development, and there is no ready-to-install release
download yet. GitHub's **Download ZIP** contains source code; it needs the
supporting libraries described in the [developer guide](DEVELOPMENT.md)
before it can be installed.

If you already have a complete copy, put the `UnitFrames` and
`UnitFrames_Workbench` folders in your Forever client's `Interface/AddOns`
folder. You can also add `UnitFrames_Media` for extra fonts and
`UnitFrames_ClickGrid` for the healing panel.

Restart the game, enable the addons on the character selection screen,
then type `/uf wb` to get started.

This addon is being developed for **WoW Forever**. Other WoW versions
have not been verified.

## Working on the addon?

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup, tests, the code map and
implementation notes.

## License

Original UnitFrames code and documentation are source-available under the
[UnitFrames Noncommercial License](LICENSE). You may use, share, modify and
reuse them for noncommercial purposes, retaining the license and attribution.
Commercial use requires separate written permission from the author.

Bundled libraries and Roboto fonts retain their own licenses. Blizzard artwork
is supplied by the game client. See [third-party notices](THIRD_PARTY_NOTICES.md)
for credits, license locations and release packaging requirements.
