--====================================================================================
-- All work by jojos38 & Titch2000.
-- You have no permission to edit, redistribute or upload. Contact us for more info!
--====================================================================================



local M = {}

-- ============= VARIABLES =============
local posErrorCorrectMul = 1   -- How much acceleration to use for correcting position error
local maxPosError = 10         -- If position error is larger than this, teleport the vehicle
local maxVelChange = 2         -- If velocity change larger than this, reset it
local rotErrorCorrectMul = 2   -- How much acceleration to use for correcting angle error
local maxRotError = 2          -- If rotation error is larger than this, reset rotation
local maxRotVelChange = 3      -- If rotation velocity change larger than this, reset it
-- ============= VARIABLES =============

-- functions for testing
local function setPosErrorMul(val)
	posErrorCorrectMul = val
end

local function setPosErrorMax(val)
	maxPosError = val
end

local function setVelChangeMax(val)
	maxVelChange = val
end

local function setRotErrorMul(val)
	rotErrorCorrectMul = val
end

local function setRotErrorMax(val)
	maxRotError = val
end

local function setRotVelChangeMax(val)
	maxRotVelChange = val
end

-- Get angle between 2 quaternions
local function quatAngle(a, b)
	return acos(abs(a:dot(b)))*2
end

local function tick()
	local ownMap = vehicleGE.getOwnMap() -- Get map of own vehicles
	for i,v in pairs(ownMap) do -- For each own vehicle
		local veh = be:getObjectByID(i) -- Get vehicle
		if veh then
			veh:queueLuaCommand("positionVE.getVehicleRotation()")
		end
	end
end



local function sendVehiclePosRot(data, gameVehicleID)
	if Network.getStatus() == 2 then -- If UDP connected
		local serverVehicleID = vehicleGE.getServerVehicleID(gameVehicleID) -- Get serverVehicleID
		if serverVehicleID and vehicleGE.isOwn(gameVehicleID) then -- If serverVehicleID not null and player own vehicle
			Network.send(Network.buildPacket(0, 2134, serverVehicleID, data))
		end
	end
end

-- TODO: remove these when velocity is synced from server
local lastPos = nil
local lastRot = nil
local lastTime = 0

local lastVel = nil
local lastRotVel = nil
local counter = 0
local function applyPos(data, serverVehicleID, timestamp)

	-- 1 = pos.x
	-- 2 = pos.y
	-- 3 = pos.z
	-- 4 = rot.x
	-- 5 = rot.y
	-- 6 = rot.z
	-- 7 = rot.w

	local gameVehicleID = vehicleGE.getGameVehicleID(serverVehicleID) or -1 -- get gameID
	local veh = be:getObjectByID(gameVehicleID)
	if veh then
		local pr = jsonDecode(data) -- Decoded data
		
		pos = vec3(pr[1], pr[2], pr[3])
		rot = quat(pr[4], pr[5], pr[6], pr[7])
		
		--debugDrawer:drawSphere(pos:toPoint3F(), 0.2, ColorF(1.0,0.0,0.0,1.0))
		
		if lastPos then
			vel = (pos - lastPos)/guardZero(timestamp - lastTime)
		else
			vel = vec3(0,0,0)
		end
		
		if lastRot then
			rotVel = (rot / lastRot):toEulerYXZ()/guardZero(timestamp - lastTime)
		else
			rotVel = vec3(0,0,0)
		end
		
		--print("dT = " .. (timestamp-lastTime) .. ", Vel = " .. tostring(vel) .. ", LastVel = " .. tostring(lastVel) .. ", RotVel = " .. tostring(rotVel) .. ", LastRotVel = " .. tostring(lastRotVel))
		
		-- If velocity changes to quickly, set it to 0
		-- TODO: find cleaner way to to this
		if lastVel and (vel-lastVel):length() > maxVelChange*lastVel:length() then
			--print("Vel = " .. tostring(vel) .. ", LastVel = " .. tostring(lastVel))
			lastVel = vel
			vel = vec3(0,0,0)
		else
			lastVel = vel
		end
		
		-- If angular velocity changes to quickly, set it to 0
		-- TODO: find cleaner way to to this
		if lastRotVel and (rotVel-lastRotVel):length() > maxRotVelChange*lastRotVel:length() then
			--print("RotVel = " .. tostring(rotVel) .. ", LastRotVel = " .. tostring(lastRotVel))
			lastRotVel = rotVel
			rotVel = vec3(0,0,0)
		else
			lastRotVel = rotVel
		end
		
		lastPos = pos
		lastRot = rot
		lastTime = timestamp
		
		vehPos = vec3(veh:getPosition())
		 -- Rotation is not updated in ge lua, but direction is, so we build rotation from direction
		vehRot = quatFromDir(vec3(-veh:getDirectionVector()), vec3(veh:getDirectionVectorUp()))
		
		posError = (pos - vehPos)
		rotError = (rot / vehRot):toEulerYXZ()
		
		if posError:length() > maxPosError or rotError:length() > maxRotError then
			print("PosError = " .. tostring(posError) .. ", RotError = " .. tostring(rotError))
			veh:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
			veh:queueLuaCommand("electricsVE.applyLatestElectrics()") -- Redefine electrics values
		else
			vel = vel + posError*posErrorCorrectMul
			rotVel = rotVel + rotError*rotErrorCorrectMul
		end
		
		veh:queueLuaCommand("velocityVE.setVelocity(" .. tostring(vel) .. ")")
		veh:queueLuaCommand("velocityVE.setAngularVelocity(" .. rotVel.y .. "," .. rotVel.z .. "," .. rotVel.x .. ")")
	end
end



M.applyPos          = applyPos
M.tick              = tick
M.sendVehiclePosRot = sendVehiclePosRot

M.setPosErrorMul = setPosErrorMul
M.setPosErrorMax = setPosErrorMax
M.setRotErrorMul = setRotErrorMul
M.setRotErrorMax = setRotErrorMax


return M
