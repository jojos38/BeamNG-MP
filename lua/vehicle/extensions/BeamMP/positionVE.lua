--====================================================================================
-- All work by jojos38 & Titch2000.
-- You have no permission to edit, redistribute or upload. Contact us for more info!
--====================================================================================



local M = {}

local dequeue = require('dequeue')

-- ============= VARIABLES =============
local posErrorCorrectMul = 3   -- How much acceleration to use for correcting position error
local maxPosError = 2          -- If position error is larger than this, teleport the vehicle
local maxAcc = 10              -- If difference between average and current velocity larger than this, clamp it
local rotErrorCorrectMul = 2   -- How much acceleration to use for correcting angle error
local maxRotError = 2          -- If rotation error is larger than this, reset rotation
local maxRotAcc = 10           -- If difference between average and current rotation velocity larger than this, clamp it
local bufferTime = 0.1         -- How many seconds packets will be kept in buffer

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
	
	local avgVel = vec3(0,0,0)
	local avgRotVel = vec3(0,0,0)
	for data in posBuf:iter_left() do
		avgVel = avgVel + data.vel
		avgRotVel = avgRotVel + data.rotVel
	end
	
	avgVel = avgVel/posBuf:length()
	avgRotVel = avgRotVel/posBuf:length()
	
	if posData.vel:length() > avgVel:length()+maxAcc then
		posData.vel = avgVel+avgVel:normalized()*maxAcc
	end
	
	if posData.rotVel:length() > avgRotVel:length()+maxRotAcc then
		posData.rotVel = avgRotVel+avgRotVel:normalized()*maxRotAcc
	end
	
	print("dT = " .. (timestamp-(lastPosData and lastPosData.timestamp or 0)) .. ", BufLen = " .. posBuf:length())
	
	local vehPos = vec3(obj:getPosition())
	local vehRot = quat(obj:getRotation())
	
	local posError = (pos - vehPos)
	local rotError = (rot / vehRot):toEulerYXZ()
	
	if posError:length() > maxPosError or rotError:length() > maxRotError then
		--print("PosError = " .. tostring(posError) .. ", RotError = " .. tostring(rotError))
		obj:queueGameEngineLua("vehicleSetPositionRotation("..obj:getID()..","..pos.x..","..pos.y..","..pos.z..","..rot.x..","..rot.y..","..rot.z..","..rot.w..")")
		electricsVE.applyLatestElectrics() -- Redefine electrics values
		posError = vec3(0,0,0)
		rotError = vec3(0,0,0)
	end
	
	velocityVE.setVelocity(avgVel + posError*posErrorCorrectMul)
	-- TODO: shorten this line
	velocityVE.setAngularVelocity(avgRotVel.y + rotError.y*rotErrorCorrectMul, avgRotVel.z + rotError.z*rotErrorCorrectMul, avgRotVel.x + rotError.x*rotErrorCorrectMul)
end

M.getVehicleRotation = getVehicleRotation
M.setVehiclePosRot = setVehiclePosRot


return M
