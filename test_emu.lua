
local cpu = require("cpu")
local mem = require("mem")

local rom = mem.i4001(0xFFF)
local ram = mem.i4002_array()
local kbd_shiftr = mem.i4003()
local prn_shiftr1 = mem.i4003()
local prn_shiftr2 = mem.i4003()

prn_shiftr1[14](prn_shiftr2)

-- Carica tutte le ROM nell'ordine corretto
rom[13](0x000, "./busicomROM/busicom.l01")
rom[13](0x100, "./busicomROM/busicom.l02") 
rom[13](0x200, "./busicomROM/busicom.l05")
rom[13](0x300, "./busicomROM/busicom.l07")
rom[13](0x400, "./busicomROM/busicom.l11")

local i4004 = cpu.i4004_i1(rom, ram, kbd_shiftr, prn_shiftr1)

return i4004