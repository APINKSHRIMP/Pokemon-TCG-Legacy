# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pokémon TCG Legacy is a single-player TCG campaign game built in **Godot 4.6** using GDScript — a spiritual successor to the Pokémon TCG GB games. It features ~2,000 collectible cards (Base Set → EX Power Keepers), 100+ CPU opponents, and a full battle engine built from scratch.

## Running the Project

This is a pure Godot project with no build system. Open in **Godot 4.6** and run, or launch an exported executable. There are no CLI build/test commands.

- **Main scene**: `res://Scenes/Intro_And_Animation_Scenes/Game_Start_Load_Splash_Scene.tscn`
- **Project config**: `project.godot`

## Architecture

### Autoload Singletons (Global State)

Four autoloads are always in scope — do not re-declare or shadow them:

| Singleton | Script | Purpose |
|-----------|--------|---------|
| `Game_State` | `Game_State_Script.gd` | Player progression, scene transition coordination |
| `Sound_Manager` | `Sound_Manager_Script.gd` | All SFX and BGM playback |
| `Game_Data_Manager` | `Game_Data_Manager_Script.gd` | Opponent/player data loading |
| `MapManager` | `MapManager.gd` | Overworld scene transitions |

### Battle Engine

The battle system spans several large scripts in `Scripts/Match_Scripts/`:

- **`Main_Match_Core_Gameplay_Script.gd`** (~4,800 lines) — Central turn loop, card selection, energy attachment, evolution, retreat, and status effects. This is the single most complex file in the project.
- **`CPU_AI.gd`** (~3,400 lines) — AI decision-making for all opponent actions each turn.
- **`Attack_Effects.gd`** — Damage calculation and per-attack effect resolution.
- **`Powers_And_Bodies_Effects.gd`** — Pokémon Power and Poké-Body effect logic.
- **`Trainer_Effects.gd`** — Trainer card effect resolution.
- **`Special_Energy_Effects.gd`** — Special energy card mechanics.
- **`Match_Start_Intro_Script.gd`** / **`Match_End_Outro_Script.gd`** — UI sequencing for battle start/end.

When modifying battle logic, the effect scripts delegate back into `Main_Match_Core_Gameplay_Script.gd` — changes to shared state must be consistent across all of them.

### Data Formats

**Card data** lives in `Card_Set_Data/` as JSON files (`base1.json`, `ex5.json`, etc.), one per set. Each card object contains attacks, abilities, weakness, retreat cost, and HP. Card IDs use the format `{set_prefix}-{number}` (e.g., `"base1-1"`, `"ex5-102"`).

**Opponent data** lives in `NPC_and_Opponent_Data/` — 29 opponent deck JSON files and ~10 NPC/time-of-day JSON files that control which opponents appear in the overworld and when.

### Save System

Player data is split across two locations:

- **`res://Player_Data/`** — Bundled defaults (starter decks, initial owned cards). These are copied to `user://` on first run and never written back.
- **`user://`** (Godot user data directory) — All runtime saves: `Player_Game_Progress.json` (opponents beaten, packs unlocked, coins, gifts), `Player_Current_Data.json` (sprite, energy style, shop state), `Player_Owned_Cards/` (per-set inventory), `Player_Decks/` (saved decks).

Always read/write player progress through `Game_State` rather than directly accessing these files.

### Overworld & Scenes

The primary overworld scene is `Celeste_Harbour.gd`. Interior locations (`Player_House_Downstairs.gd`, `Player_House_Upstairs.gd`, `Card_Mart.gd`) are separate scenes loaded by `MapManager`. Non-battle UI scenes (deck builder, pack opening, coin case, trainer card) live in `Scripts/Menu_Scripts/`.

### Key Data Classes

- **`card_object`** — Card instance with runtime state: current HP, attached energies, status conditions, effect tracking flags.
- **`Opponent_Object`** — CPU opponent definition loaded from JSON.
- **`Player_Object`** — Overworld player character (extends `CharacterBody2D`).
