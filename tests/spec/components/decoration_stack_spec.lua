local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Decoration stacks", function()
	local ns, frame, uf, stack, marker
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		stack = uf:GetDecorations()
		marker = uf:GetPart("raidTarget")
	end)

	-- A companion icon: size 10, gap 4, after the marker by default.
	-- Names follow the health bar's native layout: hosts that may sit
	-- before them carry the forbidden layout aspect, like companion icons.
	local function Join(key, overrides)
		local host = CreateFrame("Frame", nil, frame, "DisableUntrustedLayoutScriptsTemplate")
		local icon = host:CreateTexture(nil, "OVERLAY")
		icon:Hide() -- like real indicator art until a value shows it
		local member = { host = host, widgets = { icon }, enabled = true, anchor = "TOP", size = 10, order = 2, gap = 4 }
		for k, v in pairs(overrides or {}) do member[k] = v end
		stack:Set(key, member)
		stack:Reflow()
		return icon, host, member
	end

	local function Anchor(region)
		return { region:GetPoint() }
	end

	it("groups companion icons with the raid marker through frame layouts and order changes", function()
		local icon, host = Join("extra")
		icon:Show()
		marker:SetIndex(8)
		-- Marker 20 + gap 2 + icon 10 = 32 wide.
		assert.same({ "CENTER", frame, "TOP", -6, 0 }, Anchor(marker:GetFrame()))
		assert.same({ "CENTER", frame, "TOP", 11, 0 }, Anchor(host))
		ns.Config:SetUnitValue("player", "width", 260)
		assert.same({ "CENTER", frame, "TOP", 11, 0 }, Anchor(host), "frame layouts keep members")
		-- Icon 10 + its gap 4 + marker 20 = 34 wide.
		ns.Config:SetUnitValue("player", "raidTarget.order", 3)
		assert.same({ "CENTER", frame, "TOP", -12, 0 }, Anchor(host))
		assert.same({ "CENTER", frame, "TOP", 7, 0 }, Anchor(marker:GetFrame()))
		marker:SetIndex(0)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(host))
		ns.Config:SetUnitValue("player", "raidTarget.enabled", false)
		assert.is_false(marker:GetFrame():IsShown())
		ns.Config:SetUnitValue("player", "raidTarget.enabled", true)
		assert.is_true(marker:GetFrame():IsShown())
	end)

	it("lets an explicit presence decide and keeps a slot when presence is unknown", function()
		marker:SetIndex(8)
		local presence
		local icon, host = Join("extra", { present = function() return presence end })
		assert.same({ "CENTER", frame, "TOP", 11, 0 }, Anchor(host), "unknown presence keeps the slot")
		presence = false
		icon:Show()
		stack:Reflow()
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
		presence = true
		stack:Reflow()
		assert.same({ "CENTER", frame, "TOP", -6, 0 }, Anchor(marker:GetFrame()))
		Mock.RunUntainted(icon.SetShown, icon, Mock.Secret(false)) -- an engine-owned shown state
		stack:Remove("extra")
		stack:Reflow()
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
	end)

	it("centres the player's sole marker across the portrait and bars through icon toggles", function()
		ns.Config:SetUnitValue("player", "width", 170)
		ns.Config:SetUnitValue("player", "portrait.size", 35)
		ns.Config:SetUnitValue("player", "portrait.position", "LEFT")
		ns.Config:SetUnitValue("player", "raidTarget.size", 14)
		ns.Config:SetUnitValue("player", "pvp.anchor", "TOP")
		ns.Config:SetUnitValue("player", "classification.anchor", "TOP")
		marker:SetIndex(7)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
		local ready = uf:GetReadyCheck():GetIcon()
		ns.Config:SetUnitValue("player", "readyCheckIcon.anchor", "TOP")
		uf:GetReadyCheck():Set("ready")
		assert.is_true(select(4, marker:GetFrame():GetPoint()) ~= 0)
		ns.Config:SetUnitValue("player", "readyCheckIcon.enabled", false)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
		assert.is_false(ready:GetFrame():IsShown())
		-- Secret native visibility keeps a slot until that icon is disabled.
		local pvp = uf:GetPart("pvp"):GetWidget()
		Mock.RunUntainted(pvp.SetShown, pvp, Mock.Secret(false))
		uf:GetPart("pvp"):Reflow()
		assert.is_true(select(4, marker:GetFrame():GetPoint()) ~= 0)
		ns.Config:SetUnitValue("player", "pvp.enabled", false)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
		ns.Config:SetUnitValue("player", "classification.enabled", false)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, Anchor(marker:GetFrame()))
	end)

	it("hides members that cannot be placed and fits portrait corners", function()
		local icon, host = Join("extra", { anchor = "PORTRAIT_BOTTOMRIGHT", size = 64 })
		icon:Show()
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.is_false(host:IsShown())
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		local portrait = uf:GetLayoutContext().portrait
		assert.is_true(host:IsShown())
		assert.equals(math.min(64, portrait.width, portrait.height), host:GetWidth())
		assert.same({ "BOTTOMRIGHT", portrait.frame, "BOTTOMRIGHT", 0, 0 }, Anchor(host))
		local _, disabled = Join("extra", { anchor = "TOP", enabled = false })
		assert.is_false(disabled:IsShown())
	end)

	it("makes room before the name and returns it when members leave or the frame is released", function()
		local name = uf:GetLayoutContext().name
		local first, firstHost = Join("first", { anchor = "NAME", order = 1, size = 12, gap = 2 })
		local second, secondHost = Join("second", { anchor = "NAME", order = 2, size = 10, gap = 3 })
		assert.equals(0, name.leadingSpace or 0, "absent members take no room")
		first:Show()
		second:Show()
		stack:Reflow()
		assert.equals(27, name.leadingSpace)
		assert.same({ "RIGHT", name:GetFrame(), "LEFT", -15, 0 }, Anchor(firstHost))
		assert.same({ "RIGHT", name:GetFrame(), "LEFT", -3, 0 }, Anchor(secondHost))
		stack:Reflow()
		assert.equals(27, name.leadingSpace, "repeated reflows do not add room")
		second:Hide()
		stack:Reflow()
		assert.equals(14, name.leadingSpace)
		ns.Config:SetUnitValue("player", "health.left.format", "health:value")
		assert.equals(0, name.leadingSpace)
		assert.is_false(firstHost:IsShown())
		ns.Config:SetUnitValue("player", "health.left.format", "name")
		assert.equals(14, name.leadingSpace)
		local preview = ns.Units:CreateFrame("player", UIParent)
		local previewName = preview:GetLayoutContext().name
		local icon = CreateFrame("Frame", nil, preview:GetFrame(), "DisableUntrustedLayoutScriptsTemplate"):CreateTexture()
		preview:GetDecorations():Set("extra", { host = icon:GetParent(), widgets = { icon }, enabled = true,
			anchor = "NAME", size = 10, gap = 2 })
		preview:GetDecorations():Reflow()
		assert.equals(12, previewName.leadingSpace)
		preview:Release()
		assert.equals(0, previewName.leadingSpace)
		preview:GetDecorations():Set("late", { host = icon:GetParent(), enabled = true, anchor = "TOP", size = 10 })
		assert.has_no_error(function() preview:GetDecorations():Reflow() end)
		assert.is_nil(preview:GetDecorations().members.late, "released stacks accept no members")
	end)
end)
