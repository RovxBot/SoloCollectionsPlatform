local addon = assert(arg[1])
local now, frames, sent, callbacks, progress, resyncs = 0, {}, {}, {}, {}, {}
function GetTime() return now end
function UnitName() return "Tester" end
function SendAddonMessage(_, body) sent[#sent + 1] = body end
function CreateFrame()
    local frame = {
        SetScript = function(self, key, fn) self[key] = fn end,
        RegisterEvent = function() end,
    }
    frames[#frames + 1] = frame
    return frame
end
SoloCollections = {
    UI = {},
    CollectionState = {
        sessionNonce = "0123456789abcdef",
        categories = { [19] = { state = "Ready" } },
        SetSender = function() end,
        SetChangedCallback = function() end,
        GetState = function() return "Ready" end,
        IsAppliedReady = function() return true end,
        IsOutfitReady = function() return true end,
        requestResync = function(reason, typeId) resyncs[#resyncs + 1] = { reason, typeId } end,
        HandleMessage = function(message)
            return "ACTION_RESULT", { "U", "nonce", message, "ACCEPTED", "18", "1", "2" }
        end,
    },
}
dofile(addon .. "/Core/Bridge.lua")
local B = SoloCollections.Bridge
B.sc2Connected = true
B.RegisterStateListener(function(_, _, change) progress[#progress + 1] = change end)
local function tick(time)
    now = time
    frames[1].OnUpdate(frames[1], 0.1)
end
local function reply(id, sender)
    B.OnMessage("SC2", tostring(id), "WHISPER", sender or "Tester")
end
local function callback(ok, reason) callbacks[#callbacks + 1] = { ok, reason } end
local id = B.ApplyPending("1:200001", 1, callback)
assert(#sent == 1)
tick(6)
assert(#callbacks == 0, "five seconds must not turn a paid write into failure")
assert(#progress == 1 and progress[1].requestId == id)
assert(#resyncs == 1 and resyncs[1][2] == 18)
tick(12)
assert(#progress == 1 and #sent == 1, "a slow write must never be resent")
reply(id, "AnotherPlayer")
assert(#callbacks == 0, "another player cannot complete a request")
reply(id)
assert(#callbacks == 1 and callbacks[1][1] and callbacks[1][2] == "ACCEPTED")
reply(id)
assert(#callbacks == 1, "duplicate acknowledgments must be ignored")

id = B.SaveOutfit(0, "Test", "200001", callback)
tick(18)
assert(#callbacks == 1)
tick(73)
assert(#callbacks == 2 and callbacks[2][2] == "UNCONFIRMED")
assert(#sent == 2, "timeout recovery must not retry the write")

id = B.QuoteApply("1:200001", 1, callback)
tick(79)
assert(#callbacks == 3 and callbacks[3][2] == "TIMEOUT", "read quotes keep a short timeout")
print("Wardrobe delayed transport behavioral checks passed")
