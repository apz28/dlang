/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.dtm.time_zone_default_tzdata;

import core.time : dur, Duration;
import std.array : Appender, split;
import std.ascii : isWhite;
import std.algorithm.searching : countUntil;
import std.string : splitLines;
import std.uni : sicmp;

import pham.utl.numeric_parser : NumericParsedKind, parseIntegral;
import pham.utl.result : ResultIf;
import pham.dtm.date : DayOfWeek, Date, DateTime;
import pham.dtm.date_time_parse;
import pham.dtm.tick : DateTimeZoneKind, ErrorOp, toDayOfWeekUS, toMonthUS;
import pham.dtm.time : Time;
import pham.dtm.time_zone : AdjustmentRule, TimeZoneInfo, TransitionTime;

nothrow @safe:

TimeZoneInfo[] getDefaultTimeZoneInfosByTZData(string tzdataText)
{
    scope (failure)
        return null;

    if (tzdataText.length == 0)
        return null;

    auto tzDatabase = parseTZData(tzdataText);


    TimeZoneInfo[] result;
    result.reserve(200);

    return result;
}

pragma(inline, true)
bool sameFirst(string s, string sub) @nogc pure
{
    return (s.length >= sub.length && sub.length != 0 && sicmp(s[0..sub.length], sub) == 0)
        || (s.length == sub.length && sub.length == 0);
}

pragma(inline, true)
bool sameLast(string s, string sub) @nogc pure
{
    return (s.length >= sub.length && sub.length != 0 && sicmp(s[$-sub.length..$], sub) == 0)
        || (s.length == sub.length && sub.length == 0);
}


private:

static immutable string linkId = "Link";
static immutable string ruleId = "Rule";
static immutable string zoneId = "Zone";

static immutable string lastDoW = "last";
static immutable string minDate = "min";
static immutable string maxDate = "max";
static immutable string onlyDate = "only";

enum int notUsedInt = -1;

struct DayInfo
{
    int dayOfMonth;
    int dayOfWeek;
    bool advanceDayOfWeek;
}

struct LinkInfo
{
    // Order is important
    string realName;
    string aliasName;
}

struct RuleInfo
{
    // Order is important
    string name;
    int yearBegin;
    int yearEnd;
    int month;
    DayInfo day;
    TimeInfo timeOfDay;
    TimeInfo daylightDelta;
    string letters;
}

struct TimeInfo
{
    // Order is important
    Time time;
    char mode;
    bool addDay;

    static bool isValidMode(char c) @nogc nothrow pure @safe
    {
        switch (c)
        {
            // standard
            case 's':
            case 'S':
            // utc
            case 'g':
            case 'G':
            case 'u':
            case 'U':
            case 'z':
            case 'Z':
            // wall
            case 'w':
            case 'W':
                return true;
            default:
                return false;
        }
    }
}

struct ZoneInfo
{
    // Order is important
    string name;
    TimeInfo utcOffset;
    string ruleName;
    string format;
    DateTime untilDateTime;
}

struct TZDatabase
{
nothrow @safe:

    void addLink(LinkInfo link)
    {
        links[link.aliasName] = link;
    }

    void addRule(RuleInfo rule)
    {
        auto p = rule.name in rules;
        if (p !is null)
            (*p) ~= rule;
        else
            rules[rule.name] = [rule];
    }

    void addZone(ZoneInfo zone)
    {
        auto p = zone.name in zones;
        if (p !is null)
            (*p) ~= zone;
        else
            zones[zone.name] = [zone];
    }

    alias RuleInfoSet = RuleInfo[];
    alias ZoneInfoSet = ZoneInfo[];

    LinkInfo[string] links;
    RuleInfoSet[string] rules;
    ZoneInfoSet[string] zones;
}

string normalizeWhite(string line) pure
{
    enum useResult = -1;
    Appender!string result;
    ptrdiff_t leadingChars = 0;
    bool wasWhite = false;
    foreach (i; 0..line.length)
    {
        const char c = line[i];
        if (isWhite(c))
        {
            if (wasWhite)
                continue;

            if (leadingChars > 0)
                result.put(line[0..leadingChars]);
            result.put(' ');

            wasWhite = true;
            leadingChars = useResult; // No longer use
        }
        else
        {
            wasWhite = false;
            if (leadingChars >= 0)
                leadingChars++;
            else
                result.put(c);
        }
    }

    return leadingChars == useResult ? result.data : line;
}

TZDatabase parseTZData(string tzdataText)
{
    TZDatabase result;

    string zoneName;
    const tzdataLines = splitLines(tzdataText);
    foreach (tzdataLine; tzdataLines)
    {
        auto line = tzdataLine.removeComment().trimRight().normalizeWhite();
        if (line.length == 0)
            continue;

        auto elems = line.split(" ");
        if (sicmp(elems[0], linkId) == 0)
        {
            zoneName = null;
            auto linkInfo = toLink(elems);
            if (linkInfo)
                result.addLink(linkInfo);
        }
        else if (sicmp(elems[0], ruleId) == 0)
        {
            zoneName = null;
            auto ruleInfo = toRule(elems);
            if (ruleInfo)
                result.addRule(ruleInfo);
        }
        else if (sicmp(elems[0], zoneId) == 0)
        {
            auto zoneInfo = toZone(elems, null);
            if (zoneInfo)
            {
                zoneName = zoneInfo.name;
                result.addZone(zoneInfo);
            }
        }
        else if (zoneName.length != 0 && elems[0].length == 0)
        {
            auto zoneInfo = toZone(elems, zoneName);
            if (zoneInfo)
                result.addZone(zoneInfo);
        }
    }

    return result;
}

string removeComment(string line) @nogc pure
{
    foreach (i; 0..line.length)
    {
        if (line[i] == '#')
            return i == 0 ? null : line[0..i];
    }
    return line;
}

ResultIf!DayInfo toDay(string v) pure
{
    scope (failure)
        return ResultIf!DayInfo.error(1);

    ResultIf!int dayOfMonth = ResultIf!int.ok(1);
    ResultIf!int dayOfWeek = ResultIf!int.ok(notUsedInt);
    bool advanceDayOfWeek = false;

    if (sameFirst(v, lastDoW))
    {
        dayOfMonth = ResultIf!int.ok(notUsedInt);
        dayOfWeek = toDayOfWeekUS(v[lastDoW.length..$]);

        return dayOfMonth && dayOfWeek
            ? ResultIf!DayInfo.ok(DayInfo(dayOfMonth, dayOfWeek, advanceDayOfWeek))
            : ResultIf!DayInfo.error(1);
    }

    auto i = countUntil(v, ">=");
    if (i >= 0)
    {
        dayOfMonth = toDayOfMonth(v[i + 2..$]);
        dayOfWeek = toDayOfWeekUS(v[0..i]);
        advanceDayOfWeek = true;
    }
    else
    {
        i = countUntil(v, "<=");
        if (i >= 0)
        {
            dayOfMonth = toDayOfMonth(v[i + 2..$]);
            dayOfWeek = toDayOfWeekUS(v[0..i]);
        }
        else
        {
            dayOfMonth = toDayOfMonth(v);
        }
    }

    return dayOfMonth && dayOfWeek
        ? ResultIf!DayInfo.ok(DayInfo(dayOfMonth, dayOfWeek, advanceDayOfWeek))
        : ResultIf!DayInfo.error(1);
}

ResultIf!int toDayOfMonth(string v) pure
{
    int n;
    if (parseIntegral(v, n) == NumericParsedKind.ok)
    {
        if (n >= 1 && n <= 31)
            return ResultIf!int.ok(n);
    }

    return ResultIf!int.error(1);
}

ResultIf!LinkInfo toLink(string[] elems) @nogc pure
{
    return elems.length < 3 || elems[1].length == 0 || elems[2].length == 0
        ? ResultIf!LinkInfo.error(1)
        : ResultIf!LinkInfo.ok(LinkInfo(elems[1], elems[2]));
}

ResultIf!RuleInfo toRule(string[] elems)
{
    if (elems.length < 9)
        return ResultIf!RuleInfo.error(1);

    const name = elems[1];
    const yb = toYearBegin(elems[2]);
    const ye = toYearEnd(elems[3], yb);
    const m = toMonthUS(elems[5]);
    const d = toDay(elems[6]);
    const tod = toTime(elems[7]);
    const tdelta = toTime(elems[8]);
    const letters = elems.length >= 10 ? elems[9] : null;

    return name.length != 0 && yb && ye && m && d && tod && tdelta
        ? ResultIf!RuleInfo.ok(RuleInfo(name, yb, ye, m, d, tod, tdelta, letters))
        : ResultIf!RuleInfo.error(1);
}

ResultIf!TimeInfo toTime(string v)
{
    char mode = v.length != 0 ? v[$ - 1] : '\0';
    if (TimeInfo.isValidMode(mode))
        v = v[0..$ - 1];
    else
        mode = '\0';

    if (v.length == 0)
        return ResultIf!TimeInfo.error(1);

    static DateTimePattern pattern(string patternText) pure
    {
        auto result = DateTimePattern.usShortDateTime;
        result.timeSeparator = ':';
        result.patternText = patternText;
        return result;
    }

    bool addDay = false;
    Time time;
    if (v == "24:00")
    {
        time = Time.midnight;
        addDay = true;
    }
    // As of TZDB 2018f, Japan's fallback transitions occur at 25:00. We can't
    // represent this entirely accurately, but this is as close as we can approximate it.
    else if (v == "25:00")
    {
        time = Time(1, 0, 0, 0, DateTimeZoneKind.local);
        addDay = true;
    }
    else
    {
        scope const patterns = [pattern("hh:nn:ss.zzz"), pattern("hh:nn"), pattern("hh")];
        if (tryParse!Time(v, patterns, time) != DateTimeParser.noError)
            return ResultIf!TimeInfo.error(1);
    }

    return ResultIf!TimeInfo.ok(TimeInfo(time, mode, addDay));
}

ResultIf!int toYearBegin(string v) pure
{
    if (sicmp(v, minDate) == 0)
        return ResultIf!int.ok(DateTime.minYear);

    int n;
    if (parseIntegral(v, n) == NumericParsedKind.ok)
    {
        if (DateTime.isValidYear(n) == ErrorOp.none)
            return ResultIf!int.ok(n);
    }

    return ResultIf!int.error(1);
}

ResultIf!int toYearEnd(string v, ResultIf!int onlyYear) pure
{
    if (sicmp(v, maxDate) == 0)
        return ResultIf!int.ok(DateTime.maxYear);

    if (sicmp(v, onlyDate) == 0)
        return onlyYear;

    int n;
    if (parseIntegral(v, n) == NumericParsedKind.ok)
    {
        if (DateTime.isValidYear(n) == ErrorOp.none)
            return ResultIf!int.ok(n);
    }

    return ResultIf!int.error(1);
}

ResultIf!ZoneInfo toZone(string[] elems, string previousZoneName)
{
    if ((previousZoneName.length == 0 && elems.length < 5)
        || (previousZoneName.length != 0 && elems.length < 4))
        return ResultIf!ZoneInfo.error(1);

    auto zoneName = previousZoneName.length != 0 ? previousZoneName : elems[1];
    size_t i = previousZoneName.length != 0 ? 1 : 2;
    const utcOffset = toTime(elems[i++]);
    auto ruleName = elems[i++];
    auto format = elems[i++];
    DateTime untilDateTime;
    if (i < elems.length)
    {
        const untilYear = toYearEnd(elems[i++], ResultIf!int.error(1));
        const untilMonth = i < elems.length ? toMonthUS(elems[i++]) : ResultIf!int.ok(1);
        const untilDay = i < elems.length ? toDayOfMonth(elems[i++]) : ResultIf!int.ok(1);
        const untilTime = i < elems.length ? toTime(elems[i++]) : ResultIf!TimeInfo.ok(TimeInfo(Time.midnight, '\0', false));

        if (untilYear && untilMonth && untilDay && untilTime)
            untilDateTime = DateTime(Date(untilYear, untilMonth, untilDay), untilTime.time);
        else
            return ResultIf!ZoneInfo.error(1);
    }
    else
        untilDateTime = DateTime.max;

    return zoneName.length != 0 && utcOffset //&& ruleName.length != 0
        ? ResultIf!ZoneInfo.ok(ZoneInfo(zoneName, utcOffset, ruleName, format, untilDateTime))
        : ResultIf!ZoneInfo.error(1);
}

string trimRight(string line) @nogc pure
{
    size_t i = line.length;
    for (; i; i--)
    {
        if (!isWhite(line[i - 1]))
            break;
    }

    return i == line.length
        ? line
        : (i == 0 ? null : line[0..i]);
}

unittest // normalizeWhite
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.normalizeWhite");

    assert(normalizeWhite(null) is null);
    assert(normalizeWhite("  \t \n ") == " ");
    assert(normalizeWhite("abc  \t \n ") == "abc ");
    assert(normalizeWhite("  abc  \t \n ") == " abc ");
}

unittest // removeComment
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.removeComment");

    assert(removeComment(null) is null);
    assert(removeComment("#") is null);
    assert(removeComment("#abc") is null);
    assert(removeComment("abc #") == "abc ", '\'' ~ removeComment("abc #") ~ '\'');
    assert(removeComment("abc # #") == "abc ");
}

unittest // sameFirst
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.sameFirst");

    assert(sameFirst("", ""));
    assert(sameFirst("abc xyz", "ab"));
    assert(sameFirst("abc xyz", "abc xyz"));
    assert(!sameFirst("abc xyz", ""));
    assert(!sameFirst("abc xyz", "xyz"));
    assert(!sameFirst("abc xyz", "abc xyz "));
}

unittest // sameLast
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.sameLast");

    assert(sameLast("", ""));
    assert(sameLast("abc xyz", "yz"));
    assert(sameLast("abc xyz", "abc xyz"));
    assert(!sameLast("abc xyz", ""));
    assert(!sameLast("abc xyz", "abc"));
    assert(!sameLast("abc xyz", " abc xyz"));
}

unittest // toDay
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toDay");
//todo
}

unittest // toDayOfMonth
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toDayOfMonth");

    ResultIf!int r;
    r = toDayOfMonth("1");
    assert(r);
    assert(r.value == 1);

    r = toDayOfMonth("31");
    assert(r);
    assert(r.value == 31);

    assert(!toDayOfMonth(""));
    assert(!toDayOfMonth(" "));
    assert(!toDayOfMonth("0"));
    assert(!toDayOfMonth("-1"));
    assert(!toDayOfMonth("32"));
}

unittest // toLink
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toLink");

    ResultIf!LinkInfo r;
    r = toLink([linkId, "name", "alias"]);
    assert(r);
    assert(r.value.realName == "name");
    assert(r.value.aliasName == "alias");

    assert(!toLink([]));
    assert(!toLink([linkId]));
    assert(!toLink([linkId, ""]));
    assert(!toLink([linkId, "name", ""]));
    assert(!toLink([linkId, "", "alias"]));
}

unittest // toRule
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toRule");
    //todo
}

unittest // toTime
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toTime");
    //todo
}

unittest // toYearBegin
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toYearBegin");

    ResultIf!int r;
    r = toYearBegin("min");
    assert(r);
    assert(r.value == DateTime.minYear);

    r = toYearBegin("1");
    assert(r);
    assert(r.value == 1);

    r = toYearBegin("9999");
    assert(r);
    assert(r.value == 9999);

    assert(!toYearBegin(""));
    assert(!toYearBegin("0"));
    assert(!toYearBegin("-1"));
    assert(!toYearBegin("1234567"));
}

unittest // toYearEnd
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toYearEnd");

    ResultIf!int r, onlyError, onlyOK;
    onlyError = ResultIf!int.error(1);
    onlyOK = ResultIf!int.ok(2000);

    r = toYearEnd("max", onlyOK);
    assert(r);
    assert(r.value == DateTime.maxYear);

    r = toYearEnd("1", onlyOK);
    assert(r);
    assert(r.value == 1);

    r = toYearEnd("9999", onlyOK);
    assert(r);
    assert(r.value == 9999);

    r = toYearEnd("only", onlyOK);
    assert(r);
    assert(r.value == onlyOK.value);

    assert(!toYearEnd("only", onlyError));
    assert(!toYearEnd("", onlyOK));
    assert(!toYearEnd("0", onlyOK));
    assert(!toYearEnd("-1", onlyOK));
    assert(!toYearEnd("1234567", onlyOK));
}

unittest // toZone
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.toZone");
    //todo
}

unittest // trimRight
{
    import pham.utl.test;
    traceUnitTest!("pham.dtm")("unittest pham.dtm.time_zone_default_tzdata.trimRight");

    assert(trimRight(null) is null);
    assert(trimRight("  \t \n ") is null);
    assert(trimRight("abc  \t \n ") == "abc");
    assert(trimRight("  abc  \t \n ") == "  abc");
}
