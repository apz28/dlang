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

module pham.utl.datetime.tick;

import core.time : ClockType, convert;
public import core.time : dur, Duration, TimeException;
import std.conv : to;

version = RelaxCompareTime;

@safe:

enum DateTimeKind : byte
{
    unspecified = 0,
    utc = 1,
    local = 2,
}

struct Tick
{
@nogc nothrow @safe:

public:
    enum bool s_systemSupportsLeapSeconds = false;

    // Number of 100ns ticks per time unit
    enum long ticksPerMillisecond = 10_000; // hnsecs
    enum long ticksPerSecond = ticksPerMillisecond * 1_000; //      10_000_000
    enum long ticksPerMinute = ticksPerSecond * 60;         //     600_000_000
    enum long ticksPerHour = ticksPerMinute * 60;           //  36,000,000,000
    enum long ticksPerDay = ticksPerHour * 24;              // 864,000,000,000
    enum int  ticksMaxPrecision = 7;                        // 999 * ticksPerMillisecond = 7 digits

    // Number of milliseconds per time unit
    enum long millisPerSecond = 1_000;
    enum long millisPerMinute = millisPerSecond * 60;
    enum long millisPerHour = millisPerMinute * 60;
    enum long millisPerDay = millisPerHour * 24;
    enum int  millisMaxPrecision = 3;

    // Number of days in a non-leap year
    enum long daysPerYear = 365;
    // Number of days in 4 years
    enum long daysPer4Years = daysPerYear * 4 + 1;       // 1_461
    // Number of days in 100 years
    enum long daysPer100Years = daysPer4Years * 25 - 1;  // 36_524
    // Number of days in 400 years
    enum long daysPer400Years = daysPer100Years * 4 + 1; // 146_097

    // Number of days from 1/1/0001 to 12/31/1600
    enum long daysTo1601 = daysPer400Years * 4;          // 584_388
    // Number of days from 1/1/0001 to 12/30/1899
    enum long daysTo1899 = daysPer400Years * 4 + daysPer100Years * 3 - 367;
    // Number of days from 1/1/0001 to 12/31/1969
    enum long daysTo1970 = daysPer400Years * 4 + daysPer100Years * 3 + daysPer4Years * 17 + daysPerYear; // 719_162
    // Number of days from 1/1/0001 to 12/31/9999
    // The value calculated from "DateTime(12/31/9999).ticks / ticksPerDay"
    enum long daysTo10000 = daysPer400Years * 25 - 366;  // 3_652_059

    enum long unixEpochTicks = daysTo1970 * ticksPerDay;

    static long currentSystemTicks(ClockType clockType = ClockType.normal)() @trusted
    if (clockType == ClockType.coarse || clockType == ClockType.normal || clockType == ClockType.precise)
    {
        version (Windows)
            return currentSystemTicksWindows!clockType();
        else version (Posix)
            return currentSystemTicksPosix!clockType();
        else
            static assert(0, "Unsupported OS");
    }

    pragma(inline, true)
    static Duration durationFromSystemBias(long bias) pure
    {
        return bias != 0 ? dur!"minutes"(-bias) : Duration.zero;
    }

    pragma(inline, true)
    static Duration durationFromTick(long ticks) pure
    {
        return dur!"hnsecs"(ticks);
    }

    pragma(inline, true)
    static long durationToTick(scope const Duration duration) pure
    {
        return duration.total!"hnsecs";
    }

    pragma(inline, true)
    static int tickToMillisecond(int ticks) pure
    {
        return cast(int)(dur!"hnsecs"(ticks).total!"msecs");
    }

    pragma(inline, true)
    static ulong timeToTicks(int hour, int minute, int second) pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, 0) == ErrorPart.none);
    }
    do
    {
        const ulong totalSeconds = cast(ulong)hour * 3600 + minute * 60 + second;
        return totalSeconds * ticksPerSecond;
    }

    pragma(inline, true)
    static ulong timeToTicks(int hour, int minute, int second, int millisecond) pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, millisecond) == ErrorPart.none);
    }
    do
    {
        return timeToTicks(hour, minute, second) + (cast(ulong)millisecond * ticksPerMillisecond);
    }

    pragma(inline, true)
    static size_t toHash(ulong ticks) pure
    {
        static if (size_t.sizeof == ulong.sizeof)
        {
            return ticks;
        }
        else
        {
            // MurmurHash2
            enum ulong m = 0xc6a4a7935bd1e995UL;
            enum ulong n = m * 16;
            enum uint r = 47;

            ulong k = ticks;
            k *= m;
            k ^= k >> r;
            k *= m;

            ulong h = n;
            h ^= k;
            h *= m;

            return cast(size_t)h;
        }
    }
}

struct TickData
{
@nogc nothrow @safe:

    int opCmp(scope const TickData rhs) const pure scope
    {
        version (RelaxCompareTime)
        {
            return relaxCmp(this, rhs);
        }
        else
        {
            const lhsTicks = uticks;
            const rhsTicks = rhs.uticks;
            const result = (lhsTicks > rhsTicks) - (lhsTicks < rhsTicks);
            if (result == 0)
            {
                const lhsKind = internalKind;
                const rhsKind = rhs.internalKind;
                return (lhsKind > rhsKind) - (lhsKind < rhsKind);
            }
            else
                return result;
        }
    }

    bool opEquals(scope const TickData rhs) const pure scope
    {
        version (RelaxCompareTime)
            return relaxCmp(this, rhs) == 0;
        else
            return this.data == rhs.data;
    }

    //pragma(inline, true)
    static int relaxCmp(scope const TickData lhs, scope const TickData rhs) pure
    {
        const lhsTicks = lhs.uticks;
        const rhsTicks = rhs.uticks;
        const result = (lhsTicks > rhsTicks) - (lhsTicks < rhsTicks);
        if (result == 0)
        {
            const lhsKind = lhs.internalKind;
            const rhsKind = rhs.internalKind;
            if (lhsKind == kindUnspecified || rhsKind == kindUnspecified)
                return result;
            else
                return (lhsKind > rhsKind) - (lhsKind < rhsKind);
        }
        else
            return result;
    }

    pragma(inline, true)
    static TickData createDateTimeTick(ulong ticks, DateTimeKind kind) pure
    {
        return TickData((ticks & dateTimeTicksMask) | (cast(ulong)kind << kindShift));
    }

    pragma(inline, true)
    static TickData createTimeTick(ulong ticks, DateTimeKind kind) pure
    {
        return TickData((ticks & timeTicksMask) | (cast(ulong)kind << kindShift));
    }

    pragma(inline, true)
    size_t toHash() const pure scope
    {
        return Tick.toHash(data);
    }

    TickData toTickKind(DateTimeKind kind) const pure scope
    {
        return TickData(uticks | (cast(ulong)kind << kindShift));
    }

    pragma(inline, true)
    @property ulong internalKind() const pure scope
    {
        return data & flagsMask;
    }

    pragma(inline, true)
    @property DateTimeKind kind() const pure scope
    {
        const ik = internalKind;
        return ik == kindUnspecified
            ? DateTimeKind.unspecified
            : (ik == kindUtc ? DateTimeKind.utc : DateTimeKind.local);
    }

    pragma(inline, true)
    @property long sticks() const pure scope
    {
        return cast(long)(data & ticksMask);
    }

    pragma(inline, true)
    @property ulong uticks() const pure scope
    {
        return data & ticksMask;
    }

    enum ulong dateTimeTicksMask = 0x3FFF_FFFF_FFFF_FFFF;
    //enum long dateTimeTicksCeiling = 0x4000_0000_0000_0000;

    enum ulong timeTicksMask = 0xFF_FFFF_FFFF;

    enum ulong ticksMask = dateTimeTicksMask;
    enum ulong flagsMask = 0xC000_0000_0000_0000;
    enum ulong kindUnspecified = 0x0000_0000_0000_0000;
    enum ulong kindUtc = 0x4000_0000_0000_0000;
    enum ulong kindLocal = 0x8000_0000_0000_0000;
    //enum ulong kindLocalAmbiguousDst = 0xC000_0000_0000_0000;
    enum int kindShift = 62;

    ulong data;
}

enum CustomFormatSpecifier : char
{
    year = 'y',
    month = 'm',
    day = 'd',
    hour = 'h',
    minute = 'n',
    second = 's',
    fraction = 'z',
    amPm = 'a',
    separatorDate = '/',
    separatorTime = ':',
}

alias AmPmTexts = string[2];
alias DayOfWeekNames = string[7];
alias MonthNames = string[12];

struct DateTimeSetting
{
nothrow @safe:

    bool isValid() const @nogc pure
    {
        return (dayOfWeekNames !is null) && (monthNames !is null) && dateSeparator != 0 && timeSeparator != 0;
    }

    static DateTimeSetting us() @nogc
    {
        DateTimeSetting result;
        result.longDateFormat = "ddd, mmm dd, yyyy";
        result.longDateTimeFormat = "ddd, mmm dd, yyyy h:nn:ss a";
        result.longTimeFormat = "h:nn:ss a";
        result.shortDateFormat = "m/d/yyyy";
        result.shortDateTimeFormat = "m/d/yyyy h:nn a";
        result.shortTimeFormat = "h:nn a";
        result.dayOfWeekNames = &usDayOfWeekNames;
        result.monthNames = &usMonthNames;
        result.amPmTexts = &usAmPmTexts;
        result.dateSeparator = '/';
        result.timeSeparator = ':';
        return result;
    }

    string longDateFormat;
    string longDateTimeFormat;
    string longTimeFormat;
    string shortDateFormat;
    string shortDateTimeFormat;
    string shortTimeFormat;

    const(DayOfWeekNames)* dayOfWeekNames;
    const(MonthNames)* monthNames;
    const(AmPmTexts)* amPmTexts; /// Optional
    char dateSeparator = '/';
    char timeSeparator = ':';
}

enum ErrorOp : byte
{
    none,
    underflow,
    overflow,
}

enum ErrorPart : byte
{
    none,
    tick,
    millisecond,
    second,
    minute,
    hour,
    day,
    month,
    year,
    week,
    kind,
}

void checkTimeParts(int hour, int minute, int second, int millisecond) pure
{
    const e = isValidTimeParts(hour, minute, second, millisecond);
    if (e == ErrorPart.none)
        return;
    else if (e == ErrorPart.hour)
        throwOutOfRange!(ErrorPart.hour)(hour);
    else if (e == ErrorPart.minute)
        throwOutOfRange!(ErrorPart.minute)(minute);
    else if (e == ErrorPart.second)
        throwOutOfRange!(ErrorPart.second)(second);
    else if (e == ErrorPart.millisecond)
        throwOutOfRange!(ErrorPart.millisecond)(millisecond);
}

//pragma(inline, true)
ErrorPart isValidTimeParts(const int hour, const int minute, const int second, const int millisecond) @nogc nothrow pure
{
    if (hour < 0 || hour >= 24)
        return ErrorPart.hour;
    else if (minute < 0 || minute >= 60)
        return ErrorPart.minute;
    else if (second < 0 || second > 60 || (second == 60 && !Tick.s_systemSupportsLeapSeconds))
        return ErrorPart.second;
    else if (millisecond < 0 || millisecond >= Tick.millisPerSecond)
        return ErrorPart.millisecond;
    else
        return ErrorPart.none;
}

void throwArithmeticOutOfRange(ErrorPart error)(long outOfRangeValue) pure
{
    static if (error == ErrorPart.tick)
        throw new TimeException("Arithmetic ticks out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.millisecond)
        throw new TimeException("Arithmetic milliseconds out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.second)
        throw new TimeException("Arithmetic seconds out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.minute)
        throw new TimeException("Arithmetic minutes out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.hour)
        throw new TimeException("Arithmetic hours out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.day)
        throw new TimeException("Arithmetic days out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.month)
        throw new TimeException("Arithmetic months out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.year)
        throw new TimeException("Arithmetic years out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.year)
        throw new TimeException("Arithmetic weeks out of range: " ~ to!string(outOfRangeValue));
    else
        static assert(0);
}

void throwOutOfRange(ErrorPart error)(long outOfRangeValue) pure
{
    static if (error == ErrorPart.tick)
        throw new TimeException("Ticks out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.millisecond)
        throw new TimeException("Milliseconds out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.second)
        throw new TimeException("Seconds out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.minute)
        throw new TimeException("Minutes out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.hour)
        throw new TimeException("Hours out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.day)
        throw new TimeException("Days out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.month)
        throw new TimeException("Months out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.year)
        throw new TimeException("Years out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.week)
        throw new TimeException("Weeks out of range: " ~ to!string(outOfRangeValue));
    else static if (error == ErrorPart.kind)
        throw new TimeException("Kind out of range: " ~ to!string(outOfRangeValue));
    else
        static assert(0);
}

immutable AmPmTexts usAmPmTexts = ["AM", "PM"];

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

immutable DayOfWeekNames usShortDayOfWeekNames = [
    "Sun",
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat"
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

immutable MonthNames usShortMonthNames = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
    ];

DateTimeSetting dateTimeSetting;
__gshared DateTimeSetting sharedDateTimeSetting = DateTimeSetting.us();

package(pham.utl.datetime):

version (Windows)
long currentSystemTicksWindows(ClockType clockType = ClockType.normal)() @trusted
if (clockType == ClockType.coarse || clockType == ClockType.normal || clockType == ClockType.precise)
{
    import core.sys.windows.winbase : FILETIME, GetSystemTimeAsFileTime;
    import core.sys.windows.winnt : ULARGE_INTEGER;

    enum long hnsecsFrom1601 = 504_911_232_000_000_000L;

    FILETIME fileTime = void;
    GetSystemTimeAsFileTime(&fileTime);
    ULARGE_INTEGER ul = void;
    ul.HighPart = fileTime.dwHighDateTime;
    ul.LowPart = fileTime.dwLowDateTime;
    const ulong tempHNSecs = ul.QuadPart;
    assert(tempHNSecs <= long.max - hnsecsFrom1601);
    return cast(long)tempHNSecs + hnsecsFrom1601;
}

version (Posix)
long currentSystemTicksPosix(ClockType clockType = ClockType.normal)() @trusted
if (clockType == ClockType.coarse || clockType == ClockType.normal || clockType == ClockType.precise)
{
    import core.stdc.time;

    enum long hnsecsToUnixEpoch = 621_355_968_000_000_000L;

    version (Darwin)
    {
        import core.sys.posix.sys.time : gettimeofday, timeval;

        timeval tv = void;
        /*
        Posix gettimeofday called with a valid timeval address
        and a null second parameter doesn't fail.
        */
        gettimeofday(&tv, null);
        return convert!("seconds", "hnsecs")(tv.tv_sec) + tv.tv_usec * 10 + hnsecsToUnixEpoch;
    }
    else version (linux)
    {
        import core.sys.linux.time : CLOCK_REALTIME_COARSE;
        import core.sys.posix.time : clock_gettime, CLOCK_REALTIME;

        static if (clockType == ClockType.coarse)       alias clockArg = CLOCK_REALTIME_COARSE;
        else static if (clockType == ClockType.normal)  alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.precise) alias clockArg = CLOCK_REALTIME;
        else static assert(0);

        timespec ts = void;
        const error = clock_gettime(clockArg, &ts);
        /*
        Posix clock_gettime called with a valid address and valid clock_id is only
        permitted to fail if the number of seconds does not fit in time_t. If tv_sec
        is long or larger overflow won't happen before 292 billion years A.D.
        */
        assert(!error && ts.tv_sec.max < long.max);
        return convert!("seconds", "hnsecs")(ts.tv_sec) + ts.tv_nsec / 100 + hnsecsToUnixEpoch;
    }
    else version (FreeBSD)
    {
        import core.sys.freebsd.time : clock_gettime, CLOCK_REALTIME,
            CLOCK_REALTIME_FAST, CLOCK_REALTIME_PRECISE, CLOCK_SECOND;

        static if (clockType == ClockType.coarse)       alias clockArg = CLOCK_REALTIME_FAST;
        else static if (clockType == ClockType.normal)  alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.precise) alias clockArg = CLOCK_REALTIME_PRECISE;
        else static assert(0);

        timespec ts = void;
        const error = clock_gettime(clockArg, &ts);
        /*
        Posix clock_gettime called with a valid address and valid clock_id is only
        permitted to fail if the number of seconds does not fit in time_t. If tv_sec
        is long or larger overflow won't happen before 292 billion years A.D.
        */
        assert(!error && ts.tv_sec.max < long.max);
        return convert!("seconds", "hnsecs")(ts.tv_sec) + ts.tv_nsec / 100 + hnsecsToUnixEpoch;
    }
    else version (NetBSD)
    {
        import core.sys.netbsd.time : clock_gettime, CLOCK_REALTIME;

        timespec ts = void;
        const error = clock_gettime(CLOCK_REALTIME, &ts);
        /*
        Posix clock_gettime called with a valid address and valid clock_id is only
        permitted to fail if the number of seconds does not fit in time_t. If tv_sec
        is long or larger overflow won't happen before 292 billion years A.D.
        */
        assert(!error && ts.tv_sec.max < long.max);
        return convert!("seconds", "hnsecs")(ts.tv_sec) + ts.tv_nsec / 100 + hnsecsToUnixEpoch;
    }
    else version (OpenBSD)
    {
        import core.sys.openbsd.time : clock_gettime, CLOCK_REALTIME;

        static if (clockType == ClockType.coarse)       alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.normal)  alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.precise) alias clockArg = CLOCK_REALTIME;
        else static assert(0);

        timespec ts = void;
        const error = clock_gettime(clockArg, &ts);
        assert(!error && ts.tv_sec.max < long.max);
        return convert!("seconds", "hnsecs")(ts.tv_sec) + ts.tv_nsec / 100 + hnsecsToUnixEpoch;
    }
    else version (DragonFlyBSD)
    {
        import core.sys.dragonflybsd.time : clock_gettime, CLOCK_REALTIME,
            CLOCK_REALTIME_FAST, CLOCK_REALTIME_PRECISE, CLOCK_SECOND;

        static if (clockType == ClockType.coarse)       alias clockArg = CLOCK_REALTIME_FAST;
        else static if (clockType == ClockType.normal)  alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.precise) alias clockArg = CLOCK_REALTIME_PRECISE;
        else static assert(0);

        timespec ts = void;
        const error = clock_gettime(clockArg, &ts);
        /*
        Posix clock_gettime called with a valid address and valid clock_id is only
        permitted to fail if the number of seconds does not fit in time_t. If tv_sec
        is long or larger overflow won't happen before 292 billion years A.D.
        */
        assert(!error && ts.tv_sec.max < long.max);
        return convert!("seconds", "hnsecs")(ts.tv_sec) + ts.tv_nsec / 100 + hnsecsToUnixEpoch;
    }
    else version (Solaris)
    {
        import core.sys.solaris.time : clock_gettime, CLOCK_REALTIME;

        static if (clockType == ClockType.coarse)       alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.normal)  alias clockArg = CLOCK_REALTIME;
        else static if (clockType == ClockType.precise) alias clockArg = CLOCK_REALTIME;
        else static assert(0);

        timespec ts = void;
        const error = clock_gettime(clockArg, &ts);
        /*
        Posix clock_gettime called with a valid address and valid clock_id is only
        permitted to fail if the number of seconds does not fit in time_t. If tv_sec
        is long or larger overflow won't happen before 292 billion years A.D.
        */
        assert(!error && ts.tv_sec.max < long.max);
        return convert!("seconds", "hnsecs")(ts.tv_sec) + ts.tv_nsec / 100 + hnsecsToUnixEpoch;
    }
    else
        static assert(0, "Unsupported OS");
}


private:

static this() @trusted
{
    dateTimeSetting = sharedDateTimeSetting;
}
