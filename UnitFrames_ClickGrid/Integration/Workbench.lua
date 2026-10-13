local _, CG = ...
local UF = CG.UF

-- Every ClickGrid setting change restyles the open ClickGrid preview.
local REFRESH_ON = {
	{ "ClickGridConfigChanged", notifyOnly = true },
	{ "ThemeChanged", notifyOnly = true },
}

local function Report(reason)
	CG:Print(reason)
end

function CG:RegisterWorkbench()
	local wb = UF.Workbench
	if not wb or not self.started or wb.entries["clickgrid.panel"] then return end
	local data = {
		schema = {
			{ key = "source", type = "select", label = "Source", default = "static",
				values = { { "static", "Static" }, { "animated", "Animated" }, { "live", "Live group (bars and auras)" } } },
			{ key = "count", type = "range", label = "Sample members", min = 1, max = 40, step = 1, default = 5,
				hidden = function(d) return d.source == "live" end },
			{ key = "readyCheck", type = "select", label = "Ready check", default = "off",
				values = { { "off", "None" }, { "check", "Ready check" } },
				hidden = function(d) return d.source == "live" end,
				tooltip = "Sample ready check with mixed answers: bar tints and the ready check icon. Static holds the answers; Animated lets members answer one after another, then ends the check and fades out. A live check needs a group." },
		},
		update = function(handle, values) handle:ShowData(values) end,
		tick = function(handle, values, _, elapsed) handle.data = values; handle:Tick(elapsed) end,
	}
	local function Create(stage) return CG.Preview:New(stage) end
	wb:Register({ id = "clickgrid.panel", name = "Panel & indicators", category = "ClickGrid", autoSize = true, fitToStage = true,
		size = { 500, 500 }, create = Create, data = data, refreshOn = REFRESH_ON,
		styleTarget = function() return CG.Config.settings:Target(Report) end,
		reset = function() CG.Config.settings:Reset() end,
	})
	for _, kind in ipairs({ "member", "target" }) do
		local styleKind = kind
		wb:Register({ id = "clickgrid." .. styleKind, name = styleKind == "member" and "Member bars" or "Target bars",
			category = "ClickGrid", autoSize = true, fitToStage = true, size = { 500, 500 }, create = Create, data = data,
			refreshOn = REFRESH_ON,
			styleTarget = function() return CG.Config.styles[styleKind]:Target(Report) end,
			reset = function() CG.Config.styles[styleKind]:Reset() end,
		})
	end
	self:RegisterBindingEntry(wb)
end

function CG:RegisterBindingEntry(wb)
	local B, W = self.Bindings, UF.Widgets
	local editor = { button = 1, modifier = "none" }
	local buttonValues, modifierValues = {}, {}
	for i, name in ipairs(B.buttons) do buttonValues[i] = { i, name } end
	for i, modifier in ipairs(B.modifiers) do modifierValues[i] = { modifier[1], modifier[2] } end
	-- Openers are disabled in combat rather than queueing a window to open later.
	local extras = {}
	if self.Caps.spellBook then
		extras[#extras + 1] = { text = "Spellbook", combatLocked = true,
			tooltip = "Open the spellbook to drag a spell from it. Unavailable in combat.",
			onClick = function() PlayerSpellsUtil.OpenToSpellBookTab() end }
	end
	-- The editor-only drop slot shows and replaces its whole reaction group;
	-- the action list and typed spell remain the manual alternative.
	local function ReactionSchema(reaction)
		return UF.Schema.Concat({
			{ key = "drop", type = "actionslot", label = reaction == "friendly" and "Friendly action" or "Hostile action",
				tooltip = "Drop a spell from your spellbook or action bars, or click here while carrying one."
					.. " It is used on " .. reaction .. " units only, whatever the spell itself does.",
				accept = function() return B:DecodeCursor() end,
				describe = function(choice) return B:Describe(choice) end,
				empty = { action = "none" }, extras = extras },
		}, B.actionSchema)
	end
	local schema = {
		{ key = "button", type = "select", label = "Mouse button", default = 1, values = buttonValues },
		{ key = "modifier", type = "select", label = "Modifiers", default = "none", values = modifierValues },
		{ key = "friendly", type = "group", label = "Friendly unit", schema = ReactionSchema("friendly") },
		{ key = "hostile", type = "group", label = "Hostile unit", schema = ReactionSchema("hostile") },
	}
	local function Selected()
		local all = UF.Schema.Resolve(B.schema, CG.Config:GetBindings())
		local selected = UF.Util.Copy(all["button" .. editor.button][editor.modifier])
		selected.button, selected.modifier = editor.button, editor.modifier
		for _, reaction in ipairs({ "friendly", "hostile" }) do
			local choice = selected[reaction]
			choice.drop = { action = choice.action, spell = choice.action == "spell" and choice.spell or nil }
		end
		return selected
	end
	-- One matrix line per reaction: icon, name and an inactive state.
	local function Summary(tag, choice)
		local info = B:Describe(choice)
		local color = info.inactive and "ffff5a4d" or choice.action == "none" and "ff94949f" or "ffebebeb"
		return tag .. " " .. (info.icon and "|T" .. info.icon .. ":12:12|t " or "") .. "|c" .. color .. info.name .. "|r"
	end
	wb:Register({ id = "clickgrid.bindings", name = "Click spells", category = "ClickGrid", autoSize = true,
		size = { 700, 460 }, refreshOn = { "ClickGridConfigChanged" },
		create = function(stage)
			local handle = { frame = CreateFrame("Frame", nil, stage), buttons = {} }
			handle.frame:SetSize(700, 460)
			local note = handle.frame:CreateFontString(nil, "OVERLAY")
			note:SetFontObject(UF.Media:GetFontObject(UF.Config:GetTheme().font, 11, ""))
			note:SetPoint("TOPLEFT", 0, 0)
			note:SetWidth(700)
			note:SetJustifyH("LEFT")
			function handle:Apply()
				local owner = B:IsExternal() and "Clique owns live clicks. These saved bindings are inactive while Clique is loaded."
					or "Click a cell, then drop a spell into its friendly or hostile slot in settings, or type a spell ID or name."
						.. " All bindings are applied on mouse release."
				note:SetText(owner .. "\nSpecialization: " .. CG.Config:SpecKey() .. (CG.pending and " — changes pending until combat ends" or "")
					.. (#(CG.bindingErrors or {}) > 0 and "\n" .. CG.bindingErrors[1]
						.. (#CG.bindingErrors > 1 and " (and " .. (#CG.bindingErrors - 1) .. " more inactive bindings)" or "") or ""))
				local all = UF.Schema.Resolve(B.schema, CG.Config:GetBindings())
				for row, modifier in ipairs(B.modifiers) do
					for column, name in ipairs(B.buttons) do
						local key = row .. ":" .. column
						local button = self.buttons[key]
						if not button then
							local selectedButton, selectedModifier = column, modifier[1]
							button = W.Button:New(self.frame, { onClick = function()
								editor.button, editor.modifier = selectedButton, selectedModifier
								wb:RefreshInspector()
							end })
							button:SetSize(136, 44)
							button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (column - 1) * 140, -90 - (row - 1) * 46)
							self.buttons[key] = button
						end
						local cell = all["button" .. column][modifier[1]]
						button:SetText(name .. " / " .. modifier[2] .. "\n" .. Summary("|cff4fe07aF|r", cell.friendly)
							.. "\n" .. Summary("|cffff5a4dH|r", cell.hostile))
					end
				end
			end
			function handle:Release()
				for _, button in pairs(self.buttons) do
					button:Release()
				end
				self.frame:Hide()
			end
			handle:Apply()
			return handle
		end,
		styleTarget = function(handle)
			return { schema = schema,
				get = function(path)
					if path == "button" or path == "modifier" then return editor[path] end
					-- A drop slot is overridden when its whole group is.
					path = path:gsub("%.drop$", "")
					return UF.Util.GetPath(CG.Config:GetBindings(), "button" .. editor.button .. "." .. editor.modifier .. "." .. path)
				end,
				-- Returns the save result: drop slots clear the cursor only on success
				-- and show their own rejection reason.
				set = function(path, value)
					local ok, reason = true, nil
					if path == "button" or path == "modifier" then editor[path] = value or (path == "button" and 1 or "none")
					else
						local reaction, field = path:match("^(%w+)%.(%w+)$")
						if field == "drop" then
							ok, reason = CG.Config:SetAction(editor.button, editor.modifier, reaction, value)
						else
							ok, reason = CG.Config:SetBinding(editor.button, editor.modifier, reaction, field, value)
							if not ok then Report(reason) end
						end
					end
					handle:Apply()
					return ok, reason
				end,
				resolved = Selected }
		end,
		reset = function() CG.Config.bindings:Reset() end,
	})
end
