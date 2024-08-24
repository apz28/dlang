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

import core.time : Duration;
import std.datetime.date : Date, DateTime, TimeOfDay;
import std.datetime.systime : SysTime;
import std.datetime.timezone : LocalTime, SimpleTimeZone, UTC;

debug(pham_ser_ser_std_date_time) import std.stdio : writeln;
import pham.dtm.dtm_date : PhamDate=Date, PhamDateTime=DateTime;
import pham.dtm.dtm_tick : DateTimeZoneKind, Tick;
import pham.dtm.dtm_time : PhamTime=Time;
import pham.ser.ser_serialization : Deserializer, DSSerializer, Serializable, Serializer;

@safe:

void deserialize(Deserializer deserializer, scope ref Date value, scope ref Serializable attribute)
{
    const phamDate = deserializer.readDate(attribute);
    int year=void, month=void, day=void;
    phamDate.getDate(year, month, day);
    value = Date(year, month, day);
}

void serialize(Serializer serializer, scope ref Date value, scope ref Serializable attribute)
{
    auto phamDate = PhamDate(value.year, value.month, value.day);
    serializer.write(phamDate, attribute);
}

void deserialize(Deserializer deserializer, scope ref DateTime value, scope ref Serializable attribute)
{
    const phamDateTime = deserializer.readDateTime(attribute);
    int year=void, month=void, day=void, hour=void, minute=void, second=void;
    phamDateTime.getDate(year, month, day);
    phamDateTime.getTime(hour, minute, second);
    value = DateTime(year, month, day, hour, minute, second);
}

void serialize(Serializer serializer, scope ref DateTime value, scope ref Serializable attribute)
{
    auto phamDateTime = PhamDateTime(value.year, value.month, value.day, value.hour, value.minute, value.second);
    serializer.write(phamDateTime, attribute);
}

void deserialize(Deserializer deserializer, scope ref SysTime value, scope ref Serializable attribute)
{
    static immutable unspecifiedTZ = new immutable SimpleTimeZone(Duration.zero);
    const phamDateTime = deserializer.readDateTime(attribute);
    int year=void, month=void, day=void, hour=void, minute=void, second=void, fractionIn100ns=void;
    phamDateTime.getDate(year, month, day);
    phamDateTime.getTimePrecise(hour, minute, second, fractionIn100ns);
    auto timeZone = phamDateTime.kind == DateTimeZoneKind.utc
        ? UTC()
        : (phamDateTime.kind == DateTimeZoneKind.local ? LocalTime() : unspecifiedTZ);
    debug(pham_ser_ser_std_date_time) debug writeln(__FUNCTION__, "(year=", year, ", month=", month, ", day=", day,
        ", hour=", hour, ", minute=", minute, ", second=", second, ", fractionIn100ns=", fractionIn100ns, ", kind=", phamDateTime.kind, ")");
    value = SysTime(DateTime(year, month, day, hour, minute, second), Tick.durationFromTicks(fractionIn100ns), timeZone);
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
    serializer.write(phamDateTime, attribute);
}

void deserialize(Deserializer deserializer, scope ref TimeOfDay value, scope ref Serializable attribute)
{
    const phamTime = deserializer.readTime(attribute);
    int hour=void, minute=void, second=void, milliSecond=void;
    phamTime.getTime(hour, minute, second, milliSecond);
    value = TimeOfDay(hour, minute, second);
}

void serialize(Serializer serializer, scope ref TimeOfDay value, scope ref Serializable attribute)
{
    auto phamTime = PhamTime(value.hour, value.minute, value.second);
    serializer.write(phamTime, attribute);
}


version(unittest)
{
package(pham.ser):

    static struct UnitTestStdDateTime
    {
        import core.time : days, seconds;

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

        // Some database does not support 'Z' or 7 digits precision
        void assertValuesArray(ptrdiff_t index)
        {
            assert(date1 == Date(1999, 1, 1)+days(index), date1.toString());
            assert(dateTime1 == DateTime(1999, 7, 6, 12, 30, 33)+days(index), dateTime1.toString());
            assert(sysTime1 == SysTime(330_000_000L)+days(index), sysTime1.toString() ~ " ? " ~ (SysTime(330_000_000L)+days(index)).toString());
            assert(timeOfDay1 == TimeOfDay(12, 30, 33)+seconds(index), timeOfDay1.toString());
        }
    }

    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestStdDateTime);
}


private:

shared static this() nothrow @safe
{
    DSSerializer.register!Date(&serializeDate, &deserializeDate);
    DSSerializer.register!DateTime(&serializeDateTime, &deserializeDateTime);
    DSSerializer.register!SysTime(&serializeSysTime, &deserializeSysTime);
    DSSerializer.register!TimeOfDay(&serializeTimeOfDay, &deserializeTimeOfDay);
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
