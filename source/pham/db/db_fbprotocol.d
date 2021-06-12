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

module pham.db.fbprotocol;

import std.algorithm.comparison : max, min;
import std.array : Appender;
import std.conv : to;
import std.format : format;
import std.range.primitives : isOutputRange, put;
import std.typecons : Flag, No, Yes;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.bit_array : BitArray, hostToNetworkOrder;
import pham.utl.enum_set : toName;
import pham.utl.object : InitializedValue, bytesFromHexs, bytesToHexs, functionName,
    currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.cp.cipher : CipherParameters;
import pham.db.message;
import pham.db.convert;
import pham.db.util;
import pham.db.type;
import pham.db.dbobject : DbDisposableObject;
import pham.db.auth : DbAuth;
import pham.db.buffer_filter;
import pham.db.buffer_filter_cipher;
import pham.db.buffer_filter_compressor;
import pham.db.value;
import pham.db.database : DbNameColumn;
import pham.db.fbisc;
import pham.db.fbtype;
import pham.db.fbexception;
import pham.db.fbauth;
import pham.db.fbauth_legacy;
import pham.db.fbauth_sspi;
import pham.db.fbauth_srp;
import pham.db.fbbuffer;
import pham.db.fbdatabase;

/**
    Returns:
        length of blob in bytes
 */
size_t parseBlob(W)(scope ref W outputSink, scope const(ubyte)[] data) @safe
if (isOutputRange!(W, ubyte))
{
    size_t result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2; // -2 for item length
	size_t pos = 0;
	while (pos < endPos)
	{
        const len = parseInt32!true(data, pos, 2, FbIscType.SQL_BLOB);
        put(outputSink, data[pos..pos + len]);
        result += len;
        pos += len;
	}
    return result;
}

DbRecordsAffectedAggregate parseRecordsAffected(scope const(ubyte)[] data) @safe
{
    DbRecordsAffectedAggregate result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2;
    size_t pos = 0;

    void parseRecordValues()
    {
		while (pos < endPos)
		{
            const typ = data[pos++];
            if (typ == FbIsc.isc_info_end)
                break;

			const len = parseInt32!true(data, pos, 2, typ);
			switch (typ)
			{
				case FbIsc.isc_info_req_select_count:
					result.selectCount += parseInt32!true(data, pos, len, typ);
					break;

				case FbIsc.isc_info_req_insert_count:
					result.insertCount += parseInt32!true(data, pos, len, typ);
					break;

				case FbIsc.isc_info_req_update_count:
					result.updateCount += parseInt32!true(data, pos, len, typ);
					break;

				case FbIsc.isc_info_req_delete_count:
					result.deleteCount += parseInt32!true(data, pos, len, typ);
					break;

                default:
                    pos += len;
                    break;
			}
		}
    }

	while (pos < endPos)
	{
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

		const len = parseInt32!true(data, pos, 2, typ);
		switch (typ)
		{
			case FbIsc.isc_info_sql_records:
                if (pos < endPos)
                    parseRecordValues();
                else
                    goto default;
				break;

			default:
				pos += len;
				break;
		}
	}

	return result;
}

class FbProtocol : DbDisposableObject
{
@safe:

public:
    this(FbConnection connection) nothrow pure
    {
        this._connection = connection;
    }

    final FbIscObject allocateCommandRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
        return response.getIscObject();
    }

    final void allocateCommandWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        allocateCommandWrite(writer);
        writer.flush();
    }

    final void allocateCommandWrite(ref FbXdrWriter writer) nothrow
    {
        version (TraceFunction) dgFunctionTrace();

		writer.writeOperation(FbIsc.op_allocate_statement);
		writer.writeHandle(connection.fbHandle);
    }

    final FbIscArrayGetResponse arrayGetRead(ref FbArray array)
    {
        version (TraceFunction) dgFunctionTrace();

        auto reader = FbXdrReader(connection);
        const op = reader.readOperation(FbIsc.op_slice);
        return readArrayGetResponseImpl(reader, array.descriptor);
    }

    final void arrayGetWrite(ref FbArray array)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writerASdl = FbArrayWriter(connection);

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(FbIsc.op_get_slice);
	    writer.writeHandle(array.fbTransaction.fbHandle);
	    writer.writeId(array.fbId);
		writer.writeInt32(array.descriptor.calculateSliceLength());
		writer.writeBytes(describeArray(writerASdl, array, 0));
		writer.writeChars("");
		writer.writeInt32(0);
        writer.flush();
    }

    final FbIscObject arrayPutRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
        return response.getIscObject();
    }

    final void arrayPutWrite(ref FbArray array, size_t elements, scope const(ubyte)[] encodedArrayValue)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writerASdl = FbArrayWriter(connection);

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(FbIsc.op_put_slice);
	    writer.writeHandle(array.fbTransaction.fbHandle);
	    writer.writeId(array.fbId);
		writer.writeInt32(array.descriptor.calculateSliceLength(elements));
		writer.writeBytes(describeArray(writerASdl, array, elements));
		writer.writeChars("");
		writer.writeBytes(encodedArrayValue); // Should not pad?
        writer.flush();
    }

    final FbIscObject blobBeginRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
        return response.getIscObject();
    }

    final void blobBeginWrite(ref FbBlob blob, FbOperation createOrOpen)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(createOrOpen);
        writer.writeHandle(blob.fbTransaction.fbHandle);
        writer.writeId(blob.fbId);
        writer.flush();
    }

    final void blobEndRead()
    {
        version (TraceFunction) dgFunctionTrace();

        readGenericResponse();
    }

    final void blobEndWrite(ref FbBlob blob, FbOperation closeOrCancelOp)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(closeOrCancelOp);
		writer.writeHandle(blob.fbHandle);
        writer.flush();
    }

    final FbIscGenericResponse blobGetSegmentsRead()
    {
        version (TraceFunction) dgFunctionTrace();

        return readGenericResponse();
    }

    final void blobGetSegmentsWrite(ref FbBlob blob)
    {
        version (TraceFunction) dgFunctionTrace();

        const trunkLength = blob.maxSegmentLength;
        const dataSegment = 0;
        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_get_segment);
		writer.writeHandle(blob.fbHandle);
        writer.writeInt32(trunkLength);
        writer.writeInt32(dataSegment);
        writer.flush();
    }

    final void blobPutSegmentsRead()
    {
        version (TraceFunction) dgFunctionTrace();

        readGenericResponse();
    }

    final void blobPutSegmentsWrite(ref FbBlob blob, scope const(ubyte)[] segment)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_batch_segments);
		writer.writeHandle(blob.fbHandle);
        writer.writeBlob(segment);
        writer.flush();
    }

    final FbIscBlobSize blobSizeInfoRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
		if (response.data.length)
            return FbIscBlobSize(response.data);
        else
            return FbIscBlobSize.init;
    }

    final void blobSizeInfoWrite(ref FbBlob blob)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_info_blob);
		writer.writeHandle(blob.fbHandle);
		writer.writeInt32(0);
		writer.writeBytes(describeBlobSizeInfoItems);
		writer.writeInt32(FbIscSize.blobSizeInfoBufferLength);
        writer.flush();
    }

    final void cancelRequestWrite()
    {
        cancelRequestWrite(FbIsc.fb_cancel_raise);
    }

    final void closeCursorCommandRead()
    {
        version (TraceFunction) dgFunctionTrace();

        readGenericResponse();
    }

    final void closeCursorCommandWrite(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_free_statement);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(FbIsc.DSQL_close);
        writer.flush();
    }

    final void commitRetainingTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void commitTransactionRead()
    {
        version (TraceFunction) dgFunctionTrace();

        readGenericResponse();
    }

    final void commitTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject connectAttachmentRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
        return response.getIscObject();
    }

    final void connectAttachmentWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        auto useCSB = connection.connectionStringBuilder;
        auto writerAI = FbConnectionWriter(connection, FbIsc.isc_dpb_version);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_attach);
		writer.writeHandle(0);
		writer.writeChars(useCSB.databaseName);
        writer.writeBytes(describeAttachmentInformation(writerAI));
        writer.flush();
    }

    final void connectAuthenticationRead()
    {
        version (TraceFunction) dgFunctionTrace();

        void setupCompression()
        {
			if (canCompressConnection())
            {
                connection.serverInfo[DbIdentifier.serverProtocolCompressed] = dbBoolTrue;
                compressSetupBufferFilter();
            }
        }

        bool setupEncryption()
        {
            if (canCryptedConnection())
            {
                connection.serverInfo[DbIdentifier.serverProtocolEncrypted] = dbBoolTrue;
                cryptWrite();
                cryptSetupBufferFilter(); // after writing before reading
                cryptRead();
                return true;
            }
            else
                return false;
        }

        void validateRequiredEncryption()
        {
			if (getCryptedConnectionCode() == FbIsc.connect_crypt_required)
            {
                auto msg = format(DbMessage.eInvalidConnectionRequiredEncryption, connection.connectionStringBuilder.forErrorInfo);
                throw new FbException(msg, DbErrorCode.connect, 0, FbIscResultCode.isc_wirecrypt_incompatible);
            }
        }

        auto reader = FbXdrReader(connection);

        const op = reader.readOperation();
        switch (op)
        {
            case FbIsc.op_accept:
                auto aResponse = readAcceptResponseImpl(reader);
                _serverAcceptType = aResponse.acceptType;
                _serverVersion = aResponse.version_;
                connection.serverInfo[DbIdentifier.serverProtocolAcceptType] = to!string(aResponse.acceptType);
                connection.serverInfo[DbIdentifier.serverProtocolArchitect] = to!string(aResponse.architecture);
                connection.serverInfo[DbIdentifier.serverProtocolVersion] = to!string(aResponse.version_);
                setupCompression();
                if (!setupEncryption())
                    validateRequiredEncryption();
                break;
            case FbIsc.op_accept_data:
            case FbIsc.op_cond_accept:
                auto adResponse = readAcceptDataResponseImpl(reader);
                _serverAcceptType = adResponse.acceptType;
                _serverVersion = adResponse.version_;
                _serverAuthKey = adResponse.authKey;
                connection.serverInfo[DbIdentifier.serverProtocolAcceptType] = to!string(adResponse.acceptType);
                connection.serverInfo[DbIdentifier.serverProtocolArchitect] = to!string(adResponse.architecture);
                connection.serverInfo[DbIdentifier.serverProtocolVersion] = to!string(adResponse.version_);

				if (!adResponse.isAuthenticated || op == FbIsc.op_cond_accept)
				{
					if (_auth is null || adResponse.authName != _auth.name)
                    {
                        auto msg = format(DbMessage.eInvalidConnectionAuthUnsupportedName, adResponse.authName);
                        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
                    }

                    auto useCSB = connection.connectionStringBuilder;
                    _authData = _auth.getAuthData(useCSB.userName, useCSB.userPassword, adResponse.authData);
                    if (_authData.length == 0)
                    {
                        auto msg = format(DbMessage.eInvalidConnectionAuthServerData, adResponse.authName, _auth.errorMessage);
                        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
                    }
				}

                setupCompression(); // Before further sending requests

                // Authentication info will be resent when doing attachment for other op
                if (op == FbIsc.op_cond_accept)
				{
                    connectAuthenticationAcceptWrite();
                    connectAuthenticationAcceptRead();
				}

                if (!setupEncryption())
                    validateRequiredEncryption();
                return;
            case FbIsc.op_response:
                readGenericResponseImpl(reader);
                goto default;
            default:
                auto msg = format(DbMessage.eUnhandleOperation, op);
                throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void connectAuthenticationWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        clearServerInfo(Yes.includeAuth);

        auto useCSB = connection.fbConnectionStringBuilder;
        const compressFlag = useCSB.compress ? FbIsc.ptype_compress_flag : 0;
        auto protoItems = describeProtocolItems;
        auto writerUI = FbConnectionWriter(connection, FbIsc.isc_dpb_version);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_connect);
		writer.writeOperation(FbIsc.op_attach);
		writer.writeInt32(FbIsc.connect_version);
        writer.writeInt32(FbIsc.connect_generic_achitecture_client);
        writer.writeChars(useCSB.databaseName);
        writer.writeInt32(protoItems.length); // Protocol count
        writer.writeBytes(describeUserIdentification(writerUI));
        foreach (p; protoItems)
        {
		    writer.writeInt32(p.version_);
		    writer.writeInt32(p.achitectureClient);
		    writer.writeInt32(p.minType);
		    writer.writeInt32(p.maxType | (p.version_ >= FbIsc.protocol_version13 ? compressFlag : 0));
		    writer.writeInt32(p.priority);
        }
        writer.flush();
    }

    final void deallocateCommandRead()
    {
        version (TraceFunction) dgFunctionTrace();

        readGenericResponse();
    }

    final void deallocateCommandWrite(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_free_statement);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(FbIsc.DSQL_drop);
        writer.flush();
    }

    final void disconnectWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        if (connection.handle)
        {
		    writer.writeOperation(FbIsc.op_detach);
		    writer.writeHandle(connection.fbHandle);
        }
		writer.writeOperation(FbIsc.op_disconnect);
        writer.flush();

        clearServerInfo(Yes.includeAuth);
    }

    final void executeCommandRead(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        // Nothing to process - just need acknowledge
        readGenericResponse();
    }

    final void executeCommandWrite(FbCommand command, DbCommandExecuteType type)
    {
        version (TraceFunction) dgFunctionTrace("type=", type);

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(command.isStoredProcedure ? FbIsc.op_execute2 : FbIsc.op_execute);
		writer.writeHandle(command.fbHandle);
		writer.writeHandle(command.fbTransaction.fbHandle);

        auto inputParameters = command.fbInputParameters();
		if (inputParameters.length)
		{
            auto pWriterBlr = FbBlrWriter(connection);
            auto pPrmBlr = describeBlrParameterList(pWriterBlr, inputParameters);
            version (TraceFunction) dgFunctionTrace("pPrmBlr=", pPrmBlr);

            auto pWriterVal = FbXdrWriter(connection);
            auto pPrmVal = describeParameterList(pWriterVal, inputParameters);
            version (TraceFunction) dgFunctionTrace("pPrmVal=", pPrmVal);

            writer.writeBytes(pPrmBlr);
			writer.writeInt32(0); // Message number
			writer.writeInt32(1); // Number of messages
            writer.writeOpaqueBytes(pPrmVal, pPrmVal.length);
		}
		else
		{
			writer.writeBytes(null);
			writer.writeInt32(0);
			writer.writeInt32(0);
		}

		if (command.isStoredProcedure && command.hasFields)
		{
            auto pWriterBlr = FbBlrWriter(connection);
            auto pFldBlr = describeBlrFieldList(pWriterBlr, command.fbFields);
            writer.writeBytes(pFldBlr);
			writer.writeInt32(0); // Output message number
		}

        writer.flush();
    }

    final FbCommandPlanInfo.Kind executionPlanCommandInfoRead(uint mode, out FbCommandPlanInfo info)
    {
        version (TraceFunction) dgFunctionTrace();

        const describeMode = mode == 0
            ? FbIsc.isc_info_sql_get_plan
            : FbIsc.isc_info_sql_explain_plan;

        auto response = readGenericResponse();

        FbCommandPlanInfo.Kind kind;
        if (response.data.length == 0)
            kind = FbCommandPlanInfo.Kind.noData;
		else if (response.data[0] == FbIsc.isc_info_end)
            kind = FbCommandPlanInfo.Kind.empty;
        else if (response.data[0] == FbIsc.isc_info_truncated)
            kind = FbCommandPlanInfo.Kind.truncated;
        else
            kind = FbCommandPlanInfo.Kind.ok;

        final switch (kind)
        {
            case FbCommandPlanInfo.Kind.noData:
                info = FbCommandPlanInfo(kind, null);
                return kind;
            case FbCommandPlanInfo.Kind.empty:
                info = FbCommandPlanInfo(kind, "");
                return kind;
            case FbCommandPlanInfo.Kind.truncated:
                info = FbCommandPlanInfo(kind, null);
                return kind;
            case FbCommandPlanInfo.Kind.ok:
                info = FbCommandPlanInfo(kind, response.data, describeMode);
                return kind;
        }
    }

    final void executionPlanCommandInfoWrite(FbCommand command, uint mode, uint32 bufferLength)
    {
        version (TraceFunction) dgFunctionTrace();

        auto describeItems = mode == 0
            ? describeStatementPlanInfoItems
            : describeStatementExplaindPlanInfoItems;
        commandInfoWrite(command, describeItems, bufferLength);
    }

    final FbIscFetchResponse fetchCommandRead(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        auto reader = FbXdrReader(connection);

        const op = reader.readOperation();
        if (op == FbIsc.op_response)
        {
            readGenericResponseImpl(reader);
            return FbIscFetchResponse(0, 0);
        }
        else if (op == FbIsc.op_fetch_response)
            return readFetchResponseImpl(reader);
        else
        {
            auto msg = format(DbMessage.eUnexpectReadOperation, op, FbIsc.op_response);
            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_net_read_err);
        }
    }

    final void fetchCommandWrite(FbCommand command)
    in
    {
        assert(command.hasFields);
    }
    do
    {
        version (TraceFunction) dgFunctionTrace();

        auto writerBlr = FbBlrWriter(connection);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_fetch);
		writer.writeHandle(command.fbHandle);
		writer.writeBytes(describeBlrFieldList(writerBlr, command.fbFields));
		writer.writeInt32(0); // p_sqldata_message_number
		writer.writeInt32(command.fetchRecordCount); // p_sqldata_messages
		writer.flush();
    }

    final FbIscBindInfo[] prepareCommandRead(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();

        FbIscBindInfo[] bindResults;
        ptrdiff_t previousBindIndex = -1; // Start with unknown value
        ptrdiff_t previousFieldIndex = 0;

        while (!FbIscBindInfo.parse(response.data, bindResults, previousBindIndex, previousFieldIndex))
        {
            version (TraceFunction) dgFunctionTrace("previousBindIndex=", previousBindIndex, ", previousFieldIndex=", previousFieldIndex);

            enum bindBlocks = 2;
            auto bindItems = describeStatementInfoAndBindInfoItems;
            ubyte[] truncateBindItems = new ubyte[](bindItems.length + (4 * bindBlocks)); // 4 additional items for each block
            size_t truncateBindIndex, i;
            bool newBindBlock = true;
            foreach (bindItem; bindItems)
            {
                if (newBindBlock)
                {
                    newBindBlock = false;

					auto processedFieldCount = truncateBindIndex <= previousBindIndex
                        ? bindResults[truncateBindIndex].length
                        : 0;
                    truncateBindItems[i++] = FbIsc.isc_info_sql_sqlda_start;
                    truncateBindItems[i++] = 2;
					truncateBindItems[i++] = cast(ubyte)((truncateBindIndex == previousBindIndex ? previousFieldIndex : processedFieldCount) & 255);
					truncateBindItems[i++] = cast(ubyte)((truncateBindIndex == previousBindIndex ? previousFieldIndex : processedFieldCount) >> 8);
                }

                truncateBindItems[i++] = bindItem;
                if (bindItem == FbIsc.isc_info_sql_describe_end)
                {
                    truncateBindIndex++;
                    newBindBlock = true;
                }
            }

            commandInfoWrite(command, truncateBindItems, FbIscSize.prepareInfoBufferLength);
            response = readGenericResponse();
        }

        return bindResults;
    }

    final prepareCommandWrite(FbCommand command, scope const(char)[] sql)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        prepareCommandWrite(command, sql, writer);
        writer.flush();
    }

    final prepareCommandWrite(FbCommand command, scope const(char)[] sql, ref FbXdrWriter writer) nothrow
    {
        version (TraceFunction) dgFunctionTrace();

        auto bindItems = describeStatementInfoAndBindInfoItems;

		writer.writeOperation(FbIsc.op_prepare_statement);
		writer.writeHandle(command.fbTransaction.fbHandle);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(connection.dialect);
		writer.writeChars(sql);
		writer.writeBytes(bindItems);
		writer.writeInt32(FbIscSize.prepareInfoBufferLength);
    }

    final DbRecordsAffected recordsAffectedCommandRead()
    {
        version (TraceFunction) dgFunctionTrace();

        DbRecordsAffected result;
        auto response = readGenericResponse();
		if (response.data.length)
		{
            const counts = parseRecordsAffected(response.data);
            if (counts.deleteCount)
                result += counts.deleteCount;
            if (counts.insertCount)
                result += counts.insertCount;
            if (counts.updateCount)
                result += counts.updateCount;
        }
        return result;
    }

    final void recordsAffectedCommandWrite(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        commandInfoWrite(command, describeStatementRowsAffectedInfoItems, FbIscSize.rowsEffectedBufferLength);
    }

    final void rollbackRetainingTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void rollbackTransactionRead()
    {
        version (TraceFunction) dgFunctionTrace();

        readGenericResponse();
    }

    final void rollbackTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject startTransactionRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
        return response.getIscObject();
    }

    final void startTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) dgFunctionTrace();

        auto paramWriter = FbTransactionWriter(connection);
        auto paramBytes = describeTransaction(paramWriter, transaction);

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_transaction);
	    writer.writeHandle(connection.fbHandle);
	    writer.writeBytes(paramBytes);
        writer.flush();
    }

    final int typeCommandRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto response = readGenericResponse();
		if (response.data.length)
            return parseCommandType(response.data);
        else
            return FbIscCommandType.none;
    }

    final void typeCommandWrite(FbCommand command)
    {
        version (TraceFunction) dgFunctionTrace();

        commandInfoWrite(command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength);
    }

    final void typeCommandWrite(FbCommand command, ref FbXdrWriter writer) nothrow
    {
        version (TraceFunction) dgFunctionTrace();

        commandInfoWrite(command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength, writer);
    }

    final FbIscGenericResponse readGenericResponse()
    {
        auto reader = FbXdrReader(connection);
        const op = reader.readOperation(FbIsc.op_response);
        return readGenericResponseImpl(reader);
    }

    version (none)
    final FbResponse readResponse(FbOperation mainOp)
    {
        auto reader = FbXdrReader(connection);
        const op = reader.readOperation();
        switch (op)
        {
            case FbIsc.op_response:
                auto rGeneric = readGenericResponseImpl(reader);
                return new FbResponse(op, rGeneric);
            case FbIsc.op_fetch_response:
                auto rFetch = readFetchResponseImpl(reader);
                return new FbResponse(op, rFetch);
            case FbIsc.op_sql_response:
                auto rSql = readSqlResponseImpl(reader);
                return new FbResponse(op, rSql);
            case FbIsc.op_trusted_auth:
                auto rTrustedAuthentication = readTrustedAuthenticationResponseImpl(reader);
                return new FbResponse(op, rTrustedAuthentication);
            case FbIsc.op_crypt_key_callback:
                auto rCryptKeyCallback = readCryptKeyCallbackResponseImpl(reader);
                return new FbResponse(op, rCryptKeyCallback);
            default:
                auto msg = format(DbMessage.eUnexpectReadOperation, op, mainOp);
                throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_net_read_err);
        }
    }

    final FbIscSqlResponse readSqlResponse()
    {
        auto reader = FbXdrReader(connection);
        const op = reader.readOperation(FbIsc.op_sql_response);
        return readSqlResponseImpl(reader);
    }

    final DbValue readValue(FbCommand command, ref FbXdrReader reader, DbNameColumn column)
    {
        version (TraceFunction)
        dgFunctionTrace("column.type=", toName!DbType(column.type),
            ", baseTypeId=", column.baseTypeId,
            ", baseSubtypeId=", column.baseSubTypeId,
            ", baseNumericScale=", column.baseNumericScale);
        version (profile) auto p = PerfFunction.create();

        if (column.isArray)
            return DbValue.entity(reader.readId(), column.type);

        final switch (column.type)
        {
            case DbType.boolean:
                return DbValue(reader.readBool(), column.type);
            case DbType.int8:
                return DbValue(cast(int8)reader.readInt16(), column.type);
            case DbType.int16:
                return DbValue(reader.readInt16(), column.type);
            case DbType.int32:
                return DbValue(reader.readInt32(), column.type);
            case DbType.int64:
                return DbValue(reader.readInt64(), column.type);
            case DbType.int128:
                return DbValue(reader.readInt128(), column.type);
            case DbType.decimal:
                return DbValue(reader.readDecimal!Decimal(column.baseType), column.type);
            case DbType.decimal32:
                return DbValue(reader.readDecimal!Decimal32(column.baseType), column.type);
            case DbType.decimal64:
                return DbValue(reader.readDecimal!Decimal64(column.baseType), column.type);
            case DbType.decimal128:
                return DbValue(reader.readDecimal!Decimal128(column.baseType), column.type);
            case DbType.numeric:
                return DbValue(reader.readDecimal!Numeric(column.baseType), column.type);
            case DbType.float32:
                return DbValue(reader.readFloat32(), column.type);
            case DbType.float64:
                return DbValue(reader.readFloat64(), column.type);
            case DbType.date:
                return DbValue(reader.readDate(), column.type);
            case DbType.datetime:
                return DbValue(reader.readDateTime(), column.type);
            case DbType.datetimeTZ:
                return DbValue(reader.readDateTimeTZ(), column.type);
            case DbType.time:
                return DbValue(reader.readTime(), column.type);
            case DbType.timeTZ:
                return DbValue(reader.readTimeTZ(), column.type);
            case DbType.uuid:
                return DbValue(reader.readUUID(), column.type);
            case DbType.chars:
                return DbValue(reader.readFixedString(column.baseType), column.type);
            case DbType.string:
                return DbValue(reader.readString(), column.type);
            case DbType.json:
            case DbType.xml:
            case DbType.text:
            case DbType.binary:
                return DbValue.entity(reader.readId(), column.type);

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = format(DbMessage.eUnsupportDataType, functionName!(typeof(this))(), toName!DbType(column.type));
                throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_net_read_err);
        }

        version (protocolPrev13)
        {
            // Flag after value - Weird but that's how Firebird
		    auto nullFlag = reader.readInt32();
            //if (nullFlag == FbNullIndicator)
		    if (nullFlag != 0)
            {
                result.nullify();
                result.resolveValue = null;
            }
        }

        // Never reach here
        assert(0, toName!DbType(column.type));
    }

    final DbRowValue readValues(FbCommand command, FbFieldList fields)
    {
        version (TraceFunction) dgFunctionTrace();
        version (profile) auto p = PerfFunction.create();

        auto reader = FbXdrReader(connection);

        const nullByteCount = BitArray.lengthToElement!8(fields.length);
		auto nullBytes = reader.readOpaqueBytes(nullByteCount);
		auto nullBits = BitArray(nullBytes);

        size_t i = 0;
        auto result = DbRowValue(fields.length);
        foreach (field; fields)
        {
            if (nullBits[i])
                result[i++].nullify();
            else
                result[i++] = readValue(command, reader, field);
        }
        return result;
    }

    @property final FbConnection connection() nothrow pure
    {
        return _connection;
    }

    @property final int serverAcceptType() const nothrow pure @nogc
    {
        return _serverAcceptType.inited ? _serverAcceptType : 0;
    }

    @property final int serverVersion() const nothrow pure @nogc
    {
        return _serverVersion.inited ? _serverVersion : 0;
    }

protected:
    final void cancelRequestWrite(int32 cancelKind)
    {
        version (TraceFunction) dgFunctionTrace("cancelKind=", cancelKind);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_cancel);
        writer.writeInt32(cancelKind);
		writer.flush();
    }

    final bool canCompressConnection() nothrow
    {
        if (!_serverVersion.inited || _serverVersion < FbIsc.protocol_version13)
            return false;

        if (!_serverAcceptType.inited || (_serverAcceptType & FbIsc.ptype_compress_flag) == 0)
			return false;

        return connection.fbConnectionStringBuilder.compress;
    }

    final bool canCryptedConnection() nothrow
    {
        if (!_serverVersion.inited || _serverVersion < FbIsc.protocol_version13)
            return false;

        return _auth !is null && _auth.canCryptedConnection() && getCryptedConnectionCode() != FbIsc.connect_crypt_disabled;
    }

    final void clearServerInfo(Flag!"includeAuth" includeAuth)
    {
        _serverAcceptType.reset();
        _serverVersion.reset();

        if (includeAuth)
        {
            _serverAuthKey = null;
            _authData = null;
            _auth = null;
        }
    }

    final void commandInfoWrite(FbCommand command, scope const(ubyte)[] items, uint32 resultBufferLength)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
        commandInfoWrite(command, items, resultBufferLength, writer);
        writer.flush();
    }

    final void commandInfoWrite(FbCommand command, scope const(ubyte)[] items, uint32 resultBufferLength, ref FbXdrWriter writer) nothrow
    {
        version (TraceFunction) dgFunctionTrace();

		writer.writeOperation(FbIsc.op_info_sql);
        writer.writeHandle(command.fbHandle);
		writer.writeInt32(0);
		writer.writeBytes(items);
		writer.writeInt32(resultBufferLength);
    }

    final void compressSetupBufferFilter()
    {
        version (TraceFunction) dgFunctionTrace();

		auto compressor = new DbBufferFilterCompressorZip!(DbBufferFilterKind.write)();
		auto decompressor = new DbBufferFilterCompressorZip!(DbBufferFilterKind.read)();
		connection.chainBufferFilters(decompressor, compressor);
    }

    final void connectAuthenticationAcceptRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto reader = FbXdrReader(connection);
        const op = reader.readOperation();
        switch (op)
        {
            case FbIsc.op_response:
                auto gResponse = readGenericResponseImpl(reader);
                _serverAuthKey = gResponse.data;
                break;
            case FbIsc.op_trusted_auth:
                auto tResponse = readTrustedAuthResponseImpl(reader);
                _serverAuthKey = tResponse.data;
                break;
            case FbIsc.op_cont_auth:
                auto cResponse = readCondAuthResponseImpl(reader);
                _serverAuthKey = cResponse.key;

                if (cResponse.name.length != 0)
                {
                    auto authMap = FbAuth.findAuthMap(DbScheme.fb ~ cResponse.name);
                    if (!authMap.isValid())
                    {
                        auto msg = format(DbMessage.eInvalidConnectionAuthUnsupportedName, cResponse.name);
                        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
                    }
                    _auth = authMap.createAuth();
                    auto useCSB = connection.connectionStringBuilder;
                    _authData = _auth.getAuthData(useCSB.userName, useCSB.userPassword, cResponse.data);
                    if (_authData.length == 0)
                    {
                        auto msg = format(DbMessage.eInvalidConnectionAuthServerData, cResponse.name, _auth.errorMessage);
                        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
                    }
                }
                break;
            default:
                auto msg = format(DbMessage.eUnhandleOperation, op);
                throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void connectAuthenticationAcceptWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_cont_auth);
		writer.writeBytes(_authData);
		writer.writeChars(_auth.name); // like CNCT_plugin_name
		writer.writeChars(_auth.name); // like CNCT_plugin_list
		writer.writeBytes(_serverAuthKey);
		writer.flush();
    }

    final void cryptRead()
    {
        version (TraceFunction) dgFunctionTrace();

        auto reader = FbXdrReader(connection);
        const op = reader.readOperation();
        switch (op)
        {
            case FbIsc.op_crypt_key_callback:
                readCryptKeyCallbackResponseImpl(reader);
                break;
            case FbIsc.op_response:
                readGenericResponseImpl(reader);
                break;
            default:
                auto msg = format(DbMessage.eUnhandleOperation, op);
                throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void cryptSetupBufferFilter()
    {
        version (TraceFunction) dgFunctionTrace("sessionKey=", _auth.sessionKey());

        auto keyParameters = CipherParameters(_auth.sessionKey().dup);
		auto encryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.write)(keyParameters);
		auto decryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.read)(keyParameters);
		connection.chainBufferFilters(decryptor, encryptor);
    }

    final void cryptWrite()
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_crypt);
		writer.writeChars(FbIscText.isc_filter_arc4_name);
        writer.writeChars(_auth.sessionKeyName);
        writer.flush();
    }

    final ubyte[] describeAttachmentInformation(return ref FbConnectionWriter writer)
    {
        version (TraceFunction) dgFunctionTrace("_authData=", bytesToHexs(_authData));

        auto useCSB = connection.fbConnectionStringBuilder;

        version (TraceFunction) dgFunctionTrace("connectionTimeout=", useCSB.connectionTimeout.toInt32Second());

        version (none)
        bool needSendPassword()
        {
            if (_authData.length)
                return false;
            else if (version_ < FbIsc.protocol_version12)
                return true;
            else if (version_ == FbIsc.protocol_version12)
            {
                const iss = useCSB.integratedSecurity;
                return iss != DbIntegratedSecurityConnection.sspi &&
                    iss != DbIntegratedSecurityConnection.trusted;
            }
            else
                return false;
        }

		writer.writeType(FbIsc.isc_dpb_version);
		writer.writeInt32(FbIsc.isc_dpb_dummy_packet_interval, useCSB.dummyPackageInterval.toInt32Second());
		writer.writeInt32(FbIsc.isc_dpb_sql_dialect, useCSB.dialect);
		writer.writeChars(FbIsc.isc_dpb_lc_ctype, useCSB.charset);
        writer.writeCharsIf(FbIsc.isc_dpb_user_name, useCSB.userName);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, useCSB.roleName);
		writer.writeInt32(FbIsc.isc_dpb_connect_timeout, useCSB.connectionTimeout.toInt32Second());
		writer.writeInt32(FbIsc.isc_dpb_process_id, currentProcessId());
		writer.writeChars(FbIsc.isc_dpb_process_name, currentProcessName());
		writer.writeCharsIf(FbIsc.isc_dpb_client_version, useCSB.applicationVersion);
		if (_authData.length)
		    writer.writeBytes(FbIsc.isc_dpb_specific_auth_data, _authData);
		if (useCSB.cachePages)
			writer.writeInt32(FbIsc.isc_dpb_num_buffers, useCSB.cachePages);
		if (!useCSB.databaseTrigger)
		    writer.writeInt32(FbIsc.isc_dpb_no_db_triggers, 1);
		if (!useCSB.garbageCollect)
		    writer.writeInt32(FbIsc.isc_dpb_no_garbage_collect, 1);
		writer.writeInt32(FbIsc.isc_dpb_utf8_filename, 1); // This is weirdess - must be last or fail to authenticate

        auto result = writer.peekBytes();

        //version (TraceFunction) dgFunctionTrace("dpbValue.Length=", result.length, ", dpbValue=", bytesToHexs(result));

        return result;
    }

    final ubyte[] describeUserIdentification(return ref FbConnectionWriter writer)
    {
        auto useCSB = connection.fbConnectionStringBuilder;

        version (TraceFunction) dgFunctionTrace("userName=", useCSB.userName, ", userPassword=", useCSB.userPassword);

        writer.writeChars(FbIsc.CNCT_user, currentUserName());
        writer.writeChars(FbIsc.CNCT_host, currentComputerName());
        writer.writeInt8(FbIsc.CNCT_user_verification, 0);

        final switch (useCSB.integratedSecurity)
        {
            case DbIntegratedSecurityConnection.srp:
                _auth = new FbAuthSrpSHA1();

                writer.writeChars(FbIsc.CNCT_login, useCSB.userName);
                writer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                writer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                writer.writeMultiParts(FbIsc.CNCT_specific_data, _auth.publicKey());
                writer.writeInt32(FbIsc.CNCT_client_crypt, hostToNetworkOrder!int(getCryptedConnectionCode()));

                version (TraceFunction) dgFunctionTrace("specificData=", _auth.publicKey());
                break;

            case DbIntegratedSecurityConnection.srp256:
                _auth = new FbAuthSrpSHA256();

                writer.writeChars(FbIsc.CNCT_login, useCSB.userName);
                writer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                writer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                writer.writeMultiParts(FbIsc.CNCT_specific_data, _auth.publicKey());
                writer.writeInt32(FbIsc.CNCT_client_crypt, hostToNetworkOrder!int(getCryptedConnectionCode()));

                version (TraceFunction) dgFunctionTrace("specificData=", _auth.publicKey());
                break;

            case DbIntegratedSecurityConnection.sspi:
                version (Windows)
                {
                    _auth = new FbAuthSspi();
                    if (_auth.errorCode != 0)
                        throw new FbException(_auth.errorMessage, DbErrorCode.write, 0, FbIscResultCode.isc_auth_data);

                    writer.writeChars(FbIsc.CNCT_login, useCSB.userName);
                    writer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                    writer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                    writer.writeMultiParts(FbIsc.CNCT_specific_data, _auth.publicKey());
                    writer.writeInt32(FbIsc.CNCT_client_crypt, hostToNetworkOrder!int(getCryptedConnectionCode()));

                    version (TraceFunction) dgFunctionTrace("specificData=", _auth.publicKey());
                }
                else
                    goto case DbIntegratedSecurityConnection.srp;
                break;

            case DbIntegratedSecurityConnection.legacy:
                _auth = new FbAuthLegacy();

                writer.writeChars(FbIsc.CNCT_login, useCSB.userName);
                writer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                writer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                break;
        }

        auto result = writer.peekBytes();

        version (TraceFunction) dgFunctionTrace("end=", dgToHex(result));

        return result;
    }

    override void doDispose(bool disposing) nothrow
    {
        version (TraceFunction) dgFunctionTrace();

        if (_auth !is null)
        {
            _auth.disposal(disposing);
            _auth = null;
        }
        _serverAcceptType.reset();
        _serverVersion.reset();

        if (disposing)
        {
            _authData = null;
            _connection = null;
            _serverAuthKey = null;
        }
    }

    final int getCryptedConnectionCode() nothrow
    {
        auto useCSB = connection.connectionStringBuilder;

        // Check security settting that supports encryption regardless of encrypt setting
        final switch (useCSB.integratedSecurity)
        {
            case DbIntegratedSecurityConnection.srp:
            case DbIntegratedSecurityConnection.srp256:
                break;
            case DbIntegratedSecurityConnection.sspi:
            case DbIntegratedSecurityConnection.legacy:
                return FbIsc.connect_crypt_disabled;
        }

        final switch (useCSB.encrypt)
        {
            case DbEncryptedConnection.disabled:
                return FbIsc.connect_crypt_disabled;
            case DbEncryptedConnection.enabled:
                return FbIsc.connect_crypt_enabled;
            case DbEncryptedConnection.required:
                return FbIsc.connect_crypt_required;
        }
    }

    final FbIscAcceptResponse readAcceptResponseImpl(ref FbXdrReader reader)
    {
        auto version_ = FbIscAcceptResponse.normalizeVersion(reader.readInt32());
        auto architecture = reader.readInt32();
        auto acceptType = reader.readInt32();

        return FbIscAcceptResponse(version_, architecture, acceptType);
    }

    final FbIscAcceptDataResponse readAcceptDataResponseImpl(ref FbXdrReader reader)
    {
        auto version_ = FbIscAcceptResponse.normalizeVersion(reader.readInt32());
        auto architecture = reader.readInt32();
        auto acceptType = reader.readInt32();
        auto authData = reader.readBytes();
        auto authName = reader.readString();
        auto authenticated = reader.readInt32();
        auto authKey = reader.readBytes();

        return FbIscAcceptDataResponse(version_, architecture, acceptType, authData, authName, authenticated, authKey);
    }

    final FbIscArrayGetResponse readArrayGetResponseImpl(ref FbXdrReader reader, in FbIscArrayDescriptor descriptor)
    {
        version (TraceFunction) dgFunctionTrace();

        FbIscArrayGetResponse result;
        result.sliceLength = reader.readInt32(); // Weird?
        result.sliceLength = reader.readInt32();
		switch (descriptor.blrType)
		{
			case FbBlrType.blr_short:
				result.sliceLength = result.sliceLength * descriptor.fieldInfo.size;
				break;
			case FbBlrType.blr_text:
			case FbBlrType.blr_text2:
			case FbBlrType.blr_cstring:
			case FbBlrType.blr_cstring2:
				result.elements = result.sliceLength / descriptor.fieldInfo.size;
				result.sliceLength += result.elements * ((4 - descriptor.fieldInfo.size) & 3);
				break;
			case FbBlrType.blr_varying:
			case FbBlrType.blr_varying2:
				result.elements = result.sliceLength / descriptor.fieldInfo.size;
				break;
            default:
                break;
		}

        if (descriptor.blrType == FbBlrType.blr_varying || descriptor.blrType == FbBlrType.blr_varying2)
        {
            Appender!(ubyte[]) tempResult;
            tempResult.reserve(result.sliceLength);
            foreach (i; 0..result.elements)
            {
                const l = reader.readInt32();
                tempResult.put(reader.readOpaqueBytes(l));
            }
            result.data = tempResult.data;
        }
        else
            result.data = reader.readOpaqueBytes(result.sliceLength);

        return result;
    }

    alias readCondAcceptResponseImpl = readAcceptDataResponseImpl;

    final FbIscCondAuthResponse readCondAuthResponseImpl(ref FbXdrReader reader)
    {
        auto rData = reader.readBytes();
        auto rName = reader.readString();
        auto rList = reader.readBytes();
        auto rKey = reader.readBytes();
        return FbIscCondAuthResponse(rData, rName, rList, rKey);
    }

    final FbIscCryptKeyCallbackResponse readCryptKeyCallbackResponseImpl(ref FbXdrReader reader)
    {
        auto rData = reader.readBytes();
        return FbIscCryptKeyCallbackResponse(rData);
    }

    final FbIscFetchResponse readFetchResponseImpl(ref FbXdrReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

        auto rStatus = reader.readInt32();
        auto rCount = reader.readInt32();

        version (TraceFunction) dgFunctionTrace("rStatus=", rStatus, ", rCount=", rCount);

        return FbIscFetchResponse(rStatus, rCount);
    }

    final FbIscGenericResponse readGenericResponseImpl(ref FbXdrReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

        auto rHandle = reader.readHandle();
        auto rId = reader.readId();
        auto rData = reader.readBytes();
        auto rStatues = reader.readStatuses();

        version (TraceFunction) dgFunctionTrace("rHandle=", rHandle, ", rId=", rId, ", rData=", bytesToHexs(rData));

        if (rStatues.isError)
        {
            version (TraceFunction) dgFunctionTrace("Throw error: ", rStatues.errorCode());

            throw new FbException(rStatues);
        }
        else if (rStatues.isWarning)
        {
            //todo check for warning status
        }

        return FbIscGenericResponse(rHandle, rId, rData, rStatues);
    }

    final FbIscSqlResponse readSqlResponseImpl(ref FbXdrReader reader)
    {
        version (TraceFunction) dgFunctionTrace();

        auto rCount = reader.readInt32();

        version (TraceFunction) dgFunctionTrace("rCount=", rCount);

        return FbIscSqlResponse(rCount);
    }

    final FbIscTrustedAuthResponse readTrustedAuthResponseImpl(ref FbXdrReader reader)
    {
        auto rData = reader.readBytes().dup;

        return FbIscTrustedAuthResponse(rData);
    }

private:
    DbAuth _auth;
    const(ubyte)[] _authData;
    const(ubyte)[] _serverAuthKey;
    FbConnection _connection;
    InitializedValue!int _serverAcceptType;
    InitializedValue!int _serverVersion;
}

ubyte[] describeBlrFieldList(return ref FbBlrWriter writer, FbFieldList fields) nothrow @safe
in
{
    assert(fields !is null);
    assert(fields.length != 0 && fields.length <= ushort.max / 2);
}
do
{
    writer.writeBegin(fields.length);
    foreach (field; fields)
    {
        writer.writeColumn(field.baseType, field.baseSize);
    }
    writer.writeEnd(fields.length);

    auto result = writer.peekBytes();
    version (TraceFunction) dgFunctionTrace("result=", result);
    return result;
}

ubyte[] describeBlrParameterList(return ref FbBlrWriter writer, scope FbParameter[] parameters) nothrow @safe
in
{
    assert(parameters !is null);
    assert(parameters.length != 0 && parameters.length <= ushort.max / 2);
}
do
{
    writer.writeBegin(parameters.length);
    foreach (param; parameters)
    {
        writer.writeColumn(param.baseType, param.baseSize);
    }
    writer.writeEnd(parameters.length);
    return writer.peekBytes();
}

ubyte[] describeParameterList(return ref FbXdrWriter writer, scope FbParameter[] parameters) @safe
in
{
    assert(parameters !is null);
    assert(parameters.length != 0 && parameters.length <= ushort.max / 2);
}
do
{
    // Null indicators
    auto nullBits = BitArray(parameters.length);
    foreach (i, param; parameters)
    {
        nullBits[i] = param.value.isNull;
    }
    auto nullBytes = nullBits.get!ubyte();
    writer.writeOpaqueBytes(nullBytes, nullBytes.length);

    // Values
    foreach (param; parameters)
    {
        if (!param.value.isNull)
            describeValue(writer, param, param.value);
    }

    return writer.peekBytes();
}

immutable ubyte[] describeBlobSizeInfoItems = [
    FbIsc.isc_info_blob_max_segment,
    FbIsc.isc_info_blob_num_segments,
    FbIsc.isc_info_blob_total_length
];

immutable ubyte[] describeServerVersionInfoItems = [
    FbIsc.isc_info_firebird_version,
    FbIsc.isc_info_end
];

version (DeferredProtocol)
    enum ptype = FbIsc.ptype_lazy_send;
else
    enum ptype = FbIsc.ptype_batch_send;

// Codes only support v13 and above
immutable FbProtocolInfo[] describeProtocolItems = [
    //FbProtocolInfo(FbIsc.protocol_version10, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, FbIsc.ptype_batch_send, 1),
    //FbProtocolInfo(FbIsc.protocol_version11, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, ptype, 2),
    //FbProtocolInfo(FbIsc.protocol_version12, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, ptype, 3),
    FbProtocolInfo(FbIsc.protocol_version13, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, ptype, 4)
];

immutable ubyte[] describeStatementExplaindPlanInfoItems = [
    FbIsc.isc_info_sql_explain_plan
];

// SQL information
// If adding new block, update prepareCommandRead() with proper count
immutable ubyte[] describeStatementInfoAndBindInfoItems = [
    // Select block
    FbIsc.isc_info_sql_select,
    FbIsc.isc_info_sql_describe_vars,
    FbIsc.isc_info_sql_sqlda_seq,
    FbIsc.isc_info_sql_type,
    FbIsc.isc_info_sql_sub_type,
    FbIsc.isc_info_sql_length,
    FbIsc.isc_info_sql_scale,
    FbIsc.isc_info_sql_field,
    FbIsc.isc_info_sql_relation,
    //FbIsc.isc_info_sql_owner,
    FbIsc.isc_info_sql_alias,
    FbIsc.isc_info_sql_describe_end,

    // Bind block
    FbIsc.isc_info_sql_bind,
    FbIsc.isc_info_sql_describe_vars,
    FbIsc.isc_info_sql_sqlda_seq,
    FbIsc.isc_info_sql_type,
    FbIsc.isc_info_sql_sub_type,
    FbIsc.isc_info_sql_length,
    FbIsc.isc_info_sql_scale,
    FbIsc.isc_info_sql_field,
    FbIsc.isc_info_sql_relation,
    //FbIsc.isc_info_sql_owner,
    FbIsc.isc_info_sql_alias,
    FbIsc.isc_info_sql_describe_end
];

// SQL plan	information
immutable ubyte[] describeStatementPlanInfoItems = [
    FbIsc.isc_info_sql_get_plan
];

// SQL records affected
immutable ubyte[] describeStatementRowsAffectedInfoItems = [
    FbIsc.isc_info_sql_records
];

// SQL type
immutable ubyte[] describeStatementTypeInfoItems = [
    FbIsc.isc_info_sql_stmt_type
];

ubyte[] describeArray(return ref FbArrayWriter writer, ref FbArray array, size_t elements) nothrow @safe
in
{
    assert(array.descriptor.bounds.length > 0);
    assert(array.descriptor.bounds.length < int8.max);
}
do
{
    const descriptorElements = array.descriptor.calculateElements();
    if (elements == 0)
        elements = descriptorElements;

    writer.writeUInt8(FbIsc.isc_sdl_version1);
    writer.writeUInt8(FbIsc.isc_sdl_struct);
    writer.writeUInt8(1);
    writer.writeUInt8(cast(uint8)array.descriptor.blrType);
	switch (array.descriptor.blrType)
	{
		case FbBlrType.blr_short:
		case FbBlrType.blr_long:
		case FbBlrType.blr_quad:
		case FbBlrType.blr_int64:
		case FbBlrType.blr_int128:
			writer.writeInt8(cast(int8)array.descriptor.fieldInfo.numericScale);
			break;
		case FbBlrType.blr_text:
		case FbBlrType.blr_text2:
		case FbBlrType.blr_varying:
		case FbBlrType.blr_varying2:
		case FbBlrType.blr_cstring:
		case FbBlrType.blr_cstring2:
			writer.writeInt16(cast(int16)array.descriptor.fieldInfo.size);
			break;
        default:
            break;
	}
    writer.writeName(FbIsc.isc_sdl_relation, array.descriptor.fieldInfo.tableName);
    writer.writeName(FbIsc.isc_sdl_field, array.descriptor.fieldInfo.name);
    version (FbMultiDimensions)
    {
        foreach (i, ref bound; array.descriptor.bounds)
        {
            if (bound.lower == 1)
            {
                writer.writeUInt8(FbIsc.isc_sdl_do1);
                writer.writeUInt8(cast(uint8)i);
            }
            else
            {
                writer.writeUInt8(FbIsc.isc_sdl_do2);
                writer.writeUInt8(cast(uint8)i);
                writer.writeLiteral(bound.lower);
            }
            writer.writeLiteral(bound.upper);
        }
        writer.writeUInt8(FbIsc.isc_sdl_element);
        writer.writeUInt8(1);
        writer.writeUInt8(FbIsc.isc_sdl_scalar);
        writer.writeUInt8(0);
        writer.writeUInt8(cast(uint8)array.descriptor.bounds.length);
        foreach (i; 0..array.descriptor.bounds.length)
        {
            writer.writeUInt8(FbIsc.isc_sdl_variable);
            writer.writeUInt8(cast(uint8)i);
        }
    }
    else
    {
        const bound = array.descriptor.bounds[0];
        if (bound.lower == 1)
        {
            writer.writeUInt8(FbIsc.isc_sdl_do1);
            writer.writeUInt8(0);
        }
        else
        {
            writer.writeUInt8(FbIsc.isc_sdl_do2);
            writer.writeUInt8(0);
            writer.writeLiteral(bound.lower);
        }
        writer.writeLiteral(bound.lower + elements - 1);
        writer.writeUInt8(FbIsc.isc_sdl_element);
        writer.writeUInt8(1);
        writer.writeUInt8(FbIsc.isc_sdl_scalar);
        writer.writeUInt8(0);
        writer.writeUInt8(1);
        writer.writeUInt8(FbIsc.isc_sdl_variable);
        writer.writeUInt8(0);
    }
    writer.writeUInt8(FbIsc.isc_sdl_eoc);
    return writer.peekBytes();
}

ubyte[] describeTransaction(return ref FbTransactionWriter writer, FbTransaction transaction) nothrow @safe
{
    ubyte lockTableBehavior(const ref DbLockTable lockedTable) nothrow @safe
    {
        final switch (lockedTable.lockBehavior)
        {
            case DbLockBehavior.shared_:
                return FbIsc.isc_tpb_shared;
            case DbLockBehavior.protected_:
                return FbIsc.isc_tpb_protected;
            case DbLockBehavior.exclusive:
                return FbIsc.isc_tpb_exclusive;
        }
    }

    ubyte lockTableReadOrWrite(const ref DbLockTable lockedTable) nothrow @safe
    {
        return lockedTable.lockType == DbLockType.read
            ? FbIsc.isc_tpb_lock_read
            : FbIsc.isc_tpb_lock_write;
    }

    if (transaction.lockedTables.length)
    {
        foreach (ref lockedTable; transaction.lockedTables)
        {
            writer.writeChars(lockTableReadOrWrite(lockedTable), lockedTable.tableName);
            writer.writeType(lockTableBehavior(lockedTable));
        }

        return transaction.transactionItems ~ writer.peekBytes();
    }
    else
        return transaction.transactionItems;
}

ubyte[] describeTransactionItems(return ref FbTransactionWriter writer, FbTransaction transaction) nothrow @safe
{
    void isolationLevel(out ubyte isolationMode, out ubyte versionMode, out ubyte waitMode) nothrow @safe
    {
        final switch (transaction.isolationLevel)
        {
            case DbIsolationLevel.readUncommitted:
                isolationMode = FbIsc.isc_tpb_concurrency;
                versionMode = 0; // Only for isc_tpb_read_committed
                waitMode = FbIsc.isc_tpb_nowait;
                break;

            case DbIsolationLevel.readCommitted:
                isolationMode = FbIsc.isc_tpb_read_committed;
                versionMode = FbIsc.isc_tpb_rec_version;
                waitMode = FbIsc.isc_tpb_wait;
                break;

            case DbIsolationLevel.repeatableRead:
                isolationMode = FbIsc.isc_tpb_concurrency;
                versionMode = 0; // Only for isc_tpb_read_committed
                waitMode = FbIsc.isc_tpb_wait;
                break;

            case DbIsolationLevel.serializable:
                isolationMode = FbIsc.isc_tpb_consistency;
                versionMode = 0; // Only for isc_tpb_read_committed
                waitMode = FbIsc.isc_tpb_wait;
                break;

            case DbIsolationLevel.snapshot:
                isolationMode = FbIsc.isc_tpb_consistency;
                versionMode = 0; // Only for isc_tpb_read_committed
                waitMode = FbIsc.isc_tpb_nowait;
                break;
        }
    }

    ubyte readOrWriteMode() nothrow @safe
    {
        return transaction.readOnly
            ? FbIsc.isc_tpb_read
            : FbIsc.isc_tpb_write;
    }

    ubyte isolationMode, versionMode, waitMode;
    isolationLevel(isolationMode, versionMode, waitMode);

    writer.writeType(FbIsc.isc_tpb_version);
    writer.writeType(isolationMode);
    if (versionMode)
        writer.writeType(versionMode);
    writer.writeType(readOrWriteMode());
    writer.writeType(waitMode);
    if (waitMode != FbIsc.isc_tpb_nowait && transaction.lockTimeout)
        writer.writeInt32(FbIsc.isc_tpb_lock_timeout, toInt32Second(transaction.lockTimeout));
    if (transaction.autoCommit)
        writer.writeType(FbIsc.isc_tpb_autocommit);

    return writer.peekBytes();
}

void describeValue(return ref FbXdrWriter writer, DbNameColumn column, DbValue value) @safe
in
{
    assert(!value.isNull);
}
do
{
    if (column.isArray)
    {
        writer.writeId(value.get!FbId());
        return;
    }

    // Use coerce for implicit basic type conversion
    final switch (column.type)
    {
        case DbType.boolean:
            writer.writeBool(value.coerce!bool());
            return;
        case DbType.int8:
            writer.writeInt16(value.coerce!int8());
            return;
        case DbType.int16:
            writer.writeInt16(value.coerce!int16());
            return;
        case DbType.int32:
            writer.writeInt32(value.coerce!int32());
            return;
        case DbType.int64:
            writer.writeInt64(value.coerce!int64());
            return;
        case DbType.int128:
            writer.writeInt128(value.get!BigInteger());
            return;
        case DbType.decimal:
            writer.writeDecimal!Decimal(value.get!Decimal(), column.baseType);
            return;
        case DbType.decimal32:
            writer.writeDecimal!Decimal32(value.get!Decimal32(), column.baseType);
            return;
        case DbType.decimal64:
            writer.writeDecimal!Decimal64(value.get!Decimal64(), column.baseType);
            return;
        case DbType.decimal128:
            writer.writeDecimal!Decimal128(value.get!Decimal128(), column.baseType);
            return;
        case DbType.numeric:
            writer.writeDecimal!Numeric(value.get!Numeric(), column.baseType);
            return;
        case DbType.float32:
            writer.writeFloat32(value.coerce!float32());
            return;
        case DbType.float64:
            writer.writeFloat64(value.coerce!float64());
            return;
        case DbType.date:
            writer.writeDate(value.get!Date());
            return;
        case DbType.datetime:
            writer.writeDateTime(value.get!DbDateTime());
            return;
        case DbType.datetimeTZ:
            writer.writeDateTimeTZ(value.get!DbDateTime());
            return;
        case DbType.time:
            writer.writeTime(value.get!DbTime());
            return;
        case DbType.timeTZ:
            writer.writeTimeTZ(value.get!DbTime());
            return;
        case DbType.uuid:
            writer.writeUUID(value.get!UUID());
            return;
        case DbType.chars:
            writer.writeFixedChars(value.get!string(), column.baseType);
            return;
        case DbType.string:
            writer.writeChars(value.get!string());
            return;
        case DbType.text:
        case DbType.json:
        case DbType.xml:
        case DbType.binary:
            writer.writeId(value.get!FbId());
            return;

        case DbType.record:
        case DbType.array:
        case DbType.unknown:
            auto msg = format(DbMessage.eUnsupportDataType, functionName(), toName!DbType(column.type));
            throw new FbException(msg, DbErrorCode.write, 0, FbIscResultCode.isc_net_write_err);
    }
}


// Any below codes are private
private:
