local _, ob = ...
local UF = UnitFrames
local C, COLORS = UF.Skin.colors, ob.COLORS
local Pending = ob.Pending

--[[
Step 4: the look is saved. One button into Edit Mode to place the frames,
and cards that open the Workbench where each topic lives.
]]
local Ready = {
	label = "Ready",
	title = "",
	subtitle = "",
	nextLabel = "Close",
}
ob.Steps.Ready = Ready

local ICONS = [[Interface\Icons\]]
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 248, 92, 13

local DESTINATIONS = {
	{ title = "Buffs & debuffs", body = "Icon sizes, filters, dispel colours", icon = ICONS .. "Spell_Holy_WordFortitude",
		entry = "unit.player", path = "auras" },
	{ title = "Texts", body = "Names, values, percentages, custom texts", icon = ICONS .. "Spell_Nature_Regeneration",
		entry = "unit.player", path = "health.left" },
	{ title = "Castbar & timers", body = "Global cooldown, swing and ranged timers", icon = ICONS .. "Spell_Frost_FrostBolt02",
		entry = "timers" },
	{ title = "Party & raid", body = "ClickGrid panels and click casting", icon = ICONS .. "Spell_Holy_FlashHeal",
		entry = "clickgrid.panel", addon = "UnitFrames_ClickGrid" },
	{ title = "Import a string", body = "Paste a style someone shared", icon = ICONS .. "Spell_Nature_StarFall",
		entry = "profiles" },
	{ title = "Everything else", body = "The whole Workbench (/uf wb)", icon = [[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]],
		coords = { 0, 0.25, 0, 0.25 }, entry = "unit.player" },
}

local function DigCard(parent, destination, owner)
	local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	ob.Panel(card, C.panel, C.border)
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(destination.icon)
	if destination.coords then icon:SetTexCoord(unpack(destination.coords)) end
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", 16, -16)
	local title = ob.Text(card, 14, C.text, true)
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -2)
	title:SetText(destination.title)
	local body = ob.Text(card, 11, C.textDim)
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	body:SetWidth(CARD_WIDTH - 96)
	body:SetWordWrap(true)
	body:SetText(destination.body)
	local arrow = ob.Text(card, 16, COLORS.faint, true)
	arrow:SetPoint("TOPRIGHT", -14, -16)
	arrow:SetText(">")
	card:SetScript("OnEnter", function() ob.Paint(card, C.buttonHover, C.accent); arrow:SetTextColor(unpack(C.accent)) end)
	card:SetScript("OnLeave", function() ob.Paint(card, C.panel, C.border); arrow:SetTextColor(unpack(COLORS.faint)) end)
	card:SetScript("OnClick", function()
		owner:Close()
		UF:OpenWorkbench(destination.entry, destination.path)
	end)
	return card
end

local function CanEnterEditMode()
	return EditModeManagerFrame ~= nil and EditModeManagerFrame:CanEnterEditMode()
end

function Ready:Build(page, owner)
	local center = ob.Shell.PAGE_WIDTH / 2
	local badge = CreateFrame("Frame", nil, page, "BackdropTemplate")
	badge:SetSize(56, 56)
	badge:SetPoint("TOP", page, "TOPLEFT", center, -16)
	ob.Panel(badge, C.accent)
	ob.Glow(badge, C.accent):Show()
	local check = badge:CreateTexture(nil, "OVERLAY")
	check:SetTexture(ob.CHECK)
	check:SetVertexColor(unpack(COLORS.ink))
	check:SetPoint("TOPLEFT", 6, -6)
	check:SetPoint("BOTTOMRIGHT", -6, 6)
	local heading = ob.Text(page, 30, C.text, true)
	heading:SetPoint("TOP", badge, "BOTTOM", 0, -18)
	heading:SetText("You're set.")
	self.summary = ob.Text(page, 13, C.textDim)
	self.summary:SetPoint("TOP", heading, "BOTTOM", 0, -10)
	self.summary:SetJustifyH("CENTER")

	self.editMode = UF.Widgets.Button:New(page, { text = "Place frames in Edit Mode", width = 280, height = 36,
		onClick = function()
			owner:Close()
			if CanEnterEditMode() then ShowUIPanel(EditModeManagerFrame) end
		end })
	self.editMode:SetPoint("TOP", self.summary, "BOTTOM", 0, -20)
	self.editMode:SetSelected(true)

	local label = ob.Text(page, 10, C.textDim, true)
	label:SetPoint("TOPLEFT", 0, -252)
	label:SetText("DIG DEEPER WHEN YOU FEEL LIKE IT")
	local index = 0
	for _, destination in ipairs(DESTINATIONS) do
		if not destination.addon or C_AddOns.IsAddOnLoaded(destination.addon) then
			local card = DigCard(page, destination, owner)
			card:SetPoint("TOPLEFT", (index % 3) * (CARD_WIDTH + CARD_GAP), -270 - math.floor(index / 3) * (CARD_HEIGHT + CARD_GAP))
			index = index + 1
		end
	end
end

function Ready:Enter()
	local profile = Pending.result or UF.Profiles:GetCurrent()
	if Pending.newProfile then
		self.summary:SetText(("Saved as the profile \"%s\". Your previous look is still one switch away in Profiles."):format(profile))
	else
		self.summary:SetText(("Applied to your profile \"%s\". Frame positions stayed where they were."):format(profile))
	end
	self.editMode:SetShown(CanEnterEditMode())
end
