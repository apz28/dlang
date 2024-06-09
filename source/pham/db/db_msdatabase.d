/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.db_msdatabase;

version(Windows):

pragma(lib, "odbc32");

import pham.external.std.windows.sql;
import pham.external.std.windows.sqlext;
import pham.external.std.windows.sqltypes;
import std.array : Appender;
import std.conv : text, to;

debug(debug_pham_db_db_msdatabase) import pham.db.db_debug;
import pham.external.std.log.log_logger : Logger, LogLevel, LogTimming;
import pham.utl.utl_array : indexOf;
import pham.utl.utl_result : genericErrorMessage, osCharToString;
import pham.db.db_convert;
import pham.db.db_database;
import pham.db.db_object;
import pham.db.db_type;
import pham.db.db_value;
import pham.db.db_msexception;
import pham.db.db_mstype;

class MsCancelCommandData: DbCancelCommandData
{
@safe:

public:
    this(MsCommand command)
    {
        this.commandHandle = command.msHandle;
    }

public:
    SQLHSTMT commandHandle;
}

class MsCommand : DbCommand
{
public:
    this(MsConnection connection, string name = null) nothrow @safe
    {
        super(connection, name);
    }

    this(MsConnection connection, MsTransaction transaction, string name = null) nothrow @safe
    {
        super(connection, transaction, name);
    }

    // Currently not working, just return empty
	final override string getExecutionPlan(uint vendorMode) @safe
	{
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(vendorMode=", vendorMode, ")");

        return null;
        /*
        static immutable showCommand = "SET SHOWPLAN_XML ";
        msConnection.executeNonQuery(showCommand ~ "ON");
        scope (exit)
            msConnection.executeNonQuery(showCommand ~ "OFF");

        auto planCommand = cast(MsCommand)msConnection.createNonTransactionCommand(true);
        scope (exit)
            planCommand.dispose();

        planCommand.commandText = this.commandText;
        planCommand.executeNonQuery();
        return planCommand.planInfo.message;
        */
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

    @property final MsConnection msConnection() nothrow pure @safe
    {
        return cast(MsConnection)connection;
    }

    @property final SQLHSTMT msHandle() nothrow pure @trusted
    {
        return cast(SQLHSTMT)_handle.get!size_t;
    }

protected:
    final void allocateHandle() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        SQLHSTMT hStmt;
        MsConnection.checkSQLResult(SQLAllocHandle(SQL_HANDLE_STMT, msConnection.msHandle, &hStmt),
            SQL_HANDLE_STMT, hStmt, "SQLAllocHandle");
        _handle = DbHandle(cast(size_t)hStmt);
    }

    final void bindFields() nothrow @safe
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(hasFields=", hasFields, ")");

        foreach (field; fields)
        {
            auto msField = cast(MsField)field;
            msField.bindData.getBindField(msField.baseType);
        }
    }

    final void bindParameters() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(hasParameters=", hasParameters, ")");

        auto commandHandle = msHandle;
        foreach (param; parameters)
        {
            auto msParam = cast(MsParameter)param;

            if (msParam.baseTypeId == 0)
                msParam.reevaluateBaseType();

            auto bindData = msParam.isInput
                ? msParam.bindData.getBindParameter(msParam.direction, msParam.baseType, msParam.value)
                : msParam.bindData.getBindParameter(msParam.direction, msParam.baseType);

            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "name=", msParam.name, ", targetInputType=", bindData.targetInputType,
                ", targetType=", bindData.targetType, ", baseTypeId=", msParam.baseTypeId, ", baseSize=", msParam.baseSize,
                ", baseNumericScale=", msParam.baseNumericScale, ", targetLength=", bindData.targetLength, ", strLenOrIndPtr=", bindData.strLenOrIndPtr);

            MsConnection.checkSQLResult(SQLBindParameter(commandHandle, cast(SQLUSMALLINT)msParam.ordinal, bindData.targetInputType,
                bindData.targetType, cast(SQLSMALLINT)msParam.baseTypeId, msParam.baseSize, msParam.baseNumericScale,
                bindData.targetValuePtr, bindData.targetLength, bindData.strLenOrIndPtr),
                SQL_HANDLE_STMT, commandHandle, "SQLBindParameter");
        }
    }

    final override string buildStoredProcedureSql(string storedProcedureName, const(BuildCommandTextState) state) @safe
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(storedProcedureName=", storedProcedureName, ", state=", state, ")");

        if (storedProcedureName.length == 0)
            return null;

        Appender!string result;
        result.reserve(500);
        result.put('{');
        if (hasParameters)
        {
            auto params = parameters();
            const hasReturn = params[0].direction == DbParameterDirection.returnValue ? 1 : 0;
            if (hasReturn)
            {
                auto param = params[0];
                result.put(buildParameterPlaceholder(param.name, 0 + 1));
                result.put(" = ");
            }
            result.put("call ");
            result.put(storedProcedureName);
            result.put('(');
            foreach (i; hasReturn..params.length)
            {
                if (i > hasReturn)
                    result.put(',');
                auto param = params[i];
                result.put(buildParameterPlaceholder(param.name, cast(uint32)(i + 1)));
            }
            result.put(')');
        }
        else
        {
            result.put("call ");
            result.put(storedProcedureName);
            result.put("()");
        }
        result.put('}');

        debug(debug_pham_db_db_msdatabase) debug writeln("\t", "storedProcedureName=", storedProcedureName, ", result=", result.data);

        return result.data;
    }

    final void deallocateHandle() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        // Must reset regardless if error taken place
        // to avoid double errors when connection is shutting down
        scope (exit)
            _handle.reset();

        //SQLFreeStmt(msHandle, SQL_CLOSE);
        SQLFreeHandle(SQL_HANDLE_STMT, msHandle);
    }

    final override void doExecuteCommand(const(DbCommandExecuteType) type) @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(type=", type, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doExecuteCommand()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;

        if (!_handle)
            allocateHandle();

        prepareExecuting(type);

        auto commandHandle = msHandle;

        const timeout = limitRangeTimeoutAsSecond(commandTimeout, Duration.zero);
        if (timeout)
            setCommandIntAttr!SQLULEN(SQL_ATTR_QUERY_TIMEOUT, timeout);

        DbNotificationMessage exeInfo;
        if (hasParameters)
        {
            bindParameters();
            exeInfo = MsConnection.checkSQLResult(SQLExecute(commandHandle), SQL_HANDLE_STMT, commandHandle, "SQLExecute");
        }
        else
        {
            const sql = _executeCommandText;
            exeInfo = MsConnection.checkSQLResult(SQLExecDirect(commandHandle, cast(SQLCHAR*)&sql[0], cast(SQLINTEGER)sql.length),
                SQL_HANDLE_STMT, commandHandle, "SQLExecDirect");
        }

        if (getExecutionPlanning)
            planInfo = exeInfo;

        if (returnRecordsAffected)
        {
            SQLLEN rowCount;
            MsConnection.checkSQLResult(SQLRowCount(commandHandle, &rowCount),
                SQL_HANDLE_STMT, commandHandle, "SQLRowCount");
            _recordsAffected = rowCount;
        }

        if (!getExecutionPlanning)
        {
            if (type != DbCommandExecuteType.nonQuery && !hasFields)
                getFieldInfos();

            if (hasParameters && isStoredProcedure)
                readOutputParameters();
        }
    }

    final override bool doExecuteCommandNeedPrepare(const(DbCommandExecuteType) type) nothrow @safe
    {
        return super.doExecuteCommandNeedPrepare(type) || hasParameters || isStoredProcedure;
    }

    final override void doFetch(const(bool) isScalar) @trusted
    in
    {
        assert(!allRowsFetched);
    }
    do
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ", fetchRecordCount=", fetchRecordCount, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doFetch()", newline, _executeCommandText), false, logTimmingWarningDur)
            : LogTimming.init;
        
        bindFields();

        auto commandHandle = msHandle;
        uint continueFetchingCount = isScalar ? 1 : fetchRecordCount;

        while (continueFetchingCount)
        {
            const r = SQLFetch(commandHandle);
            if (r == SQL_NO_DATA)
            {
                allRowsFetched = true;
                return;
            }
            MsConnection.checkSQLResult(r, SQL_HANDLE_STMT, commandHandle, "SQLFetch");
            auto row = readRow(isScalar);
            _fetchedRows.enqueue(row);
            continueFetchingCount--;
        }
    }

    final override void doPrepare() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");
        version(profile) debug auto p = PerfFunction.create();

        const sql = executeCommandText(BuildCommandTextState.prepare); // Make sure statement is constructed before doing other tasks

        auto logTimming = canTimeLog() !is null
            ? LogTimming(canTimeLog(), text(forLogInfo(), ".doPrepare()", newline, sql), false, logTimmingWarningDur)
            : LogTimming.init;

        if (!_handle)
            allocateHandle();

        auto commandHandle = msHandle;

        MsConnection.checkSQLResult(SQLPrepare(commandHandle, cast(SQLCHAR*)&sql[0], cast(SQLINTEGER)sql.length),
            SQL_HANDLE_STMT, commandHandle, "SQLPrepare");

        if (!getExecutionPlanning)
            getParameterInfos();
    }

    final override void doUnprepare() @safe
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        if (_handle)
            deallocateHandle();
    }

    static void fillNamedColumn(DbNameColumn column, string name, const ref MsDescribeInfo info, const(bool) isNew) nothrow @safe
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(name=", name, ", info=", info.traceString(), ")");

        if (name.length)
            column.baseName = name;
        column.baseSize = cast(int32)info.dataSize;
        column.baseTypeId = info.dataType;
        column.baseNumericScale = info.decimalDigits;
        column.allowNull = info.allowNull();
        column.ordinal = info.ordinal;

        if (isNew || column.type == DbType.unknown)
        {
            column.type = info.dbType();
            column.size = info.dbTypeSize();
        }
    }

    final void getFieldInfos() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        auto commandHandle = msHandle;

        SQLSMALLINT odbcNumFields;
		MsConnection.checkSQLResult(SQLNumResultCols(commandHandle, &odbcNumFields),
            SQL_HANDLE_STMT, commandHandle, "SQLNumResultCols");

        auto localFields = fields;

        enum odbcNameMax = 200;
        char[odbcNameMax] odbcName = void;

        // SQLDescribeCol requires based 1 index
        localFields.reserve(odbcNumFields);
		for (SQLSMALLINT i = 1; i <= odbcNumFields; i++)
        {
            odbcName[] = '\0';
            MsDescribeInfo info;
            info.ordinal = i;
			SQLSMALLINT nameLength;
            MsConnection.checkSQLResult(SQLDescribeCol(commandHandle, i, cast(SQLCHAR*)&odbcName[0], odbcNameMax, &nameLength,
                &info.dataType, &info.dataSize, &info.decimalDigits, &info.nullable),
                SQL_HANDLE_STMT, commandHandle, "SQLDescribeCol");

            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "i=", i, ", odbcName=", odbcName[0..nameLength], ", ", info.traceString());

            auto newName = odbcName[0..nameLength].idup;
            auto newField = localFields.create(this, newName);
            fillNamedColumn(newField, newName, info, true);
            localFields.put(newField);
		}
    }

    final void getParameterInfos() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        auto commandHandle = msHandle;

        SQLSMALLINT odbcNumParams;
		MsConnection.checkSQLResult(SQLNumParams(commandHandle, &odbcNumParams),
            SQL_HANDLE_STMT, commandHandle, "SQLNumParams");

        auto localParameters = parameters;

        // SQLDescribeParam  requires based 1 index
        localParameters.reserve(odbcNumParams);
		for (SQLSMALLINT i = 1; i <= odbcNumParams; i++)
        {
            MsDescribeInfo info;
            info.ordinal = i;
            MsConnection.checkSQLResult(SQLDescribeParam(commandHandle, i,
                &info.dataType, &info.dataSize, &info.decimalDigits, &info.nullable),
                SQL_HANDLE_STMT, commandHandle, "SQLDescribeParam ");

            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "i=", i, ", ", info.traceString());

            const isNew = i > localParameters.length;
            auto parameter = isNew
                ? localParameters.create(localParameters.generateName())
                : localParameters[i - 1];
            fillNamedColumn(parameter, null, info, isNew);
            if (isNew)
                localParameters.put(parameter);
		}
    }

    final void readOutputParameters() @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        auto commandHandle = msHandle;
        foreach (parameter; parameters)
        {
            auto msParam = cast(MsParameter)parameter;

            enum outputOnly = false;
            if (!msParam.isOutput(outputOnly))
                continue;

            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "name=", msParam.name);

            if (msParam.bindData.isNullData())
            {
                msParam.value.nullify();
                continue;
            }

            if (msParam.bindData.hasMoreData())
            {
                Appender!(ubyte[]) buffer;
                buffer.reserve(msParam.bindData.strLenOrInd);
                buffer.put(msParam.bindData.getBufferData());
                do
                {
                    auto bindData = msParam.bindData.resetData();
                    const r = SQLGetData(commandHandle, cast(SQLUSMALLINT)msParam.ordinal,
                        bindData.targetType, bindData.targetValuePtr, bindData.targetLength, bindData.strLenOrIndPtr);
                    if (r == SQL_NO_DATA)
                        break;
                    MsConnection.checkSQLResult(r, SQL_HANDLE_STMT, commandHandle, "SQLGetData");
                    if (!msParam.bindData.isNullData())
                        buffer.put(msParam.bindData.getBufferData());
                }
                while (msParam.bindData.hasMoreData());
                if (msParam.bindData.isStringData())
                    msParam.value = DbValue(cast(string)buffer.data);
                else
                    msParam.value = DbValue(buffer.data);
            }
            else
                msParam.value = msParam.bindData.getData();
        }
    }

    final DbRowValue readRow(const(bool) isScalar) @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(isScalar=", isScalar, ")");

        auto commandHandle = msHandle;
        auto result = DbRowValue(fields.length);
        foreach (i; 0..fields.length)
        {
            auto msField = cast(MsField)fields[i];

            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "name=", msField.name);

            auto bindData = msField.bindData.resetData();
            const r = SQLGetData(commandHandle, cast(SQLUSMALLINT)msField.ordinal,
                bindData.targetType, bindData.targetValuePtr, bindData.targetLength, bindData.strLenOrIndPtr);
            if (r == SQL_NO_DATA)
            {
                result[i].nullify();
                continue;
            }
            MsConnection.checkSQLResult(r, SQL_HANDLE_STMT, commandHandle, "SQLGetData");

            if (msField.bindData.isNullData())
            {
                result[i].nullify();
                continue;
            }

            if (msField.bindData.hasMoreData())
            {
                Appender!(ubyte[]) buffer;
                buffer.reserve(msField.bindData.strLenOrInd);
                buffer.put(msField.bindData.getBufferData());
                do
                {
                    bindData = msField.bindData.resetData();
                    const r2 = SQLGetData(commandHandle, cast(SQLUSMALLINT)msField.ordinal,
                        bindData.targetType, bindData.targetValuePtr, bindData.targetLength, bindData.strLenOrIndPtr);
                    if (r2 == SQL_NO_DATA)
                        break;
                    MsConnection.checkSQLResult(r2, SQL_HANDLE_STMT, commandHandle, "SQLGetData");
                    if (!msField.bindData.isNullData())
                        buffer.put(msField.bindData.getBufferData());
                }
                while (msField.bindData.hasMoreData());
                if (msField.bindData.isStringData())
                    result[i] = DbValue(cast(string)buffer.data);
                else
                    result[i] = DbValue(buffer.data);
            }
            else
                result[i] = msField.bindData.getData();
        }

        return result;
    }

    final T getCommandIntAttr(T = int)(const(SQLINTEGER) attrb, const(T) invalid = 0) nothrow @trusted
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) || is(T == short) || is(T == ushort))
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto commandHandle = msHandle;
        SQLINTEGER dummy;
        T result;
        const r = SQLGetStmtAttr(commandHandle, attrb, cast(SQLPOINTER)&result, T.sizeof, &dummy);
        return isSuccessResult2(r) ? result : invalid;
    }

    final void setCommandIntAttr(T = int)(const(SQLINTEGER) attrb, const(T) value) @trusted
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) || is(T == short) || is(T == ushort))
    {
        auto commandHandle = msHandle;
        MsConnection.checkSQLResult(SQLSetStmtAttr(commandHandle, attrb, cast(SQLPOINTER)value, 0),
            SQL_HANDLE_STMT, commandHandle, "SQLSetStmtAttr");
    }

protected:
    DbNotificationMessage planInfo;
}

class MsConnection : DbConnection
{
public:
    this(MsDatabase database) nothrow @safe
    {
        super(database);
    }

    this(MsDatabase database, string connectionString) @safe
    {
        super(database, connectionString);
    }

    this(MsDatabase database, MsConnectionStringBuilder connectionString) nothrow @safe
    {
        super(database, connectionString);
    }

    this(MsDatabase database, DbURL!string connectionString) @safe
    {
        super(database, connectionString);
    }

    final override DbCancelCommandData createCancelCommandData(DbCommand command) @safe
    {
        return new MsCancelCommandData(cast(MsCommand)command);
    }

    @property final MsConnectionStringBuilder msConnectionStringBuilder() nothrow pure @safe
    {
        return cast(MsConnectionStringBuilder)connectionStringBuilder;
    }

    @property final SQLHDBC msHandle() nothrow pure @trusted
    {
        return cast(SQLHDBC)_handle.get!size_t;
    }

    @property final override DbScheme scheme() const nothrow pure @safe
    {
        return DbScheme.ms;
    }

    @property final override bool supportMultiReaders() nothrow @safe
    {
        return msConnectionStringBuilder.marsConnection;
    }

protected:
    static DbNotificationMessage checkSQLResult(const(SQLRETURN) r, const(SQLSMALLINT) hType, SQLHANDLE hValue, string apiName,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        if (isSuccessResult1(r))
            return DbNotificationMessage.init;

        auto resultStatuses = readResultStatuses(r, hType, hValue, apiName);
        size_t errorIndex;
        final switch (resultStatuses.getStatus(errorIndex))
        {
            case MsResultKind.error:
                throw new MsException(resultStatuses.values[errorIndex], null, funcName, file, line);
            case MsResultKind.successInfo:
                return resultStatuses.getMessage();
            case MsResultKind.success:
                return DbNotificationMessage.init;
        }
    }

    final override void doCancelCommand(DbCancelCommandData data) @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        auto commandHandle = (cast(MsCancelCommandData)data).commandHandle;
        checkSQLResult(SQLCancel(commandHandle), SQL_HANDLE_STMT, commandHandle, "SQLCancel");
    }

    final override void doClose(bool failedOpen) @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(failedOpen=", failedOpen, ")");

        if (_handle)
        {
            auto h = cast(SQLHDBC)_handle.get!size_t;
            if (!failedOpen)
                SQLDisconnect(h);
            SQLFreeHandle(SQL_HANDLE_DBC, h);
            _handle.reset();
        }

        if (_envHandle)
        {
            auto h = cast(SQLHENV)_envHandle.get!size_t;
            SQLFreeHandle(SQL_HANDLE_ENV, h);
            _envHandle.reset();
        }
    }

    final override void doOpen() @trusted
    {
        auto useCSB = msConnectionStringBuilder;

        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(odbcConnectionString=", useCSB.odbcConnectionString(), ")");

        SQLHENV hEnv;
        checkSQLResult(SQLAllocHandle(SQL_HANDLE_ENV, cast(SQLPOINTER)SQL_NULL_HANDLE, &hEnv),
            SQL_HANDLE_ENV, hEnv, "SQLAllocHandle");
        scope (failure)
            SQLFreeHandle(SQL_HANDLE_ENV, hEnv);

        checkSQLResult(SQLSetEnvAttr(hEnv, SQL_ATTR_ODBC_VERSION, cast(SQLPOINTER)SQL_OV_ODBC3, SQL_IS_UINTEGER),
            SQL_HANDLE_ENV, hEnv, "SQLSetEnvAttr");

        SQLHDBC hCon;
		checkSQLResult(SQLAllocHandle(SQL_HANDLE_DBC, hEnv, &hCon), SQL_HANDLE_DBC, hCon, "SQLAllocHandle");
        scope (failure)
            SQLFreeHandle(SQL_HANDLE_DBC, hCon);

        auto connectionTimeout = useCSB.connectionTimeout;
        auto odbcConnectionTimeout = cast(SQLUINTEGER)connectionTimeout.total!"seconds";
        if (odbcConnectionTimeout == 0 && connectionTimeout != Duration.zero)
            odbcConnectionTimeout = 1;
        if (odbcConnectionTimeout)
        {
            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "odbcConnectionTimeout=", odbcConnectionTimeout);
            SQLSetConnectAttr(hCon, SQL_ATTR_CONNECTION_TIMEOUT, cast(SQLPOINTER)odbcConnectionTimeout, SQL_IS_UINTEGER);
            SQLSetConnectAttr(hCon, SQL_ATTR_LOGIN_TIMEOUT, cast(SQLPOINTER)odbcConnectionTimeout, SQL_IS_UINTEGER);
        }

        auto odbcPackageSize = cast(SQLUINTEGER)useCSB.packageSize;
        if (odbcPackageSize)
        {
            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "odbcPackageSize=", odbcPackageSize);
            SQLSetConnectAttr(hCon, SQL_ATTR_PACKET_SIZE, cast(SQLPOINTER)odbcPackageSize, SQL_IS_UINTEGER);
        }

        const odbcConnectionString = useCSB.odbcConnectionString();
        checkSQLResult(SQLDriverConnect(hCon, null, cast(SQLCHAR*)&odbcConnectionString[0], cast(SQLSMALLINT)odbcConnectionString.length, null, 0, null, SQL_DRIVER_NOPROMPT),
            SQL_HANDLE_DBC, hCon, "SQLDriverConnect");

        _envHandle = DbHandle(cast(size_t)hEnv);
        _handle = DbHandle(cast(size_t)hCon);
    }

    final override string getServerVersion() @trusted
    {
        import pham.utl.utl_result : osCharToString;

        char[100] buffer = '\0';
        SQLSMALLINT bufferLen = 0;
        SQLGetInfo(msHandle, SQL_DBMS_VER, &buffer[0], cast(SQLSMALLINT)buffer.length, &bufferLen);
        return bufferLen ? osCharToString(buffer[0..bufferLen]) : null;
    }

    static MsResultStatusArray readResultStatuses(const(SQLRETURN) r, const(SQLSMALLINT) hType, SQLHANDLE hValue, string apiName) nothrow @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(r=", r, ", apiName=", apiName, ")");

        scope (failure) assert(0, "Assume nothrow failed");

        MsResultStatusArray result;

        char[SQL_MAX_MESSAGE_LENGTH_NULL] sqlErrorText = void;
        char[SQL_SQLSTATE_SIZE_NULL] sqlState = void;
        SQLINTEGER sqlErrorCode = void;
        SQLSMALLINT sqlErrorTextLength = void;

        SQLLEN diagCount = 0;
        SQLGetDiagField(hType, hValue, 0, SQL_DIAG_NUMBER, &diagCount, 0, null);

        debug(debug_pham_db_db_msdatabase) debug writeln("\t", "diagCount=", diagCount);

        SQLSMALLINT diagNumber = 1;
        while (diagNumber <= diagCount)
        {
            sqlErrorText[] = '\0';
            sqlState[] = '\0';
            sqlErrorCode = 0;
            sqlErrorTextLength = 0;

            if (SQLGetDiagRec(hType, hValue, diagNumber, cast(SQLCHAR*)&sqlState[0], &sqlErrorCode,
                cast(SQLCHAR*)&sqlErrorText[0], SQL_MAX_MESSAGE_LENGTH, &sqlErrorTextLength) == SQL_NO_DATA)
                break;

            const i = result.length;
            result.values[i].apiName = apiName;
            result.values[i].resultCode = r;
            result.values[i].sqlErrorCode = sqlErrorCode;
            result.values[i].state = osCharToString(sqlState[]);
            result.values[i].sqlErrorMessage = osCharToString(sqlErrorText[0..sqlErrorTextLength]);

            debug(debug_pham_db_db_msdatabase) debug writeln("\t", "state=", result.values[i].state, ", sqlErrorCode=",
                result.values[i].sqlErrorCode, ", sqlErrorMessage=", result.values[i].sqlErrorMessage);

            if (++result.length == result.max)
                break;

            diagNumber++;
        }

        if (result.length == 0 && (r == SQL_ERROR || r == SQL_INVALID_HANDLE))
        {
            result.values[0].apiName = apiName;
            result.values[0].resultCode = r;
            result.values[0].sqlErrorMessage = genericErrorMessage(apiName, r);
            result.length++;
        }

        return result;
    }

    final T getConnectIntAttr(T = int)(const(SQLINTEGER) attrb, const(T) invalid = 0) nothrow @trusted
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) || is(T == short) || is(T == ushort))
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto connectHandle = msHandle;
        SQLINTEGER dummy;
        T result;
        const r = SQLGetConnectAttr(connectHandle, attrb, cast(SQLPOINTER)&result, T.sizeof, &dummy);
        return isSuccessResult2(r) ? result : invalid;
    }

    final void setConnectIntAttr(T = int)(const(SQLINTEGER) attrb, const(T) value) @trusted
    if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) || is(T == short) || is(T == ushort))
    {
        auto connectHandle = msHandle;
        checkSQLResult(SQLSetConnectAttr(connectHandle, attrb, cast(SQLPOINTER)value, 0),
            SQL_HANDLE_DBC, connectHandle, "SQLSetConnectAttr");
    }

protected:
    DbHandle _envHandle;
}

class MsConnectionStringBuilder : DbConnectionStringBuilder
{
@safe:

public:
    this(DbDatabase database) nothrow
    {
        super(database);
    }

    this(DbDatabase database, string connectionString)
    {
        super(database, connectionString);
    }

    static immutable string[2] odbcBoolTexts = ["no", "yes"];
    static immutable string[DbEncryptedConnection.max + 1] odbcEncryptTexts = ["no", "yes", "strict"];
    final string odbcConnectionString() const nothrow
    {
        Appender!string buffer;
        string v;
        uint counter;

        void appendValue(string n, string v) nothrow @safe
        {
            if (counter != 0)
                buffer.put(';');

            buffer.put(n);
            buffer.put('=');
            buffer.put(v);
            counter++;
        }

        if (hasValue(DbConnectionParameterIdentifier.msDriver, v))
            appendValue(DbConnectionParameterIdentifier.msDriver, v);

        if (hasValue(DbConnectionParameterIdentifier.serverName, v))
        {
            if (auto p = serverPort)
                v = "tcp:" ~ v ~ "," ~ p.to!string;
            appendValue(DbConnectionParameterIdentifier.serverName, v);
        }

        if (hasValue(DbConnectionParameterIdentifier.databaseName, v))
            appendValue(DbConnectionParameterIdentifier.databaseName, v);

        v = userName;
        if (v.length)
        {
            appendValue(DbConnectionParameterIdentifier.msUID, v);

            v = userPassword;
            if (v.length)
                appendValue(DbConnectionParameterIdentifier.msPWD, v);
        }

        if (hasValue(DbConnectionParameterIdentifier.msAddress, v))
            appendValue(DbConnectionParameterIdentifier.msAddress, v);

        v = applicationName;
        if (v.length)
            appendValue(DbConnectionParameterIdentifier.msApplicationName, v);

        if (hasValue(DbConnectionParameterIdentifier.msApplicationIntent, v))
            appendValue(DbConnectionParameterIdentifier.msApplicationIntent, v);

        v = databaseFileName;
        if (v.length)
            appendValue(DbConnectionParameterIdentifier.msAttachDBFileName, v);

        if (hasValue(DbConnectionParameterIdentifier.msAutoTranslate, v))
            appendValue(DbConnectionParameterIdentifier.msAutoTranslate, odbcBoolTexts[isDbTrue(v)]);

        if (hasValue(DbConnectionParameterIdentifier.msDSN, v))
            appendValue(DbConnectionParameterIdentifier.msDSN, v);

        appendValue(DbConnectionParameterIdentifier.encrypt, odbcEncryptTexts[encrypt]);

        if (hasValue(DbConnectionParameterIdentifier.msFailoverPartner, v))
            appendValue(DbConnectionParameterIdentifier.msFailoverPartner, v);

        if (hasValue(DbConnectionParameterIdentifier.msFileDSN, v))
            appendValue(DbConnectionParameterIdentifier.msFileDSN, v);

        if (hasValue(DbConnectionParameterIdentifier.msLanguage, v))
            appendValue(DbConnectionParameterIdentifier.msLanguage, v);

        if (hasValue(DbConnectionParameterIdentifier.msMARSConnection, v))
            appendValue(DbConnectionParameterIdentifier.msMARSConnection, odbcBoolTexts[isDbTrue(v)]);

        if (hasValue(DbConnectionParameterIdentifier.msMultiSubnetFailover, v))
            appendValue(DbConnectionParameterIdentifier.msMultiSubnetFailover, odbcBoolTexts[isDbTrue(v)]);

        if (hasValue(DbConnectionParameterIdentifier.msNetwork, v))
            appendValue(DbConnectionParameterIdentifier.msNetwork, v);

        if (hasValue(DbConnectionParameterIdentifier.msQueryLogOn, v))
            appendValue(DbConnectionParameterIdentifier.msQueryLogOn, odbcBoolTexts[isDbTrue(v)]);

        if (hasValue(DbConnectionParameterIdentifier.msQueryLogFile, v))
            appendValue(DbConnectionParameterIdentifier.msQueryLogFile, v);

        if (hasValue(DbConnectionParameterIdentifier.msQueryLogTime, v))
        {
            Duration d;
            cvtConnectionParameterDuration(d, v);
            if (d != Duration.zero)
                appendValue(DbConnectionParameterIdentifier.msQueryLogTime, d.total!"msecs"().to!string);
        }

        if (hasValue(DbConnectionParameterIdentifier.msQuotedId, v))
            appendValue(DbConnectionParameterIdentifier.msQuotedId, odbcBoolTexts[isDbTrue(v)]);

        if (hasValue(DbConnectionParameterIdentifier.msRegional, v))
            appendValue(DbConnectionParameterIdentifier.msRegional, odbcBoolTexts[isDbTrue(v)]);

        appendValue(DbConnectionParameterIdentifier.msTrustedConnection, odbcBoolTexts[integratedSecurity == DbIntegratedSecurityConnection.sspi]);

        if (hasValue(DbConnectionParameterIdentifier.msTrustServerCertificate, v))
            appendValue(DbConnectionParameterIdentifier.msTrustServerCertificate, odbcBoolTexts[isDbTrue(v)]);

        if (hasCustomValue(DbConnectionCustomIdentifier.currentComputerName, v))
            appendValue(DbConnectionParameterIdentifier.msWSID, v);

        return buffer.data;
    }

    final override const(string[]) parameterNames() const nothrow
    {
        return msValidConnectionParameterNames;
    }

    @property final string address() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msAddress);
    }

    @property final typeof(this) address(string value)
    {
        auto k = DbConnectionParameterIdentifier.msAddress in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msAddress, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msAddress, value);
    }

    @property final string attachDBFileName() const nothrow
    {
        return databaseFileName;
    }

    @property final typeof(this) attachDBFileName(string value)
    {
        databaseFileName = value;
        return this;
    }

    @property final bool autoTranslate() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.msAutoTranslate));
    }

    @property final typeof(this) autoTranslate(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.msAutoTranslate, s);
        return this;
    }

    @property final string driver() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msDriver);
    }

    @property final typeof(this) driver(string value)
    {
        auto k = DbConnectionParameterIdentifier.msDriver in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msDriver, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msDriver, value);
    }

    @property final string DSN() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msDSN);
    }

    @property final typeof(this) DSN(string value)
    {
        auto k = DbConnectionParameterIdentifier.msDSN in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msDSN, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msDSN, value);
    }

    @property final string failoverPartner() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msFailoverPartner);
    }

    @property final typeof(this) failoverPartner(string value)
    {
        auto k = DbConnectionParameterIdentifier.msFailoverPartner in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msFailoverPartner, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msFailoverPartner, value);
    }

    @property final string fileDSN() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msFileDSN);
    }

    @property final typeof(this) fileDSN(string value)
    {
        auto k = DbConnectionParameterIdentifier.msFileDSN in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msFileDSN, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msFileDSN, value);
    }

    @property final string language() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msLanguage);
    }

    @property final typeof(this) language(string value)
    {
        auto k = DbConnectionParameterIdentifier.msLanguage in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msLanguage, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msLanguage, value);
    }

    @property final bool marsConnection() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.msMARSConnection));
    }

    @property final typeof(this) marsConnection(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.msMARSConnection, s);
        return this;
    }

    @property final bool multiSubnetFailover() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.msMultiSubnetFailover));
    }

    @property final typeof(this) multiSubnetFailover(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.msMultiSubnetFailover, s);
        return this;
    }

    @property final string network() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msNetwork);
    }

    @property final typeof(this) network(string value)
    {
        auto k = DbConnectionParameterIdentifier.msNetwork in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msNetwork, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msNetwork, value);
    }

    @property final string PWD() const nothrow
    {
        return userPassword;
    }

    @property final typeof(this) PWD(string value)
    {
        userPassword = value;
        return this;
    }

    @property final bool queryLogOn() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.msQueryLogOn));
    }

    @property final typeof(this) queryLogOn(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.msQueryLogOn, s);
        return this;
    }

    @property final Duration queryLogTime() const nothrow
    {
        Duration result;
        cvtConnectionParameterDuration(result, getString(DbConnectionParameterIdentifier.msQueryLogTime));
        return result;
    }

    @property final typeof(this) queryLogTime(scope const(Duration) value)
    {
        auto s = cvtConnectionParameterDuration(value);
        auto k = DbConnectionParameterIdentifier.msQueryLogTime in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(s) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msQueryLogTime, s);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msQueryLogTime, value.toString());
    }

    @property final bool quotedId() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.msQuotedId));
    }

    @property final typeof(this) quotedId(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.msQuotedId, s);
        return this;
    }

    @property final string regional() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msRegional);
    }

    @property final typeof(this) regional(string value)
    {
        auto k = DbConnectionParameterIdentifier.msRegional in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msRegional, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msRegional, value);
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.ms;
    }

    @property final bool trustedConnection() const nothrow
    {
        return integratedSecurity == DbIntegratedSecurityConnection.sspi;
    }

    @property final typeof(this) trustedConnection(bool value) nothrow
    {
        integratedSecurity = value ? DbIntegratedSecurityConnection.sspi : DbIntegratedSecurityConnection.legacy;
        return this;
    }

    @property final bool trustServerCertificate() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.msTrustServerCertificate));
    }

    @property final typeof(this) trustServerCertificate(bool value) nothrow
    {
        auto s = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.msTrustServerCertificate, s);
        return this;
    }

    @property final string UID() const nothrow
    {
        return userName;
    }

    @property final typeof(this) UID(string value)
    {
        userName = value;
        return this;
    }

    @property final string WSID() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.msWSID);
    }

    @property final typeof(this) WSID(string value)
    {
        auto k = DbConnectionParameterIdentifier.msWSID in dbDefaultConnectionParameterValues;
        assert(k !is null);
        if ((*k).isValidValue(value) == DbNameValueValidated.ok)
        {
            put(DbConnectionParameterIdentifier.msWSID, value);
            return this;
        }
        else
            throwInvalidPropertyValue(DbConnectionParameterIdentifier.msWSID, value);
    }

protected:
    final override string getDefault(string name) const nothrow
    {
        auto k = name in msDefaultConnectionParameterValues;
        return k !is null && (*k).def.length != 0 ? (*k).def : super.getDefault(name);
    }

    final override void setDefaultIfs() nothrow
    {
        foreach (ref dpv; msDefaultConnectionParameterValues.byKeyValue)
        {
            auto def = dpv.value.def;
            if (def.length)
                putIf(dpv.key, def);
        }
        super.setDefaultIfs();
    }
}

class MsDatabase : DbDatabase
{
@safe:

public:
    this() nothrow
    {
        super();
        this._name = DbIdentitier(DbScheme.ms);
        this._identifierQuoteChar = '"';
        this._stringQuoteChar = '\'';

        this._charClasses['"'] = CharClass.quote;
        this._charClasses['\''] = CharClass.quote;
        this._charClasses['\\'] = CharClass.backslash;

        this.populateValidParamNameChecks();
    }

    final override const(string[]) connectionStringParameterNames() const nothrow pure
    {
        return msValidConnectionParameterNames;
    }

    override DbCommand createCommand(DbConnection connection,
        string name = null) nothrow
    in
    {
        assert((cast(MsConnection)connection) !is null);
    }
    do
    {
        return new MsCommand(cast(MsConnection)connection, name);
    }

    override DbCommand createCommand(DbConnection connection, DbTransaction transaction,
        string name = null) nothrow
    in
    {
        assert((cast(MsConnection)connection) !is null);
        assert((cast(MsTransaction)transaction) !is null);
    }
    do
    {
        return new MsCommand(cast(MsConnection)connection, cast(MsTransaction)transaction, name);
    }

    override DbConnection createConnection(string connectionString)
    {
        auto result = new MsConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbConnectionStringBuilder connectionString) nothrow
    in
    {
        assert(connectionString !is null);
        assert(connectionString.scheme == DbScheme.ms);
        assert(cast(MsConnectionStringBuilder)connectionString !is null);
    }
    do
    {
        auto result = new MsConnection(this, cast(MsConnectionStringBuilder)connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbURL!string connectionString)
    in
    {
        assert(DbURL.scheme == DbScheme.ms);
        assert(DbURL.isValid());
    }
    do
    {
        auto result = new MsConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnectionStringBuilder createConnectionStringBuilder() nothrow
    {
        return new MsConnectionStringBuilder(this);
    }

    override DbConnectionStringBuilder createConnectionStringBuilder(string connectionString)
    {
        return new MsConnectionStringBuilder(this, connectionString);
    }

    override DbField createField(DbCommand command, DbIdentitier name) nothrow
    in
    {
        assert((cast(MsCommand)command) !is null);
    }
    do
    {
        return new MsField(cast(MsCommand)command, name);
    }

    override DbFieldList createFieldList(DbCommand command) nothrow
    in
    {
        assert(cast(MsCommand)command !is null);
    }
    do
    {
        return new MsFieldList(cast(MsCommand)command);
    }

    override DbParameter createParameter(DbIdentitier name) nothrow
    {
        return new MsParameter(this, name);
    }

    override DbParameterList createParameterList() nothrow
    {
        return new MsParameterList(this);
    }

    override DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel,
        bool defaultTransaction = false) nothrow
    in
    {
        assert((cast(MsConnection)connection) !is null);
    }
    do
    {
        return new MsTransaction(cast(MsConnection)connection, isolationLevel);
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return DbScheme.ms;
    }
}

class MsField : DbField
{
public:
    this(MsCommand command, DbIdentitier name) nothrow pure @safe
    {
        super(command, name);
    }

    final override DbField createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createField(cast(MsCommand)command, name)
            : new MsField(cast(MsCommand)command, name);
    }

    final override DbFieldIdType isValueIdType() const nothrow pure @safe
    {
        return MsDescribeInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

    @property final MsCommand msCommand() nothrow pure @safe
    {
        return cast(MsCommand)_command;
    }

protected:
    MsMappedDataInfo bindData; // Used with SQLGetData
}

class MsFieldList: DbFieldList
{
public:
    this(MsCommand command) nothrow pure @safe
    {
        super(command);
    }

    final override DbField create(DbCommand command, DbIdentitier name) nothrow @safe
    {
        return database !is null
            ? database.createField(cast(MsCommand)command, name)
            : new MsField(cast(MsCommand)command, name);
    }

    final void nullifyBindDatas() nothrow @safe
    {
        foreach (field; this)
            (cast(MsField)field).bindData.clear();
    }

    @property final MsCommand msCommand() nothrow pure @safe
    {
        return cast(MsCommand)_command;
    }

protected:
    final override DbFieldList createSelf(DbCommand command) nothrow @safe
    {
        return database !is null
            ? database.createFieldList(cast(MsCommand)command)
            : new MsFieldList(cast(MsCommand)command);
    }

    override void resetNewStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        super.resetNewStatement(kind);
        if (kind == ResetStatementKind.fetched)
            nullifyBindDatas();
    }
}

class MsParameter : DbParameter
{
public:
    this(MsDatabase database, DbIdentitier name) nothrow pure @safe
    {
        super(database, name);
    }

    final override DbFieldIdType isValueIdType() const nothrow pure @safe
    {
        return MsDescribeInfo.isValueIdType(baseTypeId, baseSubTypeId);
    }

protected:
    final override void reevaluateBaseType() nothrow @safe
    {
        foreach (ref msType; msNativeTypes)
        {
            if (msType.dbType == _type)
            {
                baseSize = msType.nativeSize;
                baseTypeId = msType.dbId;
                break;
            }
        }
    }

protected:
    MsMappedDataInfo bindData; // Used with SQLBindParameter
}

class MsParameterList : DbParameterList
{
public:
    this(MsDatabase database) nothrow pure @safe
    {
        super(database);
    }

    final void nullifyBindDatas() nothrow @safe
    {
        foreach (parameter; this)
            (cast(MsParameter)parameter).bindData.clear();
    }

protected:
    override void resetNewStatement(const(ResetStatementKind) kind) nothrow @safe
    {
        super.resetNewStatement(kind);
        if (kind == ResetStatementKind.unpreparing)
            nullifyBindDatas();
    }
}

class MsTransaction : DbTransaction
{
public:
    this(MsConnection connection, DbIsolationLevel isolationLevel) nothrow @safe
    {
        super(connection, isolationLevel);
        this.autoCommitState = msConnection.getConnectIntAttr!uint(SQL_ATTR_AUTOCOMMIT);
    }

    @property final MsConnection msConnection() nothrow pure @safe
    {
        return cast(MsConnection)connection;
    }

protected:
    final override string createSavePointStatement(const(DbSavePoint) mode, string savePointName) const @safe nothrow
    in
    {
        assert(savePointName.length > 0);
    }
    do
    {
        final switch (mode)
        {
            case DbSavePoint.start:
                return "SAVE TRANSACTION " ~ savePointName;
            case DbSavePoint.commit:
                return "COMMIT TRANSACTION " ~ savePointName;
            case DbSavePoint.rollback:
                return "ROLLBACK TRANSACTION " ~ savePointName;
        }
    }

    final override void doCommit(bool disposing) @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(disposing=", disposing, ")");

        auto connectHandle = msConnection.msHandle;
        msConnection.checkSQLResult(SQLEndTran(SQL_HANDLE_DBC, connectHandle, SQL_COMMIT),
            SQL_HANDLE_DBC, connectHandle, "SQLEndTran");
        msConnection.setConnectIntAttr!uint(SQL_ATTR_AUTOCOMMIT, this.autoCommitState);
    }

    final override void doRollback(bool disposing) @trusted
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "(disposing=", disposing, ")");

        auto connectHandle = msConnection.msHandle;
        msConnection.checkSQLResult(SQLEndTran(SQL_HANDLE_DBC, connectHandle, SQL_ROLLBACK),
            SQL_HANDLE_DBC, connectHandle, "SQLEndTran");
        msConnection.setConnectIntAttr!uint(SQL_ATTR_AUTOCOMMIT, this.autoCommitState);
    }

    final override void doStart() @safe
    {
        debug(debug_pham_db_db_msdatabase) debug writeln(__FUNCTION__, "()");

        this.autoCommitState = msConnection.getConnectIntAttr!uint(SQL_ATTR_AUTOCOMMIT);
        msConnection.setConnectIntAttr!uint(SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_OFF);
        msConnection.setConnectIntAttr!uint(SQL_ATTR_TXN_ISOLATION, odbcIsolationLevels[isolationLevel]);
    }

protected:
    uint autoCommitState;
}


private:

shared static this() nothrow @safe
{
    auto db = new MsDatabase();
    DbDatabaseList.registerDb(db);
}

version(UnitTestMSDatabase)
{
    MsConnection createTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled)
    {
        auto db = DbDatabaseList.getDb(DbScheme.ms);
        assert(cast(MsDatabase)db !is null);

        auto result = db.createConnection("");
        assert(cast(MsConnection)result !is null);

        auto csb = (cast(MsConnection)result).msConnectionStringBuilder;
        assert(csb.userName == "sa"); // Default check before change

        csb.serverName = "An-WorkPC10\\sql2019"; //"localhost"
        //csb.serverPort = 64_267; // Instance setup uses dynamic port, so avoid setting port including the default value
        csb.databaseName = "test";
        csb.userName = "test";
        csb.userPassword = "masterkey";
        csb.receiveTimeout = dur!"seconds"(20);
        csb.sendTimeout = dur!"seconds"(10);
        csb.encrypt = encrypt;

        assert(csb.serverName == "An-WorkPC10\\sql2019"); //"localhost");
        assert(csb.databaseName == "test");
        assert(csb.userName == "test");
        assert(csb.userPassword == "masterkey");
        assert(csb.receiveTimeout == dur!"seconds"(20));
        assert(csb.sendTimeout == dur!"seconds"(10));
        assert(csb.encrypt == encrypt);

        return cast(MsConnection)result;
    }

    string testStoredProcedureSchema() nothrow pure @safe
    {
        return q"{
CREATE PROCEDURE MULTIPLE_BY (
  @x int,
  @y int OUTPUT,
  @z float OUTPUT)
AS
BEGIN
  SET NOCOUNT ON;
  SET @y = @x * 2;
  SET @z = @y * 2;
END
}";
    }

    string testTableSchema() nothrow pure @safe
    {
        return q"{
CREATE TABLE test_select (
  int_field int NOT NULL,
  smallint_field smallint,
  float_field real,
  double_field float,
  numeric_field numeric(15,2),
  decimal_field decimal(15,2),
  date_field date,
  time_field time,
  timestamp_field datetime2,
  char_field char(10),
  varchar_field varchar(10),
  blob_field image,
  text_field text,
  bigint_field bigint)
}";
    }

    string testTableData() nothrow pure @safe
    {
        return q"{
INSERT INTO test_select (int_field, smallint_field, float_field, double_field, numeric_field, decimal_field, date_field, time_field, timestamp_field, char_field, varchar_field, blob_field, text_field, bigint_field)
VALUES (1, 2, 3.1, 4.2, 5.40, 6.50, '2020-05-20', '01:01:01', '2020-05-20 07:31:00', 'ABC       ', 'XYZ', NULL, 'TEXT', 4294967296)
}";
    }

    string simpleSelectCommandText() nothrow pure @safe
    {
        return q"{
SELECT INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD,
    NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD,
    CHAR_FIELD, VARCHAR_FIELD, BLOB_FIELD, TEXT_FIELD, BIGINT_FIELD
FROM TEST_SELECT
WHERE INT_FIELD = 1
}";
    }

    string parameterSelectCommandText() nothrow pure @safe
    {
        return q"{
SELECT INT_FIELD, SMALLINT_FIELD, FLOAT_FIELD, DOUBLE_FIELD,
	NUMERIC_FIELD, DECIMAL_FIELD, DATE_FIELD, TIME_FIELD, TIMESTAMP_FIELD,
	CHAR_FIELD, VARCHAR_FIELD, BLOB_FIELD, TEXT_FIELD, BIGINT_FIELD
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
            debug(debug_pham_db_db_msdatabase) debug writeln("unittest pham.db.db_msdatabase.MsCommand.DML.checking - count: ", count);

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

            assert(reader.getValue(7) == DbTime(1, 1, 1));
            assert(reader.getValue("TIME_FIELD") == DbTime(1, 1, 1));

            assert(reader.getValue(8) == DbDateTime(2020, 5, 20, 7, 31, 0));
            assert(reader.getValue("TIMESTAMP_FIELD") == DbDateTime(2020, 5, 20, 7, 31, 0));

            assert(reader.getValue(9) == "ABC       ", "'" ~ reader.getValue(9).toString() ~ "'");
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

unittest // MsConnectionStringBuilder
{
    auto db = cast(MsDatabase)DbDatabaseList.getDb(DbScheme.ms);
    auto connectionString = new MsConnectionStringBuilder(db);
    assert(connectionString.odbcConnectionString().length > 0);
}

version(UnitTestMSDatabase)
unittest // MsConnection
{
    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    assert(connection.state == DbConnectionState.closed);

    connection.open();
    assert(connection.state == DbConnectionState.opened);

    connection.close();
    assert(connection.state == DbConnectionState.closed);
}

version(UnitTestMSDatabase)
unittest // MsConnection.serverVersion
{
    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    debug(debug_pham_db_db_msdatabase) debug writeln("MsConnection.serverVersion=", connection.serverVersion);
    assert(connection.serverVersion.length > 0);
}

version(UnitTestMSDatabase)
unittest // MsTransaction
{
    auto connection = createTestConnection();
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

version(UnitTestMSDatabase)
unittest // MsTransaction.savePoint
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

version(UnitTestMSDatabase)
unittest // MsCommand.DDL
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

version(UnitTestMSDatabase)
unittest // MsCommand.DML - Simple select
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

version(UnitTestMSDatabase)
unittest // MsCommand.DML - Parameter select
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
    command.parameters.add("CHAR_FIELD", DbType.stringFixed).value = "ABC       ";
    command.parameters.add("VARCHAR_FIELD", DbType.stringVary).value = "XYZ";
    auto reader = command.executeReader();
    scope (exit)
        reader.dispose();
    validateSelectCommandTextReader(reader);
}

version(none) // Currently not working
version(UnitTestMSDatabase)
unittest // MsCommand.getExecutionPlan
{
    import std.stdio : writeln;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandText = simpleSelectCommandText();
    auto planDefault = command.getExecutionPlan();
    writeln("planDefault=", planDefault);
    //auto expectedDefault =
}

version(UnitTestMSDatabase)
unittest // MsCommand.DML.StoredProcedure
{
    import std.conv : to;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    version(none) // TODO
    {
        debug(debug_pham_db_db_msdatabase) debug writeln("Get information");

        auto info = connection.getStoredProcedureInfo("multiple_by");
        assert(info !is null);
        assert(info.argumentTypes.length == 3, info.argumentTypes.length.to!string);
        assert(info.argumentTypes[0].name == "X");
        assert(info.argumentTypes[0].direction == DbParameterDirection.input);
        assert(info.argumentTypes[1].name == "Y");
        assert(info.argumentTypes[1].direction == DbParameterDirection.output);
        assert(info.argumentTypes[2].name == "Z");
        assert(info.argumentTypes[2].direction == DbParameterDirection.output);
    }

    {
        debug(debug_pham_db_db_msdatabase) debug writeln("Execute procedure");

        auto command = connection.createCommand();
        scope (exit)
            command.dispose();

        command.commandStoredProcedure = "multiple_by";
        command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
        command.parameters.add("Y", DbType.int32, DbParameterDirection.output).value = 100;
        command.parameters.add("Z", DbType.float64, DbParameterDirection.output);
        command.executeNonQuery();
        assert(command.parameters.get("Y").variant == 4);
        assert(command.parameters.get("Z").variant == 8.0);
    }
}

version(UnitTestMSDatabase)
unittest // MsCommand.DML.StoredProcedure & Parameter select
{
    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    auto command = connection.createCommand();
    scope (exit)
        command.dispose();

    command.commandStoredProcedure = "multiple_by";
    command.parameters.add("X", DbType.int32, DbParameterDirection.input).value = 2;
    command.parameters.add("Y", DbType.int32, DbParameterDirection.output).value = 100;
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

version(UnitTestMSDatabase)
unittest // MsConnection.DML.execute...
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
