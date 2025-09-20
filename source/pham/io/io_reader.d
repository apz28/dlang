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

module pham.io.io_reader;

import std.bitmanip : bigEndianToNative, littleEndianToNative;
import std.system : Endian;

import pham.utl.utl_bit : Map32Bit, Map64Bit;
import pham.io.io_error;
import pham.io.io_stream;
import pham.io.io_type;

@safe:

struct StreamReader(Endian endianKind = Endian.littleEndian, KindType = ubyte)
{
@safe:

public:
    this(Stream stream) nothrow pure
    {
        this._stream = stream;
    }

    pragma(inline, true)
    bool readBool()
    {
        return readUByte() != 0;
    }

    pragma(inline, true)
    char readChar()
    {
        return cast(char)readUByte();
    }

    pragma(inline, true)
    ubyte readUByte()
    {
        static if (KindType.sizeof == ubyte.sizeof)
        {
            return readBuffer();
        }
        else static if (KindType.sizeof == ushort.sizeof)
        {
            return cast(ubyte)readEndianInteger!ushort();
        }
        else
            return cast(ubyte)readEndianInteger!uint();
    }

    pragma(inline, true)
    byte readByte()
    {
        return cast(byte)readUByte();
    }

    pragma(inline, true)
    ushort readUShort()
    {
        static if (KindType.sizeof <= ushort.sizeof)
            return readEndianInteger!ushort();
        else
            return cast(ushort)readEndianInteger!uint();
    }

    pragma(inline, true)
    short readShort()
    {
        return cast(short)readUShort();
    }

    pragma(inline, true)
    uint readUInt()
    {
        return readEndianInteger!uint();
    }

    pragma(inline, true)
    int readInt()
    {
        return cast(int)readUInt();
    }

    pragma(inline, true)
    ulong readULong()
    {
        return readEndianInteger!ulong();
    }

    pragma(inline, true)
    long readLong()
    {
        return cast(long)readULong();
    }

    pragma(inline, true)
    float readFloat()
    {
        Map32Bit v2 = { u:readUInt() };
        return v2.f;
    }

    pragma(inline, true)
    double readDouble()
    {
        Map64Bit v2 = { u:readULong() };
        return v2.f;
    }

    char[] readChars(size_t len)
    {
        if (len)
        {
            auto result = new char[](len);
            return readChars(result);
        }
        else
            return null;
    }

    char[] readChars(char[] chars)
    {
        if (const len = chars.length)
        {
            const rLen = readBuffer(&chars[0], len);
            return chars[0..rLen];
        }
        else
            return null;
    }

    ubyte[] readUBytes(size_t len)
    {
        if (len)
        {
            auto result = new ubyte[](len);
            return readUBytes(result);
        }
        else
            return null;
    }

    ubyte[] readUBytes(ubyte[] bytes)
    {
        if (const len = bytes.length)
        {
            const rLen = readBuffer(&bytes[0], len);
            return bytes[0..rLen];
        }
        else
            return null;
    }

    uint readEncodedInt()
    {
        import std.conv : to;

        uint result = 0;
        enum maxBytesWithoutOverflow = 4;
        for (int shift = 0; shift < maxBytesWithoutOverflow * 7; shift += 7)
        {
            const b = readBuffer();
            result |= cast(uint)(b & 0x7Fu) << shift;
            // no more bits?
            if (b <= 0x7Fu)
                return result;
        }

        // Read 4 bits left
        const b = readBuffer();
        if (b > 0x0Fu)
            throw new StreamReadException(0, "Bad readEncodedInt bits: " ~ b.to!string());

        result |= cast(uint)b << (maxBytesWithoutOverflow * 7);
        return result;
    }

    ulong readEncodedLong()
    {
        import std.conv : to;

        ulong result = 0;
        enum maxBytesWithoutOverflow = 9;
        for (int shift = 0; shift < maxBytesWithoutOverflow * 7; shift += 7)
        {
            const b = readBuffer();
            result |= cast(ulong)(b & 0x7Fu) << shift;
            // no more bits?
            if (b <= 0x7Fu)
                return result;
        }

        // Read 1 bit left
        const b = readBuffer();
        if (b > 0x01u)
            throw new StreamReadException(0, "Bad readEncodedLong bits: " ~ b.to!string());

        result |= cast(ulong)b << (maxBytesWithoutOverflow * 7);
        return result;
    }

    char[] readNullTerminatedChars()
    {
        import pham.utl.utl_array_append : Appender;

        auto buffer = Appender!(char[])(1_000);
        while (const c = readBuffer())
            buffer.put(cast(char)c);
        return buffer.data;
    }

    char[] readWithLengthChars()
    {
        const len = readLength();
        if (len)
        {
            auto result = new char[](len);
            readBuffer(&result[0], len, len);
            return result;
        }
        else
            return null;
    }

    ubyte[] readWithLengthUBytes()
    {
        const len = readLength();
        if (len)
        {
            auto result = new ubyte[](len);
            readBuffer(&result[0], len, len);
            return result;
        }
        else
            return null;
    }

    pragma(inline, true)
    KindType readKind()
    {
        static if (KindType.sizeof == ubyte.sizeof)
        {
            return cast(KindType)readBuffer();
        }
        else static if (KindType.sizeof == ushort.sizeof)
        {
            return cast(KindType)readEndianInteger!ushort();
        }
        else
            return cast(KindType)readEndianInteger!uint();
    }

    pragma(inline, true)
    size_t readLength()
    {
        return readEncodedInt();
    }

    pragma(inline, true)
    ValueKind readValueKind()
    {
        return cast(ValueKind)readKind();
    }

    @property Stream stream() nothrow pure
    {
        return _stream;
    }

package(pham.io):
    pragma(inline, true)
    ubyte readBuffer()
    {
        ubyte result = void;
        if (_stream.read(result) != 1)
            _stream.lastError.throwIt!StreamReadException();
        return result;
    }

    size_t readBuffer(scope void* buffer, size_t size, size_t minSize = 0) @trusted
    {
        size_t result;
        ubyte* p = cast(ubyte*)buffer;
        while (size)
        {
            const wRead = _stream.read(p[0..size]);
            if (wRead <= 0)
                break;

            p += wRead;
            size -= wRead;
            result += wRead;
        }
        if (minSize && result < minSize)
            _stream.lastError.throwIt!StreamReadException();
        return result;
    }

    T readEndianInteger(T)() @trusted
    {
        static if (isSameRTEndian(endianKind))
        {
            T result;
            readBuffer(&result, T.sizeof, T.sizeof);
            return result;
        }
        else static if (endianKind == Endian.bigEndian)
        {
            ubyte[T.sizeof] bytes;
            readBuffer(&bytes[0], T.sizeof, T.sizeof);
            return bigEndianToNative!T(bytes);
        }
        else
        {
            ubyte[T.sizeof] bytes;
            readBuffer(&bytes[0], T.sizeof, T.sizeof);
            return littleEndianToNative!T(bytes);
        }
    }

private:
    Stream _stream;
}


unittest // StreamReader
{
    import std.stdio;

    auto s = new ReadonlyStream(null);
    Map32Bit f = { u:0x01020304 };
    Map64Bit d = { u:0x0102030405060708 };

    auto w2 = StreamReader!(Endian.littleEndian)(s.open([0x22, 0x11]));
    assert(w2.readUShort() == 0x1122);

    auto w3 = StreamReader!(Endian.bigEndian)(s.open([0x11, 0x22]));
    assert(w3.readUShort() == 0x1122);

    auto w4 = StreamReader!(Endian.bigEndian)(s.open([1, 2, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 65, 1, 66, 0, 2, 67, 68, 2, 2, 3]));
    assert(w4.readBool() == true);
    assert(w4.readByte() == 2);
    assert(w4.readShort() == 0x0203);
    assert(w4.readInt() == 0x01020304);
    assert(w4.readLong() == 0x0102030405060708);
    assert(w4.readFloat() == f.f);
    assert(w4.readDouble() == d.f);
    assert(w4.readChars(1) == "A");
    assert(w4.readUBytes(1) == [0x1]);
    assert(w4.readNullTerminatedChars() == "B");
    assert(w4.readWithLengthChars() == "CD");
    assert(w4.readWithLengthUBytes() == [0x2, 0x3]);

    auto w5 = StreamReader!(Endian.littleEndian)(s.open([1, 2, 3, 2, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1, 65, 1, 66, 0, 2, 67, 68, 2, 2, 3]));
    assert(w5.readBool() == true); // bool
    assert(w5.readByte() == 2);
    assert(w5.readShort() == 0x0203);
    assert(w5.readInt() == 0x01020304);
    assert(w5.readLong() == 0x0102030405060708);
    assert(w5.readFloat() == f.f);
    assert(w5.readDouble() == d.f);
    assert(w5.readChars(1) == "A");
    assert(w5.readUBytes(1) == [0x1]);
    assert(w5.readNullTerminatedChars() == "B");
    assert(w5.readWithLengthChars() == "CD");
    assert(w5.readWithLengthUBytes() == [0x2, 0x3]);
}
