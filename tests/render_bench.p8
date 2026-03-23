pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- render benchmark
-- auto-runs each renderer at
-- each zoom, printh results

-- zoom presets: {htw,hth,bh,vr,label}
zooms={
    {4,  2, 1, 20, "4x2 far"},
    {8,  4, 1, 10, "8x4 mid"},
    {12, 6, 2, 8,  "12x6 game"},
    {16, 8, 3, 6,  "16x8 close"},
    {24,12, 4, 4,  "24x12 macro"},
}

half_tile_width=12
half_tile_height=6
block_h=2
view_range=8
cell_cache={}
cam_wx=0
cam_wy=0

-----------------------------
-- terrain gen
-----------------------------
function gen_tile(x,y)
    local h=flr(12*(
        sin(x/5+y/7)*0.5+0.5)*(
        cos(x/3-y/4)*0.4+0.6))
    h=mid(-2,h,20)
    if h<=0 then
        return {1,1,1,h}
    elseif h<3 then
        return {3,0,0,h}
    elseif h<8 then
        return {11,3,3,h}
    elseif h<15 then
        return {4,2,2,h}
    else
        return {6,5,5,h}
    end
end

function ensure_cached(x,y)
    if not cell_cache[x] then
        cell_cache[x]={}
    end
    if not cell_cache[x][y] then
        cell_cache[x][y]=gen_tile(x,y)
    end
end

function set_zoom(zi)
    local z=zooms[zi]
    half_tile_width=z[1]
    half_tile_height=z[2]
    block_h=z[3]
    view_range=z[4]
end

function cache_around()
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    for x=wcx-vr-1,wcx+vr+1 do
        for y=wcy-vr-1,wcy+vr+1 do
            ensure_cached(x,y)
        end
    end
end

-----------------------------
-- 1: baseline (line-based)
-- original from perf_test_zoom
-----------------------------
function draw_1_lines()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    cache_around()
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw
                    and sy>-hth and sy<128+hth then
                        local c=t[1]
                        local w=htw
                        line(sx-w,sy,sx+w,sy,c)
                        for r=1,ihth do
                            w-=dstep
                            line(sx-w,sy-r,sx+w,sy-r,c)
                            line(sx-w,sy+r,sx+w,sy+r,c)
                        end
                    end
                end
            end
        end
    end
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw
                        and sy+hth>0
                        and sy2-hth<128 then
                            local cy=sy+ihth-hp
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                for i=0,hp+1 do
                                    line(lb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                for i=0,hp+1 do
                                    line(rb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            local c=t[1]
                            local w=htw
                            line(sx-w,sy2,sx+w,sy2,c)
                            for r=1,ihth do
                                w-=dstep
                                line(sx-w,sy2-r,
                                     sx+w,sy2-r,c)
                                line(sx-w,sy2+r,
                                     sx+w,sy2+r,c)
                            end
                        end
                    end
                end
            end
        end
    end
end

-----------------------------
-- 2: inlined (baseline winner)
-- same as 1, kept for reference
-- (identical code)
-----------------------------
-- (draw_1 is already inlined,
--  so 2 = same. keeping both
--  labels to match old results)

-----------------------------
-- 3: rectfill sides
-- side faces as: rectfill body
-- + small edge triangles
--
-- left face parallelogram:
--   A(lb,sy2) -> B(sx,sy2+hth)
--   D(lb,sy2+hp+1)->C(sx,sy2+hth+hp+1)
-- AD is vertical left, BC vertical right
-- AB top diagonal, DC bottom diagonal
--
-- scanlines:
-- [sy2,sy2+hth): left=lb,
--   right=lerp along AB
-- [sy2+hth,sy2+hp]: full rect
--   lb to sx
-- (sy2+hp,sy2+hth+hp+1]:
--   left=lerp along DC, right=sx
-----------------------------
function draw_3_rectsides()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    cache_around()

    -- water
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw
                    and sy>-hth and sy<128+hth then
                        local c=t[1]
                        local w=htw
                        line(sx-w,sy,sx+w,sy,c)
                        for r=1,ihth do
                            w-=dstep
                            line(sx-w,sy-r,sx+w,sy-r,c)
                            line(sx-w,sy+r,sx+w,sy+r,c)
                        end
                    end
                end
            end
        end
    end

    -- land
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw
                        and sy+hth>0
                        and sy2-hth<128 then
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0

                            -- left side face
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                local xstep=(sx-lb)/ihth
                                -- top triangle
                                local rx=lb
                                for i=0,ihth-1 do
                                    rx+=xstep
                                    line(lb,sy2+i,
                                         rx,sy2+i,c)
                                end
                                -- middle rect
                                if hp>=ihth then
                                    rectfill(lb,sy2+ihth,
                                        sx,sy2+hp,c)
                                end
                                -- bottom triangle
                                local lx=lb
                                for i=0,ihth do
                                    lx+=xstep
                                    line(lx,sy2+hp+1+i,
                                         sx,sy2+hp+1+i,c)
                                end
                            end

                            -- right side face
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                local xstep=(rb-sx)/ihth
                                -- top triangle
                                local lx=rb
                                for i=0,ihth-1 do
                                    lx-=xstep
                                    line(lx,sy2+i,
                                         rb,sy2+i,c)
                                end
                                -- middle rect
                                if hp>=ihth then
                                    rectfill(sx,sy2+ihth,
                                        rb,sy2+hp,c)
                                end
                                -- bottom triangle
                                local rx=rb
                                for i=0,ihth do
                                    rx-=xstep
                                    line(sx,sy2+hp+1+i,
                                         rx,sy2+hp+1+i,c)
                                end
                            end

                            -- diamond top
                            local c=t[1]
                            local w=htw
                            line(sx-w,sy2,sx+w,sy2,c)
                            for r=1,ihth do
                                w-=dstep
                                line(sx-w,sy2-r,
                                     sx+w,sy2-r,c)
                                line(sx-w,sy2+r,
                                     sx+w,sy2+r,c)
                            end
                        end
                    end
                end
            end
        end
    end
end

-----------------------------
-- 4: skip side lines
-- draw every other diagonal
-- line for side faces
-----------------------------
function draw_4_skiplines()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    cache_around()

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw
                    and sy>-hth and sy<128+hth then
                        local c=t[1]
                        local w=htw
                        line(sx-w,sy,sx+w,sy,c)
                        for r=1,ihth do
                            w-=dstep
                            line(sx-w,sy-r,sx+w,sy-r,c)
                            line(sx-w,sy+r,sx+w,sy+r,c)
                        end
                    end
                end
            end
        end
    end

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw
                        and sy+hth>0
                        and sy2-hth<128 then
                            local cy=sy+ihth-hp
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                for i=0,hp+1,2 do
                                    line(lb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                for i=0,hp+1,2 do
                                    line(rb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            local c=t[1]
                            local w=htw
                            line(sx-w,sy2,sx+w,sy2,c)
                            for r=1,ihth do
                                w-=dstep
                                line(sx-w,sy2-r,
                                     sx+w,sy2-r,c)
                                line(sx-w,sy2+r,
                                     sx+w,sy2+r,c)
                            end
                        end
                    end
                end
            end
        end
    end
end

-----------------------------
-- 5: tight cull
-- tighter screen bounds +
-- skip tiles fully behind
-- the row in front
-----------------------------
function draw_5_tightcull()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    local maxbh=20*bh -- max possible hp
    cache_around()

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    -- tighter: full diamond bounds
                    if sx+htw>0 and sx-htw<128
                    and sy+ihth>0 and sy-ihth<128 then
                        local c=t[1]
                        local w=htw
                        line(sx-w,sy,sx+w,sy,c)
                        for r=1,ihth do
                            w-=dstep
                            line(sx-w,sy-r,sx+w,sy-r,c)
                            line(sx-w,sy+r,sx+w,sy+r,c)
                        end
                    end
                end
            end
        end
    end

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        -- tight: tile + column bounds
                        if sx+htw>0 and sx-htw<128
                        and sy+ihth>0
                        and sy2-ihth<128 then
                            local cy=sy+ihth-hp
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                for i=0,hp+1 do
                                    line(lb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                for i=0,hp+1 do
                                    line(rb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            local c=t[1]
                            local w=htw
                            line(sx-w,sy2,sx+w,sy2,c)
                            for r=1,ihth do
                                w-=dstep
                                line(sx-w,sy2-r,
                                     sx+w,sy2-r,c)
                                line(sx-w,sy2+r,
                                     sx+w,sy2+r,c)
                            end
                        end
                    end
                end
            end
        end
    end
end

-----------------------------
-- 6: combined best
-- rectfill sides + tight cull
-----------------------------
function draw_6_combined()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    cache_around()

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx+htw>0 and sx-htw<128
                    and sy+ihth>0 and sy-ihth<128 then
                        local c=t[1]
                        local w=htw
                        line(sx-w,sy,sx+w,sy,c)
                        for r=1,ihth do
                            w-=dstep
                            line(sx-w,sy-r,sx+w,sy-r,c)
                            line(sx-w,sy+r,sx+w,sy+r,c)
                        end
                    end
                end
            end
        end
    end

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx+htw>0 and sx-htw<128
                        and sy+ihth>0
                        and sy2-ihth<128 then
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0

                            -- left face: rectfill body
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                local xstp=(sx-lb)/ihth
                                local rx=lb
                                for i=0,ihth-1 do
                                    rx+=xstp
                                    line(lb,sy2+i,
                                         rx,sy2+i,c)
                                end
                                if hp>=ihth then
                                    rectfill(lb,sy2+ihth,
                                        sx,sy2+hp,c)
                                end
                                local lx=lb
                                for i=0,ihth do
                                    lx+=xstp
                                    line(lx,sy2+hp+1+i,
                                         sx,sy2+hp+1+i,c)
                                end
                            end

                            -- right face: rectfill body
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                local xstp=(rb-sx)/ihth
                                local lx=rb
                                for i=0,ihth-1 do
                                    lx-=xstp
                                    line(lx,sy2+i,
                                         rb,sy2+i,c)
                                end
                                if hp>=ihth then
                                    rectfill(sx,sy2+ihth,
                                        rb,sy2+hp,c)
                                end
                                local rx=rb
                                for i=0,ihth do
                                    rx-=xstp
                                    line(sx,sy2+hp+1+i,
                                         rx,sy2+hp+1+i,c)
                                end
                            end

                            -- diamond top
                            local c=t[1]
                            local w=htw
                            line(sx-w,sy2,sx+w,sy2,c)
                            for r=1,ihth do
                                w-=dstep
                                line(sx-w,sy2-r,
                                     sx+w,sy2-r,c)
                                line(sx-w,sy2+r,
                                     sx+w,sy2+r,c)
                            end
                        end
                    end
                end
            end
        end
    end
end

-----------------------------
-- 7: stamp diamonds
-- pre-render diamond shape into
-- spritesheet, sspr+pal to place
-- side faces still line-based
-----------------------------
function draw_7_stamp()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    cache_around()

    -- build diamond stamp in spritesheet
    -- use ceil(htw) as center for sub-pixel safety
    local scx=-flr(-htw)
    local sw=scx*2+1
    local sh=ihth*2+1

    poke(0x5f55,0x00)
    rectfill(0,0,sw-1,sh-1,0)
    local w=htw
    line(scx-w,ihth,scx+w,ihth,7)
    for r=1,ihth do
        w-=dstep
        line(scx-w,ihth-r,scx+w,ihth-r,7)
        line(scx-w,ihth+r,scx+w,ihth+r,7)
    end
    poke(0x5f55,0x60)

    -- water: diamond stamp only
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw
                    and sy>-hth and sy<128+hth then
                        pal(7,t[1])
                        sspr(0,0,sw,sh,
                            sx-scx,sy-ihth)
                    end
                end
            end
        end
    end

    -- land: line sides + stamp top
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw
                        and sy+hth>0
                        and sy2-hth<128 then
                            local cy=sy+ihth-hp
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                for i=0,hp+1 do
                                    line(lb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                for i=0,hp+1 do
                                    line(rb,sy2+i,
                                         sx,cy+i,c)
                                end
                            end
                            pal(7,t[1])
                            sspr(0,0,sw,sh,
                                sx-scx,sy2-ihth)
                        end
                    end
                end
            end
        end
    end

    pal()
end

-----------------------------
-- 8: stamp full
-- diamond stamp + side face
-- decomposed: rectfill body
-- + stamped edge triangles
-----------------------------
function draw_8_stampfull()
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=64-(cam_wx-cam_wy)*htw
    local co_y=64-(cam_wx+cam_wy)*hth
    local vr=view_range
    local wcx=flr(cam_wx)
    local wcy=flr(cam_wy)
    local ihth=-flr(-hth)
    if ihth<1 then ihth=1 end
    local dstep=htw/ihth
    cache_around()

    -- build stamps in spritesheet
    local scx=-flr(-htw)
    local sw=scx*2+1
    local sh=ihth*2+1

    poke(0x5f55,0x00)
    -- clear stamp area
    rectfill(0,0,127,sh+ihth*2+4,0)

    -- diamond stamp at (scx, ihth)
    local w=htw
    line(scx-w,ihth,scx+w,ihth,7)
    for r=1,ihth do
        w-=dstep
        line(scx-w,ihth-r,scx+w,ihth-r,7)
        line(scx-w,ihth+r,scx+w,ihth+r,7)
    end

    -- left side top triangle stamp
    -- at y=sh+1, width=scx+1, height=ihth
    local lty=sh+1
    local xstep=htw/ihth
    local rx=0
    for i=0,ihth-1 do
        rx+=xstep
        line(0,lty+i,rx,lty+i,7)
    end

    -- left side bottom triangle stamp
    -- at y=lty+ihth+1, height=ihth+1
    local lby=lty+ihth+1
    local lx=0
    for i=0,ihth do
        lx+=xstep
        line(lx,lby+i,htw,lby+i,7)
    end

    -- right side top triangle stamp
    -- at y=lby+ihth+2, width=scx+1
    local rty=lby+ihth+2
    local lx2=htw
    for i=0,ihth-1 do
        lx2-=xstep
        line(lx2,rty+i,htw,rty+i,7)
    end

    -- right side bottom triangle stamp
    local rby=rty+ihth+1
    local rx2=htw
    for i=0,ihth do
        rx2-=xstep
        line(0,rby+i,rx2,rby+i,7)
    end

    poke(0x5f55,0x60)

    -- stamp widths for side edges
    local ew=flr(htw)+1

    -- water: diamond stamp
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw
                    and sy>-hth and sy<128+hth then
                        pal(7,t[1])
                        sspr(0,0,sw,sh,
                            sx-scx,sy-ihth)
                    end
                end
            end
        end
    end

    -- land: stamp sides + stamp top
    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw
                        and sy+hth>0
                        and sy2-hth<128 then
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0

                            -- left side face
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                pal(7,c)
                                -- top edge stamp
                                sspr(0,lty,ew,ihth,
                                    lb,sy2)
                                -- rect body
                                if hp>=ihth then
                                    rectfill(lb,sy2+ihth,
                                        sx,sy2+hp,c)
                                end
                                -- bottom edge stamp
                                sspr(0,lby,ew,ihth+1,
                                    lb,sy2+hp+1)
                            end

                            -- right side face
                            if he<h then
                                local c=t[3]
                                pal(7,c)
                                -- top edge stamp
                                sspr(0,rty,ew,ihth,
                                    sx,sy2)
                                -- rect body
                                if hp>=ihth then
                                    rectfill(sx,sy2+ihth,
                                        sx+htw,sy2+hp,c)
                                end
                                -- bottom edge stamp
                                sspr(0,rby,ew,ihth+1,
                                    sx,sy2+hp+1)
                            end

                            -- diamond top stamp
                            pal(7,t[1])
                            sspr(0,0,sw,sh,
                                sx-scx,sy2-ihth)
                        end
                    end
                end
            end
        end
    end

    pal()
end

-----------------------------
-- benchmark runner
-----------------------------
rnames={
    "lines",
    "rectsides",
    "skiplines",
    "tightcull",
    "combined",
    "stamp",
    "stamp_full",
}
rfuncs={
    draw_1_lines,
    draw_3_rectsides,
    draw_4_skiplines,
    draw_5_tightcull,
    draw_6_combined,
    draw_7_stamp,
    draw_8_stampfull,
}

warmup_frames=5
sample_frames=30

phase="warmup"
cur_r=1
cur_z=1
frame_count=0
cpu_accum=0
cpu_min=999
cpu_max=0
results={}

function _init()
    for zi=1,#zooms do
        set_zoom(zi)
        cache_around()
    end
    set_zoom(1)
end

function _update60()
end

function pad(s,w)
    while #s<w do s=s.." " end
    return s
end

function fmtp(n)
    local v=flr(n*1000)/10
    return tostr(v).."%"
end

function _draw()
    if phase=="done" then
        cls(0)
        print("benchmark complete!",10,58,11)
        print("check console output",14,66,6)
        return
    end

    cls(0)
    local d0=stat(1)
    rfuncs[cur_r]()
    local cpu=stat(1)-d0
    frame_count+=1

    if phase=="warmup" then
        if frame_count>=warmup_frames then
            phase="sample"
            frame_count=0
            cpu_accum=0
            cpu_min=999
            cpu_max=0
        end
    elseif phase=="sample" then
        cpu_accum+=cpu
        if cpu<cpu_min then cpu_min=cpu end
        if cpu>cpu_max then cpu_max=cpu end
        if frame_count>=sample_frames then
            add(results,{
                r=rnames[cur_r],
                z=zooms[cur_z][5],
                avg=cpu_accum/sample_frames,
                mn=cpu_min,mx=cpu_max,
                tiles=(view_range*2+1)^2
            })
            phase="next"
        end
    elseif phase=="next" then
        cur_z+=1
        if cur_z>#zooms then
            cur_z=1
            cur_r+=1
        end
        if cur_r>#rfuncs then
            print_results()
            phase="done"
            return
        end
        set_zoom(cur_z)
        frame_count=0
        phase="warmup"
    end

    rectfill(0,0,127,22,0)
    local total=#rfuncs*#zooms
    local done=(cur_r-1)*#zooms+cur_z-1
    if phase=="sample" then done+=0.5 end
    local pct=done/total
    print(rnames[cur_r].." @ "
        ..zooms[cur_z][5],1,1,7)
    print(phase.." "..frame_count,1,8,6)
    rectfill(1,16,1+125*pct,20,11)
    rect(1,16,126,20,5)
    print(flr(pct*100).."%",55,16,0)
end

function print_results()
    printh("")
    printh("================================")
    printh("  render benchmark results")
    printh("================================")
    printh("")
    printh(pad("renderer",14)
        ..pad("zoom",13)
        ..pad("avg",8)
        ..pad("min",8)
        ..pad("max",8)
        .."tiles")
    printh("-------------------------------"
        .."---------------------------")

    for r in all(results) do
        printh(pad(r.r,14)
            ..pad(r.z,13)
            ..pad(fmtp(r.avg),8)
            ..pad(fmtp(r.mn),8)
            ..pad(fmtp(r.mx),8)
            ..tostr(r.tiles))
    end

    printh("")
    printh("-- avg across all zooms --")
    printh("")
    for ri=1,#rnames do
        local sum,cnt=0,0
        for r in all(results) do
            if r.r==rnames[ri] then
                sum+=r.avg
                cnt+=1
            end
        end
        if cnt>0 then
            printh("  "..pad(rnames[ri],14)
                .."avg: "..fmtp(sum/cnt))
        end
    end
    printh("================================")
end
__gfx__

__sfx__

__music__
