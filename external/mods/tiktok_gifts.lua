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

--;===========================================================
--; HAMMER SYSTEM
--;===========================================================
local activeHammers = {}
local activeImpacts = {}

-- Hammer config
local HAMMER_DAMAGE = 200       -- HP damage on hit
local HAMMER_GRAVITY = 4        -- pixels per frame acceleration
local HAMMER_GROUND_Y = 580     -- ground level in screen coords (720 height)
local HAMMER_HIT_RANGE = 150    -- how close to player X to count as a hit (screen coords)
local SCREEN_W = 1280           -- screen render width
local SCREEN_H = 720            -- screen render height

-- Try to load hammer sprite and fightfx impact sprites
local hammerSff = nil
local hammerSffLoaded = false
local fightfxSff = nil

local function loadHammerSff()
	if hammerSffLoaded then return end
	hammerSffLoaded = true
	local ok, sff = pcall(sffNew, "external/mods/hammer.sff")
	if ok and sff ~= nil then
		hammerSff = sff
		print("[TikTok] Loaded hammer.sff sprite")
	else
		print("[TikTok] hammer.sff not found, using placeholder rectangle")
	end
	-- Load fightfx for impact effects
	local ok2, sff2 = pcall(sffNew, "data/fightfx.sff")
	if ok2 and sff2 ~= nil then
		fightfxSff = sff2
		print("[TikTok] Loaded fightfx.sff for impact effects")
	else
		print("[TikTok] Could not load fightfx.sff")
	end
end

local function spawnImpact(x, y, hit)
	local imp = {
		x = x,
		y = y,
		frame = 0,
		hit = hit,
		-- Strong ground shockwave: Action 62 (11 frames x 2 ticks = 22 frames)
		shockAnim = nil,
		-- Very strong hit spark: Action 3 (7 frames)
		sparkAnim = nil,
		maxFrames = 30,
	}
	if fightfxSff ~= nil then
		-- Ground shockwave (Action 62)
		local shockStr = "62,0, 0,0, 2\n62,1, 0,0, 2\n62,2, 0,0, 2\n62,3, 0,0, 2\n62,4, 0,0, 2\n62,5, 0,0, 2\n62,6, 0,0, 2\n62,7, 0,0, 2\n62,8, 0,0, 2\n62,9, 0,0, 2\n62,10, 0,0, 3"
		local ok1, anim1 = pcall(animNew, fightfxSff, shockStr)
		if ok1 and anim1 ~= nil then
			animSetScale(anim1, 6, 6)
			animSetPos(anim1, x, y)
			imp.shockAnim = anim1
		end
		if hit then
			-- Very strong hit spark (Action 3)
			local sparkStr = "3,0, 0,0, 1\n3,1, 0,0, 1\n3,2, 0,0, 1\n3,3, 0,0, 1\n3,4, 0,0, 2\n3,5, 0,0, 1\n3,6, 0,0, 2"
			local ok2, anim2 = pcall(animNew, fightfxSff, sparkStr)
			if ok2 and anim2 ~= nil then
				animSetScale(anim2, 6, 6)
				animSetPos(anim2, x, y - 40)
				imp.sparkAnim = anim2
			end
		end
	end
	table.insert(activeImpacts, imp)
end

local function spawnHammer()
	loadHammerSff()
	local x = math.random(100, SCREEN_W - 100)
	local hammer = {
		x = x,
		y = -160,
		vel = 0,
		active = true,
		anim = nil,
	}
	-- Create sprite anim if SFF loaded
	if hammerSff ~= nil then
		local anim = animNew(hammerSff, "0,0, 0,0, -1")
		animSetScale(anim, 0.5, 0.5)
		animUpdate(anim)
		hammer.anim = anim
	end
	table.insert(activeHammers, hammer)
	print("[TikTok] HAMMER spawned at X=" .. x)
end

local function getPlayerScreenX(pn)
	local oldid = id()
	if not player(pn) then
		playerid(oldid)
		return nil
	end
	local wx = posX()
	local le = leftedge()
	playerid(oldid)
	-- Convert world X to screen coords (1280 wide, center at 640)
	return wx - le + (SCREEN_W / 2)
end

local function processHammers()
	if #activeHammers == 0 then return end

	local i = 1
	while i <= #activeHammers do
		local h = activeHammers[i]
		if not h.active then
			table.remove(activeHammers, i)
		else
			-- Apply gravity
			h.vel = h.vel + HAMMER_GRAVITY
			h.y = h.y + h.vel

			-- Draw the hammer
			if h.anim ~= nil then
				animSetPos(h.anim, h.x, h.y)
				animDraw(h.anim)
			else
				-- Placeholder rectangle
				fillRect(h.x - 8, h.y - 120, h.x + 8, h.y, 101, 67, 33, 255, 0)
				fillRect(h.x - 40, h.y - 120, h.x + 40, h.y - 80, 160, 160, 160, 255, 0)
			end

			-- Check if hammer reached ground
			if h.y >= HAMMER_GROUND_Y then
				h.active = false
				-- Find which player is closer
				local p1x = getPlayerScreenX(1)
				local p2x = getPlayerScreenX(2)
				local hitTarget = nil
				local minDist = HAMMER_HIT_RANGE

				if p1x ~= nil then
					local d1 = math.abs(h.x - p1x)
					if d1 < minDist then
						minDist = d1
						hitTarget = 1
					end
				end
				if p2x ~= nil then
					local d2 = math.abs(h.x - p2x)
					if d2 < minDist then
						minDist = d2
						hitTarget = 2
					end
				end

				if hitTarget ~= nil then
					local oldid = id()
					if player(hitTarget) then
						local newLife = math.max(life() - HAMMER_DAMAGE, 0)
						setLife(newLife)
						setRedLife(newLife)
						print("[TikTok] HAMMER HIT P" .. hitTarget .. "! -" .. HAMMER_DAMAGE .. " HP")
					end
					playerid(oldid)
					spawnImpact(h.x, HAMMER_GROUND_Y, true)
				else
					print("[TikTok] HAMMER missed both players!")
					spawnImpact(h.x, HAMMER_GROUND_Y, false)
				end
			end

			i = i + 1
		end
	end
end

local function processImpacts()
	if #activeImpacts == 0 then return end

	local i = 1
	while i <= #activeImpacts do
		local imp = activeImpacts[i]
		imp.frame = imp.frame + 1

		if imp.frame > imp.maxFrames then
			table.remove(activeImpacts, i)
		else
			-- Draw and advance the fightfx animations
			if imp.shockAnim ~= nil then
				animDraw(imp.shockAnim)
				animUpdate(imp.shockAnim)
			end
			if imp.sparkAnim ~= nil then
				animDraw(imp.sparkAnim)
				animUpdate(imp.sparkAnim)
			end

			-- White screen flash on hit (first 4 frames)
			if imp.hit and imp.frame <= 4 then
				local flashAlpha = math.floor(180 * (1 - imp.frame / 4))
				fillRect(0, 0, SCREEN_W, SCREEN_H, 255, 255, 255, flashAlpha, 0)
			end

			i = i + 1
		end
	end
end

--;===========================================================
--; CORE FUNCTIONS
--;===========================================================

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

	-- Hammer: spawn falling hammer (ignores target)
	if cmdType == "hammer" then
		spawnHammer()
		return
	end

	-- target 0 = both players: apply to P1 and P2
	if target == 0 then
		local cmd1 = {cmd = cmdType, value = value, duration = duration, target = 1}
		local cmd2 = {cmd = cmdType, value = value, duration = duration, target = 2}
		applyCommand(cmd1)
		applyCommand(cmd2)
		return
	end

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
				-- Invulnerability only: lock life at current value, no healing
				setRedLife(life())
				setGuardPoints(guardpointsmax())
				setDizzyPoints(dizzypointsmax())
				removeDizzy()
			end
			if p1.regen > 0 then
				local newLife = math.min(life() + math.ceil(p1.regen), lifemax())
				setLife(newLife)
				setRedLife(newLife)
			end
			if p1.powerRegen > 0 then
				local newPower = math.min(power() + math.ceil(p1.powerRegen), powermax())
				setPower(newPower)
			end
			playerid(oldid)
		end
	end

	if p2.godmode or p2.regen > 0 or p2.powerRegen > 0 then
		if player(2) then
			if p2.godmode then
				-- Invulnerability only: lock life at current value, no healing
				setRedLife(life())
				setGuardPoints(guardpointsmax())
				setDizzyPoints(dizzypointsmax())
				removeDizzy()
			end
			if p2.regen > 0 then
				local newLife = math.min(life() + math.ceil(p2.regen), lifemax())
				setLife(newLife)
				setRedLife(newLife)
			end
			if p2.powerRegen > 0 then
				local newPower = math.min(power() + math.ceil(p2.powerRegen), powermax())
				setPower(newPower)
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

	-- Process falling hammers every frame
	processHammers()

	-- Process impact effects every frame
	processImpacts()
end)

debugLog("Mod loaded!")
