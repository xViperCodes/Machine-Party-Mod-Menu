<div align="center">

# 🐍 VIPER MENU v0.2

**Mod menu for Machine Party** - by **xViperCodes**

Runs on Krunk-theduck's [MachinePartyModLoader](https://github.com/Krunk-theduck/MachinePartyModLoader)

![Version](https://img.shields.io/badge/version-v0.2-3ddc84?style=flat-square)
![Game](https://img.shields.io/badge/game-Machine%20Party-555?style=flat-square)
![Loader](https://img.shields.io/badge/loader-MachinePartyModLoader-555?style=flat-square)

![Viper Menu](https://i.imgur.com/ixTfGkp_d.webp?maxwidth=1520&fidelity=grand)
![Viper Menu](https://i.imgur.com/dxbMTdk_d.webp?maxwidth=1520&fidelity=grand)
![Viper Menu](https://i.imgur.com/8PbJDq0_d.webp?maxwidth=1520&fidelity=grand)
https://github.com/user-attachments/assets/82beea6f-b275-4d6c-adcd-be6de977a7a2
https://github.com/user-attachments/assets/6015d4f8-18cb-45a1-8c89-79bd60456622

</div>

## Before you use it

- ![BETA](https://img.shields.io/badge/BETA-f0b030?style=flat-square) features work but are still rough. They might not work in every minigame or situation.
- ![HOST](https://img.shields.io/badge/HOST-ff6b6b?style=flat-square) features only work when **you are hosting the lobby**. The host runs the game, so things like the queue, scores and kicking have to come from the host.
- **Not every feature has been tested in every minigame, or as both host and client.** If something breaks or acts weird, **please leave feedback or report the issue in the [Issues](../../issues) tab** (there's a template at the bottom). It really helps.
- **Works with other mods installed, as long as hotkeys do not interfere.**

---

## Features

### Debug
- 13 of the game's own debug flags, each set to Leave / Force On / Force Off. Includes Allow Singleplayer, Skip Brief, Skip Intermission, Instant Start, Skip Intro Cutscene and Debug Tools.
- Button that opens the game's built-in dev panel
- Every flag goes back to normal when you unload the mod

### ESP
- Finds the objects in **any** minigame automatically and groups them by type
- Per group: name, distance, 3D box, 2D line, dot, color, max distance and a live value
- Presets for Minefield, Inside Job, Firearm Factory, Stable Footing, Tunnel Hazard, Debris Platforms, Spine Breaker, Lethal Rebound, Forklift Certified, The Filter, Chisel Gauntlet, Table Manners, Wrong Way and Smoke Break
- Live values include mines pinging, gun part variations, platform time left, roomba speed, crates delivered and the choke timer

### Aimbot (Duck Hunt)
- Aim key (Mouse 2) with Hold, Tap and Always On modes
- Target and aim style options, smoothness, FOV circle, min/max distance, skip downed ducks, stick to target, switch delay and deadzone
- Box drawn on the locked target
- Auto fire with random pre-fire and post-fire delays, plus an "only fire inside the hitbox" option

### Duck Hunt extras
- Magazine HUD, so you know when you're out
- Teleport to the marker (J)
- Godmode (duck) : only fully reliable as host
- Infinite ammo and rapidfire (hunter)
- Speed hack with a multiplier (duck)

### Solvers
- **Chisel Gauntlet**: shows or glows only the segments you need to carve
- **Tunnel Hazard**: colors the nooks (green = safe, red = press)
- **Stable Footing**: shows the safe symbol, can hide the tiles that are dropping, fallback symbol on V
- **Inside Job**: highlights the syringe ![HOST](https://img.shields.io/badge/HOST-ff6b6b?style=flat-square), can hide the other containers, fullbright
- **Table Manners**: countdown HUD for when the coach looks. Exact timer as host; as a client, tap L / K when he looks up / away.
- **The Filter**: hold G to auto-sort items (best-effort for now, more accurate in a later update)

### Players
- Player list with Teleport To and Teleport To Me. These use the game's own teleport, so they work on friends without the mod.
- **Shove**: uses each minigame's own shove/hit where it has one, otherwise a short teleport push. Adjustable strength and distance.
- **Freeze**: keeps pulling a player back to the spot where you froze them
- **Smite**: instantly eliminates a player in minigames that have a kill. Greyed out in minigames where the game decides eliminations itself, like Chisel Gauntlet and Smoke Break.
- Freeze everyone else / Unfreeze all / Smite everyone else
- Teleport all players to me (HOME)
- Teleport items & entities to the chosen player (PAGE UP): mines, gun parts, junk, crates, the roomba and more. Objects the host owns only stay moved if you're the host.
- Kick, with an option to block them from rejoining ![HOST](https://img.shields.io/badge/HOST-ff6b6b?style=flat-square)

### Minigames ![HOST](https://img.shields.io/badge/HOST-ff6b6b?style=flat-square)
- Force-start in single player
- Play Now: pick any minigame and number of rounds and load it straight away
- Custom queue: choose exactly what plays next, with rounds for each
- Endless session
- See the default rotation (up next)

### Session ![HOST](https://img.shields.io/badge/HOST-ff6b6b?style=flat-square)
- **Score editor**: + / - / 0 for each player, adjustable step, reset all scores. Everyone sees the new scores.
- **Points multiplier**: x1 to x5 on every point scored from then on
- **Skip round / Skip minigame**: ends it through the game's normal finish, so everyone gets the usual end screen
- **Restart minigame**
- **End after this minigame / End session now**
- **Pick the Duck Hunt hunter**: next round only, or every round

### Bots ![HOST](https://img.shields.io/badge/HOST-ff6b6b?style=flat-square)
- Add named bots to fill the lobby
- Bots stand still. A minigame that waits on every player for something can hang; just remove the bot.

### Misc
- **Noclip**: fly through walls with adjustable speed
- **Freecam** (F6): mouse to look, WASD to fly, Space/E up, Ctrl/C/Q down, Shift faster, Alt slower, mouse wheel for speed. "Follow player" mode orbits any player. Your character is frozen while flying (optional). Only your screen changes.
- **Console** (F8): see the [command list](#console-commands) below
- Teleport loose objects to any player

### Hotkeys / Settings / Info
- Every hotkey can be rebound to a keyboard key or mouse button (right-click a bind to clear it)
- Save / load / reset your config
- FPS, resolution and watermark overlay
- The menu fits itself to your screen. Adjustable scale, drag to move, resize from the corner.
- Freeze your game input while the menu is open
- **Disable all cheats** button and **Unload mod** button
- Info tab shows your version and loaded mods

---

## Setup

1. Get **[MachinePartyModLoader](https://github.com/Krunk-theduck/MachinePartyModLoader)** by Krunk-theduck from GitHub and run **`MachinePartyModLoader.exe`** once. This creates a **`mods`** folder next to **`Machine Party.exe`**.
2. Download and extract the zip from the [Download](#download) section below.
3. Put the **`viper_menu`** folder inside **`mods`**. You should end up with **`mods/viper_menu/mod.json`**.
4. Start the game and press **INSERT**.

> **Updating from an older version:** delete the old `viper_menu` folder first, then drop in the new one.
>
> **After a game update:** run the loader again (that's the loader's rule, not the mod's).

---

## Default hotkeys

| Key | Action |
|---|---|
| **INSERT** | Open / close menu (Esc also closes it) |
| **END** | Unload the mod |
| **PAGE DOWN** | Toggle ESP |
| **HOME** | Teleport all players to you |
| **PAGE UP** | Teleport items & entities to the chosen player |
| **Mouse 2** | Aim key (Duck Hunt) |
| **J** | Teleport to the Duck Hunt marker |
| **G** (hold) | The Filter auto-solve |
| **L / K** | Table Manners: he looked up / looked away |
| **V** | Stable Footing: cycle the fallback symbol |
| **F6** | Freecam |
| **F8** | Console |
| *Unbound by default* | Noclip, shove / freeze / smite the chosen player. Set them in the Hotkeys tab. |

While the menu is open only INSERT and END work, so clicking around doesn't trigger game controls.

---

## Console commands

```
help                      list commands
clear                     clear the console
players                   list players and their ids
mods                      list loaded mods
pos                       your position
tp <x> <y> <z>            teleport yourself
tpto <name>               teleport to a player
bring <name>              teleport a player to you
shove <name>              shove a player
freeze <name>             freeze / unfreeze a player
smite <name>              eliminate a player
freecam                   toggle freecam
score <name> <points>     set a player's score      (host)
skip                      skip the round            (host)
skip game                 skip the whole minigame   (host)
restart                   restart the minigame      (host)
end                       end after this minigame   (host)
end now                   end the session now       (host)
host                      are you host or client
panic                     disable all cheats
unload                    unload the mod
```

Anything else is evaluated as a GDScript expression, e.g. `me.global_position`. Names you can use: `app`, `g`, `game`, `mg`, `me`, `cam`, `tree`.

---

## Host vs client

- 🔴 **Host only:** Minigames tab (queue, play now, force-start, endless), the whole Session tab, kick, bots, the Inside Job syringe highlight, the exact Table Manners timer, keeping host-owned objects where you moved them
- 🟢 **Works for everyone**, even when friends are on the vanilla game: teleports, shove, freeze, smite, ESP, aimbot, solvers, noclip, freecam, speed hack
- **Godmode** is only fully reliable as host

---

## Needs testing - feedback wanted!

These haven't been fully tested in real lobbies yet. If you try them, let me know how it went:

- The Filter auto-solve
- Stable Footing solver
- Table Manners as a client

### Reporting a bug?

[Open an issue](../../issues) and please include:

- Which minigame and what you were doing
- Whether you were host or client
- What you expected vs what happened
- Any **SCRIPT ERROR** lines from `%APPDATA%\Godot\app_userdata\Machine Party\logs\godot.log`

Also useful: `%APPDATA%\Godot\app_userdata\Machine Party\modloader.log` shows what the loader loaded. If one feature fails to load, it shows a red note on its tab and the rest of the menu keeps working.

---

## Known limits

- ESP, aimbot and solver overlays are made for online play. Local couch mode renders split-screen, so they won't line up there.
- A Debug flag shows "n/a" if your game version doesn't have it.
- Freecam only changes your own screen.

---

## Download

- [viper_menu_v0.2.zip](../../releases/latest)

---

## Credits

- **Obsidian420** - Inspiration & a lot of the cheat/solver ideas
- **[Krunk-theduck](https://github.com/Krunk-theduck)** - [MachinePartyModLoader](https://github.com/Krunk-theduck/MachinePartyModLoader)
- **xViperCodes** - Viper Menu

---

<div align="center">

**Leave feedback, suggestions and bug reports in the [Issues](../../issues) tab - every report helps!**

**Future updates will come as well.**

</div>
