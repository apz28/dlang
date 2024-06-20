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

module pham.ser.ser_dec_decimal;

import pham.external.dec.dec_decimal : Decimal32, Decimal64, Decimal128, isDecimal;
import pham.ser.ser_serialization : DataKind,
    Deserializer, DSeserializer, Serializable, Serializer,
    SerializerDataFormat, StaticBuffer;

@safe:

void deserialize(Deserializer deserializer, scope ref Decimal32 value, scope ref Serializable attribute)
{
    deserializeImpl!Decimal32(deserializer, value, attribute);
}

void serialize(Serializer serializer, scope ref Decimal32 value, scope ref Serializable attribute)
{
    serializeImpl!Decimal32(serializer, value, attribute);
}

void deserialize(Deserializer deserializer, scope ref Decimal64 value, scope ref Serializable attribute)
{
    deserializeImpl!Decimal64(deserializer, value, attribute);
}

void serialize(Serializer serializer, scope ref Decimal64 value, scope ref Serializable attribute)
{
    serializeImpl!Decimal64(serializer, value, attribute);
}

void deserialize(Deserializer deserializer, scope ref Decimal128 value, scope ref Serializable attribute)
{
    deserializeImpl!Decimal128(deserializer, value, attribute);
}

void serialize(Serializer serializer, scope ref Decimal128 value, scope ref Serializable attribute)
{
    serializeImpl!Decimal128(serializer, value, attribute);
}


version(unittest)
{
package(pham.ser):

    static struct UnitTestDecDecimal
    {
        Decimal32 decimalNaN;
        Decimal32 decimalInfinity;
        Decimal32 decimal32;
        Decimal64 decimal64;
        Decimal128 decimal128;

        ref typeof(this) setValues() return
        {
            decimalNaN = Decimal32.nan;
            decimalInfinity = Decimal32.negInfinity;
            decimal32 = Decimal32("-7145");
            decimal64 = Decimal64("714583645.40");
            decimal128 = Decimal128("294574120484.87");
            return this;
        }
        
        void assertValues()
        {
            assert(decimalNaN.isNaN);
            assert(decimalInfinity.isInfinity && decimalInfinity.isNeg);
            assert(decimal32 == Decimal32("-7145"));
            assert(decimal64 == Decimal64("714583645.40"));
            assert(decimal128 == Decimal128("294574120484.87"));
        }
    }
    
    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestDecDecimal);
}


private:

void deserializeImpl(D)(Deserializer deserializer, scope ref D value, scope ref Serializable attribute)
if (isDecimal!D)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto text = deserializer.readScopeChars(DataKind.decimal);
            value = D(text);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readScopeBytes(attribute.binaryFormat, DataKind.decimal);
            value = D.fromBigEndianBytes(binary);
            return;
    }
}

void serializeImpl(D)(Serializer serializer, scope ref D value, scope ref Serializable attribute)
if (isDecimal!D)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            StaticBuffer!(char, 350) textBuffer;
            serializer.write(value.toString!(StaticBuffer!(char, 350), char)(textBuffer)[], DataKind.decimal);
            return;
        case SerializerDataFormat.binary:
            ubyte[D.sizeof] binaryBuffer;
            serializer.write(value.toBigEndianBytes(binaryBuffer[]), attribute.binaryFormat, DataKind.decimal);
            return;
    }
}

shared static this() nothrow @safe
{
    DSeserializer.register!Decimal32(&serializeDecimal32, &deserializeDecimal32);
    DSeserializer.register!Decimal64(&serializeDecimal64, &deserializeDecimal64);
    DSeserializer.register!Decimal128(&serializeDecimal128, &deserializeDecimal128);
}

void deserializeDecimal32(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(Decimal32*)value), attribute);
}

void serializeDecimal32(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(Decimal32*)value), attribute);
}

void deserializeDecimal64(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(Decimal64*)value), attribute);
}

void serializeDecimal64(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(Decimal64*)value), attribute);
}

void deserializeDecimal128(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(Decimal128*)value), attribute);
}

void serializeDecimal128(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(Decimal128*)value), attribute);
}
