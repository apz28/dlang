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

module pham.db.db_type;

import core.internal.hash : hashOf;
import std.format: FormatSpec, formatValue;
import core.time : convert;
public import core.time : dur, Duration;
import std.range.primitives : isOutputRange, put;
import std.traits : isArray, isSomeChar, Unqual;
import std.uni : sicmp;
public import std.uuid : UUID;

debug(debug_pham_db_db_type) import std.stdio : writeln;

public import pham.dtm.dtm_date : Date, DateTime;
public import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_tick : ErrorOp, Tick;
public import pham.dtm.dtm_time : Time;
import pham.dtm.dtm_time_zone : TimeZoneInfo;
import pham.dtm.dtm_time_zone_map : TimeZoneInfoMap;
public import pham.external.dec.dec_decimal : Decimal32, Decimal64, Decimal128, isDecimal, Precision, RoundingMode;
import pham.utl.utl_array : ShortStringBuffer;
public import pham.utl.utl_big_integer : BigInteger;
import pham.utl.utl_enum_set : toName;
import pham.utl.utl_result : cmp;
import pham.utl.utl_text : NamedValue;

alias float32 = float;
alias float64 = double;
alias int8 = byte;
alias int16 = short;
alias int32 = int;
alias int64 = long;
alias uint8 = ubyte;
alias uint16 = ushort;
alias uint32 = uint;
alias uint64 = ulong;
alias int128 = BigInteger;

alias Decimal = Decimal128;
alias Numeric = Decimal128;

nothrow @safe:

static immutable string anonymousParameterNameFmt = "_parameter%d";
static immutable string returnParameterName = "return";

enum hnsecsPerDay = convert!("hours", "hnsecs")(24);
//enum hnsecsPerHour = convert!("hours", "hnsecs")(1);
enum nullDate = Date(1, 1, 1);

enum minTimeoutDuration = Duration.zero;
enum maxTimeoutDuration = dur!"msecs"(int32.max);

 /**
  * All possible values for conversion between bool and its' string
  */
static immutable string[] boolFalses = ["0", "False", "F", "No", "N"];
static immutable string[] boolTrues = ["1", "True", "T", "Yes", "Y"];
static immutable string dbBoolFalse = "False";
static immutable string dbBoolTrue = "True";

enum DbCommandExecuteType : ubyte
{
    nonQuery,
    reader,
    scalar,
}

enum DbCommandFlag : ubyte
{
    allRowsFetched,
    batched,
    implicitTransaction,
    implicitTransactionStarted,
    parametersCheck,
    prepared,
    returnRecordsAffected,
    transactionRequired,
    cancelled,
}

enum DbCommandState : ubyte
{
	closed,
    unprepared,
    prepared,
	executed,
	error,
}

/**
 * Describes how a command string is interpreted
 * $(DbCommandType.text) An SQL text command
 * $(DbCommandType.storedProcedure) The name of a stored procedure
 * $(DbCommandType.table) The name of a table or view
 * $(DbCommandType.ddl) The data definition command: ALTER, CREATE, DROP...
 */
enum DbCommandType : ubyte
{
    text,
    storedProcedure,
    table,
    ddl,
}

enum DbCompressConnection : ubyte
{
    disabled,
    zip,
}

/**
 * Describes state of the connection
 * $(DbConnectionState.closed) The connection is closed
 * $(DbConnectionState.closing) The transition state to close
 * $(DbConnectionState.opening) The transition state to open
 * $(DbConnectionState.opened) The connection is open
 * $(DbConnectionState.failing) The transition state to failed
 * $(DbConnectionState.failed) The connection to the data source is not able to open. A connection in this state may be closed and then re-opened
 * $(DbConnectionState.disposed) The connection instance is no longer usable
 */
enum DbConnectionState : ubyte
{
    closed,  // Make this state first as default value
    closing,
    opening,
    opened,
    failing,
    failed,
    disposed,
}

enum DbConnectionType : ubyte
{
    connect, // Must be first as default
    create,
}

enum DbDefaultSize
{
    /**
     * Sizes in bytes
     */
    socketReadBufferLength = 131_000, // 1_024 * 128 = 131_072
    socketWriteBufferLength = 98_000, // 1_024 * 96 = 98_304

    /**
     * Default transaction lock timeout - value in seconds
     */
    transactionLockTimeout = 60,

    /**
     * Default maximum number of connections being in pool
     */
    connectionPoolLength = 100,

    /**
     * Default maximum inactive time of a connection being in pool - value in seconds
     */
    connectionPoolInactiveTime = 360,
}

/**
 * Describes how to client and server exchanged data
 * $(DbEncryptedConnection.disabled) The connection is open with no encryption
 * $(DbEncryptedConnection.enabled) The connection is open with available encryption
 * $(DbEncryptedConnection.required) The connection must support encryption otherwise error if not
 */
enum DbEncryptedConnection : ubyte
{
    disabled,
    enabled,
    required,
}

enum DbFetchResultStatus : ubyte
{
    ready,
    hasData,
    completed,
}

enum DbFieldIdType : ubyte
{
    no,
    array,
    blob,
    clob,
}

/**
 * Describes how to client send authenticated data to server
 * $(DbIntegratedSecurityConnection.legacy) name and password
 * $(DbIntegratedSecurityConnection.srp1)
 * $(DbIntegratedSecurityConnection.srp256)
 * $(DbIntegratedSecurityConnection.sspi)
 */
enum DbIntegratedSecurityConnection : ubyte
{
    legacy,
    srp1,
    srp256,
    sspi,
}

/**
 * Specifies the transaction locking behavior for the connection
 * $(DbIsolationLevel.unspecified) A different isolation level than the one specified is being used, but the level is determined by the driver that is being used
 * $(DbIsolationLevel.readUncommitted) A dirty read; no locks
 * $(DbIsolationLevel.readCommitted) Shared locks are held while the data is being read to avoid dirty reads, but the data can be changed before the end of the transaction
 * $(DbIsolationLevel.repeatableRead) Locks are placed on all data that is used in a query, preventing other users from updating the data
 * $(DbIsolationLevel.serializable) Locks are placed on all data that is used in a query, preventing other users from updating/inserting the data
 * $(DbIsolationLevel.snapshot) Indicates that from one transaction you cannot see changes made in other transactions, even if you requery (Reduces blocking)
 */
enum DbIsolationLevel : ubyte
{
    //unspecified,
    readUncommitted,
    readCommitted,
    repeatableRead,
    serializable,
    snapshot,
}

enum DbLockBehavior : ubyte
{
    shared_,
    protected_,
    exclusive,
}

enum DbLockType : ubyte
{
    read,
    write,
}

enum DbNameValueValidated : ubyte
{
    invalidName,
    duplicateName,
    invalidValue,
    ok,
}

/**
 * Describes the type of a parameter
 * $(DbParameterDirection.input) is an input parameter
 * $(DbParameterDirection.output) is an output parameter
 * $(DbParameterDirection.inputOutput) is both input and output parameter
 * $(DbParameterDirection.returnValue) is a return value from an operation such as a stored procedure...
 */
enum DbParameterDirection : ubyte
{
    input,
    inputOutput,
    output,
    returnValue,
}

/**
 * Default connection builder element names
 */
enum DbConnectionParameterIdentifier : string
{
    allowBatch = "allowBatch", /// bool
                               /// When true, multiple SQL statements can be sent with one command execution.
                               /// Batch statements should be separated by the server-defined separator character.
    charset = "charset", /// string
    commandTimeout = "commandTimeout", /// Duration in seconds
                                       /// Sets the default value of the command timeout to be used.
    compress = "compress", /// DbCompressConnection
    connectionTimeout = "connectionTimeout", /// Duration in seconds
    databaseName = "database", /// string
    databaseFile = "databaseFile", /// string
    encrypt = "encrypt", /// DbEncryptedConnection
    fetchRecordCount = "fetchRecordCount", /// uint32
    integratedSecurity = "integratedSecurity", /// DbIntegratedSecurityConnection
    maxPoolCount = "maxPoolCount", /// uint32
    minPoolCount = "minPoolCount", /// uint32
    packageSize = "packageSize", /// uint32
    pooling = "pooling", /// bool
    poolTimeout = "poolTimeout", /// Duration in seconds
    receiveTimeout = "receiveTimeout", /// Duration in seconds
    roleName = "role", /// string
    sendTimeout = "sendTimeout", /// Duration in seconds
    serverName = "server", /// string
    serverPort = "port", // uint16
    userName = "user", /// string
    userPassword = "password", /// string

    // For socket
    socketBlocking = "blocking", /// bool
    socketNoDelay = "noDelay", /// bool
    socketSslCa = "sslCa", /// string
    socketSslCaDir = "sslCaDir", /// string
    socketSslCert = "sslCert", /// string
    socketSslKey = "sslKey", /// string
    socketSslKeyPassword = "sslKeyPassword", /// string
    socketSslVerificationHost = "sslVerificationHost", /// bool
    socketSslVerificationMode = "sslVerificationMode", /// int
                                                       /// SSL_VERIFY_NONE, SSL_VERIFY_PEER, SSL_VERIFY_FAIL_IF_NO_PEER_CERT,
                                                       /// SSL_VERIFY_CLIENT_ONCE, ...

    // Specific to firebird
    fbCachePage = "cachePage", /// uint32
    fbCryptAlgorithm = "cryptAlgorithm", /// string - name of encrypt algorithm
    fbCryptKey = "cryptKey", /// ubyte[]
    fbDatabaseTrigger = "databaseTrigger", /// bool
    fbDialect = "dialect", /// int16
    fbDummyPacketInterval = "dummyPacketInterval", /// Duration in seconds
    fbGarbageCollect = "garbageCollect", /// bool

    // Specific to mysql
    myAllowUserVariables = "allowUserVariables", /// bool
                                                 /// Setting this to true indicates that the provider expects user variables in the SQL.

    // Specific to postgresql
    /*
    pgOptions = "options",
    pgPassFile = "passfile",
    pgFallbackApplicationName = "fallback_application_name",
    pgKeepAlives = "keepalives",
    pgKeepalivesIdle = "keepalives_idle",
    pgKeepalivesInterval = "keepalives_interval",
    pgKeepalivesCount = "keepalives_count",
    pgTty = "tty",
    pgReplication = "replication",
    pgGSSEncMode = "gssencmode",
    pgSSLCert = "sslcert",
    pgSSLKey = "sslkey",
    pgSSLRootCert = "sslrootcert",
    pgSSLCrl = "sslcrl",
    pgRequirePeer = "requirepeer",
    pgKRBSrvName = "krbsrvname",
    pgGSSLibib = "gsslib",
    pgService = "service",
    pgTargetSessionAttrs = "target_session_attrs"
    */
}

enum DbConnectionCustomIdentifier : string
{
    applicationName = "applicationName",
    applicationVersion = "applicationVersion",
    currentComputerName = "currentComputerName",
    currentProcessId = "currentProcessId",
    currentProcessName = "currentProcessName",
    currentUserName = "currentUserName",
}

enum DbScheme : string
{
    fb = "firebird",
    my = "mysql",
    pg = "postgresql",
    //sq = "sqlite",
}

enum DbSchemaColumnFlag : ubyte
{
    allowNull,
    isAlias,
    isKey,
    isUnique,
    isExpression,
}

enum DbServerIdentifier : string
{
    capabilityFlag = "serverCapabilityFlag",         // mysql
    dbVersion = "serverVersion",                       // firebird, postgresql
    protocolAcceptType = "serverProtocolAcceptType", // firebird
    protocolArchitect = "serverProtocolArchitect",   // firebird
	protocolCompressed = "serverProtocolCompressed", // firebird
	protocolEncrypted = "serverProtocolEncrypted",   // firebird
    protocolProcessId = "serverProtocolProcessId",   // postgresql, mysql-threadid
    protocolSecretKey = "serverProtocolSecretKey",   // postgresql
    protocolTrStatus = "serverProtocolTrStatus",     // postgresql
    protocolVersion = "serverProtocolVersion",       // firebird, mysql
}

/**
 * Describes state of the transaction
 * $(DbTransactionState.inactive) The transaction is inactive (not started it yet)
 * $(DbTransactionState.active) The transaction is active
 * $(DbTransactionState.error) The transaction was committed/rollbacked but failed
 * $(DbTransactionState.disposed) The transaction instance is no longer usable
 */
enum DbTransactionState : ubyte
{
    inactive,
    active,
    error,
    disposed,
}

/**
 * Describes data type of a DbField or a DbParameter
 * $(DbType.unknown) A unknown type
 * $(DbType.boolean) A simple type representing boolean values of true or false
 * $(DbType.int8) An integral type representing signed 8-bit integers with values between -128 and 127
 * $(DbType.int16) An integral type representing signed 16-bit integers with values between -32_768 and 32_767
 * $(DbType.int32) An integral type representing signed 32-bit integers with values between -2_147_483_648 and 2_147_483_647
 * $(DbType.int64) An integral type representing signed 64-bit integers with values between -9_223_372_036_854_775_808 and 9_223_372_036_854_775_807
 * $(DbType.decimal) A floating point type representing values ranging from 1.0 x 10 -28 to approximately 7.9 x 10 28 with 28-29 significant digits
 * $(DbType.float32) A floating point type representing values ranging from approximately 1.5 x 10 -45 to 3.4 x 10 38 with a precision of 7 digits
 * $(DbType.float64) A floating point type representing values ranging from approximately 5.0 x 10 -324 to 1.7 x 10 308 with a precision of 15-16 digits
 * $(DbType.date) A type representing a date value
 * $(DbType.datetime) A type representing a date and time value
 * $(DbType.datetimeTZ) A type representing a date and time value with time zone awareness
 * $(DbType.time) A type representing a time value
 * $(DbType.timeTZ) A type representing a time value with time zone awareness
 * $(DbType.chars) A simple fixed length type representing a utf8 character
 * $(DbType.string) A variable-length of utf8 characters
 * $(DbType.json) A parsed representation of an JSON document
 * $(DbType.xml) A parsed representation of an XML document or fragment
 * $(DbType.binary) A variable-length stream of binary data
 * $(DbType.text) A variable-length stream of text data
 * $(DbType.struct_) A type representing a struct/record
 * $(DbType.array) A type representing an array of value
 */
enum DbType : int
{
    unknown,
    boolean,
    int8,
    int16,
    int32,
    int64,
    int128,
    decimal,
    decimal32,
    decimal64,
    decimal128,
    numeric,  // Same as decimal
    float32,
    float64,
    date,
    datetime,
    datetimeTZ,
    time,
    timeTZ,
    uuid,
    fixedString,  // fixed length string - char[] (static length)
    string, // variable length string - string (has length limit)
    text,   // similar to string type but with special construct for each database (no length limit) - string
    json,   // string with json format - ubyte[]
    xml,    // string with xml format - ubyte[]
    fixedBinary,
    binary,
    record,     // struct is reserved keyword
    array = 1 << 31,
}

enum DbTypeMask = 0x7FFF_FFFF; // Exclude array marker

struct DbArrayBound
{
nothrow @safe:

public:
    int32 lower;
    int32 upper;
}

struct DbBaseType
{
nothrow @safe:

public:
    int32 numericScale;
    int32 size;
    int32 subTypeId;
    int32 typeId;
}

alias DbDate = Date;

struct DbDateTime
{
nothrow @safe:

public:
    this(DateTime datetime,
        uint16 zoneId = 0, int16 zoneOffset = 0) @nogc pure
    {
        this._value = datetime;
        this._zoneId = zoneId;
        this._zoneOffset = zoneOffset;
    }

    this(int32 validYear, int32 validMonth, int32 validDay,
        int32 validHour, int32 validMinute, int32 validSecond, int32 validMillisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        uint16 zoneId = 0, int16 zoneOffset = 0) @nogc pure
    {
        this(DateTime(validYear, validMonth, validDay, validHour, validMinute, validSecond, validMillisecond, kind), zoneId, zoneOffset);
    }

    int opCmp(scope const(DbDateTime) rhs) const @nogc pure
    {
        int result = _value.opCmp(rhs._value);
        if (result == 0)
        {
            result = cmp(_zoneId, rhs._zoneId);
            if (result == 0)
                result = cmp(_zoneOffset, rhs._zoneOffset);
        }
        return result;
    }

    int opCmp(scope const(DateTime) rhs) const @nogc pure
    {
        return this.opCmp(toDbDateTime(rhs));
    }

    // Do not use template function to support Variant
    // Some kind of compiler bug
    bool opEquals(scope const(DbDateTime) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(DateTime) rhs) const @nogc pure
    {
        return this.opEquals(toDbDateTime(rhs));
    }

    static DbDateTime toDbDateTime(scope const(DateTime) value) @nogc pure
    {
        return DbDateTime(value, 0, 0); //TODO search for zone_id
    }

    Duration toDuration() const @nogc pure
    {
        return _value.toDuration();
    }

    size_t toHash() const @nogc pure
    {
        return _value.toHash();
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString(buffer).toString();
    }

    ref Writer toString(Writer, Char = char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char))
    {
        _value.toString(sink);
        return DbTime.toStringOffset(sink, kind, zoneOffset);
    }

    typeof(this) toUTC() const
    {
        if (kind == DateTimeZoneKind.utc)
            return this;

        if (isTZ)
        {
            auto tzm = TimeZoneInfoMap.timeZoneMap(zoneId);
            if (tzm.isValid())
            {
                auto utcDT = tzm.info.convertDateTimeToUTC(_value);
                return DbDateTime(utcDT, 0, 0);
            }
        }

        auto tz = TimeZoneInfo.localTimeZone(_value.year);
        auto utcDT = tz.convertDateTimeToUTC(_value);
        return DbDateTime(utcDT, 0, 0);
    }

    @property Date date() const @nogc pure
    {
        return _value.date;
    }

    @property bool isTZ() const @nogc pure
    {
        return zoneId != 0 || zoneOffset != 0;
    }

    @property DateTimeZoneKind kind() const @nogc pure
    {
        return _value.kind;
    }

    @property static DbDateTime min() @nogc nothrow pure
    {
        return DbDateTime(DateTime.min);
    }

    @property Time time() const @nogc pure
    {
        return _value.time;
    }

    @property DateTime value() const @nogc pure
    {
        return _value;
    }

    @property static DbDateTime zero() @nogc nothrow pure
    {
        return DbDateTime(DateTime.zero);
    }

    @property uint16 zoneId() const @nogc pure
    {
        return _zoneId;
    }

    /**
     * Zone offset in minute
     */
    @property int16 zoneOffset() const @nogc pure
    {
        return _zoneOffset;
    }

    alias value this;

private:
    DateTime _value;
    uint16 _zoneId;
    int16 _zoneOffset;
}

struct DbGeoBox
{
nothrow @safe:

public:
    this(float64 left, float64 top, float64 right, float64 bottom) @nogc pure
    {
        this.leftTop.x = left;
        this.leftTop.y = top;
        this.rightBottom.x = right;
        this.rightBottom.y = bottom;
    }

    this(scope const(DbGeoPoint) leftTop, scope const(DbGeoPoint) rightBottom) @nogc pure
    {
        this.leftTop.x = leftTop.x;
        this.leftTop.y = leftTop.y;
        this.rightBottom.x = rightBottom.x;
        this.rightBottom.y = rightBottom.y;
    }

    float opCmp(scope const(DbGeoBox) rhs) const @nogc pure
    {
        const result = leftTop.opCmp(rhs.leftTop);
        return result == 0 ? rightBottom.opCmp(rhs.rightBottom) : result;
    }

    bool opEquals(scope const(DbGeoBox) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        return hashOf(rightBottom.y, hashOf(rightBottom.x, hashOf(leftTop.y, hashOf(leftTop.x))));
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString!(ShortStringBuffer!char, char)(buffer).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        put(sink, '(');
        leftTop.toString!(Writer, Char)(sink);
        put(sink, ',');
        rightBottom.toString!(Writer, Char)(sink);
        put(sink, ')');
        return sink;
    }

    pragma(inline, true)
    @property float64 bottom() const @nogc pure
    {
        return rightBottom.y;
    }

    @property ref typeof(this) bottom(float64 value) @nogc pure return
    {
        rightBottom.y = value;
        return this;
    }

    @property float64 height() const @nogc pure
    {
        return bottom - top;
    }

    @property bool isEmpty() @nogc pure return
    {
        return height == 0.0 && width == 0.0;
    }

    pragma(inline, true)
    @property float64 left() const @nogc pure
    {
        return leftTop.x;
    }

    @property ref typeof(this) left(float64 value) @nogc pure return
    {
        leftTop.x = value;
        return this;
    }

    pragma(inline, true)
    @property float64 right() const @nogc pure
    {
        return rightBottom.x;
    }

    @property ref typeof(this) right(float64 value) @nogc pure return
    {
        rightBottom.x = value;
        return this;
    }

    pragma(inline, true)
    @property float64 top() const @nogc pure
    {
        return leftTop.y;
    }

    @property ref typeof(this) top(float64 value) @nogc pure return
    {
        leftTop.y = value;
        return this;
    }

    @property float64 width() const @nogc pure
    {
        return right - left;
    }

public:
    DbGeoPoint leftTop; // left/top
    DbGeoPoint rightBottom; // right/bottom
}

struct DbGeoCircle
{
nothrow @safe:

public:
    this(float64 x, float64 y, float64 r) @nogc pure
    {
        this.x = x;
        this.y = y;
        this.r = r;
    }

    this(scope const(DbGeoPoint) center, float64 radius) @nogc pure
    {
        this.x = center.x;
        this.y = center.y;
        this.r = radius;
    }

    float opCmp(scope const(DbGeoCircle) rhs) const @nogc pure
    {
        auto result = cmp(x, rhs.x);
        if (result == 0)
        {
            result = cmp(y, rhs.y);
            if (result == 0)
                result = cmp(r, rhs.r);
        }
        return result;
    }

    bool opEquals(scope const(DbGeoCircle) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        return hashOf(r, hashOf(y, hashOf(x)));
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString!(ShortStringBuffer!char, char)(buffer).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        FormatSpec!Char spec;
        spec.spec = 'f';

        put(sink, "<(");
        formatValue(sink, x, spec);
        put(sink, ',');
        formatValue(sink, y, spec);
        put(sink, "),");
        formatValue(sink, r, spec);
        put(sink, '>');
        return sink;
    }

public:
    float64 x = 0.0;
    float64 y = 0.0;
    float64 r = 0.0; // Radius
}

struct DbGeoPath
{
nothrow @safe:

public:
    this(this) pure
    {
        this.points = points.dup;
    }

    float opCmp(scope const(DbGeoPath) rhs) const @nogc pure
    {
        return cmp(this, rhs);
    }

    bool opEquals(scope const(DbGeoPath) rhs) const @nogc pure
    {
        return this.points.length == rhs.points.length && cmp(this, rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        size_t result = open;
        foreach (i; 0..points.length)
            result = hashOf(points[i].hashOf(), result);
        return result;
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString!(ShortStringBuffer!char, char)(buffer).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        put(sink, open ? '[' : '(');
        foreach (i; 0..points.length)
        {
            if (i != 0)
                put(sink, ',');
            points[i].toString!(Writer, Char)(sink);
        }
        put(sink, open ? ']' : ')');
        return sink;
    }

public:
    DbGeoPoint[] points;
    bool open;
    
private:
    static float cmp(scope ref const(DbGeoPath) lhs, scope ref const(DbGeoPath) rhs) @nogc pure
    {
        const len = lhs.points.length <= rhs.points.length ? lhs.points.length : rhs.points.length;
        foreach (i; 0..len)
        {
            const c = lhs.points[i].opCmp(rhs.points[i]);
            if (c != 0)
                return c;
        }

        const c = .cmp(lhs.points.length, rhs.points.length);
        return c == 0 ? .cmp(cast(byte)lhs.open, cast(byte)rhs.open) : c;
    }        
}

struct DbGeoPolygon
{
nothrow @safe:

public:
    this(this) pure
    {
        this.points = points.dup;
    }

    float opCmp(scope const(DbGeoPolygon) rhs) const @nogc pure
    {
        return cmp(this, rhs);
    }

    bool opEquals(scope const(DbGeoPolygon) rhs) const @nogc pure
    {
        return this.points.length == rhs.points.length && cmp(this, rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        if (points.length == 0)
            return 0;

        auto result = points[0].hashOf();
        foreach (i; 1..points.length)
            result = hashOf(points[i].hashOf(), result);
        return result;
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString!(ShortStringBuffer!char, char)(buffer).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        put(sink, '(');
        foreach (i; 0..points.length)
        {
            if (i != 0)
                put(sink, ',');
            points[i].toString!(Writer, Char)(sink);
        }
        put(sink, ')');
        return sink;
    }

public:
    DbGeoPoint[] points;
    
private:
    static float cmp(scope ref const(DbGeoPolygon) lhs, scope ref const(DbGeoPolygon) rhs) @nogc pure
    {
        const len = lhs.points.length <= rhs.points.length ? lhs.points.length : rhs.points.length;
        foreach (const i; 0..len)
        {
            const c = lhs.points[i].opCmp(rhs.points[i]);
            if (c != 0)
                return c;
        }

        return .cmp(lhs.points.length, rhs.points.length);
    }
}

struct DbGeoPoint
{
nothrow @safe:

public:
    float opCmp(scope const(DbGeoPoint) rhs) const @nogc pure
    {
        const result = cmp(x, rhs.x);
        return result == 0 ? cmp(y, rhs.y) : result;
    }

    bool opEquals(scope const(DbGeoPoint) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        return hashOf(y, hashOf(x));
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString!(ShortStringBuffer!char, char)(buffer).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        FormatSpec!Char spec;
        spec.spec = 'f';

        put(sink, '(');
        formatValue(sink, x, spec);
        put(sink, ',');
        formatValue(sink, y, spec);
        put(sink, ')');
        return sink;
    }

public:
    float64 x = 0.0;
    float64 y = 0.0;
}

struct DbHandle
{
@nogc nothrow @safe:

public:
    enum notSetValue = ulong.max;
    enum dummyValue = ulong.max - 1;

    enum bool isHandleValue(T) = is(T == ulong) || is(T == long) || is(T == uint) || is(T == int);

    static union DbHandleStorage
    {
        ulong u64 = notSetValue;
        long i64;
        uint u32;
        int i32;
    }

    static void set(T)(ref DbHandleStorage storage, const(T) value) pure
    if (isHandleValue!T)
    {
        static if (is(T == ulong))
            storage.u64 = value;
        else static if (is(T == long))
            storage.i64 = value;
        else static if (is(T == uint))
        {
            storage.u64 = 0U; // Must clear it first
            storage.u32 = value;
        }
        else static if (is(T == int))
        {
            storage.u64 = 0U; // Must clear it first
            storage.i32 = value;
        }
        else
            static assert(0);
    }

public:
    this(T)(const(T) v) pure
    if (isHandleValue!T)
    {
        set(this.value, v);
    }

    ref typeof(this) opAssign(T)(const(T) rhs) pure return
    if (isHandleValue!T)
    {
        set(this.value, rhs);
        return this;
    }

    bool opCast(C: bool)() const pure
    {
        return isValid;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbHandle opCast(T)() const
    if (is(Unqual!T == DbHandle))
    {
        return this;
    }

    T opCast(T)() const pure
    if (isHandleValue!T)
    {
        return get!T();
    }

    int opCmp(scope const(DbHandle) rhs) const pure
    {
        return cmp(value.i64, rhs.value.i64);
    }

    bool opEquals(scope const(DbHandle) rhs) const pure
    {
        return opCmp(rhs) == 0;
    }

    pragma(inline, true)
    T get(T)() const pure
    if (isHandleValue!T)
    {
        static if (is(T == ulong))
            return value.u64;
        else static if (is(T == long))
            return value.i64;
        else static if (is(T == uint))
            return value.u32;
        else static if (is(T == int))
            return value.i32;
        else
            static assert(0);
    }

    void reset() pure
    {
        value.u64 = notSetValue;
    }

    void setDummy() pure
    {
        value.u64 = dummyValue;
    }

    @property bool isDummy() const pure
    {
        return value.u64 == dummyValue;
    }

    pragma(inline, true)
    @property bool isValid() const pure
    {
        return value.u64 != notSetValue;
    }

private:
    DbHandleStorage value;
}

struct DbId
{
@nogc nothrow @safe:

public:
    enum notSetValue = ulong(0U);
    enum dummyValue = ulong.max;

    enum bool isIdValue(T) = is(T == ulong) || is(T == long) || is(T == uint) || is(T == int);

    static union DbIdStorage
    {
        ulong u64 = notSetValue;
        long i64;
        uint u32;
        int i32;
    }

    static void set(T)(ref DbIdStorage storage, const(T) value) pure
    if (isIdValue!T)
    {
        static if (is(T == ulong))
            storage.u64 = value;
        else static if (is(T == long))
            storage.i64 = value;
        else static if (is(T == uint))
        {
            storage.u64 = 0U; // Must clear it first
            storage.u32 = value;
        }
        else static if (is(T == int))
        {
            storage.u64 = 0U; // Must clear it first
            storage.i32 = value;
        }
        else
            static assert(0);
    }

public:
    this(T)(const(T) v) pure
    if (isIdValue!T)
    {
        set(this.value, v);
    }

    ref typeof(this) opAssign(T)(const(T) rhs) pure return
    if (isIdValue!T)
    {
        set(this.value, rhs);
        return this;
    }

    bool opCast(C: bool)() const pure
    {
        return isValid;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbId opCast(T)() const
    if (is(Unqual!T == DbId))
    {
        return this;
    }

    T opCast(T)() const pure
    if (isIdValue!T)
    {
        return get!T();
    }

    int opCmp(scope const(DbId) rhs) const pure
    {
        return cmp(value.i64, rhs.value.i64);
    }

    bool opEquals(scope const(DbId) rhs) const pure
    {
        return opCmp(rhs) == 0;
    }

    pragma(inline, true)
    T get(T)() const pure
    if (isIdValue!T)
    {
        static if (is(T == ulong))
            return value.u64;
        else static if (is(T == long))
            return value.i64;
        else static if (is(T == uint))
            return value.u32;
        else static if (is(T == int))
            return value.i32;
        else
            static assert(0);
    }

    void reset() pure
    {
        value.u64 = notSetValue;
    }

    void setDummy() pure
    {
        value.u64 = dummyValue;
    }

    pragma(inline, true)
    @property bool isValid() const pure
    {
        return value.u64 != notSetValue;
    }

private:
    DbIdStorage value;
}

struct DbLockTable
{
nothrow @safe:

public:
    this(string tableName)
    {
        this(tableName, DbLockType.read, DbLockBehavior.shared_);
    }

    this(string tableName, DbLockType lockType, DbLockBehavior lockBehavior)
    {
        this._tableName = tableName;
        this.lockType = lockType;
        this.lockBehavior = lockBehavior;
    }

    @property string tableName()
    {
        return _tableName;
    }

    DbLockType lockType;
    DbLockBehavior lockBehavior;

private:
    string _tableName;
}

struct DbNotificationMessage
{
nothrow @safe:

    string message;
    int code;
}

struct DbRecordsAffected
{
@nogc nothrow @safe:

public:
    enum notSetValue = -1;

public:
    ref typeof(this) opAssign(T)(T rhs) pure return
    if (is(T == int) || is(T == long) || is(Unqual!T == DbRecordsAffected))
    {
        static if (is(T == int) || is(T == long))
            this.value = rhs;
        else
            this.value = rhs.value;
        return this;
    }

    ref typeof(this) opOpAssign(string op, T)(T rhs) pure return
    if (op == "+" && (is(T == int) || is(T == long) || is(Unqual!T == DbRecordsAffected)))
    {
        static if (is(T == int) || is(T == long))
        {
            if (rhs >= 0)
            {
                if (hasCount)
                    this.value += rhs;
                else
                    this.value = rhs;
            }
        }
        else
        {
            if (rhs.hasCount)
            {
                if (hasCount)
                    this.value += rhs.value;
                else
                    this.value = rhs.value;
            }
        }
        return this;
    }

    bool opCast(C: bool)() const pure
    {
        return hasCount;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbRecordsAffected opCast(T)() const
    if (is(Unqual!T == DbRecordsAffected))
    {
        return this;
    }

    void reset() pure
    {
        value = notSetValue;
    }

    @property bool hasCount() const pure
    {
        return value >= 0;
    }

    alias value this;

public:
    int64 value = notSetValue;
}

struct DbRecordsAffectedAggregate
{
@nogc nothrow @safe:

public:
    bool opCast(C: bool)() const pure
    {
        return hasCounts;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbRecordsAffectedAggregate opCast(T)() const
    if (is(Unqual!T == DbRecordsAffectedAggregate))
    {
        return this;
    }

    void reset() pure
    {
        deleteCount.reset();
        insertCount.reset();
        lastInsertedId.reset();
        selectCount.reset();
        updateCount.reset();
    }

    @property bool hasCounts() const pure
    {
        return deleteCount || insertCount || selectCount || updateCount;
    }

public:
	DbRecordsAffected deleteCount;
	DbRecordsAffected insertCount;
    DbRecordsAffected lastInsertedId;
	DbRecordsAffected selectCount;
	DbRecordsAffected updateCount;
}

struct DbTime
{
nothrow @safe:

public:
    this(Time time,
        uint16 zoneId = 0, int16 zoneOffset = 0) @nogc pure
    {
        this._value = time;
        this._zoneId = zoneId;
        this._zoneOffset = zoneOffset;
    }

    this(scope const Duration time,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        uint16 zoneId = 0, int16 zoneOffset = 0) @nogc pure
    {
        this(Time(Tick.durationToTicks(time), kind), zoneId, zoneOffset);
    }

    this(int32 validHour, int32 validMinute, int32 validSecond, int32 validMillisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        uint16 zoneId = 0, int16 zoneOffset = 0) @nogc pure
    {
        auto timeDuration = Duration.zero;
        if (validHour != 0)
            timeDuration += dur!"hours"(validHour);
        if (validMinute != 0)
            timeDuration += dur!"minutes"(validMinute);
        if (validSecond != 0)
            timeDuration += dur!"seconds"(validSecond);
        if (validMillisecond != 0)
            timeDuration += dur!"msecs"(validMillisecond);
        this(timeDuration, kind, zoneId, zoneOffset);
    }

    int opCmp(scope const(DbTime) rhs) const @nogc pure
    {
        int result = _value.opCmp(rhs._value);
        if (result == 0)
        {
            result = cmp(_zoneId, rhs._zoneId);
            if (result == 0)
                result = cmp(_zoneOffset, rhs._zoneOffset);
        }
        return result;
    }

    int opCmp(scope const(Time) rhs) const @nogc pure
    {
        return this.opCmp(DbTime(rhs, 0, 0));
    }

    // Do not use template function to support Variant
    // Some kind of compiler bug
    bool opEquals(scope const(DbTime) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(Time) rhs) const @nogc pure
    {
        return this.opEquals(DbTime(rhs));
    }

    static DbTime toDbTime(scope const(Time) value) @nogc pure
    {
        return DbTime(value, 0, 0); //TODO search for zone_id
    }

    Duration toDuration() const @nogc pure
    {
        return _value.toDuration();
    }

    size_t toHash() const @nogc pure
    {
        return _value.toHash();
    }

    string toString() const
    {
        ShortStringBuffer!char buffer;
        return toString(buffer).toString();
    }

    ref Writer toString(Writer, Char = char)(return ref Writer sink) const
    if (isOutputRange!(Writer, Char))
    {
        //scope (failure) assert(0, "Assume nothrow failed");

        _value.toString(sink);
        return toStringOffset(sink, kind, zoneOffset);
    }

    static ref Writer toStringOffset(Writer, Char = char)(return ref Writer sink, const(DateTimeZoneKind) kind, const(int16) validOffset)
    if (isOutputRange!(Writer, Char))
    {
        import std.math.algebraic : abs;
        import pham.utl.utl_object : toString;

        if (validOffset != 0)
        {
            byte h = void, m = void;
            TimeZoneInfo.offsetToISOPart(validOffset, h, m);
            ShortStringBuffer!Char buffer;
            toString(buffer, abs(h), 2);
            buffer.put(':');
            toString(buffer, m, 2);
            put(sink, h < 0 ? '-' : '+');
            put(sink, buffer.toString());
        }
        else if (kind == DateTimeZoneKind.utc)
            put(sink, 'Z');

        return sink;
    }

    typeof(this) toUTC() const
    {
        if (kind == DateTimeZoneKind.utc)
            return this;

        if (isTZ)
        {
            auto tzm = TimeZoneInfoMap.timeZoneMap(zoneId);
            if (tzm.isValid())
            {
                auto dt = DateTime.utcNow.date + _value;
                auto utcDT = tzm.info.convertDateTimeToUTC(dt);
                return DbTime(utcDT.time, 0);
            }
        }

        auto dt = DateTime.utcNow.date + _value;
        auto tz = TimeZoneInfo.localTimeZone(dt.year);
        auto utcDT = tz.convertDateTimeToUTC(dt);
        return DbTime(utcDT.time, 0, 0);
    }

    @property bool isTZ() const @nogc pure
    {
        return zoneId != 0 || zoneOffset != 0;
    }

    @property DateTimeZoneKind kind() const @nogc pure
    {
        return _value.kind;
    }

    @property static DbTime min() @nogc nothrow pure
    {
        return DbTime(Time.min);
    }

    @property Time value() const @nogc pure
    {
        return _value;
    }

    @property static DbTime zero() @nogc nothrow pure
    {
        return DbTime(Time.zero);
    }

    @property uint16 zoneId() const @nogc pure
    {
        return _zoneId;
    }

    /**
     * Zone offset in minute
     */
    @property int16 zoneOffset() const @nogc pure
    {
        return _zoneOffset;
    }

    alias value this;

private:
    Time _value;
    uint16 _zoneId;
    int16 _zoneOffset;
}

struct DbTimeSpan
{
nothrow @safe:

public:
    this(Duration timeSpan) @nogc pure
    {
        this._value = timeSpan;
    }

    this(scope const(DateTime) dateTime) @nogc pure
    {
        this._value = dateTime.toDuration();
    }

    this(scope const(Time) time) @nogc pure
    {
        this._value = time.toDuration();
    }

    int opCmp(scope const(DbTimeSpan) rhs) const @nogc pure
    {
        return cmp(this.ticks, rhs.ticks);
    }

    int opCmp(scope const(Duration) rhs) const @nogc pure
    {
        return opCmp(DbTimeSpan(rhs));
    }

    bool opEquals(scope const(DbTimeSpan) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(Duration) rhs) const @nogc pure
    {
        return opEquals(DbTimeSpan(rhs));
    }

    void getTime(out bool isNeg, out int day, out int hour, out int minute, out int second, out int microsecond) const @nogc pure
    {
        isNeg = isNegative;
        if (isNeg)
            (-_value).split!("days", "hours", "minutes", "seconds", "usecs")(day, hour, minute, second, microsecond);
        else
            _value.split!("days", "hours", "minutes", "seconds", "usecs")(day, hour, minute, second, microsecond);
        while (microsecond > 1_000_000)
            microsecond /= 10;
    }

    size_t toHash() const @nogc pure
    {
        return hashOf(ticks);
    }

    pragma(inline, true)
    static long toTicks(scope const(Duration) v) @nogc pure
    {
        return v.total!"nsecs"();
    }

    @property DateTime dateTime() const @nogc pure
    {
        const ticks = Tick.durationToTicks(_value);
        final switch (DateTime.isValidTicks(ticks))
        {
            case ErrorOp.none: return DateTime(ticks);
            case ErrorOp.underflow: return DateTime.min;
            case ErrorOp.overflow: return DateTime.max;
        }
    }

    pragma(inline, true)
    @property isNegative() const @nogc pure
    {
        return _value.isNegative;
    }

    pragma(inline, true)
    @property isZero() const @nogc pure
    {
        return _value == Duration.zero;
    }

    @property static DbTimeSpan min() @nogc pure
    {
        return DbTimeSpan(Duration.zero);
    }

    @property long ticks() const @nogc pure
    {
        return toTicks(_value);
    }

    @property Time time() const @nogc pure
    {
        return dateTime.time;
    }

    @property Duration value() const @nogc pure
    {
        return _value;
    }

    @property static DbTimeSpan zero() @nogc pure
    {
        return DbTimeSpan(Duration.zero);
    }

    alias value this;

private:
    Duration _value;
}

struct DbTypeInfo
{
    string dbName;
    string nativeName;
    int32 displaySize;
    int32 nativeSize;
    int32 nativeId;
    DbType dbType;
}

struct DbHost(S)
{
nothrow @safe:

public:
    bool isValid() const @nogc
    {
        return name.length != 0;
    }

public:
    S name;
    ushort port;
}

struct DbURL(S)
{
nothrow @safe:

public:
    DbHost!S firstHost()
    {
        foreach (ref h; hosts)
        {
            if (h.isValid())
                return h;
        }

        return hosts.length ? hosts[0] : DbHost!S.init;
    }

    bool isValid() const @nogc
    {
        return database.length != 0 && isValidHosts();
    }

    bool isValidHosts() const @nogc
    {
        foreach (ref h; hosts)
        {
            if (!h.isValid())
                return false;
        }
        return hosts.length != 0;
    }

    @property S option(S name) @nogc pure
    {
        import pham.utl.utl_text : valueOf;

        return options.valueOf!S(name, null);
    }

public:
    S database;
    DbHost!S[] hosts;
    NamedValue!S[] options;
    DbScheme scheme;
    S userName;
    S userPassword;
}

alias IsConnectionParameterValue = DbNameValueValidated function(string value) nothrow;

static immutable string[string] dbDefaultConnectionParameterValues;
static immutable IsConnectionParameterValue[string] dbIsConnectionParameterValues;

enum dynamicTypeSize = -1; // blob/text - no limit
enum runtimeTypeSize = -2; // fixed/vary length string/array - limit
enum unknownTypeSize = -3; // unknown or unsupport

static immutable DbTypeInfo[] dbNativeTypes = [
    // Native & Standard
    {dbName:"", nativeName:"bool", displaySize:5, nativeSize:bool.sizeof, nativeId:0, dbType:DbType.boolean},
    {dbName:"", nativeName:"byte", displaySize:4, nativeSize:int8.sizeof, nativeId:0, dbType:DbType.int8},
    {dbName:"", nativeName:"ubyte", displaySize:6, nativeSize:int16.sizeof, nativeId:0, dbType:DbType.int16},
    {dbName:"", nativeName:"short", displaySize:6, nativeSize:int16.sizeof, nativeId:0, dbType:DbType.int16},
    {dbName:"", nativeName:"ushort", displaySize:11, nativeSize:int32.sizeof, nativeId:0, dbType:DbType.int32},
    {dbName:"", nativeName:"int", displaySize:11, nativeSize:int32.sizeof, nativeId:0, dbType:DbType.int32},
    {dbName:"", nativeName:"uint", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"long", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"ulong", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"float", displaySize:17, nativeSize:float32.sizeof, nativeId:0, dbType:DbType.float32},
    {dbName:"", nativeName:"double", displaySize:21, nativeSize:float64.sizeof, nativeId:0, dbType:DbType.float64},
    {dbName:"", nativeName:"real", displaySize:21, nativeSize:float64.sizeof, nativeId:0, dbType:DbType.float64},
    {dbName:"", nativeName:"char", displaySize:1, nativeSize:1, nativeId:0, dbType:DbType.fixedString},
    {dbName:"", nativeName:"wchar", displaySize:1, nativeSize:2, nativeId:0, dbType:DbType.fixedString},
    {dbName:"", nativeName:"dchar", displaySize:1, nativeSize:4, nativeId:0, dbType:DbType.fixedString},
    {dbName:"", nativeName:"string", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:0, dbType:DbType.string},
    {dbName:"", nativeName:"wstring", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:0, dbType:DbType.string},
    {dbName:"", nativeName:"dstring", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:0, dbType:DbType.string},
    {dbName:"", nativeName:"ubyte[]", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:0, dbType:DbType.binary},
    {dbName:"", nativeName:"Date", displaySize:10, nativeSize:Date.sizeof, nativeId:0, dbType:DbType.date},
    {dbName:"", nativeName:"DateTime", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetime},
    {dbName:"", nativeName:"Time", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.time},
    {dbName:"", nativeName:"UUID", displaySize:32, nativeSize:UUID.sizeof, nativeId:0, dbType:DbType.uuid},

    // Library
    {dbName:"", nativeName:"DbDateTime", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetime},
    {dbName:"", nativeName:"DbTime", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.time},
    {dbName:"", nativeName:"Decimal", displaySize:34, nativeSize:Decimal128.sizeof, nativeId:0, dbType:DbType.decimal},
    {dbName:"", nativeName:"Decimal32", displaySize:17, nativeSize:Decimal32.sizeof, nativeId:0, dbType:DbType.decimal32},
    {dbName:"", nativeName:"Decimal64", displaySize:21, nativeSize:Decimal64.sizeof, nativeId:0, dbType:DbType.decimal64},
    {dbName:"", nativeName:"Decimal128", displaySize:34, nativeSize:Decimal128.sizeof, nativeId:0, dbType:DbType.decimal128},
    {dbName:"", nativeName:"Numeric", displaySize:34, nativeSize:Decimal128.sizeof, nativeId:0, dbType:DbType.numeric},

    {dbName:"", nativeName:Decimal32.stringof, displaySize:17, nativeSize:Decimal32.sizeof, nativeId:0, dbType:DbType.decimal32},
    {dbName:"", nativeName:Decimal64.stringof, displaySize:21, nativeSize:Decimal64.sizeof, nativeId:0, dbType:DbType.decimal64},
    {dbName:"", nativeName:Decimal128.stringof, displaySize:34, nativeSize:Decimal128.sizeof, nativeId:0, dbType:DbType.decimal128},

    // Alias
    {dbName:"", nativeName:"int8", displaySize:4, nativeSize:int8.sizeof, nativeId:0, dbType:DbType.int8},
    {dbName:"", nativeName:"uint8", displaySize:6, nativeSize:int16.sizeof, nativeId:0, dbType:DbType.int16},
    {dbName:"", nativeName:"int16", displaySize:6, nativeSize:int16.sizeof, nativeId:0, dbType:DbType.int16},
    {dbName:"", nativeName:"uint16", displaySize:11, nativeSize:int32.sizeof, nativeId:0, dbType:DbType.int32},
    {dbName:"", nativeName:"int32", displaySize:11, nativeSize:int32.sizeof, nativeId:0, dbType:DbType.int32},
    {dbName:"", nativeName:"uint32", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"int64", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"uint64", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"int128", displaySize:41, nativeSize:BigInteger.sizeof, nativeId:0, dbType:DbType.int128},
    {dbName:"", nativeName:"float32", displaySize:17, nativeSize:float32.sizeof, nativeId:0, dbType:DbType.float32},
    {dbName:"", nativeName:"float64", displaySize:21, nativeSize:float64.sizeof, nativeId:0, dbType:DbType.float64},
    {dbName:"", nativeName:"DateTimeTZ", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetimeTZ},
    {dbName:"", nativeName:"DbDate", displaySize:10, nativeSize:Date.sizeof, nativeId:0, dbType:DbType.date},
    {dbName:"", nativeName:"TimeOfDay", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.time},
    {dbName:"", nativeName:"TimeTZ", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.timeTZ},
    ];

static immutable DbTypeInfo*[DbType] dbTypeToDbTypeInfos;
static immutable DbTypeInfo*[string] nativeNameToDbTypeInfos;

static immutable char dbSchemeSeparator = ':';

DbType dbArrayOf(DbType elementType) @nogc pure
in
{
    assert(elementType != DbType.array);
}
do
{
    return (DbType.array | elementType);
}

DbType dbTypeOf(T)() @nogc pure
{
    if (auto e = T.stringof in nativeNameToDbTypeInfos)
        return (*e).dbType;

    static if (is(T == ubyte[]))
        return DbType.binary;
    else static if (is(T == struct))
        return DbType.record;
    else static if (isArray!T)
        return DbType.array;
    else
        return DbType.unknown;
}

bool isDbScheme(string schemeStr, ref DbScheme scheme) @nogc pure
{
    import std.traits : EnumMembers;

    if (schemeStr.length)
    {
        foreach (e; EnumMembers!DbScheme)
        {
            debug(debug_pham_db_db_type) debug writeln(__FUNCTION__, "(e=", e, " ? ", cast(string)e); //output: fb ? firebird ... }
            
            if (e == schemeStr)
            {
                scheme = e;
                return true;
            }
        }
    }

    return false;
}

bool isDbTypeHasSize(DbType rawType) @nogc pure
{
    switch (rawType)
    {
        case DbType.fixedString:
        case DbType.string:
        case DbType.text:
        case DbType.json:
        case DbType.xml:
        case DbType.fixedBinary:
        case DbType.binary:
        case DbType.record:
        case DbType.array:
            return true;
        default:
            return false;
    }
}

bool isDbTypeHasZeroSizeAsNull(DbType rawType) @nogc pure
{
    switch (rawType)
    {
        case DbType.text:
        case DbType.json:
        case DbType.xml:
        case DbType.fixedBinary:
        case DbType.binary:
        case DbType.record:
        case DbType.array:
            return true;
        default:
            return false;
    }
}

bool isDbTypeString(DbType rawType) @nogc pure
{
    return rawType == DbType.string
        || rawType == DbType.text
        || rawType == DbType.json
        || rawType == rawType.xml;
}

bool isDbFalse(scope const(char)[] s) @nogc pure
{
    if (s.length != 0)
    {
        foreach (f; boolFalses)
        {
            if (sicmp(s, f) == 0)
                return true;
        }
    }

    return false;
}

bool isDbTrue(scope const(char)[] s) @nogc pure
{
    if (s.length != 0)
    {
        foreach (t; boolTrues)
        {
            if (sicmp(s, t) == 0)
                return true;
        }
    }

    return false;
}

DbParameterDirection parameterModeToDirection(scope const(char)[] mode) @nogc pure
{
    return mode == "IN" || mode == "in"
        ? DbParameterDirection.input
        : (mode == "OUT" || mode == "out"
            ? DbParameterDirection.output
            : (mode == "INOUT" || mode == "inout"
                ? DbParameterDirection.inputOutput
                : DbParameterDirection.input));
}


// Any below codes are private
private:

DbNameValueValidated isConnectionParameter1K(string v)
{
    return v.length != 0 && v.length <= 1_000
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterAny(string v)
{
    return DbNameValueValidated.ok;
}

DbNameValueValidated isConnectionParameterAny200(string v)
{
    return v.length <= 200
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterAny1K(string v)
{
    return v.length <= 1_000
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterAny2K(string v)
{
    return v.length <= 2_000
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterLength(string v)
{
    return v.length != 0
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterBool(string v)
{
    return isDbFalse(v) || isDbTrue(v)
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterCharset(string v)
{
    return v == "UTF8" || v == "utf8"
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterDurationTimeout(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    int32 vint;
    if (parseIntegral!(string, int32)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    const vdur = dur!"seconds"(vint);
    return vdur >= minTimeoutDuration && vdur <= maxTimeoutDuration
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterCompress(string v)
{
    import std.traits : EnumMembers;
    import pham.utl.utl_enum_set : toName;

    if (v.length)
    {
        foreach (e; EnumMembers!DbCompressConnection)
        {
            if (toName(e) == v)
                return DbNameValueValidated.ok;
        }
    }

    return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterEncrypt(string v)
{
    import std.traits : EnumMembers;
    import pham.utl.utl_enum_set : toName;

    if (v.length)
    {
        foreach (e; EnumMembers!DbEncryptedConnection)
        {
            if (toName(e) == v)
                return DbNameValueValidated.ok;
        }
    }

    return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterFBDialect(string v)
{
    return v == "3"
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterIntegratedSecurity(string v)
{
    import std.traits : EnumMembers;
    import pham.utl.utl_enum_set : toName;

    if (v.length)
    {
        foreach (e; EnumMembers!DbIntegratedSecurityConnection)
        {
            if (toName(e) == v)
                return DbNameValueValidated.ok;
        }
    }

    return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterInt32Any(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    int32 vint;
    if (parseIntegral!(string, int32)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return DbNameValueValidated.ok;
}

DbNameValueValidated isConnectionParameterInt32Pos(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    int32 vint;
    if (parseIntegral!(string, int32)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return vint >= 0
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterUBytesAny(string v)
{
    import pham.utl.utl_array : ShortStringBuffer;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseBase64;
    import pham.utl.utl_utf8 : NoDecodeInputRange;

    if (v.length == 0)
        return DbNameValueValidated.ok;

    NoDecodeInputRange!(v, char) inputRange;
    ShortStringBuffer!ubyte result;
    if (parseBase64(result, inputRange) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return DbNameValueValidated.ok;
}

DbNameValueValidated isConnectionParameterUInt16Any(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    uint16 vint;
    if (parseIntegral!(string, uint16)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return DbNameValueValidated.ok;
}

DbNameValueValidated isConnectionParameterUInt32Any(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    uint32 vint;
    if (parseIntegral!(string, uint32)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return DbNameValueValidated.ok;
}

DbNameValueValidated isConnectionParameterUInt32_8K(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    uint32 vint;
    if (parseIntegral!(string, uint32)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return vint > 0 && vint <= 8_000
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterUInt32_256K(string v)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

    uint32 vint;
    if (parseIntegral!(string, uint32)(v, vint) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return vint > 0 && vint <= 256_000
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

shared static this() nothrow @safe
{
    dbDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbConnectionParameterIdentifier.charset : "UTF8",
            DbConnectionParameterIdentifier.compress : toName(DbCompressConnection.disabled),
            DbConnectionParameterIdentifier.connectionTimeout : "10", // In seconds
            DbConnectionParameterIdentifier.encrypt : toName(DbEncryptedConnection.disabled),
            DbConnectionParameterIdentifier.fetchRecordCount : "200",
            DbConnectionParameterIdentifier.integratedSecurity : toName(DbIntegratedSecurityConnection.srp256),
            DbConnectionParameterIdentifier.maxPoolCount : "100",
            DbConnectionParameterIdentifier.minPoolCount : "3",
            DbConnectionParameterIdentifier.pooling : dbBoolTrue,
            DbConnectionParameterIdentifier.poolTimeout : "30", // In seconds
            DbConnectionParameterIdentifier.receiveTimeout : "0", // In seconds - no limit
            DbConnectionParameterIdentifier.sendTimeout : "60", // In seconds
            DbConnectionParameterIdentifier.serverName : "localhost"
        ];
    }();

    dbIsConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(IsConnectionParameterValue[string]))[
            DbConnectionParameterIdentifier.allowBatch : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.charset : &isConnectionParameterCharset,
            DbConnectionParameterIdentifier.commandTimeout : &isConnectionParameterDurationTimeout,
            DbConnectionParameterIdentifier.compress : &isConnectionParameterCompress,
            DbConnectionParameterIdentifier.connectionTimeout : &isConnectionParameterDurationTimeout,
            DbConnectionParameterIdentifier.databaseName : &isConnectionParameterAny1K,
            DbConnectionParameterIdentifier.databaseFile : &isConnectionParameterAny2K,
            DbConnectionParameterIdentifier.encrypt : &isConnectionParameterEncrypt,
            DbConnectionParameterIdentifier.fetchRecordCount : &isConnectionParameterUInt32_8K,
            DbConnectionParameterIdentifier.integratedSecurity : &isConnectionParameterIntegratedSecurity,
            DbConnectionParameterIdentifier.maxPoolCount : &isConnectionParameterUInt32Any,
            DbConnectionParameterIdentifier.minPoolCount : &isConnectionParameterUInt32Any,
            DbConnectionParameterIdentifier.packageSize : &isConnectionParameterUInt32_256K,
            DbConnectionParameterIdentifier.pooling : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.poolTimeout : &isConnectionParameterDurationTimeout,
            DbConnectionParameterIdentifier.receiveTimeout : &isConnectionParameterDurationTimeout,
            DbConnectionParameterIdentifier.roleName : &isConnectionParameterAny200,
            DbConnectionParameterIdentifier.sendTimeout : &isConnectionParameterDurationTimeout,
            DbConnectionParameterIdentifier.serverName : &isConnectionParameterAny1K,
            DbConnectionParameterIdentifier.serverPort : &isConnectionParameterUInt16Any,
            DbConnectionParameterIdentifier.userName : &isConnectionParameterAny200,
            DbConnectionParameterIdentifier.userPassword : &isConnectionParameterAny200,
            DbConnectionParameterIdentifier.socketBlocking : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.socketNoDelay : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.socketSslCa : &isConnectionParameterAny2K,
            DbConnectionParameterIdentifier.socketSslCaDir : &isConnectionParameterAny2K,
            DbConnectionParameterIdentifier.socketSslCert : &isConnectionParameterAny2K,
            DbConnectionParameterIdentifier.socketSslKey : &isConnectionParameterAny2K,
            DbConnectionParameterIdentifier.socketSslKeyPassword : &isConnectionParameterAny200,
            DbConnectionParameterIdentifier.socketSslVerificationHost : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.socketSslVerificationMode : &isConnectionParameterInt32Any,
            DbConnectionParameterIdentifier.fbCachePage : &isConnectionParameterInt32Pos,
            DbConnectionParameterIdentifier.fbCryptKey : &isConnectionParameterUBytesAny,
            DbConnectionParameterIdentifier.fbDatabaseTrigger : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.fbDialect : &isConnectionParameterFBDialect,
            DbConnectionParameterIdentifier.fbDummyPacketInterval : &isConnectionParameterDurationTimeout,
            DbConnectionParameterIdentifier.fbGarbageCollect : &isConnectionParameterBool,
            DbConnectionParameterIdentifier.myAllowUserVariables : &isConnectionParameterBool,
            //DbConnectionParameterIdentifier. : &,
        ];
    }();

    dbTypeToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[DbType] result;
        foreach (ref e; dbNativeTypes)
        {
            if (!(e.dbType in result))
                result[e.dbType] = &e;
        }
        return result;
    }();

    nativeNameToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[string] result;
        foreach (ref e; dbNativeTypes)
        {
            if (!(e.nativeName in result))
                result[e.nativeName] = &e;
        }
        return result;
    }();
}

unittest // dbTypeOf
{
    //pragma(msg, "DbDateTime: ", DbDateTime.sizeof); // 24
    //pragma(msg, "SysTime: ", SysTime.sizeof); // 16
    //pragma(msg, "DateTime: ", DateTime.sizeof); // 8
    //pragma(msg, "Decimal128: ", Decimal128.sizeof); // 16
    //pragma(msg, "TimeOfDay: ", TimeOfDay.sizeof); // 3
    //pragma(msg, "Date: ", Date.sizeof); // 4

    assert(dbTypeOf!bool() == DbType.boolean);
    assert(dbTypeOf!char() == DbType.fixedString);
    assert(dbTypeOf!wchar() == DbType.fixedString);
    assert(dbTypeOf!dchar() == DbType.fixedString);
    assert(dbTypeOf!byte() == DbType.int8);
    assert(dbTypeOf!ubyte() == DbType.int16);
    assert(dbTypeOf!short() == DbType.int16);
    assert(dbTypeOf!ushort() == DbType.int32);
    assert(dbTypeOf!int() == DbType.int32);
    assert(dbTypeOf!uint() == DbType.int64);
    assert(dbTypeOf!long() == DbType.int64);
    assert(dbTypeOf!ulong() == DbType.int64);
    assert(dbTypeOf!float() == DbType.float32);
    assert(dbTypeOf!double() == DbType.float64);
    assert(dbTypeOf!real() == DbType.float64);
    assert(dbTypeOf!string() == DbType.string);
    assert(dbTypeOf!wstring() == DbType.string);
    assert(dbTypeOf!dstring() == DbType.string);
    assert(dbTypeOf!Date() == DbType.date);
    assert(dbTypeOf!DateTime() == DbType.datetime);
    assert(dbTypeOf!Time() == DbType.time);
    assert(dbTypeOf!DbTime() == DbType.time);
    assert(dbTypeOf!DbDateTime() == DbType.datetime);
    assert(dbTypeOf!(ubyte[])() == DbType.binary);
    assert(dbTypeOf!UUID() == DbType.uuid);
    assert(dbTypeOf!Decimal32() == DbType.decimal32, toName(dbTypeOf!Decimal32()));
    assert(dbTypeOf!Decimal64() == DbType.decimal64, toName(dbTypeOf!Decimal64()));
    assert(dbTypeOf!Decimal128() == DbType.decimal128, toName(dbTypeOf!Decimal128()));

    version(none)
    {
        struct SimpleStruct {}
        SimpleStruct r1;
        enum ris = is(SimpleStruct == struct);
        writeln("typeid(SimpleStruct): ", typeid(SimpleStruct));
        writeln("typeid(r1): ", typeid(r1));
        writeln("is(SimpleStruct == struct): ", ris);

        int[] a1;
        writeln(typeid(a1));

        float[4] a2;
        writeln(typeid(a2));

        class SimpleClass {}
        enum cis = is(SimpleClass == class);
        writeln("is(SimpleClass == class): ", cis);
    }
}

unittest // DbDateTime
{
    assert(DbDateTime(2020, 8, 27, 8, 0, 0, 0, DateTimeZoneKind.utc, 0, 65).toString() == "08/27/2020 8:00:00 AM+01:05");
    assert(DbDateTime(2020, 8, 27, 8, 0, 0, 0, DateTimeZoneKind.utc, 0, -65).toString() == "08/27/2020 8:00:00 AM-01:05");
}

unittest // DbTime
{
    assert(DbTime(8, 0, 0, 0, DateTimeZoneKind.utc, 0, 65).toString() == "8:00:00 AM+01:05");
    assert(DbTime(8, 0, 0, 0, DateTimeZoneKind.utc, 0, -65).toString() == "8:00:00 AM-01:05");
}
