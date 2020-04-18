--====================================================================================
-- All work by jojos38 & Titch2000.
-- You have no permission to edit, redistribute or upload. Contact us for more info!
--====================================================================================



local M = {}

local dequeue = require('dequeue')

-- ============= VARIABLES =============
local posErrorCorrectMul = 3   -- How much acceleration to use for correcting position error
local maxPosError = 1          -- If position error is larger than this, teleport the vehicle
local maxPosErrorMul = 0.1     -- Allow larger position error depending on velocity
local maxAcc = 10              -- If difference between average and current velocity larger than this, clamp it
local maxAccMul = 0.5          -- Allow larger velocity changes based on velocity
local rotErrorCorrectMul = 2   -- How much acceleration to use for correcting angle error
local maxRotError = 2          -- If rotation error is larger than this, reset rotation
local maxRotAcc = 2            -- If difference between average and current rotation velocity larger than this, clamp it
local maxRotAccMul = 1         -- Allow larger rotation velocity changes depending on velocity
local bufferTime = 0.15        -- How many seconds packets will be kept in buffer

local timer = 0
local lastPos = vec3(0,0,0)
local posBuf = dequeue.new()   -- Position buffer used for smoothing
-- ============= VARIABLES =============

local function getVehicleRotation()
	local pos = obj:getPosition()
	local distance = nodesVE.distance(pos.x, pos.y, pos.z, lastPos.x, lastPos.y, lastPos.z)
	lastPos = pos

	if (distance < 0.10) then -- When vehicle doesn't move
		if timer < 40 then -- Send 40 times less packets
			timer = timer + 1
			return
		else
			timer = 0
		end
	end

	local tempTable = {}
	local pos = obj:getPosition()
	local rot = obj:getRotation()
	tempTable[1] = pos.x
	tempTable[2] = pos.y
	tempTable[3] = pos.z
	tempTable[4] = rot.x
	tempTable[5] = rot.y
	tempTable[6] = rot.z
	tempTable[7] = rot.w
	obj:queueGameEngineLua("positionGE.sendVehiclePosRot(\'"..jsonEncode(tempTable).."\', \'"..obj:getID().."\')") -- Send it
end


local function setVehiclePosRot(pos, rot, timestamp)
	
	-- Remove packets older than bufferTime from buffer
	while posBuf:length() > 1 and posBuf:peek_left().timestamp < timestamp-bufferTime do
		posBuf:pop_left()
	end
	
	local lastPosData = posBuf:peek_right()
	
	local posData = {
		pos = pos, 
		rot = rot, 
		vel = lastPosData and (pos - lastPosData.pos)/guardZero(timestamp - lastPosData.timestamp) or vec3(0,0,0), 
		rotVel = lastPosData and (rot / lastPosData.rot):toEulerYXZ()/guardZero(timestamp - lastPosData.timestamp) or vec3(0,0,0), 
		timestamp = timestamp and timestamp or 0
	}
	
	posBuf:push_right(posData)
	
	-- Average velocity over buffer
	local avgVel = vec3(0,0,0)
	local avgRotVel = vec3(0,0,0)
	for data in posBuf:iter_left() do
		avgVel = avgVel + data.vel
		avgRotVel = avgRotVel + data.rotVel
	end
	
	avgVel = avgVel/posBuf:length()
	avgRotVel = avgRotVel/posBuf:length()
	
	-- Limit acceleration, but not deceleration
	if posData.vel:length() > avgVel:length()+maxAcc + avgVel:length()*maxAccMul then
		posData.vel = avgVel + avgVel:normalized()*maxAcc + avgVel*maxAccMul
	end
	
	if posData.rotVel:length() > avgRotVel:length()+maxRotAcc + avgRotVel:length()*maxRotAccMul then
		posData.rotVel = avgRotVel + avgRotVel:normalized()*maxRotAcc + avgRotVel*maxRotAccMul
	end
	
	--print("dT = " .. (timestamp-(lastPosData and lastPosData.timestamp or 0)) .. ", BufLen = " .. posBuf:length())
	
	local vehPos = vec3(obj:getPosition())
	local vehRot = quat(obj:getRotation())
	
	local posError = (pos - vehPos)
	local rotError = (rot / vehRot):toEulerYXZ()
	
	-- If position or angle errors are larger than limit, teleport the vehicle
	if posError:length() > (maxPosError + avgVel:length()*maxPosErrorMul) or rotError:length() > maxRotError then
		--print("PosError = " .. tostring(posError) .. ", RotError = " .. tostring(rotError))
		obj:queueGameEngineLua("vehicleSetPositionRotation("..obj:getID()..","..pos.x..","..pos.y..","..pos.z..","..rot.x..","..rot.y..","..rot.z..","..rot.w..")")
		electricsVE.applyLatestElectrics() -- Redefine electrics values
		posError = vec3(0,0,0)
		rotError = vec3(0,0,0)
	end
	
	-- Apply velocities
	velocityVE.setVelocity(avgVel + posError*posErrorCorrectMul)
	-- TODO: shorten this line
	velocityVE.setAngularVelocity(avgRotVel.y + rotError.y*rotErrorCorrectMul, avgRotVel.z + rotError.z*rotErrorCorrectMul, avgRotVel.x + rotError.x*rotErrorCorrectMul)
end

M.getVehicleRotation = getVehicleRotation
M.setVehiclePosRot = setVehiclePosRot


return M
