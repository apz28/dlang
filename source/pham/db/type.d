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

module pham.db.type;

import core.time : convert;
import std.datetime.date : DateTime, TimeOfDay;
import std.datetime.systime : SysTime;
import std.range.primitives : isOutputRange, put;
import std.traits : isArray, Unqual;
import std.uni : sicmp;

public import core.time : Duration, dur;
public import std.datetime.date : Date;
public import std.datetime.timezone : LocalTime, SimpleTimeZone, TimeZone, UTC;
public import std.uuid : UUID;
public import decimal.decimal; // : Decimal

import pham.utl.enum_set;
import pham.db.convert : removeDate, timeOfDayToDuration, toDate;
import pham.db.timezone;

alias Decimal = decimal.decimal.Decimal!128;
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

union Map16Bit
{
    uint16 u;
    int16 i;
}

union Map32Bit
{
    uint32 u; // Make this first to have zero initialized value
    int32 i;
    float32 f;
}

union Map64Bit
{
    uint64 u; // Make this first to have zero initialized value
    int64 i;
    float64 f;
}

nothrow @safe:

enum hnsecsPerDay = convert!("hours", "hnsecs")(24);
//enum hnsecsPerHour = convert!("hours", "hnsecs")(1);
enum nullDate = Date(0, 1, 1);
immutable SysTime nullDateTimeLocal, nullDateTimeTZ;

enum DbFieldIdType : byte
{
    no,
    array,
    blob,
    clob
}

enum DbCommandExecuteType : byte
{
    nonQuery,
    reader,
    scalar
}

enum DbCommandFlag : byte
{
    allRowsFetched,
    implicitTransaction,
    implicitTransactionStarted,
    parametersCheck,
    returnRecordsAffected,
    transactionRequired,
    cancelled
}

enum DbCommandState : byte
{
	closed,
    unprepared,
    prepared,
	executed,
	error
}

/**
 * Describes how a command string is interpreted
 * $(DbCommandType.text) An SQL text command
 * $(DbCommandType.storedProcedure) The name of a stored procedure
 * $(DbCommandType.table) The name of a table or view
 */
enum DbCommandType : byte
{
    text,
    storedProcedure,
    table
}

/**
 * Describes state of the connection
 * $(DbConnectionState.closed) The connection is closed
 * $(DbConnectionState.closing) The transition state to close
 * $(DbConnectionState.opening) The transition state to open
 * $(DbConnectionState.open) The connection is open
 * $(DbConnectionState.failing) The transition state to fail
 * $(DbConnectionState.failed) The connection to the data source is not able to open. A connection in this state may be closed and then re-opened
 */
enum DbConnectionState : byte
{
    closed,  // Make this state first as default value
    closing,
    opening,
    open,
    failing,
    failed
}

enum DbDateTimeKind : byte
{
    unspecified,
    utc,
    local
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
}

/**
 * Describes how to client and server exchanged data
 * $(DbEncryptedConnection.disabled) The connection is open with no encryption
 * $(DbEncryptedConnection.enabled) The connection is open with available encryption
 * $(DbEncryptedConnection.required) The connection must support encryption otherwise error if not
 */
enum DbEncryptedConnection : byte
{
    disabled,
    enabled,
    required
}

enum DbFetchResultStatus : byte
{
    ready,
    hasData,
    completed
}

/**
 * Describes how to client send authenticated data to server
 * $(DbIntegratedSecurityConnection.srp)
 * $(DbIntegratedSecurityConnection.sspi)
 * $(DbIntegratedSecurityConnection.legacy) name and password
 */
enum DbIntegratedSecurityConnection : byte
{
    srp,
    srp256,
    sspi,
    legacy
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
enum DbIsolationLevel : byte
{
    //unspecified,
    readUncommitted,
    readCommitted,
    repeatableRead,
    serializable,
    snapshot
}

enum DbLockBehavior : byte
{
    shared_,
    protected_,
    exclusive
}

enum DbLockType : byte
{
    read,
    write
}

/**
 * Describes the type of a parameter
 * $(DbParameterDirection.input) is an input parameter
 * $(DbParameterDirection.output) is an output parameter
 * $(DbParameterDirection.inputOutput) is both input and output parameter
 * $(DbParameterDirection.returnValue) is a return value from an operation such as a stored procedure...
 */
enum DbParameterDirection : byte
{
    input,
    inputOutput,
    output,
    returnValue
}

/**
 * Default connection builder element names
 */
enum DbParameterName
{
    applicationVersion = "applicationVersion",
    charset = "charset",
    compress = "compress",
    connectionTimeout = "connectionTimeout",
    database = "database",
    databaseFile = "databaseFile",
    encrypt = "encrypt",
    fetchRecordCount = "fetchRecordCount",
    integratedSecurity = "integratedSecurity",
    maxPoolCount = "maxPoolCount",
    minPoolCount = "minPoolCount",
    packageSize = "packageSize",
    port = "port",
    pooling = "pooling",
    poolTimeout = "poolTimeout",
    receiveTimeout = "receiveTimeout",
    roleName = "role",
    sendTimeout = "sendTimeout",
    server = "server",
    userName = "user",
    userPassword = "password",

    // For socket
    socketBlocking = "blocking",
    socketNoDelay = "noDelay",

    // Specific to firebird
    fbCachePage = "cachePage",
    fbDatabaseTrigger = "databaseTrigger",
    fbDialect = "dialect",
    fbDummyPacketInterval = "dummyPacketInterval",
    fbGarbageCollect = "garbageCollect",

    // Specific to postgresql
    pgOptions = "options",
    /*
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

enum DbScheme : string
{
    fb = "firebird",
    //lt = "sqlite",
    //my = "mysql",
    pg = "postgresql"
}

enum DbSchemaColumnFlag : byte
{
    allowNull,
    isAlias,
    isKey,
    isUnique,
    isExpression
}

/**
 * Describes state of the transaction
 * $(DbTransactionState.inactive) The transaction is inactive (not started it yet)
 * $(DbTransactionState.active) The transaction is active
 * $(DbTransactionState.error) The transaction was committed/rollbacked but failed
 * $(DbTransactionState.disposed) The transaction instance is no longer usable
 */
enum DbTransactionState : byte
{
    inactive,
    active,
    error,
    disposed
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
enum DbType
{
    unknown,
    boolean,
    int8,
    int16,
    int32,
    int64,
    decimal,
    float32,
    float64,
    date,
    datetime,
    datetimeTZ,
    time,
    timeTZ,
    uuid,
    chars,  // fixed length string - char[] (static length)
    string, // variable length string - string (has length limit)
    text,   // similar to string type but with special construct for each database (no length limit) - string
    json,   // string with json format - ubyte[]
    xml,    // string with xml format - ubyte[]
    binary,
    record,     // struct is reserved keyword
    array = 1 << 31
}

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

struct DbDateTime
{
nothrow @safe:

public:
    this(SysTime datetime, uint16 zoneId, DbDateTimeKind kind)
    {
        this._value = datetime;
        this._zoneId = zoneId != 0 ? zoneId : DbTime.resolveZoneId(datetime.timezone.name, kind);
        this._kind = kind;
    }

    this(DateTime datetime,
        uint16 zoneId = 0, DbDateTimeKind kind = DbDateTimeKind.local)
    {
        auto convert = SysTime(datetime, timeZone(kind));
        this(convert, zoneId, kind);
    }

    this(Date date,
        uint16 zoneId = 0, DbDateTimeKind kind = DbDateTimeKind.local)
    {
        auto convert = SysTime(date, timeZone(kind));
        this(convert, zoneId, kind);
    }

    this(int32 validYear, int32 validMonth, int32 validDay, int32 hour, int32 minute, int32 second,
        int32 tms = 0, int32 tus = 0,
        uint16 zoneId = 0, DbDateTimeKind kind = DbDateTimeKind.local)
    {
        auto convert = SysTime(toDate(validYear, validMonth, validDay), timeZone(kind));
        if (hour != 0)
            convert += dur!"hours"(hour);
        if (minute != 0)
            convert += dur!"minutes"(minute);
        if (second != 0)
            convert += dur!"seconds"(second);
        if (tms != 0)
            convert += dur!"msecs"(tms);
        if (tus != 0)
            convert += dur!"usecs"(tus);
        this(convert, zoneId, kind);
    }

    // Do not use template function to support Variant
    // Some kind of compiler bug
    bool opEquals(in DbDateTime rhs) const pure
    {
        return zoneId == rhs.zoneId && kind == rhs.kind && _value.opEquals(rhs.value);
    }

    bool opEquals(in SysTime rhs) const
    {
        return this.opEquals(toDbDateTime(rhs));
    }

    bool opEquals(in DateTime rhs) const
    {
        return this.opEquals(DbDateTime(rhs));
    }

    int opCmp(in DbDateTime rhs) const pure
    {
        return _value.opCmp(rhs.value);
    }

    int opCmp(in SysTime rhs) const
    {
        return this.opCmp(toDbDateTime(rhs));
    }

    int opCmp(in DateTime rhs) const
    {
        return this.opCmp(DbDateTime(rhs));
    }

    Date getDate() const
    {
        return cast(Date)_value;
    }

    TimeOfDay getTimeOfDay() const
    {
        return cast(TimeOfDay)_value;
    }

    Duration getTimeOfDayDuration() const
    {
        return timeOfDayToDuration(_value);
    }

    static immutable(TimeZone) timeZone(DbDateTimeKind kind) pure
    {
        return (kind == DbDateTimeKind.utc) ? UTC() : LocalTime();
    }

    static DbDateTime toDbDateTime(in SysTime value)
    {
        const isLocal = value.timezone is LocalTime(); // DbDateTimeKind.utc for UTC() & SimpleTimeZone()
        auto kind = isLocal ? DbDateTimeKind.local : DbDateTimeKind.utc;
        return DbDateTime(value, 0, kind);
    }

    DateTime toDateTime() const
    {
        return cast(DateTime)_value;
    }

    size_t toHash() const pure
    {
        return _value.toHash();
    }

    string toString() const
    {
        import std.array : appender;
        auto writer = appender!string();
        writer.reserve(64);
        return toString(writer).data;
    }

    ref W toString(W)(return ref W writer) const
    if (isOutputRange!(W, char))
    {
        // Date part
        toString(writer, getDate());

        // Time part
        put(writer, ' ');
        return DbTime.toString(writer, _value, zoneId, kind);
    }

    static ref W toString(W)(return ref W writer, scope const Date dt) pure
    if (isOutputRange!(W, char))
    {
        import std.format : formattedWrite;

        scope (failure)
            assert(0);

        if (dt.year >= 0)
        {
            if (dt.year < 10_000)
                formattedWrite(writer, "%04d-%02d-%02d", dt.year, dt.month, dt.day);
            else
                formattedWrite(writer, "+%05d-%02d-%02d", dt.year, dt.month, dt.day);
        }
        else if (dt.year > -10_000)
            formattedWrite(writer, "%05d-%02d-%02d", dt.year, dt.month, dt.day);
        else
            formattedWrite(writer, "%06d-%02d-%02d", dt.year, dt.month, dt.day);

        return writer;
    }

    typeof(this) toUTC() const
    {
        return DbDateTime(_value.toUTC(), timeZoneUtcId, DbDateTimeKind.utc);
    }

    immutable(DbTimeZone) zone() const
    {
        return DbTimeZoneList.instance().zone(zoneId);
    }

public:
    @property bool isTZ() const pure
    {
        return zoneId != 0;
    }

    @property DbDateTimeKind kind() const pure
    {
        return _kind;
    }

    @property SysTime value() const pure
    {
        return _value;
    }

    @property uint16 zoneId() const pure
    {
        return _zoneId;
    }

    alias value this;

private:
    SysTime _value;
    uint16 _zoneId;
    DbDateTimeKind _kind;
}

struct DbHandle
{
nothrow @safe:

public:
    enum notSetValue = -1;

public:
    ref typeof(this) opAssign(size_t rhs) return
    in
    {
        assert(value == notSetValue);
    }
    do
    {
        value = rhs;
        return this;
    }

    bool opCast(C: bool)() const
    {
        return isValid;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbHandle opCast(T)() const
    if (is(Unqual!T == DbHandle))
    {
        return this;
    }

    void reset()
    {
        value = notSetValue;
    }

    @property bool isValid() const
    {
        return value != notSetValue;
    }

public:
    size_t value = notSetValue;
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

struct DbRecordsAffected
{
nothrow @safe:

public:
    enum notSetValue = -1;

public:
    ref typeof(this) opAssign(T)(T rhs) return
    if (is(T == int) || is(T == long) || is(Unqual!T == DbRecordsAffected))
    {
        static if (is(T == int) || is(T == long))
            this.value = rhs;
        else
            this.value = rhs.value;
        return this;
    }

    ref typeof(this) opOpAssign(string op, T)(T rhs) return
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

    bool opCast(C: bool)() const
    {
        return hasCount;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    DbRecordsAffected opCast(T)() const
    if (is(Unqual!T == DbRecordsAffected))
    {
        return this;
    }

    void reset()
    {
        value = notSetValue;
    }

    @property bool hasCount() const
    {
        return value >= 0;
    }

    alias value this;

public:
    long value = notSetValue;
}

struct DbRecordsAffectedAggregate
{
nothrow @safe:

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

    void reset()
    {
        deleteCount.reset();
        insertCount.reset();
        selectCount.reset();
        updateCount.reset();
    }

    @property bool hasCounts() const
    {
        return deleteCount || insertCount || selectCount || updateCount;
    }

public:
	DbRecordsAffected deleteCount;
	DbRecordsAffected insertCount;
	DbRecordsAffected selectCount;
	DbRecordsAffected updateCount;
}

struct DbTime
{
nothrow @safe:

public:
    this(SysTime time, uint16 zoneId, DbDateTimeKind kind)
    {
        this._value = time;
        this._zoneId = zoneId != 0 ? zoneId : resolveZoneId(time.timezone.name, kind);
        this._kind = kind;
    }

    this(scope const Duration timeOfDay, uint16 zoneId = 0, DbDateTimeKind kind = DbDateTimeKind.local)
    {
        auto nullDateTime = kind == DbDateTimeKind.utc ? nullDateTimeTZ : nullDateTimeLocal;
        auto convert = nullDateTime + removeDate(timeOfDay);
        this(convert, zoneId, kind);
    }

    this(scope const TimeOfDay timeOfDay, uint16 zoneId = 0, DbDateTimeKind kind = DbDateTimeKind.local)
    {
        this(timeOfDayToDuration(timeOfDay), zoneId, kind);
    }

    this(int32 h, int32 m, int32 s, int32 ms = 0, int32 us = 0)
    {
        auto convert = nullDateTimeLocal + dur!"seconds"(0); // Use expression to remove immutable
        if (h != 0)
            convert += dur!"hours"(h);
        if (m != 0)
            convert += dur!"minutes"(m);
        if (s != 0)
            convert += dur!"seconds"(s);
        if (ms != 0)
            convert += dur!"msecs"(ms);
        if (us != 0)
            convert += dur!"usecs"(us);
        this(convert, 0, DbDateTimeKind.local);
    }

    // Do not use template function to support Variant
    // Some kind of compiler bug
    bool opEquals(in DbTime rhs) const pure
    {
        return zoneId == rhs.zoneId && kind == rhs.kind && _value.opEquals(rhs.value);
    }

    bool opEquals(in TimeOfDay rhs) const
    {
        return this.opEquals(DbTime(rhs));
    }

    int opCmp(in DbTime rhs) const pure
    {
        return _value.opCmp(rhs.value);
    }

    int opCmp(in TimeOfDay rhs) const
    {
        return this.opCmp(DbTime(rhs));
    }

    static uint16 resolveZoneId(string zoneName, DbDateTimeKind kind)
    {
        auto result = DbTimeZoneList.instance().id(zoneName);
        if (result == 0 && kind == DbDateTimeKind.utc)
            return timeZoneUtcId;
        else
            return result;
    }

    Duration toDuration() const
    {
        return timeOfDayToDuration(_value);
    }

    size_t toHash() const pure
    {
        return _value.toHash();
    }

    TimeOfDay toTimeOfDay() const
    {
        return cast(TimeOfDay)_value;
    }

    int32 toMilliSecond() const
    {
        return cast(int32)(toDuration().total!"msecs");
    }

    string toString() const
    {
        import std.array : appender;
        auto writer = appender!string();
        writer.reserve(64);
        return toString(writer).data;
    }

    ref W toString(W)(return ref W writer) const
    if (isOutputRange!(W, char))
    {
        return toString(writer, _value, zoneId, kind);
    }

    static ref W toString(W)(return ref W writer, scope const SysTime tm, uint16 zoneId, DbDateTimeKind kind)
    if (isOutputRange!(W, char))
    {
        import std.format : formattedWrite;

        scope (failure)
            assert(0);

        auto t = cast(TimeOfDay)tm;
        auto ms = cast(int)(tm.fracSecs().total!"msecs");

        formattedWrite!("%02d:%02d:%02d.%03d")(writer, t.hour, t.minute, t.second, ms);

        if (kind == DbDateTimeKind.utc || zoneId == timeZoneUtcId)
            put(writer, 'Z');
        else if (kind == DbDateTimeKind.local && zoneId != 0)
        {
            auto zn = DbTimeZoneList.instance().zone(zoneId);
            // Valid zone?
            if (zn.id != 0)
            {
                put(writer, ' ');
                put(writer, zn.name);
            }
        }

        return writer;
    }

    typeof(this) toUTC() const
    {
        return DbTime(_value.toUTC(), timeZoneUtcId, DbDateTimeKind.utc);
    }

    immutable(DbTimeZone) zone() const
    {
        return DbTimeZoneList.instance().zone(zoneId);
    }

public:
    @property bool isTZ() const pure
    {
        return zoneId != 0;
    }

    @property DbDateTimeKind kind() const pure
    {
        return _kind;
    }

    @property SysTime value() const pure
    {
        return _value;
    }

    @property uint16 zoneId() const pure
    {
        return _zoneId;
    }

    alias value this;

private:
    SysTime _value;
    uint16 _zoneId;
    DbDateTimeKind _kind;
}

struct DbTypeInfo
{
nothrow @safe:

public:
    string dbName;
    string nativeName;
    int32 displaySize;
    int32 nativeSize;
    int32 nativeId;
    DbType dbType;
}

 /**
  * First element is being used as conversion between bool and its string
  */
immutable string[] dbBoolFalses = ["False", "F", "No", "N", "0"];
immutable string[] dbBoolTrues = ["True", "T", "Yes", "Y", "1"];

immutable string[string] dbDefaultParameterValues;

immutable DbTypeInfo[] dbNativeTypes = [
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
    {dbName:"", nativeName:"char", displaySize:1, nativeSize:1, nativeId:0, dbType:DbType.chars},
    {dbName:"", nativeName:"wchar", displaySize:1, nativeSize:2, nativeId:0, dbType:DbType.chars},
    {dbName:"", nativeName:"dchar", displaySize:1, nativeSize:4, nativeId:0, dbType:DbType.chars},
    {dbName:"", nativeName:"string", displaySize:-1, nativeSize:-1, nativeId:0, dbType:DbType.string},
    {dbName:"", nativeName:"wstring", displaySize:-1, nativeSize:-1, nativeId:0, dbType:DbType.string},
    {dbName:"", nativeName:"dstring", displaySize:-1, nativeSize:-1, nativeId:0, dbType:DbType.string},
    {dbName:"", nativeName:"ubyte[]", displaySize:-1, nativeSize:-1, nativeId:0, dbType:DbType.binary},
    {dbName:"", nativeName:"Date", displaySize:10, nativeSize:Date.sizeof, nativeId:0, dbType:DbType.date},
    {dbName:"", nativeName:"DateTime", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetime},
    {dbName:"", nativeName:"SysTime", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetime},
    {dbName:"", nativeName:"Time", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.time},
    {dbName:"", nativeName:"TimeOfDay", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.time},
    {dbName:"", nativeName:"UUID", displaySize:32, nativeSize:UUID.sizeof, nativeId:0, dbType:DbType.uuid},

    // Library
    {dbName:"", nativeName:"DbDateTime", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetime},
    {dbName:"", nativeName:"DbTime", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.time},
    {dbName:"", nativeName:"Decimal", displaySize:34, nativeSize:Decimal.sizeof, nativeId:0, dbType:DbType.decimal},
    {dbName:"", nativeName:Decimal.stringof, displaySize:34, nativeSize:Decimal.sizeof, nativeId:0, dbType:DbType.decimal},

    // Alias
    {dbName:"", nativeName:"int8", displaySize:4, nativeSize:int8.sizeof, nativeId:0, dbType:DbType.int8},
    {dbName:"", nativeName:"uint8", displaySize:6, nativeSize:int16.sizeof, nativeId:0, dbType:DbType.int16},
    {dbName:"", nativeName:"int16", displaySize:6, nativeSize:int16.sizeof, nativeId:0, dbType:DbType.int16},
    {dbName:"", nativeName:"uint16", displaySize:11, nativeSize:int32.sizeof, nativeId:0, dbType:DbType.int32},
    {dbName:"", nativeName:"int32", displaySize:11, nativeSize:int32.sizeof, nativeId:0, dbType:DbType.int32},
    {dbName:"", nativeName:"uint32", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"int64", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"uint64", displaySize:20, nativeSize:int64.sizeof, nativeId:0, dbType:DbType.int64},
    {dbName:"", nativeName:"float32", displaySize:17, nativeSize:float32.sizeof, nativeId:0, dbType:DbType.float32},
    {dbName:"", nativeName:"float64", displaySize:21, nativeSize:float64.sizeof, nativeId:0, dbType:DbType.float64},
    {dbName:"", nativeName:"DateTimeTZ", displaySize:28, nativeSize:DbDateTime.sizeof, nativeId:0, dbType:DbType.datetimeTZ},
    {dbName:"", nativeName:"TimeTZ", displaySize:11, nativeSize:DbTime.sizeof, nativeId:0, dbType:DbType.timeTZ}
];

immutable DbTypeInfo*[DbType] dbTypeToDbTypeInfos;
immutable DbTypeInfo*[string] nativeNameToDbTypeInfos;

DbType dbArrayOf(DbType elementType) pure
in
{
    assert(elementType != DbType.array);
}
do
{
    return (DbType.array | elementType);
}

DbType dbTypeOf(T)() pure
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

bool isDbTypeHasSize(DbType rawType) pure
{
    switch (rawType)
    {
        case DbType.chars:
        case DbType.string:
        case DbType.text:
        case DbType.json:
        case DbType.xml:
        case DbType.binary:
        case DbType.record:
        case DbType.array:
            return true;
        default:
            return false;
    }
}

bool isDbTypeString(DbType rawType) pure
{
    return rawType == DbType.string
        || rawType == DbType.text
        || rawType == DbType.json
        || rawType == rawType.xml;
}

bool isDbTrue(scope const(char)[] s) pure
{
    if (s.length != 0)
    {
        foreach (e; dbBoolTrues)
        {
            if (sicmp(s, e) == 0)
                return true;
        }
    }

    return false;
}


// Any below codes are private
private:


shared static this()
{
    nullDateTimeLocal = SysTime(nullDate, LocalTime());
    nullDateTimeTZ = SysTime(nullDate, UTC());

    dbDefaultParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbParameterName.charset : "UTF8",
            DbParameterName.compress : dbBoolFalses[0],
            DbParameterName.connectionTimeout : "10", // In seconds
            DbParameterName.encrypt : toName(DbEncryptedConnection.disabled),
            DbParameterName.fetchRecordCount : "200",
            DbParameterName.integratedSecurity : toName(DbIntegratedSecurityConnection.srp),
            DbParameterName.maxPoolCount : "100",
            DbParameterName.minPoolCount : "0",
            DbParameterName.pooling : dbBoolTrues[0],
            DbParameterName.poolTimeout : "30", // In seconds
            DbParameterName.receiveTimeout : "3600", // In seconds - do not add underscore, to!... does not work
            DbParameterName.sendTimeout : "60", // In seconds
            DbParameterName.server : "localhost"
        ];
    }();

    dbTypeToDbTypeInfos = () nothrow pure
    {
        immutable(DbTypeInfo)*[DbType] result;
        foreach (ref e; dbNativeTypes)
        {
            if (!(e.dbType in result))
                result[e.dbType] = &e;
        }
        return result;
    }();

    nativeNameToDbTypeInfos = () nothrow pure
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
    import std.datetime.systime;
    import pham.utl.utltest;
    dgWriteln("unittest db.type.dbTypeOf");

    assert(dbTypeOf!bool() == DbType.boolean);
    assert(dbTypeOf!char() == DbType.chars);
    assert(dbTypeOf!wchar() == DbType.chars);
    assert(dbTypeOf!dchar() == DbType.chars);
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
    assert(dbTypeOf!SysTime() == DbType.datetime);
    assert(dbTypeOf!TimeOfDay() == DbType.time);
    assert(dbTypeOf!DbTime() == DbType.time);
    assert(dbTypeOf!DbDateTime() == DbType.datetime);
    assert(dbTypeOf!(ubyte[])() == DbType.binary);
    assert(dbTypeOf!Decimal() == DbType.decimal);
    assert(dbTypeOf!UUID() == DbType.uuid);

    version (none)
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
