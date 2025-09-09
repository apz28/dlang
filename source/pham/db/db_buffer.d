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

module pham.db.db_buffer;

import std.bitmanip : swapEndian;
import std.string : representation;
import std.system : Endian;
import std.traits : isIntegral, isUnsigned;

version(profile) import pham.utl.utl_test : PerfFunction;
debug(debug_pham_db_db_buffer) import pham.db.db_debug;
import pham.utl.utl_array : inplaceMoveToLeft;
import pham.utl.utl_bit : numericBitCast;
import pham.utl.utl_dlink_list;
import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_object : alignRoundup;
import pham.utl.utl_trait : UnsignedTypeOf;
import pham.db.db_convert;
import pham.db.db_exception;
import pham.db.db_message;
import pham.db.db_object;
import pham.db.db_type;

@safe:

enum DbBufferOwner : ubyte
{
    none,
    acquired,
    owned,
}

// Network byte order is BigEndian

class DbBuffer : DbDisposableObject
{
@safe:

public:
    enum cachedCapacityLimit = 1024 * 1024;

    final bool isOverCachedCapacityLimit() const nothrow pure
    {
        return capacity > cachedCapacityLimit;
    }

    pragma(inline, true)
    @property final size_t capacity() const nothrow pure
    {
        return _data.length;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _data = null;
        _offset = 0;
        _next = _prev = null;
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

/**
 * A delegate to save blob/clob data from database server
 * Params:
 *  savedLength = an accumulated length in bytes that saved so far
 *  requestedLength = the length that caller asked for
 *  data = set to ubyte array that contains the data to be received
 * Returns:
 *  0=continue saving, non-zero=stop saving
 */
alias DbSaveBufferData = int delegate(int64 savedLength, int64 requestedLength, scope const(ubyte)[] data) @safe;

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

    final ubyte consume()
    {
        if (length == 0)
            ensureAvailable(1);

        return _data[_offset++];
    }

    final ubyte[] consume(const(size_t) nBytes) scope
    {
        if (length < nBytes)
            ensureAvailable(nBytes);

        const endOffset = _offset + nBytes;
        auto result = _data[_offset..endOffset];
        _offset = endOffset;
        return result;
    }

    final ubyte[] consumeAll() scope
    {
        return consume(length);
    }

    final size_t ensureAvailable(const(size_t) nBytes) @trusted
    {
        version(profile) debug auto p = PerfFunction.create();

        const endLength = _offset + nBytes;
        if (endLength > _maxLength)
        {
            fill(nBytes, endLength - _maxLength);
            if ((_offset + nBytes) > _maxLength)
                noReadingDataRemainingError(nBytes, length);
        }
        return length;
    }

    pragma(inline, true)
    final size_t ensureAvailableIf(const(size_t) nBytes)
    {
        version(profile) debug auto p = PerfFunction.create();

        if ((_offset + nBytes) > _maxLength)
            fill(nBytes, 0);
        return length;
    }

    final ubyte[] expand(const(size_t) nBytes) nothrow
    {
        reserve(nBytes);
        const bLength = length;
        const endOffset = _offset + bLength;
        _maxLength += nBytes;
        return _data[endOffset..endOffset + nBytes];
    }

    void fill(const(size_t) additionalBytes, const(size_t) mustSatisfiedBytes)
    {}

    final void fill(scope ubyte[] additionalBytes) nothrow
    {
        const nBytes = additionalBytes.length;
        reserve(nBytes);
        const endOffset = _offset + length;
        _maxLength += nBytes;
        _data[endOffset..endOffset + nBytes] = additionalBytes[0..$];
    }

    final ubyte[] peekBytes(size_t forLength = size_t.max) nothrow pure scope
    {
        const bLength = this.length;
        return forLength > bLength
            ? _data[_offset.._offset + bLength]
            : _data[_offset.._offset + forLength];
    }

    final ubyte[] readBytes(const(size_t) nBytes)
    {
        auto result = new ubyte[](nBytes);
        return readBytes(result);
    }

    final ubyte[] readBytes(return ubyte[] value)
    {
        const nBytes = value.length;
        ensureAvailable(nBytes);

        value[0..nBytes] = _data[_offset.._offset + nBytes];
        _offset += nBytes;
        return value;
    }

    final int64 readBytes(const(int64) nBytes, DbSaveBufferData saveBufferData, const(size_t) segmentLength)
    in
    {
        assert(saveBufferData !is null);
        assert(segmentLength != 0);
    }
    do
    {
        int64 result;
        if (nBytes > 0)
        {
            while (result < nBytes)
            {
                const leftLength = nBytes - result;

                const dataLength = ensureAvailable(leftLength >= segmentLength ? segmentLength : cast(size_t)leftLength);
                if (dataLength == 0)
                    return result;

                if (saveBufferData(result, nBytes, consume(dataLength)))
                    return result + dataLength;

                result += dataLength;
            }
        }
        else
        {
            while (true)
            {
                const dataLength = ensureAvailableIf(segmentLength);
                if (dataLength == 0)
                    return result;

                if (saveBufferData(result, nBytes, consume(dataLength)))
                    return result + dataLength;

                result += dataLength;
            }
        }
        return result;
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
        return _offset < _maxLength ? (_maxLength - _offset) : 0;
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
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(offset=", _offset, ", length=", length, ", _data.length=", _data.length, ")");

        const saveLength = length;
        if (saveLength != 0)
            inplaceMoveToLeft(_data, _offset, 0, saveLength);
        _offset = 0;
        _maxLength = saveLength;
    }

    noreturn noReadingDataRemainingError(const(size_t) requiredBytes, const(size_t) availableBytes) @safe
    {
        assert(requiredBytes > availableBytes);
        //assert(connection.availableBytes() <= 0);

        auto msg = DbMessage.eNoReadingDataRemaining.fmtMessage(requiredBytes, availableBytes);
        throw new DbException(DbErrorCode.read, msg);
    }

    final void reserve(const(size_t) additionalBytes) nothrow @trusted // @trusted for assumeSafeAppend
    {
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(offset=", _offset, ", length=", length, ", additionalBytes=", additionalBytes, ", _data.length=", _data.length, ")");

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

debug(debug_pham_db_db_buffer)
{
    private static long totalRead = 0;
    private long totalReadOf(const(size_t) nBytes) @nogc nothrow @safe
    {
        totalRead += nBytes;
        return totalRead;
    }
}

struct DbValueReader(Endian endianKind)
{
@safe:

public:
    @disable this(this);
    //@disable void opAssign(typeof(this)); // To allow construct and set to an "out" var

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
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(nBytes=", nBytes, ", total=", totalReadOf(nBytes), ")");

        _buffer.advance(nBytes);
    }

    pragma(inline, true)
    ubyte[] consume(const(size_t) nBytes)
    {
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(nBytes=", nBytes, ", total=", totalReadOf(nBytes), ")");

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
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(nBytes=", nBytes, ", total=", totalReadOf(nBytes), ")");

        return _buffer.readBytes(nBytes);
    }

    pragma(inline, true)
    ubyte[] readBytes(return ubyte[] value)
    in
    {
        assert(value.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(value.length=", value.length, ", total=", totalReadOf(value.length), ")");

        return _buffer.readBytes(value);
    }

    pragma(inline, true)
    int64 readBytes(int64 nBytes, DbSaveBufferData saveBufferData, size_t segmentLength)
    in
    {
        assert(saveBufferData !is null);
        assert(segmentLength != 0);
    }
    do
    {
        return _buffer.readBytes(nBytes, saveBufferData, segmentLength);
    }

    pragma(inline, true)
    char readChar()
    {
        return cast(char)readUInt8();
    }

    pragma(inline, true)
    char[] readChars(size_t nBytes) @trusted // @trusted=cast()
    {
        debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(nBytes=", nBytes, ", total=", totalReadOf(nBytes), ")");

        return cast(char[])_buffer.readBytes(nBytes);
    }

    pragma(inline, true)
    int64 readChars(int64 nBytes, DbSaveBufferData saveBufferData, size_t segmentLength)
    in
    {
        assert(saveBufferData !is null);
        assert(segmentLength != 0);
    }
    do
    {
        return _buffer.readBytes(nBytes, saveBufferData, segmentLength);
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

    pragma(inline, true)
    int64 readInt64()
    {
        return numericBitCast!int64(readUInt64());
    }

    uint8 readUInt8()
    {
        //debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(", uint8.sizeof, ", total=", totalReadOf(uint8.sizeof), ")");

        return _buffer.consume();
    }

    uint16 readUInt16()
    {
        //debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(", uint16.sizeof, ", total=", totalReadOf(uint16.sizeof), ")");

        const bytes = _buffer.consume(uint16.sizeof);
        return unsignedDecode!(uint16, endianKind)(bytes);
    }

    uint32 readUInt32()
    {
        //debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(", uint32.sizeof, ", total=", totalReadOf(uint32.sizeof), ")");

        const bytes = _buffer.consume(uint32.sizeof);
        return unsignedDecode!(uint32, endianKind)(bytes);
    }

    uint64 readUInt64()
    {
        //debug(debug_pham_db_db_buffer) debug writeln(__FUNCTION__, "(", uint64.sizeof, ", total=", totalReadOf(uint64.sizeof), ")");

        const bytes = _buffer.consume(uint64.sizeof);
        return unsignedDecode!(uint64, endianKind)(bytes);
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

    final string traceString() const nothrow @trusted
    {
        import std.conv : to;
        import pham.utl.utl_convert : bytesToHexs;

        const bytes = _data[0..length];
        return "length=" ~ bytes.length.to!string()
            ~ ", data=" ~ cast(string)bytes.bytesToHexs();
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

struct DbValueWriter(Endian endianKind)
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(DbWriteBuffer buffer) nothrow pure
    {
        this._buffer = buffer;
    }

    pragma(inline, true)
    static auto asBytes(T)(T v) @nogc nothrow pure
    if (isIntegral!T)
    {
        alias UT = UnsignedTypeOf!T;
        static if (isUnsigned!T)
            return unsignedEncode!(UT, endianKind)(v);
        else
            return unsignedEncode!(UT, endianKind)(numericBitCast!UT(v));
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
        const bytes = asBytes(v);
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
        const bytes = asBytes(v);
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
        const bytes = asBytes(v);
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
