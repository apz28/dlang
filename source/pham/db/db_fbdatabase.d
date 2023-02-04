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

module pham.db.fbdatabase;

import std.algorithm.comparison : max;
import std.array : Appender;
import std.conv : text, to;
import std.exception : assumeWontThrow;
import std.math : abs;
import std.string : indexOf;
import std.system : Endian;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.external.std.log.logger : Logger, LogLevel, LogTimming, ModuleLoggerOption, ModuleLoggerOptions;
import pham.utl.enum_set : toName;
import pham.utl.disposable : DisposingReason, isDisposing;
import pham.utl.object : bytesFromBase64s, bytesToBase64s, functionName, VersionString;
import pham.db.buffer;
import pham.db.convert;
import pham.db.database;
import pham.db.exception : SkException;
import pham.db.message;
import pham.db.object;
import pham.db.skdatabase;
import pham.db.type;
import pham.db.util;
import pham.db.value;
import pham.db.fbbuffer;
import pham.db.fbexception;
import pham.db.fbisc;
import pham.db.fbprotocol;
import pham.db.fbtype;

struct FbArray
{
public:
    @disable this(this);

    this(FbCommand command, FbIscArrayDescriptor descriptor) nothrow pure @safe
    in
    {
        assert(command !is null);
    }
    do
    {
        this._command = command;
        this._descriptor = descriptor;
    }

    this(FbCommand command, FbIscArrayDescriptor descriptor, FbId id) nothrow pure @safe
    in
    {
        assert(command !is null);
    }
    do
    {
        this._command = command;
        this._descriptor = descriptor;
        this._id = id;
    }

    this(FbCommand command, string tableName, string fieldName, FbId id) @safe
    in
    {
        assert(command !is null);
    }
    do
    {
        this._command = command;
        this._id = id;
        this._descriptor = fbConnection.arrayManager.getDescriptor(tableName, fieldName);
    }

    ~this() @safe
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _id = 0;
        if (isDisposing(disposingReason))
            _command = null;
    }

    Variant readArray(DbNameColumn arrayColumn) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        final switch (descriptor.fieldInfo.dbType)
        {
            case DbType.boolean:
                return Variant(readArrayImpl!bool(arrayColumn));
            case DbType.int8:
                return Variant(readArrayImpl!int8(arrayColumn));
            case DbType.int16:
                return Variant(readArrayImpl!int16(arrayColumn));
            case DbType.int32:
                return Variant(readArrayImpl!int32(arrayColumn));
            case DbType.int64:
                return Variant(readArrayImpl!int64(arrayColumn));
            case DbType.int128:
                return Variant(readArrayImpl!BigInteger(arrayColumn));
            case DbType.decimal:
                return Variant(readArrayImpl!Decimal(arrayColumn));
            case DbType.decimal32:
                return Variant(readArrayImpl!Decimal32(arrayColumn));
            case DbType.decimal64:
                return Variant(readArrayImpl!Decimal64(arrayColumn));
            case DbType.decimal128:
                return Variant(readArrayImpl!Decimal128(arrayColumn));
            case DbType.numeric:
                return Variant(readArrayImpl!Numeric(arrayColumn));
            case DbType.float32:
                return Variant(readArrayImpl!float32(arrayColumn));
            case DbType.float64:
                return Variant(readArrayImpl!float64(arrayColumn));
            case DbType.date:
                return Variant(readArrayImpl!Date(arrayColumn));
            case DbType.datetime:
            case DbType.datetimeTZ:
                return Variant(readArrayImpl!DbDateTime(arrayColumn));
            case DbType.time:
            case DbType.timeTZ:
                return Variant(readArrayImpl!DbTime(arrayColumn));
            case DbType.uuid:
                return Variant(readArrayImpl!UUID(arrayColumn));
            case DbType.fixedString:
            case DbType.string:
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                return Variant(readArrayImpl!string(arrayColumn));
            case DbType.fixedBinary:
            case DbType.binary:
                return Variant(readArrayImpl!(ubyte[])(arrayColumn));

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(functionName(), toName!DbType(descriptor.fieldInfo.dbType));
                throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_net_read_err);
        }

        // Never reach here
        assert(0);
    }

    T[] readArrayImpl(T)(DbNameColumn arrayColumn) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto baseType = descriptor.fieldInfo.baseType;
        auto response = readArrayRaw(arrayColumn);
        auto reader = FbXdrReader(fbConnection, response.data);
        T[] result = new T[](descriptor.calculateElements());
        foreach (i; 0..result.length)
        {
            if (reader.empty)
                break;

            static if (is(T == bool))
                result[i] = reader.readBool();
            else static if (is(T == int8))
                result[i] = cast(int8)reader.readInt16();
            else static if (is(T == int16))
                result[i] = reader.readInt16();
            else static if (is(T == int32))
                result[i] = reader.readInt32();
            else static if (is(T == int64))
                result[i] = reader.readInt64();
            else static if (is(T == BigInteger))
                result[i] = reader.readInt64();
            else static if (is(T == Decimal32) || is(T == Decimal64) || is(T == Decimal128))
                result[i] = reader.readDecimal!T(baseType);
            else static if (is(T == float32))
                result[i] = reader.readFloat32();
            else static if (is(T == float64))
                result[i] = reader.readFloat64();
            else static if (is(T == Date))
                result[i] = reader.readDate();
            else static if (is(T == DbDateTime))
            {
                if (baseType.typeId == FbIscType.sql_timestamp_tz)
                    result[i] = reader.readDateTimeTZ();
                else if (baseType.typeId == FbIscType.sql_timestamp_tz_ex)
                    result[i] = reader.readDateTimeTZEx();
                else
                    result[i] = reader.readDateTime();
            }
            else static if (is(T == DbTime))
            {
                if (baseType.typeId == FbIscType.sql_time_tz)
                    result[i] = reader.readTimeTZ();
                else if (baseType.typeId == FbIscType.sql_time_tz_ex)
                    result[i] = reader.readTimeTZEx();
                else
                    result[i] = reader.readTime();
            }
            else static if (is(T == UUID))
                result[i] = reader.readUUID();
            else static if (is(T == string))
            {
                if (baseType.typeId == FbIscType.sql_text)
                    result[i] = reader.readFixedString(baseType);
                else
                    result[i] = reader.readString();
            }
            else static if (is(T == ubyte[]))
                result[i] = reader.readBytes();
            else
                static assert(0, "Unsupport reading for " ~ T.toString());
        }
        return result;
    }

    FbIscArrayGetResponse readArrayRaw(DbNameColumn arrayColumn) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.arrayGetWrite(this);
        return protocol.arrayGetRead(this);
    }

    void writeArray(DbNameColumn arrayColumn, ref DbValue arrayValue) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writerBuffer = new DbWriteBuffer(4000);
        uint elements;
        ubyte[] encodedArrayValue;
        final switch (descriptor.fieldInfo.dbType)
        {
            case DbType.boolean:
                encodedArrayValue = writeArrayImpl!bool(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.int8:
                encodedArrayValue = writeArrayImpl!int8(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.int16:
                encodedArrayValue = writeArrayImpl!int16(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.int32:
                encodedArrayValue = writeArrayImpl!int32(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.int64:
                encodedArrayValue = writeArrayImpl!int64(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.int128:
                encodedArrayValue = writeArrayImpl!BigInteger(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.decimal:
                encodedArrayValue = writeArrayImpl!Decimal(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.decimal32:
                encodedArrayValue = writeArrayImpl!Decimal32(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.decimal64:
                encodedArrayValue = writeArrayImpl!Decimal64(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.decimal128:
                encodedArrayValue = writeArrayImpl!Decimal128(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.numeric:
                encodedArrayValue = writeArrayImpl!Numeric(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.float32:
                encodedArrayValue = writeArrayImpl!float32(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.float64:
                encodedArrayValue = writeArrayImpl!float64(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.date:
                encodedArrayValue = writeArrayImpl!Date(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.datetime:
            case DbType.datetimeTZ:
                encodedArrayValue = writeArrayImpl!DbDateTime(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.time:
            case DbType.timeTZ:
                encodedArrayValue = writeArrayImpl!DbTime(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.uuid:
                encodedArrayValue = writeArrayImpl!UUID(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.fixedString:
            case DbType.string:
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                encodedArrayValue = writeArrayImpl!string(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;
            case DbType.fixedBinary:
            case DbType.binary:
                encodedArrayValue = writeArrayImpl!(ubyte[])(writerBuffer, arrayColumn, arrayValue, elements).peekBytes();
                break;

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(functionName(), toName!DbType(descriptor.fieldInfo.dbType));
                throw new FbException(msg, DbErrorCode.write, null, 0, FbIscResultCode.isc_net_write_err);
        }

        auto protocol = fbConnection.protocol;
        protocol.arrayPutWrite(this, elements, encodedArrayValue);
        _id = protocol.arrayPutRead().id;
    }

    DbWriteBuffer writeArrayImpl(T)(DbWriteBuffer writerBuffer, DbNameColumn arrayColumn, ref DbValue arrayValue,
        out uint elements) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto baseType = descriptor.fieldInfo.baseType;
        auto values = arrayValue.get!(T[])();
        elements = cast(uint)values.length;
        auto writer = FbXdrWriter(fbConnection, writerBuffer);
        foreach (ref value; values)
        {
            static if (is(T == bool))
                writer.writeBool(value);
            else static if (is(T == int8))
                writer.writeInt16(value);
            else static if (is(T == int16))
                writer.writeInt16(value);
            else static if (is(T == int32))
                writer.writeInt32(value);
            else static if (is(T == int64))
                writer.writeInt64(value);
            else static if (is(T == BigInteger))
                writer.writeInt128(value);
            else static if (is(T == Decimal32) || is(T == Decimal64) || is(T == Decimal128))
                writer.writeDecimal!T(value, baseType);
            else static if (is(T == float32))
                writer.writeFloat32(value);
            else static if (is(T == float64))
                writer.writeFloat64(value);
            else static if (is(T == Date))
                writer.writeDate(value);
            else static if (is(T == DbDateTime))
            {
                if (baseType.typeId == FbIscType.sql_timestamp_tz)
                    writer.writeDateTimeTZ(value);
                else if (baseType.typeId == FbIscType.sql_timestamp_tz_ex)
                    writer.writeDateTimeTZEx(value);
                else
                    writer.writeDateTime(value);
            }
            else static if (is(T == DbTime))
            {
                if (baseType.typeId == FbIscType.sql_time_tz)
                    writer.writeTimeTZ(value);
                else if (baseType.typeId == FbIscType.sql_time_tz_ex)
                    writer.writeTimeTZEx(value);
                else
                    writer.writeTime(value);
            }
            else static if (is(T == UUID))
                writer.writeUUID(value);
            else static if (is(T == string))
            {
                if (baseType.typeId == FbIscType.sql_text)
                    writer.writeFixedChars(value, baseType);
                else
                    writer.writeChars(value);
            }
            else static if (is(T == ubyte[]))
                writer.writeBytes(value);
            else
                static assert(0, "Unsupport writing for " ~ T.toString());
        }
        return writerBuffer;
    }

    /* Properties */

    @property ref FbIscArrayDescriptor descriptor() nothrow return @safe
    {
        return _descriptor;
    }

    @property FbCommand fbCommand() nothrow pure @safe
    {
        return _command;
    }

    @property FbConnection fbConnection() nothrow pure @safe
    {
        return _command.fbConnection;
    }

    @property FbTransaction fbTransaction() nothrow pure @safe
    {
        return _command.fbTransaction;
    }

    @property FbId fbId() const nothrow @safe
    {
        return _id;
    }

package(pham.db):
    FbCommand _command;
    FbIscArrayDescriptor _descriptor;
    FbId _id;
}

struct FbArrayManager
{
@safe:

public:
    this(FbConnection connection) nothrow pure
    in
    {
        assert(connection !is null);
    }
    do
    {
        this._connection = connection;
        version (TraceFunction) { import pham.utl.test; debug dgWritefln("FbArrayManager(create)%s", cast(void*)_connection); }
    }

    ~this()
    {
        version (TraceFunction) { import pham.utl.test; debug dgWritefln("FbArrayManager(destroy)%s", cast(void*)_connection); }
        dispose(DisposingReason.destructor);
    }

    void close() nothrow
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        doClose(DisposingReason.other);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        doClose(disposingReason);
    }

    FbIscArrayDescriptor getDescriptor(string tableName, string fieldName)
    {
        version (TraceFunction) { import pham.utl.test; debug dgWritefln("FbArrayManager(getDescriptor)%s", cast(void*)_connection); }
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("tableName=", tableName, ", fieldName=", fieldName);

        FbIscArrayDescriptor result;
        result.fieldInfo.tableName = tableName;
        result.fieldInfo.name = fieldName;

        if (_arrayType is null)
            _arrayType = createCommand(arrayTypeCommand);
        _arrayType.parameters.get("tableName").value = tableName;
        _arrayType.parameters.get("fieldName").value = fieldName;
        auto reader = _arrayType.executeReader();
        scope (exit)
            reader.dispose();

        if (reader.read())
        {
            result.blrType = reader.getValue("RDB$FIELD_TYPE").get!int16();
            result.fieldInfo.type = FbIscFieldInfo.blrTypeToFbType(result.blrType);
            result.fieldInfo.numericScale = reader.getValue("RDB$FIELD_SCALE").get!int16();
            result.fieldInfo.size = reader.getValue("RDB$FIELD_LENGTH").get!int16();
            result.fieldInfo.subType = reader.getValue("RDB$FIELD_SUB_TYPE").get!int16();
            result.fieldInfo.owner = reader.getValue("RDB$OWNER_NAME").get!string();
            const dimensions = reader.getValue("RDB$DIMENSIONS").get!int16();
            assert(dimensions > 0);
            result.bounds.length = dimensions;
            result.bounds[0].lower = reader.getValue("RDB$LOWER_BOUND").get!int32();
            result.bounds[0].upper = reader.getValue("RDB$UPPER_BOUND").get!int32();
            int32 nextBound = 0;
            while (++nextBound < dimensions && reader.read())
            {
                result.bounds[nextBound].lower = reader.getValue("RDB$LOWER_BOUND").get!int32();
                result.bounds[nextBound].upper = reader.getValue("RDB$UPPER_BOUND").get!int32();
            }
        }
        return result;
    }

    /* Properties */

    @property FbConnection fbConnection() nothrow pure
    {
        return _connection;
    }

package(pham.db):
    void doClose(const(DisposingReason) disposingReason) nothrow
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        disposeCommand(_arrayType, disposingReason);
        if (isDisposing(disposingReason))
            _connection = null;
    }

private:
    FbCommand createCommand(string commandText)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto result = fbConnection.createCommand();
        result.commandText = commandText;
        return cast(FbCommand)result.prepare();
    }

    void disposeCommand(ref FbCommand command, const(DisposingReason) disposingReason) nothrow
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        if (command !is null)
        {
            command.dispose(disposingReason);
            command = null;
        }
    }

public:
    static immutable string arrayTypeCommand = q"{
SELECT f.RDB$FIELD_TYPE, f.RDB$FIELD_SUB_TYPE, f.RDB$FIELD_SCALE, f.RDB$FIELD_LENGTH, f.RDB$DIMENSIONS, f.RDB$OWNER_NAME
    , b.RDB$DIMENSION, b.RDB$LOWER_BOUND, b.RDB$UPPER_BOUND
FROM RDB$FIELDS f
JOIN RDB$FIELD_DIMENSIONS b ON b.RDB$FIELD_NAME = f.RDB$FIELD_NAME
JOIN RDB$RELATION_FIELDS rf ON rf.RDB$FIELD_SOURCE = f.RDB$FIELD_NAME
WHERE rf.RDB$RELATION_NAME = @tableName AND rf.RDB$FIELD_NAME = @fieldName
ORDER BY b.RDB$DIMENSION
}";

package(pham.db):
    FbCommand _arrayType;
    FbConnection _connection;
}

struct FbBlob
{
@safe:

public:
    @disable this(this);

    this(FbCommand command) nothrow pure
    in
    {
        assert(command !is null);
    }
    do
    {
        this._command = command;
    }

    this(FbCommand command, FbId id) nothrow pure
    {
        this._command = command;
        this._info.id = id;
    }

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    void cancel()
    in
    {
        assert(fbConnection !is null);
        assert(_info.hasHandle);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        cancelImpl();
    }

    static if (fbDeferredProtocol)
    FbDeferredResponse cancel(ref FbXdrWriter writer) nothrow
    in
    {
        assert(fbConnection !is null);
        assert(_info.hasHandle);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        scope (exit)
            _info.resetHandle();

        auto protocol = fbConnection.protocol;
        protocol.blobEndWrite(writer, this, FbIsc.op_cancel_blob);
        return &protocol.blobEndRead;
    }

    void close()
    in
    {
        assert(fbConnection !is null);
        assert(_info.hasHandle);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        doClose(DisposingReason.other);
    }

    static if (fbDeferredProtocol)
    FbDeferredResponse close(ref FbXdrWriter writer) nothrow
    in
    {
        assert(fbConnection !is null);
        assert(_info.hasHandle);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        scope (exit)
            _info.resetHandle();

        auto protocol = fbConnection.protocol;
        protocol.blobEndWrite(writer, this, FbIsc.op_close_blob);
        return &protocol.blobEndRead;
    }

    void create()
    in
    {
        assert(fbConnection !is null);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.blobBeginWrite(this, FbIsc.op_create_blob);
        _info = protocol.blobBeginRead();
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        doClose(disposingReason);
        if (isDisposing(disposingReason))
            _command = null;
    }

    int32 length()
    in
    {
        assert(fbConnection !is null);
        assert(isOpen);
    }
    do
    {
        return sizes().length;
    }

    void open()
    in
    {
        assert(fbId != 0);
        assert(fbConnection !is null);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.blobBeginWrite(this, FbIsc.op_open_blob);
        _info.handle = protocol.blobBeginRead().handle;
    }

    ubyte[] openRead()
    in
    {
        assert(fbConnection !is null);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        open();
        scope (exit)
            close();

        const blobLength = length();
        if (blobLength <= 0)
            return null;

        size_t readLength = 0;
        auto result = Appender!(ubyte[])();
        result.reserve(blobLength);
        auto protocol = fbConnection.protocol;
        while (readLength < blobLength)
        {
            protocol.blobGetSegmentsWrite(this);
            auto read = protocol.blobGetSegmentsRead();

            if (read.data.length)
                readLength += parseBlob(result, read.data);

            if (read.handle == 2)
                break;
        }
        return result.data;
    }

    void openWrite(scope const(ubyte)[] value)
    in
    {
        assert(fbConnection !is null);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        create();
        scope (failure)
            cancel();
        scope (success)
            close();

        const trunkLength = maxSegmentLength;
        auto protocol = fbConnection.protocol;
        while (value.length != 0)
        {
            auto writeLength = value.length > trunkLength ? trunkLength : value.length;
            protocol.blobPutSegmentsWrite(this, value[0..writeLength]);
            protocol.blobPutSegmentsRead();
            value = value[writeLength..$];
        }
    }

    FbIscBlobSize sizes()
    in
    {
        assert(fbConnection !is null);
        assert(isOpen);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.blobSizeInfoWrite(this);
        return protocol.blobSizeInfoRead();
    }

    /* Properties */

    @property FbCommand fbCommand() nothrow pure
    {
        return _command;
    }

    @property final FbConnection fbConnection() nothrow pure
    {
        return _command.fbConnection;
    }

    @property FbTransaction fbTransaction() nothrow pure
    {
        return _command.fbTransaction;
    }

    @property FbHandle fbHandle() const nothrow
    {
        return _info.handle;
    }

    @property FbId fbId() const nothrow
    {
        return _info.id;
    }

    @property bool isOpen() const nothrow
    {
        return _info.hasHandle;
    }

    @property Logger logger() nothrow pure
    {
        return _command !is null ? _command.logger : null;
    }

    @property uint maxSegmentLength() const nothrow pure
    {
        // Max package size - overhead
        // See FbXdrWriter.writeBlob for overhead
        const max = FbIscSize.maxPackageLength - (int32.sizeof * 6);
        return (segmentLength < 100 || segmentLength > max) ? max : segmentLength;
    }

package(pham.db):
    void cancelImpl()
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        scope (exit)
            _info.resetHandle();

        auto protocol = fbConnection.protocol;
        protocol.blobEndWrite(this, FbIsc.op_cancel_blob);
        static if (fbDeferredProtocol)
            protocol.deferredResponses ~= &protocol.blobEndRead;
        else
            protocol.blobEndRead();
    }

    void doClose(const(DisposingReason) disposingReason) nothrow
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        scope (exit)
        {
            if (isDisposing(disposingReason))
                _info.reset();
            else
                _info.resetHandle();
        }

        if (isDisposing(disposingReason) && !isOpen)
            return;

        try
        {
            if (isDisposing(disposingReason))
            {
                if (fbConnection !is null)
                    cancelImpl();
                return;
            }

            auto protocol = fbConnection.protocol;
            protocol.blobEndWrite(this, FbIsc.op_close_blob);
            static if (fbDeferredProtocol)
                protocol.deferredResponses ~= &protocol.blobEndRead;
            else
                protocol.blobEndRead();
        }
        catch (Exception e)
        {
            if (auto log = logger)
                log.error(e.msg, e);
        }
    }

public:
    uint segmentLength;

package(pham.db):
    FbCommand _command;
    FbIscObject _info;
}

class FbCancelCommandData : DbCancelCommandData
{
@safe:

    FbHandle connectionHandle;
}

class FbCommand : SkCommand
{
public:
    this(FbConnection connection, string name = null) nothrow @safe
    {
        super(connection, name);
        this._flags.set(DbCommandFlag.transactionRequired, true);
    }

    this(FbConnection connection, FbTransaction transaction, string name = null) nothrow @safe
    {
        super(connection, transaction, name);
    }

    // Firebird >= v4.0
    final FbCommandBatch createCommandBatch(size_t parametersCapacity = 0) @safe
    {
        checkActiveReader();

        return FbCommandBatch(this, false, parametersCapacity);
    }

	final override const(char)[] getExecutionPlan(uint vendorMode) @safe
	{
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("vendorMode=", vendorMode);

        const wasPrepared = prepared;
        if (!wasPrepared)
            prepare();
        scope (exit)
        {
            if (!wasPrepared)
                unprepare();
        }

        auto protocol = fbConnection.protocol;

        FbCommandPlanInfo info;
        uint bufferLength = FbIscSize.executePlanBufferLength;
        int maxTryCount = 3;
        while (maxTryCount--)
        {
            protocol.executionPlanCommandInfoWrite(this, vendorMode, bufferLength);
            if (protocol.executionPlanCommandInfoRead(this, vendorMode, info) == FbCommandPlanInfo.Kind.truncated)
                bufferLength *= 2;
            else
                break;
        }
        return info.plan;
	}

    final override Variant readArray(DbNameColumn arrayColumn, DbValue arrayValueId) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (arrayValueId.isNull)
            return Variant.varNull();

        auto array = FbArray(this, arrayColumn.baseTableName, arrayColumn.baseName, arrayValueId.get!FbId());
        return array.readArray(arrayColumn);
    }

    final override ubyte[] readBlob(DbNameColumn blobColumn, DbValue blobValueId) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (blobValueId.isNull)
            return null;

        auto blob = FbBlob(this, blobValueId.get!FbId());
        return blob.openRead();
    }

    final DbValue writeArray(DbNameColumn arrayColumn, ref DbValue arrayValue) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto array = FbArray(this, arrayColumn.baseTableName, arrayColumn.baseName, 0);
        array.writeArray(arrayColumn, arrayValue);
        return DbValue(array.fbId, arrayValue.type);
    }

    final override DbValue writeBlob(DbNameColumn blobColumn, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        // Firebird always create new id
        auto blob = FbBlob(this);
        blob.openWrite(blobValue);
        return DbValue(blob.fbId, blobColumn.type);
    }

    /* Properties */

    @property final FbConnection fbConnection() nothrow pure @safe
    {
        return cast(FbConnection)connection;
    }

    @property final FbFieldList fbFields() nothrow @safe
    {
        return cast(FbFieldList)fields;
    }

    @property final FbHandle fbHandle() const nothrow @safe
    {
        return handle.get!FbHandle();
    }

    @property final FbParameterList fbParameters() nothrow @safe
    {
        return cast(FbParameterList)parameters;
    }

    @property final FbTransaction fbTransaction() nothrow pure @safe
    {
        return cast(FbTransaction)transaction;
    }

package(pham.db):
    final bool canReturnRecordsAffected() const nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (!returnRecordsAffected || commandType == DbCommandType.ddl)
            return false;

        switch (baseCommandType)
        {
            case FbIscCommandType.insert:
            case FbIscCommandType.update:
            case FbIscCommandType.delete_:
            case FbIscCommandType.storedProcedure:
                return true;
            default:
                return false;
        }
    }

    final FbParameter[] fbInputParameters() nothrow @trusted //@trusted=cast()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        return cast(FbParameter[])inputParameters();
    }

    pragma(inline, true)
    final @property bool isFbHandle() const nothrow pure @safe
    {
        static if (fbDeferredProtocol)
        {
            enum fbdh = DbHandle(fbCommandDeferredHandle);
            return _handle.isValid && _handle != fbdh;
        }
        else
            return _handle.isValid;
    }

protected:
    final void allocateHandleRead() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        _handle = protocol.allocateCommandRead(this).handle;
    }

    final void allocateHandleWrite() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        static if (fbDeferredProtocol)
            _handle = fbCommandDeferredHandle;
        auto protocol = fbConnection.protocol;
        protocol.allocateCommandWrite();
    }

    static if (fbDeferredProtocol)
    final FbDeferredResponse allocateHandleWrite(ref FbXdrWriter writer) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        static if (fbDeferredProtocol)
            _handle = fbCommandDeferredHandle;
        auto protocol = fbConnection.protocol;
        protocol.allocateCommandWrite(writer);
        return &allocateHandleRead;
    }

    final bool canBundleOperations() nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        return protocol.serverVersion >= FbIsc.protocol_version11;
    }

    final void deallocateHandle() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("fbHandle=", fbHandle);

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
        {
            batched = false;
            _handle.reset();
            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("fbHandle=", fbHandle);
        }

        try
        {
            auto protocol = fbConnection.protocol;
            static if (fbDeferredProtocol)
            {
                auto writer = FbXdrWriter(fbConnection);

                if (batched)
                {
                    protocol.releaseCommandBatchWrite(writer, this);
                    protocol.deferredResponses ~= &protocol.releaseCommandBatchRead;
                }

                protocol.deallocateCommandWrite(writer, this);
                writer.flush();

                protocol.deferredResponses ~= &protocol.deallocateCommandRead;
            }
            else
            {
                if (batched)
                {
                    protocol.releaseCommandBatchWrite(this);
                    protocol.releaseCommandBatchRead();
                }

                protocol.deallocateCommandWrite(this);
                protocol.deallocateCommandRead();
            }
        }
        catch (Exception e)
        {
            if (auto log = logger)
                log.error(forLogInfo(), newline, e.msg, e);
        }
    }

    final override void doExecuteCommand(const(DbCommandExecuteType) type) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("type=", type);
        version (profile) debug auto p = PerfFunction.create();

        // Firebird always need to do repare
        if (!prepared)
            prepare();

        prepareExecuting(type);

        auto logTimming = logger !is null
            ? LogTimming(logger, text(forLogInfo(), newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = fbConnection.protocol;

        if (executedCount > 1 && type != DbCommandExecuteType.nonQuery)
        {
            protocol.closeCursorCommandWrite(this);
            static if (fbDeferredProtocol)
                protocol.deferredResponses ~= &protocol.closeCursorCommandRead;
            else
                protocol.closeCursorCommandRead();
        }

        protocol.executeCommandWrite(this, type);

        if (isStoredProcedure)
        {
            auto response = protocol.readSqlResponse();
            if (response.count > 0)
            {
                auto row = readRow(true);
                fetchedRows.enqueue(row);
                if (hasParameters)
                    mergeOutputParams(row);
            }
        }

        protocol.executeCommandRead(this);

        if (canReturnRecordsAffected())
        {
            _recordsAffected = getRecordsAffected();

            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("_recordsAffected=", _recordsAffected);
        }
    }

    final override void doFetch(const(bool) isScalar) @safe
    in
    {
        assert(!allRowsFetched);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("isScalar=", isScalar);
        version (profile) debug auto p = PerfFunction.create();

        auto protocol = fbConnection.protocol;
        protocol.fetchCommandWrite(this);

        bool continueFetching = true;
        while (continueFetching)
        {
            auto response = protocol.fetchCommandRead(this);
            final switch (response.fetchStatus())
            {
                case DbFetchResultStatus.hasData:
                    auto row = readRow(isScalar);
                    fetchedRows.enqueue(row);
                    break;

                case DbFetchResultStatus.completed:
                    version (TraceFunction) traceFunction!("pham.db.fbdatabase")("allRowsFetched=true");
                    allRowsFetched = true;
                    continueFetching = false;
                    break;

                // Wait for next fetch call
                case DbFetchResultStatus.ready:
                    continueFetching = false;
                    break;
            }
        }
    }

    final override void doPrepare() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();
        version (profile) debug auto p = PerfFunction.create();

        auto sql = executeCommandText(BuildCommandTextState.prepare); // Make sure statement is constructed before doing other tasks

        auto logTimming = logger !is null
            ? LogTimming(logger, text(forLogInfo(), newline, sql), false, logTimmingWarningDur)
            : LogTimming.init;

        static if (fbDeferredProtocol)
        {
            FbDeferredResponse[] requestResponses;
            {
                auto writer = FbXdrWriter(fbConnection);

                if (!isFbHandle)
                    requestResponses ~= allocateHandleWrite(writer);

                requestResponses ~= doPrepareWrite(writer, sql);

                if (commandType != DbCommandType.ddl)
                    requestResponses ~= getStatementTypeWrite(writer);

                writer.flush();
            }
            foreach (ref requestResponse; requestResponses)
                requestResponse();
        }
        else
        {
            if (!isFbHandle)
            {
                allocateHandleWrite();
                allocateHandleRead();
            }

            doPrepareWrite(sql);
            doPrepareRead();

            if (commandType != DbCommandType.ddl)
            {
                getStatementTypeWrite();
                getStatementTypeRead();
            }
        }

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("fbHandle=", fbHandle, ", baseCommandType=", _baseCommandType);
    }

    final void doPrepareRead() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        processPrepareResponse(protocol.prepareCommandRead(this));
    }

    final void doPrepareWrite(scope const(char)[] sql) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.prepareCommandWrite(this, sql);
    }

    static if (fbDeferredProtocol)
    final FbDeferredResponse doPrepareWrite(ref FbXdrWriter writer, scope const(char)[] sql) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.prepareCommandWrite(writer, this, sql);
        return &doPrepareRead;
    }

    final override void doUnprepare() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (isFbHandle)
            deallocateHandle();
    }

    FbCommandBatchResult[] executeNonQueryBatch(ref FbCommandBatch commandBatch) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();
        version (profile) debug auto p = PerfFunction.create();

        auto protocol = fbConnection.protocol;

        {
            auto writer = FbXdrWriter(fbConnection);
            if (!this.batched)
                protocol.createCommandBatchWrite(writer, commandBatch);
            protocol.messageCommandBatchWrite(writer, commandBatch);
            protocol.executeCommandBatchWrite(writer, commandBatch);

            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("data=", writer.peekBytes().dgToHex());

            writer.flush();
        }

        if (!this.batched)
        {
            protocol.createCommandBatchRead(commandBatch);
            this.batched = true;
        }
        protocol.messageCommandBatchRead(commandBatch);
        auto response = protocol.executeCommandBatchRead(commandBatch);
        return response.toCommandBatchResult();
    }

    static void fillNamedColumn(DbNameColumn column, const ref FbIscFieldInfo iscField, const(bool) isNew) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")(iscField.traceString());
        //import pham.utl.test; dgWriteln("fillNamedColumn=", iscField.traceString());

        column.baseName = iscField.name.idup;
        column.baseOwner = iscField.owner.idup;
        column.baseNumericScale = iscField.numericScale;
        column.baseSize = iscField.size;
        column.baseSubTypeId = iscField.subType;
        column.baseTableName = iscField.tableName.idup;
        column.baseTypeId = iscField.type;
        column.allowNull = iscField.allowNull;

        if (isNew || column.type == DbType.unknown)
        {
            column.type = iscField.dbType();
            column.size = iscField.dbTypeSize();
        }
    }

    final DbRecordsAffected getRecordsAffected() @safe
	{
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.recordsAffectedCommandWrite(this);
        return protocol.recordsAffectedCommandRead();
	}

	final void getStatementTypeRead() @safe
	{
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        _baseCommandType = protocol.typeCommandRead(this);
	}

	final void getStatementTypeWrite() @safe
	{
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.typeCommandWrite(this);
	}

    static if (fbDeferredProtocol)
	final FbDeferredResponse getStatementTypeWrite(ref FbXdrWriter writer) nothrow @safe
	{
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.typeCommandWrite(writer, this);
        return &getStatementTypeRead;
	}

    final override bool isSelectCommandType() const nothrow @safe
    {
        return baseCommandType == FbIscCommandType.select
            || baseCommandType == FbIscCommandType.selectForUpdate;
    }

    final void processPrepareResponse(scope FbIscBindInfo[] iscBindInfos) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        const isStoredProcedure = commandType == DbCommandType.storedProcedure;

        foreach (ref iscBindInfo; iscBindInfos)
        {
            if (iscBindInfo.selectOrBind == FbIsc.isc_info_sql_select)
            {
                version (TraceFunction) traceFunction!("pham.db.fbdatabase")("fields");

                const localIsStoredProcedure = isStoredProcedure;
                auto localParameters = localIsStoredProcedure ? parameters : null;
                auto localFields = fields;
                foreach (i, ref iscField; iscBindInfo.fields)
                {
                    auto newField = localFields.createField(this, iscField.useName.idup);
                    newField.isAlias = iscField.aliasName.length != 0;
                    fillNamedColumn(newField, iscField, true);
                    localFields.put(newField);

                    if (localIsStoredProcedure)
                    {
                        auto foundParameter = localParameters.hasOutputParameter(newField.name, i);
                        if (foundParameter is null)
                        {
                            auto newParameter = localParameters.createParameter(newField.name);
                            newParameter.direction = DbParameterDirection.output;
                            fillNamedColumn(newParameter, iscField, true);
                            localParameters.put(newParameter);
                        }
                        else
                        {
                            if (foundParameter.name.length == 0 && newField.name.length != 0)
                                foundParameter.updateEmptyName(newField.name);
                            fillNamedColumn(foundParameter, iscField, false);
                        }
                    }
                }
            }
            else if (iscBindInfo.selectOrBind == FbIsc.isc_info_sql_bind)
            {
                version (TraceFunction) traceFunction!("pham.db.fbdatabase")("parameters");

                auto localParameters = parameters;
                foreach (i, ref iscField; iscBindInfo.fields)
                {
                    if (i >= localParameters.length)
                    {
                        auto newName = iscField.useName.idup;
                        if (localParameters.exist(newName))
                            newName = localParameters.generateParameterName();
                        auto newParameter = localParameters.createParameter(newName);
                        fillNamedColumn(newParameter, iscField, true);
                        localParameters.put(newParameter);
                    }
                    else
                        fillNamedColumn(localParameters[i], iscField, false);
                }
            }
            else
            {
                assert(false, "Unknown binding type: " ~ to!string(iscBindInfo.selectOrBind));
            }
        }
    }

    final DbRowValue readRow(const(bool) isScalar) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("isScalar=", isScalar);
        version (profile) debug auto p = PerfFunction.create();

        auto protocol = fbConnection.protocol;
        auto result = protocol.readValues(this, fbFields);
        if (isScalar)
        {
            size_t i = 0;
            foreach (field; fbFields)
            {
                final switch (field.isValueIdType())
                {
                    case DbFieldIdType.no:
                        break;
                    case DbFieldIdType.array:
                        result[i].value = readArray(field, result[i]);
                        break;
                    case DbFieldIdType.blob:
                        result[i].value = Variant(readBlob(field, result[i]));
                        break;
                    case DbFieldIdType.clob:
                        result[i].value = Variant(readClob(field, result[i]));
                        break;
                }
                i++;
            }
        }
        return result;
    }

    final void removeBatch(ref FbCommandBatch commandBatch) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        assert(commandBatch.fbCommand is this);

        scope (exit)
            batched = false;
        auto protocol = fbConnection.protocol;
        protocol.releaseCommandBatchWrite(this);
        protocol.deferredResponses ~= &protocol.releaseCommandBatchRead;
    }
}

// Firebird >= v4.0
struct FbCommandBatch
{
@safe:

public:
    @disable this(this);

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    FbParameterList addParameters() nothrow
    {
        auto result = cast(FbParameterList)_command.database.createParameterList();
        _parameters ~= result;
        return result;
    }

    void clearParameters() nothrow @trusted
    {
        _parameters.length = 0;
        _parameters.assumeSafeAppend();
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        if (_command)
        {
            try
            {
                if (_commandOwned)
                    _command.dispose(disposingReason);
                else if (_preparedState == PreparedState.implicit)
                    _command.unprepare();
                else
                    _command.removeBatch(this);
            }
            catch (Exception e)
            {
                if (auto log = logger)
                    log.error(e.msg, e);
            }
        }

        _parameters = null;
        _preparedState = PreparedState.unknown;
        if (isDisposing(disposingReason))
        {
            _command = null;
            _commandOwned = false;
        }
    }

    FbCommandBatchResult[] executeNonQuery()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (_parameters.length == 0)
            return [];

        if (_preparedState == PreparedState.unknown || !_command.prepared)
        {
            if (_command.prepared)
                _preparedState = PreparedState.explicit;
            else
            {
                _command.prepare();
                _preparedState = PreparedState.implicit;
            }
        }

        return _command.executeNonQueryBatch(this);
    }

    ref typeof(this) prepare() return
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (!_command.prepared)
        {
            _command.prepare();
            _preparedState = PreparedState.explicit;
        }
        return this;
    }

    @property FbCommand fbCommand() nothrow pure
    {
        return _command;
    }

    @property final FbConnection fbConnection() nothrow pure
    {
        return _command.fbConnection;
    }

    @property FbTransaction fbTransaction() nothrow pure
    {
        return _command.fbTransaction;
    }

    @property Logger logger() nothrow pure
    {
        return _command !is null ? _command.logger : null;
    }

    @property FbParameterList[] parameters() nothrow pure
    {
        return _parameters;
    }

public:
    uint maxBatchBufferLength = FbIscSize.maxBatchBufferLength;
    bool multiErrors = true;

private:
    this(FbCommand command, bool commandOwned, size_t parametersCapacity = 0) nothrow pure
    {
        this._command = command;
        this._commandOwned = commandOwned;
        if (parametersCapacity != 0)
            this._parameters.reserve(parametersCapacity);
    }

private:
    enum PreparedState : ubyte { unknown, explicit, implicit, }

    FbCommand _command;
    FbParameterList[] _parameters;
    PreparedState _preparedState;
    bool _commandOwned;
}

class FbConnection : SkConnection
{
public:
    this(FbDatabase database) nothrow @safe
    {
        super(database);
        this._arrayManager = FbArrayManager(this);
    }

    this(FbDatabase database, string connectionString) @safe
    {
        super(database, connectionString);
        this._arrayManager = FbArrayManager(this);
    }

    this(DbDatabase database, FbConnectionStringBuilder connectionString) nothrow @safe
    {
        super(database, connectionString);
        this._arrayManager = FbArrayManager(this);
    }

    this(DbDatabase database, DbURL!string connectionString) @safe
    {
        super(database, connectionString);
        this._arrayManager = FbArrayManager(this);
    }

    // Firebird >= v4.0
    final FbCommandBatch createCommandBatch(string commandText, size_t parametersCapacity = 0) @safe
    {
        auto command = cast(FbCommand)createCommandText(commandText);
        return FbCommandBatch(command, true, parametersCapacity);
    }

    final override DbCancelCommandData createCancelCommandData(DbCommand command = null) nothrow @safe
    {
        FbCancelCommandData result = new FbCancelCommandData();
        result.connectionHandle = fbHandle;
        return result;
    }

    final void createDatabase(FbCreateDatabaseInfo createDatabaseInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (state == DbConnectionState.opened)
        {
            _protocol.createDatabaseWrite(createDatabaseInfo);
            _protocol.createDatabaseRead();
        }
        else
        {
            auto saveType = _type;
            _createDatabaseInfo = createDatabaseInfo;
            _type = DbConnectionType.create;
            scope (exit)
            {
                _type = saveType;
                _createDatabaseInfo = FbCreateDatabaseInfo.init;
            }

            open();
            close();
        }
    }

    @property final ref FbArrayManager arrayManager() nothrow @safe
    {
        return _arrayManager;
    }

    @property final int16 dialect() nothrow @safe
    {
        return fbConnectionStringBuilder.dialect;
    }

    @property final FbConnectionStringBuilder fbConnectionStringBuilder() nothrow pure @safe
    {
        return cast(FbConnectionStringBuilder)connectionStringBuilder;
    }

    @property final FbHandle fbHandle() const nothrow @safe
    {
        return handle.get!FbHandle();
    }

    /**
     * Only available after open
     */
    @property final FbProtocol protocol() nothrow pure @safe
    {
        return _protocol;
    }

    @property final override DbScheme scheme() const nothrow pure @safe
    {
        return DbScheme.fb;
    }

    @property final override bool supportMultiReaders() const nothrow pure @safe
    {
        return true;
    }

package(pham.db):
    final DbWriteBuffer acquireParameterWriteBuffer(size_t capacity = FbIscSize.parameterBufferLength) nothrow @safe
    {
        if (_parameterWriteBuffers.empty)
            return new SkWriteBuffer(this, capacity);
        else
            return cast(DbWriteBuffer)(_parameterWriteBuffers.remove(_parameterWriteBuffers.last));
    }

    final void releaseParameterWriteBuffer(DbWriteBuffer item) nothrow @safe
    {
        if (!isDisposing(lastDisposingReason))
            _parameterWriteBuffers.insertEnd(item.reset());
    }

protected:
    final override SkException createConnectError(int errorCode, string errorMessage, Exception e) @safe
    {
        auto result = super.createConnectError(errorCode, errorMessage, e);
        result.vendorCode = FbIscResultCode.isc_net_connect_err;
        return result;
    }

    final override SkException createReadDataError(int errorCode, string errorMessage, Exception e) @safe
    {
        auto result = super.createReadDataError(errorCode, errorMessage, e);
        result.vendorCode = FbIscResultCode.isc_net_read_err;
        return result;
    }

    final override SkException createWriteDataError(int errorCode, string errorMessage, Exception e) @safe
    {
        auto result = super.createWriteDataError(errorCode, errorMessage, e);
        result.vendorCode = FbIscResultCode.isc_net_write_err;
        return result;
    }

    override void disposeCommands(const(DisposingReason) disposingReason) nothrow @safe
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        if (isDisposing(disposingReason))
            this._arrayManager.dispose(disposingReason);
        else
            this._arrayManager.close();
        super.disposeCommands(disposingReason);
    }

    final void disposeParameterWriteBuffers(const(DisposingReason) disposingReason) nothrow @safe
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        while (!_parameterWriteBuffers.empty)
            _parameterWriteBuffers.remove(_parameterWriteBuffers.last).dispose(disposingReason);
    }

    final void disposeProtocol(const(DisposingReason) disposingReason) nothrow @safe
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        if (_protocol !is null)
        {
            _protocol.dispose(disposingReason);
            _protocol = null;
        }
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        version (TraceFunction) { import pham.utl.test; debug dgWriteln(__FUNCTION__); }

        super.doDispose(disposingReason);
        disposeParameterWriteBuffers(disposingReason);
        disposeProtocol(disposingReason);
    }

    final override void doCancelCommand(DbCancelCommandData data) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto fbData = cast(FbCancelCommandData)data;
        _protocol.cancelRequestWrite(fbData.connectionHandle);
    }

    final override void doClose(bool failedOpen) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("failedOpen=", failedOpen, ", socketActive=", socketActive);

        scope (exit)
            disposeProtocol(DisposingReason.other);

        if (!failedOpen)
            _arrayManager.doClose(DisposingReason.other);

        try
        {
            if (!failedOpen && _protocol !is null && canWriteDisconnectMessage())
                _protocol.disconnectWrite();
        }
        catch (Exception e)
        {
            if (auto log = logger)
                log.error(e.msg, e);
        }

        super.doClose(failedOpen);
    }

    final override void doOpen() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbConnectingStateInfo stateInfo;
        stateInfo.connectionType = _type;

        doOpenSocket();
        doOpenAuthentication(stateInfo);
        doOpenAttachment(stateInfo);
    }

    final void doOpenAttachment(ref FbConnectingStateInfo stateInfo) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        protocol.connectAttachmentWrite(stateInfo, _createDatabaseInfo);
        _handle = protocol.connectAttachmentRead(stateInfo).handle;
    }

    final void doOpenAuthentication(ref FbConnectingStateInfo stateInfo) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        _protocol = new FbProtocol(this);
        _protocol.connectAuthenticationWrite(stateInfo, _createDatabaseInfo);
        _protocol.connectAuthenticationRead(stateInfo);
    }

    final override string getServerVersion() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto command = createCommand();
        scope (exit)
            command.dispose();

        // ex: "3.0.7"
        command.commandText = "SELECT rdb$get_context('SYSTEM', 'ENGINE_VERSION') FROM rdb$database";
        auto v = command.executeScalar();
        return v.isNull() ? null : v.get!string();
    }

protected:
    FbArrayManager _arrayManager;
    FbProtocol _protocol;
    FbCreateDatabaseInfo _createDatabaseInfo;

private:
    DLinkDbBufferTypes.DLinkList _parameterWriteBuffers;
}

class FbConnectionStringBuilder : SkConnectionStringBuilder
{
@safe:

public:
    this(DbDatabase database) nothrow
    {
        super(database);
    }

    this(DbDatabase database, string connectionString)
    {
        super(database, connectionString);
    }

    final string integratedSecurityName() const nothrow
    {
        final switch (integratedSecurity) with (DbIntegratedSecurityConnection)
        {
            case legacy:
                return FbIscText.authLegacyName;
            case srp1:
                return FbIscText.authSrp1Name;
            case srp256:
                return FbIscText.authSrp256Name;
            case sspi:
                return FbIscText.authSspiName;
        }
    }

    final override const(string[]) parameterNames() const nothrow
    {
        return fbValidConnectionParameterNames;
    }

    @property final uint32 cachePages() nothrow
    {
        return toIntegerSafe!uint32(getString(DbConnectionParameterIdentifier.fbCachePage), uint16.max);
    }

    @property final string cryptAlgorithm() nothrow
    {
        return getString(DbConnectionParameterIdentifier.fbCryptAlgorithm);
    }

    @property final typeof(this) cryptAlgorithm(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.fbCryptAlgorithm, value.length != 0 ? value : FbIscText.filterCryptDefault);
        return this;
    }

    @property final ubyte[] cryptKey() nothrow
    {
        return bytesFromBase64s(getString(DbConnectionParameterIdentifier.fbCryptKey));
    }

    @property final typeof(this) cryptKey(scope const(ubyte)[] value) nothrow
    {
        put(DbConnectionParameterIdentifier.fbCryptKey, bytesToBase64s(value));
        return this;
    }

    @property final bool databaseTrigger() nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.fbDatabaseTrigger));
    }

    @property final int16 dialect() nothrow
    {
        return toIntegerSafe!int16(getString(DbConnectionParameterIdentifier.fbDialect), FbIscDefault.dialect);
    }

    @property final Duration dummyPackageInterval() nothrow
    {
        return secondDigitsToDurationSafe(getString(DbConnectionParameterIdentifier.fbDummyPacketInterval), Duration.zero);
    }

    @property final bool garbageCollect() nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.fbGarbageCollect));
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.fb;
    }

protected:
    final override string getDefault(string name) const nothrow
    {
        auto n = DbIdentitier(name);
        auto result = assumeWontThrow(fbDefaultConnectionParameterValues.get(n, null));
        if (result.ptr is null)
            result = super.getDefault(name);
        return result;
    }

    final override void setDefaultIfs() nothrow
    {
        foreach (dpv; fbDefaultConnectionParameterValues.byKeyValue)
            putIf(dpv.key, dpv.value);
        super.setDefaultIfs();
    }
}

class FbDatabase : DbDatabase
{
@safe:

public:
    this() nothrow pure
    {
        this._name = DbIdentitier(DbScheme.fb);
        this._identifierQuoteChar = '"';
        this._stringQuoteChar = '\'';

        this._charClasses['"'] = CharClass.quote;
        this._charClasses['\''] = CharClass.quote;
        this._charClasses['\\'] = CharClass.backslash;

        this.populateValidParamNameChecks();
    }

    final override const(string[]) connectionStringParameterNames() const nothrow pure
    {
        return fbValidConnectionParameterNames;
    }

    override DbCommand createCommand(DbConnection connection,
        string name = null) nothrow
    in
    {
        assert((cast(FbConnection)connection) !is null);
    }
    do
    {
        return new FbCommand(cast(FbConnection)connection, name);
    }

    override DbCommand createCommand(DbConnection connection, DbTransaction transaction,
        string name = null) nothrow
    in
    {
        assert((cast(FbConnection)connection) !is null);
        assert((cast(FbTransaction)transaction) !is null);
    }
    do
    {
        return new FbCommand(cast(FbConnection)connection, cast(FbTransaction)transaction, name);
    }

    override DbConnection createConnection(string connectionString)
    {
        auto result = new FbConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbConnectionStringBuilder connectionString) nothrow
    in
    {
        assert(connectionString !is null);
        assert(connectionString.scheme == DbScheme.fb);
        assert(cast(FbConnectionStringBuilder)connectionString !is null);
    }
    do
    {
        auto result = new FbConnection(this, cast(FbConnectionStringBuilder)connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbURL!string connectionString)
    in
    {
        assert(DbURL.scheme == DbScheme.fb);
        assert(DbURL.isValid());
    }
    do
    {
        auto result = new FbConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnectionStringBuilder createConnectionStringBuilder() nothrow
    {
        return new FbConnectionStringBuilder(this);
    }

    override DbConnectionStringBuilder createConnectionStringBuilder(string connectionString)
    {
        return new FbConnectionStringBuilder(this, connectionString);
    }

    override DbField createField(DbCommand command, DbIdentitier name) nothrow
    in
    {
        assert((cast(FbCommand)command) !is null);
    }
    do
    {
        return new FbField(cast(FbCommand)command, name);
    }

    override DbFieldList createFieldList(DbCommand command) nothrow
    in
    {
        assert(cast(FbCommand)command !is null);
    }
    do
    {
        return new FbFieldList(cast(FbCommand)command);
    }

    override DbParameter createParameter(DbIdentitier name) nothrow
    {
        return new FbParameter(this, name);
    }

    override DbParameterList createParameterList() nothrow
    {
        return new FbParameterList(this);
    }

    override DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel,
        bool defaultTransaction = false) nothrow
    in
    {
        assert((cast(FbConnection)connection) !is null);
    }
    do
    {
        const isRetaining = defaultTransaction;
        return new FbTransaction(cast(FbConnection)connection, isolationLevel, isRetaining);
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.fb;
    }
}

class FbField : DbField
{
public:
    this(FbCommand command, DbIdentitier name) nothrow pure @safe
    {
        super(command, name);
    }

    final override DbField createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createField(cast(FbCommand)command, name)
            : new FbField(cast(FbCommand)command, name);
    }

    final override DbFieldIdType isValueIdType() const nothrow pure @safe
    {
        return FbIscFieldInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

    @property final FbCommand fbCommand() nothrow pure @safe
    {
        return cast(FbCommand)_command;
    }
}

class FbFieldList: DbFieldList
{
public:
    this(FbCommand command) nothrow pure @safe
    {
        super(command);
    }

    final override DbField createField(DbCommand command, DbIdentitier name) nothrow
    {
        return database !is null
            ? database.createField(cast(FbCommand)command, name)
            : new FbField(cast(FbCommand)command, name);
    }

    final override DbFieldList createSelf(DbCommand command) nothrow
    {
        return database !is null
            ? database.createFieldList(cast(FbCommand)command)
            : new FbFieldList(cast(FbCommand)command);
    }

    @property final FbCommand fbCommand() nothrow pure @safe
    {
        return cast(FbCommand)_command;
    }
}

class FbParameter : DbParameter
{
public:
    this(FbDatabase database, DbIdentitier name) nothrow pure @safe
    {
        super(database, name);
    }

    final override DbFieldIdType isValueIdType() const nothrow pure @safe
    {
        return FbIscFieldInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

package(pham.db):
    final void prepareParameter(FbCommand command) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        if (!isInput || isNull)
            return;

        final switch (isValueIdType)
        {
            case DbFieldIdType.no:
                break;
            case DbFieldIdType.array:
                auto arrayId = command.writeArray(this, value);
                value.setEntity(arrayId.get!FbId(), type);
                break;
            case DbFieldIdType.blob:
                auto blob = value.get!(const(ubyte)[])();
                auto blobId = command.writeBlob(this, blob);
                value.setEntity(blobId.get!FbId(), type);
                break;
            case DbFieldIdType.clob:
                auto clob = value.get!(const(char)[])();
                auto clobId = command.writeClob(this, clob);
                value.setEntity(clobId.get!FbId(), type);
                break;
        }
    }
}

class FbParameterList : DbParameterList
{
public:
    this(FbDatabase database) nothrow pure @safe
    {
        super(database);
    }
}

class FbTransaction : DbTransaction
{
public:
    this(FbConnection connection, DbIsolationLevel isolationLevel, bool retaining) nothrow @safe
    {
        super(connection, isolationLevel);
        this._flags.set(DbTransactionFlag.retaining, retaining);
    }

    final override bool canSavePoint() @safe
    {
        enum minSupportVersion = VersionString("4.0");
        return super.canSavePoint() && VersionString(connection.serverVersion()) >= minSupportVersion;
    }

    @property final FbConnection fbConnection() nothrow pure @safe
    {
        return cast(FbConnection)connection;
    }

    @property final FbHandle fbHandle() const nothrow @safe
    {
        return handle.get!FbHandle();
    }

    /**
     * Allows application to customize the transaction request
     */
    @property final ubyte[] transactionItems() nothrow @safe
    {
        return _transactionItems;
    }

    @property final typeof(this) transactionItems(ubyte[] value) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        _transactionItems = value;
        return this;
    }

protected:
    final override void doCommit(bool disposing) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("disposing=", disposing);

        const canRetain = !disposing && isRetaining && !isDisposing(lastDisposingReason);
        auto protocol = fbConnection.protocol;
        if (!disposing && canRetain)
        {
            scope (failure)
                _handle.reset();

            protocol.commitRetainingTransactionWrite(this);
            protocol.commitTransactionRead();
        }
        else
        {
            scope (exit)
                _handle.reset();

            protocol.commitTransactionWrite(this);
            protocol.commitTransactionRead();
        }
    }

    final override void doRollback(bool disposing) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("disposing=", disposing);

        auto protocol = fbConnection.protocol;
        if (!disposing && canRetain())
        {
            scope (failure)
                _handle.reset();

            protocol.rollbackRetainingTransactionWrite(this);
            protocol.rollbackTransactionRead();
        }
        else
        {
            scope (exit)
                _handle.reset();

            protocol.rollbackTransactionWrite(this);
            protocol.rollbackTransactionRead();
        }
    }

    final override void doStart() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto protocol = fbConnection.protocol;
        protocol.startTransactionWrite(this);
        _handle = protocol.startTransactionRead().handle;
    }

private:
    ubyte[] _transactionItems;
}


// Any below codes are private
private:

shared static this()
{
    version (TraceFunctionFBDatabase) ModuleLoggerOptions.setModule(ModuleLoggerOption(LogLevel.trace, "pham.db.fbdatabase"));

    auto db = new FbDatabase();
    DbDatabaseList.registerDb(db);
}

version (UnitTestFBDatabase)
{
    FbConnection createTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        DbCompressConnection compress = DbCompressConnection.disabled,
        DbIntegratedSecurityConnection integratedSecurity = DbIntegratedSecurityConnection.srp256)
    {
        auto db = DbDatabaseList.getDb(DbScheme.fb);
        assert(cast(FbDatabase)db !is null);

        auto result = db.createConnection("");
        assert(cast(FbConnection)result !is null);

        auto csb = (cast(FbConnection)result).fbConnectionStringBuilder;
        csb.databaseName = "UNIT_TEST";  // Use alias mapping name
        csb.receiveTimeout = dur!"seconds"(40);
        csb.sendTimeout = dur!"seconds"(20);
        csb.encrypt = encrypt;
        csb.compress = compress;
        csb.integratedSecurity = integratedSecurity;

        return cast(FbConnection)result;
    }

    string testCreateDatabaseFileName()
    {
        return "C:\\Development\\Projects\\DLang\\FirebirdSQL\\TEST_CREATE.FDB";
    }

    string testTableSchema() nothrow pure @safe
    {
        return q"{
CREATE TABLE TEST_SELECT (
  INT_FIELD INTEGER NOT NULL,
  SMALLINT_FIELD SMALLINT,
  FLOAT_FIELD FLOAT,
  DOUBLE_FIELD DOUBLE PRECISION,
  NUMERIC_FIELD NUMERIC(15, 2),
  DECIMAL_FIELD DECIMAL(15, 2),
  DATE_FIELD DATE,
  TIME_FIELD TIME,
  TIMESTAMP_FIELD TIMESTAMP,
  CHAR_FIELD CHAR(10),
  VARCHAR_FIELD VARCHAR(10),
  BLOB_FIELD BLOB,
  TEXT_FIELD BLOB SUB_TYPE 1 SEGMENT SIZE 1000,
  INTEGER_ARRAY INTEGER[10],
  BIGINT_FIELD BIGINT)
}";
    }

    string testTableData() nothrow pure @safe
    {
        return q"{
INSERT INTO TEST_SELECT (INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD, NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD, CHAR_FIELD, VARCHAR_FIELD, INTEGER_ARRAY, BIGINT_FIELD)
VALUES (1, 2, 3.10, 4.2, 5.4, 6.5, '2020-05-20', '01:01:01', '2020-05-20 07:31:00', 'ABC', 'XYZ', NULL, 4294967296)
}";
    }

    string simpleSelectCommandText() nothrow pure @safe
    {
        return q"{
SELECT INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD,
    NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD,
    CHAR_FIELD, VARCHAR_FIELD, BLOB_FIELD, TEXT_FIELD, BIGINT_FIELD, INTEGER_ARRAY
FROM TEST_SELECT
WHERE INT_FIELD = 1
}";
    }

    string parameterSelectCommandText() nothrow pure @safe
    {
        return q"{
SELECT INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD,
	NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD,
	CHAR_FIELD, VARCHAR_FIELD, BLOB_FIELD, TEXT_FIELD, BIGINT_FIELD, INTEGER_ARRAY
FROM TEST_SELECT
WHERE INT_FIELD = @INT_FIELD
	AND DOUBLE_FIELD = @DOUBLE_FIELD
	AND DECIMAL_FIELD = @DECIMAL_FIELD
	AND DATE_FIELD = @DATE_FIELD
	AND TIME_FIELD = @TIME_FIELD
	AND CHAR_FIELD = @CHAR_FIELD
	AND VARCHAR_FIELD = @VARCHAR_FIELD
}";
    }
}

unittest // FbConnectionStringBuilder
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbConnectionStringBuilder");

    auto db = DbDatabaseList.getDb(DbScheme.fb);
    assert(cast(FbDatabase)db !is null);

    auto connectionStringBuiler = db.createConnectionStringBuilder(null);
    assert(cast(FbConnectionStringBuilder)connectionStringBuiler !is null);
    auto useCSB = cast(FbConnectionStringBuilder)connectionStringBuiler;

    assert(useCSB.serverName == "localhost");
    assert(useCSB.serverPort == 3050);
    assert(useCSB.userName == "SYSDBA");
    assert(useCSB.userPassword == "masterkey");
    assert(useCSB.dialect == 3);
}

version (UnitTestFBDatabase)
unittest // FbConnection
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbConnection");

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version (UnitTestFBDatabase)
unittest // FbConnection.encrypt
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbConnection - encrypt");

    {
        auto connection = createTestConnection(DbEncryptedConnection.enabled);
        scope (exit)
            connection.dispose();
        assert(connection.state == DbConnectionState.closed);

        connection.open();
        assert(connection.state == DbConnectionState.opened);

        connection.close();
        assert(connection.state == DbConnectionState.closed);
    }

    {
        auto connection = createTestConnection(DbEncryptedConnection.required);
        connection.fbConnectionStringBuilder.cryptAlgorithm = FbIscText.filterCryptArc4Name;
        scope (exit)
            connection.dispose();
        assert(connection.state == DbConnectionState.closed);

        connection.open();
        assert(connection.state == DbConnectionState.opened);

        connection.close();
        assert(connection.state == DbConnectionState.closed);
    }

    //version (none) // TODO
    {
        auto connection = createTestConnection(DbEncryptedConnection.required);
        connection.fbConnectionStringBuilder.cryptAlgorithm = FbIscText.filterCryptChachaName;
        scope (exit)
            connection.dispose();
        assert(connection.state == DbConnectionState.closed);

        connection.open();
        assert(connection.state == DbConnectionState.opened);

        connection.close();
        assert(connection.state == DbConnectionState.closed);
    }
}

version (UnitTestFBDatabase)
unittest // FbConnection.integratedSecurity
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbConnection - integratedSecurity");

    version (Windows)
    {
        auto connection = createTestConnection(DbEncryptedConnection.enabled, DbCompressConnection.disabled, DbIntegratedSecurityConnection.srp256);
        scope (exit)
            connection.dispose();
        assert(connection.state == DbConnectionState.closed);

        connection.open();
        assert(connection.state == DbConnectionState.opened);

        connection.close();
        assert(connection.state == DbConnectionState.closed);
    }
}

version (UnitTestFBDatabase)
unittest // FbConnection.encrypt.compress
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbConnection - encrypt=required, compress=zip");

    auto connection = createTestConnection(DbEncryptedConnection.required, DbCompressConnection.zip);
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version (UnitTestFBDatabase)
unittest // FbTransaction
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbTransaction");

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto transaction = connection.createTransaction(DbIsolationLevel.readUncommitted);
    transaction.start();
    transaction.commit();

    transaction = connection.createTransaction(DbIsolationLevel.readCommitted);
    transaction.start();
    transaction.commit();

    transaction = connection.createTransaction(DbIsolationLevel.repeatableRead);
    transaction.start();
    transaction.commit();

    transaction = connection.createTransaction(DbIsolationLevel.serializable);
    transaction.start();
    transaction.commit();

    transaction = connection.createTransaction(DbIsolationLevel.snapshot);
    transaction.start();
    transaction.commit();

    transaction = connection.defaultTransaction();
    transaction.start();
    transaction.rollback();
}

version (UnitTestFBDatabase)
unittest // FbTransaction.encrypt.compress
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbTransaction - encrypt=enabled, compress=zip");

    auto connection = createTestConnection(DbEncryptedConnection.enabled, DbCompressConnection.zip);
    scope (exit)
        connection.dispose();
    connection.open();

    auto transaction = connection.createTransaction(DbIsolationLevel.readCommitted);
    transaction.start();
    transaction.commit();
}

version (UnitTestFBDatabase)
unittest // FbCommand.DDL
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DDL");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    version (TraceFunction) traceFunction!("pham.db.fbdatabase")("CREATE TABLE");
    command.commandDDL = "CREATE TABLE create_then_drop (a INT NOT NULL PRIMARY KEY, b VARCHAR(100))";
    command.executeNonQuery();

    version (TraceFunction) traceFunction!("pham.db.fbdatabase")("DROP TABLE");
    command.commandDDL = "DROP TABLE create_then_drop";
    command.executeNonQuery();

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DDL.encrypt.compress
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DDL - encrypt=enabled, compress=zip");

    bool failed = true;
    auto connection = createTestConnection(DbEncryptedConnection.enabled, DbCompressConnection.zip);
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandDDL = q"{CREATE TABLE create_then_drop (a INT NOT NULL PRIMARY KEY, b VARCHAR(100))}";
    command.executeNonQuery();

    command.commandDDL = q"{DROP TABLE create_then_drop}";
    command.executeNonQuery();

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.getExecutionPlan
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.getExecutionPlan");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();

    auto expectedDefault = q"{
PLAN (TEST_SELECT NATURAL)}";
    auto planDefault = command.getExecutionPlan();
    //traceUnitTest!("pham.db.fbdatabase")("'", planDefault, "'");
    //traceUnitTest!("pham.db.fbdatabase")("'", expectedDefault, "'");
    assert(planDefault == expectedDefault);

    auto expectedDetail = q"{
Select Expression
    -> Filter
        -> Table "TEST_SELECT" Full Scan}";
    auto planDetail = command.getExecutionPlan(1);
    //traceUnitTest!("pham.db.fbdatabase")("'", planDetail, "'");
    //traceUnitTest!("pham.db.fbdatabase")("'", expectedDetail, "'");
    assert(planDetail == expectedDetail);

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.Types
{
    import std.conv;
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.Types");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    // char
    {
        command.commandText = "select cast(null as char(1)) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast('a' as char(1)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!string() == "a");

	    command.commandText = "select cast(' abc ' as char(5)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!string() == " abc ");
    }

    // varchar
    {
        command.commandText = "select cast(null as varchar(10)) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast('a' as varchar(10)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!string() == "a");

	    command.commandText = "select cast(' abc' as varchar(10)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!string() == " abc");
    }

    // double
    {
        command.commandText = "select cast(null as double precision) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0.0 as double precision) from rdb$database";
        v = command.executeScalar();
        assert(v.get!double() == 0.0);

	    command.commandText = "select cast(-1.0 as double precision) from rdb$database";
        v = command.executeScalar();
        assert(v.get!double() == -1.0);

	    command.commandText = "select cast(1.0 as double precision) from rdb$database";
        v = command.executeScalar();
        assert(v.get!double() == 1.0);

        const double dmin = to!double("-3.40E+38");
	    command.commandText = "select cast((-3.40E+38) as double precision) from rdb$database";
        v = command.executeScalar();
        assert(v.get!double() == dmin);

        const double dmax = to!double("3.40E+38");
	    command.commandText = "select cast((3.40E+38) as double precision) from rdb$database";
        v = command.executeScalar();
        assert(v.get!double() == dmax);
    }

    // float
    {
        command.commandText = "select cast(null as float) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0.0 as float) from rdb$database";
        v = command.executeScalar();
        assert(v.get!float() == 0.0);

	    command.commandText = "select cast(-1.0 as float) from rdb$database";
        v = command.executeScalar();
        assert(v.get!float() == -1.0);

	    command.commandText = "select cast(1.0 as float) from rdb$database";
        v = command.executeScalar();
        assert(v.get!float() == 1.0);

        const float fmin = to!float("-1.79E+38");
	    command.commandText = "select cast((-1.79E+38) as float) from rdb$database";
        v = command.executeScalar();
        assert(v.get!float() == fmin);

        const float fmax = to!float("1.79E+38");
	    command.commandText = "select cast((1.79E+38) as float) from rdb$database";
        v = command.executeScalar();
        assert(v.get!float() == fmax);
    }

    // smallint
    {
        command.commandText = "select cast(null as smallint) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as smallint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int16() == 0);

	    command.commandText = "select cast(-1 as smallint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int16() == -1);

	    command.commandText = "select cast(1 as smallint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int16() == 1);

	    command.commandText = "select cast(-32768 as smallint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int16() == -32768);

	    command.commandText = "select cast(32767 as smallint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int16() == 32767);
    }

    // integer
    {
        command.commandText = "select cast(null as integer) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as integer) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int32() == 0);

	    command.commandText = "select cast(-1 as integer) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int32() == -1);

	    command.commandText = "select cast(1 as integer) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int32() == 1);

	    command.commandText = "select cast(-2147483648 as integer) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int32() == -2147483648);

	    command.commandText = "select cast(2147483647 as integer) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int32() == 2147483647);
    }

    // bigint
    {
        command.commandText = "select cast(null as bigint) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as bigint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int64() == 0);

	    command.commandText = "select cast(-1 as bigint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int64() == -1);

	    command.commandText = "select cast(1 as bigint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int64() == 1);

	    command.commandText = "select cast('-9223372036854775808' as bigint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int64() == -9223372036854775808);

	    command.commandText = "select cast('9223372036854775807' as bigint) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int64() == 9223372036854775807);
    }

    const dbVersion = VersionString(connection.serverVersion());

    // boolean
    if (dbVersion >= "3.0")
    {
        command.commandText = "select cast(null as boolean) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(false as boolean) from rdb$database";
        v = command.executeScalar();
        assert(v.get!bool() == false);

	    command.commandText = "select cast(true as boolean) from rdb$database";
        v = command.executeScalar();
        assert(v.get!bool() == true);
    }

    // int128
    if (dbVersion >= "4.0")
    {
        command.commandText = "select cast(null as int128) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as int128) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int128() == 0);

	    command.commandText = "select cast(-1 as int128) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int128() == -1, v.get!int128().toString());

	    command.commandText = "select cast(1 as int128) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int128() == 1, v.get!int128().toString());

	    command.commandText = "select cast('-184467440737095516190874' as int128) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int128() == int128("-184467440737095516190874"), v.get!int128().toString());

	    command.commandText = "select cast('184467440737095516190874' as int128) from rdb$database";
        v = command.executeScalar();
        assert(v.get!int128() == int128("184467440737095516190874"), v.get!int128().toString());
    }

    // decfloat(16)
    if (dbVersion >= "4.0")
    {
        command.commandText = "select cast(null as decfloat(16)) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == 0, v.get!Decimal64().toString());

	    command.commandText = "select cast(-1.0 as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == -1.0, v.get!Decimal64().toString());

	    command.commandText = "select cast(1.0 as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == 1.0, v.get!Decimal64().toString());

	    command.commandText = "select cast('-100000000000000000000000000000000000' as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == Decimal64("-100000000000000000000000000000000000"), v.get!Decimal64().toString());

	    command.commandText = "select cast('100000000000000000000000000000000000' as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == Decimal64("100000000000000000000000000000000000"), v.get!Decimal64().toString());

	    command.commandText = "select cast('123.000000001E-1' as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == Decimal64("123.000000001E-1"), v.get!Decimal64().toString());

	    command.commandText = "select cast('-123.000000001E-1' as decfloat(16)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal64() == Decimal64("-123.000000001E-1"), v.get!Decimal64().toString());
    }

    // decfloat(34)
    if (dbVersion >= "4.0")
    {
        command.commandText = "select cast(null as decfloat(34)) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == 0, v.get!Decimal64().toString());

	    command.commandText = "select cast(-1.0 as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == -1.0, v.get!Decimal64().toString());

	    command.commandText = "select cast(1.0 as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == 1.0, v.get!Decimal64().toString());

	    command.commandText = "select cast('-100000000000000000000000000000000000' as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("-100000000000000000000000000000000000"), v.get!Decimal64().toString());

	    command.commandText = "select cast('100000000000000000000000000000000000' as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("100000000000000000000000000000000000"), v.get!Decimal64().toString());

	    command.commandText = "select cast('123.000000001E-1' as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("123.000000001E-1"), v.get!Decimal64().toString());

	    command.commandText = "select cast('-123.000000001E-1' as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("-123.000000001E-1"), v.get!Decimal64().toString());
    }

    // decfloat
    if (dbVersion >= "4.0")
    {
        command.commandText = "select cast(null as decfloat) from rdb$database";
        auto v = command.executeScalar();
        assert(v.isNull());

	    command.commandText = "select cast(0 as decfloat) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == 0, v.get!Decimal128().toString());

	    command.commandText = "select cast(-1.0 as decfloat) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == -1.0, v.get!Decimal128().toString());

	    command.commandText = "select cast(1.0 as decfloat(34)) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == 1.0, v.get!Decimal128().toString());

	    command.commandText = "select cast('-100000000000000000000000000000000000' as decfloat) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("-100000000000000000000000000000000000"), v.get!Decimal128().toString());

	    command.commandText = "select cast('100000000000000000000000000000000000' as decfloat) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("100000000000000000000000000000000000"), v.get!Decimal128().toString());

	    command.commandText = "select cast('123.000000001E-1' as decfloat) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("123.000000001E-1"), v.get!Decimal128().toString());

	    command.commandText = "select cast('-123.000000001E-1' as decfloat) from rdb$database";
        v = command.executeScalar();
        assert(v.get!Decimal128() == Decimal128("-123.000000001E-1"), v.get!Decimal128().toString());
    }

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML
{
    import std.math;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML - Simple select");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    int count;
    assert(reader.hasRows());
    while (reader.read())
    {
        count++;
        traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.checking - count: ", count);

        assert(reader.getValue(0) == 1);
        assert(reader.getValue("INT_FIELD") == 1);

        assert(reader.getValue(1) == 2);
        assert(reader.getValue("SMALLINT_FIELD") == 2);

        assert(isClose(reader.getValue(2).get!float(), 3.10f));
        assert(isClose(reader.getValue("FLOAT_FIELD").get!float(), 3.10f));

        assert(isClose(reader.getValue(3).get!double(), 4.20));
        assert(isClose(reader.getValue("DOUBLE_FIELD").get!double(), 4.20));

        assert(reader.getValue(4).get!Decimal64() == Decimal64.money(5.4, 2));
        assert(reader.getValue("NUMERIC_FIELD").get!Decimal64() == Decimal64.money(5.4, 2));

        assert(reader.getValue(5).get!Decimal64() == Decimal64.money(6.5, 2));
        assert(reader.getValue("DECIMAL_FIELD").get!Decimal64() == Decimal64.money(6.5, 2));

        assert(reader.getValue(6) == Date(2020, 5, 20));
        assert(reader.getValue("DATE_FIELD") == DbDate(2020, 5, 20));

        assert(reader.getValue(7) == DbTime(1, 1, 1, 0));
        assert(reader.getValue("TIME_FIELD") == DbTime(1, 1, 1, 0));

        assert(reader.getValue(8) == DbDateTime(2020, 5, 20, 7, 31, 0, 0), reader.getValue(8).toString());
        assert(reader.getValue("TIMESTAMP_FIELD") == DbDateTime(2020, 5, 20, 7, 31, 0, 0));

        assert(reader.getValue(9) == "ABC       ");
        assert(reader.getValue("CHAR_FIELD") == "ABC       ");

        assert(reader.getValue(10) == "XYZ");
        assert(reader.getValue("VARCHAR_FIELD") == "XYZ");

        assert(reader.isNull(11));
        assert(reader.isNull("BLOB_FIELD"));

        assert(reader.getValue(12) == "TEXT");
        assert(reader.getValue("TEXT_FIELD") == "TEXT");

        assert(reader.getValue(13) == 4_294_967_296);
        assert(reader.getValue("BIGINT_FIELD") == 4_294_967_296);
    }
    assert(count == 1);

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.Parameter
{
    import std.math;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML - Parameter select");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = parameterSelectCommandText();
    command.parameters.add("INT_FIELD", DbType.int32).value = 1;
    command.parameters.add("DOUBLE_FIELD", DbType.float64).value = 4.20;
    command.parameters.add("DECIMAL_FIELD", DbType.decimal64).value = Decimal64(6.5);
    command.parameters.add("DATE_FIELD", DbType.date).value = DbDate(2020, 5, 20);
    command.parameters.add("TIME_FIELD", DbType.time).value = DbTime(1, 1, 1, 0);
    command.parameters.add("CHAR_FIELD", DbType.fixedString).value = "ABC       ";
    command.parameters.add("VARCHAR_FIELD", DbType.string).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    int count;
    assert(reader.hasRows());
    while (reader.read())
    {
        count++;
        traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.checking - count: ", count);

        assert(reader.getValue(0) == 1);
        assert(reader.getValue("INT_FIELD") == 1);

        assert(reader.getValue(1) == 2);
        assert(reader.getValue("SMALLINT_FIELD") == 2);

        assert(isClose(reader.getValue(2).get!float(), 3.10f));
        assert(isClose(reader.getValue("FLOAT_FIELD").get!float(), 3.10f));

        assert(isClose(reader.getValue(3).get!double(), 4.20));
        assert(isClose(reader.getValue("DOUBLE_FIELD").get!double(), 4.20));

        assert(reader.getValue(4).get!Decimal64() == Decimal64.money(5.4, 2));
        assert(reader.getValue("NUMERIC_FIELD").get!Decimal64() == Decimal64.money(5.4, 2));

        assert(reader.getValue(5).get!Decimal64() == Decimal64.money(6.5, 2));
        assert(reader.getValue("DECIMAL_FIELD").get!Decimal64() == Decimal64.money(6.5, 2));

        assert(reader.getValue(6) == Date(2020, 5, 20));
        assert(reader.getValue("DATE_FIELD") == DbDate(2020, 5, 20));

        assert(reader.getValue(7) == DbTime(1, 1, 1, 0));
        assert(reader.getValue("TIME_FIELD") == DbTime(1, 1, 1, 0));

        assert(reader.getValue(8) == DbDateTime(2020, 5, 20, 7, 31, 0, 0));
        assert(reader.getValue("TIMESTAMP_FIELD") == DbDateTime(2020, 5, 20, 7, 31, 0, 0));

        assert(reader.getValue(9) == "ABC       ");
        assert(reader.getValue("CHAR_FIELD") == "ABC       ");

        assert(reader.getValue(10) == "XYZ");
        assert(reader.getValue("VARCHAR_FIELD") == "XYZ");

        assert(reader.isNull(11));
        assert(reader.isNull("BLOB_FIELD"));

        assert(reader.getValue(12) == "TEXT");
        assert(reader.getValue("TEXT_FIELD") == "TEXT");

        assert(reader.getValue(13) == 4_294_967_296);
        assert(reader.getValue("BIGINT_FIELD") == 4_294_967_296);
    }
    assert(count == 1);

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.encrypt.compress
{
    import std.math;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML - Simple select with encrypt=enabled, compress=zip");

    bool failed = true;
    auto connection = createTestConnection(DbEncryptedConnection.enabled, DbCompressConnection.zip);
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    int count;
    assert(reader.hasRows());
    while (reader.read())
    {
        count++;
        traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.checking - count: ", count);

        assert(reader.getValue(0) == 1);
        assert(reader.getValue("INT_FIELD") == 1);

        assert(reader.getValue(1) == 2);
        assert(reader.getValue("SMALLINT_FIELD") == 2);

        assert(isClose(reader.getValue(2).get!float(), 3.10f));
        assert(isClose(reader.getValue("FLOAT_FIELD").get!float(), 3.10f));

        assert(isClose(reader.getValue(3).get!double(), 4.20));
        assert(isClose(reader.getValue("DOUBLE_FIELD").get!double(), 4.20));

        assert(reader.getValue(4).get!Decimal64() == Decimal64.money(5.4, 2));
        assert(reader.getValue("NUMERIC_FIELD").get!Decimal64() == Decimal64.money(5.4, 2));

        assert(reader.getValue(5).get!Decimal64() == Decimal64.money(6.5, 2));
        assert(reader.getValue("DECIMAL_FIELD").get!Decimal64() == Decimal64.money(6.5, 2));

        assert(reader.getValue(6) == DbDate(2020, 5, 20));
        assert(reader.getValue("DATE_FIELD") == DbDate(2020, 05, 20));

        assert(reader.getValue(7) == DbTime(1, 1, 1, 0));
        assert(reader.getValue("TIME_FIELD") == DbTime(1, 1, 1, 0));

        assert(reader.getValue(8) == DbDateTime(2020, 5, 20, 7, 31, 0, 0));
        assert(reader.getValue("TIMESTAMP_FIELD") == DbDateTime(2020, 5, 20, 7, 31, 0, 0));

        assert(reader.getValue(9) == "ABC       ");
        assert(reader.getValue("CHAR_FIELD") == "ABC       ");

        assert(reader.getValue(10) == "XYZ");
        assert(reader.getValue("VARCHAR_FIELD") == "XYZ");

        assert(reader.isNull(11));
        assert(reader.isNull("BLOB_FIELD"));

        assert(reader.getValue(12) == "TEXT");
        assert(reader.getValue("TEXT_FIELD") == "TEXT");

        assert(reader.getValue(13) == 4_294_967_296);
        assert(reader.getValue("BIGINT_FIELD") == 4_294_967_296);
    }
    assert(count == 1);

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.FbArrayManager
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML - FbArrayManager");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    FbIscArrayDescriptor descriptor = connection.arrayManager.getDescriptor("TEST_SELECT", "INTEGER_ARRAY");
    assert(descriptor.blrType == 8);
    assert(descriptor.fieldInfo.numericScale == 0);
    assert(descriptor.fieldInfo.size == 4);
    assert(descriptor.fieldInfo.subType == 0);
    assert(descriptor.bounds.length == 1);
    assert(descriptor.bounds[0].lower == 1);
    assert(descriptor.bounds[0].upper == 10);
    assert(descriptor.calculateSliceLength() == 40);

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.Array
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML - Array");

    static int[] arrayValue() nothrow pure @safe
    {
        return [1,2,3,4,5,6,7,8,9,10];
    }

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    void setArrayValue()
    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandText = "UPDATE TEST_SELECT" ~
            " SET INTEGER_ARRAY = @INTEGER_ARRAY" ~
            " WHERE INT_FIELD = 1";
        command.parameters.add("INTEGER_ARRAY", dbArrayOf(DbType.int32)).value = arrayValue();
        auto r = command.executeNonQuery();
        assert(r == 1);
    }

    void readArrayValue()
    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandText = "SELECT INTEGER_ARRAY" ~
            " FROM TEST_SELECT" ~
            " WHERE INT_FIELD = 1";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;
            traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.checking - count: ", count);

            assert(reader.getValue(0) == arrayValue());
            assert(reader.getValue("INTEGER_ARRAY") == arrayValue());
        }
        assert(count == 1);
    }

    setArrayValue();
    readArrayValue();

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.Array.Less
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML - Array.Less");

    static int[] selectArrayValue() nothrow pure @safe
    {
        return [1,2,3,4,5,0,0,0,0,0];
    }

    static int[] updateArrayValue() nothrow pure @safe
    {
        return [1,2,3,4,5];
    }

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    void setArrayValue()
    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandText = "UPDATE TEST_SELECT" ~
            " SET INTEGER_ARRAY = @INTEGER_ARRAY" ~
            " WHERE INT_FIELD = 1";
        command.parameters.add("INTEGER_ARRAY", dbArrayOf(DbType.int32)).value = updateArrayValue();
        auto r = command.executeNonQuery();
        assert(r == 1);
    }

    void readArrayValue()
    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandText = "SELECT INTEGER_ARRAY" ~
            " FROM TEST_SELECT" ~
            " WHERE INT_FIELD = 1";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;
            traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.checking - count: ", count);

            assert(reader.getValue(0) == selectArrayValue());
            assert(reader.getValue("INTEGER_ARRAY") == selectArrayValue());
        }
        assert(count == 1);
    }

    setArrayValue();
    readArrayValue();

    failed = false;
}

version (UnitTestFBDatabase)
unittest // FbCommand.DML.StoredProcedure
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.StoredProcedure");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandStoredProcedure = "MULTIPLE_BY2";
        command.parameters.add("X", DbType.int32).value = 2;
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
    }

    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandText = "select * from MULTIPLE_BY2(2)";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;

            assert(reader.getValue(0) == 4);
            assert(reader.getValue("Y") == 4);
        }
        assert(count == 1);
    }

    failed = false;
}

version (UnitTestFBDatabase)
unittest // DbRAIITransaction
{
    import std.exception : assertThrown;
    import pham.utl.test;
    import pham.db.exception : DbException;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.DbRAIITransaction");

    bool commit = false;
    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    void testDbRAIITransaction()
    {
        auto transactionHolder = DbRAIITransaction(connection);

        auto command = connection.createCommand();
        scope (exit)
            command.dispose();
        command.transaction = transactionHolder.transaction;

        command.commandText = "SELECT 1 FROM RDB$DATABASE";
        auto v = command.executeScalar();
        assert(v.get!int32() == 1);

        command.commandDDL = "DROP TABLE unknown_drop_table";
        command.executeNonQuery();

        transactionHolder.commit();
        commit = true;
    }

    assertThrown!DbException(testDbRAIITransaction());
    assert(commit == false);
}

version (UnitTestFBDatabase)
unittest // FbCommandBatch
{
    import pham.dtm.date;
    import pham.utl.object : VersionString;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommandBatch");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();
    }
    connection.open();

    const minSupportVersion = VersionString("4.0");
    const canTest = VersionString(connection.serverVersion()) >= minSupportVersion;
    if (!canTest)
        return;

    {
        auto command = connection.createCommandDDL("create table batch (i int not null primary key, t timestamp)");
        command.executeNonQuery();
        command.dispose();
    }

    scope (exit)
    {
        auto command = connection.createCommandDDL("drop table batch");
        scope (exit)
            command.dispose();
        command.executeNonQuery();
    }

	auto iv = [1, 2, 3, 4];
	auto tv = [DateTime(2022, 01, 17, 1, 0, 0), DateTime(2022, 01, 17, 2, 0, 0),
        DateTime(2022, 01, 17, 2, 1, 0), DateTime(2022, 01, 17, 2, 2, 0)];
    assert(iv.length == tv.length);

    // OK
	{
        assert(iv.length == 4);
		auto command = connection.createCommandBatch("insert into batch(i, t) values(@i, @t)");

        // Test first block
        foreach (i; 0..2)
        {
            auto parameters = command.addParameters();
            parameters.add("i", DbValue(iv[i]));
            parameters.add("t", DbValue(tv[i]));
        }
        command.executeNonQuery();

        // Test second block
        command.clearParameters();
        foreach (i; 2..4)
        {
            auto parameters = command.addParameters();
            parameters.add("i", DbValue(iv[i]));
            parameters.add("t", DbValue(tv[i]));
        }
        command.executeNonQuery();
	}

    // OK validated
	{
        assert(iv.length == 4);
		auto command = connection.createCommandText("select i, t from batch order by i");
        scope (exit)
            command.dispose();

        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

		auto i = 0;
		while (reader.read())
		{
            assert(i < iv.length);
			assert(reader.getValue(0) == iv[i]);
			assert(reader.getValue(1) == DbDateTime.toDbDateTime(tv[i]));
			i++;
		}
	}

    // Mixed OK & Failure
    //version (none) // TODO Firebird bug -> not able to perform different sql on same connection
    {
		auto command = connection.createCommandBatch("insert into batch(i) values(@i)");

        command.addParameters().add("i", DbValue(6)); // OK
        command.addParameters().add("i", DbValue(1)); // Failure - duplicate
        command.addParameters().add("i", DbValue(7)); // OK
        command.addParameters().add("i", DbValue(2)); // Failure - duplicate
        auto result = command.executeNonQuery();
		assert(result.length == 4);
		assert(result[0].isOK);
		assert(result[0].exception is null);
		assert(result[0].recordsAffected == 1);

		assert(result[1].isError);
		assert(result[1].exception !is null);

		assert(result[2].isOK);
		assert(result[2].exception is null);
		assert(result[2].recordsAffected == 1);

		assert(result[3].isError);
		assert(result[3].exception !is null);
    }
}

unittest // DbDatabaseList.createConnection
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.DbDatabaseList.createConnection");

    auto connection = DbDatabaseList.createConnection("firebird:server=myServerAddress;database=myDataBase;" ~
        "user=myUsername;password=myPassword;role=myRole;pooling=true;connectionTimeout=100;encrypt=enabled;" ~
        "fetchRecordCount=50;integratedSecurity=legacy;cachePage=2000;cryptKey=QUIx;");
    scope (exit)
        connection.dispose();
    auto connectionString = cast(FbConnectionStringBuilder)connection.connectionStringBuilder;

    assert(connection.scheme == DbScheme.fb);
    assert(connectionString.serverName == "myServerAddress");
    assert(connectionString.databaseName == "myDataBase");
    assert(connectionString.userName == "myUsername");
    assert(connectionString.userPassword == "myPassword");
    assert(connectionString.roleName == "myRole");
    assert(connectionString.pooling == true);
    assert(connectionString.connectionTimeout == dur!"seconds"(100));
    assert(connectionString.encrypt == DbEncryptedConnection.enabled);
    assert(connectionString.fetchRecordCount == 50);
    assert(connectionString.integratedSecurity == DbIntegratedSecurityConnection.legacy);
    assert(connectionString.cachePages == 2000);
    assert(connectionString.cryptKey == "AB1".representation());
}

unittest // DbDatabaseList.createConnectionByURL
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.DbDatabaseList.createConnectionByURL");

    auto connection = DbDatabaseList.createConnectionByURL("firebird://myUsername:myPassword@myServerAddress/myDataBase?" ~
        "role=myRole&pooling=true&connectionTimeout=100&encrypt=enabled&" ~
        "fetchRecordCount=50&integratedSecurity=legacy&cachePage=2000&cryptKey=QUIx");
    scope (exit)
        connection.dispose();
    auto connectionString = cast(FbConnectionStringBuilder)connection.connectionStringBuilder;

    assert(connection.scheme == DbScheme.fb);
    assert(connectionString.serverName == "myServerAddress");
    assert(connectionString.databaseName == "myDataBase");
    assert(connectionString.userName == "myUsername");
    assert(connectionString.userPassword == "myPassword");
    assert(connectionString.roleName == "myRole");
    assert(connectionString.pooling == true);
    assert(connectionString.connectionTimeout == dur!"seconds"(100));
    assert(connectionString.encrypt == DbEncryptedConnection.enabled);
    assert(connectionString.fetchRecordCount == 50);
    assert(connectionString.integratedSecurity == DbIntegratedSecurityConnection.legacy);
    assert(connectionString.cachePages == 2000);
    assert(connectionString.cryptKey == "AB1".representation());
}

version (UnitTestPerfFBDatabase)
{
    import pham.utl.test : PerfTestResult;

    PerfTestResult unitTestPerfFBDatabase()
    {
        import core.time;

        static struct Data
        {
            long Foo1;
            long Foo2;
            string Foo3;
            string Foo4;
            DbDateTime Foo5;
            DbDateTime Foo6;
            DbDateTime Foo7;
            string Foo8;
            string Foo9;
            string Foo10;
            short Foo11;
            short Foo12;
            short Foo13;
            Decimal64 Foo14;
            Decimal64 Foo15;
            short Foo16;
            Decimal64 Foo17;
            Decimal64 Foo18;
            long Foo19;
            long Foo20;
            long Foo21;
            long Foo22;
            string Foo23;
            string Foo24;
            string Foo25;
            string Foo26;
            long Foo27;
            string Foo28;
            long Foo29;
            string Foo30;
            long Foo31;
            Decimal64 Foo32;
            Decimal64 Foo33;

            this(ref DbReader reader)
            {
                readData(reader);
            }

            void readData(ref DbReader reader)
            {
                version (all)
                {
                    Foo1 = reader.getValue!int64(0); //foo1 BIGINT NOT NULL,
                    Foo2 = reader.getValue!int64(1); //foo2 BIGINT NOT NULL,
                    Foo3 = reader.getValue!string(2); //foo3 VARCHAR(255),
                    Foo4 = reader.getValue!string(3); //foo4 VARCHAR(255),
                    Foo5 = reader.getValue!DbDateTime(4); //foo5 TIMESTAMP,
                    Foo6 = reader.getValue!DbDateTime(5); //foo6 TIMESTAMP NOT NULL,
                    Foo7 = reader.getValue!DbDateTime(6); //foo7 TIMESTAMP,
                    Foo8 = reader.getValue!string(7); //foo8 VARCHAR(255),
                    Foo9 = reader.getValue!string(8); //foo9 VARCHAR(255),
                    Foo10 = reader.getValue!string(9); //foo10 VARCHAR(255),
                    Foo11 = reader.getValue!int16(10); //foo11 SMALLINT NOT NULL,
                    Foo12 = reader.getValue!int16(11); //foo12 SMALLINT NOT NULL,
                    Foo13 = reader.getValue!int16(12); //foo13 SMALLINT NOT NULL,
                    Foo14 = reader.getValue!Decimal64(13); //foo14 DECIMAL(18, 2) NOT NULL,
                    Foo15 = reader.getValue!Decimal64(14); //foo15 DECIMAL(18, 2) NOT NULL,
                    Foo16 = reader.getValue!int16(15); //foo16 SMALLINT NOT NULL,
                    Foo17 = reader.getValue!Decimal64(16); //foo17 DECIMAL(18, 2) NOT NULL,
                    Foo18 = reader.getValue!Decimal64(17); //foo18 DECIMAL(18, 2) NOT NULL,
                    Foo19 = reader.getValue!int64(18); //foo19 BIGINT NOT NULL,
                    Foo20 = reader.getValue!int64(19); //foo20 BIGINT NOT NULL,
                    Foo21 = reader.getValue!int64(20); //foo21 BIGINT NOT NULL,
                    Foo22 = reader.getValue!int64(21); //foo22 BIGINT NOT NULL,
                    Foo23 = reader.getValue!string(22); //foo23 VARCHAR(255),
                    Foo24 = reader.getValue!string(23); //foo24 VARCHAR(255),
                    Foo25 = reader.getValue!string(24); //foo25 VARCHAR(511),
                    Foo26 = reader.getValue!string(25); //foo26 VARCHAR(256),
                    Foo27 = reader.getValue!int64(26); //foo27 BIGINT NOT NULL,
                    Foo28 = reader.getValue!string(27); //foo28 VARCHAR(255),
                    Foo29 = reader.getValue!int64(28); //foo29 BIGINT NOT NULL,
                    Foo30 = reader.getValue!string(29); //foo30 VARCHAR(255),
                    Foo31 = reader.getValue!int64(30); //foo31 BIGINT NOT NULL,
                    Foo32 = reader.getValue!Decimal64(31); //foo32 DECIMAL(18, 2) NOT NULL,
                    Foo33 = reader.getValue!Decimal64(32); //foo33 DECIMAL(18, 2) NOT NULL
                }
                else
                {
                    Foo5 = reader.getValue!DbDateTime(0);
                }
            }
        }

        bool failed = true;
        auto connection = createTestConnection();
        scope (exit)
        {
            version (unittest)
            if (failed)
                traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

            connection.dispose();
        }
        connection.open();

        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        enum maxRecordCount = 100_000;
        command.commandText = "select first(100000) * from foo";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        version (UnitTestFBCollectData) auto datas = new Data[](maxRecordCount);
        else Data data;
        assert(reader.hasRows());

        auto result = PerfTestResult.create();
        while (result.count < maxRecordCount && reader.read())
        {
            version (UnitTestFBCollectData) datas[result.count++] = Data(reader);
            else { data.readData(reader); result.count++; }
        }
        result.end();
        assert(result.count > 0);
        failed = false;
        return result;
    }
}

version (UnitTestPerfFBDatabase)
unittest // FbCommand.DML.Performance - https://github.com/FirebirdSQL/NETProvider/issues/953
{
    import std.format : format;
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.FbCommand.DML.Performance - https://github.com/FirebirdSQL/NETProvider/issues/953");

    const perfResult = unitTestPerfFBDatabase();
    dgWriteln("FB-Count: ", format!"%,3?d"('_', perfResult.count), ", Elapsed in msecs: ", format!"%,3?d"('_', perfResult.elapsedTimeMsecs()));
}

version (UnitTestFBDatabase)
unittest // FbConnection.createDatabase
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbdatabase.createDatabase");

    FbCreateDatabaseInfo ci;
    ci.fileName = testCreateDatabaseFileName();
    ci.defaultCharacterSet = "iso8859_1";
    ci.overwrite = true;
    ci.pageSize = 16384;

    void deleteTestCreateDatabaseFile()
    {
        import core.thread : Thread;
        import core.time : dur;
        import std.file : exists, remove;

        if (exists(ci.fileName))
        {
            Thread.sleep(dur!"msecs"(5_000)); // Firebird may still be holding the file
            remove(ci.fileName);
        }
    }

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest!("pham.db.fbdatabase")("failed - exiting and closing connection");

        connection.dispose();

        deleteTestCreateDatabaseFile();
    }

    { // Without active connection
        connection.createDatabase(ci);
        deleteTestCreateDatabaseFile();
    }

    { // With active connection
        connection.open();
        connection.createDatabase(ci);
        connection.close();
        deleteTestCreateDatabaseFile();
    }
}
