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

immutable string myAuthDefault = myAuthNativeName;
immutable string myAuthNativeName = "mysql_native_password";
immutable string myAuthScramSha1Name = "SCRAM-SHA-1";
immutable string myAuthScramSha256Name = "SCRAM-SHA-256";

immutable string[string] myDefaultParameterValues;

immutable string[] myValidParameterNames = [
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

immutable DbTypeInfo[] myNativeTypes = [
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

immutable DbType[string] mySimpleTypes;

immutable DbTypeInfo*[int32] myOIdTypeToDbTypeInfos;

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
    myDefaultParameterValues = () nothrow pure @trusted // @trusted=cast()
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
