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

module pham.db.db_pgbuffer;

import std.string : representation;
import std.system : Endian;

version (unittest) import pham.utl.utl_test;
import pham.external.dec.dec_decimal : scaleFrom, scaleTo;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.db.db_buffer;
import pham.db.db_convert;
import pham.db.db_type;
import pham.db.db_pgdatabase;
import pham.db.db_pgconvert;
import pham.db.db_pgoid;
import pham.db.db_pgtype;

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

    this(ubyte[] packetData) nothrow
    in
    {
        assert(packetData.length < int32.max);
    }
    do
    {
        this._connection = null;
        this._messageType = 0;
        this._messageLength = cast(int32)packetData.length;
        this._buffer = new DbReadBuffer(packetData);
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        if (_buffer !is null && _connection !is null)
            _connection.releaseMessageReadBuffer(_buffer);

        _buffer = null;        
        _reader.dispose(disposingReason);
        if (isDisposing(disposingReason))
            _connection = null;
    }

    pragma(inline, true)
    ubyte[] readBytes(size_t nBytes)
    {
        return _reader.readBytes(nBytes);
    }

    pragma(inline, true)
    char readChar()
    {
        return _reader.readChar();
    }

    version (none)
    pragma(inline, true)
    char[] readChars(size_t nBytes)
    {
        return _reader.readChars(nBytes);
    }

    pragma(inline, true)
    char[] readCChars()
    {
        auto result = _reader.readChars(_buffer.search(0));
        return result.length ? result[0..$ - 1] : null; // -1=excluded null terminated char
    }

    pragma(inline, true)
    string readCString() @trusted // @trusted=cast()
    {
        return cast(string)readCChars();
    }

    pragma(inline, true)
    int16 readFieldCount()
    {
        return _reader.readInt16();
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return _reader.readInt16();
    }

    pragma(inline, true)
    int32 readInt32()
    {
        return _reader.readInt32();
    }

    pragma(inline, true)
    PgOId readOId()
    {
        static assert(PgOId.sizeof == int32.sizeof);

        return _reader.readInt32();
    }

    pragma(inline, true)
    string readString(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(string)_reader.readChars(nBytes);
    }

    pragma(inline, true)
    uint8 readUInt8()
    {
        return _reader.readUInt8();
    }

    pragma(inline, true)
    int32 readValueLength()
    {
        return _reader.readInt32();
    }

    pragma(inline, true)
    void skip(size_t nBytes)
    {
        _buffer.advance(nBytes);
    }

    @property DbReadBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property PgConnection connection() nothrow pure
    {
        return _connection;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _buffer.empty;
    }

    pragma(inline, true)
    @property int32 messageLength() const nothrow pure
    {
        return _messageLength;
    }

    pragma(inline, true)
    @property char messageType() const nothrow pure
    {
        return _messageType;
    }

private:
    void readPacketData(PgConnection connection)
    {
        auto socketBuffer = connection.acquireSocketReadBuffer();
        auto socketReader = DbValueReader!(Endian.bigEndian)(socketBuffer);
        _messageType = socketReader.readChar();
        _messageLength = socketReader.readInt32();
        _messageLength -= int32.sizeof; // Substract message length size

        this._buffer = connection.acquireMessageReadBuffer();
        // Read message data?
        if (_messageLength > 0)
        {
            auto bufferData = this._buffer.expand(_messageLength);
            socketReader.readBytes(bufferData);
        }
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);

        version (TraceFunction) traceFunction("messageType=", _messageType, ", messageLength=", _messageLength);
    }

private:
    DbReadBuffer _buffer;
    PgConnection _connection;
    DbValueReader!(Endian.bigEndian) _reader;
    int32 _messageLength;
    char _messageType;
}

struct PgWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(PgConnection connection) nothrow
    {
        this._needBuffer = true;
        this._reserveLenghtOffset = -1;
        this._connection = connection;
        this._buffer = connection.acquireSocketWriteBuffer();
        this._writer = DbValueWriter!(Endian.bigEndian)(this._buffer);
    }

    this(PgConnection connection, DbWriteBuffer buffer) nothrow
    {
        this._needBuffer = false;
        this._reserveLenghtOffset = -1;
        this._connection = connection;
        this._buffer = buffer;
        this._writer = DbValueWriter!(Endian.bigEndian)(buffer.reset());
    }

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    void beginMessage(char messageCode) nothrow
    in
    {
        assert(_reserveLenghtOffset < 0);
    }
    do
    {
        version (TraceFunction) traceFunction(traceString(messageCode));

        if (messageCode != '\0')
            _writer.writeChar(messageCode);
        _reserveLenghtOffset = _buffer.offset;
        _writer.writeInt32(0); // Reserve length value slot
    }

    void beginUntypeMessage() nothrow
    {
        beginMessage('\0');
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        if (_needBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);

        _buffer = null;
        _reserveLenghtOffset = -1;
        if (isDisposing(disposingReason))
        {
            _needBuffer = false;
            _connection = null;
        }
    }

    pragma(inline, true)
    void endMessage() nothrow
    {
        writeMessageLength();
    }

    void flush()
    {
        version (TraceFunction) traceFunction("_buffer.length=", _buffer.length);

        writeMessageLength();
        _buffer.flush();
    }

    pragma(inline, true)
    ubyte[] peekBytes() nothrow
    {
        return _buffer.peekBytes();
    }

    version (TraceFunction)
    string traceString(char messageCode) const nothrow pure @trusted
    {
        import std.conv : to;

        if (messageCode != '\0')
            return "_buffer.offset=" ~ to!string(_buffer.offset)
                ~ ", messageCode=" ~ messageCode;
        else
            return "_buffer.offset=" ~ to!string(_buffer.offset);
    }

    void writeBytes(scope const(ubyte)[] v) nothrow
    {
        _writer.writeInt32(v.length);
        _writer.writeBytes(v);
    }

    pragma(inline, true)
    void writeBytesRaw(scope const(ubyte)[] v) nothrow
    {
        _writer.writeBytes(v);
    }

    pragma(inline, true)
    void writeChar(char v) nothrow
    {
        _writer.writeChar(v);
    }

    void writeCChars(scope const(char)[] v) nothrow
    {
        _writer.writeBytes(v.representation);
        _writer.writeUInt8(0);
    }

    pragma(inline, true)
    void writeInt16(int16 v) nothrow
    {
        _writer.writeInt16(v);
    }

    pragma(inline, true)
    void writeInt32(int32 v) nothrow
    {
        _writer.writeInt32(v);
    }

    void writeSignal(PgOIdDescribeType signalType, int32 signalId) nothrow
    {
        _writer.writeChar(signalType);
        _writer.writeInt32(signalId);
    }

    pragma(inline, true)
    void writeUInt32(uint32 v) nothrow
    {
        _writer.writeUInt32(v);
    }

    static if (size_t.sizeof > uint32.sizeof)
    pragma(inline, true)
    void writeUInt32(size_t v) nothrow
    {
        _writer.writeUInt32(cast(uint32)v);
    }

    @property DbWriteBuffer buffer() nothrow pure
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
        this._buffer = new DbWriteBuffer(4000);
        this._writer = DbValueWriter!(Endian.bigEndian)(this._buffer);
    }

    void writeMessageLength() nothrow
    {
        if (_reserveLenghtOffset >= 0)
        {
            // Package length includes the length itself but exclude the package code
            const len = _buffer.length - _reserveLenghtOffset;

            version (TraceFunction) traceFunction("_reserveLenghtOffset=", _reserveLenghtOffset, ", len=", len);

            _writer.rewriteInt32(cast(int32)len, _reserveLenghtOffset);
            _reserveLenghtOffset = -1; // Reset after done written the length
        }
    }

private:
    DbWriteBuffer _buffer;
    PgConnection _connection;
    DbValueWriter!(Endian.bigEndian) _writer;
    ptrdiff_t _reserveLenghtOffset;
    bool _needBuffer;
}

struct PgXdrReader
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(PgConnection connection, DbReadBuffer buffer)
    {
        this._connection = connection;
        this._buffer = buffer;
        this._reader = DbValueReader!(Endian.bigEndian)(buffer);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _buffer = null;
        _reader.dispose(disposingReason);
        if (isDisposing(disposingReason))
            _connection = null;
    }

    pragma(inline, true)
    bool readBool()
    {
        return _reader.readBool();
    }

    version (none)
    ubyte[] readBytes()
    {
        const len = readInt32();
        return readBytes(len);
    }

    pragma(inline, true)
    ubyte[] readBytes(size_t nBytes)
    {
        return _reader.readBytes(nBytes);
    }

    version (none)
    char[] readChars() @trusted // @trusted=cast()
    {
        const len = readInt32();
        return cast(char[])readBytes(len);
    }

    pragma(inline, true)
    char[] readChars(size_t nBytes) @trusted // @trusted=cast()
    {
        return cast(char[])readBytes(nBytes);
    }

    DbDate readDate()
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
        auto dt = _reader.readInt64();
        auto z = _reader.readInt32();
        return dateTimeDecodeTZ(dt, z);
    }

    D readDecimal(D)(scope const(DbBaseType) baseType)
    if (isDecimal!D)
    {
        if (baseType.typeId == PgOIdType.money)
            return cast(D)readMoney();
        else
            return readNumeric!D();
    }

    pragma(inline, true)
    float32 readFloat32()
    {
        return _reader.readFloat32();
    }

    pragma(inline, true)
    float64 readFloat64()
    {
        return _reader.readFloat64();
    }

    DbGeoBox readGeoBox()
    {
        DbGeoBox result = void;
        result.right = _reader.readFloat64();
        result.top = _reader.readFloat64();
        result.left = _reader.readFloat64();
        result.bottom = _reader.readFloat64();
        return result;
    }

    DbGeoCircle readGeoCircle()
    {
        DbGeoCircle result = void;
        result.x = _reader.readFloat64();
        result.y = _reader.readFloat64();
        result.r = _reader.readFloat64();
        return result;
    }

    DbGeoPath readGeoPath()
    {
        DbGeoPath result;
        result.open = _reader.readBool();
        const numPoints = _reader.readInt32();
        if (numPoints)
        {
            result.points.length = numPoints;
            foreach (i; 0..numPoints)
            {
                result.points[i].x = _reader.readFloat64();
                result.points[i].y = _reader.readFloat64();
            }
        }
        return result;
    }

    DbGeoPolygon readGeoPolygon()
    {
        DbGeoPolygon result;
        const numPoints = _reader.readInt32();
        if (numPoints)
        {
            result.points.length = numPoints;
            foreach (i; 0..numPoints)
            {
                result.points[i].x = _reader.readFloat64();
                result.points[i].y = _reader.readFloat64();
            }
        }
        return result;
    }

    DbGeoPoint readGeoPoint()
    {
        DbGeoPoint result = void;
        result.x = _reader.readFloat64();
        result.y = _reader.readFloat64();
        return result;
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return _reader.readInt16();
    }

    pragma(inline, true)
    int32 readInt32()
    {
        return _reader.readInt32();
    }

    pragma(inline, true)
    int64 readInt64()
    {
        return _reader.readInt64();
    }

    BigInteger readInt128()
    {
        assert(0, "database does not support Int128");
        //TODO
    }

    PgOIdInterval readInterval()
    {
        PgOIdInterval result = void;
        result.microseconds = _reader.readInt64();
        result.days = _reader.readInt32();
        result.months = _reader.readInt32();
        return result;
    }

    Decimal64 readMoney()
    {
        return scaleFrom!(int64, Decimal64)(readInt64(), -2);
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

    pragma(inline, true)
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
        auto t = _reader.readInt64();
        auto z = _reader.readInt32();
        return timeDecodeTZ(t, z);
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    UUID readUUID()
    {
        static assert(UUID.sizeof == 16);

        ubyte[UUID.sizeof] buffer = void;
        return UUID(_reader.readBytes(buffer)[0..UUID.sizeof]);
    }

    @property DbReadBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property PgConnection connection() nothrow pure
    {
        return _connection;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _buffer.empty;
    }

private:
    version (unittest)
    this(ubyte[] data)
    {
        this._connection = null;
        this._buffer = new DbReadBuffer(data);
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);
    }

private:
    DbReadBuffer _buffer;
    PgConnection _connection;
    DbValueReader!(Endian.bigEndian) _reader;
}

struct PgXdrWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(PgConnection connection, DbWriteBuffer buffer) nothrow
    {
        this._connection = connection;
        this._buffer = buffer;
        this._writer = DbValueWriter!(Endian.bigEndian)(buffer);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _buffer = null;
        _writer.dispose(disposingReason);
        if (isDisposing(disposingReason))
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
        _writer.writeInt32(1);
        _writer.writeBool(v);
    }

    void writeBytes(scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length < int32.max);
    }
    do
    {
        _writer.writeInt32(cast(int32)v.length);
        _writer.writeBytes(v);
    }

    void writeChars(scope const(char)[] v) nothrow
    {
        writeBytes(v.representation);
    }

    void writeDate(scope const(DbDate) v) nothrow
    {
        writeInt32(dateEncode(v));
    }

    void writeDateTime(scope const(DbDateTime) v) nothrow
    {
        writeInt64(dateTimeEncode(v));
    }

    void writeDateTimeTZ(scope const(DbDateTime) v) nothrow
    {
        int64 dt = void;
        int32 z = void;
        dateTimeEncodeTZ(v, dt, z);

        _writer.writeInt32(12);
        _writer.writeInt64(dt);
        _writer.writeInt32(z);
    }

    void writeDecimal(D)(scope const(D) v, scope const(DbBaseType) baseType) nothrow
    if (isDecimal!D)
    {
        if (baseType.typeId == PgOIdType.money)
            writeMoney(cast(Decimal64)v);
        else
            writeNumeric!D(v);
    }

    void writeFloat32(float32 v) nothrow
    {
        _writer.writeInt32(4);
        _writer.writeFloat32(v);
    }

    void writeFloat64(float64 v) nothrow
    {
        _writer.writeInt32(8);
        _writer.writeFloat64(v);
    }

    void writeGeoBox(scope const(DbGeoBox) v) nothrow
    {
        _writer.writeInt32(8 * 4);
        _writer.writeFloat64(v.right);
        _writer.writeFloat64(v.top);
        _writer.writeFloat64(v.left);
        _writer.writeFloat64(v.bottom);
    }

    void writeGeoCircle(scope const(DbGeoCircle) v) nothrow
    {
        _writer.writeInt32(8 * 3);
        _writer.writeFloat64(v.x);
        _writer.writeFloat64(v.y);
        _writer.writeFloat64(v.r);
    }

    void writeGeoPath(scope const(DbGeoPath) v) nothrow
    in
    {
        assert(v.points.length <= int32.max);
    }
    do
    {
        const numPoints = cast(int32)v.points.length;
        _writer.writeInt32(1 + 4 + numPoints * 16);
        _writer.writeBool(v.open);
        _writer.writeInt32(numPoints);
        foreach (ref p; v.points)
        {
            _writer.writeFloat64(p.x);
            _writer.writeFloat64(p.y);
        }
    }

    void writeGeoPolygon(scope const(DbGeoPolygon) v) nothrow
    in
    {
        assert(v.points.length <= int32.max);
    }
    do
    {
        const numPoints = cast(int32)v.points.length;
        _writer.writeInt32(4 + numPoints * 16);
        _writer.writeInt32(numPoints);
        foreach (ref p; v.points)
        {
            _writer.writeFloat64(p.x);
            _writer.writeFloat64(p.y);
        }
    }

    void writeGeoPoint(scope const(DbGeoPoint) v) nothrow
    {
        _writer.writeInt32(8 * 2);
        _writer.writeFloat64(v.x);
        _writer.writeFloat64(v.y);
    }

    void writeInt16(int16 v) nothrow
    {
        _writer.writeInt32(2);
        _writer.writeInt16(v);
    }

    void writeInt32(int32 v) nothrow
    {
        _writer.writeInt32(4);
        _writer.writeInt32(v);
    }

    void writeInt64(int64 v) nothrow
    {
        _writer.writeInt32(8);
        _writer.writeInt64(v);
    }

    //TODO
    void writeInt128(scope const(BigInteger) v) nothrow
    {
        assert(0, "database does not support Int128");
        //TODO
    }

    void writeInterval(scope const(PgOIdInterval) v) nothrow
    {
        _writer.writeInt32(16);
        _writer.writeInt64(v.microseconds);
        _writer.writeInt32(v.days);
        _writer.writeInt32(v.months);
    }

    void writeMoney(scope const(Decimal64) v) nothrow
    {
        writeInt64(scaleTo!(Decimal64, int64)(v, -2));
    }

    void writeNumeric(D)(scope const(D) v) nothrow
    if (isDecimal!D)
    {
        auto n = numericEncode!D(v);

        const marker = markBegin();
        _writer.writeInt16(n.ndigits);
        _writer.writeInt16(n.weight);
        _writer.writeInt16(n.sign);
        _writer.writeInt16(n.dscale);
        if (n.ndigits > 0)
        {
            foreach (i; 0..n.ndigits)
                _writer.writeInt16(n.digits[i]);
        }
        markEnd(marker);
    }

    void writeTime(scope const(DbTime) v) nothrow
    {
        writeInt64(timeEncode(v));
    }

    void writeTimeTZ(scope const(DbTime) v) nothrow
    {
        int64 t = void;
        int32 z = void;
        timeEncodeTZ(v, t, z);

        _writer.writeInt32(12);
        _writer.writeInt64(t);
        _writer.writeInt32(z);
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    void writeUUID(scope const(UUID) v) nothrow
    {
        _writer.writeInt32(16);
        _writer.writeBytes(v.data); // v.data is already in big-endian
    }

    @property DbWriteBuffer buffer() nothrow pure
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
        this._buffer = new DbWriteBuffer(4000);
        this._writer = DbValueWriter!(Endian.bigEndian)(this._buffer);
    }

    size_t markBegin() nothrow
    {
        version (TraceFunction) traceFunction("_buffer.offset=", _buffer.offset);

        auto result = _buffer.offset;
        _writer.writeInt32(0);
        return result;
    }

    void markEnd(size_t marker) nothrow
    {
        // Value length excludes its length
        const len = _buffer.offset - marker - int32.sizeof;
        version (TraceFunction) traceFunction("marker=", marker, ", len=", len);
        _writer.rewriteInt32(cast(int32)(len), marker);
    }

private:
    DbWriteBuffer _buffer;
    PgConnection _connection;
    DbValueWriter!(Endian.bigEndian) _writer;
}

unittest // PgXdrReader & PgXdrWriter
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.pgbuffer.PgXdrReader & db.fbbuffer.PgXdrWriter");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";
    const(ubyte)[] bytes = [1,2,5,101];
    const(UUID) uuid = UUID(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer(4000);
    auto writer = PgXdrWriter(null, writerBuffer);
    writer.writeBool(true);
    writer.writeBytes(bytes);
    writer.writeChars(chars);
    writer.writeDate(DbDate(1, 2, 3));
    writer.writeDateTime(DbDateTime(DateTime(1,2,3,4,5,6), 0));
    writer.writeDateTimeTZ(DbDateTime(DateTime(1,2,3,4,5,6), 0));
    //writer.writeDecimal();
    writer.writeFloat32(float.min_normal);
    writer.writeFloat32(32.32);
    writer.writeFloat32(float.max);
    writer.writeFloat64(double.min_normal);
    writer.writeFloat64(64.64);
    writer.writeFloat64(double.max);
    writer.writeInt16(short.min);
    writer.writeInt16(16);
    writer.writeInt16(short.max);
    writer.writeInt32(int.min);
    writer.writeInt32(32);
    writer.writeInt32(int.max);
    writer.writeInt64(long.min);
    writer.writeInt64(64);
    writer.writeInt64(long.max);

    writer.writeMoney(Decimal64("-92_000_000_000_000_000.00"));
    writer.writeMoney(Decimal64(0));
    writer.writeMoney(Decimal64.money(23456.78, 2));
    writer.writeMoney(Decimal64("9_200_000_000_000_000.00"));

    writer.writeNumeric!Decimal32(Decimal32.min);
    writer.writeNumeric!Decimal32(Decimal32(0));
    writer.writeNumeric!Decimal32(Decimal32.money(12345.67, 2));
    writer.writeNumeric!Decimal32(Decimal32.max);

    writer.writeNumeric!Decimal64(Decimal64.min);
    writer.writeNumeric!Decimal64(Decimal64(0));
    writer.writeNumeric!Decimal64(Decimal64.money(23456.78, 2));
    writer.writeNumeric!Decimal64(Decimal64.max);

    writer.writeNumeric!Decimal128(Decimal128.min);
    writer.writeNumeric!Decimal128(Decimal128(0));
    writer.writeNumeric!Decimal128(Decimal128.money(34567.89, 2));
    writer.writeNumeric!Decimal128(Decimal128.max);

    writer.writeTime(DbTime(Time(1,2,3)));
    writer.writeTimeTZ(DbTime(Time(1,2,3)));
    writer.writeUUID(uuid);

    ubyte[] writerBytes = writer.buffer.peekBytes();
    auto reader = PgXdrReader(writerBytes);
    int32 valueLength;
    int32 readLength(uint line = __LINE__)
    {
        valueLength = reader.readInt32();
        return valueLength;
    }

    assert(readLength() == 1); assert(reader.readBool());
    assert(readLength() == bytes.length); assert(reader.readBytes(valueLength) == bytes);
    assert(readLength() == chars.length); assert(reader.readChars(valueLength) == chars);
    assert(readLength() == 4); assert(reader.readDate() == DbDate(1, 2, 3));
    assert(readLength() == 8); assert(reader.readDateTime() == DbDateTime(DateTime(1,2,3,4,5,6), 0));
    assert(readLength() == 12); assert(reader.readDateTimeTZ() == DbDateTime(DateTime(1,2,3,4,5,6), 0));
    //assert(reader.readDecimal() == );
    assert(readLength() == 4); assert(reader.readFloat32() == float.min_normal);
    assert(readLength() == 4); assert(reader.readFloat32() == cast(float)32.32);
    assert(readLength() == 4); assert(reader.readFloat32() == float.max);
    assert(readLength() == 8); assert(reader.readFloat64() == double.min_normal);
    assert(readLength() == 8); assert(reader.readFloat64() == cast(double)64.64);
    assert(readLength() == 8); assert(reader.readFloat64() == double.max);
    assert(readLength() == 2); assert(reader.readInt16() == short.min);
    assert(readLength() == 2); assert(reader.readInt16() == 16);
    assert(readLength() == 2); assert(reader.readInt16() == short.max);
    assert(readLength() == 4); assert(reader.readInt32() == int.min);
    assert(readLength() == 4); assert(reader.readInt32() == 32);
    assert(readLength() == 4); assert(reader.readInt32() == int.max);
    assert(readLength() == 8); assert(reader.readInt64() == long.min);
    assert(readLength() == 8); assert(reader.readInt64() == 64);
    assert(readLength() == 8); assert(reader.readInt64() == long.max);

    assert(readLength() == 8); assert(reader.readMoney() == Decimal64("-92_000_000_000_000_000.00"));
    assert(readLength() == 8); assert(reader.readMoney() == Decimal64(0));
    assert(readLength() == 8); assert(reader.readMoney() == Decimal64.money(23456.78, 2));
    assert(readLength() == 8); assert(reader.readMoney() == Decimal64("9_200_000_000_000_000.00"));

    assert(readLength() >= 1); assert(reader.readNumeric!Decimal32() == Decimal32.min);
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal32() == Decimal32(0));
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal32() == Decimal32.money(12345.67, 2));
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal32() == Decimal32.max);

    assert(readLength() >= 1); assert(reader.readNumeric!Decimal64() == Decimal64.min);
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal64() == Decimal64(0));
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal64() == Decimal64.money(23456.78, 2));
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal64() == Decimal64.max);

    assert(readLength() >= 1); assert(reader.readNumeric!Decimal128() == Decimal128.min);
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal128() == Decimal128(0));
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal128() == Decimal128.money(34567.89, 2));
    assert(readLength() >= 1); assert(reader.readNumeric!Decimal128() == Decimal128.max);

    assert(readLength() == 8); assert(reader.readTime() == DbTime(Time(1,2,3)));
    assert(readLength() == 12); assert(reader.readTimeTZ() == DbTime(Time(1,2,3)));
    assert(readLength() == 16); assert(reader.readUUID() == uuid);
}
