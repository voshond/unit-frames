local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Character and full name text", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
	end)

	it("keeps character names and adds optional surnames to full names", function()
		local surname = "Proudmoore"
		UnitName = function(unit)
			assert.equals("target", unit)
			return "Jaina", surname
		end
		assert.equals("Jaina", ns.Formats.Get("name").text("target"))
		assert.equals("Jaina Proudmoore", ns.Formats.Get("fullname").text("target"))
		for _, value in ipairs({ false, "" }) do
			surname = value or nil
			assert.equals("Jaina", ns.Formats.Get("fullname").text("target"))
		end
		UnitExists = function() return false end
		UnitName = function() error("absent units must not read name data") end
		assert.equals("", ns.Formats.Get("fullname").text("target"))
	end)

	it("passes opaque first and last names through the native composer", function()
		UnitName = function() return Mock.Secret("Jaina"), Mock.Secret("Proudmoore") end
		assert.is_true(Mock.IsSecret(ns.Formats.Get("fullname").text("target")))
		local surname = ns.TextTemplate.Compile({ pieces = { { source = "lastname", before = " " } } })
		assert.is_true(Mock.IsSecret(surname.live("target")))
		UnitName = function() return "Jaina", Mock.Secret("") end
		assert.is_true(Mock.IsSecret(ns.Formats.Get("fullname").text("target")))
	end)

	it("offers both presets and last-name pieces and binds name update events", function()
		local schema = ns.Units:GetSchema("target")
		local function Choices(path)
			local choices = {}
			for _, choice in ipairs(ns.Schema.GetValues(ns.Schema.Find(schema, path))) do
				choices[choice[1]] = choice[2]
			end
			return choices
		end
		for _, row in ipairs({ "health", "power" }) do
			local formats = Choices(row .. ".left.format")
			assert.equals("Character name", formats.name)
			assert.equals("Full name", formats.fullname)
			assert.equals("Identity: Last name", Choices(row .. ".left.piece1.source").lastname)
		end
		ns.Config:SetUnitValue("target", "health.left.format", "fullname")
		local frame = ns.Units.frames.target
		local text = frame.uf:GetRow("health"):GetText("left")
		assert.equals("[uf:fullname]", frame.tags[text:GetFrame()])
		assert.equals("UNIT_NAME_UPDATE", ns.oUF.Tags.Events["uf:fullname"])
		ns.Config:SetUnitValue("target", "health.left.format", "custom")
		local saved = ns.Config:GetUnitConfig("target").health.left
		assert.same({ source = "lastname", before = " ", after = "" }, saved.piece2)
		assert.equals("UNIT_NAME_UPDATE", text:GetTemplate().events)
	end)

	it("shows surnames in sample previews without giving NPCs inherited surnames", function()
		local frame = ns.Units.frames.focus.uf
		ns.Config:SetUnitValue("focus", "health.left.format", "fullname")
		local values = ns.Units:GetSample("focus")
		ns.Units:ShowSample(frame, values)
		assert.equals("Jaina Proudmoore", frame:GetRow("health"):GetText("left"):GetFrame():GetText())
		for _, unit in ipairs({ "pet", "target", "focustarget" }) do
			local sample = ns.Units:GetSample(unit)
			assert.equals(sample.name, ns.Formats.Get("fullname").sample(sample), unit)
		end
		assert.equals("Uther Lightbringer", ns.Formats.Get("fullname").sample(ns.Units:GetSample("player")))
		assert.equals("Arthas Menethil", ns.Formats.Get("fullname").sample(ns.Units:GetSample("targettarget")))
		assert.equals("Jaina", ns.Formats.Get("fullname").sample({ name = "Jaina" }))
	end)
end)
