local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Castbar host dimensions", function()
	local ns, uf, castbar
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		ns.Config:SetUnitValue("player", "castbar.height", 26)
		ns.Config:SetUnitValue("player", "health.height", 40)
		Mock.InstallUI()
		uf = ns.Units.frames.player.uf
		castbar = uf:GetPart("castbar")
		castbar.frame.GetWidth = function() return 1 end
		castbar.frame.GetHeight = function() return 1 end
	end)

	it("sizes row and health icons before native geometry settles, including repeated toggles", function()
		for _ = 1, 2 do
			for _, placement in ipairs({ "top", "bottom", "health" }) do
				ns.Config:SetUnitValue("player", "castbar.placement", placement)
				local side = placement == "health" and 40 or 26
				assert.equals(side, castbar.icon:GetWidth(), placement)
				assert.equals(side, castbar.iconFrame:GetWidth(), placement)
				assert.equals(side, castbar.iconFrame:GetHeight(), placement)
				local sample = ns.Units:GetSample("player")
				ns.Units:ShowSample(uf, sample)
				assert.equals(side, castbar.icon:GetHeight(), placement .. " sample")
				ns.Cast.Refresh(castbar, {}, "player")
				assert.equals(side, castbar.icon:GetHeight(), placement .. " live")
			end
		end
	end)

	it("uses portrait bounds while preserving split and stack icon holders", function()
		ns.Config:SetUnitValue("player", "portrait.size", 60)
		ns.Config:SetUnitValue("player", "portrait.rowSpan", 1)
		ns.Config:SetUnitValue("player", "castbar.placement", "portrait")
		for _, layout in ipairs({ "split", "stack" }) do
			ns.Config:SetUnitValue("player", "castbar.portraitLayout", layout)
			assert.equals(layout == "split" and 40 or 60, castbar.icon:GetWidth())
			assert.equals(layout == "split" and 29.5 or 60, castbar.iconFrame:GetWidth())
			assert.equals(layout == "split" and 40 or 19.5, castbar.iconFrame:GetHeight())
		end
	end)

	it("uses known health and aura row dimensions when the covering bar can collapse", function()
		ns.Config:SetUnitValue("player", "auraBar.enabled", true)
		ns.Config:SetUnitValue("player", "auraBar.collapse", true)
		ns.Config:SetUnitValue("player", "auraBar.height", 20)
		local health = uf:GetRow("health"):GetFrame()
		health.GetWidth = function() error("must use layout width") end
		health.GetHeight = function() error("must use layout height") end
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		assert.equals(40, castbar.knownHeight)
		assert.equals(60 + uf.resolved.spacing, castbar.knownMaxHeight)
		assert.equals(castbar.knownMaxHeight, castbar.icon:GetWidth())
		assert.equals("BOTTOMLEFT", castbar.iconFrame.__state.points[2][1])
	end)
end)

describe("Pure castbar layout", function()
	it("measures portrait splits, stacks, sides and ordinary rows without native frames", function()
		local UF = Helpers.LoadAddon()
		local cfg = UF.Schema.Resolve(UF.Components.Castbar.BuildSchema(), { border = { enabled = false } }, UF.Config:GetTheme())
		local create = CreateFrame
		CreateFrame = function() error("layout must not allocate native frames") end
		for _, side in ipairs({ "LEFT", "RIGHT" }) do
			cfg.icon.position, cfg.portraitLayout = side, "split"
			local split = UF.CastbarLayout.Compute(60, 40, cfg, true)
			assert.equals(29.5, split.icon.width)
			assert.equals(40, split.icon.height)
			assert.equals(side == "LEFT" and "TOPLEFT" or "TOPRIGHT", split.icon.point)
			assert.equals(40, split.icon.side)
			cfg.portraitLayout = "stack"
			local stack = UF.CastbarLayout.Compute(60, 40, cfg, true)
			assert.equals(60, stack.icon.width)
			assert.equals(19.5, stack.icon.height)
			assert.equals(60, stack.icon.side)
			assert.same({ "TOPLEFT", "icon", "BOTTOMLEFT", 0, -1 }, stack.bar[1])
			assert.equals(40, UF.CastbarLayout.Compute(60, 40, cfg, false).icon.width)
		end
		CreateFrame = create
	end)

	it("handles small hosts, padding and hidden icons and keeps host policy outside the leaf schema", function()
		local UF = Helpers.LoadAddon()
		local C = UF.Components.Castbar
		local cfg = UF.Schema.Resolve(C.BuildSchema(), {}, UF.Config:GetTheme())
		local tiny = UF.CastbarLayout.Compute(1, 1, cfg, false)
		assert.equals(1, tiny.icon.height)
		assert.equals(1, tiny.icon.side)
		assert.equals(70 - 6, UF.CastbarLayout.Compute(60, 40, cfg, false, 70).icon.side, "covers the tallest the host can grow")
		cfg.icon.enabled = false
		local noIcon = UF.CastbarLayout.Compute(60, 40, cfg, false)
		assert.is_nil(noIcon.icon)
		assert.same({ "TOPLEFT", "frame", "TOPLEFT", 3, -3 }, noIcon.bar[1])
		assert.is_true(UF.Schema.Find(C.BuildSchema(), "portraitLayout").hidden({ placement = "portrait" }))
		local schema = UF.Units:GetSchema("player")
		local hidden = UF.Schema.Find(schema, "castbar.portraitLayout").hidden
		assert.is_false(hidden({ placement = "portrait" }))
		assert.is_true(hidden({ placement = "bottom" }))
	end)
end)
