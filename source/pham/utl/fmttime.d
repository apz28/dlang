module pham.utl.fmttime;

import core.time : Duration, msecs, usecs;
import std.conv : to;
import std.array : appender;
import std.datetime.date : Date, DateTime, DayOfWeek, Month, TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.format : FormatException, FormatSpec;
import std.range.primitives;
import std.traits;

import pham.utl.utlobject : pad;

enum FmtTimeSpecifier : char
{
    fullShortDateTime = 'f', /// 2009-06-15T12:1:30 -> Monday, June 15, 2009 12:01 PM
    fullLongDateTime = 'F', /// 2009-06-15T13:1:30 -> Monday, June 15, 2009 1:01:30 PM
    generalShortDateTime = 'g', /// 2009-06-15T13:45:30 -> 6/15/2009 1:45 PM
    generalLongDateTime = 'G', /// 2009-06-15T13:45:30 -> 6/15/2009 1:45:30 PM
    julianDay = 'j', /// Julian day - $(HTTP en.wikipedia.org/wiki/Julian_day, Julian day)
    longDate = 'D', /// 2009-06-15T13:45:30 -> Monday, June 15, 2009
    longTime = 'T', /// 2009-06-15T13:45:30 -> 1:45:30 PM
    monthDay = 'M', /// 2009-06-15T13:45:30 -> June 15
    monthYear = 'Y', /// 2009-06-15T13:45:30 -> June 2009
    part = 'p', /// pyy, pyyyy - 2009-06-01T01:02:03 -> 09, 2009
                /// pm, pmm, pmmmm - 2009-06-01T01:02:03 -> 6, 06, June
                /// pd, pdd, pdddd - 2009-06-01T01:02:03 -> 1, 01, Saturday
                /// ph, phh - 2009-06-01T01:02:03 -> 1, 01
                /// pn, pnn - 2009-06-01T01:02:03 -> 2, 02
                /// ps, pss - 2009-06-01T01:02:03 -> 3, 03
                /// pz, pzzz - 2009-06-01T01:02:03.4 -> 4, 004
    shortDate = 'd', /// 2009-06-15T13:45:30 -> 6/15/2009
    shortTime = 't', /// 2009-06-15T13:45:30 -> 1:45 PM
    sortableDateTime = 's', /// 2009-06-15T13:45:30.001000 -> 2009-06-15T13:45:30.001000
    utcFullDateTime = 'U', /// 2009-06-15T13:45:30 -> Monday, June 15, 2009 8:45:30 PM
    utcSortableDateTime = 'u', /// 2009-06-15T13:45:30 -> 2009-06-15 13:45:30Z
}

DateTimeContext threadDateTimeContext;
__gshared DateTimeContext sharedDateTimeContext = DateTimeContext.us();

static this()
{
    threadDateTimeContext = sharedDateTimeContext;
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

    @property size_t monthNameIndex() const pure
    {
        return month - Month.jan;
    }
}

uint formattedWriteDateTime(Writer, Char)(auto ref Writer writer, scope const(Char)[] fmt, const ref FmtTime fmtTime)
{
    const context = threadDateTimeContext;

    void putAMorPM() nothrow @trusted
    {
        if (context.amPmValues is null)
            return;

        auto s = context.amPmValues[fmtTime.hour >= 12];
        if (s.length)
        {
            put(writer, ' ');
            put(writer, s[]);
        }
    }

    void putFullDateTime() nothrow @trusted
    {
        put(writer, (context.dayOfWeekNames[fmtTime.dayOfWeek])[]);
        put(writer, ", ");
        put(writer, (context.monthNames[fmtTime.monthNameIndex])[]);
        put(writer, ' ');
        put(writer, to!string(fmtTime.day));
        put(writer, ", ");
        put(writer, pad(to!string(fmtTime.year), 4, '0'));
        put(writer, ' ');
        put(writer, to!string(fmtTime.hour));
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
        put(writer, to!string(fmtTime.hour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtTime.minute), 2, '0'));
    }

    void putTime() nothrow @safe
    {
        put(writer, to!string(fmtTime.hour));
        put(writer, context.timeSeparator);
        put(writer, pad(to!string(fmtTime.minute), 2, '0'));
    }

    uint result = 0;
    auto timeSpec = FmtTimeSpec!Char(fmt);
    while (timeSpec.writeUpToNextSpec(writer))
    {
        final switch (timeSpec.spec)
        {
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
                put(writer, (context.dayOfWeekNames[fmtTime.dayOfWeek])[]);
                put(writer, ", ");
                put(writer, (context.monthNames[fmtTime.monthNameIndex])[]);
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
                put(writer, (context.monthNames[fmtTime.monthNameIndex])[]);
                put(writer, ' ');
                put(writer, to!string(fmtTime.day));
                break;
            case FmtTimeSpecifier.monthYear: // 2009-06-15T13:45:30 -> June 2009
                put(writer, (context.monthNames[fmtTime.monthNameIndex])[]);
                put(writer, ' ');
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                break;
            case FmtTimeSpecifier.part:
                assert(timeSpec.specModifier.length != 0);
                switch (timeSpec.specModifier[0])
                {
                    case 'd': // day
                        put(writer, pad(to!string(fmtTime.day), timeSpec.specModifier.length, '0'));
                        break;
                    case 'h': // hour
                        put(writer, pad(to!string(fmtTime.hour), timeSpec.specModifier.length, '0'));
                        break;
                    case 'm': // month
                        put(writer, pad(to!string(fmtTime.month), timeSpec.specModifier.length, '0'));
                        break;
                    case 'n': // minute
                        put(writer, pad(to!string(fmtTime.minute), timeSpec.specModifier.length, '0'));
                        break;
                    case 's': // second
                        put(writer, pad(to!string(fmtTime.second), timeSpec.specModifier.length, '0'));
                        break;
                    case 'y': // year
                        put(writer, pad(to!string(fmtTime.year), timeSpec.specModifier.length, '0'));
                        break;
                    case 'z': // time fraction, 1..3=msec, 4..6=usec
                        if (timeSpec.specModifier.length <= 3)
                            put(writer, pad(to!string(fmtTime.msec), timeSpec.specModifier.length, '0'));
                        else
                            put(writer, pad(to!string(fmtTime.usec), timeSpec.specModifier.length, '0'));
                        break;
                    default:
                        assert(0);
                }
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
            case FmtTimeSpecifier.utcFullDateTime: // 2009-06-15T13:45:30 -> Monday, June 15, 2009 8:45:30 PM
                put(writer, (context.dayOfWeekNames[fmtTime.dayOfWeek])[]);
                put(writer, ", ");
                put(writer, (context.monthNames[fmtTime.monthNameIndex])[]);
                put(writer, ' ');
                put(writer, to!string(fmtTime.day));
                put(writer, ", ");
                put(writer, pad(to!string(fmtTime.year), 4, '0'));
                put(writer, ' ');
                put(writer, to!string(fmtTime.hour));
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
    import std.algorithm.searching : startsWith;
    import std.ascii : isDigit, isPunctuation, isAlpha;
    import std.conv : parse, text, to;

    /// The actual format specifier
    char spec = FmtTimeSpecifier.sortableDateTime;
    char[] specModifier;

    /// contains the rest of the format string.
    const(Char)[] trailing;

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

            put(writer, trailing[0..i]);
            trailing = trailing[i..$];
            enforceFmt(trailing.length >= 2, `Unterminated format specifier: "%"` ~ trailing);
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

    private void fillSpec() scope
    {
        specModifier = null;
        spec = cast(char)trailing[0];
        trailing = trailing[1..$];

        switch (spec)
        {
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
                return;
            case FmtTimeSpecifier.part:
                enforceFmt(trailing.length > 0, `Unterminated format modifier: ` ~ trailing);
                size_t limit;
                size_t count = 0;
                const first = trailing[0];
                switch (first)
                {
                    case 'd': // day
                    case 'h': // hour
                    case 'm': // month
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
                        throw new FormatException(text("Unterminated format modifier: ", trailing));
                }
                for (size_t i = 0; i < trailing.length && first == trailing[i] && count < limit; i++)
                    count++;
                specModifier = cast(char[])trailing[0..count];
                trailing = trailing[count..$];
                return;
            default:
                throw new FormatException(text("Incorrect format specifier: ", spec));
        }
    }
}