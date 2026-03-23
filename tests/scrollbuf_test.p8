pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- scrolling buffer benchmark
-- tests baseline vs buffer during:
--  1. diagonal scroll only
--  2. diagonal scroll + zoom oscillation
-- prints results to console

half_tile_width=12
half_tile_height=6
block_h=2
view_range=8
cell_cache={}
cam_wx=0
cam_wy=0

-- zoom presets: {htw,hth,bh,vr}
zooms={
    {4,  2, 1, 20},
    {8,  4, 1, 10},
    {12, 6, 2, 8},
    {16, 8, 3, 6},
    {24,12, 4, 4},
}

-- current smooth zoom state
cur_zoom=3
smooth_htw=12
smooth_hth=6
smooth_bh=2
smooth_vr=8

function set_zoom_snap(zi)
    local z=zooms[zi]
    half_tile_width=z[1]
    half_tile_height=z[2]
    block_h=z[3]
    view_range=z[4]
    smooth_htw=z[1]
    smooth_hth=z[2]
    smooth_bh=z[3]
    smooth_vr=z[4]
    cur_zoom=zi
end

function apply_smooth_zoom()
    local lo=flr(cur_zoom)
    local hi=min(#zooms,lo+1)
    local f=cur_zoom-lo
    local zl,zh=zooms[lo],zooms[hi]
    local t_htw=zl[1]+(zh[1]-zl[1])*f
    local t_hth=zl[2]+(zh[2]-zl[2])*f
    local t_bh=zl[3]+(zh[3]-zl[3])*f
    local t_vr=zl[4]+(zh[4]-zl[4])*f

    local s=0.15
    smooth_htw+=(t_htw-smooth_htw)*s
    smooth_hth+=(t_hth-smooth_hth)*s
    smooth_bh+=(t_bh-smooth_bh)*s
    smooth_vr+=(t_vr-smooth_vr)*s

    half_tile_width=smooth_htw
    half_tile_height=smooth_hth
    block_h=smooth_bh
    view_range=flr(smooth_vr)+1
end

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
-- render: full world
-----------------------------
function render_full()
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
                            line(sx-w,sy-r,
                                 sx+w,sy-r,c)
                            line(sx-w,sy+r,
                                 sx+w,sy+r,c)
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
                            line(sx-w,sy2,
                                 sx+w,sy2,c)
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
-- render: dirty edge tiles
-----------------------------
function render_edge(dx,dy)
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
    local maxhp=20*bh
    cache_around()

    local vx0,vx1=-999,999
    local hy0,hy1=-999,999
    if dx>0 then vx0=128-dx-htw*2 end
    if dx<0 then vx1=-dx+htw*2 end
    if dy>0 then hy0=128-dy-maxhp-ihth end
    if dy<0 then hy1=-dy+ihth end

    for x=wcx-vr,wcx+vr do
        local row=cell_cache[x]
        if row then
            for y=wcy-vr,wcy+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx=co_x+(x-y)*htw
                    local sy=co_y+(x+y)*hth
                    local ind=false
                    if sx+htw>=vx0
                    and sx-htw<=vx1 then
                        ind=true
                    end
                    if sy+ihth>=hy0
                    and sy-ihth<=hy1 then
                        ind=true
                    end
                    if ind
                    and sx>-htw and sx<128+htw
                    and sy>-hth and sy<128+hth then
                        local c=t[1]
                        local w=htw
                        line(sx-w,sy,sx+w,sy,c)
                        for r=1,ihth do
                            w-=dstep
                            line(sx-w,sy-r,
                                 sx+w,sy-r,c)
                            line(sx-w,sy+r,
                                 sx+w,sy+r,c)
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
                        local ind=false
                        if sx+htw>=vx0
                        and sx-htw<=vx1 then
                            ind=true
                        end
                        if sy+ihth>=hy0
                        and sy2-ihth<=hy1 then
                            ind=true
                        end
                        if ind
                        and sx>-htw and sx<128+htw
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
                            line(sx-w,sy2,
                                 sx+w,sy2,c)
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
-- buffer: shift spritesheet
-----------------------------
function shift_buf(dx,dy)
    if dy>0 then
        memcpy(0x0000, dy*64,
               (128-dy)*64)
        memset((128-dy)*64, 0, dy*64)
    elseif dy<0 then
        local ady=-dy
        memcpy(0x6000, 0x0000, 0x2000)
        for row=0,127-ady do
            memcpy((row+ady)*64,
                   0x6000+row*64, 64)
        end
        memset(0x0000, 0, ady*64)
    end

    local bdx=dx\2
    if bdx>0 then
        for row=0,127 do
            local ra=row*64
            memcpy(ra, ra+bdx, 64-bdx)
            memset(ra+64-bdx, 0, bdx)
        end
    elseif bdx<0 then
        local abx=-bdx
        memcpy(0x6000, 0x0000, 0x2000)
        for row=0,127 do
            local ra=row*64
            memcpy(ra+abx,
                   0x6000+ra, 64-abx)
            memset(ra, 0, abx)
        end
    end
end

-----------------------------
-- simulation patterns
-----------------------------
sim_frame=0

function sim_scroll()
    -- diagonal scroll at gameplay speed
    local spd=0.5
    cam_wx+=spd/half_tile_width*0.4
    cam_wy+=spd/half_tile_height*0.2
    sim_frame+=1
end

function sim_scroll_zoom()
    -- diagonal scroll + sine zoom
    -- oscillates between zoom 2-4
    -- (8x4 mid to 16x8 close)
    -- full cycle ~180 frames (3 sec)
    local spd=0.5
    cam_wx+=spd/half_tile_width*0.4
    cam_wy+=spd/half_tile_height*0.2
    cur_zoom=3+sin(sim_frame/180)*1
    apply_smooth_zoom()
    sim_frame+=1
end

-----------------------------
-- draw modes
-----------------------------
-- buffer state
buf_co_x=nil
buf_co_y=nil
buf_htw=nil
buf_hth=nil

function reset_buf()
    buf_co_x=nil
    buf_co_y=nil
    buf_htw=nil
    buf_hth=nil
end

function do_baseline()
    cls(0)
    render_full()
end

function do_buffer()
    local htw=half_tile_width
    local hth=half_tile_height
    local co_x=flr(64-(cam_wx-cam_wy)*htw)
    local co_y=flr(64-(cam_wx+cam_wy)*hth)

    -- detect zoom change: tile dims
    -- changed = buffer invalid
    local zoom_changed=false
    if buf_htw~=nil then
        if abs(htw-buf_htw)>0.01
        or abs(hth-buf_hth)>0.01 then
            zoom_changed=true
        end
    end

    -- full re-render needed?
    if buf_co_x==nil or zoom_changed then
        poke(0x5f55, 0x00)
        cls(0)
        render_full()
        poke(0x5f55, 0x60)
        buf_co_x=co_x
        buf_co_y=co_y
        buf_htw=htw
        buf_hth=hth
        memcpy(0x6000, 0x0000, 0x2000)
        return
    end

    local dx=buf_co_x-co_x
    local dy=buf_co_y-co_y
    dx=flr(dx/2)*2

    if dx==0 and dy==0 then
        memcpy(0x6000, 0x0000, 0x2000)
        return
    end

    if abs(dx)>64 or abs(dy)>64 then
        poke(0x5f55, 0x00)
        cls(0)
        render_full()
        poke(0x5f55, 0x60)
        buf_co_x=co_x
        buf_co_y=co_y
        buf_htw=htw
        buf_hth=hth
        memcpy(0x6000, 0x0000, 0x2000)
        return
    end

    shift_buf(dx, dy)
    buf_co_x-=dx
    buf_co_y-=dy

    poke(0x5f55, 0x00)
    render_edge(dx, dy)
    poke(0x5f55, 0x60)

    memcpy(0x6000, 0x0000, 0x2000)
end

-----------------------------
-- benchmark runner
-----------------------------
warmup=10
samples=120

-- test matrix:
-- {name, sim_fn, draw_fn}
tests={
    {"bl_scroll",  sim_scroll,      do_baseline},
    {"buf_scroll", sim_scroll,      do_buffer},
    {"bl_sc+zoom", sim_scroll_zoom, do_baseline},
    {"buf_sc+zoom",sim_scroll_zoom, do_buffer},
}

phase="warmup"
cur_test=1
frame_count=0
cpu_accum=0
results={}

function _init()
    -- pre-cache broadly
    set_zoom_snap(2)
    cache_around()
    set_zoom_snap(3)
    cache_around()
    set_zoom_snap(4)
    cache_around()
    reset_state()
end

function reset_state()
    cam_wx=0
    cam_wy=0
    sim_frame=0
    set_zoom_snap(3)
    reset_buf()
end

function _update60()
end

function pad(s,w)
    while #s<w do s=s.." " end
    return s
end

function fmtp(n)
    return tostr(flr(n*1000)/10).."%"
end

function _draw()
    if phase=="done" then
        cls(0)
        print("benchmark complete!",10,58,11)
        print("check console output",14,66,6)
        return
    end

    -- run simulation
    local t=tests[cur_test]
    t[2]() -- sim function

    -- run draw and measure
    local d0=stat(1)
    t[3]() -- draw function
    local cpu=stat(1)-d0

    frame_count+=1

    if phase=="warmup" then
        if frame_count>=warmup then
            phase="sample"
            frame_count=0
            cpu_accum=0
        end
    elseif phase=="sample" then
        cpu_accum+=cpu
        if frame_count>=samples then
            add(results,{
                n=t[1],
                avg=cpu_accum/samples,
            })
            phase="next"
        end
    elseif phase=="next" then
        cur_test+=1
        if cur_test>#tests then
            print_results()
            phase="done"
            return
        end
        reset_state()
        frame_count=0
        phase="warmup"
    end

    -- hud
    rectfill(0,0,127,22,0)
    local pct=(cur_test-1)/#tests
    print(t[1],1,1,7)
    print(phase.." "..frame_count
        .." z:"..tostr(flr(cur_zoom*10)/10),
        1,8,6)
    rectfill(1,16,1+125*pct,20,11)
    rect(1,16,126,20,5)
    print(flr(pct*100).."%",55,16,0)
end

function print_results()
    printh("")
    printh("================================")
    printh("  scrolling buffer benchmark")
    printh("================================")
    printh("")
    printh(pad("test",16)..pad("avg cpu",10))
    printh("---------------------------")

    for r in all(results) do
        printh(pad(r.n,16)..fmtp(r.avg))
    end

    printh("")
    printh("-- comparison --")
    printh("")

    -- scroll only
    local bl_s,bf_s=0,0
    for r in all(results) do
        if r.n=="bl_scroll" then bl_s=r.avg end
        if r.n=="buf_scroll" then bf_s=r.avg end
    end
    if bl_s>0 then
        printh("  scroll only:")
        printh("    baseline: "..fmtp(bl_s))
        printh("    buffer:   "..fmtp(bf_s))
        printh("    saved:    "
            ..tostr(flr((1-bf_s/bl_s)*100)).."%")
    end

    -- scroll + zoom
    local bl_z,bf_z=0,0
    for r in all(results) do
        if r.n=="bl_sc+zoom" then bl_z=r.avg end
        if r.n=="buf_sc+zoom" then bf_z=r.avg end
    end
    if bl_z>0 then
        printh("")
        printh("  scroll + zoom:")
        printh("    baseline: "..fmtp(bl_z))
        printh("    buffer:   "..fmtp(bf_z))
        printh("    saved:    "
            ..tostr(flr((1-bf_z/bl_z)*100)).."%")
    end

    printh("================================")
end
__gfx__

__sfx__

__music__
