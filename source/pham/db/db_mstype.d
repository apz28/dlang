/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.db_mstype;

version(Windows):

import pham.external.std.windows.sql;
import pham.external.std.windows.sqlext;
import pham.external.std.windows.sqltypes;
import std.array : Appender;
import std.conv : to;

debug(debug_pham_db_db_mstype) import pham.db.db_debug;
import pham.db.db_type;
import pham.db.db_value;
import pham.db.db_msconvert;

static immutable int[DbIsolationLevel.max + 1] odbcIsolationLevels = [
    SQL_TXN_READ_UNCOMMITTED,
    SQL_TXN_READ_COMMITTED,
    SQL_TXN_REPEATABLE_READ,
    SQL_TXN_SERIALIZABLE,
    SQL_TXN_SERIALIZABLE, //SQL_TXN_SS_SNAPSHOT, 
        // ODBC Driver... does not support snapshot - ex {ODBC Driver 17 for SQL Server}
        // only SQL Server Native Client... - ex {SQL Server Native Client 11.0}
    ];

static immutable DbConnectionParameterInfo[string] msDefaultConnectionParameterValues;

static immutable string[string] msMappedParameterNames;

static immutable string[] msValidConnectionParameterNames = [
    DbConnectionParameterIdentifier.connectionTimeout,
    DbConnectionParameterIdentifier.databaseName,
    DbConnectionParameterIdentifier.databaseFileName,
    DbConnectionParameterIdentifier.encrypt,
    DbConnectionParameterIdentifier.fetchRecordCount,
    DbConnectionParameterIdentifier.integratedSecurity,
    DbConnectionParameterIdentifier.packageSize,
    DbConnectionParameterIdentifier.pooling,
    DbConnectionParameterIdentifier.serverName,
    DbConnectionParameterIdentifier.serverPort,
    DbConnectionParameterIdentifier.userName,
    DbConnectionParameterIdentifier.userPassword,
    DbConnectionParameterIdentifier.msAddress,
    DbConnectionParameterIdentifier.msApplicationName,
    DbConnectionParameterIdentifier.msApplicationIntent,
    DbConnectionParameterIdentifier.msAttachDBFileName,
    DbConnectionParameterIdentifier.msAutoTranslate,
    //DbConnectionParameterIdentifier.msDatabase,
    DbConnectionParameterIdentifier.msDriver,
    DbConnectionParameterIdentifier.msDSN,
    //DbConnectionParameterIdentifier.msEncrypt,
    DbConnectionParameterIdentifier.msFailoverPartner,
    DbConnectionParameterIdentifier.msFileDSN,
    DbConnectionParameterIdentifier.msLanguage,
    DbConnectionParameterIdentifier.msMARSConnection,
    DbConnectionParameterIdentifier.msMultiSubnetFailover,
    DbConnectionParameterIdentifier.msNetwork,
    DbConnectionParameterIdentifier.msPWD,
    DbConnectionParameterIdentifier.msQueryLogOn,
    DbConnectionParameterIdentifier.msQueryLogFile,
    DbConnectionParameterIdentifier.msQueryLogTime,
    DbConnectionParameterIdentifier.msQuotedId,
    DbConnectionParameterIdentifier.msRegional,
    //DbConnectionParameterIdentifier.msServer,
    DbConnectionParameterIdentifier.msTrustedConnection,
    DbConnectionParameterIdentifier.msTrustServerCertificate,
    DbConnectionParameterIdentifier.msUID,
    DbConnectionParameterIdentifier.msWSID,
    ];

static immutable DbTypeInfo[] msNativeTypes = [
    {dbName:"bigint", dbType:DbType.int64, dbId:SQL_BIGINT, nativeName:"int64", nativeSize:DbTypeSize.int64, displaySize:DbTypeDisplaySize.int64},
    {dbName:"binary(?)", dbType:DbType.binaryFixed, dbId:SQL_BINARY, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryFixed, displaySize:DbTypeDisplaySize.binaryFixed}, //binary[]
    {dbName:"bit", dbType:DbType.boolean, dbId:SQL_BIT, nativeName:"bool", nativeSize:DbTypeSize.boolean, displaySize:DbTypeDisplaySize.boolean},
    {dbName:"char(?)", dbType:DbType.stringFixed, dbId:SQL_CHAR, nativeName:"string", nativeSize:DbTypeSize.stringFixed, displaySize:DbTypeDisplaySize.stringFixed}, //char[]
    {dbName:"date", dbType:DbType.date, dbId:SQL_TYPE_DATE, nativeName:"DbDate", nativeSize:DbTypeSize.date, displaySize:DbTypeDisplaySize.date},
    {dbName:"datetime2", dbType:DbType.datetime, dbId:SQL_DATETIME, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"datetime2", dbType:DbType.datetime, dbId:SQL_TIMESTAMP, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"datetime2", dbType:DbType.datetime, dbId:SQL_TYPE_TIMESTAMP, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"datetime", dbType:DbType.datetime, dbId:SQL_DATETIME, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime}, //outdated    
    {dbName:"datetimeoffset", dbType:DbType.datetimeTZ, dbId:SQL_SS_TIMESTAMPOFFSET, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetimeTZ, displaySize:DbTypeDisplaySize.datetimeTZ},    
    {dbName:"decimal", dbType:DbType.decimal, dbId:SQL_DECIMAL, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"float", dbType:DbType.float64, dbId:SQL_DOUBLE, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"float", dbType:DbType.float64, dbId:SQL_FLOAT, nativeName:"float64", nativeSize:DbTypeSize.float64, displaySize:DbTypeDisplaySize.float64},
    {dbName:"image", dbType:DbType.binaryVary, dbId:SQL_LONGVARBINARY, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"int", dbType:DbType.int32, dbId:SQL_INTEGER, nativeName:"int32", nativeSize:DbTypeSize.int32, displaySize:DbTypeDisplaySize.int32},
    {dbName:"money", dbType:DbType.decimal, dbId:SQL_DECIMAL, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"numeric", dbType:DbType.numeric, dbId:SQL_NUMERIC, nativeName:"Numeric", nativeSize:DbTypeSize.numeric, displaySize:DbTypeDisplaySize.numeric},
    {dbName:"real", dbType:DbType.float32, dbId:SQL_REAL, nativeName:"float32", nativeSize:DbTypeSize.float32, displaySize:DbTypeDisplaySize.float32},
    {dbName:"smalldatetime", dbType:DbType.datetime, dbId:SQL_DATETIME, nativeName:"DbDateTime", nativeSize:DbTypeSize.datetime, displaySize:DbTypeDisplaySize.datetime},
    {dbName:"smallint", dbType:DbType.int16, dbId:SQL_SMALLINT, nativeName:"int16", nativeSize:DbTypeSize.int16, displaySize:DbTypeDisplaySize.int16},
    {dbName:"smallmoney", dbType:DbType.decimal, dbId:SQL_DECIMAL, nativeName:"Decimal", nativeSize:DbTypeSize.decimal, displaySize:DbTypeDisplaySize.decimal},
    {dbName:"text", dbType:DbType.stringVary, dbId:SQL_LONGVARCHAR, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"time", dbType:DbType.time, dbId:SQL_SS_TIME2, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time}, // with fraction
    {dbName:"time", dbType:DbType.time, dbId:SQL_TIME, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},
    {dbName:"time", dbType:DbType.time, dbId:SQL_TYPE_TIME, nativeName:"DbTime", nativeSize:DbTypeSize.time, displaySize:DbTypeDisplaySize.time},    
    {dbName:"tinyint", dbType:DbType.int8, dbId:SQL_TINYINT, nativeName:"int8", nativeSize:DbTypeSize.int8, displaySize:DbTypeDisplaySize.int8},
    {dbName:"uniqueidentifier", dbType:DbType.uuid, dbId:SQL_GUID, nativeName:"UUID", nativeSize:DbTypeSize.uuid, displaySize:DbTypeDisplaySize.uuid},
    {dbName:"varbinary(?)", dbType:DbType.binaryVary, dbId:SQL_LONGVARBINARY, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"varbinary(?)", dbType:DbType.binaryVary, dbId:SQL_VARBINARY, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"varbinary(max)", dbType:DbType.binaryVary, dbId:SQL_LONGVARBINARY, nativeName:"ubyte[]", nativeSize:DbTypeSize.binaryVary, displaySize:DbTypeDisplaySize.binaryVary},
    {dbName:"varchar(?)", dbType:DbType.stringVary, dbId:SQL_LONGVARCHAR, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"varchar(?)", dbType:DbType.stringVary, dbId:SQL_VARCHAR, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"varchar(max)", dbType:DbType.stringVary, dbId:SQL_LONGVARCHAR, nativeName:"string", nativeSize:DbTypeSize.stringVary, displaySize:DbTypeDisplaySize.stringVary},
    {dbName:"xml", dbType:DbType.xml, dbId:SQL_SS_XML, nativeName:"string", nativeSize:DbTypeSize.xml, displaySize:DbTypeDisplaySize.xml},
    {dbName:"", dbType:DbType.unknown, dbId:SQL_UNKNOWN_TYPE, nativeName:"null", nativeSize:0, displaySize:4},
    ];

static immutable DbTypeInfo*[int32] msDbIdToDbTypeInfos;

struct MsDescribeInfo
{
nothrow @safe:

public:
    bool allowNull() const @nogc
    {
        return nullable != SQL_NO_NULLS;
    }

    static DbFieldIdType isValueIdType(int32 mIdType, int32 mIdSubType) @nogc pure
    {
        return DbFieldIdType.no;
    }

    DbType dbType() const @nogc pure
    {
        if (dataType == SQL_DECIMAL || dataType == SQL_NUMERIC)
        {
            if (const p = decimalDigits)
            {
                return p <= 9
                    ? DbType.decimal32
                    : (p <= 18 ? DbType.decimal64 : DbType.decimal);
            }
        }

        if (auto e = dataType in msDbIdToDbTypeInfos)
            return (*e).dbType;

        return DbType.unknown;
    }

    int32 dbTypeSize() const @nogc pure
    {
        if (dataSize > 0)
            return cast(int32)dataSize;

        if (dataType != 0)
        {
            if (auto e = dataType in msDbIdToDbTypeInfos)
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

    string traceString() const
    {
        import std.conv : to;

        return "dataSize=" ~ dataSize.to!string()
            ~ ", dataType=" ~ dataType.to!string()
            ~ ", decimalDigits=" ~ decimalDigits.to!string()
            ~ ", nullable=" ~ nullable.to!string();
    }

public:
    SQLULEN dataSize;
    SQLSMALLINT dataType;
    SQLSMALLINT decimalDigits;
    SQLSMALLINT nullable;
    ushort ordinal;
}

struct MsMappedData
{
    SQLPOINTER targetValuePtr;
    SQLLEN* strLenOrIndPtr;
    SQLLEN targetLength;
    SQLSMALLINT targetInputType;
    SQLSMALLINT targetType;
}

struct MsMappedDataInfo
{
@safe:

public:
    void clear() nothrow scope
    {
        clearData();
        inputBufferLength = originalType = targetType = 0;
        buffer = null;
        getDataFct = null;
        resetDataFct = null;
    }
    
    pragma(inline, true)
    void clearData() nothrow scope
    {
        strLenOrInd = 0;
        timestampOffset = SQL_SS_TIMESTAMPOFFSET_STRUCT.init; // Use biggest member to set all bytes to zero
    }
    
    MsMappedData getBindField(scope const(DbBaseTypeInfo) baseInfo) nothrow return
    {
        reset(baseInfo);
        return getBindImpl(DbParameterDirection.output, baseInfo, false);
    }
    
    MsMappedData getBindParameter(const(DbParameterDirection) direction, scope const(DbBaseTypeInfo) baseInfo) nothrow return
    {
        reset(baseInfo);
        return getBindImpl(direction, baseInfo, false);
    }

    MsMappedData getBindParameter(const(DbParameterDirection) direction, scope const(DbBaseTypeInfo) baseInfo,
        ref DbValue value) return
    {
        reset(baseInfo);

        if (!value.isNull)
            setData(baseInfo, value);

        return getBindImpl(direction, baseInfo, value.isNull);
    }

    pragma(inline, true)
    ubyte[] getBufferData() nothrow
    in
    {
        assert(strLenOrInd >= 0);
    }
    do
    {
        return buffer[0..strLenOrInd];
    }
    
    pragma(inline, true)
    DbValue getData()
    in
    {
        assert(originalType != 0);
        assert(getDataFct !is null);
    }
    do
    {
        debug(debug_pham_db_db_mstype) debug writeln(__FUNCTION__, "(targetType=", targetType, ", originalType=", originalType, ")");
        
        return getDataFct(this);
    }

    alias GetData = DbValue function(ref MsMappedDataInfo dataInfo) @safe;
    
    static DbValue getDataImpl(int originalType)(ref MsMappedDataInfo dataInfo)
    {
        static if (originalType == SQL_C_LONG)
            return DbValue(dataInfo.int_);
        else static if (originalType == SQL_C_SBIGINT)
            return DbValue(dataInfo.bigint);
        else static if (originalType == SQL_C_DOUBLE)
            return DbValue(dataInfo.double_);
        else static if (originalType == SQL_C_FLOAT)
            return DbValue(dataInfo.real_);
        else static if (originalType == SQL_C_DATE)
            return DbValue(fromDate(dataInfo.date));
        else static if (originalType == SQL_C_TIMESTAMP)
            return DbValue(fromTimestamp(dataInfo.timestamp));
        else static if (originalType == SQL_C_SS_TIMESTAMPOFFSET)
            return DbValue(fromTimestampOffset(dataInfo.timestampOffset));
        else static if (originalType == SQL_C_CHAR)
            return DbValue(cast(string)dataInfo.getBufferData().idup);
        else static if (originalType == SQL_C_BINARY)
            return DbValue(dataInfo.getBufferData().dup);
        //else static if (originalType == SQL_C_NUMERIC) // mapped to chars
        //    return dataInfo.getDataDecimal(dataInfo);
        else static if (originalType == SQL_C_GUID)
            return DbValue(dataInfo.uuid);
        else static if (originalType == SQL_C_SHORT)
            return DbValue(dataInfo.smallint);
        else static if (originalType == SQL_C_TINYINT)
            return DbValue(dataInfo.tinyint);
        else static if (originalType == SQL_C_BIT)
            return DbValue(dataInfo.bit == SQL_TRUE);
        else static if (originalType == SQL_C_SS_TIME2)
            return DbValue(fromTime2(dataInfo.time2));
        else static if (originalType == SQL_C_TIME)
            return DbValue(fromTime(dataInfo.time));
        else
            static assert(0, "Unsupported targetType: " ~ originalType.to!string);
    }
    
    pragma(inline, true)
    bool hasMoreData() const nothrow
    {
        return (strLenOrInd > buffer.length) && (originalType == SQL_C_CHAR || originalType == SQL_C_BINARY);
    }

    pragma(inline, true)
    bool isNullData() const nothrow
    {
        return strLenOrInd == SQL_NULL_DATA;
    }

    pragma(inline, true)
    bool isStringData() const nothrow
    {
        return originalType == SQL_C_CHAR;
    }
    
    pragma(inline, true)
    MsMappedData resetData() nothrow return
    in
    {
        assert(originalType != 0);
        assert(resetDataFct !is null);
    }
    do
    {        
        debug(debug_pham_db_db_mstype) debug writeln(__FUNCTION__, "(targetType=", targetType, ", originalType=", originalType, ")");
        
        return resetDataFct(this);
    }
    
    alias ResetData = MsMappedData function(return ref MsMappedDataInfo dataInfo) nothrow;
    
    static MsMappedData resetDataImpl(int originalType)(return ref MsMappedDataInfo dataInfo) nothrow
    {
        dataInfo.clearData();
        
        MsMappedData result;
        result.strLenOrIndPtr = &dataInfo.strLenOrInd;
        result.targetInputType = targetInputTypes[DbParameterDirection.output];
        result.targetType = dataInfo.targetType;
        
        static if (originalType == SQL_C_LONG)
        {
            result.targetValuePtr = &dataInfo.int_;
            result.targetLength = typeof(dataInfo.int_).sizeof;
        }
        else static if (originalType == SQL_C_SBIGINT)
        {
            result.targetValuePtr = &dataInfo.bigint;
            result.targetLength = typeof(dataInfo.bigint).sizeof;
        }
        else static if (originalType == SQL_C_DOUBLE)
        {
            result.targetValuePtr = &dataInfo.double_;
            result.targetLength = typeof(dataInfo.double_).sizeof;
        }
        else static if (originalType == SQL_C_FLOAT)
        {
            result.targetValuePtr = &dataInfo.real_;
            result.targetLength = typeof(dataInfo.real_).sizeof;
        }
        else static if (originalType == SQL_C_DATE)
        {
            result.targetValuePtr = &dataInfo.date;
            result.targetLength = typeof(dataInfo.date).sizeof;
        }
        else static if (originalType == SQL_C_TIMESTAMP)
        {
            result.targetValuePtr = &dataInfo.timestamp;
            result.targetLength = typeof(dataInfo.timestamp).sizeof;
        }
        else static if (originalType == SQL_C_SS_TIMESTAMPOFFSET)
        {
            result.targetValuePtr = &dataInfo.timestampOffset;
            result.targetLength = typeof(dataInfo.timestampOffset).sizeof;
        }
        else static if (originalType == SQL_C_CHAR)
        {
            result.targetValuePtr = &dataInfo.buffer[0];
            result.targetLength = dataInfo.buffer.length;
        }
        else static if (originalType == SQL_C_BINARY)
        {
            result.targetValuePtr = &dataInfo.buffer[0];
            result.targetLength = dataInfo.buffer.length;
        }
        else static if (originalType == SQL_C_NUMERIC) // mapped to chars
        {
            result.targetValuePtr = &dataInfo.buffer[0];
            result.targetLength = dataInfo.buffer.length;
        }
        else static if (originalType == SQL_C_GUID)
        {
            result.targetValuePtr = &dataInfo.uuid;
            result.targetLength = typeof(dataInfo.uuid).sizeof;
        }
        else static if (originalType == SQL_C_SHORT)
        {
            result.targetValuePtr = &dataInfo.smallint;
            result.targetLength = typeof(dataInfo.smallint).sizeof;
        }
        else static if (originalType == SQL_C_TINYINT)
        {
            result.targetValuePtr = &dataInfo.tinyint;
            result.targetLength = typeof(dataInfo.tinyint).sizeof;
        }
        else static if (originalType == SQL_C_BIT)
        {
            result.targetValuePtr = &dataInfo.bit;
            result.targetLength = typeof(dataInfo.bit).sizeof;
        }
        else static if (originalType == SQL_C_SS_TIME2)
        {
            result.targetValuePtr = &dataInfo.time2;
            result.targetLength = typeof(dataInfo.time2).sizeof;
        }
        else static if (originalType == SQL_C_TIME)
        {
            result.targetValuePtr = &dataInfo.time;
            result.targetLength = typeof(dataInfo.time).sizeof;
        }
        else
            static assert(0, "Unsupported targetType: " ~ originalType.to!string);
        
        return result;
    }
    
    void setData(scope const(DbBaseTypeInfo) baseInfo, ref DbValue value) @trusted
    in
    {
        assert(!value.isNull);
    }
    do
    {
        switch (baseInfo.typeId)
        {
            case SQL_INTEGER:
                this.int_ = value.coerce!int();
                break;
                
            case SQL_BIGINT:
                this.bigint = value.coerce!long();
                break;
            
            case SQL_DOUBLE:
            case SQL_FLOAT:
                this.double_ = value.coerce!double();
                break;

            case SQL_REAL:
                this.real_ = value.coerce!float();
                break;

            case SQL_TYPE_DATE:
                this.date = toDate(value.coerce!DbDate()); 
                break;

            case SQL_DATETIME:
            case SQL_TIMESTAMP:
            case SQL_TYPE_TIMESTAMP:
                this.timestamp = toTimeStamp(value.coerce!DbDateTime());
                break;

            case SQL_SS_TIMESTAMPOFFSET:
                this.timestampOffset = toTimeStampOffset(value.coerce!DbDateTime());
                break;

            case SQL_CHAR:
            case SQL_VARCHAR:
            case SQL_LONGVARCHAR:
            case SQL_SS_XML:
                auto s = value.coerce!(const(char)[])();
                const sLength = this.inputBufferLength = s.length;
                ensureBufferLength(sLength);
                this.buffer[0..sLength] = cast(ubyte[])s[0..sLength];
                break;

            case SQL_BINARY:
            case SQL_VARBINARY:
            case SQL_LONGVARBINARY:
                auto b = value.coerce!(const(ubyte)[])();
                const bLength = this.inputBufferLength = b.length;
                ensureBufferLength(bLength);
                this.buffer[0..bLength] = b[0..bLength];
                break;

            case SQL_DECIMAL:
            case SQL_NUMERIC:
                auto d = value.coerce!Decimal();
                auto ds = d.toString();
                const dsLength = this.inputBufferLength = ds.length;
                ensureBufferLength(dsLength);
                this.buffer[0..dsLength] = cast(ubyte[])ds[0..dsLength];
                break;

            case SQL_GUID:
                this.uuid = value.coerce!UUID();
                break;

            case SQL_SMALLINT:
                this.smallint = value.coerce!short();
                break;

            case SQL_TINYINT:
                this.tinyint = value.coerce!byte();
                break;

            case SQL_BIT:
                this.bit = value.coerce!bool() ? SQL_TRUE : SQL_FALSE;
                break;

            case SQL_SS_TIME2:
                this.time2 = toTime2(value.coerce!DbTime()); 
                break;

            case SQL_TIME:
            case SQL_TYPE_TIME:
                this.time = toTime(value.coerce!DbTime()); 
                break;
                
            default:
                // Probably just request in string
                assert(0, "Unsupported targetType: " ~ baseInfo.typeId.to!string);
        }
    }

private:
    bool canSetBufferLength(scope const(DbBaseTypeInfo) baseInfo) nothrow pure scope
    {
        if (baseInfo.size <= 0 || baseInfo.size > 0xFFFF) // skip varchar(max)
            return false;
            
        return baseInfo.typeId == SQL_CHAR || baseInfo.typeId == SQL_VARCHAR || baseInfo.typeId == SQL_LONGVARCHAR
            || baseInfo.typeId == SQL_BINARY || baseInfo.typeId == SQL_VARBINARY || baseInfo.typeId == SQL_LONGVARBINARY
            || baseInfo.typeId == SQL_SS_XML;
    }
    
    pragma(inline, true)
    size_t ensureBufferLength(const(size_t) capacity) nothrow scope @trusted
    {
        debug(debug_pham_db_db_mstype) debug writeln(__FUNCTION__, "(capacity=", capacity, ", targetType=", targetType, ")");
        
        if (buffer.length < capacity)
        {
            buffer.length = capacity;
            buffer.assumeSafeAppend();
        }
        return buffer.length;
    }

    static immutable SQLSMALLINT[DbParameterDirection.max + 1] targetInputTypes = [
        SQL_PARAM_INPUT, SQL_PARAM_INPUT_OUTPUT, SQL_PARAM_OUTPUT, SQL_RETURN_VALUE
        ];

    MsMappedData getBindImpl(const(DbParameterDirection) direction, scope const(DbBaseTypeInfo) baseInfo, const(bool) isNull) nothrow return
    {
        enum maxLongVarSize = 1_000;
        enum maxVarSize = 200;
        
        MsMappedData result;
        result.strLenOrIndPtr = &this.strLenOrInd;
        result.targetInputType = targetInputTypes[direction];
        switch (baseInfo.typeId)
        {
            case SQL_INTEGER:
                result.targetValuePtr = &this.int_;
                result.targetLength = typeof(this.int_).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_LONG;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.int_).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_LONG;
                this.resetDataFct = &resetDataImpl!SQL_C_LONG;
                break;
                
            case SQL_BIGINT:
                result.targetValuePtr = &this.bigint;
                result.targetLength = typeof(this.bigint).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_SBIGINT;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.bigint).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_SBIGINT;
                this.resetDataFct = &resetDataImpl!SQL_C_SBIGINT;
                break;

            case SQL_DOUBLE:
            case SQL_FLOAT:
                result.targetValuePtr = &this.double_;
                result.targetLength = typeof(this.double_).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_DOUBLE;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.double_).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_DOUBLE;
                this.resetDataFct = &resetDataImpl!SQL_C_DOUBLE;
                break;

            case SQL_REAL:
                result.targetValuePtr = &this.real_;
                result.targetLength = typeof(this.real_).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_FLOAT;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.real_).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_FLOAT;
                this.resetDataFct = &resetDataImpl!SQL_C_FLOAT;
                break;

            case SQL_TYPE_DATE:
                result.targetValuePtr = &this.date;
                result.targetLength = typeof(this.date).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_DATE;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.date).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_DATE;
                this.resetDataFct = &resetDataImpl!SQL_C_DATE;
                break;

            case SQL_DATETIME:
            case SQL_TIMESTAMP:
            case SQL_TYPE_TIMESTAMP:
                result.targetValuePtr = &this.timestamp;
                result.targetLength = typeof(this.timestamp).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_TIMESTAMP;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.timestamp).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_TIMESTAMP;
                this.resetDataFct = &resetDataImpl!SQL_C_TIMESTAMP;
                break;
                
            case SQL_SS_TIMESTAMPOFFSET:
                result.targetValuePtr = &this.timestampOffset;
                result.targetLength = typeof(this.timestampOffset).sizeof;
                result.targetType = this.targetType = SQL_C_BINARY;
                this.originalType = SQL_C_SS_TIMESTAMPOFFSET;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.timestampOffset).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_SS_TIMESTAMPOFFSET;
                this.resetDataFct = &resetDataImpl!SQL_C_SS_TIMESTAMPOFFSET;
                break;

            case SQL_CHAR:
            case SQL_VARCHAR:
                if (!canSetBufferLength(baseInfo) && isParameterOutput(direction, true))
                    this.inputBufferLength = ensureBufferLength(maxVarSize);
                result.targetValuePtr = &this.buffer[0];
                result.targetLength = isParameterInput(direction) ? this.inputBufferLength : this.buffer.length;
                result.targetType = this.originalType = this.targetType = SQL_C_CHAR;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : inputBufferLength;
                this.getDataFct = &getDataImpl!SQL_C_CHAR;
                this.resetDataFct = &resetDataImpl!SQL_C_CHAR;
                break;

            case SQL_LONGVARCHAR:
            case SQL_SS_XML:
                if (!canSetBufferLength(baseInfo) && isParameterOutput(direction, true))
                    this.inputBufferLength = ensureBufferLength(maxLongVarSize);
                result.targetValuePtr = &this.buffer[0];
                result.targetLength = isParameterInput(direction) ? this.inputBufferLength : this.buffer.length;
                result.targetType = this.originalType = this.targetType = SQL_C_CHAR;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : this.inputBufferLength;
                this.getDataFct = &getDataImpl!SQL_C_CHAR;
                this.resetDataFct = &resetDataImpl!SQL_C_CHAR;
                break;

            case SQL_BINARY:
            case SQL_VARBINARY:
                if (!canSetBufferLength(baseInfo) && isParameterOutput(direction, true))
                    this.inputBufferLength = ensureBufferLength(maxVarSize);
                result.targetValuePtr = &this.buffer[0];
                result.targetLength = isParameterInput(direction) ? this.inputBufferLength : this.buffer.length;
                result.targetType = this.originalType = this.targetType = SQL_C_BINARY;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : this.inputBufferLength;
                this.getDataFct = &getDataImpl!SQL_C_BINARY;
                this.resetDataFct = &resetDataImpl!SQL_C_BINARY;
                break;

            case SQL_LONGVARBINARY:
                if (!canSetBufferLength(baseInfo) && isParameterOutput(direction, true))
                    this.inputBufferLength = ensureBufferLength(maxLongVarSize);
                result.targetValuePtr = &this.buffer[0];
                result.targetLength = isParameterInput(direction) ? this.inputBufferLength : this.buffer.length;
                result.targetType = this.originalType = this.targetType = SQL_C_BINARY;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : this.inputBufferLength;
                this.getDataFct = &getDataImpl!SQL_C_BINARY;
                this.resetDataFct = &resetDataImpl!SQL_C_BINARY;
                break;

            case SQL_DECIMAL:
            case SQL_NUMERIC:
                enum maxNumericSize = 50;
                if (isParameterOutput(direction, true))
                    this.inputBufferLength = ensureBufferLength(maxNumericSize);
                result.targetValuePtr = &this.buffer[0];
                result.targetLength = isParameterInput(direction) ? this.inputBufferLength : this.buffer.length;
                result.targetType = this.targetType = SQL_C_CHAR;
                this.originalType = SQL_C_NUMERIC;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : this.inputBufferLength;
                this.resetDataFct = &resetDataImpl!SQL_C_NUMERIC;
                if (baseInfo.numericDigits > 0)
                {
                    if (baseInfo.numericDigits <= Decimal32.PRECISION)
                        this.getDataFct = &getDataDecimal!Decimal32;
                    else if (baseInfo.numericDigits <= Decimal64.PRECISION)
                        this.getDataFct = &getDataDecimal!Decimal64;
                    else if (baseInfo.numericDigits <= Decimal128.PRECISION)
                        this.getDataFct = &getDataDecimal!Decimal128;
                    else
                        this.getDataFct = &getDataDecimal!Decimal;
                }
                else
                    this.getDataFct = &getDataDecimal!Decimal;
                break;

            case SQL_GUID:
                result.targetValuePtr = &this.uuid;
                result.targetLength = typeof(this.uuid).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_GUID;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.uuid).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_GUID;
                this.resetDataFct = &resetDataImpl!SQL_C_GUID;
                break;

            case SQL_SMALLINT:
                result.targetValuePtr = &this.smallint;
                result.targetLength = typeof(this.smallint).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_SHORT;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.smallint).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_SHORT;
                this.resetDataFct = &resetDataImpl!SQL_C_SHORT;
                break;

            case SQL_TINYINT:
                result.targetValuePtr = &this.tinyint;
                result.targetLength = typeof(this.tinyint).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_TINYINT;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.tinyint).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_TINYINT;
                this.resetDataFct = &resetDataImpl!SQL_C_TINYINT;
                break;

            case SQL_BIT:
                result.targetValuePtr = &this.bit;
                result.targetLength = typeof(this.bit).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_BIT;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.bit).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_BIT;
                this.resetDataFct = &resetDataImpl!SQL_C_BIT;
                break;

            case SQL_SS_TIME2:
                result.targetValuePtr = &this.time2;
                result.targetLength = typeof(this.time2).sizeof;
                result.targetType = this.targetType = SQL_C_BINARY;
                this.originalType = SQL_C_SS_TIME2;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.time2).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_SS_TIME2;
                this.resetDataFct = &resetDataImpl!SQL_C_SS_TIME2;
                break;

            case SQL_TIME:
            case SQL_TYPE_TIME:
                result.targetValuePtr = &this.time;
                result.targetLength = typeof(this.time).sizeof;
                result.targetType = this.originalType = this.targetType = SQL_C_TIME;
                this.strLenOrInd = isNull ? SQL_NULL_DATA : typeof(this.time).sizeof;
                this.getDataFct = &getDataImpl!SQL_C_TIME;
                this.resetDataFct = &resetDataImpl!SQL_C_TIME;
                break;

            default:
                assert(0, "Unsupported targetType: " ~ baseInfo.typeId.to!string);
        }
        
        return result;
    }
    
    static DbValue getDataDecimal(T)(ref MsMappedDataInfo dataInfo)
    {
        const s = cast(const(char)[])dataInfo.getBufferData();
        return DbValue(T(s));
    }
    
    void reset(scope const(DbBaseTypeInfo) baseInfo) nothrow scope
    {
        clearData();
        originalType = targetType = 0;
        getDataFct = null;
        resetDataFct = null;
        inputBufferLength = ensureBufferLength(canSetBufferLength(baseInfo) ? baseInfo.size+char.sizeof : 0); // +1=null terminated
    }

public:
    // All static size types
    union
    {
        SQL_SS_TIMESTAMPOFFSET_STRUCT timestampOffset; // 24 bytes
        //SQL_NUMERIC_STRUCT numeric; // 19 bytes -> mapped to use chars
        UUID uuid; // 16 bytes
        TIMESTAMP_STRUCT timestamp; // 14 bytes
        SQL_SS_TIME2_STRUCT time2; // 12 bytes
        int64 bigint; // 8 bytes
        double double_; // 8 bytes
        DATE_STRUCT date; // 6 bytes
        TIME_STRUCT time; // 6 bytes
        int int_; // 4 bytes
        float real_; // 4 bytes
        short smallint; // 2 bytes
        byte tinyint; // 1 byte
        byte bit; // 1 byte
    }

    // dynamic size types
    ubyte[] buffer;
    size_t inputBufferLength;

    SQLLEN strLenOrInd;
    SQLSMALLINT originalType;
    SQLSMALLINT targetType;
    
    GetData getDataFct;
    ResetData resetDataFct;
}

enum MsResultKind
{
    success,
    successInfo,
    error,
}

struct MsResultStatus
{
@safe:

public:
    MsResultKind getStatus() const @nogc nothrow
    {
        return (resultCode == SQL_SUCCESS) || (resultCode == SQL_SUCCESS_WITH_INFO && sqlErrorMessage.length == 0)
            ? MsResultKind.success
            : (resultCode == SQL_SUCCESS_WITH_INFO ? MsResultKind.successInfo : MsResultKind.error);
    }
    
public:
    string apiName;
    string state;
    string sqlErrorMessage;
    int32 sqlErrorCode;
    SQLRETURN resultCode;
}

struct MsResultStatusArray
{
@safe:

public:
    bool opCast(C: bool)() const nothrow
    {
        return length != 0;
    }

    MsResultStatus[] opIndex() nothrow return
    {
        return values[0..length];
    }

    DbNotificationMessage getMessage() const nothrow
    {
        int resultCode;
        Appender!string resultText;
        resultText.reserve(500);
        foreach (i; 0..length)
        {
            if (i)
                resultText.put("\n");
            resultText.put(values[i].sqlErrorMessage);
            if (resultCode == 0)
                resultCode = values[i].sqlErrorCode;
        }
        return DbNotificationMessage(resultText.data, resultCode);
    }
    
    MsResultKind getStatus(ref size_t errorIndex) const @nogc nothrow
    {
        MsResultKind result = MsResultKind.success;        
        foreach (i; 0..length)
        {
            final switch (values[i].getStatus())
            {
                case MsResultKind.error:
                    errorIndex = i;
                    return MsResultKind.error;
                case MsResultKind.successInfo:
                    result = MsResultKind.successInfo;
                    break;
                case MsResultKind.success:
                    break;
            }
        }
        return result;
    }
    
    ref typeof(this) reset() nothrow return
    {
        length = 0;
        values[] = MsResultStatus.init;
        return this;
    }

public:
    enum max = 10;

    size_t length;
    MsResultStatus[max] values;
}

pragma(inline, true)
bool isSuccessResult1(const(SQLRETURN) r) @nogc nothrow pure @safe
{
    return r == SQL_SUCCESS;
}

pragma(inline, true)
bool isSuccessResult2(const(SQLRETURN) r) @nogc nothrow pure @safe
{
    return r == SQL_SUCCESS || r == SQL_SUCCESS_WITH_INFO;
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    msDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(DbConnectionParameterInfo[string]))[
            //DbConnectionParameterIdentifier.serverPort : DbConnectionParameterInfo(&isConnectionParameterInt32, "1_433", 0, uint16.max, DbScheme.ms), // If using instance name, it will have dynamic listening port, so avoid default setting
            DbConnectionParameterIdentifier.userName : DbConnectionParameterInfo(&isConnectionParameterString, "sa", 0, dbConnectionParameterMaxId, DbScheme.ms),
            ];
    }();

    msMappedParameterNames = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbConnectionParameterIdentifier.msAttachDBFileName : DbConnectionParameterIdentifier.databaseFileName,
            //DbConnectionParameterIdentifier.msDatabase : DbConnectionParameterIdentifier.databaseName,            
            //DbConnectionParameterIdentifier.msEncrypt : DbConnectionParameterIdentifier.encrypt,
            DbConnectionParameterIdentifier.msPWD : DbConnectionParameterIdentifier.userPassword,
            //DbConnectionParameterIdentifier.msServer : DbConnectionParameterIdentifier.serverName,
            DbConnectionParameterIdentifier.msTrustedConnection : DbConnectionParameterIdentifier.integratedSecurity,
            DbConnectionParameterIdentifier.msUID : DbConnectionParameterIdentifier.userName,
            ]; 
    }();

    msDbIdToDbTypeInfos = () nothrow pure @trusted
    {
        immutable(DbTypeInfo)*[int32] result;
        foreach (i; 0..msNativeTypes.length)
        {
            const dbId = msNativeTypes[i].dbId;
            if (!(dbId in result))
                result[dbId] = &msNativeTypes[i];
        }
        return result;
    }();
}
