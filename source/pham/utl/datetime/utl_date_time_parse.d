/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.datetime.date_time_parse;

import std.ascii : isPunctuation;
import std.traits : Unqual;
import std.uni : sicmp;

import pham.utl.datetime.tick;
import pham.utl.datetime.date : Date, DateTime;
import pham.utl.datetime.time : Time;
import pham.utl.datetime.time_zone : TimeZoneInfo;

@safe:

enum DateOrder : byte
{
    ymd = 0,  /// Year-Month-Day
    dmy = 1,  /// Day-Month-Year
    mdy = 2,  /// Month-Day-Year
}

enum ParseType : byte
{
    date,
    dateTime,
    time,
}

enum PatternKind : byte
{
    year,
    month,
    day,
    hour,
    minute,
    second,
    fraction,
    amPm,
    timeZone,
    separatorDate,
    separatorTime,
    literal,
}

enum SkipBlank : byte
{
    leading = 1,
    inner = 2,
    trailing = 4,
}

struct PatternMarker
{
nothrow @safe:

    const(char)[] slice(return scope const(char)[] text) @nogc pure
    {
        return text[begin..end];
    }

    size_t begin, end;
}

struct PatternElement
{
nothrow @safe:

    void incLength() @nogc pure
    {
        length++;
        final switch (kind)
        {
            case PatternKind.year:
                if (length > 4)
                    length = 4;
                break;
            case PatternKind.month:
            case PatternKind.day:
                if (length > 3)
                    length = 3;
                break;
            case PatternKind.hour:
            case PatternKind.minute:
            case PatternKind.second:
                if (length > 2)
                    length = 2;
                break;
            case PatternKind.fraction:
                if (length > Tick.ticksMaxPrecision)
                    length = Tick.ticksMaxPrecision;
                break;
            case PatternKind.timeZone:
            case PatternKind.amPm:
            case PatternKind.separatorDate:
            case PatternKind.separatorTime:
            case PatternKind.literal:
                break;
        }
    }

    @property bool hasText() const @nogc pure
    {
        return length == 3 && (kind == PatternKind.month || kind == PatternKind.day);
    }

    PatternMarker marker;
    size_t length;
    PatternKind kind;
}

struct DateTimePattern
{
nothrow @safe:

    ptrdiff_t indexOfAmPm(scope const(char)[] text) const @nogc pure scope
    {
        scope (failure) assert(0);

        if (amPmTexts is null)
            return -1;

        if (sicmp((*amPmTexts)[0], text) == 0)
            return 0;
        else if (sicmp((*amPmTexts)[1], text) == 0)
            return 1;
        else
            return -1;
    }

    ptrdiff_t indexOfMonth(scope const(char)[] text) const @nogc pure scope
    {
        scope (failure) assert(0);

        foreach (i, m; *monthFullNames)
        {
            if (sicmp(m, text) == 0)
                return i;
        }

        foreach (i, m; *monthShortNames)
        {
            if (sicmp(m, text) == 0)
                return i;
        }

        return -1;
    }

    bool isValid() const @nogc pure
    {
        return (dayOfWeekFullNames !is null) && (dayOfWeekShortNames !is null)
            && (monthFullNames !is null) && (monthShortNames !is null)
            && dateSeparator != 0 && timeSeparator != 0;
    }

    static DateTimePattern usDate() @nogc
    {
        auto usSetting = DateTimeSetting.us;
        DateTimePattern result;
        result.patternText = usSetting.shortDateFormat;
        result.dayOfWeekFullNames = &usDayOfWeekNames;
        result.dayOfWeekShortNames = &usShortDayOfWeekNames;
        result.monthFullNames = &usMonthNames;
        result.monthShortNames = &usShortMonthNames;
        result.amPmTexts = &usAmPmTexts;
        result.dateSeparator = usSetting.dateSeparator;
        result.timeSeparator = usSetting.timeSeparator;
        return result;
    }

    static DateTimePattern usDateTime() @nogc
    {
        auto usSetting = DateTimeSetting.us;
        DateTimePattern result;
        result.patternText = usSetting.shortDateTimeFormat;
        result.dayOfWeekFullNames = &usDayOfWeekNames;
        result.dayOfWeekShortNames = &usShortDayOfWeekNames;
        result.monthFullNames = &usMonthNames;
        result.monthShortNames = &usShortMonthNames;
        result.amPmTexts = &usAmPmTexts;
        result.dateSeparator = usSetting.dateSeparator;
        result.timeSeparator = usSetting.timeSeparator;
        return result;
    }

    static DateTimePattern usTime() @nogc
    {
        auto usSetting = DateTimeSetting.us;
        DateTimePattern result;
        result.patternText = usSetting.shortTimeFormat;
        result.dayOfWeekFullNames = &usDayOfWeekNames;
        result.dayOfWeekShortNames = &usShortDayOfWeekNames;
        result.monthFullNames = &usMonthNames;
        result.monthShortNames = &usShortMonthNames;
        result.amPmTexts = &usAmPmTexts;
        result.dateSeparator = usSetting.dateSeparator;
        result.timeSeparator = usSetting.timeSeparator;
        return result;
    }

    string patternText;
    const(DayOfWeekNames)* dayOfWeekFullNames;
    const(DayOfWeekNames)* dayOfWeekShortNames;
    const(MonthNames)* monthFullNames;
    const(MonthNames)* monthShortNames;
    const(AmPmTexts)* amPmTexts;
    int twoDigitYearCenturyWindow = 50; /// Set to -1 to skip interpreting the value
    char dateSeparator = '/';
    char timeSeparator = ':';
    SkipBlank skipBlanks = cast(SkipBlank)(SkipBlank.leading | SkipBlank.inner | SkipBlank.trailing);
    DateTimeKind defaultKind = DateTimeKind.local;
}

struct DateTimePatternInfo
{
nothrow @safe:

public:
    this(ParseType parseType, scope const(char)[] pattern) @nogc pure
    in
    {
        assert(pattern.length != 0);
    }
    do
    {
        this.dateOrder = DateOrder.ymd;
        this.elementl = this.separatorDateCount = this.separatorTimeCount = 0;
        this.parseType = parseType;

        bool dateOrderSet = false;
        byte lastPatternKind = byte.max;

        void setDateOrder(DateOrder asDateOrder) @nogc nothrow @safe
        {
            if (!dateOrderSet)
            {
                this.dateOrder = asDateOrder;
                dateOrderSet = true;
            }
        }

        bool setCurrentPatternKind(size_t p, PatternKind toKind) @nogc nothrow @safe
        {
            const changed = lastPatternKind == byte.max || cast(PatternKind)lastPatternKind != toKind;
            if (changed)
            {
                if (lastPatternKind != byte.max)
                    this.elements[this.elementl - 1].marker.end = p;

                if (this.elementl >= maxElementLength)
                    return false;

                this.elementl++;
                this.elements[this.elementl - 1].kind = toKind;
                this.elements[this.elementl - 1].marker.begin = p;

                if (toKind == PatternKind.separatorDate)
                    this.separatorDateCount++;
                else if (toKind == PatternKind.separatorTime)
                    this.separatorTimeCount++;
            }

            version (none)
            {
                import pham.utl.test;
                dgWriteln("elementl=", elementl, ", p=", p);
            }

            this.elements[this.elementl - 1].incLength();
            lastPatternKind = toKind;
            return true;
        }

        foreach (i; 0..pattern.length)
        {
            const c = pattern[i];
            switch (c)
            {
                case CustomFormatSpecifier.year:
                    setDateOrder(DateOrder.ymd);
                    if (!setCurrentPatternKind(i, PatternKind.year))
                        goto Done;
                    break;
                case CustomFormatSpecifier.month:
                    setDateOrder(DateOrder.mdy);
                    if (!setCurrentPatternKind(i, PatternKind.month))
                        goto Done;
                    break;
                case CustomFormatSpecifier.day:
                    setDateOrder(DateOrder.dmy);
                    if (!setCurrentPatternKind(i, PatternKind.day))
                        goto Done;
                    break;
                case CustomFormatSpecifier.separatorDate:
                    if (!setCurrentPatternKind(i, PatternKind.separatorDate))
                        goto Done;
                    break;
                case CustomFormatSpecifier.hour:
                    if (!setCurrentPatternKind(i, PatternKind.hour))
                        goto Done;
                    break;
                case CustomFormatSpecifier.minute:
                    if (!setCurrentPatternKind(i, PatternKind.minute))
                        goto Done;
                    break;
                case CustomFormatSpecifier.second:
                    if (!setCurrentPatternKind(i, PatternKind.second))
                        goto Done;
                    break;
                case CustomFormatSpecifier.fraction:
                    if (!setCurrentPatternKind(i, PatternKind.fraction))
                        goto Done;
                    break;
                case CustomFormatSpecifier.amPm:
                    if (!setCurrentPatternKind(i, PatternKind.amPm))
                        goto Done;
                    break;
                case '+':
                case '-':
                    if (!setCurrentPatternKind(i, PatternKind.timeZone))
                        goto Done;
                    break;
                case CustomFormatSpecifier.separatorTime:
                    if (!setCurrentPatternKind(i, PatternKind.separatorTime))
                        goto Done;
                    break;
                default:
                    if (!setCurrentPatternKind(i, PatternKind.literal))
                        goto Done;
                    break;
            }
        }
        if (this.elementl != 0 && this.elements[this.elementl - 1].marker.end == 0)
            this.elements[this.elementl - 1].marker.end = pattern.length;
        Done:
    }

    size_t dayDigitLimit(const(size_t) length) const @nogc pure
    {
        return datePartDigitLimit(length, 2);
    }

    size_t fractionDigitLimit(const(size_t) length) const @nogc pure
    {
        return length == Tick.millisMaxPrecision || separatorTimeCount < 2 ? length : Tick.ticksMaxPrecision;
    }

    size_t hourDigitLimit(const(size_t) length) const @nogc pure
    {
        return timePartDigitLimit(length, 1);
    }

    size_t minuteDigitLimit(const(size_t) length) const @nogc pure
    {
        return timePartDigitLimit(length, 1);
    }

    size_t monthDigitLimit(const(size_t) length) const @nogc pure
    {
        return datePartDigitLimit(length, 1);
    }

    size_t secondDigitLimit(const(size_t) length) const @nogc pure
    {
        return timePartDigitLimit(length, 2);
    }

    size_t yearDigitLimit(const(size_t) length) const @nogc pure
    {
        return length <= 2 && separatorDateCount >= 1 ? 4 : length;
    }

public:
    enum maxElementLength = 20;
    size_t elementl, separatorDateCount, separatorTimeCount;
    PatternElement[maxElementLength] elements;
    DateOrder dateOrder;
    ParseType parseType;

private:
    pragma(inline, true)
    size_t datePartDigitLimit(const(size_t) length, const(size_t) leastSeparatorCount) const @nogc pure
    {
        return (length == 3) || (length == 1 && separatorDateCount >= leastSeparatorCount) ? 2 : length;
    }

    pragma(inline, true)
    size_t timePartDigitLimit(const(size_t) length, const(size_t) leastSeparatorCount) const @nogc pure
    {
        return length == 1 && separatorTimeCount >= leastSeparatorCount ? 2 : length;
    }
}

struct DateTimeParser
{
nothrow @safe:

public:
    this(ParseType parseType) @nogc pure
    {
        this.parseType = parseType;
    }

    DateTimeKind constructTimeKind(scope const ref DateTimePattern pattern) const @nogc pure
    {
        return zoneAdjustment
            ? (zoneAdjustmentBias ? DateTimeKind.unspecified : DateTimeKind.utc)
            : pattern.defaultKind;
    }

    DateTimeKind convertTimeKind(scope const ref DateTimePattern pattern, ref Duration bias) const @nogc pure
    {
        if (pattern.defaultKind == DateTimeKind.unspecified)
            return DateTimeKind.unspecified;

        bias = zoneAdjustmentBias;
        return zoneAdjustment ? pattern.defaultKind : DateTimeKind.unspecified;
    }

    static DateTimePatternInfo getPatternInfo(ParseType parseType, string patternText)
    {
        auto key = CacheDateTimePatternInfoKey(parseType, patternText);
        if (auto found = key in cacheDateTimePatternInfos)
            return *found;
        else
        {
            auto result = DateTimePatternInfo(parseType, patternText);
            cacheDateTimePatternInfos[key] = result;
            return result;
        }
    }

    pragma(inline, true)
    static bool isAlphaChar(const(char) c) @nogc pure
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }

    pragma(inline, true)
    static bool isNumberChar(const(char) c) @nogc pure
    {
        return (c >= '0' && c <= '9');
    }

    pragma(inline, true)
    static bool isSpaceChar(const(char) c) @nogc pure
    {
        return c == ' ' || c == '\f' || c == '\t' || c == '\v';
    }

    pragma(inline, true)
    bool isSymbolChar(scope const ref DateTimePattern pattern, const(char) c) @nogc pure
    {
        return isPunctuation(c)
            && c != '-' && c != '+'
            && c != pattern.dateSeparator && c != pattern.timeSeparator;
    }

    ptrdiff_t parse(scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern)
    {
        scope (failure) assert(0);

        reset();
        endP = dateTimeText.length;
        patternInfo = getPatternInfo(parseType, pattern.patternText.dup);

        if (pattern.skipBlanks & SkipBlank.trailing && skipTrailingBlank(dateTimeText))
            return emptyText;

        if (pattern.skipBlanks & SkipBlank.leading && skipLeadingBlank(dateTimeText))
            return emptyText;

        if (p >= endP)
            return emptyText;

        foreach (i; 0..patternInfo.elementl)
        {
            const currentP = p;
            size_t dummyCount = void;
            const e = this.patternInfo.elements[i];
            final switch (e.kind)
            {
                case PatternKind.year:
                    if (!scanNumber(dateTimeText, pattern, patternInfo.yearDigitLimit(e.length), yearDigitCount, year))
                        return currentP;
                    break;
                case PatternKind.month:
                    if (e.hasText)
                    {
                        PatternMarker monthMarker = void;
                        if (scanAlpha(dateTimeText, pattern, monthMarker))
                        {
                            const iMonth = pattern.indexOfMonth(monthMarker.slice(dateTimeText));
                            if (iMonth < 0)
                                return currentP;
                            month = iMonth + 1;
                            //scanSymbol(dateTimeText, pattern, monthMarker);
                        }
                        else if (!scanNumber(dateTimeText, pattern, patternInfo.monthDigitLimit(e.length), dummyCount, month))
                            return currentP;
                    }
                    else if (!scanNumber(dateTimeText, pattern, patternInfo.monthDigitLimit(e.length), dummyCount, month))
                        return currentP;
                    break;
                case PatternKind.day:
                    if (e.hasText)
                    {
                        PatternMarker dayMarker = void;
                        if (scanAlpha(dateTimeText, pattern, dayMarker))
                        {
                            //scanSymbol(dateTimeText, pattern, dayMarker);
                        }
                        else if (!scanNumber(dateTimeText, pattern, patternInfo.dayDigitLimit(e.length), dummyCount, day))
                            return currentP;
                    }
                    else if (!scanNumber(dateTimeText, pattern, patternInfo.dayDigitLimit(e.length), dummyCount, day))
                        return currentP;
                    break;
                case PatternKind.hour:
                    if (zoneAdjustment == 0)
                    {
                        if (!scanNumber(dateTimeText, pattern, patternInfo.hourDigitLimit(e.length), hourDigitCount, hour))
                            return currentP;
                        hasTime = true;
                    }
                    else
                    {
                        if (!scanNumber(dateTimeText, pattern, patternInfo.hourDigitLimit(e.length), dummyCount, zoneAdjustmentHour))
                            return currentP;
                    }
                    break;
                case PatternKind.minute:
                    if (zoneAdjustment == 0)
                    {
                        if (!scanNumber(dateTimeText, pattern, patternInfo.minuteDigitLimit(e.length), dummyCount, minute))
                            return currentP;
                        hasTime = true;
                    }
                    else
                    {
                        if (!scanNumber(dateTimeText, pattern, patternInfo.minuteDigitLimit(e.length), dummyCount, zoneAdjustmentMinute))
                            return currentP;
                    }
                    break;
                case PatternKind.second:
                    if (!scanNumber(dateTimeText, pattern, patternInfo.secondDigitLimit(e.length), dummyCount, second))
                        return currentP;
                    hasTime = true;
                    break;
                case PatternKind.fraction:
                    if (!scanNumber(dateTimeText, pattern, patternInfo.fractionDigitLimit(e.length), fractionDigitCount, fraction))
                        return currentP;
                    hasTime = true;
                    break;
                case PatternKind.timeZone:
                    if (scanChar(dateTimeText, pattern, '+'))
                        zoneAdjustment = 1;
                    else if (scanChar(dateTimeText, pattern, '-'))
                        zoneAdjustment = -1;
                    else
                        return currentP;
                    break;
                case PatternKind.amPm:
                    PatternMarker amPmMarker = void;
                    if (!scanAlpha(dateTimeText, pattern, amPmMarker))
                        return currentP;
                    const iAmPm = pattern.indexOfAmPm(amPmMarker.slice(dateTimeText));
                    if (iAmPm < 0) // Not matched?
                        return currentP;
                    if (iAmPm == 1) // PM?
                        hourAdjustment = 12;
                    break;
                case PatternKind.separatorDate:
                    if (!scanChar(dateTimeText, pattern, pattern.dateSeparator))
                        return currentP;
                    break;
                case PatternKind.separatorTime:
                    if (!scanChar(dateTimeText, pattern, pattern.timeSeparator))
                        return currentP;
                    break;
                case PatternKind.literal:
                    PatternMarker literalMarker = void;
                    scanLiteral(dateTimeText, pattern, e.marker, literalMarker);
                    break;
            }

            // No more text to scan?
            if (p >= endP)
                break;
        }

        // Skip and check for left over error?
        if (pattern.skipBlanks & SkipBlank.inner)
            skipLeadingBlank(dateTimeText);
        if (p < endP)
            return p;

        if (hourDigitCount && hour < 12 && hourAdjustment)
            hour += hourAdjustment;

        if (yearDigitCount && yearDigitCount <= 2 && pattern.twoDigitYearCenturyWindow >= 0)
        {
            const centuryBase = DateTime.utcNow.year - pattern.twoDigitYearCenturyWindow;
            year += (centuryBase / 100) * 100;
            if (pattern.twoDigitYearCenturyWindow > 0 && year < centuryBase)
                year += 100;
        }

        // Check for missing data error
        final switch (parseType)
        {
            case ParseType.date:
            case ParseType.dateTime:
                if (!hasDate)
                    return 0; // First position as error
                break;
            case ParseType.time:
                if (!hasTime)
                    return 0; // First position as error
                break;
        }

        return noError;
    }

    void reset() @nogc pure
    {
        hasTime = false;
        p = endP = fractionDigitCount = hourDigitCount = yearDigitCount = 0;
        year = month = day = 0;
        hour = minute = second = fraction = hourAdjustment = zoneAdjustment = zoneAdjustmentHour = zoneAdjustmentMinute = 0;
    }

    bool scanAlpha(return scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern,
        out PatternMarker result) @nogc pure
    {
        if (pattern.skipBlanks & SkipBlank.inner)
            skipLeadingBlank(dateTimeText);

        version (none)
        {
            import pham.utl.test;
            dgWriteln("scanAlpha: p=", p, ", dateTimeText=", dateTimeText[p..endP]);
        }

        result.begin = p;
        while (p < endP && isAlphaChar(dateTimeText[p]))
            p++;
        result.end = p;
        return result.end > result.begin;
    }

    bool scanChar(scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern,
        const char c) @nogc pure
    {
        if (pattern.skipBlanks & SkipBlank.inner)
            skipLeadingBlank(dateTimeText);

        version (none)
        {
            import pham.utl.test;
            dgWriteln("scanChar: p=", p, ", dateTimeText=", dateTimeText[p..endP], ", c=", c);
        }

        const result = p < endP && dateTimeText[p] == c;
        if (result)
            p++;
        return result;
    }

    bool scanLiteral(return scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern,
        scope const ref PatternMarker marker, out PatternMarker result) @nogc pure
    {
        version (none)
        {
            import pham.utl.test;
            dgWriteln("scanLiteral: p=", p, ", dateTimeText=", dateTimeText[p..endP], ", length=", marker.end - marker.begin);
        }

        result.begin = p;
        size_t m = marker.begin;
        while (p < endP && m < marker.end)
        {
            if (pattern.skipBlanks & SkipBlank.inner)
            {
                if (skipLeadingBlank(dateTimeText))
                    break;

                while (m < marker.end && isSpaceChar(pattern.patternText[m]))
                    m++;
            }

            // Matching char?
            if (p < endP && m < marker.end)
            {
                if (dateTimeText[p] != pattern.patternText[m])
                    break;
                m++;
                p++;
            }
        }
        result.end = p;
        return result.end > result.begin;
    }

    bool scanNumber(scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern,
        const(size_t) charLimit, out size_t charCount, out int result) @nogc pure
    {
        if (pattern.skipBlanks & SkipBlank.inner)
            skipLeadingBlank(dateTimeText);

        version (none)
        {
            import pham.utl.test;
            dgWriteln("scanNumber: p=", p, ", dateTimeText=", dateTimeText[p..endP], ", charLimit=", charLimit);
        }

        charCount = 0;
        result = 0;
        while (charCount < charLimit && p < endP && isNumberChar(dateTimeText[p]))
        {
            result = result * 10 + (dateTimeText[p] - '0');
            p++;
            charCount++;
        }
        return charCount != 0;
    }

    bool scanSymbol(return scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern,
        out PatternMarker result) @nogc pure
    {
        if (pattern.skipBlanks & SkipBlank.inner)
            skipLeadingBlank(dateTimeText);

        version (none)
        {
            import pham.utl.test;
            dgWriteln("scanSymbol: p=", p, ", dateTimeText=", dateTimeText[p..endP]);
        }

        result.begin = p;
        while (p < endP && isSymbolChar(pattern, dateTimeText[p]))
            p++;
        result.end = p;
        return result.end > result.begin;
    }

    /// Returns true if all blank (no more text to process)
    bool skipLeadingBlank(scope const(char)[] dateTimeText) @nogc pure
    {
        while (p < endP && isSpaceChar(dateTimeText[p]))
            p++;
        return p >= endP;
    }

    /// Returns true if all blank (no more text to process)
    bool skipTrailingBlank(scope const(char)[] dateTimeText) @nogc pure
    {
        while (endP > p && isSpaceChar(dateTimeText[endP - 1]))
            endP--;
        return p >= endP;
    }

    @property bool hasDate() const @nogc pure
    {
        return year > 0 && month > 0 && day > 0;
    }

    @property bool isFraction() const @nogc pure
    {
        return fractionDigitCount > Tick.millisMaxPrecision;
    }

    @property int millisecond() const @nogc pure
    {
        return isFraction ? TickPart.tickToMillisecond(fraction) : fraction;
    }

    @property Duration zoneAdjustmentBias() const @nogc pure
    {
        return zoneAdjustment
            ? dur!"minutes"((zoneAdjustmentHour * 60 + zoneAdjustmentMinute) * zoneAdjustment)
            : Duration.zero;
    }

public:
    enum ptrdiff_t noError = -1;
    enum ptrdiff_t emptyText = -2;
    enum ptrdiff_t emptyPattern = -3;

    DateTimePatternInfo patternInfo;
    size_t p, endP, fractionDigitCount, hourDigitCount, yearDigitCount;
    int year, month, day;
    int hour, minute, second, fraction, hourAdjustment, zoneAdjustment, zoneAdjustmentHour, zoneAdjustmentMinute;
    ParseType parseType;
    bool hasTime;
}

ptrdiff_t tryParse(T)(scope const(char)[] dateTimeText, scope const ref DateTimePattern pattern, out T result) nothrow
if (is(Unqual!T == Date) || is(Unqual!T == DateTime) || is(Unqual!T == Time))
{
    ParseType getParseType() nothrow pure
    {
        static if (is(Unqual!T == Date))
            return ParseType.date;
        else static if (is(Unqual!T == DateTime))
            return ParseType.dateTime;
        else static if (is(Unqual!T == Time))
            return ParseType.time;
        else
            static assert(0);
    }

    enum parseType = getParseType();
    auto parser = DateTimeParser(parseType);
    const parseResult = parser.parse(dateTimeText, pattern);
    if (parseResult == DateTimeParser.noError)
    {
        static if (parseType == ParseType.date)
            result = Date(parser.year, parser.month, parser.day);
        else static if (parseType == ParseType.dateTime)
        {
            const fromKind = parser.constructTimeKind(pattern);
            if (parser.isFraction)
            {
                auto temp = DateTime(parser.year, parser.month, parser.day,
                                    parser.hour, parser.minute, parser.second,
                                    fromKind);
                result = temp.addTicksSafe(parser.fraction);
            }
            else
                result = DateTime(parser.year, parser.month, parser.day,
                                    parser.hour, parser.minute, parser.second, parser.millisecond,
                                    fromKind);

            // Convert to expected timezone?
            Duration bias;
            const toKind = parser.convertTimeKind(pattern, bias);
            if (toKind != DateTimeKind.unspecified && toKind != fromKind)
            {
                auto utcDT = bias == Duration.zero
                    ? DateTime(result.sticks, DateTimeKind.utc)
                    : DateTime(result.addTicksSafe(-bias).sticks, DateTimeKind.utc);
                result = toKind == DateTimeKind.utc ? utcDT : TimeZoneInfo.convertUtcToLocal(utcDT);
            }
        }
        else static if (parseType == ParseType.time)
        {
            if (parser.isFraction)
            {
                auto temp = Time(parser.hour, parser.minute, parser.second);
                result = temp.addTicks(parser.fraction);
            }
            else
                result = Time(parser.hour, parser.minute, parser.second, parser.millisecond);

            // Convert to expected timezone?
            Duration bias;
            const toKind = parser.convertTimeKind(pattern, bias);
            if (toKind != DateTimeKind.unspecified && toKind != parser.constructTimeKind(pattern))
            {
                auto utcDT = bias == Duration.zero
                    ? DateTime(DateTime.utcNow.date, result.asUTC)
                    : DateTime(DateTime.utcNow.date, result.asUTC).addTicksSafe(-bias);
                result = toKind == DateTimeKind.utc ? utcDT.time : TimeZoneInfo.convertUtcToLocal(utcDT).time;
            }
        }
        else
            static assert(0);
    }
    else
        result = T.init;
    return parseResult;
}

ptrdiff_t tryParse(T)(scope const(char)[] dateTimeText, scope const(DateTimePattern)[] patterns, out T result) nothrow
if (is(Unqual!T == Date) || is(Unqual!T == DateTime) || is(Unqual!T == Time))
{
    if (dateTimeText.length == 0)
    {
        result = T.init;
        return DateTimeParser.emptyText;
    }

    if (patterns.length == 0)
    {
        result = T.init;
        return DateTimeParser.emptyPattern;
    }

    auto firstError = ptrdiff_t.min;
    foreach (ref pattern; patterns)
    {
        const parseResult = tryParse!T(dateTimeText, pattern, result);
        if (parseResult == DateTimeParser.noError)
            return DateTimeParser.noError;
        if (firstError == ptrdiff_t.min)
            firstError = parseResult;
    }
    return firstError;
}


private:

struct CacheDateTimePatternInfoKey
{
nothrow @safe:

    this(ParseType parseType, string patternText) pure
    {
        this.parseType = parseType;
        this.patternText = patternText;
    }

    bool opEquals(scope const(CacheDateTimePatternInfoKey) rhs) const @nogc pure scope
    {
        return parseType == rhs.parseType && patternText == rhs.patternText;
    }

    size_t toHash() const @nogc pure scope
    {
        return patternText.hashOf(cast(size_t)parseType);
    }

    string patternText;
    ParseType parseType;
}

DateTimePatternInfo[CacheDateTimePatternInfoKey] cacheDateTimePatternInfos;

unittest // DateTimePatternInfo
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.datetime.date_time_parse.DateTimePatternInfo");

    DateTimePatternInfo p;

    p = DateTimePatternInfo(ParseType.dateTime, "yyyy/mm/ddThh:nn:ss.zzzzzzz");
    assert(p.dateOrder == DateOrder.ymd);
    assert(p.elementl == 13);
    assert(p.elements[0].kind == PatternKind.year);
    assert(p.elements[0].length == 4);
    assert(p.elements[1].kind == PatternKind.separatorDate);
    assert(p.elements[2].kind == PatternKind.month);
    assert(p.elements[2].length == 2);
    assert(p.elements[3].kind == PatternKind.separatorDate);
    assert(p.elements[4].kind == PatternKind.day);
    assert(p.elements[4].length == 2);
    assert(p.elements[5].kind == PatternKind.literal);
    assert(p.elements[6].kind == PatternKind.hour);
    assert(p.elements[6].length == 2);
    assert(p.elements[7].kind == PatternKind.separatorTime);
    assert(p.elements[8].kind == PatternKind.minute);
    assert(p.elements[8].length == 2);
    assert(p.elements[9].kind == PatternKind.separatorTime);
    assert(p.elements[10].kind == PatternKind.second);
    assert(p.elements[10].length == 2);
    assert(p.elements[11].kind == PatternKind.literal);
    assert(p.elements[12].kind == PatternKind.fraction);
    assert(p.elements[12].length == 7);

    p = DateTimePatternInfo(ParseType.date, "dd/mm/yy");
    assert(p.dateOrder == DateOrder.dmy);
    assert(p.elementl == 5);
    assert(p.elements[0].kind == PatternKind.day);
    assert(p.elements[0].length == 2);
    assert(p.elements[1].kind == PatternKind.separatorDate);
    assert(p.elements[2].kind == PatternKind.month);
    assert(p.elements[2].length == 2);
    assert(p.elements[3].kind == PatternKind.separatorDate);
    assert(p.elements[4].kind == PatternKind.year);
    assert(p.elements[4].length == 2);

    p = DateTimePatternInfo(ParseType.date, "mm/dd/yyyy");
    assert(p.dateOrder == DateOrder.mdy);
    assert(p.elementl == 5);
    assert(p.elements[0].kind == PatternKind.month);
    assert(p.elements[0].length == 2);
    assert(p.elements[1].kind == PatternKind.separatorDate);
    assert(p.elements[2].kind == PatternKind.day);
    assert(p.elements[2].length == 2);
    assert(p.elements[3].kind == PatternKind.separatorDate);
    assert(p.elements[4].kind == PatternKind.year);
    assert(p.elements[4].length == 4);

    p = DateTimePatternInfo(ParseType.date, "ddd, d/m/yy");
    assert(p.dateOrder == DateOrder.dmy);
    assert(p.elementl == 7);
    assert(p.elements[0].kind == PatternKind.day);
    assert(p.elements[0].length == 3);
    assert(p.elements[0].hasText);
    assert(p.elements[1].kind == PatternKind.literal);
    assert(p.elements[2].kind == PatternKind.day);
    assert(p.elements[2].length == 1);
    assert(p.elements[3].kind == PatternKind.separatorDate);
    assert(p.elements[4].kind == PatternKind.month);
    assert(p.elements[4].length == 1);
    assert(p.elements[5].kind == PatternKind.separatorDate);
    assert(p.elements[6].kind == PatternKind.year);
    assert(p.elements[6].length == 2);
}

unittest // tryParse
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.datetime.date_time_parse.tryParse");

    ptrdiff_t r;
    auto p = DateTimePattern.usDateTime;

    // DateTime type
    DateTime dt;
    p.patternText = "mm/dd/yyyy";
    r = tryParse!DateTime("01/20/2020", p, dt);
    assert(r == DateTimeParser.noError);
    assert(dt.year == 2020);
    assert(dt.month == 1);
    assert(dt.day == 20);

    p.patternText = "m/d/yyyy";
    r = tryParse!DateTime("01/20/2020", p, dt);
    assert(r == DateTimeParser.noError);
    assert(dt.year == 2020);
    assert(dt.month == 1);
    assert(dt.day == 20);

    // Date type
    Date d;
    p.patternText = "mm/dd/yyyy";
    r = tryParse!Date("02/22/2021", p, d);
    assert(r == DateTimeParser.noError);
    assert(d.year == 2021);
    assert(d.month == 2);
    assert(d.day == 22);

    p.patternText = "m/d/yyyy";
    r = tryParse!Date("2/22/2021", p, d);
    assert(r == DateTimeParser.noError);
    assert(d.year == 2021);
    assert(d.month == 2);
    assert(d.day == 22);

    // Time type
    Time t;
    p.patternText = "hh:nn:ss";
    r = tryParse!Time("01:02:03", p, t);
    assert(r == DateTimeParser.noError);
    assert(t.hour == 1);
    assert(t.minute == 2);
    assert(t.second == 3);

    p.patternText = "h:nn:ss";
    r = tryParse!Time("01:02:03", p, t);
    assert(r == DateTimeParser.noError);
    assert(t.hour == 1);
    assert(t.minute == 2);
    assert(t.second == 3);

    p.patternText = "h:nn";
    r = tryParse!Time("1:2", p, t);
    assert(r == DateTimeParser.noError);
    assert(t.hour == 1);
    assert(t.minute == 2);

    // Complex format
    p.patternText = "ddd, mmm dd, yyyy h:nn:ss a";
    r = tryParse!DateTime("Tuesday, June 8, 2021 2:20:14 PM", p, dt);
    assert(r == DateTimeParser.noError);
    assert(dt.year == 2021);
    assert(dt.month == 6);
    assert(dt.day == 8);
    assert(dt.hour == 14);
    assert(dt.minute == 20);
    assert(dt.second == 14);

    // Check convert to expected timezone
    auto ltz = TimeZoneInfo.localTimeZone;
    if (ltz.baseUtcOffset == dur!"minutes"(-5))
    {
        p.defaultKind = DateTimeKind.local;
        p.patternText = "yyyy/mm/ddThh:nn:ss-hh:nn";
        r = tryParse!DateTime("2021/06/09T11:00:00-04:00", p, dt);
        assert(r == DateTimeParser.noError);
        assert(dt.year == 2021);
        assert(dt.month == 6);
        assert(dt.day == 9);
        assert(dt.hour == 11);
        assert(dt.minute == 0);
        assert(dt.second == 0);

        p.defaultKind = DateTimeKind.utc;
        p.patternText = "yyyy/mm/ddThh:nn:ss-hh:nn";
        r = tryParse!DateTime("2021/06/09T11:00:00-04:00", p, dt);
        assert(r == DateTimeParser.noError);
        assert(dt.year == 2021);
        assert(dt.month == 6);
        assert(dt.day == 9);
        assert(dt.hour == 15); // 3PM utc
        assert(dt.minute == 0);
        assert(dt.second == 0);
    }

    auto isop = DateTimePattern.usDateTime;
    isop.dateSeparator = '-';
    isop.timeSeparator = ':';
    isop.patternText = "yyyy/mm/ddThh:nn:ss.zzzzzzz";
    r = tryParse!DateTime("2009-06-15T13:45:30.0000001", isop, dt);
    assert(r == DateTimeParser.noError);
    assert(dt.year == 2009);
    assert(dt.month == 6);
    assert(dt.day == 15);
    assert(dt.hour == 13);
    assert(dt.minute == 45);
    assert(dt.second == 30);
    assert(dt.fraction == 1);
}
