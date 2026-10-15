local Helpers = require("helpers")
local Mock = Helpers.Mock

local function FontCalls(text)
	local calls = {}
	for _, call in ipairs(text:GetFrame().__calls) do
		if call[1] == "SetFont" then calls[#calls + 1] = call end
	end
	return calls
end

describe("Text cold-start font initialization", function()
	local UF, parent, config
	before_each(function()
		UF = Helpers.LoadAddon(true)
		Helpers.LoadToc("UnitFrames_Media/UnitFrames_Media.toc", "UnitFrames_Media")
		parent = CreateFrame("Frame")
		config = { font = "Roboto Condensed Medium", size = 10, outline = "OUTLINE" }
	end)

	it("round trips fonts after visible population and a rendered frame, then retires", function()
		local text = UF.Components.Text:New(parent, config)
		local fs = text:GetFrame()
		local configured = { "SetFont", UF.Media:Fetch("font", config.font), 10, "OUTLINE" }
		assert.same({ configured }, FontCalls(text), "creation alone must not consume the repair")
		text:SetText("Thalaron")
		local driver = Mock.objects[#Mock.objects]
		assert.is_not_nil(driver:GetScript("OnUpdate"))
		assert.is_nil(rawget(fs, "SetText"), "remove the temporary setter immediately")
		assert.is_nil(rawget(fs, "SetFormattedText"))
		driver:RunScript("OnUpdate", 0.016)
		assert.equals(1, #FontCalls(text), "let populated text render before resetting its font")
		driver:RunScript("OnUpdate", 0.016)
		assert.same({ configured,
			{ "SetFont", GameFontNormal:GetFont() },
			configured }, FontCalls(text))
		assert.equals("Thalaron", fs:GetText())
		assert.is_nil(driver:GetScript("OnUpdate"))
		assert.is_false(driver:IsShown())
		text:SetFormattedText("%s", Secret("100%"))
		text:Apply()
		assert.equals(4, #FontCalls(text), "only the ordinary style apply sets a font again")
		assert.is_nil(driver:GetScript("OnUpdate"))
	end)

	it("waits through empty and hidden updates and shares one batch for secret tags", function()
		parent:Hide()
		local text = UF.Components.Text:New(parent, config)
		local objects = #Mock.objects
		text:SetText("")
		text:SetFormattedText("%s", Secret("100%"))
		assert.equals(objects, #Mock.objects, "hidden population must not start a polling driver")
		parent:Show()
		text:SetFormattedText("%s", Secret("100%"))
		local driver = Mock.objects[#Mock.objects]
		local second = UF.Components.Text:New(parent, config)
		objects = #Mock.objects
		second:SetText(Secret("842 / 842"))
		assert.equals(objects, #Mock.objects, "all texts share one driver")
		second:Apply({ font = "Roboto Condensed", size = 9, outline = "NONE" })
		driver:RunScript("OnUpdate", 0.016)
		driver:RunScript("OnUpdate", 0.016)
		assert.equals(3, #FontCalls(text))
		assert.same({ UF.Media:Fetch("font", "Roboto Condensed"), 9, "" }, second.frame.__state.font,
			"the deferred repair uses current settings")
		assert.is_true(Mock.IsSecret(text.frame:GetText()))
		assert.is_true(Mock.IsSecret(second.frame:GetText()))
		assert.is_nil(driver:GetScript("OnUpdate"))
	end)

	it("cancels unpopulated and pending repairs on release", function()
		local waiting = UF.Components.Text:New(parent, config)
		waiting:Release()
		assert.is_nil(rawget(waiting.frame, "SetText"))
		local text = UF.Components.Text:New(parent, config)
		text:SetText("Thalaron")
		local driver = Mock.objects[#Mock.objects]
		local update = driver:GetScript("OnUpdate")
		text:Release()
		assert.is_nil(driver:GetScript("OnUpdate"))
		update(driver, 0.016)
		assert.equals(1, #FontCalls(text), "released text must not be restyled")
	end)

	it("does not branch on secret visibility or poll for it", function()
		local text = UF.Components.Text:New(parent, config)
		Mock.RunUntainted(text.frame.SetShown, text.frame, Secret(true))
		local objects = #Mock.objects
		assert.has_no_error(function() text:SetText(Secret("Thalaron")) end)
		assert.equals(objects, #Mock.objects)
		text.frame:Show()
		text:SetText(Secret("Thalaron"))
		local driver = Mock.objects[#Mock.objects]
		driver:RunScript("OnUpdate", 0.016)
		driver:RunScript("OnUpdate", 0.016)
		assert.equals(3, #FontCalls(text))
		assert.is_nil(driver:GetScript("OnUpdate"))
	end)
end)
