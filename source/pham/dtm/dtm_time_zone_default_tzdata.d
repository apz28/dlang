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

module pham.dtm.dtm_time_zone_default_tzdata;

import core.time : dur, Duration;
import std.array : Appender, split;
import std.ascii : isWhite;
import std.algorithm.searching : countUntil;
import std.string : splitLines;
import std.uni : sicmp;

import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;
import pham.utl.utl_result : ResultIf;
import pham.dtm.dtm_date : DayOfWeek, Date, DateTime;
import pham.dtm.dtm_date_time_parse;
import pham.dtm.dtm_tick : DateTimeZoneKind, ErrorOp, toDayOfWeekUS, toMonthUS;
import pham.dtm.dtm_time : Time;
import pham.dtm.dtm_time_zone : AdjustmentRule, TimeZoneInfo, TransitionTime;

nothrow @safe:

TimeZoneInfo[] getDefaultTimeZoneInfosByTZData(string tzdataText)
{
    if (tzdataText.length == 0)
        return null;
        
    // Special try construct for grep
    try {
        auto tzDatabase = parseTZData(tzdataText);
        return toTimeZoneInfo(tzDatabase);
    } catch (Exception) return null;
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
    
    pragma(inline, true)
    bool supportsDaylightSavingTime() const @nogc pure
    {
        return daylightDelta.isValid();
    }
}

struct RuleInfoSet
{
    string name;
    RuleInfo firstRule;
    RuleInfo[] rules;
}

struct TimeInfo
{
nothrow @safe:

    // Order is important
    Time time;
    char mode;
    bool addDay;
    bool neg;

    pragma(inline, true)
    bool isValid() const @nogc pure
    {
        return time != Time.zero || mode != '\0' || addDay;        
    }
    
    static bool isValidMode(char c) @nogc pure
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

    Duration toDuration() const @nogc pure
    {
        auto result = time.toDuration();
        if (addDay)
            result += dur!"days"(1);
        return neg ? -result : result;
    }
}

struct ZoneInfo
{
nothrow @safe:

    // Order is important
    string name;
    TimeInfo stdOffset;
    string ruleName;
    TimeInfo ruleDelta;
    string format;
    DateTime untilDateTime;
    
    bool supportsDaylightSavingTime() const @nogc pure
    {
        return sameLast(format, "DT") || (ruleName.length != 0 && sameLast(format, "%sT"));
    }
}

struct ZoneInfoSet
{
    string name;
    ZoneInfo firstZone;
    ZoneInfo[] zones;
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
            (*p).rules ~= rule;
        else
            rules[rule.name] = RuleInfoSet(rule.name, rule, null);
    }

    void addZone(ZoneInfo zone)
    {
        auto p = zone.name in zones;
        if (p !is null)
            (*p).zones ~= zone;
        else
            zones[zone.name] = ZoneInfoSet(zone.name, zone, null);
    }

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

string nullIf(string s) @nogc pure
{
    return s != "-" ? s : null;
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
    ResultIf!int convDayOfWeek(ResultIf!DayOfWeek v) nothrow pure
    {
        return ResultIf!int(v.value, v.status);
    }
    
    // Special try construct for grep
    try {
        ResultIf!int dayOfMonth = ResultIf!int.ok(1);
        ResultIf!int dayOfWeek = ResultIf!int.ok(notUsedInt);
        bool advanceDayOfWeek = false;

        if (sameFirst(v, lastDoW))
        {
            dayOfMonth = ResultIf!int.ok(notUsedInt);
            dayOfWeek = convDayOfWeek(toDayOfWeekUS(v[lastDoW.length..$]));

            return dayOfMonth && dayOfWeek
                ? ResultIf!DayInfo.ok(DayInfo(dayOfMonth, dayOfWeek, advanceDayOfWeek))
                : ResultIf!DayInfo.error(1, "Invalid day: " ~ v);
        }

        auto i = countUntil(v, ">=");
        if (i >= 0)
        {
            dayOfMonth = toDayOfMonth(v[i + 2..$]);
            dayOfWeek = convDayOfWeek(toDayOfWeekUS(v[0..i]));
            advanceDayOfWeek = true;
        }
        else
        {
            i = countUntil(v, "<=");
            if (i >= 0)
            {
                dayOfMonth = toDayOfMonth(v[i + 2..$]);
                dayOfWeek = convDayOfWeek(toDayOfWeekUS(v[0..i]));
            }
            else
            {
                dayOfMonth = toDayOfMonth(v);
            }
        }

        return dayOfMonth && dayOfWeek
            ? ResultIf!DayInfo.ok(DayInfo(dayOfMonth, dayOfWeek, advanceDayOfWeek))
            : ResultIf!DayInfo.error(1, "Invalid day: " ~ v);
    } catch (Exception) return ResultIf!DayInfo.error(1, "Invalid day: " ~ v);
}

ResultIf!int toDayOfMonth(string v) pure
{
    int n;
    if (parseIntegral(v, n) == NumericParsedKind.ok)
    {
        if (n >= 1 && n <= 31)
            return ResultIf!int.ok(n);
    }

    return ResultIf!int.error(1, "Invalid day of month: " ~ v);
}

ResultIf!LinkInfo toLink(string[] elems) @nogc pure
{
    return elems.length < 3 || elems[1].length == 0 || elems[2].length == 0
        ? ResultIf!LinkInfo.error(1, "Invalid datetime link")
        : ResultIf!LinkInfo.ok(LinkInfo(elems[1], elems[2]));
}

ResultIf!RuleInfo toRule(string[] elems)
{
    if (elems.length < 9)
        return ResultIf!RuleInfo.error(1, "Invalid datetime rule");

    const name = elems[1];
    const yb = toYearBegin(elems[2]);
    const ye = toYearEnd(elems[3], yb);
    const m = toMonthUS(elems[5]);
    const d = toDay(elems[6]);
    const tod = toTime(elems[7]);
    const tdelta = toTime(elems[8]);
    const letters = elems.length >= 10 ? nullIf(elems[9]) : null;

    return name.length != 0 && yb && ye && m && d && tod && tdelta
        ? ResultIf!RuleInfo.ok(RuleInfo(name, yb, ye, m, d, tod, tdelta, letters))
        : ResultIf!RuleInfo.error(1, "Invalid datetime rule");
}

ResultIf!TimeInfo toTime(string v)
{        
    const neg = v.length != 0 && v[0] == '-';
    if (neg)
        v = v[1..$];

    char mode = v.length != 0 ? v[$ - 1] : '\0';
    if (TimeInfo.isValidMode(mode))
        v = v[0..$ - 1];
    else
        mode = '\0';

    if (v.length == 0)
        return ResultIf!TimeInfo.error(1, "Invalid time: " ~ v);

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
        time = Time(0, 0, 0, 0, DateTimeZoneKind.local);
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
            return ResultIf!TimeInfo.error(1, "Invalid time: " ~ v);
        time = time.asKind(DateTimeZoneKind.unspecified);
    }

    return ResultIf!TimeInfo.ok(TimeInfo(time, mode, addDay, neg));
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

    return ResultIf!int.error(1, "Invalid year: " ~ v);
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

    return ResultIf!int.error(1, "Invalid year: " ~ v);
}

ResultIf!ZoneInfo toZone(string[] elems, string previousZoneName)
{
    if ((previousZoneName.length == 0 && elems.length < 5)
        || (previousZoneName.length != 0 && elems.length < 4))
        return ResultIf!ZoneInfo.error(1, "Invalid datetime zone");

    auto zoneName = previousZoneName.length != 0 ? previousZoneName : elems[1];
    size_t i = previousZoneName.length != 0 ? 1 : 2;
    auto stdOffset = toTime(elems[i++]);
    auto ruleName = nullIf(elems[i++]);
    auto ruleDelta = toTime(ruleName);
    if (ruleDelta)
        ruleName = null;
    auto format = elems[i++];
    DateTime untilDateTime;
    if (i < elems.length)
    {
        const untilYear = toYearEnd(elems[i++], ResultIf!int.error(1, "Invalid datetime zone"));
        const untilMonth = i < elems.length ? toMonthUS(elems[i++]) : ResultIf!int.ok(1);
        const untilDay = i < elems.length ? toDayOfMonth(elems[i++]) : ResultIf!int.ok(1);
        const untilTime = i < elems.length ? toTime(elems[i++]) : ResultIf!TimeInfo.ok(TimeInfo(Time.midnight, '\0', false));

        if (untilYear && untilMonth && untilDay && untilTime)
            untilDateTime = DateTime(Date(untilYear, untilMonth, untilDay), untilTime.time.asKind(DateTimeZoneKind.unspecified));
        else
            return ResultIf!ZoneInfo.error(1, "Invalid datetime zone");
    }
    else
        untilDateTime = DateTime.max.asKind(DateTimeZoneKind.unspecified);

    return zoneName.length != 0 && stdOffset
        ? ResultIf!ZoneInfo.ok(ZoneInfo(zoneName, stdOffset, ruleName, ruleDelta, format, untilDateTime))
        : ResultIf!ZoneInfo.error(1, "Invalid datetime zone");
}

TimeZoneInfo[] toTimeZoneInfo(ref TZDatabase tzDatabase)
{
    scope (failure) assert(0, "Assume nothrow failed");
    
    TimeZoneInfo[] result;
    result.reserve(200);

    foreach (name, ref zoneInfoSet; tzDatabase.zones)
    {
        auto firstZone = zoneInfoSet.firstZone;
        
        auto id = name;
        auto displayName = name;
        auto standardName = name;
        auto daylightName = name;
        auto baseUtcOffset = firstZone.stdOffset.toDuration();
        auto supportsDaylightSavingTime = firstZone.supportsDaylightSavingTime();

        AdjustmentRule[] adjRules;
        DateTime adjBegin = DateTime.min.asKind(DateTimeZoneKind.unspecified);
        DateTime adjEnd = firstZone.untilDateTime;
        Duration adjDaylightDelta, adjStandardDelta, adjBaseUtcOffsetDelta;
        TransitionTime adjDaylightTransitionBegin, adjDaylightTransitionEnd;
        bool adjNoDaylightTransitions;
        
       /*
  string name;
    TimeInfo stdOffset;
    string ruleName;
    TimeInfo ruleDelta;
    string format;
    DateTime untilDateTime;
    */
         
        foreach (ref zoneInfo; zoneInfoSet.zones)
        {
            if (zoneInfo.supportsDaylightSavingTime())
                supportsDaylightSavingTime = true;
        }       
        result ~= TimeZoneInfo(id, displayName, standardName, daylightName, baseUtcOffset,
            supportsDaylightSavingTime, adjRules);
    }

    return result;
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
    assert(normalizeWhite(null) is null);
    assert(normalizeWhite("  \t \n ") == " ");
    assert(normalizeWhite("abc  \t \n ") == "abc ");
    assert(normalizeWhite("  abc  \t \n ") == " abc ");
}

unittest // removeComment
{
    assert(removeComment(null) is null);
    assert(removeComment("#") is null);
    assert(removeComment("#abc") is null);
    assert(removeComment("abc #") == "abc ", '\'' ~ removeComment("abc #") ~ '\'');
    assert(removeComment("abc # #") == "abc ");
}

unittest // sameFirst
{
    assert(sameFirst("", ""));
    assert(sameFirst("abc xyz", "ab"));
    assert(sameFirst("abc xyz", "abc xyz"));
    assert(!sameFirst("abc xyz", ""));
    assert(!sameFirst("abc xyz", "xyz"));
    assert(!sameFirst("abc xyz", "abc xyz "));
}

unittest // sameLast
{
    assert(sameLast("", ""));
    assert(sameLast("abc xyz", "yz"));
    assert(sameLast("abc xyz", "abc xyz"));
    assert(!sameLast("abc xyz", ""));
    assert(!sameLast("abc xyz", "abc"));
    assert(!sameLast("abc xyz", " abc xyz"));
}

unittest // toDay
{
//todo
}

unittest // toDayOfMonth
{
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
    //todo
}

unittest // toTime
{
    //todo
}

unittest // toYearBegin
{
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
    ResultIf!int r, onlyError, onlyOK;
    onlyError = ResultIf!int.error(1, null);
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
    //todo
}

unittest // trimRight
{
    assert(trimRight(null) is null);
    assert(trimRight("  \t \n ") is null);
    assert(trimRight("abc  \t \n ") == "abc");
    assert(trimRight("  abc  \t \n ") == "  abc");
}
