local M = {}

local cpu = require("cpu")
local mem = require("mem")

M.rom = mem.i4001(0xFFF)
M.ram = mem.i4002_array()
M.kbd_shiftr = mem.i4003()
M.prn_shiftr1 = mem.i4003()
M.prn_shiftr2 = mem.i4003()

M.prn_shiftr1[14](prn_shiftr2)

-- Carica tutte le ROM nell'ordine corretto
M.rom[13](0x000, "./rom/busicom.l01")
M.rom[13](0x100, "./rom/busicom.l02") 
M.rom[13](0x200, "./rom/busicom.l05")
M.rom[13](0x300, "./rom/busicom.l07")
M.rom[13](0x400, "./rom/busicom.l11")

-- CPU
M.bc141PF = cpu.i4004_i1(M.rom, M.ram, M.kbd_shiftr, M.prn_shiftr1)

M.ioread = M.ram[8] -- wire RAM ioread

-- KEYBOARD
M.kbd = require("keyboard")


-- MONITOR status lights (RAM1 port)
local last_status = 0
function M.lgt()
    -- Dovremmo intercettare ram[7]() calls
    local status = M.ioread() -- ioread from RAM1  
    if status ~= last_status then
        local memory_lamp = (status & 1) ~= 0
        local overflow_lamp = (status & 2) ~= 0  
        local minus_lamp = (status & 4) ~= 0
        print(string.format("LIGHTS: MEM=%s OVF=%s MINUS=%s", 
              memory_lamp and "ON" or "OFF",
              overflow_lamp and "ON" or "OFF", 
              minus_lamp and "ON" or "OFF"))
        last_status = status
    end
end

-- Monitor printer output
function M.prn()
    -- Leggere i shift registers per vedere cosa stamperebbe
    local pattern = ""
    for i = 4, 13 do  -- Q10..Q1
        pattern = pattern .. (M.prn_shiftr1[i]() == 1 and "1" or "0")
    end
    for i = 4, 13 do  -- second shifter  
        pattern = pattern .. (M.prn_shiftr2[i]() == 1 and "1" or "0")
    end
    if pattern ~= "00000000000000000000" then
        print("PRINTER: " .. pattern)
    end
end

return M
