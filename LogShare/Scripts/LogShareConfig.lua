-- LogShare configuration
-- Changes take effect after restarting the game (or Ctrl+R if hot-reload is on).

return {
    -- Fraction of a sale paid to the original chopper when someone else sells their log.
    -- 0.5 = half / half (seller gets half, chopper gets half).
    ChopperShare = 0.5,

    -- When true, log every chop, sale and money split to UE4SS console AND the file log.
    VerboseLogging = true,

    -- Tag ground logs with the chopper's id when they spawn.
    -- The game already exposes LogOwnerId / ChopInstigator on some builds;
    -- we write them when present and always keep our own registry.
    WriteGameOwnerProperties = true,

    -- On-screen toast when a split happens (PrintString, short).
    ShowSplitNotifications = true,

    -- Persistent on-screen debug line (money, tagged logs, last event).
    DebugScreen = true,
    DebugScreenRefreshMilliseconds = 500,

    -- File log. Empty = try defaults (LogShare.log next to the mod, then
    -- the game's Saved/Logs folder). Always written when non-empty.
    -- Example: "C:\\users\\steamuser\\AppData\\Local\\ChoppingTrees\\Saved\\Logs\\LogShare.log"
    LogFile = "",
}
