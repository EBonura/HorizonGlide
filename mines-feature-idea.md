# Mines Feature - Design Notes

## Core Concept
Add **mines** as a defensive/tactical weapon that both player and enemies can deploy, creating a chase-and-evade dynamic.

## Gameplay Mechanics

### Mines System
- **Player mines**: Drop behind ship when fleeing from enemies (❍ button?)
- **Enemy mines**: Dropped by enemies during combat, player must avoid
- Creates strategic depth: risk/reward when chasing enemies
- Adds evasion gameplay when being pursued

### Ammo Management
- New ammo type: **mine count** (separate from bullets)
- Displayed in bottom HUD alongside health/bullet ammo

## Recycled Bomb Event → Mine Supply Event

### Original Bomb Event (from older versions)
- Bombs drop from above onto the terrain
- Player had to avoid getting hit

### New Purpose: Mine Resupply
- **Event type #3**: "Bomb Drop" event
- Bombs fall from sky at random locations
- When bombs hit ground, they leave **mine ammo pickups**
- Player collects these to stock up on mines
- Adds 3rd event type to rotation (combat, circles, bombs)

## Implementation Challenges
- **Token budget is TIGHT** - this will require heavy optimization
- Need to add:
  - Mine dropping logic (player + enemy)
  - Mine collision detection
  - Mine ammo counter + HUD display
  - Bomb event with falling projectiles
  - Mine pickup spawning from bombs
  - Visual sprites for mines/bombs

## Benefits
- More engaging combat (not just forward shooting)
- Strategic depth (when to use mines vs bullets)
- Better pacing (3 event types instead of 2)
- Reuses discarded bomb event content

## Next Steps
1. Find old bomb event code in previous versions
2. Calculate token cost for full feature
3. Identify optimization opportunities across codebase
4. Implement mine system first, then bomb event
