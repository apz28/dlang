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
import pham.db.db_database : DbCommand, DbFieldList, DbParameter, DbParameterList, DbReader;
import pham.db.db_type : DbType;
import pham.db.db_value : DbRowValue, DbValue;
import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimePattern;
import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
import pham.var.var_coerce;
import pham.var.var_coerce_dec_decimal;
import pham.var.var_coerce_pham_date_time;
import pham.var.var_variant : Variant;
import pham.ser.ser_serialization;
import pham.ser.ser_serialization_json; // Use for supporting hierachy - aggregated member

class DbDeserializer : Deserializer
{
@safe:

public:
    this(DbReader* reader) nothrow
    {
        this.reader = reader;
        this.fields = reader.fields;
    }

    override Deserializer begin(scope ref Serializable attribute)
    {
        currentCol = 0;
        currentRow = readRowReader();
        return super.begin(attribute);
    }

    override Deserializer end(scope ref Serializable attribute)
    {
        currentCol = currentRow = 0;
        return super.end(attribute);
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

class DbSerializer : Serializer
{
@safe:

public:
    this(DbConnection connection) nothrow
    {
        this.connection = connection;
    }

    override Serializer begin(scope ref Serializable attribute)
    {
        param = null;
        commandParams = connection.database.createParameterList();
        commandText = appender!string();
        commandText.reserve(bufferCapacity);
        return super.begin(attribute);
    }

    override Serializer end(scope ref Serializable attribute)
    {
        param = null;

        return super.end(attribute);
    }

    override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        super.aggregateEnd(typeName, length, serializable);
    }

    final override Serializer aggregateItem(ptrdiff_t index, scope ref Serializable serializable)
    {
        return super.aggregateItem(index, serializable);
    }

    override void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        super.arrayBegin(elemTypeName, length, serializable);
    }

    override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        super.arrayEnd(elemTypeName, length, serializable);
    }

    final override Serializer arrayItem(ptrdiff_t index)
    {
        return super.arrayItem(index);
    }

    final override void write(Null, scope ref Serializable attribute)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.unknown);
        param.variant = Variant(null);
    }

    final override void writeBool(bool v, scope ref Serializable attribute)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.boolean);
        else
            param.type = DbType.boolean;
        param.variant = Variant(v);
    }

    final override void writeChar(char v, scope ref Serializable attribute)
    {
        auto v2 = v.to!string;
        write(v2, attribute);
    }

    final override void write(scope const(Date) v, scope ref Serializable attribute)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.date);
        else
            param.type = DbType.date;
        param.variant = Variant(v);
    }

    final override void write(scope const(DateTime) v, scope ref Serializable attribute)
    {
        const type = v.kind == DateTimeZoneKind.utc ? DbType.timeTZ : DbType.time;
        if (param is null)
            param = commandParams.add(attribute.name, type);
        else
            param.type = type;
        param.variant = Variant(v);
    }

    final override void write(scope const(Time) v, scope ref Serializable attribute)
    {
        const type = v.kind == DateTimeZoneKind.utc ? DbType.timeTZ : DbType.time;
        if (param is null)
            param = commandParams.add(attribute.name, type);
        else
            param.type = type;
        param.variant = Variant(v);
    }

    final override void write(byte v, scope ref Serializable attribute)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.int8);
        else
            param.type = DbType.int8;
        param.variant = Variant(v);
    }

    final override void write(short v, scope ref Serializable attribute)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.int16);
        else
            param.type = DbType.int16;
        param.variant = Variant(v);
    }

    final override void write(int v, scope ref Serializable attribute, const(DataKind) kind = DataKind.integral)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.int32);
        else
            param.type = DbType.int32;
        param.variant = Variant(v);
    }

    final override void write(long v, scope ref Serializable attribute, const(DataKind) kind = DataKind.integral)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.int64);
        else
            param.type = DbType.int64;
        param.variant = Variant(v);
    }

    final override void write(float v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.float32);
        else
            param.type = DbType.float32;
        param.variant = Variant(v);
    }

    final override void write(double v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.float64);
        else
            param.type = DbType.float64;
        param.variant = Variant(v);
    }

    final override void write(scope const(char)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.stringVary);
        else
            param.type = DbType.stringVary;
        param.variant = Variant(v);
    }

    final override void write(scope const(wchar)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto v2 = v.to!string;
        write(v2, attribute, kind);
    }

    final override void write(scope const(dchar)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto v2 = v.to!string;
        write(v2, attribute, kind);
    }

    final override void write(scope const(ubyte)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        if (param is null)
            param = commandParams.add(attribute.name, DbType.binaryVary);
        else
            param.type = DbType.binaryVary;
        param.variant = Variant(v);
    }

    final override Serializer writeKey(string key, scope ref Serializable attribute)
    {
        param = commandParams.add(key, DbType.unknown);
        return this;
    }

    final override Serializer writeKeyId(string key, scope ref Serializable attribute)
    {
        return writeKey(key, attribute);
    }

public:
    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    DbConnection connection;
    DbParameterList commandParams;
    Appender!string commandText;
    DbParameter param;
    size_t bufferCapacity = 1_000;
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

    connection.executeNonQuery("CREATE TABLE UnitTestCustomS1(publicInt INTEGER, publicGetSet INTEGER)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestCustomS1");
    connection.executeNonQuery("INSERT INTO UnitTestCustomS1(publicInt, publicGetSet)" ~
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
