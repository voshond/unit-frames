local Helpers = require("helpers")
local Mock = Helpers.Mock
local names = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager" }

local function Frames()
	local frames = {}
	for _, name in ipairs(names) do
		local frame = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
		_G[name] = frame
		frame:SetRolesets("unitFrames,test")
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frames[#frames + 1] = frame
	end
	return frames
end

describe("ClickGrid Blizzard group frame visibility", function()
	after_each(function()
		for _, name in ipairs(names) do _G[name] = nil end
	end)

	it("defaults to visible and reversibly filters all native group containers", function()
		local _, CG = Helpers.LoadClickGrid()
		local frames = Frames()
		CG:UpdateBlizzardFrames()
		assert.is_false(CG.Config:Resolved().panel.hideBlizzardFrames)
		for _, frame in ipairs(frames) do assert.is_true(frame:IsVisible()) end
		CG.Config:Set("panel.hideBlizzardFrames", true)
		CG:RequestRefresh()
		for _, frame in ipairs(frames) do
			assert.is_true(frame:IsRolesetFiltered())
			assert.is_false(frame:IsVisible())
			assert.is_true(frame:IsEventRegistered("GROUP_ROSTER_UPDATE"))
			frame:Show()
			assert.is_false(frame:IsVisible())
		end
		CG.Config:Set("panel.hideBlizzardFrames", false)
		for _, frame in ipairs(frames) do
			assert.same({ "unitFrames", "test" }, frame:GetRolesetNames())
			assert.is_true(frame:IsVisible())
		end
	end)

	it("defers changes in combat and restores frames when ClickGrid or the setting is reset", function()
		local _, CG = Helpers.LoadClickGrid()
		local frames = Frames()
		Mock.inCombat = true
		CG.Config:Set("panel.hideBlizzardFrames", true)
		for _, frame in ipairs(frames) do assert.is_false(frame:IsRolesetFiltered()) end
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		for _, frame in ipairs(frames) do assert.is_true(frame:IsRolesetFiltered()) end
		Mock.inCombat = true
		CG.Config:Set("panel.enabled", false)
		for _, frame in ipairs(frames) do assert.is_true(frame:IsRolesetFiltered()) end
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		for _, frame in ipairs(frames) do assert.is_false(frame:IsRolesetFiltered()) end
		CG.Config:Set("panel.enabled", true)
		for _, frame in ipairs(frames) do assert.is_true(frame:IsRolesetFiltered()) end
		CG.Config.settings:Reset()
		for _, frame in ipairs(frames) do assert.is_false(frame:IsRolesetFiltered()) end
	end)

	it("handles native frames loaded later, including during combat", function()
		local _, CG = Helpers.LoadClickGrid()
		CG.Config:Set("panel.hideBlizzardFrames", true)
		Mock.inCombat = true
		local frames
		Mock.RunUntainted(function() frames = Frames() end)
		Mock.FireEvent("ADDON_LOADED", "Blizzard_CompactRaidFrames")
		for _, frame in ipairs(frames) do assert.is_false(frame:IsRolesetFiltered()) end
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		for _, frame in ipairs(frames) do assert.is_true(frame:IsRolesetFiltered()) end
		CG.Config:Set("panel.hideBlizzardFrames", false)
		for _, frame in ipairs(frames) do assert.same({ "unitFrames", "test" }, frame:GetRolesetNames()) end
	end)

	it("exposes a searchable real setting in the ClickGrid layout inspector", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		local frames = Frames()
		wb:Open("clickgrid.panel")
		local result = wb:FindSettings("hide blizzard party raid")[1].record
		assert.equals("clickgrid.panel", result.entryId)
		assert.equals("panel.hideBlizzardFrames", result.path)
		wb:OpenDestination(result)
		assert.equals("@layout", wb.state.section)
		for _, row in ipairs(wb.inspector.page.rows) do
			if row.path == result.path then row.control.opts.onChange(true); break end
		end
		assert.is_true(CG.Config:Resolved().panel.hideBlizzardFrames)
		for _, frame in ipairs(frames) do assert.is_true(frame:IsRolesetFiltered()) end
	end)
end)
