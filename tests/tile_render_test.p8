pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- tile rendering test
-- static scene to benchmark different rendering approaches

-- config (from main game)
view_range=7
half_tile_width=12
half_tile_height=6
block_h=2
cam_offset_x=64
cam_offset_y=64

function iso(x,y) return cam_offset_x+(x-y)*half_tile_width, cam_offset_y+(x+y)*half_tile_height end

-- perlin noise (from main game)
function generate_permutation(seed)
    srand(seed)
    local p={}
    for i=0,255 do p[i]=i end
    for i=255,1,-1 do
        local j=flr(rnd(i+1))
        p[i],p[j]=p[j],p[i]
    end
    for i=0,255 do p[256+i]=p[i] end
    return p
end

function fade(t) return t*t*t*(t*(t*6-15)+10) end
function lerp(t,a,b) return a+t*(b-a) end

function grad(hash,x,y)
    local h=hash&15
    local u=(h<8) and x or y
    local v=(h<4) and y or ((h==12 or h==14) and x or 0)
    return (((h&1)==0) and u or -u)+(((h&2)==0) and v or -v)
end

function perlin2d(x,y,p)
    local xi,yi=flr(x)&255,flr(y)&255
    x,y=x-flr(x),y-flr(y)
    local u,v=fade(x),fade(y)
    local aa,ab=p[p[xi]+yi],p[p[xi]+yi+1]
    local ba,bb=p[p[xi+1]+yi],p[p[xi+1]+yi+1]
    return lerp(v,lerp(u,grad(aa,x,y),grad(ba,x-1,y)),lerp(u,grad(ab,x,y-1),grad(bb,x-1,y-1)))
end

-- terrain color lookup tables (from main game)
TERRAIN_PAL_STR = "\1\0\0\12\1\1\15\4\2\3\1\0\11\3\1\4\2\0\6\5\0\7\6\5"
TERRAIN_THRESH = split"-2,0,2,6,12,18,24,99"

terrain_perm=generate_permutation(1337)
cell_cache={}
scale=12
water_level=0

function terrain(x,y)
    x,y=flr(x),flr(y)
    local key=x..","..y
    local c=cell_cache[key]
    if c then return unpack(c) end

    local nx,ny=x/scale,y/scale
    local cont=perlin2d(nx*.03,ny*.03,terrain_perm)*15
    local hdetail=(perlin2d(nx,ny,terrain_perm)+perlin2d(nx*2,ny*2,terrain_perm)*.5+perlin2d(nx*4,ny*4,terrain_perm)*.25)*(15/1.75)
    local rid=abs(perlin2d(nx*.5,ny*.5,terrain_perm))^1.5
    local mountain=rid*max(0,cont/15+.5)*30
    local h=flr(mid(cont+hdetail+mountain-water_level,-4,28))

    local i=1
    while h>TERRAIN_THRESH[i] do i+=1 end
    local p=(i-1)*3+1
    cell_cache[key]={ord(TERRAIN_PAL_STR,p),ord(TERRAIN_PAL_STR,p+1),ord(TERRAIN_PAL_STR,p+2),h}
    return unpack(cell_cache[key])
end

function terrain_h(x,y)
    local _,_,_,h=terrain(x,y)
    return h
end

-- approach 1: baseline (optimized from working v2)
function diamond_v1(sx,sy,c)
    local w=half_tile_width
    line(sx-w,sy,sx+w,sy,c)
    for r=1,half_tile_height do
        w-=2
        line(sx-w,sy-r,sx+w,sy-r,c)
        line(sx-w,sy+r,sx+w,sy+r,c)
    end
end

function draw_tile_v1(x,y,top,side,dark,h)
    local bsx,bsy=(x-y)*half_tile_width,(x+y)*half_tile_height
    local sx,sy=cam_offset_x+bsx,cam_offset_y+bsy

    if h<=0 then
        diamond_v1(sx,sy,top)
        line(sx-half_tile_width,sy,sx+half_tile_width,sy,(h<=-2) and 12 or 1)
        return
    end

    local hp=h*block_h
    local sy2=sy-hp
    local by=bsy+half_tile_height-hp
    local hs,he=terrain_h(x,y+1),terrain_h(x+1,y)
    local cy=cam_offset_y+by

    if hs<h then
        local lb=sx-half_tile_width
        for i=0,hp do
            line(lb,sy2+i,sx,cy+i,side)
        end
    end
    if he<h then
        local rb=sx+half_tile_width
        for i=0,hp do
            line(rb,sy2+i,sx,cy+i,dark)
        end
    end
    diamond_v1(sx,sy2,top)
end

function draw_world_v1()
    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local top,side,dark,h=terrain(x,y)
            if h<=0 then draw_tile_v1(x,y,top,side,dark,h) end
        end
    end

    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local top,side,dark,h=terrain(x,y)
            if h>0 then draw_tile_v1(x,y,top,side,dark,h) end
        end
    end
end

-- approach 2: cache neighbor heights to reduce terrain_h calls
function diamond_v2(sx,sy,c)
    local w=half_tile_width
    line(sx-w,sy,sx+w,sy,c)
    for r=1,half_tile_height do
        w-=2
        line(sx-w,sy-r,sx+w,sy-r,c)
        line(sx-w,sy+r,sx+w,sy+r,c)
    end
end

function draw_tile_v2(x,y,top,side,dark,h,hs,he)
    local bsx,bsy=(x-y)*half_tile_width,(x+y)*half_tile_height
    local sx,sy=cam_offset_x+bsx,cam_offset_y+bsy

    if h<=0 then
        diamond_v2(sx,sy,top)
        line(sx-half_tile_width,sy,sx+half_tile_width,sy,(h<=-2) and 12 or 1)
        return
    end

    local hp=h*block_h
    local sy2=sy-hp
    local by=bsy+half_tile_height-hp
    local cy=cam_offset_y+by

    if hs<h then
        local lb=sx-half_tile_width
        for i=0,hp do
            line(lb,sy2+i,sx,cy+i,side)
        end
    end
    if he<h then
        local rb=sx+half_tile_width
        for i=0,hp do
            line(rb,sy2+i,sx,cy+i,dark)
        end
    end
    diamond_v2(sx,sy2,top)
end

function draw_world_v2()
    -- pre-fetch all terrain data to reduce cache lookups
    local tiles={}
    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local top,side,dark,h=terrain(x,y)
            tiles[x..","..y]={top,side,dark,h}
        end
    end

    -- draw water
    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local t=tiles[x..","..y]
            if t[4]<=0 then
                draw_tile_v2(x,y,t[1],t[2],t[3],t[4])
            end
        end
    end

    -- draw land with pre-fetched neighbor heights
    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local t=tiles[x..","..y]
            if t[4]>0 then
                local ts=tiles[x..","..(y+1)]
                local te=tiles[(x+1)..","..y]
                local hs=ts and ts[4] or 0
                local he=te and te[4] or 0
                draw_tile_v2(x,y,t[1],t[2],t[3],t[4],hs,he)
            end
        end
    end
end

-- approach 3: single-pass with inline drawing
function draw_world_v3()
    -- collect all tiles in single pass
    local tiles={}
    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local top,side,dark,h=terrain(x,y)
            tiles[x..","..y]={top,side,dark,h}
        end
    end

    -- single combined pass: water then land
    local htw,hth,co_x,co_y,bh=half_tile_width,half_tile_height,cam_offset_x,cam_offset_y,block_h

    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local t=tiles[x..","..y]
            local h=t[4]

            if h<=0 then
                -- inline water drawing
                local bsx,bsy=(x-y)*htw,(x+y)*hth
                local sx,sy=co_x+bsx,co_y+bsy
                diamond_v2(sx,sy,t[1])
                line(sx-htw,sy,sx+htw,sy,(h<=-2) and 12 or 1)
            end
        end
    end

    for x=-view_range,view_range do
        for y=-view_range,view_range do
            local t=tiles[x..","..y]
            local h=t[4]

            if h>0 then
                -- inline land drawing with cached neighbors
                local bsx,bsy=(x-y)*htw,(x+y)*hth
                local sx,sy=co_x+bsx,co_y+bsy
                local hp=h*bh
                local sy2=sy-hp
                local cy=co_y+bsy+hth-hp

                local ts=tiles[x..","..(y+1)]
                local te=tiles[(x+1)..","..y]
                local hs=ts and ts[4] or 0
                local he=te and te[4] or 0

                if hs<h then
                    local lb=sx-htw
                    for i=0,hp do line(lb,sy2+i,sx,cy+i,t[2]) end
                end
                if he<h then
                    local rb=sx+htw
                    for i=0,hp do line(rb,sy2+i,sx,cy+i,t[3]) end
                end
                diamond_v2(sx,sy2,t[1])
            end
        end
    end
end

-- approach 4: numeric array + hardcoded constants
function draw_world_v4()
    -- numeric array - faster than string-keyed table
    local tiles={}
    local idx=1
    for x=-7,7 do
        for y=-7,7 do
            local top,side,dark,h=terrain(x,y)
            tiles[idx]=top
            tiles[idx+1]=side
            tiles[idx+2]=dark
            tiles[idx+3]=h
            tiles[idx+4]=x
            tiles[idx+5]=y
            idx+=6
        end
    end

    -- draw water (idx=top, idx+1=side, idx+2=dark, idx+3=h, idx+4=x, idx+5=y)
    idx=1
    for i=1,225 do
        local h=tiles[idx+3]
        if h<=0 then
            local x,y=tiles[idx+4],tiles[idx+5]
            local bsx,bsy=(x-y)*12,(x+y)*6
            local sx,sy=64+bsx,64+bsy
            diamond_v2(sx,sy,tiles[idx])
            line(sx-12,sy,sx+12,sy,(h<=-2) and 12 or 1)
        end
        idx+=6
    end

    -- draw land
    idx=1
    for i=1,225 do
        local h=tiles[idx+3]
        if h>0 then
            local x,y=tiles[idx+4],tiles[idx+5]
            local bsx,bsy=(x-y)*12,(x+y)*6
            local sx,sy=64+bsx,64+bsy
            local hp=h*2
            local sy2=sy-hp
            local cy=70+bsy-hp

            -- neighbor heights via index math (15 tiles per row)
            local hs=(y<7 and tiles[idx+93] or 0)  -- idx + 15*6 + 3
            local he=(x<7 and tiles[idx+9] or 0)   -- idx + 6 + 3

            if hs<h then
                local lb=sx-12
                for j=0,hp do line(lb,sy2+j,sx,cy+j,tiles[idx+1]) end
            end
            if he<h then
                local rb=sx+12
                for j=0,hp do line(rb,sy2+j,sx,cy+j,tiles[idx+2]) end
            end
            diamond_v2(sx,sy2,tiles[idx])
        end
        idx+=6
    end
end

-- approach 5: eliminate table lookups by storing pre-calculated screen coords
function draw_world_v5()
    -- pre-calculate everything including screen coordinates
    local tiles={}
    local idx=1
    local htw,hth,co_x,co_y,bh=12,6,64,64,2

    for x=-7,7 do
        for y=-7,7 do
            local top,side,dark,h=terrain(x,y)
            local bsx,bsy=(x-y)*htw,(x+y)*hth
            tiles[idx]={top,side,dark,h,co_x+bsx,co_y+bsy,x,y}
            idx+=1
        end
    end

    -- draw water - no iso calculation
    for i=1,225 do
        local t=tiles[i]
        if t[4]<=0 then
            diamond_v2(t[5],t[6],t[1])
            line(t[5]-12,t[6],t[5]+12,t[6],(t[4]<=-2) and 12 or 1)
        end
    end

    -- draw land - pre-calculated coords
    for i=1,225 do
        local t=tiles[i]
        if t[4]>0 then
            local sx,sy,h=t[5],t[6],t[4]
            local hp=h*2
            local sy2=sy-hp
            local cy=70+t[6]-64-hp

            -- neighbor lookup
            local x,y=t[7],t[8]
            local hs,he=0,0
            for j=1,225 do
                local nt=tiles[j]
                if nt[7]==x and nt[8]==y+1 then hs=nt[4] end
                if nt[7]==x+1 and nt[8]==y then he=nt[4] end
            end

            if hs<h then
                local lb=sx-12
                for k=0,hp do line(lb,sy2+k,sx,cy+k,t[2]) end
            end
            if he<h then
                local rb=sx+12
                for k=0,hp do line(rb,sy2+k,sx,cy+k,t[3]) end
            end
            diamond_v2(sx,sy2,t[1])
        end
    end
end

-- approach 6: unroll diamond completely inline
function draw_world_v6()
    local tiles={}
    for x=-7,7 do
        for y=-7,7 do
            local top,side,dark,h=terrain(x,y)
            tiles[x..","..y]={top,side,dark,h}
        end
    end

    local htw,hth,co_x,co_y,bh=12,6,64,64,2

    -- draw water with fully inlined diamond
    for x=-7,7 do
        for y=-7,7 do
            local t=tiles[x..","..y]
            local h=t[4]
            if h<=0 then
                local bsx,bsy=(x-y)*htw,(x+y)*hth
                local sx,sy=co_x+bsx,co_y+bsy
                -- inline diamond
                line(sx-12,sy,sx+12,sy,t[1])
                line(sx-10,sy-1,sx+10,sy-1,t[1])
                line(sx-10,sy+1,sx+10,sy+1,t[1])
                line(sx-8,sy-2,sx+8,sy-2,t[1])
                line(sx-8,sy+2,sx+8,sy+2,t[1])
                line(sx-6,sy-3,sx+6,sy-3,t[1])
                line(sx-6,sy+3,sx+6,sy+3,t[1])
                line(sx-4,sy-4,sx+4,sy-4,t[1])
                line(sx-4,sy+4,sx+4,sy+4,t[1])
                line(sx-2,sy-5,sx+2,sy-5,t[1])
                line(sx-2,sy+5,sx+2,sy+5,t[1])
                line(sx,sy-6,sx,sy-6,t[1])
                line(sx,sy+6,sx,sy+6,t[1])
                line(sx-htw,sy,sx+htw,sy,(h<=-2) and 12 or 1)
            end
        end
    end

    -- draw land with inline diamond
    for x=-7,7 do
        for y=-7,7 do
            local t=tiles[x..","..y]
            local h=t[4]
            if h>0 then
                local bsx,bsy=(x-y)*htw,(x+y)*hth
                local sx,sy=co_x+bsx,co_y+bsy
                local hp=h*bh
                local sy2=sy-hp
                local cy=co_y+bsy+hth-hp

                local ts=tiles[x..","..(y+1)]
                local te=tiles[(x+1)..","..y]
                local hs=ts and ts[4] or 0
                local he=te and te[4] or 0

                if hs<h then
                    local lb=sx-htw
                    for i=0,hp do line(lb,sy2+i,sx,cy+i,t[2]) end
                end
                if he<h then
                    local rb=sx+htw
                    for i=0,hp do line(rb,sy2+i,sx,cy+i,t[3]) end
                end
                -- inline diamond
                line(sx-12,sy2,sx+12,sy2,t[1])
                line(sx-10,sy2-1,sx+10,sy2-1,t[1])
                line(sx-10,sy2+1,sx+10,sy2+1,t[1])
                line(sx-8,sy2-2,sx+8,sy2-2,t[1])
                line(sx-8,sy2+2,sx+8,sy2+2,t[1])
                line(sx-6,sy2-3,sx+6,sy2-3,t[1])
                line(sx-6,sy2+3,sx+6,sy2+3,t[1])
                line(sx-4,sy2-4,sx+4,sy2-4,t[1])
                line(sx-4,sy2+4,sx+4,sy2+4,t[1])
                line(sx-2,sy2-5,sx+2,sy2-5,t[1])
                line(sx-2,sy2+5,sx+2,sy2+5,t[1])
                line(sx,sy2-6,sx,sy2-6,t[1])
                line(sx,sy2+6,sx,sy2+6,t[1])
            end
        end
    end
end

-- approach 7: reduce string concatenation overhead
function draw_world_v7()
    -- use 2d array instead of string keys
    local tiles={}
    for x=-7,7 do
        tiles[x]={}
        for y=-7,7 do
            local top,side,dark,h=terrain(x,y)
            tiles[x][y]={top,side,dark,h}
        end
    end

    local htw,hth,co_x,co_y,bh=12,6,64,64,2

    -- draw water
    for x=-7,7 do
        for y=-7,7 do
            local t=tiles[x][y]
            if t[4]<=0 then
                local bsx,bsy=(x-y)*htw,(x+y)*hth
                local sx,sy=co_x+bsx,co_y+bsy
                diamond_v2(sx,sy,t[1])
                line(sx-htw,sy,sx+htw,sy,(t[4]<=-2) and 12 or 1)
            end
        end
    end

    -- draw land
    for x=-7,7 do
        for y=-7,7 do
            local t=tiles[x][y]
            if t[4]>0 then
                local bsx,bsy=(x-y)*htw,(x+y)*hth
                local sx,sy=co_x+bsx,co_y+bsy
                local h=t[4]
                local hp=h*bh
                local sy2=sy-hp
                local cy=co_y+bsy+hth-hp

                local hs=(y<7 and tiles[x][y+1]) and tiles[x][y+1][4] or 0
                local he=(x<7 and tiles[x+1]) and tiles[x+1][y][4] or 0

                if hs<h then
                    local lb=sx-htw
                    for i=0,hp do line(lb,sy2+i,sx,cy+i,t[2]) end
                end
                if he<h then
                    local rb=sx+htw
                    for i=0,hp do line(rb,sy2+i,sx,cy+i,t[3]) end
                end
                diamond_v2(sx,sy2,t[1])
            end
        end
    end
end

-- approach 8: 2d array + eliminate redundant calculations
function draw_world_v8()
    local tiles={}
    for x=-7,7 do
        tiles[x]={}
        for y=-7,7 do
            local top,side,dark,h=terrain(x,y)
            tiles[x][y]={top,side,dark,h}
        end
    end

    -- draw water
    for x=-7,7 do
        for y=-7,7 do
            local t=tiles[x][y]
            if t[4]<=0 then
                local sx,sy=64+(x-y)*12,64+(x+y)*6
                diamond_v2(sx,sy,t[1])
                line(sx-12,sy,sx+12,sy,(t[4]<=-2) and 12 or 1)
            end
        end
    end

    -- draw land - pre-calc more values
    for x=-7,7 do
        local tx=tiles[x]
        local tnx=tiles[x+1]
        for y=-7,7 do
            local t=tx[y]
            if t[4]>0 then
                local h=t[4]
                local sx,sy=64+(x-y)*12,64+(x+y)*6
                local hp=h*2
                local sy2=sy-hp
                local cy=64+(x+y)*6+6-hp

                local hs=(y<7 and tx[y+1]) and tx[y+1][4] or 0
                local he=(tnx and tnx[y]) and tnx[y][4] or 0

                if hs<h then
                    local lb=sx-12
                    for i=0,hp do line(lb,sy2+i,sx,cy+i,t[2]) end
                end
                if he<h then
                    local rb=sx+12
                    for i=0,hp do line(rb,sy2+i,sx,cy+i,t[3]) end
                end
                diamond_v2(sx,sy2,t[1])
            end
        end
    end
end

-- test setup
current_approach=1
approaches={"v1: 0.3692","v2: 0.3295","v3: 0.3066","v7: 0.303","v8: precalc2"}

function _init()
    -- pre-warm cache
    for x=-view_range,view_range do
        for y=-view_range,view_range do
            terrain(x,y)
        end
    end
end

function _update()
    -- switch approaches with arrow keys
    if btnp(0) then current_approach=max(1,current_approach-1) end
    if btnp(1) then current_approach=min(5,current_approach+1) end
end

function _draw()
    cls(1)

    -- draw scene
    if current_approach==1 then
        draw_world_v1()
    elseif current_approach==2 then
        draw_world_v2()
    elseif current_approach==3 then
        draw_world_v3()
    elseif current_approach==4 then
        draw_world_v7()
    else
        draw_world_v8()
    end

    -- stats
    local cpu=stat(1)
    local fps=stat(7)
    print("approach: "..approaches[current_approach],1,1,7)
    print("cpu: "..tostr(cpu),1,7,7)
    print("fps: "..tostr(fps),1,13,7)
    print("\x8e\x91 switch approach",1,120,6)
end
