local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Messages()
	local lines = {}
	for _, message in ipairs(Mock.messages) do lines[#lines + 1] = table.concat(message, " ") end
	return table.concat(lines, "\n")
end

describe("Getting started presets #onboarding", function()
	it("composes every preset, tweak, size and extra into a style that imports without dropping anything", function()
		local ns, _, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		local function Check(label)
			local apply, dropped = ns.Profiles:Prepare("style", pending:Style())
			assert.is_not_nil(apply, label)
			assert.same({}, dropped, label)
		end
		for _, preset in ipairs(ob.Presets.list) do
			pending:Reset()
			pending:SelectPreset(preset.id)
			Check(preset.id)
			for _, tweak in ipairs(ob.Presets.tweaks) do
				for _, choice in ipairs(ob.Presets.Choices(tweak)) do
					pending:SetTweak(tweak.key, choice[1])
					Check(preset.id .. " " .. tweak.key .. "=" .. tostring(choice[1]))
					assert.equals(choice[1], pending:GetTweak(tweak.key))
				end
			end
			for _, extra in ipairs(ob.Presets.extras) do
				for _, enabled in ipairs({ true, false }) do
					pending:SetExtra(extra.key, enabled)
					Check(preset.id .. " " .. extra.key)
					assert.equals(enabled, pending:GetExtra(extra.key))
				end
			end
		end
	end)

	it("scales widths and bar heights from the look's own sizes", function()
		local ns, _, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		pending:Reset()
		pending:SelectPreset("healer")
		local normal = pending:Resolved().units.player
		pending:SetTweak("size", "large")
		local large = pending:Resolved().units.player
		assert.equals(math.floor(normal.width * 1.2 + 0.5), large.width)
		assert.equals(math.floor(normal.health.height * 1.2 + 0.5), large.health.height)
	end)
end)

describe("Getting started applying #onboarding", function()
	it("saves the look as a new profile, switched to, keeping frame positions", function()
		local ns, _, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		local before = ns.Profiles:GetCurrent()
		ns.Config:SetPositions({ Default = { player = { "CENTER", 10, 20 } } })
		local positions = ns.Config:GetPositions()
		pending:Reset()
		pending:SelectPreset("minimal")
		pending:SetExtra("targetCast", true)
		local ok, profile = pending:Apply()
		assert.is_true(ok)
		assert.equals("Minimal look", profile)
		assert.equals("Minimal look", ns.Profiles:GetCurrent())
		assert.same(positions.Default, ns.Config:GetPositions().Default)
		assert.equals("UnitFrames Pixel", ns.Config:GetTheme().borderTexture)
		assert.is_false(ns.Config:UnitStore("player"):Resolved().portrait.enabled)
		assert.is_true(ns.Config:UnitStore("target"):Resolved().castbar.enabled)
		assert.is_true(ns.FirstRun:IsDone())
		ns.Profiles:Switch(before)
		assert.equals("Blizzard Tooltip", ns.Config:GetTheme().borderTexture)
	end)

	it("numbers a second profile of the same look", function()
		local ns, _, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		pending:Reset()
		pending:SelectPreset("classic")
		pending:Apply()
		pending:Reset()
		pending:SelectPreset("classic")
		local _, profile = pending:Apply()
		assert.equals("Classic look 2", profile)
	end)

	it("replaces the active profile's style when no new profile is wanted", function()
		local ns, _, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		local current, count = ns.Profiles:GetCurrent(), #ns.Profiles:List()
		pending:Reset()
		pending:SelectPreset("classic")
		pending:SetNewProfile(false)
		local ok, profile = pending:Apply()
		assert.is_true(ok)
		assert.equals(current, profile)
		assert.equals(count, #ns.Profiles:List())
		assert.equals("Friz Quadrata TT", ns.Config:GetTheme().font)
	end)

	it("writes nothing when the style does not validate", function()
		local ns, _, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		local count, exported = #ns.Profiles:List(), ns.Profiles:Export("style")
		pending:Reset()
		pending.style = "damaged"
		local ok, reason = pending:Apply()
		assert.is_false(ok)
		assert.is_not_nil(reason)
		assert.equals(count, #ns.Profiles:List())
		assert.equals(exported, ns.Profiles:Export("style"))
		assert.is_false(ns.FirstRun:IsDone())
	end)
end)

describe("Getting started previews #onboarding", function()
	it("never changes the saved style or the live theme while browsing looks", function()
		local ns, onboarding, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		local theme, revision, exported = ns.Config:GetTheme(), ns.Config.themeRevision, ns.Profiles:Export("style")
		onboarding:Open()
		for _, id in ipairs({ "minimal", "classic", "healer" }) do pending:SelectPreset(id) end
		onboarding:Next()
		pending:SetTweak("border", "gold")
		pending:SetTweak("portrait", "class")
		onboarding:OnUpdate(0.5)
		onboarding:Next()
		pending:SetExtra("swing", true)
		assert.equals(theme, ns.Config:GetTheme())
		assert.equals(revision, ns.Config.themeRevision)
		assert.equals(exported, ns.Profiles:Export("style"))
	end)

	it("renders a preview with its own theme, and restores the live one even after an error", function()
		local ns = Helpers.LoadOnboarding()
		local preview = { borderTexture = "Blizzard Dialog Gold" }
		local seen
		ns.Config:WithTheme(preview, function() seen = ns.Config:GetTheme() end)
		assert.equals(preview, seen)
		assert.has_error(function() ns.Config:WithTheme(preview, function() error("boom") end) end)
		assert.equals("Blizzard Tooltip", ns.Config:GetTheme().borderTexture)
		assert.is_nil(ns.Config.previewTheme)
	end)

	it("releases every preview frame when the guide closes", function()
		local _, onboarding, ob = Helpers.LoadOnboarding()
		local steps = ob.Steps
		onboarding:Open()
		assert.equals(2, #steps.Look.preview.frames)
		onboarding:Next()
		assert.equals(0, #steps.Look.preview.frames)
		assert.equals(2, #steps.Tweaks.preview.frames)
		onboarding:Close()
		assert.equals(0, #steps.Tweaks.preview.frames)
		for _, preview in pairs(steps.Look.cardPreviews) do assert.equals(0, #preview.frames) end
	end)
end)

describe("Getting started flow #onboarding", function()
	it("walks four steps, applies on the third and only closes from the last", function()
		local ns, onboarding = Helpers.LoadOnboarding()
		onboarding:Open()
		local shell = onboarding.shell
		assert.equals(1, onboarding.index)
		assert.is_false(shell.back:IsShown())
		onboarding:Next()
		onboarding:Next()
		assert.equals(3, onboarding.index)
		assert.equals("Apply and finish", shell.next.text:GetText())
		onboarding:Next()
		assert.equals(4, onboarding.index)
		assert.equals("Default look", ns.Profiles:GetCurrent())
		assert.is_false(shell.back:IsShown())
		onboarding:Jump(1)
		assert.equals(4, onboarding.index)
		onboarding:Next()
		assert.is_false(onboarding:IsShown())
	end)

	it("counts Escape, Skip and the close button as done", function()
		local ns, onboarding = Helpers.LoadOnboarding()
		local count = #ns.Profiles:List()
		onboarding:Open()
		onboarding.shell.frame:Hide()
		assert.is_true(ns.FirstRun:IsDone())
		assert.equals(count, #ns.Profiles:List())
	end)

	it("hides in combat with the choices kept and comes back afterwards", function()
		local ns, onboarding, ob = Helpers.LoadOnboarding()
		local pending = ob.Pending
		onboarding:Open()
		onboarding:Next()
		pending:SetTweak("font", "Morpheus")
		Mock.inCombat = true
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		assert.is_false(onboarding:IsShown())
		assert.is_false(ns.FirstRun:IsDone())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(onboarding:IsShown())
		assert.equals(2, onboarding.index)
		assert.equals("Morpheus", pending:GetTweak("font"))
	end)
end)

describe("Getting started first run #onboarding", function()
	it("opens once after the first login of a fresh install", function()
		local ns, onboarding = Helpers.LoadOnboarding()
		Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
		assert.is_false(onboarding:IsShown())
		Mock.RunTimers()
		assert.is_true(onboarding:IsShown())
		onboarding:Close()
		Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
		Mock.RunTimers()
		assert.is_false(onboarding:IsShown())
		assert.is_true(ns.FirstRun:IsDone())
	end)

	it("waits for combat to end before opening", function()
		local _, onboarding = Helpers.LoadOnboarding()
		Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
		Mock.inCombat = true
		Mock.RunTimers()
		assert.is_false(onboarding:IsShown())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(onboarding:IsShown())
	end)

	it("leaves existing installs alone with a one-line hint", function()
		local ns, onboarding = Helpers.LoadOnboarding({})
		Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
		Mock.RunTimers()
		assert.is_false(onboarding:IsShown())
		assert.is_true(ns.FirstRun:IsDone())
		assert.is_not_nil(Messages():find("/uf welcome", 1, true))
	end)

	it("stays silent at login and hints on request when the addon is turned off", function()
		local ns = Helpers.LoadAddon(true, true)
		C_AddOns.LoadAddOn = function() return false, "DISABLED" end
		assert.is_false(ns:OpenOnboarding(true))
		assert.is_nil(Messages():find("turned off", 1, true))
		assert.is_false(ns:OpenOnboarding())
		assert.is_not_nil(Messages():find("turned off", 1, true))
	end)
end)

describe("Getting started hand-off #onboarding", function()
	it("opens Edit Mode from the last step only when the client allows it", function()
		local _, onboarding, ob = Helpers.LoadOnboarding()
		local shown = {}
		_G.ShowUIPanel = function(frame) shown[#shown + 1] = frame end
		_G.EditModeManagerFrame = { CanEnterEditMode = function() return true end }
		onboarding:Open()
		for _ = 1, 3 do onboarding:Next() end
		local button = ob.Steps.Ready.editMode
		assert.is_true(button:IsShown())
		button:GetFrame():RunScript("OnClick")
		assert.is_false(onboarding:IsShown())
		assert.same({ EditModeManagerFrame }, shown)
		_G.ShowUIPanel, _G.EditModeManagerFrame = nil, nil
	end)

	it("opens the Workbench at the settings page holding a path", function()
		local ns, wb = Helpers.LoadWorkbench()
		C_AddOns.LoadAddOn = function() return true end
		ns:OpenWorkbench("unit.player", "auras")
		local expected
		for _, record in ipairs(wb.pageModel.records) do
			if record.path == "auras.enabled" then expected = record.pageId end
		end
		assert.is_not_nil(expected)
		assert.equals("unit.player", wb.entry.id)
		assert.equals(expected, wb.state.section)
	end)
end)
