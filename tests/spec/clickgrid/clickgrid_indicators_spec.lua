local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid status indicators", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	it("only reflows death indicators when their plain presence changes", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		frame.__unit = "party1"
		local element = UF.oUF.elements.UFCG_DeathIndicator
		local stack, reflows = frame.uf:GetDecorations(), 0
		local reflow = stack.Reflow
		stack.Reflow = function(self) reflows = reflows + 1; return reflow(self) end
		element.update(frame)
		local initial = reflows
		for _ = 1, 100 do element.update(frame) end
		assert.equals(initial, reflows)
		Mock.dead.party1 = true
		element.update(frame)
		assert.equals(initial + 1, reflows)
		Mock.dead.party1, Mock.ghosts.party1 = false, true
		element.update(frame)
		assert.equals(initial + 1, reflows, "dead to ghost occupies the same slot")
		Mock.ghosts.party1 = false
		element.update(frame)
		assert.equals(initial + 2, reflows)
		frame.__unit = "party2"
		Mock.dead.party2 = Mock.Secret(true)
		element.update(frame)
		assert.equals(initial + 2, reflows)
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
		-- Every shared portrait position reaches the member options.
		local values = {}
		for _, value in ipairs(UF.Schema.Find(CG.IndicatorSchema, "rolePosition").values) do values[value[1]] = true end
		for _, anchor in ipairs(UF.DecorationStack.ANCHORS) do assert.is_true(values[anchor[1]], anchor[1]) end
		CG.Config:SetStyle("member", "raidTarget.anchor", "PORTRAIT_TOP")
		CG.Config:Set("indicators.rolePosition", "PORTRAIT_TOP")
		local markerAt, roleAt = Anchor(marker:GetFrame()), Anchor(role:GetParent())
		assert.same({ "TOP", portrait, "TOP" }, { markerAt[1], markerAt[2], markerAt[3] })
		assert.same({ "TOP", portrait, "TOP" }, { roleAt[1], roleAt[2], roleAt[3] })
		-- One row centred on the portrait: its left and right edges mirror each other.
		local markerSize, roleSize = marker:GetFrame():GetWidth(), role:GetParent():GetWidth()
		assert.is_true(roleAt[4] > markerAt[4])
		assert.equals(-(roleAt[4] + roleSize / 2), markerAt[4] - markerSize / 2)
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
end)
