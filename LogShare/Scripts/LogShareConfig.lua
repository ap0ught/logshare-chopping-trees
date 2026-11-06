-- LogShare configuration
-- Changes take effect after restarting the game.

return {
    -- Fraction of a sale paid to the original chopper when someone else sells their log.
    -- 0.5 = half / half (seller gets half, chopper gets half).
    ChopperShare = 0.5,

    -- When true, log every chop, sale and money split to the UE4SS console/log.
    VerboseLogging = true,

    -- Tag ground logs with the chopper's id when they spawn.
    -- The game already exposes LogOwnerId / ChopInstigator on some builds;
    -- we write them when present and always keep our own registry.
    WriteGameOwnerProperties = true,

    -- On-screen toast when a split happens (small, unobtrusive).
    ShowSplitNotifications = true,
}
