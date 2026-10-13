# UnitFrames settings guide

A detailed reference for the settings available in game. For a quick
introduction, see the [main README](README.md). For setup and implementation,
see the [developer guide](DEVELOPMENT.md).

## Open settings

In game: `/uf wb` opens the Workbench.

Unit-frame settings group raid markers, PvP flags and classification markers
under **Icons**, and range, resting and ready checks under **State effects**.
The inspector remembers scrolling separately for each settings page.

With Titan Panel or another LibDataBroker display installed, enable its
**UnitFrames** launcher. Left-click the portrait icon to toggle the Workbench,
using the same load-on-demand handler as `/uf wb`. Registration also works
when the broker display loads after UnitFrames.

## Resting and ready checks

The player's **Resting border** slowly pulses from the configured frame border
colour to yellow while resting in an inn or city. It is enabled by default;
its colour and pulse duration (default four seconds) are configurable. A visible
frame border is required. Choose **Resting (zZz)** in a text slot's **Shows**
picker to display `zZz` while the player is resting, and empty text otherwise.
**Preview data > Resting** tests both effects: Static holds the resting colour,
while Animated pulses it. Resting is independent of accumulated rested XP.

During a ready check, each frame's bars turn grey while its unit has not
answered, then green (ready) or red (not ready). When the check ends, units
without an answer turn red; the result holds for two seconds, then fades back
to the normal bar colours over 1.5 seconds. The tint is drawn over the
bars, so class, reaction and health-gradient colours stay intact underneath.
Units outside the check stay untinted. The **Ready check icon** section
adds Blizzard's matching check mark (waiting, ready, not ready) to the frame's
icon groups, centred on the frame by default; it holds and fades with the
tints. The **Ready check** section has **Tint bars**, the three colours,
and the hold and fade durations shared by tints and icon.
**Preview data > Ready check** previews each state: Static holds it, while
Animated loops a whole check including the fade. ClickGrid member bars tint
the same way (Member bars > Ready check) and keep their own ready check icon,
which holds and fades with the tints; its **Preview data > Ready check**
shows a sample check with mixed answers.

## ClickGrid

**UnitFrames ClickGrid** is an optional companion for party/raid healing.
`/ufcg` opens its Workbench settings;
`/ufcg bindings` opens the click-spell matrix. It requires UnitFrames and uses
the same bar components, theme, inspector and Edit Mode integration.
See [the companion guide](UnitFrames_ClickGrid/README.md) for features, setup
and the in-game validation checklist. Blizzard party/raid frames are not
hidden by this experimental release.

## Frames, copying settings and positioning

**Unit frames** includes Player, Player pet, Target, Target of target, Focus,
and Focus target, each with independent saved settings and Edit Mode positions. Target sits opposite
the player, target-of-target beside the target, focus below the player, and
focus target beside the focus.
Frames support targeting and right-click menus. XP is only available on the
player frame.
Target and focus include castbars and auras; both target chains start compact,
with portrait, castbar, and auras off but available in its settings.
Player pet starts compact below/right of the player, with health, power,
shields and small aura icons. Portrait and castbar are available but off by
default. It hides when no pet exists and updates when you summon, dismiss or replace
your pet. Its preview shows
a friendly wolf with focus power; the same frame supports mana-based pets.
Their previews include distinct samples and NPC reaction/classification controls.
Each new frame's **General** section has **Copy player settings** to replace
its style with the player's current settings (including sizes and enabled
extras). This is an independent, one-time copy; positions and XP are excluded.
In Edit Mode, Blizzard's **Snap** checkbox also controls our frames. With
**Show grid** enabled they snap to its lines; they can also snap to visible
UnitFrames and highlighted Blizzard frame bounds, with red alignment guides
while dragging. Positions stay independent after snapping (no linked anchors).

## Absorb shields

Under each frame's **Health > Bar > Segments > Absorb shields**, **Enabled**
controls shield visibility and **Placement** defaults to **Overlay health**.
This draws shields inward from the bar's end, so they remain visible at full
health. **After health** reserves shield space inside the existing bar by
scaling it to maximum health plus shields; the shield starts at the health
fill's end. Health numbers and percentages still refer to actual health.
Shield colour defaults to blue to contrast with white priest health bars;
colour and texture are independently configurable. The standalone
Health bar preview has the same settings; set **Health %** to 100 to test.

## Text formats

The **Level + class** and **Level + class or creature type** text formats
include a small PvP flag after the text when the unit is flagged. The flag
shows Alliance, Horde (accounting for mercenary mode), or free-for-all PvP
and updates when the unit's faction/PvP state changes. Enable **Health >
Small text below left** to show the default level/class line. **Preview data >
PvP flag** lets you preview each flag or **Not flagged**.

### Custom text

Choose **Custom** in a text slot's **Shows** picker to build the text from up
to four pieces. Each piece shows one value (name, level, class, PvP flag,
health/power current, max, percent or missing, spell name, and on the player
frame XP and resting) with optional **Text before** and **Text after**. That
text appears only when its piece has a value, so put a separator on the piece
that may be missing: **Health: Missing** with before ` (-` and after `)`
shows nothing at full health. **While casting** can replace the whole text
with the spell name.

The first switch to **Custom** starts from the preset that was selected.
Switching back to a preset keeps your custom pieces for later; **Edit as custom
text** replaces them with a fresh copy of the selected preset. Custom pieces
drop their own spaces when their value is missing, unlike the presets, which
keep e.g. `42 ` for a unit without a known class. **Copy player settings**
switches off pieces the destination frame can't show (XP, resting) and keeps
the others in place.

## Portraits and cast bars

Under **Portrait > Rows to span**, choose **All rows** (the default) or
the first 1–4 visible rows from the top. Disabled rows are skipped; a castbar
in its own top/bottom row counts, while one over health does not. The span
stops at the last available row. Rows below the portrait use the full frame
width. **Width = 0** keeps the portrait square using the height of the rows
it spans; a fixed width is also supported on either side.

**Castbar > Placement > Replace portrait while casting** covers the portrait
until the cast finishes and fades out. It requires an enabled portrait and
adds no row. **Portrait cast layout** chooses a bar alone, or equal halves
for the spell icon and bar (side by side or top/bottom). **Bar > Orientation**
chooses horizontal or vertical fill; **Reverse fill** changes its direction.
Remaining time stays on the bar. Disable **Spell name > Enabled** if the
portrait is too small, and choose **Spell name while casting** or
**Level + class / spell name while casting** in a Health text slot's **Shows**
picker. The latter restores level/class when idle; a creature-type variant
is available for NPCs. These choices also work with channels and sample previews.

A castbar placed **Over the health bar** or replacing the portrait hides
what it covers while it shows and fades it back in as the cast fades out,
so a translucent out-of-range frame shows only the cast, not both layers.

## Raid markers, PvP flags and elite icons

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

Each frame's **PvP flag icon** section places the unit's PvP flag in the
same icon groups, enabled by default at the top-left border corner, after
the raid marker when both share an anchor. The game chooses the Alliance,
Horde (accounting for mercenary mode) or free-for-all art and its
visibility, so the flag updates safely in combat; an unflagged unit leaves
no gap. **Background circle** draws the flag on the default frames' dark
circle. **Preview data > PvP flag** previews each flag on the icon as well
as in the level/class texts. ClickGrid group bars do not include this icon.

The **Elite / rare icon** section adds the game's own classification
markers, enabled by default at the top-right border corner: a gold dragon
for elites and bosses, a silver dragon for rare elites and a star for rares,
matching Blizzard's nameplates. Other units show nothing and leave no gap.
It is placed like the raid marker and updates when the unit's classification
changes. Preview it with **Preview data > NPC** and **Classification**.

## Range fading

Each frame's **Out-of-range opacity** section offers an opt-in fade with
an opacity slider (0 = transparent, 1 = fully opaque; default 0.55).
**Group range** uses the game's group-member range check, normally 40 yards;
it cannot measure enemy targets. **Spell range** accepts a known spell's ID
or localised name and checks it against that frame's unit, including target,
focus and target-of-target. Choose a heal for friendly units or an attack for
enemies. Spell mode refreshes every 0.2 seconds while the frame is shown.
Missing/offline units, unknown spells and unavailable range checks stay fully
opaque. Range fading works in combat. The whole frame and its extras fade together;
you can still click the frame.
**Preview data > Out of range** lets you tune the fade in either sample mode.

## Buffs and debuffs

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

**Buff & debuff icon row** is a separate, optional row at the top or bottom
of the frame. Enable it alongside the external icons, or disable **Buffs &
debuffs** to use only the row. It has its own filters, limits and artwork settings.
It also appears in ClickGrid member and target styles.

**Icon width** sets the size of square artwork. Icons are centred vertically;
**Row height** crops the top and bottom when the art is taller than the row.
Timers and stack text sit inside the visible strip. The row fills from both
ends by default: choose the buff side, and debuffs occupy the opposite section.
Debuffs have their own **Fill from** control; **Opposite buffs** keeps inward
filling when the buff side changes. **Buff share of width** allocates space
between them. An empty enabled category keeps its
space; disabling it gives the other category the whole width. Icons too wide
for their section show none. Excess auras remain undisplayed until native
sorting selects them; this is not a first-in-first-out queue.

**Fade in new auras** uses Blizzard's native assignment animation, including
replacement on an already visible icon. Static previews stay still; animated
previews fade sample slot replacements. Time-left samples sort with permanent
auras last; native and raid-priority preview orders are illustrative. Bar icons
are non-interactive, so use external icons for tooltips and buff cancellation.

**Row background** adds a background texture, colour/opacity and optional border
behind the entire row, independently of the icon borders. It is off by default.

**Collapse into health when empty** (every unit frame and ClickGrid style,
on by default once the icon row is enabled) is experimental. The row sits
directly above or below the health bar; while it shows no icon, the row and the
gap disappear and the health bar grows into their space. The first icon shrinks
health again. Turn it off to keep a fixed row in its own place. Blizzard's own
aura layout decides this through anchors, so it also works in combat and the
secure unit button never changes size. Health texts and icons placed before
the name move with the bar. A castbar over the health bar covers the configured
health height, and a vertical health bar's prediction and shield bars keep that
height as their scale. Group previews include members without auras to show
both states.
