pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- HORIZON GLIDE
-- An infinite isometric racing game

-- Helper functions
function dist_trig(dx, dy) local ang = atan2(dx, dy) return dx * cos(ang) + dy * sin(ang) end
function iso(x,y) return cam_offset_x+(x-y)*half_tile_width, cam_offset_y+(x+y)*half_tile_height end


function fmt2(n)
    local s=flr(n*100+0.5)
    local neg=s<0 if(neg)s=-s
    return(neg and"-"or"")..flr(s/100).."."..sub("0"..(s%100),-2)
end

function opt_text(o)
    return o.name..": "..(o.is_seed and current_seed or tostr(o.values[o.current]))
end

function draw_triangle(l,t,c,m,r,b,col)
    while t>m or m>b do
        l,t,c,m=c,m,l,t
        while m>b do c,m,r,b=r,b,c,m end
    end
    local e,j=l,(r-l)/(b-t)
    while m do
        local i=(c-l)/(m-t)
        for y=flr(t),min(flr(m)-1,127) do
        line(l,y,e,y,col)
        l+=i e+=j
        end
        l,t,m,c,b=c,m,b,r
    end
end

function draw_all(t)   for o in all(t) do o:draw()   end end
function update_all(t) for o in all(t) do o:update() end end
function prune_update(t) for i=#t,1,-1 do if not t[i]:update() then deli(t,i) end end end
function draw_iso_ellipse(sx,sy,rx,ry,col,step)for a=0,1,step do pset(sx+cos(a)*rx,sy+sin(a)*ry,col)end end

function draw_circle_arrow(tx,ty,col)
    local px,py=player_ship.x,player_ship.y
    local dx,dy=tx-px,ty-py
    if dx*dx+dy*dy<4 then return end

    -- oscillating orbit distance
    local orbit_dist,a=1.5+sin(time()*1.5)*.2,atan2(dx,dy)
    local sx,sy=iso(px+cos(a)*orbit_dist,py+sin(a)*orbit_dist)
    sy-=player_ship.current_altitude*block_h

    -- screen-facing angle from iso delta
    local sa=atan2((dx-dy)*half_tile_width,(dx+dy)*half_tile_height)

    -- arrow triangle
    local s,b=7,sa+0.5
    draw_triangle(sx+cos(sa)*s,sy+sin(sa)*s*0.5,sx+cos(b-0.18)*s*.7,sy+sin(b-0.18)*s*.35,sx+cos(b+0.18)*s*.7,sy+sin(b+0.18)*s*.35,col)
end


-- terrain color lookup tables (top, side, dark triplets; height thresholds)
TERRAIN_PAL_STR = "\1\0\0\12\1\1\15\4\2\3\1\0\11\3\1\4\2\0\6\5\0\7\6\5"
TERRAIN_THRESH = split"-2,0,2,6,12,18,24,99"

function terrain(x,y)
    x,y=flr(x),flr(y)
    local row=cell_cache[x]
    local c=row and row[y]
    if c then return unpack(c) end
    return 1,0,0,0
end

function terrain_h(x,y,clamp)
    local _,_,_,h=terrain(x,y)
    return clamp and max(0,h) or h
end



-- MAIN PICO-8 FUNCTIONS
function _init()
    music(32,0,14)

    palt(0,false) palt(14,true)

    -- state + startup
    game_state,startup_phase="startup","title"
    startup_timer,startup_view_range=0,0
    title_x1,title_x2=-64,128

    -- camera + tile constants (needed before tile_manager)
    cam_offset_x,cam_offset_y=64,64
    view_range,half_tile_width,half_tile_height,block_h=0,12,6,2

    -- containers & cursors
    collectibles,floating_texts,ws,customization_panels={},{},{},{}
    customize_cursor=1

    -- player
    player_ship=ship.new(0,0)
    player_ship.is_hovering=true

    -- game manager
    game_manager=gm.new()

    -- menu options (MUST be set before any terrain() call)
    menu_options={
        {name="sCALE",  values=split"8,10,12,14,16", current=2},
        {name="wATER",  values=split"-4,-3,-2,-1,0,1,2,3,4", current=4},
        {name="sEED",   values={}, current=1, is_seed=true},
        {name="rANDOM", is_action=true},
    }

    -- terrain + tiles (terrain() uses menu_options)
    current_seed=1337
    terrain_perm,cell_cache=generate_permutation(current_seed),{}


    tile_manager:init()
    tile_manager:update_player_position(0,0)

    -- set ship altitude after tiles/terrain exist
    player_ship:set_altitude()

    -- top/right UI (no ui_typing_started needed)
    ui_msg,ui_vis,ui_until,ui_col,ui_rmsg="",0,0,7,""
    ui_box_h,ui_box_target_h=6,6
end





function _update60()
    if game_state=="startup" then
        -- intro timer + gentle drift
        startup_timer+=1
        player_ship.vy=-0.1
        player_ship.y+=player_ship.vy

        -- face along motion
        player_ship.angle=atan2(player_ship.vx-player_ship.vy,(player_ship.vx+player_ship.vy)*0.5)

        -- hover-lock to terrain
        player_ship:set_altitude()
        player_ship.is_hovering=true

        -- stream tiles
        tile_manager:update_player_position(player_ship.x,player_ship.y)

        -- ambient particles
        if startup_timer%3==0 then player_ship:spawn_particles(1,0) end

        -- camera snaps to ship
        local tx,ty=player_ship:get_camera_target()
        cam_offset_x,cam_offset_y=tx,ty

        -- phase logic
        if startup_phase=="title" then
            if startup_view_range<8 then
                startup_view_range+=0.5
                view_range=flr(startup_view_range)
                tile_manager.target_margin=view_range+2
            end
            if(title_x1<20)title_x1+=6
            if(title_x2>68)title_x2-=6
            if startup_view_range>=8 and title_x1>=20 and title_x2<=68 then
                startup_phase="menu_select"
                init_menu_select()
            end
        elseif startup_phase=="menu_select" then
            update_menu_select()
        else
            update_customize()
        end

    elseif game_state=="game" then
        if player_ship.dead then
            -- enter new death flow once
            enter_death()
        else
            player_ship:update()
            game_manager:update()
            local tx,ty=player_ship:get_camera_target()
            cam_offset_x+= (tx-cam_offset_x)*0.3
            cam_offset_y+= (ty-cam_offset_y)*0.3
        end

        update_projectiles()
        manage_collectibles()
        prune_update(floating_texts)
        prune_update(mines)

        if game_manager.display_score<game_manager.player_score then
            local diff=game_manager.player_score-game_manager.display_score
            game_manager.display_score+=diff<10 and diff or flr((diff+9)/10)
        end

        ui_tick()
    else -- "death"
        update_death()
    end

    particle_sys:update()
    tile_manager:manage_cache()
end





function _draw()
    if game_state=="startup" then
        draw_startup()
    elseif game_state=="game" then
        draw_game()
    else -- "death"
        draw_death()
    end
end



-- death flow (digital break effect)
function enter_death()
    music(34)
    game_state,death_t,death_cd="death",time(),10
    death_phase,death_closed_at=0,nil
    ui_msg,ui_rmsg,ui_box_target_h="","",6
end

function update_death()
    local el=time()-death_t

    -- transition to black screen phase after 2.5 seconds
    if death_phase==0 and el>2.5 then
        death_phase,death_closed_at=1,time()
    end

    if death_phase==2 and btnp(❎) then init_game() return end
    if time()-death_t>death_cd then _init() end
end

function draw_death()
    local el=time()-death_t

    -- digital break effect phase
    if death_phase==0 then
        -- draw the game world first
        cls(1)
        draw_world()
        -- horizontal tears
        if el>0.2 then
            for _=1,el*5 do
                local y,h,shift=flr(rnd(128)),1+flr(rnd(3)),flr(rnd(20))-10

                -- shift this horizontal band
                for dy=0,h-1 do
                    if y+dy<128 then
                        for x=0,127 do
                            local src_x=(x-shift)%128
                            local c=pget(src_x,y+dy)
                            pset(x,y+dy,c)
                        end
                    end
                end
            end
        end

        -- digital artifacts (blocks)
        if el>0.8 then
            local blocks=(el-0.8)*50
            for _=1,blocks do
                local x,y,c=flr(rnd(16))*8,flr(rnd(16))*8,rnd()<el/3 and 0 or flr(rnd(16))
                rectfill(x,y,x+7,y+7,c)
            end
        end

        -- black takeover
        if el>1.5 then
            local pct=(el-1.5)*3000
            for _=1,pct do
                pset(flr(rnd(128)),flr(rnd(128)),0)
            end
        end

    -- fully black -> show death screen UI
    else
        cls(0)

        -- wait half second before showing UI
        local t=time()-death_closed_at
        if t<0.5 then return end

        death_phase=2  -- mark UI as shown, enable restart
        local cx=64

        -- score (top)
        local s="score: "..flr(game_manager.player_score)
        print(s,cx-#s*2,30,7)

        -- face (center) with pink transparent + eye crackle
        palt(14,true) palt(0,false)
        if t<3 then if rnd()<0.4 then pal(8,0) end else pal(8,0) end
        local fx,fy=cx-12,64-12
        spr(64,fx,fy,3,3)
        pal()

        -- continue (bottom)
        local c=flr(max(0,death_cd-(time()-death_t))+0.99)
        local msg="continue? ("..c..")  ❎"
        print(msg,cx-#msg*2,92,6)
    end
end






function draw_minimap(x,y)
    local ms,step=44,64/44  -- (wr*2)/ms with wr=32
    local start_wx,start_wy=player_ship.x-32,player_ship.y-32
    rectfill(x-1,y-1,x+ms,y+ms,0)  -- background

    -- raster terrain
    for py=0,ms-1 do
        local wy=flr(start_wy+py*step)
        for px=0,ms-1 do
            pset(x+px,y+py, terrain(flr(start_wx+px*step), wy))
        end
    end

    -- view box
    local cx,cy=x+ms/2,y+ms/2
    local vb=ms*view_range/32
    rect(cx-vb/2,cy-vb/2,cx+vb/2,cy+vb/2,7)

    -- player dot
    circfill(cx,cy,1,8)
end



function draw_startup()
    cls(1)
    draw_world()

    -- title wave
    local t=time()*50
    for s=0,1 do
        local sp,x,y,w=s==0 and 69 or 85,s==0 and title_x1 or title_x2,s==0 and 10 or 20,s==0 and 64 or 48
        for i=0,w-1 do
            local d=abs(i-t%(w+40)+20)
            sspr((sp%16)*8+i,flr(sp/16)*8,1,8,x+i,y-(d<20 and cos(d*0.025)*2 or 0))
        end
    end

    -- ui
    if startup_phase=="menu_select" then
        play_panel:draw() customize_panel:draw()
    elseif startup_phase=="customize" then
        draw_all(customization_panels)
        draw_minimap(82,32)
    end
end



function init_menu_select()
    play_panel = panel.new(-50, 90, nil, nil, "play", 11)
    play_panel.selected = true
    play_panel:set_position(50, 90)

    customize_panel = panel.new(128, 104, nil, nil, "customize", 12)
    customize_panel:set_position(40, 104)
end


function update_customize()
    -- update all panels
    update_all(customization_panels)

    -- navigation
    local d=(btnp(⬆️) and -1) or (btnp(⬇️) and 1) or 0
    if d!=0 then
        sfx(57)
        customization_panels[customize_cursor].selected=false
        customize_cursor=(customize_cursor+d-1)%#customization_panels+1
        customization_panels[customize_cursor].selected=true
    end

    local p=customization_panels[customize_cursor]
    if p.is_start then
        if btnp(❎) then sfx(57) view_range=8 init_game() end
        return
    end

    local idx=p.option_index
    if not idx then return end
    local o=menu_options[idx]

    -- randomize all
    if o.is_action then
        if btnp(❎) then
            sfx(57)
            menu_options[1].current=flr(rnd(#menu_options[1].values))+1
            menu_options[2].current=flr(rnd(#menu_options[2].values))+1
            current_seed=flr(rnd(9999))
            for q in all(customization_panels) do
                if q.option_index then
                    local oo=menu_options[q.option_index]
                    q.text=oo.is_action and "random" or opt_text(oo)
                end
            end
            regenerate_world_live()
        end
        return
    end

    -- left/right adjustments
    local lr=(btnp(⬅️) and -1) or (btnp(➡️) and 1) or 0
    if lr==0 then return end
    sfx(57)

    if o.is_seed then
        current_seed=(current_seed+lr)%10000
        p.text=opt_text(o)
    else
        o.current=(o.current+lr-1)%#o.values+1
        p.text=opt_text(o)
    end
    regenerate_world_live()
end




function regenerate_world_live()
    terrain_perm,cell_cache=generate_permutation(current_seed),{}
    tile_manager.cur_margin=0
    tile_manager:update_player_position(player_ship.x,player_ship.y)
    for _=1,view_range+2 do tile_manager:manage_cache() end
    player_ship:set_altitude()
end


function update_menu_select()
    -- update panels
    update_all{play_panel, customize_panel}

    -- toggle selection with up/down
    if btnp(⬆️) or btnp(⬇️) then
        sfx(57)
        play_panel.selected,customize_panel.selected=not play_panel.selected,not customize_panel.selected
    end

    -- confirm
    if btnp(❎) then
        sfx(57)
        if play_panel.selected then
            view_range=8
            init_game()
        else
            enter_customize_mode()
        end
    end
end


function enter_customize_mode()
    startup_phase="customize" customize_cursor=1 customization_panels={}

    -- temporarily expand cache margin for minimap (need るね32 tiles)
    tile_manager.target_margin=32
    tile_manager:update_player_position(player_ship.x,player_ship.y)

    local y_start,y_spacing,delay_step=32,12,2
    local panel_index=0

    for i=1,#menu_options do
        local o=menu_options[i]
        local y=y_start+panel_index*y_spacing
        local text=o.is_action and "random" or opt_text(o)
        local col=o.is_action and 5 or 6
        local p=panel.new(-60,y,68,9,text,col)
        p.option_index=i p.anim_delay=panel_index*delay_step
        p:set_position(6,y) add(customization_panels,p)
        panel_index+=1
    end

    local sb=panel.new(50,128,nil,12,"play",11)
    sb.is_start=true sb.anim_delay=(panel_index+1)*delay_step+4
    sb:set_position(50,105) add(customization_panels,sb)

    customization_panels[1].selected=true
end







-- GAME FUNCTIONS
function init_game()
    music(0)
    pal() palt(0,false) palt(14,true)
    tile_manager.target_margin,game_state=view_range+2,"game"
    floating_texts,particle_sys.list,mines,projectiles,enemies,collectibles={},{},{},{},{},{}
    game_manager:reset()
    player_ship.dead,player_ship.hp,player_ship.last_shot_time=false,player_ship.max_hp,time()+0.5
    tile_manager:update_player_position(player_ship.x, player_ship.y)
    player_ship:set_altitude()
    ui_msg,ui_vis,ui_until,ui_rmsg="",0,0,""
    for _=1,8 do
        local a,d=rnd(),15+rnd(20)
        add(collectibles,collectible.new(cos(a)*d,sin(a)*d))
    end
end




function draw_world()
    local px,py=flr(player_ship.x),flr(player_ship.y)
    local htw,hth,co_x,co_y,bh=half_tile_width,half_tile_height,cam_offset_x,cam_offset_y,block_h
    local cc=cell_cache
    local vr=view_range
    local t_val=time()

    -- draw water
    for x=px-vr,px+vr do
        local row=cc[x]
        if row then
            for y=py-vr,py+vr do
                local t=row[y]
                if t and t[4]<=0 then
                    local sx,sy=co_x+(x-y)*htw,co_y+(x+y)*hth
                    if sx>-htw and sx<128+htw and sy>-hth and sy<128+hth then
                        diamond(sx,sy,t[1])
                        local yb=flr(sy+((x+y)&1)+sin(t_val+(x+y)/8))
                        line(sx-htw,yb,sx+htw,yb,(t[4]<=-2) and 12 or 1)
                    end
                end
            end
        end
    end

    -- water rings (update + draw)
    for i=#ws,1,-1 do
        local s=ws[i]
        s.r+=0.18 s.life-=1
        local lx,ly
        for a=0,1,0.06 do
            local wx,wy=s.x+cos(a)*s.r,s.y+sin(a)*s.r
            local h=terrain_h(flr(wx),flr(wy))
            if h<=0 then
                local rx,ry=iso(wx,wy)
                if lx then line(lx,ly,rx,ry,(h<=-2) and 12 or 7) end
                lx,ly=rx,ry
            else lx=nil end
        end
        if s.life<=0 then deli(ws,i) end
    end

    -- draw land
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
                            diamond(sx,sy2,t[1])
                        end
                    end
                end
            end
        end
    end

    -- fx + ship
    particle_sys:draw()
    draw_all(collectibles)
    if not player_ship.dead then player_ship:draw() end
end



function draw_game()
    cls(1)
    draw_world()

    -- projectiles
    for p in all(projectiles) do
        local sx,sy=iso(p.x,p.y) sy-=p.z*block_h
        circfill(sx,sy,2,0)
        circfill(sx,sy,1,p.owner.is_enemy and 8 or 12)
    end

    -- target cursor
    if not player_ship.dead and player_ship.target and player_ship.target.get_screen_pos then
        local tx,ty=player_ship.target:get_screen_pos()
        rect(tx-8,ty-8,tx+8,ty+8,8)
    end

    -- floating texts
    draw_all(floating_texts)

    -- mines
    draw_all(mines)

    -- current event visuals (arrows on top)
    if game_manager.state=="active" and game_manager.current_event then
        game_manager.current_event:draw()
    end

    -- ui (top + bottom)
    draw_ui()
end




function draw_segmented_bar(x, y, value, max_value, filled_col, empty_col)
    local filled=flr(value*15/max_value)
    for i=0,14 do
        local s=x+i*4
        rectfill(s,y,s+2,y+1,(i<filled) and filled_col or empty_col)
    end
end

function draw_ui()
    -- top HUD
    sspr(0,0,128,16,0,0,128,16)

    -- Box
    local h = flr(ui_box_h)
    rrectfill(100,1,27,h-1,2,0)

    -- Always draw green lines
    if h > 3 then
        -- Horizontal lines
        for y=3,h-2,4 do
            line(101,y,125,y,3)
        end
        -- Vertical lines
        for x=104,124,6 do
            line(x,2,x,h-1,3)
        end
    end

    -- Only draw sprite when expanded enough
    if h > 25 then
        spr(64,102,3,3,3)
        if ui_msg!="" then
            -- Mouth animation
            if (time()*8)%2<1 then spr(99,110,19) end
            -- Text
            print(sub(ui_msg,1,ui_vis),4,3,ui_col)
        end
    end

    -- Draw border last
    rrect(100,1,27,h-1,2,12)

    -- Timer outside box (no expansion needed)
    if ui_rmsg!="" and ui_msg=="" then
        print(ui_rmsg,4,3,10)
    end

    -- bottom HUD
    sspr(0,16,128,16,0,112)
    draw_segmented_bar(5,117,player_ship.hp,100,player_ship.hp>30 and 11 or 8,5)
    draw_segmented_bar(5,120,player_ship.ammo,player_ship.max_ammo,12,5)
    draw_segmented_bar(5,123,player_ship.mines,player_ship.max_mines,9,5)

    local score_text = sub("00000"..flr(game_manager.display_score),-6)
    print(score_text, 125 - #score_text * 4, 120, 10)
end




-- FLOATING TEXT CLASS
floating_text = {}
floating_text.__index = floating_text

function floating_text.new(x, y, text, col)
    return setmetatable({
        x = x,
        y = y,
        text = text,
        col = col or 7,
        life = 60,
        vy = -1,
    }, floating_text)
end

function floating_text:update()
    self.y+=self.vy
    self.vy*=0.95  -- slow down over time
    self.life-=1
    return self.life>0
end

function floating_text:draw()
    local w,x1=#self.text*4,self.x-#self.text*2
    rrectfill(x1-1,self.y-1,w+2,7,1,0)
    print(self.text,x1,self.y,self.col)
end

-- PANEL CLASS
panel = {}
panel.__index = panel

function panel.new(x,y,w,h,text,col)
    return setmetatable({
        x=x,y=y,
        w=w or (#text*4+12),
        h=h or 9,
        text=text,
        col=col or 5,
        selected=false,
        expand=0,
        target_x=x, target_y=y,
        anim_delay=0,
    },panel)
end

function panel:set_position(x,y,instant)
    self.target_x,self.target_y=x,y
    if instant then self.x,self.y=x,y end
end


function panel:update()
    if self.anim_delay>0 then self.anim_delay-=1 return true end

    -- smooth move
    self.x+=(self.target_x-self.x)*0.2
    self.y+=(self.target_y-self.y)*0.2
    if abs(self.x-self.target_x)<0.5 then self.x,self.y=self.target_x,self.target_y end

    -- expand/contract
    self.expand=self.selected and min(self.expand+1,3) or max(self.expand-1,0)
    return true
end



-- draw function remains the same
function panel:draw()
    -- position + size (include expand)
    local dx,dy,dw,dh=self.x-self.expand,self.y,self.w+self.expand*2,self.h

    -- bg + border
    rrectfill(dx-1,dy-1,dw+2,dh+2,2,self.col)
    rrectfill(dx,dy,dw,dh,2,0)

    -- centered text
    local tx,ty,tcol=dx+(dw-#self.text*4)/2,dy+(dh-5)/2,self.selected and self.col or 7
    print(self.text, tx, ty, tcol)

    -- draw arrows for option panels (but not action buttons)
    if self.option_index then
        local opt=menu_options[self.option_index]
        if not opt.is_action then
            print("⬅️", dx+2, ty, tcol)
            print("➡️", dx+dw-10, ty, tcol)
        end
    end
end


-- PARTICLE SYSTEM
particle_sys={list={}}

-- kind: 0=smoke, 1=blast (all use world coords)
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

-- SMOKE (world space)
function particle_sys:spawn(x,y,z,col,count)
    count=count or 1
    for _=1,count do
        local p=make_particle(
            x+(rnd()-.5)*.1,
            y+(rnd()-.5)*.1,
            z,
            (rnd()-.5)*.05,
            (rnd()-.5)*.05,
            1+rnd(1),
            20+rnd(10),
            0,  -- smoke
            col or 0)
        p.vz=-rnd()*0.3-0.2
        add(self.list,p)
    end
end

-- EXPLOSIONS
function particle_sys:explode(wx,wy,z,scale)
    local function add_group(radius,speed,size_px,life,count)
        for _=1,count do
            -- Create particles in world space with world velocities
            local angle = rnd()
            local dist = rnd() * radius * scale * 0.1  -- convert pixel radius to world units
            local vel = rnd() * speed * scale * 0.01   -- convert pixel speed to world units
            
            add(self.list, make_particle(
                wx + cos(angle) * dist,
                wy + sin(angle) * dist,
                z + rnd() * 0.5,  -- slight vertical variation
                cos(angle) * vel,
                sin(angle) * vel,
                size_px * scale,
                life,
                1))  -- all explosions are kind=1 (blast)
        end
    end
    -- core / medium / outer (fireballs)
    for i=1,3 do
        add_group(i*2+2,i*0.5,4-i+rnd(i==1 and 2 or 1),i*5+10,flr((4-i)*scale+(i==2 and scale or 0)))
    end
end

function particle_sys:update()
    for i=#self.list,1,-1 do
        local p=self.list[i]
        
        -- all particles use world physics
        p.x+=p.vx 
        p.y+=p.vy 
        p.z+=p.vz
        p.vx*=0.9 
        p.vy*=0.9 
        p.vz*=0.95
        
        p.life-=1
        if p.life<=0 then deli(self.list,i) end
    end
    while #self.list>100 do deli(self.list,1) end
end

function particle_sys:draw()
    for p in all(self.list) do
        -- ALL particles project from world to screen
        local screen_x,screen_y=iso(p.x,p.y) 
        screen_y+=p.z  -- z is in screen units (negative = up)
        
        if p.kind==0 then
            -- smoke rendering
            local alpha=p.life/p.max_life
            if alpha>0.5 then
                if p.size>1.5 then
                    circfill(screen_x,screen_y,1,p.col)
                else
                    pset(screen_x,screen_y,p.col)
                end
            elseif (alpha>0.25 and rnd()>0.3) or (alpha<=0.25 and rnd()>0.6) then
                pset(screen_x,screen_y,p.col)
            end
        else
            -- blast rendering (kind==1)
            local alpha=p.life/p.max_life
            circfill(screen_x,screen_y,p.size,alpha<0.15 and 2 or alpha<0.3 and 8 or alpha<0.5 and 9 or alpha<0.8 and 10 or 7)
        end
    end
end




-- Game Manager
gm = {}
gm.__index = gm


function gm.new()
    local self=setmetatable({
        idle_duration=5,
        event_types={combat_event,circle_event,bomb_event},
        difficulty_rings_base=3,
        difficulty_rings_step=1,
        difficulty_base_time=10,
        difficulty_recharge_start=2,
        difficulty_recharge_step=0.1,
        difficulty_recharge_min=1,
        difficulty_level=0,
        tut=nil
    },gm)
    self:reset()
    return self
end

function gm:reset()
    self.state,self.current_event,self.idle_start_time="idle",nil,self.tut and time()-3 or nil
    self.next_event_index,self.player_score,self.display_score,self.difficulty_level=1,0,0,0
end

function gm:update()
    -- tutorial (minimal tokens)
    if not self.tut then
        -- Skip tutorial checks during grace period (reuse last_shot_time)
        if player_ship.last_shot_time > time() then
            return  -- skip everything during grace period
        end
        
        -- Track what player has done (persist across frames)
        self.tut_moved = self.tut_moved or btn(⬆️) or btn(⬇️) or btn(⬅️) or btn(➡️)
        self.tut_shot = self.tut_shot or btn(❎)
        self.tut_collected = self.tut_collected or player_ship.ammo > 50
        self.tut_mine = self.tut_mine or player_ship.mines < 7

        -- Check what hasn't been done yet (priority: move > shoot > collect > mine)
        local new_msg = nil
        if not self.tut_moved then
            new_msg = "aRROW KEYS TO MOVE"
        elseif not self.tut_shot then
            new_msg = "❎ tO sHOOT"
        elseif not self.tut_collected then
            new_msg = "cOLLECT aMMO"
        elseif not self.tut_mine then
            new_msg = "🅾️ tO dROP mINE"
        elseif not self.tut then
            self.tut=true
            ui_say("hORIZON gLIDE bEGINS!",2,11)
            self.idle_start_time=time()-3
            return
        else return end
        
        -- Only update UI if message changed
        if new_msg != self.tut_msg then
            self.tut_msg = new_msg
            local dur = (new_msg == "good luck!") and 2 or 99
            ui_say(new_msg, dur, 11)
        end
        return  -- skip events during tutorial
    end
    
    -- original update code
    if self.state=="idle" then
        if time()-self.idle_start_time>=self.idle_duration then
            self:start_random_event()
        end
    else
        local e=self.current_event
        if e then
            e:update()
            if player_ship.hp<=0 then
                e.completed,e.success,player_ship.dead,ui_rmsg=true,false,true,""
            end
            if e.completed then self:end_event(e.success) end
        end
    end
end

function gm:start_random_event()
    self.current_event=self.event_types[self.next_event_index].new()
    self.next_event_index=self.next_event_index%3+1
    self.state="active"
end

function gm:end_event(success)
    self.state="idle" self.idle_start_time=time() ui_rmsg=""
    if success or not(player_ship and player_ship.dead) then
        ui_say(success and "event complete!" or "event failed",3,success and 11 or 8)
    end
    if success and self.next_event_index==1 then
        self.difficulty_level+=1
    end
    self.current_event=nil
end





-- BOMB EVENT
bomb_event={}
bomb_event.__index=bomb_event

function bomb_event.new()
    ui_say("incoming bombs!",3,8)
    return setmetatable({
        bombs={},
        next_bomb=time(),
        end_time=time()+12,
        completed=false,
        success=false
    },bomb_event)
end

function bomb_event:update()
    if time()>self.end_time then
        self.completed,self.success=true,true
        game_manager.player_score+=800
        player_ship.mines=player_ship.max_mines
        pop("full mines!",-10,9)
        return
    end

    if time()>self.next_bomb then
        add(self.bombs,mine.new(
            player_ship.x+player_ship.vx*12,
            player_ship.y+player_ship.vy*12,
            nil
        ))
        self.next_bomb=time()+max(0.4,0.8-0.05*game_manager.difficulty_level)+rnd(0.3)
    end

    prune_update(self.bombs)
end

function bomb_event:draw()
    draw_all(self.bombs)
end


-- CIRCLE RACE EVENT
circle_event = {}
circle_event.__index = circle_event

function circle_event.new()
    local r=game_manager.difficulty_level
    local self=setmetatable({
        base_time=game_manager.difficulty_base_time,
        recharge_seconds=max(game_manager.difficulty_recharge_min,game_manager.difficulty_recharge_start-r*game_manager.difficulty_recharge_step),
        circles={},
        current_target=1
    },circle_event)

    local n=game_manager.difficulty_rings_base+r*game_manager.difficulty_rings_step
    for _=1,n do
        local a,d=rnd(1),8+rnd(4)
        add(self.circles,{x=player_ship.x+cos(a)*d,y=player_ship.y+sin(a)*d,radius=1.5,collected=false})
    end

    self.end_time=time()+self.base_time
    ui_say("cOLLECT "..#self.circles.." cIRCLES!",1.5,8)
    ui_rmsg=flr(self.base_time).."s"
    return self
end

function pop(text, dy, col)
    local sx,sy=player_ship:get_screen_pos()
    add(floating_texts, floating_text.new(sx, (sy+(dy or -10)), text, col))
end


function circle_event:update()
    local time_left=self.end_time-time()

    -- timeout -> fail
    if time_left<=0 then
        self.completed,self.success=true,false
        ui_say("event failed",1.5,8)
        ui_rmsg=""
        return
    end

    -- update right slot timer independently of left message
    ui_rmsg=fmt2(max(0,time_left)).."s"

    -- rings
    local circle=self.circles[self.current_target]
    if circle and not circle.collected then
        local dx,dy=player_ship.x-circle.x,player_ship.y-circle.y
        if dist_trig(dx,dy)<circle.radius then
            circle.collected=true
            sfx(59)
            player_ship.hp=min(player_ship.hp+10,player_ship.max_hp)

            -- bonus time (not on last)
            if self.current_target<#self.circles then
                self.end_time+=self.recharge_seconds
                pop("+"..fmt2(self.recharge_seconds).."s",-10)
                pop("+10hp",-20,11)
            end

            self.current_target+=1

            if self.current_target>#self.circles then
                -- success - full heal on completion
                player_ship.hp=player_ship.max_hp
                local award=#self.circles*100+500
                self.completed,self.success=true,true
                game_manager.player_score+=award
                pop("+"..award,-10,7)
                pop("full hp!",-20,11)
                ui_say("event complete!",1.5,11)
                ui_rmsg=""
            else
                -- progress message (right slot keeps updating separately)
                local remaining=#self.circles-self.current_target+1
                ui_say(remaining.." circle"..(remaining>1 and "s" or "").." left",1,10)
            end
        end
    end
end

function circle_event:draw()
    -- cache time for animation
    local t=time()

    -- draw all uncollected rings
    for i=1,#self.circles do
        local circle=self.circles[i]
        if not circle.collected then
            local sx,sy=iso(circle.x,circle.y)
            local cx,cy=flr(circle.x),flr(circle.y)
            local base_y=sy-terrain_h(cx,cy)*block_h

            -- highlight current target
            local cur=(i==self.current_target)
            local base_radius=10
            local col=cur and 10 or 9

            -- ring outline
            draw_iso_ellipse(sx,base_y,base_radius,base_radius*0.5,col,0.01)

            -- expanding rings on current target
            if cur then
                for ring=0,2 do
                    local z=(t*15+ring*8)%24
                    local r=base_radius*(1+z/24)
                    draw_iso_ellipse(sx,base_y-z,r,r*0.5,col,0.02)
                end
            end
        end
    end

    -- direction arrow to current target
    local target=self.circles[self.current_target]
    if target and not target.collected then
        draw_circle_arrow(target.x,target.y,9)
    end
end


-- COLLECTIBLES
collectible = {}
collectible.__index = collectible

function collectible.new(x, y)
    return setmetatable({x=x, y=y, collected=false}, collectible)
end

function collectible:update()
    if self.collected then return false end
    local dx,dy=player_ship.x-self.x,player_ship.y-self.y
    local dist2=dist_trig(dx,dy)
    if dist2>20 then return false end

    if dist2<1 then
        self.collected=true
        sfx(61)
        player_ship.ammo=min(player_ship.ammo+10,player_ship.max_ammo)
        pop("+10ammo",-10,12)
        game_manager.player_score+=25
        return false
    end

    return true
end

function collectible:draw()
    if not self.collected then
        local sx, sy = iso(self.x, self.y)
        local h = terrain_h(self.x, self.y) * block_h
        local float = sin(time() * 2 + self.x + self.y)
        ovalfill(sx-5, sy-h+3, sx+5, sy-h+5, 1)  -- shadow
        spr(67, sx - 8, sy - h - 8 + float, 2, 2)
    end
end

function manage_collectibles()
    -- remove far ones
    prune_update(collectibles)

    -- spawn new ones if needed
    while #collectibles < 15 do
        local a, d = rnd(), 8 + rnd(15)
        local x, y = player_ship.x + cos(a) * d, player_ship.y + sin(a) * d
        add(collectibles, collectible.new(x, y))
    end
end


-- MINE CLASS
mine={}
mine.__index=mine
function mine.new(x,y,owner)return setmetatable({x=x,y=y,owner=owner,z=owner and 0 or 60},mine)end
function mine:update()
    if self.z>0 then
        self.z-=4
        if self.z<=0 then self.z=0 end
        return true
    end
    if not self.owner then
        particle_sys:explode(self.x,self.y,-terrain_h(self.x,self.y,true)*block_h,1.5)
        sfx(62)
        if dist_trig(player_ship.x-self.x,player_ship.y-self.y)<2 then player_ship.hp-=15 end
        return false
    end
    for t in all(self.owner==player_ship and enemies or{player_ship})do
        if dist_trig(t.x-self.x,t.y-self.y)<2 then
            particle_sys:explode(self.x,self.y,-terrain_h(self.x,self.y,true)*block_h,1.5)
            t.hp-=15 sfx(62)
            return false
        end
    end
    return true
end
function mine:draw()
    local sx,sy=iso(self.x,self.y)
    local col=self.owner==player_ship and 12 or 8
    local gz=terrain_h(self.x,self.y,true)*block_h
    draw_iso_ellipse(sx,sy-gz,24,12,col,0.04)
    sy+=self.z>0 and -self.z or -gz
    local r=4+sin(time()*6+self.x+self.y)*1.5
    circfill(sx,sy,r,7)circfill(sx,sy,r/2,col)
end

-- SHIP CLASS
ship = {}
ship.__index = ship

function ship.new(start_x, start_y, is_enemy)
    return setmetatable({
        x = start_x,
        y = start_y,
        vx = 0,
        vy = 0,
        vz = 0,
        hover_height = 1,
        current_altitude = 0,
        angle = 0,
        accel = 0.05,
        friction = 0.9,
        max_speed = is_enemy and 0.32 or 0.4,
        projectile_speed = 0.4,
        projectile_life = 40,
        fire_rate = is_enemy and 0.15 or 0.1,
        size = 11,
        body_col = is_enemy and 8 or 12,
        outline_col = 7,
        shadow_col = 1,
        gravity = 0.2,
        max_climb = 3,
        is_hovering = false,
        particle_timer = 0,
        ramp_boost = 0.2,
        -- combat
        is_enemy = is_enemy,
        max_hp = is_enemy and 50 or 100,
        hp = is_enemy and 50 or 1,
        target = nil,
        ai_phase = is_enemy and rnd(6) or 0,
        max_ammo = is_enemy and 9999 or 100,
        ammo = is_enemy and 9999 or 50,
        mines = is_enemy and 9999 or 7,
        max_mines = is_enemy and 9999 or 15,
        last_shot_time = 0,
        -- AI state machine
        ai_state = is_enemy and "approach" or nil,
        charge_timer = 0
    }, ship)
end

function ship:set_altitude()
    self.current_altitude = terrain_h(self.x, self.y, true) + self.hover_height
end

function ship:ai_update()
    local dx,dy=player_ship.x-self.x,player_ship.y-self.y
    local dist=dist_trig(dx,dy)

    -- chase/flee mode (health ratio check)
    local q=self.hp/self.max_hp
    local mode=(q<=0.3 and dist>15) or (q>0.3 and (dist>20 or ((time()+self.ai_phase)%6)<3))
    if not mode then dx,dy=-dx,-dy end

    -- separation
    for e in all(enemies) do
        if e~=self then
            local ex,ey=self.x-e.x,self.y-e.y
            local d=dist_trig(ex,ey)
            if d<4 then local w=4-d dx+=ex*w dy+=ey*w end
        end
    end

    -- steer toward chosen vector
    local m=dist_trig(dx,dy)
    if m>0.1 then self.vx+=dx*self.accel/m self.vy+=dy*self.accel/m end

    local t=time()
    -- fire (instant for relentless combat)
    if mode and self:update_targeting() and (not self.last_shot_time or t-self.last_shot_time>self.fire_rate) then
        self:fire_at()
        self.last_shot_time=t
    end

    -- drop mine when fleeing
    if not mode and dist<8 and (not self.last_mine_time or t-self.last_mine_time>1) then
        add(mines,mine.new(self.x,self.y,self))
        self.last_mine_time=t
    end
end




function ship:fire_at()
    if not self.target then return end
    
    if self.ammo<=0 then
        if not self.is_enemy and (not self.last_no_ammo_msg or time()-self.last_no_ammo_msg>2) then
            ui_say("no ammo!",2,8)
            self.last_no_ammo_msg=time()
        end
        return
    end
    
    local dx, dy = self.target.x - self.x, self.target.y - self.y
    local dist = dist_trig(dx, dy)
    
    add(projectiles, {
        x = self.x,
        y = self.y,
        z = self.current_altitude,
        vx = self.vx + dx/dist * self.projectile_speed,
        vy = self.vy + dy/dist * self.projectile_speed,
        life = self.projectile_life,
        owner = self,
    })
    self.ammo-=1
    sfx(63)
end

function ship:update_targeting()
    local fx,fy=cos(self.angle),sin(self.angle)
    local best,found=15,nil
    local list=self.is_enemy and {player_ship} or enemies
    for t in all(list) do
        if t~=self then
            local dx,dy=t.x-self.x,t.y-self.y
            local d=dist_trig(dx,dy)
            if d<best and (dx*fx+dy*fy)>.5*d then best=d found=t end
        end
    end
    if found then self.target=found return true end
    local world_angle = atan2(self.vx, self.vy)
    self.target = self.is_enemy and nil or {x=self.x+cos(world_angle)*10,y=self.y+sin(world_angle)*10}
    return false
end


function ship:update()
    -- AI or player
    if self.is_enemy then
        self:ai_update()
    else
        tile_manager:update_player_position(self.x,self.y)

        -- player input (iso mapping via rx/ry)
        local rx=(btn(➡️) and 1 or 0)-(btn(⬅️) and 1 or 0)
        local ry=(btn(⬇️) and 1 or 0)-(btn(⬆️) and 1 or 0)
        self.vx+=(rx+ry)*self.accel*0.707
        self.vy+=(-rx+ry)*self.accel*0.707

        -- targeting & fire
        self:update_targeting()
        if btn(❎) and (not self.last_shot_time or time()-self.last_shot_time>self.fire_rate) then
            self:fire_at()
            self.last_shot_time=time()
        end
        -- drop mine
        if btnp(🅾️) and self.mines>0 then
            add(mines,mine.new(self.x,self.y,self))
            self.mines-=1
            sfx(60)
        end
    end

    -- movement & clamp
    self.vx*=self.friction self.vy*=self.friction
    local speed=dist_trig(self.vx,self.vy)
    local s=(speed>self.max_speed) and (self.max_speed/speed) or 1
    self.vx*=s self.vy*=s
    self.x+=self.vx self.y+=self.vy

    -- terrain ramp launch
    local new_terrain=terrain_h(self.x,self.y)
    local height_diff=new_terrain-terrain_h(self.x-self.vx,self.y-self.vy)
    if self.is_hovering and height_diff>0 and speed>0.01 then
        self.vz=min(height_diff*self.ramp_boost*speed*15, 1.5)  -- cap vertical velocity
        self.is_hovering=false
    end

    -- altitude physics
    local target_altitude=new_terrain+self.hover_height
    if self.is_hovering then
        self.current_altitude=target_altitude self.vz=0
    else
        self.current_altitude+=self.vz
        self.vz-=self.gravity
        if self.current_altitude<=target_altitude then
            self.current_altitude=target_altitude self.vz=0 self.is_hovering=true
        end
        self.vz*=0.98
    end

    -- exhaust particles
    if self.is_hovering and speed>0.01 then
        self.particle_timer+=1
        local spawn_rate=max(1,5-flr(speed*10))
        if self.particle_timer>=spawn_rate then
            self.particle_timer=0
            self:spawn_particles(1+flr(speed*5))
        end
    else
        self.particle_timer=0
    end

    -- facing (always compute; cheaper than guarding)
    self.angle=atan2(self.vx-self.vy,(self.vx+self.vy)*0.5)

    -- water rings
    if self.is_hovering and speed>0.2 then
        self.st=(self.st or 0)+1
        if self.st>4 then add(ws,{x=self.x,y=self.y,r=0,life=28}) self.st=0 end
    end
end



function ship:get_screen_pos()
    local screen_x, screen_y = iso(self.x, self.y)
    return screen_x, screen_y - self.current_altitude * block_h
end


function ship:get_camera_target()
    local fx,fy=self.x,self.y
    if not self.is_enemy then
        local best,ne=10
        for e in all(enemies) do
            local d=dist_trig(e.x-fx,e.y-fy)
            if d<best then best=d ne=e end
        end
        self.cam_blend=(self.cam_blend or 0)+(ne and 0.02 or -0.03)
        self.cam_blend=mid(0,self.cam_blend,0.2)
        if ne and self.cam_blend>0 then 
            fx+=(ne.x-fx)*self.cam_blend 
            fy+=(ne.y-fy)*self.cam_blend 
        end
    end
    local sx=(fx-fy)*half_tile_width
    local sy=(fx+fy)*half_tile_height - self.current_altitude*block_h
    return 64-sx,64-sy
end



function ship:draw()
    local sx, sy = self:get_screen_pos()
    local ship_len = self.size * 0.8
    local half_ship_len = ship_len * 0.5

    -- tip + rear corners
    local fx, fy = sx + cos(self.angle) * ship_len, sy + sin(self.angle) * half_ship_len
    local back_angle = self.angle + 0.5
    local p2x = sx + cos(back_angle - 0.15) * ship_len
    local p2y = sy + sin(back_angle - 0.15) * half_ship_len
    local p3x = sx + cos(back_angle + 0.15) * ship_len
    local p3y = sy + sin(back_angle + 0.15) * half_ship_len

    -- shadow
    local terrain_height = terrain_h(self.x, self.y)
    local shadow_offset = (self.current_altitude - terrain_height) * block_h
    draw_triangle(fx, fy + shadow_offset, p2x, p2y + shadow_offset, p3x, p3y + shadow_offset, self.shadow_col)

    -- body
    draw_triangle(fx, fy, p2x, p2y, p3x, p3y, self.body_col)

    -- outline
    line(fx,  fy,  p2x, p2y, self.outline_col)
    line(p2x, p2y, p3x, p3y, self.outline_col)
    line(p3x, p3y, fx,  fy,  self.outline_col)

    -- thrusters
    if self.is_hovering then
        local c = (sin(time() * 5) > 0) and 10 or 9
        pset(p2x, p2y, c)
        pset(p3x, p3y, c)
    end

    -- enemy health bar
    if self.is_enemy then
        local w = self.hp / self.max_hp * 10
        rectfill(sx - 5, sy - 10, sx + 5, sy - 9, 5)
        rectfill(sx - 5, sy - 10, sx - 5 + w, sy - 9, 8)
    end
end


function ship:spawn_particles(num, col_override)
    -- spawn exhaust particles at the ship's position
    particle_sys:spawn(
        self.x, self.y,
        -self.current_altitude * block_h,
        col_override or (terrain_h(self.x,self.y) <= 0 and 7 or 0),
        num
    )
end

function update_projectiles()
    for i=#projectiles,1,-1 do
        local p=projectiles[i]
        p.x+=p.vx p.y+=p.vy p.life-=1

        local targets=p.owner.is_enemy and {player_ship} or enemies
        for t in all(targets) do
            local dx,dy=t.x-p.x,t.y-p.y
            if dx*dx+dy*dy<0.5 then
                t.hp-=3
                sfx(58)
                p.life=0
                particle_sys:explode(p.x,p.y,-t.current_altitude*block_h,0.8)
                if t.hp<=0 then
                    sfx(62)
                    particle_sys:explode(t.x,t.y,-t.current_altitude*block_h,3)
                    if t.is_enemy then
                        del(enemies,t)
                        game_manager.player_score+=200
                    end
                end
            end
        end

        if p.life<=0 then deli(projectiles,i) end
    end
end


function ui_say(t,d,c)
    ui_msg=t
    ui_vis,ui_col,ui_until,ui_box_target_h= 0,(c or 7),(d and time()+d or 0),26
end


function ui_tick()
    -- tween box height (only expand for actual messages, not timer)
    ui_box_h+=(ui_box_target_h-ui_box_h)*0.2
    if abs(ui_box_h-ui_box_target_h)<0.5 then ui_box_h=ui_box_target_h end

    -- nothing to type yet or box not expanded
    if ui_msg=="" or ui_box_h<=25 then return end

    -- typewriter
    if ui_vis < #ui_msg then
        ui_vis = min(ui_vis + ((#ui_msg > 15) and 3 or 1), #ui_msg)
    end

    -- timeout ヌ●★ clear & collapse
    if ui_until>0 and time()>ui_until then
        ui_msg,ui_vis,ui_until,ui_box_target_h="",0,0,6
    end
end




-- COMBAT EVENT
combat_event = {}
combat_event.__index = combat_event

function combat_event.new()
    local self=setmetatable({completed=false,success=false,start_count=0,last_msg=nil},combat_event)
    ui_say("enemy wave incoming!",3,8)

    local n=min(1+game_manager.difficulty_level,6)
    enemies={}
    for _=1,n do
        local a,d=rnd(1),10+rnd(5)
        local ex,ey=player_ship.x+cos(a)*d,player_ship.y+sin(a)*d
        local e=ship.new(ex,ey,true) e.hp=50
        add(enemies,e)
    end
    self.start_count=#enemies
    return self
end



function combat_event:update()
    update_all(enemies)
    local remaining=#enemies

    if remaining==0 then
        self.completed,self.success=true,true
        game_manager.player_score+=1000
        return
    end

    -- show remaining only after first kill; avoid repeats
    if remaining<self.start_count then
        local msg=(remaining==1) and "1 enemy left" or (remaining.." enemies left")
        if self.last_msg!=msg then ui_say(msg,3,8) self.last_msg=msg end
    end
end


function combat_event:draw()
    for e in all(enemies) do
        local q=e.hp/e.max_hp
        local dist=dist_trig(player_ship.x-e.x,player_ship.y-e.y)
        local mode=(q<=0.3 and dist>15) or (q>0.3 and (dist>20 or ((time()+e.ai_phase)%6)<3))
        local col=mode and 8 or 9
        draw_circle_arrow(e.x,e.y,col)
    end
    draw_all(enemies)
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





-- TILE MANAGER (optimized: inline generation + precomputed palette)
tile_manager = {
    player_x = 0,
    player_y = 0,
    palette_cache = nil,
    cur_margin = 0,
    target_margin = 2
}

function tile_manager:init()
    self.player_x, self.player_y = 0, 0
    self.cur_margin=0
    -- precompute palette lookup table
    if not self.palette_cache then
        self.palette_cache={}
        for i=1,8 do
            local p=(i-1)*3+1
            self.palette_cache[i]={ord(TERRAIN_PAL_STR,p),ord(TERRAIN_PAL_STR,p+1),ord(TERRAIN_PAL_STR,p+2)}
        end
    end
end

function tile_manager:update_player_position(px, py)
    self.player_x, self.player_y = flr(px), flr(py)
end

function tile_manager:manage_cache()
    local px,py=self.player_x,self.player_y
    local cm=min(self.cur_margin,self.target_margin)
    local pxm,pym=px-cm,py-cm
    local pxp,pyp=px+cm,py+cm
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=TERRAIN_THRESH
    local palcache=self.palette_cache
    local scale=menu_options[1].values[menu_options[1].current]
    local water_level=menu_options[2].values[menu_options[2].current]

    for x=pxm,pxp do
        local row=cache[x]
        if not row then row={} cache[x]=row end
        for y=pym,pyp do
            if not row[y] then
                local nx,ny=x/scale,y/scale
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain-water_level,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local pc=palcache[i]
                row[y]={pc[1],pc[2],pc[3],h}
            end
        end
    end

    for x in pairs(cache) do
        if x<pxm or x>pxp then
            cache[x]=nil
        end
    end

    if cm<self.target_margin then cm+=1 end
    self.cur_margin=cm
end





-- TERRAIN GENERATION
function perlin2d(x,y,p)
    local fx,fy=flr(x),flr(y)
    local xi,yi=fx&255,fy&255
    local xf,yf=x-fx,y-fy
    local u=xf*xf*(3-2*xf)
    local v=yf*yf*(3-2*yf)

    -- hash corners
    local a,b=p[xi]+yi,p[(xi+1)&255]+yi
    local aa,ab,ba,bb=p[a&255],p[(a+1)&255],p[b&255],p[(b+1)&255]

    -- gradients
    local ax=((aa&1)<1 and xf or -xf)+((aa&2)<2 and yf or -yf)
    local bx=((ba&1)<1 and xf-1 or 1-xf)+((ba&2)<2 and yf or -yf)
    local cx=((ab&1)<1 and xf or -xf)+((ab&2)<2 and yf-1 or 1-yf)
    local dx=((bb&1)<1 and xf-1 or 1-xf)+((bb&2)<2 and yf-1 or 1-yf)

    -- bilerp via one temp
    local x1=ax+(bx-ax)*u
    return x1+((cx+(dx-cx)*u)-x1)*v
end



function generate_permutation(seed)
    srand(seed)
    local p={}
    for i=0,255 do p[i]=rnd(256) end
    return p
end





__gfx__
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eec11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ec0000000000001110000000000000111000000000000011100000000000001110000000000000111000000000000ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ec0000000000011100000000000001110000000000000111000000000000011100000000000001110000000000000ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ec0000000000111000000000000011100000000000001110000000000000111000000000000011100000000000001ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ec0000000001110000000000000111000000000000011100000000000001110000000000000111000000000000011ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ec0000000011100000000000001110000000000000111000000000000011100000000000001110000000000000111ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eec00000011100000000000001110000000000000111000000000000011100000000000001110000000000000111ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeec1111111111111111111111111111111111111111111111111111111111111ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eec100000000000001110000000000000111000000000000011100000000000001ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ec10000000000000111000000000000011100000000000001110000000000000111ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeecccccccccccccccccccccccceee
ec100000000000011100000000000001110000000000000111000000000000011101ceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeec111111111111111111111111cee
ec1000000000001110000000000000111000000000000011100000000000001110001ceeeeeeeeeeeeeeeeeeeeeeeeeeeeec10000000001110000000000000ce
ec10000000000111000000000000011100000000000001110000000000000111000001ceeeeeeeeeeeeeeeeeeeeeeeeeeec100000000011100000000000001ce
ec100000000011100000000000001110000000000000111000000000000011100000001ceeeeeeeeeeeeeeeeeeeeeeeeec1000000000111000000000000011ce
ec1000000001110000000000000111000000000000011100000000000001110000000001ceeeeeeeeeeeeeeeeeeeeeeec10000000001110000000000000111ce
eec1000000111000000000000011100000000000001110000000000000111000000000001ccccccccccccccccccccccc100000000011100000000000001111ce
eeec1000011100000000000001110000000000000111000000000000011100000000000001110000000000000111000000000000011100000000000001111cee
eeeeccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccceee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
e00eeee000000000eeeeeeeeeeeeeeeeeeeeeeee000eeeee000000000000000000000000000000000000000000000000eeee000e000000000000000000000000
e00eee00555555d500eeeeeeeeeeeeeeeeeeeeee0c0eeeee0c0ccccccccc0ccccccccc0c0ccccccccc0ccccccccc0cc00eee0c0e000000000000000000000000
e05ee005d555555d500eeeeeeeeeeeeeeeeeeeee0c0000000c0c0000000c0c0000000c0c000000cc000c0000000c0c0cc0ee0c0e000000000000000000000000
e05ee0dd5dddddd5dd0eeeeeeeee000000000eee0ccccccccc0c0eeeee0c0ccccccccc0c0e000c00ee0c0eeeee0c0c000c000c0e000000000000000000000000
e05e00ddd6ddddd5dd00eeeeeee0ccc0cc7700ee0c0000000c0c0000000c0c0000cc000c000cc000000c0000000c0c0ee0cc0c0e000000000000000000000000
e05e05d6d6dddd5ddd50eeeeeee0c1c0cc7770ee0c0eeeee0c0ccccccccc0c0ee000cc0c0ccccccccc0ccccccccc0c0eee00cc0e000000000000000000000000
e05005ddd6dddd5dd5500eeeeee0c1c011cc00ee000eeeee000000000000000eeee0000000000000000000000000000eeeee000e000000000000000000000000
e00505666d6ddd5ddd5050eeeee0c1c0000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000
e0650500665555ddd05050eeeee0c1c0cc7700ee0000000000000eeeeeee000000000000e0000000000eeeeeeeeeeeeeeeeeeeee000000000000000000000000
e065000000000000000050eeeee0c1c0cc7770ee0ccccccccc0c0eeeeeee0c0cccccccc00ccccccccc0eeeeeeeeeeeeeeeeeeeee000000000000000000000000
e065000888000088800050eeeee0ccc011cc00ee0c000000000c0eeeeeee0c0c0000000c0c000000000eeeeeeeeeeeeeeeeeeeee000000000000000000000000
e055050088055088005050eeeeee000000000eee0c00cccccc0c0eeeeeee0c0c0eeeee0c0cccccccc0eeeeeeeeeeeeeeeeeeeeee000000000000000000000000
ee050560005665000d5050eeeeeeeeeeeeeeeeee0c0000000c0c000000000c0c0000000c0c000000000eeeeeeeeeeeeeeeeeeeee000000000000000000000000
eee0005665666dddd5000eeeeeeeeeeeeeeeeeee0ccccccccc0ccccccccc0c0cccccccc00ccccccccc0eeeeeeeeeeeeeeeeeeeee000000000000000000000000
eeee0506666ddddd5050eeeeeeeeeeeeeeeeeeee00000000000000000000000000000000e0000000000eeeeeeeeeeeeeeeeeeeee000000000000000000000000
eeee0500666ddddd0050eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000
eeee0500560000d50050eeee560000d5eeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeee0050506666050500eeee560000d5eeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeee00050666605000eeeee50666605eeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeee0005dddd5000eeeeee00dddd00eeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeeee0055555500eeeeeee05555550eeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeeeee00000000eeeeeeee00000000eeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
111111111111111fffffffffffffffffffffffff1212ccccccccccccccccccccccc1111111111111111111111111111111111111111111111111111111111111
1111111111111fffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111111111111111111111111111111111111111111
11111111111fffffffffffffffffffffffff22222cccccccccccccccccccccc11111111111111111111111111111111111111111111111111111111111111111
111111111fffffffffffffffffffffffff22222cccccccccccccccccccccc1111111111111111111111111111111111111111111111111111111111111111111
1111111fffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111111111111111111111111111111111111111111111111
11111fffffffffffffffffffffffff22222ccc111111111111111111111111ccccccccccccccccccc11111ccccccccccccccccccc11111cccccccccccccccccc
111fffffffffffffffffffffffff22222cccccccccccccccccccccc1111111111111111111111111111111111111111111111111111111111111111111111111
ffffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111111111111111111111111111111111111111111111111111111
ffffffffffffffffffffffff22222cccccccccccccccccccccc11111111111111111111111111111111111111111111111111111111111111111111111111111
ffffffffffffffffffffffffff211111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000001111000111111111111111111111111111111111111111111111
ffffffffffffffffffff000fffff0c0ccccccccc0ccccccccc0c0ccccccccc0ccccccccc0cc001110c0111111111111111111111111111111111111111111111
ffffffffffffffffffff0c0ff0000c0c0000000c0c0000000c0c000000cc000c0000000c0c0cc0110c0111111111111111111111111111111111111111111111
ffffffffffffffffffff0c000ccccc0c0fcccc0c0ccccccccc0c01000c00110c0111110c0c000c000c0111111111111111111111111111111111111111111111
ffffffffffffffffffff0cccc0000c0c0000000c0c0000cc000c000cc000000c0000000c0c0110cc0c0111111111111111111111111111111111111111111111
ffffffffffffffffffff0c000fff0c0ccccccccc0c011000cc0c0ccccccccc0ccccccccc0c011100cc0111111111111111111111111111111111111111111111
ffffffffffffffffffff0c0fffff000000000000000cccc0000000000000000000000000000ccccc0001ccccccccccccccccccccccc1cccccccccccccccccccc
ffffffffffffffffffff000fffffffffffffffffff11111111111111111111111111111111111111111111111111111111111111111111111111111111111111
ffffffffffffffffffffffffffffffffffffffffffff111111111111111111111111000000001111111111111111111111111111111111111111111111111111
ffffffffffffffffffffff22ffffffffffffffffffffff11111111111111111111110ccccccc0001111111111111111111111111111111111111111111111111
ffffffffffffffffffff222fffffffffffffffffffffffff111111111111111111110c000000cc00011111111000000000001000000000011111111111111111
ffffffffffffffffff222fffffffffffffffffffffffff22cccccccccccccccccccc0c00cccc000c0ccccccc0c0cccccccc00ccccccccc0ccccccccccccccccc
ffffffffffffffff222fffffffffffffffffffffffff2222111111111111111111110c000000cc0c011111110c0c0000000c0c00000000011111111111111111
ffffffffffffff222fffffffffffffffffffffffff22222ccc1111111111111111110ccccccc0c0c011111110c0c0ccccc0c0cccccccc0111111111111111111
ffffffffffff222fffffffffffffffffffffffff22222ccccccc111111111111111100000000cc0c001111110c0c0000000c0c00000000011111111111111111
ffffffffff222fffffffffffffffffffffffff22222ccccccccccc1111111111111111111111000ccc0000000c0cccccccc00ccccccccc011111111111111111
ffffffff222fffffffffffffffffffffffff22222ccccccccccccccc11111111111111111111111000cccccc000000000000c000000000011111111111111111
ffffff222fffffffffffffffffffffffff22222ccccccccccccccccccc1111111111111111111111110000000ccccccccccccccccc1111111111111111111111
ffff222fffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111ccccccccccccccccccccccccc11111111111111111111
ff222fffffffffffffffffffffffff22222ccc111111111111111111111111cccccccccccccccccccccccc1111111111111111111ccccccccccccccccccccccc
222fffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccc111111111111111c
2fffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccc11111111111ccc
ffffffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccc1111111ccccc
4fffffffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccc111ccccccc
444fffffffffffffffff22222cccccccccccccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
44444fffffffffffff22222111111111111111111111111111cccccccccccccccccccccccc1111111111111111111ccccc1111111111111111111ccccc111111
cc44444fffffffff222221111111ccccccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccc44444fffff2222211111111111ccccccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccc44444f22222111111111111111ccccccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccc44422221111111111111111111ccc111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccc4221111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccf
ccccccccc111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccfff
1111111111111111ccccccccccccccc111111111cccccccccccccccccccccccc111111111111111ccccccccc111111111111111ccccccccc1111111f111fffff
ccccc111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccfffffffffff
ccc111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccfffffffffffff
c111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccfffffffffffffff
ccccccccccccccccccccccc1ccccccccccccccccccccccc111111111111111111111111c11111111111111111111111c111111111111111fffffffffffffffff
11111111111111111111111111111111111111111111111111cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccfffffffffffffffffff
1111111111111111111111111111111111111111111111111111cccccccccccccccccccccccccccccccccccccccccccccccccccccccffffffffffffffffffff3
111111111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccc44ffffffffffffffff333
11111111111111111111111111111111111111111111111111111111cccccccccccccccccccccccccccccccccccccccccccccccccccf444ffffffffffff33333
1111111111111111111111111111111111111111111111111111111111cccccccccccccccccccccccccccccccccccccccccccccccfffff444ffffffff3333333
11111111111111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccfffffffff444ffff333333333
ccccccccc11111ccccccccccccccccccc11111cccccccccccccccccccccccc1111111111111111111ccccc111111111111111fffffffffffff44433333333333
1111111111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccffffffffffffffff3333333333333
11111111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccffffffffffffffff333333333333333
111111111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccffffffffffffffff33333333333333333
ccccccccccccccccccccccccccccccccccccccccccccccc11111111111111111111111111111111111111111111111144ffffffffffff3333333333333333333
11111111111111111111111111111111111111111111111cccccccccccccccccccccccccccccccccccccccccccccccc4444ffffffff333333333333333333333
111111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccc44444ffff33333333333333333333333
1111111111111111111111111111111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccc444443333333333333333333333333
11111111111111111111111111111111111111111ccccccccccccccca7777777cccccccccccccccccccccccccccccccccccc4333333333333333333333333333
111111111111111111111111111111111111111cccccccccccccccccc7cccccc77777777ccccccccccccccccccccccccccc3333333333333333333333333333b
1111111111111111111111111111111111111ccccccccccccccccccc1f7cccccccccc77cccccccccccccccccccccccccc3333333333333333333333333333bbb
ccccccccccc1cccccccccccccccccccccccc1111111111111111111ff117cccccccc711111111111111c111111111113333333333333333333333333333bbbbb
111111111111111111111111111111111ccccccccccccccccccccfffff17cccccc77111cccccccccccccccccccccc3333333333333333333333333333bbbbbbb
1111111111111111111111111111111ccccccccccccccccccc0ffffffff17cccc7111ccfccccccccccccccccccc3333333333333333333333333333bbbbbbbbb
11111111111111111111111111111cccccccccccccccccccc000fffff0ff17c77111ffffffccccccccccccccc33333333333333333333333333333333bbbbbbb
111111111111111111111111111ccccccccccccccccccccfff0ffffffffff1a111ffffffffffccccccccccc33333333333333333333333333333333b333bbbbb
ccccccccccccccccccccccc1111111111111111111111ff0ffffffffffffff111fffffffffffff111111133333333333333333333333333333333bbbbb333bbb
111111111111111111111111cccccccccccccccccccfffffffffffffffffffffffffffffffffffffccc33333333333333333333333333333333bbbbbbbbb333b
11111111111111111111111111cccccccccccccccffffffffffffffffffffffffffffffffffffffff33333333333333113333333333333333bbbbbbbbbbbbb33
1111111111111111111111111111cccccccccccffffffffffffffffffffffffffffffffffffffff33333333333333331111333333333333bbbbbbbbbbbbbbbbb
111111111111111111111111111111cccccccff0fffffffffffffffffffffffffffffffffffff33333333333333333311111133333333bbbbbbbbbbbbbbbbbbb
11111111111111111111111111111111cccffffffffffffffffffffffffffffffffffff3fff33333333333333333333311111113333bbbbbbbbbbbbbbbbbbbbb
1111111111111111111111111111111111c44ffffffffffffffffffffffffffffffff3333333333333333333333333333311111113333bbbbbbbbbbbbbbbbbbb
111111111111111111111111111111111114444ffffffffffffffffffffffffffff33333333333333333333333333333333311111113333bbbbbbbbbbbbbbbbb
ccccccccc11111cccccccccccccccccccccc44444ffffffffffffffffffffffff333333333333333333333333333333333333311111333333bbbbbbbbbbbbb11
1111111111111111111111111111111ccccccc44444ffffffffffffffff3fff3333333333333333333333333333333333333333311133333333bbbbbbbbb1113
11111111111111111111111111111ccccccccccc44444ffffffffffff333333333333333333333333333333333333333333333333333333333333bbbbb111333
111111111111111111111111111ccccccccccccccc4ffffffffffff3333333333333333333333333333333333333333333333333333333333333333b11133333
1111111111111111111111111ccccccccccccccccffffffffffff333333333333333333333333333333333333333333333333333333333333333333113333333
11111111111111111111111ccccccccccccccccffffffffffff33333333333333333333333333333333333333333333333333333333333333333333333333333
11cccccccccccccccccccccccc11111111111ffffffffffff3333333333333333333333333333333333333333333333333333333333333333333333113333333
1111111111111111111ccccccccccccccccffffffffffff333333333333333333333333333333333333333333333333333333333333333333333333311133333
11111111111111111ccccccccccccccccffffffffffffff113333333333333333333330033333333333333333333333113333333333333333333333333111333
111111111111111ccccccccccccccccffffffffffffffff111133333333333333333000333333333333333333333333111133333333333333333333333331113
1111111111111ccccccccccccccccffffffffffffffffff111111333333333333300033333333333333333333333330111111333333333333333333333333311
11111111111ccccccccccccccccffffffffffffffffffbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3333333333000311111113333333333333333333333333
111111111ccccccccccccccccffffffffffffffffffffb00000000000000000000000000000000000b3333333300033333111111133333333333333333333333
cccccccccccccccc1111111ffffffffffffffffffff33b00000000000000000000000000000000000b3333330003333333331111111333333333333333333333
11111ccccccccccccccccffffffffffffffffffff3333b00000000000000000000000000000000000b3333000333333333333311111113333333333333333333
111ccccccccccccccccffffffffffffffffffff333333b0000000000bbb0b000bbb0b0b0000000000b3300033333333333333333111111133333333333333333
1ccccccccccccccccffffffffffffffffffff33333333b0000000000b0b0b000b0b0b0b0000000000b0003333333333333333333331111111333333333333300
111111111111111ffffffffffffffffffff3333333333b0000000000bbb0b000bbb0bbb0000000000b0333333333333333333333333311111113333333330000
cccccccccccccffffffffffffffffffffff1133333333b0000000000b000b000b0b000b0000000000b0113333333333333333333333333111111133333000000
cccccccccccfffffffffffffffffffffffff111333333b0000000000b000bbb0b0b0bbb0000000000b0f11133333333333333333333333331111111300000003
ccccccccccc44fffffffffffffffffffffffff1113333b00000000000000000000000000000000000bffff111333333333333333333333333311111000000333
cccccccccccf444fffffffffffffffffffffffff11133b00000000000000000000000000000000000bffffff1113333333333333333333333333111000033333
cccccccccfffff444fffffffffffffffffffffffff111b00000000000000000000000000000000000bffffffff11133333333333333333333333331003333333
cccccccfffffffff444fffffffffffffffffffffffff1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbffffffffff111333333333333333333333333333333333
11111fffffffffffff444fffffffffffffffffffffffff111333333333333333333333000fffffffffffffffffffff1113333333333333333333330113333333
cccfffffffffffffffff444ffffffffffffffffffffffff111133333333333333333000fffffffffffffffffffffffff11133333333333333333000f11133333
ffffffffffffffffffffff444ffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccccfffffffff1113333333333333000fffff111333
ffffffffffffffffffffffff444ffffffffffffc000000000000000000000000000000000000000000000000cfffffffffff111333333333000fffffffff1113
ffffffffffffffffffffffffff444ffffffffffc000000000000000000000000000000000000000000000000cfffffffffffff11133333000fffffffffffff11
ffffffffffffffffffffffffffff444ffffffffc000000077070700770777007707770777077707770000000cfffffffffffffff1113000fffffffffffffffff
ffffffffffffffffffffffffffffff444fffff2c000000700070707000070070707770070000707000000000cfffffffffffffffff100fffffffffffffffffff
ffffffffffffffffffffffffffffffff444f222c000000700070707770070070707070070007007700000000cfffffffffffffffffffffffffffffffffffffff
fffffffffffffffffffffffffffffffffffffffc000000700070700070070070707070070070007000000000cfffffffffffffffff244fffffffffffffffffff
fffffffffffffffffffffffffffffffffffffffc000000077007707700070077007070777077707770000000cfffffffffffffff222f444fffffffffffffffff
fffffffffffffffffffffffffffffffffffffffc000000000000000000000000000000000000000000000000cfffffffffffff222fffff444fffffffffffff22
fffffffffffffffffffffffffffffffffffffffc000000000000000000000000000000000000000000000000cfffffffffff222fffffffff444fffffffff2222
fffffffffffffffffffffffffffffffffffffffc000000000000000000000000000000000000000000000000cfffffffff222fffffffffffff444fffff222222
fffffffffffffffffffffffffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccccfffffff222fffffffffffffffff444f22222222
1ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff44fffffffffffffffffffff222fffffffffffffffffffff422222222c
111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff444fffffffffffffffff222fffffffffffffffffffffffff22222ccc
11111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff444fffffffffffff222fffffffffffffffffffffffff2222211111
1111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff444fffffffff222fffffffffffffffffffffffff22222ccccccc
111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff444fffff222fffffffffffffffffffffffff22222ccccccccc
11111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff444f222fffffffffffffffffffffffff22222ccccccccccc
1111111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff422fffffffffffffffffffffffff22222ccccccccccccc
111111111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff22222ccccccccccccccc
11111111111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff2ccccccccccccccccc
1111111111111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcccccccccccccccc
111111111111111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff11111111111111
11111111111111111111111fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffcccccccccccc
1111111111111111111111111fffffffffffffffffffff244fffffffffffffffffffff22ffffffffffffffffffffffffffffffffffffffffffffffcccccccc11

__sfx__
010b00001007300000000000000010675300040000000000100730000010073000001067500000000000000010073000000000000000106750000000000000001007300000000000000010675000000000000000
010b00001007300000000000000010675300040000000000100730000010073000001067500000000000000010073000000000000000106750000000000000001007300000000000000010675000001067510675
c30b0000110400000011040000001104000000110400000011040000001104000000110400000011040000000d040000000d040000000d040000000d040000000f040000000f040000000f040000000f04000000
c30b0000110400000011040000001104000000110400000011040000001104000000110400000011040000000f040000000f040000000f040000000f040000000f040000000f040000000f040000000f04000000
c30b00000d040000000d040000000d040000000d040000000d040000000d040000000d040000000d040000000f040000000f040000000f040000000f040000000f040000000f040000000f040000000f04000000
c30b0000110400000011040000001104000000110400000011040000001104000000110400000011040000000f0420f0420f0420f0420f0420f0420f0420f0420f0420f0420f0420f0420f0420f0420f0420f042
450b0000203300000020330000001d33000000203300000020330000001d33000000203300000024330000001f330000001f330000001b330000001f3300000022330000001b3300000022330000002233000000
450b0000203300000020330000001d33000000203300000020330000001d33000000203300000024330000001b3121b3121b3121b3121b3221b3221b3221b3221b3321b3321b3321b3321b3421b3421b3421b342
010b0000247402474024740247402c7402c7402c7402c7402b7402b7402b7402b7402774027740277402774029740297402974029740297402974024740247402474024740247402474022740227402274022740
010b00002474024740247402474027740277402074020740207402074020740207402274022740227402274024740247402474024740277402774027740277402774027740277402774029740297402974029740
010b00002974229742297422974229742297422974229742297422974229742297422974229742297421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f7421f742
150b00001007300000000000000010675300040000000000000000000010073000001067500000000000000010073000000000000000106750000000000000001007310623106231063310643106531066310673
450b000029240292402922029210302403024030220302102c2402c2402c2202c2102b2402b2402c2402c2402b2402b2402b2202b21027240272402b2402b2402b2202b2102e2502e2402c2402c2402b2402b240
450b000029240292402922029210302403024030220302102c2402c240292402924030240302402e2402e2402e2202e2102c2402c2402c2202c2102b2402b2402b2202b21027240272402c2402c2402b2402b240
450b000029240292402924029240292402924029240292402924029240292202921029240292402b2402b2402c2402c2402c2402c2402c2202c2102b2402b2402b2202b210000000000030240302402c2402c240
450b00002924229242292422924229242292422924229242292422924229242292422924229242292422924229242292422924229242292422924229242292422924229242292422924229242292422924229242
470b00000534000300113400030005340003001134000300053400030011340003000534000300113400030001340003000d3400030001340003000d3400030003340003000f3400030003340003000f34000300
470b00000534000300113400030005340003001134000300053400030011340003000534000300113400030003340003000f3400030003340003000f3400030003340003000f3400030003340003000f34000300
470b000001340003000d3400030001340003000d3400030001340003000d3400030001340003000d3400030003340003000f3400030003340003000f3400030003340003000f3400030003340003000f34000300
470b00000534000300113400030005340003001134000300053400030011340003000534000300113400030005340003001134000300053400030011340003000534000300113400030005340003001134000300
010b00001104000000110400000011040000001104000000110400000011040000001104000000110400000011040000001104000000110400000011040000000f04000000110400000014040000001304000000
010b00001007300000000000000010675300040000000000100030000010073000001067500000000000000010073000000000000000106750000000000000001000300000100730000010675000000400500000
010b000029740297402974024740247402474030740307402e7402e7402e7402e7402b7402b7402c7402c7402e7402e7402e7402e740277402774022740227402274022740277402774027740277402274022750
010b00002b7502b750000002b7522c7502b700297502975029750297502975029750297502975029750000002b7502b750000002b7522c7502b70029750297502975029750297502975029750297502975000000
010b000029740297402974024740247402474030740307402e7402e7402e7402e7402b7402b7402c7402c7402e7402e7402e7402e740277402774033740337403370033700317403174031700317003074030740
010b0000307423074230742307423074230742307423074230742307423074230742307423074230742307422c7402c74000000000002b7502b75000000000002c7502c75000000000002e7502e7500000000000
010b000020740207402074020740207402074020740207402075020750207502075020750227502575024750227502275022750227502275022750227202271022750227501f7001f7501f7501b7001b7501b750
011000001d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d7421d742
010b00001007300000000000000010605300041007300000106750000010073000001060500000000000000010073000000000000000106050000000000000001067500000100730000010675000000400500000
030b000020335203351d3351d3351f3351f33520335203351d3351d3351f3351f33520335203351d3351d3351f3351f3351b3351b3351d3351d3351f3351f3351b3351b3351d3351d3351f3351f3351b3351b335
030b000020335203351d3351d3351f3351f33520335203351d3351d3351f3351f33524335243352233522335203052030520335203351f3051f3051f3351f3351f3051f3051f3351f33520335203351f3351f335
030b00001d3451d34511345113451d3451d34511345113451d3451d34529345293451d3451d34511345113451d3451d34529345293451d3451d34529345293451d3451d34511345113451d3451d3453534535345
030b00001d3451d3451d3451d3451d3451d3451d3451d34522345223451f3051f3451f3451b3051b3451b3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d3451d345
c70b000020345203451d3451d3451f3451f34520345203451d3451d3451f3451f34520345203451b3451b3451d3451f3001d3051d3301d3051d3001d3251f3001d3051d3201d3051d3001d3151f3001c3051d310
c70b000020345203451d3451d3451f3451f34520345203451d3451d3451f3451f34520345203451b3451b3451c3451f3001d3051c3301d3051d3001c3251f3001d3051c3201d3051d3001c3151f3001c3051c310
d70b00000525505255052550525505255052550525505255052550525505255052550525505255052550525505255052550525505255052550525505255052550525505255052550525505255052550525505255
d70b00000525505255052550525505255052550525505255052550525505255052550525505255052550525504255042550425504255042550425504255042550425504255042550425504255042550425504255
c70b00001c3441f3041d3041c3441d3041d3041c3441f3041d3041c3341d3041d3041c3341f3041c3041c3341c3041f3041c3241c3041d3041c3241c3041f3041c3241c3041d3041c3141c3041f3041c3141c304
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a10200001016610166101660010600106001060010600106001060010600106001060010600106001060010600106001060010600106001060010600106001060010600106001060010600106001060010600106
0001000031660256601d6601766010660096600266000660076000060000600026000460004600046000360003600056000860009600006000060000600006000060000600006000060000600006000060000600
1002000003250082500f250172501c25021250262502a250242002c20031200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
a502000005757107571b757287573a7573f7573c757387573175721757127571175715757197571c7571f75723757247571f75719757117570c75706757027570075700707007070070700707007070070700707
110200000375005750087500c750127501a7501e750257502f7503a7503f750007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
000500003b650356502f6502965025650206501c650176501365011650106500e6500b65008650066300362001610076000760006600056000460004600036000260002600016000060000600006000060000600
150100003f66033660256601d660146600e6600b660086600766006660056600566005660046600466003660036600566008660096603d6000060000600006000060000600006000060000600006000060000600
__music__
01 42460602
00 43080603
00 44090604
00 050a070b
00 000c0210
00 010d0311
00 000e0412
00 0b0f0511
00 000c0210
00 010d0311
00 000e0412
00 0b0f0511
00 15160412
00 15171413
00 15180412
00 15191413
00 15160412
00 15171413
00 151a0412
00 0b1b1413
00 1c1d0244
00 1c031e44
00 1c041d44
02 01051f44
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
01 21234344
02 22234344
03 24254344

