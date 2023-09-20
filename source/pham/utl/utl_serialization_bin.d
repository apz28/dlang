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
import std.traits : isFloatingPoint, isIntegral;
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
    //int16,
    //int32,
    float4,
    float8,
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
    override Serializer begin() nothrow
    {
        buffer = appender!(ubyte[])();
        buffer.reserve(bufferCapacity);
        return super.begin();
    }
    
    final override Serializer aggregateBegin(string typeName, ptrdiff_t length) nothrow
    {
        buffer.put(BinaryDataType.aggregateBegin);
        encodeInt!ptrdiff_t(length);
        return super.aggregateBegin(typeName, length);
    }

    final override Serializer aggregateEnd(string typeName, ptrdiff_t length) nothrow
    {
        buffer.put(BinaryDataType.aggregateEnd);
        return super.aggregateEnd(typeName, length);
    }
    
    final override Serializer arrayBegin(string elemTypeName, ptrdiff_t length) nothrow
    {
        buffer.put(BinaryDataType.arrayBegin);
        encodeInt!ptrdiff_t(length);
        return super.arrayBegin(elemTypeName, length);
    }

    final override Serializer arrayEnd(string elemTypeName, ptrdiff_t length) nothrow
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
    final void encodeInt(V)(V v)
    if (isIntegral!V)
    {
        const isNegative = v < 0;
        if (isNegative)
            v = cast(V)~v;
            
        // First 6 bits
        ubyte lowerBits = cast(ubyte)(v & 0x3F); 
        v >>= 6;
        if (v)
            lowerBits |= 0x80;
        if (isNegative)
            lowerBits |= 0x40;
        buffer.put(lowerBits);
        
        // The rest with 7 bits
        while (v)
        {
            lowerBits = cast(ubyte)(v & 0x7F);
            v >>= 7;
            if (v)
                lowerBits |= 0x80;
            buffer.put(lowerBits);
        }
    }

    final void encodeFloat(V)(V v) @trusted
    if (isFloatingPoint!V)
    {
        static if (V.sizeof == 4)
        {
            uint vi = *(cast(uint*)&v);
            import std.stdio : writefln; debug writefln("v: %f  %x", v, vi);
            version (LittleEndian)
            {
                const vh = cast(ushort)((vi >> 20) & 0x0FFF);
                vi = (vi << 12) | vh;
                import std.stdio : writefln; debug writefln("v2: %f  %x", v, vi);
            }
            encodeInt!uint(vi);
        }
        else static if (V.sizeof == 8)
        {
            ulong vi = *(cast(ulong*)&v);
            import std.stdio : writefln; debug writefln("v: %f  %x", v, vi);
            version (LittleEndian)
            {
                const vh = cast(ushort)((vi >> 48) & 0xFFFF);
                vi = (vi << 16) | vh;
                import std.stdio : writefln; debug writefln("v2: %f  %x", v, vi);
            }
            encodeInt!ulong(vi);
        }
        else
            static assert(0, "Not support float size: " ~ V.sizeof.stringof);
    }
    
public:
    Appender!(ubyte[]) buffer;
    size_t bufferCapacity = 4_000 * 4;
}
