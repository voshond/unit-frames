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

	it("composes member and pet frames with a gap and reuses owner bindings", function()
		local width, height = CG.layout.cellWidth, CG.layout.cellHeight
		CG.Config:SetStyle("pet", "display", "inline")
		local pet, count = Cell().Pet, #CG.frames
		assert.is_not_nil(pet)
		assert.equals("pet", CG:GetGridButton(pet).kind)
		assert.equals(width + CG.metrics.pet.width + CG.metrics.pet.gap, CG.layout.cellWidth)
		assert.equals(height, CG.layout.cellHeight)
		assert.same({ "TOPLEFT", Cell(), "TOPLEFT", width + CG.metrics.pet.gap, 0 }, pet:GetAnchor("TOPLEFT"))
		assert.equals(Cell().Member.uf.layout.height, pet.uf.layout.height)
		assert.equals(1, pet:GetScale())
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

	it("stretches all pet columns to member height without scaling when the member shrinks", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("pet", "power.enabled", true)
		CG.Config:SetStyle("pet", "health.height", 90)
		CG.Config:SetStyle("pet", "health.columnWidth", 12)
		CG.Config:SetStyle("member", "health.height", 14)
		local pet = Cell().Pet
		assert.equals(14, pet.uf.layout.height)
		assert.equals(14, pet.uf:GetRow("health"):GetBar().knownHeight)
		assert.equals(14, pet.uf:GetRow("power"):GetBar().knownHeight)
		assert.equals(12, pet.uf:GetRow("health"):GetBar().knownWidth)
		assert.equals(1, pet:GetScale())
		assert.equals(14, CG.metrics.pet.height)
	end)

	it("lays out either side and member targets with a configurable gap without rebinding units", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("target", "shown", true)
		local count = #CG.frames
		UF.Perf.counters = {}
		CG.Config:SetStyle("pet", "gap", 7)
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.clickgridBindingsCompile)
		local member, pet, target = Cell().Member, Cell().Pet, Cell().Target
		assert.equals(157, select(4, pet:GetPoint()))
		assert.equals(157 + CG.metrics.pet.width + CG.panelConfig.targetGap, select(4, target:GetPoint()))
		CG.Config:SetStyle("pet", "side", "LEFT")
		assert.equals(0, select(4, pet:GetPoint()))
		assert.equals(CG.metrics.pet.width + 7, select(4, member:GetPoint()))
		assert.equals(count, #CG.frames)
		CG.Config:SetStyle("pet", "gap", 0)
		assert.equals(CG.metrics.pet.width, select(4, member:GetPoint()))
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

	it("previews separate member and pet frames with matching live geometry and releases pets", function()
		CG.Config:SetStyle("pet", "display", "inline")
		local preview = wb.handle
		assert.is_true(preview.cells[1].pet.uf:GetFrame():IsShown())
		assert.is_false(preview.cells[2].pet.uf:GetFrame():IsShown())
		local first = preview.cells[1].pet.uf
		assert.equals(CG.layout.cellWidth, preview.layout.cellWidth)
		assert.equals(CG.metrics.member.height, first.layout.height)
		assert.equals(1, first:GetFrame():GetScale())
		assert.equals(preview.layout.petX, select(4, first:GetFrame():GetPoint()))
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

	it("keeps rotated left text anchored identically on runtime and sample pet bars", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("pet", "health.left", {
			enabled = true, format = "name", justifyH = "LEFT", vertical = "middle", rotation = 90, size = 8,
		})
		local runtime = CG.headers.party:GetAttribute("child1").Pet.uf:GetRow("health"):GetText("left")
		local sample = wb.handle.cells[1].pet.uf:GetRow("health"):GetText("left")
		for _, rotation in ipairs({ 90, -90, 90 }) do
			CG.Config:SetStyle("pet", "health.left.rotation", rotation)
			runtime:SetText(Mock.Secret("Pet name"))
			local liveAnchor, sampleAnchor = runtime.frame:GetAnchor("CENTER"), sample.frame:GetAnchor("CENTER")
			assert.equals(liveAnchor[4], sampleAnchor[4])
			assert.equals(liveAnchor[5], sampleAnchor[5])
			assert.equals(runtime.hostHeight, sample.hostHeight)
			assert.equals((runtime.hostHeight - runtime.resolved.inset * 2) / 2, liveAnchor[4])
		end
	end)
end)
