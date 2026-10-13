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
	local B = self.Bindings
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
	if self.Caps.macroFrame then
		extras[#extras + 1] = { text = "Macros", combatLocked = true,
			tooltip = "Open the macro window to drag a macro from it. Unavailable in combat.",
			onClick = function() ShowMacroFrame() end }
	end
	-- The editor-only drop slot shows and replaces its whole reaction group;
	-- the action list and typed spell remain the manual alternative.
	local function ReactionSchema(reaction)
		return UF.Schema.Concat({
			{ key = "drop", type = "actionslot", label = reaction == "friendly" and "Friendly action" or "Hostile action",
				tooltip = "Drop a spell or macro from your spellbook, action bars or macro window, or click here while"
					.. " carrying one. It is used on " .. reaction .. " units only, whatever the spell itself does.",
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
			choice.drop = { action = choice.action, spell = choice.action == "spell" and choice.spell or nil,
				macro = choice.action == "macro" and choice.macro or nil }
		end
		return selected
	end
	local REACTIONS = {
		{ key = "friendly", tag = "F", color = { 0.31, 0.88, 0.48 }, label = "Friendly" },
		{ key = "hostile", tag = "H", color = { 1, 0.35, 0.3 }, label = "Hostile" },
	}
	-- The grid fills the stage: column widths and row heights follow it, between
	-- these bounds; the stage scale only zooms the content.
	local FONT_SIZE, NOTE_HEIGHT, HEADER_HEIGHT, LABEL_WIDTH, GAP = 10, 54, 16, 84, 3
	local MIN_WIDTH, MIN_HEIGHT, MAX_HEIGHT = 64, 30, 52
	local function Font() return UF.Media:GetFontObject(UF.Config:GetTheme().font, FONT_SIZE) end
	wb:Register({ id = "clickgrid.bindings", name = "Click spells", category = "ClickGrid", fillStage = true,
		size = { 700, 460 }, refreshOn = { "ClickGridConfigChanged", "ClickGridBindingsCompiled" },
		create = function(stage)
			local handle = { frame = CreateFrame("Frame", nil, stage), cells = {}, columns = {}, rows = {} }
			local frame = handle.frame
			frame:SetSize(700, 460)
			local note = frame:CreateFontString(nil, "OVERLAY")
			handle.note = note
			note:SetPoint("TOPLEFT")
			note:SetPoint("TOPRIGHT")
			note:SetHeight(NOTE_HEIGHT)
			note:SetJustifyH("LEFT")
			note:SetJustifyV("TOP")

			-- Spells dropped onto a line, or a click while carrying one, bind that
			-- line's cell and reaction at once; the cursor is cleared only after saving.
			function handle:Receive(line)
				if self.released then return end
				local value, reason = B:DecodeCursor()
				if value == nil and reason == nil then return self:Select(line) end
				-- Set before saving: a saved change redraws the grid through its config event.
				editor.button, editor.modifier, self.message = line.button, line.modifier, nil
				local ok = false
				if value then
					ok, reason = CG.Config:SetAction(line.button, line.modifier, line.reaction, value)
					if ok then ClearCursor() end
				end
				wb:SelectSection(line.reaction)
				if not ok then
					self.message = reason or "The action could not be saved."
					self:Apply()
				end
			end
			-- A click with an empty cursor opens the line's settings page instead.
			function handle:Select(line)
				if self.released then return end
				editor.button, editor.modifier, self.message = line.button, line.modifier, nil
				wb:SelectSection(line.reaction)
				wb:RefreshInspector()
				self:Apply()
			end
			local function ShowTooltip(line)
				local info = line.info
				GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
				GameTooltip:SetText(B.buttons[line.button] .. " / " .. line.title, 1, 1, 1)
				GameTooltip:AddLine(info.name, 1, 1, 1)
				GameTooltip:AddLine(info.status, unpack(info.inactive and UF.Skin.colors.warning or UF.Skin.colors.textDim))
				GameTooltip:AddLine("Drop a spell or macro here, or click with one on the cursor. Click to edit this binding.",
					nil, nil, nil, true)
				GameTooltip:Show()
			end
			local function CreateLine(cell, button, modifier, reaction)
				local line = CreateFrame("Button", nil, cell)
				line.button, line.modifier, line.reaction = button, modifier[1], reaction.key
				line.title = modifier[2] .. " / " .. reaction.label
				local highlight = line:CreateTexture(nil, "HIGHLIGHT")
				highlight:SetAllPoints()
				highlight:SetColorTexture(unpack(UF.Skin.colors.hover))
				line.tag = line:CreateFontString(nil, "OVERLAY")
				line.tag:SetFontObject(Font())
				line.tag:SetPoint("LEFT", 4, 0)
				line.tag:SetTextColor(unpack(reaction.color))
				line.icon = line:CreateTexture(nil, "ARTWORK")
				line.icon:SetPoint("LEFT", 14, 0)
				line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				line.name = line:CreateFontString(nil, "OVERLAY")
				line.name:SetFontObject(Font())
				line.name:SetPoint("LEFT", line.icon, "RIGHT", 3, 0)
				line.name:SetPoint("RIGHT", -3, 0)
				line.name:SetJustifyH("LEFT")
				line.name:SetWordWrap(false)
				line:SetScript("OnReceiveDrag", function() handle:Receive(line) end)
				line:SetScript("OnClick", function()
					if CG.Caps.cursor and GetCursorInfo() ~= nil then handle:Receive(line) else handle:Select(line) end
				end)
				line:SetScript("OnEnter", ShowTooltip)
				line:SetScript("OnLeave", function() GameTooltip:Hide() end)
				return line
			end
			local function Label(justify)
				local label = frame:CreateFontString(nil, "OVERLAY")
				label:SetFontObject(Font())
				label:SetJustifyH(justify)
				label:SetWordWrap(false)
				return label
			end
			for column, name in ipairs(B.buttons) do
				handle.columns[column] = Label("CENTER")
				handle.columns[column]:SetText(name)
			end
			for row, modifier in ipairs(B.modifiers) do
				handle.rows[row] = Label("RIGHT")
				handle.rows[row]:SetText((modifier[2]:gsub(" %+ ", "+")))
				for column in ipairs(B.buttons) do
					local cell = CreateFrame("Frame", nil, frame, "BackdropTemplate")
					UF.Skin.ApplyPanel(cell, "button")
					cell.lines = {}
					for _, reaction in ipairs(REACTIONS) do
						cell.lines[reaction.key] = CreateLine(cell, column, modifier, reaction)
					end
					handle.cells[row .. ":" .. column] = cell
				end
			end

			function handle:Layout()
				local width, height = frame:GetSize()
				local columns, rows = #B.buttons, #B.modifiers
				local cellWidth = math.max(MIN_WIDTH, math.floor((width - LABEL_WIDTH - GAP * columns) / columns))
				local top = NOTE_HEIGHT + 4 + HEADER_HEIGHT
				local cellHeight = math.floor((height - top - GAP * rows) / rows)
				cellHeight = math.min(MAX_HEIGHT, math.max(MIN_HEIGHT, cellHeight))
				local lineHeight = math.floor((cellHeight - 2) / 2)
				local iconSize = math.min(14, lineHeight - 2)
				for column, label in ipairs(self.columns) do
					local x = LABEL_WIDTH + GAP + (column - 1) * (cellWidth + GAP)
					label:ClearAllPoints()
					label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, -top)
					label:SetWidth(cellWidth)
				end
				for row, label in ipairs(self.rows) do
					local y = top + (row - 1) * (cellHeight + GAP)
					label:ClearAllPoints()
					label:SetPoint("RIGHT", frame, "TOPLEFT", LABEL_WIDTH, -y - cellHeight / 2)
					label:SetWidth(LABEL_WIDTH)
					for column in ipairs(B.buttons) do
						local cell = self.cells[row .. ":" .. column]
						cell:ClearAllPoints()
						cell:SetPoint("TOPLEFT", frame, "TOPLEFT", LABEL_WIDTH + GAP + (column - 1) * (cellWidth + GAP), -y)
						cell:SetSize(cellWidth, cellHeight)
						for index, reaction in ipairs(REACTIONS) do
							local line = cell.lines[reaction.key]
							line:ClearAllPoints()
							line:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1 - (index - 1) * lineHeight)
							line:SetPoint("RIGHT", cell, "RIGHT", -1, 0)
							line:SetHeight(lineHeight)
							line.icon:SetSize(iconSize, iconSize)
						end
					end
				end
			end
			frame:SetScript("OnSizeChanged", function() handle:Layout() end)

			function handle:Apply()
				local font = Font()
				local owner = B:IsExternal() and "Clique owns live clicks. These saved bindings are inactive while Clique is loaded."
					or "Drop a spell or macro from your spellbook, action bars or macro window onto a friendly (F) or hostile (H)"
						.. " line, or click a line to edit it. All bindings are applied on mouse release."
				local errors = CG.bindingErrors or {}
				note:SetFontObject(font)
				note:SetText(owner .. "\nSpecialization: " .. CG.Config:SpecKey() .. (CG.pending and " — changes pending until combat ends" or "")
					.. (#errors > 0 and "\n" .. errors[1] .. (#errors > 1 and " (and " .. (#errors - 1) .. " more inactive bindings)" or "") or "")
					.. (self.message and "\n|cffff5a4d" .. self.message .. "|r" or ""))
				for _, label in ipairs(self.columns) do label:SetFontObject(font) end
				for _, label in ipairs(self.rows) do label:SetFontObject(font) end
				local all = UF.Schema.Resolve(B.schema, CG.Config:GetBindings())
				for row, modifier in ipairs(B.modifiers) do
					for column in ipairs(B.buttons) do
						local cell = self.cells[row .. ":" .. column]
						local selected = editor.button == column and editor.modifier == modifier[1]
						cell:SetBackdropBorderColor(unpack(UF.Skin.colors[selected and "accent" or "border"]))
						for _, reaction in ipairs(REACTIONS) do
							local line, choice = cell.lines[reaction.key], all["button" .. column][modifier[1]][reaction.key]
							local info = B:Describe(choice)
							line.info = info
							line.tag:SetFontObject(font)
							line.tag:SetText(reaction.tag)
							line.icon:SetTexture(info.icon)
							line.icon:SetDesaturated(info.inactive == true)
							line.name:SetFontObject(font)
							line.name:SetText(info.name)
							local color = info.inactive and UF.Skin.colors.warning
								or choice.action == "none" and UF.Skin.colors.textDim or UF.Skin.colors.text
							line.name:SetTextColor(color[1], color[2], color[3])
						end
					end
				end
				self:Layout()
			end
			function handle:Release()
				self.released = true
				frame:SetScript("OnSizeChanged", nil)
				for _, cell in pairs(self.cells) do
					for _, line in pairs(cell.lines) do
						for _, script in ipairs({ "OnReceiveDrag", "OnClick", "OnEnter", "OnLeave" }) do line:SetScript(script, nil) end
					end
				end
				frame:Hide()
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
					-- Saved changes redraw the grid through their config event.
					if not ok or path == "button" or path == "modifier" then handle:Apply() end
					return ok, reason
				end,
				resolved = Selected }
		end,
		reset = function() CG.Config.bindings:Reset() end,
	})
end
