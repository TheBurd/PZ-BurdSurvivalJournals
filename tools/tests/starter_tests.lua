local T = BSJ_TEST
if not T then
    error("BSJ_TEST harness not available")
end

local variants = {
    {
        label = "42",
        shared_path = T.join_path(T.mod_root, "42/media/lua/shared/BurdJournals_Shared.lua"),
        server_path = T.join_path(T.mod_root, "42/media/lua/server/BurdJournals_Server.lua"),
        client_path = T.join_path(T.mod_root, "42/media/lua/client/BurdJournals_Client.lua")
    },
    {
        label = "common",
        shared_path = T.join_path(T.mod_root, "common/media/lua/shared/BurdJournals_Shared.lua"),
        server_path = T.join_path(T.mod_root, "common/media/lua/server/BurdJournals_Server.lua"),
        client_path = T.join_path(T.mod_root, "common/media/lua/client/BurdJournals_Client.lua")
    }
}

local function as_percent(multiplier)
    return math.floor((tonumber(multiplier) or 0) * 100 + 0.5)
end

local function list_contains(list, value)
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function array_list(values)
    local items = {}
    if type(values) ~= "table" then
        return items
    end
    for i = 1, #values do
        items[i] = values[i]
    end
    return items
end

local function java_list(values)
    local items = array_list(values)
    return setmetatable(items, {
        __index = {
            size = function(self)
                return #self
            end,
            get = function(self, index)
                return self[index + 1]
            end,
            contains = function(self, wanted)
                for i = 1, #self do
                    if self[i] == wanted then
                        return true
                    end
                end
                return false
            end,
            add = function(self, value)
                self[#self + 1] = value
            end
        }
    })
end

local function find_source_entry(entries, source_id)
    if type(entries) ~= "table" then return nil end
    local target = string.lower(tostring(source_id or ""))
    for _, entry in ipairs(entries) do
        local id = entry and entry.sourceId and string.lower(tostring(entry.sourceId)) or nil
        if id == target then
            return entry
        end
    end
    return nil
end

for _, variant in ipairs(variants) do
    local prefix = "[" .. variant.label .. "] "

    T.test(prefix .. "loads shared module", function()
        local bj = T.require_shared_module(variant.shared_path)
        T.assert_type(bj, "table", "BurdJournals export should be table")
    end)

    T.test(prefix .. "normalizeTraitId strips known prefixes", function()
        local bj = T.require_shared_module(variant.shared_path)
        T.assert_equal(bj.normalizeTraitId("base:Strong"), "Strong")
        T.assert_equal(bj.normalizeTraitId("Base.Strong"), "Strong")
        T.assert_equal(bj.normalizeTraitId("Athletic"), "Athletic")
    end)

    T.test(prefix .. "resolveSkillKey is case-insensitive", function()
        local bj = T.require_shared_module(variant.shared_path)
        local skills = {Aiming = {xp = 5, level = 1}}
        T.assert_equal(bj.resolveSkillKey(skills, "aiming"), "Aiming")
        T.assert_equal(bj.resolveSkillKey(skills, "Aiming"), "Aiming")
        T.assert_equal(bj.resolveSkillKey(skills, "Fishing"), "Fishing")
    end)

    T.test(prefix .. "getSkillModSource keeps vanilla aliases as Vanilla", function()
        local bj = T.require_shared_module(variant.shared_path)
        T.assert_equal(bj.getSkillModSource("Carpentry"), "Vanilla")
        T.assert_equal(bj.getSkillModSource("FirstAid"), "Vanilla")
        T.assert_equal(bj.getSkillModSource("ShortBlade"), "Vanilla")
        T.assert_equal(bj.getSkillModSource("Lightfooted"), "Vanilla")
        T.assert_equal(bj.getSkillModSource("SOTO_Blacksmith"), "Soul's Trait Overhaul")
    end)

    T.test(prefix .. "getModSourceFromFullType maps module prefixes to display names", function()
        local bj = T.require_shared_module(variant.shared_path)
        T.assert_equal(bj.getModSourceFromFullType("Base.Book"), "Vanilla")
        T.assert_equal(bj.getModSourceFromFullType("Lifestyle.BookMusic"), "Lifestyle: Hobbies")
        T.assert_equal(bj.getModSourceFromFullType("AdaptiveTraits:SomeTrait"), "Adaptive Traits")
    end)

    T.test(prefix .. "normalizeFilterSourceId maps known names to ModID keys", function()
        local bj = T.require_shared_module(variant.shared_path)
        T.assert_equal(bj.normalizeFilterSourceId("Vanilla"), "vanilla")
        T.assert_equal(bj.normalizeFilterSourceId("Lifestyle: Hobbies"), "lifestyle")
        T.assert_equal(bj.normalizeFilterSourceId("Soul's Trait Overhaul"), "soto")
    end)

    T.test(prefix .. "collectModSources returns ModID-based source entries", function()
        local bj = T.require_shared_module(variant.shared_path)
        local journalData = {
            skills = {
                Carpentry = {xp = 75, level = 1},
                ["SOTO_Blacksmith"] = {xp = 120, level = 2},
                ["Lifestyle:Art"] = {xp = 80, level = 1},
            }
        }

        local sources = bj.collectModSources("skills", journalData, nil, "view")
        local allEntry = find_source_entry(sources, "all")
        local vanillaEntry = find_source_entry(sources, "vanilla")
        local sotoEntry = find_source_entry(sources, "soto")
        local lifestyleEntry = find_source_entry(sources, "lifestyle")

        T.assert_type(allEntry, "table")
        T.assert_type(vanillaEntry, "table")
        T.assert_type(sotoEntry, "table")
        T.assert_type(lifestyleEntry, "table")
        T.assert_equal(allEntry.count, 3)
        T.assert_equal(vanillaEntry.count, 1)
        T.assert_equal(sotoEntry.count, 1)
        T.assert_equal(lifestyleEntry.count, 1)
        T.assert_equal(sotoEntry.source, "SOTO")
        T.assert_equal(lifestyleEntry.source, "Lifestyle")
    end)

    T.test(prefix .. "getSkillModSource infers source from non-vanilla parent category", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.Perks = {
            Art = {}
        }
        env.PerkFactory = {
            getPerk = function(perk)
                if perk == env.Perks.Art then
                    return {
                        getParent = function()
                            return { getId = function() return "Lifestyle" end }
                        end
                    }
                end
                return nil
            end
        }

        T.assert_equal(bj.getSkillModSource("Art"), "Lifestyle: Hobbies")
    end)

    T.test(prefix .. "getRecipeModSource falls back to recipe module source", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.getAllRecipes = function()
            return {
                size = function() return 1 end,
                get = function(_, i)
                    if i ~= 0 then return nil end
                    return {
                        getName = function() return "PlayInstrument" end,
                        getModule = function() return "Lifestyle" end
                    }
                end
            }
        end

        T.assert_equal(bj.getRecipeModSource("PlayInstrument", nil), "Lifestyle: Hobbies")
    end)

    T.test(prefix .. "diagnoseModSource explains unknown skill classification", function()
        local bj = T.require_shared_module(variant.shared_path)
        local diag = bj.diagnoseModSource("skills", "MysterySkillNoPrefix", nil)
        T.assert_equal(diag.source, "Modded")
        T.assert_equal(diag.reason, "no_source_pattern_match")
    end)

    T.test(prefix .. "diagnoseModSource explains recipe module source", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.getAllRecipes = function()
            return {
                size = function() return 1 end,
                get = function(_, i)
                    if i ~= 0 then return nil end
                    return {
                        getName = function() return "PlayInstrument" end,
                        getModule = function() return "Lifestyle" end
                    }
                end
            }
        end
        local diag = bj.diagnoseModSource("recipes", "PlayInstrument", nil)
        T.assert_equal(diag.source, "Lifestyle: Hobbies")
        T.assert_equal(diag.reason, "recipe_module_name")
    end)

    T.test(prefix .. "playerKnowsRecipe ignores read-state heuristics without authoritative knowledge", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        bj.isRecipeRecordingEnabled = function() return true end
        env.getScriptManager = function()
            return {
                getAllItems = function()
                    return java_list({
                        {
                            getLearnedRecipes = function()
                                return java_list({"MakeBreadDough"})
                            end,
                            getFullName = function()
                                return "Base.BreadMagazine"
                            end
                        }
                    })
                end,
                getRecipe = function(_, name)
                    if name == "MakeBreadDough" then
                        return {
                            needToBeLearn = function() return true end,
                            getName = function() return "MakeBreadDough" end
                        }
                    end
                    return nil
                end
            }
        end

        local readBooks = java_list({"Base.BreadMagazine"})
        local player = {
            getKnownRecipes = function()
                return array_list({})
            end,
            getAlreadyReadBook = function()
                return readBooks
            end,
            getAlreadyReadPages = function(_, magazineType)
                if magazineType == "Base.BreadMagazine" then
                    return 10
                end
                return 0
            end,
            isRecipeKnown = function()
                return false
            end
        }

        T.assert_true(bj.playerKnowsRecipe(player, "MakeBreadDough") == false, "Read-state heuristics should not mark recipe as known")
        local collected = bj.collectPlayerMagazineRecipes(player, false, false)
        T.assert_true(collected.MakeBreadDough == nil, "Read-state heuristics should not make recipe recordable")
    end)

    T.test(prefix .. "collectPlayerMagazineRecipes records mapped and learn-required recipes but excludes baseline entries", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        bj.isRecipeRecordingEnabled = function() return true end
        env.getScriptManager = function()
            return {
                getAllItems = function()
                    return java_list({
                        {
                            getLearnedRecipes = function()
                                return java_list({"VanillaRecipe", "StartingRecipe"})
                            end,
                            getFullName = function()
                                return "Base.RecipeMagazine"
                            end
                        }
                    })
                end,
                getRecipe = function(_, name)
                    if name == "VanillaRecipe" or name == "StartingRecipe" or name == "ModdedRecipe" then
                        return {
                            needToBeLearn = function() return true end,
                            getName = function() return name end
                        }
                    end
                    return nil
                end
            }
        end

        local player = {
            getKnownRecipes = function()
                return array_list({"VanillaRecipe", "ModdedRecipe", "StartingRecipe"})
            end,
            getModData = function()
                return {
                    BurdJournals = {
                        recipeBaseline = {
                            StartingRecipe = true
                        }
                    }
                }
            end
        }

        local collected = bj.collectPlayerMagazineRecipes(player, true, false)
        T.assert_true(collected.VanillaRecipe == true, "Mapped recipe should be recordable")
        T.assert_true(collected.ModdedRecipe == true, "Unmapped learn-required recipe should be recordable")
        T.assert_true(collected.StartingRecipe == nil, "Baseline recipe should be excluded")
    end)

    T.test(prefix .. "learnRecipeWithVerification succeeds only after authoritative recipe knowledge is present", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        local knownRecipes = array_list({})
        env.getScriptManager = function()
            return {
                getAllItems = function()
                    return java_list({})
                end,
                getRecipe = function(_, name)
                    if name == "ModdedRecipe" then
                        return {
                            needToBeLearn = function() return true end,
                            getName = function() return "ModdedRecipe" end
                        }
                    end
                    return nil
                end
            }
        end

        local player = {
            getKnownRecipes = function()
                return knownRecipes
            end,
            learnRecipe = function(_, recipeName)
                knownRecipes[#knownRecipes + 1] = recipeName
            end
        }

        T.assert_true(bj.learnRecipeWithVerification(player, "ModdedRecipe", "[TEST]") == true)
        T.assert_true(bj.playerKnowsRecipe(player, "ModdedRecipe") == true)
    end)

    T.test(prefix .. "learnRecipeWithVerification rejects fallback read state when recipe never becomes known", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        local readBooks = java_list({})
        local pageReads = {}
        env.getScriptManager = function()
            return {
                getAllItems = function()
                    return java_list({
                        {
                            getLearnedRecipes = function()
                                return java_list({"MagazineRecipe"})
                            end,
                            getFullName = function()
                                return "Base.MagazineRecipeBook"
                            end,
                            getPageToLearn = function()
                                return 5
                            end
                        }
                    })
                end,
                getItem = function(_, fullType)
                    if fullType == "Base.MagazineRecipeBook" then
                        return {
                            getPageToLearn = function()
                                return 5
                            end
                        }
                    end
                    return nil
                end,
                getRecipe = function(_, name)
                    if name == "MagazineRecipe" then
                        return {
                            needToBeLearn = function() return true end,
                            getName = function() return "MagazineRecipe" end
                        }
                    end
                    return nil
                end
            }
        end

        local player = {
            getKnownRecipes = function()
                return array_list({})
            end,
            learnRecipe = function()
            end,
            setAlreadyReadPages = function(_, magazineType, pageCount)
                pageReads[magazineType] = pageCount
            end,
            getAlreadyReadPages = function(_, magazineType)
                return pageReads[magazineType] or 0
            end,
            getAlreadyReadBook = function()
                return readBooks
            end
        }

        T.assert_true(bj.learnRecipeWithVerification(player, "MagazineRecipe", "[TEST]") == false)
        T.assert_true(pageReads["Base.MagazineRecipeBook"] == 5, "Fallback should still seed read pages")
        T.assert_true(readBooks:contains("Base.MagazineRecipeBook") == true, "Fallback should still add read book entry")
        T.assert_true(bj.playerKnowsRecipe(player, "MagazineRecipe") == false, "Recipe must remain unknown without authoritative confirmation")
    end)

    T.test(prefix .. "cursed journals ignore stale unleashed state without reward flag", function()
        local bj = T.require_shared_module(variant.shared_path)
        local journalData = {
            isCursedJournal = true,
            isCursedReward = false,
            cursedState = "unleashed"
        }
        local item = {
            getFullType = function()
                return bj.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"
            end,
            getModData = function()
                return { BurdJournals = journalData }
            end
        }

        T.assert_true(bj.isCursedJournalItem(item) == true, "Cursed fullType should remain cursed without explicit reward flag")
        T.assert_equal(bj.getJournalStateString(item), "Cursed")
        T.assert_equal(bj.computeLocalizedName(item), "Cursed Survival Journal")
    end)

    T.test(prefix .. "server validateRecipePayload accepts authoritative known learn-required recipe without magazine mapping", function()
        local bj, env = T.require_server_module(variant.shared_path, variant.server_path)
        env.getScriptManager = function()
            return {
                getAllItems = function()
                    return java_list({})
                end,
                getRecipe = function(_, name)
                    if name == "ModdedRecipe" then
                        return {
                            needToBeLearn = function() return true end,
                            getName = function() return "ModdedRecipe" end
                        }
                    end
                    return nil
                end
            }
        end

        local player = {
            getKnownRecipes = function()
                return array_list({"ModdedRecipe"})
            end
        }

        local result = bj.Server.validateRecipePayload({ModdedRecipe = {name = "ModdedRecipe"}}, player, false)
        T.assert_type(result, "table")
        T.assert_true(result.ModdedRecipe == true, "Authoritative known recipe should pass validation")
    end)

    T.test(prefix .. "server claimRecipe does not mark claim when learn verification fails", function()
        local bj = T.require_server_module(variant.shared_path, variant.server_path)
        local journalData = {
            recipes = {
                MissingRecipe = true
            }
        }
        local modData = { BurdJournals = journalData }
        local journal = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return "BurdJournals.FilledSurvivalJournal"
            end,
            transmitModData = function()
            end
        }
        local sent = {}
        local player = {}

        bj.findItemById = function()
            return journal
        end
        bj.canPlayerClaimFromJournal = function()
            return true
        end
        bj.hasCharacterClaimedRecipe = function()
            return false
        end
        bj.isRecipeEnabledForJournal = function()
            return true
        end
        bj.playerKnowsRecipe = function()
            return false
        end
        bj.learnRecipeWithVerification = function()
            return false
        end
        bj.getPlayerCharacterId = function()
            return "char_1"
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end

        bj.Server.handleClaimRecipe(player, {journalId = 123, recipeName = "MissingRecipe"})

        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "error")
        T.assert_true(not journalData.claims, "Failed learn verification must not mark recipe claimed")
    end)

    T.test(prefix .. "server absorbRecipe does not mark claim when learn verification fails", function()
        local bj = T.require_server_module(variant.shared_path, variant.server_path)
        local journalData = {
            recipes = {
                MissingRecipe = true
            }
        }
        local modData = { BurdJournals = journalData }
        local journal = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return "BurdJournals.WornSurvivalJournal"
            end,
            transmitModData = function()
            end
        }
        local sent = {}
        local player = {}

        bj.findItemById = function()
            return journal
        end
        bj.canAbsorbXP = function()
            return true
        end
        bj.hasCharacterClaimedRecipe = function()
            return false
        end
        bj.isRecipeEnabledForJournal = function()
            return true
        end
        bj.playerKnowsRecipe = function()
            return false
        end
        bj.learnRecipeWithVerification = function()
            return false
        end
        bj.getPlayerCharacterId = function()
            return "char_1"
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end

        bj.Server.handleAbsorbRecipe(player, {journalId = 123, recipeName = "MissingRecipe"})

        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "error")
        T.assert_true(not journalData.claims, "Failed learn verification must not mark absorb recipe claimed")
    end)

    T.test(prefix .. "server recipeAlreadyKnown response includes runtime delta in strict MP", function()
        local bj = T.require_server_module(variant.shared_path, variant.server_path)
        local journalData = {
            recipes = {
                KnownRecipe = true
            }
        }
        local modData = { BurdJournals = journalData }
        local journal = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return "BurdJournals.FilledSurvivalJournal"
            end,
            transmitModData = function()
            end
        }
        local sent = {}
        local player = {}

        bj.findItemById = function()
            return journal
        end
        bj.canPlayerClaimFromJournal = function()
            return true
        end
        bj.hasCharacterClaimedRecipe = function()
            return false
        end
        bj.isRecipeEnabledForJournal = function()
            return true
        end
        bj.playerKnowsRecipe = function()
            return true
        end
        bj.getPlayerCharacterId = function()
            return "char_1"
        end
        bj.isStrictMPServerContext = function()
            return true
        end
        bj.buildRuntimeDeltaForPlayer = function()
            return {
                claims = {
                    char_1 = {
                        recipes = {
                            KnownRecipe = true
                        }
                    }
                }
            }
        end
        bj.isValidItem = function()
            return false
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end

        bj.Server.handleClaimRecipe(player, {journalId = 123, recipeName = "KnownRecipe"})

        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "recipeAlreadyKnown")
        T.assert_type(sent[1].args.runtimeDelta, "table")
        T.assert_true(sent[1].args.journalData == nil, "Strict MP response should avoid full journal payload")
    end)

    T.test(prefix .. "server limited-claim recipeAlreadyKnown does not spend claim", function()
        local bj = T.require_server_module(variant.shared_path, variant.server_path)
        local journalData = {
            isWorn = true,
            recipes = {
                KnownRecipe = true
            }
        }
        local modData = { BurdJournals = journalData }
        local transmitCount = 0
        local journal = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return "BurdJournals.WornSurvivalJournal"
            end,
            transmitModData = function()
                transmitCount = transmitCount + 1
            end
        }
        local sent = {}
        local player = {}

        bj.getSandboxOption = function(opt)
            if opt == "EnableLimitedClaimLootJournals" then
                return true
            end
            if opt == "LootJournalMaxClaimsBeforeDissolve" then
                return 1
            end
            return false
        end
        bj.getPlayerCharacterId = function()
            return "char_1"
        end
        bj.findItemById = function()
            return journal
        end
        bj.canPlayerClaimFromJournal = function()
            return true
        end
        bj.hasCharacterClaimedRecipe = function()
            return false
        end
        bj.isRecipeEnabledForJournal = function()
            return true
        end
        bj.playerKnowsRecipe = function()
            return true
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end

        bj.Server.handleClaimRecipe(player, {journalId = 123, recipeName = "KnownRecipe"})

        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "recipeAlreadyKnown")
        T.assert_true(not journalData.claims, "Already-known limited claim should not mark journal data")
        T.assert_equal(transmitCount, 0, "Already-known limited claim should not transmit claim mutations")
    end)

    T.test(prefix .. "server limited-claim cap blocks further mixed reward claims", function()
        local bj = T.require_server_module(variant.shared_path, variant.server_path)
        local journalData = {
            isBloody = true,
            skills = {
                Aiming = {xp = 25, level = 1}
            },
            recipes = {
                SoupRecipe = true
            }
        }
        local modData = { BurdJournals = journalData }
        local journal = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return "BurdJournals.BloodySurvivalJournal"
            end,
            transmitModData = function()
            end
        }
        local sent = {}
        local player = {}

        bj.getSandboxOption = function(opt)
            if opt == "EnableLimitedClaimLootJournals" then
                return true
            end
            if opt == "LootJournalMaxClaimsBeforeDissolve" then
                return 1
            end
            return false
        end
        bj.getPlayerCharacterId = function()
            return "char_1"
        end
        bj.findItemById = function()
            return journal
        end
        bj.canPlayerClaimFromJournal = function()
            return true
        end
        bj.hasCharacterClaimedRecipe = function()
            return false
        end
        bj.isRecipeEnabledForJournal = function()
            return true
        end
        bj.playerKnowsRecipe = function()
            return false
        end
        bj.learnRecipeWithVerification = function()
            error("claim guard should block before learning")
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end

        bj.markSkillClaimedByCharacter(journalData, player, "Aiming")
        bj.Server.handleClaimRecipe(player, {journalId = 123, recipeName = "SoupRecipe"})

        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "error")
        T.assert_true(not (journalData.claims and journalData.claims.char_1 and journalData.claims.char_1.recipes and journalData.claims.char_1.recipes.SoupRecipe), "Cap guard must not mark new claims")
    end)

    T.test(prefix .. "server openCursedJournal repairs stale unleashed state before prompt", function()
        local bj = T.require_server_module(variant.shared_path, variant.server_path)
        local journalData = {
            isCursedJournal = true,
            isCursedReward = false,
            cursedState = "unleashed",
            isBloody = true,
            wasFromBloody = true,
            hasBloodyOrigin = true
        }
        local modData = { BurdJournals = journalData }
        local transmitCount = 0
        local journal = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return bj.CURSED_ITEM_TYPE or "BurdJournals.CursedJournal"
            end,
            getID = function()
                return 321
            end,
            transmitModData = function()
                transmitCount = transmitCount + 1
            end
        }
        local sent = {}
        local player = {}

        bj.findItemById = function()
            return journal
        end
        bj.updateJournalName = function()
        end
        bj.updateJournalIcon = function()
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end

        bj.Server.handleOpenCursedJournal(player, {journalId = 321, confirm = false})

        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "cursedOpenPrompt")
        T.assert_equal(journalData.cursedState, "dormant")
        T.assert_true(journalData.isCursedJournal == true, "Dormant cursed item should remain cursed")
        T.assert_true(journalData.isCursedReward ~= true, "Dormant cursed item must not become reward state")
        T.assert_true(journalData.isBloody ~= true, "Dormant cursed item must clear stale bloody flag")
        T.assert_true(journalData.wasFromBloody ~= true, "Dormant cursed item must clear stale bloody origin")
        T.assert_true(journalData.hasBloodyOrigin ~= true, "Dormant cursed item must clear stale bloody ancestry")
        T.assert_equal(transmitCount, 1)
    end)

    T.test(prefix .. "server registerBaseline replaces same-character cache when fresh build changed", function()
        local bj, env = T.require_server_module(variant.shared_path, variant.server_path)
        local sent = {}
        local cache = {
            players = {
                ["steam_burd"] = {
                    skillBaseline = {Aiming = 75},
                    mediaSkillBaseline = {},
                    traitBaseline = {Brave = true},
                    recipeBaseline = {OldRecipe = true},
                    steamId = "steam",
                    characterName = "Burd Example",
                    debugModified = false
                }
            }
        }
        local modData = {}
        local player = {
            getHoursSurvived = function() return 0 end,
            getDescriptor = function()
                return {
                    getForename = function() return "Burd" end,
                    getSurname = function() return "Example" end
                }
            end,
            getModData = function() return modData end,
            transmitModData = function() end
        }

        bj.Server.getBaselineCache = function()
            return cache
        end
        bj.Server.isBaselineModDataReady = function()
            return true
        end
        bj.Server.transmitBaselineStores = function()
        end
        bj.Server.storeBaselineArchiveRecord = function()
        end
        bj.Server.buildBaselineForPlayer = function()
            return {
                skillBaseline = {Aiming = 150},
                mediaSkillBaseline = {},
                traitBaseline = {Athletic = true},
                recipeBaseline = {NewRecipe = true}
            }
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end
        bj.getPlayerCharacterId = function() return "steam_burd" end
        bj.getPlayerSteamId = function() return "steam" end
        bj.getPlayerCharacterName = function() return "Burd Example" end
        bj.getBaselineSnapshotMaxHours = function() return 1 end
        bj.Server.captureBaselineSnapshotForPlayer = function()
        end
        env.getGameTime = function()
            return {
                getWorldAgeHours = function()
                    return 123
                end
            }
        end
        env.isStrictMPServer = function() return false end

        bj.Server.handleRegisterBaseline(player, {characterId = "steam_burd"})

        T.assert_equal(cache.players["steam_burd"].skillBaseline.Aiming, 150)
        T.assert_true(cache.players["steam_burd"].traitBaseline.Athletic == true, "Changed trait baseline should replace cached entry")
        T.assert_true(cache.players["steam_burd"].recipeBaseline.NewRecipe == true, "Changed recipe baseline should replace cached entry")
        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "baselineRegistered")
        T.assert_true(sent[1].args.success == true, "Changed fresh-character baseline should be stored")
        T.assert_true(sent[1].args.replacedExisting == true, "Response should flag same-character replacement")
    end)

    T.test(prefix .. "server registerBaseline keeps debug-modified cache when same-character build changed", function()
        local bj, env = T.require_server_module(variant.shared_path, variant.server_path)
        local sent = {}
        local cache = {
            players = {
                ["steam_burd"] = {
                    skillBaseline = {Aiming = 75},
                    mediaSkillBaseline = {},
                    traitBaseline = {Brave = true},
                    recipeBaseline = {OldRecipe = true},
                    steamId = "steam",
                    characterName = "Burd Example",
                    debugModified = true
                }
            }
        }
        local modData = {}
        local player = {
            getHoursSurvived = function() return 0 end,
            getDescriptor = function()
                return {
                    getForename = function() return "Burd" end,
                    getSurname = function() return "Example" end
                }
            end,
            getModData = function() return modData end,
            transmitModData = function() end
        }

        bj.Server.getBaselineCache = function()
            return cache
        end
        bj.Server.isBaselineModDataReady = function()
            return true
        end
        bj.Server.transmitBaselineStores = function()
        end
        bj.Server.storeBaselineArchiveRecord = function()
        end
        bj.Server.buildBaselineForPlayer = function()
            return {
                skillBaseline = {Aiming = 150},
                mediaSkillBaseline = {},
                traitBaseline = {Athletic = true},
                recipeBaseline = {NewRecipe = true}
            }
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end
        bj.getPlayerCharacterId = function() return "steam_burd" end
        bj.getPlayerSteamId = function() return "steam" end
        bj.getPlayerCharacterName = function() return "Burd Example" end
        bj.getBaselineSnapshotMaxHours = function() return 1 end
        bj.Server.captureBaselineSnapshotForPlayer = function()
        end
        env.getGameTime = function()
            return {
                getWorldAgeHours = function()
                    return 123
                end
            }
        end
        env.isStrictMPServer = function() return false end

        bj.Server.handleRegisterBaseline(player, {characterId = "steam_burd"})

        T.assert_equal(cache.players["steam_burd"].skillBaseline.Aiming, 75)
        T.assert_true(cache.players["steam_burd"].traitBaseline.Brave == true, "Debug-modified cache should remain authoritative")
        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "baselineRegistered")
        T.assert_true(sent[1].args.success ~= true, "Debug-protected baseline should not be overwritten automatically")
        T.assert_true(sent[1].args.protectedExisting == true, "Response should expose protected-cache refusal")
    end)

    T.test(prefix .. "server requestBaseline restores missing cache from active snapshot", function()
        local bj, env = T.require_server_module(variant.shared_path, variant.server_path)
        local sent = {}
        local cache = { players = {} }
        local backupsWritten = 0
        local transmitted = 0
        local player = {
            getHoursSurvived = function() return 8 end,
            getDescriptor = function()
                return {
                    getForename = function() return "Burd" end,
                    getSurname = function() return "Example" end
                }
            end,
            getModData = function() return {} end,
            transmitModData = function()
                transmitted = transmitted + 1
            end
        }
        local snapshotStore = {
            bySnapshotId = {
                snap_live = {
                    snapshotId = "snap_live",
                    steamId = "steam",
                    characterId = "steam_burd",
                    characterName = "Burd Example",
                    capturedAtHours = 88,
                    skillBaseline = {Aiming = 320},
                    mediaSkillBaseline = {},
                    traitBaseline = {Athletic = true},
                    recipeBaseline = {Soup = true},
                }
            },
            bySteamId = { steam = {"snap_live"} },
            byCharacterId = { steam_burd = {"snap_live"} },
            activeBySteamId = { steam = "snap_live" },
            activeByCharacterId = { steam_burd = "snap_live" }
        }

        bj.Server.getBaselineCache = function()
            return cache
        end
        bj.Server.getCachedBaseline = function()
            return nil
        end
        bj.Server.getBaselineSnapshotStore = function()
            return snapshotStore
        end
        bj.Server.isBaselineModDataReady = function()
            return true
        end
        bj.Server.mergeBaselineSnapshotsFromPlayerHistory = function()
        end
        bj.Server.transmitBaselineStores = function()
        end
        bj.Server.storeBaselineArchiveRecord = function()
        end
        bj.Server.writePlayerBaselineBackup = function()
            backupsWritten = backupsWritten + 1
            return true
        end
        bj.Server.captureBaselineSnapshotForPlayer = function()
            error("Active snapshot recovery should not capture a duplicate snapshot")
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end
        bj.getPlayerCharacterId = function() return "steam_burd" end
        bj.getPlayerSteamId = function() return "steam" end
        bj.getPlayerCharacterName = function() return "Burd Example" end
        bj.getBaselineSnapshotMaxHours = function() return 1 end
        env.getGameTime = function()
            return {
                getWorldAgeHours = function()
                    return 123
                end
            }
        end
        env.isStrictMPServer = function() return false end

        bj.Server.handleRequestBaseline(player, {})

        T.assert_equal(cache.players["steam_burd"].skillBaseline.Aiming, 320)
        T.assert_true(cache.players["steam_burd"].traitBaseline.Athletic == true, "Snapshot baseline should repopulate cache")
        T.assert_equal(backupsWritten, 1)
        T.assert_equal(transmitted, 1)
        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "baselineResponse")
        T.assert_true(sent[1].args.found == true, "Snapshot recovery should respond with a baseline")
        T.assert_true(sent[1].args.recovered == true, "Snapshot recovery should be flagged as recovered")
        T.assert_equal(sent[1].args.recoverySource, "activeSnapshot")
        T.assert_equal(sent[1].args.recoveredSnapshotId, "snap_live")
    end)

    T.test(prefix .. "server requestBaseline rebuilds established baseline from live player state when recovery sources are empty", function()
        local bj, env = T.require_server_module(variant.shared_path, variant.server_path)
        local sent = {}
        local cache = { players = {} }
        local backupsWritten = 0
        local transmitted = 0
        local capturedSnapshot = nil
        local player = {
            getHoursSurvived = function() return 8 end,
            getDescriptor = function()
                return {
                    getForename = function() return "Burd" end,
                    getSurname = function() return "Example" end
                }
            end,
            getModData = function() return {} end,
            transmitModData = function()
                transmitted = transmitted + 1
            end
        }
        local snapshotStore = {
            bySnapshotId = {},
            bySteamId = {},
            byCharacterId = {},
            activeBySteamId = {},
            activeByCharacterId = {}
        }

        bj.Server.getBaselineCache = function()
            return cache
        end
        bj.Server.getCachedBaseline = function()
            return nil
        end
        bj.Server.getBaselineSnapshotStore = function()
            return snapshotStore
        end
        bj.Server.isBaselineModDataReady = function()
            return true
        end
        bj.Server.mergeBaselineSnapshotsFromPlayerHistory = function()
        end
        bj.Server.transmitBaselineStores = function()
        end
        bj.Server.storeBaselineArchiveRecord = function()
        end
        bj.Server.writePlayerBaselineBackup = function()
            backupsWritten = backupsWritten + 1
            return true
        end
        bj.Server.buildBaselineForPlayer = function()
            return {
                skillBaseline = {Aiming = 450},
                mediaSkillBaseline = {Woodcraft = 75},
                traitBaseline = {Athletic = true},
                recipeBaseline = {}
            }
        end
        bj.Server.captureBaselineSnapshotForPlayer = function(_, characterId, baseline, source, note)
            capturedSnapshot = {
                characterId = characterId,
                baseline = baseline,
                source = source,
                note = note
            }
            return true, "snap_rebuilt"
        end
        bj.Server.sendToClient = function(_, command, args)
            sent[#sent + 1] = {command = command, args = args}
        end
        bj.getPlayerCharacterId = function() return "steam_burd" end
        bj.getPlayerSteamId = function() return "steam" end
        bj.getPlayerCharacterName = function() return "Burd Example" end
        bj.getBaselineSnapshotMaxHours = function() return 1 end
        env.getGameTime = function()
            return {
                getWorldAgeHours = function()
                    return 321
                end
            }
        end
        env.isStrictMPServer = function() return false end

        bj.Server.handleRequestBaseline(player, {})

        T.assert_equal(cache.players["steam_burd"].skillBaseline.Aiming, 450)
        T.assert_true(cache.players["steam_burd"].traitBaseline.Athletic == true, "Live rebuild should seed the cache")
        T.assert_equal(backupsWritten, 1)
        T.assert_equal(transmitted, 1)
        T.assert_type(capturedSnapshot, "table", "Live rebuild should capture a fresh snapshot")
        T.assert_equal(capturedSnapshot.characterId, "steam_burd")
        T.assert_equal(capturedSnapshot.source, "request_recovery")
        T.assert_equal(capturedSnapshot.note, "live_player_state")
        T.assert_equal(#sent, 1)
        T.assert_equal(sent[1].command, "baselineResponse")
        T.assert_true(sent[1].args.found == true, "Live rebuild should respond with a baseline")
        T.assert_true(sent[1].args.recovered == true, "Live rebuild should be flagged as recovered")
        T.assert_equal(sent[1].args.recoverySource, "livePlayerState")
    end)

    T.test(prefix .. "client onCreatePlayer probes same-character baseline drift before preserving local baseline", function()
        local bj, env = T.require_client_module(variant.shared_path, variant.client_path)
        local requested = 0
        local queued = 0
        local player = {}
        local modData = {
            BurdJournals = {
                baselineCaptured = true,
                baselineVersion = 4,
                characterId = "steam_burd",
                steamId = "steam",
                skillBaseline = {Aiming = 75},
                mediaSkillBaseline = {},
                traitBaseline = {Brave = true},
                recipeBaseline = {OldRecipe = true}
            }
        }
        local knownTraits = java_list({"Athletic"})
        local knownRecipes = java_list({"NewRecipe"})
        local xpObj = {
            getXP = function(_, perk)
                if perk == "AimingPerk" then
                    return 150
                end
                return 0
            end
        }

        player.getModData = function() return modData end
        player.getHoursSurvived = function() return 0 end
        player.getCharacterTraits = function()
            return {
                getKnownTraits = function()
                    return knownTraits
                end
            }
        end
        player.getTraits = function()
            return knownTraits
        end
        player.getKnownRecipes = function()
            return knownRecipes
        end
        player.getXp = function()
            return xpObj
        end
        player.getPlayerNum = function()
            return 0
        end

        env.getSpecificPlayer = function(index)
            if index == 0 then
                return player
            end
            return nil
        end

        bj.isWithinBaselineSnapshotWindow = function() return true end
        bj.getBaselineSnapshotMaxHours = function() return 1 end
        bj.getPlayerCharacterId = function() return "steam_burd" end
        bj.getPlayerSteamId = function() return "steam" end
        bj.getAllowedSkills = function() return {"Aiming"} end
        bj.getPerkByName = function(_, skillName)
            if skillName == "Aiming" then
                return "AimingPerk"
            end
            return nil
        end
        bj.collectPlayerTraits = function()
            return {Athletic = true}
        end
        bj.collectPlayerMagazineRecipes = function()
            return {NewRecipe = true}
        end
        bj.getPlayerVhsSkillXPMapCopy = function()
            return {}
        end
        bj.Client.requestServerBaseline = function()
            requested = requested + 1
        end
        bj.Client.queueNewCharacterBaselineCapture = function()
            queued = queued + 1
            return true
        end

        bj.Client.onCreatePlayer(0)

        T.assert_true(bj.Client._pendingNewCharacterBaseline == true, "Drift probe should keep new-character baseline flow active")
        T.assert_true(bj.Client._pendingNewCharacterBaselineReplaceLocal == true, "Same-character fresh run should enable replacement probe")
        T.assert_equal(requested, 1)
        T.assert_equal(queued, 1)
    end)

    T.test(prefix .. "client onCreatePlayer repairs invalid BurdJournals player payloads", function()
        local bj, env = T.require_client_module(variant.shared_path, variant.client_path)
        local requested = 0
        local queued = 0
        local modData = {
            BurdJournals = "corrupt"
        }
        local player = {
            getModData = function()
                return modData
            end,
            getHoursSurvived = function()
                return 0
            end
        }

        env.getSpecificPlayer = function(index)
            if index == 0 then
                return player
            end
            return nil
        end

        bj.isWithinBaselineSnapshotWindow = function() return true end
        bj.getBaselineSnapshotMaxHours = function() return 1 end
        bj.getPlayerCharacterId = function() return "steam_burd" end
        bj.Client.requestServerBaseline = function()
            requested = requested + 1
        end
        bj.Client.queueNewCharacterBaselineCapture = function()
            queued = queued + 1
            return true
        end

        bj.Client.onCreatePlayer(0)

        T.assert_type(modData.BurdJournals, "table")
        T.assert_equal(requested, 1)
        T.assert_equal(queued, 1)
    end)

    T.test(prefix .. "client tryBootstrapPendingNewCharacterBaseline clears stale local baseline after drift probe", function()
        local bj, env = T.require_client_module(variant.shared_path, variant.client_path)
        local captured = 0
        local transmitted = 0
        local player = {}
        local modData = {
            BurdJournals = {
                baselineCaptured = true,
                baselineVersion = 4,
                characterId = "steam_burd",
                steamId = "steam",
                skillBaseline = {Aiming = 75},
                mediaSkillBaseline = {},
                traitBaseline = {Brave = true},
                recipeBaseline = {OldRecipe = true}
            }
        }
        local knownTraits = java_list({"Athletic"})
        local knownRecipes = java_list({"NewRecipe"})
        local xpObj = {
            getXP = function(_, perk)
                if perk == "AimingPerk" then
                    return 150
                end
                return 0
            end
        }

        player.getModData = function() return modData end
        player.getHoursSurvived = function() return 0 end
        player.getCharacterTraits = function()
            return {
                getKnownTraits = function()
                    return knownTraits
                end
            }
        end
        player.getTraits = function()
            return knownTraits
        end
        player.getKnownRecipes = function()
            return knownRecipes
        end
        player.getXp = function()
            return xpObj
        end
        player.transmitModData = function()
            transmitted = transmitted + 1
        end

        bj.getBaselineSnapshotMaxHours = function() return 1 end
        bj.getAllowedSkills = function() return {"Aiming"} end
        bj.getPerkByName = function(_, skillName)
            if skillName == "Aiming" then
                return "AimingPerk"
            end
            return nil
        end
        bj.collectPlayerTraits = function()
            return {Athletic = true}
        end
        bj.collectPlayerMagazineRecipes = function()
            return {NewRecipe = true}
        end
        bj.getPlayerVhsSkillXPMapCopy = function()
            return {}
        end
        bj.Client.captureBaseline = function()
            captured = captured + 1
            modData.BurdJournals.baselineCaptured = true
        end
        bj.Client._pendingNewCharacterBaseline = true
        bj.Client._pendingNewCharacterBaselineReplaceLocal = true

        local result = bj.Client.tryBootstrapPendingNewCharacterBaseline(player, "test", false)

        T.assert_true(result == true, "Fresh drift probe should proceed into baseline capture")
        T.assert_equal(captured, 1)
        T.assert_true(modData.BurdJournals.skillBaseline == nil, "Stale local skill baseline should be cleared before capture")
        T.assert_true(modData.BurdJournals.traitBaseline == nil, "Stale local trait baseline should be cleared before capture")
        T.assert_true(modData.BurdJournals.recipeBaseline == nil, "Stale local recipe baseline should be cleared before capture")
        T.assert_equal(transmitted, 0)
    end)

    T.test(prefix .. "client restoreJournalNamesInContainer skips invalid journal payloads", function()
        local bj = T.require_client_module(variant.shared_path, variant.client_path)
        local renamed = 0
        local badItem = {
            getFullType = function() return "BurdJournals.FilledSurvivalJournal" end,
            getModData = function()
                return { BurdJournals = "corrupt" }
            end,
            getName = function() return "Broken" end
        }
        local goodData = {
            BurdJournals = {
                customName = "Recovered Name"
            }
        }
        local goodItem = {
            getFullType = function() return "BurdJournals.FilledSurvivalJournal" end,
            getModData = function()
                return goodData
            end,
            getName = function() return "Old Name" end
        }
        local container = {
            getItems = function()
                return java_list({badItem, goodItem})
            end
        }

        bj.updateJournalName = function(item)
            if item == goodItem then
                renamed = renamed + 1
            end
        end

        bj.Client.restoreJournalNamesInContainer(container)

        T.assert_equal(renamed, 1)
    end)

    T.test(prefix .. "discoverAllSkills excludes Lifestyle skills unless registered", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.Perks = {
            Aiming = {}
        }
        env.PerkFactory = nil
        bj.refreshSkillCache()

        local skills = bj.discoverAllSkills(true)
        T.assert_true(list_contains(skills, "Aiming"), "Expected known registered skill")
        T.assert_true(not list_contains(skills, "Art"), "Art should not appear without mod registration")
        T.assert_true(not list_contains(skills, "Cleaning"), "Cleaning should not appear without mod registration")
        T.assert_true(not list_contains(skills, "Dancing"), "Dancing should not appear without mod registration")
        T.assert_true(not list_contains(skills, "Meditation"), "Meditation should not appear without mod registration")
        T.assert_true(not list_contains(skills, "Music"), "Music should not appear without mod registration")
    end)

    T.test(prefix .. "discoverAllSkills includes mod skills when perk registry provides them", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.Perks = {
            Aiming = {},
            Art = {}
        }
        env.PerkFactory = {
            PerkList = {
                size = function() return 2 end,
                get = function(_, i)
                    if i == 0 then
                        return {
                            getId = function() return "Aiming" end,
                            getParent = function()
                                return { getId = function() return "Firearm" end }
                            end
                        }
                    end
                    if i == 1 then
                        return {
                            getId = function() return "Art" end,
                            getParent = function()
                                return { getId = function() return "Lifestyle" end }
                            end
                        }
                    end
                    return nil
                end
            },
            getPerk = function(perk)
                if perk == env.Perks.Aiming then
                    return {
                        getParent = function()
                            return { getId = function() return "Firearm" end }
                        end
                    }
                end
                if perk == env.Perks.Art then
                    return {
                        getParent = function()
                            return { getId = function() return "Lifestyle" end }
                        end
                    }
                end
                return nil
            end
        }
        bj.refreshSkillCache()

        local skills = bj.discoverAllSkills(true)
        T.assert_true(list_contains(skills, "Art"), "Expected Art when mod skill is registered in PerkFactory")
    end)

    T.test(prefix .. "adaptive trait compatibility blocks managed traits in player journals by default", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.SandboxVars = {
            BurdJournals = {
                EnableTraitRecordingPlayer = true,
                AllowAdaptiveTraitsManagedTraitRecording = false
            }
        }
        env.getActivatedMods = function()
            return {
                size = function() return 1 end,
                get = function(_, i)
                    if i == 0 then return "AdaptiveTraits" end
                    return nil
                end
            }
        end
        bj._adaptiveTraitsActive = nil

        T.assert_true(not bj.isTraitEnabledForJournal({isPlayerCreated = true}, "Brave"), "Adaptive-managed trait should be blocked for player journals")
        T.assert_true(bj.isTraitEnabledForJournal({isBloody = true}, "Brave"), "Loot journals should not be blocked by AdaptiveTraits compatibility")
    end)

    T.test(prefix .. "adaptive trait compatibility allows managed traits when enabled", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.SandboxVars = {
            BurdJournals = {
                EnableTraitRecordingPlayer = true,
                AllowAdaptiveTraitsManagedTraitRecording = true
            }
        }
        env.getActivatedMods = function()
            return {
                size = function() return 1 end,
                get = function(_, i)
                    if i == 0 then return "AdaptiveTraits" end
                    return nil
                end
            }
        end
        bj._adaptiveTraitsActive = nil

        T.assert_true(bj.isTraitEnabledForJournal({isPlayerCreated = true}, "Brave"), "Managed trait should be allowed when sandbox toggle is enabled")
    end)

    T.test(prefix .. "lifestyle-specific transient trait blocking is disabled", function()
        local bj = T.require_shared_module(variant.shared_path)
        T.assert_true(not bj.isLifestyleManagedTrait("FTBad"), "Lifestyle helper should no longer hard-block transient traits")
        T.assert_true(not bj.isTraitBlockedByModCompat({isPlayerCreated = true}, "FTBad"), "Player journals should not hard-block FTBad via dedicated Lifestyle compatibility")
        T.assert_true(not bj.isTraitBlockedByModCompat({isPlayerCreated = true}, "EldoradoGood"), "Player journals should not hard-block EldoradoGood via dedicated Lifestyle compatibility")
    end)

    T.test(prefix .. "profession profile registry supports custom inference", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.unregisterProfessionProfiles("TestMod")
        local inserted = bj.registerProfessionProfiles("TestMod", {
            {
                id = "home_ec",
                name = "Home Ec",
                flavorKey = "UI_BurdJournals_WornFlavor",
                skills = {"Cooking", "Tailoring"},
                priority = 5,
            }
        })
        T.assert_true(inserted == 1, "Expected one custom profession profile to register")

        local professionId, professionName, flavorKey = bj.inferProfessionFromEntries({
            skills = {
                Cooking = {xp = 120, level = 2},
                Tailoring = {xp = 90, level = 1},
            },
        }, {
            defaultProfessionId = "chef",
            defaultProfessionName = "Chef",
            defaultFlavorKey = "UI_BurdJournals_FlavorChef",
        })
        T.assert_equal(professionId, "home_ec")
        T.assert_equal(professionName, "Home Ec")
        T.assert_equal(flavorKey, "UI_BurdJournals_WornFlavor")
        bj.unregisterProfessionProfiles("TestMod")
    end)

    T.test(prefix .. "profession inference tie-break prefers higher priority then lexical id", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.unregisterProfessionProfiles("TieMod")
        local inserted = bj.registerProfessionProfiles("TieMod", {
            {id = "tie_a", name = "Tie A", skills = {"SkillTie"}, priority = 1},
            {id = "tie_b", name = "Tie B", skills = {"SkillTie"}, priority = 5},
        })
        T.assert_true(inserted == 2, "Expected two tie-break profiles to register")

        local professionId = bj.inferProfessionFromEntries({
            skills = {
                SkillTie = {xp = 50, level = 1},
            },
        }, {
            defaultProfessionId = "unemployed",
            defaultProfessionName = "Unemployed",
            defaultFlavorKey = "UI_BurdJournals_FlavorUnemployed",
        })
        T.assert_equal(professionId, "tie_b")
        bj.unregisterProfessionProfiles("TieMod")
    end)

    T.test(prefix .. "inferProfessionFromEntries falls back to Mod Generalist for unknown mod sources", function()
        local bj = T.require_shared_module(variant.shared_path)
        local professionId, professionName, flavorKey = bj.inferProfessionFromEntries({
            skills = {
                ["MysterySource:Art"] = {xp = 60, level = 1},
            },
        }, {
            defaultProfessionId = "unemployed",
            defaultProfessionName = "Unemployed",
            defaultFlavorKey = "UI_BurdJournals_FlavorUnemployed",
        })
        T.assert_true(type(professionId) == "string" and professionId:find("^mod_generalist_"), "Expected generated Mod Generalist profession ID")
        T.assert_true(type(professionName) == "string" and professionName:find("Generalist"), "Expected Mod Generalist profession name")
        T.assert_equal(flavorKey, "UI_BurdJournals_FlavorModGeneralist")
    end)

    T.test(prefix .. "hybrid threshold only overrides when fallback count exceeds core count", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.unregisterProfessionProfiles("HybridMod")
        bj.registerProfessionProfiles("HybridMod", {
            {
                id = "home_ec",
                name = "Home Ec",
                flavorKey = "UI_BurdJournals_WornFlavor",
                skills = {"Cooking", "Tailoring"},
                priority = 5,
            }
        })

        local inferredId = bj.resolveProfessionForGeneratedEntries(
            "chef",
            "Chef",
            "UI_BurdJournals_FlavorChef",
            {
                Cooking = {xp = 50, level = 1},
                Tailoring = {xp = 50, level = 1},
            },
            {},
            {},
            1,
            2
        )
        T.assert_equal(inferredId, "home_ec")

        local unchangedId = bj.resolveProfessionForGeneratedEntries(
            "chef",
            "Chef",
            "UI_BurdJournals_FlavorChef",
            {
                Cooking = {xp = 50, level = 1},
                Tailoring = {xp = 50, level = 1},
            },
            {},
            {},
            2,
            1
        )
        T.assert_equal(unchangedId, "chef")
        bj.unregisterProfessionProfiles("HybridMod")
    end)

    T.test(prefix .. "compactPlayerJournalDRCache trims oversized player cache", function()
        local bj = T.require_shared_module(variant.shared_path)
        local maxJ = bj.DR_PLAYER_CACHE_MAX_JOURNALS or 24
        local maxA = bj.DR_PLAYER_CACHE_MAX_ALIASES or 96

        local modData = {
            BurdJournals = {
                journalDRCache = {
                    journals = {},
                    aliases = {}
                }
            }
        }

        for i = 1, (maxJ + 12) do
            local key = "journal_" .. tostring(i)
            modData.BurdJournals.journalDRCache.journals[key] = {
                readCount = 1,
                updatedAt = i
            }
            modData.BurdJournals.journalDRCache.aliases["alias_" .. tostring(i)] = key
        end
        modData.BurdJournals.journalDRCache.aliases["bad_alias"] = "missing_journal"

        local transmitted = 0
        local player = {
            getModData = function() return modData end,
            transmitModData = function() transmitted = transmitted + 1 end
        }

        local changed, removedJournals, removedAliases = bj.compactPlayerJournalDRCache(player, true)
        T.assert_true(changed == true, "Expected cache compaction to report changed=true")
        T.assert_true(removedJournals > 0, "Expected journal entries to be pruned")
        T.assert_true(removedAliases > 0, "Expected alias entries to be pruned")
        T.assert_true(transmitted > 0, "Expected transmitModData when compaction changed cache")

        local journalCount = 0
        for _ in pairs(modData.BurdJournals.journalDRCache.journals) do
            journalCount = journalCount + 1
        end
        local aliasCount = 0
        for _ in pairs(modData.BurdJournals.journalDRCache.aliases) do
            aliasCount = aliasCount + 1
        end

        T.assert_true(journalCount <= maxJ, "Journal cache should be capped")
        T.assert_true(aliasCount <= maxA, "Alias cache should be capped")
        T.assert_true(modData.BurdJournals.journalDRCache.aliases["bad_alias"] == nil, "Invalid alias should be removed")
    end)

    T.test(prefix .. "compactPlayerBurdJournalsData removes legacy/transient baseline bloat", function()
        local bj = T.require_shared_module(variant.shared_path)
        local modData = {
            BurdJournals_Baseline = {
                skills = { Carpentry = 75 }
            },
            BurdJournals = {
                steamId = "76561198000000000",
                characterId = "legacy_char",
                fromServerCache = true,
                baselineCaptured = false,
                baselineVersion = 4,
                skillBaseline = {
                    Carpentry = 1275,
                    Negative = -10,
                    [""] = 5,
                    InvalidType = "not-a-number",
                    Metalworking = "525"
                },
                traitBaseline = {
                    Brave = true,
                    Cowardly = false,
                    [""] = true
                },
                recipeBaseline = {
                    MakeSoup = true,
                    FakeEntry = 1
                },
                journalDRCache = {
                    journals = {},
                    aliases = {},
                    junk = "unused"
                }
            }
        }

        local transmitted = 0
        local player = {
            getModData = function() return modData end,
            transmitModData = function() transmitted = transmitted + 1 end
        }

        local changed, removedLegacy, removedTransient, removedSkills, removedTraits, removedRecipes =
            bj.compactPlayerBurdJournalsData(player, true)

        T.assert_true(changed == true, "Expected compaction to report changed=true")
        T.assert_true(removedLegacy > 0, "Expected legacy baseline mirror to be removed")
        T.assert_true(removedTransient > 0, "Expected transient fields to be removed")
        T.assert_true(removedSkills > 0, "Expected invalid skill baseline entries to be removed")
        T.assert_true(removedTraits > 0, "Expected invalid trait baseline entries to be removed")
        T.assert_true(removedRecipes > 0, "Expected invalid recipe baseline entries to be removed")
        T.assert_true(transmitted > 0, "Expected transmitModData when compaction changed player data")

        T.assert_true(modData.BurdJournals_Baseline == nil, "Legacy baseline mirror should be removed")
        T.assert_true(modData.BurdJournals.steamId == nil, "Transient steamId should be removed")
        T.assert_true(modData.BurdJournals.characterId == nil, "Transient characterId should be removed")
        T.assert_true(modData.BurdJournals.fromServerCache == nil, "Transient fromServerCache should be removed")
        T.assert_true(modData.BurdJournals.baselineVersion == nil, "baselineVersion should be removed when baseline not captured")

        T.assert_equal(modData.BurdJournals.skillBaseline.Carpentry, 1275)
        T.assert_equal(modData.BurdJournals.skillBaseline.Metalworking, 525)
        T.assert_true(modData.BurdJournals.skillBaseline.Negative == nil, "Negative baseline XP should be removed")
        T.assert_true(modData.BurdJournals.skillBaseline[""] == nil, "Empty skill keys should be removed")
        T.assert_true(modData.BurdJournals.skillBaseline.InvalidType == nil, "Invalid numeric baseline values should be removed")

        T.assert_true(modData.BurdJournals.traitBaseline.Brave == true, "Valid trait baseline should remain")
        T.assert_true(modData.BurdJournals.traitBaseline.Cowardly == nil, "False trait baseline values should be removed")
        T.assert_true(modData.BurdJournals.traitBaseline[""] == nil, "Empty trait keys should be removed")

        T.assert_true(modData.BurdJournals.recipeBaseline.MakeSoup == true, "Valid recipe baseline should remain")
        T.assert_true(modData.BurdJournals.recipeBaseline.FakeEntry == nil, "Non-boolean recipe baseline values should be removed")
        T.assert_true(modData.BurdJournals.journalDRCache == nil, "Empty DR cache should be removed")
    end)

    T.test(prefix .. "getSkillBaseline returns zero for passive skills when baseline is not captured", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.hasBaselineCaptured = function() return false end
        local player = {
            getModData = function()
                return { BurdJournals = {} }
            end
        }

        T.assert_equal(bj.getSkillBaseline(player, "Fitness"), 0)
        T.assert_equal(bj.getSkillBaseline(player, "Strength"), 0)
    end)

    T.test(prefix .. "getSkillBaseline returns zero when passive baseline entry is missing", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.hasBaselineCaptured = function() return true end
        local player = {
            getModData = function()
                return { BurdJournals = {} }
            end
        }

        T.assert_equal(bj.getSkillBaseline(player, "Fitness"), 0)
        T.assert_equal(bj.getSkillBaseline(player, "Strength"), 0)
    end)

    T.test(prefix .. "getSkillBaseline uses explicit stored passive baseline when present", function()
        local bj = T.require_shared_module(variant.shared_path)
        local expected = (bj.PASSIVE_XP_THRESHOLDS and bj.PASSIVE_XP_THRESHOLDS[5]) or 37500
        local player = {
            getModData = function()
                return {
                    BurdJournals = {
                        skillBaseline = {
                            Fitness = expected,
                            Strength = expected,
                        }
                    }
                }
            end
        }

        T.assert_equal(bj.getSkillBaseline(player, "Fitness"), expected)
        T.assert_equal(bj.getSkillBaseline(player, "Strength"), expected)
    end)

    T.test(prefix .. "normalizeTable supports Lua table and Java-style list", function()
        local bj = T.require_shared_module(variant.shared_path)

        local plain = bj.normalizeTable({A = 1, B = 2})
        T.assert_type(plain, "table")
        T.assert_equal(plain.A, 1)
        T.assert_equal(plain.B, 2)

        local fakeJavaList = setmetatable({
            size = function() return 2 end,
            get = function(_, i)
                if i == 0 then return "x" end
                if i == 1 then return "y" end
                return nil
            end
        }, {
            -- Force normalizeTable to skip Lua-table clone path and use size/get path.
            __pairs = function()
                error("not a standard Lua table")
            end
        })
        local listResult = bj.normalizeTable(fakeJavaList)
        T.assert_type(listResult, "table")
        T.assert_equal(listResult[1], "x")
        T.assert_equal(listResult[2], "y")
    end)

    T.test(prefix .. "normalizeJournalData guarantees container fields", function()
        local bj = T.require_shared_module(variant.shared_path)
        local normalized = bj.normalizeJournalData({owner = "tester"})
        T.assert_type(normalized, "table")
        T.assert_type(normalized.skills, "table")
        T.assert_type(normalized.traits, "table")
        T.assert_type(normalized.recipes, "table")
        T.assert_type(normalized.stats, "table")
        T.assert_type(normalized.claims, "table")
        T.assert_equal(normalized.owner, "tester")
    end)

    T.test(prefix .. "safeGetText fallback behavior", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.getText = function(key)
            if key == "UI_BSJ_TEST_TRANSLATED" then
                return "TranslatedValue"
            end
            return key
        end

        T.assert_equal(bj.safeGetText("UI_BSJ_TEST_TRANSLATED", "Fallback"), "TranslatedValue")
        T.assert_equal(bj.safeGetText("UI_BSJ_TEST_MISSING", "Fallback"), "Fallback")
        T.assert_equal(bj.safeGetText(nil, "Fallback"), "Fallback")
    end)

    T.test(prefix .. "getTraitDisplayName resolves UI_trait keys from trait labels", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.CharacterTraitDefinition = nil
        env.TraitFactory = {
            getTrait = function(id)
                if id == "ModFancyTrait" then
                    return {
                        getLabel = function() return "UI_trait_ModFancyTrait" end
                    }
                end
                return nil
            end
        }
        env.getText = function(key)
            if key == "UI_trait_ModFancyTrait" then
                return "Mod Fancy Trait"
            end
            return key
        end

        T.assert_equal(bj.getTraitDisplayName("ModFancyTrait"), "Mod Fancy Trait")
    end)

    T.test(prefix .. "getTraitDisplayName prettifies unresolved UI_trait keys", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.CharacterTraitDefinition = nil
        env.TraitFactory = {
            getTrait = function(id)
                if id == "AnotherOddTrait" then
                    return {
                        getLabel = function() return "UI_trait_Another_OddTrait" end
                    }
                end
                return nil
            end
        }
        env.getText = function(key)
            return key
        end

        T.assert_equal(bj.getTraitDisplayName("AnotherOddTrait"), "Another Odd Trait")
    end)

    T.test(prefix .. "sanitizeJournalData preserves skills when perk registry is unavailable", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.Perks = {}
        env.PerkFactory = nil

        local data = {
            BurdJournals = {
                sanitizedVersion = 0,
                skills = {
                    LegacyModSkill = {xp = 420, level = 3}
                },
                traits = {},
                recipes = {}
            }
        }
        local transmitted = 0
        local item = {
            getModData = function() return data end,
            getID = function() return 8181 end,
            transmitModData = function() transmitted = transmitted + 1 end
        }

        local result = bj.sanitizeJournalData(item, nil)
        T.assert_type(result, "table")
        T.assert_true(result.cleaned ~= true)
        T.assert_type(data.BurdJournals.skills.LegacyModSkill, "table")
        T.assert_true(transmitted > 0)
    end)

    T.test(prefix .. "getJournalData ignores invalid raw journal payloads", function()
        local bj = T.require_shared_module(variant.shared_path)
        local item = {
            getModData = function()
                return { BurdJournals = "corrupt" }
            end
        }

        T.assert_true(bj.getJournalData(item) == nil)
    end)

    T.test(prefix .. "sanitizeJournalData repairs invalid raw journal payloads", function()
        local bj = T.require_shared_module(variant.shared_path)
        local transmitted = 0
        local data = {
            BurdJournals = "corrupt"
        }
        local item = {
            getModData = function()
                return data
            end,
            getFullType = function()
                return "BurdJournals.FilledSurvivalJournal"
            end,
            getID = function()
                return 8182
            end,
            transmitModData = function()
                transmitted = transmitted + 1
            end
        }

        local result = bj.sanitizeJournalData(item, nil)

        T.assert_type(result, "table")
        T.assert_true(result.cleaned == true)
        T.assert_true(result.resetInvalidData == true)
        T.assert_type(data.BurdJournals, "table")
        T.assert_true(data.BurdJournals.recoveredInvalidData == true)
        T.assert_equal(transmitted, 1)
    end)

    T.test(prefix .. "diminishing tracking mode per-claim is global", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.SandboxVars = {
            BurdJournals = {
                XPRecoveryMode = 2,
                DiminishingTrackingMode = 1,
                DiminishingFirstRead = 100,
                DiminishingDecayRate = 10,
                DiminishingMinimum = 10
            }
        }

        local journalData = {}
        local m1, r1 = bj.consumeJournalClaimRead(journalData, "Aiming")
        local m2, r2 = bj.consumeJournalClaimRead(journalData, "Aiming")

        T.assert_equal(as_percent(m1), 100)
        T.assert_equal(r1, 0)
        T.assert_equal(as_percent(m2), 90)
        T.assert_equal(r2, 1)
        T.assert_equal(journalData.readCount, 2)
    end)

    T.test(prefix .. "diminishing tracking mode per-session reuses same read", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.SandboxVars = {
            BurdJournals = {
                XPRecoveryMode = 2,
                DiminishingTrackingMode = 2,
                DiminishingFirstRead = 100,
                DiminishingDecayRate = 10,
                DiminishingMinimum = 10
            }
        }

        local journalData = {}
        local m1, r1 = bj.consumeJournalClaimRead(journalData, "Aiming", "session-a")
        local m2, r2 = bj.consumeJournalClaimRead(journalData, "Cooking", "session-a")
        local m3, r3 = bj.consumeJournalClaimRead(journalData, "Aiming", "session-b")

        T.assert_equal(as_percent(m1), 100)
        T.assert_equal(r1, 0)
        T.assert_equal(as_percent(m2), 100)
        T.assert_equal(r2, 0)
        T.assert_equal(as_percent(m3), 90)
        T.assert_equal(r3, 1)
        T.assert_equal(journalData.readSessionCount, 2)
    end)

    T.test(prefix .. "diminishing tracking mode per-skill is persistent", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.SandboxVars = {
            BurdJournals = {
                XPRecoveryMode = 2,
                DiminishingTrackingMode = 3,
                DiminishingFirstRead = 100,
                DiminishingDecayRate = 10,
                DiminishingMinimum = 10
            }
        }

        local journalData = {}
        local m1, r1 = bj.consumeJournalClaimRead(journalData, "Aiming")
        local m2, r2 = bj.consumeJournalClaimRead(journalData, "Aiming")
        local m3, r3 = bj.consumeJournalClaimRead(journalData, "Cooking")

        T.assert_equal(as_percent(m1), 100)
        T.assert_equal(r1, 0)
        T.assert_equal(as_percent(m2), 90)
        T.assert_equal(r2, 1)
        T.assert_equal(as_percent(m3), 100)
        T.assert_equal(r3, 0)
        T.assert_equal(journalData.skillReadCounts.Aiming, 2)
        T.assert_equal(journalData.skillReadCounts.Cooking, 1)
    end)

    T.test(prefix .. "diminishing per-skill resolves existing key casing", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.SandboxVars = {
            BurdJournals = {
                XPRecoveryMode = 2,
                DiminishingTrackingMode = 3,
                DiminishingFirstRead = 100,
                DiminishingDecayRate = 10,
                DiminishingMinimum = 10
            }
        }

        local journalData = {
            skillReadCounts = {
                aiming = 1
            }
        }

        local m1, r1 = bj.consumeJournalClaimRead(journalData, "Aiming")
        T.assert_equal(as_percent(m1), 90)
        T.assert_equal(r1, 1)
        T.assert_equal(journalData.skillReadCounts.aiming, 2)
        if journalData.skillReadCounts.Aiming ~= nil then
            T.assert_equal(journalData.skillReadCounts.Aiming, 2)
        end
    end)

    T.test(prefix .. "legacy DR migration seeds once and does not reseed after manual reset", function()
        local bj = T.require_shared_module(variant.shared_path)
        local data = {
            BurdJournals = {
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                skills = {Aiming = {xp = 75, level = 1}},
                readCount = 3
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 1337 end,
            transmitModData = function() end
        }

        bj.migrateJournalIfNeeded(item, nil)
        T.assert_type(data.BurdJournals.skillReadCounts, "table")
        T.assert_equal(data.BurdJournals.skillReadCounts.Aiming, 3)
        T.assert_true(data.BurdJournals.drLegacyMode3Migrated == true)

        -- Simulate intentional debug reset to 0; migration should not reseed.
        data.BurdJournals.skillReadCounts.Aiming = 0
        bj.migrateJournalIfNeeded(item, nil)
        T.assert_equal(data.BurdJournals.skillReadCounts.Aiming, 0)
    end)

    T.test(prefix .. "legacy claimedStats migrates into legacy_unknown claim bucket", function()
        local bj = T.require_shared_module(variant.shared_path)
        local data = {
            BurdJournals = {
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                claimedStats = {zombieKills = true},
                claimedSkills = {Aiming = true}
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 7331 end,
            transmitModData = function() end
        }

        bj.migrateJournalIfNeeded(item, nil)
        local legacyClaims = data.BurdJournals.claims and data.BurdJournals.claims.legacy_unknown
        T.assert_type(legacyClaims, "table")
        T.assert_type(legacyClaims.stats, "table")
        T.assert_equal(legacyClaims.stats.zombieKills, true)
        T.assert_type(legacyClaims.skills, "table")
        T.assert_equal(legacyClaims.skills.Aiming, true)
    end)

    T.test(prefix .. "legacy_unknown claims are honored for skills", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_123_Character" end
        local fakePlayer = {}
        local journalData = {
            claims = {
                legacy_unknown = {
                    skills = {Aiming = true}
                }
            }
        }
        T.assert_true(bj.hasCharacterClaimedSkill(journalData, fakePlayer, "Aiming"))
    end)

    T.test(prefix .. "legacy_unknown trait claims ignored for reusable player journals", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_123_Character" end
        bj.getSandboxOption = function() return false end
        local fakePlayer = {}
        local journalData = {
            isPlayerCreated = true,
            claims = {
                legacy_unknown = {
                    traits = {Brave = true}
                }
            }
        }
        T.assert_true(not bj.hasCharacterClaimedTrait(journalData, fakePlayer, "Brave"))
    end)

    T.test(prefix .. "legacy_unknown recipe claims ignored for reusable player journals", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_123_Character" end
        bj.getSandboxOption = function() return false end
        local fakePlayer = {}
        local journalData = {
            isPlayerCreated = true,
            claims = {
                legacy_unknown = {
                    recipes = {MakeBreadDough = true}
                }
            }
        }
        T.assert_true(not bj.hasCharacterClaimedRecipe(journalData, fakePlayer, "MakeBreadDough"))
    end)

    T.test(prefix .. "legacy_unknown stat claims ignored for reusable player journals", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_123_Character" end
        bj.getSandboxOption = function() return false end
        local fakePlayer = {}
        local journalData = {
            isPlayerCreated = true,
            claims = {
                legacy_unknown = {
                    stats = {zombieKills = true}
                }
            }
        }
        T.assert_true(not bj.hasCharacterClaimedStat(journalData, fakePlayer, "zombieKills"))
    end)

    T.test(prefix .. "legacy_unknown stat claims honored for dissolving restored journals", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_123_Character" end
        bj.getSandboxOption = function(opt)
            if opt == "AllowPlayerJournalDissolution" then
                return true
            end
            return false
        end
        local fakePlayer = {}
        local journalData = {
            isPlayerCreated = true,
            wasFromWorn = true,
            claims = {
                legacy_unknown = {
                    stats = {zombieKills = true}
                }
            }
        }
        T.assert_true(bj.hasCharacterClaimedStat(journalData, fakePlayer, "zombieKills"))
    end)

    T.test(prefix .. "restored player journals do not track trait claims when dissolution is disabled", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_123_Character" end
        bj.getSandboxOption = function() return false end
        local fakePlayer = {}
        local journalData = {
            isPlayerCreated = true,
            wasFromWorn = true,
            claims = {
                legacy_unknown = {
                    traits = {Brave = true}
                }
            }
        }
        T.assert_true(not bj.shouldTrackCharacterClaims(journalData, "traits"))
        T.assert_true(not bj.hasCharacterClaimedTrait(journalData, fakePlayer, "Brave"))
    end)

    T.test(prefix .. "legacy wasRestored marker is treated as restored for claim policy", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getSandboxOption = function() return false end
        local journalData = {
            isPlayerCreated = true,
            wasRestored = true
        }
        T.assert_true(bj.isRestoredJournalData(journalData) == true)
        T.assert_true(bj.shouldTrackCharacterClaims(journalData, "traits") == false)
    end)

    T.test(prefix .. "restoredBy fallback is treated as restored for claim policy", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getSandboxOption = function() return false end
        local journalData = {
            isPlayerCreated = true,
            restoredBy = "Tester"
        }
        T.assert_true(bj.isRestoredJournalData(journalData) == true)
        T.assert_true(bj.shouldTrackCharacterClaims(journalData, "traits") == false)
    end)

    T.test(prefix .. "compaction preserves restored-origin markers", function()
        local bj = T.require_shared_module(variant.shared_path)
        local data = {
            BurdJournals = {
                compactVersion = 0,
                wasRestored = true,
                wasFromBloody = true,
                isPlayerCreated = true
            }
        }
        local item = {
            getModData = function() return data end,
            transmitModData = function() end
        }
        bj.compactJournalData(item)
        T.assert_true(data.BurdJournals.wasRestored == true, "wasRestored must survive compaction")
        T.assert_true(data.BurdJournals.wasFromBloody == true, "wasFromBloody must survive compaction")
    end)

    T.test(prefix .. "compaction migrates legacy author into ownerCharacterName", function()
        local bj = T.require_shared_module(variant.shared_path)
        local data = {
            BurdJournals = {
                compactVersion = 0,
                author = "Legacy Author",
                ownerCharacterName = nil
            }
        }
        local item = {
            getModData = function() return data end,
            transmitModData = function() end
        }

        bj.compactJournalData(item)
        T.assert_equal(data.BurdJournals.ownerCharacterName, "Legacy Author")
        T.assert_true(data.BurdJournals.author == nil)
    end)

    T.test(prefix .. "migration normalizes legacy restored marker to canonical origin", function()
        local bj = T.require_shared_module(variant.shared_path)
        local data = {
            BurdJournals = {
                migrationSchemaVersion = 0,
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                wasRestored = true,
                isPlayerCreated = true,
                skills = {}
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 9191 end,
            transmitModData = function() end
        }
        bj.migrateJournalIfNeeded(item, nil)
        T.assert_true(data.BurdJournals.wasFromWorn == true, "wasRestored should normalize to wasFromWorn when source is unknown")
    end)

    T.test(prefix .. "clean player journals do not track trait claims", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getSandboxOption = function() return false end
        local journalData = {
            isPlayerCreated = true
        }
        T.assert_true(not bj.shouldTrackCharacterClaims(journalData, "traits"))
    end)

    T.test(prefix .. "ambiguous clean non-player journals default to reusable claims", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getSandboxOption = function() return false end
        local fakePlayer = {}
        local journalData = {
            isPlayerCreated = false,
            isWorn = false,
            isBloody = false,
            claims = {
                legacy_unknown = {
                    traits = {Brave = true}
                }
            }
        }
        T.assert_true(not bj.shouldTrackCharacterClaims(journalData, "traits"))
        T.assert_true(not bj.hasCharacterClaimedTrait(journalData, fakePlayer, "Brave"))
    end)

    T.test(prefix .. "limited-claim mode only applies to eligible loot journals", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getSandboxOption = function(opt)
            if opt == "EnableLimitedClaimLootJournals" then
                return true
            end
            if opt == "LootJournalMaxClaimsBeforeDissolve" then
                return 1
            end
            return false
        end

        T.assert_true(bj.isLimitedClaimLootJournalActive({isWorn = true}) == true)
        T.assert_true(bj.isLimitedClaimLootJournalActive({isBloody = true}) == true)
        T.assert_true(bj.isLimitedClaimLootJournalActive({isCursedReward = true}) == true)
        T.assert_true(not bj.isLimitedClaimLootJournalActive({isCursedJournal = true, isCursedReward = false, cursedState = "dormant"}))
        T.assert_true(not bj.isLimitedClaimLootJournalActive({isPlayerCreated = true}))
        T.assert_true(not bj.isLimitedClaimLootJournalActive({}))
    end)

    T.test(prefix .. "limited-claim counters sum mixed reward claims", function()
        local bj = T.require_shared_module(variant.shared_path)
        local player = {}
        local journalData = {
            isBloody = true,
            skills = {
                Aiming = {xp = 25, level = 1}
            },
            traits = {
                Brave = true
            },
            recipes = {
                SoupRecipe = true
            },
            stats = {
                zombieKills = {value = 12}
            },
            forgetSlot = true
        }

        bj.getSandboxOption = function(opt)
            if opt == "EnableLimitedClaimLootJournals" then
                return true
            end
            if opt == "LootJournalMaxClaimsBeforeDissolve" then
                return 4
            end
            return false
        end
        bj.getPlayerCharacterId = function()
            return "char_1"
        end

        bj.markSkillClaimedByCharacter(journalData, player, "Aiming")
        bj.markRecipeClaimedByCharacter(journalData, player, "SoupRecipe")
        bj.markForgetSlotClaimedByCharacter(journalData, player, "Smoker")

        T.assert_equal(bj.getSuccessfulLootClaimCount(journalData, player), 3)
        T.assert_equal(bj.getClaimsLeftBeforeDissolve(journalData, player), 1)
    end)

    T.test(prefix .. "limited-claim shouldDissolve respects configured cap", function()
        local bj = T.require_shared_module(variant.shared_path)
        local player = {}
        local modData = {
            BurdJournals = {
                isWorn = true,
                skills = {
                    Aiming = {xp = 25, level = 1}
                },
                traits = {
                    Brave = true
                }
            }
        }
        local item = {
            getModData = function()
                return modData
            end,
            getFullType = function()
                return "BurdJournals.WornSurvivalJournal"
            end
        }

        bj.getPlayerCharacterId = function()
            return "char_1"
        end
        bj.markSkillClaimedByCharacter(modData.BurdJournals, player, "Aiming")

        bj.getSandboxOption = function(opt)
            if opt == "EnableLimitedClaimLootJournals" then
                return true
            end
            if opt == "LootJournalMaxClaimsBeforeDissolve" then
                return 1
            end
            return false
        end
        T.assert_true(bj.shouldDissolve(item, player) == true, "Cap-reached loot journal should dissolve immediately")

        bj.getSandboxOption = function()
            return false
        end
        T.assert_true(bj.shouldDissolve(item, player) == false, "Without limited-claim mode, unclaimed rewards should still block dissolution")
    end)

    T.test(prefix .. "trait lifecycle dispatcher maps add/remove events to expected direction", function()
        local bj = T.require_shared_module(variant.shared_path)
        local directions = {}
        local originalReconcile = bj.reconcileTraitXpBoostLevels
        bj.reconcileTraitXpBoostLevels = function(_, _, direction)
            directions[#directions + 1] = direction
            return true
        end

        bj.applyTraitLifecycleSideEffects({}, "Brave", "trait_added", {source = "test"})
        bj.applyTraitLifecycleSideEffects({}, "Brave", "removed", {source = "test"})
        bj.reconcileTraitXpBoostLevels = originalReconcile

        T.assert_equal(directions[1], 1)
        T.assert_equal(directions[2], -1)
    end)

    T.test(prefix .. "trait XP boost reconciliation is symmetric for add/remove", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.transformIntoKahluaTable = function(value) return value end
        bj.computeLevelShiftTargetXP = function(_, _, currentXP, currentLevel, levelDelta)
            local xpNow = tonumber(currentXP) or 0
            local levelNow = tonumber(currentLevel) or 0
            local delta = tonumber(levelDelta) or 0
            return xpNow + (delta * 100), levelNow + delta
        end

        local perkObj = {}
        env.Perks = {Aiming = perkObj}

        local xpByPerk = {[perkObj] = 250}
        local xpObj = {
            getXP = function(_, perk)
                return xpByPerk[perk] or 0
            end,
            AddXP = function(_, perk, amount)
                xpByPerk[perk] = (xpByPerk[perk] or 0) + (tonumber(amount) or 0)
            end,
        }
        local player = {
            getXp = function() return xpObj end,
            getPerkLevel = function(_, perk)
                return math.floor((xpByPerk[perk] or 0) / 100)
            end,
        }
        local traitDef = {
            getXpBoosts = function()
                return {Aiming = 1}
            end,
        }

        local added = bj.reconcileTraitXpBoostLevels(player, "TestTrait", 1, {traitDef = traitDef})
        T.assert_true(added == true)
        T.assert_equal(xpByPerk[perkObj], 350)

        local removed = bj.reconcileTraitXpBoostLevels(player, "TestTrait", -1, {traitDef = traitDef})
        T.assert_true(removed == true)
        T.assert_equal(xpByPerk[perkObj], 250)
    end)

    T.test(prefix .. "smoker removal clears nicotine stress and adjusts general stress", function()
        local bj = T.require_shared_module(variant.shared_path)
        local stress = 0.7
        local nicotineStress = 0.3
        local stats = {
            getStressFromCigarettes = function() return nicotineStress end,
            setStressFromCigarettes = function(_, value) nicotineStress = tonumber(value) or 0 end,
            getStress = function() return stress end,
            setStress = function(_, value) stress = tonumber(value) or 0 end,
        }
        local player = {
            getStats = function() return stats end,
        }

        bj.applyTraitLifecycleSideEffects(player, "Smoker", "trait_removed", {source = "test"})
        T.assert_true(math.abs(nicotineStress - 0) < 0.0001, "Expected nicotine stress to clear")
        T.assert_true(math.abs(stress - 0.4) < 0.0001, "Expected general stress to reduce by nicotine amount")
    end)

    T.test(prefix .. "smoker removal stress adjustment clamps at zero", function()
        local bj = T.require_shared_module(variant.shared_path)
        local stress = 0.1
        local nicotineStress = 0.3
        local stats = {
            getStressFromCigarettes = function() return nicotineStress end,
            setStressFromCigarettes = function(_, value) nicotineStress = tonumber(value) or 0 end,
            getStress = function() return stress end,
            setStress = function(_, value) stress = tonumber(value) or 0 end,
        }
        local player = {
            getStats = function() return stats end,
        }

        bj.applyTraitLifecycleSideEffects(player, "Smoker", "trait_removed", {source = "test"})
        T.assert_true(math.abs(nicotineStress - 0) < 0.0001, "Expected nicotine stress to clear")
        T.assert_true(math.abs(stress - 0) < 0.0001, "Expected general stress to clamp at zero")
    end)

    T.test(prefix .. "non-smoker trait removal does not mutate stress values", function()
        local bj = T.require_shared_module(variant.shared_path)
        local stress = 0.6
        local nicotineStress = 0.2
        local stats = {
            getStressFromCigarettes = function() return nicotineStress end,
            setStressFromCigarettes = function(_, value) nicotineStress = tonumber(value) or 0 end,
            getStress = function() return stress end,
            setStress = function(_, value) stress = tonumber(value) or 0 end,
        }
        local player = {
            getStats = function() return stats end,
        }

        bj.applyTraitLifecycleSideEffects(player, "Brave", "trait_removed", {source = "test"})
        T.assert_true(math.abs(nicotineStress - 0.2) < 0.0001)
        T.assert_true(math.abs(stress - 0.6) < 0.0001)
    end)

    T.test(prefix .. "trait removal wrapper dispatches fallback context through lifecycle", function()
        local bj = T.require_shared_module(variant.shared_path)
        local observed = nil
        local originalReconcile = bj.reconcileTraitXpBoostLevels
        bj.reconcileTraitXpBoostLevels = function(_, traitId, direction, context)
            observed = {
                traitId = traitId,
                direction = direction,
                source = context and context.source or nil,
            }
            return false
        end

        bj.applyTraitRemovalSideEffects({}, "Smoker", {source = "removeTraitAuthoritatively_fallback"})
        bj.reconcileTraitXpBoostLevels = originalReconcile

        T.assert_type(observed, "table")
        T.assert_equal(observed.traitId, "Smoker")
        T.assert_equal(observed.direction, -1)
        T.assert_equal(observed.source, "removeTraitAuthoritatively_fallback")
    end)

    T.test(prefix .. "runSelfTests returns structured result", function()
        local bj, env = T.require_shared_module(variant.shared_path)
        env.getText = function(key) return key end
        local result = bj.runSelfTests and bj.runSelfTests()
        T.assert_type(result, "table")
        T.assert_type(result.passed, "number")
        T.assert_type(result.failed, "number")
        T.assert_true(result.failed == 0, "Expected runSelfTests to pass starter checks")
    end)
end
