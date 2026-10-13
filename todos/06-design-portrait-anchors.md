# Design: all nine portrait indicator anchors

Status: implemented (offline tests only; in-game verification pending). Assumption: the request
concerns indicator placement inside the portrait, not moving the portrait itself.

## Goal and current behaviour

Offer top left, top, top right, left, centre, right, bottom left, bottom and
bottom right for indicators inside the portrait. Retain the existing frame
border and name anchors. Portrait position and row spanning remain separate.

`UnitFrames/Components/DecorationStack.lua` currently exposes only
`PORTRAIT_BOTTOMLEFT` and `PORTRAIT_BOTTOMRIGHT`. It groups indicators by anchor,
sorts by configured order and key, collapses known-absent icons and reserves
space when native visibility is secret. `UnitFrame.lua` provides plain portrait
width/height in the layout context. Shared consumers include raid target, PvP,
classification, ready-check and ClickGrid status indicators.

`tests/spec/decoration_stack_spec.lua` already covers grouping, unknown presence,
missing portraits and sizing. `portrait_span_spec.lua` covers rectangular
portraits and corner placement through layout changes.

## Anchor and stacking contract

Keep existing identifiers and defaults. Add the seven missing `PORTRAIT_*`
values to the shared anchor list so every consumer receives the same choices.

| Anchors | Stack axis | Alignment |
| --- | --- | --- |
| TOPLEFT, BOTTOMLEFT | Horizontal | First icon touches left edge; group extends right |
| TOPRIGHT, BOTTOMRIGHT | Horizontal | Last icon touches right edge; group extends left |
| TOP, BOTTOM | Horizontal | Whole group centred horizontally, inside its edge |
| LEFT, RIGHT | Vertical | Whole group centred vertically, inside its edge |
| CENTER | Horizontal | Whole group centred on portrait centre |

All names in this table carry the `PORTRAIT_` prefix. Order stays left-to-right
for horizontal stacks and top-to-bottom for vertical stacks, including right
anchors. Retain per-member gap and x/y offsets. Positive x moves right and
positive y moves up, consistently with existing settings.

At zero offsets, a single icon lies fully inside the portrait's outer bounds.
Keep current border-relative geometry for compatibility; portrait artwork
cropping does not change indicator coordinates. Preserve individual size
clamping to `min(configured size, portrait width, portrait height)`.

V1 does not shrink an entire stack, wrap, merge different anchor groups, hide
overflow or clamp deliberate offsets. A crowded stack can exceed the portrait,
as existing corner stacks can. Include that limitation in the sizing hint;
an occupancy-based layout would need a separate design, especially with secret
visibility. Different anchor groups can overlap by user choice.

## Implementation boundaries

Replace corner-string heuristics with a small explicit anchor descriptor table
(axis, edge, alignment), shared by placement calculations. Preserve all current
border/name behaviour and tie-breaking. Compute geometry exclusively from the
layout context and configured indicator sizes; do not read native icon sizes.

No new part or data driver is required: existing indicators still register with
the same `DecorationStack`. If the portrait is disabled or absent, hide these
addon-owned indicator hosts and preserve their settings. Restore them on the
next valid layout. Unknown native presence continues to reserve space.

Do not clip the portrait root for the aspect-ratio fix: an inner artwork viewport
keeps these indicators independent. Retain existing cast-overlay layering and
range-opacity behaviour; adding anchors must not change who covers an indicator
during a portrait-replacing cast. Check the actual rendering before promising
that indicators remain visible above that overlay.

## Delivery and verification

1. Add anchor descriptors and shared choices, preserving the two existing
   corner coordinates and all defaults.
2. Extend decoration tests with each of the nine anchors on square/wide/tall
   portraits, one and multiple unequal-size indicators, gaps, offsets, order
   changes, known/unknown presence and disable/re-enable.
3. Cover row-span, width, border, profile/reset and Copy player settings changes;
   verify ClickGrid receives the options without a duplicate anchor list.
4. Run the full suite and Workbench filter. In game inspect all positions in
   static/animated/live previews, portrait mode switches, casts, real combat,
   unit replacement and Workbench release/reopening. Defer protected layout
   work using existing combat handling if affected.

If the request instead means relocating the portrait itself, this document
does not cover that: row reservation, root bounds and cast placement would need
a separate frame-layout proposal.
