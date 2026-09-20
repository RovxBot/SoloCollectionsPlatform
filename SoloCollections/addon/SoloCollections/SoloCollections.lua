SoloCollections = SoloCollections or {}

local SC = SoloCollections

SC.NAME = "SoloCollections"
SC.VERSION = "0.2.0"
SC.BUILD_CHANNEL = SC.BUILD_CHANNEL
    or (GetAddOnMetadata and GetAddOnMetadata(SC.NAME, "X-SoloCollections-BuildChannel"))
    or "stable"
SC.DEFAULT_UI_SHELL = "DRAGONUI"
SC.PROTOCOL = "SC1"
SC.PROTOCOL_VERSION = 1
SC.TABS = {
    "MOUNTS",
    "PETS",
    "WARDROBE",
}
SC.WARDROBE_TABS = {
    "ITEMS",
    "SETS",
}
SC.Data = SC.Data or {}
SC.Pages = SC.Pages or {}
SC.UI = SC.UI or {}

-- Keep presentation text readable on English clients.  Most of the generated
-- catalog carries both names, but the original UI shell was authored on a
-- zhCN client and also has a small number of hand-written labels.  A single
-- locale helper keeps those call sites explicit without changing the
-- server-authoritative data or action protocol.
function SC.IsChineseLocale()
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    return locale == "zhCN" or locale == "zhTW"
end

function SC.Localize(enUS, zhCN)
    if SC.IsChineseLocale() then
        return zhCN or enUS or ""
    end
    return enUS or zhCN or ""
end
