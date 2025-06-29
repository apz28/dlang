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
public import std.ascii : newline;
import std.conv : to;
import std.traits : FieldNameTuple, Unqual;

debug(debug_pham_db_db_database) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.external.std.log.log_logger : Logger, LogLevel;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_delegate_list;
import pham.utl.utl_dlink_list;
import pham.utl.utl_enum_set : EnumSet, toEnum, toName;
import pham.utl.utl_disposable;
import pham.utl.utl_object : RAIIMutex, singleton;
import pham.utl.utl_system : currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.utl.utl_timer;
import pham.utl.utl_utf8 : encodeUTF8, nextUTF8Char, UTF8Iterator;
import pham.db.db_convert;
public import pham.db.db_exception;
import pham.db.db_message;
import pham.db.db_object;
import pham.db.db_parser;
public import pham.db.db_type;
import pham.db.db_util;
public import pham.db.db_value;

/**
 * A delegate to load blob/clob data to send to database server
 * Params:
 *  sender = an object that the delegate calling from (DbParameter...)
 *  loadedLength = an accumulated length in bytes that loaded so far
 *  segmentLength = an adviced length in bytes that sending to database server at once
 *  data = set to ubyte array that contains the data to be sent
 * Returns:
 *  a length in bytes that data held or 0 if no data to be sent
 */
alias LoadLongData = size_t delegate(Object sender, int64 loadedLength, size_t segmentLength,
    ref scope const(ubyte)[] data) @safe;

/**
 * A delegate to save blob/clob data to receive from database server
 * Params:
 *  sender = an object that the delegate calling from (DbParameter...)
 *  savedLength = an accumulated length in bytes that saved so far
 *  blobLength = total length of blob if known, -1 otherwise
 *  data = set to ubyte array that contains the data to be received
 * Returns:
 *  0=continue saving, none zero=stop saving
 */
alias SaveLongData = int delegate(Object sender, int64 savedLength, int64 blobLength, size_t row,
    scope const(ubyte)[] data) @safe;

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

class DbColumn : DbNamedColumn
{
public:
    this(DbDatabase database, DbCommand command, DbIdentitier name) nothrow @safe
    {
        this._database = database;
        this._command = command;
        this._name = name;
        this._flags.allowNull = true;
    }

    final typeof(this) clone(DbCommand command) nothrow @safe
    {
        auto result = createSelf(command);
        assignTo(result);
        return result;
    }

    abstract DbColumn createSelf(DbCommand command) nothrow @safe;

    static string generateName(uint32 ordinal) nothrow pure @safe
    {
        import pham.utl.utl_object : nToString = toString;

        auto buffer = Appender!string(anonymousColumnNamePrefix.length + 10);
        return buffer.put(anonymousColumnNamePrefix)
            .nToString(ordinal)
            .data;
    }

    /** Gets or sets whether this column is aliased
    */
    @property final bool isAlias() const nothrow @safe
    {
        return _flags.isAlias;
    }

    @property final typeof(this) isAlias(bool value) nothrow @safe
    {
        _flags.isAlias = value;
        return this;
    }

    /**
     * Gets or sets whether this column is an expression
     */
    @property final bool isExpression() const nothrow @safe
    {
        return _flags.isExpression;
    }

    @property final typeof(this) isExpression(bool value) nothrow @safe
    {
        _flags.isExpression = value;
        return this;
    }

    /**
     * Gets or sets whether a unique constraint applies to this column
     */
    @property final bool isUnique() const nothrow @safe
    {
        return _flags.isUnique;
    }

    @property final typeof(this) isUnique(bool value) nothrow @safe
    {
        _flags.isUnique = value;
        return this;
    }

protected:
    void resetStatement(const(ResetStatementKind) kind) nothrow @safe
    {}
}

class DbColumnList : DbNamedObjectList!DbColumn, IDisposable
{
public:
    this(DbDatabase database, DbCommand command) nothrow @safe
    {
        this._database = database;
        this._command = command;
    }

    final typeof(this) clone(DbCommand command) nothrow @safe
    {
        auto result = createSelf(command);
        foreach (column; this)
            result.add(column.clone(command));
        return result;
    }

    final DbColumn create(DbIdentitier name) nothrow @safe
    in
    {
        assert(database !is null);
    }
    do
    {
        return database.createColumn(command, name);
    }

    final DbColumn create(string name) nothrow @safe
    in
    {
        assert(database !is null);
    }
    do
    {
        DbIdentitier id = DbIdentitier(name);
        return database.createColumn(command, id);
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
        return _database;
    }

    pragma(inline, true)
    @property final override DisposingReason lastDisposingReason() const @nogc nothrow @safe
    {
        return _lastDisposingReason.value;
    }

    @property final uint16 saveLongDataCount() const @nogc nothrow @safe
    {
        return _saveLongDataCount;
    }

protected:
    abstract DbColumnList createSelf(DbCommand command) nothrow @safe;

    void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        clear();
        if (isDisposing(disposingReason))
        {
            _command = null;
            _database = null;
        }
    }

    final void resetStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

        if (kind == ResetStatementKind.unprepared || kind == ResetStatementKind.preparing)
            clear();
        else
        {
            foreach (column; this)
                column.resetStatement(kind);
        }
    }

    override void notify(DbColumn item, const(NotificationKind) kind) nothrow @safe
    {
        //super.notify(item, kind);
        if (kind == NotificationKind.added)
            item._ordinal = cast(uint32)length;
        else if (kind == NotificationKind.cleared)
            _saveLongDataCount = 0;
    }

protected:
    DbCommand _command;
    DbDatabase _database;
    uint16 _saveLongDataCount;

private:
    LastDisposingReason _lastDisposingReason;
}

package(pham.db) enum BuildCommandTextState : ubyte
{
    prepare,
    executingPlan,
    execute,
}

package(pham.db) enum ResetStatementKind : ubyte
{
    unprepared,
    preparing,
    prepared,
    executing,
    executed,
    fetching,
    fetched,
}

abstract class DbCommand : DbDisposableObject
{
public:
    this(DbDatabase database, DbConnection connection,
        string name = null) nothrow @safe
    in
    {
        assert(connection !is null);
    }
    do
    {
        this._database = database;
        this._connection = connection;
        this._name = name;
        this._commandTimeout = connection.connectionStringBuilder.commandTimeout;
        this._fetchRecordCount = connection.connectionStringBuilder.fetchRecordCount;
        this._flags.parametersCheck = true;
        this._flags.returnRecordsAffected = true;
        this.logTimmingWarningDur = dur!"seconds"(60);
        this.notifyMessage.opAssign(connection.notifyMessage);
    }

    this(DbDatabase database, DbConnection connection, DbTransaction transaction,
        string name = null) nothrow @safe
    in
    {
        assert(connection !is null);
    }
    do
    {
        this(database, connection, name);
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

    final typeof(this) clearColumns() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_columns !is null)
            _columns.clear();

        return this;
    }

    deprecated("please use clearColumns")
    alias clearFields = clearColumns;

    final typeof(this) clearParameters() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_parameters !is null)
            _parameters.clear();

        return this;
    }

    final DbRecordsAffected executeNonQuery() @safe
    {
        debug(debug_pham_db_db_database) auto dgMarker = DgMarker(__FUNCTION__ ~ "(" ~ commandText ~ ")");

        if (auto log = canTraceLog())
            log.infof("%s.command.executeNonQuery()%s%s", forLogInfo(), newline, commandText);

        checkCommand(-1);
        resetStatement(ResetStatementKind.executing);

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
        return executeReaderImpl(false);
    }

    final DbValue executeScalar() @safe
    {
        debug(debug_pham_db_db_database) auto dgMarker = DgMarker(__FUNCTION__ ~ "(" ~ commandText ~ ")");

        if (auto log = canTraceLog())
            log.infof("%s.command.executeScalar()%s%s", forLogInfo(), newline, commandText);

        checkCommand(DbCommandType.ddl);
        resetStatement(ResetStatementKind.executing);

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
     *  isScalar = When true, all columns must resolved to actual data (not its underline id)
     * Returns:
     *  A row being requested. Incase of no result left to be returned,
     *  a DbRowValue with zero column-length being returned.
     */
    final DbRowValue fetch(bool isScalar) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ", _fetchedRowCount=", _fetchedRowCount,
            ", columnCount=", columnCount, ", isStoredProcedure=", isStoredProcedure, ", isSelectCommandType=", isSelectCommandType(), ")");
        version(profile) debug auto p = PerfFunction.create();

        if (auto log = canTraceLog())
            log.infof("%s.command.fetch()%s%s", forLogInfo(), newline, commandText);

        checkActive();

		if (hasStoredProcedureFetched())
            return _fetchedRows ? _fetchedRows.dequeue() : DbRowValue(0, 0);

        if (_fetchedRows.empty && !allRowsFetched && isSelectCommandType())
        {
            resetStatement(ResetStatementKind.fetching);
            scope (exit)
                resetStatement(ResetStatementKind.fetched);

            doFetch(isScalar);
        }

        return _fetchedRows ? _fetchedRows.dequeue() : DbRowValue(0, 0);
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

    final T[] inputParameters(T : DbParameter)(InputDirectionOnly inputOnly = InputDirectionOnly.no) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        return parameterCount ? parameters.inputs!T(inputOnly) : null;
    }

    final T[] outParameters(T : DbParameter)(OutputDirectionOnly outputOnly = OutputDirectionOnly.no) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        return parameterCount ? parameters.outputs!T(outputOnly) : null;
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
        resetStatement(ResetStatementKind.preparing);

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
            resetStatement(ResetStatementKind.prepared);
        }
        catch (Exception e)
        {
            debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
            if (auto log = canErrorLog())
                log.errorf("%s.command.prepare() - %s%s%s", forLogInfo(), e.msg, newline, _executeCommandText, e);
            throw e;
        }

        if (stateChange)
            stateChange(this, commandState);

        return this;
    }

    abstract Variant readArray(DbNamedColumn arrayColumn, DbValue arrayValueId) @safe;

    abstract int64 readBlob(DbNamedColumn blobColumn, DbValue blobValueId, size_t row) @safe;

    final int64 readBlob(DbNamedColumn blobColumn, DbValue blobValueId, size_t row, out ubyte[] blob) @safe
    {
        auto saveLongDataOrg = blobColumn.saveLongData;
        scope (exit)
            blobColumn.saveLongData = saveLongDataOrg;

        Appender!(ubyte[]) buffer;
        int saveLongData(Object, int64, int64 blobLength, size_t, scope const(ubyte)[] data) nothrow @safe
        {
            if (blobLength > 0 && buffer.length == 0)
                buffer.reserve(cast(size_t)blobLength);
            buffer.put(data);
            return 0;
        }

        blobColumn.saveLongData = &saveLongData;
        const result = readBlob(blobColumn, blobValueId, row);
        blob = buffer.data;
        return result;
    }

    final int64 readClob(DbNamedColumn clobColumn, DbValue clobValueId, size_t row, out string clob) @trusted //@trusted=cast(string)
    {
        ubyte[] blob;
        const result = readBlob(clobColumn, clobValueId, row, blob);
        clob = cast(string)blob;
        return result;
    }

    final typeof(this) unprepare() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (auto log = canTraceLog())
            log.infof("%s.command.unprepare()%s%s", forLogInfo(), newline, commandText);

        if (_connection !is null && _connection.isFatalError)
        {
            resetStatement(ResetStatementKind.unprepared);
            return this;
        }

        checkActiveReader();

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
            resetStatement(ResetStatementKind.unprepared);
        doUnprepare(false);

        if (stateChange)
            stateChange(this, commandState);

        return this;
    }

    abstract DbValue writeBlob(DbParameter parameter,
        DbValue optionalBlobValueId = DbValue.init) @safe;

    final DbValue writeBlob(DbParameter parameter, scope const(ubyte)[] blobValue,
        DbValue optionalBlobValueId = DbValue.init) @safe
    {
        auto loadLongDataOrg = parameter.loadLongData;
        scope (exit)
            parameter.loadLongData = loadLongDataOrg;

        size_t loadLongData(Object, int64 loadedLength, size_t, ref scope const(ubyte)[] data) nothrow @safe
        {
            if (loadedLength == 0)
            {
                data = blobValue;
                return blobValue.length;
            }
            else
                return 0;
        }

        parameter.loadLongData = &loadLongData;
        return writeBlob(parameter, optionalBlobValueId);
    }

    final DbValue writeClob(DbParameter parameter, scope const(char)[] clobValue,
        DbValue optionalClobValueId = DbValue.init) @safe
    {
        import std.string : representation;

        return writeBlob(parameter, clobValue.representation, optionalClobValueId);
    }

    @property final bool activeReader() const nothrow @safe
    {
        return _flags.activeReader;
    }

    @property final bool allRowsFetched() const nothrow @safe
    {
        return _flags.allRowsFetched;
    }

    @property final int baseCommandType() const nothrow @safe
    {
        return _baseCommandType;
    }

    @property final bool batched() const nothrow @safe
    {
        return _flags.batched;
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
        return _database;
    }

    @property final size_t executedCount() const nothrow @safe
    {
        return _executedCount;
    }

    /**
     * Returns number of records being fetched at once.
     * Default value is set by connection instance
     */
    @property final int32 fetchRecordCount() const nothrow @safe
    {
        return _fetchRecordCount;
    }

    /**
     * Returns number of defining columns of this DbCommand
     */
    @property final size_t columnCount() const nothrow @safe
    {
        return _columns !is null ? _columns.length : 0;
    }

    deprecated("please use columnCount")
    alias fieldCount = columnCount;

    /**
     * Gets DbColumnList of this DbCommand
     */
    @property final DbColumnList columns() nothrow @safe
    {
        if (_columns is null)
            _columns = database.createColumnList(this);

        return _columns;
    }

    deprecated("please use columns")
    alias fields = columns;

    pragma(inline, true)
    @property final bool getExecutionPlanning() const nothrow @safe
    {
        return _flags.getExecutionPlanning;
    }

    @property final DbHandle handle() const nothrow @safe
    {
        return _handle;
    }

    @property final bool hasInputParameters(InputDirectionOnly inputOnly = InputDirectionOnly.no) nothrow @safe
    {
        return _parameters !is null ? _parameters.hasInput(inputOnly) : false;
    }

    @property final bool hasOutputParameters(OutputDirectionOnly outputOnly = OutputDirectionOnly.no) nothrow @safe
    {
        return _parameters !is null ? _parameters.hasOutput(outputOnly) : false;
    }

    @property final bool hasParameters(scope const(EnumSet!DbParameterDirection) directions) const nothrow @safe
    {
        return _parameters !is null ? _parameters.parameterHasOfs(directions) : false;
    }

    @property final bool isActive() const nothrow @safe
    {
        return _handle && _connection !is null && _connection.isActive;
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
     * Returns number of defining parameters of this DbCommand
     */
    @property final size_t parameterCount() const nothrow @safe
    {
        return _parameters !is null ? _parameters.length : 0;
    }

    /**
     * Gets DbParameterList of this DbCommand
     */
    @property final DbParameterList parameters() nothrow @safe
    {
        if (_parameters is null)
            _parameters = database.createParameterList(this);

        return _parameters;
    }

    /**
     * Returns true if DbParameterList is needed to parse commandText for parameters.
     * Default value is true
     */
    pragma(inline, true)
    @property final bool parametersCheck() const nothrow @safe
    {
        return _flags.parametersCheck;
    }

    @property final typeof(this) parametersCheck(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.parametersCheck, value);
        return this;
    }

    /**
     * Returns true if DbParameterList is in prepared state
     */
    pragma(inline, true)
    @property final bool prepared() const nothrow @safe
    {
        return _flags.prepared;
    }

    /**
     * Gets number of records affected after executed a commandText if applicable
     */
    @property final DbRecordsAffected recordsAffected() const nothrow @safe
    {
        return _recordsAffected;
    }

    pragma(inline, true)
    @property final bool returnRecordsAffected() const nothrow @safe
    {
        return _flags.returnRecordsAffected;
    }

    @property final typeof(this) returnRecordsAffected(bool value) nothrow @safe
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
        _flags.implicitTransaction = false;
        return this;
    }

    pragma(inline, true)
    @property final bool transactionRequired() const nothrow @safe
    {
        return _flags.transactionRequired;
    }

public:
    /**
     * Delegate to get notify when a state change
     * Params:
     *  command = this command instance
     *  newState = new state value
     */
    DelegateList!(DbCommand, DbCommandState) stateChange;

    /**
     * Delegate to get notify when there are notification messages from server
     * Params:
     *  sender = this command instance
     *  messages = array of DbNotificationMessages
     */
    nothrow @safe DelegateList!(Object, DbNotificationMessage[]) notifyMessage;
    DbNotificationMessage[] notificationMessages;

    DbCustomAttributeList customAttributes;
    Duration logTimmingWarningDur;

package(pham.db):
    enum LoadRowValueFor : ubyte
    {
        parameter,
        scalar,
        row,
    }

    void checkActive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (!_handle)
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

        if (_flags.activeReader)
            throw new DbException(0, DbMessage.eInvalidCommandActiveReader, null, funcName, file, line);

        if (_connection is null)
        {
            auto msg = DbMessage.eInvalidCommandConnection.fmtMessage(funcName);
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }

        _connection.checkActiveReader(funcName, file, line);
    }

    final void checkInactive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (_handle)
        {
            auto msg = DbMessage.eInvalidCommandActive.fmtMessage(funcName);
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }
    }

    final DbReader executeReaderImpl(const(bool) ownCommand) @safe
    {
        debug(debug_pham_db_db_database) auto dgMarker = DgMarker(__FUNCTION__ ~ "(" ~ commandText ~ ")");

        if (auto log = canTraceLog())
            log.infof("%s.command.executeReader()%s%s", forLogInfo(), newline, commandText);

        checkCommand(DbCommandType.ddl);
        resetStatement(ResetStatementKind.executing);

        auto executePrep = ExecutePrep(this, DbCommandExecuteType.reader);
        executePrep.resetTransaction = setImplicitTransactionIf(DbCommandExecuteType.reader);
        executePrep.resetPrepare = setImplicitPrepareIf(DbCommandExecuteType.reader);
        scope (exit)
            doNotifyMessage();
        scope (failure)
            executePrep.reset(true);

        doExecuteCommand(DbCommandExecuteType.reader);
        connection._readerCounter++;
        _flags.activeReader = true;
        return DbReader(this, executePrep.resetTransaction, ownCommand);
    }

    final bool hasStoredProcedureFetched() nothrow @safe
    {
        return isStoredProcedure || (columnCount != 0 && !isSelectCommandType());
    }

    @property final void allRowsFetched(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.allRowsFetched, value);
    }

    @property final void batched(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.batched, value);
    }

    @property final void getExecutionPlanning(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.getExecutionPlanning, value);
    }

    pragma(inline, true)
    @property final bool isStoredProcedure() const nothrow @safe
    {
        return commandType == DbCommandType.storedProcedure;
    }

    @property final void transactionRequired(bool value) nothrow @safe
    {
        _flags.set(DbCommandFlag.transactionRequired, value);
    }

protected:
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

        this(DbCommand command, DbCommandExecuteType executeType) nothrow @safe
        {
            this.executeType = executeType;
            this.command = command;
            this.wasPrepared = command.prepared;
        }

        void reset(const(bool) isError) @safe
        {
            scope (exit)
            {
                command = null;
                resetPrepare = resetTransaction = false;
            }

            if (resetTransaction)
            {
                auto flags = isError ? ResetImplicitTransactiontFlag.error : ResetImplicitTransactiontFlag.none;
                if (executeType == DbCommandExecuteType.nonQuery)
                    flags |= ResetImplicitTransactiontFlag.nonQuery;
                if (isError || executeType != DbCommandExecuteType.reader)
                    command.resetImplicitTransactionIf(flags);
            }

            const isPreparedError = isError && executeType == DbCommandExecuteType.prepare;
            if (resetPrepare || isPreparedError)
            {
                if (wasPrepared)
                    command.unprepare();
                else
                {
                    scope (exit)
                        command.resetStatement(ResetStatementKind.unprepared);
                    command.doUnprepare(isPreparedError);
                }
            }
        }

    public:
        DbCommand command;
        const DbCommandExecuteType executeType;
        bool resetPrepare;
        bool resetTransaction;
        const bool wasPrepared;
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

        // Construct sql
        result.put(database.parameterPlaceholder(parameterName, ordinal));

        // Create parameter
        auto params = parameters; // Use local var to avoid function call
        if (params.length == 0)
            params.reserve(20);
        DbParameter found;
        if (parameterName.length == 0)
            found = params.add(DbParameter.generateName(ordinal), DbType.unknown);
        else if (!params.find(parameterName, found))
            found = params.add(parameterName, DbType.unknown);
        found.ordinal = ordinal;
    }

    string buildStoredProcedureSql(string storedProcedureName, const(BuildCommandTextState) state) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ", state=", state, ")");

        if (storedProcedureName.length == 0)
            return null;

        auto params = inputParameters!DbParameter();
        auto result = Appender!string(500);
        result.put("EXECUTE PROCEDURE ");
        result.put(storedProcedureName);
        result.put('(');
        foreach (i, param; params)
        {
            if (i)
                result.put(',');
			result.put(database.parameterPlaceholder(param.name, cast(uint32)(i + 1)));
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

    void checkCommand(int excludeCommandType,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (_connection is null || _connection.state != DbConnectionState.opened)
        {
            auto msg = DbMessage.eInvalidCommandConnection.fmtMessage(funcName);
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }

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
            debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
            if (auto log = canErrorLog())
                log.errorf("%s.command.doDispose() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
        }

        if (_transaction !is null)
        {
            _transaction = null;
        }

        if (_columns !is null)
        {
            version(none) _columns.dispose(disposingReason);
            _columns = null;
        }

        if (_parameters !is null)
        {
            version(none) _parameters.dispose(disposingReason);
            _parameters = null;
        }

        if (_connection !is null)
        {
            _connection.removeCommand(this);
            if (isDisposing(disposingReason))
                _connection = null;
        }

        _commandState = DbCommandState.closed;
        _commandText = _executeCommandText = null;
        _baseCommandType = 0;
        _handle.reset();
        _flags.activeReader = false;
        _flags.prepared = false;
        _lastInsertedId.reset();
        _recordsAffected.reset();
        _fetchedRows.clear();
        _executedCount = _fetchedCount = _fetchedRowCount = 0;
        notificationMessages = null;
    }

    bool doExecuteCommandNeedPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        return parametersCheck && parameterCount;
    }

    final void doNotifyMessage() nothrow @trusted
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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
                debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
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

    final DbParameter getOutputParam(const(size_t) forOrdinal) nothrow @safe
    {
        assert(parameters.length);

        size_t parOrdinal;
        auto params = parameters; // Use local var to avoid function call
        foreach (param; params)
        {
            if (param.isOutput(OutputDirectionOnly.no))
            {
                parOrdinal++;
                if (parOrdinal == forOrdinal)
                    return param;
            }
        }
        return null;
    }

    bool isSelectCommandType() const nothrow @safe
    {
        return columnCount != 0 && !isStoredProcedure;
    }

    final void mergeOutputParams(ref DbRowValue values) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(values.length=", values.length, ", parameters.length=", parameters.length, ")");
        assert(values.length);
        assert(parameters.length);

        size_t valIndex;
        auto params = parameters; // Use local var to avoid function call
        foreach (param; params)
        {
            if (param.isOutput(OutputDirectionOnly.no))
            {
                param.value = values[valIndex++];
                if (valIndex >= values.length)
                    break;
            }
        }
    }

    final void removeReader(ref DbReader value) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (_flags.activeReader && value.command is this)
        {
            _flags.activeReader = false;
            connection._readerCounter--;
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
                debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
                if (auto log = canErrorLog())
                    log.errorf("%s.command.removeReaderCompleted() - %s%s%s", forLogInfo(), e.msg, newline, commandText, e);
            }
        }
    }

    final void resetImplicitTransactionIf(const(ResetImplicitTransactiontFlag) flags)  @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(flags=", flags, ")");

        auto t = this._transaction;

        const implicitTransaction = this._flags.implicitTransaction;
        if (implicitTransaction)
        {
            this._flags.implicitTransaction = false;
            this._transaction = null;
        }

        bool commitOrRollback = false;
        if (this._flags.implicitTransactionStarted)
        {
            this._flags.implicitTransactionStarted = false;
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

    void resetStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

        final switch (kind)
        {
            case ResetStatementKind.unprepared:
                notificationMessages.length = 0;
                _fetchedRows.clear();
                _executedCount = _fetchedCount = _fetchedRowCount = 0;
                //_lastInsertedId.reset(); // The value is needed to return to caller, so do not reset here
                //_recordsAffected.reset(); // The value is needed to return to caller, so do not reset here
                _handle.reset();
                _executeCommandText = null;
                _baseCommandType = 0;
                _flags.activeReader = false;
                _flags.batched = false;
                _flags.cancelled = false;
                _flags.prepared = false;
                _commandState = DbCommandState.unprepared;
                break;

            case ResetStatementKind.preparing:
                notificationMessages.length = 0;
                _fetchedRows.clear();
                //_executedCount = 0;
                _fetchedCount = _fetchedRowCount = 0;
                _lastInsertedId.reset();
                _recordsAffected.reset();
                _flags.cancelled = false;
                break;

            case ResetStatementKind.prepared:
                _flags.prepared = true;
                _commandState = DbCommandState.prepared;
                break;

            case ResetStatementKind.executing:
                allRowsFetched(false);
                _fetchedRows.clear();
                _lastInsertedId.reset();
                _recordsAffected.reset();
                break;

            case ResetStatementKind.executed:
                _executedCount++;
                _commandState = DbCommandState.executed;
                break;

            case ResetStatementKind.fetched:
                _fetchedCount++;
                break;

            case ResetStatementKind.fetching:
                break;
        }

        if (_columns !is null && _columns.length)
            _columns.resetStatement(kind);

        if (_parameters !is null && _parameters.length)
            _parameters.resetStatement(kind);
    }

    typeof(this) setCommandText(string commandText, DbCommandType type) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(type=", type, ", commandText=", commandText, ")");

        if (prepared)
            unprepare();

        clearColumns();
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
            _flags.implicitTransaction = true;

            if (_transaction.state == DbTransactionState.inactive)
            {
                _transaction.start();
                _flags.implicitTransactionStarted = true;
            }

            return true;
        }
        else
            return false;
    }

    void setOutputParameters(ref DbRowValue values)
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        if (values && parameterCount)
        {
            size_t i;
            foreach (parameter; parameters)
            {
                if (i < values.length && parameter.isOutput(OutputDirectionOnly.no))
                    parameter.value = values[i++];
            }
        }
    }

    abstract void doExecuteCommand(const(DbCommandExecuteType) type) @safe;
    abstract void doFetch(const(bool) isScalar) @safe;
    abstract void doPrepare() @safe;
    abstract void doUnprepare(const(bool) isPreparedError) @safe;

protected:
    DbColumnList _columns;
    DbConnection _connection;
    DbDatabase _database;
    DbParameterList _parameters;
    DbTransaction _transaction;
    string _commandText, _executeCommandText;
    string _name;
    DbRecordsAffected _lastInsertedId;
    DbRecordsAffected _recordsAffected;
    DbHandle _handle;
 	DbRowValueQueue _fetchedRows;
    Duration _commandTimeout;
    size_t _executedCount; // Number of execute calls after prepare
    size_t _fetchedCount; // Number of fetch calls
    size_t _fetchedRowCount; // Number of reocrds being fetched so far
    int32 _fetchRecordCount;
    int32 _baseCommandType;
    EnumSet!DbCommandFlag _flags;
    DbCommandState _commandState;
    DbCommandType _commandType;

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
            command._flags.cancelled = true;
        scope (exit)
            doNotifyMessage();

        doCancelCommandImpl(data);
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

        const previousState = state;
        if (previousState == DbConnectionState.closed)
            return this;

        _state = DbConnectionState.closing;
        scope (exit)
            _state = DbConnectionState.closed;

        doBeginStateChange(DbConnectionState.closing);
        doClose(DbConnectionState.closing);
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

    final DbCommand createCommandDDL(string commandDDL,
        string name = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        auto result = createCommand(name);
        result.commandDDL = commandDDL;
        return result;
    }

    final DbCommand createCommandText(string commandText,
        string name = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        auto result = createCommand(name);
        result.commandText = commandText;
        return result;
    }

    /// Returns true if create, false otherwise
    final bool createTableOrEmpty(string tableName, string createCommandText,
        string schema = null) @safe
    {
        if (existTable(tableName, schema))
        {
            executeNonQuery("delete from " ~ combineSymbol(schema, tableName));
            return false;
        }

        auto command = createCommandDDL(createCommandText);
        scope (exit)
            command.dispose();

        command.executeNonQuery();
        return true;
    }

    final DbTransaction createTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();
        return createTransactionImpl(isolationLevel, false);
    }

    DbValue currentTimeStamp(const(uint) precision) @safe
    {
        auto commandText = "SELECT " ~ database.currentTimeStamp(precision);
        return executeScalar(commandText);
    }

    final DbTransaction defaultTransaction(DbIsolationLevel isolationLevel = DbIsolationLevel.readCommitted) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        checkActive();

        if (_defaultTransaction is null)
            _defaultTransaction = createTransactionImpl(isolationLevel, true);

        return _defaultTransaction;
    }

    final DbRecordsAffected executeNonQuery(string commandText,
        DbParameterList commandParameters = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

        auto command = createCommandText(commandText);
        scope (exit)
            command.dispose();

        const isParameters = commandParameters !is null && commandParameters.length != 0;
        command.parametersCheck = isParameters;
        if (isParameters)
            command.parameters.assign(commandParameters);

        return command.executeNonQuery();
    }

    final DbReader executeReader(string commandText,
        DbParameterList commandParameters = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

        auto command = createCommandText(commandText);
        const isParameters = commandParameters !is null && commandParameters.length != 0;
        command.parametersCheck = isParameters;
        if (isParameters)
            command.parameters.assign(commandParameters);

        return command.executeReaderImpl(true);
    }

    final DbValue executeScalar(string commandText,
        DbParameterList commandParameters = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

        auto command = createCommandText(commandText);
        scope (exit)
            command.dispose();

        const isParameters = commandParameters !is null && commandParameters.length != 0;
        command.parametersCheck = isParameters;
        if (isParameters)
            command.parameters.assign(commandParameters);

        return command.executeScalar();
    }

    final bool existFunction(string functionName,
        string schema = null) @safe
    {
        return existRoutine(functionName, DbRoutineType.storedFunction, schema);
    }

    /**
     * Params:
     *   routineName = a function or stored-procedure name
     *   type = FUNCTION or PROCEDURE
     */
    bool existRoutine(string routineName, string type,
        string schema = null) @safe
    {
        static immutable string SQL = "select 1" ~
            " from INFORMATION_SCHEMA.ROUTINES" ~
            " where ROUTINE_NAME = @routineName and ROUTINE_TYPE = @type";
        static immutable string SQLSchema = "select 1" ~
            " from INFORMATION_SCHEMA.ROUTINES" ~
            " where ROUTINE_NAME = @routineName and ROUTINE_TYPE = @type and ROUTINE_SCHEMA = @schema";

        checkActive();

        if (routineName.length == 0)
            return false;

        auto parameters = database.createParameterList(null);
        parameters.add("routineName", DbType.stringVary, Variant(routineName));
        parameters.add("type", DbType.stringVary, Variant(type));
        if (schema.length)
            parameters.add("schema", DbType.stringVary, Variant(schema));

        auto r = executeScalar(schema.length ? SQLSchema : SQL, parameters);
        return !r.isNull && r.value == 1;
    }

    final bool existStoredProcedure(string storedProcedureName,
        string schema = null) @safe
    {
        return existRoutine(storedProcedureName, DbRoutineType.storedProcedure, schema);
    }

    bool existTable(string tableName,
        string schema = null) @safe
    {
        static immutable string SQL = "select 1" ~
            " from INFORMATION_SCHEMA.TABLES" ~
            " where TABLE_NAME = @tableName";
        static immutable string SQLSchema = "select 1" ~
            " from INFORMATION_SCHEMA.TABLES" ~
            " where TABLE_NAME = @tableName and TABLE_SCHEMA = @schema";

        checkActive();

        if (tableName.length == 0)
            return false;

        auto parameters = database.createParameterList(null);
        parameters.add("tableName", DbType.stringVary, Variant(tableName));
        if (schema.length)
            parameters.add("schema", DbType.stringVary, Variant(schema));

        auto r = executeScalar(schema.length ? SQLSchema : SQL, parameters);
        return !r.isNull && r.value == 1;
    }

    bool existView(string viewName,
        string schema = null) @safe
    {
        static immutable string SQL = "select 1" ~
            " from INFORMATION_SCHEMA.VIEWS" ~
            " where TABLE_NAME = @viewName";
        static immutable string SQLSchema = "select 1" ~
            " from INFORMATION_SCHEMA.VIEWS" ~
            " where TABLE_NAME = @viewName and TABLE_SCHEMA = @schema";

        checkActive();

        auto parameters = database.createParameterList(null);
        parameters.add("viewName", DbType.stringVary, Variant(viewName));
        if (schema.length)
            parameters.add("schema", DbType.stringVary, Variant(schema));

        auto r = executeScalar(schema.length ? SQLSchema : SQL, parameters);
        return !r.isNull && r.value == 1;
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

    final DbRoutineInfo getStoredProcedureInfo(string storedProcedureName,
        string schema = null) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ")");

        if (storedProcedureName.length == 0)
            return null;

        DbRoutineInfo result;

        const cacheKey = DbDatabase.generateCacheKeyStoredProcedure(storedProcedureName, this.forCacheKey, schema);
        if (database.cache.find!DbRoutineInfo(cacheKey, result))
            return result;

        result = doGetStoredProcedureInfo(storedProcedureName, schema);
        if (result !is null)
            database.cache.addOrReplace(cacheKey, result);

        return result;
    }

    final string limitClause(int32 rows, uint32 offset = 0) const nothrow pure @safe
    in
    {
        assert(_database !is null);
    }
    do
    {
        return _database.limitClause(rows, offset);
    }

    final typeof(this) open() @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(state=", state, ")");

        if (auto log = canTraceLog())
            log.infof("%s.connection.open()", forLogInfo());

        if (_poolList !is null)
            return _poolList.release(this);

        const previousState = state;
        if (previousState == DbConnectionState.opened)
            return this;

        reset();

        _state = DbConnectionState.opening;
        scope (exit)
        {
            if (_state == DbConnectionState.opening)
                _state = DbConnectionState.opened;
            doNotifyMessage();
        }

        scope (failure)
            fatalError(DbFatalErrorReason.open, previousState);

        doBeginStateChange(DbConnectionState.opening);
        doOpenImpl();
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

    final void removeCachedStoredProcedure(string storedProcedureName,
        string schema = null) nothrow @safe
    {
        const cacheKey = DbDatabase.generateCacheKeyStoredProcedure(storedProcedureName, this.forCacheKey, schema);
        database.cache.remove(cacheKey);
    }

    final string serverVersion() @safe
    {
        string result;
        if (serverInfo.containKey(DbServerIdentifier.dbVersion, result))
            return result;

        result = getServerVersionImpl();
        return serverInfo.require(DbServerIdentifier.dbVersion, result);
    }

    final override size_t toHash() nothrow @safe
    {
        return connectionStringBuilder.toHash().hashOf(hashOf(scheme));
    }

    final string topClause(int rows) const nothrow pure @safe
    in
    {
        assert(_database !is null);
    }
    do
    {
        return _database.topClause(rows);
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
        return _connectionStringBuilder.connectionString;
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
    @property final bool hasCommands() const nothrow @safe
    {
        return !_commands.empty;
    }

    /**
     * Returns true if this connection has any DbTransaction
     */
    @property final bool hasTransactions() const nothrow @safe
    {
        return !_transactions.empty;
    }

    @property final bool isActive() const nothrow @safe
    {
        return _state == DbConnectionState.opened;
    }

    /**
     * Returns true if there is a mismatched reading/writing data with database server and
     * must perform disconnect and connect again
     */
    @property final bool isFatalError() const nothrow @safe
    {
        return _fatalError != DbFatalErrorReason.none;
    }

    @property final DbTransaction lastTransaction(bool excludeDefaultTransaction) nothrow @safe
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
    @property final DbConnectionState state() const nothrow @safe
    {
        return _state;
    }

    @property abstract DbScheme scheme() const nothrow pure @safe;

    @property abstract bool supportMultiReaders() const nothrow @safe;

package(pham.db):
    final void checkActive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (!isActive)
        {
            auto msg = isFatalError
                ? DbMessage.eInvalidConnectionFatal.fmtMessage(funcName, _connectionStringBuilder.forErrorInfo())
                : DbMessage.eInvalidConnectionInactive.fmtMessage(funcName, _connectionStringBuilder.forErrorInfo());
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }
    }

    final void checkActiveReader(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) const @safe
    {
        if (_readerCounter != 0 && !supportMultiReaders)
            throw new DbException(0, DbMessage.eInvalidConnectionActiveReader, null, funcName, file, line);
    }

    final void checkInactive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(funcName=", funcName, ")");

        if (isActive)
        {
            auto msg = DbMessage.eInvalidConnectionActive.fmtMessage(funcName, _connectionStringBuilder.forErrorInfo());
            throw new DbException(DbErrorCode.connect, msg, null, funcName, file, line);
        }
    }

    final DbCommand createNonTransactionCommand(const(bool) getExecutionPlanning = false,
        const(bool) parametersCheck = false,
        const(bool) returnRecordsAffected = false) @safe
    {
        auto result = createCommand();
        result.getExecutionPlanning = getExecutionPlanning;
        result.parametersCheck = parametersCheck && !getExecutionPlanning;
        result.returnRecordsAffected = returnRecordsAffected && !getExecutionPlanning;
        result.transactionRequired = false;
        return result;
    }

    final void doClose(const(DbConnectionState) reasonState) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(reasonState=", reasonState, ")");

        const isFailing = isFatalError || reasonState == DbConnectionState.failing;

        try
        {
            if (!isFailing)
                rollbackTransactions();

            disposeTransactions(DisposingReason.other);
            disposeCommands(DisposingReason.other);

            doCloseImpl(reasonState);
        }
        catch (Exception e)
        {
            debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
            if (auto log = canErrorLog())
                log.errorf("%s.connection.doClose() - %s", forLogInfo(), e.msg, e);
        }

        _handle.reset();
    }

    void fatalError(const(DbFatalErrorReason) fatalError, const(DbConnectionState) previousState,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    in
    {
        assert(fatalError != DbFatalErrorReason.none);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(fatalError=", fatalError, ", previousState=", previousState, ", funcName=", funcName, ")");

        this._fatalError = fatalError;
        _state = DbConnectionState.failing;
        scope (exit)
            _state = DbConnectionState.failed;

        if (fatalError != DbFatalErrorReason.open)
            doBeginStateChange(DbConnectionState.failing);
        doCloseImpl(DbConnectionState.failing); //todo
        doEndStateChange(previousState);
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

public:
    /**
     * Delegate to get notify when a state change
     * Occurs when the before state of the event changes
     * Params:
     *  connectin = this connection instance
     *  newState = new state value
     */
    DelegateList!(DbConnection, DbConnectionState) beginStateChange;

    /**
     * Delegate to get notify when a state change
     * Occurs when the after state of the event changes
     * Params:
     *  connectin = this connection instance
     *  oldState = old state value
     */
    DelegateList!(DbConnection, DbConnectionState) endStateChange;

    /**
     * Delegate to get notify when there are notification messages from server
     * Params:
     *  sender = this connection instance
     *  messages = array of DbNotificationMessages
     */
    nothrow @safe DelegateList!(Object, DbNotificationMessage[]) notifyMessage;
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

    abstract DbRoutineInfo doGetStoredProcedureInfo(string storedProcedureName, string schema) @safe;

    final void doNotifyMessage() nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

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
                debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
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

        _fatalError = DbFatalErrorReason.none;
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

    abstract void doCancelCommandImpl(DbCancelCommandData data) @safe;
    abstract void doCloseImpl(const(DbConnectionState) reasonState) nothrow @safe;
    abstract void doOpenImpl() @safe;
    abstract string getServerVersionImpl() @safe;

protected:
    DbConnectionStringBuilder _connectionStringBuilder;
    DbDatabase _database;
    DbConnectionList _poolList;
    DbTransaction _defaultTransaction;
    DateTime _inactiveTime;
    DbHandle _handle;
    size_t _nextCounter;
    int _readerCounter, _activeTransactionCounter;
    DbConnectionState _state;
    DbConnectionType _type;
    DbFatalErrorReason _fatalError;

private:
    DLinkDbCommandTypes.DLinkList _commands;
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

    @property final string connectionString() const nothrow @safe
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
        size_t maxLength = DbDefault.connectionPoolLength,
        Duration maxInactiveTime = dur!"seconds"(DbDefault.connectionPoolInactiveTime)) nothrow
    {
        this._secondTimer = secondTimer;
        this._mutex = new Mutex();
        this._maxLength = maxLength;
        this._maxInactiveTime = maxInactiveTime;
    }

    final DbConnection acquire(DbScheme scheme, string connectionString)
    {
        auto raiiMutex = RAIIMutex(_mutex);

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

    @property final size_t maxLength() const nothrow
    {
        return atomicLoad(_maxLength);
    }

    @property final typeof(this) maxLength(size_t value) nothrow
    {
        atomicStore(_maxLength, value);
        return this;
    }

    @property final size_t unusedLength() const nothrow
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
        auto raiiMutex = RAIIMutex(_mutex);

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
        auto buffer = Appender!string(prefix.length + size_t.sizeof * 2);
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
        this.initValidParamNameChecks();
        this.setDefaultCustomAttributes();
        this.setDefaultIfs();
    }

    this(DbDatabase database, string connectionString)
    {
        this._database = database;
        this.initValidParamNameChecks();
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

        foreach (e; source)
        {
            this.put(e.name, e.value);
        }

        return this;
    }

    final string forCacheKey() const nothrow
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

    final string getValue(string name) const nothrow
    {
        return name.length != 0 && exist(name) ? getString(name) : null;
    }

    final bool hasCustomAttribute(string name, out string value) const nothrow
    {
        return customAttributes.hasValue(name, value);
    }

    final bool hasValue(string name, out string value) const nothrow
    {
        value = name.length != 0 && exist(name) ? getString(name) : null;
        return value.length != 0;
    }

    /**
     * Returns list of valid parameter names for connection string
     */
    abstract const(string[]) parameterNames() const nothrow;

    final typeof(this) parseConnectionString(string connectionString)
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

    final typeof(this) setConnectionString(DbURL!string connectionString)
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
                    addLine(errorMessage, DbMessage.eInvalidConnectionStringName.fmtMessage(scheme, o.name));
                    break;
                case duplicateName:
                    addLine(errorMessage, DbMessage.eInvalidConnectionStringNameDup.fmtMessage(scheme, o.name));
                    break;
                case invalidValue:
                    addLine(errorMessage, DbMessage.eInvalidConnectionStringValue.fmtMessage(scheme, o.name, o.value));
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
    final bool setValue(string name, string value) nothrow
    {
        if (name.length == 0)
            return false;

        put(name, value);
        const e = name in _validParamNameChecks;
        return e !is null;
    }

    final override size_t toHash() const nothrow @safe
    {
        return this.toString().hashOf();
    }

    final override string toString() const nothrow @trusted
    {
        assert(elementSeparators.length != 0);

        return getDelimiterText(cast()this, elementSeparators[0], valueSeparator);
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
    @property final string connectionString() const nothrow
    {
        assert(elementSeparators.length != 0);

        const es = elementSeparators[0];
        const vs = valueSeparator;
        const names = parameterNames();

        auto result = Appender!string(names.length * 50);
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
            debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(value=", value, ", min=", (*k).min, ", max=", (*k).max, ")");

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

public:
    DbCustomAttributeList customAttributes;
    string forErrorInfoCustom;
    string forLogInfoCustom;

protected:
    enum customAttributeInfo = DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, 200);

    string getDefault(string name) const nothrow
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(name=", name, ")");
        debug(debug_pham_db_db_database) scope(exit) debug writeln("\t", "end");

        auto k = name in dbDefaultConnectionParameterValues;
        if (k is null)
            return null;

        auto sch = (*k).scheme;
        return sch.length == 0 || sch == scheme ? (*k).def : null;
    }

    final string getString(string name) const nothrow
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(name=", name, ")");
        debug(debug_pham_db_db_database) scope(exit) debug writeln("\t", "end");

        const i = indexOf(name);
        if (i >= 0)
            return getAt(i);

        return getDefault(name);
    }

    final void initValidParamNameChecks() nothrow
    {
        if (_database !is null)
            _validParamNameChecks = _database._validParamNameChecks.dup;

        const names = parameterNames();
        _validParamNameChecks.reserve(names.length + 5, names.length);
        foreach (n; names)
            _validParamNameChecks[n] = true;
    }

    override DbNameValueValidated isValidImpl(scope const(DbIdentitier) name, string value) const nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(name=", name, ")");

        const rs = super.isValidImpl(name, value);
        if (rs != DbNameValueValidated.ok)
            return rs;

        const n = name in _validParamNameChecks;
        if (n is null)
            return DbNameValueValidated.invalidName;

        const v = name in dbDefaultConnectionParameterValues;
        if (v is null)
            return DbNameValueValidated.invalidName;

        if ((*v).isValidValue(value) != DbNameValueValidated.ok)
            return DbNameValueValidated.invalidValue;

        return DbNameValueValidated.ok;
    }

    override void notify(ref DbIdentitierValuePair item, const(NotificationKind) kind) nothrow @safe
    {
        //super.notify(, kind);
        if (kind == NotificationKind.cleared)
        {
            this.forErrorInfoCustom = null;
            this.forLogInfoCustom = null;
        }
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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(begin)");
        debug(debug_pham_db_db_database) scope(exit) debug writeln(__FUNCTION__, "(end)");

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
        auto msg = DbMessage.eInvalidConnectionStringValue.fmtMessage(scheme, name, value);
        throw new DbException(DbErrorCode.parse, msg, null, funcName, file, line);
    }

protected:
    DbDatabase _database;
    Dictionary!(string, bool) _validParamNameChecks;
    string _elementSeparators = ";";
    char _valueSeparator = '=';
}

abstract class DbDatabase : DbNamedObject
{
@safe:

public:
    dchar replacementChar = dchar.max;

    enum CharClass : ubyte
    {
        any,
        idenfifierQuote,
        stringQuote,
        backslashSequence,
    }

public:
    this() nothrow @trusted
    {
        _cache = new DbCache!string(._secondTimer);
        _identifierQuoteChar = '"';
        _stringQuoteChar = '\'';
        _stringConcatOp = "||";
    }

    final string concate(scope const(char)[][] terms) const nothrow pure
    in
    {
        assert(terms.length >= 2);
    }
    do
    {
        size_t resultLength = _stringConcatOp.length
            ? terms[0].length
            : ("concat()".length + terms[0].length);
        const sepLength = _stringConcatOp.length ? (_stringConcatOp.length + 2) : 2;
        foreach (s; terms[1..$])
            resultLength += sepLength + s.length;
        auto result = Appender!string(resultLength);
        return concate(result, terms).data;
    }

    final ref Writer concate(Writer)(return ref Writer writer, scope const(char)[][] terms) const nothrow pure
    in
    {
        assert(terms.length >= 2);
    }
    do
    {
        if (_stringConcatOp.length == 0)
            writer.put("concat(");
        writer.put(terms[0]);
        const sep = _stringConcatOp.length ? (" " ~ _stringConcatOp ~ " ") : ", ";
        foreach (s; terms[1..$])
        {
            writer.put(sep);
            writer.put(s);
        }
        if (_stringConcatOp.length == 0)
            writer.put(")");
        return writer;
    }

    abstract const(string[]) connectionStringParameterNames() const nothrow pure;
    abstract DbColumn createColumn(DbCommand command, DbIdentitier name) nothrow;
    abstract DbColumnList createColumnList(DbCommand command) nothrow;
    abstract DbCommand createCommand(DbConnection connection,
        string name = null) nothrow;
    abstract DbCommand createCommand(DbConnection connection, DbTransaction transaction,
        string name = null) nothrow;
    abstract DbConnection createConnection(string connectionString);
    abstract DbConnection createConnection(DbConnectionStringBuilder connectionString) nothrow;
    abstract DbConnection createConnection(DbURL!string connectionString);
    abstract DbConnectionStringBuilder createConnectionStringBuilder() nothrow;
    abstract DbConnectionStringBuilder createConnectionStringBuilder(string connectionString);
    abstract DbParameter createParameter(DbCommand command, DbIdentitier name) nothrow;
    abstract DbParameterList createParameterList(DbCommand command) nothrow;
    abstract DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel,
        bool defaultTransaction = false) nothrow;

    deprecated("please use createColumn")
    alias createField = createColumn;

    deprecated("please use createColumnList")
    alias createFieldList = createColumnList;

    final DbColumn createColumn(DbCommand command, string name) nothrow
    {
        DbIdentitier id = DbIdentitier(name);
        return createColumn(command, id);
    }

    final DbParameter createParameter(DbCommand command, string name) nothrow
    {
        DbIdentitier id = DbIdentitier(name);
        return createParameter(command, id);
    }

    final CharClass charClass(const(dchar) c) const @nogc nothrow pure
    {
        if (auto e = c in _charClasses)
            return *e;
        else
            return CharClass.any;
    }

    string currentTimeStamp(const(uint) precision) const nothrow pure
    {
        static immutable string[7] currentTimeStamps = [
            "CURRENT_TIMESTAMP(0)",
            "CURRENT_TIMESTAMP(1)",
            "CURRENT_TIMESTAMP(2)",
            "CURRENT_TIMESTAMP(3)",
            "CURRENT_TIMESTAMP(4)",
            "CURRENT_TIMESTAMP(5)",
            "CURRENT_TIMESTAMP(6)",
            ];

        return precision < currentTimeStamps.length
            ? currentTimeStamps[precision]
            : currentTimeStamps[$-1];
    }

    final T[] escapeIdentifier(T)(return T[] value) const nothrow pure
    if (is(Unqual!T == char))
    {
        if (value.length == 0)
            return value;

        // Find the first quote char
        const p = escapeStartIndex(value, CharClass.idenfifierQuote);

        // No quote char found?
        if (p >= value.length)
            return value;

        auto result = Appender!(T[])(value.length + 10);
        escapeIdentifierImpl(result, value, p);
        return result.data;
    }

    private void escapeIdentifierImpl(Writer)(ref Writer writer, scope const(char)[] value, size_t startIndex) const nothrow pure
    {
        if (startIndex)
            writer.put(value[0..startIndex]);

        UTF8Iterator iterator;
        while (startIndex < value.length)
        {
            if (!nextUTF8Char(value, startIndex, iterator.code, iterator.count))
                iterator.code = replacementChar;

            final switch (charClass(iterator.code))
            {
                case CharClass.any:
                case CharClass.stringQuote:
                    writer.put(encodeUTF8(iterator.codeBuffer, iterator.code));
                    break;
                case CharClass.idenfifierQuote:
                    const encodedQuote = encodeUTF8(iterator.codeBuffer, iterator.code);
                    writer.put(encodedQuote);
                    writer.put(encodedQuote);
                    break;
                case CharClass.backslashSequence:
                    const encodedBackslash = encodeUTF8(iterator.codeBuffer, iterator.code);
                    writer.put(encodedBackslash);
                    startIndex += iterator.count;
                    if (startIndex < value.length)
                    {
                        if (!nextUTF8Char(value, startIndex, iterator.code, iterator.count))
                            iterator.code = replacementChar;
                        writer.put(encodeUTF8(iterator.codeBuffer, iterator.code));
                    }
                    else
                        writer.put(encodedBackslash);
                    break;
            }

            startIndex += iterator.count;
        }
    }

    final T[] escapeString(T)(return T[] value) const nothrow pure
    if (is(Unqual!T == char))
    {
        if (value.length == 0)
            return value;

        // Find the first quote char
        const p = escapeStartIndex(value, CharClass.stringQuote);

        // No quote char found?
        if (p >= value.length)
            return value;

        auto result = Appender!(T[])(value.length + 50);
        escapeStringImpl(result, value, p);
        return result.data;
    }

    private void escapeStringImpl(Writer)(ref Writer writer, scope const(char)[] value, size_t startIndex) const nothrow pure
    {
        if (startIndex)
            writer.put(value[0..startIndex]);

        UTF8Iterator iterator;
        while (startIndex < value.length)
        {
            if (!nextUTF8Char(value, startIndex, iterator.code, iterator.count))
                iterator.code = replacementChar;

            final switch (charClass(iterator.code))
            {
                case CharClass.any:
                case CharClass.idenfifierQuote:
                    writer.put(encodeUTF8(iterator.codeBuffer, iterator.code));
                    break;
                case CharClass.stringQuote:
                    const encodedQuote = encodeUTF8(iterator.codeBuffer, iterator.code);
                    writer.put(encodedQuote);
                    writer.put(encodedQuote);
                    break;
                case CharClass.backslashSequence:
                    const encodedBackslash = encodeUTF8(iterator.codeBuffer, iterator.code);
                    writer.put(encodedBackslash);
                    startIndex += iterator.count;
                    if (startIndex < value.length)
                    {
                        if (!nextUTF8Char(value, startIndex, iterator.code, iterator.count))
                            iterator.code = replacementChar;
                        writer.put(encodeUTF8(iterator.codeBuffer, iterator.code));
                    }
                    else
                        writer.put(encodedBackslash);
                    break;
            }

            startIndex += iterator.count;
        }
    }

    private size_t escapeStartIndex(scope const(char)[] value, const(CharClass) forCharClass) const nothrow pure
    {
        size_t result;
        UTF8Iterator iterator;
        while (result < value.length && nextUTF8Char(value, result, iterator.code, iterator.count))
        {
            const cc = charClass(iterator.code);
            if (cc == forCharClass || cc == CharClass.backslashSequence)
                break;
            result += iterator.count;
        }
        return result;
    }

    static string generateCacheKey(string name, string nameCategory, string databaseCacheKey,
        string schema = null) nothrow pure
    {
        return schema.length == 0
            ? name ~ "." ~ nameCategory  ~ "." ~ databaseCacheKey
            : schema ~ "." ~ name ~ "." ~ nameCategory  ~ "." ~ databaseCacheKey;
    }

    static string generateCacheKeyStoredProcedure(string storedProcedureName, string databaseCacheKey,
        string schema = null) nothrow pure
    {
        return generateCacheKey(storedProcedureName, "StoredProcedure", databaseCacheKey, schema);
    }

    /**
     * Return a contruct to limits the rows returned in a query result set to a specified number of rows
     * witch the OFFSET clause.
     * However, MS-SQL engine requires there is an ORDER BY clause
     * Params:
     *   rows = specified number of rows to return
     *          < 0 - returns empty
     *          database engine specific limit keyword ...(1...)
     *   offset = specified number of rows to be skipped
     * SELECT column... FROM table... [ORDER BY...] specific limit keyword 1... specific offset keyword 0...
     */
    abstract string limitClause(int32 rows, uint32 offset = 0) const nothrow pure;

    string parameterPlaceholder(string parameterName, uint32 ordinal) const nothrow pure
    {
        return "?";
    }

    final string quoteIdentifier(scope const(char)[] value) const nothrow pure
    {
        auto result = Appender!string(value.length + 10);
        return quoteIdentifier(result, value).data;
    }

    final ref Writer quoteIdentifier(Writer)(return ref Writer writer, scope const(char)[] value) const nothrow pure
    {
        writer.put(identifierQuoteChar);
        escapeIdentifierImpl(writer, value, escapeStartIndex(value, CharClass.idenfifierQuote));
        writer.put(identifierQuoteChar);
        return writer;
    }

    final ref Writer quoteIdentifierIf(Writer)(return ref Writer writer, scope const(char)[] value) const nothrow pure
    {
        const i = escapeStartIndex(value, CharClass.idenfifierQuote);
        const needQuote = i < value.length;
        if (needQuote)
            writer.put(identifierQuoteChar);
        escapeIdentifierImpl(writer, value, i);
        if (needQuote)
            writer.put(identifierQuoteChar);
        return writer;
    }

    final string quoteString(scope const(char)[] value) const nothrow pure
    {
        auto result = Appender!string(value.length + 50);
        return quoteString(result, value).data;
    }

    final ref Writer quoteString(Writer)(return ref Writer writer, scope const(char)[] value) const nothrow pure
    {
        writer.put(stringQuoteChar);
        escapeStringImpl(writer, value, escapeStartIndex(value, CharClass.stringQuote));
        writer.put(stringQuoteChar);
        return writer;
    }

    /**
     * Return a contruct to limits the rows returned in a query result set to a specified number of rows.
     * However, not all database engines support this contruct. an empty string is returned.
     * If the rows is greater than 0, it is better to use `limitClause` instead. Only Firebird & MS-SQL support it.
     * Params:
     *   rows = specified number of rows to return
     *          < 0 - returns empty
     *          database engine specific top keyword...(1...)
     * SELECT topClause(1...) column... FROM table...
     */
    abstract string topClause(int32 rows) const nothrow pure;

    @property final DbCache!string cache() nothrow pure
    {
        return _cache;
    }

    pragma(inline, true)
    @property final char identifierQuoteChar() const @nogc nothrow pure
    {
        return _identifierQuoteChar;
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
     * Returns true if database supports RETURNING clause, otherwise false
     */
    @property abstract bool returningClause() const nothrow pure;

    /**
     * Name of database kind, firebird, postgresql ...
     * Refer pham.db.type.DbScheme for a list of possible values
     */
    @property abstract DbScheme scheme() const nothrow pure;

    pragma(inline, true)
    @property final string stringConcatOp() const @nogc nothrow pure
    {
        return _stringConcatOp;
    }

    pragma(inline, true)
    @property final char stringQuoteChar() const @nogc nothrow pure
    {
        return _stringQuoteChar;
    }

    /**
     * Returns a separated list of hint keywords if database supports,
     * otherwise an empty/null string
     */
    @property abstract string tableHint() const nothrow pure;

protected:
    final void populateValidParamNameChecks() nothrow
    {
        const names = connectionStringParameterNames();
        _validParamNameChecks.reserve(names.length + 5, names.length);
        foreach (n; names)
            _validParamNameChecks[n] = true;
    }

protected:
    DbCache!string _cache;
    Dictionary!(dchar, CharClass) _charClasses;
    Dictionary!(string, bool) _validParamNameChecks;
    string _stringConcatOp;
    char _identifierQuoteChar;
    char _stringQuoteChar;

private:
    shared Logger _logger;
}

// This instance is initialize at startup hence no need Mutex to have thread-guard
class DbDatabaseList : DbNamedObjectList!DbDatabase
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

    /**
     * Finds a registered DbDatabase instance if matching scheme,
     * return true if there is a matching otherwise false.
     * It is thread safe if add/remove DbDatabase is called only in startup (shared static this())
     * Params:
     *  scheme = a scheme value to look for
     *  database = hold the found registered DbDatabase object
     */
    static bool findDb(DbScheme scheme, ref DbDatabase database) nothrow @safe
    {
        auto lst = instance();
        return lst.find(scheme, database);
    }

    /**
     * Finds a registered DbDatabase instance if matching scheme in string form,
     * return true if there is a matching otherwise false.
     * It is thread safe if add/remove DbDatabase is called only in startup (shared static this())
     * Params:
     *  scheme = a scheme value to look for
     *  database = hold the found registered DbDatabase object
     */
    static bool findDb(string scheme, ref DbDatabase database) nothrow @safe
    {
        DbScheme dbScheme;
        if (!isDbScheme(scheme, dbScheme))
            return false;

        return findDb(dbScheme, database);
    }

    /**
     * Returns a registered DbDatabase instance if matching scheme,
     * will throw DbException if there is no matching.
     * It is thread safe if add/remove DbDatabase is called only in startup (shared static this())
     * Params:
     *  scheme = a scheme value to look for
     */
    static DbDatabase getDb(DbScheme scheme) @safe
    {
        DbDatabase result;
        if (findDb(scheme, result))
            return result;

        auto msg = DbMessage.eInvalidSchemeName.fmtMessage(scheme);
        throw new DbException(0, msg);
    }

    /**
     * Returns a registered DbDatabase instance if matching scheme in string form,
     * will throw DbException if there is no matching.
     * It is thread safe if add/remove DbDatabase is called only in startup (shared static this())
     * Params:
     *  scheme = a scheme value to look for
     */
    static DbDatabase getDb(string scheme) @safe
    {
        DbDatabase result;
        if (findDb(scheme, result))
            return result;

        auto msg = DbMessage.eInvalidSchemeName.fmtMessage(scheme);
        throw new DbException(0, msg);
    }

    /**
     * Returns a singular instance of DbDatabaseList
     */
    static DbDatabaseList instance() nothrow @trusted
    {
        return singleton(_instance, &createInstance);
    }

    /**
     * Registers an instance of vendor specific database object.
     * It should be called only on startup function (shared static this()) because it is not thread safe
     */
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

class DbNamedColumn : DbNamedObject
{
public:
    /*
     * Indicates if column value is an external resource id which needs special loading/saving
     */
    DbColumnIdType isValueIdType() const nothrow @safe
    {
        return DbColumnIdType.no;
    }

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
    @property final bool allowNull() const nothrow @safe
    {
        return _flags.allowNull;
    }

    @property final typeof(this) allowNull(bool value) nothrow @safe
    {
        _flags.allowNull = value;
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
    @property final int16 baseNumericDigits() const nothrow @safe
    {
        return _baseType.numericDigits;
    }

    @property final typeof(this) baseNumericDigits(int16 value) nothrow @safe
    {
        _baseType.numericDigits = value;
        return this;
    }

    /**
     * Gets or sets provider-specific numeric scale of the column
     */
    @property final int16 baseNumericScale() const nothrow @safe
    {
        return _baseType.numericScale;
    }

    @property final typeof(this) baseNumericScale(int16 value) nothrow @safe
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
    @property final DbBaseTypeInfo baseType() const nothrow @safe
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

    @property final DbCommand command() nothrow pure @safe
    {
        return _command;
    }

    @property final DbDatabase database() nothrow pure @safe
    {
        return _database;
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
     * Gets or sets whether this column is a key for the dataset
     */
    @property final bool isKey() const nothrow @safe
    {
        return _flags.isKey;
    }

    @property final typeof(this) isKey(bool value) nothrow @safe
    {
        _flags.isKey = value;
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

    @property final SaveLongData saveLongData() nothrow pure @safe
    {
        return _saveLongData;
    }

    @property final typeof(this) saveLongData(SaveLongData value) nothrow @trusted
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(value?=", value !is null, ", _list?=", _list !is null, ", columns?=", cast(DbColumnList)_list !is null, ", params?=", cast(DbParameterList)_list !is null, ")");
        
        if (auto cl = cast(DbColumnList)_list)
        {
            if (_saveLongData !is null)
                cl._saveLongDataCount--;
            if (value !is null)
                cl._saveLongDataCount++;
        }
        else if (auto pl = cast(DbParameterList)_list)
        {
            if (_saveLongData !is null)
                pl._saveLongDataCount--;
            if (value !is null)
                pl._saveLongDataCount++;
        }

        _saveLongData = value;
        return this;
    }

    /**
     * Gets or sets maximum size, in bytes of the parameter
     * used for array, binary, binaryFixed, utf8String, fixedUtf8String
     * json, and xml types.
     */
    pragma(inline, true)
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
    pragma(inline, true)
    @property final DbType type() const nothrow @safe
    {
        return _type & ~DbType.array;
    }

    @property final typeof(this) type(DbType value) nothrow @safe
    {
        // Maintain the array flag
        _type = isArray ? (value | DbType.array) : value;

        if (!isDbTypeHasSize(_type))
            _size = 0;

        return this;
    }

protected:
    void assignTo(DbNamedColumn dest) nothrow @safe
    {
        debug(debug_pham_db_db_database) string memberNames;

        foreach (m; FieldNameTuple!DbNamedColumn)
        {
            debug(debug_pham_db_db_database) { if (memberNames.length == 0) memberNames = m; else memberNames ~= m; }

            __traits(getMember, dest, m) = __traits(getMember, this, m);
        }

        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(memberNames=", memberNames, ")");
    }

    void reevaluateBaseType() nothrow @safe
    {}

protected:
    DbCommand _command;
    DbDatabase _database;
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
    SaveLongData _saveLongData;
}

deprecated("please use DbColumn")
alias DbField = DbColumn;

deprecated("please use DbColumnList")
alias DbFieldList = DbColumnList;

class DbParameter : DbNamedColumn
{
public:
    this(DbDatabase database, DbCommand command, DbIdentitier name) nothrow @safe
    {
        this._database = database;
        this._command = command;
        this._name = name;
        this._flags.allowNull = true;
    }

    final DbParameter cloneMetaInfo(DbParameter source) nothrow @safe
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

    static string generateName(uint32 ordinal) nothrow pure @safe
    {
        import pham.utl.utl_object : nToString = toString;

        auto buffer = Appender!string(anonymousParameterNamePrefix.length + 10);
        return buffer.put(anonymousParameterNamePrefix)
            .nToString(ordinal)
            .data;
    }

    final size_t loadBlob(uint64 loadedSize, size_t segmentSize, ref scope const(ubyte)[] data) @safe
    in
    {
        assert(!isNull);
    }
    do
    {
        if (loadLongData !is null)
            return loadLongData(this, loadedSize, segmentSize, data);
        else
        {
            data = value.get!(const(ubyte)[])();
            return data.length;
        }
    }

    final size_t loadClob(uint64 loadedSize, size_t segmentSize, ref scope const(char)[] data) @safe
    in
    {
        assert(!isNull);
    }
    do
    {
        if (loadLongData !is null)
        {
            const(ubyte)[] dataBytes;
            const result = loadLongData(this, loadedSize, segmentSize, dataBytes);
            data = cast(const(char)[])dataBytes;
            return result;
        }
        else
        {
            data = value.get!(const(char)[])();
            return data.length;
        }
    }

    final bool hasInputValue() const nothrow @safe
    {
        return isInput() && (!this.isNull || loadLongData !is null);
    }

    final bool isInput(InputDirectionOnly inputOnly = InputDirectionOnly.no) const nothrow @safe
    {
        static immutable inputFlags = [inputDirections(InputDirectionOnly.no), inputDirections(InputDirectionOnly.yes)];

        return inputFlags[inputOnly].isOn(direction);
    }

    final bool isOutput(OutputDirectionOnly outputOnly = OutputDirectionOnly.no) const nothrow @safe
    {
        static immutable outputFlags = [outputDirections(OutputDirectionOnly.no), outputDirections(OutputDirectionOnly.yes)];

        return outputFlags[outputOnly].isOn(direction);
    }

    final DbParameter updateEmptyName(DbIdentitier noneEmptyName) nothrow @safe
    in
    {
        assert(noneEmptyName.length > 0);
        assert(name.length == 0);
    }
    do
    {
        name = noneEmptyName;
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

    @property final bool isNull() const nothrow @safe
    {
        if (isInput() && loadLongData !is null)
            return false;
        else
            return _dbValue.isNull || (isDbTypeHasZeroSizeAsNull(type) && _dbValue.size <= 0);
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

public:
    LoadLongData loadLongData;

protected:
    override void assignTo(DbNamedColumn dest) nothrow @safe
    {
        super.assignTo(dest);

        if (auto destP = cast(DbParameter)dest)
        {
            destP._direction = this._direction;
            destP._dbValue = this._dbValue;
            destP.loadLongData = this.loadLongData;
        }
    }

    final void nullifyValue() nothrow @safe
    {
        _dbValue.nullify();
        if (type != DbType.unknown)
            _dbValue.type = type;
    }

    void resetStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        if (kind == ResetStatementKind.executing && isOutput(OutputDirectionOnly.yes))
            nullifyValue();
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

class DbParameterList : DbNamedObjectList!DbParameter, IDisposable
{
public:
    this(DbDatabase database, DbCommand command) nothrow @safe
    {
        this._database = database;
        this._command = command;
    }

    DbParameter add(DbIdentitier name, DbType type, DbParameterDirection direction, int32 size) nothrow @safe
    in
    {
        assert(name.length != 0);
        assert(!exist(name), name.value);
    }
    do
    {
        auto result = create(name);
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
        assert(!exist(name), name);
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
        assert(!exist(name), name);
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

    final DbParameterList add(Variant[string] values) @safe
    {
        foreach (k, v; values)
            add(k, DbType.unknown, v);

        return this;
    }

    final DbParameter addClone(DbParameter source) @safe
    in
    {
        assert(source !is null);
    }
    do
    {
        auto result = add(source.name, source.type, source.direction, source.size);
        source.assignTo(result);
        return result;
    }

    final DbParameterList assign(DbParameterList source) @safe
    {
        clear();
        if (source is null)
            return this;

        reserve(source.length);
        foreach (e; source)
            addClone(e);

        return this;
    }

    final DbParameter create(DbIdentitier name) nothrow @safe
    {
        return database !is null
            ? database.createParameter(command, name)
            : new DbParameter(null, command, name);
    }

    final DbParameter create(string name) nothrow @safe
    {
        auto id = DbIdentitier(name);
        return database !is null
            ? database.createParameter(command, id)
            : new DbParameter(null, command, id);
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

    final string generateName() nothrow @safe
    {
        return DbParameter.generateName(cast(uint)(length + 1));
    }

    final bool hasInput(InputDirectionOnly inputOnly = InputDirectionOnly.no) const nothrow @safe
    {
        return parameterHasOfs(inputDirections(inputOnly));
    }

    final bool hasOutput(OutputDirectionOnly outputOnly = OutputDirectionOnly.no) const nothrow @safe
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
            if (result.isOutput(OutputDirectionOnly.no))
            {
                if (outIndex++ == outputIndex)
                    return result;
            }
        }

        return null;
    }

    final size_t inputCount(InputDirectionOnly inputOnly = InputDirectionOnly.no) const nothrow @safe
    {
        return parameterCountOfs(inputDirections(inputOnly));
    }

    final T[] inputs(T : DbParameter)(InputDirectionOnly inputOnly = InputDirectionOnly.no) nothrow @safe
    {
        return parameterOfs!T(inputDirections(inputOnly));
    }

    final size_t outputCount(OutputDirectionOnly outputOnly = OutputDirectionOnly.no) const nothrow @safe
    {
        return parameterCountOfs(outputDirections(outputOnly));
    }

    final T[] outputs(T : DbParameter)(OutputDirectionOnly outputOnly = OutputDirectionOnly.no) nothrow @safe
    {
        return parameterOfs!T(outputDirections(outputOnly));
    }

    final size_t parameterCountOfs(scope const(EnumSet!DbParameterDirection) directions) const nothrow @trusted
    {
        size_t result = 0;
        foreach (item; cast()this)
        {
            if (directions.isOn(item.direction))
                result++;
        }
        return result;
    }

    final bool parameterHasOfs(scope const(EnumSet!DbParameterDirection) directions) const nothrow @trusted
    {
        foreach (item; cast()this)
        {
            if (directions.isOn(item.direction))
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
            if (directions.isOn(parameter.direction))
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

    @property final DbCommand command() nothrow pure @safe
    {
        return _command;
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

    @property final uint16 saveLongDataCount() const @nogc nothrow @safe
    {
        return _saveLongDataCount;
    }

protected:
    void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        clear();
        if (isDisposing(disposingReason))
        {
            _command = null;
            _database = null;
        }
    }

    override void notify(DbParameter item, const(NotificationKind) kind) nothrow @safe
    {
        //super.notify(item, kind);
        if (kind == NotificationKind.added)
            item._ordinal = cast(uint32)length;
        else if (kind == NotificationKind.cleared)
            _saveLongDataCount = 0;
    }

    final void resetStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(kind=", kind, ")");

        foreach (parameter; this)
            parameter.resetStatement(kind);
    }

protected:
    DbCommand _command;
    DbDatabase _database;
    uint16 _saveLongDataCount;

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
        this._columns = command.columns;
        this._flags.checkRows = true;
        this._flags.implicitTransaction = implicitTransaction;
        this._flags.ownCommand = ownCommand;
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

        if (_flags.cacheResult && _columns !is null)
        {
            // If already cloned, skip
            if (_columns.command !is null)
                _columns = _columns.clone(null);
        }
        else
        {
            _columns = null;
            _currentRow.dispose(DisposingReason.dispose);
        }

        if (_command !is null)
            doDetach(DisposingReason.dispose);

        _flags.allRowsFetched = true; // No longer able to fetch after detached
        _flags.checkRows = false;

        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        if (_command !is null)
            doDetach(disposingReason);

        _columns = null;
        _fetchedRowCount = 0;
        _flags.allRowsFetched = true;
        _flags.checkRows = false;
        _currentRow.dispose(disposingReason);
    }

    /**
     * Gets the DbValue of the specified column colIndex
     */
    DbValue getDbValue(const(size_t) colIndex) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(colIndex < _currentRow.length);
    }
    do
    {
        return _currentRow[colIndex];
    }

    /**
     * Gets the DbValue of the specified column name
     */
    DbValue getDbValue(string colName) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(columns.indexOf(colName) >= 0);
    }
    do
    {
        return getDbValue(columns.indexOfCheck(colName));
    }

    /**
     * Gets the column index given the name of the column
     */
    ptrdiff_t getIndex(scope const(DbIdentitier) colName) nothrow @safe
    {
        return columns.indexOf(colName);
    }

    ptrdiff_t getIndex(string colName) nothrow @safe
    {
        auto id = DbIdentitier(colName);
        return columns.indexOf(id);
    }

    /**
     * Gets the name of the column, given the column index
     */
    string getName(const(size_t) colIndex) nothrow @safe
    in
    {
        assert(colIndex < columns.length);
    }
    do
    {
        return columns[colIndex].name;
    }

    /**
     * Gets the Variant of the specified column index
     */
    Variant getValue(const(size_t) colIndex) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(colIndex < _currentRow.length);
    }
    do
    {
        return getVariant(colIndex);
    }

    T getValue(T)(const(size_t) colIndex) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(colIndex < _currentRow.length);
    }
    do
    {
        return isNull(colIndex) ? T.init : getVariant(colIndex).get!T();
    }

    /**
     * Gets the Variant of the specified column name
     */
    Variant getValue(string colName) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(columns.indexOf(colName) >= 0);
    }
    do
    {
        return getValue(columns.indexOfCheck(colName));
    }

    bool isNull(const(size_t) colIndex) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(colIndex < _currentRow.length);
    }
    do
    {
        return _currentRow[colIndex].isNull();
    }

    /**
     * Gets a value that indicates whether the column contains nonexistent or missing value
     */
    bool isNull(string colName) @safe
    in
    {
        assert(!_flags.checkRows);
        assert(columns.indexOf(colName) >= 0);
    }
    do
    {
        return isNull(columns.indexOfCheck(colName));
    }

    void popFront() @safe
    {
        // Initialize the first row?
        if (_flags.checkRows)
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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(_fetchedRowCount=", _fetchedRowCount, ")");
        version(profile) debug auto p = PerfFunction.create();

        if (_flags.checkRows)
            return fetchFirst(false);

        if (!_flags.allRowsFetched)
        {
            if (!_flags.skipFetchNext)
                fetchNext();
            _flags.skipFetchNext = false;
        }

        return !_flags.allRowsFetched;
    }

    /* Properties */

    @property size_t colCount() @safe
    in
    {
        assert(!_flags.checkRows);
    }
    do
    {
        return _currentRow.length;
    }

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
        return hasRows ? _flags.allRowsFetched : true;
    }

    /**
     * Returns number of defining columns of this DbReader
     */
    @property size_t columnCount() const nothrow @safe
    {
        return _columns !is null ? _columns.length : 0;
    }

    deprecated("please use columnCount")
    alias fieldCount = columnCount;

    @property DbColumnList columns() nothrow pure @safe
    {
        return _columns;
    }

    deprecated("please use columns")
    alias fields = columns;

    /**
     * Returns number of rows had been read/fetched so far
     */
    @property size_t fetchedRowCount() const nothrow @safe
    {
        return _fetchedRowCount;
    }

    /**
     * Gets a value that indicates whether this DbReader contains one or more rows
     */
    @property bool hasRows() @safe
    {
        if (_flags.checkRows)
            fetchFirst(true);

        return _fetchedRowCount != 0;
    }

    @property bool implicitTransaction() const nothrow @safe
    {
        return _flags.implicitTransaction;
    }

    @property bool ownCommand() const nothrow @safe
    {
        return _flags.ownCommand;
    }

private:
    enum Flag : ubyte
    {
        allRowsFetched,
        cacheResult,
        checkRows,
        implicitTransaction,
        ownCommand,
        skipFetchNext,
    }

    void doDetach(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(disposingReason=", disposingReason, ")");

        _command.removeReader(this);
        scope (exit)
        {
            _command = null;
            _flags.checkRows = false;
            _flags.implicitTransaction = false;
            _flags.ownCommand = false;
        }
        if (ownCommand)
            _command.dispose(disposingReason);
    }

    bool fetchFirst(const(bool) checking) @safe
    in
    {
         assert(_flags.checkRows);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(checking=", checking, ")");

        _currentRow = _command.fetch(false);
        _flags.checkRows = false;
        const hasRow = _currentRow.length != 0;
        if (hasRow)
        {
            _fetchedRowCount++;
            if (checking)
                _flags.skipFetchNext = true;
            readRowBlob(_currentRow);
        }
        else
        {
            _flags.allRowsFetched = true;
        }

        debug(debug_pham_db_db_database) debug writeln("\t", "_fetchedRowCount=", _fetchedRowCount, ", hasRow=", hasRow);

        return hasRow;
    }

    void fetchNext() @safe
    in
    {
         assert(!_flags.checkRows);
    }
    do
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "()");

        _currentRow = _command.fetch(false);
        const hasRow = _currentRow.length != 0;
        if (hasRow)
        {
            _fetchedRowCount++;
            readRowBlob(_currentRow);
        }
        else
            _flags.allRowsFetched = true;

        debug(debug_pham_db_db_database) debug writeln("\t", "_fetchedRowCount=", _fetchedRowCount, ", hasRow=", hasRow);
    }

    Variant getVariant(const(size_t) colIndex) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(colIndex=", colIndex, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto column = _columns[colIndex];
        final switch (column.isValueIdType())
        {
            case DbColumnIdType.no:
                return _currentRow[colIndex].value;
            case DbColumnIdType.array:
                return _command.readArray(column, _currentRow[colIndex]);
            case DbColumnIdType.blob:
                if (column.saveLongData is null)
                {
                    ubyte[] blob;
                    _command.readBlob(column, _currentRow[colIndex], _currentRow.row, blob);
                    return Variant(blob);
                }
                else
                    return Variant.varNull; // Variant(_command.readBlob(column, _currentRow[colIndex], _currentRow.row));
            case DbColumnIdType.clob:
                if (column.saveLongData is null)
                {
                    string clob;
                    _command.readClob(column, _currentRow[colIndex], _currentRow.row, clob);
                    return Variant(clob);
                }
                else
                    return Variant.varNull; // Variant(_command.readBlob(column, _currentRow[colIndex], _currentRow.row));
        }
    }

    void readRowBlob(ref DbRowValue rowValue) @safe
    {
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(_columns.saveLongDataCount=", _columns.saveLongDataCount, ")");
        
        if (_columns.saveLongDataCount == 0)
            return;

        foreach (i, column; _columns)
        {
            if (column.saveLongData is null)
                continue;

            final switch (column.isValueIdType())
            {
                case DbColumnIdType.no:
                case DbColumnIdType.array:
                    break;

                case DbColumnIdType.blob:
                case DbColumnIdType.clob:
                    _command.readBlob(column, rowValue[i], rowValue.row);
            }
        }
    }

private:
    DbCommand _command;
    DbColumnList _columns;
    DbRowValue _currentRow;
    size_t _fetchedRowCount;
    EnumSet!Flag _flags;
}

enum DbRoutineType : string
{
    storedFunction = "FUNCTION",
    storedProcedure = "PROCEDURE",
}

class DbRoutineInfo
{
@safe:

public:
    this(DbDatabase database, string name, DbRoutineType type) nothrow
    in
    {
        assert(database !is null);
        assert(name.length != 0);
    }
    do
    {
        this._database = database;
        this._name = name;
        this._type = type;
        this._argumentTypes = database.createParameterList(null);
        this._returnType = database.createParameter(null, DbIdentitier(returnParameterName));
        this._returnType.direction = DbParameterDirection.returnValue;
    }

    @property final DbParameterList argumentTypes() nothrow
    {
        return _argumentTypes;
    }

    @property final DbDatabase database() nothrow pure
    {
        return _database;
    }

    @property final bool hasReturnType() const nothrow
    {
        return _returnType.type != DbType.unknown;
    }

    @property final string name() const nothrow
    {
        return _name;
    }

    @property final DbParameter returnType() nothrow
    {
        return _returnType;
    }

    @property final DbRoutineType type() const nothrow
    {
        return _type;
    }

protected:
    DbParameterList _argumentTypes;
    DbParameter _returnType;

private:
    DbDatabase _database;
    string _name;
    DbRoutineType _type;
}

abstract class DbTransaction : DbDisposableObject
{
public:
    this(DbConnection connection, DbIsolationLevel isolationLevel) nothrow @safe
    {
        this._connection = connection;
        this._database = connection.database;
        this._isolationLevel = isolationLevel;
        this._lockTimeout = dur!"seconds"(DbDefault.transactionLockTimeout);
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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(savePointName=", savePointName, ")");

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
        debug(debug_pham_db_db_database) debug writeln(__FUNCTION__, "(savePointName=", savePointName, ")");

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
    @property final bool autoCommit() const nothrow @safe
    {
        return _flags.autoCommit;
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
            _flags.autoCommit = value;
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
    @property final DbIsolationLevel isolationLevel() const nothrow @safe
    {
        return _isolationLevel;
    }

    @property final bool isRetaining() const nothrow @safe
    {
        return _flags.retaining;
    }

    @property final string lastPointName() const nothrow @safe
    {
        return _savePointNames.length ? _savePointNames[$-1] : null;
    }

    @property final DbLockTable[] lockedTables() nothrow @safe
    {
        return _lockedTables;
    }

    /**
     * Transaction lock time-out
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

    pragma(inline, true)
    @property final Logger logger() nothrow pure @safe
    {
        return _connection !is null ? _connection.logger : null;
    }

    /**
     * Default value is false
     */
    @property final bool readOnly() const nothrow @safe
    {
        return _flags.readOnly;
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
            _flags.readOnly = value;
            doOptionChanged("readOnly");
        }
        return this;
    }

    /**
     * Current list of pending save-point names
     */
    @property final const(string)[] savePointNames() const nothrow @safe
    {
        return _savePointNames;
    }

    /**
     * Indicator of current state of transaction
	 */
    @property final DbTransactionState state() const nothrow @safe
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
            debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
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

    string createSavePointStatement(const(DbSavePoint) mode, string savePointName) const nothrow @safe
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
            debug(debug_pham_db_db_database) debug writeln("\t", e.msg);
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
    debug(debug_pham_db_db_database) debug writeln("shared static this(", __MODULE__, ")");

    _secondTimer = new Timer(dur!"seconds"(1));
}

shared static ~this() nothrow
{
    debug(debug_pham_db_db_database) debug writeln("shared static ~this(", __MODULE__, ")");

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
