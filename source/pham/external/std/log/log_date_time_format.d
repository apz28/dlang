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
import std.array : Appender, appender;
import std.datetime.date : Date, DateTime, DayOfWeek, Month, TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.format : FormatException;
import std.range.primitives : ElementEncodingType, empty, put;
import std.traits : EnumMembers, isIntegral, isSomeChar, isSomeString, Unqual;

@safe:

enum FormatTimeSpecifier : char
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

    enum ValueKind : ubyte
    {
        date,
        dateTime,
        sysTime,
        time,
    }

    this(scope const(Date) date) @nogc pure
    {
        this._kind = ValueKind.date;
        this.initYMD(date);
        this.initHMS(date);
    }

    this(scope const(DateTime) dateTime) @nogc pure
    {
        this._kind = ValueKind.dateTime;
        this.initYMD(dateTime);
        this.initHMS(dateTime);
    }

    this(scope const(SysTime) sysTime) @trusted
    {
        this._kind = ValueKind.sysTime;
        this.initYMD(sysTime);
        this.initHMS(sysTime);
    }

    this(scope const(Time) time) @nogc pure
    {
        this._kind = ValueKind.time;
        this.initYMD(time);
        this.initHMS(time);
    }

    string amPM(scope const(FormatDateTimeContext) context) const @nogc pure
    {
        return kind != ValueKind.date && context.amPmTexts !is null
            ? (*context.amPmTexts)[hour >= 12]
            : null;
    }

    string dayOfWeekName(scope const(FormatDateTimeContext) context) const @nogc pure
    {
        return kind != ValueKind.time
            ? (*context.dayOfWeekNames)[dayOfWeek - firstDayOfWeek]
            : null;
    }

    string monthName(scope const(FormatDateTimeContext) context) const @nogc pure
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
    void initYMD(scope const(Date) date) @nogc pure
    {
        _year = date.year;
        _month = date.month;
        _day = date.day;
        _julianDay = date.julianDay;
        _dayOfWeek = date.dayOfWeek;
    }

    void initYMD(scope const(DateTime) dateTime) @nogc pure
    {
        _year = dateTime.year;
        _month = dateTime.month;
        _day = dateTime.day;
        _julianDay = dateTime.julianDay;
        _dayOfWeek = dateTime.dayOfWeek;
    }

    void initYMD(scope const(SysTime) sysTime) @trusted
    {
        const sd = cast(DateTime)sysTime;
        _year = sd.year;
        _month = sd.month;
        _day = sd.day;
        _julianDay = sysTime.julianDay;
        _dayOfWeek = sysTime.dayOfWeek;
    }

    void initYMD(scope const(Time) time) @nogc pure
    {
        _year = _month = _day = 0;
        _julianDay = time.hour >= 12 ? 1 : 0;
        _dayOfWeek = firstDayOfWeek;
    }

    void initHMS(scope const(Date) date) @nogc pure
    {
        _hour = _minute = _second = _millisecond = 0;
    }

    void initHMS(scope const(DateTime) dateTime) @nogc pure
    {
        _hour = dateTime.hour;
        _minute = dateTime.minute;
        _second = dateTime.second;
        _millisecond = _tick = 0;
    }

    void initHMS(scope const(SysTime) sysTime) @trusted
    {
        const st = cast(TimeOfDay)sysTime;
        const sf = sysTime.fracSecs;
        _hour = st.hour;
        _minute = st.minute;
        _second = st.second;
        _millisecond = cast(int)sf.total!"msecs"(); // Total fracSecs in msecs
        _tick = cast(int)sf.total!"usecs"(); // Total fracSecs in usecs
    }

    void initHMS(scope const(Time) time) @nogc pure
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

struct ShortStringBufferSize(size_t Size, Char)
if (Size > 0 && isSomeChar!Char)
{
@safe:

public:
    this(this) nothrow pure
    {
        _longData = _longData.dup;
    }

    alias opOpAssign(string op : "~") = put;
    alias opDollar = length;

    Char[] opIndex() nothrow pure return
    {
        return _length <= Size ? _shortData[0.._length] : _longData[0.._length];
    }

    ref typeof(this) clear() nothrow pure
    {
        _length = 0;
        return this;
    }

    ref typeof(this) put(Char c) nothrow pure
    {
        if (_length < Size)
            _shortData[_length++] = c;
        else
        {
            if (_length == Size)
                switchToLongData(1);
            else if (_longData.length <= _length)
                _longData.length = _length + overReservedLength;
            _longData[_length++] = c;
        }
        return this;
    }

    ref typeof(this) put(scope const(Char)[] s) nothrow pure
    {
        if (!s.length)
            return this;

        const newLength = _length + s.length;
        assert(newLength < 1024 * 1024 * 4);
        if (newLength <= Size)
        {
            _shortData[_length..newLength] = s[0..$];
        }
        else
        {
            if (_length && _length <= Size)
                switchToLongData(s.length);
            else if (_longData.length < newLength)
                _longData.length = newLength + overReservedLength;
            _longData[_length..newLength] = s[0..$];
        }
        _length = newLength;
        return this;
    }

    immutable(Char)[] toString() const nothrow pure
    {
        return _length != 0
            ? (_length <= Size ? (_shortData[0.._length]).idup : (_longData[0.._length]).idup)
            : null;
    }

    void toString(Writer)(auto scope ref Writer sink) const pure
    {
        if (_length)
        {
            if (_length <= Size)
                sink(_shortData[0.._length]);
            else
                sink(_longData[0.._length]);
        }
    }

    @property bool empty() const @nogc nothrow pure
    {
        return _length == 0;
    }

    @property size_t length() const @nogc nothrow pure
    {
        return _length;
    }

private:
    void switchToLongData(const(size_t) addtionalLength) nothrow pure
    {
        const capacity = _length + addtionalLength + overReservedLength;
        if (_longData.length < capacity)
            _longData.length = capacity;
        _longData[0.._length] = _shortData[0.._length];
    }

private:
    enum overReservedLength = 1_000u;
    size_t _length;
    Char[] _longData;
    Char[Size] _shortData;
}

template ShortStringBuffer(Char)
{
    enum overheadSize = ShortStringBufferSize!(1, Char).sizeof;
    alias ShortStringBuffer = ShortStringBufferSize!(256u - overheadSize, Char);
}

alias enforceFormat = enforce!FormatException;

struct FormatDateTimeSpec(Char)
if (is(Unqual!Char == Char))
{
@safe:

public:
    const(Char)[] trailing; /// contains the rest of the format string.
    const(Char)[] customTrailing; /// contains custom format string
    size_t customSpecCount;
    Char customSpec;
    Char spec = FormatTimeSpecifier.sortableDateTime; /// The actual/current format specifier

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
    bool writeUpToNextSpec(Writer)(scope ref Writer sink) pure scope
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
                put(sink, trailing[0..i]);
                trailing = trailing[i..$];
            }
            // at least '%' and spec-char
            enforceFormat(trailing.length >= 2, "Unterminated format specifier: " ~ to!string(trailing));
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
        put(sink, trailing);
        trailing = null;
        return false;
    }

    bool writeUpToNextCustomSpec(Writer)(scope ref Writer sink) pure scope
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
                put(sink, customTrailing[0..i]);
                customTrailing = customTrailing[i..$];
            }
            enforceFormat((customTrailing.length > 0) || (customTrailing.length > 1 && customTrailing[0] == '%'), "Unterminated custom format specifier");

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
        put(sink, customTrailing);
        customTrailing = null;
        return false;
    }

    static bool isCustomModifierChar(const(Char) c) @nogc nothrow pure
    {
        return c == FormatTimeSpecifier.customAMPM
            || c == FormatTimeSpecifier.customDay
            || c == FormatTimeSpecifier.customFaction
            || c == FormatTimeSpecifier.customHour
            || c == FormatTimeSpecifier.customMinute
            || c == FormatTimeSpecifier.customMonth
            || c == FormatTimeSpecifier.customSecond
            || c == FormatTimeSpecifier.customSeparatorDate
            || c == FormatTimeSpecifier.customSeparatorTime
            || c == FormatTimeSpecifier.customYear;
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
            case FormatTimeSpecifier.custom:
                enforceFormat(trailing.length > 0, "Missing custom format modifier: " ~ to!string(trailing));
                fillWriteUpToNextSpecCustom();
                return;
            case FormatTimeSpecifier.fullShortDateTime:
            case FormatTimeSpecifier.fullLongDateTime:
            case FormatTimeSpecifier.generalShortDateTime:
            case FormatTimeSpecifier.generalLongDateTime:
            case FormatTimeSpecifier.julianDay:
            case FormatTimeSpecifier.longDate:
            case FormatTimeSpecifier.longTime:
            case FormatTimeSpecifier.monthDay:
            case FormatTimeSpecifier.monthYear:
            case FormatTimeSpecifier.shortDate:
            case FormatTimeSpecifier.shortTime:
            case FormatTimeSpecifier.sortableDateTime:
            case FormatTimeSpecifier.sortableDateTimeLess:
            case FormatTimeSpecifier.utcFullDateTime:
            case FormatTimeSpecifier.utcSortableDateTime:
                return;
            default:
                enforceFormat(false, "Incorrect format specifier: " ~ to!string(spec));
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
        enforceFormat(i > 0 && found > 0, "Missing custom format modifier: " ~ to!string(trailing));
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
            case FormatTimeSpecifier.customAMPM:
                limit = 1;
                break;
            case FormatTimeSpecifier.customDay:
                limit = 3;
                break;
            case FormatTimeSpecifier.customFaction: // time fraction, 1..3=msec, 4..6=usec
                limit = 6;
                break;
            case FormatTimeSpecifier.customHour:
            case FormatTimeSpecifier.customMinute:
                limit = 2;
                break;
            case FormatTimeSpecifier.customMonth:
                limit = 3;
                break;
            case FormatTimeSpecifier.customSecond:
                limit = 2;
                break;
            case FormatTimeSpecifier.customSeparatorDate:
            case FormatTimeSpecifier.customSeparatorTime:
                limit = 1;
                break;
            case FormatTimeSpecifier.customYear:
                limit = 4;
                break;
            default:
                assert(0);
        }
        for (size_t i = 0; i < customTrailing.length && customSpec == customTrailing[i]; i++)
            customSpecCount++;
        enforceFormat(customSpecCount <= limit, "Invalid custom format modifier: " ~ to!string(customTrailing[0..customSpecCount]));
        customTrailing = customTrailing[customSpecCount..$];
    }
}

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope ref FormatDateTimeSpec!Char fmtSpec, scope ref FormatDateTimeValue fmtValue)
if (isSomeChar!Char)
{
    const context = threadDateTimeContext;

    void putAMorPM() nothrow @safe
    {
        auto s = fmtValue.amPM(context);
        if (s.length)
        {
            put(sink, ' ');
            put(sink, s[]);
        }
    }

    void putCustom() @safe
    {
        while (fmtSpec.writeUpToNextCustomSpec(sink))
        {
            switch (fmtSpec.customSpec)
            {
                case FormatTimeSpecifier.customAMPM:
                    putAMorPM();
                    break;
                case FormatTimeSpecifier.customDay:
                    if (fmtSpec.customSpecCount == 3)
                        put(sink, fmtValue.dayOfWeekName(context));
                    else
                        pad(sink, to!string(fmtValue.day), fmtSpec.customSpecCount, '0');
                    break;
                case FormatTimeSpecifier.customFaction: // time fraction, 1..3=msec, 4..6=usec
                    if (fmtSpec.customSpecCount <= 3)
                        pad(sink, to!string(fmtValue.millisecond), fmtSpec.customSpecCount, '0');
                    else
                        pad(sink, to!string(fmtValue.tick), fmtSpec.customSpecCount, '0');
                    break;
                case FormatTimeSpecifier.customHour:
                    pad(sink, to!string(fmtValue.hour), fmtSpec.customSpecCount, '0');
                    break;
                case FormatTimeSpecifier.customMinute:
                    pad(sink, to!string(fmtValue.minute), fmtSpec.customSpecCount, '0');
                    break;
                case FormatTimeSpecifier.customMonth:
                    if (fmtSpec.customSpecCount == 3)
                        put(sink, fmtValue.monthName(context));
                    else
                        pad(sink, to!string(fmtValue.month), fmtSpec.customSpecCount, '0');
                    break;
                case FormatTimeSpecifier.customSecond:
                    pad(sink, to!string(fmtValue.second), fmtSpec.customSpecCount, '0');
                    break;
                case FormatTimeSpecifier.customSeparatorDate:
                    put(sink, context.dateSeparator);
                    break;
                case FormatTimeSpecifier.customSeparatorTime:
                    put(sink, context.timeSeparator);
                    break;
                case FormatTimeSpecifier.customYear:
                    if (fmtSpec.customSpecCount <= 2)
                        pad(sink, to!string(fmtValue.shortYear), fmtSpec.customSpecCount, '0');
                    else
                        pad(sink, to!string(fmtValue.year), fmtSpec.customSpecCount, '0');
                    break;
                default:
                    assert(0);
            }
        }
    }

    void putFullDateTime() nothrow @safe
    {
        put(sink, fmtValue.dayOfWeekName(context));
        put(sink, ", ");
        put(sink, fmtValue.monthName(context));
        put(sink, ' ');
        put(sink, to!string(fmtValue.day));
        put(sink, ", ");
        pad(sink, to!string(fmtValue.year), 4, '0');
        put(sink, ' ');
        put(sink, to!string(fmtValue.shortHour));
        put(sink, context.timeSeparator);
        pad(sink, to!string(fmtValue.minute), 2, '0');
    }

    void putGeneralDateTime() nothrow @safe
    {
        put(sink, to!string(fmtValue.month));
        put(sink, context.dateSeparator);
        put(sink, to!string(fmtValue.day));
        put(sink, context.dateSeparator);
        pad(sink, to!string(fmtValue.year), 4, '0');
        put(sink, ' ');
        put(sink, to!string(fmtValue.shortHour));
        put(sink, context.timeSeparator);
        pad(sink, to!string(fmtValue.minute), 2, '0');
    }

    void putTime() nothrow @safe
    {
        put(sink, to!string(fmtValue.shortHour));
        put(sink, context.timeSeparator);
        pad(sink, to!string(fmtValue.minute), 2, '0');
    }

    uint result = 0;
    while (fmtSpec.writeUpToNextSpec(sink))
    {
        switch (fmtSpec.spec)
        {
            case FormatTimeSpecifier.custom:
                putCustom();
                break;
            case FormatTimeSpecifier.fullShortDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01 PM
                putFullDateTime();
                putAMorPM();
                break;
            case FormatTimeSpecifier.fullLongDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
                putFullDateTime();
                put(sink, context.timeSeparator);
                pad(sink, to!string(fmtValue.second), 2, '0');
                putAMorPM();
                break;
            case FormatTimeSpecifier.generalShortDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
                putGeneralDateTime();
                putAMorPM();
                break;
            case FormatTimeSpecifier.generalLongDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
                putGeneralDateTime();
                put(sink, context.timeSeparator);
                pad(sink, to!string(fmtValue.second), 2, '0');
                putAMorPM();
                break;
            case FormatTimeSpecifier.julianDay:
                put(sink, to!string(fmtValue.julianDay));
                break;
            case FormatTimeSpecifier.longDate: // 2009-06-15T13:45:30 -> Monday, June 15, 2009
                put(sink, fmtValue.dayOfWeekName(context));
                put(sink, ", ");
                put(sink, fmtValue.monthName(context));
                put(sink, ' ');
                put(sink, to!string(fmtValue.day));
                put(sink, ", ");
                pad(sink, to!string(fmtValue.year), 4, '0');
                break;
            case FormatTimeSpecifier.longTime: // 2009-06-15T13:45:30 -> 1:45:30 PM
                putTime();
                put(sink, context.timeSeparator);
                pad(sink, to!string(fmtValue.second), 2, '0');
                putAMorPM();
                break;
            case FormatTimeSpecifier.monthDay: // 2009-06-15T13:45:30 -> June 15
                put(sink, fmtValue.monthName(context));
                put(sink, ' ');
                put(sink, to!string(fmtValue.day));
                break;
            case FormatTimeSpecifier.monthYear: // 2009-06-15T13:45:30 -> June 2009
                put(sink, fmtValue.monthName(context));
                put(sink, ' ');
                pad(sink, to!string(fmtValue.year), 4, '0');
                break;
            case FormatTimeSpecifier.shortDate: // 2009-06-15T13:45:30 -> 6/15/2009
                put(sink, to!string(fmtValue.month));
                put(sink, context.dateSeparator);
                put(sink, to!string(fmtValue.day));
                put(sink, context.dateSeparator);
                pad(sink, to!string(fmtValue.year), 4, '0');
                break;
            case FormatTimeSpecifier.shortTime: // 2009-06-15T13:45:30 -> 1:45 PM
                putTime();
                putAMorPM();
                break;
            case FormatTimeSpecifier.sortableDateTime: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30.000001
                // Date part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.time)
                {
                    pad(sink, to!string(fmtValue.year), 4, '0');
                    put(sink, '-');
                    pad(sink, to!string(fmtValue.month), 2, '0');
                    put(sink, '-');
                    pad(sink, to!string(fmtValue.day), 2, '0');

                    // Has time?
                    if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                        put(sink, 'T');
                }

                // Time part
                if (fmtValue.kind != FormatDateTimeValue.ValueKind.date)
                {
                    pad(sink, to!string(fmtValue.hour), 2, '0');
                    put(sink, ':');
                    pad(sink, to!string(fmtValue.minute), 2, '0');
                    put(sink, ':');
                    pad(sink, to!string(fmtValue.second), 2, '0');
                    put(sink, '.');
                    pad(sink, to!string(fmtValue.tick), 6, '0');
                }
                break;
            case FormatTimeSpecifier.sortableDateTimeLess: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30
                pad(sink, to!string(fmtValue.year), 4, '0');
                put(sink, '-');
                pad(sink, to!string(fmtValue.month), 2, '0');
                put(sink, '-');
                pad(sink, to!string(fmtValue.day), 2, '0');
                put(sink, 'T');
                pad(sink, to!string(fmtValue.hour), 2, '0');
                put(sink, ':');
                pad(sink, to!string(fmtValue.minute), 2, '0');
                put(sink, ':');
                pad(sink, to!string(fmtValue.second), 2, '0');
                break;
            case FormatTimeSpecifier.utcFullDateTime: // 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
                put(sink, fmtValue.dayOfWeekName(context));
                put(sink, ", ");
                put(sink, fmtValue.monthName(context));
                put(sink, ' ');
                put(sink, to!string(fmtValue.day));
                put(sink, ", ");
                pad(sink, to!string(fmtValue.year), 4, '0');
                put(sink, ' ');
                put(sink, to!string(fmtValue.shortHour));
                put(sink, ':');
                pad(sink, to!string(fmtValue.minute), 2, '0');
                put(sink, ':');
                pad(sink, to!string(fmtValue.second), 2, '0');
                putAMorPM();
                break;
            case FormatTimeSpecifier.utcSortableDateTime: // 2009-06-15T13:45:30.000001 -> 2009-06-15 13:45:30.000001Z
                pad(sink, to!string(fmtValue.year), 4, '0');
                put(sink, '-');
                pad(sink, to!string(fmtValue.month), 2, '0');
                put(sink, '-');
                pad(sink, to!string(fmtValue.day), 2, '0');
                put(sink, ' ');
                pad(sink, to!string(fmtValue.hour), 2, '0');
                put(sink, ':');
                pad(sink, to!string(fmtValue.minute), 2, '0');
                put(sink, ':');
                pad(sink, to!string(fmtValue.second), 2, '0');
                put(sink, '.');
                pad(sink, to!string(fmtValue.tick), 6, '0');
                put(sink, 'Z');
                break;
            default:
                assert(0);
        }
        result++;
    }
    return result;
}

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope const(Char)[] fmt, scope const(Date) date)
if (isSomeChar!Char)
{
    auto fmtSpec = FormatDateTimeSpec!Char(fmt);
    auto fmtValue = FormatDateTimeValue(date);
    return formattedWrite(sink, fmtSpec, fmtValue);
}

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope const(Char)[] fmt, scope const(DateTime) dateTime)
if (isSomeChar!Char)
{
    auto fmtSpec = FormatDateTimeSpec!Char(fmt);
    auto fmtValue = FormatDateTimeValue(dateTime);
    return formattedWrite(sink, fmtSpec, fmtValue);
}

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope const(Char)[] fmt, scope const(SysTime) sysTime)
if (isSomeChar!Char)
{
    auto fmtSpec = FormatDateTimeSpec!Char(fmt);
    auto fmtValue = FormatDateTimeValue(sysTime);
    return formattedWrite(sink, fmtSpec, fmtValue);
}

uint formattedWrite(Writer, Char)(auto scope ref Writer sink, scope const(Char)[] fmt, scope const(Time) time)
if (isSomeChar!Char)
{
    auto fmtSpec = FormatDateTimeSpec!Char(fmt);
    auto fmtValue = FormatDateTimeValue(time);
    return formattedWrite(sink, fmtSpec, fmtValue);
}

Fmt format(Fmt)(Fmt fmt, scope const(Date) date)
if (isSomeString!Fmt)
{
    alias Char = Unqual!(ElementEncodingType!Fmt);
    ShortStringBuffer!Char buffer;
    formattedWrite(buffer, fmt, date);
    return buffer.toString();
}

Fmt format(Fmt)(Fmt fmt, scope const(DateTime) dateTime)
if (isSomeString!Fmt)
{
    alias Char = Unqual!(ElementEncodingType!Fmt);
    ShortStringBuffer!Char buffer;
    formattedWrite(buffer, fmt, dateTime);
    return buffer.toString();
}

Fmt format(Fmt)(Fmt fmt, scope const(SysTime) sysTime)
if (isSomeString!Fmt)
{
    alias Char = Unqual!(ElementEncodingType!Fmt);
    ShortStringBuffer!Char buffer;
    formattedWrite(buffer, fmt, sysTime);
    return buffer.toString();
}

Fmt format(Fmt)(Fmt fmt, scope const(Time) time)
if (isSomeString!Fmt)
{
    alias Char = Unqual!(ElementEncodingType!Fmt);
    ShortStringBuffer!Char buffer;
    formattedWrite(buffer, fmt, time);
    return buffer.toString();
}

void pad(Writer, Char)(auto scope ref Writer sink, scope const(Char)[] value, ptrdiff_t size, Char c) nothrow pure
if (isSomeChar!Char)
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

/**
 * Convert an enum to its string presentation
 * Params:
 *  value = an enum to be converted
 * Returns:
 *  a string for parameter value
 * Ex:
 *  enum E {e1 = 1, e2 = 2, e3 = 10, ...}
 *  toName!E(e3) returns "e3"
 */
string toName(E)(const(E) value) nothrow pure @safe
if (is(E Base == enum))
{
    foreach (i, e; EnumMembers!E)
    {
        if (value == e)
        {
            ShortStringBuffer!char buffer;
            buffer.put(__traits(allMembers, E)[i]);
            return buffer.toString();
        }
    }
    return null;
}

string toString(scope const(Date) date, string fmt = "%s")
{
    return format(fmt, date);
}

string toString(scope const(DateTime) dateTime, string fmt = "%s")
{
    return format(fmt, dateTime);
}

string toString(scope const(SysTime) sysTime, string fmt = "%s")
{
    return format(fmt, sysTime);
}

string toString(scope const(Time) time, string fmt = "%s")
{
    return format(fmt, time);
}

static immutable AmPmTexts usAmPmTexts = ["AM", "PM"];
static immutable char usDateSeparator = '/';
static immutable char usTimeSeparator = ':';

// Must match order of DayOfWeek
static immutable DayOfWeekNames usDayOfWeekNames = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    ];

// Must match order of Month
static immutable MonthNames usMonthNames = [
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
    "December",
    ];


private:

static this() @trusted
{
    threadDateTimeContext = sharedDateTimeContext;
}

@safe unittest // ShortStringBufferSize
{
    alias TestFormatString = ShortStringBufferSize!(5, char);

    TestFormatString s;
    assert(s.length == 0);
    s.put('1');
    assert(s.length == 1);
    s.put("234");
    assert(s.length == 4);
    assert(s.toString() == "1234");
    assert(s[] == "1234");
    s.clear();
    assert(s.length == 0);
    s.put("abc");
    assert(s.length == 3);
    assert(s.toString() == "abc");
    assert(s[] == "abc");
    s.put("defghijklmnopqrstuvxywz");
    assert(s.length == 26);
    assert(s.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s[] == "abcdefghijklmnopqrstuvxywz");

    TestFormatString s2;
    s2 ~= s[];
    assert(s2.length == 26);
    assert(s2.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s2[] == "abcdefghijklmnopqrstuvxywz");
}

@safe unittest // FormatTimeSpecifier.fullShortDateTime, fullLongDateTime
{
    string s;

    s = format("%f", DateTime(2009, 06, 15, 12, 1, 30));
    assert(s == "Monday, June 15, 2009 12:01 PM", s);
    s = format("%F", DateTime(2009, 06, 15, 13, 1, 30));
    assert(s == "Monday, June 15, 2009 1:01:30 PM", s);
}

@safe unittest // FormatTimeSpecifier.generalShortDateTime, generalLongDateTime
{
    string s;

    s = format("%g", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "6/15/2009 1:45 PM", s);
    s = format("%G", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "6/15/2009 1:45:30 PM", s);
}

@safe unittest // FormatTimeSpecifier.julianDay
{
    string s;

    s = format("%j", DateTime(2010, 8, 24, 0, 0, 0));
    assert(s == "2455432", s);

    s = format("%j", DateTime(2010, 8, 24, 11, 59, 59));
    assert(s == "2455432", s);

    s = format("%j", DateTime(2010, 8, 24, 12, 0, 0));
    assert(s == "2455433", s);

    s = format("%j", DateTime(2010, 8, 24, 13, 0, 0));
    assert(s == "2455433", s);

    s = format("%j", Date(2010, 8, 24));
    assert(s == "2455433", s);

    s = format("%j", Time(11, 59, 59));
    assert(s == "0", s);

    s = format("%j", Time(12, 0, 0));
    assert(s == "1", s);
}

@safe unittest // FormatTimeSpecifier.longDate, shortDate
{
    string s;

    s = format("%D", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "Monday, June 15, 2009", s);
    s = format("%d", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "6/15/2009", s);

    s = format("%D", Date(2009, 06, 15));
    assert(s == "Monday, June 15, 2009", s);
    s = format("%d", Date(2009, 06, 15));
    assert(s == "6/15/2009");
}

@safe unittest // FormatTimeSpecifier.longTime, shortTime
{
    string s;

    s = format("%T", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "1:45:30 PM", s);
    s = format("%t", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "1:45 PM", s);

    s = format("%T", Time(13, 45, 30));
    assert(s == "1:45:30 PM", s);
    s = format("%t", Time(13, 45, 30));
    assert(s == "1:45 PM", s);
}

@safe unittest // FormatTimeSpecifier.monthDay, monthYear
{
    string s;

    s = format("%M", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "June 15", s);
    s = format("%Y", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "June 2009");
}

@safe unittest // FormatTimeSpecifier.sortableDateTime
{
    string s;

    s = format("%s", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "2009-06-15T13:45:30.000000", s);
    s = format("%s", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "2009-06-15T13:45:30.000000", s);
    s = format("%s", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "2009-06-15T13:45:30.000001", s);

    s = format("%s", Date(2009, 06, 15));
    assert(s == "2009-06-15", s);

    s = format("%s", Time(13, 45, 30));
    assert(s == "13:45:30.000000", s);
}

@safe unittest // FormatTimeSpecifier.sortableDateTimeLess
{
    string s;

    s = format("%S", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "2009-06-15T13:45:30", s);
    s = format("%S", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "2009-06-15T13:45:30", s);
    s = format("%S", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "2009-06-15T13:45:30", s);
}

@safe unittest // FormatTimeSpecifier.utcFullDateTime
{
    string s;

    s = format("%U", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "Monday, June 15, 2009 1:45:30 PM", s);
}

@safe unittest // FormatTimeSpecifier.utcSortableDateTime
{
    string s;

    s = format("%u", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "2009-06-15 13:45:30.000001Z", s);
}

@safe unittest // FormatTimeSpecifier.custom, FormatTimeSpecifier.dateSeparator, FormatTimeSpecifier.timeSeparator
{
    string s;

    s = format("%cmm/dd/yyyy hh:nn:ss", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "06/15/2009 13:45:30", s);
    s = format("%cm/dd/yyyy h:nn:ss", DateTime(2009, 06, 15, 3, 45, 30));
    assert(s == "6/15/2009 3:45:30", s);
    s = format("%cm/dd/yy h:nn:ss", DateTime(2009, 06, 15, 3, 45, 30));
    assert(s == "6/15/09 3:45:30", s);

    s = format("%cdd/mm/yyyy", Date(2009, 06, 15));
    assert(s == "15/06/2009", s);
    s = format("%cdd/mm/yy", Date(2009, 06, 15));
    assert(s == "15/06/09", s);

    s = format("%cmmm d, yyyy", Date(2009, 06, 1));
    assert(s == "June 1, 2009", s);

    s = format("%cddd, mmm d, yyyy", Date(2009, 06, 1));
    assert(s == "Monday, June 1, 2009", s);

    s = format("%cyyyymmdd hhnnsszzz", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "20090615 134530000", s);
    s = format("%cyyyymmdd hhnnsszzzzzz", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "20090615 134530000001", s);

    s = format("%ch:n:s", Time(13, 45, 30));
    assert(s == "13:45:30", s);

    // Escape % weird character format
    s = format("%cdd-%%?mm'%%-yyyy", Date(2009, 06, 15));
    assert(s == "15-%?06'%-2009", s);
}
