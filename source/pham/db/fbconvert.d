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
import std.datetime.date : TimeOfDay;
import std.datetime.systime : SysTime;
import std.exception : assumeWontThrow;

version (unittest) import pham.utl.utltest;
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
    dgWriteln("unittest db.fbconvert.dateDecode & dateEncode");

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
    dgWriteln("unittest db.fbconvert.timeDecode & timeEncode");

	enum orgFbTime = 36_610_000;

	auto time = timeDecode(orgFbTime);
	assert(time.hour == 1);
	assert(time.minute == 1);
	assert(time.second == 1);

	auto fbTime = timeEncode(time);
	assert(fbTime == orgFbTime, to!string(fbTime) ~ " ? " ~ to!string(orgFbTime));
}
