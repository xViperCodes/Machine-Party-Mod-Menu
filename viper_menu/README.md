# Viper Menu v0.3 - Machine Party

Mod for Krunk-theduck's MachinePartyModLoader (loader v3 / API 2). Developed by xViperCodes.

## Install
1. Run `MachinePartyModLoader.exe` once so a `mods` folder exists next to `Machine Party.exe`.
2. Put this `viper_menu` folder inside `mods` (you should have `mods/viper_menu/mod.json`).
3. Start the game, press **INSERT**.

After a game update, re-run the loader (that's the loader's rule, not this mod's).

## Default hotkeys (all rebindable in the Hotkeys tab)
| Key | Action |
|-|-|
| INSERT | Toggle menu (Esc also closes it) |
| END | Unload mod |
| PAGE DOWN | Toggle ESP |
| HOME | Teleport all players to you |
| PAGE UP | Teleport items & entities to the chosen player |
| Mouse 2 | Aim key (Duck Hunt) |
| J | Teleport to the Duck Hunt marker |
| G (hold) | The Filter auto-solve |
| L / K | Table Manners: he looked up / looked away |
| V | Stable Footing: cycle fallback symbol |
| F6 | Freecam |
| F8 | Console |
| (unbound) | Noclip, shove / freeze / smite the chosen player |

Noclip: W forward, S back, A left, D right, Space up, Shift down.

While the menu is open only INSERT/END work, so clicking around doesn't fire game hotkeys.

The menu fits itself to the screen. Drag the title bar to move it, drag the corner grip to resize it,
and use Settings > Menu scale to make it bigger or smaller.

## New in v0.3
- **Server Browser tab:** list public lobbies, join one, join any lobby by room ID, copy your room ID,
  and (host) make your lobby public with a name, max players and mid-match joining.
  Shares the lobby format with MachineParty+, so players of either mod see each other's lobbies.
- **Kick:** a player dropdown and Kick button in the Players tab (plus `kick <name>` in the console).
- **Noclip:** new controls (W/A/S/D, Space up, Shift down), moves flat relative to the camera and
  stays on through round starts.
- **Info tab:** GitHub and YouTube buttons and credits.
- **Freecam:** same keys as noclip (W/A/S/D, Space up, Shift down); the mouse wheel sets the speed.
- **Console:** `kick`, `servers`, `join <room id>`, `roomid`, `public`, `private`.

## New in v0.2
- **Session tab (host):** score editor (+ / - / 0 per player, step size, reset all), points multiplier,
  skip round, skip minigame, restart minigame, end after this minigame, end session now,
  and pick the Duck Hunt hunter (next round only, or every round).
- **Players tab:** Shove, Freeze and Smite buttons on every player, plus freeze / unfreeze / smite
  everyone else. Smite is greyed out in minigames where the game decides eliminations itself
  (Chisel Gauntlet, Smoke Break...). Shove falls back to a short teleport push where a minigame
  has no shove of its own.
- **Misc tab:** Freecam (F6). Mouse to look, W forward, S back, A left, D right, Space up,
  Shift down, mouse wheel = speed. "Follow player" orbits a player instead (wheel = distance).
  Your character is frozen while flying unless you turn that off. Only your screen changes.
- **Console:** `freecam`, `shove/freeze/smite <name>`, `score <name> <points>`, `skip`, `skip game`,
  `restart`, `end`, `end now`.

## Host vs client
The host runs the game logic, so some features need you to be host:
- **Host only:** custom queue / play now / force-start, the whole Session tab, kick, making the lobby public,
  Inside Job syringe info, bots,
  moving host-owned objects (mines, crates, junk...), exact Table Manners timer.
- **Works for everyone, even on friends running vanilla:** teleport to / teleport to me / pull all
  (uses the game's own `teleport_rpc`), shove, freeze, smite, ESP, aimbot, solvers, noclip, freecam, speed hack.
- **Godmode** is fully reliable only as host (each machine keeps its own health counter).

## Known limits
- **The Filter auto-solve** is best-effort: the Filter's player script wasn't in the decompiled
  files, so it detects items by their type value (0-3 burn, 4-7 recycle). The status line in the
  Solvers tab says what it found. Swap Buttons / the action names fix inverted inputs.
- **Bots (beta)** stand still. A minigame that waits on every player for something the mod
  doesn't answer can hang - remove the bot.
- ESP / aimbot / solver overlays target online play; local couch mode renders split-screen.
- The **Debug Mode** flag shows `n/a` if your game version has no matching variable.

## Credits
- xViperCodes - Viper Menu
- Obsidian420 - inspiration and a lot of the cheat / solver ideas
- Krunk-theduck - MachinePartyModLoader
- J_axon and Krunk - MachineParty+ (server browser and public lobbies adapted from it, MIT License -
  see THIRD_PARTY_NOTICES.md)

## If something breaks
- `%APPDATA%\Godot\app_userdata\Machine Party\modloader.log` - what the loader loaded.
- `...\Machine Party\logs\godot.log` - the actual error (search for `SCRIPT ERROR`).
- A module that fails to compile shows a red note on its tab; the rest of the menu keeps working.

## Files
- `main.gd` entry point - `core/` config, game helpers, hotkeys, UI - `features/` one file per feature.
- `config.json` appears when you press Save config.
