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

module pham.db.myoid;

struct MyCharSet
{
nothrow @safe:

    string name;
    string collation;
    int id;
}

immutable MyCharSet[] myCharSet = [
    {name:"utf8", collation:"utf8_general_ci", id:33},
    {name:"utf8mb4", collation:"utf8mb4_0900_ai_ci", id:255}
];

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

enum MyTypeId : int
{
    decimal = 0, /// A fixed precision and scale numeric value between -1_038 -1 and 10 38 -1
    byte_ = 1, /// The signed range is -128 to 127. The unsigned range is 0 to 255
    int16 = 2, /// A 16-bit signed integer. The signed range is  -32_768 to 32_767. The unsigned range is 0 to 65_535
    int24 = 9, /// Specifies a 24 (3 byte) signed or unsigned value
    int32 = 3, /// A 32-bit signed integer
    int64 = 8, /// A 64-bit signed integer
    float_ = 4,  /// A small (single-precision) floating-point number. Allowable values are -3.402823466E+38 to -1.175494351E-38,
                /// 0, and 1.175494351E-38 to 3.402823466E+38
    double_ = 5, /// A normal-size (double-precision) floating-point number. Allowable values are -1.7976931348623157E+308 to -2.2250738585072014E-308,
                /// 0, and 2.2250738585072014E-308 to 1.7976931348623157E+308
    timestamp = 7, /// A timestamp. The range is '1970-01-01 00:00:00' to sometime in the year 2037
    date = 10, /// Date The supported range is '1000-01-01' to '9999-12-31'
    time = 11, /// Time <para>The range is '-838:59:59' to '838:59:59'
    dateTime = 12, /// DateTime The supported range is '1000-01-01 00:00:00' to '9999-12-31 23:59:59'
    year = 13,  /// A year in 2- or 4-digit format (default is 4-digit).
                /// The allowable values are 1901 to 2155, 0000 in the 4-digit year
                /// format, and 1970-2069 if you use the 2-digit format (70-69)
    newDate = 14, /// Use Datetime or Date type - Obsolete
    varString = 15, /// A variable-length string containing 0 to 65_535 characters
    bit = 16, /// Bit-field data type
    json = 245, /// JSON
    newDecimal = 246, /// New Decimal
    enum_ = 247, /// An enumeration. A string object that can have only one value,
                 /// chosen from the list of values 'value1', 'value2', ..., NULL
                 /// or the special "" error value. An ENUM can have a maximum of  65_535 distinct values
    set = 248,  /// A set. A string object that can have zero or more values, each
                /// of which must be chosen from the list of values 'value1', 'value2',
                /// ... A SET can have a maximum of 64 members.
    tinyBlob = 249, /// A binary column with a maximum length of 255 (2^8 - 1) characters
    mediumBlob = 250, /// A binary column with a maximum length of 16_777_215 (2^24 - 1) bytes
    longBlob = 251, /// A binary column with a maximum length of 4_294_967_295 or 4G (2^32 - 1) bytes
    blob = 252, /// A binary column with a maximum length of 65_535 (2^16 - 1) bytes
    varChar = 253, /// A variable-length string containing 0 to 255 bytes
    string = 254, /// A fixed-length string
    geometry = 255, /// Geometric (GIS) data type
    ubyte_ = 501, /// Unsigned 8-bit value
    uint16 = 502, /// Unsigned 16-bit value
    uint24 = 509, /// Unsigned 24-bit value
    uint32 = 503, /// Unsigned 32-bit value
    uint64 = 508, /// Unsigned 64-bit value
    binary = 754, /// Fixed length binary string
    varBinary = 753, /// Variable length binary string
    tinyText = 749, /// A text column with a maximum length of 255 (2^8 - 1) characters
    mediumText = 750, /// A text column with a maximum length of 16_777_215 (2^24 - 1) characters
    longText = 751, /// A text column with a maximum length of 4_294_967_295 or 4G (2^32 - 1) characters
    text = 752, /// A text column with a maximum length of 65_535 (2^16 - 1) characters
    guid = 854, /// A guid column
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
