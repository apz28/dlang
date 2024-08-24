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

module pham.ser.ser_std_bigint;

import std.bigint : BigInt;
import pham.ser.ser_serialization : DataKind,
    Deserializer, DSSerializer, Serializable, Serializer,
    StaticBuffer;

@safe:

void deserialize(Deserializer deserializer, scope ref BigInt value, scope ref Serializable attribute)
{
    // There is no binary output from BigInt
    auto text = deserializer.readScopeChars(attribute, DataKind.integral);
    value = BigInt(text);
}

void serialize(Serializer serializer, scope ref BigInt value, scope ref Serializable attribute)
{
    import std.format.spec : FormatSpec;

    // There is no binary output from BigInt
    FormatSpec!char fmt;
    fmt.spec = 'd';
    StaticBuffer!(char, 200) text;
    value.toString(text, fmt);
    serializer.write(text[], attribute, DataKind.integral);
}


version(unittest)
{
package(pham.ser):

    static struct UnitTestStdBigInt
    {
        import std.format : format;
        
        BigInt bigInt1;

        ref typeof(this) setValues() return
        {
            bigInt1 = BigInt("-71459266416693160362545788781600");
            return this;
        }
        
        void assertValues()
        {
            assert(bigInt1 == BigInt("-71459266416693160362545788781600"), format("%d", bigInt1));
        }
        
        void assertValuesArray(ptrdiff_t index)
        {
            //import std.stdio : writeln; writeln(format("%d", BigInt("-71459266416693160362545788781600")+index));
            
            assert(bigInt1 == BigInt("-71459266416693160362545788781600")+index, format("%d %d", index, bigInt1));
        }
    }
    
    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestStdBigInt);
}


private:

shared static this() nothrow @safe
{
    DSSerializer.register!BigInt(&serializeBigInt, &deserializeBigInt);
}

void deserializeBigInt(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(BigInt*)value), attribute);
}

void serializeBigInt(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(BigInt*)value), attribute);
}
