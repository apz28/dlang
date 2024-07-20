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

module pham.ser.ser_serialization_db;

import std.array : Appender, appender;
import std.conv : to;
import std.traits : isDynamicArray, isFloatingPoint, isIntegral;

debug(pham_ser_ser_serialization_db) import std.stdio : writeln;

import pham.db.db_database : DbCommand, DbFieldList, DbReader;
import pham.db.db_value : DbRowValue, DbValue;
import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimePattern;
import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
import pham.var.var_coerce;
import pham.var.var_coerce_dec_decimal;
import pham.var.var_coerce_pham_date_time;
import pham.var.var_variant;
import pham.ser.ser_serialization;

class DbDeserializer : Deserializer
{
@safe:

public:
    this(DbReader* reader) nothrow
    {
        this.reader = reader;
        this.fields = reader.fields;
    }

    override Deserializer begin()
    {
        currentCol = 0;
        currentRow = readRowReader();
        return super.begin();
    }

    override Deserializer end()
    {
        currentCol = currentRow = 0;
        return super.end();
    }

    override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(typeName=", typeName, ", memberDepth=", memberDepth, ")");

        currentCol = 0;
        super.aggregateBegin(typeName, attribute);
        return currentRow;
    }

    final override Null readNull(scope ref Serializable)
    {
        const i = popFront();
        assert(reader.isNull(i));
        return null;
    }

    final override bool readBool(scope ref Serializable)
    {
        return reader.getValue(popFront()).coerce!bool();
    }

    final override char readChar(scope ref Serializable attribute)
    {
        const s = readChars(attribute);
        assert(s.length == 1);
        return s.length ? s[0] : '\0';
    }

    final override Date readDate(scope ref Serializable)
    {
        return reader.getValue(popFront()).coerce!Date();
    }

    final override DateTime readDateTime(scope ref Serializable)
    {
        return reader.getValue(popFront()).coerce!DateTime();
    }

    final override Time readTime(scope ref Serializable)
    {
        return reader.getValue(popFront()).coerce!Time();
    }

    final override byte readByte(scope ref Serializable)
    {
        return reader.getValue(popFront()).coerce!byte();
    }

    final override short readShort(scope ref Serializable)
    {
        return reader.getValue(popFront()).coerce!short();
    }

    final override int readInt(scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        return reader.getValue(popFront()).coerce!int();
    }

    final override long readLong(scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        return reader.getValue(popFront()).coerce!long();
    }

    final override float readFloat(scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        return reader.getValue(popFront()).coerce!float();
    }

    final override double readDouble(scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        return reader.getValue(popFront()).coerce!double();
    }

    final override string readChars(scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        const i = popFront();
        return reader.isNull(i) ? null : reader.getValue(i).coerce!string();
    }

    final override wstring readWChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto chars = readChars(attribute, kind);
        return chars.length != 0 ? chars.to!wstring : null;
    }

    final override dstring readDChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto chars = readChars(attribute, kind);
        return chars.length != 0 ? chars.to!dstring : null;
    }

    final override const(char)[] readScopeChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        return readChars(attribute, kind);
    }

    final override ubyte[] readBytes(scope ref Serializable, const(DataKind) kind = DataKind.binary)
    {
        const i = popFront();
        return reader.isNull(i) ? null : reader.getValue(i).coerce!(ubyte[])();
    }

    final override const(ubyte)[] readScopeBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        return readBytes(attribute, kind);
    }

    final override string readKey(size_t)
    {
        return fields !is null ? fields[currentCol].name : null;
    }

public:
    final override bool hasArrayEle(size_t i, ptrdiff_t len)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(i=", i, ", len=", len,
            ", arrayDepth=", arrayDepth, ", currentRow=", currentRow, ")");

        if (i != 0 && currentRow != 0)
        {
            currentCol = 0;
            currentRow = readRowReader();
        }

        return currentRow != 0;
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len)
    {
        return len > 0 && len > i && currentRow != 0;
    }

    pragma(inline, true)
    final size_t popFront() nothrow
    {
        return currentCol++;
    }

    final size_t readRowReader()
    {
        return reader.read() ? reader.colCount : 0u;
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    DbReader* reader;
    DbFieldList fields;
    size_t currentCol, currentRow;
}

version(none)
class DbSerializer : Serializer
{
@safe:

public:
    override Serializer begin()
    {
        buffer = appender!string();
        buffer.reserve(bufferCapacity);
        return super.begin();
    }

    override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        if (length)
            buffer.put('}');
        else
            buffer.put("null");
        super.aggregateEnd(typeName, length, serializable);
    }

    final override Serializer aggregateItem(ptrdiff_t index, scope ref Serializable serializable)
    {
        if (index)
            buffer.put(',');
        else
            buffer.put('{');
        return super.aggregateItem(index, serializable);
    }

    override void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        buffer.put('[');
        super.arrayBegin(elemTypeName, length, serializable);
    }

    override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        buffer.put(']');
        super.arrayEnd(elemTypeName, length, serializable);
    }

    final override Serializer arrayItem(ptrdiff_t index)
    {
        if (index)
            buffer.put(',');
        return super.arrayItem(index);
    }

    final override void write(Null)
    {
        buffer.put("null");
    }

    static immutable string[2] boolValues = ["false", "true"];
    final override void writeBool(bool v)
    {
        buffer.put(boolValues[v]);
    }

    final override void writeChar(char v)
    {
        char[1] s = [v];
        write(s[]);
    }

    final override void write(scope const(Date) v)
    {
        StaticBuffer!(char, 50) text;
        buffer.put('"');
        buffer.put(v.toString(text, "%s")[]); // %s=yyyy-mm-dd
        buffer.put('"');
    }

    final override void write(scope const(DateTime) v)
    {
        StaticBuffer!(char, 50) text;
        const fmt = v.kind == DateTimeZoneKind.utc ? "%u" : "%s"; // %s=yyyy-mm-ddThh:nn:ss.zzzzzzz, %u=yyyy-mm-ddThh:nn:ss.zzzzzzzZ
        buffer.put('"');
        buffer.put(v.toString(text, fmt)[]);
        buffer.put('"');
    }

    final override void write(scope const(Time) v)
    {
        StaticBuffer!(char, 50) text;
        const fmt = v.kind == DateTimeZoneKind.utc ? "%u" : "%s"; // %s=hh:nn:ss.zzzzzzz, %u=hh:nn:ss.zzzzzzzZ
        buffer.put('"');
        buffer.put(v.toString(text, fmt)[]);
        buffer.put('"');
    }

    final override void write(byte v)
    {
        writeImpl(v);
    }

    final override void write(short v)
    {
        writeImpl(v);
    }

    final override void write(int v, const(DataKind) kind = DataKind.integral)
    {
        writeImpl(v);
    }

    final override void write(long v, const(DataKind) kind = DataKind.integral)
    {
        writeImpl(v);
    }

    final override void write(float v, const(FloatFormat) floatFormat, const(DataKind) kind = DataKind.decimal)
    {
        writeImpl(v, floatFormat);
    }

    final override void write(double v, const(FloatFormat) floatFormat, const(DataKind) kind = DataKind.decimal)
    {
        writeImpl(v, floatFormat);
    }

    final override void write(scope const(char)[] v, const(DataKind) kind = DataKind.character)
    {
        if (v is null)
        {
            buffer.put("null");
            return;
        }

        buffer.put('"');
        escapeString(buffer, v);
        buffer.put('"');
    }

    final override void write(scope const(wchar)[] v, const(DataKind) kind = DataKind.character)
    {
        if (v is null)
        {
            buffer.put("null");
            return;
        }

        auto v2 = v.to!string;
        buffer.put('"');
        escapeString(buffer, v2);
        buffer.put('"');
    }

    final override void write(scope const(dchar)[] v, const(DataKind) kind = DataKind.character)
    {
        if (v is null)
        {
            buffer.put("null");
            return;
        }

        auto v2 = v.to!string;
        buffer.put('"');
        escapeString(buffer, v2);
        buffer.put('"');
    }

    final override void write(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat, const(DataKind) kind = DataKind.binary)
    {
        if (v is null)
        {
            buffer.put("null");
            return;
        }

        buffer.put('"');
        buffer.put(binaryToString(v, binaryFormat));
        buffer.put('"');
    }

    final override Serializer writeKey(scope const(char)[] key)
    {
        buffer.put('"');
        escapeString(buffer, key);
        buffer.put('"');
        buffer.put(':');
        return this;
    }

    final override Serializer writeKeyId(scope const(char)[] key)
    {
        buffer.put('"');
        buffer.put(key);
        buffer.put('"');
        buffer.put(':');
        return this;
    }

public:
    static T escapeString(T)(return scope T s) nothrow pure
    if (isDynamicArray!T)
    {
        Appender!T buffer;
        buffer.reserve(s.length + (s.length / 4));
        escapeString(buffer, s);
        return buffer[];
    }

    static void escapeString(Writer, T)(scope ref Writer sink, scope T s)
    if (isDynamicArray!T)
    {
        size_t i;
        while (i < s.length && !isEscapedChar(s[i]))
            i++;
        if (i == s.length)
        {
            sink.put(s);
            return;
        }
        sink.put(s[0..i]);
        while (i < s.length)
        {
            const c = s[i];
            if (const cs = isEscapedChar(c))
            {
                sink.put('\\');
                sink.put(cs);
            }
            else
                sink.put(c);
            i++;
        }
    }

    // std.json is special handling as json string datatype - not as special number format
    final override const(char)[] floatLiteral(return scope char[] vBuffer, scope const(char)[] literal, const(bool) floatConversion) @nogc nothrow pure
    {
        if (floatConversion)
        {
            vBuffer[0] = '"';
            vBuffer[1..literal.length+1] = literal;
            vBuffer[literal.length+1] = '"';
            return vBuffer[0..literal.length+2];
        }

        return super.floatLiteral(vBuffer, literal, floatConversion);
    }

    // https://stackoverflow.com/questions/19176024/how-to-escape-special-characters-in-building-a-json-string
    static char isEscapedChar(const(char) c) @nogc nothrow pure
    {
        switch (c)
        {
            case '"': return '"';
            case '\\': return '\\';
            case '/': return '/';
            case '\b': return 'b';
            case '\f': return 'f';
            case '\n': return 'n';
            case '\r': return 'r';
            case '\t': return 't';
            default: return '\0';
        }
    }

    final void writeImpl(V)(V v)
    if (isIntegral!V)
    {
        char[50] vBuffer = void;
        buffer.put(intToString(vBuffer[], v));
    }

    final void writeImpl(V)(V v, const(FloatFormat) floatFormat)
    if (isFloatingPoint!V)
    {
        char[350] textBuffer = void;
        buffer.put(floatToString(textBuffer[], v, floatFormat));
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    Appender!string buffer;
    size_t bufferCapacity = 1_000 * 16;
}


private:

version(UnitTestFBDatabase)
{
    import pham.db.db_database : DbConnection, DbDatabaseList;
    import pham.db.db_type;
    import pham.db.db_fbdatabase;

    DbConnection createTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        DbCompressConnection compress = DbCompressConnection.disabled,
        DbIntegratedSecurityConnection integratedSecurity = DbIntegratedSecurityConnection.srp256)
    {
        auto db = DbDatabaseList.getDb(DbScheme.fb);
        auto result = db.createConnection("");
        auto csb = result.connectionStringBuilder;
        csb.databaseName = "UNIT_TEST";  // Use alias mapping name
        csb.receiveTimeout = dur!"seconds"(40);
        csb.sendTimeout = dur!"seconds"(20);
        csb.encrypt = encrypt;
        csb.compress = compress;
        csb.integratedSecurity = integratedSecurity;
        return result;
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestS1
{
    import std.conv : to;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestS1(publicInt INTEGER, publicGetSet INTEGER)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestS1");
    connection.executeNonQuery("INSERT INTO UnitTestS1(publicInt, publicGetSet)" ~
        " VALUES(20, 1)");

    version(none)
    {
        auto c = new UnitTestC2();
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestC2(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestC2, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestS1();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestS1(publicInt, publicGetSet) VALUES(21, 2)");
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1 ORDER BY publicInt");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestS1[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestAllTypesLess
{
    import std.conv : to;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestAllTypesLess(enum1 VARCHAR(20), bool1 BOOLEAN, byte1 SMALLINT" ~
        ", ubyte1 SMALLINT, short1 SMALLINT, ushort1 SMALLINT, int1 INTEGER, uint1 INTEGER" ~
        ", long1 BIGINT, ulong1 BIGINT, float1 FLOAT, double1 DOUBLE PRECISION" ~
        ", string1 VARCHAR(1000), charArray VARCHAR(1000), binary1 BLOB)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestAllTypesLess");
    connection.executeNonQuery("INSERT INTO UnitTestAllTypesLess(enum1, bool1, byte1" ~
        ", ubyte1, short1, ushort1, int1, uint1" ~
        ", long1, ulong1, float1, double1" ~
        ", string1, charArray, binary1)" ~
        " VALUES('third', true, 101" ~
        ", 0, -1003, 3975, -382653, 3957209" ~
        ", -394572364, 284659274, 6394763.5, -2846627456445.7651" ~
        ", 'test string of', 'will this work?', base64_decode('JRjMZSs='))");

    version(none)
    {
        auto c = new UnitTestAllTypesLess();
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestAllTypesLess(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestAllTypes, serializer.buffer[]);
    }

    // One class
    {
        auto reader = connection.executeReader("SELECT enum1, bool1, byte1, ubyte1, short1, ushort1, int1, uint1, long1, ulong1, float1, double1, string1, charArray, binary1 FROM UnitTestAllTypesLess");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestAllTypesLess();
        assert(c !is null);
        c.assertValues();
    }
    
    // Array of classes
    {
        connection.executeNonQuery("INSERT INTO UnitTestAllTypesLess(enum1, bool1, byte1" ~
            ", ubyte1, short1, ushort1, int1, uint1" ~
            ", long1, ulong1, float1, double1" ~
            ", string1, charArray, binary1)" ~
            " VALUES('third', true, 102" ~
            ", 1, -1002, 3976, -382652, 3957210" ~
            ", -394572363, 284659275, 6394764.5, -2846627456444.7651" ~
            ", 'test string of', 'will this work?', base64_decode('JRjMZSs='))");
        auto reader = connection.executeReader("SELECT enum1, bool1, byte1, ubyte1, short1, ushort1, int1, uint1, long1, ulong1, float1, double1, string1, charArray, binary1 FROM UnitTestAllTypesLess ORDER BY byte1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestAllTypesLess[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
        {
            //import std.stdio : writeln; debug writeln("i=", i);
            assert(cs[i] !is null);
            cs[i].assertValuesArray(i);
        }
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestStdBigInt
{
    import std.conv : to;
    import pham.ser.ser_std_bigint;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestStdBigInt(i INTEGER, bigInt1 VARCHAR(200))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestStdBigInt");
    connection.executeNonQuery("INSERT INTO UnitTestStdBigInt(i, bigInt1) VALUES(0, '-71459266416693160362545788781600')");

    version(none)
    {
        UnitTestStdBigInt c;
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestStdBigInt(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdBigInt, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestStdBigInt");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestStdBigInt();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestStdBigInt(i, bigInt1) VALUES(1, '-71459266416693160362545788781599')");
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestStdBigInt ORDER BY i");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestStdBigInt[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestStdDateTime
{
    import std.conv : to;
    import pham.ser.ser_std_date_time;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestStdDateTime(date1 DATE, dateTime1 TIMESTAMP, sysTime1 TIMESTAMP, timeOfDay1 TIME)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestStdDateTime");
    connection.executeNonQuery("INSERT INTO UnitTestStdDateTime(date1, dateTime1, sysTime1, timeOfDay1)" ~
        " VALUES('1999-01-01', '1999-07-06 12:30:33', '0001-01-01 00:00:33', '12:30:33')");

    version(none)
    {
        UnitTestStdDateTime c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdDateTime, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT date1, dateTime1, sysTime1, timeOfDay1 FROM UnitTestStdDateTime");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestStdDateTime();
        c.assertValuesArray(0);
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestStdDateTime(date1, dateTime1, sysTime1, timeOfDay1)" ~
            " VALUES('1999-01-02', '1999-07-07 12:30:33', '0001-01-02 00:00:33', '12:30:34')");
        auto reader = connection.executeReader("SELECT date1, dateTime1, sysTime1, timeOfDay1 FROM UnitTestStdDateTime ORDER BY date1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestStdDateTime[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestStdUuid
{
    import std.conv : to;
    import pham.ser.ser_std_uuid;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestStdUuid(uuid1 VARCHAR(36))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestStdUuid");
    connection.executeNonQuery("INSERT INTO UnitTestStdUuid(uuid1) VALUES('8ab3060e-2cba-4f23-b74c-b52db3dbfb46')");

    version(none)
    {
        UnitTestStdUuid c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdUuid(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdUuid, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT uuid1 FROM UnitTestStdUuid");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestStdUuid();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestStdUuid(uuid1) VALUES('8ab3060e-2cba-4f23-b74c-b52db3dbfb46')");
        auto reader = connection.executeReader("SELECT uuid1 FROM UnitTestStdUuid ORDER BY uuid1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestStdUuid[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValues();
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestPhamBigInteger
{
    import std.conv : to;
    import pham.ser.ser_pham_big_integer;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestPhamBigInteger(i INTEGER, bigInt1 VARCHAR(200))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestPhamBigInteger");
    connection.executeNonQuery("INSERT INTO UnitTestPhamBigInteger(i, bigInt1) VALUES(0, '-71459266416693160362545788781600')");

    version(none)
    {
        UnitTestPhamBigInteger c;
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestPhamBigInteger(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdBigInt, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestPhamBigInteger");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestPhamBigInteger();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestPhamBigInteger(i, bigInt1) VALUES(1, '-71459266416693160362545788781599')");
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestPhamBigInteger ORDER BY i");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestPhamBigInteger[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestPhamDateTime
{
    import std.conv : to;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestPhamDateTime(date1 DATE, dateTime1 TIMESTAMP, time1 TIME)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestPhamDateTime");
    connection.executeNonQuery("INSERT INTO UnitTestPhamDateTime(date1, dateTime1, time1) VALUES('1999-01-01', '1999-07-06 12:30:33', '12:30:33')");

    version(none)
    {
        UnitTestPhamDateTime c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestPhamDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestPhamDateTime, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT date1, dateTime1, time1 FROM UnitTestPhamDateTime");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestPhamDateTime();
        c.assertValuesArray(0);
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestPhamDateTime(date1, dateTime1, time1) VALUES('1999-01-02', '1999-07-07 12:30:33', '12:30:34')");
        auto reader = connection.executeReader("SELECT date1, dateTime1, time1 FROM UnitTestPhamDateTime ORDER BY date1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestPhamDateTime[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestDecDecimal
{
    import std.conv : to;
    import pham.ser.ser_dec_decimal;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    //connection.executeNonQuery("CREATE TABLE UnitTestDecDecimal(decimal32 DECIMAL(7, 2), decimal64 DECIMAL(15, 2), decimal128 decfloat(34))");
    connection.executeNonQuery("CREATE TABLE UnitTestDecDecimal(decimal32 DECIMAL(7, 2), decimal64 DECIMAL(15, 2), decimal128 DECIMAL(18, 2))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestDecDecimal");
    connection.executeNonQuery("INSERT INTO UnitTestDecDecimal(decimal32, decimal64, decimal128) VALUES(-7145.0, 714583645.4, 294574120484.87)");

    version(none)
    {
        UnitTestDecDecimal c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestDecDecimal(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestDecDecimal, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT decimal32, decimal64, decimal128 FROM UnitTestDecDecimal");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestDecDecimal();
        c.assertValuesArray(0);
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestDecDecimal(decimal32, decimal64, decimal128) VALUES(-7144.0, 714583646.4, 294574120485.87)");
        auto reader = connection.executeReader("SELECT decimal32, decimal64, decimal128 FROM UnitTestDecDecimal ORDER BY decimal32");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestDecDecimal[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(none)
unittest // DbSerializer.UnitTestCustomS1
{
    import std.conv : to;

    auto connection = createTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.executeNonQuery("CREATE TABLE UnitTestS1(publicInt INTEGER, publicGetSet INTEGER)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestS1");
    connection.executeNonQuery("INSERT INTO UnitTestS1(publicInt, publicGetSet)" ~
        " VALUES(20, 1)");

    version(none)
    {
        UnitTestCustomS1 c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestCustomS1(c.setValues());
        jsonCustom = serializer.buffer[];
        //import std.stdio : writeln; debug writeln("\n", jsonCustom);
    }

    {
        scope deserializer = new JsonDeserializer(jsonCustom);
        auto c2 = deserializer.deserialize!UnitTestCustomS1();
        c2.assertValues();
    }
}
