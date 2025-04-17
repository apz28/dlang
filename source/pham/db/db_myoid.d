/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_myoid;

enum myUTF8CharSetId = 33;

struct MyCharSet
{
nothrow @safe:

    string name;
    string collation;
    int id;
}

static immutable MyCharSet[] myCharSet = [
    {name:"utf8", collation:"utf8_general_ci", id:myUTF8CharSetId},
    {name:"utf8mb4", collation:"utf8mb4_0900_ai_ci", id:255}
    ];

/// https://dev.mysql.com/doc/internals/en/capability-flags.html
enum MyCapabilityFlags : uint
{
    longPassword = 1, // New more secure passwords
    foundRows = 2, // Found instead of affected rows
    longFlag = 4, // Get all column flags
    connectWithDb = 8, // One can specify db on connect
    //parameterCountAvailable = 8, // QA should be sent to the server
    noSchema = 16, // Don't allow db.table.column
    compress = 32, // Client can use compression protocol
    odbc = 64, // ODBC client
    localFiles = 128, // Can use LOAD DATA LOCAL
    ignoreSpace = 256, // Ignore spaces before '('
    protocol41 = 512, // Support new 4.1 protocol
    interactive = 1_024, // This is an interactive client
    ssl = 2_048, // Switch to SSL after handshake
    ignoreSigPipe = 4_096, // IGNORE sigpipes
    transactions = 8_192, // Client knows about transactions
    reserved = 16_384, // Old 4.1 protocol flag
    secureConnection = 32_768, // New 4.1 authentication
    multiStatements = 65_536, // Allow multi-stmt support
    multiResults = 131_072, // Allow multiple resultsets
    psMutiResults = 1u << 18, // Allow multi results using PS protocol
    pluginAuth = 1u << 19, // Client supports plugin authentication
    connectAttrs = 1u << 20, // Allows client connection attributes
    canHandleExpiredPassword = 1u << 22, // Support for password expiration > 5.6.6
    sessionTrack = 1u << 23, // Support for sending session tracker vars
    deprecateEof = 1u << 24, // Can send OK after a Text Resultset
    queryAttributes = 1u << 27, // Support for query attributes
    sslVerifyServerCert = 1u << 30, // Verify server certificate
    rememberOptions = 1u << 31, // Don't reset the options after an unsuccessful connect
}

/// DB Operations Code
enum MyCmdId : byte
{
    sleep = 0,
    quit = 1,
    initDb = 2,
    query = 3,
    fieldList = 4,
    createDb = 5,
    dropDb = 6,
    reload = 7,
    shutdown = 8,
    statistics = 9,
    processInfo = 10,
    connect = 11,
    processKill = 12,
    debug_ = 13,
    ping = 14,
    time = 15,
    delayedInsert = 16,
    changeUser = 17,
    binlogDump = 18,
    tableDump = 19,
    connectOut = 20,
    registerReplica = 21,
    prepare = 22,
    execute = 23,
    longData = 24,
    closeStmt = 25,
    resetStmt = 26,
    setOption = 27,
    fetch = 28,
}

enum MyDefaultSize
{
    /**
     * Sizes in bytes
     */
	packetReadBufferLength = 1_024 * 128,
    parameterBufferLength = 1_024 * 96,
    socketReadBufferLength = packetReadBufferLength * 2,
    socketWriteBufferLength = parameterBufferLength + 1_024,    
}

enum MyPackageType : ubyte
{
    ok = 0x00,
    eof = 0xfe,
    error = 0xff,
}

enum MySessionTrackType : byte
{
    systemVariables = 0,
    schema = 1,
    stateChange = 2,
    GTIDS = 3,
    transactionCharacteristics = 4,
    transactionState = 5,
}

enum MyStatusFlags : ushort
{
    inTransaction = 1, // Transaction has started
    autoCommitMode = 2, // Server in auto_commit mode
    moreResults = 4, // More results on server
    anotherQuery = 8, // Multi query - next query exists
    badIndex = 16,
    noIndex = 32,
    cursorExists = 64,
    lastRowSent = 128,
    dbDropped = 256,
    noBackslashEscapes = 512,
    metadataChanged = 1_024,
    wasSlow = 2_048,
    outputParameters = 4_096,
    inTransactionReadOnly = 8_192, // In a read-only transaction
    sessionStateChanged = 16_384, // Connection state information has changed
}

enum myTypeIdExStart = 500;
enum myTypeSignedValue = 0x0;
enum myTypeUnsignedValue = 0x80;

enum MyTypeFlag : ushort
{
    notNull = 1 << 0,
    primaryKey = 1 << 1,
    uniqueKey = 1 << 2,
    multipleKey = 1 << 3,
    blob = 1 << 4,
    unsigned = 1 << 5,
    zeroFill = 1 << 6,
    binary = 1 << 7,
    enum_ = 1 << 8,
    autoIncrement = 1 << 9,
    timestamp = 1 << 10,
    set = 1 << 11,
    number = 1 << 12,
}

/// Specifies MySQL specific data type of a field
enum MyTypeId : ubyte
{
    decimal = 0,
    int8 = 1, // tiny
    int16 = 2, // short
    int32 = 3, // long - A 32-bit signed integer
    float32 = 4, // float
    float64 = 5, // double
    null_ = 6,
    timestamp = 7,
    int64 = 8, // longlong A 64-bit signed integer
    int24 = 9,
    date = 10,
    time = 11,
    datetime = 12,
    year = 13,
    newDate = 14,
    varChar = 15,
    bit = 16,
    json = 245,
    newDecimal = 246,
    enum_ = 247,
    set = 248,
    tinyBlob = 249,
    mediumBlob = 250,
    longBlob = 251,
    varBinary = 252, // blob
    tinyVarChar = 253, // varString
    fixedVarChar = 254, // string
    geometry = 255,
}

/// https://dev.mysql.com/doc/internals/en/com-query-response.html#column-type
enum MyTypeIdEx : ushort
{
    decimal = 0, /// A fixed precision and scale numeric value between -1_038 -1 and 10 38 -1
    int8 = 1, /// The signed range is -128 to 127. The unsigned range is 0 to 255
    int16 = 2, /// A 16-bit signed integer. The signed range is  -32_768 to 32_767. The unsigned range is 0 to 65_535
    int24 = 9, /// Specifies a 24 (3 byte) signed or unsigned value
    int32 = 3, /// A 32-bit signed integer
    int64 = 8, /// A 64-bit signed integer
    float32 = 4,  /// A small (single-precision) floating-point number. Allowable values are -3.402823466E+38 to -1.175494351E-38,
                /// 0, and 1.175494351E-38 to 3.402823466E+38
    float64 = 5, /// A normal-size (double-precision) floating-point number. Allowable values are -1.7976931348623157E+308 to -2.2250738585072014E-308,
                /// 0, and 2.2250738585072014E-308 to 1.7976931348623157E+308
    timestamp = 7, /// A timestamp. The range is '1970-01-01 00:00:00' to sometime in the year 2037
    date = 10, /// Date The supported range is '1000-01-01' to '9999-12-31'
    time = 11, /// Time <para>The range is '-838:59:59' to '838:59:59'
    datetime = 12, /// DateTime The supported range is '1000-01-01 00:00:00' to '9999-12-31 23:59:59'
    year = 13,  /// A year in 2- or 4-digit format (default is 4-digit).
                /// The allowable values are 1901 to 2155, 0000 in the 4-digit year
                /// format, and 1970-2069 if you use the 2-digit format (70-69)
    newDate = 14, /// Obsolete - Use datetime or date type
    varChar = 15, /// A variable-length string containing 0 to 65_535 characters
    bit = 16, /// Bit-field data type - 8 bytes
    json = 245, /// JSON
    newDecimal = 246, /// New Decimal
    enum_ = 247, /// An enumeration. A string object that can have only one value,
                 /// chosen from the list of values 'value1', 'value2', ..., NULL
                 /// or the special "" error value. An ENUM can have a maximum of  65_535 distinct values
    set = 248,  /// A set. A string object that can have zero or more values, each
                /// of which must be chosen from the list of values 'value1', 'value2',
                /// ... A SET can have a maximum of 64 members.
    tinyBlob = 249, /// A binary column with a maximum length of 255 (2^8 - 1) bytes
    mediumBlob = 250, /// A binary column with a maximum length of 16_777_215 (2^24 - 1) bytes
    longBlob = 251, /// A binary column with a maximum length of 4_294_967_295 or 4G (2^32 - 1) bytes
    varBinary = 252, /// A binary column with a maximum length of 65_535 (2^16 - 1) bytes
    tinyVarChar = 253, /// A variable-length binary containing 0 to 255 bytes
    fixedVarChar = 254, /// A fixed-length string
    geometry = 255, /// Geometric (GIS) data type

    // Calculated based on id & flags - substract 500 to get real value
    uint8 = myTypeIdExStart + int8, /// Unsigned 8-bit value
    uint16 = myTypeIdExStart + int16, /// Unsigned 16-bit value
    uint24 = myTypeIdExStart + int24, /// Unsigned 24-bit value
    uint32 = myTypeIdExStart + int32, /// Unsigned 32-bit value
    uint64 = myTypeIdExStart + int64, /// Unsigned 64-bit value
    tinyText = myTypeIdExStart + tinyBlob, /// A text column with a maximum length of 255 (2^8 - 1) characters
    mediumText = myTypeIdExStart + mediumBlob, /// A text column with a maximum length of 16_777_215 (2^24 - 1) characters
    longText = myTypeIdExStart + longBlob, /// A text column with a maximum length of 4_294_967_295 or 4G (2^32 - 1) characters
    tinyVarBinary = myTypeIdExStart + tinyVarChar, /// Variable length binary string
    binaryFixed = myTypeIdExStart + fixedVarChar, /// Fixed length binary
    uuid = 854, /// A guid column
}

enum MyPackedIntegerIndicator : ubyte
{
    negOne = 251u,
    twoByte = 252u,
    threeByte = 253u,
    fourOrEightByte = 254u,
}

enum MyPackedIntegerLimit : uint
{
    oneByte = 251u,
    twoByte = 65_536u,
    threeByte = 16_777_216u,
}
