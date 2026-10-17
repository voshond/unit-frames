local _, ns = ...
local StackIcon = ns.Components.StackIcon

--[[
The player's resting zZz in the decoration stack: Blizzard's own player frame
flipbook (PlayerFrame.xml PlayerRestLoop), looping while shown. Live frames
bind oUF's RestingIndicator; previews pass the sample resting state.
]]
local RestingIcon = StackIcon:Extend("RestingIcon")

RestingIcon.stackKey = "restingIcon"

RestingIcon.ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"
-- PlayerRestLoopAnim: 7 rows by 6 columns, 42 frames in 1.5 seconds.
RestingIcon.FLIPBOOK = { rows = 7, columns = 6, frames = 42, duration = 1.5 }

RestingIcon.schema = StackIcon.BuildIconSchema({ anchor = "TOPLEFT", order = 3, size = 20 })

function RestingIcon:OnCreate(parent, spec)
	StackIcon.OnCreate(self, parent, spec)
	self.texture.useAtlasSize = false
	self.texture:SetAtlas(RestingIcon.ATLAS)
	local flipbook = RestingIcon.FLIPBOOK
	self.animation = self.frame:CreateAnimationGroup()
	self.animation:SetLooping("REPEAT")
	self.flipbook = self.animation:CreateAnimation("FlipBook")
	self.flipbook:SetTarget(self.texture)
	self.flipbook:SetFlipBookRows(flipbook.rows)
	self.flipbook:SetFlipBookColumns(flipbook.columns)
	self.flipbook:SetFlipBookFrames(flipbook.frames)
	self.flipbook:SetDuration(flipbook.duration)
	-- oUF shows or hides the art and passes the resting state.
	self.texture.PostUpdate = function(_, resting) self:UpdateLoop(resting) end
end

function RestingIcon:UpdateLoop(resting)
	if resting then
		if not self.animation:IsPlaying() then self.animation:Play() end
	else
		self.animation:Stop()
	end
	self:Reflow()
end

-- resting: plain player state (IsResting or a sample).
function RestingIcon:SetResting(resting)
	resting = resting == true
	self.texture:SetShown(resting)
	self:UpdateLoop(resting)
end

function RestingIcon:OnRelease()
	self.animation:Stop()
	StackIcon.OnRelease(self)
end
