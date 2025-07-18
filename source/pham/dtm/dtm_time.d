/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx694
 .
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.dtm.dtm_time;

import std.range.primitives : isOutputRange;
import std.traits : isSomeChar;

debug(debug_pham_dtm_dtm_time) import std.stdio : writeln;

import pham.utl.utl_array_static : ShortStringBuffer;
import pham.dtm.dtm_date : Date, DateTime, DayOfWeek, JulianDate;
import pham.dtm.dtm_date_time_format;
import pham.dtm.dtm_tick;
public import pham.dtm.dtm_tick : CustomFormatSpecifier, DateTimeKind, DateTimeSetting,
    dateTimeSetting, DateTimeZoneKind;
public import pham.dtm.dtm_time_zone : ZoneOffset;

@safe:

struct Time
{
@safe:

public:
    /**
     * Initializes a new instance of the Time structure from a tick count. The ticks
     * argument specifies the date as the number of 100-nanosecond intervals
     * that have elapsed since 00:00:00.0_000_000.
     */
    this(long ticks,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTicks(ticks) == ErrorOp.none);
    }
    do
    {
        this.data = TickData.createTime(ticks, kind);
    }

    this(scope const(Duration) time,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTicks(Tick.durationToTicks(time)) == ErrorOp.none);
    }
    do
    {
        this(Tick.durationToTicks(time), kind);
    }

    /**
     * Initializes a new instance of the Time structure to the specified hour, minute, second, and millisecond.
     */
    this(int hour, int minute, int second, int millisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, millisecond) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createTime(Tick.timeToTicks(hour, minute, second, millisecond), kind);
    }

    /**
     * Initializes a new instance of the Time structure to the specified hour, minute, second.
     */
    this(int hour, int minute, int second,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, 0) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createTime(Tick.timeToTicks(hour, minute, second), kind);
    }

    /**
     * Initializes a new instance of the Time structure to the specified hour, minute.
     */
    this(int hour, int minute,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTimeParts(hour, minute, 0, 0) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createTime(Tick.timeToTicks(hour, minute, 0), kind);
    }
    
    this(const(TickData) data) @nogc nothrow pure
    {
        this.data = data;
    }

    Time opBinary(string op)(scope const(Duration) duration) const @nogc nothrow pure scope
    if (op == "+" || op == "-")
    {
        const long ticks = Tick.durationToTicks(duration);
        static if (op == "+")
            return addTicks(ticks);
        else static if (op == "-")
            return addTicks(-ticks);
        else
            static assert(0);
    }

    TickSpan opBinary(string op)(scope const(Time) rhs) const @nogc nothrow pure scope
    if (op == "-")
    {
        return TickSpan(this.sticks - rhs.sticks);
    }

    int opCmp(scope const(Time) rhs) const @nogc nothrow pure scope
    {
        return data.opCmp(rhs.data);
    }

    bool opEquals(scope const(Time) rhs) const @nogc nothrow pure scope
    {
        return opCmp(rhs) == 0;
    }

    Time addBias(const(int) biasSign, const(int) biasHour, const(int) biasMinute) const @nogc nothrow pure
    in
    {
        assert(biasSign == +1 || biasSign == -1);
        assert(isValidTimeParts(biasHour, biasMinute, 0, 0) == ErrorPart.none);
    }
    do
    {
        return addMinutes(-biasSign * (biasHour * Tick.minutesPerHour + biasMinute));
    }

    /**
     * Adds the specified number of hours to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of hours represented by value.
     */
    Time addHours(double value) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerHour));
    }

    /**
     * Adds the specified number of hours to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of hours represented by value.
     * If the added value circulate though the day, this method will out the number of the circulated days.
     */
    Time addHours(const(double) value, out int wrappedDays) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerHour), wrappedDays);
    }

    /**
     * Adds the specified number of milliseconds to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of milliseconds represented by value.
     */
    Time addMilliseconds(const(double) value) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerMillisecond));
    }

    /**
     * Adds the specified number of milliseconds to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of milliseconds represented by value.
     * If the added value circulate though the day, this method will out the number of the circulated days.
     */
    Time addMilliseconds(const(double) value, out int wrappedDays) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerMillisecond), wrappedDays);
    }

    /**
     * Adds the specified number of minutes to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of minutes represented by value.
     */
    Time addMinutes(const(double) value) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerMinute));
    }

    /**
     * Adds the specified number of minutes to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of minutes represented by value.
     * If the added value circulate though the day, this method will out the number of the circulated days.
     */
    Time addMinutes(const(double) value, out int wrappedDays) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerMinute), wrappedDays);
    }

    /**
     * Adds the specified number of seconds to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of seconds represented by value.
     */
    Time addSeconds(const(double) value) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerSecond));
    }

    /**
     * Adds the specified number of seconds to the value of this instance.
     * and returns instance whose value is the sum of the time represented by this instance and
     * the number of seconds represented by value.
     * If the added value circulate though the day, this method will out the number of the circulated days.
     */
    Time addSeconds(const(double) value, out int wrappedDays) const @nogc nothrow pure
    {
        return addTicks(cast(long)(value * Tick.ticksPerSecond), wrappedDays);
    }

    Time addTicks(const(long) ticks) const @nogc nothrow pure
    {
        const long newTicks = (data.sticks + Tick.ticksPerDay + (ticks % Tick.ticksPerDay)) % Tick.ticksPerDay;
        final switch (isValidTicks(newTicks))
        {
            case ErrorOp.none:
                return Time(TickData.createTime(newTicks, data.internalKind));
            case ErrorOp.underflow:
                return Time(TickData.createTime(maxTicks, data.internalKind));
            case ErrorOp.overflow:
                return Time(TickData.createTime(minTicks, data.internalKind));
        }
    }

    Time addTicks(const(long) ticks, out int wrappedDays) const @nogc nothrow pure
    {
        wrappedDays = cast(int)(ticks / Tick.ticksPerDay);
        long newTicks = data.sticks + (ticks % Tick.ticksPerDay);
        if (newTicks < 0)
        {
            wrappedDays--;
            newTicks += Tick.ticksPerDay;
        }
        else if (newTicks >= Tick.ticksPerDay)
        {
            wrappedDays++;
            newTicks -= Tick.ticksPerDay;
        }
        return Time(TickData.createTime(newTicks, data.internalKind));
    }

    Time addTicksClamp(const(long) ticks) const @nogc nothrow pure
    {
        int wrappedDays = void;
        return addTicks(ticks, wrappedDays);
    }
    
    static Time createTime(long ticks,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        if (isValidTicks(ticks) != ErrorOp.none)
            throwOutOfRange!(ErrorPart.tick)(ticks);
        return Time(TickData.createTime(ticks, kind));
    }

    static Time createTime(int hour, int minute, int second, int millisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkTimeParts(hour, minute, second, millisecond);
        return Time(hour, minute, second, millisecond, kind);
    }

    static Time createTime(int hour, int minute, int second,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkTimeParts(hour, minute, second, 0);
        return Time(hour, minute, second, kind);
    }

    static Time createTime(int hour, int minute,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkTimeParts(hour, minute, 0, 0);
        return Time(hour, minute, 0, kind);
    }

    void getTime(out int hour, out int minute, out int second, out int millisecond) const @nogc nothrow pure
    {
        toDateTime().getTime(hour, minute, second, millisecond);
    }

    void getTimePrecise(out int hour, out int minute, out int second, out int tick) const @nogc nothrow pure
    {
        toDateTime().getTimePrecise(hour, minute, second, tick);
    }

    static ErrorOp isValidTicks(const(long) ticks) @nogc nothrow pure
    {
        return ticks < minTicks
            ? ErrorOp.underflow
            : (ticks > maxTicks ? ErrorOp.overflow : ErrorOp.none);
    }

    /**
     * Returns the equivalent DateTime of this instance. The resulting value
     * corresponds to this DateTime with the date part set to zero (Jan 1st year 1).
     */
    pragma(inline, true)
    DateTime toDateTime() const @nogc nothrow pure
    {
        return DateTime(data);
    }

    /**
     * Returns equivalent Duration of this instance
     */
    Duration toDuration() const @nogc nothrow pure
    {
        return Tick.durationFromTicks(data.sticks);
    }

    size_t toHash() const @nogc nothrow pure scope
    {
        return data.toHash();
    }

    string toString() const nothrow
    {
        ShortStringBuffer!char buffer;
        return toString(buffer).toString();
    }

    string toString(scope const(char)[] fmt) const
    {
        ShortStringBuffer!char buffer;
        return toString(buffer, fmt).toString();
    }

    string toString(scope const(char)[] fmt, scope ref DateTimeSetting setting) const
    {
        ShortStringBuffer!char buffer;
        return toString(buffer, fmt, setting).toString();
    }

    ref Writer toString(Writer, Char = char)(return ref Writer sink) const nothrow
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        auto fmtSpec = FormatDateTimeSpec!Char("%G");
        auto fmtValue = FormatDateTimeValue(this);
        formattedWrite(sink, fmtSpec, fmtValue);
        return sink;
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        auto fmtSpec = FormatDateTimeSpec!Char(fmt);
        auto fmtValue = FormatDateTimeValue(this);
        if (formattedWrite(sink, fmtSpec, fmtValue) == formatedWriteError)
            throw new FormatException(fmtSpec.errorMessage.idup);
        return sink;
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt, scope auto ref DateTimeSetting setting) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        auto fmtSpec = FormatDateTimeSpec!Char(fmt);
        auto fmtValue = FormatDateTimeValue(this);
        if (formattedWrite(sink, fmtSpec, fmtValue, setting) == formatedWriteError)
            throw new FormatException(fmtSpec.errorMessage.idup);
        return sink;
    }

    Time toUTC() const nothrow
    {
        auto dt = DateTime(Date.today, this);
        return dt.toUTC().time;
    }

    /**
     * Returns Time as requested parameter, kind, without any conversion/adjustment
     */
    Time asKind(DateTimeZoneKind kind) const @nogc nothrow pure scope
    {
        return Time(data.toTickKind(kind));
    }

    /**
     * Returns Time as UTC kind without any conversion/adjustment
     */
    @property Time asUTC() const @nogc nothrow pure scope
    {
        return Time(data.toTickKind(DateTimeZoneKind.utc));
    }

    /**
     * Returns the tick component of this instance. The returned value
     * is an integer between 0 and 9_999_999.
     */
    @property int fraction() const @nogc nothrow pure
    {
        return TickPart.fractionOf(data.sticks);
    }

    /**
     * Gets the hour component of the time represented by this instance.
     */
    @property int hour() const @nogc nothrow pure
    {
        return TickPart.hourOf(data.sticks);
    }

    /**
     * Returns JulianDay represented by this Time, the Date part is zero (Jan 1st year 1)
     * The $(HTTP en.wikipedia.org/wiki/Julian_day)
     */
    @property double julianDay() const @nogc nothrow pure
    {
        int h = void, n = void, s = void, f = void;
        getTime(h, n, s, f);
        return JulianDate.toJulianDay(1, 1, 1, h, n, s, f);
    }

    /**
     * Returns current time zone of this instance
     */
    @property DateTimeZoneKind kind() const @nogc nothrow pure
    {
        return data.kind;
    }

    /**
     * Gets the microsecond component of the time represented by this instance.
     * The returned value is an integer between 0 and 999_999.
     */
    @property int microsecond() const @nogc nothrow pure
    {
        return TickPart.tickToMicrosecond(fraction);
    }

    /**
     * Gets the millisecond component of the time represented by this instance.
     * The returned value is an integer between 0 and 999.
     */
    @property int millisecond() const @nogc nothrow pure
    {
        return TickPart.tickToMillisecond(fraction);
    }

    /*
     * Gets the minute component of the time represented by this instance.
     */
    @property int minute() const @nogc nothrow pure
    {
        return TickPart.minuteOf(data.sticks);
    }

    /**
     * Gets the second component of the time represented by this instance.
     */
    @property int second() const @nogc nothrow pure
    {
        return TickPart.secondOf(data.sticks);
    }

    /**
     * Returns the number of ticks that represent the time of this instance
     */
    pragma(inline, true)
    @property long sticks() const @nogc nothrow pure
    {
        return data.sticks;
    }

    ///dito
    pragma(inline, true)
    @property ulong uticks() const @nogc nothrow pure
    {
        return data.uticks;
    }

    /**
     * Returns the maximum Time value which is 23:59:59.9999999
     */
    @property static Time max() @nogc nothrow pure
    {
        return Time(TickData.createTime(maxTicks, DateTimeZoneKind.unspecified));
    }

    /**
     * Returns the minimum Time value which is midnight
     */
    @property static Time min() @nogc nothrow pure
    {
        return Time(TickData.createTime(minTicks, DateTimeZoneKind.unspecified));
    }

    /**
     * Returns a Time object that is set to the current time on this
     * computer, expressed as the local time
     */
    @property static Time now() nothrow
    {
        return DateTime.now.time;
    }

    /**
     * Returns the value of the current Time expressed in whole hours
     */
    pragma(inline, true)
    @property long totalHours() const @nogc nothrow pure
    {
        return TickSpan(data.sticks).totalHours!long();
    }

    /**
     * Returns the value of the current Time expressed in whole minutes
     */
    pragma(inline, true)
    @property long totalMinutes() const @nogc nothrow pure
    {
        return TickSpan(data.sticks).totalMinutes!long();
    }

    /**
     * Returns the value of the current Time expressed in whole seconds
     */
    pragma(inline, true)
    @property long totalSeconds() const @nogc nothrow pure
    {
        return TickSpan(data.sticks).totalSeconds!long();
    }

    /**
     * Returns the value of the current Time expressed in whole milliseconds
     */
    pragma(inline, true)
    @property long totalMilliseconds() const @nogc nothrow pure
    {
        return TickSpan(data.sticks).totalMilliseconds!long();
    }

    @property ZoneOffset utcBias() const nothrow
    {
        auto dt = DateTime(Date.today, this);
        return dt.utcBias;
    }

    /**
     * Returns a Time object that is set to the current time on this
     * computer, expressed as the Coordinated Universal Time (UTC)
     */
    @property static Time utcNow() @nogc nothrow
    {
        return DateTime.utcNow.time;
    }

    @property TickData raw() const @nogc nothrow pure
    {
        return data;
    }

    /**
     * Returns the midnight Time value which is midnight time 00:00:00.000 AM
     * Same as zero
     */
    alias midnight = min;

    /**
     * Returns the zero Time value which is midnight time 00:00:00.000 AM
     */
    alias zero = min;


public:
    // MinTimeTicks is the ticks for the midnight time 00:00:00.000 AM
    enum long minTicks = 0;

    // MaxTimeTicks is the max tick value for the time in the day.
    // It is calculated using DateTime.today.addTicks(-1).timeOfDay.ticks.
    enum long maxTicks = 863_999_999_999;

package(pham.dtm):
    void getDate(out int year, out int month, out int day) const @nogc nothrow pure
    {
        year = month = day = 0;
    }

private:
    TickData data;
}

alias TimeOfDay = Time;


// Any below codes are private
private:

unittest // time.contructor
{
    assert(Time(0L) == Time.init);
    assert(Time(0, 0, 0, 0) == Time.init);
    assert(Time(0, 0, 0) == Time.init);
    assert(Time(0, 0) == Time.init);

    Time t;

    t = Time(0L);
    assert(t.hour == 0);
    assert(t.minute == 0);
    assert(t.second == 0);
    assert(t.millisecond == 0);

    t = Time(0, 0, 0, 0);
    assert(t.hour == 0);
    assert(t.minute == 0);
    assert(t.second == 0);
    assert(t.millisecond == 0);

    t = Time(0, 0, 0);
    assert(t.hour == 0);
    assert(t.minute == 0);
    assert(t.second == 0);
    assert(t.millisecond == 0);

    t = Time(0, 0);
    assert(t.hour == 0);
    assert(t.minute == 0);
    assert(t.second == 0);
    assert(t.millisecond == 0);

    t = Time(12, 30, 33, 1);
    assert(t.hour == 12);
    assert(t.minute == 30);
    assert(t.second == 33);
    assert(t.millisecond == 1);

    t = Time(23, 59, 59, 1);
    assert(t.hour == 23);
    assert(t.minute == 59);
    assert(t.second == 59);
    assert(t.millisecond == 1);
}

unittest // Time.opCmp
{
    assert(Time(0, 0, 0).opCmp(Time.init) == 0);

    assert(Time(0, 0, 0).opCmp(Time(0, 0, 0)) == 0);
    assert(Time(12, 0, 0).opCmp(Time(12, 0, 0)) == 0);
    assert(Time(0, 30, 0).opCmp(Time(0, 30, 0)) == 0);
    assert(Time(0, 0, 33).opCmp(Time(0, 0, 33)) == 0);

    assert(Time(12, 30, 0).opCmp(Time(12, 30, 0)) == 0);
    assert(Time(12, 30, 33).opCmp(Time(12, 30, 33)) == 0);

    assert(Time(0, 30, 33).opCmp(Time(0, 30, 33)) == 0);
    assert(Time(0, 0, 33).opCmp(Time(0, 0, 33)) == 0);

    assert(Time(12, 30, 33).opCmp(Time(13, 30, 33)) < 0);
    assert(Time(13, 30, 33).opCmp(Time(12, 30, 33)) > 0);
    assert(Time(12, 30, 33).opCmp(Time(12, 31, 33)) < 0);
    assert(Time(12, 31, 33).opCmp(Time(12, 30, 33)) > 0);
    assert(Time(12, 30, 33).opCmp(Time(12, 30, 34)) < 0);
    assert(Time(12, 30, 34).opCmp(Time(12, 30, 33)) > 0);

    assert(Time(13, 30, 33).opCmp(Time(12, 30, 34)) > 0);
    assert(Time(12, 30, 34).opCmp(Time(13, 30, 33)) < 0);
    assert(Time(13, 30, 33).opCmp(Time(12, 31, 33)) > 0);
    assert(Time(12, 31, 33).opCmp(Time(13, 30, 33)) < 0);

    assert(Time(12, 31, 33).opCmp(Time(12, 30, 34)) > 0);
    assert(Time(12, 30, 34).opCmp(Time(12, 31, 33)) < 0);

    const t1 = Time(12, 30, 33);
    immutable t2 = Time(12, 30, 33);
    assert(t1.opCmp(t2) == 0);
    assert(t2.opCmp(t1) == 0);
}

unittest // Time.opEquals
{
    assert(Time(12, 30, 33, 1).opEquals(Time(12, 30, 33, 1)));
    assert(Time(12, 30, 33).opEquals(Time(12, 30, 33)));
    assert(Time(12, 30).opEquals(Time(12, 30)));

    assert(!Time(12, 30, 33, 1).opEquals(Time(1, 1, 1, 1)));
    assert(!Time.min.opEquals(Time.max));
}

unittest // Time.hour
{
    import std.conv : to;

    assert(Time.init.hour == 0);
    assert(Time(12, 0, 0).hour == 12);

    const t1 = Time(12, 0, 0);
    assert(t1.hour == 12);

    immutable t2 = Time(12, 0, 0);
    assert(t2.hour == 12);

    auto t3 = Time(0, 0, 0, 0).addHours(12);
    assert(t3 == Time(12, 0, 0, 0));

    int i4;
    auto t4 = Time(23, 59, 59, 999).addHours(1, i4);
    assert(t4 == Time(0, 59, 59, 999), t4.toString());
    assert(i4 == 1, to!string(i4));
}

unittest // Time.minute
{
    import std.conv : to;

    assert(Time.init.minute == 0);
    assert(Time(0, 30, 0).minute == 30);

    const t1 = Time(0, 30, 0);
    assert(t1.minute == 30);

    immutable t2 = Time(0, 30, 0);
    assert(t2.minute == 30);

    auto t3 = Time(0, 0, 0, 0).addMinutes(30);
    assert(t3 == Time(0, 30, 0, 0));

    int i4;
    auto t4 = Time(23, 59, 59, 999).addMinutes(2, i4);
    assert(t4 == Time(0, 1, 59, 999), t4.toString());
    assert(i4 == 1, to!string(i4));
}

unittest // Time.second
{
    import std.conv : to;

    assert(Time.init.second == 0);
    assert(Time(0, 0, 33).second == 33);

    const t1 = Time(0, 0, 33);
    assert(t1.second == 33);

    immutable t2 = Time(0, 0, 33);
    assert(t2.second == 33);

    auto t3 = Time(0, 0, 0, 0).addSeconds(33);
    assert(t3 == Time(0, 0, 33, 0));

    int i4;
    auto t4 = Time(23, 59, 59, 999).addSeconds(2, i4);
    assert(t4 == Time(0, 0, 1, 999), t4.toString());
    assert(i4 == 1, to!string(i4));
}

unittest // Time.millisecond
{
    import std.conv : to;

    assert(Time.init.millisecond == 0);
    assert(Time(0, 0, 0, 83).millisecond == 83);

    const t1 = Time(0, 0, 0, 83);
    assert(t1.millisecond == 83);

    immutable t2 = Time(0, 0, 0, 83);
    assert(t2.millisecond == 83);

    auto t3 = Time(0, 0, 0, 0).addMilliseconds(83);
    assert(t3 == Time(0, 0, 0, 83));

    int i4;
    auto t4 = Time(23, 59, 59, 999).addMilliseconds(2, i4);
    assert(t4 == Time(0, 0, 0, 1), t4.toString());
    assert(i4 == 1, to!string(i4));
}

unittest // Time.opBinary
{
    import core.time : dur, hours, minutes, seconds, msecs;

    assert(Time(12, 12, 12, 0) + hours(1) == Time(13, 12, 12, 0));
    assert(Time(12, 12, 12, 0) + minutes(1) == Time(12, 13, 12, 0));
    assert(Time(12, 12, 12, 0) + seconds(1) == Time(12, 12, 13, 0));
    assert(Time(12, 12, 12, 4) + msecs(1) == Time(12, 12, 12, 5));
    assert(Time(23, 59, 59, 0) + seconds(1) == Time(0, 0, 0, 0));

    assert(Time(12, 12, 12, 0) - hours(1) == Time(11, 12, 12, 0));
    assert(Time(12, 12, 12, 0) - minutes(1) == Time(12, 11, 12, 0));
    assert(Time(12, 12, 12, 0) - seconds(1) == Time(12, 12, 11, 0));
    assert(Time(12, 12, 12, 12) - msecs(1) == Time(12, 12, 12, 11));
    assert(Time(0, 0, 0, 0) - seconds(1) == Time(23, 59, 59, 0));

    assert(Time(12, 30, 33) + dur!"hours"(7) == Time(19, 30, 33));
    assert(Time(12, 30, 33) + dur!"hours"(-7) == Time(5, 30, 33));
    assert(Time(12, 30, 33) + dur!"minutes"(7) == Time(12, 37, 33));
    assert(Time(12, 30, 33) + dur!"minutes"(-7) == Time(12, 23, 33));
    assert(Time(12, 30, 33) + dur!"seconds"(7) == Time(12, 30, 40));
    assert(Time(12, 30, 33) + dur!"seconds"(-7) == Time(12, 30, 26));

    assert(Time(12, 30, 33) + dur!"msecs"(7000) == Time(12, 30, 40));
    assert(Time(12, 30, 33) + dur!"msecs"(-7000) == Time(12, 30, 26));
    assert(Time(12, 30, 33) + dur!"usecs"(7_000_000) == Time(12, 30, 40));
    assert(Time(12, 30, 33) + dur!"usecs"(-7_000_000) == Time(12, 30, 26));
    assert(Time(12, 30, 33) + dur!"hnsecs"(70_000_000) == Time(12, 30, 40));
    assert(Time(12, 30, 33) + dur!"hnsecs"(-70_000_000) == Time(12, 30, 26));

    assert(Time(12, 30, 33) - dur!"hours"(-7) == Time(19, 30, 33));
    assert(Time(12, 30, 33) - dur!"hours"(7) == Time(5, 30, 33));
    assert(Time(12, 30, 33) - dur!"minutes"(-7) == Time(12, 37, 33));
    assert(Time(12, 30, 33) - dur!"minutes"(7) == Time(12, 23, 33));
    assert(Time(12, 30, 33) - dur!"seconds"(-7) == Time(12, 30, 40));
    assert(Time(12, 30, 33) - dur!"seconds"(7) == Time(12, 30, 26));

    assert(Time(12, 30, 33) - dur!"msecs"(-7000) == Time(12, 30, 40));
    assert(Time(12, 30, 33) - dur!"msecs"(7000) == Time(12, 30, 26));
    assert(Time(12, 30, 33) - dur!"usecs"(-7_000_000) == Time(12, 30, 40));
    assert(Time(12, 30, 33) - dur!"usecs"(7_000_000) == Time(12, 30, 26));
    assert(Time(12, 30, 33) - dur!"hnsecs"(-70_000_000) == Time(12, 30, 40));
    assert(Time(12, 30, 33) - dur!"hnsecs"(70_000_000) == Time(12, 30, 26));

    auto duration = dur!"hours"(11);
    assert(Time(12, 30, 33) + duration == Time(23, 30, 33));
    assert(Time(12, 30, 33) - duration == Time(1, 30, 33));

    const ctod = Time(12, 30, 33);
    assert(ctod + duration == Time(23, 30, 33));
    assert(ctod - duration == Time(1, 30, 33));

    immutable itod = Time(12, 30, 33);
    assert(itod + duration == Time(23, 30, 33));
    assert(itod - duration == Time(1, 30, 33));
}

unittest // Time.opBinary
{
    import core.time : dur;
    import std.conv : to;

    static string toString(ubyte decimals = 4)(const(double) n) nothrow pure
    {
        import std.conv : to;
        import std.format : format;

        scope (failure) assert(0, "Assume nothrow");

        static immutable string fmt = "%." ~ decimals.to!string ~ "f";
        return format(fmt, n);
    }

    static bool approxEqual(ubyte decimals = 4)(const(double) lhs, const(double) rhs) nothrow pure
    {
        import std.conv : to;
        import std.math.operations : isClose;

        enum maxRelDiff = ("1e-" ~ decimals.to!string).to!double;
        return isClose(lhs, rhs, maxRelDiff);
    }

    auto d = Time(7, 12, 52) - Time(12, 30, 33);
    assert(d.toDuration == dur!"seconds"(-19_061), d.toDuration.toString ~ " vs " ~ dur!"seconds"(-19_061).toString);
    assert((Time(12, 30, 33) - Time(7, 12, 52)).toDuration == dur!"seconds"(19_061));
    assert((Time(12, 30, 33) - Time(14, 30, 33)).toDuration == dur!"seconds"(-7200));
    assert((Time(14, 30, 33) - Time(12, 30, 33)).toDuration == dur!"seconds"(7200));
    assert((Time(12, 30, 33) - Time(12, 34, 33)).toDuration == dur!"seconds"(-240));
    assert((Time(12, 34, 33) - Time(12, 30, 33)).toDuration == dur!"seconds"(240));
    assert((Time(12, 30, 33) - Time(12, 30, 34)).toDuration == dur!"seconds"(-1));
    assert((Time(12, 30, 34) - Time(12, 30, 33)).toDuration == dur!"seconds"(1));

    auto tod = Time(12, 30, 33);
    const ctod = Time(12, 30, 33);
    immutable itod = TimeOfDay(12, 30, 33);
    assert((tod - tod).toDuration == Duration.zero);
    assert((tod - ctod).toDuration == Duration.zero);
    assert((tod - itod).toDuration == Duration.zero);
    assert((ctod - ctod).toDuration == Duration.zero);
    assert((ctod - tod).toDuration == Duration.zero);
    assert((ctod - itod).toDuration == Duration.zero);
    assert((itod - tod).toDuration == Duration.zero);
    assert((itod - ctod).toDuration == Duration.zero);
    assert((itod - itod).toDuration == Duration.zero);

	auto preTime = Time(0, 0, 0);
    auto nowTime = Time(19, 22, 7);
    assert(approxEqual!15((nowTime - preTime).totalDays, 0.807025462962963), toString!15((nowTime - preTime).totalDays));
    assert(approxEqual!13((nowTime - preTime).totalHours, 19.3686111111111), toString!13((nowTime - preTime).totalHours));
    assert(approxEqual!11((nowTime - preTime).totalMinutes, 1_162.11666666667), toString!11((nowTime - preTime).totalMinutes));
    assert((nowTime - preTime).totalSeconds == 69_727, (nowTime - preTime).totalSeconds.to!string);
    assert((nowTime - preTime).totalMilliseconds == 69_727_000, (nowTime - preTime).totalMilliseconds.to!string);
    assert((nowTime - preTime).totalTicks == 697_270_000_000, (nowTime - preTime).totalTicks.to!string);
}

unittest // Time.min
{
    assert(Time.min.hour == 0);
    assert(Time.min.minute == 0);
    assert(Time.min.second == 0);
    assert(Time.min.millisecond == 0);
}

unittest // Time.max
{
    assert(Time.max.hour == 23);
    assert(Time.max.minute == 59);
    assert(Time.max.second == 59);
    assert(Time.max.millisecond == 999);

    assert(Time.min < Time.max);
    assert(Time.max > Time.min);
}

unittest // DateTime.addBias
{
    auto t = Time(11, 0, 0, 1);
    assert(t.addBias(1, 1, 5) == Time(9, 55, 0, 1), t.addBias(1, 1, 5).toString());
    assert(t.addBias(-1, 1, 5) == Time(12, 5, 0, 1), t.addBias(-1, 1, 5).toString());
}

unittest // Time.toDateTime
{
    assert(Time(11, 0, 0, 1).toDateTime() == DateTime(1, 1, 1, 11, 0, 0, 1));
}

unittest // Time.toDuration
{
    assert(Time(0, 0, 0, 0).toDuration() == Duration.zero);
}

unittest // Time.toHash
{
    import std.conv : to;
    
    assert(Time(0, 0, 0, 0).toHash() == 0, Time(0, 0, 0, 0).raw.data.to!string ~ "," ~ Time(0, 0, 0, 0).toHash().to!string);
}

unittest // Time.toString
{
    assert(Time.max.toString() == "11:59:59 PM", Time.max.toString());

    assert(Time(0, 0, 0).toString() == "0:00:00 AM", Time(0, 0, 0).toString());
    assert(Time(12, 30, 33).toString() == "12:30:33 PM", Time(12, 30, 33).toString());

    auto tod = Time(12, 30, 33);
    assert(tod.toString() == "12:30:33 PM", tod.toString());

    const ctod = Time(12, 30, 33);
    assert(ctod.toString() == "12:30:33 PM", ctod.toString());

    immutable itod = Time(12, 30, 33);
    assert(itod.toString() == "12:30:33 PM", itod.toString());

    auto fmt = "%G";
    auto setting = DateTimeSetting.us;
    assert(Time(12, 30, 33).toString(fmt) == "12:30:33 PM");
    assert(Time(12, 30, 33).toString(fmt, setting) == "12:30:33 PM");
    
    import pham.utl.utl_array_append : Appender;
    import std.exception : assertThrown;
    
    Appender!(char[]) buffer;
    assertThrown!FormatException(Time(12, 30, 33).toString(buffer, "%X"));
    assertThrown!FormatException(Time(12, 30, 33).toString(buffer, "%X", DateTimeSetting.us));        
}

unittest // Time.createTime
{
    import std.exception : assertThrown;

    auto t1 = Time.createTime(0);
    auto t2 = Time.createTime(0, 0, 0, 100);
    auto t3 = Time.createTime(0, 0, 20);
    auto t4 = Time.createTime(0, 20);
    auto t5 = Time.createTime(20, 0);

    assertThrown!TimeException(Time.createTime(-1L));
    assertThrown!TimeException(Time.createTime(Time.maxTicks + 1));
    assertThrown!TimeException(Time.createTime(24, 1, 1, 1));
    assertThrown!TimeException(Time.createTime(1, 60, 1));
    assertThrown!TimeException(Time.createTime(1, 1, 61));
    assertThrown!TimeException(Time.createTime(1, 60));
}

unittest // Time.julianDay
{
    import std.conv : to;

    assert(Tick.round(Time(0, 0, 0, 0).julianDay) == 1721424, Tick.round(Time(0, 0, 0, 0).julianDay).to!string());
    assert(Tick.round(Time(11, 59, 59, 999).julianDay) == 1721424, Tick.round(Time(11, 59, 59, 999).julianDay).to!string());
    assert(Tick.round(Time(12, 0, 0, 0).julianDay) == 1721424, Tick.round(Time(12, 0, 0, 0).julianDay).to!string());
    assert(Tick.round(Time(23, 59, 59, 999).julianDay) == 1721424, Tick.round(Time(23, 59, 59, 999).julianDay).to!string());
}

unittest // Time.getTime
{
    int h, m, s, ms;

    Time(0, 0, 0, 0).getTime(h, m, s, ms);
    assert(h == 0);
    assert(m == 0);
    assert(s == 0);
    assert(ms == 0);

    Time(11, 59, 59, 999).getTime(h, m, s, ms);
    assert(h == 11);
    assert(m == 59);
    assert(s == 59);
    assert(ms == 999);

    Time(12, 0, 0, 0).getTime(h, m, s, ms);
    assert(h == 12);
    assert(m == 0);
    assert(s == 0);
    assert(ms == 0);

    Time(23, 59, 59, 999).getTime(h, m, s, ms);
    assert(h == 23);
    assert(m == 59);
    assert(s == 59);
    assert(ms == 999);
}

unittest // Time.getTimePrecise
{
    int h, m, s, t;

    Time(0, 0, 0, 0).getTimePrecise(h, m, s, t);
    assert(h == 0);
    assert(m == 0);
    assert(s == 0);
    assert(t == 0);

    Time(11, 59, 59, 59).getTimePrecise(h, m, s, t);
    assert(h == 11);
    assert(m == 59);
    assert(s == 59);
    assert(t == 59 * Tick.ticksPerMillisecond);

    Time(12, 0, 0, 0).getTimePrecise(h, m, s, t);
    assert(h == 12);
    assert(m == 0);
    assert(s == 0);
    assert(t == 0);

    Time(23, 59, 59, 999).getTimePrecise(h, m, s, t);
    assert(h == 23);
    assert(m == 59);
    assert(s == 59);
    assert(t == 999 * Tick.ticksPerMillisecond);
}
