local socket = require("socket")
local machine = require("Busicom141PF")
local kbd_input = require("kbd_driver")
kbd_input.init_input()

local logic = machine.bc141PF

--local FREQ = 4500000
local FREQ = 740000

local t0 = socket.gettime()
local cycles_done = 0


local drum_timer = 0
local drum_period = 1000  -- cycles per drum revolution

local stepping = 10
while true do
--for cy = 1, 3 do
	local t = socket.gettime()
	local elapsed = t - t0

	local target_cycles = math.floor(elapsed * FREQ)
	local to_run = target_cycles - cycles_done

	-- PRINTER DRUM SPINNING-UP
	drum_timer = drum_timer + to_run
	if drum_timer >= drum_period then
		drum_timer = 0
		-- Drum sector pulse: active low briefly
		logic[3](0)  -- set test pin = 0 (inactive sector)
		-- After a few cycles, back to 1
	else
		logic[3](1)  -- set test pin = 1 (active sector)
	end

	-- STEPPING CYCLE
	if to_run > 0 then
		if to_run > stepping then
			to_run = stepping
		end

		kbd_input.check_keyboard_input() 
		cycles_done = cycles_done + to_run
		while to_run > 0 do
			to_run = to_run - logic[2]()
		end

		machine.lgt()
		machine.prn()

		if logic[10] == 1 or logic[11] == 1 then
			break
		end
	else
		socket.sleep(0.0001)
	end

	-- renormalize every 10 seconds
	if elapsed > 10.0 then
		t0 = t
		cycles_done = 0
	end
end

r, f, s = logic[16]()
cpu = logic
