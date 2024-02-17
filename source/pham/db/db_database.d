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

import core.atomic : atomicFetchAdd, atomicFetchSub, atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
public import core.time : Duration, dur;
import std.array : Appender;
public import std.ascii : newline;
import std.conv : to;
import std.format : format;
import std.traits : FieldNameTuple;
import std.typecons : Flag, No, Yes;

debug(debug_pham_db_db_database) import std.stdio : writeln;

version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.std.log.log_logger : Logger, LogLevel;
import pham.utl.utl_delegate_list;
import pham.utl.utl_dlink_list;
import pham.utl.utl_enum_set : EnumSet, toEnum, toName;
import pham.utl.utl_disposable;
import pham.utl.utl_object : RAIIMutex, singleton;
import pham.utl.utl_system : currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.utl.utl_timer;
import pham.utl.utl_utf8 : nextUTF8Char;
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

        checkActive();

        if (auto log = canTraceLog())
            log.infof("%s.command.cancel()%s%s", forLogInfo(), newline, commandText);

        _connection.cancelCommand(this);
        return this;
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

    pragma(inline, true)
    final Logger canTimeLog() nothrow @safe
    {
        return _connection !is null ? _connection.canTimeLog() : null;
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

        checkCommand(-1);

        if (auto log = canTraceLog())
            log.infof("%s.command.executeNonQuery()%s%s", forLogInfo(), newline, commandText);

        bool implicitTransactionCalled = false;
        bool unprepareCalled = false;
        const wasPrepared = prepared;
        resetNewStatement(ResetStatementKind.execute);
        const implicitTransaction = setImplicitTransactionIf();

        void resetImplicitTransaction(const(bool) isError) @safe
        {
            if (!implicitTransactionCalled && implicitTransaction)
            {
                implicitTransactionCalled = true;
                const flags = isError
                    ? ResetImplicitTransactiontFlag.nonQuery | ResetImplicitTransactiontFlag.error
                    : ResetImplicitTransactiontFlag.nonQuery;
                resetImplicitTransactionIf(cast(ResetImplicitTransactiontFlag)flags);
            }
        }

        void restStatement(const(bool) isError) @safe
        {
            if (!unprepareCalled && !wasPrepared && prepared)
            {
                unprepareCalled = true;
                unprepare();
            }
        }

        scope (exit)
        {
            resetImplicitTransaction(false);
            restStatement(false);
        }
        scope (failure)
        {
            resetImplicitTransaction(true);
            restStatement(true);
        }

        doExecuteCommand(DbCommandExecuteType.nonQuery);
        auto result = recordsAffected;
        doNotifyMessage();
        return result;
    }

    final DbReader executeReader() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkCommand(DbCommandType.ddl);

        if (auto log = canTraceLog())
            log.infof("%s.command.executeReader()%s%s", forLogInfo(), newline, commandText);

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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkCommand(DbCommandType.ddl);

        if (auto log = canTraceLog())
            log.infof("%s.command.executeScalar()%s%s", forLogInfo(), newline, commandText);

        bool implicitTransactionCalled = false;
        bool unprepareCalled = false;
        const wasPrepared = prepared;
        resetNewStatement(ResetStatementKind.execute);
        const implicitTransaction = setImplicitTransactionIf();

        void resetImplicitTransaction(const(bool) isError) @safe
        {
            if (!implicitTransaction && implicitTransaction)
            {
                implicitTransactionCalled = true;
                resetImplicitTransactionIf(isError ? ResetImplicitTransactiontFlag.error : ResetImplicitTransactiontFlag.none);
            }
        }

        void restStatement(const(bool) isError) @safe
        {
            if (!unprepareCalled && !wasPrepared && prepared)
            {
                unprepareCalled = true;
                unprepare();
            }
        }

        scope (exit)
        {
            resetImplicitTransaction(false);
            restStatement(false);
        }
        scope (failure)
        {
            resetImplicitTransaction(true);
            restStatement(true);
        }

        doExecuteCommand(DbCommandExecuteType.scalar);
        auto values = fetch(true);
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

    final string forErrorInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forErrorInfo() : null;
    }

    final string forLogInfo() const nothrow @safe
    {
        return _connection !is null ? _connection.forLogInfo() : null;
    }

    abstract const(char)[] getExecutionPlan(uint vendorMode = 0) @safe;

    final DbParameter[] inputParameters() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        return hasParameters ? parameters.inputParameters() : null;
    }

    final typeof(this) prepare() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");
        assert(!prepared, "command already prepared");

        if (prepared)
            return this;

        checkCommand(-1);

        if (auto log = canTraceLog())
            log.infof("%s.command.prepare()%s%s", forLogInfo(), newline, commandText);

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

        void unprepareExit() @safe
        {
            resetNewStatement(ResetStatementKind.unprepare);

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

        if (auto log = canTraceLog())
            log.infof("%s.command.unprepare()%s%s", forLogInfo(), newline, commandText);

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
    @property final size_t hasParameters() const nothrow pure @safe
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

    /**
     * Gets the inserted id after executed a commandText if applicable
     */
    @property final DbRecordsAffected lastInsertedId() const nothrow pure @safe
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
    @property final void allRowsFetched(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.allRowsFetched, value);
    }

    @property final void batched(bool value) nothrow pure @safe
    {
        _flags.set(DbCommandFlag.batched, value);
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
    enum BuildCommandTextState : ubyte
    {
        execute,
        executingPlan,
        prepare,
    }

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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ", state=", state, ")");

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

    typeof(this) doCommandText(string commandText, DbCommandType type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(type=", type, ", commandText=", commandText, ")");

        if (prepared)
            unprepare();

        clearParameters();
        _executeCommandText = null;
        _commandText = commandText;
        return commandType(type);
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

    final void doNotifyMessage() nothrow @trusted
    {
        if (notificationMessages.length == 0)
            return;
        scope (exit)
            notificationMessages.length = 0;

        if (notifyMessage)
        {
            // Special try construct for grep
            try {
                notifyMessage(this, notificationMessages);
            } catch(Exception) {}
        }
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

    final bool needPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(type=", type, ")");

        return !prepared
            && commandType != DbCommandType.table
            && (parametersCheck || hasParameters);
    }

    void prepareExecuting(const(DbCommandExecuteType) type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(type=", type, ")");

        _lastInsertedId.reset();
        _recordsAffected.reset();
        allRowsFetched(false);

        executeCommandText(BuildCommandTextState.execute); // Make sure _executeCommandText is initialized

        if (hasParameters)
            parameters.nullifyOutputParameters();
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

    enum ResetStatementKind : ubyte
    {
        unprepare,
        prepare,
        execute,
    }

    void resetNewStatement(const(ResetStatementKind) kind) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

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

    final bool setImplicitTransactionIf() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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

    final void cancelCommand(DbCommand command = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();
        auto data = createCancelCommandData(command);
        cancelCommand(command, data);
    }

    final void cancelCommand(DbCommand command, DbCancelCommandData data) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();

        if (auto log = canTraceLog())
            log.infof("%s.connection.cancelCommand()", forLogInfo());

        notificationMessages.length = 0;
        if (command !is null)
            command._flags.set(DbCommandFlag.cancelled, true);
        doCancelCommand(data);
        doNotifyMessage();
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

        if (_poolList !is null)
        {
            if (auto log = canTraceLog())
                log.infof("%s.connection.close()", forLogInfo());

            return _poolList.release(this);
        }

        const previousState = state;
        if (previousState == DbConnectionState.closed)
            return this;

        if (auto log = canTraceLog())
            log.infof("%s.connection.close()", forLogInfo());

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

    abstract DbCancelCommandData createCancelCommandData(DbCommand command = null) @safe;

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

        const previousState = state;
        if (previousState == DbConnectionState.opened)
            return this;

        if (auto log = canTraceLog())
            log.infof("%s.connection.open()", forLogInfo());

        reset();
        _state = DbConnectionState.opening;
        doBeginStateChange(DbConnectionState.opening);

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
        doNotifyMessage();

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

    final size_t nextCounter() nothrow @safe
    {
        return (++_nextCounter);
    }

    void fatalError(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        _fatalError = true;
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
        return _transactions.insertEnd(result);
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

        if (notifyMessage)
        {
            // Special try construct for grep
            try {
                notifyMessage(this, notificationMessages);
            } catch(Exception) {}
        }
        notificationMessages.length = 0;
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
        _readerCounter = 0;
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
    int _readerCounter;
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

    final DbConnection[] removeInactives(scope const(DateTime) now, scope const(Duration) maxInactiveTime) nothrow @safe
    {
        DbConnection[] result;
        result.reserve(length);

        // Iterate and get inactive connections
        foreach (connection; this)
        {
            const elapsed = now - connection._inactiveTime;
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
            throw new DbException(DbErrorCode.connect, msg);
        }

        bool created;
        auto database = DbDatabaseList.getDb(scheme);
        auto lst = schemeConnections(database, connectionString);
        auto result = lst.acquire(created);
        atomicFetchAdd(_acquiredLength, 1);
        if (!created)
            atomicFetchSub(_length, 1);
        return result;
    }

    final DbConnection acquire(DbConnectionStringBuilder connectionStringBuilder) @safe
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

    final DbConnection release(DbConnection item) nothrow @safe
    in
    {
        assert(item !is null);
    }
    do
    {
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

        auto raiiMutex = () @trusted { return RAIIMutex(_poolMutex); }();
        const localMaxLength = maxLength;

        // Over limit?
        if (atomicLoad(_length) + 1 >= localMaxLength)
            return DbConnectionList.disposeConnection(item);

        poolList.doRelease(item);
        atomicFetchSub(_acquiredLength, 1);
        atomicFetchAdd(_length, 1);

        return null;
    }

    @property final size_t acquiredLength() const nothrow @safe
    {
        return atomicLoad(_acquiredLength);
    }

    @property final size_t length() const nothrow pure @safe
    {
        return atomicLoad(_length);
    }

    @property final size_t maxLength() const nothrow pure @safe
    {
        return atomicLoad(_maxLength);
    }

    @property final typeof(this) maxLength(size_t value) nothrow pure @safe
    {
        atomicStore(_maxLength, value);
        return this;
    }

protected:
    static DbConnectionPool createInstance() nothrow pure @safe
    {
        return new DbConnectionPool();
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        scope (failure) assert(0, "Assume nothrow failed");

        foreach (_, lst; _schemeConnections)
            lst.dispose(disposingReason);
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
                result ~= inactives;
                atomicFetchSub(_length, inactives.length);
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

    override DbNameValueValidated isValid(const(DbIdentitier) name, string value) nothrow
    {
        const rs = super.isValid(name, value);
        if (rs != DbNameValueValidated.ok)
            return rs;

        const n = name in getValidParamNameChecks();
        if (n is null)
            return DbNameValueValidated.invalidName;

        const v = name in dbIsConnectionParameterValues;
        if (v is null || (*v)(value) != DbNameValueValidated.ok)
            return DbNameValueValidated.invalidValue;

        return DbNameValueValidated.ok;
    }

    /**
     * Returns list of valid parameter names for connection string
     */
    abstract const(string[]) parameterNames() const nothrow;

    typeof(this) parseConnectionString(string connectionString)
    {
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
                    addLine(errorMessage, "Invalid name: " ~ o.name);
                    break;
                case duplicateName:
                    addLine(errorMessage, "Duplicate name: " ~ o.name);
                    break;
                case invalidValue:
                    addLine(errorMessage, "Invalid value of " ~ o.name ~ ": " ~ o.value);
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

    final override size_t toHash() nothrow
    {
        return this.connectionString.hashOf();
    }

    @property final bool allowBatch() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.allowBatch));
    }

    @property final typeof(this) allowBatch(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.allowBatch, setValue);
        return this;
    }

    @property final string applicationName() const nothrow
    {
        return customAttributes.get(DbConnectionCustomIdentifier.applicationName, null);
    }

    @property final typeof(this) applicationName(string value) nothrow
    {
        customAttributes.put(DbConnectionCustomIdentifier.applicationName, value);
        return this;
    }

    @property final string applicationVersion() const nothrow
    {
        return customAttributes.get(DbConnectionCustomIdentifier.applicationVersion, null);
    }

    @property final typeof(this) applicationVersion(string value) nothrow
    {
        customAttributes.put(DbConnectionCustomIdentifier.applicationVersion, value);
        return this;
    }

    @property final string charset() const nothrow
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
    @property final Duration commandTimeout() const nothrow
    {
        return secondDigitsToDurationSafe(getString(DbConnectionParameterIdentifier.commandTimeout), Duration.zero);
    }

    @property final typeof(this) commandTimeout(scope const(Duration) value) nothrow
    {
        // Optional value
        auto secondValue = limitRangeTimeoutAsSecond(value).to!string();
        put(DbConnectionParameterIdentifier.commandTimeout, secondValue);
        return this;
    }

    @property final DbCompressConnection compress() const nothrow
    {
        // Backward compatible with previous version(bool value)
        const s = getString(DbConnectionParameterIdentifier.compress);
        if (s == dbBoolFalse)
            return DbCompressConnection.disabled;
        else if (s == dbBoolTrue)
            return DbCompressConnection.zip;
        else
            return toEnum!DbCompressConnection(s);
    }

    @property final typeof(this) compress(DbCompressConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.compress, toName(value));
        return this;
    }

    /**
     *The connection string used to establish the initial connection.
     */
    @property final string connectionString() nothrow
    {
        assert(elementSeparators.length != 0);

        return getDelimiterText(this, elementSeparators[0], valueSeparator);
    }

    /**
     * Gets or sets the time (value based in seconds) to wait for a connection to open.
     * The default value is 10 seconds.
     */
    @property final Duration connectionTimeout() const nothrow
    {
        return secondDigitsToDurationSafe(getString(DbConnectionParameterIdentifier.connectionTimeout), Duration.zero);
    }

    @property final typeof(this) connectionTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = limitRangeTimeoutAsSecond(value);
        auto setValue = convertingSecond != 0 ? convertingSecond.to!string() : getDefault(DbConnectionParameterIdentifier.connectionTimeout);
        put(DbConnectionParameterIdentifier.connectionTimeout, setValue);
        return this;
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

    @property final typeof(this) databaseName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.databaseName, value);
        return this;
    }

    /**
     * The file-name of the database; value of "databaseFile"
     */
    @property final string databaseFileName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.databaseFile);
    }

    @property final typeof(this) databaseFileName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.databaseFile, value);
        return this;
    }

    @property final string elementSeparators() const nothrow
    {
        return _elementSeparators;
    }

    @property final DbEncryptedConnection encrypt() const nothrow
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
    @property final uint32 fetchRecordCount() const nothrow
    {
        return toIntegerSafe!uint32(getString(DbConnectionParameterIdentifier.fetchRecordCount), uint8.max);
    }

    @property final typeof(this) fetchRecordCount(uint32 value) nothrow
    {
        // Required value
        auto setValue = value != 0 ? value.to!string() : getDefault(DbConnectionParameterIdentifier.fetchRecordCount);
        put(DbConnectionParameterIdentifier.fetchRecordCount, setValue);
        return this;
    }

    @property final DbIntegratedSecurityConnection integratedSecurity() const nothrow
    {
        return toEnum!DbIntegratedSecurityConnection(getString(DbConnectionParameterIdentifier.integratedSecurity));
    }

    @property final typeof(this) integratedSecurity(DbIntegratedSecurityConnection value) nothrow
    {
        put(DbConnectionParameterIdentifier.integratedSecurity, toName(value));
        return this;
    }

    @property final uint32 maxPoolCount() const nothrow
    {
        return toIntegerSafe!uint32(getString(DbConnectionParameterIdentifier.maxPoolCount), uint8.max);
    }

    @property final typeof(this) maxPoolCount(uint32 value) nothrow
    {
        put(DbConnectionParameterIdentifier.maxPoolCount, value.to!string());
        return this;
    }

    @property final uint32 minPoolCount() const nothrow
    {
        return toIntegerSafe!uint32(getString(DbConnectionParameterIdentifier.minPoolCount), 0);
    }

    @property final typeof(this) minPoolCount(uint32 value) nothrow
    {
        put(DbConnectionParameterIdentifier.minPoolCount, value.to!string());
        return this;
    }

    @property final uint32 packageSize() const nothrow
    {
        return toIntegerSafe!uint32(getString(DbConnectionParameterIdentifier.packageSize), uint16.max);
    }

    @property final typeof(this) packageSize(uint32 value) nothrow
    {
        // Required value
        auto setValue = value != 0 ? value.to!string() : getDefault(DbConnectionParameterIdentifier.packageSize);
        put(DbConnectionParameterIdentifier.packageSize, setValue);
        return this;
    }

    @property final bool pooling() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.pooling));
    }

    @property final typeof(this) pooling(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.pooling, setValue);
        return this;
    }

    @property final Duration poolTimeout() const nothrow
    {
        return secondDigitsToDurationSafe(getString(DbConnectionParameterIdentifier.poolTimeout), Duration.zero);
    }

    @property final typeof(this) poolTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = limitRangeTimeoutAsSecond(value);
        auto setValue = convertingSecond != 0 ? convertingSecond.to!string() : getDefault(DbConnectionParameterIdentifier.poolTimeout);
        put(DbConnectionParameterIdentifier.poolTimeout, setValue);
        return this;
    }

    /**
     * Gets or sets the time (value based in seconds) to wait for a server to send back request's result.
     * The default value is 3_600 seconds (1 hour).
     * Set to zero to disable the setting.
     */
    @property final Duration receiveTimeout() const nothrow
    {
        return secondDigitsToDurationSafe(getString(DbConnectionParameterIdentifier.receiveTimeout), Duration.zero);
    }

    @property final typeof(this) receiveTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = limitRangeTimeoutAsSecond(value);
        auto setValue = convertingSecond != 0 ? convertingSecond.to!string() : getDefault(DbConnectionParameterIdentifier.receiveTimeout);
        put(DbConnectionParameterIdentifier.receiveTimeout, setValue);
        return this;
    }

    @property final string roleName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.roleName);
    }

    @property final typeof(this) roleName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.roleName, value);
        return this;
    }

    @property abstract DbScheme scheme() const nothrow pure;

    /**
     * Gets or sets the time (value based in seconds) to wait for a request to completely send to server.
     * The default value is 60 seconds.
     * Set to zero to disable the setting.
     */
    @property final Duration sendTimeout() const nothrow
    {
        return secondDigitsToDurationSafe(getString(DbConnectionParameterIdentifier.sendTimeout), Duration.zero);
    }

    @property final typeof(this) sendTimeout(scope const(Duration) value) nothrow
    {
        // Required value
        const convertingSecond = limitRangeTimeoutAsSecond(value);
        auto setValue = convertingSecond != 0 ? convertingSecond.to!string() : getDefault(DbConnectionParameterIdentifier.sendTimeout);
        put(DbConnectionParameterIdentifier.sendTimeout, setValue);
        return this;
    }

    /**
     * The name of the database server; value of "server"
     */
    @property final string serverName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.serverName);
    }

    @property final typeof(this) serverName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.serverName, value);
        return this;
    }

    @property final uint16 serverPort() const nothrow
    {
        const result = toIntegerSafe!uint16(getString(DbConnectionParameterIdentifier.serverPort), 0);
        return result != 0 ? result : toIntegerSafe!uint16(getDefault(DbConnectionParameterIdentifier.serverPort), 0);
    }

    @property final typeof(this) serverPort(uint16 value) nothrow
    {
        auto setValue = value != 0 ? value.to!string() : getDefault(DbConnectionParameterIdentifier.serverPort);
        put(DbConnectionParameterIdentifier.serverPort, setValue);
        return this;
    }

    /**
     * Returns value of "user"
     */
    @property final string userName() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.userName);
    }

    @property final typeof(this) userName(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.userName, value);
        return this;
    }

    /**
     * Returns value of "password"
     */
    @property final string userPassword() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.userPassword);
    }

    @property final typeof(this) userPassword(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.userPassword, value);
        return this;
    }

    @property final char valueSeparator() const nothrow
    {
        return _valueSeparator;
    }

protected:
    string getDefault(string name) const nothrow
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto n = DbIdentitier(name);
        return dbDefaultConnectionParameterValues.get(n, null);
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
        foreach (dpv; dbDefaultConnectionParameterValues.byKeyValue)
            putIf(dpv.key, dpv.value);
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

    final const(char)[] escapeIdentifier(return const(char)[] value) pure
    {
        if (value.length == 0)
            return value;

        size_t p;
        dchar cCode;
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

        auto result = Appender!string();
        result.reserve(value.length + 100);
        if (p)
            result.put(value[0..p]);
        while (p < value.length)
        {
            if (!nextUTF8Char(value, p, cCode, cCount))
                cCode = replacementChar;

            const cc = charClass(cCode);
            if (cc == CharClass.quote)
                result.put(cCode);
            else if (cc == CharClass.backslash)
                result.put('\\');
            result.put(cCode);

            p += cCount;
        }
        return result.data;
    }

    final const(char)[] escapeString(return const(char)[] value) pure
    {
        if (value.length == 0)
            return value;

        size_t p;
        dchar cCode;
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

        auto result = Appender!string();
        result.reserve(value.length + 100);
        if (p)
            result.put(value[0..p]);
        while (p < value.length)
        {
            if (!nextUTF8Char(value, p, cCode, cCount))
                cCode = replacementChar;

            if (charClass(cCode) != CharClass.any)
                result.put('\\');
            result.put(cCode);

            p += cCount;
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

    debug(debug_pham_db_db_database)
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

    abstract DbField createField(DbCommand command, DbIdentitier name) nothrow @safe;
    abstract DbFieldList createSelf(DbCommand command) nothrow @safe;

    final DbField createField(DbCommand command, string name) nothrow @safe
    {
        DbIdentitier id = DbIdentitier(name);
        return createField(command, id);
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

    void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        clear();
        if (isDisposing(disposingReason))
            _command = null;
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

    @property final bool isNull() const nothrow pure @safe
    {
        return _dbValue.isNull || (isDbTypeHasZeroSizeAsNull(type) && _dbValue.size <= 0);
    }

    @property final Variant variant() @safe
    {
        return _dbValue.value;
    }

    @property final DbParameter variant(Variant variant) @safe
    {
        this._dbValue.value = variant;
        this.valueAssigned();
        return this;
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

    final DbParameter add(string name, DbValue value) @safe
    {
        auto result = add(name, DbType.unknown);
        result.value = value;
        return result;
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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(DbCommand command, bool implicitTransaction) nothrow @safe
    {
        this._command = command;
        this._fields = command.fields;
        this._hasRows = HasRows.unknown;
        this._flags.set(Flag.implicitTransaction, implicitTransaction);
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

private:
    enum Flag : ubyte
    {
        allRowsFetched,
        cacheResult,
        implicitTransaction,
        skipFetchNext,
    }

    enum HasRows : ubyte
    {
        unknown,
        no,
        yes,
    }

    void doDetach(bool disposing) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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

        scope (failure)
            resetState(DbTransactionState.error);
        checkState(DbTransactionState.active);

        if (auto log = canTraceLog())
            log.infof("%s.transaction.commit(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

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

        checkSavePointState();
        _savePointNames.length = checkSavePointName(savePointName);

        if (auto log = canTraceLog())
            log.infof("%s.transaction.commit(isolationLevel=%s, savePointName=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel), savePointName);

        doSavePoint(savePointName, "RELEASE SAVEPOINT " ~ savePointName);
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

        if (state != DbTransactionState.active)
            return this;

        scope (failure)
            resetState(DbTransactionState.error);
        checkState(DbTransactionState.active);

        if (auto log = canTraceLog())
            log.infof("%s.transaction.rollback(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

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

        checkSavePointState();
        _savePointNames.length = checkSavePointName(savePointName);

        if (auto log = canTraceLog())
            log.infof("%s.transaction.rollback(isolationLevel=%s, savePointName=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel), savePointName);

        doSavePoint(savePointName, "ROLLBACK TO SAVEPOINT " ~ savePointName);
        return this;
    }

    final typeof(this) start() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(autoCommit=", autoCommit, ", isolationLevel=", isolationLevel, ", isRetaining=", isRetaining, ")");

        checkState(DbTransactionState.inactive);
        scope (failure)
            resetState(DbTransactionState.error);

        if (auto log = canTraceLog())
            log.infof("%s.transaction.start(isolationLevel=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel));

        doStart();
        _state = DbTransactionState.active;
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

        checkSavePointState();
        if (savePointName.length == 0)
            savePointName = "SAVEPOINT_" ~ _connection.nextCounter().to!string();

        if (auto log = canTraceLog())
            log.infof("%s.transaction.start(isolationLevel=%s, savePointName=%s)", forLogInfo(), toName!DbIsolationLevel(isolationLevel), savePointName);

        doSavePoint(savePointName, "SAVEPOINT " ~ savePointName);
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

protected:
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

    void doSavePoint(string savePointName, string savePointStatement) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(savePointStatement=", savePointStatement, ")");

        auto command = connection.createCommand();
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

__gshared static Mutex _poolMutex;
__gshared static TimerThread _secondTimer;

shared static this() nothrow @trusted
{
    _poolMutex = new Mutex();
    _secondTimer = new TimerThread(dur!"seconds"(1));

    // Add pool event to timer
    auto pool = DbConnectionPool.instance;
    _secondTimer.addEvent(TimerEvent("DbConnectionPool", dur!"minutes"(1), &pool.doTimer));
}

shared static ~this() nothrow @trusted
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
