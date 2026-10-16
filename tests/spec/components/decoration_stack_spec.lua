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

	it("reuses scratch storage and leaves unchanged geometry alone", function()
		local icon, host, member = Join("extra")
		icon:Show()
		stack:Reflow()
		local item, group = stack.items.extra, stack.groups.TOP
		local writes, levels, point, setLevel = 0, 0, host.SetPoint, host.SetFrameLevel
		host.SetFrameLevel = function(self, ...)
			levels = levels + 1
			return setLevel(self, ...)
		end
		host.SetPoint = function(self, ...)
			writes = writes + 1
			return point(self, ...)
		end
		for _ = 1, 100 do stack:Reflow() end
		assert.equals(0, writes)
		assert.equals(0, levels, "unchanged reflows leave frame levels alone, including in combat")
		assert.equals(item, stack.items.extra)
		assert.equals(group, stack.groups.TOP)
		member.x = 3
		stack:Reflow()
		assert.equals(1, writes)
		member.size = 14
		stack:Reflow()
		assert.equals(14, host:GetWidth())
		member.present = function() return Mock.Secret(false) end
		assert.has_no_error(function() stack:Reflow() end)
	end)

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

	it("stacks groups at all nine portrait positions through presence, offsets and toggles", function()
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		ns.Config:SetUnitValue("player", "portrait.size", 40)
		local portrait = uf:GetLayoutContext().portrait.frame
		local a, aHost, aMember = Join("a", { anchor = "PORTRAIT_TOPLEFT", order = 1, size = 10, gap = 4 })
		local b, bHost, bMember = Join("b", { anchor = "PORTRAIT_TOPLEFT", order = 2, size = 6, gap = 9 })
		a:Show()
		b:Show()
		-- a 10 + gap 4 + b 6 = 20; the last gap is dropped.
		local expected = {
			TOPLEFT = { { 0, 0 }, { 14, 0 } }, BOTTOMLEFT = { { 0, 0 }, { 14, 0 } },
			TOPRIGHT = { { -10, 0 }, { 0, 0 } }, BOTTOMRIGHT = { { -10, 0 }, { 0, 0 } },
			TOP = { { -5, 0 }, { 7, 0 } }, BOTTOM = { { -5, 0 }, { 7, 0 } }, CENTER = { { -5, 0 }, { 7, 0 } },
			LEFT = { { 0, 5 }, { 0, -7 } }, RIGHT = { { 0, 5 }, { 0, -7 } },
		}
		local function Expect(point, aAt, bAt, message)
			assert.same({ point, portrait, point, aAt[1], aAt[2] }, Anchor(aHost), point .. message)
			assert.same({ point, portrait, point, bAt[1], bAt[2] }, Anchor(bHost), point .. message)
		end
		for point, at in pairs(expected) do
			aMember.anchor, bMember.anchor = "PORTRAIT_" .. point, "PORTRAIT_" .. point
			stack:Reflow()
			Expect(point, at[1], at[2], "")
			bMember.x, bMember.y = 1, 2
			stack:Reflow()
			Expect(point, at[1], { at[2][1] + 1, at[2][2] + 2 }, " nudges one icon")
			bMember.x, bMember.y = nil, nil
			aMember.order = 3
			stack:Reflow()
			-- b 6 + gap 9 + a 10 = 25: order runs left to right or top to bottom.
			local layout = { TOPLEFT = { 15, 0 }, BOTTOMLEFT = { 15, 0 }, TOPRIGHT = { 0, -19 }, BOTTOMRIGHT = { 0, -19 },
				TOP = { 7.5, -9.5 }, BOTTOM = { 7.5, -9.5 }, CENTER = { 7.5, -9.5 }, LEFT = { -7.5, 9.5 }, RIGHT = { -7.5, 9.5 } }
			local aAlong, bAlong = layout[point][1], layout[point][2]
			if point == "LEFT" or point == "RIGHT" then
				Expect(point, { 0, aAlong }, { 0, bAlong }, " in order")
			else
				Expect(point, { aAlong, 0 }, { bAlong, 0 }, " in order")
			end
			aMember.order = 1
			b:Hide()
			stack:Reflow()
			-- Alone, each icon sits on the position itself.
			Expect(point, { 0, 0 }, { 0, 0 }, " alone")
			b:Show()
			bMember.present = function() return nil end
			b:Hide()
			stack:Reflow()
			Expect(point, at[1], at[2], " keeps an unknown member's slot")
			bMember.present = nil
			b:Show()
		end
		aMember.anchor, bMember.anchor = "PORTRAIT_TOP", "PORTRAIT_TOP"
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.is_false(aHost:IsShown())
		assert.is_false(bHost:IsShown())
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		portrait = uf:GetLayoutContext().portrait.frame
		assert.is_true(aHost:IsShown())
		Expect("TOP", { -5, 0 }, { 7, 0 }, " after re-enabling")
	end)

	it("fits every portrait position to square, wide and tall portraits", function()
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		local _, host, member = Join("extra", { anchor = "PORTRAIT_TOP", size = 64 })
		for _, size in ipairs({ 0, 12, 80 }) do -- square, tall, wide
			ns.Config:SetUnitValue("player", "portrait.size", size)
			local portrait = uf:GetLayoutContext().portrait
			for _, anchor in ipairs(ns.DecorationStack.ANCHORS) do
				if anchor[1]:match("^PORTRAIT_") then
					member.anchor = anchor[1]
					stack:Reflow()
					assert.equals(math.min(64, portrait.width, portrait.height), host:GetWidth())
					assert.equals(host:GetWidth(), host:GetHeight())
				end
			end
		end
	end)

	it("offers every portrait position to each indicator and validates them", function()
		local values = {}
		for _, anchor in ipairs(ns.DecorationStack.ANCHORS) do values[anchor[1]] = true end
		for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
			assert.is_true(values[point], point)
			assert.is_true(values["PORTRAIT_" .. point], "PORTRAIT_" .. point)
		end
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		local portrait = uf:GetLayoutContext().portrait.frame
		marker:SetIndex(8)
		for _, key in ipairs({ "raidTarget", "pvp", "classification", "readyCheckIcon" }) do
			ns.Config:SetUnitValue("player", key .. ".anchor", "PORTRAIT_TOP")
		end
		assert.same({}, ns.Schema.Validate(uf:GetSchema(), ns.Config:GetUnitConfig("player")))
		assert.equals("TOP", (marker:GetFrame():GetPoint()))
		assert.equals(portrait, select(2, marker:GetFrame():GetPoint()))
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
