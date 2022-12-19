/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.myprotocol;

import std.algorithm.comparison : max;
import std.array : Appender;
import std.conv : to;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.bit_array : BitArrayImpl, bitLengthToElement;
import pham.utl.enum_set : toName;
import pham.utl.object : shortClassName, VersionString;
import pham.db.buffer;
import pham.db.database : DbNameColumn;
import pham.db.message;
import pham.db.object;
import pham.db.parser;
import pham.db.type;
import pham.db.util;
import pham.db.value;
import pham.db.myauth;
import pham.db.mybuffer;
import pham.db.myconvert;
import pham.db.mydatabase;
import pham.db.myexception;
import pham.db.myoid;
import pham.db.mytype;

struct MyConnectingStateInfo
{
nothrow @safe:

    MyAuth auth;
    CipherBuffer authData;
    CipherBuffer serverAuthData;
    string authMethod;
    string serverVersion;
    uint32 connectionFlags;
    int32 protocolProcessId;
    int32 protocolVersion;
    uint32 serverCapabilities;
    uint32 serverStatus;
    uint8 serverCharSetIndex;
    DbEncryptedConnection canCryptedConnection;
}

class MyProtocol : DbDisposableObject
{
@safe:

public:
    this(MyConnection connection) nothrow pure
    {
        this._connection = connection;
    }

    final MyOkResponse connectAuthenticationRead(ref MyConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        enum AuthKind : ubyte { ok, cont, change, }
        AuthKind kind;

        {
            auto packageData = readPackageData();
            kind = packageData.isAuthSha2Caching(stateInfo.authMethod)
                ? AuthKind.cont
                : (packageData.isAuthSwitch() ? AuthKind.change : AuthKind.ok);
            auto reader = MyXdrReader(connection, packageData.buffer);
            final switch(kind)
            {
                case AuthKind.ok:
                    return readOkResponse(reader);

                case AuthKind.cont:
                    auto allData = reader.buffer.consumeAll();
                    stateInfo.serverAuthData = allData[1..$];
                    break;

                case AuthKind.change:
                    if (packageData.isLastPacket())
                    {
                        auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage("Old password");
                        throw new MyException(msg, DbErrorCode.connect, null);
                    }
                    const indicator = reader.readUInt8();
                    assert(indicator == 0xfe);
                    const newAuthMethod = reader.readCString();
                    stateInfo.serverAuthData = reader.buffer.consumeAll();
                    version (TraceFunction) traceFunction!("pham.db.mydatabase")("newAuthMethod=", newAuthMethod, ", stateInfo.authMethod=", stateInfo.authMethod);
                    if (stateInfo.authMethod != newAuthMethod)
                    {
                        stateInfo.authMethod = newAuthMethod;
                        stateInfo.auth = createAuth(stateInfo);
                    }
                    break;
            }

            return handleAuthenticationChallenge(stateInfo, kind == AuthKind.change);
        }
    }

    final void connectAuthenticationWrite(ref MyConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("stateInfo.connectionFlags=", stateInfo.connectionFlags);

        auto useCSB = connection.myConnectionStringBuilder;

        ubyte[23] fillers;
        auto writer = MyXdrWriter(connection, maxSinglePackage);

        if (stateInfo.authMethod.length != 0)
        {
            stateInfo.auth = createAuth(stateInfo);
            stateInfo.auth.getPassword(useCSB.userName, useCSB.userPassword, stateInfo.authData);
        }

        writer.beginPackage(++sequenceByte);
        writer.writeUInt32(stateInfo.connectionFlags);
        writer.writeUInt32(maxSinglePackage);
        writer.writeInt8(myUTF8CharSetId);
        writer.writeOpaqueBytes(fillers[]);

        // SSL?
        if (stateInfo.canCryptedConnection != DbEncryptedConnection.disabled)
        {
            writer.flush();

            version (TraceFunction) traceFunction!("pham.db.mydatabase")("Bind SSL");
            auto rs = connection.doOpenSSL();
            if (rs.isError)
            {
                version (TraceFunction) traceFunction!("pham.db.mydatabase")("SSL failed code=", rs.errorCode, ", message=", rs.errorMessage);
                connection.throwConnectError(rs.errorCode, rs.errorMessage);
            }

            connection.serverInfo[DbServerIdentifier.protocolEncrypted] = toName(stateInfo.canCryptedConnection);

            writer.beginPackage(++sequenceByte);
            writer.writeUInt32(stateInfo.connectionFlags);
            writer.writeUInt32(maxSinglePackage);
            writer.writeInt8(myUTF8CharSetId);
            writer.writeOpaqueBytes(fillers[]);
        }

        writer.writeCString(useCSB.userName);

        if (stateInfo.authData.length)
            writer.writeOpaqueBytes(stateInfo.authData[]);
        else
            writer.writeInt8(0);

        if ((stateInfo.connectionFlags & MyCapabilityFlags.connectWithDb) != 0)
            writer.writeCString(useCSB.databaseName);

        if ((stateInfo.connectionFlags & MyCapabilityFlags.pluginAuth) != 0)
            writer.writeCString(stateInfo.authMethod);

        // When the flag is turned on, must send even if it is empty
        if ((stateInfo.connectionFlags & MyCapabilityFlags.connectAttrs) != 0)
        {
            Appender!string connectionAttrs;
            connectionAttrs.reserve(1_000);
            foreach (name, value; useCSB.customAttributes.values)
            {
                connectionAttrs.put(cast(char)truncate(name.length, ubyte.max));
                connectionAttrs.put(truncate(name, ubyte.max));
                connectionAttrs.put(cast(char)truncate(value.length, ubyte.max));
                connectionAttrs.put(truncate(value, ubyte.max));
            }
            writer.writeString(connectionAttrs.data);
        }

        writer.flush();
    }

    final void connectGreetingRead(ref MyConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto useCSB = connection.myConnectionStringBuilder;
        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);

        stateInfo.protocolVersion = reader.readUInt8();
        stateInfo.serverVersion = reader.readCString();
        stateInfo.protocolProcessId = reader.readInt32();
        this._protocolVersion = stateInfo.protocolVersion;
        connection.serverInfo[DbServerIdentifier.protocolVersion] = to!string(stateInfo.protocolVersion);
        connection.serverInfo[DbServerIdentifier.dbVersion] = stateInfo.serverVersion.idup;
        connection.serverInfo[DbServerIdentifier.protocolProcessId] = to!string(stateInfo.protocolProcessId);

        ubyte[] seedPart1 = reader.readCBytes();

        // read in Server capabilities if they are provided
        stateInfo.serverCapabilities = reader.readUInt16();

        /* New protocol with 16 bytes to describe server characteristics */
        stateInfo.serverCharSetIndex = reader.readUInt8();
        stateInfo.serverStatus = reader.readUInt16();

        // Since 5.5, high bits of server caps are stored after status.
        // Previously, it was part of reserved always 0x00 13-byte filler.
        uint32 serverCapsHigh = reader.readUInt16();
        stateInfo.serverCapabilities |= (serverCapsHigh << 16);
        connection.serverInfo[DbServerIdentifier.capabilityFlag] = to!string(stateInfo.serverCapabilities);

        reader.advance(11);

        ubyte[] seedPart2 = reader.readCBytes();
        stateInfo.serverAuthData = seedPart1 ~ seedPart2;

        auto serverAuthMethod = (stateInfo.serverCapabilities & MyCapabilityFlags.pluginAuth) != 0
            ? reader.readCString()
            : null;
        auto settingAuthMethod = useCSB.integratedSecurityName();
        stateInfo.authMethod = settingAuthMethod.length ? settingAuthMethod : serverAuthMethod;

        calculateConnectionFlags(stateInfo);
    }

    final void deallocateCommandWrite(MyCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.closeStmt);
        writer.writeInt32(command.myHandle);
        writer.flush();
    }

    final void disconnectWrite()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.quit);
        writer.flush();
    }

    final MyCommandResultResponse executeCommandDirectRead(MyCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);
        return readCommandResultResponse(null, reader);
    }

    final void executeCommandDirectWrite(MyCommand command, scope const(char)[] sql)
    in
    {
        assert(sql.length != 0);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        const lisQueryAttributes = isQueryAttributes;
        const hasCustomAttributes = lisQueryAttributes && command !is null ? command.customAttributes.length : 0;
        const hasParameters = command !is null ? command.hasParameters : 0;

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.query);

        if (isQueryAttributes)
        {
            writer.writeLength(hasParameters + hasCustomAttributes);
            writer.writeUInt8(1);
        }

        void writeParameters1()
        {
            DbWriteBuffer types = connection.acquireParameterWriteBuffer();
            DbWriteBuffer values = connection.acquireParameterWriteBuffer();
            scope (exit)
            {
                connection.releaseParameterWriteBuffer(values);
                connection.releaseParameterWriteBuffer(types);
            }

            auto nullBitmap = BitArrayImpl!ubyte(hasParameters);
            auto typeWriter = MyXdrWriter(null, maxSinglePackage, types);
            auto valueWriter = MyXdrWriter(null, maxSinglePackage, values);

            if (hasParameters)
                describeParameters(typeWriter, valueWriter, nullBitmap, cast(MyParameterList)command.parameters, lisQueryAttributes);

            if (hasCustomAttributes)
                describeAttributes(typeWriter, valueWriter, command.customAttributes, lisQueryAttributes);

            version (TraceFunction) traceFunction!("pham.db.mydatabase")("nullBitmap[].length=", nullBitmap[].length, ", types.length=", types.peekBytes().length, ", values.length=", values.peekBytes().length);

            writer.writeOpaqueBytes(nullBitmap[]);
            writer.writeUInt8(1); // new_params_bind_flag
            writer.writeOpaqueBytes(types.peekBytes());
            writer.writeOpaqueBytes(values.peekBytes());
        }

        void writeParameters2()
        {
            size_t parameterIndex = 0;
            auto tokenizer = DbTokenizer!(const(char)[])(sql);
            while (!tokenizer.empty)
            {
                bool writeTokenAsIs = true;
                const isParameterToken = tokenizer.kind == DbTokenKind.parameterUnnamed
                    || tokenizer.kind == DbTokenKind.parameterNamed;

                if (isParameterToken)
                {
                     // TODO search by name for DbTokenKind.parameterNamed?
                    if (parameterIndex < hasParameters)
                    {
                        auto parameter = command.parameters[parameterIndex];
                        if (parameter.isInput())
                        {
                            describeParameter(writer, cast(MyParameter)parameter);
                            writeTokenAsIs = false;
                        }
                    }
                    parameterIndex++;
                }

                if (writeTokenAsIs)
                {
                    if (isParameterToken)
                        writer.writeOpaqueChars(tokenizer.parameterIndicator);
                    writer.writeOpaqueChars(tokenizer.front);
                }

                tokenizer.popFront();
            }
        }

        if (hasParameters || hasCustomAttributes)
        {
            writeParameters1();
            writeParameters2();
        }
        else
            writer.writeOpaqueChars(sql);

        writer.flush();
    }

    final MyCommandResultResponse executeCommandRead(MyCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);
        return readCommandResultResponse(command, reader);
    }

    // For prepared statement
    final void executeCommandWrite(MyCommand command, DbCommandExecuteType type)
    in
    {
        assert(command !is null);
        assert(command.prepared);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("type=", type);

        const lisQueryAttributes = isQueryAttributes;
        const hasCustomAttributes = lisQueryAttributes ? command.customAttributes.length : 0;

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.execute);
        writer.writeInt32(command.myHandle);
        writer.writeUInt8(lisQueryAttributes ? 8 : 0); // flags - 8=parameterCountAvailable
        writer.writeInt32(1); // iteration count

        if (lisQueryAttributes)
            writer.writeLength(command.hasParameters + hasCustomAttributes);

		if (command.hasParameters || hasCustomAttributes)
		{
            DbWriteBuffer types = connection.acquireParameterWriteBuffer();
            DbWriteBuffer values = connection.acquireParameterWriteBuffer();
            scope (exit)
            {
                connection.releaseParameterWriteBuffer(values);
                connection.releaseParameterWriteBuffer(types);
            }

            auto nullBitmap = BitArrayImpl!ubyte(command.hasParameters);
            auto typeWriter = MyXdrWriter(null, maxSinglePackage, types);
            auto valueWriter = MyXdrWriter(null, maxSinglePackage, values);

            if (command.hasParameters)
                describeParameters(typeWriter, valueWriter, nullBitmap, cast(MyParameterList)command.parameters, lisQueryAttributes);

            if (hasCustomAttributes)
                describeAttributes(typeWriter, valueWriter, command.customAttributes, lisQueryAttributes);

            version (TraceFunction) traceFunction!("pham.db.mydatabase")("nullBitmap[].length=", nullBitmap[].length, ", types.length=", types.peekBytes().length, ", values.length=", values.peekBytes().length);

            writer.writeOpaqueBytes(nullBitmap[]);
            writer.writeUInt8(1); // new_params_bind_flag
            writer.writeOpaqueBytes(types.peekBytes());
            writer.writeOpaqueBytes(values.peekBytes());
        }

        writer.flush();
    }

    final MyOkResponse pingRead()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        return readOkResponse();
    }

    final void pingWrite()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.ping);
        writer.flush();
    }

    final MyCommandPreparedResponse prepareCommandRead(MyCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        MyCommandPreparedResponse result;
        prepareCommandReadHeader(command, result);
        if (result.parameterCount > 0)
            prepareCommandReadParameters(command, result);
        if (result.fieldCount > 0)
            prepareCommandReadFields(command, result);
        return result;
    }

    final prepareCommandWrite(MyCommand command, scope const(char)[] sql)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.prepare);
        writer.writeOpaqueChars(sql);
        writer.flush();
    }

    /**
     * Read any pending rows and returns number of rows skipped/purged
     */
    final size_t purgePendingRows()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        size_t result;
        while (true)
        {
            auto rowPackage = readPackageData();
            if (rowPackage.isEOF())
                break;
            result++;
        }
        return result;
    }

    final MyOkResponse setDatabaseRead()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);
        return readOkResponse(reader);
    }

    final void setDatabaseWrite(scope const(char)[] databaseName)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("databaseName=", databaseName);

        auto writer = MyXdrWriter(connection, maxSinglePackage);
        writer.beginPackage(0);
        writer.writeCommand(MyCmdId.initDb);
        writer.writeOpaqueChars(databaseName);
        writer.flush();
    }

    final MyCommandResultResponse readCommandResultResponse(MyCommand command, ref MyXdrReader reader)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        MyCommandResultResponse result;

        result.fieldCount = cast(int32)reader.readLength();
        if (result.fieldCount == -1)
        {
            // Upload local file data....
            //TODO
        }
        else if (result.fieldCount == 0)
            result.okResponse = readOkResponse(reader);
        else
        {
            readCommandResultReadFields(command, result);
            readEOF();
        }

        return result;
    }

    final MyEOFResponse readEOF()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto packageData = readPackageData();
        if (!packageData.isEOF())
            throw new MyException("Expected end of data packet", DbErrorCode.read, null);
        auto reader = MyXdrReader(connection, packageData.buffer);

        MyEOFResponse result;

        reader.readUInt8(); // read off the indicator - 0xfe
        if (!reader.empty)
        {
            result.warningCount = reader.readInt16();
            result.statusFlags = cast(MyStatusFlags)reader.readUInt16(); // status flags
        }

        return result;
    }

    final MyOkResponse readOkResponse()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);
        return readOkResponse(reader);
    }

    final MyOkResponse readOkResponse(ref MyXdrReader reader)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("reader");

        MyOkResponse result;

        result.affectedRows = reader.readLength(); // affected rows
        result.lastInsertId = reader.readLength(); // last insert-id
        result.statusFlags = cast(MyStatusFlags)reader.readUInt16(); // status flags
        result.warningCount = reader.readInt16(); // warning count
        result.info = !reader.empty ? reader.readString() : null; // info

        if ((result.statusFlags & MyStatusFlags.sessionStateChanged) != 0)
        {
            const totalLength = reader.readPackedInt32();
            if (totalLength > 0)
            {
                const end = reader.buffer.offset + totalLength;
                while (reader.buffer.offset < end)
                {
                    auto trackType = cast(MySessionTrackType)reader.readInt8();
                    reader.readInt8(); // dataLength

                    // for specification of the packet structure, see WL#4797
                    final switch (trackType) with (MySessionTrackType)
                    {
                        case systemVariables:
                            result.addTracker(trackType, reader.readShortString(), reader.readShortString());
                            break;

                        case GTIDS:
                            reader.readInt8(); // skip the byte reserved for the encoding specification, see WL#6128
                            result.addTracker(trackType, reader.readShortString(), null);
                            break;

                        case schema:
                        case transactionCharacteristics:
                        case transactionState:
                            result.addTracker(trackType, reader.readShortString(), null);
                            break;

                        case stateChange:
                            result.addTracker(trackType, reader.readString(), null);
                            break;
                    }
                }
            }
        }

        return result;
    }

    final bool readRow(out MyReader rowPackage)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        rowPackage = readPackageData();
        return !rowPackage.isEOF();
    }

    final DbValue readValue(ref MyXdrReader reader, MyCommand command, DbNameColumn column, const(bool) readFieldLength)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")(column.traceString(), ", readFieldLength=", readFieldLength);
        version (profile) debug auto p = PerfFunction.create();

        DbValue unsupportDataError()
        {
            auto msg = DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ ".readValue", toName!DbType(column.type));
            throw new MyException(msg, DbErrorCode.read, null);
        }

        const dbType = column.type;
        final switch (dbType)
        {
            case DbType.boolean:
                return DbValue(reader.readBoolValue(readFieldLength), dbType);
            case DbType.int8:
                return DbValue(reader.readInt8Value(readFieldLength), dbType);
            case DbType.int16:
                return DbValue(reader.readInt16Value(readFieldLength), dbType);
            case DbType.int32:
                return DbValue(reader.readInt32Value(readFieldLength), dbType);
            case DbType.int64:
                return DbValue(reader.readInt64Value(readFieldLength), dbType);
            case DbType.int128:
                return unsupportDataError();
            case DbType.decimal:
                return DbValue(reader.readDecimalValue!Decimal(readFieldLength), dbType);
            case DbType.decimal32:
                return DbValue(reader.readDecimalValue!Decimal32(readFieldLength), dbType);
            case DbType.decimal64:
                return DbValue(reader.readDecimalValue!Decimal64(readFieldLength), dbType);
            case DbType.decimal128:
                return DbValue(reader.readDecimalValue!Decimal128(readFieldLength), dbType);
            case DbType.numeric:
                return DbValue(reader.readDecimalValue!Numeric(readFieldLength), dbType);
            case DbType.float32:
                return DbValue(reader.readFloat32Value(readFieldLength), dbType);
            case DbType.float64:
                return DbValue(reader.readFloat64Value(readFieldLength), dbType);
            case DbType.date:
                return DbValue(reader.readDateValue(readFieldLength), dbType);
            case DbType.datetime:
                return DbValue(reader.readDateTimeValue(readFieldLength), dbType);
            case DbType.datetimeTZ:
                return DbValue(reader.readDateTimeValue(readFieldLength), dbType); //TODO timezone
            case DbType.time:
                return DbValue(reader.readTimeValue(readFieldLength), dbType);
            case DbType.timeTZ:
                return DbValue(reader.readTimeValue(readFieldLength), dbType); //TODO timezone
            case DbType.uuid:
                return DbValue(reader.readUUIDValue(readFieldLength), dbType);
            case DbType.fixedString:
            case DbType.string:
                return DbValue(reader.readStringValue(readFieldLength), dbType);
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                auto textValue = reader.readStringValue(readFieldLength);
                return textValue.length != 0 ? DbValue(textValue, dbType) : DbValue.dbNull(dbType);
            case DbType.fixedBinary:
            case DbType.binary:
                auto binaryValue = reader.readBytesValue(readFieldLength);
                return binaryValue.length != 0 ? DbValue(binaryValue, dbType) : DbValue.dbNull(dbType);
            case DbType.record:
            case DbType.unknown:
                if (column.baseTypeId == MyTypeId.geometry)
                    return DbValue(reader.readGeometryValue(readFieldLength), dbType);
                return unsupportDataError();
            case DbType.array:
                return unsupportDataError();
        }

        // Never reach here
        assert(0, toName!DbType(dbType));
    }

    final DbRowValue readValues(ref MyReader rowPackage, MyCommand command, MyFieldList fields)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("fieldCount=", fields.length);
        version (profile) debug auto p = PerfFunction.create();

        const hasNullBitmapBytes = command.prepared;
        auto reader = MyXdrReader(connection, rowPackage.buffer);

        const nullBitmap = hasNullBitmapBytes ? readNullBitmaps(reader, fields.length) : BitArrayImpl!ubyte(0);

        auto result = DbRowValue(fields.length);

        const readFieldLength = !hasNullBitmapBytes;
        foreach (i; 0..fields.length)
        {
            if (hasNullBitmapBytes && nullBitmap[i + 2])
            {
                result[i].nullify();
                continue;
            }

            result[i] = readValue(reader, command, fields[i], readFieldLength);
        }

        return result;
    }

    @property final MyConnection connection() nothrow pure
    {
        return _connection;
    }

    @property final uint32 connectionFlags() const @nogc nothrow pure
    {
        return _connectionFlags;
    }

    @property final int32 protocolVersion() const @nogc nothrow pure
    {
        return _protocolVersion;
    }

protected:
    final void calculateConnectionFlags(ref MyConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto useCSB = connection.myConnectionStringBuilder;

        // We always allow multiple result sets
        stateInfo.connectionFlags = MyCapabilityFlags.multiResults;

        // allow load data local infile
        //if (useCSB.AllowLoadLocalInfile || useCSB.AllowLoadLocalInfileInPath.length > 0)
        //  stateInfo.connectionFlags |= MyCapabilityFlags.localFiles;

        //if (!useCSB.UseAffectedRows)
        //    stateInfo.connectionFlags |= MyCapabilityFlags.foundRows;

        stateInfo.connectionFlags |= MyCapabilityFlags.protocol41;

        // Need this to get server status values
        stateInfo.connectionFlags |= MyCapabilityFlags.transactions;

        // user allows/disallows batch statements
        if (useCSB.allowBatch)
            stateInfo.connectionFlags |= MyCapabilityFlags.multiStatements;

        // if the server allows it, tell it that we want long column info
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.longFlag) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.longFlag;

        // if the server supports it and it was requested, then turn on compression
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.compress) != 0 && useCSB.compress)
          stateInfo.connectionFlags |= MyCapabilityFlags.compress;

        // for long passwords
        stateInfo.connectionFlags |= MyCapabilityFlags.longPassword;

        // did the user request an interactive session?
        //if (useCSB.InteractiveSession)
        //  connectionFlags |= MyCapabilityFlags.interactive;

        // if the server allows it and a database was specified, then indicate
        // that we will connect with a database name
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.connectWithDb) != 0 && useCSB.databaseName.length != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.connectWithDb;

        // if the server is requesting a secure connection, then we oblige
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.secureConnection) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.secureConnection;

        // if the server supports output parameters, then we do too
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.psMutiResults) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.psMutiResults;

        if ((stateInfo.serverCapabilities & MyCapabilityFlags.pluginAuth) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.pluginAuth;

        // if the server supports connection attributes
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.connectAttrs) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.connectAttrs;

        version (none) // Not yet implementation
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.canHandleExpiredPassword) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.canHandleExpiredPassword;

        // if the server supports query attributes
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.queryAttributes) != 0)
            stateInfo.connectionFlags |= MyCapabilityFlags.queryAttributes;

        // need this to get server session trackers
        stateInfo.connectionFlags |= MyCapabilityFlags.sessionTrack;

        // if the server is capable of SSL and the user is requesting SSL
        stateInfo.canCryptedConnection = canCryptedConnection(stateInfo);
        if (stateInfo.canCryptedConnection != DbEncryptedConnection.disabled)
            stateInfo.connectionFlags |= MyCapabilityFlags.ssl; // | MyCapabilityFlags.sessionTrack;

        _connectionFlags = stateInfo.connectionFlags;
    }

    final DbEncryptedConnection canCryptedConnection(ref MyConnectingStateInfo stateInfo) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto useCSB = connection.myConnectionStringBuilder;

        final switch (useCSB.encrypt)
        {
            case DbEncryptedConnection.disabled:
                return DbEncryptedConnection.disabled;
            case DbEncryptedConnection.enabled:
                return (stateInfo.serverCapabilities & MyCapabilityFlags.ssl) != 0 && useCSB.hasSSL()
                    ? DbEncryptedConnection.enabled
                    : DbEncryptedConnection.disabled;
            case DbEncryptedConnection.required:
                return DbEncryptedConnection.required;
        }
    }

    final void clearServerInfo()
    {
        _connectionFlags = 0;
        _protocolVersion = 0;
    }

    final MyAuth createAuth(ref MyConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("stateInfo.authMethod=", stateInfo.authMethod);

        auto authMap = MyAuth.findAuthMap(stateInfo.authMethod);
        if (!authMap.isValid())
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(stateInfo.authMethod);
            throw new MyException(msg, DbErrorCode.read, null);
        }
        auto result = cast(MyAuth)authMap.createAuth();
        result.isSSLConnection = stateInfo.canCryptedConnection != DbEncryptedConnection.disabled;
        result.serverVersion = VersionString(stateInfo.serverVersion);
        result.setServerSalt(stateInfo.serverAuthData[]);
        return result;
    }

    final void describeAttributes(ref MyXdrWriter typeWriter, ref MyXdrWriter valueWriter,
        ref DbCustomAttributeList attributes, const(bool) queryAttributes)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        foreach (name, value; attributes.values)
        {
            typeWriter.writeUInt8(MyTypeId.varChar);
            typeWriter.writeUInt8(myTypeSignedValue);
            if (queryAttributes)
                typeWriter.writeString(name);
            valueWriter.writeString(value);
        }
    }

    final void describeParameter(ref MyXdrWriter writer, MyParameter parameter)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        if (parameter.isNull)
            writer.writeOpaqueChars("NULL");
        else
            describeValue(writer, parameter, parameter.value);
    }

    final void describeParameter(ref MyXdrWriter typeWriter, ref MyXdrWriter valueWriter, ref BitArrayImpl!ubyte nullBitmap,
        MyParameter parameter, const(size_t) parameterIndex, const(bool) queryAttributes)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        if (parameter.hasInputValue())
        {
            describeValue(typeWriter, valueWriter, parameter, parameter.value, queryAttributes);
        }
        else
        {
            nullBitmap[parameterIndex] = true;
            typeWriter.writeUInt8(MyTypeId.null_);
            typeWriter.writeUInt8(myTypeSignedValue);
            if (queryAttributes)
                typeWriter.writeString(parameter.name);
        }
    }

    final void describeParameters(ref MyXdrWriter typeWriter, ref MyXdrWriter valueWriter, ref BitArrayImpl!ubyte nullBitmap,
        MyParameterList parameters, const(bool) queryAttributes)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        size_t i;
        foreach (parameter; parameters)
        {
            describeParameter(typeWriter, valueWriter, nullBitmap, cast(MyParameter)parameter, i++, queryAttributes);
        }
    }

    final void describeValue(ref MyXdrWriter writer, DbNameColumn column, ref DbValue value)
    in
    {
        assert(!value.isNull);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("type=", toName!DbType(column.type), ", values.offset=", writer.buffer.offset);

        void unsupportDataError()
        {
            auto msg = DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ ".describeValue", toName!DbType(column.type));
            throw new MyException(msg, DbErrorCode.write, null);
        }

        if (column.isArray)
            return unsupportDataError();

        // Use coerce for implicit basic type conversion
        final switch (column.type)
        {
            case DbType.boolean:
                int8 v = value.coerce!bool() ? 1 : 0;
                return writer.writeInt32String(v);
            case DbType.int8:
            case DbType.int16:
            case DbType.int32:
                return writer.writeInt32String(value.coerce!int32());
            case DbType.int64:
                return writer.writeInt64String(value.coerce!int64());
            case DbType.int128:
                return unsupportDataError();
            case DbType.decimal:
                return writer.writeDecimalString!Decimal(value.get!Decimal());
            case DbType.decimal32:
                return writer.writeDecimalString!Decimal32(value.get!Decimal32());
            case DbType.decimal64:
                return writer.writeDecimalString!Decimal64(value.get!Decimal64());
            case DbType.decimal128:
                return writer.writeDecimalString!Decimal128(value.get!Decimal128());
            case DbType.numeric:
                return writer.writeDecimalString!Numeric(value.get!Numeric());
            case DbType.float32:
                return writer.writeFloat32String(value.coerce!float32());
            case DbType.float64:
                return writer.writeFloat64String(value.coerce!float64());
            case DbType.date:
                return writer.writeDateString(value.get!DbDate());
            case DbType.datetime:
            case DbType.datetimeTZ:
                return writer.writeDateTimeString(value.get!DbDateTime());
            case DbType.time:
            case DbType.timeTZ:
                return writer.writeTimeString(value.get!DbTime());
            case DbType.uuid:
                return writer.writeUUIDString(value.get!UUID());
            case DbType.fixedString:
            case DbType.string:
            case DbType.json:
            case DbType.text:
            case DbType.xml:
                return writer.writeStringString(value.get!string());
            case DbType.fixedBinary:
            case DbType.binary:
                return writer.writeBytesString(value.get!(const(ubyte)[])());
            case DbType.record:
            case DbType.unknown:
                if (column.baseTypeId == MyTypeId.geometry)
                {
                    return writer.writeGeometryString(value.get!MyGeometry());
                }
                return unsupportDataError();

            case DbType.array:
                return unsupportDataError();
        }

        // Never reach here
        assert(0, toName!DbType(column.type));
    }

    final void describeValue(ref MyXdrWriter typeWriter, ref MyXdrWriter valueWriter,
        DbNameColumn column, ref DbValue value, const(bool) queryAttributes)
    in
    {
        assert(!value.isNull);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("type=", toName!DbType(column.type), ", values.offset=", valueWriter.buffer.offset);

        void unsupportDataError()
        {
            auto msg = DbMessage.eUnsupportDataType.fmtMessage(shortClassName(this) ~ ".describeValue", toName!DbType(column.type));
            throw new MyException(msg, DbErrorCode.write, null);
        }

        if (column.isArray)
            return unsupportDataError();

        void writeType(const(MyTypeId) typeId, const(ubyte) typeSign)
        {
            typeWriter.writeUInt8(typeId);
            typeWriter.writeUInt8(typeSign);
            if (queryAttributes)
                typeWriter.writeString(column.name);
        }

        // Use coerce for implicit basic type conversion
        final switch (column.type)
        {
            case DbType.boolean:
                writeType(MyTypeId.int8, myTypeSignedValue);
                return valueWriter.writeBool(value.coerce!bool());
            case DbType.int8:
                writeType(MyTypeId.int8, myTypeSignedValue);
                return valueWriter.writeInt8(value.coerce!int8());
            case DbType.int16:
                writeType(MyTypeId.int16, myTypeSignedValue);
                return valueWriter.writeInt16(value.coerce!int16());
            case DbType.int32:
                writeType(MyTypeId.int32, myTypeSignedValue);
                return valueWriter.writeInt32(value.coerce!int32());
            case DbType.int64:
                writeType(MyTypeId.int64, myTypeSignedValue);
                return valueWriter.writeInt64(value.coerce!int64());
            case DbType.int128:
                return unsupportDataError();
                //return valueWriter.writeInt128(value.get!BigInteger());
            case DbType.decimal:
                writeType(MyTypeId.decimal, myTypeSignedValue);
                return valueWriter.writeDecimal!Decimal(value.get!Decimal());
            case DbType.decimal32:
                writeType(MyTypeId.decimal, myTypeSignedValue);
                return valueWriter.writeDecimal!Decimal32(value.get!Decimal32());
            case DbType.decimal64:
                writeType(MyTypeId.decimal, myTypeSignedValue);
                return valueWriter.writeDecimal!Decimal64(value.get!Decimal64());
            case DbType.decimal128:
                writeType(MyTypeId.decimal, myTypeSignedValue);
                return valueWriter.writeDecimal!Decimal128(value.get!Decimal128());
            case DbType.numeric:
                writeType(MyTypeId.decimal, myTypeSignedValue);
                return valueWriter.writeDecimal!Numeric(value.get!Numeric());
            case DbType.float32:
                writeType(MyTypeId.float32, myTypeSignedValue);
                return valueWriter.writeFloat32(value.coerce!float32());
            case DbType.float64:
                writeType(MyTypeId.float64, myTypeSignedValue);
                return valueWriter.writeFloat64(value.coerce!float64());
            case DbType.date:
                writeType(MyTypeId.date, myTypeSignedValue);
                return valueWriter.writeDate(value.get!Date());
            case DbType.datetime:
                writeType(MyTypeId.datetime, myTypeSignedValue);
                return valueWriter.writeDateTime(value.get!DbDateTime());
            case DbType.datetimeTZ:
                writeType(MyTypeId.datetime, myTypeSignedValue);
                // TODO convert timezone
                return valueWriter.writeDateTime(value.get!DbDateTime());
            case DbType.time:
                writeType(MyTypeId.time, myTypeSignedValue);
                return valueWriter.writeTime(value.get!DbTime());
            case DbType.timeTZ:
                writeType(MyTypeId.time, myTypeSignedValue);
                // TODO convert timezone
                return valueWriter.writeTime(value.get!DbTime());
            case DbType.uuid:
                writeType(MyTypeId.fixedVarChar, myTypeSignedValue);
                return valueWriter.writeUUID(value.get!UUID());
            case DbType.fixedString:
                writeType(MyTypeId.fixedVarChar, myTypeSignedValue);
                return valueWriter.writeString(value.get!string());
            case DbType.string:
                writeType(MyTypeId.varChar, myTypeSignedValue);
                return valueWriter.writeString(value.get!string());
            case DbType.json:
                writeType(MyTypeId.json, myTypeSignedValue);
                return valueWriter.writeString(value.get!string());
            case DbType.text:
            case DbType.xml:
                writeType(MyTypeId.longBlob, myTypeSignedValue);
                return valueWriter.writeString(value.get!string());
            case DbType.fixedBinary:
            case DbType.binary:
                writeType(MyTypeId.longBlob, myTypeSignedValue);
                return valueWriter.writeBytes(value.get!(const(ubyte)[])());
            case DbType.record:
            case DbType.unknown:
                if (column.baseTypeId == MyTypeId.geometry)
                {
                    writeType(MyTypeId.geometry, myTypeSignedValue);
                    return valueWriter.writeGeometry(value.get!MyGeometry());
                }
                return unsupportDataError();

            case DbType.array:
                return unsupportDataError();
        }

        // Never reach here
        assert(0, toName!DbType(column.type));
    }

    override void doDispose(bool disposing) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        _connection = null;
    }

    final MyOkResponse handleAuthenticationChallenge(ref MyConnectingStateInfo stateInfo, bool authMethodChanged)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("authMethodChanged=", authMethodChanged, ", stateInfo.authMethod=", stateInfo.authMethod);

        auto useCSB = connection.myConnectionStringBuilder;
        auto useUserName = useCSB.userName;
        auto useUserPassword = useCSB.userPassword;
        int authState = authMethodChanged ? 0 : 1;

		if (stateInfo.auth is null)
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(stateInfo.authMethod);
            throw new MyException(msg, DbErrorCode.read, null);
        }

        {
            auto status = stateInfo.auth.getAuthData(authState, useUserName, useUserPassword, stateInfo.serverAuthData[], stateInfo.authData);
            if (status.isError)
            {
                auto msg = stateInfo.auth.getErrorMessage(status, stateInfo.authMethod);
                throw new MyException(msg, DbErrorCode.read, null);
            }
            if (authMethodChanged && stateInfo.authData.length == 0)
                stateInfo.authData.put(0x00);
        }

        while (stateInfo.authData.length)
        {
            // Create writer scope
            {
                auto writer = MyXdrWriter(connection, maxSinglePackage);
                writer.beginPackage(++sequenceByte);
                writer.writeOpaqueBytes(stateInfo.authData[]);
                writer.flush();
            }

            // Create reader scope
            {
                auto packageData = readPackageData();
                if (packageData.empty)
                    return MyOkResponse.init;

                auto allData = packageData.buffer.consumeAll();
                if (allData[0] != 1)
                    return MyOkResponse.init;

                authState++;
                stateInfo.serverAuthData = allData[1..$];
                auto status = stateInfo.auth.getAuthData(authState, useUserName, useUserPassword,
                    stateInfo.serverAuthData[], stateInfo.authData);
                if (status.isError)
                {
                    auto msg = stateInfo.auth.getErrorMessage(status, stateInfo.authMethod);
                    throw new MyException(msg, DbErrorCode.read, null);
                }
            }
        }

        auto ignoredData = readPackageData();
        return MyOkResponse.init;
    }

    final void prepareCommandReadFields(MyCommand command, ref MyCommandPreparedResponse info)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("info.fieldCount=", info.fieldCount);

        info.fields.reserve(info.fieldCount);
        foreach (i; 0..info.fieldCount)
            info.fields ~= readFieldInfo(command, i, false);
        readEOF();
    }

    final void prepareCommandReadHeader(MyCommand command, ref MyCommandPreparedResponse info)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);

        if (reader.readUInt8() != 0)
            throw new MyException("Expected prepared statement marker", DbErrorCode.read, null);

        info.id = reader.readInt32();
        info.fieldCount = reader.readInt16();
        info.parameterCount = reader.readInt16();
        reader.readUInt32!3(); //TODO: find out what this is needed for
    }

    final void prepareCommandReadParameters(MyCommand command, ref MyCommandPreparedResponse info)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("info.parameterCount=", info.parameterCount);

        info.parameters.reserve(info.parameterCount);
        foreach (i; 0..info.parameterCount)
            info.parameters ~= readFieldInfo(command, i, true);
        readEOF();
    }

    final void readCommandResultReadFields(MyCommand command, ref MyCommandResultResponse info)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("info.fieldCount=", info.fieldCount);

        info.fields.reserve(info.fieldCount);
        foreach (i; 0..info.fieldCount)
            info.fields ~= readFieldInfo(command, i, false);
    }

    final MyFieldInfo readFieldInfo(MyCommand command, size_t index, bool isParameter)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("index=", index, ", isParameter=", isParameter);

        auto packageData = readPackageData();
        auto reader = MyXdrReader(connection, packageData.buffer);

        MyFieldInfo result;
        result.catalogName = reader.readString();
        result.databaseName = reader.readString();
        result.tableName = reader.readString();
        result.realTableName = reader.readString();
        result.columnName = reader.readString();
        result.originalColumnName = reader.readString();
        reader.readUInt8(); // one byte filler here
        result.characterSetIndex = reader.readInt16();
        result.columnLength = reader.readInt32();
        result.typeId = reader.readUInt8();
        if ((_connectionFlags & MyCapabilityFlags.longFlag) != 0)
            result.typeFlags = reader.readUInt16();
        else
            result.typeFlags = reader.readUInt8();
        result.scale = reader.readInt8();

        if (!reader.empty)
            reader.readInt16(); // reserved

        result.calculateOtherInfo(connection.fieldTypeMaps);

        return result;
    }

    final BitArrayImpl!ubyte readNullBitmaps(ref MyXdrReader reader, size_t fieldCount)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("fieldCount=", fieldCount);

        const nullBitmapBytes = bitLengthToElement!ubyte(fieldCount + 2);

        reader.readUInt8(); // byte header
        auto bytes = reader.readBytes(cast(int32)nullBitmapBytes);

        version (TraceFunction) traceFunction!("pham.db.mydatabase")("fieldCount=", fieldCount, ", length=", nullBitmapBytes, ", bytes=", bytes.dgToHex());

        return BitArrayImpl!ubyte(bytes);
    }

    final MyReader readPackageData()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto result = MyReader(connection);
        this.sequenceByte = result.sequenceByte;
        if (result.isError)
        {
            auto valueReader = MyXdrReader(connection, result.buffer);
            auto errorResult = valueReader.readError();
            throw new MyException(errorResult);
        }
        return result;
    }

    version (none)
    final bool skipPackageData()
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

        auto result = MyReader(connection);
        return !result.empty;
    }

    final void validateRequiredEncryption(ref MyConnectingStateInfo stateInfo, bool wasEncryptedSetup)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")();

		if (wasEncryptedSetup)
            return;

        const encrypt = connection.connectionStringBuilder.encrypt;

        // Client is requesting a secure connection
        if (encrypt == DbEncryptedConnection.required)
        {
            auto msg = DbMessage.eInvalidConnectionRequiredEncryption.fmtMessage(connection.connectionStringBuilder.forErrorInfo);
            throw new MyException(msg, DbErrorCode.connect, null);
        }

        // Server is requesting a secure connection
        if ((stateInfo.serverCapabilities & MyCapabilityFlags.secureConnection) != 0 && encrypt == DbEncryptedConnection.disabled)
        {
            auto msg = DbMessage.eInvalidConnectionRequiredEncryption.fmtMessage(connection.connectionStringBuilder.forErrorInfo);
            throw new MyException(msg, DbErrorCode.connect, null);
        }
    }

    @property final bool isQueryAttributes() const @nogc nothrow pure
    {
        return (_connectionFlags & MyCapabilityFlags.queryAttributes) != 0;
    }

public:
    uint32 maxSinglePackage = (256 * 256 * 256) - 1;
    ubyte sequenceByte;

private:
    MyConnection _connection;
    uint32 _connectionFlags;
    int32 _protocolVersion;
}


// Any below codes are private
private:
