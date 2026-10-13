#ifndef SOLO_COLLECTIONS_APPEARANCE_ACQUISITION_H
#define SOLO_COLLECTIONS_APPEARANCE_ACQUISITION_H

#include <cstdint>
#include <iterator>
#include <optional>
#include <set>

namespace SoloCollections
{
// Called from authoritative item receipt/ownership events. Collection does not
// depend on binding flags or whether this character can equip the item.
template <typename PlayerType, typename ItemType, typename AcceptTemplate>
[[nodiscard]] std::optional<std::uint32_t> FindAcquiredAppearanceSource(
    PlayerType const* player, ItemType const* item, AcceptTemplate accept)
{
    if (!player || !player->GetSession() || !item || item->GetOwnerGUID() != player->GetGUID())
        return std::nullopt;
    auto const* itemTemplate = item->GetTemplate();
    if (!itemTemplate || itemTemplate->ItemId == 0 || !accept(*itemTemplate))
        return std::nullopt;
    return itemTemplate->ItemId;
}

// Quest history is server-owned and includes repeatable turn-ins. Merely
// finishing objectives is insufficient. The visitor validates catalogue sources;
// no physical reward item is created for the unchosen alternatives.
template <typename PlayerType, typename QuestType, typename VisitSource>
[[nodiscard]] bool VisitRewardedQuestAppearanceSources(
    PlayerType const* player, QuestType const* quest, VisitSource visit)
{
    if (!player || !player->GetSession() || !quest || !player->IsQuestRewarded(quest->GetQuestId()))
        return false;
    std::set<std::uint32_t> visited;
    auto reward = [&visited, &visit](std::uint32_t itemId, std::uint32_t count)
    {
        if (itemId != 0 && count != 0 && visited.insert(itemId).second)
            visit(itemId);
    };
    for (std::size_t index = 0; index < std::size(quest->RewardItemId); ++index)
        reward(quest->RewardItemId[index], quest->RewardItemIdCount[index]);
    for (std::size_t index = 0; index < std::size(quest->RewardChoiceItemId); ++index)
        reward(quest->RewardChoiceItemId[index], quest->RewardChoiceItemCount[index]);
    return true;
}
}

#endif
