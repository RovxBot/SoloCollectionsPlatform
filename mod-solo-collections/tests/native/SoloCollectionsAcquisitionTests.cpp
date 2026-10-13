#include "Categories/Appearance/SoloCollectionsAppearanceAcquisition.h"

#include <cstdint>
#include <iostream>
#include <stdexcept>

namespace
{
void Require(bool condition, char const* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

struct Player
{
    bool HasSession = true;
    std::uint32_t Guid = 10;
    void const* GetSession() const { return HasSession ? this : nullptr; }
    std::uint32_t GetGUID() const { return Guid; }
};

struct ItemTemplate
{
    std::uint32_t ItemId = 100;
    std::uint32_t Class = 4;
};

struct Item
{
    ItemTemplate const* Template = nullptr;
    std::uint32_t Owner = 10;
    bool Equipped = false;
    bool Soulbound = false;
    bool Refundable = true;
    bool Tradeable = true;
    ItemTemplate const* GetTemplate() const { return Template; }
    std::uint32_t GetOwnerGUID() const { return Owner; }
};
}

int main()
{
    auto equipment = [](ItemTemplate const& item) { return item.Class == 2 || item.Class == 4; };
    Player player;
    ItemTemplate armor;
    Item item { &armor };
    auto acquired = SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment);
    Require(acquired && *acquired == 100, "unequipped, unbound, refundable/tradeable equipment must be collectible");
    ItemTemplate weapon { 200, 2 };
    item.Template = &weapon;
    acquired = SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment);
    Require(acquired && *acquired == 200, "picked-up weapons must be collectible without an equip operation");
    item.Owner = 20;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "another player's item cannot grant ownership");
    item.Owner = player.Guid;
    ItemTemplate food { 300, 0 };
    item.Template = &food;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "non-equipment items must be rejected");
    item.Template = nullptr;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "missing templates must be rejected");
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, static_cast<Item const*>(nullptr), equipment), "null items must be rejected");
    Require(!SoloCollections::FindAcquiredAppearanceSource(static_cast<Player const*>(nullptr), &item, equipment), "null players must be rejected");
    player.HasSession = false;
    item.Template = &armor;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "a disconnected player cannot grant ownership");
    std::cout << "SoloCollections appearance acquisition tests passed\n";
}
