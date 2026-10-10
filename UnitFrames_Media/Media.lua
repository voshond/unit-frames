local addonName = ...
local LSM = LibStub("LibSharedMedia-3.0")

--[[
Fonts registered with LibSharedMedia: they show up in every font picker of
UnitFrames (and of other addons using LibSharedMedia).

To add a font:
  1. copy the .ttf/.otf file into this addon's Fonts folder
     (static files; WoW can't pick weights from a variable font)
  2. add a line below: { "Name shown in the picker", "FileName.ttf" }
  3. restart the game client (new files aren't picked up by /reload)
]]
local FONTS = {
	{ "Roboto Condensed Light", "RobotoCondensed-Light.ttf" },
	{ "Roboto Condensed", "RobotoCondensed-Regular.ttf" },
	{ "Roboto Condensed Medium", "RobotoCondensed-Medium.ttf" },
	{ "Roboto Condensed Bold", "RobotoCondensed-Bold.ttf" },
}

-- Scripts the fonts contain glyphs for. Roboto covers Latin and Cyrillic;
-- use LSM.LOCALE_BIT_western alone for fonts without Cyrillic.
local LANGUAGES = LSM.LOCALE_BIT_western + LSM.LOCALE_BIT_ruRU

local folder = [[Interface\AddOns\]] .. addonName .. [[\Fonts\]]
for _, font in ipairs(FONTS) do
	LSM:Register("font", font[1], folder .. font[2], LANGUAGES)
end
