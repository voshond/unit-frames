local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Values(list)
	local out = {}
	for _, entry in ipairs(list) do out[entry[1]] = true end
	return out
end

local function Plain()
	UnitName = function() return "Jaina", "Realm" end
	UnitClass = function() return "Mage", "MAGE" end
	UnitLevel = function() return 44 end
	UnitHealth = function() return 15600 end
	UnitHealthMax = function() return 24000 end
	UnitHealthMissing = function() return 8400 end
	UnitHealthPercent = function() return 50 end
	UnitCastingInfo = function() return nil end
	UnitChannelInfo = function() return nil end
	Mock.pvpInfo = {}
end

describe("Custom text slots", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		Plain()
	end)

	local function Slot(unit, row, key)
		return ns.Units.frames[unit].uf:GetRow(row or "health"):GetText(key or "left")
	end

	local function Saved(unit, path)
		return ns.Util.GetPath(ns.Config:GetUnitConfig(unit), path)
	end

	it("copies the selected preset into the pieces on the first switch to Custom", function()
		ns.Config:SetUnitValue("target", "health.belowLeft.enabled", true)
		ns.Config:SetUnitValue("target", "health.belowLeft.format", "level:info:cast")
		ns.Config:SetUnitValue("target", "health.belowLeft.format", "custom")
		local saved = Saved("target", "health.belowLeft")
		assert.same({ source = "smartlevel", before = "", after = "" }, saved.piece1)
		assert.same({ source = "info", before = " ", after = "" }, saved.piece2)
		assert.same({ source = "pvp", before = " ", after = "" }, saved.piece3)
		assert.same({ source = "none", before = "", after = "" }, saved.piece4)
		assert.equals("spell", saved.whileCasting)
		assert.is_true(saved.customInitialized)
		local text = Slot("target", "health", "belowLeft")
		local sample = ns.Units:GetSample("target")
		sample.showCast = false
		local preset = ns.TextTemplate.Compile({ pieces = ns.Formats.Get("level:info").pieces, levelColor = true })
		assert.equals(preset.sample(sample), (text:GetTemplate().sample(sample)))
		-- Preset-owned pieces are independent copies.
		saved.piece1.source = "name"
		assert.equals("smartlevel", ns.Formats.Get("level:info").pieces[1].source)
	end)

	it("keeps custom edits behind a preset and replaces them only on request", function()
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		ns.Config:SetUnitValue("player", "health.left.piece2.source", "health.percent")
		ns.Config:SetUnitValue("player", "health.left.piece2.before", " - ")
		local text = Slot("player")
		assert.equals("Jaina - 50%", text:GetTemplate().live("player"))
		ns.Config:SetUnitValue("player", "health.left.format", "health:value")
		assert.equals("health:value", text:GetPresetTag())
		assert.equals("health.percent", Saved("player", "health.left.piece2.source"))
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		assert.equals(" - ", Saved("player", "health.left.piece2.before"), "retained edits come back")
		-- "Edit as custom text" while a preset is selected starts over from it.
		ns.Config:SetUnitValue("player", "health.left.format", "health:value")
		ns.Config:UnitStore("player"):Invoke("health.left.customize")
		assert.equals("custom", Saved("player", "health.left.format"))
		assert.same({ source = "health.max", before = " / ", after = "" }, Saved("player", "health.left.piece2"))
		assert.equals("keep", Saved("player", "health.left.whileCasting"))
	end)

	it("keeps an intentionally empty custom slot empty", function()
		ns.Config:SetUnitValue("player", "health.left.format", "none")
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		assert.is_true(Saved("player", "health.left.customInitialized"))
		assert.equals("none", Saved("player", "health.left.piece1.source"))
		local frame, text = ns.Units.frames.player, Slot("player")
		assert.is_true(text:GetTemplate().empty)
		assert.is_nil(frame.tags[text:GetFrame()])
		ns.Config:SetUnitValue("player", "health.left.format", "name")
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		assert.equals("none", Saved("player", "health.left.piece1.source"), "not reseeded")
	end)

	it("offers and shows player-only sources on the player frame only", function()
		local function Opt(unit, path) return ns.Schema.Find(ns.Units:GetSchema(unit), path) end
		local player = Values(ns.Schema.GetValues(Opt("player", "health.left.piece1.source")))
		local target = Values(ns.Schema.GetValues(Opt("target", "health.left.piece1.source")))
		assert.is_true(player["xp.current"] and player.resting and player["health.max"])
		assert.is_nil(target["xp.current"])
		assert.is_nil(target.resting)
		assert.is_true(target["health.max"] and target.pvp and target["cast.spell"])
		assert.is_true(Values(ns.Schema.GetValues(Opt("player", "health.left.format"))).resting)
		local targetFormats = Values(ns.Schema.GetValues(Opt("target", "health.left.format")))
		assert.is_nil(targetFormats.resting)
		assert.is_true(targetFormats.custom and targetFormats.name)
		-- Saved incompatible choices are kept but show nothing.
		ns.Config:SetUnitValue("target", "health.left.format", "custom")
		ns.Config:SetUnitValue("target", "health.left.piece1.source", "xp.current")
		ns.Config:SetUnitValue("target", "health.left.piece2.source", "nope")
		assert.equals("xp.current", Saved("target", "health.left.piece1.source"))
		assert.is_true(Slot("target"):GetTemplate().empty)
		ns.Config:SetUnitValue("target", "health.right.format", "resting")
		assert.is_true(Slot("target", "health", "right"):GetTemplate().empty)
		assert.is_nil(ns.Units.frames.target.tags[Slot("target", "health", "right"):GetFrame()])
	end)

	it("tags custom slots through reusable handles", function()
		local frame, text = ns.Units.frames.player, Slot("player")
		local fs = text:GetFrame()
		local created, idle = ns.TextTags.Stats()
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		local handle = ns.TextTags.GetHandle(fs)
		assert.equals("[" .. handle .. "]", frame.tags[fs])
		assert.equals("Jaina", ns.oUF.Tags.Methods[handle]("player"))
		assert.equals("UNIT_NAME_UPDATE", ns.oUF.Tags.Events[handle])
		for i = 1, 20 do
			ns.Config:SetUnitValue("player", "health.left.piece2.source", i % 2 == 0 and "xp.current" or "level")
			ns.Config:SetUnitValue("player", "health.left.piece2.before", " " .. i .. " ")
		end
		assert.equals(handle, ns.TextTags.GetHandle(fs), "edits keep the handle")
		assert.equals(created + 1, (ns.TextTags.Stats()))
		assert.equals("Jaina 20 1200", ns.oUF.Tags.Methods[handle]("player"))
		assert.is_true(ns.oUF.Tags.SharedEvents.PLAYER_XP_UPDATE)
		assert.is_not_nil(ns.oUF.Tags.Events[handle]:find("PLAYER_XP_UPDATE", 1, true))
		-- Appearance-only edits keep the compiled template.
		local template = text:GetTemplate()
		ns.Config:SetUnitValue("player", "health.left.size", 15)
		assert.equals(template, text:GetTemplate())
		-- Back to a preset or off: the handle is idle and holds nothing.
		ns.Config:SetUnitValue("player", "health.left.format", "name")
		assert.equals("[uf:name]", frame.tags[fs])
		assert.is_nil(ns.TextTags.GetHandle(fs))
		assert.equals(created + 1, (ns.TextTags.Stats()))
		assert.equals(idle + 1, select(2, ns.TextTags.Stats()))
		assert.equals("", ns.oUF.Tags.Methods[handle]("player"))
		assert.is_nil(ns.oUF.Tags.Events[handle])
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		assert.equals(handle, ns.TextTags.GetHandle(fs), "an idle handle is reused")
		ns.Config:SetUnitValue("player", "health.left.enabled", false)
		assert.is_nil(frame.tags[fs])
		assert.equals("", fs:GetText())
		assert.is_nil(ns.TextTags.GetHandle(fs))
	end)

	it("shares templates between equal contents and shows the same text in samples and live", function()
		for _, unit in ipairs({ "target", "focus" }) do
			ns.Config:SetUnitValue(unit, "health.right.format", "custom")
			ns.Config:SetUnitValue(unit, "health.right.piece1.source", "health.percent")
			ns.Config:SetUnitValue(unit, "health.right.piece2.source", "name")
			ns.Config:SetUnitValue(unit, "health.right.piece2.before", " % [x] $> ")
		end
		local a, b = Slot("target", "health", "right"), Slot("focus", "health", "right")
		assert.equals(a:GetTemplate(), b:GetTemplate())
		UnitHealthPercent = function() return 65 end
		assert.equals("65% % [x] $> Jaina", a:GetTemplate().live("target"))
		local preview = ns.Units:CreateFrame("target", UIParent)
		local sample = ns.Units:GetSample("target")
		ns.Units:ShowSample(preview, sample)
		local fs = preview:GetRow("health"):GetText("right"):GetFrame()
		assert.equals("65% % [x] $> Scarlet Myrmidon", fs:GetText())
		preview:GetRow("health"):ShowLive("target")
		assert.equals("65% % [x] $> Jaina", fs:GetText())
		preview:Release()
	end)

	it("replaces the whole custom slot while casting", function()
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		ns.Config:SetUnitValue("player", "health.left.whileCasting", "spell")
		local template = Slot("player"):GetTemplate()
		local spell = Mock.Secret("Frostbolt")
		UnitCastingInfo = function() return spell end
		assert.is_true(rawequal(spell, template.live("player")))
		assert.is_not_nil(template.events:find("UNIT_SPELLCAST_START", 1, true))
	end)

	it("moves icons before a custom text that starts with the name", function()
		local uf = ns.Units.frames.player.uf
		assert.equals(Slot("player"), uf:GetLeadingName())
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		assert.equals(Slot("player"), uf:GetLeadingName())
		ns.Config:SetUnitValue("player", "health.left.piece1.source", "health.current")
		assert.is_nil(uf:GetLeadingName())
	end)

	it("copies player texts only as far as the destination can show them", function()
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		ns.Config:SetUnitValue("player", "health.left.piece2.source", "xp.current")
		ns.Config:SetUnitValue("player", "health.left.piece2.before", " ")
		ns.Config:SetUnitValue("player", "health.left.piece3.source", "health.percent")
		ns.Config:SetUnitValue("player", "health.right.format", "custom")
		ns.Config:SetUnitValue("player", "health.right.piece1.source", "resting")
		ns.Config:SetUnitValue("player", "health.right.format", "resting")
		ns.Config:SetUnitValue("player", "power.right.format", "power:percent")
		assert.is_true(ns.Units:CopyPlayerSettings("target"))
		local left = Saved("target", "health.left")
		assert.equals("custom", left.format)
		assert.equals("name", left.piece1.source)
		assert.equals("none", left.piece2.source)
		assert.equals(" ", left.piece2.before, "position and affixes stay")
		assert.equals("health.percent", left.piece3.source)
		local right = Saved("target", "health.right")
		assert.equals("none", right.format, "an entirely player-only preset is switched off")
		assert.equals("none", right.piece1.source, "retained custom pieces are checked too")
		assert.equals("power:percent", Saved("target", "power.right.format"))
		-- Independent copies.
		ns.Config:SetUnitValue("player", "health.left.piece3.source", "name")
		assert.equals("health.percent", Saved("target", "health.left.piece3.source"))
		UnitHealthPercent = function() return 65 end
		assert.equals("Jaina65%", Slot("target"):GetTemplate().live("target"))
	end)

	it("follows profile resets", function()
		ns.Config:SetUnitValue("player", "health.left.format", "custom")
		ns.Config:SetUnitValue("player", "health.left.piece1.source", "level")
		assert.equals("44", tostring(Slot("player"):GetTemplate().live("player")))
		ns.Config:UnitStore("player"):Reset()
		assert.equals("[uf:name]", ns.Units.frames.player.tags[Slot("player"):GetFrame()])
		assert.equals("Jaina", Slot("player"):GetTemplate().live("player"))
	end)
end)

describe("Custom text slots in the Workbench", function()
	it("shows the pieces inside the slot's section only for custom slots", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		for _, item in ipairs(wb.sections) do
			assert.is_nil(item.id and item.id:find("piece", 1, true), "pieces are not sections")
		end
		wb:SelectSection("health.left")
		local rows = {}
		for _, row in ipairs(wb.inspector.page.rows) do rows[row.path] = row end
		assert.is_not_nil(rows["health.left.piece1"], "piece header")
		assert.is_not_nil(rows["health.left.piece4.after"])
		assert.is_false(rows["health.left.piece1.source"].region:IsShown())
		assert.is_true(rows["health.left.customize"].region:IsShown())
		assert.is_nil(rows["health.left.customInitialized"])
		wb.styleTarget.invoke("health.left.customize")
		wb.inspector:Refresh()
		assert.equals("custom", UF.Config:GetUnitConfig("player").health.left.format)
		assert.is_true(rows["health.left.piece1.source"].region:IsShown())
		assert.is_true(rows["health.left.piece1.before"].region:IsShown())
		assert.is_false(rows["health.left.piece2.before"].region:IsShown(), "unused pieces hide their affixes")
		assert.is_false(rows["health.left.customize"].region:IsShown())
		local fs = wb.handle.parts.uf:GetRow("health"):GetText("left"):GetFrame()
		wb.styleTarget.set("health.left.piece2.source", "health.percent")
		wb.styleTarget.set("health.left.piece2.before", " | ")
		wb:UpdateData()
		assert.equals("Uther | 65%", fs:GetText())
	end)
end)

describe("Text handles on embedded oUF", function()
	it("update, retag and release through oUF's own tag code", function()
		local ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		Plain()
		local meta = {}
		local native = {
			Private = { nierror = error, unitExists = UnitExists, validateEvent = function() return true end,
				insertObjectElementUpdateFunc = function() end, GameVersion = {}, GameCompatibility = {} },
		}
		function native:RegisterMetaFunction(name, fn) meta[name] = fn end
		assert(loadfile("UnitFrames/Libs/oUF/elements/tags.lua"))("oUF", { oUF = native })
		ns.oUF.Tags = native.Tags
		local uf = ns.Units:CreateFrame("player", UIParent)
		local frame = { __unit = "player", IsEventless = function() return false end, Tag = meta.Tag, Untag = meta.Untag }
		local text = uf:GetRow("health"):GetText("left")
		local fs = text:GetFrame()
		-- Unknown fields such as oUF's fs.frequentUpdates are nil, as on a real FontString.
		rawset(fs, "__strict", true)
		local function Pieces(...)
			local pieces = { ... }
			return ns.TextTemplate.Get({ pieces = pieces }, { player = true })
		end
		local function Fire(event, ...)
			Mock.FireEvent(event, ...)
			for _, obj in ipairs(Mock.objects) do
				local update = obj.__state.scripts.OnUpdate
				if update and obj.__state.events[event] then update(obj, 1) end
			end
		end

		ns.TextTags.Bind(frame, fs, Pieces({ source = "name" }, { source = "health.current", before = " " }))
		local handle = ns.TextTags.GetHandle(fs)
		fs:UpdateTag()
		assert.equals("Jaina 15600", fs:GetText())
		UnitHealth = function() return 9000 end
		Fire("UNIT_HEALTH", "player")
		assert.equals("Jaina 9000", fs:GetText())
		UnitHealth = function() return 8000 end
		Fire("UNIT_HEALTH", "target")
		assert.equals("Jaina 9000", fs:GetText(), "other units' events are ignored")

		-- New content: same handle, new events; the old ones no longer update it.
		assert.is_true(ns.TextTags.Bind(frame, fs, Pieces({ source = "xp.current" })))
		assert.equals(handle, ns.TextTags.GetHandle(fs))
		assert.is_false(ns.TextTags.Bind(frame, fs, Pieces({ source = "xp.current" })), "unchanged: no retag")
		fs:UpdateTag()
		assert.equals("1200", fs:GetText())
		UnitXP = function() return 1300 end
		Fire("PLAYER_XP_UPDATE")
		assert.equals("1300", fs:GetText(), "unitless events update the text")
		UnitXP = function() return 1400 end
		Fire("UNIT_HEALTH", "player")
		assert.equals("1300", fs:GetText())

		ns.TextTags.Unbind(fs)
		frame:Untag(fs)
		assert.is_nil(fs.UpdateTag)
		Fire("PLAYER_XP_UPDATE")
		assert.equals("1300", fs:GetText())
		uf:Release()
	end)
end)
