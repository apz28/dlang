/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.dtm.dtm_time_zone_map;

import std.uni : sicmp;

import pham.utl.utl_object : singleton;
import pham.utl.utl_result;
import pham.dtm.dtm_time_zone : TimeZoneInfo, ZoneOffset;
import pham.dtm.dtm_time_zone_default;

@safe:

/*
 * A map struct to hold equivalent zone names between IANA & Windows
 * https://github.com/unicode-org/cldr/blob/main/common/supplemental/windowsZones.xml
 *
 */
struct IanaWindowNameMap
{
    import std.string : toUpper;

nothrow @safe:

public:
    this(string iana, string territory, string window) pure
    {
        this._iana = iana;
        this._territory = territory;
        this._window = window;
    }

    int opCmp(scope const(IanaWindowNameMap) rhs) const @nogc pure scope
    {
        scope (failure) assert(0, "Assume nothrow failed");

        int result = sicmp(_iana, rhs._iana);
        if (result == 0)
            result = sicmp(_window, rhs._window);
        if (result == 0)
            result = sicmp(_territory, rhs._territory);
        return result;
    }

    bool opEquals(scope const(IanaWindowNameMap) rhs) const @nogc pure scope
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const pure scope
    {
        scope (failure) assert(0, "Assume nothrow failed");

        return hashOf(_territory.toUpper(), hashOf(_window.toUpper(), hashOf(_iana.toUpper())));
    }

    /**
     * IANA zone name
     */
    @property string iana() const pure
    {
        return _iana;
    }

    @property string territory() const pure
    {
        return _territory;
    }

    /**
     * Windows zone name
     */
    @property string window() const pure
    {
        return _window;
    }

private:
    string _iana;
    string _territory;
    string _window;
}

class IanaWindowNameMapList
{
    import std.string : toUpper;

@safe:

public:
    this(IanaWindowNameMap[] items) nothrow pure
    {
        this._items = items;
        if (items.length)
            this.populateTos();
    }

    /**
     * Return an array of IanaWindowNameMap structs of equivalent `windowName`
     * If there is no match, return an empty array
     * Params:
     *   windowName = Windows zone name to search for
     * Returns:
     *   An array of IanaWindowNameMap structs
     */
    const(IanaWindowNameMap)*[] findIanas(scope const(char)[] windowName) const nothrow pure @trusted
    {
        scope (failure) assert(0, "Assume nothrow failed");

        if (auto n = windowName.toUpper() in _toIanas)
            return cast(const(IanaWindowNameMap)*[])(*n);

        return null;
    }

    /**
     * Return an IanaWindowNameMap struct of equivalent `windowName` & `territory`
     * If there is no match, return null
     * Params:
     *   windowName = Windows zone name to search for
     *   territory = territory name
     * Returns:
     *   An IanaWindowNameMap struct
     */
    const(IanaWindowNameMap)* findIana(scope const(char)[] windowName, scope const(char)[] territory = "001") const nothrow pure
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto maps = findIanas(windowName);
        foreach (e; maps)
        {
            if (sicmp((*e).territory, territory) == 0)
                return e;
        }

        return null;
    }

    /**
     * Return an equivalent IANA name of `windowName` & `territory`
     * If there is no match, return null
     * Params:
     *   windowName = Windows zone name to search for
     *   territory = territory name
     * Returns:
     *   IANA name as string
     */
    string toIana(scope const(char)[] windowName, scope const(char)[] territory = "001") const nothrow pure
    {
        if (auto e = findIana(windowName, territory))
            return (*e).iana;
        return null;
    }

    /**
     * Return an array of IanaWindowNameMap structs of equivalent `ianaName`
     * If there is no match, return an empty array
     * Params:
     *   ianaName = IANA zone name to search for
     * Returns:
     *   An array of IanaWindowNameMap structs
     */
    const(IanaWindowNameMap)*[] findWindows(scope const(char)[] ianaName) const nothrow pure @trusted
    {
        scope (failure) assert(0, "Assume nothrow failed");

        if (auto n = ianaName.toUpper() in _toWindows)
            return cast(const(IanaWindowNameMap)*[])(*n);

        return null;
    }

    /**
     * Return an IanaWindowNameMap struct of equivalent `ianaName` & `territory`
     * If there is no match, return null
     * Params:
     *   ianaName = IANA zone name to search for
     *   territory = territory name
     * Returns:
     *   An IanaWindowNameMap struct
     */
    const(IanaWindowNameMap)* findWindow(scope const(char)[] ianaName, scope const(char)[] territory = "001") const nothrow pure
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto maps = findWindows(ianaName);
        foreach (e; maps)
        {
            if (sicmp((*e).territory, territory) == 0)
                return e;
        }

        return null;
    }

    /**
     * Return an equivalent Windows name of `ianaName` & `territory`
     * If there is no match, return null
     * Params:
     *   ianaName = IANA zone name to search for
     *   territory = territory name
     * Returns:
     *   Windows name as string
     */
    string toWindow(scope const(char)[] ianaName, scope const(char)[] territory = "001") const nothrow pure
    {
        if (auto e = findWindow(ianaName, territory))
            return (*e).window;
        return null;
    }

    static ResultIf!IanaWindowNameMapList parse(string windowZonesXml) nothrow
    {
        if (windowZonesXml.length == 0)
            return ResultIf!IanaWindowNameMapList.ok(null);

        try
        {
            return ResultIf!IanaWindowNameMapList.ok(parseImpl(windowZonesXml));
        }
        catch (Exception e)
            return ResultIf!IanaWindowNameMapList.error(1, e.msg);
    }

protected:
    static IanaWindowNameMapList parseImpl(string windowZonesXml)
    {
        return null;
        /* TODO
        import std.array : split;
        import pham.xml.xml_dom;

        static struct ProcessXml
        {
            enum keepingNodeResult = true;
            enum notKeepingNodeResult = false;

            IanaWindowNameMap[] items;

            bool processAttribute(XmlNode!string parent, XmlAttribute!string attribute)
            {
                return keepingNodeResult;
            }

            bool processElementEnd(XmlNode!string parent, XmlElement!string element) @trusted
            {
                // Samples
                // <mapZone other="Mountain Standard Time" territory="001" type="America/Denver"/>
                // <mapZone other="Mountain Standard Time" territory="CA" type="America/Edmonton America/Cambridge_Bay America/Inuvik America/Yellowknife"/>
                if (element.localName != "mapZone")
                    return notKeepingNodeResult;

                // Having attributes?
                auto windowNameNode = element.findAttribute("other");
                auto ianaNameNode = element.findAttribute("type");
                if (windowNameNode is null || ianaNameNode is null)
                    return notKeepingNodeResult;

                // Having text?
                string windowNameText = windowNameNode.value;
                string ianaNameText = ianaNameNode.value;
                if (windowNameText.length == 0 || ianaNameText.length == 0)
                    return notKeepingNodeResult;

                auto territoryNode = element.findAttribute("territory");
                string territoryText = territoryNode !is null ? territoryNode.value : null;

                auto ianaNameTexts = ianaNameText.split();
                foreach (ianaName; ianaNameTexts)
                {
                    items ~= IanaWindowNameMap(ianaName, territoryText, windowNameText);
                }

                return notKeepingNodeResult;
            }
        }

        ProcessXml processXml;
        {
            XmlParseOptions!string options;
            options.onSaxAttributeNode = &processXml.processAttribute;
            options.onSaxElementNodeEnd = &processXml.processElementEnd;

            auto doc = new XmlDocument!string();
            doc.load!(Yes.SAX)(windowZonesXml, options);
        }

        return new IanaWindowNameMapList(processXml.items);
        */
    }

protected:
    void populateTos() nothrow pure
    in
    {
        assert(_toIanas.length == 0);
        assert(_toWindows.length == 0);
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

        foreach (i; 0.._items.length)
        {
            const windowName = _items[i].window.toUpper();
            if (auto n = windowName in _toIanas)
                *n ~= &_items[i];
            else
                _toIanas[windowName] = [&_items[i]];

            const ianaName = _items[i].iana.toUpper();
            if (auto n = ianaName in _toWindows)
                *n ~= &_items[i];
            else
                _toWindows[ianaName] = [&_items[i]];
        }
    }

private:
    IanaWindowNameMap[] _items;
    IanaWindowNameMap*[][string] _toIanas;
    IanaWindowNameMap*[][string] _toWindows;
}

alias MapId = ushort;

struct TimeZoneInfoMap
{
nothrow @safe:

public:
    this(MapId id, string zoneIdOrName, immutable(TimeZoneInfo)* zoneInfo) @nogc pure
    {
        this._id = id;
        this._zoneIdOrName = zoneIdOrName;
        this._zoneInfo = zoneInfo;
    }

    pragma(inline, true)
	bool isValid() const @nogc pure
    {
		return (_id != 0 || _zoneIdOrName.length != 0) && _zoneInfo !is null;
    }

    static TimeZoneInfoMap timeZoneMap(MapId id) @nogc nothrow @trusted
    {
        return defaultTimeZoneInfoMaps.timeZoneMap(id);
    }

    static TimeZoneInfoMap timeZoneMap(string zoneIdOrName) @nogc nothrow @trusted
    {
        return defaultTimeZoneInfoMaps.timeZoneMap(zoneIdOrName);
    }

    @property MapId id() const @nogc pure
    {
        return _id;
    }

    @property immutable(TimeZoneInfo)* zoneInfo() const @nogc pure
    {
        return _zoneInfo;
    }

    @property string zoneIdOrName() const @nogc pure
    {
        return _zoneIdOrName;
    }

    @property ZoneOffset zoneBaseUtcOffset() const @nogc pure
    {
        return isValid()
            ? (*_zoneInfo).baseUtcOffset
            : ZoneOffset.init;
    }

private:
    string _zoneIdOrName;
    immutable(TimeZoneInfo)* _zoneInfo;
    MapId _id; // Runtime assigned value
}

class TimeZoneInfoMapList
{
nothrow @safe:

public:
    this(immutable(TimeZoneInfo)[] zoneInfos, scope const(TimeZoneNameMap)[] tzZoneIds) pure
    {
        this._zoneInfos = zoneInfos;
        if (zoneInfos.length)
            this.initDicts(tzZoneIds);
    }

    final void add(MapId id, immutable(TimeZoneInfo)* zoneInfo) pure
    in
    {
        assert(id != 0);
        assert(zoneInfo !is null);
        assert(zoneInfo.id.length != 0);
    }
    do
    {
        const infoId = zoneInfo.id;
        auto map = TimeZoneInfoMap(id, infoId, zoneInfo);
        ids[id] = map;
        zoneIdOrNames[infoId] = map;

        if (zoneInfo.standardName != infoId)
            addIf(id, zoneInfo.standardName, zoneInfo);
        if (zoneInfo.displayName != infoId)
            addIf(id, zoneInfo.displayName, zoneInfo);
        if (zoneInfo.daylightName != infoId && zoneInfo.supportsDaylightSavingTime)
            addIf(id, zoneInfo.daylightName, zoneInfo);
    }

    final void addIf(MapId id, string zoneIdOrName, immutable(TimeZoneInfo)* zoneInfo) pure
    in
    {
        assert(zoneInfo !is null);
    }
    do
    {
        if (id == 0 || zoneIdOrName.length == 0)
            return;

        auto map = TimeZoneInfoMap(id, zoneIdOrName, zoneInfo);
        if ((id in ids) is null)
            ids[id] = map;
        if ((zoneIdOrName in zoneIdOrNames) is null)
            zoneIdOrNames[zoneIdOrName] = map;
    }

    final TimeZoneInfoMap timeZoneMap(MapId id) const @nogc pure
    {
        if (auto e = id in ids)
            return *e;
        else
            return TimeZoneInfoMap.init;
    }

    final TimeZoneInfoMap timeZoneMap(string zoneIdOrName) const @nogc pure
    {
        if (auto e = zoneIdOrName in zoneIdOrNames)
            return *e;
        else
            return TimeZoneInfoMap.init;
    }

    @property immutable(TimeZoneInfo)[] zoneInfos() const @nogc pure
    {
        return _zoneInfos;
    }

private:
    final void initDicts(scope const(TimeZoneNameMap)[] tzZoneIds) pure
    in
    {
        assert(_zoneInfos.length != 0);
    }
    do
    {
        foreach (i; 0.._zoneInfos.length)
        {
            add(cast(MapId)(i + 1), &_zoneInfos[i]);
        }

        foreach (ref tzZoneId; tzZoneIds)
        {
            if (tzZoneId.otName.length == 0)
                continue;

            auto mapInfo = tzZoneId.otName in zoneIdOrNames;
            if (mapInfo is null)
            {
                //import std.stdio : writeln; debug writeln("tzZoneId.otName?=", tzZoneId.otName);
                continue;
            }

            addIf((*mapInfo).id, tzZoneId.tzName, (*mapInfo).zoneInfo);
        }
    }

private:
    TimeZoneInfoMap[MapId] ids;
    TimeZoneInfoMap[string] zoneIdOrNames;
    immutable(TimeZoneInfo)[] _zoneInfos;
}

struct TimeZoneNameMap
{
nothrow @safe:

public:
    this(string tzName, string otName) @nogc pure
    {
        this._tzName = tzName;
        this._otName = otName;
    }

    bool opEquals(scope const(typeof(this)) rhs) const @nogc pure
    {
        return this._tzName == rhs._tzName && this._otName == rhs._otName;
    }

    pragma(inline, true)
	bool isValid() const @nogc pure
    {
		return _tzName.length != 0 && _otName.length != 0;
    }

    static immutable(typeof(this)) zoneTzName(string tzName)
    {
		return TimeZoneNameMapList.instance().zoneTzName(tzName);
    }

    size_t toHash() const @nogc pure
    {
        return 0; //todo
    }

    string toString() const pure
    {
        import pham.utl.utl_array : Appender;

        auto result = Appender!string(_tzName.length + 3 + _otName.length);
        return result.put(_tzName)
            .put(" - ")
            .put(otName)
            .data;
    }

    /*
     * Standard Windows zone name
     */
    @property string otName() const @nogc pure
    {
        return _otName;
    }

    /*
     * Standard IANA zone name
     */
    @property string tzName() const @nogc pure
    {
        return _tzName;
    }

public:
	static immutable string gmtZoneId = "GMT";
    static immutable string gmtZoneName = "Greenwich Mean Time";

private:
    string _tzName;
    string _otName;
}

class TimeZoneNameMapList
{
nothrow @safe:

public:
    this() pure
    {
        this.tzNames = tzNameDict();
    }

    static typeof(this) instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    final immutable(TimeZoneNameMap) zoneTzName(string tzName) pure
    {
        if (auto p = tzName in tzNames)
            return **p;
        else
            return TimeZoneNameMap.init;
    }

	static immutable(TimeZoneNameMap)*[string] tzNameDict() pure @trusted
    {
		immutable(TimeZoneNameMap)*[string] result;
        foreach (i; 0..timeZoneNameMaps.length)
            result[timeZoneNameMaps[i].tzName] = &timeZoneNameMaps[i];
		return result;
    }

public:
    immutable(TimeZoneNameMap)*[string] tzNames;

protected:
    static typeof(this) createInstance() pure
    {
        return new TimeZoneNameMapList();
    }

private:
	static __gshared TimeZoneNameMapList _instance;
}

/*
 * Zone other name are from dtm_time_zone_map_iana_window_45.xml
 * https://github.com/nodatime/nodatime/blob/main/data/cldr/windowsZones-45.xml
 * https://code2care.org/pages/java-timezone-list-utc-gmt-offset/
 */
static immutable TimeZoneNameMap[] timeZoneNameMaps = [
	TimeZoneNameMap(TimeZoneNameMap.gmtZoneId, TimeZoneNameMap.gmtZoneName),
	TimeZoneNameMap("ACT", "AUS Central Standard Time"),
	TimeZoneNameMap("AET", "E. Australia Standard Time"),
	TimeZoneNameMap("AGT", "UTC-03"),
	TimeZoneNameMap("ART", "Argentina Standard Time"),
	TimeZoneNameMap("AST", "Atlantic Standard Time"),
	TimeZoneNameMap("Africa/Abidjan", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Accra", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Addis_Ababa", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Algiers", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Asmara", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Asmera", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Bamako", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Bangui", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Banjul", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Bissau", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Blantyre", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Brazzaville", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Bujumbura", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Cairo", "Egypt Standard Time"),
	TimeZoneNameMap("Africa/Casablanca", "Morocco Standard Time"),
	TimeZoneNameMap("Africa/Ceuta", "Romance Standard Time"),
	TimeZoneNameMap("Africa/Conakry", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Dakar", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Dar_es_Salaam", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Djibouti", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Douala", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/El_Aaiun", "Morocco Standard Time"),
	TimeZoneNameMap("Africa/Freetown", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Gaborone", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Harare", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Johannesburg", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Juba", "South Sudan Standard Time"),
	TimeZoneNameMap("Africa/Kampala", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Khartoum", "Sudan Standard Time"),
	TimeZoneNameMap("Africa/Kigali", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Kinshasa", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Lagos", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Libreville", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Lome", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Luanda", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Lubumbashi", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Lusaka", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Malabo", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Maputo", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Maseru", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Mbabane", "South Africa Standard Time"),
	TimeZoneNameMap("Africa/Mogadishu", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Monrovia", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Nairobi", "E. Africa Standard Time"),
	TimeZoneNameMap("Africa/Ndjamena", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Niamey", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Nouakchott", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Ouagadougou", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Porto-Novo", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Sao_Tome", "Sao Tome Standard Time"),
	TimeZoneNameMap("Africa/Timbuktu", "Greenwich Standard Time"),
	TimeZoneNameMap("Africa/Tripoli", "Libya Standard Time"),
	TimeZoneNameMap("Africa/Tunis", "W. Central Africa Standard Time"),
	TimeZoneNameMap("Africa/Windhoek", "Namibia Standard Time"),
	TimeZoneNameMap("America/Adak", "Aleutian Standard Time"),
	TimeZoneNameMap("America/Anchorage", "Alaskan Standard Time"),
	TimeZoneNameMap("America/Anguilla", "SA Western Standard Time"),
	TimeZoneNameMap("America/Antigua", "SA Western Standard Time"),
	TimeZoneNameMap("America/Araguaina", "Tocantins Standard Time"),
	TimeZoneNameMap("America/Argentina/Buenos_Aires", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Catamarca", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/ComodRivadavia", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Cordoba", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Jujuy", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/La_Rioja", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Mendoza", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Rio_Gallegos", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Salta", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/San_Juan", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/San_Luis", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Tucuman", "Argentina Standard Time"),
	TimeZoneNameMap("America/Argentina/Ushuaia", "Argentina Standard Time"),
	TimeZoneNameMap("America/Aruba", "SA Western Standard Time"),
	TimeZoneNameMap("America/Asuncion", "Paraguay Standard Time"),
	TimeZoneNameMap("America/Atikokan", "Eastern Standard Time"),
	TimeZoneNameMap("America/Atka", "Eastern Standard Time"),
	TimeZoneNameMap("America/Bahia", "Bahia Standard Time"),
	TimeZoneNameMap("America/Bahia_Banderas", "Central Standard Time (Mexico)"),
	TimeZoneNameMap("America/Barbados", "SA Western Standard Time"),
	TimeZoneNameMap("America/Belem", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Belize", "Central America Standard Time"),
	TimeZoneNameMap("America/Blanc-Sablon", "SA Western Standard Time"),
	TimeZoneNameMap("America/Boa_Vista", "SA Western Standard Time"),
	TimeZoneNameMap("America/Bogota", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Boise", "Mountain Standard Time"),
	TimeZoneNameMap("America/Buenos_Aires", "Argentina Standard Time"),
	TimeZoneNameMap("America/Cambridge_Bay", "Mountain Standard Time"),
	TimeZoneNameMap("America/Campo_Grande", "Central Brazilian Standard Time"),
	TimeZoneNameMap("America/Cancun", "Eastern Standard Time (Mexico)"),
	TimeZoneNameMap("America/Caracas", "Venezuela Standard Time"),
	TimeZoneNameMap("America/Catamarca", "Argentina Standard Time"),
	TimeZoneNameMap("America/Cayenne", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Cayman", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Chicago", "Central Standard Time"),
	TimeZoneNameMap("America/Chihuahua", "Central Standard Time (Mexico)"),
    TimeZoneNameMap("America/Ciudad_Juarez", "Mountain Standard Time"),
	TimeZoneNameMap("America/Coral_Harbour", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Cordoba", "Argentina Standard Time"),
	TimeZoneNameMap("America/Costa_Rica", "Central America Standard Time"),
	TimeZoneNameMap("America/Creston", "US Mountain Standard Time"),
	TimeZoneNameMap("America/Cuiaba", "Central Brazilian Standard Time"),
	TimeZoneNameMap("America/Curacao", "SA Western Standard Time"),
	TimeZoneNameMap("America/Danmarkshavn", "Greenwich Standard Time"),
	TimeZoneNameMap("America/Dawson", "Yukon Standard Time"),
	TimeZoneNameMap("America/Dawson_Creek", "US Mountain Standard Time"),
	TimeZoneNameMap("America/Denver", "Mountain Standard Time"),
	TimeZoneNameMap("America/Detroit", "Eastern Standard Time"),
	TimeZoneNameMap("America/Dominica", "SA Western Standard Time"),
	TimeZoneNameMap("America/Edmonton", "Mountain Standard Time"),
	TimeZoneNameMap("America/Eirunepe", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/El_Salvador", "Central America Standard Time"),
	TimeZoneNameMap("America/Ensenada", "Pacific Standard Time (Mexico)"),
	TimeZoneNameMap("America/Fort_Nelson", "US Mountain Standard Time"),
	TimeZoneNameMap("America/Fort_Wayne", "US Eastern Standard Time"),
	TimeZoneNameMap("America/Fortaleza", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Glace_Bay", "Atlantic Standard Time"),
	TimeZoneNameMap("America/Godthab", "Greenland Standard Time"),
	TimeZoneNameMap("America/Goose_Bay", "Atlantic Standard Time"),
	TimeZoneNameMap("America/Grand_Turk", "Turks And Caicos Standard Time"),
	TimeZoneNameMap("America/Grenada", "SA Western Standard Time"),
	TimeZoneNameMap("America/Guadeloupe", "SA Western Standard Time"),
	TimeZoneNameMap("America/Guatemala", "Central America Standard Time"),
	TimeZoneNameMap("America/Guayaquil", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Guyana", "SA Western Standard Time"),
	TimeZoneNameMap("America/Halifax", "Atlantic Standard Time"),
	TimeZoneNameMap("America/Havana", "Cuba Standard Time"),
	TimeZoneNameMap("America/Hermosillo", "US Mountain Standard Time"),
	TimeZoneNameMap("America/Indiana/Indianapolis", "US Eastern Standard Time"),
	TimeZoneNameMap("America/Indiana/Knox", "Central Standard Time"),
	TimeZoneNameMap("America/Indiana/Marengo", "US Eastern Standard Time"),
	TimeZoneNameMap("America/Indiana/Petersburg", "Eastern Standard Time"),
	TimeZoneNameMap("America/Indiana/Tell_City", "Central Standard Time"),
	TimeZoneNameMap("America/Indiana/Vevay", "US Eastern Standard Time"),
	TimeZoneNameMap("America/Indiana/Vincennes", "Eastern Standard Time"),
	TimeZoneNameMap("America/Indiana/Winamac", "Eastern Standard Time"),
	TimeZoneNameMap("America/Indianapolis", "US Eastern Standard Time"),
	TimeZoneNameMap("America/Inuvik", "Mountain Standard Time"),
	TimeZoneNameMap("America/Iqaluit", "Eastern Standard Time"),
	TimeZoneNameMap("America/Jamaica", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Jujuy", "Argentina Standard Time"),
	TimeZoneNameMap("America/Juneau", "Alaskan Standard Time"),
	TimeZoneNameMap("America/Kentucky/Louisville", "Eastern Standard Time"),
	TimeZoneNameMap("America/Kentucky/Monticello", "Eastern Standard Time"),
	TimeZoneNameMap("America/Knox_IN", "Central Standard Time"),
	TimeZoneNameMap("America/Kralendijk", "SA Western Standard Time"),
	TimeZoneNameMap("America/La_Paz", "SA Western Standard Time"),
	TimeZoneNameMap("America/Lima", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Los_Angeles", "Pacific Standard Time"),
	TimeZoneNameMap("America/Louisville", "Eastern Standard Time"),
	TimeZoneNameMap("America/Lower_Princes", "SA Western Standard Time"),
	TimeZoneNameMap("America/Maceio", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Managua", "Central America Standard Time"),
	TimeZoneNameMap("America/Manaus", "SA Western Standard Time"),
	TimeZoneNameMap("America/Marigot", "SA Western Standard Time"),
	TimeZoneNameMap("America/Martinique", "SA Western Standard Time"),
	TimeZoneNameMap("America/Matamoros", "Central Standard Time"),
	TimeZoneNameMap("America/Mazatlan", "Mountain Standard Time (Mexico)"),
	TimeZoneNameMap("America/Mendoza", "Argentina Standard Time"),
	TimeZoneNameMap("America/Menominee", "Central Standard Time"),
	TimeZoneNameMap("America/Merida", "Central Standard Time (Mexico)"),
	TimeZoneNameMap("America/Metlakatla", "Alaskan Standard Time"),
	TimeZoneNameMap("America/Mexico_City", "Central Standard Time (Mexico)"),
	TimeZoneNameMap("America/Miquelon", "Saint Pierre Standard Time"),
	TimeZoneNameMap("America/Moncton", "Atlantic Standard Time"),
	TimeZoneNameMap("America/Monterrey", "Central Standard Time (Mexico)"),
	TimeZoneNameMap("America/Montevideo", "Montevideo Standard Time"),
	TimeZoneNameMap("America/Montreal", "Eastern Standard Time"),
	TimeZoneNameMap("America/Montserrat", "SA Western Standard Time"),
	TimeZoneNameMap("America/Nassau", "Eastern Standard Time"),
	TimeZoneNameMap("America/New_York", "Eastern Standard Time"),
	TimeZoneNameMap("America/Nipigon", "Eastern Standard Time"),
	TimeZoneNameMap("America/Nome", "Alaskan Standard Time"),
	TimeZoneNameMap("America/Noronha", "UTC-02"),
	TimeZoneNameMap("America/North_Dakota/Beulah", "Central Standard Time"),
	TimeZoneNameMap("America/North_Dakota/Center", "Central Standard Time"),
	TimeZoneNameMap("America/North_Dakota/New_Salem", "Central Standard Time"),
	TimeZoneNameMap("America/Nuuk", "UTC-02"),
	TimeZoneNameMap("America/Ojinaga", "Central Standard Time"),
	TimeZoneNameMap("America/Panama", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Pangnirtung", "Eastern Standard Time"),
	TimeZoneNameMap("America/Paramaribo", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Phoenix", "US Mountain Standard Time"),
	TimeZoneNameMap("America/Port-au-Prince", "Haiti Standard Time"),
	TimeZoneNameMap("America/Port_of_Spain", "SA Western Standard Time"),
	TimeZoneNameMap("America/Porto_Acre", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Porto_Velho", "SA Western Standard Time"),
	TimeZoneNameMap("America/Puerto_Rico", "SA Western Standard Time"),
	TimeZoneNameMap("America/Punta_Arenas", "Magallanes Standard Time"),
	TimeZoneNameMap("America/Rainy_River", "Central Standard Time"),
	TimeZoneNameMap("America/Rankin_Inlet", "Central Standard Time"),
	TimeZoneNameMap("America/Recife", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Regina", "Canada Central Standard Time"),
	TimeZoneNameMap("America/Resolute", "Central Standard Time"),
	TimeZoneNameMap("America/Rio_Branco", "SA Pacific Standard Time"),
	TimeZoneNameMap("America/Rosario", "Argentina Standard Time"),
	TimeZoneNameMap("America/Santa_Isabel", "Pacific Standard Time (Mexico)"),
	TimeZoneNameMap("America/Santarem", "SA Eastern Standard Time"),
	TimeZoneNameMap("America/Santiago", "Pacific SA Standard Time"),
	TimeZoneNameMap("America/Santo_Domingo", "SA Western Standard Time"),
	TimeZoneNameMap("America/Sao_Paulo", "E. South America Standard Time"),
	TimeZoneNameMap("America/Scoresbysund", "Azores Standard Time"),
	TimeZoneNameMap("America/Shiprock", "Mountain Standard Time"),
	TimeZoneNameMap("America/Sitka", "Alaskan Standard Time"),
	TimeZoneNameMap("America/St_Barthelemy", "SA Western Standard Time"),
	TimeZoneNameMap("America/St_Johns", "Newfoundland Standard Time"),
	TimeZoneNameMap("America/St_Kitts", "SA Western Standard Time"),
	TimeZoneNameMap("America/St_Lucia", "SA Western Standard Time"),
	TimeZoneNameMap("America/St_Thomas", "SA Western Standard Time"),
	TimeZoneNameMap("America/St_Vincent", "SA Western Standard Time"),
	TimeZoneNameMap("America/Swift_Current", "Canada Central Standard Time"),
	TimeZoneNameMap("America/Tegucigalpa", "Central America Standard Time"),
	TimeZoneNameMap("America/Thule", "Atlantic Standard Time"),
	TimeZoneNameMap("America/Thunder_Bay", "Eastern Standard Time"),
	TimeZoneNameMap("America/Tijuana", "Pacific Standard Time (Mexico)"),
	TimeZoneNameMap("America/Toronto", "Eastern Standard Time"),
	TimeZoneNameMap("America/Tortola", "SA Western Standard Time"),
	TimeZoneNameMap("America/Vancouver", "Pacific Standard Time"),
	TimeZoneNameMap("America/Virgin", "Eastern Standard Time"),
	TimeZoneNameMap("America/Whitehorse", "Yukon Standard Time"),
	TimeZoneNameMap("America/Winnipeg", "Central Standard Time"),
	TimeZoneNameMap("America/Yakutat", "Alaskan Standard Time"),
	TimeZoneNameMap("America/Yellowknife", "Mountain Standard Time"),
	TimeZoneNameMap("Antarctica/Casey", "Central Pacific Standard Time"),
	TimeZoneNameMap("Antarctica/Davis", "SE Asia Standard Time"),
	TimeZoneNameMap("Antarctica/DumontDUrville", "West Pacific Standard Time"),
	TimeZoneNameMap("Antarctica/Macquarie", "Tasmania Standard Time"),
	TimeZoneNameMap("Antarctica/Mawson", "West Asia Standard Time"),
	TimeZoneNameMap("Antarctica/McMurdo", "New Zealand Standard Time"),
	TimeZoneNameMap("Antarctica/Palmer", "SA Eastern Standard Time"),
	TimeZoneNameMap("Antarctica/Rothera", "SA Eastern Standard Time"),
	TimeZoneNameMap("Antarctica/South_Pole", "Central Standard Time"),
	TimeZoneNameMap("Antarctica/Syowa", "E. Africa Standard Time"),
	TimeZoneNameMap("Antarctica/Troll", "W. Europe Standard Time"),
	TimeZoneNameMap("Antarctica/Vostok", "Central Asia Standard Time"),
	TimeZoneNameMap("Arctic/Longyearbyen", "W. Europe Standard Time"),
	TimeZoneNameMap("Asia/Aden", "Arab Standard Time"),
	TimeZoneNameMap("Asia/Almaty", "Central Asia Standard Time"),
	TimeZoneNameMap("Asia/Amman", "Jordan Standard Time"),
	TimeZoneNameMap("Asia/Anadyr", "Russia Time Zone 11"),
	TimeZoneNameMap("Asia/Aqtau", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Aqtobe", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Ashgabat", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Ashkhabad", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Atyrau", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Baghdad", "Arabic Standard Time"),
	TimeZoneNameMap("Asia/Bahrain", "Arab Standard Time"),
	TimeZoneNameMap("Asia/Baku", "Azerbaijan Standard Time"),
	TimeZoneNameMap("Asia/Bangkok", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Barnaul", "Altai Standard Time"),
	TimeZoneNameMap("Asia/Beirut", "Middle East Standard Time"),
	TimeZoneNameMap("Asia/Bishkek", "Central Asia Standard Time"),
	TimeZoneNameMap("Asia/Brunei", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Calcutta", "India Standard Time"),
	TimeZoneNameMap("Asia/Chita", "Transbaikal Standard Time"),
	TimeZoneNameMap("Asia/Choibalsan", "Ulaanbaatar Standard Time"),
	TimeZoneNameMap("Asia/Chongqing", "China Standard Time"),
	TimeZoneNameMap("Asia/Chungking", "China Standard Time"),
	TimeZoneNameMap("Asia/Colombo", "Sri Lanka Standard Time"),
	TimeZoneNameMap("Asia/Dacca", "Pakistan Standard Time"),
	TimeZoneNameMap("Asia/Damascus", "Syria Standard Time"),
	TimeZoneNameMap("Asia/Dhaka", "Bangladesh Standard Time"),
	TimeZoneNameMap("Asia/Dili", "Tokyo Standard Time"),
	TimeZoneNameMap("Asia/Dubai", "Arabian Standard Time"),
	TimeZoneNameMap("Asia/Dushanbe", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Famagusta", "GTB Standard Time"),
	TimeZoneNameMap("Asia/Gaza", "West Bank Standard Time"),
	TimeZoneNameMap("Asia/Harbin", "China Standard Time"),
	TimeZoneNameMap("Asia/Hebron", "West Bank Standard Time"),
	TimeZoneNameMap("Asia/Ho_Chi_Minh", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Hong_Kong", "China Standard Time"),
	TimeZoneNameMap("Asia/Hovd", "W. Mongolia Standard Time"),
	TimeZoneNameMap("Asia/Irkutsk", "North Asia East Standard Time"),
	TimeZoneNameMap("Asia/Istanbul", "Turkey Standard Time"),
	TimeZoneNameMap("Asia/Jakarta", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Jayapura", "Tokyo Standard Time"),
	TimeZoneNameMap("Asia/Jerusalem", "Israel Standard Time"),
	TimeZoneNameMap("Asia/Kabul", "Afghanistan Standard Time"),
	TimeZoneNameMap("Asia/Kamchatka", "Russia Time Zone 11"),
	TimeZoneNameMap("Asia/Karachi", "Pakistan Standard Time"),
	TimeZoneNameMap("Asia/Kashgar", "Central Asia Standard Time"),
	TimeZoneNameMap("Asia/Kathmandu", "Nepal Standard Time"),
	TimeZoneNameMap("Asia/Katmandu", "Nepal Standard Time"),
	TimeZoneNameMap("Asia/Khandyga", "Yakutsk Standard Time"),
	TimeZoneNameMap("Asia/Kolkata", "India Standard Time"),
	TimeZoneNameMap("Asia/Krasnoyarsk", "North Asia Standard Time"),
	TimeZoneNameMap("Asia/Kuala_Lumpur", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Kuching", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Kuwait", "Arab Standard Time"),
	TimeZoneNameMap("Asia/Macao", "China Standard Time"),
	TimeZoneNameMap("Asia/Macau", "China Standard Time"),
	TimeZoneNameMap("Asia/Magadan", "Magadan Standard Time"),
	TimeZoneNameMap("Asia/Makassar", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Manila", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Muscat", "Arabian Standard Time"),
	TimeZoneNameMap("Asia/Nicosia", "GTB Standard Time"),
	TimeZoneNameMap("Asia/Novokuznetsk", "North Asia Standard Time"),
	TimeZoneNameMap("Asia/Novosibirsk", "N. Central Asia Standard Time"),
	TimeZoneNameMap("Asia/Omsk", "Omsk Standard Time"),
	TimeZoneNameMap("Asia/Oral", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Phnom_Penh", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Pontianak", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Pyongyang", "North Korea Standard Time"),
	TimeZoneNameMap("Asia/Qatar", "Arab Standard Time"),
	TimeZoneNameMap("Asia/Qostanay", "Central Asia Standard Time"),
	TimeZoneNameMap("Asia/Qyzylorda", "Qyzylorda Standard Time"),
	TimeZoneNameMap("Asia/Rangoon", "Myanmar Standard Time"),
	TimeZoneNameMap("Asia/Riyadh", "Arab Standard Time"),
	TimeZoneNameMap("Asia/Saigon", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Sakhalin", "Sakhalin Standard Time"),
	TimeZoneNameMap("Asia/Samarkand", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Seoul", "Korea Standard Time"),
	TimeZoneNameMap("Asia/Shanghai", "China Standard Time"),
	TimeZoneNameMap("Asia/Singapore", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Srednekolymsk", "Russia Time Zone 10"),
	TimeZoneNameMap("Asia/Taipei", "Taipei Standard Time"),
	TimeZoneNameMap("Asia/Tashkent", "West Asia Standard Time"),
	TimeZoneNameMap("Asia/Tbilisi", "Georgian Standard Time"),
	TimeZoneNameMap("Asia/Tehran", "Iran Standard Time"),
	TimeZoneNameMap("Asia/Tel_Aviv", "Israel Standard Time"),
	TimeZoneNameMap("Asia/Thimbu", "Bangladesh Standard Time"),
	TimeZoneNameMap("Asia/Thimphu", "Bangladesh Standard Time"),
	TimeZoneNameMap("Asia/Tokyo", "Tokyo Standard Time"),
	TimeZoneNameMap("Asia/Tomsk", "Tomsk Standard Time"),
	TimeZoneNameMap("Asia/Ujung_Pandang", "Singapore Standard Time"),
	TimeZoneNameMap("Asia/Ulaanbaatar", "Ulaanbaatar Standard Time"),
	TimeZoneNameMap("Asia/Ulan_Bator", "Ulaanbaatar Standard Time"),
	TimeZoneNameMap("Asia/Urumqi", "Central Asia Standard Time"),
	TimeZoneNameMap("Asia/Ust-Nera", "Vladivostok Standard Time"),
	TimeZoneNameMap("Asia/Vientiane", "SE Asia Standard Time"),
	TimeZoneNameMap("Asia/Vladivostok", "Vladivostok Standard Time"),
	TimeZoneNameMap("Asia/Yakutsk", "Yakutsk Standard Time"),
	TimeZoneNameMap("Asia/Yangon", "Myanmar Standard Time"),
	TimeZoneNameMap("Asia/Yekaterinburg", "Ekaterinburg Standard Time"),
	TimeZoneNameMap("Asia/Yerevan", "Caucasus Standard Time"),
	TimeZoneNameMap("Atlantic/Azores", "Azores Standard Time"),
	TimeZoneNameMap("Atlantic/Bermuda", "Atlantic Standard Time"),
	TimeZoneNameMap("Atlantic/Canary", "GMT Standard Time"),
	TimeZoneNameMap("Atlantic/Cape_Verde", "Cape Verde Standard Time"),
	TimeZoneNameMap("Atlantic/Faeroe", "GMT Standard Time"),
	TimeZoneNameMap("Atlantic/Faroe", "W. Europe Standard Time"),
	TimeZoneNameMap("Atlantic/Jan_Mayen", "W. Europe Standard Time"),
	TimeZoneNameMap("Atlantic/Madeira", "GMT Standard Time"),
	TimeZoneNameMap("Atlantic/Reykjavik", "Greenwich Standard Time"),
	TimeZoneNameMap("Atlantic/South_Georgia", "UTC-02"),
	TimeZoneNameMap("Atlantic/St_Helena", "Greenwich Standard Time"),
	TimeZoneNameMap("Atlantic/Stanley", "SA Eastern Standard Time"),
	TimeZoneNameMap("Australia/ACT", "AUS Eastern Standard Time"),
	TimeZoneNameMap("Australia/Adelaide", "Cen. Australia Standard Time"),
	TimeZoneNameMap("Australia/Brisbane", "E. Australia Standard Time"),
	TimeZoneNameMap("Australia/Broken_Hill", "Cen. Australia Standard Time"),
	TimeZoneNameMap("Australia/Canberra", "AUS Eastern Standard Time"),
	TimeZoneNameMap("Australia/Currie", "Tasmania Standard Time"),
	TimeZoneNameMap("Australia/Darwin", "AUS Central Standard Time"),
	TimeZoneNameMap("Australia/Eucla", "Aus Central W. Standard Time"),
	TimeZoneNameMap("Australia/Hobart", "Tasmania Standard Time"),
	TimeZoneNameMap("Australia/LHI", "Lord Howe Standard Time"),
	TimeZoneNameMap("Australia/Lindeman", "E. Australia Standard Time"),
	TimeZoneNameMap("Australia/Lord_Howe", "Lord Howe Standard Time"),
	TimeZoneNameMap("Australia/Melbourne", "AUS Eastern Standard Time"),
	TimeZoneNameMap("Australia/NSW", "AUS Eastern Standard Time"),
	TimeZoneNameMap("Australia/North", "AUS Central Standard Time"),
	TimeZoneNameMap("Australia/Perth", "W. Australia Standard Time"),
	TimeZoneNameMap("Australia/Queensland", "E. Australia Standard Time"),
	TimeZoneNameMap("Australia/South", "AUS Central Standard Time"),
	TimeZoneNameMap("Australia/Sydney", "AUS Eastern Standard Time"),
	TimeZoneNameMap("Australia/Tasmania", "Tasmania Standard Time"),
	TimeZoneNameMap("Australia/Victoria", "AUS Eastern Standard Time"),
	TimeZoneNameMap("Australia/West", "W. Australia Standard Time"),
	TimeZoneNameMap("Australia/Yancowinna", "Lord Howe Standard Time"),
	TimeZoneNameMap("BET", "UTC-03"),
	TimeZoneNameMap("BST", "Greenwich Standard Time"),
	TimeZoneNameMap("Brazil/Acre", "SA Pacific Standard Time"),
	TimeZoneNameMap("Brazil/DeNoronha", "UTC-02"),
	TimeZoneNameMap("Brazil/East", "E. South America Standard Time"),
	TimeZoneNameMap("Brazil/West", "E. South America Standard Time"),
	TimeZoneNameMap("CAT", "South Africa Standard Time"),
	TimeZoneNameMap("CET", "Central European Standard Time"),
	TimeZoneNameMap("CNT", "UTC-03:30"),
	TimeZoneNameMap("CST", "Central Standard Time"),
	TimeZoneNameMap("CST6CDT", "Central Standard Time"),
	TimeZoneNameMap("CTT", "UTC+08"),
	TimeZoneNameMap("Canada/Atlantic", "Atlantic Standard Time"),
	TimeZoneNameMap("Canada/Central", "Central Standard Time"),
	TimeZoneNameMap("Canada/East-Saskatchewan", "Canada Central Standard Time"),
	TimeZoneNameMap("Canada/Eastern", "Eastern Standard Time"),
	TimeZoneNameMap("Canada/Mountain", "Mountain Standard Time"),
	TimeZoneNameMap("Canada/Newfoundland", "Newfoundland Standard Time"),
	TimeZoneNameMap("Canada/Pacific", "Pacific Standard Time"),
	TimeZoneNameMap("Canada/Saskatchewan", "Canada Central Standard Time"),
	TimeZoneNameMap("Canada/Yukon", "Yukon Standard Time"),
	TimeZoneNameMap("Chile/Continental", "Pacific SA Standard Time"),
	TimeZoneNameMap("Chile/EasterIsland", "Pacific SA Standard Time"),
	TimeZoneNameMap("Cuba", "Cuba Standard Time"),
	TimeZoneNameMap("EAT", "E. Africa Standard Time"),
	TimeZoneNameMap("ECT", "Central Europe Standard Time"),
	TimeZoneNameMap("EET", "GTB Standard Time"),
	TimeZoneNameMap("EST", "SA Pacific Standard Time"),
	TimeZoneNameMap("EST5EDT", "Eastern Standard Time"),
	TimeZoneNameMap("Egypt", "Egypt Standard Time"),
	TimeZoneNameMap("Eire", "Romance Standard Time"),
	TimeZoneNameMap("Etc/GMT", "UTC"),
	TimeZoneNameMap("Etc/GMT+0", "UTC"),
	TimeZoneNameMap("Etc/GMT+1", "UTC+01"),
	TimeZoneNameMap("Etc/GMT+2", "UTC-02"),
	TimeZoneNameMap("Etc/GMT+3", "UTC+03"),
	TimeZoneNameMap("Etc/GMT+4", "UTC+04"),
	TimeZoneNameMap("Etc/GMT+5", "UTC+05"),
	TimeZoneNameMap("Etc/GMT+6", "UTC+06"),
	TimeZoneNameMap("Etc/GMT+7", "UTC+07"),
	TimeZoneNameMap("Etc/GMT+8", "UTC+08"),
	TimeZoneNameMap("Etc/GMT+9", "UTC+09"),
	TimeZoneNameMap("Etc/GMT+10", "UTC+10"),
	TimeZoneNameMap("Etc/GMT+11", "UTC+11"),
	TimeZoneNameMap("Etc/GMT+12", "UTC+12"),
	TimeZoneNameMap("Etc/GMT0", "UTC"),
	TimeZoneNameMap("Etc/GMT-0", "UTC"),
	TimeZoneNameMap("Etc/GMT-1", "UTC-01"),
	TimeZoneNameMap("Etc/GMT-2", "UTC-02"),
	TimeZoneNameMap("Etc/GMT-3", "UTC-03"),
	TimeZoneNameMap("Etc/GMT-4", "UTC-04"),
	TimeZoneNameMap("Etc/GMT-5", "UTC-05"),
	TimeZoneNameMap("Etc/GMT-6", "UTC-06"),
	TimeZoneNameMap("Etc/GMT-7", "UTC-07"),
	TimeZoneNameMap("Etc/GMT-8", "UTC-08"),
	TimeZoneNameMap("Etc/GMT-9", "UTC-09"),
	TimeZoneNameMap("Etc/GMT-10", "UTC-10"),
	TimeZoneNameMap("Etc/GMT-11", "UTC-11"),
	TimeZoneNameMap("Etc/GMT-12", "UTC-12"),
	TimeZoneNameMap("Etc/GMT-13", "UTC-13"),
	TimeZoneNameMap("Etc/GMT-14", "UTC-14"),
	TimeZoneNameMap("Etc/Greenwich", "UTC"),
	TimeZoneNameMap("Etc/UCT", "UTC"),
	TimeZoneNameMap("Etc/UTC", "UTC"),
	TimeZoneNameMap("Etc/Universal", "UTC"),
	TimeZoneNameMap("Etc/Zulu", "UTC"),
	TimeZoneNameMap("Europe/Amsterdam", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Andorra", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Astrakhan", "Astrakhan Standard Time"),
	TimeZoneNameMap("Europe/Athens", "GTB Standard Time"),
	TimeZoneNameMap("Europe/Belfast", "New Zealand Standard Time"),
	TimeZoneNameMap("Europe/Belgrade", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/Berlin", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Bratislava", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/Brussels", "Romance Standard Time"),
	TimeZoneNameMap("Europe/Bucharest", "GTB Standard Time"),
	TimeZoneNameMap("Europe/Budapest", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/Busingen", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Chisinau", "E. Europe Standard Time"),
	TimeZoneNameMap("Europe/Copenhagen", "Romance Standard Time"),
	TimeZoneNameMap("Europe/Dublin", "GMT Standard Time"),
	TimeZoneNameMap("Europe/Gibraltar", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Guernsey", "GMT Standard Time"),
	TimeZoneNameMap("Europe/Helsinki", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Isle_of_Man", "GMT Standard Time"),
	TimeZoneNameMap("Europe/Istanbul", "Turkey Standard Time"),
	TimeZoneNameMap("Europe/Jersey", "GMT Standard Time"),
	TimeZoneNameMap("Europe/Kaliningrad", "Kaliningrad Standard Time"),
	TimeZoneNameMap("Europe/Kiev", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Kirov", "Russian Standard Time"),
    TimeZoneNameMap("Europe/Kyiv", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Lisbon", "GMT Standard Time"),
	TimeZoneNameMap("Europe/Ljubljana", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/London", "GMT Standard Time"),
	TimeZoneNameMap("Europe/Luxembourg", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Madrid", "Romance Standard Time"),
	TimeZoneNameMap("Europe/Malta", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Mariehamn", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Minsk", "Belarus Standard Time"),
	TimeZoneNameMap("Europe/Monaco", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Moscow", "Russian Standard Time"),
	TimeZoneNameMap("Europe/Nicosia", "GTB Standard Time"),
	TimeZoneNameMap("Europe/Oslo", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Paris", "Romance Standard Time"),
	TimeZoneNameMap("Europe/Podgorica", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/Prague", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/Riga", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Rome", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Samara", "Russia Time Zone 3"),
	TimeZoneNameMap("Europe/San_Marino", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Sarajevo", "Central European Standard Time"),
	TimeZoneNameMap("Europe/Saratov", "Saratov Standard Time"),
	TimeZoneNameMap("Europe/Simferopol", "Russian Standard Time"),
	TimeZoneNameMap("Europe/Skopje", "Central European Standard Time"),
	TimeZoneNameMap("Europe/Sofia", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Stockholm", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Tallinn", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Tirane", "Central Europe Standard Time"),
	TimeZoneNameMap("Europe/Tiraspol", "E. Europe Standard Time"),
	TimeZoneNameMap("Europe/Ulyanovsk", "Astrakhan Standard Time"),
	TimeZoneNameMap("Europe/Uzhgorod", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Vaduz", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Vatican", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Vienna", "W. Europe Standard Time"),
	TimeZoneNameMap("Europe/Vilnius", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Volgograd", "Volgograd Standard Time"),
	TimeZoneNameMap("Europe/Warsaw", "Central European Standard Time"),
	TimeZoneNameMap("Europe/Zagreb", "Central European Standard Time"),
	TimeZoneNameMap("Europe/Zaporozhye", "FLE Standard Time"),
	TimeZoneNameMap("Europe/Zurich", "W. Europe Standard Time"),
	TimeZoneNameMap("Factory", null),
	TimeZoneNameMap("GB", "UTC"),
	TimeZoneNameMap("GB-Eire", "UTC"),
	TimeZoneNameMap("GMT+0", "UTC"),
	TimeZoneNameMap("GMT-0", "UTC"),
	TimeZoneNameMap("GMT0", "UTC"),
	TimeZoneNameMap("Greenwich", "UTC"),
	TimeZoneNameMap("HST", "Hawaiian Standard Time"),
	TimeZoneNameMap("Hongkong", "China Standard Time"),
	TimeZoneNameMap("IET", "W. Europe Standard Time"),
	TimeZoneNameMap("IST", "India Standard Time"),
	TimeZoneNameMap("Iceland", "Greenwich Standard Time"),
	TimeZoneNameMap("Indian/Antananarivo", "E. Africa Standard Time"),
	TimeZoneNameMap("Indian/Chagos", "Central Asia Standard Time"),
	TimeZoneNameMap("Indian/Christmas", "SE Asia Standard Time"),
	TimeZoneNameMap("Indian/Cocos", "Myanmar Standard Time"),
	TimeZoneNameMap("Indian/Comoro", "E. Africa Standard Time"),
	TimeZoneNameMap("Indian/Kerguelen", "West Asia Standard Time"),
	TimeZoneNameMap("Indian/Mahe", "Mauritius Standard Time"),
	TimeZoneNameMap("Indian/Maldives", "West Asia Standard Time"),
	TimeZoneNameMap("Indian/Mauritius", "Mauritius Standard Time"),
	TimeZoneNameMap("Indian/Mayotte", "E. Africa Standard Time"),
	TimeZoneNameMap("Indian/Reunion", "Mauritius Standard Time"),
	TimeZoneNameMap("Iran", "Iran Standard Time"),
	TimeZoneNameMap("Israel", "Israel Standard Time"),
	TimeZoneNameMap("JST", "Tokyo Standard Time"),
	TimeZoneNameMap("Jamaica", "SA Pacific Standard Time"),
	TimeZoneNameMap("Japan", "Tokyo Standard Time"),
	TimeZoneNameMap("Kwajalein", "UTC+12"),
	TimeZoneNameMap("Libya", "Libya Standard Time"),
	TimeZoneNameMap("MET", "Central European Standard Time"),
	TimeZoneNameMap("MIT", "Eastern Standard Time"),
	TimeZoneNameMap("MST", "Mountain Standard Time"),
	TimeZoneNameMap("MST7MDT", "Mountain Standard Time"),
	TimeZoneNameMap("Mexico/BajaNorte", "Pacific Standard Time (Mexico)"),
	TimeZoneNameMap("Mexico/BajaSur", "Mountain Standard Time (Mexico)"),
	TimeZoneNameMap("Mexico/General", "Central Standard Time (Mexico)"),
	TimeZoneNameMap("NET", "UTC+04"),
	TimeZoneNameMap("NST", "Newfoundland Standard Time"),
	TimeZoneNameMap("NZ", "New Zealand Standard Time"),
	TimeZoneNameMap("NZ-CHAT", "Chatham Islands Standard Time"),
	TimeZoneNameMap("Navajo", "US Mountain Standard Time"),
	TimeZoneNameMap("PLT", "SA Pacific Standard Time"),
	TimeZoneNameMap("PNT", "UTC-07"),
	TimeZoneNameMap("PRC", "China Standard Time"),
	TimeZoneNameMap("PRT", "UTC-04"),
	TimeZoneNameMap("PST", "UTC-08"),
	TimeZoneNameMap("PST8PDT", "Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Apia", "Samoa Standard Time"),
	TimeZoneNameMap("Pacific/Auckland", "New Zealand Standard Time"),
	TimeZoneNameMap("Pacific/Bougainville", "Bougainville Standard Time"),
	TimeZoneNameMap("Pacific/Chatham", "Chatham Islands Standard Time"),
	TimeZoneNameMap("Pacific/Chuuk", "UTC+10"),
	TimeZoneNameMap("Pacific/Easter", "Easter Island Standard Time"),
	TimeZoneNameMap("Pacific/Efate", "Central Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Enderbury", "UTC+13"),
	TimeZoneNameMap("Pacific/Fakaofo", "UTC+13"),
	TimeZoneNameMap("Pacific/Fiji", "Fiji Standard Time"),
	TimeZoneNameMap("Pacific/Funafuti", "UTC+12"),
	TimeZoneNameMap("Pacific/Galapagos", "Central America Standard Time"),
	TimeZoneNameMap("Pacific/Gambier", "UTC-09"),
	TimeZoneNameMap("Pacific/Guadalcanal", "Central Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Guam", "West Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Honolulu", "Hawaiian Standard Time"),
	TimeZoneNameMap("Pacific/Johnston", "Hawaiian Standard Time"),
	TimeZoneNameMap("Pacific/Kiritimati", "Line Islands Standard Time"),
	TimeZoneNameMap("Pacific/Kosrae", "Central Pacific Standard Time"),
    TimeZoneNameMap("Pacific/Kanton", "UTC+13"),
	TimeZoneNameMap("Pacific/Kwajalein", "UTC+12"),
	TimeZoneNameMap("Pacific/Majuro", "UTC+12"),
	TimeZoneNameMap("Pacific/Marquesas", "Marquesas Standard Time"),
	TimeZoneNameMap("Pacific/Midway", "UTC-11"),
	TimeZoneNameMap("Pacific/Nauru", "UTC+12"),
	TimeZoneNameMap("Pacific/Niue", "UTC-11"),
	TimeZoneNameMap("Pacific/Norfolk", "Norfolk Standard Time"),
	TimeZoneNameMap("Pacific/Noumea", "Central Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Pago_Pago", "UTC-11"),
	TimeZoneNameMap("Pacific/Palau", "Tokyo Standard Time"),
	TimeZoneNameMap("Pacific/Pitcairn", "UTC-08"),
	TimeZoneNameMap("Pacific/Pohnpei", "Central Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Ponape", "Central Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Port_Moresby", "West Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Rarotonga", "Hawaiian Standard Time"),
	TimeZoneNameMap("Pacific/Saipan", "West Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Samoa", "Samoa Standard Time"),
	TimeZoneNameMap("Pacific/Tahiti", "Hawaiian Standard Time"),
	TimeZoneNameMap("Pacific/Tarawa", "UTC+12"),
	TimeZoneNameMap("Pacific/Tongatapu", "Tonga Standard Time"),
	TimeZoneNameMap("Pacific/Truk", "West Pacific Standard Time"),
	TimeZoneNameMap("Pacific/Wake", "UTC+12"),
	TimeZoneNameMap("Pacific/Wallis", "UTC+12"),
	TimeZoneNameMap("Pacific/Yap", "West Pacific Standard Time"),
	TimeZoneNameMap("Poland", "Central European Standard Time"),
	TimeZoneNameMap("Portugal", "GMT Standard Time"),
	TimeZoneNameMap("ROC", "Eastern Standard Time"),
	TimeZoneNameMap("ROK", "Korea Standard Time"),
	TimeZoneNameMap("SST", "UTC-11"),
	TimeZoneNameMap("Singapore", "Singapore Standard Time"),
	TimeZoneNameMap("SystemV/AST4", "UTC-04"),
	TimeZoneNameMap("SystemV/AST4ADT", "UTC-04"),
	TimeZoneNameMap("SystemV/CST6", "UTC-06"),
	TimeZoneNameMap("SystemV/CST6CDT", "UTC-06"),
	TimeZoneNameMap("SystemV/EST5", "UTC-05"),
	TimeZoneNameMap("SystemV/EST5EDT", "UTC-05"),
	TimeZoneNameMap("SystemV/HST10", "UTC-10"),
	TimeZoneNameMap("SystemV/MST7", "UTC-07"),
	TimeZoneNameMap("SystemV/MST7MDT", "UTC-07"),
	TimeZoneNameMap("SystemV/PST8", "UTC-08"),
	TimeZoneNameMap("SystemV/PST8PDT", "UTC-08"),
	TimeZoneNameMap("SystemV/YST9", "UTC-09"),
	TimeZoneNameMap("SystemV/YST9YDT", "UTC-09"),
	TimeZoneNameMap("Turkey", "Turkey Standard Time"),
	TimeZoneNameMap("UCT", "UTC"),
	TimeZoneNameMap("US/Alaska", "Alaskan Standard Time"),
	TimeZoneNameMap("US/Aleutian", "Aleutian Standard Time"),
	TimeZoneNameMap("US/Arizona", "US Mountain Standard Time"),
	TimeZoneNameMap("US/Central", "Central Standard Time"),
	TimeZoneNameMap("US/East-Indiana", "Central Standard Time"),
	TimeZoneNameMap("US/Eastern", "Eastern Standard Time"),
	TimeZoneNameMap("US/Hawaii", "Hawaiian Standard Time"),
	TimeZoneNameMap("US/Indiana-Starke", "Central Standard Time"),
	TimeZoneNameMap("US/Michigan", "Central Standard Time"),
	TimeZoneNameMap("US/Mountain", "Mountain Standard Time"),
	TimeZoneNameMap("US/Pacific", "Pacific Standard Time"),
	TimeZoneNameMap("US/Pacific-New", "Pacific Standard Time"),
	TimeZoneNameMap("US/Samoa", "Samoa Standard Time"),
	TimeZoneNameMap("UTC", "UTC"),
	TimeZoneNameMap("Universal", "UTC"),
	TimeZoneNameMap("VST", "UTC+10"),
	TimeZoneNameMap("W-SU", "UTC+03"),
	TimeZoneNameMap("WET", "UTC"),
	TimeZoneNameMap("Zulu", "UTC"),
	];


private:

static immutable TimeZoneInfoMapList defaultTimeZoneInfoMaps;

shared static this() nothrow @trusted
{
    defaultTimeZoneInfoMaps = cast(immutable TimeZoneInfoMapList)getDefaultTimeZoneInfoMaps();

    //import std.stdio : writeln; debug writeln("defaultTimeZoneInfoMaps.zoneInfos.length=", defaultTimeZoneInfoMaps.zoneInfos.length);
}

version(none)
unittest // IanaWindowNameMapList
{
static immutable string mapXml = q"XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE supplementalData SYSTEM "../../common/dtd/ldmlSupplemental.dtd">
<!--
Copyright © 1991-2013 Unicode, Inc.
CLDR data files are interpreted according to the LDML specification (http://unicode.org/reports/tr35/)
For terms of use, see http://www.unicode.org/copyright.html
-->

<supplementalData>
    <version number="$Revision$"/>
    <windowsZones>
        <mapTimezones otherVersion="7e11800" typeVersion="2021a">
            <!-- (UTC-09:00) Alaska -->
            <mapZone other="Alaskan Standard Time" territory="001" type="America/Anchorage"/>
            <mapZone other="Alaskan Standard Time" territory="US" type="America/Anchorage America/Juneau America/Metlakatla America/Nome America/Sitka America/Yakutat"/>
        </mapTimezones>
    </windowsZones>
</supplementalData>
XML";

    IanaWindowNameMapList maps = IanaWindowNameMapList.parse(mapXml);
    assert(maps !is null);

    // Valid tests
    assert(maps.findIanas("Alaskan Standard Time").length == 7);
    assert(maps.findIana("Alaskan Standard Time") !is null);
    assert(maps.toIana("Alaskan Standard Time") == "America/Anchorage");
    assert(maps.findWindows("America/Anchorage").length == 2);
    assert(maps.findWindow("America/Anchorage") !is null);
    assert(maps.toWindow("America/Anchorage") == "Alaskan Standard Time");

    // Invalid tests
    assert(maps.findIanas("Alaskan XYZ").length == 0);
    assert(maps.findIana("Alaskan XYZ") is null);
    assert(maps.toIana("Alaskan XYZ").length == 0);
    assert(maps.findWindows("America/AnchorageXYZ").length == 0);
    assert(maps.findWindow("America/AnchorageXYZ") is null);
    assert(maps.toWindow("America/AnchorageXYZ").length == 0);
}

unittest // defaultTimeZoneInfoMaps
{
    import pham.dtm.dtm_time_zone : ZoneOffset;

    auto m = defaultTimeZoneInfoMaps.timeZoneMap(1);
    assert(m.isValid());
    assert(m.zoneIdOrName == "UTC", "'" ~ m.zoneIdOrName ~ "'");
    assert(m.zoneInfo !is null);
    assert(m.zoneInfo.id == "UTC");
    assert(m.zoneInfo.baseUtcOffset == ZoneOffset(0));
    assert(!m.zoneInfo.supportsDaylightSavingTime);

    m = defaultTimeZoneInfoMaps.timeZoneMap("UTC");
    assert(m.isValid());
    assert(m.zoneInfo !is null);
    assert(m.zoneInfo.id == "UTC");
    assert(m.zoneInfo.baseUtcOffset == ZoneOffset(0));
    assert(!m.zoneInfo.supportsDaylightSavingTime);

    m = defaultTimeZoneInfoMaps.timeZoneMap("Etc/Zulu");
    assert(m.isValid());
    assert(m.zoneInfo !is null);
    assert(m.zoneInfo.id == "UTC");
    assert(m.zoneInfo.baseUtcOffset == ZoneOffset(0));
    assert(!m.zoneInfo.supportsDaylightSavingTime);

    m = defaultTimeZoneInfoMaps.timeZoneMap("US/Eastern");
    assert(m.isValid());
    assert(m.zoneInfo !is null);
    assert(m.zoneInfo.id == "Eastern Standard Time");
    assert(m.zoneInfo.baseUtcOffset == ZoneOffset(-300));
    assert(m.zoneInfo.supportsDaylightSavingTime);

    m = defaultTimeZoneInfoMaps.timeZoneMap("Unknown Time Zone");
    assert(!m.isValid());
    assert(m.zoneIdOrName.length == 0);
    assert(m.zoneInfo is null);
}
