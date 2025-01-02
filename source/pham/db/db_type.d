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
import core.time : convert;
import std.conv : to;
import std.format: FormatSpec, formatValue;
public import core.time : dur, Duration;
import std.range.primitives : ElementType, isOutputRange, put;
import std.traits : fullyQualifiedName, isArray, isSomeChar, Unqual;
import std.uni : sicmp;
public import std.uuid : UUID;

debug(debug_pham_db_db_type) import pham.db.db_debug;
public import pham.dtm.dtm_date : Date, DateTime;
public import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_tick : ErrorOp, Tick;
public import pham.dtm.dtm_time : Time;
import pham.dtm.dtm_time_zone : TimeZoneInfo;
public import pham.dtm.dtm_time_zone : ZoneOffset;
import pham.dtm.dtm_time_zone_map : TimeZoneInfoMap;
public import pham.external.dec.dec_decimal : Decimal32, Decimal64, Decimal128, isDecimal,
    Precision, RoundingMode;
import pham.utl.utl_array : ShortStringBuffer;
public import pham.utl.utl_big_integer : BigInteger;
import pham.utl.utl_enum_set : EnumSet, toName;
import pham.utl.utl_numeric_parser : ComputingSizeUnit, DurationUnit, NumericParsedKind,
    parseBase64, parseComputingSize, parseDuration, parseIntegral;
import pham.utl.utl_result : cmp;
import pham.utl.utl_text : NamedValue;
import pham.var.var_coerce;

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

static immutable string anonymousColumnNamePrefix = "_column";
static immutable string anonymousParameterNamePrefix = "_param";
static immutable string returnParameterName = "_return";

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
    prepare,
    nonQuery,
    reader,
    scalar,
}

enum DbCommandFlag : ubyte
{
    activeReader,
    allRowsFetched,
    batched,
    getExecutionPlanning,
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

enum DbDefault
{
    /**
     * Default maximum number of connections being in pool
     */
    connectionPoolLength = 100,

    /**
     * Default maximum inactive time of a connection being in pool - value in seconds
     */
    connectionPoolInactiveTime = 360,

    /**
     * Sizes in bytes
     */
    socketReadBufferLength = 131_000, // 1_024 * 128 = 131_072
    socketWriteBufferLength = 98_000, // 1_024 * 96 = 98_304

    /**
     * Default transaction lock timeout - value in seconds
     */
    transactionLockTimeout = 60,
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

/**
 * Describe the raw column value for database vendor data types
 * $(DbColumnIdType.no) The database vendor does not support such mechanizm
 * $(DbColumnIdType.array) Special handling for array column when retrieving & saving array data
 * $(DbColumnIdType.blob) Special handling for array column when retrieving & saving blob/binary data
 * $(DbColumnIdType.clob) Special handling for array column when retrieving & saving memo/text data
 */
enum DbColumnIdType : ubyte
{
    no,
    array,
    blob,
    clob,
}

deprecated("please use DbColumnIdType")
alias DbFieldIdType = DbColumnIdType;

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
    ok,
    duplicateName,
    invalidName,
    invalidValue,
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
    commandTimeout = "commandTimeout", /// Duration in milliseconds
                                       /// Sets the default value of the command timeout to be used.
    compress = "compress", /// DbCompressConnection
    connectionTimeout = "connectionTimeout", /// Duration in milliseconds
    databaseName = "database", /// string
    databaseFileName = "databaseFileName", /// string
    encrypt = "encrypt", /// DbEncryptedConnection
    fetchRecordCount = "fetchRecordCount", /// uint32
    integratedSecurity = "integratedSecurity", /// DbIntegratedSecurityConnection
    packageSize = "packageSize", /// uint32
    pooling = "pooling", /// bool
    poolIdleTimeout = "poolIdleTimeout", /// Duration in milliseconds
    poolMaxCount = "poolMaxCount", /// uint32
    poolMinCount = "poolMinCount", /// uint32
    receiveTimeout = "receiveTimeout", /// Duration in milliseconds
    roleName = "role", /// string
    sendTimeout = "sendTimeout", /// Duration in milliseconds
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

    // Specific to MS SQL
    // https://learn.microsoft.com/en-us/sql/relational-databases/native-client/applications/using-connection-string-keywords-with-sql-server-native-client?view=sql-server-ver15&viewFallbackFrom=sql-server-ver16
    msAddress = "Address",  // string - or Addr
    msApplicationName = "APP", // string - mapped to applicationName
    msApplicationIntent = "ApplicationIntent", // string - possible values: ReadOnly, ReadWrite
    msAttachDBFileName = "AttachDBFileName", // string - databaseFileName
    msAutoTranslate = "AutoTranslate", // bool - possible values: no, yes
    //msDatabase = "Database", // string - mapped-to/same-with databaseName
    msDriver = "Driver", // string
    msDSN = "DSN", // string
    //msEncrypt = "Encrypt", // mapped-to/same-with encrypt - possible values: no, yes, strict
    msFailoverPartner = "Failover_Partner", // string
    msFileDSN = "FileDSN", // string
    msLanguage = "Language", // string
    msMARSConnection = "MARS_Connection", // bool - possible values: no, yes
    msMultiSubnetFailover = "MultiSubnetFailover", // bool - possible values: no, yes
    msNetwork = "Network", // string - or Net
    msPWD = "PWD", // string - mapped to userPassword
    msQueryLogOn = "QueryLog_On", // bool - possible values: no, yes
    msQueryLogFile = "QueryLogFile", // string
    msQueryLogTime = "QueryLogTime", // Duration in milliseconds
    msQuotedId = "QuotedId", // bool - possible values: no, yes
    msRegional = "Regional", // bool - possible values: no, yes
    //msServer = "Server", // string - mapped-to/same-with serverName
    msTrustedConnection = "Trusted_Connection", // bool - mapped to integratedSecurity - possible values: no, yes
    msTrustServerCertificate = "TrustServerCertificate", // bool
    msUID = "UID", // string - mapped to userName
    msWSID = "WSID", // string - mapped to currentComputerName
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
    ms = "mssql", // Microsoft odbc
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
    dbVersion = "serverVersion",                     // firebird, postgresql
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
 * Describes data type of a DbColumn or a DbParameter
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
 * $(DbType.stringFixed) A simple fixed length type representing a utf8 character
 * $(DbType.stringVary) A variable-length of utf8 characters
 * $(DbType.json) A parsed representation of an JSON document
 * $(DbType.xml) A parsed representation of an XML document or fragment
 * $(DbType.binaryVary) A variable-length stream of binary data
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
    stringFixed,  // fixed length string - char[] (static length)
    stringVary, // variable length string - string (has length limit)
    text,   // similar to string type but with special construct for each database (no length limit) - string
    json,   // string with json format - ubyte[]
    xml,    // string with xml format - ubyte[]
    binaryFixed,
    binaryVary,
    record,     // struct is reserved keyword
    array = 1 << 31,
}

enum DbTypeMask = 0x7FFF_FFFF; // Exclude array marker

enum dynamicTypeSize = -1; // blob/text - no limit
enum runtimeTypeSize = -2; // fixed/vary length string/array - limit
enum unknownTypeSize = -3; // unknown or unsupport

enum DbTypeDisplaySize : int
{
    unknown = unknownTypeSize,
    boolean = 5, // true or false
    int8 = 3+1, // a sign and 3 digits
    int16 = 5+1, // a sign and 5 digits
    int32 = 10+1, // a sign and 10 digits
    int64 = 19+1, // a sign and 19 digits
    int128 = 39+1,
    decimal = 34+2, // The precision plus 2 (a sign, precision digits, and a decimal point)
    decimal32 = 7+2,
    decimal64 = 16+2,
    decimal128 = 34+2,
    numeric = 34+2, // Same as decimal
    float32 = 14, // a sign, 7 digits, a decimal point, the letter E, a sign, and 2 digits
    float64 = 24, // a sign, 15 digits, a decimal point, the letter E, a sign, and 3 digits
    date = 10, // yyyy-mm-dd
    datetime = 23, // yyyy-mm-dd hh:mm:ss.zzz
    datetimeTZ = 23+6, // yyyy-mm-dd hh:mm:ss.zzz+hh:mm
    time = 12, // hh:mm:ss.zzz
    timeTZ = 12+6, // hh:mm:ss.zzz+hh:mm
    uuid = 36, // xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    stringFixed = runtimeTypeSize, // fixed length string - char[] (static length)
    stringVary = dynamicTypeSize, // variable length string - string (has length limit)
    text = dynamicTypeSize, // similar to string type but with special construct for each database (no length limit) - string
    json = dynamicTypeSize, // string with json format - ubyte[]
    xml = dynamicTypeSize, // string with xml format - ubyte[]
    binaryFixed = runtimeTypeSize,
    binaryVary = dynamicTypeSize,
    record = runtimeTypeSize, // struct is reserved keyword
    array = dynamicTypeSize,
}

enum DbTypeSize : int
{
    unknown = unknownTypeSize,
    boolean = bool.sizeof,
    int8 = byte.sizeof,
    int16 = short.sizeof,
    int32 = int.sizeof,
    int64 = long.sizeof,
    int128 = BigInteger.sizeof+16,
    decimal = Decimal128.sizeof,
    decimal32 = Decimal32.sizeof,
    decimal64 = Decimal64.sizeof,
    decimal128 = Decimal128.sizeof,
    numeric = Decimal128.sizeof,
    float32 = float.sizeof,
    float64 = double.sizeof,
    date = DbDate.sizeof,
    datetime = DbDateTime.sizeof,
    datetimeTZ = DbDateTime.sizeof,
    time = DbTime.sizeof,
    timeTZ = DbTime.sizeof,
    uuid = UUID.sizeof,
    stringFixed = runtimeTypeSize,
    stringVary = dynamicTypeSize,
    text = dynamicTypeSize,
    json = dynamicTypeSize,
    xml = dynamicTypeSize,
    binaryFixed = runtimeTypeSize,
    binaryVary = dynamicTypeSize,
    record = runtimeTypeSize,
    array = dynamicTypeSize,
}

struct DbArrayBound
{
nothrow @safe:

public:
    int32 lower;
    int32 upper;
}

struct DbBaseTypeInfo
{
nothrow @safe:

public:
    this(int32 typeId, int32 subTypeId, int32 size,
        int16 numericDigits = 0,
        int16 numericScale = 0) @nogc pure
    {
        this.typeId = typeId;
        this.subTypeId = subTypeId;
        this.size = size;
        this.numericDigits = numericDigits;
        this.numericScale = numericScale;
    }

public:
    int32 size;
    int32 subTypeId;
    int32 typeId;
    int16 numericDigits;
    int16 numericScale;
}

enum dbConnectionParameterMaxFileName = 2_000;
enum dbConnectionParameterMaxId = 200;
enum dbConnectionParameterMaxName = 500;
enum dbConnectionParameterNullDef = null;
enum dbConnectionParameterNullMin = 0;
enum dbConnectionParameterNullMax = 0;

struct DbConnectionParameterInfo
{
nothrow @safe:

public:
    bool hasDef() const pure
    {
        return def.length != 0;
    }

    bool hasRange() const pure
    {
        return min != 0 || max != 0;
    }

    DbNameValueValidated isValidValue(string value) const
    {
        assert(isValidValueHandler !is null);

        return isValidValueHandler(this, value);
    }

public:
    alias IsValidValueHandler = DbNameValueValidated function(scope const(DbConnectionParameterInfo) info, string value) nothrow;

    IsValidValueHandler isValidValueHandler;
    string def;
    int32 min;
    int32 max;
    string scheme; // Blank means for all
}

alias DbDate = Date;

struct DbDateTime
{
nothrow @safe:

public:
    this(DateTime datetime,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this._value = datetime;
        this._zoneOffset = zoneOffset;
    }

    this(DbDate date, DbTime time) @nogc pure
    {
        this._value = DateTime(date, time.value);
        this._zoneOffset = time.zoneOffset;
    }

    this(int32 validYear, int32 validMonth, int32 validDay,
        int32 validHour, int32 validMinute, int32 validSecond, int32 validMillisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this(DateTime(validYear, validMonth, validDay, validHour, validMinute, validSecond, validMillisecond, kind), zoneOffset);
    }

    this(int32 validYear, int32 validMonth, int32 validDay,
        int32 validHour, int32 validMinute, int32 validSecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this(DateTime(validYear, validMonth, validDay, validHour, validMinute, validSecond, kind), zoneOffset);
    }

    int opCmp(scope const(DbDateTime) rhs) const @nogc pure
    {
        int result = _value.opCmp(rhs._value);
        if (result == 0)
            result = this._zoneOffset.opCmp(rhs._zoneOffset);
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
        return DbDateTime(value); //TODO search for zone_id
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

        if (_value.kind == DateTimeZoneKind.utc)
            put(sink, 'Z');
        else if (_zoneOffset.hasOffset)
            _zoneOffset.toString(sink);

        return sink;
    }

    typeof(this) toUTC() const
    {
        if (kind == DateTimeZoneKind.utc)
            return this;

        if (_zoneOffset.hasOffset)
            return DbDateTime(_value.addTicksClamp(_zoneOffset.toTicks()).asUTC);

        auto tz = TimeZoneInfo.localTimeZone(_value.year);
        return DbDateTime(tz.convertDateTimeToUTC(_value));
    }

    @property Date date() const @nogc pure
    {
        return _value.date;
    }

    @property bool isTZ() const @nogc pure
    {
        return _zoneOffset.hasOffset;
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

    /**
     * Zone offset in minute
     */
    @property ZoneOffset zoneOffset() const @nogc pure
    {
        return _zoneOffset;
    }

    alias value this;

private:
    DateTime _value;
    ZoneOffset _zoneOffset;
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

    enum bool isHandleValue(T) = is(Unqual!T == ulong) || is(Unqual!T == long)
        || is(Unqual!T == uint) || is(Unqual!T == int);

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
        alias UT = Unqual!T;
        static if (is(UT == ulong))
            storage.u64 = value;
        else static if (is(UT == long))
            storage.i64 = value;
        else static if (is(UT == uint))
        {
            storage.u64 = 0U; // Must clear it first
            storage.u32 = value;
        }
        else static if (is(UT == int))
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

    enum bool isIdValue(T) = is(Unqual!T == ulong) || is(Unqual!T == long)
        || is(Unqual!T == uint) || is(Unqual!T == int);

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
        alias UT = Unqual!T;
        static if (is(UT == ulong))
            storage.u64 = value;
        else static if (is(UT == long))
            storage.i64 = value;
        else static if (is(UT == uint))
        {
            storage.u64 = 0U; // Must clear it first
            storage.u32 = value;
        }
        else static if (is(UT == int))
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

    ref DbId reset() return
    {
        value.u64 = notSetValue;
        return this;
    }

    ref DbId setDummy() return
    {
        value.u64 = dummyValue;
        return this;
    }

    pragma(inline, true)
    @property bool isValid() const
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
    if (is(Unqual!T == int) || is(Unqual!T == long) || is(Unqual!T == DbRecordsAffected))
    {
        debug(debug_pham_db_db_type) debug writeln(__FUNCTION__, "(rhs=", rhs, ")");

        alias UT = Unqual!T;

        static if (is(UT == int) || is(UT == long))
            this.value = rhs;
        else
            this.value = rhs.value;
        return this;
    }

    ref typeof(this) opOpAssign(string op, T)(T rhs) pure return
    if (op == "+" && (is(Unqual!T == int) || is(Unqual!T == long) || is(Unqual!T == DbRecordsAffected)))
    {
        debug(debug_pham_db_db_type) debug writeln(__FUNCTION__, "(rhs=", rhs, ")");

        alias UT = Unqual!T;

        static if (is(UT == int) || is(UT == long))
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

    ref DbRecordsAffected reset() return
    {
        value = notSetValue;
        return this;
    }

    @property bool hasCount() const pure
    {
        return value >= 0;
    }

    alias value this;

public:
    int64 value = notSetValue;
}

enum DbRecordsAffectedAggregateResult
{
    changingOnly,
    queryingOnly,
    both,
}

struct DbRecordsAffectedAggregate
{
@nogc nothrow @safe:

public:
    bool opCast(C: bool)() const
    {
        return hasCounts;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbRecordsAffectedAggregate opCast(T)() const
    if (is(Unqual!T == DbRecordsAffectedAggregate))
    {
        return this;
    }

    ref DbRecordsAffectedAggregate reset() return
    {
        deleteCount.reset();
        insertCount.reset();
        selectCount.reset();
        updateCount.reset();
        lastInsertedId.reset();
        return this;
    }

    DbRecordsAffected toCount(const(DbRecordsAffectedAggregateResult) kind) const
    {
        DbRecordsAffected changingCount() const nothrow @safe
        {
            DbRecordsAffected result;
            if (deleteCount.hasCount)
                result += deleteCount;
            if (insertCount.hasCount)
                result += insertCount;
            if (updateCount.hasCount)
                result += updateCount;
            return result;
        }

        final switch(kind)
        {
            case DbRecordsAffectedAggregateResult.changingOnly:
                return changingCount();
            case DbRecordsAffectedAggregateResult.queryingOnly:
                return selectCount;
            case DbRecordsAffectedAggregateResult.both:
                DbRecordsAffected both = changingCount();
                if (selectCount.hasCount)
                    both += selectCount;
                return both;
        }
    }

    @property bool hasCounts() const
    {
        return deleteCount.hasCount || insertCount.hasCount || updateCount.hasCount
            || selectCount.hasCount;
    }

public:
	DbRecordsAffected deleteCount;
	DbRecordsAffected insertCount;
	DbRecordsAffected selectCount;
	DbRecordsAffected updateCount;
    DbId lastInsertedId;
}

struct DbTime
{
nothrow @safe:

public:
    this(Time time,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this._value = time;
        this._zoneOffset = zoneOffset;
    }

    this(scope const Duration time,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this(Time(Tick.durationToTicks(time), kind), zoneOffset);
    }

    this(int32 validHour, int32 validMinute, int32 validSecond, int32 validMillisecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this(Time(validHour, validMinute, validSecond, validMillisecond, kind), zoneOffset);
    }

    this(int32 validHour, int32 validMinute, int32 validSecond,
        DateTimeZoneKind kind = DateTimeZoneKind.unspecified,
        ZoneOffset zoneOffset = ZoneOffset.init) @nogc pure
    {
        this(Time(validHour, validMinute, validSecond, kind), zoneOffset);
    }

    int opCmp(scope const(DbTime) rhs) const @nogc pure
    {
        int result = _value.opCmp(rhs._value);
        if (result == 0)
            result = this._zoneOffset.opCmp(rhs._zoneOffset);
        return result;
    }

    int opCmp(scope const(Time) rhs) const @nogc pure
    {
        return this.opCmp(toDbTime(rhs));
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
        return DbTime(value); //TODO search for zone_id
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

        if (kind == DateTimeZoneKind.utc)
            put(sink, 'Z');
        else if (_zoneOffset.hasOffset)
            _zoneOffset.toString(sink);

        return sink;
    }

    typeof(this) toUTC() const
    {
        if (kind == DateTimeZoneKind.utc)
            return this;

        auto dt = DateTime.utcNow.date + _value;

        if (_zoneOffset.hasOffset)
            return DbTime(dt.addTicksClamp(_zoneOffset.toTicks()).asUTC.time);

        auto tz = TimeZoneInfo.localTimeZone(dt.year);
        return DbTime(tz.convertDateTimeToUTC(dt).time);
    }

    @property bool isTZ() const @nogc pure
    {
        return _zoneOffset.hasOffset;
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

    /**
     * Zone offset in minute
     */
    @property ZoneOffset zoneOffset() const @nogc pure
    {
        return _zoneOffset;
    }

    alias value this;

private:
    Time _value;
    ZoneOffset _zoneOffset;
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
    DbType dbType;
    int32 dbId;
    string nativeName;
    int32 nativeSize;
    int32 displaySize;
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

static immutable DbConnectionParameterInfo[string] dbDefaultConnectionParameterValues;

static immutable DbTypeInfo[] dbNativeTypes = [
    // Native & Standard
    {dbName:"BOOLEAN", dbType:DbType.boolean, dbId:0, nativeName:"bool", nativeSize:DbTypeSize.boolean, displaySize:DbTypeDisplaySize.boolean},
    {dbName:"TINYINT", dbType:DbType.int8, dbId:0, nativeName:"byte", nativeSize:DbTypeSize.int8, displaySize:DbTypeDisplaySize.int8},
    {dbName:"TINYINT", dbType:DbType.int8, dbId:0, nativeName:"ubyte", nativeSize:DbTypeSize.int8, displaySize:DbTypeDisplaySize.int8},
    {dbName:"SMALLINT", dbType:DbType.int16, dbId:0, nativeName:"short", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"SMALLINT", dbType:DbType.int16, dbId:0, nativeName:"ushort", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"INTEGER", dbType:DbType.int32, dbId:0, nativeName:"int", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"INTEGER", dbType:DbType.int32, dbId:0, nativeName:"uint", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"BIGINT", dbType:DbType.int64, dbId:0, nativeName:"long", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"BIGINT", dbType:DbType.int64, dbId:0, nativeName:"ulong", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"FLOAT", dbType:DbType.float32, dbId:0, nativeName:"float", nativeSize:DbTypeSize.float32, displaySize:DbTypeDisplaySize.float32},
    {dbName:"DOUBLE", dbType:DbType.float64, dbId:0, nativeName:"double", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"DOUBLE", dbType:DbType.float64, dbId:0, nativeName:"real", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"VARCHAR(?)", dbType:DbType.stringVary, dbId:0, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"VARCHAR(?)", dbType:DbType.stringVary, dbId:0, nativeName:"wstring", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"VARCHAR(?)", dbType:DbType.stringVary, dbId:0, nativeName:"dstring", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"CHAR(1)", dbType:DbType.stringFixed, dbId:0, nativeName:"char", nativeSize:char.sizeof, displaySize:1},
    {dbName:"CHAR(2)", dbType:DbType.stringFixed, dbId:0, nativeName:"wchar", nativeSize:char.sizeof*2, displaySize:1},
    {dbName:"CHAR(4)", dbType:DbType.stringFixed, dbId:0, nativeName:"dchar", nativeSize:char.sizeof*4, displaySize:1},
    {dbName:"VARBINARY(?)", dbType:DbType.binaryVary, dbId:0, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"VARBINARY(?)", dbType:DbType.binaryVary, dbId:0, nativeName:"byte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"DATE", dbType:DbType.date, dbId:0, nativeName:"DbDate", nativeSize:DbTypeSize.date, displaySize:DbTypeDisplaySize.date},
    {dbName:"DATETIME", dbType:DbType.datetime, dbId:0, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"TIME", dbType:DbType.time, dbId:0, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},
    {dbName:"CHAR(32)", dbType:DbType.uuid, dbId:0, nativeName:"UUID", nativeSize:DbTypeSize.uuid, displaySize:DbTypeDisplaySize.uuid},
    {dbName:"DECIMAL", dbType:DbType.decimal, dbId:0, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"NUMERIC", dbType:DbType.numeric, dbId:0, nativeName:"Numeric", nativeSize:DbTypeSize.numeric, displaySize:DbTypeDisplaySize.decimal},

    // Library
    {dbName:"DECIMAL(7,5)", dbType:DbType.decimal32, dbId:0, nativeName:"Decimal32", nativeSize:DbTypeSize.decimal32, displaySize:17},
    {dbName:"DECIMAL(7,5)", dbType:DbType.decimal32, dbId:0, nativeName:Decimal32.stringof, nativeSize:DbTypeSize.decimal32, displaySize:17},
    {dbName:"DECIMAL(7,5)", dbType:DbType.decimal32, dbId:0, nativeName:fullyQualifiedName!Decimal32, nativeSize:DbTypeSize.decimal32, displaySize:17},
    {dbName:"DECIMAL(16,9)", dbType:DbType.decimal64, dbId:0, nativeName:"Decimal64", nativeSize:DbTypeSize.decimal64, displaySize:21},
    {dbName:"DECIMAL(16,9)", dbType:DbType.decimal64, dbId:0, nativeName:Decimal64.stringof, nativeSize:DbTypeSize.decimal64, displaySize:21},
    {dbName:"DECIMAL(16,9)", dbType:DbType.decimal64, dbId:0, nativeName:fullyQualifiedName!Decimal64, nativeSize:DbTypeSize.decimal64, displaySize:21},
    {dbName:"DECIMAL(34,18)", dbType:DbType.decimal128, dbId:0, nativeName:"Decimal128", nativeSize:DbTypeSize.decimal128, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"DECIMAL(34,18)", dbType:DbType.decimal128, dbId:0, nativeName:Decimal128.stringof, nativeSize:DbTypeSize.decimal128, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"DECIMAL(34,18)", dbType:DbType.decimal128, dbId:0, nativeName:fullyQualifiedName!Decimal128, nativeSize:DbTypeSize.decimal128, displaySize:DbTypeDisplaySize.decimal},

    // Alias
    {dbName:"TINYINT", dbType:DbType.int8, dbId:0, nativeName:"int8", nativeSize:DbTypeSize.int8, displaySize:DbTypeDisplaySize.int8},
    {dbName:"TINYINT", dbType:DbType.int8, dbId:0, nativeName:"uint8", nativeSize:DbTypeSize.int8, displaySize:DbTypeDisplaySize.int8},
    {dbName:"SMALLINT", dbType:DbType.int16, dbId:0, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"SMALLINT", dbType:DbType.int16, dbId:0, nativeName:"uint16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"INTEGER", dbType:DbType.int32, dbId:0, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"INTEGER", dbType:DbType.int32, dbId:0, nativeName:"uint32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"BIGINT", dbType:DbType.int64, dbId:0, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"BIGINT", dbType:DbType.int64, dbId:0, nativeName:"uint64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"INT128?", dbType:DbType.int128, dbId:0, nativeName:"int128", nativeSize:DbTypeSize.int128, displaySize:DbTypeDisplaySize.int128},
    {dbName:"FLOAT", dbType:DbType.float32, dbId:0, nativeName:"float32", nativeSize:DbTypeSize.float32, displaySize:DbTypeDisplaySize.float32},
    {dbName:"DOUBLE", dbType:DbType.float64, dbId:0, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"DATE", dbType:DbType.date, dbId:0, nativeName:fullyQualifiedName!DbDate, nativeSize:DbTypeSize.date, displaySize:DbTypeDisplaySize.date},
    {dbName:"DATETIME", dbType:DbType.datetime, dbId:0, nativeName:fullyQualifiedName!DbDateTime, nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"TIME", dbType:DbType.time, dbId:0, nativeName:fullyQualifiedName!DbTime, nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},
    ];

static immutable DbTypeInfo*[DbType] dbTypeToDbTypeInfos;
static immutable DbTypeInfo*[string] nativeNameToDbTypeInfos;

static immutable char dbSchemeSeparator = ':';

pragma(inline, true)
DbType dbArrayOf(DbType elementType) @nogc pure
{
    return (DbType.array | elementType);
}

pragma(inline, true)
DbType dbArrayElementOf(DbType arrayType) @nogc pure
{
    return (~DbType.array & arrayType);
}

DbType dbTypeOf(T)() @nogc pure
{
    alias UT = Unqual!T;

    if (auto e = UT.stringof in nativeNameToDbTypeInfos)
        return (*e).dbType;

    static if (is(UT == ubyte[]))
        return DbType.binaryVary;
    else static if (is(UT == Date)) // Handling alias
        return DbType.date;
    else static if (is(UT == struct))
        return DbType.record;
    else static if (isArray!T)
        return dbArrayOf(dbTypeOf!(ElementType!UT)());
    else
        return DbType.unknown;
}

DbType decimalDbType(const(DbType) decimalType, const(int32) precision) @nogc pure
in
{
    assert(decimalType == DbType.decimal || decimalType == DbType.numeric);
}
do
{
    if (precision > 0)
    {
        if (precision <= Decimal32.PRECISION)
            return DbType.decimal32;
        else if (precision <= Decimal64.PRECISION)
            return DbType.decimal64;
    }
    return decimalType;
}

pragma(inline, true)
EnumSet!DbParameterDirection inputDirections(const(bool) inputOnly) @nogc pure
{
    return inputOnly
        ? EnumSet!DbParameterDirection([DbParameterDirection.input])
        : EnumSet!DbParameterDirection([DbParameterDirection.input, DbParameterDirection.inputOutput]);
}

pragma(inline, true)
EnumSet!DbParameterDirection outputDirections(const(bool) outputOnly) @nogc pure
{
    return outputOnly
        ? EnumSet!DbParameterDirection([DbParameterDirection.output, DbParameterDirection.returnValue])
        : EnumSet!DbParameterDirection([DbParameterDirection.output, DbParameterDirection.returnValue, DbParameterDirection.inputOutput]);
}

bool isDbScheme(string schemeStr, ref DbScheme scheme) @nogc pure
{
    import std.traits : EnumMembers;

    if (schemeStr.length == 0)
        return false;

    foreach (e; EnumMembers!DbScheme)
    {
        debug(debug_pham_db_db_type) debug writeln(__FUNCTION__, "(e=", e, " ? ", cast(string)e, ")"); //output: fb ? firebird ... }

        if (e == schemeStr)
        {
            scheme = e;
            return true;
        }
    }

    return false;
}

bool isDbTypeHasSize(const(DbType) rawType) @nogc pure
{
    switch (rawType)
    {
        case DbType.stringFixed:
        case DbType.stringVary:
        case DbType.text:
        case DbType.json:
        case DbType.xml:
        case DbType.binaryFixed:
        case DbType.binaryVary:
        case DbType.record:
        case DbType.array:
            return true;
        default:
            return false;
    }
}

bool isDbTypeHasZeroSizeAsNull(const(DbType) rawType) @nogc pure
{
    switch (rawType)
    {
        case DbType.text:
        case DbType.json:
        case DbType.xml:
        case DbType.binaryVary:
        case DbType.record:
        case DbType.array:
            return true;
        default:
            return false;
    }
}

bool isDbTypeQuoted(const(DbType) rawType) @nogc pure
{
    return isDbTypeString(rawType)
        || rawType == DbType.date
        || rawType == DbType.datetime
        || rawType == DbType.datetimeTZ
        || rawType == DbType.time
        || rawType == DbType.timeTZ
        || rawType == rawType.uuid;
}

bool isDbTypeString(const(DbType) rawType) @nogc pure
{
    return rawType == DbType.stringVary
        || rawType == DbType.stringFixed
        || rawType == DbType.text
        || rawType == DbType.json
        || rawType == rawType.xml;
}

bool isDbFalse(scope const(char)[] s) @nogc pure
{
    if (s.length == 0)
        return false;

    foreach (f; boolFalses)
    {
        if (sicmp(s, f) == 0)
            return true;
    }

    return false;
}

bool isDbTrue(scope const(char)[] s) @nogc pure
{
    if (s.length == 0)
        return false;

    foreach (t; boolTrues)
    {
        if (sicmp(s, t) == 0)
            return true;
    }

    return false;
}

bool isParameterInput(const(DbParameterDirection) direction, const(bool) inputOnly = false) @nogc pure
{
    static immutable inputFlags = [inputDirections(false), inputDirections(true)];

    return inputFlags[inputOnly].isOn(direction);
}

bool isParameterOutput(const(DbParameterDirection) direction, const(bool) outputOnly = false) @nogc pure
{
    static immutable outputFlags = [outputDirections(false), outputDirections(true)];

    return outputFlags[outputOnly].isOn(direction);
}

pragma(inline, true)
bool isInMode(scope const(char)[] mode) @nogc pure
{
    return mode == "IN" || mode == "in" || mode == "INPUT" || mode == "input";
}

pragma(inline, true)
bool isInOutMode(scope const(char)[] mode) @nogc pure
{
    return mode == "INOUT" || mode == "inout" || mode == "INOUTPUT" || mode == "inoutput";
}

pragma(inline, true)
bool isOutMode(scope const(char)[] mode) @nogc pure
{
    return mode == "OUT" || mode == "out" || mode == "OUTPUT" || mode == "output";
}

DbParameterDirection parameterModeToDirection(scope const(char)[] mode) @nogc pure
{
    return isInMode(mode)
        ? DbParameterDirection.input
        : (isOutMode(mode)
            ? DbParameterDirection.output
            : (isInOutMode(mode)
                ? DbParameterDirection.inputOutput
                : DbParameterDirection.input));
}

DbNameValueValidated cvtConnectionParameterBool(out bool cv, string v)
{
    if (isDbFalse(v))
    {
        cv = false;
        return DbNameValueValidated.ok;
    }
    else if (isDbTrue(v))
    {
        cv = true;
        return DbNameValueValidated.ok;
    }
    else
    {
        cv = false;
        return DbNameValueValidated.invalidValue;
    }
}

DbNameValueValidated isConnectionParameterBool(scope const(DbConnectionParameterInfo) info, string v)
{
    bool cv;
    return cvtConnectionParameterBool(cv, v);
}

DbNameValueValidated isConnectionParameterCharset(scope const(DbConnectionParameterInfo) info, string v)
{
    return v == "UTF8" || v == "utf8"
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated cvtConnectionParameterCompress(out DbCompressConnection cv, string v)
{
    import std.traits : EnumMembers;

    if (v.length == 0)
    {
        cv = DbCompressConnection.min;
        return DbNameValueValidated.invalidValue;
    }

    foreach (e; EnumMembers!DbCompressConnection)
    {
        if (toName(e) == v)
        {
            cv = e;
            return DbNameValueValidated.ok;
        }
    }

    cv = DbCompressConnection.min;
    return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterCompress(scope const(DbConnectionParameterInfo) info, string v)
{
    DbCompressConnection cv;
    return cvtConnectionParameterCompress(cv, v);
}

DbNameValueValidated cvtConnectionParameterComputingSize(out int32 cv, string v)
{
    long tcv;
    if (v.length == 0)
    {
        cv = 0;
        return DbNameValueValidated.invalidValue;
    }
    else if (parseComputingSize(v, ComputingSizeUnit.bytes, tcv) == NumericParsedKind.ok)
    {
        cv = tcv > int32.max ? int32.max : (tcv < int32.min ? int32.min : cast(int32)tcv);
        return DbNameValueValidated.ok;
    }
    else
        return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterComputingSize(scope const(DbConnectionParameterInfo) info, string v)
{
    int32 cv;
    if (cvtConnectionParameterComputingSize(cv, v) != DbNameValueValidated.ok)
        return DbNameValueValidated.invalidValue;

    return cv >= info.min && cv <= info.max
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

string cvtConnectionParameterDuration(scope const(Duration) v)
{
    const total = v.total!"msecs";
    return total > int32.max
        ? int32.max.to!string
        : (total < int32.min ? int32.min.to!string : total.to!string);
}

DbNameValueValidated cvtConnectionParameterDuration(out Duration cv, string v)
{
    if (v.length == 0)
    {
        cv = Duration.zero;
        return DbNameValueValidated.invalidValue;
    }
    else if (parseDuration(v, DurationUnit.msecs, cv) == NumericParsedKind.ok)
        return DbNameValueValidated.ok;
    else
        return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterDuration(scope const(DbConnectionParameterInfo) info, string v)
{
    Duration cv;
    if (cvtConnectionParameterDuration(cv, v) != DbNameValueValidated.ok)
        return DbNameValueValidated.invalidValue;

    const minDur = dur!"msecs"(info.min);
    const maxDur = dur!"msecs"(info.max);
    return cv >= minDur && cv <= maxDur
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated cvtConnectionParameterEncrypt(out DbEncryptedConnection cv, string v)
{
    import std.traits : EnumMembers;

    if (v.length == 0)
    {
        cv = DbEncryptedConnection.min;
        return DbNameValueValidated.invalidValue;
    }

    foreach (e; EnumMembers!DbEncryptedConnection)
    {
        if (toName(e) == v)
        {
            cv = e;
            return DbNameValueValidated.ok;
        }
    }

    cv = DbEncryptedConnection.min;
    return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterEncrypt(scope const(DbConnectionParameterInfo) info, string v)
{
    DbEncryptedConnection cv;
    return cvtConnectionParameterEncrypt(cv, v);
}

DbNameValueValidated isConnectionParameterFBDialect(scope const(DbConnectionParameterInfo) info, string v)
{
    return v == "3"
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterFBCryptAlgorithm(scope const(DbConnectionParameterInfo) info, string v)
{
    return (v == "ChaCha") || (v == "ChaCha64") || (v == "Arc4")
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated cvtConnectionParameterInt32(out int32 cv, string v)
{
    if (v.length == 0)
    {
        cv = 0;
        return DbNameValueValidated.invalidValue;
    }
    else if (parseIntegral(v, cv) == NumericParsedKind.ok)
        return DbNameValueValidated.ok;
    else
        return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterInt32(scope const(DbConnectionParameterInfo) info, string v)
{
    int32 cv;
    if (cvtConnectionParameterInt32(cv, v) != DbNameValueValidated.ok)
        return DbNameValueValidated.invalidValue;

    return cv >= info.min && cv <= info.max
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated cvtConnectionParameterIntegratedSecurity(out DbIntegratedSecurityConnection cv, string v)
{
    import std.traits : EnumMembers;

    if (v.length == 0)
    {
        cv = DbIntegratedSecurityConnection.min;
        return DbNameValueValidated.invalidValue;
    }

    foreach (e; EnumMembers!DbIntegratedSecurityConnection)
    {
        if (toName(e) == v)
        {
            cv = e;
            return DbNameValueValidated.ok;
        }
    }

    cv = DbIntegratedSecurityConnection.min;
    return DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterIntegratedSecurity(scope const(DbConnectionParameterInfo) info, string v)
{
    DbIntegratedSecurityConnection cv;
    return cvtConnectionParameterIntegratedSecurity(cv, v);
}

DbNameValueValidated isConnectionParameterMSApplicationIntent(scope const(DbConnectionParameterInfo) info, string v)
{
    return sicmp(v, "ReadOnly") == 0 || sicmp(v, "ReadWrite") == 0
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterMSEncrypt(scope const(DbConnectionParameterInfo) info, string v)
{
    return sicmp(v, "no") == 0 || sicmp(v, "yes") == 0 || sicmp(v, "strict") == 0
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterString(scope const(DbConnectionParameterInfo) info, string v)
{
    debug(debug_pham_db_db_type) debug writeln(__FUNCTION__, "(v=", v, ", info.min=", info.min, ", info.max=", info.max, ")");

    return v.length >= info.min && v.length <= info.max
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}

DbNameValueValidated isConnectionParameterUBytes(scope const(DbConnectionParameterInfo) info, string v)
{
    import pham.utl.utl_array : ShortStringBuffer;
    import pham.utl.utl_utf8 : NoDecodeInputRange;

    if (v.length == 0)
        return info.min == 0 ? DbNameValueValidated.ok : DbNameValueValidated.invalidValue;

    ShortStringBuffer!ubyte va;
    NoDecodeInputRange!(v, char) inputRange;
    if (parseBase64(va, inputRange) != NumericParsedKind.ok)
        return DbNameValueValidated.invalidValue;

    return va.length >= info.min && va.length <= info.max
        ? DbNameValueValidated.ok
        : DbNameValueValidated.invalidValue;
}


// Any below codes are private
private:

// Support Variant.coerce DbDate to DbDateTime
bool doCoerceDbDateToDbDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DbDateTime*)dstPtr = DbDateTime(*cast(DbDate*)srcPtr, DbTime.min);
    return true;
}

// Support Variant.coerce Date to DbDateTime
version(none) // Currently DbDate is same as Date
bool doCoerceDateToDbDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DbDateTime*)dstPtr = DbDateTime(*cast(Date*)srcPtr, DbTime.min);
    return true;
}

// Support Variant.coerce DbDateTime to DbDate
bool doCoerceDbDateTimeToDbDate(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DbDate*)dstPtr = (*cast(DbDateTime*)srcPtr).date;
    return true;
}

// Support Variant.coerce DbDateTime to DbTime
bool doCoerceDbDateTimeToDbTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    const s = *cast(DbDateTime*)srcPtr;
    *cast(DbTime*)dstPtr = DbTime(s.time, s.zoneOffset);
    return true;
}

// Support Variant.coerce DbDateTime to DateTime
bool doCoerceDbDateTimeToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DateTime*)dstPtr = (*cast(DbDateTime*)srcPtr).value;
    return true;
}

// Support Variant.coerce DateTime to DbDateTime
bool doCoerceDateTimeToDbDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DbDateTime*)dstPtr = DbDateTime(*cast(DateTime*)srcPtr);
    return true;
}

// Support Variant.coerce DbTime to DbDateTime
bool doCoerceDbTimeToDbDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DbDateTime*)dstPtr = DbDateTime(DbDate.min, *cast(DbTime*)srcPtr);
    return true;
}

// Support Variant.coerce DbTime to Time
bool doCoerceDbTimeToTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(Time*)dstPtr = (*cast(DbTime*)srcPtr).value;
    return true;
}

// Support Variant.coerce Time to DbTime
bool doCoerceTimeToDbTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DbTime*)dstPtr = DbTime(*cast(Time*)srcPtr);
    return true;
}

shared static this() nothrow @safe
{
    debug(debug_pham_db_db_type) debug writeln("shared static this(", __MODULE__, ")");

    dbDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(DbConnectionParameterInfo[string]))[
            DbConnectionParameterIdentifier.allowBatch : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.charset : DbConnectionParameterInfo(&isConnectionParameterCharset, "UTF8", dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.commandTimeout : DbConnectionParameterInfo(&isConnectionParameterDuration, dbConnectionParameterNullDef, 0, int32.max),
            DbConnectionParameterIdentifier.compress : DbConnectionParameterInfo(&isConnectionParameterCompress, toName(DbCompressConnection.disabled), dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.connectionTimeout : DbConnectionParameterInfo(&isConnectionParameterDuration, "10_000 msecs", 0, int32.max),
            DbConnectionParameterIdentifier.databaseName : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 1, dbConnectionParameterMaxName),
            DbConnectionParameterIdentifier.databaseFileName : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName),
            DbConnectionParameterIdentifier.encrypt : DbConnectionParameterInfo(&isConnectionParameterEncrypt, toName(DbEncryptedConnection.disabled), dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.fetchRecordCount : DbConnectionParameterInfo(&isConnectionParameterInt32, "200", -1, 65_000),
            DbConnectionParameterIdentifier.integratedSecurity : DbConnectionParameterInfo(&isConnectionParameterIntegratedSecurity, toName(DbIntegratedSecurityConnection.srp256), dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.packageSize : DbConnectionParameterInfo(&isConnectionParameterComputingSize, dbConnectionParameterNullDef, 4_096*2, 4_096*64),
            DbConnectionParameterIdentifier.pooling : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolFalse, dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.poolIdleTimeout : DbConnectionParameterInfo(&isConnectionParameterDuration, "300_000 msecs", 1_000, 60*60*60*1000),
            DbConnectionParameterIdentifier.poolMaxCount : DbConnectionParameterInfo(&isConnectionParameterInt32, "200", 1, 10_000),
            DbConnectionParameterIdentifier.poolMinCount : DbConnectionParameterInfo(&isConnectionParameterInt32, "0", 0, 1_000),
            DbConnectionParameterIdentifier.receiveTimeout : DbConnectionParameterInfo(&isConnectionParameterDuration, dbConnectionParameterNullDef, 0, int32.max),
            DbConnectionParameterIdentifier.roleName : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId),
            DbConnectionParameterIdentifier.sendTimeout : DbConnectionParameterInfo(&isConnectionParameterDuration, "60_000 msecs", 0, int32.max),
            DbConnectionParameterIdentifier.serverName : DbConnectionParameterInfo(&isConnectionParameterString, "localhost", 1, dbConnectionParameterMaxName),
            DbConnectionParameterIdentifier.serverPort : DbConnectionParameterInfo(&isConnectionParameterInt32, dbConnectionParameterNullDef, 0, uint16.max),
            DbConnectionParameterIdentifier.userName : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId),
            DbConnectionParameterIdentifier.userPassword : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId),

            // Socket
            DbConnectionParameterIdentifier.socketBlocking : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.socketNoDelay : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.socketSslCa : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName),
            DbConnectionParameterIdentifier.socketSslCaDir : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName),
            DbConnectionParameterIdentifier.socketSslCert : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName),
            DbConnectionParameterIdentifier.socketSslKey : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName),
            DbConnectionParameterIdentifier.socketSslKeyPassword : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId),
            DbConnectionParameterIdentifier.socketSslVerificationHost : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax),
            DbConnectionParameterIdentifier.socketSslVerificationMode : DbConnectionParameterInfo(&isConnectionParameterInt32, dbConnectionParameterNullDef, -1, uint16.max),

            // Firebird
            DbConnectionParameterIdentifier.fbCachePage : DbConnectionParameterInfo(&isConnectionParameterInt32, dbConnectionParameterNullDef, 0, int32.max, DbScheme.fb),
            DbConnectionParameterIdentifier.fbCryptAlgorithm : DbConnectionParameterInfo(&isConnectionParameterFBCryptAlgorithm, "Arc4", dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.fb),
            DbConnectionParameterIdentifier.fbCryptKey : DbConnectionParameterInfo(&isConnectionParameterUBytes, dbConnectionParameterNullDef, 0, uint16.max, DbScheme.fb),
            DbConnectionParameterIdentifier.fbDatabaseTrigger : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.fb),
            DbConnectionParameterIdentifier.fbDialect : DbConnectionParameterInfo(&isConnectionParameterFBDialect, "3", 1, 3, DbScheme.fb),
            DbConnectionParameterIdentifier.fbDummyPacketInterval : DbConnectionParameterInfo(&isConnectionParameterDuration, "300_000 msecs", 1_000, int32.max, DbScheme.fb),
            DbConnectionParameterIdentifier.fbGarbageCollect : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.fb),

            // MySQL
            DbConnectionParameterIdentifier.myAllowUserVariables : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.my),

            // MSSQL
            DbConnectionParameterIdentifier.msAddress : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
            DbConnectionParameterIdentifier.msApplicationName : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName, DbScheme.ms),
            DbConnectionParameterIdentifier.msApplicationIntent : DbConnectionParameterInfo(&isConnectionParameterMSApplicationIntent, "ReadWrite", dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msAttachDBFileName : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName, DbScheme.ms),
            DbConnectionParameterIdentifier.msAutoTranslate : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            //DbConnectionParameterIdentifier.msDatabase : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
            DbConnectionParameterIdentifier.msDriver : DbConnectionParameterInfo(&isConnectionParameterString, "{ODBC Driver 17 for SQL Server}", 0, dbConnectionParameterMaxName, DbScheme.ms),
            DbConnectionParameterIdentifier.msDSN : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
            //DbConnectionParameterIdentifier.msEncrypt : DbConnectionParameterInfo(&isConnectionParameterMSEncrypt, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msFailoverPartner : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
            DbConnectionParameterIdentifier.msFileDSN : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName, DbScheme.ms),
            DbConnectionParameterIdentifier.msLanguage : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId, DbScheme.ms),
            DbConnectionParameterIdentifier.msMARSConnection : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msMultiSubnetFailover : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msNetwork : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
            DbConnectionParameterIdentifier.msPWD : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId, DbScheme.ms),
            DbConnectionParameterIdentifier.msQueryLogOn : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msQueryLogFile : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxFileName, DbScheme.ms),
            DbConnectionParameterIdentifier.msQueryLogTime : DbConnectionParameterInfo(&isConnectionParameterDuration, dbConnectionParameterNullDef, 0, int32.max, DbScheme.ms),
            DbConnectionParameterIdentifier.msQuotedId : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolFalse, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msRegional : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            //DbConnectionParameterIdentifier.msServer : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
            DbConnectionParameterIdentifier.msTrustedConnection : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msTrustServerCertificate : DbConnectionParameterInfo(&isConnectionParameterBool, dbConnectionParameterNullDef, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.ms),
            DbConnectionParameterIdentifier.msUID : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxId, DbScheme.ms),
            DbConnectionParameterIdentifier.msWSID : DbConnectionParameterInfo(&isConnectionParameterString, dbConnectionParameterNullDef, 0, dbConnectionParameterMaxName, DbScheme.ms),
        ];
    }();

    dbTypeToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[DbType] result;
        foreach (i; 0..dbNativeTypes.length)
        {
            const dbType = dbNativeTypes[i].dbType;
            if (!(dbType in result))
                result[dbType] = &dbNativeTypes[i];
        }
        return result;
    }();

    nativeNameToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[string] result;
        foreach (i; 0..dbNativeTypes.length)
        {
            const nativeName = dbNativeTypes[i].nativeName;
            if (!(nativeName in result))
                result[nativeName] = &dbNativeTypes[i];
        }
        return result;
    }();

    // Support Variant.coerce
    ConvertHandler handler;
    handler.doCast = null;

    // DbDate
    handler.doCoerce = &doCoerceDbDateTimeToDbDate;
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.add!(DbDateTime, DbDate)(handler);
    ConvertHandler.add!(const(DbDateTime), DbDate)(handler);

    // DbDateTime
    handler.doCoerce = &doCoerceDbDateToDbDateTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.add!(DbDate, DbDateTime)(handler);
    ConvertHandler.add!(const(DbDate), DbDateTime)(handler);

    handler.doCoerce = &doCoerceDbTimeToDbDateTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.add!(DbTime, DbDateTime)(handler);
    ConvertHandler.add!(const(DbTime), DbDateTime)(handler);

    handler.doCoerce = &doCoerceDbDateTimeToDateTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.add!(DbDateTime, DateTime)(handler);
    ConvertHandler.add!(const(DbDateTime), DateTime)(handler);

    handler.doCoerce = &doCoerceDateTimeToDbDateTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.add!(DateTime, DbDateTime)(handler);
    ConvertHandler.add!(const(DateTime), DbDateTime)(handler);

    // DbTime
    handler.doCoerce = &doCoerceDbDateTimeToDbTime;
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.add!(DbDateTime, DbTime)(handler);
    ConvertHandler.add!(const(DbDateTime), DbTime)(handler);

    handler.doCoerce = &doCoerceDbTimeToTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.add!(DbTime, Time)(handler);
    ConvertHandler.add!(const(DbTime), Time)(handler);

    handler.doCoerce = &doCoerceTimeToDbTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.add!(Time, DbTime)(handler);
    ConvertHandler.add!(const(Time), DbTime)(handler);
}

unittest // dbArrayOf
{
    assert(dbArrayOf(DbType.boolean) == (DbType.array|DbType.boolean));
    assert(dbArrayOf(DbType.stringVary) == (DbType.array|DbType.stringVary));
}

unittest // dbArrayElementOf
{
    assert(dbArrayElementOf(dbArrayOf(DbType.boolean)) == DbType.boolean);
    assert(dbArrayElementOf(dbArrayOf(DbType.stringVary)) == DbType.stringVary);
    assert(dbArrayElementOf(dbArrayOf(DbType.float64)) == DbType.float64);
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
    assert(dbTypeOf!char() == DbType.stringFixed);
    assert(dbTypeOf!wchar() == DbType.stringFixed);
    assert(dbTypeOf!dchar() == DbType.stringFixed);
    assert(dbTypeOf!byte() == DbType.int8);
    assert(dbTypeOf!ubyte() == DbType.int8);
    assert(dbTypeOf!short() == DbType.int16);
    assert(dbTypeOf!ushort() == DbType.int16);
    assert(dbTypeOf!int() == DbType.int32);
    assert(dbTypeOf!uint() == DbType.int32);
    assert(dbTypeOf!long() == DbType.int64);
    assert(dbTypeOf!ulong() == DbType.int64);
    assert(dbTypeOf!float() == DbType.float32);
    assert(dbTypeOf!double() == DbType.float64);
    assert(dbTypeOf!real() == DbType.float64);
    assert(dbTypeOf!string() == DbType.stringVary);
    assert(dbTypeOf!wstring() == DbType.stringVary);
    assert(dbTypeOf!dstring() == DbType.stringVary);
    //assert(dbTypeOf!Date() == DbType.date);
    //assert(dbTypeOf!DateTime() == DbType.datetime);
    //assert(dbTypeOf!Time() == DbType.time);
    assert(dbTypeOf!DbDate() == DbType.date);
    assert(dbTypeOf!DbDateTime() == DbType.datetime);
    assert(dbTypeOf!DbTime() == DbType.time);
    assert(dbTypeOf!(ubyte[])() == DbType.binaryVary);
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
    assert(DbDateTime(2020, 8, 27, 8, 0, 0, 0, DateTimeZoneKind.utc, ZoneOffset(65)).toString() == "08/27/2020 8:00:00 AMZ");
    assert(DbDateTime(2020, 8, 27, 8, 0, 0, 0, DateTimeZoneKind.utc, ZoneOffset(-65)).toString() == "08/27/2020 8:00:00 AMZ");
}

unittest // DbTime
{
    assert(DbTime(8, 0, 0, 0, DateTimeZoneKind.utc, ZoneOffset(65)).toString() == "8:00:00 AMZ");
    assert(DbTime(8, 0, 0, 0, DateTimeZoneKind.utc, ZoneOffset(-65)).toString() == "8:00:00 AMZ");
}

unittest // DbConnectionParameterIdentifier & dbDefaultConnectionParameterValues
{
    import std.traits : EnumMembers;

    // Make sure all members of DbConnectionParameterIdentifier added to dbDefaultConnectionParameterValues
    foreach (e; EnumMembers!DbConnectionParameterIdentifier)
    {
        auto f = e in dbDefaultConnectionParameterValues;
        assert(f !is null);
    }
}
