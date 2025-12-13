-- Busicom 141-PF Keyboard Matrix Simulation
local keyboard = {}

-- 8x4 matrix + switches
local key_matrix = {}
for col = 0, 7 do
	key_matrix[col] = {false, false, false, false} -- 4 rows per column
end

local dp_switch = 0  -- decimal point switch (0,1,2,3,4,5,6,8)
local round_switch = 0  -- rounding switch (0,1,8)

-- Key mapping from BusicomROM.txt
local key_map = {
	-- col 0: CM, RM, M-, M+
	[0] = {"CM", "RM", "M-", "M+"},
	-- col 1: SQRT, %, M=-, M=+  
	[1] = {"SQRT", "%", "M=-", "M=+"},
	-- col 2: diamond, /, *, =
	[2] = {"◊", "/", "*", "="},
	-- col 3: -, +, diamond2, 000
	[3] = {"-", "+", "◊2", "000"},
	-- col 4: 9, 6, 3, .
	[4] = {"9", "6", "3", "."},
	-- col 5: 8, 5, 2, 00
	[5] = {"8", "5", "2", "00"},
	-- col 6: 7, 4, 1, 0
	[6] = {"7", "4", "1", "0"},
	-- col 7: Sign, EX, CE, C
	[7] = {"±", "EX", "CE", "C"}
}

local key_convert = {
	["000"] = "000",
	["00"] = "00",
	["0"] = "0",
	["1"] = "1",
	["2"] = "2",
	["3"] = "3",
	["4"] = "4",
	["5"] = "5",
	["6"] = "6",
	["7"] = "7",
	["8"] = "8",
	["9"] = "9",
	["+"] = "+",
	["-"] = "-",
	["*"] = "*",
	["/"] = "/",
	["%"] = "%",
	["="] = "=",
	["."] = ".",
	["M+"] = "M+",
	["M-"] = "M-",
	["M=-"] = "M=-",
	["M=+"] = "M=+",
	["CM"] = "CM",
	["RM"] = "RM",
	["R"] = "RM",
	["EX"] = "EX",
	["CE"] = "CE",
	["C"] = "C",
	["D"] = "◊",
	["D2"] = "◊2",
	["S"] = "±",
	["V"] = "SQRT",
}

-- Current shifter state (10 bits, bit 0 = current column being scanned)
local shifter_state = 0x3FF  -- all high initially

-- Press/Release functions
function keyboard.press_key(key_name)
	for col = 0, 7 do
		for row = 1, 4 do
			if key_map[col][row] == key_convert[key_name] then
				key_matrix[col][row] = true
				return true
			end
		end
	end
return false -- key not found
end

function keyboard.release_key(key_name)
	for col = 0, 7 do
		for row = 1, 4 do
			if key_map[col][row] == key_convert[key_name] then
				key_matrix[col][row] = false
				return true
			end
		end
	end
	return false
end

-- Switch controls
function keyboard.set_dp_switch(value)
	if value == 0 or value == 1 or value == 2 or value == 3 or 
		value == 4 or value == 5 or value == 6 or value == 8 then
		dp_switch = value
	end
end

function keyboard.set_round_switch(value)
	if value == 0 or value == 1 or value == 8 then
		round_switch = value
	end
end

-- Read current row state for active column
function keyboard.read_rows()
	local row_data = 0

	-- Check which column is currently selected (low bit in shifter)
	for col = 0, 7 do
		if (shifter_state & (1 << col)) == 0 then  -- active low
		-- This column is selected, read its rows
		for row = 0, 3 do
			if key_matrix[col][row+1] then
				row_data = row_data | (1 << row)
			end
		end
		break
		end
	end

	-- Add switch states (columns 8-9)
	if (shifter_state & (1 << 8)) == 0 then  -- dp switch column
		-- Decode dp_switch to ROM1 bits
		if dp_switch == 1 or dp_switch == 3 or dp_switch == 5 then
			row_data = row_data | 1  -- bit 0
		end
		if dp_switch == 2 or dp_switch == 3 or dp_switch == 6 then  
			row_data = row_data | 2  -- bit 1
		end
		if dp_switch == 4 or dp_switch == 5 or dp_switch == 6 then
			row_data = row_data | 4  -- bit 2  
		end
		if dp_switch == 8 then
			row_data = row_data | 8  -- bit 3
		end
	end

	if (shifter_state & (1 << 9)) == 0 then  -- round switch column
		if round_switch == 1 then
			row_data = row_data | 1  -- bit 0
		end
		if round_switch == 8 then
			row_data = row_data | 8  -- bit 3
		end
	end

	return row_data
end

-- Update shifter state (called by CPU via WRR)
function keyboard.update_shifter(data_bit, clock_pulse)
	if clock_pulse then
		-- Shift register: shift left, insert data_bit at LSB
		shifter_state = ((shifter_state << 1) | data_bit) & 0x3FF
	end
end

return keyboard
