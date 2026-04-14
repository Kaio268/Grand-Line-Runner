# Devil Fruit Chest System - Locked Specification

> Maintenance: Update this spec whenever chest balance, rarity weights, reward tables, duplicate conversion rules, or chest metadata behavior changes.

---

## 1. Purpose

Devil Fruits are rare, high-impact rewards tied to player skill. Fruits can only drop from the highest-tier run chest, so players must reach the deepest parts of a run to access fruit RNG. All reward logic runs through a single centralized pipeline to keep the system scalable and easy to maintain.

**Design goals**
- Keep fruits rare and meaningful
- Tie fruit access to run depth, not playtime
- Eliminate dead rewards - duplicates always convert into something useful
- Keep all reward logic in one place

---

## 2. Chest Tiers

Chests are earned during runs and opened at base. Tier scales with depth.

| Tier | Depth | Fruit Eligible |
|---|---|---|
| Wooden | Early | No |
| Iron | Mid | No |
| Gold | Strong | No |
| Legendary | Late / jackpot | **Yes (10%)** |

Only Legendary chests can roll a Devil Fruit. All other tiers have a 0% chance. This keeps early-game fruit inflation in check and makes Legendary chests genuinely worth pushing for.

---

## 3. Regular Chest Rewards

Standard run chests grant baseline rewards on open:

- Food
- Materials
- Doubloons
- Devil Fruit (Legendary only, see Section 4)

**Server reward order**
1. Compute base rewards from deterministic tier ranges
2. Grant base rewards
3. Evaluate Devil Fruit roll (only if chest is eligible)

---

## 4. Fruit Roll Flow

When a Legendary chest is opened, after base rewards are granted:

1. Roll **10% fruit gate**
2. If fail -> end
3. If pass -> roll **weighted rarity**
4. Resolve effective rarity (handle empty pools, see Section 5)
5. Pick a random fruit from that rarity pool
6. Check ownership via `DevilFruitInventoryService:IsOwned()`
7. If new -> grant fruit
8. If duplicate -> apply conversion (see Section 7-Section 8)
9. Return **fully resolved** structured result (see Section 10)

All steps run server-side. The resolver always returns a final state - no partial or intermediate results.

---

## 5. Rarity Weights and Empty Pool Fallback

**Weights**
```
FruitRarityWeights = {
    Common    = 0.60,
    Rare      = 0.30,
    Legendary = 0.09,
    Mythic    = 0.01,
}
```

All four tiers must exist in config even if a fruit pool is temporarily empty. The Common pool currently includes Suke Suke no Mi and Horo Horo no Mi, and the resolver handles any future empty pools safely.

**Empty pool fallback**
1. Step down to the next lower rarity
2. Repeat until a valid pool is found
3. If all pools are empty -> grant fallback Doubloons scaled to chest tier

Silent failure is never acceptable. The player always receives a reward and the result always reflects what happened.

---

## 6. Ownership Rule

A fruit counts as owned if it exists in the player's **collection, inventory, or equipped slot**. This prevents bypassing duplicate conversion by consuming a fruit before opening a chest.

`DevilFruitInventoryService` is the single source of truth. The resolver calls `IsOwned()` only from there - never queries inventory and equipment state independently.

---

## 7. Duplicate Conversion

Duplicates are resolved immediately during the same resolver execution.

| Duplicate Rarity | Conversion |
|---|---|
| Common | Doubloons (scaled) |
| Rare | Rare Devil Fruit Chest |
| Legendary | Legendary Devil Fruit Chest |
| Mythic | +1 Mythic Key (see Section 8) |

Converted chests enter the player's inventory through the same pipeline as any other chest.

---

## 8. Mythic Key System

Mythic duplicates grant keys instead of a chest directly, to prevent Mythic self-looping.

- 1 Mythic duplicate -> 1 Mythic Key
- 3 Mythic Keys -> 1 Mythic Devil Fruit Chest (auto-converts immediately)

**Auto-convert behavior**

Conversion happens inside the same resolver execution as the duplicate that triggered it. Keys are consumed and the chest is granted before the result is returned. The player receives the final state (`3/3 -> chest granted`) - the UI never sees an intermediate `3/3` without conversion.

```
MythicKey = {
    Threshold   = 3,
    AutoConvert = true,
}
```

---

## 9. Devil Fruit Chests

Devil Fruit Chests are a special chest type that guarantees a fruit. They are distributed through quests, events, and optionally monetization.

**Behavior**
- Use the **same fruit-resolution pipeline** as regular chests
- Do **not** grant baseline food, materials, or Doubloons on open
- Skip the 10% gate - go straight to rarity roll
- May carry a `FruitRarity` bias in metadata to weight toward a specific tier
- Prefer unowned fruits within the resolved rarity pool whenever possible
- Only apply duplicate conversion if the player already owns the entire resolved rarity pool
- This avoids redundant same-rarity chest loops while still preventing dead rewards for fully completed pools

---

## 10. Chest Metadata Schema

All chests share a unified schema, covering both regular and Devil Fruit chests.

```
Chest = {
    ChestKind     = "Standard" | "DevilFruit",
    Tier          = "Wooden" | "Iron" | "Gold" | "Legendary",
    FruitRarity   = "Common" | "Rare" | "Legendary" | "Mythic" | nil,
    Source        = "Run" | "Quest" | "Event" | "Purchase",
    RewardProfile = "Default" | ...,
    CreatedAt     = timestamp,
}
```

This schema must be backward-compatible with any chests currently sitting in player inventories unopened.

---

## 11. Structured Result

`openChest` returns a single structured result object. The UI layer reads from this - it never parses message strings to determine reward state.

```
OpenResult = {
    -- Base rewards
    GrantedResources = { food=..., materials=..., doubloons=... },

    -- Fruit result
    GrantedFruit        = fruitId | nil,
    GrantedFruitRarity  = "Common" | "Rare" | "Legendary" | "Mythic" | nil,
    WasDuplicate        = boolean,

    -- Conversion (populated if WasDuplicate = true)
    ConversionRewardType   = "Chest" | "MythicKey" | "Doubloons" | nil,
    ConversionRewardRarity = "Rare" | "Legendary" | "Mythic" | nil,

    -- Mythic key state (always included)
    MythicKeyProgress        = { current=0, threshold=3 },
    AutoConvertedMythicChest = boolean,

    -- Granted chest (if conversion produced one)
    GrantedChest = { kind=..., tier=..., fruitRarity=... } | nil,

    -- Display
    Message = string | localizationKey,
}
```

`Message` is either a raw display string or a localization key - the UI layer is responsible for resolving it. Example messages:

- `"Obtained: Mera Mera no Mi (Legendary)"`
- `"Already owned - converted to Legendary Chest"`
- `"Mythic Key +1 (2/3)"`
- `"Mythic Keys complete - Mythic Chest granted"`

---

## 12. Full Config Reference

```
Config = {
    FruitGateChanceByTier = {
        Wooden    = 0.0,
        Iron      = 0.0,
        Gold      = 0.0,
        Legendary = 0.10,
    },

    FruitRarityWeights = {
        Common    = 0.60,
        Rare      = 0.30,
        Legendary = 0.09,
        Mythic    = 0.01,
    },

    DevilFruitChestGrantsBaseRewards = false,

    DuplicateConversion = {
        Common    = { type="Doubloons", scaleByTier=true },
        Rare      = { type="Chest", tier="Rare" },
        Legendary = { type="Chest", tier="Legendary" },
        Mythic    = { type="MythicKey", amount=1 },
    },

    MythicKey = {
        Threshold   = 3,
        AutoConvert = true,
    },

    FallbackReward = {
        type        = "Doubloons",
        scaleByTier = true,
    },
}
```

---

## 13. Opening Flows

### Standard chest (Wooden / Iron / Gold)
1. Grant base rewards -> end

### Legendary chest
1. Grant base rewards
2. Roll 10% gate -> if fail, end
3. Roll weighted rarity
4. Resolve effective rarity (Section 5 fallback if needed)
5. Pick fruit from pool
6. Check ownership (Section 6)
7. Grant or convert (Section 7-Section 8)
8. Return structured result (Section 11)

### Devil Fruit Chest
1. Do not grant base rewards
2. Skip gate
3. Roll weighted rarity (or use `FruitRarity` bias from metadata)
4. Resolve effective rarity (Section 5 fallback if needed)
5. Pick fruit from pool
6. Check ownership (Section 6)
7. Grant or convert (Section 7-Section 8)
8. Return structured result (Section 11)

---

## 14. Design Principles

- Skill is the primary progression driver - depth unlocks reward quality
- Fruits are rare and memorable, not routine drops
- No dead rewards - every duplicate converts into something
- One reward pipeline for all chest types
- Monetization accelerates access, not outcomes
