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



LosingAnimals = {}; -- Class

-- global variables
LosingAnimals.dir = g_currentModDirectory
LosingAnimals.modName = g_currentModName

-- configuration
LosingAnimals.noFoodDyingRate = 25
LosingAnimals.noFoodDyingWaitingHours = 6

LosingAnimals.noHealthDyingRate = 3
LosingAnimals.noHealthDyingWaitingHours = 2

LosingAnimals.riskAgeDyingRate = 2
LosingAnimals.riskAgeDyingWaitingHours = 1
-- LosingAnimals.riskAnimalAgeInMonths = {HORSE=200, PIG=120, COW=160, SHEEP=80, CHICKEN=80}
LosingAnimals.riskAnimalAgeInMonths = {HORSE=60, PIG=60, COW=60, SHEEP=60, CHICKEN=60}	-- currently the maximum age of animals in FS22 is 60 months/5 years

LosingAnimals.warningWaitingHours = 8
LosingAnimals.hourForAction = 5		-- each first day in period

-- for the routine
LosingAnimals.numHoursAfterLastWarning = 99
LosingAnimals.clusterNumHoursWithNoHealth = {}	-- {cluster, numHours}
LosingAnimals.clusterNumHoursWithoutFood = {}	-- {cluster, numHours}


function LosingAnimals:loadMap(name)
    dbPrintHeader("LosingAnimals:loadMap()")

	g_messageCenter:subscribe(MessageType.HOUR_CHANGED, LosingAnimals.onHourChanged, LosingAnimals)
	-- g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    -- g_messageCenter:subscribe(MessageType.HUSBANDRY_ANIMALS_CHANGED, self.onHusbandryAnimalsChanged, self)
end


function LosingAnimals:onHourChanged(hour)
	dbPrintHeader("LosingAnimals:onHourChanged")
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

			local sumNumLosingAnimalsForAge = 0
			local sumNumLosingAnimalsForHealh = 0
			local sumNumLosingAnimalsForFood = 0

			for idx, cluster in ipairs(placeable:getClusters()) do
				dbPrintf("    - Cluster:  numAnimals=%s | age=%s | health=%s | subTypeName=%s | subTypeTitle=%s"
				, cluster.numAnimals, cluster.age, cluster.health, g_currentMission.animalSystem.subTypes[cluster.subTypeIndex].name, g_currentMission.animalSystem.subTypes[cluster.subTypeIndex].visuals[1].store.name)

				-- check age
				local riskAnimalAge = LosingAnimals.riskAnimalAgeInMonths[husbandry.animalTypeName]
				if cluster.age >= riskAnimalAge then
					isWarning = true

					-- Let some animals die
					if LosingAnimals.hourForAction == hour then
						-- local riskFactor = 100 / LosingAnimals.riskAnimalAgeInMonths[husbandry.animalTypeName] * (cluster.age - riskAnimalAge + 1)
						-- local numDeadAnimals = LosingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, LosingAnimals.riskAgeDyingRate * riskFactor / g_currentMission.environment.daysPerPeriod)
						local numDeadAnimals = LosingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, LosingAnimals.riskAgeDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumLosingAnimalsForAge = sumNumLosingAnimalsForAge + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for age", numDeadAnimals)
						end
					end
				end

				-- check health
				if cluster.health < 25 then
					isWarning = true
					if LosingAnimals.clusterNumHoursWithNoHealth[cluster] == nil then
						LosingAnimals.clusterNumHoursWithNoHealth[cluster] = 1					
					else
						LosingAnimals.clusterNumHoursWithNoHealth[cluster] = LosingAnimals.clusterNumHoursWithNoHealth[cluster] + 1
					end

					-- Let some animals die
					if LosingAnimals.clusterNumHoursWithNoHealth[cluster] >= LosingAnimals.noHealthDyingWaitingHours and LosingAnimals.hourForAction == hour then
						local numDeadAnimals = LosingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, LosingAnimals.noHealthDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumLosingAnimalsForHealh = sumNumLosingAnimalsForHealh + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for health", numDeadAnimals)
						end
					end
				else
					LosingAnimals.clusterNumHoursWithNoHealth[cluster] = 0					
				end

				-- check food
				if totalFood < 0.1 then
					isWarning = true
					if LosingAnimals.clusterNumHoursWithoutFood[cluster] == nil then
						LosingAnimals.clusterNumHoursWithoutFood[cluster] = 1					
					else
						LosingAnimals.clusterNumHoursWithoutFood[cluster] = LosingAnimals.clusterNumHoursWithoutFood[cluster] + 1
					end

					-- Let some animals die
					if LosingAnimals.clusterNumHoursWithoutFood[cluster] >= LosingAnimals.noFoodDyingWaitingHours and LosingAnimals.hourForAction == hour then
						local numDeadAnimals = LosingAnimals:probabilityCalculationNumOfHits(cluster.numAnimals, LosingAnimals.noFoodDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumLosingAnimalsForFood = sumNumLosingAnimalsForFood + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for food", numDeadAnimals)
						end
					end
					
				else
					LosingAnimals.clusterNumHoursWithoutFood[cluster] = 0					
				end
				
				-- clean up
				if cluster.numAnimals <= 0 then
					table.remove(placeable:getClusters(), idx)
				end
			end

			if sumNumLosingAnimalsForAge > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_ageDyingMsg"), placeableName, sumNumLosingAnimalsForAge, LosingAnimals:getAnimalTitle(husbandry.animalTypeName, sumNumLosingAnimalsForAge > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				LosingAnimals.numHoursAfterLastWarning = 0
			end

			if sumNumLosingAnimalsForHealh > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_healthDyingMsg"), placeableName, sumNumLosingAnimalsForHealh, LosingAnimals:getAnimalTitle(husbandry.animalTypeName, sumNumLosingAnimalsForHealh > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				LosingAnimals.numHoursAfterLastWarning = 0
			end
				
			if sumNumLosingAnimalsForFood > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_foodDyingMsg"), placeableName, sumNumLosingAnimalsForFood, LosingAnimals:getAnimalTitle(husbandry.animalTypeName, sumNumLosingAnimalsForFood > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				LosingAnimals.numHoursAfterLastWarning = 0
			end
		end
	end

	-- display warning when no action has been taken but potential animals would have died
	if isWarning and not isDyingNotification and LosingAnimals.numHoursAfterLastWarning >= LosingAnimals.warningWaitingHours then
		LosingAnimals.numHoursAfterLastWarning = 0
		local msgTxt = g_i18n:getText("txt_riskInfoMsg")
		dbPrintf("  --> " .. msgTxt)
		g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, msgTxt)
	else
		LosingAnimals.numHoursAfterLastWarning = LosingAnimals.numHoursAfterLastWarning + 1
	end
end


function LosingAnimals:probabilityCalculationNumOfHits(numOfTrials, proability)
	local numOfHits = 0

    for i=1, numOfTrials do
        local randomNumber = math.random(10000)
        if randomNumber <= (proability * 100) then
            numOfHits = numOfHits + 1
        end
    end

    return numOfHits
end


function LosingAnimals:getAnimalTitle(animalTypeName, isPlural)
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


function LosingAnimals:registerActionEvents()end
function LosingAnimals:onLoad(savegame)end
function LosingAnimals:onUpdate(dt)end
function LosingAnimals:deleteMap()end
function LosingAnimals:keyEvent(unicode, sym, modifier, isDown)end
function LosingAnimals:mouseEvent(posX, posY, isDown, isUp, button)end

addModEventListener(LosingAnimals)