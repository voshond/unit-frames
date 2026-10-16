local Helpers = require("helpers")
local Mock = Helpers.Mock

local function AssertSwipe(button, mode)
	assert.equals(mode ~= "none", button.ufCooldown.__state.drawSwipe)
	assert.equals(mode == "reverse", button.ufCooldown.__state.reverse)
end

describe("Aura cooldown swipe", function()
	local ns, uf
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, {
			portrait = { enabled = false }, castbar = { placement = "off" }, auraBar = { enabled = true },
		})
	end)

	for _, key in ipairs({ "auras", "auraBar" }) do
		describe(key, function()
			local part
			before_each(function() part = uf:GetPart(key) end)

			local function Native(kind)
				return part:GetContainer(kind):GetAuraGroupFrame(kind, 1)
			end

			it("defaults both groups to progressing and exposes their schema choices", function()
				for _, kind in ipairs({ "buffs", "debuffs" }) do
					local setting = ns.Schema.Find(part:GetSchema(), kind .. ".swipe")
					assert.equals("normal", setting.default)
					assert.same({ { "normal", "Progressing" }, { "reverse", "Decreasing" }, { "none", "None" } }, setting.values)
					AssertSwipe(Native(kind), "normal")
				end
			end)

			for _, source in ipairs({ "sample", "live" }) do
				it("restyles independent " .. source .. " groups across every toggle order", function()
					if source == "sample" then ns.Units:ShowSample(uf, ns.Units.SAMPLE) end
					local function Button(kind)
						if source == "live" then return Native(kind) end
						return part.previewContainers[kind].ufElements[1]
					end
					local buff, debuff = Button("buffs"), Button("debuffs")
					local remaining = debuff.ufTime:GetText()
					for _, from in ipairs({ "normal", "reverse", "none" }) do
						for _, to in ipairs({ "normal", "reverse", "none" }) do
							part:Apply({ enabled = true, buffs = { swipe = from }, debuffs = { swipe = to } })
							AssertSwipe(buff, from)
							AssertSwipe(debuff, to)
							part:Apply({ enabled = true, buffs = { swipe = to }, debuffs = { swipe = from } })
							part:Apply(part.config)
							AssertSwipe(buff, to)
							AssertSwipe(debuff, from)
							assert.equals(remaining, debuff.ufTime:GetText())
						end
					end
					part:Apply({ enabled = true })
					AssertSwipe(buff, "normal")
					AssertSwipe(debuff, "normal")
				end)
			end

			it("defers live swipe changes until combat ends", function()
				local buff, debuff = Native("buffs"), Native("debuffs")
				Mock.inCombat = true
				part:Apply({ enabled = true, buffs = { swipe = "none" }, debuffs = { swipe = "reverse" } })
				assert.is_true(ns.AfterCombat:IsQueued(part, "restyle"))
				AssertSwipe(buff, "normal")
				AssertSwipe(debuff, "normal")
				Mock.inCombat = false
				Mock.FireEvent("PLAYER_REGEN_ENABLED")
				AssertSwipe(buff, "none")
				AssertSwipe(debuff, "reverse")
				assert.is_false(ns.AfterCombat:IsQueued(part, "restyle"))
			end)
		end)
	end

	it("keeps ClickGrid fixed slots on the default swipe", function()
		local _, CG = Helpers.LoadClickGrid()
		local slots = CG.Slots:New(UIParent, { slot1 = { enabled = true, spell = "139" } })
		AssertSwipe(slots.buttons[1], "normal")
		slots:ShowSample({ buffs = { { spellId = 139, icon = "sample", duration = 15, remaining = 8 } } })
		AssertSwipe(slots.samples[1], "normal")
		slots:Release()
	end)
end)
