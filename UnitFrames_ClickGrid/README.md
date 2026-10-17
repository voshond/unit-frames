# UnitFrames ClickGrid

Experimental companion for WoW Forever (Interface `16001`). Requires
`UnitFrames`; settings use the existing load-on-demand `UnitFrames_Workbench`.
It provides party/raid healing groups with modifier click spells.

## Use

Enable this addon alongside UnitFrames. Open `/ufcg` for **Panel & indicators**,
**Member bars**, **Target bars**, and **Click spells** under the ClickGrid category.
`/ufcg bindings` opens click spells directly; `/ufcg on` and `/ufcg off` toggle
the panel. It appears in groups by default; enable **Show when solo** to test
without a group. Move its enclosing panel in Blizzard Edit Mode.

Install ClickGrid from the same release bundle as UnitFrames and restart the
client after adding it. For local builds and incremental updates, see the
[developer guide](../DEVELOPMENT.md).

## Implemented

- Secure party header (including the player) and forty-member raid capacity.
  Party panel bounds follow the current member count, including roster changes
  during combat; unused party rows do not reserve background space.
  Raid subgroups can be stacked in configurable columns, or use a flat grid
  with rows, columns and fill direction. Optional duplicate tank section.
  Flat-grid rows and columns are independent preferences: a 5 × 5 grid is
  valid. Larger rosters overflow into extra columns when filling down, or
  extra rows when filling across, without changing saved settings or hiding
  raiders. Live panel bounds reserve forty-member capacity before combat;
  previews reserve the configured grid plus any needed sample overflow.
- **Group / column titles** under **Panel & indicators**: editable party,
  tank and individual raid-subgroup/flat-column labels (Group 1, Group 2,
  etc., not one Raid title). Shared font, size,
  outline, shadow and colour; above/below placement, left/centre/right
  alignment, gap and offsets. Hiding titles removes their reserved space.
  The single enclosing backdrop excludes the outer title band, so headings
  hover outside it. No independent group backdrops are created.
- **Panel border** under **Panel & indicators** controls the enclosing panel's
  border and background independently of the member bars. It inherits the
  Theme until overridden. Choose **Blizzard Raid** for the native raid artwork;
  **Content padding** controls the space around the members. Enable **Content
  padding per side** at the top of the section for independent left, right,
  top and bottom values. **Background inset per side** provides independent
  insets for the background, without moving members. Previous Panel layout padding is preserved
  automatically in these shared controls. Borders draw above the members;
  the background stays behind them.
- Member targets beside the bars, as tall as the member's bar, with independent
  target styling. Switch them on under **Target bars > General** (an earlier
  *Show member targets* panel choice is carried over). Existing
  UnitFrames health, shields, power, portrait, castbar, text, range, marker,
  font and border controls are reused rather than duplicated.
  Hidden targets keep their prepared secure buttons but stop unit watches,
  oUF element updates, native aura subscriptions and preview data updates.
- Five mouse buttons × eight Alt/Ctrl/Shift combinations, with separate
  friendly/hostile actions: cast, macro, target, assist, focus, menu or unbound.
  The **Click spells** grid fills the Workbench stage and shows each cell's
  friendly (F) and hostile (H) action with its icon and name. Drop a spell or
  macro from the spellbook, action bars or macro window straight onto a line
  (or click it while carrying one); clicking a line otherwise opens its
  **Friendly**/**Hostile** settings page, which has the same drop slot plus
  **Spellbook** and **Macros** openers (disabled in combat). Typed spell
  IDs/localized names and macro names remain available. Spells resolve through
  the client's spell APIs; macros are stored by name and resolved to their
  current index. Unknown spells and missing macros retain saved intent and
  stay inactive. Spell/talent/spec/macro updates rebuild bindings outside
  combat. With Clique loaded, Clique owns clicks
  and this addon's binding editor does not control live actions.
- Independent native buff/debuff rows, own-cast/dispel filters, timers,
  stacks, borders, duration limits and native sorting. Both rows are off by
  default, keeping the panel compact (2-pixel gaps); when enabled, the buff row
  shows your own heals over time (`HELPFUL|PLAYER|RAID_IN_COMBAT`) up to two
  minutes long, not long maintenance buffs. A saved filter choice is kept.
- A centre icon for crowd control, big and external defensives (crowd control
  on top), mouse-transparent so hover and mouseover casts reach the member.
- Three configurable fixed friendly-buff slots, each accepting comma-separated
  numeric aura spell IDs, own/any caster, position and size. Multiple IDs share
  a slot; Blizzard chooses the earliest-expiring matching effect. These are
  buff slots, not arbitrary friendly-debuff encounter rules.
- Role, leader/assistant, ready check, dead/ghost, incoming resurrection,
  summon, phase, optional threat and native private-aura anchors, subject to
  client support. Threat outlines the cell with Blizzard's raid aggro highlight by default; **Threat style >
  Soft glow** draws Blizzard's glow border around the cell instead. Private auras sit inside the right edge by default
  (**Private aura position**), leaving the centre to crowd control.
- Ready check bar tints on member bars (**Member bars > Ready check**): grey
  while waiting, then green or red, holding and fading after the check with
  the ready check icon. Without a group, **Preview data > Ready check** shows
  a sample check; Animated lets members answer in turn and fades out.
  The ready check icon uses the same state and fade as the bars, including
  when bar tinting is disabled; its existing indicator controls place it.
  Its shared default is a 22-pixel icon at the frame centre.
  Role, leader/assistant, ready check, dead/ghost, incoming resurrection and
  summon positions offer **Before
  name** (an enabled left-aligned Name text on the health bar), the frame
  centre, or any raid-marker border/portrait anchor (nine positions inside the
  portrait as well as on the border). Role defaults before
  name, ready check to the frame centre, and the others to the top border
  with the raid marker. Icons
  sharing an anchor form one group with the raid marker that leaves no gap
  for absent icons: edges and the centre keep the group centred, border
  corners and portrait corners grow inward, left/right edges run top to
  bottom. **Order** arranges each group (raid 1, role 2, leader 3, ready 4,
  dead/ghost 5, resurrection 6, summon 7 by default). Leader and assistant share one slot. Each icon
  has independent size, gap (the space after it) and offsets that nudge only
  that icon. Before name gives the name room for the icons actually shown.
  An ordinary unassigned role takes no space; opaque roles keep their slot,
  as does any icon whose shown state is opaque. The dead/ghost icon is a
  spirit icon both while dead and after releasing as a ghost. Missing portraits
  or a missing left-aligned name hide the corresponding placement. Incoming
  resurrection turns health-row text green by default; its text-colour toggle
  restores the configured colours, as does the end of the resurrection.
  Phase stays a fixed overlay sized by **Other status icon size**.
- Static/animated group samples up to forty members and a live bars/auras
  preview. Live previews intentionally omit status/private-aura indicators.
  Group previews automatically shrink to fit the Workbench stage, retaining
  the configured group positions and empty roster slots. The stage scale is
  an upper limit; fitting does not change the live panel's size or scale.
  Samples illustrate styling/filtering; native priority ordering remains
  authoritative in game, not the sample list order.

Visual settings share the UnitFrames AceDB profile in a separate `ClickGrid`
namespace. Click bindings are per character and specialization index and do
not change when switching visual profiles. Positions remain per Edit Mode
layout. Default unmodified left/right clicks target/open the menu; no healing
spells are guessed or automatically assigned.

Configuration is saved during combat and applied after combat. Existing
headers own roster assignment; configuration never selects spells from live
health, aura, range or cooldown data. Workbench group previews pause updates
during combat; switching entries defers native component cleanup until combat
ends. Group capacities are allocated before combat; previously selected
layouts retain hidden reusable frames for the session.

## Limits and release gate

Blizzard party/raid frames remain visible. This is currently an additive panel,
not a verified replacement. Missing-buff warnings, action icons,
items, communications, plugins and sound alerts remain future work.
Arbitrary spell-ID priority logic for restricted friendly debuffs is not
promised; native selection and private-aura presentation are used instead.

Offline tests do not prove visual correctness or secure combat behavior.
Before relying on the panel for healing, verify on the actual Forever client:

1. Solo, party and forty-member raid; subgroup/flat layouts, both fill
   directions, player inclusion and optional tank duplicates. Join/leave,
   subgroup/role changes, unit disappearance and vehicle replacement in combat
   must not create new addon widgets or produce taint/protected-action errors.
2. Every modifier/button/reaction binding, mouse-release casting, override
   spells, spec/talent updates, unknown spells and Clique ownership. Spell and
   macro drops onto grid lines and settings slots (drag and click-carry),
   rejected item drops keeping the cursor, macro creation/deletion/renaming,
   the Spellbook and Macros openers and their combat lock, grid resizing and
   tooltips, and switching cells or Workbench entries after a drop.
3. Targets appearing/disappearing, native buff slots, aura timers/counts/dispel
   colors, private auras, status transitions and opaque values during combat.
4. Full-health/damaged shields in both placements, style/theme/profile switches,
   queued combat changes and repeated toggles.
5. Workbench static/animated/live sources, entry switching and deferred cleanup;
   Edit Mode moving/snapping, panel dimensions and per-layout persistence.

Run `luajit tests/run.lua`, `luajit tests/run.lua shields`,
`luajit tests/run.lua workbench`, and `luajit tests/run.lua clickgrid` from the
repository root. The mock suite covers configuration, layout capacity,
bindings, opaque threat/preview data, lifecycle and the embedded oUF header
initializer. It does not emulate Blizzard's full restricted execution engine.
