# Design: ClickGrid spell and macro input

Status: draft; no implementation. Targets Forever Interface 16001 and Lua 5.1.
Product assumption pending feedback: existing macros run as written.

## Goal and interaction

Replace the spell-name-only editing experience with a drop target displaying
an action icon, name and validation state. Keep manual spell ID/name entry as
an alternative. Users select a mouse button and modifier, then drop into an
explicit **Friendly** or **Hostile** action slot. Never infer the destination
from whether a spell appears helpful or harmful.

Provide Spellbook and Macros buttons next to these slots. Dropping a supported
action replaces that slot in one settings-store operation. Clear removes its
action; it does not delete the spell or macro. Invalid drops leave both the
previous binding and cursor untouched. Clear the cursor only after a successful
save. A click with a loaded cursor should follow the same path as a drag drop.

The matrix should show both reaction bindings, including icons and inactive
states; it currently summarises only the friendly action. It remains a settings
surface, not a secure button on which dropping an action casts it.

## Existing implementation and verified client paths

- `UnitFrames_ClickGrid/Bindings/Compiler.lua`: action schema, spell resolution,
  complete secure-attribute plans, application outside combat and Clique ownership.
- `UnitFrames_ClickGrid/Integration/Workbench.lua`: matrix and selected-binding
  inspector. `Core/Config.lua`: specialization-scoped binding store and updates.
- `examples/wow-ui-source-forever/Interface/AddOns/Blizzard_ClickBindingUI/Blizzard_ClickBindingUI.lua`:
  `AddFromCursorInfo` reads the spell ID from the fourth `GetCursorInfo()` return
  for a `spell` payload and the macro index from the second for `macro`.
  Pet actions have a separate payload; they are not implicitly supported here.
- `Blizzard_FrameXML/SecureTemplates.lua` in that checkout: `SECURE_ACTIONS.macro`
  reads the modified `macro` attribute and invokes `RunMacro`. This is the
  existing-macro path; no generated macro body is needed.
- `Blizzard_FrameXMLUtil/Mainline/PlayerSpellsUtil.lua` provides
  `PlayerSpellsUtil.ToggleSpellBookFrame()`; `Blizzard_MacroUI/Blizzard_MacroUI_Bootstrap.lua`
  provides `ShowMacroFrame()` with lazy loading. Verify their availability via
  capabilities and their behaviour from this settings UI in the actual client.

Do not modify Blizzard's click-binding configuration or action bars. Reuse
the cursor payload convention with ClickGrid's own secure compiler.

## Data and resolution

Preserve existing `{ action = "spell", spell = "ID or localized name" }`
settings. New spell drops save the numeric spell ID as text in that field;
localized name/icon are display metadata resolved from the client. Preserve
the dropped ID as intent and resolve specialization overrides at compile time.
Unknown or currently unlearned spells remain saved but inactive, as today.

Add `action = "macro"` and a schema group containing `scope` (account or
character) and `name`. The dropped index is used to inspect the macro, not as
a durable identity: indices can move. Resolve by exact name within scope;
zero or multiple matches leave the binding inactive with a useful message.
Editing a uniquely named macro's body updates its behaviour; renaming requires
re-dropping it. This tradeoff is explicit because macros lack a stable identity
in the paths inspected here. Do not guess by old index or macro body.

Listen for `UPDATE_MACROS` and reuse existing spec/spell refresh handling.
Re-resolve macro references before compiling. Do not execute macros to validate
them. Warn that macro targeting follows its own text: binding a macro to a
unit button does not rewrite its commands to target that unit. A common
mouseover macro can be shown as explanatory text, but never inserted silently.

The compiled plan must clear both ordinary and reaction-remapped `macro`,
`macrotext`, `spell` and action attributes when switching types or clearing a
slot. Current cleanup of ordinary button keys alone is insufficient once
reaction-specific macros exist. Preserve mouse-release activation, modifiers,
friendly/hostile remapping and external Clique ownership.

## Widgets, combat and lifecycle

Implement the reusable visual drop control as a `Widget`, using the shared
settings toolkit. Inject cursor decoding and validation callbacks from
ClickGrid; the widget does not write secure attributes. Commit an entire action
group through the binding store, avoiding intermediate action/argument states.
Keep display metadata out of persistent config.

Saved edits may continue in combat with the existing pending-change notice;
secure attributes apply through the established out-of-combat refresh path.
Disable spellbook/macro opener buttons in combat for v1 rather than queuing an
unexpected window opening. Macro edits can affect an already active macro
independently of ClickGrid's pending changes; the UI must not imply otherwise.
Release unregisters listeners and drops callbacks; changing the selected cell
must not leave a drop callback pointing at the previous selection.

## Delivery and verification

1. Add cursor decoding and spell drops while retaining text input and existing
   compiler semantics. Add opener controls and friendly/hostile summaries.
2. Add macro references, resolution, compiler support and macro refresh events.
3. Add focused regressions to `clickgrid_spec` and
   `clickgrid_preview_lifecycle_spec`: success/rejection and cursor clearing,
   atomic replacement, modifier/reaction targeting, scope/duplicate/rename/delete
   cases, action transitions, spec changes, pending combat updates and Clique.
   Extend the API snapshot/mock from verified client source where needed.
4. Run the full suite and Workbench filter. In game test actual spellbook,
   action-bar and macro drops, lazy-loaded openers, macro targeting, combat,
   profile switching, unit replacement and repeated entry release/reopening.

V1 excludes item/pet-action drops, creating/editing macro bodies, automatic
macro-target rewriting and dragging actions out of the editor. If forced
clicked-unit targeting is requested, design it separately before implementation.
