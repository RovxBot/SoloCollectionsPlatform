#include "SoloCollectionsMountService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsIdentity.h"

#include "Player.h"
#include "Random.h"
#include "SharedDefines.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <algorithm>
#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <utility>

namespace SoloCollections
{
namespace
{
constexpr std::uint32_t MountSpellMigrationId = 1;
constexpr std::uint16_t MountSpellMigrationVersion = 1;

enum class MigrationPhase : std::uint8_t
{
    AwaitingReady = 1,
    CheckingMarker = 2,
    Importing = 3,
    WritingMarker = 4,
    Complete = 5,
    Failed = 6,
};

struct PendingMountGrant
{
    CollectionId Collection;
    std::uint32_t SpellId = 0;
    std::uint32_t CharacterGuid = 0;
    CollectionSourceKind SourceKind = CollectionSourceKind::Gameplay;
    bool Started = false;
};

struct MountAccountState
{
    MigrationPhase Phase = MigrationPhase::AwaitingReady;
    LoginGeneration Generation;
    std::uint32_t LoginCharacterGuid = 0;
    std::set<std::uint32_t> CandidateSpells;
    std::set<CollectionId> QueuedCollections;
    std::deque<PendingMountGrant> Pending;
    std::uint32_t ImportedCount = 0;
    std::uint32_t RejectedCount = 0;
    CollectionId LastRandomCollection;
};

AccountId PlayerAccount(Player* player)
{
    return AccountId(player->GetSession()->GetAccountId());
}

bool IsMountableHumanoidForm(ShapeshiftForm form)
{
    switch (form)
    {
        case FORM_NONE:
        case FORM_SHADOW_DANCE:
        case FORM_BATTLESTANCE:
        case FORM_DEFENSIVESTANCE:
        case FORM_BERSERKERSTANCE:
        case FORM_SHADOW:
        case FORM_STEALTH:
            return true;
        default:
            return false;
    }
}

}

class MountCollectionService::Impl
{
public:
    void OnPlayerLogin(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        std::scoped_lock lock(_mutex);
        AccountId account = PlayerAccount(player);
        MountAccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
            for (std::uint32_t spellId : definition.UnlockSpellIds)
                if (player->HasSpell(spellId))
                    state.CandidateSpells.insert(spellId);
    }

    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
    {
        if (!player || !player->GetSession())
            return;
        MountCollectionDefinition const* definition = GetMountCatalog().FindByUnlockSpell(spellId);
        if (!definition)
            return;
        std::scoped_lock lock(_mutex);
        AccountId account = PlayerAccount(player);
        MountAccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        QueueGrant(state, *definition, spellId, state.LoginCharacterGuid, CollectionSourceKind::Gameplay);
    }

    void Update()
    {
        std::scoped_lock lock(_mutex);
        for (auto& [account, state] : _accounts)
        {
            std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
            if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
                continue;
            state.Generation = snapshot->Generation;

            if (state.Phase == MigrationPhase::AwaitingReady)
                BeginMigrationCheck(account, state);
            Advance(account, state);
        }
    }

    std::string ExecuteSummon(Player* player, CollectionId collectionId)
    {
        if (!player || !player->GetSession() || !collectionId.IsValid())
            return "INVALID_REQUEST";
        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            return "LOADING";
        if (snapshot->State == AccountCacheLoadState::Failed)
            return "DB_UNAVAILABLE";

        MountCollectionDefinition const* definition = GetMountCatalog().Find(collectionId);
        if (!definition)
            return "INVALID_REQUEST";
        if (definition->Lifecycle == CatalogLifecycle::Tombstone)
            return "INVALID_REQUEST";
        if (!CatalogLifecycleAllowsAction(definition->Lifecycle) || !definition->JournalVisible || !definition->Actionable)
            return "UNSUPPORTED";
        CollectionKey key { MountCollectionTypeId, collectionId };
        if (!GetAccountCollectionCache().IsOwned(account, key))
            return "NOT_OWNED";

        IdentityRegistry const& identities = GetIdentityRegistry();
        if (!identities.ResolveClass(player->getClass()).IsKnown() ||
            !identities.ResolveRace(player->getRace()).IsKnown())
            return "UNKNOWN_IDENTITY";
        if (!player->IsAlive())
            return "DEAD";
        if (player->IsInCombat())
            return "IN_COMBAT";
        if (player->GetVehicle())
            return "IN_VEHICLE";
        if (player->IsInFlight())
            return "ON_TAXI";
        if (!IsMountableHumanoidForm(player->GetShapeshiftForm()))
            return "SHAPESHIFT_RESTRICTED";
        if (!player->IsOutdoors())
            return "INDOORS";

        std::uint32_t raceMask = player->getRaceMask();
        std::uint32_t classMask = player->getClassMask();
        auto maskMatches = [](std::vector<std::uint32_t> const& masks, std::uint32_t value)
        {
            return masks.empty() || std::any_of(masks.begin(), masks.end(), [value](std::uint32_t mask)
            {
                return mask == 0 || (mask & value) != 0;
            });
        };
        bool raceCompatible = false;
        bool classCompatible = false;
        bool skillCompatible = false;
        bool flightRejected = false;
        bool locationRejected = false;
        MountActionVariant const* selected = nullptr;
        std::uint32_t ridingSkill = player->GetSkillValue(SKILL_RIDING);
        for (MountActionVariant const& variant : definition->ActionVariants)
        {
            if (!maskMatches(variant.RaceMasks, raceMask))
                continue;
            raceCompatible = true;
            if (!maskMatches(variant.ClassMasks, classMask))
                continue;
            classCompatible = true;
            if (ridingSkill < variant.MinimumRidingSkill)
                continue;
            skillCompatible = true;
            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(variant.SpellId);
            if (!spellInfo)
                continue;
            SpellCastResult location = spellInfo->CheckLocation(
                player->GetMapId(), player->GetZoneId(), player->GetAreaId(), player, true);
            if (location != SPELL_CAST_OK)
            {
                flightRejected = flightRejected || variant.IsFlying;
                locationRejected = locationRejected || !variant.IsFlying;
                continue;
            }
            if (!selected || variant.MinimumRidingSkill > selected->MinimumRidingSkill ||
                (variant.MinimumRidingSkill == selected->MinimumRidingSkill && variant.IsFlying && !selected->IsFlying))
                selected = &variant;
        }
        if (!raceCompatible)
            return "RACE_RESTRICTED";
        if (!classCompatible)
            return "CLASS_RESTRICTED";
        if (!skillCompatible)
            return "SKILL_REQUIRED";
        if (!selected)
            return flightRejected && !locationRejected ? "FLYING_NOT_ALLOWED" : "MAP_RESTRICTED";

        SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(selected->SpellId);
        if (!spellInfo)
            return "CAST_FAILED";
        // The ordinary spell pipeline owns cast time, movement interruption,
        // cooldowns, shapeshift and location checks. Any triggered flag makes
        // AzerothCore treat the cast as triggered and skip movement checks.
        player->Dismount();
        player->RemoveAurasByType(SPELL_AURA_MOUNTED);
        SpellCastResult castResult = player->CastSpell(player, spellInfo, TRIGGERED_NONE);
        if (castResult != SPELL_CAST_OK)
            return "CAST_FAILED";
        return "ACCEPTED";
    }

    std::string ExecuteRandomSummon(Player* player)
    {
        if (!player || !player->GetSession())
            return "INVALID_REQUEST";
        if (player->IsMounted())
        {
            player->Dismount();
            player->RemoveAurasByType(SPELL_AURA_MOUNTED);
            return "DISMISSED";
        }

        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            return "LOADING";
        if (snapshot->State == AccountCacheLoadState::Failed)
            return "DB_UNAVAILABLE";

        std::vector<CollectionId> all;
        std::vector<CollectionId> favorites;
        for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
        {
            if (definition.Lifecycle != CatalogLifecycle::Active || !definition.JournalVisible ||
                !definition.Actionable || !definition.RandomEligible)
                continue;
            CollectionKey mountKey { MountCollectionTypeId, definition.Id };
            if (!GetAccountCollectionCache().IsOwned(account, mountKey))
                continue;
            all.push_back(definition.Id);
            CollectionKey favoriteKey { MountFavoriteCollectionTypeId, definition.Id };
            if (GetAccountCollectionCache().IsOwned(account, favoriteKey))
                favorites.push_back(definition.Id);
        }
        if (all.empty())
            return "NO_MOUNTS";

        CollectionId previous;
        {
            std::scoped_lock lock(_mutex);
            previous = _accounts[account].LastRandomCollection;
        }
        auto tryPool = [&](std::vector<CollectionId> pool) -> std::string
        {
            if (pool.size() > 1 && previous.IsValid())
                pool.erase(std::remove(pool.begin(), pool.end(), previous), pool.end());
            while (!pool.empty())
            {
                std::size_t index = urand(0, static_cast<std::uint32_t>(pool.size() - 1));
                CollectionId selected = pool[index];
                pool.erase(pool.begin() + index);
                std::string result = ExecuteSummon(player, selected);
                if (result == "ACCEPTED")
                {
                    {
                        std::scoped_lock lock(_mutex);
                        _accounts[account].LastRandomCollection = selected;
                    }
                    return result;
                }
                if (result != "MAP_RESTRICTED" && result != "FLYING_NOT_ALLOWED" &&
                    result != "RACE_RESTRICTED" && result != "CLASS_RESTRICTED" &&
                    result != "SKILL_REQUIRED" && result != "UNSUPPORTED")
                    return result;
            }
            return "NO_USABLE_MOUNTS";
        };

        if (!favorites.empty())
        {
            std::string result = tryPool(favorites);
            if (result != "NO_USABLE_MOUNTS")
                return result;
        }
        return tryPool(all);
    }

private:
    static void QueueGrant(MountAccountState& state, MountCollectionDefinition const& definition,
        std::uint32_t spellId, std::uint32_t characterGuid, CollectionSourceKind sourceKind)
    {
        if (!state.QueuedCollections.insert(definition.Id).second)
            return;
        state.Pending.push_back({ definition.Id, spellId, characterGuid, sourceKind, false });
    }

    void BeginMigrationCheck(AccountId account, MountAccountState& state)
    {
        state.Phase = MigrationPhase::CheckingMarker;
        bool started = GetAccountCollectionStore().CheckMigrationMarker(
            { account, MountSpellMigrationId, MountSpellMigrationVersion },
            [this, account](bool succeeded, bool completed, std::vector<std::uint32_t> databaseSpells)
            {
                std::scoped_lock lock(_mutex);
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                MountAccountState& current = found->second;
                if (!succeeded)
                {
                    current.Phase = MigrationPhase::Failed;
                    return;
                }
                if (completed)
                {
                    current.Phase = MigrationPhase::Complete;
                    current.CandidateSpells.clear();
                    return;
                }
                current.CandidateSpells.insert(databaseSpells.begin(), databaseSpells.end());
                for (std::uint32_t spellId : current.CandidateSpells)
                    if (MountCollectionDefinition const* definition = GetMountCatalog().FindByUnlockSpell(spellId))
                        QueueGrant(current, *definition, spellId, current.LoginCharacterGuid, CollectionSourceKind::Migration);
                current.CandidateSpells.clear();
                current.Phase = MigrationPhase::Importing;
            });
        if (!started)
            state.Phase = MigrationPhase::AwaitingReady;
    }

    void Advance(AccountId account, MountAccountState& state)
    {
        AccountCollectionStore& store = GetAccountCollectionStore();
        if (store.HasPendingMutation(account))
            return;

        while (!state.Pending.empty())
        {
            PendingMountGrant& grant = state.Pending.front();
            CollectionKey key { MountCollectionTypeId, grant.Collection };
            if (GetAccountCollectionCache().IsOwned(account, key))
            {
                if (grant.Started && grant.SourceKind == CollectionSourceKind::Migration)
                    ++state.ImportedCount;
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }

            AccountCollectionMutation mutation;
            mutation.Account = account;
            mutation.Generation = state.Generation;
            mutation.Key = key;
            mutation.Kind = CollectionMutationKind::Grant;
            mutation.SourceKind = grant.SourceKind;
            mutation.SourceId = grant.SpellId;
            mutation.CharacterGuid = grant.CharacterGuid;
            MutationStartResult result = store.BeginMutation(mutation);
            if (result.Accepted)
            {
                grant.Started = true;
                return;
            }
            if (result.Reason == CollectionReasonCode::PendingOperation || result.Reason == CollectionReasonCode::NotReady)
                return;
            if (result.Reason == CollectionReasonCode::AlreadyOwned)
            {
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }
            if (grant.SourceKind == CollectionSourceKind::Migration)
                ++state.RejectedCount;
            state.QueuedCollections.erase(grant.Collection);
            state.Pending.pop_front();
        }

        if (state.Phase != MigrationPhase::Importing)
            return;
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        state.Phase = MigrationPhase::WritingMarker;
        bool started = store.CompleteMigrationMarker(
            { { account, MountSpellMigrationId, MountSpellMigrationVersion }, snapshot->Revision,
                state.ImportedCount, state.RejectedCount },
            [this, account](bool committed)
            {
                std::scoped_lock lock(_mutex);
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                found->second.Phase = committed ? MigrationPhase::Complete : MigrationPhase::Failed;
            });
        if (!started)
            state.Phase = MigrationPhase::Importing;
    }

    std::map<AccountId, MountAccountState> _accounts;
    std::mutex _mutex;
};

MountCollectionService::MountCollectionService() : _impl(std::make_unique<Impl>()) { }
MountCollectionService::~MountCollectionService() = default;

void MountCollectionService::OnPlayerLogin(Player* player)
{
    _impl->OnPlayerLogin(player);
}

void MountCollectionService::OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
{
    _impl->OnPlayerLearnSpell(player, spellId);
}

void MountCollectionService::Update()
{
    _impl->Update();
}

std::string MountCollectionService::ExecuteSummon(Player* player, CollectionId collectionId)
{
    return _impl->ExecuteSummon(player, collectionId);
}

std::string MountCollectionService::ExecuteRandomSummon(Player* player)
{
    return _impl->ExecuteRandomSummon(player);
}

MountCollectionService& GetMountCollectionService()
{
    static MountCollectionService service;
    return service;
}
}
