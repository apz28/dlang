module pham.utl.fmttime;

import core.time : Duration, msecs, usecs;
import std.conv : to;
import std.array : appender;
import std.datetime.date : Date, DateTime, DayOfWeek, Month, TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.format : FormatException, FormatSpec;
import std.range.primitives : empty, put;
import std.traits;

import pham.utl.utlobject : pad;

@safe:

enum FmtTimeSpecifier : char
{
    custom = 'c', /// %cyy, %cyyyyy - 2009-06-01T01:02:03 -> 09, 2009
                  /// %cm, %cmm, %cmmm - 2009-06-01T01:02:03 -> 6, 06, June
                  /// %cd, %cdd, %cddd - 2009-06-01T01:02:03 -> 1, 01, Saturday
                  /// %ch, %chh - 2009-06-01T01:02:03 -> 1, 01
                  /// %cn, %cnn - 2009-06-01T01:02:03 -> 2, 02
                  /// %cs, %css - 2009-06-01T01:02:03 -> 3, 03
                  /// %cz, %czzz, %czzzzzz - 2009-06-01T01:02:03.4 -> 4, 004, 004000
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
    utcFullDateTime = 'U', /// %U 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
    utcSortableDateTime = 'u', /// %u 2009-06-15T13:45:30.000001 -> 2009-06-15 13:45:30.000001Z
    dateSeparator = '/', /// %/
    timeSeparator = ':', /// %:
}

struct DateTimeContext
{
nothrow @safe:

    const(DayOfWeekNames)* dayOfWeekNames;
    const(MonthNames)* monthNames;
    const(AmPmValues)* amPmValues;
    char dateSeparator = 0;
    char timeSeparator = 0;

    bool isValid() const pure
    {
        return (dayOfWeekNames !is null) && (monthNames !is null)
            && dateSeparator != 0 && timeSeparator != 0;
    }

    static DateTimeContext us()
    {
        return DateTimeContext(&usDayOfWeekNames, &usMonthNames, &usAmPmValues, usDateSeparator, usTimeSeparator);
    }
}

alias AmPmValues = string[2];
alias DayOfWeekNames = string[7];
alias MonthNames = string[12];

DateTimeContext threadDateTimeContext;
__gshared DateTimeContext sharedDateTimeContext = DateTimeContext.us();

immutable(Char)[] formatDateTime(Char)(scope const(Char)[] fmt, in Date date)
if (isSomeChar!Char)
{
    auto buffer = appender!(immutable(Char)[]);
    buffer.reserve(50);
    formattedWriteDateTime(buffer, fmt, date);
    return buffer.data;
}

immutable(Char)[] formatDateTime(Char)(scope const(Char)[] fmt, in DateTime dateTime)
if (isSomeChar!Char)
{
    auto buffer = appender!(immutable(Char)[]);
    buffer.reserve(50);
    formattedWriteDateTime(buffer, fmt, dateTime);
    return buffer.data;
}

immutable(Char)[] formatDateTime(Char)(scope const(Char)[] fmt, in SysTime sysTime)
if (isSomeChar!Char)
{
    auto buffer = appender!(immutable(Char)[]);
    buffer.reserve(50);
    formattedWriteDateTime(buffer, fmt, sysTime);
    return buffer.data;
}

immutable(Char)[] formatDateTime(Char)(scope const(Char)[] fmt, in TimeOfDay time)
if (isSomeChar!Char)
{
    auto buffer = appender!(immutable(Char)[]);
    buffer.reserve(50);
    formattedWriteDateTime(buffer, fmt, time);
    return buffer.data;
}

void formattedWriteDateTime(Writer, Char)(auto ref Writer writer, scope const(Char)[] fmt, in Date date)
{
    auto v = FmtTime(date);
    formattedWriteDateTime!(Writer, Char)(writer, fmt, v);
}

void formattedWriteDateTime(Writer, Char)(auto ref Writer writer, scope const(Char)[] fmt, in DateTime dateTime)
{
    auto v = FmtTime(dateTime);
    formattedWriteDateTime!(Writer, Char)(writer, fmt, v);
}

void formattedWriteDateTime(Writer, Char)(auto ref Writer writer, scope const(Char)[] fmt, in SysTime sysTime)
{
    auto v = FmtTime(sysTime);
    formattedWriteDateTime!(Writer, Char)(writer, fmt, v);
}

void formattedWriteDateTime(Writer, Char)(auto ref Writer writer, scope const(Char)[] fmt, in TimeOfDay time)
{
    auto v = FmtTime(time);
    formattedWriteDateTime!(Writer, Char)(writer, fmt, v);
}

struct FmtTime
{
nothrow @safe:

    this(in Date date) pure
    {
        this.year = date.year;
        this.month = date.month;
        this.day = date.day;
        this.julianDay = date.julianDay;
        this.dayOfWeek = date.dayOfWeek;
    }

    this(in DateTime dateTime) pure
    {
        this.year = dateTime.year;
        this.month = dateTime.month;
        this.day = dateTime.day;
        this.julianDay = dateTime.julianDay;
        this.dayOfWeek = dateTime.dayOfWeek;
        this.hour = dateTime.hour;
        this.minute = dateTime.minute;
        this.second = dateTime.second;
    }

    this(in SysTime sysTime)
    {
        const d = cast(DateTime)sysTime;
        const t = cast(TimeOfDay)sysTime;
        const f = sysTime.fracSecs;
        this.year = d.year;
        this.month = d.month;
        this.day = d.day;
        this.julianDay = sysTime.julianDay;
        this.dayOfWeek = d.dayOfWeek;
        this.hour = t.hour;
        this.minute = t.minute;
        this.second = t.second;
        this.msec = f.total!"msecs"; // Total fracSecs in msecs
        this.usec = f.total!"usecs"; // Total fracSecs in usecs
    }

    this(in TimeOfDay time) pure
    {
        this.month = Month.jan; // Must be valid value - pick the first enum value
        this.day = 1; // Must be valid value - pick the first enum value
        this.dayOfWeek = DayOfWeek.sun; // Must be valid value - pick the first enum value
        this.hour = time.hour;
        this.minute = time.minute;
        this.second = time.second;
    }

    int year;
    ubyte month;
    ubyte day;
    ubyte hour;
    ubyte minute;
    ubyte second;
    ulong msec;
    ulong usec;
    long julianDay;
    DayOfWeek dayOfWeek;

    string amPM(const DateTimeContext context) const pure
    {
        if (context.amPmValues is null)
            return null;
        else
            return (*context.amPmValues)[hour >= 12];
    }

    string dayOfWeekName(const DateTimeContext context) const pure
    {
        return (*context.dayOfWeekNames)[this.dayOfWeek];
    }

    string monthName(const DateTimeContext context) const pure
    {
        const index = this.month - Month.jan;
        return (*context.monthNames)[index];
    }

    @property ubyte shortHour() const pure
    in
    {
        assert(hour <= 23);
    }
    do
    {
        return hour <= 12 ? hour : cast(ubyte)(hour - 12);
    }
}

uint formattedWriteDateTime(Writer, Char)(auto ref Writer writer, scope const(Char)[] fmt, const ref FmtTime fmtTime) @trusted
{
    const context = threadDateTimeContext;

    void putAMorPM() nothrow @safe
    {
        auto s = fmtTime.amPM(context);
        if (s.length)
        {
            put(writer, ' ');
            put(writer, s[]);
        }
    }

    void putCustom(char spec, size_t len) nothrow @safe
    {
        switch (spec)
        {
            case 'd': // day
                if (len == 3)
                    put(writer, fmtTime.dayOfWeekName(context));
                else
                    put(writer, pad(to!string(fmtTime.day), len, '0'));
                break;
            case 'h': // hour
                put(writer, pad(to!string(fmtTime.hour), len, '0'));
                break;
            case 'm': // month
                if (len == 3)
                    put(writer, fmtTime.monthName(context));
                else
                    put(writer, pad(to!string(fmtTime.month), len, '0'));
                break;
            case 'n': // minute
                put(writer, pad(to!string(fmtTime.minute), len, '0'));
                break;
            case 's': // second
                put(writer, pad(to!string(fmtTime.second), len, '0'));
                break;
            case 'y': // year
                put(writer, pad(to!string(fmtTime.year), len, '0'));
                break;
            case 'z': // time fraction, 1..3=msec, 4..6=usec
                if (len <= 3)
                    put(writer, pad(to!string(fmtTime.msec), len, '0'));
                else
                    put(writer, pad(to!string(fmtTime.usec), len, '0'));
                break;
            default:
                assert(0);
        }
    }

    void putFullDateTime() nothrow @safe
    {
        put(writer, fmtTime.dayOfWeekName(context));
        put(writer, ", ");
        put(writer, fmtTime.monthName(context));
        put(writer, ' ');
        put(writer, to!string(fmtTime.day));
        put(writer, ", ");
        put(writer, pad(to!string(fmtTime.year), 4, '0'));
        put(writer, ' ');
        put(writer, to!string(fmtTime.shortHour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtTime.minute), 2, '0'));
    }

    void putGeneralDateTime() nothrow @safe
    {
        put(writer, to!string(fmtTime.month));
        put(writer, context.dateSeparator);
        put(writer, to!string(fmtTime.day));
        put(writer, context.dateSeparator);
        put(writer, pad(to!string(fmtTime.year), 4, '0'));
        put(writer, ' ');
        put(writer, to!string(fmtTime.shortHour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtTime.minute), 2, '0'));
    }

    void putTime() nothrow @safe
    {
        put(writer, to!string(fmtTime.shortHour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtTime.minute), 2, '0'));
    }

    uint result = 0;
    auto timeSpec = FmtTimeSpec!Char(fmt);
    while (timeSpec.writeUpToNextSpec(writer))
    {
        final switch (timeSpec.spec)
        {
            case FmtTimeSpecifier.custom:
                assert(timeSpec.specModifier.length != 0);
                putCustom(timeSpec.specModifier[0], timeSpec.specModifier.length);
                break;
            case FmtTimeSpecifier.fullShortDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01 PM
                putFullDateTime();
                putAMorPM();
                break;
            case FmtTimeSpecifier.fullLongDateTime: // 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
                putFullDateTime();
                put(writer, context.timeSeparator);
                put(writer, pad(to!string(fmtTime.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.generalShortDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
                putGeneralDateTime();
                putAMorPM();
                break;
            case FmtTimeSpecifier.generalLongDateTime: // 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
                putGeneralDateTime();
                put(writer, context.timeSeparator);
                put(writer, pad(to!string(fmtTime.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.julianDay:
                put(writer, to!string(fmtTime.julianDay));
                break;
            case FmtTimeSpecifier.longDate: // 2009-06-15T13:45:30 -> Monday, June 15, 2009
                put(writer, fmtTime.dayOfWeekName(context));
                put(writer, ", ");
                put(writer, fmtTime.monthName(context));
                put(writer, ' ');
                put(writer, to!string(fmtTime.day));
                put(writer, ", ");
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                break;
            case FmtTimeSpecifier.longTime: // 2009-06-15T13:45:30 -> 1:45:30 PM
                putTime();
                put(writer, context.timeSeparator);
                put(writer, pad(to!string(fmtTime.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.monthDay: // 2009-06-15T13:45:30 -> June 15
                put(writer, fmtTime.monthName(context));
                put(writer, ' ');
                put(writer, to!string(fmtTime.day));
                break;
            case FmtTimeSpecifier.monthYear: // 2009-06-15T13:45:30 -> June 2009
                put(writer, fmtTime.monthName(context));
                put(writer, ' ');
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                break;
            case FmtTimeSpecifier.shortDate: // 2009-06-15T13:45:30 -> 6/15/2009
                put(writer, to!string(fmtTime.month));
                put(writer, context.dateSeparator);
                put(writer, to!string(fmtTime.day));
                put(writer, context.dateSeparator);
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                break;
            case FmtTimeSpecifier.shortTime: // 2009-06-15T13:45:30 -> 1:45 PM
                putTime();
                putAMorPM();
                break;
            case FmtTimeSpecifier.sortableDateTime: // 2009-06-15T13:45:30.000001 -> 2009-06-15T13:45:30.000001
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtTime.month), 2, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtTime.day), 2, '0'));
                put(writer, 'T');
                put(writer, pad(to!string(fmtTime.hour), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtTime.minute), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtTime.second), 2, '0'));
                put(writer, '.');
                put(writer, pad(to!string(fmtTime.usec), 6, '0'));
                break;
            case FmtTimeSpecifier.utcFullDateTime: // 2009-06-15T13:45:30 -> Monday, June 15, 2009 1:45:30 PM
                put(writer, fmtTime.dayOfWeekName(context));
                put(writer, ", ");
                put(writer, fmtTime.monthName(context));
                put(writer, ' ');
                put(writer, to!string(fmtTime.day));
                put(writer, ", ");
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                put(writer, ' ');
                put(writer, to!string(fmtTime.shortHour));
                put(writer, ':');
                put(writer, pad(to!string(fmtTime.minute), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtTime.second), 2, '0'));
                putAMorPM();
                break;
            case FmtTimeSpecifier.utcSortableDateTime: // 2009-06-15T13:45:30.000001 -> 2009-06-15 13:45:30.000001Z
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtTime.month), 2, '0'));
                put(writer, '-');
                put(writer, pad(to!string(fmtTime.day), 2, '0'));
                put(writer, ' ');
                put(writer, pad(to!string(fmtTime.hour), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtTime.minute), 2, '0'));
                put(writer, ':');
                put(writer, pad(to!string(fmtTime.second), 2, '0'));
                put(writer, '.');
                put(writer, pad(to!string(fmtTime.usec), 6, '0'));
                put(writer, 'Z');
                break;
            case FmtTimeSpecifier.dateSeparator:
                put(writer, context.dateSeparator);
                break;
            case FmtTimeSpecifier.timeSeparator:
                put(writer, context.timeSeparator);
                break;
        }
        result++;
    }
    return result;
}

alias enforceFmt = enforce!FormatException;

struct FmtTimeSpec(Char)
if (is(Unqual!Char == Char))
{
import std.conv : to;

public:
    /// contains the rest of the format string.
    const(Char)[] trailing;

    char[] specModifier;

    /// The actual format specifier
    char spec = FmtTimeSpecifier.sortableDateTime;

    /**
     * Construct a new `FmtTimeSpec` using the format string `fmt`, no
     * processing is done until needed.
     */
    this(in Char[] fmt) @safe pure
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
    bool writeUpToNextSpec(OutputRange)(ref OutputRange writer) scope
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
            enforceFmt(trailing.length >= 2, "Unterminated format specifier: " ~ to!string(trailing));
            trailing = trailing[1..$];

            if (trailing[0] != '%')
            {
                // Spec found. Fill up the spec, and bailout
                fillSpec();
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

private:
    void fillSpec() @trusted
    {
        specModifier = null;
        spec = cast(char)trailing[0];
        trailing = trailing[1..$];

        switch (spec)
        {
            case FmtTimeSpecifier.custom:
                enforceFmt(trailing.length > 0, "Unterminated format modifier: " ~ to!string(trailing));
                fillCustomSpec();
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
            case FmtTimeSpecifier.utcFullDateTime:
            case FmtTimeSpecifier.utcSortableDateTime:
            case FmtTimeSpecifier.dateSeparator:
            case FmtTimeSpecifier.timeSeparator:
                return;
            default:
                enforceFmt(false, "Incorrect format specifier: " ~ to!string(spec));
        }
    }

    void fillCustomSpec() @trusted
    {
        size_t limit;
        size_t count = 0;
        const first = trailing[0];
        switch (first)
        {
            case 'd': // day
            case 'm': // month
                limit = 3;
                break;
            case 'h': // hour
            case 'n': // minute
            case 's': // second
                limit = 2;
                break;
            case 'y': // year
                limit = 5;
                break;
            case 'z': // time fraction, 1..3=msec, 4..6=usec
                limit = 6;
                break;
            default:
                enforceFmt(false, "Unterminated format modifier: " ~ to!string(trailing));
        }
        for (size_t i = 0; i < trailing.length && first == trailing[i] && count < limit; i++)
            count++;
        specModifier = cast(char[])trailing[0..count];
        trailing = trailing[count..$];
    }
}


immutable AmPmValues usAmPmValues = ["AM", "PM"];
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
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %f %F");

    string s;

    s = formatDateTime("%f", DateTime(2009, 06, 15, 12, 1, 30));
    assert(s == "Monday, June 15, 2009 12:01 PM", s);
    s = formatDateTime("%F", DateTime(2009, 06, 15, 13, 1, 30));
    assert(s == "Monday, June 15, 2009 1:01:30 PM", s);
}

@safe unittest // FmtTimeSpecifier.generalShortDateTime, generalLongDateTime
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %g");

    string s;

    s = formatDateTime("%g", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "6/15/2009 1:45 PM", s);
    s = formatDateTime("%G", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "6/15/2009 1:45:30 PM", s);
}

@safe unittest // FmtTimeSpecifier.julianDay
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %j");

    string s;

    s = formatDateTime("%j", DateTime(2010, 8, 24, 0, 0, 0));
    assert(s == "2455432", s);
}

@safe unittest // FmtTimeSpecifier.longDate, shortDate
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %d %D");

    string s;

    s = formatDateTime("%D", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "Monday, June 15, 2009", s);
    s = formatDateTime("%d", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "6/15/2009", s);

    s = formatDateTime("%D", Date(2009, 06, 15));
    assert(s == "Monday, June 15, 2009", s);
    s = formatDateTime("%d", Date(2009, 06, 15));
    assert(s == "6/15/2009");

    s = formatDateTime("%D", SysTime(DateTime(2009, 06, 15, 13, 45, 30)));
    assert(s == "Monday, June 15, 2009", s);
    s = formatDateTime("%d", SysTime(DateTime(2009, 06, 15, 13, 45, 30)));
    assert(s == "6/15/2009", s);
}

@safe unittest // FmtTimeSpecifier.longTime, shortTime
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %t %T");

    string s;

    s = formatDateTime("%T", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "1:45:30 PM", s);
    s = formatDateTime("%t", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "1:45 PM", s);

    s = formatDateTime("%T", TimeOfDay(13, 45, 30));
    assert(s == "1:45:30 PM", s);
    s = formatDateTime("%t", TimeOfDay(13, 45, 30));
    assert(s == "1:45 PM", s);

    s = formatDateTime("%T", SysTime(DateTime(2009, 06, 15, 13, 45, 30)));
    assert(s == "1:45:30 PM", s);
    s = formatDateTime("%t", SysTime(DateTime(2009, 06, 15, 13, 45, 30)));
    assert(s == "1:45 PM", s);
}

@safe unittest // FmtTimeSpecifier.monthDay, monthYear
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %M %Y");

    string s;

    s = formatDateTime("%M", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "June 15", s);
    s = formatDateTime("%Y", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "June 2009");
}

@safe unittest // FmtTimeSpecifier.sortableDateTime
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %s");

    string s;

    s = formatDateTime("%s", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "2009-06-15T13:45:30.000000", s);
    s = formatDateTime("%s", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "2009-06-15T13:45:30.000000", s);
    s = formatDateTime("%s", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "2009-06-15T13:45:30.000001", s);
}

@safe unittest // FmtTimeSpecifier.utcFullDateTime
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %U");

    string s;

    s = formatDateTime("%U", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "Monday, June 15, 2009 1:45:30 PM", s);
}

@safe unittest // FmtTimeSpecifier.utcSortableDateTime
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %u");

    string s;

    s = formatDateTime("%u", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "2009-06-15 13:45:30.000001Z", s);
}

@safe unittest // FmtTimeSpecifier.custom, FmtTimeSpecifier.dateSeparator, FmtTimeSpecifier.timeSeparator
{
    import pham.utl.utltest;
    traceUnitTest("unittest pham.utl.fmttime - %custom....");

    string s;

    s = formatDateTime("%cmm%/%cdd%/%cyyyy %chh%:%cnn%:%css", DateTime(2009, 06, 15, 13, 45, 30));
    assert(s == "06/15/2009 13:45:30", s);
    s = formatDateTime("%cm%/%cdd%/%cyyyy %ch%:%cnn%:%css", DateTime(2009, 06, 15, 3, 45, 30));
    assert(s == "6/15/2009 3:45:30", s);

    s = formatDateTime("%cdd%/%cmm%/%cyyyy", Date(2009, 06, 15));
    assert(s == "15/06/2009", s);

    s = formatDateTime("%cmmm %cd, %cyyyy", Date(2009, 06, 1));
    assert(s == "June 1, 2009", s);

    s = formatDateTime("%cddd, %cmmm %cd, %cyyyy", Date(2009, 06, 1));
    assert(s == "Monday, June 1, 2009", s);

    s = formatDateTime("%cyyyy%cmm%cdd %chh%cnn%css%czzz", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "20090615 134530000", s);
    s = formatDateTime("%cyyyy%cmm%cdd %chh%cnn%css%czzzzzz", SysTime(DateTime(2009, 06, 15, 13, 45, 30), usecs(1), null));
    assert(s == "20090615 134530000001", s);

    s = formatDateTime("%ch%:%cn%:%cs", TimeOfDay(13, 45, 30));
    assert(s == "13:45:30", s);
}
