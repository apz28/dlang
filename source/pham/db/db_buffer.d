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
import std.format : format;
import std.string : representation;
import std.system : Endian;

version (unittest) import pham.utl.utltest;
import pham.utl.dlink_list;
import pham.utl.utlobject : alignRoundup;
import pham.utl.utf8 : inplaceMoveToLeft;
import pham.db.type;
import pham.db.message;
import pham.db.exception;
import pham.db.dbobject;
import pham.db.util;

@safe:

// Network byte order is BigEndian

class DbBuffer : DbDisposableObject
{
@safe:

public:
    IbReadBuffer isReadBuffer() nothrow pure
    {
        return null;
    }

    IbWriteBuffer isWriteBuffer() nothrow pure
    {
        return null;
    }

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

interface IbReadBuffer
{
@safe:

    IbReadBuffer advance(size_t nBytes);
    IbReadBuffer fill(const size_t additionalBytes, bool mustSatisfied);
    ubyte[] peekBytes() nothrow;
    IbReadBuffer reset() nothrow;
    size_t search(ubyte searchedByte) nothrow;
    DbBuffer self() nothrow pure;

    bool readBool();
    ubyte[] readBytes(size_t nBytes);
    ubyte[] readBytes(return ubyte[] value);
    char readChar();
    char[] readChars(size_t nBytes);
    float32 readFloat32();
    float64 readFloat64();
    int8 readInt8();
    int16 readInt16();
    int32 readInt32();
    int64 readInt64();
    uint8 readUInt8();
    uint16 readUInt16();
    uint32 readUInt32();
    uint64 readUInt64();

    @property bool empty() const nothrow pure;
    @property size_t length() const nothrow pure;
    @property size_t offset() const nothrow pure;
}

class DbReadBuffer(Endian EndianKind = Endian.bigEndian) : DbBuffer, IbReadBuffer
{
@safe:

public:
    this(size_t capacity)
    {
        this._offset = this._maxLength = 0;
        this._data = null;
        reserve(capacity);
    }

    this(ubyte[] data)
    {
        this._offset = 0;
        this._data = data;
        this._maxLength = data.length;
    }

    override IbReadBuffer advance(size_t nBytes)
    {
        if (length < nBytes)
            ensureAvailable(nBytes);
        _offset += nBytes;
        return this;
    }

    override IbReadBuffer fill(const size_t additionalBytes, bool mustSatisfied)
    {
        return this;
    }

    final override IbReadBuffer isReadBuffer() nothrow pure
    {
        return this;
    }

    final override ubyte[] peekBytes() nothrow
    {
        return _data[_offset.._offset + length];
    }

    override IbReadBuffer reset() nothrow
    {
        _offset = 0;
        return this;
    }

    override size_t search(ubyte searchedByte) nothrow
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

    final override DbBuffer self() nothrow pure
    {
        return this;
    }

    final override bool readBool()
    {
        return readUInt8() != 0;
    }

    final override ubyte[] readBytes(size_t nBytes)
    {
        return readBytesImpl(nBytes);
    }

    final override ubyte[] readBytes(return ubyte[] value)
    in
    {
        assert(value.length != 0);
    }
    do
    {
        return readBytesImpl(value);
    }

    final override char readChar()
    {
        return cast(char)readUInt8();
    }

    final override char[] readChars(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(char[])readBytesImpl(nBytes);
    }

    final override float32 readFloat32() @trusted
    {
        auto result = readUInt32();
        return *cast(float32 *)&result;
    }

    final override float64 readFloat64() @trusted
    {
        auto result = readUInt64();
        return *cast(float64 *)&result;
    }

    final override int8 readInt8()
    {
        return cast(int8)readUInt8();
    }

    final override int16 readInt16()
    {
        return cast(int16)readUInt16();
    }

    final override int32 readInt32()
    {
        return cast(int32)readUInt32();
    }

    final override int64 readInt64()
    {
        return cast(int64)readUInt64();
    }

    final override uint8 readUInt8()
    {
        if (length < uint8.sizeof)
            ensureAvailable(uint8.sizeof);

        return _data[_offset++];
    }

    final override uint16 readUInt16()
    {
        if (length < uint16.sizeof)
            ensureAvailable(uint16.sizeof);

        uint16 result = void;
        static if (EndianKind == Endian.littleEndian)
            result = cast(uint16)_data[_offset++]
                | (cast(uint16)_data[_offset++] << 8);
        else
            result = (cast(uint16)_data[_offset++] << 8)
                | cast(uint16)_data[_offset++];

        version (BigEndian)
        static if (EndianKind == Endian.littleEndian)
            result = swapEndian(result);

        return result;
    }

    final override uint32 readUInt32()
    {
        if (length < uint32.sizeof)
            ensureAvailable(uint32.sizeof);

        uint32 result = void;
        static if (EndianKind == Endian.littleEndian)
            result = cast(uint32)_data[_offset++]
                | (cast(uint32)_data[_offset++] << 8)
                | (cast(uint32)_data[_offset++] << 16)
                | (cast(uint32)_data[_offset++] << 24);
        else
            result = (cast(uint32)_data[_offset++] << 24)
                | (cast(uint32)_data[_offset++] << 16)
                | (cast(uint32)_data[_offset++] << 8)
                | cast(uint32)_data[_offset++];

        version (BigEndian)
        static if (EndianKind == Endian.littleEndian)
            result = swapEndian(result);

        return result;
    }

    final override uint64 readUInt64()
    {
        if (length < uint64.sizeof)
            ensureAvailable(uint64.sizeof);

        uint64 result = void;
        static if (EndianKind == Endian.littleEndian)
            result = cast(uint64)_data[_offset++]
                | (cast(uint64)_data[_offset++] << 8)
                | (cast(uint64)_data[_offset++] << 16)
                | (cast(uint64)_data[_offset++] << 24)
                | (cast(uint64)_data[_offset++] << 32)
                | (cast(uint64)_data[_offset++] << 40)
                | (cast(uint64)_data[_offset++] << 48)
                | (cast(uint64)_data[_offset++] << 56);
        else
            result = (cast(uint64)_data[_offset++] << 56)
                | (cast(uint64)_data[_offset++] << 48)
                | (cast(uint64)_data[_offset++] << 40)
                | (cast(uint64)_data[_offset++] << 32)
                | (cast(uint64)_data[_offset++] << 24)
                | (cast(uint64)_data[_offset++] << 16)
                | (cast(uint64)_data[_offset++] << 8)
                | cast(uint64)_data[_offset++];

        version (BigEndian)
        static if (EndianKind == Endian.littleEndian)
            result = swapEndian(result);

        return result;
    }

    @property final override bool empty() const nothrow pure
    {
        return _offset >= _maxLength;
    }

    pragma(inline, true)
    @property final override size_t length() const nothrow pure
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

    void ensureAvailable(size_t nBytes) @trusted
    {
        if (_offset + nBytes > _maxLength)
        {
            auto msg = format(DbMessage.eNotEnoughData, nBytes, length);
            throw new DbException(msg, DbErrorCode.read, 0, 0);
        }
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

    final ubyte[] readBytesImpl(size_t nBytes)
    {
        if (length < nBytes)
            ensureAvailable(nBytes);

        const start = _offset;
        _offset += nBytes;
        return _data[start.._offset].dup;
    }

    final ubyte[] readBytesImpl(return ubyte[] value)
    {
        const nBytes = value.length;
        if (length < nBytes)
            ensureAvailable(nBytes);

        const start = _offset;
        _offset += nBytes;
        value[0..nBytes] = _data[start.._offset];
        return value;
    }

    pragma(inline, true)
    final void reserve(size_t additionalBytes) nothrow @trusted
    {
        const curLength = length;
        if (_data.length < _offset + curLength + additionalBytes)
        {
            _data.assumeSafeAppend();
            _data.length = alignRoundup((_offset << 1) + curLength + additionalBytes, alignValue);
        }
    }

protected:
    size_t _maxLength;
}

interface IbWriteBuffer
{
@safe:

    void flush();
    version (TraceFunction) string logData() nothrow;
    ubyte[] peekBytes() nothrow;
    IbWriteBuffer reset() nothrow;
    IbWriteBuffer rewriteInt32(int32 v, size_t offset) nothrow;
    DbBuffer self() nothrow pure;

    IbWriteBuffer writeBool(bool v) nothrow;
    IbWriteBuffer writeBytes(scope const(ubyte)[] v) nothrow;
    IbWriteBuffer writeChar(char v) nothrow;
    IbWriteBuffer writeChars(scope const(char)[] v) nothrow;
    IbWriteBuffer writeFloat32(float32 v) nothrow;
    IbWriteBuffer writeFloat64(float64 v) nothrow;
    IbWriteBuffer writeInt8(int8 v) nothrow;
    IbWriteBuffer writeInt16(int16 v) nothrow;
    IbWriteBuffer writeInt32(int32 v) nothrow;
    IbWriteBuffer writeInt64(int64 v) nothrow;
    IbWriteBuffer writeUInt8(uint8 v) nothrow;
    IbWriteBuffer writeUInt16(uint16 v) nothrow;
    IbWriteBuffer writeUInt32(uint32 v) nothrow;
    IbWriteBuffer writeUInt64(uint64 v) nothrow;

    @property bool empty() const nothrow;
    @property size_t length() const nothrow;
    @property size_t offset() const nothrow;
}

class DbWriteBuffer(Endian EndianKind = Endian.bigEndian) : DbBuffer, IbWriteBuffer
{
@safe:

public:
    this(size_t capacity)
    {
        this._data = null;
        this._offset = 0;
        reserve(capacity);
    }

    override void flush()
    {
        reset();
    }

    final override IbWriteBuffer isWriteBuffer() nothrow pure
    {
        return this;
    }

    version (TraceFunction)
    final override string logData() nothrow @trusted
    {
        import std.conv : to;
        import pham.utl.utlobject : bytesToHexs;

        const bytes = peekBytes();
        return "length=" ~ to!string(bytes.length) ~ ", data=" ~ cast(string)bytesToHexs(bytes);
    }

    final override ubyte[] peekBytes() nothrow
    {
        return _data[0..length];
    }

    override IbWriteBuffer reset() nothrow
    {
        _offset = 0;
        return this;
    }

    final override IbWriteBuffer rewriteInt32(int32 v, size_t rewriteOffset) nothrow
    in
    {
        assert(rewriteOffset <= _offset);
    }
    do
    {
        const saveOffset = this._offset;
        this._offset = rewriteOffset;
        scope (exit)
            this._offset = saveOffset;

        return writeInt32(v);
    }

    final override DbBuffer self() nothrow pure
    {
        return this;
    }

    final override IbWriteBuffer writeBool(bool v) nothrow
    {
        return writeUInt8(v ? 1 : 0);
    }

    final override IbWriteBuffer writeBytes(scope const(ubyte)[] v) nothrow
    {
        return writeBytesImpl(v);
    }

    final override IbWriteBuffer writeChar(char v) nothrow
    {
        return writeUInt8(cast(ubyte)v);
    }

    final override IbWriteBuffer writeChars(scope const(char)[] v) nothrow
    {
        return writeBytesImpl(v.representation);
    }

    final override IbWriteBuffer writeFloat32(float32 v) nothrow @trusted
    {
        return writeUInt32(*cast(uint32 *)&v);
    }

    final override IbWriteBuffer writeFloat64(float64 v) nothrow @trusted
    {
        return writeUInt64(*cast(uint64 *)&v);
    }

    final override IbWriteBuffer writeInt8(int8 v) nothrow
    {
        return writeUInt8(cast(uint8)v);
    }

    final override IbWriteBuffer writeInt16(int16 v) nothrow
    {
        return writeUInt16(cast(uint16)v);
    }

    final override IbWriteBuffer writeInt32(int32 v) nothrow
    {
        return writeUInt32(cast(uint32)v);
    }

    final override IbWriteBuffer writeInt64(int64 v) nothrow
    {
        return writeUInt64(cast(uint64)v);
    }

    final override IbWriteBuffer writeUInt8(uint8 v) nothrow
    {
        reserve(uint8.sizeof);

        _data[_offset++] = v;

        return this;
    }

    final override IbWriteBuffer writeUInt16(uint16 v) nothrow
    {
        version (BigEndian)
        static if (EndianKind == Endian.littleEndian)
            v = swapEndian(v);

        reserve(uint16.sizeof);

        static if (EndianKind == Endian.littleEndian)
        {
            _data[_offset++] = v & 0xFF;
            _data[_offset++] = (v >> 8) & 0xFF;
        }
        else
        {
            _data[_offset++] = (v >> 8) & 0xFF;
            _data[_offset++] = v & 0xFF;
        }

        return this;
    }

    final override IbWriteBuffer writeUInt32(uint32 v) nothrow
    {
        version (BigEndian)
        static if (EndianKind == Endian.littleEndian)
            v = swapEndian(v);

        reserve(uint32.sizeof);

        static if (EndianKind == Endian.littleEndian)
        {
            _data[_offset++] = v & 0xFF;
            _data[_offset++] = (v >> 8) & 0xFF;
            _data[_offset++] = (v >> 16) & 0xFF;
            _data[_offset++] = (v >> 24) & 0xFF;
        }
        else
        {
            _data[_offset++] = (v >> 24) & 0xFF;
            _data[_offset++] = (v >> 16) & 0xFF;
            _data[_offset++] = (v >> 8) & 0xFF;
            _data[_offset++] = v & 0xFF;
        }

        return this;
    }

    final override IbWriteBuffer writeUInt64(uint64 v) nothrow
    {
        version (BigEndian)
        static if (EndianKind == Endian.littleEndian)
            v = swapEndian(v);

        reserve(uint64.sizeof);

        static if (EndianKind == Endian.littleEndian)
        {
            _data[_offset++] = v & 0xFF;
            _data[_offset++] = (v >> 8) & 0xFF;
            _data[_offset++] = (v >> 16) & 0xFF;
            _data[_offset++] = (v >> 24) & 0xFF;
            _data[_offset++] = (v >> 32) & 0xFF;
            _data[_offset++] = (v >> 40) & 0xFF;
            _data[_offset++] = (v >> 48) & 0xFF;
            _data[_offset++] = (v >> 56) & 0xFF;
        }
        else
        {
            _data[_offset++] = (v >> 56) & 0xFF;
            _data[_offset++] = (v >> 48) & 0xFF;
            _data[_offset++] = (v >> 40) & 0xFF;
            _data[_offset++] = (v >> 32) & 0xFF;
            _data[_offset++] = (v >> 24) & 0xFF;
            _data[_offset++] = (v >> 16) & 0xFF;
            _data[_offset++] = (v >> 8) & 0xFF;
            _data[_offset++] = v & 0xFF;
        }

        return this;
    }

    @property final override bool empty() const nothrow @safe
    {
        return _offset == 0;
    }

    pragma(inline, true)
    @property final override size_t length() const nothrow @safe
    {
        return _offset;
    }

    pragma(inline, true)
    @property final size_t offset() const nothrow
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

    final IbWriteBuffer writeBytesImpl(scope const(ubyte)[] v) nothrow
    {
        const nBytes = v.length;
        if (nBytes)
        {
            reserve(nBytes);

            _data[_offset.._offset + nBytes] = v[];
            _offset += nBytes;
        }

        return this;
    }
}


// Any below codes are private
private:


unittest // DbWriteBuffer & DbReadBuffer
{
    import pham.utl.utltest;
    traceUnitTest("unittest db.buffer.DbWriteBuffer & db.buffer.DbReadBuffer");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writer = new DbWriteBuffer!(Endian.littleEndian)(4000);
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

    ubyte[] bytes = writer.peekBytes().dup;
    writer.dispose();
    writer = null;

    auto reader = new DbReadBuffer!(Endian.littleEndian)(bytes);
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
    reader.dispose();
    reader = null;
}
