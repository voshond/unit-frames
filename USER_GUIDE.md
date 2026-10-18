# UnitFrames settings guide

A detailed reference for the settings available in game. For a quick
introduction, see the [main README](README.md). For setup and implementation,
see the [developer guide](DEVELOPMENT.md).

## Open settings

In game: `/uf wb` opens the Workbench.

The sidebar groups settings under **Unit Frames**, **Cast Bar & Swing Timers**,
**Global Settings**, **Party & Raid** (when ClickGrid is loaded), **Profiles**,
and **Developer Tools** (development builds). **Global Settings** directly exposes
**Fonts**, **Bars, Borders & Backgrounds**, and **Colours**.

Choose a frame in the sidebar, then a feature such as **Health & Shields**,
**Buffs & Debuffs** or **Indicators & States**. The **Section** selector opens
related controls, including individual text slots. Each section remembers its
scroll position and whether **Detailed adjustments** is expanded. This toggle
appears only when the section has available horizontal or vertical offsets.
Text-slot labels include their current content. **Related Settings** links cast
bars, portrait overlays and status text to their existing controls. **Buffs &
Debuffs** includes an **Overview** with links to each independent display.

Search all settings at the top of the window. Results include their frame,
feature and scope; use Up/Down and Enter to open one, or Escape to close the
results. **Search scope** can restrict results to the current frame/page or
include preview/developer destinations. Opening a result never runs an action.
Hidden settings explain known prerequisites and link to the controlling field.
Returning to search preserves the results, selection and scroll position until
the query or scope changes. Preview results have a separate **Preview Only —
Simulation** heading and appear only when included through **Search scope**.

Settings apply immediately. The scope header identifies the affected frames;
source labels distinguish custom values, frame defaults, shared appearance and
built-in defaults. The reset icon restores the inherited/default value, and
**Edit shared default** opens the corresponding setting in **Global Settings**.

**Preview only** contains simulation controls. **Preview zoom** and
**Preview background** affect the preview; **Show preview** restores it when
collapsed. Narrow windows collapse the preview automatically until you choose
a preference. Profile sharing and click spells keep their specialised editors.

With Titan Panel or another LibDataBroker display installed, enable its
**UnitFrames** launcher. Left-click the portrait icon to toggle the Workbench,
using the same load-on-demand handler as `/uf wb`. Registration also works
when the broker display loads after UnitFrames.

## Resting and ready checks

Choose **Blizzard Raid** in a border selector to use Blizzard's native raid
border artwork. Border size 16 uses the original dimensions; try 8 for smaller
unit frames. Border colour tints the artwork, so white shows its original colour.

Frame and panel borders draw above their content, with the background behind
it. **Background inset** pulls in only the background; **Content padding**
reserves space inside the frame. At the top of the border section, enable
**Content padding per side** to set left,
right, top and bottom spacing independently. **Background inset per side**
provides the same four controls for the background, without moving content.
Aura spacing keeps its existing controls.

The player's **Resting border** slowly pulses from the configured frame border
colour to yellow while resting in an inn or city. It is enabled by default;
its colour and pulse duration (default four seconds) are configurable. A visible
frame border is required. Choose **Resting (zZz)** in a text slot's **text content**
picker to display `zZz` while the player is resting, and empty text otherwise.
**Preview only > Resting** tests both effects: Static holds the resting colour,
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
**Preview only > Ready check** previews each state: Static holds it, while
Animated loops a whole check including the fade. ClickGrid member bars tint
the same way (**Indicators & states > Ready check tints & icon — Member style**) and keep their own ready check icon,
which holds and fades with the tints; its **Preview only > Ready check**
shows a sample check with mixed answers.

While a unit is dead or a ghost, its frame takes on a ghostly look, enabled by
default under **Indicators & states > Dead & ghost**. Bars, 2D and class
portraits, the border and texts turn greyscale and blend towards the blue-grey
**Ghost colour** at the configured **Strength**; 3D portraits only turn
greyscale. Bar fills are painted in one uniform ghost colour, so class and
power colours no longer show through; the health bar shows it across its
whole length instead of an empty or 1 health fill. Each of the four targets has its own
toggle. A ready check tint draws over the look and fades back to it, and
ClickGrid's green resurrection text still shows on top. **Preview only >
Offline / dead > Dead** previews it; the ClickGrid preview shows members 3 and 5
dead.

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
Target and focus offer castbars and auras; both target chains start compact,
with portrait, castbar, and auras off but available in its settings.
Player pet starts compact below/right of the player, with health, power,
shields and small aura icons. Portrait and castbar are available but off by
default. It hides when no pet exists and updates when you summon, dismiss or replace
your pet. Its preview shows
a friendly wolf with focus power; the same frame supports mana-based pets.
Their previews include distinct samples and NPC reaction/classification controls.
Each other frame's **Layout & border** page has **Copy player style** to replace
its style with the player's current settings (including sizes and enabled
extras). This is an independent, one-time copy; positions and XP are excluded.
In Edit Mode, Blizzard's **Snap** checkbox also controls our frames. With
**Show grid** enabled they snap to its lines; they can also snap to visible
UnitFrames and highlighted Blizzard frame bounds, with red alignment guides
while dragging. Positions stay independent after snapping (no linked anchors).

## Profiles and sharing

Each character gets a profile of its own, named after it. On first load a
character moves from the shared **Default** profile to a copy of it, so
nothing changes visibly; new characters start from a copy of **Default**.
**Profiles > Profiles & sharing** manages your profiles in the settings column:
switch the **Active profile**, create one from a **New profile name** (default
style), or **Copy style from** another profile. Tick **Allow delete and reset**
to show **Delete profile** and **Reset active profile**; the tick clears after
each use. These change style only: the active profile keeps its Edit Mode
positions, and switching moves frames to that profile's own positions.

The preview area shares profiles as text. **Export style** puts a string in
the box (press Ctrl+C to copy it). It holds the global theme, every unit
frame's style and, with ClickGrid loaded, its panel and bar styles. Paste a
string and press **Import** to replace the active profile's style, or enter a
name first to import it as a new profile. Positions are never exported or
imported. Damaged or foreign strings change nothing; settings this version
doesn't know, or with invalid values, are skipped and listed.

**Export ClickGrid click bindings** is a separate string. Importing it replaces
the bindings of your current specialization; it is refused for another class.
**Export all settings** combines the style and the click bindings in one
string; importing it skips bindings made for another class and still imports
the style.
Addons and setup tools can use `UnitFrames:ExportProfile()`,
`UnitFrames:ImportProfile(text[, newProfileName])`, `UnitFrames:SetProfile(name)`,
`UnitFrames:GetProfileKeys()` and `UnitFrames:GetCurrentProfile()`.

## Absorb shields

Under each frame's **Health & shields > Shields**, **Show Absorb shields**
controls shield visibility and **Shield placement** defaults to **Overlay health**.
This draws shields inward from the bar's end, so they remain visible at full
health. **After health** reserves shield space inside the existing bar by
scaling it to maximum health plus shields; the shield starts at the health
fill's end. Health numbers and percentages still refer to actual health.
Shield colour defaults to blue to contrast with white priest health bars;
colour and texture are independently configurable. The standalone
Health bar preview has the same settings; set **Health %** to 100 to test.

## Overheal edge

**Health > Bar > Overheal > Show overheal** (off by default) lights the end of
the health bar while incoming healing goes past full health. It steps up with
the size of the overheal: a fade painted into the bar's end plus Blizzard's
raid frame shield overflow glow, reaching further and glowing brighter once the
heal passes full health, then 25% and 50% of maximum health past it.
**Levels** chooses how many of those steps to show (each costs one more heal
prediction per update), **Length** how far the strongest one reaches, plus
**Colour** (with opacity) and **Edge glow**. It works in combat and on every
unit and ClickGrid member bar; the ClickGrid preview shows one, two and three
levels on members 1, 4 and 5. In the Health bar preview, set **Health %** and
**Incoming heals %** to add up to more than 100, 125 or 150.

## Text formats

**Character name** shows the unit's name without its Forever surname.
**Full name** adds the last name with a space, when present. **Last name**
is also available as a **Custom** text piece. Put any separator in that
piece's **Text before** so it disappears when the unit has no last name.

The **Level + class** and **Level + class or creature type** text formats
include a small PvP flag after the text when the unit is flagged. The flag
shows Alliance, Horde (accounting for mercenary mode), or free-for-all PvP
and updates when the unit's faction/PvP state changes. Enable **Health & shields > Small text below left** to show the default level/class line. **Preview only >
PvP flag** lets you preview each flag or **Not flagged**.

### Custom text

Choose **Custom** in a text slot's **text content** picker to build the text from up
to four pieces. Each piece shows one value (name, last name, level, class, creature
type, PvP flag, **Offline / dead**, health/power current, max, percent, missing
or missing percent, spell name, and on the player frame XP and resting) with
optional **Text before** and **Text after**. Current and max take a **Number
style** (short `12.3K`, full `12,345` or plain `12345`), percentages one
optional decimal. **This bar** values show whichever bar the text is on, so
the same choice works on health, power and XP bars and ClickGrid; the **This
bar** presets in **text content** do the same. That
text appears only when its piece has a value, so put a separator on the piece
that may be missing: **Health: Missing** with before ` (-` and after `)`
shows nothing at full health. Missing values are whole numbers so that they
can disappear at zero. **While casting** can replace the whole text with the
spell name. **Preview only > Offline / dead** previews the status text.

The first switch to **Custom** starts from the preset that was selected.
Switching back to a preset keeps your custom pieces for later; **Edit as custom
text** replaces them with a fresh copy of the selected preset. Custom pieces
drop their own spaces when their value is missing, unlike the presets, which
keep e.g. `42 ` for a unit without a known class. **Copy player style**
switches off pieces the destination frame can't show (XP, resting) and keeps
the others in place.

## Portraits and cast bars

Castbars and the player's experience bar start disabled. Use their **Enabled**
checkboxes to turn them on. **Castbar > Placement** chooses where an enabled
castbar appears; turning it off keeps that placement for next time.

Under **Portrait > Rows to span**, choose **All rows** (the default) or
the first 1–4 visible rows from the top. Disabled rows are skipped; a castbar
in its own top/bottom row counts, while one over health does not. The span
stops at the last available row. Rows below the portrait use the full frame
width. **Width = 0** keeps the portrait square using the height of the rows
it spans; a fixed width is also supported on either side. In a wide or tall
portrait, 2D portraits and class icons keep their proportions: the artwork
fills the portrait and is trimmed evenly at the edges instead of stretched.

**Castbar > Placement > Replace portrait while casting** covers the portrait
until the cast finishes and fades out. It requires an enabled portrait and
adds no row. **Portrait cast layout** chooses a bar alone, or equal halves
for the spell icon and bar (side by side or top/bottom). **Bar > Orientation**
chooses horizontal or vertical fill; **Reverse fill** changes its direction.
Remaining time stays on the bar. Disable **Spell name > Enabled** if the
portrait is too small, and choose **Spell name while casting** or
**Level + class / spell name while casting** in a Health text slot's **text content**
picker. The latter restores level/class when idle; a creature-type variant
is available for NPCs. These choices also work with channels and sample previews.

A castbar placed **Over the health bar** or replacing the portrait hides
what it covers while it shows and fades it back in as the cast fades out,
so a translucent out-of-range frame shows only the cast, not both layers.

## Standalone castbar and swing timers

Choose **Cast bar & swing timers** in the Workbench and turn on
**Enabled** to add a separate player timer frame. It starts disabled and
has its own width, row spacing and style. Move it in Edit Mode; its position
is saved separately for each layout. Edit Mode shows a frozen sample.

The cast row supports the same spell icon, channel behaviour, latency zone,
GCD strip, colours and finish fade as the attached player castbar. The two
castbars have independent settings and can both be enabled. Blizzard's player
castbar returns when the attached player castbar is disabled and the standalone
cast row is disabled or set to Hidden.

Enable **Main hand**, **Off hand** or **Ranged** to add swing rows beneath the
castbar. Each row has its own height, texture, colour and text style. Disabled
rows collapse; enabled rows keep their layout space when hidden. Each row,
including the castbar, has a **Visibility** setting: **While active** (the
default), **Always**, **In combat** or **Hidden**. Always and In combat show
an empty bar while idle; sparks only appear during an active timer. The
Workbench's sample **In combat** toggle previews combat visibility, while
Edit Mode shows all enabled rows for positioning. Swing progress
starts with the next native player swing event and returns to empty when
the timer ends. Weapon changes clear old timers. A weapon slot without a
weapon stays empty. Restricted timing values cannot be displayed and clear
the affected row. Blizzard's own swing timer settings remain independent.

Use **Static**, **Animated** or **Live: player** in Preview only. Static and
animated samples remain visible even while the standalone feature is off;
live previews wait for actual swings. Appearance edits apply to the real
frame immediately. Profiles, share strings and Reset include these settings;
style imports and resets preserve Edit Mode positions.

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
offsets can deliberately move them outside. **Preview only > Raid target marker** offers all eight markers and
None. Live markers follow the unit's raid target assignment automatically.

Each frame's **PvP flag icon** section places the unit's PvP flag in the
same icon groups, enabled by default at the top-left border corner, after
the raid marker when both share an anchor. The game chooses the Alliance,
Horde (accounting for mercenary mode) or free-for-all art and its
visibility, so the flag updates safely in combat; an unflagged unit leaves
no gap. **Background circle** draws the flag on the default frames' dark
circle. **Preview only > PvP flag** previews each flag on the icon as well
as in the level/class texts. ClickGrid group bars do not include this icon.

The **Elite / rare icon** section adds the game's own classification
markers, enabled by default at the top-right border corner: a gold dragon
for elites and bosses, a silver dragon for rare elites and a star for rares,
matching Blizzard's nameplates. Other units show nothing and leave no gap.
It is placed like the raid marker and updates when the unit's classification
changes. Preview it with **Preview only > NPC** and **Classification**.

The player frame's **Resting icon** section adds the default player frame's
animated zZz while you are resting in an inn or city, enabled by default at
the top-left border corner after the PvP flag. It is placed like the raid
marker and leaves no gap while you are not resting. Preview it with
**Preview only > Resting**.

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
**Preview only > Out of range** lets you tune the fade in either sample mode.

## Buffs and debuffs

Aura settings live under **Buffs & debuffs**. Each of the **Buffs** and
**Debuffs** sections has its own side, alignment, growth direction, gap,
offsets and row/column length. Buffs default to the top, debuffs to the bottom.
Right-click a buff on the live player frame to cancel it, if the game permits
removing that buff. Sample preview icons remain non-interactive.
**Cooldown swipe** independently selects **Progressing** (default), **Decreasing**,
or **None** for buffs and debuffs, both here and in the icon row. **Show swipe
edge** independently toggles the spinning line for each group. **None** hides
the fill, spinning edge and completion flash, while keeping time-left text
visible when enabled. Changes to existing live icons defer
until combat ends; ClickGrid's fixed aura slots keep the default swipe.
The parent section controls the font, separate duration/stack sizes, and
duration placement below or inside the icon. **Icon frame** styles each
individual icon border. Centre alignment centres the whole aura block;
use offsets to separate groups when placing both on the same side.
**Debuff border colours** customises the full frame tint for magic, curse,
disease, poison, and debuffs without a dispel type. Turn off **Colour debuff
border by type** to use **Icon frame > Border colour** for every icon.

**Preview only** includes sample buff/debuff counts. Static previews freeze
their timers; Animated previews cycle them. Samples include stacks, a
permanent buff, and all four debuff dispel types, using the saved aura style.

**Which** also offers category filters: **My heals over time** (your own
buffs flagged for raid frames in combat), **Big defensives**, **External
defensives**, **Important** buffs, and **Crowd control** debuffs.

## Crowd control & defensives

**Crowd control & defensives** shows the unit's crowd control, big defensive,
external defensive and (optionally) important buff, one icon per category in
the same spot. Crowd control is on top, then big defensives, external
defensives and important buffs. **Cover the portrait** fills the portrait's
shorter side, above the portrait and below a castbar covering it; the other
positions sit on that anchor without moving the other icons there, and cover
them while an aura shows. **Colour border by category** tints each icon frame
with its category colour. Time-left text stays inside the icon.

**Preview only > Crowd control & defensives** shows one category, **All (highest on top)**,
or **Cycle**: Animated previews show each category in turn, then none; Static
previews show them all. **None** (the default) keeps the portrait visible.

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
