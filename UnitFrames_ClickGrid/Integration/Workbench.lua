local _, CG = ...
local UF = CG.UF

local function RefreshPreview(handle)
	handle:Apply()
	UF.Workbench:UpdateData()
end

local function Report(ok, reason)
	if not ok then CG:Print(reason) end
end

local function StyleTarget(handle, kind)
	return {
		schema = CG.styleSchemas[kind],
		get = function(path) return UF.Util.GetPath(CG.Config:GetStyle(kind), path) end,
		set = function(path, value) Report(CG.Config:SetStyle(kind, path, value)); RefreshPreview(handle) end,
		resolved = function() return UF.Schema.Resolve(CG.styleSchemas[kind], CG.Config:GetStyle(kind), UF.Config:GetTheme()) end,
	}
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
		},
		update = function(handle, values) handle:ShowData(values) end,
		tick = function(handle, values, _, elapsed) handle.data = values; handle:Tick(elapsed) end,
	}
	local function Create(stage) return CG.Preview:New(stage) end
	wb:Register({ id = "clickgrid.panel", name = "Panel & indicators", category = "ClickGrid", autoSize = true, fitToStage = true,
		size = { 500, 500 }, create = Create, data = data,
		styleTarget = function(handle)
			return { schema = CG.Config.schema,
				get = function(path) return UF.Util.GetPath(CG.Config:Get(), path) end,
				set = function(path, value) Report(CG.Config:Set(path, value)); RefreshPreview(handle) end,
				resolved = function() return CG.Config:Resolved() end }
		end,
		reset = function() CG.Config.db.profile.settings = {}; CG:RequestRefresh(); UF.Events:Fire("ClickGridConfigChanged") end,
	})
	for _, kind in ipairs({ "member", "target" }) do
		local styleKind = kind
		wb:Register({ id = "clickgrid." .. styleKind, name = styleKind == "member" and "Member bars" or "Target bars",
			category = "ClickGrid", autoSize = true, fitToStage = true, size = { 500, 500 }, create = Create, data = data,
			styleTarget = function(handle) return StyleTarget(handle, styleKind) end,
			reset = function() CG.Config.db.profile[styleKind] = {}; CG:RequestRefresh(); UF.Events:Fire("ClickGridConfigChanged") end,
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
	local schema = {
		{ key = "button", type = "select", label = "Mouse button", default = 1, values = buttonValues },
		{ key = "modifier", type = "select", label = "Modifiers", default = "none", values = modifierValues },
		{ key = "friendly", type = "group", label = "Friendly unit", schema = B.actionSchema },
		{ key = "hostile", type = "group", label = "Hostile unit", schema = B.actionSchema },
	}
	local function Selected()
		local all = UF.Schema.Resolve(B.schema, CG.Config:GetBindings())
		local selected = UF.Util.Copy(all["button" .. editor.button][editor.modifier])
		selected.button, selected.modifier = editor.button, editor.modifier
		return selected
	end
	wb:Register({ id = "clickgrid.bindings", name = "Click spells", category = "ClickGrid", autoSize = true,
		size = { 700, 350 },
		create = function(stage)
			local handle = { frame = CreateFrame("Frame", nil, stage), buttons = {} }
			handle.frame:SetSize(700, 350)
			local note = handle.frame:CreateFontString(nil, "OVERLAY")
			note:SetFontObject(UF.Media:GetFontObject(UF.Config:GetTheme().font, 11, ""))
			note:SetPoint("TOPLEFT", 0, 0)
			note:SetWidth(700)
			note:SetJustifyH("LEFT")
			function handle:Apply()
				local owner = B:IsExternal() and "Clique owns live clicks. These saved bindings are inactive while Clique is loaded."
					or "Click a cell, then choose friendly/hostile actions in settings. All bindings are applied on mouse release."
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
								wb:Select("clickgrid.bindings")
							end })
							button:SetSize(136, 30)
							button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (column - 1) * 140, -90 - (row - 1) * 32)
							self.buttons[key] = button
						end
						local choice = all["button" .. column][modifier[1]].friendly
						button:SetText(name .. " / " .. modifier[2] .. "\n" .. (choice.action == "spell" and choice.spell or choice.action))
					end
				end
			end
			function handle:Release()
				for _, button in pairs(self.buttons) do
					button:GetFrame():SetScript("OnClick", nil)
					button:Hide()
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
					return UF.Util.GetPath(CG.Config:GetBindings(), "button" .. editor.button .. "." .. editor.modifier .. "." .. path)
				end,
				set = function(path, value)
					if path == "button" or path == "modifier" then editor[path] = value or (path == "button" and 1 or "none")
					else
						local reaction, field = path:match("^(%w+)%.(%w+)$")
						Report(CG.Config:SetBinding(editor.button, editor.modifier, reaction, field, value))
					end
					handle:Apply()
				end,
				resolved = Selected }
		end,
		reset = function()
			CG.Config.db.char.loadouts[CG.Config:SpecKey()] = {}
			CG:RequestRefresh()
			UF.Events:Fire("ClickGridConfigChanged", "bindings")
		end,
	})
end

UF.Events.RegisterCallback(CG.Preview, "ClickGridConfigChanged", function()
	local wb = UF.Workbench
	if wb and wb.handle and wb.entry and wb.entry.category == "ClickGrid" then
		wb.handle:Apply()
		if wb.inspector then wb.inspector:Refresh() end
	end
end)
