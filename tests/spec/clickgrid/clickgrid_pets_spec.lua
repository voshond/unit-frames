local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Pets start inline, interactive and inside the member width; these specs
-- begin from separately sized, off pets.
local function SeparatePets() return { pet = { display = "off", interactive = false, includeInWidth = false, gap = 2 } } end

describe("ClickGrid pet defaults", function()
	it("start inline, interactive, one pixel away and inside the member width", function()
		local _, CG = Helpers.LoadClickGrid()
		local pet = CG.Config.styles.pet:Resolved()
		assert.equals("inline", pet.display)
		assert.is_true(pet.interactive)
		assert.is_true(pet.includeInWidth)
		assert.equals(1, pet.gap)
		assert.equals(CG.metrics.member.width, CG.headers.party:GetAttribute("child1").Member:GetWidth())
	end)
end)

describe("ClickGrid pets", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid(false, SeparatePets()) end)

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
		assert.equals(CG.layout.cellWidth, Cell().Member:GetWidth())
		assert.same({ "TOPRIGHT", Cell().Member, "TOPRIGHT", 0, 0 }, pet:GetAnchor("TOPRIGHT"))
		assert.equals(Cell().Member:GetFrameLevel() + 1, pet:GetFrameLevel())
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

	it("places pets inside a bordered member's border and padding", function()
		CG.Config:SetStyle("member", "border.enabled", true)
		CG.Config:SetStyle("member", "border.padding", 3)
		CG.Config:SetStyle("pet", "display", "inline")
		local member, pet = Cell().Member, Cell().Pet
		pet:Show()
		local reserve = CG.metrics.pet.width + CG.metrics.pet.gap
		assert.equals(CG.metrics.member.width + reserve, member:GetWidth())
		assert.same({ "TOPRIGHT", member, "TOPRIGHT", -3, -3 }, pet:GetAnchor("TOPRIGHT"))
		assert.equals(member.uf.layout.height - 6, pet.uf.layout.height)
		assert.equals(member.uf.layout.height - 6, CG.metrics.pet.height)
		local health = member.uf:GetRow("health")
		assert.equals(CG.metrics.member.width - 6, health:GetBar():GetKnownSize())
		assert.equals(-3 - reserve, health:GetFrame():GetAnchor("TOPRIGHT")[4])
		pet:Hide()
		assert.equals(CG.metrics.member.width - 6 + reserve, health:GetBar():GetKnownSize())
		assert.equals(-3, health:GetFrame():GetAnchor("TOPRIGHT")[4])
		assert.equals(CG.metrics.member.width + reserve, member:GetWidth())
		CG.Config:SetStyle("pet", "side", "LEFT")
		pet:Show()
		assert.same({ "TOPLEFT", member, "TOPLEFT", 3, -3 }, pet:GetAnchor("TOPLEFT"))
		assert.equals(3 + reserve, health:GetFrame():GetAnchor("TOPLEFT")[4])
	end)

	it("can take the pet's space from the configured member width without moving targets", function()
		CG.Config:SetStyle("target", "shown", true)
		local cellWidth, targetX = CG.layout.cellWidth, CG.layout.targetX
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("pet", "includeInWidth", true)
		local member, pet = Cell().Member, Cell().Pet
		local reserve = CG.metrics.pet.width + CG.metrics.pet.gap
		local health = member.uf:GetRow("health")
		assert.equals(cellWidth, CG.layout.cellWidth)
		assert.equals(targetX, CG.layout.targetX)
		assert.equals(targetX, select(4, Cell().Target:GetPoint()))
		assert.equals(CG.metrics.member.width, member:GetWidth())
		assert.same({ "TOPRIGHT", member, "TOPRIGHT", 0, 0 }, pet:GetAnchor("TOPRIGHT"))
		Mock.inCombat = true
		Mock.RunUntainted(pet.Show, pet)
		assert.equals(CG.metrics.member.width - reserve, health:GetBar():GetKnownSize())
		Mock.RunUntainted(pet.Hide, pet)
		assert.equals(CG.metrics.member.width, health:GetBar():GetKnownSize())
		assert.equals(CG.metrics.member.width, member:GetWidth())
		Mock.inCombat = false
		CG.Config:SetStyle("pet", "includeInWidth", false)
		assert.equals(cellWidth + reserve, CG.layout.cellWidth)
		assert.equals(CG.metrics.member.width + reserve, member:GetWidth())
	end)

	it("stretches all pet columns to member height without scaling when the member shrinks", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("pet", "power.enabled", true)
		CG.Config:SetStyle("pet", "health.height", 90)
		CG.Config:SetStyle("pet", "health.columnWidth", 12)
		CG.Config:SetStyle("member", "power.enabled", false)
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
		Cell().Pet:Show()
		local count = #CG.frames
		UF.Perf.counters = {}
		CG.Config:SetStyle("pet", "gap", 7)
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.clickgridBindingsCompile)
		local member, pet, target = Cell().Member, Cell().Pet, Cell().Target
		local health = member.uf:GetRow("health"):GetFrame()
		assert.equals(CG.metrics.member.width + 7 + CG.metrics.pet.width, member:GetWidth())
		assert.same({ "TOPRIGHT", member, "TOPRIGHT", 0, 0 }, pet:GetAnchor("TOPRIGHT"))
		assert.equals(CG.metrics.member.width + 7 + CG.metrics.pet.width + CG.panelConfig.targetGap, select(4, target:GetPoint()))
		CG.Config:SetStyle("pet", "side", "LEFT")
		assert.same({ "TOPLEFT", member, "TOPLEFT", 0, 0 }, pet:GetAnchor("TOPLEFT"))
		assert.equals(0, select(4, member:GetPoint()))
		assert.equals(CG.metrics.pet.width + 7, health:GetAnchor("TOPLEFT")[4])
		assert.equals(count, #CG.frames)
		CG.Config:SetStyle("pet", "gap", 0)
		assert.equals(CG.metrics.pet.width, health:GetAnchor("TOPLEFT")[4])
	end)

	it("fills the member area when a pet disappears in combat without moving targets or rebuilding", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("target", "shown", true)
		CG.headers.party:Assign(1, "player")
		local cell = Cell()
		local target = cell.Target:GetAnchor("TOPLEFT")
		local count = #CG.frames
		local bar = cell.Member.uf:GetRow("health"):GetBar()
		Mock.inCombat = true
		UF.Perf.counters = {}
		for _, present in ipairs({ true, false, true, false }) do
			UnitExists = function(unit) return unit == "player" or present and unit == "pet" end
			UnitIsVisible = function() return false end
			Mock.RunUntainted(Mock.TickUnitVisibility, cell.Pet)
			local reserve = CG.metrics.pet.width + CG.metrics.pet.gap
			local width = CG.metrics.member.width + (present and 0 or reserve)
			assert.equals(present, cell.Pet:IsShown())
			assert.equals(CG.metrics.member.width + reserve, cell.Member:GetWidth())
			assert.equals(width, bar:GetKnownSize())
			assert.equals(width, bar.bar:GetWidth())
			assert.equals(width, cell.Member.uf:GetRow("health").textWidth)
			for _, segment in ipairs(bar.segments) do assert.equals(width, segment.bar:GetWidth()) end
			assert.same(target, cell.Target:GetAnchor("TOPLEFT"))
		end
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.clickgridPanelLayout)
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.rootApply)
		assert.equals(count, #CG.frames)
	end)

	it("removes the left-hand gap for absent pets and restores the configured split", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("pet", "side", "LEFT")
		local cell = Cell()
		local health = cell.Member.uf:GetRow("health"):GetFrame()
		cell.Pet:Hide()
		assert.equals(0, select(4, cell.Member:GetPoint()))
		assert.equals(0, health:GetAnchor("TOPLEFT")[4])
		assert.equals(CG.layout.cellWidth, cell.Member:GetWidth())
		cell.Pet:Show()
		assert.equals(CG.metrics.pet.width + CG.metrics.pet.gap, health:GetAnchor("TOPLEFT")[4])
		assert.equals(CG.layout.cellWidth, cell.Member:GetWidth())
		CG.Config:SetStyle("pet", "display", "off")
		assert.equals(CG.metrics.member.width, cell.Member:GetWidth())
		assert.equals(0, health:GetAnchor("TOPLEFT")[4])
		assert.is_nil(cell.Member.uf.reserve)
	end)

	it("keeps secondary member columns at their configured width when reclaiming pet space", function()
		CG.Config:SetStyle("member", "barLayout", "columns")
		CG.Config:SetStyle("member", "power.enabled", true)
		CG.Config:SetStyle("member", "health.columnWidth", 20)
		CG.Config:SetStyle("member", "power.columnWidth", 5)
		CG.Config:SetStyle("pet", "display", "inline")
		local cell = Cell()
		cell.Pet:Hide()
		local health, power = cell.Member.uf:GetRow("health"), cell.Member.uf:GetRow("power")
		assert.equals(20 + CG.metrics.pet.width + CG.metrics.pet.gap, health:GetBar():GetKnownSize())
		assert.equals(5, power:GetBar():GetKnownSize())
		assert.equals("TOPRIGHT", power:GetFrame():GetAnchor("TOPLEFT")[3])
		cell.Pet:Show()
		assert.equals(20, health:GetBar():GetKnownSize())
		assert.equals(5, power:GetBar():GetKnownSize())
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
		local member = Cell().Member
		member.uf:SetHovered(true)
		pet.__unit = nil
		pet:RunScript("OnEnter")
		assert.is_true(pet.uf.hover:IsShown())
		assert.same({ 0.2, 0.8, 1, 0.35 }, pet.uf.hover.__state.colorTexture)
		assert.is_false(member.uf.hover:IsShown())
		pet:RunScript("OnLeave")
		assert.is_false(pet.uf.hover:IsShown())
		pet:RunScript("OnEnter")
		CG.Config:SetStyle("pet", "interactive", false)
		assert.is_false(pet.uf.hover:IsShown(), "pets without interaction drop the highlight")
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
		assert.equals(120, Cell().Member.uf.layout.width)
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
		CG.Config:SetStyle("pet", "hover.color", { 1, 0, 1, 0.3 })
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.headerCreate)
		assert.is_nil(counters.clickgridBindingsCompile)
		assert.is_nil(counters.clickgridPanelLayout)
		assert.same({ 1, 0, 1, 0.3 }, Cell().Pet.uf.hover.__state.colorTexture)
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
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true, SeparatePets()); wb:Open("clickgrid.pet") end)

	it("previews separate member and pet frames with matching live geometry and releases pets", function()
		CG.Config:SetStyle("pet", "display", "inline")
		local preview = wb.handle
		assert.is_true(preview.cells[1].pet.uf:GetFrame():IsShown())
		assert.is_false(preview.cells[2].pet.uf:GetFrame():IsShown())
		assert.equals(preview.layout.cellWidth, preview.cells[1].member:GetFrame():GetWidth())
		assert.equals(preview.layout.cellWidth, preview.cells[2].member:GetFrame():GetWidth())
		assert.equals(CG.metrics.member.width, preview.cells[1].member:GetRow("health").textWidth)
		assert.equals(preview.layout.cellWidth, preview.cells[2].member:GetRow("health").textWidth)
		local first = preview.cells[1].pet.uf
		assert.equals(CG.layout.cellWidth, preview.layout.cellWidth)
		assert.equals(CG.metrics.member.height, first.layout.height)
		assert.equals(1, first:GetFrame():GetScale())
		assert.same({ "TOPRIGHT", preview.cells[1].member:GetFrame(), "TOPRIGHT", 0, 0 }, first:GetFrame():GetAnchor("TOPRIGHT"))
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

	it("expands a dead live member with no pet and restores the split on pet replacement", function()
		CG.Config:SetStyle("pet", "display", "inline")
		CG.Config:SetStyle("pet", "side", "LEFT")
		CG.headers.party:Assign(1, "player")
		local hasPet = false
		UnitExists = function(unit) return unit == "player" or hasPet and unit == "pet" end
		UnitIsDeadOrGhost = function(unit) return unit == "player" end
		local preview = wb.handle
		preview:ShowData({ source = "live", count = 5 })
		local cell = preview.cells[1]
		local health = cell.member:GetRow("health")
		assert.is_false(cell.pet.uf:GetFrame():IsShown())
		assert.equals(preview.layout.cellWidth, cell.member:GetFrame():GetWidth())
		assert.equals(0, health:GetFrame():GetAnchor("TOPLEFT")[4])
		assert.equals(preview.layout.cellWidth, health.textWidth)
		hasPet = true
		preview:Tick(0.2)
		assert.is_true(cell.pet.uf:GetFrame():IsShown())
		assert.equals(preview.layout.cellWidth, cell.member:GetFrame():GetWidth())
		assert.equals(CG.metrics.pet.width + CG.metrics.pet.gap, health:GetFrame():GetAnchor("TOPLEFT")[4])
		assert.equals(CG.metrics.member.width, health.textWidth)
		hasPet = false
		preview:Tick(0.2)
		assert.is_false(cell.pet.uf:GetFrame():IsShown())
		assert.equals(preview.layout.cellWidth, health.textWidth)
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
