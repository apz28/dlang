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

module pham.dtm.time_zone_map;

import std.uni : sicmp;

import pham.utl.result;
import pham.dtm.time_zone : TimeZoneInfo;
import pham.dtm.time_zone_default;

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
        import pham.xml.dom;

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
    this(MapId id, string zoneId, TimeZoneInfo* info) @nogc pure
    {
        this._id = id;
        this._zoneId = zoneId;
        this._info = info;
    }

	bool isValid() const @nogc pure
    {
		return _id != 0 && _zoneId.length != 0 && _info !is null;
    }

    static TimeZoneInfoMap timeZoneMap(MapId id) @nogc nothrow @trusted
    {
        return (cast()defaultTimeZoneInfoMaps).timeZoneMap(id);
    }

    static TimeZoneInfoMap timeZoneMap(string zoneId) @nogc nothrow @trusted
    {
        return (cast()defaultTimeZoneInfoMaps).timeZoneMap(zoneId);
    }

    @property MapId id() const @nogc pure
    {
        return _id;
    }

    @property const(TimeZoneInfo)* info() const @nogc pure
    {
        return _info;
    }

    @property string zoneId() const @nogc pure
    {
        return _zoneId;
    }

private:
    string _zoneId;
    TimeZoneInfo* _info;
    MapId _id; // Runtime assigned value
}

class TimeZoneInfoMapList
{
nothrow @safe:

public:
    this(TimeZoneInfo[] zones) pure
    {
        this.zones = zones;
        this.initDicts;
    }

    final void add(MapId id, TimeZoneInfo* info) pure
    {
        auto map = TimeZoneInfoMap(id, info.id, info);
        zoneIds[info.id] = map;
        ids[id] = map;
    }

    final void add(MapId id, string zoneId, TimeZoneInfo* info) pure
    {
        auto map = TimeZoneInfoMap(id, zoneId, info);
        zoneIds[zoneId] = map;
        if ((id in ids) is null)
            ids[id] = map;
    }

    final TimeZoneInfoMap timeZoneMap(MapId id) @nogc pure
    {
        if (auto e = id in ids)
            return *e;
        else
            return TimeZoneInfoMap(0, null, null);
    }

    final TimeZoneInfoMap timeZoneMap(string zoneId) @nogc pure
    {
        if (auto e = zoneId in zoneIds)
            return *e;
        else
            return TimeZoneInfoMap(0, null, null);
    }

private:
    final void initDicts() pure
    {
        MapId idSeed = 30; // Reserve first 30 for utc ones
        ptrdiff_t utcIdIndex = -1, utcId2Index = -1;
        foreach (i; 0..zones.length)
        {
            auto tzi = &zones[i];

            if (tzi.id == TimeZoneInfo.utcId)
            {
                utcIdIndex = i;
                add(TimeZoneInfo.utcIdInt, tzi);
            }
            else if (tzi.id == TimeZoneInfo.utcId2)
            {
                utcId2Index = i;
                add(TimeZoneInfo.utcId2Int, tzi);
            }
            else
                add(++idSeed, tzi);
        }

        // Add alias if not found
        if (utcId2Index == -1 && utcIdIndex >= 0)
            add(TimeZoneInfo.utcId2Int, TimeZoneInfo.utcId2, &zones[utcIdIndex]);
    }

private:
    TimeZoneInfoMap[MapId] ids;
    TimeZoneInfoMap[string] zoneIds;
    TimeZoneInfo[] zones;
}


private:

static immutable TimeZoneInfoMapList defaultTimeZoneInfoMaps;

shared static this() @trusted
{
    defaultTimeZoneInfoMaps = cast(immutable TimeZoneInfoMapList)getDefaultTimeZoneInfoMaps();
}

version (none)
unittest // IanaWindowNameMapList
{
    import pham.utl.test;
    traceUnitTest("unittest pham.dtm.time_zone_map.IanaWindowNameMapList");

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
