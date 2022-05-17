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

module pham.db.fbconvert;

import core.time : Duration, dur;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.system : Endian, endian;
import std.typecons : No;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.external.dec.codec : DecimalCodec32, DecimalCodec64, DecimalCodec128;
import pham.utl.datetime.time_zone : TimeZoneInfo, TimeZoneInfoMap;
import pham.utl.big_integer : toBigEndianFlag, UByteTempArray;
import pham.utl.utf8 : ShortStringBuffer;
import pham.db.type;
import pham.db.fbisc;
import pham.db.fbtimezone : FbTimeZone;

nothrow @safe:

enum epochDate = Date(1858, 11, 17);

bool boolDecode(uint8 fbBool) @nogc pure
{
    return fbBool != 0;
}

uint8 boolEncode(bool value) @nogc pure
{
    return value ? 1 : 0;
}

/**
 * Date-part value as number of days elapsed since “date zero” — November 17, 1858 - Modified JD
 * https://en.wikipedia.org/wiki/Julian_day
 */
DbDate dateDecode(int32 fbDate) @nogc pure
{
    return epochDate.addDaysSafe(fbDate);

	version (none)
    {
	const orgFbDate = fbDate;
	int year, month, day;

	fbDate -= 1_721_119 - 2_400_001;
	const century = (4 * fbDate - 1) / 146_097;

	fbDate = 4 * fbDate - 1 - 146_097 * century;
	day = fbDate / 4;
    fbDate = (4 * day + 3) / 1_461;
	day = 4 * day + 3 - 1_461 * fbDate;
	day = (day + 4) / 4;

	month = (5 * day - 3) / 153;
	day = 5 * day - 3 - 153 * month;
	day = (day + 5) / 5;

	year = 100 * century + fbDate;

	if (month < 10)
		month += 3;
	else
	{
		month -= 9;
		year += 1;
	}

    try
    {
        return Date(year, month, day);
    }
    catch (Exception e)
    {
		auto msg = assumeWontThrow(e.msg) ~ "\nyear=" ~ to!string(year) ~ ", month=" ~ to!string(month) ~ ", day=" ~ to!string(day) ~ ", fbDate=" ~ to!string(orgFbDate);
        assert(0, msg);
    }
	}
}

int32 dateEncode(scope const(DbDate) value) @nogc pure
{
    return value.days - epochDate.days;

	version (none)
	{
    const day = value.day;
    int year = value.year;
    int month = value.month;

    if (month > 2)
		month -= 3;
	else
	{
		month += 9;
		year -= 1;
	}

	const century = year / 100;
	const ya = year - 100 * century;

	return (146_097 * century) / 4 + (1_461 * ya) / 4 + (153 * month + 2) / 5 + day + 1_721_119 - 2_400_001;
	}
}

DbDateTime dateTimeDecode(int32 fbDate, int32 fbTime) @nogc pure
{
	version (profile) debug auto p = PerfFunction.create();
	//import pham.utl.test; dgWriteln("fbDate=", fbDate, ", fbTime=", fbTime);

	auto dt = DateTime(dateDecode(fbDate), Time(timeToDuration(fbTime)));
	return DbDateTime(dt, 0);
}

void dateTimeEncode(scope const(DbDateTime) value, out int32 fbDate, out int32 fbTime) @nogc pure
{
	fbDate = dateEncode(value.date);
	fbTime = durationToTime(value.time.toDuration());
}

enum notUseZoneOffset = int16.max;

DbDateTime dateTimeDecodeTZ(int32 fbDate, int32 fbTime, uint16 fbZoneId, int16 fbZoneOffset)
{
	auto fbtzm = FbTimeZone.timeZone(fbZoneId);
	auto tzm = TimeZoneInfoMap.timeZoneMap(fbtzm.name);
	auto dt = DateTime(dateDecode(fbDate), Time(timeToDuration(fbTime)));
	if (fbZoneOffset != notUseZoneOffset)
    {
		if (fbZoneOffset != 0)
			dt = dt.addMinutesSafe(-cast(int)fbZoneOffset);
		dt = dt.asUTC();
    }
	else if (tzm.isValid())
    {
		dt = tzm.info.convertDateTimeToUTC(dt);
    }
	return DbDateTime(TimeZoneInfo.convertUtcToLocal(dt), 0);
}

void dateTimeEncodeTZ(scope const(DbDateTime) value, out int32 fbDate, out int32 fbTime, out uint16 fbZoneId, out int16 fbZoneOffset)
{
	fbZoneId = FbIsc.gmt_zone;
	fbZoneOffset = 0; // Already in UTC so set it to zero
	if (value.kind == DateTimeZoneKind.utc)
		dateTimeEncode(value, fbDate, fbTime);
	else
    {
		auto utc = value.toUTC();
		dateTimeEncode(utc, fbDate, fbTime);
    }
}

size_t decimalByteLength(D)() pure
if (isDecimal!D)
{
	static if (D.sizeofData == 4)
		return DecimalCodec32.formatByteLength;
	else static if (D.sizeofData == 8)
		return DecimalCodec64.formatByteLength;
	else static if (D.sizeofData == 16)
		return DecimalCodec128.formatByteLength;
	else
		static assert(0);
}

D decimalDecode(D)(scope const(ubyte)[] bytes)
if (isDecimal!D)
{
	ShortStringBuffer!ubyte endianBytes;
	endianBytes.put(bytes);
	if (endian == Endian.littleEndian)
		endianBytes.reverse();

	static if (D.sizeofData == 4)
		return DecimalCodec32.decode(endianBytes[]);
	else static if (D.sizeofData == 8)
		return DecimalCodec64.decode(endianBytes[]);
	else static if (D.sizeofData == 16)
		return DecimalCodec128.decode(endianBytes[]);
	else
		static assert(0);
}

ref ShortStringBuffer!ubyte decimalEncode(D)(return ref ShortStringBuffer!ubyte result, scope const(D) value)
if (isDecimal!D)
{
	result.clear();

	static if (D.sizeofData == 4)
		result.put(DecimalCodec32.encode(value));
	else static if (D.sizeofData == 8)
		result.put(DecimalCodec64.encode(value));
	else static if (D.sizeofData == 16)
		result.put(DecimalCodec128.encode(value));
	else
		static assert(0);

	if (endian == Endian.littleEndian)
		result.reverse();

	return result;
}

enum int128ByteLength = 16;

BigInteger int128Decode(scope const(ubyte)[] bytes)
in
{
	assert(bytes.length == int128ByteLength);
}
do
{
	return BigInteger(bytes, No.unsigned, toBigEndianFlag(endian == Endian.bigEndian));
}

bool int128Encode(ref ubyte[int128ByteLength] bytes, scope const(BigInteger) value)
{
	UByteTempArray b;
	value.toBytes(b);

    // Too big?
	if (b.length > int128ByteLength)
		return false;

	// Pad?
	if (b.length < int128ByteLength)
    {
		const ubyte padValue = value.sign == -1 ? 255u : 0u;
		const oldLength = b.length;
		b.length = int128ByteLength;
		b.fill(padValue, oldLength);
    }

	if (endian == Endian.bigEndian)
		b.reverse();

	bytes[] = b[0..int128ByteLength];
	return true;
}

DbTime timeDecode(int32 fbTime) @nogc pure
{
	return DbTime(timeToDuration(fbTime));
}

int32 timeEncode(scope const(DbTime) value) @nogc pure
{
	return durationToTime(value.toDuration());
}

DbTime timeDecodeTZ(int32 fbTime, uint16 fbZoneId, int16 fbZoneOffset)
{
	auto fbtzm = FbTimeZone.timeZone(fbZoneId);
	auto tzm = TimeZoneInfoMap.timeZoneMap(fbtzm.name);
	auto dt = DateTime(DateTime.utcNow.date, Time(timeToDuration(fbTime)));
	if (fbZoneOffset != notUseZoneOffset)
    {
		if (fbZoneOffset != 0)
			dt = dt.addMinutesSafe(-cast(int)fbZoneOffset);
		dt = dt.asUTC;
    }
	else if (tzm.isValid())
    {
		dt = tzm.info.convertDateTimeToUTC(dt);
    }
	return DbTime(TimeZoneInfo.convertUtcToLocal(dt).time, 0);
}

void timeEncodeTZ(scope const(DbTime) value, out int32 fbTime, out uint16 fbZoneId, out int16 fbZoneOffset)
{
	fbZoneId = FbIsc.gmt_zone;
	fbZoneOffset = 0; // Already in UTC so set it to zero
	if (value.kind == DateTimeZoneKind.utc)
		fbTime = timeEncode(value);
	else
    {
		auto utct = value.toUTC();
		fbTime = timeEncode(utct);
    }
}

// time-part value as the number of deci-milliseconds (10^-4 second) elapsed since midnight
// microsecond is 10^-6 second
pragma(inline, true)
int32 durationToTime(scope const(Duration) time) @nogc pure
{
	return cast(int32)(time.total!"usecs"() / 100);
}

// time-part value as the number of deci-milliseconds (10^-4 second) elapsed since midnight
// microsecond is 10^-6 second
pragma(inline, true)
Duration timeToDuration(int32 fbTime) @nogc pure
{
	// cast(int64) = to avoid overflow
	return dur!"usecs"(cast(int64)fbTime * 100);
}


// Any below codes are private
private:

unittest // dateDecode & dateEncode
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbconvert.dateDecode & dateEncode");

	enum orgFbDate = 58_989;

	auto date = dateDecode(orgFbDate);
	assert(date.year == 2020);
	assert(date.month == 5);
	assert(date.day == 20);

	auto fbDate = dateEncode(date);
	assert(fbDate == orgFbDate);
}

unittest // timeDecode & timeEncode
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbconvert.timeDecode & timeEncode");

	enum orgFbTime = 36_610_000;

	auto time = timeDecode(orgFbTime);
	assert(time.hour == 1);
	assert(time.minute == 1);
	assert(time.second == 1);

	auto fbTime = timeEncode(time);
	assert(fbTime == orgFbTime, to!string(fbTime) ~ " ? " ~ to!string(orgFbTime));
}

unittest // int128Decode & int128Encode
{
	import pham.utl.object : bytesFromHexs;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbconvert.int128Decode & int128Encode");

	static BigInteger safeBigInteger(string value) nothrow pure @safe
    {
		scope (failure) assert(0);
		return BigInteger(value);
    }

	BigInteger v, v2;
	ubyte[int128ByteLength] b;
	bool c;

	v = BigInteger(1234);
	c = int128Encode(b, v);
	assert(c);
	assert(b == bytesFromHexs("D2040000000000000000000000000000"));
	v2 = int128Decode(b);
	assert(v2 == v);

	v = safeBigInteger("1234567890123456789012345678901234");
	c = int128Encode(b, v);
	assert(c);
	assert(b == bytesFromHexs("F2AF967ED05C82DE3297FF6FDE3C0000"));
	v2 = int128Decode(b);
	assert(v2 == v);

	v = BigInteger(-1234);
	c = int128Encode(b, v);
	assert(c);
	assert(b == bytesFromHexs("2EFBFFFFFFFFFFFFFFFFFFFFFFFFFFFF"));
	v2 = int128Decode(b);
	assert(v2 == v);

	v = safeBigInteger("-1234567890123456789012345678901234");
	c = int128Encode(b, v);
	assert(c);
	assert(b == bytesFromHexs("0E5069812FA37D21CD68009021C3FFFF"));
	v2 = int128Decode(b);
	assert(v2 == v);
}
