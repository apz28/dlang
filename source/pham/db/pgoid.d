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

module pham.db.pgoid;

enum PgId : int
{
    protocolVersion = 0x0003_0000, // version number 3
    undefined = 0,

    /*
    typeCatalog = 71,
    attributeCatalog = 75,
    procCatalog = 81,
    classCatalog = 83,

    nodeTree = 194,
    storageManager = 210,

    absTime = 702,
    relTime = 703,
    interval = 704,

    absTimeArray = 1023,
    relTimeArray = 1024,
    intervalArray = 1025,
    accessControlList = 1033,
    accessControlListArray = 1034,

    cstringArray = 1263,

    cstring = 2275,
    anyVoid = 2276,
    anyArray = 2277,
    trigger = 2279,
    languageHandler = 2280,
    internal = 2281,
    opaque = 2282,
    anyElement = 2283,
    anyNoArray = 2776,

    txidSnapshotArray = 2949,
    txidSnapshot = 2970,

    fdwHandler = 3115,
    anyEnum = 3500,

    tsVector = 3614,
    tsQuery = 3615,
    gtsVector = 3642,
    tsVectorArray = 3643,
    gtsVectorArray = 3644,
    tsQueryArray = 3645,
    regConfig = 3734,
    regConfigArray = 3735,
    regDictionary = 3769,
    regDictionaryArray = 3770,

    anyRange = 3831,
    eventTrigger = 3838,
    */
}

enum PgDiag : char
{
    columnName = 'c',
    constraintName = 'n',
    context = 'W',
    dataTypeName = 'd',
    internalPosition = 'p',
    internalQuery = 'q',
    messageDetail = 'D',
    messageHint = 'H',
    messagePrimary = 'M',
    schemaName = 's',
    severity = 'S',
    severityNonlocalized = 'V', // New in 9.6
    sourceFile = 'F',
    sourceFunction = 'R',
    sourceLine = 'L',
    sqlState = 'C',
    statementPosition = 'P',
    tableName = 't',
}

enum PgDescribeType : char
{
    bindStatement = 'B',
    close = 'C',
    describeStatement = 'D',
    disconnect = 'X',
    executeStatement = 'E',
    flush = 'H',
    parseStatement = 'P',
    portal = 'P',
    statement = 'S',
    sync = 'S',
}

enum PgIdentifier
{
    serverProcessId = "serverProcessId",
    serverSecretKey = "serverSecretKey",
    serverTrStatus = "serverTrStatus",
}

enum PgOIdType : int
{
    bool_ = 16,
    bytea = 17, // blob
    char_ = 18, // 1 byte char
    name = 19,
    int8 = 20,
    int2 = 21,
    int4 = 23,
    regproc = 24,
    text = 25,
    oid = 26, // 4 bytes unsign
    tid = 27,
    xid = 28,
    cid = 29,
    xml = 142,
    point = 600,
    lseg = 601,
    path = 602,
    box = 603,
    polygon = 604,
    line = 628,
    cidr = 650,
    float4 = 700,
    float8 = 701,
    unknown = 705,
    circle = 718,
    money = 790,
    macaddr = 829,
    inet = 869,
    bpchar = 1042, // fixed size char[n]
    varchar = 1043,
    date = 1082,
    time = 1083,
    timestamp = 1114,
    timestamptz = 1184,
    interval = 1186,
    timetz = 1266,
    bit = 1560,
    varbit = 1562,
    numeric = 1700,
    refcursor = 1790,
    record = 2249,
    void_ = 2278,
    array_record = 2287,
    regprocedure = 2202,
    regoper = 2203,
    regoperator = 2204,
    regclass = 2205,
    regtype = 2206,
    uuid = 2950,
    json = 114,
    jsonb = 3802,
    int2vector = 22,
    oidvector = 30,
    array_xml = 143,
    array_json = 199,
    array_line = 629,
    array_cidr = 651,
    array_circle = 719,
    array_money = 791,
    array_bool = 1000,
    array_bytea = 1001,
    array_char = 1002,
    array_name = 1003,
    array_int2 = 1005,
    array_int2vector = 1006,
    array_int4 = 1007,
    array_regproc = 1008,
    array_text = 1009,
    array_tid = 1010,
    array_xid = 1011,
    array_cid = 1012,
    array_oidvector = 1013,
    array_bpchar = 1014,
    array_varchar = 1015,
    array_int8 = 1016,
    array_point = 1017,
    array_lseg = 1018,
    array_path = 1019,
    array_box = 1020,
    array_float4 = 1021,
    array_float8 = 1022,
    array_polygon = 1027,
    array_oid = 1028,
    array_macaddr = 1040,
    array_inet = 1041,
    array_timestamp = 1115,
    array_date = 1182,
    array_time = 1183,
    array_timestamptz = 1185,
    array_interval = 1187,
    array_numeric = 1231,
    array_timetz = 1270,
    array_bit = 1561,
    array_varbit = 1563,
    array_refcursor = 2201,
    array_regprocedure = 2207,
    array_regoper = 2208,
    array_regoperator = 2209,
    array_regclass = 2210,
    array_regtype = 2211,
    array_uuid = 2951,
    array_jsonb = 3807,
    int4range = 3904,
    int4range_ = 3905,
    numrange = 3906,
    numrange_ = 3907,
    tsrange = 3908,
    tsrange_ = 3909,
    tstzrange = 3910,
    tstzrange_ = 3911,
    daterange = 3912,
    daterange_ = 3913,
    int8range = 3926,
    int8range_ = 3927,
}
