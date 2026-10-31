class_name Names
extends RefCounted
## Surnames for AI soldiers (Soldier.person_name), by nationality, so a squadmate reads as a
## person ("Martinez: Reloading!", MARTINEZ on the name tape) instead of a callsign. Each pool
## is that country's most common surnames (US census, ONS/England and Wales, Canadian lists),
## so the mix looks like a real unit. The node keeps its callsign (Alpha, Bravo...) for code.
##
## A side's soldiers draw from its NATIONS by weight: the player's PMC hires mostly American,
## then British and Canadian contractors (Captain: allies USA, GB, Canada). Hostiles are the
## early game's insurgents; RUSSIAN, CHINESE and IRANIAN are there for the regional factions
## (wave 6). A name is seeded by the soldier's callsign, so it's the same every time, and a
## side never repeats one (pick).

const US: Array[String] = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
	"Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor",
	"Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark",
	"Ramirez", "Lewis", "Robinson", "Walker", "Young", "Allen", "King", "Wright", "Scott", "Torres",
	"Nguyen", "Hill", "Flores", "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell",
	"Mitchell", "Carter", "Roberts", "Gomez", "Phillips", "Evans", "Turner", "Diaz", "Parker", "Cruz",
	"Edwards", "Collins", "Reyes", "Stewart", "Morris", "Morales", "Murphy", "Cook", "Rogers", "Gutierrez",
	"Ortiz", "Morgan", "Cooper", "Peterson", "Bailey", "Reed", "Kelly", "Howard", "Ramos", "Kim", "Cox",
	"Ward", "Richardson", "Watson", "Brooks", "Chavez", "Wood", "James", "Bennett", "Gray", "Mendoza",
	"Ruiz", "Hughes", "Price", "Alvarez", "Castillo", "Sanders", "Patel", "Myers", "Long", "Ross", "Foster"]
const UK: Array[String] = ["Smith", "Jones", "Williams", "Taylor", "Brown", "Davies", "Evans", "Wilson",
	"Thomas", "Johnson", "Roberts", "Robinson", "Thompson", "Wright", "Walker", "White", "Edwards", "Hughes",
	"Green", "Hall", "Lewis", "Harris", "Clarke", "Patel", "Jackson", "Wood", "Turner", "Martin", "Cooper",
	"Hill", "Ward", "Morris", "Moore", "Clark", "Lee", "King", "Baker", "Harrison", "Morgan", "Allen",
	"James", "Scott", "Phillips", "Watson", "Davis", "Parker", "Price", "Bennett", "Young", "Griffiths",
	"Mitchell", "Kelly", "Cook", "Carter", "Richardson", "Bailey", "Collins", "Bell", "Shaw", "Murphy",
	"Miller", "Cox", "Richards", "Khan", "Marshall", "Anderson", "Simpson", "Ellis", "Adams", "Singh",
	"Wilkinson", "Foster", "Chapman", "Powell", "Webb", "Rogers", "Gray", "Mason", "Ali", "Hunt",
	"Hussain", "Campbell", "Matthews", "Owen", "Palmer", "Holmes", "Mills", "Barnes", "Knight", "Lloyd",
	"Butler", "Russell", "Barker", "Fisher", "Stevens", "Jenkins", "Murray", "Dixon", "Harvey"]
const CANADA: Array[String] = ["Smith", "Brown", "Tremblay", "Martin", "Roy", "Wilson", "MacDonald", "Gagnon",
	"Johnson", "Taylor", "Cote", "Campbell", "Anderson", "Leblanc", "Lee", "Jones", "White", "Williams",
	"Miller", "Thompson", "Gauthier", "Young", "Morin", "Bouchard", "Scott", "Stewart", "Belanger", "Reid",
	"Pelletier", "Moore", "Lavoie", "King", "Robinson", "Levesque", "Murphy", "Fortin", "Gagne", "Wong",
	"Clark", "Johnston", "Clarke", "Ross", "Walker", "Thomas", "Boucher", "Landry", "Kelly", "Bergeron",
	"Chen", "Fraser", "Singh", "Ouellet", "Girard", "Patel", "Wright", "Simard", "Boivin", "Caron",
	"Beaulieu", "Cloutier", "Dube", "Poirier", "Fournier", "Lapointe", "Leclerc", "Lefebvre", "Mercier",
	"Paquette", "Richard", "MacLeod", "McDonald", "Graham", "Hall", "Grant", "Mackenzie", "Cameron", "Kerr"]
const INSURGENT: Array[String] = ["Hassan", "Hussein", "Ahmadi", "Rahimi", "Karimi", "Haidari", "Mohammadi",
	"Saleh", "Khalil", "Mahmoud", "Nasser", "Ibrahim", "Yousef", "Abbas", "Jaber", "Darwish", "Haddad",
	"Qasim", "Rashid", "Sultani", "Popal", "Zadran", "Noorzai", "Wardak", "Safi", "Durrani", "Barakzai",
	"Kakar", "Mansour", "Aziz", "Hamdan", "Obeidi", "Jubouri", "Dulaimi", "Tamimi", "Shammari", "Zubaidi",
	"Omar", "Farouk", "Habib", "Latif", "Malik", "Nouri", "Qadir", "Sharif", "Wahid",
	"Zaman", "Hakimi", "Jalali", "Mangal", "Niazi", "Samadi", "Tokhi", "Yusufzai"]
const RUSSIAN: Array[String] = ["Ivanov", "Smirnov", "Kuznetsov", "Popov", "Vasilyev", "Petrov", "Sokolov",
	"Mikhailov", "Novikov", "Fyodorov", "Morozov", "Volkov", "Alekseyev", "Lebedev", "Semyonov", "Yegorov",
	"Pavlov", "Kozlov", "Stepanov", "Nikolayev", "Orlov", "Andreyev", "Makarov", "Nikitin", "Zakharov",
	"Zaitsev", "Solovyov", "Borisov", "Yakovlev", "Grigoryev", "Romanov", "Vorobyov", "Sergeyev", "Frolov"]
const CHINESE: Array[String] = ["Wang", "Li", "Zhang", "Liu", "Chen", "Yang", "Huang", "Zhao", "Wu", "Zhou",
	"Xu", "Sun", "Ma", "Zhu", "Hu", "Guo", "He", "Gao", "Lin", "Luo", "Zheng", "Liang", "Xie", "Song", "Tang",
	"Han", "Feng", "Deng", "Cao", "Peng", "Zeng", "Xiao", "Tian", "Dong", "Pan", "Yuan", "Cai", "Jiang"]
const IRANIAN: Array[String] = ["Mohammadi", "Hosseini", "Ahmadi", "Rezaei", "Moradi", "Karimi", "Hashemi",
	"Rahimi", "Mousavi", "Jafari", "Ghasemi", "Sadeghi", "Rostami", "Heidari", "Salehi", "Kazemi",
	"Abbasi", "Najafi", "Akbari", "Hosseinzadeh", "Mirzaei", "Shirazi", "Tehrani", "Farahani", "Esfahani",
	"Nouri", "Bagheri", "Taheri", "Soltani", "Ebrahimi", "Asadi", "Yazdani", "Zare", "Amini", "Kamali"]

## Surname pools by nationality id (Soldier.nation).
const POOLS := {
	"US": US, "UK": UK, "CA": CANADA, "insurgent": INSURGENT, "RU": RUSSIAN, "CN": CHINESE, "IR": IRANIAN,
}
## Which nationalities a side draws from, by weight.
const NATIONS := {
	&"friendly": [["US", 0.6], ["UK", 0.25], ["CA", 0.15]],
	&"hostile": [["insurgent", 1.0]],
}


## A nationality and surname for the soldier `callsign` of `faction`: {"nation", "name"}, the
## name not in `taken` (a side's names so far). The same callsign gets the same every time,
## unless that name's already taken.
static func pick(faction: StringName, callsign: String, taken: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("name:%s:%s" % [faction, callsign])
	var nations: Array = NATIONS.get(faction, NATIONS[&"hostile"])
	for attempt in 50:
		var roll := rng.randf()
		var nation: String = nations[nations.size() - 1][0]
		for entry: Array in nations:
			roll -= float(entry[1])
			if roll <= 0.0:
				nation = entry[0]
				break
		var pool: Array = POOLS[nation]
		var surname: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not taken.has(surname):
			return {"nation": nation, "name": surname}
	return {"nation": String(nations[0][0]), "name": callsign}  # every name tried was taken


## A woman's form of `surname` where the language marks it: Russian -ov, -ev, -in take an "a"
## (Ivanov, Ivanova).
static func feminine(surname: String, nation: String) -> String:
	if nation == "RU" and (surname.ends_with("ov") or surname.ends_with("ev") or surname.ends_with("in")):
		return surname + "a"
	return surname


# --- Whole people (the company's hires) ---------------------------------------------------

## Body types (CharacterModel.body; VoxelArt on the female-model branch uses the same strings).
const MALE := "male"
const FEMALE := "female"
## Given names for hired contractors, by nationality and body: common given names of people
## of service age in each country (US SSA, ONS England and Wales, Canadian lists, 1985-2000).
const FIRST := {
	"US": {MALE: ["Michael", "Christopher", "Matthew", "Joshua", "David", "James", "Daniel", "Robert", "John",
		"Joseph", "Andrew", "Ryan", "Brandon", "Jason", "Justin", "William", "Jonathan", "Brian", "Anthony",
		"Kevin", "Eric", "Tyler", "Kyle", "Adam", "Nicholas", "Marcus", "Luis", "Carlos", "Jose", "Derek"],
		FEMALE: ["Jessica", "Ashley", "Jennifer", "Amanda", "Sarah", "Stephanie", "Nicole", "Heather", "Elizabeth",
		"Megan", "Melissa", "Lauren", "Rachel", "Amber", "Danielle", "Brittany", "Samantha", "Maria", "Vanessa", "Kayla"]},
	"UK": {MALE: ["James", "Daniel", "Thomas", "Matthew", "Christopher", "Adam", "Luke", "Michael", "Ryan", "Jack",
		"Andrew", "David", "Benjamin", "Liam", "Joshua", "Robert", "Craig", "Lee", "Mark", "Scott", "Jamie",
		"Callum", "Connor", "Gareth", "Rhys", "Owen", "Stuart", "Dean", "Ross", "Ashley"],
		FEMALE: ["Sarah", "Laura", "Emma", "Rebecca", "Gemma", "Claire", "Charlotte", "Amy", "Hannah", "Lauren",
		"Sophie", "Jessica", "Katie", "Rachel", "Emily", "Chloe", "Natalie", "Victoria", "Jodie", "Kirsty"]},
	"CA": {MALE: ["Michael", "Matthew", "Ryan", "Andrew", "Kevin", "Justin", "Tyler", "Daniel", "Jonathan", "Kyle",
		"Jordan", "Brandon", "Mathieu", "Alexandre", "Maxime", "Luc", "Jean-Philippe", "Patrick", "Sean", "Eric",
		"Mark", "Dylan", "Nathan", "Cody", "Marc-Andre", "Simon", "Olivier", "Travis", "Derek", "Shane"],
		FEMALE: ["Jessica", "Ashley", "Sarah", "Amanda", "Stephanie", "Jennifer", "Emily", "Samantha", "Melissa",
		"Megan", "Laura", "Julie", "Caroline", "Marie-Eve", "Catherine", "Vanessa", "Kayla", "Brittany", "Chelsea", "Kristen"]},
}


## A whole person for `faction`, drawn from `rng` (the hiring board's): {"first", "surname",
## "nation", "left", "body"}. The surname avoids `taken` where it can (Roster.add_member makes
## it unique in the company in the end). `role` (Roles) is for the body type.
static func person(rng: RandomNumberGenerator, faction: StringName, role: StringName, taken := {}) -> Dictionary:
	var nations: Array = NATIONS.get(faction, NATIONS[&"friendly"])
	var nation: String = nations[nations.size() - 1][0]
	var roll := rng.randf()
	for entry: Array in nations:
		roll -= float(entry[1])
		if roll <= 0.0:
			nation = entry[0]
			break
	var pool: Array = POOLS[nation]
	var surname: String = pool[rng.randi_range(0, pool.size() - 1)]
	for attempt in 20:
		if not taken.has(surname):
			break
		surname = pool[rng.randi_range(0, pool.size() - 1)]
	var body := body_for(nation, role, rng)
	if body == FEMALE:
		surname = feminine(surname, nation)  # Ivanova
	var firsts: Array = (FIRST.get(nation, FIRST["US"]) as Dictionary)[body]
	return {"first": String(firsts[rng.randi_range(0, firsts.size() - 1)]), "surname": surname, "nation": nation,
		"left": rng.randf() < Handedness.LEFT_SHARE, "body": body}


## The body type of a hire from `nation` in `role`: a woman at that force's share for the role
## (Demographics: a medic at the nation's overall share, other roles less).
static func body_for(nation: String, role: StringName, rng: RandomNumberGenerator) -> String:
	return FEMALE if rng.randf() < Demographics.female_chance(nation, role) else MALE


# --- The people a mission puts in a zone (wave 4B) -----------------------------------------

## Given names of the people in the zones (HVTs, hostages, civilians), by nationality and
## body, for the nations FIRST doesn't cover: "insurgent" is the region's own people (common
## Arabic, Pashto and Dari names), and the regional factions' nations (wave 6).
const LOCAL_FIRST := {
	"insurgent": {MALE: ["Ahmad", "Mohammad", "Abdullah", "Mahmoud", "Hamid", "Karim", "Omar", "Yusuf", "Tariq",
		"Bilal", "Idris", "Farid", "Nasir", "Rahim", "Jamal", "Khalid", "Walid", "Haroun", "Sami", "Zaid",
		"Qasim", "Rashid", "Hakim", "Faisal", "Gul", "Najib", "Wahid", "Shafiq", "Aziz", "Saber"],
		FEMALE: ["Fatima", "Samira", "Leila", "Mariam", "Huda", "Rania", "Nadia", "Salma", "Amina", "Zainab",
		"Farah", "Layla", "Noor", "Hana", "Shirin", "Malalai", "Parwana", "Zahra", "Soraya", "Yasmin"]},
	"RU": {MALE: ["Aleksandr", "Dmitry", "Sergei", "Andrei", "Alexei", "Ivan", "Mikhail", "Nikolai", "Pavel", "Viktor"],
		FEMALE: ["Anna", "Elena", "Olga", "Natalia", "Tatiana", "Irina", "Svetlana", "Maria", "Yulia", "Ekaterina"]},
	"CN": {MALE: ["Wei", "Jun", "Lei", "Tao", "Jie", "Peng", "Hao", "Bo", "Gang", "Ming"],
		FEMALE: ["Fang", "Jing", "Li", "Min", "Yan", "Hong", "Xia", "Mei", "Lan", "Ying"]},
	"IR": {MALE: ["Ali", "Reza", "Hossein", "Mehdi", "Hamid", "Saeed", "Amir", "Javad", "Majid", "Davood"],
		FEMALE: ["Maryam", "Zahra", "Fatemeh", "Sara", "Narges", "Leila", "Shirin", "Parisa", "Azadeh", "Mina"]},
}
## Hostages come from anywhere: aid workers, engineers and journalists from the allied
## countries, and people of the region itself.
const HOSTAGE_NATIONS := [["US", 0.3], ["UK", 0.2], ["CA", 0.15], ["insurgent", 0.35]]


## The nationality a faction's people are from: its kit's in that zone ("" = the zone being
## played; the Eastern Concord Forces' are Russian, Iranian or Chinese by region, wave 6b), else
## data/factions.json "nation" (the early game's hostiles are insurgents).
static func faction_nation(faction_id: String, zone_id := "") -> String:
	var by_kit := Kits.nation(Kits.kit_of(faction_id, zone_id))
	return by_kit if by_kit != "" else String(MissionRegistry.faction(faction_id).get("nation", "insurgent"))


## The nationality of a region's own people (data/contracts.json regions' "nation").
static func region_nation(region_id: String) -> String:
	return String(MissionRegistry.region(region_id).get("nation", "insurgent"))


## A whole name ("Qasim Rahimi") for someone a mission puts in a zone, drawn from `rng`: an
## HVT ("hvt") of `nation` (the target faction's), a hostage ("hostage") of any of
## HOSTAGE_NATIONS, a civilian ("civilian") of `nation` (the region's). `body` is MALE or
## FEMALE (people bodies are male for now). Not one of `taken` where it can help it.
static func mission_person(rng: RandomNumberGenerator, who: String, nation := "insurgent", body := MALE, taken := {}) -> String:
	var name := ""
	for attempt in 20:
		var n := nation
		if who == "hostage":
			var roll := rng.randf()
			n = HOSTAGE_NATIONS[HOSTAGE_NATIONS.size() - 1][0]
			for entry: Array in HOSTAGE_NATIONS:
				roll -= float(entry[1])
				if roll <= 0.0:
					n = entry[0]
					break
		if not POOLS.has(n):
			n = "insurgent"
		var pool: Array = POOLS[n]
		var surname := String(pool[rng.randi_range(0, pool.size() - 1)])
		if body == FEMALE:
			surname = feminine(surname, n)
		var firsts: Array = ((FIRST.get(n, LOCAL_FIRST.get(n, LOCAL_FIRST["insurgent"])) as Dictionary)[body])
		name = "%s %s" % [firsts[rng.randi_range(0, firsts.size() - 1)], surname]
		if not taken.has(name):
			break
	return name
