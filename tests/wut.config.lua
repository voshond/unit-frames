-- wow-ui-testing runner config (see the library's README, "Configuring wowtest").
return {
	specs = { { dir = "tests/spec/" } },
	path = { "./tests/?.lua" },
	syntax = {
		include = { "UnitFrames", "UnitFrames_Workbench", "UnitFrames_ClickGrid", "UnitFrames_Onboarding" },
		exclude = { "*/Libs/*" },
	},
}
