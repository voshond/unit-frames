local _, ns = ...
local Media, Backdrop = ns.Media, ns.Components.Backdrop

-- Shared fixed-size aura artwork. Owners supply style/size and retain native
-- selection, container layout, combat deferral and lifetime responsibilities.
local AuraIcon = {}
ns.AuraIcon = AuraIcon

local BORDER_PIECES = {
	"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "None" }
local dispelColorSchema = {}
for _, kind in ipairs(DISPEL_TYPES) do
	dispelColorSchema[#dispelColorSchema + 1] = {
		key = kind, type = "color", label = kind == "None" and "No dispel type" or kind,
		default = { AuraUtil.GetAuraBorderColor(kind):GetRGBA() },
	}
end

local durationFormatter
local function DurationFormatter()
	if not durationFormatter then
		durationFormatter = C_StringUtil.CreateSecondsFormatter()
		durationFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
		durationFormatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
		durationFormatter:SetCanRoundUpLastUnit(true)
		durationFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
		durationFormatter:SetMaxIntervalCurve(AuraContainerInbound.GetDefaultAuraDurationFormatter():GetMaxIntervalCurve())
		durationFormatter:SetDesiredUnitCount(1)
		durationFormatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale)
	end
	return durationFormatter
end

AuraIcon.DURATION_POSITIONS = {
	{ "below", "Below the icon" }, { "CENTER", "Inside: centre" },
	{ "TOP", "Inside: top" }, { "BOTTOM", "Inside: bottom" },
}

AuraIcon.schema = {
	{ key = "showDuration", type = "toggle", label = "Show time left", default = true },
	{ key = "durationPosition", type = "select", label = "Time position", values = AuraIcon.DURATION_POSITIONS, default = "below" },
	{ key = "durationSize", type = "range", label = "Time text size", min = 6, max = 32, step = 1, default = 10 },
	{ key = "showCount", type = "toggle", label = "Show stacks", default = true },
	{ key = "countSize", type = "range", label = "Stack text size", min = 6, max = 32, step = 1, default = 10 },
	{ key = "font", type = "font", label = "Font", inherit = "font" },
	{ key = "fontOutline", type = "select", label = "Font outline", values = ns.Theme.OUTLINES, default = "OUTLINE" },
	{ key = "dispelBorder", type = "toggle", label = "Colour debuff border by type", default = true,
		tooltip = "Tint the entire icon frame using Debuff border colours. Disable to use Icon frame > Border colour for every icon. Works in combat." },
	{ key = "dispelColors", type = "group", label = "Debuff border colours", schema = dispelColorSchema },
	{ key = "border", type = "group", label = "Icon frame", schema = Backdrop.schema,
		defaults = { size = 8, inset = 1, padding = 2, background = "None" } },
}

-- Returns `previous` when every colour is unchanged, so registered dispel
-- textures can keep their engine-side copy of the map.
function AuraIcon.DispelColors(cfg, previous)
	if previous then
		local same = true
		for _, kind in ipairs(DISPEL_TYPES) do
			local r, g, b, a = ns.Util.UnpackColor(cfg.dispelColors[kind])
			local pr, pg, pb, pa = previous[kind]:GetRGBA()
			if r ~= pr or g ~= pg or b ~= pb or a ~= pa then same = false; break end
		end
		if same then return previous end
	end
	local colors = {}
	for _, kind in ipairs(DISPEL_TYPES) do colors[kind] = CreateColor(ns.Util.UnpackColor(cfg.dispelColors[kind])) end
	return colors
end

-- kind: the owner's key for this button's settings ("buffs", "slot1", ...).
-- opts: harmful (debuff art and dispel tint), clickThrough, cancelBuffs.
function AuraIcon.Create(button, kind, preview, opts)
	ns.Perf:Count(preview and "sampleAuraButtonCreate" or "auraButtonCreate")
	opts = opts or {}
	button.ufKind = kind
	button.ufHarmful = opts.harmful == true
	button.ufPreview = preview and true or false
	-- The button includes the below-icon timer in its layout bounds. The
	-- artwork stays square, even when the container flows upwards.
	local iconFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
	iconFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	button.ufIconFrame = iconFrame

	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.ufIcon = icon
	if not preview then button:SetIcon(icon) end

	local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
	cooldown:SetHideCountdownNumbers(true)
	button.ufCooldown = cooldown
	if not preview then button:SetDurationCooldown(cooldown) end

	local cover = CreateFrame("Frame", nil, iconFrame)
	cover:SetAllPoints(iconFrame)
	cover:SetFrameLevel(cooldown:GetFrameLevel() + 1)

	-- The engine fills registered texts immediately, before OnApply.
	button.ufCountHolder = CreateFrame("Frame", nil, cover)
	button.ufCountHolder:SetAllPoints(iconFrame)
	button.ufCount = button.ufCountHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.ufCount:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
	if not preview then button:SetApplicationCount(button.ufCount, {}) end

	button.ufTime = cover:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	if not preview then button:SetDurationText(button.ufTime, { textFormatter = DurationFormatter() }) end

	-- A separate themed border lets the engine own the complete edge's
	-- colour/shown state. Hide the holder to toggle type colouring, and
	-- make the base edge transparent so no neutral border shows through.
	button.ufBorder = CreateFrame("Frame", nil, cover, "BackdropTemplate")
	button.ufBorder:SetAllPoints(iconFrame)
	button.ufDispelTextures = {}
	if preview then
		button:EnableMouse(false)
	else
		button:EnableMouse(true)
		if opts.clickThrough then button:SetMouseClickEnabled(false) end
		button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
		-- The native secure click handler cancels the button's current aura;
		-- addon code never reads its unit data or secret instance ID.
		-- Cancel on press before propagated input can start world mouselook.
		if opts.cancelBuffs and not button.ufHarmful then
			button:SetCancelAuraButtons("RightButtonDown")
		end
	end
end

function AuraIcon.TextRoom(cfg)
	return cfg.showDuration and cfg.durationPosition == "below" and cfg.durationSize + 2 or 0
end

function AuraIcon.Apply(button, cfg, size, dispelColors)
	button:SetSize(size, size + AuraIcon.TextRoom(cfg))
	button.ufIconFrame:SetSize(size, size)
	Backdrop.ApplyToFixedSize(button.ufIconFrame, cfg.border, size, size)
	-- Keep a drawable centre even at the smallest icon size.
	local pad = cfg.border.enabled and math.min(cfg.border.padding, (size - 2) / 2) or 0
	for _, region in ipairs({ button.ufIcon, button.ufCooldown }) do
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", button.ufIconFrame, "TOPLEFT", pad, -pad)
		region:SetPoint("BOTTOMRIGHT", button.ufIconFrame, "BOTTOMRIGHT", -pad, pad)
	end
	for _, entry in ipairs({ { button.ufCount, cfg.countSize }, { button.ufTime, cfg.durationSize } }) do
		Media:ApplyFont(entry[1], cfg.font, entry[2], cfg.fontOutline)
	end
	button.ufTime:ClearAllPoints()
	if cfg.durationPosition == "below" then
		button.ufTime:SetPoint("TOP", button.ufIconFrame, "BOTTOM", 0, -1)
	else
		local y = cfg.durationPosition == "TOP" and -2 or cfg.durationPosition == "BOTTOM" and 2 or 0
		button.ufTime:SetPoint(cfg.durationPosition, button.ufIconFrame, cfg.durationPosition, 0, y)
	end
	button.ufCountHolder:SetShown(cfg.showCount)
	button.ufTime:SetShown(cfg.showDuration)
	AuraIcon.ApplyDispelBorder(button, cfg, size, dispelColors)
end

-- Per button: the reused border settings (the icon border without a
-- background) and what the dispel textures were last registered with.
local dispelBorders = setmetatable({}, { __mode = "k" })
function AuraIcon.ApplyDispelBorder(button, cfg, size, dispelColors)
	local enabled = cfg.border.enabled and cfg.dispelBorder and button.ufHarmful or false
	local state = dispelBorders[button]
	if not state then
		state = { border = {} }
		dispelBorders[button] = state
	end
	local border = state.border
	for key, value in pairs(cfg.border) do border[key] = value end
	border.background = "None"
	local info = enabled and Backdrop.Info(border) or nil
	-- Registration is expensive in the engine (options are copied and the
	-- button redrawn per texture). Unchanged artwork, size and colours keep
	-- the engine's tint; only the icon frame's border, which applying the
	-- icon backdrop recoloured, is hidden again.
	if state.applied and state.enabled == enabled and state.info == info and state.size == size
		and state.colors == dispelColors then
		if state.registered then button.ufIconFrame:SetBackdropBorderColor(0, 0, 0, 0) end
		return
	end
	state.applied, state.enabled, state.info, state.size, state.colors = true, enabled, info, size, dispelColors
	state.registered = false
	-- Re-register after applying the backdrop: its setters reset vertex
	-- colours, and inbound options are copied by the engine, not shared.
	if not button.ufPreview then
		for _, texture in ipairs(button.ufDispelTextures) do button:RemoveDispelTypeTexture(texture) end
	end
	button.ufDispelTextures = {}
	button.ufBorder:SetShown(enabled)
	if not enabled then
		button.ufBorder:ClearBackdrop()
		return
	end
	local backdrop = Backdrop.ApplyToFixedSize(button.ufBorder, border, size, size)
	if backdrop and backdrop.edgeFile then
		state.registered = true
		button.ufIconFrame:SetBackdropBorderColor(0, 0, 0, 0)
		if not button.ufPreview then ns.Perf:Begin("dispel registration") end
		for _, piece in ipairs(BORDER_PIECES) do
			local texture = button.ufBorder[piece]
			button.ufDispelTextures[#button.ufDispelTextures + 1] = texture
			if not button.ufPreview then
				button:AddDispelTypeTexture(texture, {
					style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
					showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
					customDispelColorMap = dispelColors,
				})
				ns.Perf:Count("auraDispelRegister")
			end
		end
		if not button.ufPreview then ns.Perf:End("dispel registration") end
	end
end

function AuraIcon.DrawSample(button, aura, dispelColors)
	button.ufIcon:SetTexture(aura.icon)
	button.ufCount:SetText((aura.applications or 1) > 1 and aura.applications or "")
	local duration = aura.duration or 0
	local remaining = aura.remaining or duration
	button.ufTime:SetText(duration > 0 and DurationFormatter():Format(remaining) or "")
	if duration > 0 then
		button.ufCooldown:SetCooldown(GetTime() - (duration - remaining), duration)
		button.ufCooldown:Pause()
		button.ufCooldown:Show()
	else
		button.ufCooldown:Hide()
	end
	if button.ufHarmful then
		local color = dispelColors[aura.dispelName or "None"] or dispelColors.None
		for _, texture in ipairs(button.ufDispelTextures) do texture:SetVertexColor(color:GetRGBA()) end
	end
end
