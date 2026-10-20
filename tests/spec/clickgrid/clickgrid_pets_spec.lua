local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid pets", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	local function Cell() return CG.headers.party:GetAttribute("child1") end

	it("allocates no pet widgets until a mode is enabled", function()
		assert.equals("off", CG.Config.styles.pet:Resolved().display)
		assert.is_nil(CG.headers.pets)
		assert.is_nil(Cell().Pet)
		local count = #CG.frames
		CG.Config:SetStyle("pet", "health.columnWidth", 12)
		assert.equals(count, #CG.frames)
	end)

	it("reuses inline frames without changing cell geometry or owner binding", function()
		local width, height = CG.layout.cellWidth, CG.layout.cellHeight
		CG.Config:SetStyle("pet", "display", "inline")
		local pet, count = Cell().Pet, #CG.frames
		assert.is_not_nil(pet)
		assert.equals("pet", CG:GetGridButton(pet).kind)
		assert.equals(width, CG.layout.cellWidth)
		assert.equals(height, CG.layout.cellHeight)
		assert.equals("pet", pet:GetAttribute("unitsuffix"))
		assert.is_false(pet:GetAttribute("toggleForVehicle"))
		assert.is_true(pet.isChild)
		CG.Config:SetStyle("pet", "display", "off")
		assert.is_false(pet:IsEnabled())
		assert.is_true(pet:IsElementPaused("Health"))
		assert.is_false(pet.uf:GetPart("auras"):IsEnabled())
		CG.Config:SetStyle("pet", "display", "inline")
		assert.equals(pet, Cell().Pet)
		assert.equals(count, #CG.frames)
		assert.is_true(pet:IsEnabled())
		assert.is_false(pet:IsElementPaused("Health"))
	end)

	it("routes pet interactions explicitly and shows a distinct hover", function()
		CG.Config:SetStyle("pet", "display", "inline")
		local pet = Cell().Pet
		assert.is_false(pet.__state.mouseClickEnabled)
		assert.is_false(pet.__state.mouseMotionEnabled)
		CG.Config:SetStyle("pet", "interactive", true)
		assert.is_true(pet.__state.mouseClickEnabled)
		assert.is_true(pet.__state.mouseMotionEnabled)
		assert.equals("target", pet:GetAttribute("type-heal1"))
		local status = CG:GetGridButton(Cell().Member).status
		status:SetHovered(true)
		pet.__unit = nil
		pet:RunScript("OnEnter")
		assert.is_true(CG:GetGridButton(pet).hover:IsShown())
		assert.is_false(status.hover:IsShown())
		pet:RunScript("OnLeave")
		assert.is_false(CG:GetGridButton(pet).hover:IsShown())
	end)

	it("uses a pet-only native header and preserves independent styling", function()
		CG.Config:SetStyle("pet", "display", "group")
		local header = CG.headers.pets
		local cell = header:GetAttribute("child1")
		assert.is_not_nil(header:GetAttribute("child40"))
		assert.is_nil(cell.Member)
		assert.is_nil(cell.Target)
		assert.equals("pet", CG:GetGridButton(cell.Pet).kind)
		assert.is_nil(CG:GetGridButton(cell.Pet).status)
		CG.Config:SetStyle("pet", "health.columnWidth", 14)
		assert.equals(14, CG.metrics.pet.width)
		assert.equals(14, cell.Pet.uf.layout.width)
		assert.equals(150, Cell().Member.uf.layout.width)
		for _, position in ipairs({ "above", "below" }) do
			CG.Config:Set("titles.position", position)
			local layout = CG.layout
			local _, _, _, bottom = UF.Components.Backdrop.Padding(CG.Config:Resolved().border)
			local trailing = position == "below" and CG.Layout.TitleHeight(CG.Config:Resolved().titles) or 0
			assert.equals(layout.solo.height, layout.sections.pets.y + CG.metrics.pet.height + bottom + trailing)
		end
		CG.Config:Set("panel.roleOrder", "HEALER,TANK,DAMAGER,NONE")
		assert.is_nil(header:GetAttribute("groupBy"))
	end)

	it("defers pet configuration in combat and lets native ownership change without creation", function()
		CG.Config:SetStyle("pet", "display", "inline")
		local count = #CG.frames
		Mock.inCombat = true
		CG.headers.party:Assign(1, "party3")
		assert.equals("partypet3", Cell().Pet.__unit)
		CG.Config:SetStyle("pet", "display", "group")
		assert.is_nil(CG.headers.pets)
		assert.equals(count, #CG.frames)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_not_nil(CG.headers.pets)
		assert.is_false(Cell().Pet:IsEnabled())
	end)

	it("reclaims empty section space and repacks after combat", function()
		UnitExists = function(unit) return unit == "player" end
		CG.Config:SetStyle("pet", "display", "group")
		assert.is_true(CG.layout.sections.pets.parked)
		assert.is_false(CG:GetHeaderTitles(CG.headers.pets).label:IsShown())
		local height = CG.layout.solo.height
		UnitExists = function(unit) return unit == "player" or unit == "pet" end
		Mock.inCombat = true
		Mock.FireEvent("UNIT_PET", "player")
		assert.equals(height, CG.layout.solo.height)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_false(CG.layout.sections.pets.parked)
		assert.is_true(CG.layout.solo.height > height)
	end)

	it("moves the pet section below secure party growth without building widgets", function()
		Mock.inParty, Mock.groupSize = true, 2
		CG.Config:SetStyle("pet", "display", "group")
		local update = assert(loadstring(CG.panel:GetAttribute("_onstate-roster")))
		local environment = setmetatable({ self = CG.panel }, { __index = _G })
		setfenv(update, environment)
		local count = #CG.frames
		Mock.inCombat = true
		for _, members in ipairs({ 3, 5, 2 }) do
			environment.newstate = "party" .. members
			Mock.RunUntainted(update)
			local position = CG.headers.pets:GetAnchor("TOPLEFT")
			assert.equals(-CG.layout.petOffsets[environment.newstate], position[5])
			assert.equals(CG.layout.partySizes[members].height, CG.panel:GetHeight())
		end
		assert.equals(count, #CG.frames)
	end)

	it("does not recreate components or compile bindings for pet colour edits", function()
		CG.Config:SetStyle("pet", "display", "inline")
		UF.Perf.counters = {}
		CG.Config:SetStyle("pet", "hoverColor", { 1, 0, 1, 0.3 })
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.headerCreate)
		assert.is_nil(counters.clickgridBindingsCompile)
		assert.is_nil(counters.rootApply)
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.clickgridPanelLayout)
	end)

	it("keeps parked raid subgroups beyond the pet header's full secure capacity", function()
		Mock.inRaid, Mock.groupSize, Mock.raidSubgroups = true, 2, { 1, 1 }
		CG.Config:SetStyle("pet", "display", "group")
		local pets = CG.layout.sections.pets
		for group = 2, 8 do
			assert.is_true(CG.layout.sections["group" .. group].y >= pets.y + pets.capacity.height)
		end
	end)

	it("anchors flat-raid pets after the native header so combat growth cannot overlap", function()
		Mock.inRaid, Mock.groupSize, Mock.raidSubgroups = true, 2, { 1, 1 }
		CG.Config:Set("panel.mode", "flat")
		CG.Config:SetStyle("pet", "display", "group")
		local anchor = CG.headers.pets:GetAnchor("TOPLEFT")
		assert.equals(CG.headers.raid, anchor[2])
		assert.equals("BOTTOMLEFT", anchor[3])
		local update = assert(loadstring(CG.panel:GetAttribute("_onstate-roster")))
		setfenv(update, setmetatable({ self = CG.panel, newstate = "raid" }, { __index = _G }))
		Mock.inCombat = true
		Mock.RunUntainted(update)
		assert.same(anchor, CG.headers.pets:GetAnchor("TOPLEFT"))
	end)
end)

describe("ClickGrid pets #workbench", function()
	local UF, CG, wb
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.pet") end)

	it("previews mixed owners without empty slots and releases pets", function()
		CG.Config:SetStyle("pet", "display", "inline")
		local preview = wb.handle
		assert.is_true(preview.cells[1].pet.uf:GetFrame():IsShown())
		assert.is_false(preview.cells[2].pet.uf:GetFrame():IsShown())
		local first = preview.cells[1].pet.uf
		UF.Perf.counters = {}
		preview:ShowData({ source = "animated", count = 5 })
		preview:Tick(0.2)
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.rootApply)
		assert.is_nil(counters.componentCreate)
		preview:Release()
		assert.is_true(first.released)
	end)

	it("switches between packed pet samples and inline pets without retaining feeds", function()
		CG.Config:SetStyle("pet", "display", "group")
		local preview = wb.handle
		assert.equals(2, #preview.petCells)
		local grouped = preview.petCells[1]
		assert.is_true(grouped.pet.uf:GetFrame():IsShown())
		CG.Config:SetStyle("pet", "display", "inline")
		assert.is_false(grouped.frame:IsShown())
		assert.is_false(grouped.pet.uf:GetPart("auras"):IsEnabled())
		CG.Config:SetStyle("pet", "display", "off")
		assert.is_false(preview.cells[1].pet.uf:GetFrame():IsShown())
	end)

	it("uses the native pet token when a live owner is replaced by a vehicle", function()
		Mock.inParty, Mock.groupSize = true, 2
		CG.Config:SetStyle("pet", "display", "inline")
		CG.headers.party:Assign(1, "party1")
		local source = CG.headers.party:GetAttribute("child1")
		source.Member.__unit = "vehicle"
		UnitExists = function(unit) return unit == "vehicle" or unit == "partypet1" end
		wb.handle:ShowData({ source = "live" })
		assert.equals("partypet1", wb.handle.cells[1].petUnit)
		assert.is_true(wb.handle.cells[1].pet.uf:GetFrame():IsShown())
		assert.is_nil(CG.PetUnit("vehicle"))
	end)
end)
