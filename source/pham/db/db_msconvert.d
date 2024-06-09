/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.db_msconvert;

version(Windows):

import pham.external.std.windows.sqltypes;

debug(debug_pham_db_db_msconvert) import pham.db.db_debug;
import pham.db.db_type;


DbDate fromDate(scope const(DATE_STRUCT) date) @nogc nothrow pure @safe
{
    return DbDate(date.year, date.month, date.day);
}

DATE_STRUCT toDate(scope const(DbDate) date) @nogc nothrow pure @safe
{
    int year, month, day;
    date.getDate(year, month, day);
    return DATE_STRUCT(cast(SQLSMALLINT)year, cast(SQLUSMALLINT)month, cast(SQLUSMALLINT)day);
}

version(none)
DATE_STRUCT toDate(scope const(DbDateTime) datetime) @nogc nothrow pure @safe
{
    int year, month, day;
    datetime.getDate(year, month, day);
    return DATE_STRUCT(cast(SQLSMALLINT)year, cast(SQLUSMALLINT)month, cast(SQLUSMALLINT)day);
}

DbTime fromTime(scope const(TIME_STRUCT) time) @nogc nothrow pure @safe
{
    return DbTime(time.hour, time.minute, time.second);
}

TIME_STRUCT toTime(scope const(DbTime) time) @nogc nothrow pure @safe
{
    int hour, minute, second, millisecond;
    time.getTime(hour, minute, second, millisecond);
    return TIME_STRUCT(cast(SQLUSMALLINT)hour, cast(SQLUSMALLINT)minute, cast(SQLUSMALLINT)second);
}

version(none)
TIME_STRUCT toTime(scope const(DbDateTime) datetime) @nogc nothrow pure @safe
{
    int hour, minute, second, millisecond;
    datetime.getTime(hour, minute, second, millisecond);
    return TIME_STRUCT(cast(SQLUSMALLINT)hour, cast(SQLUSMALLINT)minute, cast(SQLUSMALLINT)second);
}

DbTime fromTime2(scope const(SQL_SS_TIME2_STRUCT) time2) @nogc nothrow pure @safe
{
    const t = Time(time2.hour, time2.minute, time2.second).addTicks(time2.fraction);
    return DbTime(t);
}

SQL_SS_TIME2_STRUCT toTime2(scope const(DbTime) time) @nogc nothrow pure @safe
{
    int hour, minute, second, fraction;
    time.getTimePrecise(hour, minute, second, fraction);
    return SQL_SS_TIME2_STRUCT(cast(SQLUSMALLINT)hour, cast(SQLUSMALLINT)minute, cast(SQLUSMALLINT)second, fraction);
}

DbDateTime fromTimestamp(scope const(TIMESTAMP_STRUCT) timestamp) @nogc nothrow pure @safe
{
    const dt = DateTime(timestamp.year, timestamp.month, timestamp.day,
                timestamp.hour, timestamp.minute, timestamp.second).addTicksClamp(timestamp.fraction);
    return DbDateTime(dt);
}                

TIMESTAMP_STRUCT toTimeStamp(scope const(DbDateTime) datetime) @nogc nothrow pure @safe
{
    int year, month, day, hour, minute, second, fraction;
    datetime.getDate(year, month, day);
    datetime.getTimePrecise(hour, minute, second, fraction);
    return TIMESTAMP_STRUCT(cast(SQLSMALLINT)year, cast(SQLUSMALLINT)month, cast(SQLUSMALLINT)day,
        cast(SQLUSMALLINT)hour, cast(SQLUSMALLINT)minute, cast(SQLUSMALLINT)second, fraction);
}

version(none)
TIMESTAMP_STRUCT toTimeStamp(scope const(DbDate) date) @nogc nothrow pure @safe
{
    int year, month, day;
    date.getDate(year, month, day);
    return TIMESTAMP_STRUCT(cast(SQLSMALLINT)year, cast(SQLUSMALLINT)month, cast(SQLUSMALLINT)day,
        0, 0, 0, 0);
}

DbDateTime fromTimestampOffset(scope const(SQL_SS_TIMESTAMPOFFSET_STRUCT) timestampOffset) @nogc nothrow pure @safe
{
    const dt = DateTime(timestampOffset.year, timestampOffset.month, timestampOffset.day,
                timestampOffset.hour, timestampOffset.minute, timestampOffset.second).addTicksClamp(timestampOffset.fraction);
    const offset = ZoneOffset(timestampOffset.timezone_hour, timestampOffset.timezone_minute);
    return DbDateTime(dt, 0, offset);
}                

SQL_SS_TIMESTAMPOFFSET_STRUCT toTimeStampOffset(scope const(DbDateTime) datetime) @nogc nothrow pure @safe
{
    int year, month, day, hour, minute, second, fraction;
    datetime.getDate(year, month, day);
    datetime.getTimePrecise(hour, minute, second, fraction);
    return SQL_SS_TIMESTAMPOFFSET_STRUCT(cast(SQLSMALLINT)year, cast(SQLUSMALLINT)month, cast(SQLUSMALLINT)day,
        cast(SQLUSMALLINT)hour, cast(SQLUSMALLINT)minute, cast(SQLUSMALLINT)second, fraction, 0, cast(SQLSMALLINT)datetime.zoneOffset.toMinutes());
}
