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

module pham.db.db_fbbuffer;

import std.algorithm.comparison : max, min;
import std.array : replicate;
import std.string : representation;
import std.system : Endian;
import std.traits : isIntegral;
import std.typecons : Flag, No, Yes;

debug(debug_pham_db_db_fbbuffer) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.dec.dec_decimal : scaleFrom, scaleTo;
import pham.utl.utl_array_static : ShortStringBuffer;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.db.db_buffer;
import pham.db.db_convert;
import pham.db.db_type;
import pham.db.db_util;
import pham.db.db_fbconvert;
import pham.db.db_fbdatabase;
import pham.db.db_fbisc;
import pham.db.db_fbtype;

alias FbParameterWriter = DbValueWriter!(Endian.littleEndian);

private enum maxLength = int32.max;

pragma(inline, true)
private bool isValidLength(const(size_t) length, const(bool) isLimitLength, const(size_t) limitLength) @nogc nothrow pure @safe
{
    return (!isLimitLength && length <= maxLength) || (isLimitLength && length <= limitLength);
}

struct FbParameterStorage
{
@safe:

public:
    this(DbWriteBuffer buffer, uint8 versionId = 0) nothrow
    {
        this.connection = null;
        this.bufferOwner = DbBufferOwner.none;
        this.buffer = buffer;
        this.writer = FbParameterWriter(buffer);
        this.versionId = versionId;
    }

    this(FbConnection connection, uint8 versionId = 0) nothrow
    {
        this.connection = connection;
        this.bufferOwner = DbBufferOwner.acquired;
        this.buffer = connection.acquireParameterWriteBuffer();
        this.writer = FbParameterWriter(this.buffer);
        this.versionId = versionId;
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        writer.dispose(disposingReason);

        if (buffer !is null)
        {
            final switch (bufferOwner)
            {
                case DbBufferOwner.acquired:
                    if (connection !is null)
                        connection.releaseParameterWriteBuffer(buffer);
                    break;
                case DbBufferOwner.owned:
                    buffer.dispose(disposingReason);
                    break;
                case DbBufferOwner.none:
                    break;
            }
        }

        buffer = null;
        bufferOwner = DbBufferOwner.none;
        connection = null;
    }

    DbWriteBuffer buffer;
    FbConnection connection;
    FbParameterWriter writer;
    DbBufferOwner bufferOwner;
    uint8 versionId;
}

struct FbArrayWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(FbConnection connection) nothrow
    {
        this.storage = FbParameterStorage(connection);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        storage.dispose(disposingReason);
    }

    ubyte[] peekBytes() nothrow return
    {
        return storage.buffer.peekBytes();
    }

    void writeInt8(int8 v) nothrow
    {
        storage.writer.writeInt8(v);
    }

    void writeInt16(int16 v) nothrow
    {
        storage.writer.writeInt16(v);
    }

    void writeLiteral(int32 v) nothrow
    {
		if (v >= int8.min && v <= int8.max)
		{
            storage.writer.writeUInt8(FbIsc.isc_sdl_tiny_integer);
            storage.writer.writeInt8(cast(int8)v);
		}
		else if (v >= int16.min && v <= int16.max)
		{
            storage.writer.writeUInt8(FbIsc.isc_sdl_short_integer);
            storage.writer.writeInt16(cast(int16)v);
		}
        else
        {
            storage.writer.writeUInt8(FbIsc.isc_sdl_long_integer);
            storage.writer.writeInt32(v);
        }
    }

    void writeName(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(v.length <= uint8.max);
    }
    do
    {
        storage.writer.writeUInt8(type);
        storage.writer.writeUInt8(cast(uint8)v.length);
        storage.writer.writeChars(v);
    }

    void writeUInt8(uint8 v) nothrow
    {
        storage.writer.writeUInt8(v);
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return storage.buffer;
    }

private:
    FbParameterStorage storage;
}

struct FbBatchWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(FbConnection connection, uint8 versionId) nothrow
    {
        this.storage = FbParameterStorage(connection, versionId);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        storage.dispose(disposingReason);
    }

    ubyte[] peekBytes() nothrow return
    {
        return storage.buffer.peekBytes();
    }

	void writeBytes(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(v.length <= maxLength);
    }
    do
	{
		storage.writer.writeUInt8(type);
		storage.writer.writeUInt32(v.length);
        if (v.length)
		    storage.writer.writeBytes(v);
	}

	void writeChars(uint8 type, scope const(char)[] v) nothrow
	{
		writeBytes(type, v.representation);
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
		storage.writer.writeUInt8(type);
		storage.writer.writeUInt32(1); // length
		storage.writer.writeInt8(v);
	}

	void writeInt16(uint8 type, int16 v) nothrow
	{
		storage.writer.writeUInt8(type);
		storage.writer.writeUInt32(2); // length
		storage.writer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		storage.writer.writeUInt8(type);
        storage.writer.writeUInt32(4); // length
		storage.writer.writeInt32(v);
	}

    void writeOpaqueUInt8(uint8 v) nothrow
    {
        storage.writer.writeUInt8(v);
    }

    void writeVersion() nothrow
    {
        storage.writer.writeUInt8(versionId);
    }

    pragma(inline, true)
    @property uint8 versionId() const nothrow pure
    {
        return storage.versionId;
    }

private:
    FbParameterStorage storage;
}

enum FbBlrWriteType : ubyte
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
    @disable void opAssign(typeof(this));

    this(DbWriteBuffer buffer) nothrow
    {
        this.storage = FbParameterStorage(buffer);
    }

    this(FbConnection connection) nothrow
    {
        this.storage = FbParameterStorage(connection);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        storage.dispose(disposingReason);
    }

    ubyte[] peekBytes() nothrow return
    {
        return storage.buffer.peekBytes();
    }

    void writeBegin(size_t length) nothrow
    in
    {
        assert(length <= uint16.max / 2); // Max number of columns
    }
    do
    {
	    storage.writer.writeUInt8(FbIsc.blr_version);
	    storage.writer.writeUInt8(FbIsc.blr_begin);
	    storage.writer.writeUInt8(FbIsc.blr_message);
	    storage.writer.writeUInt8(0);
	    storage.writer.writeUInt16(cast(uint16)(length * 2));
    }

    void writeColumn(scope const(DbBaseTypeInfo) baseType, ref FbIscBlrDescriptor descriptor) nothrow
    in
    {
        assert(baseType.size >= -1 && baseType.size <= uint16.max);
        assert(baseType.numericScale >= int8.min && baseType.numericScale <= int8.max);
    }
    do
    {
        const fbType = FbIscColumnInfo.fbType(baseType.typeId);
        const writeTypeFor = fbType == FbIscType.sql_null
            ? FbBlrWriteType.null_
            : (fbType == FbIscType.sql_array ? FbBlrWriteType.array : FbBlrWriteType.base);

        writeType(FbIscColumnInfo.fbTypeToBlrType(fbType), baseType, writeTypeFor, descriptor);

	    storage.writer.writeUInt8(FbBlrType.blr_short);
	    storage.writer.writeUInt8(0);
        descriptor.addSize(2, 2);
    }

    void writeEnd(size_t length) nothrow
    in
    {
        assert(length <= uint16.max / 2); // Max number of columns
    }
    do
    {
    	storage.writer.writeUInt8(FbIsc.blr_end);
	    storage.writer.writeUInt8(FbIsc.blr_eoc);
    }

    void writeType(FbBlrType blrType, scope const(DbBaseTypeInfo) baseType, const(FbBlrWriteType) writeTypeFor,
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
			storage.writer.writeUInt8(FbBlrType.blr_text);
			storage.writer.writeInt16(size);
            descriptor.addSize(0, size);
            return;
        }
        else if (writeTypeFor == FbBlrWriteType.array)
        {
			storage.writer.writeUInt8(FbBlrType.blr_quad);
			storage.writer.writeInt8(0);
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
		storage.writer.writeUInt8(blrType);

	    final switch (blrType) with (FbBlrType)
	    {
            case blr_short:
			    storage.writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(2, 2);
			    break;

            case blr_long:
			    storage.writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(4, 4);
			    break;

            case blr_quad:
			    storage.writer.writeInt8(cast(int8)baseType.numericScale);
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
			    storage.writer.writeInt16(cast(int16)baseType.subTypeId); // charset
			    storage.writer.writeInt16(size);
                descriptor.addSize(0, size);
			    break;

            case blr_int64:
			    storage.writer.writeInt8(cast(int8)baseType.numericScale);
                descriptor.addSize(8, 8);
			    break;

            case blr_blob2:
            case blr_blob:
			    storage.writer.writeInt16(cast(int16)baseType.subTypeId);
			    storage.writer.writeInt16(0); // charset
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
			    storage.writer.writeInt8(cast(int8)baseType.numericScale);
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
			    storage.writer.writeInt16(cast(int16)baseType.subTypeId); // charset
			    storage.writer.writeInt16(size);
                descriptor.addSize(2, size + 2);
			    break;

            case blr_blob_id:
                assert(0);
	    }
    }

private:
    FbParameterStorage storage;
}

struct FbConnectionWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(FbConnection connection, uint8 versionId) nothrow
    {
        this.storage = FbParameterStorage(connection, versionId);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    auto asBytes(T)(T v) const @nogc nothrow pure
    if (isIntegral!T)
    {
        return storage.writer.asBytes(v);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        storage.dispose(disposingReason);
    }

    ubyte[] peekBytes() nothrow return
    {
        return storage.buffer.peekBytes();
    }

	void writeBytes(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_dpb_version1, uint8.max));
    }
    do
	{
        if (versionId <= FbIsc.isc_dpb_version1)
            v = truncate(v, uint8.max);

		storage.writer.writeUInt8(type);
		writeLength(v.length);
        if (v.length)
		    storage.writer.writeBytes(v);
	}

	bool writeBytesIf(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_dpb_version1, uint8.max));
    }
    do
	{
        if (v.length)
        {
            writeBytes(type, v);
            return true;
        }
        else
            return false;
	}

	void writeChars(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_dpb_version1, uint8.max));
    }
    do
	{
		writeBytes(type, v.representation);
	}

	bool writeCharsIf(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_dpb_version1, uint8.max));
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
		storage.writer.writeUInt8(type);
		writeLength(1);
		storage.writer.writeInt8(v);
	}

	void writeInt16(uint8 type, int16 v) nothrow
	{
		storage.writer.writeUInt8(type);
		writeLength(2);
		storage.writer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		storage.writer.writeUInt8(type);
        writeLength(4);
		storage.writer.writeInt32(v);
	}

    void writeMultiParts(uint8 type, scope const(ubyte)[] v) nothrow
    {
        if (versionId > FbIsc.isc_dpb_version1)
            return writeBytes(type, v);

        storage.writeMultiParts(type, v);
    }

    void writeOpaqueUInt8(uint8 v) nothrow
    {
        storage.writer.writeUInt8(v);
    }

    void writeVersion() nothrow
    {
        storage.writer.writeUInt8(versionId);
    }

    pragma(inline, true)
    @property uint8 versionId() const nothrow pure
    {
        return storage.versionId;
    }

private:
    pragma(inline, true)
    void writeLength(size_t len) nothrow
    {
        if (versionId > FbIsc.isc_dpb_version1)
            storage.writer.writeUInt32(len);
        else
            storage.writer.writeUInt8(len);
    }

private:
    FbParameterStorage storage;
}

struct FbServiceWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(FbConnection connection, uint8 versionId) nothrow
    {
        this.storage = FbParameterStorage(connection, versionId);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        storage.dispose(disposingReason);
    }

    auto asBytes(T)(T v) const @nogc nothrow pure
    if (isIntegral!T)
    {
        return storage.writer.asBytes(v);
    }

    ubyte[] peekBytes() nothrow return
    {
        return storage.buffer.peekBytes();
    }

	void writeBytes1(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint8.max));
    }
    do
	{
		storage.writer.writeUInt8(type);
        if (versionId <= FbIsc.isc_spb_version2)
        {
            v = truncate(v, uint8.max);
            storage.writer.writeUInt8(v.length);
        }
        else
            storage.writer.writeUInt32(v.length);
        if (v.length)
		    storage.writer.writeBytes(v);
	}

	bool writeBytes1If(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint8.max));
    }
    do
	{
        if (v.length)
        {
		    writeBytes1(type, v);
            return true;
        }
        else
            return false;
    }

	void writeBytes2(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint16.max));
    }
    do
	{
		storage.writer.writeUInt8(type);
        if (versionId <= FbIsc.isc_spb_version2)
        {
            v = truncate(v, uint16.max);
            storage.writer.writeUInt16(v.length);
        }
        else
            storage.writer.writeUInt32(v.length);
        if (v.length)
		    storage.writer.writeBytes(v);
	}

	bool writeBytes2If(uint8 type, scope const(ubyte)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint16.max));
    }
    do
	{
        if (v.length)
        {
		    writeBytes2(type, v);
            return true;
        }
        else
            return false;
    }

	void writeChars1(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint8.max));
    }
    do
	{
		writeBytes1(type, v.representation);
	}

	void writeChars2(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint16.max));
    }
    do
	{
		writeBytes2(type, v.representation);
	}

	bool writeChars1If(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint8.max));
    }
    do
	{
        if (v.length)
        {
		    writeChars1(type, v);
            return true;
        }
        else
            return false;
	}

	bool writeChars2If(uint8 type, scope const(char)[] v) nothrow
    in
    {
        assert(isValidLength(v.length, versionId <= FbIsc.isc_spb_version2, uint16.max));
    }
    do
	{
        if (v.length)
        {
		    writeChars2(type, v);
            return true;
        }
        else
            return false;
	}

    void writePreamble() nothrow
    {
        writeVersion();
        if (versionId <= FbIsc.isc_spb_version2)
            writeVersion();
    }

	void writeInt8(uint8 type, int8 v) nothrow
	{
		storage.writer.writeUInt8(type);
		storage.writer.writeInt8(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		storage.writer.writeUInt8(type);
		storage.writer.writeInt32(v);
	}

	void writeInt32If(uint8 type, int32 v) nothrow
	{
        if (v)
        {
            storage.writer.writeUInt8(type);
            storage.writer.writeInt32(v);
        }
	}

    void writeType(uint8 type) nothrow
    {
        storage.writer.writeUInt8(type);
    }

    void writeVersion() nothrow
    {
        storage.writer.writeUInt8(versionId);
    }

    pragma(inline, true)
    @property uint8 versionId() const nothrow pure
    {
        return storage.versionId;
    }

private:
    FbParameterStorage storage;
}

struct FbTransactionWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(FbConnection connection) nothrow
    {
        this.storage = FbParameterStorage(connection);
    }

    ~this() nothrow
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        storage.dispose(disposingReason);
    }

    ubyte[] peekBytes() nothrow return
    {
        return storage.buffer.peekBytes();
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

		storage.writer.writeUInt8(type);
		storage.writer.writeUInt8(vLen);
        if (vLen)
		    storage.writer.writeBytes(v);
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
		storage.writer.writeUInt8(type);
		storage.writer.writeUInt8(2);
		storage.writer.writeInt16(v);
	}

	void writeInt32(uint8 type, int32 v) nothrow
	{
		storage.writer.writeUInt8(type);
		storage.writer.writeUInt8(4);
		storage.writer.writeInt32(v);
	}

    pragma(inline, true)
    void writeOpaqueBytes(scope const(ubyte)[] v) nothrow
    {
        storage.writer.writeBytes(v);
    }

    pragma(inline, true)
    void writeOpaqueUInt8(uint8 v) nothrow
    {
        storage.writer.writeUInt8(v);
    }

private:
    FbParameterStorage storage;
}

struct FbXdrReader
{
@safe:

public:
    @disable this(this);

    this(FbConnection connection) nothrow
    {
        this._connection = connection;
        this._bufferOwner = DbBufferOwner.none;
        this._buffer = connection.getSocketReadBuffer();
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);
    }

    this(FbConnection connection, ubyte[] bufferData) nothrow
    {
        this._connection = connection;
        this._bufferOwner = DbBufferOwner.owned;
        this._buffer = new DbReadBuffer(bufferData);
        this._reader = DbValueReader!(Endian.bigEndian)(this._buffer);
    }

    ubyte[] consumeBytes() return scope
    {
        const nBytes = _reader.readUInt32();
        auto result = _reader.consume(nBytes);
        readPad(nBytes);
        return result;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _reader.dispose(disposingReason);

        if (_buffer !is null)
        {
            final switch (_bufferOwner)
            {
                case DbBufferOwner.acquired:
                    assert(0);
                    break;
                case DbBufferOwner.owned:
                    _buffer.dispose(disposingReason);
                    break;
                case DbBufferOwner.none:
                    break;
            }
        }

        _bufferOwner = DbBufferOwner.none;
        _buffer = null;
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

    int64 readBytes(DbSaveBufferData saveBufferData, size_t segmentLength)
    in
    {
        assert(saveBufferData !is null);
        assert(segmentLength != 0);
    }
    do
    {
        const nBytes = _reader.readUInt32();
        auto result = _reader.readBytes(nBytes, saveBufferData, segmentLength);
        readPad(nBytes);
        return result;
    }

    char[] readChars()
    {
        const nBytes = _reader.readUInt32();
        auto result = _reader.readChars(nBytes);
        readPad(nBytes);
        return result;
    }

    int64 readChars(DbSaveBufferData saveBufferData, size_t segmentLength)
    in
    {
        assert(saveBufferData !is null);
        assert(segmentLength != 0);
    }
    do
    {
        const nBytes = _reader.readUInt32();
        auto result = _reader.readChars(nBytes, saveBufferData, segmentLength);
        readPad(nBytes);
        return result;
    }

    DbDate readDate()
    {
        return dateDecode(readInt32());
    }

    DbDateTime readDateTime()
    {
        const d = readInt32();
        const t = readInt32();
        return dateTimeDecode(d, t);
    }

    DbDateTime readDateTimeTZ()
    {
        // Do not try to inline function calls, D does not honor correct sequence from left to right
        const d = readInt32();
        const t = readInt32();
        const zId = readUInt16();
        return dateTimeDecodeTZ(d, t, zId, 0);
    }

    DbDateTime readDateTimeTZEx()
    {
        // Do not try to inline function calls, D does not honor correct sequence from left to right
        const d = readInt32();
        const t = readInt32();
        const zId = readUInt16();
        const zOffset = readInt16();
        return dateTimeDecodeTZ(d, t, zId, zOffset);
    }

    D readDecimal(D)(scope const(DbBaseTypeInfo) baseType)
    if (isDecimal!D)
    {
		switch (FbIscColumnInfo.fbType(baseType.typeId))
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

    ubyte[] readFixedBytes(scope const(DbBaseTypeInfo) baseType)
    {
        return readOpaqueBytes(baseType.size);
    }

    char[] readFixedChars(scope const(DbBaseTypeInfo) baseType) @trusted // @trusted=cast()
    {
        const charsCount = baseType.size / 4; // UTF8 to char
        auto result = cast(char[])readOpaqueBytes(baseType.size);
        return truncateEndIf(result, charsCount, ' ');
    }

    string readFixedString(scope const(DbBaseTypeInfo) baseType) @trusted // @trusted=cast()
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
        debug(debug_pham_db_db_fbbuffer) debug writeln(__FUNCTION__, "()");

        static assert(int32.sizeof == FbOperation.sizeof);

        while (true)
        {
            auto result = readInt32();

            debug(debug_pham_db_db_fbbuffer) debug writeln("\t", "code=", result);

            if (result != FbIsc.op_dummy)
                return result;
        }
    }

    string readString() @trusted // @trusted=cast()
    {
        return cast(string)readChars();
    }

    pragma(inline, true)
    int64 readString(DbSaveBufferData saveBufferData, size_t segmentLength)
    in
    {
        assert(saveBufferData !is null);
        assert(segmentLength != 0);
    }
    do
    {
        return readChars(saveBufferData, segmentLength);
    }

    FbIscStatues readStatuses() @trusted
    {
        debug(debug_pham_db_db_fbbuffer) debug writeln(__FUNCTION__, "()");

        FbIscStatues result;
        int gdsCode;
        int numArg;

        bool done;
        while (!done)
        {
			auto typeCode = readInt32();

            debug(debug_pham_db_db_fbbuffer) debug writeln("\t", "typeCode=", typeCode);

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
        const t = readInt32();
        const zId = readUInt16();
        return timeDecodeTZ(t, zId, 0);
    }

    DbTime readTimeTZEx()
    {
        // Do not try to inline function calls, D does not honor right sequence from left to right
        const t = readInt32();
        const zId = readUInt16();
        const zOffset = readInt16();
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
    pragma(inline, true)
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
    DbBufferOwner _bufferOwner;
}

struct FbXdrWriter
{
@safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(FbConnection connection) nothrow
    {
        this._connection = connection;
        this._bufferOwner = DbBufferOwner.acquired;
        this._buffer = connection.acquireSocketWriteBuffer();
        this._writer = DbValueWriter!(Endian.bigEndian)(this._buffer);
    }

    this(FbConnection connection, DbWriteBuffer buffer) nothrow
    {
        buffer.reset();
        this._connection = connection;
        this._bufferOwner = DbBufferOwner.none;
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

        if (_buffer !is null)
        {
            final switch (_bufferOwner)
            {
                case DbBufferOwner.acquired:
                    if (_connection !is null)
                        _connection.releaseSocketWriteBuffer(_buffer);
                    break;
                case DbBufferOwner.owned:
                    _buffer.dispose(disposingReason);
                    break;
                case DbBufferOwner.none:
                    break;
            }
        }

        _bufferOwner = DbBufferOwner.none;
        _buffer = null;
        _connection = null;
    }

    void flush()
    {
        debug(debug_pham_db_db_fbbuffer) debug writeln(__FUNCTION__, "()");

        _buffer.flush();
    }

    ubyte[] peekBytes() nothrow return
    {
        return _buffer.peekBytes();
    }

    void writeBlob(scope const(ubyte)[] v) nothrow
    {
        const len = cast(int32)v.length;

        writeInt32(len); // segmentLength
        writeInt32(len); // dataLength
        _writer.writeBytes(v);
        writePad(len);
    }

    pragma(inline, true)
    void writeBool(bool v) nothrow
    {
        _writer.writeBool(v);
        writePad(1);
    }

    void writeBytes(scope const(ubyte)[] v) nothrow
    {
        const nBytes = cast(int32)v.length;
        _writer.writeInt32(nBytes);
        _writer.writeBytes(v);
        writePad(nBytes);
    }

    pragma(inline, true)
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

    void writeDecimal(D)(scope const(D) v, scope const(DbBaseTypeInfo) baseType)
    if (isDecimal!D)
    {
		switch (FbIscColumnInfo.fbType(baseType.typeId))
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

    void writeFixedChars(scope const(char)[] v, scope const(DbBaseTypeInfo) baseType) nothrow
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
        debug(debug_pham_db_db_fbbuffer) debug writeln(__FUNCTION__, "(handle=", handle, ")");

        _writer.writeUInt32(cast(uint32)handle);
    }

    pragma(inline, true)
    void writeId(FbId id) nothrow
    {
        static assert(int64.sizeof == FbId.sizeof);
        debug(debug_pham_db_db_fbbuffer) debug writeln(__FUNCTION__, "(id=", id, ")");

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
        assert(v <= int32.max);
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
        debug(debug_pham_db_db_fbbuffer) debug writeln(__FUNCTION__, "(operation=", operation, ")");

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
        enum ptrdiff_t padSize = 4;
        static immutable ubyte[padSize] filler = [0, 0, 0, 0];

        const paddingNBytes = (padSize - nBytes) & (padSize - 1);
        if (paddingNBytes != 0)
            _writer.writeBytes(filler[0..paddingNBytes]);
    }

private:
    DbWriteBuffer _buffer;
    FbConnection _connection;
    DbValueWriter!(Endian.bigEndian) _writer;
    DbBufferOwner _bufferOwner;
}

void writeMultiParts(ref FbParameterStorage storage, uint8 type, scope const(ubyte)[] v) nothrow @safe
{
    uint8 partSequence = 0;
    while (v.length)
    {
        // -1=Reserve 1 byte for sequence
        auto partLength = cast(uint8)min(v.length, uint8.max - 1);

        storage.writer.writeUInt8(type);
        storage.writer.writeUInt8(cast(uint8)(partLength + 1)); // +1=Include the sequence
        storage.writer.writeUInt8(partSequence);
        storage.writer.writeBytes(v[0..partLength]);

        v = v[partLength..$];
        partSequence++;
        assert(v.length == 0 || partSequence > 0); // Check partSequence for wrap arround
    }
}

// Any below codes are private
private:

unittest // FbXdrWriter & FbXdrReader
{
    const(char)[] chars = "1234567890qazwsxEDCRFV_+?";
    const(ubyte)[] bytes = [1,2,5,101];
    const(UUID) uuid = UUID(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);

    //pragma(msg, float.min_normal);
    //pragma(msg, double.min_normal);

    auto writerBuffer = new DbWriteBuffer(4_000);
    auto writer = FbXdrWriter(null, writerBuffer);
    //writer.writeBlob(bytes);
    writer.writeBool(true);
    writer.writeBytes(bytes);
    writer.writeChars(chars);
    writer.writeDate(DbDate(1, 2, 3));
    writer.writeDateTime(DbDateTime(DateTime(1,2,3,4,5,6)));
    writer.writeDateTimeTZ(DbDateTime(DateTime(1,2,3,4,5,6,0,DateTimeZoneKind.utc)));
    writer.writeDateTimeTZEx(DbDateTime(DateTime(1,2,3,4,5,6,0,DateTimeZoneKind.utc)));
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
    writer.writeTimeTZ(DbTime(Time(1,2,3,0,DateTimeZoneKind.utc)));
    writer.writeTimeTZEx(DbTime(Time(1,2,3,0,DateTimeZoneKind.utc)));
    writer.writeUInt16(100);
    writer.writeUUID(uuid);

    ubyte[] writerBytes = writer.peekBytes();
    auto reader = FbXdrReader(null, writerBytes);
    assert(reader.readBool());
    assert(reader.readBytes() == bytes);
    assert(reader.readChars() == chars);
    assert(reader.readDate() == DbDate(1, 2, 3));
    assert(reader.readDateTime() == DbDateTime(DateTime(1,2,3,4,5,6)));
    assert(reader.readDateTimeTZ() == DbDateTime(DateTime(1,2,3,4,5,6,0,DateTimeZoneKind.utc)));
    assert(reader.readDateTimeTZEx() == DbDateTime(DateTime(1,2,3,4,5,6,0,DateTimeZoneKind.utc)));
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
    assert(reader.readTimeTZ() == DbTime(Time(1,2,3,0,DateTimeZoneKind.utc)));
    assert(reader.readTimeTZEx() == DbTime(Time(1,2,3,0,DateTimeZoneKind.utc)));
    assert(reader.readUInt16() == 100);
    assert(reader.readUUID() == uuid);
}
