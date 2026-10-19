local _, CG = ...
local UF = CG.UF
local B = { modifiers = {
	{ "none", "None", "" }, { "shift", "Shift", "shift-" }, { "ctrl", "Ctrl", "ctrl-" },
	{ "alt", "Alt", "alt-" }, { "ctrlshift", "Ctrl + Shift", "ctrl-shift-" },
	{ "altshift", "Alt + Shift", "alt-shift-" }, { "altctrl", "Alt + Ctrl", "alt-ctrl-" },
	{ "altctrlshift", "Alt + Ctrl + Shift", "alt-ctrl-shift-" },
}, buttons = { "Left", "Right", "Middle", "Button 4", "Button 5" } }
CG.Bindings = B
B.actions = {
	{ "none", "Unbound" }, { "spell", "Cast spell" }, { "macro", "Run macro" }, { "target", "Target" },
	{ "assist", "Assist" }, { "focus", "Focus" }, { "togglemenu", "Unit menu" },
}
B.actionSchema = {
	{ key = "action", type = "select", label = "Action", values = B.actions, default = "none" },
	{ key = "spell", type = "text", label = "Spell ID or localized name", default = "",
		hidden = function(c) return c.action ~= "spell" end },
	{ key = "macro", type = "text", label = "Macro name", default = "",
		hidden = function(c) return c.action ~= "macro" end },
}
B.schema = {}
for button, name in ipairs(B.buttons) do
	local modifiers = {}
	for _, modifier in ipairs(B.modifiers) do
		local actions = {}
		for _, reaction in ipairs({ "friendly", "hostile" }) do
			actions[#actions + 1] = { key = reaction, type = "group", label = reaction, schema = B.actionSchema,
				defaults = { action = modifier[1] == "none" and (button == 1 and "target" or button == 2 and "togglemenu" or "none") or "none" } }
		end
		modifiers[#modifiers + 1] = { key = modifier[1], type = "group", label = modifier[2], schema = actions }
	end
	B.schema[#B.schema + 1] = { key = "button" .. button, type = "group", label = name, schema = modifiers }
end

function B:ResolveSpell(text)
	text = strtrim(text)
	if text == "" or not CG.Caps.spellInfo or not CG.Caps.spellKnown then return nil, "Unknown or unavailable spell" end
	local info = C_Spell.GetSpellInfo(tonumber(text) or text)
	if not info or issecretvalue(info.name) or issecretvalue(info.spellID) then return nil, "Spell information unavailable" end
	local id = info.spellID
	if CG.Caps.spellOverride then id = C_Spell.GetOverrideSpell(id) end
	if issecretvalue(id) then return nil, "Spell override unavailable" end
	local known = C_SpellBook.IsSpellKnown(id)
	if issecretvalue(known) or not known then return nil, "Not learned in this specialization" end
	return id
end

-- Macros are stored by name: indices shift when macros are created or
-- deleted. Account macros come first, then character macros from
-- MAX_ACCOUNT_MACROS + 1, as in Blizzard's macro UI. Same names: first wins.
function B:FindMacro(name)
	name = strtrim(name or "")
	if name == "" or not CG.Caps.macros then return nil end
	local account, character = GetNumMacros()
	local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
	for index = 1, account do
		if GetMacroInfo(index) == name then return index end
	end
	for index = base + 1, base + character do
		if GetMacroInfo(index) == name then return index end
	end
end

function B:ResolveMacro(name)
	local index = self:FindMacro(name)
	if not index then return nil, "Macro not found" end
	return index
end

-- Spells and macros dropped from the spellbook, action bars or macro window,
-- following Blizzard's click-binding UI (AddFromCursorInfo): the spell ID is
-- the fourth return, the macro index the second. The spell ID is saved as
-- text, the same intent typed IDs have; overrides still resolve at compile
-- time. Returns nil, nil when the cursor is empty.
function B:DecodeCursor()
	if not CG.Caps.cursor then return nil, "Dropping actions is unavailable in this client" end
	local kind, info, _, spellID = GetCursorInfo()
	if kind == nil then return nil end
	if kind == "macro" then
		local name = CG.Caps.macros and type(info) == "number" and GetMacroInfo(info)
		if not name then return nil, "Macro information unavailable" end
		return { action = "macro", macro = name }
	end
	if kind ~= "spell" then return nil, "Only spells and macros can be dropped here" end
	if issecretvalue(spellID) or type(spellID) ~= "number" then return nil, "Spell information unavailable" end
	return { action = "spell", spell = tostring(spellID) }
end

local ACTION_NAMES = {}
for _, action in ipairs(B.actions) do ACTION_NAMES[action[1]] = action[2] end

-- Shown metadata for one action group; never stored in the config.
function B:Describe(choice)
	if choice.action == "macro" then
		local name = strtrim(choice.macro or "")
		local index, reason = self:ResolveMacro(name)
		local icon = index and select(2, GetMacroInfo(index))
		return { name = name ~= "" and name or "No macro", icon = icon, inactive = index == nil,
			status = reason or "Macro" }
	end
	if choice.action ~= "spell" then
		return { name = choice.action == "none" and "Unbound" or ACTION_NAMES[choice.action] or choice.action,
			status = choice.action == "none" and "Drop a spell or macro here" or "Unit action" }
	end
	local text = strtrim(choice.spell or "")
	local described = { name = text ~= "" and text or "No spell" }
	local info = text ~= "" and CG.Caps.spellInfo and C_Spell.GetSpellInfo(tonumber(text) or text)
	if info and not issecretvalue(info.name) and not issecretvalue(info.iconID) then
		described.name, described.icon = info.name, info.iconID
	end
	local id, reason = self:ResolveSpell(text)
	described.inactive = id == nil
	described.status = reason or "Active"
	if id and info and not issecretvalue(info.spellID) and id ~= info.spellID then
		local override = C_Spell.GetSpellInfo(id)
		if override and not issecretvalue(override.name) then described.status = "Active as " .. override.name end
	end
	return described
end

-- A complete plan includes nil removals, including wildcard oUF defaults.
-- Never choose an action from live health, aura, range or cooldown values.
function B:Compile(config)
	local resolved = UF.Schema.Resolve(self.schema, config)
	local plan, errors = {}, {}
	local function Set(key, value) plan[#plan + 1] = { key = key, value = value } end
	Set("*type1", nil)
	Set("*type2", nil)
	Set("checkselfcast", false)
	Set("checkfocuscast", false)
	for button = 1, #self.buttons do
		for _, modifier in ipairs(self.modifiers) do
			local prefix, cfg = modifier[3], resolved["button" .. button][modifier[1]]
			-- helpbutton/harmbutton are always set below: each key appears once.
			for _, name in ipairs({ "type", "spell", "macro", "macrotext", "item" }) do
				Set(prefix .. name .. button, nil)
			end
			for _, reaction in ipairs({ "friendly", "hostile" }) do
				local suffix = (reaction == "friendly" and "heal" or "harm") .. button
				local remap = reaction == "friendly" and "helpbutton" or "harmbutton"
				Set(prefix .. remap .. button, suffix)
				local action, spell, macro, reason = cfg[reaction].action, nil, nil, nil
				if action == "spell" then
					spell, reason = self:ResolveSpell(cfg[reaction].spell)
				elseif action == "macro" then
					macro, reason = self:ResolveMacro(cfg[reaction].macro)
				end
				if reason then
					errors[#errors + 1] = self.buttons[button] .. " / " .. modifier[2] .. " / " .. reaction .. ": " .. reason
					action = "none"
				end
				Set(prefix .. "type-" .. suffix, action ~= "none" and action or nil)
				Set(prefix .. "spell-" .. suffix, spell)
				Set(prefix .. "macro-" .. suffix, macro)
			end
		end
	end
	return plan, errors
end

-- What each frame was last given, kept off the secure frames. A plan sets
-- several hundred attributes, most of them removals; only changed ones are
-- written, so one edit does not rewrite every binding on every frame. A
-- removal the frame has never had is recorded without a write.
local applied = setmetatable({}, { __mode = "k" })
local NIL = {}

function B:Apply(frame, plan)
	assert(not InCombatLockdown(), "Click bindings must be applied outside combat")
	local last = applied[frame]
	if not last then
		last = {}
		applied[frame] = last
		frame:RegisterForClicks("AnyUp")
	end
	for _, attribute in ipairs(plan) do
		local value = attribute.value
		if value == nil then value = NIL end
		local previous = last[attribute.key]
		if previous == nil and value == NIL and frame:GetAttribute(attribute.key) == nil then
			last[attribute.key] = NIL
		elseif previous ~= value then
			frame:SetAttribute(attribute.key, attribute.value)
			last[attribute.key] = value
		end
	end
end

function B:IsExternal()
	-- oUF integrates Clique at secure-header creation. Respect that ownership
	-- rather than fighting its registrations or changing a shared global.
	return Clique ~= nil
end
