-- Author: VertexFloat
-- Date: 05.07.2022
-- Version: Farming Simulator 22, 1.0.0.1
-- Copyright (C): VertexFloat, All Rights Reserved
-- Manual Refueling

-- Changelog (1.0.0.1) :
--
-- improved and more clearly code
-- fixed refilling from some placeables

ManualRefueling = {
    OBJECT_MASK = {
        OLD = {
            1075838976,
            2097152
        },
        NEW = {
            1076887552,
            3145728
        }
    }
}

local function onFinalizePlacement()
    ManualRefueling:updateLoadTriggersColMask(ManualRefueling.OBJECT_MASK)
end

Placeable.finalizePlacement = Utils.appendedFunction(Placeable.finalizePlacement, onFinalizePlacement)

function ManualRefueling:loadTriggerCallback(superFunc, triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    local fillableObject = g_currentMission:getNodeObject(otherId)

    self.isManual = ManualRefueling:getIsLoadTriggerManual(triggerId)
    self.playerInTrigger = false

    if fillableObject ~= nil and fillableObject ~= self.source and fillableObject.getRootVehicle ~= nil and fillableObject.getFillUnitIndexFromNode ~= nil then
        local fillTypes = self.source:getSupportedFillTypes()

        if fillTypes ~= nil then
            local foundFillUnitIndex = fillableObject:getFillUnitIndexFromNode(otherId)

            if foundFillUnitIndex ~= nil then
                local found = false

                for fillTypeIndex, state in pairs(fillTypes) do
                    if state and (self.fillTypes == nil or self.fillTypes[fillTypeIndex]) and fillableObject:getFillUnitSupportsFillType(foundFillUnitIndex, fillTypeIndex) and fillableObject:getFillUnitAllowsFillType(foundFillUnitIndex, fillTypeIndex) then
                        found = true

                        break
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
                            if fillUnit.exactFillRootNode == nil and fillableObject:getFillUnitSupportsFillType(fillUnitIndex, fillTypeIndex) and fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
                                foundFillUnitIndex = fillUnitIndex

                                break
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

    if self.isManual then
        if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
            if onEnter and next(self.fillableObjects) ~= nil and g_currentMission.player.isControlled then
                g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)

                self.playerInTrigger = true
            else
                g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)

                if self.isLoading then
                    if not self.isElectric then
                        self:setIsLoading(false)
                    end
                end

                self.playerInTrigger = false
            end
        end
    end
end

LoadTrigger.loadTriggerCallback = Utils.overwrittenFunction(LoadTrigger.loadTriggerCallback, ManualRefueling.loadTriggerCallback)

function ManualRefueling:getIsFillableObjectAvailable()
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

LoadTrigger.getIsFillableObjectAvailable = Utils.overwrittenFunction(LoadTrigger.getIsFillableObjectAvailable, ManualRefueling.getIsFillableObjectAvailable)

function ManualRefueling:getAllowsActivation(superFunc, fillableObject)
    local fillUnitIndex = ManualRefueling:getValidFillableFillUnitIndex(fillableObject, self.fillableObjects)
    local isEmpty = ManualRefueling:getIsSourceNotEmpty(self.source, fillUnitIndex, fillableObject)

    self.isElectric = ManualRefueling:getIsFillableFillTypeIsElectric(self.source, fillUnitIndex, fillableObject)

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

                    if fillableObjectFillLevel ~= nil and fillableObjectFillLevel < 1.0 and not isEmpty and fillableObject:getOwnerFarmId() == g_currentMission:getFarmId() then
                        g_currentMission:showFuelContext(fillableObject)

                        return true
                    end
                end
            elseif not self.isElectric then
                self:setIsLoading(false)
            end
        end

        if not g_currentMission.player.isControlled then
            if not self.isElectric then
                self:setIsLoading(false)
            end
        end
    end

    return false
end

LoadTrigger.getAllowsActivation = Utils.overwrittenFunction(LoadTrigger.getAllowsActivation, ManualRefueling.getAllowsActivation)

function ManualRefueling:updateLoadTriggersColMask(objectsMasks)
    for _, station in pairs(g_currentMission.storageSystem:getLoadingStations()) do
        for _, loadTrigger in pairs(station.loadTriggers) do
            for index, _ in pairs(loadTrigger.fillTypes) do
                if (index == g_fillTypeManager:getFillTypeIndexByName("DIESEL")) or (index == g_fillTypeManager:getFillTypeIndexByName("ELECTRICCHARGE")) or (index == g_fillTypeManager:getFillTypeIndexByName("METHANE")) then
                    local collisionMask = getCollisionMask(loadTrigger.triggerNode)
                    local oldMasks = objectsMasks.OLD

                    for i = 1, #oldMasks do
                        local oldMask = oldMasks[i]

                        if collisionMask == oldMask then
                            local newMasks = objectsMasks.NEW

                            for j = 1, #newMasks do
                                local newMask = newMasks[i]

                                setCollisionMask(loadTrigger.triggerNode, newMask)

                                loadTrigger.isManual = true
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

function ManualRefueling:getIsLoadTriggerManual(triggerId)
    for _, station in pairs(g_currentMission.storageSystem:getLoadingStations()) do
        for _, loadTrigger in pairs(station.loadTriggers) do
            if loadTrigger.triggerNode == triggerId then
                if loadTrigger.isManual == true then
                    return true
                end
            end
        end
    end

    return false
end

function ManualRefueling:getValidFillableFillUnitIndex(fillableObject, fillableObjects)
    for _, validFillableObject in pairs(fillableObjects) do
        if fillableObject ~= nil then
            if fillableObject == validFillableObject.object then
                return validFillableObject.fillUnitIndex
            end
        end
    end
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

function ManualRefueling:getIsFillableFillTypeIsElectric(source, fillUnitIndex, fillableObject)
    if fillableObject ~= nil then
        local supportedFillTypes = fillableObject:getFillUnitSupportedFillTypes(fillUnitIndex)

        for _, loadTrigger in pairs(source.loadTriggers) do
            for fillTypeIndex, _ in pairs(loadTrigger.fillTypes) do
                for supportedFillType, _ in pairs(supportedFillTypes) do
                    if fillTypeIndex == supportedFillType then
                        local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)

                        if fillTypeName == "ELECTRICCHARGE" then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end