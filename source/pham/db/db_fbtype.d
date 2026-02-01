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

module pham.db.db_fbtype;

import std.array : replace;
import std.conv : to;
import std.range.primitives : isOutputRange, put;
import std.traits : EnumMembers, Unqual, isIntegral;

debug(debug_pham_db_db_fbtype) import pham.db.db_debug;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_array_static : ShortStringBuffer;
import pham.utl.utl_enum_set : toName;
import pham.var.var_variant : Algebraic, VariantType;
import pham.db.db_convert : toIntegerSafe, toStringSafe;
import pham.db.db_message;
import pham.db.db_type;
import pham.db.db_util : toVersionString;
import pham.db.db_fbisc;
import pham.db.db_fbmessage;
import pham.db.db_fbexception;

@safe:

alias FbId = int64;
alias FbHandle = uint32;
alias FbOperation = int32;

enum fbDeferredProtocol = true;
static if (fbDeferredProtocol) enum fbCommandDeferredHandle = FbHandle(0xFFFF_FFFF);

enum fbNullIndicator = -1;

enum FbIscCommandType : int32
{
	none = 0,
	select = FbIsc.isc_info_sql_stmt_select,
	insert = FbIsc.isc_info_sql_stmt_insert,
	update = FbIsc.isc_info_sql_stmt_update,
	delete_ = FbIsc.isc_info_sql_stmt_delete,
	ddl = FbIsc.isc_info_sql_stmt_ddl,
	getSegment = FbIsc.isc_info_sql_stmt_get_segment,
	putSegment = FbIsc.isc_info_sql_stmt_put_segment,
	storedProcedure = FbIsc.isc_info_sql_stmt_exec_procedure,
	startTransaction = FbIsc.isc_info_sql_stmt_start_trans,
	commit = FbIsc.isc_info_sql_stmt_commit,
	rollback = FbIsc.isc_info_sql_stmt_rollback,
	selectForUpdate = FbIsc.isc_info_sql_stmt_select_for_upd,
	setGenerator = FbIsc.isc_info_sql_stmt_set_generator,
	savePoint = FbIsc.isc_info_sql_stmt_savepoint,
}

alias FbDefaultConnectionParameterValues = Dictionary!(string, DbConnectionParameterInfo);
static immutable FbDefaultConnectionParameterValues fbDefaultConnectionParameterValues;

static immutable string[] fbValidConnectionParameterNames = [
    // Primary
    DbConnectionParameterIdentifier.serverName,
    DbConnectionParameterIdentifier.serverPort,
    DbConnectionParameterIdentifier.databaseName,
    DbConnectionParameterIdentifier.userName,
    DbConnectionParameterIdentifier.userPassword,
    DbConnectionParameterIdentifier.roleName,
    DbConnectionParameterIdentifier.charset,
    DbConnectionParameterIdentifier.compress,
    DbConnectionParameterIdentifier.encrypt,
    DbConnectionParameterIdentifier.integratedSecurity,

    // Other
    DbConnectionParameterIdentifier.commandTimeout,
    DbConnectionParameterIdentifier.connectionTimeout,
    DbConnectionParameterIdentifier.fetchRecordCount,
    DbConnectionParameterIdentifier.packageSize,
    DbConnectionParameterIdentifier.pooling,
    DbConnectionParameterIdentifier.receiveTimeout,
    DbConnectionParameterIdentifier.sendTimeout,
    DbConnectionParameterIdentifier.socketBlocking,

    DbConnectionParameterIdentifier.fbCachePage,
    DbConnectionParameterIdentifier.fbCryptAlgorithm,
    DbConnectionParameterIdentifier.fbCryptKey,
    DbConnectionParameterIdentifier.fbDatabaseTrigger,
    DbConnectionParameterIdentifier.fbDialect,
    DbConnectionParameterIdentifier.fbDummyPacketInterval,
    DbConnectionParameterIdentifier.fbGarbageCollect,
    ];

static immutable DbTypeInfo[] fbNativeTypes = [
    {dbName:"BIGINT", dbType:DbType.int64, dbId:FbIscType.sql_int64, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"BLOB", dbType:DbType.blob, dbId:FbIscType.sql_blob, nativeName:"ubyte[]", nativeSize:DbTypeSize.blob, displaySize:DbTypeDisplaySize.blob},
    {dbName:"BLOB SUB_TYPE 0", dbType:DbType.blob, dbId:FbIscType.sql_blob, nativeName:"ubyte[]", nativeSize:DbTypeSize.blob, displaySize:DbTypeDisplaySize.blob},
    {dbName:"BLOB SUB_TYPE BINARY", dbType:DbType.blob, dbId:FbIscType.sql_blob, nativeName:"ubyte[]", nativeSize:DbTypeSize.blob, displaySize:DbTypeDisplaySize.blob},
    {dbName:"BLOB SUB_TYPE 1", dbType:DbType.text, dbId:FbIscType.sql_blob, nativeName:"char[]", nativeSize:DbTypeSize.text, displaySize:DbTypeDisplaySize.text},
    {dbName:"BLOB SUB_TYPE TEXT", dbType:DbType.text, dbId:FbIscType.sql_blob, nativeName:"char[]", nativeSize:DbTypeSize.text, displaySize:DbTypeDisplaySize.text},
    {dbName:"BOOLEAN", dbType:DbType.boolean, dbId:FbIscType.sql_boolean, nativeName:"bool", nativeSize:DbTypeSize.boolean, displaySize:DbTypeDisplaySize.boolean}, // fb3
    {dbName:"CHAR(?)", dbType:DbType.stringFixed, dbId:FbIscType.sql_text, nativeName:"string", nativeSize:DbTypeSize.stringFixed, displaySize:DbTypeDisplaySize.stringFixed}, //char[]
    {dbName:"DATE", dbType:DbType.date, dbId:FbIscType.sql_date, nativeName:"DbDate", nativeSize:DbTypeSize.date, displaySize:DbTypeDisplaySize.date},
    {dbName:"TIMESTAMP", dbType:DbType.datetime, dbId:FbIscType.sql_timestamp, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"DECFLOAT(16)", dbType:DbType.decimal64, dbId:FbIscType.sql_dec16, nativeName:"Decimal64", nativeSize:DbTypeSize.decimal64, displaySize:DbTypeDisplaySize.decimal64}, // fb4
    {dbName:"DECFLOAT(34)", dbType:DbType.decimal128, dbId:FbIscType.sql_dec34, nativeName:"Decimal128", nativeSize:DbTypeSize.decimal128, displaySize:DbTypeDisplaySize.decimal128}, // fb4
    {dbName:"DOUBLE PRECISION", dbType:DbType.float64, dbId:FbIscType.sql_double, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"DOUBLE PRECISION", dbType:DbType.float64, dbId:FbIscType.sql_d_float, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"FLOAT", dbType:DbType.float32, dbId:FbIscType.sql_float, nativeName:"float32", nativeSize:DbTypeSize.float32, displaySize:DbTypeDisplaySize.float32},
    {dbName:"INT128", dbType:DbType.int128, dbId:FbIscType.sql_int128, nativeName:"BigInteger", nativeSize:DbTypeSize.int128, displaySize:DbTypeDisplaySize.int128}, // fb4
    {dbName:"INTEGER", dbType:DbType.int32, dbId:FbIscType.sql_long, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"QUAD", dbType:DbType.int64, dbId:FbIscType.sql_quad, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"SMALLINT", dbType:DbType.int16, dbId:FbIscType.sql_short, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"TIME", dbType:DbType.time, dbId:FbIscType.sql_time, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},
    {dbName:"TIME WITH OFFSET TIMEZONE", dbType:DbType.timeTZ, dbId:FbIscType.sql_time_tz_ex, nativeName:"DbTime", nativeSize:DbTypeSize.timeTZ, displaySize:DbTypeDisplaySize.timeTZ}, // fb4
    {dbName:"TIME WITH TIMEZONE", dbType:DbType.timeTZ, dbId:FbIscType.sql_time_tz, nativeName:"DbTime", nativeSize:DbTypeSize.timeTZ, displaySize:DbTypeDisplaySize.timeTZ}, // fb4
    {dbName:"TIMESTAMP WITH OFFSET TIMEZONE", dbType:DbType.datetimeTZ, dbId:FbIscType.sql_timestamp_tz_ex, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetimeTZ, displaySize:DbTypeDisplaySize.datetimeTZ}, // fb4
    {dbName:"TIMESTAMP WITH TIMEZONE", dbType:DbType.datetimeTZ, dbId:FbIscType.sql_timestamp_tz, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetimeTZ, displaySize:DbTypeDisplaySize.datetimeTZ}, // fb4
    {dbName:"VARCHAR(?)", dbType:DbType.stringVary, dbId:FbIscType.sql_varying, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"ARRAY[?,?]", dbType:DbType.array, dbId:FbIscType.sql_array, nativeName:"?[?]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"", dbType:DbType.unknown, dbId:FbIscType.sql_null, nativeName:"null", nativeSize:0, displaySize:4},
    ];

alias FbDbIdToDbTypeInfos = Dictionary!(int32, immutable(DbTypeInfo)*);
static immutable FbDbIdToDbTypeInfos fbDbIdToDbTypeInfos;

struct FbCommandBatchResult
{
@safe:

public:
    this(DbRecordsAffected recordsAffected, FbException exception, bool isError) nothrow pure
    {
        this.recordsAffected = recordsAffected;
        this.exception = exception;
        this.isError = isError;
    }

    bool opCast(C: bool)() const @nogc nothrow pure
    {
        return !isError;
    }

    /**
     * Create FbCommandBatchResult as error
     */
    pragma(inline, true)
    static typeof(this) error(DbRecordsAffected recordsAffected, FbException exception) nothrow pure
    {
        return typeof(this)(recordsAffected, exception, true);
    }

    /**
     * Create FbCommandBatchResult without error
     */
    pragma(inline, true)
    static typeof(this) ok(DbRecordsAffected recordsAffected) nothrow pure
    {
        return typeof(this)(recordsAffected, null, false);
    }

    pragma(inline, true)
    @property isOK() const nothrow @nogc pure
    {
        return !isError;
    }

public:
    DbRecordsAffected recordsAffected;
    FbException exception;
    bool isError;
}

struct FbCommandPlanInfo
{
@safe:

public:
    enum Kind : ubyte
    {
        noData,
        empty,
        truncated,
        ok,
    }

public:
    this(Kind kind, string plan) nothrow pure
    {
        this.kind = kind;
        this.plan = plan;
    }

    static string parse(scope const(ubyte)[] data, FbIsc describeMode)
    {
        return parsePlan(data, describeMode);
    }

public:
    string plan;
    Kind kind;
}

struct FbCreateDatabaseInfo
{
@safe:

public:
    static immutable int[] knownPageSizes = [4_096, 8_192, 16_384, 32_768];
    static int toKnownPageSize(const(int) pageSize) @nogc nothrow pure
    {

        // Current max if not provided
        if (pageSize <= 0)
            return knownPageSizes[$ - 1];

        foreach (n; knownPageSizes)
        {
            if (pageSize <= n)
                return n;
        }

        // Future value not known
        return pageSize;
    }

public:
    string fileName;
    string defaultCharacterSet;
    string defaultCollation;
    string ownerName;
    string ownerPassword;
    string roleName;
    int pageSize;
    bool forcedWrite;
    bool overwrite;
}

struct FbProtocolInfo
{
nothrow @safe:

public:
    int32 version_;
    int32 achitectureClient;
    int32 minType;
    int32 maxType;
    int32 priority;
}

struct FbIscAcceptDataResponse
{
nothrow @safe:

public:
    this(int32 version_, int32 architecture, int32 acceptType, const(ubyte)[] authData,
        const(char)[] authName, int32 authenticated, const(ubyte)[] authKey)
    {
        this.version_ = version_;
        this.architecture = architecture;
        this.acceptType = acceptType;
        this.authData = authData;
        this.authName = authName;
        this.authenticated = authenticated;
        this.authKey = authKey;
    }

    void reset()
    {
        authData = authKey = null;
        authName = null;
        acceptType = architecture = authenticated = version_ = 0;
    }

    @property bool canCompress() const
    {
        return (acceptType & FbIsc.ptype_compress_flag) != 0;
    }

    @property bool isAuthenticated() const
    {
        return authenticated == 1;
    }

public:
    const(ubyte)[] authData;
    const(ubyte)[] authKey;
    const(char)[] authName;
    int32 acceptType;
    int32 architecture;
    int32 authenticated;
    int32 version_;
}

struct FbIscAcceptResponse
{
nothrow @safe:

public:
    this(int32 version_, int32 architecture, int32 acceptType)
    {
        this.version_ = version_;
        this.architecture = architecture;
        this.acceptType = acceptType;
    }

    bool canCompress() const
    {
        return (acceptType & FbIsc.ptype_compress_flag) != 0;
    }

    static int32 normalizeVersion(const(int32) version_) pure
    {
        const result = version_ < 0
		    ? FbIsc.protocol_flag | cast(ushort)(version_ & FbIsc.protocol_mask)
            : version_;

        debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "(version_=", version_, ", result=", result, ")");

        return result;
    }

    void reset()
    {
        acceptType = architecture = version_ = 0;
    }

public:
    int32 acceptType;
    int32 architecture;
    int32 version_;
}

struct FbIscArrayDescriptor
{
nothrow @safe:

public:
    uint32 calculateElements() const pure
    {
		uint32 result = 1;
		foreach (ref bound; bounds)
		{
			result *= bound.upper - bound.lower + 1;
		}
        return result;
    }

	uint32 calculateSliceLength(uint32 elements = 0) const pure
	{
        if (elements == 0)
            elements = calculateElements();
		uint32 result = elements * columnInfo.size;
	    if (columnInfo.fbType() == FbIscType.sql_varying)
            result += (elements * 2);
        return result;
	}

public:
    FbIscColumnInfo columnInfo;
    DbArrayBound[] bounds;
    int16 blrType;
}

struct FbIscArrayGetResponse
{
nothrow @safe:

public:
    ubyte[] data;
    int32 elements;
    int32 sliceLength;
}

struct FbIscBindInfo
{
@safe:

public:
    this(size_t columnCount) nothrow pure
    {
        this._columns = new FbIscColumnInfo[columnCount];
    }

    bool opCast(To: bool)() const nothrow
    {
        return selectOrBind != 0 || length != 0;
    }

    /*
     * Returns:
     *  false if truncate otherwise true
     */
    static bool parse(const(ubyte)[] payload, ref FbIscBindInfo[] bindResults,
        ref ptrdiff_t previousBindIndex, ref ptrdiff_t previousColumnIndex)
    {
        debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "(payload.length=", payload.length, ")");

        size_t posData;
        ptrdiff_t columnIndex = previousColumnIndex;
        ptrdiff_t bindIndex = -1; // Always start with unknown value until isc_info_sql_select or isc_info_sql_bind

        size_t checkColumnIndex(ubyte typ) @safe
        {
            if (columnIndex < 0)
            {
                auto msg = DbMessage.eInvalidSQLDAColumnIndex.fmtMessage(typ, columnIndex);
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
            }
            return columnIndex;
        }

        size_t checkBindIndex(ubyte typ) @safe
        {
            if (bindIndex < 0)
            {
                auto msg = DbMessage.eInvalidSQLDAIndex.fmtMessage(typ);
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
            }
            return bindIndex;
        }

	    while (posData + 2 < payload.length && payload[posData] != FbIsc.isc_info_end)
	    {
            while (posData + 2 < payload.length)
            {
                const typ = payload[posData++];
                if (typ == FbIsc.isc_info_sql_describe_end)
                    break;

		        switch (typ)
		        {
			        case FbIsc.isc_info_sql_select:
			        case FbIsc.isc_info_sql_bind:
                        if (bindIndex == -1)
                            bindIndex = previousBindIndex;
                        bindIndex++;

			            if (payload[posData++] == FbIsc.isc_info_truncated)
                        {
                            columnIndex = 0; // Reset for new block
                            goto case FbIsc.isc_info_truncated;
                        }

                        const columnLen = parseInteger!uint32(payload, posData, typ);

                        if (bindIndex == bindResults.length)
                        {
                            bindResults ~= FbIscBindInfo(columnLen);
                            bindResults[bindIndex].selectOrBind = typ;
                            if (columnLen == 0)
                                goto doneItem;
                        }

			            break;

			        case FbIsc.isc_info_sql_sqlda_seq:
			            columnIndex = parseInteger!int32(payload, posData, typ) - 1;

                        if (checkColumnIndex(typ) >= bindResults[checkBindIndex(typ)].length)
                        {
                            auto msg = DbMessage.eInvalidSQLDAColumnIndex.fmtMessage(typ, columnIndex);
                            throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
                        }

			            break;

			        case FbIsc.isc_info_sql_type:
                        auto dataType = parseInteger!int32(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).type = dataType;
			            break;

			        case FbIsc.isc_info_sql_sub_type:
                        auto dataSubType = parseInteger!int32(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).subType = dataSubType;
			            break;

			        case FbIsc.isc_info_sql_scale:
                        auto numericScale = cast(int16)parseInteger!int32(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).numericScale = numericScale;
			            break;

			        case FbIsc.isc_info_sql_length:
                        auto dataSize = parseInteger!int32(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).size = dataSize;
			            break;

			        case FbIsc.isc_info_sql_field:
                        auto columnName = parseString(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).name = columnName;
			            break;

			        case FbIsc.isc_info_sql_relation:
			            auto tableName = parseString(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).tableName = tableName;
			            break;

			        case FbIsc.isc_info_sql_owner:
                        auto owner = parseString(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).owner = owner;
			            break;

			        case FbIsc.isc_info_sql_alias:
                        auto aliasName = parseString(payload, posData, typ);
			            bindResults[checkBindIndex(typ)].column(checkColumnIndex(typ)).aliasName = aliasName;
			            break;

                    case FbIsc.isc_info_truncated:
                        previousBindIndex = bindIndex;
                        previousColumnIndex = columnIndex;
                        return false;

			        default:
                        auto msg = DbMessage.eInvalidSQLDAType.fmtMessage(typ);
                        throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
		        }
            }

            doneItem:
        }

        debug(debug_pham_db_db_fbtype)
        {
            debug writeln("\tbindResults.length=", bindResults.length);
            foreach (i, ref desc; bindResults)
                debug writeln("\t", desc.traceString(i));
        }

        return true;
    }

    ref typeof(this) reset() nothrow return
    {
        selectOrBind = 0;
        _columns = null;
        return this;
    }

    string traceString(size_t index) const nothrow @trusted
    {
        import std.conv : to;
        import pham.utl.utl_array_append : Appender;

        auto result = Appender!string(1_000);
        result.put("bindResult=");
        result.put(index.to!string);
        result.put(", length=");
        result.put(length.to!string);
        result.put(", selectOrBind=");
        result.put(selectOrBind.to!string);
        foreach (ref column; _columns)
        {
            result.put('\n');
            result.put(column.traceString());
        }
        return result[];
    }

    @property ref FbIscColumnInfo column(size_t index) nothrow return
    {
        return _columns[index];
    }

    @property FbIscColumnInfo[] columns() nothrow return
    {
        return _columns;
    }

    @property size_t length() const nothrow
    {
        return _columns.length;
    }

public:
    int32 selectOrBind; // FbIsc.isc_info_sql_select or FbIsc.isc_info_sql_bind

private:
    FbIscColumnInfo[] _columns;
}

struct FbIscBlobSize
{
@safe:

public:
    this(int32 maxSegment, int32 segmentCount, int32 length, int32 type) nothrow pure
    {
        this.maxSegment = maxSegment;
        this.segmentCount = segmentCount;
        this.length = length;
        this.type = type;
    }

    static typeof(this) parse(scope const(ubyte)[] data)
    {
        return parseBlobSize(data);
    }

    ref typeof(this) reset() nothrow pure return
    {
        maxSegment = segmentCount = length = type = 0;
        return this;
    }

    @property bool isInitialized() const nothrow pure
    {
        return maxSegment != 0 || segmentCount != 0 || length != 0 || type != 0;
    }

public:
    int32 maxSegment;
    int32 segmentCount;
    int32 length;
    int32 type;
}

struct FbIscBlrDescriptor
{
nothrow @safe:

public:
	void addSize(const(uint32) alignment, const(uint32) addingSize) @nogc pure
	{
        if (alignment)
            this.size = (this.size + alignment - 1) & ~(alignment - 1);
        this.size += addingSize;
	}

public
    ubyte[] data;
    uint32 size;
}

struct FbIscColumnInfo
{
nothrow @safe:

public:
    bool opCast(C: bool)() const @nogc pure
    {
        return type != 0 && name.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    FbIscColumnInfo opCast(T)() const
    if (is(Unqual!T == FbIscColumnInfo))
    {
        return this;
    }

    DbBaseTypeInfo baseType() const @nogc pure
    {
        return DbBaseTypeInfo(fbType(type), subType, size, numericDigits, numericScale);
    }

    pragma(inline, true)
    int32 baseTypeId() const @nogc pure
    {
        return type & ~0x1; // Exclude allow null indicator
    }

    pragma(inline, true)
    static int32 baseTypeId(int32 type) @nogc pure
    {
        return type & ~0x1; // Exclude allow null indicator
    }

	static FbIscType blrTypeToFbType(int32 blrType) @nogc pure
	{
		switch (blrType)
		{
			case FbBlrType.blr_short:
				return FbIscType.sql_short;
			case FbBlrType.blr_long:
				return FbIscType.sql_long;
			case FbBlrType.blr_quad:
				return FbIscType.sql_quad;
			case FbBlrType.blr_float:
				return FbIscType.sql_float;
			case FbBlrType.blr_d_float:
				return FbIscType.sql_d_float;
			case FbBlrType.blr_date:
				return FbIscType.sql_date;
			case FbBlrType.blr_time:
				return FbIscType.sql_time;
			case FbBlrType.blr_text:
			case FbBlrType.blr_text2:
			case FbBlrType.blr_cstring:
			case FbBlrType.blr_cstring2:
				return FbIscType.sql_text;
			case FbBlrType.blr_int64:
			case FbBlrType.blr_blob_id:
				return FbIscType.sql_int64;
			case FbBlrType.blr_blob2:
			case FbBlrType.blr_blob:
				return FbIscType.sql_blob;
			case FbBlrType.blr_bool:
				return FbIscType.sql_boolean;
			case FbBlrType.blr_dec16:
				return FbIscType.sql_dec16;
			case FbBlrType.blr_dec34:
				return FbIscType.sql_dec34;
			case FbBlrType.blr_int128:
				return FbIscType.sql_int128;
			case FbBlrType.blr_double:
				return FbIscType.sql_double;
            case FbBlrType.blr_time_tz:
				return FbIscType.sql_time_tz;
	        case FbBlrType.blr_timestamp_tz:
				return FbIscType.sql_timestamp_tz;
	        case FbBlrType.blr_ex_time_tz:
				return FbIscType.sql_time_tz_ex;
	        case FbBlrType.blr_ex_timestamp_tz:
				return FbIscType.sql_timestamp_tz_ex;
			case FbBlrType.blr_timestamp:
				return FbIscType.sql_timestamp;
			case FbBlrType.blr_varying:
			case FbBlrType.blr_varying2:
				return FbIscType.sql_varying;
			default:
                return FbIscType.sql_null; // Unknown
		}
	}

    void reset() pure
    {
        aliasName = null;
        name = null;
        owner = null;
        tableName = null;
        numericScale = 0;
        size = 0;
        subType = 0;
        type = 0;
    }

    DbType dbType() const @nogc pure
    {
        const t = fbType;

        if (t == FbIscType.sql_blob)
        {
            if (subType == textBlob)
                return DbType.text;
            else if (subType == binaryBlob)
                return DbType.blob;
        }

        if (numericScale != 0)
        {
            switch (t) with (FbIscType)
            {
		        case sql_short:
		        case sql_long:
                    return DbType.decimal32;
		        case sql_quad:
		        case sql_int64:
                    return DbType.decimal64;
                default:
                    break;
            }
        }

        if (auto e = t in fbDbIdToDbTypeInfos)
            return (*e).dbType;

        return DbType.unknown;
    }

    int32 dbTypeSize() const @nogc pure
    {
        if (size > 0)
            return size;

        const t = fbType;
        if (t != 0)
        {
            if (auto e = t in fbDbIdToDbTypeInfos)
            {
                const ns = (*e).nativeSize;
                if (ns > 0)
                    return ns;
            }
        }

        if (auto e = dbType() in dbTypeToDbTypeInfos)
        {
            const ns = (*e).nativeSize;
            if (ns > 0)
                return ns;
        }

        return dynamicTypeSize;
    }

    int32 dbTypeDisplaySize() const @nogc pure
    {
        const t = fbType;
        if (t != 0)
        {
            if (auto e = t in fbDbIdToDbTypeInfos)
            {
                const ns = (*e).displaySize;
                if (ns > 0)
                    return ns;
            }
        }

        if (auto e = dbType() in dbTypeToDbTypeInfos)
        {
            const ns = (*e).displaySize;
            if (ns > 0)
                return ns;
        }

        return dynamicTypeSize;
    }

    pragma(inline, true)
    FbIscType fbType() const @nogc pure
    {
        return cast(FbIscType)baseTypeId();
    }

    pragma(inline, true)
    static FbIscType fbType(int32 type) @nogc pure
    {
        return cast(FbIscType)baseTypeId(type);
    }

    static FbBlrType fbTypeToBlrType(const(FbIscType) fbType) @nogc pure
    {
	    final switch (fbType)
	    {
		    case FbIscType.sql_varying:
			    return FbBlrType.blr_varying2; // FbBlrType.blr_varying;
		    case FbIscType.sql_text:
			    return FbBlrType.blr_text2; // FbBlrType.blr_text;
		    case FbIscType.sql_double:
			    return FbBlrType.blr_double;
		    case FbIscType.sql_float:
			    return FbBlrType.blr_float;
		    case FbIscType.sql_long:
			    return FbBlrType.blr_long;
		    case FbIscType.sql_short:
			    return FbBlrType.blr_short;
		    case FbIscType.sql_timestamp:
			    return FbBlrType.blr_timestamp;
		    case FbIscType.sql_blob:
                return FbBlrType.blr_blob2; // FbBlrType.blr_quad;
		    case FbIscType.sql_d_float:
			    return FbBlrType.blr_d_float;
		    case FbIscType.sql_array:
			    return FbBlrType.blr_quad;
		    case FbIscType.sql_quad:
			    return FbBlrType.blr_quad;
		    case FbIscType.sql_time:
			    return FbBlrType.blr_time;
		    case FbIscType.sql_date:
			    return FbBlrType.blr_date;
		    case FbIscType.sql_int64:
			    return FbBlrType.blr_int64;
		    case FbIscType.sql_int128:
			    return FbBlrType.blr_int128;
		    case FbIscType.sql_timestamp_tz:
			    return FbBlrType.blr_timestamp_tz;
		    case FbIscType.sql_timestamp_tz_ex:
			    return FbBlrType.blr_ex_timestamp_tz;
		    case FbIscType.sql_time_tz:
			    return FbBlrType.blr_time_tz;
		    case FbIscType.sql_time_tz_ex:
			    return FbBlrType.blr_ex_time_tz;
		    /*
            case FbIscType.SQL_DEC_FIXED:
			    return FbBlrType.blr_int128;
            */
		    case FbIscType.sql_dec16:
			    return FbBlrType.blr_dec16;
		    case FbIscType.sql_dec34:
			    return FbBlrType.blr_dec34;
		    case FbIscType.sql_boolean:
			    return FbBlrType.blr_bool;
		    case FbIscType.sql_null:
			    return FbBlrType.blr_text;
	    }
    }

    string fbTypeName() const pure
    {
        if (auto e = fbType in fbDbIdToDbTypeInfos)
            return (*e).nativeName;
        else
            return null;
    }

    int32 fbTypeSize() const @nogc pure
    {
        if (size > 0)
            return size;

        if (auto e = fbType in fbDbIdToDbTypeInfos)
        {
            const ns = (*e).nativeSize;
            if (ns > 0)
                return ns;
        }

        return dynamicTypeSize;
    }

    static DbColumnIdType isValueIdType(int32 type, int32 iscSubType) @nogc pure
    {
        const t = fbType(type);
        return t == FbIscType.sql_blob
            ? (iscSubType != textBlob ? DbColumnIdType.blob : DbColumnIdType.clob)
            : (t == FbIscType.sql_array ? DbColumnIdType.array : DbColumnIdType.no);
    }

    string traceString() const
    {
        import std.conv : to;
        import pham.utl.utl_enum_set : toName;

        return "aliasName=" ~ aliasName.to!string()
            ~ ", name=" ~ name.to!string()
            ~ ", tableName=" ~ tableName.to!string()
            ~ ", dbType=" ~ dbType.toName!DbType()
            ~ ", type=" ~ type.to!string()
            ~ ", subType=" ~ subType.to!string()
            ~ ", size=" ~ size.to!string()
            ~ ", numericScale=" ~ numericScale.to!string()
            ~ ", owner=" ~ owner.to!string();
    }

    const(char)[] useName() const pure
    {
        return aliasName.length ? aliasName : name;
    }

    pragma(inline, true)
    @property bool allowNull() const @nogc pure
    {
        return (type & 0x1) != 0;
    }

    @property ref typeof(this) allowNull(bool value) @nogc pure return
    {
        if (value)
            type |= 0x1;
        else
            type ^= 0x1;
        return this;
    }

    pragma(inline, true)
    @property bool hasNumericScale() const @nogc pure
    {
        const t = fbType;
	    return (numericScale != 0) &&
            (t == FbIscType.sql_short ||
             t == FbIscType.sql_long ||
             t == FbIscType.sql_quad ||
             t == FbIscType.sql_int64 ||
             //t == FbIscType.sql_dec_fixed ||
             t == FbIscType.sql_dec16 ||
             t == FbIscType.sql_dec34
            );
    }

    @property int16 numericDigits() const @nogc pure
    {
        if (!hasNumericScale)
            return 0;

        switch (fbType)
        {
            case FbIscType.sql_quad:
            case FbIscType.sql_int64:
                return 19;
            case FbIscType.sql_long:
                return 10;
            case FbIscType.sql_short:
                return 5;
            //case FbIscType.sql_dec_fixed:
            case FbIscType.sql_dec34:
                return 34;
            case FbIscType.sql_dec16:
                return 16;
            default:
                assert(0, "Need to handle all cases as in hasNumericScale");
        }
    }

public:
    enum binaryBlob = 0;
    enum textBlob = 1;

    const(char)[] aliasName;
    const(char)[] name;
    const(char)[] owner;
    const(char)[] tableName;
    int32 size;
    int32 subType;
    int32 type;
    int16 numericScale;
}

struct FbIscCommandBatchStatus
{
nothrow @safe:

public:
    int32 recIndex;
    FbIscStatues statues;
}

struct FbIscCommandBatchExecuteResponse
{
@safe:

public:
    FbCommandBatchResult[] toCommandBatchResult()
    {
        // Build hash-set for faster lookup
        int32[int32] errorIndexes;
        foreach (i, e; errorIndexesData)
            errorIndexes[e] = cast(int32)i;

        int32[int32] errorStatues;
        foreach (i, ref FbIscCommandBatchStatus e; errorStatuesData)
        {
            errorStatues[e.recIndex] = cast(int32)i;
        }

        // Construct result
        auto result =  new FbCommandBatchResult[](recCount);
        foreach (i; 0..recCount)
        {
			auto recordsAffected = i < recordsAffectedData.length
				? DbRecordsAffected(recordsAffectedData[i])
				: DbRecordsAffected.init;

            const ei = errorStatues.get(i, -1);
			if (ei >= 0)
			{
				result[i] = FbCommandBatchResult.error(recordsAffected, new FbException(errorStatuesData[ei].statues));
                continue;
			}

            if (errorIndexes.get(i, -1) >= 0)
			{
                result[i] = FbCommandBatchResult.error(recordsAffected, null);
                continue;
			}

			result[i] = FbCommandBatchResult.ok(recordsAffected);
        }

        return result;
    }

public:
    FbHandle statementHandle;
    int32 recCount;
    int32 recordsAffectedCount;
    int32 errorStatuesCount;
    int32 errorIndexesCount;
    int32[] recordsAffectedData;
    FbIscCommandBatchStatus[] errorStatuesData;
    int32[] errorIndexesData;
}

alias FbIscCondAcceptResponse = FbIscAcceptDataResponse;

struct FbIscContAuthResponse
{
nothrow @safe:

public:
    this(const(ubyte)[] data, const(char)[] name, const(ubyte)[] list, const(ubyte)[] key) pure
    {
        this.data = data;
        this.name = name;
        this.list = list;
        this.key = key;
    }

    void reset()
    {
        data = key = list = null;
        name = null;
    }

public:
    const(ubyte)[] data;
    const(ubyte)[] key;
    const(ubyte)[] list;
    const(char)[] name;
}

struct FbIscCryptKeyCallbackResponse
{
nothrow @safe:

public:
    this(const(ubyte)[] data, int32 size) pure
    {
        this.data = data;
        this.size = size;
    }

    void reset()
    {
        data = null;
        size = 0;
    }

public:
    const(ubyte)[] data;
    int32 size; // For >= FbIsc.protocol_version15
}

struct FbIscDatabaseInfo
{
@safe:

public:
    this(int32 connectionCount, string[] databaseNames)
    {
        this.connectionCount = connectionCount;
        this.databaseNames = databaseNames;
    }

    static typeof(this) parse(scope const(ubyte)[] data)
    {
        return parseDatabaseInfo(data);
    }

    void reset() nothrow
    {
        connectionCount = 0;
        databaseNames = null;
    }

public:
    int32 connectionCount;
    string[] databaseNames;
}

struct FbIscError
{
nothrow @safe:

public:
	this(int32 type, int32 intParam, int argNumber) pure
	{
		this._type = type;
		this._intParam = intParam;
        this._argNumber = argNumber;
	}

	this(int32 type, string strParam, int argNumber) pure
	{
		this._type = type;
		this._strParam = strParam;
        this._argNumber = argNumber;
	}

    final string str() const
    {
        switch (type)
		{
            case FbIsc.isc_arg_gds:
                return FbMessages.get(_intParam);
			case FbIsc.isc_arg_number:
				return _intParam.to!string();
			case FbIsc.isc_arg_string:
			case FbIsc.isc_arg_cstring:
			case FbIsc.isc_arg_interpreted:
			case FbIsc.isc_arg_sql_state:
				return _strParam;
			default:
				return null;
        }
    }

    @property final int argNumber() const pure
    {
        return _argNumber;
    }

    @property final int32 code() const pure
    {
        return _intParam;
    }

    @property final int32 type() const pure
    {
        return _type;
    }

    @property final bool isArgument() const pure
	{
        return type == FbIsc.isc_arg_number
            || type == FbIsc.isc_arg_string
            || type == FbIsc.isc_arg_cstring;
	}

	@property final bool isWarning() const pure
	{
        return type == FbIsc.isc_arg_warning;
	}

private:
    string _strParam;
    int _argNumber;
    int32 _intParam;
    int32 _type;
}

struct FbIscFetchResponse
{
nothrow @safe:

public:
    this(int32 status, int32 count) pure
    {
        this.status = status;
        this.count = count;
    }

    DbFetchResultStatus fetchStatus() const
    {
		if (status == 0 && count > 0)
            return DbFetchResultStatus.hasData;
        else if (status == 100)
            return DbFetchResultStatus.completed;
        else
            return DbFetchResultStatus.ready;
    }

public:
    int32 count;
    int32 status;
}

deprecated("please use FbIscColumnInfo")
alias FbIscFieldInfo = FbIscColumnInfo;

struct FbIscGenericResponse
{
nothrow @safe:

public:
    this(FbHandle handle, FbId id, ubyte[] data, FbIscStatues statues)
    {
        this.handle = handle;
        this.id = id;
        this.data = data;
        this.statues = statues;
    }

    FbIscObject getIscObject() const
    {
        return FbIscObject(handle, id);
    }

    void reset()
    {
        data = null;
        statues.reset();
        id = 0;
        handle = 0;
    }

    pragma(inline, true)
    @property bool isError() const
    {
        return statues.isError;
    }

public:
    ubyte[] data;
    FbIscStatues statues;
    FbId id;
    FbHandle handle;
}

struct FbIscInfo
{
@safe:

public:
    this(T)(T value) nothrow
    if (is(Unqual!T == bool) || is(Unqual!T == int) || is(T == string) || is(T == const(char)[]))
    {
        this.value = value;
    }

    T get(T)()
    if (is(Unqual!T == bool) || is(Unqual!T == int) || is(T == string) || is(T == const(char)[]))
    {
        alias UT = Unqual!T;
        static if (is(UT == bool))
            return asBool();
        else static if (is(UT == int))
            return asInt();
        else static if (is(T == string) || is(T == const(char)[]))
            return asString();
        else
            static assert(0);
    }

    static FbIscInfo[] parse(const(ubyte)[] payload)
    {
        FbIscInfo[] result;

        if (payload.length <= 2)
            return result;

        const endPos = payload.length - 2; // -2 for item length
        size_t pos = 0;
        while (pos < endPos)
        {
            const typ = payload[pos++];
            if (typ == FbIsc.isc_info_end)
                break;

            switch (typ)
            {
			    // Database characteristics

    		    // Number of database pages allocated
			    case FbIsc.isc_info_allocation:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Database version(level) number:
			        1 byte containing the number 1
			        1 byte containing the version number
			    */
			    case FbIsc.isc_info_base_level:
                    parseCheckLength(payload, pos, 2, typ);
				    result ~= FbIscInfo(toVersionString([payload[pos], payload[pos + 1]]));
                    pos += 2;
				    break;

			    /** Database file name and site name:
    			    1 byte containing the number 2
	    		    1 byte containing the length, d, of the database file name in bytes
		    	    A string of d bytes, containing the database file name
			        1 byte containing the length, l, of the site name in bytes
			        A string of l bytes, containing the site name
			    */
			    case FbIsc.isc_info_db_id:
                    pos++;
                    auto dbFile = parseString(payload, pos, typ, 1);
                    auto siteName = parseString(payload, pos, typ, 1);
                    const(char)[] fullName = siteName ~ ":" ~ dbFile;
                    result ~= FbIscInfo(fullName);
				    break;

			    /** Database implementation number:
			        1 byte containing a 1
			        1 byte containing the implementation number
			        1 byte containing a class number, either 1 or 12
			    */
			    case FbIsc.isc_info_implementation:
                    parseCheckLength(payload, pos, 3, typ);
				    result ~= FbIscInfo(toVersionString([payload[pos], payload[pos + 1], payload[pos + 2]]));
                    pos += 3;
				    break;

			    /** 0 or 1
			        0 indicates space is reserved on each database page for holding
			          backup versions of modified records [Default]
			        1 indicates no space is reserved for such records
			    */
			    case FbIsc.isc_info_no_reserve:
                    parseCheckLength(payload, pos, 1, typ);
				    result ~= FbIscInfo(payload[pos] == 1);
                    pos++;
				    break;

			    /** ODS major version number
			        _ Databases with different major version numbers have different
			        physical layouts; a database engine can only access databases
			        with a particular ODS major version number
			        _ Trying to attach to a database with a different ODS number
			        results in an error
			    */
			    case FbIsc.isc_info_ods_version:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** On-disk structure (ODS) minor version number; an increase in a
				    minor version number indicates a non-structural change, one that
				    still allows the database to be accessed by database engines with
				    the same major version number but possibly different minor
				    version numbers
			    */
			    case FbIsc.isc_info_ods_minor_version:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Number of bytes per page of the attached database; use with
				    isc_info_allocation to determine the size of the database
			    */
			    case FbIsc.isc_info_page_size:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Version identification string of the database implementation:
				    1 byte containing the number number of message
				    1 byte specifying the length, of the following string
				    n bytes containing the string
			    */
			    case FbIsc.isc_info_version:
			    case FbIsc.isc_info_firebird_version:
                    parseCheckLength(payload, pos, 1, typ);
                    uint msgCount = payload[pos];
                    pos++;
                    while (msgCount--)
                        result ~= FbIscInfo(parseString(payload, pos, typ, 1));
				    break;

			    // Environmental characteristics

			    // Amount of server memory (in bytes) currently in use
			    case FbIsc.isc_info_current_memory:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Number specifying the mode in which database writes are performed
				    0 for asynchronous
                    1 for synchronous
			    */
			    case FbIsc.isc_info_forced_writes:
                    parseCheckLength(payload, pos, 1, typ);
				    result ~= FbIscInfo(payload[pos] == 1);
                    pos++;
				    break;

			    /** Maximum amount of memory (in bytes) used at one time since the first
			        process attached to the database
			    */
			    case FbIsc.isc_info_max_memory:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of memory buffers currently allocated
			    case FbIsc.isc_info_num_buffers:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Number of transactions that are committed between sweeps to
			        remove database record versions that are no longer needed
		        */
			    case FbIsc.isc_info_sweep_interval:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Performance statistics

			    // Number of reads from the memory data cache
			    case FbIsc.isc_info_fetches:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of writes to the memory data cache
			    case FbIsc.isc_info_marks:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of page reads
			    case FbIsc.isc_info_reads:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of page writes
			    case FbIsc.isc_info_writes:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Database operation counts

			    // Number of removals of a version of a record
			    case FbIsc.isc_info_backout_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of database deletes since the database was last attached
			    case FbIsc.isc_info_delete_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Number of removals of a record and all of its ancestors, for records
			        whose deletions have been committed
			    */
			    case FbIsc.isc_info_expunge_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of inserts into the database since the database was last attached
			    case FbIsc.isc_info_insert_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of removals of old versions of fully mature records
			    case FbIsc.isc_info_purge_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of reads done via an index since the database was last attached
			    case FbIsc.isc_info_read_idx_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    /** Number of sequential sequential table scans (row reads) done on each
			        table since the database was last attached
			    */
			    case FbIsc.isc_info_read_seq_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

    		    // Number of database updates since the database was last attached
			    case FbIsc.isc_info_update_count:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Misc

			    case FbIsc.isc_info_db_class:
				    const serverClass = parseInteger!int32(payload, pos, typ);
                    string serverText = serverClass == FbIsc.isc_info_db_class_classic_access
					        ? FbIscText.infoDbClassClassicText
                            : FbIscText.infoDbClassServerText;
				    result ~= FbIscInfo(serverText);
				    break;

			    case FbIsc.isc_info_db_read_only:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

                // Database size in pages
			    case FbIsc.isc_info_db_size_in_pages:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

                // Number of oldest transaction
			    case FbIsc.isc_info_oldest_transaction:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

                // Number of oldest active transaction
			    case FbIsc.isc_info_oldest_active:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

                // Number of oldest snapshot transaction
			    case FbIsc.isc_info_oldest_snapshot:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of next transaction
			    case FbIsc.isc_info_next_transaction:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

			    // Number of active	transactions
			    case FbIsc.isc_info_active_transactions:
				    result ~= FbIscInfo(parseInteger!int32(payload, pos, typ));
				    break;

    		    // Active user name
			    case FbIsc.isc_info_user_names:
				    result ~= FbIscInfo(parseString(payload, pos, typ, 1));
				    break;

                default:
                    pos += parseLength(payload, pos, typ);
                    break;
            }
        }

        return result;
    }

    const(char)[] toString() const nothrow
    {
        return asString();
    }

private:
    bool asBool() const nothrow
    {
        switch (value.variantType)
        {
            case VariantType.boolean:
                return *value.peek!bool();
            case VariantType.integer:
                return *value.peek!int() != 0;
            case VariantType.string:
                return *value.peek!string() == dbBoolTrue;
            case VariantType.dynamicArray: // const(char)[]
                return *value.peek!(const(char)[])() == dbBoolTrue;
            default:
                assert(0);
        }
    }

    int asInt() const
    {
        switch (value.variantType)
        {
            case VariantType.boolean:
                return *value.peek!bool() ? 1 : 0;
            case VariantType.integer:
                return *value.peek!int();
            case VariantType.string:
                auto s = *value.peek!string();
                return s.length ? s.to!int() : 0;
            case VariantType.dynamicArray: // const(char)[]
                auto s2 = *value.peek!(const(char)[])();
                return s2.length ? s2.to!int() : 0;
            default:
                assert(0);
        }
    }

    const(char)[] asString() const nothrow
    {
        switch (value.variantType)
        {
            case VariantType.boolean:
                return *value.peek!bool() ? dbBoolTrue : dbBoolFalse;
            case VariantType.integer:
                return (*value.peek!int()).to!string();
            case VariantType.string:
                return *value.peek!string();
            case VariantType.dynamicArray: // const(char)[]
                return *value.peek!(const(char)[])();
            default:
                assert(0);
        }
    }

private:
    alias Value = Algebraic!(void, bool, int, string, const(char)[]);
    Value value;
}

struct FbIscObject
{
@nogc nothrow @safe:

public:
    this(FbHandle handle, FbId id)
    {
        this._handleStorage = handle;
        this._idStorage = id;
    }

    ref FbIscObject reset() return
    {
        _handleStorage.reset();
        _idStorage.reset();
        return this;
    }

    ref FbIscObject resetHandle() return
    {
        _handleStorage.reset();
        return this;
    }

    ref FbIscObject resetId() return
    {
        _idStorage.reset();
        return this;
    }

    @property bool hasHandle() const
    {
        return _handleStorage.isValid;
    }

    @property FbHandle handle() const
    {
        return _handleStorage.get!FbHandle();
    }

    @property ref FbIscObject handle(const(FbHandle) newValue) return
    {
        _handleStorage = newValue;
        return this;
    }

    @property FbId id() const
    {
        return _idStorage.get!FbId();
    }

    @property ref FbIscObject id(const(FbId) newValue) return
    {
        _idStorage = newValue;
        return this;
    }

private:
    DbHandle _handleStorage;
    DbId _idStorage;
}

struct FbIscOPResponse
{
nothrow @safe:

    void reset()
    {
        debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "(op=", op, ")");

        switch (op)
        {
            case FbIsc.op_accept:
                accept.reset();
                break;

            case FbIsc.op_accept_data:
            case FbIsc.op_cond_accept:
                acceptData.reset();
                break;

            case FbIsc.op_cont_auth:
                contAuth.reset();
                break;

            case FbIsc.op_crypt_key_callback:
                cryptKeyCallback.reset();
                break;

            case FbIsc.op_response:
                generic.reset();
                break;

            case FbIsc.op_trusted_auth:
                trustedAuth.reset();
                break;

            default:
                if (op != 0)
                    assert(0);
                break;
        }

        op = 0;
    }

    FbOperation op;
    FbIscAcceptResponse accept;
    FbIscAcceptDataResponse acceptData;
    FbIscContAuthResponse contAuth;
    FbIscCryptKeyCallbackResponse cryptKeyCallback;
    FbIscGenericResponse generic;
    FbIscTrustedAuthResponse trustedAuth;
}

struct FbIscServerPluginKey
{
@safe:

    string pluginName;
    ubyte[] specificData;
}

struct FbIscServerKey
{
@safe:

public:
    ptrdiff_t indexOf(scope const(char)[] pluginName) const nothrow pure
    {
        foreach (i; 0..pluginKeys.length)
        {
            if (pluginKeys[i].pluginName == pluginName)
                return i;
        }
        return -1;
    }

    static FbIscServerKey[] parse(const(ubyte)[] data)
    {
        FbIscServerKey[] result;

        if (data.length <= 2)
            return result;

        size_t pos = 0;
        const endPos = data.length - 2;

        void parseKeyType() @safe
        {
            import pham.utl.utl_array : indexOf;

            auto pluginType = parseString(data, pos, FbIscServerKeyType.tag_key_type, 1).idup;
            if (pos >= endPos)
                return;

            const typ = data[pos++];
            if (typ != FbIscServerKeyType.tag_key_plugins)
            {
                auto msg = DbMessage.eUnexpectValue.fmtMessage(FbIscServerKey.stringof ~ ".parse", "tag type", typ.to!string, (cast(int)FbIscServerKeyType.tag_key_plugins).to!string);
                throw new FbException(DbErrorCode.read, msg);
            }

            auto pluginNames = parseString(data, pos, FbIscServerKeyType.tag_key_plugins, 1).idup;

            FbIscServerPluginKey[] pluginKeys;
            while (pos < endPos && data[pos] == FbIscServerKeyType.tag_plugin_specific)
            {
                pos++;

                auto data = parseBytes(data, pos, FbIscServerKeyType.tag_plugin_specific, 1);
                const i = data.indexOf(0);
                if (i > 0)
                {
                    auto pluginName = (cast(const(char)[])data[0..i]).idup;
                    auto specificData = data[i + 1..$].dup;
                    pluginKeys ~= FbIscServerPluginKey(pluginName, specificData);
                }
            }

            result ~= FbIscServerKey(pluginType, pluginNames, pluginKeys);
        }

        while (pos < endPos)
        {
            const typ = data[pos++];
            switch (typ)
            {
                case FbIscServerKeyType.tag_key_type:
                    parseKeyType();
                    break;
                //case FbIscServerKeyType.tag_key_plugins:
                //case FbIscServerKeyType.tag_known_plugins:
                //case FbIscServerKeyType.tag_plugin_specific:
                default:
                    //todo log error
                    break;
            }
        }

        return result;
    }

public:
    string pluginType;
    string pluginNames;
    FbIscServerPluginKey[] pluginKeys;
}

struct FbIscServiceInfoResponse
{
nothrow @safe:
    enum ValueKind : ubyte
    {
        unassigned,
        int32,
        buffer,
        database,
        string,
        user,
    }

    void reset()
    {
        code = int32Value = 0;
        strValue = null;
        byteValues = null;
        databaseInfoValue.reset();
        userInfoValues = null;
        valueKind = ValueKind.unassigned;
    }

    string strValue;
    ubyte[] byteValues;
    FbIscDatabaseInfo databaseInfoValue;
    FbIscUserInfo[] userInfoValues;
    int32 int32Value;
    int32 code;
    ValueKind valueKind;
}

struct FbIscSqlResponse
{
nothrow @safe:

public:
    this(int64 count) pure
    {
        this.count = count;
    }

public:
    int64 count;
}

struct FbIscStatues
{
nothrow @safe:

public:
    this(FbIscError[] errors, int32 sqlCode,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @nogc pure
    {
        this.errors = errors;
        this.sqlCode = sqlCode;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
    }

    void buildMessage(out string message, out int code, out string state)
    {
        debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "()");

        message = state = null;
        code = 0;
        foreach (ref error; errors)
        {
            switch (error.type)
            {
                case FbIsc.isc_arg_gds:
                    code = error.code;
                    addMessageLine(message, error.str());
                    break;
                case FbIsc.isc_arg_number:
                case FbIsc.isc_arg_string:
                case FbIsc.isc_arg_cstring:
                    auto marker = "@" ~ error.argNumber.to!string();
                    message = message.replace(marker, error.str());
                    break;
                case FbIsc.isc_arg_interpreted:
                    addMessageLine(message, error.str());
                    break;
                case FbIsc.isc_arg_sql_state:
                    addMessageLine(state, error.str());
                    break;
                default:
                    break;
            }
        }

        debug(debug_pham_db_db_fbtype) debug writeln("\t", "code=", code, ", state=", state, ", message=", message);
    }

    int getWarn(ref DbNotificationMessage[] messages)
    {
        debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "()");

        string warnMessage;
        int32 warnCode;

        void addWarnMessage() nothrow @safe
        {
            messages ~= DbNotificationMessage(warnMessage, warnCode);
        }

        int result = 0;
        foreach (ref error; errors)
        {
            switch (error.type)
            {
                case FbIsc.isc_arg_warning:
                    if (warnMessage.length != 0)
                        addWarnMessage();
                    warnCode = error.code;
                    warnMessage = error.str();
                    result++;
                    break;
                case FbIsc.isc_arg_number:
                case FbIsc.isc_arg_string:
                case FbIsc.isc_arg_cstring:
                    if (warnMessage.length != 0)
                    {
                        auto marker = "@" ~ error.argNumber.to!string();
                        warnMessage = warnMessage.replace(marker, error.str());
                    }
                    break;
                case FbIsc.isc_arg_interpreted:
                case FbIsc.isc_arg_sql_state:
                    if (warnMessage.length != 0)
                        warnMessage ~= error.str();
                    break;
                default:
                    break;
            }
        }
        if (warnMessage.length != 0)
            addWarnMessage();

        debug(debug_pham_db_db_fbtype) debug writeln("\t", "warnCode=", warnCode, ", warnMessage=", warnMessage);

        return result;
    }

    int32 errorCode() const
    {
        foreach (ref error; errors)
        {
            if (error.type == FbIsc.isc_arg_gds)
                return error.code;
        }
        return 0;
    }

    void put(FbIscError error)
    {
        if (errors.length == 0)
            errors.reserve(FbIscSize.iscStatusLength);
        errors ~= error;
    }

    void reset()
    {
        errors = null;
        sqlCode = 0;
        file = funcName = null;
        line = 0;
    }

    string sqlState() const
    {
        foreach (ref error; errors)
        {
            if (error.type == FbIsc.isc_arg_sql_state)
                return error.str();
        }
        return FbSqlStates.get(errorCode);
    }

	@property bool hasWarn() const
	{
        foreach (ref error; errors)
        {
            if (error.isWarning)
                return true;
        }
        return false;
	}

	@property bool isError() const
	{
        return errorCode() != 0;
	}

public:
    FbIscError[] errors;
    int32 sqlCode;
    string file;
    string funcName;
    uint line;
}

struct FbIscTransactionInfo
{
@safe:

public:
    static typeof(this) parse(scope const(ubyte)[] data)
    {
        return parseTransactionInfo(data);
    }

public:
    int64 id;
    int64 oldestActiveId;
    int64 snapshotId;
    uint8 access; // [isc_info_tra_readonly | isc_info_tra_readwrite]
    uint8 isolation; // [isc_info_tra_read_committed | isc_info_tra_consistency | isc_info_tra_concurrency]
    uint8 isolationSub; // For isc_info_tra_read_committed, it can have [isc_info_tra_read_consistency | isc_info_tra_rec_version | isc_info_tra_no_rec_version]
    int16 lockTimeout;
}

struct FbIscTrustedAuthResponse
{
nothrow @safe:

public:
    this(ubyte[] data) pure
    {
        this.data = data;
    }

    void reset()
    {
        data = null;
    }

public:
    ubyte[] data;
}

struct FbIscUserInfo
{
@safe:

public:
    static typeof(this)[] parse(scope const(ubyte)[] data)
    {
        return parseUserInfo(data);
    }

    void reset()
    {
        userName = userPassword = firstName = lastName = middleName = groupName = roleName = null;
        admin = userId = groupId = 0;
    }

public:
    string userName;
    string userPassword;
	string firstName;
	string lastName;
	string middleName;
    int32 admin;
	int32 groupId;
	int32 userId;
	string groupName;
	string roleName;
}

DbParameterDirection fbParameterModeToDirection(const(int16) mode)
{
    return mode == 0
        ? DbParameterDirection.input
        : (mode == 1 ? DbParameterDirection.output : DbParameterDirection.inputOutput);
}

/**
    Returns:
        length of blob in bytes
 */
size_t parseBlob(W)(scope ref W sink, scope const(ubyte)[] data) @safe
if (isOutputRange!(W, ubyte))
{
    if (data.length <= 2)
        return 0;

    const endPos = data.length - 2; // -2 for item length
    size_t result, pos;
	while (pos < endPos)
	{
        const len = parseLength(data, pos, FbIscType.sql_blob);
        put(sink, data[pos..pos + len]);
        result += len;
        pos += len;
	}
    return result;
}

FbIscBlobSize parseBlobSize(scope const(ubyte)[] data)
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

        switch (typ)
        {
            case FbIsc.isc_info_blob_max_segment:
                result.maxSegment = parseInteger!int32(data, pos, typ);
                break;

            case FbIsc.isc_info_blob_num_segments:
                result.segmentCount = parseInteger!int32(data, pos, typ);
                break;

            case FbIsc.isc_info_blob_total_length:
                result.length = parseInteger!int32(data, pos, typ);
                break;

            case FbIsc.isc_info_blob_type:
                result.type = parseInteger!int32(data, pos, typ);
                break;

            default:
                auto msg = DbMessage.eInvalidSQLDAType.fmtMessage(typ);
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
        }
    }

    debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "(maxSegment=", result.maxSegment,
        ", segmentCount=", result.segmentCount, ", length=", result.length, ", type=", result.type, ")");

    return result;
}

pragma(inline, true)
bool parseBool(scope const(ubyte)[] data, ref size_t index, int type, const(ubyte) lengthBytes = 2) pure
{
    uint bytes;
    return parseBool(data, index, bytes, type, lengthBytes);
}

bool parseBool(scope const(ubyte)[] data, ref size_t index, out uint bytes, int type, const(ubyte) lengthBytes = 2) pure
{
    return parseInteger!int32(data, index, bytes, type, lengthBytes) != 0;
}

pragma(inline, true)
const(ubyte)[] parseBytes(const(ubyte)[] data, ref size_t index, int type, const(ubyte) lengthBytes = 2) pure
{
    uint bytes;
    return parseBytes(data, index, bytes, type, lengthBytes);
}

const(ubyte)[] parseBytes(const(ubyte)[] data, ref size_t index, out uint bytes, int type, const(ubyte) lengthBytes = 2) pure
{
    bytes = parseLength(data, index, type, lengthBytes);

    const(ubyte)[] result = null;
    if (bytes)
        result = data[index..index + bytes];
    index += bytes;
    bytes += lengthBytes;

    return result;
}

/**
 * Check if index + length is not out of bound of array `data`
 */
pragma(inline, true)
void parseCheckLength(scope const(ubyte)[] data, size_t index, const(uint) length, int type) pure
{
    if (index + length > data.length)
    {
        auto msg = DbMessage.eInvalidSQLDANotEnoughData.fmtMessage(type, length);
        throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
    }
}

FbIscCommandType parseCommandType(scope const(ubyte)[] data) pure
{
    if (data.length <= 2)
        return FbIscCommandType.none;

    const endPos = data.length - 2;
	size_t pos = 0;
	while (pos < endPos)
	{
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

		if (typ == FbIsc.isc_info_sql_stmt_type)
		    return cast(FbIscCommandType)parseInteger!int32(data, pos, typ);
        else
            pos += parseLength(data, pos, typ);
	}

	return FbIscCommandType.none;
}

FbIscDatabaseInfo parseDatabaseInfo(scope const(ubyte)[] data) pure
{
    FbIscDatabaseInfo result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2; // -2 for item length
    size_t pos = 0;
    while (pos < endPos)
    {
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

        switch (typ)
        {
            case FbIsc.isc_spb_num_att:
                result.connectionCount = parseIntegerFixedLength!int32(data, pos, typ);
                break;

            case FbIsc.isc_spb_dbname:
                result.databaseNames ~= parseString(data, pos, typ).idup;
                break;

            case FbIsc.isc_spb_num_db:
                pos += uint32.sizeof; // parseIntegerFixedLength!int32(data, pos, typ)
                break;

            default:
                auto msg = DbMessage.eInvalidSQLDAType.fmtMessage(typ);
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
        }
    }

    return result;
}

pragma(inline, true)
T parseInteger(T)(scope const(ubyte)[] data, ref size_t index, int type, const(ubyte) lengthBytes = 2) pure
if (isIntegral!T)
{
    uint bytes;
    return parseInteger!T(data, index, bytes, type, lengthBytes);
}

T parseInteger(T)(scope const(ubyte)[] data, ref size_t index, out uint bytes, int type, const(ubyte) lengthBytes = 2) pure
if (isIntegral!T)
{
    bytes = parseLength(data, index, type, lengthBytes);

    T result = 0;
    uint shift = 0;
    foreach (i; 0..bytes)
    {
        result += cast(T)data[index++] << shift;
        shift += 8;
    }
    bytes += lengthBytes;

    return result;
}

T parseIntegerFixedLength(T)(scope const(ubyte)[] data, ref size_t index, int type) pure
if (isIntegral!T)
{
    parseCheckLength(data, index, T.sizeof, type);

    T result = 0;
    uint shift = 0;
    foreach (i; 0..T.sizeof)
    {
        result += cast(T)data[index++] << shift;
        shift += 8;
    }

    return result;
}

/**
 * Check and return length in `length` bytes
 */
uint parseLength(scope const(ubyte)[] data, ref size_t index, int type, const(ubyte) lengthBytes = 2) pure
in
{
    assert(lengthBytes <= 4);
}
do
{
    parseCheckLength(data, index, lengthBytes, type);

	uint result, shift;
	foreach (i; 0..lengthBytes)
	{
		result += cast(uint)data[index++] << shift;
		shift += 8;
	}

    parseCheckLength(data, index, result, type);
    return result;
}

FbIscTransactionInfo parseTransactionInfo(scope const(ubyte)[] data)
{
    FbIscTransactionInfo result;

    if (data.length <= 2)
        return result;

    const endPos = data.length - 2; // -2 for item length
    size_t pos = 0;
    while (pos < endPos)
    {
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

        switch (typ)
        {
            case FbIsc.isc_info_tra_id:
                result.id = parseInteger!int64(data, pos, typ);
                break;

            case FbIsc.isc_info_tra_oldest_active:
                result.oldestActiveId = parseInteger!int64(data, pos, typ);
                break;

            case FbIsc.isc_info_tra_oldest_snapshot:
                result.snapshotId = parseInteger!int64(data, pos, typ);
                break;

            case FbIsc.isc_info_tra_isolation:
                const v = parseInteger!uint16(data, pos, typ);
                result.isolation = cast(uint8)(v & 0xFF);
                result.isolationSub = cast(uint8)((v >> 8) & 0xFF);
                break;

            case FbIsc.isc_info_tra_access:
                result.access = parseInteger!uint8(data, pos, typ);
                break;

            case FbIsc.isc_info_tra_lock_timeout:
                result.lockTimeout = parseInteger!int16(data, pos, typ);
                break;

            //case FbIsc.isc_info_error:

            default:
                auto msg = DbMessage.eInvalidSQLDAType.fmtMessage(typ);
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
        }
    }

    return result;
}

string parsePlan(scope const(ubyte)[] data, FbIsc describeMode) pure
{
    size_t index = 1;
    return parseString(data, index, describeMode).idup;
}

DbRecordsAffectedAggregate parseRecordsAffected(scope const(ubyte)[] data) @safe
{
    debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "()");

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

            const count = parseInteger!int32(data, pos, typ);
			switch (typ)
			{
				case FbIsc.isc_info_req_select_count:
                    debug(debug_pham_db_db_fbtype) debug writeln("\t", "selectCount=", count);
					result.selectCount += count;
					break;

				case FbIsc.isc_info_req_insert_count:
                    debug(debug_pham_db_db_fbtype) debug writeln("\t", "insertCount=", count);
					result.insertCount += count;
					break;

				case FbIsc.isc_info_req_update_count:
                    debug(debug_pham_db_db_fbtype) debug writeln("\t", "updateCount=", count);
					result.updateCount += count;
					break;

				case FbIsc.isc_info_req_delete_count:
                    debug(debug_pham_db_db_fbtype) debug writeln("\t", "deleteCount=", count);
					result.deleteCount += count;
					break;

                default:
                    break;
			}
		}
    }

	while (pos < endPos)
	{
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

		const len = parseLength(data, pos, typ);
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

pragma(inline, true)
const(char)[] parseString(return const(ubyte)[] data, ref size_t index, int type, const(ubyte) lengthBytes = 2) pure
{
    uint bytes;
    return parseString(data, index, bytes, type, lengthBytes);
}

const(char)[] parseString(return const(ubyte)[] data, ref size_t index, out uint bytes, int type, const(ubyte) lengthBytes = 2) pure
{
    bytes = parseLength(data, index, type, lengthBytes);

    const(char)[] result = null;
    if (bytes)
        result = cast(const(char)[])data[index..index + bytes];
    index += bytes;
    bytes += lengthBytes;

    return result;
}

FbHandle parseTraceSessionId(scope const(char)[] statusLine) nothrow
{
    import std.array : split;
    import std.ascii : isWhite;

    // Sample of statusLine: Trace session ID 22 started
    if (statusLine.length == 0)
        return FbHandle.init;

    try
    {
        auto words = statusLine.split!isWhite();
        int state = 0;
        foreach (w; words)
        {
            if (state == 0 && w == "session")
                state++;
            else if (state == 1 && (w == "ID" || w == "id"))
                state++;
            else if (state == 2)
                return toIntegerSafe!FbHandle(w, FbHandle.init, FbHandle.init);
            else if (state != 0)
                break;
        }
    }
    catch (Exception)
    {}
    return FbHandle.init;
}

FbIscUserInfo[] parseUserInfo(scope const(ubyte)[] data)
{
    debug(debug_pham_db_db_fbtype) debug writeln(__FUNCTION__, "(data.length=", data.length, ")");

    FbIscUserInfo[] result;

    if (data.length <= 2)
        return result;

    FbIscUserInfo currentUser;
    const endPos = data.length - 2; // -2 for item length
    size_t pos = 0;
    while (pos < endPos)
    {
        const typ = data[pos++];
        if (typ == FbIsc.isc_info_end)
            break;

        //debug writeln("\t", "typ=", typ, ", currentUser.userName=", currentUser.userName);

        switch (typ)
        {
            case FbIsc.isc_spb_sec_username:
                if (currentUser.userName.length)
                    result ~= currentUser;

                currentUser.reset();
                currentUser.userName = parseString(data, pos, typ).idup;
                break;

            case FbIsc.isc_spb_sec_firstname:
                currentUser.firstName = parseString(data, pos, typ).idup;
                break;

            case FbIsc.isc_spb_sec_middlename:
                currentUser.middleName = parseString(data, pos, typ).idup;
                break;

            case FbIsc.isc_spb_sec_lastname:
                currentUser.lastName = parseString(data, pos, typ).idup;
                break;

            case FbIsc.isc_spb_sec_userid:
                currentUser.userId = parseIntegerFixedLength!int32(data, pos, typ);
                break;

            case FbIsc.isc_spb_sec_groupid:
                currentUser.groupId = parseIntegerFixedLength!int32(data, pos, typ);
                break;

            case FbIsc.isc_spb_sec_admin:
                currentUser.admin = parseIntegerFixedLength!int32(data, pos, typ);
                break;

            case FbIsc.isc_spb_sec_groupname:
                currentUser.groupName = parseString(data, pos, typ).idup;
                break;

            case FbIsc.isc_spb_sec_password:
                currentUser.userPassword = parseString(data, pos, typ).idup;
                break;

            default:
                auto msg = DbMessage.eInvalidSQLDAType.fmtMessage(typ);
                throw new FbException(DbErrorCode.read, msg, null, 0, FbIscResultCode.isc_dsql_sqlda_err);
        }
    }

    if (currentUser.userName.length)
        result ~= currentUser;

    return result;
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    debug(debug_pham_db_db_fbtype) debug writeln("shared static this(", __MODULE__, ")");

    fbDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        auto result = FbDefaultConnectionParameterValues(5, 4);

        result[DbConnectionParameterIdentifier.serverPort] = DbConnectionParameterInfo(&isConnectionParameterInt32, "3_050", 0, uint16.max, DbScheme.fb);
        result[DbConnectionParameterIdentifier.userName] = DbConnectionParameterInfo(&isConnectionParameterString, "SYSDBA", 0, dbConnectionParameterMaxId, DbScheme.fb);
        result[DbConnectionParameterIdentifier.userPassword] = DbConnectionParameterInfo(&isConnectionParameterString, "masterkey", 0, dbConnectionParameterMaxId, DbScheme.fb);
        result[DbConnectionParameterIdentifier.fbCryptAlgorithm] = DbConnectionParameterInfo(&isConnectionParameterFBCryptAlgorithm, FbIscText.filterCryptDefault, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.fb);

        debug(debug_pham_db_db_fbtype) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return cast(immutable(FbDefaultConnectionParameterValues))result;
    }();

    fbDbIdToDbTypeInfos = () nothrow pure @trusted
    {
        auto result = FbDbIdToDbTypeInfos(fbNativeTypes.length + 1, fbNativeTypes.length, DictionaryHashMix.murmurHash3);

        foreach (i; 0..fbNativeTypes.length)
        {
            const dbId = fbNativeTypes[i].dbId;
            if (!(dbId in result))
                result[dbId] = &fbNativeTypes[i];
        }

        debug(debug_pham_db_db_fbtype) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return cast(immutable(FbDbIdToDbTypeInfos))result;
    }();
}

version(unittest)
enum countOfFbIscType = EnumMembers!FbIscType.length;

unittest // FbIscBlobSize
{
    import pham.utl.utl_convert : bytesFromHexs;

    auto info = bytesFromHexs("05040004000000040400010000000604000400000001");
    auto parsedSize = FbIscBlobSize.parse(info);
    assert(parsedSize.maxSegment == 4);
    assert(parsedSize.segmentCount == 1);
    assert(parsedSize.length == 4);
}

unittest // FbIscBindInfo
{
    import pham.utl.utl_convert : bytesFromHexs;

    FbIscBindInfo[] bindResults;
    ptrdiff_t previousBindIndex = -1;
    ptrdiff_t previousColumnIndex;
    auto info = bytesFromHexs("040704000D000000090400010000000B0400F00100000C0400000000000E0400040000000D040000000000100900494E545F4649454C44110B00544553545F53454C454354130900494E545F4649454C4408090400020000000B0400F50100000C0400000000000E0400020000000D040000000000100E00534D414C4C494E545F4649454C44110B00544553545F53454C454354130E00534D414C4C494E545F4649454C4408090400030000000B0400E30100000C0400000000000E0400040000000D040000000000100B00464C4F41545F4649454C44110B00544553545F53454C454354130B00464C4F41545F4649454C4408090400040000000B0400E10100000C0400000000000E0400080000000D040000000000100C00444F55424C455F4649454C44110B00544553545F53454C454354130C00444F55424C455F4649454C4408090400050000000B0400450200000C0400010000000E0400080000000D0400FEFFFFFF100D004E554D455249435F4649454C44110B00544553545F53454C454354130D004E554D455249435F4649454C4408090400060000000B0400450200000C0400020000000E0400080000000D0400FEFFFFFF100D00444543494D414C5F4649454C44110B00544553545F53454C454354130D00444543494D414C5F4649454C4408090400070000000B04003B0200000C0400000000000E0400040000000D040000000000100A00444154455F4649454C44110B00544553545F53454C454354130A00444154455F4649454C4408090400080000000B0400310200000C0400000000000E0400040000000D040000000000100A0054494D455F4649454C44110B00544553545F53454C454354130A0054494D455F4649454C4408090400090000000B0400FF0100000C0400000000000E0400080000000D040000000000100F0054494D455354414D505F4649454C44110B00544553545F53454C454354130F0054494D455354414D505F4649454C44080904000A0000000B0400C50100000C0400040000000E0400280000000D040000000000100A00434841525F4649454C44110B00544553545F53454C454354130A00434841525F4649454C44080904000B0000000B0400C10100000C0400040000000E0400280000000D040000000000100D00564152434841525F4649454C44110B00544553545F53454C454354130D00564152434841525F4649454C44080904000C0000000B0400090200000C0400000000000E0400080000000D040000000000100A00424C4F425F4649454C44110B00544553545F53454C454354130A00424C4F425F4649454C44080904000D0000000B0400090200000C0400010000000E0400080000000D040004000000100A00544558545F4649454C44110B00544553545F53454C454354130A00544558545F4649454C4408050704000000000001");
    auto parsed = FbIscBindInfo.parse(info, bindResults, previousBindIndex, previousColumnIndex);
    assert(parsed == true);
    assert(bindResults.length == 2);

    assert(bindResults[0].selectOrBind == FbIsc.isc_info_sql_select);
    assert(bindResults[0].length == 13);
    auto column = bindResults[0].column(0);
    assert(column.name == "INT_FIELD" && column.type == 496 && column.subType == 0 && column.numericScale == 0 && column.size == 4 && column.tableName == "TEST_SELECT" && column.aliasName == "INT_FIELD");
    column = bindResults[0].column(1);
    assert(column.name == "SMALLINT_FIELD" && column.type == 501 && column.subType == 0 && column.numericScale == 0 && column.size == 2 && column.tableName == "TEST_SELECT" && column.aliasName == "SMALLINT_FIELD");
    column = bindResults[0].column(2);
    assert(column.name == "FLOAT_FIELD" && column.type == 483 && column.subType == 0 && column.numericScale == 0 && column.size == 4 && column.tableName == "TEST_SELECT" && column.aliasName == "FLOAT_FIELD");
    column = bindResults[0].column(3);
    assert(column.name == "DOUBLE_FIELD" && column.type == 481 && column.subType == 0 && column.numericScale == 0 && column.size == 8 && column.tableName == "TEST_SELECT" && column.aliasName == "DOUBLE_FIELD");
    column = bindResults[0].column(4);
    assert(column.name == "NUMERIC_FIELD" && column.type == 581 && column.subType == 1 && column.numericScale == -2 && column.size == 8 && column.tableName == "TEST_SELECT" && column.aliasName == "NUMERIC_FIELD");
    column = bindResults[0].column(5);
    assert(column.name == "DECIMAL_FIELD" && column.type == 581 && column.subType == 2 && column.numericScale == -2 && column.size == 8 && column.tableName == "TEST_SELECT" && column.aliasName == "DECIMAL_FIELD");
    column = bindResults[0].column(6);
    assert(column.name == "DATE_FIELD" && column.type == 571 && column.subType == 0 && column.numericScale == 0 && column.size == 4 && column.tableName == "TEST_SELECT" && column.aliasName == "DATE_FIELD");
    column = bindResults[0].column(7);
    assert(column.name == "TIME_FIELD" && column.type == 561 && column.subType == 0 && column.numericScale == 0 && column.size == 4 && column.tableName == "TEST_SELECT" && column.aliasName == "TIME_FIELD");
    column = bindResults[0].column(8);
    assert(column.name == "TIMESTAMP_FIELD" && column.type == 511 && column.subType == 0 && column.numericScale == 0 && column.size == 8 && column.tableName == "TEST_SELECT" && column.aliasName == "TIMESTAMP_FIELD");
    column = bindResults[0].column(9);
    assert(column.name == "CHAR_FIELD" && column.type == 453 && column.subType == 4 && column.numericScale == 0 && column.size == 40 && column.tableName == "TEST_SELECT" && column.aliasName == "CHAR_FIELD");
    column = bindResults[0].column(10);
    assert(column.name == "VARCHAR_FIELD" && column.type == 449 && column.subType == 4 && column.numericScale == 0 && column.size == 40 && column.tableName == "TEST_SELECT" && column.aliasName == "VARCHAR_FIELD");
    column = bindResults[0].column(11);
    assert(column.name == "BLOB_FIELD" && column.type == 521 && column.subType == 0 && column.numericScale == 0 && column.size == 8 && column.tableName == "TEST_SELECT" && column.aliasName == "BLOB_FIELD");
    column = bindResults[0].column(12);
    assert(column.name == "TEXT_FIELD" && column.type == 521 && column.subType == 1 && column.numericScale == 4 && column.size == 8 && column.tableName == "TEST_SELECT" && column.aliasName == "TEXT_FIELD");

    assert(bindResults[1].selectOrBind == FbIsc.isc_info_sql_bind);
    assert(bindResults[1].length == 0);
}

unittest // FbCreateDatabaseInfo.toKnownPageSize
{
    assert(FbCreateDatabaseInfo.toKnownPageSize(-2) == FbCreateDatabaseInfo.knownPageSizes[$ - 1]);
    assert(FbCreateDatabaseInfo.toKnownPageSize(0) == FbCreateDatabaseInfo.knownPageSizes[$ - 1]);

    assert(FbCreateDatabaseInfo.toKnownPageSize(1) == 4_096);
    assert(FbCreateDatabaseInfo.toKnownPageSize(4_095) == 4_096);
    assert(FbCreateDatabaseInfo.toKnownPageSize(4_096) == 4_096);

    assert(FbCreateDatabaseInfo.toKnownPageSize(4_097) == 8_192);
    assert(FbCreateDatabaseInfo.toKnownPageSize(8_191) == 8_192);
    assert(FbCreateDatabaseInfo.toKnownPageSize(8_192) == 8_192);

    assert(FbCreateDatabaseInfo.toKnownPageSize(8_193) == 16_384);
    assert(FbCreateDatabaseInfo.toKnownPageSize(16_383) == 16_384);
    assert(FbCreateDatabaseInfo.toKnownPageSize(16_384) == 16_384);

    assert(FbCreateDatabaseInfo.toKnownPageSize(16_385) == 32_768);
    assert(FbCreateDatabaseInfo.toKnownPageSize(32_767) == 32_768);
    assert(FbCreateDatabaseInfo.toKnownPageSize(32_768) == 32_768);

    // Future value - return as is
    assert(FbCreateDatabaseInfo.toKnownPageSize(65_536) == 65_536);
    assert(FbCreateDatabaseInfo.toKnownPageSize(131_073) == 131_073);
}
