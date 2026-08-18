--[[
    GM Tools v1.0.4 - Command Definitions
    All GM commands organized by category with argument type metadata.

    Argument types -> ImGui widget mapping:
        int    -> InputInt
        float  -> InputFloat
        string -> InputText
        select -> Combo (references a lookup table by name)
        bool   -> Checkbox
        (none) -> Execute button only

    Permission levels (perm field, default = 1 if omitted):
        0 = Any player (no GM required)
        1 = GM (basic)
        2 = GM (elevated)
        3 = Admin
        4 = Super Admin
        5 = Developer/Owner
]]--

require 'common';

local commands = {};

-------------------------------------------------------------------------------
-- Lookup tables for combo/select dropdowns
-------------------------------------------------------------------------------

commands.jobs = T{
    { id = 1,  name = 'WAR' }, { id = 2,  name = 'MNK' }, { id = 3,  name = 'WHM' },
    { id = 4,  name = 'BLM' }, { id = 5,  name = 'RDM' }, { id = 6,  name = 'THF' },
    { id = 7,  name = 'PLD' }, { id = 8,  name = 'DRK' }, { id = 9,  name = 'BST' },
    { id = 10, name = 'BRD' }, { id = 11, name = 'RNG' }, { id = 12, name = 'SAM' },
    { id = 13, name = 'NIN' }, { id = 14, name = 'DRG' }, { id = 15, name = 'SMN' },
    { id = 16, name = 'BLU' }, { id = 17, name = 'COR' }, { id = 18, name = 'PUP' },
    { id = 19, name = 'DNC' }, { id = 20, name = 'SCH' }, { id = 21, name = 'GEO' },
    { id = 22, name = 'RUN' },
};

commands.zones = T{
    -- === Cities: San d'Oria ===
    { id = 230, name = 'Southern San d\'Oria' },
    { id = 231, name = 'Northern San d\'Oria' },
    { id = 232, name = 'Port San d\'Oria' },
    { id = 233, name = 'Chateau d\'Oraguille' },
    -- === Cities: Bastok ===
    { id = 234, name = 'Bastok Mines' },
    { id = 235, name = 'Bastok Markets' },
    { id = 236, name = 'Port Bastok' },
    { id = 237, name = 'Metalworks' },
    -- === Cities: Windurst ===
    { id = 238, name = 'Windurst Waters' },
    { id = 239, name = 'Windurst Walls' },
    { id = 240, name = 'Port Windurst' },
    { id = 241, name = 'Windurst Woods' },
    { id = 242, name = 'Heaven\'s Tower' },
    -- === Cities: Jeuno ===
    { id = 243, name = 'Ru\'Lude Gardens' },
    { id = 244, name = 'Upper Jeuno' },
    { id = 245, name = 'Lower Jeuno' },
    { id = 246, name = 'Port Jeuno' },
    -- === Cities: Other Towns ===
    { id = 247, name = 'Rabao' },
    { id = 248, name = 'Selbina' },
    { id = 249, name = 'Mhaura' },
    { id = 250, name = 'Kazham' },
    { id = 251, name = 'Hall of the Gods' },
    { id = 252, name = 'Norg' },
    { id = 26,  name = 'Tavnazian Safehold' },
    -- === Cities: Aht Urhgan ===
    { id = 48,  name = 'Al Zahbi' },
    { id = 50,  name = 'Aht Urhgan Whitegate' },
    { id = 53,  name = 'Nashmau' },
    -- === Cities: Adoulin ===
    { id = 256, name = 'Western Adoulin' },
    { id = 257, name = 'Eastern Adoulin' },
    -- === Special / GM ===
    { id = 210, name = 'GM Home' },
    { id = 131, name = 'Mordion Gaol' },
    { id = 280, name = 'Mog Garden' },
    -- === Overworld: Ronfaure / San d'Oria Region ===
    { id = 100, name = 'West Ronfaure' },
    { id = 101, name = 'East Ronfaure' },
    { id = 102, name = 'La Theine Plateau' },
    { id = 104, name = 'Jugner Forest' },
    { id = 105, name = 'Batallia Downs' },
    -- === Overworld: Gustaberg / Bastok Region ===
    { id = 106, name = 'North Gustaberg' },
    { id = 107, name = 'South Gustaberg' },
    { id = 108, name = 'Konschtat Highlands' },
    { id = 109, name = 'Pashhow Marshlands' },
    { id = 110, name = 'Rolanberry Fields' },
    -- === Overworld: Sarutabaruta / Windurst Region ===
    { id = 115, name = 'West Sarutabaruta' },
    { id = 116, name = 'East Sarutabaruta' },
    { id = 117, name = 'Tahrongi Canyon' },
    { id = 118, name = 'Buburimu Peninsula' },
    { id = 119, name = 'Meriphataud Mountains' },
    { id = 120, name = 'Sauromugue Champaign' },
    -- === Overworld: Shared / Neutral ===
    { id = 103, name = 'Valkurm Dunes' },
    { id = 111, name = 'Beaucedine Glacier' },
    { id = 112, name = 'Xarcabard' },
    { id = 113, name = 'Cape Teriggan' },
    { id = 114, name = 'Eastern Altepa Desert' },
    { id = 121, name = 'The Sanctuary of Zi\'Tah' },
    { id = 122, name = 'Ro\'Maeve' },
    { id = 123, name = 'Yuhtunga Jungle' },
    { id = 124, name = 'Yhoator Jungle' },
    { id = 125, name = 'Western Altepa Desert' },
    { id = 126, name = 'Qufim Island' },
    { id = 127, name = 'Behemoth\'s Dominion' },
    { id = 128, name = 'Valley of Sorrows' },
    { id = 130, name = 'Ru\'Aun Gardens' },
    -- === Dungeons: Beastmen Strongholds ===
    { id = 140, name = 'Ghelsba Outpost' },
    { id = 141, name = 'Fort Ghelsba' },
    { id = 142, name = 'Yughott Grotto' },
    { id = 145, name = 'Giddeus' },
    { id = 147, name = 'Beadeaux' },
    { id = 149, name = 'Davoi' },
    { id = 150, name = 'Monastic Cavern' },
    { id = 151, name = 'Castle Oztroja' },
    { id = 152, name = 'Altar Room' },
    -- === Dungeons: Caves & Mines ===
    { id = 143, name = 'Palborough Mines' },
    { id = 166, name = 'Ranguemont Pass' },
    { id = 167, name = 'Bostaunieux Oubliette' },
    { id = 169, name = 'Toraimarai Canal' },
    { id = 172, name = 'Zeruhn Mines' },
    { id = 173, name = 'Korroloka Tunnel' },
    { id = 174, name = 'Kuftal Tunnel' },
    { id = 176, name = 'Sea Serpent Grotto' },
    { id = 190, name = 'King Ranperre\'s Tomb' },
    { id = 191, name = 'Dangruf Wadi' },
    { id = 192, name = 'Inner Horutoto Ruins' },
    { id = 193, name = 'Ordelle\'s Caves' },
    { id = 194, name = 'Outer Horutoto Ruins' },
    { id = 195, name = 'The Eldieme Necropolis' },
    { id = 196, name = 'Gusgen Mines' },
    { id = 197, name = 'Crawlers\' Nest' },
    { id = 198, name = 'Maze of Shakhrami' },
    { id = 200, name = 'Garlaige Citadel' },
    { id = 204, name = 'Fei\'Yin' },
    { id = 205, name = 'Ifrit\'s Cauldron' },
    { id = 208, name = 'Quicksand Caves' },
    { id = 212, name = 'Gustav Tunnel' },
    { id = 213, name = 'Labyrinth of Onzozo' },
    -- === Dungeons: Towers & Temples ===
    { id = 153, name = 'The Boyahda Tree' },
    { id = 154, name = 'Dragon\'s Aery' },
    { id = 157, name = 'Middle Delkfutt\'s Tower' },
    { id = 158, name = 'Upper Delkfutt\'s Tower' },
    { id = 184, name = 'Lower Delkfutt\'s Tower' },
    { id = 159, name = 'Temple of Uggalepih' },
    { id = 160, name = 'Den of Rancor' },
    -- === Dungeons: Castle Zvahl ===
    { id = 161, name = 'Castle Zvahl Baileys' },
    { id = 162, name = 'Castle Zvahl Keep' },
    { id = 165, name = 'Throne Room' },
    -- === Battlefields / Arenas ===
    { id = 139, name = 'Horlais Peak' },
    { id = 144, name = 'Waughroon Shrine' },
    { id = 146, name = 'Balga\'s Dais' },
    { id = 163, name = 'Sacrificial Chamber' },
    { id = 168, name = 'Chamber of Oracles' },
    { id = 170, name = 'Full Moon Fountain' },
    { id = 206, name = 'Qu\'Bia Arena' },
    -- === Cloisters ===
    { id = 201, name = 'Cloister of Gales' },
    { id = 202, name = 'Cloister of Storms' },
    { id = 203, name = 'Cloister of Frost' },
    { id = 207, name = 'Cloister of Flames' },
    { id = 209, name = 'Cloister of Tremors' },
    { id = 211, name = 'Cloister of Tides' },
    -- === Sky / Tu'Lia ===
    { id = 177, name = 'Velugannon Palace' },
    { id = 178, name = 'The Shrine of Ru\'Avitau' },
    { id = 179, name = 'Stellar Fulcrum' },
    { id = 180, name = 'La\'Loff Amphitheater' },
    { id = 181, name = 'The Celestial Nexus' },
    -- === Limbus ===
    { id = 37,  name = 'Temenos' },
    { id = 38,  name = 'Apollyon' },
    -- === Chains of Promathia ===
    { id = 1,   name = 'Phanauet Channel' },
    { id = 2,   name = 'Carpenters\' Landing' },
    { id = 3,   name = 'Manaclipper' },
    { id = 4,   name = 'Bibiki Bay' },
    { id = 5,   name = 'Uleguerand Range' },
    { id = 7,   name = 'Attohwa Chasm' },
    { id = 9,   name = 'Pso\'Xja' },
    { id = 11,  name = 'Oldton Movalpolos' },
    { id = 12,  name = 'Newton Movalpolos' },
    { id = 13,  name = 'Mine Shaft #2716' },
    { id = 14,  name = 'Hall of Transference' },
    { id = 16,  name = 'Promyvion - Holla' },
    { id = 17,  name = 'Spire of Holla' },
    { id = 18,  name = 'Promyvion - Dem' },
    { id = 19,  name = 'Spire of Dem' },
    { id = 20,  name = 'Promyvion - Mea' },
    { id = 21,  name = 'Spire of Mea' },
    { id = 22,  name = 'Promyvion - Vahzl' },
    { id = 23,  name = 'Spire of Vahzl' },
    { id = 24,  name = 'Lufaise Meadows' },
    { id = 25,  name = 'Misareaux Coast' },
    { id = 27,  name = 'Phomiuna Aqueducts' },
    { id = 28,  name = 'Sacrarium' },
    { id = 29,  name = 'Riverne - Site B01' },
    { id = 30,  name = 'Riverne - Site A01' },
    { id = 31,  name = 'Monarch Linn' },
    { id = 32,  name = 'Sealion\'s Den' },
    { id = 33,  name = 'Al\'Taieu' },
    { id = 34,  name = 'Grand Palace of Hu\'Xzoi' },
    { id = 35,  name = 'The Garden of Ru\'Hmet' },
    { id = 36,  name = 'Empyreal Paradox' },
    { id = 6,   name = 'Bearclaw Pinnacle' },
    { id = 8,   name = 'Boneyard Gully' },
    { id = 10,  name = 'The Shrouded Maw' },
    -- === Treasures of Aht Urhgan ===
    { id = 51,  name = 'Wajaom Woodlands' },
    { id = 52,  name = 'Bhaflau Thickets' },
    { id = 54,  name = 'Arrapago Reef' },
    { id = 55,  name = 'Ilrusi Atoll' },
    { id = 56,  name = 'Periqia' },
    { id = 57,  name = 'Talacca Cove' },
    { id = 60,  name = 'The Ashu Talif' },
    { id = 61,  name = 'Mount Zhayolm' },
    { id = 62,  name = 'Halvung' },
    { id = 63,  name = 'Lebros Cavern' },
    { id = 64,  name = 'Navukgo Execution Chamber' },
    { id = 65,  name = 'Mamook' },
    { id = 66,  name = 'Mamool Ja Training Grounds' },
    { id = 67,  name = 'Jade Sepulcher' },
    { id = 68,  name = 'Aydeewa Subterrane' },
    { id = 69,  name = 'Leujaoam Sanctum' },
    { id = 70,  name = 'Chocobo Circuit' },
    { id = 71,  name = 'The Colosseum' },
    { id = 72,  name = 'Alzadaal Undersea Ruins' },
    { id = 73,  name = 'Zhayolm Remnants' },
    { id = 74,  name = 'Arrapago Remnants' },
    { id = 75,  name = 'Bhaflau Remnants' },
    { id = 76,  name = 'Silver Sea Remnants' },
    { id = 77,  name = 'Nyzul Isle' },
    { id = 78,  name = 'Hazhalm Testing Grounds' },
    { id = 79,  name = 'Caedarva Mire' },
    -- === Wings of the Goddess (Past) ===
    { id = 80,  name = 'Southern San d\'Oria [S]' },
    { id = 81,  name = 'East Ronfaure [S]' },
    { id = 82,  name = 'Jugner Forest [S]' },
    { id = 83,  name = 'Vunkerl Inlet [S]' },
    { id = 84,  name = 'Batallia Downs [S]' },
    { id = 85,  name = 'La Vaule [S]' },
    { id = 86,  name = 'Everbloom Hollow' },
    { id = 87,  name = 'Bastok Markets [S]' },
    { id = 88,  name = 'North Gustaberg [S]' },
    { id = 89,  name = 'Grauberg [S]' },
    { id = 90,  name = 'Pashhow Marshlands [S]' },
    { id = 91,  name = 'Rolanberry Fields [S]' },
    { id = 92,  name = 'Beadeaux [S]' },
    { id = 93,  name = 'Ruhotz Silvermines' },
    { id = 94,  name = 'Windurst Waters [S]' },
    { id = 95,  name = 'West Sarutabaruta [S]' },
    { id = 96,  name = 'Fort Karugo-Narugo [S]' },
    { id = 97,  name = 'Meriphataud Mountains [S]' },
    { id = 98,  name = 'Sauromugue Champaign [S]' },
    { id = 99,  name = 'Castle Oztroja [S]' },
    { id = 136, name = 'Beaucedine Glacier [S]' },
    { id = 137, name = 'Xarcabard [S]' },
    { id = 138, name = 'Castle Zvahl Baileys [S]' },
    { id = 155, name = 'Castle Zvahl Keep [S]' },
    { id = 164, name = 'Garlaige Citadel [S]' },
    { id = 171, name = 'Crawlers\' Nest [S]' },
    { id = 175, name = 'The Eldieme Necropolis [S]' },
    -- === Dynamis ===
    { id = 185, name = 'Dynamis - San d\'Oria' },
    { id = 186, name = 'Dynamis - Bastok' },
    { id = 187, name = 'Dynamis - Windurst' },
    { id = 188, name = 'Dynamis - Jeuno' },
    { id = 134, name = 'Dynamis - Beaucedine' },
    { id = 135, name = 'Dynamis - Xarcabard' },
    { id = 39,  name = 'Dynamis - Valkurm' },
    { id = 40,  name = 'Dynamis - Buburimu' },
    { id = 41,  name = 'Dynamis - Qufim' },
    { id = 42,  name = 'Dynamis - Tavnazia' },
    -- === Dynamis Divergence [D] ===
    { id = 294, name = 'Dynamis - San d\'Oria [D]' },
    { id = 295, name = 'Dynamis - Bastok [D]' },
    { id = 296, name = 'Dynamis - Windurst [D]' },
    { id = 297, name = 'Dynamis - Jeuno [D]' },
    -- === Abyssea ===
    { id = 15,  name = 'Abyssea - Konschtat' },
    { id = 45,  name = 'Abyssea - Tahrongi' },
    { id = 132, name = 'Abyssea - La Theine' },
    { id = 215, name = 'Abyssea - Attohwa' },
    { id = 216, name = 'Abyssea - Misareaux' },
    { id = 217, name = 'Abyssea - Vunkerl' },
    { id = 218, name = 'Abyssea - Altepa' },
    { id = 253, name = 'Abyssea - Uleguerand' },
    { id = 254, name = 'Abyssea - Grauberg' },
    { id = 255, name = 'Abyssea - Empyreal Paradox' },
    -- === Seekers of Adoulin ===
    { id = 258, name = 'Rala Waterways' },
    { id = 260, name = 'Yahse Hunting Grounds' },
    { id = 261, name = 'Ceizak Battlegrounds' },
    { id = 262, name = 'Foret de Hennetiel' },
    { id = 263, name = 'Yorcia Weald' },
    { id = 265, name = 'Morimar Basalt Fields' },
    { id = 266, name = 'Marjami Ravine' },
    { id = 267, name = 'Kamihr Drifts' },
    { id = 268, name = 'Sih Gates' },
    { id = 269, name = 'Moh Gates' },
    { id = 270, name = 'Cirdas Caverns' },
    { id = 272, name = 'Dho Gates' },
    { id = 273, name = 'Woh Gates' },
    { id = 274, name = 'Outer Ra\'Kaznar' },
    { id = 276, name = 'Ra\'Kaznar Inner Court' },
    { id = 284, name = 'Celennia Memorial Library' },
    -- === Escha / Reisenjima ===
    { id = 288, name = 'Escha - Zi\'Tah' },
    { id = 289, name = 'Escha - Ru\'Aun' },
    { id = 291, name = 'Reisenjima' },
    { id = 292, name = 'Reisenjima Henge' },
    -- === Walk of Echoes / Other ===
    { id = 182, name = 'Walk of Echoes' },
    { id = 222, name = 'Provenance' },
    { id = 43,  name = 'Diorama Abdhaljs-Ghelsba' },
    { id = 44,  name = 'Abdhaljs Isle-Purgonorgo' },
    { id = 183, name = 'Maquette Abdhaljs-Legion' },
    -- === Transport ===
    { id = 46,  name = 'Open Sea Route to Al Zahbi' },
    { id = 47,  name = 'Open Sea Route to Mhaura' },
    { id = 220, name = 'Ship bound for Selbina' },
    { id = 221, name = 'Ship bound for Mhaura' },
};

commands.weather = T{
    { id = 0,  name = 'Clear' },
    { id = 1,  name = 'Sunny' },
    { id = 2,  name = 'Cloudy' },
    { id = 3,  name = 'Fog' },
    { id = 4,  name = 'Hot' },
    { id = 5,  name = 'Heat Wave' },
    { id = 6,  name = 'Rain' },
    { id = 7,  name = 'Downpour' },
    { id = 8,  name = 'Dust Storm' },
    { id = 9,  name = 'Sandstorm' },
    { id = 10, name = 'Wind' },
    { id = 11, name = 'Gale' },
    { id = 12, name = 'Snow' },
    { id = 13, name = 'Blizzard' },
    { id = 14, name = 'Thunder' },
    { id = 15, name = 'Thunderstorm' },
    { id = 16, name = 'Auroras' },
    { id = 17, name = 'Stellar Glare' },
    { id = 18, name = 'Gloom' },
    { id = 19, name = 'Darkness' },
};

commands.nations = T{
    { id = 0, name = 'San d\'Oria' },
    { id = 1, name = 'Bastok' },
    { id = 2, name = 'Windurst' },
};

-------------------------------------------------------------------------------
-- Command definitions by category
-------------------------------------------------------------------------------

commands.categories = T{
    --
    -- 1. Teleport
    --
    {
        name = 'Teleport',
        icon = 'T',
        commands = T{
            { name = 'Zone',      cmd = '!zone',      desc = 'Teleport to a zone by ID',                 args = {{ name = 'Zone', type = 'select', options = 'zones' }} },
            { name = 'Position',  cmd = '!pos',        desc = 'Teleport to x y z coordinates',            args = {{ name = 'X', type = 'float' }, { name = 'Y', type = 'float' }, { name = 'Z', type = 'float' }} },
            { name = 'Go To',     cmd = '!goto',       desc = 'Teleport to a player',                     args = {{ name = 'Player', type = 'string' }} },
            { name = 'Go To ID',  cmd = '!gotoid',     desc = 'Teleport to entity by server ID',          args = {{ name = 'ID', type = 'int' }} },
            { name = 'Bring',     cmd = '!bring',      desc = 'Bring a player to your position',          args = {{ name = 'Player', type = 'string' }} },
            { name = 'Send',      cmd = '!send',       desc = 'Send a player to a zone',                  args = {{ name = 'Player', type = 'string' }, { name = 'Zone', type = 'select', options = 'zones' }} },
            { name = 'GM Home',   cmd = '!gmhome',     desc = 'Teleport to GM Home zone',                 args = {} },
            { name = 'Homepoint', cmd = '!homepoint',  desc = 'Warp to your homepoint',                   args = {} },
            { name = 'Return',    cmd = '!return',     desc = 'Return to last zone',                      args = {} },
            { name = 'Speed',     cmd = '!speed',      desc = 'Set movement speed (0=normal)',             args = {{ name = 'Speed', type = 'int', default = 50 }} },
            { name = 'Wallhack',  cmd = '!wallhack',   desc = 'Toggle clipping through walls',            args = {} },
            { name = 'Up',        cmd = '!up',         desc = 'Move up by Y units',                       args = {{ name = 'Y', type = 'float', default = 5.0 }} },
            { name = 'Down',      cmd = '!down',       desc = 'Move down by Y units',                     args = {{ name = 'Y', type = 'float', default = 5.0 }} },
            { name = 'Where',     cmd = '!where',      desc = 'Show current position and zone info',      args = {} },
            { name = 'Pos Fix',   cmd = '!posfix',     desc = 'Fix stuck position (offline player)',       args = {{ name = 'Player', type = 'string' }} },
            { name = 'Go To Name', cmd = '!gotoname',  desc = 'Go to mob/NPC by name',                    args = {{ name = 'Name', type = 'string' }, { name = 'Index', type = 'int' }} },
        },
    },
    --
    -- 2. Character
    --
    {
        name = 'Character',
        icon = 'C',
        commands = T{
            { name = 'Set Level',        cmd = '!setplayerlevel',   desc = 'Set character level',                args = {{ name = 'Level', type = 'int', default = 99 }} },
            { name = 'Change Job',       cmd = '!changejob',       desc = 'Change main job + level + master',   args = {{ name = 'Job', type = 'select', options = 'jobs' }, { name = 'Level', type = 'int', default = 99 }, { name = 'Master', type = 'int', default = 1 }} },
            { name = 'Change Sub Job',   cmd = '!changesjob',      desc = 'Change sub job',                     args = {{ name = 'Job', type = 'select', options = 'jobs' }} },
            { name = 'Master Job',       cmd = '!masterjob',       desc = 'Master current job (max job points)', args = {} },
            { name = 'Give XP',          cmd = '!givexp',          desc = 'Give experience points',             args = {{ name = 'Amount', type = 'int', default = 10000 }} },
            { name = 'Take XP',          cmd = '!takexp',          desc = 'Remove experience points',           args = {{ name = 'Amount', type = 'int', default = 1000 }} },
            { name = 'Set Merits',       cmd = '!setmerits',       desc = 'Set available merit points',         args = {{ name = 'Amount', type = 'int', default = 30 }} },
            { name = 'Set Job Points',   cmd = '!setjobpoints',    desc = 'Set available job points',           args = {{ name = 'Amount', type = 'int', default = 500 }} },
            { name = 'Set Capacity Pts', cmd = '!setcapacitypoints', desc = 'Set capacity points',              args = {{ name = 'Amount', type = 'int', default = 30000 }} },
            { name = 'Set Rank',         cmd = '!setrank',         desc = 'Set nation mission rank (1-10)',     args = {{ name = 'Rank', type = 'int', default = 10 }} },
            { name = 'Set Nation',       cmd = '!setplayernation', desc = 'Set player allegiance nation',       args = {{ name = 'Nation', type = 'select', options = 'nations' }} },
            { name = 'Race Change',      cmd = '!racechange',      desc = 'Grant 14-day race change token',     args = {{ name = 'Player', type = 'string' }}, perm = 3 },
            { name = 'Costume',          cmd = '!costume',         desc = 'Set player costume model',              args = {{ name = 'CostumeID', type = 'int' }} },
            { name = 'Costume 2',        cmd = '!costume2',        desc = 'Set player costume2 model',             args = {{ name = 'CostumeID', type = 'int' }} },
            { name = 'Set Model',        cmd = '!setplayermodel',  desc = 'Set player model by slot',              args = {{ name = 'Model', type = 'int' }, { name = 'Slot', type = 'int' }} },
            { name = 'CP',               cmd = '!cp',              desc = 'Add capacity points',                   args = {{ name = 'Amount', type = 'int', default = 30000 }} },
            { name = 'Chocobo',          cmd = '!chocobo',         desc = 'Register and ride a chocobo',           args = {{ name = 'Color', type = 'string' }} },
            { name = 'Mount',            cmd = '!mount',           desc = 'Register and use a mount',              args = {{ name = 'MountID', type = 'string' }} },
            { name = 'Set Allegiance',   cmd = '!setallegiance',   desc = 'Set player allegiance',                 args = {{ name = 'Allegiance', type = 'int' }} },
            { name = 'Set Mentor',       cmd = '!setmentor',       desc = 'Set mentor mode (0/1/2)',               args = {{ name = 'Mode', type = 'int' }} },
        },
    },
    --
    -- 3. Skills
    --
    {
        name = 'Skills',
        icon = 'S',
        commands = T{
            { name = 'Cap All Skills',       cmd = '!capallskills',       desc = 'Max all combat and magic skills',    args = {} },
            { name = 'Add All Spells',       cmd = '!addallspells',       desc = 'Learn all spells',                   args = {} },
            { name = 'Add All Trusts',       cmd = '!addalltrusts',       desc = 'Learn all trust magic',              args = {} },
            { name = 'Add All Weaponskills', cmd = '!addallweaponskills', desc = 'Learn all weapon skills',            args = {} },
            { name = 'Del All Weaponskills', cmd = '!delallweaponskills', desc = 'Remove all weapon skills',           args = {} },
            { name = 'Add All Maps',         cmd = '!addallmaps',         desc = 'Unlock all area maps',               args = {} },
            { name = 'Add All Mounts',       cmd = '!addallmounts',       desc = 'Unlock all mounts',                  args = {} },
            { name = 'Add All Attachments',  cmd = '!addallattachments',  desc = 'Unlock all puppet attachments',      args = {} },
            { name = 'Add All Monstrosity',  cmd = '!addallmonstrosity',  desc = 'Unlock all monstrosity species',     args = {} },
            { name = 'Set Skill',            cmd = '!setskill',           desc = 'Set a specific skill level',         args = {{ name = 'SkillID', type = 'int' }, { name = 'Value', type = 'int' }} },
            { name = 'Cap Skill',            cmd = '!capskill',           desc = 'Cap a specific skill to max',        args = {{ name = 'SkillID', type = 'int' }} },
            { name = 'Add Spell',            cmd = '!addspell',           desc = 'Learn a specific spell by ID',       args = {{ name = 'SpellID', type = 'int' }} },
            { name = 'Del Spell',            cmd = '!delspell',           desc = 'Remove a specific spell by ID',      args = {{ name = 'SpellID', type = 'int' }} },
            { name = 'Get Skill',            cmd = '!getskill',           desc = 'Show current value of a skill',      args = {{ name = 'SkillID', type = 'int' }} },
            { name = 'Set Craft Rank',       cmd = '!setcraftrank',       desc = 'Set crafting rank',                  args = {{ name = 'CraftID', type = 'int' }, { name = 'Rank', type = 'int' }} },
            { name = 'Get Craft Rank',       cmd = '!getcraftrank',       desc = 'Show rank of a craft skill',         args = {{ name = 'CraftName', type = 'string' }} },
            { name = 'Add WS Points',       cmd = '!addweaponskillpoints', desc = 'Add weapon skill points to item',  args = {{ name = 'Slot', type = 'int' }, { name = 'Points', type = 'int' }} },
        },
    },
    --
    -- 4. Items
    --
    {
        name = 'Items',
        icon = 'I',
        commands = T{
            { name = 'Add Item',          cmd = '!additem',          desc = 'Add item to your inventory',        args = {{ name = 'ItemID', type = 'int' }, { name = 'Qty', type = 'int', default = 1 }} },
            { name = 'Give Item',         cmd = '!giveitem',         desc = 'Give item to target player',        args = {{ name = 'ItemID', type = 'int' }, { name = 'Qty', type = 'int', default = 1 }} },
            { name = 'Del Item',          cmd = '!delitem',          desc = 'Delete item from inventory',        args = {{ name = 'ItemID', type = 'int' }, { name = 'Qty', type = 'int', default = 1 }} },
            { name = 'Add Temp Item',     cmd = '!addtempitem',      desc = 'Add temporary item',                args = {{ name = 'ItemID', type = 'int' }} },
            { name = 'Has Item',          cmd = '!hasitem',          desc = 'Check if you have an item',         args = {{ name = 'ItemID', type = 'int' }} },
            { name = 'Give Gil',          cmd = '!givegil',          desc = 'Give gil to target',                args = {{ name = 'Amount', type = 'int', default = 100000 }} },
            { name = 'Set Gil',           cmd = '!setgil',           desc = 'Set your gil amount',               args = {{ name = 'Amount', type = 'int', default = 10000000 }} },
            { name = 'Take Gil',          cmd = '!takegil',          desc = 'Remove gil',                        args = {{ name = 'Amount', type = 'int', default = 1000 }} },
            { name = 'Add Currency',      cmd = '!addcurrency',      desc = 'Add special currency by type',      args = {{ name = 'Type', type = 'int' }, { name = 'Amount', type = 'int', default = 1000 }} },
            { name = 'Del Currency',      cmd = '!delcurrency',      desc = 'Remove special currency',           args = {{ name = 'Type', type = 'int' }, { name = 'Amount', type = 'int', default = 1000 }} },
            { name = 'Set Bag Size',      cmd = '!setbag',           desc = 'Set inventory bag capacity',        args = {{ name = 'Size', type = 'int', default = 80 }} },
            { name = 'Del All Inventory', cmd = '!delallinventory',  desc = 'Delete ALL items from inventory',   args = {} },
            { name = 'Add Key Item',      cmd = '!addkeyitem',       desc = 'Add a key item by ID',              args = {{ name = 'KeyItemID', type = 'int' }} },
            { name = 'Del Key Item',      cmd = '!delkeyitem',       desc = 'Remove a key item by ID',           args = {{ name = 'KeyItemID', type = 'int' }} },
            { name = 'Has Key Item',      cmd = '!haskeyitem',       desc = 'Check if you have a key item',      args = {{ name = 'KeyItemID', type = 'int' }} },
            { name = 'Add All Atma',      cmd = '!addallatma',       desc = 'Add all atma key items',            args = {} },
            { name = 'Add Title',         cmd = '!addtitle',         desc = 'Add and set player title',              args = {{ name = 'TitleID', type = 'string' }} },
            { name = 'Has Title',         cmd = '!hastitle',         desc = 'Check if player has a title',           args = {{ name = 'TitleID', type = 'string' }} },
            { name = 'Add Lights',        cmd = '!addlights',        desc = 'Add Abyssea lights by type',            args = {{ name = 'LightType', type = 'string' }, { name = 'Amount', type = 'int' }} },
            { name = 'Reset Lights',      cmd = '!resetlights',      desc = 'Reset all Abyssea lights to 0',         args = {} },
            { name = 'Give Linkshell',    cmd = '!givels',           desc = 'Create a linkpearl for a LS',           args = {{ name = 'LSName', type = 'string' }} },
            { name = 'Give Magian Item',  cmd = '!givemagianitem',   desc = 'Give Magian trial reward item',         args = {{ name = 'Player', type = 'string' }, { name = 'TrialID', type = 'int' }} },
            { name = 'Add Treasure',      cmd = '!addtreasure',      desc = 'Add item to treasure pool',             args = {{ name = 'ItemID', type = 'int' }} },
            { name = 'Del Container',     cmd = '!delcontaineritems', desc = 'Delete all items in a container',      args = {{ name = 'Container', type = 'int' }} },
        },
    },
    --
    -- 5. Status
    --
    {
        name = 'Status',
        icon = 'H',
        commands = T{
            { name = 'Set HP',      cmd = '!hp',         desc = 'Set current HP',                        args = {{ name = 'HP', type = 'int', default = 9999 }} },
            { name = 'Set MP',      cmd = '!mp',         desc = 'Set current MP',                        args = {{ name = 'MP', type = 'int', default = 9999 }} },
            { name = 'Set TP',      cmd = '!tp',         desc = 'Set current TP',                        args = {{ name = 'TP', type = 'int', default = 3000 }} },
            { name = 'God Mode',    cmd = '!godmode',    desc = 'Toggle invincibility',                  args = {} },
            { name = 'Immortal',    cmd = '!immortal',   desc = 'Toggle immortality (HP won\'t drop)',   args = {} },
            { name = 'Raise',       cmd = '!raise',      desc = 'Raise from KO',                         args = {} },
            { name = 'Reset',       cmd = '!reset',      desc = 'Reset HP/MP/TP to max',                 args = {} },
            { name = 'Add Effect',  cmd = '!addeffect',  desc = 'Add status effect by ID',               args = {{ name = 'EffectID', type = 'int' }, { name = 'Power', type = 'int', default = 1 }, { name = 'Duration', type = 'int', default = 60 }} },
            { name = 'Del Effect',  cmd = '!deleffect',  desc = 'Remove status effect by ID',            args = {{ name = 'EffectID', type = 'int' }} },
            { name = 'Get Effects', cmd = '!geteffects', desc = 'List all active status effects',        args = {}, perm = 0 },
        },
    },
    --
    -- 6. Mobs
    --
    {
        name = 'Mobs',
        icon = 'M',
        commands = T{
            { name = 'Spawn Mob',     cmd = '!spawnmob',     desc = 'Spawn a mob by ID at your position',  args = {{ name = 'MobID', type = 'int' }} },
            { name = 'Despawn Mob',   cmd = '!despawnmob',   desc = 'Despawn a mob by ID',                 args = {{ name = 'MobID', type = 'int' }} },
            { name = 'Mob Here',      cmd = '!mobhere',      desc = 'Move mob to your position',           args = {{ name = 'MobID', type = 'int' }} },
            { name = 'Set Mob Level', cmd = '!setmoblevel',  desc = 'Set targeted mob level',              args = {{ name = 'Level', type = 'int', default = 1 }} },
            { name = 'Mob Skill',     cmd = '!mobskill',     desc = 'Force mob to use a skill',            args = {{ name = 'SkillID', type = 'int' }} },
            { name = 'Provoke All',   cmd = '!provokeall',   desc = 'Aggro all nearby mobs',               args = {} },
            { name = 'Get Enmity',    cmd = '!getenmity',    desc = 'Show enmity table for target',        args = {}, perm = 2 },
            { name = 'NPC Here',      cmd = '!npchere',      desc = 'Move NPC to your position',           args = {{ name = 'NPCID', type = 'int' }} },
            { name = 'Set Mob Flags', cmd = '!setmobflags',  desc = 'Set mob nameflags',                   args = {{ name = 'Flags', type = 'int' }, { name = 'MobID', type = 'int' }} },
            { name = 'Get Mob Flags', cmd = '!getmobflags',  desc = 'Show mob render flags',               args = {{ name = 'MobID', type = 'int' }} },
            { name = 'Rename',        cmd = '!rename',       desc = 'Rename target entity',                args = {{ name = 'Name', type = 'string' }} },
            { name = 'Get ID',        cmd = '!getid',        desc = 'Show target entity server ID',        args = {} },
            { name = 'Mob Sub',       cmd = '!mobsub',       desc = 'Change mob sub-animation',                args = {{ name = 'MobID', type = 'string' }, { name = 'AnimID', type = 'string' }} },
            { name = 'Get Mob Action', cmd = '!getmobaction', desc = 'Show mob current action',                args = {{ name = 'MobID', type = 'int' }} },
            { name = 'Get Mob Mod',   cmd = '!getmobmod',    desc = 'Get modifier on target mob',              args = {{ name = 'ModID', type = 'string' }} },
            { name = 'Pet God Mode',  cmd = '!petgodmode',   desc = 'Toggle god mode on your pet',             args = {} },
            { name = 'Pet TP',        cmd = '!pettp',        desc = 'Set pet TP amount',                       args = {{ name = 'Amount', type = 'int', default = 3000 }} },
            { name = 'Garrison',      cmd = '!garrison',     desc = 'Start/stop/win garrison',                 args = {{ name = 'Command', type = 'string' }} },
        },
    },
    --
    -- 7. World
    --
    {
        name = 'World',
        icon = 'W',
        commands = T{
            { name = 'Set Weather',      cmd = '!setweather',      desc = 'Set zone weather',                    args = {{ name = 'Weather', type = 'select', options = 'weather' }} },
            { name = 'Set Time',         cmd = '!time',            desc = 'Set Vana\'diel time (0-23)',          args = {{ name = 'Hour', type = 'int', default = 12 }} },
            { name = 'Add Time',         cmd = '!addtime',         desc = 'Add real seconds to game clock',      args = {{ name = 'Seconds', type = 'int', default = 3600 }}, perm = 5 },
            { name = 'Add Aby Time',     cmd = '!addabytime',      desc = 'Add Abyssea time (seconds)',          args = {{ name = 'Seconds', type = 'int', default = 600 }} },
            { name = 'Add Dyna Time',    cmd = '!adddynatime',     desc = 'Add Dynamis time (seconds)',          args = {{ name = 'Seconds', type = 'int', default = 600 }} },
            { name = 'Update Conquest',  cmd = '!updateconquest',  desc = 'Force conquest update',               args = {} },
            { name = 'Conquest Nation',  cmd = '!cnation',         desc = 'Set zone conquest nation',            args = {{ name = 'Nation', type = 'select', options = 'nations' }} },
            { name = 'Auction House',    cmd = '!ah',              desc = 'Open Auction House anywhere',         args = {} },
            { name = 'Set Music',        cmd = '!setmusic',        desc = 'Change client music (type 0-7)',      args = {{ name = 'Type', type = 'int', default = 0 }, { name = 'SongID', type = 'int' }} },
            { name = 'Animate NPC',      cmd = '!animatenpc',      desc = 'Change NPC animation',                    args = {{ name = 'NPCID', type = 'string' }, { name = 'AnimID', type = 'string' }} },
            { name = 'Animate Sub NPC',  cmd = '!animatesubnpc',   desc = 'Change NPC sub-animation',                args = {{ name = 'NPCID', type = 'string' }, { name = 'AnimID', type = 'string' }} },
            { name = 'Animation',        cmd = '!animation',       desc = 'Set player animation',                    args = {{ name = 'AnimID', type = 'string' }} },
            { name = 'Entity Visual',    cmd = '!entityvisual',    desc = 'Push entity visual packet',               args = {{ name = 'AnimString', type = 'string' }} },
            { name = 'Pose Mannequin',   cmd = '!posemannequin',   desc = 'Change mannequin pose',                   args = {{ name = 'Race', type = 'int' }, { name = 'Pose', type = 'int' }} },
        },
    },
    --
    -- 8. Quests
    --
    {
        name = 'Quests',
        icon = 'Q',
        commands = T{
            { name = 'Mission',          cmd = '!mission',          desc = 'Show current mission info',           args = {} },
            { name = 'Add Mission',      cmd = '!addmission',       desc = 'Start a mission by log and ID',      args = {{ name = 'LogID', type = 'int' }, { name = 'MissionID', type = 'int' }} },
            { name = 'Complete Mission', cmd = '!completemission',  desc = 'Complete a mission',                  args = {{ name = 'LogID', type = 'int' }, { name = 'MissionID', type = 'int' }} },
            { name = 'Del Mission',      cmd = '!delmission',       desc = 'Remove a mission',                    args = {{ name = 'LogID', type = 'int' }, { name = 'MissionID', type = 'int' }} },
            { name = 'Check Mission',    cmd = '!checkmission',     desc = 'Check mission status',                args = {{ name = 'LogID', type = 'int' }, { name = 'MissionID', type = 'int' }} },
            { name = 'Quest',            cmd = '!quest',            desc = 'Show current quest info',             args = {} },
            { name = 'Add Quest',        cmd = '!addquest',         desc = 'Start a quest by log and ID',        args = {{ name = 'LogID', type = 'int' }, { name = 'QuestID', type = 'int' }} },
            { name = 'Complete Quest',   cmd = '!completequest',    desc = 'Complete a quest',                    args = {{ name = 'LogID', type = 'int' }, { name = 'QuestID', type = 'int' }} },
            { name = 'Del Quest',        cmd = '!delquest',         desc = 'Remove a quest',                      args = {{ name = 'LogID', type = 'int' }, { name = 'QuestID', type = 'int' }} },
            { name = 'Cutscene',         cmd = '!cs',               desc = 'Play a cutscene by event ID',        args = {{ name = 'EventID', type = 'int' }} },
            { name = 'Cutscene 2',       cmd = '!cs2',              desc = 'Start event with parameters',            args = {{ name = 'EventID', type = 'int' }} },
            { name = 'Check Quest',      cmd = '!checkquest',       desc = 'Print quest status details',             args = {{ name = 'LogID', type = 'string' }, { name = 'QuestID', type = 'string' }} },
            { name = 'Check Mission Status', cmd = '!checkmissionstatus', desc = 'Print mission status value',      args = {{ name = 'LogID', type = 'int' }, { name = 'Index', type = 'int' }} },
            { name = 'Set Mission Status', cmd = '!setmissionstatus', desc = 'Set mission status value',             args = {{ name = 'Value', type = 'int' }, { name = 'LogID', type = 'int' }, { name = 'Index', type = 'int' }} },
            { name = 'Complete Record',  cmd = '!completerecord',   desc = 'Complete a record by ID',                args = {{ name = 'RecordID', type = 'int' }} },
            { name = 'Get Quest Var',    cmd = '!getquestvar',      desc = 'Get a quest variable',                   args = {{ name = 'LogID', type = 'int' }, { name = 'QuestID', type = 'int' }, { name = 'Variable', type = 'string' }} },
            { name = 'Set Quest Var',    cmd = '!setquestvar',      desc = 'Set a quest variable',                   args = {{ name = 'LogID', type = 'int' }, { name = 'QuestID', type = 'int' }, { name = 'Variable', type = 'string' }, { name = 'Value', type = 'int' }} },
        },
    },
    --
    -- 9. Admin
    --
    {
        name = 'Admin',
        icon = 'A',
        commands = T{
            { name = 'Toggle GM',      cmd = '!togglegm',      desc = 'Toggle GM flag on/off',                args = {} },
            { name = 'Hide',           cmd = '!hide',           desc = 'Toggle GM invisibility',               args = {} },
            { name = 'Promote',        cmd = '!promote',        desc = 'Set player GM level (0-5)',            args = {{ name = 'Player', type = 'string' }, { name = 'Level', type = 'int', default = 1 }} },
            { name = 'Jail',           cmd = '!jail',           desc = 'Send player to Mordion Gaol',         args = {{ name = 'Player', type = 'string' }} },
            { name = 'Pardon',         cmd = '!pardon',         desc = 'Release player from jail',             args = {{ name = 'Player', type = 'string' }} },
            { name = 'AFK Check',      cmd = '!afkcheck',       desc = 'Send AFK check to player',            args = {{ name = 'Player', type = 'string' }} },
            { name = 'Yell',           cmd = '!yell',           desc = 'Broadcast server message',             args = {{ name = 'Message', type = 'string' }} },
            { name = 'Log Off',        cmd = '!logoff',         desc = 'Force player to disconnect',           args = {{ name = 'Player', type = 'string' }} },
            { name = 'Break Linkshell', cmd = '!breaklinkshell', desc = 'Break a linkshell by name',            args = {{ name = 'Name', type = 'string' }}, perm = 4 },
            { name = 'Release',        cmd = '!release',        desc = 'Release player from event/NPC',       args = {} },
            { name = 'Sleep',          cmd = '!sleep',          desc = 'Put target to sleep',                  args = {}, perm = 5 },
            { name = 'Exec',           cmd = '!exec',           desc = 'Execute a Lua script file',           args = {{ name = 'Script', type = 'string' }}, perm = 4 },
            { name = 'Get Fishers',    cmd = '!getfishers',     desc = 'List players who recently fished',    args = {{ name = 'Minutes', type = 'int', default = 30 }} },
        },
    },
    --
    -- 10. Reload
    --
    {
        name = 'Reload',
        icon = 'R',
        commands = T{
            { name = 'Reload Global',       cmd = '!reloadglobal',       desc = 'Reload global Lua scripts',         args = {}, perm = 4 },
            { name = 'Reload Quest',        cmd = '!reloadquest',        desc = 'Reload quest scripts for zone',     args = {}, perm = 5 },
            { name = 'Reload Interaction',  cmd = '!reloadinteraction',  desc = 'Reload NPC interaction scripts',    args = {}, perm = 5 },
            { name = 'Reload NavMesh',      cmd = '!reloadnavmesh',      desc = 'Reload navigation mesh for zone',  args = {}, perm = 5 },
            { name = 'Reload Recipes',      cmd = '!reloadrecipes',      desc = 'Reload crafting recipe data',       args = {}, perm = 5 },
            { name = 'Reload Battlefield',  cmd = '!reloadbattlefield',  desc = 'Reload battlefield scripts',        args = {}, perm = 5 },
            { name = 'Reload Defaults',     cmd = '!reloaddefaultactions', desc = 'Reload default action scripts',   args = {}, perm = 5 },
        },
    },
    --
    -- 11. Debug
    --
    {
        name = 'Debug',
        icon = 'D',
        commands = T{
            { name = 'Get Stats',     cmd = '!getstats',      desc = 'Show character stat block',             args = {} },
            { name = 'Get Mod',       cmd = '!getmod',        desc = 'Get modifier value by ID',              args = {{ name = 'ModID', type = 'int' }}, perm = 3 },
            { name = 'Set Mod',       cmd = '!setmod',        desc = 'Set modifier value',                    args = {{ name = 'ModID', type = 'int' }, { name = 'Value', type = 'int' }} },
            { name = 'Check Var',     cmd = '!checkvar',      desc = 'Check a server variable',               args = {{ name = 'VarName', type = 'string' }} },
            { name = 'Set Player Var', cmd = '!setplayervar',  desc = 'Set player variable',                   args = {{ name = 'VarName', type = 'string' }, { name = 'Value', type = 'int' }} },
            { name = 'Check Local Var', cmd = '!checklocalvar', desc = 'Check a local zone variable',         args = {{ name = 'VarName', type = 'string' }} },
            { name = 'Set Local Var', cmd = '!setlocalvar',   desc = 'Set a local zone variable',             args = {{ name = 'VarName', type = 'string' }, { name = 'Value', type = 'int' }}, perm = 3 },
            { name = 'Get Fame',      cmd = '!getfame',       desc = 'Show fame values',                      args = {}, perm = 3 },
            { name = 'Set Fame Level', cmd = '!setfamelevel',  desc = 'Set fame level for a nation',          args = {{ name = 'NationID', type = 'int' }, { name = 'Level', type = 'int' }}, perm = 3 },
            { name = 'Build Info',    cmd = '!build',         desc = 'Show server build information',         args = {}, perm = 0 },
            { name = 'Uptime',        cmd = '!uptime',        desc = 'Show server uptime',                    args = {} },
            { name = 'Inject',        cmd = '!inject',        desc = 'Inject a packet (advanced)',            args = {{ name = 'PacketData', type = 'string' }} },
            { name = 'Instance',          cmd = '!instance',          desc = 'Load and enter an instance',            args = {{ name = 'InstanceID', type = 'int' }} },
            { name = 'Inject Action',     cmd = '!injectaction',      desc = 'Inject an action packet',               args = {{ name = 'ActionID', type = 'int' }, { name = 'AnimID', type = 'int' }} },
            { name = 'Message Basic',     cmd = '!messagebasic',      desc = 'Inject message basic packet',           args = {{ name = 'MsgID', type = 'int' }, { name = 'Param1', type = 'int' }, { name = 'Param2', type = 'int' }} },
            { name = 'Message Special',   cmd = '!messagespecial',    desc = 'Inject message special packet',         args = {{ name = 'MsgID', type = 'int' }} },
            { name = 'Message Standard',  cmd = '!messagestandard',   desc = 'Inject standard message packet',        args = {{ name = 'MsgID', type = 'int' }} },
            { name = 'Set Progress',      cmd = '!setprogress',       desc = 'Set instance progress',                 args = {{ name = 'Progress', type = 'int' }} },
            { name = 'Set Stage',         cmd = '!setstage',          desc = 'Set instance stage',                    args = {{ name = 'Stage', type = 'int' }} },
            { name = 'Menu',              cmd = '!menu',              desc = 'Show test menu with 3 options',         args = {} },
            { name = 'Menu Paginated',    cmd = '!menu_paginated',    desc = 'Show paginated test menu',              args = {} },
            { name = 'Minigame',          cmd = '!minigame',          desc = 'Open minigame test menu',               args = {} },
            { name = 'Chocobo Raising',   cmd = '!chocoboraising',    desc = 'Chocobo raising debug menu',            args = {} },
            { name = 'Monstrosity',       cmd = '!monstrosity',       desc = 'Monstrosity debug menu',                args = {} },
            { name = 'Get Local Vars',    cmd = '!getlocalvars',      desc = 'Get all local vars of target',          args = {} },
            { name = 'Get TA Target',     cmd = '!getta',             desc = 'Show trick attack target entity',       args = {} },
            { name = 'Get WS Points',     cmd = '!getwspoints',       desc = 'Show weapon skill points',              args = {{ name = 'Slot', type = 'string' }} },
            { name = 'Get Prev Zoneline', cmd = '!getprevzoneline',   desc = 'Get last zoneline ID',                  args = {} },
        },
    },
};

return commands;
