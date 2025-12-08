local socket = require("socket")
--local core   = require("clive.cpu.core")

local FREQ = 2250000

local t0 = socket.gettime()
local cycles_done = 0
local max = 0
local min = math.huge

for i = 1, 100000 do
	local t = socket.gettime()
	local elapsed = t - t0

	local target_cycles = math.floor(elapsed * FREQ)
	local to_run = target_cycles - cycles_done

	if to_run > 0 then
		if to_run > 10000 then
			to_run = 10000
		end
--		io.write("\r"..to_run.."                  ")
		max = math.max(max, to_run)
		min = math.min(min, to_run)
		cycles_done = cycles_done + to_run
	else
		socket.sleep(0.0001)
	end
	print(i, to_run)

	-- renormalize every 10 seconds
	if elapsed > 10.0 then
		t0 = t
		cycles_done = 0
	end
end
print("MIN: "..min.." // MAX: "..max)
