local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Presentation work transactions", function()
	local UF
	before_each(function() UF = Helpers.LoadAddon(true, true) end)

	it("batches nested decoration requests while preserving results and synchronous event reflows", function()
		local stack = UF.Units.frames.player.uf:GetDecorations()
		UF.Perf.counters = {}
		local result = stack:Batch(function()
			stack:Reflow()
			stack:Batch(function() stack:Reflow(); stack:Reflow() end)
			assert.is_nil(UF.Perf.counters.decorationReflow)
			return "complete"
		end)
		assert.equals("complete", result)
		assert.equals(1, UF.Perf.counters.decorationReflow)
		stack:Reflow()
		assert.equals(2, UF.Perf.counters.decorationReflow)
		UF.Perf.counters = nil
	end)

	it("unwinds failed batches and cancels pending layout when released", function()
		local stack = UF.DecorationStack:New()
		local ok, err = pcall(stack.Batch, stack, function()
			stack:Reflow()
			stack:Batch(function() stack:Reflow(); error("layout failure", 0) end)
		end)
		assert.is_false(ok)
		assert.equals("layout failure", err)
		assert.equals(0, stack.batchDepth)
		assert.is_nil(stack.pendingReflow)
		UF.Perf.counters = {}
		stack:Reflow()
		assert.equals(1, UF.Perf.counters.decorationReflow)
		stack:Batch(function() stack:Reflow(); stack:Release() end)
		assert.equals(1, UF.Perf.counters.decorationReflow)
		UF.Perf.counters = nil
	end)

	it("retains unchanged member records without suppressing visibility or changed geometry", function()
		local frame = UF.Units.frames.player
		local stack = frame.uf:GetDecorations()
		local host = CreateFrame("Frame", nil, frame)
		local icon = host:CreateTexture(nil, "OVERLAY")
		local member = { host = host, widgets = { icon }, enabled = true, anchor = "TOP", size = 12, gap = 2, order = 1 }
		stack:Set("extra", member)
		stack:Reflow()
		local copy = {}
		for key, value in pairs(member) do copy[key] = value end
		copy.widgets = { icon }
		stack:Set("extra", copy)
		assert.equals(member, stack.members.extra)
		local point, writes = host.SetPoint, 0
		host.SetPoint = function(self, ...) writes = writes + 1; return point(self, ...) end
		stack:Reflow()
		assert.equals(0, writes)
		copy.x = 5
		stack:Set("extra", copy)
		stack:Reflow()
		assert.equals(1, writes)
		Mock.RunUntainted(icon.SetShown, icon, Mock.Secret(false))
		assert.has_no_error(function() stack:Reflow() end)
	end)

	it("reuses aura artwork within a transaction without mutating settings or retaining stale theme values", function()
		local config = { durationPosition = "below", border = { padding = 3 } }
		local before = UF.Util.Copy(config)
		local first, second
		local spec = { schemaOwner = {} }
		UF.Perf.counters = {}
		UF.Schema.Shared(function()
			first = UF.Components.AuraBar:New(UIParent, config, spec)
			second = UF.Components.AuraBar:New(UIParent, config, spec)
		end)
		assert.equals(1, UF.Perf.counters.auraArtConfigBuild)
		assert.equals(first.artConfig, second.artConfig)
		assert.equals("BOTTOM", first.artConfig.durationPosition)
		assert.equals("below", first.resolved.durationPosition)
		assert.same(before, config)
		UF.Perf.counters = nil
		config.border.padding = 4
		first:Apply(config)
		assert.equals(4, first.artConfig.border.padding)
		assert.equals(3, second.artConfig.border.padding)
		UF.Config:SetThemeValue("font", "Arial Narrow")
		assert.equals("Arial Narrow", first.artConfig.font)
		assert.equals("Arial Narrow", second.artConfig.font)
		first:Release()
		second:Release()
	end)

	it("skips unchanged glow geometry but observes mutated settings and known bounds", function()
		local glow = UF.Glow.Create(UIParent)
		local function Size() return math.floor(glow.Halo:GetScale() * glow.Halo:GetTextureSliceMargins() + 0.5) end
		local cfg = { size = 16, offset = 8, opacity = 1 }
		UF.Glow.Apply(glow, cfg, 30, 30)
		local point, writes = glow.Halo.SetPoint, 0
		glow.Halo.SetPoint = function(self, ...) writes = writes + 1; return point(self, ...) end
		UF.Glow.SetColor(glow, 0, 1, 0, 1)
		UF.Glow.Apply(glow, cfg, 30, 30)
		assert.equals(0, writes)
		cfg.opacity = 0.5
		UF.Glow.Apply(glow, cfg, 30, 30)
		assert.equals(0.5, glow:GetAlpha())
		assert.equals(2, writes)
		UF.Glow.Apply(glow, cfg, 6, 6)
		assert.equals(11, Size())
		cfg.offset = 4
		UF.Glow.Apply(glow, cfg, 6, 6)
		assert.equals(7, Size())
	end)

	it("coalesces live refresh layout without suppressing data updates or combat event layout", function()
		local frame = UF.Units.frames.player
		UF.Perf.counters = {}
		UF.Units:Refresh("player")
		assert.equals(1, UF.Perf.counters.decorationReflow)
		assert.equals(1, UF.Perf.counters.updateAllElements)
		assert.equals(1, UF.Perf.counters.unitBind)
		Mock.inCombat = true
		frame.uf:GetPart("raidTarget"):GetWidget():Show()
		frame.uf:GetPart("raidTarget"):Reflow()
		assert.equals(2, UF.Perf.counters.decorationReflow)
		assert.equals(0, frame.uf:GetDecorations().batchDepth)
		Mock.inCombat = false
		UF.Perf.counters = nil
	end)
end)
