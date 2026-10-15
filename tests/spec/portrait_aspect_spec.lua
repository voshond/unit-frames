local Helpers = require("helpers")
local Mock = Helpers.Mock

local CROP = { 0.08, 0.92, 0.08, 0.92 }

local function LastCall(object, method)
	local value
	for _, call in ipairs(object.__calls) do if call[1] == method then value = call[2] end end
	return value
end

describe("Portrait cover geometry", function()
	it("scales uniformly to cover the viewport and refuses unusable sizes", function()
		local Portrait = Helpers.LoadAddon(false).Components.Portrait
		assert.same({ 80, 80 }, { Portrait.CoverSize(80, 26, 1, 1) })
		assert.same({ 80, 80 }, { Portrait.CoverSize(26, 80, 1, 1) })
		assert.same({ 39, 39 }, { Portrait.CoverSize(39, 39, 1, 1) })
		assert.same({ 52, 26 }, { Portrait.CoverSize(26, 26, 2, 1) })
		assert.same({ 80, 40 }, { Portrait.CoverSize(80, 26, 2, 1) })
		assert.is_nil(Portrait.CoverSize(0, 26, 1, 1))
		assert.is_nil(Portrait.CoverSize(26, -4, 1, 1))
	end)
end)

describe("Portrait artwork aspect ratio", function()
	local ns, uf, portrait, root
	local function Set(path, value)
		ns.Config:SetUnitValue("player", path, value)
	end
	local function Size(region)
		return { region:GetWidth(), region:GetHeight() }
	end
	local function Wide()
		Set("portrait.rowSpan", 1)
		Set("portrait.size", 80)
	end

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "experience.enabled", true)
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		Mock.InstallUI()
		uf = ns.Units.frames.player.uf
		portrait = uf:GetPart("portrait")
		root = portrait:GetFrame()
	end)

	it("covers a wide interior with square 2D artwork, centred and clipped", function()
		Wide()
		Set("portrait.mode", "2D")
		assert.same({ 80, 26 }, Size(root), "outer layout is unchanged")
		assert.same({ 80, 80 }, Size(portrait.texture))
		assert.same({ "CENTER", portrait.viewport, "CENTER", 0, 0 }, portrait.texture:GetAnchor("CENTER"))
		assert.equals(true, LastCall(portrait.viewport, "SetClipsChildren"))
		assert.same({ "TOPLEFT", root, "TOPLEFT", 0, 0 }, portrait.viewport:GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0 }, portrait.viewport:GetAnchor("BOTTOMRIGHT"))
		assert.same(CROP, portrait.texture.__state.texCoords)
		assert.is_true(portrait.viewport:IsShown())
		assert.is_false(portrait.model:IsShown())
	end)

	it("covers tall and square interiors and follows span and width changes", function()
		Set("portrait.mode", "2D")
		Set("portrait.size", 20)
		assert.same({ 20, 69 }, Size(root))
		assert.same({ 69, 69 }, Size(portrait.texture), "a tall interior clips the sides")
		Set("portrait.size", 0)
		assert.same({ 69, 69 }, Size(portrait.texture), "a square interior keeps today's framing")
		Set("portrait.rowSpan", 2)
		assert.same({ 39, 39 }, Size(portrait.texture))
		Set("portrait.size", 80)
		assert.same({ 80, 80 }, Size(portrait.texture))
	end)

	it("subtracts the border padding from the viewport", function()
		Wide()
		Set("portrait.mode", "2D")
		Set("portrait.border.enabled", true)
		Set("portrait.border.padding", 4)
		assert.same({ 80, 26 }, Size(root))
		assert.same({ "TOPLEFT", root, "TOPLEFT", 4, -4 }, portrait.viewport:GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOMRIGHT", root, "BOTTOMRIGHT", -4, 4 }, portrait.viewport:GetAnchor("BOTTOMRIGHT"))
		assert.same({ 72, 72 }, Size(portrait.texture))
	end)

	it("hides artwork without a usable interior and restores it afterwards", function()
		Wide()
		Set("portrait.mode", "2D")
		Set("portrait.border.enabled", true)
		Set("portrait.border.padding", 16)
		assert.is_false(portrait.viewport:IsShown())
		assert.same({ 80, 26 }, Size(root), "the root is never resized")
		Set("portrait.border.padding", 2)
		assert.is_true(portrait.viewport:IsShown())
		assert.same({ 76, 76 }, Size(portrait.texture))
	end)

	it("sizes class icons from static atlas metadata, without touching atlas coordinates", function()
		Mock.atlasInfo["classicon-warrior"] = { width = 64, height = 32 }
		Wide()
		Set("portrait.mode", "class")
		assert.same({ 80, 40 }, Size(portrait.texture))
		portrait.texture.__state.texCoords = "atlas"
		portrait.texture:PostUpdate("player", true)
		uf:Apply()
		assert.equals("atlas", portrait.texture.__state.texCoords, "an atlas keeps its own coordinates")
		assert.same({ 80, 40 }, Size(portrait.texture))
	end)

	it("restores base coordinates across mode switches without accumulating crops", function()
		Wide()
		Set("portrait.mode", "2D")
		Set("portrait.mode", "class")
		assert.same({ 0, 1, 0, 1 }, portrait.texture.__state.texCoords, "the 2D crop is dropped once")
		assert.same({ 80, 80 }, Size(portrait.texture))
		Set("portrait.mode", "2D")
		for _ = 1, 3 do uf:Apply() end
		assert.same(CROP, portrait.texture.__state.texCoords)
		assert.same({ 80, 80 }, Size(portrait.texture))
		Set("portrait.mode", "3D")
		assert.is_false(portrait.viewport:IsShown())
		assert.is_true(portrait.model:IsShown())
		assert.same({ "TOPLEFT", root, "TOPLEFT", 0, 0 }, portrait.model:GetAnchor("TOPLEFT"))
		Set("portrait.mode", "2D")
		assert.is_true(portrait.viewport:IsShown())
	end)

	it("re-presents artwork after oUF's portrait element replaces it", function()
		Wide()
		Set("portrait.mode", "2D")
		local frame = ns.Units.frames.player
		ns.oUF.Private = { unitIsUnit = function(a, b) return a == b end }
		assert(loadfile("UnitFrames/Libs/oUF/elements/portrait.lua"))("oUF", ns)
		local element, handlers = ns.oUF.elements.Portrait, {}
		frame.RegisterEvent = function(_, event, handler) handlers[event] = handler end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		UnitGUID = function() return "Player-1" end
		UnitIsVisible = function() return true end
		rawset(portrait.texture, "__strict", true)
		frame.Portrait = portrait:GetWidget()
		assert.is_true(element.enable(frame, "player"))

		portrait.texture.__state.texCoords = { 0, 1, 0, 1 } -- a replacement may reset coordinates
		portrait.texture:SetSize(1, 1)
		handlers.UNIT_PORTRAIT_UPDATE(frame, "UNIT_PORTRAIT_UPDATE", "player")
		assert.equals("portrait", portrait.texture.__state.texture)
		assert.same(CROP, portrait.texture.__state.texCoords)
		assert.same({ 80, 80 }, Size(portrait.texture))

		Set("portrait.mode", "class")
		portrait.texture:SetSize(1, 1)
		handlers.UNIT_PORTRAIT_UPDATE(frame, "UNIT_PORTRAIT_UPDATE", "player")
		assert.is_true(Mock.IsSecret(portrait.texture.__state.atlas), "oUF sets the live class atlas")
		assert.same({ 80, 80 }, Size(portrait.texture))
		element.disable(frame)
	end)

	it("keeps preview geometry current when SetUnit skips a repeated unit and mode", function()
		local preview = ns.Components.Portrait:New(UIParent, { mode = "2D" })
		preview:SetSize(60, 20)
		preview:SetUnit("player")
		assert.same(CROP, preview.texture.__state.texCoords)
		assert.same({ 60, 60 }, Size(preview.texture))
		preview:SetSize(20, 50)
		preview:SetUnit("player")
		assert.same({ 50, 50 }, Size(preview.texture))
		preview:Apply({ mode = "class" })
		preview:SetUnit("player")
		assert.is_not_nil(preview.texture.__state.atlas)
		assert.same({ 50, 50 }, Size(preview.texture))
		preview:Release()
		assert.is_nil(rawget(preview.texture, "PostUpdate"))
		assert.is_nil(rawget(preview.model, "PostUpdate"))
	end)
end)
