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

module pham.dtm.dtm_tick;

import core.sync.mutex : Mutex;
import core.time : ClockType, convert;
public import core.time : dur, Duration, TimeException;
import std.conv : to;
import std.traits : isIntegral;

import pham.utl.utl_result : cmp, ResultIf;

version = RelaxCompareTime;

@safe:

/**
 * Custom format specifiers for Date, DateTime & Time
 */
enum CustomFormatSpecifier : char
{
    year = 'y',
    month = 'm',
    day = 'd',
    longHour = 'H', // 0..23
    shortHour = 'h', // 0..11
    minute = 'n',
    second = 's',
    fraction = 'z', // Millisecond [zzz], 100-nanosecond [zzzzzzz]
    amPm = 'a', // For US, they are AM or PM used with short hour format
    separatorDate = '/',
    separatorTime = ':',
}

alias AmPmTexts = string[2];
alias DayOfWeekNames = string[7];
alias MonthNames = string[12];

enum DayOfWeek : ubyte
{
    sunday = 0,
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
}

enum firstDayOfMonth = 1;

enum firstDayOfWeek = DayOfWeek.sunday;

/**
 * Aggregate format settings for Date, DateTime & Time object
 */
struct DateTimeKindFormat
{
nothrow @safe:

    string date;
    string dateTime;
    string time;
}

struct DateTimeSetting
{
nothrow @safe:

    /**
     * Returns true if this DateTimeSetting is in valid state
     */
    bool isValid() const @nogc pure scope
    {
        return fullDayOfWeekNames !is null && shortDayOfWeekNames !is null
            && fullMonthNames !is null && shortMonthNames !is null
            && dateSeparator != 0 && timeSeparator != 0;
    }

    /**
     * Default DateTimeSetting for US
     */
    static DateTimeSetting us() @nogc pure
    {
        DateTimeSetting result;

        result.generalLongFormat.date = "mm/dd/yyyy";
        result.generalLongFormat.dateTime = "mm/dd/yyyy h:nn:ss a";
        result.generalLongFormat.time = "h:nn:ss a";

        result.generalShortFormat.date = "m/d/yyyy";
        result.generalShortFormat.dateTime = "m/d/yyyy h:nn a";
        result.generalShortFormat.time = "h:nn a";

        result.longFormat.date = "ddd, mmm dd, yyyy";
        result.longFormat.dateTime = "ddd, mmm dd, yyyy h:nn:ss a";
        result.longFormat.time = "h:nn:ss a";

        result.shortFormat.date = "m/d/yyyy";
        result.shortFormat.dateTime = "m/d/yyyy h:nn a";
        result.shortFormat.time = "h:nn a";

        result.fullDayOfWeekNames = &usFullDayOfWeekNames;
        result.shortDayOfWeekNames = &usShortDayOfWeekNames;

        result.fullMonthNames = &usFullMonthNames;
        result.shortMonthNames = &usShortMonthNames;

        result.amPmTexts = &usAmPmTexts;
        result.dateSeparator = '/';
        result.timeSeparator = ':';

        return result;
    }

    DateTimeKindFormat generalLongFormat;
    DateTimeKindFormat generalShortFormat;
    DateTimeKindFormat longFormat;
    DateTimeKindFormat shortFormat;
    const(DayOfWeekNames)* fullDayOfWeekNames;
    const(DayOfWeekNames)* shortDayOfWeekNames;
    const(MonthNames)* fullMonthNames;
    const(MonthNames)* shortMonthNames;
    const(AmPmTexts)* amPmTexts; /// Optional
    char dateSeparator = '/';
    char timeSeparator = ':';
}

/**
 * Specifies an operation/container is for Date, DateTime or Time object
 */
enum DateTimeKind : ubyte
{
    date,
    dateTime,
    time,
}

/**
 * Specifies whether a DateTime & Time object represents a local time,
 * a Coordinated Universal Time (UTC), or is not specified as either local time or UTC
 */
enum DateTimeZoneKind : ubyte
{
    unspecified = 0,
    utc = 1,
    local = 2,
}

struct Tick
{
@nogc nothrow @safe:

    enum bool s_systemSupportsLeapSeconds = false;

    // Number of 100ns ticks per time unit
    enum long ticksPerMicrosecond = 10;
    enum long ticksPerMillisecond = 10_000; // hnsecs
    enum long ticksPerSecond = ticksPerMillisecond * 1_000; //      10_000_000
    enum long ticksPerMinute = ticksPerSecond * 60;         //     600_000_000
    enum long ticksPerHour = ticksPerMinute * 60;           //  36,000,000,000
    enum long ticksPerDay = ticksPerHour * 24;              // 864,000,000,000
    enum int  ticksMaxPrecision = 7;                        // 999 * ticksPerMillisecond = 7 digits

    enum int hoursPerDay = 24;

    enum int minutesPerHour = 60;
    enum int minutesPerDay = minutesPerHour * hoursPerDay;

    enum int secondsPerMinute = 60;
    enum int secondsPerDay = secondsPerMinute * minutesPerDay;

    // Number of milliseconds per time unit
    enum int millisPerSecond = 1_000;
    enum int millisPerMinute = millisPerSecond * secondsPerMinute;
    enum int millisPerHour = millisPerMinute * minutesPerHour;
    enum int millisPerDay = millisPerHour * hoursPerDay;
    enum int millisMaxPrecision = 3;

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
            static assert(0, "Unsupport system for " ~ __FUNCTION__);
    }

    pragma(inline, true)
    static Duration durationFromSystemBias(long biasMinute) pure
    {
        return biasMinute != 0 ? dur!"minutes"(-biasMinute) : Duration.zero;
    }

    pragma(inline, true)
    static Duration durationFromTicks(long ticks) pure
    {
        return dur!"hnsecs"(ticks);
    }

    pragma(inline, true)
    static long durationToTicks(scope const(Duration) duration) pure
    {
        return duration.total!"hnsecs"();
    }

    static long round(const(double) d) pure
    {
        const r = d >= 0.0 ? 0.5 : -0.5;
        return cast(long)(d + r);
    }

    pragma(inline, true)
    static ulong timeToTicks(int hour, int minute, int second) pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, 0) == ErrorPart.none);
    }
    do
    {
        const ulong totalSeconds = (cast(ulong)hour * 3_600) + (minute * 60) + second;
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
            enum ulong m = 0xC6A4_A793_5BD1_E995UL;
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

/**
 * 100-nanosecond intervals precision for DateTime & Time
 */
struct TickData
{
@nogc nothrow @safe:

    int opCmp(scope const(TickData) rhs) const pure scope
    {
        version (RelaxCompareTime)
        {
            const result = cmp(this.uticks, rhs.uticks);
            if (result == 0)
            {
                const lhsKind = this.internalKind;
                const rhsKind = rhs.internalKind;
                if (!isCompatibleKind(lhsKind, rhsKind))
                    return cmp(lhsKind, rhsKind);
            }
            return result;
        }
        else
        {
            const result = cmp(this.uticks, rhs.uticks);
            return result == 0 ? cmp(this.internalKind, rhs.internalKind) : result;
        }
    }

    bool opEquals(scope const(TickData) rhs) const pure scope
    {
        version (RelaxCompareTime)
            return opCmp(rhs) == 0;
        else
            return this.data == rhs.data;
    }

    pragma(inline, true)
    static TickData createDateTimeTick(ulong ticks, DateTimeZoneKind kind) pure
    {
        return TickData((ticks & dateTimeTicksMask) | (cast(ulong)kind << kindShift));
    }

    pragma(inline, true)
    static TickData createTimeTick(ulong ticks, DateTimeZoneKind kind) pure
    {
        return TickData((ticks & timeTicksMask) | (cast(ulong)kind << kindShift));
    }

    pragma(inline, true)
    static bool isCompatibleKind(const(DateTimeZoneKind) lhs, const(DateTimeZoneKind) rhs) pure
    {
        // Unspecified ~ Local
        // UTC != Local
        // UTC != Unspecified
        return (lhs == rhs)
            || (lhs != DateTimeZoneKind.utc && rhs != DateTimeZoneKind.utc);
    }

    pragma(inline, true)
    static bool isCompatibleKind(const(ulong) lhsInternalKind, const(ulong) rhsInternalKind) pure
    {
        // Unspecified ~ Local
        // UTC != Local
        // UTC != Unspecified
        return (lhsInternalKind == rhsInternalKind)
            || (lhsInternalKind != kindUtc && rhsInternalKind != kindUtc);
    }

    pragma(inline, true)
    size_t toHash() const pure scope
    {
        return Tick.toHash(data);
    }

    TickData toTickKind(DateTimeZoneKind kind) const pure scope
    {
        return TickData(uticks | (cast(ulong)kind << kindShift));
    }

    pragma(inline, true)
    @property ulong internalKind() const pure scope
    {
        return data & flagsMask;
    }

    pragma(inline, true)
    @property DateTimeZoneKind kind() const pure scope
    {
        const ik = internalKind;
        return ik == kindUnspecified
            ? DateTimeZoneKind.unspecified
            : (ik == kindUtc ? DateTimeZoneKind.utc : DateTimeZoneKind.local);
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

    //enum long dateTimeTicksCeiling = 0x4000_0000_0000_0000;
    enum ulong dateTimeTicksMask = 0x3FFF_FFFF_FFFF_FFFF;
    enum ulong timeTicksMask = 0x00FF_FFFF_FFFF;
    enum ulong ticksMask = dateTimeTicksMask;
    enum ulong flagsMask = 0xC000_0000_0000_0000;
    enum ulong kindUnspecified = 0x0000_0000_0000_0000;
    enum ulong kindUtc = 0x4000_0000_0000_0000;
    enum ulong kindLocal = 0x8000_0000_0000_0000;
    //enum ulong kindLocalAmbiguousDst = 0xC000_0000_0000_0000;
    enum int kindShift = 62;

    ulong data;
}

struct TickPart
{
@nogc nothrow @safe:

    pragma(inline, true)
    static int microsecondToTick(int microsecond) pure
    in
    {
        assert(microsecond >= -999_999 && microsecond <= 999_999);
    }
    do
    {
        return cast(int)(microsecond * Tick.ticksPerMicrosecond);
    }

    pragma(inline, true)
    static int millisecondToMicrosecond(int millisecond) pure
    in
    {
        assert(millisecond >= -999 && millisecond <= 999);
    }
    do
    {
        return millisecond * 1_000;
    }

    pragma(inline, true)
    static int millisecondToTick(int millisecond) pure
    in
    {
        assert(millisecond >= -999 && millisecond <= 999);
    }
    do
    {
        return cast(int)(millisecond * Tick.ticksPerMillisecond);
    }

    pragma(inline, true)
    static int tickToMicrosecond(int tick) pure
    in
    {
        assert(tick >= -9_999_999 && tick <= 9_999_999);
    }
    do
    {
        return tick / Tick.ticksPerMicrosecond;
    }

    pragma(inline, true)
    static int tickToMillisecond(int tick) pure
    in
    {
        assert(tick >= -9_999_999 && tick <= 9_999_999);
    }
    do
    {
        return tick / Tick.ticksPerMillisecond;
    }
}

/**
 * Indicators the result of an operation
 *   none = no error taken place
 *   underflow = result of an operation is underflow
 *   overflow = result of an operation is overflow
 */
enum ErrorOp : ubyte
{
    none,
    underflow,
    overflow,
}

/**
 * Specifies the part of a Date, DateTime, Time having an error
 */
enum ErrorPart : ubyte
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
ErrorPart isValidTimeParts(const(int) hour, const(int) minute, const(int) second, const(int) millisecond) @nogc nothrow pure
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
        throw new TimeException("Arithmetic ticks out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.millisecond)
        throw new TimeException("Arithmetic milliseconds out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.second)
        throw new TimeException("Arithmetic seconds out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.minute)
        throw new TimeException("Arithmetic minutes out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.hour)
        throw new TimeException("Arithmetic hours out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.day)
        throw new TimeException("Arithmetic days out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.month)
        throw new TimeException("Arithmetic months out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.year)
        throw new TimeException("Arithmetic years out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.year)
        throw new TimeException("Arithmetic weeks out of range: " ~ outOfRangeValue.to!string());
    else
        static assert(0);
}

void throwOutOfRange(ErrorPart error)(long outOfRangeValue) pure
{
    static if (error == ErrorPart.tick)
        throw new TimeException("Ticks out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.millisecond)
        throw new TimeException("Milliseconds out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.second)
        throw new TimeException("Seconds out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.minute)
        throw new TimeException("Minutes out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.hour)
        throw new TimeException("Hours out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.day)
        throw new TimeException("Days out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.month)
        throw new TimeException("Months out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.year)
        throw new TimeException("Years out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.week)
        throw new TimeException("Weeks out of range: " ~ outOfRangeValue.to!string());
    else static if (error == ErrorPart.kind)
        throw new TimeException("Kind out of range: " ~ outOfRangeValue.to!string());
    else
        static assert(0);
}

static immutable AmPmTexts usAmPmTexts = ["AM", "PM"];

// Must match order of DayOfWeek
static immutable DayOfWeekNames usFullDayOfWeekNames = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    ];

static immutable DayOfWeekNames usShortDayOfWeekNames = [
    "Sun",
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    ];

/**
 * Convert date of week name into DayOfWeek enum
 * Params:
 *   dowName = day of week name to be converted
 *   shortDayOfWeekNames = array[0..7] of valid and in-order short week names
 *   fullDayOfWeekNames = array[0..7] of valid and in-order full week names
 * Returns:
 *   ResultIf!DayOfWeek
 */
ResultIf!DayOfWeek toDayOfWeek(string dowName, scope const(DayOfWeekNames) shortDayOfWeekNames, scope const(DayOfWeekNames) fullDayOfWeekNames) @nogc nothrow pure
{
    import std.uni : sicmp;

    if (dowName.length)
    {
        foreach (i; 0..shortDayOfWeekNames.length)
        {
            if (sicmp(shortDayOfWeekNames[i], dowName) == 0)
                return ResultIf!DayOfWeek.ok(cast(DayOfWeek)i);
        }

        foreach (i; 0..fullDayOfWeekNames.length)
        {
            if (sicmp(fullDayOfWeekNames[i], dowName) == 0)
                return ResultIf!DayOfWeek.ok(cast(DayOfWeek)i);
        }
    }

    return ResultIf!DayOfWeek.error(1, dowName);
}

/**
 * Convert date of week name (US Names) into DayOfWeek enum
 * Params:
 *   dowName = day of week name to be converted
 * Returns:
 *   ResultIf!DayOfWeek
 */
ResultIf!DayOfWeek toDayOfWeekUS(string dowName) @nogc nothrow pure
{
    return toDayOfWeek(dowName, usShortDayOfWeekNames, usFullDayOfWeekNames);
}

// Must match order of Month
static immutable MonthNames usFullMonthNames = [
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

static immutable MonthNames usShortMonthNames = [
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
    "Dec",
    ];

/**
 * Convert month name into `int` month value [1..12]
 * Params:
 *   monthName = month name to be converted
 *   shortMonthNames = array[0..12] of valid and in-order short month names
 *   fullMonthNames = array[0..12] of valid and in-order full month names
 * Returns:
 *   ResultIf!int
 */
ResultIf!int toMonth(string monthName, scope const(MonthNames) shortMonthNames, scope const(MonthNames) fullMonthNames) @nogc nothrow pure
{
    import std.uni : sicmp;

    if (monthName.length)
    {
        foreach (i; 0..shortMonthNames.length)
        {
            if (sicmp(shortMonthNames[i], monthName) == 0)
                return ResultIf!int.ok(cast(int)i + 1);
        }

        foreach (i; 0..fullMonthNames.length)
        {
            if (sicmp(fullMonthNames[i], monthName) == 0)
                return ResultIf!int.ok(cast(int)i + 1);
        }
    }

    return ResultIf!int.error(1, monthName);
}

/**
 * Convert month name (US Names) into `int` month value [1..12]
 * Params:
 *   monthName = month name to be converted
 * Returns:
 *   ResultIf!int
 */
ResultIf!int toMonthUS(string monthName) @nogc nothrow pure
{
    return toMonth(monthName, usShortMonthNames, usFullMonthNames);
}

DateTimeSetting dateTimeSetting;
__gshared DateTimeSetting sharedDateTimeSetting = DateTimeSetting.us();


package(pham.dtm):

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
        static assert(0, "Unsupport system for " ~ __FUNCTION__);
}

__gshared static Mutex tdMutex;


private:

shared static this() nothrow @trusted
{
    tdMutex = new Mutex();
}

shared static ~this() nothrow @trusted
{
    if (tdMutex !is null)
    {
        tdMutex.destroy();
        tdMutex = null;
    }
}

static this() nothrow @trusted
{
    dateTimeSetting = sharedDateTimeSetting;
}

version (none)
unittest // Show duration precision
{
    import pham.utl.utl_test;

    auto d = dur!"seconds"(1);
    dgWriteln("1 second in msecs:  ", d.total!"msecs"().dgToStr());  //         1_000
    dgWriteln("1 second in usecs:  ", d.total!"usecs"().dgToStr());  //     1_000_000
    dgWriteln("1 second in hnsecs: ", d.total!"hnsecs"().dgToStr()); //    10_000_000
    dgWriteln("1 second in nsecs:  ", d.total!"nsecs"().dgToStr());  // 1_000_000_000

    d = dur!"msecs"(999);
    dgWriteln("999 msecs in usecs:  ", d.total!"usecs"().dgToStr());  //     999_000
    dgWriteln("999 msecs in hnsecs: ", d.total!"hnsecs"().dgToStr()); //   9_990_000
    dgWriteln("999 msecs in nsecs:  ", d.total!"nsecs"().dgToStr());  // 999_000_000
}

unittest // toDayOfWeekUS
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.dtm.tick.toDayOfWeekUS");

    assert(toDayOfWeekUS("sunday").value == DayOfWeek.sunday);
    assert(toDayOfWeekUS("monday").value == DayOfWeek.monday);
    assert(toDayOfWeekUS("sun").value == DayOfWeek.sunday);
    assert(toDayOfWeekUS("mon").value == DayOfWeek.monday);

    foreach (i, m; usShortDayOfWeekNames)
    {
        assert(toDayOfWeekUS(m).value == i);
    }

    foreach (i, m; usFullDayOfWeekNames)
    {
        assert(toDayOfWeekUS(m).value == i);
    }

    assert(!toDayOfWeekUS(""));
    assert(!toDayOfWeekUS(" "));
    assert(!toDayOfWeekUS("0"));
    assert(!toDayOfWeekUS("1"));
    assert(!toDayOfWeekUS("what"));
}

unittest // toMonthUS
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.dtm.tick.toMonthUS");

    assert(toMonthUS("january").value == 1);
    assert(toMonthUS("december").value == 12);
    assert(toMonthUS("jan").value == 1);
    assert(toMonthUS("dec").value == 12);

    foreach (i, m; usShortMonthNames)
    {
        assert(toMonthUS(m).value == i + 1);
    }

    foreach (i, m; usFullMonthNames)
    {
        assert(toMonthUS(m).value == i + 1);
    }

    assert(!toMonthUS(""));
    assert(!toMonthUS(" "));
    assert(!toMonthUS("0"));
    assert(!toMonthUS("-1"));
    assert(!toMonthUS("13"));
}
