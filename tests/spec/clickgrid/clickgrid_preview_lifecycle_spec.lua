local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid preview lifecycle", function()
	it("restyles and feeds an active preview once per saved edit, theme and profile change", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local preview, applies, feeds = wb.handle, 0, 0
		local inspectorRefreshes, refresh = 0, wb.inspector.Refresh
		wb.inspector.Refresh = function(self, ...)
			inspectorRefreshes = inspectorRefreshes + 1
			return refresh(self, ...)
		end
		local apply, feed = preview.Apply, preview.ShowData
		preview.Apply = function(self, ...)
			applies = applies + 1
			return apply(self, ...)
		end
		preview.ShowData = function(self, ...)
			feeds = feeds + 1
			return feed(self, ...)
		end
		local function Once(edit)
			applies, feeds, inspectorRefreshes = 0, 0, 0
			edit()
			assert.equals(1, applies)
			assert.equals(1, feeds)
			assert.is_true(inspectorRefreshes > 0)
		end
		Once(function() CG.Config:Set("indicators.readySize", 24) end)
		Once(function() UF.Config:SetThemeValue("fontSize", 13) end)
		Once(function() UF.Config.db:SetProfile("other") end)
		assert.equals(preview, wb.handle)
	end)

	it("updates samples without a full style application and disables absent live subscriptions", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local cell = wb.handle.cells[2]
		local applies, apply = 0, cell.member.Apply
		cell.member.Apply = function(self, ...)
			applies = applies + 1
			return apply(self, ...)
		end
		wb.dataTarget.set("readyCheck", "check")
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.equals(0, applies)
		Mock.groupSize = 2
		CG.headers.party:Assign(2, "party1")
		wb.dataTarget.set("source", "live")
		assert.is_true(cell.member:GetPart("auras").containers.buffs:IsEnabled())
		CG.headers.party:Assign(2, nil)
		wb:OnUpdate(0.2)
		assert.is_false(cell.member:GetPart("auras").containers.buffs:IsEnabled())
		assert.is_false(cell.slots.container:IsEnabled())
		CG.headers.party:Assign(2, "party1")
		wb:OnUpdate(0.2)
		assert.is_true(cell.member:GetPart("auras").containers.buffs:IsEnabled())
	end)

	it("switches ready check samples to live and back without retaining sample state", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		wb.dataTarget.set("readyCheck", "check")
		local cell = wb.handle.cells[1]
		assert.is_not_nil(cell.member:GetRow("health"):GetBar():GetTint())
		for _, source in ipairs({ "live", "animated", "live", "static" }) do
			wb.dataTarget.set("source", source)
			if source == "live" then
				assert.is_nil(cell.member:GetRow("health"):GetBar():GetTint())
				assert.is_false(cell.status.ReadyCheckIndicator:IsShown())
			else
				assert.is_not_nil(cell.member:GetRow("health"):GetBar():GetTint())
			end
		end
	end)

	it("retains combat source changes and never resumes a retired preview", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local old = wb.handle
		Mock.inCombat = true
		wb.dataTarget.set("source", "live")
		wb:Select("clickgrid.target")
		assert.is_true(old.released)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(old.cells[1].member.released)
		assert.is_nil(CG.previews[old])
		assert.is_nil(next(CG.retiredPreviews))
	end)
end)
