# Terrain Scroll Buffer (removed from v0.22)

Removed to free ~53 tokens for dynamic zoom system. Can be re-added if token budget allows.

## How it worked

Buffer terrain (water + rings + land) to map/GP memory when camera pixel position hasn't changed. Skip expensive tile loops on stationary frames while always redrawing particles, ship, and HUD.

**Benchmark:** ~73% CPU savings for scroll-only frames (from `tests/scrollbuf_test.p8`).

## Memory layout

- Screen: `0x6000–0x7FFF` (8192 bytes)
- Buffer low: `0x2000–0x2FFF` (map RAM, unused by game — no mget/mset)
- Buffer high: `0x4300–0x52FF` (general purpose memory)
- Save: `memcpy(0x2000,0x6000,0x1000)` + `memcpy(0x4300,0x7000,0x1000)`
- Restore: reverse the addresses

## Code changes (3 locations)

### 1. draw_game() — buffer check before rendering

```lua
function draw_game()
    local ncx,ncy=flr(cam_offset_x),flr(cam_offset_y)
    if ncx==buf_cx and ncy==buf_cy then
        memcpy(0x6000,0x2000,0x1000)
        memcpy(0x7000,0x4300,0x1000)
        buf_ok=true
    else
        cls(1) buf_ok=false
        buf_cx,buf_cy=ncx,ncy
    end
    draw_world()
    -- ... rest of draw_game unchanged
```

### 2. draw_world() — wrap terrain in buf_ok guard + save

```lua
function draw_world()
    -- ... locals ...

    if not buf_ok then
    -- draw water
    -- ... water loop ...

    -- water rings
    -- ... rings loop ...

    -- draw land
    -- ... land loop ...

    memcpy(0x2000,0x6000,0x1000)
    memcpy(0x4300,0x7000,0x1000)
    end

    -- fx + ship (always drawn)
    ptl_draw()
    for c in all(cols) do col_draw(c) end
    if not ps.dead then ship_draw(ps) end
end
```

### 3. enter_death() — reset buf_ok on state transition

```lua
death_phase,death_closed_at,buf_ok=0,nil,false
```

## Caveats if re-adding with dynamic zoom

The buffer doesn't track zoom state — if htw/hth/bh change between frames, the
buffer contains wrong-scale terrain. Would need to also check `flr(half_tile_width)`
hasn't changed, or invalidate on zoom lerp.
