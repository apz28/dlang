/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.buffer;

import std.bitmanip : swapEndian;
import std.string : representation;
import std.system : Endian;

version (unittest) import pham.utl.test;
import pham.utl.dlink_list;
import pham.utl.object : alignRoundup;
import pham.utl.utf8 : inplaceMoveToLeft;
import pham.db.type;
import pham.db.message;
import pham.db.exception;
import pham.db.object;
import pham.db.util : asFloatBit, asIntegerBit;
import pham.db.convert;

@safe:

// Network byte order is BigEndian

class DbBuffer : DbDisposableObject
{
@safe:

protected:
    override void doDispose(bool disposing) nothrow
    {
        _data = null;
        _offset = 0;
        _next = null;
        _prev = null;
    }

protected:
    enum size_t alignValue = 32;
    ubyte[] _data;
    size_t _offset;

private:
    DbBuffer _next;
    DbBuffer _prev;
}

mixin DLinkTypes!(DbBuffer) DLinkDbBufferTypes;

class DbReadBuffer : DbBuffer
{
@safe:

public:
    this(size_t capacity) nothrow
    {
        this._offset = this._maxLength = 0;
        this._data = null;
        if (capacity)
            reserve(capacity);
    }

    this(ubyte[] data) nothrow pure
    {
        this._offset = 0;
        this._data = data;
        this._maxLength = data.length;
    }

    final void advance(const(size_t) nBytes)
    {
        if (length < nBytes)
            ensureAvailable(nBytes);
        _offset += nBytes;
    }

    final ubyte[] consume(const(size_t) nBytes)
    {
        if (length < nBytes)
            ensureAvailable(nBytes);
        auto result = _data[_offset.._offset + nBytes];
        _offset += nBytes;
        return result;
    }

    final void ensureAvailable(const(size_t) nBytes) @trusted
    {
        version (profile) debug auto p = PerfFunction.create();

        if ((_offset + nBytes) > _maxLength)
        {
            fill(nBytes, false);
            if ((_offset + nBytes) > _maxLength)
            {
                auto msg = DbMessage.eNotEnoughData.fmtMessage(nBytes, length);
                throw new DbException(msg, DbErrorCode.read, 0, 0);
            }
        }
    }

    pragma(inline, true)
    final void ensureAvailableIf(const(size_t) nBytes)
    {
        if (length < nBytes)
            ensureAvailable(nBytes);
    }

    void fill(const(size_t) additionalBytes, bool mustSatisfied)
    {}

    final ubyte[] peekBytes() nothrow pure
    {
        return _data[_offset.._offset + length];
    }

    final void reset() nothrow pure
    {
        _offset = 0;
    }

    final size_t search(const(ubyte) searchedByte) nothrow pure
    {
        auto endOffset = _offset;
        while (endOffset < _maxLength)
        {
            if (_data[endOffset] == searchedByte)
            {
                endOffset++;
                break;
            }
            else
                endOffset++;
        }
        return endOffset - _offset;
    }

    pragma(inline, true)
    @property final bool empty() const nothrow pure
    {
        return _offset >= _maxLength;
    }

    pragma(inline, true)
    @property final size_t length() const nothrow pure
    {
        return _offset >= _maxLength ? 0 : _maxLength - _offset;
    }

    pragma(inline, true)
    @property final size_t offset() const nothrow pure
    {
        return _offset;
    }

protected:
    override void doDispose(bool disposing) nothrow
    {
        _maxLength = 0;
        super.doDispose(disposing);
    }

    final void mergeOffset() nothrow
    in
    {
        assert(_offset != 0);
    }
    do
    {
        //dgWriteln("offset=", _offset, ", length=", length, ", _data.length=", _data.length);

        const saveLength = length;
        if (saveLength != 0)
            inplaceMoveToLeft(_data, _offset, 0, saveLength);
        _offset = 0;
        _maxLength = saveLength;
    }

    final ubyte[] readBytesImpl(const(size_t) nBytes)
    {
        ensureAvailableIf(nBytes);

        const start = _offset;
        _offset += nBytes;
        return _data[start.._offset].dup;
    }

    final ubyte[] readBytesImpl(return ubyte[] value)
    {
        const nBytes = value.length;
        ensureAvailableIf(nBytes);

        const start = _offset;
        _offset += nBytes;
        value[0..nBytes] = _data[start.._offset];
        return value;
    }

    pragma(inline, true)
    final void reserve(const(size_t) additionalBytes) nothrow @trusted
    {
        const curLength = length;
        if (_data.length < (_offset + curLength + additionalBytes))
        {
            _data.assumeSafeAppend();
            _data.length = alignRoundup((_offset << 1) + curLength + additionalBytes, alignValue);
        }
    }

protected:
    size_t _maxLength;
}

struct DbValueReader(Endian EndianKind)
{
@safe:

public:
    @disable this(this);

    this(DbReadBuffer buffer) nothrow pure
    {
        this._buffer = buffer;
    }

    void dispose(bool disposing = true) nothrow pure
    {
        _buffer = null;
    }

    pragma(inline, true)
    void advance(const(size_t) nBytes)
    {
        _buffer.advance(nBytes);
    }

    pragma(inline, true)
    ubyte[] peekBytes() nothrow pure
    {
        return _buffer.peekBytes();
    }

    pragma(inline, true)
    bool readBool()
    {
        return readUInt8() != 0;
    }

    pragma(inline, true)
    ubyte[] readBytes(size_t nBytes)
    {
        return _buffer.readBytesImpl(nBytes);
    }

    pragma(inline, true)
    ubyte[] readBytes(return ubyte[] value)
    in
    {
        assert(value.length != 0);
    }
    do
    {
        return _buffer.readBytesImpl(value);
    }

    pragma(inline, true)
    char readChar()
    {
        return cast(char)readUInt8();
    }

    pragma(inline, true)
    char[] readChars(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(char[])_buffer.readBytesImpl(nBytes);
    }

    pragma(inline, true)
    float32 readFloat32() @trusted
    {
        static assert(uint32.sizeof == float32.sizeof);

        return asFloatBit!(uint32, float32)(readUInt32());
    }

    pragma(inline, true)
    float64 readFloat64() @trusted
    {
        static assert(uint64.sizeof == float64.sizeof);

        return asFloatBit!(uint64, float64)(readUInt64());
    }

    pragma(inline, true)
    int8 readInt8()
    {
        return cast(int8)readUInt8();
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return cast(int16)readUInt16();
    }

    pragma(inline, true)
    int32 readInt32()
    {
        return cast(int32)readUInt32();
    }

    void readTwoInt32(out int32 i1, out int32 i2)
    {
        const bytes = _buffer.consume(uint32.sizeof * 2);
        i1 = cast(int32)uintDecode!(uint32, EndianKind)(bytes[0..uint32.sizeof]);
        i2 = cast(int32)uintDecode!(uint32, EndianKind)(bytes[uint32.sizeof..$]);
    }

    pragma(inline, true)
    int64 readInt64()
    {
        return cast(int64)readUInt64();
    }

    uint8 readUInt8()
    {
        _buffer.ensureAvailableIf(uint8.sizeof);

        return _buffer._data[_buffer._offset++];
    }

    uint16 readUInt16()
    {
        const bytes = _buffer.consume(uint16.sizeof);
        return uintDecode!(uint16, EndianKind)(bytes);
    }

    uint32 readUInt32()
    {
        const bytes = _buffer.consume(uint32.sizeof);
        return uintDecode!(uint32, EndianKind)(bytes);
    }

    uint64 readUInt64()
    {
        const bytes = _buffer.consume(uint64.sizeof);
        return uintDecode!(uint64, EndianKind)(bytes);
    }

    @property DbReadBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _buffer.empty;
    }

private:
    DbReadBuffer _buffer;
}

class DbWriteBuffer : DbBuffer
{
@safe:

public:
    this(size_t capacity) nothrow
    {
        this._data = null;
        this._offset = 0;
        reserve(capacity);
    }

    void flush()
    {
        reset();
    }

    version (TraceFunction)
    final string logData() nothrow @trusted
    {
        import std.conv : to;
        import pham.utl.object : bytesToHexs;

        const bytes = peekBytes();
        return "length=" ~ to!string(bytes.length) ~ ", data=" ~ cast(string)bytesToHexs(bytes);
    }

    final ubyte[] peekBytes() nothrow
    {
        return _data[0..length];
    }

    DbWriteBuffer reset() nothrow
    {
        _offset = 0;
        return this;
    }

    @property final bool empty() const nothrow pure
    {
        return _offset == 0;
    }

    pragma(inline, true)
    @property final size_t length() const nothrow pure
    {
        return _offset;
    }

    pragma(inline, true)
    @property final size_t offset() const nothrow pure
    {
        return _offset;
    }

protected:
    pragma(inline, true)
    final void reserve(size_t additionalBytes) nothrow @trusted
    {
        if (_data.length < _offset + additionalBytes)
        {
            _data.assumeSafeAppend();
            _data.length = alignRoundup((_offset << 1) + additionalBytes, alignValue);
        }

        assert(_data.length >= _offset + additionalBytes);
    }

    final void writeBytesImpl(scope const(ubyte)[] v) nothrow
    {
        const nBytes = v.length;
        if (nBytes)
        {
            reserve(nBytes);

            _data[_offset.._offset + nBytes] = v[];
            _offset += nBytes;
        }
    }
}

struct DbValueWriter(Endian EndianKind)
{
@safe:

public:
    @disable this(this);

    this(DbWriteBuffer buffer) nothrow pure
    {
        this._buffer = buffer;
    }

    void dispose(bool disposing = true) nothrow pure
    {
        _buffer = null;
    }

    void rewriteInt32(int32 v, size_t rewriteOffset) nothrow
    in
    {
        assert(rewriteOffset <= _buffer._offset);
    }
    do
    {
        const saveOffset = _buffer._offset;
        _buffer._offset = rewriteOffset;
        scope (exit)
            _buffer._offset = saveOffset;

        writeInt32(v);
    }

    pragma(inline, true)
    void writeBool(bool v) nothrow
    {
        writeUInt8(v ? 1 : 0);
    }

    pragma(inline, true)
    void writeBytes(scope const(ubyte)[] v) nothrow
    {
        _buffer.writeBytesImpl(v);
    }

    pragma(inline, true)
    void writeChar(char v) nothrow
    {
        writeUInt8(cast(ubyte)v);
    }

    pragma(inline, true)
    void writeChars(scope const(char)[] v) nothrow
    {
        return _buffer.writeBytesImpl(v.representation);
    }

    pragma(inline, true)
    void writeFloat32(float32 v) nothrow @trusted
    {
        static assert(float32.sizeof == uint32.sizeof);

        writeUInt32(asIntegerBit!(float32, uint32)(v));
    }

    pragma(inline, true)
    void writeFloat64(float64 v) nothrow @trusted
    {
        static assert(float64.sizeof == uint64.sizeof);

        writeUInt64(asIntegerBit!(float64, uint64)(v));
    }

    pragma(inline, true)
    void writeInt8(int8 v) nothrow
    {
        writeUInt8(cast(uint8)v);
    }

    pragma(inline, true)
    void writeInt16(int16 v) nothrow
    {
        writeUInt16(cast(uint16)v);
    }

    pragma(inline, true)
    void writeInt32(int32 v) nothrow
    {
        writeUInt32(cast(uint32)v);
    }

    pragma(inline, true)
    void writeInt64(int64 v) nothrow
    {
        writeUInt64(cast(uint64)v);
    }

    void writeUInt8(uint8 v) nothrow
    {
        _buffer.reserve(uint8.sizeof);

        _buffer._data[_buffer._offset++] = v;
    }

    void writeUInt16(uint16 v) nothrow
    {
        auto bytes = uintEncode!(uint16, EndianKind)(v);
        _buffer.writeBytesImpl(bytes[]);
    }

    void writeUInt32(uint32 v) nothrow
    {
        auto bytes = uintEncode!(uint32, EndianKind)(v);
        _buffer.writeBytesImpl(bytes[]);
    }

    void writeUInt64(uint64 v) nothrow
    {
        auto bytes = uintEncode!(uint64, EndianKind)(v);
        _buffer.writeBytesImpl(bytes[]);
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

private:
    DbWriteBuffer _buffer;
}


// Any below codes are private
private:

unittest // DbWriteBuffer & DbReadBuffer
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.buffer.DbWriteBuffer & db.buffer.DbReadBuffer");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer(4000);
    auto writer = DbValueWriter!(Endian.littleEndian)(writerBuffer);
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
    writer.writeFloat32(float.min_normal);
    writer.writeFloat32(32.32);
    writer.writeFloat32(float.max);
    writer.writeFloat64(double.min_normal);
    writer.writeFloat64(64.64);
    writer.writeFloat64(double.max);
    writer.writeChars(chars);
    ubyte[] bytes = writerBuffer.peekBytes().dup;
    writerBuffer.dispose();
    writerBuffer = null;

    auto readerBuffer = new DbReadBuffer(bytes);
    auto reader = DbValueReader!(Endian.littleEndian)(readerBuffer);
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
    assert(reader.readFloat32() == float.min_normal);
    assert(reader.readFloat32() == cast(float)32.32);
    assert(reader.readFloat32() == float.max);
    assert(reader.readFloat64() == double.min_normal);
    assert(reader.readFloat64() == cast(double)64.64);
    assert(reader.readFloat64() == double.max);
    assert(reader.readChars(chars.length) == chars);
    assert(reader.empty);
    readerBuffer.dispose();
    readerBuffer = null;
}
