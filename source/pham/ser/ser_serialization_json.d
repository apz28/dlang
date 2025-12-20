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

import std.conv : to;
import std.traits : isDynamicArray, isFloatingPoint, isIntegral;

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimePattern, dateTimeParse=parse;
import pham.dtm.dtm_tick : DateTimeSetting, DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
import pham.json.json_reader : parseJSON;
import pham.json.json_type : JSONOptions, JSONType;
import pham.json.json_value : JSONValue;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_enum_set : EnumSet;
import pham.ser.ser_serialization;

alias JSONTypeChecked = JSONType;

class JsonDeserializer : Deserializer
{
@safe:

public:
    this(const(char)[] data)
    {
        this.root = parseJSON!(JSONOptions.none)(data); // Need to handle Nan, +inf, -inf ourself
        //import std.stdio : writeln; debug writeln("root=", root.toString(JSONOptions.specialFloatLiterals));
    }

    override JsonDeserializer begin(scope ref Serializable attribute)
    {
        currents = [Node(&root)];
        return cast(JsonDeserializer)super.begin(attribute);
    }

    override JsonDeserializer end(scope ref Serializable attribute)
    {
        currents = null;
        //root = JSONValue.init;
        return cast(JsonDeserializer)super.end(attribute);
    }

    final override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        static immutable EnumSet!JSONTypeChecked checkTypes = EnumSet!JSONTypeChecked([JSONTypeChecked.object, JSONTypeChecked.null_]);
        checkDataType(checkTypes);
        super.aggregateBegin(typeName, attribute);
        const len = readLength();
        popFront(); // Navigate into member(s)
        return len;
    }

    final override ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        static immutable EnumSet!JSONTypeChecked checkTypes = EnumSet!JSONTypeChecked([JSONTypeChecked.array, JSONTypeChecked.null_]);
        checkDataType(checkTypes);
        super.arrayBegin(elemTypeName, attribute);
        const len = readLength();
        popFront(); // Navigate into member(s)
        return len;
    }

    final override Null readNull(scope ref Serializable)
    {
        checkDataType(JSONType.null_);
        popFront();
        return null;
    }

    final override bool readBool(scope ref Serializable)
    {
        static immutable EnumSet!JSONTypeChecked checkTypes = EnumSet!JSONTypeChecked([JSONTypeChecked.false_, JSONTypeChecked.true_]);
        const t = checkDataType(checkTypes);
        //const v = currents[$-1].value.boolean;
        popFront();
        //return v;
        return t == JSONType.true_;
    }

    final override char readChar(scope ref Serializable attribute)
    {
        const s = readChars(attribute);
        assert(s.length == 1);
        return s.length ? s[0] : '\0';
    }

    final override Date readDate(scope ref Serializable attribute)
    {
        auto isop = DateTimePattern.iso8601Date();
        auto text = readScopeChars(attribute, DataKind.date);
        return dateTimeParse!(Date, DeserializerException)(text, isop);
    }

    final override DateTime readDateTime(scope ref Serializable attribute)
    {
        auto isop = DateTimePattern.iso8601DateTime();
        auto text = readScopeChars(attribute, DataKind.dateTime);
        return dateTimeParse!(DateTime, DeserializerException)(text, isop);
    }

    final override Time readTime(scope ref Serializable attribute)
    {
        auto isop = DateTimePattern.iso8601Time();
        auto text = readScopeChars(attribute, DataKind.time);
        return dateTimeParse!(Time, DeserializerException)(text, isop);
    }

    final override byte readByte(scope ref Serializable)
    {
        return readInt!byte();
    }

    final override short readShort(scope ref Serializable)
    {
        return readInt!short();
    }

    final override int readInt(scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        return readInt!int();
    }

    final override long readLong(scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        return readInt!long();
    }

    final V readInt(V)()
    if (isIntegral!V)
    {
        //import std.stdio : writeln; debug writeln("readInt().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.value=",  currents[$-1].value.toString(JSONOptions.specialFloatLiterals));
        static immutable EnumSet!JSONTypeChecked checkTypes = EnumSet!JSONTypeChecked([JSONTypeChecked.integer]);
        const t = checkDataType(checkTypes);
        const v = cast(V)currents[$-1].value.integer;        
        popFront();
        return v;
    }

    final override float readFloat(scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        return readFloat!float();
    }

    final override double readDouble(scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        return readFloat!double();
    }

    final V readFloat(V)()
    if (isFloatingPoint!V)
    {
        //import std.stdio : writeln; debug writeln("readFloat().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.value=",  currents[$-1].value.toString(JSONOptions.specialFloatLiterals));
        static immutable EnumSet!JSONTypeChecked checkTypes = EnumSet!JSONTypeChecked([JSONTypeChecked.float_, JSONTypeChecked.integer, JSONTypeChecked.string]);
        const t = checkDataType(checkTypes);
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
                : readFloatLiteral());
        popFront();
        return v;
    }

    final override string readChars(scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        static immutable EnumSet!JSONTypeChecked checkTypes = EnumSet!JSONTypeChecked([JSONTypeChecked.string, JSONTypeChecked.null_]);
        const t = checkDataType(checkTypes);
        const v = t == JSONType.string ? currents[$-1].value.str : null;
        popFront();
        return v;
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

    final override ubyte[] readBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        const s = readChars(attribute, kind);
        return s.length ? binaryFromString!DeserializerException(s, binaryFormat(attribute)) : null;
    }

    final override const(ubyte)[] readScopeBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        return readBytes(attribute, kind);
    }

    final override string readKey(size_t)
    {
        return currents[$-1].name;
    }

    final ptrdiff_t readLength() const nothrow
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

    final JSONType checkDataType(scope const(EnumSet!JSONTypeChecked) dataTypes)
    {
        if (currents.length == 0)
            throw new DeserializerException("EOS");

        //import std.stdio : writeln; debug writeln("\tcheckDataType().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.name=", currents[$-1].name);

        const t = currents[$-1].type;
        if (dataTypes.isOff(cast(JSONTypeChecked)t))
            throw new DeserializerException("Expect one of datatypes " ~ dataTypes.toString() ~ " but found " ~ t.to!string ~ " (name: " ~ currents[$-1].name ~ ")");
        return t;
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len)
    {
        //import std.stdio : writeln; debug writeln("hasAggregateEle().i=", i, ", len=", len);
        return len > 0 && len > i && currents.length != 0;
    }

    final override bool hasArrayEle(size_t i, ptrdiff_t len)
    {
        //import std.stdio : writeln; debug writeln("hasArrayEle().i=", i, ", len=", len);
        return len > 0 && len > i && currents.length != 0;
    }

    final void popFront()
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

        this(JSONValue* value,
            ptrdiff_t index = 0,
            ptrdiff_t parentLength = DSSerializer.unknownLength,
            string name = null) @trusted
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
                //this.childNames = null;
                this.childLength = value.array.length;
            }
            else if (this.type == JSONType.null_)
            {
                //this.childNames = null;
                //this.childLength = 0;
            }
            else
            {
                //this.childNames = null;
                this.childLength = DSSerializer.unknownLength;
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
        const(string)[] childNames;
        JSONType type;
    }

    JSONValue root;
    Node[] currents;
}

class JsonSerializer : Serializer
{
@safe:

public:
    override JsonSerializer begin(scope ref Serializable attribute)
    {
        buffer.clear();
        buffer.capacity = bufferCapacity;
        return cast(JsonSerializer)super.begin(attribute);
    }

    override JsonSerializer end(scope ref Serializable attribute)
    {
        return cast(JsonSerializer)super.end(attribute);
    }

    final override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put(length ? "}" : "null");
        super.aggregateEnd(typeName, length, attribute);
    }

    final override JsonSerializer aggregateItem(ptrdiff_t index, scope ref Serializable attribute)
    {
        buffer.put(index ? ',' : '{');
        return cast(JsonSerializer)super.aggregateItem(index, attribute);
    }

    final override void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put('[');
        super.arrayBegin(elemTypeName, length, attribute);
    }

    final override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put(']');
        super.arrayEnd(elemTypeName, length, attribute);
    }

    final override JsonSerializer arrayItem(ptrdiff_t index, scope ref Serializable attribute)
    {
        if (index)
            buffer.put(',');
        return cast(JsonSerializer)super.arrayItem(index, attribute);
    }

    final override void write(Null, scope ref Serializable)
    {
        buffer.put("null");
    }

    static immutable string[2] boolValues = ["false", "true"];
    final override void writeBool(bool v, scope ref Serializable)
    {
        buffer.put(boolValues[v]);
    }

    final override void writeChar(char v, scope ref Serializable attribute)
    {
        char[1] s = [v];
        write(s[], attribute);
    }

    final override void write(scope const(Date) v, scope ref Serializable)
    {
        auto setting = DateTimeSetting.iso8601;

        buffer.put('"');
        v.toString(buffer, DateTimeSetting.iso8601Fmt, setting);
        buffer.put('"');
    }

    final override void write(scope const(DateTime) v, scope ref Serializable)
    {
        auto setting = v.kind == DateTimeZoneKind.utc ? DateTimeSetting.iso8601Utc : DateTimeSetting.iso8601;
        const fmt = v.kind == DateTimeZoneKind.utc ? DateTimeSetting.iso8601FmtUtc : DateTimeSetting.iso8601Fmt;

        buffer.put('"');
        v.toString(buffer, fmt, setting);
        buffer.put('"');
    }

    final override void write(scope const(Time) v, scope ref Serializable)
    {
        auto setting = v.kind == DateTimeZoneKind.utc ? DateTimeSetting.iso8601Utc : DateTimeSetting.iso8601;
        const fmt = v.kind == DateTimeZoneKind.utc ? DateTimeSetting.iso8601FmtUtc : DateTimeSetting.iso8601Fmt;

        buffer.put('"');
        v.toString(buffer, fmt, setting);
        buffer.put('"');
    }

    final override void write(byte v, scope ref Serializable)
    {
        writeImpl(v);
    }

    final override void write(short v, scope ref Serializable)
    {
        writeImpl(v);
    }

    final override void write(int v, scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        writeImpl(v);
    }

    final override void write(long v, scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        writeImpl(v);
    }

    final override void write(float v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        writeImpl(v, attribute);
    }

    final override void write(double v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        writeImpl(v, attribute);
    }

    final override void write(scope const(char)[] v, scope ref Serializable, const(DataKind) kind = DataKind.character)
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

    final override void write(scope const(wchar)[] v, scope ref Serializable, const(DataKind) kind = DataKind.character)
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

    final override void write(scope const(dchar)[] v, scope ref Serializable, const(DataKind) kind = DataKind.character)
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

    final override void write(scope const(ubyte)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        if (v is null)
        {
            buffer.put("null");
            return;
        }

        buffer.put('"');
        binaryToString(buffer, v, binaryFormat(attribute));
        buffer.put('"');
    }

    final override Serializer writeKey(scope ref Serializable attribute)
    {
        auto key = attribute.name;
        buffer.put('"');
        escapeString(buffer, key);
        buffer.put('"');
        buffer.put(':');
        return this;
    }

    final override Serializer writeKeyId(scope ref Serializable attribute)
    {
        auto key = attribute.name;
        buffer.put('"');
        buffer.put(key);
        buffer.put('"');
        buffer.put(':');
        return this;
    }

public:
    static T escapeString(T)(scope T s) nothrow pure
    if (isDynamicArray!T)
    {
        auto buffer = Appender!T(s.length + (s.length / 4));
        return escapeString(buffer, s).data;
    }

    static ref Writer escapeString(T, Writer)(return ref Writer sink, scope T s)
    if (isDynamicArray!T)
    {
        size_t i;
        while (i < s.length && !isEscapedChar(s[i]))
            i++;
        if (i == s.length)
        {
            sink.put(s);
            return sink;
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
        return sink;
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
        import pham.utl.utl_convert : putNumber;

        buffer.putNumber(v);
    }

    final void writeImpl(V)(V v, scope ref Serializable attribute)
    if (isFloatingPoint!V)
    {
        char[350] vBuffer = void;
        buffer.put(floatToString(vBuffer[], v, floatFormat(attribute)));
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    Appender!(char[]) buffer;
    size_t bufferCapacity = 1_000 * 16;
}


private:

unittest // JsonSerializer
{
    Serializable serializableAggregate, serializableAggregateMember, serializableArray;
    Serializable serializableByName = Serializable(null, EnumFormat.name);
    Serializable serializableByIntegral = Serializable(null, EnumFormat.integral);
    Serializable anyAttribute;
    Serializable binaryAttribute;
    Serializable floatAttribute;
    floatAttribute.floatFormat = FloatFormat(4, true);

    ref Serializable aggregateMember(string name)
    {
        serializableAggregateMember.name = name;
        serializableAggregateMember.memberName = name;
        return serializableAggregateMember;
    }

    Serializable emptyAttribute;
    scope serializer = new JsonSerializer();
    serializer.begin(emptyAttribute);
    serializer.aggregateBegin(null, -1, serializableAggregate);
    serializer.aggregateItem(0, aggregateMember("b1")).writeBool(true, anyAttribute);
    serializer.aggregateItem(1, aggregateMember("b2")).writeBool(false, anyAttribute);
    serializer.aggregateItem(2, aggregateMember("n1")).write(null, anyAttribute);
    serializer.aggregateItem(3, aggregateMember("f1")).write(1.5, floatAttribute);
    serializer.aggregateItem(4, aggregateMember("d1")).write(100, anyAttribute);
    serializer.aggregateItem(5, aggregateMember("c1")).writeChar('c', anyAttribute);
    serializer.aggregateItem(6, aggregateMember("s1")).write("This is a string /\\", anyAttribute);
    serializer.aggregateItem(7, aggregateMember("e1")); serializer.serialize(UnitTestEnum.second, serializableByName);
    serializer.aggregateItem(8, aggregateMember("e2")); serializer.serialize(UnitTestEnum.forth, serializableByIntegral);
    serializer.aggregateItem(9, aggregateMember("bin1")).write(cast(const(ubyte)[])[100, 101], binaryAttribute);
    serializer.aggregateItem(10, aggregateMember("arr1"));
    serializer.arrayBegin(null, 2, serializableArray);
    serializer.arrayItem(0, anyAttribute).write(200, anyAttribute);
    serializer.arrayItem(1, anyAttribute).write(201, anyAttribute);
    serializer.arrayEnd(null, 2, serializableArray);
    serializer.aggregateEnd(null, 11, serializableAggregate);
    serializer.end(emptyAttribute);

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
        serializer.serialize!UnitTestC2(c.setValues());
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

unittest // JsonSerializer.UnitTestCustomS1
{
    string jsonCustom;

    {
        UnitTestCustomS1 c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestCustomS1(c.setValues());
        jsonCustom = serializer.buffer[].idup;
        //import std.stdio : writeln; debug writeln("\n", jsonCustom);
    }

    {
        scope deserializer = new JsonDeserializer(jsonCustom);
        auto c2 = deserializer.deserialize!UnitTestCustomS1();
        c2.assertValues();
    }
}
