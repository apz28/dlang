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

module pham.utl.datetime.date_time_format;

public import std.format : FormatException;
import std.range.primitives : isOutputRange, put;
import std.traits : isSomeChar, isSomeString, Unqual;

import pham.utl.object : toString;
import pham.utl.datetime.tick;
import pham.utl.datetime.date : Date, DateTime, DayOfWeek, firstDayOfMonth, firstDayOfWeek;
import pham.utl.datetime.time : Time;

@safe:

enum FormatDateTimeSpecifier : char
{
    custom = 'c', /// Custom specifier `%c` - %cmm/dd/yyyy hh:nn:ss.zzz - 2009-06-01T01:02:03.4 -> 06/01/2009 01:02:03.004
    customAmPm = CustomFormatSpecifier.amPm, /// Time part indicator AM or PM - %ca - 2009-06-15T13:45:30 -> PM
    customDay = CustomFormatSpecifier.day, /// Custom day part - %cd, %cdd, %cddd - 2009-06-01T01:02:03 -> 1, 01, Saturday
    customFraction = CustomFormatSpecifier.fraction, /// Custom fraction of second part - %cz, %czzz, %czzzzzzz - 2009-06-01T01:02:03.4 -> 4, 004, 0040000
    customHour = CustomFormatSpecifier.hour, /// Custom hour part - %ch, %chh - 2009-06-01T01:02:03 -> 1, 01
    customMinute = CustomFormatSpecifier.minute, /// Custom minute part - %cn, %cnn - 2009-06-01T01:02:03 -> 2, 02
    customMonth = CustomFormatSpecifier.month, /// Custom month part - %cm, %cmm, %cmmm - 2009-06-01T01:02:03 -> 6, 06, June
    customSecond = CustomFormatSpecifier.second, /// Custom second part - %cs, %css - 2009-06-01T01:02:03 -> 3, 03
    customSeparatorDate = CustomFormatSpecifier.separatorDate, /// Date part separator
    customSeparatorTime = CustomFormatSpecifier.separatorTime, /// Time part separator
    customYear = CustomFormatSpecifier.year, /// Custom year part - %cyy, %cyyyy - 2009-06-01T01:02:03 -> 09, 2009
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
    sortableDateTime = 's', /// %s 2009-06-15T13:45:30.0010000 -> 2009-06-15T13:45:30.0010000
    sortableDateTimeLess = 'S', /// %S 2009-06-15T13:45:30.0010000 -> 2009-06-15T13:45:30
    utcFullDateTime = 'U', /// %U 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
    utcSortableDateTime = 'u', /// %u 2009-06-15T13:45:30.0000001 -> 2009-06-15 13:45:30.0000001Z
}

struct FormatDateTimeValue
{
nothrow @safe:

public:
    enum ValueKind : byte
    {
        date,
        dateTime,
        time,
    }

public:
    this(in Date date) @nogc pure
    {
        this._kind = ValueKind.date;
        this.date = date;
        date.getDate(_year, _month, _day);
    }

    this(in DateTime dateTime) @nogc pure
    {
        this._kind = ValueKind.dateTime;
        this.dateTime = dateTime;
        dateTime.getDate(_year, _month, _day);
        dateTime.getTimePrecise(_hour, _minute, _second, _tick);
        this._millisecond = TickPart.tickToMillisecond(_tick);
    }

    this(in Time time) @nogc pure
    {
        this._kind = ValueKind.time;
        this.time = time;
        time.getTimePrecise(_hour, _minute, _second, _tick);
        this._millisecond = TickPart.tickToMillisecond(_tick);
    }

    string amPM(scope const ref DateTimeSetting setting) const pure
    {
        return kind != ValueKind.date && setting.amPmTexts !is null
            ? (*setting.amPmTexts)[hour >= 12]
            : null;
    }

    string dayOfWeekName(scope const ref DateTimeSetting setting) const pure
    {
        return kind != ValueKind.time
            ? (*setting.dayOfWeekNames)[dayOfWeek - firstDayOfWeek]
            : null;
    }

    string monthName(scope const ref DateTimeSetting setting) const pure
    {
        return kind != ValueKind.time
            ? (*setting.monthNames)[month - firstDayOfMonth]
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
            case ValueKind.date:
                return date.dayOfWeek;
            case ValueKind.dateTime:
                return dateTime.dayOfWeek;
            case ValueKind.time:
                return firstDayOfWeek;
        }
    }

    @property ValueKind kind() const @nogc pure
    {
        return _kind;
    }

    @property int hour() const @nogc pure
    {
        return _hour;
    }

    @property uint julianDay() const @nogc pure
    {
        final switch (kind)
        {
            case ValueKind.date:
                return date.julianDay;
            case ValueKind.dateTime:
                return dateTime.julianDay;
            case ValueKind.time:
                return time.julianDay;
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

private:
    union
    {
        Date date;
        DateTime dateTime;
        Time time;
    }
    int _year, _month, _day, _hour, _minute, _second, _millisecond, _tick;
    ValueKind _kind;
}

enum FormatWriteResult : byte
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
            || c == FormatDateTimeSpecifier.customHour
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
        customSpecCount = 0;
        customSpec = 0;
        spec = trailing[0];
        trailing = trailing[1..$];

        switch (spec)
        {
            case FormatDateTimeSpecifier.custom:
                if (trailing.length == 0)
                    return errorWriteUp("Missing custom format modifier");
                return fillWriteUpToNextSpecCustom();
            case FormatDateTimeSpecifier.fullShortDateTime:
            case FormatDateTimeSpecifier.fullLongDateTime:
            case FormatDateTimeSpecifier.generalShortDateTime:
            case FormatDateTimeSpecifier.generalLongDateTime:
            case FormatDateTimeSpecifier.julianDay:
            case FormatDateTimeSpecifier.longDate:
            case FormatDateTimeSpecifier.longTime:
            case FormatDateTimeSpecifier.monthDay:
            case FormatDateTimeSpecifier.monthYear:
            case FormatDateTimeSpecifier.shortDate:
            case FormatDateTimeSpecifier.shortTime:
            case FormatDateTimeSpecifier.sortableDateTime:
            case FormatDateTimeSpecifier.sortableDateTimeLess:
            case FormatDateTimeSpecifier.utcFullDateTime:
            case FormatDateTimeSpecifier.utcSortableDateTime:
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
            case FormatDateTimeSpecifier.customHour:
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
        scope (failure) assert(0);

        return c != 0 ? to!string(c) : null;
    }

    static string toString(const(Char)[] c) nothrow pure
    {
        import std.conv : to;
        scope (failure) assert(0);

        return c.length != 0 ? to!string(c) : null;
    }
}

enum formatedWriteError = uint.max;

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope ref FormatDateTimeSpec!Char fmtSpec,
    scope ref FormatDateTimeValue fmtValue, scope const ref DateTimeSetting setting) nothrow
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    void putAMorPM() nothrow @safe
    {
        auto s = fmtValue.amPM(setting);
        if (s.length)
        {
            put(sink, ' ');
            put(sink, s[]);
        }
    }

    FormatWriteResult putCustom() nothrow @safe
    {
        FormatWriteResult wr = fmtSpec.writeUpToNextCustomSpec(sink);
        while (wr == FormatWriteResult.ok)
        {
            switch (fmtSpec.customSpec)
            {
                case FormatDateTimeSpecifier.customAmPm:
                    putAMorPM();
                    break;
                case FormatDateTimeSpecifier.customDay:
                    if (fmtSpec.customSpecCount == 3)
                        put(sink, fmtValue.dayOfWeekName(setting));
                    else
                        toString(sink, fmtValue.day, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customFraction: // time fraction, 1..3=msec, 4..7=usec
                    if (fmtSpec.customSpecCount <= Tick.millisMaxPrecision)
                        toString(sink, fmtValue.millisecond, fmtSpec.customSpecCount);
                    else
                        toString(sink, fmtValue.tick, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customHour:
                    toString(sink, fmtValue.hour, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customMinute:
                    toString(sink, fmtValue.minute, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customMonth:
                    if (fmtSpec.customSpecCount == 3)
                        put(sink, fmtValue.monthName(setting));
                    else
                        toString(sink, fmtValue.month, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customSecond:
                    toString(sink, fmtValue.second, fmtSpec.customSpecCount);
                    break;
                case FormatDateTimeSpecifier.customSeparatorDate:
                    put(sink, setting.dateSeparator);
                    break;
                case FormatDateTimeSpecifier.customSeparatorTime:
                    put(sink, setting.timeSeparator);
                    break;
                case FormatDateTimeSpecifier.customYear:
                    if (fmtSpec.customSpecCount <= 2)
                        toString(sink, fmtValue.shortYear, fmtSpec.customSpecCount);
                    else
                        toString(sink, fmtValue.year, fmtSpec.customSpecCount);
                    break;
                default:
                    assert(0);
            }
            wr = fmtSpec.writeUpToNextCustomSpec(sink);
        }
        return wr;
    }

    void putFullDateTime() nothrow @safe
    {
        put(sink, fmtValue.dayOfWeekName(setting));
        put(sink, ", ");
        put(sink, fmtValue.monthName(setting));
        put(sink, ' ');
        toString(sink, fmtValue.day);
        put(sink, ", ");
        toString(sink, fmtValue.year, 4);
        put(sink, ' ');
        toString(sink, fmtValue.shortHour);
        put(sink, setting.timeSeparator);
        toString(sink, fmtValue.minute, 2);
    }

    void putGeneralDateTime() nothrow @safe
    {
        toString(sink, fmtValue.month);
        put(sink, setting.dateSeparator);
        toString(sink, fmtValue.day);
        put(sink, setting.dateSeparator);
        toString(sink, fmtValue.year, 4);
        put(sink, ' ');
        toString(sink, fmtValue.shortHour);
        put(sink, setting.timeSeparator);
        toString(sink, fmtValue.minute, 2);
    }

    void putTime() nothrow @safe
    {
        toString(sink, fmtValue.shortHour);
        put(sink, setting.timeSeparator);
        toString(sink, fmtValue.minute, 2);
    }

    uint result = 0;
    FormatWriteResult wr = fmtSpec.writeUpToNextSpec(sink);
    while (wr == FormatWriteResult.ok)
    {
        switch (fmtSpec.spec)
        {
            case FormatDateTimeSpecifier.custom:
                if (putCustom() == FormatWriteResult.error)
                    return formatedWriteError;
                break;
            case FormatDateTimeSpecifier.fullShortDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01 PM
                putFullDateTime();
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.fullLongDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
                putFullDateTime();
                put(sink, setting.timeSeparator);
                toString(sink, fmtValue.second, 2);
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.generalShortDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
                putGeneralDateTime();
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.generalLongDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
                putGeneralDateTime();
                put(sink, setting.timeSeparator);
                toString(sink, fmtValue.second, 2);
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.julianDay:
                toString(sink, fmtValue.julianDay);
                break;
            case FormatDateTimeSpecifier.longDate: // 2009-06-15T13:45:30 -> Monday, June 15, 2009
                put(sink, fmtValue.dayOfWeekName(setting));
                put(sink, ", ");
                put(sink, fmtValue.monthName(setting));
                put(sink, ' ');
                toString(sink, fmtValue.day);
                put(sink, ", ");
                toString(sink, fmtValue.year, 4);
                break;
            case FormatDateTimeSpecifier.longTime: // 2009-06-15T13:45:30 -> 1:45:30 PM
                putTime();
                put(sink, setting.timeSeparator);
                toString(sink, fmtValue.second, 2);
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.monthDay: // 2009-06-15T13:45:30 -> June 15
                put(sink, fmtValue.monthName(setting));
                put(sink, ' ');
                toString(sink, fmtValue.day);
                break;
            case FormatDateTimeSpecifier.monthYear: // 2009-06-15T13:45:30 -> June 2009
                put(sink, fmtValue.monthName(setting));
                put(sink, ' ');
                toString(sink, fmtValue.year, 4);
                break;
            case FormatDateTimeSpecifier.shortDate: // 2009-06-15T13:45:30 -> 6/15/2009
                toString(sink, fmtValue.month);
                put(sink, setting.dateSeparator);
                toString(sink, fmtValue.day);
                put(sink, setting.dateSeparator);
                toString(sink, fmtValue.year, 4);
                break;
            case FormatDateTimeSpecifier.shortTime: // 2009-06-15T13:45:30 -> 1:45 PM
                putTime();
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.sortableDateTime: // 2009-06-15T13:45:30.0000001 -> 2009-06-15T13:45:30.0000001
                // Date part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.time)
                {
                    toString(sink, fmtValue.year, 4);
                    put(sink, '-');
                    toString(sink, fmtValue.month, 2);
                    put(sink, '-');
                    toString(sink, fmtValue.day, 2);

                    // Has time?
                    if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                {
                    toString(sink, fmtValue.hour, 2);
                    put(sink, ':');
                    toString(sink, fmtValue.minute, 2);
                    put(sink, ':');
                    toString(sink, fmtValue.second, 2);
                    put(sink, '.');
                    toString(sink, fmtValue.tick, Tick.ticksMaxPrecision);
                }
                break;
            case FormatDateTimeSpecifier.sortableDateTimeLess: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30
                // Date part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.time)
                {
                    toString(sink, fmtValue.year, 4);
                    put(sink, '-');
                    toString(sink, fmtValue.month, 2);
                    put(sink, '-');
                    toString(sink, fmtValue.day, 2);

                    // Has time?
                    if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                {
                    toString(sink, fmtValue.hour, 2);
                    put(sink, ':');
                    toString(sink, fmtValue.minute, 2);
                    put(sink, ':');
                    toString(sink, fmtValue.second, 2);
                }
                break;
            case FormatDateTimeSpecifier.utcFullDateTime: // 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
                put(sink, fmtValue.dayOfWeekName(setting));
                put(sink, ", ");
                put(sink, fmtValue.monthName(setting));
                put(sink, ' ');
                toString(sink, fmtValue.day);
                put(sink, ", ");
                toString(sink, fmtValue.year, 4);
                put(sink, ' ');
                toString(sink, fmtValue.shortHour);
                put(sink, ':');
                toString(sink, fmtValue.minute, 2);
                put(sink, ':');
                toString(sink, fmtValue.second, 2);
                putAMorPM();
                break;
            case FormatDateTimeSpecifier.utcSortableDateTime: // 2009-06-15T13:45:30.0000001 -> 2009-06-15 13:45:30.0000001Z
                toString(sink, fmtValue.year, 4);
                put(sink, '-');
                toString(sink, fmtValue.month, 2);
                put(sink, '-');
                toString(sink, fmtValue.day, 2);
                put(sink, ' ');
                toString(sink, fmtValue.hour, 2);
                put(sink, ':');
                toString(sink, fmtValue.minute, 2);
                put(sink, ':');
                toString(sink, fmtValue.second, 2);
                put(sink, '.');
                toString(sink, fmtValue.tick, Tick.ticksMaxPrecision);
                put(sink, 'Z');
                break;
            default:
                assert(0);
        }
        result++;
        wr = fmtSpec.writeUpToNextSpec(sink);
    }

    return wr != FormatWriteResult.error ? result : formatedWriteError;
}

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope ref FormatDateTimeSpec!Char fmtSpec,
    scope ref FormatDateTimeValue fmtValue) nothrow
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    auto setting = dateTimeSetting; // Use local var from a thread var for faster use
    return formattedWrite(sink, fmtSpec, fmtValue, setting);
}

version (none)
void pad(Writer, Char)(auto scope ref Writer sink, scope const(Char)[] value, ptrdiff_t size, Char c) nothrow pure
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

@safe unittest // FormatDateTimeSpecifier.fullShortDateTime, fullLongDateTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %f %F");

    string s;

    s = DateTime(2009, 06, 15, 12, 1, 30).toString("%f");
    assert(s == "Monday, June 15, 2009 12:01 PM", s);
    s = DateTime(2009, 06, 15, 13, 1, 30).toString("%F");
    assert(s == "Monday, June 15, 2009 1:01:30 PM", s);
}

@safe unittest // FormatDateTimeSpecifier.generalShortDateTime, generalLongDateTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %g");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%g");
    assert(s == "6/15/2009 1:45 PM", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%G");
    assert(s == "6/15/2009 1:45:30 PM", s);
}

@safe unittest // FormatDateTimeSpecifier.julianDay
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %j");

    string s;

    s = DateTime(2010, 8, 24, 0, 0, 0).toString("%j");
    assert(s == "734007", s);

    s = DateTime(2010, 8, 24, 11, 59, 59).toString("%j");
    assert(s == "734007", s);

    s = DateTime(2010, 8, 24, 12, 0, 0).toString("%j");
    assert(s == "734008", s);

    s = DateTime(2010, 8, 24, 13, 0, 0).toString("%j");
    assert(s == "734008", s);

    s = Date(2010, 8, 24).toString("%j");
    assert(s == "734007", s);

    s = Time(11, 59, 59).toString("%j");
    assert(s == "0", s);

    s = Time(12, 0, 0).toString("%j");
    assert(s == "1", s);
}

@safe unittest // FormatDateTimeSpecifier.longDate, shortDate
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %d %D");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%D");
    assert(s == "Monday, June 15, 2009", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%d");
    assert(s == "6/15/2009", s);

    s = Date(2009, 06, 15).toString("%D");
    assert(s == "Monday, June 15, 2009", s);
    s = Date(2009, 06, 15).toString("%d");
    assert(s == "6/15/2009");
}

@safe unittest // FormatDateTimeSpecifier.longTime, shortTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %t %T");

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

@safe unittest // FormatDateTimeSpecifier.monthDay, monthYear
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %M %Y");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%M");
    assert(s == "June 15", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%Y");
    assert(s == "June 2009");
}

@safe unittest // FormatDateTimeSpecifier.sortableDateTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %s");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%s");
    assert(s == "2009-06-15T13:45:30.0000000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%s");
    assert(s == "2009-06-15T13:45:30.0000000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%s");
    assert(s == "2009-06-15T13:45:30.0000001", s);

    s = Date(2009, 06, 15).toString("%s");
    assert(s == "2009-06-15", s);

    s = Time(13, 45, 30).toString("%s");
    assert(s == "13:45:30.0000000", s);
}

@safe unittest // FormatDateTimeSpecifier.sortableDateTimeLess
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %S");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%S");
    assert(s == "2009-06-15T13:45:30", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%S");
    assert(s == "2009-06-15T13:45:30", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%S");
    assert(s == "2009-06-15T13:45:30", s);
}

@safe unittest // FormatDateTimeSpecifier.utcFullDateTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %U");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%U");
    assert(s == "Monday, June 15, 2009 1:45:30 PM", s);
}

@safe unittest // FormatDateTimeSpecifier.utcSortableDateTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %u");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%u");
    assert(s == "2009-06-15 13:45:30.0000001Z", s);
}

@safe unittest // FormatDateTimeSpecifier.custom, FormatDateTimeSpecifier.dateSeparator, FormatDateTimeSpecifier.timeSeparator
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.date_time_format - %custom....");

    string s;

    s = DateTime(2009, 06, 15, 13, 45, 30).toString("%cmm/dd/yyyy hh:nn:ss");
    assert(s == "06/15/2009 13:45:30", s);
    s = DateTime(2009, 06, 15, 3, 45, 30).toString("%cm/dd/yyyy h:nn:ss");
    assert(s == "6/15/2009 3:45:30", s);
    s = DateTime(2009, 06, 15, 3, 45, 30).toString("%cm/dd/yy h:nn:ss");
    assert(s == "6/15/09 3:45:30", s);

    s = Date(2009, 06, 15).toString("%cdd/mm/yyyy");
    assert(s == "15/06/2009", s);
    s = Date(2009, 06, 15).toString("%cdd/mm/yy");
    assert(s == "15/06/09", s);

    s = Date(2009, 06, 1).toString("%cmmm d, yyyy");
    assert(s == "June 1, 2009", s);

    s = Date(2009, 06, 1).toString("%cddd, mmm d, yyyy");
    assert(s == "Monday, June 1, 2009", s);

    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%cyyyymmdd hhnnsszzz");
    assert(s == "20090615 134530000", s);
    s = DateTime(2009, 06, 15, 13, 45, 30).addTicks(1).toString("%cyyyymmdd hhnnsszzzzzzz");
    assert(s == "20090615 1345300000001", s);

    s = Time(13, 45, 30).toString("%ch:n:s");
    assert(s == "13:45:30", s);

    // Escape % weird character format
    s = Date(2009, 06, 15).toString("%cdd-%%?mm'%%-yyyy");
    assert(s == "15-%?06'%-2009", s);
}
