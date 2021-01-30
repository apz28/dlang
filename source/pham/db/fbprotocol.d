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

version (unittest) import pham.utl.utltest;
import pham.utl.bit_array;
import pham.utl.enum_set;
import pham.utl.utlobject;
import pham.cp.auth_rsp;
import pham.cp.cipher;
import pham.db.message;
import pham.db.convert;
import pham.db.util;
import pham.db.type;
import pham.db.dbobject;
import pham.db.buffer;
import pham.db.buffer_filter;
import pham.db.buffer_filter_compressor;
import pham.db.buffer_filter_cipher;
import pham.db.value;
import pham.db.database : DbNamedColumn;
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

FbIscBlobSize parseBlobSizeInfo(scope const(ubyte)[] data) @safe
{
    FbIscBlobSize result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2; // -2 for item length
    size_t pos = 0;
    while (pos < endPos)
    {
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

        const len = parseInt32!true(data, pos, 2, typ);
        switch (typ)
        {
            case FbIsc.isc_info_blob_max_segment:
                result.maxSegment = parseInt32!true(data, pos, len, typ);
                break;
            case FbIsc.isc_info_blob_num_segments:
                result.segmentCount = parseInt32!true(data, pos, len, typ);
                break;
            case FbIsc.isc_info_blob_total_length:
                result.length = parseInt32!true(data, pos, len, typ);
                break;
            default:
                pos = data.length; // break out while loop because of garbage
                break;
        }
    }

    version (TraceFunction) dgFunctionTrace("maxSegment=", result.maxSegment, ", segmentCount=", result.segmentCount, ", length=", result.length);

    return result;
}

bool parseBool(bool Advance)(scope const(ubyte)[] data, size_t index, int type) @safe
if (Advance == false)
{
    parseCheckLength(data, index, 1, type);
    return parseBoolImpl(data, index);
}

int parseBool(bool Advance)(scope const(ubyte)[] data, ref size_t index, int type) @safe
if (Advance == true)
{
    parseCheckLength(data, index, 1, type);
    return parseBoolImpl(data, index);
}

pragma(inline, true)
private bool parseBoolImpl(scope const(ubyte)[] data, ref size_t index) nothrow @safe
{
    return data[index++] == 1;
}

pragma(inline, true)
void parseCheckLength(scope const(ubyte)[] data, size_t index, uint length, int type) @safe
{
    if (index + length > data.length)
    {
        auto msg = format(DbMessage.eInvalidSQLDANotEnoughData, type, length);
        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
    }
}

int32 parseInt32(bool Advance)(scope const(ubyte)[] data, size_t index, uint length, int type) @safe
if (Advance == false)
{
    parseCheckLength(data, index, length, type);
    return parseInt32Impl(data, index, length);
}

int32 parseInt32(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length, int type) @safe
if (Advance == true)
{
    parseCheckLength(data, index, length, type);
    return parseInt32Impl(data, index, length);
}

private int32 parseInt32Impl(scope const(ubyte)[] data, ref size_t index, uint length) nothrow @safe
{
	int32 result = 0;
	uint shift = 0;
	while (length--)
	{
		result += cast(int)data[index++] << shift;
		shift += 8;
	}
	return result;
}

version (none)
int64 parseInt64(bool Advance)(scope const(ubyte)[] data, size_t index, uint length, int type) @safe
if (Advance == false)
{
    parseCheckLength(data, index, length, type);
    return parseInt64Impl(data, index, length);
}

version (none)
int64 parseInt64(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length, int type) @safe
if (Advance == true)
{
    parseCheckLength(data, index, length, type);
    return parseInt64Impl(data, index, length);
}

version (none)
private int64 parseInt64Impl(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length) nothrow @safe
{
	int64 result = 0;
	uint shift = 0;
	while (length--)
	{
		result += cast(long)data[index++] << shift;
		shift += 8;
	}
	return result;
}

string parseString(bool Advance)(scope const(ubyte)[] data, size_t index, uint length, int type) @safe
if (Advance == false)
{
    parseCheckLength(data, index, length, type);
    return parseStringImpl(data, index, length);
}

string parseString(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length, int type) @safe
if (Advance == true)
{
    parseCheckLength(data, index, length, type);
    return parseStringImpl(data, index, length);
}

pragma(inline, true)
private string parseStringImpl(scope const(ubyte)[] data, ref size_t index, uint length) nothrow @trusted
{
    if (length)
    {
        auto result = ((cast(char[])data[index..index + length])).idup;
        index += length;
        return result;
    }
    else
        return null;
}

FbIscInfo[] parseInfo(scope const(ubyte)[] data) @safe
{
    FbIscInfo[] result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2; // -2 for item length
    size_t pos = 0;
    while (pos < endPos)
    {
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

        const len = parseInt32!true(data, pos, 2, typ);
        switch (typ)
        {
			// Database characteristics

    		// Number of database pages allocated
			case FbIsc.isc_info_allocation:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Database version (level) number:
			    1 byte containing the number 1
			    1 byte containing the version number
			*/
			case FbIsc.isc_info_base_level:
                parseCheckLength(data, pos, 2, typ);
				result ~= FbIscInfo(toVersionString([data[pos], data[pos + 1]]));
				break;

			/** Database file name and site name:
    			1 byte containing the number 2
	    		1 byte containing the length, d, of the database file name in bytes
		    	A string of d bytes, containing the database file name
			    1 byte containing the length, l, of the site name in bytes
			    A string of l bytes, containing the site name
			*/
			case FbIsc.isc_info_db_id:
                auto pos2 = pos + 1;
                int len2 = parseInt32!true(data, pos2, 1, typ);
                auto dbFile = parseString!true(data, pos2, len2, typ);

                len2 = parseInt32!true(data, pos2, 1, typ);
                auto siteName = parseString!false(data, pos2, len2, typ);

                result ~= FbIscInfo(siteName ~ ":" ~ dbFile);
				break;

			/** Database implementation number:
			    1 byte containing a 1
			    1 byte containing the implementation number
			    1 byte containing a class number, either 1 or 12
			*/
			case FbIsc.isc_info_implementation:
                parseCheckLength(data, pos, 3, typ);
				result ~= FbIscInfo(toVersionString([data[pos], data[pos + 1], data[pos + 2]]));
				break;

			/** 0 or 1
			    0 indicates space is reserved on each database page for holding
			      backup versions of modified records [Default]
			    1 indicates no space is reserved for such records
			*/
			case FbIsc.isc_info_no_reserve:
				result ~= FbIscInfo(parseBool!false(data, pos, typ));
				break;

			/** ODS major version number
			    _ Databases with different major version numbers have different
			    physical layouts; a database engine can only access databases
			    with a particular ODS major version number
			    _ Trying to attach to a database with a different ODS number
			    results in an error
			*/
			case FbIsc.isc_info_ods_version:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** On-disk structure (ODS) minor version number; an increase in a
				minor version number indicates a non-structural change, one that
				still allows the database to be accessed by database engines with
				the same major version number but possibly different minor
				version numbers
			*/
			case FbIsc.isc_info_ods_minor_version:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Number of bytes per page of the attached database; use with
				isc_info_allocation to determine the size of the database
			*/
			case FbIsc.isc_info_page_size:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Version identification string of the database implementation:
				1 byte containing the number number of message
				1 byte specifying the length, of the following string
				n bytes containing the string
			*/
			case FbIsc.isc_info_version:
			case FbIsc.isc_info_firebird_version:
                uint msgCount = parseInt32!false(data, pos, 1, typ);
                auto pos2 = pos + 1;
                while (msgCount--)
				{
                    const len2 = parseInt32!true(data, pos2, 1, typ);
                    result ~= FbIscInfo(parseString!true(data, pos2, len2, typ));
				}
				break;

			// Environmental characteristics

			// Amount of server memory (in bytes) currently in use
			case FbIsc.isc_info_current_memory:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Number specifying the mode in which database writes are performed
				0 for asynchronous
                1 for synchronous
			*/
			case FbIsc.isc_info_forced_writes:
				result ~= FbIscInfo(parseBool!false(data, pos, typ));
				break;

			/** Maximum amount of memory (in bytes) used at one time since the first
			    process attached to the database
			*/
			case FbIsc.isc_info_max_memory:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of memory buffers currently allocated
			case FbIsc.isc_info_num_buffers:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Number of transactions that are committed between sweeps to
			    remove database record versions that are no longer needed
		    */
			case FbIsc.isc_info_sweep_interval:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Performance statistics

			// Number of reads from the memory data cache
			case FbIsc.isc_info_fetches:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of writes to the memory data cache
			case FbIsc.isc_info_marks:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of page reads
			case FbIsc.isc_info_reads:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of page writes
			case FbIsc.isc_info_writes:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Database operation counts

			// Number of removals of a version of a record
			case FbIsc.isc_info_backout_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of database deletes since the database was last attached
			case FbIsc.isc_info_delete_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Number of removals of a record and all of its ancestors, for records
			    whose deletions have been committed
			*/
			case FbIsc.isc_info_expunge_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of inserts into the database since the database was last attached
			case FbIsc.isc_info_insert_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of removals of old versions of fully mature records
			case FbIsc.isc_info_purge_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of reads done via an index since the database was last attached
			case FbIsc.isc_info_read_idx_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			/** Number of sequential sequential table scans (row reads) done on each
			    table since the database was last attached
			*/
			case FbIsc.isc_info_read_seq_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

    		// Number of database updates since the database was last attached
			case FbIsc.isc_info_update_count:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Misc

			case FbIsc.isc_info_db_class:
				const serverClass = parseInt32!false(data, pos, len, typ);
                string serverText = serverClass == FbIsc.isc_info_db_class_classic_access
					    ? FbIscText.isc_info_db_class_classic_text
                        : FbIscText.isc_info_db_class_server_text;
				result ~= FbIscInfo(serverText);
				break;

			case FbIsc.isc_info_db_read_only:
				result ~= FbIscInfo(parseBool!false(data, pos, typ));
				break;

            // Database size in pages
			case FbIsc.isc_info_db_size_in_pages:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

            // Number of oldest transaction
			case FbIsc.isc_info_oldest_transaction:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

            // Number of oldest active transaction
			case FbIsc.isc_info_oldest_active:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

            // Number of oldest snapshot transaction
			case FbIsc.isc_info_oldest_snapshot:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of next transaction
			case FbIsc.isc_info_next_transaction:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

			// Number of active	transactions
			case FbIsc.isc_info_active_transactions:
				result ~= FbIscInfo(parseInt32!false(data, pos, len, typ));
				break;

    		// Active user name
			case FbIsc.isc_info_user_names:
                const uint len2 = parseInt32!false(data, pos, 1, typ);
				result ~= FbIscInfo(parseString!false(data, pos + 1, len2, typ));
				break;

            default:
                break;
        }
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

int32 parseCommandType(scope const(ubyte)[] data) @safe
{
    int32 result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2;
	size_t pos = 0;
	while (pos < endPos)
	{
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

		const len = parseInt32!true(data, pos, 2, typ);
		switch (typ)
		{
			case FbIsc.isc_info_sql_stmt_type:
				result = parseInt32!true(data, pos, len, typ);
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
    this(FbConnection connection) nothrow pure @safe
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
		writer.writeOperation(FbIsc.op_allocate_statement);
		writer.writeHandle(connection.fbHandle);
        writer.flush();
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
            return parseBlobSizeInfo(response.data);
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

        auto useCSB = connection.fbConnectionStringBuilder;
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

        auto reader = FbXdrReader(connection);

        const op = reader.readOperation();
        switch (op)
        {
            //case FbIsc.op_cont_auth:
            case FbIsc.op_accept:
            case FbIsc.op_cond_accept:
            case FbIsc.op_accept_data:
                auto v = reader.readInt32();
                if (v < 0)
			        v = FbIsc.protocol_flag | cast(ushort)(v & FbIsc.protocol_mask);
                _serverVersion = v;
                auto serverArchitect = reader.readInt32();
                _serverMinType = reader.readInt32();

                connection.serverInfo[FbIdentifier.serverArchitect] = to!string(serverArchitect);
                connection.serverInfo[FbIdentifier.serverMinType] = to!string(serverMinType);
                connection.serverInfo[FbIdentifier.serverVersion] = to!string(serverVersion);

                version (TraceFunction) dgFunctionTrace(
                    "serverVersion=", serverVersion,
                    ", serverArchitect=", serverArchitect,
                    ", serverMinType=", serverMinType);

                if (op == FbIsc.op_cond_accept || op == FbIsc.op_accept_data)
                {
				    auto serverAuthData = reader.readBytes();
					auto acceptPluginName = reader.readChars();
					auto isAuthenticated = reader.readBool();
					_serverAuthKey = reader.readBytes();

                    auto useCSB = connection.fbConnectionStringBuilder;

					if (!isAuthenticated || op == FbIsc.op_cond_accept)
					{
						if (_auth is null || acceptPluginName != _auth.name)
                        {
                            auto msg = format(DbMessage.eInvalidConnectionAuthUnsupportedName, acceptPluginName);
                            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
                        }

                        _authData = _auth.getAuthData(useCSB.normalizedUserName, useCSB.userPassword, serverAuthData);
                        if (_authData.length == 0)
                        {
                            auto msg = format(DbMessage.eInvalidConnectionAuthServerData, acceptPluginName);
                            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_auth_data);
                        }

						//case SspiHelper.PluginName: todo
						//	AuthData = sspi.GetClientSecurity(serverData);
						//	break;
					}

					if (canCompressConnection())
                    {
                        connection.serverInfo[FbIdentifier.serverCompressed] = dbBoolTrues[0];
                        compressSetupBufferFilter();
                    }

                    // Authentication info will be resent when doing attachment for other op
                    if (op == FbIsc.op_cond_accept)
					{
                        connectAuthenticationAcceptWrite();
                        connectAuthenticationAcceptRead();
                        isAuthenticated = true;
					}

                    auto serverEncrypted = op == FbIsc.op_cond_accept && canCryptedConnection();
                    if (serverEncrypted)
                    {
                        connection.serverInfo[FbIdentifier.serverEncrypted] = dbBoolTrues[0];
                        cryptWrite();
                        cryptSetupBufferFilter(); // after writing before reading
                        cryptRead();
                    }

					if (!serverEncrypted && getCryptedConnectionCode() == FbIsc.connect_crypt_required)
                    {
                        auto msg = format(DbMessage.eInvalidConnectionRequiredEncryption, useCSB.forErrorInfo);
                        throw new FbException(msg, DbErrorCode.connect, 0, FbIscResultCode.isc_wirecrypt_incompatible);
                    }
                }

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
            {
                const len = parseInt32!false(response.data, 1, 2, describeMode);
                auto plan = len > 0
                    ? parseString!false(response.data, 3, len, describeMode)
                    : "";
                info = FbCommandPlanInfo(kind, plan);
                return kind;
            }
        }
    }

    final void executionPlanCommandInfoWrite(FbCommand command, uint mode, uint32 bufferLength)
    {
        version (TraceFunction) dgFunctionTrace();

        auto describeItems = mode == 0
            ? describeStatementPlanInfoItems
            : describeStatementExplaindPlanInfoItems;
        writeCommandInfo(command, describeItems, bufferLength);
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

        FbIscBindInfo[] bindResult;
        ptrdiff_t previousBindIndex = -1; // Start with unknown value
        ptrdiff_t previousFieldIndex = 0;

        while (!parseBindInfo(response.data, bindResult, previousBindIndex, previousFieldIndex))
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
                        ? bindResult[truncateBindIndex].length
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

            writeCommandInfo(command, truncateBindItems, FbIscSize.prepareInfoBufferLength);
            response = readGenericResponse();
        }

        return bindResult;
    }

    final prepareCommandWrite(FbCommand command, scope const(char)[] sql)
    {
        version (TraceFunction) dgFunctionTrace();

        auto useCSB = connection.fbConnectionStringBuilder;
        auto bindItems = describeStatementInfoAndBindInfoItems;

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_prepare_statement);
		writer.writeHandle(command.fbTransaction.fbHandle);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(useCSB.dialect);
		writer.writeChars(sql);
		writer.writeBytes(bindItems);
		writer.writeInt32(FbIscSize.prepareInfoBufferLength);
        writer.flush();
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

        writeCommandInfo(command, describeStatementRowsAffectedInfoItems, FbIscSize.rowsEffectedBufferLength);
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

        writeCommandInfo(command, describeStatementTypeInfoItems, FbIscSize.statementTypeBufferLength);
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

    final DbValue readValue(FbCommand command, ref FbXdrReader reader, DbNamedColumn column)
    {
        version (TraceFunction)
        dgFunctionTrace("column.type=", toName!DbType(column.type),
            ", baseTypeId=", column.baseTypeId,
            ", baseSubtypeId=", column.baseSubTypeId,
            ", baseNumericScale=", column.baseNumericScale);

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
            case DbType.decimal:
                return DbValue(reader.readDecimal(column.baseType), column.type);
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

        auto reader = FbXdrReader(connection);

        const nullByteCount = BitArray.lengthToElement!8(fields.length);
		auto nullBytes = reader.readOpaqueBytes(nullByteCount);
		auto nullBits = BitArray(nullBytes);

        auto result = DbRowValue(fields.length);
        size_t i;
        foreach (field; fields)
        {
            if (nullBits[i])
                result[i++].nullify();
            else
                result[i++] = readValue(command, reader, field);
        }
        return result;
    }

    @property final FbConnection connection() nothrow pure @safe
    {
        return _connection;
    }

    @property final int serverMinType() const nothrow pure @nogc @safe
    {
        return _serverMinType.inited ? _serverMinType : 0;
    }

    @property final int serverVersion() const nothrow pure @nogc @safe
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

    final bool canCompressConnection() nothrow @safe
    {
        if (!_serverVersion.inited || !_serverMinType.inited)
            return false;

        if (serverVersion < FbIsc.protocol_version13)
            return false;

        if ((serverMinType & FbIsc.ptype_compress_flag) == 0)
			return false;

        return connection.fbConnectionStringBuilder.compress;
    }

    final bool canCryptedConnection() nothrow @safe
    {
        if (!_serverVersion.inited)
            return false;

        if (serverVersion < FbIsc.protocol_version13)
            return false;

        return _auth !is null && getCryptedConnectionCode() != FbIsc.connect_crypt_disabled;
    }

    final void clearServerInfo(Flag!"includeAuth" includeAuth)
    {
        _serverMinType.reset();
        _serverVersion.reset();

        if (includeAuth)
        {
            _serverAuthKey = null;
            _authData = null;
            _auth = null;
        }
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

        auto authenticationResponse = readGenericResponse();
        _serverAuthKey = authenticationResponse.data;
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
                _auth = new FbAuthSrp();

                writer.writeChars(FbIsc.CNCT_login, useCSB.userName);
                writer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                writer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                writer.writeMultiParts(FbIsc.CNCT_specific_data, _auth.publicKey());
                writer.writeInt32(FbIsc.CNCT_client_crypt, hostToNetworkOrder!int(getCryptedConnectionCode()));

                version (TraceFunction) dgFunctionTrace("specificData=", _auth.publicKey());

                break;

            case DbIntegratedSecurityConnection.sspi:
            case DbIntegratedSecurityConnection.trusted:
                goto case DbIntegratedSecurityConnection.legacy; //todo remove after testing
                /* todo
                _auth = new FbAuthSspi();

                buffer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                buffer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                buffer.writeMultiParts(FbIsc.CNCT_specific_data, _auth.publicKey());
                //var specificData = sspi.InitializeClientSecurity();
                break;
                */

            case DbIntegratedSecurityConnection.legacy:
                _auth = new FbAuthLegacy();

                writer.writeChars(FbIsc.CNCT_login, useCSB.userName);
                writer.writeChars(FbIsc.CNCT_plugin_name, _auth.name);
                writer.writeChars(FbIsc.CNCT_plugin_list, _auth.name);
                break;
        }

        auto result = writer.peekBytes();

        version (TraceFunction) dgFunctionTrace("end=", dgToString(result));

        return result;
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_auth !is null)
        {
            _auth.disposal(disposing);
            _auth = null;
        }
        _authData[] = 0;
        _serverAuthKey[] = 0;
        _connection = null;
        _serverMinType.reset();
        _serverVersion.reset();
    }

    final int getCryptedConnectionCode() nothrow @safe
    {
        auto useCSB = connection.fbConnectionStringBuilder;

        // For these securities, no supported encryption regardless of encrypt setting
        switch (useCSB.integratedSecurity)
        {
            case DbIntegratedSecurityConnection.sspi:
            case DbIntegratedSecurityConnection.trusted:
            case DbIntegratedSecurityConnection.legacy:
                return FbIsc.connect_crypt_disabled;
            default:
                break;
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

    final FbIscTrustedAuthenticationResponse readTrustedAuthenticationResponseImpl(ref FbXdrReader reader)
    {
        auto rData = reader.readBytes().dup;

        return FbIscTrustedAuthenticationResponse(rData);
    }

    final void writeCommandInfo(FbCommand command, scope const(ubyte)[] items, uint32 resultBufferLength)
    {
        version (TraceFunction) dgFunctionTrace();

        auto writer = FbXdrWriter(connection);
		writer.writeOperation(FbIsc.op_info_sql);
		writer.writeHandle(command.fbHandle);
		writer.writeInt32(0);
		writer.writeBytes(items);
		writer.writeInt32(resultBufferLength);
        writer.flush();
    }

private:
    FbAuth _auth;
    ubyte[] _authData;
    ubyte[] _serverAuthKey;
    FbConnection _connection;
    InitializedValue!int _serverMinType;
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

// Codes only support v13 and above
immutable FbProtocolInfo[] describeProtocolItems = [
    //FbProtocolInfo(FbIsc.protocol_version10, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, FbIsc.ptype_batch_send, 1),
    //FbProtocolInfo(FbIsc.protocol_version11, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, FbIsc.ptype_batch_send, 2),
    //FbProtocolInfo(FbIsc.protocol_version12, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, FbIsc.ptype_batch_send, 3),
    FbProtocolInfo(FbIsc.protocol_version13, FbIsc.connect_generic_achitecture_client, FbIsc.ptype_rpc, FbIsc.ptype_batch_send, 4)
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

void describeValue(return ref FbXdrWriter writer, DbNamedColumn column, DbValue value) @safe
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
        case DbType.decimal:
            writer.writeDecimal(value.get!Decimal(), column.baseType);
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


/*
 * Returns:
 *  false if truncate otherwise true
 */
bool parseBindInfo(const(ubyte)[] data, ref FbIscBindInfo[] bindResult,
    ref ptrdiff_t previousBindIndex, ref ptrdiff_t previousFieldIndex) @safe
{
    version (TraceFunction) dgFunctionTrace("data.length=", data.length);

    size_t posData;
    ptrdiff_t fieldIndex = previousFieldIndex;
    ptrdiff_t bindIndex = -1; // Always start with unknown value until isc_info_sql_select or isc_info_sql_bind

    size_t checkFieldIndex(ubyte typ) @safe
    {
        if (fieldIndex < 0)
        {
            auto msg = format(DbMessage.eInvalidSQLDAFieldIndex, typ, fieldIndex);
            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
        }
        return fieldIndex;
    }

    size_t checkBindIndex(ubyte typ) @safe
    {
        if (bindIndex < 0)
        {
            auto msg = format(DbMessage.eInvalidSQLDAIndex, typ);
            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
        }
        return bindIndex;
    }

	while (posData + 2 < data.length && data[posData] != FbIsc.isc_info_end)
	{
        while (posData + 2 < data.length)
        {
            const typ = data[posData++];
            if (typ == FbIsc.isc_info_sql_describe_end)
                break;

		    switch (typ)
		    {
			    case FbIsc.isc_info_sql_select:
			    case FbIsc.isc_info_sql_bind:
                    if (bindIndex == -1)
                        bindIndex = previousBindIndex;
                    bindIndex++;

			        if (data[posData++] == FbIsc.isc_info_truncated)
                    {
                        fieldIndex = 0; // Reset for new block
                        goto case FbIsc.isc_info_truncated;
                    }

			        const uint len = parseInt32!true(data, posData, 2, typ);

                    const uint fieldLen = parseInt32!true(data, posData, len, typ);

                    if (bindIndex == bindResult.length)
                    {
                        bindResult ~= FbIscBindInfo(fieldLen);
                        bindResult[bindIndex].selectOrBind = typ;

                        if (fieldLen == 0)
                            goto doneItem;
                    }

			        break;

			    case FbIsc.isc_info_sql_sqlda_seq:
			        const uint len = parseInt32!true(data, posData, 2, typ);

			        fieldIndex = parseInt32!true(data, posData, len, typ) - 1;

                    if (checkFieldIndex(typ) >= bindResult[checkBindIndex(typ)].length)
                    {
                        auto msg = format(DbMessage.eInvalidSQLDAFieldIndex, typ, fieldIndex);
                        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
                    }

			        break;

			    case FbIsc.isc_info_sql_type:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto dataType = parseInt32!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).type = dataType;
			        break;

			    case FbIsc.isc_info_sql_sub_type:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto dataSubType = parseInt32!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).subType = dataSubType;
			        break;

			    case FbIsc.isc_info_sql_scale:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto numericScale = parseInt32!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).numericScale = numericScale;
			        break;

			    case FbIsc.isc_info_sql_length:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto dataSize = parseInt32!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).size = dataSize;
			        break;

			    case FbIsc.isc_info_sql_field:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto fieldName = parseString!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).name = fieldName;
			        break;

			    case FbIsc.isc_info_sql_relation:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto tableName = parseString!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).tableName = tableName;
			        break;

			    case FbIsc.isc_info_sql_owner:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto owner = parseString!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).owner = owner;
			        break;

			    case FbIsc.isc_info_sql_alias:
			        const uint len = parseInt32!true(data, posData, 2, typ);
                    auto aliasName = parseString!true(data, posData, len, typ);

			        bindResult[checkBindIndex(typ)].field(checkFieldIndex(typ)).aliasName = aliasName;
			        break;

                case FbIsc.isc_info_truncated:
                    previousBindIndex = bindIndex;
                    previousFieldIndex = fieldIndex;
                    return false;

			    default:
                    auto msg = format(DbMessage.eInvalidSQLDAType, typ);
                    throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
		    }
        }

        doneItem:
    }

    version (TraceFunction)
    {
        dgFunctionTrace("rowDescs.length=", bindResult.length);
        foreach (i, ref desc; bindResult)
        {
            dgFunctionTrace("desc=", i, ", count=", desc.length, ", selectOrBind=", desc.selectOrBind);
            foreach (ref field; desc.fields)
            {
                dgFunctionTrace("field-name=", field.name,
                    ", type=", field.type, ", subtype=", field.subType,
                    ", numericScale=", field.numericScale, ", size=", field.size,
                    ", tableName=", field.tableName, ", field.aliasName=", field.aliasName);
            }
        }
    }

    return true;
}

unittest // parseBindInfo
{
    import pham.utl.utltest;
    dgWriteln("unittest db.fbprotocol.parseBindInfo");

    FbIscBindInfo[] bindResult;
    ptrdiff_t previousBindIndex = -1;
    ptrdiff_t previousFieldIndex;
    auto info = bytesFromHexs("040704000D000000090400010000000B0400F00100000C0400000000000E0400040000000D040000000000100900494E545F4649454C44110B00544553545F53454C454354130900494E545F4649454C4408090400020000000B0400F50100000C0400000000000E0400020000000D040000000000100E00534D414C4C494E545F4649454C44110B00544553545F53454C454354130E00534D414C4C494E545F4649454C4408090400030000000B0400E30100000C0400000000000E0400040000000D040000000000100B00464C4F41545F4649454C44110B00544553545F53454C454354130B00464C4F41545F4649454C4408090400040000000B0400E10100000C0400000000000E0400080000000D040000000000100C00444F55424C455F4649454C44110B00544553545F53454C454354130C00444F55424C455F4649454C4408090400050000000B0400450200000C0400010000000E0400080000000D0400FEFFFFFF100D004E554D455249435F4649454C44110B00544553545F53454C454354130D004E554D455249435F4649454C4408090400060000000B0400450200000C0400020000000E0400080000000D0400FEFFFFFF100D00444543494D414C5F4649454C44110B00544553545F53454C454354130D00444543494D414C5F4649454C4408090400070000000B04003B0200000C0400000000000E0400040000000D040000000000100A00444154455F4649454C44110B00544553545F53454C454354130A00444154455F4649454C4408090400080000000B0400310200000C0400000000000E0400040000000D040000000000100A0054494D455F4649454C44110B00544553545F53454C454354130A0054494D455F4649454C4408090400090000000B0400FF0100000C0400000000000E0400080000000D040000000000100F0054494D455354414D505F4649454C44110B00544553545F53454C454354130F0054494D455354414D505F4649454C44080904000A0000000B0400C50100000C0400040000000E0400280000000D040000000000100A00434841525F4649454C44110B00544553545F53454C454354130A00434841525F4649454C44080904000B0000000B0400C10100000C0400040000000E0400280000000D040000000000100D00564152434841525F4649454C44110B00544553545F53454C454354130D00564152434841525F4649454C44080904000C0000000B0400090200000C0400000000000E0400080000000D040000000000100A00424C4F425F4649454C44110B00544553545F53454C454354130A00424C4F425F4649454C44080904000D0000000B0400090200000C0400010000000E0400080000000D040004000000100A00544558545F4649454C44110B00544553545F53454C454354130A00544558545F4649454C4408050704000000000001");
    auto parsed = parseBindInfo(info, bindResult, previousBindIndex, previousFieldIndex);
    assert(parsed == true);
    assert(bindResult.length == 2);

    assert(bindResult[0].selectOrBind == FbIsc.isc_info_sql_select);
    assert(bindResult[0].length == 13);
    auto field = bindResult[0].field(0);
    assert(field.name == "INT_FIELD" && field.type == 496 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "INT_FIELD");
    field = bindResult[0].field(1);
    assert(field.name == "SMALLINT_FIELD" && field.type == 501 && field.subType == 0 && field.numericScale == 0 && field.size == 2 && field.tableName == "TEST_SELECT" && field.aliasName == "SMALLINT_FIELD");
    field = bindResult[0].field(2);
    assert(field.name == "FLOAT_FIELD" && field.type == 483 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "FLOAT_FIELD");
    field = bindResult[0].field(3);
    assert(field.name == "DOUBLE_FIELD" && field.type == 481 && field.subType == 0 && field.numericScale == 0 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "DOUBLE_FIELD");
    field = bindResult[0].field(4);
    assert(field.name == "NUMERIC_FIELD" && field.type == 581 && field.subType == 1 && field.numericScale == -2 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "NUMERIC_FIELD");
    field = bindResult[0].field(5);
    assert(field.name == "DECIMAL_FIELD" && field.type == 581 && field.subType == 2 && field.numericScale == -2 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "DECIMAL_FIELD");
    field = bindResult[0].field(6);
    assert(field.name == "DATE_FIELD" && field.type == 571 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "DATE_FIELD");
    field = bindResult[0].field(7);
    assert(field.name == "TIME_FIELD" && field.type == 561 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "TIME_FIELD");
    field = bindResult[0].field(8);
    assert(field.name == "TIMESTAMP_FIELD" && field.type == 511 && field.subType == 0 && field.numericScale == 0 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "TIMESTAMP_FIELD");
    field = bindResult[0].field(9);
    assert(field.name == "CHAR_FIELD" && field.type == 453 && field.subType == 4 && field.numericScale == 0 && field.size == 40 && field.tableName == "TEST_SELECT" && field.aliasName == "CHAR_FIELD");
    field = bindResult[0].field(10);
    assert(field.name == "VARCHAR_FIELD" && field.type == 449 && field.subType == 4 && field.numericScale == 0 && field.size == 40 && field.tableName == "TEST_SELECT" && field.aliasName == "VARCHAR_FIELD");
    field = bindResult[0].field(11);
    assert(field.name == "BLOB_FIELD" && field.type == 521 && field.subType == 0 && field.numericScale == 0 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "BLOB_FIELD");
    field = bindResult[0].field(12);
    assert(field.name == "TEXT_FIELD" && field.type == 521 && field.subType == 1 && field.numericScale == 4 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "TEXT_FIELD");

    assert(bindResult[1].selectOrBind == FbIsc.isc_info_sql_bind);
    assert(bindResult[1].length == 0);
}

unittest // parseBlobSizeInfo
{
    import pham.utl.utltest;
    dgWriteln("unittest db.fbprotocol.parseBlobSizeInfo");

    auto info = bytesFromHexs("05040004000000040400010000000604000400000001");
    auto parsedSize = parseBlobSizeInfo(info);
    assert(parsedSize.maxSegment == 4);
    assert(parsedSize.segmentCount == 1);
    assert(parsedSize.length == 4);
}
