#ifndef SOLO_COLLECTIONS_APPEARANCE_ACQUISITION_H
#define SOLO_COLLECTIONS_APPEARANCE_ACQUISITION_H

#include <cstdint>
#include <optional>

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
}

#endif
