pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- horizon glide v0.21

-- helper functions
function dist_trig(dx,dy) local ang=atan2(dx,dy) return dx*cos(ang)+dy*sin(ang) end
function iso(x,y) return cam_offset_x+(x-y)*half_tile_width,cam_offset_y+(x+y)*half_tile_height end
function vdist(s,ox,oy) local dh=(s.current_altitude-terrain_h(ox,oy))/6 return dist_trig(s.x-ox-dh,s.y-oy-dh) end

hc=split"0,0,1,0,5,1,5,6,2,4,9,3,13,2,8,9"
function printx(s,x,y,c)
    clip(0,y,128,3) print(s,x,y,c)
    clip(0,y+3,128,3) print(s,x,y,hc[c+1])
    clip()
end

function fmt2(n)
    local s=flr(n*100+0.5)
    local neg=s<0 if(neg)s=-s
    return(neg and"-"or"")..flr(s/100).."."..sub("0"..(s%100),-2)
end

function opt_text(o)
    return o.name..": "..(o.is_seed and cseed or tostr(o.values[o.current]))
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

function draw_iso_ellipse(sx,sy,rx,ry,col,step)for a=0,1,step do pset(sx+cos(a)*rx,sy+sin(a)*ry,col)end end

function draw_circle_arrow(tx,ty,col)
    local dx,dy=tx-ps.x,ty-ps.y
    if dx*dx+dy*dy<4 then return end
    local orbit_dist,a=1.5+sin(time()*1.5)*.2,atan2(dx,dy)
    local sx,sy=iso(ps.x+cos(a)*orbit_dist,ps.y+sin(a)*orbit_dist)
    sy-=ps.current_altitude*block_h
    local sa=atan2((dx-dy)*half_tile_width,(dx+dy)*half_tile_height)
    local s,b=7,sa+0.5
    draw_triangle(sx+cos(sa)*s,sy+sin(sa)*s*0.5,sx+cos(b-0.18)*s*.7,sy+sin(b-0.18)*s*.35,sx+cos(b+0.18)*s*.7,sy+sin(b+0.18)*s*.35,col)
end


-- terrain color lookup tables
TERRAIN_PAL_STR="\1\0\0\12\1\1\15\4\2\3\1\0\11\3\1\4\2\0\6\5\0\7\6\5"
TERRAIN_THRESH=split"-2,0,2,6,12,18,24,99"

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


function _init()
    music(32,0,14)
    palt(0,false) palt(14,true)

    gstate,sphase="startup","title"
    stimer,svr=0,0
    title_x1,title_x2=-64,128

    cam_offset_x,cam_offset_y=64,64
    view_range,half_tile_width,half_tile_height,block_h=0,12,6,2

    cols,ftexts,ws,cpanels={},{},{},{}
    ccursor=1
    projs,enemies,mines={},{},{}

    -- player ship
    ps=ship_new(0,0)
    ps.is_hovering=true

    -- game manager globals
    gm_idle_dur=5
    gm_rb,gm_rs,gm_bt=3,1,10
    gm_rcs,gm_rcstep,gm_rcmin=2,0.1,1
    gm_diff,gm_tut=0,nil
    gm_state,gm_evt,gm_idle_t="idle",nil,nil
    gm_nidx,gm_score,gm_dscore=1,0,0

    -- particle list
    ptl={}

    -- menu options
    mopts={
        {name="sCALE",  values=split"8,10,12,14,16", current=2},
        {name="wATER",  values=split"-4,-3,-2,-1,0,1,2,3,4", current=4},
        {name="sEED",   values={}, current=1, is_seed=true},
        {name="rANDOM", is_action=true},
    }

    cseed=1337
    tperm,cell_cache=generate_permutation(cseed),{}

    tm_init()
    tm_setpos(0,0)

    ship_set_alt(ps)

    ui_msg,ui_vis,ui_until,ui_col,ui_rmsg="",0,0,7,""
    ui_box_h,ui_box_target_h,ui_shake=6,6,0
end


function _update60()
    if gstate=="startup" then
        stimer+=1
        ps.vy=-0.05
        ps.y+=ps.vy

        ps.angle=atan2(ps.vx-ps.vy,(ps.vx+ps.vy)*0.5)

        ship_set_alt(ps)
        ps.is_hovering=true

        tm_setpos(ps.x,ps.y)

        if stimer%6==0 then ship_spawn_p(ps,1,0) end

        cam_offset_x,cam_offset_y=ship_cam(ps)

        if sphase=="title" then
            if svr<8 then
                svr+=0.25
                view_range=flr(svr)
                tm_target=view_range+2
            end
            if(title_x1<20)title_x1+=3
            if(title_x2>68)title_x2-=3
            if svr>=8 and title_x1>=20 and title_x2<=68 then
                sphase="menu_select"
                init_menu_select()
            end
        elseif sphase=="menu_select" then
            update_menu_select()
        else
            update_customize()
        end

    elseif gstate=="game" then
        if ps.dead then
            enter_death()
        else
            ship_update(ps)
            gm_update()
            local tx,ty=ship_cam(ps)
            cam_offset_x+=(tx-cam_offset_x)*0.15
            cam_offset_y+=(ty-cam_offset_y)*0.15
        end

        update_projs()
        manage_cols()
        for i=#ftexts,1,-1 do if not ft_update(ftexts[i]) then deli(ftexts,i) end end
        for i=#mines,1,-1 do if not mn_update(mines[i]) then deli(mines,i) end end

        if gm_dscore<gm_score then
            local diff=gm_score-gm_dscore
            gm_dscore+=diff<10 and diff or flr((diff+9)/10)
        end

        ui_tick()
    else -- "death"
        update_death()
    end

    ptl_update()
    tm_cache()
end


function _draw()
    if gstate=="startup" then
        draw_startup()
    elseif gstate=="game" then
        draw_game()
    else
        draw_death()
    end
end



function enter_death()
    music(34)
    gstate,death_t,death_cd="death",time(),10
    death_phase,death_closed_at,buf_ok=0,nil,false
    ui_msg,ui_rmsg,ui_box_target_h="","",6
end

function update_death()
    local el=time()-death_t
    if death_phase==0 and el>2.5 then
        death_phase,death_closed_at=1,time()
    end
    if death_phase==2 and btnp(❎) then init_game() return end
    if time()-death_t>death_cd then _init() end
end

function draw_death()
    local el=time()-death_t
    if death_phase==0 then
        cls(1)
        draw_world()
        if el>0.2 then
            for _=1,el*5 do
                local y,h,shift=flr(rnd(128)),1+flr(rnd(3)),flr(rnd(20))-10
                for dy=0,h-1 do
                    if y+dy<128 then
                        for x=0,127 do
                            local src_x=(x-shift)%128
                            pset(x,y+dy,pget(src_x,y+dy))
                        end
                    end
                end
            end
        end
        if el>0.8 then
            local blocks=(el-0.8)*50
            for _=1,blocks do
                local x,y,c=flr(rnd(16))*8,flr(rnd(16))*8,rnd()<el/3 and 0 or flr(rnd(16))
                rectfill(x,y,x+7,y+7,c)
            end
        end
        if el>1.5 then
            local pct=(el-1.5)*3000
            for _=1,pct do
                pset(flr(rnd(128)),flr(rnd(128)),0)
            end
        end
    else
        cls(0)
        local t=time()-death_closed_at
        if t<0.5 then return end
        death_phase=2
        local cx=64
        local s="score: "..flr(gm_score)
        printx(s,cx-#s*2,30,7)
        palt(14,true) palt(0,false)
        if t>=3 or rnd()<0.4 then pal(8,0) end
        spr(64,cx-12,52,3,3)
        pal()
        local c=flr(max(0,death_cd-(time()-death_t))+0.99)
        local msg="continue? ("..c..")  ❎"
        print(msg,cx-#msg*2,92,6)
    end
end



function draw_minimap(x,y)
    local ms,step=44,64/44
    local start_wx,start_wy=ps.x-32,ps.y-32
    rectfill(x-1,y-1,x+ms,y+ms,0)
    for py=0,ms-1 do
        local wy=flr(start_wy+py*step)
        for px=0,ms-1 do
            pset(x+px,y+py,terrain(flr(start_wx+px*step),wy))
        end
    end
    local cx,cy=x+ms/2,y+ms/2
    local vb=ms*view_range/32
    rect(cx-vb/2,cy-vb/2,cx+vb/2,cy+vb/2,7)
    circfill(cx,cy,1,8)
end


function draw_startup()
    cls(1)
    draw_world()
    local t=time()*50
    for s=0,1 do
        local sp,x,y,w=s==0 and 69 or 85,s==0 and title_x1 or title_x2,s==0 and 10 or 20,s==0 and 64 or 48
        for i=0,w-1 do
            local d=abs(i-t%(w+40)+20)
            sspr((sp%16)*8+i,flr(sp/16)*8,1,8,x+i,y-(d<20 and cos(d*0.025)*2 or 0))
        end
    end
    if sphase=="menu_select" then
        pnl_draw(play_panel) pnl_draw(cust_panel)
    elseif sphase=="customize" then
        for p in all(cpanels) do pnl_draw(p) end
        draw_minimap(82,32)
    end
end



function init_menu_select()
    play_panel=pnl_new(-50,90,nil,nil,"play",11)
    play_panel.selected=true
    pnl_setpos(play_panel,50,90)

    cust_panel=pnl_new(128,104,nil,nil,"customize",12)
    pnl_setpos(cust_panel,40,104)
end


function update_customize()
    for p in all(cpanels) do pnl_update(p) end

    local d=btnp(⬆️) and -1 or btnp(⬇️) and 1 or 0
    if d!=0 then
        sfx(57)
        cpanels[ccursor].selected=false
        ccursor=(ccursor+d-1)%#cpanels+1
        cpanels[ccursor].selected=true
    end

    local p=cpanels[ccursor]
    if p.is_start then
        if btnp(❎) then sfx(57) view_range=8 init_game() end
        return
    end

    local idx=p.option_index
    if not idx then return end
    local o=mopts[idx]

    if o.is_action then
        if btnp(❎) then
            sfx(57)
            mopts[1].current=flr(rnd(#mopts[1].values))+1
            mopts[2].current=flr(rnd(#mopts[2].values))+1
            cseed=flr(rnd(9999))
            for q in all(cpanels) do
                if q.option_index then
                    local oo=mopts[q.option_index]
                    q.text=oo.is_action and "random" or opt_text(oo)
                end
            end
            regenerate_world_live()
        end
        return
    end

    local lr=btnp(⬅️) and -1 or btnp(➡️) and 1 or 0
    if lr==0 then return end
    sfx(57)

    if o.is_seed then
        cseed=(cseed+lr)%10000
        p.text=opt_text(o)
    else
        o.current=(o.current+lr-1)%#o.values+1
        p.text=opt_text(o)
    end
    regenerate_world_live()
end




function regenerate_world_live()
    tperm,cell_cache=generate_permutation(cseed),{}
    tm_cm=0
    tm_setpos(ps.x,ps.y)
    for _=1,view_range+2 do tm_cache() end
    ship_set_alt(ps)
end


function update_menu_select()
    pnl_update(play_panel) pnl_update(cust_panel)

    if btnp(⬆️) or btnp(⬇️) then
        sfx(57)
        play_panel.selected,cust_panel.selected=not play_panel.selected,not cust_panel.selected
    end

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
    sphase="customize" ccursor=1 cpanels={}
    tm_target=32
    tm_setpos(ps.x,ps.y)

    local y_start,y_spacing,delay_step=32,12,4
    local panel_index=0

    for i=1,#mopts do
        local o=mopts[i]
        local y=y_start+panel_index*y_spacing
        local p=pnl_new(-60,y,68,9,o.is_action and "random" or opt_text(o),6)
        p.option_index=i p.anim_delay=panel_index*delay_step
        pnl_setpos(p,6,y) add(cpanels,p)
        panel_index+=1
    end

    local sb=pnl_new(50,128,nil,12,"play",11)
    sb.is_start=true sb.anim_delay=(panel_index+1)*delay_step+8
    pnl_setpos(sb,50,105) add(cpanels,sb)

    cpanels[1].selected=true
end




-- GAME FUNCTIONS
function init_game()
    music(0)
    pal() palt(0,false) palt(14,true)
    tm_target,gstate=view_range+2,"game"
    ftexts,ptl,mines,projs,enemies,cols={},{},{},{},{},{}
    gm_reset()
    ps.dead,ps.hp,ps.last_shot_time=false,ps.max_hp,time()+0.5
    tm_setpos(ps.x,ps.y)
    ship_set_alt(ps)
    ui_msg,ui_vis,ui_until,ui_rmsg="",0,0,""
    for _=1,8 do
        local a,d=rnd(),15+rnd(20)
        add(cols,col_new(cos(a)*d,sin(a)*d))
    end
end


function draw_world()
    local px,py=flr(ps.x),flr(ps.y)
    local htw,hth,co_x,co_y,bh=half_tile_width,half_tile_height,cam_offset_x,cam_offset_y,block_h
    local cc=cell_cache
    local vr=view_range
    local t_val=time()

    if not buf_ok then
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

    -- water rings
    for i=#ws,1,-1 do
        local s=ws[i]
        s.r+=0.09 s.life-=1
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
    memcpy(0x2000,0x6000,0x1000)
    memcpy(0x4300,0x7000,0x1000)
    end

    -- fx + ship
    ptl_draw()
    for c in all(cols) do col_draw(c) end
    if not ps.dead then ship_draw(ps) end
end


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

    -- projectiles
    for p in all(projs) do
        local sx,sy=iso(p.x,p.y) sy-=p.z*block_h
        circfill(sx,sy,2,0)
        circfill(sx,sy,1,p.is_enemy and 8 or 12)
    end

    -- target cursor
    if not ps.dead and ps.target and ps.target.is_enemy then
        local tx,ty=ship_spos(ps.target)
        rect(tx-8,ty-8,tx+8,ty+8,8)
    end

    -- floating texts
    for f in all(ftexts) do ft_draw(f) end

    -- mines
    for m in all(mines) do mn_draw(m) end

    -- current event visuals
    if gm_state=="active" and gm_evt then
        evt_draw()
    end

    draw_ui()
end




function draw_segmented_bar(x,y,value,max_value,filled_col)
    local filled=flr(value*15/max_value)
    for i=0,14 do
        local s=x+i*4
        rectfill(s,y,s+2,y+1,(i<filled) and filled_col or 5)
    end
end

function draw_ui()
    sspr(0,0,128,16,0,0,128,16)

    local h=flr(ui_box_h)
    rrectfill(100,1,27,h-1,2,0)

    if h>3 then
        for y=3,h-2,4 do
            line(101,y,125,y,3)
        end
        for x=104,124,6 do
            line(x,2,x,h-1,3)
        end
    end

    if h>25 then
        local sx,sy=102,3
        if ui_shake>0 then sx+=rnd(3) sy+=rnd(3) end
        spr(64,sx,sy,3,3)
        if ui_msg!="" then
            if (time()*8)%2<1 then spr(99,110,19) end
            printx(sub(ui_msg,1,ui_vis),4,3,ui_col)
        end
    end

    rrect(100,1,27,h-1,2,12)

    if ui_rmsg!="" and ui_msg=="" then
        printx(ui_rmsg,4,3,10)
    end

    -- bottom HUD
    if ui_shake>0 then camera(0,-rnd(3)) ui_shake-=1 end
    sspr(0,16,128,16,0,112)
    draw_segmented_bar(5,117,ps.hp,100,ps.hp>30 and 11 or 8)
    draw_segmented_bar(5,120,ps.ammo,ps.max_ammo,12)
    draw_segmented_bar(5,123,ps.mines,ps.max_mines,9)

    local score_text=sub("00000"..flr(gm_dscore),-6)
    printx(score_text,125-#score_text*4,120,10)
    camera()
end


-- FLOATING TEXT
function ft_new(x,y,text,col)
    return {x=x,y=y,text=text,col=col or 7,life=40,vy=-1.5}
end

function ft_update(f)
    f.y+=f.vy
    f.vy+=0.06
    f.life-=1
    return f.life>0
end

function ft_draw(f)
    local w,x1=#f.text*4,f.x-#f.text*2
    rrectfill(x1-1,f.y-1,w+2,7,1,0)
    printx(f.text,x1,f.y,f.col)
end

-- PANEL
function pnl_new(x,y,w,h,text,col)
    return {
        x=x,y=y,
        w=w or (#text*4+12),
        h=h or 9,
        text=text,
        col=col or 5,
        selected=false,
        expand=0,
        target_x=x,target_y=y,
        anim_delay=0,
    }
end

function pnl_setpos(p,x,y,instant)
    p.target_x,p.target_y=x,y
    if instant then p.x,p.y=x,y end
end

function pnl_update(p)
    if p.anim_delay>0 then p.anim_delay-=1 return true end
    p.x+=(p.target_x-p.x)*0.1
    p.y+=(p.target_y-p.y)*0.1
    p.expand=p.selected and min(p.expand+0.5,3) or max(p.expand-0.5,0)
    return true
end

function pnl_draw(p)
    local dx,dy,dw,dh=p.x-p.expand,p.y,p.w+p.expand*2,p.h
    rrectfill(dx-1,dy-1,dw+2,dh+2,2,p.col)
    rrectfill(dx,dy,dw,dh,2,0)
    local tx,ty,tcol=dx+(dw-#p.text*4)/2,dy+(dh-5)/2,p.selected and p.col or 7
    printx(p.text,tx,ty,tcol)
    if p.option_index then
        local opt=mopts[p.option_index]
        if not opt.is_action then
            print("⬅️",dx+2,ty,tcol)
            print("➡️",dx+dw-10,ty,tcol)
        end
    end
end


-- PARTICLE SYSTEM
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

function ptl_spawn(x,y,z,col,count)
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
        add(ptl,p)
    end
end

function ptl_explode(wx,wy,z,scale)
    local function add_group(radius,speed,size_px,life,count)
        for _=1,count do
            local angle=rnd()
            local dist=rnd()*radius*scale*0.1
            local vel=rnd()*speed*scale*0.005
            add(ptl,make_particle(
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

function ptl_update()
    for i=#ptl,1,-1 do
        local p=ptl[i]
        p.x+=p.vx
        p.y+=p.vy
        p.z+=p.vz
        p.vx*=0.95
        p.vy*=0.95
        p.vz*=0.975
        p.life-=1
        if p.life<=0 then deli(ptl,i) end
    end
    while #ptl>100 do deli(ptl,1) end
end

function ptl_draw()
    for p in all(ptl) do
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


-- GAME MANAGER
function gm_reset()
    gm_state,gm_evt,gm_idle_t="idle",nil,gm_tut and time()-3 or nil
    gm_nidx,gm_score,gm_dscore,gm_diff=1,0,0,0
end

function gm_update()
    -- tutorial
    if not gm_tut then
        if ps.last_shot_time>time() then return end
        gm_tut_moved=gm_tut_moved or btn(⬆️) or btn(⬇️) or btn(⬅️) or btn(➡️)
        gm_tut_shot=gm_tut_shot or btn(❎)
        gm_tut_col=gm_tut_col or ps.ammo>50
        gm_tut_mine=gm_tut_mine or ps.mines<7

        local new_msg=nil
        if not gm_tut_moved then
            new_msg="aRROW KEYS TO MOVE"
        elseif not gm_tut_shot then
            new_msg="❎ tO sHOOT"
        elseif not gm_tut_col then
            new_msg="cOLLECT aMMO"
        elseif not gm_tut_mine then
            new_msg="🅾️ tO dROP mINE"
        elseif not gm_tut then
            gm_tut=true
            ui_say("hORIZON gLIDE bEGINS!",2,11)
            gm_idle_t=time()-3
            return
        else return end

        if new_msg!=gm_tut_msg then
            gm_tut_msg=new_msg
            ui_say(new_msg,(new_msg=="good luck!") and 2 or 99,11)
        end
        return
    end

    if gm_state=="idle" then
        if time()-gm_idle_t>=gm_idle_dur then
            gm_start_evt()
        end
    else
        if gm_evt then
            evt_update()
            if ps.hp<=0 then
                gm_evt.completed,gm_evt.success,ps.dead,ui_rmsg=true,false,true,""
            end
            if gm_evt.completed then gm_end_evt(gm_evt.success) end
        end
    end
end

function gm_start_evt()
    local t=gm_nidx
    if t==1 then
        -- combat event
        ui_say("enemy wave incoming!",3,8)
        enemies={}
        local n=min(1+gm_diff,6)
        for _=1,n do
            local a,d=rnd(1),10+rnd(5)
            add(enemies,ship_new(ps.x+cos(a)*d,ps.y+sin(a)*d,true))
        end
        gm_evt={type=1,start_count=#enemies,last_msg=nil,completed=false,success=false}
    elseif t==2 then
        -- circle event
        local r=gm_diff
        local recharge=max(gm_rcmin,gm_rcs-r*gm_rcstep)
        local circles={}
        local n=gm_rb+r*gm_rs
        for _=1,n do
            local a,d=rnd(1),8+rnd(4)
            add(circles,{x=ps.x+cos(a)*d,y=ps.y+sin(a)*d,radius=1.5,collected=false})
        end
        gm_evt={type=2,circles=circles,current_target=1,end_time=time()+gm_bt,recharge=recharge,completed=false,success=false}
        ui_say("cOLLECT "..#circles.." cIRCLES!",1.5,8)
        ui_rmsg=flr(gm_bt).."s"
    else
        -- bomb event
        ui_say("incoming bombs!",3,8)
        gm_evt={type=3,bombs={},next_bomb=time(),end_time=time()+8,completed=false,success=false}
    end
    gm_nidx=gm_nidx%3+1
    gm_state="active"
end

function gm_end_evt(success)
    gm_state="idle" gm_idle_t=time() ui_rmsg=""
    if success or not ps.dead then
        ui_say(success and "event complete!" or "event failed",3,success and 11 or 8)
    end
    if success and gm_nidx==1 then
        gm_diff+=1
    end
    gm_evt=nil
end


-- EVENT UPDATE DISPATCH
function evt_update()
    local e=gm_evt
    if e.type==1 then
        -- combat
        for i=#enemies,1,-1 do ship_update(enemies[i]) end
        local remaining=#enemies
        if remaining==0 then
            e.completed,e.success=true,true
            gm_score+=1000
            return
        end
        if remaining<e.start_count then
            local msg=(remaining==1) and "1 enemy left" or (remaining.." enemies left")
            if e.last_msg!=msg then ui_say(msg,3,8) e.last_msg=msg end
        end
    elseif e.type==2 then
        -- circle
        local time_left=e.end_time-time()
        if time_left<=0 then
            e.completed,e.success=true,false
            ui_say("event failed",1.5,8)
            ui_rmsg=""
            return
        end
        ui_rmsg=fmt2(max(0,time_left)).."s"
        local circle=e.circles[e.current_target]
        if circle and not circle.collected then
            if vdist(ps,circle.x,circle.y)<circle.radius then
                circle.collected=true
                sfx(59)
                ps.hp=min(ps.hp+10,ps.max_hp)
                if e.current_target<#e.circles then
                    e.end_time+=e.recharge
                    pop("+"..fmt2(e.recharge).."s",-10)
                    pop("+10hp",-20,11)
                end
                e.current_target+=1
                if e.current_target>#e.circles then
                    ps.hp=ps.max_hp
                    local award=#e.circles*100+500
                    e.completed,e.success=true,true
                    gm_score+=award
                    pop("+"..award,-10,7)
                    pop("full hp!",-20,11)
                    ui_say("event complete!",1.5,11)
                    ui_rmsg=""
                else
                    local remaining=#e.circles-e.current_target+1
                    ui_say(remaining.." circle"..(remaining>1 and "s" or "").." left",1,10)
                end
            end
        end
    else
        -- bomb
        if time()>e.end_time then
            e.completed,e.success=true,true
            gm_score+=800
            ps.mines=ps.max_mines
            pop("full mines!",-10,9)
            return
        end
        if time()>e.next_bomb then
            add(e.bombs,mn_new(
                ps.x+ps.vx*24,
                ps.y+ps.vy*24,
                nil
            ))
            e.next_bomb=time()+max(0.6,0.8-0.05*gm_diff)+rnd(0.3)
        end
        for i=#e.bombs,1,-1 do if not mn_update(e.bombs[i]) then deli(e.bombs,i) end end
    end
end

-- EVENT DRAW DISPATCH
function evt_draw()
    local e=gm_evt
    if e.type==1 then
        for en in all(enemies) do
            local q=en.hp/en.max_hp
            local dist=dist_trig(ps.x-en.x,ps.y-en.y)
            local mode=(q<=0.3 and dist>15) or (q>0.3 and (dist>20 or ((time()+en.ai_phase)%6)<3))
            draw_circle_arrow(en.x,en.y,mode and 8 or 9)
        end
        for en in all(enemies) do ship_draw(en) end
    elseif e.type==2 then
        local t=time()
        for i=1,#e.circles do
            local circle=e.circles[i]
            if not circle.collected then
                local sx,sy=iso(circle.x,circle.y)
                local base_y=sy-terrain_h(flr(circle.x),flr(circle.y))*block_h
                local cur=(i==e.current_target)
                local base_radius=10
                local col=cur and 10 or 9
                draw_iso_ellipse(sx,base_y,base_radius,base_radius*0.5,col,0.01)
                if cur then
                    for ring=0,2 do
                        local z=(t*15+ring*8)%24
                        local r=base_radius*(1+z/24)
                        draw_iso_ellipse(sx,base_y-z,r,r*0.5,col,0.02)
                    end
                end
            end
        end
        local target=e.circles[e.current_target]
        if target and not target.collected then
            draw_circle_arrow(target.x,target.y,9)
        end
    else
        for m in all(e.bombs) do mn_draw(m) end
    end
end


-- COLLECTIBLES
function col_new(x,y)
    return {x=x,y=y,collected=false}
end

function col_update(c)
    if c.collected then return false end
    local d=vdist(ps,c.x,c.y)
    if d>20 then return false end
    if d<1 then
        c.collected=true
        sfx(61)
        ps.ammo=min(ps.ammo+10,ps.max_ammo)
        pop("+10ammo",-10,12)
        gm_score+=25
        return false
    end
    return true
end

function col_draw(c)
    if not c.collected then
        local sx,sy=iso(c.x,c.y)
        local h=terrain_h(c.x,c.y)*block_h
        ovalfill(sx-5,sy-h+3,sx+5,sy-h+5,1)
        spr(67,sx-8,sy-h-8+sin(time()*2+c.x+c.y),2,2)
    end
end

function manage_cols()
    for i=#cols,1,-1 do if not col_update(cols[i]) then deli(cols,i) end end
    while #cols<15 do
        local a,d=rnd(),8+rnd(15)
        add(cols,col_new(ps.x+cos(a)*d,ps.y+sin(a)*d))
    end
end


-- MINE
-- owner: ps=player, enemy table=enemy, nil=bomb
function mn_new(x,y,owner)return {x=x,y=y,owner=owner,z=owner and 0 or 60}end

function mn_update(m)
    if m.z>0 then
        m.z=max(0,m.z-2)
        return true
    end
    if not m.owner then
        -- bomb mine: damage player on landing
        ptl_explode(m.x,m.y,-terrain_h(m.x,m.y,true)*block_h,1.5)
        sfx(62)
        if vdist(ps,m.x,m.y)<2 then ps.hp-=10 ui_react("ouch!",1,8) end
        return false
    end
    for t in all(m.owner==ps and enemies or{ps})do
        if vdist(t,m.x,m.y)<2 then
            ptl_explode(m.x,m.y,-terrain_h(m.x,m.y,true)*block_h,1.5)
            t.hp-=15 sfx(62)
            return false
        end
    end
    return true
end

function mn_draw(m)
    local sx,sy=iso(m.x,m.y)
    local col=m.owner==ps and 12 or 8
    local gz=terrain_h(m.x,m.y,true)*block_h
    draw_iso_ellipse(sx,sy-gz,24,12,col,0.04)
    sy+=m.z>0 and -m.z or -gz
    local r=4+sin(time()*6+m.x+m.y)*1.5
    circfill(sx,sy,r,7)circfill(sx,sy,r/2,col)
end


-- SHIP (shared between player and enemies)
function ship_new(x,y,is_enemy)
    return {
        x=x,y=y,vx=0,vy=0,vz=0,
        hover_height=1,current_altitude=0,cam_alt=0,
        angle=0,accel=0.025,friction=0.95,max_speed=is_enemy and 0.16 or 0.2,
        projectile_speed=0.2,projectile_life=80,fire_rate=is_enemy and 0.15 or 0.1,
        size=11,body_col=is_enemy and 8 or 12,outline_col=7,shadow_col=1,
        gravity=0.025,is_hovering=false,particle_timer=0,ramp_boost=0.1,
        is_enemy=is_enemy,max_hp=is_enemy and 50 or 100,hp=is_enemy and 50 or 1,
        target=nil,ai_phase=is_enemy and rnd(6) or 0,
        max_ammo=is_enemy and 9999 or 100,ammo=is_enemy and 9999 or 50,
        mines=is_enemy and 9999 or 7,max_mines=is_enemy and 9999 or 15,
        last_shot_time=0,ai_state=is_enemy and "approach" or nil,charge_timer=0
    }
end

function ship_set_alt(s)
    s.current_altitude=terrain_h(s.x,s.y,true)+s.hover_height
end

function ship_spos(s)
    local sx,sy=iso(s.x,s.y)
    return sx,sy-s.current_altitude*block_h
end

function ship_cam(s)
    local fx,fy=s.x,s.y
    if not s.is_enemy then
        local best,ne=10
        for e in all(enemies) do
            local d=dist_trig(e.x-fx,e.y-fy)
            if d<best then best=d ne=e end
        end
        s.cam_blend=(s.cam_blend or 0)+(ne and 0.01 or -0.015)
        s.cam_blend=mid(0,s.cam_blend,0.2)
        if ne and s.cam_blend>0 then
            fx+=(ne.x-fx)*s.cam_blend
            fy+=(ne.y-fy)*s.cam_blend
        end
    end
    s.cam_alt+=(s.current_altitude-s.cam_alt)*0.08
    local sx=(fx-fy)*half_tile_width
    local sy=(fx+fy)*half_tile_height-s.cam_alt*block_h
    return 64-sx,64-sy
end

function ship_fire(s)
    if not s.target then return end
    if s.ammo<=0 then
        if not s.is_enemy and (not s.last_no_ammo_msg or time()-s.last_no_ammo_msg>2) then
            ui_say("no ammo!",2,8)
            s.last_no_ammo_msg=time()
        end
        return
    end
    local dx,dy=s.target.x-s.x,s.target.y-s.y
    local dist=dist_trig(dx,dy)
    add(projs,{
        x=s.x,y=s.y,z=s.current_altitude,
        vx=s.vx+dx/dist*s.projectile_speed,
        vy=s.vy+dy/dist*s.projectile_speed,
        life=s.projectile_life,
        is_enemy=s.is_enemy,
    })
    s.ammo-=1
    sfx(63)
end

function ship_targeting(s)
    local fx,fy=cos(s.angle),sin(s.angle)
    local best,found=15,nil
    for t in all(s.is_enemy and {ps} or enemies) do
        if t~=s then
            local dx,dy=t.x-s.x,t.y-s.y
            local d=dist_trig(dx,dy)
            if d<best and (dx*fx+dy*fy)>.5*d then best=d found=t end
        end
    end
    if found then s.target=found return true end
    local world_angle=atan2(s.vx,s.vy)
    s.target=s.is_enemy and nil or {x=s.x+cos(world_angle)*10,y=s.y+sin(world_angle)*10}
    return false
end

function ship_ai(s)
    local dx,dy=ps.x-s.x,ps.y-s.y
    local dist=dist_trig(dx,dy)
    local q=s.hp/s.max_hp
    local mode=(q<=0.3 and dist>15) or (q>0.3 and (dist>20 or ((time()+s.ai_phase)%6)<3))
    if not mode then dx,dy=-dx,-dy end

    for e in all(enemies) do
        if e~=s then
            local ex,ey=s.x-e.x,s.y-e.y
            local d=dist_trig(ex,ey)
            if d<4 then local w=4-d dx+=ex*w dy+=ey*w end
        end
    end

    local m=dist_trig(dx,dy)
    if m>0.1 then s.vx+=dx*s.accel/m s.vy+=dy*s.accel/m end

    local t=time()
    if mode and ship_targeting(s) and (not s.last_shot_time or t-s.last_shot_time>s.fire_rate) then
        ship_fire(s)
        s.last_shot_time=t
    end

    if not mode and dist<8 and (not s.last_mine_time or t-s.last_mine_time>1) then
        add(mines,mn_new(s.x,s.y,s))
        s.last_mine_time=t
    end
end

function ship_update(s)
    if s.is_enemy then
        ship_ai(s)
    else
        tm_setpos(s.x,s.y)
        local rx=(btn(➡️) and 1 or 0)-(btn(⬅️) and 1 or 0)
        local ry=(btn(⬇️) and 1 or 0)-(btn(⬆️) and 1 or 0)
        s.vx+=(rx+ry)*s.accel*0.707
        s.vy+=(-rx+ry)*s.accel*0.707

        ship_targeting(s)
        if btn(❎) and (not s.last_shot_time or time()-s.last_shot_time>s.fire_rate) then
            ship_fire(s)
            s.last_shot_time=time()
        end
        if btnp(🅾️) and s.mines>0 then
            add(mines,mn_new(s.x,s.y,s))
            s.mines-=1
            sfx(60)
        end
    end

    -- movement & clamp
    s.vx*=s.friction s.vy*=s.friction
    local speed=dist_trig(s.vx,s.vy)
    local sc=(speed>s.max_speed) and (s.max_speed/speed) or 1
    s.vx*=sc s.vy*=sc
    s.x+=s.vx s.y+=s.vy

    -- terrain ramp launch
    local new_terrain=terrain_h(s.x,s.y)
    local height_diff=new_terrain-terrain_h(s.x-s.vx,s.y-s.vy)
    if s.is_hovering and height_diff>0 and speed>0.01 then
        s.vz=min(height_diff*s.ramp_boost*speed*30,0.75)
        s.is_hovering=false
    end

    -- altitude physics
    local target_altitude=new_terrain+s.hover_height
    if s.is_hovering then
        s.current_altitude+=(target_altitude-s.current_altitude)*0.3 s.vz=0
    else
        s.current_altitude+=s.vz
        s.vz-=s.gravity
        if s.current_altitude<=target_altitude then
            s.current_altitude=target_altitude s.vz=0 s.is_hovering=true
        end
        s.vz*=0.995
    end

    -- exhaust particles
    if s.is_hovering and speed>0.01 then
        s.particle_timer+=1
        if s.particle_timer>=max(1,5-flr(speed*10)) then
            s.particle_timer=0
            ship_spawn_p(s,1+flr(speed*5))
        end
    else
        s.particle_timer=0
    end

    -- facing
    s.angle=atan2(s.vx-s.vy,(s.vx+s.vy)*0.5)

    -- water rings
    if s.is_hovering and speed>0.1 then
        s.st=(s.st or 0)+1
        if s.st>8 then add(ws,{x=s.x,y=s.y,r=0,life=56}) s.st=0 end
    end
end

function ship_draw(s)
    local sx,sy=ship_spos(s)
    local ship_len=s.size*0.8
    local half_ship_len=ship_len*0.5

    local fx,fy=sx+cos(s.angle)*ship_len,sy+sin(s.angle)*half_ship_len
    local back_angle=s.angle+0.5
    local p2x=sx+cos(back_angle-0.15)*ship_len
    local p2y=sy+sin(back_angle-0.15)*half_ship_len
    local p3x=sx+cos(back_angle+0.15)*ship_len
    local p3y=sy+sin(back_angle+0.15)*half_ship_len

    local so=(s.current_altitude-terrain_h(s.x,s.y))*block_h
    draw_triangle(fx,fy+so,p2x,p2y+so,p3x,p3y+so,s.shadow_col)
    draw_triangle(fx,fy,p2x,p2y,p3x,p3y,s.body_col)
    line(fx,fy,p2x,p2y,s.outline_col)
    line(p2x,p2y,p3x,p3y,s.outline_col)
    line(p3x,p3y,fx,fy,s.outline_col)

    if s.is_hovering then
        local c=sin(time()*5)>0 and 10 or 9
        pset(p2x,p2y,c)
        pset(p3x,p3y,c)
    end

    if s.is_enemy then
        rectfill(sx-5,sy-10,sx+5,sy-9,5)
        rectfill(sx-5,sy-10,sx-5+s.hp/s.max_hp*10,sy-9,8)
    end
end

function ship_spawn_p(s,num,col_override)
    ptl_spawn(
        s.x,s.y,
        -s.current_altitude*block_h,
        col_override or (terrain_h(s.x,s.y)<=0 and 7 or 0),
        num
    )
end


function update_projs()
    for i=#projs,1,-1 do
        local p=projs[i]
        p.x+=p.vx p.y+=p.vy p.life-=1

        if p.is_enemy then
            -- enemy projectile: check player
            local dh=(p.z-ps.current_altitude)/6
            local dx,dy=ps.x-p.x+dh,ps.y-p.y+dh
            if dx*dx+dy*dy<0.5 then
                ps.hp-=3
                ui_react("ouch!",1,8)
                sfx(58)
                p.life=0
                ptl_explode(p.x,p.y,-ps.current_altitude*block_h,0.8)
                if ps.hp<=0 then
                    sfx(62)
                    ptl_explode(ps.x,ps.y,-ps.current_altitude*block_h,3)
                end
            end
        else
            -- player projectile: check enemies
            for _,t in pairs(enemies) do
                local dh=(p.z-t.current_altitude)/6
                local dx,dy=t.x-p.x+dh,t.y-p.y+dh
                if dx*dx+dy*dy<0.5 then
                    t.hp-=3
                    sfx(58)
                    p.life=0
                    ptl_explode(p.x,p.y,-t.current_altitude*block_h,0.8)
                    if t.hp<=0 then
                        sfx(62)
                        ptl_explode(t.x,t.y,-t.current_altitude*block_h,3)
                        del(enemies,t)
                        gm_score+=200
                    end
                    break
                end
            end
        end

        if p.life<=0 then deli(projs,i) end
    end
end


function pop(text,dy,col)
    local sx,sy=ship_spos(ps)
    add(ftexts,ft_new(sx,(sy+(dy or -10)),text,col))
end

function ui_say(t,d,c)
    ui_msg=t
    ui_vis,ui_col,ui_until,ui_box_target_h=0,(c or 7),(d and time()+d or 0),26
end
function ui_react(t,d,c)
    ui_shake=8
    if ui_msg=="" and rnd()<.25 then ui_say(t,d,c) end
end


function ui_tick()
    ui_box_h+=(ui_box_target_h-ui_box_h)*0.1
    if abs(ui_box_h-ui_box_target_h)<0.5 then ui_box_h=ui_box_target_h end
    if ui_msg=="" or ui_box_h<=25 then return end
    if ui_vis<#ui_msg then
        ui_vis=min(ui_vis+(#ui_msg>15 and 1.5 or 0.5),#ui_msg)
    end
    if ui_until>0 and time()>ui_until then
        ui_msg,ui_vis,ui_until,ui_box_target_h="",0,0,6
    end
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



-- TILE MANAGER
tm_px,tm_py,tm_cm,tm_target=0,0,0,2

function tm_init()
    tm_px,tm_py,tm_cm=0,0,0
    if not tm_pal then
        tm_pal={}
        for i=1,8 do
            local p=(i-1)*3+1
            tm_pal[i]={ord(TERRAIN_PAL_STR,p),ord(TERRAIN_PAL_STR,p+1),ord(TERRAIN_PAL_STR,p+2)}
        end
    end
end

function tm_setpos(px,py)
    tm_px,tm_py=flr(px),flr(py)
end

function tm_cache()
    local px,py=tm_px,tm_py
    local cm=min(tm_cm,tm_target)
    local pxm,pym=px-cm,py-cm
    local pxp,pyp=px+cm,py+cm
    local cache=cell_cache
    local perm=tperm
    local thresh=TERRAIN_THRESH
    local palcache=tm_pal
    local scale=mopts[1].values[mopts[1].current]
    local water_level=mopts[2].values[mopts[2].current]

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

    if cm<tm_target then cm+=1 end
    tm_cm=cm
end




-- TERRAIN GENERATION
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
11f111ccccccccccccccccfffffffffffffffffffffffffffffffff111333333333101fffffffffffffffffffffffff121f1212ccccccccccccccccccccccc11
fffffcccccccccccccccfffffffffffffffffffffffffffffffffffff11133333000fffffffffffffffffffffffff222fffff2cccccccccccccccccccccc1111
fffffffccccccc3cccffffffffffffffffffff3ffffffffffffffffffff1113000fffffffffffffffffffffffff222fffffffffcccccccccccccccccccc11111
fffffffff11133333fffffffffffffffffff33333ffffffffffffffffffff100fffffffffffffffffffffffff222fffffffffffff111111111111111cccccccc
ff3fffffff333333333fffffffffffffff333333333ffffffffffffffffffffffffffffffffffffffffffff222fffffffffffffffffcccccccccccccccccccc1
33333fff3333333333333fffffffffff3333333333333ffffffffffffffff244fffffffffffffffffffff222fffffffffffffffffffffccccccccccccccccccc
33333333333333333333333fff3fff33333333333333333ffffffffffff222f444fffffffffffffffff222fffffffffffffffffffffffffccccccccccccccccc
3333333333333333333333333333333333333333333333333ffffffff222fffff444fffffffffffff222fffffffffffffffffffffffff2211111111111111111
333333333333333333333333333333333333333333333333333ffff222fffffffff444fffffffff222fffffffffffffffffffffffff2222ccccccccccccccccc
333333333333333333333333333333333333333333333333300ff222fffffffffffff444fffff222fffffffffffffffffffffffff22222cccccccccccccccccc
333333333333333333333003333300000000000000000000000000000000000000000000000022ff000ffffffffffffffffffff22222cccccccccccccccccccc
333333333333333333330c0333330c0ccccccccc0ccccccccc0c0ccccccccc0ccccccccc0cc00fff0c0ffffffffffffffffff22222cccccccccccccccccccccc
33b333333333333333330c0000000c0c0000000c0c0000000c0c000000cc000c0000000c0c0cc0ff0c0ffffffffffffffff22222cccccccccccccccccccccccc
bbbbb3333333333333330ccccccccc0c0333300c0ccccccccc0c0f000c00ff0c0fffff0c0c000c000c0ffffffffffffff22222cccccccccccccccccccccccccc
bbbbbbb33333333333330c0000000c0c0000000c0c0000cc000c000cc000000c0000000c0c0440cc0c0ffffffffffff222221111111111111111111111c11111
bbbbbbbbb333333333330c0330030c0ccccccccc0c0ff000cc0c0ccccccccc0ccccccccc0c044400cc0ffffffffff22222cccccccccccccccccccccccccccccc
bbbbbbbbbbb33333333300000003000000000000000ffff0000000000000000000000000000cc444000ffffffff22222cccccccccccccccccccccccccccccccc
bbbbbbbbbbbbb33333330000000330003333333333333ffffffffffffffff22ff22222ccccccccc44444fffff22222cccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbb33330000000300033333333333333333ffffffffffff222f22222ccccccccccccc44444f22222cccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbb113300000003333333333333333333333333ffffffff222fffff2ccccccccccccccccc4442222cccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbb1113000000033333333333333333333333333333ffff222fffffffff1000000000000011114220000000000001000000001c11111111111111111
bbbbbbbbb111333330003333333333333333333333333333300ff222ffffffffffff0ccccccccc0c0ccccccc0c0cccccccc00cccccccc00ccccccccccccccccc
bbbbbbb1113333333333333333333333333333333333333000f222ffffffffffffff0c000000000c0ccccccc0c0c0000000c0c0000000c0ccccccccccccccccc
b11bb1113333333333333333333333333333333333333000ffffffffffffffffffff0c00cccccc0c0ccccccc0c0c0ccccc0c0cccccccc00ccccccccccccccccc
11b1113333333333333333333333333333333333333000ffffffffffffffffffffff0c0000000c0c000000000c0c0000000c0c00000000cccccccccccccccccc
bbbbb333333333333333333333333333333330033000ffffffffffffffffffffffff0ccccccccc0ccccccccc0c0cccccccc00cccccccc00ccccccccccccccccc
bbbbbbb33333333333333333333333333330003000ffffffffffffffffffffffffff00000000000000000000000000000000c00000000c0ccccccccccccccccc
bbbbbbbbb33333333333333330033333300033333ffffffffffffffffffffffffffff22222ccc1111111111111111111ccccc1111111100111111111ccccc111
bbbbbbbbbbb33333333333300003333000333333333ffffffffffffffffffffffff22222cccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbb33333333000000330003333333333333ffffffffffffffff22ff22222cccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbb33330000000300033333333333333333ffffffffffff222f22222cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbb113300000003333333333333333333333333ffffffff222fffff2cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbb1113000000033333333333333333333333333333ffff222fffffffffccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbb111333330003333333333333333333333333333300ff222fffffffffffff111111111111111ccccc1111111111111111111ccccc111111111111111
bbbbbbb1113333333333333333333333333333333333333000f222fffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbb1113333333333333333333333333333333333333000fffffffffffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbb1113333333333333333333333333333333333333000fffffffffffffffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccccccc
b1113333333333333333333333333333333333333000fffffffffffffffffffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccccc
1133333333333333333333333333333333333333333fffffffffffffffffff3ffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccccc
333333333333333333333333300333333333333333333fffffffffffffff33333ffffffffffffffffccccccccccccccccccccccccccccccccccccccccccccccc
33333333333333333333333000333333333333333333333fffffffffff333333333ffffffffffffffff111f1111111ccccccccc1111111f1111111ccccccccc1
3333333333333333333330003333333333333333333333333fffffff3333333333333ffffffffffffffffffffcccccccccccccccccccfffffccccccccccccccc
333333333333333333300033333333333333333333333333333fff33333333333333333ffffffffffffffffffffcccccccccccccccfffffffffccccccc3ccccc
3333333333333333300033333333333333333333333333333333333333333333333333333ffffffffffffffffffffcccccccccccfffffffffffffccc33333ccc
333333333333333000333333333333333333333333333333333333333333333333333333333ffffffffffffffffffffccc3cccffffffffffffffff333333333f
33333333333333333333333333333333333333333333333333333333333333333333333333333fffffffffffffffffff33333fffffffffffffff333333333333
3333333333333333333333333333333333333333333333333333333333333333333333333333333fffffffffffffff333333333fffffffffff33333333333333
b33333333333333333333333333333333333333333333333333333333333333333333333333333333fffffffffff3333333333333fffffff3333333333333333
bbb33333333333333333333333b33333333333333333333333333333333333333333333333333333333fffffff33333333333333333fff333333333333333333
bbbbb3333333333333333333bbbbb33333333333333333333333333333333333333333333333333333333fff3333333333333333333333333333333333333333
bbbbbbb333333333333333bbbbbbbbb3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333
bbbbbbbbb33333333333bbbbbbbbbbbbb33333333333333333333333333333333333333333333333333330113333333333333333333333333333333333333333
bbbbbbbbbbb333b333bbbbbbbbbbbbbbbbb333333333333333333333333333333333333333333333333000f11133333333333333333333333333333333333330
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb33333333333333333333333333333333333333333333000fffff111333333333333333333333333333333333000
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3333333333333333333333333333333333333333000fffffffff1113333333333333333333333333333300033
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1133333333333333333333333333333333330033000fffffffffffff11133113333333333333333333330003333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1113333333333333333333333333333333330003000fffffffffffffffff111111133333333333333333000333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb11133333333333333333333333330033333300033333ffffffffffffffffffff1111111333333333333300033333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111333333333333333333333333300003333000333333333ffffffffffffffffffff11111113333333330003333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbb1113333333333333333333333333000000330003333333333333ffffffffffffffffffff111111133333000333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3333333333333333333333330000000300033333333333333333ffffffffffffffffffff1111111300033333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3333333333333333333300000003333333333333333333333333ffffffffffffffffffff11111003333333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3333333333333333000000033333333333333333333333333333ffffffffffffffffffff111333333333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb33333333333300000009777777777777777333333333333300ffffffffffffffffffffff1113333333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3333333300000003337cccccccccccc7333333333333000fffffffffffffffffffffffff11133333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1133333300000003333117ccccccccc77113333333330000044fffffffffffffffffffffffff111333333333333
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1111333300000003330333117ccccccc7111333333330000000f444fffffffffffffffffffffffff1113333333330
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111111330000000333300033317cccccc711333300330000000fffff444fffffffffffffffffffffffff11133333000
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111111130000000333333303333317ccc771133300000000000fffffffff444fffffffffffffffffffffffff1113000ff
bb33bbbbbbbbbbbbbbbbbbbbb11bb111111133333000333333333333333317c71133300000000000fffffffffffff444fffffffffffffffffffffffff100ffff
bbb333bbbbbbbbbbbbbbbbb111b111111133333333333333333333333333319113300000000000fffffffffffffffff444ffffffffffffffffffffffffffffff
bbbbb333bbbbbbbbbbbbb111bbbbb11133333333333333303333333333333311300000000000fffffffffffffffffffff444fffffffffffffffffffff244ffff
bbbbbbb333bbbbbbbbb111bbbbbbbbb3333333333333333333333333333333300000000000ffffffffffffffffffffffff4444fffffffffffffffff222f444ff
bbbbbbbbb333bbbbb111bbbbbbbbbbbbb333333333333333333333333333300000000000fffffffffffffffffffffffff2444444fffffffffffff222fffff444
bbbbbbbbbbb333b111bbbbbbbbbbbbbbbbb33333333333333333333333300000000000fffffffffffffffffffffffff22244444444fffffffff222fffffffff4
bbbbbbbbbbbbb311bbbbbbbbbbbbbbbbbbbbb3333333333330033333300000000000fffffffffffffffffffffffff22222c444444444fffff222ffffffffffff
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb333333330000333300000000000fffffffffffffffffffffffff22222ccccc444444444f222ffffffffffffff
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb113333330000003300000000000fffffffffffffffffffffffff22222ccccccccc444444422ffffffffffffffff
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111b33330000000300000000000fffffffffffffffffffffffff22222ccccccccccccc44444ffffffffffffffffff
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111bbbbb0000000333330000000fffffffffffffffffffffffff22222ccccccccccccccccc44444ffffffffffffffff
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111bbbbbbbbb000333333333000fffffffffffffffffffffffff22222ccccccccccccccccccccc44444ffffffffffffff
bbbbbbbbbbbbbbbbbbbbbbbbbbbbb111bbbbbbbbbbbbb333333333333ffffffffffffffffffffffff22222ccc1111111111111111111ccc44444ffffffffffff
33bbbbbbbbbbbbbbbbbbbbbbbbb111bbbbbbbbbbbbbbbbb333333333333ffffffffffffffffffff22222ccccccccccccccccccccccccccccc44444fffffffff2
b333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb333333333333ffffffffffffffff22222ccccccccccccccccccccccccccccccccc44444fffff222
bbb333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb333333333333ffffffffffff22222ccccccccccccccccccccccccccccccccccccc44444f22222
bbbbb333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb11333333333300ffffffffff22222ccccccccccccccccccccccccccccccccccccccccc4442222cc
bbbbbbb333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1111333333330000ffffffff22222ccccccccccccccccccccccccccccccccccccccccccccc422cccc
bbbbbbbbb333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111111333333000000ffffff22222cccccccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbb333bbbbbbbbbbbbbbbbbbbbbbbbbbbbb1111111133330000000fffff22222ccccccc111111111111111ccccccccc111111111111111ccccccccc1
bbbbbbbbbbbbb333bbbbbbbbbbbbbbbbbbbbb11bb111111bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbb333bbbbbbbbbbbbbbbbb11111111111bb000000000000000000000000000000bbcccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbbbb333bbbbbbbbbbbbb111111111111bb00000000000000000000000000000000bbccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbbbbbb333bbbbbbbbb11111111111111b000000000bbb0b000bbb0b0b0000000000bccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbbbbbbbb333bbbbb1111111111111113b000000000b0b0b000b0b0b0b0000000000b111ccccc1111111111111111111ccccc111111111111111
bbbbbbbbbbbbbbbbbbbbbbb333b111111111113111333b000000000bbb0b000bbb0bbb0000000000bccccccccccccccccccccccccccccccccccccccccccccccc
bbbbbbbbbbbbbbbbbbbbbbbbb31111111111333333333b0000000003000300030300030000000000bccccccccccccccccccccccccccccccccccccccccccccccc
33bbbbbbbbbbbbbbbbbbbbbbbbb111111133333333333b0000000003000333030303330000000000bccccccccccccccccccccccccccccccccccccccccccccc11
3333bbbbbbbbbbbbbbbbbbbbb11111113333333333333bb00000000000000000000000000000000bbccccccccccccccccccccccccccccccccccccccccccc1111
333333bbbbbbbbbbbbbbbbb11111113333333333333333bb000000000000000000000000000000bbcccccccccccccccccc1ccccccccccccccccccccccc111111
33333333bbbbbbbbbbbbb11111113333333333333333333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1111111111111111111111111111111111111111111111ccc
3333333333bbbbbbbbb11111113333333333333333333333333333300000000222222222cccccccccccccccccccccc111111111ccccccccccccccc1111111111
333333333333bbbbb11111113333333333333333333333333003300000000002222222cccccccccccccccccccccc1111111111111ccccccccccc111111111111
33333333333333b11111113333333333333333333333333000000000000000022222cccccccccccccccccccccc11111111111111111ccccccc11111111111111
33333333333333111111333333333333333333333ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
3333333333333331113333333333333333333333cc00000000000000000000000000000000000000000000cc1111111111111111111111111111111111111111
333333333333300133333333333333333333333cc0000000000000000000000000000000000000000000000cc111111111111111111111111111111111111111
333333333330003333333333333333333333333c000000077070700770777007707770777077707770000000c111111111111111111111111111111111111111
333333333000001133333333333333333333300c000000700070707000070070707770070000707000000000c111111111111111111111111111111111111111
333333300000003111333333333333333330000c000000700070707770070070707070070007007700000000c111111111111111111111111111111111111111
333330000000333331113333333333333000000c000000600060600060060060606060060060006000000000c111111111111111111111111111111111111111
113000000033333333311133333333300000000c000000066006606600060066006060666066606660000000cccccccccc1ccccccccccccccccccccccc1ccccc
310000003333333333333111333330000000000cc0000000000000000000000000000000000000000000000cc111111111111111111111111111111111111111
3330003333333333333333311130000000000000cc00000000000000000000000000000000000000000000cc1111111111111111111111111111111111111111
3000333333333333333333333100000000000000fcccccccccccccccccccccccccccccccccccccccccccccc11111111111111111111111111111111111111111
00333333333333333333333333300000000000fffffffffffffffffffffffffccc11111111111111111111111111111111111111111111111111111111111111
001133333333333333333333300000000000fffffffffffffffffffffffff22c1111111111111111111111111111111111111111111111111111111111111111
0031113333333333333333300000000000fffffffffffffffffffffffff2222ccccccccccccccccccccccc1ccccccccccccccccccccccc1ccccccccccccccccc
33333111333333333333300000000000fffffffffffffffffffffffff22222111111111111111111111111111111111111111111111111111111111111111111
333333311133333333300000000000fffffffffffffffffffffffff2222211111111111111111111111111111111111111111111111111111111111111111111
3333333331113333300000000000fffffffffffffffffffffffff222221111111111111111111111111111111111111111111111111111111111111111111111
33333333333111300000000000fffffffffffffffffffffffff22222111111111111111111111111111111111111111111111111111111111111111111111111
3333333333333100000000000044fffffffffffffffffffff2222211111111111111111111111111111111111111111111111111111111111111111111111111
333333333333333000000000004444fffffffffffffffff222221111111111111111111111111111111111111111111111111111111111111111111111111111
33333333333330000000000000c44444fffffffffffff22222111ccccccccccccccccccc11111ccccccccccccccccccc11111ccccccccccccccccccc11111ccc
333333333330000000000000ccccc44444fffffffff2222211111111111111111111111111111111111111111111111111111111111111111111111111111111
3333333330000000000000ccccccccc44444fffff222221111111111111111111111111111111111111111111111111111111111111111111111111111111111
33333330000000000000ccccccccccccc44444f22222111111111111111111111111111111111111111111111111111111111111111111111111111111111111
333330000000000000ccccccccccccccccc444222211111111111111111111111111111111111111111111111111111111111111111111111111111111111111

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

