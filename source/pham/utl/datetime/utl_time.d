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

module pham.utl.datetime.time;

import std.range.primitives : isOutputRange;
import std.traits : isSomeChar;

import pham.utl.utf8 : ShortStringBuffer;
import pham.utl.datetime.date : DateTime, DayOfWeek;
import pham.utl.datetime.tick;

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
        DateTimeKind kind = DateTimeKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTicks(ticks) == ErrorOp.none);
    }
    do
    {
        this.data = TickData.createTimeTick(cast(ulong)ticks, kind);
    }

    this(scope const(Duration) time,
        DateTimeKind kind = DateTimeKind.unspecified) @nogc nothrow pure
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
        DateTimeKind kind = DateTimeKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, millisecond) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createTimeTick(Tick.timeToTicks(hour, minute, second, millisecond), kind);
    }

    /**
     * Initializes a new instance of the Time structure to the specified hour, minute, second.
     */
    this(int hour, int minute, int second,
        DateTimeKind kind = DateTimeKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTimeParts(hour, minute, second, 0) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createTimeTick(Tick.timeToTicks(hour, minute, second), kind);
    }

    /**
     * Initializes a new instance of the Time structure to the specified hour, minute.
     */
    this(int hour, int minute,
        DateTimeKind kind = DateTimeKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTimeParts(hour, minute, 0, 0) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createTimeTick(Tick.timeToTicks(hour, minute, 0), kind);
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

    Duration opBinary(string op)(scope const(Time) rhs) const @nogc nothrow pure scope
    if (op == "-")
    {
        return Tick.durationFromTicks(data.sticks - rhs.data.sticks);
    }

    int opCmp(scope const(Time) rhs) const @nogc nothrow pure scope
    {
        return data.opCmp(rhs.data);
    }

    bool opEquals(scope const(Time) rhs) const @nogc nothrow pure scope
    {
        return data.opEquals(rhs.data);
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
        return Time(cast(ulong)newTicks | data.internalKind);
    }

    Time addTicks(const(long) ticks, out int wrappedDays) const @nogc nothrow pure
    {
        wrappedDays = cast(int)(ticks / Tick.ticksPerDay);
        long newTicks = data.sticks + ticks % Tick.ticksPerDay;
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
        return Time(cast(ulong)newTicks | data.internalKind);
    }

    static Time createTime(long ticks,
        DateTimeKind kind = DateTimeKind.unspecified) pure
    {
        if (isValidTicks(ticks) != ErrorOp.none)
            throwOutOfRange!(ErrorPart.tick)(ticks);
        return Time(ticks, kind);
    }

    static Time createTime(int hour, int minute, int second, int millisecond,
        DateTimeKind kind = DateTimeKind.unspecified) pure
    {
        checkTimeParts(hour, minute, second, millisecond);
        return Time(hour, minute, second, millisecond, kind);
    }

    static Time createTime(int hour, int minute, int second,
        DateTimeKind kind = DateTimeKind.unspecified) pure
    {
        checkTimeParts(hour, minute, second, 0);
        return Time(hour, minute, second, kind);
    }

    static Time createTime(int hour, int minute,
        DateTimeKind kind = DateTimeKind.unspecified) pure
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
     * corresponds to this DateTime with the date part set to
     * zero (Jan 1st year 1).
     */
    pragma(inline, true)
    DateTime toDateTime() const @nogc nothrow pure
    {
        return DateTime(data);
    }

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

    ref Writer toString(Writer, Char = char)(return ref Writer sink) const nothrow
    if (isOutputRange!(Writer, Char))
    {
        import pham.utl.datetime.date_time_format;

        auto fmtSpec = FormatDateTimeSpec!Char("%s");
        auto fmtValue = FormatDateTimeValue(this);
        formattedWrite(sink, fmtSpec, fmtValue);
        return sink;
    }

    string toString(scope const(char)[] fmt) const
    {
        ShortStringBuffer!char buffer;
        return toString(buffer, fmt).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        import pham.utl.datetime.date_time_format;

        auto fmtSpec = FormatDateTimeSpec!Char(fmt);
        auto fmtValue = FormatDateTimeValue(this);
        if (formattedWrite(sink, fmtSpec, fmtValue) == formatedWriteError)
            throw new FormatException(fmtSpec.errorMessage.idup);
        return sink;
    }

    /**
     * Returns Time as requested parameter, kind, without any conversion/adjustment
     */
    Time asKind(DateTimeKind kind) const @nogc nothrow pure scope
    {
        return Time(data.toTickKind(kind));
    }

    /**
     * Returns Time as UTC kind without any conversion/adjustment
     */
    @property Time asUTC() const @nogc nothrow pure scope
    {
        return Time(data.toTickKind(DateTimeKind.utc));
    }

    /**
     * Returns the tick component of this instance. The returned value
     * is an integer between 0 and 9_999_999.
     */
    @property int fraction() const @nogc nothrow pure
    {
        const t = data.sticks;
        const long totalSeconds = t / Tick.ticksPerSecond;
        return cast(int)(t - (totalSeconds * Tick.ticksPerSecond));
    }

    /**
     * Gets the hour component of the time represented by this instance.
     */
    @property int hour() const @nogc nothrow pure
    {
        return cast(int)((data.sticks / Tick.ticksPerHour) % 24);
    }

    @property uint julianDay() const @nogc nothrow pure
    {
        return hour >= 12 ? 1 : 0;
    }

    @property DateTimeKind kind() const @nogc nothrow pure
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
        return cast(int)((data.sticks / Tick.ticksPerMinute) % 60);
    }

    /**
     * Gets the second component of the time represented by this instance.
     */
    @property int second() const @nogc nothrow pure
    {
        return cast(int)((data.sticks / Tick.ticksPerSecond) % 60);
    }

    pragma(inline, true)
    @property long sticks() const @nogc nothrow pure
    {
        return data.sticks;
    }

    pragma(inline, true)
    @property ulong uticks() const @nogc nothrow pure
    {
        return data.uticks;
    }

    /**
     * Returns the Date farthest in the future which is representable by Date.
     */
    @property static Time max() @nogc nothrow pure
    {
        return Time(cast(ulong)maxTicks | TickData.kindUnspecified);
    }

    /**
     * Returns the Date farthest in the past which is representable by Date.
     */
    @property static Time min() @nogc nothrow pure
    {
        return Time(cast(ulong)minTicks | TickData.kindUnspecified);
    }

    @property static Time now() nothrow
    {
        return DateTime.now.time;
    }

    @property static Time utcNow() @nogc nothrow
    {
        return DateTime.utcNow.time;
    }

    alias zero = min;

public:
    // MinTimeTicks is the ticks for the midnight time 00:00:00.000 AM
    enum long minTicks = 0;

    // MaxTimeTicks is the max tick value for the time in the day.
    // It is calculated using DateTime.today.addTicks(-1).timeOfDay.ticks.
    enum long maxTicks = 863_999_999_999;

package(pham.utl.datetime):
    this(ulong data) @nogc nothrow pure
    {
        this.data = TickData(data);
    }

    this(TickData data) @nogc nothrow pure
    {
        this.data = data;
    }

    void getDate(out int year, out int month, out int day) const @nogc nothrow pure
    {
        year = month = day = 0;
    }

private:
    TickData data;
}

alias TimeOfDay = Time;


private:

unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.contructor");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.opCmp");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.opEquals");

    assert(Time(12, 30, 33, 1).opEquals(Time(12, 30, 33, 1)));
    assert(Time(12, 30, 33).opEquals(Time(12, 30, 33)));
    assert(Time(12, 30).opEquals(Time(12, 30)));

    assert(!Time(12, 30, 33, 1).opEquals(Time(1, 1, 1, 1)));
    assert(!Time.min.opEquals(Time.max));
}

unittest // Time.hour
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.hour");

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
    assert(i4 == 1, i4.dgToStr());
}

unittest // Time.minute
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.minute");

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
    assert(i4 == 1, i4.dgToStr());
}

unittest // Time.second
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.second");

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
    assert(i4 == 1, i4.dgToStr());
}

unittest // Time.millisecond
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.millisecond");

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
    assert(i4 == 1, i4.dgToStr());
}

unittest // Time.opBinary
{
    import core.time : dur, hours, minutes, seconds, msecs;
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.opBinary");

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
    import core.time : dur, hours, minutes, seconds, msecs;
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.opBinary");

    assert(Time(7, 12, 52) - Time(12, 30, 33) == dur!"seconds"(-19_061));
    assert(Time(12, 30, 33) - Time(7, 12, 52) == dur!"seconds"(19_061));
    assert(Time(12, 30, 33) - Time(14, 30, 33) == dur!"seconds"(-7200));
    assert(Time(14, 30, 33) - Time(12, 30, 33) == dur!"seconds"(7200));
    assert(Time(12, 30, 33) - Time(12, 34, 33) == dur!"seconds"(-240));
    assert(Time(12, 34, 33) - Time(12, 30, 33) == dur!"seconds"(240));
    assert(Time(12, 30, 33) - Time(12, 30, 34) == dur!"seconds"(-1));
    assert(Time(12, 30, 34) - Time(12, 30, 33) == dur!"seconds"(1));

    auto tod = Time(12, 30, 33);
    const ctod = Time(12, 30, 33);
    immutable itod = TimeOfDay(12, 30, 33);

    assert(tod - tod == Duration.zero);
    assert(tod - ctod == Duration.zero);
    assert(tod - itod == Duration.zero);

    assert(ctod - ctod == Duration.zero);
    assert(ctod - tod == Duration.zero);
    assert(ctod - itod == Duration.zero);

    assert(itod - tod == Duration.zero);
    assert(itod - ctod == Duration.zero);
    assert(itod - itod == Duration.zero);
}

unittest // Time.min
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.min");

    assert(Time.min.hour == 0);
    assert(Time.min.minute == 0);
    assert(Time.min.second == 0);
    assert(Time.min.millisecond == 0);
}

unittest // Time.max
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.max");

    assert(Time.max.hour == 23);
    assert(Time.max.minute == 59);
    assert(Time.max.second == 59);
    assert(Time.max.millisecond == 999);

    assert(Time.min < Time.max);
    assert(Time.max > Time.min);
}

unittest // Time.toString
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.toString");

    assert(Time.max.toString() == "23:59:59.9999999");

    assert(Time(0, 0, 0).toString() == "00:00:00.0000000");
    assert(Time(12, 30, 33).toString() == "12:30:33.0000000");

    auto tod = Time(12, 30, 33);
    assert(tod.toString() == "12:30:33.0000000");

    const ctod = Time(12, 30, 33);
    assert(ctod.toString() == "12:30:33.0000000");

    immutable itod = Time(12, 30, 33);
    assert(itod.toString() == "12:30:33.0000000");
}

unittest // Time.createTime
{
    import std.exception : assertThrown;
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.createTime");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.julianDay");

    assert(Time(0, 0, 0, 0).julianDay == 0);
    assert(Time(11, 59, 59, 999).julianDay == 0);
    assert(Time(12, 0, 0, 0).julianDay == 1);
    assert(Time(23, 59, 59, 999).julianDay == 1);
}

unittest // Time.getTime
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.getTime");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl.datetime")("unittest pham.utl.datetime.time.Time.getTimePrecise");

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
