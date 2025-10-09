pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- cache management test
-- test different cache strategies

-- config
view_range=7

-- perlin noise (minimal implementation)
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

terrain_pal_str="\1\0\0\12\1\1\15\4\2\3\1\0\11\3\1\4\2\0\6\5\0\7\6\5"
terrain_thresh=split"-2,0,2,6,12,18,24,99"
terrain_perm=generate_permutation(1337)
cell_cache={}
scale=12
water_level=0

function terrain(x,y)
    x,y=flr(x),flr(y)
    local key=x*10000+y
    local c=cell_cache[key]
    if c then return unpack(c) end

    local nx,ny=x/scale,y/scale
    local cont=perlin2d(nx*.03,ny*.03,terrain_perm)*15
    local hdetail=(perlin2d(nx,ny,terrain_perm)+perlin2d(nx*2,ny*2,terrain_perm)*.5+perlin2d(nx*4,ny*4,terrain_perm)*.25)*(15/1.75)
    local rid=abs(perlin2d(nx*.5,ny*.5,terrain_perm))^1.5
    local mountain=rid*max(0,cont/15+.5)*30
    local h=flr(mid(cont+hdetail+mountain-water_level,-4,28))

    local i=1
    while h>terrain_thresh[i] do i+=1 end
    local p=(i-1)*3+1
    cell_cache[key]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2),h}
    return unpack(cell_cache[key])
end

-- tile manager v1: numeric keys + box check (baseline from v5)
tile_manager_v1={
    player_x=0,
    player_y=0
}

function tile_manager_v1:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v1:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14

    -- phase 1: fill missing
    local added=0
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            if not cell_cache[x10k+y] then
                terrain(x,y)
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    local removed=0
    for k in pairs(cell_cache) do
        if removed>=10 then break end
        local x=flr(k/10000)
        if x<pxm14 or x>pxp14 then
            cell_cache[k]=nil
            removed+=1
        else
            local y=k%10000
            if y<pym14 or y>pyp14 then
                cell_cache[k]=nil
                removed+=1
            end
        end
    end
end

-- tile manager v2: store cache reference
tile_manager_v2={
    player_x=0,
    player_y=0
}

function tile_manager_v2:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v2:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache

    -- phase 1: fill missing
    local added=0
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            if not cache[x10k+y] then
                terrain(x,y)
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    local removed=0
    for k in pairs(cache) do
        if removed>=10 then break end
        local x=flr(k/10000)
        if x<pxm14 or x>pxp14 then
            cache[k]=nil
            removed+=1
        else
            local y=k%10000
            if y<pym14 or y>pyp14 then
                cache[k]=nil
                removed+=1
            end
        end
    end
end

-- tile manager v3: remove flr() in cleanup
tile_manager_v3={
    player_x=0,
    player_y=0
}

function tile_manager_v3:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v3:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache

    -- phase 1: fill missing
    local added=0
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            if not cache[x10k+y] then
                terrain(x,y)
                added+=1
            end
        end
    end

    -- phase 2: cleanup (k is already integer)
    local removed=0
    for k in pairs(cache) do
        if removed>=10 then break end
        local x=k\10000  -- integer division
        if x<pxm14 or x>pxp14 then
            cache[k]=nil
            removed+=1
        else
            local y=k%10000
            if y<pym14 or y>pyp14 then
                cache[k]=nil
                removed+=1
            end
        end
    end
end

-- tile manager v4: combine loops
tile_manager_v4={
    player_x=0,
    player_y=0
}

function tile_manager_v4:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v4:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            if not cache[x10k+y] then
                terrain(x,y)
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x=k\10000
        if x<pxm14 or x>pxp14 then
            cache[k]=nil
            removed+=1
        else
            local y=k%10000
            if y<pym14 or y>pyp14 then
                cache[k]=nil
                removed+=1
            end
        end
    end
end

-- tile manager v5: inline terrain call
tile_manager_v5={
    player_x=0,
    player_y=0
}

function tile_manager_v5:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v5:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local added,removed=0,0

    -- phase 1: fill missing (inline check)
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                -- inline terrain generation
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,terrain_perm)*15
                local hdetail=(perlin2d(nx,ny,terrain_perm)+perlin2d(nx*2,ny*2,terrain_perm)*.5+perlin2d(nx*4,ny*4,terrain_perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,terrain_perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>terrain_thresh[i] do i+=1 end
                local p=(i-1)*3+1
                cache[key]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x=k\10000
        if x<pxm14 or x>pxp14 then
            cache[k]=nil
            removed+=1
        else
            local y=k%10000
            if y<pym14 or y>pyp14 then
                cache[k]=nil
                removed+=1
            end
        end
    end
end

-- tile manager v6: single if for bounds
tile_manager_v6={
    player_x=0,
    player_y=0
}

function tile_manager_v6:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v6:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            if not cache[x10k+y] then
                terrain(x,y)
                added+=1
            end
        end
    end

    -- phase 2: cleanup - combined check
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v7: v5 + single if
tile_manager_v7={
    player_x=0,
    player_y=0
}

function tile_manager_v7:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v7:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local added,removed=0,0

    -- phase 1: fill missing (inline terrain)
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,terrain_perm)*15
                local hdetail=(perlin2d(nx,ny,terrain_perm)+perlin2d(nx*2,ny*2,terrain_perm)*.5+perlin2d(nx*4,ny*4,terrain_perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,terrain_perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>terrain_thresh[i] do i+=1 end
                local p=(i-1)*3+1
                cache[key]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup - single if
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v8: v7 + cache perlin perm
tile_manager_v8={
    player_x=0,
    player_y=0
}

function tile_manager_v8:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v8:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>terrain_thresh[i] do i+=1 end
                local p=(i-1)*3+1
                cache[key]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v9: v7 + cache terrain_thresh/pal
tile_manager_v9={
    player_x=0,
    player_y=0
}

function tile_manager_v9:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v9:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local pal=terrain_pal_str
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local p=(i-1)*3+1
                cache[key]={ord(pal,p),ord(pal,p+1),ord(pal,p+2),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v10: v9 + hardcode scale
tile_manager_v10={
    player_x=0,
    player_y=0
}

function tile_manager_v10:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v10:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local pal=terrain_pal_str
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12  -- hardcoded scale
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local p=(i-1)*3+1
                cache[key]={ord(pal,p),ord(pal,p+1),ord(pal,p+2),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v11: v9 + precalc p
tile_manager_v11={
    player_x=0,
    player_y=0
}

function tile_manager_v11:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v11:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local pal=terrain_pal_str
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local p3=(i-1)*3
                cache[key]={ord(pal,p3+1),ord(pal,p3+2),ord(pal,p3+3),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v12: v9 + skip ord calls
tile_manager_v12={
    player_x=0,
    player_y=0
}

function tile_manager_v12:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v12:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                -- skip palette lookup, just store h
                cache[key]={1,1,1,h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v13: binary search thresh
tile_manager_v13={
    player_x=0,
    player_y=0
}

function tile_manager_v13:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v13:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local pal=terrain_pal_str
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                -- unrolled threshold check
                local i=1
                if h>thresh[4] then
                    i=h>thresh[6] and (h>thresh[7] and 8 or 7) or (h>thresh[5] and 6 or 5)
                elseif h>thresh[2] then
                    i=h>thresh[3] and 4 or 3
                elseif h>thresh[1] then
                    i=2
                end
                local p=(i-1)*3+1
                cache[key]={ord(pal,p),ord(pal,p+1),ord(pal,p+2),h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v14: cache ord results
tile_manager_v14={
    player_x=0,
    player_y=0
}

function tile_manager_v14:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v14:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local pal=terrain_pal_str
    local added,removed=0,0

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local p=(i-1)*3+1
                local c1,c2,c3=ord(pal,p),ord(pal,p+1),ord(pal,p+2)
                cache[key]={c1,c2,c3,h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v15: precompute palette table
tile_manager_v15={
    player_x=0,
    player_y=0,
    palette_cache=nil
}

function tile_manager_v15:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v15:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local added,removed=0,0

    -- build palette cache once
    if not self.palette_cache then
        self.palette_cache={}
        for i=1,8 do
            local p=(i-1)*3+1
            self.palette_cache[i]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2)}
        end
    end
    local palcache=self.palette_cache

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local pal=palcache[i]
                cache[key]={pal[1],pal[2],pal[3],h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v16: v15 + all other opts
tile_manager_v16={
    player_x=0,
    player_y=0,
    palette_cache=nil
}

function tile_manager_v16:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v16:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local added,removed=0,0

    -- build palette cache once
    if not self.palette_cache then
        self.palette_cache={}
        for i=1,8 do
            local p=(i-1)*3+1
            self.palette_cache[i]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2)}
        end
    end
    local palcache=self.palette_cache

    -- phase 1: fill missing
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local x10k=x*10000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=x10k+y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local pal=palcache[i]
                cache[key]={pal[1],pal[2],pal[3],h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local x,y=k\10000,k%10000
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v17: 2D table instead of numeric keys
tile_manager_v17={
    player_x=0,
    player_y=0,
    palette_cache=nil
}

function tile_manager_v17:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v17:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local added,removed=0,0

    -- build palette cache once
    if not self.palette_cache then
        self.palette_cache={}
        for i=1,8 do
            local p=(i-1)*3+1
            self.palette_cache[i]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2)}
        end
    end
    local palcache=self.palette_cache

    -- phase 1: fill missing (2D table)
    for x=pxm14,pxp14 do
        if added>=10 then break end
        if not cache[x] then cache[x]={} end
        local cx=cache[x]
        for y=pym14,pyp14 do
            if added>=10 then break end
            if not cx[y] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local pal=palcache[i]
                cx[y]={pal[1],pal[2],pal[3],h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup (2D table)
    for x in pairs(cache) do
        if removed>=10 then break end
        if x<pxm14 or x>pxp14 then
            cache[x]=nil
            removed+=1
        else
            for y in pairs(cache[x]) do
                if removed>=10 then break end
                if y<pym14 or y>pyp14 then
                    cache[x][y]=nil
                    removed+=1
                end
            end
        end
    end
end

-- tile manager v18: safe numeric keys (offset + modulo)
tile_manager_v18={
    player_x=0,
    player_y=0,
    palette_cache=nil
}

function tile_manager_v18:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v18:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local added,removed=0,0

    -- build palette cache once
    if not self.palette_cache then
        self.palette_cache={}
        for i=1,8 do
            local p=(i-1)*3+1
            self.palette_cache[i]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2)}
        end
    end
    local palcache=self.palette_cache

    -- phase 1: fill missing (offset to handle negatives)
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local xoff=(x+16384)%32768  -- offset by 16384, wrap at 32768
        local xkey=xoff*1000
        for y=pym14,pyp14 do
            if added>=10 then break end
            local yoff=(y+16384)%32768
            local key=xkey+yoff
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local pal=palcache[i]
                cache[key]={pal[1],pal[2],pal[3],h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup
    for k in pairs(cache) do
        if removed>=10 then break end
        local yoff=k%1000
        local xoff=(k-yoff)/1000
        local x=(xoff-16384)%32768
        local y=(yoff-16384)%32768
        if x>16384 then x=x-32768 end
        if y>16384 then y=y-32768 end
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- tile manager v19: string concat but cached
tile_manager_v19={
    player_x=0,
    player_y=0,
    palette_cache=nil
}

function tile_manager_v19:update_player_position(px,py)
    self.player_x,self.player_y=flr(px),flr(py)
end

function tile_manager_v19:manage_cache()
    local px,py=self.player_x,self.player_y
    local pxm14,pym14=px-14,py-14
    local pxp14,pyp14=px+14,py+14
    local cache=cell_cache
    local perm=terrain_perm
    local thresh=terrain_thresh
    local added,removed=0,0

    -- build palette cache once
    if not self.palette_cache then
        self.palette_cache={}
        for i=1,8 do
            local p=(i-1)*3+1
            self.palette_cache[i]={ord(terrain_pal_str,p),ord(terrain_pal_str,p+1),ord(terrain_pal_str,p+2)}
        end
    end
    local palcache=self.palette_cache

    -- phase 1: fill missing (string keys, inline generation)
    for x=pxm14,pxp14 do
        if added>=10 then break end
        local xs=tostr(x)
        for y=pym14,pyp14 do
            if added>=10 then break end
            local key=xs..","..y
            if not cache[key] then
                local nx,ny=x/12,y/12
                local cont=perlin2d(nx*.03,ny*.03,perm)*15
                local hdetail=(perlin2d(nx,ny,perm)+perlin2d(nx*2,ny*2,perm)*.5+perlin2d(nx*4,ny*4,perm)*.25)*(15/1.75)
                local rid=abs(perlin2d(nx*.5,ny*.5,perm))^1.5
                local mountain=rid*max(0,cont/15+.5)*30
                local h=flr(mid(cont+hdetail+mountain,-4,28))
                local i=1
                while h>thresh[i] do i+=1 end
                local pal=palcache[i]
                cache[key]={pal[1],pal[2],pal[3],h}
                added+=1
            end
        end
    end

    -- phase 2: cleanup (string split)
    for k in pairs(cache) do
        if removed>=10 then break end
        local comma=0
        for i=1,#k do
            if sub(k,i,i)=="," then comma=i break end
        end
        local x,y=tonum(sub(k,1,comma-1)),tonum(sub(k,comma+1))
        if x<pxm14 or x>pxp14 or y<pym14 or y>pyp14 then
            cache[k]=nil
            removed+=1
        end
    end
end

-- simulation
current_manager=1
managers={
    {name="v16: numeric",obj=tile_manager_v16,time=nil},
    {name="v17: 2D table",obj=tile_manager_v17,time=nil},
    {name="v18: safe numeric",obj=tile_manager_v18,time=nil},
    {name="v19: string+inline",obj=tile_manager_v19,time=nil}
}

player_x,player_y=0,0
test_frames=0
max_test_frames=300
testing=false
all_tests_done=false

function run_all_tests()
    printh("===== cache management benchmark =====")
    for i=1,#managers do
        local m=managers[i]

        -- reset cache
        cell_cache={}
        for x=-14,14 do
            for y=-14,14 do
                terrain(x,y)
            end
        end

        -- reset manager
        local mgr=m.obj
        mgr.player_x,mgr.player_y=0,0
        if mgr.last_px then
            mgr.last_px,mgr.last_py=0,0
        end

        -- run test
        local px,py=0,0
        local start_time=stat(1)
        for j=1,max_test_frames do
            px+=0.3
            py+=0.2
            mgr:update_player_position(px,py)
            mgr:manage_cache()
        end
        local elapsed=stat(1)-start_time

        m.time=elapsed
        printh(m.name..": "..elapsed)
    end
    printh("=======================================")
end

function _init()
    run_all_tests()
    all_tests_done=true
end

function _update()
    -- switch managers
    if btnp(0) then
        current_manager=max(1,current_manager-1)
        test_frames=0
        testing=false
        player_x,player_y=0,0
    end
    if btnp(1) then
        current_manager=min(4,current_manager+1)
        test_frames=0
        testing=false
        player_x,player_y=0,0
    end

    -- rerun tests
    if btnp(4) then
        all_tests_done=false
        run_all_tests()
        all_tests_done=true
    end
end

function _draw()
    cls(1)

    if all_tests_done then
        print("all tests complete!",1,1,11)
        print("check console for results",1,7,7)
        print("",1,13,7)

        local y=25
        for i=1,#managers do
            local m=managers[i]
            local col=(i==current_manager) and 11 or 7
            print(m.name..": "..sub(tostr(m.time),1,6),1,y,col)
            y+=6
        end

        print("",1,y+6,7)
        print("\x8e\x91 switch | \x97 rerun",1,114,6)
    else
        print("running tests...",1,1,11)
    end
end
