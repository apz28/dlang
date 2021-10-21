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

module pham.db.myconvert;

import std.traits: isUnsigned, Unqual;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.datetime.tick : Tick, TickPart;
import pham.db.type;
import pham.db.myoid;

nothrow @safe:

Date dateDecode(scope const(ubyte)[] myDateBytes) @nogc pure
in
{
	assert(myDateBytes.length == 4);
}
do
{
	const year = myDateBytes[0] + (cast(int)myDateBytes[1] << 8);
	const month = cast(int)myDateBytes[2];
	const day = cast(int)myDateBytes[3];
	return Date(year, month, day);
}

enum maxDateBufferSize = 5;
uint8 dateEncode(ref ubyte[maxDateBufferSize] myDateBytes, scope const(Date) date) @nogc pure
{
	if (date.days == 0)
    {
		myDateBytes[0] = 0;
		return 1;
    }

    const year = date.year;
	myDateBytes[0] = 4u;
	myDateBytes[1] = cast(ubyte)(year & 0xFF);
	myDateBytes[2] = cast(ubyte)((year >> 8) & 0xFF);
	myDateBytes[3] = cast(ubyte)date.month;
	myDateBytes[4] = cast(ubyte)date.day;
	return 5;
}

DbDateTime dateTimeDecode(scope const(ubyte)[] myDateTimeBytes) @nogc pure
in
{
	assert(myDateTimeBytes.length == 4 || myDateTimeBytes.length == 7 || myDateTimeBytes.length == 11);
}
do
{
    const year = myDateTimeBytes[0] + (cast(int)myDateTimeBytes[1] << 8);
	const month = cast(int)myDateTimeBytes[2];
	const day = cast(int)myDateTimeBytes[3];

	if (myDateTimeBytes.length == 4)
		return DbDateTime(DateTime(year, month, day), 0);

	const hour = cast(int)myDateTimeBytes[4];
	const minute = cast(int)myDateTimeBytes[5];
	const second = cast(int)myDateTimeBytes[6];

	if (myDateTimeBytes.length == 7)
		return DbDateTime(DateTime(year, month, day, hour, minute, second), 0);

	const int microsecond = cast(int)uintDecode!(uint)(myDateTimeBytes[7..$]);
	return DbDateTime(DateTime(year, month, day, hour, minute, second).addTicksSafe(TickPart.microsecondToTick(microsecond)), 0);
}

enum maxDateTimeBufferSize = 12;
uint8 dateTimeEncode(ref ubyte[maxDateTimeBufferSize] myDateTimeBytes, scope const(DbDateTime) dateTime) @nogc pure
{
	if (dateTime.value.uticks == 0)
    {
		myDateTimeBytes[0] = 0;
		return 1;
    }

	int year = void, month = void, day = void, hour = void, minute = void, second = void, tick = void;
	dateTime.value.getDate(year, month, day);
	dateTime.value.getTimePrecise(hour, minute, second, tick);

	myDateTimeBytes[1] = cast(ubyte)(year & 0xFF);
	myDateTimeBytes[2] = cast(ubyte)((year >> 8) & 0xFF);
	myDateTimeBytes[3] = cast(ubyte)month;
	myDateTimeBytes[4] = cast(ubyte)day;

	if (hour || minute || second || tick)
    {
		myDateTimeBytes[5] = cast(ubyte)hour;
		myDateTimeBytes[6] = cast(ubyte)minute;
		myDateTimeBytes[7] = cast(ubyte)second;

		if (tick)
        {
			myDateTimeBytes[8..12] = uintEncode!(uint32, 4u)(cast(uint32)TickPart.tickToMicrosecond(tick));

			myDateTimeBytes[0] = 11;
			return 12;
        }

		myDateTimeBytes[0] = 7;
		return 8;
    }

    myDateTimeBytes[0] = 4;
	return 5;
}

DbTimeSpan timeSpanDecode(scope const(ubyte)[] myTimeBytes) @nogc pure
in
{
	assert(myTimeBytes.length == 8 || myTimeBytes.length == 12);
}
do
{
	auto result = Duration.zero;
	result += dur!"days"(cast(int)uintDecode!(uint)(myTimeBytes[1..5]));
	result += dur!"hours"(cast(int)myTimeBytes[5]);
	result += dur!"minutes"(cast(int)myTimeBytes[6]);
	result += dur!"seconds"(cast(int)myTimeBytes[7]);
	if (myTimeBytes.length == 12) // Microsecond?
        result += dur!"usecs"(cast(int)uintDecode!(uint)(myTimeBytes[8..$]));
	// Negative?
	return myTimeBytes[0] == 1 ? DbTimeSpan(-result) : DbTimeSpan(result);
}

enum maxTimeSpanBufferSize = 13;
uint8 timeSpanEncode(ref ubyte[maxTimeSpanBufferSize] myTimeSpanBytes, scope const(DbTimeSpan) timeSpan) @nogc pure
{
	if (timeSpan.isZero)
    {
		myTimeSpanBytes[0] = 0;
		return 1;
    }

	int day = void, hour = void, minute = void, second = void, microsecond = void;
	const isNeg = timeSpan.isNegative;
    if (isNeg)
        (-timeSpan.value).split!("days", "hours", "minutes", "seconds", "usecs")(day, hour, minute, second, microsecond);
    else
        timeSpan.value.split!("days", "hours", "minutes", "seconds", "usecs")(day, hour, minute, second, microsecond);
	myTimeSpanBytes[1] = isNeg ? 1 : 0;
	myTimeSpanBytes[2..6] = uintEncode!(uint32, 4u)(cast(uint32)day);
	myTimeSpanBytes[6] = cast(ubyte)hour;
	myTimeSpanBytes[7] = cast(ubyte)minute;
	myTimeSpanBytes[8] = cast(ubyte)second;

	if (microsecond != 0)
    {
		myTimeSpanBytes[9..13] = uintEncode!(uint32, 4u)(cast(uint32)microsecond);
		myTimeSpanBytes[0] = 12;
		return 13;
    }
	else
    {
		myTimeSpanBytes[0] = 8;
		return 9;
    }
}

pragma(inline, true)
T uintDecode(T)(scope const(ubyte)[] v)
if (isUnsigned!T && T.sizeof > 1)
in
{
    assert(v.length <= T.sizeof);
	assert(v.length == 2 || v.length == 3 || v.length == 4 || v.length == 8);
}
do
{
    int shift = 0;
	T result = cast(T)(v[0]); shift += 8;
	result |= cast(T)(v[1]) << shift;
	if (v.length >= 3u)
    {
		shift += 8;
		result |= cast(T)(v[2]) << shift;
    }
	if (v.length >= 4u)
    {
		shift += 8;
		result |= cast(T)(v[3]) << shift;
    }
	if (v.length >= 8u)
    {
		shift += 8;
		result |= cast(T)(v[4]) << shift; shift += 8;
		result |= cast(T)(v[5]) << shift; shift += 8;
		result |= cast(T)(v[6]) << shift; shift += 8;
		result |= cast(T)(v[7]) << shift;
    }

    return result;
}

pragma(inline, true)
ubyte[T.sizeof] uintEncode(T, uint8 NBytes)(T v)
if (isUnsigned!T && T.sizeof > 1
    && (NBytes == 2 || NBytes == 3 || NBytes == 4 || NBytes == 8)
    && NBytes <= T.sizeof)
{
    ubyte[T.sizeof] result = void;
    auto uv = cast(Unqual!T)v;

	result[0] = cast(ubyte)(uv & 0xFF); uv >>= 8;
	result[1] = cast(ubyte)(uv & 0xFF);
	static if (NBytes >= 3u)
    {
		uv >>= 8;
		result[2] = cast(ubyte)(uv & 0xFF);
    }
	static if (NBytes >= 4u)
    {
		uv >>= 8;
		result[3] = cast(ubyte)(uv & 0xFF);
    }
	static if (NBytes >= 8u)
    {
		uv >>= 8;
		result[4] = cast(ubyte)(uv & 0xFF); uv >>= 8;
		result[5] = cast(ubyte)(uv & 0xFF); uv >>= 8;
		result[6] = cast(ubyte)(uv & 0xFF); uv >>= 8;
		result[7] = cast(ubyte)(uv & 0xFF);
	}

	return result;
}

ubyte[T.sizeof + 1] uintEncodePacked(T)(T v, out uint8 nBytes)
if (isUnsigned!T && T.sizeof > 1)
{
    ubyte[T.sizeof + 1] result = void;

    if (v < MyPackedIntegerLimit.oneByte)
    {
        result[0] = cast(uint8)v;
		nBytes = 1;
    }
    else if (v < MyPackedIntegerLimit.twoByte)
    {
		result[0] = MyPackedIntegerIndicator.twoByte;
		result[1..$] = uintEncode!(T, 2u)(v);
        nBytes = 3;
    }
    else if (v < MyPackedIntegerLimit.threeByte)
    {
        result[0] = MyPackedIntegerIndicator.threeByte;
		result[1..$] = uintEncode!(T, 3u)(v);
        nBytes = 4;
    }
    else
    {
		static if (T.sizeof <= 4u)
        {
			result[0] = MyPackedIntegerIndicator.fourOrEightByte;
			result[1..$] = uintEncode!(T, 4u)(v);
			nBytes = 5;
        }
		else
        {
			result[0] = MyPackedIntegerIndicator.fourOrEightByte;
			result[1..$] = uintEncode!(T, 8u)(v);
			nBytes = 9;
        }
    }

	return result;
}


// Any below codes are private
private:

unittest // uintEncode & uintDecode
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.myconvert.uintEncode & uintDecode");

    // 16 bits
    auto b16 = uintEncode!(ushort, 2u)(ushort.min);
    auto u16 = uintDecode!(ushort)(b16[]);
    assert(u16 == ushort.min);

    b16 = uintEncode!(ushort, 2u)(ushort.max);
    u16 = uintDecode!(ushort)(b16[]);
    assert(u16 == ushort.max);

    b16 = uintEncode!(ushort, 2u)(0u);
    u16 = uintDecode!(ushort)(b16[]);
    assert(u16 == 0u);

    b16 = uintEncode!(ushort, 2u)(ushort.max / 3);
    u16 = uintDecode!(ushort)(b16[]);
    assert(u16 == ushort.max / 3);

	// 24 bits
    auto b24 = uintEncode!(uint, 3u)(0xFFFFFF);
    auto u24 = uintDecode!(uint)(b24[0..3]);
    assert(u24 == 0xFFFFFF);

    b24 = uintEncode!(uint, 3u)(0u);
    u24 = uintDecode!(uint)(b24[0..3]);
    assert(u24 == 0u);

    b24 = uintEncode!(uint, 3u)(ushort.max / 3);
    u24 = uintDecode!(uint)(b24[0..3]);
    assert(u24 == ushort.max / 3);

    // 32 bits
    auto b32 = uintEncode!(uint, 4u)(uint.min);
    auto u32 = uintDecode!(uint)(b32[]);
    assert(u32 == uint.min);

    b32 = uintEncode!(uint, 4u)(uint.max);
    u32 = uintDecode!(uint)(b32[]);
    assert(u32 == uint.max);

    b32 = uintEncode!(uint, 4u)(0u);
    u32 = uintDecode!(uint)(b32[]);
    assert(u32 == 0u);

    b32 = uintEncode!(uint, 4u)(uint.max / 3);
    u32 = uintDecode!(uint)(b32[]);
    assert(u32 == uint.max / 3);

    // 64 bits
    auto b64 = uintEncode!(ulong, 8u)(ulong.min);
    auto u64 = uintDecode!(ulong)(b64[]);
    assert(u64 == ulong.min);

    b64 = uintEncode!(ulong, 8u)(ulong.max);
    u64 = uintDecode!(ulong)(b64[]);
    assert(u64 == ulong.max);

    b64 = uintEncode!(ulong, 8u)(0u);
    u64 = uintDecode!(ulong)(b64[]);
    assert(u64 == 0u);

    b64 = uintEncode!(ulong, 8u)(ulong.max / 3);
    u64 = uintDecode!(ulong)(b64[]);
    assert(u64 == ulong.max / 3);
}

unittest // dateDecode & dateEncode
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.myconvert.dateDecode & dateEncode");

	ubyte[maxDateBufferSize] buffer = void;
	int bufferSize = void;
	Date date = void;

	bufferSize = dateEncode(buffer, Date(2020, 5, 20));
	assert(bufferSize == 5);
	assert(buffer[0] == 4);
	date = dateDecode(buffer[1..bufferSize]);
	assert(date.year == 2020);
	assert(date.month == 5);
	assert(date.day == 20);

	bufferSize = dateEncode(buffer, Date(0));
	assert(bufferSize == 1);
	assert(buffer[0] == 0);
}

unittest // dateTimeDecode & dateTimeEncode
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.myconvert.dateTimeDecode & dateTimeEncode");

	ubyte[maxDateTimeBufferSize] buffer = void;
	int bufferSize = void;
	DbDateTime dateTime = void;

	bufferSize = dateTimeEncode(buffer, DbDateTime(DateTime(2020, 5, 20, 1, 1, 1, 1)));
	assert(bufferSize == 12);
	assert(buffer[0] == 11);
	dateTime = dateTimeDecode(buffer[1..bufferSize]);
	assert(dateTime.year == 2020);
	assert(dateTime.month == 5);
	assert(dateTime.day == 20);
	assert(dateTime.hour == 1);
	assert(dateTime.minute == 1);
	assert(dateTime.second == 1);
	assert(dateTime.millisecond == 1);

	bufferSize = dateTimeEncode(buffer, DbDateTime(DateTime(0L)));
	assert(bufferSize == 1);
	assert(buffer[0] == 0);

	bufferSize = dateTimeEncode(buffer, DbDateTime(DateTime(2020, 5, 20, 1, 1, 1)));
	assert(bufferSize == 8);
	assert(buffer[0] == 7);
	dateTime = dateTimeDecode(buffer[1..bufferSize]);
	assert(dateTime.year == 2020);
	assert(dateTime.month == 5);
	assert(dateTime.day == 20);
	assert(dateTime.hour == 1);
	assert(dateTime.minute == 1);
	assert(dateTime.second == 1);
	assert(dateTime.millisecond == 0);

	bufferSize = dateTimeEncode(buffer, DbDateTime(DateTime(2020, 5, 20)));
	assert(bufferSize == 5);
	assert(buffer[0] == 4);
	dateTime = dateTimeDecode(buffer[1..bufferSize]);
	assert(dateTime.year == 2020);
	assert(dateTime.month == 5);
	assert(dateTime.day == 20);
	assert(dateTime.hour == 0);
	assert(dateTime.minute == 0);
	assert(dateTime.second == 0);
	assert(dateTime.millisecond == 0);
}

unittest // timeSpanDecode & timeSpanEncode
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.myconvert.timeSpanDecode & timeSpanEncode");

	Time time;
	DbTimeSpan timeSpan;
	ubyte[maxTimeSpanBufferSize] buffer;
	int bufferLen;

	time = Time(1, 1, 1);
	bufferLen = timeSpanEncode(buffer, DbTimeSpan(time));
	assert(bufferLen == 9);
	assert(buffer[0] == 8);
	timeSpan = timeSpanDecode(buffer[1..bufferLen]);
	assert(timeSpan.time == time);

	time = Time(11, 11, 11, 101);
	bufferLen = timeSpanEncode(buffer, DbTimeSpan(time));
	assert(bufferLen == 13);
	assert(buffer[0] == 12);
	timeSpan = timeSpanDecode(buffer[1..bufferLen]);
	assert(timeSpan.time == time);

	time = Time(0L);
	bufferLen = timeSpanEncode(buffer, DbTimeSpan(time));
	assert(bufferLen == 1);
	assert(buffer[0] == 0);
}
