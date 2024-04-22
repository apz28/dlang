/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

//-----------------------------------------------------------------------------
// File:            sql.h
//
// Contents:        This is the the main include for ODBC Core functions.
//
// Comments:        preconditions: #include "windows.h"
//
//-----------------------------------------------------------------------------

module pham.external.std.windows.sql;

version (Windows):
extern (Windows):
@nogc:
nothrow:

import pham.external.std.windows.sqltypes;

//enum ODBCVER = 0x0380; // Already defined in pham.external.std.windows.sqltypes

/* special length/indicator values */
enum SQL_NULL_DATA = -1;
enum SQL_DATA_AT_EXEC = -2;

/* return values from functions */
enum SQL_SUCCESS = 0;
enum SQL_SUCCESS_WITH_INFO = 1;
enum SQL_NO_DATA = 100;

enum SQL_PARAM_DATA_AVAILABLE = 101;

enum SQL_ERROR = -1;
enum SQL_INVALID_HANDLE = -2;

enum SQL_STILL_EXECUTING = 2;
enum SQL_NEED_DATA = 99;

/* test for SQL_SUCCESS or SQL_SUCCESS_WITH_INFO */
extern (D) auto SQL_SUCCEEDED(T)(auto ref T rc)
{
    return (rc & (~1)) == 0;
}

/* flags for null-terminated string */
enum SQL_NTS = -3;
enum SQL_NTSL = -3L;

/* maximum message length */
enum SQL_MAX_MESSAGE_LENGTH = 512;
enum SQL_MAX_MESSAGE_LENGTH_NULL = SQL_MAX_MESSAGE_LENGTH + 1;

/* date/time length constants */
enum SQL_DATE_LEN = 10;
enum SQL_TIME_LEN = 8; /* add P+1 if precision is nonzero */
enum SQL_TIMESTAMP_LEN = 19; /* add P+1 if precision is nonzero */

/* handle type identifiers */
enum SQL_HANDLE_ENV = 1;
enum SQL_HANDLE_DBC = 2;
enum SQL_HANDLE_STMT = 3;
enum SQL_HANDLE_DESC = 4;

/* environment attribute */
enum SQL_ATTR_OUTPUT_NTS = 10001;

/* connection attributes */
enum SQL_ATTR_AUTO_IPD = 10001;
enum SQL_ATTR_METADATA_ID = 10014;

/* statement attributes */
enum SQL_ATTR_APP_ROW_DESC = 10010;
enum SQL_ATTR_APP_PARAM_DESC = 10011;
enum SQL_ATTR_IMP_ROW_DESC = 10012;
enum SQL_ATTR_IMP_PARAM_DESC = 10013;
enum SQL_ATTR_CURSOR_SCROLLABLE = -1;
enum SQL_ATTR_CURSOR_SENSITIVITY = -2;

/* SQL_ATTR_CURSOR_SCROLLABLE values */
enum SQL_NONSCROLLABLE = 0;
enum SQL_SCROLLABLE = 1;

/* identifiers of fields in the SQL descriptor */
enum SQL_DESC_COUNT = 1001;
enum SQL_DESC_TYPE = 1002;
enum SQL_DESC_LENGTH = 1003;
enum SQL_DESC_OCTET_LENGTH_PTR = 1004;
enum SQL_DESC_PRECISION = 1005;
enum SQL_DESC_SCALE = 1006;
enum SQL_DESC_DATETIME_INTERVAL_CODE = 1007;
enum SQL_DESC_NULLABLE = 1008;
enum SQL_DESC_INDICATOR_PTR = 1009;
enum SQL_DESC_DATA_PTR = 1010;
enum SQL_DESC_NAME = 1011;
enum SQL_DESC_UNNAMED = 1012;
enum SQL_DESC_OCTET_LENGTH = 1013;
enum SQL_DESC_ALLOC_TYPE = 1099;

/* identifiers of fields in the diagnostics area */
enum SQL_DIAG_RETURNCODE = 1;
enum SQL_DIAG_NUMBER = 2;
enum SQL_DIAG_ROW_COUNT = 3;
enum SQL_DIAG_SQLSTATE = 4;
enum SQL_DIAG_NATIVE = 5;
enum SQL_DIAG_MESSAGE_TEXT = 6;
enum SQL_DIAG_DYNAMIC_FUNCTION = 7;
enum SQL_DIAG_CLASS_ORIGIN = 8;
enum SQL_DIAG_SUBCLASS_ORIGIN = 9;
enum SQL_DIAG_CONNECTION_NAME = 10;
enum SQL_DIAG_SERVER_NAME = 11;
enum SQL_DIAG_DYNAMIC_FUNCTION_CODE = 12;

/* dynamic function codes */
enum SQL_DIAG_ALTER_DOMAIN = 3;
enum SQL_DIAG_ALTER_TABLE = 4;
enum SQL_DIAG_CALL = 7;
enum SQL_DIAG_CREATE_ASSERTION = 6;
enum SQL_DIAG_CREATE_CHARACTER_SET = 8;
enum SQL_DIAG_CREATE_COLLATION = 10;
enum SQL_DIAG_CREATE_DOMAIN = 23;
enum SQL_DIAG_CREATE_INDEX = -1;
enum SQL_DIAG_CREATE_SCHEMA = 64;
enum SQL_DIAG_CREATE_TABLE = 77;
enum SQL_DIAG_CREATE_TRANSLATION = 79;
enum SQL_DIAG_CREATE_VIEW = 84;
enum SQL_DIAG_DELETE_WHERE = 19;
enum SQL_DIAG_DROP_ASSERTION = 24;
enum SQL_DIAG_DROP_CHARACTER_SET = 25;
enum SQL_DIAG_DROP_COLLATION = 26;
enum SQL_DIAG_DROP_DOMAIN = 27;
enum SQL_DIAG_DROP_INDEX = -2;
enum SQL_DIAG_DROP_SCHEMA = 31;
enum SQL_DIAG_DROP_TABLE = 32;
enum SQL_DIAG_DROP_TRANSLATION = 33;
enum SQL_DIAG_DROP_VIEW = 36;
enum SQL_DIAG_DYNAMIC_DELETE_CURSOR = 38;
enum SQL_DIAG_DYNAMIC_UPDATE_CURSOR = 81;
enum SQL_DIAG_GRANT = 48;
enum SQL_DIAG_INSERT = 50;
enum SQL_DIAG_REVOKE = 59;
enum SQL_DIAG_SELECT_CURSOR = 85;
enum SQL_DIAG_UNKNOWN_STATEMENT = 0;
enum SQL_DIAG_UPDATE_WHERE = 82;

/* SQL data type codes */
enum SQL_UNKNOWN_TYPE = 0;
enum SQL_CHAR = 1;
enum SQL_NUMERIC = 2;
enum SQL_DECIMAL = 3;
enum SQL_INTEGER = 4;
enum SQL_SMALLINT = 5;
enum SQL_FLOAT = 6;
enum SQL_REAL = 7;
enum SQL_DOUBLE = 8;
enum SQL_DATETIME = 9;
enum SQL_VARCHAR = 12;

/* One-parameter shortcuts for date/time data types */
enum SQL_TYPE_DATE = 91;
enum SQL_TYPE_TIME = 92;
enum SQL_TYPE_TIMESTAMP = 93;

/* Statement attribute values for cursor sensitivity */
enum SQL_UNSPECIFIED = 0;
enum SQL_INSENSITIVE = 1;
enum SQL_SENSITIVE = 2;

/* GetTypeInfo() request for all data types */
enum SQL_ALL_TYPES = 0;

/* Default conversion code for SQLBindCol(), SQLBindParam() and SQLGetData() */
enum SQL_DEFAULT = 99;

/* SQLSQLLEN GetData() code indicating that the application row descriptor
 * specifies the data type
 */
enum SQL_ARD_TYPE = -99;

enum SQL_APD_TYPE = -100;

/* SQL date/time type subcodes */
enum SQL_CODE_DATE = 1;
enum SQL_CODE_TIME = 2;
enum SQL_CODE_TIMESTAMP = 3;

/* CLI option values */
enum SQL_FALSE = 0;
enum SQL_TRUE = 1;

/* values of NULLABLE field in descriptor */
enum SQL_NO_NULLS = 0;
enum SQL_NULLABLE = 1;

/* Value returned by SQLGetTypeInfo() to denote that it is
 * not known whether or not a data type supports null values.
 */
enum SQL_NULLABLE_UNKNOWN = 2;

/* Values returned by SQLGetTypeInfo() to show WHERE clause
 * supported
 */
enum SQL_PRED_NONE = 0;
enum SQL_PRED_CHAR = 1;
enum SQL_PRED_BASIC = 2;

/* values of UNNAMED field in descriptor */
enum SQL_NAMED = 0;
enum SQL_UNNAMED = 1;

/* values of ALLOC_TYPE field in descriptor */
enum SQL_DESC_ALLOC_AUTO = 1;
enum SQL_DESC_ALLOC_USER = 2;

/* FreeStmt() options */
enum SQL_CLOSE = 0;
enum SQL_DROP = 1;
enum SQL_UNBIND = 2;
enum SQL_RESET_PARAMS = 3;

/* Codes used for FetchOrientation in SQLFetchScroll(),
   and in SQLDataSources()
*/
enum SQL_FETCH_NEXT = 1;
enum SQL_FETCH_FIRST = 2;

/* Other codes used for FetchOrientation in SQLFetchScroll() */
enum SQL_FETCH_LAST = 3;
enum SQL_FETCH_PRIOR = 4;
enum SQL_FETCH_ABSOLUTE = 5;
enum SQL_FETCH_RELATIVE = 6;

/* SQLEndTran() options */
enum SQL_COMMIT = 0;
enum SQL_ROLLBACK = 1;

/* null handles returned by SQLAllocHandle() */
enum SQL_NULL_HENV = 0;
enum SQL_NULL_HDBC = 0;
enum SQL_NULL_HSTMT = 0;
enum SQL_NULL_HDESC = 0;

/* null handle used in place of parent handle when allocating HENV */
enum SQL_NULL_HANDLE = 0L;

/* Values that may appear in the result set of SQLSpecialColumns() */
enum SQL_SCOPE_CURROW = 0;
enum SQL_SCOPE_TRANSACTION = 1;
enum SQL_SCOPE_SESSION = 2;

enum SQL_PC_UNKNOWN = 0;
enum SQL_PC_NON_PSEUDO = 1;
enum SQL_PC_PSEUDO = 2;

/* Reserved value for the IdentifierType argument of SQLSpecialColumns() */
enum SQL_ROW_IDENTIFIER = 1;

/* Reserved values for UNIQUE argument of SQLStatistics() */
enum SQL_INDEX_UNIQUE = 0;
enum SQL_INDEX_ALL = 1;

/* Values that may appear in the result set of SQLStatistics() */
enum SQL_INDEX_CLUSTERED = 1;
enum SQL_INDEX_HASHED = 2;
enum SQL_INDEX_OTHER = 3;

/* SQLGetFunctions() values to identify ODBC APIs */
enum SQL_API_SQLALLOCCONNECT = 1;
enum SQL_API_SQLALLOCENV = 2;
enum SQL_API_SQLALLOCHANDLE = 1001;

enum SQL_API_SQLALLOCSTMT = 3;
enum SQL_API_SQLBINDCOL = 4;
enum SQL_API_SQLBINDPARAM = 1002;

enum SQL_API_SQLCANCEL = 5;
enum SQL_API_SQLCLOSECURSOR = 1003;
enum SQL_API_SQLCOLATTRIBUTE = 6;

enum SQL_API_SQLCOLUMNS = 40;
enum SQL_API_SQLCONNECT = 7;
enum SQL_API_SQLCOPYDESC = 1004;

enum SQL_API_SQLDATASOURCES = 57;
enum SQL_API_SQLDESCRIBECOL = 8;
enum SQL_API_SQLDISCONNECT = 9;
enum SQL_API_SQLENDTRAN = 1005;

enum SQL_API_SQLERROR = 10;
enum SQL_API_SQLEXECDIRECT = 11;
enum SQL_API_SQLEXECUTE = 12;
enum SQL_API_SQLFETCH = 13;
enum SQL_API_SQLFETCHSCROLL = 1021;

enum SQL_API_SQLFREECONNECT = 14;
enum SQL_API_SQLFREEENV = 15;
enum SQL_API_SQLFREEHANDLE = 1006;

enum SQL_API_SQLFREESTMT = 16;
enum SQL_API_SQLGETCONNECTATTR = 1007;

enum SQL_API_SQLGETCONNECTOPTION = 42;
enum SQL_API_SQLGETCURSORNAME = 17;
enum SQL_API_SQLGETDATA = 43;
enum SQL_API_SQLGETDESCFIELD = 1008;
enum SQL_API_SQLGETDESCREC = 1009;
enum SQL_API_SQLGETDIAGFIELD = 1010;
enum SQL_API_SQLGETDIAGREC = 1011;
enum SQL_API_SQLGETENVATTR = 1012;

enum SQL_API_SQLGETFUNCTIONS = 44;
enum SQL_API_SQLGETINFO = 45;
enum SQL_API_SQLGETSTMTATTR = 1014;

enum SQL_API_SQLGETSTMTOPTION = 46;
enum SQL_API_SQLGETTYPEINFO = 47;
enum SQL_API_SQLNUMRESULTCOLS = 18;
enum SQL_API_SQLPARAMDATA = 48;
enum SQL_API_SQLPREPARE = 19;
enum SQL_API_SQLPUTDATA = 49;
enum SQL_API_SQLROWCOUNT = 20;
enum SQL_API_SQLSETCONNECTATTR = 1016;

enum SQL_API_SQLSETCONNECTOPTION = 50;
enum SQL_API_SQLSETCURSORNAME = 21;
enum SQL_API_SQLSETDESCFIELD = 1017;
enum SQL_API_SQLSETDESCREC = 1018;
enum SQL_API_SQLSETENVATTR = 1019;

enum SQL_API_SQLSETPARAM = 22;
enum SQL_API_SQLSETSTMTATTR = 1020;

enum SQL_API_SQLSETSTMTOPTION = 51;
enum SQL_API_SQLSPECIALCOLUMNS = 52;
enum SQL_API_SQLSTATISTICS = 53;
enum SQL_API_SQLTABLES = 54;
enum SQL_API_SQLTRANSACT = 23;
enum SQL_API_SQLCANCELHANDLE = 1550;
enum SQL_API_SQLCOMPLETEASYNC = 1551;

/* Information requested by SQLGetInfo() */
enum SQL_MAX_DRIVER_CONNECTIONS = 0;
enum SQL_MAXIMUM_DRIVER_CONNECTIONS = SQL_MAX_DRIVER_CONNECTIONS;
enum SQL_MAX_CONCURRENT_ACTIVITIES = 1;
enum SQL_MAXIMUM_CONCURRENT_ACTIVITIES = SQL_MAX_CONCURRENT_ACTIVITIES;

enum SQL_DATA_SOURCE_NAME = 2;
enum SQL_FETCH_DIRECTION = 8;
enum SQL_SERVER_NAME = 13;
enum SQL_SEARCH_PATTERN_ESCAPE = 14;
enum SQL_DBMS_NAME = 17;
enum SQL_DBMS_VER = 18;
enum SQL_ACCESSIBLE_TABLES = 19;
enum SQL_ACCESSIBLE_PROCEDURES = 20;
enum SQL_CURSOR_COMMIT_BEHAVIOR = 23;
enum SQL_DATA_SOURCE_READ_ONLY = 25;
enum SQL_DEFAULT_TXN_ISOLATION = 26;
enum SQL_IDENTIFIER_CASE = 28;
enum SQL_IDENTIFIER_QUOTE_CHAR = 29;
enum SQL_MAX_COLUMN_NAME_LEN = 30;
enum SQL_MAXIMUM_COLUMN_NAME_LENGTH = SQL_MAX_COLUMN_NAME_LEN;
enum SQL_MAX_CURSOR_NAME_LEN = 31;
enum SQL_MAXIMUM_CURSOR_NAME_LENGTH = SQL_MAX_CURSOR_NAME_LEN;
enum SQL_MAX_SCHEMA_NAME_LEN = 32;
enum SQL_MAXIMUM_SCHEMA_NAME_LENGTH = SQL_MAX_SCHEMA_NAME_LEN;
enum SQL_MAX_CATALOG_NAME_LEN = 34;
enum SQL_MAXIMUM_CATALOG_NAME_LENGTH = SQL_MAX_CATALOG_NAME_LEN;
enum SQL_MAX_TABLE_NAME_LEN = 35;
enum SQL_SCROLL_CONCURRENCY = 43;
enum SQL_TXN_CAPABLE = 46;
enum SQL_TRANSACTION_CAPABLE = SQL_TXN_CAPABLE;
enum SQL_USER_NAME = 47;
enum SQL_TXN_ISOLATION_OPTION = 72;
enum SQL_TRANSACTION_ISOLATION_OPTION = SQL_TXN_ISOLATION_OPTION;
enum SQL_INTEGRITY = 73;
enum SQL_GETDATA_EXTENSIONS = 81;
enum SQL_NULL_COLLATION = 85;
enum SQL_ALTER_TABLE = 86;
enum SQL_ORDER_BY_COLUMNS_IN_SELECT = 90;
enum SQL_SPECIAL_CHARACTERS = 94;
enum SQL_MAX_COLUMNS_IN_GROUP_BY = 97;
enum SQL_MAXIMUM_COLUMNS_IN_GROUP_BY = SQL_MAX_COLUMNS_IN_GROUP_BY;
enum SQL_MAX_COLUMNS_IN_INDEX = 98;
enum SQL_MAXIMUM_COLUMNS_IN_INDEX = SQL_MAX_COLUMNS_IN_INDEX;
enum SQL_MAX_COLUMNS_IN_ORDER_BY = 99;
enum SQL_MAXIMUM_COLUMNS_IN_ORDER_BY = SQL_MAX_COLUMNS_IN_ORDER_BY;
enum SQL_MAX_COLUMNS_IN_SELECT = 100;
enum SQL_MAXIMUM_COLUMNS_IN_SELECT = SQL_MAX_COLUMNS_IN_SELECT;
enum SQL_MAX_COLUMNS_IN_TABLE = 101;
enum SQL_MAX_INDEX_SIZE = 102;
enum SQL_MAXIMUM_INDEX_SIZE = SQL_MAX_INDEX_SIZE;
enum SQL_MAX_ROW_SIZE = 104;
enum SQL_MAXIMUM_ROW_SIZE = SQL_MAX_ROW_SIZE;
enum SQL_MAX_STATEMENT_LEN = 105;
enum SQL_MAXIMUM_STATEMENT_LENGTH = SQL_MAX_STATEMENT_LEN;
enum SQL_MAX_TABLES_IN_SELECT = 106;
enum SQL_MAXIMUM_TABLES_IN_SELECT = SQL_MAX_TABLES_IN_SELECT;
enum SQL_MAX_USER_NAME_LEN = 107;
enum SQL_MAXIMUM_USER_NAME_LENGTH = SQL_MAX_USER_NAME_LEN;
enum SQL_OJ_CAPABILITIES = 115;
enum SQL_OUTER_JOIN_CAPABILITIES = SQL_OJ_CAPABILITIES;

enum SQL_XOPEN_CLI_YEAR = 10000;
enum SQL_CURSOR_SENSITIVITY = 10001;
enum SQL_DESCRIBE_PARAMETER = 10002;
enum SQL_CATALOG_NAME = 10003;
enum SQL_COLLATION_SEQ = 10004;
enum SQL_MAX_IDENTIFIER_LEN = 10005;
enum SQL_MAXIMUM_IDENTIFIER_LENGTH = SQL_MAX_IDENTIFIER_LEN;

/* SQL_ALTER_TABLE bitmasks */
enum SQL_AT_ADD_COLUMN = 0x00000001L;
enum SQL_AT_DROP_COLUMN = 0x00000002L;

enum SQL_AT_ADD_CONSTRAINT = 0x00000008L;

/* The following bitmasks are ODBC extensions and defined in sqlext.h
*#define    SQL_AT_COLUMN_SINGLE                    0x00000020L
*#define    SQL_AT_ADD_COLUMN_DEFAULT               0x00000040L
*#define    SQL_AT_ADD_COLUMN_COLLATION             0x00000080L
*#define    SQL_AT_SET_COLUMN_DEFAULT               0x00000100L
*#define    SQL_AT_DROP_COLUMN_DEFAULT              0x00000200L
*#define    SQL_AT_DROP_COLUMN_CASCADE              0x00000400L
*#define    SQL_AT_DROP_COLUMN_RESTRICT             0x00000800L
*#define SQL_AT_ADD_TABLE_CONSTRAINT                0x00001000L
*#define SQL_AT_DROP_TABLE_CONSTRAINT_CASCADE       0x00002000L
*#define SQL_AT_DROP_TABLE_CONSTRAINT_RESTRICT      0x00004000L
*#define SQL_AT_CONSTRAINT_NAME_DEFINITION          0x00008000L
*#define SQL_AT_CONSTRAINT_INITIALLY_DEFERRED       0x00010000L
*#define SQL_AT_CONSTRAINT_INITIALLY_IMMEDIATE      0x00020000L
*#define SQL_AT_CONSTRAINT_DEFERRABLE               0x00040000L
*#define SQL_AT_CONSTRAINT_NON_DEFERRABLE           0x00080000L
*/

/* SQL_ASYNC_MODE values */
enum SQL_AM_NONE = 0;
enum SQL_AM_CONNECTION = 1;
enum SQL_AM_STATEMENT = 2;

/* SQL_CURSOR_COMMIT_BEHAVIOR values */
enum SQL_CB_DELETE = 0;
enum SQL_CB_CLOSE = 1;
enum SQL_CB_PRESERVE = 2;

/* SQL_FETCH_DIRECTION bitmasks */
enum SQL_FD_FETCH_NEXT = 0x00000001L;
enum SQL_FD_FETCH_FIRST = 0x00000002L;
enum SQL_FD_FETCH_LAST = 0x00000004L;
enum SQL_FD_FETCH_PRIOR = 0x00000008L;
enum SQL_FD_FETCH_ABSOLUTE = 0x00000010L;
enum SQL_FD_FETCH_RELATIVE = 0x00000020L;

/* SQL_GETDATA_EXTENSIONS bitmasks */
enum SQL_GD_ANY_COLUMN = 0x00000001L;
enum SQL_GD_ANY_ORDER = 0x00000002L;

/* SQL_IDENTIFIER_CASE values */
enum SQL_IC_UPPER = 1;
enum SQL_IC_LOWER = 2;
enum SQL_IC_SENSITIVE = 3;
enum SQL_IC_MIXED = 4;

/* SQL_OJ_CAPABILITIES bitmasks */
/* NB: this means 'outer join', not what  you may be thinking */

enum SQL_OJ_LEFT = 0x00000001L;
enum SQL_OJ_RIGHT = 0x00000002L;
enum SQL_OJ_FULL = 0x00000004L;
enum SQL_OJ_NESTED = 0x00000008L;
enum SQL_OJ_NOT_ORDERED = 0x00000010L;
enum SQL_OJ_INNER = 0x00000020L;
enum SQL_OJ_ALL_COMPARISON_OPS = 0x00000040L;

/* SQL_SCROLL_CONCURRENCY bitmasks */
enum SQL_SCCO_READ_ONLY = 0x00000001L;
enum SQL_SCCO_LOCK = 0x00000002L;
enum SQL_SCCO_OPT_ROWVER = 0x00000004L;
enum SQL_SCCO_OPT_VALUES = 0x00000008L;

/* SQL_TXN_CAPABLE values */
enum SQL_TC_NONE = 0;
enum SQL_TC_DML = 1;
enum SQL_TC_ALL = 2;
enum SQL_TC_DDL_COMMIT = 3;
enum SQL_TC_DDL_IGNORE = 4;

/* SQL_TXN_ISOLATION_OPTION bitmasks */
enum SQL_TXN_READ_UNCOMMITTED = 0x00000001L;
enum SQL_TRANSACTION_READ_UNCOMMITTED = SQL_TXN_READ_UNCOMMITTED;
enum SQL_TXN_READ_COMMITTED = 0x00000002L;
enum SQL_TRANSACTION_READ_COMMITTED = SQL_TXN_READ_COMMITTED;
enum SQL_TXN_REPEATABLE_READ = 0x00000004L;
enum SQL_TRANSACTION_REPEATABLE_READ = SQL_TXN_REPEATABLE_READ;
enum SQL_TXN_SERIALIZABLE = 0x00000008L;
enum SQL_TRANSACTION_SERIALIZABLE = SQL_TXN_SERIALIZABLE;
enum SQL_TXN_SS_SNAPSHOT = 0x00000020L; // sqlncli.h

/* SQL_NULL_COLLATION values */
enum SQL_NC_HIGH = 0;
enum SQL_NC_LOW = 1;

SQLRETURN SQLAllocConnect (
    SQLHENV EnvironmentHandle,
    SQLHDBC* ConnectionHandle);

SQLRETURN SQLAllocEnv (SQLHENV* EnvironmentHandle);

SQLRETURN SQLAllocHandle (
    SQLSMALLINT HandleType,
    SQLHANDLE InputHandle,
    SQLHANDLE* OutputHandle);

SQLRETURN SQLAllocStmt (SQLHDBC ConnectionHandle, SQLHSTMT* StatementHandle);

SQLRETURN SQLBindCol (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT ColumnNumber,
    SQLSMALLINT TargetType,
    SQLPOINTER TargetValue,
    SQLLEN BufferLength,
    SQLLEN* StrLen_or_Ind);

deprecated("Please use SQLBindParameter instead.")
SQLRETURN SQLBindParam (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT ParameterNumber,
    SQLSMALLINT ValueType,
    SQLSMALLINT ParameterType,
    SQLULEN LengthPrecision,
    SQLSMALLINT ParameterScale,
    SQLPOINTER ParameterValue,
    SQLLEN* StrLen_or_Ind);

SQLRETURN SQLCancel (SQLHSTMT StatementHandle);

SQLRETURN SQLCancelHandle (SQLSMALLINT HandleType, SQLHANDLE InputHandle);

SQLRETURN SQLCloseCursor (SQLHSTMT StatementHandle);

version (Win64)
    alias NumericAttributePtr = SQLLEN*;
else
    alias NumericAttributePtr = SQLPOINTER;
SQLRETURN SQLColAttribute (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT ColumnNumber,
    SQLUSMALLINT FieldIdentifier,
    SQLPOINTER CharacterAttribute,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* StringLength,
    NumericAttributePtr NumericAttribute);

SQLRETURN SQLColumns (
    SQLHSTMT StatementHandle,
    SQLCHAR* CatalogName,
    SQLSMALLINT NameLength1,
    SQLCHAR* SchemaName,
    SQLSMALLINT NameLength2,
    SQLCHAR* TableName,
    SQLSMALLINT NameLength3,
    SQLCHAR* ColumnName,
    SQLSMALLINT NameLength4);

SQLRETURN SQLCompleteAsync (
    SQLSMALLINT HandleType,
    SQLHANDLE Handle,
    RETCODE* AsyncRetCodePtr);

SQLRETURN SQLConnect (
    SQLHDBC ConnectionHandle,
    SQLCHAR* ServerName,
    SQLSMALLINT NameLength1,
    SQLCHAR* UserName,
    SQLSMALLINT NameLength2,
    SQLCHAR* Authentication,
    SQLSMALLINT NameLength3);

SQLRETURN SQLCopyDesc (SQLHDESC SourceDescHandle, SQLHDESC TargetDescHandle);

SQLRETURN SQLDataSources (
    SQLHENV EnvironmentHandle,
    SQLUSMALLINT Direction,
    SQLCHAR* ServerName,
    SQLSMALLINT BufferLength1,
    SQLSMALLINT* NameLength1Ptr,
    SQLCHAR* Description,
    SQLSMALLINT BufferLength2,
    SQLSMALLINT* NameLength2Ptr);

SQLRETURN SQLDescribeCol (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT ColumnNumber,
    SQLCHAR* ColumnName,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* NameLength,
    SQLSMALLINT* DataType,
    SQLULEN* ColumnSize,
    SQLSMALLINT* DecimalDigits,
    SQLSMALLINT* Nullable);

SQLRETURN SQLDisconnect (SQLHDBC ConnectionHandle);

SQLRETURN SQLEndTran (
    SQLSMALLINT HandleType,
    SQLHANDLE Handle,
    SQLSMALLINT CompletionType);

SQLRETURN SQLError (
    SQLHENV EnvironmentHandle,
    SQLHDBC ConnectionHandle,
    SQLHSTMT StatementHandle,
    SQLCHAR* Sqlstate,
    SQLINTEGER* NativeError,
    SQLCHAR* MessageText,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* TextLength);

SQLRETURN SQLExecDirect (
    SQLHSTMT StatementHandle,
    SQLCHAR* StatementText,
    SQLINTEGER TextLength);

SQLRETURN SQLExecute (SQLHSTMT StatementHandle);

SQLRETURN SQLFetch (SQLHSTMT StatementHandle);

SQLRETURN SQLFetchScroll (
    SQLHSTMT StatementHandle,
    SQLSMALLINT FetchOrientation,
    SQLLEN FetchOffset);

SQLRETURN SQLFreeConnect (SQLHDBC ConnectionHandle);

SQLRETURN SQLFreeEnv (SQLHENV EnvironmentHandle);

SQLRETURN SQLFreeHandle (SQLSMALLINT HandleType, SQLHANDLE Handle);

SQLRETURN SQLFreeStmt (SQLHSTMT StatementHandle, SQLUSMALLINT Option);

SQLRETURN SQLGetConnectAttr (
    SQLHDBC ConnectionHandle,
    SQLINTEGER Attribute,
    SQLPOINTER Value,
    SQLINTEGER BufferLength,
    SQLINTEGER* StringLengthPtr);

deprecated("Please use SQLGetConnectAttr instead.")
SQLRETURN SQLGetConnectOption (
    SQLHDBC ConnectionHandle,
    SQLUSMALLINT Option,
    SQLPOINTER Value);

SQLRETURN SQLGetCursorName (
    SQLHSTMT StatementHandle,
    SQLCHAR* CursorName,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* NameLengthPtr);

SQLRETURN SQLGetData (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT ColumnNumber,
    SQLSMALLINT TargetType,
    SQLPOINTER TargetValue,
    SQLLEN BufferLength,
    SQLLEN* StrLen_or_IndPtr);

SQLRETURN SQLGetDescField (
    SQLHDESC DescriptorHandle,
    SQLSMALLINT RecNumber,
    SQLSMALLINT FieldIdentifier,
    SQLPOINTER Value,
    SQLINTEGER BufferLength,
    SQLINTEGER* StringLength);

SQLRETURN SQLGetDescRec (
    SQLHDESC DescriptorHandle,
    SQLSMALLINT RecNumber,
    SQLCHAR* Name,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* StringLengthPtr,
    SQLSMALLINT* TypePtr,
    SQLSMALLINT* SubTypePtr,
    SQLLEN* LengthPtr,
    SQLSMALLINT* PrecisionPtr,
    SQLSMALLINT* ScalePtr,
    SQLSMALLINT* NullablePtr);

SQLRETURN SQLGetDiagField (
    SQLSMALLINT HandleType,
    SQLHANDLE Handle,
    SQLSMALLINT RecNumber,
    SQLSMALLINT DiagIdentifier,
    SQLPOINTER DiagInfo,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* StringLength);

SQLRETURN SQLGetDiagRec (
    SQLSMALLINT HandleType,
    SQLHANDLE Handle,
    SQLSMALLINT RecNumber,
    SQLCHAR* Sqlstate,
    SQLINTEGER* NativeError,
    SQLCHAR* MessageText,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* TextLength);

SQLRETURN SQLGetEnvAttr (
    SQLHENV EnvironmentHandle,
    SQLINTEGER Attribute,
    SQLPOINTER Value,
    SQLINTEGER BufferLength,
    SQLINTEGER* StringLength);

SQLRETURN SQLGetFunctions (
    SQLHDBC ConnectionHandle,
    SQLUSMALLINT FunctionId,
    SQLUSMALLINT* Supported);

//_Success_(return == SQL_SUCCESS)
SQLRETURN SQLGetInfo (
    SQLHDBC ConnectionHandle,
    SQLUSMALLINT InfoType,
    SQLPOINTER InfoValue,
    SQLSMALLINT BufferLength,
    SQLSMALLINT* StringLengthPtr);

SQLRETURN SQLGetStmtAttr (
    SQLHSTMT StatementHandle,
    SQLINTEGER Attribute,
    SQLPOINTER Value,
    SQLINTEGER BufferLength,
    SQLINTEGER* StringLength);

deprecated("Please use SQLGetStmtAttr instead.")
SQLRETURN SQLGetStmtOption (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT Option,
    SQLPOINTER Value);

SQLRETURN SQLGetTypeInfo (SQLHSTMT StatementHandle, SQLSMALLINT DataType);

SQLRETURN SQLNumResultCols (SQLHSTMT StatementHandle, SQLSMALLINT* ColumnCount);

SQLRETURN SQLParamData (SQLHSTMT StatementHandle, SQLPOINTER* Value);

SQLRETURN SQLPrepare (
    SQLHSTMT StatementHandle,
    SQLCHAR* StatementText,
    SQLINTEGER TextLength);

SQLRETURN SQLPutData (
    SQLHSTMT StatementHandle,
    SQLPOINTER Data,
    SQLLEN StrLen_or_Ind);

SQLRETURN SQLRowCount (SQLHSTMT StatementHandle, SQLLEN* RowCount);

SQLRETURN SQLSetConnectAttr (
    SQLHDBC ConnectionHandle,
    SQLINTEGER Attribute,
    SQLPOINTER Value,
    SQLINTEGER StringLength);

deprecated("Please use SQLSetConnectAttr instead.")
SQLRETURN SQLSetConnectOption (
    SQLHDBC ConnectionHandle,
    SQLUSMALLINT Option,
    SQLULEN Value);

SQLRETURN SQLSetCursorName (
    SQLHSTMT StatementHandle,
    SQLCHAR* CursorName,
    SQLSMALLINT NameLength);

SQLRETURN SQLSetDescField (
    SQLHDESC DescriptorHandle,
    SQLSMALLINT RecNumber,
    SQLSMALLINT FieldIdentifier,
    SQLPOINTER Value,
    SQLINTEGER BufferLength);

SQLRETURN SQLSetDescRec (
    SQLHDESC DescriptorHandle,
    SQLSMALLINT RecNumber,
    SQLSMALLINT Type,
    SQLSMALLINT SubType,
    SQLLEN Length,
    SQLSMALLINT Precision,
    SQLSMALLINT Scale,
    SQLPOINTER Data,
    SQLLEN* StringLength,
    SQLLEN* Indicator);

SQLRETURN SQLSetEnvAttr (
    SQLHENV EnvironmentHandle,
    SQLINTEGER Attribute,
    SQLPOINTER Value,
    SQLINTEGER StringLength);

deprecated("Please use SQLBindParameter instead.")
SQLRETURN SQLSetParam (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT ParameterNumber,
    SQLSMALLINT ValueType,
    SQLSMALLINT ParameterType,
    SQLULEN LengthPrecision,
    SQLSMALLINT ParameterScale,
    SQLPOINTER ParameterValue,
    SQLLEN* StrLen_or_Ind);

SQLRETURN SQLSetStmtAttr (
    SQLHSTMT StatementHandle,
    SQLINTEGER Attribute,
    SQLPOINTER Value,
    SQLINTEGER StringLength);

deprecated("Please use SQLSetStmtAttr instead.")
SQLRETURN SQLSetStmtOption (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT Option,
    SQLULEN Value);

SQLRETURN SQLSpecialColumns (
    SQLHSTMT StatementHandle,
    SQLUSMALLINT IdentifierType,
    SQLCHAR* CatalogName,
    SQLSMALLINT NameLength1,
    SQLCHAR* SchemaName,
    SQLSMALLINT NameLength2,
    SQLCHAR* TableName,
    SQLSMALLINT NameLength3,
    SQLUSMALLINT Scope,
    SQLUSMALLINT Nullable);

SQLRETURN SQLStatistics (
    SQLHSTMT StatementHandle,
    SQLCHAR* CatalogName,
    SQLSMALLINT NameLength1,
    SQLCHAR* SchemaName,
    SQLSMALLINT NameLength2,
    SQLCHAR* TableName,
    SQLSMALLINT NameLength3,
    SQLUSMALLINT Unique,
    SQLUSMALLINT Reserved);

SQLRETURN SQLTables (
    SQLHSTMT StatementHandle,
    SQLCHAR* CatalogName,
    SQLSMALLINT NameLength1,
    SQLCHAR* SchemaName,
    SQLSMALLINT NameLength2,
    SQLCHAR* TableName,
    SQLSMALLINT NameLength3,
    SQLCHAR* TableType,
    SQLSMALLINT NameLength4);

SQLRETURN SQLTransact (
    SQLHENV EnvironmentHandle,
    SQLHDBC ConnectionHandle,
    SQLUSMALLINT CompletionType);
