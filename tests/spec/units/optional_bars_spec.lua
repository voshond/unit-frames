local Helpers = require("helpers")

describe("Optional cast and experience bars", function()
	it("starts every unit castbar and player experience disabled in live frames and previews", function()
		local ns = Helpers.LoadAddon(true, true)
		for _, unit in ipairs(ns.Units.order) do
			local frame = ns.Units.frames[unit]
			assert.is_false(frame.uf.resolved.castbar.enabled, unit)
			assert.is_false(frame:IsElementEnabled("UF_Castbar"), unit)
			local preview = ns.Units:CreateFrame(unit, UIParent)
			ns.Units:ShowSample(preview, ns.Units:GetSample(unit))
			assert.is_false(preview:GetPart("castbar"):IsEnabled(), unit)
			assert.is_false(preview:GetPart("castbar"):GetFrame():IsShown(), unit)
			if unit == "player" then
				assert.is_false(frame:IsElementEnabled("UF_Experience"))
				assert.is_false(preview:GetRow("experience"):IsEnabled())
			end
			preview:Release()
		end
	end)

	it("ignores every placement while disabled and retains it across repeated toggles", function()
		local ns = Helpers.LoadAddon(true, true)
		local frame = ns.Units.frames.player
		local uf, castbar = frame.uf, frame.uf:GetPart("castbar")
		local height = frame:GetHeight()
		for _, choice in ipairs(ns.Components.UnitFrame.CASTBAR_PLACEMENTS) do
			local placement = choice[1]
			assert.is_false(placement == "off")
			ns.Config:SetUnitValue("player", "castbar.placement", placement)
			assert.equals(height, frame:GetHeight())
			assert.equals("off", uf.layout.castbarPlacement)
			assert.is_false(frame:IsElementEnabled("UF_Castbar"))
			for _ = 1, 2 do
				ns.Config:SetUnitValue("player", "castbar.enabled", true)
				assert.is_true(frame:IsElementEnabled("UF_Castbar"))
				assert.equals(placement, uf.layout.castbarPlacement)
				ns.Units:ShowSample(uf, ns.Units:GetSample("player"))
				assert.is_true(castbar:GetFrame():IsShown())
				ns.Config:SetUnitValue("player", "castbar.enabled", false)
				assert.is_false(frame:IsElementEnabled("UF_Castbar"))
				assert.is_false(castbar:GetFrame():IsShown())
				assert.equals(height, frame:GetHeight())
				assert.equals(placement, uf.resolved.castbar.placement)
				assert.equals(1, uf:GetRow("health"):GetFrame():GetAlpha())
				assert.equals(1, uf:GetPart("portrait"):GetFrame():GetAlpha())
			end
		end
	end)

	it("exposes working enable checkboxes in Workbench and refreshes the unit preview", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		wb:SelectSection("castbar")
		local controls = {}
		for _, row in ipairs(wb.inspector.page.rows) do controls[row.path] = row.control end
		assert.is_not_nil(controls["castbar.enabled"])
		controls["castbar.placement"].opts.onChange("top")
		local preview = wb.handle.parts.uf
		assert.is_false(preview:GetPart("castbar"):IsEnabled())
		controls["castbar.enabled"].opts.onChange(true)
		assert.is_true(preview:GetPart("castbar"):IsEnabled())
		assert.equals("top", preview.layout.castbarPlacement)
		assert.is_true(ns.Units.frames.player:IsElementEnabled("UF_Castbar"))
		controls["castbar.enabled"].opts.onChange(false)
		assert.is_false(preview:GetPart("castbar"):IsEnabled())
		assert.equals("top", preview.resolved.castbar.placement)
		wb:SelectSection("experience")
		local enabled
		for _, row in ipairs(wb.inspector.page.rows) do
			if row.path == "experience.enabled" then enabled = row.control end
		end
		enabled.opts.onChange(true)
		assert.is_true(preview:GetRow("experience"):IsEnabled())
		assert.is_true(ns.Units.frames.player:IsElementEnabled("UF_Experience"))
		enabled.opts.onChange(false)
		assert.is_false(preview:GetRow("experience"):IsEnabled())
		assert.is_false(ns.Units.frames.player:IsElementEnabled("UF_Experience"))
		wb:Select("unit.target")
		assert.is_true(preview.released)
	end)

	it("migrates old Off placements on profile load, switch and import so enabling works", function()
		local ns = Helpers.LoadAddon(true, true, { profiles = { Default = {
			units = { player = { castbar = { placement = "off" } } },
		} } })
		local function Check()
			local frame = ns.Units.frames.player
			assert.is_false(frame.uf.resolved.castbar.enabled)
			assert.equals("bottom", frame.uf.resolved.castbar.placement)
			ns.Config:SetUnitValue("player", "castbar.enabled", true)
			assert.is_true(frame:IsElementEnabled("UF_Castbar"))
		end
		Check()
		ns.Config.db.profiles.Legacy = { units = { player = { castbar = { placement = "off" } } } }
		ns.Profiles:Switch("Legacy")
		Check()
		local E = C_EncodingUtil
		local text = "!UF1!" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR({
			addon = "UnitFrames", kind = "style", data = { units = { player = { castbar = { placement = "off" } } } },
		})))
		local ok, dropped = ns.Profiles:Import(text)
		assert.is_true(ok)
		assert.same({}, dropped)
		Check()
	end)

	it("migrates ClickGrid saved and imported Off placements without blocking the checkbox", function()
		local ns, cg = Helpers.LoadClickGrid()
		cg.Config.db.profile.member = { castbar = { placement = "off" } }
		local style = cg.Config:GetStyle("member")
		assert.is_false(style.castbar.enabled)
		assert.is_nil(style.castbar.placement)
		assert.is_true(cg.Config:SetStyle("member", "castbar.enabled", true))
		assert.is_true(cg.Config.styles.member:Resolved().castbar.enabled)
		local E = C_EncodingUtil
		local text = "!UF1!" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR({
			addon = "UnitFrames", kind = "style", data = { clickgrid = {
				member = { castbar = { placement = "off" } },
				target = { castbar = { enabled = true, placement = "portrait" } },
			} },
		})))
		local ok, dropped = ns.Profiles:Import(text)
		assert.is_true(ok)
		assert.same({}, dropped)
		assert.is_false(cg.Config.styles.member:Resolved().castbar.enabled)
		assert.is_true(cg.Config.styles.target:Resolved().castbar.enabled)
		assert.equals("portrait", cg.Config.styles.target:Resolved().castbar.placement)
	end)
end)
