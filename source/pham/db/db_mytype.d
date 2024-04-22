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

module pham.db.db_mytype;

debug(debug_pham_db_db_mytype) import std.stdio : writeln;

import pham.utl.utl_array : ShortStringBuffer;
import pham.utl.utl_bit : Map32Bit;
import pham.utl.utl_enum_set : toName;
import pham.db.db_message;
import pham.db.db_type;
import pham.db.db_myoid;

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

static immutable DbConnectionParameterInfo[string] myDefaultConnectionParameterValues;

static immutable string[] myValidConnectionParameterNames = [
    // Primary
    DbConnectionParameterIdentifier.serverName,
    DbConnectionParameterIdentifier.serverPort,
    DbConnectionParameterIdentifier.databaseName,
    DbConnectionParameterIdentifier.userName,
    DbConnectionParameterIdentifier.userPassword,
    DbConnectionParameterIdentifier.roleName,
    DbConnectionParameterIdentifier.allowBatch,
    DbConnectionParameterIdentifier.charset,
    DbConnectionParameterIdentifier.compress,
    DbConnectionParameterIdentifier.encrypt,
    DbConnectionParameterIdentifier.integratedSecurity,

    // Other
    DbConnectionParameterIdentifier.commandTimeout,
    DbConnectionParameterIdentifier.connectionTimeout,
    DbConnectionParameterIdentifier.fetchRecordCount,
    DbConnectionParameterIdentifier.packageSize,
    DbConnectionParameterIdentifier.pooling,
    DbConnectionParameterIdentifier.receiveTimeout,
    DbConnectionParameterIdentifier.sendTimeout,
    DbConnectionParameterIdentifier.socketBlocking,

    // MySQL
    DbConnectionParameterIdentifier.myAllowUserVariables,
    ];

static immutable DbTypeInfo[] myNativeTypes = [
    {dbName:"bigint", dbType:DbType.int64, dbId:MyTypeId.int64, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"binary(?)", dbType:DbType.binaryFixed, dbId:MyTypeIdEx.binaryFixed, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryFixed, displaySize:DbTypeDisplaySize.binaryFixed},
    {dbName:"bit", dbType:DbType.int64, dbId:MyTypeId.bit, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"char(32)", dbType:DbType.uuid, dbId:MyTypeIdEx.uuid, nativeName:"UUID", nativeSize:DbTypeSize.uuid, displaySize:DbTypeDisplaySize.uuid},
    {dbName:"char(?)", dbType:DbType.stringFixed, dbId:MyTypeId.fixedVarChar, nativeName:"string", nativeSize:DbTypeSize.stringFixed, displaySize:DbTypeDisplaySize.stringFixed},
    {dbName:"longblob", dbType:DbType.binaryVary, dbId:MyTypeId.longBlob, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"float", dbType:DbType.float32, dbId:MyTypeId.float32, nativeName:"float32", nativeSize:DbTypeSize.float32, displaySize:DbTypeDisplaySize.float32},
    {dbName:"date", dbType:DbType.date, dbId:MyTypeId.date, nativeName:"DbDate", nativeSize:DbTypeSize.date, displaySize:DbTypeDisplaySize.date},
    {dbName:"newdate", dbType:DbType.datetime, dbId:MyTypeId.newDate, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"datetime", dbType:DbType.datetime, dbId:MyTypeId.datetime, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"decimal", dbType:DbType.decimal, dbId:MyTypeId.newDecimal, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"decimal", dbType:DbType.decimal, dbId:MyTypeId.decimal, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"double", dbType:DbType.float64, dbId:MyTypeId.float64, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"enum", dbType:DbType.int16, dbId:MyTypeId.enum_, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"geometry", dbType:DbType.record, dbId:MyTypeId.geometry, nativeName:"struct?", nativeSize:DbTypeSize.record, displaySize:DbTypeDisplaySize.record},
    {dbName:"int", dbType:DbType.int32, dbId:MyTypeId.int32, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"int24", dbType:DbType.int32, dbId:MyTypeId.int24, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"json", dbType:DbType.json, dbId:MyTypeId.json, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.json},
    {dbName:"longtext", dbType:DbType.text, dbId:MyTypeIdEx.longText, nativeName:"string", nativeSize:DbTypeSize.text, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"mediumblob", dbType:DbType.binaryVary, dbId:MyTypeId.mediumBlob, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"mediumtext", dbType:DbType.text, dbId:MyTypeIdEx.mediumText, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.text},
    {dbName:"set", dbType:DbType.int64, dbId:MyTypeId.set, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"smallint", dbType:DbType.int16, dbId:MyTypeId.int16, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"time", dbType:DbType.time, dbId:MyTypeId.time, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},
    {dbName:"timestamp", dbType:DbType.datetime, dbId:MyTypeId.timestamp, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"tinyblob", dbType:DbType.binaryVary, dbId:MyTypeId.tinyBlob, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"tinyint", dbType:DbType.int8, dbId:MyTypeId.int8, nativeName:"int8", nativeSize:DbTypeSize.int8, displaySize:DbTypeDisplaySize.int8},
    {dbName:"tinyint(1)", dbType:DbType.boolean, dbId:MyTypeIdEx.int8, nativeName:"bool", nativeSize:DbTypeSize.boolean, displaySize:DbTypeDisplaySize.boolean},
    {dbName:"tinytext", dbType:DbType.text, dbId:MyTypeIdEx.tinyText, nativeName:"string", nativeSize:DbTypeSize.text, displaySize:DbTypeDisplaySize.text},
    {dbName:"tinyvarchar", dbType:DbType.stringVary, dbId:MyTypeId.tinyVarChar, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"year", dbType:DbType.int16, dbId:MyTypeId.year, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"varbinary(?)", dbType:DbType.binaryVary, dbId:MyTypeId.varBinary, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"varchar(?)", dbType:DbType.stringVary, dbId:MyTypeId.varChar, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    ];

static immutable DbType[string] mySimpleTypes;

static immutable DbTypeInfo*[int32] myDbIdToDbTypeInfos;

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

public:
    this(int errorCode, string errorMessage, string sqlState,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @nogc nothrow pure
    {
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
        this.sqlState = sqlState;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
    }

public:
    string errorMessage;
    string file;
    string funcName;
    string sqlState;
    int errorCode;
    uint line;
}

struct MyFieldInfo
{
nothrow @safe:

public:
    DbType calculateDbType() const @nogc pure
    {
        DbType result = DbType.unknown;
        if (auto e = typeId in myDbIdToDbTypeInfos)
        {
            result = (*e).dbType;
            if (result == DbType.decimal || result == DbType.numeric)
                result = decimalDbType(result, precision);
            else if ((result == DbType.binaryVary || typeId == MyTypeId.enum_ || typeId == MyTypeId.set) && isText)
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

        version(none) //We do not support unsigned
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
        if (columnLength > 0)
            return columnLength;
    
        if (typeId != 0)
        {
            if (auto e = typeId in myDbIdToDbTypeInfos)
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
            ~ ", typeFlags=" ~ typeFlags.to!string()
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

shared static this() nothrow @safe
{
    myDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(DbConnectionParameterInfo[string]))[
            DbConnectionParameterIdentifier.allowBatch : DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.my),
            DbConnectionParameterIdentifier.integratedSecurity : DbConnectionParameterInfo(&isConnectionParameterIntegratedSecurity, toName(DbIntegratedSecurityConnection.legacy), dbConnectionParameterNullMin, dbConnectionParameterNullMax, DbScheme.my),
            DbConnectionParameterIdentifier.serverPort : DbConnectionParameterInfo(&isConnectionParameterInt32, "3_306", 0, uint16.max, DbScheme.my), // x_protocol=33060
            DbConnectionParameterIdentifier.userName : DbConnectionParameterInfo(&isConnectionParameterString, "root", 0, dbConnectionParameterMaxId, DbScheme.my),
        ];
    }();

    myDbIdToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[int32] result;
        foreach (i; 0..myNativeTypes.length)
        {
            const dbId = myNativeTypes[i].dbId;
            if (!(dbId in result))
                result[dbId] = &myNativeTypes[i];
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
        result["char"] = DbType.stringFixed;
        result["varchar"] = DbType.stringVary;
        result["binary"] = DbType.binaryFixed;
        result["varbinary"] = DbType.binaryVary;
        result["blob"] = DbType.binaryVary;
        result["tinyblob"] = DbType.binaryVary;
        result["mediumblob"] = DbType.binaryVary;
        result["longblob"] = DbType.binaryVary;
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
