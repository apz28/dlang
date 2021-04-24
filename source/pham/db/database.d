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
import std.conv : text, to;
import std.datetime.systime : SysTime;
import std.exception : assumeWontThrow;
import std.format : format;
import std.logger.core : Logger, LogTimming;
import std.traits; // : allMembers, getMember;
import std.typecons : Flag, No, Yes;

version (unittest) import pham.utl.utltest;
import pham.utl.delegate_list;
import pham.utl.dlink_list;
import pham.utl.enum_set : EnumSet, toEnum, toName;
import pham.utl.timer;
import pham.utl.utlobject : DisposableState, IDisposable, RAIIMutex, singleton;
import pham.db.message;
import pham.db.exception;
import pham.db.util;
import pham.db.type;
import pham.db.dbobject;
import pham.db.convert;
import pham.db.value;
import pham.db.parser;

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
    this(DbConnection connection, string name = null) nothrow @trusted //@trusted=cast(void*)
    {
        this._connection = connection;
        //this._name = name.length != 0 ? name : makeCommandName(cast(void*)this, connection.nextCounter);
        this._name = name;
        this._fetchRecordCount = connection.connectionStringBuilder.fetchRecordCount;
        _flags.set(DbCommandFlag.parametersCheck, true);
        _flags.set(DbCommandFlag.returnRecordsAffected, true);
    }

    final typeof(this) cancel()
    {
        version (TraceFunction) dgFunctionTrace();

        if (_connection !is null)
            _connection.cancelCommand(this);

        return this;
    }

    final typeof(this) clearParameters() nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_parameters !is null)
            _parameters.clear();

        return this;
    }

    final DbRecordsAffected executeNonQuery() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        bool implicitTransactionCalled = false;
        bool unprepareCalled = false;
        checkCommand();
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
        return result;
    }

    final DbReader executeReader() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        checkCommand();
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
        return DbReader(this, implicitTransaction);
    }

    final DbValue executeScalar() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        bool implicitTransactionCalled = false;
        bool unprepareCalled = false;
        checkCommand();
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
        return values ? values[0] : DbValue.dbNull();
    }

    abstract DbRowValue fetch(bool isScalar) @safe;

    final string forLogInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    abstract const(char)[] getExecutionPlan(uint vendorMode = 0);

    final DbParameter[] inputParameters() nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (!hasParameters)
            return null;
        else
            return parameters.inputParameters();
    }

    final typeof(this) prepare() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (prepared)
            return this;

        checkCommand();
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
        }
        catch (Exception e)
        {
            if (auto log = logger)
                log.error(forLogInfo(), newline, e.msg, newline, executeCommandText, e);
            throw e;
        }

        return this;
    }

    abstract Variant readArray(DbNamedColumn arrayColumn, DbValue arrayValueId) @safe;
    abstract ubyte[] readBlob(DbNamedColumn blobColumn, DbValue blobValueId) @safe;

    final string readClob(DbNamedColumn clobColumn, DbValue clobValueId) @trusted //@trusted=cast(string)
    {
        auto blob = readBlob(clobColumn, clobValueId);
        return blob.length != 0 ? cast(string)blob : null;
    }

    final typeof(this) unprepare() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        checkActiveReader();

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
        {
            resetNewStatement(ResetStatementKind.unprepare);

            _executeCommandText = null;
            _recordsAffected.reset();
            _baseCommandType = 0;
            _commandState = DbCommandState.unprepared;
        }

        doUnprepare();

        return this;
    }

    abstract DbValue writeBlob(DbNamedColumn blobColumn, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe;

    final DbValue writeClob(DbNamedColumn clobColumn, scope const(char)[] clobValue,
        DbValue optionalClobValueId = DbValue.init) @safe
    {
        import std.string : representation;

        return writeBlob(clobColumn, clobValue.representation, optionalClobValueId);
    }

    /* Properties */

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
        _commandTimeout = minDuration(value);
        return this;
    }

    /** Gets or sets how the commandText property is interpreted
    */
    @property final DbCommandType commandType() const nothrow @safe
    {
        return _commandType;
    }

    @property final typeof(this) commandType(DbCommandType value) nothrow @safe
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

    @property final uint executedCount() const nothrow @safe
    {
        return _executedCount;
    }

    @property final uint fetchRecordCount() const nothrow @safe
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
    @property final bool hasFields() const nothrow @safe
    {
        return _fields !is null && _fields.length != 0;
    }

    /**
     * Returns true if this DbCommand has atleast one DbParameter; otherwise returns false
     */
    @property final bool hasParameters() const nothrow @safe
    {
        return _parameters !is null && _parameters.length != 0;
    }

    @property final bool hasReaders() const nothrow @safe
    {
        return _readerCounter != 0;
    }

    @property final bool isStoredProcedure() const nothrow @safe
    {
        return commandType == DbCommandType.storedProcedure;
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
    @property final bool parametersCheck() const nothrow @safe
    {
        return _flags.on(DbCommandFlag.parametersCheck);
    }

    @property final typeof(this) parametersCheck(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.parametersCheck, value);
        return this;
    }

    /**
     * Returns true if DbParameterList is in prepared state
     */
    @property final bool prepared() const nothrow @safe
    {
        return _commandState == DbCommandState.prepared ||
            _commandState == DbCommandState.executed;
    }

    /**
     * Gets number of records affected after executed a commandText
     */
    @property final DbRecordsAffected recordsAffected() const nothrow @safe
    {
        return _recordsAffected;
    }

    @property final bool returnRecordsAffected() const nothrow @safe
    {
        return _flags.on(DbCommandFlag.returnRecordsAffected);
    }

    @property final typeof(this) returnRecordsAffected(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.returnRecordsAffected, value);
        return this;
    }

    /**
     * Gets or sets DbTransaction used by this DbCommand
     */
    @property final DbTransaction transaction() nothrow @safe
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

    @property final bool transactionRequired() const nothrow @safe
    {
        return _flags.on(DbCommandFlag.transactionRequired);
    }

package:
    @property final void allRowsFetched(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.allRowsFetched, value);
    }

    @property final void transactionRequired(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.transactionRequired, value);
    }

protected:
    final string buildExecuteCommandText() nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        string result;
        final switch (commandType)
        {
            case DbCommandType.text:
                result = buildTextSql(commandText);
                break;
            case DbCommandType.storedProcedure:
                result = buildStoredProcedureSql(commandText);
                break;
            case DbCommandType.table:
                result = buildTableSql(commandText);
                break;
            case DbCommandType.ddl:
                result = buildTextSql(commandText);
                break;
        }

        if (auto log = logger)
            log.info(forLogInfo(), newline, result);

        return result;
    }

    final void buildParameterNameCallback(ref Appender!string result, string parameterName, size_t ordinal) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace("parameterName=", parameterName, ", ordinal=", ordinal);

        result.put(buildParameterPlaceholder(parameterName, ordinal));
        DbParameter found;
        if (!parameters.find(parameterName, found))
            found = parameters.add(parameterName, DbType.unknown);
        found.ordinal = ordinal;
    }

    string buildParameterPlaceholder(string parameterName, size_t ordinal) nothrow @safe
    {
        return "?";
    }

    string buildStoredProcedureSql(string storedProcedureName) nothrow @safe
    {
        if (storedProcedureName.length == 0)
            return null;

        scope (failure) assert(0);

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
			result.put(buildParameterPlaceholder(param.name, i + 1));
        }
        result.put(')');

        version (TraceFunction) dgFunctionTrace("storedProcedureName=", storedProcedureName, ", result=", result.data);

        return result.data;
    }

    string buildTableSql(string tableName) nothrow @safe
    {
        if (tableName.length == 0)
            return null;

        auto result = "SELECT * FROM " ~ tableName;

        version (TraceFunction) dgFunctionTrace("tableName=", tableName, ", result=", result);

        return result;
    }

    string buildTextSql(string sql) nothrow @safe
    {
        if (sql.length == 0)
            return null;

        // Do not clear to allow parameters to be filled without calling prepare
        // clearParameters();

        auto result = parametersCheck && commandType != DbCommandType.ddl
            ? parseParameter(sql, &buildParameterNameCallback)
            : sql;

        version (TraceFunction) dgFunctionTrace("result=", result);

        return result;
    }

    void checkActive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) dgFunctionTrace("callerName=", callerName);

        if (!handle)
        {
            auto msg = format(DbMessage.eInvalidCommandInactive, callerName);
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }

        if (_connection is null || _connection.state != DbConnectionState.open)
        {
            auto msg = format(DbMessage.eInvalidCommandConnection, callerName);
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }
    }

    final void checkActiveReader(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) dgFunctionTrace("callerName=", callerName);

        if (_readerCounter)
            throw new DbException(DbMessage.eInvalidCommandActiveReader, 0, 0, 0);
    }

    void checkCommand(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) dgFunctionTrace("callerName=", callerName);

        checkActiveReader(callerName);

        if (_transaction !is null && _transaction.state != DbTransactionState.active)
            transaction = null;

        if (_commandText.length == 0)
            throw new DbException(DbMessage.eInvalidCommandText, 0, 0, 0);

        if (_transaction !is null && _transaction.connection !is _connection)
            throw new DbException(DbMessage.eInvalidCommandConnectionDif, 0, 0, 0);

        if (_connection is null || _connection.state != DbConnectionState.open)
            throw new DbException(DbMessage.eInvalidCommandConnection, DbErrorCode.connect, 0, 0);
    }

    final void checkInactive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) dgFunctionTrace("callerName=", callerName);

        if (handle)
        {
            auto msg = format(DbMessage.eInvalidCommandActive, callerName);
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }
    }

    typeof(this) doCommandText(string customText, DbCommandType type) @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type, ", customText=", customText);

        if (prepared)
            unprepare();

        clearParameters();
        _executeCommandText = null;
        _commandText = customText;
        return commandType(type);
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

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

    final bool needPrepare(DbCommandExecuteType type) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        return !prepared &&
            commandType != DbCommandType.table &&
            (parametersCheck || hasParameters);
    }

    void prepareExecute(DbCommandExecuteType type) @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        _recordsAffected.reset();
        allRowsFetched(false);

        if (hasParameters)
            parameters.nullifyOutputParameters();

        executeCommandText(); // Make sure _executeCommandText is initialized
    }

    void removeReader(ref DbReader value) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_readerCounter && value.command is this)
        {
            _readerCounter--;

            if (_readerCounter == 0 && value.implicitTransaction && disposingState != DisposableState.destructing)
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
    }

    enum ResetImplicitTransactiontFlag : byte
    {
        none = 0,
        error = 1,
        nonQuery = 2
    }

    final void resetImplicitTransactionIf(ResetImplicitTransactiontFlag flags)  @safe
    {
        version (TraceFunction) dgFunctionTrace("flags=", flags);

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

    void resetNewStatement(ResetStatementKind kind) @safe
    {
        version (TraceFunction) dgFunctionTrace("kind=", kind);

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
        version (TraceFunction) dgFunctionTrace();

        if (values && hasParameters)
        {
            size_t i;
            foreach (parameter; parameters)
            {
                if (i < values.length && parameter.isOutput(No.outputOnly))
                    parameter.value = values[i++];
            }
        }
    }

    final bool setImplicitTransactionIf() @safe
    {
        version (TraceFunction) dgFunctionTrace();

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

    abstract void doExecuteCommand(DbCommandExecuteType type) @safe;
    abstract void doPrepare() @safe;
    abstract void doUnprepare() @safe;
    abstract bool isSelectCommandType() const nothrow @safe;

    @property final string executeCommandText() nothrow @safe
    {
        if (_executeCommandText.length == 0)
            _executeCommandText = buildExecuteCommandText();
        return _executeCommandText;
    }

protected:
    DbConnection _connection;
    DbFieldList _fields;
    DbParameterList _parameters;
    DbTransaction _transaction;
    string _commandText, _executeCommandText;
    string _name;
    DbRecordsAffected _recordsAffected;
    DbHandle _handle;
    Duration _commandTimeout;
    uint _executedCount; // Number of execute calls after prepare
    uint _fetchRecordCount;
    int _baseCommandType;
    EnumSet!DbCommandFlag _flags;
    DbCommandState _commandState;
    DbCommandType _commandType;
    byte _readerCounter;

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
        version (TraceFunction) dgFunctionTrace();

        checkActive();
        if (command !is null)
            command._flags.set(DbCommandFlag.cancelled, true);
        doCancelCommand();
    }

    final void close()
    {
        version (TraceFunction) dgFunctionTrace();

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
        doClose();
    }

    final DLinkDbCommandTypes.DLinkRange commands()
    {
        return _commands[];
    }

    final DbCommand createCommand(string name = null) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        checkActive();
        return _commands.insertEnd(database.createCommand(this, name));
    }

    final DbTransaction createTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        checkActive();
        return createTransactionImpl(isolationLevel, false);
    }

    final DbTransaction defaultTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

        auto previousState = state;
        if (previousState == DbConnectionState.open)
            return this;

        _state = DbConnectionState.opening;
        serverInfo.clear();
        doBeginStateChange(DbConnectionState.open);

        scope (failure)
        {
            _state = DbConnectionState.failing;
            doClose();

            _state = DbConnectionState.failed;
            doEndStateChange(previousState);
        }

        doOpen();
        _state = DbConnectionState.open;
        doEndStateChange(previousState);

        return this;
    }

    final typeof(this) release() @safe
    {
        version (TraceFunction) dgFunctionTrace();

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
        auto e = DbIdentifier.serverVersion in serverInfo;
        if (e !is null)
            return *e;

        auto v = getServerVersion();
        if (v.length != 0)
            serverInfo[DbIdentifier.serverVersion] = v;
        return v;
    }

    final override size_t toHash() nothrow @safe
    {
        return connectionStringBuilder.toHash().hashOf(scheme.toHash());
    }

    final DLinkDbTransactionTypes.DLinkRange transactions()
    {
        return _transactions[];
    }

    /* Properties */

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

    @property abstract DbIdentitier scheme() const nothrow pure @safe;

package:
    final size_t nextCounter() nothrow @safe
    {
        return (++_nextCounter);
    }

protected:
    final void checkActive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) dgFunctionTrace("callerName=", callerName);

        if (state != DbConnectionState.open)
        {
            auto msg = format(DbMessage.eInvalidConnectionInactive, callerName, connectionStringBuilder.forErrorInfo());
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }
    }

    final void checkInactive(string callerName = __FUNCTION__) @safe
    {
        version (TraceFunction) dgFunctionTrace("callerName=", callerName);

        if (state == DbConnectionState.open)
        {
            auto msg = format(DbMessage.eInvalidConnectionActive, callerName, connectionStringBuilder.forErrorInfo());
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }
    }

    final DbTransaction createTransactionImpl(DbIsolationLevel isolationLevel, bool defaultTransaction) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        return _transactions.insertEnd(database.createTransaction(this, isolationLevel, defaultTransaction));
    }

    void disposeCommands(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        while (!_commands.empty)
            _commands.remove(_commands.last).disposal(disposing);
    }

    void disposeTransactions(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _defaultTransaction = null;
        while (!_transactions.empty)
            _transactions.remove(_transactions.last).disposal(disposing);
    }

    final void doBeginStateChange(DbConnectionState newState)
    {
        if (beginStateChanges)
            beginStateChanges(this, newState);
    }

    final void doEndStateChange(DbConnectionState oldState)
    {
        if (endStateChanges)
            endStateChanges(this, oldState);
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        beginStateChanges.clear();
        endStateChanges.clear();
        disposeTransactions(disposing);
        disposeCommands(disposing);
        serverInfo = null;
        _list = null;
        _connectionStringBuilder = null;
        _database = null;
        _handle.reset();
        _state = DbConnectionState.closed;
    }

    void doPool(bool pooling) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (pooling)
        {
            disposeCommands(true);
            disposeTransactions(true);
        }
    }

    void removeCommand(DbCommand value) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (!disposingState)
        {
            if (value._prev !is null || value._next !is null)
                _commands.remove(value);
        }
    }

    void removeTransaction(DbTransaction value) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (!disposingState)
        {
            if (_defaultTransaction is value)
                _defaultTransaction = null;

            if (value._prev !is null || value._next !is null)
                _transactions.remove(value);
        }
    }

    final void rollbackTransactions(bool disposing) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        foreach (t; _transactions[])
            t.rollback();
    }

    void setConnectionString(string value) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        connectionStringBuilder().parseConnectionString(value);
    }

    abstract void doCancelCommand() @safe;
    abstract void doClose() @safe;
    abstract void doOpen() @safe;
    abstract string getServerVersion() @safe;

public:
    /**
     * Delegate to get notify when a state change
     * Occurs when the before state of the event changes
     * Params:
     *  newState = new state value
     */
    nothrow DelegateList!(DbConnection, DbConnectionState) beginStateChanges;

    /**
     * Delegate to get notify when a state change
     * Occurs when the after state of the event changes
     * Params:
     *  oldState = old state value
     */
    nothrow DelegateList!(DbConnection, DbConnectionState) endStateChanges;

    /**
     * Populate when connection is established
     */
    string[string] serverInfo;

    /**
     * For logging various message & trace
     */
    Logger logger;

protected:
    DbDatabase _database;
    DbConnectionList _list;
    DbTransaction _defaultTransaction;
    SysTime _inactiveTime;
    DbHandle _handle;
    size_t _nextCounter;
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

    final DLinkDbConnectionTypes.DLinkRange opSlice() nothrow @safe
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

    final DbConnection[] removeInactives(in SysTime now, in Duration maxInactiveTime) nothrow @safe
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

    final DbConnection acquire(string scheme, string connectionString) @safe
    {
        auto raiiMutex = () @trusted { return RAIIMutex(_poolMutex); }();
        const localMaxLength = maxLength;

        if (_acquiredLength >= localMaxLength)
        {
            auto msg = format(DbMessage.eInvalidConnectionPoolMaxUsed, _acquiredLength, localMaxLength);
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
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

        item._inactiveTime = currTime();
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
        const now = currTime();
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

    @property final string applicationVersion() const nothrow @safe
    {
        return getString(DbParameterName.applicationVersion);
    }

    @property final typeof(this) applicationVersion(string value) nothrow
    {
        put(DbParameterName.applicationVersion, value);
        return this;
    }

    @property final string charset() const nothrow @safe
    {
        return getString(DbParameterName.charset);
    }

    @property final typeof(this) charset(string value) nothrow
    {
        if (value.length)
            put(DbParameterName.charset, value);
        return this;
    }

    @property final bool compress() const nothrow @safe
    {
        return isDbTrue(getString(DbParameterName.compress));
    }

    @property final typeof(this) compress(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbParameterName.compress, setValue);
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
     * Gets or sets the time (minimum value based in seconds) to wait for a connection to open.
     * The default value is 10 seconds.
     */
    @property final Duration connectionTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbParameterName.connectionTimeout));
    }

    @property final typeof(this) connectionTimeout(in Duration value) nothrow
    {
        const setSecond = value.toMinSecond();
        auto setValue = setSecond != 0 ? to!string(setSecond) : getDefault(DbParameterName.connectionTimeout);
        put(DbParameterName.connectionTimeout, setValue);
        return this;
    }

    /**
     * The name of the database; value of "database"
     */
    @property final DbIdentitier databaseName() const nothrow @safe
    {
        return DbIdentitier(getString(DbParameterName.database));
    }

    @property final typeof(this) databaseName(string value) nothrow
    {
        put(DbParameterName.database, value);
        return this;
    }

    /**
     * The file-name of the database; value of "databaseFile"
     */
    @property final string databaseFileName() const nothrow @safe
    {
        return getString(DbParameterName.databaseFile);
    }

    @property final typeof(this) databaseFileName(string value) nothrow
    {
        put(DbParameterName.databaseFile, value);
        return this;
    }

    @property final char elementSeparator() const nothrow @safe
    {
        return _elementSeparator;
    }

    @property final DbEncryptedConnection encrypt() const nothrow @safe
    {
        return toEnum!DbEncryptedConnection(getString(DbParameterName.encrypt));
    }

    @property final typeof(this) encrypt(DbEncryptedConnection value) nothrow
    {
        put(DbParameterName.encrypt, toName(value));
        return this;
    }

    /**
     * Gets or sets number of records of each fetch call.
     * Default value is 100
     */
    @property final uint32 fetchRecordCount() const nothrow @safe
    {
        return toInt!uint32(getString(DbParameterName.fetchRecordCount));
    }

    @property final typeof(this) fetchRecordCount(uint32 value) nothrow
    {
        auto setValue = value != 0 ? to!string(value) : getDefault(DbParameterName.fetchRecordCount);
        put(DbParameterName.fetchRecordCount, setValue);
        return this;
    }

    @property final DbIntegratedSecurityConnection integratedSecurity() const nothrow @safe
    {
        return toEnum!DbIntegratedSecurityConnection(getString(DbParameterName.integratedSecurity));
    }

    @property final typeof(this) integratedSecurity(DbIntegratedSecurityConnection value) nothrow
    {
        put(DbParameterName.integratedSecurity, toName(value));
        return this;
    }

    @property final uint32 maxPoolCount() const nothrow @safe
    {
        return toInt!uint32(getString(DbParameterName.maxPoolCount));
    }

    @property final typeof(this) maxPoolCount(uint32 value) nothrow
    {
        put(DbParameterName.maxPoolCount, to!string(value));
        return this;
    }

    @property final uint32 minPoolCount() const nothrow @safe
    {
        return toInt!uint32(getString(DbParameterName.minPoolCount));
    }

    @property final typeof(this) minPoolCount(uint32 value) nothrow
    {
        put(DbParameterName.minPoolCount, to!string(value));
        return this;
    }

    @property final uint32 packageSize() const nothrow @safe
    {
        return toInt!uint32(getString(DbParameterName.packageSize));
    }

    @property final typeof(this) packageSize(uint32 value) nothrow
    {
        auto setValue = value != 0 ? to!string(value) : getDefault(DbParameterName.packageSize);
        put(DbParameterName.packageSize, setValue);
        return this;
    }

    @property final bool pooling() const nothrow @safe
    {
        return isDbTrue(getString(DbParameterName.pooling));
    }

    @property final typeof(this) pooling(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbParameterName.pooling, setValue);
        return this;
    }

    @property final Duration poolTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbParameterName.poolTimeout));
    }

    @property final typeof(this) poolTimeout(in Duration value) nothrow
    {
        const setSecond = value.toMinSecond();
        auto setValue = setSecond != 0 ? to!string(setSecond) : getDefault(DbParameterName.poolTimeout);
        put(DbParameterName.poolTimeout, setValue);
        return this;
    }

    @property final uint16 port() const nothrow @safe
    {
        return toInt!uint16(getString(DbParameterName.port));
    }

    @property final typeof(this) port(uint16 value) nothrow
    {
        auto setValue = value != 0 ? to!string(value) : getDefault(DbParameterName.port);
        put(DbParameterName.port, setValue);
        return this;
    }

    /**
     * Gets or sets the time (minimum value based in seconds) to wait for a server to send back request's result.
     * The default value is 3_600 seconds (1 hour).
     * Set to zero to disable the setting.
     */
    @property final Duration receiveTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbParameterName.receiveTimeout));
    }

    @property final typeof(this) receiveTimeout(in Duration value) nothrow
    {
        const setSecond = value.toMinSecond();
        auto setValue = setSecond != 0 ? to!string(setSecond) : getDefault(DbParameterName.receiveTimeout);
        put(DbParameterName.receiveTimeout, setValue);
        return this;
    }

    @property final DbIdentitier roleName() const nothrow @safe
    {
        return DbIdentitier(getString(DbParameterName.roleName));
    }

    @property final typeof(this) roleName(string value) nothrow
    {
        put(DbParameterName.roleName, value);
        return this;
    }

    @property abstract DbIdentitier scheme() const nothrow pure @safe;

    /**
     * Gets or sets the time (minimum value based in seconds) to wait for a request to completely send to server.
     * The default value is 60 seconds.
     * Set to zero to disable the setting.
     */
    @property final Duration sendTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbParameterName.sendTimeout));
    }

    @property final typeof(this) sendTimeout(in Duration value) nothrow
    {
        const setSecond = value.toMinSecond();
        auto setValue = setSecond != 0 ? to!string(setSecond) : getDefault(DbParameterName.sendTimeout);
        put(DbParameterName.sendTimeout, setValue);
        return this;
    }

    /**
     * The name of the database server; value of "server"
     */
    @property final DbIdentitier serverName() const nothrow @safe
    {
        return DbIdentitier(getString(DbParameterName.server));
    }

    @property final typeof(this) serverName(string value) nothrow
    {
        put(DbParameterName.server, value);
        return this;
    }

    /**
     * Returns value of "user"
     */
    @property final DbIdentitier userName() const nothrow @safe
    {
        return DbIdentitier(getString(DbParameterName.userName));
    }

    @property final typeof(this) userName(string value) nothrow
    {
        put(DbParameterName.userName, value);
        return this;
    }

    /**
     * Returns value of "password"
     */
    @property final string userPassword() const nothrow @safe
    {
        return getString(DbParameterName.userPassword);
    }

    @property final typeof(this) userPassword(string value) nothrow
    {
        put(DbParameterName.userPassword, value);
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

    void setDefaultIfs() nothrow @safe
    {
        putIf(DbParameterName.connectionTimeout, getDefault(DbParameterName.connectionTimeout));
        putIf(DbParameterName.encrypt, getDefault(DbParameterName.encrypt));
        putIf(DbParameterName.fetchRecordCount, getDefault(DbParameterName.fetchRecordCount));
        putIf(DbParameterName.maxPoolCount, getDefault(DbParameterName.maxPoolCount));
        putIf(DbParameterName.minPoolCount, getDefault(DbParameterName.minPoolCount));
        putIf(DbParameterName.packageSize, getDefault(DbParameterName.packageSize));
        putIf(DbParameterName.poolTimeout, getDefault(DbParameterName.poolTimeout));
        putIf(DbParameterName.receiveTimeout, getDefault(DbParameterName.receiveTimeout));
        putIf(DbParameterName.sendTimeout, getDefault(DbParameterName.sendTimeout));
        putIf(DbParameterName.pooling, getDefault(DbParameterName.pooling));
        //putIf(, getDefault());
    }

public:
    string forErrorInfoCustom;
    string forLogInfoCustom;

protected:
    char _elementSeparator = ';';
    char _valueSeparator = '=';

private:
    bool[string] _validParamNameChecks;
}

abstract class DbDatabase : DbSimpleNamedObject
{
nothrow @safe:

public:
    abstract DbCommand createCommand(DbConnection connection, string name = null);
    abstract DbConnection createConnection(string connectionString);
    abstract DbConnection createConnection(DbConnectionStringBuilder connectionStringBuilder);
    abstract DbConnectionStringBuilder createConnectionStringBuilder(string connectionString);
    abstract DbField createField(DbCommand command, DbIdentitier name);
    abstract DbFieldList createFieldList(DbCommand command);
    abstract DbParameter createParameter(DbIdentitier name);
    abstract DbParameterList createParameterList();
    abstract DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel, bool defaultTransaction);

    final DbField createField(DbCommand command, string name)
    {
        DbIdentitier id = DbIdentitier(name);
        return createField(command, id);
    }

    final DbParameter createParameter(string name)
    {
        DbIdentitier id = DbIdentitier(name);
        return createParameter(id);
    }

    /**
     * For logging various message & trace
     * Central place to assign to newly created DbConnection
     */
    @property Logger logger() nothrow @trusted //@trusted=cast()
    {
        import core.atomic : atomicLoad,  MemoryOrder;

        return cast(Logger)atomicLoad!(MemoryOrder.acq)(_logger);
    }

    @property DbDatabase logger(Logger logger) nothrow @trusted //@trusted=cast()
    {
        import core.atomic : atomicStore,  MemoryOrder;

        atomicStore!(MemoryOrder.rel)(_logger, cast(shared)logger);
        return this;
    }

    /**
     * Name of database kind, firebird, postgresql ...
     * Refer pham.db.type.DbScheme for a list of possible values
     */
    @property final DbIdentitier scheme() const pure
    {
        return name;
    }

private:
    shared Logger _logger;
}

// This instance is initialize at startup hence no need Mutex to have thread-guard
class DbDatabaseList : DbSimpleNamedObjectList!DbDatabase
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

    static bool findDb(string scheme, ref DbDatabase database) nothrow @safe
    {
        auto lst = instance();
        return lst.find(scheme, database);
    }

    static DbDatabase getDb(string scheme) @safe
    {
        DbDatabase result;
        if (findDb(scheme, result))
            return result;

        auto msg = format(DbMessage.eInvalidSchemeName, scheme);
        throw new DbException(msg, 0, 0, 0);
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

class DbNamedColumn : DbSimpleNamedObject
{
public:
    /*
     * Indicates if field value is an external resource id which needs special loading/saving
     */
    abstract DbFieldIdType isIdType() const nothrow @safe;

    /**
     * Gets or sets whether value NULL is allowed
     */
    @property final bool allowNull() const nothrow @safe
    {
        return _flags.on(DbSchemaColumnFlag.allowNull);
    }

    @property final typeof(this) allowNull(bool value) nothrow @safe
    {
        _flags.set(DbSchemaColumnFlag.allowNull, value);
        return this;
    }

    /**
     * Gets or sets the id of the column in the schema table
     */
    @property final int32 baseId() const nothrow @safe
    {
        return _baseId;
    }

    @property final typeof(this) baseId(int32 value) nothrow @safe
    {
        _baseId = value;
        return this;
    }

    /**
     * Gets or sets the name of the column in the schema table
     */
    @property final string baseName() const nothrow @safe
    {
        return _baseName.length != 0 ? _baseName : name;
    }

    @property final typeof(this) baseName(string value) nothrow @safe
    {
        _baseName = value;
        return this;
    }

    /**
     * Gets or sets the owner of the column in the schema table
     */
    @property final string baseOwner() const nothrow @safe
    {
        return _baseOwner;
    }

    @property final typeof(this) baseOwner(string value) nothrow @safe
    {
        _baseOwner = value;
        return this;
    }

    /**
     * Gets or sets the name of the schema in the schema table
     */
    @property final string baseSchemaName() const nothrow @safe
    {
        return _baseSchemaName;
    }

    @property final typeof(this) baseSchemaName(string value) nothrow @safe
    {
        _baseSchemaName = value;
        return this;
    }

    /**
     * Gets or sets provider-specific numeric scale of the column
     */
    @property final int32 baseNumericScale() const nothrow @safe
    {
        return _baseType.numericScale;
    }

    @property final typeof(this) baseNumericScale(int value) nothrow @safe
    {
        _baseType.numericScale = value;
        return this;
    }

    /**
     * Gets or sets provider-specific size of the column
     */
    @property final int32 baseSize() const nothrow @safe
    {
        return _baseType.size;
    }

    @property final typeof(this) baseSize(int32 value) nothrow @safe
    {
        _baseType.size = value;
        return this;
    }

    /**
     * Gets or sets provider-specific subtype of the column
     */
    @property final int32 baseSubTypeId() const nothrow @safe
    {
        return _baseType.subTypeId;
    }

    @property final typeof(this) baseSubTypeId(int32 value) nothrow @safe
    {
        _baseType.subTypeId = value;
        return this;
    }

    /**
     * Gets or sets the name of the table in the schema table
     */
    @property final string baseTableName() const nothrow @safe
    {
        return _baseTableName;
    }

    @property final typeof(this) baseTableName(string value) nothrow @safe
    {
        _baseTableName = value;
        return this;
    }

    /**
     * Gets or sets the id of the table in the schema table
     */
    @property final int32 baseTableId() const nothrow @safe
    {
        return _baseTableId;
    }

    @property final typeof(this) baseTableId(int32 value) nothrow @safe
    {
        _baseTableId = value;
        return this;
    }

    /**
     * Gets or sets provider-specific data type of the column
     */
    @property final DbBaseType baseType() nothrow pure @safe
    {
        return _baseType;
    }

    /**
     * Gets or sets provider-specific data type of the column
     */
    @property final int32 baseTypeId() const nothrow @safe
    {
        return _baseType.typeId;
    }

    @property final typeof(this) baseTypeId(int32 value) nothrow @safe
    {
        _baseType.typeId = value;
        return this;
    }

    @property bool isArray() const nothrow @safe
    {
        return (_type & DbType.array) != 0;
    }

    @property final typeof(this) isArray(bool value) nothrow @safe
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
    @property final uint32 ordinal() const nothrow @safe
    {
        return _ordinal;
    }

    @property final typeof(this) ordinal(uint32 value) nothrow @safe
    {
        _ordinal = value;
        return this;
    }

    /**
     * Gets or sets maximum size, in bytes of the parameter
     * used for array, binary, fixedBinary, utf8String, fixedUtf8String
     * json, and xml types.
     */
    @property final int32 size() const nothrow @safe
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
    @property final DbType type() const nothrow @safe
    {
        return _type & ~DbType.array;
    }

    @property final typeof(this) type(DbType value) nothrow @safe
    {
        // Maintain the array flag
         _type = isArray ? value | DbType.array : value;

         if (!isDbTypeHasSize(_type))
             _size = 0;

        return this;
    }

protected:
    void assignTo(DbNamedColumn dest) nothrow @safe
    {
        version (none)
        foreach (m; __traits(allMembers, DbNamedColumn))
        {
            static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m).dup)))
                __traits(getMember, ret, m) = __traits(getMember, this, m).dup;
            else static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m))))
                __traits(getMember, ret, m) = __traits(getMember, this, m);
        }

        foreach (m; FieldNameTuple!DbNamedColumn)
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

class DbField : DbNamedColumn
{
public:
    this(DbCommand command, DbIdentitier name) nothrow @safe
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

class DbFieldList : DbSimpleNamedObjectList!DbField, IDisposable
{
public:
    this(DbCommand command) nothrow @safe
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
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing++;
        doDispose(disposing);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
    }

    final void dispose() nothrow @safe
    {
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing++;
        doDispose(true);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
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

class DbParameter : DbNamedColumn
{
public:
    this(DbDatabase database, DbIdentitier name) nothrow @safe
    {
        this._name = name;
        this._flags.set(DbSchemaColumnFlag.allowNull, true);
    }

    final bool isInput() const nothrow @safe
    {
        return direction == DbParameterDirection.input
            || direction == DbParameterDirection.inputOutput;
    }

    final bool isOutput(bool outputOnly) const nothrow @safe
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
    @property final DbParameterDirection direction() const nothrow @safe
    {
        return _direction;
    }

    @property final DbParameter direction(DbParameterDirection value) nothrow @safe
    {
        _direction = value;
        return this;
    }

    @property final Variant val() @safe
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
    override void assignTo(DbNamedColumn dest) nothrow @safe
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

class DbParameterList : DbSimpleNamedObjectList!DbParameter, IDisposable
{
public:
    this(DbDatabase database) nothrow @safe
    {
        this._database = database;
    }

    DbParameter add(DbIdentitier name, DbType type,
        int32 size = 0,
        DbParameterDirection direction = DbParameterDirection.input) nothrow @safe
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
        return add(id, type, size, direction);
    }

    final DbParameter addClone(DbParameter source) @safe
    {
        auto result = add(source.name, source.type, source.size, source.direction);
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
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing++;
        doDispose(disposing);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
    }

    final void dispose() nothrow @safe
    {
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing++;
        doDispose(true);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
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
            if (result.isOutput(false))
            {
                if (outIndex++ == outputIndex)
                    return result;
            }
        }
        return null;
    }

    final size_t inputCount() nothrow @safe
    {
        size_t result = 0;
        foreach(parameter; this)
        {
            if (parameter.isInput())
                result++;
        }
        return result;
    }

    final DbParameter[] inputParameters() nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        const count = inputCount();
        if (count == 0)
            return null;
        else
        {
            size_t i = 0;
            auto result = new DbParameter[](count);
            foreach(parameter; this)
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
            if (parameter.isOutput(Yes.outputOnly))
                parameter.nullifyValue();
        }
        return this;
    }

    final size_t outputCount(bool outputOnly) nothrow @safe
    {
        size_t result = 0;
        foreach(parameter; this)
        {
            if (parameter.isOutput(outputOnly))
                result++;
        }
        return result;
    }

    /*
     * Search for existing parameter matched with name; if not found, add it
     */
    DbParameter touch(DbIdentitier name, DbType type,
        int32 size = 0,
        DbParameterDirection direction = DbParameterDirection.input) nothrow @safe
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
            return add(name, type, size, direction);
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
        return touch(id, type, size, direction);
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

struct DbReader
{
public:
    @disable this(this);

    this(DbCommand command, bool implicitTransaction) nothrow @safe
    {
        this._command = command;
        this._fields = command.fields;
        this._hasRows = HasRows.unknown;
        this._implicitTransaction = implicitTransaction;
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
        version (TraceFunction) dgFunctionTrace();

        _allRowsFetched = true;
        if (_hasRows == HasRows.unknown)
            _hasRows = HasRows.no;

        if (_cacheResult && _hasRows == HasRows.yes && _command !is null)
        {
            _fields = _command.fields.clone(null);
        }
        else
        {
            _fields = null;
            _currentRow.nullify();
        }

        doDetach(false);

        return this;
    }

    void dispose(bool disposing = true) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_command !is null)
            doDetach(disposing);

        _fields = null;
        _fetchedCount = 0;
        _hasRows = HasRows.no;
        _allRowsFetched = true;
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
    ptrdiff_t getIndex(in DbIdentitier name) nothrow @safe
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

    T getValue(T)(size_t index) nothrow @safe
    in
    {
        assert(index < _currentRow.length);
    }
    do
    {
        return getVariant(index).get!T();
    }

    /**
     * Gets the Variant of the specified column name
     */
    Variant getValue(string name) @safe
    {
        const index = fields.indexOfSafe(name);
        return getValue(index);
    }

    /**
     * Gets a value that indicates whether this DbReader contains one or more rows
     */
    bool hasRows() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_hasRows == HasRows.unknown)
        {
            fetchNext();
            _skipFetchNext = true;
        }

        version (TraceFunction) dgFunctionTrace("_hasRows=", _hasRows, ", _skipFetchNext=", _skipFetchNext);

        return _hasRows == HasRows.yes;
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

    /**
     * Advances this DbReader to the next record in a result set
     */
    bool read() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (!_allRowsFetched)
        {
            if (!_skipFetchNext)
                fetchNext();
            _skipFetchNext = false;
        }

        version (TraceFunction) dgFunctionTrace("_allRowsFetched=", _allRowsFetched, ", _skipFetchNext=", _skipFetchNext);

        return !_allRowsFetched;
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

    @property DbFieldList fields() nothrow pure @safe
    {
        return _fields;
    }

    @property bool implicitTransaction() nothrow pure @safe
    {
        return _implicitTransaction;
    }

private:
    enum HasRows : byte
    {
        unknown,
        no,
        yes
    }

    void doDetach(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _command.removeReader(this);
        _command = null;
    }

    void fetchNext() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _currentRow = command.fetch(false);
        _allRowsFetched = _currentRow.length == 0;
        _fetchedCount++;
        if (_hasRows == HasRows.unknown)
            _hasRows = _allRowsFetched ? HasRows.no : HasRows.yes;

        version (TraceFunction) dgFunctionTrace("_fetchedCount=", _fetchedCount, ", _allRowsFetched=", _allRowsFetched, ", _hasRows=", _hasRows);
    }

    Variant getVariant(const size_t index) @safe
    {
        auto field = fields[index];
        final switch (field.isIdType())
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
    HasRows _hasRows;
    bool _allRowsFetched, _cacheResult, _implicitTransaction, _skipFetchNext;
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
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

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
    @property final bool autoCommit() const nothrow @safe
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

    @property final DbHandle handle() const nothrow @safe
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
    @property final DbIsolationLevel isolationLevel() const nothrow @safe
    {
        return _isolationLevel;
    }

    @property final bool isRetaining() const nothrow @safe
    {
        return _flags.on(DbTransactionFlag.retaining);
    }

    @property final DbLockTable[] lockedTables() nothrow @safe
    {
        return _lockedTables;
    }

    /**
     * Default value is 60 seconds
     */
    @property final Duration lockTimeout() const nothrow @safe
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
    @property final bool readOnly() const nothrow @safe
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
    @property final DbTransactionState state() const nothrow @safe
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
        version (TraceFunction) dgFunctionTrace("checkingState=", checkingState, ", callerName=", callerName);

        if (_state != checkingState)
        {
            auto msg = format(DbMessage.eInvalidTransactionState, callerName, toName!DbTransactionState(_state), toName!DbTransactionState(checkingState));
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }

        if (_connection is null)
        {
            auto msg = format(DbMessage.eCompletedTransaction, callerName);
            throw new DbException(msg, 0, 0, 0);
        }
    }

    final void complete(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace("disposing=", disposing);

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
