# Burd's Survival Journals - Translation Guide

This document lists all translatable strings in the mod for community translators.

## Quick Start for Translators

### File Structure
Translation files are located in:
```
media/lua/shared/Translate/XX/
```
Where `XX` is the language code (e.g., `EN`, `CN`, `ES`, `FR`, `DE`, `RU`, etc.)

### File Naming Convention
Each translation file follows the pattern: `Category_XX.txt`
- `Sandbox_CN.txt` - Chinese sandbox options
- `UI_FR.txt` - French UI strings
- `Items_DE.txt` - German item names

### File Format
Translation files use Lua table syntax:
```lua
Category_XX = {
    Key_Name = "Translated text here",
    Another_Key = "Another translation",
}
```

### How to Create a New Translation
1. Copy all files from the `EN` folder to a new folder with your language code
2. Rename each file (e.g., `Sandbox_EN.txt` to `Sandbox_ES.txt`)
3. Change the table name in each file (e.g., `Sandbox_EN` to `Sandbox_ES`)
4. Translate all the values (keep the keys unchanged)

---

## Translation Files Reference

### Overview

| File | Keys | Purpose |
|------|------|---------|
| Sandbox_EN.txt | ~51 | Sandbox/server options |
| UI_EN.txt | ~210 | UI labels, buttons, messages, feedback, stats, profession names |
| IG_UI_EN.txt | ~60 | In-game UI elements (legacy) |
| ContextMenu_EN.txt | ~31 | Right-click menu options |
| Tooltip_EN.txt | ~80 | Item hover tooltips + inventory tooltip labels |
| ItemName_EN.txt | 6 | Item display names (module-prefixed keys) |
| Recipes_EN.txt | ~10 | Crafting recipe names |

**Total: ~450+ translation keys**

> **Note:** UI_EN.txt was significantly expanded in recent updates to support the new MainPanel UI, timed actions, recipe tab, search bar, and improved feedback messages.

---

## 1. Sandbox_EN.txt (51 keys)

Server/sandbox option names and tooltips shown in the game settings menu.

### Tab Names
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_Player` | Journals - Player |
| `Sandbox_BurdJournals_Loot` | Journals - Loot |
| `Sandbox_BurdJournals_Advanced` | Journals - Advanced |

### Player Settings - Master Toggle
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnableJournals` | Enable Survival Journals |
| `Sandbox_BurdJournals_EnableJournals_tooltip` | Master toggle for the entire survival journals system. |

### Player Settings - XP Recovery
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_XPRecoveryMode` | Clean Journal XP Mode |
| `Sandbox_BurdJournals_XPRecoveryMode_tooltip` | How much XP is recovered when reading a CLEAN journal (SET mode). Does not affect worn/bloody journals. |
| `Sandbox_BurdJournals_XPRecoveryMode_option1` | Full Recovery (100%) |
| `Sandbox_BurdJournals_XPRecoveryMode_option2` | Diminishing Returns |
| `Sandbox_BurdJournals_DiminishingFirstRead` | First Read XP % |
| `Sandbox_BurdJournals_DiminishingFirstRead_tooltip` | XP percentage on first read (50-100%). Only applies with Diminishing Returns. |
| `Sandbox_BurdJournals_DiminishingDecayRate` | Decay Per Read % |
| `Sandbox_BurdJournals_DiminishingDecayRate_tooltip` | XP reduction for each subsequent read (5-50%). |
| `Sandbox_BurdJournals_DiminishingMinimum` | Minimum XP % |
| `Sandbox_BurdJournals_DiminishingMinimum_tooltip` | Floor percentage that recovery cannot go below (0-50%). |

### Player Settings - XP Multiplier
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_JournalXPMultiplier` | Journal XP Multiplier |
| `Sandbox_BurdJournals_JournalXPMultiplier_tooltip` | Multiplier for XP gained from journals (0.25 = 25%, 1.0 = 100%, 2.0 = 200%). Applies to both worn and bloody journals. |

### Player Settings - Writing Requirements
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_RequirePenToWrite` | Require Pen to Write |
| `Sandbox_BurdJournals_RequirePenToWrite_tooltip` | Require a pen or pencil to log skills in a clean journal. |
| `Sandbox_BurdJournals_PenUsesPerLog` | Pen Uses Per Log |
| `Sandbox_BurdJournals_PenUsesPerLog_tooltip` | Pen durability consumed when logging skills (1-10). |
| `Sandbox_BurdJournals_RequireEraserToErase` | Require Eraser to Erase |
| `Sandbox_BurdJournals_RequireEraserToErase_tooltip` | Require an eraser to wipe clean journal contents. |

### Player Settings - Learning Time
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_LearningTimePerSkill` | Learning Time Per Skill (sec) |
| `Sandbox_BurdJournals_LearningTimePerSkill_tooltip` | Base time in seconds to learn each skill from a journal. Simulates reading/studying. |
| `Sandbox_BurdJournals_LearningTimePerTrait` | Learning Time Per Trait (sec) |
| `Sandbox_BurdJournals_LearningTimePerTrait_tooltip` | Base time in seconds to absorb each trait from a journal. |
| `Sandbox_BurdJournals_LearningTimeMultiplier` | Learning Time Multiplier |
| `Sandbox_BurdJournals_LearningTimeMultiplier_tooltip` | Global multiplier for all learning times. 0.5 = twice as fast, 2.0 = twice as slow. |

### Player Settings - Stat Recording
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnableStatRecording` | Enable Stat Recording |
| `Sandbox_BurdJournals_EnableStatRecording_tooltip` | Master toggle for recording player stats (kills, survival time, etc.) in personal journals. |
| `Sandbox_BurdJournals_RecordZombieKills` | Record Zombie Kills |
| `Sandbox_BurdJournals_RecordZombieKills_tooltip` | Allow players to record their zombie kill count in journals. |
| `Sandbox_BurdJournals_RecordHoursSurvived` | Record Hours Survived |
| `Sandbox_BurdJournals_RecordHoursSurvived_tooltip` | Allow players to record their survival time in journals. |

### Player Settings - Baseline Restriction
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnableBaselineRestriction` | Only Record Earned Progress |
| `Sandbox_BurdJournals_EnableBaselineRestriction_tooltip` | When enabled, journals only record XP earned through gameplay - not profession starting bonuses or trait skill boosts. This prevents exploits where players farm profession skills by creating multiple characters. Recommended ON for multiplayer servers. |

### Recipe Recording
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnableRecipeRecording` | Enable Recipe Recording |
| `Sandbox_BurdJournals_EnableRecipeRecording_tooltip` | Allow players to record magazine-learned recipes in journals. Recipes learned from magazines can be shared with others. |
| `Sandbox_BurdJournals_LearningTimePerRecipe` | Learning Time Per Recipe (sec) |
| `Sandbox_BurdJournals_LearningTimePerRecipe_tooltip` | Base time in seconds to learn each recipe from a journal. |

### Loot Settings - Worn Journals
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnableWornJournalSpawns` | Enable Worn Journal Spawns |
| `Sandbox_BurdJournals_EnableWornJournalSpawns_tooltip` | Allow worn journals to spawn in world containers (shelves, desks, cabinets). These offer light XP rewards. |
| `Sandbox_BurdJournals_WornJournalSpawnChance` | Worn Spawn Chance % |
| `Sandbox_BurdJournals_WornJournalSpawnChance_tooltip` | Chance for worn journals to appear in world containers (0.1-100%). |
| `Sandbox_BurdJournals_WornJournalMinSkills` | Worn Min Skills |
| `Sandbox_BurdJournals_WornJournalMinSkills_tooltip` | Minimum skills in world-found worn journals. |
| `Sandbox_BurdJournals_WornJournalMaxSkills` | Worn Max Skills |
| `Sandbox_BurdJournals_WornJournalMaxSkills_tooltip` | Maximum skills in world-found worn journals. |
| `Sandbox_BurdJournals_WornJournalMinXP` | Worn Min XP/Skill |
| `Sandbox_BurdJournals_WornJournalMinXP_tooltip` | Minimum XP per skill in worn journals. |
| `Sandbox_BurdJournals_WornJournalMaxXP` | Worn Max XP/Skill |
| `Sandbox_BurdJournals_WornJournalMaxXP_tooltip` | Maximum XP per skill in worn journals. |

### Loot Settings - Bloody Journals
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnableBloodyJournalSpawns` | Enable Bloody Journal Drops |
| `Sandbox_BurdJournals_EnableBloodyJournalSpawns_tooltip` | Allow zombies to drop bloody journals. These offer better rewards and rare traits. |
| `Sandbox_BurdJournals_BloodyJournalSpawnChance` | Bloody Drop Chance % |
| `Sandbox_BurdJournals_BloodyJournalSpawnChance_tooltip` | Chance for a zombie to drop a bloody journal (0.1-100%). |
| `Sandbox_BurdJournals_BloodyJournalMinSkills` | Bloody Min Skills |
| `Sandbox_BurdJournals_BloodyJournalMinSkills_tooltip` | Minimum skills in zombie-dropped bloody journals. |
| `Sandbox_BurdJournals_BloodyJournalMaxSkills` | Bloody Max Skills |
| `Sandbox_BurdJournals_BloodyJournalMaxSkills_tooltip` | Maximum skills in zombie-dropped bloody journals. |
| `Sandbox_BurdJournals_BloodyJournalMinXP` | Bloody Min XP/Skill |
| `Sandbox_BurdJournals_BloodyJournalMinXP_tooltip` | Minimum XP per skill in bloody journals. |
| `Sandbox_BurdJournals_BloodyJournalMaxXP` | Bloody Max XP/Skill |
| `Sandbox_BurdJournals_BloodyJournalMaxXP_tooltip` | Maximum XP per skill in bloody journals. |
| `Sandbox_BurdJournals_BloodyJournalTraitChance` | Rare Trait Chance % |
| `Sandbox_BurdJournals_BloodyJournalTraitChance_tooltip` | Chance for bloody journals to include a grantable trait (Brave, Organized, etc.). |
| `Sandbox_BurdJournals_BloodyJournalMaxTraits` | Max Traits Per Bloody |
| `Sandbox_BurdJournals_BloodyJournalMaxTraits_tooltip` | Maximum number of traits that can spawn on a single bloody journal (0-5). |

### Loot Settings - Recipe/Magazine Spawns
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_WornJournalRecipeChance` | Worn Recipe Chance % |
| `Sandbox_BurdJournals_WornJournalRecipeChance_tooltip` | Chance for worn journals to include a magazine recipe (0-100%). Worn journals have a lower chance than bloody. |
| `Sandbox_BurdJournals_BloodyJournalRecipeChance` | Bloody Recipe Chance % |
| `Sandbox_BurdJournals_BloodyJournalRecipeChance_tooltip` | Chance for bloody journals to include magazine recipes (0-100%). Bloody journals have a higher chance than worn. |
| `Sandbox_BurdJournals_BloodyJournalMaxRecipes` | Max Recipes Per Bloody |
| `Sandbox_BurdJournals_BloodyJournalMaxRecipes_tooltip` | Maximum number of magazine recipes that can spawn on a single bloody journal (1-5). |

### Advanced Settings
| Key | English Value |
|-----|---------------|
| `Sandbox_BurdJournals_EnablePlayerJournals` | Enable Player Journals |
| `Sandbox_BurdJournals_EnablePlayerJournals_tooltip` | Allow players to craft and use personal journals for recording/recovering skills. Disable to only allow looted journals. |
| `Sandbox_BurdJournals_ReadingSkillAffectsSpeed` | Reading Skill Affects Speed |
| `Sandbox_BurdJournals_ReadingSkillAffectsSpeed_tooltip` | Higher reading skill levels reduce learning time when absorbing from journals. |
| `Sandbox_BurdJournals_ReadingSpeedBonus` | Reading Speed Bonus |
| `Sandbox_BurdJournals_ReadingSpeedBonus_tooltip` | Speed bonus per reading skill level (0.1 = 10% faster per level, max 100% at level 10). |
| `Sandbox_BurdJournals_EraseTime` | Erase Time (seconds) |
| `Sandbox_BurdJournals_EraseTime_tooltip` | Time in seconds to erase a journal's contents. |
| `Sandbox_BurdJournals_ConvertTime` | Convert Time (seconds) |
| `Sandbox_BurdJournals_ConvertTime_tooltip` | Time in seconds to convert a worn journal to a clean journal. |
| `Sandbox_BurdJournals_AllowOthersToOpenJournals` | Allow Others to Open Personal Journals |
| `Sandbox_BurdJournals_AllowOthersToOpenJournals_tooltip` | If enabled, other players can open and view personal journals they didn't create. If disabled, only the journal's author can open it. |
| `Sandbox_BurdJournals_AllowOthersToClaimFromJournals` | Allow Others to Claim from Personal Journals |
| `Sandbox_BurdJournals_AllowOthersToClaimFromJournals_tooltip` | If enabled, other players can claim skills/traits from personal journals they didn't create. Requires 'Allow Others to Open' to be enabled. If disabled, only the author can claim from their own journals. |
| `Sandbox_BurdJournals_AllowNegativeTraits` | Allow Negative Traits |
| `Sandbox_BurdJournals_AllowNegativeTraits_tooltip` | If enabled, negative traits (like Clumsy, Slow Learner, etc.) can appear in journals and be recorded. Useful for modded traits or challenge runs. Default: OFF (only positive traits). |

---

## 2. UI_EN.txt (~172 keys)

Main UI labels, buttons, messages, feedback, and condition states. This file was significantly expanded to support the new MainPanel UI system.

### Journal Types
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_BlankJournal` | Blank Survival Journal |
| `UI_BurdJournals_FilledJournal` | Filled Survival Journal |
| `UI_BurdJournals_WornJournal` | Worn Survival Journal |
| `UI_BurdJournals_BloodyJournal` | Bloody Survival Journal |

### Journal Name States (Dynamic Item Names)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_StateWorn` | Worn |
| `UI_BurdJournals_StateBloody` | Bloody |
| `UI_BurdJournals_PreviousProfession` | Previous %s |

### Journal Info Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_Author` | Author |
| `UI_BurdJournals_Written` | Written |
| `UI_BurdJournals_TimesRead` | Times Read |
| `UI_BurdJournals_Condition` | Condition |
| `UI_BurdJournals_NeedsCleaning` | Needs Cleaning |

### UI Buttons (Legacy)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_SelectAll` | Select All |
| `UI_BurdJournals_DeselectAll` | Deselect All |
| `UI_BurdJournals_Log` | Log Skills |
| `UI_BurdJournals_Learn` | Learn |
| `UI_BurdJournals_Update` | Update |
| `UI_BurdJournals_Erase` | Erase |
| `UI_BurdJournals_Close` | Close |
| `UI_BurdJournals_Absorb` | Absorb |
| `UI_BurdJournals_AbsorbAll` | Absorb All |

### Confirmation Dialogs
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ConfirmErase` | Are you sure you want to erase this journal? All recorded skills will be lost forever. |
| `UI_BurdJournals_ConfirmOverwrite` | This will overwrite the existing journal contents with your current skills. Are you sure? |
| `UI_BurdJournals_ConfirmConvert` | This will destroy the remaining rewards. Are you sure? |
| `UI_BurdJournals_ConfirmDisassemble` | Disassemble this journal? |
| `UI_BurdJournals_RenamePrompt` | Enter a new name for this journal: |
| `UI_BurdJournals_ConfirmAbsorbAll` | Absorb all remaining rewards? |
| `UI_BurdJournals_SkillCount` | %d skill |
| `UI_BurdJournals_SkillsCount` | %d skills |
| `UI_BurdJournals_RareTraitCount` | %d rare trait |
| `UI_BurdJournals_RareTraitsCount` | %d rare traits |
| `UI_BurdJournals_MaxedSkillsSkipped` | Maxed skills and known traits will be skipped. |

### Messages (Legacy)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_NoSkillsSelected` | Select at least one skill first. |
| `UI_BurdJournals_SkillsLogged` | Skills recorded in journal. |
| `UI_BurdJournals_SkillsLearned` | Knowledge absorbed from the journal! |
| `UI_BurdJournals_JournalErased` | Journal contents erased. |
| `UI_BurdJournals_JournalCleaned` | The journal has been cleaned and is now readable. |
| `UI_BurdJournals_JournalUpdated` | Journal skills updated. |
| `UI_BurdJournals_JournalRenamed` | Journal renamed. |
| `UI_BurdJournals_JournalConverted` | Journal converted to a clean blank journal. |
| `UI_BurdJournals_JournalDissolved` | The journal crumbles in your hands... |

### Dissolution Messages (Random spoken text when journal is fully consumed)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_Dissolve1` | Looks like that journal was on its last read... |
| `UI_BurdJournals_Dissolve2` | The pages crumble to dust in your hands... |
| `UI_BurdJournals_Dissolve3` | That was all it had left to give... |
| `UI_BurdJournals_Dissolve4` | The journal falls apart as you close it... |
| `UI_BurdJournals_Dissolve5` | Nothing but scraps remain... |
| `UI_BurdJournals_Dissolve6` | The binding finally gives way... |
| `UI_BurdJournals_Dissolve7` | It served its purpose... |
| `UI_BurdJournals_Dissolve8` | The ink fades completely as you finish reading... |
| `UI_BurdJournals_Dissolve9` | The worn pages disintegrate... |
| `UI_BurdJournals_Dissolve10` | Knowledge absorbed, the journal fades away... |
### Condition States
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ConditionPristine` | Pristine |
| `UI_BurdJournals_ConditionGood` | Good |
| `UI_BurdJournals_ConditionWorn` | Worn |
| `UI_BurdJournals_ConditionDamaged` | Damaged |
| `UI_BurdJournals_ConditionCritical` | Critical |

### Inspect Tooltips
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_InspectBlank` | A blank journal in %1 condition. |
| `UI_BurdJournals_InspectFilled` | A journal written by %1. Condition: %2 |
| `UI_BurdJournals_InspectWorn` | A worn journal from %1. Condition: %2. Needs cleaning. |
| `UI_BurdJournals_InspectBloody` | A bloody journal from a corpse. Contains skills and traits from the fallen survivor. |

### Absorption UI (Legacy)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_RewardsRemaining` | rewards remaining |
| `UI_BurdJournals_SkillClaimed` | CLAIMED |
| `UI_BurdJournals_TraitAlreadyKnown` | Already Known |
| `UI_BurdJournals_ClickToAbsorb` | Click to absorb |

### Journal Type Headers (MainPanel)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_BloodyJournalHeader` | BLOODY JOURNAL |
| `UI_BurdJournals_WornJournalHeader` | WORN JOURNAL |
| `UI_BurdJournals_PersonalJournalHeader` | PERSONAL JOURNAL |
| `UI_BurdJournals_RecordProgressHeader` | RECORD PROGRESS |

### Rarity Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_RarityRare` | RARE |
| `UI_BurdJournals_RarityUncommon` | UNCOMMON |

### Flavor Text
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_BloodyFlavor` | Found on a fallen survivor... |
| `UI_BurdJournals_WornBloodyFlavor` | Recovered from the wasteland... |
| `UI_BurdJournals_WornFlavor` | An old survivor's notes... |
| `UI_BurdJournals_PersonalFlavor` | Your documented survival knowledge... |
| `UI_BurdJournals_RecordFlavor` | Document your survival skills... |

### Tab Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_TabSkills` | Skills |
| `UI_BurdJournals_TabTraits` | Traits |
| `UI_BurdJournals_TabStats` | Stats |
| `UI_BurdJournals_TabRecipes` | Recipes |

### Search Bar
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_SearchPlaceholder` | Search... |
| `UI_BurdJournals_ClearSearch` | Clear search |
| `UI_BurdJournals_NoSearchResults` | No results found |

### Recipe Tab
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_Recipes` | RECIPES |
| `UI_BurdJournals_RecipesAvailable` | (%d available) |
| `UI_BurdJournals_RecipesRecordable` | (%d recordable) |
| `UI_BurdJournals_NoRecipesRecorded` | No recipes recorded |
| `UI_BurdJournals_NoRecipesToRecord` | No magazine recipes learned |
| `UI_BurdJournals_NoRecipesAvailable` | No recipes available |
| `UI_BurdJournals_RecipeAlreadyKnown` | Already known |
| `UI_BurdJournals_RecipeClaimed` | Claimed |
| `UI_BurdJournals_LearnedRecipe` | Learned: %s |
| `UI_BurdJournals_AlreadyKnowRecipe` | Already know: %s |
| `UI_BurdJournals_RecipeFromMagazine` | From: %s |
| `UI_BurdJournals_RecipeCount` | %d recipe |
| `UI_BurdJournals_RecipesCount` | %d recipes |
| `UI_BurdJournals_PlusRecipe` | , +%d recipe |
| `UI_BurdJournals_PlusRecipes` | , +%d recipes |
| `UI_BurdJournals_RecipeAlreadyKnownCount` | %d recipe already known |
| `UI_BurdJournals_RecipesAlreadyKnownCount` | %d recipes already known |

### Stats Tab
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_Stats` | STATS |
| `UI_BurdJournals_StatsAvailable` | (%d available) |
| `UI_BurdJournals_StatsRecordable` | (%d recordable) |
| `UI_BurdJournals_StatZombieKills` | Zombie Kills |
| `UI_BurdJournals_StatZombieKillsDesc` | Total zombies killed |
| `UI_BurdJournals_StatHoursSurvived` | Hours Survived |
| `UI_BurdJournals_StatHoursSurvivedDesc` | Total hours alive in the apocalypse |
| `UI_BurdJournals_StatDays` | %d days |
| `UI_BurdJournals_StatHours` | %d hours |
| `UI_BurdJournals_StatDaysHours` | %d days, %d hours |

### MainPanel Buttons
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_BtnAbsorbAll` | Absorb All |
| `UI_BurdJournals_BtnClaimAll` | Claim All |
| `UI_BurdJournals_BtnRecordAll` | Record All |
| `UI_BurdJournals_BtnAbsorbTab` | Absorb %s |
| `UI_BurdJournals_BtnClaimTab` | Claim %s |
| `UI_BurdJournals_BtnRecordTab` | Record %s |
| `UI_BurdJournals_BtnClose` | Close |
| `UI_BurdJournals_BtnKeepReading` | Keep Reading |
| `UI_BurdJournals_BtnCancelClose` | Cancel & Close |
| `UI_BurdJournals_BtnQueue` | QUEUE |
| `UI_BurdJournals_BtnClaim` | CLAIM |
| `UI_BurdJournals_BtnRecord` | RECORD |
| `UI_BurdJournals_BtnErase` | Erase |

### Button States
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_StateReading` | Reading... |
| `UI_BurdJournals_StateClaiming` | Claiming... |
| `UI_BurdJournals_StateRecording` | Recording... |
| `UI_BurdJournals_StateErasing` | Erasing... |
| `UI_BurdJournals_ErasingProgress` | Erasing... %d%% |

### Feedback Messages (MainPanel)
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_AlreadyReading` | Already reading... |
| `UI_BurdJournals_AlreadyRecording` | Already recording... |
| `UI_BurdJournals_NoNewRewards` | No new rewards to claim |
| `UI_BurdJournals_AlreadyQueued` | Already queued |
| `UI_BurdJournals_AlreadyAtLevel` | Already at or above this level |
| `UI_BurdJournals_CantRecordStartingSkills` | Can't record starting skills |
| `UI_BurdJournals_CantRecordStartingTraits` | Can't record starting traits |
| `UI_BurdJournals_NothingNewToRecord` | Nothing new to record |
| `UI_BurdJournals_SavingProgress` | Saving progress... |
| `UI_BurdJournals_Queued` | Queued: %s |
| `UI_BurdJournals_CannotRecord` | Cannot record: %s |
| `UI_BurdJournals_SetSkillToLevel` | Set %s to recorded level |
| `UI_BurdJournals_SkillMaxed` | %s already at or above this level |
| `UI_BurdJournals_NoPlayer` | No player found |
| `UI_BurdJournals_GainedTrait` | Gained trait: %s |
| `UI_BurdJournals_FailedToAddTrait` | Failed to add trait: %s |
| `UI_BurdJournals_BaselineReset` | Baseline reset! |
| `UI_BurdJournals_GainedXP` | +%s %s |
| `UI_BurdJournals_JournalSyncFailed` | Error: Journal sync failed |
| `UI_BurdJournals_EntryErased` | Entry erased: %s |
| `UI_BurdJournals_PlusTrait` | , +%d trait |
| `UI_BurdJournals_PlusTraits` | , +%d traits |
| `UI_BurdJournals_SkillAlreadyMaxed` | %d skill already maxed |
| `UI_BurdJournals_SkillsAlreadyMaxed` | %d skills already maxed |
| `UI_BurdJournals_TraitAlreadyKnown` | %d trait already known |
| `UI_BurdJournals_TraitsAlreadyKnown` | %d traits already known |

### Empty States
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_NoRewardsAvailable` | No rewards available |
| `UI_BurdJournals_NoSkillsRecorded` | No skills recorded |
| `UI_BurdJournals_NoRareTraits` | No rare traits found |
| `UI_BurdJournals_NoTraitsAvailable` | No traits available |
| `UI_BurdJournals_NoTraitsRecorded` | No traits recorded |
| `UI_BurdJournals_NoStatsRecorded` | No stats recorded |
| `UI_BurdJournals_NothingToRecord` | Nothing to record |
| `UI_BurdJournals_NoSkillsToRecord` | No skills to record |
| `UI_BurdJournals_NoTraitsToRecord` | No traits to record |
| `UI_BurdJournals_NoStatsEnabled` | No stat recording enabled |
| `UI_BurdJournals_NoContent` | No content |
| `UI_BurdJournals_TraitAlreadyKnownFeedback` | You already have this trait |

### Status Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_StatusAlreadyKnown` | Already known |
| `UI_BurdJournals_StatusAlreadyClaimed` | Already claimed |
| `UI_BurdJournals_StatusAlreadyRecorded` | Already recorded |
| `UI_BurdJournals_StatusClaimed` | Claimed |
| `UI_BurdJournals_RareTraitQueued` | Rare trait - Queued #%d |
| `UI_BurdJournals_NegativeTraitQueued` | Cursed trait - Queued #%d |
| `UI_BurdJournals_RareTraitBonus` | Rare trait bonus! |
| `UI_BurdJournals_RareTraitBonusQueued` | Rare trait bonus! - Queued |
| `UI_BurdJournals_NegativeTraitCurse` | Cursed knowledge... |
| `UI_BurdJournals_NegativeTraitCurseQueued` | Cursed knowledge... - Queued |

### Author Box
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_RecordingFor` | Recording progress for %s |
| `UI_BurdJournals_FromNotesOf` | From the notes of %s |
| `UI_BurdJournals_UnknownSurvivor` | Unknown Survivor |
| `UI_BurdJournals_Unknown` | Unknown |

### Headers
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_YourSkills` | YOUR SKILLS |
| `UI_BurdJournals_Skills` | SKILLS |
| `UI_BurdJournals_Traits` | TRAITS |
| `UI_BurdJournals_Available` | (%d available) |
| `UI_BurdJournals_Recordable` | (%d recordable) |
| `UI_BurdJournals_Claimable` | (%d claimable) |

### Progress Format
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ReadingAllProgress` | Reading All: %d%% (%s remaining) |
| `UI_BurdJournals_ReadingProgress` | Reading... %d%% |
| `UI_BurdJournals_RecordingProgress` | Recording... %d%% |
| `UI_BurdJournals_AbsorbingProgress` | Absorbing... %d%% |
| `UI_BurdJournals_LearningProgress` | Learning... %d%% |
| `UI_BurdJournals_RecordingAllProgress` | Recording All: %d%% (%s remaining) |
| `UI_BurdJournals_ClaimingAllProgress` | Claiming All: %d%% (%s remaining) |
| `UI_BurdJournals_AbsorbingAllProgress` | Absorbing All: %d%% (%s remaining) |
| `UI_BurdJournals_ItemCount` | %d item |
| `UI_BurdJournals_ItemCountPlural` | %d items |
| `UI_BurdJournals_RewardQueued` | %d reward queued |
| `UI_BurdJournals_RewardsQueued` | %d rewards queued |
| `UI_BurdJournals_SummaryTotalXP` | Total: +%s XP |
| `UI_BurdJournals_SummaryTrait` | %d trait |
| `UI_BurdJournals_SummaryTraits` | %d traits |
| `UI_BurdJournals_SummarySeparator` | \|  (separator between XP and traits) |

### Skill/Trait Row Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_LevelFormat` | Lv %d |
| `UI_BurdJournals_XPFormat` | %d XP |
| `UI_BurdJournals_XPWithBaseline` | %s XP (+%s starting) |
| `UI_BurdJournals_StartingXP` | Starting: %s XP |
| `UI_BurdJournals_CurrentLevel` | Current: Lv %d |
| `UI_BurdJournals_RecordedLevel` | Recorded: Lv %d |
| `UI_BurdJournals_RecordedXP` | Recorded: %s XP |
| `UI_BurdJournals_RecordedWas` | %s XP (was %s) |
| `UI_BurdJournals_SpawnedWith` | Spawned with |
| `UI_BurdJournals_YourTrait` | Your trait |
| `UI_BurdJournals_QueuedNumber` | Queued #%d |
| `UI_BurdJournals_NowWas` | Now: %s (was %s) |
| `UI_BurdJournals_RecordedValue` | Recorded: %s |
| `UI_BurdJournals_CurrentValue` | Current: %s |
| `UI_BurdJournals_RecordedAchieved` | Recorded: %s (achieved!) |
| `UI_BurdJournals_RecordedVsCurrent` | Recorded: %s \| Current: %s |
| `UI_BurdJournals_CurrentQueued` | Current: %s - Queued #%d |

### Client Messages
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_SkillsRecorded` | Skills recorded! |
| `UI_BurdJournals_JournalErased` | Journal erased |
| `UI_BurdJournals_JournalCleaned` | Journal cleaned |
| `UI_BurdJournals_JournalRebound` | Journal rebound |
| `UI_BurdJournals_ProgressSaved` | Progress saved! |
| `UI_BurdJournals_RecordedItem` | Recorded %s |
| `UI_BurdJournals_RecordedItems` | Recorded %s |
| `UI_BurdJournals_RecordedItemsMore` | Recorded %s, %s +%d more |
| `UI_BurdJournals_ClaimedSkill` | Claimed: %s (+%s XP) |
| `UI_BurdJournals_LearnedTrait` | Learned: %s |
| `UI_BurdJournals_AlreadyKnowTrait` | Already know: %s |
| `UI_BurdJournals_SkillAlreadyMaxedMsg` | %s is already maxed! |

### Timed Actions
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_JournalRestored` | Journal restored! |
| `UI_BurdJournals_JournalBound` | Journal bound! |
| `UI_BurdJournals_Salvaged` | Salvaged: %s |
| `UI_BurdJournals_JournalDisassembled` | Journal disassembled. |

### Dialog Strings
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ConfirmCancelLearning` | Cancel learning and close? |
| `UI_BurdJournals_RecordedTrait` | Recorded trait |
| `UI_BurdJournals_RecordedRecipe` | Recorded recipe |

### Recipe Knowledge Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_RecipeKnowledge` | Recipe knowledge |
| `UI_BurdJournals_RecipeKnowledgeQueued` | Recipe knowledge - Queued |
| `UI_BurdJournals_RecipeKnowledgeQueuedNum` | Recipe knowledge - Queued #%d |

### Fallback Text
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_UnknownTrait` | Unknown Trait |

### Capacity Warnings
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ApproachingCapacity` | Journal approaching capacity: %s |
| `UI_BurdJournals_CapacitySkills` | Skills: %d/%d |
| `UI_BurdJournals_CapacityTraits` | Traits: %d/%d |
| `UI_BurdJournals_CapacityRecipes` | Recipes: %d/%d |

### Profession Names (Dynamic Journal Names)
These keys are used for journal item names that include profession information (e.g., "Filled Survival Journal (Bloody - Former Mechanic)").

| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ProfSurvivor` | Survivor |
| `UI_BurdJournals_UnknownSurvivor` | Unknown Survivor |

**WorldSpawn Professions** (found in world containers):
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ProfFireOfficer` | Fire Officer |
| `UI_BurdJournals_ProfPoliceOfficer` | Police Officer |
| `UI_BurdJournals_ProfParkRanger` | Park Ranger |
| `UI_BurdJournals_ProfConstructionWorker` | Construction Worker |
| `UI_BurdJournals_ProfSecurityGuard` | Security Guard |
| `UI_BurdJournals_ProfCarpenter` | Carpenter |
| `UI_BurdJournals_ProfBurglar` | Burglar |
| `UI_BurdJournals_ProfChef` | Chef |
| `UI_BurdJournals_ProfRepairman` | Repairman |
| `UI_BurdJournals_ProfFarmer` | Farmer |
| `UI_BurdJournals_ProfFisherman` | Fisherman |
| `UI_BurdJournals_ProfDoctor` | Doctor |
| `UI_BurdJournals_ProfNurse` | Nurse |
| `UI_BurdJournals_ProfLumberjack` | Lumberjack |
| `UI_BurdJournals_ProfFitnessInstructor` | Fitness Instructor |
| `UI_BurdJournals_ProfBurgerFlipper` | Burger Flipper |
| `UI_BurdJournals_ProfElectrician` | Electrician |
| `UI_BurdJournals_ProfEngineer` | Engineer |
| `UI_BurdJournals_ProfMetalworker` | Metalworker |
| `UI_BurdJournals_ProfMechanic` | Mechanic |
| `UI_BurdJournals_ProfVeteran` | Veteran |
| `UI_BurdJournals_ProfUnemployed` | Unemployed |

**ZombieLoot Professions** (dropped by zombies - "Former X" format):
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ProfFormerFarmer` | Former Farmer |
| `UI_BurdJournals_ProfFormerMechanic` | Former Mechanic |
| `UI_BurdJournals_ProfFormerDoctor` | Former Doctor |
| `UI_BurdJournals_ProfFormerCarpenter` | Former Carpenter |
| `UI_BurdJournals_ProfFormerHunter` | Former Hunter |
| `UI_BurdJournals_ProfFormerSoldier` | Former Soldier |
| `UI_BurdJournals_ProfFormerChef` | Former Chef |
| `UI_BurdJournals_ProfFormerAthlete` | Former Athlete |
| `UI_BurdJournals_ProfFormerBurglar` | Former Burglar |
| `UI_BurdJournals_ProfFormerLumberjack` | Former Lumberjack |
| `UI_BurdJournals_ProfFormerFisherman` | Former Fisherman |
| `UI_BurdJournals_ProfFormerTailor` | Former Tailor |
| `UI_BurdJournals_ProfFormerElectrician` | Former Electrician |
| `UI_BurdJournals_ProfFormerMetalworker` | Former Metalworker |
| `UI_BurdJournals_ProfFormerSurvivalist` | Former Survivalist |
| `UI_BurdJournals_ProfFormerFighter` | Former Fighter |

---

## 3. IG_UI_EN.txt (60 keys)

In-game UI elements including context menus, data categories, and tooltips.

### Context Menu - Main Options
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_OpenJournal` | Open Journal... |
| `ContextMenu_BurdJournals_Read` | Read |
| `ContextMenu_BurdJournals_Rename` | Rename |
| `ContextMenu_BurdJournals_EraseJournal` | Erase Journal |
| `ContextMenu_BurdJournals_RecordProgress` | Record Progress |

### Context Menu - Clean/Repair
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_CleanRepair` | Clean/Repair |
| `ContextMenu_BurdJournals_CleanSoap` | Clean with Soap & Cloth |
| `ContextMenu_BurdJournals_RepairTape` | Patch with Duct Tape |
| `ContextMenu_BurdJournals_RepairLeather` | Rebind with Leather |
| `ContextMenu_BurdJournals_RepairGlue` | Glue Pages Together |

### UI Panel Titles
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_BlankJournal` | Blank Survival Journal |
| `UI_BurdJournals_FilledJournal` | Filled Survival Journal |
| `UI_BurdJournals_WornJournal` | Worn Survival Journal |

### Data Category Headers
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_CategoryCharacter` | Character Info |
| `UI_BurdJournals_CategorySurvival` | Survival Record |
| `UI_BurdJournals_CategoryKills` | Kill Tally |
| `UI_BurdJournals_CategoryTraits` | Personality Traits |
| `UI_BurdJournals_CategorySkills` | Learned Skills |

### UI Panel Labels
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_Author` | Author |
| `UI_BurdJournals_Written` | Written |
| `UI_BurdJournals_TimesRead` | Times Read |
| `UI_BurdJournals_Condition` | Condition |
| `UI_BurdJournals_NeedsCleaning` | Needs Cleaning |

### UI Buttons
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_SelectAll` | Select All |
| `UI_BurdJournals_DeselectAll` | Deselect All |
| `UI_BurdJournals_Log` | Log Skills |
| `UI_BurdJournals_Learn` | Learn |
| `UI_BurdJournals_Update` | Update |
| `UI_BurdJournals_Erase` | Erase |
| `UI_BurdJournals_Close` | Close |

### Confirmation Dialogs
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ConfirmErase` | Are you sure you want to erase this journal? All recorded skills will be lost forever. |
| `UI_BurdJournals_ConfirmOverwrite` | This will overwrite the existing journal contents with your current skills. Are you sure? |
| `UI_BurdJournals_RenamePrompt` | Enter a new name for this journal: |
| `UI_BurdJournals_NoSkillsSelected` | Select at least one skill first. |
| `UI_BurdJournals_NoSkillsInJournal` | This journal contains no skills to learn. |

### Condition States
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_ConditionPristine` | Pristine |
| `UI_BurdJournals_ConditionGood` | Good |
| `UI_BurdJournals_ConditionWorn` | Worn |
| `UI_BurdJournals_ConditionDamaged` | Damaged |
| `UI_BurdJournals_ConditionCritical` | Critical |

### Inspect Messages
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_InspectBlank` | A blank journal in %1 condition. |
| `UI_BurdJournals_InspectFilled` | A journal written by %1. Condition: %2 |

### Tooltips - Journal Info
| Key | English Value |
|-----|---------------|
| `Tooltip_BlankSurvivalJournal` | A blank journal ready to record your survival knowledge. |
| `Tooltip_FilledSurvivalJournal` | A journal containing recorded survival skills. Right-click to read. |
| `Tooltip_BurdJournals_ContainsSkills` | Contains %1 skill(s) recorded |

### Tooltips - Requirements
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_NeedPen` | Requires a pen or pencil to write. |
| `Tooltip_BurdJournals_NeedEraser` | Requires an eraser to wipe the contents. |
| `Tooltip_BurdJournals_NeedsCleaning` | This journal is too worn to read. |
| `Tooltip_BurdJournals_NeedsCleaningDesc` | Use soap and cloth to clean it, duct tape to patch it, or leather strips to rebind it. |

### Tooltips - Cleaning Materials
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_MissingMaterials` | Missing Materials |
| `Tooltip_BurdJournals_NeedsSoapCloth` | Requires: Soap + Ripped Sheets or Dish Cloth |
| `Tooltip_BurdJournals_NeedsTape` | Requires: Duct Tape |
| `Tooltip_BurdJournals_NeedsLeatherBinding` | Requires: Leather Strips + Thread + Needle |
| `Tooltip_BurdJournals_NeedsGluePaper` | Requires: Glue + Sheet of Paper |

### Illiterate Trait Block
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_IlliterateName` | Illiterate |
| `Tooltip_BurdJournals_IlliterateDesc` | You cannot read or write. Journals are useless to you. |

### Feedback Messages
| Key | English Value |
|-----|---------------|
| `UI_BurdJournals_SkillsLogged` | Skills recorded in journal. |
| `UI_BurdJournals_SkillsLearned` | Knowledge absorbed from the journal! |
| `UI_BurdJournals_JournalErased` | Journal contents erased. |
| `UI_BurdJournals_JournalCleaned` | The journal has been cleaned and is now readable. |
| `UI_BurdJournals_JournalUpdated` | Journal skills updated. |
| `UI_BurdJournals_JournalRenamed` | Journal renamed. |

---

## 4. ContextMenu_EN.txt (24 keys)

Right-click context menu options.

### Journal Actions
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_OpenJournal` | Open Journal... |
| `ContextMenu_BurdJournals_Read` | Read Journal |
| `ContextMenu_BurdJournals_Rename` | Rename |
| `ContextMenu_BurdJournals_EraseJournal` | Erase Journal |
| `ContextMenu_BurdJournals_RecordProgress` | Record Progress |
| `ContextMenu_BurdJournals_UpdateRecords` | Update Records |
| `ContextMenu_BurdJournals_ClaimAll` | Claim All Skills |

### Bind Journal (Context Menu Crafting)
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_BindAsSurvivalJournal` | Bind as Survival Journal |
| `ContextMenu_BurdJournals_BindAsSurvivalJournal_Missing` | Bind as Survival Journal (Missing Materials) |
| `ContextMenu_BurdJournals_BindAsSurvivalJournal_NoTailoring` | Bind as Survival Journal (Requires Tailoring 1) |

### Bloody Journal
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_BloodyBlank` | Bloody Blank Journal |
| `ContextMenu_BurdJournals_ConvertViaCrafting` | Convert to Personal Journal (Crafting) |

### Worn Journal
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_WornBlank` | Worn Blank Journal |
| `ContextMenu_BurdJournals_AbsorbAll` | Absorb All Rewards |
| `ContextMenu_BurdJournals_ConvertToClean` | Rebind as Personal Journal |

### Absorb All Dynamic Labels
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_AbsorbAllFormat` | Absorb All (%s) |
| `ContextMenu_BurdJournals_SkillCount` | %d skill |
| `ContextMenu_BurdJournals_SkillsCount` | %d skills |
| `ContextMenu_BurdJournals_TraitCount` | %d trait |
| `ContextMenu_BurdJournals_TraitsCount` | %d traits |
| `ContextMenu_BurdJournals_RecipeCount` | %d recipe |
| `ContextMenu_BurdJournals_RecipesCount` | %d recipes |

### Personal Journal (Clean)
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_RecordAll` | Record All Progress |
| `ContextMenu_BurdJournals_Disassemble` | Disassemble Journal |

### Legacy (Clean/Repair)
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_CleanRepair` | Clean/Repair |
| `ContextMenu_BurdJournals_CleanSoap` | Clean with Soap & Cloth |
| `ContextMenu_BurdJournals_RepairTape` | Patch with Duct Tape |
| `ContextMenu_BurdJournals_RepairLeather` | Rebind with Leather |
| `ContextMenu_BurdJournals_RepairGlue` | Glue Pages Together |

### Illiterate Trait Block
| Key | English Value |
|-----|---------------|
| `ContextMenu_BurdJournals_CannotRead` | Cannot Read (Illiterate) |

---

## 5. Tooltip_EN.txt (56 keys)

Item hover tooltips, dynamic text, and requirement descriptions. Significantly expanded for improved context menu tooltips.

### Item Tooltips
| Key | English Value |
|-----|---------------|
| `Tooltip_BlankSurvivalJournal` | A blank journal ready to record your survival knowledge. |
| `Tooltip_FilledSurvivalJournal` | A journal containing recorded survival skills. Right-click to read. |

### Skill Info
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_ContainsSkills` | Contains %d skill(s) recorded |
| `Tooltip_BurdJournals_RewardsRemaining` | rewards remaining |
| `Tooltip_BurdJournals_SetModeDesc` | Reading will SET your XP to match recorded levels (if higher).\n\n |

### Tool Requirements
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_NeedPen` | Requires a pen or pencil to write. |
| `Tooltip_BurdJournals_NeedEraser` | Requires an eraser to wipe the contents. |

### Bloody Journal
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_BloodyJournal` | Bloody Journal |
| `Tooltip_BurdJournals_BloodyJournalDesc` | A journal from a fallen survivor. Contains skills and traits that can be absorbed. |
| `Tooltip_BurdJournals_BloodyDesc` | Rare find! May contain valuable traits. |
| `Tooltip_BurdJournals_ConvertBloodyToClean` | Convert to Clean Journal |
| `Tooltip_BurdJournals_ConvertBloodyToCleanDesc` | Use crafting to convert this bloody journal to a clean personal journal. |
| `Tooltip_BurdJournals_ConvertBloodyDesc` | Open the crafting menu (B) to find 'Clean and Convert Bloody Journal'.\nRequires: Soap, Cloth, Leather, Thread, Needle, Tailoring Lv1.\nWARNING: Destroys any remaining rewards! |
| `Tooltip_BurdJournals_CraftingRequired` | Crafting Required |

### Worn Journal
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_WornJournal` | Worn Journal |
| `Tooltip_BurdJournals_NeedsCleaning` | This journal is too worn to read. |
| `Tooltip_BurdJournals_NeedsCleaningDesc` | Use soap and cloth to clean it, duct tape to patch it, or leather strips to rebind it. |
| `Tooltip_BurdJournals_AbsorbAll` | Absorb All |
| `Tooltip_BurdJournals_AbsorbAllDesc` | Claim all remaining skills and traits at once. Journal will dissolve. |
| `Tooltip_BurdJournals_AbsorbAllRewards` | Absorb All Rewards |
| `Tooltip_BurdJournals_AbsorbAllSkillsTraits` | Absorb All (%d skills, %d traits) |
| `Tooltip_BurdJournals_AbsorbAllSkills` | Absorb All (%d skills) |

### Personal Journal (Clean)
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_PersonalJournal` | Personal Survival Journal |
| `Tooltip_BurdJournals_BlankJournal` | Blank Survival Journal |
| `Tooltip_BurdJournals_BlankJournalDesc` | Opens the journal to record your survival progress.\nRequires a writing tool. |
| `Tooltip_BurdJournals_RecordProgress` | Record Your Progress |
| `Tooltip_BurdJournals_RecordProgressDesc` | Opens journal to record your current skills and traits.\nRecorded values are only updated if your current level is higher. |
| `Tooltip_BurdJournals_ClaimAll` | Claim All Skills |
| `Tooltip_BurdJournals_ClaimAllDesc` | Opens journal and claims all available skills.\nThis will take time based on your reading speed. |
| `Tooltip_BurdJournals_UpdateRecords` | Update Journal Records |
| `Tooltip_BurdJournals_UpdateRecordsDesc` | Opens journal to update your recorded skills.\nRecorded values are only updated if your current level is higher. |
| `Tooltip_BurdJournals_Disassemble` | Disassemble Journal |
| `Tooltip_BurdJournals_DisassembleDesc` | Tear apart this journal for materials.\n\nYou will receive:\n  2x Paper\n  1x Leather Strips |
| `Tooltip_BurdJournals_EraseContents` | Erase All Contents |
| `Tooltip_BurdJournals_EraseContentsDesc` | Erases all recorded data, returning the journal to a blank state.\nRequires an eraser. |

### Dynamic Tooltip Text
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_SkillsAvailable` | Skills: %d/%d available |
| `Tooltip_BurdJournals_TraitsAvailable` | Traits: %d/%d available |
| `Tooltip_BurdJournals_NoRewardsFound` | No rewards found |
| `Tooltip_BurdJournals_WrittenBy` | Written by: %s |
| `Tooltip_BurdJournals_RecordedItem` | Contains %d recorded item |
| `Tooltip_BurdJournals_RecordedItems` | Contains %d recorded items |
| `Tooltip_BurdJournals_ClaimableRewards` | Claimable rewards: |
| `Tooltip_BurdJournals_SkillCount` | - %d skill |
| `Tooltip_BurdJournals_SkillsCount` | - %d skills |
| `Tooltip_BurdJournals_TraitCount` | - %d trait |
| `Tooltip_BurdJournals_TraitsCount` | - %d traits |
| `Tooltip_BurdJournals_AvailableSkill` | Available: %d skill |
| `Tooltip_BurdJournals_AvailableSkills` | Available: %d skills |
| `Tooltip_BurdJournals_AndTrait` | , %d trait |
| `Tooltip_BurdJournals_AndTraits` | , %d traits |
| `Tooltip_BurdJournals_ReadingSpeedNote` | This will take time based on your reading speed. |
| `Tooltip_BurdJournals_NoNewRewards` | No new rewards available. |
| `Tooltip_BurdJournals_ClaimingInfo` | Claiming sets your XP to the recorded level (if higher). |

### Access Control
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_ViewOnly` | View only |
| `Tooltip_BurdJournals_CannotClaimDefault` | Cannot claim from this journal. |
| `Tooltip_BurdJournals_CannotClaim` | Cannot Claim |
| `Tooltip_BurdJournals_NoPermissionClaim` | You don't have permission to claim from this journal. |
| `Tooltip_BurdJournals_CannotOpen` | Cannot Open |

### Conversion
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_ConvertToClean` | Rebind as Personal Survival Journal |
| `Tooltip_BurdJournals_ConvertToCleanDesc` | Rebind this worn journal into a clean blank survival journal for personal use. Requires tailoring supplies. |
| `Tooltip_BurdJournals_CannotConvert` | Cannot Convert |
| `Tooltip_BurdJournals_NeedsConvertMaterials` | Requires: Leather Strips + Thread + Needle + Tailoring Lv1 |

### Materials
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_MissingMaterials` | Missing Materials |
| `Tooltip_BurdJournals_NeedsSoapCloth` | Requires: Soap + Ripped Sheets or Dish Cloth |
| `Tooltip_BurdJournals_NeedsTape` | Requires: Duct Tape |
| `Tooltip_BurdJournals_NeedsLeatherBinding` | Requires: Leather Strips + Thread + Needle |
| `Tooltip_BurdJournals_NeedsGluePaper` | Requires: Glue + Sheet of Paper |

### Illiterate Trait Block
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_IlliterateName` | Illiterate |
| `Tooltip_BurdJournals_IlliterateDesc` | You cannot read or write. Journals are useless to you. |

### Inventory Tooltip Labels (Hover Info)
| Key | English Value |
|-----|---------------|
| `Tooltip_BurdJournals_Owner` | Owner: %s |
| `Tooltip_BurdJournals_OwnerYou` | (You) |
| `Tooltip_BurdJournals_Author` | Author: %s |
| `Tooltip_BurdJournals_Profession` | Profession: %s |
| `Tooltip_BurdJournals_SkillsLine` | Skills: %d/%d |
| `Tooltip_BurdJournals_SkillsLineXP` | Skills: %d/%d (%s XP) |
| `Tooltip_BurdJournals_AllClaimed` | (all claimed) |
| `Tooltip_BurdJournals_TraitsLine` | Traits: %d/%d |
| `Tooltip_BurdJournals_ConditionBloody` | Condition: Bloody |
| `Tooltip_BurdJournals_ConditionWorn` | Condition: Worn |
| `Tooltip_BurdJournals_ConditionRestored` | Condition: Restored |
| `Tooltip_BurdJournals_ConditionClean` | Condition: Clean |
| `Tooltip_BurdJournals_OriginZombie` | Origin: Recovered from zombie |
| `Tooltip_BurdJournals_OriginWorld` | Origin: Found in world |
| `Tooltip_BurdJournals_OriginCrafted` | Origin: Crafted |
| `Tooltip_BurdJournals_OriginFound` | Origin: Found |
| `Tooltip_BurdJournals_OriginPersonal` | Origin: Personal |
| `Tooltip_BurdJournals_Created` | Created: %s |
| `Tooltip_BurdJournals_LastUpdated` | Last Updated: %s |
| `Tooltip_BurdJournals_AgeToday` | Today |
| `Tooltip_BurdJournals_Age1Day` | 1 day ago |
| `Tooltip_BurdJournals_AgeDays` | %d days ago |

---

## 6. ItemName_EN.txt (6 keys)

Item display names shown in inventory.

> **IMPORTANT:** As of the recent update, item names use the `ItemName_XX.txt` filename format (not `Items_XX.txt`) with module-prefixed keys. This is the correct format required by Project Zomboid's translation system.

**Correct File Format:**
```lua
ItemName_XX = {
    -- Blank Journals
    ItemName_BurdJournals.BlankSurvivalJournal = "Blank Survival Journal",
    ItemName_BurdJournals.BlankSurvivalJournal_Worn = "Worn Blank Journal",
    ItemName_BurdJournals.BlankSurvivalJournal_Bloody = "Bloody Blank Journal",

    -- Filled Journals
    ItemName_BurdJournals.FilledSurvivalJournal = "Filled Survival Journal",
    ItemName_BurdJournals.FilledSurvivalJournal_Worn = "Worn Survival Journal",
    ItemName_BurdJournals.FilledSurvivalJournal_Bloody = "Bloody Survival Journal",
}
```

| Key | English Value |
|-----|---------------|
| `ItemName_BurdJournals.BlankSurvivalJournal` | Blank Survival Journal |
| `ItemName_BurdJournals.BlankSurvivalJournal_Worn` | Worn Blank Journal |
| `ItemName_BurdJournals.BlankSurvivalJournal_Bloody` | Bloody Blank Journal |
| `ItemName_BurdJournals.FilledSurvivalJournal` | Filled Survival Journal |
| `ItemName_BurdJournals.FilledSurvivalJournal_Worn` | Worn Survival Journal |
| `ItemName_BurdJournals.FilledSurvivalJournal_Bloody` | Bloody Survival Journal |

---

## 7. Recipes_EN.txt (16 keys)

Crafting recipe names for binding and restoring survival journals.

### Erase/Reset
| Key | English Value |
|-----|---------------|
| `EraseFilledJournal` | Erase Filled Journal |
| `Recipe_EraseFilledJournal` | Erase Filled Journal |

### Bind Recipes (Thread-based)
| Key | English Value |
|-----|---------------|
| `Bind_Thread_Leather` | Bind Survival Journal (Thread + Leather) |
| `Recipe_Bind_Thread_Leather` | Bind Survival Journal (Thread + Leather) |
| `Bind_Thread_AnyCover` | Bind Survival Journal (Thread + Fabric) |
| `Recipe_Bind_Thread_AnyCover` | Bind Survival Journal (Thread + Fabric) |

### Bind Recipes (Adhesive-based)
| Key | English Value |
|-----|---------------|
| `Bind_Adhesive_Leather` | Bind Survival Journal (Adhesive + Leather) |
| `Recipe_Bind_Adhesive_Leather` | Bind Survival Journal (Adhesive + Leather) |
| `Bind_Adhesive_AnyCover` | Bind Survival Journal (Adhesive + Fabric) |
| `Recipe_Bind_Adhesive_AnyCover` | Bind Survival Journal (Adhesive + Fabric) |

### Restore Journal Recipes (Thread-based)
| Key | English Value |
|-----|---------------|
| `RestoreJournal_Thread_Leather` | Restore Journal (Thread + Leather) |
| `Recipe_RestoreJournal_Thread_Leather` | Restore Journal (Thread + Leather) |
| `RestoreJournal_Thread_AnyCover` | Restore Journal (Thread + Fabric) |
| `Recipe_RestoreJournal_Thread_AnyCover` | Restore Journal (Thread + Fabric) |

### Restore Journal Recipes (Adhesive-based)
| Key | English Value |
|-----|---------------|
| `RestoreJournal_Adhesive_Leather` | Restore Journal (Adhesive + Leather) |
| `Recipe_RestoreJournal_Adhesive_Leather` | Restore Journal (Adhesive + Leather) |
| `RestoreJournal_Adhesive_AnyCover` | Restore Journal (Adhesive + Fabric) |
| `Recipe_RestoreJournal_Adhesive_AnyCover` | Restore Journal (Adhesive + Fabric) |

---

## Notes for Translators

### Placeholders
Some strings contain placeholders that will be replaced at runtime:
- `%1`, `%2`, etc. - Positional placeholders (keep these in your translation)
- `%d` - Number placeholder
- `%s` - String placeholder
- `\n` - Newline character

### Consistency Tips
- Keep terminology consistent (e.g., "journal" vs "diary")
- Match the tone of the original (casual vs formal)
- Test long translations to ensure they fit in the UI

### Existing Translations
Currently available translations:
- English (EN) - Complete
- Chinese Simplified (CN) - Complete
- Portuguese Brazilian (PTBR) - Complete
- French (FR) - Complete
- Korean (KO) - Complete
- Turkish (TR) - Complete
- Russian (RU) - Complete

---

## Known Issues / Future Work

All user-facing strings are now properly localized.

### Recent Fixes (v2.x)
- **Recipe Knowledge Labels**: Added translation keys for recipe knowledge source text
- **Capacity Warnings**: Added translation keys for journal capacity warning messages
- **Unknown Trait Fallback**: Added fallback text translation key
- **Hardcoded String Audit**: Comprehensive audit of all Lua source files to ensure all user-facing text uses `getText()` with proper fallbacks
- **Tooltip System**: Fixed `common/` directory tooltips to use proper `getText()` calls matching `42/` version

### Previous Fixes (v1.x)
- **Item Names**: Fixed translation file format from `Items_XX.txt` (incorrect) to `ItemName_XX.txt` with module-prefixed keys like `ItemName_BurdJournals.BlankSurvivalJournal`
- **Profession Names**: Journal names now properly translate profession information (e.g., "Former Mechanic" -> "Ancien Mécanicien" in French)
- **Hardcoded "(was X)" text**: Fixed to use translation key `UI_BurdJournals_RecordedWas`
- **Comment syntax**: Fixed invalid `/* */` C-style comments to proper Lua `--` comments in translation files

If you notice untranslated text in-game, please report it so we can add the appropriate translation keys.

---

## Contributing

To submit a translation:
1. Fork the repository
2. Create your translation files
3. Test in-game to verify everything displays correctly
4. Submit a pull request

Thank you for helping make this mod accessible to more players!
