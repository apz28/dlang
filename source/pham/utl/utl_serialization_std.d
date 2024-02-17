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

module pham.utl.utl_serialization_std;

import std.bigint : BigInt;
import std.datetime.date : Date, DateTime, TimeOfDay;
import std.datetime.systime : SysTime;
import std.datetime.timezone : UTC;
import std.uuid : parseUUID, UUID;
import pham.utl.utl_serialization : asciiCaseInplace, Deserializer, DSeserializer, Serializable, Serializer,
    SerializerDataFormat, StaticBuffer;

@safe:

void deserialize(Deserializer deserializer, scope ref BigInt value, scope ref Serializable attribute)
{
    // There is no binary output from BigInt
    auto text = deserializer.readScopeChars();
    value = BigInt(text);
}

void serialize(Serializer serializer, scope ref BigInt value, scope ref Serializable attribute)
{
    import std.format.spec : FormatSpec;

    // There is no binary output from BigInt
    FormatSpec!char fmt;
    fmt.spec = 'd';
    StaticBuffer!(char, 80) buffer;
    value.toString(buffer, fmt);
    serializer.write(buffer[]);
}


void deserialize(Deserializer deserializer, scope ref Date value, scope ref Serializable attribute)
{
    // Does not have a way to get binary/integer value
    auto text = deserializer.readScopeChars();
    value = Date.fromISOExtString(text);
}

void serialize(Serializer serializer, scope ref Date value, scope ref Serializable attribute)
{
    // Does not have a way to get binary/integer value
    StaticBuffer!(char, 50) buffer;
    value.toISOExtString(buffer);
    serializer.write(buffer[]);
}


void deserialize(Deserializer deserializer, scope ref DateTime value, scope ref Serializable attribute)
{
    // Does not have a way to get binary/integer value
    auto text = deserializer.readScopeChars();
    value = DateTime.fromISOExtString(text);
}

void serialize(Serializer serializer, scope ref DateTime value, scope ref Serializable attribute)
{
    // Does not have a way to get binary/integer value
    StaticBuffer!(char, 50) buffer;
    value.toISOExtString(buffer);
    serializer.write(buffer[]);
}


void deserialize(Deserializer deserializer, scope ref SysTime value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto text = deserializer.readScopeChars();
            value = SysTime.fromISOExtString(text, UTC());
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readLong();
            value = SysTime(binary, UTC());
            return;
    }
}

void serialize(Serializer serializer, scope ref SysTime value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            StaticBuffer!(char, 50) buffer;
            value.toUTC().toISOExtString(buffer, 7);
            serializer.write(buffer[]);
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.toUTC().stdTime);
            return;
    }
}


void deserialize(Deserializer deserializer, scope ref TimeOfDay value, scope ref Serializable attribute)
{
    // Does not have a way to get binary/integer value
    auto text = deserializer.readScopeChars();
    value = TimeOfDay.fromISOExtString(text);
}

void serialize(Serializer serializer, scope ref TimeOfDay value, scope ref Serializable attribute)
{
    // Does not have a way to get binary/integer value
    StaticBuffer!(char, 50) buffer;
    value.toISOExtString(buffer);
    serializer.write(buffer[]);
}


void deserialize(Deserializer deserializer, scope ref UUID value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto text = deserializer.readScopeChars();
            value = parseUUID(text);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readScopeBytes(attribute.binaryFormat);
            value = UUID(binary[0..16]);
            return;
    }
}

void serialize(Serializer serializer, scope ref UUID value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            char[36] buffer = void;
            value.toString(buffer[]);
            serializer.write(asciiCaseInplace(buffer[], attribute.binaryFormat.characterCaseFormat)[]);
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.data[], attribute.binaryFormat);
            return;
    }
}


version(unittest)
{
package(pham.utl):

    static struct UnitTestStd
    {
        BigInt bigInt1;
        Date date1;
        DateTime dateTime1;
        SysTime sysTime1;
        TimeOfDay timeOfDay1;
        UUID uuid1;

        ref typeof(this) setValues() return
        {
            bigInt1 = BigInt("-71459266416693160362545788781600");
            date1 = Date(1999, 1, 1);
            dateTime1 = DateTime(1999, 7, 6, 12, 30, 33);
            sysTime1 = SysTime(330_000_502L, UTC()); // 1-1-1T0:0:33.0000502
            timeOfDay1 = TimeOfDay(12, 30, 33);
            uuid1 = UUID("8AB3060E-2CBA-4F23-B74C-B52DB3DBFB46"); // [138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189, 251, 70]
            return this;
        }
        
        void assertValues()
        {
            assert(bigInt1 == BigInt("-71459266416693160362545788781600"));
            assert(date1 == Date(1999, 1, 1));
            assert(dateTime1 == DateTime(1999, 7, 6, 12, 30, 33));
            assert(sysTime1 == SysTime(330_000_502L, UTC())); // 1-1-1T0:0:33.0000502
            assert(timeOfDay1 == TimeOfDay(12, 30, 33));
            assert(uuid1 == UUID("8AB3060E-2CBA-4F23-B74C-B52DB3DBFB46")); // [138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189, 251, 70]
        }
    }
    
    //import pham.utl.utl_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestStd);
}


private:

shared static this() nothrow @safe
{
    DSeserializer.register!BigInt(&serializeBigInt, &deserializeBigInt);
    DSeserializer.register!Date(&serializeDate, &deserializeDate);
    DSeserializer.register!DateTime(&serializeDateTime, &deserializeDateTime);
    DSeserializer.register!SysTime(&serializeSysTime, &deserializeSysTime);
    DSeserializer.register!TimeOfDay(&serializeTimeOfDay, &deserializeTimeOfDay);
    DSeserializer.register!UUID(&serializeUUID, &deserializeUUID);
}

void deserializeBigInt(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(BigInt*)value), attribute);
}

void serializeBigInt(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(BigInt*)value), attribute);
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


void deserializeUUID(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(UUID*)value), attribute);
}

void serializeUUID(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(UUID*)value), attribute);
}
