pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- automated perf stress test
-- runs each test for sample_frames,
-- escalates load, logs via printh

-- iso constants (match game)
half_tile_width=12
half_tile_height=6
block_h=2
cam_offset_x=64
cam_offset_y=64

function iso(x,y)
    return cam_offset_x+(x-y)*half_tile_width,
           cam_offset_y+(x+y)*half_tile_height
end

function draw_iso_ellipse(sx,sy,rx,ry,col,step)
    for a=0,1,step do
        pset(sx+cos(a)*rx,sy+sin(a)*ry,col)
    end
end

-- particle system (exact copy from game)
particle_sys={list={}}

local function make_particle(x,y,z,vx,vy,size,life,kind,col)
    return {
        x=x,y=y,z=z or 0,
        vx=vx,vy=vy,vz=0,
        size=size,
        life=life,max_life=life,
        kind=kind,
        col=col
    }
end

function particle_sys:spawn(x,y,z,col,count)
    count=count or 1
    for _=1,count do
        local p=make_particle(
            x+(rnd()-.5)*.1,
            y+(rnd()-.5)*.1,
            z,
            (rnd()-.5)*.025,
            (rnd()-.5)*.025,
            1+rnd(1),
            40+rnd(20),
            0,col or 0)
        p.vz=-rnd()*0.15-0.1
        add(self.list,p)
    end
end

function particle_sys:explode(wx,wy,z,scale)
    local function add_group(radius,speed,size_px,life,count)
        for _=1,count do
            local angle=rnd()
            local dist=rnd()*radius*scale*0.1
            local vel=rnd()*speed*scale*0.005
            add(self.list,make_particle(
                wx+cos(angle)*dist,
                wy+sin(angle)*dist,
                z+rnd()*0.5,
                cos(angle)*vel,
                sin(angle)*vel,
                size_px*scale,
                life,
                1))
        end
    end
    for i=1,3 do
        add_group(i*2+2,i*0.5,4-i+rnd(i==1 and 2 or 1),i*10+20,flr((4-i)*scale+(i==2 and scale or 0)))
    end
end

function particle_sys:update(cap)
    for i=#self.list,1,-1 do
        local p=self.list[i]
        p.x+=p.vx
        p.y+=p.vy
        p.z+=p.vz
        p.vx*=0.95
        p.vy*=0.95
        p.vz*=0.975
        p.life-=1
        if p.life<=0 then deli(self.list,i) end
    end
    while #self.list>cap do deli(self.list,1) end
end

function particle_sys:draw()
    for p in all(self.list) do
        local screen_x,screen_y=iso(p.x,p.y)
        screen_y+=p.z
        if p.kind==0 then
            local alpha=p.life/p.max_life
            if alpha>0.5 then
                if p.size>1.5 then
                    circfill(screen_x,screen_y,1,p.col)
                else
                    pset(screen_x,screen_y,p.col)
                end
            elseif rnd()>(alpha>0.25 and 0.3 or 0.6) then
                pset(screen_x,screen_y,p.col)
            end
        else
            local alpha=p.life/p.max_life
            circfill(screen_x,screen_y,p.size,alpha<0.15 and 2 or alpha<0.3 and 8 or alpha<0.5 and 9 or alpha<0.8 and 10 or 7)
        end
    end
end

-- mine (exact copy from game)
mine={}
mine.__index=mine
function mine.new(x,y)
    return setmetatable({x=x,y=y,z=60},mine)
end
function mine:update()
    if self.z>0 then
        self.z=max(0,self.z-2)
        return true
    end
    particle_sys:explode(self.x,self.y,0,1.5)
    return false
end
function mine:draw()
    local sx,sy=iso(self.x,self.y)
    draw_iso_ellipse(sx,sy,24,12,8,0.04)
    sy-=self.z>0 and self.z or 0
    local r=4+sin(time()*6+self.x+self.y)*1.5
    circfill(sx,sy,r,7)circfill(sx,sy,r/2,8)
end

---------------------------------------
-- test harness
---------------------------------------
sample_frames=120  -- 2 seconds at 60fps

-- test definitions
-- each: {name, setup_fn, tick_fn, levels}
-- tick_fn runs every frame during sample
-- levels = list of parameter values to test
tests={}
results={}

function add_test(name,setup,tick,levels)
    add(tests,{
        name=name,
        setup=setup,
        tick=tick,
        levels=levels
    })
end

-- state machine
cur_test=1
cur_level=1
frame_count=0
cpu_sum=0
cpu_peak=0
phase="warmup" -- warmup, sample, next, done
warmup_frames=30
status_msg=""
done=false

function log(s)
    printh(s)
end

function pct(v)
    return flr(v*1000)/10
end

function clear_state()
    particle_sys.list={}
    mines={}
end

function _init()
    -- define all tests

    -- test 1: explosion particle cap
    -- how many blast particles can we sustain?
    add_test(
        "blast particles (cap)",
        function(lvl)
            -- pre-fill with explosions to hit cap
            for _=1,20 do
                particle_sys:explode(rnd(6)-3,rnd(6)-3,0,1.5)
            end
        end,
        function(lvl)
            -- keep spawning to maintain saturation
            if #particle_sys.list<lvl then
                particle_sys:explode(rnd(6)-3,rnd(6)-3,0,1.5)
            end
            particle_sys:update(lvl)
        end,
        {25,50,75,100,150,200,300}
    )

    -- test 2: smoke particles (cap)
    add_test(
        "smoke particles (cap)",
        function(lvl)
            for _=1,lvl do
                particle_sys:spawn(rnd(4)-2,rnd(4)-2,0,0,1)
            end
        end,
        function(lvl)
            if #particle_sys.list<lvl then
                particle_sys:spawn(rnd(4)-2,rnd(4)-2,0,0,3)
            end
            particle_sys:update(lvl)
        end,
        {25,50,75,100,150,200,300}
    )

    -- test 3: simultaneous explosions per frame
    -- how many explode() calls per frame?
    add_test(
        "explosions/frame (cap=100)",
        function(lvl) end,
        function(lvl)
            for _=1,lvl do
                particle_sys:explode(rnd(6)-3,rnd(6)-3,0,1.5)
            end
            particle_sys:update(100)
        end,
        {1,2,3,4,5,8,10}
    )

    -- test 4: mine draw cost (iso_ellipse)
    add_test(
        "mine rendering",
        function(lvl)
            for _=1,lvl do
                add(mines,mine.new(rnd(10)-5,rnd(10)-5))
                mines[#mines].z=0 -- grounded so they draw fully
            end
        end,
        function(lvl)
            -- no update, just keep them alive for draw
        end,
        {1,5,10,15,20,30}
    )

    -- test 5: full bomb event simulation
    -- mines falling + exploding + particles
    add_test(
        "bomb event (rate=0.7s, cap=100)",
        function(lvl) end,
        function(lvl)
            -- spawn mines at game rate
            if frame_count%flr(42*lvl)==0 then
                add(mines,mine.new(rnd(6)-3,rnd(6)-3))
            end
            for i=#mines,1,-1 do
                if not mines[i]:update() then
                    deli(mines,i)
                end
            end
            particle_sys:update(100)
        end,
        {1,0.5,0.33,0.25,0.16}
        -- rate multiplier: 1x=game rate, 0.5=2x faster...
    )

    -- test 6: draw_iso_ellipse cost
    add_test(
        "draw_iso_ellipse only",
        function(lvl) end,
        function(lvl) end, -- draw-only test
        {5,10,20,30,50,75}
    )

    -- header
    log("============================")
    log("horizon glide perf test")
    log("date: "..stat(91).."/"..stat(92).."/"..stat(90))
    log("60fps budget = 1.0 (100%)")
    log("============================")
    log("")

    status_msg="starting..."
end

function _update60()
    if done then return end

    if phase=="warmup" then
        local t=tests[cur_test]
        if frame_count==0 then
            clear_state()
            local lvl=t.levels[cur_level]
            status_msg=t.name.." [lvl "..cur_level.."/"..#t.levels..": "..lvl.."]"
            t.setup(lvl)
        end
        -- run tick during warmup too
        t.tick(t.levels[cur_level])
        frame_count+=1
        if frame_count>=warmup_frames then
            frame_count=0
            cpu_sum=0
            cpu_peak=0
            phase="sample"
        end

    elseif phase=="sample" then
        local t=tests[cur_test]
        local lvl=t.levels[cur_level]
        local c0=stat(1)
        t.tick(lvl)
        -- draw cost measured separately in _draw
        local cpu_frame=stat(1)-c0
        cpu_sum+=cpu_frame
        cpu_peak=max(cpu_peak,cpu_frame)
        frame_count+=1

        if frame_count>=sample_frames then
            phase="next"
        end

    elseif phase=="next" then
        -- record result
        local t=tests[cur_test]
        local lvl=t.levels[cur_level]
        local avg=cpu_sum/sample_frames
        local pcount=#particle_sys.list
        local mcount=#mines

        local r={
            test=t.name,
            level=lvl,
            avg_update=avg,
            peak_update=cpu_peak,
            particles=pcount,
            mines_active=mcount
        }
        add(results,r)

        log(t.name.." | lvl="..lvl
            .." | upd_avg="..pct(avg).."%"
            .." | upd_peak="..pct(cpu_peak).."%"
            .." | particles="..pcount
            .." | mines="..mcount)

        -- advance
        cur_level+=1
        if cur_level>#t.levels then
            log("")
            cur_test+=1
            cur_level=1
        end
        if cur_test>#tests then
            phase="done"
            log("============================")
            log("all tests complete")
            log("============================")
            done=true
            status_msg="done! check console"
        else
            frame_count=0
            phase="warmup"
        end
    end
end

-- separate draw cost tracking
draw_cpu=0

function _draw()
    local d0=stat(1)
    cls(0)

    -- draw mines
    for m in all(mines) do
        m:draw()
    end

    -- draw particles
    particle_sys:draw()

    -- test 6 special: draw ellipses directly
    if not done and cur_test<=#tests and tests[cur_test].name=="draw_iso_ellipse only" then
        local n=tests[cur_test].levels[cur_level] or 0
        for _=1,n do
            draw_iso_ellipse(64+rnd(40)-20,64+rnd(40)-20,24,12,8,0.04)
        end
    end

    draw_cpu=stat(1)-d0

    -- status hud
    rectfill(0,0,127,52,0)
    print("horizon glide perf test",1,1,7)
    print("",1,7)

    if done then
        print("all tests complete!",1,14,11)
        print("results printed to console",1,22,6)
        print("press esc to view",1,28,10)
    else
        print("test "..cur_test.."/"..#tests.." lvl "..cur_level,1,14,6)
        print(status_msg,1,21,10)
        print("phase: "..phase.." ("..frame_count.."/"..sample_frames..")",1,28,5)
        print("particles: "..#particle_sys.list.."  mines: "..#mines,1,35,6)

        -- live cpu
        local total=stat(1)
        print("cpu: "..pct(total).."%",1,42,total>0.5 and 8 or total>0.3 and 9 or 11)

        -- progress bar
        local done_tests=(cur_test-1)
        for i=1,cur_test-1 do end
        local total_levels=0
        local done_levels=0
        for i=1,#tests do
            total_levels+=#tests[i].levels
            if i<cur_test then
                done_levels+=#tests[i].levels
            elseif i==cur_test then
                done_levels+=cur_level-1
            end
        end
        local pbar=flr(done_levels/total_levels*126)
        rectfill(1,50,127,52,1)
        rectfill(1,50,1+pbar,52,11)
    end
end
__gfx__

__sfx__

__music__
