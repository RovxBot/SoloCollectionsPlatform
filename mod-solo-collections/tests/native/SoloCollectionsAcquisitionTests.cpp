#include "Categories/Appearance/SoloCollectionsAppearanceAcquisition.h"

#include <cstdint>
#include <array>
#include <iostream>
#include <set>
#include <stdexcept>
#include <vector>

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
    std::set<std::uint32_t> Rewarded;
    void const* GetSession() const { return HasSession ? this : nullptr; }
    std::uint32_t GetGUID() const { return Guid; }
    bool IsQuestRewarded(std::uint32_t id) const { return Rewarded.contains(id); }
};

struct Quest
{
    std::array<std::uint32_t, 4> RewardItemId { 105, 106, 0, 102 };
    std::array<std::uint32_t, 4> RewardItemIdCount { 1, 1, 1, 1 };
    std::array<std::uint32_t, 6> RewardChoiceItemId { 101, 102, 0, 103, 101, 104 };
    std::array<std::uint32_t, 6> RewardChoiceItemCount { 1, 1, 1, 0, 1, 1 };
    std::uint32_t GetQuestId() const { return 1000; }
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
    ItemTemplate invalid { 0, 4 };
    item.Template = &invalid;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "zero source IDs must be rejected");
    item.Template = nullptr;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "missing templates must be rejected");
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, static_cast<Item const*>(nullptr), equipment), "null items must be rejected");
    Require(!SoloCollections::FindAcquiredAppearanceSource(static_cast<Player const*>(nullptr), &item, equipment), "null players must be rejected");
    player.HasSession = false;
    item.Template = &armor;
    Require(!SoloCollections::FindAcquiredAppearanceSource(&player, &item, equipment), "a disconnected player cannot grant ownership");

    Quest quest;
    std::vector<std::uint32_t> rewards;
    auto visit = [&rewards](std::uint32_t id) { rewards.push_back(id); };
    player.HasSession = true;
    Require(!SoloCollections::VisitRewardedQuestAppearanceSources(&player, &quest, visit),
        "completed objectives without turn-in must not grant reward appearances");
    Require(rewards.empty(), "an unrewarded quest must not enqueue any sources");
    player.Rewarded.insert(quest.GetQuestId());
    Require(SoloCollections::VisitRewardedQuestAppearanceSources(&player, &quest, visit), "rewarded quest was rejected");
    Require(std::set<std::uint32_t>(rewards.begin(), rewards.end()) == std::set<std::uint32_t> { 101, 102, 104, 105, 106 },
        "fixed rewards and every positive-count reward choice must be visited");
    Require(rewards.size() == 5, "duplicate/empty/zero-count rewards must not enqueue extra sources");
    rewards.clear();
    Require(SoloCollections::VisitRewardedQuestAppearanceSources(&player, &quest, visit) && rewards.size() == 5,
        "existing rewarded history must be usable for login reconciliation");
    player.HasSession = false;
    rewards.clear();
    Require(!SoloCollections::VisitRewardedQuestAppearanceSources(&player, &quest, visit) && rewards.empty(),
        "disconnected quest owners must not grant appearances");
    Require(!SoloCollections::VisitRewardedQuestAppearanceSources(static_cast<Player const*>(nullptr), &quest, visit),
        "null quest players must be rejected");
    player.HasSession = true;
    Require(!SoloCollections::VisitRewardedQuestAppearanceSources(&player, static_cast<Quest const*>(nullptr), visit),
        "null quest templates must be rejected");
    std::cout << "SoloCollections appearance acquisition tests passed\n";
}
