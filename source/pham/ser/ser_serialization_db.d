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
        currentCol = 0;
        currentRow = DbRowValue.init;
        return super.end();
    }

    override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(typeName=", typeName, ", memberDepth=", memberDepth, ")");

        currentCol = 0;
        super.aggregateBegin(typeName, attribute);
        return currentRow.length;
    }

    final override Null readNull(scope ref Serializable)
    {
        const i = popFront();
        assert(currentRow[i].isNull);
        return null;
    }

    final override bool readBool(scope ref Serializable)
    {
        return currentRow[popFront()].value.coerce!bool();
    }

    final override char readChar(scope ref Serializable attribute)
    {
        const s = readChars(attribute);
        assert(s.length == 1);
        return s.length ? s[0] : '\0';
    }

    final override Date readDate(scope ref Serializable)
    {
        return currentRow[popFront()].value.coerce!Date();
    }

    final override DateTime readDateTime(scope ref Serializable)
    {
        return currentRow[popFront()].value.coerce!DateTime();
    }

    final override Time readTime(scope ref Serializable)
    {
        return currentRow[popFront()].value.coerce!Time();
    }

    final override byte readByte(scope ref Serializable)
    {
        return currentRow[popFront()].value.coerce!byte();
    }

    final override short readShort(scope ref Serializable)
    {
        return currentRow[popFront()].value.coerce!short();
    }

    final override int readInt(scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        return currentRow[popFront()].value.coerce!int();
    }

    final override long readLong(scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        return currentRow[popFront()].value.coerce!long();
    }

    final override float readFloat(scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        return currentRow[popFront()].value.coerce!float();
    }

    final override double readDouble(scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        return currentRow[popFront()].value.coerce!double();
    }

    final override string readChars(scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        const i = popFront();
        return currentRow[i].isNull ? null : currentRow[i].value.coerce!string();
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
        return currentRow[i].isNull ? null : currentRow[i].value.coerce!(ubyte[])();
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
            ", arrayDepth=", arrayDepth, ", currentRow.length=", currentRow.length, ")");

        if (i != 0 && currentRow.length != 0)
        {
            currentCol = 0;
            currentRow = readRowReader();
        }

        return currentRow.length != 0;
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len)
    {
        return len > 0 && len > i && currentRow.length != 0;
    }

    pragma(inline, true)
    final size_t popFront() nothrow
    {
        return currentCol++;
    }

    final DbRowValue readRowReader()
    {
        return (*reader).read() ? reader.currentRow : DbRowValue.init;
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    DbReader* reader;
    DbFieldList fields;
    DbRowValue currentRow;
    size_t currentCol;
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
    connection.executeNonQuery("INSERT INTO UnitTestS1 (publicInt, publicGetSet) VALUES (20, 1)");

    version(none)
    {
        auto c = new UnitTestC2();
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestC2(cast(UnitTestC2)(c.setValues()));
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
        connection.executeNonQuery("INSERT INTO UnitTestS1 (publicInt, publicGetSet) VALUES (21, 2)");
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1 ORDER BY publicInt");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestS1[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
}

version(none)
unittest // DbSerializer.UnitTestAllTypes
{
    static immutable string jsonUnitTestAllTypes =
        q"<{"enum1":"third","bool1":true,"byte1":101,"ubyte1":0,"short1":-1003,"ushort1":3975,"int1":-382653,"uint1":3957209,"long1":-394572364,"ulong1":284659274,"float1":6394763.5,"floatNaN":"NaN","double1":-2846627456445.7651,"doubleInf":"-Infinity","string1":"test string of","charArray":"will this work?","binary1":"JRjMZSs=","intArray":[135,937,3725,3068,38465,380],"intArrayNull":[],"intInt":{"2":23456,"11":113456},"intIntNull":null,"enumEnum":{"forth":"sixth","third":"second"},"strStr":{"key1":"key1 value","key2":"key2 value","key3":null},"struct1":{"publicInt":20,"publicGetSet":1},"class1":{"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1},"GetSet":1},"class1Null":null}>";

    {
        auto c = new UnitTestAllTypes();
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestAllTypes(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestAllTypes, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestAllTypes);
        auto c = deserializer.deserialize!UnitTestAllTypes();
        assert(c !is null);
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestStdBigInt
{
    import pham.ser.ser_std_bigint;

    static immutable string jsonUnitTestStdBigInt =
        q"<{"bigInt1":"-71459266416693160362545788781600"}>";

    {
        UnitTestStdBigInt c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdBigInt(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdBigInt, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestStdBigInt);
        auto c = deserializer.deserialize!UnitTestStdBigInt();
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestStdDateTime
{
    import pham.ser.ser_std_date_time;

    static immutable string jsonUnitTestStdDateTime =
        q"<{"date1":"1999-01-01","dateTime1":"1999-07-06T12:30:33.0000000","sysTime1":"0001-01-01T00:00:33.0000502Z","timeOfDay1":"12:30:33.0000000"}>";

    {
        UnitTestStdDateTime c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdDateTime, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestStdDateTime);
        auto c = deserializer.deserialize!UnitTestStdDateTime();
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestStdUuid
{
    import pham.ser.ser_std_uuid;

    static immutable string jsonUnitTestStdUuid =
        q"<{"uuid1":"8ab3060e-2cba-4f23-b74c-b52db3dbfb46"}>";

    {
        UnitTestStdUuid c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdUuid(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdUuid, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestStdUuid);
        auto c = deserializer.deserialize!UnitTestStdUuid();
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestPhamBigInteger
{
    import pham.ser.ser_pham_big_integer;

    static immutable string jsonUnitTestPhamBigInteger =
        q"<{"bigInt1":"-71459266416693160362545788781600"}>";

    {
        UnitTestPhamBigInteger c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestPhamBigInteger(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestPhamBigInteger, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestPhamBigInteger);
        auto c = deserializer.deserialize!UnitTestPhamBigInteger();
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestPhamDateTime
{
    static immutable string jsonUnitTestPhamDateTime =
        q"<{"date1":"1999-01-01","dateTime1":"1999-07-06T12:30:33.0000000Z","time1":"12:30:33.0000000Z"}>";

    {
        UnitTestPhamDateTime c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestPhamDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestPhamDateTime, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestPhamDateTime);
        auto c = deserializer.deserialize!UnitTestPhamDateTime();
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestDecDecimal
{
    import pham.ser.ser_dec_decimal;

    static immutable string jsonUnitTestDecDecimal =
        q"<{"decimalNaN":"nan","decimalInfinity":"-inf","decimal32":"-7145.0","decimal64":"714583645.4","decimal128":"294574120484.87"}>";

    {
        UnitTestDecDecimal c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestDecDecimal(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestDecDecimal, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestDecDecimal);
        auto c = deserializer.deserialize!UnitTestDecDecimal();
        c.assertValues();
    }
}

version(none)
unittest // DbSerializer.UnitTestCustomS1
{
    string jsonCustom;

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
