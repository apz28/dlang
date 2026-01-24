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

module pham.db.db_pgprotocol;

import std.algorithm.comparison : max, min;
import std.ascii : LetterCase;
import std.conv : to;
import std.string : indexOf, lastIndexOf, representation;
import std.system : Endian;
import std.traits : Unqual;

debug(debug_pham_db_db_pgprotocol) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_enum_set : toName;
import pham.utl.utl_result : ResultCode;
import pham.utl.utl_text : shortClassName;
import pham.db.db_buffer;
import pham.db.db_database : DbNamedColumn;
import pham.db.db_message;
import pham.db.db_object;
import pham.db.db_type;
import pham.db.db_value;
import pham.db.db_pgauth;
import pham.db.db_pgbuffer;
import pham.db.db_pgdatabase;
import pham.db.db_pgexception;
import pham.db.db_pgoid;
import pham.db.db_pgtype;

struct PgConnectingStateInfo
{
nothrow @safe:

    PgAuth auth;
    CipherBuffer!ubyte authData;
    const(char)[] authMethod;
    int32 authType;
    int32 serverProcessId;
    int32 serverSecretKey;
    int nextAuthState;
    DbEncryptedConnection canCryptedConnection;
    char trStatus;
}

class PgProtocol : DbDisposableObject
{
@safe:

public:
    this(PgConnection connection) nothrow pure
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln("**********");

        this._connection = connection;
    }

    final PgOIdRowDescription bindCommandParameterRead(PgCommand command)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

    receiveAgain:
        auto reader = PgReader(connection);
        switch (reader.messageType)
        {
            case '2': // BindComplete
            case '3': // CloseComplete
                goto receiveAgain;

            case 'T': // RowDescription (response to Describe)
                return readRowDescription(reader);

            case 'n': // NoData (response to Describe)
                return PgOIdRowDescription.init;

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                writeSignal(PgOIdDescribeType.sync);
                throw new PgException(EResponse);

            case 'N': // NoticeResponse
                auto NResponse = readGenericResponse(reader);
                NResponse.getWarn(command.notificationMessages);
                goto receiveAgain;

            /*
            case 'A': // NotificationResponse
                auto AResponse = readNotificationResponse(reader);
                goto receiveAgain;
            */

            default:
                goto receiveAgain;
        }
    }

    final void bindCommandParameterWrite(PgCommand command)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto inputParameters = command.pgInputParameters();

        auto writer = PgWriter(connection);
        // Close previous cursor
        if (command.executedCount > 1)
            writeCloseMessage(writer, PgOIdDescribeType.portal, command.name);
        writeBindMessage(writer, command, inputParameters);
        writeDescribeMessage(writer, command);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final void cancelRequestWrite(int32 serverProcessId, int32 serverSecretKey)
    {
        cancelRequestWrite(serverProcessId, serverSecretKey, 1234 << 16 | 5678);
    }

    final void connectAuthenticationRead(ref PgConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

    receiveAgain:
        auto reader = PgReader(connection);
        switch (reader.messageType)
        {
            case 'K': // BackendKeyData
                stateInfo.serverProcessId = reader.readInt32();
                stateInfo.serverSecretKey = reader.readInt32();
                connection.serverInfo[DbServerIdentifier.protocolProcessId] = stateInfo.serverProcessId.to!string();
                connection.serverInfo[DbServerIdentifier.protocolSecretKey] = stateInfo.serverSecretKey.to!string();
                goto receiveAgain;

            case 'R': // AuthenticationXXXX
                stateInfo.authType = reader.readInt32();
                debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "authType=", stateInfo.authType);
                switch (stateInfo.authType)
                {
                    case 0: // authentication successful, now wait for another messages
                        goto receiveAgain;

                    case 3: // clear-text password is required
                        stateInfo.authMethod = pgAuthClearTextName;
                        stateInfo.authData = null;
                        stateInfo.nextAuthState = 0;
                        connectAuthenticationProcess(stateInfo, null);
                        goto receiveAgain;

                    case 5: // MD5
                        stateInfo.authMethod = pgAuthMD5Name;
                        stateInfo.authData = null;
                        stateInfo.nextAuthState = 0;
                        const md5Salt = reader.readBytes(4);
                        connectAuthenticationProcess(stateInfo, md5Salt);
                        goto receiveAgain;

                    case 10: // HMAC - SCRAM-SHA-256
                        stateInfo.authMethod = pgAuthScram256Name;
                        stateInfo.authData = null;
                        stateInfo.nextAuthState = 0;
                        connectAuthenticationProcess(stateInfo, null);
                        goto receiveAgain;

                    case 11: // HMAC - SCRAM-SHA-256 - Send proof
                        const continuePayload = reader.readBytes(reader.messageLength - int32.sizeof); // Exclude type type indicator size
                        stateInfo.nextAuthState = 1;
                        connectAuthenticationProcess(stateInfo, continuePayload);
                        goto receiveAgain;

                    case 12: // HMAC - SCRAM-SHA-256 - Verification
                        const verifyPayload = reader.readBytes(reader.messageLength - int32.sizeof); // Exclude type type indicator size
                        stateInfo.nextAuthState = 2;
                        connectAuthenticationProcess(stateInfo, verifyPayload);
                        goto receiveAgain;

                    default: // non supported authentication type, close connection
                        auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(stateInfo.authType.to!string());
                        throw new PgException(DbErrorCode.read, msg);
                }

            case 'S': // ParameterStatus
                const name = reader.readCString();
                const value = reader.readCString();
                debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "name=", name, ", value=", value);
                connection.serverInfo[name] = value;
                goto receiveAgain;

            case 'Z': // ReadyForQuery
                stateInfo.trStatus = reader.readChar();
                debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "trStatus=", stateInfo.trStatus);
                switch (stateInfo.trStatus) // check for validity
                {
                    case 'E', 'I', 'T':
                        connection.serverInfo[DbServerIdentifier.protocolTrStatus] = stateInfo.trStatus.to!string();
                        break;

                    default:
                        auto msg = DbMessage.eInvalidConnectionStatus.fmtMessage(stateInfo.trStatus.to!string());
                        throw new PgException(DbErrorCode.read, msg);
                }

                // connection is opened and now it's possible to send queries
                return;

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                throw new PgException(EResponse);

            case 'N': // NoticeResponse
                auto NResponse = readGenericResponse(reader);
                NResponse.getWarn(connection.notificationMessages);
                goto receiveAgain;

            /*
            case 'A': // NotificationResponse
                auto AResponse = readNotificationResponse(reader);
                goto receiveAgain;
            */

            default: // unknown message type, ignore it
                goto receiveAgain;
        }
    }

    final void connectAuthenticationWrite(ref PgConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto useCSB = connection.pgConnectionStringBuilder;

        auto writer = PgWriter(connection);
        writer.beginUntypeMessage();
        writer.writeUInt32(PgOIdOther.protocolVersion);
        foreach (n; useCSB.parameterNames)
        {
            string mappedName;
            final switch (canSendParameter(n, mappedName))
            {
                case CanSendParameter.no:
                    break;

                case CanSendParameter.yes:
                    auto yv = useCSB.getValue(n);
                    if (yv.length)
                    {
                        writer.writeCChars(mappedName);
                        writer.writeCChars(yv);
                    }
                    break;

                case CanSendParameter.yesConvert:
                    auto cv = useCSB.getValue(n);
                    //if (cv.length)
                    //    cv = convertConnectionParameter(n, cv);
                    if (cv.length)
                    {
                        writer.writeCChars(mappedName);
                        writer.writeCChars(cv);
                    }
                    break;
            }
        }
		writer.writeChar('\0');
        writer.flush();
    }

    final void connectCheckingSSL(ref PgConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        stateInfo.canCryptedConnection = canCryptedConnection(stateInfo);
        if (stateInfo.canCryptedConnection != DbEncryptedConnection.disabled)
        {
            connectSSLWrite(stateInfo);
            connectSSLRead(stateInfo);
        }
    }

    final void connectSSLRead(ref PgConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto socketBuffer = connection.getSocketReadBuffer();
        auto socketReader = DbValueReader!(Endian.bigEndian)(socketBuffer);
        const messageType = socketReader.readChar();
        switch (messageType)
        {
            case 'N':
                if (stateInfo.canCryptedConnection == DbEncryptedConnection.required)
                {
                    auto msg = DbMessage.eInvalidConnectionRequiredEncryption.fmtMessage(connection.connectionStringBuilder.forErrorInfo);
                    throw new PgException(DbErrorCode.connect, msg);
                }
                break;
            case 'S':
                debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "Bind SSL");
                auto rs = connection.doOpenSSL();
                if (rs.isError)
                {
                    debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "SSL failed code=", rs.errorCode, ", message=", rs.errorMessage);
                    connection.throwConnectError(rs.errorCode, rs.errorMessage);
                }

                connection.serverInfo[DbServerIdentifier.protocolEncrypted] = toName(stateInfo.canCryptedConnection);
                socketBuffer.reset(); // Reset to empty after reading single SSL char
                break;
            default:
                auto msg = DbMessage.eUnhandleStrOperation.fmtMessage(to!string(messageType), "SSLRequest (N or S)");
                throw new PgException(DbErrorCode.connect, msg);
        }
    }

    final void connectSSLWrite(ref PgConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = PgWriter(connection);
        writer.beginUntypeMessage();
        writer.writeInt32(80877103);
        writer.flush();
    }

    final void deallocateCommandRead()
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

    receiveAgain:
        auto reader = PgReader(connection);
        switch (reader.messageType)
        {
            case '3': // CloseComplete
                return;

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                throw new PgException(EResponse);

            /* No need to process on shutdown
            case 'N': // NoticeResponse
                auto NResponse = readGenericResponse(reader);
                NResponse.getWarn(command.notificationMessages);
                goto receiveAgain;
            */

            /*
            case 'A': // NotificationResponse
                auto AResponse = readNotificationResponse(reader);
                goto receiveAgain;
            */

            default:
                goto receiveAgain;
        }
    }

    final void deallocateCommandWrite(PgCommand command)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = PgWriter(connection);
        writeCloseMessage(writer, PgOIdDescribeType.statement, command.name);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final void disconnectWrite()
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        writeSignal(PgOIdDescribeType.disconnect);
    }

    final PgOIdExecuteResult executeCommandRead(PgCommand command, const(DbCommandExecuteType) type, out PgReader reader)
    {
        // Need to return package reader to continue reading row values

        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(type=", type, ")");

        PgOIdExecuteResult result;

	receiveAgain:
        reader = PgReader(connection);
        result.messageType = reader.messageType;

        debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "reader.messageType=", reader.messageType, ", result.messageType=", result.messageType);

		switch (reader.messageType)
        {
            case 'C': // CommandComplete
                auto tag = reader.readCString();
                const b1 = indexOf(tag, ' ');
                if (b1 >= 0)
                {
                    result.dmlName = tag[0..b1].idup;
                    switch (result.dmlName)
                    {
                        case "COPY", "DELETE", "FETCH", "MOVE", "UPDATE":
                            result.recordsAffected = tag[b1 + 1..$].to!long();
                            break;

                        case "INSERT":
                            const b2 = lastIndexOf(tag, ' ');
                            result.oid = tag[b1 + 1..b2].to!int32();
                            result.recordsAffected = tag[b2 + 1..$].to!long();
                            break;

                        case "SELECT":
                            const b2 = lastIndexOf(tag, ' ');
                            if (b2 > b1)
                                result.recordsAffected = tag[b2 + 1..$].to!long();
                            else
                                result.recordsAffected = tag[b1 + 1..$].to!long();
                            break;

                        default: // CREATE TABLE
                            break;
                     }
                }
                else
                    result.dmlName = tag;
                break;

            case 'D': // DataRow - Let the caller to read row result
                break;

            case 'I': // EmptyQueryResponse
                throw new PgException(DbErrorCode.read, DbMessage.eInvalidCommandText);

            case 'Z': // ReadyForQuery - done
                break;

            case 's': // PortalSuspended
                throw new PgException(DbErrorCode.read, DbMessage.eInvalidCommandSuspended);

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                throw new PgException(EResponse);

            case 'N': // NoticeResponse
                auto NResponse = readGenericResponse(reader);
                NResponse.getWarn(command.notificationMessages);
                goto receiveAgain;

            /*
            case 'A': // NotificationResponse
                auto AResponse = readNotificationResponse(reader);
                goto receiveAgain;
            */

            default:
                goto receiveAgain;
        }

        return result;
    }

    final void executeCommandWrite(PgCommand command, const(DbCommandExecuteType) type, int32 fetchRecordCount)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(fetchRecordCount=", fetchRecordCount, ")");

        auto writer = PgWriter(connection);
        writeExecuteMessage(writer, command, fetchRecordCount > 0 ? fetchRecordCount : int32.max);
        writeSignal(writer, PgOIdDescribeType.sync);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final PgOIdFetchResult fetchCommandRead(PgCommand command, ref bool isSuspended, out PgReader reader)
    in
    {
        assert(command.columnCount != 0);
    }
    do
    {
        // Need to return package reader to continue reading row values

        debug(debug_pham_db_db_pgprotocol) { static ulong counter; debug writeln(__FUNCTION__, "() - counter=", ++counter); }

        PgOIdFetchResult result;

	receiveAgain:
        reader = PgReader(connection);
        result.messageType = reader.messageType;
		switch (reader.messageType)
        {
            case 'D': // DataRow - Let caller to read the row result
                break;

            case 'Z': // ReadyForQuery - done
                break;

            case 's': // PortalSuspended
                isSuspended = true;
                goto receiveAgain;

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                throw new PgException(EResponse);

            case 'N': // NoticeResponse
                auto NResponse = readGenericResponse(reader);
                NResponse.getWarn(command.notificationMessages);
                goto receiveAgain;

            /*
            case 'A': // NotificationResponse
                auto AResponse = readNotificationResponse(reader);
                goto receiveAgain;
            */

            default:
                goto receiveAgain;
        }

        return result;
    }

    final void prepareCommandRead(PgCommand command)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

	receiveAgain:
        auto reader = PgReader(connection);
		switch (reader.messageType)
        {
            case '1': // ParseComplete
                return;

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                writeSignal(PgOIdDescribeType.sync);
                throw new PgException(EResponse);

            case 'N': // NoticeResponse
                auto NResponse = readGenericResponse(reader);
                NResponse.getWarn(command.notificationMessages);
                goto receiveAgain;

            /*
            case 'A': // NotificationResponse
                auto AResponse = readNotificationResponse(reader);
                goto receiveAgain;
            */

            default:
                goto receiveAgain;
        }
    }

    final void prepareCommandWrite(PgCommand command, scope const(char)[] sql)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(sql=", sql, ")");

        auto inputParameters = command.pgInputParameters();

        auto writer = PgWriter(connection);
        writeParseMessage(writer, command, sql, inputParameters);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final PgOIdRowDescription readRowDescription(ref PgReader reader)
    {
        const count = reader.readInt16();
        PgOIdRowDescription result;
        if (count == 0)
            return result;

        result.columns = new PgOIdColumnInfo[](count);
        foreach (i; 0..count)
        {
            result.columns[i].name = reader.readCString();
            result.columns[i].tableOid = reader.readOId();
            result.columns[i].ordinal = reader.readInt16();
            result.columns[i].type = reader.readOId();
            result.columns[i].size = reader.readInt16();
            result.columns[i].modifier = reader.readOId();
            result.columns[i].formatCode = reader.readInt16();
        }
        return result;
    }

    final DbValue readValue(ref PgReader reader, DbNamedColumn column, size_t row, const(int32) valueLength)
    in
    {
        assert(valueLength != pgNullValueLength);
    }
    do
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(", column.traceString(), ", row=", row, ", valueLength=", valueLength, ")");
        version(profile) debug auto p = PerfFunction.create();

        const dbType = column.type;

        PgXdrReader checkValueLength(const(int32) expectedLength) @safe
        {
            debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(expectedLength=", expectedLength, ")");

            if (expectedLength && expectedLength != valueLength)
                readValueError(column, valueLength, expectedLength);
            return PgXdrReader(connection, reader.buffer);
        }

        DbValue readBytesDelegate() @safe
        {
            debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

            auto columnDelegate = column.saveLongData;

            int readerDelegate(int64 savedLength, int64 requestedLength, scope const(ubyte)[] data) @safe
            {
                return columnDelegate(column, savedLength, requestedLength, row, data);
            }

            auto reader = checkValueLength(0);
            reader.readBytes(valueLength, &readerDelegate, PgDefaultSize.maxSegmentLength);

            return DbValue.dbNull(dbType);
        }

        DbValue readTextDelegate() @safe
        {
            debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

            auto columnDelegate = column.saveLongData;

            int readerDelegate(int64 savedLength, int64 requestedLength, scope const(ubyte)[] data) @safe
            {
                return columnDelegate(column, savedLength, requestedLength, row, data);
            }

            auto reader = checkValueLength(0);
            reader.readString(valueLength, &readerDelegate, PgDefaultSize.maxSegmentLength);

            return DbValue.dbNull(dbType);
        }

        if (column.isArray)
        {
            final switch (dbType)
            {
                case DbType.boolean:
                    return DbValue(readValueArray!bool(reader, column, valueLength), dbType);
                case DbType.int8:
                    return DbValue(readValueArray!int8(reader, column, valueLength), dbType);
                case DbType.int16:
                    return DbValue(readValueArray!int16(reader, column, valueLength), dbType);
                case DbType.int32:
                    return DbValue(readValueArray!int32(reader, column, valueLength), dbType);
                case DbType.int64:
                    return DbValue(readValueArray!int64(reader, column, valueLength), dbType);
                case DbType.int128:
                    return DbValue(readValueArray!int128(reader, column, valueLength), dbType);
                case DbType.decimal:
                    return DbValue(readValueArray!Decimal(reader, column, valueLength), dbType);
                case DbType.decimal32:
                    return DbValue(readValueArray!Decimal32(reader, column, valueLength), dbType);
                case DbType.decimal64:
                    return DbValue(readValueArray!Decimal64(reader, column, valueLength), dbType);
                case DbType.decimal128:
                    return DbValue(readValueArray!Decimal128(reader, column, valueLength), dbType);
                case DbType.numeric:
                    return DbValue(readValueArray!Numeric(reader, column, valueLength), dbType);
                case DbType.float32:
                    return DbValue(readValueArray!float32(reader, column, valueLength), dbType);
                case DbType.float64:
                    return DbValue(readValueArray!float64(reader, column, valueLength), dbType);
                case DbType.date:
                    return DbValue(readValueArray!Date(reader, column, valueLength), dbType);
                case DbType.datetime:
                case DbType.datetimeTZ:
                    return DbValue(readValueArray!DbDateTime(reader, column, valueLength), dbType);
                case DbType.time:
                case DbType.timeTZ:
                    return DbValue(readValueArray!DbTime(reader, column, valueLength), dbType);
                case DbType.uuid:
                    return DbValue(readValueArray!UUID(reader, column, valueLength), dbType);
                case DbType.stringFixed:
                case DbType.stringVary:
                case DbType.json:
                case DbType.xml:
                case DbType.text:
                    return DbValue(readValueArray!string(reader, column, valueLength), dbType);
                case DbType.binaryFixed:
                case DbType.binaryVary:
                case DbType.blob:
                    return DbValue(readValueArray!(ubyte[])(reader, column, valueLength), dbType);
                case DbType.record:
                case DbType.unknown:
                    switch (column.baseSubTypeId)
                    {
                        case PgOIdType.interval:
                            return DbValue(readValueArray!PgOIdInterval(reader, column, valueLength), dbType);
                        case PgOIdType.point:
                            return DbValue(readValueArray!DbGeoPoint(reader, column, valueLength), dbType);
                        case PgOIdType.path:
                            return DbValue(readValueArray!DbGeoPath(reader, column, valueLength), dbType);
                        case PgOIdType.box:
                            return DbValue(readValueArray!DbGeoBox(reader, column, valueLength), dbType);
                        case PgOIdType.polygon:
                            return DbValue(readValueArray!DbGeoPolygon(reader, column, valueLength), dbType);
                        case PgOIdType.circle:
                            return DbValue(readValueArray!DbGeoCircle(reader, column, valueLength), dbType);
                        default:
                            return readValueError(column, valueLength, 0);
                    }
                case DbType.array:
                    return readValueError(column, valueLength, 0);
            }

            // Never reach here
            assert(0, toName!DbType(dbType));
        }

        final switch (dbType)
        {
            case DbType.boolean:
                return DbValue(checkValueLength(1).readBool(), dbType);
            case DbType.int8:
                return DbValue(cast(int8)(checkValueLength(2).readInt16()), dbType);
            case DbType.int16:
                return DbValue(checkValueLength(2).readInt16(), dbType);
            case DbType.int32:
                return DbValue(checkValueLength(4).readInt32(), dbType);
            case DbType.int64:
                return DbValue(checkValueLength(8).readInt64(), dbType);
            case DbType.int128:
                return DbValue(checkValueLength(16).readInt128(), dbType);
            case DbType.decimal:
                return DbValue(checkValueLength(0).readDecimal!Decimal(column.baseType), dbType);
            case DbType.decimal32:
                return DbValue(checkValueLength(0).readDecimal!Decimal32(column.baseType), dbType);
            case DbType.decimal64:
                return DbValue(checkValueLength(0).readDecimal!Decimal64(column.baseType), dbType);
            case DbType.decimal128:
                return DbValue(checkValueLength(0).readDecimal!Decimal128(column.baseType), dbType);
            case DbType.numeric:
                return DbValue(checkValueLength(0).readDecimal!Numeric(column.baseType), dbType);
            case DbType.float32:
                return DbValue(checkValueLength(4).readFloat32(), dbType);
            case DbType.float64:
                return DbValue(checkValueLength(8).readFloat64(), dbType);
            case DbType.date:
                return DbValue(checkValueLength(4).readDate(), dbType);
            case DbType.datetime:
                return DbValue(checkValueLength(8).readDateTime(), dbType);
            case DbType.datetimeTZ:
                return DbValue(checkValueLength(8).readDateTimeTZ(), dbType);
            case DbType.time:
                return DbValue(checkValueLength(8).readTime(), dbType);
            case DbType.timeTZ:
                return DbValue(checkValueLength(12).readTimeTZ(), dbType);
            case DbType.uuid:
                return DbValue(checkValueLength(16).readUUID(), dbType);
            case DbType.stringFixed:
                return DbValue(checkValueLength(0).readString(valueLength), dbType);
            case DbType.stringVary:
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                return column.saveLongData is null
                    ? DbValue(checkValueLength(0).readString(valueLength), dbType)
                    : readTextDelegate();
            case DbType.binaryFixed:
                return DbValue(checkValueLength(0).readBytes(valueLength), dbType);
            case DbType.binaryVary:
            case DbType.blob:
                return column.saveLongData is null
                    ? DbValue(checkValueLength(0).readBytes(valueLength), dbType)
                    : readBytesDelegate();
            case DbType.record:
            case DbType.unknown:
                switch (column.baseTypeId)
                {
                    case PgOIdType.interval:
                        return DbValue(checkValueLength(16).readInterval(), dbType);
                    case PgOIdType.point:
                        return DbValue(checkValueLength(8 * 2).readGeoPoint(), dbType);
                    case PgOIdType.path:
                        return DbValue(checkValueLength(0).readGeoPath(), dbType);
                    case PgOIdType.box:
                        return DbValue(checkValueLength(8 * 4).readGeoBox(), dbType);
                    case PgOIdType.polygon:
                        return DbValue(checkValueLength(0).readGeoPolygon(), dbType);
                    case PgOIdType.circle:
                        return DbValue(checkValueLength(8 * 3).readGeoCircle(), dbType);
                    default:
                        return readValueError(column, valueLength, 0);
                }
            case DbType.array:
                return readValueError(column, valueLength, 0);
        }

        // Never reach here
        assert(0, toName!DbType(dbType));
    }

    final DbRowValue readValues(ref PgReader reader, PgColumnList columns, size_t row)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(row=", row, ")");
        version(profile) debug auto p = PerfFunction.create();

        const columnCount = reader.readColumnCount();
        const resultColumnCount = max(columnCount, columns.length);
        const readColumnCount = min(columnCount, columns.length);

        debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "columnCount=", columnCount, ", columns.length=", columns.length);

        auto result = DbRowValue(resultColumnCount, row);

        if (readColumnCount < resultColumnCount)
        {
            foreach (i; readColumnCount..resultColumnCount)
                result[i].nullify();
        }

        foreach (i; 0..readColumnCount)
        {
            const valueLength = reader.readValueLength();
            if (valueLength == pgNullValueLength)
            {
                result[i].nullify();
                continue;
            }

            result[i] = readValue(reader, columns[i], row, valueLength);
        }

        return result;
    }

    final PgGenericResponse readGenericResponse(ref PgReader reader)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        PgGenericResponse result;
        while (true)
        {
            const type = reader.readChar();
            if (type == 0)
                break;

            auto value = reader.readCString();
            result.typeValues[type] = value;
        }
        return result;
    }

    final PgNotificationResponse readNotificationResponse(ref PgReader reader)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        PgNotificationResponse result;
        result.pid = reader.readInt32();
        result.channel = reader.readCString();
        result.payload = reader.readCString();
        return result;
    }

    final void writeSignal(const(PgOIdDescribeType) signalType, const(int32) signalId = 4)
    {
        auto writer = PgWriter(connection);
		writeSignal(writer, signalType, signalId);
        writer.flush();
    }

    @property final PgConnection connection() nothrow pure
    {
        return _connection;
    }

protected:
    final void cancelRequestWrite(int32 serverProcessId, int32 serverSecretKey, int32 cancelKind)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(serverProcessId=", serverProcessId, ", serverSecretKey=", serverSecretKey, ", cancelKind=", cancelKind, ")");

        const len = int32.sizeof +  // Length
                    int32.sizeof +  // Cancel request code
                    int32.sizeof +  // Backend process id
                    int32.sizeof;   // Backend secret key

        auto writer = PgWriter(connection);
        writer.writeInt32(len);
        writer.writeInt32(cancelKind);
        writer.writeInt32(serverProcessId);
        writer.writeInt32(serverSecretKey);
        writer.flush();
    }

    final DbEncryptedConnection canCryptedConnection(ref PgConnectingStateInfo stateInfo) nothrow
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto useCSB = connection.pgConnectionStringBuilder;

        final switch (useCSB.encrypt)
        {
            case DbEncryptedConnection.disabled:
                return DbEncryptedConnection.disabled;
            case DbEncryptedConnection.enabled:
                return useCSB.hasSSL()
                    ? DbEncryptedConnection.enabled
                    : DbEncryptedConnection.disabled;
            case DbEncryptedConnection.required:
                return DbEncryptedConnection.required;
        }
    }

    final void connectAuthenticationProcess(ref PgConnectingStateInfo stateInfo, const(ubyte)[] serverAuthData)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(stateInfo.nextAuthState=", stateInfo.nextAuthState,
            ", stateInfo.authMethod=", stateInfo.authMethod, ", serverAuthData=", serverAuthData.dgToString(), ")");

        auto useCSB = connection.pgConnectionStringBuilder;

        if (stateInfo.nextAuthState == 0)
            stateInfo.auth = createAuth(stateInfo.authMethod);
        if (stateInfo.auth is null)
        {
            auto msg = DbMessage.eInvalidConnectionAuthServerData.fmtMessage(stateInfo.authMethod, "invalid state: " ~ stateInfo.nextAuthState.to!string());
            throw new PgException(DbErrorCode.read, msg);
        }

        auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword,
            serverAuthData, stateInfo.authData);
        if (status.isError)
            throw new PgException(DbErrorCode.read, status.errorMessage);

        if (stateInfo.authData.length || stateInfo.nextAuthState == 0)
        {
            auto writer = PgWriter(connection);
            writer.beginMessage('p');
            if (stateInfo.nextAuthState == 0)
            {
                if (stateInfo.auth.multiStates == 1)
                    writer.writeCChars(cast(const(char)[])stateInfo.authData[]);
                else
                {
                    writer.writeCChars(stateInfo.authMethod);
                    writer.writeBytes(stateInfo.authData[]);
                }
            }
            else
                writer.writeBytesRaw(stateInfo.authData[]);
            stateInfo.nextAuthState++;
            writer.flush();
        }
    }

    version(none)
    final string convertConnectionParameter(string name, string value) nothrow
    {
        auto useCSB = connection.pgConnectionStringBuilder;
        switch (name)
        {
            case DbConnectionParameterIdentifier.compress:
                return useCSB.compress ? "1" : null; // Return empty to skip sending since default is disabled
            case DbConnectionParameterIdentifier.connectionTimeout:
                auto connectionTimeout = useCSB.connectionTimeout.total!"seconds";
                return connectionTimeout != 0 ? connectionTimeout.to!string() : null; // Return empty to skip
            case DbConnectionParameterIdentifier.encrypt:
                final switch (useCSB.encrypt)
                {
                    case DbEncryptedConnection.disabled:
                        return "disable";
                    case DbEncryptedConnection.enabled:
                        return "allow";
                    case DbEncryptedConnection.required:
                        return "require";
                }
            case DbConnectionParameterIdentifier.receiveTimeout:
                auto receiveTimeout = useCSB.receiveTimeout.total!"msecs";
                return receiveTimeout != 0 ? receiveTimeout.to!string() : null; // Return empty to skip
            default:
                assert(0, "convertConnectionParameter? "  ~ name);
        }
    }

    final PgAuth createAuth(const(char)[] authMethod)
    {
        auto authMap = PgAuth.findAuthMap(authMethod);
        if (!authMap.isValid())
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(authMethod);
            throw new PgException(DbErrorCode.read, msg);
        }

        return cast(PgAuth)authMap.createAuth();
    }

    final void describeParameters(ref PgWriter writer, scope PgParameter[] inputParameters)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(inputParameters.length=", inputParameters.length, ")");

        writer.writeInt16(cast(int16)inputParameters.length);
        foreach (parameter; inputParameters)
            describeParameter(writer, parameter); // parameter.value);
    }

    final void describeParameter(ref PgWriter writer, PgParameter parameter)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(parameter.name=", parameter.name,
            ", parameter.type=", parameter.type, ", parameter.baseTypeId=", parameter.baseTypeId, ")");

        if (parameter.isNull)
            return writer.writeInt32(pgNullValueLength);

        noreturn unsupportDataError()
        {
            auto msg = DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ "." ~ __FUNCTION__, toName!DbType(parameter.type));
            throw new PgException(DbErrorCode.write, msg);
        }

        if (parameter.isArray)
        {
            final switch (parameter.type)
            {
                case DbType.boolean:
                    return describeParameterArray!bool(writer, parameter, PgOIdType.bool_);
                case DbType.int8:
                    return describeParameterArray!int8(writer, parameter, PgOIdType.int2);
                case DbType.int16:
                    return describeParameterArray!int16(writer, parameter, PgOIdType.int2);
                case DbType.int32:
                    return describeParameterArray!int32(writer, parameter, PgOIdType.int4);
                case DbType.int64:
                    return describeParameterArray!int64(writer, parameter, PgOIdType.int8);
                case DbType.int128:
                    //return describeParameterArray!int64(writer, parameter, PgOIdType.unknown);
                    return unsupportDataError();
                case DbType.decimal:
                    return describeParameterArray!Decimal(writer, parameter, PgOIdType.numeric);
                case DbType.decimal32:
                    return describeParameterArray!Decimal32(writer, parameter, PgOIdType.numeric);
                case DbType.decimal64:
                    return describeParameterArray!Decimal64(writer, parameter, PgOIdType.numeric);
                case DbType.decimal128:
                    return describeParameterArray!Decimal128(writer, parameter, PgOIdType.numeric);
                case DbType.numeric:
                    return describeParameterArray!Numeric(writer, parameter, PgOIdType.numeric);
                case DbType.float32:
                    return describeParameterArray!float32(writer, parameter, PgOIdType.float4);
                case DbType.float64:
                    return describeParameterArray!float64(writer, parameter, PgOIdType.float8);
                case DbType.date:
                    return describeParameterArray!Date(writer, parameter, PgOIdType.date);
                case DbType.datetime:
                    return describeParameterArray!DbDateTime(writer, parameter, PgOIdType.timestamp);
                case DbType.datetimeTZ:
                    return describeParameterArray!DbDateTime(writer, parameter, PgOIdType.timestamptz);
                case DbType.time:
                    return describeParameterArray!DbTime(writer, parameter, PgOIdType.time);
                case DbType.timeTZ:
                    return describeParameterArray!DbTime(writer, parameter, PgOIdType.timetz);
                case DbType.uuid:
                    return describeParameterArray!UUID(writer, parameter, PgOIdType.uuid);
                case DbType.stringFixed:
                    return describeParameterArray!(const(char)[])(writer, parameter, PgOIdType.bpchar);
                case DbType.stringVary:
                    return describeParameterArray!(const(char)[])(writer, parameter, PgOIdType.varchar);
                case DbType.json:
                    return describeParameterArray!(const(char)[])(writer, parameter, PgOIdType.json);
                case DbType.xml:
                    return describeParameterArray!(const(char)[])(writer, parameter, PgOIdType.xml);
                case DbType.text:
                    return describeParameterArray!(const(char)[])(writer, parameter, PgOIdType.text);
                case DbType.binaryFixed:
                case DbType.binaryVary:
                case DbType.blob:
                    return describeParameterArray!(const(ubyte)[])(writer, parameter, PgOIdType.bytea);
                case DbType.record:
                case DbType.unknown:
                    switch (parameter.baseSubTypeId)
                    {
                        case PgOIdType.interval:
                            return describeParameterArray!PgOIdInterval(writer, parameter, PgOIdType.interval);
                        case PgOIdType.point:
                            return describeParameterArray!DbGeoPoint(writer, parameter, PgOIdType.point);
                        case PgOIdType.path:
                            return describeParameterArray!DbGeoPath(writer, parameter, PgOIdType.path);
                        case PgOIdType.box:
                            return describeParameterArray!DbGeoBox(writer, parameter, PgOIdType.box);
                        case PgOIdType.polygon:
                            return describeParameterArray!DbGeoPolygon(writer, parameter, PgOIdType.polygon);
                        case PgOIdType.circle:
                            return describeParameterArray!DbGeoCircle(writer, parameter, PgOIdType.circle);
                        default:
                            return unsupportDataError();
                    }
                case DbType.array:
                    return unsupportDataError();
            }

            // Never reach here
            assert(0, toName!DbType(parameter.type));
        }

        auto valueWriter = PgXdrWriter(connection, writer.buffer);
        // Use coerce for implicit basic type conversion
        final switch (parameter.type)
        {
            case DbType.boolean:
                return valueWriter.writeBool(parameter.value.coerce!bool());
            case DbType.int8:
                return valueWriter.writeInt16(parameter.value.coerce!int8());
            case DbType.int16:
                return valueWriter.writeInt16(parameter.value.coerce!int16());
            case DbType.int32:
                return valueWriter.writeInt32(parameter.value.coerce!int32());
            case DbType.int64:
                return valueWriter.writeInt64(parameter.value.coerce!int64());
            case DbType.int128:
                return valueWriter.writeInt128(parameter.value.get!BigInteger());
            case DbType.decimal:
                return valueWriter.writeDecimal!Decimal(parameter.value.get!Decimal(), parameter.baseType);
            case DbType.decimal32:
                return valueWriter.writeDecimal!Decimal32(parameter.value.get!Decimal32(), parameter.baseType);
            case DbType.decimal64:
                return valueWriter.writeDecimal!Decimal64(parameter.value.get!Decimal64(), parameter.baseType);
            case DbType.decimal128:
                return valueWriter.writeDecimal!Decimal128(parameter.value.get!Decimal128(), parameter.baseType);
            case DbType.numeric:
                return valueWriter.writeDecimal!Numeric(parameter.value.get!Numeric(), parameter.baseType);
            case DbType.float32:
                return valueWriter.writeFloat32(parameter.value.coerce!float32());
            case DbType.float64:
                return valueWriter.writeFloat64(parameter.value.coerce!float64());
            case DbType.date:
                return valueWriter.writeDate(parameter.value.get!Date());
            case DbType.datetime:
                return valueWriter.writeDateTime(parameter.value.get!DbDateTime());
            case DbType.datetimeTZ:
                return valueWriter.writeDateTimeTZ(parameter.value.get!DbDateTime());
            case DbType.time:
                return valueWriter.writeTime(parameter.value.get!DbTime());
            case DbType.timeTZ:
                return valueWriter.writeTimeTZ(parameter.value.get!DbTime());
            case DbType.uuid:
                return valueWriter.writeUUID(parameter.value.get!UUID());
            case DbType.stringFixed:
            case DbType.stringVary:
            case DbType.text:
            case DbType.json:
            case DbType.xml:
                const(char)[] data;
                if (parameter.loadClob(0, size_t.max, data) == 0)
                    return writer.writeInt32(pgNullValueLength);
                else
                    return valueWriter.writeChars(data);
            case DbType.binaryFixed:
            case DbType.binaryVary:
            case DbType.blob:
                const(ubyte)[] data;
                if (parameter.loadBlob(0, size_t.max, data) == 0)
                    return writer.writeInt32(pgNullValueLength);
                else
                    return valueWriter.writeBytes(data);
            case DbType.record:
            case DbType.unknown:
                switch (parameter.baseTypeId)
                {
                    case PgOIdType.interval:
                        return valueWriter.writeInterval(parameter.value.get!PgOIdInterval());
                    case PgOIdType.point:
                        return valueWriter.writeGeoPoint(parameter.value.get!DbGeoPoint());
                    case PgOIdType.path:
                        return valueWriter.writeGeoPath(parameter.value.get!DbGeoPath());
                    case PgOIdType.box:
                        return valueWriter.writeGeoBox(parameter.value.get!DbGeoBox());
                    case PgOIdType.polygon:
                        return valueWriter.writeGeoPolygon(parameter.value.get!DbGeoPolygon());
                    case PgOIdType.circle:
                        return valueWriter.writeGeoCircle(parameter.value.get!DbGeoCircle());
                    default:
                        return unsupportDataError();
                }

            case DbType.array:
                return unsupportDataError();
        }

        // Never reach here
        assert(0, toName!DbType(parameter.type));
    }

    final void describeParameterArray(T)(ref PgWriter writer, PgParameter parameter, const(int32) elementOid)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(parameter.name=", parameter.name, ", elementOid=", elementOid, ")");

        alias UT = Unqual!T;

        auto values = parameter.value.get!(T[])();
        const int32 length = cast(int32)values.length;
        auto valueWriter = PgXdrWriter(connection, writer.buffer);
        const marker = valueWriter.writeArrayBegin();

        // No length indicator values
        writer.writeInt32(1); // dims
        writer.writeInt32(0); // hasNulls
        writer.writeInt32(elementOid);
        writer.writeInt32(length); // lengths
        writer.writeInt32(1); // lowerBounds for first dimension which we do not map

        foreach (i; 0..length)
        {
            static if (is(UT == bool))
                valueWriter.writeBool(values[i]);
            else static if (is(UT == int8))
                valueWriter.writeInt16(values[i]);
            else static if (is(UT == int16))
                valueWriter.writeInt16(values[i]);
            else static if (is(UT == int32))
                valueWriter.writeInt32(values[i]);
            else static if (is(UT == int64))
                valueWriter.writeInt64(values[i]);
            else static if (is(UT == Decimal32) || is(UT == Decimal64) || is(UT == Decimal128))
                valueWriter.writeDecimal!T(values[i], parameter.baseType);
            else static if (is(UT == float32))
                valueWriter.writeFloat32(values[i]);
            else static if (is(UT == float64))
                valueWriter.writeFloat64(values[i]);
            else static if (is(UT == Date))
                valueWriter.writeDate(values[i]);
            else static if (is(UT == DbDateTime))
            {
                if (elementOid == PgOIdType.timestamptz)
                    valueWriter.writeDateTimeTZ(values[i]);
                else
                    valueWriter.writeDateTime(values[i]);
            }
            else static if (is(UT == DbTime))
            {
                if (elementOid == PgOIdType.timetz)
                    valueWriter.writeTimeTZ(values[i]);
                else
                    valueWriter.writeTime(values[i]);
            }
            else static if (is(UT == UUID))
                valueWriter.writeUUID(values[i]);
            else static if (is(UT == string) || is(T == const(char)[]))
                valueWriter.writeChars(values[i]);
            else static if (is(UT == ubyte[]) || is(T == const(ubyte)[]))
                valueWriter.writeBytes(values[i]);
            else static if (is(UT == PgOIdInterval))
                valueWriter.writeInterval(values[i]);
            else static if (is(UT == DbGeoBox))
                valueWriter.writeGeoBox(values[i]);
            else static if (is(UT == DbGeoCircle))
                valueWriter.writeGeoCircle(values[i]);
            else static if (is(UT == DbGeoPath))
                valueWriter.writeGeoPath(values[i]);
            else static if (is(UT == DbGeoPolygon))
                valueWriter.writeGeoPolygon(values[i]);
            else static if (is(UT == DbGeoPoint))
                valueWriter.writeGeoPoint(values[i]);
            else
                static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
        }

        valueWriter.writeArrayEnd(marker);
    }

    override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        if (isDisposing(disposingReason))
            _connection = null;

        debug(debug_pham_db_db_pgprotocol) debug writeln("**********");
        return ResultCode.ok;
    }

    final T[] readValueArray(T)(ref PgReader reader, DbNamedColumn column, const(int32) valueLength)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(column.name=", column.name, ", valueLength=", valueLength, ")");

        int32[] lengths;
        int32 elementOid;

        PgXdrReader checkValueLength(const(int32) valueLength, const(int32) expectedLength) @safe
        {
            if (expectedLength && expectedLength != valueLength)
                readValueError(column, valueLength, expectedLength);
            return PgXdrReader(connection, reader.buffer);
        }

        int32 readDimensions() @safe
        {
            auto valueReader = PgXdrReader(connection, reader.buffer);

            int32 dims, hasNulls;
            int32[] lowerBounds;

            dims = valueReader.readInt32();
            hasNulls = valueReader.readInt32(); // 0 or 1
            elementOid = valueReader.readInt32();

            if (dims > 0)
            {
                lengths.length = lowerBounds.length = dims;
                foreach (i; 0..dims)
                {
                    lengths[i] = valueReader.readInt32();
                    lowerBounds[i] = valueReader.readInt32();
                }
            }

            return dims;
        }

        if (readDimensions() <= 0)
            return null;

        // Only process the first one
        if (lengths[0] <= 0)
            return null;

        T[] result = new T[](lengths[0]);
        foreach (i; 0..result.length)
        {
            const elementValueLength = reader.readValueLength();
            if (elementValueLength <= 0)
                continue;

            static if (is(T == bool))
                result[i] = checkValueLength(elementValueLength, 1).readBool();
            else static if (is(T == int8))
                result[i] = cast(int8)(checkValueLength(elementValueLength, 2).readInt16());
            else static if (is(T == int16))
                result[i] = checkValueLength(elementValueLength, 2).readInt16();
            else static if (is(T == int32))
                result[i] = checkValueLength(elementValueLength, 4).readInt32();
            else static if (is(T == int64))
                result[i] = checkValueLength(elementValueLength, 8).readInt64();
            else static if (is(T == int128))
                result[i] = checkValueLength(elementValueLength, 16).readInt128();
            else static if (is(T == Decimal32) || is(T == Decimal64) || is(T == Decimal128))
                result[i] = checkValueLength(elementValueLength, 0).readDecimal!T(column.baseType);
            else static if (is(T == float32))
                result[i] = checkValueLength(elementValueLength, 4).readFloat32();
            else static if (is(T == float64))
                result[i] = checkValueLength(elementValueLength, 8).readFloat64();
            else static if (is(T == Date))
                result[i] = checkValueLength(elementValueLength, 4).readDate();
            else static if (is(T == DbDateTime))
            {
                if (elementOid == PgOIdType.timestamptz)
                    result[i] = checkValueLength(elementValueLength, 12).readDateTimeTZ();
                else
                    result[i] = checkValueLength(elementValueLength, 8).readDateTime();
            }
            else static if (is(T == DbTime))
            {
                if (elementOid == PgOIdType.timetz)
                    result[i] = checkValueLength(elementValueLength, 12).readTimeTZ();
                else
                    result[i] = checkValueLength(elementValueLength, 8).readTime();
            }
            else static if (is(T == UUID))
                result[i] = checkValueLength(elementValueLength, 16).readUUID();
            else static if (is(T == string))
                result[i] = checkValueLength(elementValueLength, 0).readString(elementValueLength);
            else static if (is(T == ubyte[]))
                result[i] = checkValueLength(elementValueLength, 0).readBytes(elementValueLength);
            else static if (is(T == PgOIdInterval))
                result[i] = checkValueLength(elementValueLength, 16).readInterval();
            else static if (is(T == DbGeoBox))
                result[i] = checkValueLength(elementValueLength, 8 * 4).readGeoBox();
            else static if (is(T == DbGeoCircle))
                result[i] = checkValueLength(elementValueLength, 8 * 3).readGeoCircle();
            else static if (is(T == DbGeoPath))
                result[i] = checkValueLength(elementValueLength, 0).readGeoPath();
            else static if (is(T == DbGeoPolygon))
                result[i] = checkValueLength(elementValueLength, 0).readGeoPolygon();
            else static if (is(T == DbGeoPoint))
                result[i] = checkValueLength(elementValueLength, 8 * 2).readGeoPoint();
            else
                static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
        }
        return result;
    }

    final DbValue readValueError(DbNamedColumn column, const(int32) valueLength, const(int32) expectedLength)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        auto msg = expectedLength > 0
            ? DbMessage.eUnexpectReadValue.fmtMessage(shortClassName(this) ~ ".readValue", toName!DbType(column.type), valueLength, expectedLength)
            : DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ ".readValue", toName!DbType(column.type));
        throw new PgException(DbErrorCode.read, msg);
    }

    final void writeBindMessage(ref PgWriter writer, PgCommand command, scope PgParameter[] inputParameters)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        writer.beginMessage(PgOIdDescribeType.bindStatement);
        writer.writeCChars(command.name); // portalName
        writer.writeCChars(command.name); // statementName
        writer.writeInt16(1); // only one parameter format code
        writer.writeInt16(1); // all binary format code

        if (inputParameters.length)
            describeParameters(writer, inputParameters);
        else
            writer.writeInt16(0); // zero parameter length indicator
        writer.writeInt16(1); // only one result format code
        writer.writeInt16(1); // all binary format code
        writer.endMessage();
    }

    final void writeCloseMessage(ref PgWriter writer, const(PgOIdDescribeType) type, scope const(char)[] name)
	{
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

		writer.beginMessage(PgOIdDescribeType.close);
        writer.writeChar(type);
        writer.writeCChars(name);
        writer.endMessage();
    }

    final void writeDescribeMessage(ref PgWriter writer, PgCommand command)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

		writer.beginMessage(PgOIdDescribeType.describeStatement);
        writer.writeChar(PgOIdDescribeType.portal);
        writer.writeCChars(command.name);
        writer.endMessage();
    }

    final void writeExecuteMessage(ref PgWriter writer, PgCommand command, int32 fetchRecordCount)
	{
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "(fetchRecordCount=", fetchRecordCount, ")");

		writer.beginMessage(PgOIdDescribeType.executeStatement);
        writer.writeCChars(command.name);
        writer.writeInt32(fetchRecordCount > 0 ? fetchRecordCount : int32.max);
        writer.endMessage();
    }

    final void writeParseMessage(ref PgWriter writer, PgCommand command, scope const(char)[] sql,
        scope PgParameter[] inputParameters)
    {
        debug(debug_pham_db_db_pgprotocol) debug writeln(__FUNCTION__, "()");

        /*
        size_t sendParameters = inputParameters.length;
        foreach (inputParameter; inputParameters)
        {
            const baseTypeId = inputParameter.baseTypeId;
            if (baseTypeId == PgOIdType.void_ || baseTypeId == PgOIdType.unknown)
                sendParameters--;
        }
        */

		writer.beginMessage(PgOIdDescribeType.parseStatement);
        writer.writeCChars(command.name);
        writer.writeCChars(sql);
        if (inputParameters.length)
        {
            writer.writeInt16(cast(int16)inputParameters.length);
            foreach (inputParameter; inputParameters)
            {
                debug(debug_pham_db_db_pgprotocol) debug writeln("\t", "inputParameter.name=", inputParameter.name,
                    ", baseName=", inputParameter.baseName, ", baseTypeId=", inputParameter.baseTypeId);

                // 54.2.3. Extended Query; PgOIdType.void_ is only being used for out parameter
                const baseTypeId = inputParameter.baseTypeId;
                writer.writeInt32(baseTypeId != PgOIdType.void_ ? baseTypeId : PgOIdType.unknown);
            }
        }
        else
            writer.writeInt16(0);
        writer.endMessage();
    }

    final void writeSignal(ref PgWriter writer, const(PgOIdDescribeType) signalType, const(int32) signalId = 4)
    {
        writer.writeSignal(signalType, signalId);
    }

private:
    PgConnection _connection;
}


// Any below codes are private
private:
