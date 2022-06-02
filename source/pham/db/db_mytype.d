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

module pham.db.mytype;

version (TraceFunction) import pham.utl.test;
import pham.utl.bit_array : Map32Bit;
import pham.utl.enum_set : toName;
import pham.utl.utf8 : ShortStringBuffer;
import pham.db.message;
import pham.db.type;
import pham.db.myoid;

nothrow @safe:

alias MyCommandId = int32;

static immutable string myAuthDefault = myAuthNativeName;
static immutable string myAuthNativeName = "mysql_native_password";
static immutable string myAuthScramSha1Name = "SCRAM-SHA-1";
static immutable string myAuthScramSha256Name = "SCRAM-SHA-256";
static immutable string myAuthSha256Mem = "SHA256_MEMORY";
static immutable string myAuthSha2Caching = "caching_sha2_password";
static immutable string myAuthSSPIName = "authentication_windows_client";

static immutable string[] myCiphers = [
    // Blocked
    "!aNULL",
    "!eNULL",
    "!EXPORT",
    "!LOW",
    "!MD5",
    "!DES",
    "!RC2",
    "!RC4",
    "!PSK",
    "!DES-CBC3-SHA",
    "!DHE-DSS-DES-CBC3-SHA",
    "!DHE-RSA-DES-CBC3-SHA",
    "!ECDH-RSA-DES-CBC3-SHA",
    "!ECDH-ECDSA-DES-CBC3-SHA",
    "!ECDHE-RSA-DES-CBC3-SHA",
    "!ECDHE-ECDSA-DES-CBC3-SHA",
    "!DH-RSA-DES-CBC3-SHA",
    "!DH-DSS-DES-CBC3-SHA",
    // Mandatory
    "ECDHE-ECDSA-AES128-GCM-SHA256",
    "ECDHE-ECDSA-AES256-GCM-SHA384",
    "ECDHE-RSA-AES128-GCM-SHA256",
    "ECDHE-ECDSA-AES128-SHA256",
    "ECDHE-RSA-AES128-SHA256",
    // Optional 1
    "ECDHE-RSA-AES256-GCM-SHA384",
    "ECDHE-ECDSA-AES256-SHA384",
    "ECDHE-RSA-AES256-SHA384",
    "DHE-RSA-AES128-GCM-SHA256",
    "DHE-DSS-AES128-GCM-SHA256",
    "DHE-RSA-AES128-SHA256",
    "DHE-DSS-AES128-SHA256",
    "DHE-DSS-AES256-GCM-SHA384",
    "DHE-RSA-AES256-SHA256",
    "DHE-DSS-AES256-SHA256",
    "DHE-RSA-AES256-GCM-SHA384",
    // Optional 2
    "DH-DSS-AES128-GCM-SHA256",
    "ECDH-ECDSA-AES128-GCM-SHA256",
    "DH-DSS-AES256-GCM-SHA384",
    "ECDH-ECDSA-AES256-GCM-SHA384",
    "DH-DSS-AES128-SHA256",
    "ECDH-ECDSA-AES128-SHA256",
    "DH-DSS-AES256-SHA256",
    "ECDH-ECDSA-AES256-SHA384",
    "DH-RSA-AES128-GCM-SHA256",
    "ECDH-RSA-AES128-GCM-SHA256",
    "DH-RSA-AES256-GCM-SHA384",
    "ECDH-RSA-AES256-GCM-SHA384",
    "DH-RSA-AES128-SHA256",
    "ECDH-RSA-AES128-SHA256",
    "DH-RSA-AES256-SHA256",
    "ECDH-RSA-AES256-SHA384",
    // Optional 3
    "ECDHE-RSA-AES128-SHA",
    "ECDHE-ECDSA-AES128-SHA",
    "ECDHE-RSA-AES256-SHA",
    "ECDHE-ECDSA-AES256-SHA",
    "DHE-DSS-AES128-SHA",
    "DHE-RSA-AES128-SHA",
    "DHE-DSS-AES256-SHA",
    "DHE-RSA-AES256-SHA",
    "DH-DSS-AES128-SHA",
    "ECDH-ECDSA-AES128-SHA",
    "AES256-SHA",
    "DH-DSS-AES256-SHA",
    "ECDH-ECDSA-AES256-SHA",
    "DH-RSA-AES128-SHA",
    "ECDH-RSA-AES128-SHA",
    "DH-RSA-AES256-SHA",
    "ECDH-RSA-AES256-SHA",
    "CAMELLIA256-SHA",
    "CAMELLIA128-SHA",
    "AES128-GCM-SHA256",
    "AES256-GCM-SHA384",
    "AES128-SHA256",
    "AES256-SHA256",
    "AES128-SHA",
    ];

static immutable ubyte[] myDH2048_p = [
    0x8A, 0x5D, 0xFA, 0xC0, 0x66, 0x76, 0x4E, 0x61, 0xFA, 0xCA, 0xC0, 0x37,
    0x57, 0x5C, 0x6D, 0x3F, 0x83, 0x0A, 0xA1, 0xF5, 0xF1, 0xE6, 0x7F, 0x3C,
    0xC6, 0xAF, 0xDA, 0x8B, 0x26, 0xE6, 0x1A, 0x74, 0x5E, 0x64, 0xCB, 0xE2,
    0x08, 0xF1, 0x09, 0xE3, 0xAF, 0xBB, 0x54, 0x29, 0x2D, 0x97, 0xF4, 0x59,
    0xE6, 0x26, 0x83, 0x1F, 0x55, 0xCD, 0x1B, 0x57, 0x55, 0x42, 0x6C, 0xE7,
    0xB7, 0xDA, 0x6E, 0xD8, 0x6D, 0xEE, 0xB1, 0x4F, 0xA4, 0xD7, 0xF5, 0x41,
    0xE1, 0xB4, 0x0B, 0xE1, 0x98, 0x16, 0xE2, 0xED, 0x16, 0xCF, 0x18, 0x7D,
    0x3F, 0x25, 0xC3, 0x82, 0x59, 0xBD, 0xF4, 0x8F, 0x57, 0xCA, 0x3E, 0x19,
    0xE4, 0xF5, 0x44, 0xE0, 0xCC, 0x80, 0xB3, 0x10, 0x91, 0x18, 0x0D, 0x64,
    0x59, 0x0A, 0x43, 0xF7, 0xFC, 0xCA, 0x01, 0xE8, 0x14, 0x04, 0xF2, 0xCD,
    0xA9, 0x2A, 0x3C, 0xF3, 0xA5, 0x2A, 0x83, 0xD8, 0x66, 0x9F, 0xC9, 0x2C,
    0xC9, 0x4F, 0x44, 0x05, 0x5E, 0x5E, 0x00, 0x47, 0x22, 0x0A, 0xE6, 0xB0,
    0x87, 0xA5, 0x74, 0x3B, 0xE4, 0xA3, 0xFC, 0x2D, 0xDC, 0x49, 0xF2, 0xE1,
    0x80, 0x0D, 0x06, 0x71, 0x7A, 0x77, 0x3A, 0xA9, 0x66, 0x70, 0x3B, 0xBA,
    0x8D, 0x2E, 0x60, 0x5A, 0x39, 0xF7, 0x2D, 0xD3, 0xF5, 0x53, 0x47, 0x6E,
    0x57, 0x13, 0x01, 0x87, 0xF9, 0xDE, 0x4D, 0x20, 0x92, 0xBE, 0xD7, 0x1E,
    0xE0, 0x20, 0x0C, 0x60, 0xC8, 0xCA, 0x35, 0x58, 0x7D, 0x3F, 0x59, 0xEE,
    0xFB, 0x67, 0x7D, 0x64, 0x7D, 0x8E, 0x77, 0x6C, 0x61, 0x44, 0x8A, 0x8C,
    0x4D, 0xF0, 0x12, 0xD4, 0xA4, 0xEA, 0x17, 0x75, 0x66, 0x49, 0x6C, 0xCF,
    0x14, 0x28, 0xC6, 0x9A, 0x3C, 0x71, 0xFD, 0xB8, 0x3A, 0x6C, 0xE3, 0xA3,
    0xA6, 0x06, 0x5A, 0xA6, 0xF0, 0x7A, 0x00, 0x15, 0xA5, 0x5A, 0x64, 0x66,
    0x00, 0x05, 0x85, 0xB7,
    ];

static immutable ubyte[] myDH2048_g = [
    0x05,
    ];

static immutable string[string] myDefaultConnectionParameterValues;

static immutable string[] myValidConnectionParameterNames = [
    // Primary
    DbConnectionParameterIdentifier.server,
    DbConnectionParameterIdentifier.port,
    DbConnectionParameterIdentifier.database,
    DbConnectionParameterIdentifier.userName,
    DbConnectionParameterIdentifier.userPassword,
    DbConnectionParameterIdentifier.allowBatch,
    DbConnectionParameterIdentifier.charset,
    DbConnectionParameterIdentifier.compress,
    DbConnectionParameterIdentifier.encrypt,

    // Other
    DbConnectionParameterIdentifier.commandTimeout,
    DbConnectionParameterIdentifier.connectionTimeout,
    DbConnectionParameterIdentifier.pooling,
    DbConnectionParameterIdentifier.receiveTimeout,
    DbConnectionParameterIdentifier.sendTimeout,
    DbConnectionParameterIdentifier.socketBlocking,

    // MySQL
    DbConnectionParameterIdentifier.myAllowUserVariables,
    ];

static immutable DbTypeInfo[] myNativeTypes = [
    {dbName:"DECIMAL", nativeName:"decimal", displaySize:34, nativeSize:Decimal.sizeof, nativeId:MyTypeId.decimal, dbType:DbType.decimal},
    {dbName:"BYTE", nativeName:"tinyint", displaySize:4, nativeSize:1, nativeId:MyTypeId.int8, dbType:DbType.int8},
    {dbName:"SMALLINT", nativeName:"smallint", displaySize:6, nativeSize:2, nativeId:MyTypeId.int16, dbType:DbType.int16},
    {dbName:"INTEGER", nativeName:"int", displaySize:11, nativeSize:4, nativeId:MyTypeId.int32, dbType:DbType.int32},
    {dbName:"INTEGER", nativeName:"int24", displaySize:11, nativeSize:4, nativeId:MyTypeId.int24, dbType:DbType.int32},
    {dbName:"BIGINT", nativeName:"bigint", displaySize:20, nativeSize:8, nativeId:MyTypeId.int64, dbType:DbType.int64},
    {dbName:"FLOAT", nativeName:"float", displaySize:17, nativeSize:4, nativeId:MyTypeId.float32, dbType:DbType.float32},
    {dbName:"DOUBLE", nativeName:"double", displaySize:17, nativeSize:8, nativeId:MyTypeId.float64, dbType:DbType.float64},
    {dbName:"TIMESTAMP", nativeName:"timestamp", displaySize:22, nativeSize:8, nativeId:MyTypeId.timestamp, dbType:DbType.datetime},
    {dbName:"DATE", nativeName:"date", displaySize:10, nativeSize:4, nativeId:MyTypeId.date, dbType:DbType.date},
    {dbName:"TIME", nativeName:"time", displaySize:11, nativeSize:8, nativeId:MyTypeId.time, dbType:DbType.time},
    {dbName:"DATETIME", nativeName:"datetime", displaySize:22, nativeSize:8, nativeId:MyTypeId.datetime, dbType:DbType.datetime},
    {dbName:"YEAR", nativeName:"year", displaySize:4, nativeSize:2, nativeId:MyTypeId.year, dbType:DbType.int16},
    {dbName:"DATETIME", nativeName:"newdate", displaySize:22, nativeSize:8, nativeId:MyTypeId.newDate, dbType:DbType.datetime},
    {dbName:"VARCHAR(?)", nativeName:"varchar(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:MyTypeId.varChar, dbType:DbType.string},
    {dbName:"BIT", nativeName:"bit", displaySize:dynamicTypeSize, nativeSize:8, nativeId:MyTypeId.bit, dbType:DbType.int64},
    {dbName:"JSON", nativeName:"json", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeId.json, dbType:DbType.json},
    {dbName:"DECIMAL", nativeName:"decimal", displaySize:34, nativeSize:Decimal.sizeof, nativeId:MyTypeId.newDecimal, dbType:DbType.decimal},
    {dbName:"ENUM", nativeName:"enum", displaySize:dynamicTypeSize, nativeSize:2, nativeId:MyTypeId.enum_, dbType:DbType.int16},
    {dbName:"SET", nativeName:"set", displaySize:dynamicTypeSize, nativeSize:8, nativeId:MyTypeId.set, dbType:DbType.int64},
    {dbName:"TINYBLOB,", nativeName:"tinyblob", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeId.tinyBlob, dbType:DbType.binary},
    {dbName:"MEDIUMBLOB", nativeName:"mediumblob", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeId.mediumBlob, dbType:DbType.binary},
    {dbName:"BLOB", nativeName:"longblob", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeId.longBlob, dbType:DbType.binary},
    {dbName:"VARBINARY(?)", nativeName:"varbinary(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:MyTypeId.varBinary, dbType:DbType.binary},
    {dbName:"VARCHAR(?)", nativeName:"tinyvarchar(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:MyTypeId.tinyVarChar, dbType:DbType.string},
    {dbName:"CHAR(?)", nativeName:"char(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:MyTypeId.fixedVarChar, dbType:DbType.fixedString},
    {dbName:"GEOMETRY", nativeName:"geometry", displaySize:dynamicTypeSize, nativeSize:runtimeTypeSize, nativeId:MyTypeId.geometry, dbType:DbType.record},

    // Extra for dbType name
    //{dbName:"BOOLEAN", nativeName:"TINYINT", displaySize:5, nativeSize:1, nativeId:MyTypeIdEx.boolean, dbType:DbType.boolean},
    {dbName:"BINARY(?)", nativeName:"binary(?)", displaySize:runtimeTypeSize, nativeSize:runtimeTypeSize, nativeId:MyTypeIdEx.fixedBinary, dbType:DbType.binary},
    {dbName:"TINYTEXT", nativeName:"tinytext", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeIdEx.tinyText, dbType:DbType.text},
    {dbName:"MEDIUMTEXT", nativeName:"mediumtext", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeIdEx.mediumText, dbType:DbType.text},
    {dbName:"TEXT", nativeName:"longtext", displaySize:dynamicTypeSize, nativeSize:dynamicTypeSize, nativeId:MyTypeIdEx.longText, dbType:DbType.text},
    {dbName:"UUID", nativeName:"char(36)", displaySize:32, nativeSize:36, nativeId:MyTypeIdEx.uuid, dbType:DbType.uuid},
    //{dbName:"", nativeName:"", displaySize:-1, nativeSize:-1, nativeId:MyTypeIdEx., dbType:DbType.},
    ];

static immutable DbType[string] mySimpleTypes;

static immutable DbTypeInfo*[int32] myOIdTypeToDbTypeInfos;

alias MyBlockHeader = Map32Bit;

struct MyCommandPreparedResponse
{
nothrow @safe:

    MyFieldInfo[] fields;
    MyFieldInfo[] parameters;
    MyCommandId id;
    int16 fieldCount;
    int16 parameterCount;
}

struct MyCommandResultResponse
{
nothrow @safe:

    MyFieldInfo[] fields;
    MyOkResponse okResponse;
    int32 fieldCount;
}

struct MyEOFResponse
{
nothrow @safe:

    int16 warningCount;
    MyStatusFlags statusFlags;
}

struct MyErrorResult
{
@safe:

    string message;
    string sqlState;
    int code;
}

struct MyFieldInfo
{
nothrow @safe:

public:
    DbType calculateDbType() const @nogc pure
    {
        DbType result = DbType.unknown;
        if (auto e = typeId in myOIdTypeToDbTypeInfos)
        {
            result = (*e).dbType;
            if (result == DbType.decimal || result == DbType.numeric)
                result = decimalDbType(result, precision);
            else if ((result == DbType.binary || typeId == MyTypeId.enum_ || typeId == MyTypeId.set) && isText)
                result = DbType.text;
        }
        return result;
    }

    void calculateOtherInfo(const ref MyFieldTypeMap fieldTypeMaps) pure
    {
        if (typeId == MyTypeId.decimal || typeId == MyTypeId.newDecimal)
        {
            precision = isUnsigned ? columnLength : columnLength - 1;
            if (scale != 0)
                precision--;
        }

        version (none) //We do not support unsigned
        if (isUnsigned)
        {
            switch (typeId) with (MyTypeId)
            {
                case byte_:
                    typeId = ubyte_;
                    return;
                case int16:
                    typeId = uint16;
                    return;
                case int24:
                    typeId = uint24;
                    return;
                case int32:
                    typeId = uint32;
                    return;
                case int64:
                    typeId = uint64;
                    return;
                default:
                    break;
            }
        }

        if (typeId == MyTypeId.json && isBlob)
        {
            characterSetIndex = -1;
            characterSetLength = 4;
        }

        const kind = fieldTypeMaps.get(useName);
        if (kind != MyFieldTypeMapKind.unknown)
        {
            final switch (kind) with (MyFieldTypeMapKind)
            {
                case unknown:
                    assert(0);
                case boolean:
                    _dbType = DbType.boolean;
                    break;
                case tinyText:
                case mediumText:
                case longText:
                    _dbType = DbType.text;
                    break;
                case uuid:
                    _dbType = DbType.uuid;
                    break;
            }
        }
        else
        {
            _dbType = calculateDbType();
        }
    }

    DbType dbType() const @nogc pure
    {
        return _dbType != DbType.unknown ? _dbType : calculateDbType();
    }

    int32 dbTypeSize() const @nogc pure
    {
        if (auto e = dbType() in dbTypeToDbTypeInfos)
        {
            const ns = (*e).nativeSize;
            return ns > 0 ? ns : columnLength;
        }
        return dynamicTypeSize;
    }

    static DbType decimalDbType(const(DbType) decimalType, const(int32) precision) @nogc pure
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

    version (TraceFunction)
    string traceString() const nothrow @trusted
    {
        import std.conv : to;

        return "columnName=" ~ columnName
            ~ ", originalColumnName=" ~ originalColumnName
            ~ ", tableName=" ~ tableName
            ~ ", realTableName=" ~ realTableName
            ~ ", catalogName=" ~ catalogName
            ~ ", databaseName=" ~ databaseName
            ~ ", columnLength=" ~ columnLength.to!string()
            ~ ", precision=" ~ precision.to!string()
            ~ ", scale=" ~ scale.to!string()
            ~ ", dbType=" ~ toName!DbType(dbType())
            ~ ", characterSetIndex=" ~ characterSetIndex.to!string()
            ~ ", typeFlags=" ~ typeFlags.dgToHex()
            ~ ", typeId=" ~ typeId.to!string()
            ~ ", isBlob=" ~ isBlob.to!string()
            ~ ", isText=" ~ isText.to!string();
    }

    static DbFieldIdType isValueIdType(int32 mIdType, int32 mIdSubType) @nogc pure
    {
        return DbFieldIdType.no;
    }

    pragma(inline, true)
    string useName() const pure
    {
        return columnName.length != 0 ? columnName : originalColumnName;
    }

    pragma(inline, true)
    string useTableName() const pure
    {
        return tableName.length != 0 ? tableName : realTableName;
    }

    pragma(inline, true)
    @property bool allowNull() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.notNull) == 0;
    }

    @property int characterLength() const @nogc pure
    {
        return columnLength / characterSetLength;
    }

    @property bool isAlias() const @nogc pure
    {
        return originalColumnName.length != 0
            && columnName.length != 0
            && originalColumnName != columnName;
    }

    @property bool isAutoIncrement() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.autoIncrement) != 0;
    }

    @property bool isNumeric() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.number) != 0;
    }

    @property bool isUnique() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.uniqueKey) != 0;
    }

    @property bool isPrimaryKey() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.primaryKey) != 0;
    }

    @property bool isBlob() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.blob) != 0
            && ((typeFlags & MyTypeFlag.binary) != 0 || characterSetIndex == 63);
    }

    @property bool isText() const @nogc pure
    {
        return (typeFlags & (MyTypeFlag.blob | MyTypeFlag.binary)) != 0
            && (characterSetIndex == 33);
    }

    @property bool isUnsigned() const @nogc pure
    {
        return (typeFlags & MyTypeFlag.unsigned) != 0;
    }

public:
    string catalogName;
    string columnName;
    string databaseName;
    string originalColumnName;
    string realTableName;
    string tableName;
    DbType _dbType = DbType.unknown;
    int32 columnLength;
    int32 precision;
    int16 characterSetIndex;
    uint16 typeFlags;
    uint8 typeId;
    int8 characterSetLength = 4; // Our default charset is UTF-8
    int8 scale;
}

struct MyOkResponse
{
nothrow @safe:

    MySessionTrackerInfo[] sessionTrackers;
    string info;
    int64 affectedRows = -1;
    int64 lastInsertId = -1;
    int16 warningCount;
    MyStatusFlags statusFlags;

    ref typeof(this) addTracker(MySessionTrackType trackType, string name, string value) return
    {
        sessionTrackers ~= MySessionTrackerInfo(name, value, trackType);
        return this;
    }
}

struct MySessionTrackerInfo
{
nothrow @safe:

    string name;
    string value;
    MySessionTrackType trackType;
}

enum MyFieldTypeMapKind : ubyte
{
    unknown,
    boolean,
    tinyText,
    mediumText,
    longText,
    uuid,
}

struct MyFieldTypeMap
{
nothrow @safe:

public:
    MyFieldTypeMapKind get(string fieldName) const @nogc pure
    {
        if (auto e = fieldName in fieldNames)
            return *e;
        else
            return MyFieldTypeMapKind.unknown;
    }

    void set(string fieldName, MyFieldTypeMapKind kind) pure
    {
        fieldNames[fieldName] = kind;
    }

public:
    MyFieldTypeMapKind[string] fieldNames;
}

struct MyGeometry
{
nothrow @safe:

public:
    DbGeoPoint point;
    int32 srid;
}

DbType myParameterTypeToDbType(scope const(char)[] myTypeName, const(int32) precision) pure
{
    if (auto e = myTypeName in mySimpleTypes)
    {
        DbType result = *e;
        return result != DbType.decimal
            ? result
            : MyFieldInfo.decimalDbType(result, precision);
    }
    else
        return DbType.unknown;
}


// Any below codes are private
private:

shared static this() nothrow
{
    myDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbConnectionParameterIdentifier.port : "3306", // x_protocol=33060
            DbConnectionParameterIdentifier.userName : "root",
            DbConnectionParameterIdentifier.integratedSecurity : toName(DbIntegratedSecurityConnection.legacy),
            DbConnectionParameterIdentifier.allowBatch : dbBoolTrue,
            DbConnectionParameterIdentifier.myAllowUserVariables : dbBoolTrue,
        ];
    }();

    myOIdTypeToDbTypeInfos = () nothrow pure
    {
        immutable(DbTypeInfo)*[int32] result;
        foreach (ref e; myNativeTypes)
        {
            result[e.nativeId] = &e;
        }
        return result;
    }();

    mySimpleTypes = () nothrow pure
    {
        DbType[string] result;
        result["tinyint"] = DbType.int8;
        result["mediumint"] = DbType.int16;
        result["int"] = DbType.int32;
        result["bigint"] = DbType.int64;
        result["decimal"] = DbType.decimal;
        result["float"] = DbType.float32;
        result["double"] = DbType.float64;
        result["bit"] = DbType.int64;
        result["char"] = DbType.fixedString;
        result["varchar"] = DbType.string;
        result["binary"] = DbType.fixedBinary;
        result["varbinary"] = DbType.binary;
        result["blob"] = DbType.binary;
        result["tinyblob"] = DbType.binary;
        result["mediumblob"] = DbType.binary;
        result["longblob"] = DbType.binary;
        result["text"] = DbType.text;
        result["tinytext"] = DbType.text;
        result["mediumtext"] = DbType.text;
        result["longtext"] = DbType.text;
        //result["enum"] = DbType.int32;
        //result["set"] = DbType.;
        result["date"] = DbType.date;
        result["time"] = DbType.time;
        result["datetime"] = DbType.datetime;
        result["timestamp"] = DbType.datetime;
        result["year"] = DbType.int32;
        //result["geometry"] = DbType.;
        //result["point"] = DbType.;
        //result["linestring"] = DbType.;
        //result["polygon"] = DbType.;
        //result["geometrycollection"] = DbType.;
        //result["multilinestring"] = DbType.;
        //result["multipoint"] = DbType.;
        //result["multipolygon"] = DbType.;
        result["json"] = DbType.json;
        //result[""] = DbType.;
        return result;
    }();
}
