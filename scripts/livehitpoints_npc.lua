--
--	Please see the LICENSE.md file included with this distribution for attribution and copyright information.
--
--
--	NPC Specific Data Acquisition Functions
--
---	This function checks NPCs for feats, traits, and/or special abilities.
--	luacheck: no unused args
local function hasSpecialAbility(nodeActor, sSearchString, bFeat, bTrait, bSpecialAbility)
	if not nodeActor then return false; end

	local sLowerSpecAbil = string.lower(sSearchString);
	local sSpecialQualities = string.lower(DB.getValue(nodeActor, '.specialqualities', ''));
	local sSpecAtks = string.lower(DB.getValue(nodeActor, '.specialattacks', ''));
	local sFeats = string.lower(DB.getValue(nodeActor, '.feats', ''));

	if bFeat and sFeats:match(sLowerSpecAbil, 1) then
		local nRank = tonumber(sFeats:match(sLowerSpecAbil .. ' (%d+)', 1));
		return true, (nRank or 1);
	elseif bSpecialAbility and (sSpecAtks:match(sLowerSpecAbil, 1) or sSpecialQualities:match(sLowerSpecAbil, 1)) then
		local nRank = tonumber(sSpecAtks:match(sLowerSpecAbil .. ' (%d+)', 1) or sSpecialQualities:match(sLowerSpecAbil .. ' (%d+)', 1));
		return true, (nRank or 1);
	end

	return false
end

---	This function reports if the HD information is entered incorrectly.
--	It alerts the user and suggests that they report it on the bug report thread.
local function reportHdErrors(nodeNPC, sHd)
	local sError = ''
	local sHdErrorEnd = string.find(sHd, '%)', 1)
	if not sHdErrorEnd then sHdErrorEnd = string.find(sHd, '%;', 1) end
	if not sHdErrorEnd then sHdErrorEnd = string.find(sHd, 'planar', 1) end
	if not sHdErrorEnd then sHdErrorEnd = string.find(sHd, 'profane', 1) end
	if not sHdErrorEnd then sHdErrorEnd = string.find(sHd, 'sacred', 1) end
	if string.find(sHd, 'regeneration', 1) then sError = 'regeneration' end
	if string.find(sHd, 'fast-healing', 1) then sError = 'fast healing' end
	if string.find(sHd, 'fast healing', 1) then sError = 'fast healing' end

	local bErrorAlerted = (DB.getValue(nodeNPC, 'erroralerted') == 1)
	local sNpcName = DB.getValue(nodeNPC, 'name', '')
	if (sNpcName ~= '') and sHdErrorEnd and DataCommon.isPFRPG() and not bErrorAlerted then
		ChatManager.SystemMessage(string.format(Interface.getString('npc_hd_error_pf1e'), sNpcName))
		if (sError ~= '') then ChatManager.SystemMessage(string.format(Interface.getString('npc_hd_error_type'), sError, sError)) end
		DB.setValue(nodeNPC, 'erroralerted', 'number', 1)
	elseif (sNpcName ~= '') and sHdErrorEnd and not bErrorAlerted then
		ChatManager.SystemMessage(string.format(Interface.getString('npc_hd_error_generic'), sNpcName))
		if (sError ~= '') then ChatManager.SystemMessage(string.format(Interface.getString('npc_hd_error_type'), sError, sError)) end
		DB.setValue(nodeNPC, 'erroralerted', 'number', 1)
	end
end

---	This function finds the total number of HD for the NPC.
--	luacheck: globals processHd
function processHd(nodeNPC)
	local sHd = DB.getValue(nodeNPC, 'hd', '')

	-- remove potential hit dice 'total'
	-- Paizo uses format of "10 HD; 5d6+5d6+10" sometimes
	-- FG only understands this if trimmed to "5d6+5d6+10"
	sHd = string.gsub(sHd, '%d+%s-HD%;', '')

	reportHdErrors(nodeNPC, sHd)

	sHd = sHd .. '+' -- ending plus
	local tHd = {} -- table to collect fields
	local fieldstart = 1
	repeat
		local nexti = string.find(sHd, '+', fieldstart)
		table.insert(tHd, string.sub(sHd, fieldstart, nexti - 1))
		fieldstart = nexti + 1
	until fieldstart > string.len(sHd)

	local nAbilHp = 0

	if (tHd == {}) or (tHd[1] == '') then return nAbilHp, 0 end

	local nHdCount = 0
	for _, v in ipairs(tHd) do
		if string.find(v, 'd', 1) then
			local nHdEndPos = string.find(v, 'd', 1)
			local nHd = tonumber(string.sub(v, 1, nHdEndPos - 1))
			if nHd then nHdCount = nHdCount + nHd end
		elseif not string.match(v, '%D', 1) then
			nAbilHp = nAbilHp + v
		end
	end

	return nAbilHp, nHdCount
end

local function getFeatBonusHp(nodeNPC, rActor, nLevel)
	local nFeatBonus = 0
	if DataCommon.isPFRPG() then
		if hasSpecialAbility(nodeNPC, 'Toughness %(Mythic%)', true) then
			return nFeatBonus + ((math.max(nLevel, 3)) * 2)
		elseif hasSpecialAbility(nodeNPC, 'Toughness', true) then
			return nFeatBonus + math.max(nLevel, 3)
		end
	else
		if hasSpecialAbility(nodeNPC, 'Toughness', true) then nFeatBonus = nFeatBonus + 3 end
		if hasSpecialAbility(nodeNPC, 'Improved Toughness', true) then nFeatBonus = nFeatBonus + nLevel end
		return nFeatBonus
	end
	return 0
end

local function upgradeNpc(nodeNPC, rActor, nLevel, nCalculatedAbilHp, nHdAbilHp, bOnAdd)
	local nHpTotal = DB.getValue(nodeNPC, 'hp', 0)

	-- house rule compatibility for rolling NPC hitpoints or using max
	local sHD = StringManager.trim(DB.getValue(nodeNPC, 'hd', ''))
	if bOnAdd then
		local sOptHRNH = OptionsManager.getOption('HRNH');
		if sOptHRNH == 'max' and sHD ~= '' then
			sHD = string.gsub(sHD, '%d+%s-HD%;', '')
			nHpTotal = DiceManager.evalDiceString(sHD, true, true)
		elseif sOptHRNH == 'random' and sHD ~= '' then
			sHD = string.gsub(sHD, '%d+%s-HD%;', '')
			nHpTotal = math.max(DiceManager.evalDiceString(sHD, true), 1)
		end
	end

	local nRolledHp = nHpTotal - nHdAbilHp
	local nMiscMod = nHdAbilHp - nCalculatedAbilHp - getFeatBonusHp(nodeNPC, rActor, nLevel)

	DB.setValue(nodeNPC, 'livehp.rolled', 'number', nRolledHp)
	DB.setValue(nodeNPC, 'livehp.misc', 'number', nMiscMod)
end

--
--	Set NPC HP
--

--	luacheck: globals setHpTotal
function setHpTotal(rActor, bOnAdd)
	local nodeNPC = ActorManager.getCreatureNode(rActor)
	local nHdAbilHp, nLevel = processHd(nodeNPC)

	local function getAbilityBonusUsed(nAbilHp)

		local function constructSizeBonus(sType)
			if sType:find('small') then
				return 10
			elseif sType:find('medium') then
				return 20
			elseif sType:find('large') then
				return 30
			elseif sType:find('huge') then
				return 40
			elseif sType:find('gargantuan') then
				return 60
			elseif sType:find('colossal') then
				return 80
			else
				return 0
			end
		end

		local nAbilModOverride, nBonus
		local sAbility = DB.getValue(nodeNPC, 'livehp.abilitycycler', '')
		if sAbility == '' then
			local sType = string.lower(DB.getValue(nodeNPC, 'type', ''))
			if string.find(sType, 'undead', 1) and DataCommon.isPFRPG() then
				sAbility = 'charisma'
				DB.setValue(nodeNPC, 'livehp.abilitycycler', 'string', sAbility)
			elseif string.find(sType, 'construct', 1) and DataCommon.isPFRPG() then
				nAbilModOverride = 0
				nBonus = constructSizeBonus(sType)
			elseif sType ~= '' then
				sAbility = 'constitution'
				DB.setValue(nodeNPC, 'livehp.abilitycycler', 'string', sAbility)
			else
				sAbility = 'constitution'
			end
		end

		local nAbilityMod = nAbilModOverride or math.floor((DB.getValue(nodeNPC, sAbility, 0) - 10) / 2)
		local nEffectBonus = math.floor((EffectManager35EDS.getEffectsBonus(rActor, { DataCommon.ability_ltos[sAbility] }, true) or 0) / 2)

		if bOnAdd or not DB.getValue(nodeNPC, 'livehp.total') then
			upgradeNpc(nodeNPC, rActor, nLevel, (nAbilityMod * nLevel) or 0, nAbilHp, bOnAdd)
		end

		return (((nAbilityMod + nEffectBonus) * nLevel) + nBonus) or 0
	end

	local nTotalHp = LiveHP.calculateHp(nodeNPC, rActor, getAbilityBonusUsed(nHdAbilHp), getFeatBonusHp(nodeNPC, rActor, nLevel or 0))

	DB.setValue(nodeNPC, 'hp', 'number', nTotalHp)
end

--
--	Triggering Functions
--

---	This function is called when effect components are changed.
--	First, it makes sure the triggering actor is not a PC and that the effect is relevant to this extension.
--	Then, it calls the calculateHp function in LiveHP and provides it with nodeActor and rActor.
local function onEffectChanged(node)
	local rActor = ActorManager.resolveActor(node.getChild('....'))
	if not ActorManager.isPC(rActor) and LiveHP.checkEffectRelevance(node.getChild('..')) then setHpTotal(rActor) end
end

---	This function is called when effects are removed.
--	It calls the calculateHp function in LiveHP and provides it with nodeActor and rActor.
local function onEffectRemoved(node)
	local rActor = ActorManager.resolveActor(node.getChild('..'))
	if not ActorManager.isPC(rActor) then setHpTotal(rActor) end
end

---	This function watches for changes in the database and triggers various functions.
--	It only runs on the host machine.
function onInit()

	---	This function is called when NPCs are added to the combat tracker.
	--	First, it calls the original addNPC function.
	--	Then, it recalculates the hitpoints after the NPC has been added.
	local addNPC_old -- placeholder for original addNPC function
	local function addNPC_new(tCustom, ...)
		addNPC_old(tCustom, ...) -- call original function

		-- calculate hitpoints immediately upon adding NPC to prevent changes mid-encounter from random/max house rule options
		if OptionsManager.getOption('HRNH') ~= 'off' then
			local bOnAdd = true
			setHpTotal(ActorManager.resolveActor(tCustom['nodeCT']), bOnAdd)
		end
	end

	addNPC_old = CombatRecordManager.addNPC
	CombatRecordManager.addNPC = addNPC_new


	if Session.IsHost then
		DB.addHandler(DB.getPath(CombatManager.CT_COMBATANT_PATH .. '.effects.*.label'), 'onUpdate', onEffectChanged)
		DB.addHandler(DB.getPath(CombatManager.CT_COMBATANT_PATH .. '.effects.*.isactive'), 'onUpdate', onEffectChanged)
		DB.addHandler(DB.getPath(CombatManager.CT_COMBATANT_PATH .. '.effects'), 'onChildDeleted', onEffectRemoved)
	end
end
