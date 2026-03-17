--;===========================================================
--; DYNAMIC DIFFICULTY SCALING MOD
--;
--; Difficulty ramps based on current health:
--;   100-76% HP -> difficulty 1-3
--;    75-51% HP -> difficulty 3-5
--;    50-26% HP -> difficulty 5-7
--;    25-0%  HP -> difficulty 7-9
--;
--; Anti-corner system:
--;   When one player is pinned near the screen edge and the
--;   attacker is close, the attacker's AI drops to 1 so they
--;   back off and give the cornered player room to fight.
--;===========================================================

local CHECK_EVERY = 60 -- frames between difficulty updates
local CORNER_CHECK_EVERY = 5 -- frames between corner checks (fast response)
local frameCounter = 0
local cornerFrameCounter = 0
local scalingActive = false

-- Anti-corner settings
local CORNER_EDGE_DIST = 30    -- how close to screen edge counts as "cornered"
local CORNER_PLAYER_DIST = 60  -- how close attacker must be to trigger back-off
local CORNER_BACKOFF_AI = 1    -- AI level when backing off
local cornerBackoff = { false, false } -- track if each player is in back-off mode

-- Difficulty tiers
local TIERS = {
	{ threshold = 76, low = 1, high = 3 },
	{ threshold = 51, low = 3, high = 5 },
	{ threshold = 26, low = 5, high = 7 },
	{ threshold = 0,  low = 7, high = 9 },
}

local function getTierDifficulty(hpPercent)
	for _, tier in ipairs(TIERS) do
		if hpPercent >= tier.threshold then
			return math.random(tier.low, tier.high)
		end
	end
	return math.random(7, 9)
end

local function getHealthPercent(pn)
	local oldid = id()
	if not player(pn) then
		playerid(oldid)
		return 100
	end
	local hp = life()
	local maxhp = lifemax()
	playerid(oldid)
	if maxhp <= 0 then return 100 end
	return math.floor((hp / maxhp) * 100)
end

local function getPlayerPosX(pn)
	local oldid = id()
	if not player(pn) then
		playerid(oldid)
		return 0
	end
	local px = posX()
	playerid(oldid)
	return px
end

local function updateDifficulty()
	for pn = 1, 2 do
		if not cornerBackoff[pn] then
			local hpPct = getHealthPercent(pn)
			local diff = getTierDifficulty(hpPct)
			setCom(pn, diff)
		end
	end
end

-- Detect corner trapping and force the attacker to back off
local function updateCornerCheck()
	local p1x = getPlayerPosX(1)
	local p2x = getPlayerPosX(2)
	local le = leftedge()
	local re = rightedge()

	local p1DistToEdge = math.min(math.abs(p1x - le), math.abs(p1x - re))
	local p2DistToEdge = math.min(math.abs(p2x - le), math.abs(p2x - re))
	local distBetween = math.abs(p1x - p2x)

	-- Check if P1 is cornered and P2 is pressing them
	if p1DistToEdge < CORNER_EDGE_DIST and distBetween < CORNER_PLAYER_DIST then
		if not cornerBackoff[2] then
			cornerBackoff[2] = true
			setCom(2, CORNER_BACKOFF_AI)
		end
	else
		if cornerBackoff[2] then
			cornerBackoff[2] = false
		end
	end

	-- Check if P2 is cornered and P1 is pressing them
	if p2DistToEdge < CORNER_EDGE_DIST and distBetween < CORNER_PLAYER_DIST then
		if not cornerBackoff[1] then
			cornerBackoff[1] = true
			setCom(1, CORNER_BACKOFF_AI)
		end
	else
		if cornerBackoff[1] then
			cornerBackoff[1] = false
		end
	end
end

hook.add("loop", "difficulty_scaling", function()
	-- Reset on round 1 start
	if roundstart() and roundno() == 1 then
		scalingActive = false
		frameCounter = 0
		cornerFrameCounter = 0
		cornerBackoff = { false, false }
	end

	if not scalingActive then
		scalingActive = true
		updateDifficulty()
	end

	-- Difficulty update every ~1 second
	frameCounter = frameCounter + 1
	if frameCounter >= CHECK_EVERY then
		frameCounter = 0
		updateDifficulty()
	end

	-- Corner trap check (very frequent for fast response)
	cornerFrameCounter = cornerFrameCounter + 1
	if cornerFrameCounter >= CORNER_CHECK_EVERY then
		cornerFrameCounter = 0
		updateCornerCheck()
	end
end)

print("[DifficultyScaling] Mod loaded! HP-based difficulty + anti-corner active.")
