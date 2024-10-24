/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2020 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_pgdatabase;

import std.conv : text, to;
import std.system : Endian;

debug(debug_pham_db_db_pgdatabase) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.std.log.log_logger : Logger, LogLevel, LogTimming;
import pham.utl.utl_array : Appender;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_object : VersionString;
import pham.db.db_buffer;
import pham.db.db_convert;
import pham.db.db_database;
import pham.db.db_message;
import pham.db.db_object;
import pham.db.db_skdatabase;
import pham.db.db_type;
import pham.db.db_util;
import pham.db.db_value;
import pham.db.db_pgbuffer;
import pham.db.db_pgexception;
import pham.db.db_pgoid;
import pham.db.db_pgprotocol;
import pham.db.db_pgtype;

// Require in active transaction block
struct PgLargeBlob
{
public:
    enum maxBlockLength = 32_000;

    enum OpenMode : int32
    {
        write = 0x0002_0000,
        read  = 0x0004_0000,
        readWrite = read | write
    }

    enum SeekOrigin : int32
    {
        begin = 0,
        current = 1,
        end = 2
    }

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(PgConnection connection) nothrow pure @safe
    in
    {
        assert(connection !is null);
    }
    do
    {
        this._connection = connection;
    }

    this(PgConnection connection, PgOId id) nothrow pure @safe
    {
        this._connection = connection;
        this._id = id;
    }

    ~this() @safe
    {
        dispose(DisposingReason.destructor);
    }

    bool opCast(C: bool)() const nothrow @safe
    {
        return pgId.isValid();
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    PgLargeBlob opCast(T)() const nothrow @safe
    if (is(Unqual!T == PgLargeBlob))
    {
        return this;
    }

    pragma(inline, true)
    final Logger canErrorLog() nothrow @safe
    {
        return _connection !is null ? _connection.canErrorLog() : null;
    }

    void close() @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen == true);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        doClose(DisposingReason.other);
    }

    void create(PgOId preferredId = 0) @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen == false);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        _id = pgConnection.largeBlobManager.createPreferred(preferredId);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        doClose(disposingReason);
        if (isDisposing(disposingReason))
            _connection = null;
    }

    string forLogInfo() nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    int64 length() @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (_length < 0)
        {
            _length = seek(0, SeekOrigin.end);
            seek(offset, SeekOrigin.begin); // Rewind
        }
        return _length;
    }

    void open(OpenMode mode = OpenMode.readWrite) @safe
    in
    {
        assert(pgConnection !is null);
        assert(!isOpen);
        assert(_id.isValid());
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        this._mode = mode;
        this._descriptorId = pgConnection.largeBlobManager.open(pgId, mode);
    }

    ubyte[] openRead() @safe
    in
    {
        assert(pgConnection !is null);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        open(OpenMode.read);
        scope (exit)
            close();

        const blobLength = cast(size_t)length;
        if (blobLength <= 0)
            return null;

        size_t readOffset = 0;
        ubyte[] result = new ubyte[](blobLength);
        while (readOffset < blobLength)
        {
            const leftLength = blobLength - readOffset;
            const readLength = leftLength > maxBlockLength ? maxBlockLength : leftLength;
            readOffset += read(result[readOffset..readOffset + readLength]);
        }
        return result;
    }

    void openWrite(scope const(ubyte)[] value) @safe
    in
    {
        assert(pgConnection !is null);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (!_id.isValid())
            create();
        open(OpenMode.write);
        scope (exit)
            close();

        write(value);
    }

    size_t read(ubyte[] data) @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        size_t result = 0;
        while (result < data.length)
        {
            const leftLength = data.length - result;
            const readLength = leftLength > maxBlockLength ? maxBlockLength : cast(int32)leftLength;
            auto readData = pgConnection.largeBlobManager.read(pgDescriptorId, readLength);
            if (readData.length == 0)
                break;
            data[result..readData.length] = readData[];
            _offset += readData.length;
            result += readData.length;
        }
        return result;
    }

    void remove() @safe
    in
    {
        assert(pgConnection !is null);
        assert(_id.isValid());
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (isOpen)
            close();
        scope (exit)
            reset();
        pgConnection.largeBlobManager.unlink(pgId);
    }

    size_t write(scope const(ubyte)[] data) @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        _length = -1; // Need to reset the length
        size_t result = 0;
        while (result < data.length)
        {
            const leftLength = data.length - result;
            auto writeLength = leftLength > maxBlockLength ? maxBlockLength : cast(int32)leftLength;
            writeLength = pgConnection.largeBlobManager.write(pgDescriptorId, data[result..result + writeLength]);
            if (writeLength == 0)
                break;
            _offset += writeLength;
            result += writeLength;
        }
        return result;
    }

    /* Properties */

    @property PgConnection pgConnection() nothrow pure @safe
    {
        return _connection;
    }

    @property PgDescriptorId pgDescriptorId() const nothrow @safe
    {
        return _descriptorId.get!PgDescriptorId();
    }

    @property PgOId pgId() const nothrow @safe
    {
        return _id.get!PgOId();
    }

    @property bool isOpen() const nothrow @safe
    {
        return _descriptorId.isValid();
    }

    @property final Logger logger() nothrow pure @safe
    {
        return _connection !is null ? _connection.logger : null;
    }

    @property OpenMode mode() const nothrow @safe
    {
        return _mode;
    }

    @property int64 offset() const nothrow @safe
    {
        return _offset;
    }

    @property ref typeof(this) offset(int64 newOffset) return @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen == true);
    }
    do
    {
        _offset = seek(newOffset, SeekOrigin.begin);
        return this;
    }

package(pham.db):
    void doClose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        scope (exit)
        {
            if (isDisposing(disposingReason))
                reset();
            else
                resetClose();
        }

        if (isDisposing(disposingReason) && !isOpen)
            return;

        try
        {
            if (isDisposing(disposingReason))
            {
                if (pgConnection !is null)
                    pgConnection.largeBlobManager.close(pgDescriptorId);
                return;
            }

            pgConnection.largeBlobManager.close(pgDescriptorId);
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.blob.doClose() - %s", forLogInfo(), e.msg, e);
        }
    }

    void reset() nothrow @safe
    {
        resetClose();
        _id.reset();
    }

    void resetClose() nothrow @safe
    {
        _descriptorId.reset();
        _length = -1;
        _offset = 0;
    }

    int64 seek(int64 offset, SeekOrigin origin) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(offset=", offset, ", origin=", origin, ")");

        return pgConnection.largeBlobManager.seek(pgDescriptorId, offset, origin);
    }

package(pham.db):
    PgConnection _connection;
    DbHandle _descriptorId;
    DbId _id;
    int64 _length = -1;
    int64 _offset;
    OpenMode _mode;
}

// https://www.postgresql.org/docs/9.2/lo-interfaces.html
struct PgLargeBlobManager
{
public:
    this(PgConnection connection) nothrow pure @safe
    in
    {
        assert(connection !is null);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        this._connection = connection;
    }

    ~this() @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        dispose(DisposingReason.destructor);
    }

    void close() nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        doClose(DisposingReason.other);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        doClose(disposingReason);
    }

    int32 close(PgDescriptorId descriptorId) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(descriptorId=", descriptorId, ")");

        if (!_close)
            _close = createFunction("lo_close", [Argument("descriptorId", PgOIdType.int4)]);
        _close.parameters.get("descriptorId").value = descriptorId;
        return _close.executeScalar().get!int32();
    }

    PgOId createNew() @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (!_createNew)
            _createNew = createFunction("lo_creat", [Argument("blobId", PgOIdType.int4)]);
        _createNew.parameters.get("blobId").value = -1;
        return _createNew.executeScalar().get!PgOId();
    }

    PgOId createPreferred(PgOId preferredId) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(preferredId=", preferredId, ")");

        if (!_createPreferred)
            _createPreferred = createFunction("lo_create", [Argument("blobId", PgOIdType.oid)]);
        _createPreferred.parameters.get("blobId").value = preferredId;
        return _createPreferred.executeScalar().get!PgOId();
    }

    PgDescriptorId open(PgOId blobId, int32 mode) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(blobId=", blobId, ", mode=", mode, ")");

        if (!_open)
            _open = createFunction("lo_open", [Argument("blobId", PgOIdType.oid), Argument("mode", PgOIdType.int4)]);
        _open.parameters.get("blobId").value = blobId;
        _open.parameters.get("mode").value = mode;
        return _open.executeScalar().get!PgDescriptorId();
    }

    ubyte[] read(PgDescriptorId descriptorId, int32 nBytes) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(descriptorId=", descriptorId, ", nBytes=", nBytes, ")");

        if (!_read)
            _read = createFunction("loread", [Argument("descriptorId", PgOIdType.int4), Argument("nBytes", PgOIdType.int4)]);
        _read.parameters.get("descriptorId").value = descriptorId;
        _read.parameters.get("nBytes").value = nBytes;
        auto result = _read.executeScalar();
        return !result.isNull ? result.get!(ubyte[])() : null;
    }

    int64 seek(PgDescriptorId descriptorId, int64 offset, int32 origin) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(descriptorId=", descriptorId, ", offset=", offset, ", origin=", origin, ")");

        if (!_seek)
            _seek = createFunction("lo_lseek64", [Argument("descriptorId", PgOIdType.int4), Argument("offset", PgOIdType.int8), Argument("origin", PgOIdType.int4)]);
        _seek.parameters.get("descriptorId").value = descriptorId;
        _seek.parameters.get("offset").value = offset;
        _seek.parameters.get("origin").value = origin;
        return _seek.executeScalar().get!int64();
    }

    int32 write(PgDescriptorId descriptorId, scope const(ubyte)[] bytes) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(descriptorId=", descriptorId, ")");

        if (!_write)
            _write = createFunction("lowrite", [Argument("descriptorId", PgOIdType.int4), Argument("bytes", PgOIdType.bytea)]);
        _write.parameters.get("descriptorId").value = descriptorId;
        _write.parameters.get("bytes").value = bytes.dup;
        return _write.executeScalar().get!int32();
    }

    int32 unlink(PgOId blobId) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(blobId=", blobId, ")");

        if (!_unlink)
            _unlink = createFunction("lo_unlink", [Argument("blobId", PgOIdType.oid)]);
        _unlink.parameters.get("blobId").value = blobId;
        return _unlink.executeScalar().get!int32();
    }

    /* Properties */

    @property final PgConnection pgConnection() nothrow pure @safe
    {
        return _connection;
    }

package(pham.db):
    void doClose(const(DisposingReason) disposingReason) nothrow @safe
    {
        disposeCommand(_close, disposingReason);
        disposeCommand(_createNew, disposingReason);
        disposeCommand(_createPreferred, disposingReason);
        disposeCommand(_open, disposingReason);
        disposeCommand(_read, disposingReason);
        disposeCommand(_seek, disposingReason);
        disposeCommand(_write, disposingReason);
        disposeCommand(_unlink, disposingReason);
        if (isDisposing(disposingReason))
            _connection = null;
    }

private:
    static struct Argument
    {
    nothrow @safe:

        string name;
        PgOId type;
    }

    PgCommand createFunction(string functionName, scope Argument[] arguments) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(functionName=", functionName, ")");

        auto commandText = Appender!string(500);
        commandText.put("SELECT * FROM ");
        commandText.put(functionName);
        commandText.put('(');
        foreach (i, ref argument; arguments)
        {
            if (i)
                commandText.put(',');
            commandText.put('@');
			commandText.put(argument.name);
        }
        commandText.put(')');

        auto result = pgConnection.createCommandText(commandText.data);
        PgOIdColumnInfo info;
        foreach (ref argument; arguments)
        {
            info.type = argument.type;
            result.parameters.add(argument.name, info.dbType(), 0, DbParameterDirection.input).baseTypeId = argument.type;
        }
        return cast(PgCommand)result.prepare();
    }

    PgCommand createStoredProcedure(string storedProcedureName, scope Argument[] arguments) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ")");

        auto result = pgConnection.createCommand(storedProcedureName);
        result.commandStoredProcedure = storedProcedureName;
        PgOIdColumnInfo info;
        foreach (ref argument; arguments)
        {
            info.type = argument.type;
            result.parameters.add(argument.name, info.dbType(), 0, DbParameterDirection.input).baseTypeId = argument.type;
        }
        return cast(PgCommand)result.prepare();
    }

    void disposeCommand(ref PgCommand command, const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (command !is null)
        {
            command.dispose(disposingReason);
            command = null;
        }
    }

package(pham.db):
    PgConnection _connection;
    PgCommand _close;
    PgCommand _createNew;
    PgCommand _createPreferred;
    PgCommand _open;
    PgCommand _read;
    PgCommand _seek;
    PgCommand _write;
    PgCommand _unlink;
}

class PgCancelCommandData: DbCancelCommandData
{
@safe:

public:
    this(PgConnection connection)
    {
        this.serverProcessId = connection.serverInfo[DbServerIdentifier.protocolProcessId].to!int32();
        this.serverSecretKey = connection.serverInfo[DbServerIdentifier.protocolSecretKey].to!int32();
    }

public:
    int32 serverProcessId;
    int32 serverSecretKey;
}

class PgColumn : DbColumn
{
public:
    this(PgCommand command, DbIdentitier name) nothrow pure @safe
    {
        super(command, name);
    }

    final override DbColumn createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createColumn(cast(PgCommand)command, name)
            : new PgColumn(cast(PgCommand)command, name);
    }

    final override DbColumnIdType isValueIdType() const nothrow @safe
    {
        return PgOIdColumnInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

    @property final PgCommand pgCommand() nothrow pure @safe
    {
        return cast(PgCommand)_command;
    }
}

class PgColumnList: DbColumnList
{
public:
    this(PgCommand command) nothrow pure @safe
    {
        super(command);
    }

    final override DbColumn create(DbCommand command, DbIdentitier name) nothrow @safe
    {
        return database !is null
            ? database.createColumn(cast(PgCommand)command, name)
            : new PgColumn(cast(PgCommand)command, name);
    }

    @property final PgCommand pgCommand() nothrow pure @safe
    {
        return cast(PgCommand)_command;
    }

protected:
    final override DbColumnList createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createColumnList(cast(PgCommand)command)
            : new PgColumnList(cast(PgCommand)command);
    }
}

class PgCommand : SkCommand
{
public:
    this(PgConnection connection, string name = null) nothrow @safe
    {
        super(connection, name);
    }

    this(PgConnection connection, PgTransaction transaction, string name = null) nothrow @safe
    {
        super(connection, transaction, name);
    }

	final override string getExecutionPlan(uint vendorMode = 0) @safe
	{
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(vendorMode=", vendorMode, ")");

        if (auto log = canTraceLog())
            log.infof("%s.command.getExecutionPlan(vendorMode=%d)%s%s", forLogInfo(), vendorMode, newline, commandText);

        auto planCommandText = vendorMode == 0
            ? "EXPLAIN (ANALYZE, BUFFERS) " ~ buildExecuteCommandText(BuildCommandTextState.executingPlan)
            : "EXPLAIN " ~ buildExecuteCommandText(BuildCommandTextState.executingPlan);
        auto planCommand = pgConnection.createNonTransactionCommand(true);
        scope (exit)
            planCommand.dispose();

        planCommand.commandText = planCommandText;
        auto planReader = planCommand.executeReader();
        scope (exit)
            planReader.dispose();

        auto result = Appender!string(1_000);
        while (planReader.read())
        {
            if (result.length)
                result.put('\n');
            result.put(planReader.getValue!string(0));
        }
        return result.data;
    }

    final PgParameter[] pgInputParameters(const(bool) inputOnly = false) nothrow @safe
    {
        return inputParameters!PgParameter(inputOnly);
    }

    final override Variant readArray(DbNameColumn arrayColumn, DbValue arrayValueId) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        return Variant.varNull();
    }

    final override ubyte[] readBlob(DbNameColumn blobColumn, DbValue blobValueId) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (blobValueId.isNull)
            return null;

        auto blob = PgLargeBlob(pgConnection, blobValueId.get!PgOId());
        return blob.openRead();
    }

    final override DbValue writeBlob(DbNameColumn blobColumn, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        auto blob = optionalBlobValueId.isNull
                    ? PgLargeBlob(pgConnection)
                    : PgLargeBlob(pgConnection, optionalBlobValueId.get!PgOId());
        blob.openWrite(blobValue);
        return DbValue(blob.pgId, blobColumn.type);
    }

    @property final PgConnection pgConnection() nothrow pure @safe
    {
        return cast(PgConnection)connection;
    }

protected:
    override string buildStoredProcedureSql(string storedProcedureName, const(BuildCommandTextState) state) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ", state=", state, ")");

        if (storedProcedureName.length == 0)
            return null;

        if (!hasParameters && parametersCheck)
        {
            auto info = pgConnection.getStoredProcedureInfo(storedProcedureName);
            if (info !is null)
            {
                auto params = parameters; // Use local var to avoid function call
                params.reserve(info.argumentTypes.length);
                foreach (src; info.argumentTypes)
                    params.addClone(src);
            }
        }

        auto result = Appender!string(500);
        result.put("CALL ");
        result.put(storedProcedureName);
        result.put('(');
        if (hasParameters)
        {
            auto params = parameters();
            foreach (i; 0..params.length)
            {
                auto param = params[i];
                if (i)
                    result.put(',');
                // Note
                // <= v12 do not support output direction
                if (param.direction == DbParameterDirection.output)
                    result.put("NULL");
                else
                    result.put(database.parameterPlaceholder(param.name, cast(uint32)(i + 1)));
            }
        }
        result.put(')');

        debug(debug_pham_db_db_pgdatabase) debug writeln("\t", "storedProcedureName=", storedProcedureName, ", result=", result.data);

        return result.data;
    }

    final void deallocateHandle() @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
            _handle.reset();

        try
        {
            auto protocol = pgConnection.protocol;
            protocol.deallocateCommandWrite(this);
            protocol.deallocateCommandRead();
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.connection.deallocateHandle() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
        }
    }

    final override void doExecuteCommand(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(type=", type, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doExecuteCommand()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        prepareExecuting(type);

        auto protocol = pgConnection.protocol;
        protocol.bindCommandParameterWrite(this);
        processBindResponse(protocol.bindCommandParameterRead(this));
        const fcs = doExecuteCommandFetch(type, false);

        if (isStoredProcedure)
        {
            if (fcs == DbFetchResultStatus.ready && _fetchedRows.empty)
                doFetch(true);

            if (_fetchedRows && hasParameters)
            {
                auto row = _fetchedRows.front;
                mergeOutputParams(row);
            }
        }
    }

    final override bool doExecuteCommandNeedPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        return true; // Need to do directExecute in order to return false
    }

    final DbFetchResultStatus doExecuteCommandFetch(const(DbCommandExecuteType) type, const(bool) fetchAgain) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(type=", type, ", fetchAgain=", fetchAgain, ")");

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doExecuteCommandFetch()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = pgConnection.protocol;
        protocol.executeCommandWrite(this, type);
        PgReader reader;  // Since it is package message, need reader to continue reading row values
        auto response = protocol.executeCommandRead(this, type, reader);
        if (!fetchAgain)
        {
            _recordsAffected = response.recordsAffected;
            debug(debug_pham_db_db_pgdatabase) debug writeln("\t", "_recordsAffected=", _recordsAffected);
        }

        const result = response.fetchStatus();
        final switch (result)
        {
            // Defer subsequence row for fetch call
            case DbFetchResultStatus.hasData:
                auto row = readRow(reader, type == DbCommandExecuteType.scalar);
                _fetchedRows.enqueue(row);
                break;

            case DbFetchResultStatus.completed:
                debug(debug_pham_db_db_pgdatabase) debug writeln("\t", "allRowsFetched=true");
                allRowsFetched = true;
                break;

            // Next for fetch call
            case DbFetchResultStatus.ready:
                break;
        }

        return result;
    }

    final override void doFetch(const(bool) isScalar) @safe
    in
    {
        assert(!allRowsFetched);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ", fetchRecordCount=", fetchRecordCount, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doFetch()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = pgConnection.protocol;
        uint continueFetchingCount = isScalar ? 1 : fetchRecordCount;
        bool continueFetching = true, isSuspended = false;
        while (continueFetching && continueFetchingCount)
        {
            PgReader reader; // Since it is package message, need reader to continue reading row values
            auto response = protocol.fetchCommandRead(this, isSuspended, reader);
            final switch (response.fetchStatus())
            {
                case DbFetchResultStatus.hasData:
                    auto row = readRow(reader, isScalar);
                    _fetchedRows.enqueue(row);
                    continueFetchingCount--;
                    break;

                case DbFetchResultStatus.completed:
                    debug(debug_pham_db_db_pgdatabase) debug writeln("\t", "allRowsFetched=true");
                    allRowsFetched = true;
                    continueFetching = false;

                    version(none) // Only valid if there is portal name
                    if (!isScalar && response.needFetchAgain(isSuspended))
                    {
                        final switch (doExecuteCommandFetch(DbCommandExecuteType.reader, true))
                        {
                            case DbFetchResultStatus.hasData:
                                allRowsFetched = false;
                                continueFetching = true;
                                continueFetchingCount--;
                                break;

                            case DbFetchResultStatus.completed:
                                break;

                            case DbFetchResultStatus.ready:
                                allRowsFetched = false;
                                break;
                        }
                    }

                    isSuspended = false;
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
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");
        version(profile) debug auto p = PerfFunction.create();

        auto sql = executeCommandText(BuildCommandTextState.prepare); // Make sure statement is constructed before doing other tasks

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doPrepare()", newline, sql), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = pgConnection.protocol;
        protocol.prepareCommandWrite(this, sql);
        protocol.prepareCommandRead(this);
        _handle.setDummy();
    }

    final override void doUnprepare(const(bool) isPreparedError) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (_handle)
            deallocateHandle();
    }

    static void fillNamedColumn(DbNameColumn column, const ref PgOIdColumnInfo oidColumn, const(bool) isNew) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(oidColumn=", oidColumn.traceString(), ")");

        column.baseName = oidColumn.name;
        column.baseNumericDigits = oidColumn.numericPrecision;
        column.baseNumericScale = oidColumn.numericScale;
        column.baseSize = oidColumn.size;
        column.baseTableId = oidColumn.tableOid;
        column.baseTypeId = oidColumn.type;
        column.baseSubTypeId = oidColumn.modifier;
        column.allowNull = oidColumn.allowNull;
        column.ordinal = oidColumn.ordinal;
        column.type = oidColumn.dbType();
        column.size = oidColumn.dbTypeSize();
    }

    final void processBindResponse(scope PgOIdColumnInfo[] oidColumnInfos) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (oidColumnInfos.length == 0)
            return;

        const localIsStoredProcedure = isStoredProcedure;
        auto params = localIsStoredProcedure ? parameters : null; // Use local var to avoid function call
        if (localIsStoredProcedure)
            params.reserve(oidColumnInfos.length);
        auto localColumns = columns; // Use local var to avoid function call
        localColumns.reserve(oidColumnInfos.length);
        foreach (i, ref oidColumn; oidColumnInfos)
        {
            auto newColumn = localColumns.create(this, oidColumn.name);
            fillNamedColumn(newColumn, oidColumn, true);
            localColumns.put(newColumn);

            if (localIsStoredProcedure)
            {
                auto foundParameter = params.hasOutput(newColumn.name, i);
                if (foundParameter is null)
                {
                    auto newParameter = params.create(newColumn.name);
                    newParameter.direction = DbParameterDirection.output;
                    fillNamedColumn(newParameter, oidColumn, true);
                    params.put(newParameter);
                }
                else
                {
                    if (foundParameter.name.length == 0 && newColumn.name.length != 0)
                        foundParameter.updateEmptyName(newColumn.name);
                    fillNamedColumn(foundParameter, oidColumn, false);
                }
            }
        }
    }

    final DbRowValue readRow(ref PgReader reader, const(bool) isScalar) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto protocol = pgConnection.protocol;
        return protocol.readValues(reader, this, cast(PgColumnList)columns);
    }
}

class PgConnection : SkConnection
{
public:
    this(PgDatabase database) nothrow @safe
    {
        super(database !is null ? database : pgDB);
        this._largeBlobManager = PgLargeBlobManager(this);
    }

    this(PgDatabase database, string connectionString) @safe
    {
        super(database !is null ? database : pgDB, connectionString);
        this._largeBlobManager = PgLargeBlobManager(this);
    }

    this(PgDatabase database, PgConnectionStringBuilder connectionString) nothrow @safe
    {
        super(database !is null ? database : pgDB, connectionString);
        this._largeBlobManager = PgLargeBlobManager(this);
    }

    this(PgDatabase database, DbURL!string connectionString) @safe
    {
        super(database !is null ? database : pgDB, connectionString);
        this._largeBlobManager = PgLargeBlobManager(this);
    }

    final override DbCancelCommandData createCancelCommandData(DbCommand command) @safe
    {
        return new PgCancelCommandData(this);
    }

    @property final ref PgLargeBlobManager largeBlobManager() nothrow @safe
    {
        return _largeBlobManager;
    }

    @property final PgConnectionStringBuilder pgConnectionStringBuilder() nothrow pure @safe
    {
        return cast(PgConnectionStringBuilder)connectionStringBuilder;
    }

    /**
     * Only available after open
     */
    @property final PgProtocol protocol() nothrow pure @safe
    {
        return _protocol;
    }

    @property final override DbScheme scheme() const nothrow pure @safe
    {
        return DbScheme.pg;
    }

    @property final override bool supportMultiReaders() const nothrow @safe
    {
        return false;
    }

package(pham.db):
    final DbReadBuffer acquireMessageReadBuffer(size_t capacity = PgDefaultSize.messageReadBufferLength) nothrow @safe
    {
        if (_messageReadBuffers.empty)
            return new DbReadBuffer(capacity);
        else
            return cast(DbReadBuffer)(_messageReadBuffers.remove(_messageReadBuffers.last));
    }

    final void releaseMessageReadBuffer(DbReadBuffer item) nothrow @safe
    {
        if (!isDisposing(lastDisposingReason))
            _messageReadBuffers.insertEnd(item.reset());
    }

protected:
    final override SkException createConnectError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new PgException(DbErrorCode.connect, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    final override SkException createReadDataError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new PgException(DbErrorCode.read, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    final override SkException createWriteDataError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new PgException(DbErrorCode.write, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    override void disposeCommands(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (isDisposing(disposingReason))
            this._largeBlobManager.dispose(disposingReason);
        else
            this._largeBlobManager.close();
        super.disposeCommands(disposingReason);
    }

    final void disposeMessageReadBuffers(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        while (!_messageReadBuffers.empty)
            _messageReadBuffers.remove(_messageReadBuffers.last).dispose(disposingReason);
    }

    final void disposeProtocol(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        if (_protocol !is null)
        {
            _protocol.dispose(disposingReason);
            _protocol = null;
        }
    }

    final override void doCancelCommand(DbCancelCommandData data) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        auto pgData = cast(PgCancelCommandData)data;
        _protocol.cancelRequestWrite(pgData.serverProcessId, pgData.serverSecretKey);
    }

    final override void doClose(bool failedOpen) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(failedOpen=", failedOpen, ", socketActive=", socketActive, ")");

        scope (exit)
            disposeProtocol(DisposingReason.other);

        if (!failedOpen)
            _largeBlobManager.doClose(DisposingReason.other);

        try
        {
            if (!failedOpen && _protocol !is null && canWriteDisconnectMessage())
                _protocol.disconnectWrite();
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.connection.doClose() - %s", forLogInfo(), e.msg, e);
        }

        super.doClose(failedOpen);
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        super.doDispose(disposingReason);
        disposeMessageReadBuffers(disposingReason);
        disposeProtocol(disposingReason);
    }

    final override void doOpen() @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        PgConnectingStateInfo stateInfo;

        doOpenSocket();
        doOpenAuthentication(stateInfo);
        _handle.setDummy();
    }

    final void doOpenAuthentication(ref PgConnectingStateInfo stateInfo) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        _protocol = new PgProtocol(this);
        _protocol.connectCheckingSSL(stateInfo);
        _protocol.connectAuthenticationWrite(stateInfo);
        _protocol.connectAuthenticationRead(stateInfo);
    }

    final override string getServerVersion() @safe
    {
        // Ex: SELECT version()="PostgreSQL 12.4, compiled by Visual C++ build 1914, 64-bit"
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        // Ex: 12.4
        auto v = this.executeScalar("SHOW server_version");
        return v.isNull() ? null : v.get!string();
    }

    final PgStoredProcedureInfo getStoredProcedureInfo(string storedProcedureName) @safe
    in
    {
        assert(storedProcedureName.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ")");

        PgStoredProcedureInfo result;

        const cacheKey = DbDatabase.generateCacheKeyStoredProcedure(storedProcedureName, this.forCacheKey);
        if (database.cache.find!PgStoredProcedureInfo(cacheKey, result))
            return result;

        auto command = createNonTransactionCommand();
        scope (exit)
            command.dispose();

        command.parametersCheck = true;
        command.commandText = q"{
SELECT pronargs, prorettype, proallargtypes, proargmodes, proargnames
FROM pg_proc
WHERE proname = @proname AND prokind = 'p'
ORDER BY oid
}";
        command.parameters.add("proname", DbType.stringVary).value = storedProcedureName;
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        if (reader.hasRows() && reader.read())
        {
            PgOIdColumnInfo info;

            result = new PgStoredProcedureInfo(cast(PgDatabase)database, storedProcedureName);

            //const numberInputArgs = reader.getValue(0).get!int32();
            const returnType = reader.getValue(1).get!PgOId();
            PgOId[] typeArgs = !reader.isNull(2) ? reader.getValue(2).get!(PgOId[])() : null;
            string[] modeArgs = !reader.isNull(3) ? reader.getValue(3).get!(string[])() : null;
            string[] nameArgs = !reader.isNull(4) ? reader.getValue(4).get!(string[])() : null;

            debug(debug_pham_db_db_pgdatabase) debug writeln("\t", "nameArgs=", nameArgs, ", typeArgs=", typeArgs, ", modeArgs=", modeArgs, ", returnType=", returnType);

            // Arguments
            foreach (i; 0..nameArgs.length)
            {
                if (i >= typeArgs.length || i >= modeArgs.length)
                {
                    //todo throw error?
                    break;
                }

                const paramType = typeArgs[i];
                const paramName = nameArgs[i];
                const mode = modeArgs[i];
                const paramDirection = pgParameterModeToDirection(mode);

                info.type = paramType;
                result.argumentTypes.add(
                    paramName.length ? paramName : result.argumentTypes.generateName(),
                    info.dbType(),
                    0,
                    paramDirection).baseTypeId = paramType;
            }

            // Return value type
            info.type = returnType;
            result.returnType.baseTypeId = returnType;
            result.returnType.type = info.dbType();
        }

        database.cache.addOrReplace(cacheKey, result);
        return result;
    }

protected:
    PgLargeBlobManager _largeBlobManager;
    PgProtocol _protocol;

private:
    DLinkDbBufferTypes.DLinkList _messageReadBuffers;
}

class PgConnectionStringBuilder : SkConnectionStringBuilder
{
@safe:

public:
    this(PgDatabase database) nothrow
    {
        super(database !is null ? database : pgDB);
    }

    this(PgDatabase database, string connectionString)
    {
        super(database !is null ? database : pgDB, connectionString);
    }

    final string integratedSecurityName() const nothrow
    {
        final switch (integratedSecurity) with (DbIntegratedSecurityConnection)
        {
            case legacy:
                return pgAuthMD5Name;
            case srp1:
            case srp256:
                return pgAuthScram256Name;
            case sspi:
                return "Not supported SSPI";
        }
    }

    final override const(string[]) parameterNames() const nothrow
    {
        return pgValidConnectionParameterNames;
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.pg;
    }

protected:
    final override string getDefault(string name) const nothrow
    {
        auto k = name in pgDefaultConnectionParameterValues;
        return k !is null && (*k).def.length != 0 ? (*k).def : super.getDefault(name);
    }

    final override void setDefaultIfs() nothrow
    {
        foreach (ref dpv; pgDefaultConnectionParameterValues.byKeyValue)
        {
            auto def = dpv.value.def;
            if (def.length)
                putIf(dpv.key, def);
        }
        super.setDefaultIfs();
    }
}

class PgDatabase : DbDatabase
{
@safe:

public:
    this() nothrow
    {
        super();
        _name = DbIdentitier(DbScheme.pg);

        _charClasses['"'] = CharClass.idenfifierQuote;
        _charClasses['\''] = CharClass.stringQuote;
        _charClasses['\\'] = CharClass.backslashSequence;

        populateValidParamNameChecks();
    }

    final override const(string[]) connectionStringParameterNames() const nothrow pure
    {
        return pgValidConnectionParameterNames;
    }

    override DbColumn createColumn(DbCommand command, DbIdentitier name) nothrow
    in
    {
        assert((cast(PgCommand)command) !is null);
    }
    do
    {
        return new PgColumn(cast(PgCommand)command, name);
    }

    override DbColumnList createColumnList(DbCommand command) nothrow
    in
    {
        assert(cast(PgCommand)command !is null);
    }
    do
    {
        return new PgColumnList(cast(PgCommand)command);
    }

    override DbCommand createCommand(DbConnection connection,
        string name = null) nothrow
    in
    {
        assert((cast(PgConnection)connection) !is null);
    }
    do
    {
        return new PgCommand(cast(PgConnection)connection, name);
    }

    override DbCommand createCommand(DbConnection connection, DbTransaction transaction,
        string name = null) nothrow
    in
    {
        assert((cast(PgConnection)connection) !is null);
        assert((cast(PgTransaction)transaction) !is null);
    }
    do
    {
        return new PgCommand(cast(PgConnection)connection, cast(PgTransaction)transaction, name);
    }

    override DbConnection createConnection(string connectionString)
    {
        auto result = new PgConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbConnectionStringBuilder connectionString) nothrow
    in
    {
        assert(connectionString !is null);
        assert(connectionString.scheme == DbScheme.pg);
        assert(cast(PgConnectionStringBuilder)connectionString !is null);
    }
    do
    {
        auto result = new PgConnection(this, cast(PgConnectionStringBuilder)connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbURL!string connectionString)
    in
    {
        assert(DbURL.scheme == DbScheme.pg);
        assert(DbURL.isValid());
    }
    do
    {
        auto result = new PgConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnectionStringBuilder createConnectionStringBuilder() nothrow
    {
        return new PgConnectionStringBuilder(this);
    }

    override DbConnectionStringBuilder createConnectionStringBuilder(string connectionString)
    {
        return new PgConnectionStringBuilder(this, connectionString);
    }

    override DbParameter createParameter(DbIdentitier name) nothrow
    {
        return new PgParameter(this, name);
    }

    override DbParameterList createParameterList() nothrow
    {
        return new PgParameterList(this);
    }

    override DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel,
        bool defaultTransaction = false) nothrow
    in
    {
        assert((cast(PgConnection)connection) !is null);
    }
    do
    {
        return new PgTransaction(cast(PgConnection)connection, isolationLevel);
    }

    // https://www.postgresql.org/docs/13/sql-select.html#SQL-LIMIT
    // LIMIT { count | ALL } OFFSET start
    final override string limitClause(int32 rows, uint32 offset = 0) const nothrow pure @safe
    {
        import pham.utl.utl_object : nToString = toString;

        // No restriction
        if (rows < 0)
            return null;

        // Returns empty
        if (rows == 0)
            return "LIMIT 0 OFFSET 0";

        auto buffer = Appender!string(50);
        return buffer.put("LIMIT ")
            .nToString(rows)
            .put(" OFFSET ")
            .nToString(offset)
            .data;
    }

    final override string parameterPlaceholder(string parameterName, uint32 ordinal) const nothrow pure @safe
    {
        import pham.utl.utl_object : nToString = toString;

        auto buffer = Appender!string(1 + 10);
        return buffer.put('$')
            .nToString(ordinal)
            .data;
    }

    // Does not support this contruct
    // select TOP(?) ... from ...
    final override string topClause(int32 rows) const nothrow pure @safe
    {
        return null;
    }

    @property final override bool returningClause() const nothrow pure
    {
        return true;
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.pg;
    }

    @property final override string tableHint() const nothrow pure
    {
        return null;
    }
}

class PgParameter : DbParameter
{
public:
    this(PgDatabase database, DbIdentitier name) nothrow @safe
    {
        super(database !is null ? database : pgDB, name);
    }

    final override DbColumnIdType isValueIdType() const nothrow @safe
    {
        return PgOIdColumnInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

protected:
    final override void reevaluateBaseType() nothrow @safe
    {
        foreach (ref pgType; pgNativeTypes)
        {
            if (pgType.dbType == _type)
            {
                baseSize = pgType.nativeSize;
                baseTypeId = pgType.dbId;
                break;
            }
        }
    }
}

class PgParameterList : DbParameterList
{
public:
    this(PgDatabase database) nothrow @safe
    {
        super(database !is null ? database : pgDB);
    }
}

class PgStoredProcedureInfo
{
public:
    this(PgDatabase database, string name) nothrow @safe
    {
        this._name = name;
        this._argumentTypes = new PgParameterList(database);
        this._returnType = new PgParameter(database, DbIdentitier(returnParameterName));
        this._returnType.direction = DbParameterDirection.returnValue;
    }

    @property final PgParameterList argumentTypes() nothrow @safe
    {
        return _argumentTypes;
    }

    @property final bool hasReturnType() const nothrow @safe
    {
        return _returnType.type != DbType.unknown;
    }

    @property final string name() const nothrow @safe
    {
        return _name;
    }

    @property final PgParameter returnType() nothrow @safe
    {
        return _returnType;
    }

private:
    string _name;
    PgParameter _returnType;
    PgParameterList _argumentTypes;
}

class PgTransaction : DbTransaction
{
public:
    this(PgConnection connection, DbIsolationLevel isolationLevel) nothrow @safe
    {
        super(connection, isolationLevel);
    }

    final override bool canSavePoint() @safe
    {
        enum minSupportVersion = VersionString("11.0");
        return super.canSavePoint() && VersionString(connection.serverVersion()) >= minSupportVersion;
    }

    @property final PgConnection pgConnection() nothrow pure @safe
    {
        return cast(PgConnection)connection;
    }

    /**
     * Allows application to customize the transaction request
     */
    @property final string transactionCommandText() nothrow @safe
    {
        return _transactionCommandText;
    }

    @property final typeof(this) transactionCommandText(string value) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        this._transactionCommandText = value;
        return this;
    }

protected:
    final string buildTransactionCommandText() const nothrow @safe
    {
        string writeOrReadMode() const nothrow @safe
        {
            return readOnly ? "READ ONLY" : "READ WRITE";
        }

        final switch (isolationLevel) with (DbIsolationLevel)
        {
            case readUncommitted:
                return "START TRANSACTION ISOLATION LEVEL READ UNCOMMITTED " ~ writeOrReadMode();
            case readCommitted:
                return "START TRANSACTION ISOLATION LEVEL READ COMMITTED " ~ writeOrReadMode();
            case repeatableRead:
                return "START TRANSACTION ISOLATION LEVEL REPEATABLE READ " ~ writeOrReadMode();
            case serializable:
                return "START TRANSACTION ISOLATION LEVEL SERIALIZABLE " ~ writeOrReadMode();
            case snapshot:
                return "START TRANSACTION ISOLATION LEVEL SERIALIZABLE " ~ writeOrReadMode();
        }
    }

    final override void doCommit(bool disposing) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(disposing=", disposing, ")");

        transactionCommand("COMMIT");
    }

    final override void doRollback(bool disposing) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(disposing=", disposing, ")");

        transactionCommand("ROLLBACK");
    }

    final override void doStart() @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "()");

        auto tmText = _transactionCommandText;
        if (tmText.length == 0)
            tmText = buildTransactionCommandText();

        transactionCommand(tmText);
    }

    final void transactionCommand(string tmText) @safe
    {
        debug(debug_pham_db_db_pgdatabase) debug writeln(__FUNCTION__, "(tmText=", tmText, ")");

        auto command = pgConnection.createNonTransactionCommand();
        scope (exit)
            command.dispose();

        command.commandText = tmText;
        command.executeNonQuery();
    }

private:
    string _transactionCommandText;
}


// Any below codes are private
private:

__gshared PgDatabase _pgDB;
shared static this() nothrow @trusted
{
    _pgDB = new PgDatabase();
    DbDatabaseList.registerDb(_pgDB);
}

shared static ~this() nothrow
{
    _pgDB = null;
}

pragma(inline, true)
@property PgDatabase pgDB() nothrow @trusted
{
    return _pgDB;
}

version(UnitTestPGDatabase)
{
    PgConnection createUnitTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        DbCompressConnection compress = DbCompressConnection.disabled)
    {
        import std.file : thisExePath;

        auto db = DbDatabaseList.getDb(DbScheme.pg);
        assert(cast(PgDatabase)db !is null);

        auto result = db.createConnection("");
        assert(cast(PgConnection)result !is null);

        auto csb = (cast(PgConnection)result).pgConnectionStringBuilder;
        csb.databaseName = "test";
        csb.userPassword = "masterkey";
        csb.receiveTimeout = dur!"seconds"(20);
        csb.sendTimeout = dur!"seconds"(10);
        csb.encrypt = encrypt;
        csb.compress = compress;
        csb.sslCa = "pg_ca.pem";
        csb.sslCaDir = thisExePath();
        csb.sslCert = "pg_client-cert.pem";
        csb.sslKey = "pg_client-key.pem";

        assert(csb.serverName == "localhost");
        assert(csb.serverPort == 5_432);
        assert(csb.userName == "postgres");
        assert(csb.databaseName == "test");
        assert(csb.userPassword == "masterkey");
        assert(csb.receiveTimeout == dur!"seconds"(20));
        assert(csb.sendTimeout == dur!"seconds"(10));
        assert(csb.encrypt == encrypt);
        assert(csb.compress == compress);
        assert(csb.sslCa == "pg_ca.pem");
        assert(csb.sslCaDir == thisExePath());
        assert(csb.sslCert == "pg_client-cert.pem");
        assert(csb.sslKey == "pg_client-key.pem");

        return cast(PgConnection)result;
    }

    string testStoredProcedureScheme() nothrow pure @safe
    {
        return q"{
CREATE PROCEDURE public.multiple_by(
  IN X integer,
  INOUT Y integer,
  OUT Z double precision)
LANGUAGE plpgsql
AS $$
BEGIN
  Y  = (X * 2);
  Z  = (Y * 2);
END;
$$
}";
    }

    string testTableSchema() nothrow pure @safe
    {
        return q"{
CREATE TABLE public.test_select (
  int_field INTEGER NOT NULL,
  smallint_field SMALLINT,
  float_field REAL,
  double_field DOUBLE PRECISION,
  numeric_field NUMERIC(15,2),
  decimal_field NUMERIC(15,2),
  date_field DATE,
  time_field TIME WITHOUT TIME ZONE,
  timestamp_field TIMESTAMP WITHOUT TIME ZONE,
  char_field CHAR(10),
  varchar_field VARCHAR(10),
  blob_field BYTEA,
  text_field TEXT,
  integer_array INTEGER[],
  bigint_field BIGINT)
}";
    }

    string testTableData() nothrow pure @safe
    {
        return q"{
INSERT INTO test_select (int_field, smallint_field, float_field, double_field, numeric_field, decimal_field, date_field, time_field, timestamp_field, char_field, varchar_field, blob_field, text_field, integer_array, bigint_field)
VALUES (1, 2, 3.1, 4.2, 5.40, 6.50, '2020-05-20', '01:01:01', '2020-05-20 07:31:00', 'ABC       ', 'XYZ', NULL, 'TEXT', NULL, 4294967296)
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

    // DbReader is a non-assignable struct so ref storage
    void validateSelectCommandTextReader(ref DbReader reader)
    {
        import std.math : isClose;

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;
            debug(debug_pham_db_db_pgdatabase) debug writeln("unittest pham.db.db_pgdatabase.PgCommand.DML.checking - count: ", count);

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
            assert(reader.getValue("TIME_FIELD") == DbTime(1, 1, 1));

            assert(reader.getValue(8) == DbDateTime(2020, 5, 20, 7, 31, 0));
            assert(reader.getValue("TIMESTAMP_FIELD") == DbDateTime(2020, 5, 20, 7, 31, 0));

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
    }
}

unittest // PgDatabase.limitClause
{
    assert(pgDB.limitClause(-1, 1) == "");
    assert(pgDB.limitClause(0, 1) == "LIMIT 0 OFFSET 0");
    assert(pgDB.limitClause(2, 1) == "LIMIT 2 OFFSET 1");
    assert(pgDB.limitClause(2) == "LIMIT 2 OFFSET 0");

    assert(pgDB.topClause(-1) == "");
    assert(pgDB.topClause(0) == "");
    assert(pgDB.topClause(10) == "");
}

unittest // PgDatabase.concate
{
    assert(pgDB.concate(["''", "''"]) == "'' || ''");
    assert(pgDB.concate(["abc", "'123'", "xyz"]) == "abc || '123' || xyz");
}

unittest // PgDatabase.escapeIdentifier
{
    assert(pgDB.escapeIdentifier("") == "");
    assert(pgDB.escapeIdentifier("'\"\"'") == "'\"\"\"\"'");
    assert(pgDB.escapeIdentifier("abc 123") == "abc 123");
    assert(pgDB.escapeIdentifier("\"abc 123\"") == "\"\"abc 123\"\"");
}

unittest // PgDatabase.quoteIdentifier
{
    assert(pgDB.quoteIdentifier("") == "\"\"");
    assert(pgDB.quoteIdentifier("'\"\"'") == "\"'\"\"\"\"'\"");
    assert(pgDB.quoteIdentifier("abc 123") == "\"abc 123\"");
    assert(pgDB.quoteIdentifier("\"abc 123\"") == "\"\"\"abc 123\"\"\"");
}

unittest // PgDatabase.escapeString
{
    assert(pgDB.escapeString("") == "");
    assert(pgDB.escapeString("\"''\"") == "\"''''\"");
    assert(pgDB.escapeString("abc 123") == "abc 123");
    assert(pgDB.escapeString("'abc 123'") == "''abc 123''");
}

unittest // PgDatabase.quoteString
{
    assert(pgDB.quoteString("") == "''");
    assert(pgDB.quoteString("\"''\"") == "'\"''''\"'");
    assert(pgDB.quoteString("abc 123") == "'abc 123'");
    assert(pgDB.quoteString("'abc 123'") == "'''abc 123'''");
}

version(UnitTestPGDatabase)
unittest // PgConnection
{
    import std.stdio : writeln; writeln("UnitTestPGDatabase.PgConnection"); // For first unittest

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version(UnitTestPGDatabase)
unittest // PgConnection.serverVersion
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    debug(debug_pham_db_db_pgdatabase) debug writeln("PgConnection.serverVersion=", connection.serverVersion);
    assert(connection.serverVersion.length > 0);
}

version(UnitTestPGDatabase)
unittest // PgTransaction
{
    auto connection = createUnitTestConnection();
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

version(UnitTestPGDatabase)
unittest // PgTransaction.savePoint
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto transaction = connection.createTransaction(DbIsolationLevel.readUncommitted);
    transaction.start();
    if (transaction.canSavePoint())
    {
        auto commit1 = transaction.start("commit1");
        auto rollback2 = transaction.start("rollback2");
        rollback2.rollback("rollback2");
        commit1.commit("commit1");
    }
    transaction.commit();
}

version(UnitTestPGDatabase)
unittest // PgCommand.DDL
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandDDL = q"{CREATE TABLE create_then_drop (a INT NOT NULL PRIMARY KEY, b VARCHAR(100))}";
    command.executeNonQuery();

    command.commandDDL = q"{DROP TABLE create_then_drop}";
    command.executeNonQuery();
}

version(UnitTestPGDatabase)
unittest // PgCommand.DML - Simple select
{
    import std.math;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    {
        command.commandText = simpleSelectCommandText();
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();
        validateSelectCommandTextReader(reader);
    }

    // Try again to make sure it is working
    {
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();
        validateSelectCommandTextReader(reader);
    }

    {
        command.commandText = simpleSelectCommandText()
            ~ " " ~ connection.limitClause(1);
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();
        validateSelectCommandTextReader(reader);
    }

    {
        command.commandText = simpleSelectCommandText()
            ~ " " ~ connection.limitClause(0);
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();
        assert(!reader.hasRows);
    }

    {
        command.commandText = simpleSelectCommandText()
            ~ " " ~ connection.limitClause(1, 1);
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();
        assert(!reader.hasRows);
    }
}

version(UnitTestPGDatabase)
unittest // PgCommand.DML - Parameter select
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = parameterSelectCommandText();
    command.parameters.add("INT_FIELD", DbType.int32).value = 1;
    command.parameters.add("DOUBLE_FIELD", DbType.float64).value = 4.20;
    command.parameters.add("DECIMAL_FIELD", DbType.numeric).value = Numeric(6.5);
    command.parameters.add("DATE_FIELD", DbType.date).value = DbDate(2020, 5, 20);
    command.parameters.add("TIME_FIELD", DbType.time).value = DbTime(1, 1, 1);
    command.parameters.add("CHAR_FIELD", DbType.stringFixed).value = "ABC       ";
    command.parameters.add("VARCHAR_FIELD", DbType.stringVary).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();
    validateSelectCommandTextReader(reader);
}

version(UnitTestPGDatabase)
unittest // PgCommand.DML.pg_proc
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = q"{
SELECT pg_proc.proname, pg_proc.pronargs, pg_proc.proargnames, pg_proc.proargtypes, pg_proc.proargmodes, pg_proc.prorettype
FROM pg_proc
WHERE pg_proc.proname in ('lo_open', 'lo_close', 'loread', 'lowrite', 'lo_lseek64', 'lo_creat', 'lo_create', 'lo_unlink')
ORDER BY pg_proc.proname
}";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    int count;
    assert(reader.hasRows());
    while (reader.read())
    {
        count++;
        debug(debug_pham_db_db_pgdatabase) debug writeln("unittest pham.db.db_pgdatabase.PgCommand.DML.checking - count: ", count);

        auto proname = reader.getValue("proname").toString();
        auto pronargs = reader.getValue("pronargs").toString();
        auto proargnames = reader.getValue("proargnames").toString();
        auto proargtypes = reader.getValue("proargtypes").toString();
        auto proargmodes = reader.getValue("proargmodes").toString();
        auto prorettype = reader.getValue("prorettype").toString();
        debug(debug_pham_db_db_pgdatabase) debug writeln("unittest pham.db.db_pgdatabase.PgCommand.DML.proname=", proname,
            ", pronargs=", pronargs, ", proargnames=", proargnames, ", proargtypes=", proargtypes,
            ", proargmodes=", proargmodes, ", prorettype=", prorettype);
    }
}

version(UnitTestPGDatabase)
unittest // PgLargeBlob
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    static immutable ubyte[] testData = [1,2,3,4,5,6,7,8,9,10];

    auto transaction = connection.createTransaction();
    transaction.start();
    scope (failure)
    {
        if (transaction)
            transaction.rollback();
    }

    auto blob = PgLargeBlob(connection);
    scope (exit)
        blob.dispose();
    blob.create();
    assert(blob.pgId != 0);

    blob.open();
    assert(blob.isOpen);

    blob.write(testData);
    assert(blob.length == testData.length);

    ubyte[] readData = new ubyte[](testData.length);
    blob.offset = 0;
    const readLenght = blob.read(readData);
    assert(readLenght == testData.length);
    assert(readData == testData);

    blob.close();
    assert(!blob.isOpen);

    blob.remove();
    assert(blob.pgId == 0);

    transaction.commit();

    transaction.dispose();
    transaction = null;
}

version(UnitTestPGDatabase)
unittest // PgCommand.DML - Array
{
    static int[] arrayValue() nothrow pure @safe
    {
        return [1,2,3,4,5,6,7,8,9,10];
    }

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
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
            debug(debug_pham_db_db_pgdatabase) debug writeln("unittest pham.db.pgdatabase.PgCommand.DML.checking - count: ", count);

            assert(reader.getValue(0) == arrayValue());
            assert(reader.getValue("INTEGER_ARRAY") == arrayValue());
        }
        assert(count == 1);
    }

    setArrayValue();
    readArrayValue();
}

version(UnitTestPGDatabase)
unittest // PgCommand.getExecutionPlan
{
    import std.array : split;
    //import std.stdio : writeln;
    import std.string : indexOf;

    static const(char)[] removePText(const(char)[] s)
    {
        while (1)
        {
            const i = s.indexOf('(');
            if (i < 0)
                break;
            const j = s.indexOf(')', i + 1);
            if (j < i)
                break;
            if (i == 0)
                s = s[j + 1..$];
            else if (j == s.length)
                s = s[0..i];
            else
                s = s[0..i] ~ s[j + 1..$];
        }
        return s;
    }

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();

    auto planDefault = command.getExecutionPlan(0);
    static immutable expectedDefault =
q"{Seq Scan on test_select  (cost=0.00..13.50 rows=1 width=260) (actual time=0.031..0.032 rows=1 loops=1)
  Filter: (int_field = 1)
  Buffers: shared hit=1
Planning Time: 0.062 ms
Execution Time: 0.053 ms}";
    //writeln("planDefault=", planDefault);
    // Can't check for exact because time change for each run
    auto lines = planDefault.split("\n");
    assert(lines.length >= 5);
    assert(planDefault.indexOf("Seq Scan on test_select") == 0);
    assert(planDefault.indexOf("Planning Time:") >= 3);
    assert(planDefault.indexOf("Execution Time:") >= 4);

    auto plan1 = command.getExecutionPlan(1);
    static immutable expectedPlan1 =
q"{Seq Scan on test_select  (cost=0.00..13.50 rows=1 width=260)
  Filter: (int_field = 1)}";
    //writeln("plan1=", plan1);
    assert(removePText(plan1) == removePText(expectedPlan1));
}

version(UnitTestPGDatabase)
unittest // PgCommand.DML.StoredProcedure
{
    import std.conv : to;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    {
        debug(debug_pham_db_db_pgdatabase) debug writeln("Get information");

        auto info = connection.getStoredProcedureInfo("multiple_by");
        assert(info !is null);
        assert(info.argumentTypes.length == 3, info.argumentTypes.length.to!string);
        assert(info.argumentTypes[0].name == "X");
        assert(info.argumentTypes[0].direction == DbParameterDirection.input);
        assert(info.argumentTypes[1].name == "Y");
        assert(info.argumentTypes[1].direction == DbParameterDirection.inputOutput);
        assert(info.argumentTypes[2].name == "Z");
        assert(info.argumentTypes[2].direction == DbParameterDirection.output);
    }

    {
        debug(debug_pham_db_db_pgdatabase) debug writeln("Execute procedure");

        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandStoredProcedure = "multiple_by";
        command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
        command.parameters.add("Y", DbType.int32, DbParameterDirection.inputOutput).value = 100;
        command.parameters.add("Z", DbType.float64, DbParameterDirection.output);
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
        assert(command.parameters.get("Z").variant == 8.0);
    }
}

version(UnitTestPGDatabase)
unittest // PgCommand.DML.StoredProcedure & Parameter select
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandStoredProcedure = "multiple_by";
    command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
    command.parameters.add("Y", DbType.int32, DbParameterDirection.inputOutput).value = 100;
    command.parameters.add("Z", DbType.float64, DbParameterDirection.output);
    command.executeNonQuery();
    assert(command.parameters.get("Y").variant == 4);
    assert(command.parameters.get("Z").variant == 8.0);

    command.commandText = parameterSelectCommandText();
    command.parameters.add("INT_FIELD", DbType.int32).value = 1;
    command.parameters.add("DOUBLE_FIELD", DbType.float64).value = 4.20;
    command.parameters.add("DECIMAL_FIELD", DbType.numeric).value = Numeric(6.5);
    command.parameters.add("DATE_FIELD", DbType.date).value = DbDate(2020, 5, 20);
    command.parameters.add("TIME_FIELD", DbType.time).value = DbTime(1, 1, 1);
    command.parameters.add("CHAR_FIELD", DbType.stringFixed).value = "ABC       ";
    command.parameters.add("VARCHAR_FIELD", DbType.stringVary).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();
    validateSelectCommandTextReader(reader);
}

version(UnitTestPGDatabase)
unittest // PgConnection(SSL)
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    auto csb = connection.pgConnectionStringBuilder;
    csb.encrypt = DbEncryptedConnection.enabled;

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

unittest // DbDatabaseList.createConnection
{
    auto connection = DbDatabaseList.createConnection("postgresql:server=myServerAddress;database=myDataBase;" ~
        "user=myUsername;password=myPassword;role=myRole;pooling=true;connectionTimeout=100seconds;encrypt=enabled;" ~
        "fetchRecordCount=50;integratedSecurity=legacy;");
    scope (exit)
        connection.dispose();
    auto connectionString = cast(PgConnectionStringBuilder)connection.connectionStringBuilder;

    assert(connection.scheme == DbScheme.pg);
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
}

unittest // DbDatabaseList.createConnectionByURL
{
    auto connection = DbDatabaseList.createConnectionByURL("postgresql://myUsername:myPassword@myServerAddress/myDataBase?" ~
        "role=myRole&pooling=true&connectionTimeout=100seconds&encrypt=enabled&" ~
        "fetchRecordCount=50&integratedSecurity=legacy");
    scope (exit)
        connection.dispose();
    auto connectionString = cast(PgConnectionStringBuilder)connection.connectionStringBuilder;

    assert(connection.scheme == DbScheme.pg);
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
}

version(UnitTestPerfPGDatabase)
{
    import pham.utl.utl_test : PerfTestResult;

    PerfTestResult unitTestPerfPGDatabase()
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
                version(all)
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

        auto connection = createUnitTestConnection();
        scope (exit)
            connection.dispose();
        connection.open();

        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        enum maxRecordCount = 100_000;
        command.commandText = "select * from foo limit 100000";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        version(UnitTestPGCollectData) auto datas = new Data[](maxRecordCount);
        else Data data;
        assert(reader.hasRows());

        auto result = PerfTestResult.create();
        while (result.count < maxRecordCount && reader.read())
        {
            version(UnitTestPGCollectData) datas[result.count++] = Data(reader);
            else { data.readData(reader); result.count++; }
        }
        result.end();
        assert(result.count > 0);
        return result;
    }
}

version(UnitTestPerfPGDatabase)
unittest // PgCommand.DML.Performance - https://github.com/FirebirdSQL/NETProvider/issues/953
{
    import std.format : format;

    const perfResult = unitTestPerfPGDatabase();
    dgWriteln("PG-Count: ", format!"%,3?d"('_', perfResult.count), ", Elapsed in msecs: ", format!"%,3?d"('_', perfResult.elapsedTimeMsecs()));
}

version(UnitTestPGDatabase)
unittest // PgConnection.DML.execute...
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto INT_FIELD = connection.executeScalar(simpleSelectCommandText());
    assert(INT_FIELD.get!int() == 1); // First field

    auto reader = connection.executeReader(simpleSelectCommandText());
    validateSelectCommandTextReader(reader);
    reader.dispose();

    auto TEXT_FIELD = connection.executeScalar("SELECT TEXT_FIELD FROM TEST_SELECT WHERE INT_FIELD = 1");
    assert(TEXT_FIELD.get!string() == "TEXT");
}

version(UnitTestPGDatabase)
unittest // PgConnection.DML.returning...
{
    import std.conv : to;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestReturning",
        "CREATE TABLE UnitTestReturning(pk INTEGER generated by default as identity primary key, i INTEGER, s VARCHAR(100))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestReturning");

    int pk = 0;
    auto reader = connection.executeReader("INSERT INTO UnitTestReturning(i, s) VALUES(100, 'AbC') RETURNING pk, i, s");
    assert(reader.hasRows());
    if (reader.read())
    {
        pk = reader.getValue("pk").get!int();
        assert(pk > 0, reader.getValue("pk").toString());
        assert(reader.getValue("i") == 100);
        assert(reader.getValue("s") == "AbC");
    }
    reader.dispose();

    auto i = connection.executeScalar("UPDATE UnitTestReturning SET i = 1000 WHERE pk = " ~ pk.to!string() ~ " RETURNING i");
    assert(i.value == 1000);
}

version(UnitTestPGDatabase)
unittest // PgDatabase.currentTimeStamp...
{
    import pham.dtm.dtm_date : DateTime;
    
    void countZero(string s, uint leastCount)
    {
        import std.format : format;

        //import std.stdio : writeln; debug writeln("s=", s, ", leastCount=", leastCount);

        uint count;
        size_t left = s.length;
        while (left && s[left-1] == '0')
        {
            count++;
            left--;
        }
        assert(count >= leastCount, format("%s - %d vs %d", s, count, leastCount));
    }

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto s = "SELECT to_char(" ~ connection.database.currentTimeStamp(0) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')";
    //import std.stdio : writeln; debug writeln("s=", s);
    auto v = connection.executeScalar(s);
    countZero(v.value.toString(), 6);

    v = connection.executeScalar("SELECT to_char(" ~ connection.database.currentTimeStamp(1) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')");
    countZero(v.value.toString(), 5);

    v = connection.executeScalar("SELECT to_char(" ~ connection.database.currentTimeStamp(2) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')");
    countZero(v.value.toString(), 4);

    v = connection.executeScalar("SELECT to_char(" ~ connection.database.currentTimeStamp(3) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')");
    countZero(v.value.toString(), 3);

    v = connection.executeScalar("SELECT to_char(" ~ connection.database.currentTimeStamp(4) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')");
    countZero(v.value.toString(), 2);

    v = connection.executeScalar("SELECT to_char(" ~ connection.database.currentTimeStamp(5) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')");
    countZero(v.value.toString(), 1);

    v = connection.executeScalar("SELECT to_char(" ~ connection.database.currentTimeStamp(6) ~ ", 'YYYY-MM-DD HH24:MI:SS.US')");
    countZero(v.value.toString(), 0);
    
    auto n = DateTime.now;
    auto t = connection.currentTimeStamp(6);
    assert(t.value.get!DateTime() >= n, t.value.get!DateTime().toString("%s") ~ " vs " ~ n.toString("%s"));
}

version(UnitTestPGDatabase)
unittest
{
    import std.stdio : writeln;
    writeln("UnitTestPGDatabase done");
}
