/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * Conversion should be found under PostgreSQL...\src\backend\utils\adt\... (_recv or _send)
*/

module pham.db.pgbuffer;

import std.string : representation;
import std.system : Endian;

version (unittest) import pham.utl.test;
import pham.db.message;
import pham.db.type;
import pham.db.util;
import pham.db.convert;
import pham.db.buffer;
import pham.db.value;
import pham.db.pgoid;
import pham.db.pgtype;
import pham.db.pgexception;
import pham.db.pgconvert;
import pham.db.pgdatabase;

struct PgReader
{
@safe:

public:
    @disable this(this);

    this(PgConnection connection)
    {
        this._connection = connection;
        this.readPacketData(connection);
    }

    this(PgConnection connection, ubyte[] packetData)
    in
    {
        assert(packetData.length < int.max);
    }
    do
    {
        this._messageType = 0;
        this._connection = connection;
        this._messageLength = cast(int)packetData.length;
        this._readBuffer = new DbReadBuffer(packetData);
        this._reader = DbValueReader!(Endian.bigEndian)(this._readBuffer);
    }

    void dispose(bool disposing = true)
    {
        _readBuffer = null;
        _connection = null;
        _reader.dispose(disposing);
    }

    ubyte[] readBytes(size_t nBytes)
    {
        return _reader.readBytes(nBytes);
    }

    char readChar()
    {
        return _reader.readChar();
    }

    char[] readChars(size_t nBytes)
    {
        return _reader.readChars(nBytes);
    }

    string readString(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(string)readChars(nBytes);
    }

    char[] readCChars()
    {
        auto result = readChars(_readBuffer.search(0));
        return result[0..$ - 1]; // Excluded null terminated char
    }

    string readCString() @trusted // @trusted=cast()
    {
        return cast(string)readCChars();
    }

    int16 readFieldCount()
    {
        return _reader.readInt16();
    }

    int16 readInt16()
    {
        return _reader.readInt16();
    }

    int32 readInt32()
    {
        return _reader.readInt32();
    }

    PgOId readOId()
    {
        assert(PgOId.sizeof == int32.sizeof);

        return _reader.readInt32();
    }

    uint8 readUInt8()
    {
        return _reader.readUInt8();
    }

    int32 readValueLength()
    {
        return _reader.readInt32();
    }

    void skip(size_t nBytes)
    {
        _readBuffer.advance(nBytes);
    }

    @property PgConnection connection() nothrow pure
    {
        return _connection;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _readBuffer.empty;
    }

    @property int messageLength() const nothrow pure
    {
        return _messageLength;
    }

    @property char messageType() const nothrow pure
    {
        return _messageType;
    }

    @property DbReadBuffer readBuffer() nothrow pure
    {
        return _readBuffer;
    }

private:
    void readPacketData(PgConnection connection)
    {
        auto socketBuffer = connection.acquireSocketReadBuffer();
        auto socketReader = DbValueReader!(Endian.bigEndian)(socketBuffer);
        _messageType = socketReader.readChar();
        _messageLength = socketReader.readInt32();
        _messageLength -= int32.sizeof; // Substract message length size

        // Read message data?
        if (_messageLength > 0)
        {
            auto packetData = socketReader.readBytes(_messageLength);
            this._readBuffer = new DbReadBuffer(packetData);
        }
        else
        {
            this._readBuffer = new DbReadBuffer(0);
        }
        this._reader = DbValueReader!(Endian.bigEndian)(this._readBuffer);

        version (TraceFunction)
        dgFunctionTrace("messageType=", _messageType, ", messageLength=", _messageLength);
    }

private:
    PgConnection _connection;
    DbReadBuffer _readBuffer;
    DbValueReader!(Endian.bigEndian) _reader;
    int32 _messageLength;
    char _messageType;
}

struct PgWriter
{
@safe:

public:
    @disable this(this);

    this(PgConnection connection,
        IbWriteBuffer buffer = null)
    {
        this._reserveLenghtOffset = -1;
        this._connection = connection;
        this._buffer = buffer;
        this._needBuffer = buffer is null;
        if (this._needBuffer)
            this._buffer = connection.acquireSocketWriteBuffer();
        else
            buffer.reset();
    }

    ~this()
    {
        dispose(false);
    }

    void dispose(bool disposing = true)
    {
        if (_needBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);

        _buffer = null;
        _connection = null;
        _needBuffer = false;
        _reserveLenghtOffset = -1;
    }

    void endMessage() nothrow
    {
        writeMessageLength();
    }

    void flush()
    {
        version (TraceFunction) dgFunctionTrace();

        writeMessageLength();
        _buffer.flush();
    }

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

    void startMessage(char messageCode) nothrow
    in
    {
        assert(_reserveLenghtOffset < 0);
    }
    do
    {
        version (TraceFunction)
        {
            if (messageCode != '\0')
                dgFunctionTrace("_buffer.offset=", _buffer.offset, ", messageCode=", messageCode);
            else
                dgFunctionTrace("_buffer.offset=", _buffer.offset);
        }

        if (messageCode != '\0')
            _buffer.writeChar(messageCode);
        _reserveLenghtOffset = _buffer.offset;
        _buffer.writeInt32(0);
    }

    void writeBytes(scope const(ubyte)[] v) nothrow
    {
        _buffer.writeInt32(v.length);
        _buffer.writeBytes(v);
    }

    void writeBytesRaw(scope const(ubyte)[] v) nothrow
    {
        _buffer.writeBytes(v);
    }

    void writeChar(char v) nothrow
    {
        _buffer.writeChar(v);
    }

    void writeCChars(scope const(char)[] v) nothrow
    {
        _buffer.writeBytes(v.representation);
        _buffer.writeUInt8(0);
    }

    void writeInt16(int16 v) nothrow
    {
        _buffer.writeInt16(v);
    }

    void writeInt32(int32 v) nothrow
    {
        _buffer.writeInt32(v);
    }

    void writeSignal(PgDescribeType signalType, int32 signalId) nothrow
    {
        _buffer.writeChar(signalType);
        _buffer.writeInt32(signalId);
    }

    void writeUInt32(uint32 v) nothrow
    {
        _buffer.writeUInt32(v);
    }

    static if (size_t.sizeof > uint32.sizeof)
    void writeUInt32(size_t v) nothrow
    {
        _buffer.writeUInt32(cast(uint32)v);
    }

    @property IbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property PgConnection connection() nothrow pure
    {
        return _connection;
    }

private:
    version (unittest)
    this(ubyte[] dummy)
    {
        this._connection = null;
        this._reserveLenghtOffset = -1;
        this._needBuffer = false;
        this._buffer = new DbWriteBuffer!(Endian.bigEndian)(4000);
    }

    void writeMessageLength() nothrow
    {
        if (_reserveLenghtOffset >= 0)
        {
            // Package length includes the length itself but exclude the package code
            const len = _buffer.length - _reserveLenghtOffset;

            version (TraceFunction) dgFunctionTrace("_reserveLenghtOffset=", _reserveLenghtOffset, ", len=", len);

            _buffer.rewriteInt32(cast(int32)len, _reserveLenghtOffset);
            _reserveLenghtOffset = -1; // Reset after done written the length
        }
    }

private:
    IbWriteBuffer _buffer;
    PgConnection _connection;
    ptrdiff_t _reserveLenghtOffset = -1;
    bool _needBuffer;
}

struct PgXdrReader
{
@safe:

public:
    @disable this(this);

    this(PgConnection connection, DbReadBuffer readBuffer)
    {
        this._connection = connection;
        this._readBuffer = readBuffer;
        this._reader = DbValueReader!(Endian.bigEndian)(this._readBuffer);
    }

    void dispose(bool disposing = true)
    {
        _readBuffer = null;
        _connection = null;
        _reader.dispose(disposing);
    }

    bool readBool()
    {
        return _reader.readBool();
    }

    ubyte[] readBytes(size_t nBytes)
    {
        return _reader.readBytes(nBytes);
    }

    char[] readChars(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(char[])readBytes(nBytes);
    }

    Date readDate()
    {
        return dateDecode(readInt32());
    }

    DbDateTime readDateTime()
    {
        return dateTimeDecode(readInt64());
    }

    DbDateTime readDateTimeTZ()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        auto dt = readInt64();
        auto z = readInt16();
        return dateTimeDecodeTZ(dt, z);
    }

    D readDecimal(D)(in DbBaseType baseType)
    if (isDecimal!D)
    {
        if (baseType.typeId == PgOIdType.money)
            return cast(D)readMoney();
        else
            return readNumeric!D();
    }

    float readFloat32()
    {
        return _reader.readFloat32();
    }

    double readFloat64()
    {
        return _reader.readFloat64();
    }

    int16 readInt16()
    {
        return _reader.readInt16();
    }

    int32 readInt32()
    {
        return _reader.readInt32();
    }

    int64 readInt64()
    {
        return _reader.readInt64();
    }

    BigInteger readInt128()
    {
        assert(0, "database does not support");
        //TODO return _buffer.readInt64();
        //return BigInteger(0);
    }

    Decimal64 readMoney()
    {
        return decimalDecode!(Decimal64, int64)(readInt64(), -2);
    }

    D readNumeric(D)()
    if (isDecimal!D)
    {
        PgOIdNumeric result;
        result.ndigits = readInt16();
        result.weight = readInt16();
        result.sign = readInt16();
        result.dscale = readInt16();
        if (result.ndigits > 0)
        {
            result.digits.length = result.ndigits;
            foreach (i; 0..result.ndigits)
                result.digits[i] = readInt16();
        }
        return numericDecode!D(result);
    }

    string readString(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(string)readChars(nBytes);
    }

    DbTime readTime()
    {
        return timeDecode(readInt64());
    }

    DbTime readTimeTZ()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        auto t = readInt64();
        auto z = readInt16();
        return timeDecodeTZ(t, z);
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    UUID readUUID()
    {
        static assert(UUID.sizeof == 16);

        ubyte[UUID.sizeof] buffer = void;
        return UUID(_reader.readBytes(buffer)[0..UUID.sizeof]);
    }

    @property PgConnection connection() nothrow pure
    {
        return _connection;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _readBuffer.empty;
    }

    @property DbReadBuffer readBuffer() nothrow pure
    {
        return _readBuffer;
    }

private:
    version (unittest)
    this(ubyte[] data)
    {
        this._connection = null;
        this._readBuffer = new DbReadBuffer(data);
        this._reader = DbValueReader!(Endian.bigEndian)(this._readBuffer);
    }

private:
    PgConnection _connection;
    DbReadBuffer _readBuffer;
    DbValueReader!(Endian.bigEndian) _reader;
}

struct PgXdrWriter
{
@safe:

public:
    @disable this(this);

    this(PgConnection connection, IbWriteBuffer buffer)
    {
        this._connection = connection;
        this._buffer = buffer;
    }

    void dispose(bool disposing = true)
    {
        _buffer = null;
        _connection = null;
    }

    size_t writeArrayBegin() nothrow
    {
        return markBegin();
    }

    void writeArrayEnd(size_t marker) nothrow
    {
        markEnd(marker);
    }

    void writeBool(bool v) nothrow
    {
        _buffer.writeInt32(1);
        _buffer.writeBool(v);
    }

    void writeBytes(scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length < int32.max);
    }
    do
    {
        _buffer.writeInt32(cast(int32)v.length);
        _buffer.writeBytes(v);
    }

    void writeChars(scope const(char)[] v) nothrow
    {
        writeBytes(v.representation);
    }

    void writeDate(in Date v) nothrow
    {
        writeInt32(dateEncode(v));
    }

    void writeDateTime(in DbDateTime v) nothrow
    {
        writeInt64(dateTimeEncode(v));
    }

    void writeDateTimeTZ(in DbDateTime v) nothrow
    {
        int64 dt = void;
        int32 z = void;
        dateTimeEncodeTZ(v, dt, z);

        _buffer.writeInt32(12);
        _buffer.writeInt64(dt);
        _buffer.writeInt32(z);
    }

    void writeDecimal(D)(in D v, in DbBaseType baseType) nothrow
    if (isDecimal!D)
    {
        if (baseType.typeId == PgOIdType.money)
            writeMoney(cast(Decimal64)v);
        else
            writeNumeric!D(v);
    }

    void writeFloat32(float32 v) nothrow
    {
        _buffer.writeInt32(4);
        _buffer.writeFloat32(v);
    }

    void writeFloat64(float64 v) nothrow
    {
        _buffer.writeInt32(8);
        _buffer.writeFloat64(v);
    }

    void writeInt16(int16 v) nothrow
    {
        _buffer.writeInt32(2);
        _buffer.writeInt16(v);
    }

    void writeInt32(int32 v) nothrow
    {
        _buffer.writeInt32(4);
        _buffer.writeInt32(v);
    }

    void writeInt64(int64 v) nothrow
    {
        _buffer.writeInt32(8);
        _buffer.writeInt64(v);
    }

    void writeInt128(in BigInteger v) nothrow
    {
        //TODO
    }

    void writeMoney(in Decimal64 v) nothrow
    {
        writeInt64(decimalEncode!(Decimal64, int64)(v, -2));
    }

    void writeNumeric(D)(in D v) nothrow
    if (isDecimal!D)
    {
        auto n = numericEncode!D(v);

        const marker = markBegin();
        _buffer.writeInt16(n.ndigits);
        _buffer.writeInt16(n.weight);
        _buffer.writeInt16(n.sign);
        _buffer.writeInt16(n.dscale);
        if (n.ndigits > 0)
        {
            foreach (i; 0..n.ndigits)
                _buffer.writeInt16(n.digits[i]);
        }
        markEnd(marker);
    }

    void writeTime(in DbTime v) nothrow
    {
        writeInt64(timeEncode(v));
    }

    void writeTimeTZ(in DbTime v) nothrow
    {
        int64 t = void;
        int32 z = void;
        timeEncodeTZ(v, t, z);

        _buffer.writeInt32(12);
        _buffer.writeInt64(t);
        _buffer.writeInt32(z);
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    void writeUUID(in UUID v) nothrow
    {
        _buffer.writeInt32(16);
        _buffer.writeBytes(v.data); // v.data is already in big-endian
    }

    @property PgConnection connection() nothrow pure
    {
        return _connection;
    }

private:
    version (unittest)
    this(ubyte[] dummy)
    {
        this._connection = null;
        this._buffer = new DbWriteBuffer!(Endian.bigEndian)(4000);
    }

    size_t markBegin() nothrow
    {
        version (TraceFunction) dgFunctionTrace("_buffer.offset=", _buffer.offset);

        auto result = _buffer.offset;
        _buffer.writeInt32(0);
        return result;
    }

    void markEnd(size_t marker) nothrow
    {
        // Value length excludes its length
        const len = _buffer.offset - marker - int32.sizeof;
        version (TraceFunction) dgFunctionTrace("marker=", marker, ", len=", len);
        _buffer.rewriteInt32(cast(int32)(len), marker);
    }

private:
    IbWriteBuffer _buffer;
    PgConnection _connection;
}
