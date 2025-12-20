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
    // There is no binary output from BigInt
    const text = toString(value);
    serializer.write(text[], attribute, DataKind.integral);
}

version(unittest)
{
package(pham.ser):

    static struct UnitTestStdBigInt
    {
        BigInt bigInt1;

        ref typeof(this) setValues() return
        {
            bigInt1 = BigInt("-71459266416693160362545788781600");
            return this;
        }
        
        void assertValues()
        {
            const bigInt1Text = toString(bigInt1);
            assert(bigInt1 == BigInt("-71459266416693160362545788781600"), bigInt1Text[]);
        }
        
        void assertValuesArray(ptrdiff_t index)
        {

            import std.conv : text;
            //import std.stdio : writeln; writeln(toString(BigInt("-71459266416693160362545788781600")+index))[]);
            
            const bigInt1Text = toString(bigInt1);
            assert(bigInt1 == BigInt("-71459266416693160362545788781600")+index, text(index, " ", bigInt1Text[]));
        }
    }
    
    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestStdBigInt);
}


private:

StaticBuffer!(char, 300) toString(scope const(BigInt) value)
{
    import std.format.spec : FormatSpec;

    FormatSpec!char fmt;
    fmt.spec = 'd';
    StaticBuffer!(char, 300) result;
    value.toString(result, fmt);
    return result;
}

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
