local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Collapsing icon row", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	local function Member()
		CG.Config:SetStyle("member", "auraBar.enabled", true)
		local frame = CG.headers.party:GetAttribute("child1").Member
		local uf = frame.uf
		return frame, uf, uf:GetRow("health"), uf:GetPart("auraBar")
	end
	local function Root(row) return row:GetBar():GetFrame() end
	local function LastCall(object, method)
		local value
		for _, call in ipairs(object.__calls) do if call[1] == method then value = call[2] end end
		return value
	end

	it("is offered on every unit frame and group bar", function()
		for _, kind in ipairs({ "member", "target" }) do
			local option = UF.Schema.Find(CG:StyleSchema(kind), "auraBar.collapse")
			assert.is_not_nil(option, kind)
			assert.is_true(option.default)
		end
		for _, unit in ipairs(UF.Units.order) do
			local uf = UF.Units.frames[unit].uf
			assert.is_not_nil(UF.Schema.Find(UF.Units:GetSchema(unit), "auraBar.collapse"), unit)
			assert.is_true(uf:IsNativeLayout(), unit)
			assert.is_true(Mock.HasLayoutAspect(Root(uf:GetRow("health"))), unit)
			assert.is_false(Mock.HasLayoutAspect(uf:GetFrame()), unit)
			-- Only health follows the row; other bars stay ordinary.
			for key, row in uf:Rows() do
				if key ~= "health" then assert.is_false(Mock.HasLayoutAspect(row:GetFrame()), unit .. " " .. key) end
			end
		end
		local _, uf, row = Member()
		assert.is_true(Mock.HasLayoutAspect(Root(row)))
		assert.is_false(Mock.HasLayoutAspect(row:GetFrame()))
		assert.is_nil(CG.Config:GetStyle("member").auraBar.collapse, "the default is not written as an override")
	end)

	it("anchors standalone health to the row and to the oUF unit's presence feed", function()
		UF.Config:SetUnitValue("target", "auraBar.enabled", true)
		local frame = UF.Units.frames.target
		local row, bar = frame.uf:GetRow("health"), frame.uf:GetPart("auraBar")
		assert.same({ "BOTTOMRIGHT", bar:GetViewport(), "TOPRIGHT", 0, 0 }, Root(row):GetAnchor("BOTTOMRIGHT"))
		frame.__unit = "focus"
		UF.oUF.elements.UF_AuraBar.update(frame, "UnitFramesRefresh")
		assert.equals("focus", bar.presence:GetUnit())
		assert.is_true(bar.presence:IsEnabled())
		-- Copied player settings keep the choice independently.
		UF.Config:SetUnitValue("player", "auraBar.collapse", false)
		UF.Units:CopyPlayerSettings("target")
		assert.is_false(frame.uf.resolved.auraBar.collapse)
		assert.same({ "ALL", row:GetFrame() }, Root(row).__state.points[1])
	end)

	it("places the row beside health without changing the bar's height", function()
		local spec = UF.Units:GetSpec(CG.definitions.member)
		local function Compute(config)
			return UF.UnitFrameLayout.Compute(spec, UF.Schema.Resolve(CG:StyleSchema("member"), config, UF.Config:GetTheme()))
		end
		local function Keys(layout)
			local keys = {}
			for i, item in ipairs(layout.rows) do keys[i] = item.key end
			return keys
		end
		local collapsing = Compute({ auraBar = { enabled = true }, power = { enabled = true } })
		local fixed = Compute({ auraBar = { enabled = true, collapse = false }, power = { enabled = true } })
		assert.is_true(collapsing.auraBarCollapses)
		assert.is_false(fixed.auraBarCollapses)
		assert.same({ "health", "auraBar", "power" }, Keys(collapsing))
		assert.same({ "health", "power", "auraBar" }, Keys(fixed))
		assert.equals(fixed.height, collapsing.height)
		local top = Compute({ auraBar = { enabled = true, position = "top" }, power = { enabled = true } })
		assert.same({ "auraBar", "health", "power" }, Keys(top))
		assert.is_false(Compute({ auraBar = { enabled = true }, health = { enabled = false } }).auraBarCollapses)
		assert.is_false(Compute({}).auraBarCollapses)
		-- Secure cells keep their precomputed size: collapsing is anchoring only.
		local _, uf = Member()
		local height = CG.metrics.member.height
		CG.Config:SetStyle("member", "auraBar.collapse", false)
		assert.equals(height, CG.metrics.member.height)
		assert.equals(height, uf.layout.height)
	end)

	it("anchors health to the row's viewport, sized by a mirrored native presence container", function()
		local frame, uf, row, bar = Member()
		local gap, height = uf.resolved.spacing, bar.resolved.height
		local viewport, presence = bar:GetViewport(), bar.presence
		assert.same({ "TOPLEFT", row:GetFrame(), "TOPLEFT", 0, 0 }, Root(row):GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOMRIGHT", viewport, "TOPRIGHT", 0, 0 }, Root(row):GetAnchor("BOTTOMRIGHT"))
		assert.same({ "TOPLEFT", presence, "TOPLEFT", 0, -1 }, viewport:GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOMRIGHT", bar:GetFrame(), "BOTTOMRIGHT", 0, 0 }, viewport:GetAnchor("BOTTOMRIGHT"))
		assert.same({ "BOTTOMLEFT", bar:GetFrame(), "BOTTOMLEFT", 0, 0 }, presence:GetAnchor("BOTTOMLEFT"))
		assert.equals(true, LastCall(viewport, "SetClipsChildren"))
		assert.is_true(Mock.HasLayoutAspect(viewport))
		local state = presence.__state
		assert.equals("BOTTOMLEFT", state.flowAnchor)
		assert.same({ AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up }, state.growth)
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			local group, visible = state.groups[kind], bar:GetContainer(kind).__state.groups[kind]
			assert.equals(1, group.options.maxFrameCount)
			assert.equals(height + gap + 1, group.layout.elementHeight)
			assert.equals(visible.filter, group.filter)
			assert.same(visible.candidateFilters, group.candidateFilters)
			assert.equals(visible.enabled, group.enabled)
			assert.equals(false, LastCall(group.frames[1], "EnableMouse"), "artless buttons ignore the mouse")
		end
		assert.is_true(presence:IsEnabled())
		assert.is_true(presence:IsShown())
		frame.__unit = "party1"
		UF.oUF.elements.UF_AuraBar.update(frame, "UnitFramesRefresh")
		assert.equals("party1", presence:GetUnit())
		assert.equals("party1", bar:GetContainer("buffs"):GetUnit())
		-- Mirrors filters and capacity on restyle.
		CG.Config:SetStyle("member", "auraBar.buffs.filter", "HELPFUL|PLAYER")
		CG.Config:SetStyle("member", "auraBar.buffs.maxDuration", 60)
		CG.Config:SetStyle("member", "auraBar.debuffs.enabled", false)
		assert.equals("HELPFUL|PLAYER", state.groups.buffs.filter)
		assert.same({ maxDuration = 60 }, state.groups.buffs.candidateFilters)
		assert.is_false(state.groups.debuffs.enabled)
	end)

	it("matches Blizzard's flow arithmetic: one cell with any icon, nothing without", function()
		local source = loadfile("examples/wow-ui-source-forever/Interface/AddOns/Blizzard_SharedXMLBase/AnchorUtil.lua")
		if not source then return end
		local env = setmetatable({
			GenerateClosure = function(fn, value) return function(...) return fn(value, ...) end end,
			CreateFromMixins = function(...) local out = {}; for i = 1, select("#", ...) do
				for key, value in pairs(select(i, ...)) do out[key] = value end end; return out end,
			GetValueOrCallFunction = function(owner, key)
				local value = owner[key]
				return type(value) == "function" and value() or value
			end,
		}, { __index = _G })
		setfenv(source, env)
		source()
		local _, uf, _, bar = Member()
		local state = bar.presence.__state
		local flow = env.AnchorUtil.CreateFlowLayout()
		flow:SetAnchorPoint(state.flowAnchor)
		flow:SetGrowthDirection(state.growth[1], state.growth[2])
		-- CustomAuraContainerFlowLayoutMixin sizes elements from the group.
		function flow:GetElementSize(_, _, group) return group.elementWidth, group.elementHeight end
		local container = CreateFrame("Frame", nil, UIParent)
		for _, counts in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0, 0 } }) do
			local groups = {}
			for i, kind in ipairs({ "buffs", "debuffs" }) do
				local layout, elements = state.groups[kind].layout, {}
				for n = 1, counts[i] do elements[n] = CreateFrame("Button", nil, container) end
				groups[i] = { elements = elements, elementWidth = layout.elementWidth, elementHeight = layout.elementHeight,
					elementSpacing = layout.elementSpacing, lineSpacing = layout.lineSpacing }
			end
			flow:Apply(container, groups)
			-- The viewport's top is the extent's top minus one unit.
			local viewport = container:GetHeight() - 1
			assert.equals(counts[1] + counts[2] == 0 and 0 or bar.resolved.height + uf.resolved.spacing, viewport)
		end
	end)

	it("centres texts on the resizing bar and lets name icons follow them", function()
		local frame, uf, row = Member()
		local overlay = row:GetBar():GetTextParent()
		for _, text in pairs(row.texts) do
			assert.equals(overlay, text:GetFrame():GetParent())
			assert.is_true(Mock.HasLayoutAspect(text:GetFrame()))
		end
		assert.same({ "ALL", row:GetBar():GetStatusBar() }, overlay.__state.points[1])
		local name = uf:GetLeadingName()
		assert.is_not_nil(name)
		local anchor = name:GetFrame():GetAnchor("LEFT")
		assert.same({ "LEFT", overlay, "LEFT" }, { anchor[1], anchor[2], anchor[3] }, "vertically centred on the bar")
		-- Every icon that may sit before the name carries the aspect: the
		-- raid marker and all group status icons (role defaults there).
		assert.is_true(uf:IsNativeLayout())
		assert.is_true(Mock.HasLayoutAspect(uf:GetPart("raidTarget"):GetFrame()))
		local status = CG:GetGridButton(frame).status
		for key, host in pairs(status.hosts) do assert.is_true(Mock.HasLayoutAspect(host), key) end
		assert.is_false(Mock.HasLayoutAspect(status:GetFrame()))
		CG.Config:Set("indicators.role", true)
		CG.Config:SetStyle("member", "raidTarget.anchor", "NAME")
		for _, key in ipairs({ "leader", "ready", "death", "resurrection", "summon" }) do
			CG.Config:Set("indicators." .. key, true)
			CG.Config:Set("indicators." .. key .. "Position", "NAME")
		end
		status:ShowSample(2, true)
		assert.has_no_error(function() uf:GetDecorations():Reflow() end)
		assert.equals(name:GetFrame(), status.hosts.role:GetAnchor("RIGHT")[2])
		-- Standalone frames' own icons carry it too.
		for _, key in ipairs({ "raidTarget", "pvp", "classification", "readyCheckIcon" }) do
			assert.is_true(Mock.HasLayoutAspect(UF.Units.frames.player.uf:GetPart(key):GetFrame()), key)
		end
		-- A castbar over health follows the bar the collapsing aura bar resizes.
		CG.Config:SetStyle("member", "castbar.enabled", true)
		assert.has_no_error(function() CG.Config:SetStyle("member", "castbar.placement", "health") end)
		assert.same({ "ALL", Root(row) }, uf:GetPart("castbar"):GetFrame().__state.points[1])
		local castbar = uf:GetPart("castbar")
		assert.is_true(castbar.iconFrame:IsShown())
		assert.equals(2, #castbar.iconFrame.__state.points)
		-- The mock enforces the client's rule for anything else.
		assert.has_error(function()
			CreateFrame("Frame", nil, UIParent):SetPoint("RIGHT", name:GetFrame(), "LEFT")
		end)
		assert.has_error(function()
			CreateFrame("Frame", nil, UIParent):SetPoint("TOP", uf:GetPart("auraBar"):GetViewport(), "BOTTOM")
		end)
		assert.has_error(function() CreateFrame("Frame", nil, UIParent):SetAllPoints(Root(row)) end)
	end)

	it("sizes segments and border from plain layout and never reads restricted geometry", function()
		local _, uf, row, bar = Member()
		local inner = row:GetBar()
		assert.is_nil(inner.bar:GetScript("OnSizeChanged"))
		local restricted = { Root(row), bar:GetViewport(), bar.presence }
		for _, frame in ipairs(restricted) do
			Mock.SetEngineSize(frame, Mock.Secret(150), Mock.Secret(47))
			frame.GetWidth = function() error("restricted width read") end
			frame.GetHeight = function() error("restricted height read") end
			frame.GetSize = function() error("restricted size read") end
			frame.GetRect = function() error("restricted rect read") end
		end
		CG.Config:SetStyle("member", "health.bar.border.enabled", true)
		CG.Config:SetStyle("member", "health.bar.border.padding", 2)
		CG.Config:SetStyle("member", "auraBar.height", 14)
		CG.Config:SetStyle("member", "auraBar.position", "top")
		CG.Config:SetStyle("member", "auraBar.position", "bottom")
		local item
		for _, entry in ipairs(uf.layout.rows) do if entry.key == "health" then item = entry end end
		local width = uf.layout.width - item.left - item.right
		assert.equals(width - 4, inner:GetSegmentBar("absorb"):GetWidth())
		assert.is_not_nil(Root(row):GetBackdrop())
		-- Native layout passes cannot run addon size scripts; Lua size reads
		-- of the StatusBar (oUF) see the plain known size.
		Mock.SetEngineSize(inner.bar, Mock.Secret(10), Mock.Secret(10))
		assert.equals(width - 4, inner:GetSegmentBar("absorb"):GetWidth())
		assert.equals(width - 4, inner.bar:GetWidth())
		assert.equals(item.height - 4, inner.bar:GetHeight())
		assert.same({ width - 4, item.height - 4 }, { inner.bar:GetSize() })
		Mock.inCombat, Mock.aurasSecret = true, true
		Mock.FireEvent("UNIT_AURA", "party1")
		Mock.inCombat, Mock.aurasSecret = false, false
	end)

	it("runs oUF's real health element while the bar's engine geometry is secret", function()
		local frame, _, row = Member()
		local inner = row:GetBar()
		Mock.SetEngineSize(inner.bar, Mock.Secret(150), Mock.Secret(47))
		inner.bar.__strict = true
		for _, seg in ipairs(inner.segments) do seg.bar.__strict = true end
		CreateUnitHealPredictionCalculator = function()
			return {
				SetDamageAbsorbClampMode = function() end,
				SetMaximumHealthMode = function() end,
				ResetPredictedValues = function() end,
				GetMaximumHealth = function() return Secret(1200) end,
				GetCurrentHealth = function() return Secret(1000) end,
				GetIncomingHeals = function() return Secret(0) end,
				GetHealAbsorbs = function() return Secret(0) end,
				GetDamageAbsorbs = function() return Secret(200) end,
			}
		end
		UnitGetDetailedHealPrediction = function() end
		UnitClassBase = function() return "PALADIN" end
		UnitIsConnected = function() return true end
		UF.oUF.Private = { GameVersion = { Forever = true } }
		assert(loadfile("UnitFrames/Libs/oUF/elements/health.lua"))("UnitFrames", UF)
		local element = UF.oUF.elements.Health
		frame.__unit = "player"
		element.enable(frame, "player")
		assert.has_no_error(function() element.update(frame, "UNIT_HEALTH", "player") end)
		assert.equals(200, frame.Health.DamageAbsorb:GetValue().secretValue)
		assert.equals(inner.bar:GetWidth(), frame.Health.DamageAbsorb:GetWidth())
		element.disable(frame)
	end)

	it("grows the viewport down from the top when the row sits above health", function()
		local _, uf, row, bar = Member()
		CG.Config:SetStyle("member", "auraBar.position", "top")
		local viewport, presence = bar:GetViewport(), bar.presence
		assert.equals("auraBar", uf.layout.rows[1].key)
		assert.same({ "BOTTOMRIGHT", row:GetFrame(), "BOTTOMRIGHT", 0, 0 }, Root(row):GetAnchor("BOTTOMRIGHT"))
		assert.same({ "TOPLEFT", viewport, "BOTTOMLEFT", 0, 0 }, Root(row):GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOMLEFT", presence, "BOTTOMLEFT", 0, 1 }, viewport:GetAnchor("BOTTOMLEFT"))
		assert.same({ "TOPRIGHT", bar:GetFrame(), "TOPRIGHT", 0, 0 }, viewport:GetAnchor("TOPRIGHT"))
		assert.same({ "TOPLEFT", bar:GetFrame(), "TOPLEFT", 0, 0 }, presence:GetAnchor("TOPLEFT"))
		assert.equals("TOPLEFT", presence.__state.flowAnchor)
		assert.same({ AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down }, presence.__state.growth)
	end)

	it("gives the space back to the row when collapsing is off, the row is hidden or health is off", function()
		local _, _, row, bar = Member()
		local function Fixed()
			assert.same({ "ALL", row:GetFrame() }, Root(row).__state.points[1])
			assert.is_false(bar.presence:IsEnabled())
		end
		CG.Config:SetStyle("member", "auraBar.collapse", false)
		Fixed()
		assert.same({ "ALL", bar:GetFrame() }, bar:GetViewport().__state.points[1])
		CG.Config:SetStyle("member", "auraBar.collapse", nil)
		assert.is_true(bar.presence:IsEnabled())
		CG.Config:SetStyle("member", "auraBar.enabled", false)
		Fixed()
		CG.Config:SetStyle("member", "auraBar.enabled", true)
		CG.Config:SetStyle("member", "health.enabled", false)
		Fixed()
		CG.Config:SetStyle("member", "health.enabled", true)
		assert.same({ "BOTTOMRIGHT", bar:GetViewport(), "TOPRIGHT", 0, 0 }, Root(row):GetAnchor("BOTTOMRIGHT"))
		assert.is_true(bar.presence:IsEnabled())
	end)

	it("previews the collapse from plain samples and returns to native presence for live units", function()
		local uf = UF.Units:CreateFromDefinition(CG.definitions.member, UIParent, { auraBar = { enabled = true } })
		local row, bar = uf:GetRow("health"), uf:GetPart("auraBar")
		local extent = bar.resolved.height + uf.resolved.spacing
		UF.Units:ShowSample(uf, UF.Units.SAMPLE)
		local viewport = bar:GetViewport()
		assert.is_false(bar.presence:IsEnabled())
		assert.same({ "TOPRIGHT", bar:GetFrame(), "BOTTOMRIGHT", 0, extent }, viewport:GetAnchor("TOPRIGHT"))
		assert.same({ "BOTTOMRIGHT", viewport, "TOPRIGHT", 0, 0 }, Root(row):GetAnchor("BOTTOMRIGHT"))
		bar:ShowSample({ buffs = {}, debuffs = {} })
		assert.same({ "TOPRIGHT", bar:GetFrame(), "BOTTOMRIGHT", 0, 0 }, viewport:GetAnchor("TOPRIGHT"))
		bar:ShowSample({ buffs = {}, debuffs = { UF.Units.SAMPLE.debuffs[1] } })
		assert.same({ "TOPRIGHT", bar:GetFrame(), "BOTTOMRIGHT", 0, extent }, viewport:GetAnchor("TOPRIGHT"))
		bar:SetUnit("player")
		assert.is_true(bar.presence:IsEnabled())
		assert.equals("player", bar.presence:GetUnit())
		assert.same({ "TOPLEFT", bar.presence, "TOPLEFT", 0, -1 }, viewport:GetAnchor("TOPLEFT"))
		-- Applying the same style twice is stable.
		uf:Apply(uf.config)
		uf:Apply(uf.config)
		assert.same({ "BOTTOMRIGHT", viewport, "TOPRIGHT", 0, 0 }, Root(row):GetAnchor("BOTTOMRIGHT"))
		uf:Release()
		assert.is_false(bar.presence:IsEnabled())
		assert.is_false(bar:GetContainer("buffs"):IsEnabled())
	end)

	it("shows collapsed and expanded members in the panel preview", function()
		CG.Config:SetStyle("member", "auraBar.enabled", true)
		local preview = CG.Preview:New(UIParent)
		preview:ShowData({ source = "static", count = 5 })
		local tops = {}
		for i = 1, 5 do
			local bar = preview.cells[i].member:GetPart("auraBar")
			tops[i] = bar:GetViewport():GetAnchor("TOPRIGHT")[5]
		end
		local extent = preview.cells[1].member:GetPart("auraBar").resolved.height + preview.cells[1].member.resolved.spacing
		local collapsed, expanded = 0, 0
		for _, top in ipairs(tops) do
			if top == 0 then collapsed = collapsed + 1 elseif top == extent then expanded = expanded + 1 end
		end
		assert.is_true(collapsed > 0, "some sample members carry no icon")
		assert.equals(5, collapsed + expanded)
		preview:Release()
	end)
end)
