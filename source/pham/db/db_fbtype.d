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

module pham.db.fbtype;

import std.array : Appender, replace;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.format : format;
import std.traits : EnumMembers, Unqual;

version (TraceFunction) import pham.utl.test;
import pham.utl.variant : Algebraic, Variant, VariantType;
import pham.db.util : toVersionString;
import pham.db.message;
import pham.db.type;
import pham.db.fbisc;
import pham.db.fbmessage;
import pham.db.fbexception;

@safe:

alias FbId = int64;
alias FbHandle = uint32;
alias FbOperation = int32;

enum fbMaxChars = 32_767;
enum fbMaxPackageSize = 32_767;
enum fbMaxVarChars = fbMaxChars - 2; // -2 for size place holder
enum fbNullIndicator = -1;

version (DeferredProtocol)
enum fbCommandDeferredHandle = 65535;

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
	savePoint = FbIsc.isc_info_sql_stmt_savepoint
}

immutable string[string] fbDefaultParameterValues;

immutable string[] fbValidParameterNames = [
    // Primary
    DbParameterName.server,
    DbParameterName.port,
    DbParameterName.database,
    DbParameterName.userName,
    DbParameterName.userPassword,
    DbParameterName.encrypt,
    DbParameterName.compress,
    DbParameterName.charset,

    // Other
    DbParameterName.connectionTimeout,
    DbParameterName.fetchRecordCount,
    DbParameterName.pooling,
    DbParameterName.packageSize,
    DbParameterName.receiveTimeout,
    DbParameterName.sendTimeout,
    DbParameterName.socketBlocking,

    DbParameterName.fbCachePage,
    DbParameterName.fbDatabaseTrigger,
    DbParameterName.fbDialect,
    DbParameterName.fbDummyPacketInterval,
    DbParameterName.fbGarbageCollect
];

immutable DbTypeInfo[] fbNativeTypes = [
    {dbName:"VARCHAR[?]", nativeName:"VARCHAR", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_VARYING, dbType:DbType.string}, //varchar
    {dbName:"CHAR[?]", nativeName:"CHAR", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_TEXT, dbType:DbType.chars}, //char[]
    {dbName:"DOUBLE", nativeName:"DOUBLE PRECISION", displaySize:17, nativeSize:8, nativeId:FbIscType.SQL_DOUBLE, dbType:DbType.float64},
    {dbName:"FLOAT", nativeName:"FLOAT", displaySize:17, nativeSize:4, nativeId:FbIscType.SQL_FLOAT, dbType:DbType.float32},
    {dbName:"INTEGER", nativeName:"INTEGER", displaySize:11, nativeSize:4, nativeId:FbIscType.SQL_LONG, dbType:DbType.int32},
    {dbName:"SMALLINT", nativeName:"SMALLINT", displaySize:6, nativeSize:2, nativeId:FbIscType.SQL_SHORT, dbType:DbType.int16},
    {dbName:"TIMESTAMP", nativeName:"TIMESTAMP", displaySize:22, nativeSize:8, nativeId:FbIscType.SQL_TIMESTAMP, dbType:DbType.datetime},
    {dbName:"BLOB", nativeName:"BLOB", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_BLOB, dbType:DbType.binary},
    {dbName:"DOUBLE", nativeName:"DOUBLE PRECISION", displaySize:17, nativeSize:8, nativeId:FbIscType.SQL_D_FLOAT, dbType:DbType.float64},
    {dbName:"ARRAY[?,?]", nativeName:"ARRAY", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_ARRAY, dbType:DbType.array},
    {dbName:"BIGINT", nativeName:"QUAD", displaySize:20, nativeSize:8, nativeId:FbIscType.SQL_QUAD, dbType:DbType.int64},
    {dbName:"TIME", nativeName:"TIME", displaySize:11, nativeSize:4, nativeId:FbIscType.SQL_TIME, dbType:DbType.time},
    {dbName:"DATE", nativeName:"DATE", displaySize:10, nativeSize:4, nativeId:FbIscType.SQL_DATE, dbType:DbType.date},
    {dbName:"BIGINT", nativeName:"BIGINT", displaySize:20, nativeSize:8, nativeId:FbIscType.SQL_INT64, dbType:DbType.int64},
    {dbName:"BOOLEAN", nativeName:"BOOLEAN", displaySize:5, nativeSize:1, nativeId:FbIscType.SQL_BOOLEAN, dbType:DbType.boolean}, // fb3
    {dbName:"INT128", nativeName:"INT128", displaySize:40, nativeSize:16, nativeId:FbIscType.SQL_INT128, dbType:DbType.int128}, // fb4
    {dbName:"TIMESTAMPTZ", nativeName:"TIMESTAMP WITH TIMEZONE", displaySize:28, nativeSize:10, nativeId:FbIscType.SQL_TIMESTAMP_TZ, dbType:DbType.datetimeTZ}, // fb4
    {dbName:"TIMESTAMPTZ", nativeName:"TIMESTAMP WITH OFFSET TIMEZONE", displaySize:28, nativeSize:10, nativeId:FbIscType.SQL_TIMESTAMP_TZ_EX, dbType:DbType.datetimeTZ}, // fb4
    {dbName:"TIMETZ", nativeName:"TIME WITH TIMEZONE", displaySize:17, nativeSize:6, nativeId:FbIscType.SQL_TIME_TZ, dbType:DbType.timeTZ}, // fb4
    {dbName:"TIMETZ", nativeName:"TIME WITH OFFSET TIMEZONE", displaySize:17, nativeSize:6, nativeId:FbIscType.SQL_TIME_TZ_EX, dbType:DbType.timeTZ}, // fb4
    {dbName:"DECIMAL(16)", nativeName:"DECFLOAT(16)", displaySize:16, nativeSize:8, nativeId:FbIscType.SQL_DEC64, dbType:DbType.decimal64}, // fb4
    {dbName:"DECIMAL(34)", nativeName:"DECFLOAT(34)", displaySize:34, nativeSize:16, nativeId:FbIscType.SQL_DEC128, dbType:DbType.decimal128}, // fb4
    {dbName:"DECIMAL(34)", nativeName:"DECFLOAT", displaySize:34, nativeSize:16, nativeId:FbIscType.SQL_DEC128, dbType:DbType.decimal128}, // fb4 - Map to DECFLOAT(34) as document
    {dbName:"", nativeName:"NULL", displaySize:4, nativeSize:0, nativeId:FbIscType.SQL_NULL, dbType:DbType.unknown}
];

immutable DbTypeInfo*[int32] fbIscTypeToDbTypeInfos;

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

    static int32 normalizeVersion(int32 version_) pure
    {
        return (version_ < 0)
		    ? FbIsc.protocol_flag | cast(ushort)(version_ & FbIsc.protocol_mask)
            : version_;
    }

public:
    int32 acceptType;
    int32 architecture;
    int32 version_;
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

struct FbIscArrayDescriptor
{
nothrow @safe:

public:
    size_t calculateElements() const pure
    {
		size_t result = 1;
		foreach (ref bound; bounds)
		{
			result *= bound.upper - bound.lower + 1;
		}
        return result;
    }

	size_t calculateSliceLength(size_t elements = 0) const pure
	{
        if (elements == 0)
            elements = calculateElements();
		auto result = elements * fieldInfo.size;
	    if (fieldInfo.fbType() == FbIscType.SQL_VARYING)
            result += (elements * 2);
        return result;
	}

public:
    FbIscFieldInfo fieldInfo;
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
    this(size_t fieldCount) nothrow pure
    {
        this._fields = new FbIscFieldInfo[fieldCount];
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
        ref ptrdiff_t previousBindIndex, ref ptrdiff_t previousFieldIndex)
    {
        version (TraceFunction) dgFunctionTrace("payload.length=", payload.length);

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
                            fieldIndex = 0; // Reset for new block
                            goto case FbIsc.isc_info_truncated;
                        }

			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        const uint fieldLen = parseInt32!true(payload, posData, len, typ);

                        if (bindIndex == bindResults.length)
                        {
                            bindResults ~= FbIscBindInfo(fieldLen);
                            bindResults[bindIndex].selectOrBind = typ;
                            if (fieldLen == 0)
                                goto doneItem;
                        }

			            break;

			        case FbIsc.isc_info_sql_sqlda_seq:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
			            fieldIndex = parseInt32!true(payload, posData, len, typ) - 1;

                        if (checkFieldIndex(typ) >= bindResults[checkBindIndex(typ)].length)
                        {
                            auto msg = format(DbMessage.eInvalidSQLDAFieldIndex, typ, fieldIndex);
                            throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
                        }

			            break;

			        case FbIsc.isc_info_sql_type:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto dataType = parseInt32!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).type = dataType;
			            break;

			        case FbIsc.isc_info_sql_sub_type:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto dataSubType = parseInt32!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).subType = dataSubType;
			            break;

			        case FbIsc.isc_info_sql_scale:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto numericScale = parseInt32!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).numericScale = numericScale;
			            break;

			        case FbIsc.isc_info_sql_length:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto dataSize = parseInt32!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).size = dataSize;
			            break;

			        case FbIsc.isc_info_sql_field:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto fieldName = parseString!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).name = fieldName;
			            break;

			        case FbIsc.isc_info_sql_relation:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto tableName = parseString!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).tableName = tableName;
			            break;

			        case FbIsc.isc_info_sql_owner:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto owner = parseString!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).owner = owner;
			            break;

			        case FbIsc.isc_info_sql_alias:
			            const uint len = parseInt32!true(payload, posData, 2, typ);
                        auto aliasName = parseString!true(payload, posData, len, typ);
			            bindResults[checkBindIndex(typ)].field(checkFieldIndex(typ)).aliasName = aliasName;
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
            dgFunctionTrace("rowDescs.length=", bindResults.length);
            foreach (i, ref desc; bindResults)
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

    ref typeof(this) reset() nothrow return
    {
        selectOrBind = 0;
        _fields = null;
        return this;
    }

    @property ref FbIscFieldInfo field(size_t index) nothrow return
    {
        return _fields[index];
    }

    @property FbIscFieldInfo[] fields() nothrow return
    {
        return _fields;
    }

    @property size_t length() const nothrow
    {
        return _fields.length;
    }

public:
    int32 selectOrBind; // FbIsc.isc_info_sql_select or FbIsc.isc_info_sql_bind

private:
    FbIscFieldInfo[] _fields;
}

struct FbIscBlobSize
{
@safe:

public:
    this(int32 maxSegment, int32 segmentCount, int32 length) nothrow pure
    {
        this.maxSegment = maxSegment;
        this.segmentCount = segmentCount;
        this.length = length;
    }

    this(scope const(ubyte)[] payload)
    {
        if (payload.length <= 2)
            return;

        const endPos = payload.length - 2; // -2 for item length
        size_t pos = 0;
        while (pos < endPos)
        {
            const typ = payload[pos++];
            if (typ == FbIsc.isc_info_end)
                break;

            const len = parseInt32!true(payload, pos, 2, typ);
            switch (typ)
            {
                case FbIsc.isc_info_blob_max_segment:
                    this.maxSegment = parseInt32!true(payload, pos, len, typ);
                    break;

                case FbIsc.isc_info_blob_num_segments:
                    this.segmentCount = parseInt32!true(payload, pos, len, typ);
                    break;

                case FbIsc.isc_info_blob_total_length:
                    this.length = parseInt32!true(payload, pos, len, typ);
                    break;

                default:
                    pos = payload.length; // break out while loop because of garbage
                    break;
            }
        }

        version (TraceFunction) dgFunctionTrace("maxSegment=", maxSegment, ", segmentCount=", segmentCount, ", length=", length);
    }

    ref typeof(this) reset() nothrow pure return
    {
        maxSegment = 0;
        segmentCount = 0;
        length = 0;
        return this;
    }

    @property bool isInitialized() const nothrow pure
    {
        return maxSegment != 0 || segmentCount != 0 || length != 0;
    }

public:
    int32 maxSegment;
    int32 segmentCount;
    int32 length;
}

alias FbIscCondAcceptResponse = FbIscAcceptDataResponse;

struct FbIscCondAuthResponse
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
    this(const(ubyte)[] data) pure
    {
        this.data = data;
    }

public:
    const(ubyte)[] data;
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
				return to!string(_intParam);
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
        switch (type)
        {
			case FbIsc.isc_arg_number:
			case FbIsc.isc_arg_string:
			case FbIsc.isc_arg_cstring:
				return true;
			default:
				return false;
		}
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

struct FbIscFieldInfo
{
nothrow @safe:

public:
    bool opCast(C: bool)() const @nogc pure
    {
        return type != 0 && name.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    FbIscFieldInfo opCast(T)() const
    if (is(Unqual!T == FbIscFieldInfo))
    {
        return this;
    }

    DbBaseType baseType() @nogc pure
    {
        return DbBaseType(numericScale, size, subType, type);
    }

	static FbIscType blrTypeToIscType(int32 blrType) @nogc pure
	{
		switch (blrType)
		{
			case FbBlrType.blr_short:
				return FbIscType.SQL_SHORT;
			case FbBlrType.blr_long:
				return FbIscType.SQL_LONG;
			case FbBlrType.blr_quad:
				return FbIscType.SQL_QUAD;
			case FbBlrType.blr_float:
				return FbIscType.SQL_FLOAT;
			case FbBlrType.blr_d_float:
				return FbIscType.SQL_D_FLOAT;
			case FbBlrType.blr_sql_date:
				return FbIscType.SQL_DATE;
			case FbBlrType.blr_sql_time:
				return FbIscType.SQL_TIME;
			case FbBlrType.blr_text:
			case FbBlrType.blr_text2:
			case FbBlrType.blr_cstring:
			case FbBlrType.blr_cstring2:
				return FbIscType.SQL_TEXT;
			case FbBlrType.blr_int64:
			case FbBlrType.blr_blob_id:
				return FbIscType.SQL_INT64;
			case FbBlrType.blr_blob2:
			case FbBlrType.blr_blob:
				return FbIscType.SQL_BLOB;
			case FbBlrType.blr_bool:
				return FbIscType.SQL_BOOLEAN;
			case FbBlrType.blr_dec64:
				return FbIscType.SQL_DEC64;
			case FbBlrType.blr_dec128:
				return FbIscType.SQL_DEC128;
			case FbBlrType.blr_int128:
				return FbIscType.SQL_INT128;
			case FbBlrType.blr_double:
				return FbIscType.SQL_DOUBLE;
            case FbBlrType.blr_sql_time_tz:
				return FbIscType.SQL_TIME_TZ;
	        case FbBlrType.blr_timestamp_tz:
				return FbIscType.SQL_TIMESTAMP_TZ;
	        case FbBlrType.blr_ex_time_tz:
				return FbIscType.SQL_TIME_TZ_EX;
	        case FbBlrType.blr_ex_timestamp_tz:
				return FbIscType.SQL_TIMESTAMP_TZ_EX;
			case FbBlrType.blr_timestamp:
				return FbIscType.SQL_TIMESTAMP;
			case FbBlrType.blr_varying:
			case FbBlrType.blr_varying2:
				return FbIscType.SQL_VARYING;
			default:
                return FbIscType.SQL_NULL; // Unknown
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
        return dbType(type, subType, numericScale);
    }

    static DbType dbType(int32 iscType, int32 iscSubtype, int32 iscScale) @nogc pure
    {
        const t = fbType(iscType);

        DbType result = DbType.unknown;
        if (auto e = t in fbIscTypeToDbTypeInfos)
            result = (*e).dbType;

        if (iscSubtype == 1 && t == FbIscType.SQL_BLOB)
            result = DbType.text;

        if (iscScale != 0)
        {
            switch (t)
            {
		        case FbIscType.SQL_SHORT:
		        case FbIscType.SQL_LONG:
                    result = DbType.decimal32;
                    break;
		        case FbIscType.SQL_QUAD:
		        case FbIscType.SQL_INT64:
                    result = DbType.decimal64;
                    break;
                default:
                    break;
            }
        }

        return result;
    }

    int32 dbTypeSize() const @nogc pure
    {
        return dbTypeSize(dbType(), size);
    }

    static int32 dbTypeSize(DbType dbType, int32 iscSize) @nogc pure
    {
        int32 result = -1;
        if (auto e = dbType in dbTypeToDbTypeInfos)
            result = (*e).nativeSize;
        return result != -1 ? result : iscSize;
    }

    int32 dbTypeDisplaySize() const @nogc pure
    {
        return dbTypeDisplaySize(type, size);
    }

    static int32 dbTypeDisplaySize(int32 iscType, int32 iscSize) @nogc pure
    {
        int32 result = -1;
        if (auto e = fbType(iscType) in fbIscTypeToDbTypeInfos)
            result = (*e).displaySize;
        return result == -1 ? iscSize : result;
    }

    pragma(inline, true)
    static bool fbAllowNull(int32 iscType) @nogc pure
    {
        return (iscType & 0x1) != 0;
    }

    pragma(inline, true)
    FbIscType fbType() const @nogc pure
    {
        return fbType(type);
    }

    pragma(inline, true)
    static FbIscType fbType(int32 iscType) @nogc pure
    {
        return cast(FbIscType)(iscType & ~0x1);
    }

    string fbTypeName() const pure
    {
        return fbTypeName(type);
    }

    static string fbTypeName(int32 iscType) pure
    {
        if (auto e = fbType(iscType) in fbIscTypeToDbTypeInfos)
            return (*e).nativeName;
        else
            return null;
    }

    int32 fbTypeSize() const @nogc pure
    {
        return fbTypeSize(type, size);
    }

    static int32 fbTypeSize(int32 iscType, int32 iscSize) @nogc pure
    {
        int32 result = -1;
        if (auto e = fbType(iscType) in fbIscTypeToDbTypeInfos)
            result = (*e).nativeSize;
        return result == -1 ? iscSize : result;
    }

    bool hasNumericScale() const @nogc pure
    {
        return hasNumericScale(type, numericScale);
    }

    static bool hasNumericScale(int32 iscType, int32 iscScale) @nogc pure
    {
        const t = fbType(iscType);
	    return (iscScale != 0) &&
            (t == FbIscType.SQL_SHORT ||
             t == FbIscType.SQL_LONG ||
             t == FbIscType.SQL_QUAD ||
             t == FbIscType.SQL_INT64 ||
             //t == FbIscType.SQL_DEC_FIXED ||
             t == FbIscType.SQL_DEC64 ||
             t == FbIscType.SQL_DEC128
            );
    }

    static DbFieldIdType isIdType(int32 iscType, int32 iscSubType) @nogc pure
    {
        switch (fbType(iscType))
        {
            case FbIscType.SQL_BLOB:
                return iscSubType != 1 ? DbFieldIdType.blob : DbFieldIdType.clob;
            case FbIscType.SQL_ARRAY:
                return DbFieldIdType.array;
            default:
                return DbFieldIdType.no;
        }
    }

    const(char)[] useName() const pure
    {
        return aliasName.length ? aliasName : name;
    }

    @property bool allowNull() const pure
    {
        return fbAllowNull(type);
    }

    @property ref typeof(this) allowNull(bool value) return
    {
        if (value)
            type |= 0x1;
        else
            type ^= 0x1;
        return this;
    }

public:
    const(char)[] aliasName;
    const(char)[] name;
    const(char)[] owner;
    const(char)[] tableName;
    int32 numericScale;
    int32 size;
    int32 subType;
    int32 type;
}

struct FbIscGenericResponse
{
nothrow @safe:

public:
    this(FbHandle handle, FbId id, ubyte[] data, FbIscStatues statues) pure
    {
        this.handle = handle;
        this.id = id;
        this.data = data;
        this.statues = statues;
    }

    FbIscObject getIscObject() const pure
    {
        return FbIscObject(handle, id);
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
    if (is(T == bool) || is(T == int) || is(T == string) || is(T == const(char)[]))
    {
        this.value = value;
    }

    T get(T)()
    if (is(T == bool) || is(T == int) || is(T == string) || is(T == const(char)[]))
    {
        static if (is(T == bool))
            return asBool();
        else static if (is(T == int))
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

            const len = parseInt32!true(payload, pos, 2, typ);
            switch (typ)
            {
			    // Database characteristics

    		    // Number of database pages allocated
			    case FbIsc.isc_info_allocation:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Database version (level) number:
			        1 byte containing the number 1
			        1 byte containing the version number
			    */
			    case FbIsc.isc_info_base_level:
                    parseCheckLength(payload, pos, 2, typ);
				    result ~= FbIscInfo(toVersionString([payload[pos], payload[pos + 1]]));
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
                    int len2 = parseInt32!true(payload, pos2, 1, typ);
                    auto dbFile = parseString!true(payload, pos2, len2, typ);

                    len2 = parseInt32!true(payload, pos2, 1, typ);
                    auto siteName = parseString!false(payload, pos2, len2, typ);
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
				    break;

			    /** 0 or 1
			        0 indicates space is reserved on each database page for holding
			          backup versions of modified records [Default]
			        1 indicates no space is reserved for such records
			    */
			    case FbIsc.isc_info_no_reserve:
				    result ~= FbIscInfo(parseBool!false(payload, pos, typ));
				    break;

			    /** ODS major version number
			        _ Databases with different major version numbers have different
			        physical layouts; a database engine can only access databases
			        with a particular ODS major version number
			        _ Trying to attach to a database with a different ODS number
			        results in an error
			    */
			    case FbIsc.isc_info_ods_version:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** On-disk structure (ODS) minor version number; an increase in a
				    minor version number indicates a non-structural change, one that
				    still allows the database to be accessed by database engines with
				    the same major version number but possibly different minor
				    version numbers
			    */
			    case FbIsc.isc_info_ods_minor_version:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Number of bytes per page of the attached database; use with
				    isc_info_allocation to determine the size of the database
			    */
			    case FbIsc.isc_info_page_size:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Version identification string of the database implementation:
				    1 byte containing the number number of message
				    1 byte specifying the length, of the following string
				    n bytes containing the string
			    */
			    case FbIsc.isc_info_version:
			    case FbIsc.isc_info_firebird_version:
                    uint msgCount = parseInt32!false(payload, pos, 1, typ);
                    auto pos2 = pos + 1;
                    while (msgCount--)
				    {
                        const len2 = parseInt32!true(payload, pos2, 1, typ);
                        result ~= FbIscInfo(parseString!true(payload, pos2, len2, typ));
				    }
				    break;

			    // Environmental characteristics

			    // Amount of server memory (in bytes) currently in use
			    case FbIsc.isc_info_current_memory:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Number specifying the mode in which database writes are performed
				    0 for asynchronous
                    1 for synchronous
			    */
			    case FbIsc.isc_info_forced_writes:
				    result ~= FbIscInfo(parseBool!false(payload, pos, typ));
				    break;

			    /** Maximum amount of memory (in bytes) used at one time since the first
			        process attached to the database
			    */
			    case FbIsc.isc_info_max_memory:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of memory buffers currently allocated
			    case FbIsc.isc_info_num_buffers:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Number of transactions that are committed between sweeps to
			        remove database record versions that are no longer needed
		        */
			    case FbIsc.isc_info_sweep_interval:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Performance statistics

			    // Number of reads from the memory data cache
			    case FbIsc.isc_info_fetches:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of writes to the memory data cache
			    case FbIsc.isc_info_marks:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of page reads
			    case FbIsc.isc_info_reads:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of page writes
			    case FbIsc.isc_info_writes:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Database operation counts

			    // Number of removals of a version of a record
			    case FbIsc.isc_info_backout_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of database deletes since the database was last attached
			    case FbIsc.isc_info_delete_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Number of removals of a record and all of its ancestors, for records
			        whose deletions have been committed
			    */
			    case FbIsc.isc_info_expunge_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of inserts into the database since the database was last attached
			    case FbIsc.isc_info_insert_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of removals of old versions of fully mature records
			    case FbIsc.isc_info_purge_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of reads done via an index since the database was last attached
			    case FbIsc.isc_info_read_idx_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    /** Number of sequential sequential table scans (row reads) done on each
			        table since the database was last attached
			    */
			    case FbIsc.isc_info_read_seq_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

    		    // Number of database updates since the database was last attached
			    case FbIsc.isc_info_update_count:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Misc

			    case FbIsc.isc_info_db_class:
				    const serverClass = parseInt32!false(payload, pos, len, typ);
                    string serverText = serverClass == FbIsc.isc_info_db_class_classic_access
					        ? FbIscText.isc_info_db_class_classic_text
                            : FbIscText.isc_info_db_class_server_text;
				    result ~= FbIscInfo(serverText);
				    break;

			    case FbIsc.isc_info_db_read_only:
				    result ~= FbIscInfo(parseBool!false(payload, pos, typ));
				    break;

                // Database size in pages
			    case FbIsc.isc_info_db_size_in_pages:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

                // Number of oldest transaction
			    case FbIsc.isc_info_oldest_transaction:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

                // Number of oldest active transaction
			    case FbIsc.isc_info_oldest_active:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

                // Number of oldest snapshot transaction
			    case FbIsc.isc_info_oldest_snapshot:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of next transaction
			    case FbIsc.isc_info_next_transaction:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

			    // Number of active	transactions
			    case FbIsc.isc_info_active_transactions:
				    result ~= FbIscInfo(parseInt32!false(payload, pos, len, typ));
				    break;

    		    // Active user name
			    case FbIsc.isc_info_user_names:
                    const uint len2 = parseInt32!false(payload, pos, 1, typ);
				    result ~= FbIscInfo(parseString!false(payload, pos + 1, len2, typ));
				    break;

                default:
                    break;
            }
            pos += len;
        }

        return result;
    }

    const(char)[] toString() nothrow
    {
        return asString();
    }

private:
    bool asBool() nothrow
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

    int asInt()
    {
        switch (value.variantType)
        {
            case VariantType.boolean:
                return *value.peek!bool() ? 1 : 0;
            case VariantType.integer:
                return *value.peek!int();
            case VariantType.string:
                auto s = *value.peek!string();
                if (s.length)
                    return to!int(s);
                else
                    return 0;
            case VariantType.dynamicArray: // const(char)[]
                auto s2 = *value.peek!(const(char)[])();
                if (s2.length)
                    return to!int(s2);
                else
                    return 0;
            default:
                assert(0);
        }
    }

    const(char)[] asString() nothrow
    {
        switch (value.variantType)
        {
            case VariantType.boolean:
                return *value.peek!bool() ? dbBoolTrue : dbBoolFalse;
            case VariantType.integer:
                return to!string(*value.peek!int());
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
nothrow @safe:

public:
    this(FbHandle handle, FbId id) pure
    {
        this._handleStorage = handle;
        this._idStorage = id;
    }

    void reset() pure
    {
        _handleStorage.reset();
        _idStorage.reset();
    }

    void resetHandle() pure
    {
        _handleStorage.reset();
    }

    @property bool hasHandle() const pure
    {
        return _handleStorage.isValid;
    }

    @property FbHandle handle() const pure
    {
        return _handleStorage.get!FbHandle();
    }

    @property ref FbIscObject handle(const FbHandle newValue) pure return
    {
        _handleStorage = newValue;
        return this;
    }

    @property FbId id() const pure
    {
        return _idStorage.get!FbId();
    }

    @property ref FbIscObject id(const FbId newValue) pure return
    {
        _idStorage = newValue;
        return this;
    }

private:
    DbHandle _handleStorage;
    DbHandle _idStorage = DbHandle(0);
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
    void buildMessage(out string errorMessage, out int32 errorCode)
    {
        version (TraceFunction) dgFunctionTrace();

        errorMessage = "";
        errorCode = 0;
        foreach (ref error; errors)
        {
            switch (error.type)
            {
                case FbIsc.isc_arg_gds:
                    errorCode = error.code;
                    errorMessage ~= error.str();
                    break;
                case FbIsc.isc_arg_number:
                case FbIsc.isc_arg_string:
                case FbIsc.isc_arg_cstring:
                    auto marker = "@" ~ to!string(error.argNumber);
                    errorMessage = errorMessage.replace(marker, error.str());
                    break;
                case FbIsc.isc_arg_interpreted:
                case FbIsc.isc_arg_sql_state:
                    errorMessage ~= error.str();
                    break;
                default:
                    break;
            }
        }
    }

    int getWarn(ref DbNotificationMessage[] messages)
    {
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
                        auto marker = "@" ~ to!string(error.argNumber);
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
        return result;
    }

    int32 errorCode() const pure
    {
        foreach (ref error; errors)
        {
            if (error.type == FbIsc.isc_arg_gds)
                return error.code;
        }
        return 0;
    }

    void put(FbIscError error) pure
    {
        if (errors.length == 0)
            errors.reserve(FbIscSize.iscStatusLength);
        errors ~= error;
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

	@property bool hasWarn() const pure
	{
        foreach (ref error; errors)
        {
            if (error.isWarning)
                return true;
        }
        return false;
	}

	@property bool isError() const pure
	{
        return errorCode() != 0;
	}

public:
    FbIscError[] errors;
    int32 sqlCode;
}

struct FbIscTrustedAuthResponse
{
nothrow @safe:

public:
    this(ubyte[] data) pure
    {
        this.data = data;
    }

public:
    ubyte[] data;

}

struct FbCommandPlanInfo
{
@safe:

public:
    enum Kind : byte
    {
        noData,
        empty,
        truncated,
        ok
    }

public:
    this(Kind kind, const(char)[] plan) nothrow pure
    {
        this.kind = kind;
        this.plan = plan;
    }

    this(Kind kind, const(ubyte)[] payload, FbIsc describeMode) pure
    {
        this.kind = kind;
        const len = parseInt32!false(payload, 1, 2, describeMode);
        this.plan = len > 0
            ? parseString!false(payload, 3, len, describeMode)
            : "";
    }

public:
    const(char)[] plan;
    Kind kind;
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

version (none)
class FbResponse
{
nothrow @safe:

public:
    this(FbOperation operation) pure
    {
        this._operation = operation;
    }

    this(FbOperation operation, FbIscGenericResponse generic) pure @trusted
    {
        this._operation = operation;
        this.generic = generic;
    }

    this(FbOperation operation, FbIscTrustedAuthenticationResponse trustedAuthentication) pure @trusted
    {
        this._operation = operation;
        this.trustedAuthentication = trustedAuthentication;
    }

    this(FbOperation operation, FbIscCryptKeyCallbackResponse cryptKeyCallback) pure @trusted
    {
        this._operation = operation;
        this.cryptKeyCallback = cryptKeyCallback;
    }

    this(FbOperation operation, FbIscFetchResponse fetch) pure @trusted
    {
        this._operation = operation;
        this.fetch = fetch;
    }

    this(FbOperation operation, FbIscSqlResponse sql) pure @trusted
    {
        this._operation = operation;
        this.sql = sql;
    }

    @property FbOperation operation() const
    {
        return _operation;
    }

public:
    union
    {
        FbIscGenericResponse generic;
        FbIscTrustedAuthenticationResponse trustedAuthentication;
        FbIscCryptKeyCallbackResponse cryptKeyCallback;
        FbIscFetchResponse fetch;
        FbIscSqlResponse sql;
    }

private:
    FbOperation _operation;
}

bool parseBool(bool Advance)(scope const(ubyte)[] data, size_t index, int type) pure
if (Advance == false)
{
    parseCheckLength(data, index, 1, type);
    return parseBoolImpl(data, index);
}

int parseBool(bool Advance)(scope const(ubyte)[] data, ref size_t index, int type) pure
if (Advance == true)
{
    parseCheckLength(data, index, 1, type);
    return parseBoolImpl(data, index);
}

pragma(inline, true)
private bool parseBoolImpl(scope const(ubyte)[] data, ref size_t index) nothrow pure
{
    return data[index++] == 1;
}

pragma(inline, true)
void parseCheckLength(scope const(ubyte)[] data, size_t index, uint length, int type) pure
{
    if (index + length > data.length)
    {
        auto msg = format(DbMessage.eInvalidSQLDANotEnoughData, type, length);
        throw new FbException(msg, DbErrorCode.read, 0, FbIscResultCode.isc_dsql_sqlda_err);
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

		const len = parseInt32!true(data, pos, 2, typ);
		switch (typ)
		{
			case FbIsc.isc_info_sql_stmt_type:
				return cast(FbIscCommandType)parseInt32!true(data, pos, len, typ);

			default:
                pos += len;
				break;
		}
	}

	return FbIscCommandType.none;
}

int32 parseInt32(bool Advance)(scope const(ubyte)[] data, size_t index, uint length, int type) pure
if (Advance == false)
{
    parseCheckLength(data, index, length, type);
    return parseInt32Impl(data, index, length);
}

int32 parseInt32(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length, int type) pure
if (Advance == true)
{
    parseCheckLength(data, index, length, type);
    return parseInt32Impl(data, index, length);
}

private int32 parseInt32Impl(scope const(ubyte)[] data, ref size_t index, uint length) nothrow pure
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
int64 parseInt64(bool Advance)(scope const(ubyte)[] data, size_t index, uint length, int type) pure
if (Advance == false)
{
    parseCheckLength(data, index, length, type);
    return parseInt64Impl(data, index, length);
}

version (none)
int64 parseInt64(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length, int type) pure
if (Advance == true)
{
    parseCheckLength(data, index, length, type);
    return parseInt64Impl(data, index, length);
}

version (none)
private int64 parseInt64Impl(bool Advance)(scope const(ubyte)[] data, ref size_t index, uint length) nothrow pure
{
	int64 result = 0;
	uint shift = 0;
	while (length--)
	{
		result += cast(int64)data[index++] << shift;
		shift += 8;
	}
	return result;
}

const(char)[] parseString(bool Advance)(const(ubyte)[] data, size_t index, uint length, int type) pure
if (Advance == false)
{
    parseCheckLength(data, index, length, type);
    return parseStringImpl(data, index, length);
}

const(char)[] parseString(bool Advance)(const(ubyte)[] data, ref size_t index, uint length, int type) pure
if (Advance == true)
{
    parseCheckLength(data, index, length, type);
    return parseStringImpl(data, index, length);
}

pragma(inline, true)
private const(char)[] parseStringImpl(const(ubyte)[] data, ref size_t index, uint length) nothrow pure
{
    if (length)
    {
        const(char)[] result = cast(const(char)[])data[index..index + length];
        index += length;
        return result;
    }
    else
        return null;
}


// Any below codes are private
private:

version (unittest)
enum countOfFbIscType = EnumMembers!FbIscType.length;

shared static this() nothrow
{
    fbDefaultParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbParameterName.port : "3050",
            DbParameterName.userName : "SYSDBA",
            DbParameterName.userPassword : "masterkey",
            DbParameterName.fbCachePage : "0", // 0=Not used/set
            DbParameterName.fbDialect : "3",
            DbParameterName.fbDatabaseTrigger : dbBoolTrue,
            DbParameterName.fbDummyPacketInterval : "300",  // In seconds, 5 minutes
            DbParameterName.fbGarbageCollect : dbBoolTrue
        ];
    }();

    fbIscTypeToDbTypeInfos = () nothrow pure
    {
        immutable(DbTypeInfo)*[int32] result;
        foreach (ref e; fbNativeTypes)
        {
            result[e.nativeId] = &e;
        }
        return result;
    }();
}

unittest // FbIscBlobSize
{
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest("unittest db.fbtype.FbIscBlobSize");

    auto info = bytesFromHexs("05040004000000040400010000000604000400000001");
    auto parsedSize = FbIscBlobSize(info);
    assert(parsedSize.maxSegment == 4);
    assert(parsedSize.segmentCount == 1);
    assert(parsedSize.length == 4);
}

unittest // FbIscBindInfo
{
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest("unittest db.fbtype.FbIscBindInfo");

    FbIscBindInfo[] bindResults;
    ptrdiff_t previousBindIndex = -1;
    ptrdiff_t previousFieldIndex;
    auto info = bytesFromHexs("040704000D000000090400010000000B0400F00100000C0400000000000E0400040000000D040000000000100900494E545F4649454C44110B00544553545F53454C454354130900494E545F4649454C4408090400020000000B0400F50100000C0400000000000E0400020000000D040000000000100E00534D414C4C494E545F4649454C44110B00544553545F53454C454354130E00534D414C4C494E545F4649454C4408090400030000000B0400E30100000C0400000000000E0400040000000D040000000000100B00464C4F41545F4649454C44110B00544553545F53454C454354130B00464C4F41545F4649454C4408090400040000000B0400E10100000C0400000000000E0400080000000D040000000000100C00444F55424C455F4649454C44110B00544553545F53454C454354130C00444F55424C455F4649454C4408090400050000000B0400450200000C0400010000000E0400080000000D0400FEFFFFFF100D004E554D455249435F4649454C44110B00544553545F53454C454354130D004E554D455249435F4649454C4408090400060000000B0400450200000C0400020000000E0400080000000D0400FEFFFFFF100D00444543494D414C5F4649454C44110B00544553545F53454C454354130D00444543494D414C5F4649454C4408090400070000000B04003B0200000C0400000000000E0400040000000D040000000000100A00444154455F4649454C44110B00544553545F53454C454354130A00444154455F4649454C4408090400080000000B0400310200000C0400000000000E0400040000000D040000000000100A0054494D455F4649454C44110B00544553545F53454C454354130A0054494D455F4649454C4408090400090000000B0400FF0100000C0400000000000E0400080000000D040000000000100F0054494D455354414D505F4649454C44110B00544553545F53454C454354130F0054494D455354414D505F4649454C44080904000A0000000B0400C50100000C0400040000000E0400280000000D040000000000100A00434841525F4649454C44110B00544553545F53454C454354130A00434841525F4649454C44080904000B0000000B0400C10100000C0400040000000E0400280000000D040000000000100D00564152434841525F4649454C44110B00544553545F53454C454354130D00564152434841525F4649454C44080904000C0000000B0400090200000C0400000000000E0400080000000D040000000000100A00424C4F425F4649454C44110B00544553545F53454C454354130A00424C4F425F4649454C44080904000D0000000B0400090200000C0400010000000E0400080000000D040004000000100A00544558545F4649454C44110B00544553545F53454C454354130A00544558545F4649454C4408050704000000000001");
    auto parsed = FbIscBindInfo.parse(info, bindResults, previousBindIndex, previousFieldIndex);
    assert(parsed == true);
    assert(bindResults.length == 2);

    assert(bindResults[0].selectOrBind == FbIsc.isc_info_sql_select);
    assert(bindResults[0].length == 13);
    auto field = bindResults[0].field(0);
    assert(field.name == "INT_FIELD" && field.type == 496 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "INT_FIELD");
    field = bindResults[0].field(1);
    assert(field.name == "SMALLINT_FIELD" && field.type == 501 && field.subType == 0 && field.numericScale == 0 && field.size == 2 && field.tableName == "TEST_SELECT" && field.aliasName == "SMALLINT_FIELD");
    field = bindResults[0].field(2);
    assert(field.name == "FLOAT_FIELD" && field.type == 483 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "FLOAT_FIELD");
    field = bindResults[0].field(3);
    assert(field.name == "DOUBLE_FIELD" && field.type == 481 && field.subType == 0 && field.numericScale == 0 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "DOUBLE_FIELD");
    field = bindResults[0].field(4);
    assert(field.name == "NUMERIC_FIELD" && field.type == 581 && field.subType == 1 && field.numericScale == -2 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "NUMERIC_FIELD");
    field = bindResults[0].field(5);
    assert(field.name == "DECIMAL_FIELD" && field.type == 581 && field.subType == 2 && field.numericScale == -2 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "DECIMAL_FIELD");
    field = bindResults[0].field(6);
    assert(field.name == "DATE_FIELD" && field.type == 571 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "DATE_FIELD");
    field = bindResults[0].field(7);
    assert(field.name == "TIME_FIELD" && field.type == 561 && field.subType == 0 && field.numericScale == 0 && field.size == 4 && field.tableName == "TEST_SELECT" && field.aliasName == "TIME_FIELD");
    field = bindResults[0].field(8);
    assert(field.name == "TIMESTAMP_FIELD" && field.type == 511 && field.subType == 0 && field.numericScale == 0 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "TIMESTAMP_FIELD");
    field = bindResults[0].field(9);
    assert(field.name == "CHAR_FIELD" && field.type == 453 && field.subType == 4 && field.numericScale == 0 && field.size == 40 && field.tableName == "TEST_SELECT" && field.aliasName == "CHAR_FIELD");
    field = bindResults[0].field(10);
    assert(field.name == "VARCHAR_FIELD" && field.type == 449 && field.subType == 4 && field.numericScale == 0 && field.size == 40 && field.tableName == "TEST_SELECT" && field.aliasName == "VARCHAR_FIELD");
    field = bindResults[0].field(11);
    assert(field.name == "BLOB_FIELD" && field.type == 521 && field.subType == 0 && field.numericScale == 0 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "BLOB_FIELD");
    field = bindResults[0].field(12);
    assert(field.name == "TEXT_FIELD" && field.type == 521 && field.subType == 1 && field.numericScale == 4 && field.size == 8 && field.tableName == "TEST_SELECT" && field.aliasName == "TEXT_FIELD");

    assert(bindResults[1].selectOrBind == FbIsc.isc_info_sql_bind);
    assert(bindResults[1].length == 0);
}
