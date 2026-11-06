# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

**LogShare** — a UE4SS Lua mod for *A Game About Chopping Trees* (Steam App **4512570**).
Co-op rule: chopped logs are tagged with the chopper’s id; on sawmill sale, seller == chopper → full price, otherwise seller keeps half and each foreign chopper gets an equal share (`ChopperShare`, default `0.5`).

Repo: https://github.com/ap0ught/logshare-chopping-trees

## Layout

| Path | Role |
|------|------|
| `LogShare/Scripts/main.lua` | Mod logic (hooks, ownership registry, money poll, splits, debug UI) |
| `LogShare/Scripts/LogShareConfig.lua` | User config (return a table) |
| `LogShare/enabled.txt` | UE4SS enable marker (empty file; required for auto-load) |
| `dist/LogShare-v*.zip` | LogShare-only drop-in |
| `dist/ChoppingTrees-Mods-*.zip` | Full package: UE4SS + Lumber Vision + LogShare |
| `README.md` | Player-facing install/config/credits |
| `LICENSE` | MIT for **our** LogShare source only |

Do not commit game files, saves, UE4SS binaries, or decompiled dumps.

## Game / mod facts (verified from shipping exe strings)

- UE5.7/5.8, Windows build; often run via **Proton** on Linux.
- Classes/assets: `BP_Human_C`, `BP_Tree_Log` (+ `_Birch`/`_Pine`/`_Oak`…), `BP_Tree_FallenLog`, `BP_LogPickup`, `BP_PlayerState_Base`.
- Money: `Money` on PlayerState (GAS); sawmill payout raises it.
- Owner fields seen in exe: `LogOwner`, `LogOwnerId`, `ChopInstigator`, `OwnerPlayer`.
- Choppers/sellers identified via `BP_Human_C` + `PlayerState.PlayerId` / `PlayerName`.

## UE4SS conventions

- Loader package: `dwmapi.dll` + `ue4ss/` beside `ChoppingTrees-Win64-Shipping.exe`.
- Mods live in `ue4ss/Mods/<Name>/` with `enabled.txt` + `Scripts/main.lua`.
- `print()` → UE4SS console/log. Prefer `pcall` around all UObject access.
- On-screen text: `UEHelpers.GetKismetSystemLibrary():PrintString(...)` (same pattern as Lumber Vision).
- Timers: `ExecuteInGameThreadWithDelay(ms, fn)` — **anonymous** functions only; Lua has no `function name()` expression form (this broke early LogShare loads).
- Hot reload / GUI console are **off** in shipped `UE4SS-settings.ini`; enable for local debug.

## Proton / Linux (critical)

Wine’s builtin `dwmapi.dll` shadows UE4SS’s proxy unless launch options force native:

```
WINEDLLOVERRIDES=dwmapi=n,b %command%
```

No quotes around the value in Steam launch options (quotes become part of the env string and Wine never matches `dwmapi.dll`).

Set via Steam → Properties → Launch Options. Steam rewrites `localconfig.vdf` while running; edit only with Steam shut down if patching by hand.

## Local test checklist

1. Saves: `um backup create` on  
   `.../compatdata/4512570/pfx/drive_c/users/steamuser/AppData/Local/ChoppingTrees/Saved`  
   before modded launches.
2. Install zip into `ChoppingTrees/Binaries/Win64`.
3. Confirm `WINEDLLOVERRIDES` and that `/proc/<pid>/maps` shows **our** `.../Win64/dwmapi.dll`, not  
   `.../proton-*/files/lib/wine/x86_64-windows/dwmapi.dll`.
4. Expect logs: `Win64/UE4SS.log`, `Win64/LogShare.log` (or `Saved/Logs/LogShare.log`).
5. Debug screen (config `DebugScreen = true`): player, `$`, tag count, last event.

## Config keys (`LogShareConfig.lua`)

`ChopperShare`, `VerboseLogging`, `WriteGameOwnerProperties`, `ShowSplitNotifications`, `DebugScreen`, `DebugScreenRefreshMilliseconds`, `LogFile`.

## Known gaps / next work

- Sale detection is **Money polling**, not a per-log sawmill hook — refine after a live class/function dump.
- Splits only apply on a client that can see both PlayerStates; run mod on both co-op peers.
- `SetPropertyValue("Money", ...)` / `LogOwnerId` writability untested until a session with a working UE4SS log.
- `NotifyOnNewObject` paths for log BPs may move with game updates — keep the generic `Actor` fallback.

## Commands

```bash
# Syntax-check Lua (host)
lua5.4 -e "assert(loadfile('LogShare/Scripts/main.lua'))"
lua5.4 -e "assert(loadfile('LogShare/Scripts/LogShareConfig.lua'))"

# Rebuild LogShare-only zip (example staging root)
# …copy LogShare/ + README into ue4ss/Mods/LogShare and zip .

git add LogShare README.md dist && git commit && git push
```

## Style

- No comments unless they explain non-obvious game/UE4SS behavior.
- Prefer small `pcall`-guarded helpers (`safe_get` / `safe_set` / `is_valid`).
- Keep player-facing docs in `README.md`; keep this file operational for agents.
