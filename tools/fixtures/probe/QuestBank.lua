
QuestBankDB = {
	["disc"] = {
		["v"] = 1,
		["q"] = {
			[7] = {
				["t"] = "Kobold Camp Cleanup",
				["lv"] = 2,
				["min"] = 2,
				["xp"] = {
					["3"] = 250,
					["2"] = 250,
				},
				["paid"] = 1,
				["from"] = {
					"c197", -- [1]
				},
				["to"] = {
					"c197", -- [1]
				},
			},
			[15] = {
				["t"] = "Investigate Echo Ridge",
				["lv"] = 3,
				["min"] = 3,
				["xp"] = {
					["3b"] = 340,
				},
				["from"] = {
					"c197", -- [1]
				},
				["g"] = 0,
			},
			[2158] = {
				["t"] = "Rest and Relaxation",
				["xp"] = {
				},
				["from"] = {
					"i1000", -- [1]
					"c823", -- [2]
				},
			},
		},
		["npc"] = {
			["c197"] = {
				["n"] = "Marshal McBride",
				["p"] = {
					"1429:48.2,42.1", -- [1]
					"1429:48.3,42.0", -- [2]
				},
			},
			["c823"] = {
				["n"] = "Deputy Willem",
				["p"] = {
					"1429:48.9,40.1", -- [1]
				},
			},
		},
		["offer"] = {
			["c197"] = {
				[7] = 2,
				[15] = 3,
			},
		},
		["chain"] = {
			["7>15"] = true,
		},
		["item"] = {
			[1000] = 2158,
		},
		["build"] = "70058",
		["ver"] = "3.3.2",
	},
	["errors"] = {
	},
	["settings"] = {
		["shareParty"] = true,
		["arrow"] = false,
		["escaped"] = "He said \"hi\"\\n|cffffffffwhite|r",
		["neg"] = -1.5,
		["big"] = 1e+15,
	},
}
