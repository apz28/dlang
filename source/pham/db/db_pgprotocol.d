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

module pham.db.pgprotocol;

import std.algorithm.comparison : max, min;
import std.ascii : LetterCase;
import std.conv : to;
import std.string : indexOf, lastIndexOf, representation;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.enum_set : toName;
import pham.utl.object : shortClassName;
import pham.db.buffer;
import pham.db.database : DbNameColumn;
import pham.db.message;
import pham.db.object;
import pham.db.type;
import pham.db.value;
import pham.db.pgauth;
import pham.db.pgbuffer;
import pham.db.pgdatabase;
import pham.db.pgexception;
import pham.db.pgoid;
import pham.db.pgtype;

struct PgConnectingStateInfo
{
nothrow @safe:

    PgAuth auth;
    const(ubyte)[] authData;
    const(char)[] authMethod;
    int32 authType;
    int32 serverProcessId;
    int32 serverSecretKey;
    int nextAuthState;
    char trStatus;
}

class PgProtocol : DbDisposableObject
{
@safe:

public:
    this(PgConnection connection) nothrow pure
    {
        this._connection = connection;
    }

    final PgOIdFieldInfo[] bindCommandParameterRead(PgCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

    receiveAgain:
        auto reader = PgReader(connection);
        switch (reader.messageType)
        {
            case '2': // BindComplete
            case '3': // CloseComplete
                goto receiveAgain;

            case 'T': // RowDescription (response to Describe)
                const count = reader.readInt16();
                PgOIdFieldInfo[] result = new PgOIdFieldInfo[](count);
                foreach (i; 0..count)
                {
                    result[i].name = reader.readCString();
                    result[i].tableOid = reader.readOId();
                    result[i].index = reader.readInt16();
                    result[i].type = reader.readOId();
                    result[i].size = reader.readInt16();
                    result[i].modifier = reader.readOId();
                    result[i].formatCode = reader.readInt16();
                }
                return result;

            case 'n': // NoData (response to Describe)
                return null;

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

    receiveAgain:
        auto reader = PgReader(connection);
        switch (reader.messageType)
        {
            case 'K': // BackendKeyData
                stateInfo.serverProcessId = reader.readInt32();
                stateInfo.serverSecretKey = reader.readInt32();
                connection.serverInfo[DbServerIdentifier.protocolProcessId] = to!string(stateInfo.serverProcessId);
                connection.serverInfo[DbServerIdentifier.protocolSecretKey] = to!string(stateInfo.serverSecretKey);
                goto receiveAgain;

            case 'R': // AuthenticationXXXX
                stateInfo.authType = reader.readInt32();
                version (TraceFunction) traceFunction!("pham.db.pgdatabase")("authType=", stateInfo.authType);
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
                        auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(to!string(stateInfo.authType));
                        throw new PgException(msg, DbErrorCode.read, null);
                }

            case 'S': // ParameterStatus
                const name = reader.readCString();
                const value = reader.readCString();
                version (TraceFunction) traceFunction!("pham.db.pgdatabase")("name=", name, ", value=", value);
                connection.serverInfo[name] = value;
                goto receiveAgain;

            case 'Z': // ReadyForQuery
                stateInfo.trStatus = reader.readChar();
                version (TraceFunction) traceFunction!("pham.db.pgdatabase")("trStatus=", stateInfo.trStatus);
                switch (stateInfo.trStatus) // check for validity
                {
                    case 'E', 'I', 'T':
                        connection.serverInfo[DbServerIdentifier.protocolTrStatus] = to!string(stateInfo.trStatus);
                        break;

                    default:
                        auto msg = DbMessage.eInvalidConnectionStatus.fmtMessage(to!string(stateInfo.trStatus));
                        throw new PgException(msg, DbErrorCode.read, null);
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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        auto useCSB = connection.pgConnectionStringBuilder;

        auto writer = PgWriter(connection);
        writer.beginMessage('\0'); // \0=No type indicator
        writer.writeUInt32(PgOIdOther.protocolVersion);
        foreach (n; useCSB.parameterNames)
        {
            string mappedName;
            final switch (canSendParameter(n, mappedName))
            {
                case CanSendParameter.no:
                    break;

                case CanSendParameter.yes:
                    auto yv = useCSB.getCustomValue(n);
                    if (yv.length)
                    {
                        writer.writeCChars(mappedName);
                        writer.writeCChars(yv);
                    }
                    break;

                case CanSendParameter.yesConvert:
                    auto cv = useCSB.getCustomValue(n);
                    if (cv.length)
                        cv = convertConnectionParameter(n, cv);
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

    final void deallocateCommandRead()
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        auto writer = PgWriter(connection);
        writeCloseMessage(writer, PgOIdDescribeType.statement, command.name);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final void disconnectWrite()
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        writeSignal(PgOIdDescribeType.disconnect);
    }

    final PgOIdExecuteResult executeCommandRead(PgCommand command, const(DbCommandExecuteType) type, out PgReader reader)
    {
        // Need to return package reader to continue reading row values

        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("type=", type);

        PgOIdExecuteResult result;

	receiveAgain:
        reader = PgReader(connection);
        result.messageType = reader.messageType;
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
                            result.recordsAffected = to!long(tag[b1 + 1..$]);
                            break;

                        case "INSERT":
                            const b2 = lastIndexOf(tag, ' ');
                            result.oid = to!int32(tag[b1 + 1..b2]);
                            result.recordsAffected = to!long(tag[b2 + 1..$]);
                            break;

                        case "SELECT":
                            const b2 = lastIndexOf(tag, ' ');
                            if (b2 > b1)
                                result.recordsAffected = to!long(tag[b2 + 1..$]);
                            else
                                result.recordsAffected = to!long(tag[b1 + 1..$]);
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
                throw new PgException(DbMessage.eInvalidCommandText, DbErrorCode.read, null);

            case 'Z': // ReadyForQuery - done
                break;

            case 's': // PortalSuspended
                throw new PgException(DbMessage.eInvalidCommandSuspended, DbErrorCode.read, null);

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

    final void executeCommandWrite(PgCommand command, const(DbCommandExecuteType) type)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("type=", type);

        auto writer = PgWriter(connection);
        writeExecuteMessage(writer, command, type);
        writeSignal(writer, PgOIdDescribeType.sync);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final PgOIdFetchResult fetchCommandRead(PgCommand command, ref bool isSuspended, out PgReader reader)
    in
    {
        assert(command.hasFields);
    }
    do
    {
        // Need to return package reader to continue reading row values

        version (TraceFunction)
        {
            static ulong counter;
            traceFunction!("pham.db.pgdatabase")("counter: ", ++counter);
        }

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        auto inputParameters = command.pgInputParameters();

        auto writer = PgWriter(connection);
        writeParseMessage(writer, command, sql, inputParameters);
        writeSignal(writer, PgOIdDescribeType.flush);
        writer.flush();
    }

    final DbValue readValue(ref PgReader reader, PgCommand command, DbNameColumn column, const(int32) valueLength)
    in
    {
        assert(valueLength != pgNullValueLength);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")(column.traceString(), ", valueLength=", valueLength);
        version (profile) debug auto p = PerfFunction.create();

        PgXdrReader checkValueLength(const(int32) expectedLength) @safe
        {
            if (expectedLength && expectedLength != valueLength)
                readValueError(column, valueLength, expectedLength);
            return PgXdrReader(connection, reader.buffer);
        }

        const dbType = column.type;
        if (column.isArray)
        {
            final switch (dbType)
            {
                case DbType.boolean:
                    return DbValue(readValueArray!bool(reader, command, column, valueLength), dbType);
                case DbType.int8:
                    return DbValue(readValueArray!int8(reader, command, column, valueLength), dbType);
                case DbType.int16:
                    return DbValue(readValueArray!int16(reader, command, column, valueLength), dbType);
                case DbType.int32:
                    return DbValue(readValueArray!int32(reader, command, column, valueLength), dbType);
                case DbType.int64:
                    return DbValue(readValueArray!int64(reader, command, column, valueLength), dbType);
                case DbType.int128:
                    return DbValue(readValueArray!int128(reader, command, column, valueLength), dbType);
                case DbType.decimal:
                    return DbValue(readValueArray!Decimal(reader, command, column, valueLength), dbType);
                case DbType.decimal32:
                    return DbValue(readValueArray!Decimal32(reader, command, column, valueLength), dbType);
                case DbType.decimal64:
                    return DbValue(readValueArray!Decimal64(reader, command, column, valueLength), dbType);
                case DbType.decimal128:
                    return DbValue(readValueArray!Decimal128(reader, command, column, valueLength), dbType);
                case DbType.numeric:
                    return DbValue(readValueArray!Numeric(reader, command, column, valueLength), dbType);
                case DbType.float32:
                    return DbValue(readValueArray!float32(reader, command, column, valueLength), dbType);
                case DbType.float64:
                    return DbValue(readValueArray!float64(reader, command, column, valueLength), dbType);
                case DbType.date:
                    return DbValue(readValueArray!Date(reader, command, column, valueLength), dbType);
                case DbType.datetime:
                case DbType.datetimeTZ:
                    return DbValue(readValueArray!DbDateTime(reader, command, column, valueLength), dbType);
                case DbType.time:
                case DbType.timeTZ:
                    return DbValue(readValueArray!DbTime(reader, command, column, valueLength), dbType);
                case DbType.uuid:
                    return DbValue(readValueArray!UUID(reader, command, column, valueLength), dbType);
                case DbType.fixedString:
                case DbType.string:
                case DbType.json:
                case DbType.xml:
                case DbType.text:
                    return DbValue(readValueArray!string(reader, command, column, valueLength), dbType);
                case DbType.fixedBinary:
                case DbType.binary:
                    return DbValue(readValueArray!(ubyte[])(reader, command, column, valueLength), dbType);
                case DbType.record:
                case DbType.unknown:
                    switch (column.baseSubTypeId)
                    {
                        case PgOIdType.interval:
                            return DbValue(readValueArray!PgOIdInterval(reader, command, column, valueLength), dbType);
                        case PgOIdType.point:
                            return DbValue(readValueArray!DbGeoPoint(reader, command, column, valueLength), dbType);
                        case PgOIdType.path:
                            return DbValue(readValueArray!DbGeoPath(reader, command, column, valueLength), dbType);
                        case PgOIdType.box:
                            return DbValue(readValueArray!DbGeoBox(reader, command, column, valueLength), dbType);
                        case PgOIdType.polygon:
                            return DbValue(readValueArray!DbGeoPolygon(reader, command, column, valueLength), dbType);
                        case PgOIdType.circle:
                            return DbValue(readValueArray!DbGeoCircle(reader, command, column, valueLength), dbType);

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
                return DbValue(checkValueLength(12).readDateTimeTZ(), dbType);
            case DbType.time:
                return DbValue(checkValueLength(8).readTime(), dbType);
            case DbType.timeTZ:
                return DbValue(checkValueLength(12).readTimeTZ(), dbType);
            case DbType.uuid:
                return DbValue(checkValueLength(16).readUUID(), dbType);
            case DbType.fixedString:
            case DbType.string:
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                return DbValue(checkValueLength(0).readString(valueLength), dbType);
            case DbType.fixedBinary:
            case DbType.binary:
                return DbValue(checkValueLength(0).readBytes(valueLength), dbType);
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

    final DbRowValue readValues(ref PgReader reader, PgCommand command, PgFieldList fields)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();
        version (profile) debug auto p = PerfFunction.create();

        const fieldCount = reader.readFieldCount();
        const resultFieldCount = max(fieldCount, fields.length);
        const readFieldCount = min(fieldCount, fields.length);

        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("fieldCount=", fieldCount, ", fields.length=", fields.length);

        auto result = DbRowValue(resultFieldCount);

        if (readFieldCount < resultFieldCount)
        {
            foreach (i; readFieldCount..resultFieldCount)
                result[i].nullify();
        }

        foreach (i; 0..readFieldCount)
        {
            const valueLength = reader.readValueLength();
            if (valueLength == pgNullValueLength)
            {
                result[i].nullify();
                continue;
            }

            result[i] = readValue(reader, command, fields[i], valueLength);
        }

        return result;
    }

    final PgGenericResponse readGenericResponse(ref PgReader reader)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("serverProcessId=", serverProcessId, ", serverSecretKey=", serverSecretKey, ", cancelKind=", cancelKind);

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

    final void connectAuthenticationProcess(ref PgConnectingStateInfo stateInfo, const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("stateInfo.nextAuthState=", stateInfo.nextAuthState, ", stateInfo.authMethod=", stateInfo.authMethod);

        auto useCSB = connection.pgConnectionStringBuilder;

        if (stateInfo.nextAuthState == 0)
            stateInfo.auth = createAuth(stateInfo.authMethod);
        if (stateInfo.auth is null)
        {
            auto msg = DbMessage.eInvalidConnectionAuthServerData.fmtMessage(stateInfo.authMethod, stateInfo.nextAuthState);
            throw new PgException(msg, DbErrorCode.read, null);
        }

        stateInfo.authData = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword, serverAuthData);
        if (stateInfo.auth.isError)
        {
            auto msg = stateInfo.auth.getErrorMessage(stateInfo.authMethod);
            throw new PgException(msg, DbErrorCode.read, null);
        }

        if (stateInfo.authData.length || stateInfo.nextAuthState == 0)
        {
            auto writer = PgWriter(connection);
            writer.beginMessage('p');
            if (stateInfo.nextAuthState == 0)
            {
                if (stateInfo.auth.multiSteps == 1)
                    writer.writeCChars(cast(const(char)[])stateInfo.authData);
                else
                {
                    writer.writeCChars(stateInfo.authMethod);
                    writer.writeBytes(stateInfo.authData);
                }
            }
            else
                writer.writeBytesRaw(stateInfo.authData);
            stateInfo.nextAuthState++;
            writer.flush();
        }
    }

    final string convertConnectionParameter(string name, string value) nothrow
    {
        return null;
        /*
        auto useCSB = connection.pgConnectionStringBuilder;
        switch (name)
        {
            case DbConnectionParameterIdentifier.compress:
                return useCSB.compress ? "1" : null; // Return empty to skip sending since default is disabled
            case DbConnectionParameterIdentifier.connectionTimeout:
                auto connectionTimeout = useCSB.connectionTimeout.total!"seconds";
                return connectionTimeout != 0 ? to!string(connectionTimeout) : null; // Return empty to skip
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
                return receiveTimeout != 0 ? to!string(receiveTimeout) : null; // Return empty to skip
            default:
                assert(0, "convertConnectionParameter? "  ~ name);
        }
        */
    }

    final PgAuth createAuth(const(char)[] authMethod)
    {
        auto authMap = PgAuth.findAuthMap(authMethod);
        if (!authMap.isValid())
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(authMethod);
            throw new PgException(msg, DbErrorCode.read, null);
        }

        auto result = cast(PgAuth)authMap.createAuth();
        if (result.isError)
        {
            auto msg = result.getErrorMessage(authMethod);
            throw new PgException(msg, DbErrorCode.write, null);
        }
        return result;
    }

    final void describeParameters(ref PgWriter writer, scope PgParameter[] inputParameters)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("inputParameters.length=", inputParameters.length);

        writer.writeInt16(cast(int16)inputParameters.length);
        foreach (param; inputParameters)
            describeValue(writer, param, param.value);
    }

    final void describeValue(ref PgWriter writer, DbNameColumn column, ref DbValue value)
    {
        if (value.isNull)
        {
            writer.writeInt32(pgNullValueLength);
            return;
        }

        void unsupportDataError()
        {
            auto msg = DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ ".describeValue", toName!DbType(column.type));
            throw new PgException(msg, DbErrorCode.write, null);
        }

        if (column.isArray)
        {
            final switch (column.type)
            {
                case DbType.boolean:
                    return describeValueArray!bool(writer, column, value, PgOIdType.bool_);
                case DbType.int8:
                    return describeValueArray!int8(writer, column, value, PgOIdType.int2);
                case DbType.int16:
                    return describeValueArray!int16(writer, column, value, PgOIdType.int2);
                case DbType.int32:
                    return describeValueArray!int32(writer, column, value, PgOIdType.int4);
                case DbType.int64:
                    return describeValueArray!int64(writer, column, value, PgOIdType.int8);
                case DbType.int128:
                    return describeValueArray!int64(writer, column, value, PgOIdType.unknown); //TODO they do not have this type
                case DbType.decimal:
                    return describeValueArray!Decimal(writer, column, value, PgOIdType.numeric);
                case DbType.decimal32:
                    return describeValueArray!Decimal32(writer, column, value, PgOIdType.numeric);
                case DbType.decimal64:
                    return describeValueArray!Decimal64(writer, column, value, PgOIdType.numeric);
                case DbType.decimal128:
                    return describeValueArray!Decimal128(writer, column, value, PgOIdType.numeric);
                case DbType.numeric:
                    return describeValueArray!Numeric(writer, column, value, PgOIdType.numeric);
                case DbType.float32:
                    return describeValueArray!float32(writer, column, value, PgOIdType.float4);
                case DbType.float64:
                    return describeValueArray!float64(writer, column, value, PgOIdType.float8);
                case DbType.date:
                    return describeValueArray!Date(writer, column, value, PgOIdType.date);
                case DbType.datetime:
                    return describeValueArray!DbDateTime(writer, column, value, PgOIdType.timestamp);
                case DbType.datetimeTZ:
                    return describeValueArray!DbDateTime(writer, column, value, PgOIdType.timestamptz);
                case DbType.time:
                    return describeValueArray!DbTime(writer, column, value, PgOIdType.time);
                case DbType.timeTZ:
                    return describeValueArray!DbTime(writer, column, value, PgOIdType.timetz);
                case DbType.uuid:
                    return describeValueArray!UUID(writer, column, value, PgOIdType.uuid);
                case DbType.fixedString:
                    return describeValueArray!string(writer, column, value, PgOIdType.bpchar);
                case DbType.string:
                    return describeValueArray!string(writer, column, value, PgOIdType.varchar);
                case DbType.json:
                    return describeValueArray!string(writer, column, value, PgOIdType.json);
                case DbType.xml:
                    return describeValueArray!string(writer, column, value, PgOIdType.xml);
                case DbType.text:
                    return describeValueArray!string(writer, column, value, PgOIdType.text);
                case DbType.fixedBinary:
                case DbType.binary:
                    return describeValueArray!(const(ubyte)[])(writer, column, value, PgOIdType.bytea);
                case DbType.record:
                case DbType.unknown:
                    switch (column.baseSubTypeId)
                    {
                        case PgOIdType.interval:
                            return describeValueArray!PgOIdInterval(writer, column, value, PgOIdType.interval);
                        case PgOIdType.point:
                            return describeValueArray!DbGeoPoint(writer, column, value, PgOIdType.point);
                        case PgOIdType.path:
                            return describeValueArray!DbGeoPath(writer, column, value, PgOIdType.path);
                        case PgOIdType.box:
                            return describeValueArray!DbGeoBox(writer, column, value, PgOIdType.box);
                        case PgOIdType.polygon:
                            return describeValueArray!DbGeoPolygon(writer, column, value, PgOIdType.polygon);
                        case PgOIdType.circle:
                            return describeValueArray!DbGeoCircle(writer, column, value, PgOIdType.circle);
                        default:
                            return unsupportDataError();
                    }
                case DbType.array:
                    return unsupportDataError();
            }

            // Never reach here
            assert(0, toName!DbType(column.type));
        }

        auto valueWriter = PgXdrWriter(connection, writer.buffer);
        // Use coerce for implicit basic type conversion
        final switch (column.type)
        {
            case DbType.boolean:
                return valueWriter.writeBool(value.coerce!bool());
            case DbType.int8:
                return valueWriter.writeInt16(value.coerce!int8());
            case DbType.int16:
                return valueWriter.writeInt16(value.coerce!int16());
            case DbType.int32:
                return valueWriter.writeInt32(value.coerce!int32());
            case DbType.int64:
                return valueWriter.writeInt64(value.coerce!int64());
            case DbType.int128:
                return valueWriter.writeInt128(value.get!BigInteger());
            case DbType.decimal:
                return valueWriter.writeDecimal!Decimal(value.get!Decimal(), column.baseType);
            case DbType.decimal32:
                return valueWriter.writeDecimal!Decimal32(value.get!Decimal32(), column.baseType);
            case DbType.decimal64:
                return valueWriter.writeDecimal!Decimal64(value.get!Decimal64(), column.baseType);
            case DbType.decimal128:
                return valueWriter.writeDecimal!Decimal128(value.get!Decimal128(), column.baseType);
            case DbType.numeric:
                return valueWriter.writeDecimal!Numeric(value.get!Numeric(), column.baseType);
            case DbType.float32:
                return valueWriter.writeFloat32(value.coerce!float32());
            case DbType.float64:
                return valueWriter.writeFloat64(value.coerce!float64());
            case DbType.date:
                return valueWriter.writeDate(value.get!Date());
            case DbType.datetime:
                return valueWriter.writeDateTime(value.get!DbDateTime());
            case DbType.datetimeTZ:
                return valueWriter.writeDateTimeTZ(value.get!DbDateTime());
            case DbType.time:
                return valueWriter.writeTime(value.get!DbTime());
            case DbType.timeTZ:
                return valueWriter.writeTimeTZ(value.get!DbTime());
            case DbType.uuid:
                return valueWriter.writeUUID(value.get!UUID());
            case DbType.fixedString:
            case DbType.string:
            case DbType.text:
            case DbType.json:
            case DbType.xml:
                return valueWriter.writeChars(value.get!string());
            case DbType.fixedBinary:
            case DbType.binary:
                return valueWriter.writeBytes(value.get!(const(ubyte)[])());
            case DbType.record:
            case DbType.unknown:
                switch (column.baseTypeId)
                {
                    case PgOIdType.interval:
                        return valueWriter.writeInterval(value.get!PgOIdInterval());
                    case PgOIdType.point:
                        return valueWriter.writeGeoPoint(value.get!DbGeoPoint());
                    case PgOIdType.path:
                        return valueWriter.writeGeoPath(value.get!DbGeoPath());
                    case PgOIdType.box:
                        return valueWriter.writeGeoBox(value.get!DbGeoBox());
                    case PgOIdType.polygon:
                        return valueWriter.writeGeoPolygon(value.get!DbGeoPolygon());
                    case PgOIdType.circle:
                        return valueWriter.writeGeoCircle(value.get!DbGeoCircle());

                    default:
                        return unsupportDataError();
                }

            case DbType.array:
                return unsupportDataError();
        }

        // Never reach here
        assert(0, toName!DbType(column.type));
    }

    final void describeValueArray(T)(ref PgWriter writer, DbNameColumn column, ref DbValue value, const(int32) elementOid)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("elementOid=", elementOid);

        auto values = value.get!(T[])();
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
            static if (is(T == bool))
                valueWriter.writeBool(values[i]);
            else static if (is(T == int8))
                valueWriter.writeInt16(values[i]);
            else static if (is(T == int16))
                valueWriter.writeInt16(values[i]);
            else static if (is(T == int32))
                valueWriter.writeInt32(values[i]);
            else static if (is(T == int64))
                valueWriter.writeInt64(values[i]);
            else static if (is(T == Decimal32) || is(T == Decimal64) || is(T == Decimal128))
                valueWriter.writeDecimal!T(values[i], column.baseType);
            else static if (is(T == float32))
                valueWriter.writeFloat32(values[i]);
            else static if (is(T == float64))
                valueWriter.writeFloat64(values[i]);
            else static if (is(T == Date))
                valueWriter.writeDate(values[i]);
            else static if (is(T == DbDateTime))
            {
                if (elementOid == PgOIdType.timestamptz)
                    valueWriter.writeDateTimeTZ(values[i]);
                else
                    valueWriter.writeDateTime(values[i]);
            }
            else static if (is(T == DbTime))
            {
                if (elementOid == PgOIdType.timetz)
                    valueWriter.writeTimeTZ(values[i]);
                else
                    valueWriter.writeTime(values[i]);
            }
            else static if (is(T == UUID))
                valueWriter.writeUUID(values[i]);
            else static if (is(T == string))
                valueWriter.writeChars(values[i]);
            else static if (is(T == ubyte[]) || is(T == const(ubyte)[]))
                valueWriter.writeBytes(values[i]);
            else static if (is(T == PgOIdInterval))
                valueWriter.writeInterval(values[i]);
            else static if (is(T == DbGeoBox))
                valueWriter.writeGeoBox(values[i]);
            else static if (is(T == DbGeoCircle))
                valueWriter.writeGeoCircle(values[i]);
            else static if (is(T == DbGeoPath))
                valueWriter.writeGeoPath(values[i]);
            else static if (is(T == DbGeoPolygon))
                valueWriter.writeGeoPolygon(values[i]);
            else static if (is(T == DbGeoPoint))
                valueWriter.writeGeoPoint(values[i]);
            else
                static assert(0, "Unsupport writing for " ~ T.toString());
        }

        valueWriter.writeArrayEnd(marker);
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        _connection = null;
    }

    final T[] readValueArray(T)(ref PgReader reader, PgCommand command, DbNameColumn column, const(int32) valueLength)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
                static assert(0, "Unsupport reading for " ~ T.toString());
        }
        return result;
    }

    final DbValue readValueError(DbNameColumn column, const(int32) valueLength, const(int32) expectedLength)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        auto msg = expectedLength > 0
            ? DbMessage.eUnexpectReadValue.fmtMessage(shortClassName(this) ~ ".readValue", toName!DbType(column.type), valueLength, expectedLength)
            : DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ ".readValue", toName!DbType(column.type));
        throw new PgException(msg, DbErrorCode.read, null);
    }

    final void writeBindMessage(ref PgWriter writer, PgCommand command, scope PgParameter[] inputParameters)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

		writer.beginMessage(PgOIdDescribeType.close);
        writer.writeChar(type);
        writer.writeCChars(name);
        writer.endMessage();
    }

    final void writeDescribeMessage(ref PgWriter writer, PgCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

		writer.beginMessage(PgOIdDescribeType.describeStatement);
        writer.writeChar(PgOIdDescribeType.portal);
        writer.writeCChars(command.name);
        writer.endMessage();
    }

    final void writeExecuteMessage(ref PgWriter writer, PgCommand command, const(DbCommandExecuteType) type)
	{
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

		writer.beginMessage(PgOIdDescribeType.executeStatement);
        writer.writeCChars(command.name);
        writer.writeInt32(type == DbCommandExecuteType.reader ? 0 : command.fetchRecordCount);
        writer.endMessage();
    }

    final void writeParseMessage(ref PgWriter writer, PgCommand command, scope const(char)[] sql,
        scope PgParameter[] inputParameters)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

		writer.beginMessage(PgOIdDescribeType.parseStatement);
        writer.writeCChars(command.name);
        writer.writeCChars(sql);
        if (inputParameters.length)
        {
            writer.writeInt16(cast(int16)inputParameters.length);
            foreach (parameter; inputParameters)
            {
                version (TraceFunction) traceFunction!("pham.db.pgdatabase")("parameter.name=", parameter.name, ", baseName=", parameter.baseName, ", baseTypeId=", parameter.baseTypeId);
                writer.writeInt32(parameter.baseTypeId); // OIDType
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
