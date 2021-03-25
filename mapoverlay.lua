-- Customizeable Region --

zoomlevel = 1       -- Starting zoom level
zoomrange = 3       -- Maximum zoom level
hexmap = false      -- Initial state of hexmap
pixmap = false      -- Initial state of pixelmap
hexcoords = true    -- How to display x,y (exact hex or decimal)

center = {120, 88}  -- coordinates of center of overlays
hexmapsize = 5
pixmapsize = 64

heightmap = {
    active = true,
    relative = true,
    show_neg = false,
}

flash = {
    value = nil,
    color = 0x000000FF,
}

controls = {
    hexmap    = {"shift", "O"},
    pixmap    = {"shift", "P"},
    zoom_in   = {"shift", "quote"},
    zoom_out  = {"shift", "semicolon"},
    teleport  = {"shift", "leftclick"},
    flash     = {"control", "leftclick"},
    increase  = {"control", "period"},
    decrease  = {"control", "comma"},
    relheight = {"shift", "L"},
    hexcoords = {"shift", "N"},
}

-- colormap consists of entries of the form {color, value1, value2, value3, ...}
-- the values may be numbers, or ranges of the form {lower, upper}, or preset strings
--     presets: "unknown", "door", "on_contact", "on_interact", "wall", "other"
-- the color will be applied to each corresponding value/range/preset
-- entries farther down on the list have higher priority
colormap = {
    {0xFFFFFFFF, "unknown"},
    {0x8000C0FF, "other"},
    {0x00FF00FF, "on_contact"},
    {0x0000FFFF, "on_interact"},
    {0xFF0000FF, "door"},
    {0x808080FF, "wall"},
    {0x00000080, 0},
}

print("Golden Sun 1 & 2 Map Overlay Script\tupdated March 25, 2021")
print("")
print("shift + O\t\ttoggle hex overlay")
print("shift + P\t\ttoggle pixel overlay")
print("shift + ; or '\tzoom in/out on pixel map")
print("shift + click\tteleport to position of cursor")
print("ctrl + click\tmake selected value flash")
print("ctrl + . or ,\tincrease/decrease value of tile hovered over")
print("shift + L\t\ttoggle relative vs absolute height")
print("shift + N\t\ttoggle x,y display type")

---------------------

GAME = {}
function GAME:update()
    local ROM = ""
    for i=0,11 do
        ROM = ROM..string.char(memory.readbyte(0x080000A0 + i))
    end
    if ROM ~= self.ROM then
        self.ROM = ROM
        if self.ROM == "Golden_Sun_A" then
            self.tilepntr = 0x020301B8
            self.eventpntr = 0x02030010
            self.xtown = 0x02030EC4
            self.ytown = 0x02030ECC
            self.mapaddr = 0x02000400
            self.xover = 0x02030DAC
            self.yover = 0x02030DB4
            self.pcdata_pntr = 0x02030014
        elseif self.ROM == "GOLDEN_SUN_B" then
            self.tilepntr = 0x020301A4
            self.eventpntr = 0x02030010
            self.xtown = 0x020322F4
            self.ytown = 0x020322FC
            self.mapaddr = 0x02000420
            self.xover = 0x020321C0
            self.yover = 0x020321C8
            self.pcdata_pntr = 0x03000014
        end
    end
end

inputs = {__update=true, __keyup=true, __keydown=true}
function inputs:update()
    self.keydown = {}
    self.keyup = {}
    local keys = input.get()
    for k, v in pairs(keys) do
        if not self[k] then self.keydown[k] = true end
        self[k] = (self[k] or 0) + 1
    end
    for k, v in pairs(self) do
        if not self["__"..k] and string.sub(k,1,2) ~= "__" and not keys[k] then
            if self[k] then self.keyup[k] = true end
            self[k] = nil
        end
    end
    local mouse = {X=keys["xmouse"], Y=keys["ymouse"]}
    if input.getmouse then mouse = input.getmouse() end
    self.xmouse = mouse["X"]
    self.ymouse = mouse["Y"]
    self.mouse = {mouse["X"], mouse["Y"]}
end

function get_event_type_ids()
    local type_map = {{}, {}, {}, other={}}
    local ids_found = {}
    local addr = memory.readdword(GAME.eventpntr)
    while addr < 0x02010000 and memory.readdword(addr) ~= 0xFFFFFFFF do
        local type = bit.band(memory.readbyte(addr), 0xF)
        local id = memory.readbyte(addr+4)
        if not ids_found[id] then
            if not type_map[type] then
                table.insert(type_map["other"], id)
            else
                table.insert(type_map[type], id)
            end
        end
        ids_found[id] = true
        addr = addr + 12
    end
    return type_map
end

function loadcolors()
    local colors = {}
    local type_map = get_event_type_ids()
    local name_map = {
        unknown     = {"default"},
        door        = type_map[1],
        on_contact  = type_map[2],
        on_interact = type_map[3],
        wall        = {0xFF},
        other       = type_map["other"],
    }
    for _,c in ipairs(colormap) do
        local color, entries = c[1], {unpack(c, 2)}
        for _,entry in ipairs(entries) do
            local t = type(entry)
            if t == "string" then
                for _,id in ipairs(name_map[entry]) do colors[id] = color end
            elseif t == "table" then
                for i=entry[1],entry[2] do colors[i] = color end
            else
                colors[entry] = color
            end
        end
    end
    for i=0,255 do
        if not colors[i] then colors[i] = colors.default or 0xFFFFFFFF end
    end
    return colors
end

function timed_display(x, y, text, duration)
    local obj = {x=x, y=y, text=text, duration=duration}
    local identifier = tostring({x, y})
    function obj:update()
        if self.duration == 0 then
            loop[self.handle] = nil
            loop[identifier] = nil
        else
            gui.text(self.x, self.y, self.text)
            self.duration = self.duration - 1
        end
    end
    if loop[identifier] then
        obj.handle = loop[identifier]
    else
        obj.handle = #loop + 1
        loop[identifier] = obj.handle
    end
    loop[obj.handle] = obj
end

function keycheck(key, hold)
    local state = false
    for _,k in pairs(controls[key]) do
        if not inputs[k] then return false end
        if not(k == "shift" or k == "alt" or k == "control") then
            if inputs.keydown[k] or (hold and inputs[k] and inputs[k] >= hold) then
                state = true
            end
        end
    end
    return state
end

function colliderect(point, box)
    local x, y = unpack(point)
    local x1, y1, x2, y2 = unpack(box)
    return x1 <= x and x <= x2 and y1 <= y and y <= y2
end

function gui_box(x1, y1, x2, y2, color)
    for x=x1,x2 do
        for y=y1,y2 do
            gui.pixel(x,y,color)
        end
    end
end

function hex(value, length)
    local length = length or 8
    return string.format("%0"..length.."X", value)
end

function shift_coords(xdiff, ydiff)
    local multiplier, xaddr, yaddr
    if overworld then
        xaddr, yaddr = GAME.xover, GAME.yover
    else
        xaddr, yaddr = GAME.xtown, GAME.ytown
    end
    memory.writedword(xaddr, bit.band(memory.readdword(xaddr) + xdiff, 0xFFFFFFFF))
    memory.writedword(yaddr, bit.band(memory.readdword(yaddr) + ydiff, 0xFFFFFFFF))
end

function hover_check(center, blocksize, blockcount)
    local xhalf, yhalf = math.floor(blocksize[1]/2), math.floor(blocksize[2]/2)
    local box = {
        center[1]-blocksize[1]*blockcount-xhalf, center[2]-blocksize[2]*blockcount-yhalf,
        center[1]+blocksize[1]*blockcount+xhalf-1, center[2]+blocksize[2]*blockcount+yhalf-1}
    if not colliderect(inputs.mouse, box) then return false end
    local xdiff = math.floor((inputs.xmouse-(center[1]-xhalf))/blocksize[1])
    local ydiff = math.floor((inputs.ymouse-(center[2]-yhalf))/blocksize[2])
    return true, xdiff, ydiff
end

function show_tiledata(x, y, name, data)  -- data is a table {x, y, addr}
    local xdisp, ydisp, addr = unpack(data)
    if not hexcoords then
        xdisp = string.format("%.2f", bit.band(xdisp, 0xFFFFFFFF) / 0x100000) + 0
        ydisp = string.format("%.2f", bit.band(ydisp, 0xFFFFFFFF) / 0x100000) + 0
    else
        xdisp, ydisp = hex(xdisp), hex(ydisp)
    end
    gui.text(x, y, name..hex(data[3])
        .." x:"..xdisp.." y:"..ydisp
        .." h:"..get_height(addr)
        .." hex:"..hex(memory.readbyte(data[3]+2),2)
        .." dec:"..memory.readbyte(data[3]+2)
    )
end

function index(array, value)
    for k,v in pairs(array) do
        if v == value then return k end
    end
end

function signed(value, bitcount)
    return bit.bxor(value, 2^(bitcount-1)) - 2^(bitcount-1)
end

function get_height(tileaddr)
    local h_index
    if GAME.ROM == "Golden_Sun_A" then
        h_index = memory.readbyte(tileaddr+3)
    elseif GAME.ROM == "GOLDEN_SUN_B" then
        local pc_data_addr = memory.readdword(0x03000014)
        local layer = memory.readbyte(pc_data_addr + 0x22)
        local layer_header = memory.readdword(0x03000020) + 0x138 + layer*0x38
        local base_addr = memory.readdword(layer_header)
        local height_addr = memory.readdword(layer_header + 4)
        local tile_offset = math.floor((tileaddr - base_addr)/4)
        h_index = memory.readbyte(height_addr + tile_offset)
    end
    local tile_type, h1, h2, h3 = unpack(memory.readbyterange(0x0202C000 + 4*h_index, 4))
    h1, h2, h3 = signed(h1, 8), signed(h2, 8), signed(h3, 8)
    tile_type = bit.band(tile_type, 0xF)
    local height
    if index({1,2,8,9}, tile_type) then
        return bit.arshift(h1 + h2, 2)
    elseif 7 == tile_type then
        return bit.arshift(h2, 1)
    else
        return bit.arshift(h1, 1)
    end
end

function height_text(x, y, text, color, height)
    local step
    if height == 0 then
        gui.text(x, y, text, color); return
    elseif height > 0 then
        step = 1
    else
        step = -1
    end
    if bit.arshift(color, 8) == 0 then color = 0xFFFFFFE0 end
    for i=0,height,step do
        gui.text(x-i, y-i, text, color, 0xE0)
    end
end


flash.count = 0
loop = {inputs, GAME}
while true do
    for _,obj in ipairs(loop) do obj:update() end
    flash.count = (flash.count + 1) % 60
    overworld = memory.readword(GAME.mapaddr) == 2
    
    if keycheck("hexmap") then hexmap = not hexmap end
    if keycheck("pixmap") then pixmap = not pixmap end
    if keycheck("zoom_in") and zoomlevel < zoomrange then
        zoomlevel = zoomlevel+1
        timed_display(2,152, "zoom: "..zoomlevel, 90)
    end
    if keycheck("zoom_out") and zoomlevel > 0 then
        zoomlevel = zoomlevel-1
        timed_display(2,152, "zoom: "..zoomlevel, 90)
    end
    if keycheck("relheight") then
        heightmap.relative = not heightmap.relative
        timed_display(2,152, "relheight: "..tostring(heightmap.relative), 90)
    end
    if keycheck("hexcoords") then
        hexcoords = not hexcoords
        timed_display(2,152, "hexcoords: "..tostring(hexcoords), 90)
    end

    local currentaddr = memory.readdword(GAME.tilepntr)
    local eventpntr = memory.readdword(GAME.eventpntr)
    if currentaddr >= 0x02000000 and eventpntr >= 0x02000000 then
        local colors = loadcolors()
        if flash.value and flash.count < 30 then colors[flash.value] = flash.color end
        local zoom = 2^zoomlevel
        local xaddr, yaddr, x_interval, y_interval, coord_mult
        local is_hovering, xdiff, ydiff
        if overworld then
            xaddr, yaddr = GAME.xover, GAME.yover
            x_interval, y_interval = 0x4, 0x80
            coord_mult = 0x200000
        else
            xaddr, yaddr = GAME.xtown, GAME.ytown
            x_interval, y_interval = 0x4, 0x200
            coord_mult = 0x100000
        end
        local xcurrent, ycurrent = memory.readdword(xaddr), memory.readdword(yaddr)
        show_tiledata(2, 2, "Tile:  ", {xcurrent, ycurrent, currentaddr})

        if pixmap then
            local overlaysize = math.floor(pixmapsize/zoom)
            local xcenter, ycenter = center[1]-math.floor(zoom/2), center[2]-math.floor(zoom/2)
            for y=-overlaysize,overlaysize do
                for x=-overlaysize,overlaysize do
                    local tilevalue = memory.readbyte(currentaddr + x_interval*x + y*y_interval + 2)
                    if zoom == 1 then
                        gui.pixel(x+xcenter, y+ycenter, colors[tilevalue])
                    else
                        local x1, y1 = x*zoom+xcenter, y*zoom+ycenter
                        gui_box(x1, y1, x1+zoom-1, y1+zoom-1, colors[tilevalue])
                    end
                end
            end
            local playercolor = 0xFFFF40FF
            gui.box(xcenter-1, ycenter-1, xcenter + zoom, ycenter + zoom, playercolor, 0xFF)
            is_hovering, xdiff, ydiff = hover_check(center, {zoom, zoom}, overlaysize)
        end

        if hexmap then
            local pc_data_addr = memory.readdword(GAME.pcdata_pntr)
            local pc_height = bit.arshift(memory.readwordsigned(pc_data_addr + 0x16), 4)
            for y=-hexmapsize,hexmapsize do
                for x=-hexmapsize,hexmapsize do
                    local tileaddr = currentaddr + y_interval*y + x_interval*x
                    local tilevalue = memory.readbyte(tileaddr + 2)
                    local xpos, ypos = center[1] + 12*x - 3, center[2] + 10*y - 4
                    local color = colors[tilevalue]
                    if heightmap.active and not overworld then
                        local height = get_height(tileaddr)
                        if heightmap.relative then height = height - pc_height end
                        if not heightmap.show_neg then height = math.max(0, height) end
                        height_text(xpos, ypos, hex(tilevalue, 2), color, height)
                        xpos, ypos = xpos - height, ypos - height
                    else
                        gui.text(xpos, ypos, hex(tilevalue, 2), color)
                    end
                    if x == 0 and y == 0 then
                        gui.box(xpos-2, ypos-1, xpos+8, ypos+7, 0, 0xFFFFFFFF)
                    end
                end
            end
            is_hovering, xdiff, ydiff = hover_check(center, {12, 10}, hexmapsize)
        end

        if is_hovering then
            local hoveraddr = currentaddr + x_interval*xdiff + y_interval*ydiff
            local hovervalue = memory.readbyte(hoveraddr+2)
            show_tiledata(2, 10, "Hover: ", {xdiff*coord_mult + xcurrent, ydiff*coord_mult + ycurrent, hoveraddr})
            if keycheck("teleport") then shift_coords(xdiff*coord_mult, ydiff*coord_mult) end
            if keycheck("flash") then
                if flash.value == hovervalue then flash.value = nil
                else flash.value = hovervalue end
                flash.count = 0
            end
            if keycheck("increase", 30) then memory.writebyte(hoveraddr+2, hovervalue+1) end
            if keycheck("decrease", 30) then memory.writebyte(hoveraddr+2, hovervalue-1) end
        end

    end

    emu.frameadvance()
end