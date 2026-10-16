local Helpers = require("helpers")

describe("ClickGrid crowd control & defensives", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	local function Member()
		return CG.headers.party:GetAttribute("child1").Member
	end

	it("centres a mouse-transparent icon on members and leaves target strips without one", function()
		local frame = Member()
		local icons = frame.uf:GetPart("categoryAuras")
		assert.is_true(icons:IsEnabled())
		assert.equals("CENTER", icons.resolved.anchor)
		assert.equals(18, icons.buttons.crowdControl:GetWidth())
		assert.is_true(frame:IsElementEnabled("UF_CategoryAuras"))
		for _, button in pairs(icons.buttons) do
			local disabled = {}
			for _, call in ipairs(button.__calls) do
				if call[2] == false then disabled[call[1]] = true end
			end
			assert.is_true(disabled.SetMouseClickEnabled and disabled.SetMouseMotionEnabled)
		end
		CG.Config:SetStyle("target", "shown", true)
		local target = CG.headers.party:GetAttribute("child1").Target
		assert.is_false(target.uf:GetPart("categoryAuras"):IsEnabled())
	end)

	it("moves private auras off the centre, configurably", function()
		local private = CG:GetGridButton(Member()).status.PrivateAuras
		assert.same({ "RIGHT", Member(), "RIGHT", -2, 0 }, private:GetAnchor("RIGHT"))
		CG.Config:Set("indicators.privatePosition", "TOP")
		assert.same({ "TOP", Member(), "TOP", 0, -2 }, private:GetAnchor("TOP"))
		CG.Config:Set("indicators.privatePosition", "CENTER")
		assert.same({ "CENTER", Member(), "CENTER", 0, 0 }, private:GetAnchor("CENTER"))
	end)

	it("defaults member buffs to my heals over time and keeps an explicit filter", function()
		local buffs = Member().uf:GetPart("auras"):GetContainer("buffs")
		assert.equals("HELPFUL|PLAYER|RAID_IN_COMBAT", buffs.__state.groups.buffs.filter)
		CG.Config:SetStyle("member", "auras.buffs.filter", "HELPFUL|PLAYER")
		assert.equals("HELPFUL|PLAYER", buffs.__state.groups.buffs.filter)
		assert.equals("HELPFUL|PLAYER", CG.Config:GetStyle("member").auras.buffs.filter)
	end)
end)

describe("ClickGrid crowd control & defensive previews", function()
	local UF, CG, wb
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	local function Shown()
		local shown = {}
		for index, cell in ipairs(wb.handle.cells) do
			local part = cell.member:GetPart("categoryAuras")
			for key, button in pairs(part.samples or {}) do
				if button:IsShown() and cell.frame:IsShown() then shown[index] = key end
			end
		end
		return shown
	end

	it("mixes sample categories across members and rotates them when animated", function()
		wb.dataTarget.set("count", 8)
		local static = Shown()
		local categories, count = {}, 0
		for _, key in pairs(static) do categories[key], count = true, count + 1 end
		assert.is_true(categories.crowdControl and categories.bigDefensive and categories.externalDefensive)
		assert.is_true(count < 8, "some members show none")
		wb.dataTarget.set("source", "animated")
		wb.handle:Tick(2)
		assert.is_false(UF.Util.Equals(static, Shown()), "animated samples move along")
		wb.dataTarget.set("categoryAuras", false)
		assert.is_nil(next(Shown()))
	end)
end)
