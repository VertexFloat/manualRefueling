-- @author: 4c65736975, All Rights Reserved
-- @version: 1.0.0.3, 29|01|2024
-- @filename: main.lua

-- Changelog (1.0.0.1):
-- improved and more clearly code
-- fixed refilling from some placeables

-- Changelog (1.0.0.2):
-- optimized and cleaned code
-- added sounds for starting/stopping refueling
-- removed unnecessary functionality (refueling no more stops when player leave trigger or enter vehicle)

-- Changelog (1.0.0.3):
-- optimized and cleaned code
-- added support for manual refueling from objects such as barrels and pallets
-- added DEF fill type support

MOD_DIRECTORY = g_currentModDirectory
SOUNDS_CONFIG_XML_PATH = MOD_DIRECTORY .. "data/sounds/sounds.xml"

INTERACTION_RADIUS = 5.0

OBJECT_MASK = {
  [1075838976] = 1076887552,
  [1088421888] = 1089470464,
  [2097152] = 3145728
}
SUPPORTED_FILL_TYPES = {
  ["DIESEL"] = true,
  ["ELECTRICCHARGE"] = true,
  ["METHANE"] = true,
  ["DEF"] = true
}

local function load(self, superFunc, components, xmlFile, key, customEnv, i3dMappings, rootNode)
  local ret = superFunc(self, components, xmlFile, key, customEnv, i3dMappings, rootNode)

  for i = 1, #self.loadTriggers do
    local loadTrigger = self.loadTriggers[i]
    local isValidFillTypes = true

    for fillTypeIndex, _ in pairs(loadTrigger.fillTypes) do
      local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)

      if SUPPORTED_FILL_TYPES[fillTypeName] == nil then
        isValidFillTypes = false

        break
      end
    end

    if isValidFillTypes then
      local collisionMask = OBJECT_MASK[getCollisionMask(loadTrigger.triggerNode)]

      if collisionMask ~= nil then
        setCollisionMask(loadTrigger.triggerNode, collisionMask)

        loadTrigger.isManual = true
        loadTrigger.isPlayerInTrigger = false

        local xmlSoundsFile = loadXMLFile("soundsXML", SOUNDS_CONFIG_XML_PATH)

        if xmlSoundsFile ~= nil and xmlSoundsFile ~= 0 then
          loadTrigger.samples.start = g_soundManager:loadSampleFromXML(xmlSoundsFile, "sounds.start", "sample", MOD_DIRECTORY, getRootNode(), 1, AudioGroup.ENVIRONMENT, nil, nil)
          loadTrigger.samples.stop = g_soundManager:loadSampleFromXML(xmlSoundsFile, "sounds.stop", "sample", MOD_DIRECTORY, getRootNode(), 1, AudioGroup.ENVIRONMENT, nil, nil)

          if loadTrigger.samples.start ~= nil and loadTrigger.samples.stop ~= nil then
            link(loadTrigger.soundNode, loadTrigger.samples.start.soundNode)
            setTranslation(loadTrigger.samples.start.soundNode, 0, 0, 0)

            link(loadTrigger.soundNode, loadTrigger.samples.stop.soundNode)
            setTranslation(loadTrigger.samples.stop.soundNode, 0, 0, 0)
          end

          delete(xmlSoundsFile)
        end
      end
    end
  end

  return ret
end

LoadingStation.load = Utils.overwrittenFunction(LoadingStation.load, load)

local function loadTriggerCallback(self, triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
  if self.isManual and g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
    if onEnter or onStay and g_currentMission.player.isControlled then
      self.isPlayerInTrigger = true
      -- we need to make sure it is added to the activatable objects
      g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)
    else
      self.isPlayerInTrigger = false

      g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)
    end
  end
end

LoadTrigger.loadTriggerCallback = Utils.appendedFunction(LoadTrigger.loadTriggerCallback, loadTriggerCallback)

local function startLoading(self, fillType, fillableObject, fillUnitIndex)
  if not self.isLoading and self.samples.start ~= nil then
    if self.isClient then
      g_soundManager:playSample(self.samples.start)
    end
  end
end

LoadTrigger.startLoading = Utils.prependedFunction(LoadTrigger.startLoading, startLoading)

local function stopLoading(self)
  if self.isLoading and self.samples.stop ~= nil then
    if self.isClient then
      g_soundManager:playSample(self.samples.stop)
    end
  end
end

LoadTrigger.stopLoading = Utils.prependedFunction(LoadTrigger.stopLoading, stopLoading)

local function getIsObjectFilled(object, fillUnitIndex)
  if object ~= nil and object.getFillUnitFreeCapacity ~= nil and fillUnitIndex ~= nil then
    return not (object:getFillUnitFreeCapacity(fillUnitIndex) > 0)
  end

  return false
end

local function getIsSourceEmpty(loadTrigger)
  if loadTrigger.hasInfiniteCapacity then
    return false
  end

  local fillLevels = loadTrigger.source:getAllFillLevels(g_currentMission:getFarmId())

  for _, fillLevel in pairs(fillLevels) do
    if fillLevel > 0.0 then
      return false
    end
  end

  return true
end

local function getCanAccessObject(object)
  if object ~= nil then
    local ownerId = object:getOwnerFarmId()
    local farmId = g_currentMission:getFarmId()
    local conductor = AccessHandler:canFarmAccessOtherId(farmId, ownerId)

    if ownerId == farmId or conductor then
      return true
    end
  end

  return false
end

local function getAllowsActivation(self, superFunc, fillableObject)
  if getIsSourceEmpty(self) then
    return false
  end

  local fillUnitIndex = nil

  for _, object in pairs(self.fillableObjects) do
    if object.object == fillableObject then
      fillUnitIndex = object.fillUnitIndex
    end
  end

  if getIsObjectFilled(fillableObject, fillUnitIndex) then
    return false
  end

  if self.isManual then
    return getCanAccessObject(fillableObject)
  end

  return superFunc(self, fillableObject)
end

LoadTrigger.getAllowsActivation = Utils.overwrittenFunction(LoadTrigger.getAllowsActivation, getAllowsActivation)

local function getIsFillableObjectAvailable(self, superFunc)
  if self.isManual then
    if next(self.fillableObjects) == nil then
      return false
    elseif self.isLoading then
      if self.currentFillableObject ~= nil and self:getAllowsActivation(self.currentFillableObject) then
        return true
      end
    else
      self.validFillableObject = nil
      self.validFillableFillUnitIndex = nil

      if self.isPlayerInTrigger then
        local nearestObject = nil
        local nearestDistance = math.huge

        for _, fillableObject in pairs(self.fillableObjects) do
          local objectDistance = calcDistanceFrom(fillableObject.object.rootNode, g_currentMission.player.rootNode)

          if objectDistance < nearestDistance and objectDistance <= INTERACTION_RADIUS then
            nearestDistance = objectDistance
            nearestObject = fillableObject
          end
        end

        if nearestObject ~= nil then
          if self:getAllowsActivation(nearestObject.object) and nearestObject.object:getFillUnitSupportsToolType(nearestObject.fillUnitIndex, ToolType.TRIGGER) then
            if not self.source:getIsFillAllowedToFarm(self:farmIdForFillableObject(nearestObject.object)) then
              return false
            end

            self.validFillableObject = nearestObject.object
            self.validFillableFillUnitIndex = nearestObject.fillUnitIndex

            g_currentMission:showFuelContext(self.validFillableObject)

            return true
          end
        end
      end
    end

    return false
  end

  return superFunc(self)
end

LoadTrigger.getIsFillableObjectAvailable = Utils.overwrittenFunction(LoadTrigger.getIsFillableObjectAvailable, getIsFillableObjectAvailable)

local function new(self, superFunc, id, sourceObject, fillUnitIndex, fillLitersPerSecond, defaultFillType, customMt)
  local ret = superFunc(self, id, sourceObject, fillUnitIndex, fillLitersPerSecond, defaultFillType, customMt)

  local isValidFillTypes = true

  for fillTypeIndex, _ in pairs(ret.sourceObject:getFillUnitSupportedFillTypes(ret.fillUnitIndex)) do
    local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)

    if SUPPORTED_FILL_TYPES[fillTypeName] == nil then
      isValidFillTypes = false
    end
  end

  if isValidFillTypes then
    local collisionMask = OBJECT_MASK[getCollisionMask(ret.triggerId)]

    if collisionMask ~= nil then
      setCollisionMask(ret.triggerId, collisionMask)

      ret.isManual = true
      ret.vehiclesInTrigger = {}
      ret.isPlayerInTrigger = false
    end
  end

  return ret
end

FillTrigger.new = Utils.overwrittenFunction(FillTrigger.new, new)

local function fillTriggerCallback(self, triggerId, otherId, onEnter, onLeave, onStay)
  if self.isManual and self.isEnabled then
    local vehicle = g_currentMission:getNodeObject(otherId)

    if vehicle ~= nil and vehicle.addFillUnitTrigger ~= nil and vehicle.removeFillUnitTrigger ~= nil and vehicle ~= self and vehicle ~= self.sourceObject then
      if onEnter or onStay then
        local fillType = self:getCurrentFillType()
        local fillUnitIndex = vehicle:getFirstValidFillUnitToFill(fillType)

        if fillUnitIndex ~= nil then
          self.vehiclesInTrigger[otherId] = {
            object = vehicle,
            distance = math.huge
          }
        end
      else
        self.vehiclesInTrigger[otherId] = nil
      end
    end

    if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
      if onEnter or onStay and g_currentMission.player.isControlled then
        self.isPlayerInTrigger = true
      else
        self.isPlayerInTrigger = false
      end
    end
  end
end

FillTrigger.fillTriggerCallback = Utils.appendedFunction(FillTrigger.fillTriggerCallback, fillTriggerCallback)

local function getIsActivatable(self, superFunc, vehicle)
  local ret = superFunc(self, vehicle)

  if ret and self.isManual then
    if self.isPlayerInTrigger and next(self.vehiclesInTrigger) ~= nil then
      local nearestVehicle = nil
      local nearestDistance = math.huge

      for _, vehicle in pairs(self.vehiclesInTrigger) do
        if entityExists(vehicle.object.rootNode) then
          vehicle.distance = calcDistanceFrom(vehicle.object.rootNode, g_currentMission.player.rootNode)

          if vehicle.distance < nearestDistance and vehicle.distance <= INTERACTION_RADIUS then
            nearestDistance = vehicle.distance
            nearestVehicle = vehicle.object
          end
        end
      end

      if nearestVehicle ~= nil and vehicle == nearestVehicle then
        return true
      end

      return false
    end

    return false
  end

  return ret
end

FillTrigger.getIsActivatable = Utils.overwrittenFunction(FillTrigger.getIsActivatable, getIsActivatable)

-- unfortunately we have to override this function to add a delay in the fill sound,
-- to avoid the start sound and the fill sound being played equally
local function setFillSoundIsPlaying(self, superFunc, state)
  if self.isManual and self.samples ~= nil and self.samples.start ~= nil then
    if state then
      local sharedSample = g_fillTypeManager:getSampleByFillType(self:getCurrentFillType())

      if sharedSample ~= nil then
        if sharedSample ~= self.sharedSample then
          if self.sample ~= nil then
            g_soundManager:deleteSample(self.sample)
          end

          self.sample = g_soundManager:cloneSample(sharedSample, self.soundNode, self)
          self.sharedSample = sharedSample

          g_soundManager:playSample(self.sample, 350)
        elseif not g_soundManager:getIsSamplePlaying(self.sample) then
          g_soundManager:playSample(self.sample, 350)
        end
      end
    elseif g_soundManager:getIsSamplePlaying(self.sample) then
      g_soundManager:stopSample(self.sample)
    end
  end

  return superFunc(self, state)
end

FillTrigger.setFillSoundIsPlaying = Utils.overwrittenFunction(FillTrigger.setFillSoundIsPlaying, setFillSoundIsPlaying)

local function getIsActivatable(self, superFunc)
  local fillUnitIndex = self.vehicle:getFirstValidFillUnitToFill(self.fillTypeIndex)

  if fillUnitIndex ~= nil then
    local enoughSpace = self.vehicle:getFillUnitFillLevel(fillUnitIndex) < self.vehicle:getFillUnitCapacity(fillUnitIndex) - 1
    local allowsFilling = self.vehicle:getFillUnitAllowsFillType(fillUnitIndex, self.fillTypeIndex)
    local allowsToolType = self.vehicle:getFillUnitSupportsToolType(fillUnitIndex, ToolType.TRIGGER)

    if enoughSpace and allowsFilling and allowsToolType then
      local spec = self.vehicle.spec_fillUnit

      for _, trigger in ipairs(spec.fillTrigger.triggers) do
        if trigger.isManual and getCanAccessObject(self.vehicle) and trigger:getIsActivatable(self.vehicle) then
          self:updateActivateText(spec.fillTrigger.isFilling)

          if not spec.fillTrigger.isFilling then
            g_currentMission:showFuelContext(self.vehicle)
          end

          return true
        end

        return superFunc(self)
      end
    end
  end

  return superFunc(self)
end

FillActivatable.getIsActivatable = Utils.overwrittenFunction(FillActivatable.getIsActivatable, getIsActivatable)

local function run(self)
  local spec = self.vehicle.spec_fillUnit

  if spec.fillTrigger.currentTrigger ~= nil and spec.fillTrigger.currentTrigger.isManual then
    self.vehicle:raiseActive()
  end
end

FillActivatable.run = Utils.appendedFunction(FillActivatable.run, run)