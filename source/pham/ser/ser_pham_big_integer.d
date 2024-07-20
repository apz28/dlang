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

module pham.ser.ser_pham_big_integer;

import pham.utl.utl_big_integer : BigInteger;
import pham.ser.ser_serialization : DataKind,
    Deserializer, DSeserializer, Serializable, Serializer,
    SerializerDataFormat;

@safe:

void deserialize(Deserializer deserializer, scope ref BigInteger value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto text = deserializer.readScopeChars(attribute, DataKind.integral);
            value = BigInteger(text);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readScopeBytes(attribute, DataKind.integral);
            value = BigInteger(binary);
            return;
    }
}

void serialize(Serializer serializer, scope ref BigInteger value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            serializer.write(value.toString(), attribute, DataKind.integral);
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.toBytes(), attribute, DataKind.integral);
            return;
    }
}


version(unittest)
{
package(pham.ser):

    static struct UnitTestPhamBigInteger
    {
        BigInteger bigInt1;

        ref typeof(this) setValues() return
        {
            bigInt1 = BigInteger("-71459266416693160362545788781600");
            return this;
        }
        
        void assertValues()
        {
            assert(bigInt1 == BigInteger("-71459266416693160362545788781600"));
        }
        
        void assertValuesArray(int i)
        {
            assert(bigInt1 == BigInteger("-71459266416693160362545788781600")+i);
        }
    }
    
    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestPhamBigInteger);
}


private:

shared static this() nothrow @safe
{
    DSeserializer.register!BigInteger(&serializeBigInteger, &deserializeBigInteger);
}

void deserializeBigInteger(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(BigInteger*)value), attribute);
}

void serializeBigInteger(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(BigInteger*)value), attribute);
}
