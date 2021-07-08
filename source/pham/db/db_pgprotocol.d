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

import std.algorithm.comparison : max;
import std.ascii : LetterCase;
import std.conv : to;
import std.format : format;
import std.string : indexOf, lastIndexOf, representation;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.enum_set : toName;
import pham.utl.object : shortClassName;
import pham.db.message;
import pham.db.convert;
import pham.db.type;
import pham.db.object;
import pham.db.buffer;
import pham.db.value;
import pham.db.database : DbNameColumn;
import pham.db.pgoid;
import pham.db.pgtype;
import pham.db.pgexception;
import pham.db.pgbuffer;
import pham.db.pgauth_md5;
import pham.db.pgauth_scram;
import pham.db.pgdatabase;

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
        version (TraceFunction) dgFunctionTrace();

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
                writeSignal(PgDescribeType.sync);
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
        version (TraceFunction) dgFunctionTrace();

        auto inputParameters = command.pgInputParameters();

        auto writer = PgWriter(connection);
        // Close previous cursor
        if (command.executedCount > 1)
            writeCloseMessage(writer, PgDescribeType.portal, command.name);
        writeBindMessage(writer, command, inputParameters);
        writeDescribeMessage(writer, command);
        writeSignal(writer, PgDescribeType.flush);
        writer.flush();
    }

    final void cancelRequestWrite(int32 serverProcessId, int32 serverSecretKey)
    {
        cancelRequestWrite(serverProcessId, serverSecretKey, 1234 << 16 | 5678);
    }

    final void connectAuthenticationRead()
    {
        version (TraceFunction) dgFunctionTrace();

    receiveAgain:
        auto reader = PgReader(connection);
        switch (reader.messageType)
        {
            case 'K': // BackendKeyData
                const serverProcessId = reader.readInt32();
                const serverSecretKey = reader.readInt32();
                connection.serverInfo[DbIdentifier.serverProtocolProcessId] = to!string(serverProcessId);
                connection.serverInfo[DbIdentifier.serverProtocolSecretKey] = to!string(serverSecretKey);
                goto receiveAgain;

            case 'R': // AuthenticationXXXX
                const authType = reader.readInt32();
                version (TraceFunction) dgFunctionTrace("authType=", authType);
                switch (authType)
                {
                    case 0: // authentication successful, now wait for another messages
                        goto receiveAgain;

                    case 3: // clear-text password is required
                        connectAuthenticationSendPassword(connection.pgConnectionStringBuilder.userPassword);
                        goto receiveAgain;

                    case 5: // MD5
                        connectAuthenticationSendMD5(reader);
                        goto receiveAgain;

                    case 10: // HMAC - SCRAM-SHA-256
                        connectAuthenticationSendInitialScramSHA256(reader);
                        goto receiveAgain;

                    case 11: // HMAC - SCRAM-SHA-256
                        connectAuthenticationSendContinuedScramSHA256(reader);
                        goto receiveAgain;

                    case 12: // HMAC - SCRAM-SHA-256
                        connectAuthenticationSendFinalScramSHA256(reader);
                        goto receiveAgain;

                    default: // non supported authentication type, close connection
                        auto msg = format(DbMessage.eInvalidConnectionAuthUnsupportedName, to!string(authType));
                        throw new PgException(msg, DbErrorCode.read, 0, 0);
                }

            case 'S': // ParameterStatus
                const name = reader.readCString();
                const value = reader.readCString();
                version (TraceFunction) dgFunctionTrace("name=", name, ", value=", value);
                connection.serverInfo[name] = value;
                goto receiveAgain;

            case 'Z': // ReadyForQuery
                const trStatus = reader.readChar();
                version (TraceFunction) dgFunctionTrace("trStatus=", trStatus);
                switch (trStatus) // check for validity
                {
                    case 'E', 'I', 'T':
                        connection.serverInfo[DbIdentifier.serverProtocolTrStatus] = to!string(trStatus);
                        break;

                    default:
                        auto msg = format(DbMessage.eInvalidConnectionStatus, to!string(trStatus));
                        throw new PgException(msg, DbErrorCode.read, 0, 0);
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

    final void connectAuthenticationWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        clearServerInfo();

        auto useCSB = connection.pgConnectionStringBuilder;

        auto writer = PgWriter(connection);
        writer.startMessage('\0'); // \0=No type indicator
        writer.writeUInt32(PgId.protocolVersion);
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

    final void disconnectWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        writeSignal(PgDescribeType.disconnect);
        clearServerInfo();
    }

    final PgOIdExecuteResult executeCommandRead(PgCommand command, DbCommandExecuteType type, out PgReader reader)
    {
        // Need to return package reader to continue reading row values

        version (TraceFunction) dgFunctionTrace("type=", type);

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
                throw new PgException(DbMessage.eInvalidCommandText, DbErrorCode.read, 0, 0);

            case 'Z': // ReadyForQuery - done
                break;

            case 's': // PortalSuspended
                throw new PgException(DbMessage.eInvalidCommandSuspended, DbErrorCode.read, 0, 0);

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

    final void executeCommandWrite(PgCommand command, DbCommandExecuteType type)
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        auto writer = PgWriter(connection);
        writeExecuteMessage(writer, command, type);
        writeSignal(writer, PgDescribeType.sync);
        writeSignal(writer, PgDescribeType.flush);
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
            dgFunctionTrace("counter: ", ++counter);
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
        version (TraceFunction) dgFunctionTrace();

	receiveAgain:
        auto reader = PgReader(connection);
		switch (reader.messageType)
        {
            case '1': // ParseComplete
                return;

            case 'E': // ErrorResponse
                auto EResponse = readGenericResponse(reader);
                writeSignal(PgDescribeType.sync);
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
        version (TraceFunction) dgFunctionTrace();

        auto inputParameters = command.pgInputParameters();

        auto writer = PgWriter(connection);
        writeParseMessage(writer, command, sql, inputParameters);
        writeSignal(writer, PgDescribeType.flush);
        writer.flush();
    }

    final DbValue readValue(PgCommand command, ref PgReader reader, DbNameColumn column,
        const int32 valueLength)
    {
        version (TraceFunction)
        dgFunctionTrace("column.type=", toName!DbType(column.type),
            ", baseTypeId=", column.baseTypeId,
            ", baseSubTypeId=", column.baseSubTypeId,
            ", valueLength=", valueLength);
        version (profile) auto p = PerfFunction.create();

        PgXdrReader checkValueLength(const int32 expectedLength) @safe
        {
            if (expectedLength && expectedLength != valueLength)
                readValueError(column, valueLength, expectedLength);
            return PgXdrReader(connection, reader.readBuffer);
        }

        if (column.isArray)
        {
            final switch (column.type)
            {
                case DbType.boolean:
                    return DbValue(readValueArray!bool(command, reader, column, valueLength), column.type);
                case DbType.int8:
                    return DbValue(readValueArray!int8(command, reader, column, valueLength), column.type);
                case DbType.int16:
                    return DbValue(readValueArray!int16(command, reader, column, valueLength), column.type);
                case DbType.int32:
                    return DbValue(readValueArray!int32(command, reader, column, valueLength), column.type);
                case DbType.int64:
                    return DbValue(readValueArray!int64(command, reader, column, valueLength), column.type);
                case DbType.int128:
                    return DbValue(readValueArray!int128(command, reader, column, valueLength), column.type);
                case DbType.decimal:
                    return DbValue(readValueArray!Decimal(command, reader, column, valueLength), column.type);
                case DbType.decimal32:
                    return DbValue(readValueArray!Decimal32(command, reader, column, valueLength), column.type);
                case DbType.decimal64:
                    return DbValue(readValueArray!Decimal64(command, reader, column, valueLength), column.type);
                case DbType.decimal128:
                    return DbValue(readValueArray!Decimal128(command, reader, column, valueLength), column.type);
                case DbType.numeric:
                    return DbValue(readValueArray!Numeric(command, reader, column, valueLength), column.type);
                case DbType.float32:
                    return DbValue(readValueArray!float32(command, reader, column, valueLength), column.type);
                case DbType.float64:
                    return DbValue(readValueArray!float64(command, reader, column, valueLength), column.type);
                case DbType.date:
                    return DbValue(readValueArray!Date(command, reader, column, valueLength), column.type);
                case DbType.datetime:
                case DbType.datetimeTZ:
                    return DbValue(readValueArray!DbDateTime(command, reader, column, valueLength), column.type);
                case DbType.time:
                case DbType.timeTZ:
                    return DbValue(readValueArray!DbTime(command, reader, column, valueLength), column.type);
                case DbType.uuid:
                    return DbValue(readValueArray!UUID(command, reader, column, valueLength), column.type);
                case DbType.chars:
                case DbType.string:
                case DbType.json:
                case DbType.xml:
                case DbType.text:
                    return DbValue(readValueArray!string(command, reader, column, valueLength), column.type);
                case DbType.binary:
                    return DbValue(readValueArray!(ubyte[])(command, reader, column, valueLength), column.type);

                case DbType.record:
                case DbType.array:
                case DbType.unknown:
                    readValueError(column, valueLength, 0);
                    break;
            }

            // Never reach here
            assert(0);
        }

        final switch (column.type)
        {
            case DbType.boolean:
                return DbValue(checkValueLength(1).readBool(), column.type);
            case DbType.int8:
                return DbValue(cast(int8)(checkValueLength(2).readInt16()), column.type);
            case DbType.int16:
                return DbValue(checkValueLength(2).readInt16(), column.type);
            case DbType.int32:
                return DbValue(checkValueLength(4).readInt32(), column.type);
            case DbType.int64:
                return DbValue(checkValueLength(8).readInt64(), column.type);
            case DbType.int128:
                return DbValue(checkValueLength(16).readInt128(), column.type);
            case DbType.decimal:
                return DbValue(checkValueLength(0).readDecimal!Decimal(column.baseType), column.type);
            case DbType.decimal32:
                return DbValue(checkValueLength(0).readDecimal!Decimal32(column.baseType), column.type);
            case DbType.decimal64:
                return DbValue(checkValueLength(0).readDecimal!Decimal64(column.baseType), column.type);
            case DbType.decimal128:
                return DbValue(checkValueLength(0).readDecimal!Decimal128(column.baseType), column.type);
            case DbType.numeric:
                return DbValue(checkValueLength(0).readDecimal!Numeric(column.baseType), column.type);
            case DbType.float32:
                return DbValue(checkValueLength(4).readFloat32(), column.type);
            case DbType.float64:
                return DbValue(checkValueLength(8).readFloat64(), column.type);
            case DbType.date:
                return DbValue(checkValueLength(4).readDate(), column.type);
            case DbType.datetime:
                return DbValue(checkValueLength(8).readDateTime(), column.type);
            case DbType.datetimeTZ:
                return DbValue(checkValueLength(12).readDateTimeTZ(), column.type);
            case DbType.time:
                return DbValue(checkValueLength(8).readTime(), column.type);
            case DbType.timeTZ:
                return DbValue(checkValueLength(12).readTimeTZ(), column.type);
            case DbType.uuid:
                return DbValue(checkValueLength(16).readUUID(), column.type);
            case DbType.chars:
            case DbType.string:
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                return DbValue(checkValueLength(0).readString(valueLength), column.type);
            case DbType.binary:
                return DbValue(checkValueLength(0).readBytes(valueLength), column.type);

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                readValueError(column, valueLength, 0);
                break;
        }

        // Never reach here
        assert(0);
    }

    protected final T[] readValueArray(T)(PgCommand command, ref PgReader reader, DbNameColumn column,
        const int32 valueLength)
    {
        version (TraceFunction) dgFunctionTrace();

        int32[] lengths;
        int32 elementOid;

        PgXdrReader checkValueLength(const int32 valueLength, const int32 expectedLength) @safe
        {
            if (expectedLength && expectedLength != valueLength)
                readValueError(column, valueLength, expectedLength);
            return PgXdrReader(connection, reader.readBuffer);
        }

        int32 readDimensions() @safe
        {
            auto valueReader = PgXdrReader(connection, reader.readBuffer);

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
            else
                static assert(0, "Unsupport reading for " ~ T.toString());
        }
        return result;
    }

    protected final void readValueError(DbNameColumn column, const int32 valueLength, const int32 expectedLength)
    {
        version (TraceFunction) dgFunctionTrace();

        auto msg = expectedLength > 0
            ? format(DbMessage.eUnexpectReadValue, shortClassName(this) ~ ".readValue", toName!DbType(column.type), valueLength, expectedLength)
            : format(DbMessage.eUnsupportDataType, shortClassName(this) ~ ".readValue", toName!DbType(column.type));
        throw new PgException(msg, DbErrorCode.read, 0, 0);
    }

    final DbRowValue readValues(PgCommand command, ref PgReader reader, PgFieldList fields)
    {
        version (TraceFunction) dgFunctionTrace();
        version (profile) auto p = PerfFunction.create();

        const fieldCount = reader.readFieldCount();

        version (TraceFunction) dgFunctionTrace("fieldCount=", fieldCount, ", fields.length=", fields.length);

        size_t i = 0;
        auto result = DbRowValue(max(fieldCount, fields.length));
        foreach (field; fields)
        {
            const valueLength = i < fieldCount ? reader.readValueLength() : -1;
            if (valueLength < 0 || i >= fields.length)
                result[i++].nullify();
            else
                result[i++] = readValue(command, reader, field, valueLength);
        }
        return result;
    }

    final void unprepareCommandRead()
    {
        version (TraceFunction) dgFunctionTrace();

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

    final void unprepareCommandWrite(PgCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = PgWriter(connection);
        writeCloseMessage(writer, PgDescribeType.statement, command.name);
        writeSignal(writer, PgDescribeType.flush);
        writer.flush();
    }

    final PgGenericResponse readGenericResponse(ref PgReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

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
        version (TraceFunction) dgFunctionTrace();

        PgNotificationResponse result;
        result.pid = reader.readInt32();
        result.channel = reader.readCString();
        result.payload = reader.readCString();
        return result;
    }

    final void writeSignal(PgDescribeType signalType, int32 signalId = 4)
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
        version (TraceFunction) dgFunctionTrace("serverProcessId=", serverProcessId, ", serverSecretKey=", serverSecretKey, ", cancelKind=", cancelKind);

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

    final void clearServerInfo() nothrow @trusted
    {
        version (TraceFunction) dgFunctionTrace();
    }

    final void connectAuthenticationSendMD5(ref PgReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

        auto useCSB = connection.pgConnectionStringBuilder;
        const salt = reader.readBytes(4);
        auto auth = new PgAuthMD5();
        const password = cast(const(char)[])auth.getAuthData(useCSB.userName, useCSB.userPassword, salt);
        connectAuthenticationSendPassword(password);
    }

    final void connectAuthenticationSendContinuedScramSHA256(ref PgReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

        auto useCSB = connection.pgConnectionStringBuilder;

        const payload = reader.readBytes(reader.messageLength - int32.sizeof); // Exclude type type indicator size
        const proof = _authScramSHA256 !is null
            ? _authScramSHA256.getAuthData(useCSB.userName, useCSB.userPassword, payload)
            : null;
        if (proof.length == 0)
        {
            auto msg = format(DbMessage.eInvalidConnectionAuthServerData, PgAuthScram256.authScram256Name);
            throw new PgException(msg, DbErrorCode.read, 0, 0);
        }

        auto writer = PgWriter(connection);
        writer.startMessage('p');
        writer.writeBytesRaw(proof);
        writer.flush();
    }

    final void connectAuthenticationSendFinalScramSHA256(ref PgReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

        const payload = reader.readBytes(reader.messageLength - int32.sizeof); // Exclude type type indicator size
        if (_authScramSHA256 is null || !_authScramSHA256.verifyServerSignature(payload))
        {
            auto msg = format(DbMessage.eInvalidConnectionAuthVerificationFailed, PgAuthScram256.authScram256Name);
            throw new PgException(msg, DbErrorCode.read, 0, 0);
        }

        // Done with authentication
        _authScramSHA256.dispose();
        _authScramSHA256 = null;
    }

    final void connectAuthenticationSendInitialScramSHA256(ref PgReader reader)
    {
        _authScramSHA256 = new PgAuthScram256();

        version (TraceFunction) dgFunctionTrace("initialRequest=", _authScramSHA256.initialRequest());

        auto writer = PgWriter(connection);
        writer.startMessage('p');
        writer.writeCChars(_authScramSHA256.mechanism);
        writer.writeBytes(_authScramSHA256.initialRequest().representation);
        writer.flush();
    }

    final void connectAuthenticationSendPassword(scope const(char)[] password)
    {
        version (TraceFunction) dgFunctionTrace("password.length=", password.length, ", password=", password);

        auto writer = PgWriter(connection);
        writer.startMessage('p');
        writer.writeCChars(password);
        writer.flush();
    }

    final string convertConnectionParameter(string name, string value) nothrow
    {
        return null;
        /*
        auto useCSB = connection.pgConnectionStringBuilder;
        switch (name)
        {
            case DbParameterName.compress:
                return useCSB.compress ? "1" : null; // Return empty to skip sending since default is disabled
            case DbParameterName.connectionTimeout:
                auto connectionTimeout = useCSB.connectionTimeout.total!"seconds";
                return connectionTimeout != 0 ? to!string(connectionTimeout) : null; // Return empty to skip
            case DbParameterName.encrypt:
                final switch (useCSB.encrypt)
                {
                    case DbEncryptedConnection.disabled:
                        return "disable";
                    case DbEncryptedConnection.enabled:
                        return "allow";
                    case DbEncryptedConnection.required:
                        return "require";
                }
            case DbParameterName.receiveTimeout:
                auto receiveTimeout = useCSB.receiveTimeout.total!"msecs";
                return receiveTimeout != 0 ? to!string(receiveTimeout) : null; // Return empty to skip
            default:
                assert(0, "convertConnectionParameter? "  ~ name);
        }
        */
    }

    final void describeParameters(ref PgWriter writer, scope PgParameter[] inputParameters)
    {
        version (TraceFunction) dgFunctionTrace("inputParameters.length=", inputParameters.length);

        writer.writeInt16(cast(int16)inputParameters.length);
        foreach (param; inputParameters)
            describeValue(writer, param, param.value);
    }

    final void describeValue(ref PgWriter writer, DbNameColumn column, DbValue value)
    {
        if (value.isNull)
        {
            writer.writeInt32(-1);
            return;
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
                case DbType.chars:
                    return describeValueArray!string(writer, column, value, PgOIdType.bpchar);
                case DbType.string:
                    return describeValueArray!string(writer, column, value, PgOIdType.varchar);
                case DbType.json:
                    return describeValueArray!string(writer, column, value, PgOIdType.json);
                case DbType.xml:
                    return describeValueArray!string(writer, column, value, PgOIdType.xml);
                case DbType.text:
                    return describeValueArray!string(writer, column, value, PgOIdType.text);
                case DbType.binary:
                    return describeValueArray!(const(ubyte)[])(writer, column, value, PgOIdType.bytea);

                case DbType.record:
                case DbType.array:
                case DbType.unknown:
                    auto msg = format(DbMessage.eUnsupportDataType, shortClassName(this) ~ ".describeValue", toName!DbType(column.type));
                    throw new PgException(msg, DbErrorCode.write, 0, 0);
            }

            // Never reach here
            assert(0, toName!DbType(column.type));
        }

        auto valueWriter = PgXdrWriter(connection, writer.buffer);
        // Use coerce for implicit basic type conversion
        final switch (column.type)
        {
            case DbType.boolean:
                valueWriter.writeBool(value.coerce!bool());
                return;
            case DbType.int8:
                valueWriter.writeInt16(value.coerce!int8());
                return;
            case DbType.int16:
                valueWriter.writeInt16(value.coerce!int16());
                return;
            case DbType.int32:
                valueWriter.writeInt32(value.coerce!int32());
                return;
            case DbType.int64:
                valueWriter.writeInt64(value.coerce!int64());
                return;
            case DbType.int128:
                valueWriter.writeInt128(value.get!BigInteger());
                return;
            case DbType.decimal:
                valueWriter.writeDecimal!Decimal(value.get!Decimal(), column.baseType);
                return;
            case DbType.decimal32:
                valueWriter.writeDecimal!Decimal32(value.get!Decimal32(), column.baseType);
                return;
            case DbType.decimal64:
                valueWriter.writeDecimal!Decimal64(value.get!Decimal64(), column.baseType);
                return;
            case DbType.decimal128:
                valueWriter.writeDecimal!Decimal128(value.get!Decimal128(), column.baseType);
                return;
            case DbType.numeric:
                valueWriter.writeDecimal!Numeric(value.get!Numeric(), column.baseType);
                return;
            case DbType.float32:
                valueWriter.writeFloat32(value.coerce!float32());
                return;
            case DbType.float64:
                valueWriter.writeFloat64(value.coerce!float64());
                return;
            case DbType.date:
                valueWriter.writeDate(value.get!Date());
                return;
            case DbType.datetime:
                valueWriter.writeDateTime(value.get!DbDateTime());
                return;
            case DbType.datetimeTZ:
                valueWriter.writeDateTimeTZ(value.get!DbDateTime());
                return;
            case DbType.time:
                valueWriter.writeTime(value.get!DbTime());
                return;
            case DbType.timeTZ:
                valueWriter.writeTimeTZ(value.get!DbTime());
                return;
            case DbType.uuid:
                valueWriter.writeUUID(value.get!UUID());
                return;
            case DbType.chars:
            case DbType.string:
            case DbType.text:
            case DbType.json:
            case DbType.xml:
                valueWriter.writeChars(value.get!string());
                return;
            case DbType.binary:
                valueWriter.writeBytes(value.get!(const(ubyte)[])());
                return;

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = format(DbMessage.eUnsupportDataType, shortClassName(this) ~ ".describeValue", toName!DbType(column.type));
                throw new PgException(msg, DbErrorCode.write, 0, 0);
        }

        // Never reach here
        assert(0, toName!DbType(column.type));
    }

    final void describeValueArray(T)(ref PgWriter writer, DbNameColumn column, DbValue value, const int32 elementOid)
    {
        version (TraceFunction) dgFunctionTrace("elementOid=", elementOid);

        assert(value.isArray);

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
            else
                static assert(0, "Unsupport writing for " ~ T.toString());
        }

        valueWriter.writeArrayEnd(marker);
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        _connection = null;
    }

    final void writeBindMessage(ref PgWriter writer, PgCommand command, scope PgParameter[] inputParameters)
    {
        version (TraceFunction) dgFunctionTrace();

        writer.startMessage(PgDescribeType.bindStatement);
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

    final void writeCloseMessage(ref PgWriter writer, PgDescribeType type, scope const(char)[] name)
	{
        version (TraceFunction) dgFunctionTrace();

		writer.startMessage(PgDescribeType.close);
        writer.writeChar(type);
        writer.writeCChars(name);
        writer.endMessage();
    }

    final void writeDescribeMessage(ref PgWriter writer, PgCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

		writer.startMessage(PgDescribeType.describeStatement);
        writer.writeChar(PgDescribeType.portal);
        writer.writeCChars(command.name);
        writer.endMessage();
    }

    final void writeExecuteMessage(ref PgWriter writer, PgCommand command, DbCommandExecuteType type)
	{
        version (TraceFunction) dgFunctionTrace();

		writer.startMessage(PgDescribeType.executeStatement);
        writer.writeCChars(command.name);
        writer.writeInt32(type == DbCommandExecuteType.reader ? 0 : command.fetchRecordCount);
        writer.endMessage();
    }

    final void writeParseMessage(ref PgWriter writer, PgCommand command, scope const(char)[] sql, scope PgParameter[] inputParameters)
    {
        version (TraceFunction) dgFunctionTrace();

		writer.startMessage(PgDescribeType.parseStatement);
        writer.writeCChars(command.name);
        writer.writeCChars(sql);
        if (inputParameters.length)
        {
            writer.writeInt16(cast(int16)inputParameters.length);
            foreach (parameter; inputParameters)
            {
                version (TraceFunction) dgWriteln("parameter: ", parameter.name, ", b: ", parameter.baseName, ", t: ", parameter.baseTypeId);
                writer.writeInt32(parameter.baseTypeId); // OIDType
            }
        }
        else
            writer.writeInt16(0);
        writer.endMessage();
    }

    final void writeSignal(ref PgWriter writer, PgDescribeType signalType, int32 signalId = 4)
    {
        writer.writeSignal(signalType, signalId);
    }

private:
    PgConnection _connection;
    PgAuthScram256 _authScramSHA256;
}


// Any below codes are private
private:
