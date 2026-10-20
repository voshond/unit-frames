local Helpers = require("helpers")

describe("Aura blocks sharing a side #auras-stack", function()
	local ns, frame, auras
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		frame = ns.Units:CreateFrame("player", CreateFrame("Frame"))
		auras = frame:GetPart("auras")
	end)

	local function Apply(cfg)
		auras:Apply(ns.Util.Merge({
			buffs = { position = "bottom", lineSize = 100, max = 6 },
			debuffs = { position = "bottom", lineSize = 100, max = 6 },
		}, cfg or {}))
	end

	local function AnchorY(kind, containers)
		local anchor = (containers or auras.containers)[kind]:GetAnchor("TOPLEFT")
		return anchor[5]
	end

	it("keeps combined blocks at the same edge by default", function()
		Apply()
		assert.equals(-2, AnchorY("buffs"))
		assert.equals(-2, AnchorY("debuffs"))
	end)

	-- Buffs: 4 per 100px line of 20px icons, 6 max = 2 lines of 32px (timer below).
	it("moves debuffs past the full capacity of the buffs", function()
		Apply({ sharedSide = "stacked" })
		assert.equals(-2, AnchorY("buffs"))
		assert.equals(-(2 + 2 + 2 * 32 + 2), AnchorY("debuffs"))
	end)

	-- Debuffs: 3 per 100px line of 26px icons, 6 max = 2 lines of 38px.
	it("places debuffs closest to the frame when chosen", function()
		Apply({ sharedSide = "stacked", stackFirst = "debuffs" })
		assert.equals(-2, AnchorY("debuffs"))
		assert.equals(-(2 + 2 + 2 * 38 + 2), AnchorY("buffs"))
	end)

	it("adds the inner block's outward offset and the outer block's own gap", function()
		Apply({ sharedSide = "stacked", buffs = { offsetY = -5 }, debuffs = { gap = 4 } })
		assert.equals(-(4 + 2 + 5 + 2 * 32 + 2), AnchorY("debuffs"))
	end)

	-- Vertical lines are 32px per icon along, 20px across: 3 per line, 2 lines.
	it("stacks columns on the left and right", function()
		Apply({ sharedSide = "stacked", buffs = { position = "left" }, debuffs = { position = "left" } })
		assert.same({ "TOPRIGHT", frame.frame, "TOPLEFT", -2, 0 }, auras.containers.buffs:GetAnchor("TOPRIGHT"))
		assert.same({ "TOPRIGHT", frame.frame, "TOPLEFT", -(2 + 2 + 2 * 20 + 2), 0 },
			auras.containers.debuffs:GetAnchor("TOPRIGHT"))
	end)

	it("falls back to the normal edge on separate sides or a disabled block", function()
		Apply({ sharedSide = "stacked", buffs = { position = "top" } })
		assert.equals(-2, AnchorY("debuffs"))
		Apply({ sharedSide = "stacked", buffs = { enabled = false } })
		assert.equals(-2, AnchorY("debuffs"))
	end)

	it("keeps the stack stable across repeated applies", function()
		Apply({ sharedSide = "stacked" })
		Apply({ sharedSide = "stacked" })
		assert.equals(-70, AnchorY("debuffs"))
		Apply({ sharedSide = "combined" })
		assert.equals(-2, AnchorY("debuffs"))
	end)

	it("stacks sample previews like live containers", function()
		ns.Units:ShowSample(frame, ns.Units.SAMPLE)
		Apply({ sharedSide = "stacked" })
		assert.equals(-2, AnchorY("buffs", auras.previewContainers))
		assert.equals(-70, AnchorY("debuffs", auras.previewContainers))
	end)

	it("offers the options only for blocks on one side, and not to the embedded row", function()
		local function Option(key)
			return ns.Schema.Find(ns.Components.Auras.schema, key)
		end
		Apply()
		assert.is_false(Option("sharedSide").hidden(auras.resolved))
		assert.is_true(Option("stackFirst").hidden(auras.resolved))
		Apply({ sharedSide = "stacked" })
		assert.is_false(Option("stackFirst").hidden(auras.resolved))
		Apply({ buffs = { position = "top" } })
		assert.is_true(Option("sharedSide").hidden(auras.resolved))
		assert.is_nil(ns.Schema.Find(ns.Components.AuraBar.schema, "sharedSide"))
		assert.is_nil(ns.Schema.Find(ns.Components.AuraBar.schema, "stackFirst"))
	end)
end)
