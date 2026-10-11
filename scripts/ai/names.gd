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
	var firsts: Array = (FIRST.get(nation, FIRST["US"]) as Dictionary)[body]
	return {"first": String(firsts[rng.randi_range(0, firsts.size() - 1)]), "surname": surname, "nation": nation,
		"left": rng.randf() < Handedness.LEFT_SHARE, "body": body}


## The body type of a hire from `nation` in `role`. Always MALE here; the female-model branch
## decides it by its Demographics instead (this is the one place it changes).
static func body_for(_nation: String, _role: StringName, _rng: RandomNumberGenerator) -> String:
	return MALE
