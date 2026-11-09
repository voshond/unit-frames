# wowproof

Visual proof for World of Warcraft addon tests. wowproof takes the frame tree
of a mocked client and renders it to SVG, PNG and an HTML contact sheet. It is
plain Lua 5.1 / LuaJIT and has no dependencies. Two external tools are optional:
`rsvg-convert` turns the SVGs into PNGs, and ImageMagick converts `.tga`/`.blp`
textures.

It never touches a widget directly. Everything goes through an **adapter**, so
any mock (or any other frame model) can be rendered by writing one.

## Use

```lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local Proof = require("wowproof")
local MockState = require("wowproof.adapters.mock_state")

local proof = Proof.New({
	adapter = MockState({
		isSecret = Mock.IsSecret,
		reveal = function(value) return value.secretValue end,
		objects = function() return Mock.objects end,
		globals = _G,
	}),
	outDir = ".proof",
	assets = {
		textures = function(path) return "MyAddon/Media/Glow.tga" end,
		fonts = { dirs = { "MyAddon/Fonts" }, family = function(path) return "Roboto", 700 end, default = "Roboto" },
	},
})

proof:Snapshot(MyFrame, "player-frame", { pad = 8, scale = 2, debug = false })
proof:Sheet()
```

To run named scenarios and get a contact sheet with failures included, use
`require("wowproof.runner").Run({ proof = proof, scenarios = { { name, build } }, filters = arg })`.

## Adapter contract

An adapter is a table of functions over the host's region objects. Values
must be plain Lua values. Unwrapping secrets or other host-specific values is
the adapter's job.

| Function | Returns |
| --- | --- |
| `Parent(r)`, `Children(r)` | the parent region or nil; children in creation order |
| `Order(r)`, `Type(r)`, `Name(r)` | creation index; `Frame`, `StatusBar`, `Texture`, `FontString`, …; a name or nil |
| `Points(r)` | `{ point, relativeTo, relativePoint, x, y }` entries, or `{ all = true, relativeTo }` |
| `Size(r)`, `Scale(r)` | width, height; own scale |
| `Shown(r)`, `Alpha(r)`, `IgnoresParentAlpha(r)` | own shown state; own alpha; boolean |
| `Strata(r)`, `Level(r)`, `Layer(r)` | strata or nil (inherited); frame level; draw layer and sublevel |
| `Texture(r)` | `{ color, vertexColor, file, atlas, gradient = { orientation, from, to }, blend, slice }` |
| `Bar(r)` | nil, or for status bars `{ min, max, value, orientation, reverse, color }` |
| `Text(r)` | nil, or for font strings `{ text, font, size, flags, color, justifyH, justifyV }` |
| `FillOf(r)` *(optional)* | the status bar whose fill texture `r` is; the fill then gets its rect from the bar value |
| `ClipsChildren(r)` *(optional)* | whether the frame clips its children |

`wowproof.scene` validates adapters and lists the strata and draw-layer order.
`wowproof.adapters.mock_state` covers mocks that keep widget state in
`obj.__state` and unimplemented calls in `obj.__calls`.

## What it draws

- **Layout:** anchors (single point plus size, two-point stretch, all points), offsets, scale and clipping.
  The content is cropped to the snapshot region, everything it draws, and the screen.
- **Paint order:** strata, then frame level, then draw layer, then sublevel, then creation order.
  Effective alpha and visibility are honoured.
- **Textures:**
  - colour and gradient textures
  - Blizzard's white textures, drawn as solid colour
  - resolved image files, tinted by vertex colour, including nine-slice
  - anything else as a dashed placeholder titled with its path
- **Status bars and text:** status bar fills by value, and font strings with justification, outline and `|c` colour codes.

Rendering is deterministic: the same scene gives the same SVG.

## Tests

`spec/` holds busted-style specs (`describe`/`it`/`assert.*`) that need
nothing but this package. `spec/package_spec.lua` also fails if a file here
mentions the addon that hosts it.
