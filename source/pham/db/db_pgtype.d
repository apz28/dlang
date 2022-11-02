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

module pham.db.pgtype;

import core.time : dur;
import std.algorithm : startsWith;
import std.array : split;
import std.conv : to;

version (TraceFunction) import pham.utl.test;
import pham.cp.cipher : CipherHelper;
import pham.utl.enum_set : toName;
import pham.utl.object : cmpInteger;
import pham.db.convert : toIntegerSafe;
import pham.db.message;
import pham.db.type;
import pham.db.pgoid;

nothrow @safe:

alias PgOId = int32;
alias PgDescriptorId = int32;

enum pgNullValueLength = -1;

static immutable string pgAuthClearTextName = "ClearText";
static immutable string pgAuthMD5Name = "MD5";
static immutable string pgAuthScram256Name = "SCRAM-SHA-256";

static immutable string[string] pgDefaultConnectionParameterValues;

static immutable string[] pgValidConnectionParameterNames = [
    // Primary
    DbConnectionParameterIdentifier.server,
    DbConnectionParameterIdentifier.port,
    DbConnectionParameterIdentifier.database,
    DbConnectionParameterIdentifier.userName,
    DbConnectionParameterIdentifier.userPassword,
    //DbConnectionParameterIdentifier.encrypt,
    //DbConnectionParameterIdentifier.compress,
    DbConnectionParameterIdentifier.charset,

    // Other
    DbConnectionParameterIdentifier.connectionTimeout,
    DbConnectionParameterIdentifier.pooling,
    DbConnectionParameterIdentifier.receiveTimeout,
    DbConnectionParameterIdentifier.sendTimeout,
    DbConnectionParameterIdentifier.socketBlocking,

    DbConnectionParameterIdentifier.pgOptions,
    /*
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
    {dbName:"BOOLEAN", nativeName:"bool", displaySize:5, nativeSize:1, nativeId:PgOIdType.bool_, dbType:DbType.boolean},
    {dbName:"BLOB", nativeName:"bytea", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.bytea, dbType:DbType.binary},
    {dbName:"CHAR(?)", nativeName:"char(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:PgOIdType.bpchar, dbType:DbType.fixedString}, // Prefer multi chars[] over 1 char type
    {dbName:"VARCHAR(?)", nativeName:"varchar(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:PgOIdType.varchar, dbType:DbType.string}, // Prefer vary chars[] over name
    {dbName:"BIGINT", nativeName:"bigint", displaySize:20, nativeSize:8, nativeId:PgOIdType.int8, dbType:DbType.int64},
    {dbName:"SMALLINT", nativeName:"smallint", displaySize:6, nativeSize:2, nativeId:PgOIdType.int2, dbType:DbType.int16},
    {dbName:"INTEGER", nativeName:"integer", displaySize:11, nativeSize:4, nativeId:PgOIdType.int4, dbType:DbType.int32},
    {dbName:"TEXT", nativeName:"text", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.text, dbType:DbType.text},
    {dbName:"XML", nativeName:"xml", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.xml, dbType:DbType.xml},
    {dbName:"FLOAT", nativeName:"real", displaySize:17, nativeSize:4, nativeId:PgOIdType.float4, dbType:DbType.float32},
    {dbName:"DOUBLE", nativeName:"double precision", displaySize:17, nativeSize:8, nativeId:PgOIdType.float8, dbType:DbType.float64},
    {dbName:"DECIMAL(?,?)", nativeName:"numeric(?,?)", displaySize:34, nativeSize:Decimal.sizeof, nativeId:PgOIdType.numeric, dbType:DbType.decimal}, // Prefer numeric over money for generic setting
    {dbName:"NUMERIC(?,?)", nativeName:"numeric(?,?)", displaySize:34, nativeSize:Decimal.sizeof, nativeId:PgOIdType.numeric, dbType:DbType.decimal}, // Prefer numeric over money for generic setting
    {dbName:"DATE", nativeName:"date", displaySize:10, nativeSize:4, nativeId:PgOIdType.date, dbType:DbType.date},
    {dbName:"TIME", nativeName:"time", displaySize:11, nativeSize:8, nativeId:PgOIdType.time, dbType:DbType.time},
    {dbName:"TIMESTAMP", nativeName:"timestamp", displaySize:22, nativeSize:8, nativeId:PgOIdType.timestamp, dbType:DbType.datetime},
    {dbName:"TIMESTAMPTZ", nativeName:"timestamp with time zone", displaySize:28, nativeSize:12, nativeId:PgOIdType.timestamptz, dbType:DbType.datetimeTZ},
    {dbName:"TIMETZ", nativeName:"time with time zone", displaySize:17, nativeSize:12, nativeId:PgOIdType.timetz, dbType:DbType.timeTZ},
    {dbName:"UUID", nativeName:"uuid", displaySize:32, nativeSize:16, nativeId:PgOIdType.uuid, dbType:DbType.uuid},
    {dbName:"JSON", nativeName:"json", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:PgOIdType.json, dbType:DbType.json},
    {dbName:"VARCHAR(64)", nativeName:"name", displaySize:64, nativeSize:64, nativeId:PgOIdType.name, dbType:DbType.string},
    {dbName:"CHAR(1)", nativeName:"char", displaySize:1, nativeSize:1, nativeId:PgOIdType.char_, dbType:DbType.fixedString}, // Native 1 char
    {dbName:"MONEY", nativeName:"money", displaySize:34, nativeSize:Decimal64.sizeof, nativeId:PgOIdType.money, dbType:DbType.decimal64},
    {dbName:"INTEGER", nativeName:"oid", displaySize:11, nativeSize:4, nativeId:PgOIdType.oid, dbType:DbType.int32},
    {dbName:"", nativeName:"void", displaySize:4, nativeSize:0, nativeId:PgOIdType.void_, dbType:DbType.unknown},
    {dbName:"ARRAY[SMALLINT,?]", nativeName:"array_int2", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_int2, dbType:DbType.int16 | DbType.array}, // Prefer native array over vector
    {dbName:"ARRAY[SMALLINT,?]", nativeName:"int2vector", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.int2vector, dbType:DbType.int16 | DbType.array},
    {dbName:"ARRAY[INTEGER,?]", nativeName:"array_int4", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_int4, dbType:DbType.int32 | DbType.array}, // Prefer native array over vector
    {dbName:"ARRAY[INTEGER,?]", nativeName:"array_oid", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_oid, dbType:DbType.int32 | DbType.array},
    {dbName:"ARRAY[INTEGER,?]", nativeName:"oidvector", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.oidvector, dbType:DbType.int32 | DbType.array},
    {dbName:"ARRAY[XML,?]", nativeName:"array_xml", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_xml, dbType:DbType.string | DbType.array},
    {dbName:"ARRAY[JSON,?]", nativeName:"array_json", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_json, dbType:DbType.string | DbType.array},
    {dbName:"ARRAY[DECIMAL(?),?]", nativeName:"array_numeric", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_numeric, dbType:DbType.decimal | DbType.array}, // Prefer numerice over money for generic setting
    {dbName:"ARRAY[MONEY,?]", nativeName:"array_money", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_money, dbType:DbType.decimal | DbType.array},
    {dbName:"ARRAY[BOOLEAN,?]", nativeName:"array_bool", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_bool, dbType:DbType.boolean | DbType.array},
    {dbName:"ARRAY[BLOB,?]", nativeName:"array_bytea", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_bytea, dbType:DbType.binary | DbType.array},
    {dbName:"ARRAY[CHAR[?],?]", nativeName:"array_bpchar", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_bpchar, dbType:DbType.fixedString | DbType.array}, // Prefer multi chars[] over 1 char type
    {dbName:"ARRAY[CHAR[1],?]", nativeName:"array_char", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_char, dbType:DbType.fixedString | DbType.array},
    {dbName:"ARRAY[VARCHAR[?],?]", nativeName:"array_varchar", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_varchar, dbType:DbType.string | DbType.array}, // Prefer vary chars[] over name
    {dbName:"ARRAY[VARCHAR[64],?]", nativeName:"array_name", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_name, dbType:DbType.string | DbType.array},
    {dbName:"ARRAY[TEXT,?]", nativeName:"array_text", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_text, dbType:DbType.text | DbType.array},
    {dbName:"ARRAY[BIGINT,?]", nativeName:"array_int8", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_int8, dbType:DbType.int64 | DbType.array},
    {dbName:"ARRAY[FLOAT,?]", nativeName:"array_float4", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_float4, dbType:DbType.float32 | DbType.array},
    {dbName:"ARRAY[DOUBLE,?]", nativeName:"array_float8", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_float8, dbType:DbType.float64 | DbType.array},
    {dbName:"ARRAY[TIMESTAMP,?]", nativeName:"array_timestamp", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_timestamp, dbType:DbType.datetime | DbType.array},
    {dbName:"ARRAY[DATE,?]", nativeName:"array_date", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_date, dbType:DbType.date | DbType.array},
    {dbName:"ARRAY[TIME,?]", nativeName:"array_time", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_time, dbType:DbType.time | DbType.array},
    {dbName:"ARRAY[TIMESTAMPTZ,?]", nativeName:"array_timestamptz", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_timestamptz, dbType:DbType.datetimeTZ | DbType.array},
    {dbName:"ARRAY[TIMETZ,?]", nativeName:"array_timetz", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_timetz, dbType:DbType.timeTZ | DbType.array},
    {dbName:"ARRAY[UUID,?]", nativeName:"array_uuid", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:PgOIdType.array_uuid, dbType:DbType.uuid | DbType.array}
    //{dbName:"", nativeName:"", displaySize:, nativeSize:, nativeId:PgOIdType., dbType:DbType.},
    ];

static immutable DbTypeInfo*[int32] PgOIdTypeToDbTypeInfos;

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
    int errorCode() const
    {
        return 0;
    }

    string errorString() const
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        auto result = severity ~ ' ' ~ sqlState ~ ": " ~ message;

        auto s = detail;
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

        addWarnMessage(message);
        addWarnMessage(detail);
        addWarnMessage(hint);

        return result;
    }

    @property string message() const
    {
        return typeValues[PgOIdDiag.messagePrimary];
    }

    @property string severity() const
    {
        return typeValues[PgOIdDiag.severity];
    }

    @property string sqlState() const
    {
        return typeValues[PgOIdDiag.sqlState];
    }

    /* Optional Values */

    @property string detail() const
    {
        return getOptional(PgOIdDiag.messageDetail);
    }

    @property string file() const
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

    @property string line() const
    {
        return getOptional(PgOIdDiag.sourceLine);
    }

    @property string position() const
    {
        return getOptional(PgOIdDiag.statementPosition);
    }

    @property string routine() const
    {
        return getOptional(PgOIdDiag.sourceFunction);
    }

    @property string where() const
    {
        return getOptional(PgOIdDiag.context);
    }

public:
    string[char] typeValues;
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
        index = 0;
    }

    DbType dbType() const @nogc pure
    {
        if (type == PgOIdType.numeric)
        {
            const p = numericPrecision;
            if (p != 0)
            {
                return p <= 9
                    ? DbType.decimal32
                    : (p <= 18 ? DbType.decimal64 : DbType.decimal);
            }
            return DbType.decimal; // Maximum supported native type
        }

        if (auto e = type in PgOIdTypeToDbTypeInfos)
            return (*e).dbType;

        return DbType.unknown;
    }

    int32 dbTypeSize() const @nogc pure
    {
        if (auto e = dbType() in dbTypeToDbTypeInfos)
        {
            const ns = (*e).nativeSize;
            return ns > 0 ? ns : size;
        }
        return dynamicTypeSize;
    }

    static DbFieldIdType isValueIdType(int32 oIdType, int32 oIdSubType) @nogc pure
    {
        return DbFieldIdType.no; //oIdType == PgOIdType.oid;
    }

    version (TraceFunction)
    string traceString() const nothrow @trusted
    {
        import std.conv : to;
        import pham.utl.enum_set : toName;

        return "name=" ~ name
            ~ ", modifier=" ~ to!string(modifier)
            ~ ", tableOid=" ~ to!string(tableOid)
            ~ ", type=" ~ to!string(type)
            ~ ", numericPrecision=" ~ to!string(numericPrecision)
            ~ ", numericScale=" ~ to!string(numericScale)
            ~ ", formatCode=" ~ to!string(formatCode)
            ~ ", index=" ~ to!string(index)
            ~ ", size=" ~ to!string(size)
            ~ ", dbType=" ~ toName!DbType(dbType);
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

    @property int32 numericPrecision() const @nogc pure
    {
        // See https://stackoverflow.com/questions/3350148/where-are-numeric-precision-and-scale-for-a-field-found-in-the-pg-catalog-tables
        return type == PgOIdType.numeric && modifier != -1
            ? (((modifier - 4) >> 16) & 0xFFFF)
            : 0;
    }

    @property int32 numericScale() const @nogc pure
    {
        // See https://stackoverflow.com/questions/3350148/where-are-numeric-precision-and-scale-for-a-field-found-in-the-pg-catalog-tables
        return type == PgOIdType.numeric && modifier != -1
            ? ((modifier - 4) & 0xFFFF)
            : 0;
    }

    @property int32 timezonePrecision() const @nogc pure
    {
        return (type == PgOIdType.timestamptz || type == PgOIdType.timetz) && modifier != -1
            ? (modifier & 0xFFFF)
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
    int16 index;
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
        auto result = cmpInteger(months, rhs.months);
        if (result == 0)
        {
            result = cmpInteger(days, rhs.days);
            if (result == 0)
                result = cmpInteger(microseconds, rhs.microseconds);
        }
        return result;
    }

    bool opEquals(scope const(PgOIdInterval) rhs) const @nogc pure
    {
        return months == rhs.months && days == rhs.days && microseconds == rhs.microseconds;
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

    version (TraceFunction)
    string traceString() const nothrow scope @trusted
    {
        import std.conv : to;

        scope (failure) assert(0);

        return "ndigits=" ~ to!string(ndigits)
            ~ ", weight=" ~ to!string(weight)
            ~ ", sign=" ~ to!string(sign)
            ~ ", dscale=" ~ to!string(dscale)
            ~ ", digits=" ~ to!string(digits[0..ndigits]);
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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("signature=", signature);

        this.signature = signature.dup;
    }

    this(scope const(ubyte)[] payload) pure @trusted
    {
        foreach (scope part; (cast(string)payload).split(","))
        {
            if (part.startsWith("v="))
                this.signature = part[2..$].dup;
            else
            {
                version (TraceFunction) traceFunction!("pham.db.pgdatabase")("Unknown part: ", part);
            }
        }

        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("signature=", signature);
    }

    ~this() pure
    {
        dispose(false);
    }

    void dispose(bool disposing) pure
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
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("nonce=", nonce, ", salt=", salt, ", iteration=", iteration);

        this.nonce = nonce.dup;
        this.salt = salt.dup;
        this._iteration = iteration;
    }

    this(scope const(ubyte)[] payload) pure @trusted
    {
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
                version (TraceFunction) traceFunction!("pham.db.pgdatabase")("Unknown part: ", part);
            }
        }

        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("nonce=", nonce, ", salt=", salt, ", _iteration=", _iteration);
    }

    ~this() pure
    {
        dispose(false);
    }

    void dispose(bool disposing) pure
    {
        nonce[] = 0;
        nonce = null;
        salt[] = 0;
        salt = null;
        _iteration = 0;
    }

    const(char)[] getMessage() const pure
    {
        return "r=" ~ nonce ~ ",s=" ~ salt ~ ",i=" ~ to!string(iteration);
    }

    const(ubyte)[] getSalt() const pure
    {
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

shared static this()
{
    pgDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbConnectionParameterIdentifier.port : "5432",
            DbConnectionParameterIdentifier.userName : "postgres",
            DbConnectionParameterIdentifier.integratedSecurity : toName(DbIntegratedSecurityConnection.srp256),
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
            DbConnectionParameterIdentifier.database : "database",
            DbConnectionParameterIdentifier.databaseFile : "",
            DbConnectionParameterIdentifier.encrypt : "",
            DbConnectionParameterIdentifier.fetchRecordCount : "",
            DbConnectionParameterIdentifier.integratedSecurity : "",
            DbConnectionParameterIdentifier.maxPoolCount : "",
            DbConnectionParameterIdentifier.minPoolCount : "",
            DbConnectionParameterIdentifier.packageSize : "",
            DbConnectionParameterIdentifier.port : "", // port - ignore sending over
            DbConnectionParameterIdentifier.pooling : "",
            DbConnectionParameterIdentifier.poolTimeout : "",
            DbConnectionParameterIdentifier.receiveTimeout : "",
            DbConnectionParameterIdentifier.roleName : "",
            DbConnectionParameterIdentifier.sendTimeout : "",
            DbConnectionParameterIdentifier.server : "", // host - ignore sending over
            DbConnectionParameterIdentifier.userName : "user",
            DbConnectionParameterIdentifier.userPassword : "", // password - special handling
            DbConnectionParameterIdentifier.socketBlocking : "",
            DbConnectionParameterIdentifier.socketNoDelay : "",
            DbConnectionParameterIdentifier.pgOptions : DbConnectionParameterIdentifier.pgOptions,
            /*
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

    PgOIdTypeToDbTypeInfos = () nothrow pure
    {
        immutable(DbTypeInfo)*[int32] result;
        foreach (ref e; pgNativeTypes)
        {
            result[e.nativeId] = &e;
        }
        return result;
    }();
}

unittest // canSendParameter
{
    import pham.utl.test;
    traceUnitTest!("pham.db.pgdatabase")("unittest pham.db.pgtype.canSendParameter");

    string mappedName;
    assert(canSendParameter(DbConnectionParameterIdentifier.userPassword, mappedName) == CanSendParameter.no);
    /*
    assert(canSendParameter(DbConnectionParameterIdentifier.pgPassFile, mappedName) == CanSendParameter.yes);
    assert(DbConnectionParameterIdentifier.pgPassFile == mappedName);
    */
}

unittest // PgOIdScramSHA256FirstMessage
{
    import pham.utl.test;
    traceUnitTest!("pham.db.pgdatabase")("unittest pham.db.pgtype.PgOIdScramSHA256FirstMessage");

    auto r = PgOIdScramSHA256FirstMessage(bytesFromHexs("723D307131356635454831642F682F313258634E4F485A2B3731524F4149563643492F322B35786344516B56534E317A6E6C2C733D456E5261337A47685830462F464A62616279685655513D3D2C693D34303936"));
    assert(r.iteration == 4096);
    assert(r.nonce == "0q15f5EH1d/h/12XcNOHZ+71ROAIV6CI/2+5xcDQkVSN1znl");
    assert(r.salt == "EnRa3zGhX0F/FJbabyhVUQ==");
    assert(r.getSalt() == bytesFromHexs("12745ADF31A15F417F1496DA6F285551"), r.getSalt().dgToHex());
}
