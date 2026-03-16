--;===========================================================
--; TIKTOK LIVE GIFTS MOD
--; Reads gift commands from tiktok_commands.json and applies
--; heal/buff effects to Player 1 or Player 2 during matches.
--;===========================================================

-- Path to the commands file written by tiktok_bridge.py
local cmdFile = "tiktok_commands.json"

-- How often to check the file (in frames). 60 frames = 1 second at 60 FPS.
local CHECK_INTERVAL = 15

-- Frame counter
local frameCount = 0

-- Active buffs: each entry = {cmd, value, framesLeft, target}
local activeBuffs = {}

-- Debug: set to true to see print output in IkemenGO console
local DEBUG = true

local function debugLog(msg)
	if DEBUG then
		print("[TikTok] " .. msg)
	end
end

local function readCommands()
	local file = io.open(cmdFile, "r")
	if file == nil then
		return nil
	end
	local content = file:read("*all")
	file:close()
	if content == nil or content == "" or content == "[]" then
		return nil
	end
	local ok, data = pcall(json.decode, content)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return data
end

local function clearCommands()
	local file = io.open(cmdFile, "w")
	if file ~= nil then
		file:write("[]")
		file:close()
	end
end

-- Apply an instant command to a specific player.
-- Uses the same pattern as global.lua kill/full/powMax functions.
local function applyCommand(cmd)
	local oldid = id()
	local target = cmd.target or 1
	local cmdType = cmd.cmd or ""
	local value = cmd.value or 0
	local duration = cmd.duration or 1

	if player(target) then
		if cmdType == "heal" then
			local newLife = math.min(life() + value, lifemax())
			setLife(newLife)
			setRedLife(newLife)
			debugLog("P" .. target .. " healed +" .. value)

		elseif cmdType == "heal_full" then
			setLife(lifemax())
			setRedLife(lifemax())
			debugLog("P" .. target .. " FULL HEAL")

		elseif cmdType == "power" then
			local newPower = math.min(power() + value, powermax())
			setPower(newPower)
			debugLog("P" .. target .. " power +" .. value)

		elseif cmdType == "attack" or cmdType == "defense" then
			table.insert(activeBuffs, {cmd = "regen", value = value, framesLeft = duration, target = target})
			debugLog("P" .. target .. " regen buff " .. duration .. " frames")

		elseif cmdType == "speed" then
			table.insert(activeBuffs, {cmd = "powerregen", value = value, framesLeft = duration, target = target})
			debugLog("P" .. target .. " power regen buff " .. duration .. " frames")

		elseif cmdType == "godmode" then
			table.insert(activeBuffs, {cmd = "godmode", value = value, framesLeft = duration, target = target})
			debugLog("P" .. target .. " GOD MODE " .. duration .. " frames")

		elseif cmdType == "all" then
			table.insert(activeBuffs, {cmd = "regen", value = value * 2, framesLeft = duration, target = target})
			table.insert(activeBuffs, {cmd = "powerregen", value = value * 2, framesLeft = duration, target = target})
			debugLog("P" .. target .. " ALL BUFFS " .. duration .. " frames")
		end
		playerid(oldid)
	end
end

-- Process active buffs each frame.
-- Applies effects per-player using the same player()/playerid() pattern as engine.
local function processBuffs()
	if #activeBuffs == 0 then
		return
	end

	-- First pass: tick down and accumulate per-player totals
	local p1 = {godmode = false, regen = 0, powerRegen = 0}
	local p2 = {godmode = false, regen = 0, powerRegen = 0}

	local i = 1
	while i <= #activeBuffs do
		local buff = activeBuffs[i]
		buff.framesLeft = buff.framesLeft - 1

		if buff.framesLeft <= 0 then
			table.remove(activeBuffs, i)
		else
			local p = buff.target == 2 and p2 or p1
			if buff.cmd == "godmode" then
				p.godmode = true
			elseif buff.cmd == "regen" then
				p.regen = p.regen + buff.value / 60.0
			elseif buff.cmd == "powerregen" then
				p.powerRegen = p.powerRegen + buff.value / 60.0
			end
			i = i + 1
		end
	end

	-- Second pass: apply to each player (same pattern as full() in global.lua)
	local oldid = id()

	if p1.godmode or p1.regen > 0 or p1.powerRegen > 0 then
		if player(1) then
			if p1.godmode then
				setLife(lifemax())
				setRedLife(lifemax())
				setPower(powermax())
				setGuardPoints(guardpointsmax())
				setDizzyPoints(dizzypointsmax())
				removeDizzy()
			else
				if p1.regen > 0 then
					local newLife = math.min(life() + math.ceil(p1.regen), lifemax())
					setLife(newLife)
					setRedLife(newLife)
				end
				if p1.powerRegen > 0 then
					local newPower = math.min(power() + math.ceil(p1.powerRegen), powermax())
					setPower(newPower)
				end
			end
			playerid(oldid)
		end
	end

	if p2.godmode or p2.regen > 0 or p2.powerRegen > 0 then
		if player(2) then
			if p2.godmode then
				setLife(lifemax())
				setRedLife(lifemax())
				setPower(powermax())
				setGuardPoints(guardpointsmax())
				setDizzyPoints(dizzypointsmax())
				removeDizzy()
			else
				if p2.regen > 0 then
					local newLife = math.min(life() + math.ceil(p2.regen), lifemax())
					setLife(newLife)
					setRedLife(newLife)
				end
				if p2.powerRegen > 0 then
					local newPower = math.min(power() + math.ceil(p2.powerRegen), powermax())
					setPower(newPower)
				end
			end
			playerid(oldid)
		end
	end
end

-- Hook into the match loop
hook.add("loop", "tiktok_gifts", function()
	frameCount = frameCount + 1

	-- Check for new commands periodically
	if frameCount >= CHECK_INTERVAL then
		frameCount = 0
		local commands = readCommands()
		if commands ~= nil and #commands > 0 then
			debugLog("Read " .. #commands .. " command(s)")
			for _, cmd in ipairs(commands) do
				applyCommand(cmd)
			end
			clearCommands()
		end
	end

	-- Process active buffs every frame
	processBuffs()
end)

debugLog("Mod loaded!")
