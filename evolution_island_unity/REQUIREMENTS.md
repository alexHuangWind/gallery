# Darwin Evolution Island — Product Requirements (PRD)

> Version: v1.0 ｜ Platform: Unity 3D ｜ Genre: Single-player / top-down / survival-and-evolve

> 中文版见 [`需求文档.md`](需求文档.md)。

---

## 1. Overview

A single-player 3D top-down survival game. The player wakes on a monster-filled
island, **automatically attacks** nearby enemies, and uses the kills to gain
experience and **evolve** into ever stronger forms. The goal is to survive as
long as possible and evolve as far as possible. Core fun: dead-simple controls
(just movement), a tight "get stronger" loop, and visible form upgrades.

Reference feel: Darwin Evolution Island / Archero-style casual action —
move, auto-attack, grow.

---

## 2. Goals & Non-goals

**Goals**
- Controls simple enough that the player only steers movement; combat is automatic.
- A satisfying combat loop: kill → XP → level/evolve → stronger → tougher enemies.
- Differentiated enemies: at least melee and ranged animal behaviours.
- 3D presentation for player, enemies and world.

**Non-goals (not in v1)**
- Multiplayer / networking.
- Complex story, dialogue, quests.
- Complex economy / shop / IAP.

---

## 3. Platform & Tech

- Engine: Unity (2021 LTS or newer recommended).
- View: 3D top-down / 3-4 angled, camera follows the player.
- Input: keyboard (arrows / WASD); later extensible to gamepad and mobile joystick.
- Render pipeline: Built-in or URP.
- Art: v1 uses procedural primitive-built models (no external assets); can be
  replaced with proper art models later.

---

## 4. Core Gameplay Loop

```
enter island → reposition / dodge → auto-attack nearest enemy → kill for XP
   → level up / evolve (stronger, new form) → face tougher enemies → ...
   → death → restart
```

---

## 5. Controls

| Action | Input | Notes |
| --- | --- | --- |
| Move | Arrows or W A S D | Up/down/left/right, free movement on the island |
| Attack | None (automatic) | System auto-targets and attacks the nearest enemy in range |
| Restart | R / button | Instantly restart after death |

- Requirement: controls as simple as possible — pick up and play, no learning curve.
- Movement must be confined to the island (no walking into the sea / off the map).

---

## 6. Player

- Attributes: HP, move speed, attack power, attack range, attack interval (cooldown).
- **Auto-attack**: every "attack interval", auto-select the **nearest** enemy in
  range and attack it (v1 uses a ranged projectile).
- Taking damage: enemy contact or projectile hits reduce HP; a brief invulnerability
  window prevents instant multi-hits.
- Death: HP reaching zero triggers Game Over.
- Facing: faces movement / attack direction.
- Feedback: hit flash, attack motion, slight bob while moving.

---

## 7. Enemies (key: two attack styles)

Common: enemies have HP, move speed, attack power, attack interval, XP reward;
show a health bar overhead; have a kill feedback effect.

### 7.1 Melee animal (e.g. boar)
- Behaviour: once it notices the player, it **keeps charging toward the player**.
- Attack: within contact range, deals contact damage on its cooldown.
- Role: high threat; forces the player to keep kiting away.

### 7.2 Ranged animal (e.g. spitter-toad)
- Behaviour: holds a "preferred distance" — approaches if too far, retreats if too
  close (kites the player).
- Attack: within firing range, **fires projectiles** on its cooldown; projectile
  hits reduce HP.
- Role: forces the player to dodge bullets while also avoiding melee.

### 7.3 Spawning rules
- Continuously spawn enemies outside a radius around the player, within the island.
- Cap the number of concurrent enemies on screen; raise the cap with player level.
- Scale enemy strength (HP / attack) with player level to stay challenging.
- Mix melee / ranged at a set ratio.

---

## 8. Progression & Evolution

- **XP & levels**: kills grant XP; reaching a threshold levels up; level-ups raise
  stats (e.g. attack, max HP) and heal.
- **Evolution**: at certain levels, evolve into a new form —
  - Clearly different appearance (size / shape upgrade).
  - Large stat boost (HP, attack, possibly upgraded attack style).
  - On evolving, fully heal plus brief invulnerability and a visual effect.
- Evolution chain (suggested, tunable):
  `Slime → Lizard → Shadow Wolf → Rock Beast → Flame Wyvern → Ancient Dragon`
  (melee forms may unlock stronger ranged attacks at higher tiers.)

---

## 9. World

- A circular island surrounded by sea, with grassland on top.
- Scenery (trees, rocks) scattered to enrich the 3D look and depth.
- Both player and enemies confined to the walkable island area.

---

## 10. UI / HUD

- Top / corner: current level, kill count, HP bar, XP bar, current form name.
- Above enemies: health bar shown after taking damage.
- Combat floating text: damage numbers, XP gained, level-up / evolution prompts.
- Start screen: title + how-to-play + "Start".
- End screen: run stats (evolution stage / level / kills) + "Play again".

---

## 11. Audio (can be deferred)

- Basic SFX placeholders: attack / hit / kill / take-damage / level-up / evolve / death.
- Looping background music.

---

## 12. State Machine

```
Start screen → In game → Game over → (restart) → In game
```

---

## 13. Acceptance Criteria (definition of done for v1)

1. Pressing Play in the Unity editor enters the game and runs smoothly.
2. Arrows / WASD move the character on the island and cannot leave it.
3. The player auto-attacks and can kill the nearest enemy.
4. Both **melee** and **ranged** enemies exist simultaneously, behaving per 7.1 / 7.2.
5. Kills grant XP and level-ups, and at least one **evolution** triggers
   (appearance + stat change).
6. HP reaching zero shows the end screen; one-click restart works.
7. Player, enemies and world are all rendered in 3D.

---

## 14. Roadmap (not required for v1)

- More animal species, elites, stage bosses.
- Skill / equipment / talent build systems.
- Drops and pickups (XP orbs, items).
- Polished hit / kill / evolution VFX and SFX.
- Replace procedural models with proper art models and animation.
- Mobile support (virtual joystick), gamepad support.
- High-score / best-evolution-stage save data.

---

## Appendix: Current code status (reference)

- Repo `alexHuangWind/gallery`, branch `claude/monster-evolution-game-8sa829`.
- Unity scripts: `evolution_island_unity/Assets/EvolutionIsland3D/Scripts/`
  (`GameBootstrap` / `GameManager` / `PlayerController` / `Enemy` / `Projectile` / `CreatureBuilder`).
- Status: offline-compile verified; the gameplay skeleton (movement, auto-attack,
  melee + ranged enemies, spawning, leveling, HUD, restart) is implemented; the
  **evolution chain is still a simplified version, pending in-editor playtest and polish.**
