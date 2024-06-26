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

module pham.db.db_database;

import core.atomic : atomicFetchAdd, atomicFetchSub, atomicLoad, atomicStore, cas;
import core.sync.mutex : Mutex;
public import core.time : Duration, dur;
import std.array : Appender;
public import std.ascii : newline;
import std.conv : to;
import std.format : format;
import std.traits : FieldNameTuple;
import std.typecons : Flag, No, Yes;

debug(debug_pham_db_db_database) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.std.log.log_logger : Logger, LogLevel;
import pham.utl.utl_delegate_list;
import pham.utl.utl_dlink_list;
import pham.utl.utl_enum_set : EnumSet, toEnum, toName;
import pham.utl.utl_disposable;
import pham.utl.utl_object : RAIIMutex, singleton;
import pham.utl.utl_system : currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.utl.utl_timer;
import pham.utl.utl_utf8 : encodeUTF8, encodeUTF8MaxLength, nextUTF8Char;
import pham.db.db_convert;
public import pham.db.db_exception;
import pham.db.db_message;
import pham.db.db_object;
import pham.db.db_parser;
public import pham.db.db_type;
import pham.db.db_util;
public import pham.db.db_value;

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

package(pham.db) enum BuildCommandTextState : ubyte
{
    prepare,
    executingPlan,
    execute,
}

package(pham.db) enum ResetStatementKind : ubyte
{
    unpreparing,
    preparing,
    executing,
    fetching,
    fetched,
}

abstract class DbCommand : DbDisposableObject
{
public:
    this(DbConnection connection, string name = null) nothrow @safe
    in
    {
        assert(connection !is null);
    }
    do
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
    in
    {
        assert(connection !is null);
    }
    do
    {
        this(connection, name);
        this._transaction = transaction;
        this._flags.set(DbCommandFlag.implicitTransaction, transaction is null);
    }

    final typeof(this) cancel() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.command.cancel()%s%s", forLogInfo(), newline, commandText);

        checkActive();

        _connection.cancelCommand(this);
        return this;
    }

    pragma(inline, true)
    final Logger canErrorLog() nothrow @safe
    {
        return _connection !is null ? _connection.canErrorLog() : null;
    }

    pragma(inline, true)
    final Logger canTimeLog() nothrow @safe
    {
        return _connection !is null ? _connection.canTimeLog() : null;
    }

    pragma(inline, true)
    final Logger canTraceLog() nothrow @safe
    {
        return _connection !is null ? _connection.canTraceLog() : null;
    }

    final typeof(this) clearFields() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_fields !is null)
            _fields.clear();

        return this;
    }

    final typeof(this) clearParameters() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_parameters !is null)
            _parameters.clear();

        return this;
    }

    final DbRecordsAffected executeNonQuery() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.command.executeNonQuery()%s%s", forLogInfo(), newline, commandText);

        checkCommand(-1);
        resetNewStatement(ResetStatementKind.executing);

        auto executePrep = ExecutePrep(this, DbCommandExecuteType.nonQuery);
        executePrep.resetTransaction = setImplicitTransactionIf(DbCommandExecuteType.nonQuery);
        executePrep.resetPrepare = setImplicitPrepareIf(DbCommandExecuteType.nonQuery);
        scope (exit)
        {
            executePrep.reset(false);
            doNotifyMessage();
        }
        scope (failure)
            executePrep.reset(true);

        doExecuteCommand(DbCommandExecuteType.nonQuery);
        return recordsAffected;
    }

    final DbReader executeReader() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        return executeReaderImpl(false);
    }
    
    final DbValue executeScalar() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.command.executeScalar()%s%s", forLogInfo(), newline, commandText);

        checkCommand(DbCommandType.ddl);
        resetNewStatement(ResetStatementKind.executing);

        auto executePrep = ExecutePrep(this, DbCommandExecuteType.scalar);
        executePrep.resetTransaction = setImplicitTransactionIf(DbCommandExecuteType.scalar);
        executePrep.resetPrepare = setImplicitPrepareIf(DbCommandExecuteType.scalar);
        scope (exit)
        {
            executePrep.reset(false);
            doNotifyMessage();
        }
        scope (failure)
            executePrep.reset(true);

        doExecuteCommand(DbCommandExecuteType.scalar);
        auto values = fetch(true);
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
    final DbRowValue fetch(const(bool) isScalar) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ")");
        version(profile) debug auto p = PerfFunction.create();

        if (auto log = canTraceLog())
            log.infof("%s.command.fetch()%s%s", forLogInfo(), newline, commandText);

        checkActive();

		if (isStoredProcedure)
            return _fetchedRows ? _fetchedRows.dequeue() : DbRowValue(0);

        if (_fetchedRows.empty && !allRowsFetched && isSelectCommandType())
        {
            resetNewStatement(ResetStatementKind.fetching);
            scope (exit)
            {
                _fetchedCount++;
                resetNewStatement(ResetStatementKind.fetched);
            }

            doFetch(isScalar);
        }

        return _fetchedRows ? _fetchedRows.dequeue() : DbRowValue(0);
    }

    final string forErrorInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forErrorInfo() : null;
    }

    final string forLogInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    abstract string getExecutionPlan(uint vendorMode = 0) @safe;

    final T[] inputParameters(T : DbParameter)(const(bool) inputOnly = false) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        return hasParameters ? parameters.inputs!T(inputOnly) : null;
    }

    final T[] outParameters(T : DbParameter)(const(bool) outputOnly = false) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        return hasParameters ? parameters.outputs!T(outputOnly) : null;
    }

    final typeof(this) prepare() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");
        assert(!prepared, "command already prepared");

        if (auto log = canTraceLog())
            log.infof("%s.command.prepare()%s%s", forLogInfo(), newline, commandText);

        if (prepared)
            return this;

        checkCommand(-1);
        resetNewStatement(ResetStatementKind.preparing);

        auto executePrep = ExecutePrep(this, DbCommandExecuteType.prepare);
        executePrep.resetTransaction = setImplicitTransactionIf(DbCommandExecuteType.prepare);
        scope (exit)
            doNotifyMessage();
        scope (failure)
        {
            _commandState = DbCommandState.error;
            executePrep.reset(true);
        }

        try
        {
            doPrepare();
            _commandState = DbCommandState.prepared;
            _flags.set(DbCommandFlag.prepared, true);
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.command.prepare() - %s%s%s", forLogInfo(), e.msg, newline, _executeCommandText, e);
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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.command.unprepare()%s%s", forLogInfo(), newline, commandText);

        void unprepareExit() @safe
        {
            resetNewStatement(ResetStatementKind.unpreparing);

            _executeCommandText = null;
            _lastInsertedId.reset();
            _recordsAffected.reset();
            _handle.reset();
            _baseCommandType = 0;
            _flags.set(DbCommandFlag.prepared, false);
            _commandState = DbCommandState.unprepared;
        }

        if (_connection !is null && _connection.isFatalError)
        {
            unprepareExit();
            return this;
        }

        checkActiveReader();

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
            unprepareExit();
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

    @property final bool activeReader() const nothrow pure @safe
    {
        return _activeReader;
    }

    @property final bool allRowsFetched() const nothrow @safe
    {
        return _flags.on(DbCommandFlag.allRowsFetched);
    }

    @property final int baseCommandType() const nothrow @safe
    {
        return _baseCommandType;
    }

    @property final bool batched() const nothrow pure @safe
    {
        return _flags.on(DbCommandFlag.batched);
    }

    @property final DbCommandState commandState() const nothrow @safe
    {
        return _commandState;
    }

    @property final typeof(this) commandDDL(string value) @safe
    {
        checkActiveReader();

        return setCommandText(value, DbCommandType.ddl);
    }

    @property final typeof(this) commandStoredProcedure(string storedProcedureName) @safe
    {
        checkActiveReader();

        return setCommandText(storedProcedureName, DbCommandType.storedProcedure);
    }

    @property final typeof(this) commandTable(string tableName) @safe
    {
        checkActiveReader();

        return setCommandText(tableName, DbCommandType.table);
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

        return setCommandText(value, DbCommandType.text);
    }

    /**
     * Gets or sets the time to wait for executing
     * a command and generating an error if elapsed
     */
    @property final Duration commandTimeout() const nothrow @safe
    {
        return _commandTimeout;
    }

    @property final typeof(this) commandTimeout(Duration value) nothrow @safe
    {
        _commandTimeout = limitRangeTimeout(value);
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

    @property final bool getExecutionPlanning() const nothrow pure @safe
    {
        return _flags.on(DbCommandFlag.getExecutionPlanning);
    }

    @property final DbHandle handle() const nothrow @safe
    {
        return _handle;
    }

    /**
     * Returns true if this DbCommand has atleast one DbSchemaColumn; otherwise returns false
     */
    @property final size_t hasFields() const nothrow @safe
    {
        return _fields !is null ? _fields.length : 0;
    }

    @property final bool hasInputParameters(const(bool) inputOnly = false) nothrow @safe
    {
        return _parameters !is null ? _parameters.hasInput(inputOnly) : false;
    }

    @property final bool hasOutputParameters(const(bool) outputOnly = false) nothrow @safe
    {
        return _parameters !is null ? _parameters.hasOutput(outputOnly) : false;
    }

    /**
     * Returns count of parameters
     */
    @property final size_t hasParameters() const nothrow @safe
    {
        return _parameters !is null ? _parameters.length : 0;
    }

    @property final bool hasParameters(scope const(EnumSet!DbParameterDirection) directions) const nothrow @safe
    {
        return _parameters !is null ? _parameters.parameterHasOfs(directions) : false;
    }

    /**
     * Gets the inserted id after executed a commandText if applicable
     */
    @property final DbRecordsAffected lastInsertedId() const nothrow @safe
    {
        return _lastInsertedId;
    }

    pragma(inline, true)
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
    Duration logTimmingWarningDur = dur!"seconds"(60);

package(pham.db):
    final DbReader executeReaderImpl(const(bool) ownCommand) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(ownCommand=", ownCommand, ")");

        if (auto log = canTraceLog())
            log.infof("%s.command.executeReader()%s%s", forLogInfo(), newline, commandText);
        
        checkCommand(DbCommandType.ddl);
        resetNewStatement(ResetStatementKind.executing);

        auto executePrep = ExecutePrep(this, DbCommandExecuteType.reader);
        executePrep.resetTransaction = setImplicitTransactionIf(DbCommandExecuteType.reader);
        executePrep.resetPrepare = setImplicitPrepareIf(DbCommandExecuteType.reader);
        scope (exit)
            doNotifyMessage();
        scope (failure)
            executePrep.reset(true);

        doExecuteCommand(DbCommandExecuteType.reader);
        connection._readerCounter++;
        _activeReader = true;
        return DbReader(this, executePrep.resetTransaction, ownCommand);
    }
    
    @property final void allRowsFetched(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.allRowsFetched, value);
    }

    @property final void batched(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.batched, value);
    }

    @property final void getExecutionPlanning(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.getExecutionPlanning, value);
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
    final string buildExecuteCommandText(const(BuildCommandTextState) state) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(state=", state, ")");

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

        if (auto log = canTraceLog())
        {
            if (result != commandText)
                log.infof("%s.command.buildExecuteCommandText()%s%s", forLogInfo(), newline, result);
        }

        return result;
    }

    final void buildParameterNameCallback(ref Appender!string result, string parameterName, uint32 ordinal) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(parameterName=", parameterName, ", ordinal=", ordinal, ")");
        scope (failure) assert(0, "Assume nothrow failed");

        // Construct sql
        result.put(buildParameterPlaceholder(parameterName, ordinal));

        // Create parameter
        auto localParameters = parameters;
        if (localParameters.length == 0)
            localParameters.reserve(20);
        DbParameter found;
        if (parameterName.length == 0)
            found = localParameters.add(format(anonymousParameterNameFmt, ordinal), DbType.unknown);
        else if (!localParameters.find(parameterName, found))
            found = localParameters.add(parameterName, DbType.unknown);
        found.ordinal = ordinal;
    }

    string buildParameterPlaceholder(string parameterName, uint32 ordinal) nothrow @safe
    {
        return "?";
    }

    string buildStoredProcedureSql(string storedProcedureName, const(BuildCommandTextState) state) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ", state=", state, ")");

        if (storedProcedureName.length == 0)
            return null;

        auto params = inputParameters!DbParameter();
        Appender!string result;
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

        debug(debug_pham_db_db_database) debug writeln("\t", "storedProcedureName=", storedProcedureName, ", result=", result.data);

        return result.data;
    }

    string buildTableSql(string tableName, const(BuildCommandTextState) state) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(tableName=", tableName, ", state=", state, ")");

        auto result = tableName.length != 0 ? ("SELECT * FROM " ~ tableName) : null;

        debug(debug_pham_db_db_database) debug writeln("\t", "tableName=", tableName, ", result=", result);

        return result;
    }

    string buildTextSql(string sql, const(BuildCommandTextState) state) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(state=", state, ", sql=", sql, ",");

        // Do not clear to allow parameters to be filled without calling prepare
        // clearParameters();

        auto result = sql.length != 0 && parametersCheck && commandType != DbCommandType.ddl
            ? parseParameter(sql, &buildParameterNameCallback)
            : sql;

        debug(debug_pham_db_db_database) debug writeln("\t", "result=", result);

        return result;
    }

    void checkActive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (!handle)
        {
            auto msg = DbMessage.eInvalidCommandInactive.fmtMessage(funcName);
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }

        if (_connection is null)
        {
            auto msg = DbMessage.eInvalidCommandConnection.fmtMessage(funcName);
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }

        _connection.checkActive(funcName, file, line);
    }

    final void checkActiveReader(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (_activeReader)
            throw new DbException(0, DbMessage.eInvalidCommandActiveReader, null, funcName, file, line);

        connection.checkActiveReader(funcName, file, line);
    }

    void checkCommand(int excludeCommandType,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (_connection is null || _connection.state != DbConnectionState.opened)
            throw new DbException(DbErrorCode.connect, DbMessage.eInvalidCommandConnection, null, funcName, file, line);

        checkActiveReader(funcName, file, line);

        if (_transaction !is null && _transaction.state != DbTransactionState.active)
            transaction = null;

        if (_commandText.length == 0)
            throw new DbException(0, DbMessage.eInvalidCommandText, null, funcName, file, line);

        if (excludeCommandType != -1 && _commandType == excludeCommandType)
        {
            auto msg = DbMessage.eInvalidCommandUnfit.fmtMessage(funcName);
            throw new DbException(0, msg, null, funcName, file, line);
        }

        if (_transaction !is null && _transaction.connection !is _connection)
            throw new DbException(0, DbMessage.eInvalidCommandConnectionDif, null, funcName, file, line);
    }

    final void checkInactive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (handle)
        {
            auto msg = DbMessage.eInvalidCommandActive.fmtMessage(funcName);
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        try
        {
            if (_connection !is null && prepared)
                unprepare();
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.command.doDispose() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
        }

        if (_fields !is null)
        {
            version(none) _fields.dispose(disposingReason);
            _fields = null;
        }

        if (_parameters !is null)
        {
            version(none) _parameters.dispose(disposingReason);
            _parameters = null;
        }

        if (_transaction !is null)
        {
            _transaction = null;
        }

        if (_connection !is null)
        {
            _connection.removeCommand(this);
            if (isDisposing(disposingReason))
                _connection = null;
        }

        _commandState = DbCommandState.closed;
        _commandText = null;
        _executeCommandText = null;
        _baseCommandType = 0;
        _handle.reset();
    }

    bool doExecuteCommandNeedPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        return parametersCheck && hasParameters;
    }

    final void doNotifyMessage() nothrow @trusted
    {
        if (notificationMessages.length == 0)
            return;
        scope (exit)
            notificationMessages.length = 0;

        if (notifyMessage)
        {
            try
            {
                notifyMessage(this, notificationMessages);
            }
            catch (Exception e)
            {
                if (auto log = canErrorLog())
                    log.errorf("%s.command.doNotifyMessage() - %s%s%s", forLogInfo(), e.msg, newline, _executeCommandText, e);
            }
        }
    }

    final string executeCommandText(const(BuildCommandTextState) state) @safe
    {
        if (_executeCommandText.length == 0)
            _executeCommandText = buildExecuteCommandText(state);
        return _executeCommandText;
    }

    bool isSelectCommandType() const nothrow @safe
    {
        return hasFields && !isStoredProcedure;
    }

    final void mergeOutputParams(ref DbRowValue values) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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

    void prepareExecuting(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(type=", type, ")");

        _fetchedCount = 0;
        _lastInsertedId.reset();
        _recordsAffected.reset();
        _fetchedRows.clear();
        allRowsFetched(false);

        executeCommandText(BuildCommandTextState.execute); // Make sure _executeCommandText is initialized
    }

    final void removeReader(ref DbReader value) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_activeReader && value.command is this)
        {
            connection._readerCounter--;
            _activeReader = false;
            removeReaderCompleted(value.implicitTransaction);
        }
    }

    void removeReaderCompleted(const(bool) implicitTransaction) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(implicitTransaction=", implicitTransaction, ")");

        if (implicitTransaction && !isDisposing(lastDisposingReason))
        {
            try
            {
                resetImplicitTransactionIf(ResetImplicitTransactiontFlag.none);
            }
            catch (Exception e)
            {
                if (auto log = canErrorLog())
                    log.errorf("%s.command.removeReaderCompleted() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
            }
        }
    }

    enum ResetImplicitTransactiontFlag : ubyte
    {
        none = 0, // Must be bit flag for set
        error = 1,
        nonQuery = 2,
    }

    static struct ExecutePrep
    {
    public:
        @disable this();
        @disable this(this);
        @disable void opAssign(typeof(this));

        this(DbCommand command, DbCommandExecuteType type) nothrow @safe
        {
            this.command = command;
            this.type = type;
            this.wasPrepared = command.prepared;
        }

        void reset(const(bool) isError) @safe
        {
            if (resetTransaction)
            {
                resetTransaction = false;
                auto flags = isError ? ResetImplicitTransactiontFlag.error : ResetImplicitTransactiontFlag.none;
                if (type == DbCommandExecuteType.nonQuery)
                    flags |= ResetImplicitTransactiontFlag.nonQuery;
                if (isError || type != DbCommandExecuteType.reader)
                    command.resetImplicitTransactionIf(flags);
            }

            if (resetPrepare)
            {
                resetPrepare = false;
                if (isError && !wasPrepared && command.prepared)
                    command.unprepare();
            }

            command = null;
        }

    public:
        DbCommand command;
        const DbCommandExecuteType type;
        bool resetPrepare;
        bool resetTransaction;
        const bool wasPrepared;
    }

    final void resetImplicitTransactionIf(const(ResetImplicitTransactiontFlag) flags)  @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(flags=", flags, ")");

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
        if (implicitTransaction
            && (flags & ResetImplicitTransactiontFlag.nonQuery)
            && t !is null
            && t.isRetaining)
            commitOrRollback = true;

        if (commitOrRollback && t !is null)
        {
            if ((flags & ResetImplicitTransactiontFlag.error))
                t.rollbackError();
            else
                t.commit();
        }
    }

    void resetNewStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

        notificationMessages.length = 0;
        _flags.set(DbCommandFlag.cancelled, false);
        if (kind < ResetStatementKind.executing)
            _executedCount = 0;
        else
            _executedCount++;
        if (_fields !is null)
            _fields.resetNewStatement(kind);
        if (_parameters !is null)
            _parameters.resetNewStatement(kind);
    }

    typeof(this) setCommandText(string commandText, DbCommandType type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(type=", type, ", commandText=", commandText, ")");

        if (prepared)
            unprepare();

        clearFields();
        clearParameters();
        _executeCommandText = null;
        _commandText = commandText;
        return commandType(type);
    }

    final bool setImplicitPrepareIf(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (doExecuteCommandNeedPrepare(DbCommandExecuteType.scalar) && !prepared)
        {
            prepare();

            return true;
        }
        else
            return false;
    }

    final bool setImplicitTransactionIf(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (transactionRequired && (_transaction is null || _transaction.state == DbTransactionState.disposed))
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

    void setOutputParameters(ref DbRowValue values)
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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

    abstract void doExecuteCommand(const(DbCommandExecuteType) type) @safe;
    abstract void doFetch(const(bool) isScalar) @safe;
    abstract void doPrepare() @safe;
    abstract void doUnprepare() @safe;

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
 	DbRowValueQueue _fetchedRows;
    Duration _commandTimeout;
    uint _executedCount; // Number of execute calls after prepare
    uint _fetchedCount; // Number of fetch calls
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
    in
    {
        assert(database !is null);
    }
    do
    {
        this._database = database;
        this._connectionStringBuilder = database.createConnectionStringBuilder();
    }

    this(DbDatabase database, string connectionString) @safe
    in
    {
        assert(database !is null);
    }
    do
    {
        this(database);
        if (connectionString.length != 0)
            this._connectionStringBuilder.parseConnectionString(connectionString);
    }

    this(DbDatabase database, DbConnectionStringBuilder connectionString) nothrow @safe
    in
    {
        assert(database !is null);
        assert(connectionString !is null);
        assert(connectionString.scheme == database.scheme);
        assert(connectionString.scheme == scheme);
    }
    do
    {
        this(database);
        this._connectionStringBuilder.assign(connectionString);
    }

    this(DbDatabase database, DbURL!string connectionString) @safe
    in
    {
        assert(database !is null);
        assert(connectionString.scheme == database.scheme);
        assert(connectionString.scheme == scheme);
    }
    do
    {
        this(database);
        this._connectionStringBuilder.setConnectionString(connectionString);
    }

    final void cancelCommand(DbCommand command) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();
        auto data = createCancelCommandData(command);
        cancelCommand(command, data);
    }

    final void cancelCommand(DbCommand command, DbCancelCommandData data) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.connection.cancelCommand()", forLogInfo());

        checkActive();

        notificationMessages.length = 0;
        if (command !is null)
            command._flags.set(DbCommandFlag.cancelled, true);
        scope (exit)
            doNotifyMessage();

        doCancelCommand(data);
    }

    pragma(inline, true)
    final Logger canErrorLog() nothrow @safe
    {
        auto result = logger;
        return result !is null && result.isError ? result : null;
    }

    pragma(inline, true)
    final Logger canTimeLog() nothrow @safe
    {
        auto result = logger;
        return result !is null && result.isWarn ? result : null;
    }

    pragma(inline, true)
    final Logger canTraceLog() nothrow @safe
    {
        auto result = logger;
        return result !is null && result.isInfo ? result : null;
    }

    final typeof(this) close() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(state=", state, ")");

        if (auto log = canTraceLog())
            log.infof("%s.connection.close()", forLogInfo());

        if (_poolList !is null)
            return _poolList.release(this);

        const previousState = state;
        if (previousState == DbConnectionState.closed)
            return this;

        _state = DbConnectionState.closing;
        doBeginStateChange(DbConnectionState.closing);
        doClose(DbConnectionState.closing);
        _state = DbConnectionState.closed;
        doEndStateChange(previousState);

        return this;
    }

    final DLinkDbCommandTypes.DLinkRange commands() @safe
    {
        return _commands[];
    }

    abstract DbCancelCommandData createCancelCommandData(DbCommand command) @safe;

    final DbCommand createCommand(string name = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();
        return _commands.insertEnd(database.createCommand(this, name));
    }

    final DbCommand createCommandDDL(string commandDDL, string name = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        auto result = createCommand(name);
        result.commandDDL = commandDDL;
        return result;
    }

    final DbCommand createCommandText(string commandText, string name = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        auto result = createCommand(name);
        result.commandText = commandText;
        return result;
    }

    final DbTransaction createTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();
        return createTransactionImpl(isolationLevel, false);
    }

    final DbTransaction defaultTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();
        if (_defaultTransaction is null)
            _defaultTransaction = createTransactionImpl(isolationLevel, true);
        return _defaultTransaction;
    }

    final DbRecordsAffected executeNonQuery(string commandText) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

        checkActive();
        auto command = createCommandText(commandText);
        scope (exit)
            command.dispose();

        command.parametersCheck = false;
        return command.executeNonQuery();
    }
    
    final DbReader executeReader(string commandText) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

        checkActive();
        auto command = createCommandText(commandText);
        command.parametersCheck = false;
        return command.executeReaderImpl(true);
    }

    final DbValue executeScalar(string commandText) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

        checkActive();
        auto command = createCommandText(commandText);
        scope (exit)
            command.dispose();

        command.parametersCheck = false;
        return command.executeScalar();
    }
    
    final string forCacheKey() const nothrow @safe
    {
        return _connectionStringBuilder.forCacheKey();
    }

    pragma(inline, true)
    final string forErrorInfo() const nothrow @safe
    {
        return _connectionStringBuilder.forErrorInfo();
    }

    pragma(inline, true)
    final string forLogInfo() const nothrow @safe
    {
        return _connectionStringBuilder.forLogInfo();
    }

    final typeof(this) open() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(state=", state, ")");

        if (auto log = canTraceLog())
            log.infof("%s.connection.open()", forLogInfo());

        const previousState = state;
        if (previousState == DbConnectionState.opened)
            return this;

        reset();
        _state = DbConnectionState.opening;
        doBeginStateChange(DbConnectionState.opening);
        scope (exit)
            doNotifyMessage();
        scope (failure)
        {
            _fatalError = true;
            _state = DbConnectionState.failing;
            doClose(DbConnectionState.failing);
            doEndStateChange(previousState);
            _state = DbConnectionState.failed;
        }

        doOpen();
        _state = DbConnectionState.opened;
        doEndStateChange(previousState);

        return this;
    }

    final typeof(this) release() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.connection.release()", forLogInfo());

        if (_poolList !is null)
            return _poolList.release(this);

        dispose();
        return null;
    }

    final void removeCachedStoredProcedure(string storedProcedureName) nothrow @safe
    {
        const cacheKey = DbDatabase.generateCacheKeyStoredProcedure(storedProcedureName, this.forCacheKey);
        database.cache.remove(cacheKey);
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
    @property final string connectionString() @safe
    {
        return connectionStringBuilder.connectionString;
    }

    @property final typeof(this) connectionString(string value) @safe
    {
        checkInactive();
        _connectionStringBuilder.parseConnectionString(value);
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
     * Returns true if there is a mismatched reading/writing data with database server and
     * must perform disconnect and connect again
     */
    @property final bool isFatalError() const nothrow pure @safe
    {
        return _fatalError;
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

	/**
     * Gets the indicator of current state of the connection
	 */
    @property final DbConnectionState state() const nothrow pure @safe
    {
        return _state;
    }

    @property abstract DbScheme scheme() const nothrow pure @safe;

    @property abstract bool supportMultiReaders() nothrow @safe;

package(pham.db):
    final DbCommand createNonTransactionCommand(const(bool) getExecutionPlanning = false) @safe
    {
        auto result = createCommand();
        result.getExecutionPlanning = getExecutionPlanning;
        result.parametersCheck = !getExecutionPlanning;
        result.returnRecordsAffected = !getExecutionPlanning;
        result.transactionRequired = false;
        return result;
    }

    final void doClose(const(DbConnectionState) reasonState) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(reasonState=", reasonState, ")");

        const isClosing = reasonState == DbConnectionState.closing;
        const isFailing = isFatalError || reasonState == DbConnectionState.failing;

        try
        {
            if (!isFailing)
                rollbackTransactions();
            disposeTransactions(DisposingReason.other);
            disposeCommands(DisposingReason.other);
            doClose(isFailing);
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.connection.doClose() - %s", forLogInfo(), e.msg, e);
        }

        _handle.reset();
    }

    void fatalError(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        _fatalError = true;
    }

    final size_t nextCounter() nothrow @safe
    {
        return (++_nextCounter);
    }

    @property final int activeTransactionCounter() const nothrow @safe
    {
        return _activeTransactionCounter;
    }

    @property final int readerCounter() const nothrow @safe
    {
        return _readerCounter;
    }

protected:
    final void checkActive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (state != DbConnectionState.opened)
        {
            auto msg = _fatalError
                ? DbMessage.eInvalidConnectionFatal.fmtMessage(funcName, connectionStringBuilder.forErrorInfo())
                : DbMessage.eInvalidConnectionInactive.fmtMessage(funcName, connectionStringBuilder.forErrorInfo());
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }
    }

    final void checkActiveReader(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        if (_readerCounter != 0 && !supportMultiReaders)
            throw new DbException(0, DbMessage.eInvalidConnectionActiveReader, null, funcName, file, line);
    }

    final void checkInactive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (state == DbConnectionState.opened)
        {
            auto msg = DbMessage.eInvalidConnectionActive.fmtMessage(funcName, connectionStringBuilder.forErrorInfo());
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }
    }

    final DbTransaction createTransactionImpl(DbIsolationLevel isolationLevel, bool defaultTransaction) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        auto result = database.createTransaction(this, isolationLevel, defaultTransaction);
        _transactions.insertEnd(result);
        return result;
    }

    void disposeCommands(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        while (!_commands.empty)
            _commands.remove(_commands.last).dispose(disposingReason);
    }

    void disposeTransactions(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        _defaultTransaction = null;
        while (!_transactions.empty)
            _transactions.remove(_transactions.last).dispose(disposingReason);
    }

    final void doBeginStateChange(DbConnectionState newState) @safe
    {
        if (beginStateChange)
            beginStateChange(this, newState);
    }

    final void doEndStateChange(DbConnectionState oldState) @safe
    {
        if (endStateChange)
            endStateChange(this, oldState);
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        if (_state != DbConnectionState.closed && _state != DbConnectionState.failed)
            doClose(DbConnectionState.closing);

        beginStateChange.clear();
        endStateChange.clear();
        disposeTransactions(disposingReason);
        disposeCommands(disposingReason);
        serverInfo.clear();
        _handle.reset();
        _state = DbConnectionState.disposed;

        if (_poolList !is null)
            DbConnectionList.beforeDisposeConnection(this);

        if (isDisposing(disposingReason))
        {
            _connectionStringBuilder = null;
            _database = null;
            _poolList = null;
        }
    }

    final void doNotifyMessage() nothrow @safe
    {
        if (notificationMessages.length == 0)
            return;
        scope (exit)
            notificationMessages.length = 0;

        if (notifyMessage)
        {
            try
            {
                notifyMessage(this, notificationMessages);
            }
            catch (Exception e)
            {
                if (auto log = canErrorLog())
                    log.errorf("%s.connection.doNotifyMessage() - %s", forLogInfo(), e.msg, e);
            }
        }
    }

    void doPool(bool pooling) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (pooling)
        {
            _inactiveTime = DateTime.utcNow;
            disposeTransactions(DisposingReason.other);
            disposeCommands(DisposingReason.other);
        }
    }

    void removeCommand(DbCommand value) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (value._prev !is null || value._next !is null)
            _commands.remove(value);
    }

    void removeTransaction(DbTransaction value) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_defaultTransaction is value)
            _defaultTransaction = null;

        if (value._prev !is null || value._next !is null)
            _transactions.remove(value);
    }

    void reset() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        _fatalError = false;
        _nextCounter = 0;
        _readerCounter = _activeTransactionCounter = 0;
        _inactiveTime = DateTime.zero;
        serverInfo.clear();
        notificationMessages.length = 0;
        disposeTransactions(DisposingReason.other);
        disposeCommands(DisposingReason.other);
    }

    final void rollbackTransactions() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        foreach (t; _transactions[])
            t.rollback();
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
    DelegateList!(DbConnection, DbConnectionState) beginStateChange;

    /**
     * Delegate to get notify when a state change
     * Occurs when the after state of the event changes
     * Params:
     *  oldState = old state value
     */
    DelegateList!(DbConnection, DbConnectionState) endStateChange;

    DelegateList!(Object, DbNotificationMessage[]) notifyMessage;

    DbNotificationMessage[] notificationMessages;

    /**
     * Populate when connection is established
     */
    DbCustomAttributeList serverInfo;

    /**
     * For logging various operation or error message
     */
    Logger logger;

protected:
    DbDatabase _database;
    DbConnectionList _poolList;
    DbTransaction _defaultTransaction;
    DateTime _inactiveTime;
    DbHandle _handle;
    size_t _nextCounter;
    int _readerCounter, _activeTransactionCounter;
    DbConnectionState _state;
    DbConnectionType _type;
    bool _fatalError;

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
            result._poolList = this;
            return result;
        }
        else
        {
            auto result = _connections.remove(_connections.last);
            atomicFetchSub(_length, 1);
            result._poolList = this;
            result.doPool(false);
            return result;
        }
    }

    final DbConnection release(DbConnection item) nothrow @safe
    in
    {
        assert(item !is null);
    }
    do
    {
        DbConnectionList poolList;
        final switch (canPoolConnection(this, null, item, poolList)) with (CanPool)
        {
            case none:
                return disposeConnection(item);
            case wrongList:
                return poolList.release(item);
            case dispose:
                return disposeConnection(item);
            case ok:
                return pool.release(item);
        }
    }

    final DbConnection[] removeInactives(scope const(DateTime) utcNow, scope const(Duration) maxInactiveTime) nothrow @safe
    {
        DbConnection[] result;
        result.reserve(length);

        // Iterate and get inactive connections
        foreach (connection; this)
        {
            const elapsed = utcNow - connection._inactiveTime;
            if (elapsed.toDuration > maxInactiveTime)
                result ~= connection;
        }

        // Detach from list
        foreach (removed; result)
        {
            _connections.remove(removed);
            atomicFetchSub(_length, 1);
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
        return atomicLoad(_length);
    }

    @property final DbConnectionPool pool() nothrow pure @safe
    {
        return _pool;
    }

protected:
    static void beforeDisposeConnection(DbConnection item) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        auto itemPool = item._poolList !is null ? item._poolList.pool : null;
        if (itemPool !is null)
            atomicFetchSub(itemPool._acquiredLength, 1);
        item._poolList = null;
    }

    enum CanPool : ubyte { none, wrongList, dispose, ok }

    static CanPool canPoolConnection(DbConnectionList checkList, DbConnectionPool checkPool,
        DbConnection item, out DbConnectionList poolList) nothrow @safe
    {
        poolList = item._poolList;

        // Not pooling
        if (poolList is null)
            return CanPool.none;

        // Wrong pool
        if (checkList !is null && poolList !is checkList)
            return CanPool.wrongList;

        if (checkPool !is null && poolList.pool !is null && poolList.pool !is checkPool)
            return CanPool.wrongList;

        // In disposing mode or no longer active
        if (poolList.pool is null
            || isDisposing(poolList.lastDisposingReason)
            || item.state != DbConnectionState.opened || item.isFatalError)
            return CanPool.dispose;

        return CanPool.ok;
    }

    static DbConnection disposeConnection(DbConnection item) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        beforeDisposeConnection(item);
        item.dispose();
        return null;
    }

    final DbConnection doRelease(DbConnection item) nothrow @safe
    {
        item.doPool(true);
        item._poolList = null;
        _connections.insertEnd(item);
        atomicFetchAdd(_length, 1);
        return null;
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        while (!_connections.empty)
            _connections.remove(_connections.last).dispose(disposingReason);
        _length = 0;
        if (isDisposing(disposingReason))
        {
            _database = null;
            _pool = null;
        }
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
@safe:

public:
    this(Timer secondTimer,
        size_t maxLength = DbDefaultSize.connectionPoolLength,
        Duration maxInactiveTime = dur!"seconds"(DbDefaultSize.connectionPoolInactiveTime)) nothrow
    {
        this._secondTimer = secondTimer;
        this._mutex = new Mutex();
        this._maxLength = maxLength;
        this._maxInactiveTime = maxInactiveTime;
    }

    final DbConnection acquire(DbScheme scheme, string connectionString)
    {
        auto raiiMutex = () @trusted { return RAIIMutex(_mutex); }();

        const localMaxLength = maxLength;
        if (_acquiredLength >= localMaxLength)
        {
            auto msg = DbMessage.eInvalidConnectionPoolMaxUsed.fmtMessage(_acquiredLength, localMaxLength);
            throw new DbException(DbErrorCode.connect, msg);
        }

        bool created;
        auto database = DbDatabaseList.getDb(scheme);
        auto lst = schemeConnections(database, connectionString);
        auto result = lst.acquire(created);
        atomicFetchAdd(_acquiredLength, 1);
        if (!created)
            atomicFetchSub(_unusedLength, 1);
        return result;
    }

    final DbConnection acquire(DbConnectionStringBuilder connectionStringBuilder)
    {
        return acquire(connectionStringBuilder.scheme, connectionStringBuilder.connectionString);
    }

    static void cleanup() nothrow @trusted
    {
        if (_instance !is null)
        {
            _instance.dispose();
            _instance = null;
        }
    }

    final size_t cleanupInactives()
    {
        auto inactives = removeInactives();
        
        foreach (inactive; inactives)
            inactive.dispose();
        
        return inactives.length;
    }

    static DbConnectionPool instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    final DbConnection release(DbConnection item) nothrow @trusted
    in
    {
        assert(item !is null);
    }
    do
    {
        registerWithTimer();

        DbConnectionList poolList;
        final switch (DbConnectionList.canPoolConnection(null, this, item, poolList)) with (DbConnectionList.CanPool)
        {
            case none:
                return DbConnectionList.disposeConnection(item);
            case wrongList:
                return poolList.release(item);
            case dispose:
                return DbConnectionList.disposeConnection(item);
            case ok:
                break;
        }

        auto raiiMutex = RAIIMutex(_mutex);

        atomicFetchSub(_acquiredLength, 1);

        // Over limit?
        const localMaxLength = maxLength;
        if (atomicFetchAdd(_unusedLength, 1) >= localMaxLength)
        {
            atomicFetchSub(_unusedLength, 1);
            return DbConnectionList.disposeConnection(item);
        }

        poolList.doRelease(item);

        return null;
    }

    @property final size_t acquiredLength() const nothrow
    {
        return atomicLoad(_acquiredLength);
    }

    @property final size_t maxLength() const nothrow pure
    {
        return atomicLoad(_maxLength);
    }

    @property final typeof(this) maxLength(size_t value) nothrow pure
    {
        atomicStore(_maxLength, value);
        return this;
    }

    @property final size_t unusedLength() const nothrow pure
    {
        return atomicLoad(_unusedLength);
    }

protected:
    static DbConnectionPool createInstance() nothrow @trusted
    {
        return new DbConnectionPool(._secondTimer);
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @trusted
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        scope (failure) assert(0, "Assume nothrow failed");

        unregisterWithTimer();
        _secondTimer = null;

        foreach (_, lst; _schemeConnections)
            lst.dispose(disposingReason);

        _schemeConnections = null;
        _acquiredLength = 0;
        _unusedLength = 0;

        if (_mutex !is null)
        {
            _mutex.destroy();
            _mutex = null;
        }
    }

    final void doTimer(TimerEvent event)
    {
        cleanupInactives();
    }

    final void registerWithTimer() nothrow
    {
        if (cas(&_timerAdded, false, true) && _secondTimer !is null)
            _secondTimer.addEvent(TimerEvent(timerName(), dur!"minutes"(1), &doTimer));
    }
    
    final DbConnection[] removeInactives()
    {
        auto raiiMutex = () @trusted { return RAIIMutex(_mutex); }();
        
        if (_unusedLength == 0)
            return null;
            
        const utcNow = DateTime.utcNow;
        DbConnection[] result;
        result.reserve(_unusedLength);
        foreach (_, lst; _schemeConnections)
        {
            auto inactives = lst.removeInactives(utcNow, _maxInactiveTime);
            if (inactives.length)
            {
                result ~= inactives;
                atomicFetchSub(_unusedLength, inactives.length);
            }
        }
        return result;
    }

    final DbConnectionList schemeConnections(DbDatabase database, string connectionString)
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

    final string timerName() nothrow pure @trusted
    {
        import pham.utl.utl_object : toString;

        static immutable string prefix = "DbConnectionPool_";
        Appender!string buffer;
        buffer.reserve(prefix.length + size_t.sizeof * 2);
        buffer.put(prefix);
        return toString!16(buffer, cast(size_t)(cast(void*)this)).data;
    }

    final void unregisterWithTimer() nothrow
    {
        if (cas(&_timerAdded, true, false) && _secondTimer !is null)
            _secondTimer.removeEvent(timerName());
    }
    
private:
    Mutex _mutex;
    DbConnectionList[DbIdentitier] _schemeConnections;
    Duration _maxInactiveTime;
    size_t _acquiredLength, _unusedLength, _maxLength;
    Timer _secondTimer;
    bool _timerAdded;
    __gshared static DbConnectionPool _instance;
    
}

abstract class DbConnectionStringBuilder : DbIdentitierValueList!string
{
@safe:

public:
    this(DbDatabase database) nothrow
    {
        this._database = database;
        this.setDefaultCustomAttributes();
        this.setDefaultIfs();
    }

    this(DbDatabase database, string connectionString)
    {
        this._database = database;
        this.setDefaultCustomAttributes();
        if (connectionString.length != 0)
            this.parseConnectionString(connectionString);
        else
            this.setDefaultIfs();
    }

    typeof(this) assign(DbConnectionStringBuilder source) nothrow
    in
    {
        assert(source !is null);
        assert(source.scheme == scheme);
    }
    do
    {
        clear();

        this.forErrorInfoCustom = source.forErrorInfoCustom;
        this.forLogInfoCustom = source.forLogInfoCustom;
        this._elementSeparators = source._elementSeparators;
        this._valueSeparator = source._valueSeparator;

        foreach (n; source.sequenceNames)
        {
            auto p = n in source.lookupItems;
            this.put(p.name, p.value);
        }

        return this;
    }

    override typeof(this) clear() nothrow @trusted
    {
        super.clear();
        this.forErrorInfoCustom = null;
        this.forLogInfoCustom = null;
        return this;
    }

    final string forCacheKey() const nothrow @safe
    {
        return databaseName ~ "." ~ serverName;
    }

    /**
     * Returns a text about database for constructing error/exception message
     */
    final string forErrorInfo() const nothrow
    {
        return forErrorInfoCustom.length != 0
            ? forErrorInfoCustom
            : serverName ~ ":" ~ databaseName;
    }

    /**
     * Returns a text about database for logging
     */
    final string forLogInfo() const nothrow
    {
        return forLogInfoCustom.length != 0
            ? forLogInfoCustom
            : serverName ~ ":" ~ databaseName;
    }

    final string getCustomValue(string name) nothrow
    {
        return name.length != 0 && exist(name) ? getString(name) : null;
    }

    final bool hasValue(string name, out string value) const nothrow
    {
        const id = DbIdentitier(name);
        const r = find(id, value);
        return r && value.length != 0;
    }

    final bool hasCustomValue(string name, out string value) const nothrow
    {
        return customAttributes.hasValue(name, value);
    }

    override DbNameValueValidated isValid(const(DbIdentitier) name, string value) nothrow
    {
        const rs = super.isValid(name, value);
        if (rs != DbNameValueValidated.ok)
            return rs;

        const n = name in getValidParamNameChecks();
        if (n is null)
            return DbNameValueValidated.invalidName;

        const v = name in dbDefaultConnectionParameterValues;
        if (v is null)
            return DbNameValueValidated.invalidName;

        if ((*v).isValidValue(value) != DbNameValueValidated.ok)
            return DbNameValueValidated.invalidValue;

        return DbNameValueValidated.ok;
    }

    /**
     * Returns list of valid parameter names for connection string
     */
    abstract const(string[]) parameterNames() const nothrow;

    typeof(this) parseConnectionString(string connectionString)
    {
        assert(elementSeparators.length != 0);

        string errorMessage;
        int errorCode;
        bool error;

        clear();

        if (connectionString.length)
        {
            auto status = this.setDelimiterText(connectionString, elementSeparators, valueSeparator);
            if (!status)
            {
                errorMessage = status.errorMessage;
                errorCode = status.errorCode;
                error = true;
            }
        }

        this.setDefaultIfs();

        if (error)
            throw new DbException(errorCode, errorMessage);

        return this;
    }

    typeof(this) setConnectionString(DbURL!string connectionString)
    in
    {
        assert(connectionString.scheme == scheme);
    }
    do
    {
        import pham.utl.utl_result : addLine;

        string errorMessage;

        clear();

        foreach (ref o; connectionString.options)
        {
            final switch (super.isValid(o.name, o.value)) with (DbNameValueValidated)
            {
                case invalidName:
                    addLine(errorMessage, format(DbMessage.eInvalidConnectionStringName, scheme, o.name));
                    break;
                case duplicateName:
                    addLine(errorMessage, format(DbMessage.eInvalidConnectionStringNameDup, scheme, o.name));
                    break;
                case invalidValue:
                    addLine(errorMessage, format(DbMessage.eInvalidConnectionStringValue, scheme, o.name, o.value));
                    break;
                case ok:
                    put(o.name, o.value);
                    break;
            }
        }

        databaseName = connectionString.database;
        userName = connectionString.userName;
        userPassword = connectionString.userPassword;

        auto firstHost = connectionString.firstHost();
        serverName = firstHost.name;
        serverPort = firstHost.port;

        this.setDefaultIfs();

        if (errorMessage.length)
            throw new DbException(DbErrorCode.parse, errorMessage);

        return this;
    }

    /**
     * Allow to set custom parameter value without verfication based on database engine.
     * It is up to caller to supply value correctly
     * Returns:
     *  true if name is supported by database engine otherwise false
     */
    final bool setCustomValue(string name, string value) nothrow
    {
        if (name.length == 0)
            return false;

        put(name, value);
        const e = name in getValidParamNameChecks();
        return e !is null;
    }

    final override size_t toHash() nothrow @safe
    {
        return this.toString().hashOf();
    }

    final override string toString() nothrow @safe
    {
        assert(elementSeparators.length != 0);

        return getDelimiterText(this, elementSeparators[0], valueSeparator);
    }

    @property final bool allowBatch() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.allowBatch));
    }

    @property final typeof(this) allowBatch(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.allowBatch, s);
        return this;
    }

    @property final string applicationName() const nothrow
    {
        return customAttributes.get(DbConnectionCustomIdentifier.applicationName, null);
    }

    @property final typeof(this) applicationName(string value)
    {
        if (customAttributeInfo.isValidValue(value) == DbNameValueValidated.ok)
        {
            customAttributes.put(DbConnectionCustomIdentifier.applicationName, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionCustomIdentifier.applicationName, value);
    }

    @property final string applicationVersion() const nothrow
    {
        return customAttributes.get(DbConnectionCustomIdentifier.applicationVersion, null);
    }

    @property final typeof(this) applicationVersion(string value)
    {
        if (customAttributeInfo.isValidValue(value) == DbNameValueValidated.ok)
        {
            customAttributes.put(DbConnectionCustomIdentifier.applicationVersion, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionCustomIdentifier.applicationVersion, value);
    }

    @property final string charset() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.charset);
    }

    @property final typeof(this) charset(string value)
    {
        auto k = DbConnectionParameterIdentifier.charset in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.charset, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.charset, value);
    }

    /**
     * Gets or sets the time (value based in milliseconds) to wait for a command to be executed completely.
     * Set to zero to disable the setting.
     */
    @property final Duration commandTimeout() const nothrow
    {
        Duration result;
        cvtConnectionParameterDuration(result, getString(DbConnectionParameterIdentifier.commandTimeout));
        return result;
    }

    @property final typeof(this) commandTimeout(scope const(Duration) value)
    {
        auto s = cvtConnectionParameterDuration(value);
        auto k = DbConnectionParameterIdentifier.commandTimeout in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.commandTimeout, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.commandTimeout, value.toString());
    }

    @property final DbCompressConnection compress() const nothrow
    {
        const s = getString(DbConnectionParameterIdentifier.compress);
        DbCompressConnection result;
        if (cvtConnectionParameterCompress(result, s) == DbNameValueValidated.ok)
            return result;
        // Backward compatible with previous version(bool value)
        else if (s == dbBoolTrue)
            return DbCompressConnection.zip;
        else
            return DbCompressConnection.disabled;
    }

    @property final typeof(this) compress(DbCompressConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.compress, toName(value));
        return this;
    }

    /**
     * The connection string used to establish the initial connection.
     */
    @property final string connectionString() nothrow
    {
        assert(elementSeparators.length != 0);

        const es = elementSeparators[0];
        const vs = valueSeparator;
        const names = parameterNames();

        Appender!string result;
        result.reserve(names.length * 50);
        string v;
        size_t count;
        foreach (name; names)
        {
            if (find(name, v))
            {
                if (count)
                    result.put(es);
                result.put(name);
                result.put(vs);
                result.put(v);
                count++;
            }
        }
        return result.data;
    }

    /**
     * Gets or sets the time (value based in milliseconds) to wait for a connection to open.
     * The default value is 10 seconds.
     */
    @property final Duration connectionTimeout() const nothrow
    {
        Duration result;
        cvtConnectionParameterDuration(result, getString(DbConnectionParameterIdentifier.connectionTimeout));
        return result;
    }

    @property final typeof(this) connectionTimeout(scope const(Duration) value)
    {
        auto s = value != Duration.zero ? cvtConnectionParameterDuration(value) : getDefault(DbConnectionParameterIdentifier.connectionTimeout);
        auto k = DbConnectionParameterIdentifier.connectionTimeout in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.connectionTimeout, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.connectionTimeout, value.toString());
    }

    @property final DbDatabase database() nothrow pure
    {
        return _database;
    }

    /**
     * The name of the database; value of "database"
     */
    @property final DbIdentitier databaseName() const nothrow
    {
        return DbIdentitier(getString(DbConnectionParameterIdentifier.databaseName));
    }

    @property final typeof(this) databaseName(string value)
    {
        auto k = DbConnectionParameterIdentifier.databaseName in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            debug(debug_pham_db_db_type) debug writeln(__FUNCTION__, "(value=", value, ", min=", (*k).min, ", max=", (*k).max, ")");

            put(DbConnectionParameterIdentifier.databaseName, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.databaseName, value);
    }

    /**
     * The file-name of the database; value of "databaseFileName"
     */
    @property final string databaseFileName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.databaseFileName);
    }

    @property final typeof(this) databaseFileName(string value)
    {
        auto k = DbConnectionParameterIdentifier.databaseFileName in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.databaseFileName, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.databaseFileName, value);
    }

    @property final string elementSeparators() const nothrow
    {
        return _elementSeparators;
    }

    @property final DbEncryptedConnection encrypt() const nothrow
    {
        DbEncryptedConnection result;
        cvtConnectionParameterEncrypt(result, getString(DbConnectionParameterIdentifier.encrypt));
        return result;
    }

    @property final typeof(this) encrypt(DbEncryptedConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.encrypt, toName(value));
        return this;
    }

    /**
     * Gets or sets number of records of each fetch call.
     * Use -1 to fetch all
     * Default value is 200
     */
    @property final int32 fetchRecordCount() const nothrow
    {
        int32 result;
        cvtConnectionParameterInt32(result, getString(DbConnectionParameterIdentifier.fetchRecordCount));
        return result;
    }

    @property final typeof(this) fetchRecordCount(int32 value)
    {
        auto s = value != 0 ? value.to!string : getDefault(DbConnectionParameterIdentifier.fetchRecordCount);
        auto k = DbConnectionParameterIdentifier.fetchRecordCount in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.fetchRecordCount, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.fetchRecordCount, value.to!string);
    }

    @property final DbIntegratedSecurityConnection integratedSecurity() const nothrow
    {
        DbIntegratedSecurityConnection result;
        cvtConnectionParameterIntegratedSecurity(result, getString(DbConnectionParameterIdentifier.integratedSecurity));
        return result;
    }

    @property final typeof(this) integratedSecurity(DbIntegratedSecurityConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.integratedSecurity, toName(value));
        return this;
    }

    /**
     * Gets or sets transport package size in bytes.
     * Default value is 8_192
     */
    @property final uint32 packageSize() const nothrow
    {
        int32 result;
        cvtConnectionParameterComputingSize(result, getString(DbConnectionParameterIdentifier.packageSize));
        return result;
    }

    @property final typeof(this) packageSize(uint32 value)
    {
        auto s = value != 0 ? value.to!string : getDefault(DbConnectionParameterIdentifier.packageSize);
        auto k = DbConnectionParameterIdentifier.packageSize in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.packageSize, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.packageSize, value.to!string);
    }

    @property final bool pooling() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.pooling));
    }

    @property final typeof(this) pooling(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.pooling, s);
        return this;
    }

    @property final Duration poolIdleTimeout() const nothrow
    {
        Duration result;
        cvtConnectionParameterDuration(result, getString(DbConnectionParameterIdentifier.poolIdleTimeout));
        return result;
    }

    @property final typeof(this) poolIdleTimeout(scope const(Duration) value)
    {
        auto s = cvtConnectionParameterDuration(value);
        auto k = DbConnectionParameterIdentifier.poolIdleTimeout in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.poolIdleTimeout, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.poolIdleTimeout, value.toString());
    }

    @property final uint32 poolMaxCount() const nothrow
    {
        int32 result;
        cvtConnectionParameterInt32(result, getString(DbConnectionParameterIdentifier.poolMaxCount));
        if (result == 0)
            cvtConnectionParameterInt32(result, getDefault(DbConnectionParameterIdentifier.poolMaxCount));
        return result;
    }

    @property final typeof(this) poolMaxCount(uint32 value)
    {
        auto s = value != 0 ? value.to!string : getDefault(DbConnectionParameterIdentifier.poolMaxCount);
        auto k = DbConnectionParameterIdentifier.poolMaxCount in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.poolMaxCount, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.poolMaxCount, value.to!string);
    }

    @property final uint32 poolMinCount() const nothrow
    {
        int32 result;
        cvtConnectionParameterInt32(result, getString(DbConnectionParameterIdentifier.poolMinCount));
        return result;
    }

    @property final typeof(this) poolMinCount(uint32 value)
    {
        auto s = value.to!string();
        auto k = DbConnectionParameterIdentifier.poolMinCount in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.poolMinCount, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.poolMinCount, value.to!string);
    }

    /**
     * Gets or sets the time (value based in milliseconds) to wait for a server to send back request's result.
     * The default value is 3_600 seconds (1 hour).
     * Set to zero to disable the setting.
     */
    @property final Duration receiveTimeout() const nothrow
    {
        Duration result;
        cvtConnectionParameterDuration(result, getString(DbConnectionParameterIdentifier.receiveTimeout));
        return result;
    }

    @property final typeof(this) receiveTimeout(scope const(Duration) value)
    {
        auto s = cvtConnectionParameterDuration(value);
        auto k = DbConnectionParameterIdentifier.receiveTimeout in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.receiveTimeout, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.receiveTimeout, value.toString());
    }

    @property final string roleName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.roleName);
    }

    @property final typeof(this) roleName(string value)
    {
        auto k = DbConnectionParameterIdentifier.roleName in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.roleName, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.roleName, value);
    }

    @property abstract DbScheme scheme() const nothrow pure;

    /**
     * Gets or sets the time (value based in milliseconds) to wait for a request to completely send to server.
     * The default value is 60 seconds.
     * Set to zero to disable the setting.
     */
    @property final Duration sendTimeout() const nothrow
    {
        Duration result;
        cvtConnectionParameterDuration(result, getString(DbConnectionParameterIdentifier.sendTimeout));
        return result;
    }

    @property final typeof(this) sendTimeout(scope const(Duration) value)
    {
        auto s = cvtConnectionParameterDuration(value);
        auto k = DbConnectionParameterIdentifier.sendTimeout in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.sendTimeout, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.sendTimeout, value.toString());
    }

    /**
     * The name of the database server; value of "server"
     */
    @property final string serverName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.serverName);
    }

    @property final typeof(this) serverName(string value)
    {
        auto k = DbConnectionParameterIdentifier.serverName in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.serverName, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.serverName, value);
    }

    @property final uint16 serverPort() const nothrow
    {
        int32 result;
        cvtConnectionParameterInt32(result, getString(DbConnectionParameterIdentifier.serverPort));
        return cast(uint16)result;
    }

    @property final typeof(this) serverPort(uint16 value)
    {
        auto s = value != 0 ? value.to!string() : getDefault(DbConnectionParameterIdentifier.serverPort);
        auto k = DbConnectionParameterIdentifier.serverPort in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.serverPort, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.serverPort, value.to!string);
    }

    /**
     * Returns value of "user"
     */
    @property final string userName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.userName);
    }

    @property final typeof(this) userName(string value)
    {
        auto k = DbConnectionParameterIdentifier.userName in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.userName, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.userName, value);
    }

    /**
     * Returns value of "password"
     */
    @property final string userPassword() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.userPassword);
    }

    @property final typeof(this) userPassword(string value)
    {
        auto k = DbConnectionParameterIdentifier.userPassword in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.userPassword, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.userPassword, value);
    }

    @property final char valueSeparator() const nothrow
    {
        return _valueSeparator;
    }

protected:
    enum customAttributeInfo = DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, 200);

    string getDefault(string name) const nothrow
    {
        auto k = name in dbDefaultConnectionParameterValues;
        if (k is null)
            return null;

        auto sch = (*k).scheme;
        return sch.length == 0 || sch == scheme ? (*k).def : null;
    }

    final string getString(string name) const nothrow
    {
        string result;
        if (find(name, result))
            return result;
        else
            return getDefault(name);
    }

    final const(bool[string]) getValidParamNameChecks() nothrow
    {
        if (_validParamNameChecks.length == 0)
        {
            if (_database !is null)
                _validParamNameChecks = _database._validParamNameChecks;
            else
            {
                const names = parameterNames();
                foreach (n; names)
                    _validParamNameChecks[n] = true;
            }
        }

        return _validParamNameChecks;
    }

    final void setDefaultCustomAttributes() nothrow
    {
        customAttributes.put(DbConnectionCustomIdentifier.currentComputerName, currentComputerName());
        customAttributes.put(DbConnectionCustomIdentifier.currentProcessId, currentProcessId().to!string());
        customAttributes.put(DbConnectionCustomIdentifier.currentProcessName, currentProcessName());
        customAttributes.put(DbConnectionCustomIdentifier.currentUserName, currentUserName());
    }

    void setDefaultIfs() nothrow
    {
        foreach (ref dpv; dbDefaultConnectionParameterValues.byKeyValue)
        {
            auto def = dpv.value.def;
            auto sch = dpv.value.scheme;
            if (def.length && (sch.length == 0 || sch == scheme))
                putIf(dpv.key, def);
        }
    }

    final noreturn throwInvalidPropertyValue(string name, string value,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__)
    {
        throw new DbException(DbErrorCode.parse, format(DbMessage.eInvalidConnectionStringValue, scheme, name, value),
            null, funcName, file, line);
    }

public:
    DbCustomAttributeList customAttributes;
    string forErrorInfoCustom;
    string forLogInfoCustom;

protected:
    DbDatabase _database;
    bool[string] _validParamNameChecks;
    string _elementSeparators = ";";
    char _valueSeparator = '=';
}

abstract class DbDatabase : DbNameObject
{
@safe:

public:
    dchar replacementChar = dchar.max;

    enum CharClass : ubyte
    {
        any,
        quote,
        backslash,
    }

public:
    this() nothrow @trusted
    {
        _cache = new DbCache!string(._secondTimer);
    }

    abstract const(string[]) connectionStringParameterNames() const nothrow pure;
    abstract DbCommand createCommand(DbConnection connection,
        string name = null) nothrow;
    abstract DbCommand createCommand(DbConnection connection, DbTransaction transaction,
        string name = null) nothrow;
    abstract DbConnection createConnection(string connectionString);
    abstract DbConnection createConnection(DbConnectionStringBuilder connectionString) nothrow;
    abstract DbConnection createConnection(DbURL!string connectionString);
    abstract DbConnectionStringBuilder createConnectionStringBuilder() nothrow;
    abstract DbConnectionStringBuilder createConnectionStringBuilder(string connectionString);
    abstract DbField createField(DbCommand command, DbIdentitier name) nothrow;
    abstract DbFieldList createFieldList(DbCommand command) nothrow;
    abstract DbParameter createParameter(DbIdentitier name) nothrow;
    abstract DbParameterList createParameterList() nothrow;
    abstract DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel,
        bool defaultTransaction = false) nothrow;

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
        if (auto e = c in _charClasses)
            return *e;
        else
            return CharClass.any;
    }

    final const(char)[] escapeIdentifier(return const(char)[] value) nothrow pure
    {
        if (value.length == 0)
            return value;

        size_t p;
        dchar cCode;
        char[encodeUTF8MaxLength] cCodeBuffer;
        ubyte cCount;

        // Find the first quote char
        while (p < value.length && nextUTF8Char(value, p, cCode, cCount))
        {
            if (charClass(cCode) != CharClass.any)
                break;
            p += cCount;
        }

        // No quote char found?
        if (p >= value.length)
            return value;

        Appender!string result;
        result.reserve(value.length + 100);
        if (p)
            result.put(value[0..p]);
        while (p < value.length)
        {
            if (!nextUTF8Char(value, p, cCode, cCount))
                cCode = replacementChar;

            const cc = charClass(cCode);
            if (cc == CharClass.quote)
                result.put(encodeUTF8(cCodeBuffer, cCode));
            else if (cc == CharClass.backslash)
                result.put('\\');
                
            result.put(encodeUTF8(cCodeBuffer, cCode));

            p += cCount;
        }
        return result.data;
    }

    final const(char)[] escapeString(return const(char)[] value) nothrow pure
    {
        if (value.length == 0)
            return value;

        size_t p;
        dchar cCode;
        char[encodeUTF8MaxLength] cCodeBuffer;
        ubyte cCount;

        // Find the first quote char
        while (p < value.length && nextUTF8Char(value, p, cCode, cCount))
        {
            if (charClass(cCode) != CharClass.any)
                break;
            p += cCount;
        }

        // No quote char found?
        if (p >= value.length)
            return value;

        Appender!string result;
        result.reserve(value.length + 100);
        if (p)
            result.put(value[0..p]);
        while (p < value.length)
        {
            if (!nextUTF8Char(value, p, cCode, cCount))
                cCode = replacementChar;

            if (charClass(cCode) != CharClass.any)
                result.put('\\');
                
            result.put(encodeUTF8(cCodeBuffer, cCode));

            p += cCount;
        }
        return result.data;
    }

    static string generateCacheKeyStoredProcedure(string storedProcedureName, string databaseCacheKey) nothrow pure
    {
        return storedProcedureName ~ ".StoredProcedure." ~ databaseCacheKey;
    }

    final const(char)[] quoteIdentifier(scope const(char)[] value) pure
    {
        return identifierQuoteChar ~ escapeIdentifier(value) ~ identifierQuoteChar;
    }

    final const(char)[] quoteString(scope const(char)[] value) pure
    {
        return stringQuoteChar ~ escapeString(value) ~ stringQuoteChar;
    }

    @property final DbCache!string cache() nothrow pure
    {
        return _cache;
    }

    /**
     * For logging various message & trace
     * Central place to assign to newly created DbConnection
     */
    @property final Logger logger() nothrow pure @trusted //@trusted=cast()
    {
        return cast(Logger)atomicLoad(_logger);
    }

    @property final DbDatabase logger(Logger logger) nothrow pure @trusted //@trusted=cast()
    {
        atomicStore(_logger, cast(shared)logger);
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
    final void populateValidParamNameChecks() nothrow pure @safe
    {
        const names = connectionStringParameterNames();
        foreach (n; names)
            _validParamNameChecks[n] = true;
    }

protected:
    DbCache!string _cache;
    bool[string] _validParamNameChecks;
    CharClass[dchar] _charClasses;
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
     * Search the leading scheme value, <scheme_name:>, for matching existing database
     * If found, will create and return instance of its' corresponding ...Connection
     * and throw DbException if not found
     */
    static DbConnection createConnection(string connectionString) @safe
    {
        import std.string : indexOf;

        const i = connectionString.indexOf(dbSchemeSeparator);
        auto database = getDb(i > 0 ? connectionString[0..i] : null);
        return database.createConnection(connectionString[i + 1..$]);
    }

    /**
     * Search the connection-string scheme for matching existing database
     * If found, will create and return instance of its' corresponding ...Connection
     * and throw DbException if not found
     */
    static DbConnection createConnection(DbConnectionStringBuilder connectionString) @safe
    {
        auto database = getDb(connectionString.scheme);
        return database.createConnection(connectionString);
    }

    /**
     * Search the connection-string scheme for matching existing database
     * If found, will create and return instance of its' corresponding ...Connection
     * and throw DbException if not found
     */
    static DbConnection createConnectionByURL(string dbURL) @safe
    {
        auto cfg = parseDbURL(dbURL);
        if (!cfg)
            throw new DbException(cfg.errorCode, cfg.errorMessage);

        auto database = getDb(cfg.scheme);
        return database.createConnection(cfg);
    }

    static bool findDb(DbScheme scheme, ref DbDatabase database) nothrow @safe
    {
        auto lst = instance();
        return lst.find(scheme, database);
    }

    static bool findDb(string scheme, ref DbDatabase database) nothrow @safe
    {
        DbScheme dbScheme;
        if (!isDbScheme(scheme, dbScheme))
            return false;
        else
            return findDb(dbScheme, database);
    }

    static DbDatabase getDb(DbScheme scheme) @safe
    {
        DbDatabase result;
        if (findDb(scheme, result))
            return result;

        auto msg = DbMessage.eInvalidSchemeName.fmtMessage(scheme);
        throw new DbException(0, msg);
    }

    static DbDatabase getDb(string scheme) @safe
    {
        DbDatabase result;
        if (findDb(scheme, result))
            return result;

        auto msg = DbMessage.eInvalidSchemeName.fmtMessage(scheme);
        throw new DbException(0, msg);
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

    static void cleanup() nothrow @trusted
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

    string traceString() const nothrow @trusted
    {
        import std.conv : to;

        return "type=" ~ toName!DbType(type)
             ~ ", baseTypeId=" ~ baseTypeId.to!string()
             ~ ", baseSubtypeId=" ~ baseSubTypeId.to!string()
             ~ ", baseSize=" ~ baseSize.to!string()
             ~ ", baseNumericScale=" ~ baseNumericScale.to!string();
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
    @property final int16 baseNumericDigits() const nothrow pure @safe
    {
        return _baseType.numericDigits;
    }

    @property final typeof(this) baseNumericDigits(int16 value) nothrow pure @safe
    {
        _baseType.numericDigits = value;
        return this;
    }

    /**
     * Gets or sets provider-specific numeric scale of the column
     */
    @property final int16 baseNumericScale() const nothrow pure @safe
    {
        return _baseType.numericScale;
    }

    @property final typeof(this) baseNumericScale(int16 value) nothrow pure @safe
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
    @property final DbBaseTypeInfo baseType() const nothrow pure @safe
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
     * used for array, binary, binaryFixed, utf8String, fixedUtf8String
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
        version(none)
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
    DbBaseTypeInfo _baseType;
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

    @property final DbCommand command() nothrow pure @safe
    {
        return _command;
    }

    @property final DbDatabase database() nothrow pure @safe
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

    abstract DbField create(DbCommand command, DbIdentitier name) nothrow @safe;

    final DbField create(DbCommand command, string name) nothrow @safe
    {
        DbIdentitier id = DbIdentitier(name);
        return create(command, id);
    }

    /**
     * Implement IDisposable.dispose
     * Will do nothing if called more than one
     */
    final void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        if (!_lastDisposingReason.canDispose(disposingReason))
            return;

        _lastDisposingReason.value = disposingReason;
        doDispose(disposingReason);
    }

    @property final DbCommand command() nothrow pure @safe
    {
        return _command;
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _command !is null ? _command.database : null;
    }

    pragma(inline, true)
    @property final override DisposingReason lastDisposingReason() const @nogc nothrow @safe
    {
        return _lastDisposingReason.value;
    }

protected:
    override void add(DbField item) nothrow
    {
        super.add(item);
        item._ordinal = cast(uint32)length;
    }

    abstract DbFieldList createSelf(DbCommand command) nothrow @safe;

    void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        clear();
        if (isDisposing(disposingReason))
            _command = null;
    }

    void resetNewStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

        if (kind < ResetStatementKind.executing)
            clear();
    }

protected:
    DbCommand _command;

private:
    LastDisposingReason _lastDisposingReason;
}

class DbParameter : DbNameColumn
{
public:
    this(DbDatabase database, DbIdentitier name) nothrow pure @safe
    {
        this._name = name;
        this._flags.set(DbSchemaColumnFlag.allowNull, true);
    }

    final DbParameter cloneMetaInfo(DbParameter source) nothrow pure @safe
    in
    {
        assert(source !is null);
    }
    do
    {
        //this._name = source._name;
        this._baseName = source._baseName;
        this._baseOwner = source._baseOwner;
        this._baseSchemaName = source._baseSchemaName;
        this._baseTableName = source._baseTableName;
        this._baseId = source._baseId;
        this._baseTableId = source._baseTableId;
        this._baseType = source._baseType;
        //this._ordinal = source._ordinal;
        this._size = source._size;
        this._type = source._type;
        this._flags = source._flags;
        this._direction = source._direction;
        return this;
    }

    final bool hasInputValue() const nothrow pure @safe
    {
        return isInput() && !_dbValue.isNull;
    }

    final bool isInput(const(bool) inputOnly = false) const nothrow pure @safe
    {
        static immutable inputFlags = [inputDirections(false), inputDirections(true)];

        return inputFlags[inputOnly].on(direction);
    }

    final bool isOutput(const(bool) outputOnly = false) const nothrow pure @safe
    {
        static immutable outputFlags = [outputDirections(false), outputDirections(true)];

        return outputFlags[outputOnly].on(direction);
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

    @property final bool isNull() const nothrow pure @safe
    {
        return _dbValue.isNull
            || (isDbTypeHasZeroSizeAsNull(type) && _dbValue.size <= 0);
    }

    @property final Variant variant() nothrow @safe
    {
        return _dbValue.value;
    }

    @property final DbParameter variant(Variant variant) nothrow @safe
    {
        this._dbValue.value = variant;
        this.valueAssigned();
        return this;
    }

    /**
     * Gets or sets the value of the parameter
     */
    @property final ref DbValue value() nothrow return @safe
    {
        return _dbValue;
    }

    @property final DbParameter value(DbValue newValue) nothrow @safe
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
        if (type != DbType.unknown)
            _dbValue.type = type;
    }

    final void valueAssigned() nothrow @safe
    {
        if (type == DbType.unknown && _dbValue.type != DbType.unknown)
        {
            if (isDbTypeHasSize(_dbValue.type) && _dbValue.hasSize)
                size = cast(int32)_dbValue.size;
            type = _dbValue.type;
            reevaluateBaseType();
        }
        else if (type != DbType.unknown)
            _dbValue.type = type;
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
        auto id = DbIdentitier(name);
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
        auto id = DbIdentitier(name);
        return add(id, type, direction, size);
    }

    final DbParameter add(string name, DbType type, DbValue value) @safe
    {
        auto result = add(name, type);
        result.value = value;
        return result;
    }

    final DbParameter add(string name, DbType type, Variant value) @safe
    {
        auto result = add(name, type);
        result.variant = value;
        return result;
    }

    final DbParameter addClone(DbParameter source) @safe
    {
        auto result = add(source.name, source.type, source.direction, source.size);
        source.assignTo(result);
        return result;
    }

    final DbParameter create(DbIdentitier name) nothrow @safe
    {
        return database.createParameter(name);
    }

    final DbParameter create(string name) nothrow @safe
    {
        auto id = DbIdentitier(name);
        return database.createParameter(id);
    }

    /**
     * Implement IDisposable.dispose
     * Will do nothing if called more than one
     */
    final void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        if (!_lastDisposingReason.canDispose(disposingReason))
            return;

        _lastDisposingReason.value = disposingReason;
        doDispose(disposingReason);
    }

    final DbIdentitier generateName() nothrow @safe
    {
        return generateUniqueName("parameter");
    }

    final bool hasInput(const(bool) inputOnly = false) const nothrow @safe
    {
        return parameterHasOfs(inputDirections(inputOnly));
    }

    final bool hasOutput(const(bool) outputOnly = false) const nothrow @safe
    {
        return parameterHasOfs(outputDirections(outputOnly));
    }

    final DbParameter hasOutput(string name, size_t outputIndex) nothrow @safe
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

    final size_t inputCount(const(bool) inputOnly = false) const nothrow @safe
    {
        return parameterCountOfs(inputDirections(inputOnly));
    }

    final T[] inputs(T : DbParameter)(const(bool) inputOnly = false) nothrow @safe
    {
        return parameterOfs!T(inputDirections(inputOnly));
    }

    final void nullifyOutputs() nothrow @safe
    {
        foreach (parameter; this)
        {
            enum outputOnly = true;
            if (parameter.isOutput(outputOnly))
                parameter.nullifyValue();
        }
    }

    final size_t outputCount(const(bool) outputOnly = false) const nothrow @safe
    {
        return parameterCountOfs(outputDirections(outputOnly));
    }

    final T[] outputs(T : DbParameter)(const(bool) outputOnly = false) nothrow @safe
    {
        return parameterOfs!T(outputDirections(outputOnly));
    }

    final size_t parameterCountOfs(scope const(EnumSet!DbParameterDirection) directions) const nothrow @safe
    {
        size_t result = 0;
        foreach (item; sequenceItems)
        {
            if (directions.on(item.direction))
                result++;
        }
        return result;
    }

    final bool parameterHasOfs(scope const(EnumSet!DbParameterDirection) directions) const nothrow @safe
    {
        foreach (item; sequenceItems)
        {
            if (directions.on(item.direction))
                return true;
        }
        return false;
    }

    final T[] parameterOfs(T : DbParameter)(scope const(EnumSet!DbParameterDirection) directions) nothrow @safe
    {
        T[] result;
        result.reserve(length);
        foreach (parameter; this)
        {
            if (parameter.baseTypeId == 0)
                parameter.reevaluateBaseType();
            if (directions.on(parameter.direction))
                result ~= cast(T)parameter;
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
        auto id = DbIdentitier(name);
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
        auto id = DbIdentitier(name);
        return touch(id, type, direction, size);
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _database;
    }

    pragma(inline, true)
    @property final override DisposingReason lastDisposingReason() const @nogc nothrow @safe
    {
        return _lastDisposingReason.value;
    }

protected:
    override void add(DbParameter item) nothrow @safe
    {
        super.add(item);
        item._ordinal = cast(uint32)length;
    }

    void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        clear();
        if (isDisposing(disposingReason))
            _database = null;
    }

    void resetNewStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

        if (kind == ResetStatementKind.executing)
            nullifyOutputs();
    }

protected:
    DbDatabase _database;

private:
    LastDisposingReason _lastDisposingReason;
}

struct DbRAIITransaction
{
@safe:

public:
    @disable this(this);
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
    @disable this();
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(DbCommand command, bool implicitTransaction, bool ownCommand) nothrow @safe
    {
        this._command = command;
        this._fields = command.fields;
        this._hasRows = HasRows.unknown;
        this._flags.set(Flag.implicitTransaction, implicitTransaction);
        this._flags.set(Flag.ownCommand, ownCommand);
    }

    ~this() @safe
    {
        dispose(DisposingReason.destructor);
    }

    /*
     * Remove this DbReader from its command
     * Returns:
     *      Self
     */
    ref typeof(this) detach() nothrow return
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        if (_command !is null)
            doDetach(isDisposing(disposingReason));

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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(_fetchedCount=", _fetchedCount, ")");
        version(profile) debug auto p = PerfFunction.create();

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

    @property bool ownCommand() const nothrow pure @safe
    {
        return _flags.on(Flag.ownCommand);
    }
private:
    enum Flag : ubyte
    {
        allRowsFetched,
        cacheResult,
        implicitTransaction,
        ownCommand,
        skipFetchNext,
    }

    enum HasRows : ubyte
    {
        unknown,
        no,
        yes,
    }

    void doDetach(const(bool) disposing) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        _command.removeReader(this);
        scope (exit)
        {
            _command = null;
            _flags.set(Flag.implicitTransaction, false);
            _flags.set(Flag.ownCommand, false);
        }
        if (ownCommand)
            _command.dispose(DisposingReason.dispose);
    }

    bool fetchFirst(const(bool) checking) @safe
    in
    {
         assert(_hasRows == HasRows.unknown);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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

        debug(debug_pham_db_db_database) debug writeln("\t", "_fetchedCount=", _fetchedCount, ", hasRow=", hasRow);

        return hasRow;
    }

    void fetchNext() @safe
    in
    {
         assert(_hasRows == HasRows.yes);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        _currentRow = command.fetch(false);
        const hasRow = _currentRow.length != 0;
        if (hasRow)
            _fetchedCount++;
        else
            _flags.set(Flag.allRowsFetched, true);

        debug(debug_pham_db_db_database) debug writeln("\t", "_fetchedCount=", _fetchedCount, ", hasRow=", hasRow);
    }

    Variant getVariant(const(size_t) index) @safe
    {
        version(profile) debug auto p = PerfFunction.create();

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
     * Returns true if this transaction instance can start a save-point
     */
    bool canSavePoint() @safe
    {
        return state == DbTransactionState.active && isOpenedConnection();
    }

    pragma(inline, true)
    final Logger canErrorLog() nothrow @safe
    {
        return _connection !is null ? _connection.canErrorLog() : null;
    }

    pragma(inline, true)
    final Logger canTraceLog() nothrow @safe
    {
        return _connection !is null ? _connection.canTraceLog() : null;
    }

    /**
     * Performs a commit for this transaction
	 */
    final typeof(this) commit() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.commit(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

        scope (failure)
            resetState(DbTransactionState.error);

        checkState(DbTransactionState.active);
        doCommit(isDisposing(lastDisposingReason));
        if (!handle)
            resetState(DbTransactionState.inactive);

        return this;
    }

    /**
     * Releases a pending transaction save-point
     * Params:
     *  savePointName = The name of the save-point
     */
    final typeof(this) commit(string savePointName) @safe
    in
    {
        assert(savePointName.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.commit(isolationLevel=%s, savePointName=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel), savePointName);

        checkSavePointState();
        auto savePointStatement = createSavePointStatement(DbSavePoint.commit, savePointName);
        _savePointNames.length = checkSavePointName(savePointName);
        doSavePoint(DbSavePoint.commit, savePointName, savePointStatement);

        return this;
    }

    final string forErrorInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forErrorInfo() : null;
    }

    final string forLogInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    /**
     * Returns index of matched existing savePointName;
     * If not found, return -1
     * Params:
     *  savePointName = The name of the save-point to search
     */
    final ptrdiff_t isSavePoint(scope const(char)[] savePointName) const nothrow @safe
    {
        foreach (i, n; _savePointNames)
        {
            if (n == savePointName)
                return i;
        }
        return -1;
    }

    /**
     * Performs a rollback for this transaction
	 */
    final typeof(this) rollback() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.rollback(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

        if (state != DbTransactionState.active)
            return this;

        scope (failure)
            resetState(DbTransactionState.error);

        checkState(DbTransactionState.active);
        doRollback(isDisposing(lastDisposingReason));
        if (!handle)
            resetState(DbTransactionState.inactive);

        return this;
    }

    /**
     * Rolls back a pending transaction save-point
     * Params:
     *  savePointName = The name of the save-point
     */
    final typeof(this) rollback(string savePointName) @safe
    in
    {
        assert(savePointName.length != 0);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.rollback(isolationLevel=%s, savePointName=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel), savePointName);

        checkSavePointState();
        auto savePointStatement = createSavePointStatement(DbSavePoint.rollback, savePointName);
        _savePointNames.length = checkSavePointName(savePointName);
        doSavePoint(DbSavePoint.rollback, savePointName, savePointStatement);

        return this;
    }

    final typeof(this) start() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(autoCommit=", autoCommit, ", isolationLevel=", isolationLevel, ", isRetaining=", isRetaining, ")");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.start(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

        checkState(DbTransactionState.inactive);
        scope (failure)
            resetState(DbTransactionState.error);

        doStart();

        _state = DbTransactionState.active;
        if (_connection !is null)
            _connection._activeTransactionCounter++;

        return this;
    }

    /**
     * Creates a transaction save-point
     * Params:
     *  savePointName = The name of the save-point
     *                  if no name is supplied, a default name is generated as "SAVEPOINT_nnn"
     *                  where nnn is an incremented counter
     */
    final typeof(this) start(string savePointName) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.start(isolationLevel=%s, savePointName=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel), savePointName);

        checkSavePointState();
        if (savePointName.length == 0)
            savePointName = "SAVEPOINT_" ~ _connection.nextCounter().to!string();
        auto savePointStatement = createSavePointStatement(DbSavePoint.start, savePointName);
        doSavePoint(DbSavePoint.start, savePointName, savePointStatement);
        _savePointNames ~= savePointName;
        return this;
    }

    /**
     * Should it performs a commit of this pending transaction instance is out of scope
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

    /**
     * Returns true if having pending save-point to be released or rollback
     */
    @property final bool hasSavePoint() const nothrow @safe
    {
        return _savePointNames.length != 0;
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

    @property final string lastPointName() const nothrow pure @safe
    {
        return _savePointNames.length ? _savePointNames[$-1] : null;
    }

    @property final DbLockTable[] lockedTables() nothrow pure @safe
    {
        return _lockedTables;
    }

    /**
     * Transaction lock time-out
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

    pragma(inline, true)
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
     * Current list of pending save-point names
     */
    @property final const(string)[] savePointNames() const nothrow pure @safe
    {
        return _savePointNames;
    }

    /**
     * Indicator of current state of transaction
	 */
    @property final DbTransactionState state() const nothrow pure @safe
    {
        return _state;
    }

package(pham.db):
    /**
     * Performs a rollback for this transaction but trap all errors
	 */
    final typeof(this) rollbackError() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.transaction.rollbackError(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

        if (state != DbTransactionState.active)
            return this;

        try
        {
            checkState(DbTransactionState.active);
            doRollback(isDisposing(lastDisposingReason));
            if (!handle)
                resetState(DbTransactionState.inactive);
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.transaction.rollbackError(isolationLevel=%s) - %s", forLogInfo(), toName!DbIsolationLevel(isolationLevel), e.msg, e);

            if (!canRetain())
                resetState(DbTransactionState.error);
            else if (!handle)
                resetState(DbTransactionState.inactive);
        }

        return this;
    }

protected:
    enum DbSavePoint : char
    {
        start = 'S',
        commit = 'C',
        rollback = 'R',
    }

    enum DbTransactionFlag : ubyte
    {
        autoCommit,
        readOnly,
        retaining,
    }

    final bool canRetain() const nothrow @safe
    {
        return isRetaining && isOpenedConnection() && !isDisposing(lastDisposingReason);
    }

    final ptrdiff_t checkSavePointName(string savePointName,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(savePointName=", savePointName, ", funcName=", funcName, ")");

        const index = isSavePoint(savePointName);
        if (index < 0)
        {
            auto msg = DbMessage.eInvalidTransactionSavePoint.fmtMessage(funcName, savePointName);
            throw new DbException(0, msg, null, funcName, file, line);
        }
        return index;
    }

    final void checkSavePointState(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        try
        {
            checkState(DbTransactionState.active, funcName, file, line);
        }
        catch (Exception ex)
        {
            resetState(DbTransactionState.error);
            throw ex;
        }
    }

    final void checkState(const(DbTransactionState) checkingState,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(checkingState=", checkingState, ", funcName=", funcName, ")");

        if (_state != checkingState)
        {
            auto msg = DbMessage.eInvalidTransactionState.fmtMessage(funcName, toName!DbTransactionState(_state), toName!DbTransactionState(checkingState));
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }

        if (_connection is null)
        {
            auto msg = DbMessage.eCompletedTransaction.fmtMessage(funcName);
            throw new DbException(0, msg, null, funcName, file, line);
        }

        _connection.checkActive(funcName, file, line);
    }

    string createSavePointStatement(const(DbSavePoint) mode, string savePointName) const @safe nothrow
    in
    {
        assert(savePointName.length > 0);
    }
    do
    {
        final switch (mode)
        {
            case DbSavePoint.start:
                return "SAVEPOINT " ~ savePointName;
            case DbSavePoint.commit:
                return "RELEASE SAVEPOINT " ~ savePointName;
            case DbSavePoint.rollback:
                return "ROLLBACK TO SAVEPOINT " ~ savePointName;
        }
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        try
        {
            if (_state == DbTransactionState.active && isOpenedConnection())
            {
                if (autoCommit)
                    commit();
                else
                    rollback();
            }
        }
        catch (Exception e)
        {
            if (auto log = canErrorLog())
                log.errorf("%s.transaction.doDispose() - %s", forLogInfo(), e.msg, e);
        }

        if (_connection !is null)
            _connection.removeTransaction(this);

        _state = DbTransactionState.disposed;
        _savePointNames = null;
        _lockedTables = null;
        _handle.reset();
        _connection = null;
        _database = null;
        _next = null;
        _prev = null;
    }

    void doSavePoint(const(DbSavePoint) mode, string savePointName, string savePointStatement) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(savePointStatement=", savePointStatement, ")");

        auto command = connection.createNonTransactionCommand();
        scope (exit)
            command.dispose();

        command.commandText = savePointStatement;
        command.transaction = this;
        command.executeNonQuery();
    }

    final bool isOpenedConnection() const nothrow @safe
    {
        return _connection !is null && _connection.state == DbConnectionState.opened && !_connection.isFatalError;
    }

    void resetState(const(DbTransactionState) toState) nothrow @safe
    {
        if (_state == DbTransactionState.active && toState != DbTransactionState.active && _connection !is null)
            _connection._activeTransactionCounter--;

        _savePointNames = null;
        _state = toState;
        _handle.reset();

        if (toState == DbTransactionState.error && !isDefault)
            doDispose(DisposingReason.other);
    }

    abstract void doCommit(bool disposing) @safe;
    abstract void doRollback(bool disposing) @safe;
    abstract void doStart() @safe;

protected:
    DbConnection _connection;
    DbDatabase _database;
    string[] _savePointNames;
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

__gshared static Timer _secondTimer;

shared static this() nothrow
{
    debug(debug_pham_db_db_database) debug writeln("shared static this()");

    _secondTimer = new Timer(dur!"seconds"(1));
}

shared static ~this() nothrow
{
    debug(debug_pham_db_db_database) debug writeln("shared static ~this()");

    if (_secondTimer !is null)
        _secondTimer.enabled = false;

    DbConnectionPool.cleanup();
    DbDatabaseList.cleanup();

    if (_secondTimer !is null)
    {
        _secondTimer.destroy();
        _secondTimer = null;
    }
}
