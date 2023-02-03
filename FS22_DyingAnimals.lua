-- Author: Fetty42
-- Date: 28.11.2022
-- Version: 1.0.0.0

local dbPrintfOn = false
local dbInfoPrintfOn = true

local function dbInfoPrintf(...)
	if dbInfoPrintfOn then
    	print(string.format(...))
	end
end

local function dbPrintf(...)
	if dbPrintfOn then
    	print(string.format(...))
	end
end

local function dbPrintHeader(ftName)
	if dbPrintfOn then
    	print(string.format("Call %s: g_currentMission:getIsServer()=%s | g_currentMission:getIsClient()=%s", ftName, g_currentMission:getIsServer(), g_currentMission:getIsClient()))
	end
end



DyingAnimals = {}; -- Class

-- global variables
DyingAnimals.dir = g_currentModDirectory
DyingAnimals.modName = g_currentModName

-- configuration
DyingAnimals.noFoodDyingRate = 25
DyingAnimals.noFoodDyingWaitingHours = 6

DyingAnimals.noHealthDyingRate = 3
DyingAnimals.noHealthDyingWaitingHours = 2

DyingAnimals.riskAgeDyingRate = 2
DyingAnimals.riskAgeDyingWaitingHours = 1
-- DyingAnimals.riskAnimalAgeInMonths = {HORSE=200, PIG=120, COW=160, SHEEP=80, CHICKEN=80}
DyingAnimals.riskAnimalAgeInMonths = {HORSE=60, PIG=60, COW=60, SHEEP=60, CHICKEN=60}	-- currently the maximum age of animals in FS22 is 60 months/5 years

DyingAnimals.warningWaitingHours = 8
DyingAnimals.hourForAction = 5		-- each first day in period

-- for the routine
DyingAnimals.numHoursAfterLastWarning = 99
DyingAnimals.clusterNumHoursWithNoHealth = {}	-- {cluster, numHours}
DyingAnimals.clusterNumHoursWithoutFood = {}	-- {cluster, numHours}


function DyingAnimals:loadMap(name)
    dbPrintHeader("DyingAnimals:loadMap()")

	g_messageCenter:subscribe(MessageType.HOUR_CHANGED, DyingAnimals.onHourChanged, DyingAnimals)
	-- g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    -- g_messageCenter:subscribe(MessageType.HUSBANDRY_ANIMALS_CHANGED, self.onHusbandryAnimalsChanged, self)
end


function DyingAnimals:onHourChanged(hour)
	dbPrintHeader("DyingAnimals:onHourChanged")
	dbPrintf("  parameter=%s", hour)
	
	-- check each cluster for healthy and food
	local farmId = g_currentMission.player.farmId;
	local isWarning = false
	local isDyingNotification = false
	for _,husbandry in pairs(g_currentMission.husbandrySystem.clusterHusbandries) do
		local placeable = husbandry:getPlaceable()
		if placeable.ownerFarmId == farmId then
			local placeableName = placeable:getName()
			local totalFood = placeable:getTotalFood()

			dbPrintf("  - husbandry placeables:  Name=%s | AnimalType=%s | NumOfAnimals=%s | TotalFood=%s | getNumOfClusters=%s"
				, placeableName, husbandry.animalTypeName, placeable:getNumOfAnimals(), totalFood, placeable:getNumOfClusters())

			local sumNumDyingAnimalsForAge = 0
			local sumNumDyingAnimalsForHealh = 0
			local sumNumDyingAnimalsForFood = 0

			for idx, cluster in ipairs(placeable:getClusters()) do
				dbPrintf("    - Cluster:  numAnimals=%s | age=%s | health=%s | subTypeName=%s | subTypeTitle=%s"
				, cluster.numAnimals, cluster.age, cluster.health, g_currentMission.animalSystem.subTypes[cluster.subTypeIndex].name, g_currentMission.animalSystem.subTypes[cluster.subTypeIndex].visuals[1].store.name)

				-- check age
				local riskAnimalAge = DyingAnimals.riskAnimalAgeInMonths[husbandry.animalTypeName]
				if cluster.age >= riskAnimalAge then
					isWarning = true

					-- Let some animals die
					if DyingAnimals.hourForAction == hour then
						-- local riskFactor = 100 / DyingAnimals.riskAnimalAgeInMonths[husbandry.animalTypeName] * (cluster.age - riskAnimalAge + 1)
						-- local numDeadAnimals = DyingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, DyingAnimals.riskAgeDyingRate * riskFactor / g_currentMission.environment.daysPerPeriod)
						local numDeadAnimals = DyingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, DyingAnimals.riskAgeDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumDyingAnimalsForAge = sumNumDyingAnimalsForAge + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for age", numDeadAnimals)
						end
					end
				end

				-- check health
				if cluster.health < 25 then
					isWarning = true
					if DyingAnimals.clusterNumHoursWithNoHealth[cluster] == nil then
						DyingAnimals.clusterNumHoursWithNoHealth[cluster] = 1					
					else
						DyingAnimals.clusterNumHoursWithNoHealth[cluster] = DyingAnimals.clusterNumHoursWithNoHealth[cluster] + 1
					end

					-- Let some animals die
					if DyingAnimals.clusterNumHoursWithNoHealth[cluster] >= DyingAnimals.noHealthDyingWaitingHours and DyingAnimals.hourForAction == hour then
						local numDeadAnimals = DyingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, DyingAnimals.noHealthDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumDyingAnimalsForHealh = sumNumDyingAnimalsForHealh + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for health", numDeadAnimals)
						end
					end
				else
					DyingAnimals.clusterNumHoursWithNoHealth[cluster] = 0					
				end

				-- check food
				if totalFood < 0.1 then
					isWarning = true
					if DyingAnimals.clusterNumHoursWithoutFood[cluster] == nil then
						DyingAnimals.clusterNumHoursWithoutFood[cluster] = 1					
					else
						DyingAnimals.clusterNumHoursWithoutFood[cluster] = DyingAnimals.clusterNumHoursWithoutFood[cluster] + 1
					end

					-- Let some animals die
					if DyingAnimals.clusterNumHoursWithoutFood[cluster] >= DyingAnimals.noFoodDyingWaitingHours and DyingAnimals.hourForAction == hour then
						local numDeadAnimals = DyingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, DyingAnimals.noFoodDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumDyingAnimalsForFood = sumNumDyingAnimalsForFood + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for food", numDeadAnimals)
						end
					end
					
				else
					DyingAnimals.clusterNumHoursWithoutFood[cluster] = 0					
				end
				
				-- clean up
				if cluster.numAnimals <= 0 then
					table.remove(placeable:getClusters(), idx)
				end
			end

			if sumNumDyingAnimalsForAge > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_ageDyingMsg"), placeableName, sumNumDyingAnimalsForAge, DyingAnimals:getAnimalTitle(husbandry.animalTypeName, sumNumDyingAnimalsForAge > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				DyingAnimals.numHoursAfterLastWarning = 0
			end

			if sumNumDyingAnimalsForHealh > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_healthDyingMsg"), placeableName, sumNumDyingAnimalsForHealh, DyingAnimals:getAnimalTitle(husbandry.animalTypeName, sumNumDyingAnimalsForHealh > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				DyingAnimals.numHoursAfterLastWarning = 0
			end
				
			if sumNumDyingAnimalsForFood > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_foodDyingMsg"), placeableName, sumNumDyingAnimalsForFood, DyingAnimals:getAnimalTitle(husbandry.animalTypeName, sumNumDyingAnimalsForFood > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				DyingAnimals.numHoursAfterLastWarning = 0
			end
		end
	end

	-- display warning when no action has been taken but potential animals would have died
	if isWarning and not isDyingNotification and DyingAnimals.numHoursAfterLastWarning >= DyingAnimals.warningWaitingHours then
		DyingAnimals.numHoursAfterLastWarning = 0
		local msgTxt = g_i18n:getText("txt_riskInfoMsg")
		dbPrintf("  --> " .. msgTxt)
		g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, msgTxt)
	else
		DyingAnimals.numHoursAfterLastWarning = DyingAnimals.numHoursAfterLastWarning + 1
	end
end


function DyingAnimals:probabilityCalculationNumOfHits(numOfTrials, proability)
	local numOfHits = 0

    for i=1, numOfTrials do
        local randomNumber = math.random(10000)
        if randomNumber <= (proability * 100) then
            numOfHits = numOfHits + 1
        end
    end

    return numOfHits
end


function DyingAnimals:getAnimalTitle(animalTypeName, isPlural)
	local singular = "animal"
	local plural = "animals"
	
	if animalTypeName == "HORSE" then
		singular, plural = string.match(g_i18n:getText("txt_horse"), "([^,]+),([^,]+)")
	elseif animalTypeName == "PIG" then
		singular, plural = string.match(g_i18n:getText("txt_pig"), "([^,]+),([^,]+)")
	elseif animalTypeName == "COW" then
		singular, plural = string.match(g_i18n:getText("txt_cow"), "([^,]+),([^,]+)")
	elseif animalTypeName == "SHEEP" then
		singular, plural = string.match(g_i18n:getText("txt_sheep"), "([^,]+),([^,]+)")
	elseif animalTypeName == "CHICKEN" then
		singular, plural = string.match(g_i18n:getText("txt_chicken"), "([^,]+),([^,]+)")
	end

	local animalTitle = isPlural and plural or singular
	return animalTitle
end


function DyingAnimals:registerActionEvents()end
function DyingAnimals:onLoad(savegame)end
function DyingAnimals:onUpdate(dt)end
function DyingAnimals:deleteMap()end
function DyingAnimals:keyEvent(unicode, sym, modifier, isDown)end
function DyingAnimals:mouseEvent(posX, posY, isDown, isUp, button)end

addModEventListener(DyingAnimals)