local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Bar tint", function()
	local ns, C, parent
	local SEGMENTS = {
		{ key = "heal", label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
		{ key = "absorb", label = "Absorb shields", mode = "overlay", colorInherit = "colors.absorb" },
	}
	before_each(function()
		ns = Helpers.LoadAddon(true)
		C = ns.Components
		parent = CreateFrame("Frame", nil, UIParent)
	end)

	local function Near(expected, actual, message)
		for i = 1, #expected do
			assert.is_true(math.abs(expected[i] - actual[i]) < 1e-6,
				(message or "") .. ": channel " .. i .. " expected " .. expected[i] .. ", got " .. tostring(actual[i]))
		end
	end

	it("crossfades over a secret data colour without touching it", function()
		local bar = C.Bar:New(parent, {}, { segments = SEGMENTS })
		local fill = bar.bar:GetStatusBarTexture()
		local r, g, b = Secret(0.2), Secret(0.4), Secret(0.6)
		bar:SetColor(r, g, b)
		assert.is_false(bar.tintFill:IsShown(), "no tint by default")
		bar:SetTint(0.1, 0.9, 0.1, 0.25)
		assert.same({ r, g, b, 1 }, bar.bar.__state.color, "the data colour stays as it is")
		assert.is_true(bar.tintFill:IsShown())
		assert.same({ "ALL", fill }, { bar.tintFill:GetPoint(1) })
		assert.same({ 0.1, 0.9, 0.1, 0.25 }, bar.tintFill.__state.vertexColor)
		assert.equals(bar.clip, bar.tintFill:GetParent(), "drawn above the fill, below the segments")
		-- The bar-coloured background fades over to the tint at its own opacity.
		assert.is_true(bar.tintBg:IsShown())
		assert.same({ 0.1, 0.9, 0.1, 0.25 * 0.25 }, bar.tintBg.__state.vertexColor)
		assert.same({ r, g, b, 0.25 * 0.75 }, bar.bg.__state.vertexColor, "the secret colour passes through")
		bar:SetTint(nil)
		assert.is_false(bar.tintFill:IsShown())
		assert.is_false(bar.tintBg:IsShown())
		assert.same({ r, g, b, 0.25 }, bar.bg.__state.vertexColor)
		assert.is_nil(bar:GetTint())
	end)

	it("blends plain segment colours and restores them", function()
		local bar = C.Bar:New(parent, { segments = { heal = { color = { 0, 1, 0, 0.5 } } } }, { segments = SEGMENTS })
		local heal = bar.segmentsByKey.heal.bar
		bar:SetTint(1, 0, 0, 0.5)
		Near({ 0.5, 0.5, 0, 0.5 }, heal.__state.color, "half way, keeping segment opacity")
		bar:SetTint(1, 0, 0, 1)
		Near({ 1, 0, 0, 0.5 }, heal.__state.color)
		bar:SetTint(1, 0, 0, 0)
		Near({ 0, 1, 0, 0.5 }, heal.__state.color, "a zero amount removes the tint")
		assert.is_false(bar.tintFill:IsShown())
	end)

	it("survives re-styling and leaves a fixed background colour alone", function()
		local bar = C.Bar:New(parent, {}, { segments = SEGMENTS })
		bar:SetTint(0.5, 0.5, 0.5)
		bar:Apply({ texture = "Blizzard Raid Bar", background = { useBarColor = false } })
		assert.is_true(bar.tintFill:IsShown())
		assert.same({ 0.5, 0.5, 0.5, 1 }, { bar:GetTint() })
		assert.equals(bar.bg.__state.texture, bar.tintFill.__state.texture, "tint uses the bar texture")
		assert.is_false(bar.tintBg:IsShown())
		assert.same({ 0, 0, 0, 0.5 }, bar.bg.__state.vertexColor, "a fixed background colour stays")
		bar:Apply({ background = { enabled = false } })
		assert.is_false(bar.tintBg:IsShown())
		bar:Apply({})
		assert.is_true(bar.tintBg:IsShown())
		assert.equals(0, bar.bg.__state.vertexColor[4])
		bar:Apply({})
		assert.equals(1, bar.tintFill.__state.vertexColor[4], "applying twice is safe")
	end)

	it("passes through text bars", function()
		local row = C.TextBar:New(parent, {}, ns.UnitRows.Spec("health"))
		row:SetTint(0.2, 0.8, 0.2)
		assert.same({ 0.2, 0.8, 0.2, 1 }, { row:GetBar():GetTint() })
		row:SetTint(nil)
		assert.is_nil(row:GetBar():GetTint())
		assert.is_false(Mock.IsSecret(row:GetBar().bg:GetAlpha()))
	end)

	-- A texture's SetAlpha replaces its vertex alpha in the client, which
	-- turned the 25% bar-coloured background fully opaque (XP looked full).
	it("keeps the background's opacity in its vertex colour through frame refreshes", function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		local uf = ns.Units.frames.player.uf
		ns.Units:Refresh("player")
		uf:GetReadyCheck():Set("ready")
		uf:GetReadyCheck():Set(nil)
		for key, row in uf:Rows() do
			local bar = row:GetBar()
			assert.equals(0.25, bar.bg.__state.vertexColor[4], key)
			for _, texture in ipairs({ bar.bg, bar.tintBg, bar.tintFill }) do
				for _, call in ipairs(texture.__calls) do
					assert.is_false(call[1] == "SetAlpha", key .. ": bar textures fade by vertex alpha only")
				end
			end
		end
	end)
end)
