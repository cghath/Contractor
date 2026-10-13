extends ZoneLevel
## The supports suite's zone: a ZoneLevel whose weather the test sets (Supports.can_fly asks a
## level's weather_grounds_aircraft, wave 7's hook). Joining clients load a plain ZoneLevel
## from the same definition.

var storm := false


func weather_grounds_aircraft() -> bool:
	return storm
