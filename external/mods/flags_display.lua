--;===========================================================
--; COUNTRY FLAGS DISPLAY MOD
--; Shows random country flags in two places:
--;   1. Circular flags over the yellow orbs next to portraits
--;   2. Rectangular static flags on the sides of the screen
--;===========================================================

local flagsData = require("external.mods.flags_index")
local flagsSff = nil
local flagsLoaded = false

-- Flag state per fight
local p1Flag = nil
local p2Flag = nil
local p1Label = nil
local p2Label = nil
local initialized = false

-- Scales
local ORB_FLAG_SCALE = 4 -- circular flag over the orb (50% larger than original 0.65)
local FLOAT_FLAG_SCALE = 2  -- flag floating above character's head
local FLOAT_X_OFFSET = 120    -- horizontal offset (positive = right, negative = left)
local FLOAT_Y_OFFSET = 230  -- pixels above character pos (in localcoord space, negative = up)
local LOCALCOORD_W = 500
local LOCALCOORD_H = 240
local GROUND_Y = 200           -- approximate ground line in screen localcoord space
local labelFont = nil

-- Orb positions (where the yellow balls are in the HUD)
-- fight.def [Face]: p1.pos=2,12  p2.pos=316,12
-- The orb center is roughly at face pos + offset
local P1_ORB_X = 90
local P1_ORB_Y = 180
local P2_ORB_X = 1180
local P2_ORB_Y = 187


local function loadFlags()
	if flagsLoaded then return true end
	local ok, sff = pcall(sffNew, "external/mods/flags.sff")
	if not ok or sff == nil then
		print("[Flags] ERROR: Could not load external/mods/flags.sff")
		return false
	end
	flagsSff = sff
	flagsLoaded = true
	print("[Flags] Loaded flags.sff (" .. flagsData.count .. " countries)")
	return true
end

local function createFlagAnim(group, spriteIndex, scale)
	local animStr = string.format("%d,%d, 0,0, -1", group, spriteIndex)
	local anim = animNew(flagsSff, animStr)
	animSetScale(anim, scale, scale)
	animUpdate(anim)
	return anim
end

local function createLabel(text)
	if labelFont == nil then
		labelFont = fontNew("font/f-6x9.def")
	end
	local t = textImgNew()
	textImgSetFont(t, labelFont)
	textImgSetText(t, text)
	textImgSetScale(t, 0.4, 0.4)
	textImgSetAlign(t, 0)
	return t
end

local function pickTwoCountries()
	local idx1 = math.random(0, flagsData.count - 1)
	local idx2 = idx1
	local attempts = 0
	while idx2 == idx1 and attempts < 50 do
		idx2 = math.random(0, flagsData.count - 1)
		attempts = attempts + 1
	end
	return idx1, idx2
end

local function initFight()
	if not loadFlags() then return false end

	local idx1, idx2 = pickTwoCountries()
	local c1 = flagsData.index[idx1]
	local c2 = flagsData.index[idx2]

	p1Flag = {
		index = idx1,
		code = c1.code,
		name = c1.name,
		orbAnim = createFlagAnim(0, idx1, ORB_FLAG_SCALE),
		floatAnim = createFlagAnim(0, idx1, FLOAT_FLAG_SCALE),
	}
	p2Flag = {
		index = idx2,
		code = c2.code,
		name = c2.name,
		orbAnim = createFlagAnim(0, idx2, ORB_FLAG_SCALE),
		floatAnim = createFlagAnim(0, idx2, FLOAT_FLAG_SCALE),
	}
	p1Label = createLabel(c1.code)
	p2Label = createLabel(c2.code)

	print("[Flags] P1: " .. c1.name .. " (" .. c1.code .. ")")
	print("[Flags] P2: " .. c2.name .. " (" .. c2.code .. ")")
	initialized = true
	return true
end

-- Draw circular flag over the yellow orb
local function drawOrbFlag(flagData, pn)
	if flagData == nil or flagData.orbAnim == nil then return end
	local ox = pn == 1 and P1_ORB_X or P2_ORB_X
	local oy = pn == 1 and P1_ORB_Y or P2_ORB_Y
	animSetPos(flagData.orbAnim, ox, oy)
	animDraw(flagData.orbAnim)
end


-- Draw floating flag above a character's head
local function drawFloatingFlag(flagData, pn)
	if flagData == nil or flagData.floatAnim == nil then return end
	local oldid = id()
	if not player(pn) then
		playerid(oldid)
		return
	end
	-- Get world position and camera info
	local wx = posX()
	local wy = posY()
	playerid(oldid)
	-- Convert world pos to screen localcoord space
	-- X: posX relative to left camera edge
	local le = leftedge()
	local sx = wx - le + FLOAT_X_OFFSET
	-- Y: posY is 0 at ground, negative is up. Map to screen coords.
	local sy = GROUND_Y + wy + FLOAT_Y_OFFSET
	animSetPos(flagData.floatAnim, sx, sy)
	animDraw(flagData.floatAnim)
end

-- Hook into the match loop
hook.add("loop", "flags_display", function()
	if roundstart() and roundno() == 1 then
		initialized = false
	end

	if not initialized then
		if not initFight() then return end
	end

	-- Draw circular flags over the orbs
	drawOrbFlag(p1Flag, 1)
	drawOrbFlag(p2Flag, 2)

	-- Draw floating flags above characters (disabled for now)
	--drawFloatingFlag(p1Flag, 1)
	--drawFloatingFlag(p2Flag, 2)
end)

print("[Flags] Mod loaded!")
