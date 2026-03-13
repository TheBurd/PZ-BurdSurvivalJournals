local T = BSJ_TEST
if not T then
    error("BSJ_TEST harness not available")
end

local variants = {
    {
        label = "42",
        shared_path = T.join_path(T.mod_root, "42/media/lua/shared/BurdJournals_Shared.lua")
    },
    {
        label = "common",
        shared_path = T.join_path(T.mod_root, "common/media/lua/shared/BurdJournals_Shared.lua")
    }
}

for _, variant in ipairs(variants) do
    local prefix = "[migration " .. variant.label .. "] "

    T.test(prefix .. "schema stamps once and second pass is no-op", function()
        local bj = T.require_shared_module(variant.shared_path)
        local transmitCount = 0
        local data = {
            BurdJournals = {
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                ownerUsername = "LegacyUser",
                skills = {Aiming = {xp = 75, level = 1}},
                claimedSkills = {Aiming = true},
                readCount = 2
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 9001 end,
            transmitModData = function() transmitCount = transmitCount + 1 end
        }

        bj.migrateJournalIfNeeded(item, nil)
        local targetSchema = tonumber(bj.MIGRATION_SCHEMA_VERSION) or 1
        T.assert_equal(tonumber(data.BurdJournals.migrationSchemaVersion) or 0, targetSchema)
        T.assert_true(transmitCount > 0, "first migration pass should persist data")

        transmitCount = 0
        bj.migrateJournalIfNeeded(item, nil)
        T.assert_equal(transmitCount, 0, "second migration pass should not rewrite unchanged data")
    end)

    T.test(prefix .. "legacy claims survive compact via legacy_unknown fallback", function()
        local bj = T.require_shared_module(variant.shared_path)
        bj.getPlayerCharacterId = function() return "steam_1_Character" end
        local fakePlayer = {}
        local data = {
            BurdJournals = {
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                isPlayerCreated = false,
                wasFromWorn = true,
                skills = {Aiming = {xp = 75, level = 1}},
                claimedSkills = {Aiming = true},
                claimedStats = {zombieKills = true},
                readCount = 1
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 9002 end,
            transmitModData = function() end
        }

        bj.migrateJournalIfNeeded(item, nil)

        local claims = data.BurdJournals.claims
        T.assert_type(claims, "table")
        T.assert_type(claims.legacy_unknown, "table")
        T.assert_true(data.BurdJournals.claimedSkills == nil, "compact pass should remove legacy claimedSkills")
        T.assert_true(data.BurdJournals.claimedStats == nil, "compact pass should remove legacy claimedStats")
        T.assert_true(bj.hasCharacterClaimedSkill(data.BurdJournals, fakePlayer, "Aiming"))
        T.assert_true(bj.hasCharacterClaimedStat(data.BurdJournals, fakePlayer, "zombieKills"))
    end)

    T.test(prefix .. "legacy claims normalize even when schema is already stamped", function()
        local bj = T.require_shared_module(variant.shared_path)
        local targetSchema = tonumber(bj.MIGRATION_SCHEMA_VERSION) or 1
        local data = {
            BurdJournals = {
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                migrationSchemaVersion = targetSchema,
                claims = {
                    legacy_unknown = {
                        skills = {Aiming = true}
                    }
                },
                claimedSkills = {Reloading = true},
                claimedStats = {zombieKills = true}
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 9003 end,
            transmitModData = function() end
        }

        bj.migrateJournalIfNeeded(item, nil)

        local legacyClaims = data.BurdJournals.claims and data.BurdJournals.claims.legacy_unknown
        T.assert_type(legacyClaims, "table")
        T.assert_type(legacyClaims.skills, "table")
        T.assert_equal(legacyClaims.skills.Aiming, true)
        T.assert_equal(legacyClaims.skills.Reloading, true)
        T.assert_type(legacyClaims.stats, "table")
        T.assert_equal(legacyClaims.stats.zombieKills, true)
        T.assert_true(data.BurdJournals.claimedSkills == nil, "legacy claimedSkills should be normalized away")
        T.assert_true(data.BurdJournals.claimedStats == nil, "legacy claimedStats should be normalized away")
        T.assert_equal(tonumber(data.BurdJournals.migrationSchemaVersion) or 0, targetSchema)
    end)

    T.test(prefix .. "depot-style legacy payload normalizes ownership and claims", function()
        local bj = T.require_shared_module(variant.shared_path)
        local targetSchema = tonumber(bj.MIGRATION_SCHEMA_VERSION) or 1
        local data = {
            BurdJournals = {
                sanitizedVersion = bj.SANITIZE_VERSION or 1,
                author = "Legacy Author",
                ownerUsername = "LegacyUser",
                ownerCharacterName = nil,
                isWorn = false,
                isBloody = false,
                claimedSkills = {Aiming = true},
                claimedTraits = {Brave = true},
                claimedRecipes = {MakeBreadDough = true},
                claimedStats = {zombieKills = true}
            }
        }
        local item = {
            getModData = function() return data end,
            getID = function() return 9004 end,
            transmitModData = function() end
        }

        bj.migrateJournalIfNeeded(item, nil)

        local journal = data.BurdJournals
        local legacyClaims = journal.claims and journal.claims.legacy_unknown
        T.assert_equal(journal.ownerSteamId, "legacy_LegacyUser")
        T.assert_equal(journal.isPlayerCreated, true)
        T.assert_equal(journal.ownerCharacterName, "Legacy Author")
        T.assert_true(journal.author == nil, "author should be compacted into ownerCharacterName")
        T.assert_type(legacyClaims, "table")
        T.assert_type(legacyClaims.skills, "table")
        T.assert_type(legacyClaims.traits, "table")
        T.assert_type(legacyClaims.recipes, "table")
        T.assert_type(legacyClaims.stats, "table")
        T.assert_equal(legacyClaims.skills.Aiming, true)
        T.assert_equal(legacyClaims.traits.Brave, true)
        T.assert_equal(legacyClaims.recipes.MakeBreadDough, true)
        T.assert_equal(legacyClaims.stats.zombieKills, true)
        T.assert_equal(tonumber(journal.migrationSchemaVersion) or 0, targetSchema)
    end)
end
