-- @author: 4c65736975, All Rights Reserved
-- @version: 1.0.0.2, 23/02/2023
-- @filename: ManualRefueling.lua

-- Changelog (1.0.0.1) :
--
-- improved and more clearly code
-- fixed refilling from some placeables

-- Changelog (1.0.0.2) :
--
-- optimized and cleaned code
-- added sounds for starting/stopping refueling
-- removed unnecessary functionality (refueling no more stops when player leave trigger or enter vehicle)

ManualRefueling = {
	MOD_DIRECTORY = g_currentModDirectory,
	OBJECT_MASK = {
		OLD = {1075838976, 2097152},
		NEW = {1076887552, 3145728}
	}
}

ManualRefueling.SOUND_XML = ManualRefueling.MOD_DIRECTORY .. 'src/resources/sounds/sound.xml'
ManualRefueling.SOUND_LOAD_DELAY = 350

function ManualRefueling:getValidFillableFillUnitIndex(fillableObject, fillableObjects)
	for _, validFillableObject in pairs(fillableObjects) do
		if fillableObject ~= nil then
			if fillableObject == validFillableObject.object then
				return validFillableObject.fillUnitIndex
			end
		end
	end
end

function ManualRefueling:getIsLoadTriggerManual(triggerId)
	for _, station in pairs(g_currentMission.storageSystem:getLoadingStations()) do
		for _, loadTrigger in pairs(station.loadTriggers) do
			if loadTrigger.triggerNode == triggerId then
				if loadTrigger.isManual ~= nil then
					return loadTrigger.isManual
				end
			end
		end
	end

	return false
end

function ManualRefueling:getIsSourceNotEmpty(source, fillUnitIndex, fillableObject)
	if fillableObject ~= nil then
		local supportedFillTypes = fillableObject:getFillUnitSupportedFillTypes(fillUnitIndex)

		for _, loadTrigger in pairs(source.loadTriggers) do
			for fillTypeIndex, _ in pairs(loadTrigger.fillTypes) do
				for supportedFillType, _ in pairs(supportedFillTypes) do
					if fillTypeIndex == supportedFillType then
						local fillLevels = source:getAllFillLevels(g_currentMission:getFarmId())

						for fillType, fillLevel in pairs(fillLevels) do
							if fillTypeIndex == fillType then
								if fillLevel > 0 then
									return false
								end
							end
						end
					end
				end
			end

			if loadTrigger.hasInfiniteCapacity then
				return false
			end
		end
	end

	return true
end

local function onFinalizePlacement()
	for _, station in pairs(g_currentMission.storageSystem:getLoadingStations()) do
		for _, loadTrigger in pairs(station.loadTriggers) do
			for index, _ in pairs(loadTrigger.fillTypes) do
				if ((index == g_fillTypeManager:getFillTypeIndexByName('DIESEL')) or (index == g_fillTypeManager:getFillTypeIndexByName('ELECTRICCHARGE')) or (index == g_fillTypeManager:getFillTypeIndexByName('METHANE'))) then
					local collisionMask = getCollisionMask(loadTrigger.triggerNode)

					for i = 1, #ManualRefueling.OBJECT_MASK.OLD do
						local oldMask = ManualRefueling.OBJECT_MASK.OLD[i]

						if collisionMask == oldMask then
							setCollisionMask(loadTrigger.triggerNode, ManualRefueling.OBJECT_MASK.NEW[i])

							loadTrigger.isManual = true

							local xmlSoundFile = loadXMLFile('soundXML', ManualRefueling.SOUND_XML)

							if xmlSoundFile ~= nil and xmlSoundFile ~= 0 then
								loadTrigger.samples.start = g_soundManager:loadSampleFromXML(xmlSoundFile, 'sound.start', 'sample', ManualRefueling.MOD_DIRECTORY, getRootNode(), 1, AudioGroup.ENVIRONMENT, nil, nil)
								loadTrigger.samples.stop = g_soundManager:loadSampleFromXML(xmlSoundFile, 'sound.stop', 'sample', ManualRefueling.MOD_DIRECTORY, getRootNode(), 1, AudioGroup.ENVIRONMENT, nil, nil)

								if loadTrigger.samples.start ~= nil and loadTrigger.samples.stop ~= nil then
									link(loadTrigger.soundNode, loadTrigger.samples.start.soundNode)
									setTranslation(loadTrigger.samples.start.soundNode, 0, 0, 0)

									link(loadTrigger.soundNode, loadTrigger.samples.stop.soundNode)
									setTranslation(loadTrigger.samples.stop.soundNode, 0, 0, 0)
								end

								delete(xmlSoundFile)
							end
						end
					end
				else
					loadTrigger.isManual = false
				end
			end
		end
	end
end

Placeable.finalizePlacement = Utils.appendedFunction(Placeable.finalizePlacement, onFinalizePlacement)

local function startLoading(self, superFunc, fillType, fillableObject, fillUnitIndex)
	if self.isManual and self.samples.start ~= nil then
		if not self.isLoading then
			if self.isClient then
				g_soundManager:playSample(self.samples.start, 0, self.samples.load)

				g_effectManager:setFillType(self.effects, self.selectedFillType)
				g_effectManager:startEffects(self.effects)

				if self.scroller ~= nil then
					setShaderParameter(self.scroller, self.scrollerShaderParameterName, self.scrollerSpeedX, self.scrollerSpeedY, 0, 0, false)
				end
			end

			self:raiseActive()

			self.isLoading = true
			self.selectedFillType = fillType
			self.currentFillableObject = fillableObject
			self.fillUnitIndex = fillUnitIndex

			self.activatable:setText(self.stopFillText)
		end
	else
		return superFunc(self, fillType, fillableObject, fillUnitIndex)
	end
end

LoadTrigger.startLoading = Utils.overwrittenFunction(LoadTrigger.startLoading, startLoading)

local function stopLoading(self, superFunc)
	if self.isManual and self.samples.stop ~= nil then
		if self.isLoading then
			if self.isClient then
				g_soundManager:playSample(self.samples.stop)
			end
		end
	end

	return superFunc(self)
end

LoadTrigger.stopLoading = Utils.overwrittenFunction(LoadTrigger.stopLoading, stopLoading)

local function loadTriggerCallback(self, superFunc, triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	local fillableObject = g_currentMission:getNodeObject(otherId)

	self.isManual = ManualRefueling:getIsLoadTriggerManual(triggerId)
	self.playerInTrigger = false

	if fillableObject ~= nil then
		if fillableObject ~= self.source and fillableObject.getRootVehicle ~= nil and fillableObject.getFillUnitIndexFromNode ~= nil then
			local fillTypes = self.source:getSupportedFillTypes()

			if fillTypes ~= nil then
				local foundFillUnitIndex = fillableObject:getFillUnitIndexFromNode(otherId)

				if foundFillUnitIndex ~= nil then
					local found = false

					for fillTypeIndex, state in pairs(fillTypes) do
						if state and (self.fillTypes == nil or self.fillTypes[fillTypeIndex]) then
							if fillableObject:getFillUnitSupportsFillType(foundFillUnitIndex, fillTypeIndex) then
								if fillableObject:getFillUnitAllowsFillType(foundFillUnitIndex, fillTypeIndex) then
									found = true

									break
								end
							end
						end
					end

					if not found then
						foundFillUnitIndex = nil
					end
				end

				if foundFillUnitIndex == nil then
					for fillTypeIndex, state in pairs(fillTypes) do
						if state and (self.fillTypes == nil or self.fillTypes[fillTypeIndex]) then
							local fillUnits = fillableObject:getFillUnits()

							for fillUnitIndex, fillUnit in ipairs(fillUnits) do
								if fillUnit.exactFillRootNode == nil then
									if fillableObject:getFillUnitSupportsFillType(fillUnitIndex, fillTypeIndex) then
										if fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
											foundFillUnitIndex = fillUnitIndex

											break
										end
									end
								end
							end
						end
					end
				end

				if foundFillUnitIndex ~= nil then
					if onEnter or onStay then
						self.fillableObjects[otherId] = {
							object = fillableObject,
							fillUnitIndex = foundFillUnitIndex
						}

						fillableObject:addDeleteListener(self)
					elseif onLeave then
						self.fillableObjects[otherId] = nil

						fillableObject:removeDeleteListener(self)

						if self.isLoading and self.currentFillableObject == fillableObject then
							self:setIsLoading(false)
						end

						if fillableObject == self.validFillableObject then
							self.validFillableObject = nil
							self.validFillableFillUnitIndex = nil
						end
					end

					if self.automaticFilling then
						if not self.isLoading and next(self.fillableObjects) ~= nil and self:getIsFillableObjectAvailable() then
							self:toggleLoading()
						end
					elseif next(self.fillableObjects) ~= nil and not self.isManual then
						g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)
					else
						g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)
					end
				end
			end
		end
	end

	if self.isManual then
		if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
			if onEnter and next(self.fillableObjects) ~= nil and g_currentMission.player.isControlled then
				g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)

				self.playerInTrigger = true
			else
				g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)

				self.playerInTrigger = false
			end
		end
	end
end

LoadTrigger.loadTriggerCallback = Utils.overwrittenFunction(LoadTrigger.loadTriggerCallback, loadTriggerCallback)

local function getIsFillableObjectAvailable(self)
	if next(self.fillableObjects) == nil then
		return false
	else
		if self.isLoading then
			if self.currentFillableObject ~= nil and self:getAllowsActivation(self.currentFillableObject) then
				return true
			end
		else
			self.validFillableObject = nil
			self.validFillableFillUnitIndex = nil

			-- last object that was filled has lower prio than the other objects in the trigger
			-- so we can guarantee that all objects will be filled
			-- !
			-- it's counting all of components so for one vehicle if it has two or more components it's blocking action when we stop refilling and
			-- we must enter trigger with vehicle again, so, so far for manual refilling trigger it's disabled and always return one vehicle in trigger
			-- !
			local hasLowPrioObject = false
			local numOfObjects = 0

			for _, fillableObject in pairs(self.fillableObjects) do
				if fillableObject.lastWasFilled then
					hasLowPrioObject = true
				end

				if self.isManual then
					numOfObjects = 1
				else
					numOfObjects = numOfObjects + 1
				end
			end

			hasLowPrioObject = hasLowPrioObject and (numOfObjects > 1)

			for _, fillableObject in pairs(self.fillableObjects) do
				if not fillableObject.lastWasFilled or not hasLowPrioObject then
					if self:getAllowsActivation(fillableObject.object) then
						if fillableObject.object:getFillUnitSupportsToolType(fillableObject.fillUnitIndex, ToolType.TRIGGER) then
							if not self.source:getIsFillAllowedToFarm(self:farmIdForFillableObject(fillableObject.object)) then
								return false
							end

							self.validFillableObject = fillableObject.object
							self.validFillableFillUnitIndex = fillableObject.fillUnitIndex

							return true
						end
					end
				end
			end
		end
	end

	return false
end

LoadTrigger.getIsFillableObjectAvailable = Utils.overwrittenFunction(LoadTrigger.getIsFillableObjectAvailable, getIsFillableObjectAvailable)

local function getAllowsActivation(self, superFunc, fillableObject)
	local fillUnitIndex = ManualRefueling:getValidFillableFillUnitIndex(fillableObject, self.fillableObjects)
	local isEmpty = ManualRefueling:getIsSourceNotEmpty(self.source, fillUnitIndex, fillableObject)

	if not self.requiresActiveVehicle then
		return true
	end

	if fillableObject.getAllowLoadTriggerActivation ~= nil and fillableObject:getAllowLoadTriggerActivation(fillableObject) then
		if fillUnitIndex ~= nil then
			local fillableObjectFillLevel = fillableObject:getFillUnitFillLevelPercentage(fillUnitIndex)

			if fillableObjectFillLevel ~= nil and fillableObjectFillLevel < 1.0 and not isEmpty then
				return true
			end
		end
	end

	if self.isManual then
		if self.playerInTrigger then
			local player = g_currentMission.player.rootNode
			local distance = calcDistanceFrom(fillableObject.rootNode, player)

			if distance < 5 then
				if fillUnitIndex ~= nil then
					local fillableObjectFillLevel = fillableObject:getFillUnitFillLevelPercentage(fillUnitIndex)
					local ownerId = fillableObject:getOwnerFarmId()
					local farmId = g_currentMission:getFarmId()
					local conductor = AccessHandler:canFarmAccessOtherId(farmId, ownerId)

					if (ownerId == farmId or (ownerId ~= farmId and conductor)) then
						if fillableObjectFillLevel ~= nil and fillableObjectFillLevel < 1.0 and not isEmpty then
							g_currentMission:showFuelContext(fillableObject)

							return true
						end
					end
				end
			end
		end
	end

	return false
end

LoadTrigger.getAllowsActivation = Utils.overwrittenFunction(LoadTrigger.getAllowsActivation, getAllowsActivation)

local function setFillSoundIsPlaying(self, superFunc, state)
	if self.isManual and self.samples.start ~= nil then
		if state then
			local sharedSample = g_fillTypeManager:getSampleByFillType(self:getCurrentFillType())

			if sharedSample ~= nil then
				if sharedSample ~= self.sharedSample then
					if self.sample ~= nil then
						g_soundManager:deleteSample(self.sample)
					end

					self.sample = g_soundManager:cloneSample(sharedSample, self.soundNode, self)
					self.sharedSample = sharedSample

					g_soundManager:playSample(self.sample, ManualRefueling.SOUND_LOAD_DELAY)
				elseif not g_soundManager:getIsSamplePlaying(self.sample) then
					g_soundManager:playSample(self.sample, ManualRefueling.SOUND_LOAD_DELAY)
				end
			end
		elseif g_soundManager:getIsSamplePlaying(self.sample) then
			g_soundManager:stopSample(self.sample)
		end
	else
		return superFunc(self, state)
	end
end

FillTrigger.setFillSoundIsPlaying = Utils.overwrittenFunction(FillTrigger.setFillSoundIsPlaying, setFillSoundIsPlaying)