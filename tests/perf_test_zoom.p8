pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- zoom engine test
-- interactive: explore dynamic zoom
-- for potential engine rewrite

-- zoom presets: {htw, hth, bh, vr, label}
zooms={
    {4,  2, 1, 20, "4x2  (far)"},
    {6,  3, 1, 14, "6x3  (wide)"},
    {8,  4, 1, 10, "8x4"},
    {10, 5, 2, 9,  "10x5"},
    {12, 6, 2, 8,  "12x6 (game)"},
    {16, 8, 3, 6,  "16x8 (close)"},
    {20,10, 4, 5,  "20x10"},
    {24,12, 4, 4,  "24x12 (macro)"},
}
cur_zoom=5  -- start at game default

-- state
half_tile_width=12
half_tile_height=6
block_h=2
view_range=8
cam_offset_x=64
cam_offset_y=64
cell_cache={}
scroll_x=0
scroll_y=0

-- terrain gen (simple sin hills)
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
    if not cell_cache[x] then cell_cache[x]={} end
    if not cell_cache[x][y] then
        cell_cache[x][y]=gen_tile(x,y)
    end
end

function iso(x,y)
    return cam_offset_x+(x-y)*half_tile_width,
           cam_offset_y+(x+y)*half_tile_height
end

function diamond(sx,sy,c)
    local htw=half_tile_width
    local hth=flr(half_tile_height)
    if hth<1 then hth=1 end
    local step=htw/hth
    local w=htw
    line(sx-w,sy,sx+w,sy,c)
    for r=1,hth do
        w-=step
        line(sx-w,sy-r,sx+w,sy-r,c)
        line(sx-w,sy+r,sx+w,sy+r,c)
    end
end

-- side face renderer (line-based,
-- works at any fractional scale)
function draw_side_l(sx,sy2,hp,cy,htw,hth,c)
    local lb=sx-htw
    for i=0,hp do line(lb,sy2+i,sx,cy+i,c) end
end

function draw_side_r(sx,sy2,hp,cy,htw,hth,c)
    local rb=sx+htw
    for i=0,hp do line(rb,sy2+i,sx,cy+i,c) end
end

function draw_world()
    local px=flr(scroll_x)
    local py=flr(scroll_y)
    local htw=half_tile_width
    local hth=half_tile_height
    local bh=block_h
    local co_x=cam_offset_x-(scroll_x-px)*htw*2
    local co_y=cam_offset_y-(scroll_y-py)*hth*2
    local vr=view_range

    -- ensure cache
    for x=px-vr-1,px+vr+1 do
        for y=py-vr-1,py+vr+1 do
            ensure_cached(x,y)
        end
    end

    -- draw water
    for x=px-vr,px+vr do
        local row=cell_cache[x]
        if row then
            for y=py-vr,py+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw and sy>-hth and sy<128+hth then
                        diamond(sx,sy,t[1])
                    end
                end
            end
        end
    end

    -- draw land
    for x=px-vr,px+vr do
        local row=cell_cache[x]
        local nrow=cell_cache[x+1]
        if row then
            for y=py-vr,py+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw and sy+hth>0 and sy2-hth<128 then
                            local cy=sy+hth-hp
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0
                            if hs<h then
                                draw_side_l(sx,sy2,hp,cy,htw,hth,t[2])
                            end
                            if he<h then
                                draw_side_r(sx,sy2,hp,cy,htw,hth,t[3])
                            end
                            diamond(sx,sy2,t[1])
                        end
                    end
                end
            end
        end
    end
end

cpu_draw=0
-- smooth zoom state
target_htw=12
target_hth=6
target_bh=2
target_vr=8
smooth_htw=12
smooth_hth=6
smooth_bh=2
smooth_vr=8

function _update60()
    -- zoom controls (x/o)
    if btn(5) then cur_zoom=min(#zooms,cur_zoom+0.05) end
    if btn(4) then cur_zoom=max(1,cur_zoom-0.05) end

    -- interpolate between adjacent presets
    local lo=flr(cur_zoom)
    local hi=min(#zooms,lo+1)
    local frac=cur_zoom-lo
    local zl,zh=zooms[lo],zooms[hi]
    target_htw=zl[1]+(zh[1]-zl[1])*frac
    target_hth=zl[2]+(zh[2]-zl[2])*frac
    target_bh=zl[3]+(zh[3]-zl[3])*frac
    target_vr=zl[4]+(zh[4]-zl[4])*frac

    -- smooth lerp
    local s=0.15
    smooth_htw+=(target_htw-smooth_htw)*s
    smooth_hth+=(target_hth-smooth_hth)*s
    smooth_bh+=(target_bh-smooth_bh)*s
    smooth_vr+=(target_vr-smooth_vr)*s

    half_tile_width=smooth_htw
    half_tile_height=smooth_hth
    block_h=smooth_bh
    view_range=flr(smooth_vr)+1

    -- scroll (arrows = screen-space movement)
    local spd=0.05
    if btn(0) then scroll_x-=spd scroll_y+=spd end
    if btn(1) then scroll_x+=spd scroll_y-=spd end
    if btn(2) then scroll_x-=spd scroll_y-=spd end
    if btn(3) then scroll_x+=spd scroll_y+=spd end
end

function _draw()
    local d0=stat(1)
    cls(0)
    draw_world()
    cpu_draw=stat(1)-d0

    -- hud
    local tiles=(view_range*2+1)^2
    rectfill(0,0,127,20,0)
    print("htw:"..flr(smooth_htw).." hth:"..flr(smooth_hth).." bh:"..flr(smooth_bh*10)/10 .." tiles:"..tiles,1,1,7)
    print("draw:"..flr(cpu_draw*1000)/10 .."%  "..
        (cpu_draw>0.8 and "!!!" or cpu_draw>0.5 and "!" or "ok"),
        1,8,cpu_draw>0.5 and 8 or cpu_draw>0.3 and 9 or 11)
    print("\x8e\x97 zoom  \x8b\x91\x83\x94 move",1,15,5)
end
__gfx__

__sfx__

__music__
