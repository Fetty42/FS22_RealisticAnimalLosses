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



RealisticAnimalLosses = {}; -- Class

-- global variables
RealisticAnimalLosses.dir = g_currentModDirectory
RealisticAnimalLosses.modName = g_currentModName

-- configuration
RealisticAnimalLosses.noFoodDyingRate = 25
RealisticAnimalLosses.noFoodDyingWaitingHours = 6

RealisticAnimalLosses.noHealthDyingRate = 3
RealisticAnimalLosses.noHealthDyingWaitingHours = 2

RealisticAnimalLosses.riskAgeDyingRate = 2
RealisticAnimalLosses.riskAgeDyingWaitingHours = 1
-- RealisticAnimalLosses.riskAnimalAgeInMonths = {HORSE=200, PIG=120, COW=160, SHEEP=80, CHICKEN=80}
RealisticAnimalLosses.riskAnimalAgeInMonths = {HORSE=60, PIG=60, COW=60, SHEEP=60, CHICKEN=60}	-- currently the maximum age of animals in FS22 is 60 months/5 years

RealisticAnimalLosses.warningWaitingHours = 8
RealisticAnimalLosses.hourForAction = 5		-- each first day in period

-- for the routine
RealisticAnimalLosses.numHoursAfterLastWarning = 99
RealisticAnimalLosses.clusterNumHoursWithNoHealth = {}	-- {cluster, numHours}
RealisticAnimalLosses.clusterNumHoursWithoutFood = {}	-- {cluster, numHours}


function RealisticAnimalLosses:loadMap(name)
    dbPrintHeader("RealisticAnimalLosses:loadMap()")

	g_messageCenter:subscribe(MessageType.HOUR_CHANGED, RealisticAnimalLosses.onHourChanged, RealisticAnimalLosses)
	-- g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    -- g_messageCenter:subscribe(MessageType.HUSBANDRY_ANIMALS_CHANGED, self.onHusbandryAnimalsChanged, self)
end


function RealisticAnimalLosses:onHourChanged(hour)
	dbPrintHeader("RealisticAnimalLosses:onHourChanged")
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

			local sumNumRealisticAnimalLossesForAge = 0
			local sumNumRealisticAnimalLossesForHealh = 0
			local sumNumRealisticAnimalLossesForFood = 0

			for idx, cluster in ipairs(placeable:getClusters()) do
				dbPrintf("    - Cluster:  numAnimals=%s | age=%s | health=%s | subTypeName=%s | subTypeTitle=%s"
				, cluster.numAnimals, cluster.age, cluster.health, g_currentMission.animalSystem.subTypes[cluster.subTypeIndex].name, g_currentMission.animalSystem.subTypes[cluster.subTypeIndex].visuals[1].store.name)

				-- check age
				local riskAnimalAge = RealisticAnimalLosses.riskAnimalAgeInMonths[husbandry.animalTypeName]
				if cluster.age >= riskAnimalAge then
					isWarning = true

					-- Let some animals die
					if RealisticAnimalLosses.hourForAction == hour then
						-- local riskFactor = 100 / RealisticAnimalLosses.riskAnimalAgeInMonths[husbandry.animalTypeName] * (cluster.age - riskAnimalAge + 1)
						-- local numDeadAnimals = RealisticAnimalLosses:probabilityCalculationNumOfHits(cluster.numAnimals, RealisticAnimalLosses.riskAgeDyingRate * riskFactor / g_currentMission.environment.daysPerPeriod)
						local numDeadAnimals = RealisticAnimalLosses:probabilityCalculationNumOfHits(cluster.numAnimals, RealisticAnimalLosses.riskAgeDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumRealisticAnimalLossesForAge = sumNumRealisticAnimalLossesForAge + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for age", numDeadAnimals)
						end
					end
				end

				-- check health
				if cluster.health < 25 then
					isWarning = true
					if RealisticAnimalLosses.clusterNumHoursWithNoHealth[cluster] == nil then
						RealisticAnimalLosses.clusterNumHoursWithNoHealth[cluster] = 1					
					else
						RealisticAnimalLosses.clusterNumHoursWithNoHealth[cluster] = RealisticAnimalLosses.clusterNumHoursWithNoHealth[cluster] + 1
					end

					-- Let some animals die
					if RealisticAnimalLosses.clusterNumHoursWithNoHealth[cluster] >= RealisticAnimalLosses.noHealthDyingWaitingHours and RealisticAnimalLosses.hourForAction == hour then
						local numDeadAnimals = RealisticAnimalLosses:probabilityCalculationNumOfHits(cluster.numAnimals, RealisticAnimalLosses.noHealthDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumRealisticAnimalLossesForHealh = sumNumRealisticAnimalLossesForHealh + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for health", numDeadAnimals)
						end
					end
				else
					RealisticAnimalLosses.clusterNumHoursWithNoHealth[cluster] = 0					
				end

				-- check food
				if totalFood < 0.1 then
					isWarning = true
					if RealisticAnimalLosses.clusterNumHoursWithoutFood[cluster] == nil then
						RealisticAnimalLosses.clusterNumHoursWithoutFood[cluster] = 1					
					else
						RealisticAnimalLosses.clusterNumHoursWithoutFood[cluster] = RealisticAnimalLosses.clusterNumHoursWithoutFood[cluster] + 1
					end

					-- Let some animals die
					if RealisticAnimalLosses.clusterNumHoursWithoutFood[cluster] >= RealisticAnimalLosses.noFoodDyingWaitingHours and RealisticAnimalLosses.hourForAction == hour then
						local numDeadAnimals = RealisticAnimalLosses:probabilityCalculationNumOfHits(cluster.numAnimals, RealisticAnimalLosses.noFoodDyingRate / g_currentMission.environment.daysPerPeriod)
						if numDeadAnimals > 0 then
							cluster.numAnimals = cluster.numAnimals - numDeadAnimals
							sumNumRealisticAnimalLossesForFood = sumNumRealisticAnimalLossesForFood + numDeadAnimals
							dbPrintf("    --> Cluster: %s aminals dying for food", numDeadAnimals)
						end
					end
					
				else
					RealisticAnimalLosses.clusterNumHoursWithoutFood[cluster] = 0					
				end
				
				-- clean up
				if cluster.numAnimals <= 0 then
					table.remove(placeable:getClusters(), idx)
				end
			end

			if sumNumRealisticAnimalLossesForAge > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_ageDyingMsg"), placeableName, sumNumRealisticAnimalLossesForAge, RealisticAnimalLosses:getAnimalTitle(husbandry.animalTypeName, sumNumRealisticAnimalLossesForAge > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				RealisticAnimalLosses.numHoursAfterLastWarning = 0
			end

			if sumNumRealisticAnimalLossesForHealh > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_healthDyingMsg"), placeableName, sumNumRealisticAnimalLossesForHealh, RealisticAnimalLosses:getAnimalTitle(husbandry.animalTypeName, sumNumRealisticAnimalLossesForHealh > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				RealisticAnimalLosses.numHoursAfterLastWarning = 0
			end
				
			if sumNumRealisticAnimalLossesForFood > 0 then
				local msgTxt = string.format(g_i18n:getText("txt_foodDyingMsg"), placeableName, sumNumRealisticAnimalLossesForFood, RealisticAnimalLosses:getAnimalTitle(husbandry.animalTypeName, sumNumRealisticAnimalLossesForFood > 1))
				dbPrintf("  --> " .. msgTxt)
				g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msgTxt)
				isDyingNotification = true
				RealisticAnimalLosses.numHoursAfterLastWarning = 0
			end
		end
	end

	-- display warning when no action has been taken but potential animals would have died
	if isWarning and not isDyingNotification and RealisticAnimalLosses.numHoursAfterLastWarning >= RealisticAnimalLosses.warningWaitingHours then
		RealisticAnimalLosses.numHoursAfterLastWarning = 0
		local msgTxt = g_i18n:getText("txt_riskInfoMsg")
		dbPrintf("  --> " .. msgTxt)
		g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, msgTxt)
	else
		RealisticAnimalLosses.numHoursAfterLastWarning = RealisticAnimalLosses.numHoursAfterLastWarning + 1
	end
end


function RealisticAnimalLosses:probabilityCalculationNumOfHits(numOfTrials, proability)
	local numOfHits = 0

    for i=1, numOfTrials do
        local randomNumber = math.random(10000)
        if randomNumber <= (proability * 100) then
            numOfHits = numOfHits + 1
        end
    end

    return numOfHits
end


function RealisticAnimalLosses:getAnimalTitle(animalTypeName, isPlural)
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


function RealisticAnimalLosses:registerActionEvents()end
function RealisticAnimalLosses:onLoad(savegame)end
function RealisticAnimalLosses:onUpdate(dt)end
function RealisticAnimalLosses:deleteMap()end
function RealisticAnimalLosses:keyEvent(unicode, sym, modifier, isDown)end
function RealisticAnimalLosses:mouseEvent(posX, posY, isDown, isUp, button)end

addModEventListener(RealisticAnimalLosses)