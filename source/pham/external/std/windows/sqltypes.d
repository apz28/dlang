/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

//-----------------------------------------------------------------------------
// File:			sqltypes.h
//
// Contents: 		This file defines the types used in ODBC
//
// Comments:
//
//-----------------------------------------------------------------------------

module pham.external.std.windows.sqltypes;

version(Windows):
extern (Windows):
@nogc:
nothrow:

version(ANSI)
{
    version = Ansicode;
}
else
{
    version = Unicode;
}

public import core.sys.windows.basetyps : GUID;
public import core.sys.windows.windef : BYTE, BOOL, CHAR, DWORD, HANDLE, HWND, INT64, LPWSTR, PVOID, VOID, UINT64, WCHAR, WORD;

/*
 * ODBCVER  Default to ODBC version number (0x0380). To exclude
 *          definitions introduced in version 3.8 (or above)
 *          #define ODBCVER 0x0351 before #including <sql.h>
 */
enum ODBCVER = 0x0380;

/* generally useful constants */
enum SQL_SPEC_MAJOR = 3; /* Major version of specification  */
enum SQL_SPEC_MINOR = 80; /* Minor version of specification  */
enum SQL_SPEC_STRING = "03.80"; /* String constant for version */

/* environment specific definitions */

/* API declaration data types */
alias SQLCHAR = ubyte;
alias SQLSCHAR = byte;
alias SQLDATE = ubyte;
alias SQLDECIMAL = ubyte;
alias SQLDOUBLE = double;
alias SQLFLOAT = double;

alias SQLINTEGER = int;
alias SQLUINTEGER = uint;

version(Win64)
{
    alias SQLLEN = long;
    alias SQLULEN = ulong;
    alias SQLSETPOSIROW = ulong;
}
else
{
    alias SQLLEN = SQLINTEGER;
    alias SQLULEN = SQLUINTEGER;
    alias SQLSETPOSIROW = SQLUSMALLINT;
}

//For Backward compatibility
version(Win32)
{
    alias SQLROWCOUNT = SQLULEN;
    alias SQLROWSETSIZE = SQLULEN;
    alias SQLTRANSID = SQLULEN;
    alias SQLROWOFFSET = SQLLEN;
}

alias SQLNUMERIC = ubyte;
alias SQLPOINTER = void*;
alias SQLREAL = float;
alias SQLSMALLINT = short;
alias SQLUSMALLINT = ushort;
alias SQLTIME = ubyte;
alias SQLTIMESTAMP = ubyte;
alias SQLVARCHAR = ubyte;

/* function return type */
alias SQLRETURN = short;

/* generic data structures */
alias SQLHANDLE = void*;
alias SQLHENV = SQLHANDLE;
alias SQLHDBC = SQLHANDLE;
alias SQLHSTMT = SQLHANDLE;
alias SQLHDESC = SQLHANDLE;

/* SQL portable types for C */
alias UCHAR = ubyte;
alias SCHAR = byte;
alias SDWORD = int;
alias SWORD = short;
alias UDWORD = uint;
alias UWORD = ushort;

alias SLONG = int;
alias SSHORT = short;
alias ULONG = uint;
alias USHORT = ushort;
alias SDOUBLE = double;
alias LDOUBLE = double;
alias SFLOAT = float;

alias PTR = void*;

alias HENV = void*;
alias HDBC = void*;
alias HSTMT = void*;

alias RETCODE = short;

alias SQLHWND = HWND;

/* transfer types for DATE, TIME, TIMESTAMP */
struct tagDATE_STRUCT
{
    SQLSMALLINT year;
    SQLUSMALLINT month;
    SQLUSMALLINT day;
}

alias DATE_STRUCT = tagDATE_STRUCT;

alias SQL_DATE_STRUCT = tagDATE_STRUCT;

struct tagTIME_STRUCT
{
    SQLUSMALLINT hour;
    SQLUSMALLINT minute;
    SQLUSMALLINT second;
}

alias TIME_STRUCT = tagTIME_STRUCT;

alias SQL_TIME_STRUCT = tagTIME_STRUCT;

struct tagTIMESTAMP_STRUCT
{
    SQLSMALLINT year;
    SQLUSMALLINT month;
    SQLUSMALLINT day;
    SQLUSMALLINT hour;
    SQLUSMALLINT minute;
    SQLUSMALLINT second;
    SQLUINTEGER fraction;
}
//pragma(msg, tagTIMESTAMP_STRUCT.stringof ~ "." ~ tagTIMESTAMP_STRUCT.sizeof.stringof); // sizeof=16

alias TIMESTAMP_STRUCT = tagTIMESTAMP_STRUCT;

alias SQL_TIMESTAMP_STRUCT = tagTIMESTAMP_STRUCT;

/*
 * enumerations for DATETIME_INTERVAL_SUBCODE values for interval data types
 * these values are from SQL-92
 */

enum SQLINTERVAL
{
    SQL_IS_YEAR = 1,
    SQL_IS_MONTH = 2,
    SQL_IS_DAY = 3,
    SQL_IS_HOUR = 4,
    SQL_IS_MINUTE = 5,
    SQL_IS_SECOND = 6,
    SQL_IS_YEAR_TO_MONTH = 7,
    SQL_IS_DAY_TO_HOUR = 8,
    SQL_IS_DAY_TO_MINUTE = 9,
    SQL_IS_DAY_TO_SECOND = 10,
    SQL_IS_HOUR_TO_MINUTE = 11,
    SQL_IS_HOUR_TO_SECOND = 12,
    SQL_IS_MINUTE_TO_SECOND = 13
}

struct tagSQL_YEAR_MONTH
{
    SQLUINTEGER year;
    SQLUINTEGER month;
}

alias SQL_YEAR_MONTH_STRUCT = tagSQL_YEAR_MONTH;

struct tagSQL_DAY_SECOND
{
    SQLUINTEGER day;
    SQLUINTEGER hour;
    SQLUINTEGER minute;
    SQLUINTEGER second;
    SQLUINTEGER fraction;
}

alias SQL_DAY_SECOND_STRUCT = tagSQL_DAY_SECOND;

struct tagSQL_INTERVAL_STRUCT
{
    SQLINTERVAL interval_type;
    SQLSMALLINT interval_sign;

    union _Anonymous_0
    {
        SQL_YEAR_MONTH_STRUCT year_month;
        SQL_DAY_SECOND_STRUCT day_second;
    }

    _Anonymous_0 intval;
}

alias SQL_INTERVAL_STRUCT = tagSQL_INTERVAL_STRUCT;

/* the ODBC C types for SQL_C_SBIGINT and SQL_C_UBIGINT */

/* If using other compilers, define ODBCINT64 to the
	approriate 64 bit integer type */
alias ODBCINT64 = long;
alias SQLBIGINT = long;
alias SQLUBIGINT = ulong;

/* internal representation of numeric data type */
enum SQL_MAX_NUMERIC_LEN = 16;
struct tagSQL_NUMERIC_STRUCT
{
    SQLCHAR precision;
    SQLSCHAR scale;
    SQLCHAR sign; /* 1 if positive, 0 if negative */
    SQLCHAR[SQL_MAX_NUMERIC_LEN] val;
}
//pragma(msg, tagSQL_NUMERIC_STRUCT.stringof ~ "." ~ tagSQL_NUMERIC_STRUCT.sizeof.stringof); // sizeof=19

alias SQL_NUMERIC_STRUCT = tagSQL_NUMERIC_STRUCT;

/* size is 16 */
struct tagSQLGUID
{
    DWORD Data1;
    WORD Data2;
    WORD Data3;
    BYTE[8] Data4;
}
//pragma(msg, tagSQLGUID.stringof ~ "." ~ tagSQLGUID.sizeof.stringof); // sizeof=16

alias SQLGUID = GUID;

alias BOOKMARK = SQLULEN;

alias SQLWCHAR = wchar;

version(Unicode)
    alias SQLTCHAR = SQLWCHAR;
else
    alias SQLTCHAR = SQLCHAR;

/* New Date Time Structures */
/* New Structure for TIME2 */
struct tagSS_TIME2_STRUCT
{
    SQLUSMALLINT   hour;
    SQLUSMALLINT   minute;
    SQLUSMALLINT   second;
    SQLUINTEGER    fraction;
}
//pragma(msg, tagSS_TIME2_STRUCT.stringof ~ "." ~ tagSS_TIME2_STRUCT.sizeof.stringof); // sizeof=12

alias SQL_SS_TIME2_STRUCT = tagSS_TIME2_STRUCT;

/* New Structure for TIMESTAMPOFFSET */
struct tagSS_TIMESTAMPOFFSET_STRUCT
{
    SQLSMALLINT    year;
    SQLUSMALLINT   month;
    SQLUSMALLINT   day;
    SQLUSMALLINT   hour;
    SQLUSMALLINT   minute;
    SQLUSMALLINT   second;
    SQLUINTEGER    fraction;
    SQLSMALLINT    timezone_hour;
    SQLSMALLINT    timezone_minute;
}
//pragma(msg, tagSS_TIMESTAMPOFFSET_STRUCT.stringof ~ "." ~ tagSS_TIMESTAMPOFFSET_STRUCT.sizeof.stringof); // sizeof=32

alias SQL_SS_TIMESTAMPOFFSET_STRUCT = tagSS_TIMESTAMPOFFSET_STRUCT;
