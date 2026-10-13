local addon = assert(arg[1])
local chinese, names = false, {}
function GetItemInfo(id) return names[tonumber(id)] end
function CreateFrame()
    return { SetScript = function(self, key, fn) self[key] = fn end, RegisterEvent = function() end }
end
SoloCollections = {
    Localize = function(en, zh) return chinese and zh or en end,
    IsChineseLocale = function() return chinese end,
    UI = {}, Data = {},
    CollectionState = { ResolveOwned = function(_, id) return id == 200001, true end },
    GeneratedWardrobeCatalog = {
        compactFormat = 2, appearanceCount = 2,
        slots = { "HEAD" }, armorTypes = { "PLATE" },
        appearances = {
            ids = { 200001, 200002 }, itemIds = { 100, 200 }, slotIds = { 1, 1 },
            armorIds = { 1, 1 }, names = { "测试头盔", "另一头盔" },
            extraItemIds = { [1] = { 100, 101 } },
        },
    },
}
dofile(addon .. "/Core/Catalog.lua")
local C = SoloCollections.Catalog
local filters = { slot = "HEAD", armorType = "ALL", collected = true, uncollected = true }
local records = C.QueryAll("APPEARANCES", "", filters)
assert(#records == 2 and records[1].name == "Item 100 (name loading)")
assert(#C.QueryAll("APPEARANCES", "101", filters) == 1, "alternate source item IDs must be searchable")
assert(#C.QueryAll("APPEARANCES", "item:200", filters) == 1)
assert(#C.QueryAll("APPEARANCES", "999999", filters) == 0)
names[100] = "Crown of Testing"
assert(#C.QueryAll("APPEARANCES", "crown", filters) == 1, "search must use localized native names")
assert(C.GetAppearanceDisplayName(records[1]) == "Crown of Testing")
chinese = true
records = C.QueryAll("APPEARANCES", "", filters)
assert(records[1].name == "测试头盔", "Chinese clients must keep their source names")

SoloCollections.db = { filters = { favorites = false, armorType = "CLOTH" }, query = "journal search" }
SoloCollections.WardrobeLab = {}
dofile(addon .. "/UI/WardrobeLab/Sources.lua")
local studioFilters = SoloCollections.WardrobeLab.GetFilters()
studioFilters.favorites, studioFilters.slot, studioFilters.armorType = true, "HEAD", "ALL"
assert(C.ToggleDemoFavorite("APPEARANCES", 200001))
records = C.QueryAll("APPEARANCES", "", studioFilters)
assert(#records == 1 and records[1].id == 200001, "favorites-only must select the starred appearance")
assert(SoloCollections.db.filters.favorites == false and SoloCollections.db.filters.armorType == "CLOTH")
assert(SoloCollections.db.query == "journal search", "studio preferences must not overwrite journal preferences")
assert(SoloCollections.WardrobeLab.GetFilters().favorites == true, "opening filters again must retain the selection")
print("Wardrobe catalogue locale and search behavioral checks passed")
