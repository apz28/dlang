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

module pham.db.fbbuffer;

import std.algorithm.comparison : max, min;
import std.array : replicate;
import std.format : format;
import std.string : representation;
import std.system : Endian;
import std.typecons : Flag, No, Yes;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.db.message;
import pham.db.type;
import pham.db.util;
import pham.db.convert;
import pham.db.buffer;
import pham.db.value;
import pham.db.fbisc;
import pham.db.fbtype;
import pham.db.fbexception;
import pham.db.fbconvert;
import pham.db.fbdatabase;

class FbParameterWriteBuffer : DbWriteBuffer!(Endian.littleEndian)
{
@safe:

public:
    this(size_t capacity) nothrow
    {
        super(capacity);
    }
}

struct FbArrayWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._connection = connection;
        this._buffer = connection.acquireParameterWriteBuffer();
    }

    ~this() nothrow
    {
        dispose(false);
    }

    void dispose(bool disposing = true) nothrow
    {
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);

        _buffer = null;
        _connection = null;
    }

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

    void writeInt8(int8 v) nothrow
    {
        _buffer.writeInt8(v);
    }

    void writeInt16(int16 v) nothrow
    {
        _buffer.writeInt16(v);
    }

    void writeLiteral(int32 v) nothrow
    {
		if (v >= int8.min && v <= int8.max)
		{
            _buffer.writeUInt8(FbIsc.isc_sdl_tiny_integer);
            _buffer.writeInt8(cast(int8)v);
		}
		else if (v >= int16.min && v <= int16.max)
		{
            _buffer.writeUInt8(FbIsc.isc_sdl_short_integer);
            _buffer.writeInt16(cast(int16)v);
		}
        else
        {
            _buffer.writeUInt8(FbIsc.isc_sdl_long_integer);
            _buffer.writeInt32(v);
        }
    }

    void writeName(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length <= uint.max);
    }
    do
    {
        _buffer.writeUInt8(type);
        _buffer.writeUInt8(cast(uint8)v.length);
        _buffer.writeChars(v);
    }

    void writeUInt8(uint8 v) nothrow
    {
        _buffer.writeUInt8(v);
    }

private:
    IbWriteBuffer _buffer;
    FbConnection _connection;
}

struct FbBlrWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._connection = connection;
        this._buffer = connection.acquireParameterWriteBuffer();
    }

    ~this() nothrow
    {
        dispose(false);
    }

    void dispose(bool disposing = true) nothrow
    {
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);

        _buffer = null;
        _connection = null;
    }

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

    void writeBegin(size_t length) nothrow
    in
    {
        assert(length <= ushort.max / 2);
    }
    do
    {
	    _buffer.writeUInt8(FbIsc.blr_version);
	    _buffer.writeUInt8(FbIsc.blr_begin);
	    _buffer.writeUInt8(FbIsc.blr_message);
	    _buffer.writeUInt8(0);
	    _buffer.writeUInt16(cast(ushort)(length * 2));
    }

    void writeColumn(in DbBaseType baseType, int32 size) nothrow
    in
    {
        assert(size >= -1 && size <= uint16.max);
        assert(baseType.numericScale >= int8.min && baseType.numericScale <= uint8.max);
    }
    do
    {
	    final switch (FbIscFieldInfo.fbType(baseType.typeId))
	    {
		    case FbIscType.SQL_VARYING:
			    _buffer.writeUInt8(FbBlrType.blr_varying);
			    _buffer.writeUInt16(cast(ushort)size);
			    break;
		    case FbIscType.SQL_TEXT:
			    _buffer.writeUInt8(FbBlrType.blr_text);
			    _buffer.writeUInt16(cast(ushort)size);
			    break;
		    case FbIscType.SQL_DOUBLE:
			    _buffer.writeUInt8(FbBlrType.blr_double);
			    break;
		    case FbIscType.SQL_FLOAT:
			    _buffer.writeUInt8(FbBlrType.blr_float);
			    break;
		    case FbIscType.SQL_LONG:
			    _buffer.writeUInt8(FbBlrType.blr_long);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_SHORT:
			    _buffer.writeUInt8(FbBlrType.blr_short);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_TIMESTAMP:
			    _buffer.writeUInt8(FbBlrType.blr_timestamp);
			    break;
		    case FbIscType.SQL_BLOB:
			    _buffer.writeUInt8(FbBlrType.blr_quad);
			    _buffer.writeUInt8(0);
			    break;
		    case FbIscType.SQL_D_FLOAT:
			    _buffer.writeUInt8(FbBlrType.blr_d_float);
			    break;
		    case FbIscType.SQL_ARRAY:
			    _buffer.writeUInt8(FbBlrType.blr_quad);
			    _buffer.writeUInt8(0);
			    break;
		    case FbIscType.SQL_QUAD:
			    _buffer.writeUInt8(FbBlrType.blr_quad);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_TIME:
			    _buffer.writeUInt8(FbBlrType.blr_sql_time);
			    break;
		    case FbIscType.SQL_DATE:
			    _buffer.writeUInt8(FbBlrType.blr_sql_date);
			    break;
		    case FbIscType.SQL_INT64:
			    _buffer.writeUInt8(FbBlrType.blr_int64);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_INT128:
			    _buffer.writeUInt8(FbBlrType.blr_int128);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_TIMESTAMP_TZ:
			    _buffer.writeUInt8(FbBlrType.blr_timestamp_tz);
			    break;
		    case FbIscType.SQL_TIMESTAMP_TZ_EX:
			    _buffer.writeUInt8(FbBlrType.blr_ex_timestamp_tz);
			    break;
		    case FbIscType.SQL_TIME_TZ:
			    _buffer.writeUInt8(FbBlrType.blr_sql_time_tz);
			    break;
		    case FbIscType.SQL_TIME_TZ_EX:
			    _buffer.writeUInt8(FbBlrType.blr_ex_time_tz);
			    break;
		    /*
            case FbIscType.SQL_DEC_FIXED:
			    _buffer.writeUInt8(FbBlrType.blr_int128);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
            */
		    case FbIscType.SQL_DEC64:
			    _buffer.writeUInt8(FbBlrType.blr_dec64);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_DEC128:
			    _buffer.writeUInt8(FbBlrType.blr_dec128);
			    _buffer.writeUInt8(cast(ubyte)baseType.numericScale);
			    break;
		    case FbIscType.SQL_BOOLEAN:
			    _buffer.writeUInt8(FbBlrType.blr_bool);
			    break;
		    case FbIscType.SQL_NULL:
			    _buffer.writeUInt8(FbBlrType.blr_text);
			    _buffer.writeUInt16(cast(ushort)size);
			    break;
	    }
	    _buffer.writeUInt8(FbBlrType.blr_short);
	    _buffer.writeUInt8(0);
    }

    void writeEnd(size_t length) nothrow
    in
    {
        assert(length <= ushort.max / 2);
    }
    do
    {
    	_buffer.writeUInt8(FbIsc.blr_end);
	    _buffer.writeUInt8(FbIsc.blr_eoc);
    }

private:
    IbWriteBuffer _buffer;
    FbConnection _connection;
}

struct FbConnectionWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection, FbOperation versionId) nothrow
    {
        this._connection = connection;
        this._versionId = versionId;
        this._buffer = connection.acquireParameterWriteBuffer();
    }

    ~this() nothrow
    {
        dispose(false);
    }

    void dispose(bool disposing = true) nothrow
    {
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);

        _buffer = null;
        _connection = null;
    }

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

	void writeBytes(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length < uint32.max);
        assert(v.length <= uint8.max || versionId > FbIsc.isc_dpb_version1);
    }
    do
	{
        if (versionId <= FbIsc.isc_dpb_version1)
            v = truncate(v, uint8.max);

		_buffer.writeUInt8(type);
		writeLength(v.length);
        if (v.length)
		    _buffer.writeBytes(v);
	}

	void writeChars(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length <= uint8.max);
    }
    do
	{
		writeBytes(type, v.representation);
	}

	bool writeCharsIf(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length <= uint8.max);
    }
    do
	{
        if (v.length)
        {
		    writeBytes(type, v.representation);
            return true;
        }
        else
            return false;
	}

	void writeInt8(uint8 type, int8 v) nothrow
	{
		_buffer.writeUInt8(type);
		writeLength(1);
		_buffer.writeInt8(v);
	}

	void writeInt16(uint8 type, short v) nothrow
	{
		_buffer.writeUInt8(type);
		writeLength(2);
		_buffer.writeInt16(v);
	}

	void writeInt32(uint8 type, int v) nothrow
	{
		_buffer.writeUInt8(type);
        writeLength(4);
		_buffer.writeInt32(v);
	}

    void writeMultiParts(uint8 type, scope const(ubyte)[] v) nothrow
    {
        if (versionId > FbIsc.isc_dpb_version1)
            return writeBytes(type, v);

        uint8 partSequence = 0;
        while (v.length)
        {
            // -1=Reserve 1 byte for sequence
            auto partLength = cast(uint8)min(v.length, uint8.max - 1);

            _buffer.writeUInt8(type);
            _buffer.writeUInt8(cast(uint8)(partLength + 1)); // +1=Include the sequence
            _buffer.writeUInt8(partSequence);
            _buffer.writeBytes(v[0..partLength]);

            v = v[partLength..$];
            partSequence++;
            assert(v.length == 0 || partSequence > 0); // Check partSequence for wrap arround
        }
    }

    void writeType(uint8 type) nothrow
    {
        _buffer.writeUInt8(type);
    }

    @property FbOperation versionId() const nothrow
    {
        return _versionId;
    }

private:
    pragma(inline, true)
    void writeLength(size_t len) nothrow
    {
        if (versionId > FbIsc.isc_dpb_version1)
            _buffer.writeUInt32(cast(uint32)len);
        else
            _buffer.writeUInt8(cast(uint8)len);
    }

private:
    IbWriteBuffer _buffer;
    FbConnection _connection;
    FbOperation _versionId;
}

struct FbTransactionWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._connection = connection;
        this._buffer = connection.acquireParameterWriteBuffer();
    }

    ~this() nothrow
    {
        dispose(false);
    }

    void dispose(bool disposing = true) nothrow
    {
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);

        _buffer = null;
        _connection = null;
    }

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

	void writeBytes(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length <= uint8.max);
    }
    do
	{
        v = truncate(v, uint8.max);
        const vLen = cast(uint8)v.length;

		_buffer.writeUInt8(type);
		_buffer.writeUInt8(vLen);
        if (vLen)
		    _buffer.writeBytes(v);
	}

	void writeChars(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length <= uint8.max);
    }
    do
	{
		writeBytes(type, v.representation);
	}

	void writeInt16(uint8 type, int16 v) nothrow
	{
		_buffer.writeUInt8(type);
		_buffer.writeUInt8(2);
		_buffer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		_buffer.writeUInt8(type);
		_buffer.writeUInt8(4);
		_buffer.writeInt32(v);
	}

    void writeType(uint8 type) nothrow
    {
        _buffer.writeUInt8(type);
    }

private:
    IbWriteBuffer _buffer;
    FbConnection _connection;
}

struct FbXdrReader
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection, ubyte[] bufferData = null)
    {
        this._connection = connection;
        this._connectionBuffer = bufferData.length == 0;
        this._readBuffer = this._connectionBuffer
            ? connection.acquireSocketReadBuffer()
            : new DbReadBuffer(bufferData);
        this._reader = DbValueReader!(Endian.bigEndian)(this._readBuffer);
    }

    void dispose(bool disposing = true)
    {
        _readBuffer = null;
        _connection = null;
        _connectionBuffer = false;
        _reader.dispose(disposing);
    }

    bool readBool()
    {
        auto result = _reader.readBool();
        readPad(1);
        return result;
    }

    ubyte[] readBytes()
    {
        const nBytes = _reader.readUInt32();
        auto result = _reader.readBytes(nBytes);
        readPad(nBytes);
        return result;
    }

    char[] readChars() @trusted // @trusted=cast()
    {
        return cast(char[])readBytes();
    }

    Date readDate()
    {
        return dateDecode(readInt32());
    }

    DbDateTime readDateTime()
    {
        int32 d = void, t = void;
        _reader.readTwoInt32(d, t);
        return dateTimeDecode(d, t);
    }

    DbDateTime readDateTimeTZ()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        auto d = readInt32();
        auto t = readInt32();
        auto zId = readUInt16();
        return dateTimeDecodeTZ(d, t, zId, notUseZoneOffset);
    }

    DbDateTime readDateTimeTZEx()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        auto d = readInt32();
        auto t = readInt32();
        auto zId = readUInt16();
        auto zOffset = readInt16();
        return dateTimeDecodeTZ(d, t, zId, zOffset);
    }

    D readDecimal(D)(in DbBaseType baseType)
    if (isDecimal!D)
    {
		switch (FbIscFieldInfo.fbType(baseType.typeId))
		{
			case FbIscType.SQL_SHORT:
				return decimalDecode!(D, int16)(readInt16(), baseType.numericScale);
			case FbIscType.SQL_LONG:
				return decimalDecode!(D, int32)(readInt32(), baseType.numericScale);
			case FbIscType.SQL_QUAD:
			case FbIscType.SQL_INT64:
				return decimalDecode!(D, int64)(readInt64(), baseType.numericScale);
			case FbIscType.SQL_DOUBLE:
			case FbIscType.SQL_D_FLOAT:
				return decimalDecode!(D, float64)(readFloat64(), baseType.numericScale);
    		case FbIscType.SQL_FLOAT:
				return decimalDecode!(D, float32)(readFloat32(), baseType.numericScale);
            case FbIscType.SQL_DEC64:
            case FbIscType.SQL_DEC128:
                auto bytes = _reader.readBytes(decimalByteLength!D());
                return decimalDecode!D(bytes);
			default:
                assert(0);
		}
    }

    char[] readFixedChars(in DbBaseType baseType) @trusted // @trusted=cast()
    {
        const charsCount = baseType.size / 4; // UTF8 to char
        auto result = cast(char[])readOpaqueBytes(baseType.size);
        return truncateEndIf(result, charsCount, ' ');
    }

    string readFixedString(in DbBaseType baseType) @trusted // @trusted=cast()
    {
        return cast(string)readFixedChars(baseType);
    }

    float32 readFloat32()
    {
        return _reader.readFloat32();
    }

    float64 readFloat64()
    {
        return _reader.readFloat64();
    }

    FbHandle readHandle()
    {
        assert(FbHandle.sizeof == uint32.sizeof);

        return _reader.readUInt32();
    }

    FbId readId()
    {
        static assert(int64.sizeof == FbId.sizeof);

        return _reader.readInt64();
    }

    int16 readInt16()
    {
        return cast(int16)_reader.readInt32();
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
        ubyte[int128ByteLength] buffer = void;
        return int128Decode(_reader.readBytes(buffer[]));
    }

    ubyte[] readOpaqueBytes(const size_t forLength)
    {
        auto result = _reader.readBytes(forLength);
        readPad(forLength);
        return result;
    }

    FbOperation readOperation()
    {
        version (TraceFunction) dgFunctionTrace();

        static assert(int32.sizeof == FbOperation.sizeof);

        while (true)
        {
            auto result = readInt32();

            version (TraceFunction) dgFunctionTrace("code=", result);

            if (result != FbIsc.op_dummy)
                return result;
        }
    }

    FbOperation readOperation(FbOperation expectedOperation) @trusted
    {
        auto result = readOperation();
        if (result != expectedOperation)
        {
            auto msg = format(DbMessage.eUnexpectReadOperation, result, expectedOperation);
            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_net_read_err);
        }
        return result;
    }

    string readString() @trusted // @trusted=cast()
    {
        return cast(string)readChars();
    }

    FbIscStatues readStatuses() @trusted
    {
        version (TraceFunction) dgFunctionTrace();

        FbIscStatues result;
        int gdsCode;
        int numArg;

        bool done;
        while (!done)
        {
			auto typeCode = readInt32();

            version (TraceFunction) dgFunctionTrace("typeCode=", typeCode);

			switch (typeCode)
			{
				case FbIsc.isc_arg_end:
					done = true;
					break;

				case FbIsc.isc_arg_number:
                    auto numParam = readInt32();
                    ++numArg;
                    if (gdsCode == 335544436)
				        result.sqlCode = numParam;
					result.put(FbIscError(typeCode, numParam, numArg));
					break;

				case FbIsc.isc_arg_string:
                case FbIsc.isc_arg_cstring:
                    auto msg = readString();
                    ++numArg;
                    result.put(FbIscError(typeCode, msg, numArg));
                    break;

				case FbIsc.isc_arg_interpreted:
                    auto msg = readString();
                    result.put(FbIscError(typeCode, msg, -1));
                    break;

                //case FbIsc.isc_arg_warning:
				case FbIsc.isc_arg_sql_state:
                    auto msg = readString();
					result.put(FbIscError(typeCode, msg, -1));
					break;

				case FbIsc.isc_arg_gds:
                default:
                    gdsCode = readInt32();
                    if (gdsCode != 0)
                    {
                        result.put(FbIscError(typeCode, gdsCode, -1));
				        numArg = 0;
                    }
                    break;
			}
        }

        return result;
    }

    DbTime readTime()
    {
        return timeDecode(readInt32());
    }

    DbTime readTimeTZ()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        auto t = readInt32();
        auto zId = readUInt16();
        return timeDecodeTZ(t, zId, notUseZoneOffset);
    }

    DbTime readTimeTZEx()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        auto t = readInt32();
        auto zId = readUInt16();
        auto zOffset = readInt16();
        return timeDecodeTZ(t, zId, zOffset);
    }

    uint16 readUInt16()
    {
        return cast(uint16)_reader.readUInt32();
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    UUID readUUID()
    {
        static assert(UUID.sizeof == 16);

        ubyte[UUID.sizeof] buffer = void;
        return UUID(_reader.readBytes(buffer[])[0..UUID.sizeof]);
    }

    @property FbConnection connection() nothrow pure
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
    pragma (inline, true)
    void readPad(const ptrdiff_t nBytes)
    {
        const paddingNBytes = (4 - nBytes) & 3;
        if (paddingNBytes)
            _readBuffer.advance(paddingNBytes);
    }

private:
    FbConnection _connection;
    DbReadBuffer _readBuffer;
    DbValueReader!(Endian.bigEndian) _reader;
    bool _connectionBuffer;
}

struct FbXdrWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection,
        IbWriteBuffer buffer = null)
    {
        this._connection = connection;
        this._buffer = buffer;
        this._socketBuffer = buffer is null;
        if (this._socketBuffer)
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

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

    void writeBlob(scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
    }
    do
    {
        const len = cast(ushort)v.length;
        // Bizarre with three copies of the length
        writeInt32(len);
        writeInt32(len);
        _buffer.writeUInt16(len);
        _buffer.writeBytes(v);
        writePad(len + 2);
    }

    void writeBool(bool v) nothrow
    {
        _buffer.writeBool(v);
        writePad(1);
    }

    void writeBytes(scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
    }
    do
    {
        const nBytes = cast(int32)v.length;
        _buffer.writeInt32(nBytes);
        _buffer.writeBytes(v);
        writePad(nBytes);
    }

    void writeChars(scope const(char)[] v) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
    }
    do
    {
        writeBytes(v.representation);
    }

    void writeDate(in Date v) nothrow
    {
        writeInt32(dateEncode(v));
    }

    void writeDateTime(in DbDateTime v) nothrow
    {
        int32 d, t = void;
        dateTimeEncode(v, d, t);
        writeInt32(d);
        writeInt32(t);
    }

    void writeDateTimeTZ(in DbDateTime v) nothrow
    {
        int32 d, t = void;
        uint16 zId = void;
        int16 zOffset = void;
        dateTimeEncodeTZ(v, d, t, zId, zOffset);
        writeInt32(d);
        writeInt32(t);
        writeUInt16(zId);
    }

    void writeDateTimeTZEx(in DbDateTime v) nothrow
    {
        int32 d, t = void;
        uint16 zId = void;
        int16 zOffset = void;
        dateTimeEncodeTZ(v, d, t, zId, zOffset);
        writeInt32(d);
        writeInt32(t);
        writeUInt16(zId);
        writeInt16(zOffset);
    }

    void writeDecimal(D)(in D v, in DbBaseType baseType)
    if (isDecimal!D)
    {
		switch (FbIscFieldInfo.fbType(baseType.typeId))
		{
			case FbIscType.SQL_SHORT:
				return writeInt16(decimalEncode!(D, int16)(v, baseType.numericScale));
			case FbIscType.SQL_LONG:
				return writeInt32(decimalEncode!(D, int32)(v, baseType.numericScale));
			case FbIscType.SQL_QUAD:
			case FbIscType.SQL_INT64:
				return writeInt64(decimalEncode!(D, int64)(v, baseType.numericScale));
			case FbIscType.SQL_DOUBLE:
			case FbIscType.SQL_D_FLOAT:
				return writeFloat64(decimalEncode!(D, float64)(v, baseType.numericScale));
    		case FbIscType.SQL_FLOAT:
				return writeFloat32(decimalEncode!(D, float32)(v, baseType.numericScale));
            case FbIscType.SQL_DEC64:
            case FbIscType.SQL_DEC128:
                _buffer.writeBytes(decimalEncode!D(v));
                return;
			default:
                assert(0);
		}
    }

    void writeFixedChars(scope const(char)[] v, in DbBaseType baseType) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
        assert(baseType.size < fbMaxPackageSize);
    }
    do
    {
        _buffer.writeBytes(v.representation);
        if (baseType.size > v.length)
        {
            writeFiller!(Yes.IsSpace)(baseType.size - v.length);
            writePad(baseType.size);
        }
        else
            writePad(v.length);
    }

    void writeFloat32(float32 v) nothrow
    {
        _buffer.writeFloat32(v);
    }

    void writeFloat64(float64 v) nothrow
    {
        _buffer.writeFloat64(v);
    }

    void writeHandle(FbHandle handle) nothrow
    {
        static assert(uint32.sizeof == FbHandle.sizeof);

        _buffer.writeUInt32(cast(uint32)handle);
    }

    void writeId(FbId id) nothrow
    {
        static assert(int64.sizeof == FbId.sizeof);

        _buffer.writeInt64(cast(int64)id);
    }

    void writeInt16(int16 v) nothrow
    {
        _buffer.writeInt32(v);
    }

    void writeInt32(int32 v) nothrow
    {
        _buffer.writeInt32(v);
    }

    static if (size_t.sizeof > int32.sizeof)
    void writeInt32(size_t v) nothrow
    in
    {
        assert(v < int32.max);
    }
    do
    {
        _buffer.writeInt32(cast(int32)v);
    }

    void writeInt64(int64 v) nothrow
    {
        _buffer.writeInt64(v);
    }

    void writeInt128(in BigInteger v) nothrow
    {
        ubyte[int128ByteLength] bytes;
        const e = int128Encode(v, bytes);
        assert(e);
        _buffer.writeBytes(bytes);
    }

    void writeOpaqueBytes(scope const(ubyte)[] v, size_t forLength) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
        assert(forLength < fbMaxPackageSize);
    }
    do
    {
        _buffer.writeBytes(v);
        if (forLength > v.length)
        {
            writeFiller!(No.IsSpace)(forLength - v.length);
            writePad(forLength);
        }
        else
            writePad(v.length);
    }

    void writeOperation(FbOperation operation) nothrow
    {
        static assert(int32.sizeof == FbOperation.sizeof);

        writeInt32(cast(int32)operation);
    }

    void writeTime(in DbTime v) nothrow
    {
        writeInt32(timeEncode(v));
    }

    void writeTimeTZ(in DbTime v) nothrow
    {
        int32 t = void;
        uint16 zId = void;
        int16 zOffset = void;
        timeEncodeTZ(v, t, zId, zOffset);
        writeInt32(t);
        writeUInt16(zId);
    }

    void writeTimeTZEx(in DbTime v) nothrow
    {
        int32 t = void;
        uint16 zId = void;
        int16 zOffset = void;
        timeEncodeTZ(v, t, zId, zOffset);
        writeInt32(t);
        writeUInt16(zId);
        writeInt16(zOffset);
    }

    void writeUInt16(uint16 v) nothrow
    {
        _buffer.writeUInt32(v);
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    void writeUUID(in UUID v) nothrow
    {
        _buffer.writeBytes(v.data); // v.data is already in big-endian
        //return writePad(16); // No need filler since alignment to 4
    }

    @property FbConnection connection() nothrow
    {
        return _connection;
    }

private:
    void writeFiller(Flag!"IsSpace" IsSpace)(ptrdiff_t nBytes) nothrow
    {
        enum fillerLenght = 1024;
        static if (IsSpace)
        {
            static immutable ubyte[fillerLenght] spaceFiller = replicate([32], fillerLenght);
            alias writeFiller = spaceFiller;
        }
        else
        {
            static immutable ubyte[fillerLenght] zeroFiller; // Compiler fill in default value
            alias writeFiller = zeroFiller;
        }

        while (nBytes)
        {
            const writeBytes = nBytes > fillerLenght ? fillerLenght : nBytes;
            _buffer.writeBytes(writeFiller[0..writeBytes]);
            nBytes -= writeBytes;
        }
    }

    void writePad(ptrdiff_t nBytes) nothrow
    {
        immutable ubyte[4] filler = [0, 0, 0, 0];

        const paddingNBytes = (4 - nBytes) & 3;
        if (paddingNBytes != 0)
            _buffer.writeBytes(filler[0..paddingNBytes]);
    }

private:
    IbWriteBuffer _buffer;
    FbConnection _connection;
    bool _socketBuffer;
}


// Any below codes are private
private:

unittest // FbXdrWriter & FbXdrReader
{
    import pham.utl.test;
    traceUnitTest("unittest db.fbbuffer.FbXdrReader & db.fbbuffer.FbXdrWriter");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer!(Endian.bigEndian)(4000);
    auto writer = FbXdrWriter(null, writerBuffer);
    writer.writeBool(true);
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

    ubyte[] bytes = writer.peekBytes();
    auto reader = FbXdrReader(null, bytes);
    assert(reader.readBool());
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
    assert(reader.readChars() == chars);
}
