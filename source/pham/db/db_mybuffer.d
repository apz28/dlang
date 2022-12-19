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

import std.conv : to;
import std.format : FormatSpec, formatValue;
import std.string : representation;
import std.system : Endian;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.bit_array : numericBitCast;
import pham.utl.object : simpleFloatFmt, simpleIntegerFmt;
import pham.utl.utf8 : ShortStringBuffer, ShortStringBufferSize;
import pham.db.buffer;
import pham.db.message;
import pham.db.type;
import pham.db.myconvert;
import pham.db.mydatabase;
import pham.db.myexception;
import pham.db.myoid;
import pham.db.mytype;

@safe:

struct MyReader
{
@safe:

public:
    this(MyConnection connection)
    {
        this._connection = connection;
        this.readPacketData(connection);
    }

    this(ubyte[] packetData) nothrow
    in
    {
        assert(packetData.length < int32.max);
    }
    do
    {
        this._connection = null;
        this.sequenceByte = 0;
        this._packetLength = cast(int32)packetData.length;
        this._buffer = new DbReadBuffer(packetData);
    }

    void dispose(bool disposing = true)
    {
        if (_buffer !is null && _connection !is null)
            _connection.releasePackageReadBuffer(_buffer);

        _buffer = null;
        _connection = null;
    }

    bool isAuthSha2Caching(string authMethod) nothrow pure
    {
        return _buffer.length && _buffer.peekBytes(1)[0] == 0x01 && authMethod == myAuthSha2Caching;
    }

    pragma(inline, true)
    bool isAuthSwitch() nothrow pure
    {
        return _buffer.length && _buffer.peekBytes(1)[0] == MyPackageType.eof;
    }

    pragma(inline, true)
    bool isError() nothrow pure
    {
        return _buffer.length && _buffer.peekBytes(1)[0] == MyPackageType.error;
    }

    alias isEOF = isLastPacket;

    pragma(inline, true)
    bool isLastPacket() nothrow pure
    {
        return _packetLength <= 5 && _buffer.length && _buffer.peekBytes(1)[0] == MyPackageType.eof;
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

    pragma(inline, true)
    @property int32 packetLength() const nothrow pure
    {
        return _packetLength;
    }

public:
    int32 maxBlockSize = int32.max / 2;
    int32 maxPacketSize = int32.max;
    ubyte sequenceByte;

private:
    void readPacketData(MyConnection connection)
    {
        this.sequenceByte = 0;
        auto socketBuffer = connection.acquireSocketReadBuffer();
        auto socketReader = DbValueReader!(Endian.littleEndian)(socketBuffer);
        this._buffer = connection.acquirePackageReadBuffer();
        auto blockBuffer = connection.acquirePackageReadBuffer();
        scope (exit)
            connection.releasePackageReadBuffer(blockBuffer);
        while (true)
        {
            MyBlockHeader blockHeader;
            blockHeader.a = socketReader.consume(4);
            size_t blockSize = void;
            blockHeaderDecode(blockHeader, blockSize, sequenceByte);

            version (TraceFunction) traceFunction!("pham.db.mydatabase")("blockSize=", blockSize, ", sequenceByte=", sequenceByte, ", blockHeader=", blockHeader.a[].dgToHex());

            if (blockSize)
            {
                auto bufferData = blockBuffer.reset().expand(blockSize);
                auto readData = socketReader.readBytes(bufferData);
                this._buffer.fill(readData);
            }

            // if this block was < maxBlockSize then it's last one in a multi-packet series
            if (blockSize < maxBlockSize)
                break;
        }
        this._packetLength = cast(int32)this._buffer.length;

        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_packetLength=", _packetLength, ", buffer=", this._buffer.peekBytes(200).dgToHex());
    }

private:
    DbReadBuffer _buffer;
    MyConnection _connection;
    int32 _packetLength;
}

struct MyXdrReader
{
@safe:

public:
    @disable this(this);

    this(MyConnection connection, DbReadBuffer buffer)
    {
        this._connection = connection;
        this._buffer = buffer;
        this._reader = DbValueReader!(Endian.littleEndian)(buffer);
    }

    pragma(inline, true)
    void advance(size_t nBytes)
    {
        _buffer.advance(nBytes);
    }

    void dispose(bool disposing = true)
    {
        _buffer = null;
        _connection = null;
        _reader.dispose(disposing);
    }

    pragma(inline, true)
    uint64 readBit()
    {
        return readUInt64!8();
    }

    pragma(inline, true)
    bool readBoolValue(const(bool) readFieldLength)
    {
        return readInt8Value(readFieldLength) != 0;
    }

    pragma(inline, true)
    ubyte[] readBytes()
    {
        const len = readLength();
        return readBytes(cast(int32)len);
    }

    pragma(inline, true)
    ubyte[] readBytes(const(int32) nBytes)
    {
        return nBytes > 0 ? _reader.readBytes(cast(size_t)nBytes) : null;
    }

    pragma(inline, true)
    ubyte[] readBytesValue(const(bool) readFieldLength)
    {
        const len = readLength();
        return readBytes(cast(int32)len);
    }

    pragma(inline, true)
    ubyte[] readCBytes()
    {
        auto result = _reader.readBytes(_buffer.search(0, 0xFF));
        return result.length ? result[0..$ - 1] : null; // -1=excluded terminated byte
    }

    char[] readCChars(bool allIfNotTerminated = false)
    {
        auto len = _buffer.search(0, 0xFF);
        if (len == 0 && allIfNotTerminated)
            len = _buffer.length;
        auto result = _reader.readChars(len);
        // excluded terminated char ?
        while (result.length && result[$ - 1] == '\0')
            result = result[0..$ - 1];
        return result;
    }

    pragma(inline, true)
    string readCString(bool allIfNotTerminated = false) @trusted // @trusted=cast()
    {
        return cast(string)readCChars(allIfNotTerminated);
    }

    DbDate readDateValue(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        if (len == -1)
        {
            const nBytes = cast(size_t)readUInt8();
            const bytes = consumeBytes(nBytes);
            return bytes.length != 0 ? dateDecode(bytes) : DbDate.zero;
        }
        else
        {
            if (len <= 0)
                return DbDate.zero;

            auto s = consumeChars(len);
            DbDate result;
            if (dateDecodeString(s, result))
                return result;

            auto msg = DbMessage.eReadInvalidData.fmtMessage(s, "DbDate");
            throw new MyException(msg, DbErrorCode.read, null);
        }
    }

    DbDateTime readDateTimeValue(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        if (len == -1)
        {
            const nBytes = cast(size_t)readUInt8();
            const bytes = consumeBytes(nBytes);
            return bytes.length != 0 ? dateTimeDecode(bytes) : DbDateTime.zero;
        }
        else
        {
            if (len <= 0)
                return DbDateTime.zero;

            auto s = consumeChars(len);
            DbDateTime result;
            if (dateTimeDecodeString(s, result))
                return result;

            auto msg = DbMessage.eReadInvalidData.fmtMessage(s, "DbDateTime");
            throw new MyException(msg, DbErrorCode.read, null);
        }
    }

    D readDecimalValue(D)(const(bool) readFieldLength)
    if (isDecimal!D)
    {
        const len = readLength();
        return len > 0 ? D(consumeChars(len), RoundingMode.banking) : D(0);
    }

    MyErrorResult readError()
    {
        _buffer.advance(1); // Skip error indicator

        MyErrorResult result;
        result.code = readInt16();
        result.message = readCString(true);

        // Start with SQL_STATE?
        if (result.message.length >= 6 && result.message[0] == '#')
        {
            enum offset = 1; //result.message[0] == '#' ? 1 : 0;
            result.sqlState = result.message[offset..5 + offset];
            result.message = result.message[offset + 5..$];
        }

        return result;
    }

    float32 readFloat32Value(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        return len == -1
            ? numericBitCast!float32(readUInt32!4())
            : (len > 0 ? to!float32(consumeChars(len)) : 0);
    }

    float64 readFloat64Value(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        return len == -1
            ? numericBitCast!float64(readUInt64!8())
            : (len > 0 ? to!float64(consumeChars(len)) : 0);
    }

    MyGeometry readGeometryValue(const(bool) readFieldLength)
    {
        const len = readLength();
        return len > 0 ? geometryDecode(consumeBytes(len)) : MyGeometry.init;
    }

    pragma(inline, true)
    int8 readInt8() // TINYINT
    {
        return _reader.readInt8();
    }

    int8 readInt8Value(const(bool) readFieldLength) // TINYINT
    {
        const len = readFieldLength ? readLength() : -1;
        return len == -1
            ? _reader.readInt8()
            : (len > 0 ? to!int8(consumeChars(len)) : 0);
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return numericBitCast!int16(readUInt16());
    }

    int16 readInt16Value(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        return len == -1
            ? readInt16()
            : (len > 0 ? to!int16(consumeChars(len)) : 0);
    }

    pragma(inline, true)
    int32 readInt24()
    {
        return numericBitCast!int32(readUInt32!3());
    }

    pragma(inline, true)
    int32 readInt32()
    {
        return numericBitCast!int32(readUInt32!4());
    }

    int32 readInt32Value(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        return len == -1
            ? readInt32()
            : (len > 0 ? to!int32(consumeChars(len)) : 0);
    }

    pragma(inline, true)
    int64 readInt64()
    {
        return numericBitCast!int64(readUInt64!8());
    }

    int64 readInt64Value(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        return len == -1
            ? readInt64()
            : (len > 0 ? to!int64(consumeChars(len)) : 0);
    }

    pragma(inline, true)
    int64 readLength()
    {
        return readPackedInt64();
    }

    int32 readPackedInt32()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.negOne: return -1;
            case MyPackedIntegerIndicator.twoByte: return numericBitCast!int32(readUInt32!2());
            case MyPackedIntegerIndicator.threeByte: return numericBitCast!int32(readUInt32!3());
            case MyPackedIntegerIndicator.fourOrEightByte: return numericBitCast!int32(readUInt32!4());
            default: return cast(int32)c;
        }
    }

    int64 readPackedInt64()
    {
        const c = readUInt8();

        version (TraceFunction) traceFunction!("pham.db.mydatabase")("readPackedInt64.c=", c);

        switch (c)
        {
            case MyPackedIntegerIndicator.negOne: return -1L;
            case MyPackedIntegerIndicator.twoByte: return numericBitCast!int64(readUInt64!2());
            case MyPackedIntegerIndicator.threeByte: return numericBitCast!int64(readUInt64!3());
            case MyPackedIntegerIndicator.fourOrEightByte: return numericBitCast!int64(readUInt64!8());
            default: return cast(int64)c;
        }
    }

    uint32 readPackedUInt32()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.twoByte: return readUInt32!2();
            case MyPackedIntegerIndicator.threeByte: return readUInt32!3();
            case MyPackedIntegerIndicator.fourOrEightByte: return readUInt32!4();
            default: return cast(uint32)c;
        }
    }

    uint64 readPackedUInt64()
    {
        const c = readUInt8();
        switch (c)
        {
            case MyPackedIntegerIndicator.twoByte: return readUInt64!2();
            case MyPackedIntegerIndicator.threeByte: return readUInt64!3();
            case MyPackedIntegerIndicator.fourOrEightByte: return readUInt64!8();
            default: return cast(uint64)c;
        }
    }

    pragma(inline, true)
    string readShortString()
    {
        const len = readInt8();
        return readString(len);
    }

    pragma(inline, true)
    string readString() @trusted
    {
        return cast(string)readBytes();
    }

    pragma(inline, true)
    string readString(const(int32) len) @trusted
    {
        return cast(string)readBytes(len);
    }

    pragma(inline, true)
    string readStringValue(const(bool) readFieldLength) @trusted
    {
        return cast(string)readBytesValue(readFieldLength);
    }

    DbTime readTimeValue(const(bool) readFieldLength)
    {
        auto ts = readTimeSpanValue(readFieldLength);
        return DbTime(ts.time);
    }

    DbTimeSpan readTimeSpanValue(const(bool) readFieldLength)
    {
        const len = readFieldLength ? readLength() : -1;
        if (len == -1)
        {
            const nBytes = cast(size_t)readUInt8();
            const bytes = consumeBytes(nBytes);
            return bytes.length != 0 ? timeSpanDecode(bytes) : DbTimeSpan.zero;
        }
        else
        {
            if (len <= 0)
                return DbTimeSpan.zero;

            auto s = consumeChars(len);
            DbTimeSpan result;
            if (timeSpanDecodeString(s, result))
                return result;

            auto msg = DbMessage.eReadInvalidData.fmtMessage(s, "DbTimeSpan");
            throw new MyException(msg, DbErrorCode.read, null);
        }
    }

    pragma(inline, true)
    uint8 readUInt8()
    {
        return _reader.readUInt8();
    }

    pragma(inline, true)
    uint16 readUInt16()
    {
        return cast(uint16)readUInt32!2();
    }

    pragma(inline, true)
    uint32 readUInt24()
    {
        return readUInt32!3();
    }

    pragma(inline, true)
    uint32 readUInt32()
    {
        return readUInt32!4();
    }

    // This is optimized for 32 bits build to avoid value return on stack
    // if use readUInt64
    pragma(inline, true)
    uint32 readUInt32(uint8 NBytes)()
    if (NBytes == 2 || NBytes == 3 || NBytes == 4)
    {
        auto bytes = _buffer.consume(NBytes);
        return uintDecode!uint32(bytes);
    }

    pragma(inline, true)
    uint64 readUInt64()
    {
        return readUInt64!8();
    }

    pragma(inline, true)
    uint64 readUInt64(uint8 NBytes)()
    if (NBytes == 2 || NBytes == 3 || NBytes == 8)
    do
    {
        auto bytes = _buffer.consume(NBytes);
        return uintDecode!uint64(bytes);
    }

    // "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    UUID readUUIDValue(const(bool) readFieldLength)
    {
        const len = readLength();
        return len > 0 ? UUID(consumeChars(len)) : UUID.init;
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
    pragma(inline, true)
    ubyte[] consumeBytes(const(size_t) len)
    {
        return len != 0 ? _buffer.consume(len) : null;
    }

    pragma(inline, true)
    ubyte[] consumeBytes(const(int64) len)
    {
        return len > 0 ? _buffer.consume(cast(size_t)(cast(int32)len)) : null;
    }

    pragma(inline, true)
    char[] consumeChars(const(int64) len) @trusted
    {
        auto result = cast(char[])consumeBytes(len);

        version (TraceFunction) traceFunction!("pham.db.mydatabase")("consumeChars=", result);

        return result;
    }

private:
    DbReadBuffer _buffer;
    MyConnection _connection;
    DbValueReader!(Endian.littleEndian) _reader;
}

struct MyXdrWriter
{
@safe:

public:
    @disable this(this);

    this(MyConnection connection, uint maxSinglePackage) nothrow
    {
        this._socketBuffer = true;
        this._reserveLenghtOffset = -1;
        this._maxSinglePackage = maxSinglePackage;
        this._connection = connection;
        this._buffer = connection.acquireSocketWriteBuffer();
        this._writer = DbValueWriter!(Endian.littleEndian)(this._buffer);
    }

    this(MyConnection connection, uint maxSinglePackage, DbWriteBuffer buffer) nothrow
    {
        buffer.reset();
        this._socketBuffer = false;
        this._reserveLenghtOffset = -1;
        this._maxSinglePackage = maxSinglePackage;
        this._connection = connection;
        this._buffer = buffer;
        this._writer = DbValueWriter!(Endian.littleEndian)(buffer);
    }

    ~this()
    {
        dispose(false);
    }

    void beginPackage(ubyte sequenceByte) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")(traceString(sequenceByte));

        this._sequenceByte = sequenceByte;
        this._reserveLenghtOffset = _buffer.offset;
        this._writer.writeUInt32(0);
    }

    void dispose(bool disposing = true)
    {
        _writer.dispose(disposing);
        if (_socketBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);
        _buffer = null;
        _connection = null;
    }

    pragma(inline, true)
    void endPackage() nothrow
    {
        writePackageLength();
    }

    void flush()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_buffer.length=", _buffer.length);

        writePackageLength();
        _buffer.flush();
    }

    pragma(inline, true)
    ubyte[] peekBytes() nothrow
    {
        return _buffer.peekBytes();
    }

    version (TraceFunction)
    string traceString(ubyte sequenceByte) const nothrow pure @trusted
    {
        import std.conv : to;

        return "_buffer.offset=" ~ to!string(_buffer.offset)
            ~ ", sequenceByte=" ~ to!string(sequenceByte);
    }

    pragma(inline, true)
    void writeBit(uint64 v) nothrow
    {
        writeUInt64!8(v);
    }

    void writeBool(bool v) nothrow
    {
        _writer.writeUInt8(1);
        _writer.writeUInt8(v ? 0x31 : 0x30);
    }

    pragma(inline, true)
    void writeBytes(scope const(ubyte)[] v) nothrow
    {
        writeLength(v.length);
        if (v.length)
            _writer.writeBytes(v);
    }

    void writeBytesString(scope const(ubyte)[] v) nothrow
    {
        writeOpaqueChars("_binary ");
        _writer.writeChar('\'');
        foreach (ubyte b; v)
        {
            if (b == '\0' || b == '\\' || b == '\'' || b == '\"')
            {
                _writer.writeChar('\\');
                _writer.writeUInt8(b);
            }
            else
                _writer.writeUInt8(b);
        }
        _writer.writeChar('\'');
    }

    pragma(inline, true)
    void writeChar(char v)
    {
        _writer.writeChar(v);
    }

    pragma(inline, true)
    void writeCommand(MyCmdId v) nothrow
    {
        _writer.writeInt8(v);
    }

    void writeCString(scope const(char)[] v) nothrow
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
    void writeDate(scope const(DbDate) v) nothrow
    {
        ubyte[maxDateBufferSize] bytes = void;
        const nBytes = dateEncode(bytes, v);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    void writeDateString(scope const(DbDate) v) nothrow
    {
        char[maxDateStringSize] str = void;
        const len = dateEncodeString(str, v);
        writeOpaqueChars(str[0..len]);
    }

    pragma(inline, true)
    void writeDateTime(scope const(DbDateTime) v) nothrow
    {
        ubyte[maxDateTimeBufferSize] bytes = void;
        const nBytes = dateTimeEncode(bytes, v);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    void writeDateTimeString(scope const(DbDateTime) v) nothrow
    {
        char[maxDateTimeStringSize] str = void;
        const len = dateTimeEncodeString(str, v);
        writeOpaqueChars(str[0..len]);
    }

    void writeDecimal(D)(scope const(D) v)
    if (isDecimal!D)
    {
        ShortStringBuffer!char buffer;
        writeString(v.toString!(ShortStringBuffer!char, char)(buffer)[]);
    }

    void writeDecimalString(D)(scope const(D) v)
    if (isDecimal!D)
    {
        ShortStringBuffer!char buffer;
        writeOpaqueChars(v.toString!(ShortStringBuffer!char, char)(buffer)[]);
    }

    pragma(inline, true)
    void writeFloat32(float32 v) nothrow
    {
        writeUInt32!4(numericBitCast!uint32(v));
    }

    void writeFloat32String(float32 v)
    {
        ShortStringBuffer!char buffer;
        auto fmtSpec = simpleFloatFmt();
        formatValue(buffer, v, fmtSpec);
        writeOpaqueChars(buffer[]);
    }

    pragma(inline, true)
    void writeFloat64(float64 v) nothrow
    {
        writeUInt64!8(numericBitCast!uint64(v));
    }

    void writeFloat64String(float64 v)
    {
        ShortStringBuffer!char buffer;
        auto fmtSpec = simpleFloatFmt();
        formatValue(buffer, v, fmtSpec);
        writeOpaqueChars(buffer[]);
    }

    void writeGeometry(scope const(MyGeometry) v) nothrow
    {
        char[maxMyGeometryBufferSize] str = void;
        const len = geometryEncode(str, v);
        writeString(str[0..len]);
    }

    void writeGeometryString(scope const(MyGeometry) v) nothrow
    {
        ubyte[maxMyGeometryBufferSize] bytes = void;
        const len = geometryEncode(bytes, v);
        writeBytesString(bytes[0..len]);
    }

    pragma(inline, true)
    void writeInt8(int8 v) nothrow // TINYINT
    {
        _writer.writeInt8(v);
    }

    pragma(inline, true)
    void writeInt16(int16 v) nothrow
    {
        writeUInt16(numericBitCast!uint16(v));
    }

    pragma(inline, true)
    void writeInt32(int32 v) nothrow
    {
        writeUInt32!4(numericBitCast!uint32(v));
    }

    void writeInt32String(int32 v)
    {
        ShortStringBuffer!char buffer;
        auto fmtSpec = simpleIntegerFmt();
        formatValue(buffer, v, fmtSpec);
        writeOpaqueChars(buffer[]);
    }

    pragma(inline, true)
    void writeInt64(int64 v) nothrow
    {
        writeUInt64!8(numericBitCast!uint64(v));
    }

    void writeInt64String(int64 v)
    {
        ShortStringBuffer!char buffer;
        auto fmtSpec = simpleIntegerFmt();
        formatValue(buffer, v, fmtSpec);
        writeOpaqueChars(buffer[]);
    }

    pragma(inline, true)
    void writeLength(int64 length) nothrow
    in
    {
        assert(length >= 0);
    }
    do
    {
        writePackedUInt64(numericBitCast!uint64(length));
    }

    pragma(inline, true)
    void writeLength(size_t length) nothrow
    {
        writeLength(cast(int64)length);
    }

    pragma(inline, true)
    void writeOpaqueBytes(scope const(ubyte)[] v) nothrow
    {
        _writer.writeBytes(v);
    }

    pragma(inline, true)
    void writeOpaqueChars(scope const(char)[] v) nothrow
    {
        _writer.writeBytes(v.representation());
    }

    pragma(inline, true)
    void writePackedInt32(int32 v) nothrow
    {
        if (v == -1)
            writeUInt8(MyPackedIntegerIndicator.negOne);
        else
            writePackedUInt32(numericBitCast!uint32(v));
    }

    pragma(inline, true)
    void writePackedInt64(int64 v) nothrow
    {
        if (v == -1)
            writeUInt8(MyPackedIntegerIndicator.negOne);
        else
            writePackedUInt64(numericBitCast!uint64(v));
    }

    pragma(inline, true)
    void writePackedUInt32(uint32 v) nothrow
    {
        uint8 nBytes = void;
        auto bytes = uintEncodePacked!uint32(v, nBytes);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    pragma(inline, true)
    void writePackedUInt64(uint64 v) nothrow
    {
        uint8 nBytes = void;
        auto bytes = uintEncodePacked!uint64(v, nBytes);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    void writeString(scope const(char)[] v) nothrow
    in
    {
        assert(v.length < int32.max);
    }
    do
    {
        writeLength(v.length);
        if (v.length)
            _writer.writeBytes(v.representation);
    }

    void writeStringString(scope const(char)[] v)
    in
    {
        assert(v.length < int32.max);
    }
    do
    {
        auto db = connection.database;
        _writer.writeChar('\'');
        writeOpaqueChars(db.escapeString(v));
        _writer.writeChar('\'');
    }

    void writeTime(scope const(DbTime) v) nothrow
    {
        writeTimeSpan(DbTimeSpan(v));
    }

    void writeTimeString(scope const(DbTime) v) nothrow
    {
        writeTimeSpanString(DbTimeSpan(v));
    }

    void writeTimeSpan(scope const(DbTimeSpan) v) nothrow
    {
        ubyte[maxTimeSpanBufferSize] bytes = void;
        const nBytes = timeSpanEncode(bytes, v);
        _writer.writeBytes(bytes[0..nBytes]);
    }

    void writeTimeSpanString(scope const(DbTimeSpan) v) nothrow
    {
        char[maxTimeSpanStringSize] str = void;
        const len = timeSpanEncodeString(str, v);
        writeOpaqueChars(str[0..len]);
    }

    pragma(inline, true)
    void writeUInt8(uint8 v) nothrow
    {
        _writer.writeUInt8(v);
    }

    pragma(inline, true)
    void writeUInt16(uint16 v) nothrow
    {
        writeUInt32!2(cast(uint32)v);
    }

    pragma(inline, true)
    void writeUInt32(uint32 v) nothrow
    {
        writeUInt32!4(v);
    }

    // This is optimized for 32 bits build to avoid values passed on stack
    // if use writeUInt64
    void writeUInt32(uint8 NBytes)(uint32 v) nothrow
    if (NBytes == 2 || NBytes == 3 || NBytes == 4)
    {
        auto bytes = uintEncode!(uint32, NBytes)(v);
        _writer.writeBytes(bytes[0..NBytes]);
    }

    pragma(inline, true)
    void writeUInt64(uint64 v) nothrow
    {
        writeUInt64!8(v);
    }

    void writeUInt64(uint8 NBytes)(uint64 v) nothrow
    if (NBytes == 2 || NBytes == 3 || NBytes == 8)
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

    void writeUUIDString(scope const(UUID) v)
    {
        char[36] tempBuffer;
        v.toString(tempBuffer[]);
        writeStringString(tempBuffer[]);
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property MyConnection connection() nothrow pure
    {
        return _connection;
    }

    @property uint maxSinglePackage() const nothrow pure
    {
        return _maxSinglePackage;
    }

private:
    void writePackageLength() nothrow
    {
        if (_reserveLenghtOffset >= 0)
        {
            // Package length exclude the length header
            const blockSize = _buffer.length - _reserveLenghtOffset - 4;
            auto blockHeader = blockHeaderEncode(blockSize, _sequenceByte);

            version (TraceFunction) traceFunction!("pham.db.mydatabase")("_reserveLenghtOffset=", _reserveLenghtOffset, ", blockSize=", blockSize, ", blockHeader=", blockHeader.a[].dgToHex());

            _writer.rewriteUInt32(blockHeader.u, _reserveLenghtOffset);
            _reserveLenghtOffset = -1; // Reset after done written the length
        }
    }

private:
    DbWriteBuffer _buffer;
    MyConnection _connection;
    DbValueWriter!(Endian.littleEndian) _writer;
    ptrdiff_t _reserveLenghtOffset;
    uint _maxSinglePackage;
    ubyte _sequenceByte;
    bool _socketBuffer;
}


// Any below codes are private
private:

version (none) //todo
unittest // MyXdrWriter & MyXdrReader
{
    import pham.utl.test;
    traceUnitTest!("pham.db.mydatabase")("unittest pham.db.mybuffer.MyXdrReader & db.mybuffer.MyXdrWriter");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";
    const(ubyte)[] bytes = [1,2,5,101];
    const(UUID) uuid = UUID(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer(4000);
    auto writer = MyXdrWriter(null, 0, writerBuffer);
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
    writer.writeCString(chars);
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
    auto readerBuffer = new DbReadBuffer(writerBytes);
    auto reader = MyXdrReader(null, readerBuffer);
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
    assert(reader.readCString() == chars);
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
