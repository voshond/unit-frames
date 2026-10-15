local Helpers = require("helpers")

-- The mock character's own profile (AceDB character key).
local CHAR = "Tester - TestRealm"

describe("Profiles #profiles", function()
	local ns, Profiles
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Profiles = ns.Profiles
	end)

	local function Encode(payload)
		local E = C_EncodingUtil
		return "!UF1!" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(payload)))
	end

	it("exports only style overrides and imports them without positions", function()
		ns.Config:SetUnitValue("player", "width", 280)
		ns.Config:SetUnitValue("target", "health.height", 30)
		ns.Config:SetThemeValue("colors.absorb", { 1, 0, 0 })
		ns.Config:SetPosition("default", "player", "CENTER", 10, 20)
		local text = assert(Profiles:Export())
		assert.is_not_nil(text:match("^!UF1![%w%+/=]+$"))
		local payload = Profiles:Decode(text)
		assert.same({ colors = { absorb = { 1, 0, 0 } } }, payload.data.theme)
		assert.is_nil(payload.data.positions)
		assert.same({ width = 280 }, payload.data.units.player)

		Profiles:Reset()
		assert.same({}, ns.Config:GetUnitConfig("player"))
		assert.equals(10, ns.Config:GetPosition("default", "player").x, "reset keeps positions")
		ns.Config:SetPosition("default", "player", "CENTER", 99, 99)

		local ok, dropped = ns:ImportProfile("  " .. text:sub(1, 20) .. "\n" .. text:sub(21) .. "  ")
		assert.is_true(ok)
		assert.same({}, dropped)
		assert.equals(280, ns.Config:GetUnitConfig("player").width)
		assert.equals(30, ns.Config:GetUnitConfig("target").health.height)
		-- A whole colour replaces the default, alpha included.
		assert.same({ 1, 0, 0 }, ns.Config:GetTheme().colors.absorb)
		assert.equals(99, ns.Config:GetPosition("default", "player").x, "imports never touch positions")
		assert.equals(280, ns.Units.frames.player.uf.resolved.width)
	end)

	it("drops unknown and invalid settings and reports them", function()
		local ok, dropped = Profiles:Import(Encode({ addon = "UnitFrames", kind = "style", data = {
			theme = { fontSize = 500, borderColor = { 1, 2, 3 }, bogus = true, colors = { health = { 0, 1, 0, 1 } } },
			units = { player = { width = 250, health = { height = "tall" } }, raid40 = { width = 1 } },
			positions = { default = {} },
			clickgrid = { settings = {} },
		} }))
		assert.is_true(ok)
		table.sort(dropped)
		assert.same({ "clickgrid", "positions", "theme.bogus", "theme.borderColor", "theme.fontSize",
			"units.player.health.height", "units.raid40" }, dropped)
		assert.equals(250, ns.Config:GetUnitConfig("player").width)
		assert.same({ 0, 1, 0, 1 }, ns.Config:GetTheme().colors.health)
		assert.equals(11, ns.Config:GetTheme().fontSize)
	end)

	it("rejects foreign, damaged and newer strings without writing", function()
		ns.Config:SetUnitValue("player", "width", 222)
		local cases = {
			{ "", "Paste" },
			{ "hello", "not a UnitFrames string" },
			{ "!UF9!AAAA", "newer version" },
			{ "!UF1!@@@@", "damaged" },
			{ "!UF1!" .. C_EncodingUtil.EncodeBase64("not compressed"), "damaged" },
			{ "!UF1!" .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString("{garbage")), "damaged" },
			{ Encode({ addon = "Plater", kind = "style", data = {} }), "damaged" },
			{ Encode({ addon = "UnitFrames", kind = "nameplates", data = {} }), "can't import" },
			{ Encode({ addon = "UnitFrames", kind = "style", data = "x" }), "damaged" },
		}
		for _, case in ipairs(cases) do
			local ok, reason = Profiles:Import(case[1])
			assert.is_false(ok, case[1])
			assert.is_not_nil(reason:find(case[2], 1, true), reason)
		end
		assert.equals(222, ns.Config:GetUnitConfig("player").width)
	end)

	it("imports into a new profile that keeps the current positions", function()
		ns.Config:SetUnitValue("player", "width", 260)
		local text = Profiles:Export()
		ns.Config:SetUnitValue("player", "width", 200)
		ns.Config:SetPosition("default", "player", "CENTER", 5, 6)
		local ok = Profiles:Import(text, "Shared")
		assert.is_true(ok)
		assert.equals("Shared", Profiles:GetCurrent())
		assert.equals(260, ns.Config:GetUnitConfig("player").width)
		assert.equals(5, ns.Config:GetPosition("default", "player").x)
		assert.same({ "Default", "Shared", CHAR }, ns:GetProfileKeys())
		local again, reason = Profiles:Import(text, CHAR)
		assert.is_false(again)
		assert.is_not_nil(reason:find("already exists", 1, true))
		assert.is_true(ns:SetProfile(CHAR))
		assert.equals(200, ns.Config:GetUnitConfig("player").width)
	end)

	it("creates, copies, switches and deletes profiles", function()
		ns.Config:SetUnitValue("player", "width", 240)
		ns.Config:SetPosition("default", "player", "CENTER", 1, 2)
		assert.is_false((Profiles:Create("  ")))
		assert.is_false((Profiles:Create(string.rep("x", 51))))
		assert.is_true(Profiles:Create(" Second "))
		assert.equals("Second", Profiles:GetCurrent())
		assert.same({}, ns.Config:GetUnitConfig("player"), "new profiles start from the default style")
		assert.equals(1, ns.Config:GetPosition("default", "player").x)
		assert.equals(ns.Units.definitions.player.width, ns.Units.frames.player.uf.resolved.width)

		ns.Config:SetPosition("default", "player", "CENTER", 7, 8)
		assert.is_true(Profiles:Copy(CHAR))
		assert.equals(240, ns.Config:GetUnitConfig("player").width)
		assert.equals(7, ns.Config:GetPosition("default", "player").x, "copying keeps the active positions")
		assert.equals(240, ns.Units.frames.player.uf.resolved.width)
		assert.is_false((Profiles:Copy("Second")))

		assert.is_false((Profiles:Delete("Second")))
		assert.is_true(Profiles:Switch(CHAR))
		assert.equals(1, ns.Config:GetPosition("default", "player").x)
		assert.is_true(Profiles:Delete("Second"))
		assert.same({ "Default", CHAR }, Profiles:List())
		assert.is_false((Profiles:Switch("Second")))
	end)

	it("moves frames to the switched profile's positions", function()
		local frame = ns.Units.frames.player
		ns.Config:SetPosition(nil, "player", "CENTER", 11, 12)
		Profiles:Create("Other")
		ns.Config:SetPosition(nil, "player", "CENTER", 33, 34)
		Profiles:Switch(CHAR)
		local _, _, _, x, y = frame:GetPoint(1)
		assert.equals(11, x)
		assert.equals(12, y)
	end)

	it("reports clients without the encoding API", function()
		ns.Caps.encoding = false
		assert.is_nil((Profiles:Export()))
		local ok, reason = Profiles:Import("!UF1!AAAA")
		assert.is_false(ok)
		assert.is_not_nil(reason:find("can't decode", 1, true))
	end)
end)

describe("Profiles Workbench entry #profiles", function()
	-- The Workbench mock's character name is opaque: it stays on Default.
	local HOME = "Default"
	local ns, workbench, handle, target
	before_each(function()
		ns, workbench = Helpers.LoadWorkbench()
		workbench:Open("profiles")
		handle, target = workbench.handle, workbench.styleTarget
	end)

	local function Row(key)
		for _, row in ipairs(workbench.inspector.page.rows) do
			if row.opt.key == key then return row end
		end
	end

	it("exports into the box and imports into a new profile", function()
		ns.Config:SetUnitValue("player", "width", 275)
		handle:Export("style")
		local text = handle.box:GetInputText()
		assert.is_not_nil(text:match("^!UF1!"))
		ns.Config:SetUnitValue("player", "width", 210)
		handle.nameBox:SetValue("From string")
		handle:Import()
		assert.equals("From string", ns.Profiles:GetCurrent())
		assert.equals(275, ns.Config:GetUnitConfig("player").width)
		assert.equals("Imported style into From string.", handle.message:GetText())
		assert.equals("From string", target.resolved().current)
		assert.equals("", handle.nameBox:GetValue())
	end)

	it("keeps the message below the buttons and offers one export without ClickGrid", function()
		local point, relative, relativePoint = handle.message:GetPoint(1)
		assert.equals("TOPLEFT", point)
		assert.equals("BOTTOMLEFT", relativePoint)
		assert.is_true(relative ~= handle.frame)
		assert.equals("Export style", handle.buttons[1].text:GetText())
		assert.equals(handle.nameBox, handle.buttons[2], "no all settings export with a single kind")
	end)

	it("reports bad strings without changing anything", function()
		handle.box:SetText("not a string")
		handle:Import()
		assert.equals("This is not a UnitFrames string.", handle.message:GetText())
		assert.equals(HOME, ns.Profiles:GetCurrent())
	end)

	it("creates, switches and copies profiles from the settings column", function()
		ns.Config:SetUnitValue("player", "width", 260)
		target.set("newName", "Healer")
		target.invoke("create")
		assert.equals("Healer", ns.Profiles:GetCurrent())
		assert.equals("Created and switched to Healer.", handle.message:GetText())
		assert.same({}, ns.Config:GetUnitConfig("player"))
		assert.equals(HOME, target.resolved().copyFrom)
		target.invoke("copy")
		assert.equals(260, ns.Config:GetUnitConfig("player").width)
		target.set("current", HOME)
		assert.equals(HOME, ns.Profiles:GetCurrent())
		target.set("newName", HOME)
		target.invoke("create")
		assert.equals("A profile named " .. HOME .. " already exists.", handle.message:GetText())
	end)

	it("hides deleting and resetting until allowed, once", function()
		ns.Profiles:Create("Spare")
		workbench:RefreshInspector()
		assert.is_false(Row("delete").region:IsShown())
		assert.is_false(Row("reset").region:IsShown())
		target.set("unlocked", true)
		workbench:RefreshInspector()
		assert.is_true(Row("delete").region:IsShown())
		assert.equals(HOME, target.resolved().deleteName)
		target.invoke("delete")
		assert.same({ "Spare" }, ns.Profiles:List())
		assert.is_false(target.resolved().unlocked)
		workbench:RefreshInspector()
		assert.is_false(Row("reset").region:IsShown())
	end)
end)

describe("Character profiles #profiles", function()
	local Mock = Helpers.Mock

	it("gives a new character its own profile", function()
		local ns = Helpers.LoadAddon(true, true)
		assert.equals(CHAR, ns.Profiles:GetCurrent())
		assert.same({ "Default", CHAR }, ns.Profiles:List())
	end)

	it("stays on Default while the character name is opaque", function()
		Mock.Install()
		Mock.InstallUI()
		local ns = Helpers.LoadWorkbench()
		assert.equals("Default", ns.Profiles:GetCurrent())
	end)

	it("moves a character from the shared Default profile to its own copy, once", function()
		local ns = Helpers.LoadAddon(true, true, {
			profileKeys = { [CHAR] = "Default" },
			profiles = { Default = { units = { player = { width = 270 } },
				positions = { default = { player = { point = "CENTER", x = 4, y = 5 } } } } },
			namespaces = { ClickGrid = { profiles = { Default = { settings = { panel = { columns = 2 } } } } } },
		})
		assert.equals(CHAR, ns.Profiles:GetCurrent())
		assert.equals(270, ns.Config:GetUnitConfig("player").width)
		assert.equals(4, ns.Config:GetPosition("default", "player").x)
		assert.equals(2, UnitFramesDB.namespaces.ClickGrid.profiles[CHAR].settings.panel.columns)
		-- A later, deliberate switch back to Default stays.
		ns.Profiles:Switch("Default")
		ns = Helpers.LoadAddon(true, true, UnitFramesDB)
		assert.equals("Default", ns.Profiles:GetCurrent())
	end)
end)
