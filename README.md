# LogShare — A Game About Chopping Trees

Co-op log ownership split for [A Game About Chopping Trees](https://store.steampowered.com/app/4512570/) (Steam 4512570), running as a [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod.

## Rules

1. When a player chops a tree, the resulting ground logs are tagged with that player's id.
2. On sale (sawmill payout):
   - **Seller chopped it** → seller keeps the **full** price.
   - **Someone else chopped it** → seller keeps **half**, the chopper receives the **other half**.

Solo play is unaffected (seller always == chopper). The split fraction is configurable (`ChopperShare`).

## Packages

| Zip | Contents |
|-----|----------|
| `dist/LogShare-v0.1.0.zip` | **Just LogShare** — drop into `ChoppingTrees\Binaries\Win64` (requires UE4SS already installed). |
| `dist/ChoppingTrees-Mods-UE4SS-LumberVision-LogShare-v1.2.0.zip` | **Full drop-in** — UE4SS loader + Lumber Vision + LogShare, everything needed in one extract. |

Also mirrored as GitHub Release assets when published.

## Install (full drop-in)

1. Steam → right-click game → **Manage → Browse local files**.
2. Open `ChoppingTrees\Binaries\Win64`.
3. Extract the full zip into that folder (so `dwmapi.dll` sits beside `ChoppingTrees-Win64-Shipping.exe`).
4. Launch the game. Both gameplay mods ship `enabled.txt` and turn on automatically.

## Install (LogShare only)

Same as above but extract `LogShare-v0.1.0.zip`; UE4SS must already be present.

## Configuration

- `ue4ss\Mods\LogShare\Scripts\LogShareConfig.lua`
  - `ChopperShare` — fraction paid to the original chopper when someone else sells (default `0.5`).
  - `VerboseLogging` — log chops/sales/splits to the UE4SS console.
  - `WriteGameOwnerProperties` — also write `LogOwnerId` / `ChopInstigator` when the game exposes them.
  - `ShowSplitNotifications` — notify on splits.
- Restart the game after editing.

## Multiplayer notes

- Run the mod on **both** co-op clients so ownership tags and Money adjustments stay consistent.
- v0.1.0 tags logs via `BP_Tree_Log*` spawn watchers + world scan, and detects sales via `Money` attribute polling. Splits adjust each visible `PlayerState`'s `Money` on that client.
- If the other player's `PlayerState` is not visible, the split is logged but not delivered on that client.
- Per-log sawmill hooks are planned once a live UE4SS class dump hardens the sale path.

## Layout in the game folder

```
ChoppingTrees\Binaries\Win64\
  dwmapi.dll
  ue4ss\
    UE4SS.dll
    UE4SS-settings.ini
    Mods\
      LogShare\
        enabled.txt
        Scripts\main.lua
        Scripts\LogShareConfig.lua
      LumberVision\          (full package only)
        ...
```

## Uninstall

Delete `ue4ss\Mods\LogShare` (and/or the whole `ue4ss\` + `dwmapi.dll` for a clean slate). Saves are not modified.

## Credits

- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — MIT License (bundled binaries unchanged from upstream).
- **Lumber Vision** v0.3.2 by **Kaliraxa** (Nexus Mods) — included in the full package with credit; remains property of its author.
- **LogShare** — original mod for this repository.
- Unofficial; not affiliated with Space Raccoon Game Studio, Spaghetti Cat, Nexus Mods, or UE4SS-RE.
- Generative AI assisted Lua development of LogShare (and of Lumber Vision, per its author's disclosure).

## License

LogShare source in this repo is MIT. Bundled third-party components keep their own licenses (see `dist/` package READMEs).
