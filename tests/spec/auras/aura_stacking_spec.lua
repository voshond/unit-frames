local Helpers = require("helpers")

describe("Aura blocks sharing a side #auras-stack", function()
	local ns, frame, auras
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		-- Start on separate sides: blocks sharing one are combined from creation.
		ns.Config:SetUnitValue("player", "auras.debuffs.position", "bottom")
		frame = ns.Units:CreateFrame("player", CreateFrame("Frame"))
		auras = frame:GetPart("auras")
	end)

	local function Apply(cfg)
		auras:Apply(ns.Util.Merge({
			durationPosition = "below",
			buffs = { position = "bottom", lineSize = 100, max = 6 },
			debuffs = { position = "bottom", lineSize = 100, max = 6 },
		}, cfg or {}))
	end

	local function AnchorY(kind, containers)
		local anchor = (containers or auras.containers)[kind]:GetAnchor("TOPLEFT")
		return anchor[5]
	end

	local function Groups(container)
		return container.__state.groups
	end

	it("flows combined blocks through the buff container by default", function()
		Apply()
		local buffs, debuffs = auras.containers.buffs, auras.containers.debuffs
		assert.equals(-2, AnchorY("buffs"))
		assert.is_true(Groups(buffs).debuffs.enabled)
		assert.equals("HARMFUL", Groups(buffs).debuffs.filter)
		assert.equals(6, Groups(buffs).debuffs.max)
		assert.equals(1, Groups(buffs).buffs.layout.layoutIndex)
		assert.equals(2, Groups(buffs).debuffs.layout.layoutIndex)
		assert.equals(26, Groups(buffs).debuffs.layout.elementWidth)
		assert.is_false(Groups(debuffs).debuffs.enabled)
		assert.is_false(debuffs:IsEnabled())
		assert.is_false(debuffs:IsShown())
		assert.is_true(buffs:IsEnabled())
	end)

	it("leads the combined flow with debuffs and places it by their settings", function()
		Apply({ stackFirst = "debuffs", debuffs = { gap = 6, alignment = "end" } })
		local buffs = auras.containers.buffs
		assert.equals(2, Groups(buffs).buffs.layout.layoutIndex)
		assert.equals(1, Groups(buffs).debuffs.layout.layoutIndex)
		assert.same({ "TOPRIGHT", frame.frame, "BOTTOMRIGHT", 0, -6 }, buffs:GetAnchor("TOPRIGHT"))
	end)

	it("styles combined debuff buttons as debuffs and restores separate containers", function()
		Apply()
		local buffs, debuffs = auras.containers.buffs, auras.containers.debuffs
		local guest = buffs:GetAuraGroupFrame("debuffs", 1)
		assert.equals("debuffs", guest.ufKind)
		assert.equals(26, guest:GetWidth())
		Apply({ sharedSide = "stacked" })
		assert.is_false(Groups(buffs).debuffs.enabled)
		assert.is_true(Groups(debuffs).debuffs.enabled)
		assert.is_true(debuffs:IsEnabled())
		assert.equals(-70, AnchorY("debuffs"))
		Apply({ debuffs = { position = "top" } })
		assert.is_false(Groups(buffs).debuffs.enabled)
		assert.is_true(debuffs:IsEnabled())
	end)

	it("does not add the combined group until blocks are combined", function()
		Apply({ sharedSide = "stacked" })
		assert.is_nil(Groups(auras.containers.buffs).debuffs)
		Apply({ debuffs = { enabled = false } })
		assert.is_nil(Groups(auras.containers.buffs).debuffs)
	end)

	it("flows combined sample previews as one block", function()
		ns.Units:ShowSample(frame, ns.Units.SAMPLE)
		Apply()
		local buffs, debuffs = auras.previewContainers.buffs, auras.previewContainers.debuffs
		local lastBuff = buffs.ufElements[#buffs.ufElements]
		local firstDebuff = debuffs.ufElements[1]
		assert.is_true(#buffs.ufElements > 0 and firstDebuff ~= nil)
		assert.equals(buffs, firstDebuff:GetAnchor("TOPLEFT")[2])
		local lastX, firstX = lastBuff:GetAnchor("TOPLEFT")[4], firstDebuff:GetAnchor("TOPLEFT")[4]
		local lastY, firstY = lastBuff:GetAnchor("TOPLEFT")[5], firstDebuff:GetAnchor("TOPLEFT")[5]
		assert.is_true(firstY < lastY or firstX >= lastX + lastBuff:GetWidth())
		assert.is_true(debuffs:IsShown())
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
		assert.is_false(auras.containers.debuffs:IsEnabled())
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
		assert.is_false(Option("stackFirst").hidden(auras.resolved))
		Apply({ sharedSide = "stacked" })
		assert.is_false(Option("stackFirst").hidden(auras.resolved))
		Apply({ buffs = { position = "top" } })
		assert.is_true(Option("sharedSide").hidden(auras.resolved))
		assert.is_true(Option("stackFirst").hidden(auras.resolved))
		assert.is_nil(ns.Schema.Find(ns.Components.AuraBar.schema, "sharedSide"))
		assert.is_nil(ns.Schema.Find(ns.Components.AuraBar.schema, "stackFirst"))
	end)
end)
