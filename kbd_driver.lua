
-- keyboard_input.lua
local keyboard = require("keyboard")

local pipe_name = "/tmp/busicom_input"
local pipe_fd = nil

function init_inputOLD()
    -- Create named pipe if not existing
    os.execute("mkfifo " .. pipe_name .. " 2>/dev/null")
    -- Open FIFO in sort-of non-blocking mode
    pipe_fd = io.popen("timeout 0.001 cat " .. pipe_name .. " 2>/dev/null", "r")
end

function init_input()
    -- Create named pipe if missing
    os.execute("mkfifo " .. pipe_name .. " 2>/dev/null")
    -- Open FIFO in read mode
    pipe_fd = io.open(pipe_name, "r")
    if pipe_fd then
        pipe_fd:setvbuf("no")
    else
        error("Cannot open pipe " .. pipe_name)
    end
end

local pressed 
function check_keyboard_input()
    if not pipe_fd then init_input() end
   
    if pressed then
        keyboard.release_key(pressed)
        pressed = nil
    end

    -- Read non-blocking
    local input = pipe_fd:read("*l")
    if input then
        local cmd, key = input:match("(%w+)%s+(.+)")
        if cmd == "KEY" then 
            keyboard.press_key(key)
            pressed = key
        --elseif cmd == "RELEASE" then 
        elseif cmd == "DP" then
            keyboard.set_dp_switch(tonumber(key))
        elseif cmd == "ROUND" then
            keyboard.set_round_switch(tonumber(key))
        end
    end
end

return {check_keyboard_input = check_keyboard_input, init_input = init_input}

--[[

-- kbd_driver.lua
local fifo_path = "/tmp/busicom_input"
local fifo
function init_input()
    fifo = io.open(fifo_path, "r")
    if not fifo then
        error("Cannot open FIFO " .. fifo_path)
    end
    fifo:setvbuf("no")
end

function check_keyboard_input()
    if not fifo then return end
    local line = fifo:read("*l")  -- legge una riga (non-bloccante se qualcuno scrive)
    while line do
        -- Parsing semplice: es. "PRESS 2" o "RELEASE SQRT"
        local cmd, key = line:match("^(%a+)%s+(.+)$")
        if cmd and key then
            if cmd == "PRESS" then
                -- metti qui la chiamata alla tua logica di press-key
            elseif cmd == "RELEASE" then
                -- metti qui la chiamata alla tua logica di release-key
            end
        end
        line = fifo:read("*l")
    end
end


]]