
ForeverProbeDB = {
	["meta"] = {
		["addon"] = "0.4.0",
		["lastExport"] = "2026-09-30T15:00:00Z",
		["errors"] = {
		},
	},
	["snapshots"] = {
		{
			["at"] = "2026-09-30T14:00:00Z",
			["why"] = "login",
			["char"] = "Helga-Forever Normal",
			["name"] = "Helga",
			["class"] = "PALADIN",
			["race"] = "Dwarf",
			["level"] = 20,
			["xpMax"] = 23200,
			["build"] = "70058",
			["interface"] = 16001,
			["zone"] = "Stormwind City",
			["spells"] = {
				635, -- [1]
				20594, -- [2]
			},
			["items"] = {
				2361, -- [1]
				45, -- [2]
			},
		}, -- [1]
		{
			["at"] = "2026-09-30T14:40:00Z",
			["why"] = "levelup",
			["char"] = "Helga-Forever Normal",
			["name"] = "Helga",
			["class"] = "PALADIN",
			["race"] = "Dwarf",
			["level"] = 21,
			["xpMax"] = 25200,
			["build"] = "70058",
			["interface"] = 16001,
			["spells"] = {
				635, -- [1]
				20271, -- [2]
				20594, -- [3]
			},
			["items"] = {
				2361, -- [1]
				45, -- [2]
				2589, -- [3]
			},
		}, -- [2]
		{
			["at"] = "2026-09-30T14:50:00Z",
			["why"] = "login",
			["class"] = "WARRIOR",
			["race"] = "Human",
			["level"] = 4,
			["xpMax"] = 2100,
			["interface"] = 11507,
			["spells"] = {
				6673, -- [1]
			},
			["items"] = {
				25, -- [1]
			},
		}, -- [3]
	},
	["items"] = {
		[2361] = {
			["b"] = "70170",
			["at"] = 1759240000,
			["lc"] = "enUS",
			["n"] = "Battleworn Hammer",
			["q"] = 1,
			["l"] = 2,
			["r"] = 1,
			["el"] = "INVTYPE_2HWEAPON",
			["c"] = 2,
			["u"] = 4,
			["ic"] = 133052,
			["x"] = {
				"Two-Hand\tMace", -- [1]
				"5 - 10 Damage\tSpeed 2.90", -- [2]
			},
		},
		[2589] = {
			["b"] = "70170",
			["at"] = 1759240100,
			["lc"] = "enGB",
			["n"] = "Linen Cloth",
			["q"] = 1,
			["l"] = 5,
			["c"] = 7,
			["u"] = 5,
			["ic"] = 132889,
			["x"] = {
				"Sell Price: 13c", -- [1]
			},
		},
		[2590] = {
			["b"] = "70170",
			["at"] = 1759240100,
			["lc"] = "enGB",
			["n"] = "Wool Cloth",
			["q"] = 1,
			["l"] = 15,
			["c"] = 7,
			["u"] = 5,
			["ic"] = 132890,
			["x"] = {
			},
		},
	},
	["trainers"] = {
		{
			["npc"] = "Brother Sammuel",
			["zone"] = "Elwynn Forest",
			["at"] = "2026-09-30T14:30:00Z",
			["chars"] = {
				["Helga-Forever Normal"] = 1759242600,
			},
			["services"] = {
				{
					["n"] = "Seal of Righteousness",
					["r"] = "Rank 3",
					["lvl"] = 18,
					["c"] = 300,
					["t"] = "unavailable",
				}, -- [1]
				{
					["n"] = "Holy Light",
					["r"] = "Rank 4",
					["lvl"] = 22,
					["c"] = 600,
					["t"] = "unavailable",
				}, -- [2]
				{
					["n"] = "Blessing of Might",
					["r"] = "Rank 2",
					["lvl"] = 12,
					["c"] = 100,
					["t"] = "available",
				}, -- [3]
				{
					["n"] = "Plate Mail",
					["r"] = "",
					["lvl"] = 40,
					["c"] = 18000,
					["t"] = "unavailable",
				}, -- [4]
			},
		}, -- [1]
		{
			["npc"] = "Tomas",
			["zone"] = "Elwynn Forest",
			["at"] = "2026-09-30T14:35:00Z",
			["chars"] = {
				["Helga-Forever Normal"] = 1759242900,
			},
			["services"] = {
				{
					["n"] = "Spiced Wolf Meat",
					["r"] = "",
					["lvl"] = 0,
					["c"] = 100,
					["t"] = "available",
				}, -- [1]
			},
		}, -- [2]
	},
	["questbank"] = {
		["at"] = 1759240800,
		["version"] = "3.3.2",
		["build"] = "70058",
		["disc"] = {
			["v"] = 1,
			["q"] = {
				[7] = {
					["t"] = "Kobold Camp Cleanup",
					["xp"] = {
						["3"] = 260,
					},
					["to"] = {
						"c197", -- [1]
					},
				},
				[176] = {
					["t"] = "Wanted: \"Hogger\"",
					["lv"] = 10,
					["min"] = 9,
					["xp"] = {
						["11"] = 850,
					},
					["from"] = {
						"o19",
					},
				},
			},
			["npc"] = {
				["c197"] = {
					["n"] = "Marshal McBride",
					["p"] = {
						"1429:48.2,42.1", -- [1]
					},
				},
			},
			["offer"] = {
			},
			["chain"] = {
				["7>15"] = true,
				["15>18"] = true,
			},
			["item"] = {
			},
			["build"] = "70058",
			["ver"] = "3.3.2",
		},
	},
}
