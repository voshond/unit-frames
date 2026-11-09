local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Mock BackdropTemplate layout", function()
	local frame
	local INFO = {
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		tile = true,
		tileSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	before_each(function()
		Mock.Install()
		Mock.InstallUI()
		frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		frame:SetSize(160, 48)
		frame:SetBackdrop(INFO)
	end)

	local function Rounded(values)
		local out = {}
		for index, value in ipairs(values) do out[index] = math.floor(value * 10000 + 0.5) / 10000 end
		return out
	end

	it("anchors corners to the frame and edges and center between the corners", function()
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 0, 0 }, { frame.TopLeftCorner:GetPoint(1) })
		assert.same({ 16, 16 }, { frame.TopLeftCorner:GetSize() })
		assert.same({ "TOPLEFT", frame.TopLeftCorner, "TOPRIGHT", 0, 0 }, { frame.TopEdge:GetPoint(1) })
		assert.same({ "TOPRIGHT", frame.TopRightCorner, "TOPLEFT", 0, 0 }, { frame.TopEdge:GetPoint(2) })
		assert.same({ 0, 16 }, { frame.TopEdge:GetSize() })
		assert.same({ 16, 0 }, { frame.LeftEdge:GetSize() })
		assert.same({ "TOPLEFT", frame.TopLeftCorner, "BOTTOMRIGHT", -13, 13 }, { frame.Center:GetPoint(1) })
		assert.same({ "BOTTOMRIGHT", frame.BottomRightCorner, "TOPLEFT", 13, -13 }, { frame.Center:GetPoint(2) })
		assert.equals(INFO.edgeFile, frame.TopEdge:GetTexture())
		assert.equals(INFO.bgFile, frame.Center:GetTexture())
	end)

	it("sets Blizzard's edge strip coordinates, repeating with the frame size", function()
		assert.same({ 0.5078, 0.0625, 0.5078, 0.9375, 0.6172, 0.0625, 0.6172, 0.9375 },
			Rounded(frame.TopLeftCorner.__state.texCoords))
		assert.same({ 0.2578, 7.9375, 0.3672, 7.9375, 0.2578, 0.0625, 0.3672, 0.0625 },
			Rounded(frame.TopEdge.__state.texCoords))
		assert.same({ 0, 0, 0, 3, 10, 0, 10, 3 }, Rounded(frame.Center.__state.texCoords))
		frame:SetSize(320, 48)
		assert.same({ 0.2578, 17.9375, 0.3672, 17.9375, 0.2578, 0.0625, 0.3672, 0.0625 },
			Rounded(frame.TopEdge.__state.texCoords))
	end)

	it("tints the center with the backdrop colour and the edges with the border colour", function()
		frame:SetBackdropColor(0, 0, 0, 0.8)
		frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
		assert.same({ 0, 0, 0, 0.8 }, frame.Center.__state.vertexColor)
		assert.same({ 0.5, 0.5, 0.5, 1 }, frame.RightEdge.__state.vertexColor)
	end)

	it("stops following size changes once a script replaces the template's OnSizeChanged", function()
		frame:SetScript("OnSizeChanged", nil)
		frame:SetSize(320, 48)
		assert.same({ 0.2578, 7.9375, 0.3672, 7.9375, 0.2578, 0.0625, 0.3672, 0.0625 },
			Rounded(frame.TopEdge.__state.texCoords))
	end)
end)
