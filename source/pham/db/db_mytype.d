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
import pham.db.message;
import pham.db.type;
import pham.db.myoid;

nothrow @safe:

version (none) immutable string[string] pgDefaultParameterValues;

version (none)
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

version (none)
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
    {dbName:"DECIMAL(?)", nativeName:"numeric", displaySize:34, nativeSize:Decimal.sizeof, nativeId:PgOIdType.numeric, dbType:DbType.decimal}, // Prefer numeric over money for generic setting
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

version (none)
immutable DbTypeInfo*[int32] PgOIdTypeToDbTypeInfos;

