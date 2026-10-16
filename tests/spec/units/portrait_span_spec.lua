local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Portrait row spans", function()
	local ns, frame, uf, portrait
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "experience.enabled", true)
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		portrait = uf:GetPart("portrait"):GetFrame()
	end)

	local function Set(path, value)
		ns.Config:SetUnitValue("player", path, value)
	end

	it("preserves the all-rows default and sizes the portrait to a selected span", function()
		assert.equals(0, uf.resolved.portrait.rowSpan)
		assert.equals(69, portrait:GetHeight())
		Set("portrait.rowSpan", 2)
		assert.equals(39, portrait:GetHeight())
		assert.equals(39, portrait:GetWidth())
		assert.equals(271, frame:GetWidth())
		assert.equals(75, frame:GetHeight(), "row span does not alter the stack height")
		Set("portrait.rowSpan", 1)
		assert.equals(26, portrait:GetHeight())
		Set("portrait.rowSpan", 3)
		assert.equals(50, portrait:GetHeight())
		Set("portrait.rowSpan", 4)
		assert.equals(69, portrait:GetHeight())
		Set("portrait.rowSpan", nil)
		assert.equals(0, uf.resolved.portrait.rowSpan)
		assert.equals(69, portrait:GetHeight())
	end)

	it("reserves the portrait column only for covered rows on either side", function()
		Set("portrait.rowSpan", 2)
		for _, side in ipairs({ "LEFT", "RIGHT" }) do
			Set("portrait.position", side)
			local left = side == "LEFT" and 44 or 3
			local right = side == "RIGHT" and -44 or -3
			assert.same({ "TOPLEFT", frame, "TOPLEFT", left, -3 }, uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT"))
			assert.same({ "TOPRIGHT", frame, "TOPRIGHT", right, -30 }, uf:GetRow("power"):GetFrame():GetAnchor("TOPRIGHT"))
			assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -43 }, uf:GetRow("experience"):GetFrame():GetAnchor("TOPLEFT"))
			assert.same({ "TOPRIGHT", frame, "TOPRIGHT", -3, -54 }, uf:GetPart("castbar"):GetFrame():GetAnchor("TOPRIGHT"))
		end
	end)

	it("counts enabled rows and includes only spacing within the span", function()
		Set("portrait.rowSpan", 2)
		Set("power.enabled", false)
		Set("spacing", 5)
		Set("health.height", 30)
		assert.equals(45, portrait:GetHeight(), "health + gap + XP")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 50, -38 }, uf:GetRow("experience"):GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -53 }, uf:GetPart("castbar"):GetFrame():GetAnchor("TOPLEFT"))
		Set("experience.enabled", false)
		assert.equals(53, portrait:GetHeight(), "health + gap + castbar")
		Set("portrait.rowSpan", 4)
		assert.equals(53, portrait:GetHeight(), "clamped to available rows")
		Set("castbar.enabled", false)
		assert.equals(30, portrait:GetHeight())
		Set("portrait.enabled", false)
		assert.equals(230, frame:GetWidth())
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -3 }, uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT"))
		Set("portrait.enabled", true)
		assert.equals(262, frame:GetWidth())
	end)

	it("counts castbar rows by their placement and follows the health-overlay fallback", function()
		Set("portrait.rowSpan", 2)
		Set("castbar.placement", "top")
		assert.equals(45, portrait:GetHeight(), "castbar + gap + health")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 50, -3 }, uf:GetPart("castbar"):GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -49 }, uf:GetRow("power"):GetFrame():GetAnchor("TOPLEFT"))
		Set("castbar.placement", "health")
		assert.equals(39, portrait:GetHeight(), "overlay consumes no row")
		assert.same({ "ALL", uf:GetRow("health"):GetFrame() }, uf:GetPart("castbar"):GetFrame().__state.points[1])
		Set("health.enabled", false)
		assert.equals(31, portrait:GetHeight(), "fallback castbar row + gap + power")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -35 }, uf:GetRow("experience"):GetFrame():GetAnchor("TOPLEFT"))
	end)

	it("honours fixed widths and fits portrait markers to the shorter height", function()
		Set("portrait.rowSpan", 1)
		Set("portrait.size", 80)
		Set("raidTarget.anchor", "PORTRAIT_BOTTOMRIGHT")
		Set("raidTarget.size", 64)
		local marker = uf:GetPart("raidTarget")
		assert.equals(80, portrait:GetWidth())
		assert.equals(26, portrait:GetHeight())
		assert.equals(26, marker:GetFrame():GetHeight())
		assert.same({ "BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0 }, marker:GetFrame():GetAnchor("BOTTOMRIGHT"))
		Set("health.enabled", false)
		assert.equals(12, marker:GetFrame():GetHeight())
		Set("power.enabled", false)
		Set("experience.enabled", false)
		Set("castbar.enabled", false)
		assert.is_false(marker:GetFrame():IsShown())
		Set("health.enabled", true)
		assert.equals(26, marker:GetFrame():GetHeight())
		assert.is_true(marker:GetFrame():IsShown())
	end)

	it("copies spans to compact units and clamps geometry without invalidating settings", function()
		Set("portrait.rowSpan", 4)
		Set("castbar.enabled", false)
		for _, unit in ipairs({ "pet", "target", "targettarget", "focus", "focustarget" }) do
			ns.Units:CopyPlayerSettings(unit)
			local copied = ns.Units.frames[unit].uf
			assert.equals(4, copied.resolved.portrait.rowSpan)
			assert.same({}, ns.Schema.Validate(copied:GetSchema(), ns.Config:GetUnitConfig(unit)))
			assert.equals(39, copied:GetPart("portrait"):GetFrame():GetHeight())
		end
	end)

	it("keeps a span stable across repeated applies, style changes and combat resizing", function()
		Set("portrait.rowSpan", 2)
		for _, mode in ipairs({ "3D", "2D", "class" }) do
			Set("portrait.mode", mode)
			uf:Apply()
			assert.equals(39, portrait:GetHeight())
			assert.equals(271, frame:GetWidth())
		end
		ns.Config:SetThemeValue("fontSize", 12)
		assert.equals(39, portrait:GetHeight())
		Mock.inCombat = true
		Set("portrait.rowSpan", 1)
		assert.equals(271, frame:GetWidth(), "protected size waits until combat ends")
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(258, frame:GetWidth())
		assert.equals(26, portrait:GetHeight())
	end)
end)

describe("Portrait row span Workbench setting", function()
	it("updates saved and preview layouts independently for each unit", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		for _, unit in ipairs(ns.Units.order) do
			wb:Select("unit." .. unit)
			wb:SelectSection("portrait")
			local control
			for _, row in ipairs(wb.inspector.page.rows) do
				if row.path == "portrait.rowSpan" then control = row.control end
			end
			assert.is_not_nil(control)
			wb.styleTarget.set("portrait.enabled", true)
			control.opts.onChange(1)
			assert.equals(1, ns.Config:GetUnitConfig(unit).portrait.rowSpan)
			local live, preview = ns.Units.frames[unit].uf, wb.handle.parts.uf
			assert.equals(preview.resolved.health.height, preview:GetPart("portrait"):GetFrame():GetHeight())
			assert.equals(live:GetPart("portrait"):GetFrame():GetHeight(), preview:GetPart("portrait"):GetFrame():GetHeight())
			wb.styleTarget.set("portrait.rowSpan", nil)
			assert.equals(0, preview.resolved.portrait.rowSpan)
		end
	end)
end)
