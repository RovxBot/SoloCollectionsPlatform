local SC = SoloCollections
local L = SC.Localize
local Goals = {}
SC.WardrobeGoals = Goals

function Goals.GetPieces(record)
    if type(record) ~= "table" then return {} end
    local variant = record.selectedVariant
    if not variant then
        for _, candidate in ipairs(record.variants or {}) do
            if not variant or candidate.isDefault then variant = candidate end
            if record.selectedVariantOrdinal and tonumber(record.selectedVariantOrdinal) == tonumber(candidate.variantOrdinal) then
                variant = candidate
                break
            end
        end
    end
    local result, seen = {}, {}
    for _, member in ipairs((variant and variant.members) or {}) do
        if member.slotKey and not seen[member.slotKey] then
            seen[member.slotKey] = true
            local id = tonumber(member.collectionId) or tonumber(member.appearanceIds and member.appearanceIds[1])
            local owned = false
            for _, candidate in ipairs(member.appearanceIds or { id }) do
                if SC.CollectionState and SC.CollectionState.IsOwnedByType
                    and SC.CollectionState.IsOwnedByType(13, tonumber(candidate)) then
                    id, owned = tonumber(candidate), true
                    break
                end
            end
            local appearance = SC.Catalog.FindAppearance and SC.Catalog.FindAppearance(id)
            result[#result + 1] = {
                slotKey = member.slotKey, collectionId = id, owned = owned,
                itemId = tonumber(member.previewSourceItemId) or (appearance and appearance.itemId)
                    or tonumber(member.sourceItemIds and member.sourceItemIds[1]),
                appearance = appearance, required = member.required ~= false,
            }
        end
    end
    return result
end

function Goals.IsTracked(record)
    local saved = SC.db and SC.db.trackedWardrobeSets
    return type(saved) == "table" and record and saved[tonumber(record.id)] == true or false
end

function Goals.ToggleTracked(record)
    local id = record and tonumber(record.id)
    if not SC.db or not id then return false end
    SC.db.trackedWardrobeSets = type(SC.db.trackedWardrobeSets) == "table" and SC.db.trackedWardrobeSets or {}
    if Goals.IsTracked(record) then SC.db.trackedWardrobeSets[id] = nil
    else SC.db.trackedWardrobeSets[id] = true end
    return Goals.IsTracked(record)
end

function Goals.AddMissingTooltip(tooltip, record)
    local count = 0
    for _, piece in ipairs(Goals.GetPieces(record)) do
        if not piece.owned then
            if count == 0 then tooltip:AddLine(L("Missing pieces:", "缺少的部件："), 1, 0.82, 0.18) end
            count = count + 1
            local name = piece.appearance and SC.Catalog.GetAppearanceDisplayName(piece.appearance)
                or string.format(L("Item %s", "物品 %s"), tostring(piece.itemId or "?"))
            tooltip:AddLine(name, 0.85, 0.85, 0.85, true)
            local source = piece.appearance and piece.appearance.source
            if not source and piece.appearance then
                for _, kind in ipairs(SC.Catalog.APPEARANCE_SOURCE_KINDS or {}) do
                    if kind.key == piece.appearance.sourceKind then source = kind.label break end
                end
            end
            if source then tooltip:AddLine(source, 0.72, 0.72, 0.72, true) end
        end
    end
    if count == 0 then tooltip:AddLine(L("All pieces collected", "所有部件已收集"), 0.45, 0.9, 0.34) end
end
