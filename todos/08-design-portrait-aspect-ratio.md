# Design: portrait artwork without stretching

Status: in progress; first implementation done, in-game checks pending.
Proposal: centre-cover the portrait interior, cropping excess artwork while
preserving its proportions.

## Problem and current behaviour

Portrait width can be independent of the height of its spanned rows. In
`UnitFrames/Components/Portrait.lua`, both 2D and class textures are inset and
stretched to those rectangular bounds. The fixed 2D UV crop (0.08 to 0.92)
does not compensate for destination aspect ratio.

`UnitFrame.lua` already computes plain layout dimensions; `portrait_span_spec`
tests rectangles such as 80 by 26. Embedded `oUF/elements/portrait.lua` refreshes
the texture using `SetPortraitTexture` or `SetAtlas` and then invokes the
texture's `PostUpdate`. Any correction must survive those refreshes as well as
Workbench `Portrait:SetUnit`, mode changes, borders and row-span changes.

## Rendering contract

The portrait's outer size, background, border and indicator anchors do not
change. Introduce an inner artwork viewport following the existing border
inset. Render the texture centred within it with uniform scale:

```
scale = max(viewportWidth / sourceWidth, viewportHeight / sourceHeight)
drawWidth  = sourceWidth  * scale
drawHeight = sourceHeight * scale
```

All inputs are plain layout/configuration or verified static asset metadata.
A square source in an 80 by 26 interior draws at 80 by 80 and clips 27 pixels
above and below. A 26 by 80 interior clips the sides instead. A square interior
preserves today's framing. Zero or negative interior dimensions hide artwork
until usable geometry returns; do not divide by zero or resize the root.

Use native child clipping on the inner viewport, not the portrait root, so
indicator stacks, borders and cast overlays retain their existing geometry.
The image is centred and crops symmetrically. V1 needs no new saved setting;
this corrects distortion for existing rectangular portraits automatically.
A future contain/letterbox option can use minimum scale, but is outside this fix.

## 2D textures, atlases and ownership

Keep the existing symmetric 2D portrait crop as its base framing. Its retained
source region is square, so it uses a square drawing region before viewport
clipping. Restore the appropriate base UVs when changing from a class atlas
or returning from another mode; never accumulate crops across repeated Apply.

Class icons are atlas regions, not necessarily the whole underlying texture.
Prefer rendering the atlas unchanged on a uniformly sized drawing region and
clipping that region. Do not apply raw 0..1 UV crops to an atlas without proving
how its coordinates are represented; this can sample adjacent artwork.

The Forever checkout's `TextureUtilsDocumentation.lua` documents
`C_Texture.GetAtlasInfo(atlas)` and `SimpleFrameAPIDocumentation.lua` documents
`SetClipsChildren`. Verify the class atlas logical width/height and clipping
behaviour in the actual client. Obtain aspect ratio only from known non-secret
asset identifiers/metadata; never index a cache or do arithmetic using opaque
live identifiers or dimensions. Confirm the existing class-token/atlas path's
API contract before using it for metadata. If necessary, use verified static
class-icon ratios rather than querying an opaque atlas name.

Centralise geometry in a plain aspect-fit helper and presentation in Portrait.
Pass the owner's known dimensions through an explicit layout method after size
changes, subtracting the same border inset used by Backdrop. Recompute on style
changes too. Avoid repeated per-frame work and native width/height reads.

oUF still owns the portrait texture and unit updates. Use its `PostUpdate` hook
to restore presentation after asset changes; preview `SetUnit` calls the same
presentation path. Geometry refresh must work even when SetUnit skips a repeated
unit/mode. Remove callbacks on release. Rebind through the existing driver if
the driven widget changes; do not edit embedded oUF.

## 3D models and cast overlays

Keep 3D camera framing unchanged: a model is not a bitmap to which this scale
formula applies. Preserve model `PostUpdate`, range fade and cover alpha behaviour
from `portrait_opacity_spec`. A mode switch must leave only the intended widget
visible and restore each widget's own geometry and UV state.

Portrait-replacing castbars keep their outer host and layering. This task fixes
2D portrait/class artwork; it does not silently change the castbar's spell-icon
layout. Cover and restoration must still work across the new inner viewport.
Coordinate with [portrait anchors](06-design-portrait-anchors.md): those hosts
remain outside artwork clipping.

## Delivery and verification

1. Prove atlas and 2D clipping on square, wide and tall native textures before
   choosing viewport clipping over direct UV cropping. If clipping fails for
   required layers, investigate atlas-aware UV composition as a documented
   fallback; do not ship stretched artwork or sample-only behaviour.
2. Add the pure geometry helper and Portrait-owned viewport, preserving outer
   layout and oUF ownership. Extend API snapshot/mocks only from verified source.
3. Add aspect-ratio regressions alongside `portrait_span_spec`: exact uniform
   dimensions, centring, borders, tiny interiors, width/span changes, repeated
   Apply/SetUnit, class-to-2D switches, atlas refresh and release. Exercise the
   embedded oUF PostUpdate path, not only the simplified mock.
4. Run full, shields and Workbench tests. In game compare recognisable faces
   and class symbols in wide/tall frames; check clipping, backgrounds/borders,
   all indicator anchors, range fades, cast cover/restoration, combat, unit
   disappearance/replacement and Workbench entry/source switching.

Acceptance: no visible non-uniform scaling in 2D/class modes; no atlas bleed;
no artwork outside the inner viewport; unchanged outer layout and 3D behaviour.
