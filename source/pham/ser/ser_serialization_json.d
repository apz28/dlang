/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.ser.ser_serialization_json;

import std.array : Appender, appender;
import std.conv : to;
import std.json : JSONOptions, JSONType, JSONValue, parseJSON;
import std.traits : isDynamicArray, isFloatingPoint, isIntegral;

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimePattern, dateTimeParse=parse;
import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
import pham.ser.ser_serialization;

class JsonDeserializer : Deserializer
{
@safe:

public:
    this(scope const(char)[] data)
    {
        //import std.stdio : writeln; writeln("\n'", data, "'\n");
        this.root = parseJSON(data);
        //import std.stdio : writeln; debug writeln("root.type=", root.type);
        //import std.stdio : writeln; debug writeln("\n'", this.root.toString(JSONOptions.specialFloatLiterals), "'\n");
    }

    override Deserializer begin()
    {
        currents = [Node(&root)];
        return super.begin();
    }

    override Deserializer end()
    {
        currents = null;
        //root = JSONValue.init;
        return super.end();
    }

    override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        static immutable JSONType[2] checkTypes = [JSONType.object, JSONType.null_];
        checkDataType(checkTypes[]);
        super.aggregateBegin(typeName, attribute);
        const len = readLength();
        popFront(); // Navigate into member(s)
        return len;
    }

    override ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        static immutable JSONType[2] checkTypes = [JSONType.array, JSONType.null_];
        checkDataType(checkTypes[]);
        super.arrayBegin(elemTypeName, attribute);
        const len = readLength();
        popFront(); // Navigate into member(s)
        return len;
    }

    final override Null readNull()
    {
        checkDataType(JSONType.null_);
        popFront();
        return null;
    }

    final override bool readBool()
    {
        static immutable JSONType[2] checkTypes = [JSONType.false_, JSONType.true_];
        const t = checkDataType(checkTypes[]);
        //const v = currents[$-1].value.boolean;
        popFront();
        //return v;
        return t == JSONType.true_;
    }

    final override char readChar()
    {
        const s = readChars();
        assert(s.length == 1);
        return s.length ? s[0] : '\0';
    }

    final override Date readDate()
    {
        auto isop = DateTimePattern.iso8601Date();
        auto text = readScopeChars(DataKind.date);
        return dateTimeParse!(Date, DeserializerException)(text, isop);
    }

    final override DateTime readDateTime()
    {
        auto isop = DateTimePattern.iso8601DateTime();
        auto text = readScopeChars(DataKind.dateTime);
        return dateTimeParse!(DateTime, DeserializerException)(text, isop);
    }

    final override Time readTime()
    {
        auto isop = DateTimePattern.iso8601Time();
        auto text = readScopeChars(DataKind.time);
        return dateTimeParse!(Time, DeserializerException)(text, isop);
    }

    final override byte readByte()
    {
        return readInt!byte();
    }

    final override short readShort()
    {
        return readInt!short();
    }

    final override int readInt(const(DataKind) kind = DataKind.integral)
    {
        return readInt!int();
    }

    final override long readLong(const(DataKind) kind = DataKind.integral)
    {
        return readInt!long();
    }

    final V readInt(V)()
    if (isIntegral!V)
    {
        static immutable JSONType[2] checkTypes = [JSONType.integer, JSONType.uinteger];
        const t = checkDataType(checkTypes[]);
        const v = t == JSONType.integer ? cast(V)currents[$-1].value.integer : cast(V)currents[$-1].value.uinteger;
        popFront();
        return v;
    }

    final override float readFloat(const(FloatFormat) floatFormat, const(DataKind) kind = DataKind.decimal)
    {
        return readFloat!float();
    }

    final override double readDouble(const(FloatFormat) floatFormat, const(DataKind) kind = DataKind.decimal)
    {
        return readFloat!double();
    }

    final V readFloat(V)()
    if (isFloatingPoint!V)
    {
        //import std.stdio : writeln; debug writeln("readFloat().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.value=",  currents[$-1].value.toString(JSONOptions.specialFloatLiterals));
        static immutable JSONType[4] checkTypes = [JSONType.float_, JSONType.integer, JSONType.uinteger, JSONType.string];
        const t = checkDataType(checkTypes[]);
        auto p = &currents[$-1];

        V readFloatLiteral()
        {
            assert(t == JSONType.string);

            const fl = isFloatLiteral(p.value.str);
            return fl == IsFloatLiteral.nan
                ? V.nan
                : (fl == IsFloatLiteral.pinf
                    ? V.infinity
                    : (fl == IsFloatLiteral.ninf
                        ? -V.infinity
                        : throw new DeserializerException("Not a floating point json value")));
        }

        const v = t == JSONType.float_
            ? cast(V)p.value.floating
            : (t == JSONType.integer
                ? cast(V)p.value.integer
                : (t == JSONType.uinteger
                    ? cast(V)p.value.uinteger
                    : readFloatLiteral()));
        popFront();
        return v;
    }

    final override string readChars(const(DataKind) kind = DataKind.character)
    {
        static immutable JSONType[2] checkTypes = [JSONType.string, JSONType.null_];
        const t = checkDataType(checkTypes[]);
        const v = t == JSONType.string ? currents[$-1].value.str : null;
        popFront();
        return v;
    }

    final override wstring readWChars(const(DataKind) kind = DataKind.character)
    {
        auto chars = readChars(kind);
        return chars.length != 0 ? chars.to!wstring : null;
    }

    final override dstring readDChars(const(DataKind) kind = DataKind.character)
    {
        auto chars = readChars(kind);
        return chars.length != 0 ? chars.to!dstring : null;
    }

    final override const(char)[] readScopeChars(const(DataKind) kind = DataKind.character)
    {
        return readChars(kind);
    }

    final override ubyte[] readBytes(const(BinaryFormat) binaryFormat, const(DataKind) kind = DataKind.binary)
    {
        const s = readChars(kind);
        return s.length ? binaryFromString!DeserializerException(s, binaryFormat) : null;
    }

    final override const(ubyte)[] readScopeBytes(const(BinaryFormat) binaryFormat, const(DataKind) kind = DataKind.binary)
    {
        return readBytes(binaryFormat, kind);
    }

    final override string readKey()
    {
        return currents[$-1].name;
    }

    final override ptrdiff_t readLength()
    {
        return currents[$-1].childLength;
    }

public:
    final JSONType checkDataType(const(JSONType) dataType)
    {
        if (currents.length == 0)
            throw new DeserializerException("EOS");

        //import std.stdio : writeln; debug writeln("\tcheckDataType().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.name=", currents[$-1].name);

        const t = currents[$-1].type;
        if (t != dataType)
            throw new DeserializerException("Expect datatype " ~ dataType.to!string ~ " but found " ~ t.to!string ~ " (name: " ~ currents[$-1].name ~ ")");
        return t;
    }

    final JSONType checkDataType(scope const(JSONType)[] dataTypes)
    {
        if (currents.length == 0)
            throw new DeserializerException("EOS");

        //import std.stdio : writeln; debug writeln("\tcheckDataType().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.name=", currents[$-1].name);

        const t = currents[$-1].type;
        bool found = false;
        foreach (const dataType; dataTypes)
        {
            if (t == dataType)
            {
                found = true;
                break;
            }
        }
        if (!found)
            throw new DeserializerException("Expect one of datatypes " ~ dataTypes.to!string ~ " but found " ~ t.to!string ~ " (name: " ~ currents[$-1].name ~ ")");
        return t;
    }

    final override bool empty() nothrow
    {
        return currents.length == 0;
    }

    final override SerializerDataType frontDataType() nothrow
    in
    {
        assert(!empty());
    }
    do
    {
        final switch (currents[$-1].type)
        {
            case JSONType.null_:
                return SerializerDataType.null_;
            case JSONType.string:
                return SerializerDataType.chars;
            case JSONType.integer:
            case JSONType.uinteger:
                return SerializerDataType.int8;
            case JSONType.float_:
                return SerializerDataType.float8;
            case JSONType.true_:
            case JSONType.false_:
                return SerializerDataType.bool_;
            case JSONType.array:
                return SerializerDataType.arrayBegin;
            case JSONType.object:
                return SerializerDataType.aggregateBegin;
        }
    }

    final override bool hasArrayEle(size_t i, ptrdiff_t len) nothrow
    {
        //import std.stdio : writeln; debug writeln("hasArrayEle().i=", i, ", len=", len);
        return len > 0 && len > i && currents.length != 0;
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len) nothrow
    {
        //import std.stdio : writeln; debug writeln("hasAggregateEle().i=", i, ", len=", len);
        return len > 0 && len > i && currents.length != 0;
    }

    final void popFront()
    in
    {
        assert(!empty());
    }
    do
    {
        //import std.stdio : writeln; debug writeln("\tpopFront().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.name=", currents[$-1].name);
        //import std.stdio : writeln; debug writeln("\t           childLength=", currents[$-1].childLength, ", index=", currents[$-1].index, ", parentLength=", currents[$-1].parentLength);

        const i = currents.length - 1;

        // Has children?
        if (currents[i].childLength > 0)
        {
            currents ~= currents[i].getChild(0);
            return;
        }

        // Next sibling?
        const iind = currents[i].index + 1;
        if (iind < currents[i].parentLength)
        {
            currents[i] = currents[i - 1].getChild(iind);
            return;
        }

        // Set next parent sibling
        currents = currents[0..i];
        while (currents.length)
        {
            const j = currents.length - 1;
            const jind = currents[j].index + 1;
            //import std.stdio : writeln; debug writeln("\t           childLength=", currents[$-1].childLength, ", index=", currents[$-1].index, ", parentLength=", currents[$-1].parentLength);
            if (jind < currents[j].parentLength)
            {
                currents[j] = currents[j - 1].getChild(jind);
                return; // Out of while loop
            }

            currents = currents[0..j];
        }
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    static struct Node
    {
    @safe:

        this(JSONValue* value, ptrdiff_t index = 0, ptrdiff_t parentLength = -1, string name = null) @trusted
        in
        {
            assert(value !is null);
        }
        do
        {
            this.index = index;
            this.parentLength = parentLength;
            this.name = name;
            this.value = value;
            this.type = value.type;
            if (this.type == JSONType.object)
            {
                this.childNames = value.object.keys;
                this.childLength = this.childNames.length;
            }
            else if (this.type == JSONType.array)
            {
                this.childLength = value.array.length;
                //this.childNames = null;
            }
            else if (this.type == JSONType.null_)
            {
                this.childLength = 0;
                //this.childNames = null;
            }
            else
            {
                this.childLength = -1;
                //this.childNames = null;
            }
            //import std.stdio : writeln; debug writeln("\tNode().name=", name, ", index=", index, ", childNames=", childNames);
        }

        Node getChild(size_t childIndex) @trusted
        in
        {
            assert(type == JSONType.array || type == JSONType.object);
            assert(childLength > 0);
            assert(childIndex < childLength);
        }
        do
        {
            if (type == JSONType.object)
            {
                const childName = childNames[childIndex];
                return Node(&value.object[childName], childIndex, childLength, childName);
            }

            return Node(&value.array[childIndex], childIndex, childLength);
        }

        JSONValue* value;
        ptrdiff_t index;
        string name;
        ptrdiff_t childLength;
        ptrdiff_t parentLength;
        string[] childNames;
        JSONType type;
    }

    JSONValue root;
    Node[] currents;
}

class JsonSerializer : Serializer
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

unittest // JsonSerializer
{
    Serializable serializableAggregate, serializableAggregateMember, serializableArray;
    Serializable serializableByName = Serializable(null, EnumFormat.name);
    Serializable serializableByIntegral = Serializable(null, EnumFormat.integral);
    FloatFormat floatFormat = FloatFormat(4, true);
    BinaryFormat binaryFormat;

    ref Serializable aggregateMember(string name)
    {
        serializableAggregateMember.name = name;
        serializableAggregateMember.memberName = name;
        return serializableAggregateMember;
    }

    scope serializer = new JsonSerializer();
    serializer.begin();
    serializer.aggregateBegin(null, -1, serializableAggregate);
    serializer.aggregateItem(0, aggregateMember("b1")).writeBool(true);
    serializer.aggregateItem(1, aggregateMember("b2")).writeBool(false);
    serializer.aggregateItem(2, aggregateMember("n1")).write(null);
    serializer.aggregateItem(3, aggregateMember("f1")).write(1.5, floatFormat);
    serializer.aggregateItem(4, aggregateMember("d1")).write(100);
    serializer.aggregateItem(5, aggregateMember("c1")).writeChar('c');
    serializer.aggregateItem(6, aggregateMember("s1")).write("This is a string /\\");
    serializer.aggregateItem(7, aggregateMember("e1")); serializer.serialize(UnitTestEnum.second, serializableByName);
    serializer.aggregateItem(8, aggregateMember("e2")); serializer.serialize(UnitTestEnum.forth, serializableByIntegral);
    serializer.aggregateItem(9, aggregateMember("bin1")).write([100, 101], binaryFormat);
    serializer.aggregateItem(10, aggregateMember("arr1"));
    serializer.arrayBegin(null, 2, serializableArray);
    serializer.arrayItem(0).write(200);
    serializer.arrayItem(1).write(201);
    serializer.arrayEnd(null, 2, serializableArray);
    serializer.aggregateEnd(null, 11, serializableAggregate);
    serializer.end();

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == q"<{"b1":true,"b2":false,"n1":null,"f1":1.5,"d1":100,"c1":"c","s1":"This is a string \/\\","e1":"second","e2":3,"bin1":"ZGU=","arr1":[200,201]}>", serializer.buffer[]);
}

unittest // JsonSerializer.UnitTestC2
{
    static immutable string jsonUnitTestC2 =
        q"<{"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1},"GetSet":1,"publicStr":"C2 public string"}>";

    {
        auto c = new UnitTestC2();
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestC2(cast(UnitTestC2)(c.setValues()));
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestC2, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestC2);
        auto c = deserializer.deserialize!UnitTestC2();
        assert(c !is null);
        c.assertValues();
    }
}

unittest // JsonSerializer.UnitTestAllTypes
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

unittest // JsonSerializer.UnitTestStdBigInt
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

unittest // JsonSerializer.UnitTestStdDateTime
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

unittest // JsonSerializer.UnitTestStdUuid
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

unittest // JsonSerializer.UnitTestPhamBigInteger
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

unittest // JsonSerializer.UnitTestPhamDateTime
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

unittest // JsonSerializer.UnitTestDecDecimal
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

unittest // JsonSerializer+JsonDeserializer.UnitTestCustomS1
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
