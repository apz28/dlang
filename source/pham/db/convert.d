/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.convert;

import core.time : convert;
import std.conv : to;
import std.datetime.date : DateTime, TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : assumeWontThrow;
import std.math : pow;

version (unittest) import pham.utl.utltest;
import pham.db.type;

nothrow @safe:

Decimal decimalDecode(T)(T value, int32 integralScale, RoundingMode roundingMode = RoundingMode.banking)
if (is(T == int16) || is(T == int32) || is(T == int64) || is(T == float32) || is(T == float64))
{
    static int32 precision() nothrow pure @safe
    {
        static if (T.sizeof == 2)
            return 5;
        else static if (T.sizeof == 4)
            return 10;
        else
            return 20;
    }

	auto result = Decimal(value, precision(), roundingMode);
	static if (is(T == int16) || is(T == int32) || is(T == int64))
        return result.scaleFrom(integralScale, roundingMode);
    else
        return result;
}

T decimalEncode(T)(scope Decimal value, int32 integralScale, RoundingMode roundingMode = RoundingMode.banking)
if (is(T == int16) || is(T == int32) || is(T == int64) || is(T == float32) || is(T == float64))
{
    return value.scaleTo!T(integralScale, roundingMode);
}

Duration minDuration(Duration value, const int64 minSecond = 0) pure
{
    return value.total!"seconds"() >= minSecond ? value : dur!"seconds"(minSecond);
}

int64 removeUnitsFromHNSecs(string units)(int64 hnsecs) pure
if (units == "weeks" || units == "days" || units == "hours" || units == "minutes" || units == "seconds"
    || units == "msecs" || units == "usecs" || units == "hnsecs")
{
    const value = convert!("hnsecs", units)(hnsecs);
    return hnsecs - convert!(units, "hnsecs")(value);
}

Duration removeDate(scope const Duration value) pure
{
    auto hnsecs = removeUnitsFromHNSecs!"days"(value.total!"hnsecs");
    if (hnsecs < 0)
        hnsecs += hnsecsPerDay;
    return dur!"hnsecs"(hnsecs);
}

Duration timeOfDayToDuration(scope const SysTime value)
{
    return removeDate(dur!"hnsecs"(value.timezone.utcToTZ(value.stdTime)));
}

Duration timeOfDayToDuration(scope const TimeOfDay value) pure
{
    return dur!"hours"(value.hour) + dur!"minutes"(value.minute) + dur!"seconds"(value.second);
}

Date toDate(int32 validYear, int32 validMonth, int32 validDay) pure
{
    return assumeWontThrow(Date(validYear, validMonth, validDay));
}

I toInt(I)(scope const(char)[] validValue, I emptyValue = 0) pure
if (is(I == int) || is(I == uint)
    || is(I == short) || is(I == ushort)
    || is(I == long) || is(I == ulong))
{
    return validValue.length != 0 ? assumeWontThrow(to!I(validValue)) : emptyValue;
}

Decimal toDecimal(const(char)[] validDecimal)
{
    return assumeWontThrow(Decimal(validDecimal));
}

int64 toMinSecond(scope const Duration value, const int64 minSecond = 0) pure
{
    const result = value.total!"seconds"();
    return result >= minSecond ? result : minSecond;
}

int32 toInt32Second(scope const Duration value, const int32 maxSecond = int32.max) pure
{
    const result = toMinSecond(value);
    return result <= maxSecond ? cast(int32)result : maxSecond;
}

string toString(C)(C c)
if (is(C == char) || is(C == wchar) || is(C == dchar))
{
    return assumeWontThrow(to!string(c));
}

string toString(S)(S s)
if (is(S == wstring) || is(S == dstring))
{
    return assumeWontThrow(to!string(s));
}

Duration secondToDuration(const(char)[] validSecond) pure
{
    return dur!"seconds"(toInt!int64(validSecond));
}

bool isDSTBug(in DateTime forDT, ref Duration biasDuration) @trusted
{
    version (Windows)
    {
		import core.sys.windows.winbase : TIME_ZONE_INFORMATION, GetTimeZoneInformation;

        TIME_ZONE_INFORMATION tzInfo;
		GetTimeZoneInformation(&tzInfo);

		version (TraceFunction)
        dgFunctionTrace("DaylightBias=", tzInfo.DaylightBias,
			", DaylightDate.wYear=", tzInfo.DaylightDate.wYear,
            ", DaylightDate.wMonth=", tzInfo.DaylightDate.wMonth,
            ", DaylightDate.wDay=", tzInfo.DaylightDate.wDay,
            ", DaylightDate.wHour=", tzInfo.DaylightDate.wHour,
			", StandardBias=", tzInfo.StandardBias,
			", StandardDate.wYear=", tzInfo.StandardDate.wYear,
            ", StandardDate.wMonth=", tzInfo.StandardDate.wMonth,
            ", StandardDate.wDay=", tzInfo.StandardDate.wDay,
            ", StandardDate.wHour=", tzInfo.StandardDate.wHour);

		if (tzInfo.DaylightDate.wMonth == 0 || tzInfo.DaylightBias == 0)
            return false;

        bool dstObserved() nothrow
        {
            biasDuration = dur!"minutes"(tzInfo.DaylightBias);
            return true;
        }

        if (tzInfo.DaylightDate.wYear == 0)
        {
            const forDtMonth = forDT.month;
            if (forDtMonth > tzInfo.DaylightDate.wMonth && forDtMonth < tzInfo.StandardDate.wMonth)
                return dstObserved();
            else if (forDtMonth == tzInfo.DaylightDate.wMonth)
            {
                const forDtDay = forDT.day;
                if (forDtDay > tzInfo.DaylightDate.wDay)
                    return dstObserved();
                else if (forDtDay == tzInfo.DaylightDate.wDay && forDT.hour >= tzInfo.DaylightDate.wHour)
                    return dstObserved();
            }
            else if (forDtMonth == tzInfo.StandardDate.wMonth)
            {
                const forDtDay = forDT.day;
                if (forDtDay < tzInfo.StandardDate.wDay)
                    return dstObserved();
                else if (forDtDay == tzInfo.StandardDate.wDay && forDT.hour < tzInfo.StandardDate.wHour)
                    return dstObserved();
            }
        }
        else if (forDT.year >= tzInfo.DaylightDate.wYear)
            return dstObserved();
    }

    return false;
}


// Any below codes are private
private:


unittest // toInt
{
    import pham.utl.utltest;
    dgWriteln("unittest db.util.toInt");

    assert(toInt!int("") == 0);
    assert(toInt!int("", int.max) == int.max);
    assert(toInt!int("1") == 1);
    assert(toInt!int("98765432") == 98_765_432);
    assert(toInt!int("-1") == -1);
    assert(toInt!int("-8765324") == -8_765_324);
}

unittest // toString
{
    import pham.utl.utltest;
    dgWriteln("unittest db.util.toString");

    assert(toString('a') == "a");
    assert(toString(wchar('b')) == "b");
    assert(toString(dchar('c')) == "c");

    assert(toString("b"w) == "b");
    assert(toString("c"d) == "c");
}