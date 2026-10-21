-- Recovery tool for when the normal per-entity Undo can no longer find anything to undo - most commonly
-- because the "Absolutes_Laboratory_Mutations" entity variable that Undo depends on (holding exactly what
-- was changed and what to put back) got wiped, e.g. by fully uninstalling Absolute's Laboratory itself
-- while mutated entities existed in the save, then reloading.
--
-- Rather than relying on that per-entity record, this walks every Mutation in a chosen Folder (e.g. a
-- config mod's own folder, like "Cahoot's" folder) and works out every Passive/Status/Spell that folder's
-- mutators COULD have granted - loose entries plus anything hand-authored in the Lists they reference,
-- recursively through linked Lists - then checks every currently-loaded character directly against that
-- set and strips whatever's actually present. It does not try to reconstruct exactly what was applied to
-- a given entity (that would require replaying the same randomness Lab used, which isn't reproducible) -
-- it takes the safer, broader "does this character currently have anything this config could have given
-- them" approach instead.
--
-- Scope, intentionally: this only covers PassiveList/StatusList/SpellList mutators. Ability/Health/Level/
-- ClassesAndSubclasses/Equipment/Boosts/ActionResources/Progressions/PrepPhaseMarker mutators overwrite
-- values rather than adding something removable by name, so there's no safe way to detect or revert them
-- without the lost record. It also can't restore Spells a config REMOVED from a character (no record of
-- what those were), and doesn't walk vanilla class-progression auto-population, only hand-authored List
-- entries and their linked Lists - see ForceCleanWindow.lua for how this is presented to the user.
--
-- Both the List-resolution step and the per-entity scan are deliberately defensive about running time:
-- Lists can be shared/linked from many different Mutations (a class-conversion Folder like "Ranger" links
-- every subclass variant back into that class's shared vanilla spell pool, for example), and the per-entity
-- scan can cover a lot of characters on a busy level - see the comments on visitedByType/visitBudget below
-- and CleanCurrentLevelAsync's batching for why, after this used to be able to hang the game for a very
-- long time on exactly this kind of Folder.

ForceCleanUtility = {
	---@type boolean?
	running = nil,
}

-- Hard ceiling on how many distinct Lists a single ResolveCandidatesForFolder call will walk, across every
-- Mutation in the Folder combined. Existing purely as a circuit breaker - a well-formed Folder should never
-- get remotely close to this - so that a pathological or unexpectedly large/deeply-linked List web produces
-- a logged warning and a partial (rather than a folder that never finishes resolving).
local MAX_LIST_VISITS = 3000

-- How many characters get processed per game tick during the actual clean-up pass. Kept deliberately small -
-- this is a one-off recovery tool, not a hot path, so there's no reason to push it - the goal is just to
-- never block the game for more than a fraction of a second at a time, however large the level is.
local ENTITIES_PER_BATCH = 15

---@class ForceCleanCandidates
---@field passives {[string]: boolean}
---@field statuses {[string]: boolean}
---@field spells {[string]: boolean}

---@param listType "passiveLists"|"statusLists"|"spellLists"
---@param listId Guid
---@param candidateSet {[string]: boolean}
---@param visited {[Guid]: boolean} Shared across the WHOLE folder resolution for this listType - see ResolveCandidatesForFolder.
---@param visitBudget {count: integer, warned: boolean?}
local function collectListEntries(listType, listId, candidateSet, visited, visitBudget)
	if visited[listId] then
		return
	end

	if visitBudget.count >= MAX_LIST_VISITS then
		if not visitBudget.warned then
			visitBudget.warned = true
			Logger:BasicWarning(
				"Force Clean: hit the %d-list safety cap while resolving %s - stopping early with whatever was found so far. This usually means a very large or deeply cross-linked set of Lists; results may be incomplete.",
				MAX_LIST_VISITS, listType)
		end
		return
	end
	visitBudget.count = visitBudget.count + 1

	visited[listId] = true

	local lists = MutationConfigurationProxy.lists and MutationConfigurationProxy.lists[listType]
	local list = lists and lists[listId]
	if not list then
		return
	end
	list = list.__real or list

	if list.levels then
		for _, levelEntry in pairs(list.levels) do
			if levelEntry and levelEntry.manuallySelectedEntries then
				for _, entry in pairs(levelEntry.manuallySelectedEntries) do
					local name = type(entry) == "string" and entry or (entry and entry.name)
					if name then
						candidateSet[name] = true
					end
				end
			end
			-- Intentionally not walking levelEntry.linkedProgressions (vanilla class-progression
			-- auto-population) here - see the header comment/ForceCleanWindow for why.
		end
	end

	if list.linkedLists then
		for _, linkedId in pairs(list.linkedLists) do
			collectListEntries(listType, linkedId, candidateSet, visited, visitBudget)
		end
	end
end

---@param mutation Mutation
---@param candidates ForceCleanCandidates
---@param visitedByType {passiveLists: table, statusLists: table, spellLists: table}
---@param visitBudget {count: integer, warned: boolean?}
local function collectMutationCandidates(mutation, candidates, visitedByType, visitBudget)
	if not mutation.mutators then
		return
	end

	for _, mutator in pairs(mutation.mutators) do
		if mutator.targetProperty == "PassiveList" and mutator.values then
			if mutator.values.passives then
				for _, entry in pairs(mutator.values.passives) do
					local name = type(entry) == "string" and entry or (entry and entry.name)
					if name then
						candidates.passives[name] = true
					end
				end
			end
			if mutator.values.passiveLists then
				for _, listId in pairs(mutator.values.passiveLists) do
					collectListEntries("passiveLists", listId, candidates.passives, visitedByType.passiveLists, visitBudget)
				end
			end
		elseif mutator.targetProperty == "StatusList" and mutator.values then
			if mutator.values.statuses then
				for _, entry in pairs(mutator.values.statuses) do
					local name = type(entry) == "string" and entry or (entry and entry.name)
					if name then
						candidates.statuses[name] = true
					end
				end
			end
			if mutator.values.statusLists then
				for _, listId in pairs(mutator.values.statusLists) do
					collectListEntries("statusLists", listId, candidates.statuses, visitedByType.statusLists, visitBudget)
				end
			end
		elseif mutator.targetProperty == "SpellList" then
			if mutator.looseSpells then
				for _, entry in pairs(mutator.looseSpells) do
					local name = type(entry) == "string" and entry or (entry and entry.name)
					if name then
						candidates.spells[name] = true
					end
				end
			end
			if mutator.values then
				for _, group in pairs(mutator.values) do
					if group.leveledSpellPool then
						for _, pool in pairs(group.leveledSpellPool) do
							if pool.spells then
								for _, entry in pairs(pool.spells) do
									local name = type(entry) == "string" and entry or (entry and entry.name)
									if name then
										candidates.spells[name] = true
									end
								end
							end
							if pool.spellLists then
								for _, listId in pairs(pool.spellLists) do
									collectListEntries("spellLists", listId, candidates.spells, visitedByType.spellLists, visitBudget)
								end
							end
						end
					end
				end
			end
		end
	end
end

---@param folderId Guid
---@return ForceCleanCandidates?, string?
function ForceCleanUtility:ResolveCandidatesForFolder(folderId)
	local folder = MutationConfigurationProxy.folders and MutationConfigurationProxy.folders[folderId]
	if not folder then
		return nil, "Couldn't find that Mutation Folder - it may have been removed."
	end

	---@type ForceCleanCandidates
	local candidates = { passives = {}, statuses = {}, spells = {} }

	-- Shared per-listType across every Mutation in this Folder (rather than a fresh {} per reference,
	-- which is what this used to do) - a List referenced from several different Mutations, or from several
	-- subclass variants within one Mutation, now only ever gets walked once for the whole Folder instead of
	-- once per reference. Without this, a class-conversion Folder (where every subclass links back into
	-- that class's shared vanilla spell pool) could redundantly re-walk the same large List web dozens of
	-- times over, which is what let a single Force Clean run hang for a very long time.
	local visitedByType = { passiveLists = {}, statusLists = {}, spellLists = {} }
	local visitBudget = { count = 0 }

	if folder.mutations then
		for _, mutation in pairs(folder.mutations) do
			collectMutationCandidates(mutation, candidates, visitedByType, visitBudget)
		end
	end

	return candidates, nil
end

--- Broadcasts a progress snapshot through the same status window Apply/Undo Mutations Now use, so Force
--- Clean shows the same "this is running, don't move" box instead of silently locking up the UI. Reuses
--- action = "Undo" since Force Clean is, functionally, an undo - MutationExecutionStatusWindow.lua renders
--- that as "Undoing Mutations" / "Entities Undone" without needing any changes on the client side.
---@param stage "Starting"|"Running"|"Complete"|"Error"
---@param processed integer
---@param total integer
---@param startTime integer
local function broadcastForceCleanStatus(stage, processed, total, startTime)
	if ConfigurationStructure.config.mutations.settings.profileExecution.statusView == "Off" then
		return
	end

	Channels.MutationExecutionStatus:Broadcast({
		action = "Undo",
		stage = stage,
		processed = processed,
		total = total,
		timeElapsed = math.floor(Ext.Timer.MonotonicTime() - startTime),
	})
end

--- Walks every ServerCharacter on the current level in small batches, spread one batch per game tick, so
--- this can never again block the whole game for an extended stretch no matter how many characters/
--- candidates are involved - see ENTITIES_PER_BATCH above. Entities are snapshotted by UUID up front and
--- re-fetched per batch (mirroring MutationProfileExecutor's own pipeline) so one disappearing mid-run
--- (e.g. dying, or a scripted despawn) is just skipped rather than erroring the whole run.
---@param candidates ForceCleanCandidates
---@param onComplete fun(entitiesCleaned: integer, passivesRemoved: integer, statusesRemoved: integer, spellsRemoved: integer)
function ForceCleanUtility:CleanCurrentLevelAsync(candidates, onComplete)
	local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level
	local spellSystem = Ext.System.ServerSpell
	local startTime = Ext.Timer.MonotonicTime()

	---@type Guid[]
	local entityIds = {}
	for _, entity in pairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
		if entity.ServerCharacter.Level == currentLevel then
			table.insert(entityIds, entity.Uuid.EntityUuid)
		end
	end

	local total = #entityIds
	local index = 0
	local entitiesCleaned, passivesRemoved, statusesRemoved, spellsRemoved = 0, 0, 0, 0

	-- Forward-declared so step() (defined first, for readability) can call scheduleStep() below it.
	local scheduleStep

	---@param entity EntityHandle
	---@return boolean touchedThisEntity
	local function processEntity(entity)
		local touchedThisEntity = false

		if next(candidates.passives) and entity.PassiveContainer then
			for _, passiveEntity in pairs(entity.PassiveContainer.Passives) do
				local passiveId = passiveEntity.Passive.PassiveId
				if candidates.passives[passiveId] then
					Logger:BasicDebug("Force Clean: removing passive %s from %s", passiveId, EntityRecorder:GetEntityName(entity))
					Osi.RemovePassive(entity.Uuid.EntityUuid, passiveId)
					passivesRemoved = passivesRemoved + 1
					touchedThisEntity = true
				end
			end
		end

		-- Iterates the entity's OWN (usually short) list of active statuses and checks each one against the
		-- candidate set, rather than the other way around (iterating every candidate status and asking the
		-- engine "does this entity have it" via a separate Osiris round-trip each time) - same pattern the
		-- spell removal below already uses. A Folder with a large candidate status set (easy to end up with
		-- once linked Lists cross into other loaded mods' own Lists) could otherwise mean thousands of
		-- Osi.HasActiveStatus calls per entity, which is real, cumulative cost across a whole level.
		if next(candidates.statuses) and entity.ServerCharacter and entity.ServerCharacter.StatusManager then
			local statusesToRemove = {}
			for _, status in pairs(entity.ServerCharacter.StatusManager.Statuses) do
				if status.StatusId and candidates.statuses[status.StatusId] then
					table.insert(statusesToRemove, status.StatusId)
				end
			end
			for _, statusId in pairs(statusesToRemove) do
				Logger:BasicDebug("Force Clean: removing status %s from %s", statusId, EntityRecorder:GetEntityName(entity))
				Osi.RemoveStatus(entity.Uuid.EntityUuid, statusId)
				statusesRemoved = statusesRemoved + 1
				touchedThisEntity = true
			end
		end

		if next(candidates.spells) and entity.SpellBook then
			local removedSpellNames = {}

			for _, spell in pairs(entity.SpellBook.Spells) do
				local spellId = spell.Id.OriginatorPrototype
				if candidates.spells[spellId] then
					spellSystem.RemoveSpell[entity] = spellSystem.RemoveSpell[entity] or {}
					table.insert(spellSystem.RemoveSpell[entity], spell.Id)
					table.insert(removedSpellNames, spellId)
					spellsRemoved = spellsRemoved + 1
					touchedThisEntity = true

					Logger:BasicDebug("Force Clean: removing spell %s from %s", spellId, EntityRecorder:GetEntityName(entity))
				end
			end

			-- Mirrors MutatorInterface's real undo behavior: a removed spell may have left a
			-- persistent buff status behind (on the entity itself or its equipped weapon), since
			-- those statuses don't disappear just because the spell that cast them is now gone.
			if next(removedSpellNames) then
				local statusesToRemove = {}
				for _, status in pairs(entity.ServerCharacter.StatusManager.Statuses) do
					if status.SourceSpell
						and status.SourceSpell.SourceType == "Osiris"
						and TableUtils:IndexOf(removedSpellNames, status.SourceSpell.OriginatorPrototype)
					then
						table.insert(statusesToRemove, status.StatusId)
					end
				end
				for _, statusId in pairs(statusesToRemove) do
					Osi.RemoveStatus(entity.Uuid.EntityUuid, statusId)
					statusesRemoved = statusesRemoved + 1
				end

				local weapon = Osi.GetEquippedWeapon(entity.Uuid.EntityUuid)
				if weapon then
					weapon = Ext.Entity.Get(weapon)
					if weapon and weapon.ServerItem then
						local weaponStatusesToRemove = {}
						for _, status in pairs(weapon.ServerItem.StatusManager.Statuses) do
							if status.SourceSpell
								and status.SourceSpell.SourceType == "Osiris"
								and TableUtils:IndexOf(removedSpellNames, status.SourceSpell.OriginatorPrototype)
							then
								table.insert(weaponStatusesToRemove, status.StatusId)
							end
						end
						for _, statusId in pairs(weaponStatusesToRemove) do
							Osi.RemoveStatus(weapon.Uuid.EntityUuid, statusId)
							statusesRemoved = statusesRemoved + 1
						end
					end
				end
			end
		end

		if touchedThisEntity then
			Ext.System.ServerStats.ReloadStats[entity] = true
		end

		return touchedThisEntity
	end

	local function step()
		local processedThisBatch = 0
		while index < total and processedThisBatch < ENTITIES_PER_BATCH do
			index = index + 1
			local entity = Ext.Entity.Get(entityIds[index])
			-- Entities that ceased to exist mid-run (died, despawned, etc.) are simply skipped. Also
			-- pcall-wrapped: this used to be able to hit an unexpected nil somewhere on one oddly-shaped
			-- entity (a malformed passive slot, a spell with no OriginatorPrototype, etc.), throw, and
			-- silently kill this whole tick chain forever - leaving the status box stuck mid-run with no
			-- error ever shown and no result ever delivered. One bad entity should never be able to do that
			-- again; it's now just logged and skipped like a despawned one would be.
			if entity then
				local ok, touchedOrErr = pcall(processEntity, entity)
				if ok then
					if touchedOrErr then
						entitiesCleaned = entitiesCleaned + 1
					end
				else
					Logger:BasicError("Force Clean: error processing %s - skipping this entity and continuing: %s",
						EntityRecorder:GetEntityName(entity), touchedOrErr)
				end
			end
			processedThisBatch = processedThisBatch + 1
		end

		broadcastForceCleanStatus("Running", index, total, startTime)

		if index < total then
			Ext.Timer.WaitFor(1, scheduleStep)
		else
			broadcastForceCleanStatus("Complete", index, total, startTime)
			onComplete(entitiesCleaned, passivesRemoved, statusesRemoved, spellsRemoved)
		end
	end

	-- Belt-and-suspenders around step() itself, on top of the pcall around each individual entity above -
	-- if anything in here throws for a reason that isn't one specific entity's data, this still guarantees
	-- the status box gets an Error state and the client gets SOME reply instead of hanging indefinitely.
	scheduleStep = function()
		local ok, err = pcall(step)
		if not ok then
			Logger:BasicError("Force Clean: unexpected error during the clean-up pass, stopping here: %s", err)
			broadcastForceCleanStatus("Error", index, total, startTime)
			onComplete(entitiesCleaned, passivesRemoved, statusesRemoved, spellsRemoved)
		end
	end

	broadcastForceCleanStatus("Starting", 0, total, startTime)
	scheduleStep()
end

-- One-way trigger + a separate ForceCleanResult reply, rather than a synchronous request/reply - the actual
-- clean-up pass is now spread across ticks (see CleanCurrentLevelAsync), so it can't return its result
-- immediately the way a plain SetRequestHandler expects. This mirrors how "Apply Mutations Now"/"Undo
-- Mutations Now" already report back via Channels.MutationExecutionStatus rather than a direct reply.
Channels.ForceCleanByFolder:SetHandler(function(folderId, user)
	if ForceCleanUtility.running then
		Channels.ForceCleanResult:SendToClient({ error = "A Force Clean is already running - wait for it to finish." }, user)
		return
	end

	if MutationProfileExecutor.running or MutationProfileExecutor.runningUndo then
		Channels.ForceCleanResult:SendToClient({ error = "A Mutation Profile Apply/Undo is currently running - wait for it to finish, then try again." }, user)
		return
	end

	ForceCleanUtility.running = true

	local candidates, resolveError = ForceCleanUtility:ResolveCandidatesForFolder(folderId)
	if not candidates then
		ForceCleanUtility.running = nil
		Channels.ForceCleanResult:SendToClient({ error = resolveError }, user)
		return
	end

	Logger:BasicInfo("Force Clean: starting for folder %s - %d candidate passive(s), %d status(es), %d spell(s)",
		folderId,
		TableUtils:CountElements(candidates.passives),
		TableUtils:CountElements(candidates.statuses),
		TableUtils:CountElements(candidates.spells))

	ForceCleanUtility:CleanCurrentLevelAsync(candidates, function(entitiesCleaned, passivesRemoved, statusesRemoved, spellsRemoved)
		Logger:BasicInfo("Force Clean: finished - touched %d entities, removed %d passive(s), %d status(es), %d spell(s)",
			entitiesCleaned, passivesRemoved, statusesRemoved, spellsRemoved)

		ForceCleanUtility.running = nil

		Channels.ForceCleanResult:SendToClient({
			entitiesCleaned = entitiesCleaned,
			passivesRemoved = passivesRemoved,
			statusesRemoved = statusesRemoved,
			spellsRemoved = spellsRemoved
		}, user)
	end)
end)
