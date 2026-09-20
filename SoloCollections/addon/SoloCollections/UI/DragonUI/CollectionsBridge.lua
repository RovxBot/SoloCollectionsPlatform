-- Present the account-authoritative SoloCollections mount and companion state
-- in DragonUI's existing Pets & Mounts journal.  DragonUI owns the window,
-- microbar button and visual behaviour; this adapter only replaces the
-- character-local companion API projection once the SC2 snapshot is ready.
local SC = SoloCollections
local Catalog = SC.Catalog
local State = SC.CollectionState
local Bridge = SC.Bridge
local DragonUI = _G.DragonUI
local CO = DragonUI and DragonUI.Collections

if not (Catalog and State and Bridge and CO) or CO.scAccountCollectionsBridge then
    return
end

CO.scAccountCollectionsBridge = true
SC.DragonUICollectionsBridge = true

local CATEGORY_BY_KIND = { MOUNT = "MOUNTS", CRITTER = "PETS" }
local TYPE_BY_KIND = { MOUNT = 10, CRITTER = 11 }
local FAVORITE_TYPE_BY_KIND = { MOUNT = 16, CRITTER = 17 }
local SOURCE_OFFSET = 1 -- SoloCollections uses 0-based source types; DragonUI uses 1-based values.

local original = {
    List = CO.List,
    CollectedCount = CO.CollectedCount,
    Find = CO.Find,
    Active = CO.Active,
    IsFavorite = CO.IsFavorite,
    ToggleFavorite = CO.ToggleFavorite,
    Summon = CO.Summon,
    SummonRandomFavorite = CO.SummonRandomFavorite,
    SourceIndex = CO.SourceIndex,
}

local originalToggleJournal = SC.ToggleJournal
function SC:ToggleJournal()
    if DragonUI and type(DragonUI.ToggleCollections) == "function" then
        return DragonUI.ToggleCollections()
    end
    return originalToggleJournal(self)
end

local cache = {
    MOUNT = { entries = nil, byCollectionId = {}, sourceBySpell = {} },
    CRITTER = { entries = nil, byCollectionId = {}, sourceBySpell = {} },
}
local favoriteOverrides = { MOUNT = {}, CRITTER = {} }

local function categoryFor(kind)
    return CATEGORY_BY_KIND[kind]
end

local function accountStateReady(kind)
    local category = categoryFor(kind)
    return category and State.GetCategoryState and State.GetCategoryState(category) == "Ready"
end

local function invalidate(kind)
    if kind then
        cache[kind].entries = nil
        cache[kind].byCollectionId = {}
        cache[kind].sourceBySpell = {}
        return
    end
    invalidate("MOUNT")
    invalidate("CRITTER")
end

local function nativeBySpell(kind)
    local result = {}
    if type(GetNumCompanions) ~= "function" or type(GetCompanionInfo) ~= "function" then
        return result
    end
    for index = 1, (GetNumCompanions(kind) or 0) do
        local creatureId, name, spellId, icon, active = GetCompanionInfo(kind, index)
        spellId = tonumber(spellId)
        if creatureId and spellId then
            result[spellId] = {
                index = index,
                creatureId = creatureId,
                name = name,
                icon = icon,
                active = active and true or false,
            }
        end
    end
    return result
end

local function visibleName(value)
    return type(value) == "string" and value ~= "" and value ~= "?"
end

local function companionName(record, companion, spellId, fallback)
    if record and visibleName(record.name) then return record.name end
    if companion and visibleName(companion.name) then return companion.name end
    if type(GetSpellInfo) == "function" then
        local name = GetSpellInfo(spellId)
        if visibleName(name) then return name end
    end
    return fallback
end

local function accountEntries(kind)
    local kindCache = cache[kind]
    if kindCache.entries then
        return kindCache.entries
    end

    local category = categoryFor(kind)
    local native = nativeBySpell(kind)
    local entries = {}
    local byCollectionId = {}
    local sourceBySpell = {}
    local catalogSpellIds = {}
    for _, record in ipairs(Catalog.Get(category) or {}) do
        local collectionId = tonumber(record.id)
        local spellId = tonumber(record.spellId or record.canonicalActionSpellId)
        if collectionId and spellId then
            local localCompanion = native[spellId]
            local icon = record.icon or (localCompanion and localCompanion.icon)
            if not icon and GetSpellInfo then
                local _, _, spellIcon = GetSpellInfo(spellId)
                icon = spellIcon
            end
            local entry = {
                -- DragonUI uses index as its collected/actionable marker.  The
                -- stable collection id deliberately takes that role here; all
                -- actions below route through the SC2 bridge rather than the
                -- legacy index-based companion API.
                index = record.collected and collectionId or nil,
                nativeIndex = localCompanion and localCompanion.index or nil,
                collectionId = collectionId,
                creatureID = collectionId,
                previewCreatureID = record.previewCreatureEntry or
                    (localCompanion and localCompanion.creatureId),
                name = companionName(record, localCompanion, spellId, "Collection #" .. collectionId),
                spellID = spellId,
                icon = icon,
                active = localCompanion and localCompanion.active or false,
                scAccountCollection = true,
                scCollected = record.collected and true or false,
            }
            entries[#entries + 1] = entry
            byCollectionId[collectionId] = entry
            sourceBySpell[spellId] = (tonumber(record.sourceType) or 11) + SOURCE_OFFSET
            catalogSpellIds[spellId] = true
            if favoriteOverrides[kind][collectionId] == nil then
                favoriteOverrides[kind][collectionId] = record.favorite and true or false
            end
        end
    end

    -- Class summons are intentionally excluded from the account catalog: they
    -- are character-native spells rather than account rewards.  DragonUI
    -- should still display the class mounts that the client exposes, such as
    -- a Paladin's Summon Warhorse, and leave their actions to the native API.
    for spellId, companion in pairs(native) do
        if not catalogSpellIds[spellId] then
            entries[#entries + 1] = {
                index = companion.index,
                nativeIndex = companion.index,
                creatureID = companion.creatureId,
                previewCreatureID = companion.creatureId,
                name = companionName(nil, companion, spellId, "Companion #" .. spellId),
                spellID = spellId,
                icon = companion.icon,
                active = companion.active,
                scAccountCollection = false,
                scCollected = true,
            }
        end
    end

    table.sort(entries, function(left, right)
        if (left.index ~= nil) ~= (right.index ~= nil) then
            return left.index ~= nil
        end
        return tostring(left.name or "") < tostring(right.name or "")
    end)
    kindCache.entries = entries
    kindCache.byCollectionId = byCollectionId
    kindCache.sourceBySpell = sourceBySpell
    return entries
end

function CO.List(kind)
    if not accountStateReady(kind) then
        return original.List(kind)
    end
    return accountEntries(kind)
end

function CO.CollectedCount(kind)
    if not accountStateReady(kind) then
        return original.CollectedCount(kind)
    end
    local count = 0
    for _, entry in ipairs(CO.List(kind)) do
        if entry.index then count = count + 1 end
    end
    return count
end

function CO.Find(kind, spellId)
    if not accountStateReady(kind) then
        return original.Find(kind, spellId)
    end
    spellId = tonumber(spellId)
    for _, entry in ipairs(CO.List(kind)) do
        if entry.spellID == spellId then return entry end
    end
    return nil
end

function CO.Active(kind)
    if not accountStateReady(kind) then
        return original.Active(kind)
    end
    for _, entry in ipairs(CO.List(kind)) do
        if entry.active then return entry end
    end
    return nil
end

function CO.IsFavorite(kind, collectionId)
    if not accountStateReady(kind) then
        return original.IsFavorite(kind, collectionId)
    end
    collectionId = tonumber(collectionId)
    if not collectionId or not cache[kind].byCollectionId[collectionId] then
        return original.IsFavorite(kind, collectionId)
    end
    return favoriteOverrides[kind][collectionId] == true
end

local function refreshJournalSoon()
    if CO.RefreshJournal then CO.RefreshJournal() end
end

local function reportActionFailure(kind, reason)
    local prefix = kind == "MOUNT" and "Mount action failed: " or "Pet action failed: "
    local message = prefix .. tostring(reason or "UNKNOWN")
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.35, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. message)
    end
end

function CO.ToggleFavorite(kind, collectionId)
    if not accountStateReady(kind) then
        return original.ToggleFavorite(kind, collectionId)
    end
    collectionId = tonumber(collectionId)
    local entry = collectionId and cache[kind].byCollectionId[collectionId]
    if not entry then
        return original.ToggleFavorite(kind, collectionId)
    end
    if not (entry and entry.scCollected) then return false end
    if not (Bridge.GetCategoryState and Bridge.GetCategoryState(FAVORITE_TYPE_BY_KIND[kind]) == "Ready") then
        reportActionFailure(kind, "FAVORITES_SYNCING")
        return false
    end
    local wanted = not CO.IsFavorite(kind, collectionId)
    favoriteOverrides[kind][collectionId] = wanted
    refreshJournalSoon()
    local setFavorite = kind == "MOUNT" and Bridge.SetMountFavorite or Bridge.SetPetFavorite
    if type(setFavorite) ~= "function" then
        favoriteOverrides[kind][collectionId] = nil
        reportActionFailure(kind, "BRIDGE_UNAVAILABLE")
        refreshJournalSoon()
        return false
    end
    setFavorite(collectionId, wanted, function(ok, reason)
        if not ok then
            favoriteOverrides[kind][collectionId] = nil
            reportActionFailure(kind, reason)
        end
        refreshJournalSoon()
    end)
    return wanted
end

function CO.Summon(kind, entry)
    if not (entry and entry.scAccountCollection and accountStateReady(kind)) then
        return original.Summon(kind, entry)
    end
    if not entry.scCollected then return end
    local summon = kind == "MOUNT" and Bridge.SummonMount or Bridge.SummonPet
    if type(summon) ~= "function" then
        reportActionFailure(kind, "BRIDGE_UNAVAILABLE")
        return
    end
    summon(entry.collectionId, function(ok, reason)
        if not ok then reportActionFailure(kind, reason) end
        invalidate(kind)
        refreshJournalSoon()
    end)
end

function CO.SummonRandomFavorite(kind)
    if not accountStateReady(kind) then
        return original.SummonRandomFavorite(kind)
    end
    local summon = kind == "MOUNT" and Bridge.SummonRandomMount or Bridge.SummonRandomPet
    if type(summon) ~= "function" then
        reportActionFailure(kind, "BRIDGE_UNAVAILABLE")
        return
    end
    summon(function(ok, reason)
        if not ok then reportActionFailure(kind, reason) end
        invalidate(kind)
        refreshJournalSoon()
    end)
end

-- Only locally materialized companion spells can be dragged to an action bar.
-- Account-wide entries still summon from the journal through the authoritative
-- bridge; treating collection ids as legacy companion indexes would select an
-- unrelated spell or corrupt the drag operation.
function CO.Drag(kind, entry)
    if entry and entry.scAccountCollection then
        if entry.nativeIndex and PickupCompanion then PickupCompanion(kind, entry.nativeIndex) end
        return
    end
    if entry and entry.index and PickupCompanion then PickupCompanion(kind, entry.index) end
end

function CO.SourceIndex(kind, spellId)
    if accountStateReady(kind) then
        local index = cache[kind].sourceBySpell[tonumber(spellId)]
        if index then return index end
    end
    return original.SourceIndex(kind, spellId)
end

local events = CreateFrame("Frame")
events:RegisterEvent("COMPANION_UPDATE")
events:RegisterEvent("COMPANION_LEARNED")
events:RegisterEvent("COMPANION_UNLEARNED")
events:SetScript("OnEvent", function()
    invalidate()
    refreshJournalSoon()
end)

if Bridge.RegisterStateListener then
    Bridge.RegisterStateListener(function(_, typeId)
        typeId = tonumber(typeId)
        if typeId == TYPE_BY_KIND.MOUNT or typeId == TYPE_BY_KIND.CRITTER or
            typeId == FAVORITE_TYPE_BY_KIND.MOUNT or typeId == FAVORITE_TYPE_BY_KIND.CRITTER then
            if typeId == FAVORITE_TYPE_BY_KIND.MOUNT then favoriteOverrides.MOUNT = {} end
            if typeId == FAVORITE_TYPE_BY_KIND.CRITTER then favoriteOverrides.CRITTER = {} end
            invalidate()
            refreshJournalSoon()
        end
        return false
    end)
end
