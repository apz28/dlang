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

import core.sync.mutex : Mutex;
public import core.time : Duration;
import std.array : Appender;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.experimental.logger : logError = error;
import std.format : format;
import std.traits; // : allMembers, getMember;
import std.typecons : Flag, No, Yes;

version (unittest) import pham.utl.utltest;
import pham.utl.delegate_list;
import pham.utl.dlink_list;
import pham.utl.enum_set;
import pham.utl.utlobject;
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

        checkCommand();
        const wasPrepared = prepared;
        resetNewStatement(ResetStatementKind.execute);
        const implicitTransaction = setImplicitTransactionIf();
        scope (failure)
        {
            if (implicitTransaction)
                resetImplicitTransactionIf(cast(ResetImplicitTransactiontFlag)(ResetImplicitTransactiontFlag.error | ResetImplicitTransactiontFlag.nonQuery));
            if (!wasPrepared && prepared)
                unprepare();
        }
        doExecuteCommand(DbCommandExecuteType.nonQuery);
        auto result = recordsAffected;
        if (implicitTransaction)
            resetImplicitTransactionIf(ResetImplicitTransactiontFlag.nonQuery);
        if (!wasPrepared && prepared)
            unprepare();
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
        doExecuteCommand(DbCommandExecuteType.scalar);
        auto values = fetch(true);
        if (implicitTransaction)
            resetImplicitTransactionIf(ResetImplicitTransactiontFlag.none);
        if (!wasPrepared && prepared)
            unprepare();
        return values ? values[0] : DbValue.dbNull();
    }

    abstract DbRowValue fetch(bool isScalar) @safe;

    abstract string getExecutionPlan(uint vendorMode = 0);

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
            _executeCommandText = buildExecuteCommandText();
            doPrepare(_executeCommandText);
            _commandState = DbCommandState.prepared;
        }
        catch (Exception e)
        {
            //todo logError(e.message);
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
        return writeBlob(clobColumn, cast(const(ubyte)[])clobValue, optionalClobValueId);
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

        parametersCheck(false);
        return doCommandText(value, DbCommandType.text);
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

        final switch (commandType)
        {
            case DbCommandType.text:
                return buildTextSql(commandText);
            case DbCommandType.storedProcedure:
                return buildStoredProcedureSql(commandText);
            case DbCommandType.table:
                return buildTableSql(commandText);
        }
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

        scope (failure)
            assert(0);

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

        string result;
        if (parametersCheck)
            result = parseParameter(sql, &buildParameterNameCallback);
        else
            result = sql;

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

        //TODO unprepare();

        if (_fields !is null)
        {
            _fields.disposal(disposing);
            _fields = null;
        }

        if (_parameters !is null)
        {
            _parameters.disposal(disposing);
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

        _commandText = null;
        _commandState = DbCommandState.closed;
        _executeCommandText = null;
        _baseCommandType = 0;
        _handle.reset();
    }

    final bool needPrepare(DbCommandExecuteType type) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        return commandType != DbCommandType.table &&
            !prepared &&
            (parametersCheck || hasParameters);
    }

    void prepareExecute(DbCommandExecuteType type) @safe
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        _recordsAffected.reset();
        allRowsFetched(false);

        if (hasParameters)
            parameters.nullifyOutputParameters();

        if (_executeCommandText.length == 0)
            _executeCommandText = buildExecuteCommandText();
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
                    //todo logError(e.message);
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
    abstract void doPrepare(string sql) @safe;
    abstract void doUnprepare() @safe;
    abstract bool isSelectCommandType() const nothrow @safe;

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

abstract class DbConnection : DbDisposableObject
{
public:
    mixin DLinkTypes!(DbCommand) DLinkDbCommandTypes;
    mixin DLinkTypes!(DbTransaction) DLinkDbTransactionTypes;

public:
    this(DbDatabase database) nothrow @safe
    {
        _database = database;
        _connectionStringBuilder = database.createConnectionStringBuilder(null);
    }

    this(DbDatabase database, string connectionString) nothrow @safe
    {
        this(database);
        setConnectionString(connectionString);
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
        disposeTransactions(true);
        disposeCommands(true);
        doClose();
    }

    final DLinkDbCommandTypes.Range commands()
    {
        return DLinkDbCommandTypes.Range(_commands);
    }

    final DbCommand createCommand(string name = null) @safe
    {
        version (TraceFunction) dgFunctionTrace();

        checkActive();
        auto result = database.createCommand(this, name);
        return DLinkCommandLastFunctions.insertEnd(_commands, result);
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

    final override size_t toHash() nothrow @safe
    {
        return connectionStringBuilder.toHash().hashOf(scheme.toHash());
    }

    final DLinkDbTransactionTypes.Range transactions()
    {
        return DLinkDbTransactionTypes.Range(_transactions);
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
    @property final bool hasCommands() const nothrow @safe
    {
        return _commands !is null;
    }

    /**
     * Returns true if this connection has any DbTransaction
     */
    @property final bool hasTransactions() const nothrow @safe
    {
        return _transactions !is null;
    }

	/**
     * Gets the indicator of current state of the connection
	 */
    @property final DbConnectionState state() const nothrow @safe
    {
        return _state;
    }

    @property abstract DbIdentitier scheme() const nothrow @safe;

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

        auto result = database.createTransaction(this, isolationLevel, defaultTransaction);
        return DLinkTransactionLastFunctions.insertEnd(_transactions, result);
    }

    void disposeCommands(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        while (_commands !is null)
        {
            auto t = _commands;
            // Must unhook before calling dispose
            DLinkCommandLastFunctions.remove(_commands, t);
            t.disposal(disposing);
        }
    }

    void disposeTransactions(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _defaultTransaction = null;
        while (_transactions !is null)
        {
            auto t = _transactions;
            // Must unhook before calling dispose
            DLinkTransactionLastFunctions.remove(_transactions, t);
            t.disposal(disposing);
        }
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

        void doCloseSafe() nothrow @trusted
        {
            try
            {
                doClose();
            }
            catch (Exception e)
            {
                //todo log
            }
        }

        beginStateChanges.clear();
        endStateChanges.clear();
        serverInfo = null;
        _list = null;

        disposeCommands(disposing);
        disposeTransactions(disposing);
        if (state == DbConnectionState.open)
            doCloseSafe();

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
                DLinkCommandLastFunctions.remove(_commands, value);
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
                DLinkTransactionLastFunctions.remove(_transactions, value);
        }
    }

    void setConnectionString(string value) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        connectionStringBuilder().parseConnectionString(value);
    }

    abstract void doCancelCommand();
    abstract void doClose();
    abstract void doOpen();

private:
    mixin DLinkFunctions!(DbCommand) DLinkCommandLastFunctions;
    mixin DLinkFunctions!(DbTransaction) DLinkTransactionLastFunctions;

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

protected:
    DbDatabase _database;
    DbConnectionList _list;
    DbTransaction _defaultTransaction;
    DbHandle _handle;
    size_t _nextCounter;
    DbConnectionState _state;

private:
    DbCommand _commands;
    DbConnectionStringBuilder _connectionStringBuilder;
    DbTransaction _transactions;

private:
    DbConnection _next;
    DbConnection _prev;
}

class DbConnectionList : DbDisposableObject
{
public:
    // Range
    mixin DLinkTypes!(DbConnection) DLinkDbConnectionTypes;

public:
    this(DbDatabase database, DbConnectionPool pool)
    {
        this._database = database;
        this._pool = pool;
    }

    final DLinkDbConnectionTypes.Range opSlice() nothrow @safe
    {
        return DLinkDbConnectionTypes.Range(_connections);
    }

    final DbConnection acquire(out bool created) @safe
    {
        if (_connections !is null)
        {
            --_length;
            created = false;
            auto result = _connections;
            DLinkConnectionLastFunctions.remove(_connections, result);
            result.doPool(false);
            return result;
        }
        else
        {
            created = true;
            auto result = database.createConnection(connectionString);
            result._list = this;
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
                return disposeConnection(item, null);
            else
            {
                auto lst = item.list;
                return lst.disposeConnection(item, lst);
            }
        }

        try
        {
            item.doPool(true);
        }
        catch (Exception e)
        {
            disposeConnection(item, this);
            throw e; // rethrow
        }
        ++_length;
        DLinkConnectionLastFunctions.insertEnd(_connections, item);

        return null;
    }

    @property final string connectionString() const nothrow pure @safe
    {
        return _connectionString;
    }

    @property final typeof(this) connectionString(string value) nothrow @safe
    in
    {
        assert(length == 0);
    }
    do
    {
        _connectionString = value;
        return this;
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
    final DbConnection disposeConnection(DbConnection item, Object caller) @safe
    in
    {
        assert(item !is null);
    }
    do
    {
        static void minusAcquiredLength(DbConnectionPool pool) nothrow @trusted
        {
            _lock.lock_nothrow();
            pool._acquiredLength--;
            _lock.unlock_nothrow();
        }

        if (caller is this && item.list !is null && item.list.pool !is null)
            minusAcquiredLength(item.list.pool);

        item._list = null;
        item.dispose();
        return null;
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        while (_connections !is null)
        {
            auto t = _connections;
            DLinkConnectionLastFunctions.remove(_connections, t);
            t.disposal(disposing);
        }
        _length = 0;
        _database = null;
        _pool = null;
    }

private:
    mixin DLinkFunctions!(DbConnection) DLinkConnectionLastFunctions;

protected:
    string _connectionString;
    DbConnection _connections;
    DbDatabase _database;
    DbConnectionPool _pool;
    size_t _length;
}

class DbConnectionPool : DbDisposableObject
{
public:
    this(size_t maxLength = DbDefaultSize.connectionPoolLength) nothrow pure @safe
    {
        this._maxLength = maxLength;
    }

    final DbConnection acquire(string scheme, string connectionString)
    {
        auto database = DbDatabaseList.getRegister(scheme);

        _lock.lock_nothrow();
        scope (exit)
            _lock.unlock_nothrow();

        if (_acquiredLength >= _maxLength)
        {
            auto msg = format(DbMessage.eInvalidConnectionPoolMaxUsed, _acquiredLength, _maxLength);
            throw new DbException(msg, DbErrorCode.connect, 0, 0);
        }

        auto lst = schemeConnections(database);
        if (lst.length == 0)
            lst.connectionString = connectionString;
        bool created;
        auto result = lst.acquire(created);
        _acquiredLength++;
        if (!created)
            _length--;
        return result;
    }

    static void cleanup()
    {
        if (_instance !is null)
        {
            _instance.dispose();
            _instance = null;
        }
    }

    static DbConnectionPool instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    final DbConnection release(DbConnection item)
    in
    {
        assert(item !is null);
    }
    do
    {
        _lock.lock_nothrow();
        scope (exit)
            _lock.unlock_nothrow();

        auto lst = item.list;
        if (lst is null)
        {
            item.dispose();
            return null;
        }
        if (lst.pool !is this)
        {
            lst.disposeConnection(item, lst);
            return null;
        }

        _acquiredLength--;
        if (_length + 1 >= _maxLength)
        {
            lst.disposeConnection(item, this);
        }
        else
        {
            lst.release(item);
            _length++;
        }

        return null;
    }

    @property final size_t acquiredLength() const nothrow
    {
        return _acquiredLength;
    }

    @property final size_t length() const nothrow
    {
        return _length;
    }

    @property final size_t maxLength() const nothrow
    {
        return _maxLength;
    }

    @property final typeof(this) maxLength(size_t value)
    {
        _lock.lock_nothrow();
        scope (exit)
            _lock.unlock_nothrow();

        _maxLength = value;
        return this;
    }

protected:
    static DbConnectionPool createInstance() nothrow pure @safe
    {
        return new DbConnectionPool();
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        scope (failure)
            assert(0);

        foreach (_, lst; _schemeConnections)
            lst.disposal(disposing);
        _schemeConnections = null;
        _acquiredLength = 0;
        _length = 0;
    }

    final DbConnectionList schemeConnections(DbDatabase database)
    {
        if (auto e = database.scheme in _schemeConnections)
            return (*e);
        else
        {
            auto result = new DbConnectionList(database, this);
            _schemeConnections[database.scheme] = result;
            return result;
        }
    }

private:
    DbConnectionList[DbIdentitier] _schemeConnections;
    size_t _acquiredLength, _length;
    size_t _maxLength;
    __gshared static DbConnectionPool _instance;
}

abstract class DbConnectionStringBuilder : DbNameValueList!string
{
public:
    this(string connectionString) nothrow @safe
    {
        parseConnectionString(connectionString);
    }

    final string forErrorInfo() const nothrow @safe
    {
        return serverName ~ ":" ~ databaseName;
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
        auto setValue = value ? dbBoolTrues[0] : dbBoolFalses[0];
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

    @property final typeof(this) connectionTimeout(Duration value) nothrow
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
        auto setValue = value ? dbBoolTrues[0] : dbBoolFalses[0];
        put(DbParameterName.pooling, setValue);
        return this;
    }

    @property final Duration poolTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbParameterName.poolTimeout));
    }

    @property final typeof(this) poolTimeout(Duration value) nothrow
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

    @property final typeof(this) receiveTimeout(Duration value) nothrow
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

    @property abstract DbIdentitier scheme() const nothrow @safe;

    /**
     * Gets or sets the time (minimum value based in seconds) to wait for a request to completely send to server.
     * The default value is 60 seconds.
     * Set to zero to disable the setting.
     */
    @property final Duration sendTimeout() const nothrow @safe
    {
        return secondToDuration(getString(DbParameterName.sendTimeout));
    }

    @property final typeof(this) sendTimeout(Duration value) nothrow
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
    abstract DbConnectionStringBuilder createConnectionStringBuilder(string connectionString);
    abstract DbField createField(DbCommand command);
    abstract DbFieldList createFieldList(DbCommand command);
    abstract DbParameter createParameter();
    abstract DbParameterList createParameterList();
    abstract DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel, bool defaultTransaction);

    @property final DbIdentitier scheme() const
    {
        return name;
    }
}

class DbDatabaseList : DbSimpleNamedObjectList!DbDatabase
{
public:
    static DbDatabase getRegister(string scheme)
    {
        DbDatabase result;
        auto lst = instance();
        if (!lst.find(scheme, result))
        {
            auto msg = format(DbMessage.eInvalidSchemeName, scheme);
            throw new DbException(msg, 0, 0, 0);
        }
        return result;
    }

    static DbDatabaseList instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    static void register(DbDatabase database)
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

    static void cleanup()
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
    this(DbCommand command) nothrow @safe
    {
        this._command = command;
        _flags.set(DbSchemaColumnFlag.allowNull, true);
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

    ~this()
    {
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing = byte.min; // Set to min avoid ++ then --
        doDispose(false);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
    }

    final typeof(this) clone(DbCommand command) nothrow @safe
    {
        auto result = createSelf(command);
        foreach (field; this)
            result.add(field.clone(command));
        return result;
    }

    abstract DbField createField(DbCommand command) nothrow @safe;
    abstract DbFieldList createSelf(DbCommand command) nothrow @safe;

    final void disposal(bool disposing) nothrow @safe
    {
        if (!disposing)
            _disposing = byte.min; // Set to min avoid ++ then --

        _disposing++;
        scope (exit)
            _disposing--;

        doDispose(disposing);
    }

    final void dispose() nothrow @safe
    {
        version (TraceFunction)
        if (disposingState != DisposableState.destructing)
            dgFunctionTrace();

        _disposing++;
        scope (exit)
            _disposing--;

        doDispose(true);
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
    this(DbDatabase database) nothrow @safe
    {
        _flags.set(DbSchemaColumnFlag.allowNull, true);
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

    /**
     * Gets or sets the value of the parameter
     */
    @property final ref DbValue value() return @safe
    {
        return _value;
    }

    @property final DbParameter value(DbValue value) @safe
    {
        _value = value;

        if (type == DbType.unknown && value.type != DbType.unknown)
        {
            if (isDbTypeHasSize(value.type) && value.hasSize)
                size = value.size;
            type = value.type;
            reevaluateBaseType();
        }

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
            destP._value = _value;
        }
    }

protected:
    final void nullifyValue() nothrow @safe
    {
        _value.nullify();
    }

protected:
    DbValue _value;
    DbParameterDirection _direction;
}

class DbParameterList : DbSimpleNamedObjectList!DbParameter, IDisposable
{
public:
    this(DbDatabase database) nothrow @safe
    {
        this._database = database;
    }

    ~this()
    {
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing = byte.min; // Set to min avoid ++ then --
        doDispose(false);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
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
        auto id = DbIdentitier(name);
        return add(id, type, size, direction);
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
        auto result = database.createParameter();
        result.name = name;
        result.type = type;
        result.size = size;
        result.direction = direction;
        put(result);
        return result;
    }

    final DbParameter addClone(DbParameter source) @safe
    {
        auto result = add(source.name, source.type, source.size, source.direction);
        source.assignTo(result);
        return result;
    }

    final DbParameter createParameter() nothrow @safe
    {
        return database.createParameter();
    }

    final void disposal(bool disposing) nothrow @safe
    {
        if (!disposing)
            _disposing = byte.min; // Set to min avoid ++ then --

        _disposing++;
        scope (exit)
            _disposing--;

        doDispose(disposing);
    }

    final void dispose() nothrow @safe
    {
        version (TraceFunction)
        if (disposingState != DisposableState.destructing)
            dgFunctionTrace();

        _disposing++;
        scope (exit)
            _disposing--;

        doDispose(true);
    }

    final DbIdentitier generateParameterName() nothrow @safe
    {
        return generateUniqueName("parameter");
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
    final DbParameter touch(string name, DbType type,
        int32 size = 0,
        DbParameterDirection direction = DbParameterDirection.input) nothrow @safe
    in
    {
        assert(name.length != 0);
    }
    do
    {
        auto id = DbIdentitier(name);
        return touch(id, type, size, direction);
    }

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
        version (TraceFunction)
        if (disposing)
            dgFunctionTrace();

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

        scope (failure)
            _state = DbTransactionState.error;

        doCommit(false);
        if (!handle)
            _state = DbTransactionState.inactive;

        return this;
    }

    /**
     * Performs a rollback for this transaction
	 */
    final typeof(this) rollback() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (state == DbTransactionState.active)
        {
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
        if (state == DbTransactionState.active)
        {
            try
            {
                () @trusted
                {
                    if (autoCommit)
                        doCommit(disposing);
                    else
                        doRollback(disposing);
                } ();
            }
            catch (Exception)
            {
                //todo log
            }
        }

        complete(disposing);
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


// Any below codes are private
private:


__gshared static Mutex _lock;

shared static this()
{
    _lock = new Mutex();
}

shared static ~this()
{
    DbConnectionPool.cleanup();
    DbDatabaseList.cleanup();

    if (_lock !is null)
    {
        _lock.destroy();
        _lock = null;
    }
}