
local M = {}

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
		pattern = pattern .. (prn_shiftr1[i]() == 1 and "1" or "0")
	end
	for i = 4, 13 do  -- second shifter  
		pattern = pattern .. (prn_shiftr2[i]() == 1 and "1" or "0")
	end
	if pattern ~= "00000000000000000000" then
		print("PRINTER: " .. pattern)
	end
end

return M
