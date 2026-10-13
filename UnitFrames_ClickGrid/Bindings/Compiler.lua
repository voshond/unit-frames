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
	{ "none", "Unbound" }, { "spell", "Cast spell" }, { "target", "Target" },
	{ "assist", "Assist" }, { "focus", "Focus" }, { "togglemenu", "Unit menu" },
}
B.actionSchema = {
	{ key = "action", type = "select", label = "Action", values = B.actions, default = "none" },
	{ key = "spell", type = "text", label = "Spell ID or localized name", default = "",
		hidden = function(c) return c.action ~= "spell" end },
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

-- Spells dropped from the spellbook or action bars, following Blizzard's
-- click-binding UI (AddFromCursorInfo): the spell ID is the fourth return.
-- The ID is saved as text, the same intent typed IDs have; overrides still
-- resolve at compile time. Returns nil, nil when the cursor is empty.
function B:DecodeCursor()
	if not CG.Caps.cursor then return nil, "Dropping actions is unavailable in this client" end
	local kind, _, _, spellID = GetCursorInfo()
	if kind == nil then return nil end
	if kind ~= "spell" then return nil, "Only spells can be dropped here" end
	if issecretvalue(spellID) or type(spellID) ~= "number" then return nil, "Spell information unavailable" end
	return { action = "spell", spell = tostring(spellID) }
end

local ACTION_NAMES = {}
for _, action in ipairs(B.actions) do ACTION_NAMES[action[1]] = action[2] end

-- Shown metadata for one action group; never stored in the config.
function B:Describe(choice)
	if choice.action ~= "spell" then
		return { name = choice.action == "none" and "Unbound" or ACTION_NAMES[choice.action] or choice.action,
			status = choice.action == "none" and "Drop a spell here, or click with one on the cursor" or "Unit action" }
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
			for _, name in ipairs({ "type", "spell", "macro", "macrotext", "item", "helpbutton", "harmbutton" }) do
				Set(prefix .. name .. button, nil)
			end
			for _, reaction in ipairs({ "friendly", "hostile" }) do
				local suffix = (reaction == "friendly" and "heal" or "harm") .. button
				local remap = reaction == "friendly" and "helpbutton" or "harmbutton"
				Set(prefix .. remap .. button, suffix)
				local action, spell = cfg[reaction].action, nil
				if action == "spell" then
					local reason
					spell, reason = self:ResolveSpell(cfg[reaction].spell)
					if not spell then
						errors[#errors + 1] = self.buttons[button] .. " / " .. modifier[2] .. " / " .. reaction .. ": " .. reason
						action = "none"
					end
				end
				Set(prefix .. "type-" .. suffix, action ~= "none" and action or nil)
				Set(prefix .. "spell-" .. suffix, spell)
			end
		end
	end
	return plan, errors
end

function B:Apply(frame, plan)
	assert(not InCombatLockdown(), "Click bindings must be applied outside combat")
	for _, attribute in ipairs(plan) do frame:SetAttribute(attribute.key, attribute.value) end
	frame:RegisterForClicks("AnyUp")
end

function B:IsExternal()
	-- oUF integrates Clique at secure-header creation. Respect that ownership
	-- rather than fighting its registrations or changing a shared global.
	return Clique ~= nil
end
