
local M = {}


-- PINs:
-- 	[1] - reset
-- 	[2] - read
-- 	[3] - write
function M.ram(last_addr)-- >{
	local rawmem = {}
	local size = last_addr + 1
	
	local mod = {
		[1] = {"i4002", "Intel Corp."},
		[2] = "RAM Chip",
		[3] = size 	-- size in bytes
	}

	-- init rawmem
	local function reset()
		for i= 1, size do
			rawmem[i] = 0
		end
	end
	local function write(addr, uint8)
		rawmem[addr+1] = uint8
	end
	local function read(addr)
		return rawmem[addr+1]
	end

	reset()
	-- PINs: [1] , [2] , [3]
	return {reset, read, write}
end-- >}

-- PINs:
--   [1]   - unused/reserved
--   [2]   - readmem(addr)        - official, fast read, no bounds check
--   [14]  - writechunk(addr, chunk) - private, loads chunk/table/string, validates bytes
--   [15]  - writemem(addr, byte) - private, single byte write, validates range
--   [16]  - model info
--   3..14 unused (reserved/dummy)
function M.i4001(size)-- >{
	local rawmem = {}		-- memory array (byte addressed)
	local memsize = size or 4096	-- default: 256 bytes

	-- INIT: set all to 0
	for i = 1, memsize do rawmem[i] = 0 end

	local model = {
		[1] = {"i4001", "Intel Corp."},
		[2] = "ROM Chip",
		[3] = memsize -- size in bytes
	}

	-- [1] READMEM: fast read, no checks (official/CPU uses this)
	local function readmem(addr)
		return rawmem[addr+1]
	end

	-- [16] WRITEMEM: set a single byte, error if not byte or out of range
	local function writemem(addr, byte)
		if type(addr) ~= "number" or type(byte) ~= "number" then
			error("i4001.writemem: address and byte must be numbers")
		end
		if byte < 0 or byte > 0xFF or byte ~= math.floor(byte) then
			error(string.format("i4001.writemem: byte value %s out of range [0x00..0xFF]", tostring(byte)))
		end
		if addr < 0 or addr >= memsize or addr ~= math.floor(addr) then
			error(string.format("i4001.writemem: address %s out of range [0..%d]", tostring(addr), memsize-1))
		end
		rawmem[addr+1] = byte
	end

	-- [13] writebin: append multiple binary files to ROM (by filename)
	local function writebin(addr, ...)
		local args = {...}
		local idx = addr or 0
		for a = 1, #args do
			local filename = args[a]
			if type(filename) ~= "string" then
				error("i4001.writebin: argument " .. a .. " is not filename string")
			end
			local f = io.open(filename, "rb")
			if not f then
				error("i4001.writebin: cannot open file '" .. filename .. "'")
			end
			local data = f:read("*a")
			f:close()
			if not data then
				error("i4001.writebin: cannot read file '" .. filename .. "'")
			end
			for i = 1, #data do
				if idx >= memsize then
					error("i4001.writebin: ROM size exceeded")
				end
				rawmem[idx+1] = data:byte(i)
				idx = idx + 1
			end
		end
	end
	
	-- [15] WRITECHUNK: write chunk at start_addr, from table or hex string
	local function writechunk(start_addr, chunk)
		if type(start_addr) ~= "number" or start_addr < 0 or start_addr >= memsize then
			error(string.format("i4001.writechunk: start_addr %s out of range [0..%d]", tostring(start_addr), memsize-1))
		end

		if type(chunk) == "table" then
			for i=1, #chunk do
				local v = chunk[i]
				if type(v) ~= "number" or v < 0 or v > 0xFF or v ~= math.floor(v) then
					error(string.format(
						"i4001.writechunk: table[%d]=%s is not a byte [0x00..0xFF]", i, tostring(v)))
				end
				local idx = start_addr + i - 1
				if idx >= memsize then
					error("i4001.writechunk: chunk exceeds memory size")
				end
				rawmem[idx+1] = v
			end
		elseif type(chunk) == "string" then
			local idx = start_addr
			for byte in chunk:gmatch("[0-9A-Fa-f][0-9A-Fa-f]") do
				if idx >= memsize then
					error("i4001.writechunk: hex string exceeds memory size")
				end
				local num = tonumber(byte, 16)
				if not num then
					error("i4001.writechunk: invalid hex pair: " .. byte)
				end
				rawmem[idx+1] = num
				idx = idx + 1
			end
			-- check for any non-hex, non-space char (strict)
			local bad = chunk:gsub("[%x%s]", "")
			if #bad > 0 then
				error("i4001.writechunk: non-hex character(s) found: " .. bad)
			end
		else
			error("i4001.writechunk: chunk must be table or hex string")
		end
	end

	local NOP = function() end
	local pin = {}
	for i=1,16 do
		pin[i] = NOP
	end

	-- pin 1 (reset) not allowed
	pin[2]  = readmem	-- official, public read
	-- pins 2 - 13 unused
	pin[13] = writebin	-- private: chunk loader
	pin[14] = writechunk	-- private: chunk loader
	pin[15] = writemem	-- private: single byte
	pin[16] = model

	return pin
end-- >}

function M.i4002()-- >{
	-- 16 Data register 4bit
	-- 4 Chars I/O 4bit
	-- 4 Status 4bit
	local reg = {}
	local char = {}
	local stat = {}
	local io = 0

	local model = {
		[1] = {"i4002", "Intel Corp."},
		[2] = "RAM Chip",
		[3] = 8 -- size in bytes (registers only)
	}

	local function reset()
		for i = 1, 16 do
			reg[i] = 0
			char[i] = 0
			stat[i] = 0
		end
		io = 0
	end

	-- REGISTERS
	local function regread(num)
		return reg[num+1]
	end
	local function regwrite(num, uint4)
		reg[num+1] = uint4
	end

	-- STATUSES
	local function statread(num)
		return stat[num+1]
	end
	local function statwrite(num, uint4)
		stat[num+1] = uint4
	end

	-- CHARACTER
	local function charread(num)
		return char[num+1]
	end
	local function charwrite(num, uint4)
		char[num+1] = uint4
	end

	-- IO
	local function ioread()
		return io
	end
	
	local function iowrite(uint4)
		io = uint4
	end

	reset()

	local NOP = function() end
	local pin = {}
	for i=1,16 do
		pin[i] = NOP
	end

	pin[1] = reset
	pin[2] = regread ; 	pin[3] = regwrite
	pin[4] = statread ; pin[5] = statwrite
	pin[6] = charread ; pin[7] = charwrite
	pin[8] = ioread ; 	pin[9] = iowrite
	-- pins 10->15 unused
	pin[16] = model

	return pin
end-- >}

function M.i4002_array()-- >{
	local i4002_chip = {}
	for i = 1, 16 do
		i4002_chip[i] = M.i4002()
	end

	local model = {
		[1] = {"16 x i4002 Array", "Intel Corp."},
		[2] = "RAM Board",
		[3] = 16*8 -- size in bytes (registers only)
	}

	local function NOP() end
	local pin = {}
	for i = 1, 16 do
		pin[i] = NOP
	end

	local function reset()
		for i = 1, 16 do
			i4002_chip[i][1]()
		end
		-- reassing all read/write to chip 1
		for i = 2, 9 do
			pin[i] = i4002_chip[1][i]
		end
	end

	local function designate(chip)
		-- assign all read/write to <chip>
		for i = 2, 9 do
			pin[i] = i4002_chip[chip][i]
		end
	end

	reset()

	pin[1] = reset
	-- pins 2->9 used for read/write to designated chip
	pin[10] = designate
	-- pins 11->15 unused
	pin[16] = model

	return pin
end-- >}

-- PINs:
--   [1] - reset (clears all bits)
--   [2] - shift (inserts bit into input, clocks all bits serially)
--   [3] - set_serial(bit) (optional: direct set, for test/debug/concat)
--   [4-13] - parallel output lines (Q1..Q10: lowest Q1 = last in, highest Q10 = first in)
--   [14] - connect_next(i4003_chip) (optional: chaining with next chip)
--   [15-16] - unused
function M.i4003()-- >{
	local sr = {0,0,0,0,0,0,0,0,0,0}	-- 10-bit shift register, sr[1]=Q10 (first in), sr[10]=Q1 (last in)
	local serial_in = 0	-- input bit for next clock
	local next_chip = nil

	local model = {
		[1] = {"i4003", "Intel Corp."},
		[2] = "10bit Shift Register",
		[3] = 0 -- size in bytes (registers only)
	}

	-- [1] reset: clear all bits
	local function reset()
		for i=1,10 do sr[i]=0 end
		serial_in = 0
		if next_chip and next_chip[1] then next_chip[1]() end
	end

	-- [2] shift: insert 'serial_in', push right, Q1=bit out, Q10 <= serial_in
	local function clock()
		local bit_out = sr[10]	-- last bit shifts out (used for chaining)
		for i=10,2,-1 do
			sr[i] = sr[i-1]
		end
		sr[1] = serial_in
		if next_chip and next_chip[3] then next_chip[3](bit_out) end
	end

	-- [3] set input: serial bit (accepts only 0 or 1, no check for speed)
	local function set_serial(bit)
		serial_in = bit
	end

	-- [4-13]: parallel out, immediate reflect, 1=Q10..10=Q1
	local pin = {}
	for i=1,16 do pin[i]=function() end end
	pin[1] = reset
	pin[2] = clock
	pin[3] = set_serial
	for i=1,10 do
		-- pin[4] = Q10 (MSB, first-in), ..., pin[13] = Q1 (LSB, last-in)
		pin[i+3] = function() return sr[i] end
	end

	-- [14] connect next i4003 (for chaining)
	pin[14] = function(chip)
		next_chip = chip
	end

	-- pins 15 unused
	pin[16] = model

	reset()
	return pin
end-- >}

return M
-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
