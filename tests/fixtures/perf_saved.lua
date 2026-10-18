UnitFramesDB = {
	global = {
		perfSuiteReport = {
			status = "completed", timestamp = 1792356815, skipped = {},
			context = {
				client = { version = "1.60.1", build = "70450" }, version = "dev", commit = "unknown",
				profile = "Performance fixture", groupSize = 0, raid = false, workbenchShown = false, loadedAddons = { "UnitFrames" },
			},
			operations = {
				{ name = "clickgrid", samples = { {} }, counters = { resolveCall = 2301, resolveBuild = 539 },
					timeMS = { median = 285.554, maximum = 320.207 }, allocatedBytes = { median = 14031667.2, maximum = 14226841.6 } },
			},
		},
		perfMeasurements = {
			["measure clickgrid"] = {
				timestamp = 1792356829, ms = 283.138, allocatedBytes = 14049080, deallocatedBytes = 6278216,
				counters = { resolveCall = 2301, resolveBuild = 539 },
				phases = {
					{ name = "resolve", ms = 57.874, bytes = 2921779.2, calls = 2301 },
					{ name = "decoration reflow", ms = 30.673, bytes = 0, calls = 816 },
					{ name = "bind tags", ms = 14.820, bytes = 4837376, calls = 180 },
				},
			},
		},
	},
	profiles = { private = "unrelated profile data" },
}
UnitFramesLogs = { entries = { "unrelated log data" } }
