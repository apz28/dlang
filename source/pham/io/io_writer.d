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

module pham.io.writer;

import std.bitmanip : nativeToBigEndian, nativeToLittleEndian;
import std.system : Endian;

import pham.utl.bit : Map32Bit, Map64Bit;
import pham.io.error;
import pham.io.stream;
import pham.io.type;

@safe:

struct StreamWriter(Endian EndianKind = Endian.littleEndian, KindType = ubyte)
{
@safe:

public:
    this(Stream stream) nothrow pure
    {
        this._stream = stream;
    }

    pragma(inline, true)
    void write(bool v)
    {
        write(v ? cast(ubyte)1 : cast(ubyte)0);
    }

    pragma(inline, true)
    void write(char v)
    {
        write(cast(ubyte)v);
    }

    pragma(inline, true)
    void write(ubyte v)
    {
        static if (KindType.sizeof == ubyte.sizeof)
        {
            writeBuffer(v);
        }
        else static if (KindType.sizeof == ushort.sizeof)
        {
            writeEndianInteger!ushort(v);
        }
        else
            writeEndianInteger!uint(v);
    }

    pragma(inline, true)
    void write(byte v)
    {
        write(cast(ubyte)v);
    }

    pragma(inline, true)
    void write(ushort v)
    {
        static if (KindType.sizeof <= ushort.sizeof)
            writeEndianInteger!ushort(v);
        else
            writeEndianInteger!uint(v);
    }

    pragma(inline, true)
    void write(short v)
    {
        write(cast(ushort)v);
    }

    pragma(inline, true)
    void write(uint v)
    {
        writeEndianInteger!uint(v);
    }

    pragma(inline, true)
    void write(int v)
    {
        write(cast(uint)v);
    }

    pragma(inline, true)
    void write(ulong v)
    {
        writeEndianInteger!ulong(v);
    }

    pragma(inline, true)
    void write(long v)
    {
        write(cast(ulong)v);
    }

    pragma(inline, true)
    void write(float v)
    {
        Map32Bit v2 = { f:v };
        write(v2.u);
    }

    pragma(inline, true)
    void write(double v)
    {
        Map64Bit v2 = { f:v };
        write(v2.u);
    }

    pragma(inline, true)
    void write(scope const(char)[] v)
    {
        if (v.length)
            writeBuffer(&v[0], v.length);
    }

    pragma(inline, true)
    void write(scope const(ubyte)[] v)
    {
        if (v.length)
            writeBuffer(&v[0], v.length);
    }

    pragma(inline, true)
    void writei(bool v, KindType i = ValueKind.boolean)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(char v, KindType i = ValueKind.character)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(ubyte v, KindType i = ValueKind.uint8)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(byte v, KindType i = ValueKind.int8)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(ushort v, KindType i = ValueKind.uint16)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(short v, KindType i = ValueKind.int16)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(uint v, KindType i = ValueKind.uint32)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(int v, KindType i = ValueKind.int32)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(ulong v, KindType i = ValueKind.uint64)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(long v, KindType i = ValueKind.int64)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(float v, KindType i = ValueKind.float32)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(double v, KindType i = ValueKind.float64)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(scope const(char)[] v, KindType i = ValueKind.characters)
    {
        writeKind(i);
        write(v);
    }

    pragma(inline, true)
    void writei(scope const(ubyte)[] v, KindType i = ValueKind.binarys)
    {
        writeKind(i);
        write(v);
    }

    void writeEncodedInt(uint v)
    {
        // Write out an int 7 bits at a time. The high bit of the byte,
        // when on, tells reader to continue reading more bytes.
        ubyte[5] bytes;
        ubyte count = 0;
        while (v > 0x7Fu)
        {
            bytes[count++] = cast(ubyte)(v | ~0x7Fu);
            v >>= 7;
        }
        bytes[count++] = cast(ubyte)v;
        write(bytes[0..count]);
    }

    void writeEncodedLong(ulong v)
    {
        // Write out an int 7 bits at a time. The high bit of the byte,
        // when on, tells reader to continue reading more bytes.
        ubyte[10] bytes;
        ubyte count = 0;
        while (v > 0x7FU)
        {
            bytes[count++] = cast(ubyte)(v | ~0x7FU);
            v >>= 7;
        }
        bytes[count++] = cast(ubyte)v;
        write(bytes[0..count]);
    }

    void writeNullTerminatedChars(scope const(char)[] v)
    {
        if (v.length)
        {
            writeBuffer(&v[0], v.length);
            if (v[$-1] != '\0')
                writeBuffer('\0');
        }
        else
            writeBuffer('\0');
    }

    pragma(inline, true)
    void writeNullTerminatedCharsi(scope const(char)[] v, KindType i = ValueKind.characters)
    {
        writeKind(i);
        writeNullTerminatedChars(v);
    }

    pragma(inline, true)
    void writeWithLength(scope const(char)[] v)
    {
        writeLength(v.length);
        if (v.length)
            writeBuffer(&v[0], v.length);
    }

    pragma(inline, true)
    void writeWithLength(scope const(ubyte)[] v)
    {
        writeLength(v.length);
        if (v.length)
            writeBuffer(&v[0], v.length);
    }

    pragma(inline, true)
    void writeWithLengthi(scope const(char)[] v, KindType i = ValueKind.characters)
    {
        writeKind(i);
        writeWithLength(v);
    }

    pragma(inline, true)
    void writeWithLengthi(scope const(ubyte)[] v, KindType i = ValueKind.binarys)
    {
        writeKind(i);
        writeWithLength(v);
    }

    pragma(inline, true)
    void writeKind(KindType v)
    {
        static if (KindType.sizeof == ubyte.sizeof)
        {
            writeBuffer(cast(ubyte)v);
        }
        else static if (KindType.sizeof == ushort.sizeof)
        {
            writeEndianInteger!ushort(cast(ushort)v);
        }
        else
            writeEndianInteger!uint(cast(uint)v);
    }

    pragma(inline, true)
    void writeLength(size_t v)
    in
    {
        assert(v <= uint.max);
    }
    do
    {
        writeEncodedInt(cast(uint)v);
    }

    @property Stream stream() nothrow pure
    {
        return _stream;
    }

package(pham.io):
    pragma(inline, true)
    void writeBuffer(ubyte v)
    {
        if (_stream.writeUByte(v) != 1)
            _stream.lastError.throwIt!StreamWriteException();
    }

    void writeBuffer(scope const(void)* buffer, size_t size) @trusted
    {
        const(ubyte)* p = cast(const(ubyte)*)buffer;
        while (size)
        {
            const wSize = _stream.write(p[0..size]);
            if (wSize <= 0)
                break;
            p += cast(size_t)wSize;
            size -= cast(size_t)wSize;
        }
        if (size != 0)
            _stream.lastError.throwIt!StreamWriteException();
    }

    pragma(inline, true)
    void writeEndianInteger(T)(T v)
    {
        static if (isSameRTEndian(EndianKind))
            writeBuffer(&v, T.sizeof);
        else static if (EndianKind == Endian.bigEndian)
        {
            const bytes = nativeToBigEndian!T(v);
            writeBuffer(&bytes[0], T.sizeof);
        }
        else
        {
            const bytes = nativeToLittleEndian!T(v);
            writeBuffer(&bytes[0], T.sizeof);
        }
    }

private:
    Stream _stream;
}

unittest // StreamWriter
{
    auto s = new MemoryStream();
    Map32Bit f = { u:0x01020304 };
    Map64Bit d = { u:0x0102030405060708 };

    auto w1 = StreamWriter!(Endian.littleEndian)(s.clear());
    w1.write("hello");
    assert(s.toUBytes() == "hello");

    auto w2 = StreamWriter!(Endian.littleEndian)(s.clear());
    w2.write(cast(ushort)0x1122);
    assert(s.toUBytes() == [0x22, 0x11]);

    auto w3 = StreamWriter!(Endian.bigEndian)(s.clear());
    w3.write(cast(ushort)0x1122);
    assert(s.toUBytes() == [0x11, 0x22]);

    auto w4 = StreamWriter!(Endian.bigEndian)(s.clear());
    w4.write(1==1); // bool
    w4.write(cast(byte)2);
    w4.write(cast(short)0x0203);
    w4.write(cast(int)0x01020304);
    w4.write(cast(long)0x0102030405060708);
    w4.write(f.f);
    w4.write(d.f);
    w4.write("A");
    w4.write(cast(const(ubyte)[])[0x1]);
    w4.writeNullTerminatedChars("B");
    w4.writeWithLength("CD");
    w4.writeWithLength(cast(const(ubyte)[])[0x2, 0x3]);
    //import std.stdio writeln(s.toUBytes());
    assert(s.toUBytes() == cast(const(ubyte)[])[1, 2, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 1, 2, 3, 4, 5, 6, 7, 8, 65, 1, 66, 0, 2, 67, 68, 2, 2, 3]);

    auto w5 = StreamWriter!(Endian.littleEndian)(s.clear());
    w5.write(1==1); // bool
    w5.write(cast(byte)2);
    w5.write(cast(short)0x0203);
    w5.write(cast(int)0x01020304);
    w5.write(cast(long)0x0102030405060708);
    w5.write(f.f);
    w5.write(d.f);
    w5.write("A");
    w5.write(cast(const(ubyte)[])[0x1]);
    w5.writeNullTerminatedChars("B");
    w5.writeWithLength("CD");
    w5.writeWithLength(cast(const(ubyte)[])[0x2, 0x3]);
    //import std.stdio writeln(s.toUBytes());
    assert(s.toUBytes() == cast(const(ubyte)[])[1, 2, 3, 2, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1, 65, 1, 66, 0, 2, 67, 68, 2, 2, 3]);
}
