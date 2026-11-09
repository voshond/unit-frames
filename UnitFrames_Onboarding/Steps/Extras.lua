local _, ob = ...
local UF = UnitFrames
local C, COLORS = UF.Skin.colors, ob.COLORS
local Pending, Presets = ob.Pending, ob.Presets

--[[
Step 3: a map of the screen. The frames themselves are fixed blocks; the
extras around them are tiles to switch on or off. Below it, whether the
look goes into a new profile. Next applies everything.
]]
local Extras = {
	label = "Extras",
	title = "Add the extras",
	subtitle = "Click a tile to switch it on or off. You'll drag everything into place in Edit Mode at the end.",
	nextLabel = "Apply and finish",
}
ob.Steps.Extras = Extras

local MAP_HEIGHT, TILE_WIDTH, TILE_HEIGHT, TILE_GAP = 400, 170, 28, 6

-- Fixed blocks (centre offsets on the map) and where each area's tiles start.
local BLOCKS = {
	{ label = "Player", x = -200, y = 50, width = 170, height = 44 },
	{ label = "Target", x = 200, y = 50, width = 170, height = 44 },
	{ label = "Focus", x = 200, y = 150, width = 150, height = 36 },
}
local AREAS = { player = { -200, 0 }, target = { 200, 0 }, focus = { 200, 108 }, center = { 0, -78 } }

local function Block(map, block)
	local frame = CreateFrame("Frame", nil, map, "BackdropTemplate")
	frame:SetSize(block.width, block.height)
	frame:SetPoint("CENTER", block.x, block.y)
	ob.Panel(frame, { C.accent[1], C.accent[2], C.accent[3], 0.1 }, { C.accent[1], C.accent[2], C.accent[3], 0.45 })
	local text = ob.Text(frame, 13, C.text, true)
	text:SetPoint("CENTER")
	text:SetText(block.label)
end

function Extras:Build(page)
	local map = ob.Stage(page, ob.Shell.PAGE_WIDTH, MAP_HEIGHT)
	map:SetPoint("TOPLEFT")
	self.map = map
	local bars = map:CreateTexture(nil, "ARTWORK")
	bars:SetColorTexture(1, 1, 1, 0.05)
	bars:SetSize(260, 14)
	bars:SetPoint("BOTTOM", 0, 14)
	local barsText = ob.Text(map, 10, COLORS.faint)
	barsText:SetPoint("CENTER", bars, "CENTER")
	barsText:SetText("action bars")
	for _, block in ipairs(BLOCKS) do Block(map, block) end

	self.tiles = {}
	local placed = {}
	for _, extra in ipairs(Presets.extras) do
		local area = AREAS[extra.area]
		local index = placed[extra.area] or 0
		placed[extra.area] = index + 1
		local tile = ob.Widgets.Chip:New(map, { text = extra.label, width = TILE_WIDTH, height = TILE_HEIGHT, dot = true,
			accent = extra.accent and COLORS[extra.accent] or nil, tooltip = extra.hint,
			onClick = function() Pending:SetExtra(extra.key, not Pending:GetExtra(extra.key)) end })
		tile:SetPoint("CENTER", area[1], area[2] - index * (TILE_HEIGHT + TILE_GAP))
		self.tiles[extra.key] = tile
	end

	self.newProfile = UF.Widgets.Checkbox:New(page, { label = "Save as a new profile",
		onChange = function(value) Pending:SetNewProfile(value); self:Refresh() end })
	self.newProfile:SetPoint("TOPLEFT", 0, -(MAP_HEIGHT + 20))
	self.newProfile:SetWidth(240)
	self.profileNote = ob.Text(page, 12, C.textDim)
	self.profileNote:SetPoint("TOPLEFT", 0, -(MAP_HEIGHT + 46))
	self.profileNote:SetWidth(ob.Shell.PAGE_WIDTH)
end

function Extras:Refresh()
	local on, count = 0, 0
	for key, tile in pairs(self.tiles) do
		local enabled = Pending:GetExtra(key)
		tile:SetSelected(enabled)
		count = count + 1
		if enabled then on = on + 1 end
	end
	self.map.caption:SetText(("%d OF %d EXTRAS ON"):format(on, count))
	self.map.note:SetText("Hover a tile to see what it adds.")
	self.newProfile:SetValue(Pending.newProfile)
	if Pending.newProfile then
		self.profileNote:SetText(("A new profile \"%s\" gets this look. Your current profile \"%s\" stays as it is.")
			:format(UF.Profiles:UniqueName(Pending.preset.name .. " look"), UF.Profiles:GetCurrent()))
	else
		self.profileNote:SetText(("This look replaces the style of your current profile \"%s\". Frame positions stay.")
			:format(UF.Profiles:GetCurrent()))
	end
end

function Extras:Enter()
	self:Refresh()
end
