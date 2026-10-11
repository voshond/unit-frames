local Helpers = require("helpers")

describe("Health shields", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
	end)

	local function Bar(unit)
		return ns.Units.frames[unit or "player"].uf:GetRow("health"):GetBar()
	end

	it("enables full-health shield overlays on every unit without changing saved overrides", function()
		for _, unit in ipairs(ns.Units.order) do
			local bar = Bar(unit)
			assert.is_true(bar.resolved.segments.absorb.enabled)
			assert.equals("overlay", bar.resolved.segments.absorb.placement)
			assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, ns.Units.frames[unit].Health.damageAbsorbClampMode)
			assert.is_nil(ns.Config:GetUnitConfig(unit).health)
		end
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", false)
		assert.is_nil(rawget(ns.Units.frames.player.Health, "DamageAbsorb"))
		assert.is_false(Bar().segmentsByKey.absorb.bar:IsShown())
	end)

	it("anchors overlays inside the full bar for all orientations without reading secret health", function()
		local bar = Bar()
		local max, shield = Secret(1000), Secret(200)
		for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
			for _, reverse in ipairs({ false, true }) do
				bar:Apply({ orientation = orientation, reverseFill = reverse })
				bar.bar:SetSize(200, 100)
				bar:SetRange(0, max)
				bar:SetValue(max)
				bar:SetSegmentValue("absorb", shield)
				local sb = bar:GetSegmentBar("absorb")
				for _, pair in ipairs(ns.Components.Bar.LAYOUT[orientation][reverse].inset) do
					assert.same({ pair[1], bar.bar, pair[2], 0, 0 }, sb:GetAnchor(pair[1]))
				end
				assert.equals(not reverse, sb.__state.reverseFill)
				assert.equals(orientation, sb.__state.orientation)
				assert.equals(shield, sb:GetValue())
				local _, segMax = sb:GetMinMaxValues()
				assert.equals(max, segMax)
				assert.equals(orientation == "HORIZONTAL" and 200 or 100,
					orientation == "HORIZONTAL" and sb:GetWidth() or sb:GetHeight())
			end
		end
	end)

	it("appends shields directly to health, independently of incoming heals", function()
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "append")
		local bar, sb = Bar(), Bar():GetSegmentBar("absorb")
		assert.same({ "TOPLEFT", bar.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0 }, sb:GetAnchor("TOPLEFT"))
		assert.is_false(sb.__state.reverseFill)
		assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, ns.Units.frames.player.Health.damageAbsorbClampMode)
		assert.equals(Enum.UnitMaximumHealthMode.WithAbsorbs, ns.Units.frames.player.Health.maximumHealthClampMode)
		ns.Config:SetUnitValue("player", "health.bar.segments.heal.enabled", false)
		assert.same({ "TOPLEFT", bar.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0 }, sb:GetAnchor("TOPLEFT"))
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", nil)
		assert.same({ "TOPRIGHT", bar.bar, "TOPRIGHT", 0, 0 }, sb:GetAnchor("TOPRIGHT"))
	end)

	it("fits appended full-health shields for reversed and vertical bars on every unit", function()
		for _, unit in ipairs(ns.Units.order) do
			local frame, bar = ns.Units.frames[unit], Bar(unit)
			local sample = ns.Units:GetSample(unit)
			sample.health, sample.absorb, sample.showCast = sample.healthMax, sample.healthMax / 4, false
			ns.Config:SetUnitValue(unit, "health.bar.segments.absorb.placement", "append")
			for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
				for _, reverse in ipairs({ false, true }) do
					ns.Config:SetUnitValue(unit, "health.bar.orientation", orientation)
					ns.Config:SetUnitValue(unit, "health.bar.reverseFill", reverse)
					ns.Units:ShowSample(frame.uf, sample)
					local sb = bar:GetSegmentBar("absorb")
					local _, max = bar.bar:GetMinMaxValues()
					assert.equals(bar.bar:GetValue() + sb:GetValue(), max)
					assert.equals(reverse, sb.__state.reverseFill)
					for _, pair in ipairs(ns.Components.Bar.LAYOUT[orientation][reverse].append) do
						assert.same({ pair[1], bar.bar:GetStatusBarTexture(), pair[2], 0, 0 }, sb:GetAnchor(pair[1]))
					end
				end
			end
		end
	end)

	it("updates an existing calculator immediately when placement changes", function()
		local health, applied = ns.Units.frames.player.Health, {}
		health.values = {
			SetMaximumHealthMode = function(_, mode) applied[#applied + 1] = mode end,
			SetDamageAbsorbClampMode = function(_, mode) assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, mode) end,
		}
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "append")
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "overlay")
		assert.same({ Enum.UnitMaximumHealthMode.WithAbsorbs, Enum.UnitMaximumHealthMode.Default }, applied)
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "append")
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", false)
		assert.equals(Enum.UnitMaximumHealthMode.Default, applied[#applied])
	end)

	it("copies shield placement and visibility independently to the other frames", function()
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "append")
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", false)
		for _, unit in ipairs({ "pet", "target", "targettarget", "focus", "focustarget" }) do
			ns.Units:CopyPlayerSettings(unit)
			assert.equals("append", Bar(unit).resolved.segments.absorb.placement)
			assert.is_false(Bar(unit).resolved.segments.absorb.enabled)
		end
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", true)
		assert.is_false(Bar("target").resolved.segments.absorb.enabled)
	end)

	it("previews shields at 100 percent health on standalone and unit health bars", function()
		local wb
		ns, wb = Helpers.LoadWorkbench()
		wb:Open()
		for _, id in ipairs({ "bar.health", "unit.player", "unit.pet", "unit.target", "unit.targettarget", "unit.focus", "unit.focustarget" }) do
			wb:Select(id)
			wb.dataTarget.set("health", 100)
			wb.dataTarget.set("absorb", 20)
			local row = wb.handle.parts.row or wb.handle.parts.uf:GetRow("health")
			local bar = row:GetBar()
			local _, max = bar.bar:GetMinMaxValues()
			assert.equals(max, bar.bar:GetValue())
			local sb = bar:GetSegmentBar("absorb")
			assert.equals(max * 0.2, sb:GetValue())
			assert.same({ "TOPRIGHT", bar.bar, "TOPRIGHT", 0, 0 }, sb:GetAnchor("TOPRIGHT"))
		end
	end)

	it("fits full health plus shields inside the preview and keeps health text unchanged", function()
		local wb
		ns, wb = Helpers.LoadWorkbench()
		wb:Open()
		for _, id in ipairs({ "bar.health", "unit.player", "unit.pet", "unit.target", "unit.targettarget", "unit.focus", "unit.focustarget" }) do
			wb:Select(id)
			wb.dataTarget.set("health", 100)
			wb.dataTarget.set("absorb", 20)
			local row = wb.handle.parts.row or wb.handle.parts.uf:GetRow("health")
			local text = row:GetText("right"):GetFrame():GetText()
			local path = id == "bar.health" and "row.bar" or "health.bar"
			wb.styleTarget.set(path .. ".segments.absorb.placement", "append")
			local bar, cur = row:GetBar(), row:GetBar().bar:GetValue()
			local _, max = bar.bar:GetMinMaxValues()
			assert.equals(cur * 1.2, max)
			assert.equals(cur * 0.2, bar:GetSegmentBar("absorb"):GetValue())
			assert.equals(0, bar:GetSegmentBar("heal"):GetValue())
			assert.equals(text, row:GetText("right"):GetFrame():GetText())
			assert.same({ "TOPLEFT", bar.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0 }, bar:GetSegmentBar("absorb"):GetAnchor("TOPLEFT"))
			wb.styleTarget.set(path .. ".segments.absorb.enabled", false)
			local _, unshieldedMax = bar.bar:GetMinMaxValues()
			assert.equals(cur, unshieldedMax)
		end
	end)

	it("uses a contrasting default shield tint without replacing custom colours", function()
		assert.same({ 0.2, 0.65, 1, 0.75 }, Bar():GetSegmentBar("absorb").__state.color)
		local custom = { 0.9, 0.3, 0.6, 0.8 }
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.color", custom)
		ns.Config:SetThemeValue("colors.absorb", { 0.1, 0.4, 0.9, 1 })
		assert.same(custom, Bar():GetSegmentBar("absorb").__state.color)
	end)

	it("uses a native combined scale in the standalone live preview without adding secrets", function()
		local wb
		ns, wb = Helpers.LoadWorkbench()
		wb:Open("bar.health")
		UnitHealth = function() return Secret(1000) end
		UnitHealthMax = function() return Secret(1000) end
		UnitGetTotalAbsorbs = function() return Secret(200) end
		wb.styleTarget.set("row.bar.segments.absorb.placement", "append")
		wb.dataTarget.set("source", "player")
		wb:OnUpdate(0.1)
		local bar = wb.handle.parts.row:GetBar()
		local _, max = bar.bar:GetMinMaxValues()
		assert.equals(1200, max.secretValue)
		assert.equals(1000, bar.bar:GetValue().secretValue)
		assert.equals(200, bar:GetSegmentBar("absorb"):GetValue().secretValue)
		wb.styleTarget.set("row.bar.segments.absorb.placement", "overlay")
		wb:OnUpdate(0.1)
		local _, normalMax = bar.bar:GetMinMaxValues()
		assert.equals(1000, normalMax.secretValue)
	end)

	-- Exercise the bundled oUF health element, not the binding-only stub.
	-- The C++ calculator is simulated according to Blizzard's documented clamp
	-- modes; its output is secret to catch arithmetic in addon/oUF Lua.
	local function NativeHealth()
		local frame, bar = ns.Units.frames.player, Bar()
		bar.bar.__strict = true
		for _, seg in ipairs(bar.segments) do seg.bar.__strict = true end
		local sample = { health = 1000, max = 1000, absorb = 200, heal = 0 }
		CreateUnitHealPredictionCalculator = function()
			return {
				SetDamageAbsorbClampMode = function(self, mode) self.mode = mode end,
				SetMaximumHealthMode = function(self, mode) self.maximumMode = mode end,
				ResetPredictedValues = function() end,
				GetMaximumHealth = function(self)
					return Secret(sample.max + (self.maximumMode == Enum.UnitMaximumHealthMode.WithAbsorbs and sample.absorb or 0))
				end,
				GetCurrentHealth = function() return Secret(sample.health) end,
				GetIncomingHeals = function() return Secret(sample.heal) end,
				GetHealAbsorbs = function() return Secret(0) end,
				GetDamageAbsorbs = function(self)
					local limit = self.mode == Enum.UnitDamageAbsorbClampMode.MaximumHealth
						and self:GetMaximumHealth().secretValue or math.max(0, sample.max - sample.health - sample.heal)
					return Secret(math.min(sample.absorb, limit))
				end,
			}
		end
		UnitGetDetailedHealPrediction = function() end
		UnitClassBase = function() return "PALADIN" end
		UnitIsConnected = function() return true end
		ns.oUF.Private = { GameVersion = { Forever = true } }
		assert(loadfile("UnitFrames/Libs/oUF/elements/health.lua"))("UnitFrames", ns)
		local element = ns.oUF.elements.Health
		local enable, disable = frame.EnableElement, frame.DisableElement
		function frame:EnableElement(name)
			enable(self, name)
			if name == "Health" then element.enable(self, self.__unit) end
		end
		function frame:DisableElement(name)
			if name == "Health" then element.disable(self) end
			disable(self, name)
		end
		frame:EnableElement("Health")
		return frame, element, sample
	end

	it("passes full-health and oversized shields through real oUF with the correct clamp mode", function()
		local frame, element, sample = NativeHealth()
		local function Update(expected)
			element.update(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
			assert.equals(expected, frame.Health.DamageAbsorb:GetValue().secretValue)
		end
		Update(200)
		sample.absorb = 1500
		Update(1000)
		sample.health, sample.absorb, sample.heal = 100, 400, 300
		Update(400)
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "append")
		sample.health = 1000
		Update(400)
		local _, max = frame.Health:GetMinMaxValues()
		assert.equals(1400, max.secretValue)
		assert.equals(1000, frame.Health:GetValue().secretValue)
		sample.health = 800
		Update(400) -- incoming heals must not hide shields
		sample.health, sample.absorb = 1000, 0
		Update(0)
		local _, noShieldMax = frame.Health:GetMinMaxValues()
		assert.equals(1000, noShieldMax.secretValue)
		sample.health, sample.absorb = 1000, 1500
		Update(1500)
		local _, largeMax = frame.Health:GetMinMaxValues()
		assert.equals(2500, largeMax.secretValue)
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "overlay")
		Update(1000)
	end)

	it("refreshes real oUF absorb subscriptions when shields are enabled after being off", function()
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", false)
		local frame, element = NativeHealth()
		assert.is_nil(frame.__state.events.UNIT_ABSORB_AMOUNT_CHANGED)
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", true)
		assert.is_true(frame.__state.events.UNIT_ABSORB_AMOUNT_CHANGED)
		element.update(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
		assert.equals(200, frame.Health.DamageAbsorb:GetValue().secretValue)
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.enabled", false)
		assert.is_nil(frame.__state.events.UNIT_ABSORB_AMOUNT_CHANGED)
		assert.is_false(Bar().segmentsByKey.absorb.bar:IsShown())
	end)
end)
