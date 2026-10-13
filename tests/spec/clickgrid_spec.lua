local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid companion", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	it("keeps standalone units separate and prepares party and all raid subgroup capacity", function()
		assert.equals(CG, UF.ClickGrid)
		for _, key in ipairs(UF.Units.order) do
			assert.is_not_nil(UF.Units.definitions[key])
			assert.is_false(key == "member" or key == "clickgrid")
		end
		assert.equals(9, #UF.oUF.headers)
		assert.equals(90, #CG.frames)
		for key, header in pairs(CG.headers) do
			assert.is_not_nil(header:GetAttribute("child5"), key)
			assert.equals(1, header:GetAttribute("startingIndex"))
		end
		assert.is_true(CG.headers.party:GetAttribute("showParty"))
		assert.is_false(CG.headers.party:GetAttribute("showRaid"))
		assert.equals("1", CG.headers.group1:GetAttribute("groupFilter"))
		assert.equals("8", CG.headers.group8:GetAttribute("groupFilter"))
		assert.equals(UF.Units.STYLE, UF.oUF:GetActiveStyle())
	end)

	it("keeps addon state off the secure unit buttons and headers", function()
		local function NoAddonFields(frame, name)
			for key in pairs(frame) do
				local addonKey = type(key) == "string" and (key:match("^ufcg") or key == "ufReady")
				assert.is_true(not addonKey, name .. " carries " .. tostring(key))
			end
		end
		for _, frame in ipairs(CG.frames) do NoAddonFields(frame, frame:GetName()) end
		for key, header in pairs(CG.headers) do NoAddonFields(header, key) end
		for unit, frame in pairs(UF.Units.frames) do NoAddonFields(frame, unit) end
		local cell = CG.headers.party:GetAttribute("child1")
		assert.equals("member", CG:GetGridButton(cell.Member).kind)
		assert.is_not_nil(CG:GetGridButton(cell.Member).status)
		assert.equals("target", CG:GetGridButton(cell.Target).kind)
		assert.is_nil(CG:GetGridButton(cell.Target).slots, "targets have no member extras")
		assert.is_nil(CG:GetGridButton(cell), "the structural cell is not a unit button")
		assert.is_not_nil(CG:GetHeaderTitles(CG.headers.party).label)
	end)

	it("runs the embedded oUF header initializer on the structural cell and both unit children", function()
		local file = assert(io.open("UnitFrames/Libs/oUF/ouf.lua"))
		local source = file:read("*a"); file:close()
		local body = assert(source:match("local initialConfigFunction = %[%[(.-)%]%]"))
		local header = CG.headers.party
		-- oUF must guess raid while precreating units, before this header is
		-- switched to party. This exercises the real snippet, not its stand-in.
		header:SetAttribute("showRaid", true)
		local cell = header:GetAttribute("child1")
		local styled
		function cell:GetChildList(frames) frames[#frames + 1] = self.Member; frames[#frames + 1] = self.Target end
		for _, frame in ipairs({ cell, cell.Member, cell.Target }) do
			-- Restricted snippets receive self as a global, not a vararg.
			function frame:Run(code)
				local chunk = assert(loadstring(code))
				setfenv(chunk, setmetatable({ self = self }, { __index = _G }))
				chunk()
			end
		end
		function header:CallMethod(_, name) styled = name end
		function header:GetFrameRef() return nil end
		local restrictedTable = { new = function() return {} end, insert = table.insert }
		local initialize = assert(loadstring(body))
		setfenv(initialize, setmetatable({ self = cell, table = restrictedTable }, { __index = _G }))
		assert.has_no_error(initialize)
		assert.equals(cell:GetName(), styled)
		assert.equals("raid", cell.Member:GetAttribute("oUF-guessUnit"))
		assert.equals("raidtarget", cell.Target:GetAttribute("oUF-guessUnit"))
		assert.is_true(cell.Member:GetAttribute("useparent-unit"))
		assert.is_true(cell.Member:GetAttribute("toggleForVehicle"))
		assert.is_false(cell.Target:GetAttribute("toggleForVehicle"))
		assert.equals(CG.metrics.member.height, cell:GetHeight())
	end)

	it("shrinks party bounds and selects precomputed roster sizes during combat", function()
		Mock.inParty, Mock.groupSize = true, 2
		CG:Refresh()
		local cfg, layout = CG.Config:Resolved(), CG.layout
		local function Height(count)
			return count * layout.cellHeight + (count - 1) * cfg.panel.spacingY
				+ CG.Layout.TitleHeight(cfg.titles) + 2 * cfg.panel.padding
		end
		assert.equals(Height(2), CG.panel:GetHeight())
		assert.equals("[group:raid] raid; [@party4,exists] party5; [@party3,exists] party4; [@party2,exists] party3; [group:party] party2; solo",
			CG.panel.__state.drivers.roster)
		assert.equals(5, CG.headers.party:GetAttribute("unitsPerColumn"))
		assert.is_not_nil(CG.headers.party:GetAttribute("child5"))
		local resize = assert(loadstring(CG.panel:GetAttribute("_onstate-roster")))
		local env = setmetatable({ self = CG.panel }, { __index = _G })
		setfenv(resize, env)
		local frames = #CG.frames
		Mock.inCombat = true
		for _, count in ipairs({ 3, 5, 4, 2 }) do
			env.newstate = "party" .. count
			-- Secure state snippets run untainted: they may resize protected frames in combat.
			assert.has_no_error(function() Mock.RunUntainted(resize) end)
			assert.equals(Height(count), CG.panel:GetHeight())
			assert.equals(layout.party.width, CG.panel:GetWidth())
		end
		env.newstate = "raid"
		Mock.RunUntainted(resize)
		assert.equals(layout.raid.height, CG.panel:GetHeight())
		env.newstate = "solo"
		Mock.RunUntainted(resize)
		assert.equals(Height(1), CG.panel:GetHeight())
		assert.equals(frames, #CG.frames)
		Mock.inCombat = false
		Mock.groupSize = 4
		CG:Refresh()
		assert.equals(Height(4), CG.panel:GetHeight())
	end)

	it("creates alternate layouts outside combat and preserves all 40 primary slots", function()
		assert.is_true(CG.Config:Set("panel.mode", "flat"))
		local header = CG.headers.raid
		assert.is_not_nil(header:GetAttribute("child40"))
		assert.equals("custom hide", CG.headers.group1.visibility)
		assert.equals("custom [group:raid] show; hide", header.visibility)
		assert.is_true(CG.Config:Set("panel.columns", 1))
		assert.equals(10, CG.Config:Resolved().panel.rows)
		assert.equals(10, header:GetAttribute("unitsPerColumn"))
		assert.equals(4, header:GetAttribute("maxColumns"))
		assert.is_true(CG.Config:Set("panel.rows", 4))
		assert.equals(1, CG.Config:Resolved().panel.columns)
		assert.equals(10, header:GetAttribute("maxColumns"))
		assert.is_true(CG.Config:Set("panel.rows", 1))
		assert.equals(40, header:GetAttribute("maxColumns"))
		assert.is_false(CG.Config:Set("panel.rows", 0))
	end)

	it("preserves independent five-by-five preferences and forty-member secure capacity in both flows", function()
		CG.Config:Set("panel.mode", "flat")
		CG.Config:Set("panel.columns", 5)
		CG.Config:Set("panel.rows", 5)
		local header = CG.headers.raid
		assert.equals(5, CG.Config:Resolved().panel.columns)
		assert.equals(5, CG.Config:Resolved().panel.rows)
		assert.equals(5, header:GetAttribute("unitsPerColumn"))
		assert.equals(8, header:GetAttribute("maxColumns"))
		assert.is_not_nil(header:GetAttribute("child40"))
		CG.Config:Set("panel.flow", "across")
		assert.equals(5, CG.Config:Resolved().panel.columns)
		assert.equals(5, CG.Config:Resolved().panel.rows)
		assert.equals(5, header:GetAttribute("unitsPerColumn"))
		assert.equals(8, header:GetAttribute("maxColumns"))
		assert.equals(8, CG.layout.sections.raid.grid.rows)
	end)

	it("compiles row-first layout spacing with positive native column spacing", function()
		local cfg = CG.Config:Resolved().panel
		cfg.mode, cfg.flow, cfg.columns, cfg.rows = "flat", "across", 5, 8
		local layout = CG.Layout.Compute(cfg, CG.metrics.member, CG.metrics.target)
		local attr = CG.Layout.Attributes(layout.sections.raid.grid, cfg)
		assert.equals("LEFT", attr.point)
		assert.equals("TOP", attr.columnAnchorPoint)
		assert.equals(cfg.spacingY, attr.columnSpacing)
		local x, y = CG.Layout.Cell(6, 5, 8, cfg.flow, layout.cellWidth, layout.cellHeight, cfg.spacingX, cfg.spacingY)
		assert.equals(0, x)
		assert.equals(layout.cellHeight + cfg.spacingY, y)
	end)

	it("reserves title size and gap without changing grid spacing", function()
		local cfg = CG.Config:Resolved()
		local original = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals("Group 1", CG:GetHeaderTitles(CG.headers.group1).label:GetText())
		CG.Config:Set("titles.size", 20)
		CG.Config:Set("titles.gap", 9)
		cfg = CG.Config:Resolved()
		local larger = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals(original.party.height + 13, larger.party.height)
		assert.same(original.sections.party.grid, larger.sections.party.grid)
		CG.Config:Set("titles.position", "below")
		cfg = CG.Config:Resolved()
		local below = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals(larger.raid.height, below.raid.height)
		assert.equals(cfg.panel.padding, below.sections.group1.y)
		CG.Config:Set("titles.enabled", false)
		cfg = CG.Config:Resolved()
		local hidden = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals(below.party.height - 31, hidden.party.height)
		assert.is_false(CG:GetHeaderTitles(CG.headers.party).label:IsShown())
		CG.Config:Set("titles.enabled", true)
		assert.is_true(CG:GetHeaderTitles(CG.headers.party).label:IsShown())
	end)

	it("anchors titles to native headers and defers changes during combat", function()
		local header = CG.headers.party
		local label = CG:GetHeaderTitles(header).label
		CG.Config:Set("titles.offsetX", 7)
		CG.Config:Set("titles.offsetY", -3)
		assert.same({ "BOTTOMLEFT", header, "TOPLEFT", 7, 14 }, { label:GetPoint() })
		CG.Config:Set("titles.position", "below")
		assert.same({ "TOPLEFT", header, "BOTTOMLEFT", 7, -20 }, { label:GetPoint() })
		Mock.inCombat = true
		CG.Config:Set("titles.party", "My party")
		CG.Config:Set("titles.size", 18)
		assert.equals("Party", label:GetText())
		assert.equals(11, label.__state.font[2])
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals("My party", label:GetText())
		assert.equals(18, label.__state.font[2])
	end)

	it("uses independent member defaults and inherited styles", function()
		assert.equals(150, CG.definitions.member.width)
		assert.equals(170, UF.Units.definitions.pet.width)
		local member = CG.headers.party:GetAttribute("child1").Member
		assert.is_nil(member.UF_Experience)
		assert.equals(member.uf:GetRow("health"):GetBar():GetStatusBar(), member.Health)
		assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, member.Health.damageAbsorbClampMode)
		assert.equals(120, member.uf:GetPart("auras").resolved.buffs.maxDuration)
		assert.equals("unitDebuff", member.uf:GetPart("auras").resolved.debuffs.sort)
		assert.is_true(member.uf:GetRow("health"):GetText("left").deferInCombat)
		local auraButton = member.uf:GetPart("auras").containers.buffs.__state.groups.buffs.frames[1]
		local clickThrough = false
		for _, call in ipairs(auraButton.__calls) do
			if call[1] == "SetMouseClickEnabled" and call[2] == false then clickThrough = true end
		end
		assert.is_true(clickThrough)
	end)

	it("queues geometry and bindings without touching secure frames during combat", function()
		local member = CG.headers.party:GetAttribute("child1").Member
		local originalWidth = member:GetWidth()
		local oldSet = member.SetAttribute
		member.SetAttribute = function(self, ...)
			assert.is_false(Mock.inCombat)
			return oldSet(self, ...)
		end
		Mock.inCombat = true
		assert.is_true(CG.Config:SetStyle("member", "width", 200))
		assert.is_true(CG.Config:Set("panel.targets", true))
		assert.is_true(CG.Config:SetBinding(1, "shift", "friendly", "action", "spell"))
		assert.is_true(CG.Config:SetBinding(1, "shift", "friendly", "spell", "2061"))
		assert.is_true(CG.pending)
		assert.equals(originalWidth, member:GetWidth())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_nil(CG.pending)
		assert.equals(200, member:GetWidth())
		assert.equals(2061, member:GetAttribute("shift-spell-heal1"))
		assert.is_true(CG.headers.party:GetAttribute("child1").Target.__state.unitWatched)
	end)

	it("stops watching and updating hidden targets, then restores their elements", function()
		local target = CG.headers.party:GetAttribute("child1").Target
		assert.is_false(target:IsEnabled(), "disabled by default even though oUF prepares the button")
		CG.Config:Set("panel.targets", true)
		assert.is_true(target:IsEnabled())
		assert.is_false(target:IsElementPaused("Health"))
		CG.Config:SetStyle("target", "auras.enabled", true)
		CG.Config:Set("panel.targets", false)
		assert.is_false(target:IsEnabled())
		assert.is_false(target:IsShown())
		assert.is_true(target:IsElementPaused("Health"))
		assert.is_true(target:IsElementPaused("RaidTargetIndicator"))
		assert.is_false(target.uf:GetPart("auras"):IsEnabled())
		target.calls = {}
		CG:Refresh()
		for _, call in ipairs(target.calls) do
			assert.is_false(call:match("^UpdateAllElements") ~= nil, "hidden targets do no forced refresh")
		end
		CG.Config:Set("panel.targets", true)
		assert.is_true(target:IsEnabled())
		assert.is_false(target:IsElementPaused("Health"))
		assert.is_true(target.uf:GetPart("auras"):IsEnabled())
		assert.is_nil(target.__state.drivers["state-visibility"])
	end)

	it("keeps disabled targets hidden when visibility drivers run before unit watches", function()
		local target = CG.headers.party:GetAttribute("child1").Target
		target.__unit = "party1target"
		Mock.TickUnitVisibility(target)
		assert.is_false(target:IsShown(), "unit watch must not override the hide driver")
		CG.Config:Set("panel.targets", true)
		Mock.TickUnitVisibility(target)
		assert.is_true(target:IsShown(), "the native watcher shows an existing unit")
		CG.Config:Set("panel.targets", false)
		Mock.TickUnitVisibility(target)
		assert.is_false(target:IsShown(), "hiding again also unregisters the watcher")
	end)

	it("lets a header assign a different member and its target in combat without building widgets", function()
		local header = CG.headers.group1
		local count = #CG.frames
		Mock.inCombat = true
		header:Assign(1, "raid22")
		local cell = header:GetAttribute("child1")
		assert.equals("raid22", cell.Member.__unit)
		assert.equals("raid22target", cell.Target.__unit)
		assert.has_no_error(function()
			UF.oUF.elements.UF_Auras.update(cell.Member)
			UF.oUF.elements.UFCG_Slots.update(cell.Member)
		end)
		assert.equals("raid22", CG:GetGridButton(cell.Member).slots.container:GetUnit())
		assert.equals(count, #CG.frames)
		header:Assign(1, nil)
		assert.has_no_error(function() UF.oUF.elements.UF_Auras.update(cell.Member) end)
		Mock.inCombat = false
	end)

	it("registers status and private aura widgets with pre-created anchors", function()
		local member = CG.headers.party:GetAttribute("child1").Member
		assert.is_true(member:IsElementEnabled("GroupRoleIndicator"))
		assert.is_false(member:IsElementEnabled("ReadyCheckIndicator"))
		assert.is_true(member:IsElementEnabled("UF_ReadyCheck"))
		assert.is_true(member:IsElementEnabled("UFCG_DeathIndicator"))
		-- The base mock has no private aura API. Absence is a capability, not an error.
		assert.is_false(member:IsElementEnabled("PrivateAuras"))
		assert.equals(3, #CG:GetGridButton(member).status.PrivateAuras)
		assert.is_nil(member.ThreatIndicator)
		CG.Config:Set("indicators.threat", true)
		member.__unit = "raid1"
		local previous = UnitThreatSituation
		UnitThreatSituation = function() return Mock.Secret(3) end
		assert.has_no_error(function() member.ThreatIndicator.Override(member) end)
		UnitThreatSituation = previous
	end)

	it("clears name padding for an unassigned role and restores it on native role updates", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local role, name = frame.GroupRoleIndicator, frame.uf:GetRow("health"):GetText("left")
		Mock.assignedRole = nil
		role:PostUpdate()
		assert.equals(0, name.leadingSpace)
		assert.equals(name.resolved.inset + name.resolved.offsetX, select(4, name:GetFrame():GetPoint()))
		CG:RequestRefresh()
		assert.equals(0, name.leadingSpace)
		Mock.assignedRole = Enum.LFGRole.Healer
		role:PostUpdate()
		assert.equals(16, name.leadingSpace)
		assert.is_true(role:GetParent():IsShown())
		Mock.inCombat = true
		Mock.assignedRole = nil
		assert.has_no_error(function() role:PostUpdate() end)
		assert.equals(0, name.leadingSpace)
		Mock.assignedRole = Mock.Secret(Enum.LFGRole.Healer)
		assert.has_no_error(function() role:PostUpdate() end)
		assert.equals(16, name.leadingSpace)
		Mock.inCombat = false
	end)

	it("excludes the title band from the single panel backdrop", function()
		local cfg = CG.Config:Resolved()
		assert.same({ "TOPLEFT", CG.panel, "TOPLEFT", 0, -CG.Layout.TitleHeight(cfg.titles) }, { CG.background:GetPoint(1) })
		assert.same({ "BOTTOMRIGHT", CG.panel, "BOTTOMRIGHT", 0, 0 }, { CG.background:GetPoint(2) })
		CG.Config:Set("titles.position", "below")
		assert.equals(0, select(5, CG.background:GetPoint(1)))
		assert.equals(CG.Layout.TitleHeight(cfg.titles), select(5, CG.background:GetPoint(2)))
		CG.Config:Set("titles.enabled", false)
		assert.equals(0, select(5, CG.background:GetPoint(2)))
	end)

	it("raises role and status art above bars and reserves space before the name", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local role = frame.GroupRoleIndicator
		local name = frame.uf:GetRow("health"):GetText("left")
		local cfg = CG.Config:Resolved().indicators
		assert.is_true(role:GetParent():GetFrameLevel() > frame.uf:GetRow("health"):GetBar():GetTextParent():GetFrameLevel())
		assert.is_true(CG:GetGridButton(frame).status.ReadyCheckIndicator:GetParent():GetFrameLevel() > frame:GetFrameLevel())
		assert.equals(cfg.roleSize + cfg.roleGap, name.leadingSpace)
		assert.equals(name.resolved.inset + name.resolved.offsetX + name.leadingSpace, select(4, name:GetFrame():GetPoint(1)))
		local point, relative, relativePoint, x = role:GetParent():GetPoint()
		assert.equals("RIGHT", point)
		assert.equals(name:GetFrame(), relative)
		assert.equals("LEFT", relativePoint)
		assert.equals(-cfg.roleGap, x)
		CG.Config:Set("indicators.roleSize", 20)
		assert.equals(22, name.leadingSpace)
		CG:RequestRefresh()
		assert.equals(22, name.leadingSpace, "repeated application must not add space twice")
		CG.Config:Set("indicators.role", false)
		assert.equals(0, name.leadingSpace)
		assert.is_false(role:GetParent():IsShown())
		CG.Config:Set("indicators.role", true)
		assert.equals(22, name.leadingSpace)
	end)

	-- oUF shows or hides an icon, then calls its PostUpdate.
	local function Native(icon, shown)
		icon:SetShown(shown)
		icon:PostUpdate()
	end
	local function Anchor(host)
		local point, relative, relativePoint, x, y = host:GetPoint()
		return { point, relative, relativePoint, x, y }
	end

	it("keeps icons sharing an edge centred as a group and collapses absent icons", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local frame = CG.headers.party:GetAttribute("child1").Member
		local marker, leader, ready = frame.uf:GetPart("raidTarget"), frame.LeaderIndicator, CG:GetGridButton(frame).status.ReadyCheckIndicator
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(leader:GetParent()), "absent icons keep their own position")
		Native(leader, true)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(leader:GetParent()))
		-- Marker 12 + gap 2 + leader 14 = 28 wide, centred on the top edge.
		Native(marker:GetWidget(), true)
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(marker:GetFrame()))
		assert.same({ "CENTER", frame, "TOP", 7, 0 }, Anchor(leader:GetParent()))
		frame.uf:GetReadyCheck():Set("ready")
		assert.same({ "CENTER", frame, "TOP", -16, 0 }, Anchor(marker:GetFrame()))
		assert.same({ "CENTER", frame, "TOP", -1, 0 }, Anchor(leader:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 15, 0 }, Anchor(ready:GetParent()))
		Native(marker:GetWidget(), false)
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(leader:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
		-- The assistant shares the leader's slot.
		Native(leader, false)
		Native(frame.AssistantIndicator, true)
		assert.equals(leader:GetParent(), frame.AssistantIndicator:GetParent())
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(leader:GetParent()))
		CG:RequestRefresh()
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(ready:GetParent()), "repeated application is stable")
		assert.equals(16, frame.uf:GetRow("health"):GetText("left").leadingSpace, "the role stays before the name")
	end)

	it("orders, nudges and grows groups by anchor kind", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local frame = CG.headers.party:GetAttribute("child1").Member
		local leader, ready = frame.LeaderIndicator, CG:GetGridButton(frame).status.ReadyCheckIndicator
		Native(leader, true)
		frame.uf:GetReadyCheck():Set("ready")
		CG.Config:Set("indicators.readyOrder", 1)
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(leader:GetParent()))
		CG.Config:Set("indicators.leaderOffsetX", 3)
		CG.Config:Set("indicators.leaderOffsetY", -1)
		assert.same({ "CENTER", frame, "TOP", 11, -1 }, Anchor(leader:GetParent()))
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(ready:GetParent()), "an offset moves only its own icon")
		CG.Config:Set("indicators.leaderOffsetX", 0)
		CG.Config:Set("indicators.leaderOffsetY", 0)
		-- Sides run top to bottom, centred.
		CG.Config:Set("indicators.leaderPosition", "RIGHT")
		CG.Config:Set("indicators.readyPosition", "RIGHT")
		assert.same({ "CENTER", frame, "RIGHT", 0, 8 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "RIGHT", 0, -8 }, Anchor(leader:GetParent()))
		-- Corners keep the outer icon on the corner and grow inward.
		CG.Config:Set("indicators.leaderPosition", "TOPLEFT")
		CG.Config:Set("indicators.readyPosition", "TOPLEFT")
		assert.same({ "CENTER", frame, "TOPLEFT", 0, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "TOPLEFT", 16, 0 }, Anchor(leader:GetParent()))
		CG.Config:Set("indicators.leaderPosition", "BOTTOMRIGHT")
		CG.Config:Set("indicators.readyPosition", "BOTTOMRIGHT")
		assert.same({ "CENTER", frame, "BOTTOMRIGHT", -16, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "BOTTOMRIGHT", 0, 0 }, Anchor(leader:GetParent()))
		CG.Config:Set("indicators.readyPosition", "CENTER")
		assert.same({ "CENTER", frame, "CENTER", 0, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "BOTTOMRIGHT", 0, 0 }, Anchor(leader:GetParent()))
	end)

	it("keeps a slot for an opaque shown state and an opaque role", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local frame = CG.headers.party:GetAttribute("child1").Member
		local role, leader, ready = frame.GroupRoleIndicator, frame.LeaderIndicator, CG:GetGridButton(frame).status.ReadyCheckIndicator
		frame.uf:GetReadyCheck():Set("ready")
		Mock.RunUntainted(leader.SetShown, leader, Mock.Secret(true)) -- an engine-owned shown state
		assert.has_no_error(function() leader:PostUpdate() end)
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(leader:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(ready:GetParent()))
		CG.Config:Set("indicators.rolePosition", "TOP")
		CG.Config:Set("indicators.roleOrder", 6)
		Mock.assignedRole = Mock.Secret(Enum.LFGRole.Healer)
		assert.has_no_error(function() role:PostUpdate() end)
		assert.same({ "CENTER", frame, "TOP", 16, 0 }, Anchor(role:GetParent()))
		Mock.assignedRole = nil
		role:PostUpdate()
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(role:GetParent()))
	end)

	it("positions portrait decorations without a raid-marker component", function()
		local spec = UF.Units:GetSpec(UF.Units.definitions.player)
		spec.raidTarget = nil
		local uf = UF.Components.UnitFrame:New(UIParent, { portrait = { enabled = true } }, spec)
		local status = uf:Own(CG.Status:New(uf:GetFrame(), { role = true, rolePosition = "PORTRAIT_BOTTOMLEFT" }, { unitFrame = uf }))
		local host = status.GroupRoleIndicator:GetParent()
		assert.is_true(host:IsShown())
		assert.equals("BOTTOMLEFT", host:GetPoint())
		assert.equals(uf:GetLayoutContext().portrait.frame, select(2, host:GetPoint()))
		uf:Apply({ portrait = { enabled = false } })
		status:LayoutIcons()
		assert.is_false(host:IsShown())
		uf:Release()
		assert.is_true(status.released)
	end)

	it("supports portrait role anchors and defers role layout changes in combat", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local role, marker = frame.GroupRoleIndicator, frame.uf:GetPart("raidTarget")
		CG.Config:Set("indicators.rolePosition", "PORTRAIT_BOTTOMLEFT")
		assert.is_false(role:GetParent():IsShown())
		CG.Config:SetStyle("member", "portrait.enabled", true)
		local portrait = frame.uf:GetLayoutContext().portrait.frame
		assert.is_true(role:GetParent():IsShown())
		assert.same({ "BOTTOMLEFT", portrait, "BOTTOMLEFT", 0, 0 }, Anchor(role:GetParent()))
		Native(marker:GetWidget(), true)
		CG.Config:SetStyle("member", "raidTarget.anchor", "PORTRAIT_BOTTOMLEFT")
		assert.same({ "BOTTOMLEFT", portrait, "BOTTOMLEFT", 0, 0 }, Anchor(marker:GetFrame()))
		assert.same({ "BOTTOMLEFT", portrait, "BOTTOMLEFT", 14, 0 }, Anchor(role:GetParent()))
		CG.Config:SetStyle("member", "raidTarget.anchor", "PORTRAIT_BOTTOMRIGHT")
		CG.Config:Set("indicators.rolePosition", "PORTRAIT_BOTTOMRIGHT")
		assert.same({ "BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -16, 0 }, Anchor(marker:GetFrame()))
		assert.same({ "BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0 }, Anchor(role:GetParent()))
		Mock.inCombat = true
		CG.Config:Set("indicators.rolePosition", "TOP")
		assert.equals("BOTTOMRIGHT", (role:GetParent():GetPoint()))
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(role:GetParent()))
		assert.same({ "BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0 }, Anchor(marker:GetFrame()))
	end)

	it("shows the same spirit artwork for the dead and ghosts", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local frame = CG.headers.party:GetAttribute("child1").Member
		local death, ready = frame.UFCG_DeathIndicator, CG:GetGridButton(frame).status.ReadyCheckIndicator
		local element, events = UF.oUF.elements.UFCG_DeathIndicator, {}
		local function Atlas()
			for i = #death.__calls, 1, -1 do
				if death.__calls[i][1] == "SetAtlas" then return death.__calls[i][2] end
			end
		end
		assert.is_true(frame:IsElementEnabled("UFCG_DeathIndicator"))
		frame.RegisterEvent = function(_, event, _, shared) events[event] = shared or false end
		frame.UnregisterEvent = function(_, event) events[event] = nil end
		assert.is_true(element.enable(frame))
		assert.same({ UNIT_HEALTH = false, UNIT_CONNECTION = false, PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true }, events)
		frame.__unit = "party1"
		frame.uf:GetReadyCheck():Set("ready")
		element.update(frame, "UNIT_HEALTH")
		assert.is_false(death:IsShown())
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(ready:GetParent()))
		Mock.dead.party1 = true
		element.update(frame, "UNIT_HEALTH")
		assert.is_true(death:IsShown())
		assert.equals("RaidFrame-Icon-Rez", Atlas())
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(ready:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(death:GetParent()))
		Mock.dead.party1, Mock.ghosts.party1 = nil, true
		element.update(frame, "UNIT_HEALTH")
		assert.equals("RaidFrame-Icon-Rez", Atlas())
		Mock.ghosts.party1 = Mock.Secret(true)
		assert.has_no_error(function() element.update(frame, "UNIT_HEALTH") end)
		assert.is_false(death:IsShown(), "an opaque state counts as alive")
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(ready:GetParent()))
		Mock.dead.party1 = true
		element.update(frame, "UNIT_HEALTH")
		element.disable(frame)
		assert.same({}, events)
		assert.is_false(death:IsShown())
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(ready:GetParent()))
		CG.Config:Set("indicators.death", false)
		assert.is_false(frame:IsElementEnabled("UFCG_DeathIndicator"))
		assert.is_false(death:GetParent():IsShown())
	end)

	it("stacks resurrection and summon and restores health text after resurrection", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local status, row = CG:GetGridButton(frame).status, frame.uf:GetRow("health")
		local rez, summon = frame.ResurrectIndicator, frame.SummonIndicator
		Mock.incomingResurrections.party1 = true
		frame.__unit = "party1"
		CG.Config:Set("indicators.role", false)
		CG.Config:SetStyle("member", "health.left.color", { 0.8, 0.2, 0.4, 1 })
		rez.Override(frame)
		assert.is_true(rez:IsShown())
		assert.same({ 0, 1, 0, 1 }, row:GetText("left"):GetFrame().__state.textColor)
		assert.same({ 0, 1, 0, 1 }, row:GetText("right"):GetFrame().__state.textColor)
		Native(summon, true)
		assert.same({ "CENTER", frame, "TOP", -8, 0 }, Anchor(rez:GetParent()))
		assert.same({ "CENTER", frame, "TOP", 8, 0 }, Anchor(summon:GetParent()))
		CG.Config:Set("indicators.resurrectionPosition", "NAME")
		CG.Config:Set("indicators.summonPosition", "NAME")
		assert.equals(32, row:GetText("left").leadingSpace)
		CG.Config:SetStyle("member", "health.left.color", { 0.3, 0.4, 0.5, 1 })
		assert.same({ 0, 1, 0, 1 }, row:GetText("left"):GetFrame().__state.textColor)
		Mock.incomingResurrections.party1 = false
		rez.Override(frame)
		assert.is_false(rez:IsShown())
		assert.equals(16, row:GetText("left").leadingSpace)
		assert.same({ 0.3, 0.4, 0.5, 1 }, row:GetText("left"):GetFrame().__state.textColor)
		Mock.incomingResurrections.party1 = Mock.Secret(true)
		assert.has_no_error(function() rez.Override(frame) end)
		assert.equals(32, row:GetText("left").leadingSpace, "opaque resurrection keeps its slot")
		assert.is_true(Mock.IsSecret(row:GetText("left"):GetFrame().__state.textColor[1]))
		CG.Config:Set("indicators.resurrectionText", false)
		assert.same({ 0.3, 0.4, 0.5, 1 }, row:GetText("left"):GetFrame().__state.textColor)
		CG.Config:Set("indicators.resurrectionText", true)
		CG.Config:Set("indicators.resurrection", false)
		assert.is_false(rez:GetParent():IsShown())
		assert.same({ 0.3, 0.4, 0.5, 1 }, row:GetText("left"):GetFrame().__state.textColor)
		CG.Config:Set("indicators.resurrection", true)
		Mock.incomingResurrections.party1 = true
		rez.Override(frame)
		frame.__unit = nil
		rez.Override(frame)
		assert.is_false(rez:IsShown())
		assert.same({ 0.3, 0.4, 0.5, 1 }, row:GetText("left"):GetFrame().__state.textColor)
		Native(summon, false)
		assert.equals(0, row:GetText("left").leadingSpace)
		status:SetResurrection(true)
		status:Release()
		assert.is_nil(row:GetText("left").colorCondition)
		assert.is_nil(frame.uf:GetDecorations().members.resurrection)
		assert.is_nil(frame.uf:GetDecorations().members.summon)
	end)

	it("reserves combined name space once and restores it when leader or role is disabled", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local role, leader = frame.GroupRoleIndicator, frame.LeaderIndicator
		local name = frame.uf:GetRow("health"):GetText("left")
		CG.Config:Set("indicators.leaderPosition", "NAME")
		assert.equals(16, name.leadingSpace, "no space for an absent leader")
		Native(leader, true)
		assert.equals(32, name.leadingSpace)
		assert.equals(-18, select(4, role:GetParent():GetPoint()))
		assert.equals(-2, select(4, leader:GetParent():GetPoint()))
		CG.Config:Set("indicators.leaderSize", 20)
		CG.Config:Set("indicators.leaderGap", 3)
		CG:RequestRefresh()
		assert.equals(39, name.leadingSpace)
		assert.equals(-25, select(4, role:GetParent():GetPoint()))
		assert.equals(-3, select(4, leader:GetParent():GetPoint()))
		CG.Config:Set("indicators.role", false)
		assert.equals(23, name.leadingSpace)
		CG.Config:Set("indicators.leader", false)
		assert.equals(0, name.leadingSpace)
		assert.is_false(leader:GetParent():IsShown())
		assert.is_false(frame:IsElementEnabled("AssistantIndicator"))
		CG.Config:Set("indicators.leader", true)
		Native(leader, true)
		assert.equals(23, name.leadingSpace)
		CG.Config:SetStyle("member", "health.left.enabled", false)
		assert.equals(0, name.leadingSpace)
		assert.is_false(leader:GetParent():IsShown())
	end)

	it("supports leader portrait anchors and defers leader changes in combat", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local leader = frame.LeaderIndicator
		CG.Config:Set("indicators.leaderPosition", "PORTRAIT_BOTTOMRIGHT")
		assert.is_false(leader:GetParent():IsShown())
		CG.Config:SetStyle("member", "portrait.enabled", true)
		assert.is_true(leader:GetParent():IsShown())
		assert.equals("BOTTOMRIGHT", leader:GetParent():GetPoint())
		Mock.inCombat = true
		CG.Config:Set("indicators.leaderPosition", "TOP")
		CG.Config:Set("indicators.leaderSize", 22)
		assert.equals("BOTTOMRIGHT", leader:GetParent():GetPoint())
		assert.equals(14, leader:GetParent():GetWidth())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(leader:GetParent()))
		assert.equals(22, leader:GetParent():GetWidth())
	end)

	it("styles fixed slots from the member's aura config, inheriting the theme", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local config = CG:SlotConfig(frame.uf)
		assert.is_nil(config.font, "inherited values stay inherited")
		assert.equals("CENTER", config.durationPosition, "member aura group defaults carry over")
		UF.Config:SetThemeValue("font", "Arial Narrow")
		assert.equals("Arial Narrow", CG:GetGridButton(frame).slots.resolved.font)
		CG.Config:SetStyle("member", "auras.font", "Morpheus")
		assert.equals("Morpheus", CG:GetGridButton(frame).slots.resolved.font)
		CG.Config:SetStyle("member", "auras.enabled", false)
		assert.is_false(CG:GetGridButton(frame).slots:IsEnabled())
		assert.equals(frame.uf, CG:GetGridButton(frame).slots.componentOwner)
		assert.equals(frame.uf, CG:GetGridButton(frame).status.componentOwner)
	end)

	it("defers slot restyling while native aura buttons deny access, then retries at combat end", function()
		local slots = CG:GetGridButton(CG.headers.party:GetAttribute("child1").Member).slots
		local config = UF.Util.Copy(slots.config)
		config.slot1 = config.slot1 or {}
		config.slot1.offsetX = 7
		Mock.aurasSecret = true
		assert.has_no_error(function() slots:Apply(config) end)
		assert.is_true(UF.AfterCombat:IsQueued(slots, "restyle"))
		Mock.aurasSecret = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_false(UF.AfterCombat:IsQueued(slots, "restyle"))
		assert.equals(7, select(4, slots.buttons[1]:GetPoint()))
	end)

	it("keeps profile style separate from character/spec bindings", function()
		CG.Config:SetStyle("member", "width", 190)
		CG.Config:SetBinding(1, "none", "friendly", "spell", "2061")
		Mock.specIndex = 2
		assert.is_nil(next(CG.Config:GetBindings()))
		CG.Config:SetBinding(1, "none", "friendly", "spell", "139")
		Mock.specIndex = 1
		assert.equals("2061", CG.Config:GetBindings().button1.none.friendly.spell)
		UF.Config.db:SetProfile("Another")
		assert.is_nil(CG.Config:GetStyle("member").width)
		assert.equals("2061", CG.Config:GetBindings().button1.none.friendly.spell)
	end)

	it("resolves every modifier and clears previous spells and wildcard actions", function()
		local B, config = CG.Bindings, {}
		for i, modifier in ipairs(B.modifiers) do
			UF.Util.SetPath(config, "button1." .. modifier[1] .. ".friendly", { action = "spell", spell = tostring(2060 + i) })
		end
		local frame = CG.headers.party:GetAttribute("child1").Member
		local plan, errors = B:Compile(config)
		assert.equals(0, #errors)
		B:Apply(frame, plan)
		for i, modifier in ipairs(B.modifiers) do assert.equals(2060 + i, frame:GetAttribute(modifier[3] .. "spell-heal1")) end
		B:Apply(frame, B:Compile({}))
		assert.is_nil(frame:GetAttribute("shift-spell-heal1"))
		assert.is_nil(frame:GetAttribute("*type1"))
		assert.equals("target", frame:GetAttribute("type-heal1"))
		assert.equals("togglemenu", frame:GetAttribute("type-harm2"))
	end)

	it("keeps unknown spell intent and resolves overrides after spell updates", function()
		Mock.unknownSpells[2061] = true
		CG.Config:SetBinding(1, "none", "friendly", "action", "spell")
		CG.Config:SetBinding(1, "none", "friendly", "spell", "2061")
		local frame = CG.headers.party:GetAttribute("child1").Member
		assert.is_nil(frame:GetAttribute("type-heal1"))
		assert.equals("2061", CG.Config:GetBindings().button1.none.friendly.spell)
		assert.equals(1, #CG.bindingErrors)
		Mock.spellOverrides[2061], Mock.unknownSpells[2061] = 2062, nil
		Mock.FireEvent("SPELLS_CHANGED")
		assert.equals(2062, frame:GetAttribute("spell-heal1"))
		assert.equals(0, #CG.bindingErrors)
	end)

	it("respects Clique ownership and does not rewrite its attributes", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		Clique = {}
		frame:SetAttribute("type-heal1", "external")
		CG:RequestRefresh()
		assert.equals("external", frame:GetAttribute("type-heal1"))
		Clique = nil
	end)

	it("keeps shield scale options correct across placement and repeated toggles", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		CG.Config:SetStyle("member", "health.bar.segments.absorb.placement", "append")
		assert.equals(Enum.UnitMaximumHealthMode.WithAbsorbs, frame.Health.maximumHealthClampMode)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.enabled", false)
		assert.equals(Enum.UnitMaximumHealthMode.Default, frame.Health.maximumHealthClampMode)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.enabled", true)
		assert.equals(Enum.UnitMaximumHealthMode.WithAbsorbs, frame.Health.maximumHealthClampMode)
	end)

	it("validates fixed friendly-buff IDs and passes them to native slots", function()
		assert.is_false(CG.Config:Set("slots.slot1.spell", "139, invalid"))
		assert.is_false(CG.Config:Set("slots.slot1.spell", "1e999"))
		CG.Config:Set("slots.slot1.spell", "139,774")
		CG.Config:Set("slots.slot1.enabled", true)
		local slots = CG:GetGridButton(CG.headers.party:GetAttribute("child1").Member).slots
		local native = slots.container.__state.slots.slot1
		assert.equals("HELPFUL|PLAYER", native.filter)
		assert.same({ [139] = true, [774] = true }, native.candidateFilters.includeSpellIDs)
		CG.Config:Set("slots.slot1.enabled", false)
		assert.same({}, native.candidateFilters.includeSpellIDs)
		assert.is_nil(UF.Schema.Find(CG.SlotSchema, "slot1.debuff"))
	end)
end)

describe("ClickGrid Workbench", function()
	local UF, CG, wb
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	it("renders matching flat-grid column headings outside the single backdrop", function()
		CG.Config:Set("panel.mode", "flat")
		CG.Config:Set("panel.columns", 5)
		CG.Config:Set("panel.rows", 5)
		wb.dataTarget.set("count", 25)
		local preview, header = wb.handle, CG.headers.raid
		assert.is_false(preview.labels.raid:IsShown())
		assert.is_false(CG:GetHeaderTitles(header).label:IsShown())
		for column = 1, 5 do
			assert.equals("Group " .. column, preview.labels["column" .. column]:GetText())
			assert.equals("Group " .. column, CG:GetHeaderTitles(header).columns[column]:GetText())
			assert.equals(preview.layout.cellWidth, preview.labels["column" .. column]:GetWidth())
		end
		local cfg = CG.Config:Resolved()
		local section = preview.layout.sections.raid
		local _, _, _, x, y = preview.labels.column2:GetPoint()
		assert.equals(section.x + preview.layout.cellWidth + cfg.panel.spacingX, x)
		assert.equals(-section.y + cfg.titles.gap + cfg.panel.padding, y)
		assert.equals(-CG.Layout.TitleHeight(cfg.titles), select(5, preview.background:GetPoint()))
		CG.Config:Set("titles.group2", "Healers")
		assert.equals("Healers", preview.labels.column2:GetText())
		assert.equals("Healers", CG:GetHeaderTitles(header).columns[2]:GetText())
		CG.Config:Set("titles.enabled", false)
		assert.is_false(preview.labels.column2:IsShown())
		assert.is_false(CG:GetHeaderTitles(header).columns[2]:IsShown())
		CG.Config:Set("panel.mode", "subgroups")
		assert.is_false(preview.labels.column2:IsShown())
		assert.is_false(CG:GetHeaderTitles(header).columns[2]:IsVisible())
	end)

	it("previews five-by-five preferences with safe overflow rather than rewriting either control", function()
		CG.Config:Set("panel.mode", "flat")
		wb.styleTarget.set("panel.columns", 5)
		wb.styleTarget.set("panel.rows", 5)
		wb.dataTarget.set("count", 25)
		local grid = wb.handle.layout.sections.raid.grid
		assert.equals(5, grid.columns)
		assert.equals(5, grid.rows)
		wb.dataTarget.set("count", 40)
		grid = wb.handle.layout.sections.raid.grid
		assert.equals(8, grid.columns)
		assert.equals(5, grid.rows)
		assert.equals(5, CG.Config:Resolved().panel.columns)
		assert.equals(5, CG.Config:Resolved().panel.rows)
		CG.Config:Set("panel.flow", "across")
		grid = wb.handle.layout.sections.raid.grid
		assert.equals(5, grid.columns)
		assert.equals(8, grid.rows)
		assert.equals(40, #wb.handle.cells)
		wb.dataTarget.set("count", 25)
		assert.equals(5, wb.handle.layout.sections.raid.grid.rows)
		assert.is_false(wb.handle.cells[26].frame:IsShown())
	end)

	it("fits the whole configured raid grid inside the stage instead of clipping its first columns", function()
		wb.stage:SetSize(700, 400)
		wb:GetDB().stage.scale = 2
		CG.Config:SetStyle("member", "width", 600)
		wb.dataTarget.set("count", 40)
		local preview = wb.handle
		local width, height = preview.frame:GetSize()
		local expected = math.min(2, 668 / width, 368 / height)
		assert.equals(expected, wb.holder:GetScale())
		assert.equals(2, wb:GetDB().stage.scale)
		assert.same({ "CENTER", wb.holder, "CENTER", 0, 0 }, { preview.frame:GetPoint() })
		assert.same({ "TOPLEFT", preview.frame, "TOPLEFT", preview.layout.sections.group2.x,
			-preview.layout.sections.group2.y }, { preview.cells[6].frame:GetPoint() })
		assert.equals(600, CG.headers.group1:GetAttribute("child1").Member:GetWidth())
		assert.equals(1, CG.panel:GetScale())
		wb.stage:SetSize(400, 300)
		assert.equals(math.min(2, 368 / width, 268 / height), wb.holder:GetScale())
		CG.Config:Set("panel.mode", "flat")
		width, height = preview.frame:GetSize()
		assert.equals(math.min(2, 368 / width, 268 / height), wb.holder:GetScale())
	end)

	it("refits on count changes and restores normal scale after leaving the group preview", function()
		wb.stage:SetSize(500, 400)
		wb.dataTarget.set("count", 40)
		assert.is_true(wb.holder:GetScale() < 1)
		wb.dataTarget.set("count", 1)
		assert.equals(1, wb.holder:GetScale())
		local old = wb.handle
		wb:Select("clickgrid.member")
		assert.is_nil(old.frame:GetScript("OnSizeChanged"))
		assert.is_true(wb.entry.fitToStage)
		wb:GetDB().stage.scale = 1.5
		wb:Select("unit.player")
		assert.equals(1.5, wb.holder:GetScale())
	end)

	it("defers stage fitting during combat and resumes without touching native aura dimensions", function()
		wb.stage:SetSize(700, 400)
		wb.dataTarget.set("count", 40)
		local before = wb.holder:GetScale()
		Mock.inCombat = true
		wb.stage:SetSize(400, 300)
		assert.equals(before, wb.holder:GetScale())
		assert.is_true(wb.pendingStageFit)
		Mock.inCombat = false
		wb:OnUpdate(0.01)
		assert.is_nil(wb.pendingStageFit)
		local width, height = wb.handle.frame:GetSize()
		assert.equals(math.min(1, 368 / width, 268 / height), wb.holder:GetScale())
	end)

	it("shares custom title text and styling with live headers", function()
		wb.dataTarget.set("count", 10)
		wb.styleTarget.set("titles.group1", "Healing team")
		CG.Config:Set("titles.size", 17)
		CG.Config:Set("titles.outline", "OUTLINE")
		CG.Config:Set("titles.color", { 0.2, 0.4, 0.6, 0.8 })
		CG.Config:Set("titles.alignment", "RIGHT")
		CG.Config:Set("titles.shadow", false)
		local live, preview = CG:GetHeaderTitles(CG.headers.group1).label, wb.handle.labels.group1
		assert.equals("Healing team", live:GetText())
		assert.equals(live:GetText(), preview:GetText())
		assert.equals("Group 2", wb.handle.labels.group2:GetText())
		assert.same(live.__state.font, preview.__state.font)
		assert.equals(17, preview.__state.font[2])
		assert.equals("OUTLINE", preview.__state.font[3])
		assert.same({ 0.2, 0.4, 0.6, 0.8 }, preview.__state.textColor)
		assert.equals(CG.layout.sections.group1.grid.width, preview:GetWidth())
		CG.Config:Set("titles.enabled", false)
		assert.is_false(preview:IsShown())
		assert.is_false(live:IsShown())
		CG.Config:Set("titles.enabled", true)
		assert.is_true(preview:IsShown())
		assert.is_true(CG.Config:Set("titles.outline", ""))
		assert.equals("", preview.__state.font[3])
	end)

	it("keeps below-title preview placement inside the solo panel", function()
		wb.dataTarget.set("count", 1)
		CG.Config:Set("titles.position", "below")
		CG.Config:Set("titles.offsetX", 4)
		CG.Config:Set("titles.offsetY", -2)
		local preview, cfg = wb.handle, CG.Config:Resolved()
		local section = preview.layout.sections.party
		assert.same({ "TOPLEFT", preview.frame, "TOPLEFT", section.x + 4,
			-section.y - preview.layout.cellHeight - cfg.titles.gap - cfg.panel.padding - 2 }, { preview.labels.party:GetPoint() })
		assert.equals(preview.layout.solo.height, preview.frame:GetHeight())
	end)

	it("fits party previews to occupied rows for sample and live sources", function()
		for _, flow in ipairs({ "down", "across" }) do
			CG.Config:Set("panel.flow", flow)
			CG.Config:Set("titles.position", "below")
			for _, source in ipairs({ "static", "animated", "live" }) do
				wb.dataTarget.set("source", source)
				for _, count in ipairs({ 2, 5, 3, 1 }) do
					Mock.inParty, Mock.groupSize = count > 1, count
					wb.dataTarget.set("count", count)
					local preview, cfg = wb.handle, CG.Config:Resolved()
					local section = preview.layout.sections.party
					assert.equals(count, section.grid.rows)
					assert.equals(section.grid.height + CG.Layout.TitleHeight(cfg.titles)
						+ 2 * cfg.panel.padding, preview.frame:GetHeight())
					assert.same({ "TOPLEFT", preview.frame, "TOPLEFT", section.x + cfg.titles.offsetX,
						-section.y - section.grid.height - cfg.titles.gap - cfg.panel.padding + cfg.titles.offsetY },
						{ preview.labels.party:GetPoint() })
					if preview.cells[count + 1] then assert.is_false(preview.cells[count + 1].frame:IsShown()) end
				end
			end
		end
	end)

	it("renders enemy targets with NPC reaction colors instead of an absent class token", function()
		assert.has_error(function() C_ClassColor.GetClassColor(nil) end)
		CG.Config:Set("panel.targets", true)
		local target = wb.handle.cells[1].target:GetRow("health"):GetBar()
		assert.same(UF.Config:GetTheme().colors.hostile, target.bar.__state.color)
		assert.has_no_error(function()
			wb:Select("clickgrid.target")
			wb.dataTarget.set("source", "animated")
			wb:OnUpdate(0.2)
		end)
		assert.same(UF.Config:GetTheme().colors.hostile, wb.handle.cells[1].target:GetRow("health"):GetBar().bar.__state.color)
		assert.same({ 0.5, 0.5, 0.5 }, { UF.Colors.Class(nil) })
		assert.same({ UF.Colors.Class("MAGE") }, { UF.Colors.Class(Mock.Secret("MAGE")) })
	end)

	it("does not populate hidden targets in static, animated or live previews", function()
		local target = wb.handle.cells[1].target
		local showSample, showLive = UF.Units.ShowSample, wb.handle.ShowLive
		local samples, liveUpdates = 0, 0
		UF.Units.ShowSample = function(self, uf, values)
			if uf == target then samples = samples + 1 end
			return showSample(self, uf, values)
		end
		wb.handle.ShowLive = function(self, uf, ...)
			if uf == target then liveUpdates = liveUpdates + 1 end
			return showLive(self, uf, ...)
		end
		wb.handle:Apply()
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.equals(0, samples)
		assert.is_false(target:GetFrame():IsShown())
		CG.Config:Set("panel.targets", true)
		assert.is_true(samples > 0)
		CG.Config:Set("panel.targets", false)
		samples = 0
		wb:OnUpdate(0.2)
		assert.equals(0, samples)
		wb.dataTarget.set("source", "live")
		wb:OnUpdate(0.2)
		assert.equals(0, liveUpdates)
		CG.Config:Set("panel.targets", true)
		assert.is_true(liveUpdates > 0)
	end)

	it("does not tick or apply config after a preview failed to build", function()
		local entry = wb.entries["clickgrid.panel"]
		local create = entry.create
		entry.create = function() error("preview construction failed") end
		assert.has_error(function() wb:Select("clickgrid.panel") end)
		entry.create = create
		assert.is_nil(wb.session)
		assert.has_no_error(function()
			wb:OnUpdate(0.005)
			CG.Config:Set("panel.columns", 2)
		end)
		assert.equals(0, wb.entryState.time)
		assert.has_no_error(function() wb:Select("clickgrid.panel"); wb:OnUpdate(0.005) end)
		assert.is_not_nil(wb.handle)
	end)

	it("uses saved settings for panel and both bar styles", function()
		assert.is_not_nil(wb.entries["clickgrid.bindings"])
		wb.styleTarget.set("panel.columns", 2)
		assert.equals(2, CG.Config:Resolved().panel.columns)
		wb:Select("clickgrid.member")
		wb.styleTarget.set("width", 205)
		assert.equals(205, wb.handle.cells[1].member:GetFrame():GetWidth())
		assert.equals(205, CG.headers.party:GetAttribute("child1").Member:GetWidth())
	end)

	it("matches role placement in previews and removes name reservations when released", function()
		local cell = wb.handle.cells[1]
		local role = cell.status.GroupRoleIndicator
		local name = cell.member:GetRow("health"):GetText("left")
		assert.equals(16, name.leadingSpace)
		-- Sample member 1: marker 12, role 14 and leader 14 at the top, 44 wide.
		CG.Config:Set("indicators.rolePosition", "TOP")
		local frame = cell.member:GetFrame()
		assert.same({ "CENTER", frame, "TOP", -16, 0 }, { cell.member:GetPart("raidTarget"):GetFrame():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", -1, 0 }, { role:GetParent():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", 15, 0 }, { cell.status.LeaderIndicator:GetParent():GetPoint() })
		assert.equals(0, name.leadingSpace)
		CG.Config:Set("indicators.rolePosition", "NAME")
		assert.equals(16, name.leadingSpace)
		CG.Config:SetStyle("member", "health.left.enabled", false)
		assert.is_false(role:GetParent():IsShown())
		assert.equals(0, name.leadingSpace)
		CG.Config:SetStyle("member", "health.left.enabled", true)
		assert.equals(16, name.leadingSpace)
		local status = cell.status
		wb:Select("unit.player")
		assert.equals(0, name.leadingSpace)
		assert.is_true(status.released)
		assert.is_false(status:GetFrame():IsShown())
	end)

	it("matches leader placement in samples and cleans up combined name reservations", function()
		CG.Config:Set("indicators.leaderPosition", "NAME")
		local cell = wb.handle.cells[1]
		local name = cell.member:GetRow("health"):GetText("left")
		assert.equals(32, name.leadingSpace)
		assert.is_true(cell.status.LeaderIndicator:IsShown())
		assert.is_true(wb.handle.cells[2].status.AssistantIndicator:IsShown())
		assert.is_false(wb.handle.cells[2].status.LeaderIndicator:IsShown())
		CG.Config:Set("indicators.leaderPosition", "TOP")
		assert.same({ "CENTER", cell.member:GetFrame(), "TOP", 7, 0 }, { cell.status.LeaderIndicator:GetParent():GetPoint() })
		assert.equals(16, name.leadingSpace)
		CG.Config:Set("indicators.leaderPosition", "NAME")
		wb:Select("unit.player")
		assert.equals(0, name.leadingSpace)
		assert.is_false(cell.status.LeaderIndicator:GetParent():IsVisible())
	end)

	it("samples ready checks, the dead and ghosts in grouped edge icons", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local function Atlas(icon)
			for i = #icon.__calls, 1, -1 do
				if icon.__calls[i][1] == "SetAtlas" then return icon.__calls[i][2] end
			end
		end
		local second, third, fifth = wb.handle.cells[2], wb.handle.cells[3], wb.handle.cells[5]
		-- Member 2 has no marker: assistant 14 + gap 2 + ready check 14.
		local ready = second.status.ReadyCheckIndicator
		assert.is_true(ready:IsShown())
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", -8, 0 }, { second.status.AssistantIndicator:GetParent():GetPoint() })
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", 8, 0 }, { ready:GetParent():GetPoint() })
		local dead, ghost = third.status.UFCG_DeathIndicator, fifth.status.UFCG_DeathIndicator
		assert.is_true(dead:IsShown())
		assert.is_true(ghost:IsShown())
		assert.equals("RaidFrame-Icon-Rez", Atlas(dead))
		assert.equals(Atlas(dead), Atlas(ghost))
		assert.is_false(wb.handle.cells[4].status.UFCG_DeathIndicator:IsShown())
		assert.same({ "CENTER", third.member:GetFrame(), "TOP", -8, 0 }, { dead:GetParent():GetPoint() })
		assert.same({ "CENTER", third.member:GetFrame(), "TOP", 8, 0 }, { third.status.ResurrectIndicator:GetParent():GetPoint() })
		CG.Config:Set("indicators.death", false)
		assert.is_false(dead:IsShown())
		assert.is_false(dead:GetParent():IsShown())
		CG.Config:Set("indicators.readyOrder", 1)
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", -8, 0 }, { ready:GetParent():GetPoint() })
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", -8, 0 }, { ready:GetParent():GetPoint() })
	end)

	it("previews green resurrection text and clears it on toggles and release", function()
		local third, fourth = wb.handle.cells[3], wb.handle.cells[4]
		local text = third.member:GetRow("health"):GetText("left")
		assert.same({ 0, 1, 0, 1 }, text:GetFrame().__state.textColor)
		assert.same({ 1, 1, 1, 1 }, fourth.member:GetRow("health"):GetText("left"):GetFrame().__state.textColor)
		assert.is_true(fourth.status.SummonIndicator:IsShown())
		assert.same({ "CENTER", fourth.member:GetFrame(), "TOP", 0, 0 }, { fourth.status.SummonIndicator:GetParent():GetPoint() })
		CG.Config:Set("indicators.resurrectionText", false)
		assert.same({ 1, 1, 1, 1 }, text:GetFrame().__state.textColor)
		CG.Config:Set("indicators.resurrectionText", true)
		assert.same({ 0, 1, 0, 1 }, text:GetFrame().__state.textColor)
		CG.Config:Set("indicators.resurrection", false)
		assert.same({ 1, 1, 1, 1 }, text:GetFrame().__state.textColor)
		assert.same({ "CENTER", third.member:GetFrame(), "TOP", 0, 0 }, { third.status.UFCG_DeathIndicator:GetParent():GetPoint() })
		CG.Config:Set("indicators.resurrection", true)
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.same({ 0, 1, 0, 1 }, text:GetFrame().__state.textColor)
		third.status:HideIndicators()
		assert.same({ 1, 1, 1, 1 }, text:GetFrame().__state.textColor)
		third.status:ShowSample(3)
		wb:Select("unit.player")
		assert.is_nil(text.colorCondition)
	end)

	it("previews 40 members, animated timers, configured slots and full-health shields", function()
		wb.dataTarget.set("count", 40)
		assert.equals(40, #wb.handle.cells)
		CG.Config:Set("slots.slot1.spell", "139")
		CG.Config:Set("slots.slot1.enabled", true)
		wb:UpdateData()
		local cell = wb.handle.cells[1]
		assert.is_true(cell.slots.samples[1]:IsShown())
		local remaining = cell.member:GetPart("auras").previewData.buffs[3].remaining
		wb:OnUpdate(0.2)
		assert.equals(remaining, cell.member:GetPart("auras").previewData.buffs[3].remaining)
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.is_true(remaining ~= cell.member:GetPart("auras").previewData.buffs[3].remaining)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.placement", "append")
		wb.dataTarget.set("source", "static")
		assert.equals(28800, cell.member:GetRow("health"):GetBar():GetStatusBar().__state.max)
	end)

	it("shows live opaque data without secret arithmetic and defers source changes in combat", function()
		CG.headers.party:Assign(1, "player")
		assert.has_no_error(function() wb.dataTarget.set("source", "live") end)
		assert.is_true(Mock.IsSecret(wb.handle.cells[1].member:GetRow("health"):GetBar():GetStatusBar().__state.value))
		Mock.inCombat = true
		assert.has_no_error(function()
			wb.dataTarget.set("count", 40)
			wb.dataTarget.set("source", "static")
			wb:Select("clickgrid.target")
		end)
		assert.equals(0, #wb.handle.cells)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(#wb.handle.cells > 0)
		assert.is_nil(next(CG.retiredPreviews))
	end)

	it("previews sparse live raids without assuming consecutive subgroup occupancy", function()
		Mock.inRaid, Mock.groupSize = true, 4
		CG.headers.group8:Assign(1, "raid1")
		wb.dataTarget.set("source", "live")
		assert.equals(40, #wb.handle.cells)
		assert.is_true(wb.handle.cells[36].member:GetFrame():IsShown())
		assert.equals("raid1", wb.handle.cells[36].member:GetPart("auras").containers.buffs:GetUnit())
	end)

	it("releases old previews and their native aura subscriptions when switching entries", function()
		local old = wb.handle
		wb:Select("clickgrid.bindings")
		assert.is_true(old.released)
		assert.is_nil(CG.previews[old])
		assert.is_false(old.cells[1].slots.container:IsEnabled())
		wb.styleTarget.set("friendly.action", "spell")
		wb.styleTarget.set("friendly.spell", "2061")
		assert.equals(2061, CG.headers.party:GetAttribute("child1").Member:GetAttribute("spell-heal1"))
		assert.has_no_error(function() wb:Select("unit.player"); wb:Select("clickgrid.bindings") end)
	end)

	it("edits another binding cell and refreshes on saves without rebuilding the preview", function()
		wb:Select("clickgrid.bindings")
		local session, handle = wb.session, wb.handle
		handle.buttons["2:3"].opts.onClick()
		assert.equals(3, wb.styleTarget.resolved().button)
		assert.equals("shift", wb.styleTarget.resolved().modifier)
		wb.styleTarget.set("friendly.action", "focus")
		assert.equals(session, wb.session)
		assert.is_false(handle.released == true)
		assert.equals("focus", CG.Config:GetBindings().button3.shift.friendly.action)
		CG.Config:SetBinding(1, "none", "hostile", "action", "assist")
		assert.equals(session, wb.session)
		assert.is_true(handle.buttons["1:1"].text:GetText():find("target", 1, true) ~= nil)
	end)

	it("restyles only the ClickGrid entries when ClickGrid settings change", function()
		wb:Select("unit.player")
		local session = wb.session
		CG.Config:Set("panel.columns", 3)
		assert.equals(session, wb.session)
		assert.is_false(session.released == true)
	end)

	it("registers entries when Workbench was loaded before the companion", function()
		local core, workbench = Helpers.LoadWorkbench()
		Helpers.LoadToc("UnitFrames_ClickGrid/UnitFrames_ClickGrid.toc", "UnitFrames_ClickGrid")
		Mock.FireEvent("ADDON_LOADED", "UnitFrames_ClickGrid")
		Mock.FireEvent("PLAYER_LOGIN")
		assert.is_not_nil(workbench.entries["clickgrid.panel"])
		assert.equals(core.ClickGrid, UnitFrames.ClickGrid)
	end)
end)
