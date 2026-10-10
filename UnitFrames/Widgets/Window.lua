local _, ns = ...
local Skin = ns.Skin

--[[
Movable, resizable window with a title bar and close button.
opts:
  name        global frame name (lets Escape close it)
  title
  width, height, minWidth, minHeight
  db          table where position and size are remembered
  onHide      callback
]]
local Window = ns.Widget:Extend("Window")

local TITLE_HEIGHT = 24

function Window:OnCreate(parent, opts)
	local frame = CreateFrame("Frame", opts.name, parent or UIParent, "BackdropTemplate")
	self.frame = frame
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(opts.minWidth or 300, opts.minHeight or 200)
	frame:SetSize(opts.width or 600, opts.height or 400)
	frame:SetPoint("CENTER")
	Skin.ApplyPanel(frame, "window")

	local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(TITLE_HEIGHT)
	Skin.ApplyPanel(titleBar, "panel", "panel")
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		self:SaveGeometry()
	end)

	self.title = Skin.FontString(titleBar, "title")
	self.title:SetPoint("LEFT", 8, 0)
	self.title:SetText(opts.title or "")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
	grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
	grip:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		self:SaveGeometry()
	end)

	self.content = CreateFrame("Frame", nil, frame)
	self.content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 6, -6)
	self.content:SetPoint("BOTTOMRIGHT", -6, 20)

	frame:SetScript("OnHide", function()
		if opts.onHide then
			opts.onHide(self)
		end
	end)

	if opts.name then
		tinsert(UISpecialFrames, opts.name)
	end
	self:RestoreGeometry()
end

function Window:GetContent()
	return self.content
end

function Window:SaveGeometry()
	local db = self.opts.db
	if not db then
		return
	end
	local point, _, relativePoint, x, y = self.frame:GetPoint(1)
	db.point = { point, relativePoint, x, y }
	db.size = { self.frame:GetSize() }
end

function Window:RestoreGeometry()
	local db = self.opts.db
	if not db then
		return
	end
	if db.size then
		self.frame:SetSize(db.size[1], db.size[2])
	end
	if db.point then
		self.frame:ClearAllPoints()
		self.frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
	end
end

function Window:Toggle()
	self.frame:SetShown(not self.frame:IsShown())
end
