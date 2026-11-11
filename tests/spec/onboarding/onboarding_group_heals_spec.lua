local Helpers = require("helpers")

describe("Getting started heals on group frames #onboarding #buffs", function()
	local function As(class)
		UnitClass = function() return class, class, 1 end
	end

	local function LoadWithClickGrid()
		local ns, cg = Helpers.LoadClickGrid()
		local ob = Helpers.LoadToc("UnitFrames_Onboarding/UnitFrames_Onboarding.toc", "UnitFrames_Onboarding")
		C_AddOns.LoadAddOn = function(name) return name == "UnitFrames_Onboarding" end
		ob.Pending:Reset()
		return ns, cg, ob
	end

	local function Offered(ob)
		return ob.Presets.Available(ob.Presets.extrasByKey.groupHeals, ob.Pending)
	end

	it("is offered for the Healer look or a healing class, only with ClickGrid loaded", function()
		local _, _, ob = Helpers.LoadOnboarding()
		As("DRUID")
		ob.Pending:Reset()
		ob.Pending:SelectPreset("healer")
		assert.is_false(Offered(ob))

		_, _, ob = LoadWithClickGrid()
		As("WARRIOR")
		assert.is_false(Offered(ob))
		ob.Pending:SelectPreset("healer")
		assert.is_true(Offered(ob))
		for _, class in ipairs({ "DRUID", "PRIEST", "PALADIN", "SHAMAN" }) do
			As(class)
			ob.Pending:SelectPreset("default")
			assert.is_true(Offered(ob), class)
		end
	end)

	it("shows the tile and its placements on the Extras step only when offered", function()
		local ns, _, ob = LoadWithClickGrid()
		As("WARRIOR")
		ns.Onboarding:Open()
		ns.Onboarding:Next()
		ns.Onboarding:Next()
		local extras = ob.Steps.Extras
		assert.is_false(extras.tiles.groupHeals:IsShown())
		for _, chip in ipairs(extras.choices.groupHeals) do assert.is_false(chip:IsShown()) end
		assert.is_not_nil(extras.map.caption:GetText():find((" OF %d EXTRAS ON"):format(#ob.Presets.extras - 1), 1, true))

		ns.Onboarding:Jump(1)
		ob.Pending:SelectPreset("healer")
		ns.Onboarding:Next()
		ns.Onboarding:Next()
		assert.is_true(extras.tiles.groupHeals:IsShown())
		assert.is_true(extras.tiles.groupHeals.selected, "ClickGrid already shows my heals outside")
		assert.is_true(extras.choices.groupHeals[1].selected)
		extras.choices.groupHeals[3].frame:RunScript("OnClick")
		assert.equals("bar", ob.Pending:GetExtraChoice("groupHeals"))
		assert.is_true(extras.choices.groupHeals[3].selected)
		assert.is_false(extras.choices.groupHeals[1].selected)
	end)

	it("applies My heals & shields in the chosen placement through the pending style", function()
		local ns, cg, ob = LoadWithClickGrid()
		As("DRUID")
		cg.Config:SetStyle("target", "shown", true)
		cg.Config:SetStyle("member", "width", 140)
		local pending = ob.Pending
		pending:SelectPreset("healer")
		pending:SetNewProfile(false)
		pending:SetExtraChoice("groupHeals", "inside")
		local apply, dropped = ns.Profiles:Prepare("style", pending:Style())
		assert.is_not_nil(apply)
		assert.same({}, dropped)
		assert.is_false(cg.Config:Resolved().slots.slot1.enabled, "nothing is saved before Apply")

		assert.is_true(pending:Apply())
		local slots = cg.Config:Resolved().slots
		assert.is_true(slots.slot1.enabled)
		assert.equals("774", slots.slot1.spell)
		assert.equals("TOPLEFT", slots.slot1.anchor)
		assert.is_false(cg.Config.styles.member:Resolved().auras.buffs.enabled)
		assert.is_true(cg.Config.styles.target:Resolved().shown, "other ClickGrid settings stay")
		assert.equals(140, cg.Config.styles.member:Resolved().width)
	end)

	it("drops only the heals set when switched off", function()
		local _, cg, ob = LoadWithClickGrid()
		As("PRIEST")
		local pending = ob.Pending
		pending:SetExtra("groupHeals", false)
		assert.is_false(pending:GetExtra("groupHeals"))
		local member = pending:Style().clickgrid.member
		assert.is_false(member.auras.buffs.enabled)

		cg.Config:SetStyle("member", "auras.buffs.filter", "HELPFUL")
		pending:Changed()
		assert.is_nil(UnitFrames.Util.GetPath(pending:Style().clickgrid.member, "auras.buffs.enabled"),
			"a different buff filter is not the heals set")
	end)

	it("leaves ClickGrid alone when untouched, after Back to another look, or on cancel", function()
		local ns, cg, ob = LoadWithClickGrid()
		As("WARRIOR")
		local pending = ob.Pending
		pending:SelectPreset("healer")
		assert.is_nil(pending:Style().clickgrid)

		pending:SetExtraChoice("groupHeals", "bar")
		assert.is_not_nil(pending:Style().clickgrid)
		pending:SelectPreset("default")
		assert.is_nil(pending:Style().clickgrid, "a look that no longer offers it writes nothing")

		ns.Onboarding:Open()
		ob.Pending:SelectPreset("healer")
		ob.Pending:SetExtraChoice("groupHeals", "bar")
		ns.Onboarding:Close()
		assert.is_false(cg.Config.styles.member:Resolved().auraBar.enabled)
		assert.same({ preset = "heals", placement = "outside", side = "top" }, cg.BuffPresets.Current())
	end)
end)
