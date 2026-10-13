local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Blizzard player castbar", function()
	local ns, element, blizzard
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		element = ns.oUF.elements.UF_Castbar
		blizzard = Mock.NewObject("StatusBar", nil, "PlayerCastingBarFrame")
		blizzard:RegisterEvent("UNIT_SPELLCAST_START")
	end)

	local function Muted()
		return next(blizzard.__state.events) == nil and not blizzard:IsShown()
	end

	it("is muted by the player castbar and restored when it is disabled", function()
		local player = ns.Units.frames.player
		assert.is_true(element.enable(player, "player"))
		assert.is_true(Muted())
		element.disable(player)
		assert.is_true(blizzard.__state.events.UNIT_SPELLCAST_START)
		assert.is_true(blizzard.__state.events.PLAYER_ENTERING_WORLD)
	end)

	it("is restored by the frame that muted it, whichever unit oUF has swapped in", function()
		local player, pet = ns.Units.frames.player, ns.Units.frames.pet
		element.enable(player, "player")
		-- In a vehicle oUF swaps tokens: the pet frame shows the player.
		player.__unit, pet.__unit = "vehicle", "player"
		element.enable(pet, "player")
		element.disable(pet)
		assert.is_true(Muted(), "another frame's castbar does not unmute Blizzard's")
		element.disable(player)
		assert.is_true(blizzard.__state.events.UNIT_SPELLCAST_START, "the muting frame restores it")
	end)

	it("is left alone by castbars of other units", function()
		local target = ns.Units.frames.target
		element.enable(target, "target")
		element.disable(target)
		assert.same({ UNIT_SPELLCAST_START = true }, blizzard.__state.events)
		assert.is_true(blizzard:IsShown())
	end)
end)
