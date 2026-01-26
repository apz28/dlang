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
import std.typecons : Flag, No, Yes;

debug(debug_pham_db_db_fbprotocol) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_bit : bitLengthToElement, hostToNetworkOrder;
import pham.utl.utl_bit_array : BitArrayImpl;
import pham.utl.utl_convert : bytesFromHexs, bytesToHexs;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.utl.utl_enum_set : EnumSet, toName;
import pham.utl.utl_object : InitializedValue;
import pham.utl.utl_result : ResultCode;
import pham.utl.utl_system : currentComputerName, currentProcessId, currentProcessName, currentUserName;
import pham.db.db_buffer_filter;
import pham.db.db_buffer_filter_cipher;
import pham.db.db_buffer_filter_compressor;
import pham.db.db_convert;
import pham.db.db_database : DbNamedColumn;
import pham.db.db_message;
import pham.db.db_object : DbDisposableObject, DbLocalReferenceList;
import pham.db.db_type;
import pham.db.db_util;
import pham.db.db_value;
import pham.db.db_fbauth;
import pham.db.db_fbbuffer;
import pham.db.db_fbdatabase;
import pham.db.db_fbexception;
import pham.db.db_fbisc;
import pham.db.db_fbtype;

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

protected:
    string forOP;
    int forOPCode;
    ushort callLimitCounter;
}

enum FbDeferredFlag : ubyte
{
    deferred,
    scopedData,
}

struct FbDeferredInfo
{
nothrow @safe:

    this(EnumSet!FbDeferredFlag flags)
    {
        this.flags = flags;
        this.errorStatues = null;
    }

    this(Flags...)(scope Flags flags)
    {
        this(EnumSet!FbDeferredFlag(flags));
    }

    void restoreScopedData(bool scopedData)
    {
        flags.scopedData = scopedData;
    }

    bool setScopedData()
    {
        const result = flags.scopedData;
        flags.scopedData = true;
        return result;
    }

    FbException toException()
    in
    {
        assert(hasError());
    }
    do
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(errorStatues.length=", errorStatues.length, ")");

        FbException result;
        auto i = errorStatues.length;
        while (i)
        {
            result = new FbException(errorStatues[i - 1], result);
            i--;
        }
        return result;
    }

    pragma(inline, true)
	@property bool hasError() const @nogc
	{
        return errorStatues.length != 0;
	}

    FbIscStatues[] errorStatues;
    EnumSet!FbDeferredFlag flags;
}

struct FbDeferredResponse
{
    alias DeferredDelegate = void delegate(ref FbDeferredInfo deferredInfo) @safe;

    string name;
    DeferredDelegate caller;
}

class FbProtocol : DbDisposableObject
{
@safe:

public:
    this(FbConnection connection) nothrow pure
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln("**********");

        this._connection = connection;
    }

    final FbIscObject allocateCommandRead(FbCommand command, ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse(deferredInfo, command);
        return r.getIscObject();
    }

    final void allocateCommandWrite()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.handle=", connection.fbHandle, ")");

        auto writer = FbXdrWriter(connection);
        allocateCommandWrite(writer);
        writer.flush();
    }

    final void allocateCommandWrite(ref FbXdrWriter writer) nothrow
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.handle=", connection.fbHandle, ")");

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", array.fbTransaction.fbHandle, ", array.fbId=", array.fbId, ")");

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

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
        return r.getIscObject();
    }

    final void arrayPutWrite(ref FbArray array, uint32 elements, scope const(ubyte)[] encodedArrayValue)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", array.fbTransaction.fbHandle, ", array.fbId=", array.fbId, ")");

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

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
        return r.getIscObject();
    }

    final void blobBeginWrite(ref FbBlob blob, FbOperation createOrOpen)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", blob.fbTransaction.fbHandle, ", blob.fbId=", blob.fbId, ")");

        auto writer = FbXdrWriter(connection);
	    writer.writeOperation(createOrOpen);
        writer.writeHandle(blob.fbTransaction.fbHandle);
        writer.writeId(blob.fbId);
        writer.flush();
    }

    final void blobEndRead(ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse(deferredInfo, null);
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

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.scopedData);
        auto r = readGenericResponse(deferredInfo, null);
        return r;
    }

    final void blobGetSegmentsWrite(ref FbBlob blob)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_get_segment);
		writer.writeHandle(blob.fbHandle);
        writer.writeInt32(FbIscSize.maxBlobSegmentLength);
        writer.writeInt32(0);
        writer.flush();
    }

    final void blobPutSegmentsRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
    }

    final void blobPutSegmentsWrite(ref FbBlob blob, scope const(ubyte)[] segment)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_put_segment);
		writer.writeHandle(blob.fbHandle);
        writer.writeBlob(segment);
        writer.flush();
    }

    final FbIscBlobSize blobSizeInfoRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.scopedData);
        auto r = readGenericResponse(deferredInfo, null);
        auto result = r.data.length ? FbIscBlobSize.parse(r.data) : FbIscBlobSize.init;
        return result;
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

    final void closeCursorCommandRead(ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse(deferredInfo, null);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", transaction.fbHandle, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void commitTransactionRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
    }

    final void commitTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", transaction.fbHandle, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_commit);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject connectAttachmentRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.connectionType=", connection.connectionType, ")");

        stateInfo.callLimitCounter = 50;
        stateInfo.forOP = "connectAttachment";
        stateInfo.forOPCode = FbIscResultCode.isc_auth_data;
        FbIscOPResponse opResponse;
        scope (exit)
            opResponse.reset();
        auto reader = FbXdrReader(connection);
        const op = readOperationImpl(reader, stateInfo, opResponse);

        if (op != FbIsc.op_response)
        {
            auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(op, stateInfo.forOP);
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_net_read_err);
        }

        auto result = opResponse.generic.getIscObject();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "connection.handle=", result.handle);
        return result;
    }

    final void connectAttachmentWrite(ref FbConnectingStateInfo stateInfo, FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.connectionType=", connection.connectionType, ")");

        auto useCSB = connection.fbConnectionStringBuilder;
        const forOperation = connection.connectionType == DbConnectionType.create ? FbIsc.op_create : FbIsc.op_attach;
        const forName = connection.connectionType == DbConnectionType.create ? createDatabaseInfo.fileName : useCSB.databaseName;
        auto connectionParamWriter = FbConnectionWriter(connection, FbIsc.isc_dpb_version); // Can be latest version depending on protocol version
        const paramBytes = connection.connectionType == DbConnectionType.create
            ? describeCreationInformation(connectionParamWriter, stateInfo, createDatabaseInfo)
            : describeAttachmentInformation(connectionParamWriter, stateInfo);

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "paramBytes.length=", paramBytes.length);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(forOperation);
		writer.writeHandle(0); // DatabaseObjectId
		writer.writeChars(forName);
        writer.writeBytes(paramBytes);
        writer.flush();
    }

    final void connectAuthenticationRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.connectionType=", connection.connectionType, ")");

        stateInfo.callLimitCounter = 100;
        stateInfo.forOP = "connectAuthentication";
        stateInfo.forOPCode = FbIscResultCode.isc_auth_data;
        FbIscOPResponse opResponse;
        scope (exit)
            opResponse.reset();
        auto reader = FbXdrReader(connection);
        const op = readOperationImpl(reader, stateInfo, opResponse);

        // Invalid op(s) for this step
        if (op == FbIsc.op_cont_auth)
        {
            auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, stateInfo.forOP);
            throw new FbException(DbErrorCode.read, msg, null, 0, stateInfo.forOPCode);
        }
    }

    final void connectAuthenticationWrite(ref FbConnectingStateInfo stateInfo, FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.connectionType=", connection.connectionType, ")");

        clearServerInfo();

        auto useCSB = connection.fbConnectionStringBuilder;
        const forOperation = connection.connectionType == DbConnectionType.create
            ? FbIsc.op_create
            : (connection.connectionType == DbConnectionType.service ? FbIsc.op_service_attach : FbIsc.op_attach);
        const forName = connection.connectionType == DbConnectionType.create ? createDatabaseInfo.fileName : useCSB.databaseName;
        const compressFlag = useCSB.compress ? FbIsc.ptype_compress_flag : 0;
        auto protoItems = describeProtocolItems;
        auto paramWriter = FbConnectionWriter(connection, FbIsc.isc_dpb_version1); // Must be version1 at this point
        const paramBytes = describeUserIdentification(paramWriter, stateInfo);

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "paramBytes.length=", paramBytes.length);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_connect);
		writer.writeOperation(forOperation);
		writer.writeInt32(FbIsc.connect_version);
        writer.writeInt32(FbIsc.connect_generic_achitecture_client);
        writer.writeChars(forName);
        writer.writeInt32(protoItems.length); // Protocol count
        writer.writeBytes(paramBytes);
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

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, commandBatch.fbCommand);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(command.handle=", commandBatch.fbCommand.fbHandle, ")");

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

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
    }

    final void createDatabaseWrite(FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto connectionParamWriter = FbConnectionWriter(connection, FbIsc.isc_dpb_version); // Can be latest version depending on protocol version
        const paramBytes = describeCreationInformation(connectionParamWriter, createDatabaseInfo);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_create);
        writer.writeHandle(0);
		writer.writeChars(createDatabaseInfo.fileName);
        writer.writeBytes(paramBytes);
        writer.flush();
    }

    final void deallocateCommandRead(ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse(deferredInfo, null);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(command.fbHandle=", command.fbHandle, ")");

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
		    writer.writeOperation(connection.connectionType == DbConnectionType.service ? FbIsc.op_service_detach : FbIsc.op_detach);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", commandBatch.fbCommand.fbTransaction.fbHandle, ", command.handle=", commandBatch.fbCommand.fbHandle, ")");

		writer.writeOperation(FbIsc.op_batch_exec);
		writer.writeHandle(commandBatch.fbCommand.fbHandle);
		writer.writeHandle(commandBatch.fbCommand.fbTransaction.fbHandle);
    }

    final void executeCommandRead(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        // Nothing to process - just need acknowledge
        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, command);
    }

    final void executeCommandWrite(FbCommand command, DbCommandExecuteType type)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(type=", type, ", transaction.handle=", command.fbTransaction.fbHandle, ", command.handle=", command.fbHandle, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(command.hasStoredProcedureFetched() ? FbIsc.op_execute2 : FbIsc.op_execute);
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

		if (command.columnCount != 0 && command.hasStoredProcedureFetched())
		{
            auto pWriterBlr = FbBlrWriter(connection);
            auto pFldBlr = describeBlrColumns(pWriterBlr, cast(FbColumnList)command.columns);
            writer.writeBytes(pFldBlr.data);
			writer.writeInt32(0); // Output message number
		}

        if (_serverVersion >= FbIsc.protocol_version16)
        {
            const timeout = command.commandTimeout.limitRangeTimeAsMilliSecond();
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

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.scopedData);
        auto r = readGenericResponse(deferredInfo, command);

        const kind = r.data.length == 0
            ? FbCommandPlanInfo.Kind.noData
            : (r.data[0] == FbIsc.isc_info_end
                ? FbCommandPlanInfo.Kind.empty
                : (r.data[0] == FbIsc.isc_info_truncated
                    ? FbCommandPlanInfo.Kind.truncated
                    : FbCommandPlanInfo.Kind.ok));

        final switch (kind)
        {
            case FbCommandPlanInfo.Kind.noData:
                info = FbCommandPlanInfo(kind, null);
                break;
            case FbCommandPlanInfo.Kind.empty:
                info = FbCommandPlanInfo(kind, "");
                break;
            case FbCommandPlanInfo.Kind.truncated:
                info = FbCommandPlanInfo(kind, null);
                break;
            case FbCommandPlanInfo.Kind.ok:
                info = FbCommandPlanInfo(kind, FbCommandPlanInfo.parse(r.data, describeMode));
                break;
        }

        return kind;
    }

    final void executionPlanCommandInfoWrite(FbCommand command, uint mode, uint32 bufferLength)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto describeItems = mode == 0
            ? describeStatementExplaindPlanInfoItems
            : describeStatementPlanInfoItems;
        commandInfoWrite(command, describeItems, bufferLength);
    }

    final FbIscFetchResponse fetchCommandRead(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, ignoreCheckingResponseOp);
        if (op == FbIsc.op_response)
        {
            auto deferredInfo = FbDeferredInfo.init;
            auto r = readGenericResponseImpl(reader, deferredInfo, command);
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

    final void fetchCommandWrite(FbCommand command, int32 fetchRecordCount)
    in
    {
        assert(command.columnCount != 0);
    }
    do
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(fetchRecordCount=", fetchRecordCount, ", command.handle=", command.fbHandle, ")");

        auto writerBlr = FbBlrWriter(connection);
        auto pFldBlr = describeBlrColumns(writerBlr, cast(FbColumnList)command.columns);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_fetch);
		writer.writeHandle(command.fbHandle);
		writer.writeBytes(pFldBlr.data);
		writer.writeInt32(0); // p_sqldata_message_number
		writer.writeInt32(fetchRecordCount > 0 ? fetchRecordCount : int32.max); // p_sqldata_messages
		writer.flush();
    }

    final void messageCommandBatchRead(ref FbCommandBatch commandBatch)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        // Nothing to process - just need acknowledge
        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, commandBatch.fbCommand);
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(command.handle=", commandBatch.fbCommand, ")");

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

    final FbIscBindInfo[] prepareCommandRead(FbCommand command, ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse(deferredInfo, command);

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
            r = readGenericResponse(deferredInfo, command);
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
        string sqlLog() nothrow @safe
        {
            return sql.length > 50 ? sql[0..50].idup : sql.idup;
        }
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", command.fbTransaction.fbHandle, ", command.handle=", command.fbHandle, ", sql=", sqlLog, ")");

        auto bindItems = describeStatementInfoAndBindInfoItems;

		writer.writeOperation(FbIsc.op_prepare_statement);
		writer.writeHandle(command.fbTransaction.fbHandle);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(connection.dialect);
		writer.writeChars(sql);
		writer.writeBytes(bindItems);
		writer.writeInt32(FbIscSize.prepareInfoBufferLength);
    }

    final DbRecordsAffected recordsAffectedCommandRead(FbCommand command, const(DbRecordsAffectedAggregateResult) kind)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.scopedData);
        auto r = readGenericResponse(deferredInfo, command);
        auto counts = r.data.length ? parseRecordsAffected(r.data) : DbRecordsAffectedAggregate.init;
        return counts.toCount(kind);
    }

    final void recordsAffectedCommandWrite(FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        commandInfoWrite(command, describeStatementRowsAffectedInfoItems, FbIscSize.rowsEffectedBufferLength);
    }

    final void rollbackRetainingTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", transaction.fbHandle, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback_retaining);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final void rollbackTransactionRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
    }

    final void rollbackTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(transaction.handle=", transaction.fbHandle, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_rollback);
	    writer.writeHandle(transaction.fbHandle);
        writer.flush();
    }

    final FbIscObject serviceAttachmentRead(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        stateInfo.callLimitCounter = 50;
        stateInfo.forOP = "serviceAttachment";
        stateInfo.forOPCode = FbIscResultCode.isc_auth_data;
        FbIscOPResponse opResponse;
        scope (exit)
            opResponse.reset();
        auto reader = FbXdrReader(connection);
        auto op = readOperationImpl(reader, stateInfo, opResponse);

        if (op != FbIsc.op_response)
        {
            auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(op, stateInfo.forOP);
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_net_read_err);
        }

        auto result = opResponse.generic.getIscObject();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "connection.handle=", result.handle);
        return result;
    }

    final void serviceAttachmentWrite(ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version);
        const paramBytes = describeAttachmentService(paramWriter, stateInfo);

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_service_attach);
        writer.writeHandle(0); // DatabaseObjectId
		writer.writeChars(FbIscText.serviceName);
        writer.writeBytes(paramBytes);
        writer.flush();
    }

    version(none)
    final void serviceDetachmentWrite()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
        if (connection.handle)
        {
		    writer.writeOperation(FbIsc.op_service_detach);
		    writer.writeHandle(connection.fbHandle);
        }
		writer.writeOperation(FbIsc.op_disconnect);
        writer.flush();
    }

    final ubyte[] serviceInfoRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.scopedData);
        auto r = readGenericResponse(deferredInfo, null);
        return r.data;
    }

    final void serviceInfoWrite(scope const(uint8)[] receiveItems, uint bufferLength = FbIscSize.serviceInfoBufferLength)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(bufferLength=", bufferLength, ", receiveItems=", receiveItems.dgToString(), ")");

        //auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_service_info);
        writer.writeHandle(connection.fbHandle);
        writer.writeHandle(0); // Incarnation
        writer.writeBytes([]);
        writer.writeBytes(receiveItems);
		writer.writeInt32(bufferLength);

        debug(debug_pham_db_db_fbprotocol)
        {
            auto xdr = writer.peekBytes();
            debug writeln("ServiceProtocol.Query.xdr.length=", xdr.length, "\n", xdr.dgToString());
        }

        writer.flush();
    }

    final FbIscGenericResponse serviceRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo.init;
        return readGenericResponse(deferredInfo, null);
    }

    final void serviceTraceStartWrite(uint8 action, FbHandle sessionId)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(action=", action, ", sessionId=", sessionId, ")");

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);
		paramWriter.writeType(action);
		if (sessionId)
			paramWriter.writeInt32(FbIsc.isc_spb_trc_id, sessionId);
        const paramBytes = paramWriter.peekBytes();

        serviceStartWrite(paramBytes);
    }

    final void serviceTraceStartWrite(string sessionName, string configuration)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(sessionName=", sessionName, ")");
        debug(debug_pham_db_db_fbprotocol) debug writeln("configuration.length=", configuration.length, "\n", configuration);

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);
		paramWriter.writeType(FbIsc.isc_action_svc_trace_start);
        paramWriter.writeChars2If(FbIsc.isc_spb_trc_name, sessionName);
		paramWriter.writeChars2(FbIsc.isc_spb_trc_cfg, configuration);
        const paramBytes = paramWriter.peekBytes();

        serviceStartWrite(paramBytes);
    }

    final void serviceStartWrite(uint8 action)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(action=", action, ")");

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);
		paramWriter.writeType(action);
        const paramBytes = paramWriter.peekBytes();

        serviceStartWrite(paramBytes);
    }

    final void serviceStartWrite(scope const(ubyte)[] spb)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(spb.length=", spb.length, ")");

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_service_start);
        writer.writeHandle(connection.fbHandle);
		writer.writeHandle(0);
        writer.writeBytes(spb);

        debug(debug_pham_db_db_fbprotocol)
        {
            debug writeln("ServiceProtocol.Start.spb.length=", spb.length, "\n", spb.dgToString());
            auto xdr = writer.peekBytes();
            debug writeln("ServiceProtocol.Start.xdr.length=", xdr.length, "\n", xdr.dgToString());
        }

        writer.flush();
    }

    final void serviceUserAddWrite(scope const(FbIscUserInfo) userInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);
		paramWriter.writeType(FbIsc.isc_action_svc_add_user);
		paramWriter.writeChars2(FbIsc.isc_spb_sec_username, userInfo.userName);
		paramWriter.writeChars2(FbIsc.isc_spb_sec_password, userInfo.userPassword);
		paramWriter.writeChars2If(FbIsc.isc_spb_sec_firstname, userInfo.firstName);
		paramWriter.writeChars2If(FbIsc.isc_spb_sec_middlename, userInfo.middleName);
		paramWriter.writeChars2If(FbIsc.isc_spb_sec_lastname, userInfo.lastName);
        paramWriter.writeInt32If(FbIsc.isc_spb_sec_userid, userInfo.userId);
		paramWriter.writeInt32If(FbIsc.isc_spb_sec_groupid, userInfo.groupId);
        paramWriter.writeChars2If(FbIsc.isc_spb_sec_groupname, userInfo.groupName);
		paramWriter.writeChars2If(FbIsc.isc_spb_sql_role_name, userInfo.roleName);
        const paramBytes = paramWriter.peekBytes();

        serviceStartWrite(paramBytes);
    }

    final void serviceUserDeleteWrite(string userName, string roleName)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);
		paramWriter.writeType(FbIsc.isc_action_svc_delete_user);
		paramWriter.writeChars2(FbIsc.isc_spb_sec_username, userName);
		paramWriter.writeChars2If(FbIsc.isc_spb_sql_role_name, roleName);
        const paramBytes = paramWriter.peekBytes();

        serviceStartWrite(paramBytes);
    }

    final void serviceUserGetWrite(string userName)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto paramWriter = FbServiceWriter(connection, FbIsc.isc_spb_version2);
		paramWriter.writeType(FbIsc.isc_action_svc_display_user);
		paramWriter.writeChars2(FbIsc.isc_spb_sec_username, userName);
        const paramBytes = paramWriter.peekBytes();

        serviceStartWrite(paramBytes);
    }

    final FbIscObject startTransactionRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo.init;
        auto r = readGenericResponse(deferredInfo, null);
        return r.getIscObject();
    }

    final void startTransactionWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(connection.handle=", connection.fbHandle, ")");

        auto paramWriter = FbTransactionWriter(connection);
        auto paramBytes = describeTransaction(paramWriter, transaction);

        auto writer = FbXdrWriter(connection);
        writer.writeOperation(FbIsc.op_transaction);
	    writer.writeHandle(connection.fbHandle);
	    writer.writeBytes(paramBytes);
        writer.flush();
    }

    final FbIscTransactionInfo transactionInfoRead()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.scopedData);
        auto r = readGenericResponse(deferredInfo, null);
        return FbIscTransactionInfo.parse(r.data);
    }

    final void transactionInfoWrite(FbTransaction transaction)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_info_transaction);
        writer.writeHandle(transaction.fbHandle);
		writer.writeHandle(0);
		writer.writeBytes(describeTransactionInfoItems);
		writer.writeInt32(FbIscSize.transactionInfoBufferLength);
        writer.flush();
    }

    final FbIscCommandType typeCommandRead(FbCommand command, ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        const savedScopeDat = deferredInfo.setScopedData();
        scope (exit)
            deferredInfo.restoreScopedData(savedScopeDat);
        auto r = readGenericResponse(deferredInfo, command);
        deferredInfo.restoreScopedData(savedScopeDat);
        const result = r.data.length ? parseCommandType(r.data) : FbIscCommandType.none;
        return result;
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

    final FbIscGenericResponse readGenericResponse(ref FbDeferredInfo deferredInfo, FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_response);
        return readGenericResponseImpl(reader, deferredInfo, command);
    }

    final FbIscSqlResponse readSqlResponse()
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        FbXdrReader reader;
        const op = readOperation(reader, FbIsc.op_sql_response);
        return readSqlResponseImpl(reader);
    }

    final DbValue readValue(ref FbXdrReader reader, DbNamedColumn column, size_t row)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(column=", column.traceString(), ", row=", row, ")");
        version(profile) debug auto p = PerfFunction.create();

        const dbType = column.type;

        if (column.isArray)
            return DbValue.entity(reader.readId(), dbType);

        DbValue readBytesDelegate() @safe
        {
            debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

            auto columnDelegate = column.saveLongData;

            int readerDelegate(int64 savedLength, int64 requestedLength, scope const(ubyte)[] data) @safe
            {
                return columnDelegate(column, savedLength, requestedLength, row, data);
            }

            reader.readBytes(&readerDelegate, FbIscSize.maxBlobSegmentLength);

            return DbValue.dbNull(dbType);
        }

        DbValue readStringDelegate() @safe
        {
            debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

            auto columnDelegate = column.saveLongData;

            int readerDelegate(int64 savedLength, int64 requestedLength, scope const(ubyte)[] data) @safe
            {
                return columnDelegate(column, savedLength, requestedLength, row, data);
            }

            reader.readString(&readerDelegate, FbIscSize.maxBlobSegmentLength);

            return DbValue.dbNull(dbType);
        }

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
                return DbValue(reader.readFixedString(column.baseType));
            case DbType.stringVary:
                return column.saveLongData is null
                    ? DbValue(reader.readString(), dbType)
                    : readStringDelegate();
            case DbType.binaryFixed:
                return DbValue(reader.readFixedBytes(column.baseType));
            case DbType.binaryVary:
                return column.saveLongData is null
                    ? DbValue(reader.readBytes())
                    : readBytesDelegate();
            case DbType.json:
            case DbType.xml:
            case DbType.text:
                auto textId = reader.readId();
                return DbValue.entity(textId, dbType);
            case DbType.blob:
                auto blobId = reader.readId();
                return DbValue.entity(blobId, dbType);

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(__FUNCTION__, toName!DbType(dbType));
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

    final DbRowValue readValues(FbColumnList columns, size_t row)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(row=", row, ")");
        version(profile) debug auto p = PerfFunction.create();

        auto reader = FbXdrReader(connection);

        const nullBitmapBytes = bitLengthToElement!ubyte(columns.length);
		const nullBitmap = BitArrayImpl!ubyte(reader.readOpaqueBytes(nullBitmapBytes));

        auto result = DbRowValue(columns.length, row);
        foreach (i, column; columns)
        {
            if (nullBitmap[i])
                result[i].nullify();
            else
                result[i] = readValue(reader, column, row);
        }
        return result;
    }

    final void releaseCommandBatchRead(ref FbDeferredInfo deferredInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto r = readGenericResponse(deferredInfo, null);
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

    final void callDeferredResponses() @safe
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(deferredResponses.length=", deferredResponses.length, ")");

        // Must use temp to avoid recursive entry - stack overflow
        auto deferredResponses2 = this.deferredResponses;
        this.deferredResponses = null;

        auto deferredInfo = FbDeferredInfo(FbDeferredFlag.deferred);
        foreach (deferredResponse; deferredResponses2)
        {
            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "deferred=", deferredResponse.name);

            deferredResponse.caller(deferredInfo);
        }
        if (deferredInfo.hasError)
            throw deferredInfo.toException();
    }

    @property final FbConnection connection() nothrow pure
    {
        return _connection;
    }

    // Protocol version
    @property final int32 serverVersion() const nothrow pure @nogc
    {
        return _serverVersion;
    }

public:
    FbDeferredResponse[] deferredResponses;

protected:
    enum ignoreCheckingResponseOp = 0;

    final FbOperation acceptResponse(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse,
        ref FbIscAcceptResponse accept)
    {
        stateInfo.serverAcceptType = accept.acceptType;
        stateInfo.serverArchitecture = accept.architecture;
        stateInfo.serverVersion = accept.version_;
        this._serverVersion = stateInfo.serverVersion;
        connection.serverInfo[DbServerIdentifier.protocolAcceptType] = stateInfo.serverAcceptType.to!string();
        connection.serverInfo[DbServerIdentifier.protocolArchitect] = stateInfo.serverArchitecture.to!string();
        connection.serverInfo[DbServerIdentifier.protocolVersion] = stateInfo.serverVersion.to!string();

        setupCompression(stateInfo);
        return setupEncryption(reader, stateInfo, opResponse);
    }

    final FbOperation acceptDataResponse(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse,
        ref FbIscAcceptDataResponse acceptData)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        const op = opResponse.op;

        stateInfo.serverAcceptType = acceptData.acceptType;
        stateInfo.serverArchitecture = acceptData.architecture;
        stateInfo.serverVersion = acceptData.version_;
        stateInfo.serverAuthKey = acceptData.authKey;
        stateInfo.serverAuthData = acceptData.authData;
        stateInfo.serverAuthMethod = acceptData.authName;
        stateInfo.serverAuthKeys = FbIscServerKey.parse(acceptData.authKey);
        this._serverVersion = stateInfo.serverVersion;
        connection.serverInfo[DbServerIdentifier.protocolAcceptType] = stateInfo.serverAcceptType.to!string();
        connection.serverInfo[DbServerIdentifier.protocolArchitect] = stateInfo.serverArchitecture.to!string();
        connection.serverInfo[DbServerIdentifier.protocolVersion] = stateInfo.serverVersion.to!string();

		if (!acceptData.isAuthenticated || op == FbIsc.op_cond_accept)
		{
			if (stateInfo.auth is null || stateInfo.serverAuthMethod != stateInfo.authMethod)
            {
                auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(stateInfo.serverAuthMethod);
                throw new FbException(DbErrorCode.read, msg, null, 0, stateInfo.forOPCode);
            }

            auto useCSB = connection.fbConnectionStringBuilder;
            auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName,
                useCSB.userPassword, stateInfo.serverAuthData[], stateInfo.authData);
            if (status.isError)
                throw new FbException(DbErrorCode.read, status.errorMessage, null, 0, stateInfo.forOPCode);
		}

        setupCompression(stateInfo); // Before further sending requests

        // Authentication info will be resent when doing attachment for other op
        if (op == FbIsc.op_cond_accept)
		{
            contAuthWrite(stateInfo);
            contAuthRead(reader, stateInfo, opResponse);
		}

        return setupEncryption(reader, stateInfo, opResponse);
    }

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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(command.fbHandle=", command.fbHandle, ")");

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

    final FbOperation contAuthRead(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        const op = readOperationImpl(reader, stateInfo, opResponse);
        switch (op)
        {
            case FbIsc.op_response:
                stateInfo.serverAuthKey = opResponse.generic.data;
                stateInfo.serverAuthKeys = FbIscServerKey.parse(opResponse.generic.data);
                break;

            case FbIsc.op_cont_auth:
            case FbIsc.op_crypt_key_callback:
            case FbIsc.op_trusted_auth:
                break;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, stateInfo.forOP);
                throw new FbException(DbErrorCode.read, msg, null, 0, stateInfo.forOPCode);
        }
        return op;
    }

    final FbOperation contAuthResponse(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse, ref FbIscContAuthResponse contAuth)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        stateInfo.serverAuthMethod = contAuth.name;
        stateInfo.serverAuthKey = contAuth.key;
        stateInfo.serverAuthKeys = FbIscServerKey.parse(contAuth.key);

        if (contAuth.name.length)
        {
            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "contAuth.name=", contAuth.name);

            if (stateInfo.authMethod != contAuth.name)
            {
                stateInfo.nextAuthState = 0;
                stateInfo.authMethod = contAuth.name;
                stateInfo.auth = createAuth(stateInfo.authMethod);
            }

            auto useCSB = connection.fbConnectionStringBuilder;
            auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName,
                useCSB.userPassword, contAuth.data, stateInfo.authData);
            if (status.isError)
                throw new FbException(DbErrorCode.read, status.errorMessage, null, 0, stateInfo.forOPCode);
        }

        contAuthWrite(stateInfo);
        return contAuthRead(reader, stateInfo, opResponse);
    }

    final void contAuthWrite(ref FbConnectingStateInfo stateInfo)
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

    final FbAuth createAuth(scope const(char)[] authMethod)
    {
        auto authMap = FbAuth.findAuthMap(authMethod);
        if (!authMap.isValid())
        {
            auto msg = DbMessage.eInvalidConnectionAuthUnsupportedName.fmtMessage(authMethod);
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_auth_data);
        }

        return cast(FbAuth)authMap.createAuth();
    }

    final FbOperation cryptKeyCallbackResponse(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse,
        ref FbIscCryptKeyCallbackResponse cryptKeyCallback, const(int32) protocolVersion)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        {
            auto useCSB = connection.fbConnectionStringBuilder;
            auto cryptKey = useCSB.cryptKey;
            auto writer = FbXdrWriter(connection);
            writer.writeOperation(FbIsc.op_crypt_key_callback);
            writer.writeBytes(cryptKey);
            if (protocolVersion > FbIsc.protocol_version13)
                writer.writeInt32(cryptKeyCallback.size);
            writer.flush();
        }

        return readOperationImpl(reader, stateInfo, opResponse);
    }

    final FbOperation cryptRead(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        const op = readOperationImpl(reader, stateInfo, opResponse);
        if (op != FbIsc.op_crypt_key_callback && op != FbIsc.op_response)
        {
            auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, stateInfo.forOP);
            throw new FbException(DbErrorCode.read, msg, null, 0, stateInfo.forOPCode);
        }
        return op;
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
		writer.writeInt32(FbIsc.isc_dpb_dummy_packet_interval, useCSB.dummyPackageInterval.limitRangeTimeAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_sql_dialect, useCSB.dialect);
		writer.writeChars(FbIsc.isc_dpb_lc_ctype, useCSB.charset);
        writer.writeCharsIf(FbIsc.isc_dpb_user_name, useCSB.userName);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, useCSB.roleName);
		writer.writeInt32(FbIsc.isc_dpb_connect_timeout, useCSB.connectionTimeout.limitRangeTimeAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_process_id, currentProcessId());
		writer.writeChars(FbIsc.isc_dpb_process_name, currentProcessName());
		writer.writeCharsIf(FbIsc.isc_dpb_client_version, useCSB.applicationVersion);
		writer.writeChars(FbIsc.isc_dpb_host_name, currentComputerName());
		writer.writeChars(FbIsc.isc_dpb_os_user, currentUserName());
        writer.writeBytes(FbIsc.isc_spb_utf8_filename, [0x1]);

		if (useCSB.cachePages)
			writer.writeInt32(FbIsc.isc_dpb_num_buffers, useCSB.cachePages);
		if (!useCSB.databaseTrigger)
		    writer.writeInt32(FbIsc.isc_dpb_no_db_triggers, 1);
		if (!useCSB.garbageCollect)
		    writer.writeInt32(FbIsc.isc_dpb_no_garbage_collect, 1);

        writer.writeBytesIf(FbIsc.isc_dpb_specific_auth_data, stateInfo.authData[]);

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

    final ubyte[] describeAttachmentService(return ref FbServiceWriter writer, ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto useCSB = connection.fbConnectionStringBuilder;

        stateInfo.nextAuthState = 0;
        stateInfo.authData = null;
        stateInfo.authMethod = useCSB.integratedSecurityName;
        stateInfo.auth = createAuth(stateInfo.authMethod);
        const isMultiStates = stateInfo.auth.multiStates > 1;
        if (isMultiStates)
        {
            auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword, null, stateInfo.authData);
            if (status.isError)
                throw new FbException(DbErrorCode.write, status.errorMessage, null, 0, FbIscResultCode.isc_auth_data);
        }

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "stateInfo.authMethod=", stateInfo.authMethod, ", stateInfo.authData.length=", stateInfo.authData.length);

		writer.writePreamble();
		writer.writeBytes1(FbIsc.isc_spb_dummy_packet_interval, writer.asBytes(useCSB.dummyPackageInterval.limitRangeTimeAsSecond()));
        writer.writeChars1If(FbIsc.isc_spb_user_name, useCSB.userName);
        writer.writeChars1If(FbIsc.isc_spb_sql_role_name, useCSB.roleName);
		writer.writeBytes1(FbIsc.isc_spb_process_id, writer.asBytes(currentProcessId()));
		writer.writeChars1(FbIsc.isc_spb_process_name, currentProcessName());
		writer.writeChars1If(FbIsc.isc_spb_client_version, useCSB.applicationVersion);
		writer.writeChars1(FbIsc.isc_spb_host_name, currentComputerName());
		writer.writeChars1(FbIsc.isc_spb_os_user, currentUserName());
        writer.writeBytes1(FbIsc.isc_spb_utf8_filename, [0x1]);
		writer.writeChars1(FbIsc.isc_spb_expected_db, useCSB.databaseName);

        if (stateInfo.authData.length)
        {
            writer.writeChars1(FbIsc.isc_spb_auth_plugin_name, stateInfo.authMethod);
            writer.writeChars1(FbIsc.isc_spb_auth_plugin_list, stateInfo.authMethod);
            writer.writeBytes1(FbIsc.isc_spb_specific_auth_data, stateInfo.authData[]);
        }
        else
            writer.writeChars1(FbIsc.isc_spb_password, useCSB.userPassword);

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "dpbValue.length=", result.length, ", dpbValue=", result.dgToString());
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

    final ubyte[] describeCreationInformation(return ref FbConnectionWriter writer, ref FbConnectingStateInfo stateInfo,
        FbCreateDatabaseInfo createDatabaseInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(stateInfo.authData=", stateInfo.authData.toString(), ")");

        auto useCSB = connection.fbConnectionStringBuilder;
        auto useRoleName = createDatabaseInfo.roleName.length ? createDatabaseInfo.roleName : useCSB.roleName;
        auto useUserName = createDatabaseInfo.ownerName.length ? createDatabaseInfo.ownerName : useCSB.userName;

		writer.writeVersion();
		writer.writeInt32(FbIsc.isc_dpb_dummy_packet_interval, useCSB.dummyPackageInterval.limitRangeTimeAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_sql_dialect, useCSB.dialect);
		writer.writeChars(FbIsc.isc_dpb_lc_ctype, useCSB.charset);
        if (writer.writeCharsIf(FbIsc.isc_dpb_user_name, useUserName))
            writer.writeCharsIf(FbIsc.isc_dpb_password, createDatabaseInfo.ownerPassword);
	    writer.writeCharsIf(FbIsc.isc_dpb_sql_role_name, useRoleName);
		writer.writeInt32(FbIsc.isc_dpb_connect_timeout, useCSB.connectionTimeout.limitRangeTimeAsSecond());
		writer.writeInt32(FbIsc.isc_dpb_process_id, currentProcessId());
		writer.writeChars(FbIsc.isc_dpb_process_name, currentProcessName());
		writer.writeCharsIf(FbIsc.isc_dpb_client_version, useCSB.applicationVersion);
		writer.writeChars(FbIsc.isc_dpb_host_name, currentComputerName());
		writer.writeChars(FbIsc.isc_dpb_os_user, currentUserName());
        writer.writeBytesIf(FbIsc.isc_dpb_specific_auth_data, stateInfo.authData[]);
        writer.writeCharsIf(FbIsc.isc_dpb_set_db_charset, createDatabaseInfo.defaultCharacterSet);
		writer.writeInt32(FbIsc.isc_dpb_force_write, createDatabaseInfo.forcedWrite ? 1 : 0);
		writer.writeInt32(FbIsc.isc_dpb_overwrite, createDatabaseInfo.overwrite ? 1 : 0);
		writer.writeBytes(FbIsc.isc_dpb_utf8_filename, [0x1]);

		if (createDatabaseInfo.pageSize > 0)
			writer.writeInt32(FbIsc.isc_dpb_page_size, createDatabaseInfo.toKnownPageSize(createDatabaseInfo.pageSize));

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "dpbValue.length=", result.length, ", dpbValue=", result.dgToString());
        return result;
    }

    final ubyte[] describeCreationInformation(return ref FbConnectionWriter writer,
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
        writer.writeBytes(FbIsc.isc_dpb_utf8_filename, [0x1]);

		if (createDatabaseInfo.pageSize > 0)
			writer.writeInt32(FbIsc.isc_dpb_page_size, createDatabaseInfo.pageSize);

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "dpbValue.length=", result.length, ", dpbValue=", result.dgToString());
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        static ubyte lockTableBehavior(const ref DbLockTable lockedTable) nothrow pure @safe
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

        static ubyte lockTableReadOrWrite(const ref DbLockTable lockedTable) nothrow pure @safe
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
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

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
            writer.writeInt32(FbIsc.isc_tpb_lock_timeout, transaction.lockTimeout.limitRangeTimeAsSecond);
        if (transaction.autoCommit)
            writer.writeOpaqueUInt8(FbIsc.isc_tpb_autocommit);
    }

    final ubyte[] describeUserIdentification(return ref FbConnectionWriter writer, ref FbConnectingStateInfo stateInfo)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(userName=", connection.fbConnectionStringBuilder.userName, ")");

        auto useCSB = connection.fbConnectionStringBuilder;

        stateInfo.nextAuthState = 0;
        stateInfo.authData = null;
        stateInfo.authMethod = useCSB.integratedSecurityName;
        stateInfo.auth = createAuth(stateInfo.authMethod);
        const isMultiStates = stateInfo.auth.multiStates > 1;
        if (isMultiStates)
        {
            auto status = stateInfo.auth.getAuthData(stateInfo.nextAuthState, useCSB.userName, useCSB.userPassword, null, stateInfo.authData);
            if (status.isError)
                throw new FbException(DbErrorCode.write, status.errorMessage, null, 0, FbIscResultCode.isc_auth_data);
        }

        writer.writeChars(FbIsc.cnct_user, currentUserName());
        writer.writeChars(FbIsc.cnct_host, currentComputerName());
        writer.writeInt8(FbIsc.cnct_user_verification, 0);
        writer.writeChars(FbIsc.cnct_login, useCSB.userName);
        writer.writeChars(FbIsc.cnct_plugin_name, stateInfo.authMethod);
        writer.writeChars(FbIsc.cnct_plugin_list, stateInfo.authMethod);

        if (isMultiStates)
        {
            assert(stateInfo.authData.length);

            writer.writeMultiParts(FbIsc.cnct_specific_data, stateInfo.authData[]);
            stateInfo.nextAuthState++;

            debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "specificData=", stateInfo.authData.toString());
        }

        // Must be last because of wrong check order on server side if encounter earlier
        writer.writeInt32(FbIsc.cnct_client_crypt, hostToNetworkOrder!int32(getCryptedConnectionCode()));

        auto result = writer.peekBytes();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "result=", result.dgToString());
        return result;
    }

    final void describeValue(ref FbXdrWriter writer, DbNamedColumn column, ref DbValue value)
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
            case DbType.blob:
                return writer.writeId(value.get!FbId());

            case DbType.record:
            case DbType.array:
            case DbType.unknown:
                auto msg = DbMessage.eUnsupportDataType.fmtMessage(__FUNCTION__, toName!DbType(column.type));
                throw new FbException(DbErrorCode.write, msg, null, 0, FbIscResultCode.isc_net_write_err);
        }
    }

    override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _serverVersion = 0;
        if (isDisposing(disposingReason))
            _connection = null;

        debug(debug_pham_db_db_fbprotocol) debug writeln("**********");
        return ResultCode.ok;
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

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "version_=", version_, ", acceptType=", acceptType, ", authenticated=", authenticated,
            ", authName=", authName, ", authData=", authData.dgToString(), ", authKey=", authKey.dgToString());

        return FbIscAcceptDataResponse(version_, architecture, acceptType, authData, authName, authenticated, authKey);
    }

    final FbIscAcceptResponse readAcceptResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto version_ = FbIscAcceptResponse.normalizeVersion(reader.readInt32());
        auto architecture = reader.readInt32();
        auto acceptType = reader.readInt32();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "version_=", version_, ", architecture=", architecture, ", acceptType=", acceptType);

        return FbIscAcceptResponse(version_, architecture, acceptType);
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

    final FbIscContAuthResponse readContAuthResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rData = reader.readBytes();
        auto rName = reader.readString();
        auto rList = reader.readBytes();
        auto rKey = reader.readBytes();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rName=", rName, ", rData=", rData.dgToString(),
            ", rKey=", rKey.dgToString(), ", rList=", rList.dgToString());

        return FbIscContAuthResponse(rData, rName, rList, rKey);
    }

    final FbIscCryptKeyCallbackResponse readCryptKeyCallbackResponseImpl(ref FbXdrReader reader, const(int32) protocolVersion)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rData = reader.readBytes();
        auto rSize = protocolVersion > FbIsc.protocol_version13 ? reader.readInt32() : int32.min; // Use min to indicate not used - zero may be false positive

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rSize=", rSize, ", rData=", rData.dgToString());

        return FbIscCryptKeyCallbackResponse(rData, rSize);
    }

    final FbIscFetchResponse readFetchResponseImpl(ref FbXdrReader reader)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rStatus = reader.readInt32();
        auto rCount = reader.readInt32();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rStatus=", rStatus, ", rCount=", rCount);
        return FbIscFetchResponse(rStatus, rCount);
    }

    final FbIscGenericResponse readGenericResponseImpl(ref FbXdrReader reader, ref FbDeferredInfo deferredInfo, FbCommand command)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "()");

        auto rHandle = reader.readHandle();
        auto rId = reader.readId();
        auto rData = deferredInfo.flags.scopedData ? reader.consumeBytes() : reader.readBytes();
        auto rStatues = reader.readStatuses();

        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "rHandle=", rHandle, ", rId=", rId, ", rData=", rData.dgToString(),
            ", isError=", rStatues.isError,  ", errorCode=", rStatues.errorCode());

        if (rStatues.isError)
        {
            if (deferredInfo.flags.deferred)
                deferredInfo.errorStatues ~= rStatues;
            else
                throw new FbException(rStatues);
        }

        auto result = FbIscGenericResponse(rHandle, rId, rData, rStatues);
        if (command is null)
            result.statues.getWarn(connection.notificationMessages);
        else
            result.statues.getWarn(command.notificationMessages);
        return result;
    }

    final FbOperation readOperation(out FbXdrReader reader, const(FbOperation) expectedOperation)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(expectedOperation=", expectedOperation, ", deferredResponses.length=", deferredResponses.length, ")");

        reader = FbXdrReader(connection);
        return readOperationImpl(reader, expectedOperation);
    }

    final FbOperation readOperationImpl(ref FbXdrReader reader, const(FbOperation) expectedOperation)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(expectedOperation=", expectedOperation, ", deferredResponses.length=", deferredResponses.length, ")");

        if (deferredResponses.length != 0)
            callDeferredResponses();

        scope (failure)
            connection.fatalError(DbFatalErrorReason.readData, connection.state);

        auto result = reader.readOperation();
        debug(debug_pham_db_db_fbprotocol) debug writeln("\t", "result=", result);
        if (expectedOperation != ignoreCheckingResponseOp && expectedOperation != result)
        {
            auto msg = DbMessage.eUnexpectReadOperation.fmtMessage(result, expectedOperation);
            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_net_read_err);
        }
        return result;
    }

    final FbOperation readOperationImpl(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse)
    {
        debug(debug_pham_db_db_fbprotocol) debug writeln(__FUNCTION__, "(deferredResponses.length=", deferredResponses.length, ")");

        if (stateInfo.callLimitCounter-- == 0)
        {
            auto msg = DbMessage.eConnectOverflow.fmtMessage(stateInfo.forOP);
            throw new FbException(DbErrorCode.read, msg, null, 0, stateInfo.forOPCode);
        }

        auto op = readOperationImpl(reader, ignoreCheckingResponseOp);

        switch (op)
        {
            case FbIsc.op_accept:
                auto accept = readAcceptResponseImpl(reader);
                opResponse.reset();
                opResponse.op = op;
                opResponse.accept = accept;

                return acceptResponse(reader, stateInfo, opResponse, accept);

            case FbIsc.op_accept_data:
            case FbIsc.op_cond_accept:
                auto acceptData = readAcceptDataResponseImpl(reader);
                opResponse.reset();
                opResponse.op = op;
                opResponse.acceptData = acceptData;

                return acceptDataResponse(reader, stateInfo, opResponse, acceptData);

            case FbIsc.op_cont_auth:
                auto contAuth = readContAuthResponseImpl(reader);
                opResponse.reset();
                opResponse.op = op;
                opResponse.contAuth = contAuth;

                return contAuthResponse(reader, stateInfo, opResponse, contAuth);

            case FbIsc.op_crypt_key_callback:
                auto protocolVersion = stateInfo.serverVersion == 0 ? FbIsc.protocol_version15 : stateInfo.serverVersion;

                auto cryptKeyCallback = readCryptKeyCallbackResponseImpl(reader, protocolVersion);
                opResponse.reset();
                opResponse.op = op;
                opResponse.cryptKeyCallback = cryptKeyCallback;

                return cryptKeyCallbackResponse(reader, stateInfo, opResponse, cryptKeyCallback, protocolVersion);

            case FbIsc.op_response:
                auto genericDeferredInfo = FbDeferredInfo.init;
                auto generic = readGenericResponseImpl(reader, genericDeferredInfo, null);
                opResponse.reset();
                opResponse.op = op;
                opResponse.generic = generic;
                break;

            case FbIsc.op_trusted_auth:
                auto trustedAuth = readTrustedAuthResponseImpl(reader);
                opResponse.reset();
                opResponse.op = op;
                opResponse.trustedAuth = trustedAuth;

                stateInfo.serverAuthKey = trustedAuth.data;
                stateInfo.serverAuthKeys = FbIscServerKey.parse(trustedAuth.data);

                break;

            default:
                auto msg = DbMessage.eUnhandleIntOperation.fmtMessage(op, stateInfo.forOP);
                throw new FbException(DbErrorCode.read, msg, null, 0, stateInfo.forOPCode);
        }
        return op;
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

    final void setupCompression(ref FbConnectingStateInfo stateInfo)
    {
        const compress = canCompressConnection(stateInfo);
		if (compress == DbCompressConnection.zip)
        {
            connection.serverInfo[DbServerIdentifier.protocolCompressed] = toName(compress);
            compressSetupBufferFilter();
        }
    }

    final FbOperation setupEncryption(ref FbXdrReader reader, ref FbConnectingStateInfo stateInfo, ref FbIscOPResponse opResponse)
    {
        const canEncrypted = canCryptedConnection(stateInfo);
        if (canEncrypted != DbEncryptedConnection.disabled && stateInfo.serverAuthKey.length)
        {
            connection.serverInfo[DbServerIdentifier.protocolEncrypted] = toName(canEncrypted);
            cryptWrite(stateInfo);
            cryptSetupBufferFilter(stateInfo); // after writing before reading
            cryptRead(reader, stateInfo, opResponse);
            validateRequiredEncryption(true);
        }
        else
            validateRequiredEncryption(false);
        return opResponse.op;
    }

    final void validateRequiredEncryption(bool wasEncryptedSetup)
    {
		if (!wasEncryptedSetup && getCryptedConnectionCode() == FbIsc.cnct_client_crypt_required)
        {
            auto msg = DbMessage.eInvalidConnectionRequiredEncryption.fmtMessage(connection.connectionStringBuilder.forErrorInfo);
            throw new FbException(DbErrorCode.connect, msg, null, 0, FbIscResultCode.isc_wirecrypt_incompatible);
        }
    }

private:
    FbConnection _connection;
    int32 _serverVersion; // Protocol version
}

// If change, please update FbIscBlobSize
static immutable ubyte[] describeBlobSizeInfoItems = [
    FbIsc.isc_info_blob_max_segment,
    FbIsc.isc_info_blob_num_segments,
    FbIsc.isc_info_blob_total_length,
    FbIsc.isc_info_blob_type,
    FbIsc.isc_info_end,
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

// Transaction information
static immutable ubyte[] describeTransactionInfoItems = [
    FbIsc.isc_info_tra_id,
    FbIsc.isc_info_tra_oldest_active,
    FbIsc.isc_info_tra_oldest_snapshot,
    FbIsc.isc_info_tra_isolation,
    FbIsc.isc_info_tra_access,
    FbIsc.isc_info_tra_lock_timeout,
    FbIsc.isc_info_end,
    ];
