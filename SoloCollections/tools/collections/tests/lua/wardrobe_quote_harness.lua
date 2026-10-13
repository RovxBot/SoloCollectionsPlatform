local addon = assert(arg[1], "AddOn path is required")
local now, money = 0, 1000000
local quotes, applies, notices, frames = {}, {}, {}, {}
function GetTime() return now end
function GetMoney() return money end
function UnitName() return "Tester" end
function GetInventoryItemID(_, slot) return slot == 1 and 100 or nil end
function CreateFrame()
    local frame = {
        SetScript = function(self, key, fn) self[key] = fn end,
        RegisterEvent = function() end,
    }
    frames[#frames + 1] = frame
    return frame
end
function StaticPopup_Show() return {} end
SoloCollections = {
    Localize = function(en) return en end,
    UI = {},
    CollectionState = {
        GetRevision = function() return "1" end,
        IsAppliedReady = function() return true end,
        GetAppliedSlots = function() return {} end,
    },
    Bridge = {
        QuoteApply = function(entries, count, callback)
            quotes[#quotes + 1] = { entries = entries, count = count, callback = callback }
            return #quotes
        end,
        ApplyPending = function(entries, count, callback)
            applies[#applies + 1] = { entries = entries, count = count, callback = callback }
            return #applies
        end,
    },
}
dofile(addon .. "/UI/WardrobeLab/State.lua")
local Lab = SoloCollections.WardrobeLab
Lab.Notice = function(text) notices[#notices + 1] = text end
local function draft(state, id)
    assert(state:SetDraft("HEAD", { id = id, itemId = id, collected = true }))
end
local function reply(index, copper)
    quotes[index].callback(true, "ACCEPTED", { copper = copper, warningMask = 0 })
end
local function ready(state, copper)
    state:RequestQuote()
    reply(#quotes, copper)
end

local state = Lab.CreateState()
draft(state, 200001)
assert(state:GetApplyCost() == nil)
local canApply, reason = state:GetDraftApplyState()
assert(not canApply and reason == "QUOTE_PENDING", "an unquoted draft must be blocked")
ready(state, 10000)
assert(state:GetDraftApplyState() and state:GetApplyCost() == 10000)
draft(state, 200002)
assert(state:GetApplyCost() == nil, "the old price must disappear before debounce")

state:RequestQuote()
local obsolete = #quotes
draft(state, 200003)
reply(obsolete, 90000)
assert(state:GetApplyCost() == nil, "a stale reply must not price a different draft")
ready(state, 10000)
Lab.ConfirmApply(state, "Apply?", function() state:BeginApplyAll() end)
local accept = Lab.pendingPopupAccept
draft(state, 200004)
local before = #applies
accept()
assert(#applies == before, "changing the selection must invalidate confirmation")

ready(state, 10000)
Lab.ConfirmApply(state, "Apply?", function() state:BeginApplyAll() end)
Lab.pendingPopupAccept()
assert(#applies == before, "apply must wait for the refreshed quote")
reply(#quotes, 20000)
assert(#applies == before, "a changed price must require another confirmation")
assert(state:GetApplyCost() == 20000)

Lab.ConfirmApply(state, "Apply?", function() state:BeginApplyAll() end)
Lab.pendingPopupAccept()
reply(#quotes, 20000)
assert(#applies == before + 1, "one confirmed price must send one paid request")
assert(applies[#applies].entries == "1:200004")
applies[#applies].callback(true, "ACCEPTED")
assert(not state:HasDraft())

state = Lab.CreateState()
draft(state, 200005)
money = 0
ready(state, 0)
assert(state:GetApplyCost() == 0 and state:GetDraftApplyState(), "a server-quoted zero is valid")
Lab.ConfirmApply(state, "Apply?", function() state:BeginApplyAll() end)
accept = Lab.pendingPopupAccept
state.equipmentGeneration = state.equipmentGeneration + 1
before = #applies
accept()
assert(#applies == before, "equipment changes must invalidate confirmation")
ready(state, 1)
canApply, reason = state:GetDraftApplyState()
assert(not canApply and reason == "INSUFFICIENT_FUNDS")

state = Lab.CreateState()
state:RememberAppliedSlot("HEAD", 200005)
assert(state:GetAppliedCollectionId("HEAD") == 200005)
state:OnEquipmentChanged(3)
assert(state:GetAppliedCollectionId("HEAD") == 200005, "unrelated gear slots keep their indicators")
state:OnEquipmentChanged(1)
state:CaptureEquipped()
assert(state.equippedBySlot.HEAD == 100)
assert(state:GetAppliedCollectionId("HEAD") == nil, "same-template swaps must discard the old instance's overlay")
state:RememberAppliedSlot("HEAD", 200006)
assert(state:GetAppliedCollectionId("HEAD") == 200006, "a confirmed apply binds the new item")

local refreshed
SoloCollections.Bridge.RegisterStateListener = function(callback) refreshed = callback end
SoloCollections.CollectionState.GetAppliedSlots = function() return { HEAD = 2 } end
dofile(addon .. "/UI/WardrobeLab/Tooltip.lua")
local tooltipFrame = frames[#frames]
tooltipFrame.OnEvent(tooltipFrame, "PLAYER_ENTERING_WORLD")
local lines = {}
local tooltip = { AddLine = function(_, line) lines[#lines + 1] = line end, Show = function() end }
Lab.AddInventoryTransmogTooltip(tooltip, 1)
assert(#lines == 2)

SoloCollections.db = {}
SoloCollections.Catalog = {
    FindAppearance = function(id)
        return { id = id, itemId = 100, name = "A piece", collected = true }
    end,
}
SoloCollections.CollectionState.IsOwnedByType = function(_, id) return id == 200009 end
dofile(addon .. "/Core/WardrobeGoals.lua")
local set = { id = 1001, name = "A set", collected = false, variants = { { members = {
    { slotKey = "HEAD", appearanceIds = { 200009 }, sourceItemIds = { 100 } },
    { slotKey = "FEET", appearanceIds = { 200010 }, sourceItemIds = { 200 } },
} } } }
local Goals = SoloCollections.WardrobeGoals
assert(Goals.ToggleTracked(set) and Goals.IsTracked(set))
assert(not Goals.ToggleTracked(set) and not Goals.IsTracked(set), "tracking must be reversible")
state = Lab.CreateState()
assert(state:LoadCollectedSet(set))
assert(state.draftBySlot.HEAD.id == 200009 and state.draftBySlot.FEET == nil)
assert(state:BuildIntentEntries() == "1:200009", "a partial set must never submit locked pieces")
assert(state:GetApplyCost() == nil, "partial sets still require a fresh quote and paid confirmation")
SoloCollections.CollectionState.IsOwnedByType = function() return false end
state = Lab.CreateState()
assert(not state:LoadCollectedSet(set), "local collected flags cannot grant ownership")
lines = {}
tooltipFrame.OnEvent(tooltipFrame, "PLAYER_EQUIPMENT_CHANGED", 1)
Lab.AddInventoryTransmogTooltip(tooltip, 1)
assert(#lines == 0, "same-template swaps must discard stale tooltip lines")
refreshed("Ready", 18)
Lab.AddInventoryTransmogTooltip(tooltip, 1)
assert(#lines == 0, "a projection refresh must not authorize an old item instance")
Lab.ConfirmEquippedTransmog("HEAD")
Lab.AddInventoryTransmogTooltip(tooltip, 1)
assert(#lines == 2)

print("Wardrobe quote behavioral checks passed")
