# GamePadHelper

**Version:** 1.06.13  
**Authors:** olegbl, quelron  
**API:** 101049

GamePadHelper is a modular collection of quality-of-life improvements for Elder Scrolls Online, built specifically for gamepad and console UI.

Price data can use supported sources such as TamrielTradeCentre and Tamriel Savings Co Price Fetcher / TSC data packages when available.

## What's New in 1.06.13

- **Notifications entry** - `What's New` now appears in the gamepad Notifications menu instead of using an automatic popup.
- **Inventory Trait refresh** - bag, bank, and deconstruction trait icons now update colors, counts, and icon switching more reliably.
- **Private Multi-Icon helper** - GamePadHelper no longer depends on `LibMultiIcon`. If you installed the standalone library for older builds, remove or disable it.
- **Map Search cache reuse** - city service scan data is now reused across `ReloadUI` and relogin, and refreshes only after ESO API updates or when the cache is cleared.

## Installation

1. Extract the addon into:

   `Documents\Elder Scrolls Online\live\AddOns\GamePadHelper\`

2. Install the required libraries listed below.
3. If you previously installed **LibMultiIcon** for older GamePadHelper builds, remove or disable it.
4. Enable **GamePadHelper** in the AddOn Manager.

## Main Features

- **Overview Panel** - adds a two-column root menu overview with quest details on the left and daily reminders on the right.
- **Map Search** - adds a gamepad search tab for wayshrines, zones, houses, city services, daily quest givers, and travel NPCs.
- **Teleporter** - teleports to hovered zones from the world map and adds chat jump options.
- **Dungeon Finder** - shows pledge quest names in the finder list.
- **Fishing** - vibration, reel alert, automatic bait selection, and fallback bait support.
- **Auto Repair** - repairs equipped gear at merchants.
- **Auto Charge** - recharges weapons after combat using filled soul gems.
- **Antiquarian's Eye** - auto-slots and uses the collectible when appropriate.
- **Provisioning Filter** - hides low-level recipes below CP160.
- **Gear Comparison** - shows side-by-side item comparison panels.
- **Loot Offset** - moves the loot history panel upward to avoid chat overlap.

## Tooltip Features

- **Tooltip Price** - cleaner price display with supported market data.
- **Tooltip Enchantment** - cleaner enchantment formatting.
- **Tooltip Poison** - cleaner poison formatting.
- **Tooltip Trait** - improved trait visibility in tooltips.
- **Tooltip Font** - cleaner tooltip font for gamepad.

## Inventory Features

### Inventory Covetous Countess

Highlights treasures relevant to the **Covetous Countess** quest.

- **Green icon** - useful for the current active quest step.
- **White icon** - useful for the quest, but not the current active step.

### Inventory Trait

Shows trait research indicators in inventory, bank, and deconstruction.

- **Green** - only accessible copy with this trait; safe to research.
- **Yellow** - another copy with the same trait exists in your inventory.
- **Red** - another copy with the same trait exists in your bank.

Duplicate counts are shown under the icon where applicable. Locked items are excluded from duplicate counting.

## Required Libraries

- **LibCovetousCountess** - quest-step data for Inventory Covetous Countess.
- **LibItemLinkDecoder** - raw item link decoding for Tooltip Enchantment.
- **LibTraitResearch** - trait research data for Inventory Trait and Tooltip Trait.

## Optional Integrations

- **TamrielTradeCentre** - optional PC market price source.
- **TSCPriceDataAPIXBNA**
- **TSCPriceDataAPIPSNA**
- **TSCPriceDataAPIXBEU**
- **TSCPriceDataAPIPSEU**

Console price data is provided by Tamriel Savings Co Price Fetcher / TSC packages when installed:

https://tamrielsavings.com/price-fetcher

## Notes

- Every feature can be enabled or disabled individually from `Options > GPH Settings`.
- Optional integrations improve specific features but are not required for GamePadHelper to load.
- This addon is provided as-is. Please report issues on the GamePadHelper project page.
