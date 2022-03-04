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

module pham.db.database;

import core.atomic : atomicLoad, atomicStore,  MemoryOrder;
import core.sync.mutex : Mutex;
public import core.time : Duration, dur;
import std.array : Appender;
public import std.ascii : newline;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.format : format;
import std.traits : FieldNameTuple;
import std.typecons : Flag, No, Yes;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.external.std.log.logger : Logger, LogLevel, LogTimming, ModuleLoggerOption, ModuleLoggerOptions;
import pham.utl.delegate_list;
import pham.utl.dlink_list;
import pham.utl.enum_set : EnumSet, toEnum, toName;
import pham.utl.object : currentComputerName, currentProcessId, currentProcessName, currentUserName,
    DisposableState, IDisposable, RAIIMutex, singleton;
import pham.utl.timer;
import pham.utl.utf8 : nextUTF8Char;
import pham.db.convert;
public import pham.db.exception;
import pham.db.message;
import pham.db.object;
import pham.db.parser;
public import pham.db.type;
import pham.db.util;
public import pham.db.value;

alias DbNotificationMessageEvent = void delegate(scope DbNotificationMessage[] notificationMessages);

abstract class DbCancelCommandData
{}

class DbCharset : DbObject
{
public:
    this(string name, string systemName, int id, ubyte bytesPerChar, bool caseSensitive) nothrow @safe
    {
        this._name = name;
        this._systemName = systemName;
        this._id = id;
        this._bytesPerChar = bytesPerChar;
        this._caseSensitive = caseSensitive;
    }

    @property ubyte bytesPerChar() const nothrow
    {
        return _bytesPerChar;
    }

    @property bool caseSensitive() const nothrow
    {
        return _caseSensitive;
    }

    @property int id() const nothrow
    {
        return _id;
    }

    @property string name() const nothrow
    {
        return _name;
    }

    @property string systemName() const nothrow
    {
        return _systemName;
    }

private:
    string _name;
    string _systemName;
    int _id;
    ubyte _bytesPerChar;
    bool _caseSensitive;
}

abstract class DbCommand : DbDisposableObject
{
public:
    this(DbConnection connection, string name = null) nothrow @safe
    {
        this._connection = connection;
        this._name = name;
        this._commandTimeout = connection.connectionStringBuilder.commandTimeout;
        this._fetchRecordCount = connection.connectionStringBuilder.fetchRecordCount;
        this.notifyMessage = connection.notifyMessage;
        this._flags.set(DbCommandFlag.parametersCheck, true);
        this._flags.set(DbCommandFlag.returnRecordsAffected, true);
    }

    this(DbConnection connection, DbTransaction transaction, string name = null) nothrow @safe
    {
        this(connection, name);
        this._transaction = transaction;
        this._flags.set(DbCommandFlag.implicitTransaction, false);
    }

    final typeof(this) cancel()
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_connection !is null)
            _connection.cancelCommand(this);

        return this;
    }

    final typeof(this) clearParameters() nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_parameters !is null)
            _parameters.clear();

        return this;
    }

    final DbRecordsAffected executeNonQuery() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        bool implicitTransactionCalled = false;
        bool unprepareCalled = false;
        checkCommand(-1);
        const wasPrepared = prepared;
        resetNewStatement(ResetStatementKind.execute);
        const implicitTransaction = setImplicitTransactionIf();
        scope (failure)
        {
            if (!implicitTransactionCalled && implicitTransaction)
                resetImplicitTransactionIf(cast(ResetImplicitTransactiontFlag)(ResetImplicitTransactiontFlag.error | ResetImplicitTransactiontFlag.nonQuery));
            if (!unprepareCalled && !wasPrepared && prepared)
                unprepare();
        }
        doExecuteCommand(DbCommandExecuteType.nonQuery);
        auto result = recordsAffected;
        if (implicitTransaction)
        {
            implicitTransactionCalled = true;
            resetImplicitTransactionIf(ResetImplicitTransactiontFlag.nonQuery);
        }
        if (!wasPrepared && prepared)
        {
            unprepareCalled = true;
            unprepare();
        }
        doNotifyMessage();
        return result;
    }

    final DbReader executeReader() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkCommand(DbCommandType.ddl);
        const wasPrepared = prepared;
        resetNewStatement(ResetStatementKind.execute);
        const implicitTransaction = setImplicitTransactionIf();
        scope (failure)
        {
            if (implicitTransaction)
                resetImplicitTransactionIf(ResetImplicitTransactiontFlag.error);
            if (!wasPrepared && prepared)
                unprepare();
        }
        doExecuteCommand(DbCommandExecuteType.reader);
        doNotifyMessage();

        connection._readerCounter++;
        _activeReader = true;
        return DbReader(this, implicitTransaction);
    }

    final DbValue executeScalar() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        bool implicitTransactionCalled = false;
        bool unprepareCalled = false;
        checkCommand(DbCommandType.ddl);
        const wasPrepared = prepared;
        resetNewStatement(ResetStatementKind.execute);
        const implicitTransaction = setImplicitTransactionIf();
        scope (failure)
        {
            if (!implicitTransaction && implicitTransaction)
                resetImplicitTransactionIf(ResetImplicitTransactiontFlag.error);
            if (!unprepareCalled && !wasPrepared && prepared)
                unprepare();
        }
        doExecuteCommand(DbCommandExecuteType.scalar);
        auto values = fetch(true);
        if (implicitTransaction)
        {
            implicitTransactionCalled = true;
            resetImplicitTransactionIf(ResetImplicitTransactiontFlag.none);
        }
        if (!wasPrepared && prepared)
        {
            unprepareCalled = true;
            unprepare();
        }
        doNotifyMessage();
        return values ? values[0] : DbValue.dbNull();
    }

    /**
     * Fetch and return a row for executed statement or stored procedure
     * Params:
     *  isScalar = When true, all fields must resolved to actual data (not its underline id)
     * Returns:
     *  A row being requested. Incase of no result left to be returned,
     *  a DbRowValue with zero column-length being returned.
     */
    abstract DbRowValue fetch(const(bool) isScalar) @safe;

    final string forLogInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    abstract const(char)[] getExecutionPlan(uint vendorMode = 0);

    final DbParameter[] inputParameters() nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        return hasParameters ? parameters.inputParameters() : null;
    }

    final typeof(this) prepare() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (prepared)
            return this;

        checkCommand(-1);
        resetNewStatement(ResetStatementKind.prepare);
        const implicitTransaction = setImplicitTransactionIf();
        scope (failure)
        {
            _commandState = DbCommandState.error;
            if (implicitTransaction)
                resetImplicitTransactionIf(ResetImplicitTransactiontFlag.error);
        }

        try
        {
            doPrepare();
            _commandState = DbCommandState.prepared;
            _flags.set(DbCommandFlag.prepared, true);
            doNotifyMessage();
        }
        catch (Exception e)
        {
            if (auto log = logger)
                log.error(forLogInfo(), newline, e.msg, newline, _executeCommandText, e);
            throw e;
        }

        return this;
    }

    abstract Variant readArray(DbNameColumn arrayColumn, DbValue arrayValueId) @safe;
    abstract ubyte[] readBlob(DbNameColumn blobColumn, DbValue blobValueId) @safe;

    final string readClob(DbNameColumn clobColumn, DbValue clobValueId) @trusted //@trusted=cast(string)
    {
        auto blob = readBlob(clobColumn, clobValueId);
        return blob.length != 0 ? cast(string)blob : null;
    }

    final typeof(this) unprepare() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkActiveReader();

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
        {
            resetNewStatement(ResetStatementKind.unprepare);

            _executeCommandText = null;
            _lastInsertedId.reset();
            _recordsAffected.reset();
            _baseCommandType = 0;
            _commandState = DbCommandState.unprepared;
            _flags.set(DbCommandFlag.prepared, false);
        }

        doUnprepare();

        return this;
    }

    abstract DbValue writeBlob(DbNameColumn blobColumn, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe;

    final DbValue writeClob(DbNameColumn clobColumn, scope const(char)[] clobValue,
        DbValue optionalClobValueId = DbValue.init) @safe
    {
        import std.string : representation;

        return writeBlob(clobColumn, clobValue.representation, optionalClobValueId);
    }

    @property final bool allRowsFetched() const nothrow @safe
    {
        return _flags.on(DbCommandFlag.allRowsFetched);
    }

    @property final int baseCommandType() const nothrow @safe
    {
        return _baseCommandType;
    }

    @property final DbCommandState commandState() const nothrow @safe
    {
        return _commandState;
    }

    @property final typeof(this) commandDDL(string value) @safe
    {
        checkActiveReader();

        return doCommandText(value, DbCommandType.ddl);
    }

    @property final typeof(this) commandStoredProcedure(string storedProcedureName) @safe
    {
        checkActiveReader();

        return doCommandText(storedProcedureName, DbCommandType.storedProcedure);
    }

    @property final typeof(this) commandTable(string tableName) @safe
    {
        checkActiveReader();

        return doCommandText(tableName, DbCommandType.table);
    }

    /** Gets or sets the sql statement of this DbCommand
        In case of commandType = storedProcedure, it should be a stored procedure name
        In case of commandType = table, it should be a table or view name
    */
    @property final string commandText() const nothrow @safe
    {
        return _commandText;
    }

    @property final typeof(this) commandText(string value) @safe
    {
        checkActiveReader();

        return doCommandText(value, DbCommandType.text);
    }

    /**
     * Gets or sets the time (minimum value based in seconds) to wait for executing
     * a command and generating an error if elapsed
     */
    @property final Duration commandTimeout() const nothrow @safe
    {
        return _commandTimeout;
    }

    @property final typeof(this) commandTimeout(Duration value) nothrow @safe
    {
        _commandTimeout = rangeDuration(value);
        return this;
    }

    /** Gets or sets how the commandText property is interpreted
    */
    @property final DbCommandType commandType() const nothrow pure @safe
    {
        return _commandType;
    }

    @property final typeof(this) commandType(DbCommandType value) nothrow pure @safe
    {
        _commandType = value;
        return this;
    }

    /** Gets DbConnection used by this DbCommand
    */
    @property final DbConnection connection() nothrow pure @safe
    {
        return _connection;
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _connection !is null ? _connection.database : null;
    }

    @property final uint executedCount() const nothrow pure @safe
    {
        return _executedCount;
    }

    @property final uint fetchRecordCount() const nothrow pure @safe
    {
        return _fetchRecordCount;
    }

    /**
     * Gets DbFieldList of this DbCommand
     */
    @property final DbFieldList fields() nothrow @safe
    {
        if (_fields is null)
            _fields = database.createFieldList(this);

        return _fields;
    }

    @property final DbHandle handle() const nothrow @safe
    {
        return _handle;
    }

    /**
     * Returns true if this DbCommand has atleast one DbSchemaColumn; otherwise returns false
     */
    @property final size_t hasFields() const nothrow pure @safe
    {
        return _fields !is null ? _fields.length : 0;
    }

    /**
     * Returns true if this DbCommand has atleast one DbParameter; otherwise returns false
     */
    @property final size_t hasParameters() nothrow pure @safe
    {
        return _parameters !is null ? _parameters.length : 0;
    }

    @property final size_t hasInputParameters() nothrow pure @safe
    {
        return _parameters !is null ? _parameters.inputCount() : 0;
    }

    @property final size_t hasOutputParameters() nothrow pure @safe
    {
        enum outputOnly = false;
        return _parameters !is null ? _parameters.outputCount(outputOnly) : 0;
    }

    @property final bool activeReader() const nothrow pure @safe
    {
        return _activeReader;
    }

    /**
     * Gets the inserted id after executed a commandText if applicable
     */
    @property final DbRecordsAffected lastInsertedId() const nothrow pure @safe
    {
        return _lastInsertedId;
    }

    @property final Logger logger() nothrow pure @safe
    {
        return _connection !is null ? _connection.logger : null;
    }

    /**
     * Returns name of this DbCommand if supplied
     */
    @property final string name() const nothrow @safe
    {
        return _name;
    }

    /**
     * Gets DbParameterList of this DbCommand
     */
    @property final DbParameterList parameters() nothrow @safe
    {
        if (_parameters is null)
            _parameters = database.createParameterList();

        return _parameters;
    }

    /**
     * Returns true if DbParameterList is needed to parse commandText for parameters.
     * Default value is true
     */
    @property final bool parametersCheck() const nothrow pure @safe
    {
        return _flags.on(DbCommandFlag.parametersCheck);
    }

    @property final typeof(this) parametersCheck(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.parametersCheck, value);
        return this;
    }

    /**
     * Returns true if DbParameterList is in prepared state
     */
    @property final bool prepared() const nothrow pure @safe
    {
        return _flags.on(DbCommandFlag.prepared);
    }

    /**
     * Gets number of records affected after executed a commandText if applicable
     */
    @property final DbRecordsAffected recordsAffected() const nothrow @safe
    {
        return _recordsAffected;
    }

    @property final bool returnRecordsAffected() const nothrow pure @safe
    {
        return _flags.on(DbCommandFlag.returnRecordsAffected);
    }

    @property final typeof(this) returnRecordsAffected(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.returnRecordsAffected, value);
        return this;
    }

    /**
     * Gets or sets DbTransaction used by this DbCommand
     */
    @property final DbTransaction transaction() nothrow pure @safe
    {
        return _transaction;
    }

    @property final typeof(this) transaction(DbTransaction value) @safe
    {
        checkActiveReader();
        if (value !is null)
            checkInactive();

        _transaction = value;
        _flags.set(DbCommandFlag.implicitTransaction, false);
        return this;
    }

    @property final bool transactionRequired() const nothrow pure @safe
    {
        return _flags.on(DbCommandFlag.transactionRequired);
    }

public:
    nothrow @safe DelegateList!(Object, DbNotificationMessage[]) notifyMessage;
    DbCustomAttributeList customAttributes;
    DbNotificationMessage[] notificationMessages;
    Duration logTimmingWarningDur = dur!"seconds"(10);

package(pham.db):
    @property final void allRowsFetched(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.allRowsFetched, value);
    }

    pragma(inline, true)
    @property final bool isStoredProcedure() const nothrow pure @safe
    {
        return commandType == DbCommandType.storedProcedure;
    }

    @property final void transactionRequired(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.transactionRequired, value);
    }

protected:
    enum BuildCommandTextState : byte
    {
        execute,
        executingPlan,
        prepare,
    }

    final string buildExecuteCommandText(const(BuildCommandTextState) state) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("state=", state);

        string result;
        final switch (commandType)
        {
            case DbCommandType.text:
                result = buildTextSql(commandText, state);
                break;
            case DbCommandType.storedProcedure:
                result = buildStoredProcedureSql(commandText, state);
                break;
            case DbCommandType.table:
                result = buildTableSql(commandText, state);
                break;
            case DbCommandType.ddl:
                result = buildTextSql(commandText, state);
                break;
        }

        if (auto log = logger)
            log.info(forLogInfo(), newline, result);

        return result;
    }

    final void buildParameterNameCallback(ref Appender!string result, string parameterName, uint32 ordinal) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("parameterName=", parameterName, ", ordinal=", ordinal);
        scope (failure) assert(0);

        // Construct sql
        result.put(buildParameterPlaceholder(parameterName, ordinal));

        // Create parameter
        DbParameter found;
        if (parameterName.length == 0)
            found = parameters.add(format(anonymousParameterNameFmt, ordinal), DbType.unknown);
        else if (!parameters.find(parameterName, found))
            found = parameters.add(parameterName, DbType.unknown);
        found.ordinal = ordinal;
    }

    string buildParameterPlaceholder(string parameterName, uint32 ordinal) nothrow @safe
    {
        return "?";
    }

    string buildStoredProcedureSql(string storedProcedureName, const(BuildCommandTextState) state) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("storedProcedureName=", storedProcedureName, ", state=", state);

        if (storedProcedureName.length == 0)
            return null;

        auto params = inputParameters();
        auto result = Appender!string();
        result.reserve(500);
        result.put("EXECUTE PROCEDURE ");
        result.put(storedProcedureName);
        result.put('(');
        foreach (i, param; params)
        {
            if (i)
                result.put(',');
			result.put(buildParameterPlaceholder(param.name, cast(uint32)(i + 1)));
        }
        result.put(')');

        version (TraceFunction) traceFunction!("pham.db.database")("storedProcedureName=", storedProcedureName, ", result=", result.data);

        return result.data;
    }

    string buildTableSql(string tableName, const(BuildCommandTextState) state) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("tableName=", tableName, ", state=", state);

        if (tableName.length == 0)
            return null;

        auto result = "SELECT * FROM " ~ tableName;

        version (TraceFunction) traceFunction!("pham.db.database")("tableName=", tableName, ", result=", result);

        return result;
    }

    string buildTextSql(string sql, const(BuildCommandTextState) state) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("sql=", sql, ", state=", state);

        if (sql.length == 0)
            return null;

        // Do not clear to allow parameters to be filled without calling prepare
        // clearParameters();

        auto result = parametersCheck && commandType != DbCommandType.ddl
            ? DbTokenizer!string.parseParameter(sql, &buildParameterNameCallback)
            : sql;

        version (TraceFunction) traceFunction!("pham.db.database")("result=", result);

        return result;
    }

    void checkActive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("callerName=", callerName);

        if (!handle)
        {
            auto msg = DbMessage.eInvalidCommandInactive.fmtMessage(callerName);
            throw new DbException(msg, DbErrorCode.connect, null);
        }

        if (_connection is null || _connection.state != DbConnectionState.open)
        {
            auto msg = DbMessage.eInvalidCommandConnection.fmtMessage(callerName);
            throw new DbException(msg, DbErrorCode.connect, null);
        }
    }

    final void checkActiveReader(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("callerName=", callerName);

        if (_activeReader)
            throw new DbException(DbMessage.eInvalidCommandActiveReader, 0, null);

        connection.checkActiveReader(callerName);
    }

    void checkCommand(int excludeCommandType, string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("callerName=", callerName);

        if (_connection is null || _connection.state != DbConnectionState.open)
            throw new DbException(DbMessage.eInvalidCommandConnection, DbErrorCode.connect, null);

        checkActiveReader(callerName);

        if (_transaction !is null && _transaction.state != DbTransactionState.active)
            transaction = null;

        if (_commandText.length == 0)
            throw new DbException(DbMessage.eInvalidCommandText, 0, null);

        if (excludeCommandType != -1 && _commandType == excludeCommandType)
        {
            auto msg = DbMessage.eInvalidCommandUnfit.fmtMessage(callerName);
            throw new DbException(msg, 0, null);
        }

        if (_transaction !is null && _transaction.connection !is _connection)
            throw new DbException(DbMessage.eInvalidCommandConnectionDif, 0, null);
    }

    final void checkInactive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("callerName=", callerName);

        if (handle)
        {
            auto msg = DbMessage.eInvalidCommandActive.fmtMessage(callerName);
            throw new DbException(msg, DbErrorCode.connect, null);
        }
    }

    typeof(this) doCommandText(string customText, DbCommandType type) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("type=", type, ", customText=", customText);

        if (prepared)
            unprepare();

        clearParameters();
        _executeCommandText = null;
        _commandText = customText;
        return commandType(type);
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_fields !is null)
        {
            version (none) _fields.disposal(disposing);
            _fields = null;
        }

        if (_parameters !is null)
        {
            version (none) _parameters.disposal(disposing);
            _parameters = null;
        }

        if (_transaction !is null)
        {
            _transaction = null;
        }

        if (_connection !is null)
        {
            _connection.removeCommand(this);
            _connection = null;
        }

        _commandState = DbCommandState.closed;
        _commandText = null;
        _executeCommandText = null;
        _baseCommandType = 0;
        _handle.reset();
    }

    final void doNotifyMessage() nothrow @trusted
    {
        if (notificationMessages.length == 0)
            return;

        if (notifyMessage)
        {
            try { notifyMessage(this, notificationMessages); } catch(Exception) {}
        }
        notificationMessages.length = 0;
    }

    final void mergeOutputParams(ref DbRowValue values) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        auto localParameters = parameters;
        size_t i;
        foreach (ref value; values[])
        {
            while (i < localParameters.length)
            {
                auto param = localParameters[i++];
                enum outputOnly = false;
                if (param.isOutput(outputOnly))
                {
                    param.value = value;
                    break;
                }
            }
            if (i >= localParameters.length)
                break;
        }
    }

    final bool needPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("type=", type);

        return !prepared
            && commandType != DbCommandType.table
            && (parametersCheck || hasParameters);
    }

    void prepareExecuting(const(DbCommandExecuteType) type) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("type=", type);

        _lastInsertedId.reset();
        _recordsAffected.reset();
        allRowsFetched(false);

        executeCommandText(BuildCommandTextState.execute); // Make sure _executeCommandText is initialized

        if (hasParameters)
            parameters.nullifyOutputParameters();
    }

    final void removeReader(ref DbReader value) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_activeReader && value.command is this)
        {
            connection._readerCounter--;
            _activeReader = false;
            removeReaderCompleted(value.implicitTransaction);
        }
    }

    void removeReaderCompleted(const(bool) implicitTransaction) nothrow @safe
    {
        if (implicitTransaction && disposingState != DisposableState.destructing)
        {
            try
            {
                resetImplicitTransactionIf(ResetImplicitTransactiontFlag.none);
            }
            catch (Exception e)
            {
                if (auto log = logger)
                    log.error(forLogInfo(), newline, e.msg, e);
            }
        }
    }

    enum ResetImplicitTransactiontFlag : byte
    {
        none = 0,
        error = 1,
        nonQuery = 2
    }

    final void resetImplicitTransactionIf(const(ResetImplicitTransactiontFlag) flags)  @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("flags=", flags);

        auto t = _transaction;

        const implicitTransaction = _flags.on(DbCommandFlag.implicitTransaction);
        if (implicitTransaction)
        {
            _flags.set(DbCommandFlag.implicitTransaction, false);
            _transaction = null;
        }

        bool commitOrRollback = false;
        if (_flags.on(DbCommandFlag.implicitTransactionStarted))
        {
            _flags.set(DbCommandFlag.implicitTransactionStarted, false);
            commitOrRollback = true;
        }

        // For case of executing last DML which need commit/rollback
        if (implicitTransaction && (flags & ResetImplicitTransactiontFlag.nonQuery)
            && t !is null && t.isRetaining)
            commitOrRollback = true;

        if (commitOrRollback && t !is null)
        {
            if ((flags & ResetImplicitTransactiontFlag.error))
                t.rollback();
            else
                t.commit();
        }
    }

    enum ResetStatementKind : byte
    {
        unprepare,
        prepare,
        execute
    }

    void resetNewStatement(const(ResetStatementKind) kind) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("kind=", kind);

        notificationMessages.length = 0;
        _flags.set(DbCommandFlag.cancelled, false);
        if (kind < ResetStatementKind.execute)
        {
            _executedCount = 0;
            if (_fields !is null)
                _fields.clear();
        }
        else
            _executedCount++;
    }

    void setOutputParameters(ref DbRowValue values)
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (values && hasParameters)
        {
            size_t i;
            foreach (parameter; parameters)
            {
                enum outputOnly = false;
                if (i < values.length && parameter.isOutput(outputOnly))
                    parameter.value = values[i++];
            }
        }
    }

    final bool setImplicitTransactionIf() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if ((_transaction is null || _transaction.state == DbTransactionState.disposed) && transactionRequired)
        {
            _transaction = connection.defaultTransaction();
            _flags.set(DbCommandFlag.implicitTransaction, true);

            if (_transaction.state == DbTransactionState.inactive)
            {
                _transaction.start();
                _flags.set(DbCommandFlag.implicitTransactionStarted, true);
            }

            return true;
        }
        else
            return false;
    }

    abstract void doExecuteCommand(const(DbCommandExecuteType) type) @safe;
    abstract void doPrepare() @safe;
    abstract void doUnprepare() @safe;

    bool isSelectCommandType() const nothrow @safe
    {
        return hasFields && !isStoredProcedure;
    }

    @property final string executeCommandText(const(BuildCommandTextState) state) @safe
    {
        if (_executeCommandText.length == 0)
            _executeCommandText = buildExecuteCommandText(state);
        return _executeCommandText;
    }

protected:
    DbConnection _connection;
    DbFieldList _fields;
    DbParameterList _parameters;
    DbTransaction _transaction;
    string _commandText, _executeCommandText;
    string _name;
    DbRecordsAffected _lastInsertedId;
    DbRecordsAffected _recordsAffected;
    DbHandle _handle;
    Duration _commandTimeout;
    uint _executedCount; // Number of execute calls after prepare
    uint _fetchRecordCount;
    int _baseCommandType;
    EnumSet!DbCommandFlag _flags;
    DbCommandState _commandState;
    DbCommandType _commandType;
    bool _activeReader;

private:
    DbCommand _next;
    DbCommand _prev;
}

mixin DLinkTypes!(DbCommand) DLinkDbCommandTypes;

abstract class DbConnection : DbDisposableObject
{
public:
    this(DbDatabase database) nothrow @safe
    {
        this._database = database;
        this._connectionStringBuilder = database.createConnectionStringBuilder(null);
    }

    this(DbDatabase database, string connectionString) nothrow @safe
    {
        this(database);
        if (connectionString.length != 0)
            setConnectionString(connectionString);
    }

    this(DbDatabase database, DbConnectionStringBuilder connectionStringBuilder) nothrow @safe
    in
    {
        assert(connectionStringBuilder !is null);
        assert(connectionStringBuilder.scheme == scheme);
    }
    do
    {
        this(database);
        this._connectionStringBuilder.assign(connectionStringBuilder);
    }

    final void cancelCommand(DbCommand command = null)
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkActive();
        auto data = createCancelCommandData(command);
        cancelCommand(command, data);
    }

    final void cancelCommand(DbCommand command, DbCancelCommandData data)
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkActive();
        notificationMessages.length = 0;
        if (command !is null)
            command._flags.set(DbCommandFlag.cancelled, true);
        doCancelCommand(data);
        doNotifyMessage();
    }

    final void close()
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        auto previousState = state;
        if (previousState != DbConnectionState.open)
            return;

        // Pool?
        if (list !is null && list.pool !is null)
        {
            list.pool.release(this);
            return;
        }

        scope (exit)
        {
            _handle.reset();
            _state = DbConnectionState.closed;
            doEndStateChange(previousState);
        }

        _state = DbConnectionState.closing;
        doBeginStateChange(DbConnectionState.closed);
        rollbackTransactions(false);
        disposeTransactions(false);
        disposeCommands(false);
        doClose(false);
    }

    final DLinkDbCommandTypes.DLinkRange commands()
    {
        return _commands[];
    }

    abstract DbCancelCommandData createCancelCommandData(DbCommand command = null);

    final DbCommand createCommand(string name = null) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkActive();
        return _commands.insertEnd(database.createCommand(this, name));
    }

    final DbTransaction createTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkActive();
        return createTransactionImpl(isolationLevel, false);
    }

    final DbTransaction defaultTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkActive();
        if (_defaultTransaction is null)
            _defaultTransaction = createTransactionImpl(isolationLevel, true);
        return _defaultTransaction;
    }

    final string forErrorInfo() const nothrow @safe
    {
        return _connectionStringBuilder.forErrorInfo();
    }

    final string forLogInfo() const nothrow @safe
    {
        return _connectionStringBuilder.forLogInfo();
    }

    final typeof(this) open()
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        auto previousState = state;
        if (previousState == DbConnectionState.open)
            return this;

        _state = DbConnectionState.opening;
        serverInfo.clear();
        notificationMessages.length = 0;
        doBeginStateChange(DbConnectionState.open);

        scope (failure)
        {
            _state = DbConnectionState.failing;
            doClose(true);

            _state = DbConnectionState.failed;
            doEndStateChange(previousState);
        }

        doOpen();
        _state = DbConnectionState.open;
        doEndStateChange(previousState);
        doNotifyMessage();

        return this;
    }

    final typeof(this) release() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        auto lst = _list;
        if (lst !is null)
        {
            auto pool = lst.pool;
            if (pool !is null)
                pool.release(this);
            else
                lst.release(this);
        }
        else
            dispose();

        return null;
    }

    final string serverVersion() @safe
    {
        if (auto e = DbServerIdentifier.dbVersion in serverInfo.values)
            return *e;
        else
            return serverInfo.put(DbServerIdentifier.dbVersion, getServerVersion());
    }

    final override size_t toHash() nothrow @safe
    {
        return connectionStringBuilder.toHash().hashOf(hashOf(scheme));
    }

    final DLinkDbTransactionTypes.DLinkRange transactions()
    {
        return _transactions[];
    }

    /**
     * Gets or sets the connection string used to establish the initial connection.
     */
    @property final string connectionString()
    {
        return connectionStringBuilder.connectionString;
    }

    @property final typeof(this) connectionString(string value)
    {
        if (connectionString != value)
        {
            checkInactive();
            setConnectionString(value);
        }
        return this;
    }

    @property final DbConnectionStringBuilder connectionStringBuilder() nothrow pure @safe
    {
        return _connectionStringBuilder;
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _database;
    }

    @property final DbHandle handle() const nothrow @safe
    {
        return _handle;
    }

    @property final DbTransaction lastTransaction(bool excludeDefaultTransaction) nothrow pure @safe
    {
        auto result = _transactions.first;
        while (result !is null)
        {
            if (!excludeDefaultTransaction || result !is _defaultTransaction)
                break;
            result = _transactions.next(result);
        }
        return result;
    }

    @property final DbConnectionList list() nothrow pure @safe
    {
        return _list;
    }

    /**
     * Returns true if this connection has any DbCommand
     */
    @property final bool hasCommands() const nothrow pure @safe
    {
        return !_commands.empty;
    }

    /**
     * Returns true if this connection has any DbTransaction
     */
    @property final bool hasTransactions() const nothrow pure @safe
    {
        return !_transactions.empty;
    }

	/**
     * Gets the indicator of current state of the connection
	 */
    @property final DbConnectionState state() const nothrow pure @safe
    {
        return _state;
    }

    @property abstract DbScheme scheme() const nothrow pure @safe;

    @property abstract bool supportMultiReaders() const nothrow pure @safe;

package(pham.db):
    final DbCommand createNonTransactionCommand() @safe
    {
        auto result = createCommand();
        result.parametersCheck = false;
        result.returnRecordsAffected = false;
        result.transactionRequired = false;
        return result;
    }

    final size_t nextCounter() nothrow @safe
    {
        return (++_nextCounter);
    }

protected:
    final void checkActive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("callerName=", callerName);

        if (state != DbConnectionState.open)
        {
            auto msg = DbMessage.eInvalidConnectionInactive.fmtMessage(callerName, connectionStringBuilder.forErrorInfo());
            throw new DbException(msg, DbErrorCode.connect, null);
        }
    }

    final void checkActiveReader(string callerName = __FUNCTION__) @safe
    {
        if (_readerCounter != 0 && !supportMultiReaders)
            throw new DbException(DbMessage.eInvalidConnectionActiveReader, 0, null);
    }

    final void checkInactive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("callerName=", callerName);

        if (state == DbConnectionState.open)
        {
            auto msg = DbMessage.eInvalidConnectionActive.fmtMessage(callerName, connectionStringBuilder.forErrorInfo());
            throw new DbException(msg, DbErrorCode.connect, null);
        }
    }

    final DbTransaction createTransactionImpl(DbIsolationLevel isolationLevel, bool defaultTransaction) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        auto result = database.createTransaction(this, isolationLevel, defaultTransaction);
        return _transactions.insertEnd(result);
    }

    void disposeCommands(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        while (!_commands.empty)
            _commands.remove(_commands.last).disposal(disposing);
    }

    void disposeTransactions(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        _defaultTransaction = null;
        while (!_transactions.empty)
            _transactions.remove(_transactions.last).disposal(disposing);
    }

    final void doBeginStateChange(DbConnectionState newState)
    {
        if (beginStateChange)
            beginStateChange(this, newState);
    }

    final void doEndStateChange(DbConnectionState oldState)
    {
        if (endStateChange)
            endStateChange(this, oldState);
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        beginStateChange.clear();
        endStateChange.clear();
        disposeTransactions(disposing);
        disposeCommands(disposing);
        serverInfo.clear();
        _list = null;
        _connectionStringBuilder = null;
        _database = null;
        _handle.reset();
        _state = DbConnectionState.closed;
    }

    final void doNotifyMessage() nothrow @trusted
    {
        if (notificationMessages.length == 0)
            return;

        if (notifyMessage)
        {
            try { notifyMessage(this, notificationMessages); } catch(Exception) {}
        }
        notificationMessages.length = 0;
    }

    void doPool(bool pooling) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (pooling)
        {
            disposeCommands(true);
            disposeTransactions(true);
        }
    }

    void removeCommand(DbCommand value) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (!disposingState)
        {
            if (value._prev !is null || value._next !is null)
                _commands.remove(value);
        }
    }

    void removeTransaction(DbTransaction value) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_defaultTransaction is value)
            _defaultTransaction = null;

        if (!disposingState)
        {
            if (value._prev !is null || value._next !is null)
                _transactions.remove(value);
        }
    }

    final void rollbackTransactions(bool disposing) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        foreach (t; _transactions[])
            t.rollback();
    }

    void setConnectionString(string value) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        connectionStringBuilder().parseConnectionString(value);
    }

    abstract void doCancelCommand(DbCancelCommandData data) @safe;
    abstract void doClose(bool failedOpen) @safe;
    abstract void doOpen() @safe;
    abstract string getServerVersion() @safe;

public:
    /**
     * Delegate to get notify when a state change
     * Occurs when the before state of the event changes
     * Params:
     *  newState = new state value
     */
    nothrow @safe DelegateList!(DbConnection, DbConnectionState) beginStateChange;

    /**
     * Delegate to get notify when a state change
     * Occurs when the after state of the event changes
     * Params:
     *  oldState = old state value
     */
    nothrow @safe DelegateList!(DbConnection, DbConnectionState) endStateChange;

    nothrow @safe DelegateList!(Object, DbNotificationMessage[]) notifyMessage;

    DbNotificationMessage[] notificationMessages;

    /**
     * Populate when connection is established
     */
    DbCustomAttributeList serverInfo;

    /**
     * For logging various message & trace
     */
    Logger logger;

protected:
    DbDatabase _database;
    DbConnectionList _list;
    DbTransaction _defaultTransaction;
    DateTime _inactiveTime;
    DbHandle _handle;
    size_t _nextCounter;
    int _readerCounter;
    DbConnectionState _state;

private:
    DLinkDbCommandTypes.DLinkList _commands;
    DbConnectionStringBuilder _connectionStringBuilder;
    DLinkDbTransactionTypes.DLinkList _transactions;

private:
    DbConnection _next;
    DbConnection _prev;
}

mixin DLinkTypes!(DbConnection) DLinkDbConnectionTypes;

class DbConnectionList : DbDisposableObject
{
public:
    this(DbDatabase database, string connectionString, DbConnectionPool pool) nothrow pure @safe
    {
        this._database = database;
        this._connectionString = connectionString;
        this._pool = pool;
    }

    final DLinkDbConnectionTypes.DLinkRange opIndex() nothrow @safe
    {
        return _connections[];
    }

    final DbConnection acquire(out bool created) @safe
    {
        created = _connections.empty;
        if (created)
        {
            auto result = database.createConnection(connectionString);
            result._list = this;
            return result;
        }
        else
        {
            auto result = _connections.remove(_connections.last);
            _length--;
            result.doPool(false);
            return result;
        }
    }

    final DbConnection release(DbConnection item) @safe
    in
    {
        assert(item !is null);
        assert(item.list is null || item.list is this);
    }
    do
    {
        if (item.list !is this)
        {
            if (item.list is null)
                return disposeConnection(item);
            else
            {
                auto lst = item.list;
                return lst.disposeConnection(item);
            }
        }

        try
        {
            item.doPool(true);
        }
        catch (Exception e)
        {
            disposeConnection(item);
            throw e; // rethrow
        }
        _connections.insertEnd(item);
        _length++;

        return null;
    }

    final DbConnection[] removeInactives(scope const(DateTime) now, scope const(Duration) maxInactiveTime) nothrow @safe
    {
        DbConnection[] result;
        result.reserve(length);
        // Iterate and get inactive connections
        foreach (connection; this)
        {
            const elapsed = now - connection._inactiveTime;
            if (elapsed > maxInactiveTime)
                result ~= connection;
        }
        // Detach from list
        foreach (removed; result)
        {
            _connections.remove(removed);
            removed._list = null;
            _length--;
        }
        return result;
    }

    @property final string connectionString() const nothrow pure @safe
    {
        return _connectionString;
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _database;
    }

    @property final size_t length() const nothrow @safe
    {
        return _length;
    }

    @property final DbConnectionPool pool() nothrow pure @safe
    {
        return _pool;
    }

protected:
    final DbConnection disposeConnection(DbConnection item) @safe
    in
    {
        assert(item !is null);
    }
    do
    {
        if (item.list !is null && item.list.pool !is null)
            item.list.pool._acquiredLength--;

        item._list = null;
        item.dispose();
        return null;
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        while (!_connections.empty)
            _connections.remove(_connections.last).disposal(disposing);
        _length = 0;
        _database = null;
        _pool = null;
    }

protected:
    string _connectionString;
    DLinkDbConnectionTypes.DLinkList _connections;
    DbDatabase _database;
    DbConnectionPool _pool;
    size_t _length;
}

class DbConnectionPool : DbDisposableObject
{
public:
    this(size_t maxLength = DbDefaultSize.connectionPoolLength,
         uint maxInactiveTimeInSeconds = DbDefaultSize.connectionPoolInactiveTime) nothrow pure @safe
    {
        this._maxLength = maxLength;
        this._maxInactiveTime = dur!"seconds"(maxInactiveTimeInSeconds);
    }

    final DbConnection acquire(DbScheme scheme, string connectionString) @safe
    {
        auto raiiMutex = () @trusted { return RAIIMutex(_poolMutex); }();
        const localMaxLength = maxLength;

        if (_acquiredLength >= localMaxLength)
        {
            auto msg = DbMessage.eInvalidConnectionPoolMaxUsed.fmtMessage(_acquiredLength, localMaxLength);
            throw new DbException(msg, DbErrorCode.connect, null);
        }

        auto database = DbDatabaseList.getDb(scheme);
        auto lst = schemeConnections(database, connectionString);
        bool created;
        auto result = lst.acquire(created);
        _acquiredLength++;
        if (!created)
            _length--;
        return result;
    }

    final DbConnection acquire(DbConnectionStringBuilder connectionStringBuilder) @safe
    {
        return acquire(connectionStringBuilder.scheme, connectionStringBuilder.connectionString);
    }

    static void cleanup() @trusted
    {
        if (_instance !is null)
        {
            _instance.dispose();
            _instance = null;
        }
    }

    final size_t cleanupInactives() @safe
    {
        auto inactives = removeInactives();
        foreach (inactive; inactives)
        {
            inactive.dispose();
        }
        return inactives.length;
    }

    static DbConnectionPool instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    final DbConnection release(DbConnection item) @safe
    in
    {
        assert(item !is null);
    }
    do
    {
        auto lst = item.list;

        // Not from pool?
        if (lst is null)
        {
            item.dispose();
            return null;
        }

        // Wrong pool?
        if (lst.pool !is this)
        {
            if (lst.pool is null)
                lst.disposeConnection(item);
            else
                lst.pool.release(item);
            return null;
        }

        auto raiiMutex = () @trusted { return RAIIMutex(_poolMutex); }();
        const localMaxLength = maxLength;

        // Over limit?
        if (_length + 1 >= localMaxLength)
        {
            lst.disposeConnection(item);
            return null;
        }

        item._inactiveTime = DateTime.utcNow;
        lst.release(item); // release can raise exception
        _acquiredLength--;
        _length++;

        return null;
    }

    @property final size_t acquiredLength() const nothrow @safe
    {
        return _acquiredLength;
    }

    @property final size_t length() const nothrow pure @safe
    {
        return _length;
    }

    @property final size_t maxLength() const nothrow pure @safe
    {
        return atomicLoad!(MemoryOrder.acq)(_maxLength);
    }

    @property final typeof(this) maxLength(size_t value) nothrow pure @safe
    {
        atomicStore!(MemoryOrder.rel)(_maxLength, cast(shared)value);
        return this;
    }

protected:
    static DbConnectionPool createInstance() nothrow pure @safe
    {
        return new DbConnectionPool();
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        scope (failure) assert(0);

        foreach (_, lst; _schemeConnections)
            lst.disposal(disposing);
        _schemeConnections = null;
        _acquiredLength = 0;
        _length = 0;
    }

    final void doTimer(TimerEvent event)
    {
        cleanupInactives();
    }

    final DbConnection[] removeInactives() @safe
    {
        auto raiiMutex = () @trusted { return RAIIMutex(_poolMutex); }();
        const now = DateTime.utcNow;
        DbConnection[] result;
        result.reserve(_length);
        foreach (_, lst; _schemeConnections)
        {
            auto inactives = lst.removeInactives(now, _maxInactiveTime);
            if (inactives.length)
            {
                _length -= inactives.length;
                result ~= inactives;
            }
        }
        return result;
    }

    final DbConnectionList schemeConnections(DbDatabase database, string connectionString) @safe
    {
        auto id = DbIdentitier(database.scheme ~ dbSchemeSeparator ~ connectionString);
        if (auto e = id in _schemeConnections)
            return (*e);
        else
        {
            auto result = new DbConnectionList(database, connectionString, this);
            _schemeConnections[id] = result;
            return result;
        }
    }

private:
    DbConnectionList[DbIdentitier] _schemeConnections;
    Duration _maxInactiveTime;
    size_t _acquiredLength, _length;
    shared size_t _maxLength;
    __gshared static DbConnectionPool _instance;
}

abstract class DbConnectionStringBuilder : DbNameValueList!string
{
public:
    this(string connectionString) nothrow @safe
    {
        setDefaultCustomAttributes();
        parseConnectionString(connectionString);
    }

    typeof(this) assign(DbConnectionStringBuilder source) nothrow @safe
    in
    {
        assert(source !is null);
        assert(source.scheme == scheme);
    }
    do
    {
        super.clear();

        this.forErrorInfoCustom = source.forErrorInfoCustom;
        this.forLogInfoCustom = source.forLogInfoCustom;
        this._elementSeparator = source._elementSeparator;
        this._valueSeparator = source._valueSeparator;

        foreach (n; source.sequenceNames)
        {
            auto p = n in source.lookupItems;
            this.put(p.name, p.value);
        }

        return this;
    }

    final string forErrorInfo() const nothrow @safe
    {
        return forErrorInfoCustom.length != 0 ? forErrorInfoCustom : serverName ~ ":" ~ databaseName;
    }

    final string forLogInfo() const nothrow @safe
    {
        return forLogInfoCustom.length != 0 ? forLogInfoCustom : serverName ~ ":" ~ databaseName;
    }

    final string getCustomValue(string name) nothrow @safe
    {
        if (name.length == 0 || !exist(name))
            return null;
        else
            return getString(name);
    }

    final bool isValidParameterName(string name) nothrow @safe
    {
        if (name.length == 0)
            return false;

        auto e = name in getValidParamNameChecks();
        return e !is null;
    }

    /**
     * Returns list of valid parameter names for connection string
     */
    abstract const(string[]) parameterNames() const nothrow @safe;

    typeof(this) parseConnectionString(string connectionString) nothrow @safe
    {
        //todo clear existing values?
        if (connectionString.length)
            this.setDelimiterText(connectionString, elementSeparator, valueSeparator);
        setDefaultIfs();

        return this;
    }

    /**
     * Allow to set custom parameter value without verfication based on database engine.
     * It is up to caller to supply value correctly
     * Returns:
     *  true if name is supported by database engine otherwise false
     */
    final bool setCustomValue(string name, string value) nothrow @safe
    {
        if (name.length != 0)
        {
            put(name, value);
            return isValidParameterName(name);
        }
        else
            return false;
    }

    final override size_t toHash() nothrow @safe
    {
        return this.connectionString.hashOf();
    }

    @property final bool allowBatch() const nothrow @safe
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.allowBatch));
    }

    @property final typeof(this) allowBatch(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.allowBatch, setValue);
        return this;
    }

    @property final string applicationName() const nothrow @safe
    {
        return customAttributes.get(DbConnectionCustomIdentifier.applicationName, null);
    }

    @property final typeof(this) applicationName(string value) nothrow
    {
        customAttributes.put(DbConnectionCustomIdentifier.applicationName, value);
        return this;
    }

    @property final string applicationVersion() const nothrow @safe
    {
        return customAttributes.get(DbConnectionCustomIdentifier.applicationVersion, null);
    }

    @property final typeof(this) applicationVersion(string value) nothrow
    {
        customAttributes.put(DbConnectionCustomIdentifier.applicationVersion, value);
        return this;
    }

    @property final string charset() const nothrow @safe
    {
        return getString(DbConnectionParameterIdentifier.charset);
    }

    @property final typeof(this) charset(string value) nothrow
    {
        if (value.length)
            put(DbConnectionParameterIdentifier.charset, value);
        return this;
    }

    /**
     * Gets or sets the time (value based in seconds) to wait for a command to be executed completely.
     * Set to zero to disable the setting.
     */
    @property final Duration commandTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbConnectionParameterIdentifier.commandTimeout));
    }

    @property final typeof(this) commandTimeout(scope const(Duration) value) nothrow
    {
        // Optional value
        const convertingSecond = value.toRangeSecond32();
        auto setValue = to!string(convertingSecond);
        put(DbConnectionParameterIdentifier.commandTimeout, setValue);
        return this;
    }

    @property final bool compress() const nothrow @safe
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.compress));
    }

    @property final typeof(this) compress(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.compress, setValue);
        return this;
    }

    /**
     *The connection string used to establish the initial connection.
     */
    @property final string connectionString() nothrow @safe
    {
        return getDelimiterText(this, elementSeparator, valueSeparator);
    }

    /**
     * Gets or sets the time (value based in seconds) to wait for a connection to open.
     * The default value is 10 seconds.
     */
    @property final Duration connectionTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbConnectionParameterIdentifier.connectionTimeout));
    }

    @property final typeof(this) connectionTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = value.toRangeSecond32();
        auto setValue = convertingSecond != 0 ? to!string(convertingSecond) : getDefault(DbConnectionParameterIdentifier.connectionTimeout);
        put(DbConnectionParameterIdentifier.connectionTimeout, setValue);
        return this;
    }

    /**
     * The name of the database; value of "database"
     */
    @property final DbIdentitier databaseName() const nothrow @safe
    {
        return DbIdentitier(getString(DbConnectionParameterIdentifier.database));
    }

    @property final typeof(this) databaseName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.database, value);
        return this;
    }

    /**
     * The file-name of the database; value of "databaseFile"
     */
    @property final string databaseFileName() const nothrow @safe
    {
        return getString(DbConnectionParameterIdentifier.databaseFile);
    }

    @property final typeof(this) databaseFileName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.databaseFile, value);
        return this;
    }

    @property final char elementSeparator() const nothrow @safe
    {
        return _elementSeparator;
    }

    @property final DbEncryptedConnection encrypt() const nothrow @safe
    {
        return toEnum!DbEncryptedConnection(getString(DbConnectionParameterIdentifier.encrypt));
    }

    @property final typeof(this) encrypt(DbEncryptedConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.encrypt, toName(value));
        return this;
    }

    /**
     * Gets or sets number of records of each fetch call.
     * Default value is 100
     */
    @property final uint32 fetchRecordCount() const nothrow @safe
    {
        return toInteger!uint32(getString(DbConnectionParameterIdentifier.fetchRecordCount));
    }

    @property final typeof(this) fetchRecordCount(uint32 value) nothrow
    {
        // Required value
        auto setValue = value != 0 ? to!string(value) : getDefault(DbConnectionParameterIdentifier.fetchRecordCount);
        put(DbConnectionParameterIdentifier.fetchRecordCount, setValue);
        return this;
    }

    @property final DbIntegratedSecurityConnection integratedSecurity() const nothrow @safe
    {
        return toEnum!DbIntegratedSecurityConnection(getString(DbConnectionParameterIdentifier.integratedSecurity));
    }

    @property final typeof(this) integratedSecurity(DbIntegratedSecurityConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.integratedSecurity, toName(value));
        return this;
    }

    @property final uint32 maxPoolCount() const nothrow @safe
    {
        return toInteger!uint32(getString(DbConnectionParameterIdentifier.maxPoolCount));
    }

    @property final typeof(this) maxPoolCount(uint32 value) nothrow
    {
        put(DbConnectionParameterIdentifier.maxPoolCount, to!string(value));
        return this;
    }

    @property final uint32 minPoolCount() const nothrow @safe
    {
        return toInteger!uint32(getString(DbConnectionParameterIdentifier.minPoolCount));
    }

    @property final typeof(this) minPoolCount(uint32 value) nothrow
    {
        put(DbConnectionParameterIdentifier.minPoolCount, to!string(value));
        return this;
    }

    @property final uint32 packageSize() const nothrow @safe
    {
        return toInteger!uint32(getString(DbConnectionParameterIdentifier.packageSize));
    }

    @property final typeof(this) packageSize(uint32 value) nothrow
    {
        // Required value
        auto setValue = value != 0 ? to!string(value) : getDefault(DbConnectionParameterIdentifier.packageSize);
        put(DbConnectionParameterIdentifier.packageSize, setValue);
        return this;
    }

    @property final bool pooling() const nothrow @safe
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.pooling));
    }

    @property final typeof(this) pooling(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.pooling, setValue);
        return this;
    }

    @property final Duration poolTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbConnectionParameterIdentifier.poolTimeout));
    }

    @property final typeof(this) poolTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = value.toRangeSecond32();
        auto setValue = convertingSecond != 0 ? to!string(convertingSecond) : getDefault(DbConnectionParameterIdentifier.poolTimeout);
        put(DbConnectionParameterIdentifier.poolTimeout, setValue);
        return this;
    }

    @property final uint16 port() const nothrow @safe
    {
        return toInteger!uint16(getString(DbConnectionParameterIdentifier.port));
    }

    @property final typeof(this) port(uint16 value) nothrow
    {
        auto setValue = value != 0 ? to!string(value) : getDefault(DbConnectionParameterIdentifier.port);
        put(DbConnectionParameterIdentifier.port, setValue);
        return this;
    }

    /**
     * Gets or sets the time (value based in seconds) to wait for a server to send back request's result.
     * The default value is 3_600 seconds (1 hour).
     * Set to zero to disable the setting.
     */
    @property final Duration receiveTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbConnectionParameterIdentifier.receiveTimeout));
    }

    @property final typeof(this) receiveTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = value.toRangeSecond32();
        auto setValue = convertingSecond != 0 ? to!string(convertingSecond) : getDefault(DbConnectionParameterIdentifier.receiveTimeout);
        put(DbConnectionParameterIdentifier.receiveTimeout, setValue);
        return this;
    }

    @property final DbIdentitier roleName() const nothrow @safe
    {
        return DbIdentitier(getString(DbConnectionParameterIdentifier.roleName));
    }

    @property final typeof(this) roleName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.roleName, value);
        return this;
    }

    @property abstract DbScheme scheme() const nothrow pure @safe;

    /**
     * Gets or sets the time (value based in seconds) to wait for a request to completely send to server.
     * The default value is 60 seconds.
     * Set to zero to disable the setting.
     */
    @property final Duration sendTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbConnectionParameterIdentifier.sendTimeout));
    }

    @property final typeof(this) sendTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = value.toRangeSecond32();
        auto setValue = convertingSecond != 0 ? to!string(convertingSecond) : getDefault(DbConnectionParameterIdentifier.sendTimeout);
        put(DbConnectionParameterIdentifier.sendTimeout, setValue);
        return this;
    }

    /**
     * The name of the database server; value of "server"
     */
    @property final DbIdentitier serverName() const nothrow @safe
    {
        return DbIdentitier(getString(DbConnectionParameterIdentifier.server));
    }

    @property final typeof(this) serverName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.server, value);
        return this;
    }

    /**
     * Returns value of "user"
     */
    @property final DbIdentitier userName() const nothrow @safe
    {
        return DbIdentitier(getString(DbConnectionParameterIdentifier.userName));
    }

    @property final typeof(this) userName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.userName, value);
        return this;
    }

    /**
     * Returns value of "password"
     */
    @property final string userPassword() const nothrow @safe
    {
        return getString(DbConnectionParameterIdentifier.userPassword);
    }

    @property final typeof(this) userPassword(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.userPassword, value);
        return this;
    }

    @property final char valueSeparator() const nothrow @safe
    {
        return _valueSeparator;
    }

protected:
    string getDefault(string name) const nothrow @safe
    {
        auto n = DbIdentitier(name);
        return assumeWontThrow(dbDefaultParameterValues.get(n, null));
    }

    final string getString(string name) const nothrow @safe
    {
        string result;
        if (find(name, result))
            return result;
        else
            return getDefault(name);
    }

    final bool[string] getValidParamNameChecks() nothrow @trusted // @trusted=rehash();
    {
        if (_validParamNameChecks.length == 0)
        {
            foreach (n; parameterNames())
                _validParamNameChecks[n] = true;
            _validParamNameChecks.rehash();
        }
        return _validParamNameChecks;
    }

    final void setDefaultCustomAttributes() nothrow @safe
    {
        customAttributes.put(DbConnectionCustomIdentifier.currentComputerName, currentComputerName());
        customAttributes.put(DbConnectionCustomIdentifier.currentProcessId, to!string(currentProcessId()));
        customAttributes.put(DbConnectionCustomIdentifier.currentProcessName, currentProcessName());
        customAttributes.put(DbConnectionCustomIdentifier.currentUserName, currentUserName());
    }

    void setDefaultIfs() nothrow @safe
    {
        putIf(DbConnectionParameterIdentifier.connectionTimeout, getDefault(DbConnectionParameterIdentifier.connectionTimeout));
        putIf(DbConnectionParameterIdentifier.encrypt, getDefault(DbConnectionParameterIdentifier.encrypt));
        putIf(DbConnectionParameterIdentifier.fetchRecordCount, getDefault(DbConnectionParameterIdentifier.fetchRecordCount));
        putIf(DbConnectionParameterIdentifier.maxPoolCount, getDefault(DbConnectionParameterIdentifier.maxPoolCount));
        putIf(DbConnectionParameterIdentifier.minPoolCount, getDefault(DbConnectionParameterIdentifier.minPoolCount));
        putIf(DbConnectionParameterIdentifier.packageSize, getDefault(DbConnectionParameterIdentifier.packageSize));
        putIf(DbConnectionParameterIdentifier.poolTimeout, getDefault(DbConnectionParameterIdentifier.poolTimeout));
        putIf(DbConnectionParameterIdentifier.receiveTimeout, getDefault(DbConnectionParameterIdentifier.receiveTimeout));
        putIf(DbConnectionParameterIdentifier.sendTimeout, getDefault(DbConnectionParameterIdentifier.sendTimeout));
        putIf(DbConnectionParameterIdentifier.pooling, getDefault(DbConnectionParameterIdentifier.pooling));
        //putIf(, getDefault());
    }

public:
    DbCustomAttributeList customAttributes;
    string forErrorInfoCustom;
    string forLogInfoCustom;

protected:
    char _elementSeparator = ';';
    char _valueSeparator = '=';

private:
    bool[string] _validParamNameChecks;
}

abstract class DbDatabase : DbNameObject
{
@safe:

public:
    enum CharClass : byte
    {
        any,
        quote,
        backslash,
    }

public:
    abstract DbCommand createCommand(DbConnection connection, string name = null) nothrow;
    abstract DbCommand createCommand(DbConnection connection, DbTransaction transaction, string name = null) nothrow;
    abstract DbConnection createConnection(string connectionString) nothrow;
    abstract DbConnection createConnection(DbConnectionStringBuilder connectionStringBuilder) nothrow;
    abstract DbConnectionStringBuilder createConnectionStringBuilder(string connectionString) nothrow;
    abstract DbField createField(DbCommand command, DbIdentitier name) nothrow;
    abstract DbFieldList createFieldList(DbCommand command) nothrow;
    abstract DbParameter createParameter(DbIdentitier name) nothrow;
    abstract DbParameterList createParameterList() nothrow;
    abstract DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel, bool defaultTransaction) nothrow;

    final DbField createField(DbCommand command, string name) nothrow
    {
        DbIdentitier id = DbIdentitier(name);
        return createField(command, id);
    }

    final DbParameter createParameter(string name) nothrow
    {
        DbIdentitier id = DbIdentitier(name);
        return createParameter(id);
    }

    final CharClass charClass(const(dchar) c) const @nogc nothrow pure
    {
        if (auto e = c in charClasses)
            return *e;
        else
            return CharClass.any;
    }

    final const(char)[] escapeIdentifier(return const(char)[] value) pure
    {
        if (value.length == 0)
            return value;

        size_t p, lastP, cCount;

        // Find the first quote char
        while (p < value.length)
        {
            const c = nextUTF8Char(value, p, cCount);
            if (charClass(c) != CharClass.any)
                break;
            lastP = p;
        }

        // No quote char found?
        if (lastP >= value.length)
            return value;

        auto result = Appender!string();
        result.reserve(value.length + 100);
        if (lastP)
            result.put(value[0..lastP]);
        p = lastP;
        while (p < value.length)
        {
            const c = nextUTF8Char(value, p, cCount);
            const cc = charClass(c);
            if (cc == CharClass.quote)
                result.put(c);
            else if (cc == CharClass.backslash)
                result.put('\\');
            result.put(c);
        }
        return result.data;
    }

    final const(char)[] escapeString(return const(char)[] value) pure
    {
        if (value.length == 0)
            return value;

        size_t p, lastP, cCount;

        // Find the first quote char
        while (p < value.length)
        {
            const c = nextUTF8Char(value, p, cCount);
            if (charClass(c) != CharClass.any)
                break;
            lastP = p;
        }

        // No quote char found?
        if (lastP >= value.length)
            return value;

        auto result = Appender!string();
        result.reserve(value.length + 100);
        if (lastP)
            result.put(value[0..lastP]);
        p = lastP;
        while (p < value.length)
        {
            const c = nextUTF8Char(value, p, cCount);
            if (charClass(c) != CharClass.any)
                result.put('\\');
            result.put(c);
        }
        return result.data;
    }

    final const(char)[] quoteIdentifier(scope const(char)[] value) pure
    {
        return identifierQuoteChar ~ escapeIdentifier(value) ~ identifierQuoteChar;
    }

    final const(char)[] quoteString(scope const(char)[] value) pure
    {
        return stringQuoteChar ~ escapeString(value) ~ stringQuoteChar;
    }

    /**
     * For logging various message & trace
     * Central place to assign to newly created DbConnection
     */
    @property final Logger logger() nothrow pure @trusted //@trusted=cast()
    {
        import core.atomic : atomicLoad,  MemoryOrder;

        return cast(Logger)atomicLoad!(MemoryOrder.acq)(_logger);
    }

    @property final DbDatabase logger(Logger logger) nothrow pure @trusted //@trusted=cast()
    {
        import core.atomic : atomicStore,  MemoryOrder;

        atomicStore!(MemoryOrder.rel)(_logger, cast(shared)logger);
        return this;
    }

    /**
     * Name of database kind, firebird, postgresql ...
     * Refer pham.db.type.DbScheme for a list of possible values
     */
    @property abstract DbScheme scheme() const nothrow pure;

    pragma(inline, true)
    @property final char identifierQuoteChar() const @nogc nothrow pure
    {
        return _identifierQuoteChar;
    }

    pragma(inline, true)
    @property final char stringQuoteChar() const @nogc nothrow pure
    {
        return _stringQuoteChar;
    }

protected:
    CharClass[dchar] charClasses;
    char _identifierQuoteChar;
    char _stringQuoteChar;

private:
    shared Logger _logger;
}

// This instance is initialize at startup hence no need Mutex to have thread-guard
class DbDatabaseList : DbNameObjectList!DbDatabase
{
public:
    /**
     * Search the leading scheme value for matching existing database
     * If found, will create and return instance of its' corresponding ...Connection
     * and null otherwise
     */
    static DbConnection createConnection(string connectionString) nothrow @safe
    {
        import std.string : indexOf;

        const i = connectionString.indexOf(dbSchemeSeparator);
        if (i <= 0)
            return null;

        DbDatabase database;
        if (findDb(connectionString[0..i - 1], database))
            return database.createConnection(connectionString[i + 1..$]);
        else
            return null;
    }

    static DbConnection createConnection(DbConnectionStringBuilder connectionStringBuilder) nothrow @safe
    {
        DbDatabase database;
        if (findDb(connectionStringBuilder.scheme, database))
            return database.createConnection(connectionStringBuilder);
        else
            return null;
    }

    static bool findDb(DbScheme scheme, ref DbDatabase database) nothrow @safe
    {
        auto lst = instance();
        return lst.find(scheme, database);
    }

    static DbDatabase getDb(DbScheme scheme) @safe
    {
        DbDatabase result;
        if (findDb(scheme, result))
            return result;

        auto msg = DbMessage.eInvalidSchemeName.fmtMessage(scheme);
        throw new DbException(msg, 0, null);
    }

    static DbDatabaseList instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    static void registerDb(DbDatabase database) nothrow @safe
    in
    {
        assert(database !is null);
        assert(database.name.length != 0);
        assert(database.scheme.length != 0);
    }
    do
    {
        instance().put(database);
    }

    static void cleanup() @trusted
    {
        if (_instance !is null)
        {
            _instance.clear();
            _instance = null;
        }
    }

protected:
    static DbDatabaseList createInstance() nothrow pure @safe
    {
        return new DbDatabaseList();
    }

private:
    __gshared static DbDatabaseList _instance;
}

class DbNameColumn : DbNameObject
{
public:
    /*
     * Indicates if field value is an external resource id which needs special loading/saving
     */
    abstract DbFieldIdType isValueIdType() const nothrow pure @safe;

    version (TraceFunction)
    string traceString() const nothrow @trusted
    {
        import std.conv : to;

        return "type=" ~ toName!DbType(type)
             ~ ", baseTypeId=" ~ to!string(baseTypeId)
             ~ ", baseSubtypeId=" ~ to!string(baseSubTypeId)
             ~ ", baseSize=" ~ to!string(baseSize)
             ~ ", baseNumericScale=" ~ to!string(baseNumericScale);
    }

    /**
     * Gets or sets whether value NULL is allowed
     */
    @property final bool allowNull() const nothrow pure @safe
    {
        return _flags.on(DbSchemaColumnFlag.allowNull);
    }

    @property final typeof(this) allowNull(bool value) nothrow pure @safe
    {
        _flags.set(DbSchemaColumnFlag.allowNull, value);
        return this;
    }

    /**
     * Gets or sets the id of the column in the schema table
     */
    @property final int32 baseId() const nothrow pure @safe
    {
        return _baseId;
    }

    @property final typeof(this) baseId(int32 value) nothrow pure @safe
    {
        _baseId = value;
        return this;
    }

    /**
     * Gets or sets the name of the column in the schema table
     */
    @property final string baseName() const nothrow pure @safe
    {
        return _baseName.length != 0 ? _baseName : name;
    }

    @property final typeof(this) baseName(string value) nothrow pure @safe
    {
        _baseName = value;
        return this;
    }

    /**
     * Gets or sets the owner of the column in the schema table
     */
    @property final string baseOwner() const nothrow pure @safe
    {
        return _baseOwner;
    }

    @property final typeof(this) baseOwner(string value) nothrow pure @safe
    {
        _baseOwner = value;
        return this;
    }

    /**
     * Gets or sets the name of the schema in the schema table
     */
    @property final string baseSchemaName() const nothrow pure @safe
    {
        return _baseSchemaName;
    }

    @property final typeof(this) baseSchemaName(string value) nothrow pure @safe
    {
        _baseSchemaName = value;
        return this;
    }

    /**
     * Gets or sets provider-specific numeric scale of the column
     */
    @property final int32 baseNumericScale() const nothrow pure @safe
    {
        return _baseType.numericScale;
    }

    @property final typeof(this) baseNumericScale(int value) nothrow pure @safe
    {
        _baseType.numericScale = value;
        return this;
    }

    /**
     * Gets or sets provider-specific size of the column
     */
    @property final int32 baseSize() const nothrow pure @safe
    {
        return _baseType.size;
    }

    @property final typeof(this) baseSize(int32 value) nothrow pure @safe
    {
        _baseType.size = value;
        return this;
    }

    /**
     * Gets or sets provider-specific subtype of the column
     */
    @property final int32 baseSubTypeId() const nothrow pure @safe
    {
        return _baseType.subTypeId;
    }

    @property final typeof(this) baseSubTypeId(int32 value) nothrow pure @safe
    {
        _baseType.subTypeId = value;
        return this;
    }

    /**
     * Gets or sets the name of the table in the schema table
     */
    @property final string baseTableName() const nothrow pure @safe
    {
        return _baseTableName;
    }

    @property final typeof(this) baseTableName(string value) nothrow pure @safe
    {
        _baseTableName = value;
        return this;
    }

    /**
     * Gets or sets the id of the table in the schema table
     */
    @property final int32 baseTableId() const nothrow pure @safe
    {
        return _baseTableId;
    }

    @property final typeof(this) baseTableId(int32 value) nothrow pure @safe
    {
        _baseTableId = value;
        return this;
    }

    /**
     * Gets or sets provider-specific data type of the column
     */
    @property final DbBaseType baseType() const nothrow pure @safe
    {
        return _baseType;
    }

    /**
     * Gets or sets provider-specific data type of the column
     */
    @property final int32 baseTypeId() const nothrow pure @safe
    {
        return _baseType.typeId;
    }

    @property final typeof(this) baseTypeId(int32 value) nothrow @safe
    {
        _baseType.typeId = value;
        return this;
    }

    @property bool isArray() const nothrow pure @safe
    {
        return (_type & DbType.array) != 0;
    }

    @property final typeof(this) isArray(bool value) nothrow pure @safe
    {
        if (value)
            _type |= DbType.array;
        else
            _type &= ~DbType.array;

        if (!isDbTypeHasSize(_type))
            _size = 0;

        return this;
    }

    /**
     * Gets or sets the ordinal of the column, based 1 value
     */
    @property final uint32 ordinal() const nothrow pure @safe
    {
        return _ordinal;
    }

    @property final typeof(this) ordinal(uint32 value) nothrow pure @safe
    {
        _ordinal = value;
        return this;
    }

    /**
     * Gets or sets maximum size, in bytes of the parameter
     * used for array, binary, fixedBinary, utf8String, fixedUtf8String
     * json, and xml types.
     */
    pragma(inline, true)
    @property final int32 size() const nothrow pure @safe
    {
        return _size;
    }

    @property final typeof(this) size(int32 value) nothrow @safe
    {
        _size = value;
        return this;
    }

    /**
     * Gets or sets the DbType of the parameter
     */
    pragma(inline, true)
    @property final DbType type() const nothrow pure @safe
    {
        return _type & ~DbType.array;
    }

    @property final typeof(this) type(DbType value) nothrow pure @safe
    {
        // Maintain the array flag
        _type = isArray ? (value | DbType.array) : value;

        if (!isDbTypeHasSize(_type))
            _size = 0;

        return this;
    }

protected:
    void assignTo(DbNameColumn dest) nothrow @safe
    {
        version (none)
        foreach (m; __traits(allMembers, DbNamedColumn))
        {
            static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m).dup)))
                __traits(getMember, ret, m) = __traits(getMember, this, m).dup;
            else static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m))))
                __traits(getMember, ret, m) = __traits(getMember, this, m);
        }

        foreach (m; FieldNameTuple!DbNameColumn)
        {
            __traits(getMember, dest, m) = __traits(getMember, this, m);
        }
    }

    void reevaluateBaseType() nothrow @safe
    {}

protected:
    string _baseName;
    string _baseOwner;
    string _baseSchemaName;
    string _baseTableName;
    int32 _baseId;
    int32 _baseTableId;
    DbBaseType _baseType;
    uint32 _ordinal; // 0=Unknown position
    int32 _size;
    DbType _type;
    EnumSet!DbSchemaColumnFlag _flags;
    //int32 _basePrecision;
    //DbCharset _charset;
}

class DbField : DbNameColumn
{
public:
    this(DbCommand command, DbIdentitier name) nothrow pure @safe
    {
        this._command = command;
        this._name = name;
        this._flags.set(DbSchemaColumnFlag.allowNull, true);
    }

    final typeof(this) clone(DbCommand command) nothrow @safe
    {
        auto result = createSelf(command);
        assignTo(result);
        return result;
    }

    abstract DbField createSelf(DbCommand command) nothrow @safe;

    @property final DbCommand command() nothrow @safe
    {
        return _command;
    }

    @property final DbDatabase database() nothrow @safe
    {
        return _command !is null ? _command.database : null;
    }

    /** Gets or sets whether this column is aliased
    */
    @property final bool isAlias() const nothrow @safe
    {
        return _flags.on(DbSchemaColumnFlag.isAlias);
    }

    @property final typeof(this) isAlias(bool value) nothrow @safe
    {
        _flags.set(DbSchemaColumnFlag.isAlias, value);
        return this;
    }

    /**
     * Gets or sets whether this column is an expression
     */
    @property final bool isExpression() const nothrow @safe
    {
        return _flags.on(DbSchemaColumnFlag.isExpression);
    }

    @property final typeof(this) isExpression(bool value) nothrow @safe
    {
        _flags.set(DbSchemaColumnFlag.isExpression, value);
        return this;
    }

    /**
     * Gets or sets whether this column is a key for the dataset
     */
    @property final bool isKey() const nothrow @safe
    {
        return _flags.on(DbSchemaColumnFlag.isKey);
    }

    @property final typeof(this) isKey(bool value) nothrow @safe
    {
        _flags.set(DbSchemaColumnFlag.isKey, value);
        return this;
    }

    /**
     * Gets or sets whether a unique constraint applies to this column
     */
    @property final bool isUnique() const nothrow @safe
    {
        return _flags.on(DbSchemaColumnFlag.isUnique);
    }

    @property final typeof(this) isUnique(bool value) nothrow @safe
    {
        _flags.set(DbSchemaColumnFlag.isUnique, value);
        return this;
    }

protected:
    DbCommand _command;
}

class DbFieldList : DbNameObjectList!DbField, IDisposable
{
public:
    this(DbCommand command) nothrow pure @safe
    {
        this._command = command;
    }

    final typeof(this) clone(DbCommand command) nothrow @safe
    {
        auto result = createSelf(command);
        foreach (field; this)
            result.add(field.clone(command));
        return result;
    }

    abstract DbField createField(DbCommand command, DbIdentitier name) nothrow @safe;
    abstract DbFieldList createSelf(DbCommand command) nothrow @safe;

    final DbField createField(DbCommand command, string name) nothrow @safe
    {
        DbIdentitier id = DbIdentitier(name);
        return createField(command, id);
    }

    final void disposal(bool disposing) nothrow @safe
    {
        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));

        _disposing++;
        doDispose(disposing);

        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));
    }

    final void dispose() nothrow @safe
    {
        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));

        _disposing++;
        doDispose(true);

        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));
    }

    @property final DbCommand command() nothrow @safe
    {
        return _command;
    }

    @property final DbDatabase database() nothrow @safe
    {
        return _command !is null ? _command.database : null;
    }

    @property final DisposableState disposingState() const nothrow @safe
    {
        if (_disposing == 0)
            return DisposableState.none;
        else if (_disposing > 0)
            return DisposableState.disposing;
        else
            return DisposableState.destructing;
    }

protected:
    override void add(DbField item) nothrow
    {
        super.add(item);
        item._ordinal = cast(uint32)length;
    }

    void doDispose(bool disposing) nothrow @safe
    {
        clear();
        _command = null;
    }

protected:
    DbCommand _command;

private:
    byte _disposing;
}

class DbParameter : DbNameColumn
{
public:
    this(DbDatabase database, DbIdentitier name) nothrow pure @safe
    {
        this._name = name;
        this._flags.set(DbSchemaColumnFlag.allowNull, true);
    }

    final bool hasInputValue() const nothrow pure @safe
    {
        return isInput() && !_dbValue.isNull;
    }

    final bool isInput() const nothrow pure @safe
    {
        return direction == DbParameterDirection.input
            || direction == DbParameterDirection.inputOutput;
    }

    final bool isOutput(bool outputOnly) const nothrow pure @safe
    {
        return (direction == DbParameterDirection.inputOutput && !outputOnly)
            || direction == DbParameterDirection.output
            || direction == DbParameterDirection.returnValue;
    }

    final DbParameter updateEmptyName(DbIdentitier noneEmptyName) nothrow @safe
    in
    {
        assert(noneEmptyName.length > 0);
        assert(name.length == 0);
    }
    do
    {
        updateName(noneEmptyName);
        return this;
    }

    /**
     * Gets or sets a value that describes the type of the parameter
     */
    @property final DbParameterDirection direction() const nothrow pure @safe
    {
        return _direction;
    }

    @property final DbParameter direction(DbParameterDirection value) nothrow pure @safe
    {
        _direction = value;
        return this;
    }

    @property final bool isNullValue() const nothrow pure @safe
    {
        return _dbValue.isNull;
    }

    @property final Variant variant() @safe
    {
        return _dbValue.value;
    }

    /**
     * Gets or sets the value of the parameter
     */
    @property final ref DbValue value() return @safe
    {
        return _dbValue;
    }

    @property final DbParameter value(DbValue newValue) @safe
    {
        this._dbValue = newValue;
        this.valueAssigned();
        return this;
    }

protected:
    override void assignTo(DbNameColumn dest) nothrow @safe
    {
        super.assignTo(dest);

        auto destP = cast(DbParameter)dest;
        if (destP)
        {
            destP._direction = _direction;
            destP._dbValue = _dbValue;
        }
    }

    final void nullifyValue() nothrow @safe
    {
        _dbValue.nullify();
    }

    final void valueAssigned() @safe
    {
        if (type == DbType.unknown && _dbValue.type != DbType.unknown)
        {
            if (isDbTypeHasSize(_dbValue.type) && _dbValue.hasSize)
                size = _dbValue.size;
            type = _dbValue.type;
            reevaluateBaseType();
        }
    }

protected:
    DbValue _dbValue;
    DbParameterDirection _direction;
}

class DbParameterList : DbNameObjectList!DbParameter, IDisposable
{
public:
    this(DbDatabase database) nothrow pure @safe
    {
        this._database = database;
    }

    DbParameter add(DbIdentitier name, DbType type, DbParameterDirection direction, int32 size) nothrow @safe
    in
    {
        assert(name.length != 0);
        assert(!exist(name));
    }
    do
    {
        auto result = database.createParameter(name);
        result.type = type;
        result.size = size;
        result.direction = direction;
        put(result);
        return result;
    }

    final DbParameter add(string name, DbType type, DbParameterDirection direction,
        int32 size = 0) nothrow @safe
    in
    {
        assert(name.length != 0);
        assert(!exist(name));
    }
    do
    {
        DbIdentitier id = DbIdentitier(name);
        return add(id, type, direction, size);
    }

    final DbParameter add(string name, DbType type,
        int32 size = 0,
        DbParameterDirection direction = DbParameterDirection.input) nothrow @safe
    in
    {
        assert(name.length != 0);
        assert(!exist(name));
    }
    do
    {
        DbIdentitier id = DbIdentitier(name);
        return add(id, type, direction, size);
    }

    final DbParameter addClone(DbParameter source) @safe
    {
        auto result = add(source.name, source.type, source.direction, source.size);
        source.assignTo(result);
        return result;
    }

    final DbParameter createParameter(DbIdentitier name) nothrow @safe
    {
        return database.createParameter(name);
    }

    final DbParameter createParameter(string name) nothrow @safe
    {
        DbIdentitier id = DbIdentitier(name);
        return database.createParameter(id);
    }

    final void disposal(bool disposing) nothrow @safe
    {
        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));

        _disposing++;
        doDispose(disposing);

        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));
    }

    final void dispose() nothrow @safe
    {
        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));

        _disposing++;
        doDispose(true);

        version (TraceInvalidMemoryOp) traceFunction!("pham.db.database")(className(this));
    }

    final DbIdentitier generateParameterName() nothrow @safe
    {
        return generateUniqueName("parameter");
    }

    final DbParameter hasOutputParameter(string name, size_t outputIndex) nothrow @safe
    {
        DbParameter result;
        // Parameter can't have same name regardless of direction
        if (name.length != 0 && find(name, result))
            return result;
        size_t outIndex;
        foreach (i; 0..length)
        {
            result = this[i];
            enum outputOnly = false;
            if (result.isOutput(outputOnly))
            {
                if (outIndex++ == outputIndex)
                    return result;
            }
        }
        return null;
    }

    final size_t inputCount() nothrow pure @safe
    {
        size_t result = 0;
        foreach (i; 0..length)
        {
            if (this[i].isInput())
                result++;
        }
        return result;
    }

    final DbParameter[] inputParameters() nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        const count = inputCount();
        if (count == 0)
            return null;
        else
        {
            size_t i = 0;
            auto result = new DbParameter[](count);
            foreach (parameter; this)
            {
                if (parameter.isInput())
                {
                    if (parameter.baseTypeId == 0)
                        parameter.reevaluateBaseType();
                    result[i++] = parameter;
                }
            }
            return result;
        }
    }

    final typeof(this) nullifyOutputParameters() nothrow @safe
    {
        foreach (parameter; this)
        {
            enum outputOnly = true;
            if (parameter.isOutput(outputOnly))
                parameter.nullifyValue();
        }
        return this;
    }

    final size_t outputCount(bool outputOnly) nothrow pure @safe
    {
        size_t result = 0;
        foreach (i; 0..length)
        {
            if (this[i].isOutput(outputOnly))
                result++;
        }
        return result;
    }

    /*
     * Search for existing parameter matched with name; if not found, add it
     */
    DbParameter touch(DbIdentitier name, DbType type, DbParameterDirection direction, int32 size) nothrow @safe
    in
    {
        assert(name.length != 0);
    }
    do
    {
        DbParameter result;
        if (find(name, result))
        {
            if (result.type == DbType.unknown)
            {
                result.size = size;
                result.type = type;
                result.reevaluateBaseType();
            }
            return result;
        }
        else
            return add(name, type, direction, size);
    }

    final DbParameter touch(string name, DbType type, DbParameterDirection direction,
        int32 size = 0) nothrow @safe
    in
    {
        assert(name.length != 0);
    }
    do
    {
        DbIdentitier id = DbIdentitier(name);
        return touch(id, type, direction, size);
    }

    final DbParameter touch(string name, DbType type,
        int32 size = 0,
        DbParameterDirection direction = DbParameterDirection.input) nothrow @safe
    in
    {
        assert(name.length != 0);
    }
    do
    {
        DbIdentitier id = DbIdentitier(name);
        return touch(id, type, direction, size);
    }

    @property final DbDatabase database() nothrow @safe
    {
        return _database;
    }

    @property final DisposableState disposingState() const nothrow @safe
    {
        if (_disposing == 0)
            return DisposableState.none;
        else if (_disposing > 0)
            return DisposableState.disposing;
        else
            return DisposableState.destructing;
    }

protected:
    override void add(DbParameter item) nothrow @safe
    {
        super.add(item);
        item._ordinal = cast(uint32)length;
    }

    void doDispose(bool disposing) nothrow @safe
    {
        clear();
        _database = null;
    }

protected:
    DbDatabase _database;

private:
    byte _disposing;
}

struct DbRAIITransaction
{
@safe:

public:
    @disable this();
    @disable this(ref typeof(this));
    @disable void opAssign(typeof(this));

    this(DbConnection connection,
        DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted,
        bool isAutoCommit = false) // false=since we can not findout when exception is taken placed
    {
        auto last = connection.lastTransaction(false);
        if (last is null)
        {
            auto newTransaction = connection.createTransaction(isolationLevel);
            this(connection, newTransaction, isAutoCommit, true);
            newTransaction.start();
        }
        else
        {
            this(connection, last, isAutoCommit, false);
        }
    }

    this(DbConnection connection, DbTransaction transaction,
        bool isAutoCommit = false, // false=since we can not findout when exception is taken placed
        bool isManage = false)
    {
        this._connection = connection;
        this._transaction = transaction;
        this.isAutoCommit = isAutoCommit;
        this.isManage = isManage;
    }

    ~this()
    {
        if (isManage)
        {
            if (isAutoCommit)
                commit();
            else
                rollback();
        }
    }

    void commit()
    {
        if (isManage && _transaction !is null)
        {
            _transaction.commit();
            _transaction.dispose();
        }
        _transaction = null;
    }

    void rollback()
    {
        if (isManage && _transaction !is null)
        {
            _transaction.rollback();
            _transaction.dispose();
        }
        _transaction = null;
    }

    @property DbConnection connection() nothrow pure
    {
        return _connection;
    }

    @property DbTransaction transaction() nothrow pure
    {
        return _transaction;
    }

private:
    DbConnection _connection;
    DbTransaction _transaction;
    bool isAutoCommit, isManage;
}

struct DbReader
{
public:
    @disable this(this);

    this(DbCommand command, bool implicitTransaction) nothrow @safe
    {
        this._command = command;
        this._fields = command.fields;
        this._hasRows = HasRows.unknown;
        this._flags.set(Flag.implicitTransaction, implicitTransaction);
    }

    ~this() @safe
    {
        dispose(false);
    }

    /*
     * Remove this DbReader from its command
     * Returns:
     *      Self
     */
    ref typeof(this) detach() nothrow return
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_flags.on(Flag.cacheResult) && _hasRows == HasRows.yes && _command !is null)
        {
            _fields = _command.fields.clone(null);
        }
        else
        {
            _fields = null;
            _currentRow.nullify();
        }

        doDetach(false);
        _flags.set(Flag.allRowsFetched, true); // No longer able to fetch after detached

        return this;
    }

    void dispose(bool disposing = true) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (_command !is null)
            doDetach(disposing);

        _fields = null;
        _fetchedCount = 0;
        _hasRows = HasRows.no;
        _flags.set(Flag.allRowsFetched, true);
        _currentRow.nullify();
    }

    /**
     * Gets the DbValue of the specified column index
     */
    DbValue getDbValue(size_t index) @safe
    in
    {
        assert(index < _currentRow.length);
    }
    do
    {
        return _currentRow[index];
    }

    /**
     * Gets the DbValue of the specified column name
     */
    DbValue getDbValue(string name) @safe
    {
        const index = fields.indexOfSafe(name);
        return getDbValue(index);
    }

    /**
     * Gets the column index given the name of the column
     */
    ptrdiff_t getIndex(scope const(DbIdentitier) name) nothrow @safe
    {
        return fields.indexOf(name);
    }

    ptrdiff_t getIndex(string name) nothrow @safe
    {
        auto id = DbIdentitier(name);
        return fields.indexOf(id);
    }

    /**
     * Gets the name of the column, given the column index
     */
    string getName(size_t index) nothrow @safe
    in
    {
        assert(index < fields.length);
    }
    do
    {
        return fields[index].name;
    }

    /**
     * Gets the Variant of the specified column index
     */
    Variant getValue(size_t index) @safe
    in
    {
        assert(index < _currentRow.length);
    }
    do
    {
        return getVariant(index);
    }

    T getValue(T)(size_t index) @safe
    in
    {
        assert(index < _currentRow.length);
    }
    do
    {
        return !isNull(index) ? getVariant(index).get!T() : T.init;
    }

    /**
     * Gets the Variant of the specified column name
     */
    Variant getValue(string name) @safe
    {
        const index = fields.indexOfSafe(name);
        return getValue(index);
    }

    bool isNull(size_t index) nothrow @safe
    in
    {
        assert(index < _currentRow.length);
    }
    do
    {
        return _currentRow[index].isNull();
    }

    /**
     * Gets a value that indicates whether the column contains nonexistent or missing value
     */
    bool isNull(string name) @safe
    {
        const index = fields.indexOfSafe(name);
        return _currentRow[index].isNull();
    }

    void popFront() @safe
    {
        // Initialize the first row?
        if (_hasRows == HasRows.unknown)
        {
            if (read())
                read();
        }
        else
            read();
    }

    /**
     * Advances this DbReader to the next record in a result set
     */
    bool read() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("_fetchedCount=", _fetchedCount);
        version (profile) debug auto p = PerfFunction.create();

        if (_hasRows == HasRows.unknown)
            return fetchFirst(false);

        if (_flags.off(Flag.allRowsFetched))
        {
            if (_flags.off(Flag.skipFetchNext))
                fetchNext();

            _flags.set(Flag.skipFetchNext, false);
        }

        return _flags.off(Flag.allRowsFetched);
    }

    /* Properties */

    @property DbCommand command() nothrow pure @safe
    {
        return _command;
    }

    @property DbDatabase database() nothrow pure @safe
    {
        return _command !is null ? _command.database : null;
    }

    @property bool empty() @safe
    {
        return hasRows ? _flags.on(Flag.allRowsFetched) : true;
    }

    @property DbFieldList fields() nothrow pure @safe
    {
        return _fields;
    }

    /**
     * Gets a value that indicates whether this DbReader contains one or more rows
     */
    @property bool hasRows() @safe
    {
        if (_hasRows == HasRows.unknown)
            fetchFirst(true);

        return _hasRows == HasRows.yes;
    }

    @property bool implicitTransaction() const nothrow pure @safe
    {
        return _flags.on(Flag.implicitTransaction);
    }

private:
    enum Flag : byte
    {
        allRowsFetched,
        cacheResult,
        implicitTransaction,
        skipFetchNext,
    }

    enum HasRows : byte
    {
        unknown,
        no,
        yes
    }

    void doDetach(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        _command.removeReader(this);
        _command = null;
    }

    bool fetchFirst(const(bool) checking) @safe
    in
    {
         assert(_hasRows == HasRows.unknown);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        _currentRow = command.fetch(false);
        const hasRow = _currentRow.length != 0;
        if (hasRow)
        {
            _fetchedCount++;
            _hasRows = HasRows.yes;
            if (checking)
                _flags.set(Flag.skipFetchNext, true);
        }
        else
        {
            _hasRows = HasRows.no;
            _flags.set(Flag.allRowsFetched, true);
        }

        version (TraceFunction) traceFunction!("pham.db.database")("_fetchedCount=", _fetchedCount, ", hasRow=", hasRow);

        return hasRow;
    }

    void fetchNext() @safe
    in
    {
         assert(_hasRows == HasRows.yes);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        _currentRow = command.fetch(false);
        const hasRow = _currentRow.length != 0;
        if (hasRow)
            _fetchedCount++;
        else
            _flags.set(Flag.allRowsFetched, true);

        version (TraceFunction) traceFunction!("pham.db.database")("_fetchedCount=", _fetchedCount, ", hasRow=", hasRow);
    }

    Variant getVariant(const(size_t) index) @safe
    {
        version (profile) debug auto p = PerfFunction.create();

        auto field = fields[index];
        final switch (field.isValueIdType())
        {
            case DbFieldIdType.no:
                return _currentRow[index].value;
            case DbFieldIdType.array:
                return command.readArray(field, _currentRow[index]);
            case DbFieldIdType.blob:
                return Variant(command.readBlob(field, _currentRow[index]));
            case DbFieldIdType.clob:
                return Variant(command.readClob(field, _currentRow[index]));
        }
    }

private:
    DbCommand _command;
    DbFieldList _fields;
    DbRowValue _currentRow;
    size_t _fetchedCount;
    EnumSet!Flag _flags;
    HasRows _hasRows;
    //bool _allRowsFetched, _cacheResult, _implicitTransaction, _skipFetchNext;
}

abstract class DbTransaction : DbDisposableObject
{
public:
    this(DbConnection connection, DbIsolationLevel isolationLevel) nothrow @safe
    {
        this._connection = connection;
        this._database = connection.database;
        this._isolationLevel = isolationLevel;
        this._lockTimeout = dur!"seconds"(DbDefaultSize.transactionLockTimeout);
        this._state = DbTransactionState.inactive;
    }

    final typeof(this) addLockTable(DbLockTable lockedTable) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        _lockedTables ~= lockedTable;
        doOptionChanged("addLockTable");
        return this;
    }

    /**
     * Performs a commit for this transaction
	 */
    final typeof(this) commit() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkState(DbTransactionState.active);

        if (auto log = logger)
            log.info(forLogInfo(), newline, "transaction.commit()");

        scope (failure)
            _state = DbTransactionState.error;

        doCommit(false);
        if (!handle)
            _state = DbTransactionState.inactive;

        return this;
    }

    final string forLogInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    /**
     * Performs a rollback for this transaction
	 */
    final typeof(this) rollback() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        if (state == DbTransactionState.active)
        {
            if (auto log = logger)
                log.info(forLogInfo(), newline, "transaction.rollback()");

            scope (failure)
                _state = DbTransactionState.error;

            doRollback(false);
            if (!handle)
                _state = DbTransactionState.inactive;
        }

        return this;
    }

    final typeof(this) start() @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        checkState(DbTransactionState.inactive);

        if (auto log = logger)
            log.info(forLogInfo(), newline, "transaction.start()");

        scope (failure)
        {
            _state = DbTransactionState.error;
            if (!isDefault)
                complete(false);
        }

        doStart();
        _state = DbTransactionState.active;

        return this;
    }

    /**
     * Default value is false
     */
    @property final bool autoCommit() const nothrow pure @safe
    {
        return _flags.on(DbTransactionFlag.autoCommit);
    }

    @property final typeof(this) autoCommit(bool value) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        if (autoCommit != value)
        {
            _flags.set(DbTransactionFlag.autoCommit, value);
            doOptionChanged("autoCommit");
        }
        return this;
    }

    /**
     * The connection that creates and owns this transaction
	 */
    @property final DbConnection connection() nothrow pure @safe
    {
        return _connection;
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _database;
    }

    @property final DbHandle handle() const nothrow pure @safe
    {
        return _handle;
    }

    @property final bool isDefault() const nothrow @safe
    {
        return _connection !is null && this is _connection._defaultTransaction;
    }

    /**
     * Indicator of current isolation level of transaction
	 */
    @property final DbIsolationLevel isolationLevel() const nothrow pure @safe
    {
        return _isolationLevel;
    }

    @property final bool isRetaining() const nothrow pure @safe
    {
        return _flags.on(DbTransactionFlag.retaining);
    }

    @property final DbLockTable[] lockedTables() nothrow pure @safe
    {
        return _lockedTables;
    }

    /**
     * Default value is 60 seconds
     */
    @property final Duration lockTimeout() const nothrow pure @safe
    {
        return _lockTimeout;
    }

    @property final typeof(this) lockTimeout(Duration value) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        if (_lockTimeout != value)
        {
            _lockTimeout = value;
            doOptionChanged("lockTimeout");
        }
        return this;
    }

    @property final Logger logger() nothrow pure @safe
    {
        return _connection !is null ? _connection.logger : null;
    }

    /**
     * Default value is false
     */
    @property final bool readOnly() const nothrow pure @safe
    {
        return _flags.on(DbTransactionFlag.readOnly);
    }

    @property final typeof(this) readOnly(bool value) nothrow @safe
    in
    {
        assert(state == DbTransactionState.inactive);
    }
    do
    {
        if (readOnly != value)
        {
            _flags.set(DbTransactionFlag.readOnly, value);
            doOptionChanged("readOnly");
        }
        return this;
    }

    /**
     * Indicator of current state of transaction
	 */
    @property final DbTransactionState state() const nothrow pure @safe
    {
        return _state;
    }

protected:
    enum DbTransactionFlag : byte
    {
        autoCommit,
        readOnly,
        retaining
    }

    final bool canRetain() const nothrow @safe
    {
        return isRetaining
            && disposingState == DisposableState.none
            && _connection.state == DbConnectionState.open;
    }

    final void checkState(DbTransactionState checkingState,
        string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("checkingState=", checkingState, ", callerName=", callerName);

        if (_state != checkingState)
        {
            auto msg = DbMessage.eInvalidTransactionState.fmtMessage(callerName, toName!DbTransactionState(_state), toName!DbTransactionState(checkingState));
            throw new DbException(msg, DbErrorCode.connect, null);
        }

        if (_connection is null)
        {
            auto msg = DbMessage.eCompletedTransaction.fmtMessage(callerName);
            throw new DbException(msg, 0, null);
        }
    }

    final void complete(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("disposing=", disposing);

        if (_connection !is null)
        {
            _connection.removeTransaction(this);
            _connection = null;
        }

        _state = DbTransactionState.disposed;
        _lockedTables = null;
        _database = null;
        _handle.reset();
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        assert(state != DbTransactionState.active);

        complete(disposing);
        _next = null;
        _prev = null;
    }

    void doOptionChanged(string name) nothrow @safe
    {}

    abstract void doCommit(bool disposing) @safe;
    abstract void doRollback(bool disposing) @safe;
    abstract void doStart() @safe;

protected:
    DbConnection _connection;
    DbDatabase _database;
    DbHandle _handle;
    Duration _lockTimeout;
    DbLockTable[] _lockedTables;
    EnumSet!DbTransactionFlag _flags;
    DbIsolationLevel _isolationLevel;
    DbTransactionState _state;

private:
    DbTransaction _next;
    DbTransaction _prev;
}

mixin DLinkTypes!(DbTransaction) DLinkDbTransactionTypes;


// Any below codes are private
private:

__gshared static Mutex _poolMutex;
__gshared static TimerThread _secondTimer;

shared static this()
{
    version (TraceFunctionDB) ModuleLoggerOptions.setModule(ModuleLoggerOption(LogLevel.trace, "pham.db.database"));

    _poolMutex = new Mutex();
    _secondTimer = new TimerThread(dur!"seconds"(1));

    // Add pool event to timer
    auto pool = DbConnectionPool.instance;
    _secondTimer.addEvent(TimerEvent("DbConnectionPool", dur!"minutes"(1), &pool.doTimer));
}

shared static ~this()
{
    // Timer must be destroyed first
    if (_secondTimer !is null)
    {
        _secondTimer.terminate();
        _secondTimer.destroy();
        _secondTimer = null;
    }

    DbConnectionPool.cleanup();
    DbDatabaseList.cleanup();

    if (_poolMutex !is null)
    {
        _poolMutex.destroy();
        _poolMutex = null;
    }
}
