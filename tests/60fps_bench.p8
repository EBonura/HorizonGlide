pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- 60fps benchmark round 4
-- test view_range to fix missing tiles
-- draw: v4 (no prefetch+inline diamond+clip)
-- cache: fill15+bulkevict, fast perlin

half_tile_width=12
half_tile_height=6
block_h=2
cam_offset_x=64
cam_offset_y=64
cam_x,cam_y=0,0

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

function perlin2d(x,y,p)
    local fx,fy=flr(x),flr(y)
    local xi,yi=fx&255,fy&255
    local xf,yf=x-fx,y-fy
    local u=xf*xf*(3-2*xf)
    local v=yf*yf*(3-2*yf)
    local a,b=p[xi]+yi,p[(xi+1)&255]+yi
    local aa,ab,ba,bb=p[a&255],p[(a+1)&255],p[b&255],p[(b+1)&255]
    local ax=((aa&1)<1 and xf or -xf)+((aa&2)<2 and yf or -yf)
    local bx=((ba&1)<1 and xf-1 or 1-xf)+((ba&2)<2 and yf or -yf)
    local cx=((ab&1)<1 and xf or -xf)+((ab&2)<2 and yf-1 or 1-yf)
    local dx=((bb&1)<1 and xf-1 or 1-xf)+((bb&2)<2 and yf-1 or 1-yf)
    local x1=ax+(bx-ax)*u
    return x1+((cx+(dx-cx)*u)-x1)*v
end

TERRAIN_PAL_STR = "\1\0\0\12\1\1\15\4\2\3\1\0\11\3\1\4\2\0\6\5\0\7\6\5"
TERRAIN_THRESH = split"-2,0,2,6,12,18,24,99"
terrain_perm=generate_permutation(1337)
cell_cache={}
scale=12
water_level=0

palette_cache={}
for i=1,8 do
    local p=(i-1)*3+1
    palette_cache[i]={ord(TERRAIN_PAL_STR,p),ord(TERRAIN_PAL_STR,p+1),ord(TERRAIN_PAL_STR,p+2)}
end

function gen_terrain(x,y)
    local nx,ny=x/scale,y/scale
    local perm=terrain_perm
    local cont=perlin2d(nx*.03,ny*.03,perm)*15
    local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
    local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
    local mountain=rid*max(0,cont/15+.5)*30
    local h=flr(mid(cont+hdetail+mountain-water_level,-4,28))
    local i=1
    while h>TERRAIN_THRESH[i] do i+=1 end
    local pc=palette_cache[i]
    return {pc[1],pc[2],pc[3],h}
end

function terrain_raw(x,y)
    x,y=flr(x),flr(y)
    local row=cell_cache[x]
    if not row then row={} cell_cache[x]=row end
    local c=row[y]
    if not c then c=gen_terrain(x,y) row[y]=c end
    return c
end

function diamond(sx,sy,c)
    local w=half_tile_width
    line(sx-w,sy,sx+w,sy,c)
    for r=1,half_tile_height do
        w-=2
        line(sx-w,sy-r,sx+w,sy-r,c)
        line(sx-w,sy+r,sx+w,sy+r,c)
    end
end

-- current view_range for this test
cur_vr=7

function manage_cache()
    local px,py=flr(cam_x),flr(cam_y)
    local margin=cur_vr+2
    local pxm,pym=px-margin,py-margin
    local pxp,pyp=px+margin,py+margin

    local added=0
    for x=pxm,pxp do
        if added>=15 then break end
        for y=pym,pyp do
            if added>=15 then break end
            local row=cell_cache[x]
            if not row then row={} cell_cache[x]=row end
            if not row[y] then
                row[y]=gen_terrain(x,y)
                added+=1
            end
        end
    end

    for x in pairs(cell_cache) do
        if x<pxm or x>pxp then
            cell_cache[x]=nil
        end
    end
end

-- draw v4: no prefetch + inline diamond + clip
function draw_world()
    local px,py=flr(cam_x),flr(cam_y)
    local htw,hth,co_x,co_y,bh=half_tile_width,half_tile_height,cam_offset_x,cam_offset_y,block_h
    local cc=cell_cache
    local vr=cur_vr

    for x=px-vr,px+vr do
        local row=cc[x]
        if row then
            for y=py-vr,py+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx,sy=co_x+(x-y)*htw,co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw and sy>-hth and sy<128+hth then
                        local c=t[1]
                        line(sx-12,sy,sx+12,sy,c)
                        line(sx-10,sy-1,sx+10,sy-1,c)
                        line(sx-10,sy+1,sx+10,sy+1,c)
                        line(sx-8,sy-2,sx+8,sy-2,c)
                        line(sx-8,sy+2,sx+8,sy+2,c)
                        line(sx-6,sy-3,sx+6,sy-3,c)
                        line(sx-6,sy+3,sx+6,sy+3,c)
                        line(sx-4,sy-4,sx+4,sy-4,c)
                        line(sx-4,sy+4,sx+4,sy+4,c)
                        line(sx-2,sy-5,sx+2,sy-5,c)
                        line(sx-2,sy+5,sx+2,sy+5,c)
                        line(sx,sy-6,sx,sy-6,c)
                        line(sx,sy+6,sx,sy+6,c)
                        line(sx-htw,sy,sx+htw,sy,(t[4]<=-2) and 12 or 1)
                    end
                end
            end
        end
    end

    for x=px-vr,px+vr do
        local row=cc[x]
        local nrow=cc[x+1]
        if row then
            for y=py-vr,py+vr do
                local t=row[y]
                if t then
                    local h=t[4]
                    if h>0 then
                        local sx,sy=co_x+(x-y)*htw,co_y+(x+y)*hth
                        local hp=h*bh
                        local sy2=sy-hp
                        if sx>-htw and sx<128+htw and sy+hth>0 and sy2-hth<128 then
                            local cy=co_y+(x+y)*hth+hth-hp
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
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
                            local c=t[1]
                            line(sx-12,sy2,sx+12,sy2,c)
                            line(sx-10,sy2-1,sx+10,sy2-1,c)
                            line(sx-10,sy2+1,sx+10,sy2+1,c)
                            line(sx-8,sy2-2,sx+8,sy2-2,c)
                            line(sx-8,sy2+2,sx+8,sy2+2,c)
                            line(sx-6,sy2-3,sx+6,sy2-3,c)
                            line(sx-6,sy2+3,sx+6,sy2+3,c)
                            line(sx-4,sy2-4,sx+4,sy2-4,c)
                            line(sx-4,sy2+4,sx+4,sy2+4,c)
                            line(sx-2,sy2-5,sx+2,sy2-5,c)
                            line(sx-2,sy2+5,sx+2,sy2+5,c)
                            line(sx,sy2-6,sx,sy2-6,c)
                            line(sx,sy2+6,sx,sy2+6,c)
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------
-- BENCHMARK
--------------------------------------
bench_frames=300
path={}
test_vrs={7,8,9,10}

function build_path()
    for f=0,bench_frames-1 do
        local a=f/bench_frames
        path[f]={cos(a)*20, sin(a)*20}
    end
end

test_mode=1
frame=0
done=false
results={}

function reset_mode()
    frame=0
    cur_vr=test_vrs[test_mode]
    cell_cache={}
    -- warm cache for entire path at this view_range
    for f=0,bench_frames-1 do
        local px,py=flr(path[f][1]),flr(path[f][2])
        local margin=cur_vr+2
        for x=px-margin,px+margin do
            for y=py-margin,py+margin do
                terrain_raw(x,y)
            end
        end
    end
    results[test_mode]={
        cache_sum=0,draw_sum=0,total_sum=0,
        peak_cache=0,peak_draw=0,peak_total=0
    }
end

function _init()
    palt(0,false) palt(14,true)
    build_path()
    printh("---- round 4: view_range test ----")
    reset_mode()
end

function _update60()
    if done then return end

    cam_x,cam_y=path[frame][1],path[frame][2]
    local sx=(cam_x-cam_y)*half_tile_width
    local sy=(cam_x+cam_y)*half_tile_height
    cam_offset_x,cam_offset_y=64-sx,64-sy

    local c0=stat(1)
    manage_cache()
    local c1=stat(1)

    local r=results[test_mode]
    local cc=c1-c0
    r.cache_sum+=cc
    if cc>r.peak_cache then r.peak_cache=cc end
end

function _draw()
    if done then
        cls(0)
        print("benchmark complete",20,50,11)
        print("check debug console",18,60,6)
        return
    end

    cls(1)

    local d0=stat(1)
    draw_world()
    local d1=stat(1)
    local total=d1

    local r=results[test_mode]
    local dc=d1-d0
    r.draw_sum+=dc
    r.total_sum+=total
    if dc>r.peak_draw then r.peak_draw=dc end
    if total>r.peak_total then r.peak_total=total end

    local pct=flr(((test_mode-1)*bench_frames+frame)*100/(#test_vrs*bench_frames))
    rectfill(0,0,127,8,0)
    print("vr="..cur_vr.."  "..test_mode.."/"..#test_vrs.."  f:"..frame.."  "..pct.."%",1,1,7)

    frame+=1
    if frame>=bench_frames then
        if test_mode<#test_vrs then
            test_mode+=1
            reset_mode()
        else
            done=true
            printh("")
            printh("==== ROUND 4: VIEW_RANGE RESULTS ("..bench_frames.." frames, 60fps) ====")
            printh("")
            for m=1,#test_vrs do
                local r=results[m]
                local vr=test_vrs[m]
                local tiles=(vr*2+1)*(vr*2+1)
                printh("view_range="..vr.." ("..tiles.." tiles iterated)")
                printh("    avg cache: "..r.cache_sum/bench_frames)
                printh("    avg draw:  "..r.draw_sum/bench_frames)
                printh("    avg total: "..r.total_sum/bench_frames)
                printh("    peak draw: "..r.peak_draw)
                printh("    peak total:"..r.peak_total)
                printh("")
            end
            printh("============================================")
        end
    end
end
