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

import std.array : Appender;
import std.conv : text, to;
import std.system : Endian;

debug(debug_pham_db_db_mydatabase) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.std.log.log_logger : Logger, LogLevel, LogTimming;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_enum_set;
import pham.utl.utl_object : VersionString;
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

class MyCommand : SkCommand
{
public:
    this(MyConnection connection, string name = null) nothrow @safe
    {
        super(connection, name);
    }

    this(MyConnection connection, MyTransaction transaction, string name = null) nothrow @safe
    {
        super(connection, transaction, name);
    }

    final override string getExecutionPlan(uint vendorMode) @safe
	{
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(vendorMode=", vendorMode, ")");

        if (auto log = canTraceLog())
            log.infof("%s.command.getExecutionPlan(vendorMode=%d)%s%s", forLogInfo(), vendorMode, newline, commandText);

        string explainFormat() nothrow @safe
        {
            switch (vendorMode)
            {
                case 0: return "";
                case 1: return "FORMAT = JSON ";
                case 2: return "FORMAT = TREE ";
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

        size_t lines = 0;
        Appender!string result;
        result.reserve(1_000);
        while (planReader.read())
        {
            if (lines)
                result.put('\n');
            result.put(planReader.getValue!string(0));
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
        return null;
    }

    final override DbValue writeBlob(DbNameColumn blobColumn, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe
    {
        return DbValue(null);
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

        if (!hasParameters && parametersCheck)
        {
            auto info = myConnection.getStoredProcedureInfo(storedProcedureName);
            if (info !is null)
            {
                auto localParameters = parameters;
                localParameters.reserve(info.argumentTypes.length);
                foreach (src; info.argumentTypes)
                    localParameters.addClone(src);
            }
        }

        Appender!string result;
        result.reserve(500);
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

        Appender!string outputNames;
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
            if (hasParameters)
            {
                foreach (param; parameters)
                    addPlaceHolder();
            }
            result.put(')');
        }
        else
        {
            outputNames.reserve(300);

            if (hasParameters)
            {
                foreach (param; parameters)
                {
                    addInputName(param.name);
                    if (param.isOutput(false))
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

        scope (exit)
            _handle.reset();

        try
        {
            auto protocol = myConnection.protocol;
            protocol.deallocateCommandWrite(this);
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.command.deallocateHandle() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
        }
    }

    final override void doExecuteCommand(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(type=", type, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doExecuteCommand()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        prepareExecuting(type);
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
    }

    final override bool doExecuteCommandNeedPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        static immutable inOutFlags = EnumSet!DbParameterDirection([DbParameterDirection.inputOutput]);

        // Need prepare for storedProcedure with inputOutput parameter(s)
        return super.doExecuteCommandNeedPrepare(type) || hasParameters(inOutFlags) || (!hasParameters && isStoredProcedure);
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
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doFetch()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = myConnection.protocol;
        const fetchRecordCountTemp = fetchRecordCount;
        uint continueFetchingCount = fetchRecordCountTemp >= 0 && fetchRecordCountTemp < 2
            ? 2
            : fetchRecordCountTemp;  // 2=record+eof package
        while (continueFetchingCount)
        {
            MyReader rowPackage;
            if (!protocol.readRow(rowPackage))
            {
                debug(debug_pham_db_db_mydatabase) debug writeln("\t", "allRowsFetched=true");
                allRowsFetched = true;
                break;
            }

            auto row = readRow(rowPackage, isScalar);
            _fetchedRows.enqueue(row);
            continueFetchingCount--;
        }
    }

    final override void doPrepare() @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");
        version(profile) debug auto p = PerfFunction.create();

        auto sql = executeCommandText(BuildCommandTextState.prepare);

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doPrepare()", newline, sql), false, logTimmingWarningDur)
            : LogTimming.init;

        auto protocol = myConnection.protocol;
        protocol.prepareCommandWrite(this, sql);
        auto response = protocol.prepareCommandRead(this);
        _handle = response.id;
        processPrepareResponse(response);
    }

    final override void doUnprepare() @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        purgePendingRows();

        if (_handle)
        {
            if (_handle.isDummy)
                _handle.reset();
            else
                deallocateHandle();
        }
    }

    static void fillNamedColumn(DbNameColumn column, const ref MyFieldInfo myField, const(bool) isNew) nothrow @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(myField=", myField.traceString(), ")");

        column.baseName = myField.useName();
        column.baseNumericDigits = cast(int16)myField.precision;
        column.baseNumericScale = myField.scale;
        column.baseSize = myField.columnLength;
        column.baseSubTypeId = myField.typeFlags;
        column.baseTableName = myField.useTableName();
        column.baseTypeId = myField.typeId;
        column.allowNull = myField.allowNull;

        if (isNew || column.type == DbType.unknown)
        {
            column.type = myField.dbType();
            column.size = myField.dbTypeSize();
        }

        auto f = cast(DbField)column;
        if (f !is null)
        {
            f.isKey = myField.isPrimaryKey;
            f.isUnique = myField.isUnique;
        }
    }

    final void processExecuteResponse(ref MyCommandResultResponse response, const(int) counter) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(response.okResponse.lastInsertId=", response.okResponse.lastInsertId,
            ", response.okResponse.affectedRows=", response.okResponse.affectedRows, ", response.fields.length=", response.fields.length, ")");

        if (counter == 1)
        {
            _lastInsertedId = response.okResponse.lastInsertId;
            _recordsAffected = response.okResponse.affectedRows;
        }

        if (response.fields.length != 0)
        {
            auto localFields = fields;

            if (prepared)
            {
                if (localFields.length != response.fields.length)
                    localFields.clear();
            }
            else
            {
                localFields.clear();
            }

            if (localFields.length == 0)
            {
                localFields.reserve(response.fields.length);
                foreach (ref myField; response.fields)
                {
                    auto newName = myField.useName;
                    auto newField = localFields.create(this, newName);
                    fillNamedColumn(newField, myField, true);
                    localFields.put(newField);
                }
            }
        }
    }

    final void processPrepareResponse(ref MyCommandPreparedResponse response) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "()");

        if (response.parameters.length != 0)
        {
            auto localParameters = parameters;
            localParameters.reserve(response.parameters.length);
            foreach (i, ref myParameter; response.parameters)
            {
                 if (i >= localParameters.length)
                {
                    auto newName = myParameter.useName;
                    if (localParameters.exist(newName))
                        newName = localParameters.generateName();
                    auto newParameter = localParameters.create(newName);
                    fillNamedColumn(newParameter, myParameter, true);
                    localParameters.put(newParameter);
                }
                else
                    fillNamedColumn(localParameters[i], myParameter, false);
            }
        }

        if (response.fields.length != 0)
        {
            const localIsStoredProcedure = isStoredProcedure;
            auto localParameters = localIsStoredProcedure ? parameters : null;
            if (localIsStoredProcedure)
                localParameters.reserve(response.fields.length);
            auto localFields = fields;
            localFields.reserve(response.fields.length);
            foreach (i, ref myField; response.fields)
            {
                auto newField = localFields.create(this, myField.useName);
                newField.isAlias = myField.isAlias;
                fillNamedColumn(newField, myField, true);
                localFields.put(newField);

                if (localIsStoredProcedure)
                {
                    auto foundParameter = localParameters.hasOutput(newField.name, i);
                    if (foundParameter is null)
                    {
                        auto newParameter = localParameters.create(newField.name);
                        newParameter.direction = DbParameterDirection.output;
                        fillNamedColumn(newParameter, myField, true);
                        localParameters.put(newParameter);
                    }
                    else
                    {
                        if (foundParameter.name.length == 0 && newField.name.length != 0)
                            foundParameter.updateEmptyName(newField.name);
                        fillNamedColumn(foundParameter, myField, false);
                    }
                }
            }
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
            if (auto log = canErrorLog())
                log.errorf("%s.command.purgePendingRows() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
        }
    }

    final DbRowValue readRow(ref MyReader rowPackage, const(bool) isScalar) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto protocol = myConnection.protocol;
        return protocol.readValues(rowPackage, this, cast(MyFieldList)fields);
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
        super(database);
    }

    this(MyDatabase database, string connectionString) @safe
    {
        super(database, connectionString);
    }

    this(MyDatabase database, MyConnectionStringBuilder connectionString) nothrow @safe
    {
        super(database, connectionString);
    }

    this(MyDatabase database, DbURL!string connectionString) @safe
    {
        super(database, connectionString);
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
        if (!isDisposing(lastDisposingReason))
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
        if (!isDisposing(lastDisposingReason))
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

    final override void doCancelCommand(DbCancelCommandData data) @safe
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

    final override void doClose(bool failedOpen) @safe
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(failedOpen=", failedOpen, ", socketActive=", socketActive, ")");

        scope (exit)
            disposeProtocol(DisposingReason.other);

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
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        super.doDispose(disposingReason);
        disposePackageReadBuffers(disposingReason);
        disposeProtocol(disposingReason);
    }

    final override void doOpen() @safe
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

    final override string getServerVersion() @safe
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

    final MyStoredProcedureInfo getStoredProcedureInfo(string storedProcedureName) @safe
    in
    {
        assert(storedProcedureName.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_mydatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ")");

        MyStoredProcedureInfo result;

        const cacheKey = DbDatabase.generateCacheKeyStoredProcedure(storedProcedureName, this.forCacheKey);
        if (database.cache.find!MyStoredProcedureInfo(cacheKey, result))
            return result;

        auto command = createNonTransactionCommand();
        scope (exit)
            command.dispose();

        command.parametersCheck = true;
        command.commandText = q"{
SELECT ORDINAL_POSITION, PARAMETER_NAME, DATA_TYPE, PARAMETER_MODE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.PARAMETERS
WHERE ROUTINE_TYPE = @ROUTINE_TYPE AND SPECIFIC_NAME = @SPECIFIC_NAME
ORDER BY ORDINAL_POSITION
}";
        command.parameters.add("ROUTINE_TYPE", DbType.stringVary).value = "PROCEDURE";
        command.parameters.add("SPECIFIC_NAME", DbType.stringVary).value = storedProcedureName;
        auto reader = command.executeReader();
        scope (exit)
            reader.dispose();

        if (reader.hasRows())
        {
            result = new MyStoredProcedureInfo(cast(MyDatabase)database, storedProcedureName);
            while (reader.read())
            {
                // pos=0 is a return type one
                const pos = reader.getValue!int64(0);
                const name = reader.getValue!string(1);
                const dataType = reader.getValue!string(2);
                const mode = reader.getValue!string(3);
                const size = reader.getValue!int64(4);
                const precision = reader.getValue!int32(5);
                const scale = reader.getValue!int64(6); // TODO why 64 bits

                const isParameter = pos > 0; // Position zero is a return type info
                const paramDirection = isParameter ? parameterModeToDirection(mode) : DbParameterDirection.returnValue;
                if (isParameter)
                {
                    auto p = result.argumentTypes.add(
                        name,
                        myParameterTypeToDbType(dataType, precision),
                        cast(int32)size,
                        paramDirection);

                    p.baseSize = cast(int32)size;
                    p.baseNumericDigits = cast(int16)precision;
                    p.baseNumericScale = cast(int16)scale;
                }
                else
                {
                    result.returnType.type = myParameterTypeToDbType(dataType, precision);
                    result.returnType.size = cast(int32)size;

                    result.returnType.baseSize = cast(int32)size;
                    result.returnType.baseNumericDigits = cast(int16)precision;
                    result.returnType.baseNumericScale = cast(int16)scale;
                }
            }
        }

        database.cache.addOrReplace(cacheKey, result);
        return result;
    }

    override void setSSLSocketOptions()
    {
        super.setSSLSocketOptions();
        _sslSocket.dhp = myDH2048_p;
        _sslSocket.dhg = myDH2048_g;
        _sslSocket.ciphers = myCiphers;
    }

public:
    MyFieldTypeMap fieldTypeMaps;

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
        super(database);
    }

    this(MyDatabase database, string connectionString)
    {
        super(database, connectionString);
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
@safe:

public:
    this() nothrow
    {
        super();
        this._name = DbIdentitier(DbScheme.my);
        this._identifierQuoteChar = '`';
        this._stringQuoteChar = '\'';

        this._charClasses['\u0022'] = CharClass.quote;
        this._charClasses['\u0027'] = CharClass.quote;
        this._charClasses['\u0060'] = CharClass.quote;
        this._charClasses['\u00b4'] = CharClass.quote;
        this._charClasses['\u02b9'] = CharClass.quote;
        this._charClasses['\u02ba'] = CharClass.quote;
        this._charClasses['\u02bb'] = CharClass.quote;
        this._charClasses['\u02bc'] = CharClass.quote;
        this._charClasses['\u02c8'] = CharClass.quote;
        this._charClasses['\u02ca'] = CharClass.quote;
        this._charClasses['\u02cb'] = CharClass.quote;
        this._charClasses['\u02d9'] = CharClass.quote;
        this._charClasses['\u0300'] = CharClass.quote;
        this._charClasses['\u0301'] = CharClass.quote;
        this._charClasses['\u2018'] = CharClass.quote;
        this._charClasses['\u2019'] = CharClass.quote;
        this._charClasses['\u201a'] = CharClass.quote;
        this._charClasses['\u2032'] = CharClass.quote;
        this._charClasses['\u2035'] = CharClass.quote;
        this._charClasses['\u275b'] = CharClass.quote;
        this._charClasses['\u275c'] = CharClass.quote;
        this._charClasses['\uff07'] = CharClass.quote;

        this._charClasses['\u005c'] = CharClass.backslash;
        this._charClasses['\u00a5'] = CharClass.backslash;
        this._charClasses['\u0160'] = CharClass.backslash;
        this._charClasses['\u20a9'] = CharClass.backslash;
        this._charClasses['\u2216'] = CharClass.backslash;
        this._charClasses['\ufe68'] = CharClass.backslash;
        this._charClasses['\uff3c'] = CharClass.backslash;

        this.populateValidParamNameChecks();
    }

    final override const(string[]) connectionStringParameterNames() const nothrow pure
    {
        return myValidConnectionParameterNames;
    }

    override DbCommand createCommand(DbConnection connection,
        string name = null) nothrow
    in
    {
        assert((cast(MyConnection)connection) !is null);
    }
    do
    {
        return new MyCommand(cast(MyConnection)connection, name);
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
        return new MyCommand(cast(MyConnection)connection, cast(MyTransaction)transaction, name);
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

    override DbField createField(DbCommand command, DbIdentitier name) nothrow
    in
    {
        assert((cast(MyCommand)command) !is null);
    }
    do
    {
        return new MyField(cast(MyCommand)command, name);
    }

    override DbFieldList createFieldList(DbCommand command) nothrow
    in
    {
        assert(cast(MyCommand)command !is null);
    }
    do
    {
        return new MyFieldList(cast(MyCommand)command);
    }

    override DbParameter createParameter(DbIdentitier name) nothrow
    {
        return new MyParameter(this, name);
    }

    override DbParameterList createParameterList() nothrow
    {
        return new MyParameterList(this);
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

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.my;
    }
}

class MyField : DbField
{
public:
    this(MyCommand command, DbIdentitier name) nothrow pure @safe
    {
        super(command, name);
    }

    final override DbField createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createField(cast(MyCommand)command, name)
            : new MyField(cast(MyCommand)command, name);
    }

    final override DbFieldIdType isValueIdType() const nothrow @safe
    {
        return MyFieldInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

    @property final MyCommand myCommand() nothrow pure @safe
    {
        return cast(MyCommand)_command;
    }
}

class MyFieldList: DbFieldList
{
public:
    this(MyCommand command) nothrow pure @safe
    {
        super(command);
    }

    final override DbField create(DbCommand command, DbIdentitier name) nothrow @safe
    {
        return database !is null
            ? database.createField(cast(MyCommand)command, name)
            : new MyField(cast(MyCommand)command, name);
    }

    @property final MyCommand myCommand() nothrow pure @safe
    {
        return cast(MyCommand)_command;
    }

protected:
    final override DbFieldList createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createFieldList(cast(MyCommand)command)
            : new MyFieldList(cast(MyCommand)command);
    }
}

class MyParameter : DbParameter
{
public:
    this(MyDatabase database, DbIdentitier name) nothrow pure @safe
    {
        super(database, name);
    }

    final override DbFieldIdType isValueIdType() const nothrow @safe
    {
        return MyFieldInfo.isValueIdType(baseTypeId, baseSubTypeId);
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
    this(MyDatabase database) nothrow pure @safe
    {
        super(database);
    }
}

class MyStoredProcedureInfo
{
public:
    this(MyDatabase database, string name) nothrow @safe
    {
        this._name = name;
        this._argumentTypes = new MyParameterList(database);
        this._returnType = new MyParameter(database, DbIdentitier(returnParameterName));
        this._returnType.direction = DbParameterDirection.returnValue;
    }

    @property final MyParameterList argumentTypes() nothrow @safe
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

    @property final MyParameter returnType() nothrow @safe
    {
        return _returnType;
    }

private:
    string _name;
    MyParameter _returnType;
    MyParameterList _argumentTypes;
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
    final string buildTransactionCommandText() nothrow @safe
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

shared static this() nothrow @safe
{
    auto db = new MyDatabase();
    DbDatabaseList.registerDb(db);
}

version(UnitTestMYDatabase)
{
    MyConnection createTestConnection(
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
        csb.receiveTimeout = dur!"seconds"(20);
        csb.sendTimeout = dur!"seconds"(10);
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
        assert(csb.receiveTimeout == dur!"seconds"(20));
        assert(csb.sendTimeout == dur!"seconds"(10));
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

        int count;
        assert(reader.hasRows());
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
}

version(UnitTestMYDatabase)
unittest // MyConnection
{
    import std.stdio : writeln; writeln("UnitTestMYDatabase.MyConnection"); // For first unittest
    
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    debug(debug_pham_db_db_mydatabase) debug writeln("MyConnection.serverVersion=", connection.serverVersion);
    assert(connection.serverVersion.length > 0);
}

version(UnitTestMYDatabase)
unittest // MyConnection(myAuthSha2Caching)
{
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();
    validateSelectCommandTextReader(reader);
}

version(UnitTestMYDatabase)
unittest // MyCommand.DML - Parameter select
{
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
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
unittest // MyCommand.DML.Abort reader
{
    auto connection = createTestConnection();
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
    auto connection = createTestConnection();
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

        auto connection = createTestConnection();
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

    const perfResult = unitTestPerfMYDatabase();
    dgWriteln("MY-Count: ", format!"%,3?d"('_', perfResult.count), ", Elapsed in msecs: ", format!"%,3?d"('_', perfResult.elapsedTimeMsecs()));
}

version(UnitTestMYDatabase)
unittest // MyConnection.DML.execute...
{
    auto connection = createTestConnection();
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

version(UnitTestMYDatabase)
unittest
{
    import std.stdio : writeln;
    writeln("UnitTestMYDatabase done");
}
