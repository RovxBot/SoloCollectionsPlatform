local SC = SoloCollections
local Actions = {}
SC.MountActions = Actions

local function notice(enUS, zhCN)
    local message = SC.Localize(enUS, zhCN)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.35, 0.2, 1)
    end
end

local function mountRecord(collectionId)
    if not SC.CollectionState or SC.CollectionState.GetCategoryState("MOUNTS") ~= "Ready" then
        return nil
    end
    for _, record in ipairs(SC.Catalog.Get("MOUNTS") or {}) do
        if record.id == collectionId and record.collected and record.actionable and record.draggable and
            tonumber(record.canonicalActionSpellId or 0) > 0 then
            return record
        end
    end
end

local function result(ok, reason)
    if not ok then
        notice("Mount summon failed: " .. tostring(reason), "坐骑召唤失败：" .. tostring(reason))
    end
end

function Actions.Summon(collectionId)
    if not mountRecord(collectionId) then
        notice("This mount is not collected or collections are still syncing.", "尚未收集该坐骑或收藏仍在同步。")
        return false
    end
    return SC.Bridge.SummonMount(collectionId, result)
end

function Actions.SummonRandom()
    return SC.Bridge.SummonRandomMount(result)
end

local function iconIndex(path)
    if type(path) ~= "string" or not (GetNumMacroIcons and GetMacroIconInfo) then return 1 end
    local wanted = path:lower():gsub("/", "\\")
    for index = 1, GetNumMacroIcons() do
        local icon = GetMacroIconInfo(index)
        if type(icon) == "string" and icon:lower():gsub("/", "\\") == wanted then return index end
    end
    return 1
end

local function pickup(name, action, icon, spellId)
    if InCombatLockdown and InCombatLockdown() then
        notice("Mount shortcuts cannot be dragged in combat.", "战斗中不能拖拽坐骑快捷方式。")
        return false
    end
    if not (GetNumMacros and GetMacroInfo and CreateMacro and PickupMacro) then return false end
    local account, character = GetNumMacros()
    local accountLimit = MAX_ACCOUNT_MACROS or 36
    local characterLimit = MAX_CHARACTER_MACROS or 18
    local function find(first, last)
        for index = first, last do
            local _, _, body = GetMacroInfo(index)
            -- Match the action, not a user-editable name or localized tooltip.
            local storedAction = body and body:gsub("%s+$", ""):match("([^\n]+)$")
            if storedAction == action then return index end
        end
    end
    local index = find(1, account) or find(accountLimit + 1, accountLimit + character)
    if not index then
        local perCharacter = account >= accountLimit
        if perCharacter and character >= characterLimit then
            notice("Free a macro slot to drag this mount to an action bar.", "请腾出一个宏栏位以拖拽此坐骑。")
            return false
        end
        local spellName = spellId and GetSpellInfo and GetSpellInfo(spellId)
        local body = (spellName and ("#showtooltip " .. spellName .. "\n") or "") .. action
        local ok, created = pcall(CreateMacro, name, iconIndex(icon), body, perCharacter)
        if not ok or not created or created == 0 then
            notice("Could not create the mount shortcut.", "无法创建坐骑快捷方式。")
            return false
        end
        index = created
    end
    PickupMacro(index)
    return true
end

function Actions.Pickup(collectionId)
    local record = mountRecord(collectionId)
    if not record then
        notice("This mount is not collected or collections are still syncing.", "尚未收集该坐骑或收藏仍在同步。")
        return false
    end
    return pickup("SCM" .. collectionId,
        "/run SoloCollections.MountActions.Summon(" .. collectionId .. ")",
        record.icon, record.canonicalActionSpellId)
end

function Actions.PickupRandom()
    return pickup("SC Random Mount", "/run SoloCollections.MountActions.SummonRandom()",
        "Interface\\Icons\\Ability_Mount_RidingHorse")
end
