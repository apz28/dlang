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

module pham.external.std.log.date_time_format;

import core.time : Duration, msecs, usecs;
import std.conv : to;
import std.array : appender;
import std.datetime.date : Date, DateTime, DayOfWeek, Month, TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.format : FormatException;
import std.range.primitives : empty, put;
import std.traits : isSomeChar, isSomeString, Unqual;

@safe:

enum FmtTimeSpecifier : char
{
    custom = 'c', /// Custom specifier `%c` - %cmm/dd/yyyy hh:nn:ss.zzz - 2009-06-01T01:02:03.4 -> 06/01/2009 01:02:03.004
    customAMPM = 'a', /// Time part indicator AM or PM - %ca - 2009-06-15T13:45:30 -> PM
    customDay = 'd', /// Custom day part - %cd, %cdd, %cddd - 2009-06-01T01:02:03 -> 1, 01, Saturday
    customFaction = 'z', /// Custom fraction of second part - %cz, %czzz, %czzzzzz - 2009-06-01T01:02:03.4 -> 4, 004, 004000
    customHour = 'h', /// Custom hour part - %ch, %chh - 2009-06-01T01:02:03 -> 1, 01
    customMinute = 'n', /// Custom minute part - %cn, %cnn - 2009-06-01T01:02:03 -> 2, 02
    customMonth = 'm', /// Custom month part - %cm, %cmm, %cmmm - 2009-06-01T01:02:03 -> 6, 06, June
    customSecond = 's', /// Custom second part - %cs, %css - 2009-06-01T01:02:03 -> 3, 03
    customSeparatorDate = '/', /// Date part separator
    customSeparatorTime = ':', /// Time part separator
    customYear = 'y', /// Custom year part - %cyy, %cyyyy - 2009-06-01T01:02:03 -> 09, 2009
    fullShortDateTime = 'f', /// %f 2009-06-15T12:1:30 -> Monday, June 15, 2009 12:01 PM
    fullLongDateTime = 'F', /// %F 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
    generalShortDateTime = 'g', /// %g 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
    generalLongDateTime = 'G', /// %G 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
    julianDay = 'j', /// %j Julian day - $(HTTP en.wikipedia.org/wiki/Julian_day, Julian day)
    longDate = 'D', /// %D 2009-06-15T13:45:30 -> Monday, June 15, 2009
    longTime = 'T', /// %T 2009-06-15T13:45:30 -> 1:45:30 PM
    monthDay = 'M', /// %M 2009-06-15T13:45:30 -> June 15
    monthYear = 'Y', /// %Y 2009-06-15T13:45:30 -> June 2009
    shortDate = 'd', /// %d 2009-06-15T13:45:30 -> 6/15/2009
    shortTime = 't', /// %t 2009-06-15T13:45:30 -> 1:45 PM
    sortableDateTime = 's', /// %s 2009-06-15T13:45:30.001000 -> 2009-06-15T13:45:30.001000
    sortableDateTimeLess = 'S', /// %S 2009-06-15T13:45:30.001000 -> 2009-06-15T13:45:30
    utcFullDateTime = 'U', /// %U 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
    utcSortableDateTime = 'u', /// %u 2009-06-15T13:45:30.000001 -> 2009-06-15 13:45:30.000001Z
}

alias AmPmTexts = string[2];
alias DayOfWeekNames = string[7];
alias MonthNames = string[12];
alias Time = TimeOfDay;

struct FormatDateTimeContext
{
nothrow @safe:

    const(DayOfWeekNames)* dayOfWeekNames;
    const(MonthNames)* monthNames;
    const(AmPmTexts)* amPmTexts;
    char dateSeparator = 0;
    char timeSeparator = 0;

    bool isValid() const @nogc pure
    {
        return (dayOfWeekNames !is null) && (monthNames !is null) && dateSeparator != 0 && timeSeparator != 0;
    }

    static FormatDateTimeContext us() @nogc
    {
        return FormatDateTimeContext(&usDayOfWeekNames, &usMonthNames, &usAmPmTexts, usDateSeparator, usTimeSeparator);
    }
}

FormatDateTimeContext threadDateTimeContext;
__gshared FormatDateTimeContext sharedDateTimeContext = FormatDateTimeContext.us();

struct FormatDateTimeValue
{
nothrow @safe:

    enum firstDayOfWeek = DayOfWeek.sun;
    enum firstDayOfMonth = Month.jan;

    enum ValueKind : byte
    {
        date,
        dateTime,
        sysTime,
        time
    }

    this(scope const Date date) @nogc pure
    {
        this._kind = ValueKind.date;
        this.initYMD(date);
        this.initHMS(date);
    }

    this(scope const DateTime dateTime) @nogc pure
    {
        this._kind = ValueKind.dateTime;
        this.initYMD(dateTime);
        this.initHMS(dateTime);
    }

    this(scope const SysTime sysTime) @trusted
    {
        this._kind = ValueKind.sysTime;
        this.initYMD(sysTime);
        this.initHMS(sysTime);
    }

    this(scope const Time time) @nogc pure
    {
        this._kind = ValueKind.time;
        this.initYMD(time);
        this.initHMS(time);
    }

    string amPM(scope const FormatDateTimeContext context) const @nogc pure
    {
        return kind != ValueKind.date && context.amPmTexts !is null
            ? (*context.amPmTexts)[hour >= 12]
            : null;
    }

    string dayOfWeekName(scope const FormatDateTimeContext context) const @nogc pure
    {
        return kind != ValueKind.time
            ? (*context.dayOfWeekNames)[dayOfWeek - firstDayOfWeek]
            : null;
    }

    string monthName(scope const FormatDateTimeContext context) const @nogc pure
    {
        return kind != ValueKind.time
            ? (*context.monthNames)[month - firstDayOfMonth]
            : null;
    }

    @property int century() const @nogc pure
    {
        return year / 100;
    }

    @property int day() const @nogc pure
    {
        return _day;
    }

    @property DayOfWeek dayOfWeek() const @nogc pure
    {
        return _dayOfWeek;
    }

    @property ValueKind kind() const @nogc pure
    {
        return _kind;
    }

    @property int hour() const @nogc pure
    {
        return _hour;
    }

    @property long julianDay() const @nogc pure
    {
        return _julianDay;
    }

    @property int millisecond() const @nogc pure
    {
        return _millisecond;
    }

    @property int minute() const @nogc pure
    {
        return _minute;
    }

    @property int month() const @nogc pure
    {
        return _month;
    }

    @property int second() const @nogc pure
    {
        return _second;
    }

    @property int shortHour() const @nogc pure
    {
        return hour <= 12 ? hour : hour - 12;
    }

    @property int shortYear() const @nogc pure
    {
        return year - (century * 100);
    }

    @property int tick() const @nogc pure
    {
        return _tick;
    }

    @property int year() const @nogc pure
    {
        return _year;
    }

private:
    void initYMD(scope const Date date) @nogc pure
    {
        _year = date.year;
        _month = date.month;
        _day = date.day;
        _julianDay = date.julianDay;
        _dayOfWeek = date.dayOfWeek;
    }

    void initYMD(scope const DateTime dateTime) @nogc pure
    {
        _year = dateTime.year;
        _month = dateTime.month;
        _day = dateTime.day;
        _julianDay = dateTime.julianDay;
        _dayOfWeek = dateTime.dayOfWeek;
    }

    void initYMD(scope const SysTime sysTime) @trusted
    {
        const sd = cast(DateTime)sysTime;
        _year = sd.year;
        _month = sd.month;
        _day = sd.day;
        _julianDay = sysTime.julianDay;
        _dayOfWeek = sysTime.dayOfWeek;
    }

    void initYMD(scope const Time time) @nogc pure
    {
        _year = _month = _day = 0;
        _julianDay = time.hour >= 12 ? 1 : 0;
        _dayOfWeek = firstDayOfWeek;
    }

    void initHMS(scope const Date date) @nogc pure
    {
        _hour = _minute = _second = _millisecond = 0;
    }

    void initHMS(scope const DateTime dateTime) @nogc pure
    {
        _hour = dateTime.hour;
        _minute = dateTime.minute;
        _second = dateTime.second;
        _millisecond = _tick = 0;
    }

    void initHMS(scope const SysTime sysTime) @trusted
    {
        const st = cast(TimeOfDay)sysTime;
        const sf = sysTime.fracSecs;
        _hour = st.hour;
        _minute = st.minute;
        _second = st.second;
        _millisecond = cast(int)sf.total!"msecs"(); // Total fracSecs in msecs
        _tick = cast(int)sf.total!"usecs"(); // Total fracSecs in usecs
    }

    void initHMS(scope const Time time) @nogc pure
    {
        _hour = time.hour;
        _minute = time.minute;
        _second = time.second;
        _millisecond = _tick = 0;
    }

private:
    long _julianDay;
    int _year, _month, _day;
    int _hour, _minute, _second, _millisecond, _tick;
    DayOfWeek _dayOfWeek;
    ValueKind _kind;
}

alias enforceFmt = enforce!FormatException;

struct FormatDateTimeSpec(Char)
if (is(Unqual!Char == Char))
{
@safe:

public:
    const(Char)[] trailing; /// contains the rest of the format string.
    const(Char)[] customTrailing; /// contains custom format string
    size_t customSpecCount;
    Char customSpec;
    Char spec = FmtTimeSpecifier.sortableDateTime; /// The actual/current format specifier

    /**
     * Construct a new `FormatDateTimeSpec` using the format string `fmt`, no
     * processing is done until needed.
     */
    this(in Char[] fmt) pure
    {
        this.trailing = fmt;
    }

    /**
     * Write the format string to an output range until the next format
     * specifier is found and parse that format specifier.
     * See $(LREF FormatSpec) for an example, how to use `writeUpToNextSpec`.
     * Params:
     *  writer = the $(REF_ALTTEXT output range, isOutputRange, std, range, primitives)
     * Returns:
     *  True, when a format specifier is found.
     * Throws:
     *  A $(LREF FormatException) when the found format specifier could not be parsed.
     */
    bool writeUpToNextSpec(Writer)(ref Writer writer) pure scope
    {
        if (trailing.empty)
            return false;

        size_t i = 0;
        for (; i < trailing.length; ++i)
        {
            if (trailing[i] != '%')
                continue;

            if (i)
            {
                put(writer, trailing[0..i]);
                trailing = trailing[i..$];
            }
            // at least '%' and spec-char
            enforceFmt(trailing.length >= 2, "Unterminated format specifier: " ~ to!string(trailing));
            trailing = trailing[1..$]; // Skip '%'

            // Spec found. Fill up the spec, and bailout
            if (trailing[0] != '%')
            {
                fillWriteUpToNextSpec();
                return true;
            }

            // Reset and keep going
            i = 0;
        }

        // no format spec found
        put(writer, trailing);
        trailing = null;
        return false;
    }

    bool writeUpToNextCustomSpec(Writer)(ref Writer writer) pure scope
    {
        if (customTrailing.empty)
            return false;

        size_t i = 0;
        for (; i < customTrailing.length; ++i)
        {
            const c = customTrailing[i];
            if (c != '%' && !isCustomModifierChar(c))
                continue;

            if (i)
            {
                put(writer, customTrailing[0..i]);
                customTrailing = customTrailing[i..$];
            }
            enforceFmt((customTrailing.length > 0) || (customTrailing.length > 1 && customTrailing[0] == '%'), "Unterminated custom format specifier");

            // Skip '%'?
            if (customTrailing[0] == '%')
                customTrailing = customTrailing[1..$];

            // Spec found. Fill up the spec, and bailout
            if (customTrailing[0] != '%')
            {
                fillWriteUpToNextCustomSpec();
                return true;
            }

            // Reset and keep going
            i = 0;
        }

        // no format spec found
        put(writer, customTrailing);
        customTrailing = null;
        return false;
    }

    static bool isCustomModifierChar(const Char c) @nogc nothrow pure
    {
        return c == FmtTimeSpecifier.customAMPM
            || c == FmtTimeSpecifier.customDay
            || c == FmtTimeSpecifier.customFaction
            || c == FmtTimeSpecifier.customHour
            || c == FmtTimeSpecifier.customMinute
            || c == FmtTimeSpecifier.customMonth
            || c == FmtTimeSpecifier.customSecond
            || c == FmtTimeSpecifier.customSeparatorDate
            || c == FmtTimeSpecifier.customSeparatorTime
            || c == FmtTimeSpecifier.customYear;
    }

private:
    void fillWriteUpToNextSpec() pure
    {
        customTrailing = null;
        customSpecCount = 0;
        customSpec = '\0';
        spec = trailing[0];
        trailing = trailing[1..$];

        switch (spec)
        {
            case FmtTimeSpecifier.custom:
                enforceFmt(trailing.length > 0, "Missing custom format modifier: " ~ to!string(trailing));
                fillWriteUpToNextSpecCustom();
                return;
            case FmtTimeSpecifier.fullShortDateTime:
            case FmtTimeSpecifier.fullLongDateTime:
            case FmtTimeSpecifier.generalShortDateTime:
            case FmtTimeSpecifier.generalLongDateTime:
            case FmtTimeSpecifier.julianDay:
            case FmtTimeSpecifier.longDate:
            case FmtTimeSpecifier.longTime:
            case FmtTimeSpecifier.monthDay:
            case FmtTimeSpecifier.monthYear:
            case FmtTimeSpecifier.shortDate:
            case FmtTimeSpecifier.shortTime:
            case FmtTimeSpecifier.sortableDateTime:
            case FmtTimeSpecifier.sortableDateTimeLess:
            case FmtTimeSpecifier.utcFullDateTime:
            case FmtTimeSpecifier.utcSortableDateTime:
                return;
            default:
                enforceFmt(false, "Incorrect format specifier: " ~ to!string(spec));
        }
    }

    void fillWriteUpToNextSpecCustom() pure
    {
        size_t i = 0, found = 0;
        for (; i < trailing.length; ++i)
        {
            const c = trailing[i];
            // Next specifier?
            if (c == '%')
            {
                // Escape literal '%'?
                const n = i + 1;
                if (n < trailing.length && trailing[n] == '%')
                    i++;
                else
                    break;
            }
            else
            {
                if (isCustomModifierChar(c))
                    found++;
            }
        }
        enforceFmt(i > 0 && found > 0, "Missing custom format modifier: " ~ to!string(trailing));
        customTrailing = trailing[0..i];
        trailing = trailing[i..$];
    }

    void fillWriteUpToNextCustomSpec() pure
    {
        size_t limit = 0;
        customSpecCount = 0;
        customSpec = customTrailing[0];
        switch (customSpec)
        {
            case FmtTimeSpecifier.customAMPM:
                limit = 1;
                break;
            case FmtTimeSpecifier.customDay:
                limit = 3;
                break;
            case FmtTimeSpecifier.customFaction: // time fraction, 1..3=msec, 4..6=usec
                limit = 6;
                break;
            case FmtTimeSpecifier.customHour:
            case FmtTimeSpecifier.customMinute:
                limit = 2;
                break;
            case FmtTimeSpecifier.customMonth:
                limit = 3;
                break;
            case FmtTimeSpecifier.customSecond:
                limit = 2;
                break;
            case FmtTimeSpecifier.customSeparatorDate:
            case FmtTimeSpecifier.customSeparatorTime:
                limit = 1;
                break;
            case FmtTimeSpecifier.customYear:
                limit = 4;
                break;
            default:
                assert(0);
        }
        for (size_t i = 0; i < customTrailing.length && customSpec == customTrailing[i]; i++)
            customSpecCount++;
        enforceFmt(customSpecCount <= limit, "Invalid custom format modifier: " ~ to!string(customTrailing[0..customSpecCount]));
        customTrailing = customTrailing[customSpecCount..$];
    }
}

uint formatValue(Writer, Char)(auto ref Writer writer, scope ref FormatDateTimeValue fmtValue, scope ref FormatDateTimeSpec!Char fmtSpec)
if (isSomeChar!Char)
{
    const context = threadDateTimeContext;

    void putAMorPM() nothrow @safe
    {
        auto s = fmtValue.amPM(context);
        if (s.length)
        {
            put(writer, ' ');
            put(writer, s[]);
        }
    }

    void putCustom() @safe
    {
        while (fmtSpec.writeUpToNextCustomSpec(writer))
        {
            switch (fmtSpec.customSpec)
            {
                case FmtTimeSpecifier.customAMPM:
                    putAMorPM();
                    break;
                case FmtTimeSpecifier.customDay:
                    if (fmtSpec.customSpecCount == 3)
                        put(writer, fmtValue.dayOfWeekName(context));
                    else
                        put(writer, pad(to!string(fmtValue.day), fmtSpec.customSpecCount, '0'));
                    break;
                case FmtTimeSpecifier.customFaction: // time fraction, 1..3=msec, 4..6=usec
                    if (fmtSpec.customSpecCount <= 3)
                        put(writer, pad(to!string(fmtValue.millisecond), fmtSpec.customSpecCount, '0'));
                    else
                        put(writer, pad(to!string(fmtValue.tick), fmtSpec.customSpecCount, '0'));
                    break;
                case FmtTimeSpecifier.customHour:
                    put(writer, pad(to!string(fmtValue.hour), fmtSpec.customSpecCount, '0'));
                    break;
                case FmtTimeSpecifier.customMinute:
                    put(writer, pad(to!string(fmtValue.minute), fmtSpec.customSpecCount, '0'));
                    break;
                case FmtTimeSpecifier.customMonth:
                    if (fmtSpec.customSpecCount == 3)
                        put(writer, fmtValue.monthName(context));
                    else
                        put(writer, pad(to!string(fmtValue.month), fmtSpec.customSpecCount, '0'));
                    break;
                case FmtTimeSpecifier.customSecond:
                    put(writer, pad(to!string(fmtValue.second), fmtSpec.customSpecCount, '0'));
                    break;
                case FmtTimeSpecifier.customSeparatorDate:
                    put(writer, context.dateSeparator);
                    break;
                case FmtTimeSpecifier.customSeparatorTime:
                    put(writer, context.timeSeparator);
                    break;
                case FmtTimeSpecifier.customYear:
                    if (fmtSpec.customSpecCount <= 2)
                        put(writer, pad(to!string(fmtValue.shortYear), fmtSpec.customSpecCount, '0'));
                    else
                        put(writer, pad(to!string(fmtValue.year), fmtSpec.customSpecCount, '0'));
                    break;
                default:
                    assert(0);
            }
        }
    }

    void putFullDateTime() nothrow @safe
    {
        put(writer, fmtValue.dayOfWeekName(context));
        put(writer, ", ");
        put(writer, fmtValue.monthName(context));
        put(writer, ' ');
        put(writer, to!string(fmtValue.day));
        put(writer, ", ");
        put(writer, pad(to!string(fmtValue.year), 4, '0'));
        put(writer, ' ');
        put(writer, to!string(fmtValue.shortHour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtValue.minute), 2, '0'));
    }

    void putGeneralDateTime() nothrow @safe
    {
        put(writer, to!string(fmtValue.month));
        put(writer, context.dateSeparator);
        put(writer, to!string(fmtValue.day));
        put(writer, context.dateSeparator);
        put(writer, pad(to!string(fmtValue.year), 4, '0'));
        put(writer, ' ');
        put(writer, to!string(fmtValue.shortHour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtValue.minute), 2, '0'));
    }

    void putTime() nothrow @safe
    {
        put(writer, to!string(fmtValue.shortHour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtValue.minute), 2, '0'));
    }

    uint result = 0;
    while (fmtSpec.writeUpToNextSpec(writer))
    {
        switch (fmtSpec.spec)
        {
            case FmtTimeSpecifier.custom:
                putCustom();
                break;
            case FmtTimeSpecifier.fullShortDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01 PM
                putFullDateTime();
                putAMorPM();
                break;
            case FmtTimeSpecifier.fullLongDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
                putFullDateTime();
                put(writer, context.timeSeparator);
                put(writer, pad(to!string(fmtValue.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.generalShortDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
                putGeneralDateTime();
                putAMorPM();
                break;
            case FmtTimeSpecifier.generalLongDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
                putGeneralDateTime();
                put(writer, context.timeSeparator);
                put(writer, pad(to!string(fmtValue.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.julianDay:
                put(writer, to!string(fmtValue.julianDay));
                break;
            case FmtTimeSpecifier.longDate: // 2009-06-15T13:45:30 -> Monday, June 15, 2009
                put(writer, fmtValue.dayOfWeekName(context));
                put(writer, ", ");
                put(writer, fmtValue.monthName(context));
                put(writer, ' ');
                put(writer, to!string(fmtValue.day));
                put(writer, ", ");
                put(writer, pad(to!string(fmtValue.year), 4, '0'));
                break;
            case FmtTimeSpecifier.longTime: // 2009-06-15T13:45:30 -> 1:45:30 PM
                putTime();
                put(writer, context.timeSeparator);
                put(writer, pad(to!string(fmtValue.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.monthDay: // 2009-06-15T13:45:30 -> June 15
                put(writer, fmtValue.monthName(context));
                put(writer, ' ');
                put(writer, to!string(fmtValue.day));
                break;
            case FmtTimeSpecifier.monthYear: // 2009-06-15T13:45:30 -> June 2009
                put(writer, fmtValue.monthName(context));
                put(writer, ' ');
                put(writer, pad(to!string(fmtValue.year), 4, '0'));
                break;
            case FmtTimeSpecifier.shortDate: // 2009-06-15T13:45:30 -> 6/15/2009
                put(writer, to!string(fmtValue.month));
                put(writer, context.dateSeparator);
                put(writer, to!string(fmtValue.day));
                put(writer, context.dateSeparator);
                put(writer, pad(to!string(fmtValue.year), 4, '0'));
                break;
            case FmtTimeSpecifier.shortTime: // 2009-06-15T13:45:30 -> 1:45 PM
                putTime();
                putAMorPM();
                break;
            case FmtTimeSpecifier.sortableDateTime: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30.000001
                // Date part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.time)
                {
                    put(writer, pad(to!string(fmtValue.year), 4, '0'));
                    put(writer, '-');
                    put(writer, pad(to!string(fmtValue.month), 2, '0'));
                    put(writer, '-');
                    put(writer, pad(to!string(fmtValue.day), 2, '0'));

                    // Has time?
                    if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                        put(writer, 'T');
                }

                // Time part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                {
                    put(writer, pad(to!string(fmtValue.hour), 2, '0'));
                    put(writer, ':');
                    put(writer, pad(to!string(fmtValue.minute), 2, '0'));
                    put(writer, ':');
                    put(writer, pad(to!string(fmtValue.second), 2, '0'));
                    put(writer, '.');
                    put(writer, pad(to!string(fmtValue.tick), 6, '0'));
                }
                break;
            case FmtTimeSpecifier.sortableDateTimeLess: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30
                put(writer, pad(to!string(fmtValue.year), 4, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtValue.month), 2, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtValue.day), 2, '0'));
                put(writer, 'T');
                put(writer, pad(to!string(fmtValue.hour), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtValue.minute), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtValue.second), 2, '0'));
                break;
            case FmtTimeSpecifier.utcFullDateTime: // 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
                put(writer, fmtValue.dayOfWeekName(context));
                put(writer, ", ");
                put(writer, fmtValue.monthName(context));
                put(writer, ' ');
                put(writer, to!string(fmtValue.day));
                put(writer, ", ");
                put(writer, pad(to!string(fmtValue.year), 4, '0'));
                put(writer, ' ');
                put(writer, to!string(fmtValue.shortHour));
                put(writer, ':');
                put(writer, pad(to!string(fmtValue.minute), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtValue.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.utcSortableDateTime: // 2009-06-15T13:45:30.000001 -> 2009-06-15 13:45:30.000001Z
                put(writer, pad(to!string(fmtValue.year), 4, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtValue.month), 2, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtValue.day), 2, '0'));
                put(writer, ' ');
                put(writer, pad(to!string(fmtValue.hour), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtValue.minute), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtValue.second), 2, '0'));
                put(writer, '.');
                put(writer, pad(to!string(fmtValue.tick), 6, '0'));
                put(writer, 'Z');
                break;
            default:
                assert(0);
        }
        result++;
    }
    return result;
}

uint formatValue(Writer, Char)(auto ref Writer writer, scope ref FormatDateTimeValue fmtValue, scope const(Char)[] fmt)
if (isSomeChar!Char)
{
    auto fmtSpec = FormatDateTimeSpec!Char(fmt);
    return formatValue(writer, fmtValue, fmtSpec);
}

C[] arrayOfChar(C = char)(size_t count, C c) nothrow pure
if (is(Unqual!C == char) || is(Unqual!C == wchar) || is(Unqual!C == dchar))
{
    auto result = new Unqual!C[count];
    result[] = c;
    return result;
}

S pad(S, C)(S value, const(ptrdiff_t) size, C c) nothrow pure
if (isSomeString!S && isSomeChar!C && is(Unqual!(typeof(S.init[0])) == C))
{
    import std.math : abs;

    const n = abs(size);
    if (value.length >= n)
        return value;
    else
        return size > 0
            ? arrayOfChar!C(n - value.length, c) ~ value
            : value ~ arrayOfChar!C(n - value.length, c);
}

string toString(scope const Date date)
{
    return format(date, "%s");
}

string format(scope const Date date, const(char)[] fmt)
{
    auto fmtValue = FormatDateTimeValue(date);
    auto buffer = appender!string;
    buffer.reserve(50);
    formatValue(buffer, fmtValue, fmt);
    return buffer.data;
}

string toString(scope const DateTime dateTime)
{
    return format(dateTime, "%s");
}

string format(scope const DateTime dateTime, const(char)[] fmt)
{
    auto fmtValue = FormatDateTimeValue(dateTime);
    auto buffer = appender!string;
    buffer.reserve(50);
    formatValue(buffer, fmtValue, fmt);
    return buffer.data;
}

string toString(scope const SysTime sysTime)
{
    return format(sysTime, "%s");
}

string format(scope const SysTime sysTime, const(char)[] fmt)
{
    auto fmtValue = FormatDateTimeValue(sysTime);
    auto buffer = appender!string;
    buffer.reserve(50);
    formatValue(buffer, fmtValue, fmt);
    return buffer.data;
}

string toString(scope const Time time)
{
    return format(time, "%s");
}

string format(scope const Time time, const(char)[] fmt)
{
    auto fmtValue = FormatDateTimeValue(time);
    auto buffer = appender!string;
    buffer.reserve(50);
    formatValue(buffer, fmtValue, fmt);
    return buffer.data;
}

immutable AmPmTexts usAmPmTexts = ["AM", "PM"];
immutable char usDateSeparator = '/';
immutable char usTimeSeparator = ':';

// Must match order of DayOfWeek
immutable DayOfWeekNames usDayOfWeekNames = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
    ];

// Must match order of Month
immutable MonthNames usMonthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
    ];


private:

static this() @trusted
{
    threadDateTimeContext = sharedDateTimeContext;
}

@safe unittest // FmtTimeSpecifier.fullShortDateTime, fullLongDateTime
{
    string s;

    s = DateTime(2009, 06, 15, 12, 1, 30).format("%f");
    assert(s == "Monday, June 15, 2009 12:01 PM", s);
    s = DateTime(2009, 06, 15, 13, 1, 30).format("%F");
    assert(s == "Monday, June 15, 2009 1:01:30 PM", s);
}

@safe unittest // FmtTimeSpecifier.generalShortDateTime, generalLongDateTime
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%g");
    assert(s == "6/15/2009 1:45 PM", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).format("%G");
    assert(s == "6/15/2009 1:45:30 PM", s);
}

@safe unittest // FmtTimeSpecifier.julianDay
{
    string s;

    s = DateTime(2010, 8, 24, 0, 0, 0).format("%j");
    assert(s == "2455432", s);

    s = DateTime(2010, 8, 24, 11, 59, 59).format("%j");
    assert(s == "2455432", s);

    s = DateTime(2010, 8, 24, 12, 0, 0).format("%j");
    assert(s == "2455433", s);

    s = DateTime(2010, 8, 24, 13, 0, 0).format("%j");
    assert(s == "2455433", s);

    s = Date(2010, 8, 24).format("%j");
    assert(s == "2455433", s);

    s = Time(11, 59, 59).format("%j");
    assert(s == "0", s);

    s = Time(12, 0, 0).format("%j");
    assert(s == "1", s);
}

@safe unittest // FmtTimeSpecifier.longDate, shortDate
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%D");
    assert(s == "Monday, June 15, 2009", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).format("%d");
    assert(s == "6/15/2009", s);

    s = Date(2009, 06, 15).format("%D");
    assert(s == "Monday, June 15, 2009", s);
    s = Date(2009, 06, 15).format("%d");
    assert(s == "6/15/2009");
}

@safe unittest // FmtTimeSpecifier.longTime, shortTime
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%T");
    assert(s == "1:45:30 PM", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).format("%t");
    assert(s == "1:45 PM", s);

    s = Time(13, 45, 30).format("%T");
    assert(s == "1:45:30 PM", s);
    s = Time(13, 45, 30).format("%t");
    assert(s == "1:45 PM", s);
}

@safe unittest // FmtTimeSpecifier.monthDay, monthYear
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%M");
    assert(s == "June 15", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).format("%Y");
    assert(s == "June 2009");
}

@safe unittest // FmtTimeSpecifier.sortableDateTime
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%s");
    assert(s == "2009-06-15T13:45:30.000000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).format("%s");
    assert(s == "2009-06-15T13:45:30.000000", s);
    s = SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null).format("%s");
    assert(s == "2009-06-15T13:45:30.000001", s);

    s = Date(2009, 06, 15).format("%s");
    assert(s == "2009-06-15", s);

    s = Time(13, 45, 30).format("%s");
    assert(s == "13:45:30.000000", s);
}

@safe unittest // FmtTimeSpecifier.sortableDateTimeLess
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%S");
    assert(s == "2009-06-15T13:45:30", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).format("%S");
    assert(s == "2009-06-15T13:45:30", s);
    s = SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null).format("%S");
    assert(s == "2009-06-15T13:45:30", s);
}

@safe unittest // FmtTimeSpecifier.utcFullDateTime
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%U");
    assert(s == "Monday, June 15, 2009 1:45:30 PM", s);
}

@safe unittest // FmtTimeSpecifier.utcSortableDateTime
{
    string s;

    s = SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null).format("%u");
    assert(s == "2009-06-15 13:45:30.000001Z", s);
}

@safe unittest // FmtTimeSpecifier.custom, FmtTimeSpecifier.dateSeparator, FmtTimeSpecifier.timeSeparator
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).format("%cmm/dd/yyyy hh:nn:ss");
    assert(s == "06/15/2009 13:45:30", s);
    s = DateTime(2009, 06, 15, 3, 45, 30).format("%cm/dd/yyyy h:nn:ss");
    assert(s == "6/15/2009 3:45:30", s);
    s = DateTime(2009, 06, 15, 3, 45, 30).format("%cm/dd/yy h:nn:ss");
    assert(s == "6/15/09 3:45:30", s);

    s = Date(2009, 06, 15).format("%cdd/mm/yyyy");
    assert(s == "15/06/2009", s);
    s = Date(2009, 06, 15).format("%cdd/mm/yy");
    assert(s == "15/06/09", s);

    s = Date(2009, 06, 1).format("%cmmm d, yyyy");
    assert(s == "June 1, 2009", s);

    s = Date(2009, 06, 1).format("%cddd, mmm d, yyyy");
    assert(s == "Monday, June 1, 2009", s);

    s = SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null).format("%cyyyymmdd hhnnsszzz");
    assert(s == "20090615 134530000", s);
    s = SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null).format("%cyyyymmdd hhnnsszzzzzz");
    assert(s == "20090615 134530000001", s);

    s = Time(13, 45, 30).format("%ch:n:s");
    assert(s == "13:45:30", s);

    // Escape % weird character format
    s = Date(2009, 06, 15).format("%cdd-%%?mm'%%-yyyy");
    assert(s == "15-%?06'%-2009", s);
}
