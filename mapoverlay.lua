-- Created by Dyrati
-- Thanks to Teawater for the very first version of this script,
-- and for providing useful info that helped improve it

-- Customizeable Region --
    local zoomlevel = 1       -- Starting zoom level
    local zoomrange = 3       -- Maximum zoom level
    local hexmap = false      -- Initial state of hexmap
    local pixmap = false      -- Initial state of pixelmap
    local hud = true          -- Heads up display
    local hexcoords = true    -- How to display x,y (exact hex or decimal)

    local center = {120, 88}  -- coordinates of center of overlays
    local hexmapsize = 5
    local pixmapsize = 64

    local heightmap = {
        active = true,
        relative = true,
        show_neg = false,
    }

    local flash = {
        value = nil,
        color = 0x000000FF,
    }

    local controls = {
        hexmap    = {"shift", "O"},
        pixmap    = {"shift", "P"},
        zoom_in   = {"shift", "quote"},
        zoom_out  = {"shift", "semicolon"},
        teleport  = {"shift", "leftclick"},
        flash     = {"control", "leftclick"},
        increase  = {"control", "period"},
        decrease  = {"control", "comma"},
        relheight = {"shift", "L"},
        hud       = {"shift", "slash"},
    }

    -- colormap consists of entries of the form {color, value1, value2, value3, ...}
    -- the values may be numbers, or ranges of the form {lower, upper}, or preset strings
    -- the color will be applied to each corresponding value/range/preset
    local colormap = {    -- presets: "unknown", "door", "on_contact", "on_interact", "wall", "other"
        {0xFFFFFFFF, "unknown"},
        {0x8000C0FF, "other"},
        {0x00FF00FF, "on_contact"},
        {0x0000FFFF, "on_interact"},
        {0xFF0000FF, "door"},
        {0x808080FF, "wall"},
        {0x00000080, 0},
    }
--------------------------

local GAME = {}
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
            self.mapaddr = 0x02000400
            self.pc_data_pntr = 0x02030014
        elseif self.ROM == "GOLDEN_SUN_B" then
            self.tilepntr = 0x020301A4
            self.eventpntr = 0x02030010
            self.mapaddr = 0x02000420
            self.pc_data_pntr = 0x03000014
        end
    end
end

local inputs = {keys={}}
function inputs:update()
    self.keydown = {}
    self.keyup = {}
    local keys = input.get()
    for k, v in pairs(keys) do
        if not self.keys[k] then self.keydown[k] = true end
        self.keys[k] = (self.keys[k] or 0) + 1
    end
    for k, v in pairs(self.keys) do
        if not keys[k] then
            if self.keys[k] then self.keyup[k] = true end
            self.keys[k] = nil
        end
    end
    self.mouse = {keys["xmouse"], keys["ymouse"]}
    self.xmouse, self.ymouse = unpack(self.mouse)
end

local function UpdateLoop()
    local loop = {entries={}}
    function loop:update()
        for _,obj in pairs(self.entries) do obj:update() end
    end
    function loop:add(obj)
        table.insert(self.entries, obj)
    end
    function loop:del(obj)
        for k,v in pairs(self.entries) do
            if v == obj then self.entries[k] = nil; break end
        end
    end
    return loop
end

local function timed_text_handler()
    local handler = {}
    handler.entries = {}
    function handler:new(x, y, text, duration)
        local identifier = tostring({x, y})
        self.entries[identifier] = {x=x, y=y, text=text, duration=duration}
    end
    function handler:update()
        for identifier, entry in pairs(self.entries) do
            if entry.duration == 0 then
                self.entries[identifier] = nil
            else
                gui.text(entry.x, entry.y, entry.text)
                entry.duration = entry.duration - 1
            end
        end
    end
    return handler
end

local function get_event_type_ids()
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

local function loadcolors()
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

local function keycheck(key, hold)
    local state = false
    for _,k in pairs(controls[key]) do
        if not inputs.keys[k] then return false end
        if not(k == "shift" or k == "alt" or k == "control") then
            if inputs.keydown[k] or (hold and inputs.keys[k] and inputs.keys[k] >= hold) then
                state = true
            end
        end
    end
    return state
end

local function collidepoint(point, box)
    local x, y = unpack(point)
    local x1, y1, x2, y2 = unpack(box)
    return x1 <= x and x <= x2 and y1 <= y and y <= y2
end

local function gui_box(x1, y1, x2, y2, color)
    for x=x1,x2 do
        for y=y1,y2 do
            gui.pixel(x,y,color)
        end
    end
end

local function hex(value, length)
    local length = length or 8
    return string.format("%0"..length.."X", value)
end

local function shift_coords(xdiff, ydiff)
    local pc_data = memory.readdword(GAME.pc_data_pntr)
    local xaddr, yaddr = pc_data+0x8, pc_data+0x10
    memory.writedword(xaddr, bit.band(memory.readdword(xaddr) + xdiff, 0xFFFFFFFF))
    memory.writedword(yaddr, bit.band(memory.readdword(yaddr) + ydiff, 0xFFFFFFFF))
end

local function hover_check(center, blocksize, blockcount)
    local xhalf, yhalf = math.floor(blocksize[1]/2), math.floor(blocksize[2]/2)
    local box = {
        center[1]-blocksize[1]*blockcount-xhalf, center[2]-blocksize[2]*blockcount-yhalf,
        center[1]+blocksize[1]*blockcount+xhalf-1, center[2]+blocksize[2]*blockcount+yhalf-1}
    if not collidepoint(inputs.mouse, box) then return false end
    local xdiff = math.floor((inputs.xmouse-(center[1]-xhalf))/blocksize[1])
    local ydiff = math.floor((inputs.ymouse-(center[2]-yhalf))/blocksize[2])
    return true, xdiff, ydiff
end

local function highlight(x, y, text, color, height)
    if bit.arshift(color,8) == 0 and color ~= flash.color then
        color = 0xFFFFFF80
    end
    local x, y = x-height, y-height
    gui.text(x, y, text, color)
    local x1, y1, x2, y2 = x-2, y-1, x+8, y+7
    gui.box(x1, y1, x2, y2, 0, 0xFFFFFFFF)
    if height < 0 then gui.line(x1, y1, x1+height, y1+height, 0xFFFFFFFF) end
    gui.line(x1, y2, x1+height, y2+height, 0xFFFFFFFF)
    gui.line(x2, y1, x2+height, y1+height, 0xFFFFFFFF)
    gui.line(x2, y2, x2+height, y2+height, 0xFFFFFFFF)
end

local function index(array, value)
    for k,v in pairs(array) do
        if v == value then return k end
    end
end

local function signed(value, bitcount)
    return bit.bxor(value, 2^(bitcount-1)) - 2^(bitcount-1)
end

local function get_h_index(tileaddr)
    if GAME.ROM == "Golden_Sun_A" then
        return memory.readbyte(tileaddr+3)
    elseif GAME.ROM == "GOLDEN_SUN_B" then
        local pc_data = memory.readdword(GAME.pc_data_pntr)
        local layer = memory.readbyte(pc_data + 0x22)
        local layer_header = memory.readdword(0x03000020) + 0x138 + layer*0x38
        local base_addr = memory.readdword(layer_header)
        local height_addr = memory.readdword(layer_header + 4)
        local tile_offset = bit.arshift(tileaddr - base_addr, 2)
        return memory.readbyte(height_addr + tile_offset)
    end
end

local function get_height(tileaddr)
    local pc_data = memory.readdword(GAME.pc_data_pntr)
    local pc_height = bit.arshift(memory.readwordsigned(pc_data + 0x16), 4)
    local h_index = get_h_index(tileaddr)
    local tile_type, h1, h2, h3 = unpack(memory.readbyterange(0x0202C000 + 4*h_index, 4))
    tile_type = bit.band(tile_type, 0xF)
    h1, h2, h3 = signed(h1, 8), signed(h2, 8), signed(h3, 8)
    local h4 = bit.arshift(h1 + h2, 1)
    local h5 = math.max(h1, h2)
    if pc_height < bit.arshift(h5,1) then h5 = math.min(h1, h2) end
    local hmap = {
        [0x0] = h1,  -- floor
        [0x1] = h4,  -- left/right slope
        [0x2] = h4,  -- up/down slope
        [0x3] = h5,  -- slanted wall \
        [0x4] = h5,  -- slanted wall /
        [0x5] = h2,  -- slanted slope \
        [0x6] = h2,  -- slanted slope /
        [0x7] = h2,  -- circle
        [0x8] = h4,  -- left/right half split
        [0x9] = h4,  -- up/down half split
        [0xA] = h2,  -- triangle (up)
        [0xB] = h2,  -- triangle (down)
        [0xC] = h2,  -- triangle (right)
        [0xD] = h2,  -- triangle (left)
        [0xE] = h3,  -- 4-corners: 1,2,3,3
        [0xF] = h1,  -- 4-corners: 1,1,2,3
    }
    return bit.arshift(hmap[tile_type], 1)
end

local function show_tiledata(x, y, name, data)  -- data is a table {x, y, addr}
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

local function gui_text_3D(x, y, text, color, height)
    if height == 0 then
        gui.text(x, y, text, color); return
    elseif height > 0 then
        for i=0,height do gui.text(x-i, y-i, text, color, 0xE0) end
    else
        for i=0,height,-1 do gui.text(x-i, y-i, text, color, 0xE0) end
    end
end

local function is_main()
    return not debug.getinfo(3)
end

local loop = UpdateLoop()
loop:add(GAME)
loop:add(inputs)
local timed_text = timed_text_handler()
loop:add(timed_text)
flash.count = 0

function mapoverlay()
    loop:update()
    flash.count = (flash.count + 1) % 60
    overworld = memory.readword(GAME.mapaddr) == 2
    
    if keycheck("hexmap") then hexmap = not hexmap end
    if keycheck("pixmap") then pixmap = not pixmap end
    if keycheck("zoom_in") and zoomlevel < zoomrange then
        zoomlevel = zoomlevel+1
        timed_text:new(2,152, "zoom: "..zoomlevel, 90)
    end
    if keycheck("zoom_out") and zoomlevel > 0 then
        zoomlevel = zoomlevel-1
        timed_text:new(2,152, "zoom: "..zoomlevel, 90)
    end
    if keycheck("relheight") then
        heightmap.relative = not heightmap.relative
        timed_text:new(2,152, "relheight: "..tostring(heightmap.relative), 90)
    end
    if keycheck("hud") then
        hud = not hud
        timed_text:new(2,152, "hud: "..tostring(hud), 90)
    end

    local currentaddr = memory.readdword(GAME.tilepntr)
    local eventpntr = memory.readdword(GAME.eventpntr)
    if currentaddr >= 0x02000000 and eventpntr >= 0x02000000 then
        local colors = loadcolors()
        if flash.value and flash.count < 30 then colors[flash.value] = flash.color end
        local zoom = 2^zoomlevel
        local is_hovering, xdiff, ydiff
        local pc_data = memory.readdword(GAME.pc_data_pntr)
        local xaddr, yaddr = pc_data+0x8, pc_data+0x10
        local x_interval, y_interval, coord_mult
        if overworld then
            x_interval, y_interval = 0x4, 0x80
            coord_mult = 0x200000
        else
            x_interval, y_interval = 0x4, 0x200
            coord_mult = 0x100000
        end
        local xcurrent, ycurrent = memory.readdword(xaddr), memory.readdword(yaddr)
        local pc_height = get_height(currentaddr)

        if pixmap then
            local overlaysize = math.floor(pixmapsize/zoom)
            local xcenter, ycenter = center[1]-math.floor(zoom/2), center[2]-math.floor(zoom/2)
            for y=-overlaysize,overlaysize do
                for x=-overlaysize,overlaysize do
                    local tileaddr = currentaddr + x_interval*x + y*y_interval
                    local tilevalue = memory.readbyte(tileaddr + 2)
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
            is_hovering, xdiff, ydiff = hover_check(center, {12, 10}, hexmapsize)
            local deferred = {}
            for y=-hexmapsize,hexmapsize do
                for x=-hexmapsize,hexmapsize do
                    local tileaddr = currentaddr + y_interval*y + x_interval*x
                    local tilevalue = memory.readbyte(tileaddr + 2)
                    local xpos, ypos = center[1] + 12*x - 3, center[2] + 10*y - 4
                    local color = colors[tilevalue]
                    local height = 0
                    if heightmap.active and not overworld then
                        height = get_height(tileaddr)
                        if heightmap.relative then height = height - pc_height end
                        if not heightmap.show_neg then height = math.max(0, height) end
                        if height ~= 0 and bit.rshift(color, 8) == 0 and color ~= flash.color then
                            color = 0xFFFFFFE0
                        end
                    end
                    gui_text_3D(xpos, ypos, hex(tilevalue, 2), color, height)
                    if (x == 0 and y == 0) or (x == xdiff and y == ydiff) then
                        table.insert(deferred, {xpos, ypos, hex(tilevalue, 2), color, height})
                    end
                end
            end
            for _,args in pairs(deferred) do highlight(unpack(args)) end
        end

        if hud then show_tiledata(2, 2, "Tile:  ", {xcurrent, ycurrent, currentaddr}) end
        if is_hovering then
            local hoveraddr = currentaddr + x_interval*xdiff + y_interval*ydiff
            local hovervalue = memory.readbyte(hoveraddr+2)
            if hud then
                show_tiledata(2, 10, "Hover: ", {xdiff*coord_mult + xcurrent, ydiff*coord_mult + ycurrent, hoveraddr})
            end
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
end

if is_main() then
    print("Golden Sun 1 & 2 Map Overlay Script")
    print("Updated May 30, 2021")
    print("")
    print("shift + O\t\ttoggle hex overlay")
    print("shift + P\t\ttoggle pixel overlay")
    print("shift + ; or '\tzoom in/out on pixel map")
    print("shift + click\tteleport to position of cursor")
    print("ctrl + click\tmake selected value flash")
    print("ctrl + . or ,\tEdit value of tile hovered over")
    print("shift + L\t\ttoggle relative vs absolute height")
    print("shift + /\t\ttoggle heads up display")
    while true do
        mapoverlay()
        emu.frameadvance()
    end
end