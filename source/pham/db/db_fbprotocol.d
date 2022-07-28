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
import std.range.primitives : isOutputRange, put;
import std.typecons : Flag, No, Yes;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.utl.bit_array : BitArrayImpl, bitLengthToElement, hostToNetworkOrder;
import pham.utl.enum_set : toName;
import pham.utl.object : InitializedValue, bytesFromHexs, bytesToHexs, functionName,
    currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.db.buffer_filter;
import pham.db.buffer_filter_cipher;
import pham.db.buffer_filter_compressor;
import pham.db.convert;
import pham.db.database : DbNameColumn;
import pham.db.message;
import pham.db.object : DbDisposableObject;
import pham.db.type;
import pham.db.util;
import pham.db.value;
import pham.db.fbauth;
import pham.db.fbbuffer;
import pham.db.fbdatabase;
import pham.db.fbexception;
import pham.db.fbisc;
import pham.db.fbtype;

/**
    Returns:
        length of blob in bytes
 */
size_t parseBlob(W)(scope ref W sink, scope const(ubyte)[] data) @safe
if (isOutputRange!(W, ubyte))
{
    size_t result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2; // -2 for item length
	size_t pos = 0;
	while (pos < endPos)
	{
        const len = parseInt32!true(data, pos, 2, FbIscType.sql_blob);
        put(sink, data[pos..pos + len]);
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
		if (typ == FbIsc.isc_info_sql_records)
		{
            if (pos < endPos)
                parseRecordValues();
            else
                break;
        }
        else
		    pos += len;
	}

	return result;
}

struct FbConnectingStateInfo
{
nothrow @safe:

    FbAuth auth;
    CipherBuffer authData;
    const(char)[] authMethod;
    CipherBuffer serverAuthData;
    CipherBuffer serverAuthKey;
    const(char)[] serverAuthMethod;
    int32 serverAcceptType;
    int32 serverArchitecture;
    int32 serverVersion;
    int nextAuthState;
}

alias FbDeferredResponse = void delegate() @safe;

class FbProtocol : DbDisposableObject
{
@safe:

public:
    this(FbConnection connection) nothrow pure
    {
        this._connection = connection;
    }

    final FbIscObject allocateCommandRead(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);
        return r.getIscObject();
    }

    final void allocateCommandWrite()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        allocateCommandWrite(writer);
        writer.flush();
    }

    final void allocateCommandWrite(ref FbXdrWriter writer) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

		writer.writeOperation(FbIsc.op_allocate_statement);
		writer.writeHandle(connection.fbHandle);
    }

    final FbIscArrayGetResponse arrayGetRead(ref FbArray array)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_slice);
        return readArrayGetResponseImpl(reader, array.descriptor);
    }

    final void arrayGetWrite(ref FbArray array)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
        return r.getIscObject();
    }

    final void arrayPutWrite(ref FbArray array, uint32 elements, scope const(ubyte)[] encodedArrayValue)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
        return r.getIscObject();
    }

    final void blobBeginWrite(ref FbBlob blob, FbOperation createOrOpen)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(createOrOpen);
        writer.writeHandle(blob.fbTransaction.fbHandle);
        writer.writeId(blob.fbId);
        writer.flush();
    }

    final void blobEndRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void blobEndWrite(ref FbBlob blob, FbOperation closeOrCancelOp)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        blobEndWrite(writer, blob, closeOrCancelOp);
        writer.flush();
    }

    final void blobEndWrite(ref FbXdrWriter writer, ref FbBlob blob, FbOperation closeOrCancelOp) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

	    writer.writeOperation(closeOrCancelOp);
		writer.writeHandle(blob.fbHandle);
    }

    final FbIscGenericResponse blobGetSegmentsRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
        return r;
    }

    final void blobGetSegmentsWrite(ref FbBlob blob)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void blobPutSegmentsWrite(ref FbBlob blob, scope const(ubyte)[] segment)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_batch_segments);
		writer.writeHandle(blob.fbHandle);
        writer.writeBlob(segment);
        writer.flush();
    }

    final FbIscBlobSize blobSizeInfoRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
		if (r.data.length)
            return FbIscBlobSize(r.data);
        else
            return FbIscBlobSize.init;
    }

    final void blobSizeInfoWrite(ref FbBlob blob)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_info_blob);
		writer.writeHandle(blob.fbHandle);
		writer.writeInt32(0);
		writer.writeBytes(describeBlobSizeInfoItems);
		writer.writeInt32(FbIscSize.blobSizeInfoBufferLength);
        writer.flush();
    }

    final void cancelRequestWrite(FbHandle handle)
    {
        cancelRequestWrite(handle, FbIsc.fb_cancel_raise);
    }

    final void closeCursorCommandRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void closeCursorCommandWrite(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_free_statement);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(FbIsc.dsql_close);
        writer.flush();
    }

    final void commitRetainingTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void commitTransactionRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(connection.notificationMessages);
    }

    final void commitTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject connectAttachmentRead(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        r.statues.getWarn(connection.notificationMessages);
        return r.getIscObject();
    }

    final void connectAttachmentWrite(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto useCSB = connection.connectionStringBuilder;
        auto writerAI = FbConnectionWriter(connection, FbIsc.isc_dpb_version);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_attach);
		writer.writeHandle(0);
		writer.writeChars(useCSB.databaseName);
        writer.writeBytes(describeAttachmentInformation(writerAI, stateInfo));
        writer.flush();
    }

    final void connectAuthenticationRead(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        void setupCompression()
        {
            const compress = canCompressConnection(stateInfo);
			if (compress == DbCompressConnection.zip)
            {
                connection.serverInfo[DbServerIdentifier.protocolCompressed] = toName(compress);
                compressSetupBufferFilter();
            }
        }

        bool setupEncryption()
        {
            const encrypted = canCryptedConnection(stateInfo);
            if (encrypted != DbEncryptedConnection.disabled)
            {
                connection.serverInfo[DbServerIdentifier.protocolEncrypted] = toName(encrypted);
                cryptWrite(stateInfo);
                cryptSetupBufferFilter(stateInfo); // after writing before reading
                cryptRead(stateInfo);
                return true;
            }
            else
                return false;
        }

        FbXdrReader reader;
        const op = readOperation(reader, 0);
        switch (op)
        {
            case FbIsc.op_accept:
                auto aResponse = readAcceptResponseImpl(reader);
                stateInfo.serverAcceptType = aResponse.acceptType;
                stateInfo.serverArchitecture = aResponse.architecture;
                stateInfo.serverVersion = aResponse.version_;
                this._serverVersion = stateInfo.serverVersion;
                connection.serverInfo[DbServerIdentifier.protocolAcceptType] = to!string(stateInfo.serverAcceptType);
                connection.serverInfo[DbServerIdentifier.protocolArchitect] = to!string(stateInfo.serverArchitecture);
                connection.serverInfo[DbServerIdentifier.protocolVersion] = to!string(stateInfo.serverVersion);
                setupCompression();
                validateRequiredEncryption(setupEncryption());
                break;

            case FbIsc.op_accept_data:
            case FbIsc.op_cond_accept:
                auto adResponse = readAcceptDataResponseImpl(reader);
                stateInfo.serverAcceptType = adResponse.acceptType;
                stateInfo.serverArchitecture = adResponse.architecture;
                stateInfo.serverVersion = adResponse.version_;
                stateInfo.serverAuthKey = adResponse.authKey;
                stateInfo.serverAuthData = adResponse.authData;
                stateInfo.serverAuthMethod = adResponse.authName;
                this._serverVersion = stateInfo.serverVersion;
                connection.serverInfo[DbServerIdentifier.protocolAcceptType] = to!string(stateInfo.serverAcceptType);
                connection.serverInfo[DbServerIdentifier.protocolArchitect] = to!string(stateInfo.serverArchitecture);
                connection.serverInfo[DbServerIdentifier.protocolVersion] = to!string(stateInfo.serverVersion);

				if (!adResponse.isAuthenticated || op == FbIsc.op_cond_accept)
				{
					if (stateInfo.auth is null || stateInfo.serverAuthMethod != stateInfo.authMethod)
                    {
                        auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(stateInfo.serverAuthMethod);
                        throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
                    }

                    auto useCSB = connection.connectionStringBuilder;
                    auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword, stateInfo.serverAuthData[], stateInfo.authData);
                    if (status.isError)
                    {
                        auto msg = stateInfo.auth.getErrorMessage(status, stateInfo.authMethod);
                        throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
                    }
				}

                setupCompression(); // Before further sending requests

                // Authentication info will be resent when doing attachment for other op
                if (op == FbIsc.op_cond_accept)
				{
                    connectAuthenticationAcceptWrite(stateInfo);
                    connectAuthenticationAcceptRead(stateInfo);
				}

                validateRequiredEncryption(setupEncryption());
                return;

            case FbIsc.op_response:
                auto r = readGenericResponseImpl(reader);
                r.statues.getWarn(connection.notificationMessages);
                goto default;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, "authentication");
                throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void connectAuthenticationWrite(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        clearServerInfo();

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
        writer.writeBytes(describeUserIdentification(writerUI, stateInfo));
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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void deallocateCommandWrite(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        deallocateCommandWrite(writer, command);
        writer.flush();
    }

    final void deallocateCommandWrite(ref FbXdrWriter writer, FbCommand command) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

		writer.writeOperation(FbIsc.op_free_statement);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(FbIsc.dsql_drop);
    }

    final void disconnectWrite()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        if (connection.handle)
        {
		    writer.writeOperation(FbIsc.op_detach);
		    writer.writeHandle(connection.fbHandle);
        }
		writer.writeOperation(FbIsc.op_disconnect);
        writer.flush();

        clearServerInfo();
    }

    final void executeCommandRead(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        // Nothing to process - just need acknowledge
        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);
    }

    final void executeCommandWrite(FbCommand command, DbCommandExecuteType type)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("type=", type);

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(command.isStoredProcedure ? FbIsc.op_execute2 : FbIsc.op_execute);
		writer.writeHandle(command.fbHandle);
		writer.writeHandle(command.fbTransaction.fbHandle);

        auto inputParameters = command.fbInputParameters();
		if (inputParameters.length)
		{
            auto pWriterBlr = FbBlrWriter(connection);
            auto pPrmBlr = describeBlrParameters(pWriterBlr, inputParameters);
            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("pPrmBlr=", pPrmBlr);

            auto pWriterVal = FbXdrWriter(connection);
            auto pPrmVal = describeParameters(pWriterVal, inputParameters);
            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("pPrmVal=", pPrmVal);

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
            auto pFldBlr = describeBlrFields(pWriterBlr, command.fbFields);
            writer.writeBytes(pFldBlr);
			writer.writeInt32(0); // Output message number
		}

        writer.flush();
    }

    final FbCommandPlanInfo.Kind executionPlanCommandInfoRead(FbCommand command, uint mode,
        out FbCommandPlanInfo info)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        const describeMode = mode == 0
            ? FbIsc.isc_info_sql_get_plan
            : FbIsc.isc_info_sql_explain_plan;

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);

        FbCommandPlanInfo.Kind kind;
        if (r.data.length == 0)
            kind = FbCommandPlanInfo.Kind.noData;
		else if (r.data[0] == FbIsc.isc_info_end)
            kind = FbCommandPlanInfo.Kind.empty;
        else if (r.data[0] == FbIsc.isc_info_truncated)
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
                info = FbCommandPlanInfo(kind, r.data, describeMode);
                return kind;
        }
    }

    final void executionPlanCommandInfoWrite(FbCommand command, uint mode, uint32 bufferLength)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto describeItems = mode == 0
            ? describeStatementPlanInfoItems
            : describeStatementExplaindPlanInfoItems;
        commandInfoWrite(command, describeItems, bufferLength);
    }

    final FbIscFetchResponse fetchCommandRead(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, 0);
        if (op == FbIsc.op_response)
        {
            auto r = readGenericResponseImpl(reader);
            r.statues.getWarn(command.notificationMessages);
            return FbIscFetchResponse(0, 0);
        }
        else if (op == FbIsc.op_fetch_response)
            return readFetchResponseImpl(reader);
        else
        {
            auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(op, FbIsc.op_response);
            throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_net_read_err);
        }
    }

    final void fetchCommandWrite(FbCommand command)
    in
    {
        assert(command.hasFields);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writerBlr = FbBlrWriter(connection);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_fetch);
		writer.writeHandle(command.fbHandle);
		writer.writeBytes(describeBlrFields(writerBlr, command.fbFields));
		writer.writeInt32(0); // p_sqldata_message_number
		writer.writeInt32(command.fetchRecordCount); // p_sqldata_messages
		writer.flush();
    }

    final FbIscBindInfo[] prepareCommandRead(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);

        FbIscBindInfo[] bindResults;
        ptrdiff_t previousBindIndex = -1; // Start with unknown value
        ptrdiff_t previousFieldIndex = 0;

        while (!FbIscBindInfo.parse(r.data, bindResults, previousBindIndex, previousFieldIndex))
        {
            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("previousBindIndex=", previousBindIndex, ", previousFieldIndex=", previousFieldIndex);

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
            r = readGenericResponse();
            r.statues.getWarn(command.notificationMessages);
        }

        return bindResults;
    }

    final prepareCommandWrite(FbCommand command, scope const(char)[] sql)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        prepareCommandWrite(writer, command, sql);
        writer.flush();
    }

    final prepareCommandWrite(ref FbXdrWriter writer, FbCommand command, scope const(char)[] sql) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        DbRecordsAffected result;
        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
		if (r.data.length)
		{
            const counts = parseRecordsAffected(r.data);
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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        commandInfoWrite(command, describeStatementRowsAffectedInfoItems, FbIscSize.rowsEffectedBufferLength);
    }

    final void rollbackRetainingTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void rollbackTransactionRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(connection.notificationMessages);
    }

    final void rollbackTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject startTransactionRead()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        //r.statues.getWarn(connection.notificationMessages);
        return r.getIscObject();
    }

    final void startTransactionWrite(FbTransaction transaction)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto paramWriter = FbTransactionWriter(connection);
        auto paramBytes = describeTransaction(paramWriter, transaction);

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_transaction);
	    writer.writeHandle(connection.fbHandle);
	    writer.writeBytes(paramBytes);
        writer.flush();
    }

    final int typeCommandRead(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);
		if (r.data.length)
            return parseCommandType(r.data);
        else
            return FbIscCommandType.none;
    }

    final void typeCommandWrite(FbCommand command)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        commandInfoWrite(command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength);
    }

    final void typeCommandWrite(ref FbXdrWriter writer, FbCommand command) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        commandInfoWrite(writer, command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength);
    }

    final FbIscGenericResponse readGenericResponse()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_response);
        return readGenericResponseImpl(reader);
    }

    version (none)
    final FbResponse readResponse(FbOperation mainOp)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, 0);
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
                auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(op, mainOp);
                throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_net_read_err);
        }
    }

    final FbIscSqlResponse readSqlResponse()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_sql_response);
        return readSqlResponseImpl(reader);
    }

    final DbValue readValue(ref FbXdrReader reader, FbCommand command, DbNameColumn column)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")(column.traceString());
        version (profile) debug auto p = PerfFunction.create();

        const dbType = column.type;

        if (column.isArray)
            return DbValue.entity(reader.readId(), dbType);

        final switch (dbType)
        {
            case DbType.boolean:
                return DbValue(reader.readBool(), dbType);
            case DbType.int8:
                return DbValue(cast(int8)reader.readInt16(), dbType);
            case DbType.int16:
                return DbValue(reader.readInt16(), dbType);
            case DbType.int32:
                return DbValue(reader.readInt32(), dbType);
            case DbType.int64:
                return DbValue(reader.readInt64(), dbType);
            case DbType.int128:
                return DbValue(reader.readInt128(), dbType);
            case DbType.decimal:
                return DbValue(reader.readDecimal!Decimal(column.baseType), dbType);
            case DbType.decimal32:
                return DbValue(reader.readDecimal!Decimal32(column.baseType), dbType);
            case DbType.decimal64:
                return DbValue(reader.readDecimal!Decimal64(column.baseType), dbType);
            case DbType.decimal128:
                return DbValue(reader.readDecimal!Decimal128(column.baseType), dbType);
            case DbType.numeric:
                return DbValue(reader.readDecimal!Numeric(column.baseType), dbType);
            case DbType.float32:
                return DbValue(reader.readFloat32(), dbType);
            case DbType.float64:
                return DbValue(reader.readFloat64(), dbType);
            case DbType.date:
                return DbValue(reader.readDate(), dbType);
            case DbType.datetime:
                return DbValue(reader.readDateTime(), dbType);
            case DbType.datetimeTZ:
                return DbValue(reader.readDateTimeTZ(), dbType);
            case DbType.time:
                return DbValue(reader.readTime(), dbType);
            case DbType.timeTZ:
                return DbValue(reader.readTimeTZ(), dbType);
            case DbType.uuid:
                return DbValue(reader.readUUID(), dbType);
            case DbType.fixedString:
                return DbValue(reader.readFixedString(column.baseType), dbType);
            case DbType.string:
                return DbValue(reader.readString(), dbType);
            case DbType.json:
            case DbType.xml:
            case DbType.text:
            case DbType.fixedBinary:
            case DbType.binary:
                return DbValue.entity(reader.readId(), dbType);

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(functionName!(typeof(this))(), toName!DbType(dbType));
                throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_net_read_err);
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
        assert(0, toName!DbType(dbType));
    }

    final DbRowValue readValues(FbCommand command, FbFieldList fields)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();
        version (profile) debug auto p = PerfFunction.create();

        auto reader = FbXdrReader(connection);

        const nullBitmapBytes = bitLengthToElement!ubyte(fields.length);
		const nullBitmap = BitArrayImpl!ubyte(reader.readOpaqueBytes(nullBitmapBytes));

        auto result = DbRowValue(fields.length);
        size_t i = 0;
        foreach (field; fields)
        {
            if (nullBitmap[i])
                result[i++].nullify();
            else
                result[i++] = readValue(reader, command, field);
        }
        return result;
    }

    @property final FbConnection connection() nothrow pure
    {
        return _connection;
    }

    @property final int32 serverVersion() const nothrow pure @nogc
    {
        return _serverVersion;
    }

protected:
    final void cancelRequestWrite(FbHandle handle, int32 cancelKind)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("cancelKind=", cancelKind);

        auto writer = FbXdrWriter(connection);
        writer.writeHandle(handle);
		writer.writeOperation(FbIsc.op_cancel);
        writer.writeInt32(cancelKind);
		writer.flush();
    }

    final DbCompressConnection canCompressConnection(ref FbConnectingStateInfo stateInfo) nothrow
    {
        if (stateInfo.serverVersion < FbIsc.protocol_version13)
            return DbCompressConnection.disabled;

        if ((stateInfo.serverAcceptType & FbIsc.ptype_compress_flag) == 0)
			return DbCompressConnection.disabled;

        return connection.fbConnectionStringBuilder.compress;
    }

    final DbEncryptedConnection canCryptedConnection(ref FbConnectingStateInfo stateInfo) nothrow
    {
        if (stateInfo.serverVersion < FbIsc.protocol_version13)
            return DbEncryptedConnection.disabled;

        return stateInfo.auth !is null
                && stateInfo.auth.canCryptedConnection()
                && getCryptedConnectionCode() != FbIsc.connect_crypt_disabled
            ? DbEncryptedConnection.enabled
            : DbEncryptedConnection.disabled;
    }

    final void clearServerInfo()
    {
        _serverVersion = 0;
    }

    final void commandInfoWrite(FbCommand command, scope const(ubyte)[] items, uint32 resultBufferLength)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
        commandInfoWrite(writer, command, items, resultBufferLength);
        writer.flush();
    }

    final void commandInfoWrite(ref FbXdrWriter writer, FbCommand command, scope const(ubyte)[] items,
        uint32 resultBufferLength) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

		writer.writeOperation(FbIsc.op_info_sql);
        writer.writeHandle(command.fbHandle);
		writer.writeInt32(0);
		writer.writeBytes(items);
		writer.writeInt32(resultBufferLength);
    }

    final void compressSetupBufferFilter()
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

		auto compressor = new DbBufferFilterCompressorZip!(DbBufferFilterKind.write)();
		auto decompressor = new DbBufferFilterCompressorZip!(DbBufferFilterKind.read)();
		connection.chainBufferFilters(decompressor, compressor);
    }

    final void connectAuthenticationAcceptRead(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, 0);
        switch (op)
        {
            case FbIsc.op_response:
                auto r = readGenericResponseImpl(reader);
                r.statues.getWarn(connection.notificationMessages);
                stateInfo.serverAuthKey = r.data;
                break;

            case FbIsc.op_trusted_auth:
                auto tResponse = readTrustedAuthResponseImpl(reader);
                stateInfo.serverAuthKey = tResponse.data;
                break;

            case FbIsc.op_cont_auth:
                auto cResponse = readCondAuthResponseImpl(reader);
                stateInfo.serverAuthKey = cResponse.key;
                stateInfo.serverAuthMethod = cResponse.name;
                if (stateInfo.serverAuthMethod.length != 0)
                {
                    if (stateInfo.serverAuthMethod != stateInfo.authMethod)
                    {
                        stateInfo.nextAuthState = 0;
                        stateInfo.authMethod = stateInfo.serverAuthMethod;
                        stateInfo.auth = createAuth(stateInfo.authMethod);
                    }
                    auto useCSB = connection.connectionStringBuilder;
                    auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword, cResponse.data, stateInfo.authData);
                    if (status.isError)
                    {
                        auto msg = stateInfo.auth.getErrorMessage(status, stateInfo.authMethod);
                        throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
                    }
                }
                break;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, "authentication");
                throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void connectAuthenticationAcceptWrite(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_cont_auth);
		writer.writeBytes(stateInfo.authData[]);
		writer.writeChars(stateInfo.auth.name); // like CNCT_plugin_name
		writer.writeChars(stateInfo.auth.name); // like CNCT_plugin_list
		writer.writeBytes(stateInfo.serverAuthKey[]);
        stateInfo.nextAuthState++;
		writer.flush();
    }

    final FbAuth createAuth(const(char)[] authMethod)
    {
        auto authMap = FbAuth.findAuthMap(authMethod);
        if (!authMap.isValid())
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(authMethod);
            throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
        }

        return cast(FbAuth)authMap.createAuth();
    }

    final void cryptRead(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        FbXdrReader reader;
        const op = readOperation(reader, 0);
        switch (op)
        {
            case FbIsc.op_crypt_key_callback:
                readCryptKeyCallbackResponseImpl(reader);
                break;

            case FbIsc.op_response:
                auto r = readGenericResponseImpl(reader);
                r.statues.getWarn(connection.notificationMessages);
                break;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, "encryption");
                throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void cryptSetupBufferFilter(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("sessionKey=", stateInfo.auth.sessionKey().dgToHex());

        auto privateKey = CipherKey(0, stateInfo.auth.sessionKey());
		auto encryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.write)(privateKey);
		auto decryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.read)(privateKey);
		connection.chainBufferFilters(decryptor, encryptor);
    }

    final void cryptWrite(ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_crypt);
		writer.writeChars(FbIscText.isc_filter_arc4_name);
        writer.writeChars(stateInfo.auth.sessionKeyName);
        writer.flush();
    }

    final ubyte[] describeArray(return ref FbArrayWriter writer, ref FbArray array, size_t elements) nothrow
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
        
        switch (array.descriptor.blrType)
        {            
		    case FbBlrType.blr_text: // Map blr_text to blr_text2
                writer.writeUInt8(cast(uint8)FbBlrType.blr_text2);
                break;
		    case FbBlrType.blr_varying: // Map blr_varying to blr_varying2
                writer.writeUInt8(cast(uint8)FbBlrType.blr_varying2);
                break;
            default:
                writer.writeUInt8(cast(uint8)array.descriptor.blrType);
                break;
        }
        
	    switch (array.descriptor.blrType)
	    {
		    case FbBlrType.blr_short:
		    case FbBlrType.blr_long:
		    case FbBlrType.blr_quad:
		    case FbBlrType.blr_int64:
		    case FbBlrType.blr_int128:
			    writer.writeInt8(cast(int8)array.descriptor.fieldInfo.numericScale);
			    break;
		    case FbBlrType.blr_cstring:
		    case FbBlrType.blr_cstring2:
			    writer.writeInt16(cast(int16)array.descriptor.fieldInfo.size);
			    break;
		    case FbBlrType.blr_text: // Map blr_text to blr_text2
		    case FbBlrType.blr_text2:
		    case FbBlrType.blr_varying: // Map blr_varying to blr_varying2
		    case FbBlrType.blr_varying2:
			    writer.writeInt16(cast(int16)array.descriptor.fieldInfo.subType);            
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
            writer.writeLiteral(cast(int32)(bound.lower + elements - 1));
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

    final ubyte[] describeAttachmentInformation(return ref FbConnectionWriter writer, ref FbConnectingStateInfo stateInfo)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("stateInfo.authData=", stateInfo.authData.toString());

        auto useCSB = connection.fbConnectionStringBuilder;

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("connectionTimeout=", useCSB.connectionTimeout.toRangeSecond32());

        version (none)
        bool needSendPassword() nothrow pure @safe
        {
            if (stateInfo.authData.length)
                return false;
            else if (stateInfo.serverVersion < FbIsc.protocol_version12)
                return true;
            else if (stateInfo.serverVersion == FbIsc.protocol_version12)
            {
                const iss = useCSB.integratedSecurity;
                return iss != DbIntegratedSecurityConnection.sspi &&
                    iss != DbIntegratedSecurityConnection.trusted;
            }
            else
                return false;
        }

		writer.writeType(FbIsc.isc_dpb_version);
		writer.writeInt32(FbIsc.isc_dpb_dummy_packet_interval, useCSB.dummyPackageInterval.toRangeSecond32());
		writer.writeInt32(FbIsc.isc_dpb_sql_dialect, useCSB.dialect);
		writer.writeChars(FbIsc.isc_dpb_lc_ctype, useCSB.charset);
        writer.writeCharsIf(FbIsc.isc_dpb_user_name, useCSB.userName);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, useCSB.roleName);
		writer.writeInt32(FbIsc.isc_dpb_connect_timeout, useCSB.connectionTimeout.toRangeSecond32());
		writer.writeInt32(FbIsc.isc_dpb_process_id, currentProcessId());
		writer.writeChars(FbIsc.isc_dpb_process_name, currentProcessName());
		writer.writeCharsIf(FbIsc.isc_dpb_client_version, useCSB.applicationVersion);
		if (stateInfo.authData.length)
		    writer.writeBytes(FbIsc.isc_dpb_specific_auth_data, stateInfo.authData[]);
		if (useCSB.cachePages)
			writer.writeInt32(FbIsc.isc_dpb_num_buffers, useCSB.cachePages);
		if (!useCSB.databaseTrigger)
		    writer.writeInt32(FbIsc.isc_dpb_no_db_triggers, 1);
		if (!useCSB.garbageCollect)
		    writer.writeInt32(FbIsc.isc_dpb_no_garbage_collect, 1);
		writer.writeInt32(FbIsc.isc_dpb_utf8_filename, 1); // This is weirdess - must be last or fail to authenticate

        auto result = writer.peekBytes();

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("dpbValue.length=", result.length, ", dpbValue=", result.dgToHex());

        return result;
    }

    final ubyte[] describeBlrFields(return ref FbBlrWriter writer, FbFieldList fields) nothrow
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
            writer.writeColumn(field.baseType, field.baseSubTypeId, field.baseSize);
        }
        writer.writeEnd(fields.length);

        auto result = writer.peekBytes();
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("result=", result.dgToHex());
        return result;
    }

    final ubyte[] describeBlrParameters(return ref FbBlrWriter writer, scope FbParameter[] parameters) nothrow
    in
    {
        assert(parameters !is null);
        assert(parameters.length != 0 && parameters.length <= ushort.max / 2);
    }
    do
    {
        writer.writeBegin(parameters.length);
        foreach (parameter; parameters)
        {
            writer.writeColumn(parameter.baseType, parameter.baseSubTypeId, parameter.baseSize);
        }
        writer.writeEnd(parameters.length);
        return writer.peekBytes();
    }

    final ubyte[] describeParameters(return ref FbXdrWriter writer, scope FbParameter[] parameters)
    in
    {
        assert(parameters !is null);
        assert(parameters.length != 0 && parameters.length <= ushort.max / 2);
    }
    do
    {
        // Null indicators
        auto nullBitmap = BitArrayImpl!ubyte(parameters.length);
        foreach (i, parameter; parameters)
        {
            if (parameter.value.isNull)
                nullBitmap[i] = true;
        }
        writer.writeOpaqueBytes(nullBitmap[], nullBitmap[].length);

        // Values
        foreach (parameter; parameters)
        {
            if (!parameter.value.isNull)
                describeValue(writer, parameter, parameter.value);
        }

        return writer.peekBytes();
    }

    final ubyte[] describeTransaction(return ref FbTransactionWriter writer, FbTransaction transaction) nothrow
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

    public static ubyte[] describeTransactionItems(return ref FbTransactionWriter writer, FbTransaction transaction) nothrow
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
            writer.writeInt32(FbIsc.isc_tpb_lock_timeout, toRangeSecond32(transaction.lockTimeout));
        if (transaction.autoCommit)
            writer.writeType(FbIsc.isc_tpb_autocommit);

        return writer.peekBytes();
    }

    final ubyte[] describeUserIdentification(return ref FbConnectionWriter writer, ref FbConnectingStateInfo stateInfo)
    {
        auto useCSB = connection.fbConnectionStringBuilder;

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("userName=", useCSB.userName);

        stateInfo.nextAuthState = 0;
        stateInfo.authData = null;
        stateInfo.authMethod = useCSB.integratedSecurityName;
        stateInfo.auth = createAuth(stateInfo.authMethod);

        writer.writeChars(FbIsc.cnct_user, currentUserName());
        writer.writeChars(FbIsc.cnct_host, currentComputerName());
        writer.writeInt8(FbIsc.cnct_user_verification, 0);
        writer.writeChars(FbIsc.cnct_login, useCSB.userName);
        writer.writeChars(FbIsc.cnct_plugin_name, stateInfo.authMethod);
        writer.writeChars(FbIsc.cnct_plugin_list, stateInfo.authMethod);

        if (stateInfo.auth.multiStates > 1)
        {
            auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword, null, stateInfo.authData);
            if (status.isError)
            {
                auto msg = stateInfo.auth.getErrorMessage(status, stateInfo.authMethod);
                throw new FbException(msg, DbErrorCode.write, null, 0, FbIscResultCode.isc_auth_data);
            }

            writer.writeMultiParts(FbIsc.cnct_specific_data, stateInfo.authData[]);
            writer.writeInt32(FbIsc.cnct_client_crypt, hostToNetworkOrder!int32(getCryptedConnectionCode()));
            stateInfo.nextAuthState++;

            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("specificData=", stateInfo.authData.toString());
        }

        auto result = writer.peekBytes();

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("result=", result.dgToHex());

        return result;
    }

    final void describeValue(return ref FbXdrWriter writer, DbNameColumn column, ref DbValue value)
    in
    {
        assert(!value.isNull);
    }
    do
    {
        if (column.isArray)
            return writer.writeId(value.get!FbId());

        // Use coerce for implicit basic type conversion
        final switch (column.type)
        {
            case DbType.boolean:
                return writer.writeBool(value.coerce!bool());
            case DbType.int8:
                return writer.writeInt16(value.coerce!int8());
            case DbType.int16:
                return writer.writeInt16(value.coerce!int16());
            case DbType.int32:
                return writer.writeInt32(value.coerce!int32());
            case DbType.int64:
                return writer.writeInt64(value.coerce!int64());
            case DbType.int128:
                return writer.writeInt128(value.get!BigInteger());
            case DbType.decimal:
                return writer.writeDecimal!Decimal(value.get!Decimal(), column.baseType);
            case DbType.decimal32:
                return writer.writeDecimal!Decimal32(value.get!Decimal32(), column.baseType);
            case DbType.decimal64:
                return writer.writeDecimal!Decimal64(value.get!Decimal64(), column.baseType);
            case DbType.decimal128:
                return writer.writeDecimal!Decimal128(value.get!Decimal128(), column.baseType);
            case DbType.numeric:
                return writer.writeDecimal!Numeric(value.get!Numeric(), column.baseType);
            case DbType.float32:
                return writer.writeFloat32(value.coerce!float32());
            case DbType.float64:
                return writer.writeFloat64(value.coerce!float64());
            case DbType.date:
                return writer.writeDate(value.get!Date());
            case DbType.datetime:
                return writer.writeDateTime(value.get!DbDateTime());
            case DbType.datetimeTZ:
                return writer.writeDateTimeTZ(value.get!DbDateTime());
            case DbType.time:
                return writer.writeTime(value.get!DbTime());
            case DbType.timeTZ:
                return writer.writeTimeTZ(value.get!DbTime());
            case DbType.uuid:
                return writer.writeUUID(value.get!UUID());
            case DbType.fixedString:
                return writer.writeFixedChars(value.get!string(), column.baseType);
            case DbType.string:
                return writer.writeChars(value.get!string());
            case DbType.text:
            case DbType.json:
            case DbType.xml:
            case DbType.fixedBinary:
            case DbType.binary:
                return writer.writeId(value.get!FbId());

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(functionName(), toName!DbType(column.type));
                throw new FbException(msg, DbErrorCode.write, null, 0, FbIscResultCode.isc_net_write_err);
        }
    }

    override void doDispose(bool disposing) nothrow
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        _connection = null;
        _serverVersion = 0;
    }

    final int32 getCryptedConnectionCode() nothrow
    {
        auto useCSB = connection.connectionStringBuilder;

        // Check security settting that supports encryption regardless of encrypt setting
        final switch (useCSB.integratedSecurity) with (DbIntegratedSecurityConnection)
        {
            case srp1:
            case srp256:
                break;
            case legacy:
            case sspi:
                return FbIsc.connect_crypt_disabled;
        }

        final switch (useCSB.encrypt) with (DbEncryptedConnection)
        {
            case disabled:
                return FbIsc.connect_crypt_disabled;
            case enabled:
                return FbIsc.connect_crypt_enabled;
            case required:
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

    final FbIscArrayGetResponse readArrayGetResponseImpl(ref FbXdrReader reader, scope const(FbIscArrayDescriptor) descriptor)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

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
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto rStatus = reader.readInt32();
        auto rCount = reader.readInt32();

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("rStatus=", rStatus, ", rCount=", rCount);

        return FbIscFetchResponse(rStatus, rCount);
    }

    final FbIscGenericResponse readGenericResponseImpl(ref FbXdrReader reader)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto rHandle = reader.readHandle();
        auto rId = reader.readId();
        auto rData = reader.readBytes();
        auto rStatues = reader.readStatuses();

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("rHandle=", rHandle, ", rId=", rId, ", rData=", rData.dgToHex());

        if (rStatues.isError)
        {
            version (TraceFunction) traceFunction!("pham.db.fbdatabase")("errorCode=", rStatues.errorCode());

            throw new FbException(rStatues);
        }
        else if (rStatues.hasWarn)
        {
            //todo check for warning status
        }

        return FbIscGenericResponse(rHandle, rId, rData, rStatues);
    }

    final FbOperation readOperation(out FbXdrReader reader, const(FbOperation) expectedOperation) @trusted
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("deferredResponses.length=", deferredResponses.length);

        if (deferredResponses.length != 0)
        {
            auto responses = deferredResponses;
            deferredResponses = [];
            foreach (response; responses)
                response();
        }

        reader = FbXdrReader(connection);
        auto result = reader.readOperation();
        if (expectedOperation != 0 && expectedOperation != result)
        {
            auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(result, expectedOperation);
            throw new FbException(msg, DbErrorCode.read, null, 0, FbIscResultCode.isc_net_read_err);
        }
        return result;
    }

    final FbIscSqlResponse readSqlResponseImpl(ref FbXdrReader reader)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")();

        auto rCount = reader.readInt32();

        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("rCount=", rCount);

        return FbIscSqlResponse(rCount);
    }

    final FbIscTrustedAuthResponse readTrustedAuthResponseImpl(ref FbXdrReader reader)
    {
        auto rData = reader.readBytes().dup;

        return FbIscTrustedAuthResponse(rData);
    }

    final void validateRequiredEncryption(bool wasEncryptedSetup)
    {
		if (!wasEncryptedSetup && getCryptedConnectionCode() == FbIsc.connect_crypt_required)
        {
            auto msg = DbMessage.eInvalidConnectionRequiredEncryption.fmtMessage(connection.connectionStringBuilder.forErrorInfo);
            throw new FbException(msg, DbErrorCode.connect, null, 0, FbIscResultCode.isc_wirecrypt_incompatible);
        }
    }

public:
    FbDeferredResponse[] deferredResponses;

private:
    FbConnection _connection;
    int32 _serverVersion;
}

static immutable ubyte[] describeBlobSizeInfoItems = [
    FbIsc.isc_info_blob_max_segment,
    FbIsc.isc_info_blob_num_segments,
    FbIsc.isc_info_blob_total_length
    ];

static immutable ubyte[] describeServerVersionInfoItems = [
    FbIsc.isc_info_firebird_version,
    FbIsc.isc_info_end
    ];

// Codes only support v13 and above
static if (fbDeferredProtocol)
{
    alias protocolMinType = FbIsc.ptype_lazy_send;
    alias protocolMaxType = FbIsc.ptype_lazy_send;
}
else
{
    alias protocolMinType = FbIsc.ptype_batch_send;
    alias protocolMaxType = FbIsc.ptype_batch_send;
}

static immutable FbProtocolInfo[] describeProtocolItems = [
    //FbProtocolInfo(FbIsc.protocol_version10, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, FbIsc.ptype_batch_send, 1),
    //FbProtocolInfo(FbIsc.protocol_version11, FbIsc.connect_generic_achitecture_client, protocolMinType, protocolMaxType, 2),
    //FbProtocolInfo(FbIsc.protocol_version12, FbIsc.connect_generic_achitecture_client, protocolMinType, protocolMaxType, 3),
    FbProtocolInfo(FbIsc.protocol_version13, FbIsc.connect_generic_achitecture_client, protocolMinType, protocolMaxType, 4),
    ];

static immutable ubyte[] describeStatementExplaindPlanInfoItems = [
    FbIsc.isc_info_sql_explain_plan
    ];

// SQL information
// If adding new block, update prepareCommandRead() with proper count
static immutable ubyte[] describeStatementInfoAndBindInfoItems = [
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
static immutable ubyte[] describeStatementPlanInfoItems = [
    FbIsc.isc_info_sql_get_plan
    ];

// SQL records affected
static immutable ubyte[] describeStatementRowsAffectedInfoItems = [
    FbIsc.isc_info_sql_records
    ];

// SQL type
static immutable ubyte[] describeStatementTypeInfoItems = [
    FbIsc.isc_info_sql_stmt_type
    ];


// Any below codes are private
private:
