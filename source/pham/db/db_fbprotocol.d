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

module pham.db.db_fbprotocol;

import std.algorithm.comparison : max, min;
import std.conv : to;
import std.range.primitives : isOutputRange, put;
import std.typecons : Flag, No, Yes;

debug(debug_pham_db_db_fbprotocol) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_array : Appender;
import pham.utl.utl_bit : bitLengthToElement, hostToNetworkOrder;
import pham.utl.utl_bit_array : BitArrayImpl;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_enum_set : toName;
import pham.utl.utl_object : InitializedValue, bytesFromHexs, bytesToHexs, functionName;
import pham.utl.utl_system : currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.db.db_buffer_filter;
import pham.db.db_buffer_filter_cipher;
import pham.db.db_buffer_filter_compressor;
import pham.db.db_convert;
import pham.db.db_database : DbNameColumn;
import pham.db.db_message;
import pham.db.db_object : DbDisposableObject;
import pham.db.db_type;
import pham.db.db_util;
import pham.db.db_value;
import pham.db.db_fbauth;
import pham.db.db_fbbuffer;
import pham.db.db_fbdatabase;
import pham.db.db_fbexception;
import pham.db.db_fbisc;
import pham.db.db_fbtype;

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
    debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");
    
    DbRecordsAffectedAggregate result;

    if (data.length <= 2)
        return result;

    size_t pos = 0;
    const endPos = data.length - 2;

    void parseRecordValues()
    {
		while (pos < endPos)
		{
            const typ = data[pos++];
            if (typ == FbIsc.isc_info_end)
                break;

			const len = parseInt32!true(data, pos, 2, typ);
            const count = parseInt32!true(data, pos, len, typ);
			switch (typ)
			{
				case FbIsc.isc_info_req_select_count:
                    debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "selectCount=", count);
					result.selectCount += count;
					break;

				case FbIsc.isc_info_req_insert_count:
                    debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "insertCount=", count);
					result.insertCount += count;
					break;

				case FbIsc.isc_info_req_update_count:
                    debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "updateCount=", count);
					result.updateCount += count;
					break;

				case FbIsc.isc_info_req_delete_count:
                    debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "deleteCount=", count);
					result.deleteCount += count;
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
    CipherBuffer!ubyte authData;
    const(char)[] authMethod;
    CipherBuffer!ubyte serverAuthData;
    CipherBuffer!ubyte serverAuthKey;
    const(char)[] serverAuthMethod;
    FbIscServerKey[] serverAuthKeys;
    int32 serverAcceptType;
    int32 serverArchitecture;
    int32 serverVersion;
    int nextAuthState;
    DbConnectionType connectionType;
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);
        return r.getIscObject();
    }

    final void allocateCommandWrite()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        allocateCommandWrite(writer);
        writer.flush();
    }

    final void allocateCommandWrite(ref FbXdrWriter writer) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		writer.writeOperation(FbIsc.op_allocate_statement);
		writer.writeHandle(connection.fbHandle);
    }

    final FbIscArrayGetResponse arrayGetRead(ref FbArray array)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_slice);
        return readArrayGetResponseImpl(reader, array.descriptor);
    }

    final void arrayGetWrite(ref FbArray array)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
        return r.getIscObject();
    }

    final void arrayPutWrite(ref FbArray array, uint32 elements, scope const(ubyte)[] encodedArrayValue)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
        return r.getIscObject();
    }

    final void blobBeginWrite(ref FbBlob blob, FbOperation createOrOpen)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(createOrOpen);
        writer.writeHandle(blob.fbTransaction.fbHandle);
        writer.writeId(blob.fbId);
        writer.flush();
    }

    final void blobEndRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void blobEndWrite(ref FbBlob blob, FbOperation closeOrCancelOp)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        blobEndWrite(writer, blob, closeOrCancelOp);
        writer.flush();
    }

    final void blobEndWrite(ref FbXdrWriter writer, ref FbBlob blob, FbOperation closeOrCancelOp) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

	    writer.writeOperation(closeOrCancelOp);
		writer.writeHandle(blob.fbHandle);
    }

    final FbIscGenericResponse blobGetSegmentsRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
        return r;
    }

    final void blobGetSegmentsWrite(ref FbBlob blob)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void blobPutSegmentsWrite(ref FbBlob blob, scope const(ubyte)[] segment)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_batch_segments);
		writer.writeHandle(blob.fbHandle);
        writer.writeBlob(segment);
        writer.flush();
    }

    final FbIscBlobSize blobSizeInfoRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
		if (r.data.length)
            return FbIscBlobSize(r.data);
        else
            return FbIscBlobSize.init;
    }

    final void blobSizeInfoWrite(ref FbBlob blob)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        cancelRequestWrite(handle, FbIsc.op_cancel_raise);
    }

    final void closeCursorCommandRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void closeCursorCommandWrite(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_free_statement);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(FbIsc.dsql_close);
        writer.flush();
    }

    final void commitRetainingTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void commitTransactionRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(connection.notificationMessages);
    }

    final void commitTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject connectAttachmentRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        r.statues.getWarn(connection.notificationMessages);
        return r.getIscObject();
    }

    final void connectAttachmentWrite(ref FbConnectingStateInfo stateInfo, FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        const isCreateOp = stateInfo.connectionType == DbConnectionType.create;
        auto useCSB = connection.fbConnectionStringBuilder;
        auto writerAI = FbConnectionWriter(connection, FbIsc.isc_dpb_version2); // Can be latest version depending on protocol version

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(isCreateOp ? FbIsc.op_create : FbIsc.op_attach);
		writer.writeHandle(0);
		writer.writeChars(isCreateOp ? createDatabaseInfo.fileName : useCSB.databaseName);
        writer.writeBytes(isCreateOp
            ? describeCreateInformation(writerAI, stateInfo, createDatabaseInfo)
            : describeAttachmentInformation(writerAI, stateInfo));
        writer.flush();
    }

    final void connectAuthenticationRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        FbOperation op = readOperation(reader, 0);

        size_t limitCounter = 20; // Avoid malicious response
        while (op == FbIsc.op_crypt_key_callback && limitCounter--)
        {
            auto rCryptKeyCallback = readCryptKeyCallbackResponseImpl(reader, FbIsc.protocol_version15);
            writeCryptKeyCallbackResponse(stateInfo, rCryptKeyCallback, FbIsc.protocol_version15);
            op = readOperation(reader, 0);
        }

        switch (op)
        {
            case FbIsc.op_accept:
                auto acceptResponse = readAcceptResponseImpl(reader);
                stateInfo.serverAcceptType = acceptResponse.acceptType;
                stateInfo.serverArchitecture = acceptResponse.architecture;
                stateInfo.serverVersion = acceptResponse.version_;
                this._serverVersion = stateInfo.serverVersion;
                connection.serverInfo[DbServerIdentifier.protocolAcceptType] = stateInfo.serverAcceptType.to!string();
                connection.serverInfo[DbServerIdentifier.protocolArchitect] = stateInfo.serverArchitecture.to!string();
                connection.serverInfo[DbServerIdentifier.protocolVersion] = stateInfo.serverVersion.to!string();
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
                stateInfo.serverAuthKeys = FbIscServerKey.parse(adResponse.authKey);
                this._serverVersion = stateInfo.serverVersion;
                connection.serverInfo[DbServerIdentifier.protocolAcceptType] = stateInfo.serverAcceptType.to!string();
                connection.serverInfo[DbServerIdentifier.protocolArchitect] = stateInfo.serverArchitecture.to!string();
                connection.serverInfo[DbServerIdentifier.protocolVersion] = stateInfo.serverVersion.to!string();

				if (!adResponse.isAuthenticated || op == FbIsc.op_cond_accept)
				{
					if (stateInfo.auth is null || stateInfo.serverAuthMethod != stateInfo.authMethod)
                    {
                        auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(stateInfo.serverAuthMethod);
                        throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_auth_data);
                    }

                    auto useCSB = connection.fbConnectionStringBuilder;
                    auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName,
                        useCSB.userPassword, stateInfo.serverAuthData[], stateInfo.authData);
                    if (status.isError)
                        throw new FbException(DbErrorCode.read, status.errorMessage, null, 0, FbIscResultCode.isc_auth_data);
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
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void connectAuthenticationWrite(ref FbConnectingStateInfo stateInfo, FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        clearServerInfo();

        const isCreateOp = stateInfo.connectionType == DbConnectionType.create;
        auto useCSB = connection.fbConnectionStringBuilder;
        const compressFlag = useCSB.compress ? FbIsc.ptype_compress_flag : 0;
        auto protoItems = describeProtocolItems;
        auto writerUI = FbConnectionWriter(connection, FbIsc.isc_dpb_version1); // Must be version1 at this point

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_connect);
		writer.writeOperation(isCreateOp ? FbIsc.op_create : FbIsc.op_attach);
		writer.writeInt32(FbIsc.connect_version);
        writer.writeInt32(FbIsc.connect_generic_achitecture_client);
        writer.writeChars(isCreateOp ? createDatabaseInfo.fileName : useCSB.databaseName);
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

    final void createCommandBatchRead(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        r.statues.getWarn(commandBatch.fbCommand.notificationMessages);
    }

    final void createCommandBatchWrite(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        createCommandBatchWrite(writer, commandBatch);
        writer.flush();
    }

    final void createCommandBatchWrite(ref FbXdrWriter writer, ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto inputParameters = commandBatch.fbCommand.fbInputParameters();
        auto pWriterBlr = FbBlrWriter(connection);
        auto pPrmBlr = describeBlrParameters(pWriterBlr, inputParameters);

        auto batchWriter = FbBatchWriter(connection, FbIscBatchType.version_);
        batchWriter.writeVersion();
		if (commandBatch.fbCommand.canReturnRecordsAffected())
			batchWriter.writeInt32(FbIscBatchType.tag_record_counts, 1);
		if (commandBatch.multiErrors)
			batchWriter.writeInt32(FbIscBatchType.tag_multierror, 1);
		batchWriter.writeInt32(FbIscBatchType.tag_buffer_bytes_size, commandBatch.maxBatchBufferLength);
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "maxBatchBufferLength=", commandBatch.maxBatchBufferLength, ", data=", batchWriter.peekBytes().dgToString());

		writer.writeOperation(FbIsc.op_batch_create);
        writer.writeHandle(commandBatch.fbCommand.fbHandle);
		writer.writeBytes(pPrmBlr.data);
		writer.writeInt32(pPrmBlr.size);
		writer.writeBytes(batchWriter.peekBytes());
    }

    final void createDatabaseRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
    }

    final void createDatabaseWrite(FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writerAI = FbConnectionWriter(connection, FbIsc.isc_dpb_version2); // Can be latest version depending on protocol version

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_create);
        writer.writeHandle(0);
		writer.writeChars(createDatabaseInfo.fileName);
        writer.writeBytes(describeCreateInformation(writerAI, createDatabaseInfo));
        writer.flush();
    }

    final void deallocateCommandRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void deallocateCommandWrite(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        deallocateCommandWrite(writer, command);
        writer.flush();
    }

    final void deallocateCommandWrite(ref FbXdrWriter writer, FbCommand command) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		writer.writeOperation(FbIsc.op_free_statement);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(FbIsc.dsql_drop);
    }

    final void disconnectWrite()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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

    final FbIscCommandBatchExecuteResponse executeCommandBatchRead(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_batch_cs);
        return readCommandBatchResponseImpl(reader);
    }

    final void executeCommandBatchWrite(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        executeCommandBatchWrite(writer, commandBatch);
        writer.flush();
    }

    final void executeCommandBatchWrite(ref FbXdrWriter writer, ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		writer.writeOperation(FbIsc.op_batch_exec);
		writer.writeHandle(commandBatch.fbCommand.fbHandle);
		writer.writeHandle(commandBatch.fbCommand.fbTransaction.fbHandle);
    }

    final void executeCommandRead(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        // Nothing to process - just need acknowledge
        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);
    }

    final void executeCommandWrite(FbCommand command, DbCommandExecuteType type)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(type=", type, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(command.isStoredProcedure ? FbIsc.op_execute2 : FbIsc.op_execute);
		writer.writeHandle(command.fbHandle);
		writer.writeHandle(command.fbTransaction.fbHandle);

        auto inputParameters = command.fbInputParameters();
		if (inputParameters.length)
		{
            auto pWriterBlr = FbBlrWriter(connection);
            auto pPrmBlr = describeBlrParameters(pWriterBlr, inputParameters);
            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "pPrmBlr=", pPrmBlr);

            auto pWriterVal = FbXdrWriter(connection);
            auto pPrmVal = describeParameters(pWriterVal, command, inputParameters).peekBytes();
            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "pPrmVal=", pPrmVal);

            writer.writeBytes(pPrmBlr.data);
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

		if (command.columnCount != 0 && command.isStoredProcedure)
		{
            auto pWriterBlr = FbBlrWriter(connection);
            auto pFldBlr = describeBlrColumns(pWriterBlr, cast(FbColumnList)command.columns);
            writer.writeBytes(pFldBlr.data);
			writer.writeInt32(0); // Output message number
		}

        if (_serverVersion >= FbIsc.protocol_version16)
        {
            const timeout = command.commandTimeout.limitRangeTimeoutAsMilliSecond();
            writer.writeInt32(timeout);
        }

        writer.flush();
    }

    final FbCommandPlanInfo.Kind executionPlanCommandInfoRead(FbCommand command, uint mode,
        out FbCommandPlanInfo info)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto describeItems = mode == 0
            ? describeStatementPlanInfoItems
            : describeStatementExplaindPlanInfoItems;
        commandInfoWrite(command, describeItems, bufferLength);
    }

    final FbIscFetchResponse fetchCommandRead(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_net_read_err);
        }
    }

    final void fetchCommandWrite(FbCommand command, const(bool) isScalar)
    in
    {
        assert(command.columnCount != 0);
    }
    do
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(fetchRecordCount=", command.fetchRecordCount, ")");

        auto writerBlr = FbBlrWriter(connection);
        auto pFldBlr = describeBlrColumns(writerBlr, cast(FbColumnList)command.columns);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_fetch);
		writer.writeHandle(command.fbHandle);
		writer.writeBytes(pFldBlr.data);
		writer.writeInt32(0); // p_sqldata_message_number
		writer.writeInt32(isScalar ? 1 : command.fetchRecordCount); // p_sqldata_messages
		writer.flush();
    }

    final void messageCommandBatchRead(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        // Nothing to process - just need acknowledge
        auto r = readGenericResponse();
        r.statues.getWarn(commandBatch.fbCommand.notificationMessages);
    }

    final void messageCommandBatchWrite(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        messageCommandBatchWrite(writer, commandBatch);
        writer.flush();
    }

    final void messageCommandBatchWrite(ref FbXdrWriter writer, ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto inputParameters = commandBatch.fbCommand.fbInputParameters();

		writer.writeOperation(FbIsc.op_batch_msg);
		writer.writeHandle(commandBatch.fbCommand.fbHandle);
        writer.writeInt32(commandBatch.parameters.length);
		foreach (i; 0..commandBatch.parameters.length)
		{
            auto pWriterVal = FbXdrWriter(connection);
            auto pPrmVal = describeParameters(pWriterVal, inputParameters, commandBatch, i).peekBytes();
            writer.writeOpaqueBytes(pPrmVal, pPrmVal.length);
		}
    }

    final FbIscBindInfo[] prepareCommandRead(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);

        FbIscBindInfo[] bindResults;
        ptrdiff_t previousBindIndex = -1; // Start with unknown value
        ptrdiff_t previousColumnIndex = 0;

        while (!FbIscBindInfo.parse(r.data, bindResults, previousBindIndex, previousColumnIndex))
        {
            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "previousBindIndex=", previousBindIndex, ", previousColumnIndex=", previousColumnIndex);

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

					auto processedColumnCount = truncateBindIndex <= previousBindIndex
                        ? bindResults[truncateBindIndex].length
                        : 0;
                    truncateBindItems[i++] = FbIsc.isc_info_sql_sqlda_start;
                    truncateBindItems[i++] = 2;
					truncateBindItems[i++] = cast(ubyte)((truncateBindIndex == previousBindIndex ? previousColumnIndex : processedColumnCount) & 255);
					truncateBindItems[i++] = cast(ubyte)((truncateBindIndex == previousBindIndex ? previousColumnIndex : processedColumnCount) >> 8);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        prepareCommandWrite(writer, command, sql);
        writer.flush();
    }

    final prepareCommandWrite(ref FbXdrWriter writer, FbCommand command, scope const(char)[] sql) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto bindItems = describeStatementInfoAndBindInfoItems;

		writer.writeOperation(FbIsc.op_prepare_statement);
		writer.writeHandle(command.fbTransaction.fbHandle);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(connection.dialect);
		writer.writeChars(sql);
		writer.writeBytes(bindItems);
		writer.writeInt32(FbIscSize.prepareInfoBufferLength);
    }

    final DbRecordsAffected recordsAffectedCommandRead(const(DbRecordsAffectedAggregateResult) kind)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
		if (r.data.length)
		{
            const counts = parseRecordsAffected(r.data);
            return counts.toCount(kind);
        }
        return DbRecordsAffected.init;
    }

    final void recordsAffectedCommandWrite(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        commandInfoWrite(command, describeStatementRowsAffectedInfoItems, FbIscSize.rowsEffectedBufferLength);
    }

    final void rollbackRetainingTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void rollbackTransactionRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(connection.notificationMessages);
    }

    final void rollbackTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject startTransactionRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(connection.notificationMessages);
        return r.getIscObject();
    }

    final void startTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        r.statues.getWarn(command.notificationMessages);
		if (r.data.length)
            return parseCommandType(r.data);
        else
            return FbIscCommandType.none;
    }

    final void typeCommandWrite(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        commandInfoWrite(command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength);
    }

    final void typeCommandWrite(ref FbXdrWriter writer, FbCommand command) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        commandInfoWrite(writer, command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength);
    }

    final FbIscGenericResponse readGenericResponse()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_response);
        return readGenericResponseImpl(reader);
    }

    final FbIscSqlResponse readSqlResponse()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_sql_response);
        return readSqlResponseImpl(reader);
    }

    final DbValue readValue(ref FbXdrReader reader, FbCommand command, DbNameColumn column)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(column=", column.traceString(), ")");
        version(profile) debug auto p = PerfFunction.create();

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
            case DbType.stringFixed:
                return DbValue(reader.readFixedString(column.baseType), dbType);
            case DbType.stringVary:
                return DbValue(reader.readString(), dbType);
            case DbType.json:
            case DbType.xml:
            case DbType.text:
            case DbType.binaryFixed:
            case DbType.binaryVary:
                return DbValue.entity(reader.readId(), dbType);

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(functionName(), toName!DbType(dbType));
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_net_read_err);
        }

        version(fbProtocolPrev13)
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

    final DbRowValue readValues(FbCommand command, FbColumnList columns)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");
        version(profile) debug auto p = PerfFunction.create();

        auto reader = FbXdrReader(connection);

        const nullBitmapBytes = bitLengthToElement!ubyte(columns.length);
		const nullBitmap = BitArrayImpl!ubyte(reader.readOpaqueBytes(nullBitmapBytes));

        auto result = DbRowValue(columns.length);
        foreach (i, column; columns)
        {
            if (nullBitmap[i])
                result[i].nullify();
            else
                result[i] = readValue(reader, command, column);
        }
        return result;
    }

    final void releaseCommandBatchRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse();
        //r.statues.getWarn(command.notificationMessages);
    }

    final void releaseCommandBatchWrite(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        releaseCommandBatchWrite(writer, command);
        writer.flush();
    }

    final void releaseCommandBatchWrite(ref FbXdrWriter writer, FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		writer.writeOperation(FbIsc.op_batch_rls);
		writer.writeHandle(command.fbHandle);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(cancelKind=", cancelKind, ")");

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
                && getCryptedConnectionCode() != FbIsc.cnct_client_crypt_disabled
            ? DbEncryptedConnection.enabled
            : DbEncryptedConnection.disabled;
    }

    final void clearServerInfo()
    {
        _serverVersion = 0;
    }

    final void commandInfoWrite(FbCommand command, scope const(ubyte)[] items, uint32 resultBufferLength)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        commandInfoWrite(writer, command, items, resultBufferLength);
        writer.flush();
    }

    final void commandInfoWrite(ref FbXdrWriter writer, FbCommand command, scope const(ubyte)[] items,
        uint32 resultBufferLength) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		writer.writeOperation(FbIsc.op_info_sql);
        writer.writeHandle(command.fbHandle);
		writer.writeInt32(0);
		writer.writeBytes(items);
		writer.writeInt32(resultBufferLength);
    }

    final void compressSetupBufferFilter()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		auto compressor = new DbBufferFilterCompressorZip!(DbBufferFilterKind.write)();
		auto decompressor = new DbBufferFilterCompressorZip!(DbBufferFilterKind.read)();
		connection.chainBufferFilters(decompressor, compressor);
    }

    final void connectAuthenticationAcceptRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, 0);
        switch (op)
        {
            case FbIsc.op_response:
                auto r = readGenericResponseImpl(reader);
                r.statues.getWarn(connection.notificationMessages);
                stateInfo.serverAuthKey = r.data;
                stateInfo.serverAuthKeys = FbIscServerKey.parse(r.data);
                break;

            case FbIsc.op_trusted_auth:
                auto tResponse = readTrustedAuthResponseImpl(reader);
                if (tResponse.data.length)
                {
                    stateInfo.serverAuthKey = tResponse.data;
                    stateInfo.serverAuthKeys = FbIscServerKey.parse(tResponse.data);
                }
                break;

            case FbIsc.op_cont_auth:
                auto cResponse = readCondAuthResponseImpl(reader);
                stateInfo.serverAuthMethod = cResponse.name;
                stateInfo.serverAuthKey = cResponse.key;
                stateInfo.serverAuthKeys = FbIscServerKey.parse(cResponse.key);
                if (stateInfo.serverAuthMethod.length != 0)
                {
                    if (stateInfo.serverAuthMethod != stateInfo.authMethod)
                    {
                        stateInfo.nextAuthState = 0;
                        stateInfo.authMethod = stateInfo.serverAuthMethod;
                        stateInfo.auth = createAuth(stateInfo.authMethod);
                    }
                    auto useCSB = connection.fbConnectionStringBuilder;
                    auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName,
                        useCSB.userPassword, cResponse.data, stateInfo.authData);
                    if (status.isError)
                        throw new FbException(DbErrorCode.read, status.errorMessage, null, 0, FbIscResultCode.isc_auth_data);
                }
                break;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, "authentication");
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void connectAuthenticationAcceptWrite(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_cont_auth);
		writer.writeBytes(stateInfo.authData[]);
		writer.writeChars(stateInfo.auth.name); // like CNCT_plugin_name
		writer.writeChars(stateInfo.auth.name); // like CNCT_plugin_list
		writer.writeBytes(stateInfo.serverAuthKey[]);
		writer.flush();
        stateInfo.nextAuthState++;
    }

    final FbAuth createAuth(const(char)[] authMethod)
    {
        auto authMap = FbAuth.findAuthMap(authMethod);
        if (!authMap.isValid())
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(authMethod);
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_auth_data);
        }

        return cast(FbAuth)authMap.createAuth();
    }

    final void cryptRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, 0);
        switch (op)
        {
            case FbIsc.op_crypt_key_callback:
                auto rCryptKeyCallback = readCryptKeyCallbackResponseImpl(reader, stateInfo.serverVersion);
                writeCryptKeyCallbackResponse(stateInfo, rCryptKeyCallback, stateInfo.serverVersion);
                break;

            case FbIsc.op_response:
                auto r = readGenericResponseImpl(reader);
                r.statues.getWarn(connection.notificationMessages);
                break;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, "encryption");
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_auth_data);
        }
    }

    final void cryptSetupBufferFilter(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto useCSB = connection.fbConnectionStringBuilder;
        auto cryptAlgorithm = useCSB.cryptAlgorithm;
        auto key = createCryptKey(cryptAlgorithm, stateInfo.auth.sessionKey(), stateInfo.serverAuthKeys);

        switch (cryptAlgorithm)
        {
            case FbIscText.filterCryptChachaName:
                auto encryptor = new DbBufferFilterCipherChaCha!(DbBufferFilterKind.write)(key);
                auto decryptor = new DbBufferFilterCipherChaCha!(DbBufferFilterKind.read)(key);
                connection.chainBufferFilters(decryptor, encryptor);
                break;

            case FbIscText.filterCryptChacha64Name:
                auto encryptor = new DbBufferFilterCipherChaCha!(DbBufferFilterKind.write)(key);
                auto decryptor = new DbBufferFilterCipherChaCha!(DbBufferFilterKind.read)(key);
                connection.chainBufferFilters(decryptor, encryptor);
                break;

            //case FbIscText.filterCryptArc4Name:
            default:
                auto encryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.write)(key);
                auto decryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.read)(key);
                connection.chainBufferFilters(decryptor, encryptor);
                break;
        }
    }

    final void cryptWrite(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto useCSB = connection.fbConnectionStringBuilder;
        auto cryptAlgorithm = useCSB.cryptAlgorithm;

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_crypt);
		writer.writeChars(cryptAlgorithm);
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

        { // Type
            auto typeWriter = FbBlrWriter(writer.buffer);
            FbIscBlrDescriptor descriptor;
            typeWriter.writeType(cast(FbBlrType)array.descriptor.blrType, array.descriptor.columnInfo.baseType(), FbBlrWriteType.base, descriptor);
        }

        writer.writeName(FbIsc.isc_sdl_relation, array.descriptor.columnInfo.tableName);
        writer.writeName(FbIsc.isc_sdl_field, array.descriptor.columnInfo.name);

        version(fbMultiDimensions)
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(stateInfo.authData=", stateInfo.authData.toString(), ")");

        auto useCSB = connection.fbConnectionStringBuilder;

		writer.writeVersion();
		writer.writeInt32(FbIsc.isc_dpb_dummy_packet_interval, useCSB.dummyPackageInterval.limitRangeTimeoutAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_sql_dialect, useCSB.dialect);
		writer.writeChars(FbIsc.isc_dpb_lc_ctype, useCSB.charset);
        writer.writeCharsIf(FbIsc.isc_dpb_user_name, useCSB.userName);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, useCSB.roleName);
		writer.writeInt32(FbIsc.isc_dpb_connect_timeout, useCSB.connectionTimeout.limitRangeTimeoutAsSecond());
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
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "dpbValue.length=", result.length, ", dpbValue=", result.dgToString());
        return result;
    }

    final ubyte[] describeCreateInformation(return ref FbConnectionWriter writer, ref FbConnectingStateInfo stateInfo,
        FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(stateInfo.authData=", stateInfo.authData.toString(), ")");

        auto useCSB = connection.fbConnectionStringBuilder;
        auto useRoleName = createDatabaseInfo.roleName.length
            ? createDatabaseInfo.roleName
            : useCSB.roleName;
        auto useUserName = createDatabaseInfo.ownerName.length
            ? createDatabaseInfo.ownerName
            : useCSB.userName;

		writer.writeVersion();
		writer.writeInt32(FbIsc.isc_dpb_dummy_packet_interval, useCSB.dummyPackageInterval.limitRangeTimeoutAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_sql_dialect, useCSB.dialect);
		writer.writeChars(FbIsc.isc_dpb_lc_ctype, useCSB.charset);
        if (writer.writeCharsIf(FbIsc.isc_dpb_user_name, useUserName))
            writer.writeCharsIf(FbIsc.isc_dpb_password, createDatabaseInfo.ownerPassword);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, useRoleName);
		writer.writeInt32(FbIsc.isc_dpb_connect_timeout, useCSB.connectionTimeout.limitRangeTimeoutAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_process_id, currentProcessId());
		writer.writeChars(FbIsc.isc_dpb_process_name, currentProcessName());
		writer.writeCharsIf(FbIsc.isc_dpb_client_version, useCSB.applicationVersion);
		if (stateInfo.authData.length)
		    writer.writeBytes(FbIsc.isc_dpb_specific_auth_data, stateInfo.authData[]);
        writer.writeCharsIf(FbIsc.isc_dpb_set_db_charset, createDatabaseInfo.defaultCharacterSet);
		writer.writeInt32(FbIsc.isc_dpb_force_write, createDatabaseInfo.forcedWrite ? 1 : 0);
		writer.writeInt32(FbIsc.isc_dpb_overwrite, createDatabaseInfo.overwrite ? 1 : 0);
		if (createDatabaseInfo.pageSize > 0)
			writer.writeInt32(FbIsc.isc_dpb_page_size, createDatabaseInfo.toKnownPageSize(createDatabaseInfo.pageSize));
		writer.writeInt32(FbIsc.isc_dpb_utf8_filename, 1); // This is weirdess - must be last or fail to authenticate

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "dpbValue.length=", result.length, ", dpbValue=", result.dgToString());
        return result;
    }

    final ubyte[] describeCreateInformation(return ref FbConnectionWriter writer,
        FbCreateDatabaseInfo createDatabaseInfo) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

		writer.writeVersion();
        if (writer.writeCharsIf(FbIsc.isc_dpb_user_name, createDatabaseInfo.ownerName))
            writer.writeCharsIf(FbIsc.isc_dpb_password, createDatabaseInfo.ownerPassword);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, createDatabaseInfo.roleName);
        writer.writeCharsIf(FbIsc.isc_dpb_set_db_charset, createDatabaseInfo.defaultCharacterSet);
		writer.writeInt32(FbIsc.isc_dpb_force_write, createDatabaseInfo.forcedWrite ? 1 : 0);
		writer.writeInt32(FbIsc.isc_dpb_overwrite, createDatabaseInfo.overwrite ? 1 : 0);
		if (createDatabaseInfo.pageSize > 0)
			writer.writeInt32(FbIsc.isc_dpb_page_size, createDatabaseInfo.pageSize);
		writer.writeInt32(FbIsc.isc_dpb_utf8_filename, 1); // This is weirdess - must be last or fail to authenticate

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "dpbValue.length=", result.length, ", dpbValue=", result.dgToString());
        return result;
    }

    final FbIscBlrDescriptor describeBlrColumns(return ref FbBlrWriter writer, FbColumnList columns) nothrow
    in
    {
        assert(columns !is null);
        assert(columns.length != 0 && columns.length <= ushort.max / 2);
    }
    do
    {
        FbIscBlrDescriptor result;

        writer.writeBegin(columns.length);
        foreach (column; columns)
        {
            writer.writeColumn(column.baseType, result);
        }
        writer.writeEnd(columns.length);

        result.data = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(size=", result.size, ", data=", result.data.dgToString(), ")");
        return result;
    }

    final FbIscBlrDescriptor describeBlrParameters(return ref FbBlrWriter writer, scope FbParameter[] parameters) nothrow
    in
    {
        assert(parameters !is null);
        assert(parameters.length != 0 && parameters.length <= ushort.max / 2);
    }
    do
    {
        FbIscBlrDescriptor result;

        writer.writeBegin(parameters.length);
        foreach (parameter; parameters)
        {
            writer.writeColumn(parameter.baseType, result);
        }
        writer.writeEnd(parameters.length);

        result.data = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(size=", result.size, ", data=", result.data.dgToString(), ")");
        return result;
    }

    final ref FbXdrWriter describeParameters(return ref FbXdrWriter writer, FbCommand command, scope FbParameter[] parameters)
    in
    {
        assert(parameters.length != 0 && parameters.length <= ushort.max / 2);
    }
    do
    {
        // Null indicators
        auto nullBitmap = BitArrayImpl!ubyte(parameters.length);
        foreach (i, parameter; parameters)
        {
            if (parameter.isNull)
                nullBitmap[i] = true;
        }
        writer.writeOpaqueBytes(nullBitmap[], nullBitmap[].length);

        // Values
        foreach (parameter; parameters)
        {
            if (!parameter.isNull)
            {
                (cast(FbParameter)parameter).prepareParameter(command);
                describeValue(writer, parameter, parameter.value);
            }
        }

        return writer;
    }

    final ref FbXdrWriter describeParameters(return ref FbXdrWriter writer, scope FbParameter[] parameterMetas,
        ref FbCommandBatch commandBatch, const(size_t) parameterIndex)
    in
    {
        assert(parameterMetas.length != 0 && parameterMetas.length <= ushort.max / 2);
    }
    do
    {
        auto parameterValues = commandBatch.parameters[parameterIndex];

        // Null indicators
        auto nullBitmap = BitArrayImpl!ubyte(parameterMetas.length);
        foreach (i, parameterMeta; parameterMetas)
        {
            auto parameterValue = i < parameterValues.length ? parameterValues[i] : null;

            // Must set the meta info which affect null checking
            if (parameterValue !is null)
                parameterValue.cloneMetaInfo(parameterMeta);

            if (parameterValue is null || parameterValue.isNull)
                nullBitmap[i] = true;
        }
        writer.writeOpaqueBytes(nullBitmap[], nullBitmap[].length);

        // Values
        foreach (i, parameterMeta; parameterMetas)
        {
            if (i >= parameterValues.length)
                break;

            auto parameterValue = parameterValues[i];
            if (!parameterValue.isNull)
            {
                (cast(FbParameter)parameterValue).prepareParameter(commandBatch.fbCommand);
                describeValue(writer, parameterValue, parameterValue.value);
            }
        }

        return writer;
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

        if (transaction.transactionItems.length == 0)
            describeTransactionItems(writer, transaction);
        else
            writer.writeOpaqueBytes(transaction.transactionItems);

        if (transaction.lockedTables.length)
        {
            foreach (ref lockedTable; transaction.lockedTables)
            {
                writer.writeChars(lockTableReadOrWrite(lockedTable), lockedTable.tableName);
                writer.writeOpaqueUInt8(lockTableBehavior(lockedTable));
            }
        }

        return writer.peekBytes();
    }

    public static void describeTransactionItems(ref FbTransactionWriter writer, FbTransaction transaction) nothrow
    {
        void isolationLevel(out ubyte isolationMode, out ubyte versionMode, out ubyte waitMode) nothrow @safe
        {
            // isc_tpb_rec_version or isc_tpb_no_rec_version = Only for isc_tpb_read_committed
            final switch (transaction.isolationLevel)
            {
                case DbIsolationLevel.readUncommitted:
                    isolationMode = FbIsc.isc_tpb_concurrency;
                    versionMode = 0;
                    waitMode = FbIsc.isc_tpb_nowait;
                    break;

                case DbIsolationLevel.readCommitted:
                    isolationMode = FbIsc.isc_tpb_read_committed;
                    versionMode = FbIsc.isc_tpb_rec_version;
                    waitMode = FbIsc.isc_tpb_wait;
                    break;

                case DbIsolationLevel.repeatableRead:
                    isolationMode = FbIsc.isc_tpb_concurrency;
                    versionMode = 0;
                    waitMode = FbIsc.isc_tpb_nowait;
                    break;

                case DbIsolationLevel.serializable:
                    isolationMode = FbIsc.isc_tpb_consistency;
                    versionMode = 0;
                    waitMode = FbIsc.isc_tpb_wait;
                    break;

                case DbIsolationLevel.snapshot:
                    isolationMode = FbIsc.isc_tpb_consistency;
                    versionMode = 0;
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

        writer.writeOpaqueUInt8(FbIsc.isc_tpb_version);
        writer.writeOpaqueUInt8(isolationMode);
        if (isolationMode == FbIsc.isc_tpb_read_committed && versionMode)
            writer.writeOpaqueUInt8(versionMode);
        writer.writeOpaqueUInt8(readOrWriteMode());
        writer.writeOpaqueUInt8(waitMode);
        if (waitMode == FbIsc.isc_tpb_wait && transaction.lockTimeout)
            writer.writeInt32(FbIsc.isc_tpb_lock_timeout, transaction.lockTimeout.limitRangeTimeoutAsSecond);
        if (transaction.autoCommit)
            writer.writeOpaqueUInt8(FbIsc.isc_tpb_autocommit);
    }

    final ubyte[] describeUserIdentification(return ref FbConnectionWriter writer, ref FbConnectingStateInfo stateInfo)
    {
        auto useCSB = connection.fbConnectionStringBuilder;

        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(userName=", useCSB.userName, ")");

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
                throw new FbException(DbErrorCode.write, status.errorMessage, null, 0, FbIscResultCode.isc_auth_data);

            writer.writeMultiParts(FbIsc.cnct_specific_data, stateInfo.authData[]);
            writer.writeInt32(FbIsc.cnct_client_crypt, hostToNetworkOrder!int32(getCryptedConnectionCode()));
            stateInfo.nextAuthState++;

            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "specificData=", stateInfo.authData.toString());
        }

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "result=", result.dgToString());
        return result;
    }

    final void describeValue(ref FbXdrWriter writer, DbNameColumn column, ref DbValue value)
    in
    {
        assert(!value.isNull);
    }
    do
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(column=", column.name, ", type=", column.type, ")");

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
            case DbType.stringFixed:
                return writer.writeFixedChars(value.coerce!(const(char)[])(), column.baseType);
            case DbType.stringVary:
                return writer.writeChars(value.coerce!(const(char)[])());
            case DbType.text:
            case DbType.json:
            case DbType.xml:
            case DbType.binaryFixed:
            case DbType.binaryVary:
                return writer.writeId(value.get!FbId());

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(functionName(), toName!DbType(column.type));
                throw new FbException(DbErrorCode.write, msg, null, 0, FbIscResultCode.isc_net_write_err);
        }
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        _serverVersion = 0;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    final int32 getCryptedConnectionCode() nothrow
    {
        auto useCSB = connection.fbConnectionStringBuilder;

        // Check security settting that supports encryption regardless of encrypt setting
        final switch (useCSB.integratedSecurity) with (DbIntegratedSecurityConnection)
        {
            case srp1:
            case srp256:
                break;
            case legacy:
            case sspi:
                return FbIsc.cnct_client_crypt_disabled;
        }

        final switch (useCSB.encrypt) with (DbEncryptedConnection)
        {
            case disabled:
                return FbIsc.cnct_client_crypt_disabled;
            case enabled:
                return FbIsc.cnct_client_crypt_enabled;
            case required:
                return FbIsc.cnct_client_crypt_required;
        }
    }

    final FbIscAcceptResponse readAcceptResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto version_ = FbIscAcceptResponse.normalizeVersion(reader.readInt32());
        auto architecture = reader.readInt32();
        auto acceptType = reader.readInt32();

        return FbIscAcceptResponse(version_, architecture, acceptType);
    }

    final FbIscAcceptDataResponse readAcceptDataResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto version_ = FbIscAcceptResponse.normalizeVersion(reader.readInt32());
        auto architecture = reader.readInt32();
        auto acceptType = reader.readInt32();
        auto authData = reader.readBytes();
        auto authName = reader.readString();
        auto authenticated = reader.readInt32();
        auto authKey = reader.readBytes();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "authenticated=", authenticated, ", authData=", authData.dgToString(),
            ", authKey=", authKey.dgToString(), ", authName=", authName);

        return FbIscAcceptDataResponse(version_, architecture, acceptType, authData, authName, authenticated, authKey);
    }

    final FbIscArrayGetResponse readArrayGetResponseImpl(ref FbXdrReader reader, scope const(FbIscArrayDescriptor) descriptor)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbIscArrayGetResponse result;
        result.sliceLength = reader.readInt32(); // Weird?
        result.sliceLength = reader.readInt32();
		switch (descriptor.blrType)
		{
			case FbBlrType.blr_short:
				result.sliceLength = result.sliceLength * descriptor.columnInfo.size;
				break;
			case FbBlrType.blr_text:
			case FbBlrType.blr_text2:
			case FbBlrType.blr_cstring:
			case FbBlrType.blr_cstring2:
				result.elements = result.sliceLength / descriptor.columnInfo.size;
				result.sliceLength += result.elements * ((4 - descriptor.columnInfo.size) & 3);
				break;
			case FbBlrType.blr_varying:
			case FbBlrType.blr_varying2:
				result.elements = result.sliceLength / descriptor.columnInfo.size;
				break;
            default:
                break;
		}

        if (descriptor.blrType == FbBlrType.blr_varying || descriptor.blrType == FbBlrType.blr_varying2)
        {
            auto tempResult = Appender!(ubyte[])(result.sliceLength);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rData = reader.readBytes();
        auto rName = reader.readString();
        auto rList = reader.readBytes();
        auto rKey = reader.readBytes();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rName=", rName, ", rData=", rData.dgToString(),
            ", rKey=", rKey.dgToString(), ", rList=", rList.dgToString());

        return FbIscCondAuthResponse(rData, rName, rList, rKey);
    }

    final FbIscCommandBatchExecuteResponse readCommandBatchResponseImpl(ref FbXdrReader reader)
    {
        FbIscCommandBatchExecuteResponse result;

        result.statementHandle = reader.readHandle();
        result.recCount = reader.readInt32();
        result.recordsAffectedCount = reader.readInt32();
        result.errorStatuesCount = reader.readInt32();
        result.errorIndexesCount = reader.readInt32();

        if (result.recordsAffectedCount > 0)
        {
            result.recordsAffectedData = new int32[](result.recordsAffectedCount);
            foreach (i; 0..result.recordsAffectedCount)
                result.recordsAffectedData[i] = reader.readInt32();
        }

        if (result.errorStatuesCount > 0)
        {
            result.errorStatuesData = new FbIscCommandBatchStatus[](result.errorStatuesCount);
            foreach (i; 0..result.errorStatuesCount)
            {
                result.errorStatuesData[i].recIndex = reader.readInt32();
                result.errorStatuesData[i].statues = reader.readStatuses();
            }
        }

        if (result.errorIndexesCount > 0)
        {
            result.errorIndexesData = new int32[](result.errorIndexesCount);
            foreach (i; 0..result.errorIndexesCount)
                result.errorIndexesData[i] = reader.readInt32();
        }

        return result;
    }

    final FbIscCryptKeyCallbackResponse readCryptKeyCallbackResponseImpl(ref FbXdrReader reader, const(int32) serverVersion)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rData = reader.readBytes();
        auto rSize = serverVersion > FbIsc.protocol_version13 ? reader.readInt32() : int32.min; // Use min to indicate not used - zero may be false positive

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rSize=", rSize, ", rData=", rData.dgToString());

        return FbIscCryptKeyCallbackResponse(rData, rSize);
    }

    final void writeCryptKeyCallbackResponse(ref FbConnectingStateInfo stateInfo,
        ref FbIscCryptKeyCallbackResponse cryptKeyCallbackResponse, const(int32) serverVersion)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto useCSB = connection.fbConnectionStringBuilder;
        auto cryptKey = useCSB.cryptKey;
        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_crypt_key_callback);
        writer.writeBytes(cryptKey);
        if (serverVersion > FbIsc.protocol_version13)
            writer.writeInt32(cryptKeyCallbackResponse.size);
        writer.flush();
    }

    final FbIscFetchResponse readFetchResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rStatus = reader.readInt32();
        auto rCount = reader.readInt32();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rStatus=", rStatus, ", rCount=", rCount);
        return FbIscFetchResponse(rStatus, rCount);
    }

    final FbIscGenericResponse readGenericResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rHandle = reader.readHandle();
        auto rId = reader.readId();
        auto rData = reader.readBytes();
        auto rStatues = reader.readStatuses();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rHandle=", rHandle, ", rId=", rId, ", rData=", rData.dgToString());

        if (rStatues.isError)
        {
            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "errorCode=", rStatues.errorCode());

            throw new FbException(rStatues);
        }

        return FbIscGenericResponse(rHandle, rId, rData, rStatues);
    }

    final FbOperation readOperation(out FbXdrReader reader, const(FbOperation) expectedOperation) @trusted
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(deferredResponses.length=", deferredResponses.length, ")");

        if (deferredResponses.length != 0)
        {
            auto responses = deferredResponses;
            deferredResponses = [];
            foreach (response; responses)
                response();
        }

        scope (failure)
            connection.fatalError();

        reader = FbXdrReader(connection);
        auto result = reader.readOperation();
        if (expectedOperation != 0 && expectedOperation != result)
        {
            auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(result, expectedOperation);
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_net_read_err);
        }
        return result;
    }

    final FbIscSqlResponse readSqlResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rCount = reader.readInt32();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rCount=", rCount);
        return FbIscSqlResponse(rCount);
    }

    final FbIscTrustedAuthResponse readTrustedAuthResponseImpl(ref FbXdrReader reader)
    {
        auto rData = reader.readBytes().dup;

        return FbIscTrustedAuthResponse(rData);
    }

    final void validateRequiredEncryption(bool wasEncryptedSetup)
    {
		if (!wasEncryptedSetup && getCryptedConnectionCode() == FbIsc.cnct_client_crypt_required)
        {
            auto msg = DbMessage.eInvalidConnectionRequiredEncryption.fmtMessage(connection.connectionStringBuilder.forErrorInfo);
            throw new FbException(DbErrorCode.connect, msg, null, 0, FbIscResultCode.isc_wirecrypt_incompatible);
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
    FbIsc.isc_info_blob_total_length,
    ];

static immutable ubyte[] describeServerVersionInfoItems = [
    FbIsc.isc_info_firebird_version,
    FbIsc.isc_info_end,
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
    FbProtocolInfo(FbIsc.protocol_version15, FbIsc.connect_generic_achitecture_client, protocolMinType, protocolMaxType, 5),
    FbProtocolInfo(FbIsc.protocol_version16, FbIsc.connect_generic_achitecture_client, protocolMinType, protocolMaxType, 6),
    ];

static immutable ubyte[] describeStatementExplaindPlanInfoItems = [
    FbIsc.isc_info_sql_explain_plan,
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
    FbIsc.isc_info_sql_describe_end,
    ];

// SQL plan	information
static immutable ubyte[] describeStatementPlanInfoItems = [
    FbIsc.isc_info_sql_get_plan,
    ];

// SQL records affected
static immutable ubyte[] describeStatementRowsAffectedInfoItems = [
    FbIsc.isc_info_sql_records,
    ];

// SQL type
static immutable ubyte[] describeStatementTypeInfoItems = [
    FbIsc.isc_info_sql_stmt_type,
    ];
