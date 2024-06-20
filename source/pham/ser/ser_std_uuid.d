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

module pham.ser.ser_std_uuid;

import std.uuid : parseUUID, UUID;
import pham.ser.ser_serialization : asciiCaseInplace, DataKind,
    Deserializer, DSeserializer, Serializable, Serializer,
    SerializerDataFormat;

@safe:

void deserialize(Deserializer deserializer, scope ref UUID value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto text = deserializer.readScopeChars(DataKind.uuid);
            value = parseUUID(text);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readScopeBytes(attribute.binaryFormat, DataKind.uuid);
            value = UUID(binary[0..16]);
            return;
    }
}

void serialize(Serializer serializer, scope ref UUID value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            char[36] text = void;
            value.toString(text[]);
            serializer.write(asciiCaseInplace(text[], attribute.binaryFormat.characterCaseFormat)[], DataKind.uuid);
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.data[], attribute.binaryFormat, DataKind.uuid);
            return;
    }
}

version(unittest)
{
package(pham.ser):

    static struct UnitTestStdUuid
    {
        UUID uuid1;

        ref typeof(this) setValues() return
        {
            uuid1 = UUID("8AB3060E-2CBA-4F23-B74C-B52DB3DBFB46"); // [138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189, 251, 70]
            return this;
        }
        
        void assertValues()
        {
            assert(uuid1 == UUID("8AB3060E-2CBA-4F23-B74C-B52DB3DBFB46")); // [138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189, 251, 70]
        }
    }
    
    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestStdUuid);
}


private:

shared static this() nothrow @safe
{
    DSeserializer.register!UUID(&serializeUUID, &deserializeUUID);
}

void deserializeUUID(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(UUID*)value), attribute);
}

void serializeUUID(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(UUID*)value), attribute);
}
