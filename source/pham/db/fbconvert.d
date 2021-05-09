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
import std.algorithm.mutation : reverse;
import std.conv : to;
import std.datetime.date : TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : assumeWontThrow;
import std.system : Endian, endian;
import std.typecons : No;

import pham.external.decimal.codec;

version (unittest) import pham.utl.utltest;
import pham.utl.biginteger : toBigEndianFlag;
import pham.db.type;
import pham.db.convert;
import pham.db.fbisc;

nothrow @safe:

immutable epochDate = Date(1858, 11, 17);
enum epochDateDayOfGregorianCal = epochDate.dayOfGregorianCal;

bool boolDecode(uint8 data) pure
{
    return data != 0;
}

uint8 boolEncode(bool value) pure
{
    return value ? 1 : 0;
}

/**
 * Date-part value as number of days elapsed since “date zero” — November 17, 1858 - Modified JD
 * https://en.wikipedia.org/wiki/Julian_day
 */
Date dateDecode(int32 fbDate)
{
    return epochDate + dur!"days"(fbDate);

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

int32 dateEncode(in Date value) pure
{
    return cast(int32)(value.dayOfGregorianCal - epochDateDayOfGregorianCal);

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

DbDateTime dateTimeDecode(int32 fbDate, int32 fbTime)
{
	auto convert = SysTime(dateDecode(fbDate), LocalTime()) + timeToDuration(fbTime);
	return DbDateTime(convert, 0, DbDateTimeKind.local);
}

void dateTimeEncode(in DbDateTime value, out int32 fbDate, out int32 fbTime)
{
	fbDate = dateEncode(value.getDate());
	fbTime = durationToTime(value.getTimeOfDayDuration());
}

DbDateTime dateTimeDecodeTZ(int32 fbDate, int32 fbTime, uint16 fbZoneId, int16 fbZoneOffset)
{
	//todo fbZoneOffset if not zero
	auto convert = SysTime(dateDecode(fbDate), UTC()) + timeToDuration(fbTime);
	return DbDateTime(convert, fbZoneId, DbDateTimeKind.utc);
}

void dateTimeEncodeTZ(in DbDateTime value, out int32 fbDate, out int32 fbTime, out uint16 fbZoneId, out int16 fbZoneOffset)
{
	dateTimeEncode(value.toUTC(), fbDate, fbTime);
	fbZoneId = FbIsc.GMT_ZONE;
	fbZoneOffset = 0; // Already in UTC so set it to zero
}

size_t decimalByteLength(D)() pure
if (isDecimal!D)
{
	static if (D.bitLength == 32)
		return DecimalCodec32.formatByteLength;
	else static if (D.bitLength == 64)
		return DecimalCodec64.formatByteLength;
	else static if (D.bitLength == 128)
		return DecimalCodec128.formatByteLength;
	else
		static assert(0);
}

D decimalDecode(D)(scope ubyte[] bytes)
if (isDecimal!D)
{
	static ubyte[] endianValue(scope ubyte[] value) nothrow pure @safe
    {
		return endian == Endian.bigEndian ? value : reverse(value);
    }

	static if (D.bitLength == 32)
		return DecimalCodec32.decode(endianValue(bytes));
	else static if (D.bitLength == 64)
		return DecimalCodec64.decode(endianValue(bytes));
	else static if (D.bitLength == 128)
		return DecimalCodec128.decode(endianValue(bytes));
	else
		static assert(0);
}

ubyte[] decimalEncode(D)(in D value)
if (isDecimal!D)
{
	static ubyte[] endianResult(ubyte[] bytes) nothrow pure @safe
    {
		return endian == Endian.bigEndian ? bytes : reverse(bytes);
    }

	static if (D.bitLength == 32)
		return endianResult(DecimalCodec32.encode(value).dup);
	else static if (D.bitLength == 64)
		return endianResult(DecimalCodec64.encode(value).dup);
	else static if (D.bitLength == 128)
		return endianResult(DecimalCodec128.encode(value).dup);
	else
		static assert(0);
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

bool int128Encode(in BigInteger value, ref ubyte[int128ByteLength] bytes)
{
	auto b = value.toBytes();

    // Too big?
	if (b.length > int128ByteLength)
		return false;

	// Pad?
	if (b.length < int128ByteLength)
    {
		const ubyte padValue = value.sign == -1 ? 255u : 0u;
		const oldLength = b.length;
		b.length = int128ByteLength;
		b[oldLength..$] = padValue;
    }

	if (endian == Endian.bigEndian)
		b = b.reverse();

	bytes[] = b[0..int128ByteLength];
	return true;
}

DbTime timeDecode(int32 fbTime)
{
	return DbTime(timeToDuration(fbTime));
}

int32 timeEncode(in DbTime value)
{
	return durationToTime(value.toDuration());
}

DbTime timeDecodeTZ(int32 fbTime, uint16 fbZoneId, int16 fbZoneOffset)
{
	//todo fbZoneOffset if not zero
	auto convert = nullDateTimeTZ + timeToDuration(fbTime);
	return DbTime(convert, fbZoneId, DbDateTimeKind.utc);
}

void timeEncodeTZ(in DbTime value, out int32 fbTime, out uint16 fbZoneId, out int16 fbZoneOffset)
{
    fbTime = durationToTime(value.toUTC().toDuration());
	fbZoneId = FbIsc.GMT_ZONE;
	fbZoneOffset = 0; // Already in UTC so set it to zero
}

// time-part value as the number of deci-milliseconds (10^-4 second) elapsed since midnight
// microsecond is 10^-6 second
pragma(inline, true)
int32 durationToTime(Duration timeOfDay) pure
{
	return cast(int32)(timeOfDay.total!"usecs" / 100);
}

// time-part value as the number of deci-milliseconds (10^-4 second) elapsed since midnight
// microsecond is 10^-6 second
pragma(inline, true)
Duration timeToDuration(int32 fbTime) pure
{
	// cast(int64) = to avoid overflow
	return dur!"usecs"(cast(int64)fbTime * 100);
}


// Any below codes are private
private:


unittest // dateDecode & dateEncode
{
    import pham.utl.utltest;
    traceUnitTest("unittest db.fbconvert.dateDecode & dateEncode");

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
    import pham.utl.utltest;
    traceUnitTest("unittest db.fbconvert.timeDecode & timeEncode");

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
	import pham.utl.utlobject : bytesFromHexs;
    import pham.utl.utltest;
    traceUnitTest("unittest db.fbconvert.int128Decode & int128Encode");

	static BigInteger safeBigInteger(string value) nothrow pure @safe
    {
		scope (failure) assert(0);
		return BigInteger(value);
    }

	BigInteger v, v2;
	ubyte[int128ByteLength] b;
	bool c;

	v = BigInteger(1234);
	c = int128Encode(v, b);
	assert(c);
	assert(b == bytesFromHexs("D2040000000000000000000000000000"));
	v2 = int128Decode(b);
	assert(v2 == v);

	v = safeBigInteger("1234567890123456789012345678901234");
	c = int128Encode(v, b);
	assert(c);
	assert(b == bytesFromHexs("F2AF967ED05C82DE3297FF6FDE3C0000"));
	v2 = int128Decode(b);
	assert(v2 == v);

	v = BigInteger(-1234);
	c = int128Encode(v, b);
	assert(c);
	assert(b == bytesFromHexs("2EFBFFFFFFFFFFFFFFFFFFFFFFFFFFFF"));
	v2 = int128Decode(b);
	assert(v2 == v);

	v = safeBigInteger("-1234567890123456789012345678901234");
	c = int128Encode(v, b);
	assert(c);
	assert(b == bytesFromHexs("0E5069812FA37D21CD68009021C3FFFF"));
	v2 = int128Decode(b);
	assert(v2 == v);
}
