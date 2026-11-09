local _, ob = ...
local UF = UnitFrames
local C, COLORS = UF.Skin.colors, ob.COLORS
local Pending, Presets = ob.Pending, ob.Presets

--[[
Step 1: an animated stage (player with a cast, target with DoTs) in the
chosen look, and a card per preset with a still mini preview of its own.
]]
ob.Steps = ob.Steps or {}
local Look = {
	label = "Pick a look",
	title = "Pick a look",
	subtitle = "Start from a style you like. Everything stays adjustable later; this gets you most of the way there.",
	nextLabel = "Next: make it yours",
}
ob.Steps.Look = Look

local STAGE_HEIGHT, CARD_WIDTH, CARD_GAP, CARD_SCALE = 272, 186, 8, 0.6

local STAGE_LAYOUT = {
	{ unit = "player", point = { "CENTER", -190, 6 }, cast = true, buffs = 4 },
	{ unit = "target", point = { "CENTER", 190, 6 }, dots = true, debuffs = 3 },
}

-- A dark preview well with faint guide lines, as on the mockups.
function ob.Stage(parent, width, height)
	local stage = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	stage:SetSize(width, height)
	ob.Panel(stage, COLORS.well, C.border)
	for x = 20, width - 1, 40 do
		local line = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
		line:SetColorTexture(1, 1, 1, 0.025)
		line:SetPoint("TOPLEFT", x, -1)
		line:SetPoint("BOTTOMLEFT", x, 1)
		line:SetWidth(1)
	end
	stage.caption = ob.Text(stage, 12, C.accent, true)
	stage.caption:SetPoint("TOPLEFT", 16, -14)
	stage.note = ob.Text(stage, 11, C.textDim)
	stage.note:SetPoint("TOPLEFT", stage.caption, "BOTTOMLEFT", 0, -4)
	stage.note:SetWidth(width - 32)
	local live = stage:CreateTexture(nil, "OVERLAY")
	live:SetColorTexture(0.33, 1, 0.47, 1)
	live:SetSize(6, 6)
	live:SetPoint("BOTTOMLEFT", 18, 18)
	local liveText = ob.Text(stage, 11, C.textDim)
	liveText:SetPoint("LEFT", live, "RIGHT", 8, 0)
	liveText:SetText("Live preview with sample data")
	return stage
end

function Look:Build(page, owner)
	self.owner = owner
	self.stage = ob.Stage(page, ob.Shell.PAGE_WIDTH, STAGE_HEIGHT)
	self.stage:SetPoint("TOPLEFT")
	self.preview = ob.Preview:New(self.stage, STAGE_LAYOUT, { animated = true })
	self.cards, self.cardPreviews = {}, {}
	for index, preset in ipairs(Presets.list) do
		local card = ob.Widgets.Card:New(page, { name = preset.name, tags = preset.tags, width = CARD_WIDTH,
			onClick = function() Pending:SelectPreset(preset.id) end })
		card:SetPoint("TOPLEFT", (index - 1) * (CARD_WIDTH + CARD_GAP), -(STAGE_HEIGHT + 22))
		local holder = CreateFrame("Frame", nil, card.well)
		holder:SetScale(CARD_SCALE)
		holder:SetSize(CARD_WIDTH / CARD_SCALE, card.well:GetHeight() / CARD_SCALE)
		holder:SetPoint("CENTER", card.well, "CENTER")
		self.cards[preset.id] = card
		self.cardPreviews[preset.id] = ob.Preview:New(holder, { { unit = "player", point = { "CENTER" } } })
	end
end

function Look:Refresh()
	local preset = Pending.preset
	self.stage.caption:SetText(preset.name:upper())
	self.stage.note:SetText(preset.pitch)
	self.preview:Show(Pending:Style(), Pending:Resolved().theme)
	for id, card in pairs(self.cards) do card:SetSelected(id == preset.id) end
end

function Look:Enter()
	for _, preset in ipairs(Presets.list) do
		local style = Pending.PresetStyle(preset)
		self.cardPreviews[preset.id]:Show(style, Pending.Resolve(style).theme)
	end
	self:Refresh()
end

function Look:Leave()
	self.preview:Release()
	for _, preview in pairs(self.cardPreviews) do preview:Release() end
end

function Look:Tick(elapsed)
	self.preview:Tick(elapsed)
end
