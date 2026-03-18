pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- terrain a/b perf test
-- compares line vs rectfill side faces
-- at every height with checkerboard terrain

half_tile_width=12
half_tile_height=6
block_h=2
cam_offset_x=64
cam_offset_y=64
view_range=8

function diamond(sx,sy,c)
    local w=half_tile_width
    line(sx-w,sy,sx+w,sy,c)
    for r=1,half_tile_height do
        w-=2
        line(sx-w,sy-r,sx+w,sy-r,c)
        line(sx-w,sy+r,sx+w,sy+r,c)
    end
end

-- checkerboard: alternating h and 0
-- forces every tile to draw both sides
function build_checker(h)
    cell_cache={}
    for x=-12,12 do
        cell_cache[x]={}
        for y=-12,12 do
            local th=((x+y)%2==0) and h or 0
            local tc=th>0 and 11 or 1
            local lc=th>0 and 3 or 0
            cell_cache[x][y]={tc,lc,lc,th}
        end
    end
end

-- draw with diagonal LINE approach (original)
function draw_line()
    local px,py=0,0
    local htw,hth=half_tile_width,half_tile_height
    local co_x,co_y=cam_offset_x,cam_offset_y
    local bh=block_h
    local cc=cell_cache
    local vr=view_range
    for x=px-vr,px+vr do
        local row=cc[x]
        local nrow=cc[x+1]
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
                            diamond(sx,sy2,t[1])
                        end
                    elseif h<=0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        if sx>-htw and sx<128+htw and sy>-hth and sy<128+hth then
                            diamond(sx,sy,t[1])
                        end
                    end
                end
            end
        end
    end
end

-- draw with RECTFILL 3-zone approach
function draw_rect()
    local px,py=0,0
    local htw,hth=half_tile_width,half_tile_height
    local co_x,co_y=cam_offset_x,cam_offset_y
    local bh=block_h
    local cc=cell_cache
    local vr=view_range
    for x=px-vr,px+vr do
        local row=cc[x]
        local nrow=cc[x+1]
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
                            local ts=row[y+1]
                            local te=nrow and nrow[y]
                            local hs=ts and ts[4] or 0
                            local he=te and te[4] or 0
                            if hs<h then
                                local lb=sx-htw
                                local c=t[2]
                                for dy=0,hth-1 do
                                    rectfill(lb,sy2+dy,lb+dy*2+1,sy2+dy,c)
                                end
                                if hp>=hth then
                                    rectfill(lb,sy2+hth,sx,sy2+hp,c)
                                end
                                for dy=1,hth do
                                    rectfill(lb+dy*2,sy2+hp+dy,sx,sy2+hp+dy,c)
                                end
                            end
                            if he<h then
                                local rb=sx+htw
                                local c=t[3]
                                for dy=0,hth-1 do
                                    rectfill(rb-dy*2-1,sy2+dy,rb,sy2+dy,c)
                                end
                                if hp>=hth then
                                    rectfill(sx,sy2+hth,rb,sy2+hp,c)
                                end
                                for dy=1,hth do
                                    rectfill(sx,sy2+hp+dy,rb-dy*2,sy2+hp+dy,c)
                                end
                            end
                            diamond(sx,sy2,t[1])
                        end
                    elseif h<=0 then
                        local sx=co_x+(x-y)*htw
                        local sy=co_y+(x+y)*hth
                        if sx>-htw and sx<128+htw and sy>-hth and sy<128+hth then
                            diamond(sx,sy,t[1])
                        end
                    end
                end
            end
        end
    end
end

-- test harness
sample_frames=60
warmup_frames=10
heights={1,2,3,4,5,6,8,10,12,16,20,28}
cur_h=1      -- index into heights
cur_mode=1   -- 1=line, 2=rectfill
frame_count=0
cpu_sum=0
cpu_peak=0
phase="warmup"
done=false
status_msg=""
-- store results for summary
res_line={}
res_rect={}

function pct(v) return flr(v*1000)/10 end

function _init()
    printh("================================")
    printh("line vs rectfill a/b test")
    printh("checkerboard terrain, vr=8, bh=2")
    printh("================================")
    printh("")
    printh("h  | line_avg | line_pk | rect_avg | rect_pk | winner")
    printh("---|---------|---------|----------|---------|-------")
end

function _update60()
    if done then return end

    if phase=="warmup" then
        if frame_count==0 then
            local h=heights[cur_h]
            build_checker(h)
            local mode_name=cur_mode==1 and "line" or "rectfill"
            status_msg="h="..h.." ["..mode_name.."]"
        end
        frame_count+=1
        if frame_count>=warmup_frames then
            frame_count=0
            cpu_sum=0
            cpu_peak=0
            phase="sample"
        end

    elseif phase=="sample" then
        frame_count+=1
        if frame_count>=sample_frames then
            phase="next"
        end

    elseif phase=="next" then
        local h=heights[cur_h]
        local avg=cpu_sum/sample_frames

        if cur_mode==1 then
            res_line[cur_h]={avg=avg,peak=cpu_peak}
            -- now test rectfill for same height
            cur_mode=2
            frame_count=0
            phase="warmup"
        else
            res_rect[cur_h]={avg=avg,peak=cpu_peak}
            -- print comparison row
            local rl=res_line[cur_h]
            local rr=res_rect[cur_h]
            local winner=rl.avg<rr.avg and "LINE" or "RECT"
            local diff=pct(abs(rl.avg-rr.avg))
            printh(h
                .."  | "..pct(rl.avg).."%"
                .." | "..pct(rl.peak).."%"
                .." | "..pct(rr.avg).."%"
                .." | "..pct(rr.peak).."%"
                .." | "..winner.." +"..diff.."%")

            -- advance to next height
            cur_mode=1
            cur_h+=1
            if cur_h>#heights then
                printh("")
                printh("================================")
                printh("test complete")
                printh("================================")
                done=true
                status_msg="done! press esc for results"
            else
                frame_count=0
                phase="warmup"
            end
        end
    end
end

function _draw()
    local d0=stat(1)
    cls(0)

    if cur_mode==1 then
        draw_line()
    else
        draw_rect()
    end

    local dcost=stat(1)-d0

    if phase=="sample" then
        cpu_sum+=dcost
        cpu_peak=max(cpu_peak,dcost)
    end

    -- status overlay
    rectfill(0,0,127,24,0)
    print("line vs rectfill a/b test",1,1,7)
    if done then
        print("complete! esc for results",1,10,11)
    else
        local progress=(cur_h-1)*2+(cur_mode-1)
        local total=#heights*2
        print("test "..progress.."/"..total.." "..status_msg,1,10,10)
        print("phase:"..phase.." f:"..frame_count.."/"..sample_frames.." draw:"..pct(dcost).."%",1,17,5)
    end
end
__gfx__

__sfx__

__music__
