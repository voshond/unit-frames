local Helpers = require("helpers")
local Mock = Helpers.Mock

local SPELLS = {
	[1] = { "Corruption", "Corrupts the target, causing 40 Shadow damage over 12 sec." },
	[2] = { "Immolate", "Burns the enemy for 11 Fire damage and then an additional 30 Fire damage over 15 sec." },
}

describe("Pending DoT damage on health bars #dots", function()
	local ns, element

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		element = ns.oUF.elements.UF_PendingDamage
		for id, spell in pairs(SPELLS) do Mock.spells[id] = { name = spell[1], description = spell[2] } end
		ns.DotCatalog.spells[1] = { family = 1, school = 32, basePoints = 10, durationMs = 12000,
			maxDurationMs = 12000, durationPerResourceMs = 0, pointsPerResource = 0, periodMs = 3000 }
		ns.DotCatalog.spells[2] = { family = 2, school = 4, basePoints = 6, durationMs = 15000,
			maxDurationMs = 15000, durationPerResourceMs = 0, pointsPerResource = 0, periodMs = 3000 }
		Mock.guids.target = "mob"
	end)

	local function LastCall(obj, name)
		for i = #obj.__calls, 1, -1 do
			if obj.__calls[i][1] == name then return obj.__calls[i][2] end
		end
	end
	local function Bar(unit) return ns.Units.frames[unit].uf:GetRow("health"):GetBar() end
	local function Pending(unit) return Bar(unit).pendingDamage end
	local function Set(unit, key, value) ns.Config:SetUnitValue(unit, "health.bar.pendingDamage." .. key, value) end
	local function Values(pending)
		local values = {}
		for i, segment in ipairs(pending.segments) do values[i] = segment.bar.__state.value end
		return values
	end
	local function Cast(id)
		Mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "cast-" .. id, id)
		Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. id, id)
	end
	local function Sample(unit, values)
		ns.Units:ShowSample(ns.Units.frames[unit].uf, ns.Util.Merge(ns.Units:GetSample(unit), values))
	end

	it("is offered on health bars, on for target and focus only, and builds nothing until enabled", function()
		assert.is_nil(ns.Schema.Find(ns.Units.frames.target.uf:GetRow("power"):GetBar():GetSchema(), "pendingDamage"))
		for _, unit in ipairs({ "player", "pet", "targettarget", "focustarget" }) do
			assert.is_nil(Bar(unit):GetPendingDamage(), unit)
			assert.is_nil(Pending(unit).segments, unit)
			assert.is_false(Pending(unit).holder:IsShown(), unit)
		end
		for _, unit in ipairs({ "target", "focus" }) do
			assert.equals(Pending(unit), Bar(unit):GetPendingDamage(), unit)
			assert.equals(ns.PendingDamage.MAX_SEGMENTS, #Pending(unit).segments)
		end
		assert.is_nil(ns.Config:GetUnitConfig("target").health)
	end)

	it("binds its element and feeds health only where enabled, and unbinds when switched off", function()
		local target, player = ns.Units.frames.target, ns.Units.frames.player
		assert.equals(Pending("target"), target.UF_PendingDamage)
		assert.is_true(target:IsElementEnabled("UF_PendingDamage"))
		assert.is_nil(rawget(player, "UF_PendingDamage"))
		assert.equals(Pending("target"), target.Health.ufHealthHooks.pending)
		assert.is_nil(rawget(player.Health, "PostUpdate"))

		Set("target", "enabled", false)
		assert.is_nil(rawget(target, "UF_PendingDamage"))
		assert.is_false(target:IsElementEnabled("UF_PendingDamage"))
		assert.is_nil(target.Health.ufHealthHooks.pending)
		assert.is_false(Pending("target").holder:IsShown())
		Set("player", "enabled", true)
		assert.equals(Pending("player"), player.UF_PendingDamage)
		assert.equals("function", type(player.Health.PostUpdate))
	end)

	it("draws each tracked DoT on the frame's mob, chained back from the end of the health fill", function()
		local frame, pending = ns.Units.frames.target, Pending("target")
		assert.is_true(element.enable(frame, "target"))
		assert.is_true(ns.DotTracker:IsActive())
		ns.DotTracker.ticks[1], ns.DotTracker.ticks[2] = 10, 6
		Cast(1)
		Mock.time = Mock.time + 0.5
		Cast(2)
		assert.same({ 40, 30, 0, 0, 0, 0 }, Values(pending))

		local fill, segments = Bar("target").bar:GetStatusBarTexture(), pending.segments
		assert.equals(fill, segments[1].bar:GetAnchor("TOPRIGHT")[2])
		assert.equals("TOPRIGHT", segments[1].bar:GetAnchor("TOPRIGHT")[3])
		assert.equals(segments[1].bar:GetStatusBarTexture(), segments[2].bar:GetAnchor("TOPRIGHT")[2])
		assert.equals("TOPLEFT", segments[2].bar:GetAnchor("TOPRIGHT")[3])
		assert.is_true(segments[1].bar.__state.reverseFill)
		assert.same({ 0.7, 0.35, 1, 0.75 }, segments[1].bar.__state.color)
		assert.same({ 1, 0.55, 0.15, 0.75 }, segments[2].bar.__state.color)
		assert.is_true(segments[1].divider:IsShown())
		assert.is_false(segments[2].divider:IsShown())
		assert.is_true(pending.edge:IsShown())
		assert.equals(segments[2].bar:GetStatusBarTexture(), pending.edge:GetAnchor("TOPLEFT")[2])

		Mock.guids.target = "other"
		element.update(frame, "UnitFramesRefresh")
		assert.same({ 0, 0, 0, 0, 0, 0 }, Values(pending))
		assert.is_false(pending.edge:IsShown())
		Mock.guids.target = "mob"
		element.update(frame, "UnitFramesRefresh")
		element.disable(frame)
		assert.is_false(ns.DotTracker:IsActive())
		assert.same({ 0, 0, 0, 0, 0, 0 }, Values(pending))
		Cast(1)
		assert.same({ 0, 0, 0, 0, 0, 0 }, Values(pending), "no longer listening")
	end)

	it("takes the secret health scale and current health from the health update without reading them", function()
		local frame, pending = ns.Units.frames.target, Pending("target")
		element.enable(frame, "target")
		ns.DotTracker.ticks[1] = 10
		Cast(1)
		local current, max = Mock.Secret(500), Mock.Secret(1000)
		frame.Health:PostUpdate("target", current, max)
		for _, segment in ipairs(pending.segments) do assert.equals(max, segment.bar.__state.max) end
		assert.equals(current, pending.icon.probe.__state.max)
		assert.equals(current, pending.tint.probe.__state.max)
		assert.equals(40, pending.icon.probe.__state.value)
		assert.is_true(pending.icon.gate:IsShown())
		assert.is_false(pending.tint.gate:IsShown(), "the tint is opt-in")
		element.disable(frame)
		assert.is_false(pending.icon.gate:IsShown())
	end)

	it("only lets the kill icon into view through a clipped gate at the end of a long probe", function()
		local pending = Pending("target")
		local icon = pending.icon
		assert.is_true(LastCall(icon.gate, "SetClipsChildren"))
		assert.equals(50000, icon.probe.__state.width)
		assert.equals(icon.gate, icon.probe:GetAnchor("TOPRIGHT")[2])
		assert.equals(icon.probe:GetStatusBarTexture(), icon.texture:GetAnchor("TOPRIGHT")[2])
		assert.equals("Interface\\TargetingFrame\\UI-TargetingFrame-Skull", icon.texture:GetTexture())
		assert.is_nil(icon.texture.__state.raidTargetIndex)
		assert.equals(16, icon.texture.__state.width)
		Set("target", "lethalIconSize", 24)
		Set("target", "lethalIconPosition", "LEFT")
		local uf = ns.Units.frames.target.uf
		assert.equals(24, Pending("target").iconHost.__state.width)
		assert.equals(uf:GetFrame(), Pending("target").iconHost:GetAnchor("CENTER")[2])
		assert.equals("LEFT", Pending("target").iconHost:GetAnchor("CENTER")[3])
		assert.equals(Pending("target").iconHost, uf:GetDecorations().members.pendingDamage.host)
		Set("target", "lethalTint", true)
		Sample("target", { health = 300, pendingDamage = { { name = "Corruption", school = 32, damage = 40 } } })
		assert.is_true(Pending("target").tint.gate:IsShown())
		assert.same({ 1, 0.1, 0.1, 0.35 }, Pending("target").tint.texture.__state.vertexColor)
	end)

	it("shows sample DoTs in one colour or per spell, with the sample health as the lethal scale", function()
		Sample("target", { health = 15600, pendingDamage = {
			{ name = "Corruption", school = 32, damage = 3000 }, { name = "Immolate", school = 4, damage = 2000 } } })
		local pending = Pending("target")
		assert.same({ 3000, 2000, 0, 0, 0, 0 }, Values(pending))
		assert.equals(15600, pending.icon.probe.__state.max)
		assert.equals(5000, pending.icon.probe.__state.value)
		assert.equals(24000, pending.segments[1].bar.__state.max)

		Set("target", "colorMode", "single")
		pending = Pending("target")
		assert.same({ 5000, 0, 0, 0, 0, 0 }, Values(pending))
		assert.same({ 0.7, 0.3, 1, 0.75 }, pending.segments[1].bar.__state.color)
		assert.is_false(pending.segments[1].divider:IsShown())

		Set("target", "colorMode", "spell")
		local first = ns.Util.Copy(Pending("target").segments[1].bar.__state.color)
		Sample("target", { pendingDamage = { { name = "Corruption", school = 32, damage = 10 } } })
		assert.same(first, Pending("target").segments[1].bar.__state.color, "a spell keeps its colour")
		Sample("target", { pendingDamage = nil })
		assert.same({ 0, 0, 0, 0, 0, 0 }, Values(Pending("target")))
		assert.is_false(Pending("target").icon.gate:IsShown())
	end)

	it("groups the kill icon with decorations and removes its slot when disabled or empty", function()
		local uf, pending = ns.Units.frames.target.uf, Pending("target")
		ns.Config:SetUnitValue("target", "raidTarget.anchor", "CENTER")
		ns.Config:SetUnitValue("target", "raidTarget.size", 16)
		Sample("target", { pendingDamage = { { name = "Corruption", school = 32, damage = 3000 } } })
		uf:GetPart("raidTarget"):SetIndex(1)
		local stack = uf:GetDecorations()
		assert.equals(2, #stack.groups.CENTER)
		assert.equals("raidTarget", stack.groups.CENTER[1].key)
		assert.equals("pendingDamage", stack.groups.CENTER[2].key)
		Set("target", "lethalIconOrder", 1)
		ns.Config:SetUnitValue("target", "raidTarget.order", 2)
		assert.equals("pendingDamage", stack.groups.CENTER[1].key)
		Set("target", "lethalIconOffsetX", 7)
		assert.equals(7, stack.members.pendingDamage.x)
		Set("target", "lethalIcon", false)
		uf:GetPart("raidTarget"):SetIndex(1)
		assert.equals(1, #stack.groups.CENTER)
		assert.is_false(pending.iconHost:IsShown())
		Set("target", "lethalIcon", true)
		uf:GetPart("raidTarget"):SetIndex(1)
		assert.equals(2, #stack.groups.CENTER)
		Sample("target", { pendingDamage = {} })
		uf:GetPart("raidTarget"):SetIndex(1)
		assert.equals(1, #stack.groups.CENTER)
		Set("target", "enabled", false)
		assert.is_false(pending.iconHost:IsShown())
	end)

	it("hides with its health row, fits portrait anchors and releases its decoration host", function()
		local uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, {})
		local pending = uf:GetRow("health"):GetBar():GetPendingDamage()
		ns.Units:ShowSample(uf, ns.Units:GetSample("target"))
		uf:Apply({ health = { enabled = false } })
		assert.is_false(pending.iconHost:IsShown())
		uf:Apply({ portrait = { enabled = true, size = 12 },
			health = { bar = { pendingDamage = { lethalIconPosition = "PORTRAIT_CENTER", lethalIconSize = 32 } } } })
		local portrait = uf:GetLayoutContext().portrait
		assert.equals(math.min(32, portrait.width, portrait.height), pending.icon.texture.__state.width)
		assert.equals(portrait.frame, pending.iconHost:GetAnchor("CENTER")[2])
		uf:Release()
		assert.is_false(pending.iconHost:IsShown())
		assert.is_nil(uf:GetDecorations().members.pendingDamage)
	end)

	it("hatches each DoT with a repeating stripes texture over its fill, in any toggle order", function()
		local segment = Pending("target").segments[2]
		local pattern = segment.pattern
		assert.equals("Interface\\AddOns\\UnitFrames\\Media\\Stripes", pattern:GetTexture())
		assert.is_true(LastCall(pattern, "SetHorizTile"))
		assert.is_true(LastCall(pattern, "SetVertTile"))
		assert.equals(segment.bar:GetStatusBarTexture(), pattern:GetAnchor("TOPLEFT")[2])
		assert.equals(segment.bar:GetStatusBarTexture(), pattern:GetAnchor("BOTTOMRIGHT")[2])
		assert.is_true(pattern:IsShown())
		assert.same({ 0, 0, 0, 0.35 }, pattern.__state.vertexColor)
		Set("target", "pattern", "none")
		assert.is_false(Pending("target").segments[2].pattern:IsShown())
		Set("target", "patternColor", { 1, 1, 1 })
		Set("target", "patternOpacity", 0.2)
		Set("target", "pattern", "stripes")
		pattern = Pending("target").segments[2].pattern
		assert.is_true(pattern:IsShown())
		assert.same({ 1, 1, 1, 0.2 }, pattern.__state.vertexColor)
		Set("target", "patternOpacity", 0)
		assert.same({ 1, 1, 1, 0 }, Pending("target").segments[2].pattern.__state.vertexColor)
	end)

	it("folds DoTs beyond the last segment into it", function()
		local entries, expected = {}, 0
		for i = 1, 8 do
			entries[i] = { name = "Dot" .. i, school = 32, damage = i }
			if i >= 6 then expected = expected + i end
		end
		Sample("target", { pendingDamage = entries })
		assert.same({ 1, 2, 3, 4, 5, expected }, Values(Pending("target")))
	end)

	it("polls the tracker for an explicit unit in previews and honours the wait mode", function()
		local uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent,
			{ health = { bar = { pendingDamage = { waitMode = "always" } } } })
		local pending = uf:GetRow("health"):GetBar():GetPendingDamage()
		ns.Units:ShowLive(uf, "target", {})
		assert.same({ 0, 0, 0, 0, 0, 0 }, Values(pending), "tracker idle")
		ns.DotTracker:Acquire("spec")
		ns.DotTracker.ticks[1] = 10
		Cast(1)
		ns.Units:ShowLive(uf, "target", {})
		assert.same({ 0, 0, 0, 0, 0, 0 }, Values(pending), "waits for a real tick")
		uf:Apply({ health = { bar = { pendingDamage = { waitMode = "off" } } } })
		ns.Units:ShowLive(uf, "target", {})
		assert.same({ 40, 0, 0, 0, 0, 0 }, Values(pending))
		assert.is_true(Mock.IsSecret(pending.icon.probe.__state.max), "live current health from the calculator")
		ns.DotTracker:Release("spec")
	end)

	it("follows vertical and reversed bars", function()
		ns.Config:SetUnitValue("target", "health.bar.orientation", "VERTICAL")
		ns.Config:SetUnitValue("target", "health.bar.reverseFill", true)
		local pending = Pending("target")
		local fill = Bar("target").bar:GetStatusBarTexture()
		assert.equals(fill, pending.segments[1].bar:GetAnchor("BOTTOMLEFT")[2])
		assert.equals("BOTTOMLEFT", pending.segments[1].bar:GetAnchor("BOTTOMLEFT")[3])
		assert.equals("TOPLEFT", pending.segments[2].bar:GetAnchor("BOTTOMLEFT")[3])
		assert.is_false(pending.segments[1].bar.__state.reverseFill)
		assert.equals("VERTICAL", pending.segments[1].bar:GetOrientation())
	end)
end)

describe("Pending DoT damage in the Workbench #dots", function()
	it("has its own section under Health & shields and a sample in the unit preview", function()
		local _, wb = Helpers.LoadWorkbench()
		wb:Open("unit.target")
		wb:SelectFeaturePage("@health", "style:dots")
		local found, stripeOpacity, iconOrder
		for _, row in ipairs(wb.inspector.page.rows) do
			if row.path == "health.bar.pendingDamage.enabled" then found = row end
			if row.path == "health.bar.pendingDamage.patternOpacity" then stripeOpacity = row end
			if row.path == "health.bar.pendingDamage.lethalIconOrder" then iconOrder = row end
		end
		assert.is_not_nil(found)
		assert.is_not_nil(stripeOpacity)
		assert.is_not_nil(iconOrder)
		local pending = wb.handle.parts.uf:GetRow("health"):GetBar():GetPendingDamage()
		local total = 0
		for _, segment in ipairs(pending.segments) do total = total + segment.bar.__state.value end
		assert.equals(24000 * 0.3, math.floor(total + 0.5))
		wb.dataTarget.set("dots", 80)
		assert.equals(24000 * 0.65, pending.icon.probe.__state.max)
		assert.equals(24000 * 0.8, pending.icon.probe.__state.value)
	end)
end)
