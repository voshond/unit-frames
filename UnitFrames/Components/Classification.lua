local _, ns = ...
local StackIcon = ns.Components.StackIcon

--[[
The unit's elite, rare-elite, rare or boss marker in the decoration stack.
Live frames drive it with the UF_Classification element (Units/Elements.lua);
previews pass the sample classification. Normal and minor units show nothing
and leave no gap.
]]
local Classification = StackIcon:Extend("Classification")

Classification.stackKey = "classification"

-- Blizzard's own Forever mapping (nameplate classification and damage meter).
Classification.ATLASES = {
	elite = "nameplates-icon-elite-gold",
	worldboss = "nameplates-icon-elite-gold",
	rareelite = "nameplates-icon-elite-silver",
	rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}

Classification.schema = StackIcon.BuildIconSchema({ anchor = "TOPRIGHT", size = 18 })

-- classification: a UnitClassification result (plain), or nil for none.
function Classification:SetClassification(classification)
	local atlas = classification and Classification.ATLASES[classification]
	if atlas then
		self.texture:SetAtlas(atlas)
		self.texture:Show()
	else
		self.texture:Hide()
	end
	self:Reflow()
end
