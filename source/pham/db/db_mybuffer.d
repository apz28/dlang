/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.mybuffer;

import std.string : representation;
import std.system : Endian;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.utf8 : ShortStringBuffer, ShortStringBufferSize;
import pham.db.type;
import pham.db.buffer;
import pham.db.util : asFloatBit, asIntegerBit;
import pham.db.myoid;
import pham.db.myconvert;
import pham.db.mydatabase;

struct MyReader
{
@safe:

public:
    @disable this(this);

    this(MyConnection connection) nothrow
    {
        this._connectionBuffer = true;
        this._connection = connection;
        this._buffer = connection.acquireSocketReadBuffer();
        this._reader = DbValueReader!(Endian.littleEndian)(this._buffer);
    }

    this(MyConnection connection, ubyte[] bufferData) nothrow
    {
        this._connectionBuffer = false;
        this._connection = connection;
        this._buffer = new DbReadBuffer(bufferData);
        this._reader = DbValueReader!(Endian.littleEndian)(this._buffer);
    }

    void dispose(bool disposing = true)
    {
        _reader.dispose(disposing);
        _buffer = null;
        _connection = null;
        _connectionBuffer = false;
    }

    pragma(inline, true)
    uint64 readBit()
    {
        return readUInt64!(8u)();
    }

    pragma(inline, true)
    ubyte[] readBytes()
    {
        const len = readLength();
        return readBytes(cast(int32)len);
    }

    DbDate readDate()
    {
        const nBytes = readUInt8();
        if (nBytes == 0)
            return DbDate.min;
        auto bytes = _buffer.consume(nBytes);
        return dateDecode(bytes);
    }

    DbDateTime readDateTime()
    {
        const nBytes = readUInt8();
        if (nBytes == 0)
            return DbDateTime.min;
        auto bytes = _buffer.consume(nBytes);
        return dateTimeDecode(bytes);
    }

    D readDecimal(D)() @trusted // cast
    if (isDecimal!D)
    {
        // TODO field scale

        auto s = cast(char[])consumeBytes();
        return D(s, RoundingMode.banking);
    }

    pragma(inline, true)
    float32 readFloat32()
    {
        static assert(float32.sizeof == uint32.sizeof);

        return asFloatBit!(uint32, float32)(readUInt32!(4u)());
    }

    pragma(inline, true)
    float64 readFloat64()
    {
        static assert(float64.sizeof == uint64.sizeof);

        return asFloatBit!(uint64, float64)(readUInt64!(8u)());
    }

    pragma(inline, true)
    int8 readInt8() // TINYINT
    {
        return _reader.readInt8();
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return cast(int16)(cast(int32)readUInt32!(2u)());
    }

    pragma(inline, true)
    int32 readInt32()
    {
        return cast(int32)readUInt32!(4u)();
    }

    pragma(inline, true)
    int64 readInt64()
    {
        return cast(int64)readUInt64!(8u)();
    }

    pragma(inline, true)
    int64 readLength()
    {
        return readPackedInt64();
    }

    string readNullTerminatedString() @trusted
    {
        auto bytes = _buffer.peekBytes();
        size_t len = 0;
        while (len < bytes.length && bytes[len] != 0 && cast(int)bytes[len] != -1)
            len++;

        string result = len != 0 ? cast(string)_reader.readChars(len) : null;
        _reader.advance(1); // Skip null terminated char
        return result;
    }

    int32 readPackedInt32()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.negOne: return -1;
            case MyPackedIntegerIndicator.twoByte: return cast(int32)readUInt32!(2u)();
            case MyPackedIntegerIndicator.threeByte: return cast(int32)readUInt32!(3u)();
            case MyPackedIntegerIndicator.fourOrEightByte: return cast(int32)readUInt32!(4u)();
            default: return cast(int32)c;
        }
    }

    int64 readPackedInt64()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.negOne: return -1L;
            case MyPackedIntegerIndicator.twoByte: return cast(int64)readUInt64!(2u)();
            case MyPackedIntegerIndicator.threeByte: return cast(int64)readUInt64!(3u)();
            case MyPackedIntegerIndicator.fourOrEightByte: return cast(int64)readUInt64!(8u)();
            default: return cast(int64)c;
        }
    }

    uint32 readPackedUInt32()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.twoByte: return readUInt32!(2u)();
            case MyPackedIntegerIndicator.threeByte: return readUInt32!(3u)();
            case MyPackedIntegerIndicator.fourOrEightByte: return readUInt32!(4u)();
            default: return cast(uint32)c;
        }
    }

    uint64 readPackedUInt64()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.twoByte: return readUInt64!(2u)();
            case MyPackedIntegerIndicator.threeByte: return readUInt64!(3u)();
            case MyPackedIntegerIndicator.fourOrEightByte: return readUInt64!(8u)();
            default: return cast(uint64)c;
        }
    }

    pragma(inline, true)
    string readString() @trusted
    {
        return cast(string)readBytes();
    }

    DbTimeSpan readTimeSpan()
    {
        const nBytes = readUInt8();
        if (nBytes == 0)
            return DbTimeSpan.zero;
        auto bytes = _buffer.consume(nBytes);
        return timeSpanDecode(bytes);
    }

    pragma(inline, true)
    uint8 readUInt8()
    {
        return _reader.readUInt8();
    }

    pragma(inline, true)
    uint16 readUInt16()
    {
        return cast(uint16)readUInt32!(2u)();
    }

    pragma(inline, true)
    uint32 readUInt32()
    {
        return readUInt32!(4u)();
    }

    // This is optimized for 32 bits build to avoid value return on stack
    // if use readUInt64
    pragma(inline, true)
    uint32 readUInt32(uint8 NBytes)()
    if (NBytes == 2u || NBytes == 3u || NBytes == 4u)
    {
        auto bytes = _buffer.consume(NBytes);
        return uintDecode!(uint32)(bytes);
    }

    pragma(inline, true)
    uint64 readUInt64()
    {
        return readUInt64!(8u)();
    }

    pragma(inline, true)
    uint64 readUInt64(uint8 NBytes)()
    if (NBytes == 2u || NBytes == 3u || NBytes == 8u)
    do
    {
        auto bytes = _buffer.consume(NBytes);
        return uintDecode!(uint64)(bytes);
    }

    // "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    UUID readUUID()
    {
        //auto s = readString();
        auto s = cast(char[])consumeBytes();
        return UUID(s);
    }

    @property DbReadBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property MyConnection connection() nothrow pure
    {
        return _connection;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _buffer.empty;
    }

private:
    ubyte[] consumeBytes()
    {
        const len = readLength();
        return consumeBytes(cast(int32)len);
    }

    pragma(inline, true)
    ubyte[] consumeBytes(const(int32) len)
    {
        return len > 0 ? _buffer.consume(cast(size_t)len) : null;
    }

    pragma(inline, true)
    ubyte[] readBytes(const(int32) len)
    {
        return len > 0 ? _reader.readBytes(cast(size_t)len) : null;
    }

private:
    DbReadBuffer _buffer;
    MyConnection _connection;
    DbValueReader!(Endian.littleEndian) _reader;
    bool _connectionBuffer;
}

struct MyWriter
{
@safe:

public:
    @disable this(this);

    this(MyConnection connection) nothrow
    {
        this._socketBuffer = true;
        this._connection = connection;
        this._buffer = connection.acquireSocketWriteBuffer();
        this._writer = DbValueWriter!(Endian.littleEndian)(this._buffer);
    }

    this(MyConnection connection, DbWriteBuffer buffer) nothrow
    {
        buffer.reset();
        this._socketBuffer = false;
        this._connection = connection;
        this._buffer = buffer;
        this._writer = DbValueWriter!(Endian.littleEndian)(buffer);
    }

    ~this()
    {
        dispose(false);
    }

    void dispose(bool disposing = true)
    {
        _writer.dispose(disposing);
        if (_socketBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);
        _buffer = null;
        _connection = null;
    }

    void flush()
    {
        version (TraceFunction) dgFunctionTrace();

        _buffer.flush();
    }

    pragma(inline, true)
    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

    pragma(inline, true)
    void writeBit(uint64 v) nothrow
    {
        writeUInt64!(8u)(v);
    }

    pragma(inline, true)
    void writeBytes(scope const(ubyte)[] v) nothrow
    {
        writeLength(cast(int64)v.length);
        if (v.length)
            _writer.writeBytes(v);
    }

    pragma(inline, true)
    void writeDate(scope const(DbDate) v) nothrow
    {
        ubyte[maxDateBufferSize] bytes = void;
        const nBytes = dateEncode(bytes, v);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    pragma(inline, true)
    void writeDateTime(scope const(DbDateTime) v) nothrow
    {
        ubyte[maxDateTimeBufferSize] bytes = void;
        const nBytes = dateTimeEncode(bytes, v);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    void writeDecimal(D)(scope const(D) v)
    if (isDecimal!D)
    {
        // TODO field scale

        ShortStringBuffer!char buffer;
        writeString(v.toString!(ShortStringBuffer!char, char)(buffer)[]);
    }

    pragma(inline, true)
    void writeFloat32(float32 v) nothrow
    {
        static assert(uint32.sizeof == float32.sizeof);

        writeUInt32!(4u)(asIntegerBit!(float32, uint32)(v));
    }

    pragma(inline, true)
    void writeFloat64(float64 v) nothrow
    {
        static assert(uint64.sizeof == float64.sizeof);

        writeUInt64!(8u)(asIntegerBit!(float64, uint64)(v));
    }

    pragma(inline, true)
    void writeInt8(int8 v) nothrow // TINYINT
    {
        _writer.writeInt8(v);
    }

    pragma(inline, true)
    void writeInt16(int16 v) nothrow
    {
        writeUInt32!(2u)(cast(uint32)v);
    }

    pragma(inline, true)
    void writeInt32(int32 v) nothrow
    {
        writeUInt32!(4u)(cast(uint32)v);
    }

    pragma(inline, true)
    void writeInt64(int64 v) nothrow
    {
        writeUInt64!(8u)(cast(uint64)v);
    }

    pragma(inline, true)
    void writeLength(int64 length) nothrow
    in
    {
        assert(length >= 0);
    }
    do
    {
        writePackedUInt64(cast(uint64)length);
    }

    void writeNullTerminatedString(scope const(char)[] v) nothrow
    in
    {
        assert(v.length < int32.max);
    }
    do
    {
        if (v.length)
            _writer.writeBytes(v.representation);
        _writer.writeUInt8(0);
    }

    pragma(inline, true)
    void writePackedInt32(int32 v) nothrow
    {
        if (v == -1)
            writeUInt8(MyPackedIntegerIndicator.negOne);
        else
            writePackedUInt32(cast(uint32)v);
    }

    pragma(inline, true)
    void writePackedInt64(int64 v) nothrow
    {
        if (v == -1)
            writeUInt8(MyPackedIntegerIndicator.negOne);
        else
            writePackedUInt64(cast(uint64)v);
    }

    pragma(inline, true)
    void writePackedUInt32(uint32 v) nothrow
    {
        uint8 nBytes = void;
        auto bytes = uintEncodePacked!(uint32)(v, nBytes);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    pragma(inline, true)
    void writePackedUInt64(uint64 v) nothrow
    {
        uint8 nBytes = void;
        auto bytes = uintEncodePacked!(uint64)(v, nBytes);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    void writeString(scope const(char)[] v) nothrow
    in
    {
        assert(v.length < int32.max);
    }
    do
    {
        writeLength(cast(int64)v.length);
        if (v.length)
            _writer.writeBytes(v.representation);
    }

    void writeTimeSpan(scope const(DbTimeSpan) v) nothrow
    {
        ubyte[maxTimeSpanBufferSize] bytes = void;
        const nBytes = timeSpanEncode(bytes, v);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    pragma(inline, true)
    void writeUInt8(uint8 v) nothrow
    {
        _writer.writeUInt8(v);
    }

    pragma(inline, true)
    void writeUInt16(uint16 v) nothrow
    {
        writeUInt32!(2u)(cast(uint32)v);
    }

    pragma(inline, true)
    void writeUInt32(uint32 v) nothrow
    {
        writeUInt32!(4u)(v);
    }

    // This is optimized for 32 bits build to avoid values passed on stack
    // if use writeUInt64
    void writeUInt32(uint8 NBytes)(uint32 v) nothrow
    if (NBytes == 2u || NBytes == 3u || NBytes == 4u)
    {
        auto bytes = uintEncode!(uint32, NBytes)(v);
        _writer.writeBytes(bytes[0..NBytes]);
    }

    pragma(inline, true)
    void writeUInt64(uint64 v) nothrow
    {
        writeUInt64!(8u)(v);
    }

    void writeUInt64(uint8 NBytes)(uint64 v) nothrow
    if (NBytes == 2u || NBytes == 3u || NBytes == 8u)
    {
        auto bytes = uintEncode!(uint64, NBytes)(v);
        _writer.writeBytes(bytes[0..NBytes]);
    }

    // "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    void writeUUID(scope const(UUID) v) nothrow
    {
        char[36] tempBuffer;
        v.toString(tempBuffer[]);
        writeString(tempBuffer[]);
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property MyConnection connection() nothrow pure
    {
        return _connection;
    }

private:
    DbWriteBuffer _buffer;
    MyConnection _connection;
    DbValueWriter!(Endian.littleEndian) _writer;
    bool _socketBuffer;
}


// Any below codes are private
private:

unittest // MyWriter & MyReader
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.mybuffer.MyReader & db.mybuffer.MyWriter");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";
    const(ubyte)[] bytes = [1,2,5,101];
    const(UUID) uuid = UUID(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer(4000);
    auto writer = MyWriter(null, writerBuffer);
    writer.writeBit(103uL);
    writer.writeBytes(bytes);
    writer.writeDate(DbDate(1, 2, 3));
    writer.writeDateTime(DbDateTime(DateTime(1,2,3,4,5,6), 0));

    writer.writeDecimal!Decimal32(Decimal32.min);
    writer.writeDecimal!Decimal32(Decimal32(0));
    writer.writeDecimal!Decimal32(Decimal32.money(12345.67, 2));
    writer.writeDecimal!Decimal32(Decimal32.max);

    writer.writeDecimal!Decimal64(Decimal64.min);
    writer.writeDecimal!Decimal64(Decimal64(0));
    writer.writeDecimal!Decimal64(Decimal64.money(23456.78, 2));
    writer.writeDecimal!Decimal64(Decimal64.max);

    writer.writeDecimal!Decimal128(Decimal128.min);
    writer.writeDecimal!Decimal128(Decimal128(0));
    writer.writeDecimal!Decimal128(Decimal128.money(34567.89, 2));
    writer.writeDecimal!Decimal128(Decimal128.max);

    writer.writeFloat32(float.min_normal);
    writer.writeFloat32(32.32);
    writer.writeFloat32(float.max);
    writer.writeFloat64(double.min_normal);
    writer.writeFloat64(64.64);
    writer.writeFloat64(double.max);

    writer.writeInt8(byte.min);
    writer.writeInt8(8);
    writer.writeInt8(byte.max);
    writer.writeInt16(short.min);
    writer.writeInt16(16);
    writer.writeInt16(short.max);
    writer.writeInt32(int.min);
    writer.writeInt32(32);
    writer.writeInt32(int.max);
    writer.writeInt64(long.min);
    writer.writeInt64(64);
    writer.writeInt64(long.max);
    writer.writeLength(123456);
    writer.writeNullTerminatedString(chars);
    writer.writePackedInt32(int.min);
    writer.writePackedInt32(-1);
    writer.writePackedInt32(123456);
    writer.writePackedInt32(int.max);
    writer.writePackedInt64(long.min);
    writer.writePackedInt64(-1);
    writer.writePackedInt64(234567);
    writer.writePackedInt64(long.max);
    writer.writePackedUInt32(123456);
    writer.writePackedUInt32(uint.max);
    writer.writePackedUInt64(234567);
    writer.writePackedUInt64(ulong.max);
    writer.writeString(chars);
    writer.writeTimeSpan(DbTimeSpan(dur!"msecs"(short.min)));
    writer.writeTimeSpan(DbTimeSpan(dur!"msecs"(-1)));
    writer.writeTimeSpan(DbTimeSpan(dur!"msecs"(0)));
    writer.writeTimeSpan(DbTimeSpan(dur!"msecs"(345)));
    writer.writeTimeSpan(DbTimeSpan(dur!"msecs"(short.max)));
    writer.writeUInt8(123);
    writer.writeUInt8(ubyte.max);
    writer.writeUInt16(234);
    writer.writeUInt16(ushort.max);
    writer.writeUInt32(345);
    writer.writeUInt32(uint.max);
    writer.writeUInt64(456);
    writer.writeUInt64(ulong.max);
    writer.writeUUID(uuid);

    ubyte[] writerBytes = writer.peekBytes();
    auto reader = MyReader(null, writerBytes);
    assert(reader.readBit() == 103uL);
    assert(reader.readBytes() == bytes);
    assert(reader.readDate() == DbDate(1, 2, 3));
    assert(reader.readDateTime() == DbDateTime(DateTime(1,2,3,4,5,6), 0));

    //dgWriteln("Decimal32.min=", Decimal32.min.toString());
    //dgWriteln("Decimal32.min=", Decimal32.max.toString());
    //dgWriteln("Decimal64.min=", Decimal64.min.toString());
    //dgWriteln("Decimal64.min=", Decimal64.max.toString());
    //dgWriteln("Decimal128.min=", Decimal128.min.toString());
    //dgWriteln("Decimal128.min=", Decimal128.max.toString());

    assert(reader.readDecimal!Decimal32() == Decimal32.min);
    assert(reader.readDecimal!Decimal32() == Decimal32(0));
    assert(reader.readDecimal!Decimal32() == Decimal32.money(12345.67, 2));
    assert(reader.readDecimal!Decimal32() == Decimal32.max);

    assert(reader.readDecimal!Decimal64() == Decimal64.min);
    assert(reader.readDecimal!Decimal64() == Decimal64(0));
    assert(reader.readDecimal!Decimal64() == Decimal64.money(23456.78, 2));
    assert(reader.readDecimal!Decimal64() == Decimal64.max);

    assert(reader.readDecimal!Decimal128() == Decimal128.min);
    assert(reader.readDecimal!Decimal128() == Decimal128(0));
    assert(reader.readDecimal!Decimal128() == Decimal128.money(34567.89, 2));
    assert(reader.readDecimal!Decimal128() == Decimal128.max);

    assert(reader.readFloat32() == float.min_normal);
    assert(reader.readFloat32() == cast(float)32.32);
    assert(reader.readFloat32() == float.max);
    assert(reader.readFloat64() == double.min_normal);
    assert(reader.readFloat64() == cast(double)64.64);
    assert(reader.readFloat64() == double.max);

    assert(reader.readInt8() == byte.min);
    assert(reader.readInt8() == 8);
    assert(reader.readInt8() == byte.max);
    assert(reader.readInt16() == short.min);
    assert(reader.readInt16() == 16);
    assert(reader.readInt16() == short.max);
    assert(reader.readInt32() == int.min);
    assert(reader.readInt32() == 32);
    assert(reader.readInt32() == int.max);
    assert(reader.readInt64() == long.min);
    assert(reader.readInt64() == 64);
    assert(reader.readInt64() == long.max);
    assert(reader.readLength() == 123456);
    assert(reader.readNullTerminatedString() == chars);
    assert(reader.readPackedInt32() == int.min);
    assert(reader.readPackedInt32() == -1);
    assert(reader.readPackedInt32() == 123456);
    assert(reader.readPackedInt32() == int.max);
    assert(reader.readPackedInt64() == long.min);
    assert(reader.readPackedInt64() == -1);
    assert(reader.readPackedInt64() == 234567);
    assert(reader.readPackedInt64() == long.max);
    assert(reader.readPackedUInt32() == 123456);
    assert(reader.readPackedUInt32() == uint.max);
    assert(reader.readPackedUInt64() == 234567);
    assert(reader.readPackedUInt64() == ulong.max);
    assert(reader.readString() == chars);
    assert(reader.readTimeSpan() == DbTimeSpan(dur!"msecs"(short.min)));
    assert(reader.readTimeSpan() == DbTimeSpan(dur!"msecs"(-1)));
    assert(reader.readTimeSpan() == DbTimeSpan(dur!"msecs"(0)));
    assert(reader.readTimeSpan() == DbTimeSpan(dur!"msecs"(345)));
    assert(reader.readTimeSpan() == DbTimeSpan(dur!"msecs"(short.max)));
    assert(reader.readUInt8() == 123);
    assert(reader.readUInt8() == ubyte.max);
    assert(reader.readUInt16() == 234);
    assert(reader.readUInt16() == ushort.max);
    assert(reader.readUInt32() == 345);
    assert(reader.readUInt32() == uint.max);
    assert(reader.readUInt64() == 456);
    assert(reader.readUInt64() == ulong.max);
    assert(reader.readUUID() == uuid);
}
