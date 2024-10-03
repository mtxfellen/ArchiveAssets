::__potato.MapFixes <- {
	// == GENERIC REUSABLE FIXES ==

	/**
	 * Indiscriminately sets kRenderTransColor on all func_respawnroomvisualizers.
	 *
	 * This fixes the issue where sometimes the entity texture will incorrectly render
	 * behind entities that are spatially behind it relative to the player.
	 */
	function FixAllVisualizers() {
		for (local vis; vis = Entities.FindByClassname(vis, "func_respawnroomvisualizer");)
			NetProps.SetPropInt(vis, "m_nRenderMode", Constants.ERenderMode.kRenderTransColor)
		RegisterFix("Added rendermode 1 to func_respawnroomvisualizer.")
	}

	/**
	 * Indiscriminately disables all bone followers on the map.
	 *
	 * Bone followers are used for server-side physics calculations on some entities
	 * with collision models set. However, they have various undesireable side effects.
	 * Of these side effects, the ones that concern us are:
	 *  - Large demo file sizes.
	 *  - Heavy entity traffic (poor networking performance).
	 *  - Counting toward the edict limit (multiple are generated per collision model).
	 * As such, we force them off on some maps that do not use them sparingly.
	 */
	function DisableAllBoneFollowers() {
		local parents = []
		for (local follower; follower = Entities.FindByClassname(follower, "phys_bone_follower");) {
			local parent = follower.GetOwner()
			if (parent && parents.find(parent) == null) {
				// DisableBoneFollowers on Owner entities fixes network/demo issues.
				parents.push(parent)
				parent.KeyValueFromInt("DisableBoneFollowers", 1)
				NetProps.SetPropInt(parent,
					"m_BoneFollowerManager.m_iNumBones", 0)
			}
			// Kill the bone followers to free up edicts.
			EntFireByHandle(follower, "Kill", null, -1, null, null)
		}

		RegisterFix("Added DisableBoneFollowers 1 to prop_dynamic and (monster/npc)_furniture.")
	}

	/**
	 * Fixes a bug with func_rotating entities where they will max out at a 360,000 degree
	 * rotation and freeze in place.
	 */
	function FixFuncRotating() {
		for (local e; e = Entities.FindByClassname(e, "func_rotating");) {
			// Try not to interfere with map/mission scripts.
			if (e.GetScriptThinkFunc() != "") continue

			e.ValidateScriptScope()
			e.GetScriptScope().MaxAnglesFix <- function() {
				local angles = self.GetLocalAngles()
				foreach (rot, angle in angles) {
					if (angle < 359640.0) continue	// 359640 = 360k - 360
					angles.rot %= 360.0
				}
				self.SetLocalAngles(angles)
				return 1.0
			}
			AddThinkToEnt(e, "MaxAnglesFix")
		}

		RegisterFix("Added uncapped rotation script to func_rotating.")
	}

	/**
	 * Creates a func_forcefield that blocks players filtered by team.
	 * Will allow bullets and projectiles to pass.
	 * Used to patch up some holes in world geometry.
	 *
	 * @param Vector p1     One corner of the forcefield cuboid.
	 * @param Vector p2     Opposite corner of the forcefield cuboid.
	 * @param int team?     Team of the forcefield to allow passing (Default: SPEC).
	 * @return handle       EHANDLE of the forcefield.
	 */
	function MakeForceField(p1, p2, team = Constants.ETFTeam.TEAM_SPECTATOR) {
		local ent = Entities.CreateByClassname("func_forcefield")
		SetupAABBox(ent, p1, p2)
		ent.SetTeam(team)
		return ent
	}

	/**
	 * Creates a func_nobuild that blocks building placement.
	 * Automatically extends the brush ±96 units on all sides of where you want to block
	 * buildings, as nobuilds only block the centre of buildings when placing them.
	 *
	 * @param Vector p1     One corner of the nobuild cuboid.
	 * @param Vector p2     Opposite corner of the nobuild cuboid.
	 * @param bool resize?	Set to false to disable automatically extending the brush.
	 * @return handle       EHANDLE of the nobuild.
	 */
	function MakeNoBuild(p1, p2, resize = true) {
		local ent = Entities.CreateByClassname("func_nobuild")
		SetupAABBox(ent, p1, p2)

		if (!resize)
			return ent
		ent.SetSize(
			Vector(-96, -96, -96),
			ent.GetBoundingMaxs() + Vector(96, 96, 96)
		)
		ent.AddSolidFlags(Constants.FSolid.FSOLID_NOT_SOLID)
		return ent
	}

	/**
	 * Modifies a brush entity to become an axis-aligned bounding entity between two absolute
	 * points.
	 * If you need to DispatchSpawn() a brush, call it before this function.
	 *
	 * @param Vector p1     One corner of the brush cuboid.
	 * @param Vector p2     Opposite corner of the brush cuboid.
	 * @return handle       EHANDLE of the brush.
	 */
	function SetupAABBox(ent, p1, p2) {
		// Suppress ent console spam; without a brush model they cannot render anyway.
		NetProps.SetPropInt(ent, "m_nRenderMode", Constants.ERenderMode.kRenderNone)

		// Bounding brushes need a (non-brush) model or else collision with them will
		//  result in client prediction errors.
		ent.SetModel("models/empty.mdl")

		// Convert two spatial points to absolute origin and local maxs.
		// Recall that maxs must be greater than the origin, or the server will crash.
		local origin = Vector(
			min(p1.x, p2.x),
			min(p1.y, p2.y),
			min(p1.z, p2.z)
		)
		local maxs = Vector(
			max(p1.x, p2.x) - origin.x,
			max(p1.y, p2.y) - origin.y,
			max(p1.z, p2.z) - origin.z
		)
		ent.SetAbsOrigin(origin)
		NetProps.SetPropVector(ent, "m_Collision.m_vecMaxsPreScaled", maxs)
		ent.SetSize(Vector(), maxs)
		ent.SetSolid(Constants.ESolidType.SOLID_BBOX)

		return ent
	}

	// == TESTING SERVER PRINT FUNCTIONS ==

	/**
	 * Registers a map fix description for printing.
	 *
	 * @param str desc      Array containing a string description of the map fix applied.
	 *                      Will fail if it exceeds 255 chars in length.
	 */
	Descriptions = []
	function RegisterFix(desc)
		if (desc.len() < 256)
			Descriptions.push(desc)

	/**
	 * Prints the map fixes applied on the map to player consoles on first mission
	 * load.
	 */
	function PrintMapFixes() {
		if (!TestingServer) return
		if (Descriptions.len() == 0)
			return

		ClientPrint(null, Constants.EHudNotify.HUD_PRINTCONSOLE,
			"\n\n== " + MapName + ": VScript map fixes have been applied. ==\nIf you are the map maker, you may wish to consider implementing these changes directly in your map:\n")

		foreach (fix in Descriptions)
			ClientPrint(null, Constants.EHudNotify.HUD_PRINTCONSOLE, " - " + fix + "\n")
		ClientPrint(null, Constants.EHudNotify.HUD_PRINTCONSOLE, "\n")
	}
	// Call PrintMapFixes() once for every map on first mission load.
	BaseEvents = {
		function OnGameEvent_recalculate_holidays(_) {
			if (GetRoundState() != Constants.ERoundState.GR_STATE_PREROUND) return
			// Fire on a delay to avoid a code race.
			EntFireByHandle(::__potato.hWorldspawn,
				"RunScriptCode", "::__potato.MapFixes.PrintMapFixes()",
			0.5, null, null)
			delete ::__potato.MapFixes.BaseEvents
		}
	}

	// == UTIL ==
	function min(a, b) return a < b ? a : b
	function max(a, b) return a > b ? a : b
}
::__potato.MapFixes.setdelegate(::__potato)
__CollectGameEventCallbacks(::__potato.MapFixes.BaseEvents)

// Map fixes are split in to separate files as "potato/map_fixes/<MapName>.nut"
try
	DoIncludeScript("potato/map_fixes/" + ::__potato.MapName + ".nut", ::__potato.MapFixes)
catch (e) {
	if (e != "Failed to include script \"potato/map_fixes/" + ::__potato.MapName + ".nut\"")
	throw e
}

// The "Events" table in the relevant file is collected here.
if ("Events" in ::__potato.MapFixes) {
	::__potato.MapFixes.Events.setdelegate(::__potato.MapFixes)
	__CollectGameEventCallbacks(::__potato.MapFixes.Events)
}

// The "RunOnce" function is called once map entities load.
if ("RunOnce" in ::__potato.MapFixes)
	EntFireByHandle(::__potato.hWorldspawn,
		"RunScriptCode", "::__potato.MapFixes.RunOnce()",
	-1, null, null)
