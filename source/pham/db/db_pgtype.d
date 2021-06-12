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

import std.algorithm : startsWith;
import std.array : split;
import std.base64 : Base64;
import std.conv : to;

version (TraceFunction) import pham.utl.test;
import pham.db.message;
import pham.db.type;
import pham.db.pgoid;

nothrow @safe:

alias PgOId = int32;
alias PgDescriptorId = int32;

enum pgCommandPreparedHandle = 1; // Any dummy number > zero
enum pgInvalidDescriptorId = -1;

immutable string[string] pgDefaultParameterValues;

immutable string[] pgValidParameterNames = [
    // Primary
    DbParameterName.server,
    DbParameterName.port,
    DbParameterName.database,
    DbParameterName.userName,
    DbParameterName.userPassword,
    //DbParameterName.encrypt,
    //DbParameterName.compress,
    DbParameterName.charset,

    // Other
    DbParameterName.connectionTimeout,
    DbParameterName.pooling,
    DbParameterName.receiveTimeout,
    DbParameterName.sendTimeout,
    DbParameterName.socketBlocking,

    DbParameterName.pgOptions,
    /*
    DbParameterName.pgPassFile,
    DbParameterName.pgFallbackApplicationName,
    DbParameterName.pgKeepAlives,
    DbParameterName.pgKeepalivesIdle,
    DbParameterName.pgKeepalivesInterval,
    DbParameterName.pgKeepalivesCount,
    DbParameterName.pgTty,
    DbParameterName.pgReplication,
    DbParameterName.pgGSSEncMode,
    DbParameterName.pgSSLCert,
    DbParameterName.pgSSLKey,
    DbParameterName.pgSSLRootCert,
    DbParameterName.pgSSLCrl,
    DbParameterName.pgRequirePeer,
    DbParameterName.pgKRBSrvName,
    DbParameterName.pgGSSLibib,
    DbParameterName.pgService,
    DbParameterName.pgTargetSessionAttrs
    */
];

// https://www.postgresql.org/docs/12/libpq-connect.html#LIBPQ-PARAMKEYWORDS
immutable string[string] pgMappedParameterNames;

immutable DbTypeInfo[] pgNativeTypes = [
    {dbName:"BOOLEAN", nativeName:"bool", displaySize:5, nativeSize:1, nativeId:PgOIdType.bool_, dbType:DbType.boolean},
    {dbName:"BLOB", nativeName:"bytea", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.bytea, dbType:DbType.binary},
    {dbName:"CHAR[?]", nativeName:"bpchar", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.bpchar, dbType:DbType.chars}, // Prefer multi chars[] over 1 char type
    {dbName:"CHAR[1]", nativeName:"char", displaySize:1, nativeSize:1, nativeId:PgOIdType.char_, dbType:DbType.chars}, // Native 1 char
    {dbName:"VARCHAR[?]", nativeName:"varchar", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.varchar, dbType:DbType.string}, // Prefer vary chars[] over name
    {dbName:"VARCHAR[64]", nativeName:"name", displaySize:64, nativeSize:64, nativeId:PgOIdType.name, dbType:DbType.string},
    {dbName:"BIGINT", nativeName:"bigint", displaySize:20, nativeSize:8, nativeId:PgOIdType.int8, dbType:DbType.int64},
    {dbName:"SMALLINT", nativeName:"smallint", displaySize:6, nativeSize:2, nativeId:PgOIdType.int2, dbType:DbType.int16},
    {dbName:"INTEGER", nativeName:"integer", displaySize:11, nativeSize:4, nativeId:PgOIdType.int4, dbType:DbType.int32},
    {dbName:"TEXT", nativeName:"text", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.text, dbType:DbType.text},
    {dbName:"INTEGER", nativeName:"oid", displaySize:11, nativeSize:4, nativeId:PgOIdType.oid, dbType:DbType.int32},
    {dbName:"XML", nativeName:"xml", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.xml, dbType:DbType.xml},
    {dbName:"FLOAT", nativeName:"real", displaySize:17, nativeSize:4, nativeId:PgOIdType.float4, dbType:DbType.float32},
    {dbName:"DOUBLE", nativeName:"double precision", displaySize:17, nativeSize:8, nativeId:PgOIdType.float8, dbType:DbType.float64},
    {dbName:"DECIMAL(?)", nativeName:"numeric", displaySize:34, nativeSize:Decimal.sizeof, nativeId:PgOIdType.numeric, dbType:DbType.decimal}, // Prefer numerice over money for generic setting
    {dbName:"MONEY", nativeName:"money", displaySize:34, nativeSize:Decimal64.sizeof, nativeId:PgOIdType.money, dbType:DbType.decimal64},
    {dbName:"DATE", nativeName:"date", displaySize:10, nativeSize:4, nativeId:PgOIdType.date, dbType:DbType.date},
    {dbName:"TIME", nativeName:"time", displaySize:11, nativeSize:8, nativeId:PgOIdType.time, dbType:DbType.time},
    {dbName:"TIMESTAMP", nativeName:"timestamp", displaySize:22, nativeSize:8, nativeId:PgOIdType.timestamp, dbType:DbType.datetime},
    {dbName:"TIMESTAMPTZ", nativeName:"timestamp with time zone", displaySize:28, nativeSize:12, nativeId:PgOIdType.timestamptz, dbType:DbType.datetimeTZ},
    {dbName:"TIMETZ", nativeName:"time with time zone", displaySize:17, nativeSize:12, nativeId:PgOIdType.timetz, dbType:DbType.timeTZ},
    {dbName:"UUID", nativeName:"uuid", displaySize:32, nativeSize:16, nativeId:PgOIdType.uuid, dbType:DbType.uuid},
    {dbName:"JSON", nativeName:"json", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.json, dbType:DbType.json},
    {dbName:"", nativeName:"void", displaySize:4, nativeSize:0, nativeId:PgOIdType.void_, dbType:DbType.unknown},
    {dbName:"ARRAY[SMALLINT,?]", nativeName:"array_int2", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_int2, dbType:DbType.int16 | DbType.array}, // Prefer native array over vector
    {dbName:"ARRAY[SMALLINT,?]", nativeName:"int2vector", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.int2vector, dbType:DbType.int16 | DbType.array},
    {dbName:"ARRAY[INTEGER,?]", nativeName:"array_int4", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_int4, dbType:DbType.int32 | DbType.array}, // Prefer native array over vector
    {dbName:"ARRAY[INTEGER,?]", nativeName:"array_oid", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_oid, dbType:DbType.int32 | DbType.array},
    {dbName:"ARRAY[INTEGER,?]", nativeName:"oidvector", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.oidvector, dbType:DbType.int32 | DbType.array},
    {dbName:"ARRAY[XML,?]", nativeName:"array_xml", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_xml, dbType:DbType.string | DbType.array},
    {dbName:"ARRAY[JSON,?]", nativeName:"array_json", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_json, dbType:DbType.string | DbType.array},
    {dbName:"ARRAY[DECIMAL(?),?]", nativeName:"array_numeric", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_numeric, dbType:DbType.decimal | DbType.array}, // Prefer numerice over money for generic setting
    {dbName:"ARRAY[MONEY,?]", nativeName:"array_money", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_money, dbType:DbType.decimal | DbType.array},
    {dbName:"ARRAY[BOOLEAN,?]", nativeName:"array_bool", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_bool, dbType:DbType.boolean | DbType.array},
    {dbName:"ARRAY[BLOB,?]", nativeName:"array_bytea", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_bytea, dbType:DbType.binary | DbType.array},
    {dbName:"ARRAY[CHAR[?],?]", nativeName:"array_bpchar", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_bpchar, dbType:DbType.chars | DbType.array}, // Prefer multi chars[] over 1 char type
    {dbName:"ARRAY[CHAR[1],?]", nativeName:"array_char", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_char, dbType:DbType.chars | DbType.array},
    {dbName:"ARRAY[VARCHAR[?],?]", nativeName:"array_varchar", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_varchar, dbType:DbType.string | DbType.array}, // Prefer vary chars[] over name
    {dbName:"ARRAY[VARCHAR[64],?]", nativeName:"array_name", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_name, dbType:DbType.string | DbType.array},
    {dbName:"ARRAY[TEXT,?]", nativeName:"array_text", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_text, dbType:DbType.text | DbType.array},
    {dbName:"ARRAY[BIGINT,?]", nativeName:"array_int8", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_int8, dbType:DbType.int64 | DbType.array},
    {dbName:"ARRAY[FLOAT,?]", nativeName:"array_float4", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_float4, dbType:DbType.float32 | DbType.array},
    {dbName:"ARRAY[DOUBLE,?]", nativeName:"array_float8", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_float8, dbType:DbType.float64 | DbType.array},
    {dbName:"ARRAY[TIMESTAMP,?]", nativeName:"array_timestamp", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_timestamp, dbType:DbType.datetime | DbType.array},
    {dbName:"ARRAY[DATE,?]", nativeName:"array_date", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_date, dbType:DbType.date | DbType.array},
    {dbName:"ARRAY[TIME,?]", nativeName:"array_time", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_time, dbType:DbType.time | DbType.array},
    {dbName:"ARRAY[TIMESTAMPTZ,?]", nativeName:"array_timestamptz", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_timestamptz, dbType:DbType.datetimeTZ | DbType.array},
    {dbName:"ARRAY[TIMETZ,?]", nativeName:"array_timetz", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_timetz, dbType:DbType.timeTZ | DbType.array},
    {dbName:"ARRAY[UUID,?]", nativeName:"array_uuid", displaySize:-1, nativeSize:-1, nativeId:PgOIdType.array_uuid, dbType:DbType.uuid | DbType.array}
    //{dbName:"", nativeName:"", displaySize:-1, nativeSize:-1, nativeId:PgOIdType., dbType:DbType.},
];

immutable DbTypeInfo*[int32] PgOIdTypeToDbTypeInfos;

enum CanSendParameter
{
    no,
    yes,
    yesConvert
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
        scope (failure)
            return 0;

        auto c = sqlState;
        if (c.length)
            return to!int(c);
        else
            return 0;
    }

    string errorString() const
    {
        version (TraceFunction) dgFunctionTrace();

        auto result = severity ~ ' ' ~ sqlState ~ ": " ~ message;

        auto detail = PgDiag.messageDetail in typeValues;
        if (detail)
            result ~= "\n" ~ DbMessage.eErrorDetail ~ ": " ~ *detail;

        auto hint = PgDiag.messageHint in typeValues;
        if (hint)
            result ~= "\n" ~ DbMessage.eErrorHint ~ ": " ~ *hint;

        return result;
    }

    string getOptional(char type) const
    {
        auto p = type in typeValues;
        return p ? *p : null;
    }

    @property string message() const
    {
        return typeValues[PgDiag.messagePrimary];
    }

    @property string severity() const
    {
        return typeValues[PgDiag.severity];
    }

    @property string sqlState() const
    {
        return typeValues[PgDiag.sqlState];
    }

    /* Optional Values */

    @property string detail() const
    {
        return getOptional(PgDiag.messageDetail);
    }

    @property string file() const
    {
        return getOptional(PgDiag.sourceFile);
    }

    @property string hint() const
    {
        return getOptional(PgDiag.messageHint);
    }

    @property string internalPosition() const
    {
        return getOptional(PgDiag.internalPosition);
    }

    @property string internalQuery() const
    {
        return getOptional(PgDiag.internalQuery);
    }

    @property string line() const
    {
        return getOptional(PgDiag.sourceLine);
    }

    @property string position() const
    {
        return getOptional(PgDiag.statementPosition);
    }

    @property string routine() const
    {
        return getOptional(PgDiag.sourceFunction);
    }

    @property string where() const
    {
        return getOptional(PgDiag.context);
    }

public:
    string[char] typeValues;
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

public:
    char messageType;
}

struct PgOIdFieldInfo
{
nothrow @safe:

public:
    bool opCast(C: bool)() const
    {
        return type != 0 && name.length != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    PgOidFieldInfo opCast(T)() const
    if (is(Unqual!T == PgOidFieldInfo))
    {
        return this;
    }

    void reset()
    {
        name = null;
        modifier = 0;
        size = 0;
        tableOid = 0;
        type = 0;
        index = 0;
    }

    DbType dbType() const
    {
        DbType result = DbType.unknown;
        if (auto e = type in PgOIdTypeToDbTypeInfos)
            result = (*e).dbType;
        return result;
    }

    int32 dbTypeSize() const
    {
        int32 result = -1;
        if (auto e = dbType() in dbTypeToDbTypeInfos)
            result = (*e).nativeSize;
        return result != -1 ? result : size;
    }

    static DbFieldIdType isIdType(int32 oIdType, int32 oIdSubType) pure
    {
        return DbFieldIdType.no; //oIdType == PgOIdType.oid;
    }

    @property bool allowNull() const nothrow
    {
        return true;
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

struct PgOIdNumeric
{
nothrow @safe:

public:
    enum nbase = 10000;
    enum digitPerBase = 4; /* decimal digits per NBASE digit */
    enum signNaN = 0xC000;
    enum signNeg = 0x4000;

    // Exclude null terminated
    size_t digitLength() const
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

    void setSign(uint16 value)
    {
        this.sign = cast(int16)value;
    }

    @property bool isNaN() const
    {
        return sign == signNaN;
    }

    @property bool isNeg() const
    {
        return sign == signNeg;
    }

public:
	int16 ndigits;		/* # of digits in digits[] - can be 0! */
	int16 weight;		/* weight of first digit */
	int16 sign;			/* NUMERIC_POS=0x0000, NUMERIC_NEG=0x4000, or NUMERIC_NAN=0xC000 */
	int16 dscale;		/* display scale */
	int16[] digits;		/* base-NBASE digits */
}

struct PgOIdScramSHA256FinalMessage
{
nothrow @safe:

public:
    this(const(char)[] signature) pure
    {
        this.signature = signature;
    }

    this(const(ubyte)[] payload) pure
    {
        auto charsPayload = cast(const(char)[])payload;
        auto parts = charsPayload.split(",");
        foreach (part; parts)
        {
            if (part.startsWith("v="))
                this.signature = part[2..$];
            else
            {
                version (TraceFunction) dgFunctionTrace("Unknown part: ", part);
            }
        }
    }

    ~this() pure
    {
        dispose(false);
    }

    void dispose(bool disposing) pure
    {
        if (disposing)
        {
            signature = null;
        }
    }

public:
    const(char)[] signature;
}

struct PgOIdScramSHA256FirstMessage
{
nothrow @safe:

public:
    this(const(char)[] nonce, const(char)[] salt, uint iteration) pure
    {
        this.nonce = nonce;
        this.salt = salt;
        this.iteration = to!(const(char)[])(iteration);
    }

    this(const(ubyte)[] payload) pure
    {
        auto charsPayload = cast(const(char)[])payload;
        auto parts = charsPayload.split(",");
        foreach (part; parts)
        {
            if (part.startsWith("r="))
                this.nonce = part[2..$];
            else if (part.startsWith("s="))
                this.salt = part[2..$];
            else if (part.startsWith("i="))
                this.iteration = part[2..$];
            else
            {
                version (TraceFunction) dgFunctionTrace("Unknown part: ", part);
            }
        }
    }

    ~this() pure
    {
        dispose(false);
    }

    void dispose(bool disposing) pure
    {
        if (disposing)
        {
            iteration = null;
            nonce = null;
            salt = null;
        }
    }

    int32 getIteration() const pure
    {
        if (iteration.length == 0)
            return -1;

        scope (failure)
            return -1;

        return to!int32(iteration);
    }

    const(char)[] getMessage() const pure
    {
        return "r=" ~ nonce ~ ",s=" ~ salt ~ ",i=" ~ iteration;
    }

    const(ubyte)[] getSalt() const pure
    {
        scope (failure)
            return null;

        return Base64.decode(salt);
    }

    bool isValid() const pure
    {
        return nonce.length != 0
            && salt.length != 0
            && getIteration() > 0; // Counter start number is 1
    }

public:
    const(char)[] iteration;
    const(char)[] nonce;
    const(char)[] salt;
}

// Any below codes are private
private:


shared static this()
{
    pgDefaultParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbParameterName.port : "5432",
            DbParameterName.userName : "postgres"
        ];
    }();

    // https://www.postgresql.org/docs/12/libpq-connect.html#LIBPQ-PARAMKEYWORDS
    pgMappedParameterNames = () nothrow pure @trusted // @trusted=cast()
    {
        // Map to blank - skip sending over
        // Map to leading '?' - need special conversion
        return cast(immutable(string[string]))[
            DbParameterName.applicationVersion : "",
            DbParameterName.charset : "client_encoding",
            DbParameterName.compress : "",
            DbParameterName.connectionTimeout : "",
            DbParameterName.database : "database",
            DbParameterName.databaseFile : "",
            DbParameterName.encrypt : "",
            DbParameterName.fetchRecordCount : "",
            DbParameterName.integratedSecurity : "",
            DbParameterName.maxPoolCount : "",
            DbParameterName.minPoolCount : "",
            DbParameterName.packageSize : "",
            DbParameterName.port : "", // port - ignore sending over
            DbParameterName.pooling : "",
            DbParameterName.poolTimeout : "",
            DbParameterName.receiveTimeout : "",
            DbParameterName.roleName : "",
            DbParameterName.sendTimeout : "",
            DbParameterName.server : "", // host - ignore sending over
            DbParameterName.userName : "user",
            DbParameterName.userPassword : "", // password - special handling
            DbParameterName.socketBlocking : "",
            DbParameterName.socketNoDelay : "",

            DbParameterName.pgOptions : DbParameterName.pgOptions,
            /*
            DbParameterName.pgPassFile : DbParameterName.pgPassFile,
            DbParameterName.pgFallbackApplicationName : DbParameterName.pgFallbackApplicationName,
            DbParameterName.pgKeepAlives : DbParameterName.pgKeepAlives,
            DbParameterName.pgKeepalivesIdle : DbParameterName.pgKeepalivesIdle,
            DbParameterName.pgKeepalivesInterval : DbParameterName.pgKeepalivesInterval,
            DbParameterName.pgKeepalivesCount : DbParameterName.pgKeepalivesCount,
            DbParameterName.pgTty : DbParameterName.pgTty,
            DbParameterName.pgReplication : DbParameterName.pgReplication,
            DbParameterName.pgGSSEncMode : DbParameterName.pgGSSEncMode,
            DbParameterName.pgSSLCert : DbParameterName.pgSSLCert,
            DbParameterName.pgSSLKey : DbParameterName.pgSSLKey,
            DbParameterName.pgSSLRootCert : DbParameterName.pgSSLRootCert,
            DbParameterName.pgSSLCrl : DbParameterName.pgSSLCrl,
            DbParameterName.pgRequirePeer : DbParameterName.pgRequirePeer,
            DbParameterName.pgKRBSrvName : DbParameterName.pgKRBSrvName,
            DbParameterName.pgGSSLibib : DbParameterName.pgGSSLibib,
            DbParameterName.pgService : DbParameterName.pgService,
            DbParameterName.pgTargetSessionAttrs : DbParameterName.pgTargetSessionAttrs
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
    traceUnitTest("unittest db.pgtype.canSendParameter");

    string mappedName;
    assert(canSendParameter(DbParameterName.userPassword, mappedName) == CanSendParameter.no);
    /*
    assert(canSendParameter(DbParameterName.pgPassFile, mappedName) == CanSendParameter.yes);
    assert(DbParameterName.pgPassFile == mappedName);
    */
}
