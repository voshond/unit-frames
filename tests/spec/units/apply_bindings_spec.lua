local Helpers = require("helpers")

describe("Unchanged unit tag bindings", function()
	it("retags only changed presets while preserving custom events and toggle transitions", function()
		local ns = Helpers.LoadAddon(true, true)
		local frame = ns.Units.frames.player
		local text = frame.uf:GetRow("health"):GetText("left")
		local fs = text:GetFrame()
		local tags, tag = 0, frame.Tag
		frame.Tag = function(self, ...)
			tags = tags + 1
			return tag(self, ...)
		end
		ns.Units:Refresh("player")
		ns.Config:SetUnitValue("player", "health.left.color", { 1, 0, 0, 1 })
		assert.equals(0, tags)
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		assert.equals(1, tags)
		local handle = ns.TextTags.GetHandle(fs)
		ns.Config:SetUnitValue("player", "health.left.piece2.source", "xp.current")
		assert.equals(2, tags)
		assert.is_not_nil(ns.oUF.Tags.Events[handle]:find("PLAYER_XP_UPDATE", 1, true))
		ns.Units:Refresh("player")
		assert.equals(2, tags)
		ns.Config:SetUnitValue("player", "health.left.format", "name")
		assert.equals(3, tags)
		assert.equals("[uf:name]", frame.tags[fs])
		ns.Config:SetUnitValue("player", "health.left.enabled", false)
		assert.is_nil(frame.tags[fs])
		ns.Config:SetUnitValue("player", "health.left.enabled", true)
		assert.equals(4, tags)
		assert.equals("[uf:name]", frame.tags[fs])
	end)

	it("clears disabled slots once and restores presets after explicit deactivation", function()
		local ns = Helpers.LoadAddon(true, true)
		local frame = ns.Units.frames.player
		local left = frame.uf:GetRow("health"):GetText("left"):GetFrame()
		local clears, untag = 0, frame.Untag
		frame.Untag = function(self, ...) clears = clears + 1; return untag(self, ...) end
		for _ = 1, 3 do ns.Units:Refresh("player") end
		assert.equals(0, clears)
		ns.Config:SetUnitValue("player", "health.left.enabled", false)
		assert.equals(1, clears)
		assert.is_nil(frame.tags[left])
		ns.Units:Refresh("player")
		assert.equals(1, clears)
		ns.Config:SetUnitValue("player", "health.left.enabled", true)
		assert.equals("[uf:name]", frame.tags[left])
		ns.Units:ClearTags(frame)
		assert.is_nil(frame.tags[left])
		local before = clears
		ns.Units:ClearTags(frame)
		assert.equals(before, clears)
		ns.Units:Bind(frame)
		assert.equals("[uf:name]", frame.tags[left])
		frame.__unit = "target"
		ns.Units:Bind(frame)
		assert.equals("[uf:name]", frame.tags[left])
	end)
end)
