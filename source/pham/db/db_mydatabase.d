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

module pham.db.db_mydatabase;

import std.conv : text, to;
import std.system : Endian;

debug(debug_pham_db_db_mydatabase) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.std.log.log_logger : Logger, LogLevel, LogTimming;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_enum_set;
import pham.utl.utl_result : ResultCode;
import pham.utl.utl_text : shortFunctionName;
import pham.utl.utl_version : VersionString;
import pham.db.db_buffer;
import pham.db.db_database;
import pham.db.db_exception;
import pham.db.db_message;
import pham.db.db_object;
import pham.db.db_skdatabase;
import pham.db.db_type;
import pham.db.db_util;
import pham.db.db_value;
import pham.db.db_mybuffer;
import pham.db.db_myexception;
import pham.db.db_myoid;
import pham.db.db_myprotocol;
import pham.db.db_mytype;

class MyCancelCommandData : DbCancelCommandData
{
@safe:

public:
    this(MyConnection connection)
    {
        this.serverProcessId = connection.serverInfo[DbServerIdentifier.protocolProcessId].to!int32();
    }

public:
    int32 serverProcessId;
}

class MyColumn : DbColumn
{
public:
    this(MyDatabase database, MyCommand command, DbIdentitier name) nothrow @safe
    {
        super(database !is null ? database : myDB, command, name);
    }

    final override DbColumn createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createColumn(cast(MyCommand)command, name)
            : new MyColumn(myDB, cast(MyCommand)command, name);
    }

    final override DbColumnIdType isValueIdType() const nothrow @safe
    {
        return MyColumnInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

    @property final MyCommand myCommand() nothrow pure @safe
    {
        return cast(MyCommand)_command;
    }
}

class MyColumnList: DbColumnList
{
public:
    this(MyDatabase database, MyCommand command) nothrow @safe
    {
        super(database !is null ? database : myDB, command);
    }

    @property final MyCommand myCommand() nothrow pure @safe
    {
        return cast(MyCommand)_command;
    }

protected:
    final override DbColumn createColumn(DbIdentitier name) nothrow @safe
    {
        return new MyColumn(database !is null ? cast(MyDatabase)database : myDB, myCommand, name);
    }

    final override DbColumnList createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createColumnList(cast(MyCommand)command)
            : new MyColumnList(myDB, cast(MyCommand)command);
    }
}

class MyCommand : SkCommand
{
public:
    this(MyDatabase database, MyConnection connection, string name = null) nothrow @safe
    {
        super(database, connection, name);
    }

    this(MyDatabase database, MyConnection connection, MyTransaction transaction, string name = null) nothrow @safe
    {
        super(database, connection, transaction, name);
    }

    final override string getExecutionPlan(uint vendorMode = 0) @safe
	{
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(vendorMode=", vendorMode, ")");

        if (auto log = canTraceLog())
            log.infof("%s.%s(vendorMode=%d)%s%s", forLogInfo(), shortFunctionName(2), vendorMode, newline, commandText);

        string explainFormat() nothrow @safe
        {
            switch (vendorMode)
            {
                case 0: return "FORMAT = TREE ";
                case 1: return "FORMAT = JSON ";
                default: return "";
            }
        }

        auto planCommandText = "EXPLAIN ANALYZE " ~ explainFormat()
            ~ buildExecuteCommandText(BuildCommandTextState.executingPlan);
        auto planCommand = myConnection.createNonTransactionCommand(true);
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

    final override Variant readArray(DbNamedColumn, DbValue) @safe
    {
        auto msg = DbMessage.eUnsupportFunction.fmtMessage(__FUNCTION__);
        throw new MyException(0, msg);
    }

    final override int64 readBlob(DbNamedColumn, DbValue, size_t) @safe
    {
        auto msg = DbMessage.eUnsupportFunction.fmtMessage(__FUNCTION__);
        throw new MyException(0, msg);
    }

    final override DbValue writeBlob(DbParameter, DbValue) @safe
    {
        auto msg = DbMessage.eUnsupportFunction.fmtMessage(__FUNCTION__);
        throw new MyException(0, msg);
    }

    @property final MyConnection myConnection() nothrow pure @safe
    {
        return cast(MyConnection)connection;
    }

    @property final MyCommandId myHandle() const nothrow @safe
    {
        return handle.get!MyCommandId();
    }

protected:
    override string buildStoredProcedureSql(string storedProcedureName, const(BuildCommandTextState) state) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ", state=", state, ")");

        if (storedProcedureName.length == 0)
            return null;

        if (!parameterCount && parametersCheck)
        {
            auto info = myConnection.getStoredProcedureInfo(storedProcedureName);
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
        result.put('`');
        result.put(storedProcedureName);
        result.put('`');
        result.put('(');

        size_t addPlaceHolderCount;
        void addPlaceHolder() nothrow @safe
        {
            if (addPlaceHolderCount)
                result.put(',');
            result.put('?');
            addPlaceHolderCount++;
        }

        size_t addInputNameCount;
        void addInputName(string name) nothrow @safe
        {
            if (addInputNameCount)
                result.put(',');
            result.put('@');
            result.put(name);
            addInputNameCount++;
        }

        auto outputNames = Appender!string(500);

        size_t addOutputNameCount;
        void addOutputName(string name) nothrow @safe
        {
            if (addOutputNameCount)
                outputNames.put(',');
            outputNames.put('@');
            outputNames.put(name);
            addOutputNameCount++;
        }

        if (state == BuildCommandTextState.prepare)
        {
            if (parameterCount)
            {
                foreach (param; parameters)
                    addPlaceHolder();
            }
            result.put(')');
        }
        else
        {
            if (parameterCount)
            {
                foreach (param; parameters)
                {
                    addInputName(param.name);
                    if (param.isOutput(OutputDirectionOnly.no))
                        addOutputName(param.name);
                }
            }

            result.put(')');
            if (addOutputNameCount)
            {
                result.put(";SELECT ");
                result.put(outputNames.data);
            }
        }

        debug(debug_pham_db_db_mydatabase) debug writeln("\t", "result=", result.data);

        return result.data;
    }

    final void deallocateHandle() @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        try
        {
            auto protocol = myConnection.protocol;
            protocol.deallocateCommandWrite(this);
        }
        catch (Exception e)
        {
            debug(debug_pham_db_db_mydatabase) debug writeln("\t", e.msg);
            if (auto log = canErrorLog())
                log.errorf("%s.%s() - %s%s%s", forLogInfo(), shortFunctionName(2), e.msg, newline, commandText, e);
        }
    }

    final override void doExecuteCommand(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(type=", type, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".", shortFunctionName(2), "()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        const lPrepared = prepared;

        auto protocol = myConnection.protocol;
        if (lPrepared)
            protocol.executeCommandWrite(this, type);
        else
            protocol.executeCommandDirectWrite(this, executeCommandText(BuildCommandTextState.execute));
        auto response = lPrepared
            ? protocol.executeCommandRead(this)
            : protocol.executeCommandDirectRead(this);
        processExecuteResponse(response, 1);

        const lhasOutputParameters = isStoredProcedure && hasOutputParameters;
        if (lhasOutputParameters && !lPrepared)
        {
            auto response2 = protocol.executeCommandDirectRead(this);
            processExecuteResponse(response2, 2);
        }

        // Mark command as active?
        if (!_handle && (isSelectCommandType || lhasOutputParameters))
            _handle.setDummy();

        resetStatement(ResetStatementKind.executed);

        if (lhasOutputParameters && type != DbCommandExecuteType.reader)
        {
            doFetch(true);
            if (_fetchedRows)
            {
                auto row = _fetchedRows.front;
                mergeOutputParams(row);
            }
            if (lPrepared)
                protocol.readOkResponse();
        }

        doStateChange(commandState);
    }

    final override bool doExecuteCommandNeedPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        static immutable inOutFlags = EnumSet!DbParameterDirection([DbParameterDirection.inputOutput]);

        // Need prepare for storedProcedure with inputOutput parameter(s)
        return super.doExecuteCommandNeedPrepare(type) || (!parameterCount && isStoredProcedure) || hasParameters(inOutFlags);
    }

    final override void doFetch(const(bool) isScalar) @safe
    in
    {
        assert(!allRowsFetched);
    }
    do
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ", fetchRecordCount=", fetchRecordCount, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".", shortFunctionName(2), "()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = myConnection.protocol;
        auto continueFetchingCount = true;
        while (continueFetchingCount)
        {
            MyReader rowPackage;
            if (!protocol.readRow(rowPackage))
            {
                debug(debug_pham_db_db_mydatabase) debug writeln("\t", "allRowsFetched=true");
                allRowsFetched = true;
                continueFetchingCount = false;
                break;
            }

            auto row = readRow(rowPackage);
            _fetchedRows.enqueue(row);
            _fetchedRowCount++;
        }
    }

    final override void doPrepare() @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");
        version(profile) debug auto p = PerfFunction.create();

        auto sql = executeCommandText(BuildCommandTextState.prepare);

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".", shortFunctionName(2), "()", newline, sql), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = myConnection.protocol;
        protocol.prepareCommandWrite(this, sql);
        auto response = protocol.prepareCommandRead(this);
        _handle = response.id;
        processPrepareResponse(response);
    }

    final override void doUnprepare(const(bool) isPreparedError) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(isPreparedError=", isPreparedError, ")");

        if (!isPreparedError && !connection.isFatalError)
            purgePendingRows();

        if (_handle && !_handle.isDummy && !connection.isFatalError)
            deallocateHandle();
    }

    static void fillNamedColumn(DbNamedColumn column, const ref MyColumnInfo myColumn, const(bool) isNew) nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(myColumn=", myColumn.traceString(), ")");

        column.baseName = myColumn.useName();
        column.baseNumericDigits = cast(int16)myColumn.precision;
        column.baseNumericScale = myColumn.scale;
        column.baseSize = myColumn.columnLength;
        column.baseSubTypeId = myColumn.typeFlags;
        column.baseTableName = myColumn.useTableName();
        column.baseTypeId = myColumn.typeId;
        column.allowNull = myColumn.allowNull;
        column.type = myColumn.dbType();
        column.size = myColumn.dbTypeSize();

        auto f = cast(DbColumn)column;
        if (f !is null)
        {
            f.isKey = myColumn.isPrimaryKey;
            f.isUnique = myColumn.isUnique;
        }
    }

    final void processExecuteResponse(ref MyCommandResultResponse response, const(int) counter) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(response.okResponse.lastInsertId=", response.okResponse.lastInsertId,
            ", response.okResponse.affectedRows=", response.okResponse.affectedRows, ", response.columns.length=", response.columns.length, ")");

        if (counter == 1)
        {
            _lastInsertedId = response.okResponse.lastInsertId;
            _recordsAffected = response.okResponse.affectedRows;
        }

        if (response.columns.length != 0)
        {
            auto localColumns = columns;

            if (prepared)
            {
                if (localColumns.length != response.columns.length)
                    localColumns.clear();
            }
            else
            {
                localColumns.clear();
            }

            if (localColumns.length == 0)
            {
                localColumns.reserve(response.columns.length);
                foreach (ref myColumn; response.columns)
                {
                    auto newName = myColumn.useName;
                    auto newColumn = localColumns.create(newName);
                    fillNamedColumn(newColumn, myColumn, true);
                    localColumns.put(newColumn);
                }

                doColumnCreated();
            }
        }
    }

    final void processPrepareResponse(ref MyCommandPreparedResponse response) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        if (response.parameters.length != 0)
        {
            auto params = parameters; // Use local var to avoid function call
            params.reserve(response.parameters.length);
            foreach (i, ref myParameter; response.parameters)
            {
                 if (i >= params.length)
                {
                    auto newName = myParameter.useName;
                    if (params.exist(newName))
                        newName = params.generateName();
                    auto newParameter = params.create(newName);
                    fillNamedColumn(newParameter, myParameter, true);
                    params.put(newParameter);
                }
                else
                    fillNamedColumn(params[i], myParameter, false);
            }
        }

        if (response.columns.length != 0)
        {
            const localIsStoredProcedure = isStoredProcedure;
            auto params = localIsStoredProcedure ? parameters : null; // Use local var to avoid function call
            if (localIsStoredProcedure)
                params.reserve(response.columns.length);
            auto localColumns = columns; // Use local var to avoid function call
            localColumns.reserve(response.columns.length);
            foreach (i, ref myColumn; response.columns)
            {
                auto newColumn = localColumns.create(myColumn.useName);
                newColumn.isAlias = myColumn.isAlias;
                fillNamedColumn(newColumn, myColumn, true);
                localColumns.put(newColumn);

                if (localIsStoredProcedure)
                {
                    auto foundParameter = params.hasOutput(newColumn.name, i);
                    if (foundParameter is null)
                    {
                        auto newParameter = params.create(newColumn.name);
                        newParameter.direction = DbParameterDirection.output;
                        fillNamedColumn(newParameter, myColumn, true);
                        params.put(newParameter);
                    }
                    else
                    {
                        if (foundParameter.name.length == 0 && newColumn.name.length != 0)
                            foundParameter.updateEmptyName(newColumn.name);
                        fillNamedColumn(foundParameter, myColumn, false);
                    }
                }
            }

            doColumnCreated();
        }
    }

    final void purgePendingRows() nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        if (!isSelectCommandType || allRowsFetched)
            return;

        try
        {
            auto protocol = myConnection.protocol;
            protocol.purgePendingRows();
            allRowsFetched = true;
        }
        catch (Exception e)
        {
            debug(debug_pham_db_db_mydatabase) debug writeln("\t", e.msg);
            if (auto log = canErrorLog())
                log.errorf("%s.%s() - %s%s%s", forLogInfo(), shortFunctionName(2), e.msg, newline, commandText, e);
        }
    }

    final DbRowValue readRow(ref MyReader rowPackage) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");
        version(profile) debug auto p = PerfFunction.create();

        auto protocol = myConnection.protocol;
        return protocol.readValues(rowPackage, this, cast(MyColumnList)columns, _fetchedRowCount);
    }

    override void removeReaderCompleted(const(bool) implicitTransaction) nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        purgePendingRows();
        super.removeReaderCompleted(implicitTransaction);
    }
}

struct MyCommandResult
{
public:
    this(MyCommand command)
    {
        this._command = command;
        this.reset();
    }

    ~this()
    {
        close(true);
    }

    void close(const(bool) disposing)
    {
        scope (exit)
        {
            if (disposing)
                _command = null;
        }

        if (empty)
            return;
    }

    void reset()
    {
        _rowCount = 0;
        _flags.set(Flag.hasOutputParameter, command.isStoredProcedure && command.hasOutputParameters != 0);
    }

    @property MyCommand command() nothrow pure @safe
    {
        return _command;
    }

    @property bool empty() const nothrow @safe
    {
        return _flags.done;
    }

    @property size_t rowCount() const nothrow @safe
    {
        return _rowCount;
    }

private:
    enum Flag
    {
        done = 1 << 0,
        hasOutputParameter = 1 << 1,
    }

    MyCommand _command;
    size_t _rowCount;
    EnumSet!Flag _flags;
}

class MyConnection : SkConnection
{
public:
    this(MyDatabase database) nothrow @safe
    {
        super(database !is null ? database : myDB);
    }

    this(MyDatabase database, string connectionString) @safe
    {
        super(database !is null ? database : myDB, connectionString);
    }

    this(MyDatabase database, MyConnectionStringBuilder connectionString) nothrow @safe
    {
        super(database !is null ? database : myDB, connectionString);
    }

    this(MyDatabase database, DbURL!string connectionString) @safe
    {
        super(database !is null ? database : myDB, connectionString);
    }

    final override DbCancelCommandData createCancelCommandData(DbCommand command) @safe
    {
        return new MyCancelCommandData(this);
    }

    @property final MyConnectionStringBuilder myConnectionStringBuilder() nothrow pure @safe
    {
        return cast(MyConnectionStringBuilder)connectionStringBuilder;
    }

    /**
     * Only available after open
     */
    @property final MyProtocol protocol() nothrow pure @safe
    {
        return _protocol;
    }

    @property final override DbScheme scheme() const nothrow pure @safe
    {
        return DbScheme.my;
    }

    @property final uint32 serverCapabilities() const nothrow @safe
    {
        return _protocol !is null ? _protocol.connectionFlags : 0u;
    }

    @property final override bool supportMultiReaders() const nothrow @safe
    {
        return false;
    }

public:
    MyColumnTypeMap columnTypeMaps;

    deprecated("please use columnTypeMaps")
    alias fieldTypeMaps = columnTypeMaps;

package(pham.db):
    final DbReadBuffer acquirePackageReadBuffer(size_t capacity = MyDefaultSize.packetReadBufferLength) nothrow @safe
    {
        if (_packageReadBuffers.empty)
            return new DbReadBuffer(capacity);
        else
            return cast(DbReadBuffer)(_packageReadBuffers.remove(_packageReadBuffers.last));
    }

    final void releasePackageReadBuffer(DbReadBuffer item) nothrow @safe
    {
        if (isDisposing(lastDisposingReason) || (!_packageReadBuffers.empty && item.isOverCachedCapacityLimit()))
            item.dispose(DisposingReason.dispose);
        else
            _packageReadBuffers.insertEnd(item.reset());
    }

    final DbWriteBuffer acquireParameterWriteBuffer(size_t capacity = MyDefaultSize.parameterBufferLength) nothrow @safe
    {
        if (_parameterWriteBuffers.empty)
            return new DbWriteBuffer(capacity);
        else
            return cast(DbWriteBuffer)(_parameterWriteBuffers.remove(_parameterWriteBuffers.last));
    }

    final void releaseParameterWriteBuffer(DbWriteBuffer item) nothrow @safe
    {
        if (isDisposing(lastDisposingReason) || (!_parameterWriteBuffers.empty && item.isOverCachedCapacityLimit()))
            item.dispose(DisposingReason.dispose);
        else
            _parameterWriteBuffers.insertEnd(item.reset());
    }

protected:
    final override SkException createConnectError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new MyException(DbErrorCode.connect, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    final override SkException createReadDataError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new MyException(DbErrorCode.read, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    final override SkException createWriteDataError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new MyException(DbErrorCode.write, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    final override DbReadBuffer createSocketReadBuffer() nothrow @safe
    {
        return new SkReadBuffer(this, MyDefaultSize.socketReadBufferLength);
    }

    final override DbWriteBuffer createSocketWriteBuffer() nothrow @safe
    {
        return new SkWriteBuffer(this, MyDefaultSize.socketWriteBufferLength);
    }

    final void disposePackageReadBuffers(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        while (!_packageReadBuffers.empty)
            _packageReadBuffers.remove(_packageReadBuffers.last).dispose(disposingReason);
    }

    final void disposeProtocol(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        if (_protocol !is null)
        {
            _protocol.dispose(disposingReason);
            _protocol = null;
        }
    }

    final override void doCancelCommandImpl(DbCancelCommandData data) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        auto myData = cast(MyCancelCommandData)data;
        auto cancelCommandText = "KILL QUERY " ~ myData.serverProcessId.to!string();

        auto command = createCommand(null);
        scope (exit)
            command.dispose();

        command.parametersCheck = false;
        command.returnRecordsAffected = false;
        command.transactionRequired = false;
        command.commandText = cancelCommandText;
        command.executeNonQuery();
    }

    final override void doCloseImpl(const(DbConnectionState) reasonState) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(reasonState=", reasonState, ", socketActive=", socketActive, ")");

        const isFailing = isFatalError || reasonState == DbConnectionState.failing;

        scope (exit)
            disposeProtocol(DisposingReason.other);

        try
        {
            if (!isFailing && _protocol !is null && canWriteDisconnectMessage())
                _protocol.disconnectWrite();
        }
        catch (Exception e)
        {
            debug(debug_pham_db_db_mydatabase) debug writeln("\t", e.msg);
            if (auto log = canErrorLog())
                log.errorf("%s.%s() - %s", forLogInfo(), shortFunctionName(2), e.msg, e);
        }

        super.doCloseImpl(reasonState);
    }

    override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        // Must call super first to close the connection with use protocol & parameter buffers
        super.doDispose(disposingReason);
        disposePackageReadBuffers(disposingReason);
        disposeProtocol(disposingReason);
        return ResultCode.ok;
    }

    final override DbRoutineInfo doGetStoredProcedureInfo(string storedProcedureName, string schema) @safe
    in
    {
        assert(storedProcedureName.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ")");

        auto command = createNonTransactionCommand();
        scope (exit)
            command.dispose();

        static immutable withSchema = q"{
SELECT ORDINAL_POSITION, PARAMETER_NAME, DATA_TYPE, PARAMETER_MODE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.PARAMETERS
WHERE ROUTINE_TYPE = @ROUTINE_TYPE AND SPECIFIC_NAME = @SPECIFIC_NAME AND SPECIFIC_SCHEMA = @SPECIFIC_SCHEMA
ORDER BY ORDINAL_POSITION
}";

        static immutable withoutSchema = q"{
SELECT ORDINAL_POSITION, PARAMETER_NAME, DATA_TYPE, PARAMETER_MODE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.PARAMETERS
WHERE ROUTINE_TYPE = @ROUTINE_TYPE AND SPECIFIC_NAME = @SPECIFIC_NAME
ORDER BY ORDINAL_POSITION
}";

        command.parametersCheck = true;
        command.commandText = schema.length != 0 ? withSchema : withoutSchema;
        command.parameters.add("ROUTINE_TYPE", DbType.stringVary).value = DbRoutineType.storedProcedure;
        command.parameters.add("SPECIFIC_NAME", DbType.stringVary).value = storedProcedureName;
        if (schema.length != 0)
            command.parameters.add("SPECIFIC_SCHEMA", DbType.stringVary).value = schema;
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        if (reader.hasRows())
        {
            debug(debug_pham_db_db_mydatabase)
            {
                foreach (column; reader.columns)
                    debug writeln("\t", column.traceString());
            }

            auto result = new MyStoredProcedureInfo(cast(MyDatabase)database, storedProcedureName);
            while (reader.read())
            {
                // pos=0 is a return type one
                const pos = reader.getValue!int64(0);
                const name = reader.getValue!string(1);
                const dataType = reader.getValue!string(2);
                const mode = reader.getValue!string(3);
                const size = reader.getValue!int64(4);
                const precision = reader.getValue!int32(5);
                const scale = reader.getValue!int64(6);

                debug(debug_pham_db_db_mydatabase) debug writeln("\t", "name=", name, ", dataType=", dataType, ", size=", size, ", mode=", mode);

                const isParameter = pos > 0; // Position zero is a return type info
                const paramDirection = isParameter ? parameterModeToDirection(mode) : DbParameterDirection.returnValue;
                auto paramType = myParameterTypeToDbType(dataType, precision);
                if (isParameter)
                {
                    auto p = result.argumentTypes.add(name, paramType, cast(int32)size, paramDirection);
                    p.baseSize = cast(int32)size;
                    p.baseNumericDigits = cast(int16)precision;
                    p.baseNumericScale = cast(int16)scale;
                }
                else
                {
                    result.returnType.type = paramType;
                    result.returnType.size = cast(int32)size;
                    result.returnType.baseSize = cast(int32)size;
                    result.returnType.baseNumericDigits = cast(int16)precision;
                    result.returnType.baseNumericScale = cast(int16)scale;
                }
            }
            return result;
        }

        return null;
    }

    final override void doOpenImpl() @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        MyConnectingStateInfo stateInfo;

        doOpenSocket();
        doOpenAuthentication(stateInfo);
        _handle.setDummy();
    }

    final void doOpenAuthentication(ref MyConnectingStateInfo stateInfo) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        _protocol = new MyProtocol(this);
        _protocol.connectGreetingRead(stateInfo);
        _protocol.connectAuthenticationWrite(stateInfo);
        _protocol.connectAuthenticationRead(stateInfo);
    }

    final override string getServerVersionImpl() @safe
    {
        // Use this command "SHOW VARIABLES LIKE 'version'" or "SHOW VARIABLES LIKE '%version%'"
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        auto command = createNonTransactionCommand();
        scope (exit)
            command.dispose();

        // Variable_name, Value
        // 'version', '8.0.27'
        command.commandText = "SHOW VARIABLES LIKE 'version'";
        command.parametersCheck = false;
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        return reader.read() ? reader.getValue!string(1) : null;
    }

    override void setSSLSocketOptions()
    {
        super.setSSLSocketOptions();
        _sslSocket.dhp = myDH2048_p;
        _sslSocket.dhg = myDH2048_g;
        _sslSocket.ciphers = myCiphers;
    }

protected:
    MyProtocol _protocol;

private:
    DLinkDbBufferTypes.DLinkList _packageReadBuffers;
    DLinkDbBufferTypes.DLinkList _parameterWriteBuffers;
}

class MyConnectionStringBuilder : SkConnectionStringBuilder
{
@safe:

public:
    this(MyDatabase database) nothrow
    {
        super(database !is null ? database : myDB);
    }

    this(MyDatabase database, string connectionString)
    {
        super(database !is null ? database : myDB, connectionString);
    }

    final string integratedSecurityName() const nothrow
    {
        final switch (integratedSecurity) with (DbIntegratedSecurityConnection)
        {
            case legacy:
                return myAuthNativeName;
            case srp1:
                return myAuthScramSha1Name;
            case srp256:
                return myAuthSha2Caching; //myAuthScramSha256Name;
            case sspi:
                return myAuthSSPIName;
        }
    }

    final override const(string[]) parameterNames() const nothrow
    {
        return myValidConnectionParameterNames;
    }

    @property final bool allowUserVariables() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.myAllowUserVariables));
    }

    @property final typeof(this) allowUserVariables(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.myAllowUserVariables, setValue);
        return this;
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.my;
    }

protected:
    final override string getDefault(string name) const nothrow
    {
        auto k = name in myDefaultConnectionParameterValues;
        return k !is null && (*k).def.length != 0 ? (*k).def : super.getDefault(name);
    }

    final override void setDefaultIfs() nothrow
    {
        foreach (ref dpv; myDefaultConnectionParameterValues.byKeyValue)
        {
            auto def = dpv.value.def;
            if (def.length)
                putIf(dpv.key, def);
        }
        super.setDefaultIfs();
    }
}

class MyDatabase : DbDatabase
{
    import pham.utl.utl_convert : putNumber;

@safe:

public:
    this() nothrow
    {
        super();
        _name = DbIdentitier(DbScheme.my);
        _identifierQuoteChar = '`';
        _stringConcatOp = null;

        _charClasses['`'] = CharClass.idenfifierQuote;
        _charClasses['\''] = CharClass.stringQuote;
        _charClasses['"'] = CharClass.stringQuote;
        _charClasses['\\'] = CharClass.backslashSequence;

        //_charClasses['\u0022'] = CharClass.quote;
        //_charClasses['\u0027'] = CharClass.quote;
        //_charClasses['\u0060'] = CharClass.quote;
        //_charClasses['\u00b4'] = CharClass.quote;
        //_charClasses['\u02b9'] = CharClass.quote;
        //_charClasses['\u02ba'] = CharClass.quote;
        //_charClasses['\u02bb'] = CharClass.quote;
        //_charClasses['\u02bc'] = CharClass.quote;
        //_charClasses['\u02c8'] = CharClass.quote;
        //_charClasses['\u02ca'] = CharClass.quote;
        //_charClasses['\u02cb'] = CharClass.quote;
        //_charClasses['\u02d9'] = CharClass.quote;
        //_charClasses['\u0300'] = CharClass.quote;
        //_charClasses['\u0301'] = CharClass.quote;
        //_charClasses['\u2018'] = CharClass.quote;
        //_charClasses['\u2019'] = CharClass.quote;
        //_charClasses['\u201a'] = CharClass.quote;
        //_charClasses['\u2032'] = CharClass.quote;
        //_charClasses['\u2035'] = CharClass.quote;
        //_charClasses['\u275b'] = CharClass.quote;
        //_charClasses['\u275c'] = CharClass.quote;
        //_charClasses['\uff07'] = CharClass.quote;

        //_charClasses['\u005c'] = CharClass.backslash;
        //_charClasses['\u00a5'] = CharClass.backslash;
        //_charClasses['\u0160'] = CharClass.backslash;
        //_charClasses['\u20a9'] = CharClass.backslash;
        //_charClasses['\u2216'] = CharClass.backslash;
        //_charClasses['\ufe68'] = CharClass.backslash;
        //_charClasses['\uff3c'] = CharClass.backslash;

        populateValidParamNameChecks();
    }

    final override const(string[]) connectionStringParameterNames() const nothrow pure
    {
        return myValidConnectionParameterNames;
    }

    override DbColumn createColumn(DbCommand command, DbIdentitier name) nothrow
    in
    {
        assert((cast(MyCommand)command) !is null);
    }
    do
    {
        return new MyColumn(this, cast(MyCommand)command, name);
    }

    override DbColumnList createColumnList(DbCommand command) nothrow
    in
    {
        assert(cast(MyCommand)command !is null);
    }
    do
    {
        return new MyColumnList(this, cast(MyCommand)command);
    }

    override DbCommand createCommand(DbConnection connection,
        string name = null) nothrow
    in
    {
        assert((cast(MyConnection)connection) !is null);
    }
    do
    {
        return new MyCommand(this, cast(MyConnection)connection, name);
    }

    override DbCommand createCommand(DbConnection connection, DbTransaction transaction,
        string name = null) nothrow
    in
    {
        assert((cast(MyConnection)connection) !is null);
        assert((cast(MyTransaction)transaction) !is null);
    }
    do
    {
        return new MyCommand(this, cast(MyConnection)connection, cast(MyTransaction)transaction, name);
    }

    override DbConnection createConnection(string connectionString)
    {
        auto result = new MyConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbConnectionStringBuilder connectionString) nothrow
    in
    {
        assert(connectionString !is null);
        assert(connectionString.scheme == DbScheme.my);
        assert(cast(MyConnectionStringBuilder)connectionString !is null);
    }
    do
    {
        auto result = new MyConnection(this, cast(MyConnectionStringBuilder)connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbURL!string connectionString)
    in
    {
        assert(DbURL.scheme == DbScheme.my);
        assert(DbURL.isValid());
    }
    do
    {
        auto result = new MyConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnectionStringBuilder createConnectionStringBuilder() nothrow
    {
        return new MyConnectionStringBuilder(this);
    }

    override DbConnectionStringBuilder createConnectionStringBuilder(string connectionString)
    {
        return new MyConnectionStringBuilder(this, connectionString);
    }

    override DbParameter createParameter(DbCommand command, DbIdentitier name) nothrow
    {
        return new MyParameter(this, cast(MyCommand)command, name);
    }

    override DbParameterList createParameterList(DbCommand command = null) nothrow
    {
        return new MyParameterList(this, cast(MyCommand)command);
    }

    override DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel,
        bool defaultTransaction = false) nothrow
    in
    {
        assert((cast(MyConnection)connection) !is null);
    }
    do
    {
        return new MyTransaction(cast(MyConnection)connection, isolationLevel);
    }

    // https://dev.mysql.com/doc/refman/8.4/en/select.html
    // [LIMIT {[offset,] row_count | row_count OFFSET offset}]
    // The offset of the initial row is 0 (not 1)
    final override string limitClause(int32 rows, uint32 offset = 0) const nothrow pure @safe
    {
        // No restriction
        if (rows < 0)
            return null;

        // Returns empty
        if (rows == 0)
            return "LIMIT 0 OFFSET 0";

        auto buffer = Appender!string(40);
        return buffer.put("LIMIT ")
            .putNumber(rows)
            .put(" OFFSET ")
            .putNumber(offset)
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
        return false;
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.my;
    }

    @property final override string tableHint() const nothrow pure
    {
        return null;
    }
}

class MyParameter : DbParameter
{
public:
    this(MyDatabase database, MyCommand command, DbIdentitier name) nothrow @safe
    {
        super(database !is null ? database : myDB, command, name);
    }

    final override DbColumnIdType isValueIdType() const nothrow @safe
    {
        return MyColumnInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

protected:
    final override void reevaluateBaseType() nothrow @safe
    {
        foreach (ref myType; myNativeTypes)
        {
            if (myType.dbType == _type)
            {
                baseSize = myType.nativeSize;
                baseTypeId = myType.dbId;
                break;
            }
        }
    }
}

class MyParameterList : DbParameterList
{
public:
    this(MyDatabase database, MyCommand command = null) nothrow @safe
    {
        super(database !is null ? database : myDB, command);
    }

    @property final MyCommand myCommand() nothrow pure @safe
    {
        return cast(MyCommand)_command;
    }

protected:
    final override DbParameter createParameter(DbIdentitier name) nothrow @safe
    {
        return new MyParameter(database !is null ? cast(MyDatabase)database : myDB, myCommand, name);
    }
}

class MyStoredProcedureInfo : DbRoutineInfo
{
@safe:

public:
    this(MyDatabase database, string name) nothrow
    {
        super(database, name, DbRoutineType.storedProcedure);
    }

    @property final MyParameterList myArgumentTypes() nothrow
    {
        return cast(MyParameterList)_argumentTypes;
    }

    @property final MyParameter myReturnType() nothrow
    {
        return cast(MyParameter)_returnType;
    }
}

class MyTransaction : DbTransaction
{
public:
    this(MyConnection connection, DbIsolationLevel isolationLevel) nothrow @safe
    {
        super(connection, isolationLevel);
    }

    final override bool canSavePoint() @safe
    {
        enum minSupportVersion = VersionString("8.0");
        return super.canSavePoint() && VersionString(connection.serverVersion()) >= minSupportVersion;
    }

    @property final MyConnection myConnection() nothrow pure @safe
    {
        return cast(MyConnection)connection;
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
        final switch (isolationLevel) with (DbIsolationLevel)
        {
            case readUncommitted:
                return "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED";
            case readCommitted:
                return "SET TRANSACTION ISOLATION LEVEL READ COMMITTED";
            case repeatableRead:
                return "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ";
            case serializable:
                return "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE";
            case snapshot:
                return "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE";
        }
    }

    final override void doCommit(bool disposing) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(disposing=", disposing, ")");

        transactionCommand("COMMIT");
    }

    final override void doRollback(bool disposing) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(disposing=", disposing, ")");

        transactionCommand("ROLLBACK");
    }

    final override void doStart() @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        auto tmText = _transactionCommandText.length != 0
            ? _transactionCommandText
            : buildTransactionCommandText();

        transactionCommand(tmText);
        transactionCommand("BEGIN");
    }

    final void transactionCommand(string tmText) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(tmText=", tmText, ")");

        auto command = myConnection.createNonTransactionCommand();
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

__gshared MyDatabase _myDB;
shared static this() nothrow @trusted
{
    debug(debug_pham_db_db_mydatabase) debug writeln("shared static this(", __MODULE__, ")");

    _myDB = new MyDatabase();
    DbDatabaseList.registerDb(_myDB);
}

shared static ~this() nothrow
{
    _myDB = null;
}

pragma(inline, true)
@property MyDatabase myDB() nothrow @trusted
{
    return _myDB;
}

version(UnitTestMYDatabase)
{
    MyConnection createUnitTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        DbCompressConnection compress = DbCompressConnection.disabled)
    {
        import std.file : thisExePath;

        auto db = DbDatabaseList.getDb(DbScheme.my);
        assert(cast(MyDatabase)db !is null);

        auto result = db.createConnection("");
        assert(cast(MyConnection)result !is null);

        auto csb = (cast(MyConnection)result).myConnectionStringBuilder;
        csb.databaseName = "test";
        csb.userPassword = "masterkey";
        csb.receiveTimeout = dur!"seconds"(40);
        csb.sendTimeout = dur!"seconds"(20);
        csb.encrypt = encrypt;
        csb.compress = compress;
        csb.sslCa = "my_ca.pem";
        csb.sslCaDir = thisExePath();
        csb.sslCert = "my_client-cert.pem";
        csb.sslKey = "my_client-key.pem";

        assert(csb.serverName == "localhost");
        assert(csb.serverPort == 3_306);
        assert(csb.userName == "root");
        assert(csb.databaseName == "test");
        assert(csb.userPassword == "masterkey");
        assert(csb.receiveTimeout == dur!"seconds"(40));
        assert(csb.sendTimeout == dur!"seconds"(20));
        assert(csb.encrypt == encrypt);
        assert(csb.compress == compress);
        assert(csb.sslCa == "my_ca.pem");
        assert(csb.sslCaDir == thisExePath());
        assert(csb.sslCert == "my_client-cert.pem");
        assert(csb.sslKey == "my_client-key.pem");

        return cast(MyConnection)result;
    }

    string testStoredProcedureSchema() nothrow pure @safe
    {
        return q"{
CREATE PROCEDURE MULTIPLE_BY(IN X INTEGER, INOUT Y INTEGER, OUT Z DOUBLE)
BEGIN
  SET Y = X * 2;
  SET Z = Y * 2;
END
}";
    }

    string testTableSchema() nothrow pure @safe
    {
        return q"{
CREATE TABLE test_select (
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
  BLOB_FIELD LONGBLOB,
  TEXT_FIELD LONGTEXT,
  BIGINT_FIELD BIGINT)
}";
    }

    string testTableData() nothrow pure @safe
    {
        return q"{
INSERT INTO test_select (INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD, NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD, CHAR_FIELD, VARCHAR_FIELD, BIGINT_FIELD)
VALUES (1, 2, 3.10, 4.2, 5.4, 6.5, '2020-05-20', '01:01:01', '2020-05-20 07:31:00', 'ABC', 'XYZ', 4294967296)
}";
    }

    string simpleSelectCommandText() nothrow pure @safe
    {
        return q"{
SELECT INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD,
    NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD,
    CHAR_FIELD, VARCHAR_FIELD, BLOB_FIELD, TEXT_FIELD, BIGINT_FIELD
FROM test_select
WHERE INT_FIELD = 1
}";
    }

    string parameterSelectCommandText() nothrow pure @safe
    {
        return q"{
SELECT INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD,
	NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD,
	CHAR_FIELD, VARCHAR_FIELD, BLOB_FIELD, TEXT_FIELD, BIGINT_FIELD
FROM test_select
WHERE INT_FIELD = @INT_FIELD
	AND DOUBLE_FIELD = @DOUBLE_FIELD
	AND DECIMAL_FIELD = @DECIMAL_FIELD
	AND DATE_FIELD = @DATE_FIELD
	AND TIME_FIELD = @TIME_FIELD
	AND CHAR_FIELD = @CHAR_FIELD
	AND VARCHAR_FIELD = @VARCHAR_FIELD
}";
    }

    // Sample SQL to create user with special authenticated type
    // CREATE USER 'sha256user'@'localhost' IDENTIFIED WITH sha256_password BY 'password';

    // DbReader is a non-assignable struct so ref storage
    void validateSelectCommandTextReader(ref DbReader reader)
    {
        import std.math : isClose;

        assert(reader.hasRows());

        int count;
        while (reader.read())
        {
            count++;
            debug(debug_pham_db_db_mydatabase) debug writeln("unittest pham.db.mydatabase.MyCommand.DML.checking - count: ", count);

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
            assert(reader.getValue("DATE_FIELD") == DbDate(2020, 5, 20));

            assert(reader.getValue(7) == DbTime(1, 1, 1));
            assert(reader.getValue("TIME_FIELD") == DbTime(1, 1, 1));

            assert(reader.getValue(8) == DbDateTime(2020, 5, 20, 7, 31, 0));
            assert(reader.getValue("TIMESTAMP_FIELD") == DbDateTime(2020, 5, 20, 7, 31, 0));

            assert(reader.getValue(9) == "ABC");
            assert(reader.getValue("CHAR_FIELD") == "ABC");

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

    void validateSelectCommandTextReaderRange(ref DbReader reader)
    {
        import std.math : isClose;

        // Must not call hasRows to loading blob/clob columns' value
        int count;
        foreach (ref row; reader)
        {
            count++;
            debug(debug_pham_db_db_mydatabase) debug writeln("unittest pham.db.mydatabase.MyCommand.DML.checking - count: ", count);

            assert(row[0].value == 1);
            assert(row[1].value == 2);
            assert(isClose(row[2].value.get!float(), 3.10f));
            assert(isClose(row[3].value.get!double(), 4.20));
            assert(row[4].value.get!Decimal64() == Decimal64.money(5.4, 2));
            assert(row[5].value.get!Decimal64() == Decimal64.money(6.5, 2));
            assert(row[6].value == DbDate(2020, 5, 20));
            assert(row[7].value == DbTime(1, 1, 1));
            assert(row[8].value == DbDateTime(2020, 5, 20, 7, 31, 0));
            assert(row[9].value == "ABC");
            assert(row[10].value == "XYZ");
            assert(row[11].isNull);
            assert(row[12].value == "TEXT");
            assert(row[13].value == 4_294_967_296);
        }
        assert(count == 1);
    }
}

unittest // MyDatabase.limitClause
{
    assert(myDB.limitClause(-1, 1) == "");
    assert(myDB.limitClause(0, 1) == "LIMIT 0 OFFSET 0");
    assert(myDB.limitClause(2, 1) == "LIMIT 2 OFFSET 1");
    assert(myDB.limitClause(2) == "LIMIT 2 OFFSET 0");

    assert(myDB.topClause(-1) == "");
    assert(myDB.topClause(0) == "");
    assert(myDB.topClause(10) == "");
}

unittest // MyDatabase.concate
{
    assert(myDB.concate(["''", "''"]) == "concat('', '')");
    assert(myDB.concate(["abc", "'123'", "xyz"]) == "concat(abc, '123', xyz)");
}

unittest // MyDatabase.escapeIdentifier
{
    assert(myDB.escapeIdentifier("") == "");
    assert(myDB.escapeIdentifier("'\"\"'") == "'\"\"'");
    assert(myDB.escapeIdentifier("abc 123") == "abc 123");
    assert(myDB.escapeIdentifier("``abc 123`") == "````abc 123``");
}

unittest // MyDatabase.quoteIdentifier
{
    assert(myDB.quoteIdentifier("") == "``");
    assert(myDB.quoteIdentifier("'`'") == "`'``'`");
    assert(myDB.quoteIdentifier("abc 123") == "`abc 123`");
    assert(myDB.quoteIdentifier("`abc 123`") == "```abc 123```");
}

unittest // MyDatabase.escapeString
{
    assert(myDB.escapeString("") == "");
    assert(myDB.escapeString("\"''\"") == "\"\"''''\"\"");
    assert(myDB.escapeString("abc 123") == "abc 123");
    assert(myDB.escapeString("'abc 123'") == "''abc 123''");
}

unittest // MyDatabase.quoteString
{
    assert(myDB.quoteString("") == "''");
    assert(myDB.quoteString("\"''\"") == "'\"\"''''\"\"'");
    assert(myDB.quoteString("abc 123") == "'abc 123'");
    assert(myDB.quoteString("'abc 123'") == "'''abc 123'''");
}

version(UnitTestMYDatabase)
unittest // MyConnection
{
    import std.stdio : writeln; writeln("UnitTestMYDatabase.MyConnection"); // For first unittest

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version(UnitTestMYDatabase)
unittest // MyConnection.serverVersion
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    debug(debug_pham_db_db_mydatabase) debug writeln("MyConnection.serverVersion=", connection.serverVersion);
    assert(connection.serverVersion.length > 0);
}

version(UnitTestMYDatabase)
unittest // MyConnection(myAuthSha2Caching)
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    auto csb = connection.myConnectionStringBuilder;
    csb.userName = "caching_sha2_password";
    csb.userPassword = "masterkey";
    csb.integratedSecurity = DbIntegratedSecurityConnection.srp256;
    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);

    // Not matching with server to check for authentication change
    csb.integratedSecurity = DbIntegratedSecurityConnection.legacy;
    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version(UnitTestMYDatabase)
unittest // MyTransaction
{
    auto connection = createUnitTestConnection();
    scope (exit)
    {
        connection.dispose();
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
}

version(UnitTestMYDatabase)
unittest // MyTransaction.savePoint
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

version(UnitTestMYDatabase)
unittest // MyCommand.DDL
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

version(UnitTestMYDatabase)
unittest // MyCommand.DML - Simple select
{
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

    // Try again against range
    {
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();
        validateSelectCommandTextReaderRange(reader);
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

version(UnitTestMYDatabase)
unittest // MyCommand.DML - Parameter select
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
    command.parameters.add("CHAR_FIELD", DbType.stringFixed).value = "ABC";
    command.parameters.add("VARCHAR_FIELD", DbType.stringVary).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();
    validateSelectCommandTextReader(reader);
}

version(UnitTestMYDatabase)
unittest // MyCommand.DML.StoredProcedure
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    debug(debug_pham_db_db_mydatabase) debug writeln("Get information");
    {
        auto info = connection.getStoredProcedureInfo("MULTIPLE_BY");
        assert(info.argumentTypes.length == 3);
        assert(info.argumentTypes[0].name == "X");
        assert(info.argumentTypes[0].direction == DbParameterDirection.input);
        assert(info.argumentTypes[1].name == "Y");
        assert(info.argumentTypes[1].direction == DbParameterDirection.inputOutput);
        assert(info.argumentTypes[2].name == "Z");
        assert(info.argumentTypes[2].direction == DbParameterDirection.output);
    }

    debug(debug_pham_db_db_mydatabase) debug writeln("Without prepare");
    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.parametersCheck = false;
        command.commandStoredProcedure = "MULTIPLE_BY2";
        command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
        command.parameters.add("Y", DbType.float64, DbParameterDirection.output);
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
    }

    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.parametersCheck = false;
        command.commandStoredProcedure = "MULTIPLE_BY";
        command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
        command.parameters.add("Y", DbType.int32, DbParameterDirection.inputOutput).value = 100;
        command.parameters.add("Z", DbType.float64, DbParameterDirection.output);
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
        assert(command.parameters.get("Z").variant == 8.0);
    }

    debug(debug_pham_db_db_mydatabase) debug writeln("With prepare");
    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.parametersCheck = true;
        command.commandStoredProcedure = "MULTIPLE_BY2";
        command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
        command.parameters.add("Y", DbType.float64, DbParameterDirection.output);
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
    }

    {
        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.parametersCheck = true;
        command.commandStoredProcedure = "MULTIPLE_BY";
        command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
        command.parameters.add("Y", DbType.int32, DbParameterDirection.inputOutput).value = 100;
        command.parameters.add("Z", DbType.float64, DbParameterDirection.output);
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
        assert(command.parameters.get("Z").variant == 8.0);
    }
}

version(UnitTestMYDatabase)
unittest // MyCommand.DML.StoredProcedure & Parameter select
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandStoredProcedure = "MULTIPLE_BY";
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
    command.parameters.add("CHAR_FIELD", DbType.stringFixed).value = "ABC";
    command.parameters.add("VARCHAR_FIELD", DbType.stringVary).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();
    validateSelectCommandTextReader(reader);
}

version(UnitTestMYDatabase)
unittest // MyCommand.getExecutionPlan
{
    //import std.stdio : writeln;
    import std.string : indexOf;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();

    auto planDefault = command.getExecutionPlan(0);
    //writeln("planDefault=", planDefault);
    assert(planDefault.indexOf("actual time") > 0);
    assert(planDefault.indexOf("Table scan on") > 0);

    // JSON is not support
    //auto plan1 = command.getExecutionPlan(1);
    //writeln("plan1=", plan1);
}

version(UnitTestMYDatabase)
unittest // MyCommand.DML.Abort reader
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = "select * from foo limit 1000";

    {
        debug(debug_pham_db_db_mydatabase) debug writeln("Read some - Abort reader case");

        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;
            if (count == 10)
                break;
        }
        assert(count == 10);
    }

    {
        debug(debug_pham_db_db_mydatabase) debug writeln("Read all - Abort reader case");

        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        int count;
        assert(reader.hasRows());
        while (reader.read())
        {
            count++;
        }
        assert(count == 1000);
    }
}

version(UnitTestMYDatabase)
unittest // MyConnection(SSL)
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    auto csb = connection.myConnectionStringBuilder;
    csb.userName = "caching_sha2_password";
    csb.userPassword = "masterkey";
    csb.integratedSecurity = DbIntegratedSecurityConnection.srp256;
    csb.encrypt = DbEncryptedConnection.enabled;

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

unittest // DbDatabaseList.createConnection
{
    auto connection = DbDatabaseList.createConnection("mysql:server=myServerAddress;database=myDataBase;" ~
        "user=myUsername;password=myPassword;role=myRole;pooling=true;connectionTimeout=100seconds;encrypt=enabled;" ~
        "fetchRecordCount=50;integratedSecurity=legacy;");
    scope (exit)
        connection.dispose();
    auto connectionString = cast(MyConnectionStringBuilder)connection.connectionStringBuilder;

    assert(connection.scheme == DbScheme.my);
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
    auto connection = DbDatabaseList.createConnectionByURL("mysql://myUsername:myPassword@myServerAddress/myDataBase?" ~
        "role=myRole&pooling=true&connectionTimeout=100seconds&encrypt=enabled&" ~
        "fetchRecordCount=50&integratedSecurity=legacy");
    scope (exit)
        connection.dispose();
    auto connectionString = cast(MyConnectionStringBuilder)connection.connectionStringBuilder;

    assert(connection.scheme == DbScheme.my);
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

version(UnitTestMYDatabase)
unittest // MyConnection.DML.executeReader
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto reader1 = connection.executeReader(simpleSelectCommandText());
    validateSelectCommandTextReader(reader1);
    reader1.dispose();

    int rowCount = 0;
    auto reader2 = connection.executeQuery("SELECT TEXT_FIELD FROM TEST_SELECT WHERE INT_FIELD = ?", 1);
    while (reader2.read())
    {
        assert(reader2.getValue!string(0) == "TEXT");
        rowCount++;
    }
    reader2.dispose();
    assert(rowCount == 1);
}

version(UnitTestMYDatabase)
unittest // MyConnection.DML.executeScalar
{
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto INT_FIELD = connection.executeScalar(simpleSelectCommandText());
    assert(INT_FIELD.get!int() == 1); // First field

    auto TEXT_FIELD = connection.executeScalar("SELECT TEXT_FIELD FROM TEST_SELECT WHERE INT_FIELD = 1");
    assert(TEXT_FIELD.get!string() == "TEXT");

    TEXT_FIELD = connection.executeScalar("SELECT TEXT_FIELD FROM TEST_SELECT WHERE INT_FIELD = ?", 1);
    assert(TEXT_FIELD.get!string() == "TEXT");

    auto unassign = connection.executeScalar("SELECT TEXT_FIELD FROM TEST_SELECT WHERE 0=1");
    assert(unassign.isUnassign);
    assert(unassign.isNull);
}

version(UnitTestMYDatabase)
unittest // MyDatabase.currentTimeStamp...
{
    import core.thread : Thread;
    import core.time : dur;
    import pham.dtm.dtm_date : DateTime;

    void countZero(string s, uint expectedLength)
    {
        import std.format : format;

        //import std.stdio : writeln; debug writeln("s=", s, ", expectedLength=", expectedLength);

        assert(s.length == expectedLength, format("%s - %d", s, expectedLength));
    }

    // 2024-10-14 12:06:39
    // 2024-10-14 12:06:39.xxxxxx
    enum baseLength = "2024-10-14 12:06:39".length;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(0) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength);

    v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(1) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength+1+1);

    v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(2) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength+1+2);

    v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(3) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength+1+3);

    v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(4) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength+1+4);

    v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(5) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength+1+5);

    v = connection.executeScalar("SELECT cast(" ~ connection.database.currentTimeStamp(6) ~ " as CHAR)");
    countZero(v.value.toString(), baseLength+1+6);

    auto n = DateTime.now;
    Thread.sleep(dur!"msecs"(1));
    auto t = connection.currentTimeStamp(6);
    assert(t.value.get!DateTime() >= n, t.value.get!DateTime().toString("%s") ~ " vs " ~ n.toString("%s"));
}

version(UnitTestMYDatabase)
unittest // blob
{
    import std.conv : text;
    import std.string : representation;
    import pham.utl.utl_array_append : Appender;

    //import std.stdio : writeln; debug writeln(__FUNCTION__, " - create text blob");
    char[] textBlob = "1234567890qwertyuiop".dup;
    textBlob.reserve(200_000);
    while (textBlob.length < 200_000)
    {
        const len = textBlob.length;
        textBlob.length = len * 2;
        textBlob[len..$] = textBlob[0..len];
    }
    size_t loadLongText(Object, int64 loadedLength, size_t segmentLength, ref scope const(ubyte)[] data) nothrow @safe
    {
        assert(segmentLength != 0);

        if (loadedLength >= textBlob.length)
            return 0;

        const leftOverLength = textBlob.length - loadedLength;
        if (segmentLength > leftOverLength)
            segmentLength = cast(size_t)leftOverLength;

        data = cast(const(ubyte)[])textBlob[cast(size_t)loadedLength..cast(size_t)(loadedLength+segmentLength)];
        return segmentLength;
    }

    //import std.stdio : writeln; debug writeln(__FUNCTION__, " - create binary blob");
    ubyte[] binaryBlob = "asdfghjkl;1234567890".dup.representation;
    binaryBlob.reserve(300_000);
    while (binaryBlob.length < 300_000)
    {
        const len = binaryBlob.length;
        binaryBlob.length = len * 2;
        binaryBlob[len..$] = binaryBlob[0..len];
    }
    size_t loadLongBinary(Object, int64 loadedLength, size_t segmentLength, ref scope const(ubyte)[] data) nothrow @safe
    {
        assert(segmentLength != 0);

        if (loadedLength >= binaryBlob.length)
            return 0;

        const leftOverLength = binaryBlob.length - loadedLength;
        if (segmentLength > leftOverLength)
            segmentLength = cast(size_t)leftOverLength;

        data = binaryBlob[cast(size_t)loadedLength..cast(size_t)(loadedLength+segmentLength)];
        return segmentLength;
    }

    Appender!(ubyte[]) binaryBlob2;
    int saveLongBinary(Object sender, int64 savedLength, int64 blobLength, size_t row, scope const(ubyte)[] data)
    {
        if (blobLength > 0 && binaryBlob2.length == 0)
            binaryBlob2.reserve(cast(size_t)blobLength);
        binaryBlob2.put(data);
        return 0;
    }

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
       command.dispose();

    //import std.stdio : writeln; debug writeln(__FUNCTION__, " - create table");
    if (!connection.existTable("create_then_drop_blob"))
    {
        command.commandDDL = "CREATE TABLE create_then_drop_blob (txt LONGTEXT, bin LONGBLOB)";
        command.executeNonQuery();
    }
    scope (exit)
    {
        if (connection.isActive)
        {
            command.commandDDL = "DROP TABLE create_then_drop_blob";
            command.executeNonQuery();
        }
    }

    //import std.stdio : writeln; debug writeln(__FUNCTION__, " - insert blob");
    command.commandText = "INSERT INTO create_then_drop_blob(txt, bin) VALUES(@txt, @bin)";
    auto txt = command.parameters.add("txt", DbType.text);
    txt.loadLongData = &loadLongText;
    auto bin = command.parameters.add("bin", DbType.blob);
    bin.loadLongData = &loadLongBinary;
    const insertResult = command.executeNonQuery();
    assert(insertResult == 1);

    //import std.stdio : writeln; debug writeln(__FUNCTION__, " - select blob");
    void setSaveLongData(DbCommand command) @safe
    {
        auto binColumn = command.columns.get("bin");
        binColumn.saveLongData = &saveLongBinary;
    }
    command.commandText = "SELECT txt, bin FROM create_then_drop_blob LIMIT 1";
    command.columnCreatedEvents ~= &setSaveLongData;
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();

    //import std.stdio : writeln; debug writeln(__FUNCTION__, " - read blob");
    const rs = reader.read();
    assert(rs);
    const txtVal = reader.getValue("txt").get!string;
    assert(txtVal == textBlob, text("length: ", txtVal.length, " vs ", textBlob.length, " - txtVal.ptr=", cast(void*)txtVal.ptr));
    const binVal = reader.getValue("bin");
    assert(binVal.isNull);
    assert(binaryBlob2.data == binaryBlob, text("length: ", binaryBlob2.length, " vs ", binaryBlob.length));
}

version(UnitTestPerfMYDatabase)
{
    import pham.utl.utl_test : PerfTestResult;

    PerfTestResult unitTestPerfMYDatabase()
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
                    Foo14 = reader.getValue!Decimal128(13); //foo14 DECIMAL(18, 2) NOT NULL,
                    Foo15 = reader.getValue!Decimal128(14); //foo15 DECIMAL(18, 2) NOT NULL,
                    Foo16 = reader.getValue!int16(15); //foo16 SMALLINT NOT NULL,
                    Foo17 = reader.getValue!Decimal128(16); //foo17 DECIMAL(18, 2) NOT NULL,
                    Foo18 = reader.getValue!Decimal128(17); //foo18 DECIMAL(18, 2) NOT NULL,
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
                    Foo32 = reader.getValue!Decimal128(31); //foo32 DECIMAL(18, 2) NOT NULL,
                    Foo33 = reader.getValue!Decimal128(32); //foo33 DECIMAL(18, 2) NOT NULL
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

        version(UnitTestMYCollectData) auto datas = new Data[](maxRecordCount);
        else Data data;
        assert(reader.hasRows());

        auto result = PerfTestResult.create();
        while (result.count < maxRecordCount && reader.read())
        {
            version(UnitTestMYCollectData) datas[result.count++] = Data(reader);
            else { data.readData(reader); result.count++; }
        }
        result.end();
        assert(result.count > 0);
        return result;
    }
}

version(UnitTestPerfMYDatabase)
unittest // MyCommand.DML.Performance - https://github.com/FirebirdSQL/NETProvider/issues/953
{
    import std.format : format;
    import pham.db.db_debug;

    const perfResult = unitTestPerfMYDatabase();
    debug writeln("MY-Count: ", format!"%,3?d"('_', perfResult.count), ", Elapsed in msecs: ", format!"%,3?d"('_', perfResult.elapsedTimeMsecs()));
}

version(UnitTestMYDatabase)
unittest
{
    import std.stdio : writeln;
    writeln("UnitTestMYDatabase done");
}
