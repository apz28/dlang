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

module pham.utl.utl_serialization_bin;

import std.array : Appender, appender;
import std.traits : isFloatingPoint, isIntegral, Unsigned;
import pham.utl.utl_serialization;

enum BinaryDataType : ubyte
{
    unknown,
    null_,
    bool_,
    int1,
    int2,
    int4,
    int8,
    int16_Reserved,
    int32_Reserved,
    float4,
    float8,
    float16_Reserved,
    float32_Reserved,
    char_,
    chars,
    charsKey,
    bytes,
    aggregateBegin,
    aggregateEnd,
    arrayBegin,
    arrayEnd,
}

class BinarySerializer : Serializer
{
@safe:

public:
    override Serializer begin()
    {
        buffer = appender!(ubyte[])();
        buffer.reserve(bufferCapacity);
        return super.begin();
    }

    final override Serializer aggregateBegin(string typeName, ptrdiff_t length)
    {
        buffer.put(BinaryDataType.aggregateBegin);
        encodeInt!ptrdiff_t(length);
        put(typeName);
        return super.aggregateBegin(typeName, length);
    }

    final override Serializer aggregateEnd(string typeName, ptrdiff_t length)
    {
        buffer.put(BinaryDataType.aggregateEnd);
        return super.aggregateEnd(typeName, length);
    }

    final override Serializer arrayBegin(string elemTypeName, ptrdiff_t length)
    {
        buffer.put(BinaryDataType.arrayBegin);
        encodeInt!ptrdiff_t(length);
        put(elemTypeName);
        return super.arrayBegin(elemTypeName, length);
    }

    final override Serializer arrayEnd(string elemTypeName, ptrdiff_t length)
    {
        buffer.put(BinaryDataType.arrayEnd);
        return super.arrayEnd(elemTypeName, length);
    }

    final override void put(typeof(null))
    {
        buffer.put(BinaryDataType.null_);
    }

    static immutable ubyte[2] boolValues = [0, 1];
    final override void putBool(bool v)
    {
        buffer.put(BinaryDataType.bool_);
        buffer.put(boolValues[v]);
    }

    final override void putChar(char v)
    {
        buffer.put(BinaryDataType.char_);
        buffer.put(cast(ubyte)v);
    }

    final override void put(byte v)
    {
        buffer.put(BinaryDataType.int1);
        buffer.put(cast(ubyte)v);
    }

    final override void put(short v)
    {
        buffer.put(BinaryDataType.int2);
        encodeInt!short(v);
    }

    final override void put(int v)
    {
        buffer.put(BinaryDataType.int4);
        encodeInt!int(v);
    }

    final override void put(long v)
    {
        buffer.put(BinaryDataType.int8);
        encodeInt!long(v);
    }

    final override void put(float v, const(FloatFormat) floatFormat)
    {
        buffer.put(BinaryDataType.float4);
        encodeFloat!float(v);
    }

    final override void put(double v, const(FloatFormat) floatFormat)
    {
        buffer.put(BinaryDataType.float8);
        encodeFloat!double(v);
    }

    final override void put(scope const(char)[] v) @trusted
    {
        buffer.put(BinaryDataType.chars);
        encodeInt!size_t(v.length);
        if (v.length)
            buffer.put(cast(ubyte[])v);
    }

    final override void put(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        buffer.put(BinaryDataType.bytes);
        encodeInt!size_t(v.length);
        if (v.length)
            buffer.put(v);
    }

    final override Serializer putKey(scope const(char)[] key) @trusted
    {
        buffer.put(BinaryDataType.charsKey);
        encodeInt!size_t(key.length);
        if (key.length)
            buffer.put(cast(ubyte[])key);
        return this;
    }

    final override Serializer putKeyId(scope const(char)[] key)
    {
        return putKey(key);
    }

    @property final override SerializerDataType dataType() const @nogc nothrow pure
    {
        return SerializerDataType.binary;
    }

public:
    private enum firstBits = 6;
    private enum moreBits = 7;
    private enum ubyte firstByteMask = 0x3F;
    private enum ubyte moreBit = 0x80;
    private enum ubyte moreByteMask = 0x7F;
    private enum ubyte negativeBit = 0x40;
    
    final V decodeInt(V)() @trusted
    if (isIntegral!V)
    {
        alias UV = Unsigned!V;
        size_t i = 0;
        int counter = 1, shift = 0;
        ubyte lowerBits = (buffer[])[i++];
        const isNegative = (lowerBits & negativeBit) != 0;
        UV result = lowerBits & firstByteMask;
        while ((lowerBits & moreBit) != 0 && i < (buffer[]).length)
        {
            shift = counter == 1 ? firstBits : (shift + moreBits);
            lowerBits = (buffer[])[i++];
            result |= (cast(UV)(lowerBits & moreByteMask)) << shift;
            counter++;
        }
        result = isNegative ? cast(UV)~result : result;
        return *(cast(V*)&result);
    }

    final V decodeFloat(V)() @trusted
    if (isFloatingPoint!V)
    {
        static if (V.sizeof == 4)
        {
            auto vi = decodeInt!uint();
            return *(cast(V*)&vi);
        }
        else static if (V.sizeof == 8)
        {
            auto vi = decodeInt!ulong();
            return *(cast(V*)&vi);
        }
        else
            static assert(0, "Not support float size: " ~ V.sizeof.stringof);
    }

    final void encodeInt(V)(V v) @trusted
    if (isIntegral!V)
    {
        alias UV = Unsigned!V;
        const isNegative = v < 0;
        auto ev = *(cast(UV*)&v);
        if (isNegative)
            ev = cast(UV)~ev;

        // First 6 bits
        ubyte lowerBits = cast(ubyte)(ev & firstByteMask);
        ev >>= firstBits;
        if (ev)
            lowerBits |= moreBit;
        if (isNegative)
            lowerBits |= negativeBit;
        buffer.put(lowerBits);

        // The rest with 7 bits
        while (ev)
        {
            lowerBits = cast(ubyte)(ev & moreByteMask);
            ev >>= moreBits;
            if (ev)
                lowerBits |= moreBit;
            buffer.put(lowerBits);
        }
    }

    final void encodeFloat(V)(V v) @trusted
    if (isFloatingPoint!V)
    {
        static if (V.sizeof == 4)
        {
            encodeInt!uint(*(cast(uint*)&v));
        }
        else static if (V.sizeof == 8)
        {
            encodeInt!ulong(*(cast(ulong*)&v));
        }
        else
            static assert(0, "Not support float size: " ~ V.sizeof.stringof);
    }

public:
    Appender!(ubyte[]) buffer;
    size_t bufferCapacity = 4_000 * 4;
}

unittest // BinarySerializer.encodeInt & decodeInt
{
    import std.digest : toHexString;
    import std.stdio : writefln; 
    
    scope serializer = new BinarySerializer();
    
    serializer.begin();
    serializer.encodeInt!short(22_826);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    const i2 = serializer.decodeInt!short(); //debug writefln("%x", i2);
    assert(i2 == 22_826);
    
    serializer.begin();
    serializer.encodeInt!uint(0x0FFF1A);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    const i4 = serializer.decodeInt!uint(); //debug writefln("%x", i4);
    assert(i4 == 0x0FFF1A);
    
    serializer.begin();
    serializer.encodeInt!long(-83_659_374_736_539L);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));    
    const i8 = serializer.decodeInt!long(); //debug writefln("%s", i8);
    assert(i8 == -83_659_374_736_539L);
}

unittest // BinarySerializer.encodeFloat & decodeFloat
{
    import std.digest : toHexString;
    import std.stdio : writefln; 
    
    scope serializer = new BinarySerializer();

    serializer.begin();
    serializer.encodeFloat!float(1_826.22f);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    auto f4 = serializer.decodeFloat!float(); //debug writefln("%x", i2);
    assert(f4 == 1_826.22f);

    serializer.begin();
    serializer.encodeFloat!float(-1_826.22f);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    f4 = serializer.decodeFloat!float(); //debug writefln("%x", i2);
    assert(f4 == -1_826.22f);

    serializer.begin();
    serializer.encodeFloat!double(9_877_631_826.22);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    auto f8 = serializer.decodeFloat!double(); //debug writefln("%x", i2);
    assert(f8 == 9_877_631_826.22);

    serializer.begin();
    serializer.encodeFloat!double(-9_877_631_826.22);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    f8 = serializer.decodeFloat!double(); //debug writefln("%x", i2);
    assert(f8 == -9_877_631_826.22);

    serializer.begin();
    serializer.encodeFloat!double(-1.1);
    serializer.end(); //debug writefln("%s", toHexString(serializer.buffer[]));
    f8 = serializer.decodeFloat!double(); //debug writefln("%x", i2);
    assert(f8 == -1.1);
}
