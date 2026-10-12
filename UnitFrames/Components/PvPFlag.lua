local _, ns = ...
local StackIcon = ns.Components.StackIcon

--[[
The unit's PvP flag in the decoration stack. Live frames bind oUF's
PvPIndicator, which on Forever hands both textures to Blizzard's secret-safe
UnitFrameUtil.UpdateUnitPvPIndicator: it picks Alliance, Horde (accounting
for mercenary mode) or free-for-all art and shows or hides the icon and its
background circle. Previews use SetSample with plain sample states.
]]
local PvPFlag = StackIcon:Extend("PvPFlag")

PvPFlag.stackKey = "pvp"

-- Forever's flag icons sit on this circle, like Blizzard's own frames.
PvPFlag.BACKGROUND_ATLAS = "UI-HUD-UnitFrame-SmallCircle"

PvPFlag.schema = StackIcon.BuildIconSchema({ anchor = "TOPLEFT", order = 2, size = 18 })
PvPFlag.schema[#PvPFlag.schema + 1] = { key = "background", type = "toggle", label = "Background circle", default = true,
	tooltip = "Draw the flag on the game's dark circle, as on the default unit frames." }

function PvPFlag:OnCreate(parent)
	StackIcon.OnCreate(self, parent)
	-- Configured size only: never the atlas size.
	self.texture.useAtlasSize = false
	-- The circle art is opaque; keep it below the flag.
	self.background = self.frame:CreateTexture(nil, "OVERLAY", nil, -1)
	self.background:SetAllPoints(self.frame)
	self.background:SetAtlas(PvPFlag.BACKGROUND_ATLAS)
	self.background:Hide()
end

-- oUF reads the Background sub-widget when the element is enabled; the
-- binding re-enables the element when it changes.
function PvPFlag:OnApply(cfg)
	StackIcon.OnApply(self, cfg)
	self.texture.Background = self:GetBackground()
	if not cfg.background then
		self.background:Hide()
	end
end

-- The enabled background circle, or nil.
function PvPFlag:GetBackground()
	return self.resolved.background and self.background or nil
end

-- state: "off", "Alliance", "Horde" or "FFA" (Formats.PVP_FLAGS).
function PvPFlag:SetSample(state)
	local atlas = ns.Formats.PVP_ATLASES[state]
	if atlas then
		self.texture:SetAtlas(atlas)
		self.texture:Show()
	else
		self.texture:Hide()
	end
	self.background:SetShown(atlas ~= nil and self.resolved.background)
	self:Reflow()
end
