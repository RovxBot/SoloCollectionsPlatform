local addon = assert(arg[1])
local record = { id = 100001, collected = true, actionable = true, draggable = true,
    canonicalActionSpellId = 60025, icon = "Interface\\Icons\\Mount" }
local ready, combat, calls, notices, picked = true, false, {}, {}, {}
local macros = {}
local accountCount, characterCount = 0, 0

SoloCollections = {
    Localize = function(enUS) return enUS end,
    CollectionState = { GetCategoryState = function() return ready and "Ready" or "Loading" end },
    Catalog = { Get = function() return { record } end },
    Bridge = {
        SummonMount = function(id, callback)
            calls[#calls + 1] = id
            callback(true, "ACCEPTED")
            return true
        end,
        SummonRandomMount = function(callback)
            calls[#calls + 1] = "random"
            callback(true, "ACCEPTED")
            return true
        end,
    },
}
UIErrorsFrame = { AddMessage = function(_, text) notices[#notices + 1] = text end }
InCombatLockdown = function() return combat end
GetNumMacros = function() return accountCount, characterCount end
GetMacroInfo = function(index)
    local macro = macros[index]
    if macro then return macro.name, macro.icon, macro.body end
end
GetSpellInfo = function() return "Shared Mount" end
GetNumMacroIcons = function() return 2 end
GetMacroIconInfo = function(index) return index == 2 and record.icon or "QuestionMark" end
CreateMacro = function(name, icon, body, perCharacter)
    assert(not combat)
    local index
    if perCharacter then
        characterCount = characterCount + 1
        index = 36 + characterCount
    else
        accountCount = accountCount + 1
        index = accountCount
    end
    macros[index] = { name = name, icon = icon, body = body }
    return index
end
PickupMacro = function(index) picked[#picked + 1] = index end
PickupCompanion = function() error("Shared mount drag must not depend on a learned companion") end

dofile(addon .. "/Core/MountActions.lua")
local actions = SoloCollections.MountActions
assert(actions.Pickup(record.id))
assert(accountCount == 1 and characterCount == 0 and picked[1] == 1)
assert(macros[1].icon == 2 and #calls == 0, "Dragging must not cast")
macros[1].name = "Renamed by player"
macros[1].body = macros[1].body .. "\n \n"
assert(actions.Pickup(record.id) and accountCount == 1, "Repeated drag must reuse its macro")

-- Recreate the AddOn state as on another character; no native mount spell is known.
dofile(addon .. "/Core/MountActions.lua")
actions = SoloCollections.MountActions
assert(actions.Pickup(record.id) and accountCount == 1, "Another character must reuse the shortcut")
local action = assert(macros[1].body:match("/run ([^\n]+)"))
assert((loadstring or load)(action))()
assert(calls[1] == record.id, "The action must send the stable collection ID")
record.collected = false
assert(not actions.Pickup(record.id))
assert(not actions.Summon(record.id) and #calls == 1, "A stale shortcut cannot authorize ownership")
record.collected = true
ready = false
assert(not actions.Pickup(record.id))
ready = true
record.draggable = false
assert(not actions.Pickup(record.id))
record.draggable = true
assert(not actions.Pickup(999999))
combat = true
assert(not actions.Pickup(record.id) and accountCount == 1)
combat = false
accountCount = 36
assert(actions.PickupRandom() and characterCount == 1 and picked[#picked] == 37)
assert(actions.PickupRandom() and characterCount == 1)
assert(actions.SummonRandom() and calls[#calls] == "random")
characterCount = 18
record.id = 100002
local before = #picked
assert(not actions.Pickup(record.id) and #picked == before and #notices > 0)
assert(macros[1].name == "Renamed by player", "Never overwrite an existing macro")

-- DragonUI's cached native index may be absent or stale; both use the same helper.
record.id = 100001
DragonUI = { Collections = {} }
SoloCollections.ToggleJournal = function() end
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
dofile(addon .. "/UI/DragonUI/CollectionsBridge.lua")
assert(DragonUI.Collections.Drag("MOUNT", {
    scAccountCollection = true, collectionId = record.id, nativeIndex = 999,
}))
assert(picked[#picked] == 1)
local nativeIndex
PickupCompanion = function(_, index) nativeIndex = index end
DragonUI.Collections.Drag("MOUNT", { index = 7 })
assert(nativeIndex == 7, "Native class mounts retain their native action")
print("Mount shortcut behavior passed")
