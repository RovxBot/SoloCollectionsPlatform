local addon = assert(arg[1])
unpack = unpack or table.unpack
local frames, calls, tickNumber, queryCallbacks, race = {}, {}, 0, {}, "Human"
function UnitRace() return race, race end
function UnitSex() return 2 end
function GetItemInfo() return nil end
function CreateFrame()
    local frame = { shown = true, scripts = {} }
    function frame:SetScript(key, fn) self.scripts[key] = fn end
    function frame:GetScript(key) return self.scripts[key] end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:GetModel() return self.model end
    function frame:ClearModel() calls[#calls + 1] = { "clear", tickNumber }; self.model = nil end
    function frame:SetUnit() calls[#calls + 1] = { "unit", tickNumber }; self.model = "player.m2" end
    function frame:TryOn(id) calls[#calls + 1] = { "try", tickNumber, id } end
    function frame:Undress() calls[#calls + 1] = { "undress", tickNumber } end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:SetWidth(value) self.width = value end
    function frame:SetHeight(value) self.height = value end
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
    function frame:SetPosition() end
    function frame:SetFacing() end
    function frame:SetModelScale() end
    function frame:SetAutoDress() end
    function frame:SetDoBlend() end
    function frame:SetKeepModelOnHide() end
    function frame:SetLight() end
    function frame:SetSequence() end
    frames[#frames + 1] = frame
    return frame
end
SoloCollections = {
    Localize = function(en) return en end,
    UI = {},
    TransmorpherPreviewSetup = { classic = { Human = { [2] = { Armor = {
        Head = { x = 0, y = 0, z = 0, facing = 0, sequence = 0 },
    } } } } },
    TransmorpherItemQuery = { Query = function(_, _, callback) queryCallbacks[#queryCallbacks + 1] = callback end },
}
dofile(addon .. "/UI/EzWardrobe/Model.lua")
local M = SoloCollections.EzWardrobe.Model
local driver = frames[1]
local frame = CreateFrame()
frame.scCard = { GetWidth = function() return 78 end, GetHeight = function() return 104 end, Show = function() end, Hide = function() end }
local function runTicks(count)
    for _ = 1, count do
        tickNumber = tickNumber + 1
        local fn = driver:GetScript("OnUpdate")
        if fn then fn(driver, 0.016) end
    end
end
local function tries()
    local result = {}
    for _, call in ipairs(calls) do if call[1] == "try" then result[#result + 1] = call end end
    return result
end
local first = { id = 1, itemId = 100, slot = "HEAD" }
local second = { id = 2, itemId = 200, slot = "HEAD" }
assert(M:Present(frame, first, 1))
runTicks(12)
assert(#tries() == 1 and tries()[1][3] == 100, "cold item cache must not prevent a native preview")
local clearAt, unitAt
for _, call in ipairs(calls) do
    if call[1] == "clear" then clearAt = call[2] end
    if call[1] == "unit" then unitAt = call[2] end
end
assert(clearAt and unitAt and clearAt < unitAt, "ClearModel and SetUnit must run on different frames")
assert(frame.width == 78 and frame.height == 104 and frame.alpha == 1)
assert(driver:GetScript("OnUpdate") == nil, "an idle renderer must stop its driver")
local allocations = #frames
assert(M:Present(frame, first, 2))
runTicks(8)
assert(#tries() == 1 and #frames == allocations, "unchanged records must reuse their actor and frame")
queryCallbacks[1](100, true)
runTicks(8)
assert(#tries() == 1, "late cache readiness must not rebuild an already visible actor")

assert(M:Present(frame, second, 3))
assert(M:Present(frame, first, 4))
runTicks(12)
assert(#tries() == 2 and tries()[2][3] == 100, "obsolete queued work must not render the replaced appearance")
assert(M:Present(frame, second, 5))
assert(M:Clear(frame))
runTicks(12)
assert(#tries() == 2 and not frame:IsShown(), "hidden/cleared cards must not be resurrected by queued work")

race = "UnknownRace"
assert(M:Present(frame, first, 6))
runTicks(8)
assert(frame.scRuntimeUnavailableReason == "TRANSMORPHER_SETUP_UNAVAILABLE" and not frame:IsShown())
race = "Human"
assert(M:Present(frame, { id = 3, itemId = 300, slot = "MAINHAND", weaponType = "DAGGER" }, 7))
runTicks(8)
assert(frame.scRuntimeUnavailableReason == "CAPABILITY_MISSING" and #tries() == 2,
    "weapons must fail closed when the native preview capability is missing")
print("Wardrobe native renderer lifecycle behavioral checks passed")
