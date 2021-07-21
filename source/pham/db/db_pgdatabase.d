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

module pham.db.pgdatabase;

import std.array : Appender;
import std.conv : text, to;
import std.exception : assumeWontThrow;
import std.system : Endian;

import pham.external.std.log.logger : Logger, LogTimming;
version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.db.type;
import pham.db.message;
import pham.db.object;
import pham.db.util;
import pham.db.convert;
import pham.db.buffer;
import pham.db.value;
import pham.db.database;
import pham.db.skdatabase;
import pham.db.pgoid;
import pham.db.pgtype;
import pham.db.pgexception;
import pham.db.pgbuffer;
import pham.db.pgprotocol;


// Require in active transaction block
struct PgLargeBlob
{
public:
    enum maxBlockLength = 32_000;

    enum OpenMode : int32
    {
        write = 0x00020000,
        read  = 0x00040000,
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

    this(PgConnection connection) nothrow pure @safe
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
        dispose(false);
    }

    bool opCast(C: bool)() const nothrow @safe
    {
        return pgId != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    PgLargeBlob opCast(T)() const nothrow @safe
    if (is(Unqual!T == PgLargeBlob))
    {
        return this;
    }

    void close() @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen == true);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace();

        scope (exit)
            resetClose();
        pgConnection.largeBlobManager.close(pgDescriptorId);
    }

    void create(PgOId preferredId = 0) @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen == false);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace();

        _id = pgConnection.largeBlobManager.createPreferred(preferredId);
    }

    void dispose(bool disposing = true) nothrow @safe
    {
        if (isOpen && _connection)
        {
            try
            {
                close();
            }
            catch (Exception)
            {} //todo just log
        }

        _connection = null;
        reset();
    }

    int64 length() @safe
    in
    {
        assert(pgConnection !is null);
        assert(isOpen);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace();

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
        assert(pgId != 0);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

        if (pgId == 0)
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
        version (TraceFunction) dgFunctionTrace();

        size_t result = 0;
        while (result < data.length)
        {
            const leftLength = data.length - result;
            const readLength = leftLength > maxBlockLength ? maxBlockLength : leftLength;
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
        assert(pgId != 0);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

        _length = -1; // Need to reset the length
        size_t result = 0;
        while (result < data.length)
        {
            const leftLength = data.length - result;
            auto writeLength = leftLength > maxBlockLength ? maxBlockLength : leftLength;
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
        return _descriptorId;
    }

    @property PgOId pgId() const nothrow @safe
    {
        return _id;
    }

    @property bool isOpen() const nothrow @safe
    {
        return pgDescriptorId != pgInvalidDescriptorId;
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
    void reset() nothrow @safe
    {
        resetClose();
        _id = 0;
    }

    void resetClose() nothrow @safe
    {
        _descriptorId = pgInvalidDescriptorId;
        _length = -1;
        _offset = 0;
    }

    int64 seek(int64 offset, SeekOrigin origin) @safe
    {
        version (TraceFunction) dgFunctionTrace("offset=", offset, ", origin=", origin);

        return pgConnection.largeBlobManager.seek(pgDescriptorId, offset, origin);
    }

package(pham.db):
    PgConnection _connection;
    int64 _length = -1;
    int64 _offset;
    PgDescriptorId _descriptorId = pgInvalidDescriptorId;
    PgOId _id;
    OpenMode _mode;
}

struct PgLargeBlobManager
{
public:
    this(PgConnection connection) nothrow pure @safe
    {
        this._connection = connection;
    }

    ~this() @safe
    {
        dispose(false);
    }

    void dispose(bool disposing = true) nothrow @safe
    {
        disposeCommand(_close, disposing);
        disposeCommand(_createNew, disposing);
        disposeCommand(_createPreferred, disposing);
        disposeCommand(_open, disposing);
        disposeCommand(_read, disposing);
        disposeCommand(_seek, disposing);
        disposeCommand(_write, disposing);
        disposeCommand(_unlink, disposing);
        _connection = null;
    }

    int32 close(PgDescriptorId descriptorId) @safe
    {
        version (TraceFunction) dgFunctionTrace("descriptorId=", descriptorId);

        if (!_close)
            _close = createStoredProcedure("lo_close", [Argument("descriptorId", PgOIdType.int4)]);
        _close.parameters.get("descriptorId").value = descriptorId;
        return _close.executeScalar().get!int32();
    }

    PgOId createNew() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (!_createNew)
            _createNew = createStoredProcedure("lo_creat", [Argument("blobId", PgOIdType.int4)]);
        _createNew.parameters.get("blobId").value = -1;
        return _createNew.executeScalar().get!PgOId();
    }

    PgOId createPreferred(PgOId preferredId) @safe
    {
        version (TraceFunction) dgFunctionTrace("preferredId=", preferredId);

        if (!_createPreferred)
            _createPreferred = createStoredProcedure("lo_create", [Argument("blobId", PgOIdType.oid)]);
        _createPreferred.parameters.get("blobId").value = preferredId;
        return _createPreferred.executeScalar().get!PgOId();
    }

    PgDescriptorId open(PgOId blobId, int32 mode) @safe
    {
        version (TraceFunction) dgFunctionTrace("blobId=", blobId, ", mode=", mode);

        if (!_open)
            _open = createStoredProcedure("lo_open", [Argument("blobId", PgOIdType.oid), Argument("mode", PgOIdType.int4)]);
        _open.parameters.get("blobId").value = blobId;
        _open.parameters.get("mode").value = mode;
        return _open.executeScalar().get!PgDescriptorId();
    }

    ubyte[] read(PgDescriptorId descriptorId, int32 nBytes) @safe
    {
        version (TraceFunction) dgFunctionTrace("descriptorId=", descriptorId, ", nBytes=", nBytes);

        if (!_read)
            _read = createStoredProcedure("loread", [Argument("descriptorId", PgOIdType.int4), Argument("nBytes", PgOIdType.int4)]);
        _read.parameters.get("descriptorId").value = descriptorId;
        _read.parameters.get("nBytes").value = nBytes;
        auto result = _read.executeScalar();
        return !result.isNull ? result.get!(ubyte[])() : null;
    }

    int64 seek(PgDescriptorId descriptorId, int64 offset, int32 origin) @safe
    {
        version (TraceFunction) dgFunctionTrace("descriptorId=", descriptorId, ", offset=", offset, ", origin=", origin);

        if (!_seek)
            _seek = createStoredProcedure("lo_lseek64", [Argument("descriptorId", PgOIdType.int4), Argument("offset", PgOIdType.int8), Argument("origin", PgOIdType.int4)]);
        _seek.parameters.get("descriptorId").value = descriptorId;
        _seek.parameters.get("offset").value = offset;
        _seek.parameters.get("origin").value = origin;
        return _seek.executeScalar().get!int64();
    }

    int32 write(PgDescriptorId descriptorId, scope const(ubyte)[] bytes) @safe
    {
        version (TraceFunction) dgFunctionTrace("descriptorId=", descriptorId);

        if (!_write)
            _write = createStoredProcedure("lowrite", [Argument("descriptorId", PgOIdType.int4), Argument("bytes", PgOIdType.bytea)]);
        _write.parameters.get("descriptorId").value = descriptorId;
        _write.parameters.get("bytes").value = bytes.dup;
        return _write.executeScalar().get!int32();
    }

    int32 unlink(PgOId blobId) @safe
    {
        version (TraceFunction) dgFunctionTrace("blobId=", blobId);

        if (!_unlink)
            _unlink = createStoredProcedure("lo_unlink", [Argument("blobId", PgOIdType.oid)]);
        _unlink.parameters.get("blobId").value = blobId;
        return _unlink.executeScalar().get!int32();
    }

    /* Properties */

    @property final PgConnection pgConnection() nothrow pure @safe
    {
        return _connection;
    }

private:
    static struct Argument
    {
    nothrow @safe:

        string name;
        PgOId type;
    }

    PgCommand createStoredProcedure(string storedProcedureName, scope Argument[] arguments) @safe
    {
        version (TraceFunction) dgFunctionTrace("storedProcedureName=", storedProcedureName);

        auto result = pgConnection.createCommand(storedProcedureName);
        result.commandStoredProcedure = storedProcedureName;
        PgOIdFieldInfo info;
        foreach (ref argument; arguments)
        {
            info.type = argument.type;
            result.parameters.add(argument.name, info.dbType(), 0, DbParameterDirection.input).baseTypeId = argument.type;
        }
        return cast(PgCommand)result.prepare();
    }

    void disposeCommand(ref PgCommand command, bool disposing)  nothrow @safe
    {
        if (command)
        {
            command.disposal(disposing);
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

	final override const(char)[] getExecutionPlan(uint vendorMode)
	{
        version (TraceFunction) dgFunctionTrace("vendorMode=", vendorMode);

        auto explainQuery = new PgCommand(pgConnection);
        scope (exit)
            explainQuery.dispose();
        explainQuery.commandText = vendorMode == 0
            ? "EXPLAIN " ~ buildExecuteCommandText()
            : "EXPLAIN (ANALYZE, BUFFERS) " ~ buildExecuteCommandText();
        auto explainReader = explainQuery.executeReader();
        scope (exit)
            explainReader.dispose();

        size_t lines = 0;
        auto result = Appender!string();
        result.reserve(1000);
        while (explainReader.read())
        {
            if (lines)
                result.put('\n');
            result.put(explainReader.getValue(0).get!string());
            lines++;
        }
        return result.data;
    }

    final override Variant readArray(DbNameColumn arrayColumn, DbValue arrayValueId) @safe
    {
        return Variant.varNull();
    }

    final override ubyte[] readBlob(DbNameColumn blobColumn, DbValue blobValueId) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (blobValueId.isNull)
            return null;

        auto blob = PgLargeBlob(pgConnection, blobValueId.get!PgOId());
        return blob.openRead();
    }

    final override DbValue writeBlob(DbNameColumn blobColumn, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        auto blob = optionalBlobValueId.isNull
                    ? PgLargeBlob(pgConnection)
                    : PgLargeBlob(pgConnection, optionalBlobValueId.get!PgOId());
        blob.openWrite(blobValue);
        return DbValue(blob.pgId, blobColumn.type);
    }

    /* Properties */

    @property final PgConnection pgConnection() nothrow pure @safe
    {
        return cast(PgConnection)connection;
    }

    @property final PgFieldList pgFields() nothrow @safe
    {
        return cast(PgFieldList)fields;
    }

    @property final PgParameterList pgParameters() nothrow @safe
    {
        return cast(PgParameterList)parameters;
    }

package(pham.db):
    final PgParameter[] pgInputParameters() nothrow @trusted //@trusted=cast()
    {
        version (TraceFunction) dgFunctionTrace();

        return cast(PgParameter[])inputParameters();
    }

protected:
    final override string buildParameterPlaceholder(string parameterName, size_t ordinal) nothrow @safe
    {
        return "$" ~ to!string(ordinal);
    }

    override string buildStoredProcedureSql(string storedProcedureName) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace("storedProcedureName=", storedProcedureName);

        scope (failure) assert(0);

        if (storedProcedureName.length == 0)
            return storedProcedureName;

        if (!hasParameters)
        {
            auto info = pgConnection.getStoredProcedureInfo(storedProcedureName);
            foreach (src; info.argumentTypes)
                parameters.addClone(src);
        }

        auto params = inputParameters();
        auto result = Appender!string();
        result.reserve(500);
        result.put("SELECT * FROM ");
        result.put(storedProcedureName);
        result.put('(');
        foreach (i, param; params)
        {
            if (i)
                result.put(',');
			result.put(buildParameterPlaceholder(param.name, i + 1));
        }
        result.put(')');
        return result.data;
    }

    final override void doExecuteCommand(DbCommandExecuteType type) @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        if (!prepared)
            prepare();

        auto logTimming = logger !is null
            ? LogTimming(logger, text(forLogInfo(), newline, executeCommandText), false, dur!"seconds"(10))
            : LogTimming.init;

        prepareExecute(type);

        auto protocol = pgConnection.protocol;
        protocol.bindCommandParameterWrite(this);
        processBindResponse(protocol.bindCommandParameterRead(this));
        doExecuteCommandFetch(type, false);
    }

    final DbFetchResultStatus doExecuteCommandFetch(DbCommandExecuteType type, bool fetchAgain) @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type, ", fetchAgain=", fetchAgain);

        auto protocol = pgConnection.protocol;
        protocol.executeCommandWrite(this, type);
        PgReader reader;  // Since it is package message, need reader to continue reading row values
        auto response = protocol.executeCommandRead(this, type, reader);
        if (!fetchAgain)
        {
            _recordsAffected = response.recordsAffected;
            version (TraceFunction) dgFunctionTrace("_recordsAffected=", _recordsAffected);
        }

        const result = response.fetchStatus();
        final switch (result)
        {
            // Defer subsequence row for fetch call
            case DbFetchResultStatus.hasData:
                auto row = readRow(reader, type == DbCommandExecuteType.scalar);
                fetchedRows.enqueue(row);
                break;

            case DbFetchResultStatus.completed:
                allRowsFetched = true;
                break;

            // Next for fetch call
            case DbFetchResultStatus.ready:
                break;
        }

        /*
        if (isStoredProcedure)
        {
            auto response = protocol.readSqlResponse();
            if (response.count > 0)
            {
                auto row = readRow();
                fetchedOutputParams.enqueue(row);
                if (hasParameters)
                    mergeOutputParams(row);
            }
        }
        */

        return result;
    }

    final override void doFetch(bool isScalar) @safe
    in
    {
        assert(!allRowsFetched);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace("isScalar=", isScalar);
        version (profile) debug auto p = PerfFunction.create();

        auto protocol = pgConnection.protocol;
        auto continueFetchingCount = fetchRecordCount;
        bool continueFetching = true;
        bool isSuspended = false;
        while (continueFetching && continueFetchingCount)
        {
            PgReader reader; // Since it is package message, need reader to continue reading row values
            auto response = protocol.fetchCommandRead(this, isSuspended, reader);
            final switch (response.fetchStatus())
            {
                case DbFetchResultStatus.hasData:
                    continueFetchingCount--;
                    auto row = readRow(reader, isScalar);
                    fetchedRows.enqueue(row);
                    break;

                case DbFetchResultStatus.completed:
                    allRowsFetched = true;
                    continueFetching = false;
                    version (none) // Only valid if there is portal name
                    if (!isScalar && response.needFetchAgain(isSuspended))
                    {
                        final switch (doExecuteCommandFetch(DbCommandExecuteType.reader, true))
                        {
                            case DbFetchResultStatus.hasData:
                                continueFetchingCount--;
                                allRowsFetched = false;
                                continueFetching = true;
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
        version (TraceFunction) dgFunctionTrace();

        auto sql = executeCommandText; // Make sure statement is constructed before doing other tasks

        auto logTimming = logger !is null
            ? LogTimming(logger, text(forLogInfo(), newline, sql), false, dur!"seconds"(1))
            : LogTimming.init;

        auto protocol = pgConnection.protocol;
        protocol.prepareCommandWrite(this, sql);
        protocol.prepareCommandRead(this);
        _handle = pgCommandPreparedHandle;
    }

    final override void doUnprepare() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_handle)
        {
            // Must reset regardless if error taken place
            // to avoid double errors when connection is shutting down
            scope (exit)
                _handle.reset();

            auto protocol = pgConnection.protocol;
            protocol.unprepareCommandWrite(this);
            protocol.unprepareCommandRead();
        }
    }

    final override bool isSelectCommandType() const nothrow @safe
    {
        return hasFields;
    }

    final void processBindResponse(scope PgOIdFieldInfo[] oidFieldInfos) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (oidFieldInfos.length == 0)
            return;

        auto localFields = fields;
        foreach (ref oidFieldInfo; oidFieldInfos)
        {
            auto localField = localFields.createField(this, oidFieldInfo.name);
            localField.fillNamedColumn(oidFieldInfo, true);
            localFields.put(localField);
        }
    }

    final DbRowValue readRow(ref PgReader reader, bool isScalar) @safe
    {
        version (TraceFunction) dgFunctionTrace("isScalar=", isScalar);
        version (profile) debug auto p = PerfFunction.create();

        auto protocol = pgConnection.protocol;
        return protocol.readValues(this, reader, pgFields);
    }
}

class PgConnection : SkConnection
{
public:
    this(PgDatabase database) nothrow @safe
    {
        super(database);
        this._largeBlobManager._connection = this;
    }

    this(PgDatabase database, string connectionString) nothrow @safe
    {
        super(database, connectionString);
        this._largeBlobManager._connection = this;
    }

    this(DbDatabase database, PgConnectionStringBuilder connectionStringBuilder) nothrow @safe
    in
    {
        assert(connectionStringBuilder !is null);
    }
    do
    {
        super(database, connectionStringBuilder);
        this._largeBlobManager._connection = this;
    }

    /* Properties */

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

    @property final override DbIdentitier scheme() const nothrow pure @safe
    {
        return DbIdentitier(DbScheme.pg);
    }

protected:
    final override DbReadBuffer createSocketReadBuffer(size_t capacity = DbDefaultSize.socketReadBufferLength) nothrow @safe
    {
        return new SkReadBuffer(this, capacity);
    }

    final override DbBuffer createSocketWriteBuffer(size_t capacity = DbDefaultSize.socketWriteBufferLength) nothrow @safe
    {
        return new SkWriteBuffer!(Endian.bigEndian)(this, capacity);
    }

    override void disposeCommands(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _largeBlobManager.dispose(disposing);
        super.disposeCommands(disposing);
    }

    final void disposeProtocol(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_protocol !is null)
        {
            _protocol.disposal(disposing);
            _protocol = null;
        }
    }

    final override void doCancelCommand() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        auto serverProcessId = to!int32(serverInfo[DbIdentifier.serverProtocolProcessId]);
        auto serverSecretKey = to!int32(serverInfo[DbIdentifier.serverProtocolSecretKey]);
        _protocol.cancelRequestWrite(serverProcessId, serverSecretKey);
    }

    final override void doClose() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _largeBlobManager.dispose(false);
        if (_protocol !is null && state == DbConnectionState.open && socketActive)
            _protocol.disconnectWrite();
        disposeProtocol(false);
        super.doClose();
    }

    final override void doOpen() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        doOpenSocket();
        doOpenAuthentication();
    }

    final void doOpenAuthentication() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _protocol = new PgProtocol(this);
        _protocol.connectAuthenticationWrite();
        _protocol.connectAuthenticationRead();
    }

    final override string getServerVersion() @safe
    {
        auto command = createCommand();
        scope (exit)
        {
            command.dispose();
            command = null;
        }
        // Ex: SELECT version()="PostgreSQL 12.4, compiled by Visual C++ build 1914, 64-bit"
        // Ex: 12.4
        command.commandText = "SHOW server_version as VARCHAR(60)";
        auto v = command.executeScalar();
        return v.isNull() ? null : v.get!string();
    }

    final PgStoredProcedureInfo getStoredProcedureInfo(string storedProcedureName) @safe
    in
    {
        assert(storedProcedureName.length > 0);
    }
    do
    {
        //TODO cache this result
        version (TraceFunction) dgFunctionTrace("storedProcedureName=", storedProcedureName);

        auto command = createCommand(null);
        scope (exit)
            command.dispose();

        PgStoredProcedureInfo result;

        command.transactionRequired = false;
        command.commandText = q"{
SELECT pronargs, prorettype, proargtypes, proargmodes, proargnames
FROM pg_proc
WHERE proname = @proname
}";
        command.parameters.add("proname", DbType.string).value = storedProcedureName;
        auto reader = command.executeReader();
        if (reader.hasRows() && reader.read())
        {
            PgOIdFieldInfo info;

            result = new PgStoredProcedureInfo(cast(PgDatabase)database, storedProcedureName);

            const numberArgs = reader.getValue(0).get!int32();
            const returnType = reader.getValue(1).get!PgOId();
            PgOId[] typeArgs = numberArgs && !reader.isNull(2) ? reader.getValue(2).get!(PgOId[])() : null;
            string[] modeArgs = numberArgs && !reader.isNull(3) ? reader.getValue(3).get!(string[])() : null;
            string[] nameArgs = numberArgs && !reader.isNull(4) ? reader.getValue(4).get!(string[])() : null;

            // Arguments
            foreach (i; 0..numberArgs)
            {
                if (i >= typeArgs.length)
                {
                    //todo throw error
                    break;
                }

                auto paramType = typeArgs[i];
                auto paramName = i < nameArgs.length ? nameArgs[i] : null;
                auto mode = i < modeArgs.length ? modeArgs[i] : "i";
                auto paramDirection = DbParameterDirection.input;
                if (mode == "i")
                    paramDirection = DbParameterDirection.input;
                else if (mode == "o" || mode == "t")
                    paramDirection = DbParameterDirection.output;
                else if (mode == "b")
                    paramDirection = DbParameterDirection.inputOutput;
                else
                {} //todo throw error

                info.type = paramType;
                result.argumentTypes.add(
                    paramName.length ? paramName : result.argumentTypes.generateParameterName(),
                    info.dbType(),
                    0,
                    paramDirection).baseTypeId = paramType;
            }

            // Return value type
            info.type = returnType;
            result.returnType.baseTypeId = returnType;
            result.returnType.type = info.dbType();
        }
        reader.dispose();
        return result;
    }

protected:
    PgLargeBlobManager _largeBlobManager;
    PgProtocol _protocol;
}

class PgConnectionStringBuilder : SkConnectionStringBuilder
{
public:
    this(string connectionString) nothrow @safe
    {
        super(connectionString);
    }

    final override const(string[]) parameterNames() const nothrow @safe
    {
        return pgValidParameterNames;
    }

    @property final override DbIdentitier scheme() const nothrow pure @safe
    {
        return DbIdentitier(DbScheme.pg);
    }

protected:
    final override string getDefault(string name) const nothrow @safe
    {
        auto result = super.getDefault(name);
        if (result.ptr is null)
        {
            auto n = DbIdentitier(name);
            result = assumeWontThrow(pgDefaultParameterValues.get(n, null));
        }
        return result;
    }

    final override void setDefaultIfs() nothrow @safe
    {
        super.setDefaultIfs();
        putIf(DbParameterName.port, getDefault(DbParameterName.port));
        putIf(DbParameterName.userName, getDefault(DbParameterName.userName));
    }
}

class PgDatabase : DbDatabase
{
nothrow @safe:

public:
    this()
    {
        this._name = DbIdentitier(DbScheme.pg);
    }

    override DbCommand createCommand(DbConnection connection, string name = null)
    in
    {
        assert ((cast(PgConnection)connection) !is null);
    }
    do
    {
        return new PgCommand(cast(PgConnection)connection, name);
    }

    override DbCommand createCommand(DbConnection connection, DbTransaction transaction, string name = null)
    in
    {
        assert ((cast(PgConnection)connection) !is null);
        assert ((cast(PgTransaction)transaction) !is null);
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

    override DbConnection createConnection(DbConnectionStringBuilder connectionStringBuilder)
    in
    {
        assert(connectionStringBuilder !is null);
        assert(cast(PgConnectionStringBuilder)connectionStringBuilder !is null);
    }
    do
    {
        auto result = new PgConnection(this, cast(PgConnectionStringBuilder)connectionStringBuilder);
        result.logger = this.logger;
        return result;
    }

    override DbConnectionStringBuilder createConnectionStringBuilder(string connectionString)
    {
        return new PgConnectionStringBuilder(connectionString);
    }

    override DbField createField(DbCommand command, DbIdentitier name)
    in
    {
        assert ((cast(PgCommand)command) !is null);
    }
    do
    {
        return new PgField(cast(PgCommand)command, name);
    }

    override DbFieldList createFieldList(DbCommand command)
    in
    {
        assert (cast(PgCommand)command !is null);
    }
    do
    {
        return new PgFieldList(cast(PgCommand)command);
    }

    override DbParameter createParameter(DbIdentitier name)
    {
        return new PgParameter(this, name);
    }

    override DbParameterList createParameterList()
    {
        return new PgParameterList(this);
    }

    override DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel, bool defaultTransaction)
    in
    {
        assert ((cast(PgConnection)connection) !is null);
    }
    do
    {
        return new PgTransaction(cast(PgConnection)connection, isolationLevel);
    }
}

class PgField : DbField
{
public:
    this(PgCommand command, DbIdentitier name) nothrow @safe
    {
        super(command, name);
    }

    final override DbField createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createField(cast(PgCommand)command, name)
            : new PgField(cast(PgCommand)command, name);
    }

    final override DbFieldIdType isIdType() const nothrow pure @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        return PgOIdFieldInfo.isIdType(baseTypeId, baseSubTypeId);
    }

    @property final PgCommand pgCommand() nothrow pure @safe
    {
        return cast(PgCommand)_command;
    }
}

class PgFieldList: DbFieldList
{
public:
    this(PgCommand command) nothrow @safe
    {
        super(command);
    }

    final override DbField createField(DbCommand command, DbIdentitier name) nothrow
    {
        return database !is null
            ? database.createField(cast(PgCommand)command, name)
            : new PgField(cast(PgCommand)command, name);
    }

    final override DbFieldList createSelf(DbCommand command) nothrow
    {
        return database !is null
            ? database.createFieldList(cast(PgCommand)command)
            : new PgFieldList(cast(PgCommand)command);
    }

    @property final PgCommand pgCommand() nothrow pure @safe
    {
        return cast(PgCommand)_command;
    }
}

class PgParameter : DbParameter
{
public:
    this(PgDatabase database, DbIdentitier name) nothrow @safe
    {
        super(database, name);
    }

    final override DbFieldIdType isIdType() const nothrow pure @safe
    {
        return PgOIdFieldInfo.isIdType(baseTypeId, baseSubTypeId);
    }

protected:
    final override void reevaluateBaseType() nothrow @safe
    {
        foreach (ref pgType; pgNativeTypes)
        {
            // Must use completed type check
            if (pgType.dbType == _type)
            {
                baseSize = pgType.nativeSize;
                baseTypeId = pgType.nativeId;
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
        super(database);
    }
}

class PgStoredProcedureInfo
{
public:
    this(PgDatabase database, string name) nothrow @safe
    {
        this._name = name;
        this._argumentTypes = new PgParameterList(database);
        this._returnType = new PgParameter(database, DbIdentitier("return"));
        this._returnType.direction = DbParameterDirection.returnValue;
    }

    @property final PgParameterList argumentTypes() nothrow @safe
    {
        return _argumentTypes;
    }

    @property final bool hasReturnType() nothrow @safe
    {
        return _returnType.type != DbType.unknown;
    }

    @property final string name() nothrow @safe
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
        this._transactionMode = buildTransactionMode();
    }

    @property final PgConnection pgConnection() nothrow pure @safe
    {
        return cast(PgConnection)connection;
    }

    /**
     * Allows application to customize the transaction request
     */
    @property final string transactionMode() nothrow @safe
    {
        return _transactionMode;
    }

    @property final typeof(this) transactionMode(string value) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        _transactionMode = value;
        return this;
    }

protected:
    final string buildTransactionMode() nothrow @safe
    {
        string isolationLevelMode() nothrow @safe
        {
            final switch (isolationLevel)
            {
                case DbIsolationLevel.readCommitted:
                    return "READ COMMITTED";
                case DbIsolationLevel.serializable:
                    return "SERIALIZABLE";
                case DbIsolationLevel.readUncommitted:
                    return "READ UNCOMMITTED";
                case DbIsolationLevel.repeatableRead:
                    return "REPEATABLE READ";
                case DbIsolationLevel.snapshot:
                    return "SERIALIZABLE";
            }
        }

        string writeOrReadMode() nothrow @safe
        {
            return readOnly ? "READ ONLY" : "READ WRITE";
        }

        return "ISOLATION LEVEL " ~ isolationLevelMode() ~ " " ~ writeOrReadMode();
    }

    final override void doCommit(bool disposing) @safe
    {
        version (TraceFunction) dgFunctionTrace("disposing=", disposing);

        transactionCommand("COMMIT");
    }

    final override void doRollback(bool disposing) @safe
    {
        version (TraceFunction) dgFunctionTrace("disposing=", disposing);

        transactionCommand("ROLLBACK");
    }

    final override void doStart() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        auto mode = transactionMode;
        if (mode.length)
            transactionCommand("START TRANSACTION " ~ mode);
        else
            transactionCommand("START TRANSACTION");
    }

    final void transactionCommand(string transactionCommandText) @safe
    {
        auto command = pgConnection.createCommand(null);
        scope (exit)
            command.dispose();

        command.parametersCheck = false;
        command.returnRecordsAffected = false;
        command.transactionRequired = false;
        command.commandText = transactionCommandText;
        command.executeNonQuery();
    }

private:
    string _transactionMode;
}


// Any below codes are private
private:

shared static this()
{
    auto db = new PgDatabase();
    DbDatabaseList.registerDb(db);
}

void fillNamedColumn(DbNameColumn column, const ref PgOIdFieldInfo oidField, bool isNew) nothrow @safe
{
    version (TraceFunction)
    dgFunctionTrace("name=", oidField.name,
        ", modifier=", oidField.modifier,
        ", tableOid=", oidField.tableOid,
        ", type=", oidField.type,
        ", numericPrecision=", oidField.numericPrecision,
        ", numericScale=", oidField.numericScale,
        ", formatCode=", oidField.formatCode,
        ", index=", oidField.index,
        ", size=", oidField.size,
        ", dbType=", oidField.dbType);

    column.baseName = oidField.name;
    column.baseSize = oidField.size;
    column.baseTableId = oidField.tableOid;
    column.baseTypeId = oidField.type;
    column.baseSubTypeId = oidField.modifier;
    column.allowNull = oidField.allowNull;
    column.ordinal = oidField.index;

    if (isNew || column.type == DbType.unknown)
    {
        column.type = oidField.dbType();
        column.size = oidField.dbTypeSize();
    }
}

version (UnitTestPGDatabase)
{
    PgConnection createTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        bool compress = false)
    {
        auto db = DbDatabaseList.getDb(DbScheme.pg);
        assert(cast(PgDatabase)db !is null);

        auto result = db.createConnection("");
        result.connectionStringBuilder.databaseName = "test";
        result.connectionStringBuilder.userPassword = "masterkey";
        result.connectionStringBuilder.receiveTimeout = dur!"seconds"(20);
        result.connectionStringBuilder.sendTimeout = dur!"seconds"(10);
        result.connectionStringBuilder.encrypt = encrypt;
        result.connectionStringBuilder.compress = compress;

        assert(cast(PgConnection)result !is null);

        return cast(PgConnection)result;
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
  bigint_field BIGINT
)}";
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
}

version (UnitTestPGDatabase)
unittest // PgConnection
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgConnection");

    auto connection = createTestConnection();
    scope (exit)
    {
        connection.dispose();
        connection = null;
    }
    assert(connection.state == DbConnectionState.closed);

    connection.open();
    assert(connection.state == DbConnectionState.open);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version (UnitTestPGDatabase)
unittest // PgTransaction
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgTransaction");

    auto connection = createTestConnection();
    scope (exit)
    {
        connection.close();
        connection.dispose();
        connection = null;
    }
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

    transaction = null;
}

version (UnitTestPGDatabase)
unittest // PgCommand.DDL
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DDL");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
    {
        command.dispose();
        command = null;
    }

    command.commandDDL = q"{CREATE TABLE create_then_drop (a INT NOT NULL PRIMARY KEY, b VARCHAR(100))}";
    command.executeNonQuery();

    command.commandDDL = q"{DROP TABLE create_then_drop}";
    command.executeNonQuery();

    failed = false;
}

version (UnitTestPGDatabase)
unittest // PgCommand.DML
{
    import std.math;
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DML - Simple select");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
    {
        command.dispose();
        command = null;
    }

    command.commandText = simpleSelectCommandText();
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    int count;
    assert(reader.hasRows());
    while (reader.read())
    {
        count++;
        traceUnitTest("checking - count: ", count);

        assert(reader.getValue(0) == 1);
        assert(reader.getValue("INT_FIELD") == 1);

        assert(reader.getValue(1) == 2);
        assert(reader.getValue("SMALLINT_FIELD") == 2);

        assert(isClose(reader.getValue(2).get!float(), 3.10f));
        assert(isClose(reader.getValue("FLOAT_FIELD").get!float(), 3.10f));

        assert(isClose(reader.getValue(3).get!double(), 4.20));
        assert(isClose(reader.getValue("DOUBLE_FIELD").get!double(), 4.20));

        assert(decimalEqual(reader.getValue(4).get!Decimal64(), 5.4));
        assert(decimalEqual(reader.getValue("NUMERIC_FIELD").get!Decimal64(), 5.4));

        assert(decimalEqual(reader.getValue(5).get!Decimal64(), 6.5));
        assert(decimalEqual(reader.getValue("DECIMAL_FIELD").get!Decimal64(), 6.5));

        assert(reader.getValue(6) == Date(2020, 5, 20));
        assert(reader.getValue("DATE_FIELD") == Date(2020, 5, 20));

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

version (UnitTestPGDatabase)
unittest // PgCommand.DML
{
    import std.math;
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DML - Parameter select");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
    {
        command.dispose();
        command = null;
    }

    command.commandText = parameterSelectCommandText();
    command.parameters.add("INT_FIELD", DbType.int32).value = 1;
    command.parameters.add("DOUBLE_FIELD", DbType.float64).value = 4.20;
    command.parameters.add("DECIMAL_FIELD", DbType.numeric).value = Numeric(6.5);
    command.parameters.add("DATE_FIELD", DbType.date).value = Date(2020, 5, 20);
    command.parameters.add("TIME_FIELD", DbType.time).value = DbTime(1, 1, 1, 0);
    command.parameters.add("CHAR_FIELD", DbType.chars).value = "ABC       ";
    command.parameters.add("VARCHAR_FIELD", DbType.string).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    int count;
    assert(reader.hasRows());
    while (reader.read())
    {
        count++;
        traceUnitTest("checking - count: ", count);

        assert(reader.getValue(0) == 1);
        assert(reader.getValue("INT_FIELD") == 1);

        assert(reader.getValue(1) == 2);
        assert(reader.getValue("SMALLINT_FIELD") == 2);

        assert(isClose(reader.getValue(2).get!float(), 3.10f));
        assert(isClose(reader.getValue("FLOAT_FIELD").get!float(), 3.10f));

        assert(isClose(reader.getValue(3).get!double(), 4.20));
        assert(isClose(reader.getValue("DOUBLE_FIELD").get!double(), 4.20));

        assert(decimalEqual(reader.getValue(4).get!Decimal64(), 5.4));
        assert(decimalEqual(reader.getValue("NUMERIC_FIELD").get!Decimal64(), 5.4));

        assert(decimalEqual(reader.getValue(5).get!Decimal64(), 6.5));
        assert(decimalEqual(reader.getValue("DECIMAL_FIELD").get!Decimal64(), 6.5));

        assert(reader.getValue(6) == Date(2020, 5, 20));
        assert(reader.getValue("DATE_FIELD") == Date(2020, 5, 20));

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

version (UnitTestPGDatabase)
unittest // PgCommand.DML.pg_proc
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DML - pg_proc");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
    }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
    {
        command.dispose();
        command = null;
    }

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
        traceUnitTest("checking - count: ", count);

        traceUnitTest("proname=", reader.getValue("proname"),
            ", pronargs=", reader.getValue("pronargs"),
            ", proargnames=", reader.getValue("proargnames"),
            ", proargtypes=", reader.getValue("proargtypes"),
            ", proargmodes=", reader.getValue("proargmodes"),
            ", prorettype=", reader.getValue("prorettype"));
    }

    failed = false;
}

version (UnitTestPGDatabase)
unittest // PgLargeBlob
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgLargeBlob");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
    }
    connection.open();

    enum ubyte[] testData = [1,2,3,4,5,6,7,8,9,10];

    auto transaction = connection.createTransaction();
    transaction.start();
    scope (failure)
    {
        if (transaction)
            transaction.rollback();
    }

    auto blob = PgLargeBlob(connection);
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
    blob.dispose();

    transaction.commit();
    transaction.dispose();
    transaction = null;

    failed = false;
}

version (UnitTestPGDatabase)
unittest // PgCommand.DML
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DML - Array");

    static int[] arrayValue() nothrow pure @safe
    {
        return [1,2,3,4,5,6,7,8,9,10];
    }

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
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
            traceUnitTest("checking - count: ", count);

            assert(reader.getValue(0) == arrayValue());
            assert(reader.getValue("INTEGER_ARRAY") == arrayValue());
        }
        assert(count == 1);
    }

    setArrayValue();
    readArrayValue();

    failed = false;
}

version (UnitTestPGDatabase)
unittest // PgCommand.getExecutionPlan
{
    import std.algorithm.searching : startsWith;
    import std.array : split;
    import std.string : indexOf;
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.getExecutionPlan");

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

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
   }
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
    {
        command.dispose();
        command = null;
    }

    command.commandText = simpleSelectCommandText();

    auto expectedDefault =
q"{Seq Scan on test_select  (cost=0.00..13.50 rows=1 width=260)
  Filter: (int_field = 1)}";
    auto planDefault = command.getExecutionPlan();
    //traceUnitTest("'", removePText(planDefault), "' vs ", "'", removePText(expectedDefault), "'");
    assert(removePText(planDefault) == removePText(expectedDefault));

    auto expectedDetail =
q"{Seq Scan on test_select  (cost=0.00..13.50 rows=1 width=260) (actual time=0.031..0.032 rows=1 loops=1)
  Filter: (int_field = 1)
  Buffers: shared hit=1
Planning Time: 0.062 ms
Execution Time: 0.053 ms}";
    auto planDetail = command.getExecutionPlan(1);
    //traceUnitTest("'", planDetail, "'");
    //traceUnitTest("'", expectedDetail, "'");
    // Can't check for exact because time change for each run
    auto lines = planDetail.split("\n");
    assert(lines.length == 5);
    assert(startsWith(lines[0], "Seq Scan on test_select"));
    assert(startsWith(lines[3], "Planning Time:"));
    assert(startsWith(lines[4], "Execution Time:"));

    failed = false;
}

version (UnitTestPGDatabase)
unittest // PgCommand.DML.Function
{
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DML.Function");

    bool failed = true;
    auto connection = createTestConnection();
    scope (exit)
    {
        if (failed)
            traceUnitTest("failed - exiting and closing connection");

        connection.close();
        connection.dispose();
        connection = null;
    }
    connection.open();

    {
        auto command = connection.createCommand();
        scope (exit)
        {
            command.dispose();
            command = null;
        }

        command.commandText = "select * from multiple_by2(2)";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;

            assert(reader.getValue(0) == 4);
        }
        assert(count == 1);
    }

    {
        auto command = connection.createCommand();
        scope (exit)
        {
            command.dispose();
            command = null;
        }

        command.commandText = "select multiple_by2(2)";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;

            assert(reader.getValue(0) == 4);
        }
        assert(count == 1);
    }

    failed = false;
}

version (UnitTestPerfPGDatabase)
{
    import pham.utl.test : PerfTestResult;

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
                traceUnitTest("failed - exiting and closing connection");

            connection.close();
            connection.dispose();
            connection = null;
        }
        connection.open();

        auto command = connection.createCommand();
        scope (exit)
        {
            command.dispose();
            command = null;
        }

        command.commandText = "select * from foo";
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        enum maxRecordCount = 100_000;
        version (UnitTestPGCollectData) auto datas = new Data[](maxRecordCount);
        else Data data;
        assert(reader.hasRows());

        auto result = PerfTestResult.create();
        while (result.count < maxRecordCount && reader.read())
        {
            version (UnitTestPGCollectData) datas[result.count++] = Data(reader);
            else { data.readData(reader); result.count++; }
        }
        result.end();
        assert(result.count > 0);
        failed = false;
        return result;
    }
}

version (UnitTestPerfPGDatabase)
unittest // PgCommand.DML.Performance - https://github.com/FirebirdSQL/NETProvider/issues/953
{
    import std.format : format;
    import pham.utl.test;
    traceUnitTest("unittest db.pgdatabase.PgCommand.DML.Performance - https://github.com/FirebirdSQL/NETProvider/issues/953");

    const perfResult = unitTestPerfPGDatabase();
    dgWriteln("PG-Count: ", format!"%,3?d"('_', perfResult.count), ", Elapsed in msecs: ", format!"%,3?d"('_', perfResult.elapsedTimeMsecs()));
}
