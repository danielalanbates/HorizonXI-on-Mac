--[[
    GM Tools v1.0.4 - Job Gear Definitions
    Per-job gear sets organized by equipment slot.
    Each slot supports multiple items for multi-set loadouts.
    All item IDs verified against LSB item_basic.sql and item_equipment.sql.

    Slot order matches FFXI equipment layout:
        Main, Sub, Range, Ammo, Head, Body, Hands, Legs, Feet,
        Neck, Waist, Ear1, Ear2, Ring1, Ring2, Back

    Users can customize loadouts via the UI and save to SQLite.
]]--

require 'common';

local jobgear = {};

-- Equipment slot display order (16 FFXI slots)
jobgear.slot_order = T{
    'Main', 'Sub', 'Range', 'Ammo',
    'Head', 'Body', 'Hands', 'Legs', 'Feet',
    'Neck', 'Waist', 'Ear1', 'Ear2', 'Ring1', 'Ring2', 'Back',
};

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------

-- Deep copy a slots table (returns new table with T{} for each slot)
function jobgear.copy_slots(slots)
    local copy = {};
    for _, name in ipairs(jobgear.slot_order) do
        copy[name] = T{};
        if (slots[name] ~= nil) then
            for _, item in ipairs(slots[name]) do
                copy[name]:append({ id = item.id, name = item.name });
            end
        end
    end
    return copy;
end

-- Build !additem commands for all items in a slots table
function jobgear.build_commands(slots)
    local cmds = T{};
    for _, slot_name in ipairs(jobgear.slot_order) do
        local items = slots[slot_name];
        if (items ~= nil) then
            for _, item in ipairs(items) do
                cmds:append(('!additem %d 1'):fmt(item.id));
            end
        end
    end
    return cmds;
end

-- Count total items across all slots
function jobgear.count_items(slots)
    local count = 0;
    for _, slot_name in ipairs(jobgear.slot_order) do
        if (slots[slot_name] ~= nil) then
            count = count + #slots[slot_name];
        end
    end
    return count;
end

-- Get default slots for a job by name (returns a deep copy)
function jobgear.get_defaults(job_name)
    for _, job in ipairs(jobgear.jobs) do
        if (job.name == job_name) then
            return jobgear.copy_slots(job.slots);
        end
    end
    return nil;
end

-------------------------------------------------------------------------------
-- Per-Job Gear Definitions
-- Weapon slot assignments:
--   Main = primary weapon (1H sword, 2H greatsword, H2H, etc.)
--   Sub  = off-hand (shield, grip, dual-wield weapon)
--   Range = ranged weapon (bow, gun, crossbow)
--   Ammo = ammo/throwing items
-- Armor mapped to Head/Body/Hands/Legs/Feet slots.
-- Accessories mapped to Neck/Waist/Ear1/Ear2/Ring1/Ring2.
-- Back = JSE Ambuscade cape (job-specific).
-------------------------------------------------------------------------------

jobgear.jobs = T{
    -- WAR: Bravura(GA), Ragnarok(GS), Naegling(Sword); Sakpata armor; melee acc
    {
        id = 1, name = 'WAR', full_name = 'Warrior',
        slots = {
            Main  = T{ {id=20835, name='Bravura 119'}, {id=21683, name='Ragnarok 119 III'}, {id=21621, name='Naegling'} },
            Sub   = T{ {id=22217, name='Kaja Grip'} },
            Ammo  = T{ {id=22281, name='Knobkierrie'}, {id=21431, name='Coiste Bodhar'} },
            Head  = T{ {id=23757, name="Sakpata's Helm"} },
            Body  = T{ {id=23764, name="Sakpata's Plate"} },
            Hands = T{ {id=23771, name="Sakpata's Gauntlets"} },
            Legs  = T{ {id=23778, name="Sakpata's Cuisses"} },
            Feet  = T{ {id=23785, name="Sakpata's Leggings"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26246, name="Cichol's Mantle"} },
        },
    },
    -- MNK: Spharai(H2H), Godhands(H2H), Karambit(H2H); Mpaca armor; melee acc
    {
        id = 2, name = 'MNK', full_name = 'Monk',
        slots = {
            Main  = T{ {id=20509, name='Spharai 119 III'}, {id=20515, name='Godhands'}, {id=21519, name='Karambit'} },
            Ammo  = T{ {id=21431, name='Coiste Bodhar'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=23758, name="Mpaca's Cap"} },
            Body  = T{ {id=23765, name="Mpaca's Doublet"} },
            Hands = T{ {id=23772, name="Mpaca's Gloves"} },
            Legs  = T{ {id=23779, name="Mpaca's Hose"} },
            Feet  = T{ {id=23786, name="Mpaca's Boots"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26247, name="Segomo's Mantle"} },
        },
    },
    -- WHM: Yagrush(Club), Mjollnir(Club), Maxentius(Club); Bunzi armor; mage acc
    {
        id = 3, name = 'WHM', full_name = 'White Mage',
        slots = {
            Main  = T{ {id=21078, name='Yagrush 119 III'}, {id=21060, name='Mjollnir 119'}, {id=22031, name='Maxentius'} },
            Ammo  = T{ {id=22271, name='Pemphredo Tathlum'}, {id=21345, name='Focal Orb'} },
            Head  = T{ {id=23760, name="Bunzi's Hat"} },
            Body  = T{ {id=23767, name="Bunzi's Robe"} },
            Hands = T{ {id=23774, name="Bunzi's Gloves"} },
            Legs  = T{ {id=23781, name="Bunzi's Pants"} },
            Feet  = T{ {id=23788, name="Bunzi's Sabots"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26248, name="Alaunus's Cape"} },
        },
    },
    -- BLM: Claustrum(Staff), Bunzi's Rod(Club), Mpaca's Staff; Nyame armor; mage acc
    {
        id = 4, name = 'BLM', full_name = 'Black Mage',
        slots = {
            Main  = T{ {id=22060, name='Claustrum 119 III'}, {id=22041, name="Bunzi's Rod"}, {id=22100, name="Mpaca's Staff"} },
            Ammo  = T{ {id=21344, name='Ghastly Tathlum +1'}, {id=22271, name='Pemphredo Tathlum'} },
            Head  = T{ {id=23761, name='Nyame Helm'} },
            Body  = T{ {id=23768, name='Nyame Mail'} },
            Hands = T{ {id=23775, name='Nyame Gauntlets'} },
            Legs  = T{ {id=23782, name='Nyame Flanchard'} },
            Feet  = T{ {id=23789, name='Nyame Sollerets'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26249, name="Taranus's Cape"} },
        },
    },
    -- RDM: Naegling(Sword), Sequence(Sword), Almace(Sword), Murgleis(Sword); Ayanmo armor; mage acc
    {
        id = 5, name = 'RDM', full_name = 'Red Mage',
        slots = {
            Main  = T{ {id=21621, name='Naegling'}, {id=20695, name='Sequence'}, {id=20689, name='Almace 119'}, {id=20647, name='Murgleis 119'} },
            Ammo  = T{ {id=22271, name='Pemphredo Tathlum'}, {id=22298, name='Aurgelmir Orb +1'} },
            Head  = T{ {id=25572, name='Ayanmo Zucchetto +2'} },
            Body  = T{ {id=25795, name='Ayanmo Corazza +2'} },
            Hands = T{ {id=25833, name='Ayanmo Manopolas +2'} },
            Legs  = T{ {id=25884, name='Ayanmo Cosciales +2'} },
            Feet  = T{ {id=25951, name='Ayanmo Gambieras +2'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26250, name="Sucellos's Cape"} },
        },
    },
    -- THF: Mandau(Dagger), Aeneas(Dagger), Tauret(Dagger); Mummu armor; melee acc
    {
        id = 6, name = 'THF', full_name = 'Thief',
        slots = {
            Main  = T{ {id=20583, name='Mandau 119 III'}, {id=20594, name='Aeneas'}, {id=21565, name='Tauret'} },
            Ammo  = T{ {id=22298, name='Aurgelmir Orb +1'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=25570, name='Mummu Bonnet +2'} },
            Body  = T{ {id=25798, name='Mummu Jacket +2'} },
            Hands = T{ {id=25836, name='Mummu Wrists +2'} },
            Legs  = T{ {id=25887, name='Mummu Kecks +2'} },
            Feet  = T{ {id=25954, name='Mummu Gamashes +2'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26251, name="Toutatis's Cape"} },
        },
    },
    -- PLD: Excalibur(Sword), Naegling(Sword); Ochain/Aegis shields; Sakpata armor; tank acc
    {
        id = 7, name = 'PLD', full_name = 'Paladin',
        slots = {
            Main  = T{ {id=20685, name='Excalibur 119 III'}, {id=21621, name='Naegling'} },
            Sub   = T{ {id=11926, name='Ochain 99'}, {id=11927, name='Aegis 99'} },
            Ammo  = T{ {id=22279, name='Staunch Tathlum +1'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=23757, name="Sakpata's Helm"} },
            Body  = T{ {id=23764, name="Sakpata's Plate"} },
            Hands = T{ {id=23771, name="Sakpata's Gauntlets"} },
            Legs  = T{ {id=23778, name="Sakpata's Cuisses"} },
            Feet  = T{ {id=23785, name="Sakpata's Leggings"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26209, name='Ayanmo Ring'} },
            Back  = T{ {id=26252, name="Rudianos's Mantle"} },
        },
    },
    -- DRK: Apocalypse(Scythe), Anguta(Scythe), Caladbolg(GS), Liberator(Scythe); Sakpata armor; melee acc
    {
        id = 8, name = 'DRK', full_name = 'Dark Knight',
        slots = {
            Main  = T{ {id=21808, name='Apocalypse 119 III'}, {id=20890, name='Anguta'}, {id=20747, name='Caladbolg'}, {id=20882, name='Liberator 119'} },
            Sub   = T{ {id=22217, name='Kaja Grip'} },
            Ammo  = T{ {id=21431, name='Coiste Bodhar'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=23757, name="Sakpata's Helm"} },
            Body  = T{ {id=23764, name="Sakpata's Plate"} },
            Hands = T{ {id=23771, name="Sakpata's Gauntlets"} },
            Legs  = T{ {id=23778, name="Sakpata's Cuisses"} },
            Feet  = T{ {id=23785, name="Sakpata's Leggings"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26253, name="Ankou's Mantle"} },
        },
    },
    -- BST: Aymur(Axe), Dolichenus(Axe), Kaja Axe; Gleti armor; melee acc
    {
        id = 9, name = 'BST', full_name = 'Beastmaster',
        slots = {
            Main  = T{ {id=20792, name='Aymur 119'}, {id=21722, name='Dolichenus'}, {id=21721, name='Kaja Axe'} },
            Ammo  = T{ {id=21371, name='Ginsen'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=23756, name="Gleti's Mask"} },
            Body  = T{ {id=23763, name="Gleti's Cuirass"} },
            Hands = T{ {id=23770, name="Gleti's Gauntlets"} },
            Legs  = T{ {id=23777, name="Gleti's Breeches"} },
            Feet  = T{ {id=23784, name="Gleti's Boots"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26254, name="Artio's Mantle"} },
        },
    },
    -- BRD: Carnwenhan(Dagger), Naegling(Sword), Tauret(Dagger); Nyame armor; mage acc
    {
        id = 10, name = 'BRD', full_name = 'Bard',
        slots = {
            Main  = T{ {id=20561, name='Carnwenhan 119'}, {id=21621, name='Naegling'}, {id=21565, name='Tauret'} },
            Ammo  = T{ {id=21345, name='Focal Orb'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=23761, name='Nyame Helm'} },
            Body  = T{ {id=23768, name='Nyame Mail'} },
            Hands = T{ {id=23775, name='Nyame Gauntlets'} },
            Legs  = T{ {id=23782, name='Nyame Flanchard'} },
            Feet  = T{ {id=23789, name='Nyame Sollerets'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26255, name="Intarabus's Cape"} },
        },
    },
    -- RNG: Yoichinoyumi(Bow), Annihilator(Gun), Gastraphetes(Xbow); Malignance armor; ranged acc
    {
        id = 11, name = 'RNG', full_name = 'Ranger',
        slots = {
            Range = T{ {id=22115, name='Yoichinoyumi 119 III'}, {id=21267, name='Annihilator 119 III'}, {id=21266, name='Gastraphetes 119 III'} },
            Ammo  = T{ {id=21297, name='Chrono Arrow'}, {id=21299, name="Yoichi's Arrow"}, {id=21296, name='Chrono Bullet'} },
            Head  = T{ {id=23732, name='Malignance Chapeau'} },
            Body  = T{ {id=23733, name='Malignance Tabard'} },
            Hands = T{ {id=23734, name='Malignance Gloves'} },
            Legs  = T{ {id=23735, name='Malignance Tights'} },
            Feet  = T{ {id=23736, name='Malignance Boots'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=27541, name='Cessance Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26205, name='Meghanada Ring'} },
            Back  = T{ {id=26256, name="Belenus's Cape"} },
        },
    },
    -- SAM: Amanomurakumo(GK), Dojikiri(GK), Shining One(Polearm); Flamma armor; melee acc
    {
        id = 12, name = 'SAM', full_name = 'Samurai',
        slots = {
            Main  = T{ {id=21954, name='Amanomurakumo 119 III'}, {id=21025, name='Dojikiri Yasutsuna'}, {id=21883, name='Shining One'} },
            Sub   = T{ {id=22217, name='Kaja Grip'} },
            Ammo  = T{ {id=22281, name='Knobkierrie'}, {id=21431, name='Coiste Bodhar'} },
            Head  = T{ {id=25569, name='Flamma Zucchetto +2'} },
            Body  = T{ {id=25797, name='Flamma Korazin +2'} },
            Hands = T{ {id=25835, name='Flamma Manopolas +2'} },
            Legs  = T{ {id=25886, name='Flamma Dirs +2'} },
            Feet  = T{ {id=25953, name='Flamma Gambieras +2'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26257, name="Smertrios's Mantle"} },
        },
    },
    -- NIN: Kikoku(Katana), Heishi(Katana); Tauret off-hand; Malignance armor; melee acc
    {
        id = 13, name = 'NIN', full_name = 'Ninja',
        slots = {
            Main  = T{ {id=21906, name='Kikoku 119 III'}, {id=20977, name='Heishi Shorinken'} },
            Sub   = T{ {id=21565, name='Tauret'} },
            Ammo  = T{ {id=22298, name='Aurgelmir Orb +1'}, {id=22255, name='Seething Bomblet +1'} },
            Head  = T{ {id=23732, name='Malignance Chapeau'} },
            Body  = T{ {id=23733, name='Malignance Tabard'} },
            Hands = T{ {id=23734, name='Malignance Gloves'} },
            Legs  = T{ {id=23735, name='Malignance Tights'} },
            Feet  = T{ {id=23736, name='Malignance Boots'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26258, name="Andartia's Mantle"} },
        },
    },
    -- DRG: Gungnir(Polearm), Trishula(Polearm), Shining One(Polearm); Flamma armor; melee acc
    {
        id = 14, name = 'DRG', full_name = 'Dragoon',
        slots = {
            Main  = T{ {id=21857, name='Gungnir 119 III'}, {id=20935, name='Trishula'}, {id=21883, name='Shining One'} },
            Ammo  = T{ {id=22281, name='Knobkierrie'}, {id=21431, name='Coiste Bodhar'} },
            Head  = T{ {id=25569, name='Flamma Zucchetto +2'} },
            Body  = T{ {id=25797, name='Flamma Korazin +2'} },
            Hands = T{ {id=25835, name='Flamma Manopolas +2'} },
            Legs  = T{ {id=25886, name='Flamma Dirs +2'} },
            Feet  = T{ {id=25953, name='Flamma Gambieras +2'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26259, name="Brigantia's Mantle"} },
        },
    },
    -- SMN: Nirvana(Staff), Mpaca's Staff, Kaja Staff; Bunzi armor; mage acc
    {
        id = 15, name = 'SMN', full_name = 'Summoner',
        slots = {
            Main  = T{ {id=21141, name='Nirvana 119'}, {id=22100, name="Mpaca's Staff"}, {id=22085, name='Kaja Staff'} },
            Ammo  = T{ {id=21345, name='Focal Orb'}, {id=22255, name='Seething Bomblet +1'} },
            Head  = T{ {id=23760, name="Bunzi's Hat"} },
            Body  = T{ {id=23767, name="Bunzi's Robe"} },
            Hands = T{ {id=23774, name="Bunzi's Gloves"} },
            Legs  = T{ {id=23781, name="Bunzi's Pants"} },
            Feet  = T{ {id=23788, name="Bunzi's Sabots"} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26260, name="Campestres's Cape"} },
        },
    },
    -- BLU: Tizona(Sword), Naegling(Sword); Sequence off-hand; Ayanmo armor; melee acc
    {
        id = 16, name = 'BLU', full_name = 'Blue Mage',
        slots = {
            Main  = T{ {id=20651, name='Tizona 119'}, {id=21621, name='Naegling'} },
            Sub   = T{ {id=20695, name='Sequence'} },
            Ammo  = T{ {id=22298, name='Aurgelmir Orb +1'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=25572, name='Ayanmo Zucchetto +2'} },
            Body  = T{ {id=25795, name='Ayanmo Corazza +2'} },
            Hands = T{ {id=25833, name='Ayanmo Manopolas +2'} },
            Legs  = T{ {id=25884, name='Ayanmo Cosciales +2'} },
            Feet  = T{ {id=25951, name='Ayanmo Gambieras +2'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26261, name="Rosmerta's Cape"} },
        },
    },
    -- COR: Naegling(Sword) main, Tauret(Dagger) off-hand; Death Penalty(Gun) ranged; Malignance armor; ranged acc
    {
        id = 17, name = 'COR', full_name = 'Corsair',
        slots = {
            Main  = T{ {id=21621, name='Naegling'} },
            Sub   = T{ {id=21565, name='Tauret'} },
            Range = T{ {id=21262, name='Death Penalty 119'} },
            Ammo  = T{ {id=21296, name='Chrono Bullet'}, {id=21334, name='Animikii Bullet'}, {id=26350, name='Chrono Bullet Pouch'} },
            Head  = T{ {id=23732, name='Malignance Chapeau'} },
            Body  = T{ {id=23733, name='Malignance Tabard'} },
            Hands = T{ {id=23734, name='Malignance Gloves'} },
            Legs  = T{ {id=23735, name='Malignance Tights'} },
            Feet  = T{ {id=23736, name='Malignance Boots'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=27541, name='Cessance Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26205, name='Meghanada Ring'} },
            Back  = T{ {id=26262, name="Camulus's Mantle"} },
        },
    },
    -- PUP: Kenkonken(H2H), Godhands(H2H), Karambit(H2H); Nyame armor; melee acc
    {
        id = 18, name = 'PUP', full_name = 'Puppetmaster',
        slots = {
            Main  = T{ {id=20484, name='Kenkonken 119'}, {id=20515, name='Godhands'}, {id=21519, name='Karambit'} },
            Ammo  = T{ {id=21431, name='Coiste Bodhar'}, {id=22298, name='Aurgelmir Orb +1'} },
            Head  = T{ {id=23761, name='Nyame Helm'} },
            Body  = T{ {id=23768, name='Nyame Mail'} },
            Hands = T{ {id=23775, name='Nyame Gauntlets'} },
            Legs  = T{ {id=23782, name='Nyame Flanchard'} },
            Feet  = T{ {id=23789, name='Nyame Sollerets'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26263, name="Visucius's Mantle"} },
        },
    },
    -- DNC: Terpsichore(Dagger), Aeneas(Dagger); Twashtar off-hand; Malignance armor; melee acc
    {
        id = 19, name = 'DNC', full_name = 'Dancer',
        slots = {
            Main  = T{ {id=20557, name='Terpsichore 119'}, {id=20594, name='Aeneas'} },
            Sub   = T{ {id=20587, name='Twashtar 119'} },
            Ammo  = T{ {id=22298, name='Aurgelmir Orb +1'}, {id=22281, name='Knobkierrie'} },
            Head  = T{ {id=23732, name='Malignance Chapeau'} },
            Body  = T{ {id=23733, name='Malignance Tabard'} },
            Hands = T{ {id=23734, name='Malignance Gloves'} },
            Legs  = T{ {id=23735, name='Malignance Tights'} },
            Feet  = T{ {id=23736, name='Malignance Boots'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=11697, name='Moonshade Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=11651, name="Epona's Ring"} },
            Back  = T{ {id=26264, name="Senuna's Mantle"} },
        },
    },
    -- SCH: Bunzi's Rod(Club), Mpaca's Staff, Kaja Staff; Nyame armor; mage acc
    {
        id = 20, name = 'SCH', full_name = 'Scholar',
        slots = {
            Main  = T{ {id=22041, name="Bunzi's Rod"}, {id=22100, name="Mpaca's Staff"}, {id=22085, name='Kaja Staff'} },
            Ammo  = T{ {id=22271, name='Pemphredo Tathlum'}, {id=21344, name='Ghastly Tathlum +1'} },
            Head  = T{ {id=23761, name='Nyame Helm'} },
            Body  = T{ {id=23768, name='Nyame Mail'} },
            Hands = T{ {id=23775, name='Nyame Gauntlets'} },
            Legs  = T{ {id=23782, name='Nyame Flanchard'} },
            Feet  = T{ {id=23789, name='Nyame Sollerets'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26265, name="Lugh's Cape"} },
        },
    },
    -- GEO: Idris(Club), Maxentius(Club), Bunzi's Rod(Club); Nyame armor; mage acc
    {
        id = 21, name = 'GEO', full_name = 'Geomancer',
        slots = {
            Main  = T{ {id=21070, name='Idris'}, {id=22031, name='Maxentius'}, {id=22041, name="Bunzi's Rod"} },
            Ammo  = T{ {id=22271, name='Pemphredo Tathlum'}, {id=21345, name='Focal Orb'} },
            Head  = T{ {id=23761, name='Nyame Helm'} },
            Body  = T{ {id=23768, name='Nyame Mail'} },
            Hands = T{ {id=23775, name='Nyame Gauntlets'} },
            Legs  = T{ {id=23782, name='Nyame Flanchard'} },
            Feet  = T{ {id=23789, name='Nyame Sollerets'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=11697, name='Moonshade Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26207, name='Inyanga Ring'} },
            Back  = T{ {id=26266, name="Nantosuelta's Cape"} },
        },
    },
    -- RUN: Epeolatry(GS), Lionheart(GS), Naegling(Sword); Nyame armor; tank acc
    {
        id = 22, name = 'RUN', full_name = 'Rune Fencer',
        slots = {
            Main  = T{ {id=20753, name='Epeolatry'}, {id=21694, name='Lionheart'}, {id=21621, name='Naegling'} },
            Sub   = T{ {id=22217, name='Kaja Grip'} },
            Ammo  = T{ {id=22279, name='Staunch Tathlum +1'}, {id=22255, name='Seething Bomblet +1'} },
            Head  = T{ {id=23761, name='Nyame Helm'} },
            Body  = T{ {id=23768, name='Nyame Mail'} },
            Hands = T{ {id=23775, name='Nyame Gauntlets'} },
            Legs  = T{ {id=23782, name='Nyame Flanchard'} },
            Feet  = T{ {id=23789, name='Nyame Sollerets'} },
            Neck  = T{ {id=27510, name='Fotia Gorget'} },
            Waist = T{ {id=28420, name='Fotia Belt'} },
            Ear1  = T{ {id=15965, name='Ethereal Earring'} },
            Ear2  = T{ {id=14813, name='Brutal Earring'} },
            Ring1 = T{ {id=13566, name='Defending Ring'} },
            Ring2 = T{ {id=26209, name='Ayanmo Ring'} },
            Back  = T{ {id=26267, name="Ogma's Cape"} },
        },
    },
};

return jobgear;
