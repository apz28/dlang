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
import std.string : representation;
import std.system : Endian;
import std.typecons : Flag, No, Yes;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.external.dec.decimal : scaleFrom, scaleTo;
import pham.utl.disposable : DisposingReason, isDisposing;
import pham.utl.utf8 : ShortStringBuffer;
import pham.db.buffer;
import pham.db.convert;
import pham.db.type;
import pham.db.util;
import pham.db.fbconvert;
import pham.db.fbdatabase;
import pham.db.fbisc;
import pham.db.fbtype;

alias FbParameterWriter = DbValueWriter!(Endian.littleEndian);

struct FbArrayWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._connection = connection;
        this._buffer = connection.acquireParameterWriteBuffer();
        this._writer = FbParameterWriter(this._buffer);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _writer.dispose(disposingReason);
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    ubyte[] peekBytes() nothrow
    {
        return _buffer.peekBytes();
    }

    void writeInt8(int8 v) nothrow
    {
        _writer.writeInt8(v);
    }

    void writeInt16(int16 v) nothrow
    {
        _writer.writeInt16(v);
    }

    void writeLiteral(int32 v) nothrow
    {
		if (v >= int8.min && v <= int8.max)
		{
            _writer.writeUInt8(FbIsc.isc_sdl_tiny_integer);
            _writer.writeInt8(cast(int8)v);
		}
		else if (v >= int16.min && v <= int16.max)
		{
            _writer.writeUInt8(FbIsc.isc_sdl_short_integer);
            _writer.writeInt16(cast(int16)v);
		}
        else
        {
            _writer.writeUInt8(FbIsc.isc_sdl_long_integer);
            _writer.writeInt32(v);
        }
    }

    void writeName(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length < uint32.max);
    }
    do
    {
        _writer.writeUInt8(type);
        _writer.writeUInt8(cast(uint8)v.length);
        _writer.writeChars(v);
    }

    void writeUInt8(uint8 v) nothrow
    {
        _writer.writeUInt8(v);
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    FbParameterWriter _writer;
}

struct FbBatchWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection, uint8 versionId) nothrow
    {
        this._connection = connection;
        this._versionId = versionId;
        this._buffer = connection.acquireParameterWriteBuffer();
        this._writer = FbParameterWriter(this._buffer);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _writer.dispose(disposingReason);
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    ubyte[] peekBytes() nothrow
    {
        return _buffer.peekBytes();
    }

	void writeBytes(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length < uint32.max);
    }
    do
	{
		_writer.writeUInt8(type);
		_writer.writeUInt32(v.length);
        if (v.length)
		    _writer.writeBytes(v);
	}

	void writeChars(uint8 type, scope const(char)[] v) nothrow
	{
        auto bytes = v.representation;
		writeBytes(type, bytes);
	}

	bool writeCharsIf(uint8 type, scope const(char)[] v) nothrow
	{
        if (v.length)
        {
		    writeChars(type, v);
            return true;
        }
        else
            return false;
	}

	void writeInt8(uint8 type, int8 v) nothrow
	{
		_writer.writeUInt8(type);
		_writer.writeUInt32(1); // length
		_writer.writeInt8(v);
	}

	void writeInt16(uint8 type, int16 v) nothrow
	{
		_writer.writeUInt8(type);
		_writer.writeUInt32(2); // length
		_writer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		_writer.writeUInt8(type);
        _writer.writeUInt32(4); // length
		_writer.writeInt32(v);
	}

    pragma(inline, true)
    void writeOpaqueUInt8(uint8 v) nothrow
    {
        _writer.writeUInt8(v);
    }

    pragma(inline, true)
    void writeVersion() nothrow
    {
        _writer.writeUInt8(versionId);
    }

    @property uint8 versionId() const nothrow pure
    {
        return _versionId;
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    FbParameterWriter _writer;
    uint8 _versionId;
}

enum FbBlrWriteType
{
    base,
    null_,
    array,
}

struct FbBlrWriter
{
@safe:

public:
    @disable this(this);

    this(DbWriteBuffer buffer) nothrow pure
    {
        this._connection = null;
        this._buffer = buffer;
        this._writer = FbParameterWriter(buffer);
    }

    this(FbConnection connection) nothrow
    {
        DbWriteBuffer conBuffer = connection.acquireParameterWriteBuffer();
        this._connection = connection;
        this._buffer = conBuffer;
        this._writer = FbParameterWriter(conBuffer);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _writer.dispose(disposingReason);
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    ubyte[] peekBytes() nothrow
    {
        return _buffer.peekBytes();
    }

    void writeBegin(size_t length) nothrow
    in
    {
        assert(length <= uint16.max / 2); // Max number of columns
    }
    do
    {
	    _writer.writeUInt8(FbIsc.blr_version);
	    _writer.writeUInt8(FbIsc.blr_begin);
	    _writer.writeUInt8(FbIsc.blr_message);
	    _writer.writeUInt8(0);
	    _writer.writeUInt16(cast(uint16)(length * 2));
    }

    void writeColumn(scope const(DbBaseType) baseType, ref FbIscBlrDescriptor descriptor) nothrow
    in
    {
        assert(baseType.size >= -1 && baseType.size <= uint16.max);
        assert(baseType.numericScale >= int8.min && baseType.numericScale <= int8.max);
    }
    do
    {
        const fbType = FbIscFieldInfo.fbType(baseType.typeId);
        const writeTypeFor = fbType == FbIscType.sql_null
            ? FbBlrWriteType.null_
            : (fbType == FbIscType.sql_array ? FbBlrWriteType.array : FbBlrWriteType.base);

        writeType(FbIscFieldInfo.fbTypeToBlrType(fbType), baseType, writeTypeFor, descriptor);

	    _writer.writeUInt8(FbBlrType.blr_short);
	    _writer.writeUInt8(0);
        descriptor.addSize(2, 2);
    }

    void writeEnd(size_t length) nothrow
    in
    {
        assert(length <= uint16.max / 2); // Max number of columns
    }
    do
    {
    	_writer.writeUInt8(FbIsc.blr_end);
	    _writer.writeUInt8(FbIsc.blr_eoc);
    }

    void writeType(FbBlrType blrType, scope const(DbBaseType) baseType, const(FbBlrWriteType) writeTypeFor,
        ref FbIscBlrDescriptor descriptor) nothrow
    in
    {
        assert(baseType.size >= -1 && baseType.size <= uint16.max);
        assert(baseType.numericScale >= int8.min && baseType.numericScale <= int8.max);
    }
    do
    {
        if (writeTypeFor == FbBlrWriteType.null_)
        {
            const size = cast(int16)baseType.size;
			_writer.writeUInt8(FbBlrType.blr_text);
			_writer.writeInt16(size);
            descriptor.addSize(0, size);
            return;
        }
        else if (writeTypeFor == FbBlrWriteType.array)
        {
			_writer.writeUInt8(FbBlrType.blr_quad);
			_writer.writeInt8(0);
            descriptor.addSize(4, 8);
            return;
        }

        assert(writeTypeFor == FbBlrWriteType.base);

        // Mapping
        if (blrType == FbBlrType.blr_text)
            blrType = FbBlrType.blr_text2;
        else if (blrType == FbBlrType.blr_blob)
            blrType = FbBlrType.blr_blob2;
        else if (blrType == FbBlrType.blr_varying)
            blrType = FbBlrType.blr_varying2;
        else if (blrType == FbBlrType.blr_cstring)
            blrType = FbBlrType.blr_cstring2;

        // Type
		_writer.writeUInt8(blrType);

	    final switch (blrType) with (FbBlrType)
	    {
            case blr_short:
			    _writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(2, 2);
			    break;

            case blr_long:
			    _writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(4, 4);
			    break;

            case blr_quad:
			    _writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(4, 8);
			    break;

            case blr_float:
                descriptor.addSize(4, 4);
			    break;

            case blr_d_float:
            case blr_double:
                descriptor.addSize(8, 8);
			    break;

            case blr_date:
            case blr_time:
                descriptor.addSize(4, 4);
			    break;

            case blr_text:
            case blr_text2:
                const size = cast(int16)baseType.size;
			    _writer.writeInt16(cast(int16)baseType.subTypeId); // charset
			    _writer.writeInt16(size);
                descriptor.addSize(0, size);
			    break;

            case blr_int64:
			    _writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(8, 8);
			    break;

            case blr_blob2:
            case blr_blob:
			    _writer.writeInt16(cast(int16)baseType.subTypeId);
			    _writer.writeInt16(0); // charset
                descriptor.addSize(4, 8);
			    break;

            case blr_bool:
                descriptor.addSize(0, 1);
			    break;

            case blr_dec16:
                descriptor.addSize(8, 8);
			    break;

            case blr_dec34:
                descriptor.addSize(8, 16);
			    break;

            case blr_int128:
			    _writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(8, 16);
			    break;

            case blr_time_tz:
                descriptor.addSize(4, 6);
			    break;

            case blr_timestamp_tz:
                descriptor.addSize(4, 10);
			    break;

            case blr_ex_time_tz:
                descriptor.addSize(4, 8);
			    break;

            case blr_ex_timestamp_tz:
                descriptor.addSize(4, 12);
			    break;

            case blr_timestamp:
                descriptor.addSize(4, 8);
			    break;

            case blr_varying:
            case blr_varying2:
            case blr_cstring:
            case blr_cstring2:
                const size = cast(int16)baseType.size;
			    _writer.writeInt16(cast(int16)baseType.subTypeId); // charset
			    _writer.writeInt16(size);
                descriptor.addSize(2, size + 2);
			    break;

            case blr_blob_id:
                assert(0);
	    }
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    FbParameterWriter _writer;
}

struct FbConnectionWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection, uint8 versionId) nothrow
    {
        this._connection = connection;
        this._versionId = versionId;
        this._buffer = connection.acquireParameterWriteBuffer();
        this._writer = FbParameterWriter(this._buffer);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _writer.dispose(disposingReason);
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    ubyte[] peekBytes() nothrow
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

		_writer.writeUInt8(type);
		writeLength(v.length);
        if (v.length)
		    _writer.writeBytes(v);
	}

	void writeChars(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length < uint32.max);
        assert(v.length <= uint8.max || versionId > FbIsc.isc_dpb_version1);
    }
    do
	{
        auto bytes = v.representation;
		writeBytes(type, bytes);
	}

	bool writeCharsIf(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length < uint32.max);
        assert(v.length <= uint8.max || versionId > FbIsc.isc_dpb_version1);
    }
    do
	{
        if (v.length)
        {
		    writeChars(type, v);
            return true;
        }
        else
            return false;
	}

	void writeInt8(uint8 type, int8 v) nothrow
	{
		_writer.writeUInt8(type);
		writeLength(1);
		_writer.writeInt8(v);
	}

	void writeInt16(uint8 type, int16 v) nothrow
	{
		_writer.writeUInt8(type);
		writeLength(2);
		_writer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		_writer.writeUInt8(type);
        writeLength(4);
		_writer.writeInt32(v);
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

            _writer.writeUInt8(type);
            _writer.writeUInt8(cast(uint8)(partLength + 1)); // +1=Include the sequence
            _writer.writeUInt8(partSequence);
            _writer.writeBytes(v[0..partLength]);

            v = v[partLength..$];
            partSequence++;
            assert(v.length == 0 || partSequence > 0); // Check partSequence for wrap arround
        }
    }

    pragma(inline, true)
    void writeOpaqueUInt8(uint8 v) nothrow
    {
        _writer.writeUInt8(v);
    }

    pragma(inline, true)
    void writeVersion() nothrow
    {
        _writer.writeUInt8(versionId);
    }

    @property uint8 versionId() const nothrow pure
    {
        return _versionId;
    }

private:
    pragma(inline, true)
    void writeLength(size_t len) nothrow
    {
        if (versionId > FbIsc.isc_dpb_version1)
            _writer.writeUInt32(len);
        else
            _writer.writeUInt8(len);
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    FbParameterWriter _writer;
    uint8 _versionId;
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
        this._writer = FbParameterWriter(this._buffer);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _writer.dispose(disposingReason);
        if (_buffer !is null && _connection !is null)
            _connection.releaseParameterWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    ubyte[] peekBytes() nothrow
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
        const vLen = v.length;

		_writer.writeUInt8(type);
		_writer.writeUInt8(vLen);
        if (vLen)
		    _writer.writeBytes(v);
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
		_writer.writeUInt8(type);
		_writer.writeUInt8(2);
		_writer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		_writer.writeUInt8(type);
		_writer.writeUInt8(4);
		_writer.writeInt32(v);
	}

    pragma(inline, true)
    void writeOpaqueUInt8(uint8 v) nothrow
    {
        _writer.writeUInt8(v);
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    FbParameterWriter _writer;
}

struct FbXdrReader
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._connectionBuffer = true;
        this._connection = connection;
        this._buffer = connection.acquireSocketReadBuffer();
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);
    }

    this(FbConnection connection, ubyte[] bufferData) nothrow
    {
        this._connectionBuffer = false;
        this._connection = connection;
        this._buffer = new DbReadBuffer(bufferData);
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _reader.dispose(disposingReason);
        _buffer = null;
        _connectionBuffer = false;
        if (isDisposing(disposingReason))
            _connection = null;
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

    pragma(inline, true)
    char[] readChars() @trusted // @trusted=cast()
    {
        return cast(char[])readBytes();
    }

    DbDate readDate()
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

    D readDecimal(D)(scope const(DbBaseType) baseType)
    if (isDecimal!D)
    {
		switch (FbIscFieldInfo.fbType(baseType.typeId))
		{
			case FbIscType.sql_short:
				return scaleFrom!(int16, D)(readInt16(), baseType.numericScale);
			case FbIscType.sql_long:
				return scaleFrom!(int32, D)(readInt32(), baseType.numericScale);
			case FbIscType.sql_quad:
			case FbIscType.sql_int64:
				return scaleFrom!(int64, D)(readInt64(), baseType.numericScale);
			case FbIscType.sql_double:
			case FbIscType.sql_d_float:
				return D(readFloat64());
    		case FbIscType.sql_float:
				return D(readFloat32());
            case FbIscType.sql_dec16:
            case FbIscType.sql_dec34:
                assert(decimalByteLength!D() == 8 || decimalByteLength!D() == 16);
                auto bytes = _reader.readBytes(decimalByteLength!D());
                return decimalDecode!D(bytes);
			default:
                assert(0);
		}
    }

    char[] readFixedChars(scope const(DbBaseType) baseType) @trusted // @trusted=cast()
    {
        const charsCount = baseType.size / 4; // UTF8 to char
        auto result = cast(char[])readOpaqueBytes(baseType.size);
        return truncateEndIf(result, charsCount, ' ');
    }

    string readFixedString(scope const(DbBaseType) baseType) @trusted // @trusted=cast()
    {
        return cast(string)readFixedChars(baseType);
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

    pragma(inline, true)
    FbHandle readHandle()
    {
        static assert(FbHandle.sizeof == uint32.sizeof);

        return _reader.readUInt32();
    }

    pragma(inline, true)
    FbId readId()
    {
        static assert(int64.sizeof == FbId.sizeof);

        return _reader.readInt64();
    }

    pragma(inline, true)
    int16 readInt16()
    {
        return cast(int16)_reader.readInt32();
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
        ubyte[int128ByteLength] buffer = void;
        return int128Decode(_reader.readBytes(buffer[]));
    }

    ubyte[] readOpaqueBytes(const(size_t) forLength)
    {
        auto result = _reader.readBytes(forLength);
        readPad(forLength);
        return result;
    }

    FbOperation readOperation()
    {
        version (TraceFunctionReader) traceFunction!("pham.db.fbdatabase")();

        static assert(int32.sizeof == FbOperation.sizeof);

        while (true)
        {
            auto result = readInt32();

            version (TraceFunctionReader) traceFunction!("pham.db.fbdatabase")("code=", result);

            if (result != FbIsc.op_dummy)
                return result;
        }
    }

    string readString() @trusted // @trusted=cast()
    {
        return cast(string)readChars();
    }

    FbIscStatues readStatuses() @trusted
    {
        version (TraceFunctionReader) traceFunction!("pham.db.fbdatabase")();

        FbIscStatues result;
        int gdsCode;
        int numArg;

        bool done;
        while (!done)
        {
			auto typeCode = readInt32();

            version (TraceFunctionReader) traceFunction!("pham.db.fbdatabase")("typeCode=", typeCode);

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

    pragma(inline, true)
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

    @property DbReadBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property FbConnection connection() nothrow pure
    {
        return _connection;
    }

    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _buffer.empty;
    }

private:
    pragma (inline, true)
    void readPad(const(ptrdiff_t) nBytes)
    {
        const paddingNBytes = (4 - nBytes) & 3;
        if (paddingNBytes)
            _reader.advance(paddingNBytes);
    }

private:
    DbReadBuffer _buffer;
    FbConnection _connection;
    DbValueReader!(Endian.bigEndian) _reader;
    bool _connectionBuffer;
}

struct FbXdrWriter
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._socketBuffer = true;
        this._connection = connection;
        this._buffer = connection.acquireSocketWriteBuffer();
        this._writer = DbValueWriter!(Endian.bigEndian)(this._buffer);
    }

    this(FbConnection connection, DbWriteBuffer buffer) nothrow
    {
        buffer.reset();
        this._socketBuffer = false;
        this._connection = connection;
        this._buffer = buffer;
        this._writer = DbValueWriter!(Endian.bigEndian)(buffer);
    }

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _writer.dispose(disposingReason);
        if (_socketBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    void flush()
    {
        version (TraceFunctionWriter) traceFunction!("pham.db.fbdatabase")();

        _buffer.flush();
    }

    pragma(inline, true)
    ubyte[] peekBytes() nothrow
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
        const len = cast(uint16)v.length;

        // Bizarre with three copies of the length
        writeInt32(cast(int32)len);
        writeInt32(cast(int32)len);
        _writer.writeUInt16(len);
        _writer.writeBytes(v);
        writePad(len + 2);
    }

    pragma(inline, true)
    void writeBool(bool v) nothrow
    {
        _writer.writeBool(v);
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
        _writer.writeInt32(nBytes);
        _writer.writeBytes(v);
        writePad(nBytes);
    }

    pragma(inline, true)
    void writeChars(scope const(char)[] v) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
    }
    do
    {
        writeBytes(v.representation);
    }

    void writeDate(scope const(DbDate) v) nothrow
    {
        writeInt32(dateEncode(v));
    }

    void writeDateTime(scope const(DbDateTime) v) nothrow
    {
        int32 d, t = void;
        dateTimeEncode(v, d, t);
        writeInt32(d);
        writeInt32(t);
    }

    void writeDateTimeTZ(scope const(DbDateTime) v) nothrow
    {
        int32 d, t = void;
        uint16 zId = void;
        int16 zOffset = void;
        dateTimeEncodeTZ(v, d, t, zId, zOffset);
        writeInt32(d);
        writeInt32(t);
        writeUInt16(zId);
    }

    void writeDateTimeTZEx(scope const(DbDateTime) v) nothrow
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

    void writeDecimal(D)(scope const(D) v, scope const(DbBaseType) baseType)
    if (isDecimal!D)
    {
		switch (FbIscFieldInfo.fbType(baseType.typeId))
		{
			case FbIscType.sql_short:
				return writeInt16(scaleTo!(D, int16)(v, baseType.numericScale));
			case FbIscType.sql_long:
				return writeInt32(scaleTo!(D, int32)(v, baseType.numericScale));
			case FbIscType.sql_quad:
			case FbIscType.sql_int64:
				return writeInt64(scaleTo!(D, int64)(v, baseType.numericScale));
			case FbIscType.sql_double:
			case FbIscType.sql_d_float:
				return writeFloat64(cast(float64)v);
    		case FbIscType.sql_float:
				return writeFloat32(cast(float32)v);
            case FbIscType.sql_dec16:
            case FbIscType.sql_dec34:
                ShortStringBuffer!ubyte buffer;
                _writer.writeBytes(decimalEncode!D(buffer, v)[]);
                return;
			default:
                assert(0);
		}
    }

    void writeFixedChars(scope const(char)[] v, scope const(DbBaseType) baseType) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
        assert(baseType.size < fbMaxPackageSize);
    }
    do
    {
        _writer.writeBytes(v.representation);
        if (baseType.size > v.length)
        {
            writeFiller!(Yes.IsSpace)(baseType.size - v.length);
            writePad(baseType.size);
        }
        else
            writePad(v.length);
    }

    pragma(inline, true)
    void writeFloat32(float32 v) nothrow
    {
        _writer.writeFloat32(v);
    }

    pragma(inline, true)
    void writeFloat64(float64 v) nothrow
    {
        _writer.writeFloat64(v);
    }

    pragma(inline, true)
    void writeHandle(FbHandle handle) nothrow
    {
        static assert(uint32.sizeof == FbHandle.sizeof);
        version (TraceFunctionWriter) traceFunction!("pham.db.fbdatabase")("handle=", handle);

        _writer.writeUInt32(cast(uint32)handle);
    }

    pragma(inline, true)
    void writeId(FbId id) nothrow
    {
        static assert(int64.sizeof == FbId.sizeof);
        version (TraceFunctionWriter) traceFunction!("pham.db.fbdatabase")("id=", id);

        _writer.writeInt64(cast(int64)id);
    }

    pragma(inline, true)
    void writeInt16(int16 v) nothrow
    {
        _writer.writeInt32(cast(int32)v);
    }

    pragma(inline, true)
    void writeInt32(int32 v) nothrow
    {
        _writer.writeInt32(v);
    }

    pragma(inline, true)
    static if (size_t.sizeof > int32.sizeof)
    void writeInt32(size_t v) nothrow
    in
    {
        assert(v < int32.max);
    }
    do
    {
        _writer.writeInt32(v);
    }

    pragma(inline, true)
    void writeInt64(int64 v) nothrow
    {
        _writer.writeInt64(v);
    }

    void writeInt128(scope const(BigInteger) v) nothrow
    {
        ubyte[int128ByteLength] bytes;
        const e = int128Encode(bytes, v);
        assert(e);
        _writer.writeBytes(bytes);
    }

    void writeOpaqueBytes(scope const(ubyte)[] v, const(size_t) forLength) nothrow
    in
    {
        assert(v.length < fbMaxPackageSize);
        assert(forLength < fbMaxPackageSize);
    }
    do
    {
        _writer.writeBytes(v);
        if (forLength > v.length)
        {
            writeFiller!(No.IsSpace)(forLength - v.length);
            writePad(forLength);
        }
        else
            writePad(v.length);
    }

    pragma(inline, true)
    void writeOperation(FbOperation operation) nothrow
    {
        static assert(int32.sizeof == FbOperation.sizeof);
        version (TraceFunctionWriter) traceFunction!("pham.db.fbdatabase")("operation=", operation);

        writeInt32(cast(int32)operation);
    }

    void writeTime(scope const(DbTime) v) nothrow
    {
        writeInt32(timeEncode(v));
    }

    void writeTimeTZ(scope const(DbTime) v) nothrow
    {
        int32 t = void;
        uint16 zId = void;
        int16 zOffset = void;
        timeEncodeTZ(v, t, zId, zOffset);
        writeInt32(t);
        writeUInt16(zId);
    }

    void writeTimeTZEx(scope const(DbTime) v) nothrow
    {
        int32 t = void;
        uint16 zId = void;
        int16 zOffset = void;
        timeEncodeTZ(v, t, zId, zOffset);
        writeInt32(t);
        writeUInt16(zId);
        writeInt16(zOffset);
    }

    pragma(inline, true)
    void writeUInt16(uint16 v) nothrow
    {
        _writer.writeUInt32(v);
    }

    // https://stackoverflow.com/questions/246930/is-there-any-difference-between-a-guid-and-a-uuid
    void writeUUID(scope const(UUID) v) nothrow
    {
        _writer.writeBytes(v.data); // v.data is already in big-endian
        //return writePad(16); // No need filler since alignment to 4
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property FbConnection connection() nothrow pure
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
            _writer.writeBytes(writeFiller[0..writeBytes]);
            nBytes -= writeBytes;
        }
    }

    void writePad(ptrdiff_t nBytes) nothrow
    {
        static immutable ubyte[4] filler = [0, 0, 0, 0];

        const paddingNBytes = (4 - nBytes) & 3;
        if (paddingNBytes != 0)
            _writer.writeBytes(filler[0..paddingNBytes]);
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    DbValueWriter!(Endian.bigEndian) _writer;
    bool _socketBuffer;
}


// Any below codes are private
private:

unittest // FbXdrWriter & FbXdrReader
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbbuffer.FbXdrReader & db.fbbuffer.FbXdrWriter");

    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";
    const(ubyte)[] bytes = [1,2,5,101];
    const(UUID) uuid = UUID(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer(4000);
    auto writer = FbXdrWriter(null, writerBuffer);
    //writer.writeBlob(bytes);
    writer.writeBool(true);
    writer.writeBytes(bytes);
    writer.writeChars(chars);
    writer.writeDate(DbDate(1, 2, 3));
    writer.writeDateTime(DbDateTime(DateTime(1,2,3,4,5,6), 0));
    writer.writeDateTimeTZ(DbDateTime(DateTime(1,2,3,4,5,6), 0));
    writer.writeDateTimeTZEx(DbDateTime(DateTime(1,2,3,4,5,6), 0));
    //writer.writeDecimal();
    //writer.writeFixedChars();
    writer.writeFloat32(float.min_normal);
    writer.writeFloat32(32.32);
    writer.writeFloat32(float.max);
    writer.writeFloat64(double.min_normal);
    writer.writeFloat64(64.64);
    writer.writeFloat64(double.max);
    writer.writeHandle(1);
    writer.writeId(3);
    writer.writeInt16(short.min);
    writer.writeInt16(16);
    writer.writeInt16(short.max);
    writer.writeInt32(int.min);
    writer.writeInt32(32);
    writer.writeInt32(int.max);
    writer.writeInt64(long.min);
    writer.writeInt64(64);
    writer.writeInt64(long.max);
    writer.writeOpaqueBytes(bytes, bytes.length);
    writer.writeOperation(5);
    writer.writeTime(DbTime(Time(1,2,3)));
    writer.writeTimeTZ(DbTime(Time(1,2,3)));
    writer.writeTimeTZEx(DbTime(Time(1,2,3)));
    writer.writeUInt16(100);
    writer.writeUUID(uuid);

    ubyte[] writerBytes = writer.peekBytes();
    auto reader = FbXdrReader(null, writerBytes);
    assert(reader.readBool());
    assert(reader.readBytes() == bytes);
    assert(reader.readChars() == chars);
    assert(reader.readDate() == DbDate(1, 2, 3));
    assert(reader.readDateTime() == DbDateTime(DateTime(1,2,3,4,5,6), 0));
    assert(reader.readDateTimeTZ() == DbDateTime(DateTime(1,2,3,4,5,6), 0));
    assert(reader.readDateTimeTZEx() == DbDateTime(DateTime(1,2,3,4,5,6), 0));
    //assert(reader.readDecimal() == );
    //assert(reader.readFixedChars() == );
    assert(reader.readFloat32() == float.min_normal);
    assert(reader.readFloat32() == cast(float)32.32);
    assert(reader.readFloat32() == float.max);
    assert(reader.readFloat64() == double.min_normal);
    assert(reader.readFloat64() == cast(double)64.64);
    assert(reader.readFloat64() == double.max);
    assert(reader.readHandle() == 1);
    assert(reader.readId() == 3);
    assert(reader.readInt16() == short.min);
    assert(reader.readInt16() == 16);
    assert(reader.readInt16() == short.max);
    assert(reader.readInt32() == int.min);
    assert(reader.readInt32() == 32);
    assert(reader.readInt32() == int.max);
    assert(reader.readInt64() == long.min);
    assert(reader.readInt64() == 64);
    assert(reader.readInt64() == long.max);
    assert(reader.readOpaqueBytes(bytes.length) == bytes);
    assert(reader.readOperation() == 5);
    assert(reader.readTime() == DbTime(Time(1,2,3)));
    assert(reader.readTimeTZ() == DbTime(Time(1,2,3)));
    assert(reader.readTimeTZEx() == DbTime(Time(1,2,3)));
    assert(reader.readUInt16() == 100);
    assert(reader.readUUID() == uuid);
}
