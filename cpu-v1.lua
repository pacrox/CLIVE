
local M = {}


local function cpu_proto()-- >{
	-- reg = (registers)
	-- 	[1] register/accumulator
	-- 	[2] register/accumulator
	-- 	...
	local reg = {}  -- registers
	-- stk = (stack)
	-- 	[1] level 1
	-- 	[2] level 2
	-- 	...
	local stk = {} -- stacks

	-- mod = (model)
	-- 	[1] model name
	-- 	[2] type
	-- 	[3] frequency
	-- 	[4] max registers
	-- 	[5] max stack levels
	local mod = {}

	-- st =	(status)
	-- 	[1] instruction address (mem arr) PC
	-- 	[2] stack level
	-- 	[3] cycle counter
	local st = {}
	
	-- opset = (op-codes set)
	-- 	[0x00+1] function
	-- 	[0x01+1] function
	-- 	...
	local opset = {}

	local mbus
	local instr
	local halt

	local stcycl

	local function step()
		-- FETCH
		-- load byte from mem-bus
		opr = mbus[2](st[1])		-- st[1] = instruction address
		st[1] = st[1] + 1		-- increase PC
		-- Opcode is 4bit
		opa = opr & 0x0F		-- extract arguments from 4bit nibble
		opr = (opr >> 4) & 0x0F		-- extract opcode from 4bit nibble
		-- Opcode is 8bit
						-- nothing to be done
		-- DECODE and EXEC
		stcycl = 1
		opset[opr+1]()			-- DECODE, FETCH (if needed) & EXECUTE
						-- it may increase stcycl
		return stcycl
	end

	-- pins = (cpu functions / readouts)
	-- 	[1] = step	(func)
	-- 	[2] = reset	(func)
	-- 	[3] = interrupt (func)
	-- 	[4] = wait	(func)
	-- 	[5] = bus req	(func)
	-- 	[6] = halt	(flag)
	-- 	...
	local pins = {
		[1] = step
	}

	return pins
end-- >}



function M.i4004_i1(rom, ram)
	-- pin = (connection pins)
	-- 	16 pins allocated
	local pin = {}		-- control pins
		for i = 1, 16 do pin[i]=0 end
	local opset = {}	-- opcode set

	-- reg = (registers)	-->{
	-- 	[1]  A		- 4bit accumulator
	-- 	[2]  R0		- 4bit register
	-- 	[3]  R1		
	-- 	...
	-- 	[17] R15
	-- 	[18] IO_LATCH	- 8bit internal register
	local reg = {} -- >}
	-- flag = (flags)	-->{
	-- 	[1]  carry
	-- 	[2]  external pin
	-- 	...
	local flag = {} -- >}
	-- st =	(status)	-->{
	-- 	[1]  PC (program counter) - 12bit
	-- 	[2]  stack level
	-- 	[15] last fault reason
	-- 	[16] cycle counter
	local st = {} -- >}

	-- DEBUG INFOS
	pin[16] = function()	-- DEBUG INFO	-->{
		return reg, flag, st
	end-- >}

	-- BUSSES WIRING
	local rom = rom
	pin[15] = function(addr_space)	-- WIRE ROM	-->{
		rom = addr_space
	end-- >}

	local ram = ram
	pin[14] = function(addr_space)  -- WIRE RAM	-->{
		ram = addr_space
	end-- >}

	-- NOP function
	local NOP = function() end

	-- STEPPER
	local step_cycl				-- counts the num of steps
	local STEP = function()	-- STEP		-->{
		opr = rom[2](st[1])		-- fetch instruction (st[1] = PC)
		st[1] = st[1] + 1		-- increase PC
		step_cycl = 1			-- increase steps counter
		opset[opr+1]()			-- decode opcode and exec

		st[16] = st[16] + step_cycl	-- increase total cycles cnt
		return step_cycl
	end					-->}

	-- RESET
	pin[1] = function ()	-- RESET	-->{
		-- init more than needed
		for i = 1, 24 do reg[i] = 0 end
		for i = 1, 8 do flag[i] = 0 end
		for i = 1, 16 do st[i] = 0 end
		-- init the instruction stack
		st[2] = {}
		-- reset pin 2 (step)
		pin[2] = STEP			-- normal execution
		pin[10] = 0			-- mark NOT HALTED
		pin[11] = 0			-- mark NOT FAULT
	end-- >}

	FAULT = function(reason)-- >{
		pin[2] = NOP			-- halt CPU
		pin[10] = 1			-- mark HALTED
		pin[11] = 1			-- mark FAULT
		st[15] = reason or "UNKNOWN"	-- store fault reason
	end-- >}

	pin[10] = 0		-- HALTED
	pin[11] = 0		-- FAULT

	-- init opset setting all to NOP
	for i = 1, 0xFF+1 do opset[i] = NOP end

	local taddr	-- tempvar for address
	local tbyte	-- tempvar for byte
	local tnibble	-- tempvar for nibble

	-- DECODER/OPCODES
	opset[0x00+1] = NOP			-- NOP

	-- 0x0?: JCN (jump if condition)	-->{
	-- 	JCN cond, addr8
	-- 	
	-- 	bit0 = Z (A == 0, test zero)
	-- 	bit1 = C (Carry)
	-- 	bit2 = T (External Pin Test)
	-- 	bit3 = I (invert)
	-- 
	-- Note: PC is 12 bit, JCN changes bit 0:7 (low)
	--
	opset[0x01+1] = function() 		-- JCN [Z] 0001
		step_cycl = step_cycl + 1
		if reg[1] == 0 then -- A is zero
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x02+1] = function() 		-- JCN [C] 0010
		step_cycl = step_cycl + 1
		if flag[1] then -- flag CARRY
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x03+1] = function() 		-- JCN [ZC] 0011
		step_cycl = step_cycl + 1
		if reg[1] == 0 or flag[1] then -- A is zero or flag CARRY
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x04+1] = function() 		-- JCN [T] 0100
		step_cycl = step_cycl + 1
		if flag[2] then -- flag ext-pin 
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x05+1] = function() 		-- JCN [TZ] 0101
		step_cycl = step_cycl + 1
		if reg[1] == 0 or flag[2] then -- A is zero or flag ext-pin 
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x06+1] = function() 		-- JCN [TC] 0110
		step_cycl = step_cycl + 1
		if flag[1] or flag[2] then -- flag carry or flag ext-pin 
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x07+1] = function() 		-- JCN [TCZ] 0111
		step_cycl = step_cycl + 1
		if reg[1] == 0 or flag[1] or flag[2] then 
			st[1] = (st[1] & 0xF00) | rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x08+1] = function() 		-- JCN [] 1000 (always jump)
		step_cycl = step_cycl + 1
		st[1] = (st[1] & 0xF00) | 
			rom[2](st[1])		-- fetch new byte into PC
	end
	opset[0x09+1] = function() 		-- JCN [IZ] 1001
		step_cycl = step_cycl + 1
		if reg[1] ~= 0 then -- A is zero
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x0A+1] = function() 		-- JCN [IC] 1010
		step_cycl = step_cycl + 1
		if not(flag[1]) then -- flag CARRY
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x0B+1] = function() 		-- JCN [IZC] 1011
		step_cycl = step_cycl + 1
		if not(reg[1] == 0 or flag[1]) then -- A is zero or flag CARRY
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x0C+1] = function() 		-- JCN [IT] 1100
		step_cycl = step_cycl + 1
		if not(flag[2]) then -- flag ext-pin 
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x0D+1] = function() 		-- JCN [ITZ] 1101
		step_cycl = step_cycl + 1
		if not(reg[1] == 0 or flag[2]) then -- A is zero or flag ext-pin 
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x0E+1] = function() 		-- JCN [ITC] 1110
		step_cycl = step_cycl + 1
		if not(flag[1] or flag[2]) then -- flag carry or flag ext-pin 
			st[1] = (st[1] & 0xF00) | 
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x0F+1] = function() 		-- JCN [ITCZ] 1111
		step_cycl = step_cycl + 1
		if not(reg[1] == 0 or flag[1] or flag[2]) then 
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- fetch new byte into PC
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end-- >}

	-- 0x1?: JCN (jump if condition)	-->{
	-- 	0x10 alway pass
	-- 	0x11-0x1F = copy of save opcodes from 0x01 to 0x0F
	opset[0x10+1] = function() 		-- JCN [] 0000 (always pass)
		step_cycl = step_cycl + 1
		st[1] = st[1] + 1	-- increment PC
	end
	for i = 0x1, 0xF do	-- duplicates opcodes
		opset[0x10+i+1] = opset[0x00+i+1]
	end-- >}

	-- 0x2?: FIM/SRC (load registers, source ram) -->{
	--	if ? is even = FIM
	--	if ? is odd = SRC
	-- FIM  0-7
	opset[0x20+1] = function()		-- FIM 0
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[2] = (taddr >> 4) & 0x0F	-- R0 4bit (hi)
		reg[3] = taddr & 0x0F		-- R1 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x22+1] = function()		-- FIM 1
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[4] = (taddr >> 4) & 0x0F	-- R2 4bit (hi)
		reg[5] = taddr & 0x0F		-- R3 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x24+1] = function()		-- FIM 2
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[6] = (taddr >> 4) & 0x0F	-- R4 4bit (hi)
		reg[7] = taddr & 0x0F		-- R5 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x26+1] = function()		-- FIM 3
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[8] = (taddr >> 4) & 0x0F	-- R6 4bit (hi)
		reg[9] = taddr & 0x0F		-- R7 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x28+1] = function()		-- FIM 4
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[10] = (taddr >> 4) & 0x0F	-- R8 4bit (hi)
		reg[11] = taddr & 0x0F		-- R9 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x2A+1] = function()		-- FIM 5
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[12] = (taddr >> 4) & 0x0F	-- R10 4bit (hi)
		reg[13] = taddr & 0x0F		-- R11 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x2C+1] = function()		-- FIM 6
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[14] = (taddr >> 4) & 0x0F	-- R12 4bit (hi)
		reg[15] = taddr & 0x0F		-- R13 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x2E+1] = function()		-- FIM 7
		step_cycl = step_cycl + 1
		taddr = rom[2](st[1])		-- fetch next byte
		reg[16] = (taddr >> 4) & 0x0F	-- R14 4bit (hi)
		reg[17] = taddr & 0x0F		-- R15 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	-- SRC 0-7
	opset[0x21+1] = function()		-- SRC 0
		reg[18] = (reg[2] << 4) | 
			reg[3] 			-- R0 (hi), R1 (low)
	end
	opset[0x23+1] = function()		-- SRC 1
		reg[18] = (reg[4] << 4) | 
			reg[5] 			-- R2 (hi), R3 (low)
	end
	opset[0x25+1] = function()		-- SRC 2
		reg[18] = (reg[6] << 4) | 
			reg[7] 			-- R4 (hi), R5 (low)
	end
	opset[0x27+1] = function()		-- SRC 3
		reg[18] = (reg[8] << 4) |
			reg[9] 			-- R6 (hi), R7 (low)
	end
	opset[0x29+1] = function()		-- SRC 4
		reg[18] = (reg[10] << 4) | 
			reg[11] 		-- R8 (hi), R9 (low)
	end
	opset[0x2B+1] = function()		-- SRC 5
		reg[18] = (reg[12] << 4) | 
			reg[13] 		-- R10 (hi), R11 (low)
	end
	opset[0x2D+1] = function()		-- SRC 6
		reg[18] = (reg[14] << 4) | 
			reg[15] 		-- R12 (hi), R13 (low)
	end
	opset[0x2F+1] = function()		-- SRC 7
		reg[18] = (reg[16] << 4) | 
			reg[17] 		-- R14 (hi), R15 (low)
	end -->}

	-- 0x3?: FIN/JIN (load indirect, jump indirect)	-->{
	--
	-- FIN rp
	opset[0x30+1] = function()		-- FIN 0
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[2] = (tbyte >> 4) & 0x0F	-- R0 4bit (hi)
		reg[3] = tbyte & 0x0F		-- R1 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x32+1] = function()		-- FIN 1
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[4] = (tbyte >> 4) & 0x0F	-- R2 4bit (hi)
		reg[5] = tbyte & 0x0F		-- R3 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x34+1] = function()		-- FIN 2
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[6] = (tbyte >> 4) & 0x0F	-- R4 4bit (hi)
		reg[7] = tbyte & 0x0F		-- R5 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x36+1] = function()		-- FIN 3
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[8] = (tbyte >> 4) & 0x0F	-- R6 4bit (hi)
		reg[9] = tbyte & 0x0F		-- R7 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x38+1] = function()		-- FIN 4
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[10] = (tbyte >> 4) & 0x0F	-- R8 4bit (hi)
		reg[11] = tbyte & 0x0F		-- R9 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x3A+1] = function()		-- FIN 5
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[12] = (tbyte >> 4) & 0x0F	-- R10 4bit (hi)
		reg[13] = tbyte & 0x0F		-- R11 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x3C+1] = function()		-- FIN 6
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[14] = (tbyte >> 4) & 0x0F	-- R12 4bit (hi)
		reg[15] = tbyte & 0x0F		-- R13 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	opset[0x3E+1] = function()		-- FIN 7
		step_cycl = step_cycl + 1
		tbyte = rom[2](reg[18])	-- fetch IO_LATCH addr8
		reg[16] = (tbyte >> 4) & 0x0F	-- R14 4bit (hi)
		reg[17] = tbyte & 0x0F		-- R15 4bit (low)
		st[1] = st[1] + 1 		-- increment PC
	end
	-- JIN rp
	opset[0x31+1] = function()		-- JIN 0
		taddr = (reg[2] << 4) | reg[3] 	-- R0/R1 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x33+1] = function()		-- JIN 1
		taddr = (reg[4] << 4) | reg[5] 	-- R2/R3 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x35+1] = function()		-- JIN 2
		taddr = (reg[6] << 4) | reg[7] 	-- R4/R5 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x37+1] = function()		-- JIN 3
		taddr = (reg[8] << 4) | reg[9] 	-- R6/R7 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x39+1] = function()		-- JIN 4
		taddr = (reg[10] << 4) | reg[11]-- R8/R9 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x3B+1] = function()		-- JIN 5
		taddr = (reg[12] << 4) | reg[13]-- R10/R11 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x3D+1] = function()		-- JIN 6
		taddr = (reg[14] << 4) | reg[15]-- R12/R13 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end
	opset[0x3F+1] = function()		-- JIN 7
		taddr = (reg[16] << 4) | reg[17]-- R14/R15 addr8
		st[1] = (st[1] & 0xF00) | taddr	-- copy lower 8bits to PC
	end-- >}

	-- 0x4?: JUN (Jump unconditional, addr12)	-->{
	--
	-- JUN addr12 (4bit opcode / 4bit hi addr + 8bit low addr)
	opset[0x40+1] = function()		-- JUN 0
		step_cycl = step_cycl + 1
		st[1] = 0x000 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x41+1] = function()		-- JUN 1
		step_cycl = step_cycl + 1
		st[1] = 0x100 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x42+1] = function()		-- JUN 2
		step_cycl = step_cycl + 1
		st[1] = 0x200 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x43+1] = function()		-- JUN 3
		step_cycl = step_cycl + 1
		st[1] = 0x300 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x44+1] = function()		-- JUN 4
		step_cycl = step_cycl + 1
		st[1] = 0x400 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x45+1] = function()		-- JUN 5
		step_cycl = step_cycl + 1
		st[1] = 0x500 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x46+1] = function()		-- JUN 6
		step_cycl = step_cycl + 1
		st[1] = 0x600 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x47+1] = function()		-- JUN 7
		step_cycl = step_cycl + 1
		st[1] = 0x700 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x48+1] = function()		-- JUN 8
		step_cycl = step_cycl + 1
		st[1] = 0x800 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x49+1] = function()		-- JUN 9
		step_cycl = step_cycl + 1
		st[1] = 0x900 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x4A+1] = function()		-- JUN A
		step_cycl = step_cycl + 1
		st[1] = 0xA00 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x4B+1] = function()		-- JUN B
		step_cycl = step_cycl + 1
		st[1] = 0xB00 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x4C+1] = function()		-- JUN C
		step_cycl = step_cycl + 1
		st[1] = 0xC00 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x4D+1] = function()		-- JUN D
		step_cycl = step_cycl + 1
		st[1] = 0xD00 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x4E+1] = function()		-- JUN E
		step_cycl = step_cycl + 1
		st[1] = 0xE00 | rom[2](st[1])	-- fetch next byte & set PC
	end
	opset[0x4F+1] = function()		-- JUN F
		step_cycl = step_cycl + 1
		st[1] = 0xF00 | rom[2](st[1])	-- fetch next byte & set PC
	end-- >}

	-- 0x5?: JMS (Jump Subroutine, addr12)	-->{
	--	handle stack to store return addr12
	--	cast UB (Undefined Behaviour) on stack overflow.
	local f_over = "STACK OVERFLOW"
	opset[0x50+1] = function()		-- JMS 0
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x000 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x51+1] = function()		-- JMS 1
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x100 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x52+1] = function()		-- JMS 2
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x200 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x53+1] = function()		-- JMS 3
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x300 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x54+1] = function()		-- JMS 4
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x400 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x55+1] = function()		-- JMS 5
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x500 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x56+1] = function()		-- JMS 6
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x600 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x57+1] = function()		-- JMS 7
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x700 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x58+1] = function()		-- JMS 8
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x800 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x59+1] = function()		-- JMS 9
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0x900 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x5A+1] = function()		-- JMS A
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0xA00 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x5B+1] = function()		-- JMS B
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0xB00 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x5C+1] = function()		-- JMS C
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0xC00 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x5D+1] = function()		-- JMS D
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0xD00 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x5E+1] = function()		-- JMS E
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0xE00 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end
	opset[0x5F+1] = function()		-- JMS F
		step_cycl = step_cycl + 1
		st[2][#st[2]+1] = st[1]+1	-- push PC_next to stack
		st[1] = 0xF00 | rom[2](st[1])	-- fetch next byte & set PC
		if #st[2] > 3 then 
			FAULT(f_over) end	-- UB causes cpu fault
	end-- >}

	-- 0x6?: INC (Increase register)	-->{
	--
	-- INC r (<4bit opcode> <4bit register>)
	opset[0x60+1] = function()		-- INC 0
		reg[2] = (reg[2] + 1) & 0x0F	-- increase R0 (check 4bit wrap)
	end
	opset[0x61+1] = function()		-- INC 1
		reg[3] = (reg[3] + 1) & 0x0F	-- increase R1 (check 4bit wrap)
	end
	opset[0x62+1] = function()		-- INC 2
		reg[4] = (reg[4] + 1) & 0x0F	-- increase R2 (check 4bit wrap)
	end
	opset[0x63+1] = function()		-- INC 3
		reg[5] = (reg[5] + 1) & 0x0F	-- increase R3 (check 4bit wrap)
	end
	opset[0x64+1] = function()		-- INC 4
		reg[6] = (reg[6] + 1) & 0x0F	-- increase R4 (check 4bit wrap)
	end
	opset[0x65+1] = function()		-- INC 5
		reg[7] = (reg[7] + 1) & 0x0F	-- increase R5 (check 4bit wrap)
	end
	opset[0x66+1] = function()		-- INC 6
		reg[8] = (reg[8] + 1) & 0x0F	-- increase R6 (check 4bit wrap)
	end
	opset[0x67+1] = function()		-- INC 7
		reg[9] = (reg[9] + 1) & 0x0F	-- increase R7 (check 4bit wrap)
	end
	opset[0x68+1] = function()		-- INC 8
		reg[10] = (reg[10] + 1) & 0x0F	-- increase R8 (check 4bit wrap)
	end
	opset[0x69+1] = function()		-- INC 9
		reg[11] = (reg[11] + 1) & 0x0F	-- increase R9 (check 4bit wrap)
	end
	opset[0x6A+1] = function()		-- INC A
		reg[12] = (reg[12] + 1) & 0x0F	-- increase R10 (check 4bit wrap)
	end
	opset[0x6B+1] = function()		-- INC B
		reg[13] = (reg[13] + 1) & 0x0F	-- increase R11 (check 4bit wrap)
	end
	opset[0x6C+1] = function()		-- INC C
		reg[14] = (reg[14] + 1) & 0x0F	-- increase R12 (check 4bit wrap)
	end
	opset[0x6D+1] = function()		-- INC D
		reg[15] = (reg[15] + 1) & 0x0F	-- increase R13 (check 4bit wrap)
	end
	opset[0x6E+1] = function()		-- INC E
		reg[16] = (reg[16] + 1) & 0x0F	-- increase R14 (check 4bit wrap)
	end
	opset[0x6F+1] = function()		-- INC F
		reg[17] = (reg[17] + 1) & 0x0F	-- increase R15 (check 4bit wrap)
	end-- >}

	-- 0x7?: ISZ (Increase and jump if not zero)	-->{
	--
	opset[0x70+1] = function()		-- ISZ 0
		step_cycl = step_cycl + 1
		reg[2] = (reg[2] + 1) & 0x0F	-- increase R0 (check 4bit wrap)
		if reg[2] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x71+1] = function()		-- ISZ 1
		step_cycl = step_cycl + 1
		reg[3] = (reg[3] + 1) & 0x0F	-- increase R1 (check 4bit wrap)
		if reg[3] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x72+1] = function()		-- ISZ 2
		step_cycl = step_cycl + 1
		reg[4] = (reg[4] + 1) & 0x0F	-- increase R2 (check 4bit wrap)
		if reg[4] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x73+1] = function()		-- ISZ 3
		step_cycl = step_cycl + 1
		reg[5] = (reg[5] + 1) & 0x0F	-- increase R3 (check 4bit wrap)
		if reg[5] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x74+1] = function()		-- ISZ 4
		step_cycl = step_cycl + 1
		reg[6] = (reg[6] + 1) & 0x0F	-- increase R4 (check 4bit wrap)
		if reg[6] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x75+1] = function()		-- ISZ 5
		step_cycl = step_cycl + 1
		reg[7] = (reg[7] + 1) & 0x0F	-- increase R5 (check 4bit wrap)
		if reg[7] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x76+1] = function()		-- ISZ 6
		step_cycl = step_cycl + 1
		reg[8] = (reg[8] + 1) & 0x0F	-- increase R6 (check 4bit wrap)
		if reg[8] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x77+1] = function()		-- ISZ 7
		step_cycl = step_cycl + 1
		reg[9] = (reg[9] + 1) & 0x0F	-- increase R7 (check 4bit wrap)
		if reg[9] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x78+1] = function()		-- ISZ 8
		step_cycl = step_cycl + 1
		reg[10] = (reg[10] + 1) & 0x0F	-- increase R8 (check 4bit wrap)
		if reg[10] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x79+1] = function()		-- ISZ 9
		step_cycl = step_cycl + 1
		reg[11] = (reg[11] + 1) & 0x0F	-- increase R9 (check 4bit wrap)
		if reg[11] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x7A+1] = function()		-- ISZ 10
		step_cycl = step_cycl + 1
		reg[12] = (reg[12] + 1) & 0x0F	-- increase R10 (check 4bit wrap)
		if reg[12] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x7B+1] = function()		-- ISZ 11
		step_cycl = step_cycl + 1
		reg[13] = (reg[13] + 1) & 0x0F	-- increase R11 (check 4bit wrap)
		if reg[13] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x7C+1] = function()		-- ISZ 12
		step_cycl = step_cycl + 1
		reg[14] = (reg[14] + 1) & 0x0F	-- increase R12 (check 4bit wrap)
		if reg[14] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x7D+1] = function()		-- ISZ 13
		step_cycl = step_cycl + 1
		reg[15] = (reg[15] + 1) & 0x0F	-- increase R13 (check 4bit wrap)
		if reg[15] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x7E+1] = function()		-- ISZ 14
		step_cycl = step_cycl + 1
		reg[16] = (reg[16] + 1) & 0x0F	-- increase R14 (check 4bit wrap)
		if reg[16] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end
	opset[0x7F+1] = function()		-- ISZ 15
		step_cycl = step_cycl + 1
		reg[17] = (reg[17] + 1) & 0x0F	-- increase R15 (check 4bit wrap)
		if reg[17] ~= 0 then
			st[1] = (st[1] & 0xF00) |
				rom[2](st[1])	-- jump to addr8
			return
		end
		st[1] = st[1] + 1	-- increment PC
	end-- >}

	-- 0x8?: ADD (Add register to accum with carry)	-->{
	--
	-- ADD r (<4bit opcode> <4bit register>)
	opset[0x80+1] = function()		-- ADD 0
		tnibble = reg[1] + reg[2] +
			flag[1]			-- Acc + R0 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x81+1] = function()		-- ADD 1
		tnibble = reg[1] + reg[3] +
			flag[1]			-- Acc + R1 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x82+1] = function()		-- ADD 2
		tnibble = reg[1] + reg[4] +
			flag[1]			-- Acc + R2 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x83+1] = function()		-- ADD 3
		tnibble = reg[1] + reg[5] +
			flag[1]			-- Acc + R3 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x84+1] = function()		-- ADD 4
		tnibble = reg[1] + reg[6] +
			flag[1]			-- Acc + R4 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x85+1] = function()		-- ADD 5
		tnibble = reg[1] + reg[7] +
			flag[1]			-- Acc + R5 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x86+1] = function()		-- ADD 6
		tnibble = reg[1] + reg[8] +
			flag[1]			-- Acc + R6 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x87+1] = function()		-- ADD 7
		tnibble = reg[1] + reg[9] +
			flag[1]			-- Acc + R7 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x88+1] = function()		-- ADD 8
		tnibble = reg[1] + reg[10] +
			flag[1]			-- Acc + R8 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x89+1] = function()		-- ADD 9
		tnibble = reg[1] + reg[11] +
			flag[1]			-- Acc + R9 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x8A+1] = function()		-- ADD 10
		tnibble = reg[1] + reg[12] +
			flag[1]			-- Acc + R10 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x8B+1] = function()		-- ADD 11
		tnibble = reg[1] + reg[13] +
			flag[1]			-- Acc + R11 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x8C+1] = function()		-- ADD 12
		tnibble = reg[1] + reg[14] +
			flag[1]			-- Acc + R12 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x8D+1] = function()		-- ADD 13
		tnibble = reg[1] + reg[15] +
			flag[1]			-- Acc + R13 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x8E+1] = function()		-- ADD 14
		tnibble = reg[1] + reg[16] +
			flag[1]			-- Acc + R14 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x8F+1] = function()		-- ADD 15
		tnibble = reg[1] + reg[17] +
			flag[1]			-- Acc + R15 + Carry
		flag[1] = (tnibble > 0x0F) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end-- >}

	-- 0x9?: SUB (Subtract register to accum with carry as borrow)	-->{
	--
	-- SUB r (<4bit opcode> <4bit register>)
	opset[0x90+1] = function()		-- SUB 0
		tnibble = reg[1] - reg[2] -
			(1 - flag[1])		-- Acc - R0 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x91+1] = function()		-- SUB 1
		tnibble = reg[1] - reg[3] -
			(1 - flag[1])		-- Acc - R1 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x92+1] = function()		-- SUB 2
		tnibble = reg[1] - reg[4] -
			(1 - flag[1])		-- Acc - R2 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x93+1] = function()		-- SUB 3
		tnibble = reg[1] - reg[5] -
			(1 - flag[1])		-- Acc - R3 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x94+1] = function()		-- SUB 4
		tnibble = reg[1] - reg[6] -
			(1 - flag[1])		-- Acc - R4 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x95+1] = function()		-- SUB 5
		tnibble = reg[1] - reg[7] -
			(1 - flag[1])		-- Acc - R5 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x96+1] = function()		-- SUB 6
		tnibble = reg[1] - reg[8] -
			(1 - flag[1])		-- Acc - R6 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x97+1] = function()		-- SUB 7
		tnibble = reg[1] - reg[9] -
			(1 - flag[1])		-- Acc - R7 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x98+1] = function()		-- SUB 8
		tnibble = reg[1] - reg[10] -
			(1 - flag[1])		-- Acc - R8 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x99+1] = function()		-- SUB 9
		tnibble = reg[1] - reg[11] -
			(1 - flag[1])		-- Acc - R9 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x9A+1] = function()		-- SUB 10
		tnibble = reg[1] - reg[12] -
			(1 - flag[1])		-- Acc - R10 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x9B+1] = function()		-- SUB 11
		tnibble = reg[1] - reg[13] -
			(1 - flag[1])		-- Acc - R11 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x9C+1] = function()		-- SUB 12
		tnibble = reg[1] - reg[14] -
			(1 - flag[1])		-- Acc - R12 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x9D+1] = function()		-- SUB 13
		tnibble = reg[1] - reg[15] -
			(1 - flag[1])		-- Acc - R13 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x9E+1] = function()		-- SUB 14
		tnibble = reg[1] - reg[16] -
			(1 - flag[1])		-- Acc - R14 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end
	opset[0x9F+1] = function()		-- SUB 15
		tnibble = reg[1] - reg[17] -
			(1 - flag[1])		-- Acc - R15 - (1 - Carry)
		flag[1] = (tnibble >= 0) and
			1 or 0			-- set Carry
		reg[1] = tnibble & 0x0F		-- update Acc (check 4bit wrap)
	end-- >}
	
	-- 0xA?: LD (Load register to accum)	-->{
	--
	-- LD r (<4bit opcode> <4bit register>)
	opset[0xA0+1] = function()		-- LD 0
		reg[1] = reg[2]			-- copy R0 to Acc
	end
	opset[0xA1+1] = function()		-- LD 1
		reg[1] = reg[3]			-- copy R1 to Acc
	end
	opset[0xA2+1] = function()		-- LD 2
		reg[1] = reg[4]			-- copy R2 to Acc
	end
	opset[0xA3+1] = function()		-- LD 3
		reg[1] = reg[5]			-- copy R3 to Acc
	end
	opset[0xA4+1] = function()		-- LD 4
		reg[1] = reg[6]			-- copy R4 to Acc
	end
	opset[0xA5+1] = function()		-- LD 5
		reg[1] = reg[7]			-- copy R5 to Acc
	end
	opset[0xA6+1] = function()		-- LD 6
		reg[1] = reg[8]			-- copy R6 to Acc
	end
	opset[0xA7+1] = function()		-- LD 7
		reg[1] = reg[9]			-- copy R7 to Acc
	end
	opset[0xA8+1] = function()		-- LD 8
		reg[1] = reg[10]		-- copy R8 to Acc
	end
	opset[0xA9+1] = function()		-- LD 9
		reg[1] = reg[11]		-- copy R9 to Acc
	end
	opset[0xAA+1] = function()		-- LD 10
		reg[1] = reg[12]		-- copy R10 to Acc
	end
	opset[0xAB+1] = function()		-- LD 11
		reg[1] = reg[13]		-- copy R11 to Acc
	end
	opset[0xAC+1] = function()		-- LD 12
		reg[1] = reg[14]		-- copy R12 to Acc
	end
	opset[0xAD+1] = function()		-- LD 13
		reg[1] = reg[15]		-- copy R13 to Acc
	end
	opset[0xAE+1] = function()		-- LD 14
		reg[1] = reg[16]		-- copy R14 to Acc
	end
	opset[0xAF+1] = function()		-- LD 15
		reg[1] = reg[17]		-- copy R15 to Acc
	end-- >}

	-- 0xB?: XCH (Exchange A with register)	-->{
	--
	-- XCH r (<4bit opcode> <4bit register>)
	opset[0xB0+1] = function()		-- XCH 0
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[2]			-- copy Rn to Acc
		reg[2] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB1+1] = function()	-- XCH 1
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[3]			-- copy Rn to Acc
		reg[3] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB2+1] = function()	-- XCH 2
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[4]			-- copy Rn to Acc
		reg[4] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB3+1] = function()	-- XCH 3
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[5]			-- copy Rn to Acc
		reg[5] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB4+1] = function()	-- XCH 4
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[6]			-- copy Rn to Acc
		reg[6] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB5+1] = function()	-- XCH 5
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[7]			-- copy Rn to Acc
		reg[7] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB6+1] = function()	-- XCH 6
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[8]			-- copy Rn to Acc
		reg[8] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB7+1] = function()	-- XCH 7
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[9]			-- copy Rn to Acc
		reg[9] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB8+1] = function()	-- XCH 8
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[10]		-- copy Rn to Acc
		reg[10] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xB9+1] = function()	-- XCH 9
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[11]		-- copy Rn to Acc
		reg[11] = tnibble			-- copy tnibble (Acc) to Rn
	end
	opset[0xBA+1] = function()	-- XCH 10
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[12]		-- copy Rn to Acc
		reg[12] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xBB+1] = function()	-- XCH 11
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[13]		-- copy Rn to Acc
		reg[13] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xBC+1] = function()	-- XCH 12
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[14]		-- copy Rn to Acc
		reg[14] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xBD+1] = function()	-- XCH 13
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[15]		-- copy Rn to Acc
		reg[15] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xBE+1] = function()	-- XCH 14
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[16]		-- copy Rn to Acc
		reg[16] = tnibble		-- copy tnibble (Acc) to Rn
	end
	opset[0xBF+1] = function()	-- XCH 15
		tnibble = reg[1]		-- store A to tnibble
		reg[1] = reg[17]		-- copy Rn to Acc
		reg[17] = tnibble		-- copy tnibble (Acc) to Rn
	end-- >}

	-- 0xC?: BBL (Branch Back and Load)	-->{
	--
	-- BBL k (<4bit opcode> <4bit const>)
	local f_undr = "STACK UNDERFLOW"
	opset[0xC0+1] = function()	-- BBL 0
		reg[1] = 0x0			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]	-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC1+1] = function()	-- BBL 1
		reg[1] = 0x1			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]	-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC2+1] = function()		-- BBL 2
		reg[1] = 0x2			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC3+1] = function()		-- BBL 3
		reg[1] = 0x3			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC4+1] = function()		-- BBL 4
		reg[1] = 0x4			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC5+1] = function()		-- BBL 5
		reg[1] = 0x5			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC6+1] = function()		-- BBL 6
		reg[1] = 0x6			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC7+1] = function()		-- BBL 7
		reg[1] = 0x7			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC8+1] = function()		-- BBL 8
		reg[1] = 0x8			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xC9+1] = function()		-- BBL 9
		reg[1] = 0x9			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xCA+1] = function()		-- BBL 10
		reg[1] = 0xA			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xCB+1] = function()		-- BBL 11
		reg[1] = 0xB			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xCC+1] = function()		-- BBL 12
		reg[1] = 0xC			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xCD+1] = function()		-- BBL 13
		reg[1] = 0xD			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xCE+1] = function()		-- BBL 14
		reg[1] = 0xE			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end
	opset[0xCF+1] = function()		-- BBL 15
		reg[1] = 0xF			-- copy k to Acc
		if #st[2] == 0 then
			FAULT(f_undr)		-- UB causes cpu fault
			return
		end
		st[1] = st[2][#st[2]]		-- pop stack to PC
		st[2][#st[2]] = nil		-- empty last bucket
	end-- >}

	-- 0xD?: LDM (Load Immediate to Accum)	-->{
	--
	-- LDM k (<4bit opcode> <4bit const>)
	opset[0xD0+1] = function()		-- LDM 0
		reg[1] = 0x0			-- copy k to Acc
	end
	opset[0xD1+1] = function()		-- LDM 1
		reg[1] = 0x1			-- copy k to Acc
	end
	opset[0xD2+1] = function()		-- LDM 2
		reg[1] = 0x2			-- copy k to Acc
	end
	opset[0xD3+1] = function()		-- LDM 3
		reg[1] = 0x3			-- copy k to Acc
	end
	opset[0xD4+1] = function()		-- LDM 4
		reg[1] = 0x4			-- copy k to Acc
	end
	opset[0xD5+1] = function()		-- LDM 5
		reg[1] = 0x5			-- copy k to Acc
	end
	opset[0xD6+1] = function()		-- LDM 6
		reg[1] = 0x6			-- copy k to Acc
	end
	opset[0xD7+1] = function()		-- LDM 7
		reg[1] = 0x7			-- copy k to Acc
	end
	opset[0xD8+1] = function()		-- LDM 8
		reg[1] = 0x8			-- copy k to Acc
	end
	opset[0xD9+1] = function()		-- LDM 9
		reg[1] = 0x9			-- copy k to Acc
	end
	opset[0xDA+1] = function()		-- LDM A
		reg[1] = 0xA			-- copy k to Acc
	end
	opset[0xDB+1] = function()		-- LDM B
		reg[1] = 0xB			-- copy k to Acc
	end
	opset[0xDC+1] = function()		-- LDM C
		reg[1] = 0xC			-- copy k to Acc
	end
	opset[0xDD+1] = function()		-- LDM D
		reg[1] = 0xD			-- copy k to Acc
	end
	opset[0xDE+1] = function()		-- LDM E
		reg[1] = 0xE			-- copy k to Acc
	end
	opset[0xDF+1] = function()		-- LDM F
		reg[1] = 0xF			-- copy k to Acc
	end-- >}

	-- 0xE?: RAM / I-O instructions	-->{
	--
	opset[0xE0+1] = function()		-- WRM (write Acc to RAM main)
		ram[3](reg[18] & 0x0F, reg[1])
	end
	opset[0xE1+1] = function()		-- WMP (write Acc to main output port)
		ram[6](reg[1])		-- main output port
	end
	opset[0xE2+1] = function()		-- WRR (write Acc to RAM status port)
		ram[7](reg[1])		-- status port
	end
	opset[0xE3+1] = function()		-- WPM (write Acc to program output port)
		ram[10](reg[1])		-- program output port
	end
	opset[0xE4+1] = function()		-- WR0 (write Acc to RAM status 0)
		ram[5](0x0, reg[1])
	end
	opset[0xE5+1] = function()		-- WR1 (write Acc to RAM status 1)
		ram[5](0x1, reg[1])
	end
	opset[0xE6+1] = function()		-- WR2 (write Acc to RAM status 2)
		ram[5](0x2, reg[1])
	end
	opset[0xE7+1] = function()		-- WR3 (write Acc to RAM status 3)
		ram[5](0x3, reg[1])
	end
	opset[0xE8+1] = function()		-- SBM (subtract RAM from Acc with borrow)
		tbyte = ram[2](reg[18] & 0x0F)
		tnibble = reg[1] - tbyte - (1 - flag[1])
		flag[1] = (tnibble >= 0) and 1 or 0
		reg[1] = tnibble & 0x0F
	end
	opset[0xE9+1] = function()		-- RDM (read RAM to Acc)
		reg[1] = ram[2](reg[18] & 0x0F)
	end
	opset[0xEA+1] = function()		-- RDR (read input port to Acc)
		reg[1] = ram[8]()
	end
	opset[0xEB+1] = function()		-- ADM (add RAM to Acc with carry)
		tbyte = ram[2](reg[18] & 0x0F)
		tnibble = reg[1] + tbyte + flag[1]
		flag[1] = (tnibble > 0x0F) and 1 or 0
		reg[1] = tnibble & 0x0F
	end
	opset[0xEC+1] = function()		-- RD0 (read RAM status 0 to Acc)
		reg[1] = ram[4](0x0)
	end
	opset[0xED+1] = function()		-- RD1 (read RAM status 1 to Acc)
		reg[1] = ram[4](0x1)
	end
	opset[0xEE+1] = function()		-- RD2 (read RAM status 2 to Acc)
		reg[1] = ram[4](0x2)
	end
	opset[0xEF+1] = function()		-- RD3 (read RAM status 3 to Acc)
		reg[1] = ram[4](0x3)
	end -- >}

	-- 0xF?: Accumulator / Flag ops	-->{
	--
	--
	opset[0xF0+1] = function()		-- CLB (clear both)
		reg[1] = 0			-- clear Acc
		flag[1] = 0			-- clear Carry
	end
	opset[0xF1+1] = function()		-- CLC (clear carry)
		flag[1] = 0			-- clear Carry
	end
	opset[0xF2+1] = function()		-- IAC (increment A with Carry)
		tnibble = reg[1] + 1		-- store Acc+1 to tnibble
		flag[1] = (tnibble > 0x0F)
			and 1 or 0		-- update Carry
		reg[1] = tnibble		-- update Acc
	end
	opset[0xF3+1] = function()		-- CMC (complement Carry)
		flag[1] = 1 - flag[1]		-- invert Carry
	end
	opset[0xF4+1] = function()		-- CMA (complement Acc)
		reg[1] = (~reg[1]) & 0x0F	-- invert Acc
	end
	opset[0xF5+1] = function()		-- RAL (rotate A left through C)
		tnibble = (reg[1] >> 3) & 1	-- new Carry
		reg[1] = ((reg[1] << 1)	& 
			0x0F) | flag[1] 	-- update Acc
		flag[1] = tnibble		-- update Carry
	end
	opset[0xF6+1] = function()		-- RAR (rotate A right through C)
		tnibble = reg[1] & 1		-- new Carry
		reg[1] = (reg[1] >> 1) & 
			(flag[1] << 3)		-- update Acc
		flag[1] = tnibble		-- update Carry
	end
	opset[0xF7+1] = function()		-- TCC (tranfer Carry to Acc)
		reg[1] = flag[1]		-- copy C to A
		flag[1] = 0			-- clear Carry
	end
	opset[0xF8+1] = function()		-- DAC (decrement Acc, no Carry)
		reg[1] = (reg[1] - 1) & 0x0F	-- copy C to A
	end
	opset[0xF9+1] = function()		-- TCS (tranfer C to A, set C to 1)
		reg[1] = flag[1]		-- copy C to A
		flag[1] = 1			-- set Carry
	end
	opset[0xFA+1] = function()		-- STC (set Carry)
		flag[1] = 1			-- set Carry
	end
	opset[0xFB+1] = function()		-- DAA (Decimal adjust A) (BCD)
		if (reg[1] > 9) or
			(flag[1] == 1) then
			reg[1] = (reg[1] + 6) &
				0x0F		-- set Acc
			flag[1] = 1		-- set Carry
		else
			flag[1] = 0		-- clear Carry
		end
	end
	opset[0xFC+1] = function()		-- KBP (Keyboard process)
		if reg[1] == 0x1 then
			reg[1] = 0		-- 0001 -> 0
		elseif reg[1] == 0x2 then
			reg[1] = 1		-- 0010 -> 1
		elseif reg[1] == 0x4 then
			reg[1] = 2		-- 0100 -> 2
		elseif reg[1] == 0x8 then
			reg[1] = 3		-- 1000 -> 3
		else
			-- impossible case
			-- hw did not allowed
			-- multiple keys
			reg[1] = 0xF		-- più tasti o nessuno
		end
	end
	opset[0xFD+1] = function()		-- DCL (Designate RAM bank)
		-- FIXME: TO BE IMPLEMENTED
	end
	-- 0xFE -> 0xFF: undefined / reserved>}

	pin[1]()	-- issue a RESET
	return pin
end


return M

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
