local Helpers = require("helpers")
local Mock = Helpers.Mock
local names = { hideBuffs = "BuffFrame", hideDebuffs = "DebuffFrame" }

local function Frames()
	local frames = {}
	for key, name in pairs(names) do
		local frame = CreateFrame("Frame", nil, UIParent)
		_G[name] = frame
		frame:SetRolesets("buffs")
		frame:RegisterEvent("UNIT_AURA")
		frames[key] = frame
	end
	return frames
end

describe("Blizzard player buff and debuff visibility", function()
	after_each(function()
		for _, name in pairs(names) do _G[name] = nil end
	end)

	it("defaults to visible and reversibly filters each native section independently", function()
		local ns = Helpers.LoadAddon(true, true)
		local frames = Frames()
		ns.BlizzardAuras:Update()
		local resolved = ns.Config:UnitStore("player"):Resolved().blizzardAuras
		assert.is_false(resolved.hideBuffs)
		assert.is_false(resolved.hideDebuffs)
		for _, frame in pairs(frames) do assert.is_true(frame:IsVisible()) end
		ns.Config:SetUnitValue("player", "blizzardAuras.hideBuffs", true)
		assert.is_true(frames.hideBuffs:IsRolesetFiltered())
		assert.is_false(frames.hideBuffs:IsVisible())
		assert.is_true(frames.hideBuffs:IsEventRegistered("UNIT_AURA"))
		frames.hideBuffs:Show()
		assert.is_false(frames.hideBuffs:IsVisible())
		assert.is_false(frames.hideDebuffs:IsRolesetFiltered())
		ns.Config:SetUnitValue("player", "blizzardAuras.hideDebuffs", true)
		assert.is_true(frames.hideDebuffs:IsRolesetFiltered())
		ns.Config:SetUnitValue("player", "blizzardAuras.hideBuffs", nil)
		assert.same({ "buffs" }, frames.hideBuffs:GetRolesetNames())
		assert.is_true(frames.hideBuffs:IsVisible())
		assert.is_true(frames.hideDebuffs:IsRolesetFiltered())
	end)

	it("defers changes in combat and restores the sections on a profile reset", function()
		local ns = Helpers.LoadAddon(true, true)
		local frames = Frames()
		Mock.inCombat = true
		ns.Config:SetUnitValue("player", "blizzardAuras.hideBuffs", true)
		ns.Config:SetUnitValue("player", "blizzardAuras.hideDebuffs", true)
		for _, frame in pairs(frames) do assert.is_false(frame:IsRolesetFiltered()) end
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		for _, frame in pairs(frames) do assert.is_true(frame:IsRolesetFiltered()) end
		ns.Config.db:ResetProfile()
		for _, frame in pairs(frames) do assert.same({ "buffs" }, frame:GetRolesetNames()) end
	end)

	it("applies saved settings on load and offers them only on the player", function()
		local ns = Helpers.LoadAddon(false, false, { profileKeys = {}, profiles = { Default = {
			units = { player = { blizzardAuras = { hideDebuffs = true } } } } } })
		local frames = Frames()
		Mock.FireEvent("ADDON_LOADED", "UnitFrames")
		ns.oUF:RunFactories()
		assert.is_false(frames.hideBuffs:IsRolesetFiltered())
		assert.is_true(frames.hideDebuffs:IsRolesetFiltered())
		for _, unit in ipairs(ns.Units.order) do
			if unit ~= "player" then
				assert.is_nil(ns.Schema.Find(ns.Units:GetSchema(unit), "blizzardAuras.hideBuffs"))
			end
		end
		assert.is_true(ns.Units:CopyPlayerSettings("target"))
		assert.is_nil(ns.Config:GetUnitConfig("target").blizzardAuras)
	end)

	it("exposes searchable settings on the player's buffs and debuffs page", function()
		local ns, wb = Helpers.LoadWorkbench()
		local frames = Frames()
		wb:Open("unit.player")
		local result = wb:FindSettings("hide blizzard debuffs")[1].record
		assert.equals("unit.player", result.entryId)
		assert.equals("blizzardAuras.hideDebuffs", result.path)
		assert.equals("@auras", result.pageId)
		wb:OpenDestination(result)
		for _, row in ipairs(wb.inspector.page.rows) do
			if row.path == result.path then row.control.opts.onChange(true); break end
		end
		assert.is_true(ns.Config:UnitStore("player"):Resolved().blizzardAuras.hideDebuffs)
		assert.is_true(frames.hideDebuffs:IsRolesetFiltered())
	end)
end)
