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

module pham.dtm.dtm_date;

import std.math.algebraic : abs;
import std.range.primitives : isOutputRange;
import std.traits : isSomeChar;

import pham.utl.utl_array : ShortStringBuffer;
import pham.utl.utl_result : cmp;
import pham.dtm.dtm_date_time_format;
import pham.dtm.dtm_tick;
public import pham.dtm.dtm_tick : CustomFormatSpecifier, DayOfWeek, DateTimeKind,
    DateTimeSetting, dateTimeSetting, DateTimeZoneKind,
    firstDayOfMonth, firstDayOfWeek;
public import pham.dtm.dtm_time : Time;
import pham.dtm.dtm_time_zone : TimeZoneInfo;

@safe:

struct Date
{
@safe:

public:
    /**
     * Initializes a new instance of the Date structure from a number of days. The days
     * argument specifies the date from Jan 1st year 1.
     */
    this(int days) @nogc nothrow pure
    in
    {
        assert(isValidDays(days) == ErrorOp.none);
    }
    do
    {
        this.data = cast(uint)days;
    }

    /**
     * Initializes a new instance of the Date structure to the specified year, month, and day.
     */
    this(int year, int month, int day) @nogc nothrow pure
    in
    {
        assert(DateTime.isValidDateParts(year, month, day) == ErrorPart.none);
    }
    do
    {
        this.data = DateTime(year, month, day).totalDays;
    }

    Date opBinary(string op)(scope const(Duration) duration) const pure scope
    if (op == "+" || op == "-")
    {
        const dt = toDateTime().opBinary!op(duration);
        return Date(dt.totalDays);
    }

    DateTime opBinary(string op)(scope const(Time) time) const @nogc nothrow pure
    if (op == "+")
    {
        static if (op == "+")
            return DateTime(this.sticks + time.sticks, time.kind);
        else
            static assert(0);
    }

    TickSpan opBinary(string op)(scope const(Date) rhs) const @nogc nothrow pure scope
    if (op == "-")
    {
        return TickSpan(this.sticks, rhs.sticks);
    }

    int opCmp(scope const(Date) rhs) const @nogc nothrow pure scope
    {
        return cmp(data, rhs.data);
    }

    bool opEquals(scope const(Date) rhs) const @nogc nothrow pure scope
    {
        return opCmp(rhs) == 0;
    }

    /**
     * Adds the specified number of days to the value of this Date
     * and returns new Date whose value is the sum of the date represented by this Date
     * and days
     * Params:
     *   days = number of days to be added
     * Returns:
     *   Date whose value is the sum of the date represented by this Date and days
     * Throws:
     *   TimeException if sum of days is not in valid days range
     */
    Date addDays(const(int) days) const pure
    {
        Date result = void;
        long newDays = void;
        if (addDaysImpl(days, newDays, result) != ErrorOp.none)
            throwOutOfRange!(ErrorPart.day)(newDays);
        return result;
    }

    /**
     * Same as addDays except it won't raise TimeException when the calculation
     * is out of bound. The result will be Date.min for underflow and Date.max for overflow
     */
    Date addDaysSafe(const(int) days) const @nogc pure nothrow
    {
        Date result = void;
        long newDays = void;
        addDaysImpl(days, newDays, result);
        return result;
    }

    /**
     * Adds the specified number of months to the value of this Date
     * and returns new Date whose value is the sum of the date represented by this Date
     * and months
     */
    Date addMonths(const(int) months) const pure
    {
        const dt = toDateTime().addMonths(months);
        return Date(dt.totalDays);
    }

    /**
     * Adds the specified number of years to the value of this Date
     * and returns new Date whose value is the sum of the date represented by this Date
     * and years
     */
    Date addYears(const(int) years) const pure
    {
        const dt = toDateTime().addYears(years);
        return Date(dt.totalDays);
    }

    /**
     * Returns the first day in the month that this Date is in
     */
    Date beginOfMonth() const nothrow pure @safe
    {
        int y = void, m = void, d = void;
        getDate(y, m, d);
        return Date(y, m, 1);
    }

    /**
     * Create new Date with specified number of days
     * Params:
     *   days = number of days since 1/1/1
     * Returns:
     *   Date with days
     * Throws:
     *   TimeException if days is not in valid days range
     */
    static Date createDate(int days) pure
    {
        if (isValidDays(days) != ErrorOp.none)
            throwOutOfRange!(ErrorPart.day)(days);
        return Date(days);
    }

    /**
     * Create new Date with specified year, month & day
     * Params:
     *   year = the year of date
     *   month = the month of year
     *   day = the day of month
     * Returns:
     *   Date with specified year, month & day
     * Throws:
     *   TimeException if year or month or day is not in its' valid value range
     */
    static Date createDate(int year, int month, int day) pure
    {
        DateTime.checkDateParts(year, month, day);
        return Date(year, month, day);
    }

    /**
     * Returns the last day in the month that this Date is in
     */
    Date endOfMonth() const @nogc nothrow pure @safe
    {
        int y = void, m = void, d = void;
        getDate(y, m, d);
        return Date(y, m, DateTime.daysInMonth(y, m));
    }

    /**
     * Gets date parts of this Date
     * Params:
     *   year = the year of this Date
     *   month = the month of year of this Date
     *   day = the day of month of this Date
     */
    void getDate(out int year, out int month, out int day) const @nogc nothrow pure
    {
        toDateTime().getDate(year, month, day);
    }

    /**
     * Query if days is in valid days range
     * Params:
     *   days = number of days to be checked
     * Returns:
     *   an enum ErrorOp value
     */
    static ErrorOp isValidDays(const(long) days) @nogc nothrow pure
    {
        return days < minDays
            ? ErrorOp.underflow
            : (days > maxDays ? ErrorOp.overflow : ErrorOp.none);
    }

    alias isValidMonth = DateTime.isValidMonth;
    alias isValidYear = DateTime.isValidMonth;

    /**
     * Returns the equivalent DateTime of this Date. The resulting value
     * corresponds to this DateTime with the time-of-day part set to
     * zero (midnight)
     */
    pragma(inline, true)
    DateTime toDateTime() const @nogc nothrow pure
    {
        return DateTime(uticks);
    }

    /**
     * Returns equivalent Duration of this instance
     */
    Duration toDuration() const @nogc nothrow pure
    {
        return Tick.durationFromTicks(sticks);
    }

    size_t toHash() const @nogc nothrow pure scope
    {
        return data;
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

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt, auto scope ref DateTimeSetting setting) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        auto fmtSpec = FormatDateTimeSpec!Char(fmt);
        auto fmtValue = FormatDateTimeValue(this);
        if (formattedWrite(sink, fmtSpec, fmtValue, setting) == formatedWriteError)
            throw new FormatException(fmtSpec.errorMessage.idup);
        return sink;
    }

    /**
     * Adds the specified number of days to the value of this Date
     * and set newDate whose value is the sum of the date represented by this Date
     * and days
     * Params:
     *   days = number of days to be added
     *   newDate = Date whose value is the sum of the date represented by this Date and days
     * Returns:
     *   an enum ErrorOp value of this add operation
     */
    ErrorOp tryAddDays(const(int) days, out Date newDate) const @nogc nothrow pure
    {
        long newDays = void;
        return addDaysImpl(days, newDays, newDate);
    }

    /**
     * Returns the century of this Date
     */
    @property int century() const @nogc nothrow pure
    {
        return year / 100;
    }

    /**
     * Returns the day-of-month part of this Date. The returned
     * value is an integer between 1 and 31
     */
    @property int day() const @nogc nothrow pure
    {
        return toDateTime().day;
    }

    /**
     * Returns the day-of-year part of this Date. The returned value
     * is an integer between 1 and 366
     */
    @property int dayOfYear() const @nogc nothrow pure
    {
        return toDateTime().dayOfYear;
    }

    /**
     * Returns the day-of-week part of this instance. The returned value
     * is an integer between 0 and 6, where 0 indicates Sunday, 1 indicates
     * Monday, 2 indicates Tuesday, 3 indicates Wednesday, 4 indicates
     * Thursday, 5 indicates Friday, and 6 indicates Saturday
     */
    @property DayOfWeek dayOfWeek() const @nogc nothrow pure
    {
        return toDateTime().dayOfWeek;
    }

    /**
     * Returns the number of days since January 1, 0001 in the Proleptic Gregorian calendar represented by this Date
     */
    @property int days() const @nogc nothrow pure
    {
        return cast(int)data;
    }

    /**
     * Returns JulianDay represented by this Date, the Time part is zero (midnight 00:00:00.000)
     * The $(HTTP en.wikipedia.org/wiki/Julian_day)
     */
    @property double julianDay() const @nogc nothrow pure
    {
        int y = void, m = void, d = void;
        getDate(y, m, d);
        return JulianDate.toJulianDay(y, m, d, 0, 0, 0, 0);
    }

    /**
     * Returns the month part of this Date. The returned value is an
     * integer between 1 and 12
     */
    @property int month() const @nogc nothrow pure
    {
        return toDateTime().month;
    }

    /**
     * Returns the value of the current Date expressed in whole days
     */
    alias totalDays = days;

    /**
     * Returns the value of the current Date expressed in whole hours
     */
    pragma(inline, true)
    @property long totalHours() const @nogc nothrow pure
    {
        return cast(long)(sticks / Tick.ticksPerHour);
    }

    /**
     * Returns the value of the current Date expressed in whole minutes
     */
    pragma(inline, true)
    @property long totalMinutes() const @nogc nothrow pure
    {
        return cast(long)(sticks / Tick.ticksPerMinute);
    }

    /**
     * Returns the value of the current Date expressed in whole seconds
     */
    pragma(inline, true)
    @property long totalSeconds() const @nogc nothrow pure
    {
        return cast(long)(sticks / Tick.ticksPerSecond);
    }

    /**
     * Returns the value of the current Date expressed in whole milliseconds
     */
    pragma(inline, true)
    @property long totalMilliseconds() const @nogc nothrow pure
    {
        return cast(long)(sticks / Tick.ticksPerMillisecond);
    }

    /**
     * Returns the number of ticks that represent the date of this Date
     */
    pragma(inline, true)
    @property long sticks() const @nogc nothrow pure
    {
        return cast(long)data * Tick.ticksPerDay;
    }

    /**
     * Returns the number of ticks that represent the date of this Date
     */
    pragma(inline, true)
    @property ulong uticks() const @nogc nothrow pure
    {
        return cast(ulong)data * Tick.ticksPerDay;
    }

    /**
     * Returns the year part of this Date. The returned value is an
     * integer between 1 and 9999.
     */
    @property int year() const @nogc nothrow pure
    {
        return toDateTime().year;
    }

    /**
     * Returns the Date farthest in the future which is representable by Date.
     */
    @property static Date max() @nogc nothrow pure
    {
        return Date(cast(uint)maxDays);
    }

    /**
     * Returns the Date farthest in the past which is representable by Date.
     */
    @property static Date min() @nogc nothrow pure
    {
        return Date(cast(uint)minDays);
    }

    /**
     * Returns the current date
     */
    @property static Date today() @nogc nothrow
    {
        return DateTime.today;
    }

    alias zero = min;

public:
    // Maps to Jan 1st year 1
    enum int minDays = 0;

    // Maps to December 31 year 9999.
    enum int maxDays = Tick.daysTo10000 - 1;

    alias minYear = DateTime.minYear;
    alias maxYear = DateTime.maxYear;

    alias daysInMonth365 = DateTime.daysInMonth365;
    alias daysInMonth366 = DateTime.daysInMonth366;

package(pham.dtm):
    this(uint data) @nogc nothrow pure
    {
        this.data = data;
    }

    static Date errorResult(const(ErrorOp) error) @nogc nothrow pure
    in
    {
        assert(error != ErrorOp.none);
    }
    do
    {
        return ErrorOp.underflow ? min : max;
    }

    void getTime(out int hour, out int minute, out int second, out int millisecond) const @nogc nothrow pure
    {
        hour = minute = second = millisecond = 0;
    }

    void getTimePrecise(out int hour, out int minute, out int second, out int tick) const @nogc nothrow pure
    {
        hour = minute = second = tick = 0;
    }

private:
    ErrorOp addDaysImpl(const(int) days, out long newDays, out Date newDate) const @nogc nothrow pure
    {
        newDays = cast(long)data + days;
        const result = isValidDays(newDays);
        newDate = result == ErrorOp.none ? Date(cast(uint)newDays) : errorResult(result);
        return result;
    }

private:
    uint data;
}

struct DateTime
{
@safe:

public:
    /**
     * Constructs a DateTime from a tick count. The ticks
     * argument specifies the date as the number of 100-nanosecond intervals
     * that have elapsed since 1/1/0001 12:00am.
     */
    this(long ticks,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidTicks(ticks) == ErrorOp.none);
    }
    do
    {
        this.data = TickData.createDateTimeTick(cast(ulong)ticks, kind);
    }

    this(scope const(Date) date, scope const(Time) time) @nogc nothrow pure
    {
        this.data = TickData.createDateTimeTick(date.uticks + time.uticks, time.kind);
    }

    this(int year, int month, int day, int hour, int minute, int second, int millisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidDateParts(year, month, day) == ErrorPart.none);
        assert(isValidTimeParts(hour, minute, second, millisecond) == ErrorPart.none);
    }
    do
    {
        if (second != 60 || !Tick.s_systemSupportsLeapSeconds)
        {
            const ticks = dateToTicks(year, month, day) + Tick.timeToTicks(hour, minute, second, millisecond);
            assert(ticks <= maxTicks);
            this.data = TickData.createDateTimeTick(ticks, kind);
        }
        else
        {
            // if we have a leap second, then we adjust it to 59 so that DateTime will
            // consider it the last in the specified minute.
            const ticks = dateToTicks(year, month, day) + Tick.timeToTicks(hour, minute, 59, millisecond);
            assert(ticks <= maxTicks);
            this.data = TickData.createDateTimeTick(ticks, kind);
        }
    }

    this(int year, int month, int day, int hour, int minute, int second,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidDateParts(year, month, day) == ErrorPart.none);
        assert(isValidTimeParts(hour, minute, second, 0) == ErrorPart.none);
    }
    do
    {
        if (second != 60 || !Tick.s_systemSupportsLeapSeconds)
        {
            const ticks = dateToTicks(year, month, day) + Tick.timeToTicks(hour, minute, second);
            this.data = TickData.createDateTimeTick(ticks, kind);
        }
        else
        {
            // if we have a leap second, then we adjust it to 59 so that DateTime will
            // consider it the last in the specified minute.
            const ticks = dateToTicks(year, month, day) + Tick.timeToTicks(hour, minute, 59);
            this.data = TickData.createDateTimeTick(ticks, kind);
        }
    }

    this(int year, int month, int day, int hour, int minute,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidDateParts(year, month, day) == ErrorPart.none);
        assert(isValidTimeParts(hour, minute, 0, 0) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createDateTimeTick(dateToTicks(year, month, day) + Tick.timeToTicks(hour, minute, 0), kind);
    }

    this(int year, int month, int day,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    in
    {
        assert(isValidDateParts(year, month, day) == ErrorPart.none);
    }
    do
    {
        this.data = TickData.createDateTimeTick(dateToTicks(year, month, day), kind);
    }

    this(TickData data) @nogc nothrow pure
    {
        this.data = data;
    }

    DateTime opBinary(string op)(scope const(Duration) duration) const pure scope
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

    DateTime opBinary(string op)(scope const(Time) time) const pure scope
    if (op == "+")
    {
        static if (op == "+")
            return addTicks(cast(long)(time.ticks));
        else
            static assert(0);
    }

    TickSpan opBinary(string op)(scope const(DateTime) rhs) const @nogc nothrow pure scope
    if (op == "-")
    {
        return TickSpan(this.sticks, rhs.sticks);
    }

    int opCmp(scope const(DateTime) rhs) const @nogc nothrow pure scope
    {
        return data.opCmp(rhs.data);
    }

    bool opEquals(scope const(DateTime) rhs) const @nogc nothrow pure scope
    {
        return opCmp(rhs) == 0;
    }

    DateTime addBias(const(int) biasSign, const(int) biasHour, const(int) biasMinute) const @nogc nothrow pure
    in
    {
        assert(biasSign == +1 || biasSign == -1);
        assert(isValidTimeParts(biasHour, biasMinute, 0, 0) == ErrorPart.none);
    }
    do
    {
        return addMinutesSafe(-biasSign * (biasHour * 60 + biasMinute));
    }

    /**
     * Returns the DateTime resulting from adding a fractional number of
     * days to this DateTime. The result is computed by rounding the
     * fractional number of days given by value to the nearest
     * millisecond, and adding that interval to this DateTime. The
     * value argument is permitted to be negative.
     */
    DateTime addDays(const(double) days) const pure
    {
        long newTicks = void;
        DateTime result = void;
        if (addImpl(toMilliSeconds(days, Tick.millisPerDay), newTicks, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.tick)(newTicks);
        return result;
    }

    /**
     * Returns the DateTime resulting from adding a fractional number of
     * hours to this DateTime. The result is computed by rounding the
     * fractional number of hours given by value to the nearest
     * millisecond, and adding that interval to this DateTime. The
     * value argument is permitted to be negative.
     */
    DateTime addHours(const(double) hours) const pure
    {
        long newTicks = void;
        DateTime result = void;
        if (addImpl(toMilliSeconds(hours, Tick.millisPerHour), newTicks, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.tick)(newTicks);
        return result;
    }

    /**
     * Returns the DateTime resulting from the given number of
     * milliseconds to this DateTime. The result is computed by rounding
     * the number of milliseconds given by value to the nearest integer,
     * and adding that interval to this DateTime. The value
     * argument is permitted to be negative.
     */
    DateTime addMilliseconds(const(double) milliseconds) const pure
    {
        long newTicks = void;
        DateTime result = void;
        if (addImpl(toMilliSeconds(milliseconds, 1), newTicks, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.tick)(newTicks);
        return result;
    }

    /**
     * Returns the DateTime resulting from adding a fractional number of
     * minutes to this DateTime. The result is computed by rounding the
     * fractional number of minutes given by value to the nearest
     * millisecond, and adding that interval to this DateTime. The
     * value argument is permitted to be negative.
     */
    DateTime addMinutes(const(double) minutes) const pure
    {
        long newTicks = void;
        DateTime result = void;
        if (addImpl(toMilliSeconds(minutes, Tick.millisPerMinute), newTicks, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.tick)(newTicks);
        return result;
    }

    /**
     * Same as addMinutes except it won't raise TimeException when the calculation
     * is out of bound. The result will be DateTime.min for underflow and DateTime.max for overflow
     */
    DateTime addMinutesSafe(const(int) minutes) const @nogc nothrow pure
    {
        long newTicks = void;
        DateTime result = void;
        addImpl(toMilliSeconds(minutes, Tick.millisPerMinute), newTicks, result);
        return result;
    }

    /**
     * Returns the DateTime resulting from adding the given number of
     * months to this DateTime. The result is computed by incrementing
     * (or decrementing) the year and month parts of this DateTime by
     * months months, and, if required, adjusting the day part of the
     * resulting date downwards to the last day of the resulting month in the
     * resulting year. The time-of-day part of the result is the same as the
     * time-of-day part of this DateTime.
     *
     * In more precise terms, considering this DateTime to be of the
     * form y / m / d + t, where y is the
     * year, m is the month, d is the day, and t is the
     * time-of-day, the result is y1 / m1 / d1 + t,
     * where y1 and m1 are computed by adding months months
     * to y and m, and d1 is the largest value less than
     * or equal to d that denotes a valid day in month m1 of year y1.
     */
    DateTime addMonths(const(int) months) const pure
    {
        if (months < -120_000 || months > 120_000)
            throwOutOfRange!(ErrorPart.month)(months);

        int year = void, month = void, day = void;
        getDate(year, month, day);
        int y = year, d = day;
        int m = month + months;
        if (m > 0)
        {
            const int q = cast(int)(cast(uint)(m - 1) / 12);
            y += q;
            m -= q * 12;
        }
        else
        {
            y += m / 12 - 1;
            m = 12 + m % 12;
        }
        if (y < minYear || y > maxYear)
            throwArithmeticOutOfRange!(ErrorPart.year)(y);
        const daysTo = isLeapYear(y) ? s_daysToMonth366 : s_daysToMonth365;
        uint daysToMonth = daysTo[m - 1];
        const int days = cast(int)(daysTo[m] - daysToMonth);
        if (d > days)
            d = days;
        const long n = yearToDays(cast(uint)y) + daysToMonth + cast(uint)d - 1;
        const newTicks = n * Tick.ticksPerDay + data.sticks % Tick.ticksPerDay;
        return DateTime(cast(ulong)newTicks | data.internalKind);
    }

    /**
     * Returns the DateTime resulting from adding a fractional number of
     * seconds to this DateTime. The result is computed by rounding the
     * fractional number of seconds given by value to the nearest
     * millisecond, and adding that interval to this DateTime. The
     * value argument is permitted to be negative.
     */
    DateTime addSeconds(const(double) seconds) const pure
    {
        long newTicks = void;
        DateTime result = void;
        if (addImpl(toMilliSeconds(seconds, Tick.millisPerSecond), newTicks, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.tick)(newTicks);
        return result;
    }

    /**
     * Same as addSeconds except it won't raise TimeException when the calculation
     * is out of bound. The result will be DateTime.min for underflow and DateTime.max for overflow
     */
    DateTime addSecondsSafe(const(int) seconds) const @nogc nothrow pure
    {
        long newTicks = void;
        DateTime result = void;
        addImpl(toMilliSeconds(seconds, Tick.millisPerSecond), newTicks, result);
        return result;
    }

    /**
     * Returns the DateTime resulting from adding the given number of
     * 100-nanosecond ticks to this DateTime. The value argument
     * is permitted to be negative.
     */
    DateTime addTicks(const(long) ticks) const pure
    {
        long newTicks = void;
        DateTime result = void;
        if (addTicksImpl(ticks, newTicks, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.tick)(newTicks);
        return result;
    }

    /**
     * Same as addTicks except it won't raise TimeException when the calculation
     * is out of bound. The result will be DateTime.min for underflow and DateTime.max for overflow
     */
    DateTime addTicksSafe(const(long) ticks) const @nogc nothrow pure
    {
        long newTicks = void;
        DateTime result = void;
        addTicksImpl(ticks, newTicks, result);
        return result;
    }

    ///
    DateTime addTicksSafe(scope const(Duration) duration) const @nogc nothrow pure
    {
        return addTicksSafe(Tick.durationToTicks(duration));
    }

    /**
     * Returns the DateTime resulting from adding the given number of
     * years to this DateTime. The result is computed by incrementing
     * (or decrementing) the year part of this DateTime by value
     * years. If the month and day of this DateTime is 2/29, and if the
     * resulting year is not a leap year, the month and day of the resulting
     * DateTime becomes 2/28. Otherwise, the month, day, and time-of-day
     * parts of the result are the same as those of this DateTime.
     */
    DateTime addYears(const(int) years) const pure
    {
        int newYears = void;
        DateTime result = void;
        if (addYearsImpl(years, newYears, result) != ErrorOp.none)
            throwArithmeticOutOfRange!(ErrorPart.year)(newYears);
        return result;
    }

    static int adjustTwoDigitYear(int twoDigitYear, const(int) twoDigitYearCenturyWindow) @nogc nothrow
    in
    {
        assert(twoDigitYear >= 0 && twoDigitYear < 100);
        assert(twoDigitYearCenturyWindow >= 0 && twoDigitYearCenturyWindow < 100);
    }
    do
    {
        const centuryBase = utcNow.year - twoDigitYearCenturyWindow;
        twoDigitYear += (centuryBase / 100) * 100;
        if (twoDigitYearCenturyWindow > 0 && twoDigitYear < centuryBase)
            twoDigitYear += 100;
        return twoDigitYear;
    }

    /**
     * Returns the first day in the month that this DateTime is in.
     * The time portion of beginOfMonth is always 0:0:0.0
     */
    DateTime beginOfMonth() const pure nothrow
    {
        int y = void, m = void, d = void;
        getDate(y, m, d);
        return DateTime(y, m, 1, kind);
    }

    static void checkDateParts(int year, int month, int day) pure
    {
        const e = isValidDateParts(year, month, day);
        if (e == ErrorPart.none)
            return;
        else if (e == ErrorPart.year)
            throwOutOfRange!(ErrorPart.year)(year);
        else if (e == ErrorPart.month)
            throwOutOfRange!(ErrorPart.month)(month);
        else if (e == ErrorPart.day)
            throwOutOfRange!(ErrorPart.day)(day);
    }

    pragma(inline, true)
    static void checkTimeParts(int hour, int minute, int second, int millisecond) pure
    {
        // Forward call to tick.checkTimeParts
        .checkTimeParts(hour, minute, second, millisecond);
    }

    static DateTime createDateTime(long ticks,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        if (isValidTicks(ticks) != ErrorOp.none)
            throwOutOfRange!(ErrorPart.tick)(ticks);
        return DateTime(ticks, kind);
    }

    static DateTime createDateTime(int year, int month, int day, int hour, int minute, int second, int millisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkDateParts(year, month, day);
        checkTimeParts(hour, minute, second, millisecond);
        auto result = DateTime(year, month, day, hour, minute, second, millisecond, kind);
        static if (Tick.s_systemSupportsLeapSeconds)
        {
            if (second == 60)
                result.validateLeapSecond();
        }
        return result;
    }

    static DateTime createDateTime(int year, int month, int day, int hour, int minute, int second,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkDateParts(year, month, day);
        checkTimeParts(hour, minute, second, 0);
        auto result = DateTime(year, month, day, hour, minute, second, kind);
        static if (Tick.s_systemSupportsLeapSeconds)
        {
            if (second == 60)
                result.validateLeapSecond();
        }
        return result;
    }

    static DateTime createDateTime(int year, int month, int day, int hour, int minute,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkDateParts(year, month, day);
        checkTimeParts(hour, minute, 0, 0);
        return DateTime(year, month, day, hour, minute, kind);
    }

    static DateTime createDateTime(int year, int month, int day,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) pure
    {
        checkDateParts(year, month, day);
        return DateTime(year, month, day, kind);
    }

    static long dateToTicks(int year, int month, int day) @nogc nothrow pure
    in
    {
        assert(isValidDateParts(year, month, day) == ErrorPart.none);
    }
    do
    {
        const days = isLeapYear(year) ? s_daysToMonth366 : s_daysToMonth365;
        const totalDays = cast(long)yearToDays(cast(uint)year) + days[month - 1] + day - 1;
        return totalDays * Tick.ticksPerDay;
    }

    /**
     * Returns the number of days in the month given by the year and
     * month arguments.
     */
    static int daysInMonth(const(int) year, const(int) month) @nogc nothrow pure
    in
    {
        assert(isValidDateParts(year, month, 1) == ErrorPart.none);
    }
    do
    {
        return (isLeapYear(year) ? daysInMonth366 : daysInMonth365)[month - 1];
    }

    /**
     * Returns the last day in the month that this DateTime is in.
     * The time portion of endOfMonth is always 23:59:59.9999999
     */
    DateTime endOfMonth() const pure nothrow
    {
        int y = void, m = void, d = void;
        getDate(y, m, d);
        return DateTime(Date(y, m, daysInMonth(y, m)), Time.max.asKind(kind));
    }

    void getDate(out int year, out int month, out int day) const @nogc nothrow pure
    {
        // n = number of days since 1/1/0001
        uint n = cast(uint)(data.sticks / Tick.ticksPerDay);
        // y400 = number of whole 400-year periods since 1/1/0001
        const uint y400 = n / Tick.daysPer400Years;
        // n = day number within 400-year period
        n -= y400 * Tick.daysPer400Years;
        // y100 = number of whole 100-year periods within 400-year period
        uint y100 = n / Tick.daysPer100Years;
        // Last 100-year period has an extra day, so decrement result if 4
        if (y100 == 4)
            y100 = 3;
        // n = day number within 100-year period
        n -= y100 * Tick.daysPer100Years;
        // y4 = number of whole 4-year periods within 100-year period
        const uint y4 = n / Tick.daysPer4Years;
        // n = day number within 4-year period
        n -= y4 * Tick.daysPer4Years;
        // y1 = number of whole years within 4-year period
        uint y1 = n / Tick.daysPerYear;
        // Last year has an extra day, so decrement result if 4
        if (y1 == 4)
            y1 = 3;
        // compute year
        year = cast(int)(y400 * 400 + y100 * 100 + y4 * 4 + y1 + 1);
        // n = day number within year
        n -= y1 * Tick.daysPerYear;
        // dayOfYear = n + 1;
        // Leap year calculation looks different from isLeapYear since y1, y4,
        // and y100 are relative to year 1, not year 0
        const days = y1 == 3 && (y4 != 24 || y100 == 3) ? s_daysToMonth366 : s_daysToMonth365;
        // All months have less than 32 days, so n >> 5 is a good conservative
        // estimate for the month
        uint m = (n >> 5) + 1;
        // m = 1-based month number
        while (n >= days[m])
            m++;
        // compute month and day
        month = cast(int)m;
        day = cast(int)(n - days[m - 1] + 1);
    }

    void getTime(out int hour, out int minute, out int second) const @nogc nothrow pure
    {
        const long seconds = data.sticks / Tick.ticksPerSecond;
        const long minutes = seconds / 60;
        second = cast(int)(seconds - (minutes * 60));
        const long hours = minutes / 60;
        minute = cast(int)(minutes - (hours * 60));
        hour = cast(int)(cast(uint)hours % 24);
    }

    void getTime(out int hour, out int minute, out int second, out int millisecond) const @nogc nothrow pure
    {
        const long totalMilliseconds = data.sticks / Tick.ticksPerMillisecond;
        const long totalSeconds = totalMilliseconds / 1_000;
        millisecond = cast(int)(totalMilliseconds - (totalSeconds * 1_000));
        const long totalMinutes = totalSeconds / 60;
        second = cast(int)(totalSeconds - (totalMinutes * 60));
        const long totalHours = totalMinutes / 60;
        minute = cast(int)(totalMinutes - (totalHours * 60));
        hour = cast(int)(totalHours % 24);
    }

    void getTimePrecise(out int hour, out int minute, out int second, out int tick) const @nogc nothrow pure
    {
        const t = data.sticks;
        const long totalSeconds = t / Tick.ticksPerSecond;
        tick = cast(int)(t - (totalSeconds * Tick.ticksPerSecond));
        const long totalMinutes = totalSeconds / 60;
        second = cast(int)(totalSeconds - (totalMinutes * 60));
        const long totalHours = totalMinutes / 60;
        minute = cast(int)(totalMinutes - (totalHours * 60));
        hour = cast(int)(totalHours % 24);
    }

    /**
     * Indicates whether this instance of DateTime is within the daylight saving
     * time range for the current time zone
     */
    bool isDaylightSavingTime() const nothrow
    {
        if (data.internalKind == TickData.kindUtc)
            return false;
        else
        {
            auto ltz = TimeZoneInfo.localTimeZone(0); // Use default local
            return ltz.isDaylightSavingTime(this);
        }
    }

    //pragma(inline, true)
    static bool isLeapYear(const(int) year) @nogc nothrow pure
    in
    {
        assert(isValidYear(year) == ErrorOp.none);
    }
    do
    {
        if ((year & 3) != 0)
            return false;
        else if ((year & 15) == 0)
            return true;
        else
            return (cast(uint)year % 25) != 0;
    }

    //pragma(inline, true)
    static ErrorPart isValidDateParts(const(int) year, const(int) month, const(int) day) @nogc nothrow pure
    {
        if (isValidYear(year) != ErrorOp.none)
            return ErrorPart.year;
        else if (isValidMonth(month) != ErrorOp.none)
            return ErrorPart.month;
        // Check for "day > 28" to avoid circular call in pre-condition of daysInMonth
        else if (day < 1 || (day > 28 && day > daysInMonth(year, month)))
            return ErrorPart.day;
        else
            return ErrorPart.none;
    }

    pragma(inline, true)
    static ErrorOp isValidMonth(const(int) month) @nogc nothrow pure
    {
        return month < 1
            ? ErrorOp.underflow
            : (month > 12 ? ErrorOp.overflow : ErrorOp.none);
    }

    pragma(inline, true)
    static ErrorOp isValidTicks(const(long) ticks) @nogc nothrow pure
    {
        return ticks < minTicks
            ? ErrorOp.underflow
            : (ticks > maxTicks ? ErrorOp.overflow : ErrorOp.none);
    }

    pragma(inline, true)
    static ErrorPart isValidTimeParts(const(int) hour, const(int) minute, const(int) second, const(int) millisecond) @nogc nothrow pure
    {
        // Forward call to tick.isValidTimeParts
        return .isValidTimeParts(hour, minute, second, millisecond);
    }

    static ErrorOp isValidTimeWithLeapSeconds(int year, int month, int day, int hour, int minute, DateTimeZoneKind kind) @nogc nothrow pure
    {
        return ErrorOp.none; //todo
    }

    pragma(inline, true)
    static ErrorOp isValidYear(const(int) year) @nogc nothrow pure
    {
        return year < minYear
            ? ErrorOp.underflow
            : (year > maxYear ? ErrorOp.overflow : ErrorOp.none);
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
        import pham.dtm.dtm_date_time_format;

        auto fmtSpec = FormatDateTimeSpec!Char("%G");
        auto fmtValue = FormatDateTimeValue(this);
        formattedWrite(sink, fmtSpec, fmtValue);
        return sink;
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        import pham.dtm.dtm_date_time_format;

        auto fmtSpec = FormatDateTimeSpec!Char(fmt);
        auto fmtValue = FormatDateTimeValue(this);
        if (formattedWrite(sink, fmtSpec, fmtValue) == formatedWriteError)
            throw new FormatException(fmtSpec.errorMessage.idup);
        return sink;
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt, auto scope ref DateTimeSetting setting) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        auto fmtSpec = FormatDateTimeSpec!Char(fmt);
        auto fmtValue = FormatDateTimeValue(this);
        if (formattedWrite(sink, fmtSpec, fmtValue, setting) == formatedWriteError)
            throw new FormatException(fmtSpec.errorMessage.idup);
        return sink;
    }

    DateTime toUTC() const nothrow
    {
        if (kind == DateTimeZoneKind.utc)
            return DateTime(data);

        auto localZone = TimeZoneInfo.localTimeZone(year);
        return localZone.convertDateTimeToUTC(this);
    }

    ErrorOp tryAddDays(const(double) days, out DateTime newDateTime) const @nogc nothrow pure
    {
        long newTicks = void;
        return addImpl(toMilliSeconds(days, Tick.millisPerDay), newTicks, newDateTime);
    }

    /**
     * tryAddTicks is exact as addTicks except it doesn't throw
     */
    ErrorOp tryAddTicks(const(long) ticks, out DateTime newDateTime) const @nogc nothrow pure
    {
        long newTicks = void;
        return addTicksImpl(ticks, newTicks, newDateTime);
    }

    ErrorOp tryAddTicks(scope const(Duration) duration, out DateTime newDateTime) const @nogc nothrow pure
    {
        long newTicks = void;
        return addTicksImpl(Tick.durationToTicks(duration), newTicks, newDateTime);
    }

    ErrorOp tryAddYears(const(int) years, out DateTime newDateTime) const @nogc nothrow pure
    {
        int newYears = void;
        return addYearsImpl(years, newYears, newDateTime);
    }

    /**
     * Tries to construct a DateTime from a given year, month, day, hour,
     * minute, second and millisecond.
     */
    static bool tryCreate(int year, int month, int day, int hour, int minute, int second, int millisecond,
        out DateTime result,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified) @nogc nothrow pure
    {
        if (isValidDateParts(year, month, day) != ErrorPart.none)
        {
            result = DateTime.init;
            return false;
        }

        if (isValidTimeParts(hour, minute, second, millisecond) != ErrorPart.none)
        {
            result = DateTime.init;
            return false;
        }

        const days = isLeapYear(year) ? s_daysToMonth366 : s_daysToMonth365;
        ulong ticks = (yearToDays(cast(uint)year) + days[month - 1] + cast(uint)day - 1) * cast(ulong)Tick.ticksPerDay;
        if (cast(uint)second < 60)
        {
            ticks += Tick.timeToTicks(hour, minute, second) + (cast(uint)millisecond * cast(uint)Tick.ticksPerMillisecond);
        }
        else if (second == 60 && Tick.s_systemSupportsLeapSeconds && isValidTimeWithLeapSeconds(year, month, day, hour, minute, DateTimeZoneKind.unspecified))
        {
            // if we have leap second (second = 60) then we'll need to check if it is valid time.
            // if it is valid, then we adjust the second to 59 so DateTime will consider this second is last second
            // of this minute.
            // if it is not valid time, we'll eventually throw.
            // although this is unspecified datetime kind, we'll assume the passed time is UTC to check the leap seconds.
            ticks += Tick.timeToTicks(hour, minute, 59) + (999 * Tick.ticksPerMillisecond);
        }
        else
        {
            result = DateTime.init;
            return false;
        }
        assert(ticks <= maxTicks);

        result = DateTime(ticks, kind);
        return true;
    }

    /**
     * Returns DateTime as requested parameter, kind, without any conversion/adjustment
     */
    DateTime asKind(DateTimeZoneKind kind) const @nogc nothrow pure
    {
        return DateTime(data.toTickKind(kind));
    }

    /**
     * Returns DateTime as UTC kind without any conversion/adjustment
     */
    @property DateTime asUTC() const @nogc nothrow pure
    {
        return DateTime(data.toTickKind(DateTimeZoneKind.utc));
    }

    @property int century() const @nogc nothrow pure
    {
        return year / 100;
    }

    /**
     * Returns the date part of this DateTime. The returned value
     * is a Date that indicates the date elapsed since 1/1/0001.
     */
    @property Date date() const @nogc nothrow pure
    {
        return Date(cast(uint)totalDays);
    }

    /**
     * Returns the date part of this instance. The resulting value
     * corresponds to this Date with the time-of-day part set to
     * zero (midnight).
     */
    @property DateTime dateOnly() const @nogc nothrow pure
    {
        const t = data.sticks;
        return DateTime(cast(ulong)(t - t % Tick.ticksPerDay) | data.internalKind);
    }

    /**
     * Returns the day-of-month component of this instance. The returned
     * value is an integer between 1 and 31.
     */
    @property int day() const @nogc nothrow pure
    {
        return getDatePart(DatePart.day);
    }

    /**
     * Returns the day-of-week component of this instance. The returned value
     * is an integer between 0 and 6, where 0 indicates Sunday, 1 indicates
     * Monday, 2 indicates Tuesday, 3 indicates Wednesday, 4 indicates
     * Thursday, 5 indicates Friday, and 6 indicates Saturday.
     */
    @property DayOfWeek dayOfWeek() const @nogc nothrow pure
    {
        return cast(DayOfWeek)((cast(uint)(data.sticks / Tick.ticksPerDay) + 1) % 7);
    }

    /**
     * Returns the day-of-year component of this instance. The returned value
     * is an integer between 1 and 366.
     */
    @property int dayOfYear() const @nogc nothrow pure
    {
        return getDatePart(DatePart.dayOfYear);
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
     * Returns the hour component of this instance. The returned value is an
     * integer between 0 and 23.
     */
    @property int hour() const @nogc nothrow pure
    {
        return cast(int)(cast(uint)(data.sticks / Tick.ticksPerHour) % 24);
    }

    /**
     * Returns JulianDay represented by this DateTime
     * The $(HTTP en.wikipedia.org/wiki/Julian_day)
     */
    @property double julianDay() const @nogc nothrow pure
    {
        int y = void, m = void, d = void, h = void, n = void, s = void, f = void;
        getDate(y, m, d);
        getTime(h, n, s, f);
        return JulianDate.toJulianDay(y, m, d, h, n, s, f);
    }

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
     * Returns the millisecond component of this instance. The returned value
     * is an integer between 0 and 999.
     */
    @property int millisecond() const @nogc nothrow pure
    {
        return TickPart.tickToMillisecond(fraction);
    }

    /**
     * Returns the minute component of this instance. The returned value is
     * an integer between 0 and 59.
     */
    @property int minute() const @nogc nothrow pure
    {
        return cast(int)((data.sticks / Tick.ticksPerMinute) % 60);
    }

    /**
     * Returns the month component of this instance. The returned value is an
     * integer between 1 and 12.
     */
    @property int month() const @nogc nothrow pure
    {
        return getDatePart(DatePart.month);
    }

    /**
     * Returns the second component of this instance. The returned value is
     * an integer between 0 and 59.
     */
    @property int second() const @nogc nothrow pure
    {
        return cast(int)((data.sticks / Tick.ticksPerSecond) % 60);
    }

    /**
     * Returns the time-of-day part of this DateTime. The returned value
     * is a Time that indicates the time elapsed since midnight.
     */
    @property Time time() const @nogc nothrow pure
    {
        return Time(cast(ulong)(data.sticks % Tick.ticksPerDay) | data.internalKind);
    }

    /**
     * Returns the value of the current DateTime expressed in whole days
     */
    pragma(inline, true)
    @property int totalDays() const @nogc nothrow pure
    {
        return cast(int)(data.sticks / Tick.ticksPerDay);
    }

    /**
     * Returns the value of the current DateTime expressed in whole hours
     */
    pragma(inline, true)
    @property long totalHours() const @nogc nothrow pure
    {
        return cast(long)(data.sticks / Tick.ticksPerHour);
    }

    /**
     * Returns the value of the current DateTime expressed in whole minutes
     */
    pragma(inline, true)
    @property long totalMinutes() const @nogc nothrow pure
    {
        return cast(long)(data.sticks / Tick.ticksPerMinute);
    }

    /**
     * Returns the value of the current DateTime expressed in whole seconds
     */
    pragma(inline, true)
    @property long totalSeconds() const @nogc nothrow pure
    {
        return cast(long)(data.sticks / Tick.ticksPerSecond);
    }

    /**
     * Returns the value of the current DateTime expressed in whole milliseconds
     */
    pragma(inline, true)
    @property long totalMilliseconds() const @nogc nothrow pure
    {
        return cast(long)(data.sticks / Tick.ticksPerMillisecond);
    }

    /**
     * Returns the number of ticks that represent the date and time of this instance
     */
    pragma(inline, true)
    @property long sticks() const @nogc nothrow pure scope
    {
        return data.sticks;
    }

    ///dito
    pragma(inline, true)
    @property ulong uticks() const @nogc nothrow pure scope
    {
        return data.uticks;
    }

    /**
     * Returns the year component of this DateTime. The returned value is an
     * integer between 1 and 9999.
     */
    @property int year() const @nogc nothrow pure
    {
        return getDatePart(DatePart.year);
    }

    /**
     * Returns the DateTime farthest in the future which is representable by DateTime.
     * The DateTime which is returned is in UTC
     */
    @property static DateTime max() @nogc nothrow pure
    {
        return DateTime(cast(ulong)maxTicks | TickData.kindUtc);
    }

    /**
     * Returns the DateTime farthest in the past which is representable by DateTime.
     * The DateTime which is returned is in UTC
     */
    @property static DateTime min() @nogc nothrow pure
    {
        return DateTime(cast(ulong)minTicks | TickData.kindUtc);
    }

    /**
     * Returns a DateTime object that is set to the current date and time on this
     * computer, expressed as the local time
     */
    @property static DateTime now() nothrow
    {
        return TimeZoneInfo.convertUtcToLocal(utcNow());
    }

    /**
     * Returns the current date on this computer
     */
    @property static Date today() @nogc nothrow
    {
        return utcNow.date;
    }

    /**
     * Returns a DateTime object that is set to the current date and time on this
     * computer, expressed as the Coordinated Universal Time (UTC)
     */
    @property static DateTime utcNow() @nogc nothrow
    {
        const ticks = Tick.currentSystemTicks();
        return DateTime(cast(ulong)ticks | TickData.kindUtc);
    }

    @property int utcBias() const nothrow
    {
        if (kind == DateTimeZoneKind.utc)
            return 0;

        return cast(int)(totalMinutes - toUTC().totalMinutes);
    }

    @property TickData raw() const @nogc nothrow pure
    {
        return data;
    }

    alias zero = min;

public:
    enum long minTicks = 0;
    enum long maxTicks = Tick.daysTo10000 * Tick.ticksPerDay - 1;

    enum long minMillis =  0;
    enum long maxMillis = Tick.daysTo10000 * Tick.millisPerDay;

    enum int minYear = 1;
    enum int maxYear = 9_999;

    static immutable byte[] daysInMonth365 = [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ];
    static immutable byte[] daysInMonth366 = [ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ];

package(pham.dtm):
    this(ulong data) @nogc nothrow pure
    {
        this.data = TickData(data);
    }

    DateTime errorDateTime(const(ErrorOp) error) const @nogc nothrow pure scope
    in
    {
        assert(error != ErrorOp.none);
    }
    do
    {
        return error == ErrorOp.underflow
            ? DateTime(cast(ulong)minTicks | data.internalKind)
            : DateTime(cast(ulong)maxTicks | data.internalKind);
    }

    ErrorOp errorResult(const(ErrorOp) error, out DateTime newDateTime) const @nogc nothrow pure scope
    {
        newDateTime = errorDateTime(error);
        return error;
    }

private:
    /**
     * Returns the DateTime resulting from adding a fractional number of
     * time units to this DateTime.
     */
    ErrorOp addImpl(const(long) milliseconds, out long newTicks, out DateTime newDateTime) const @nogc nothrow pure
    {
        //const long milliseconds = cast(long)(value * scale + (value >= 0 ? 0.5 : -0.5));
        const error = milliseconds <= -maxMillis
            ? ErrorOp.underflow
            : (milliseconds >= maxMillis ? ErrorOp.overflow : ErrorOp.none);
        return error == ErrorOp.none
            ? addTicksImpl(milliseconds * Tick.ticksPerMillisecond, newTicks, newDateTime)
            : errorResult(error, newDateTime);
    }

    ErrorOp addTicksImpl(const(long) ticks, out long newTicks, out DateTime newDateTime) const @nogc nothrow pure
    {
        newTicks = data.sticks + ticks;
        const result = isValidTicks(newTicks);
        newDateTime = result == ErrorOp.none
            ? DateTime(cast(ulong)newTicks | data.internalKind)
            : errorDateTime(result);
        return result;
    }

    ErrorOp addYearsImpl(const(int) years, out int newYears, out DateTime newDateTime) const @nogc nothrow pure
    {
        int year = void, month = void, day = void;
        getDate(year, month, day);
        newYears = year + years;
        const result = isValidYear(newYears);
        if (result != ErrorOp.none)
        {
            newDateTime = errorDateTime(result);
            return result;
        }
        long n = yearToDays(cast(uint)newYears);
        int m = month - 1, d = day - 1;
        if (isLeapYear(newYears))
        {
            n += s_daysToMonth366[m];
        }
        else
        {
            if (d == 28 && m == 1)
                d--;
            n += s_daysToMonth365[m];
        }
        n += d;
        const newTicks = n * Tick.ticksPerDay + data.sticks % Tick.ticksPerDay;
        newDateTime = DateTime(cast(ulong)newTicks | data.internalKind);
        return ErrorOp.none;
    }

    /**
     * Returns a given date part of this DateTime. This method is used
     * to compute the year, day-of-year, month, or day part.
     */
    int getDatePart(const(DatePart) part) const @nogc nothrow pure
    {
        // n = number of days since 1/1/0001
        uint n = cast(uint)(data.sticks / Tick.ticksPerDay);
        // y400 = number of whole 400-year periods since 1/1/0001
        const uint y400 = n / Tick.daysPer400Years;
        // n = day number within 400-year period
        n -= y400 * Tick.daysPer400Years;
        // y100 = number of whole 100-year periods within 400-year period
        uint y100 = n / Tick.daysPer100Years;
        // Last 100-year period has an extra day, so decrement result if 4
        if (y100 == 4)
            y100 = 3;
        // n = day number within 100-year period
        n -= y100 * Tick.daysPer100Years;
        // y4 = number of whole 4-year periods within 100-year period
        const uint y4 = n / Tick.daysPer4Years;
        // n = day number within 4-year period
        n -= y4 * Tick.daysPer4Years;
        // y1 = number of whole years within 4-year period
        uint y1 = n / Tick.daysPerYear;
        // Last year has an extra day, so decrement result if 4
        if (y1 == 4)
            y1 = 3;
        // If year was requested, compute and return it
        if (part == DatePart.year)
            return cast(int)(y400 * 400 + y100 * 100 + y4 * 4 + y1 + 1);
        // n = day number within year
        n -= y1 * Tick.daysPerYear;
        // If day-of-year was requested, return it
        if (part == DatePart.dayOfYear)
            return cast(int)n + 1;
        // Leap year calculation looks different from isLeapYear since y1, y4,
        // and y100 are relative to year 1, not year 0
        const days = y1 == 3 && (y4 != 24 || y100 == 3) ? s_daysToMonth366 : s_daysToMonth365;
        // All months have less than 32 days, so n >> 5 is a good conservative
        // estimate for the month
        uint m = (n >> 5) + 1;
        // m = 1-based month number
        while (n >= days[m])
            m++;
        // If month was requested, return it
        if (part == DatePart.month)
            return cast(int)m;
        // Return 1-based day-of-month
        return cast(int)(n - days[m - 1] + 1);
    }

    pragma(inline, true)
    static long toMilliSeconds(const(double) value, const(int) scale) @nogc nothrow pure
    {
        return cast(long)(value * scale + (value >= 0 ? 0.5 : -0.5));
    }

    pragma(inline, true)
    static long toMilliSeconds(const(int) value, const(int) scale) @nogc nothrow pure
    {
        return cast(long)value * scale;
    }

    void validateLeapSecond() pure
    {
        version(none)
        if (!isValidTimeWithLeapSeconds(year, month, day, hour, minute, kind))
            throwOutOfRange!(ErrorPart.second)(second);
    }

    static uint yearToDays(uint year) @nogc nothrow pure
    {
        const uint y = year - 1;
        const uint century = y / 100;
        return y * (365 * 4 + 1) / 4 - century + century / 4;
    }

private:
    static immutable int[] s_daysToMonth365 = [ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365 ];
    static immutable int[] s_daysToMonth366 = [ 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366 ];

    enum DatePart : ubyte
    {
        year,
        dayOfYear,
        month,
        day,
    }

    TickData data;
}

struct JulianDate
{
@nogc nothrow @safe:

    enum CalendarKind : ubyte
    {
        julian,
        gregorian,
        outofrange,
    }

    static CalendarKind calendarKind(const(int) year, const(int) month, const(int) day) pure
    {
        // All dates prior to 1582 are in the Julian calendar
        if (year < 1582)
            return CalendarKind.julian;
        // All dates after 1582 are in the Gregorian calendar
        else if (year > 1582)
            return CalendarKind.gregorian;
        else
        {
            // If 1582, check before October 4 (Julian) or after October 15 (Gregorian)
            if (month < 10)
                return CalendarKind.julian;
            else if (month > 10)
                return CalendarKind.gregorian;
            else
            {
                if (day < 5)
                    return CalendarKind.julian;
                else if (day > 14)
                    return CalendarKind.gregorian;
                else
                    // Any date in the range 10/5/1582 to 10/14/1582 is invalid
                    // This date is not valid as it does not exist in either the Julian or the Gregorian calendars
                    return CalendarKind.outofrange;
            }
        }
    }

    /**
     * Calculate julian day for year, month, day, hour, minute, second, millisecond
     * If date (year, month, day) is not a valid Julian/Gregorian calendar, the return value is NaN
     * The $(HTTP en.wikipedia.org/wiki/Julian_day)
     */
    static double toJulianDay(const(int) year, const(int) month, const(int) day, const(int) hour, const(int) minute, const(int) second, const(int) millisecond) pure
    {
        // Determine correct calendar based on date
        const ck = calendarKind(year, month, day);
        if (ck == CalendarKind.outofrange)
            return double.nan;

        const int Y = month > 2 ? year : year - 1;
        const int M = month > 2 ? month : month + 12;
        const double D = day + hour/24.0 + minute/1440.0 + (second + millisecond / 1000.0)/86400.0;
        const int B = ck == CalendarKind.julian ? 0 : (2 - Y/100 + Y/100/4);

        return cast(int)(365.25*(Y + 4716)) + cast(int)(30.6001*(M + 1)) + D + B - 1524.5;
    }
}

/**
 * Returns total positive number of years between 'now' and 'then'
 */
pragma(inline, true)
int yearsBetween(T)(scope const(T) now, scope const(T) then,
    const(double) approxDaysPerYear = TickSpan.approxDaysPerYear4ys) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{

    static if (is(T == Time))
        return 0;
    else
        return abs(cast(int)(now - then).totalYears(approxDaysPerYear));
}

/**
 * Returns total positive number of months between 'now' and 'then'
 */
pragma(inline, true)
int monthsBetween(T)(scope const(T) now, scope const(T) then,
    const(double) approxDaysPerMonth = TickSpan.approxDaysPerMonth4ys) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    static if (is(T == Time))
        return 0;
    else
        return abs(cast(int)(now - then).totalMonths(approxDaysPerMonth));
}

/**
 * Returns total positive number of weeks between 'now' and 'then'
 */
pragma(inline, true)
int weeksBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    static if (is(T == Time))
        return 0;
    else
        return abs(cast(int)(now - then).totalWeeks);
}

/**
 * Returns total positive number of days between 'now' and 'then'
 */
pragma(inline, true)
int daysBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    static if (is(T == Time))
        return 0;
    else
        return abs(cast(int)(now - then).totalDays);
}

/**
 * Returns total positive number of hours between 'now' and 'then'
 */
pragma(inline, true)
long hoursBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    return abs(cast(long)(now - then).totalHours);
}

/**
 * Returns total positive number of minutes between 'now' and 'then'
 */
pragma(inline, true)
long minutesBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    return abs(cast(long)(now - then).totalMinutes);
}

/**
 * Returns total positive number of seconds between 'now' and 'then'
 */
pragma(inline, true)
long secondsBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    return abs(cast(long)(now - then).totalSeconds);
}

/**
 * Returns total positive number of milliseconds between 'now' and 'then'
 */
pragma(inline, true)
long millisecondsBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    return abs(cast(long)(now - then).totalMilliseconds);
}

/**
 * Returns total positive number of ticks between 'now' and 'then'
 */
pragma(inline, true)
long ticksBetween(T)(scope const(T) now, scope const(T) then) @nogc nothrow pure
if (is(T == Date) || is(T == DateTime) || is(T == Time))
{
    return abs((now - then).ticks);
}


// Any below codes are private
private:

version(none)
{
    import std.conv : to;

    pragma(msg, (dur!"msecs"(1).total!"usecs"()).to!string());    //     1_000
    pragma(msg, (dur!"msecs"(1).total!"hnsecs"()).to!string());   //    10_000
    pragma(msg, (dur!"msecs"(1).total!"nsecs"()).to!string());    // 1_000_000
    pragma(msg, DateTime.maxMillis.to!string());                   //       315_537_897_600_000
    pragma(msg, (maxMillis * Tick.ticksPerMillisecond).to!string()); // 3_155_378_976_000_000_000
    enum ulong realMaxTicks = DateTime.ticksMask & 0xFFFF_FFFF_FFFF_FFFF;
    pragma(msg, realMaxTicks.to!string());                      // 4_611_686_018_427_387_903
    pragma(msg, DateTime.maxTicks.to!string());                 // 3_155_378_975_999_999_999
    pragma(msg, (realMaxTicks - DateTime.maxTicks).to!string());  // 1_456_307_042_427_387_904
}

unittest // DateTime.now
{
    import std.datetime.systime : SysClock = Clock, SysTime;
    import std.datetime.date : SysDateTime = DateTime;

    auto sysNow = SysClock.currTime;
    auto sysDateTime = cast(SysDateTime)sysNow;

    auto now = DateTime.now();
    //int year, month, day;
    //int hour, minute, second, millisecond;
    //int hour2, minute2, second2, tick;
    //now.getDate(year, month, day);
    //now.getTime(hour, minute, second, millisecond);
    //now.getTimePrecise(hour2, minute2, second2, tick);

    assert(now.year == sysDateTime.year);
    assert(now.month == sysDateTime.month);
    assert(now.day == sysDateTime.day);

    assert(now.hour == sysDateTime.hour);
    assert(now.minute == sysDateTime.minute);
    assert(now.second == sysDateTime.second);
}

unittest // DateTime.constructor
{
    auto d1 = DateTime.init;
    assert(d1.date == Date.init);
    assert(d1.time == Time.init);

    auto d2 = DateTime(1999, 7 ,6);
    assert(d2.date == Date(1999, 7, 6));
    assert(d2.time == Time.init);

    auto d3 = DateTime(1999, 7 , 6, 12, 30, 33);
    assert(d3.date == Date(1999, 7, 6));
    assert(d3.time == Time(12, 30, 33));

    auto d4 = DateTime(Date(1999, 7, 6), Time(12, 30, 33));
    assert(d4.date == Date(1999, 7, 6));
    assert(d4.time == Time(12, 30, 33));
}

unittest // DateTime.opCmp
{
    assert(DateTime(1999, 1, 1).opCmp(DateTime(1999, 1, 1)) == 0);
    assert(DateTime(1, 7, 1).opCmp(DateTime(1, 7, 1)) == 0);
    assert(DateTime(1, 1, 6).opCmp(DateTime(1, 1, 6)) == 0);
    assert(DateTime(1999, 7, 1).opCmp(DateTime(1999, 7, 1)) == 0);
    assert(DateTime(1999, 7, 6).opCmp(DateTime(1999, 7, 6)) == 0);
    assert(DateTime(1, 7, 6).opCmp(DateTime(1, 7, 6)) == 0);
    assert(DateTime(1999, 7, 6, 0, 0, 0).opCmp(DateTime(1999, 7, 6, 0, 0, 0)) == 0);
    assert(DateTime(1999, 7, 6, 12, 0, 0).opCmp(DateTime(1999, 7, 6, 12, 0, 0)) == 0);
    assert(DateTime(1999, 7, 6, 0, 30, 0).opCmp(DateTime(1999, 7, 6, 0, 30, 0)) == 0);
    assert(DateTime(1999, 7, 6, 0, 0, 33).opCmp(DateTime(1999, 7, 6, 0, 0, 33)) == 0);
    assert(DateTime(1999, 7, 6, 12, 30, 0).opCmp(DateTime(1999, 7, 6, 12, 30, 0)) == 0);
    assert(DateTime(1999, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 33)) == 0);
    assert(DateTime(1999, 7, 6, 0, 30, 33).opCmp(DateTime(1999, 7, 6, 0, 30, 33)) == 0);
    assert(DateTime(1999, 7, 6, 0, 0, 33).opCmp(DateTime(1999, 7, 6, 0, 0, 33)) == 0);

    auto dt = DateTime(Date(1999, 7, 6), Time(12, 33, 30));
    const cdt = DateTime(Date(1999, 7, 6), Time(12, 33, 30));
    immutable idt = DateTime(Date(1999, 7, 6), Time(12, 33, 30));
    assert(dt.opCmp(dt) == 0);
    assert(dt.opCmp(cdt) == 0);
    assert(dt.opCmp(idt) == 0);
    assert(cdt.opCmp(dt) == 0);
    assert(cdt.opCmp(cdt) == 0);
    assert(cdt.opCmp(idt) == 0);
    assert(idt.opCmp(dt) == 0);
    assert(idt.opCmp(cdt) == 0);
    assert(idt.opCmp(idt) == 0);

    assert(DateTime(1999, 7, 6).opCmp(DateTime(2000, 7, 6)) < 0);
    assert(DateTime(1999, 7, 6).opCmp(DateTime(1999, 8, 6)) < 0);
    assert(DateTime(1999, 7, 6).opCmp(DateTime(1999, 7, 7)) < 0);
    assert(DateTime(1999, 8, 7).opCmp(DateTime(2000, 7, 6)) < 0);
    assert(DateTime(1999, 7, 7).opCmp(DateTime(2000, 7, 6)) < 0);
    assert(DateTime(1999, 7, 7).opCmp(DateTime(1999, 8, 6)) < 0);

    assert(DateTime(2000, 7, 6).opCmp(DateTime(1999, 7, 6)) > 0);
    assert(DateTime(1999, 8, 6).opCmp(DateTime(1999, 7, 6)) > 0);
    assert(DateTime(1999, 7, 7).opCmp(DateTime(1999, 7, 6)) > 0);
    assert(DateTime(2000, 8, 6).opCmp(DateTime(1999, 7, 7)) > 0);
    assert(DateTime(2000, 7, 6).opCmp(DateTime(1999, 7, 7)) > 0);
    assert(DateTime(1999, 8, 6).opCmp(DateTime(1999, 7, 7)) > 0);

    assert(DateTime(1999, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 13, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 31, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 34)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 34).opCmp(DateTime(1999, 7, 6, 13, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 31, 33).opCmp(DateTime(1999, 7, 6, 13, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 34).opCmp(DateTime(1999, 7, 6, 12, 31, 33)) < 0);
    assert(DateTime(1999, 7, 6, 13, 30, 33).opCmp(DateTime(2000, 7, 6, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 31, 33).opCmp(DateTime(2000, 7, 6, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 34).opCmp(DateTime(2000, 7, 6, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 13, 30, 33).opCmp(DateTime(1999, 8, 6, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 31, 33).opCmp(DateTime(1999, 8, 6, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 34).opCmp(DateTime(1999, 8, 6, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 13, 30, 33).opCmp(DateTime(1999, 7, 7, 12, 30, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 31, 33).opCmp(DateTime(1999, 7, 7, 12, 31, 33)) < 0);
    assert(DateTime(1999, 7, 6, 12, 30, 34).opCmp(DateTime(1999, 7, 7, 12, 30, 33)) < 0);

    assert(DateTime(1999, 7, 6, 13, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 33)) > 0);
    assert(DateTime(1999, 7, 6, 12, 31, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 33)) > 0);
    assert(DateTime(1999, 7, 6, 12, 30, 34).opCmp(DateTime(1999, 7, 6, 12, 30, 33)) > 0);
    assert(DateTime(1999, 7, 6, 13, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 34)) > 0);
    assert(DateTime(1999, 7, 6, 13, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 31, 33)) > 0);
    assert(DateTime(1999, 7, 6, 12, 31, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 34)) > 0);
    assert(DateTime(2000, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 13, 30, 33)) > 0);
    assert(DateTime(2000, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 31, 33)) > 0);
    assert(DateTime(2000, 7, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 34)) > 0);
    assert(DateTime(1999, 8, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 13, 30, 33)) > 0);
    assert(DateTime(1999, 8, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 31, 33)) > 0);
    assert(DateTime(1999, 8, 6, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 34)) > 0);
    assert(DateTime(1999, 7, 7, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 13, 30, 33)) > 0);
    assert(DateTime(1999, 7, 7, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 33)) > 0);
    assert(DateTime(1999, 7, 7, 12, 30, 33).opCmp(DateTime(1999, 7, 6, 12, 30, 34)) > 0);
}

unittest // DateTime.opEquals
{
    assert(DateTime(1999, 1, 1, 1, 1, 1, 1).opEquals(DateTime(1999, 1, 1, 1, 1, 1, 1)));
    assert(DateTime(1999, 1, 1, 1, 1, 1).opEquals(DateTime(1999, 1, 1, 1, 1, 1)));
    assert(DateTime(1999, 1, 1, 1, 1).opEquals(DateTime(1999, 1, 1, 1, 1)));
    assert(DateTime(1999, 1, 1).opEquals(DateTime(1999, 1, 1)));

    assert(!DateTime(1999, 12, 30, 12, 30, 33, 1).opEquals(DateTime(1999, 1, 1, 1, 1, 1, 1)));
    assert(!DateTime(1999, 12, 30, 12, 30, 33).opEquals(DateTime(1999, 1, 1, 1, 1, 1)));
    assert(!DateTime(1999, 12, 30, 12, 30).opEquals(DateTime(1999, 1, 1, 1, 1)));
    assert(!DateTime(1999, 12, 30).opEquals(DateTime(1999, 1, 1)));
    assert(!DateTime.min.opEquals(DateTime.max));
}

unittest // DateTime.date
{
    auto dt1 = DateTime.init;
    assert(dt1.date == Date.init);

    auto dt2 = DateTime(1999, 7, 6);
    assert(dt2.date == Date(1999, 7, 6));

    const cdt = DateTime(1999, 7, 6);
    assert(cdt.date == Date(1999, 7, 6));

    immutable idt = DateTime(1999, 7, 6);
    assert(idt.date == Date(1999, 7, 6));
}

unittest // DateTime.time
{
    auto dt1 = DateTime.init;
    assert(dt1.time == Time.init);

    auto dt2 = DateTime(Date.init, Time(12, 30, 33, 22));
    assert(dt2.time == Time(12, 30, 33, 22));

    const cdt = DateTime(1999, 7, 6, 12, 30, 33, 22);
    assert(cdt.time == Time(12, 30, 33, 22));

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33, 22);
    assert(idt.time == Time(12, 30, 33, 22));
}

unittest // DateTime.year
{
    assert(DateTime.init.year == 1);
    assert(DateTime(1999, 7, 6).year == 1999);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.year == 1999);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.year == 1999);

    assert(DateTime(1999, 7, 6, 12, 30, 33).addYears(7) == DateTime(2006, 7, 06, 12, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33).addYears(-7) == DateTime(1992, 7, 06, 12, 30, 33));
}

unittest // DateTime.month
{
    assert(DateTime.init.month == 1);
    assert(DateTime(1999, 7, 6, 12, 30, 33).month == 7);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.month == 7);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.month == 7);

    assert(DateTime(1999, 8, 6, 12, 30, 33).addMonths(7) == DateTime(2000, 3, 6, 12, 30, 33));
    assert(DateTime(1999, 8, 6, 12, 30, 33).addMonths(-7) == DateTime(1999, 1, 6, 12, 30, 33));
}

unittest // DateTime.day
{
    assert(DateTime(1999, 7, 6, 9, 7, 5).day == 6);
    assert(DateTime(2010, 10, 4, 0, 0, 30).day == 4);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.day == 6);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.day == 6);

    assert(DateTime(1999, 7, 6, 12, 30, 33).addDays(7) == DateTime(1999, 7, 13, 12, 30, 33), DateTime(1999, 7, 6, 12, 30, 33).addDays(7).toString());
    assert(DateTime(1999, 7, 6, 12, 30, 33).addDays(-7) == DateTime(1999, 6, 29, 12, 30, 33), DateTime(1999, 7, 6, 12, 30, 33).addDays(-7).toString());
}

unittest // DateTime.hour
{
    assert(DateTime.init.hour == 0);
    assert(DateTime(1, 1, 1, 12, 0, 0).hour == 12);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.hour == 12);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.hour == 12);

    assert(DateTime(1999, 7, 6, 12, 30, 33).addHours(7) == DateTime(1999, 7, 6, 19, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33).addHours(-7) == DateTime(1999, 7, 6, 5, 30, 33));
}

unittest // DateTime.minute
{
    assert(DateTime.init.minute == 0);
    assert(DateTime(1, 1, 1, 0, 30, 0).minute == 30);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.minute == 30);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.minute == 30);

    assert(DateTime(1999, 7, 6, 12, 30, 33).addMinutes(7) == DateTime(1999, 7, 6, 12, 37, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33).addMinutes(-7) == DateTime(1999, 7, 6, 12, 23, 33));
}

unittest // DateTime.second
{
    assert(DateTime.init.second == 0);
    assert(DateTime(1, 1, 1, 0, 0, 33, 999).second == 33);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33, 999);
    assert(cdt.second == 33);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33, 999);
    assert(idt.second == 33);

    assert(DateTime(1999, 7, 6, 12, 30, 33).addSeconds(7) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33).addSeconds(-7) == DateTime(1999, 7, 6, 12, 30, 26));
}

unittest // DateTime.millisecond
{
    assert(DateTime.init.millisecond == 0);
    assert(DateTime(1, 1, 1, 0, 0, 33, 999).millisecond == 999);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33, 1);
    assert(cdt.millisecond == 1);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33, 500);
    assert(idt.millisecond == 500);

    assert(DateTime(1999, 7, 6, 12, 30, 33).addMilliseconds(7_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33).addMilliseconds(-7_000) == DateTime(1999, 7, 6, 12, 30, 26));
}

unittest // DateTime.min
{
    assert(DateTime.min.year == 1);
    assert(DateTime.min.month == 1);
    assert(DateTime.min.day == 1);
    assert(DateTime.min.hour == 0);
    assert(DateTime.min.minute == 0);
    assert(DateTime.min.second == 0);
    assert(DateTime.min.millisecond == 0);
}

unittest // DateTime.max
{
    assert(DateTime.max.year == 9999);
    assert(DateTime.max.month == 12);
    assert(DateTime.max.day == 31);
    assert(DateTime.max.hour == 23);
    assert(DateTime.max.minute == 59);
    assert(DateTime.max.second == 59);
    assert(DateTime.max.millisecond == 999);

    assert(DateTime.min < DateTime.max);
    assert(DateTime.max > DateTime.min);
}

unittest // DateTime.julianDay
{
    import std.conv : to;

    assert(Tick.round(DateTime.min.julianDay) == 1721424, Tick.round(DateTime.min.julianDay).to!string());
    assert(Tick.round(DateTime.max.julianDay) == 5373484, Tick.round(DateTime.max.julianDay).to!string());
    assert(Tick.round(DateTime(1, 1, 1, 12, 0, 0, 0).julianDay) == 1721424, Tick.round(DateTime(1, 1, 1, 12, 0, 0, 0).julianDay).to!string());
}

unittest // DateTime.opBinary
{
    import core.time : dur;
    import std.conv : to;

    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"days"(7) == DateTime(1999, 7, 13, 12, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"days"(-7) == DateTime(1999, 6, 29, 12, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"hours"(7) == DateTime(1999, 7, 6, 19, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"hours"(-7) == DateTime(1999, 7, 6, 5, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"minutes"(7) == DateTime(1999, 7, 6, 12, 37, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"minutes"(-7) == DateTime(1999, 7, 6, 12, 23, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"seconds"(7) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"seconds"(-7) == DateTime(1999, 7, 6, 12, 30, 26));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"msecs"(7_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"msecs"(-7_000) == DateTime(1999, 7, 6, 12, 30, 26));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"usecs"(7_000_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"usecs"(-7_000_000) == DateTime(1999, 7, 6, 12, 30, 26));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"hnsecs"(70_000_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) + dur!"hnsecs"(-70_000_000) == DateTime(1999, 7, 6, 12, 30, 26));

    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"days"(-7) == DateTime(1999, 7, 13, 12, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"days"(7) == DateTime(1999, 6, 29, 12, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"hours"(-7) == DateTime(1999, 7, 6, 19, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"hours"(7) == DateTime(1999, 7, 6, 5, 30, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"minutes"(-7) == DateTime(1999, 7, 6, 12, 37, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"minutes"(7) == DateTime(1999, 7, 6, 12, 23, 33));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"seconds"(-7) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"seconds"(7) == DateTime(1999, 7, 6, 12, 30, 26));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"msecs"(-7_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"msecs"(7_000) == DateTime(1999, 7, 6, 12, 30, 26));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"usecs"(-7_000_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"usecs"(7_000_000) == DateTime(1999, 7, 6, 12, 30, 26));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"hnsecs"(-70_000_000) == DateTime(1999, 7, 6, 12, 30, 40));
    assert(DateTime(1999, 7, 6, 12, 30, 33) - dur!"hnsecs"(70_000_000) == DateTime(1999, 7, 6, 12, 30, 26));

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt + dur!"seconds"(12) == DateTime(1999, 7, 6, 12, 30, 45));
    assert(cdt - dur!"seconds"(12) == DateTime(1999, 7, 6, 12, 30, 21));

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt + dur!"seconds"(12) == DateTime(1999, 7, 6, 12, 30, 45));
    assert(idt - dur!"seconds"(12) == DateTime(1999, 7, 6, 12, 30, 21));
}

unittest // DateTime.opBinary
{
    import core.time : dur;
    import std.conv : to;

    static string toString(ubyte decimals = 4)(const(double) n) nothrow pure
    {
        import std.conv : to;
        import std.format : format;

        scope (failure) assert(0, "Assume nothrow");

        enum fmt = "%." ~ decimals.to!string ~ "f";
        return format(fmt, n);
    }

    static bool approxEqual(ubyte decimals = 4)(const(double) lhs, const(double) rhs) nothrow pure
    {
        import std.conv : to;
        import std.math.operations : isClose;

        enum maxRelDiff = ("1e-" ~ decimals.to!string).to!double;
        return isClose(lhs, rhs, maxRelDiff);
    }

    assert((DateTime(1999, 7, 6, 12, 30, 33) - DateTime(1998, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(31_536_000));
    assert((DateTime(1998, 7, 6, 12, 30, 33) - DateTime(1999, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(-31_536_000));
    assert((DateTime(1999, 8, 6, 12, 30, 33) - DateTime(1999, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(26_78_400));
    assert((DateTime(1999, 7, 6, 12, 30, 33) - DateTime(1999, 8, 6, 12, 30, 33)).toDuration == dur!"seconds"(-26_78_400));
    assert((DateTime(1999, 7, 6, 12, 30, 33) - DateTime(1999, 7, 5, 12, 30, 33)).toDuration == dur!"seconds"(86_400));
    assert((DateTime(1999, 7, 5, 12, 30, 33) - DateTime(1999, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(-86_400));
    assert((DateTime(1999, 7, 6, 12, 30, 33) - DateTime(1999, 7, 6, 11, 30, 33)).toDuration == dur!"seconds"(3_600));
    assert((DateTime(1999, 7, 6, 11, 30, 33) - DateTime(1999, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(-3_600));
    assert((DateTime(1999, 7, 6, 12, 31, 33) - DateTime(1999, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(60));
    assert((DateTime(1999, 7, 6, 12, 30, 33) - DateTime(1999, 7, 6, 12, 31, 33)).toDuration == dur!"seconds"(-60));
    assert((DateTime(1999, 7, 6, 12, 30, 34) - DateTime(1999, 7, 6, 12, 30, 33)).toDuration == dur!"seconds"(1));
    assert((DateTime(1999, 7, 6, 12, 30, 33) - DateTime(1999, 7, 6, 12, 30, 34)).toDuration == dur!"seconds"(-1));
    assert((DateTime(1, 1, 1, 12, 30, 33) - DateTime(1, 1, 1, 0, 0, 0)).toDuration == dur!"seconds"(45_033));
    assert((DateTime(1, 1, 1, 0, 0, 0) - DateTime(1, 1, 1, 12, 30, 33)).toDuration == dur!"seconds"(-45_033));

    auto dt = DateTime(1999, 7, 6, 12, 30, 33);
    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert((dt - dt).toDuration == Duration.zero);
    assert((cdt - dt).toDuration == Duration.zero);
    assert((idt - dt).toDuration == Duration.zero);
    assert((dt - cdt).toDuration == Duration.zero);
    assert((cdt - cdt).toDuration == Duration.zero);
    assert((idt - cdt).toDuration == Duration.zero);
    assert((dt - idt).toDuration == Duration.zero);
    assert((cdt - idt).toDuration == Duration.zero);
    assert((idt - idt).toDuration == Duration.zero);

	auto preDate = DateTime(2021, 7, 15, 0, 0, 0); //15 July 2021 00:00:00
    auto nowDate = DateTime(2024, 2, 13, 10, 49, 4); //13 February 2024 10:49:04
    assert(approxEqual!12((nowDate - preDate).totalDays, 943.450740740741), toString!12((nowDate - preDate).totalDays));
    assert(approxEqual!10((nowDate - preDate).totalHours, 22_642.8177777778), toString!10((nowDate - preDate).totalHours));
    assert(approxEqual!8((nowDate - preDate).totalMinutes, 1_358_569.06666667), toString!8((nowDate - preDate).totalMinutes));
    assert((nowDate - preDate).totalSeconds == 81_514_144, (nowDate - preDate).totalSeconds.to!string);
    assert((nowDate - preDate).totalMilliseconds == 81_514_144_000, (nowDate - preDate).totalMilliseconds.to!string);
    assert((nowDate - preDate).totalTicks == 815_141_440_000_000, (nowDate - preDate).totalTicks.to!string);
}

unittest // DateTime.toString
{
    assert(DateTime.max.toString() == "12/31/9999 11:59:59 PM", DateTime.max.toString());

    auto dt = DateTime(1999, 7, 6, 12, 30, 33, 1);
    assert(dt.toString() == "07/06/1999 12:30:33 PM", dt.toString());

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.toString() == "07/06/1999 12:30:33 PM", cdt.toString());

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.toString() == "07/06/1999 12:30:33 PM", idt.toString());
}

unittest // DateTime.dayOfWeek
{
    auto dt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(dt.dayOfWeek == DayOfWeek.tuesday);

    assert(DateTime(2021, 6, 4, 12, 12, 12).dayOfWeek == DayOfWeek.friday);

    const cdt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(cdt.dayOfWeek == DayOfWeek.tuesday);

    immutable idt = DateTime(1999, 7, 6, 12, 30, 33);
    assert(idt.dayOfWeek == DayOfWeek.tuesday);
}

unittest // DateTime.dayOfYear
{
    assert(DateTime(1999, 1, 1, 12, 22, 7).dayOfYear == 1);
    assert(DateTime(1999, 12, 31, 7, 2, 59).dayOfYear == 365);
    assert(DateTime(2000, 12, 31, 21, 20, 0).dayOfYear == 366);
}

unittest // DateTime.beginOfMonth
{
    assert(DateTime(1999, 1, 1, 0, 13, 26).beginOfMonth == DateTime(1999, 1, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 2, 2, 1, 14, 27).beginOfMonth == DateTime(1999, 2, 1, 0, 0, 0, 0));
    assert(DateTime(2000, 2, 3, 2, 15, 28).beginOfMonth == DateTime(2000, 2, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 3, 4, 3, 16, 29).beginOfMonth == DateTime(1999, 3, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 4, 5, 4, 17, 30).beginOfMonth == DateTime(1999, 4, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 5, 16, 5, 18, 31).beginOfMonth == DateTime(1999, 5, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 6, 17, 6, 19, 32).beginOfMonth == DateTime(1999, 6, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 7, 18, 7, 20, 33).beginOfMonth == DateTime(1999, 7, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 8, 19, 8, 21, 34).beginOfMonth == DateTime(1999, 8, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 9, 24, 9, 22, 35).beginOfMonth == DateTime(1999, 9, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 10, 25, 10, 23, 36).beginOfMonth == DateTime(1999, 10, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 11, 26, 11, 24, 37).beginOfMonth == DateTime(1999, 11, 1, 0, 0, 0, 0));
    assert(DateTime(1999, 12, 31, 12, 25, 38).beginOfMonth == DateTime(1999, 12, 1, 0, 0, 0, 0));
}

unittest // DateTime.endOfMonth
{
    assert(DateTime(1999, 1, 1, 0, 13, 26).endOfMonth == DateTime(Date(1999, 1, 31), Time.max));
    assert(DateTime(1999, 2, 2, 1, 14, 27).endOfMonth == DateTime(Date(1999, 2, 28), Time.max));
    assert(DateTime(2000, 2, 3, 2, 15, 28).endOfMonth == DateTime(Date(2000, 2, 29), Time.max));
    assert(DateTime(1999, 3, 4, 3, 16, 29).endOfMonth == DateTime(Date(1999, 3, 31), Time.max));
    assert(DateTime(1999, 4, 5, 4, 17, 30).endOfMonth == DateTime(Date(1999, 4, 30), Time.max));
    assert(DateTime(1999, 5, 16, 5, 18, 31).endOfMonth == DateTime(Date(1999, 5, 31), Time.max));
    assert(DateTime(1999, 6, 17, 6, 19, 32).endOfMonth == DateTime(Date(1999, 6, 30), Time.max));
    assert(DateTime(1999, 7, 18, 7, 20, 33).endOfMonth == DateTime(Date(1999, 7, 31), Time.max));
    assert(DateTime(1999, 8, 19, 8, 21, 34).endOfMonth == DateTime(Date(1999, 8, 31), Time.max));
    assert(DateTime(1999, 9, 21, 9, 22, 35).endOfMonth == DateTime(Date(1999, 9, 30), Time.max));
    assert(DateTime(1999, 10, 22, 10, 23, 36).endOfMonth == DateTime(Date(1999, 10, 31), Time.max));
    assert(DateTime(1999, 11, 23, 11, 24, 37).endOfMonth == DateTime(Date(1999, 11, 30), Time.max));
    assert(DateTime(1999, 12, 24, 12, 25, 38).endOfMonth == DateTime(Date(1999, 12, 31), Time.max));
    assert(DateTime(1999, 12, 25, 12, 25, 38).endOfMonth.toString() == "12/31/1999 11:59:59 PM", DateTime(1999, 12, 25, 12, 25, 38).endOfMonth.toString());
}

unittest // Date.constructor
{
    auto d1 = Date.init;
    assert(d1.year == 1);
    assert(d1.month == 1);
    assert(d1.day == 1);

    auto d2 = Date(1);
    assert(d2.year == 1);
    assert(d2.month == 1);
    assert(d2.day == 2);

    auto d3 = Date(1999, 7 ,6);
    assert(d3.year == 1999);
    assert(d3.month == 7);
    assert(d3.day == 6);
}

unittest // Date.opCmp
{
    assert(Date(1999, 1, 1).opCmp(Date(1999, 1, 1)) == 0);
    assert(Date(1, 7, 1).opCmp(Date(1, 7, 1)) == 0);
    assert(Date(1, 1, 6).opCmp(Date(1, 1, 6)) == 0);
    assert(Date(1999, 7, 1).opCmp(Date(1999, 7, 1)) == 0);
    assert(Date(1999, 7, 6).opCmp(Date(1999, 7, 6)) == 0);
    assert(Date(1, 7, 6).opCmp(Date(1, 7, 6)) == 0);

    auto dt = Date(1999, 7, 6);
    const cdt = Date(1999, 7, 6);
    immutable idt = Date(1999, 7, 6);
    assert(dt.opCmp(dt) == 0);
    assert(dt.opCmp(cdt) == 0);
    assert(dt.opCmp(idt) == 0);
    assert(cdt.opCmp(dt) == 0);
    assert(cdt.opCmp(cdt) == 0);
    assert(cdt.opCmp(idt) == 0);
    assert(idt.opCmp(dt) == 0);
    assert(idt.opCmp(cdt) == 0);
    assert(idt.opCmp(idt) == 0);

    assert(Date(1999, 7, 6).opCmp(Date(2000, 7, 6)) < 0);
    assert(Date(1999, 7, 6).opCmp(Date(1999, 8, 6)) < 0);
    assert(Date(1999, 7, 6).opCmp(Date(1999, 7, 7)) < 0);
    assert(Date(1999, 8, 7).opCmp(Date(2000, 7, 6)) < 0);
    assert(Date(1999, 7, 7).opCmp(Date(2000, 7, 6)) < 0);
    assert(Date(1999, 7, 7).opCmp(Date(1999, 8, 6)) < 0);

    assert(Date(2000, 7, 6).opCmp(Date(1999, 7, 6)) > 0);
    assert(Date(1999, 8, 6).opCmp(Date(1999, 7, 6)) > 0);
    assert(Date(1999, 7, 7).opCmp(Date(1999, 7, 6)) > 0);
    assert(Date(2000, 8, 6).opCmp(Date(1999, 7, 7)) > 0);
    assert(Date(2000, 7, 6).opCmp(Date(1999, 7, 7)) > 0);
    assert(Date(1999, 8, 6).opCmp(Date(1999, 7, 7)) > 0);
}

unittest // Date.opEquals
{
    assert(Date(1999, 1, 1).opEquals(Date(1999, 1, 1)));

    assert(!Date(1999, 12, 30).opEquals(Date(1999, 1, 1)));
    assert(!Date.min.opEquals(Date.max));
}

unittest // Date.year
{
    assert(Date.init.year == 1);
    assert(Date(1999, 7, 6).year == 1999);

    const cdt = Date(1999, 7, 6);
    assert(cdt.year == 1999);

    immutable idt = Date(1999, 7, 6);
    assert(idt.year == 1999);

    assert(Date(1999, 7, 6).addYears(7) == Date(2006, 7, 06));
    assert(Date(1999, 7, 6).addYears(-7) == Date(1992, 7, 06));
}

unittest // Date.month
{
    assert(Date.init.month == 1);
    assert(Date(1999, 7, 6).month == 7);

    const cdt = Date(1999, 7, 6);
    assert(cdt.month == 7);

    immutable idt = Date(1999, 7, 6);
    assert(idt.month == 7);

    assert(Date(1999, 8, 6).addMonths(7) == Date(2000, 3, 6));
    assert(Date(1999, 8, 6).addMonths(-7) == Date(1999, 1, 6));
}

unittest // Date.day
{
    assert(Date(1999, 7, 6).day == 6);
    assert(Date(2010, 10, 4).day == 4);

    const cdt = DateTime(1999, 7, 6);
    assert(cdt.day == 6);

    immutable idt = DateTime(1999, 7, 6);
    assert(idt.day == 6);

    assert(Date(1999, 7, 6).addDays(7) == Date(1999, 7, 13));
    assert(Date(1999, 7, 6).addDays(-7) == Date(1999, 6, 29));
}

unittest // Date.min
{
    assert(Date.min.year == 1);
    assert(Date.min.month == 1);
    assert(Date.min.day == 1);
}

unittest // Date.max
{
    assert(Date.max.year == 9999);
    assert(Date.max.month == 12);
    assert(Date.max.day == 31);

    assert(Date.min < Date.max);
    assert(Date.max > Date.min);
}

unittest // Date.julianDay
{
    import std.conv : to;

    assert(Tick.round(Date.min.julianDay) == 1721424, Tick.round(Date.min.julianDay).to!string());
    assert(Tick.round(Date.max.julianDay) == 5373484, Tick.round(Date.max.julianDay).to!string());
    assert(Tick.round(Date(1, 1, 1).julianDay) == 1721424, Tick.round(Date(1, 1, 1).julianDay).to!string());
}

unittest // Date.opBinary
{
    import core.time : dur;
    import std.conv : to;

    assert(Date(1999, 7, 6) + dur!"days"(7) == Date(1999, 7, 13));
    assert(Date(1999, 7, 6) + dur!"days"(-7) == Date(1999, 6, 29));

    assert(Date(1999, 7, 6) - dur!"days"(-7) == Date(1999, 7, 13));
    assert(Date(1999, 7, 6) - dur!"days"(7) == Date(1999, 6, 29));

    assert(Date(1999, 7, 6) + Time(1, 1, 1, 1) == DateTime(1999, 7, 6, 1, 1, 1, 1));
}

unittest // Date.opBinary
{
    import core.time : dur;
    import std.conv : to;

    assert((Date(1999, 7, 6) - Date(1998, 7, 6)).toDuration == dur!"seconds"(31_536_000));
    assert((Date(1998, 7, 6) - Date(1999, 7, 6)).toDuration == dur!"seconds"(-31_536_000));
    assert((Date(1999, 8, 6) - Date(1999, 7, 6)).toDuration == dur!"seconds"(26_78_400));
    assert((Date(1999, 7, 6) - Date(1999, 8, 6)).toDuration == dur!"seconds"(-26_78_400));
    assert((Date(1999, 7, 6) - Date(1999, 7, 5)).toDuration == dur!"seconds"(86_400));
    assert((Date(1999, 7, 5) - Date(1999, 7, 6)).toDuration == dur!"seconds"(-86_400));

    auto dt = Date(1999, 7, 6);
    const cdt = Date(1999, 7, 6);
    immutable idt = Date(1999, 7, 6);
    assert((dt - dt).toDuration == Duration.zero);
    assert((cdt - dt).toDuration == Duration.zero);
    assert((idt - dt).toDuration == Duration.zero);
    assert((dt - cdt).toDuration == Duration.zero);
    assert((cdt - cdt).toDuration == Duration.zero);
    assert((idt - cdt).toDuration == Duration.zero);
    assert((dt - idt).toDuration == Duration.zero);
    assert((cdt - idt).toDuration == Duration.zero);
    assert((idt - idt).toDuration == Duration.zero);

	auto preDate = Date(2021, 7, 15); //15 July 2021
    auto nowDate = Date(2024, 2, 13); //13 February 2024
    assert((nowDate - preDate).totalDays == 943);
    assert((nowDate - preDate).totalHours == 22_632);
    assert((nowDate - preDate).totalMinutes == 1_357_920);
    assert((nowDate - preDate).totalSeconds == 81_475_200);
    assert((nowDate - preDate).totalMilliseconds == 81_475_200_000);
    assert((nowDate - preDate).totalTicks == 814_752_000_000_000);
}

unittest // Date.toString
{
    assert(Date.max.toString() == "12/31/9999", Date.max.toString());

    auto dt = Date(1999, 7, 6);
    assert(dt.toString() == "07/06/1999", dt.toString());

    const cdt = Date(1999, 7, 6);
    assert(cdt.toString() == "07/06/1999", cdt.toString());

    immutable idt = Date(1999, 7, 6);
    assert(idt.toString() == "07/06/1999", idt.toString());
}

unittest // Date.dayOfWeek
{
    auto dt = Date(1999, 7, 6);
    assert(dt.dayOfWeek == DayOfWeek.tuesday);

    assert(Date(2021, 6, 4).dayOfWeek == DayOfWeek.friday);

    const cdt = Date(1999, 7, 6);
    assert(cdt.dayOfWeek == DayOfWeek.tuesday);

    immutable idt = Date(1999, 7, 6);
    assert(idt.dayOfWeek == DayOfWeek.tuesday);
}

unittest // Date.dayOfYear
{
    assert(Date(1999, 1, 1).dayOfYear == 1);
    assert(Date(1999, 12, 31).dayOfYear == 365);
    assert(Date(2000, 12, 31).dayOfYear == 366);
}

unittest // Date.beginOfMonth
{
    assert(Date(1999, 1, 1).beginOfMonth == Date(1999, 1, 1));
    assert(Date(1999, 2, 2).beginOfMonth == Date(1999, 2, 1));
    assert(Date(2000, 2, 3).beginOfMonth == Date(2000, 2, 1));
    assert(Date(1999, 3, 4).beginOfMonth == Date(1999, 3, 1));
    assert(Date(1999, 4, 5).beginOfMonth == Date(1999, 4, 1));
    assert(Date(1999, 5, 16).beginOfMonth == Date(1999, 5, 1));
    assert(Date(1999, 6, 17).beginOfMonth == Date(1999, 6, 1));
    assert(Date(1999, 7, 18).beginOfMonth == Date(1999, 7, 1));
    assert(Date(1999, 8, 19).beginOfMonth == Date(1999, 8, 1));
    assert(Date(1999, 9, 25).beginOfMonth == Date(1999, 9, 1));
    assert(Date(1999, 10, 26).beginOfMonth == Date(1999, 10, 1));
    assert(Date(1999, 11, 27).beginOfMonth == Date(1999, 11, 1));
    assert(Date(1999, 12, 31).beginOfMonth == Date(1999, 12, 1));
}

unittest // Date.endOfMonth
{
    assert(Date(1999, 1, 1).endOfMonth == Date(1999, 1, 31));
    assert(Date(1999, 2, 2).endOfMonth == Date(1999, 2, 28));
    assert(Date(2000, 2, 3).endOfMonth == Date(2000, 2, 29));
    assert(Date(1999, 3, 4).endOfMonth == Date(1999, 3, 31));
    assert(Date(1999, 4, 5).endOfMonth == Date(1999, 4, 30));
    assert(Date(1999, 5, 11).endOfMonth == Date(1999, 5, 31));
    assert(Date(1999, 6, 12).endOfMonth == Date(1999, 6, 30));
    assert(Date(1999, 7, 13).endOfMonth == Date(1999, 7, 31));
    assert(Date(1999, 8, 14).endOfMonth == Date(1999, 8, 31));
    assert(Date(1999, 9, 15).endOfMonth == Date(1999, 9, 30));
    assert(Date(1999, 10, 21).endOfMonth == Date(1999, 10, 31));
    assert(Date(1999, 11, 22).endOfMonth == Date(1999, 11, 30));
    assert(Date(1999, 12, 23).endOfMonth == Date(1999, 12, 31));
}

unittest // ...Between
{
    import std.conv : to;

    // Date
	auto preDate = Date(2021, 7, 15); //15 July 2021
    auto nowDate = Date(2024, 2, 13); //13 February 2024
    assert(yearsBetween(nowDate, preDate) == 2, yearsBetween(nowDate, preDate).to!string);
    assert(monthsBetween(nowDate, preDate) == 30, monthsBetween(nowDate, preDate).to!string);
    assert(weeksBetween(nowDate, preDate) == 134, weeksBetween(nowDate, preDate).to!string);
    assert(daysBetween(nowDate, preDate) == 943, daysBetween(nowDate, preDate).to!string);
    assert(hoursBetween(nowDate, preDate) == 22_632);
    assert(minutesBetween(nowDate, preDate) == 1_357_920);
    assert(secondsBetween(nowDate, preDate) == 81_475_200);
    assert(millisecondsBetween(nowDate, preDate) == 81_475_200_000);
    assert(ticksBetween(nowDate, preDate) == 814_752_000_000_000);

    // DateTime
	auto preDateTime = DateTime(2021, 7, 15, 0, 0, 0); //15 July 2021 00:00:00
    auto nowDateTime = DateTime(2024, 2, 13, 10, 49, 4); //13 February 2024 10:49:04
    assert(yearsBetween(nowDateTime, preDateTime) == 2, yearsBetween(nowDateTime, preDateTime).to!string);
    assert(monthsBetween(nowDateTime, preDateTime) == 30, monthsBetween(nowDateTime, preDateTime).to!string);
    assert(weeksBetween(nowDateTime, preDateTime) == 134, weeksBetween(nowDateTime, preDateTime).to!string);
    assert(daysBetween(nowDateTime, preDateTime) == 943, daysBetween(nowDateTime, preDateTime).to!string);
    assert(hoursBetween(nowDateTime, preDateTime) == 22_642, hoursBetween(nowDateTime, preDateTime).to!string);
    assert(minutesBetween(nowDateTime, preDateTime) == 1_358_569, minutesBetween(nowDateTime, preDateTime).to!string);
    assert(secondsBetween(nowDateTime, preDateTime) == 81_514_144, secondsBetween(nowDateTime, preDateTime).to!string);
    assert(millisecondsBetween(nowDateTime, preDateTime) == 81_514_144_000, millisecondsBetween(nowDateTime, preDateTime).to!string);
    assert(ticksBetween(nowDateTime, preDateTime) == 815_141_440_000_000, ticksBetween(nowDateTime, preDateTime).to!string);

    // Time
	auto preTime = Time(0, 0, 0);
    auto nowTime = Time(19, 22, 7);
    assert(yearsBetween(nowTime, preTime) == 0, yearsBetween(nowTime, preTime).to!string);
    assert(monthsBetween(nowTime, preTime) == 0, monthsBetween(nowTime, preTime).to!string);
    assert(daysBetween(nowTime, preTime) == 0, daysBetween(nowTime, preTime).to!string);
    assert(hoursBetween(nowTime, preTime) == 19, hoursBetween(nowTime, preTime).to!string);
    assert(minutesBetween(nowTime, preTime) == 1_162, minutesBetween(nowTime, preTime).to!string);
    assert(secondsBetween(nowTime, preTime) == 69_727, secondsBetween(nowTime, preTime).to!string);
    assert(millisecondsBetween(nowTime, preTime) == 69_727_000, millisecondsBetween(nowTime, preTime).to!string);
    assert(ticksBetween(nowTime, preTime) == 697_270_000_000, ticksBetween(nowTime, preTime).to!string);
}
