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
import std.datetime.systime : SysTime;
import std.datetime.timezone : UTC;
import std.traits : fullyQualifiedName;
import std.uuid : UUID;
import pham.utl.utl_serialization : asciiCaseInplace, Serializable, Serializer,
    SerializerDataType, StaticBuffer;

@safe:

void serialize(Serializer serializer, scope ref BigInt value, scope ref Serializable attribute)
{
    import std.format.spec : FormatSpec;
    
    // There is no binary output from BigInt
    FormatSpec!char fmt;
    fmt.spec = 'd';
    StaticBuffer!(char, 80) buffer;
    value.toString(buffer, fmt);
    serializer.put(buffer[]);
}

void serialize(Serializer serializer, scope ref SysTime value, scope ref Serializable attribute)
{
    final switch (serializer.dataType)
    {
        case SerializerDataType.text:
            StaticBuffer!(char, 36) buffer;
            value.toUTC().toISOExtString(buffer, 7);
            serializer.put(buffer[]);
            return;
        case SerializerDataType.binary:
            serializer.put(value.toUTC().stdTime);
            return;
    }
}

void serialize(Serializer serializer, scope ref UUID value, scope ref Serializable attribute)
{
    final switch (serializer.dataType)
    {
        case SerializerDataType.text:
            char[36] buffer = void;
            value.toString(buffer[]);
            serializer.put(asciiCaseInplace(buffer[], attribute.binaryFormat.characterCaseFormat)[]);
            return;
        case SerializerDataType.binary:
            serializer.put(value.data[], attribute.binaryFormat);
            return;
    }
}
    
version (unittest)
{
package(pham.utl):

    static struct UnitTestStd
    {
        BigInt bigInt1;
        SysTime sysTime1;
        UUID uuid1;
                
        ref UnitTestStd setValues() return
        {
            bigInt1 = BigInt("-71459266416693160362545788781600");
            sysTime1 = SysTime(330_000_502L, UTC()); // 1/1/1T0:0:33.502
            uuid1 = UUID("8AB3060E-2CBA-4F23-B74C-B52DB3DBFB46"); // [138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189, 251, 70]
            return this;
        }        
    }
}


private:

shared static this()
{
    Serializer.registerSerialize(fullyQualifiedName!BigInt, &serializeBigInt);
    Serializer.registerSerialize(fullyQualifiedName!SysTime, &serializeSysTime);
    Serializer.registerSerialize(fullyQualifiedName!UUID, &serializeUUID);
}

void serializeBigInt(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(BigInt*)value), attribute);
}

void serializeSysTime(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(SysTime*)value), attribute);
}

void serializeUUID(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(UUID*)value), attribute);
}
    