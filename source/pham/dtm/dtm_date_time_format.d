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

module pham.dtm.dtm_date_time_format;

public import std.format : FormatException;
import std.range.primitives : isOutputRange, put;
import std.traits : isSomeChar, isSomeString, Unqual;

import pham.dtm.dtm_date : Date, DateTime, DayOfWeek, JulianDate,
    firstDayOfMonth, firstDayOfWeek;
import pham.dtm.dtm_tick;
import pham.dtm.dtm_time : Time;
import pham.dtm.dtm_time_zone : TimeZoneInfo, ZoneOffset;

@safe:

enum FormatDateTimeSpecifier : char
{
    custom = 'c', /// Custom specifier `%c` - %cmm/dd/yyyy hh:nn:ss.zzz - 2009-06-01T01:02:03.4 -> 06/01/2009 01:02:03.004
    customAmPm = CustomFormatSpecifier.amPm, /// Time part indicator AM or PM - %ca - 2009-06-15T13:45:30 -> PM
    customDay = CustomFormatSpecifier.day, /// Custom day part - %cd, %cdd, %cddd - 2009-06-01T01:02:03 -> 1, 01, Saturday
    customFraction = CustomFormatSpecifier.fraction, /// Custom fraction of second part - %cz, %czzz, %czzzzzzz - 2009-06-01T01:02:03.4 -> 4, 004, 0040000
    customLongHour = CustomFormatSpecifier.longHour, /// Custom hour part - %cH, %cHH - 2009-06-01T1:02:03 -> 1, 01; 2009-06-01T13:02:03 -> 13, 13
    customShortHour = CustomFormatSpecifier.shortHour, /// Custom hour part - %ch, %chh - 2009-06-01T13:02:03 -> 1, 01
    customMinute = CustomFormatSpecifier.minute, /// Custom minute part - %cn, %cnn - 2009-06-01T01:02:03 -> 2, 02
    customMonth = CustomFormatSpecifier.month, /// Custom month part - %cm, %cmm, %cmmm - 2009-06-01T01:02:03 -> 6, 06, June
    customSecond = CustomFormatSpecifier.second, /// Custom second part - %cs, %css - 2009-06-01T01:02:03 -> 3, 03
    customSeparatorDate = CustomFormatSpecifier.separatorDate, /// Date part separator
    customSeparatorTime = CustomFormatSpecifier.separatorTime, /// Time part separator
    customYear = CustomFormatSpecifier.year, /// Custom year part - %cyy, %cyyyy - 2009-06-01T01:02:03 -> 09, 2009
    generalShortDateTime = 'g', /// %g 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
    generalLongDateTime = 'G', /// %G 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
    julianDay = 'j', /// %j Julian day - $(HTTP en.wikipedia.org/wiki/Julian_day, Julian day)
    longDate = 'D', /// %D 2009-06-15T13:45:30 -> Monday, June 15, 2009
    longDateTime = 'F', /// %F 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
    longTime = 'T', /// %T 2009-06-15T13:45:30 -> 1:45:30 PM
    monthDay = 'M', /// %M 2009-06-15T13:45:30 -> June 15
    monthYear = 'Y', /// %Y 2009-06-15T13:45:30 -> June 2009
    shortDate = 'd', /// %d 2009-06-15T13:45:30 -> 6/15/2009
    shortDateTime = 'f', /// %f 2009-06-15T12:1:30 -> Monday, June 15, 2009 12:01 PM
    shortTime = 't', /// %t 2009-06-15T13:45:30 -> 1:45 PM
    sortableDateTime = 's', /// %s 2009-06-15T13:45:30.0010000 -> 2009-06-15T13:45:30.0010000
    sortableDateTimeLess = 'S', /// %S 2009-06-15T13:45:30.0010000 -> 2009-06-15T13:45:30
    utcSortableDateTime = 'u', /// %u 2009-06-15T13:45:30.0000001 -> 2009-06-15 13:45:30.0000001Z
    utcSortableDateTimeZ = 'U', /// %U 2009-06-15T13:45:30.0000001 -> 2009-06-15 13:45:30.0000001+HH:NN
}

struct FormatDateTimeValue
{
nothrow @safe:

public:
    this(in Date date) @nogc pure
    {
        this._kind = DateTimeKind.date;
        this.date = date;
        date.getDate(_year, _month, _day);
    }

    this(in DateTime dateTime)
    {
        this._kind = DateTimeKind.dateTime;
        this.dateTime = dateTime;
        dateTime.getDate(_year, _month, _day);
        dateTime.getTimePrecise(_hour, _minute, _second, _tick);
        this._millisecond = TickPart.tickToMillisecond(_tick);
        this._utcBias = dateTime.utcBias;
    }

    this(in Time time)
    {
        this._kind = DateTimeKind.time;
        this.time = time;
        time.getTimePrecise(_hour, _minute, _second, _tick);
        this._millisecond = TickPart.tickToMillisecond(_tick);
        this._utcBias = time.utcBias;
    }

    string amPM(scope const ref DateTimeSetting setting) const pure
    {
        return kind != DateTimeKind.date && setting.amPmTexts !is null
            ? (*setting.amPmTexts)[hour >= 12]
            : null;
    }

    string dayOfWeekName(scope const ref DateTimeSetting setting, const(bool) useShort) const pure
    {
        auto dayOfWeekNames = useShort ? setting.shortDayOfWeekNames : setting.fullDayOfWeekNames;
        return kind != DateTimeKind.time
            ? (*dayOfWeekNames)[dayOfWeek - firstDayOfWeek]
            : null;
    }

    string monthName(scope const ref DateTimeSetting setting, const(bool) useShort) const pure
    {
        auto monthNames = useShort ? setting.shortMonthNames : setting.fullMonthNames;
        return kind != DateTimeKind.time
            ? (*monthNames)[month - firstDayOfMonth]
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
        final switch (kind)
        {
            case DateTimeKind.date:
                return date.dayOfWeek;
            case DateTimeKind.dateTime:
                return dateTime.dayOfWeek;
            case DateTimeKind.time:
                return firstDayOfWeek;
        }
    }

    @property DateTimeKind kind() const @nogc pure
    {
        return _kind;
    }

    @property int hour() const @nogc pure
    {
        return _hour;
    }

    @property int julianDay() const @nogc pure
    {
        final switch (kind)
        {
            case DateTimeKind.date:
                return cast(int)Tick.round(date.julianDay);
            case DateTimeKind.dateTime:
                return cast(int)Tick.round(dateTime.julianDay);
            case DateTimeKind.time:
                return cast(int)Tick.round(time.julianDay);
        }
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

    @property ZoneOffset utcBias() const @nogc pure
    {
        return _utcBias;
    }

private:
    union
    {
        Date date;
        DateTime dateTime;
        Time time;
    }
    int _year, _month, _day, _hour, _minute, _second, _millisecond, _tick;
    ZoneOffset _utcBias;
    DateTimeKind _kind;
}

enum FormatWriteResult : ubyte
{
    ok,
    done,
    error,
}

struct FormatDateTimeSpec(Char)
if (is(Unqual!Char == Char))
{
@safe:

public:
    const(Char)[] trailing; /// contains the rest of the format string.
    Char spec = 0; /// The actual/current format specifier
    const(Char)[] customTrailing; /// contains custom format string
    Char customSpec = 0;
    ubyte customSpecCount;
    string errorMessage;

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
    FormatWriteResult writeUpToNextSpec(Writer)(scope ref Writer sink) nothrow pure scope
    {
        if (trailing.length == 0)
            return FormatWriteResult.done;

        size_t i = 0;
        for (; i < trailing.length; ++i)
        {
            if (trailing[i] != '%')
                continue;

            if (i)
            {
                put(sink, trailing[0..i]);
                trailing = trailing[i..$];
            }
            // at least '%' and spec-char
            if (trailing.length <= 1)
                return errorWriteUp("Unterminated format specifier: " ~ toString(trailing));
            trailing = trailing[1..$]; // Skip '%'

            // Spec found. Fill up the spec and bailout
            if (trailing[0] != '%')
                return fillWriteUpToNextSpec();

            // Reset and keep going
            i = 0;
        }

        // no format spec found
        put(sink, trailing);
        trailing = null;
        return FormatWriteResult.done;
    }

    FormatWriteResult writeUpToNextCustomSpec(Writer)(scope ref Writer sink) nothrow pure scope
    {
        if (customTrailing.length == 0)
            return FormatWriteResult.done;

        size_t i = 0;
        for (; i < customTrailing.length; ++i)
        {
            const c = customTrailing[i];
            if (c != '%' && !isCustomModifierChar(c))
                continue;

            if (i)
            {
                put(sink, customTrailing[0..i]);
                customTrailing = customTrailing[i..$];
            }

            if (customTrailing.length == 0 || (customTrailing.length == 1 && customTrailing[0] == '%'))
                return errorWriteUp("Unterminated custom format specifier: " ~ toString(customTrailing));

            // Skip '%'?
            if (customTrailing[0] == '%')
                customTrailing = customTrailing[1..$];

            // Spec found. Fill up the spec and bailout
            if (customTrailing[0] != '%')
                return fillWriteUpToNextCustomSpec();

            // Reset and keep going
            i = 0;
        }

        // no format spec found
        put(sink, customTrailing);
        customTrailing = null;
        return FormatWriteResult.done;
    }

    static bool isCustomModifierChar(const(Char) c) @nogc nothrow pure
    {
        return c == FormatDateTimeSpecifier.customAmPm
            || c == FormatDateTimeSpecifier.customDay
            || c == FormatDateTimeSpecifier.customFraction
            || c == FormatDateTimeSpecifier.customLongHour
            || c == FormatDateTimeSpecifier.customShortHour
            || c == FormatDateTimeSpecifier.customMinute
            || c == FormatDateTimeSpecifier.customMonth
            || c == FormatDateTimeSpecifier.customSecond
            || c == FormatDateTimeSpecifier.customSeparatorDate
            || c == FormatDateTimeSpecifier.customSeparatorTime
            || c == FormatDateTimeSpecifier.customYear;
    }

private:
    FormatWriteResult errorWriteUp(string errorMessage) nothrow pure
    {
        this.errorMessage = errorMessage;
        return FormatWriteResult.error;
    }

    FormatWriteResult fillWriteUpToNextSpec() nothrow pure
    {
        customTrailing = null;
        customSpec = 0;
        customSpecCount = 0;
        spec = trailing[0];
        trailing = trailing[1..$];

        switch (spec)
        {
            case FormatDateTimeSpecifier.custom:
                if (trailing.length == 0)
                    return errorWriteUp("Missing custom format modifier");
                return fillWriteUpToNextSpecCustom();
            case FormatDateTimeSpecifier.generalShortDateTime:
            case FormatDateTimeSpecifier.generalLongDateTime:
            case FormatDateTimeSpecifier.julianDay:
            case FormatDateTimeSpecifier.longDate:
            case FormatDateTimeSpecifier.longDateTime:
            case FormatDateTimeSpecifier.longTime:
            case FormatDateTimeSpecifier.monthDay:
            case FormatDateTimeSpecifier.monthYear:
            case FormatDateTimeSpecifier.shortDate:
            case FormatDateTimeSpecifier.shortDateTime:
            case FormatDateTimeSpecifier.shortTime:
            case FormatDateTimeSpecifier.sortableDateTime:
            case FormatDateTimeSpecifier.sortableDateTimeLess:
            case FormatDateTimeSpecifier.utcSortableDateTime:
            case FormatDateTimeSpecifier.utcSortableDateTimeZ:
                return FormatWriteResult.ok;
            default:
                return errorWriteUp("Incorrect format specifier: " ~ toString(spec));
        }
    }

    FormatWriteResult fillWriteUpToNextSpecCustom() nothrow pure
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
        if (i == 0 || found == 0)
            return errorWriteUp("Missing custom format modifier: " ~ toString(trailing));
        customTrailing = trailing[0..i];
        trailing = trailing[i..$];
        return FormatWriteResult.ok;
    }

    FormatWriteResult fillWriteUpToNextCustomSpec() nothrow pure
    {
        size_t limit = 0;
        customSpecCount = 0;
        customSpec = customTrailing[0];
        switch (customSpec)
        {
            case FormatDateTimeSpecifier.customAmPm:
                limit = 1;
                break;
            case FormatDateTimeSpecifier.customDay:
                limit = 3;
                break;
            case FormatDateTimeSpecifier.customFraction: // time fraction, 1..3=msec, 4..7=usec
                limit = Tick.ticksMaxPrecision; // 999 * 10_000 (ticksPerMillisecond) or 9_999_999 (precision);
                break;
            case FormatDateTimeSpecifier.customLongHour:
            case FormatDateTimeSpecifier.customShortHour:
            case FormatDateTimeSpecifier.customMinute:
                limit = 2;
                break;
            case FormatDateTimeSpecifier.customMonth:
                limit = 3;
                break;
            case FormatDateTimeSpecifier.customSecond:
                limit = 2;
                break;
            case FormatDateTimeSpecifier.customSeparatorDate:
            case FormatDateTimeSpecifier.customSeparatorTime:
                limit = 1;
                break;
            case FormatDateTimeSpecifier.customYear:
                limit = 4;
                break;
            default:
                assert(0);
        }

        size_t count;
        for (size_t i = 0; i < customTrailing.length && customSpec == customTrailing[i]; i++)
            count++;
        if (count > limit)
            return errorWriteUp("Invalid custom format modifier: " ~ toString(customTrailing[0..count]));

        customSpecCount = cast(ubyte)count;
        customTrailing = customTrailing[count..$];
        return FormatWriteResult.ok;
    }

    static string toString(const(Char) c) nothrow pure
    {
        import std.conv : to;
        scope (failure) assert(0, "Assume nothrow failed");

        return c != 0 ? c.to!string() : null;
    }

    static string toString(const(Char)[] c) nothrow pure
    {
        import std.conv : to;
        scope (failure) assert(0, "Assume nothrow failed");

        return c.length != 0 ? c.to!string() : null;
    }
}

enum formatedWriteError = uint.max;

uint formattedWrite(Writer, Char)(scope auto ref Writer sink, scope ref FormatDateTimeSpec!Char fmtSpec,
    scope auto ref FormatDateTimeValue fmtValue) nothrow
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    auto setting = dateTimeSetting; // Use local var from a thread var for faster use
    return formattedWrite(sink, fmtSpec, fmtValue, setting);
}

uint formattedWrite(Writer, Char)(scope auto ref Writer sink, scope ref FormatDateTimeSpec!Char fmtSpec,
    scope auto ref FormatDateTimeValue fmtValue, scope auto ref DateTimeSetting setting) nothrow
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    import std.math.algebraic : abs;
    import pham.utl.utl_convert : putNumber;

    void putAMorPM(bool space) nothrow @safe
    {
        auto s = fmtValue.amPM(setting);
        if (s.length)
        {
            if (space)
                put(sink, ' ');
            put(sink, s[]);
        }
    }

    FormatWriteResult putCustom(const(bool) useShort) nothrow @safe
    {
        FormatWriteResult wr = fmtSpec.writeUpToNextCustomSpec(sink);
        while (wr == FormatWriteResult.ok)
        {
            switch (fmtSpec.customSpec)
            {
                case FormatDateTimeSpecifier.customAmPm:
                    putAMorPM(false);
                    break;
                case FormatDateTimeSpecifier.customDay:
                    if (fmtSpec.customSpecCount == 3)
                        put(sink, fmtValue.dayOfWeekName(setting, useShort));
                    else
                        putNumber(sink, fmtValue.day, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customFraction: // time fraction, 1..3=msec, 4..7=usec
                    if (fmtSpec.customSpecCount <= Tick.millisMaxPrecision)
                        putNumber(sink, fmtValue.millisecond, fmtSpec.customSpecCount);
                    else
                        putNumber(sink, fmtValue.tick, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customLongHour:
                    putNumber(sink, fmtValue.hour, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customShortHour:
                    putNumber(sink, fmtValue.shortHour, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customMinute:
                    putNumber(sink, fmtValue.minute, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customMonth:
                    if (fmtSpec.customSpecCount == 3)
                        put(sink, fmtValue.monthName(setting, useShort));
                    else
                        putNumber(sink, fmtValue.month, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customSecond:
                    putNumber(sink, fmtValue.second, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customSeparatorDate:
                    put(sink, setting.dateSeparator);
                    break;
                case FormatDateTimeSpecifier.customSeparatorTime:
                    put(sink, setting.timeSeparator);
                    break;
                case FormatDateTimeSpecifier.customYear:
                    if (fmtSpec.customSpecCount <= 2)
                        putNumber(sink, fmtValue.shortYear, fmtSpec.customSpecCount);
                    else
                        putNumber(sink, fmtValue.year, fmtSpec.customSpecCount);
                    break;
                default:
                    assert(0);
            }
            wr = fmtSpec.writeUpToNextCustomSpec(sink);
        }
        return wr;
    }

    FormatWriteResult putCustomFor(string customFormat, const(bool) useShort) nothrow @safe
    {
        fmtSpec.customSpec = 0;
        fmtSpec.customSpecCount = 0;
        fmtSpec.customTrailing = customFormat;
        return putCustom(useShort);
    }

    version(none)
    void putFullDateTime() nothrow @safe
    {
        put(sink, fmtValue.dayOfWeekName(setting, false));
        put(sink, ", ");
        put(sink, fmtValue.monthName(setting, false));
        put(sink, ' ');
        putNumber(sink, fmtValue.day);
        put(sink, ", ");
        putNumber(sink, fmtValue.year, 4);
        put(sink, ' ');
        toString(sink, fmtValue.shortHour);
        put(sink, setting.timeSeparator);
        putNumber(sink, fmtValue.minute, 2);
    }

    version(none)
    void putGeneralDateTime() nothrow @safe
    {
        putNumber(sink, fmtValue.month);
        put(sink, setting.dateSeparator);
        putNumber(sink, fmtValue.day);
        put(sink, setting.dateSeparator);
        putNumber(sink, fmtValue.year, 4);
        put(sink, ' ');
        putNumber(sink, fmtValue.shortHour);
        put(sink, setting.timeSeparator);
        putNumber(sink, fmtValue.minute, 2);
    }

    version(none)
    void putTime() nothrow @safe
    {
        putNumber(sink, fmtValue.shortHour);
        put(sink, setting.timeSeparator);
        putNumber(sink, fmtValue.minute, 2);
    }

    uint result = 0;
    FormatWriteResult wr = fmtSpec.writeUpToNextSpec(sink);
    while (wr == FormatWriteResult.ok)
    {
        switch (fmtSpec.spec)
        {
            case FormatDateTimeSpecifier.custom:
                if (putCustom(false) == FormatWriteResult.error)
                    return formatedWriteError;
                break;
            case FormatDateTimeSpecifier.generalShortDateTime:
                auto fmt = fmtValue.kind == DateTimeKind.date
                            ? setting.generalShortFormat.date
                            : (fmtValue.kind == DateTimeKind.dateTime
                                ? setting.generalShortFormat.dateTime
                                : setting.generalShortFormat.time);
                if (putCustomFor(fmt, true) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
                    putGeneralDateTime();
                    putAMorPM(true);
                }
                break;
            case FormatDateTimeSpecifier.generalLongDateTime:
                auto fmt = fmtValue.kind == DateTimeKind.date
                            ? setting.generalLongFormat.date
                            : (fmtValue.kind == DateTimeKind.dateTime
                                ? setting.generalLongFormat.dateTime
                                : setting.generalLongFormat.time);
                if (putCustomFor(fmt, false) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
                    putGeneralDateTime();
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                    putAMorPM(true);
                }
                break;
            case FormatDateTimeSpecifier.julianDay:
                putNumber(sink, fmtValue.julianDay);
                break;
            case FormatDateTimeSpecifier.longDate:
                if (putCustomFor(setting.longFormat.date, false) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:45:30 -> Monday, June 15, 2009
                    put(sink, fmtValue.dayOfWeekName(setting, false));
                    put(sink, ", ");
                    put(sink, fmtValue.monthName(setting, false));
                    put(sink, ' ');
                    putNumber(sink, fmtValue.day);
                    put(sink, ", ");
                    putNumber(sink, fmtValue.year, 4);
                }
                break;
            case FormatDateTimeSpecifier.longDateTime:
                if (putCustomFor(setting.longFormat.dateTime, false) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
                    putFullDateTime();
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                    putAMorPM(true);
                }
                break;
            case FormatDateTimeSpecifier.longTime:
                if (putCustomFor(setting.longFormat.time, false) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:45:30 -> 1:45:30 PM
                    putTime();
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                    putAMorPM(true);
                }
                break;
            case FormatDateTimeSpecifier.monthDay: // 2009-06-15T13:45:30 -> June 15
                put(sink, fmtValue.monthName(setting, false));
                put(sink, ' ');
                putNumber(sink, fmtValue.day);
                break;
            case FormatDateTimeSpecifier.monthYear: // 2009-06-15T13:45:30 -> June 2009
                put(sink, fmtValue.monthName(setting, false));
                put(sink, ' ');
                putNumber(sink, fmtValue.year, 4);
                break;
            case FormatDateTimeSpecifier.shortDate:
                if (putCustomFor(setting.shortFormat.date, true) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:45:30 -> 6/15/2009
                    putNumber(sink, fmtValue.month);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.day);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.year, 4);
                }
                break;
            case FormatDateTimeSpecifier.shortDateTime:
                if (putCustomFor(setting.shortFormat.dateTime, true) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01 PM
                    putFullDateTime();
                    putAMorPM(true);
                }
                break;
            case FormatDateTimeSpecifier.shortTime:
                if (putCustomFor(setting.shortFormat.time, true) == FormatWriteResult.error)
                    return formatedWriteError;
                version(none)
                {
                    // 2009-06-15T13:45:30 -> 1:45 PM
                    putTime();
                    putAMorPM(true);
                }
                break;
            case FormatDateTimeSpecifier.sortableDateTime: // 2009-06-15T13:45:30.0000001 -> 2009-06-15T13:45:30.0000001
                // Date part
                if (fmtValue.kind != DateTimeKind.time)
                {
                    putNumber(sink, fmtValue.year, 4);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.month, 2);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.day, 2);

                    // Has time?
                    if (fmtValue.kind != DateTimeKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != DateTimeKind.date)
                {
                    putNumber(sink, fmtValue.hour, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.minute, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                    put(sink, '.');
                    putNumber(sink, fmtValue.tick, Tick.ticksMaxPrecision);
                }
                break;
            case FormatDateTimeSpecifier.sortableDateTimeLess: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30
                // Date part
                if (fmtValue.kind != DateTimeKind.time)
                {
                    putNumber(sink, fmtValue.year, 4);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.month, 2);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.day, 2);

                    // Has time?
                    if (fmtValue.kind != DateTimeKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != DateTimeKind.date)
                {
                    putNumber(sink, fmtValue.hour, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.minute, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                }
                break;
            case FormatDateTimeSpecifier.utcSortableDateTime: // 2009-06-15T13:45:30.0000001 -> 2009-06-15T13:45:30.0000001Z
                // Date part
                if (fmtValue.kind != DateTimeKind.time)
                {
                    putNumber(sink, fmtValue.year, 4);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.month, 2);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.day, 2);

                    // Has time?
                    if (fmtValue.kind != DateTimeKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != DateTimeKind.date)
                {
                    putNumber(sink, fmtValue.hour, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.minute, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                    put(sink, '.');
                    putNumber(sink, fmtValue.tick, Tick.ticksMaxPrecision);
                    put(sink, 'Z');
                }
                break;
            case FormatDateTimeSpecifier.utcSortableDateTimeZ: // 2009-06-15T13:45:30.0000001 -> 2009-06-15T13:45:30.0000001+HH:NN
                // Date part
                if (fmtValue.kind != DateTimeKind.time)
                {
                    putNumber(sink, fmtValue.year, 4);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.month, 2);
                    put(sink, setting.dateSeparator);
                    putNumber(sink, fmtValue.day, 2);

                    // Has time?
                    if (fmtValue.kind != DateTimeKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != DateTimeKind.date)
                {
                    putNumber(sink, fmtValue.hour, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.minute, 2);
                    put(sink, setting.timeSeparator);
                    putNumber(sink, fmtValue.second, 2);
                    put(sink, '.');
                    putNumber(sink, fmtValue.tick, Tick.ticksMaxPrecision);
                    fmtValue.utcBias.toString(sink);
                }
                break;
            default:
                assert(0);
        }
        result++;
        wr = fmtSpec.writeUpToNextSpec(sink);
    }

    return wr != FormatWriteResult.error ? result : formatedWriteError;
}

version(none)
void pad(Writer, Char)(scope auto ref Writer sink, scope const(Char)[] value, ptrdiff_t size, Char c) nothrow pure
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    import std.math : abs;

    auto n = abs(size);
    if (value.length >= n)
        put(sink, value);
    else
    {
        // Leading pad?
        if (size > 0)
        {
            n -= value.length;
            while (n--)
                put(sink, c);
            put(sink, value);
        }
        else
        {
            put(sink, value);
            n -= value.length;
            while (n--)
                put(sink, c);
        }
    }
}


private:

@safe unittest // FormatDateTimeSpecifier.shortDateTime, longDateTime - %f %F
{
    string s;

    s = DateTime(2009, 06, 15, 12, 1, 30).toString("%f");
    assert(s == "6/15/2009 12:01 PM", s);
    s = DateTime(2009, 06, 15, 13, 1, 30).toString("%F");
    assert(s == "Monday, June 15, 2009 1:01:30 PM", s);
}

@safe unittest // FormatDateTimeSpecifier.generalShortDateTime, generalLongDateTime - %g %G
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%g");
    assert(s == "6/15/2009 1:45 PM", s);

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%G");
    assert(s == "06/15/2009 1:45:30 PM", s);
}

@safe unittest // FormatDateTimeSpecifier.julianDay - %j
{
    string s;

    s = DateTime(2010, 8, 24, 0, 0, 0).toString("%j");
    assert(s == "2455433", s);

    s = DateTime(2010, 8, 24, 11, 59, 59).toString("%j");
    assert(s == "2455433", s);

    s = DateTime(2010, 8, 24, 12, 0, 0).toString("%j");
    assert(s == "2455433", s);

    s = DateTime(2010, 8, 24, 13, 0, 0).toString("%j");
    assert(s == "2455433", s);

    s = Date(2010, 8, 24).toString("%j");
    assert(s == "2455433", s);

    s = Time(11, 59, 59).toString("%j");
    assert(s == "1721424", s);

    s = Time(12, 0, 0).toString("%j");
    assert(s == "1721424", s);
}

@safe unittest // FormatDateTimeSpecifier.longDate, shortDate - %d %D
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%D");
    assert(s == "Monday, June 15, 2009", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%d");
    assert(s == "6/15/2009", s);

    s = Date(2009, 06, 15).toString("%D");
    assert(s == "Monday, June 15, 2009", s);
    s = Date(2009, 06, 15).toString("%d");
    assert(s == "6/15/2009");

    DateTimeSetting setting = DateTimeSetting.us;
    setting.dateSeparator = '-';
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%d", setting);
    assert(s == "6-15-2009", s);
    s = Date(2009, 06, 15).toString("%d", setting);
    assert(s == "6-15-2009");
}

@safe unittest // FormatDateTimeSpecifier.longTime, shortTime - %t %T
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%T");
    assert(s == "1:45:30 PM", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%t");
    assert(s == "1:45 PM", s);

    s = Time(13, 45, 30).toString("%T");
    assert(s == "1:45:30 PM", s);
    s = Time(13, 45, 30).toString("%t");
    assert(s == "1:45 PM", s);
}

@safe unittest // FormatDateTimeSpecifier.monthDay, monthYear - %M %Y
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%M");
    assert(s == "June 15", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%Y");
    assert(s == "June 2009");
}

@safe unittest // FormatDateTimeSpecifier.sortableDateTime - %s
{
    string s;

    // Date
    s = Date(2009, 06, 15).toString("%s");
    assert(s == "2009/06/15", s);

    // DateTime
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%s");
    assert(s == "2009/06/15T13:45:30.0000000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%s");
    assert(s == "2009/06/15T13:45:30.0000000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%s");
    assert(s == "2009/06/15T13:45:30.0000001", s);

    // Time
    s = Time(13, 45, 30).toString("%s");
    assert(s == "13:45:30.0000000", s);

    auto setting = DateTimeSetting.iso8601;
    s = Date(2009, 06, 15).toString("%s", setting);
    assert(s == "2009-06-15", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%s", setting);
    assert(s == "2009-06-15T13:45:30.0000001", s);
    s = Time(13, 45, 30).toString("%s", setting);
    assert(s == "13:45:30.0000000", s);
}

@safe unittest // FormatDateTimeSpecifier.sortableDateTimeLess - %S
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%S");
    assert(s == "2009/06/15T13:45:30", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%S");
    assert(s == "2009/06/15T13:45:30", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%S");
    assert(s == "2009/06/15T13:45:30", s);

    auto setting = DateTimeSetting.iso8601;
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%S", setting);
    assert(s == "2009-06-15T13:45:30", s);
}

@safe unittest // FormatDateTimeSpecifier.utcSortableDateTime - %u
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%u");
    assert(s == "2009/06/15T13:45:30.0000001Z", s);

    auto setting = DateTimeSetting.iso8601Utc;
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%u", setting);
    assert(s == "2009-06-15T13:45:30.0000001Z", s);
}

@safe unittest // FormatDateTimeSpecifier.utcSortableDateTimeZ - %U
{
    DateTime d;
    string s, expected;

    d = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1);
    s = d.toString("%U");
    expected = "2009/06/15T13:45:30.0000001" ~ d.utcBias.toString();
    assert(s == expected, s ~ " vs " ~ expected);

    d = DateTime(2009, 06, 15, 13, 45, 30, DateTimeZoneKind.utc).addTicks(1);
    s = d.toString("%U");
    expected = "2009/06/15T13:45:30.0000001+00:00";
    assert(s == expected, s ~ " vs " ~ expected);

    auto setting = DateTimeSetting.iso8601Utc;
    d = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1);
    s = d.toString("%U", setting);
    expected = "2009-06-15T13:45:30.0000001" ~ d.utcBias.toString();
    assert(s == expected, s ~ " vs " ~ expected);
}

@safe unittest // FormatDateTimeSpecifier.custom, FormatDateTimeSpecifier.dateSeparator, FormatDateTimeSpecifier.timeSeparator - %custom....
{
    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%cmm/dd/yyyy HH:nn:ss");
    assert(s == "06/15/2009 13:45:30", s);
    s = DateTime(2009, 06, 15, 3, 45, 30).toString("%cm/dd/yyyy H:nn:ss");
    assert(s == "6/15/2009 3:45:30", s);
    s = DateTime(2009, 06, 15, 3, 45, 30).toString("%cm/dd/yy H:nn:ss");
    assert(s == "6/15/09 3:45:30", s);

    s = Date(2009, 06, 15).toString("%cdd/mm/yyyy");
    assert(s == "15/06/2009", s);
    s = Date(2009, 06, 15).toString("%cdd/mm/yy");
    assert(s == "15/06/09", s);

    s = Date(2009, 06, 1).toString("%cmmm d, yyyy");
    assert(s == "June 1, 2009", s);

    s = Date(2009, 06, 1).toString("%cddd, mmm d, yyyy");
    assert(s == "Monday, June 1, 2009", s);

    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%cyyyymmdd HHnnsszzz");
    assert(s == "20090615 134530000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%cyyyymmdd HHnnsszzzzzzz");
    assert(s == "20090615 1345300000001", s);

    s = Time(13, 45, 30).toString("%cH:n:s");
    assert(s == "13:45:30", s);

    s = Time(1, 45, 30).toString("%cHH:n:s");
    assert(s == "01:45:30", s);

    s = Time(13, 45, 30).toString("%ch:n:s");
    assert(s == "1:45:30", s);

    s = Time(13, 45, 30).toString("%chh:n:s");
    assert(s == "01:45:30", s);

    // Escape % weird character format
    s = Date(2009, 06, 15).toString("%cdd-%%?mm'%%-yyyy");
    assert(s == "15-%?06'%-2009", s);
}
