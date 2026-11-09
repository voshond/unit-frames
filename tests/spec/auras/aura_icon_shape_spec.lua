local Helpers = require("helpers")

local function Near(expected, actual)
	for index, value in ipairs(expected) do
		assert.is_true(math.abs(value - actual[index]) < 1e-9, "coordinate " .. index)
	end
end

describe("Aura icon border and shape", function()
	local ns, auras, button

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "auras.border", { enabled = true, border = "UnitFrames Pixel", padding = 1 })
		auras = ns.Units.frames.player.uf:GetPart("auras")
		button = auras:GetContainer("buffs"):GetAuraGroupFrame("buffs", 1)
	end)

	it("draws the icon frame's border above the artwork and swipe, below the texts", function()
		local edge = ns.Components.Backdrop.BorderTextures(button.ufIconFrame)[1]
		local layer = edge:GetParent()
		assert.is_true(layer ~= button.ufIconFrame, "edges leave the icon frame's own layers")
		assert.is_true(layer:GetFrameLevel() > button.ufCooldown:GetFrameLevel())
		assert.is_true(button.ufCover:GetFrameLevel() > layer:GetFrameLevel())
		assert.is_true(button.ufCountHolder:GetFrameLevel() > layer:GetFrameLevel())
		ns.Config:SetUnitValue("player", "auras.border.border", "Blizzard Raid")
		local raid = ns.Components.Backdrop.BorderTextures(button.ufIconFrame)[1]:GetParent()
		assert.is_true(raid:GetFrameLevel() > button.ufCooldown:GetFrameLevel())
	end)

	it("keeps square icons until a separate height is enabled, then crops the artwork to fit", function()
		local layout = auras:GetContainer("buffs").__state.groups.buffs.layout
		local textRoom = ns.AuraIcon.TextRoom(auras.resolved)
		assert.equals(20, layout.elementWidth)
		assert.equals(20 + textRoom, layout.elementHeight)
		Near({ 0.08, 0.92, 0.08, 0.92 }, button.ufIcon.__state.texCoords)

		ns.Config:SetUnitValue("player", "auras.buffs.separateHeight", true)
		assert.equals(20, auras.resolved.buffs.height, "the height starts from the current size")
		ns.Config:SetUnitValue("player", "auras.buffs.height", 11)
		layout = auras:GetContainer("buffs").__state.groups.buffs.layout
		assert.equals(20, layout.elementWidth)
		assert.equals(11 + textRoom, layout.elementHeight)
		assert.equals(20, button.ufIconFrame:GetWidth())
		assert.equals(11, button.ufIconFrame:GetHeight())
		Near({ 0.08, 0.92, 0.5 - 0.42 * 9 / 18, 0.5 + 0.42 * 9 / 18 }, button.ufIcon.__state.texCoords)

		ns.Config:SetUnitValue("player", "auras.buffs.separateHeight", false)
		assert.equals(20, button.ufIconFrame:GetHeight())
	end)

	it("crops the longer side of tall icons", function()
		Near({ 0.5 - 0.42 * 0.5, 0.5 + 0.42 * 0.5, 0.08, 0.92 }, { ns.AuraIcon.TexCoords(10, 20) })
	end)
end)
