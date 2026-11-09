local _, ob = ...
local UF = UnitFrames
local C = UF.Skin.colors
local Pending, Presets = ob.Pending, ob.Presets

--[[
Step 2: the chosen look on a stage, and a row of chips per tweak. Every chip
shows its option directly (fonts in their own face) and restyles the stage.
]]
local Tweaks = {
	label = "Make it yours",
	title = "Make it yours",
	subtitle = "The few options that change the feel most. Hundreds more are waiting in the Workbench.",
	nextLabel = "Next: extras",
}
ob.Steps.Tweaks = Tweaks

local STAGE_WIDTH, COLUMN_GAP, CHIP_GAP, ROW_GAP = 400, 24, 8, 18

local STAGE_LAYOUT = {
	{ unit = "player", point = { "CENTER", 0, 76 }, cast = true },
	{ unit = "target", point = { "CENTER", 0, -84 }, dots = true },
}

local function ChipRow(parent, tweak, width, top)
	local label = ob.Text(parent, 10, C.textDim, true)
	label:SetPoint("TOPLEFT", 0, top)
	label:SetText(tweak.label:upper())
	local chips, x, y = {}, 0, top - 18
	for _, choice in ipairs(Presets.Choices(tweak)) do
		local chip = ob.Widgets.Chip:New(parent, { text = choice[2], font = tweak.media == "font" and choice[1] or nil,
			onClick = function() Pending:SetTweak(tweak.key, choice[1]) end })
		local chipWidth = chip.frame:GetWidth()
		if x > 0 and x + chipWidth > width then x, y = 0, y - 28 - CHIP_GAP end
		chip:SetPoint("TOPLEFT", x, y)
		x = x + chipWidth + CHIP_GAP
		chip.value = choice[1]
		chips[#chips + 1] = chip
	end
	return chips, y - 28 - ROW_GAP
end

function Tweaks:Build(page)
	self.stage = ob.Stage(page, STAGE_WIDTH, ob.Shell.PAGE_HEIGHT)
	self.stage:SetPoint("TOPLEFT")
	self.preview = ob.Preview:New(self.stage, STAGE_LAYOUT, { animated = true })
	local column = CreateFrame("Frame", nil, page)
	local width = ob.Shell.PAGE_WIDTH - STAGE_WIDTH - COLUMN_GAP
	column:SetPoint("TOPLEFT", STAGE_WIDTH + COLUMN_GAP, -2)
	column:SetSize(width, ob.Shell.PAGE_HEIGHT)
	self.rows = {}
	local top = 0
	for _, tweak in ipairs(Presets.tweaks) do
		self.rows[tweak.key], top = ChipRow(column, tweak, width, top)
	end
end

function Tweaks:Refresh()
	self.stage.caption:SetText(Pending.preset.name:upper() .. " + YOUR TWEAKS")
	self.stage.note:SetText("")
	self.preview:Show(Pending:Style(), Pending:Resolved().theme)
	for key, chips in pairs(self.rows) do
		local value = Pending:GetTweak(key)
		for _, chip in ipairs(chips) do chip:SetSelected(chip.value == value) end
	end
end

function Tweaks:Enter()
	self:Refresh()
end

function Tweaks:Leave()
	self.preview:Release()
end

function Tweaks:Tick(elapsed)
	self.preview:Tick(elapsed)
end
