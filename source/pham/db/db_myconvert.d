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

module pham.db.db_myconvert;

import core.time : dur;
import std.format : FormatSpec, formatValue;
import std.traits: isUnsigned, Unqual;

debug(debug_pham_db_db_myconvert) import std.stdio : writeln;

version(profile) import pham.utl.utl_test : PerfFunction;
import pham.dtm.dtm_date_time_parse;
import pham.dtm.dtm_tick : Tick, TickPart;
import pham.utl.utl_array : ShortStringBuffer;
import pham.utl.utl_bit : numericBitCast;
import pham.utl.utl_object : simpleIntegerFmt;
import pham.db.db_type;
import pham.db.db_myoid;
import pham.db.db_mytype;

nothrow @safe:

void blockHeaderDecode(scope const(MyBlockHeader) blockHeader, out size_t blockSize, out ubyte sequenceByte) @nogc nothrow pure
{
    blockSize = cast(uint32)blockHeader.a[0] | (cast(uint32)blockHeader.a[1] << 8) | (cast(uint32)blockHeader.a[2] << 16);
    sequenceByte = blockHeader.a[3];
}

MyBlockHeader blockHeaderEncode(size_t blockSize, ubyte sequenceByte) @nogc nothrow pure
in
{
    assert(blockSize <= 0x00FFFFFF);
}
do
{
    MyBlockHeader result;
    result.a[0] = cast(ubyte)(blockSize & 0xff);
    result.a[1] = cast(ubyte)((blockSize >> 8) & 0xff);
    result.a[2] = cast(ubyte)((blockSize >> 16) & 0xff);
    result.a[3] = sequenceByte;
    return result;
}

DbDate dateDecode(scope const(ubyte)[] myDateBytes) @nogc pure
in
{
	assert(myDateBytes.length == 4 || myDateBytes.length == 7);
}
do
{
	const year = myDateBytes[0] + (cast(int)myDateBytes[1] << 8);
	const month = cast(int)myDateBytes[2];
	const day = cast(int)myDateBytes[3];
	return DbDate(year, month, day);
}

enum maxDateBufferSize = 8;
uint8 dateEncode(ref ubyte[maxDateBufferSize] myDateBytes, scope const(Date) date) @nogc pure
{
	if (date.days == 0)
    {
		myDateBytes[0] = 0;
		return 1;
    }

    const year = date.year;
	myDateBytes[0] = 7;
	myDateBytes[1] = cast(ubyte)(year & 0xFF);
	myDateBytes[2] = cast(ubyte)((year >> 8) & 0xFF);
	myDateBytes[3] = cast(ubyte)date.month;
	myDateBytes[4] = cast(ubyte)date.day;
	myDateBytes[5] = 0u; // Hour
	myDateBytes[6] = 0u; // Minute
	myDateBytes[7] = 0u; // Second
	return maxDateBufferSize;
}

static immutable DateTimePattern[] datePatterns;
bool dateDecodeString(scope const(char)[] myDateString, ref DbDate dbDate)
{
	debug(debug_pham_db_db_myconvert) debug writeln(__FUNCTION__, "(myDateString=", myDateString, ")");
	assert(datePatterns.length != 0);

	Date dt = void;
	if (tryParse!Date(myDateString, datePatterns, dt) == DateTimeParser.noError)
    {
		dbDate = dt;
		return true;
    }
	else
		return false;
}

enum maxDateStringSize = 23;
uint8 dateEncodeString(ref char[maxDateStringSize] myDateString, scope const(Date) date)
{
	scope (failure) assert(0, "Assume nothrow failed");

	ShortStringBuffer!char buffer;
	myDateString[0..maxDateStringSize] = date.toString(buffer, "timestamp('%cyyyy-mm-dd')")[0..maxDateStringSize];
	return maxDateStringSize;
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

	const int microsecond = numericBitCast!int32(uintDecode!uint32(myDateTimeBytes[7..$]));
	return DbDateTime(DateTime(year, month, day, hour, minute, second).addTicksClamp(TickPart.microsecondToTick(microsecond)), 0);
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
	myDateTimeBytes[5] = cast(ubyte)hour;
	myDateTimeBytes[6] = cast(ubyte)minute;
	myDateTimeBytes[7] = cast(ubyte)second;

	if (tick)
    {
		myDateTimeBytes[8..12] = uintEncode!(uint32, 4)(cast(uint32)TickPart.tickToMicrosecond(tick));

		myDateTimeBytes[0] = 11;
		return maxDateTimeBufferSize;
    }

    myDateTimeBytes[0] = 7;
	return 8;
}

static immutable DateTimePattern[] dateTimePatterns;
bool dateTimeDecodeString(scope const(char)[] myDateTimeString, ref DbDateTime dbDateTime)
{
	debug(debug_pham_db_db_myconvert) debug writeln(__FUNCTION__, "(myDateTimeString=", myDateTimeString, ")");
	assert(dateTimePatterns.length != 0);

	DateTime dt = void;
	if (tryParse!DateTime(myDateTimeString, dateTimePatterns, dt) == DateTimeParser.noError)
    {
		dbDateTime = DbDateTime(dt, 0);
		return true;
    }
	else
		return false;
}

enum maxDateTimeStringSize = 39;
uint8 dateTimeEncodeString(ref char[maxDateTimeStringSize] myDateTimeString, scope const(DbDateTime) dateTime)
{
	scope (failure) assert(0, "Assume nothrow failed");

	ShortStringBuffer!char buffer;
	if (dateTime.value.fraction != 0)
    {
		myDateTimeString[0..maxDateTimeStringSize] = dateTime.value.toString(buffer, "timestamp('%cyyyy-mm-dd hh:nn:ss.zzzzzz')")[0..maxDateTimeStringSize];
		return maxDateStringSize;
    }
	else
    {
		myDateTimeString[0..31] = dateTime.value.toString(buffer, "timestamp('%cyyyy-mm-dd hh:nn:ss')")[0..31];
		return 31;
    }
}

enum maxMyGeometryBufferSize = 50;
MyGeometry geometryDecode(scope const(ubyte)[] myGeometryBytes) @nogc pure
{
	const validLength = myGeometryBytes.length >= maxMyGeometryBufferSize;

	MyGeometry result;
	result.srid = validLength
        ? numericBitCast!int32(uintDecode!uint32(myGeometryBytes[0..4]))
        : 0;
	const xIndex = validLength ? 9 : 5;
	const xEnd = xIndex + 8;
	result.point.x = myGeometryBytes.length >= xEnd
        ? numericBitCast!float64(uintDecode!uint64(myGeometryBytes[xIndex..xEnd]))
        : 0.0;
	const yIndex = validLength ? 17 : 13;
	const yEnd = yIndex + 8;
	result.point.y = myGeometryBytes.length >= yEnd
        ? numericBitCast!float64(uintDecode!uint64(myGeometryBytes[yIndex..yEnd]))
        : 0.0;
	return result;
}

uint8 geometryEncode(ref ubyte[maxMyGeometryBufferSize] myGeometryBytes, scope const(MyGeometry) geometry) @nogc pure
{
	const srid = uintEncode!(uint32, 4)(numericBitCast!uint32(geometry.srid));
	myGeometryBytes[0..4] = srid[0..4];
    myGeometryBytes[4] = 1;
	myGeometryBytes[5] = 1;
	myGeometryBytes[6..9] = 0;
	const x = uintEncode!(uint64, 8)(numericBitCast!uint64(geometry.point.x));
	myGeometryBytes[9..17] = x[0..8];
	const y = uintEncode!(uint64, 8)(numericBitCast!uint64(geometry.point.y));
	myGeometryBytes[17..25] = y[0..8];
	return 25;
}

uint8 geometryEncode(ref char[maxMyGeometryBufferSize] myGeometryChars, scope const(MyGeometry) geometry)
{
	scope (failure) assert(0, "Assume nothrow failed");

	ShortStringBuffer!char buffer;
	if (geometry.srid != 0)
    {
		buffer.put("SRID=");
		auto fmtSpec = simpleIntegerFmt();
		formatValue(buffer, geometry.srid, fmtSpec);
        buffer.put(';');
    }
	buffer.put("POINT(");
	auto fmtSpec = simpleIntegerFmt();
	formatValue(buffer, geometry.point.x, fmtSpec);
	buffer.put(' ');
	fmtSpec = simpleIntegerFmt();
	formatValue(buffer, geometry.point.y, fmtSpec);
	buffer.put(')');

	myGeometryChars[0..buffer.length] = buffer[0..buffer.length];
	return cast(uint8)buffer.length;
}

DbTimeSpan timeSpanDecode(scope const(ubyte)[] myTimeBytes) @nogc pure
in
{
	assert(myTimeBytes.length == 8 || myTimeBytes.length == 12);
}
do
{
	auto result = Duration.zero;
	result += dur!"days"(numericBitCast!int32(uintDecode!uint32(myTimeBytes[1..5])));
	result += dur!"hours"(cast(int)myTimeBytes[5]);
	result += dur!"minutes"(cast(int)myTimeBytes[6]);
	result += dur!"seconds"(cast(int)myTimeBytes[7]);
	if (myTimeBytes.length == 12) // Microsecond?
        result += dur!"usecs"(numericBitCast!int32(uintDecode!uint32(myTimeBytes[8..$])));
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
	bool isNeg;
	timeSpan.getTime(isNeg, day, hour, minute, second, microsecond);

	myTimeSpanBytes[1] = isNeg ? 1 : 0;
	myTimeSpanBytes[2..6] = uintEncode!(uint32, 4)(numericBitCast!uint32(day));
	myTimeSpanBytes[6] = cast(ubyte)hour;
	myTimeSpanBytes[7] = cast(ubyte)minute;
	myTimeSpanBytes[8] = cast(ubyte)second;

	if (microsecond != 0)
    {
		myTimeSpanBytes[9..13] = uintEncode!(uint32, 4)(numericBitCast!uint32(microsecond));
		myTimeSpanBytes[0] = 12;
		return 13;
    }
	else
    {
		myTimeSpanBytes[0] = 8;
		return 9;
    }
}

static immutable DateTimePattern[] timePatterns;
bool timeSpanDecodeString(scope const(char)[] myTimeString, ref DbTimeSpan dbTimeSpan)
{
	debug(debug_pham_db_db_myconvert) debug writeln(__FUNCTION__, "(myTimeString=", myTimeString, ")");
	assert(timePatterns.length != 0);

	Time tm = void;
	if (tryParse!Time(myTimeString, timePatterns, tm) == DateTimeParser.noError)
    {
		dbTimeSpan = DbTimeSpan(tm);
		return true;
    }
	else
		return false;
}

enum maxTimeSpanStringSize = 30;
uint8 timeSpanEncodeString(ref char[maxTimeSpanStringSize] myTimeSpanString, scope const(DbTimeSpan) timeSpan)
{
	scope (failure) assert(0, "Assume nothrow failed");

	int day = void, hour = void, minute = void, second = void, microsecond = void;
	bool isNeg = void;
	timeSpan.getTime(isNeg, day, hour, minute, second, microsecond);

	ShortStringBuffer!char buffer;
	buffer.put('\'');
    if (isNeg)
		buffer.put('-');
	auto fmtSpec = simpleIntegerFmt();
	formatValue(buffer, day, fmtSpec);
	buffer.put(' ');
	fmtSpec = simpleIntegerFmt(2);
	formatValue(buffer, hour, fmtSpec);
	buffer.put(':');
	fmtSpec = simpleIntegerFmt(2);
	formatValue(buffer, minute, fmtSpec);
	buffer.put(':');
	fmtSpec = simpleIntegerFmt(2);
	formatValue(buffer, second, fmtSpec);
	buffer.put('.');
	fmtSpec = simpleIntegerFmt(6);
	formatValue(buffer, microsecond, fmtSpec);
	buffer.put('\'');

	myTimeSpanString[0..buffer.length] = buffer[0..buffer.length];
	return cast(uint8)buffer.length;
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

	debug(debug_pham_db_db_myconvert) debug writeln(__FUNCTION__, "(uintDecode.result=", result, ", bytes=", v.dgToHex(), ")");

    return result;
}

pragma(inline, true)
ubyte[T.sizeof] uintEncode(T, uint8 NBytes)(T v)
if (isUnsigned!T && T.sizeof > 1
    && (NBytes == 2 || NBytes == 3 || NBytes == 4 || NBytes == 8)
    && NBytes <= T.sizeof)
{
    ubyte[T.sizeof] result;
    auto uv = cast(Unqual!T)v;

	result[0] = cast(ubyte)(uv & 0xFF); uv >>= 8;
	result[1] = cast(ubyte)(uv & 0xFF);
	static if (NBytes >= 3)
    {
		uv >>= 8;
		result[2] = cast(ubyte)(uv & 0xFF);
    }
	static if (NBytes >= 4)
    {
		uv >>= 8;
		result[3] = cast(ubyte)(uv & 0xFF);
    }
	static if (NBytes >= 8)
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
    ubyte[T.sizeof + 1] result;

    if (v < MyPackedIntegerLimit.oneByte)
    {
        result[0] = cast(uint8)v;
		nBytes = 1;
    }
    else if (v < MyPackedIntegerLimit.twoByte)
    {
		result[0] = MyPackedIntegerIndicator.twoByte;
		result[1..$] = uintEncode!(T, 2)(v);
        nBytes = 3;
    }
    else if (v < MyPackedIntegerLimit.threeByte)
    {
        result[0] = MyPackedIntegerIndicator.threeByte;
		result[1..$] = uintEncode!(T, 3)(v);
        nBytes = 4;
    }
    else
    {
		static if (T.sizeof <= 4u)
        {
			result[0] = MyPackedIntegerIndicator.fourOrEightByte;
			result[1..$] = uintEncode!(T, 4)(v);
			nBytes = 5;
        }
		else
        {
			result[0] = MyPackedIntegerIndicator.fourOrEightByte;
			result[1..$] = uintEncode!(T, 8)(v);
			nBytes = 9;
        }
    }

	return result;
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
	static DateTimePattern dtPattern(string patternText, char dateSeparator, char timeSeparator) nothrow
    {
		auto result = DateTimePattern.usShortDateTime;
		result.patternText = patternText;
		result.dateSeparator = dateSeparator;
		result.timeSeparator = timeSeparator;
		return result;
    }

	datePatterns = () nothrow @trusted
    {
        return cast(immutable(DateTimePattern)[])[
			dtPattern("yyyy/mm/dd", '-', ':'),  // Most likely pattern to be first
			dtPattern("yyyy/mm/dd", '/', ':')
		];
    }();

	dateTimePatterns = () nothrow @trusted
    {
        return cast(immutable(DateTimePattern)[])[
			dtPattern("yyyy/mm/dd hh:nn:ss.zzzzzz", '-', ':'),  // Most likely pattern to be first
			dtPattern("yyyy/mm/dd hh:nn:ss.zzzzzz", '/', ':')
		];
    }();

	timePatterns = () nothrow @trusted
    {
        return cast(immutable(DateTimePattern)[])[
			dtPattern("hh:nn:ss.zzzzzz", '/', ':'),  // Most likely pattern to be first
			dtPattern("hh:nn:ss.zzzzzz", '/', '-')
		];
    }();
}

unittest // uintEncode & uintDecode
{
    // 16 bits
    auto b16 = uintEncode!(ushort, 2)(ushort.min);
    auto u16 = uintDecode!ushort(b16[]);
    assert(u16 == ushort.min);

    b16 = uintEncode!(ushort, 2)(ushort.max);
    u16 = uintDecode!ushort(b16[]);
    assert(u16 == ushort.max);

    b16 = uintEncode!(ushort, 2)(0u);
    u16 = uintDecode!ushort(b16[]);
    assert(u16 == 0u);

    b16 = uintEncode!(ushort, 2)(ushort.max / 3);
    u16 = uintDecode!ushort(b16[]);
    assert(u16 == ushort.max / 3);

	// 24 bits
    auto b24 = uintEncode!(uint, 3)(0xFFFFFF);
    auto u24 = uintDecode!uint(b24[0..3]);
    assert(u24 == 0xFFFFFF);

    b24 = uintEncode!(uint, 3)(0u);
    u24 = uintDecode!uint(b24[0..3]);
    assert(u24 == 0u);

    b24 = uintEncode!(uint, 3)(ushort.max / 3);
    u24 = uintDecode!uint(b24[0..3]);
    assert(u24 == ushort.max / 3);

    // 32 bits
    auto b32 = uintEncode!(uint, 4)(uint.min);
    auto u32 = uintDecode!uint(b32[]);
    assert(u32 == uint.min);

    b32 = uintEncode!(uint, 4)(uint.max);
    u32 = uintDecode!uint(b32[]);
    assert(u32 == uint.max);

    b32 = uintEncode!(uint, 4)(0u);
    u32 = uintDecode!uint(b32[]);
    assert(u32 == 0u);

    b32 = uintEncode!(uint, 4)(uint.max / 3);
    u32 = uintDecode!uint(b32[]);
    assert(u32 == uint.max / 3);

    // 64 bits
    auto b64 = uintEncode!(ulong, 8)(ulong.min);
    auto u64 = uintDecode!ulong(b64[]);
    assert(u64 == ulong.min);

    b64 = uintEncode!(ulong, 8)(ulong.max);
    u64 = uintDecode!ulong(b64[]);
    assert(u64 == ulong.max);

    b64 = uintEncode!(ulong, 8)(0u);
    u64 = uintDecode!ulong(b64[]);
    assert(u64 == 0u);

    b64 = uintEncode!(ulong, 8)(ulong.max / 3);
    u64 = uintDecode!ulong(b64[]);
    assert(u64 == ulong.max / 3);
}

unittest // dateDecode & dateEncode
{
	ubyte[maxDateBufferSize] buffer = void;
	int bufferSize = void;
	Date date = void;

	bufferSize = dateEncode(buffer, Date(2020, 5, 20));
	assert(bufferSize == 8);
	assert(buffer[0] == 7);
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
	assert(bufferSize == 8);
	assert(buffer[0] == 7);
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
