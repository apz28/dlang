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

version (TraceFunction) import pham.utl.utltest;
import pham.utl.variant;
import pham.db.message;
import pham.db.type;
import pham.db.fbisc;
import pham.db.fbmessage;

nothrow @safe:

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
    {dbName:"", nativeName:"VARCHAR", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_VARYING, dbType:DbType.string}, //varchar
    {dbName:"", nativeName:"CHAR", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_TEXT, dbType:DbType.chars}, //char[]
    {dbName:"", nativeName:"DOUBLE", displaySize:17, nativeSize:8, nativeId:FbIscType.SQL_DOUBLE, dbType:DbType.float64},
    {dbName:"", nativeName:"FLOAT", displaySize:17, nativeSize:4, nativeId:FbIscType.SQL_FLOAT, dbType:DbType.float32},
    {dbName:"", nativeName:"LONG", displaySize:11, nativeSize:4, nativeId:FbIscType.SQL_LONG, dbType:DbType.int32},
    {dbName:"", nativeName:"SHORT", displaySize:6, nativeSize:2, nativeId:FbIscType.SQL_SHORT, dbType:DbType.int16},
    {dbName:"", nativeName:"TIMESTAMP", displaySize:22, nativeSize:8, nativeId:FbIscType.SQL_TIMESTAMP, dbType:DbType.datetime},
    {dbName:"", nativeName:"BLOB", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_BLOB, dbType:DbType.binary},
    {dbName:"", nativeName:"DOUBLE", displaySize:17, nativeSize:8, nativeId:FbIscType.SQL_D_FLOAT, dbType:DbType.float64},
    {dbName:"", nativeName:"ARRAY", displaySize:-1, nativeSize:-1, nativeId:FbIscType.SQL_ARRAY, dbType:DbType.array},
    {dbName:"", nativeName:"QUAD", displaySize:20, nativeSize:8, nativeId:FbIscType.SQL_QUAD, dbType:DbType.int64},
    {dbName:"", nativeName:"TIME", displaySize:11, nativeSize:4, nativeId:FbIscType.SQL_TIME, dbType:DbType.time},
    {dbName:"", nativeName:"DATE", displaySize:10, nativeSize:4, nativeId:FbIscType.SQL_DATE, dbType:DbType.date},
    {dbName:"", nativeName:"INT64", displaySize:20, nativeSize:8, nativeId:FbIscType.SQL_INT64, dbType:DbType.int64},
    {dbName:"", nativeName:"INT128", displaySize:40, nativeSize:16, nativeId:FbIscType.SQL_INT128, dbType:DbType.int128},
    {dbName:"", nativeName:"TIMESTAMP WITH TIMEZONE", displaySize:28, nativeSize:10, nativeId:FbIscType.SQL_TIMESTAMP_TZ, dbType:DbType.datetimeTZ},
    {dbName:"", nativeName:"TIMESTAMP WITH OFFSET TIMEZONE", displaySize:28, nativeSize:10, nativeId:FbIscType.SQL_TIMESTAMP_TZ_EX, dbType:DbType.datetimeTZ},
    {dbName:"", nativeName:"TIME WITH TIMEZONE", displaySize:17, nativeSize:6, nativeId:FbIscType.SQL_TIME_TZ, dbType:DbType.timeTZ},
    {dbName:"", nativeName:"TIME WITH OFFSET TIMEZONE", displaySize:17, nativeSize:6, nativeId:FbIscType.SQL_TIME_TZ_EX, dbType:DbType.timeTZ},
    //{dbName:"", nativeName:"DECFIXED", displaySize:34, nativeSize:16, nativeId:FbIscType.SQL_DEC_FIXED, dbType:DbType.decimal},
    {dbName:"", nativeName:"DECFLOAT(16)", displaySize:16, nativeSize:8, nativeId:FbIscType.SQL_DEC64, dbType:DbType.decimal64},
    {dbName:"", nativeName:"DECFLOAT(34)", displaySize:34, nativeSize:16, nativeId:FbIscType.SQL_DEC128, dbType:DbType.decimal128},
    {dbName:"", nativeName:"BOOLEAN", displaySize:5, nativeSize:1, nativeId:FbIscType.SQL_BOOLEAN, dbType:DbType.boolean},
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
    this(int32 version_, int32 architecture, int32 acceptType, ubyte[] authData,
        string authName, int32 authenticated, ubyte[] authKey)
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
    ubyte[] authData;
    ubyte[] authKey;
    string authName;
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
nothrow @safe:

public:
    this(size_t fieldCount) pure
    {
        this._fields = new FbIscFieldInfo[fieldCount];
    }

    bool opCast(To: bool)() const
    {
        return selectOrBind != 0 || length != 0;
    }

    void reset()
    {
        selectOrBind = 0;
        _fields = null;
    }

    @property ref FbIscFieldInfo field(size_t index) return
    {
        return _fields[index];
    }

    @property FbIscFieldInfo[] fields() return
    {
        return _fields;
    }

    @property size_t length() const
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
nothrow @safe:

public:
    void reset()
    {
        maxSegment = 0;
        segmentCount = 0;
        length = 0;
    }

    @property bool isInitialized() const
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
    this(ubyte[] data, string name, ubyte[] list, ubyte[] key) pure
    {
        this.data = data;
        this.name = name;
        this.list = list;
        this.key = key;
    }

public:
    ubyte[] data;
    ubyte[] key;
    ubyte[] list;
    string name;
}

struct FbIscCryptKeyCallbackResponse
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

    @property final int argNumber() const
    {
        return _argNumber;
    }

    @property final int32 code() const
    {
        return _intParam;
    }

    @property final int32 type() const
    {
        return _type;
    }

    @property final bool isArgument() const
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

	@property final bool isWarning() const
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
    bool opCast(C: bool)() const
    {
        return type != 0 && name.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    FbIscFieldInfo opCast(T)() const
    if (is(Unqual!T == FbIscFieldInfo))
    {
        return this;
    }

    DbBaseType baseType() pure
    {
        return DbBaseType(numericScale, size, subType, type);
    }

	static FbIscType blrTypeToIscType(int32 blrType) pure
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

    void reset()
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

    DbType dbType() const
    {
        return dbType(type, subType, numericScale);
    }

    static DbType dbType(int32 iscType, int32 iscSubtype, int32 iscScale) pure
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

    int32 dbTypeSize() const
    {
        return dbTypeSize(dbType(), size);
    }

    static int32 dbTypeSize(DbType dbType, int32 iscSize) pure
    {
        int32 result = -1;
        if (auto e = dbType in dbTypeToDbTypeInfos)
            result = (*e).nativeSize;
        return result != -1 ? result : iscSize;
    }

    int32 dbTypeDisplaySize() const
    {
        return dbTypeDisplaySize(type, size);
    }

    static int32 dbTypeDisplaySize(int32 iscType, int32 iscSize) pure
    {
        int32 result = -1;
        if (auto e = fbType(iscType) in fbIscTypeToDbTypeInfos)
            result = (*e).displaySize;
        return result == -1 ? iscSize : result;
    }

    static bool fbAllowNull(int32 iscType) pure
    {
        return (iscType & 0x1) != 0;
    }

    FbIscType fbType() const pure
    {
        return fbType(type);
    }

    static FbIscType fbType(int32 iscType) pure
    {
        return cast(FbIscType)(iscType & ~0x1);
    }

    string fbTypeName() const
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

    int32 fbTypeSize() const
    {
        return fbTypeSize(type, size);
    }

    static int32 fbTypeSize(int32 iscType, int32 iscSize) pure
    {
        int32 result = -1;
        if (auto e = fbType(iscType) in fbIscTypeToDbTypeInfos)
            result = (*e).nativeSize;
        return result == -1 ? iscSize : result;
    }

    bool hasNumericScale() const
    {
        return hasNumericScale(type, numericScale);
    }

    static bool hasNumericScale(int32 iscType, int32 iscScale) pure
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

    static DbFieldIdType isIdType(int32 iscType, int32 iscSubType) pure
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

    string useName() const
    {
        return aliasName.length ? aliasName : name;
    }

    @property bool allowNull() const
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
    string aliasName;
    string name;
    string owner;
    string tableName;
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
    if (is(T == bool) || is(T == int) || is(T == string))
    {
        this.value = value;
    }

    T get(T)()
    if (is(T == bool) || is(T == int) || is(T == string))
    {
        static if (is(T == bool))
            return asBool();
        else static if (is(T == int))
            return asInt();
        else static if (is(T == string))
            return asString();
        else
            static assert(0);
    }

    string toString() nothrow
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
                return *value.peek!string() == "1";
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
            default:
                assert(0);
        }
    }

    string asString() nothrow
    {
         switch (value.variantType)
         {
             case VariantType.boolean:
                 return *value.peek!bool() ? "1" : "0";
             case VariantType.integer:
                 return to!string(*value.peek!int());
             case VariantType.string:
                 return *value.peek!string();
             default:
                assert(0);
         }
    }

private:
    alias Value = Algebraic!(void, bool, int, string);
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
        foreach (ref i; errors)
        {
            switch (i.type)
            {
                case FbIsc.isc_arg_gds:
                    errorCode = i.code;
                    errorMessage ~= i.str();
                    break;
                case FbIsc.isc_arg_number:
                case FbIsc.isc_arg_string:
                case FbIsc.isc_arg_cstring:
                    auto marker = "@" ~ to!string(i.argNumber);
                    errorMessage = errorMessage.replace(marker, i.str());
                    break;
                case FbIsc.isc_arg_interpreted:
                case FbIsc.isc_arg_sql_state:
                    errorMessage ~= i.str();
                    break;
                default:
                    break;
            }
        }
    }

    final int32 errorCode() const
    {
        foreach (ref i; errors)
        {
            if (i.type == FbIsc.isc_arg_gds)
                return i.code;
        }

        return 0;
    }

    void put(FbIscError error)
    {
        if (errors.length == 0)
            errors.reserve(FbIscSize.iscStatusLength);

        errors ~= error;
    }

    string sqlState() const
    {
        foreach (ref i; errors)
        {
            if (i.type == FbIsc.isc_arg_sql_state)
                return i.str();
        }

        return FbSqlStates.get(errorCode);
    }

	@property final bool isError() const
	{
        return errorCode() != 0;
	}

	@property final bool isWarning() const
	{
        return errors.length && errors[0].isWarning;
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
nothrow @safe:

public:
    enum Kind : byte
    {
        noData,
        empty,
        truncated,
        ok
    }

public:
    this(Kind kind, string plan) pure
    {
        this.kind = kind;
        this.plan = plan;
    }

public:
    string plan;
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


// Any below codes are private
private:


version (unittest)
enum countOfFbIscType = EnumMembers!FbIscType.length;

shared static this()
{
    fbDefaultParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbParameterName.port : "3050",
            DbParameterName.userName : "SYSDBA",
            DbParameterName.userPassword : "masterkey",
            DbParameterName.fbCachePage : "0", // 0=Not used/set
            DbParameterName.fbDialect : "3",
            DbParameterName.fbDatabaseTrigger : dbBoolTrues[0],
            DbParameterName.fbDummyPacketInterval : "300",  // In seconds, 5 minutes
            DbParameterName.fbGarbageCollect : dbBoolTrues[0]
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
