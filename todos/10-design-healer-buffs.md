# Design: Healer buffs out of the box

Status: in progress. §1 buff catalogue (UNIT-13), §2 rank-proof slots (UNIT-14) and §3 "My heals & shields"
on by default (UNIT-15) are implemented; §4 presets/showcases and the Verification below (UNIT-17) are open.
Targets Forever Interface 16001, build 1.60.1.70862.

## Problem

A druid healer's Rejuvenation never showed on the tank's ClickGrid cell. Nothing
healer-related is on by default:

- ClickGrid member `auras.buffs` ships `enabled = false` (filter "My heals over time").
- The three fixed friendly buff slots ship `enabled = false` with an empty spell ID list.
- A slot matches **exact** aura spell IDs. Rejuvenation has 11 learnable ranks
  (774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299). Typing the
  ID from a wiki or a tooltip of rank 1 misses every other rank.

## Findings

### `RAID_IN_COMBAT` does not cover the ranks players cast

Our "My heals over time" filter is `HELPFUL|PLAYER|RAID_IN_COMBAT`. That flag
comes from the `SpellAuraVisibility` DB2 (Type 0 = RaidInCombat). On build
1.60.1.70862 it is set on:

| Spell | Flagged IDs | Learnable ranks (SkillLineAbility) |
|---|---|---|
| Rejuvenation | 417057–417062 … (11, **not** skill-line spells) | 774 … 25299 — **not flagged** |
| Regrowth | 436937 … (9, not skill-line) | 8936 … 9858 — **not flagged** |
| Renew | 425268–425277 (skill-line) | 139 … 25315 — **not flagged** |
| Lifebloom, Wild Growth, Prayer of Mending (401877 …), Temporal Beacon | flagged | — |
| Riptide, Power Word: Shield, Earth Shield | **not flagged** | — |

So even a user who switches the member buffs on can miss classic-rank HoTs,
and shields never pass. Needs one in-game check of which set a druid's
spellbook casts (see Verification).

### Both ID sets belong to one family

`SpellClassOptions` gives the same class set and mask to every rank of a spell,
flagged or not (Rejuvenation: set 7, mask 16; Renew: set 6, mask 64; Regrowth:
set 7, mask 64). `scripts/spell_catalog.py` already groups DoT ranks into
families this way. A heal classifier on the same tables finds (prototype in
`.beluga/scratch/proto/hot_probe.py`):

- HoTs (`EffectAura` 8 on an ally): Rejuvenation 11, Regrowth 9, Renew 20,
  Lifebloom, Riptide 3, Lightwell Renew, Flash of Light HoT.
- Absorbs (`EffectAura` 69): Power Word: Shield 10, Ice Barrier, Fire/Frost Ward,
  Shadow Ward.
- Missed by effect rules, need a short hand list: Earth Shield (proc aura),
  Prayer of Mending (buff lands under 401877 …), Wild Growth (non-skill-line).

### How others do it

- **HealKit** (`examples/HealKit`): one Blizzard `AuraContainer` per corner with
  `HELPFUL|PLAYER`, `candidateFilters = { maxDuration = 60, excludeSpellIDs = <all PW:S ranks> }`.
  Zero config, works in combat, no spell lists. Debuff corner `HARMFUL|PLAYER`,
  dispel corner `HARMFUL|RAID`.
- **EllesmereUI** (all rights reserved: ideas only, no code): spell → filter →
  indicator. Hand-curated Forever catalogue (`EllesmereUI_BuffPresets.lua`)
  lists rank 1 as primary and every other rank as alts. Presets: Defensives,
  Raid CDs, Externals, Core Healing Buffs, Offensive CDs, Movement, Utility,
  Consumables. Healer starter seed: "Defensives & Utility" centre (any caster),
  "Core Healing Buffs" top left and "Lesser" top right (own only). Indicator
  kinds: icon, square, health-bar colour, background colour, border, frame alpha.
- **HealBot** (`examples/HealBot`, its `16001` TOC; Forever path behind
  `HEALBOT_FOREVER`, "camelot" = Mainline 12.1.5 API): matches HoTs by name
  from the 774-set ranks, never the 417057 set. A hint that players cast the
  unflagged ranks.
- **Blizzard Forever party frames**: `HELPFUL|RAID` for castable buffs when the
  `showCastableBuffs` CVar is on.

Sources read on their Forever paths: EllesmereUI has no Forever branch; `main`
targets `16001` among retail builds and gates Forever behind `IS_FOREVER`
(`ForeverCatalogue()`, `EllesmereUI_Migration.lua` FvBW starter seed). HealKit
targets `16001` only. Blizzard code from `examples/wow-ui-source-forever`.

`AuraContainer` candidate filters are spell-ID only (`includeSpellIDs`,
`excludeSpellIDs`, dispel types, `maxDuration`); no name matching. Any preset
must therefore expand to every rank ID.

## Proposal

### 1. Generated buff catalogue

Extend `scripts/spell_catalog.py` to also emit `UnitFrames/Tracking/BuffCatalog.lua`
(generated, never hand-edited) from the same pinned tables plus
`SpellAuraVisibility`:

```
ns.BuffCatalog = {
	families = { [774] = { name = "Rejuvenation", class = "DRUID", kind = "hot", ids = { 774, …, 417057, … } }, … },
	byId = { [1058] = 774, … },
}
```

Family key = lowest skill-line rank. A short curated table in the script adds
proc buffs (Earth Shield, Prayer of Mending) and the EllesmereUI-style
categories (externals, defensives) by family root only — ranks always come
from the data.

As built (`compile_buffs`, 51 families on 1.60.1.70862):

- Grouping uses the DoT rule exactly: class set, the four masks, school and the
  primary aura. School and aura matter: Blessed Recovery shares Rejuvenation's
  set 7 / mask 16, and Power Infusion shares Divine Spirit's set and mask.
- A group is a `hot` (aura 8) or `absorb` (aura 69) family only when one of its
  **skill-line** ranks lands on someone other than the caster, pet or master
  (`ImplicitTarget_0` not 1, 5, 27). This keeps out Ice Barrier, Fire/Frost Ward
  (self-only skill ranks, ally-targeted rune variants) and the Voidwalker's
  Sacrifice, so Warrior, Rogue, Hunter and Warlock get no heal families.
- Heal families exist for Druid, Priest, Shaman, Paladin and Mage (Season of
  Discovery arcane healing: Mass Regeneration, curated Regeneration and
  Temporal Beacon).
- `BUFF_EXTRAS` holds roots only. Several roots make one family: Prayer of
  Mending is the cast (401859 …) plus the buff (401877 …); Sacred Shield is
  412019 plus its absorb 412018. Kinds: `hot`, `proc`, `external`, `defensive`,
  `raid`. A missing root stops generation for review.
- `raidInCombat` lists catalogue IDs with `SpellAuraVisibility` Type 0.

### 2. Rank-proof slots (fixes the reported bug)

`Slots.ParseIDs` keeps its validation; resolving a slot expands every entered
ID through `BuffCatalog.byId` to its whole family. Saved data is unchanged, so
existing profiles fix themselves. The slot editor gets a family picker
("Rejuvenation — all ranks") beside the raw ID field.

### 3. "My heals & shields" that works by default

- New buff filter choice backed by the catalogue: `HELPFUL|PLAYER` plus
  `includeSpellIDs` = the player's class families of kind hot/absorb. Wire
  `includeSpellIDs` through `Auras.CandidateFilters` beside `maxDuration`.
- ClickGrid member buffs default `enabled = true` with that choice. Only the
  player's own heals pass, so non-healers see nothing.
- Keep `HELPFUL|PLAYER|RAID_IN_COMBAT` as an option, relabelled honestly.

### 4. Presets and showcases

Named buff sets the user picks instead of IDs: **My heals & shields**,
**Externals & defensives** (any caster), **Raid buffs**. Each placement gets a
live showcase card fed by sample auras:

| Placement | Part | Look |
|---|---|---|
| Outside | `Auras` block, side top/bottom | row of icons above the cell |
| Inside | ClickGrid slots | fixed corners, one family per corner |
| Aura bar | `AuraBar` row | strip under the health bar |

Workbench: a "Healing buffs" page under ClickGrid members with the preset
picker and the three cards. Onboarding: with the Healer preset (or a healing
class) a tile "Show my heals on group frames" plus the placement choice.

### 5. Shared with DoT tracking

One generator, two outputs. DoT and buff families use the same family rule,
so a later "my DoTs on target" preset reuses the catalogue API.

## Verification (in game, needs a druid and a priest)

1. Cast Rejuvenation on yourself, then
   `/dump C_UnitAuras.GetUnitAuras("player", "HELPFUL|PLAYER")` → which spellId
   (774-set or 417057-set)?
2. Same with `HELPFUL|PLAYER|RAID_IN_COMBAT` → listed or not?
3. In combat: does a catalogue-backed member group show Rejuvenation, Renew,
   Power Word: Shield on another party member?
