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
import std.array : split;
import std.ascii : isWhite;
import std.conv : to;
import std.string : splitLines;
import std.uni : sicmp;

debug(pham_dtm_dtm_time_zone_default_tzdata) import std.stdio : writeln;
import pham.utl.utl_array : indexOf;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;
import pham.utl.utl_result : ResultIf;
import pham.dtm.dtm_date : DayOfWeek, Date, DateTime;
import pham.dtm.dtm_date_time_parse;
import pham.dtm.dtm_tick : DateTimeZoneKind, ErrorOp, MonthOfYear, toDayOfWeekUS, toMonthUS;
import pham.dtm.dtm_time : Time;
import pham.dtm.dtm_time_zone : AdjustmentRule, TimeZoneInfo, TransitionTime, ZoneOffset;

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

static immutable string lineLink = "Link";
static immutable string lineRule = "Rule";
static immutable string lineZone = "Zone";

static immutable string lastDoW = "last";
static immutable string minDate = "min";
static immutable string maxDate = "max";
static immutable string onlyDate = "only";

enum notUsedInt = -1;

enum NotUsedAs
{
    min,
    max,
}

struct DateInfo
{
nothrow @safe:

    bool opEqual(scope const(DateInfo) rhs) const @nogc pure
    {
        return this.year == rhs.year
            && this.month == rhs.month
            && this.day == rhs.day;
    }

    static typeof(this) notUsedInfo() @nogc pure
    {
        typeof(this) result;
        result.reset();
        return result;
    }

    void reset() @nogc pure
    {
        year = month = day = notUsedInt;
    }

    Date toDate(const(NotUsedAs) kind) const @nogc pure
    {
        const byte actMonth = month == notUsedInt
            ? (kind == NotUsedAs.min ? MonthOfYear.january : MonthOfYear.december)
            : month;
        return year == notUsedInt
            ? (kind == NotUsedAs.min ? Date.min : Date.max)
            : Date(year, actMonth, day == notUsedInt ? (kind == NotUsedAs.min ? 1 : Date.daysInMonth(year, actMonth)) : day);
    }

    int year;
    byte month;
    byte day;
}

struct DayInfo
{
nothrow @safe:

    enum AdvancedDayOfWeek : ubyte
    {
        eq, // equal
        ge, // greater or equal
        le, // less than or equal
        lo, // last of
    }

    bool opEqual(scope const(DayInfo) rhs) const @nogc pure
    {
        return this.dayOfMonth == rhs.dayOfMonth
            && this.dayOfWeek == rhs.dayOfWeek
            && this.advanceDayOfWeek == rhs.advanceDayOfWeek;
    }

    static typeof(this) notUsedInfo() @nogc pure
    {
        typeof(this) result;
        result.reset();
        return result;
    }

    void reset() @nogc pure
    {
        dayOfMonth = dayOfWeek = notUsedInt;
        advanceDayOfWeek = AdvancedDayOfWeek.eq;
    }

    string toString() const pure
    {
        scope (failure) assert(0, "Assume nothrow failed");

        return "{"
            ~ "dayOfMonth:" ~ dayOfMonth.to!string
            ~ ", dayOfWeek:" ~ dayOfWeek.to!string
            ~ ", advanceDayOfWeek:" ~ advanceDayOfWeek.to!string
            ~ "}";
    }

    byte dayOfMonth;
    byte dayOfWeek;
    AdvancedDayOfWeek advanceDayOfWeek;
}

struct LinkInfo
{
nothrow @safe:

    pragma(inline, true)
    bool isValid() const
    {
        return realName.length != 0 && aliasName.length != 0;
    }

    string toString() const pure
    {
        return realName ~ "=" ~ aliasName;
    }

    string aliasName;
    string realName;
}

struct RuleInfo
{
nothrow @safe:

    bool opEqual(scope const(RuleInfo) rhs) const @nogc pure
    {
        return this.letters == rhs.letters
            && this.name == rhs.name
            && this.monthOnDay == rhs.monthOnDay
            && this.monthOnDayTime == rhs.monthOnDayTime
            && this.saveTime == rhs.saveTime
            && this.yearFrom == rhs.yearFrom
            && this.yearTo == rhs.yearTo
            && this.month == rhs.month;
    }

    pragma(inline, true)
    bool hasSaveTime() const @nogc pure
    {
        return saveTime != TimeInfo.notUsedInfo();
    }

    pragma(inline, true)
    bool isValid() const @nogc pure
    {
        return name.length != 0;
    }

    void reset() @nogc pure
    {
        name = letters = null;
        yearFrom = yearTo = month = notUsedInt;
        monthOnDay.reset();
        monthOnDayTime.reset();
        saveTime.reset();
    }

    string letters;
    string name;
    DayInfo monthOnDay;
    TimeInfo monthOnDayTime;
    TimeInfo saveTime;
    int yearFrom;
    int yearTo;
    byte month;
}

struct RuleInfoSet
{
nothrow @safe:

    void add(ref RuleInfo rule)
    in
    {
        assert(name.length == 0 || name == rule.name);
    }
    do
    {
        if (name.length == 0)
            this.name = rule.name;

        this.rules ~= rule;
    }

    pragma(inline, true)
    bool isValid() const
    {
        return name.length != 0 && rules.length != 0;
    }

    void reset()
    {
        name = null;
        rules = null;
    }

    string name;
    RuleInfo[] rules;
}

struct TimeInfo
{
nothrow @safe:

    bool opEqual(scope const(TimeInfo) rhs) const @nogc pure
    {
        return this.hour == rhs.hour
            && this.minute == rhs.minute
            && this.second == rhs.second
            && this.mode == rhs.mode
            && this.addDay == rhs.addDay
            && this.neg == rhs.neg;
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

    static typeof(this) notUsedInfo() @nogc pure
    {
        typeof(this) result;
        result.reset();
        return result;
    }

    void reset() @nogc pure
    {
        hour = minute = second = notUsedInt;
        addDay = 0;
        mode = '\0';
        neg = false;
    }

    Duration toDuration(const(NotUsedAs) kind) const @nogc pure
    {
        const result = toTime(kind).toDuration() + dur!"days"(addDay);
        return neg ? -result : result;
    }

    string toString() const
    {
        scope (failure) assert(0, "Assume nothrow failed");

        return "{"
            ~ "time:" ~ hour.to!string ~ ":" ~ minute.to!string ~ ":" ~ second.to!string
            ~ ", mode:" ~ (mode != '\0' ? mode.to!string : "")
            ~ ", addDay:" ~ addDay.to!string
            ~ ", neg:" ~ neg.to!string
            ~ "}";
    }

    Time toTime(const(NotUsedAs) kind) const @nogc pure
    {
        return hour == notUsedInt
            ? (kind == NotUsedAs.min ? Time.min : Time.max)
            : Time(hour,
                    minute == notUsedInt ? (kind == NotUsedAs.min ? 0 : 59) : minute,
                    second == notUsedInt ? (kind == NotUsedAs.min ? 0 : 59) : second,
                    0, DateTimeZoneKind.unspecified);
    }

    byte addDay;
    byte hour;
    byte minute;
    byte second;
    char mode;
    bool neg;
}

struct ZoneInfo
{
nothrow @safe:

    bool opEqual(scope const(ZoneInfo) rhs) const @nogc pure
    {
        return this.format == rhs.format
            && this.name == rhs.name
            && this.ruleName == rhs.ruleName
            && this.stdOffset == rhs.stdOffset
            && this.untilTime == rhs.untilTime
            && this.untilDate == rhs.untilDate;
    }

    ZoneOffset baseUtcOffset() const @nogc pure
    {
        return ZoneOffset(stdOffset.toDuration(NotUsedAs.max));
    }
    
    pragma(inline, true)
    bool isValid() const
    {
        return stdOffset != TimeInfo.notUsedInfo();
    }

    void reset() @nogc pure
    {
        format = name = ruleName = null;
        stdOffset.reset();
        untilTime.reset();
        untilDate.reset();
    }

    bool supportsDaylightSavingTime() const @nogc pure
    {
        return sameLast(format, "DT") || (ruleName.length != 0 && sameLast(format, "%sT"));
    }

    DateTime untilDateTime() const @nogc pure
    {
        return DateTime(untilDate.toDate(NotUsedAs.max), untilTime.toTime(NotUsedAs.max)).addDaysClamp(untilTime.addDay);
    }

    string format;
    string name;
    string ruleName;
    TimeInfo stdOffset;
    TimeInfo untilTime;
    DateInfo untilDate;
}

struct ZoneInfoSet
{
nothrow @safe:

    void add(ref ZoneInfo zone)
    in
    {
        assert(name.length == 0 || name == zone.name);
    }
    do
    {
        if (name.length == 0)
            this.name = zone.name;

        this.zones ~= zone;
    }

    pragma(inline, true)
    bool isValid() const
    {
        return name.length != 0 && zones.length != 0;
    }

    void reset()
    {
        name = null;
        zones = null;
    }

    string name;
    ZoneInfo[] zones;
}

struct TZDatabase
{
nothrow @safe:

    void addLink(ref LinkInfo link)
    {
        this.links[link.aliasName] = link;
    }

    void addRules(ref RuleInfoSet rules)
    {
        this.rules[rules.name] = rules;
    }

    void addZones(ref ZoneInfoSet zones)
    {
        this.zones[zones.name] = zones;
    }

    bool hasRules(string name, ref RuleInfoSet rules)
    {
        if (name.length == 0)
            return false;

        auto e = name in this.rules;
        if (e)
        {
            rules = *e;
            return true;
        }
        else
            return false;
    }

    LinkInfo[string] links;
    RuleInfoSet[string] rules;
    ZoneInfoSet[string] zones;
}

struct TZLine
{
nothrow @safe:

    this(string[] elements)
    {
        const minLength = elements.length <= this.elements.length
            ? cast(uint)elements.length
            : cast(uint)this.elements.length;
        this.length = minLength;
        this.elements[0..minLength] = elements[0..minLength];
    }

    void addElement(string element)
    {
        if (length < elements.length)
            elements[length++] = element;
    }

    void chopFirst(const(uint) count)
    {
        if (count == 0)
            return;
        else if (count >= length)
        {
            length = 0;
            return;
        }

        length -= count;
        foreach (i; 0..length)
        {
            elements[i] = elements[count + i];
        }
    }

    pragma(inline, true)
    string element(const(uint) index, string missing = null) const pure
    {
        return index < length ? elements[index] : missing;
    }

    string parse(string line)
    {
        //debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(", line, ")");

        length = 0;
        line = line.removeComment().normalizeWhite();
        size_t end = line.length;
        if (end == 0)
            return null;

        enum delimiter = ' ';
        size_t b, i;
        for (; i < end; i++)
        {
            const c = line[i];

            //debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln("\t", "i=", i, ", line[i]=", c, "/", cast(int)c);

            if (c == delimiter)
            {
                //debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln("\t", "b=", b, ", i=", i, ", line[b..i]=", line[b..i]);

                addElement(line[b..i]);
                b = i + 1;
            }
        }

        if (line[end - 1] == delimiter)
            addElement("");
        else if (b < i)
        {
            //debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln("\t", "b=", b, ", i=", i, ", line[b..i]=", line[b..i]);

            addElement(line[b..i]);
        }

        return id;
    }

    string toString() const
    {
        auto result = Appender!string(length * 10);
        result.put('[');
        foreach (i; 0..length)
        {
            if (i)
                result.put(',');
            result.put(elements[i]);
        }
        result.put(']');
        return result.data;
    }

    pragma(inline, true)
    @property string id() const pure
    {
        return length ? elements[0] : null;
    }

    string[15] elements;
    uint length;
}

pragma(inline, true)
bool isCommentChar(char c) @nogc pure
{
    return c == '#';
}

pragma(inline, true)
bool isCommentLine(string line) @nogc pure
{
    return line.length == 0 || isCommentChar(line[0]);
}

string normalizeWhite(string line) pure
{
    const lineLength = line.length;
    if (lineLength == 0)
        return line;

    enum useResult = -1;
    auto result = Appender!string(lineLength);
    ptrdiff_t leadingChars;
    bool wasSpace;

    void addChar(char c) nothrow @safe
    {
        if (leadingChars > 0)
            result.put(line[0..leadingChars]);
        leadingChars = useResult; // No longer use
        result.put(c);
    }

    foreach (i; 0..lineLength)
    {
        const c = line[i];

        if (isCommentChar(c))
            break;
        else if (c == ' ')
        {
            if (wasSpace)
                continue;

            addChar(' ');
            wasSpace = true;
        }
        else
        {
            wasSpace = false;
            if (c == '\t')
            {
                addChar(' ');
                wasSpace = true; // "\t " -> consider trimLeft
            }
            else if (leadingChars >= 0)
                leadingChars++;
            else
                addChar(c);
        }
    }

    return leadingChars == useResult ? result.data : line;
}

string nullIf(string s) @nogc pure
{
    return s != "-" ? s : null;
}

TZDatabase parseTZData(string tzData)
{
    TZDatabase result;

    string lastLineId;
    RuleInfo lastRule;
    RuleInfoSet lastRules;
    ZoneInfo lastZone;
    ZoneInfoSet lastZones;
    TZLine line;
    const tzDataLines = splitLines(tzData);
    foreach (tzDataLine; tzDataLines)
    {
        if (isCommentLine(tzDataLine))
            continue;

        const lineId = line.parse(tzDataLine);

        if (lineId == lineRule)
        {
            // New rule set?
            if (lastLineId == lineZone)
            {
                if (lastZones.isValid())
                    result.addZones(lastZones);

                lastRule.reset();
                lastRules.reset();
                lastZone.reset();
                lastZones.reset();
            }

            auto ruleInfo = toRuleInfo(line, lastRule, tzDataLine);
            if (ruleInfo.isValid())
            {
                lastRules.add(ruleInfo);
                lastRule = ruleInfo;
            }

            lastLineId = lineRule;
        }
        else if ((lineId == lineZone) || (lineId.length == 0 && lastLineId == lineZone && lastZone.isValid()))
        {
            // New zone set?
            if (lastLineId == lineRule)
            {
                if (lastRules.isValid())
                    result.addRules(lastRules);

                lastRule.reset();
                lastRules.reset();
                lastZone.reset();
                lastZones.reset();
            }

            auto zoneInfo = toZoneInfo(line, lastZone, tzDataLine);
            if (zoneInfo.isValid())
            {
                lastZones.add(zoneInfo);
                lastZone = zoneInfo;
            }

            lastLineId = lineZone;
        }
        else if (lineId == lineLink)
        {
            auto linkInfo = toLinkInfo(line, tzDataLine);
            if (linkInfo.isValid())
                result.addLink(linkInfo);

            lastLineId = lineLink;
        }
        //else
        //    lastLineId = lineId;
    }

    if (lastRules.isValid())
        result.addRules(lastRules);

    if (lastZones.isValid())
        result.addZones(lastZones);

    return result;
}

TZLine parseTZLine(string tzLine)
{
    TZLine result;
    result.parse(tzLine);
    return result;
}

string removeComment(string line) pure
{
    foreach (i; 0..line.length)
    {
        if (line[i] == '#')
            return i == 0 ? null : line[0..i].trimRight();
    }
    return line;
}

ResultIf!DateInfo toDateInfo(string y, string m, string d) pure
{
    ResultIf!DateInfo invalidDateInfo() nothrow @safe
    {
        return ResultIf!DateInfo.error(1, "Invalid tzdate date: " ~ y ~ " " ~ m ~ " " ~ d);
    }

    if (y.length == 0 && m.length == 0 && d.length == 0)
        return ResultIf!DateInfo.ok(DateInfo.notUsedInfo());

    auto year = y.length ? toYear(y) : ResultIf!int.ok(notUsedInt);
    auto month = m.length ? toMonth(m) : ResultIf!byte.ok(notUsedInt);
    auto day = d.length ? toDayOfMonth(d) : ResultIf!byte.ok(notUsedInt);
    return year && month && day
        ? ResultIf!DateInfo.ok(DateInfo(year:year, month:month, day:day))
        : invalidDateInfo();
}

ResultIf!DayInfo toDayInfo(string v) pure
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    ResultIf!DayInfo invalidDayInfo() nothrow @safe
    {
        return ResultIf!DayInfo.error(1, "Invalid tzdate day: " ~ v);
    }

    ResultIf!byte convDayOfWeek(ResultIf!DayOfWeek v) nothrow pure
    {
        return ResultIf!byte(cast(byte)v.value, v.status);
    }

    ResultIf!byte dayOfMonth = ResultIf!byte.ok(1);
    ResultIf!byte dayOfWeek = ResultIf!byte.ok(notUsedInt);
    DayInfo.AdvancedDayOfWeek advanceDayOfWeek = DayInfo.AdvancedDayOfWeek.eq;

    if (sameFirst(v, lastDoW))
    {
        advanceDayOfWeek = DayInfo.AdvancedDayOfWeek.lo;
        dayOfMonth = ResultIf!byte.ok(notUsedInt);
        dayOfWeek = convDayOfWeek(toDayOfWeek(v[lastDoW.length..$]));

        return dayOfMonth && dayOfWeek
            ? ResultIf!DayInfo.ok(DayInfo(dayOfMonth:dayOfMonth, dayOfWeek:dayOfWeek, advanceDayOfWeek:advanceDayOfWeek))
            : invalidDayInfo();
    }

    auto i = indexOf(v, ">=");
    if (i >= 0)
    {
        advanceDayOfWeek = DayInfo.AdvancedDayOfWeek.ge;
        dayOfMonth = toDayOfMonth(v[i + 2..$]);
        dayOfWeek = convDayOfWeek(toDayOfWeek(v[0..i]));
    }
    else
    {
        i = indexOf(v, "<=");
        if (i >= 0)
        {
            advanceDayOfWeek = DayInfo.AdvancedDayOfWeek.le;
            dayOfMonth = toDayOfMonth(v[i + 2..$]);
            dayOfWeek = convDayOfWeek(toDayOfWeek(v[0..i]));
        }
        else
        {
            dayOfMonth = toDayOfMonth(v);
        }
    }

    return dayOfMonth && dayOfWeek
        ? ResultIf!DayInfo.ok(DayInfo(dayOfMonth:dayOfMonth, dayOfWeek:dayOfWeek, advanceDayOfWeek:advanceDayOfWeek))
        : invalidDayInfo();
}

ResultIf!byte toDayOfMonth(string v) pure
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    byte n;
    if (parseIntegral(v, n) == NumericParsedKind.ok)
    {
        if (n >= 1 && n <= 31)
            return ResultIf!byte.ok(n);
    }

    return ResultIf!byte.error(1, "Invalid day of month: " ~ v);
}

ResultIf!DayOfWeek toDayOfWeek(string v) pure
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    return toDayOfWeekUS(v);
}

ResultIf!LinkInfo toLinkInfo(ref TZLine line, string originalLine) pure
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(originalLine=", originalLine, ", elements=", line.toString, ")");

    return line.length < 3 || line.element(1).length == 0 || line.element(2).length == 0
        ? ResultIf!LinkInfo.error(1, "Invalid datetime link")
        : ResultIf!LinkInfo.ok(LinkInfo(realName:line.element(1), aliasName:line.element(2)));
}

ResultIf!byte toMonth(string v) pure
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    return toMonthUS(v);
}

ResultIf!RuleInfo toRuleInfo(ref TZLine line, ref RuleInfo lastInfo, string originalLine)
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(originalLine=", originalLine, ", elements=", line.toString, ")");

    ResultIf!RuleInfo invalidRuleInfo() nothrow @safe
    {
        return ResultIf!RuleInfo.error(1, "Invalid tzdata rule: " ~ originalLine);
    }

    if (line.length < 9)
        return invalidRuleInfo();

    // skip Rule
    const name = line.element(1);
    const yearFrom = toYear(line.element(2));
    const yearTo = toYearEnd(line.element(3), yearFrom);
    // skip "-"
    const month = toMonth(line.element(5));
    const monthOnDay = toDayInfo(line.element(6));
    const monthOnDayTime = toTimeInfo(line.element(7));
    const saveTime = toTimeInfo(line.element(8));
    const letters = nullIf(line.element(9));

    return name.length != 0 && yearFrom && yearTo && month && monthOnDay && monthOnDayTime && saveTime
        ? ResultIf!RuleInfo.ok(RuleInfo(name:name, yearFrom:yearFrom, yearTo:yearTo,
            month:month, monthOnDay:monthOnDay, monthOnDayTime:monthOnDayTime, saveTime:saveTime, letters:letters))
        : invalidRuleInfo();
}

ResultIf!TimeInfo toTimeInfo(string v)
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    ResultIf!TimeInfo invalidTimeInfo() nothrow @safe
    {
        return ResultIf!TimeInfo.error(1, "Invalid tzdata time: " ~ v);
    }

    static DateTimePattern pattern(string patternText) nothrow pure @safe
    {
        auto result = DateTimePattern.usShortDateTime;
        result.timeSeparator = ':';
        result.patternText = patternText;
        return result;
    }

    if (v == "0")
        return ResultIf!TimeInfo.ok(TimeInfo(addDay:0, hour:0, minute:0, second:0, mode:'\0', neg:false));

    TimeInfo result;
    result.reset();

    result.neg = v.length != 0 && v[0] == '-';
    if (result.neg)
        v = v[1..$];

    result.mode = v.length != 0 ? v[$ - 1] : '\0';
    if (TimeInfo.isValidMode(result.mode))
        v = v[0..$ - 1];
    else
        result.mode = '\0';

    if (v.length == 0)
        return invalidTimeInfo();

    if (v == "24:00" || v == "24")
    {
        result.hour = 0;
        result.minute = 0;
        result.second = 0;
        result.addDay = 1;
    }
    // As of TZDB 2018f, Japan's fallback transitions occur at 25:00. We can't
    // represent this entirely accurately, but this is as close as we can approximate it.
    else if (v == "25:00" || v == "25")
    {
        result.hour = 1;
        result.minute = 0;
        result.second = 0;
        result.addDay = 1;
    }
    else
    {
        Time parsedTime;
        scope const patterns = [pattern("hh:nn:ss.zzz"), pattern("hh:nn"), pattern("hh")];
        if (tryParse!Time(v, patterns, parsedTime) != DateTimeParser.noError)
            return invalidTimeInfo();
        int hour, minute, second, millisecond;
        parsedTime.getTime(hour, minute, second, millisecond);
        result.hour = cast(byte)hour;
        result.minute = cast(byte)minute;
        result.second = cast(byte)second;
    }

    return ResultIf!TimeInfo.ok(result);
}

ResultIf!int toYear(string v) pure
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    if (sicmp(v, minDate) == 0)
        return ResultIf!int.ok(DateTime.minYear);
    else if (sicmp(v, maxDate) == 0)
        return ResultIf!int.ok(DateTime.maxYear);

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
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(v=", v, ")");

    if (sicmp(v, onlyDate) == 0)
        return onlyYear;
    else
        return toYear(v);
}

ResultIf!ZoneInfo toZoneInfo(ref TZLine line, ref ZoneInfo lastInfo, string originalLine)
{
    debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln(__FUNCTION__, "(originalLine=", originalLine, ", elements=", line.toString, ")");

    ResultIf!ZoneInfo invalidZoneInfo() nothrow @safe
    {
        return ResultIf!ZoneInfo.error(1, "Invalid tzdata zone: " ~ originalLine);
    }

    if (sameFirst(originalLine, "\t\t\t"))
    {
        line.chopFirst(1);
        debug(pham_dtm_dtm_time_zone_default_tzdata) debug writeln("\t", "elements=", line.toString);
    }

    if (line.length < 5)
        return invalidZoneInfo();

    int offsetIndex = 0;
    auto name = line.element(1).length ? line.element(1) : lastInfo.name;
    auto stdOffset = toTimeInfo(line.element(2));
    if (!stdOffset)
    {
        auto tryOffset = toTimeInfo(line.element(3));
        if (tryOffset)
        {
            stdOffset = tryOffset;
            offsetIndex = 1;
        }
    }
    auto ruleName = nullIf(line.element(3+offsetIndex));
    auto format = line.element(4+offsetIndex);
    auto untilDate = toDateInfo(line.element(5+offsetIndex), line.element(6+offsetIndex), line.element(7+offsetIndex));
    auto untilTime = line.length >= 9+offsetIndex ? toTimeInfo(line.element(8+offsetIndex)): ResultIf!TimeInfo.ok(TimeInfo.notUsedInfo());

    return stdOffset && untilDate && untilTime
        ? ResultIf!ZoneInfo.ok(ZoneInfo(name:name, stdOffset:stdOffset, ruleName:ruleName,
            format:format, untilDate:untilDate, untilTime:untilTime))
        : invalidZoneInfo();
}

TimeZoneInfo[] toTimeZoneInfo(ref TZDatabase tzDatabase)
{
    scope (failure) assert(0, "Assume nothrow failed");

    TimeZoneInfo[] result;
    result.reserve(200);

    foreach (name, ref zoneInfoSet; tzDatabase.zones)
    {
        auto firstZone = zoneInfoSet.zones[0];

        auto id = firstZone.name;
        auto displayName = firstZone.name;
        auto standardName = firstZone.name;
        auto daylightName = firstZone.name;
        auto baseUtcOffset = firstZone.baseUtcOffset();
        auto supportsDaylightSavingTime = firstZone.supportsDaylightSavingTime();
        auto untilDateTime = firstZone.untilDateTime();

/*
TimeZoneInfo
    this(string id, string displayName, string standardName, string daylightName,
        ZoneOffset baseUtcOffset, bool supportsDaylightSavingTime) @nogc nothrow pure
    this(string id, string displayName, string standardName, string daylightName,
        ZoneOffset baseUtcOffset, bool supportsDaylightSavingTime,
        AdjustmentRule[] adjustmentRules) @nogc nothrow pure

AdjustmentRule
    this(in DateTime dateBegin,
        in DateTime dateEnd,
        in ZoneOffset baseUtcOffsetDelta,
        in ZoneOffset daylightDelta,
        in ZoneOffset standardDelta,
        in TransitionTime daylightTransitionBegin,
        in TransitionTime daylightTransitionEnd,
        bool noDaylightTransitions) @nogc nothrow pure
        
TransitionTime        
    this(in DateTime timeOfDay, int month, int week, int day, DayOfWeek dayOfWeek, bool isFixedDateRule) @nogc nothrow pure
        
*/        

        RuleInfoSet rules;
        if (tzDatabase.hasRules(firstZone.ruleName, rules))
        {
        }
        else
        {
        }

        AdjustmentRule[] adjRules;
        DateTime adjBegin = DateTime.min.asKind(DateTimeZoneKind.unspecified);
        //todo DateTime adjEnd = firstZone.untilDateTime;
        Duration adjDaylightDelta, adjStandardDelta, adjBaseUtcOffsetDelta;
        TransitionTime adjDaylightTransitionBegin, adjDaylightTransitionEnd;
        bool adjNoDaylightTransitions;

        foreach (ref zoneInfo; zoneInfoSet.zones[1..$])
        {
            supportsDaylightSavingTime = zoneInfo.supportsDaylightSavingTime();
               
        }
        //todo result ~= TimeZoneInfo(id, displayName, standardName, daylightName, baseUtcOffset,
        //    supportsDaylightSavingTime, adjRules);
    }

    return result;
}

string trimRight(string line) pure
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
    assert(normalizeWhite("   ") == " ");
    assert(normalizeWhite("  \t  ") == "  ");
    assert(normalizeWhite("abc  \t  ") == "abc  ");
    assert(normalizeWhite("   abc   \t   ") == " abc  ");
}

unittest // removeComment
{
    assert(removeComment(null) is null);
    assert(removeComment("#") is null);
    assert(removeComment("#abc") is null);
    assert(removeComment("abc #") == "abc", '"' ~ removeComment("abc #") ~ '"');
    assert(removeComment("  abc # #") == "  abc");
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

unittest // toDayInfo
{
    auto v = toDayInfo("1");
    assert(v.dayOfMonth == 1);
    assert(v.dayOfWeek == notUsedInt);
    assert(v.advanceDayOfWeek == DayInfo.AdvancedDayOfWeek.eq);

    v = toDayInfo("16");
    assert(v.dayOfMonth == 16);
    assert(v.dayOfWeek == notUsedInt);
    assert(v.advanceDayOfWeek == DayInfo.AdvancedDayOfWeek.eq);

    v = toDayInfo("31");
    assert(v.dayOfMonth == 31);
    assert(v.dayOfWeek == notUsedInt);
    assert(v.advanceDayOfWeek == DayInfo.AdvancedDayOfWeek.eq);

    v = toDayInfo("Sun>=15");
    assert(v.dayOfMonth == 15);
    assert(v.dayOfWeek == DayOfWeek.sunday);
    assert(v.advanceDayOfWeek == DayInfo.AdvancedDayOfWeek.ge);

    v = toDayInfo("lastFri");
    assert(v.dayOfMonth == notUsedInt);
    assert(v.dayOfWeek == DayOfWeek.friday);
    assert(v.advanceDayOfWeek == DayInfo.AdvancedDayOfWeek.lo);

    v = toDayInfo("Fri>=1");
    assert(v.dayOfMonth == 1);
    assert(v.dayOfWeek == DayOfWeek.friday);
    assert(v.advanceDayOfWeek == DayInfo.AdvancedDayOfWeek.ge);
}

unittest // toDayOfMonth
{
    ResultIf!byte r;
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

unittest // toLinkInfo
{
    ResultIf!LinkInfo r;

    auto line = TZLine([lineLink, "name", "alias"]);
    r = toLinkInfo(line, "Link name alias");
    assert(r);
    assert(r.value.realName == "name");
    assert(r.value.aliasName == "alias");

    line = TZLine([]);
    assert(!toLinkInfo(line, ""));

    line = TZLine([lineLink]);
    assert(!toLinkInfo(line, "Link"));

    line = TZLine([lineLink, ""]);
    assert(!toLinkInfo(line, "Link "));

    line = TZLine([lineLink, "name", ""]);
    assert(!toLinkInfo(line, "Link name "));

    line = TZLine([lineLink, "", "alias"]);
    assert(!toLinkInfo(line, "Link  alias"));
}

unittest // toRuleInfo
{
    RuleInfo lastInfo;
    ResultIf!RuleInfo toRuleInfo(string tzLine) nothrow @safe
    {
        auto line = parseTZLine(tzLine);
        return .toRuleInfo(line, lastInfo, tzLine);
    }

    auto v = toRuleInfo("Rule	Syria	2008	only	-	Apr	Fri>=1	0:00	1:00	S");
    assert(v);
    assert(v.name == "Syria");
    assert(v.yearFrom == 2008);
    assert(v.yearTo == 2008);
    assert(v.month == MonthOfYear.april);
    assert(v.monthOnDay == DayInfo(dayOfMonth:1, dayOfWeek:DayOfWeek.friday, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.ge), v.monthOnDay.toString ~ " vs " ~ DayInfo(dayOfMonth:1, dayOfWeek:DayOfWeek.friday, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.eq).toString);
    assert(v.monthOnDayTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.monthOnDayTime.toString);
    assert(v.saveTime == TimeInfo(hour:1, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.saveTime.toString);
    assert(v.letters == "S");

    v = toRuleInfo("Rule	Syria	2008	only	-	Nov	1	0:00	0	-");
    assert(v);
    assert(v.name == "Syria");
    assert(v.yearFrom == 2008);
    assert(v.yearTo == 2008);
    assert(v.month == MonthOfYear.november);
    assert(v.monthOnDay == DayInfo(dayOfMonth:1, dayOfWeek:notUsedInt, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.eq), v.monthOnDay.toString);
    assert(v.monthOnDayTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.monthOnDayTime.toString);
    assert(v.saveTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.saveTime.toString);
    assert(v.letters == "");

    v = toRuleInfo("Rule	Syria	2012	2022	-	Mar	lastFri	0:00	1:00	S");
    assert(v);
    assert(v.name == "Syria");
    assert(v.yearFrom == 2012);
    assert(v.yearTo == 2022);
    assert(v.month == MonthOfYear.march);
    assert(v.monthOnDay == DayInfo(dayOfMonth:notUsedInt, dayOfWeek:DayOfWeek.friday, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.lo), v.monthOnDay.toString);
    assert(v.monthOnDayTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.monthOnDayTime.toString);
    assert(v.saveTime == TimeInfo(hour:1, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.saveTime.toString);
    assert(v.letters == "S");

    v = toRuleInfo("Rule	Syria	2009	2022	-	Oct	lastFri	0:00	0	-");
    assert(v);
    assert(v.name == "Syria");
    assert(v.yearFrom == 2009);
    assert(v.yearTo == 2022);
    assert(v.month == MonthOfYear.october);
    assert(v.monthOnDay == DayInfo(dayOfMonth:notUsedInt, dayOfWeek:DayOfWeek.friday, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.lo), v.monthOnDay.toString);
    assert(v.monthOnDayTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.monthOnDayTime.toString);
    assert(v.saveTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.saveTime.toString);
    assert(v.letters == "");

    v = toRuleInfo("Rule	US	2007	max	-	Mar	Sun>=8	2:00	1:00	D");
    assert(v);
    assert(v.name == "US");
    assert(v.yearFrom == 2007);
    assert(v.yearTo == DateTime.maxYear);
    assert(v.month == MonthOfYear.march);
    assert(v.monthOnDay == DayInfo(dayOfMonth:8, dayOfWeek:DayOfWeek.sunday, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.ge), v.monthOnDay.toString);
    assert(v.monthOnDayTime == TimeInfo(hour:2, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.monthOnDayTime.toString);
    assert(v.saveTime == TimeInfo(hour:1, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.saveTime.toString);
    assert(v.letters == "D");

    v = toRuleInfo("Rule	US	2007	max	-	Nov	Sun>=1	2:00	0	S");
    assert(v);
    assert(v.name == "US");
    assert(v.yearFrom == 2007);
    assert(v.yearTo == DateTime.maxYear);
    assert(v.month == MonthOfYear.november);
    assert(v.monthOnDay == DayInfo(dayOfMonth:1, dayOfWeek:DayOfWeek.sunday, advanceDayOfWeek:DayInfo.AdvancedDayOfWeek.ge), v.monthOnDay.toString);
    assert(v.monthOnDayTime == TimeInfo(hour:2, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.monthOnDayTime.toString);
    assert(v.saveTime == TimeInfo(hour:0, minute:0, second:0, mode:'\0', addDay:0, neg:false), v.saveTime.toString);
    assert(v.letters == "S");
}

unittest // toTimeInfo
{
    auto v = toTimeInfo("0");
    assert(v.hour == 0);
    assert(v.minute == 0);
    assert(v.second == 0);
    assert(v.mode == '\0');
    assert(v.addDay == 0);
    assert(!v.neg);

    v = toTimeInfo("9");
    assert(v.hour == 9);
    assert(v.minute == 0);
    assert(v.second == 0);
    assert(v.mode == '\0');
    assert(v.addDay == 0);
    assert(!v.neg);

    v = toTimeInfo("13:19");
    assert(v.hour == 13);
    assert(v.minute == 19);
    assert(v.second == 0);
    assert(v.mode == '\0');
    assert(v.addDay == 0);
    assert(!v.neg);

    v = toTimeInfo("24:00");
    assert(v.hour == 0);
    assert(v.minute == 0);
    assert(v.second == 0);
    assert(v.mode == '\0');
    assert(v.addDay == 1);
    assert(!v.neg);

    v = toTimeInfo("24:00u");
    assert(v.hour == 0);
    assert(v.minute == 0);
    assert(v.second == 0);
    assert(v.mode == 'u');
    assert(v.addDay == 1);
    assert(!v.neg);

    v = toTimeInfo("25:00");
    assert(v.hour == 1);
    assert(v.minute == 0);
    assert(v.second == 0);
    assert(v.mode == '\0');
    assert(v.addDay == 1);
    assert(!v.neg);
}

unittest // toYear
{
    ResultIf!int r;
    r = toYear("min");
    assert(r);
    assert(r.value == DateTime.minYear);

    r = toYear("max");
    assert(r);
    assert(r.value == DateTime.maxYear);

    r = toYear("1");
    assert(r);
    assert(r.value == 1);

    r = toYear("9999");
    assert(r);
    assert(r.value == 9999);

    assert(!toYear(""));
    assert(!toYear("0"));
    assert(!toYear("-1"));
    assert(!toYear("1234567"));
}

unittest // toYearEnd
{
    ResultIf!int r, onlyError, onlyOK;
    onlyError = ResultIf!int.error(1, null);
    onlyOK = ResultIf!int.ok(2000);

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

unittest // toZoneInfo
{
    ZoneInfo lastInfo;
    ResultIf!ZoneInfo toZoneInfo(string tzLine) nothrow @safe
    {
        auto line = parseTZLine(tzLine);
        return .toZoneInfo(line, lastInfo, tzLine);
    }

    auto v = toZoneInfo("Zone	Asia/Dushanbe	4:35:12 -	LMT	1924 May  2");
    assert(v);
    assert(v.name == "Asia/Dushanbe");
    assert(v.stdOffset == TimeInfo(hour:4, minute:35, second:12, mode:'\0', addDay:0, neg:false));
    assert(v.ruleName == "");
    assert(v.format == "LMT");
    assert(v.untilDate.year == 1924);
    assert(v.untilDate.month == MonthOfYear.may);
    assert(v.untilDate.day == 2);
    assert(v.untilTime == TimeInfo.notUsedInfo());

    v = toZoneInfo("			5:00	-	+05	1930 Jun 21");
    assert(v);
    assert(v.name == "");
    assert(v.stdOffset == TimeInfo(hour:5, minute:0, second:0, mode:'\0', addDay:0, neg:false));
    assert(v.ruleName == "");
    assert(v.format == "+05");
    assert(v.untilDate.year == 1930);
    assert(v.untilDate.month == MonthOfYear.june);
    assert(v.untilDate.day == 21);
    assert(v.untilTime == TimeInfo.notUsedInfo());

    v = toZoneInfo("			6:00 RussiaAsia +06/+07	1991 Mar 31  2:00s");
    assert(v);
    assert(v.name == "");
    assert(v.stdOffset == TimeInfo(hour:6, minute:0, second:0, mode:'\0', addDay:0, neg:false));
    assert(v.ruleName == "RussiaAsia");
    assert(v.format == "+06/+07");
    assert(v.untilDate.year == 1991);
    assert(v.untilDate.month == MonthOfYear.march);
    assert(v.untilDate.day == 31);
    assert(v.untilTime == TimeInfo(hour:2, minute:0, second:0, mode:'s', addDay:0, neg:false));

    v = toZoneInfo("			5:00	1:00	+06	1991 Sep  9  2:00s");
    assert(v);
    assert(v.name == "");
    assert(v.stdOffset == TimeInfo(hour:5, minute:0, second:0, mode:'\0', addDay:0, neg:false));
    assert(v.ruleName == "1:00");
    assert(v.format == "+06");
    assert(v.untilDate.year == 1991);
    assert(v.untilDate.month == MonthOfYear.september);
    assert(v.untilDate.day == 9);
    assert(v.untilTime == TimeInfo(hour:2, minute:0, second:0, mode:'s', addDay:0, neg:false));

    v = toZoneInfo("			5:00	-	+05");
    assert(v);
    assert(v.name == "");
    assert(v.stdOffset == TimeInfo(hour:5, minute:0, second:0, mode:'\0', addDay:0, neg:false));
    assert(v.ruleName == "");
    assert(v.format == "+05");
    assert(v.untilDate == DateInfo.notUsedInfo());
    assert(v.untilTime == TimeInfo.notUsedInfo());

    v = toZoneInfo("Zone	EST		 -5:00	-	EST");
    assert(v);
    assert(v.name == "EST");
    assert(v.stdOffset == TimeInfo(hour:5, minute:0, second:0, mode:'\0', addDay:0, neg:true));
    assert(v.ruleName == "");
    assert(v.format == "EST");
    assert(v.untilDate == DateInfo.notUsedInfo());

    v = toZoneInfo("Zone	PST8PDT		 -8:00	US	P%sT");
    assert(v);
    assert(v.name == "PST8PDT");
    assert(v.stdOffset == TimeInfo(hour:8, minute:0, second:0, mode:'\0', addDay:0, neg:true));
    assert(v.ruleName == "US");
    assert(v.format == "P%sT");
    assert(v.untilDate == DateInfo.notUsedInfo());

    v = toZoneInfo("Zone	EST5EDT		 -5:00	US	E%sT");
    assert(v);
    assert(v.name == "EST5EDT");
    assert(v.stdOffset == TimeInfo(hour:5, minute:0, second:0, mode:'\0', addDay:0, neg:true));
    assert(v.ruleName == "US");
    assert(v.format == "E%sT");
    assert(v.untilDate == DateInfo.notUsedInfo());
}

unittest // trimRight
{
    assert(trimRight(null) is null);
    assert(trimRight("  \t \n ") is null);
    assert(trimRight("abc  \t \n ") == "abc");
    assert(trimRight("  abc  \t \n ") == "  abc");
}

unittest // TZLine
{
    TZLine line;

    assert(line.parse("") == "");
    assert(line.length == 0, line.toString());

    assert(line.parse(" ") == "", line.toString());
    assert(line.length == 2, line.toString());
    assert(line.element(1) == "");

    assert(line.parse("   ") == "", line.toString());
    assert(line.length == 2, line.toString());
    assert(line.element(1) == "");

    assert(line.parse("\t") == "", line.toString());
    assert(line.length == 2, line.toString());
    assert(line.element(1) == "");

    assert(line.parse("\t\t") == "", line.toString());
    assert(line.length == 3, line.toString());
    assert(line.element(1) == "");
    assert(line.element(2) == "");

    assert(line.parse("\t ") == "", line.toString());
    assert(line.length == 2, line.toString());
    assert(line.element(1) == "");

    assert(line.parse("\tb") == "", line.toString());
    assert(line.length == 2, line.toString());
    assert(line.element(1) == "b");

    assert(line.parse("a \t b") == "a", line.toString());
    assert(line.length == 3, line.toString());
    assert(line.element(1) == "");
    assert(line.element(2) == "b");

    assert(line.parse("Rule	Macau	1942	1943	-	Apr	30	23:00	1:00	-") == "Rule", line.toString());
    assert(line.length == 10, line.toString());
    assert(line.element(1) == "Macau");
    assert(line.element(2) == "1942");
    assert(line.element(3) == "1943");
    assert(line.element(4) == "-");
    assert(line.element(5) == "Apr");
    assert(line.element(6) == "30");
    assert(line.element(7) == "23:00");
    assert(line.element(8) == "1:00");
    assert(line.element(9) == "-");

    assert(line.parse("Zone	Asia/Macau	7:34:10	-	LMT	1904 Oct 30") == "Zone", line.toString());
    assert(line.element(1) == "Asia/Macau");
    assert(line.element(2) == "7:34:10", line.element(2));
    assert(line.element(3) == "-");
    assert(line.element(4) == "LMT");
    assert(line.element(5) == "1904");
    assert(line.element(6) == "Oct");
    assert(line.element(7) == "30");

    assert(line.parse("Zone	Asia/Tbilisi	2:59:11 -	LMT	1880") == "Zone", line.toString());
    assert(line.element(1) == "Asia/Tbilisi");
    assert(line.element(2) == "2:59:11", line.element(2));
    assert(line.element(3) == "-");
    assert(line.element(4) == "LMT");
    assert(line.element(5) == "1880");

    assert(line.parse("			9:00	Macau	+09/+10	1945 Sep 30 24:00") == "", line.toString());
    assert(line.element(1) == "");
    assert(line.element(2) == "");
    assert(line.element(3) == "9:00");
    assert(line.element(4) == "Macau");
    assert(line.element(5) == "+09/+10");
    assert(line.element(6) == "1945");
    assert(line.element(7) == "Sep");
    assert(line.element(8) == "30");
    assert(line.element(9) == "24:00");

    assert(line.parse("			7:07:12	-	BMT	1923 Dec 31 16:40u # Batavia") == "", line.toString());
    assert(line.element(1) == "");
    assert(line.element(2) == "");
    assert(line.element(3) == "7:07:12");
    assert(line.element(4) == "-");
    assert(line.element(5) == "BMT");
    assert(line.element(6) == "1923", line.element(6));
    assert(line.element(7) == "Dec", line.element(7));
    assert(line.element(8) == "31", line.element(8));
    assert(line.element(9) == "16:40u", line.element(9));
    assert(line.length == 10);
}
