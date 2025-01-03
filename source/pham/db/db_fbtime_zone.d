/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2020 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.db_fbtime_zone;

import pham.dtm.dtm_time_zone : ZoneOffset;
import pham.dtm.dtm_time_zone_map : TimeZoneInfoMap;
import pham.utl.utl_object : singleton;
import pham.db.db_type : uint16;
import pham.db.db_fbisc : FbIscDefaultInt, FbIscDefaultStr;

nothrow @safe:

struct FbTimeZone
{
nothrow @safe:

public:
    this(string name, uint16 id) @nogc pure
    {
        this._name = name;
        this._id = id;
    }

    bool opEquals(scope const(FbTimeZone) rhs) const @nogc pure
    {
        return this._id == rhs._id && this._name == rhs._name;
    }

    pragma(inline, true)
	bool isValid() const @nogc pure
    {
		return _id != 0 && _name.length != 0;
    }

    /*
     * Params:
     *   id = Firebird numeric zone id
     */
    static immutable(FbTimeZone) timeZone(uint16 id)
    {
		return FbTimeZoneList.instance().timeZone(id);
    }

    /*
     * Params:
     *   name = Firebird zone name
     */
    static immutable(FbTimeZone) timeZone(string name)
    {
		return FbTimeZoneList.instance().timeZone(name);
    }    

    /*
     * Params:
     *   id = Firebird numeric zone id
     */
    static ZoneOffset timeZoneBaseUtcOffset(uint16 id)
    {
        return timeZoneMap(id).zoneBaseUtcOffset;
    }
    
    /*
     * Params:
     *   name = Firebird zone name
     */
    static ZoneOffset timeZoneBaseUtcOffset(string name)
    {
        return timeZoneMap(name).zoneBaseUtcOffset;
    }
    
    /*
     * Params:
     *   id = Firebird numeric zone id
     */
    static TimeZoneInfoMap timeZoneMap(uint16 id)
    {
        const nameMap = timeZone(id);
        return nameMap.isValid()
            ? timeZoneMap(nameMap.name)
            : TimeZoneInfoMap.init;
    }

    static TimeZoneInfoMap timeZoneMap(string zoneIdOrName)
    {
        return TimeZoneInfoMap.timeZoneMap(zoneIdOrName);
    }

    size_t toHash() const @nogc pure
    {
        return _id;
    }

    string toString() const @nogc pure
    {
        return _name;
    }

    @property uint16 id() const @nogc pure
    {
        return _id;
    }

    @property string name() const @nogc pure
    {
        return _name;
    }

private:
    string _name;
    uint16 _id;
}

class FbTimeZoneList
{
nothrow @safe:

public:
    this() pure
    {
		this.ids = idDict();
        this.names = nameDict();
    }

    static FbTimeZoneList instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    final immutable(FbTimeZone) timeZone(uint16 id) pure
    {
        if (auto p = id in ids)
            return **p;
        else
            return FbTimeZone.init;
    }

    final immutable(FbTimeZone) timeZone(string name) pure
    {
        if (auto p = name in names)
            return **p;
        else
            return FbTimeZone.init;
    }

	static immutable(FbTimeZone)*[string] nameDict() pure @trusted
    {
		immutable(FbTimeZone)*[string] result;
        foreach (i; 0..timeZones.length)
            result[timeZones[i].name] = &timeZones[i];
		return result;
    }

	static immutable(FbTimeZone)*[uint16] idDict() pure @trusted
    {
		immutable(FbTimeZone)*[uint16] result;
        foreach (i; 0..timeZones.length)
            result[timeZones[i].id] = &timeZones[i];
		return result;
    }

public:
    immutable(FbTimeZone)*[uint16] ids;
    immutable(FbTimeZone)*[string] names;

protected:
    static FbTimeZoneList createInstance() pure
    {
        return new FbTimeZoneList();
    }

private:
	__gshared static FbTimeZoneList _instance;
}

static immutable FbTimeZone[] timeZones = [
	FbTimeZone(FbIscDefaultStr.gmt_zoneName, FbIscDefaultInt.gmt_zoneId),
	FbTimeZone("ACT", 65534),
	FbTimeZone("AET", 65533),
	FbTimeZone("AGT", 65532),
	FbTimeZone("ART", 65531),
	FbTimeZone("AST", 65530),
	FbTimeZone("Africa/Abidjan", 65529),
	FbTimeZone("Africa/Accra", 65528),
	FbTimeZone("Africa/Addis_Ababa", 65527),
	FbTimeZone("Africa/Algiers", 65526),
	FbTimeZone("Africa/Asmara", 65525),
	FbTimeZone("Africa/Asmera", 65524),
	FbTimeZone("Africa/Bamako", 65523),
	FbTimeZone("Africa/Bangui", 65522),
	FbTimeZone("Africa/Banjul", 65521),
	FbTimeZone("Africa/Bissau", 65520),
	FbTimeZone("Africa/Blantyre", 65519),
	FbTimeZone("Africa/Brazzaville", 65518),
	FbTimeZone("Africa/Bujumbura", 65517),
	FbTimeZone("Africa/Cairo", 65516),
	FbTimeZone("Africa/Casablanca", 65515),
	FbTimeZone("Africa/Ceuta", 65514),
	FbTimeZone("Africa/Conakry", 65513),
	FbTimeZone("Africa/Dakar", 65512),
	FbTimeZone("Africa/Dar_es_Salaam", 65511),
	FbTimeZone("Africa/Djibouti", 65510),
	FbTimeZone("Africa/Douala", 65509),
	FbTimeZone("Africa/El_Aaiun", 65508),
	FbTimeZone("Africa/Freetown", 65507),
	FbTimeZone("Africa/Gaborone", 65506),
	FbTimeZone("Africa/Harare", 65505),
	FbTimeZone("Africa/Johannesburg", 65504),
	FbTimeZone("Africa/Juba", 65503),
	FbTimeZone("Africa/Kampala", 65502),
	FbTimeZone("Africa/Khartoum", 65501),
	FbTimeZone("Africa/Kigali", 65500),
	FbTimeZone("Africa/Kinshasa", 65499),
	FbTimeZone("Africa/Lagos", 65498),
	FbTimeZone("Africa/Libreville", 65497),
	FbTimeZone("Africa/Lome", 65496),
	FbTimeZone("Africa/Luanda", 65495),
	FbTimeZone("Africa/Lubumbashi", 65494),
	FbTimeZone("Africa/Lusaka", 65493),
	FbTimeZone("Africa/Malabo", 65492),
	FbTimeZone("Africa/Maputo", 65491),
	FbTimeZone("Africa/Maseru", 65490),
	FbTimeZone("Africa/Mbabane", 65489),
	FbTimeZone("Africa/Mogadishu", 65488),
	FbTimeZone("Africa/Monrovia", 65487),
	FbTimeZone("Africa/Nairobi", 65486),
	FbTimeZone("Africa/Ndjamena", 65485),
	FbTimeZone("Africa/Niamey", 65484),
	FbTimeZone("Africa/Nouakchott", 65483),
	FbTimeZone("Africa/Ouagadougou", 65482),
	FbTimeZone("Africa/Porto-Novo", 65481),
	FbTimeZone("Africa/Sao_Tome", 65480),
	FbTimeZone("Africa/Timbuktu", 65479),
	FbTimeZone("Africa/Tripoli", 65478),
	FbTimeZone("Africa/Tunis", 65477),
	FbTimeZone("Africa/Windhoek", 65476),
	FbTimeZone("America/Adak", 65475),
	FbTimeZone("America/Anchorage", 65474),
	FbTimeZone("America/Anguilla", 65473),
	FbTimeZone("America/Antigua", 65472),
	FbTimeZone("America/Araguaina", 65471),
	FbTimeZone("America/Argentina/Buenos_Aires", 65470),
	FbTimeZone("America/Argentina/Catamarca", 65469),
	FbTimeZone("America/Argentina/ComodRivadavia", 65468),
	FbTimeZone("America/Argentina/Cordoba", 65467),
	FbTimeZone("America/Argentina/Jujuy", 65466),
	FbTimeZone("America/Argentina/La_Rioja", 65465),
	FbTimeZone("America/Argentina/Mendoza", 65464),
	FbTimeZone("America/Argentina/Rio_Gallegos", 65463),
	FbTimeZone("America/Argentina/Salta", 65462),
	FbTimeZone("America/Argentina/San_Juan", 65461),
	FbTimeZone("America/Argentina/San_Luis", 65460),
	FbTimeZone("America/Argentina/Tucuman", 65459),
	FbTimeZone("America/Argentina/Ushuaia", 65458),
	FbTimeZone("America/Aruba", 65457),
	FbTimeZone("America/Asuncion", 65456),
	FbTimeZone("America/Atikokan", 65455),
	FbTimeZone("America/Atka", 65454),
	FbTimeZone("America/Bahia", 65453),
	FbTimeZone("America/Bahia_Banderas", 65452),
	FbTimeZone("America/Barbados", 65451),
	FbTimeZone("America/Belem", 65450),
	FbTimeZone("America/Belize", 65449),
	FbTimeZone("America/Blanc-Sablon", 65448),
	FbTimeZone("America/Boa_Vista", 65447),
	FbTimeZone("America/Bogota", 65446),
	FbTimeZone("America/Boise", 65445),
	FbTimeZone("America/Buenos_Aires", 65444),
	FbTimeZone("America/Cambridge_Bay", 65443),
	FbTimeZone("America/Campo_Grande", 65442),
	FbTimeZone("America/Cancun", 65441),
	FbTimeZone("America/Caracas", 65440),
	FbTimeZone("America/Catamarca", 65439),
	FbTimeZone("America/Cayenne", 65438),
	FbTimeZone("America/Cayman", 65437),
	FbTimeZone("America/Chicago", 65436),
	FbTimeZone("America/Chihuahua", 65435),
    FbTimeZone("America/Ciudad_Juarez", 64899),
	FbTimeZone("America/Coral_Harbour", 65434),
	FbTimeZone("America/Cordoba", 65433),
	FbTimeZone("America/Costa_Rica", 65432),
	FbTimeZone("America/Creston", 65431),
	FbTimeZone("America/Cuiaba", 65430),
	FbTimeZone("America/Curacao", 65429),
	FbTimeZone("America/Danmarkshavn", 65428),
	FbTimeZone("America/Dawson", 65427),
	FbTimeZone("America/Dawson_Creek", 65426),
	FbTimeZone("America/Denver", 65425),
	FbTimeZone("America/Detroit", 65424),
	FbTimeZone("America/Dominica", 65423),
	FbTimeZone("America/Edmonton", 65422),
	FbTimeZone("America/Eirunepe", 65421),
	FbTimeZone("America/El_Salvador", 65420),
	FbTimeZone("America/Ensenada", 65419),
	FbTimeZone("America/Fort_Nelson", 65418),
	FbTimeZone("America/Fort_Wayne", 65417),
	FbTimeZone("America/Fortaleza", 65416),
	FbTimeZone("America/Glace_Bay", 65415),
	FbTimeZone("America/Godthab", 65414),
	FbTimeZone("America/Goose_Bay", 65413),
	FbTimeZone("America/Grand_Turk", 65412),
	FbTimeZone("America/Grenada", 65411),
	FbTimeZone("America/Guadeloupe", 65410),
	FbTimeZone("America/Guatemala", 65409),
	FbTimeZone("America/Guayaquil", 65408),
	FbTimeZone("America/Guyana", 65407),
	FbTimeZone("America/Halifax", 65406),
	FbTimeZone("America/Havana", 65405),
	FbTimeZone("America/Hermosillo", 65404),
	FbTimeZone("America/Indiana/Indianapolis", 65403),
	FbTimeZone("America/Indiana/Knox", 65402),
	FbTimeZone("America/Indiana/Marengo", 65401),
	FbTimeZone("America/Indiana/Petersburg", 65400),
	FbTimeZone("America/Indiana/Tell_City", 65399),
	FbTimeZone("America/Indiana/Vevay", 65398),
	FbTimeZone("America/Indiana/Vincennes", 65397),
	FbTimeZone("America/Indiana/Winamac", 65396),
	FbTimeZone("America/Indianapolis", 65395),
	FbTimeZone("America/Inuvik", 65394),
	FbTimeZone("America/Iqaluit", 65393),
	FbTimeZone("America/Jamaica", 65392),
	FbTimeZone("America/Jujuy", 65391),
	FbTimeZone("America/Juneau", 65390),
	FbTimeZone("America/Kentucky/Louisville", 65389),
	FbTimeZone("America/Kentucky/Monticello", 65388),
	FbTimeZone("America/Knox_IN", 65387),
	FbTimeZone("America/Kralendijk", 65386),
	FbTimeZone("America/La_Paz", 65385),
	FbTimeZone("America/Lima", 65384),
	FbTimeZone("America/Los_Angeles", 65383),
	FbTimeZone("America/Louisville", 65382),
	FbTimeZone("America/Lower_Princes", 65381),
	FbTimeZone("America/Maceio", 65380),
	FbTimeZone("America/Managua", 65379),
	FbTimeZone("America/Manaus", 65378),
	FbTimeZone("America/Marigot", 65377),
	FbTimeZone("America/Martinique", 65376),
	FbTimeZone("America/Matamoros", 65375),
	FbTimeZone("America/Mazatlan", 65374),
	FbTimeZone("America/Mendoza", 65373),
	FbTimeZone("America/Menominee", 65372),
	FbTimeZone("America/Merida", 65371),
	FbTimeZone("America/Metlakatla", 65370),
	FbTimeZone("America/Mexico_City", 65369),
	FbTimeZone("America/Miquelon", 65368),
	FbTimeZone("America/Moncton", 65367),
	FbTimeZone("America/Monterrey", 65366),
	FbTimeZone("America/Montevideo", 65365),
	FbTimeZone("America/Montreal", 65364),
	FbTimeZone("America/Montserrat", 65363),
	FbTimeZone("America/Nassau", 65362),
	FbTimeZone("America/New_York", 65361),
	FbTimeZone("America/Nipigon", 65360),
	FbTimeZone("America/Nome", 65359),
	FbTimeZone("America/Noronha", 65358),
	FbTimeZone("America/North_Dakota/Beulah", 65357),
	FbTimeZone("America/North_Dakota/Center", 65356),
	FbTimeZone("America/North_Dakota/New_Salem", 65355),
	FbTimeZone("America/Nuuk", 64903),
	FbTimeZone("America/Ojinaga", 65354),
	FbTimeZone("America/Panama", 65353),
	FbTimeZone("America/Pangnirtung", 65352),
	FbTimeZone("America/Paramaribo", 65351),
	FbTimeZone("America/Phoenix", 65350),
	FbTimeZone("America/Port-au-Prince", 65349),
	FbTimeZone("America/Port_of_Spain", 65348),
	FbTimeZone("America/Porto_Acre", 65347),
	FbTimeZone("America/Porto_Velho", 65346),
	FbTimeZone("America/Puerto_Rico", 65345),
	FbTimeZone("America/Punta_Arenas", 65344),
	FbTimeZone("America/Rainy_River", 65343),
	FbTimeZone("America/Rankin_Inlet", 65342),
	FbTimeZone("America/Recife", 65341),
	FbTimeZone("America/Regina", 65340),
	FbTimeZone("America/Resolute", 65339),
	FbTimeZone("America/Rio_Branco", 65338),
	FbTimeZone("America/Rosario", 65337),
	FbTimeZone("America/Santa_Isabel", 65336),
	FbTimeZone("America/Santarem", 65335),
	FbTimeZone("America/Santiago", 65334),
	FbTimeZone("America/Santo_Domingo", 65333),
	FbTimeZone("America/Sao_Paulo", 65332),
	FbTimeZone("America/Scoresbysund", 65331),
	FbTimeZone("America/Shiprock", 65330),
	FbTimeZone("America/Sitka", 65329),
	FbTimeZone("America/St_Barthelemy", 65328),
	FbTimeZone("America/St_Johns", 65327),
	FbTimeZone("America/St_Kitts", 65326),
	FbTimeZone("America/St_Lucia", 65325),
	FbTimeZone("America/St_Thomas", 65324),
	FbTimeZone("America/St_Vincent", 65323),
	FbTimeZone("America/Swift_Current", 65322),
	FbTimeZone("America/Tegucigalpa", 65321),
	FbTimeZone("America/Thule", 65320),
	FbTimeZone("America/Thunder_Bay", 65319),
	FbTimeZone("America/Tijuana", 65318),
	FbTimeZone("America/Toronto", 65317),
	FbTimeZone("America/Tortola", 65316),
	FbTimeZone("America/Vancouver", 65315),
	FbTimeZone("America/Virgin", 65314),
	FbTimeZone("America/Whitehorse", 65313),
	FbTimeZone("America/Winnipeg", 65312),
	FbTimeZone("America/Yakutat", 65311),
	FbTimeZone("America/Yellowknife", 65310),
	FbTimeZone("Antarctica/Casey", 65309),
	FbTimeZone("Antarctica/Davis", 65308),
	FbTimeZone("Antarctica/DumontDUrville", 65307),
	FbTimeZone("Antarctica/Macquarie", 65306),
	FbTimeZone("Antarctica/Mawson", 65305),
	FbTimeZone("Antarctica/McMurdo", 65304),
	FbTimeZone("Antarctica/Palmer", 65303),
	FbTimeZone("Antarctica/Rothera", 65302),
	FbTimeZone("Antarctica/South_Pole", 65301),
	FbTimeZone("Antarctica/Syowa", 65300),
	FbTimeZone("Antarctica/Troll", 65299),
	FbTimeZone("Antarctica/Vostok", 65298),
	FbTimeZone("Arctic/Longyearbyen", 65297),
	FbTimeZone("Asia/Aden", 65296),
	FbTimeZone("Asia/Almaty", 65295),
	FbTimeZone("Asia/Amman", 65294),
	FbTimeZone("Asia/Anadyr", 65293),
	FbTimeZone("Asia/Aqtau", 65292),
	FbTimeZone("Asia/Aqtobe", 65291),
	FbTimeZone("Asia/Ashgabat", 65290),
	FbTimeZone("Asia/Ashkhabad", 65289),
	FbTimeZone("Asia/Atyrau", 65288),
	FbTimeZone("Asia/Baghdad", 65287),
	FbTimeZone("Asia/Bahrain", 65286),
	FbTimeZone("Asia/Baku", 65285),
	FbTimeZone("Asia/Bangkok", 65284),
	FbTimeZone("Asia/Barnaul", 65283),
	FbTimeZone("Asia/Beirut", 65282),
	FbTimeZone("Asia/Bishkek", 65281),
	FbTimeZone("Asia/Brunei", 65280),
	FbTimeZone("Asia/Calcutta", 65279),
	FbTimeZone("Asia/Chita", 65278),
	FbTimeZone("Asia/Choibalsan", 65277),
	FbTimeZone("Asia/Chongqing", 65276),
	FbTimeZone("Asia/Chungking", 65275),
	FbTimeZone("Asia/Colombo", 65274),
	FbTimeZone("Asia/Dacca", 65273),
	FbTimeZone("Asia/Damascus", 65272),
	FbTimeZone("Asia/Dhaka", 65271),
	FbTimeZone("Asia/Dili", 65270),
	FbTimeZone("Asia/Dubai", 65269),
	FbTimeZone("Asia/Dushanbe", 65268),
	FbTimeZone("Asia/Famagusta", 65267),
	FbTimeZone("Asia/Gaza", 65266),
	FbTimeZone("Asia/Harbin", 65265),
	FbTimeZone("Asia/Hebron", 65264),
	FbTimeZone("Asia/Ho_Chi_Minh", 65263),
	FbTimeZone("Asia/Hong_Kong", 65262),
	FbTimeZone("Asia/Hovd", 65261),
	FbTimeZone("Asia/Irkutsk", 65260),
	FbTimeZone("Asia/Istanbul", 65259),
	FbTimeZone("Asia/Jakarta", 65258),
	FbTimeZone("Asia/Jayapura", 65257),
	FbTimeZone("Asia/Jerusalem", 65256),
	FbTimeZone("Asia/Kabul", 65255),
	FbTimeZone("Asia/Kamchatka", 65254),
	FbTimeZone("Asia/Karachi", 65253),
	FbTimeZone("Asia/Kashgar", 65252),
	FbTimeZone("Asia/Kathmandu", 65251),
	FbTimeZone("Asia/Katmandu", 65250),
	FbTimeZone("Asia/Khandyga", 65249),
	FbTimeZone("Asia/Kolkata", 65248),
	FbTimeZone("Asia/Krasnoyarsk", 65247),
	FbTimeZone("Asia/Kuala_Lumpur", 65246),
	FbTimeZone("Asia/Kuching", 65245),
	FbTimeZone("Asia/Kuwait", 65244),
	FbTimeZone("Asia/Macao", 65243),
	FbTimeZone("Asia/Macau", 65242),
	FbTimeZone("Asia/Magadan", 65241),
	FbTimeZone("Asia/Makassar", 65240),
	FbTimeZone("Asia/Manila", 65239),
	FbTimeZone("Asia/Muscat", 65238),
	FbTimeZone("Asia/Nicosia", 65237),
	FbTimeZone("Asia/Novokuznetsk", 65236),
	FbTimeZone("Asia/Novosibirsk", 65235),
	FbTimeZone("Asia/Omsk", 65234),
	FbTimeZone("Asia/Oral", 65233),
	FbTimeZone("Asia/Phnom_Penh", 65232),
	FbTimeZone("Asia/Pontianak", 65231),
	FbTimeZone("Asia/Pyongyang", 65230),
	FbTimeZone("Asia/Qatar", 65229),
	FbTimeZone("Asia/Qostanay", 64902),
	FbTimeZone("Asia/Qyzylorda", 65228),
	FbTimeZone("Asia/Rangoon", 65227),
	FbTimeZone("Asia/Riyadh", 65226),
	FbTimeZone("Asia/Saigon", 65225),
	FbTimeZone("Asia/Sakhalin", 65224),
	FbTimeZone("Asia/Samarkand", 65223),
	FbTimeZone("Asia/Seoul", 65222),
	FbTimeZone("Asia/Shanghai", 65221),
	FbTimeZone("Asia/Singapore", 65220),
	FbTimeZone("Asia/Srednekolymsk", 65219),
	FbTimeZone("Asia/Taipei", 65218),
	FbTimeZone("Asia/Tashkent", 65217),
	FbTimeZone("Asia/Tbilisi", 65216),
	FbTimeZone("Asia/Tehran", 65215),
	FbTimeZone("Asia/Tel_Aviv", 65214),
	FbTimeZone("Asia/Thimbu", 65213),
	FbTimeZone("Asia/Thimphu", 65212),
	FbTimeZone("Asia/Tokyo", 65211),
	FbTimeZone("Asia/Tomsk", 65210),
	FbTimeZone("Asia/Ujung_Pandang", 65209),
	FbTimeZone("Asia/Ulaanbaatar", 65208),
	FbTimeZone("Asia/Ulan_Bator", 65207),
	FbTimeZone("Asia/Urumqi", 65206),
	FbTimeZone("Asia/Ust-Nera", 65205),
	FbTimeZone("Asia/Vientiane", 65204),
	FbTimeZone("Asia/Vladivostok", 65203),
	FbTimeZone("Asia/Yakutsk", 65202),
	FbTimeZone("Asia/Yangon", 65201),
	FbTimeZone("Asia/Yekaterinburg", 65200),
	FbTimeZone("Asia/Yerevan", 65199),
	FbTimeZone("Atlantic/Azores", 65198),
	FbTimeZone("Atlantic/Bermuda", 65197),
	FbTimeZone("Atlantic/Canary", 65196),
	FbTimeZone("Atlantic/Cape_Verde", 65195),
	FbTimeZone("Atlantic/Faeroe", 65194),
	FbTimeZone("Atlantic/Faroe", 65193),
	FbTimeZone("Atlantic/Jan_Mayen", 65192),
	FbTimeZone("Atlantic/Madeira", 65191),
	FbTimeZone("Atlantic/Reykjavik", 65190),
	FbTimeZone("Atlantic/South_Georgia", 65189),
	FbTimeZone("Atlantic/St_Helena", 65188),
	FbTimeZone("Atlantic/Stanley", 65187),
	FbTimeZone("Australia/ACT", 65186),
	FbTimeZone("Australia/Adelaide", 65185),
	FbTimeZone("Australia/Brisbane", 65184),
	FbTimeZone("Australia/Broken_Hill", 65183),
	FbTimeZone("Australia/Canberra", 65182),
	FbTimeZone("Australia/Currie", 65181),
	FbTimeZone("Australia/Darwin", 65180),
	FbTimeZone("Australia/Eucla", 65179),
	FbTimeZone("Australia/Hobart", 65178),
	FbTimeZone("Australia/LHI", 65177),
	FbTimeZone("Australia/Lindeman", 65176),
	FbTimeZone("Australia/Lord_Howe", 65175),
	FbTimeZone("Australia/Melbourne", 65174),
	FbTimeZone("Australia/NSW", 65173),
	FbTimeZone("Australia/North", 65172),
	FbTimeZone("Australia/Perth", 65171),
	FbTimeZone("Australia/Queensland", 65170),
	FbTimeZone("Australia/South", 65169),
	FbTimeZone("Australia/Sydney", 65168),
	FbTimeZone("Australia/Tasmania", 65167),
	FbTimeZone("Australia/Victoria", 65166),
	FbTimeZone("Australia/West", 65165),
	FbTimeZone("Australia/Yancowinna", 65164),
	FbTimeZone("BET", 65163),
	FbTimeZone("BST", 65162),
	FbTimeZone("Brazil/Acre", 65161),
	FbTimeZone("Brazil/DeNoronha", 65160),
	FbTimeZone("Brazil/East", 65159),
	FbTimeZone("Brazil/West", 65158),
	FbTimeZone("CAT", 65157),
	FbTimeZone("CET", 65156),
	FbTimeZone("CNT", 65155),
	FbTimeZone("CST", 65154),
	FbTimeZone("CST6CDT", 65153),
	FbTimeZone("CTT", 65152),
	FbTimeZone("Canada/Atlantic", 65151),
	FbTimeZone("Canada/Central", 65150),
	FbTimeZone("Canada/East-Saskatchewan", 65149),
	FbTimeZone("Canada/Eastern", 65148),
	FbTimeZone("Canada/Mountain", 65147),
	FbTimeZone("Canada/Newfoundland", 65146),
	FbTimeZone("Canada/Pacific", 65145),
	FbTimeZone("Canada/Saskatchewan", 65144),
	FbTimeZone("Canada/Yukon", 65143),
	FbTimeZone("Chile/Continental", 65142),
	FbTimeZone("Chile/EasterIsland", 65141),
	FbTimeZone("Cuba", 65140),
	FbTimeZone("EAT", 65139),
	FbTimeZone("ECT", 65138),
	FbTimeZone("EET", 65137),
	FbTimeZone("EST", 65136),
	FbTimeZone("EST5EDT", 65135),
	FbTimeZone("Egypt", 65134),
	FbTimeZone("Eire", 65133),
	FbTimeZone("Etc/GMT", 65132),
	FbTimeZone("Etc/GMT+0", 65131),
	FbTimeZone("Etc/GMT+1", 65130),
	FbTimeZone("Etc/GMT+10", 65129),
	FbTimeZone("Etc/GMT+11", 65128),
	FbTimeZone("Etc/GMT+12", 65127),
	FbTimeZone("Etc/GMT+2", 65126),
	FbTimeZone("Etc/GMT+3", 65125),
	FbTimeZone("Etc/GMT+4", 65124),
	FbTimeZone("Etc/GMT+5", 65123),
	FbTimeZone("Etc/GMT+6", 65122),
	FbTimeZone("Etc/GMT+7", 65121),
	FbTimeZone("Etc/GMT+8", 65120),
	FbTimeZone("Etc/GMT+9", 65119),
	FbTimeZone("Etc/GMT-0", 65118),
	FbTimeZone("Etc/GMT-1", 65117),
	FbTimeZone("Etc/GMT-10", 65116),
	FbTimeZone("Etc/GMT-11", 65115),
	FbTimeZone("Etc/GMT-12", 65114),
	FbTimeZone("Etc/GMT-13", 65113),
	FbTimeZone("Etc/GMT-14", 65112),
	FbTimeZone("Etc/GMT-2", 65111),
	FbTimeZone("Etc/GMT-3", 65110),
	FbTimeZone("Etc/GMT-4", 65109),
	FbTimeZone("Etc/GMT-5", 65108),
	FbTimeZone("Etc/GMT-6", 65107),
	FbTimeZone("Etc/GMT-7", 65106),
	FbTimeZone("Etc/GMT-8", 65105),
	FbTimeZone("Etc/GMT-9", 65104),
	FbTimeZone("Etc/GMT0", 65103),
	FbTimeZone("Etc/Greenwich", 65102),
	FbTimeZone("Etc/UCT", 65101),
	FbTimeZone("Etc/UTC", 65100),
	FbTimeZone("Etc/Universal", 65099),
	FbTimeZone("Etc/Zulu", 65098),
	FbTimeZone("Europe/Amsterdam", 65097),
	FbTimeZone("Europe/Andorra", 65096),
	FbTimeZone("Europe/Astrakhan", 65095),
	FbTimeZone("Europe/Athens", 65094),
	FbTimeZone("Europe/Belfast", 65093),
	FbTimeZone("Europe/Belgrade", 65092),
	FbTimeZone("Europe/Berlin", 65091),
	FbTimeZone("Europe/Bratislava", 65090),
	FbTimeZone("Europe/Brussels", 65089),
	FbTimeZone("Europe/Bucharest", 65088),
	FbTimeZone("Europe/Budapest", 65087),
	FbTimeZone("Europe/Busingen", 65086),
	FbTimeZone("Europe/Chisinau", 65085),
	FbTimeZone("Europe/Copenhagen", 65084),
	FbTimeZone("Europe/Dublin", 65083),
	FbTimeZone("Europe/Gibraltar", 65082),
	FbTimeZone("Europe/Guernsey", 65081),
	FbTimeZone("Europe/Helsinki", 65080),
	FbTimeZone("Europe/Isle_of_Man", 65079),
	FbTimeZone("Europe/Istanbul", 65078),
	FbTimeZone("Europe/Jersey", 65077),
	FbTimeZone("Europe/Kaliningrad", 65076),
	FbTimeZone("Europe/Kiev", 65075),
	FbTimeZone("Europe/Kirov", 65074),
    FbTimeZone("Europe/Kyiv", 64900),
	FbTimeZone("Europe/Lisbon", 65073),
	FbTimeZone("Europe/Ljubljana", 65072),
	FbTimeZone("Europe/London", 65071),
	FbTimeZone("Europe/Luxembourg", 65070),
	FbTimeZone("Europe/Madrid", 65069),
	FbTimeZone("Europe/Malta", 65068),
	FbTimeZone("Europe/Mariehamn", 65067),
	FbTimeZone("Europe/Minsk", 65066),
	FbTimeZone("Europe/Monaco", 65065),
	FbTimeZone("Europe/Moscow", 65064),
	FbTimeZone("Europe/Nicosia", 65063),
	FbTimeZone("Europe/Oslo", 65062),
	FbTimeZone("Europe/Paris", 65061),
	FbTimeZone("Europe/Podgorica", 65060),
	FbTimeZone("Europe/Prague", 65059),
	FbTimeZone("Europe/Riga", 65058),
	FbTimeZone("Europe/Rome", 65057),
	FbTimeZone("Europe/Samara", 65056),
	FbTimeZone("Europe/San_Marino", 65055),
	FbTimeZone("Europe/Sarajevo", 65054),
	FbTimeZone("Europe/Saratov", 65053),
	FbTimeZone("Europe/Simferopol", 65052),
	FbTimeZone("Europe/Skopje", 65051),
	FbTimeZone("Europe/Sofia", 65050),
	FbTimeZone("Europe/Stockholm", 65049),
	FbTimeZone("Europe/Tallinn", 65048),
	FbTimeZone("Europe/Tirane", 65047),
	FbTimeZone("Europe/Tiraspol", 65046),
	FbTimeZone("Europe/Ulyanovsk", 65045),
	FbTimeZone("Europe/Uzhgorod", 65044),
	FbTimeZone("Europe/Vaduz", 65043),
	FbTimeZone("Europe/Vatican", 65042),
	FbTimeZone("Europe/Vienna", 65041),
	FbTimeZone("Europe/Vilnius", 65040),
	FbTimeZone("Europe/Volgograd", 65039),
	FbTimeZone("Europe/Warsaw", 65038),
	FbTimeZone("Europe/Zagreb", 65037),
	FbTimeZone("Europe/Zaporozhye", 65036),
	FbTimeZone("Europe/Zurich", 65035),
	FbTimeZone("Factory", 65034),
	FbTimeZone("GB", 65033),
	FbTimeZone("GB-Eire", 65032),
	FbTimeZone("GMT+0", 65031),
	FbTimeZone("GMT-0", 65030),
	FbTimeZone("GMT0", 65029),
	FbTimeZone("Greenwich", 65028),
	FbTimeZone("HST", 65027),
	FbTimeZone("Hongkong", 65026),
	FbTimeZone("IET", 65025),
	FbTimeZone("IST", 65024),
	FbTimeZone("Iceland", 65023),
	FbTimeZone("Indian/Antananarivo", 65022),
	FbTimeZone("Indian/Chagos", 65021),
	FbTimeZone("Indian/Christmas", 65020),
	FbTimeZone("Indian/Cocos", 65019),
	FbTimeZone("Indian/Comoro", 65018),
	FbTimeZone("Indian/Kerguelen", 65017),
	FbTimeZone("Indian/Mahe", 65016),
	FbTimeZone("Indian/Maldives", 65015),
	FbTimeZone("Indian/Mauritius", 65014),
	FbTimeZone("Indian/Mayotte", 65013),
	FbTimeZone("Indian/Reunion", 65012),
	FbTimeZone("Iran", 65011),
	FbTimeZone("Israel", 65010),
	FbTimeZone("JST", 65009),
	FbTimeZone("Jamaica", 65008),
	FbTimeZone("Japan", 65007),
	FbTimeZone("Kwajalein", 65006),
	FbTimeZone("Libya", 65005),
	FbTimeZone("MET", 65004),
	FbTimeZone("MIT", 65003),
	FbTimeZone("MST", 65002),
	FbTimeZone("MST7MDT", 65001),
	FbTimeZone("Mexico/BajaNorte", 65000),
	FbTimeZone("Mexico/BajaSur", 64999),
	FbTimeZone("Mexico/General", 64998),
	FbTimeZone("NET", 64997),
	FbTimeZone("NST", 64996),
	FbTimeZone("NZ", 64995),
	FbTimeZone("NZ-CHAT", 64994),
	FbTimeZone("Navajo", 64993),
	FbTimeZone("PLT", 64992),
	FbTimeZone("PNT", 64991),
	FbTimeZone("PRC", 64990),
	FbTimeZone("PRT", 64989),
	FbTimeZone("PST", 64988),
	FbTimeZone("PST8PDT", 64987),
	FbTimeZone("Pacific/Apia", 64986),
	FbTimeZone("Pacific/Auckland", 64985),
	FbTimeZone("Pacific/Bougainville", 64984),
	FbTimeZone("Pacific/Chatham", 64983),
	FbTimeZone("Pacific/Chuuk", 64982),
	FbTimeZone("Pacific/Easter", 64981),
	FbTimeZone("Pacific/Efate", 64980),
	FbTimeZone("Pacific/Enderbury", 64979),
	FbTimeZone("Pacific/Fakaofo", 64978),
	FbTimeZone("Pacific/Fiji", 64977),
	FbTimeZone("Pacific/Funafuti", 64976),
	FbTimeZone("Pacific/Galapagos", 64975),
	FbTimeZone("Pacific/Gambier", 64974),
	FbTimeZone("Pacific/Guadalcanal", 64973),
	FbTimeZone("Pacific/Guam", 64972),
	FbTimeZone("Pacific/Honolulu", 64971),
	FbTimeZone("Pacific/Johnston", 64970),
	FbTimeZone("Pacific/Kiritimati", 64969),
	FbTimeZone("Pacific/Kosrae", 64968),
    FbTimeZone("Pacific/Kanton", 64901),
	FbTimeZone("Pacific/Kwajalein", 64967),
	FbTimeZone("Pacific/Majuro", 64966),
	FbTimeZone("Pacific/Marquesas", 64965),
	FbTimeZone("Pacific/Midway", 64964),
	FbTimeZone("Pacific/Nauru", 64963),
	FbTimeZone("Pacific/Niue", 64962),
	FbTimeZone("Pacific/Norfolk", 64961),
	FbTimeZone("Pacific/Noumea", 64960),
	FbTimeZone("Pacific/Pago_Pago", 64959),
	FbTimeZone("Pacific/Palau", 64958),
	FbTimeZone("Pacific/Pitcairn", 64957),
	FbTimeZone("Pacific/Pohnpei", 64956),
	FbTimeZone("Pacific/Ponape", 64955),
	FbTimeZone("Pacific/Port_Moresby", 64954),
	FbTimeZone("Pacific/Rarotonga", 64953),
	FbTimeZone("Pacific/Saipan", 64952),
	FbTimeZone("Pacific/Samoa", 64951),
	FbTimeZone("Pacific/Tahiti", 64950),
	FbTimeZone("Pacific/Tarawa", 64949),
	FbTimeZone("Pacific/Tongatapu", 64948),
	FbTimeZone("Pacific/Truk", 64947),
	FbTimeZone("Pacific/Wake", 64946),
	FbTimeZone("Pacific/Wallis", 64945),
	FbTimeZone("Pacific/Yap", 64944),
	FbTimeZone("Poland", 64943),
	FbTimeZone("Portugal", 64942),
	FbTimeZone("ROC", 64941),
	FbTimeZone("ROK", 64940),
	FbTimeZone("SST", 64939),
	FbTimeZone("Singapore", 64938),
	FbTimeZone("SystemV/AST4", 64937),
	FbTimeZone("SystemV/AST4ADT", 64936),
	FbTimeZone("SystemV/CST6", 64935),
	FbTimeZone("SystemV/CST6CDT", 64934),
	FbTimeZone("SystemV/EST5", 64933),
	FbTimeZone("SystemV/EST5EDT", 64932),
	FbTimeZone("SystemV/HST10", 64931),
	FbTimeZone("SystemV/MST7", 64930),
	FbTimeZone("SystemV/MST7MDT", 64929),
	FbTimeZone("SystemV/PST8", 64928),
	FbTimeZone("SystemV/PST8PDT", 64927),
	FbTimeZone("SystemV/YST9", 64926),
	FbTimeZone("SystemV/YST9YDT", 64925),
	FbTimeZone("Turkey", 64924),
	FbTimeZone("UCT", 64923),
	FbTimeZone("US/Alaska", 64922),
	FbTimeZone("US/Aleutian", 64921),
	FbTimeZone("US/Arizona", 64920),
	FbTimeZone("US/Central", 64919),
	FbTimeZone("US/East-Indiana", 64918),
	FbTimeZone("US/Eastern", 64917),
	FbTimeZone("US/Hawaii", 64916),
	FbTimeZone("US/Indiana-Starke", 64915),
	FbTimeZone("US/Michigan", 64914),
	FbTimeZone("US/Mountain", 64913),
	FbTimeZone("US/Pacific", 64912),
	FbTimeZone("US/Pacific-New", 64911),
	FbTimeZone("US/Samoa", 64910),
	FbTimeZone("UTC", 64909),
	FbTimeZone("Universal", 64908),
	FbTimeZone("VST", 64907),
	FbTimeZone("W-SU", 64906),
	FbTimeZone("WET", 64905),
	FbTimeZone("Zulu", 64904),
	];
