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
import pham.utl.array : inplaceMoveToLeft;
import pham.utl.bit_array : numericBitCast;
import pham.utl.dlink_list;
import pham.utl.disposable : DisposingReason;
import pham.utl.object : alignRoundup;
import pham.db.convert;
import pham.db.exception;
import pham.db.message;
import pham.db.object;
import pham.db.type;

@safe:

// Network byte order is BigEndian

class DbBuffer : DbDisposableObject
{
@safe:

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _data = null;
        _offset = 0;
        _next = null;
        _prev = null;
    }

protected:
    enum size_t dataSizeAlignment = 128;
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

    final ubyte[] consumeAll()
    {
        return consume(length);
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
                throw new DbException(msg, DbErrorCode.read, null);
            }
        }
    }

    pragma(inline, true)
    final void ensureAvailableIf(const(size_t) nBytes)
    {
        if (length < nBytes)
            ensureAvailable(nBytes);
    }

    final ubyte[] expand(const(size_t) nBytes) nothrow
    {
        reserve(nBytes);
        const bLength = length;
        const endOffset = _offset + bLength;
        _maxLength += nBytes;
        return _data[endOffset..endOffset + nBytes];
    }

    void fill(const(size_t) additionalBytes, bool mustSatisfied)
    {}

    final void fill(ubyte[] additionalBytes) nothrow
    {
        const nBytes = additionalBytes.length;
        reserve(nBytes);
        const endOffset = _offset + length;
        _maxLength += nBytes;
        _data[endOffset..endOffset + nBytes] = additionalBytes[0..$];
    }

    final ubyte[] peekBytes(size_t forLength = size_t.max) nothrow pure
    {
        const bLength = this.length;
        if (forLength > bLength)
            forLength = bLength;
        return _data[_offset.._offset + forLength];
    }

    final DbReadBuffer reset() nothrow pure
    {
        _offset = _maxLength = 0;
        return this;
    }

    /** Return n bytes if searchedByte found, 0 otherwise
     */
    final size_t search(const(ubyte) searchedByte) nothrow pure
    {
        size_t endOffset = _offset;
        while (endOffset < _maxLength)
        {
            if (_data[endOffset++] == searchedByte)
                return endOffset - _offset;
        }
        return 0;
    }

    /** Return n bytes if searchedByte1 or searchedByte2 found, 0 otherwise
     */
    final size_t search(const(ubyte) searchedByte1, const(ubyte) searchedByte2) nothrow pure
    {
        size_t endOffset = _offset;
        while (endOffset < _maxLength)
        {
            const b = _data[endOffset++];
            if (b == searchedByte1 || b == searchedByte2)
                return endOffset - _offset;
        }
        return 0;
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
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _maxLength = 0;
        super.doDispose(disposingReason);
    }

    final void mergeOffset() nothrow
    in
    {
        assert(_offset != 0);
    }
    do
    {
        //import pham.utl.test; dgWriteln("offset=", _offset, ", length=", length, ", _data.length=", _data.length);

        const saveLength = length;
        if (saveLength != 0)
            inplaceMoveToLeft(_data, _offset, 0, saveLength);
        _offset = 0;
        _maxLength = saveLength;
    }

    final ubyte[] readBytesImpl(const(size_t) nBytes)
    {
        ubyte[] result = new ubyte[nBytes];
        return readBytesImpl(result);
    }

    final ubyte[] readBytesImpl(return ubyte[] value)
    {
        const nBytes = value.length;
        ensureAvailableIf(nBytes);

        value[0..nBytes] = _data[_offset.._offset + nBytes];
        _offset += nBytes;
        return value;
    }

    final void reserve(const(size_t) additionalBytes) nothrow @trusted
    {
        const curLength = length;
        if (_data.length < (_offset + curLength + additionalBytes))
        {
            _data.length = alignRoundup((_offset << 1) + curLength + additionalBytes, dataSizeAlignment);
            _data.assumeSafeAppend();
        }
    }

protected:
    size_t _maxLength;
}

version (TraceFunctionReader)
{
    private static long totalRead = 0;
    private long totalReadOf(const(size_t) nBytes) @nogc nothrow @safe
    {
        totalRead += nBytes;
        return totalRead;
    }
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

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        _buffer = null;
    }

    pragma(inline, true)
    void advance(const(size_t) nBytes)
    {
        version (TraceFunctionReader) debug traceFunction(nBytes, ", total=", totalReadOf(nBytes));

        _buffer.advance(nBytes);
    }

    pragma(inline, true)
    ubyte[] consume(const(size_t) nBytes)
    {
        version (TraceFunctionReader) debug traceFunction(nBytes, ", total=", totalReadOf(nBytes));

        return _buffer.consume(nBytes);
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
        version (TraceFunctionReader) debug traceFunction(nBytes, ", total=", totalReadOf(nBytes));

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
        version (TraceFunctionReader) debug traceFunction(value.length, ", total=", totalReadOf(value.length));

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
        version (TraceFunctionReader) debug traceFunction(nBytes, ", total=", totalReadOf(nBytes));

        return cast(char[])_buffer.readBytesImpl(nBytes);
    }

    pragma(inline, true)
    float32 readFloat32() @trusted
    {
        return numericBitCast!float32(readUInt32());
    }

    pragma(inline, true)
    float64 readFloat64() @trusted
    {
        return numericBitCast!float64(readUInt64());
    }

    pragma(inline, true)
    int8 readInt8()
    {
        return numericBitCast!int8(readUInt8());
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return numericBitCast!int16(readUInt16());
    }

    pragma(inline, true)
    int32 readInt32()
    {
        return numericBitCast!int32(readUInt32());
    }

    void readTwoInt32(out int32 i1, out int32 i2)
    {
        version (TraceFunctionReader) debug traceFunction(uint32.sizeof * 2, ", total=", totalReadOf(uint32.sizeof * 2));

        const bytes = _buffer.consume(uint32.sizeof * 2);
        i1 = cast(int32)uintDecode!(uint32, EndianKind)(bytes[0..uint32.sizeof]);
        i2 = cast(int32)uintDecode!(uint32, EndianKind)(bytes[uint32.sizeof..$]);
    }

    pragma(inline, true)
    int64 readInt64()
    {
        return numericBitCast!int64(readUInt64());
    }

    uint8 readUInt8()
    {
        version (TraceFunctionReader) debug traceFunction(uint8.sizeof, ", total=", totalReadOf(uint8.sizeof));

        _buffer.ensureAvailableIf(uint8.sizeof);
        return _buffer._data[_buffer._offset++];
    }

    uint16 readUInt16()
    {
        version (TraceFunctionReader) debug traceFunction(uint16.sizeof, ", total=", totalReadOf(uint16.sizeof));

        const bytes = _buffer.consume(uint16.sizeof);
        return uintDecode!(uint16, EndianKind)(bytes);
    }

    uint32 readUInt32()
    {
        version (TraceFunctionReader) debug traceFunction(uint32.sizeof, ", total=", totalReadOf(uint32.sizeof));

        const bytes = _buffer.consume(uint32.sizeof);
        return uintDecode!(uint32, EndianKind)(bytes);
    }

    uint64 readUInt64()
    {
        version (TraceFunctionReader) debug traceFunction(uint64.sizeof, ", total=", totalReadOf(uint64.sizeof));

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

    final ubyte[] peekBytes() nothrow
    {
        return _data[0..length];
    }

    DbWriteBuffer reset() nothrow
    {
        _offset = 0;
        return this;
    }

    version (TraceFunction)
    final string traceString() const nothrow @trusted
    {
        import std.conv : to;
        import pham.utl.object : bytesToHexs;

        const bytes = _data[0..length];
        return "length=" ~ to!string(bytes.length)
            ~ ", data=" ~ cast(string)bytesToHexs(bytes);
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
            _data.length = alignRoundup((_offset << 1) + additionalBytes, dataSizeAlignment);
            _data.assumeSafeAppend();
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

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
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

    void rewriteUInt32(uint32 v, size_t rewriteOffset) nothrow
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

        writeUInt32(v);
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
        writeUInt32(numericBitCast!uint32(v));
    }

    pragma(inline, true)
    void writeFloat64(float64 v) nothrow @trusted
    {
        writeUInt64(numericBitCast!uint64(v));
    }

    pragma(inline, true)
    void writeInt8(int8 v) nothrow
    {
        writeUInt8(numericBitCast!uint8(v));
    }

    pragma(inline, true)
    void writeInt16(int16 v) nothrow
    {
        writeUInt16(numericBitCast!uint16(v));
    }

    pragma(inline, true)
    void writeInt32(int32 v) nothrow
    {
        writeUInt32(numericBitCast!uint32(v));
    }

    pragma(inline, true)
    static if (size_t.sizeof > int32.sizeof)
    void writeInt32(size_t v) nothrow
    in
    {
        assert(v <= int32.max);
    }
    do
    {
        writeInt32(cast(int32)v);
    }

    pragma(inline, true)
    void writeInt64(int64 v) nothrow
    {
        writeUInt64(numericBitCast!uint64(v));
    }

    void writeUInt8(uint8 v) nothrow
    {
        _buffer.reserve(uint8.sizeof);
        _buffer._data[_buffer._offset++] = v;
    }

    pragma(inline, true)
    void writeUInt8(size_t v) nothrow
    in
    {
        assert(v <= uint8.max);
    }
    do
    {
        writeUInt8(cast(uint8)v);
    }

    void writeUInt16(uint16 v) nothrow
    {
        auto bytes = uintEncode!(uint16, EndianKind)(v);
        _buffer.writeBytesImpl(bytes[]);
    }

    pragma(inline, true)
    void writeUInt16(size_t v) nothrow
    in
    {
        assert(v <= uint16.max);
    }
    do
    {
        writeUInt16(cast(uint16)v);
    }

    void writeUInt32(uint32 v) nothrow
    {
        auto bytes = uintEncode!(uint32, EndianKind)(v);
        _buffer.writeBytesImpl(bytes[]);
    }

    pragma(inline, true)
    static if (size_t.sizeof > uint32.sizeof)
    void writeUInt32(size_t v) nothrow
    in
    {
        assert(v <= uint32.max);
    }
    do
    {
        writeUInt32(cast(uint32)v);
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
