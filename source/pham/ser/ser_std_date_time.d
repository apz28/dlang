/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.ser.ser_std_date_time;

import std.datetime.date : Date, DateTime, TimeOfDay;
import std.datetime.systime : SysTime;
import std.datetime.timezone : LocalTime, UTC;

import pham.dtm.dtm_date : PhamDate=Date, PhamDateTime=DateTime;
import pham.dtm.dtm_tick : DateTimeZoneKind, Tick;
import pham.dtm.dtm_time : PhamTime=Time;
import pham.ser.ser_serialization : Deserializer, DSeserializer, Serializable, Serializer;

@safe:

void deserialize(Deserializer deserializer, scope ref Date value, scope ref Serializable attribute)
{
    const phamDate = deserializer.readDate();
    int year=void, month=void, day=void;
    phamDate.getDate(year, month, day);
    value = Date(year, month, day);
}

void serialize(Serializer serializer, scope ref Date value, scope ref Serializable attribute)
{
    auto phamDate = PhamDate(value.year, value.month, value.day);
    serializer.write(phamDate);
}

void deserialize(Deserializer deserializer, scope ref DateTime value, scope ref Serializable attribute)
{
    const phamDateTime = deserializer.readDateTime();
    int year=void, month=void, day=void, hour=void, minute=void, second=void;
    phamDateTime.getDate(year, month, day);
    phamDateTime.getTime(hour, minute, second);
    value = DateTime(year, month, day, hour, minute, second);
}

void serialize(Serializer serializer, scope ref DateTime value, scope ref Serializable attribute)
{
    auto phamDateTime = PhamDateTime(value.year, value.month, value.day, value.hour, value.minute, value.second);
    serializer.write(phamDateTime);
}

void deserialize(Deserializer deserializer, scope ref SysTime value, scope ref Serializable attribute)
{
    const phamDateTime = deserializer.readDateTime();
    int year=void, month=void, day=void, hour=void, minute=void, second=void, fractionIn100ns=void;
    phamDateTime.getDate(year, month, day);
    phamDateTime.getTimePrecise(hour, minute, second, fractionIn100ns);
    value = SysTime(DateTime(year, month, day, hour, minute, second),
        Tick.durationFromTicks(fractionIn100ns),
        phamDateTime.kind == DateTimeZoneKind.utc ? UTC() : null);
}

void serialize(Serializer serializer, scope ref SysTime value, scope ref Serializable attribute)
{
    DateTimeZoneKind kind() nothrow @safe
    {
        return value.timezone is UTC()
            ? DateTimeZoneKind.utc
            : (value.timezone is LocalTime() ? DateTimeZoneKind.local : DateTimeZoneKind.unspecified);
    }

    const dtValue = cast(DateTime)value;
    auto phamDateTime = PhamDateTime(dtValue.year, dtValue.month, dtValue.day, dtValue.hour, dtValue.minute, dtValue.second, kind).addTicksClamp(value.fracSecs);
    serializer.write(phamDateTime);
}

void deserialize(Deserializer deserializer, scope ref TimeOfDay value, scope ref Serializable attribute)
{
    const phamTime = deserializer.readTime();
    int hour=void, minute=void, second=void, milliSecond=void;
    phamTime.getTime(hour, minute, second, milliSecond);
    value = TimeOfDay(hour, minute, second);
}

void serialize(Serializer serializer, scope ref TimeOfDay value, scope ref Serializable attribute)
{
    auto phamTime = PhamTime(value.hour, value.minute, value.second);
    serializer.write(phamTime);
}


version(unittest)
{
package(pham.ser):

    static struct UnitTestStdDateTime
    {
        Date date1;
        DateTime dateTime1;
        SysTime sysTime1;
        TimeOfDay timeOfDay1;

        ref typeof(this) setValues() return
        {
            date1 = Date(1999, 1, 1);
            dateTime1 = DateTime(1999, 7, 6, 12, 30, 33);
            sysTime1 = SysTime(330_000_502L, UTC()); // 0001-01-01T00:00:33.0000502Z
            timeOfDay1 = TimeOfDay(12, 30, 33);
            return this;
        }

        void assertValues()
        {
            assert(date1 == Date(1999, 1, 1), date1.toString());
            assert(dateTime1 == DateTime(1999, 7, 6, 12, 30, 33), dateTime1.toString());
            assert(sysTime1 == SysTime(330_000_502L, UTC()), sysTime1.toString() ~ " ? " ~ SysTime(330_000_502L, UTC()).toString());
            assert(timeOfDay1 == TimeOfDay(12, 30, 33), timeOfDay1.toString());
        }
    }

    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestStdDateTime);
}


private:

shared static this() nothrow @safe
{
    DSeserializer.register!Date(&serializeDate, &deserializeDate);
    DSeserializer.register!DateTime(&serializeDateTime, &deserializeDateTime);
    DSeserializer.register!SysTime(&serializeSysTime, &deserializeSysTime);
    DSeserializer.register!TimeOfDay(&serializeTimeOfDay, &deserializeTimeOfDay);
}

void deserializeDate(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(Date*)value), attribute);
}

void serializeDate(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(Date*)value), attribute);
}

void deserializeDateTime(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(DateTime*)value), attribute);
}

void serializeDateTime(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(DateTime*)value), attribute);
}

void deserializeSysTime(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(SysTime*)value), attribute);
}

void serializeSysTime(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(SysTime*)value), attribute);
}

void deserializeTimeOfDay(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(TimeOfDay*)value), attribute);
}

void serializeTimeOfDay(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(TimeOfDay*)value), attribute);
}
