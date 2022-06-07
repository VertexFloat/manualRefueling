-- Author: VertexFloat
-- Date: 06.06.2022
-- Version: Farming Simulator 22, 1.0.0.0
-- Copyright (C): VertexFloat, All Rights Reserved
-- Manual Refueling

ManualRefueling = {
    OLD_TRIGGER_COLMASK = 1075838976,
    OLD_TRIGGER_COLMASK2 = 2097152,
    NEW_TRIGGER_COLMASK = 1076887552,
    NEW_TRIGGER_COLMASK2 = 3145728
}

local function onFinishedLoading()
    ManualRefueling:updateLoadTriggersColMask()
end

FSBaseMission.onFinishedLoading = Utils.appendedFunction(FSBaseMission.onFinishedLoading, onFinishedLoading)

local function onFinalizePlacement()
    ManualRefueling:updateLoadTriggersColMask()
end

Placeable.finalizePlacement = Utils.appendedFunction(Placeable.finalizePlacement, onFinalizePlacement)

function ManualRefueling:loadTriggerCallback(superFunc, triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    local isManual = ManualRefueling:getIsLoadTriggerManual(triggerId)
    local fillableObject = g_currentMission:getNodeObject(otherId)

    self.playerInTrigger = false
    self.currentTrigger = triggerId

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
                elseif next(self.fillableObjects) ~= nil and not isManual then
                    g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)
                else
                    g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)
                end
            end
        end
    end

    if isManual then
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

LoadTrigger.loadTriggerCallback = Utils.overwrittenFunction(LoadTrigger.loadTriggerCallback, ManualRefueling.loadTriggerCallback)

function ManualRefueling:getIsFillableObjectAvailable()
    if next(self.fillableObjects) == nil then
        return false
    elseif self.isLoading then
        if self.currentFillableObject ~= nil and self:getAllowsActivation(self.currentFillableObject) then
            return true
        end
    else
        self.validFillableObject = nil
        self.validFillableFillUnitIndex = nil
        local numOfObjects = 0

        for _, fillableObject in pairs(self.fillableObjects) do
            numOfObjects = numOfObjects + 1
        end

        for _, fillableObject in pairs(self.fillableObjects) do
            if self:getAllowsActivation(fillableObject.object) and fillableObject.object:getFillUnitSupportsToolType(fillableObject.fillUnitIndex, ToolType.TRIGGER) then
                if not self.source:getIsFillAllowedToFarm(self:farmIdForFillableObject(fillableObject.object)) then

                    return false
                end

                self.validFillableObject = fillableObject.object
                self.validFillableFillUnitIndex = fillableObject.fillUnitIndex

                return true
            end
        end
    end

    return false
end

LoadTrigger.getIsFillableObjectAvailable = Utils.overwrittenFunction(LoadTrigger.getIsFillableObjectAvailable, ManualRefueling.getIsFillableObjectAvailable)

function ManualRefueling:getAllowsActivation(superFunc, fillableObject)
    local fillUnitIndex = 1
    local isEmpty = true

    for _, validFillableObject in pairs(self.fillableObjects) do
        if fillableObject ~= nil then
            if fillableObject == validFillableObject.object then
                fillUnitIndex = validFillableObject.fillUnitIndex
            end
        end
    end

    for _, loadTrigger in pairs(self.source.loadTriggers) do
        if loadTrigger.hasInfiniteCapacity then
            isEmpty = false
        end
    end

    if fillableObject ~= nil then
        local supportedFillTypes = fillableObject:getFillUnitSupportedFillTypes(fillUnitIndex)

        for _, loadTrigger in pairs(self.source.loadTriggers) do
            for fillTypeIndex, _ in pairs(loadTrigger.fillTypes) do
                for supportedFillType, _ in pairs(supportedFillTypes) do
                    if fillTypeIndex == supportedFillType then
                        for _, source in pairs(self.source.sourceStorages) do
                            for fillType, fillLevel in pairs(source.fillLevels) do
                                if fillTypeIndex == fillType then
                                    if fillLevel > 0 then
                                        isEmpty = false
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not g_currentMission.player.isControlled and self.playerInTrigger then
        self:setIsLoading(false)
    end

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

    local isManual = ManualRefueling:getIsLoadTriggerManual(self.currentTrigger)

    if isManual then
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
            else
                 self:setIsLoading(false)
            end
        end
    end

    return false
end

LoadTrigger.getAllowsActivation = Utils.overwrittenFunction(LoadTrigger.getAllowsActivation, ManualRefueling.getAllowsActivation)

function ManualRefueling:updateLoadTriggersColMask()
    for _, station in pairs(g_currentMission.storageSystem:getLoadingStations()) do
        for _, loadTrigger in pairs(station.loadTriggers) do
            for i, _ in pairs(loadTrigger.fillTypes) do
                if (i == g_fillTypeManager:getFillTypeIndexByName("DIESEL")) or (i == g_fillTypeManager:getFillTypeIndexByName("ELECTRICCHARGE")) or (i == g_fillTypeManager:getFillTypeIndexByName("METHANE")) then
                    local collisionMask = getCollisionMask(loadTrigger.triggerNode)

                    if collisionMask == ManualRefueling.OLD_TRIGGER_COLMASK then
                        setCollisionMask(loadTrigger.triggerNode, ManualRefueling.NEW_TRIGGER_COLMASK)

                        loadTrigger.isManual = true
                    elseif collisionMask == ManualRefueling.OLD_TRIGGER_COLMASK2 then
                        setCollisionMask(loadTrigger.triggerNode, ManualRefueling.NEW_TRIGGER_COLMASK2)

                        loadTrigger.isManual = true
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