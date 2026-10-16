local _, ns = ...
local Media, Util = ns.Media, ns.Util

-- Background + border around a frame. Defaults come from the theme, which
-- uses Blizzard's tooltip border for the chamfered "classic" look.
--
-- Other components embed it as a `border` group and call Backdrop.ApplyTo.
local Backdrop = ns.Component:Extend("Backdrop")
Backdrop.LEVELS = { border = 20, frame = 60, panel = 100, decorations = 120 }

local BORDER_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
local RAID_FILES = { "UpperLeft", "UpperRight", "BottomLeft", "BottomRight",
	"UpperMiddle", "BottomMiddle", "Left", "Right" }
local raidBorders = setmetatable({}, { __mode = "k" })
local overlays = setmetatable({}, { __mode = "k" })

-- Only the edge textures move above the content; the background stays below.
-- Fixed relative tiers avoid inspecting potentially secret aura descendants.
function Backdrop.SetBorderLevel(frame, level)
	local overlay = overlays[frame]
	if not overlay then
		overlay = CreateFrame("Frame", nil, frame)
		overlay:SetAllPoints(frame)
		overlays[frame] = overlay
	end
	overlay:SetFrameLevel(level or frame:GetFrameLevel() + Backdrop.LEVELS.border)
	for _, piece in ipairs(BORDER_PIECES) do
		local texture = rawget(frame, piece)
		if texture then texture:SetParent(overlay) end
	end
	local raid = raidBorders[frame]
	if raid then raid:SetFrameLevel(overlay:GetFrameLevel()) end
end

-- Separate textures leave BackdropTemplate's background and UV calculations
-- intact. Native anchors resize the artwork without reading frame dimensions.
local function ApplyRaidBorder(frame, size)
	local art = raidBorders[frame]
	if not art then
		art = CreateFrame("Frame", nil, frame)
		art:SetAllPoints(frame)
		art:SetFrameLevel(frame:GetFrameLevel())
		raidBorders[frame] = art
		for i, piece in ipairs(BORDER_PIECES) do
			local texture = art:CreateTexture(nil, "ARTWORK")
			texture:SetTexture("Interface\\RaidFrame\\RaidBorder-" .. RAID_FILES[i])
			if i == 5 or i == 6 then texture:SetHorizTile(true) end
			if i == 7 or i == 8 then texture:SetVertTile(true) end
			art[piece] = texture
		end
	end
	art:Show()
	local t, scale = {}, size / 16
	for i, piece in ipairs(BORDER_PIECES) do
		t[i] = art[piece]
		t[i]:ClearAllPoints()
	end
	-- Blizzard_CompactRaidFrameContainer.xml: 32px corners, 16px edges,
	-- with asymmetric offsets for the artwork's transparent padding.
	for i = 1, 4 do t[i]:SetSize(size * 2, size * 2) end
	t[1]:SetPoint("TOPLEFT", art, "TOPLEFT", -5 * scale, 0)
	t[2]:SetPoint("TOPRIGHT", art, "TOPRIGHT")
	t[3]:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", -5 * scale, 0)
	t[4]:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT")
	t[5]:SetHeight(size)
	t[5]:SetPoint("TOPLEFT", t[1], "TOPRIGHT", 0, scale)
	t[5]:SetPoint("TOPRIGHT", t[2], "TOPLEFT", 0, scale)
	t[6]:SetHeight(size)
	t[6]:SetPoint("BOTTOMLEFT", t[3], "BOTTOMRIGHT", 0, -4 * scale)
	t[6]:SetPoint("BOTTOMRIGHT", t[4], "BOTTOMLEFT", 0, -4 * scale)
	t[7]:SetWidth(size)
	t[7]:SetPoint("TOPLEFT", t[1], "BOTTOMLEFT", -scale, 0)
	t[7]:SetPoint("BOTTOMLEFT", t[3], "TOPLEFT", -scale, 0)
	t[8]:SetWidth(size)
	t[8]:SetPoint("TOPRIGHT", t[2], "BOTTOMRIGHT", 2 * scale, 0)
	t[8]:SetPoint("BOTTOMRIGHT", t[4], "TOPRIGHT", 2 * scale, 0)
end

-- Shared by resting tints and native aura dispel registration.
function Backdrop.BorderTextures(frame)
	local owner = raidBorders[frame]
	if not (owner and owner:IsShown()) then owner = frame end
	local textures = {}
	for _, piece in ipairs(BORDER_PIECES) do
		local texture = rawget(owner, piece)
		if texture then textures[#textures + 1] = texture end
	end
	return textures
end

function Backdrop.SetBorderColor(frame, r, g, b, a)
	frame:SetBackdropBorderColor(r, g, b, a)
	local art = raidBorders[frame]
	if art then
		for _, piece in ipairs(BORDER_PIECES) do art[piece]:SetVertexColor(r, g, b, a) end
	end
end

Backdrop.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "separatePadding", type = "toggle", label = "Content padding per side", default = false,
		tooltip = "Enable to show separate Left, Right, Top and Bottom padding controls below.",
		onSet = function(config, value, before)
			if value and not before.separatePadding then
				for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
					if config["padding" .. side] == nil then config["padding" .. side] = before.padding end
				end
			end
		end },
	{ key = "padding", type = "range", label = "Content padding", min = 0, max = 40, step = 1, default = 4,
		hidden = function(cfg) return cfg.separatePadding end,
		tooltip = "Space between the border and the content inside it." },
	{ key = "border", type = "border", label = "Border", inherit = "borderTexture" },
	{ key = "size", type = "range", label = "Border size", min = 1, max = 32, step = 1, inherit = "borderSize" },
	{ key = "color", type = "color", label = "Border colour", inherit = "borderColor" },
	{ key = "background", type = "background", label = "Background", inherit = "backgroundTexture" },
	{ key = "backgroundColor", type = "color", label = "Background colour", inherit = "backgroundColor" },
}
for i, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
	table.insert(Backdrop.schema, 3 + i, { key = "padding" .. side, type = "range",
		label = side .. " padding", min = 0, max = 40, step = 1, default = 4,
		hidden = function(cfg) return not cfg.separatePadding end })
end

local insetOptions = {
	{ key = "separateInset", type = "toggle", label = "Background inset per side", default = false,
		tooltip = "Enable to show separate Left, Right, Top and Bottom background insets. Content padding is unchanged.",
		onSet = function(config, value, before)
			if value and not before.separateInset then
				for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
					if config["inset" .. side] == nil then config["inset" .. side] = before.inset end
				end
			end
		end },
	{ key = "inset", type = "range", label = "Background inset", min = 0, max = 16, step = 1, default = 3,
		hidden = function(cfg) return cfg.separateInset end,
		tooltip = "How far the background is pulled in from the outer edge, so it doesn't poke out of rounded corners." },
}
for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
	insetOptions[#insetOptions + 1] = { key = "inset" .. side, type = "range", label = side .. " background inset",
		min = 0, max = 16, step = 1, default = 3, hidden = function(cfg) return not cfg.separateInset end }
end
Backdrop.schema = ns.Schema.Insert(Backdrop.schema, "paddingBottom", insetOptions)

-- Aura presentation keeps its existing uniform padding and layering.
-- Decorative backgrounds offer only the artwork controls.
Backdrop.artSchema = {}
for _, option in ipairs(Backdrop.schema) do
	if option.key ~= "separatePadding" and not option.key:match("^padding")
		and option.key ~= "separateInset" and not option.key:match("^inset[A-Z]") and option.key ~= "inset" then
		Backdrop.artSchema[#Backdrop.artSchema + 1] = option
	end
end
local auraInset = Util.Copy(ns.Schema.Find(Backdrop.schema, "inset"))
auraInset.hidden = nil
Backdrop.artSchema[#Backdrop.artSchema + 1] = auraInset
local auraPadding = Util.Copy(ns.Schema.Find(Backdrop.schema, "padding"))
auraPadding.max, auraPadding.hidden = 16, nil
Backdrop.auraSchema = ns.Schema.Concat(Backdrop.artSchema, { auraPadding })

-- Shared plain geometry: left, right, top, bottom. Insets affect only the
-- background; padding reserves space for the content independently per side.
function Backdrop.Padding(cfg)
	if not cfg.enabled then return 0, 0, 0, 0 end
	if cfg.separatePadding then
		return cfg.paddingLeft, cfg.paddingRight, cfg.paddingTop, cfg.paddingBottom
	end
	return cfg.padding, cfg.padding, cfg.padding, cfg.padding
end

-- LSM's "None" entries are "", which BackdropTemplate treats as a texture.
local function Path(kind, key)
	local path = Media:Fetch(kind, key)
	if path == "" then
		return nil
	end
	return path
end

-- BackdropTemplate rebuilds its nine-slice layout and texture coordinates
-- unless it receives the info table it already holds, so equal settings share
-- one immutable table. Live tables are held by the frames that use them.
local infos = setmetatable({}, { __mode = "v" })
local function Info(cfg)
	local raid = cfg.border == "Blizzard Raid"
	local bgFile = Path("background", cfg.background)
	local edgeFile = not raid and Path("border", cfg.border) or nil
	if not (bgFile or edgeFile or raid) then
		return nil
	end
	local left, right, top, bottom = cfg.inset, cfg.inset, cfg.inset, cfg.inset
	if cfg.separateInset then left, right, top, bottom = cfg.insetLeft, cfg.insetRight, cfg.insetTop, cfg.insetBottom end
	local key = tostring(bgFile) .. "\0" .. tostring(edgeFile) .. "\0" .. cfg.size
		.. "\0" .. left .. "\0" .. right .. "\0" .. top .. "\0" .. bottom .. "\0" .. tostring(raid)
	local info = infos[key]
	if not info then
		info = {
			raidBorder = raid,
			bgFile = bgFile,
			edgeFile = edgeFile,
			edgeSize = cfg.size,
			tile = true,
			tileSize = 16,
			insets = { left = left, right = right, top = top, bottom = bottom },
		}
		infos[key] = info
	end
	return info
end

-- The shared info for resolved settings, without applying it (nil: nothing drawn).
Backdrop.Info = Info

-- Applies resolved backdrop settings to a frame created with "BackdropTemplate".
-- Returns the applied info (shared; never modify it), or nil when nothing is drawn.
function Backdrop.ApplyTo(frame, cfg, raiseBorder)
	if raidBorders[frame] then raidBorders[frame]:Hide() end
	if not cfg.enabled then
		frame:ClearBackdrop()
		return nil
	end
	local info = Info(cfg)
	if info then
		frame:SetBackdrop(info)
	else
		frame:ClearBackdrop()
	end
	frame:SetBackdropColor(Util.UnpackColor(cfg.backgroundColor))
	if info and info.raidBorder then ApplyRaidBorder(frame, cfg.size) end
	if raiseBorder ~= false and info and (info.edgeFile or info.raidBorder) then Backdrop.SetBorderLevel(frame) end
	Backdrop.SetBorderColor(frame, Util.UnpackColor(cfg.color))
	return info
end

-- Aura descendants can report secret dimensions even outside combat.
-- BackdropTemplate's Lua UV calculation does arithmetic on GetWidth/Height;
-- provide the known configured size to that calculation instead. Region
-- methods still operate on the real textures, never on this geometry view.
local fixedSizes = setmetatable({}, { __mode = "k" })
function Backdrop.ApplyToFixedSize(frame, cfg, width, height, raiseBorder)
	local geometry = fixedSizes[frame]
	if not geometry then
		geometry = setmetatable({}, { __index = function(_, key) return frame[key] end })
		geometry.GetWidth = function() return geometry.width end
		geometry.GetHeight = function() return geometry.height end
		geometry.GetEffectiveScale = function() return frame:GetEffectiveScale() end
		geometry.GetEdgeSize = function() return frame:GetEdgeSize() end
		fixedSizes[frame] = geometry
		-- The owner updates the fixed size explicitly. Do not run an addon
		-- size-change script when Blizzard changes the aura's secret layout.
		frame:SetScript("OnSizeChanged", nil)
		frame.SetupTextureCoordinates = function()
			BackdropTemplateMixin.SetupTextureCoordinates(geometry)
		end
	end
	local resized = geometry.width ~= width or geometry.height ~= height
	geometry.width, geometry.height = width, height
	local previous = geometry.info
	local info = Backdrop.ApplyTo(frame, cfg, raiseBorder)
	geometry.info = info
	-- An unchanged backdrop is not reapplied; its UVs still follow the new size.
	if info and (info.bgFile or info.edgeFile) and info == previous and resized then
		frame:SetupTextureCoordinates()
	end
	return info
end

-- Anchors `content` inside `frame`, leaving room for the border.
function Backdrop.Inset(content, frame, cfg)
	local left, right, top, bottom = Backdrop.Padding(cfg)
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -right, bottom)
end

function Backdrop:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
end

function Backdrop:OnApply(cfg)
	Backdrop.ApplyTo(self.frame, cfg)
end

-- A disabled backdrop stays shown (it may hold content) but draws nothing.
function Backdrop:SetEnabled(enabled)
	self.enabled = enabled and true or false
end
