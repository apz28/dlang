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

module pham.db.db_pgtype;

import core.time : dur;
import std.algorithm : startsWith;
import std.array : split;
import std.conv : to;

debug(debug_pham_db_db_pgtype) import std.stdio : writeln;

import pham.cp.cp_cipher : CipherHelper;
import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_enum_set : toName;
import pham.utl.utl_result : cmp;
import pham.db.db_convert : toIntegerSafe;
import pham.db.db_message;
import pham.db.db_type;
import pham.db.db_pgoid;

nothrow @safe:

alias PgOId = int32;
alias PgDescriptorId = int32;

enum pgNullValueLength = -1;

static immutable string pgAuthClearTextName = "ClearText";
static immutable string pgAuthMD5Name = "MD5";
static immutable string pgAuthScram256Name = "SCRAM-SHA-256";

static immutable DbConnectionParameterInfo[string] pgDefaultConnectionParameterValues;

static immutable string[] pgValidConnectionParameterNames = [
    // Primary
    DbConnectionParameterIdentifier.serverName,
    DbConnectionParameterIdentifier.serverPort,
    DbConnectionParameterIdentifier.databaseName,
    DbConnectionParameterIdentifier.userName,
    DbConnectionParameterIdentifier.userPassword,
    DbConnectionParameterIdentifier.roleName,
    DbConnectionParameterIdentifier.encrypt,
    DbConnectionParameterIdentifier.charset,
    //DbConnectionParameterIdentifier.compress,
    DbConnectionParameterIdentifier.encrypt,
    DbConnectionParameterIdentifier.integratedSecurity,

    // Other
    DbConnectionParameterIdentifier.connectionTimeout,
    DbConnectionParameterIdentifier.fetchRecordCount,
    DbConnectionParameterIdentifier.packageSize,
    DbConnectionParameterIdentifier.pooling,
    DbConnectionParameterIdentifier.receiveTimeout,
    DbConnectionParameterIdentifier.sendTimeout,
    DbConnectionParameterIdentifier.socketBlocking,

    /*
    DbConnectionParameterIdentifier.pgOptions,
    DbConnectionParameterIdentifier.pgPassFile,
    DbConnectionParameterIdentifier.pgFallbackApplicationName,
    DbConnectionParameterIdentifier.pgKeepAlives,
    DbConnectionParameterIdentifier.pgKeepalivesIdle,
    DbConnectionParameterIdentifier.pgKeepalivesInterval,
    DbConnectionParameterIdentifier.pgKeepalivesCount,
    DbConnectionParameterIdentifier.pgTty,
    DbConnectionParameterIdentifier.pgReplication,
    DbConnectionParameterIdentifier.pgGSSEncMode,
    DbConnectionParameterIdentifier.pgSSLCert,
    DbConnectionParameterIdentifier.pgSSLKey,
    DbConnectionParameterIdentifier.pgSSLRootCert,
    DbConnectionParameterIdentifier.pgSSLCrl,
    DbConnectionParameterIdentifier.pgRequirePeer,
    DbConnectionParameterIdentifier.pgKRBSrvName,
    DbConnectionParameterIdentifier.pgGSSLibib,
    DbConnectionParameterIdentifier.pgService,
    DbConnectionParameterIdentifier.pgTargetSessionAttrs,
    */
    ];

// https://www.postgresql.org/docs/12/libpq-connect.html#LIBPQ-PARAMKEYWORDS
static immutable string[string] pgMappedParameterNames;

static immutable DbTypeInfo[] pgNativeTypes = [
    {dbName:"bigint", dbType:DbType.int64, dbId:PgOIdType.int8, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"bool", dbType:DbType.boolean, dbId:PgOIdType.bool_, nativeName:"bool", nativeSize:DbTypeSize.boolean, displaySize:DbTypeDisplaySize.boolean},
    {dbName:"bytea", dbType:DbType.binaryVary, dbId:PgOIdType.bytea, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"char(?)", dbType:DbType.stringFixed, dbId:PgOIdType.bpchar, nativeName:"string", nativeSize:DbTypeSize.stringFixed, displaySize:DbTypeDisplaySize.stringFixed}, // Prefer multi chars[] over 1 char type
    {dbName:"char(1)", dbType:DbType.stringFixed, dbId:PgOIdType.char_, nativeName:"char", nativeSize:char.sizeof, displaySize:char.sizeof}, // Native 1 char
    {dbName:"date", dbType:DbType.date, dbId:PgOIdType.date, nativeName:"DbDate", nativeSize:DbTypeSize.date, displaySize:DbTypeDisplaySize.date},
    {dbName:"double precision", dbType:DbType.float64, dbId:PgOIdType.float8, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"integer", dbType:DbType.int32, dbId:PgOIdType.int4, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"json", dbType:DbType.json, dbId:PgOIdType.json, nativeName:"string", nativeSize:DbTypeSize.json, displaySize:DbTypeDisplaySize.json},
    {dbName:"money", dbType:DbType.decimal64, dbId:PgOIdType.money, nativeName:"Decimal", nativeSize:DbTypeSize.decimal64, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"name", dbType:DbType.stringVary, dbId:PgOIdType.name, nativeName:"string", nativeSize:DbTypeSize.stringFixed, displaySize:DbTypeDisplaySize.stringFixed},
    {dbName:"numeric(?,?)", dbType:DbType.decimal, dbId:PgOIdType.numeric, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal}, // Prefer numeric over money for generic setting
    {dbName:"oid", dbType:DbType.int32, dbId:PgOIdType.oid, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"real", dbType:DbType.float32, dbId:PgOIdType.float4, nativeName:"float32", nativeSize:DbTypeSize.float32, displaySize:DbTypeDisplaySize.float32},
    {dbName:"smallint", dbType:DbType.int16, dbId:PgOIdType.int2, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"text", dbType:DbType.text, dbId:PgOIdType.text, nativeName:"string", nativeSize:DbTypeSize.text, displaySize:DbTypeDisplaySize.text},
    {dbName:"time", dbType:DbType.time, dbId:PgOIdType.time, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},
    {dbName:"time with time zone", dbType:DbType.timeTZ, dbId:PgOIdType.timetz, nativeName:"DbTime", nativeSize:DbTypeSize.timeTZ, displaySize:DbTypeDisplaySize.timeTZ},
    {dbName:"timestamp", dbType:DbType.datetime, dbId:PgOIdType.timestamp, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"timestamp with time zone", dbType:DbType.datetimeTZ, dbId:PgOIdType.timestamptz, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetimeTZ, displaySize:DbTypeDisplaySize.datetimeTZ},
    {dbName:"uuid", dbType:DbType.uuid, dbId:PgOIdType.uuid, nativeName:"UUID", nativeSize:DbTypeSize.uuid, displaySize:DbTypeDisplaySize.uuid},
    {dbName:"varchar(?)", dbType:DbType.stringVary, dbId:PgOIdType.varchar, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary}, // Prefer vary chars[] over name
    {dbName:"xml", dbType:DbType.xml, dbId:PgOIdType.xml, nativeName:"string", nativeSize:DbTypeSize.xml, displaySize:DbTypeDisplaySize.xml},
    {dbName:"array_bool(?)", dbType:DbType.boolean|DbType.array, dbId:PgOIdType.array_bool, nativeName:"bool[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_bpchar(?)", dbType:DbType.stringFixed|DbType.array, dbId:PgOIdType.array_bpchar, nativeName:"string[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array}, // Prefer multi chars[] over 1 char type
    {dbName:"array_bytea(?)", dbType:DbType.binaryVary|DbType.array, dbId:PgOIdType.array_bytea, nativeName:"ubyte[][]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_char(?)", dbType:DbType.stringFixed|DbType.array, dbId:PgOIdType.array_char, nativeName:"char[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_date(?)", dbType:DbType.date|DbType.array, dbId:PgOIdType.array_date, nativeName:"DbDate[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_float4(?)", dbType:DbType.float32|DbType.array, dbId:PgOIdType.array_float4, nativeName:"float32[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_float8(?)", dbType:DbType.float64|DbType.array, dbId:PgOIdType.array_float8, nativeName:"float64[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_int2(?)", dbType:DbType.int16|DbType.array, dbId:PgOIdType.array_int2, nativeName:"int16[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array}, // Prefer native array over vector
    {dbName:"array_int4(?)", dbType:DbType.int32|DbType.array, dbId:PgOIdType.array_int4, nativeName:"int32[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array}, // Prefer native array over vector
    {dbName:"array_int8(?)", dbType:DbType.int64|DbType.array, dbId:PgOIdType.array_int8, nativeName:"int64[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_json(?)", dbType:DbType.stringVary|DbType.array, dbId:PgOIdType.array_json, nativeName:"string[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_money(?)", dbType:DbType.decimal|DbType.array, dbId:PgOIdType.array_money, nativeName:"Decimal[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_name(?)", dbType:DbType.stringVary|DbType.array, dbId:PgOIdType.array_name, nativeName:"string[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_numeric(?)", dbType:DbType.decimal|DbType.array, dbId:PgOIdType.array_numeric, nativeName:"Decimal[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array}, // Prefer numerice over money for generic setting
    {dbName:"array_oid(?)", dbType:DbType.int32|DbType.array, dbId:PgOIdType.array_oid, nativeName:"int32[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_text(?)", dbType:DbType.text|DbType.array, dbId:PgOIdType.array_text, nativeName:"string[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_time(?)", dbType:DbType.time|DbType.array, dbId:PgOIdType.array_time, nativeName:"DbTime[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_timestamp(?)", dbType:DbType.datetime|DbType.array, dbId:PgOIdType.array_timestamp, nativeName:"DbDateTime[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_timestamptz(?)", dbType:DbType.datetimeTZ|DbType.array, dbId:PgOIdType.array_timestamptz, nativeName:"DbDateTime[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_timetz(?)", dbType:DbType.timeTZ|DbType.array, dbId:PgOIdType.array_timetz, nativeName:"DbTime[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_uuid(?)", dbType:DbType.uuid|DbType.array, dbId:PgOIdType.array_uuid, nativeName:"UUID[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"array_varchar(?)", dbType:DbType.stringVary|DbType.array, dbId:PgOIdType.array_varchar, nativeName:"string[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array}, // Prefer vary chars[] over name
    {dbName:"array_xml(?)", dbType:DbType.stringVary|DbType.array, dbId:PgOIdType.array_xml, nativeName:"string[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"int2vector(?)", dbType:DbType.int16|DbType.array, dbId:PgOIdType.int2vector, nativeName:"int16[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"oidvector(?)", dbType:DbType.int32|DbType.array, dbId:PgOIdType.oidvector, nativeName:"int32[]", nativeSize:DbTypeSize.array, displaySize:DbTypeDisplaySize.array},
    {dbName:"", dbType:DbType.unknown, dbId:PgOIdType.void_, nativeName:"void", nativeSize:0, displaySize:4},
    ];

static immutable DbTypeInfo*[int32] pgDbIdToDbTypeInfos;

enum CanSendParameter
{
    no,
    yes,
    yesConvert,
}

/**
 * Encapsulating errors and notices.
 * $(LINK2 http://www.postgresql.org/docs/9.0/static/protocol-error-fields.html,here).
 */
struct PgGenericResponse
{
nothrow @safe:

public:
    this(string[char] typeValues,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) pure
    {
        this.typeValues = typeValues;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
    }

    uint errorCode() const
    {
        return 0;
    }

    string errorString() const
    {
        auto result = sqlSeverity ~ ' ' ~ sqlState ~ ": " ~ sqlMessage;

        auto s = detailMessage;
        if (s.length)
            result ~= "\n" ~ DbMessage.eErrorDetail ~ ": " ~ s;

        s = hint;
        if (s.length)
            result ~= "\n" ~ DbMessage.eErrorHint ~ ": " ~ s;

        return result;
    }

    string getOptional(char type) const
    {
        auto p = type in typeValues;
        return p ? *p : null;
    }

    int getWarn(ref DbNotificationMessage[] messages)
    {
        int result = 0;

        void addWarnMessage(string s) nothrow @safe
        {
            if (s.length)
            {
                messages ~= DbNotificationMessage(s, 0);
                result++;
            }
        }

        addWarnMessage(sqlMessage);
        addWarnMessage(detailMessage);
        addWarnMessage(hint);

        return result;
    }

    @property string sqlMessage() const
    {
        return typeValues[PgOIdDiag.messagePrimary];
    }

    @property string sqlSeverity() const
    {
        return typeValues[PgOIdDiag.severity];
    }

    @property string sqlState() const
    {
        return typeValues[PgOIdDiag.sqlState];
    }

    /* Optional Values */

    @property string detailMessage() const
    {
        return getOptional(PgOIdDiag.messageDetail);
    }

    @property string sqlFile() const
    {
        return getOptional(PgOIdDiag.sourceFile);
    }

    @property string hint() const
    {
        return getOptional(PgOIdDiag.messageHint);
    }

    @property string internalPosition() const
    {
        return getOptional(PgOIdDiag.internalPosition);
    }

    @property string internalQuery() const
    {
        return getOptional(PgOIdDiag.internalQuery);
    }

    @property string sqlLine() const
    {
        return getOptional(PgOIdDiag.sourceLine);
    }

    @property string sqlPosition() const
    {
        return getOptional(PgOIdDiag.statementPosition);
    }

    @property string sqlRoutine() const
    {
        return getOptional(PgOIdDiag.sourceFunction);
    }

    @property string sqlWhere() const
    {
        return getOptional(PgOIdDiag.context);
    }

public:
    string[char] typeValues;
    string file;
    string funcName;
    uint line;
}

struct PgNotificationResponse
{
nothrow @safe:

public:
    string channel;
    string payload;
    int32 pid;
}

struct PgOIdExecuteResult
{
nothrow @safe:

public:
    DbFetchResultStatus fetchStatus() const
    {
		if (messageType == 'D')
            return DbFetchResultStatus.hasData;
        else if (messageType == 'C')
            return DbFetchResultStatus.ready;
        else
            return DbFetchResultStatus.completed;
    }

public:
    string dmlName; // DELETE, INSERT, UPDATE ...
    DbRecordsAffected recordsAffected;
    PgOId oid;
    char messageType;
}

struct PgOIdFetchResult
{
nothrow @safe:

public:
    DbFetchResultStatus fetchStatus() const
    {
        if (messageType == 'Z')
            return DbFetchResultStatus.completed;
		else if (messageType == 'D')
            return DbFetchResultStatus.hasData;
        else
            return DbFetchResultStatus.ready;
    }

    bool needFetchAgain(bool isSuspended) const
    {
        return isSuspended && messageType == 'Z';
    }

public:
    char messageType;
}

// https://www.postgresql.org/docs/current/protocol-message-formats.html
struct PgOIdFieldInfo
{
nothrow @safe:

public:
    bool opCast(C: bool)() const pure
    {
        return type != 0 && name.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    PgOidFieldInfo opCast(T)() const
    if (is(Unqual!T == PgOidFieldInfo))
    {
        return this;
    }

    void reset() pure
    {
        name = null;
        modifier = 0;
        size = 0;
        tableOid = 0;
        type = 0;
        ordinal = 0;
    }

    DbType dbType() const @nogc pure
    {
        if (type == PgOIdType.numeric)
        {
            if (const p = numericPrecision)
            {
                return p <= 9
                    ? DbType.decimal32
                    : (p <= 18 ? DbType.decimal64 : DbType.decimal);
            }
            return DbType.decimal; // Maximum supported native type
        }

        if (auto e = type in pgDbIdToDbTypeInfos)
            return (*e).dbType;

        return DbType.unknown;
    }

    int32 dbTypeSize() const @nogc pure
    {
        if (size > 0)
            return size;
            
        if (type != 0)
        {
            if (auto e = type in pgDbIdToDbTypeInfos)
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

    static DbFieldIdType isValueIdType(int32 oIdType, int32 oIdSubType) @nogc pure
    {
        return DbFieldIdType.no; //oIdType == PgOIdType.oid;
    }

    string traceString() const
    {
        import std.conv : to;
        import pham.utl.utl_enum_set : toName;

        return "name=" ~ name
            ~ ", modifier=" ~ modifier.to!string()
            ~ ", tableOid=" ~ tableOid.to!string()
            ~ ", type=" ~ type.to!string()
            ~ ", numericPrecision=" ~ numericPrecision.to!string()
            ~ ", numericScale=" ~ numericScale.to!string()
            ~ ", formatCode=" ~ formatCode.to!string()
            ~ ", ordinal=" ~ ordinal.to!string()
            ~ ", size=" ~ size.to!string()
            ~ ", dbType=" ~ dbType().toName!DbType();
    }

    @property bool allowNull() const @nogc pure
    {
        return true;
    }

    @property int32 bitLength() const @nogc pure
    {
        return (type == PgOIdType.bit || type == PgOIdType.varbit)
            ? modifier
            : dynamicTypeSize; // -1=No limit or unknown
    }

    @property int32 characterLength() const @nogc pure
    {
        // For PgOIdType.varchar, this is a max length
        return (type == PgOIdType.bpchar || type == PgOIdType.varchar) && modifier != -1
            ? (modifier - 4)
            : dynamicTypeSize; // -1=No limit or unknown
    }

    @property int16 numericPrecision() const @nogc pure
    {
        // See https://stackoverflow.com/questions/3350148/where-are-numeric-precision-and-scale-for-a-field-found-in-the-pg-catalog-tables
        return type == PgOIdType.numeric && modifier != -1
            ? cast(int16)(((modifier - 4) >> 16) & 0xFFFF)
            : 0;
    }

    @property int16 numericScale() const @nogc pure
    {
        // See https://stackoverflow.com/questions/3350148/where-are-numeric-precision-and-scale-for-a-field-found-in-the-pg-catalog-tables
        return type == PgOIdType.numeric && modifier != -1
            ? cast(int16)((modifier - 4) & 0xFFFF)
            : 0;
    }

    @property int16 timezonePrecision() const @nogc pure
    {
        return (type == PgOIdType.timestamptz || type == PgOIdType.timetz) && modifier != -1
            ? cast(int16)(modifier & 0xFFFF)
            : 0;
    }

public:
    string name;
    /// The type modifier (see pg_attribute.atttypmod). The meaning of the modifier is type-specific.
    PgOId modifier;
    /// If the field can be identified as a column of a specific table, the object ID of the table; otherwise zero.
    PgOId tableOid;
    /// The object ID of the field's data type.
    PgOId type;
    int16 formatCode;
    /// If the field can be identified as a column of a specific table, the attribute number of the column; otherwise zero.
    int16 ordinal;
    /// The data type size (see pg_type.typlen). Note that negative values denote variable-width types.
    int16 size;
}

struct PgOIdInterval
{
nothrow @safe:

public:
    this(int32 months, int32 days, int64 microseconds) @nogc pure
    {
        this.months = months;
        this.days = days;
        this.microseconds = microseconds;
    }

    this(scope const(Duration) duration) @nogc pure
    {
        this.months = 0;
        this.days = 0;
        this.microseconds = duration.total!"usecs"();
    }

    this(scope const(DbTimeSpan) timeSpan) @nogc pure
    {
        this.months = 0;
        this.days = 0;
        this.microseconds = timeSpan.total!"usecs"();
    }

    int opCmp(scope const(PgOIdInterval) rhs) const @nogc pure
    {
        auto result = cmp(months, rhs.months);
        if (result == 0)
        {
            result = cmp(days, rhs.days);
            if (result == 0)
                result = cmp(microseconds, rhs.microseconds);
        }
        return result;
    }

    bool opEquals(scope const(PgOIdInterval) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        return hashOf(months, hashOf(days, hashOf(microseconds)));
    }

    Duration toDuration() const @nogc pure
    {
        // For months, the best is just a guess
        return dur!"usecs"(microseconds) + dur!"days"(days) + dur!"days"(months * 30);
    }

    DbTimeSpan toTimeSpan() const @nogc pure
    {
        return DbTimeSpan(toDuration());
    }

public:
    int64 microseconds;
    int32 days;
    int32 months;
}

struct PgOIdNumeric
{
nothrow @safe:

public:
    enum nbase = 10_000;
    enum digitPerBase = 4; /* decimal digits per NBASE digit */
    enum signNaN = 0xC000;
    enum signNeg = 0x4000;

    // Exclude null terminated
    size_t digitLength() const @nogc pure scope
    {
	    auto i = (weight + 1) * digitPerBase;
	    if (i <= 0)
		    i = 1;
	    return i + dscale + digitPerBase + 1;
    }

    static PgOIdNumeric NaN()
    {
        PgOIdNumeric result;
        result.setSign(signNaN);
        return result;
    }

    void setSign(uint16 value) @nogc pure
    {
        this.sign = cast(int16)value;
    }

    string traceString() const nothrow scope @trusted
    {
        import std.conv : to;

        scope (failure) assert(0, "Assume nothrow failed");

        return "ndigits=" ~ ndigits.to!string()
            ~ ", weight=" ~ weight.to!string()
            ~ ", sign=" ~ sign.to!string()
            ~ ", dscale=" ~ dscale.to!string()
            ~ ", digits=" ~ digits[0..ndigits].to!string();
    }

    @property bool isNaN() const @nogc pure scope
    {
        return sign == signNaN;
    }

    @property bool isNeg() const @nogc pure scope
    {
        return sign == signNeg;
    }

public:
	int16[] digits;		/* base-NBASE digits */
	int16 ndigits;		/* # of digits in digits[] - can be 0! */
	int16 weight;		/* weight of first digit */
	int16 sign;			/* NUMERIC_POS=0x0000, NUMERIC_NEG=0x4000, or NUMERIC_NAN=0xC000 */
	int16 dscale;		/* display scale */
}

struct PgOIdScramSHA256FinalMessage
{
nothrow @safe:

public:
    this(scope const(char)[] signature) pure
    {
        debug(debug_pham_db_db_pgtype) debug writeln(__FUNCTION__, "(signature=", signature, ")");

        this.signature = signature.dup;
    }

    this(scope const(ubyte)[] payload) pure @trusted
    {
        debug(debug_pham_db_db_pgtype) debug writeln(__FUNCTION__, "(payload=", payload, ")");

        foreach (scope part; (cast(string)payload).split(","))
        {
            if (part.startsWith("v="))
                this.signature = part[2..$].dup;
            else
            {
                debug(debug_pham_db_db_pgtype) debug writeln("\t", "Unknown part=", part);
            }
        }

        debug(debug_pham_db_db_pgtype) debug writeln("\t", "signature=", signature);
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        signature[] = 0;
        signature = null;
    }

public:
    char[] signature;
}

struct PgOIdScramSHA256FirstMessage
{
nothrow @safe:

public:
    this(scope const(char)[] nonce, scope const(char)[] salt, int32 iteration) pure
    {
        debug(debug_pham_db_db_pgtype) debug writeln(__FUNCTION__, "(nonce=", nonce, ", salt=", salt, ", iteration=", iteration, ")");

        this.nonce = nonce.dup;
        this.salt = salt.dup;
        this._iteration = iteration;
    }

    this(scope const(ubyte)[] payload) pure @trusted
    {
        debug(debug_pham_db_db_pgtype) debug writeln(__FUNCTION__, "(payload=", payload, ")");
        
        foreach (scope part; (cast(string)payload).split(","))
        {
            if (part.startsWith("r="))
                this.nonce = part[2..$].dup;
            else if (part.startsWith("s="))
                this.salt = part[2..$].dup;
            else if (part.startsWith("i="))
                this._iteration = toIntegerSafe!int32(part[2..$], -1);
            else
            {
                debug(debug_pham_db_db_pgtype) debug writeln("\t", "Unknown part=", part);
            }
        }

        debug(debug_pham_db_db_pgtype) debug writeln("\t", "nonce=", nonce, ", salt=", salt, ", _iteration=", _iteration);
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        nonce[] = 0;
        nonce = null;
        salt[] = 0;
        salt = null;
        _iteration = 0;
    }

    const(char)[] getMessage() const pure
    {
        return "r=" ~ nonce ~ ",s=" ~ salt ~ ",i=" ~ iteration.to!string();
    }

    const(ubyte)[] getSalt() const pure
    {
        // Special try construct for grep
        try {
            enum padding = true;
            return CipherHelper.base64Decode!padding(salt);
        } catch (Exception) return null;
    }

    bool isValid() const pure scope
    {
        return nonce.length != 0
            && salt.length != 0
            && iteration > 0; // Counter start number is 1
    }

    int32 iteration() const pure scope
    {
        return this._iteration;
    }

public:
    char[] nonce;
    char[] salt;
    int32 _iteration;
}

CanSendParameter canSendParameter(string name, ref string mappedName) pure
{
    auto m = name in pgMappedParameterNames;
    if (m is null || (*m).length == 0)
        return CanSendParameter.no;

    mappedName = *m;
    if (mappedName[0] == '?')
    {
        mappedName = mappedName[1..$];
        return CanSendParameter.yesConvert;
    }
    else
        return CanSendParameter.yes;
}

int32 pgOIdTypeSize(PgOIdType oid) @nogc pure
{
    switch (oid)
    {
        case PgOIdType.bool_:
            return 1;
        case PgOIdType.bytea:
            return dynamicTypeSize;
        case PgOIdType.char_:
            return 1;
        case PgOIdType.name:
            return 64;
        case PgOIdType.int8:
            return 8;
        case PgOIdType.int2:
            return 2;
        case PgOIdType.int4:
            return 4;
        //case PgOIdType.regproc:
        case PgOIdType.text:
            return dynamicTypeSize;
        case PgOIdType.oid:
            return 4;
        //case PgOIdType.tid:
        //case PgOIdType.xid:
        //case PgOIdType.cid:
        case PgOIdType.xml:
            return dynamicTypeSize;
        case PgOIdType.point:
            return 8 * 2;
        //case PgOIdType.lseg:
        case PgOIdType.path:
            return dynamicTypeSize;
        case PgOIdType.box:
            return 8 * 4;
        case PgOIdType.polygon:
            return dynamicTypeSize;
        //case PgOIdType.line:
        //case PgOIdType.cidr:
        case PgOIdType.float4:
            return 4;
        case PgOIdType.float8:
            return 8;
        //case PgOIdType.unknown:
        case PgOIdType.circle:
            return 8 * 3;
        case PgOIdType.money:
            return 8;
        //case PgOIdType.macaddr:
        //case PgOIdType.inet:
        case PgOIdType.bpchar:
            return runtimeTypeSize;
        case PgOIdType.varchar:
            return runtimeTypeSize;
        case PgOIdType.date:
            return 4;
        case PgOIdType.time:
            return 8;
        case PgOIdType.timestamp:
            return 8;
        case PgOIdType.timestamptz:
            return 12;
        case PgOIdType.interval:
            return 16;
        case PgOIdType.timetz:
            return 12;
        //case PgOIdType.bit:
        case PgOIdType.varbit:
            return runtimeTypeSize;
        case PgOIdType.numeric:
            return dynamicTypeSize;
        //case PgOIdType.refcursor:
        //case PgOIdType.record:
        //case PgOIdType.void_:
        //case PgOIdType.array_record:
        //case PgOIdType.regprocedure:
        //case PgOIdType.regoper:
        //case PgOIdType.regoperator:
        //case PgOIdType.regclass:
        //case PgOIdType.regtype:
        case PgOIdType.uuid:
            return 16;
        case PgOIdType.json:
        case PgOIdType.jsonb:
            return dynamicTypeSize;
        case PgOIdType.int2vector:
        case PgOIdType.oidvector:
            return dynamicTypeSize;
        case PgOIdType.array_xml:
        case PgOIdType.array_json:
        case PgOIdType.array_line:
        case PgOIdType.array_cidr:
        case PgOIdType.array_circle:
        case PgOIdType.array_money:
        case PgOIdType.array_bool:
        case PgOIdType.array_bytea:
        case PgOIdType.array_char:
        case PgOIdType.array_name:
        case PgOIdType.array_int2:
        case PgOIdType.array_int2vector:
        case PgOIdType.array_int4:
        case PgOIdType.array_regproc:
        case PgOIdType.array_text:
        case PgOIdType.array_tid:
        case PgOIdType.array_xid:
        case PgOIdType.array_cid:
        case PgOIdType.array_oidvector:
        case PgOIdType.array_bpchar:
        case PgOIdType.array_varchar:
        case PgOIdType.array_int8:
        case PgOIdType.array_point:
        case PgOIdType.array_lseg:
        case PgOIdType.array_path:
        case PgOIdType.array_box:
        case PgOIdType.array_float4:
        case PgOIdType.array_float8:
        case PgOIdType.array_polygon:
        case PgOIdType.array_oid:
        case PgOIdType.array_macaddr:
        case PgOIdType.array_inet:
        case PgOIdType.array_timestamp:
        case PgOIdType.array_date:
        case PgOIdType.array_time:
        case PgOIdType.array_timestamptz:
        case PgOIdType.array_interval:
        case PgOIdType.array_numeric:
        case PgOIdType.array_timetz:
        case PgOIdType.array_bit:
        case PgOIdType.array_varbit:
        case PgOIdType.array_refcursor:
        case PgOIdType.array_regprocedure:
        case PgOIdType.array_regoper:
        case PgOIdType.array_regoperator:
        case PgOIdType.array_regclass:
        case PgOIdType.array_regtype:
        case PgOIdType.array_uuid:
        case PgOIdType.array_jsonb:
            return dynamicTypeSize;
        case PgOIdType.int4range:
        case PgOIdType.int4range_:
        case PgOIdType.numrange:
        case PgOIdType.numrange_:
        case PgOIdType.tsrange:
        case PgOIdType.tsrange_:
        case PgOIdType.tstzrange:
        case PgOIdType.tstzrange_:
        case PgOIdType.daterange:
        case PgOIdType.daterange_:
        case PgOIdType.int8range:
        case PgOIdType.int8range_:
            return unknownTypeSize;
        default:
            return unknownTypeSize;
    }
}

DbParameterDirection pgParameterModeToDirection(scope const(char)[] mode)
{
    return mode == "i"
        ? DbParameterDirection.input
        : (mode == "o" || mode == "t"
            ? DbParameterDirection.output
            : (mode == "b"
                ? DbParameterDirection.inputOutput
                : DbParameterDirection.input));
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    pgDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(DbConnectionParameterInfo[string]))[
            DbConnectionParameterIdentifier.serverPort : DbConnectionParameterInfo(&isConnectionParameterInt32, "5_432", 0, uint16.max, DbScheme.pg),
            DbConnectionParameterIdentifier.userName : DbConnectionParameterInfo(&isConnectionParameterString, "postgres", 0, dbConnectionParameterMaxId, DbScheme.pg),
            ];
    }();

    // https://www.postgresql.org/docs/12/libpq-connect.html#LIBPQ-PARAMKEYWORDS
    pgMappedParameterNames = () nothrow pure @trusted // @trusted=cast()
    {
        // Map to blank - skip sending over
        // Map to leading '?' - need special conversion
        return cast(immutable(string[string]))[
            DbConnectionParameterIdentifier.charset : "client_encoding",
            DbConnectionParameterIdentifier.compress : "",
            DbConnectionParameterIdentifier.connectionTimeout : "",
            DbConnectionParameterIdentifier.databaseName : "database",
            DbConnectionParameterIdentifier.databaseFileName : "",
            DbConnectionParameterIdentifier.encrypt : "",
            DbConnectionParameterIdentifier.fetchRecordCount : "",
            DbConnectionParameterIdentifier.integratedSecurity : "",
            DbConnectionParameterIdentifier.packageSize : "",
            DbConnectionParameterIdentifier.pooling : "",
            DbConnectionParameterIdentifier.poolIdleTimeout : "",
            DbConnectionParameterIdentifier.poolMaxCount : "",
            DbConnectionParameterIdentifier.poolMinCount : "",
            DbConnectionParameterIdentifier.receiveTimeout : "",
            DbConnectionParameterIdentifier.roleName : "",
            DbConnectionParameterIdentifier.sendTimeout : "",
            DbConnectionParameterIdentifier.serverName : "", // host - ignore sending over
            DbConnectionParameterIdentifier.serverPort : "", // port - ignore sending over
            DbConnectionParameterIdentifier.userName : "user",
            DbConnectionParameterIdentifier.userPassword : "", // password - special handling
            DbConnectionParameterIdentifier.socketBlocking : "",
            DbConnectionParameterIdentifier.socketNoDelay : "",
            /*
            DbConnectionParameterIdentifier.pgOptions : DbConnectionParameterIdentifier.pgOptions,
            DbConnectionParameterIdentifier.pgPassFile : DbConnectionParameterIdentifier.pgPassFile,
            DbConnectionParameterIdentifier.pgFallbackApplicationName : DbConnectionParameterIdentifier.pgFallbackApplicationName,
            DbConnectionParameterIdentifier.pgKeepAlives : DbConnectionParameterIdentifier.pgKeepAlives,
            DbConnectionParameterIdentifier.pgKeepalivesIdle : DbConnectionParameterIdentifier.pgKeepalivesIdle,
            DbConnectionParameterIdentifier.pgKeepalivesInterval : DbConnectionParameterIdentifier.pgKeepalivesInterval,
            DbConnectionParameterIdentifier.pgKeepalivesCount : DbConnectionParameterIdentifier.pgKeepalivesCount,
            DbConnectionParameterIdentifier.pgTty : DbConnectionParameterIdentifier.pgTty,
            DbConnectionParameterIdentifier.pgReplication : DbConnectionParameterIdentifier.pgReplication,
            DbConnectionParameterIdentifier.pgGSSEncMode : DbConnectionParameterIdentifier.pgGSSEncMode,
            DbConnectionParameterIdentifier.pgSSLCert : DbConnectionParameterIdentifier.pgSSLCert,
            DbConnectionParameterIdentifier.pgSSLKey : DbConnectionParameterIdentifier.pgSSLKey,
            DbConnectionParameterIdentifier.pgSSLRootCert : DbConnectionParameterIdentifier.pgSSLRootCert,
            DbConnectionParameterIdentifier.pgSSLCrl : DbConnectionParameterIdentifier.pgSSLCrl,
            DbConnectionParameterIdentifier.pgRequirePeer : DbConnectionParameterIdentifier.pgRequirePeer,
            DbConnectionParameterIdentifier.pgKRBSrvName : DbConnectionParameterIdentifier.pgKRBSrvName,
            DbConnectionParameterIdentifier.pgGSSLibib : DbConnectionParameterIdentifier.pgGSSLibib,
            DbConnectionParameterIdentifier.pgService : DbConnectionParameterIdentifier.pgService,
            DbConnectionParameterIdentifier.pgTargetSessionAttrs : DbConnectionParameterIdentifier.pgTargetSessionAttrs,
            */
            ];
    }();

    pgDbIdToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[int32] result;
        foreach (i; 0..pgNativeTypes.length)
        {
            const dbId = pgNativeTypes[i].dbId;
            if (!(dbId in result))
                result[dbId] = &pgNativeTypes[i];
        }
        return result;
    }();
}

unittest // canSendParameter
{
    string mappedName;
    assert(canSendParameter(DbConnectionParameterIdentifier.userPassword, mappedName) == CanSendParameter.no);
    /*
    assert(canSendParameter(DbConnectionParameterIdentifier.pgPassFile, mappedName) == CanSendParameter.yes);
    assert(DbConnectionParameterIdentifier.pgPassFile == mappedName);
    */
}

unittest // PgOIdScramSHA256FirstMessage
{
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    
    auto r = PgOIdScramSHA256FirstMessage(bytesFromHexs("723D307131356635454831642F682F313258634E4F485A2B3731524F4149563643492F322B35786344516B56534E317A6E6C2C733D456E5261337A47685830462F464A62616279685655513D3D2C693D34303936"));
    assert(r.iteration == 4096);
    assert(r.nonce == "0q15f5EH1d/h/12XcNOHZ+71ROAIV6CI/2+5xcDQkVSN1znl");
    assert(r.salt == "EnRa3zGhX0F/FJbabyhVUQ==");
    assert(r.getSalt() == bytesFromHexs("12745ADF31A15F417F1496DA6F285551"), r.getSalt().bytesToHexs());
}
