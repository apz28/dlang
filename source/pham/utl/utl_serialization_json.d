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

module pham.utl.utl_serialization_json;

import std.array : Appender, appender;
import std.json : JSONOptions, JSONType, JSONValue, parseJSON;
import std.traits : isDynamicArray, isFloatingPoint, isIntegral;
import pham.utl.utl_serialization;

class JsonDeserializer : Deserializer
{
@safe:

public:
    this(scope const(char)[] data)
    {
        //import std.stdio : writeln; writeln("\n'", data, "'\n");
        this.root = parseJSON(data);
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
        super.aggregateBegin(typeName, attribute);
        const len = readLength();
        popFront(); // Navigate into member(s)
        return len;
    }

    override ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        super.arrayBegin(elemTypeName, attribute);
        const len = readLength();
        popFront(); // Navigate into member(s)
        return len;
    }

    final override Null readNull()
    {
        assert(currents[$-1].type == JSONType.null_);

        popFront();
        return null;
    }

    final override bool readBool()
    {
        auto p = currents[$-1];
        const t = p.type;
        assert(t == JSONType.false_ || t == JSONType.true_);

        const v = p.value.boolean;
        popFront();
        return v;
    }

    final override char readChar()
    {
        const s = readChars();
        assert(s.length == 1);
        return s.length ? s[0] : '\0';
    }

    final override byte readByte()
    {
        return readInt!byte();
    }

    final override short readShort()
    {
        return readInt!short();
    }

    final override int readInt()
    {
        return readInt!int();
    }

    final override long readLong()
    {
        return readInt!long();
    }

    final V readInt(V)()
    if (isIntegral!V)
    {
        auto p = currents[$-1];
        const t = p.type;
        assert(t == JSONType.integer || t == JSONType.uinteger);

        const v = t == JSONType.integer ? cast(V)p.value.integer : cast(V)p.value.uinteger;
        popFront();
        return v;
    }

    final override float readFloat(const(FloatFormat) floatFormat)
    {
        return readFloat!float();
    }

    final override double readDouble(const(FloatFormat) floatFormat)
    {
        return readFloat!double();
    }

    final V readFloat(V)()
    if (isFloatingPoint!V)
    {
        //import std.stdio : writeln; debug writeln("readFloat().currents.length=", currents.length, ", current.type=", currents[$-1].type, ", current.value=",  currents[$-1].value.toString(JSONOptions.specialFloatLiterals));
        auto p = currents[$-1];
        const t = p.type;
        assert(t == JSONType.float_ || t == JSONType.integer || t == JSONType.uinteger || t == JSONType.string);

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
                        : cast(V)p.value.floating));
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

    final override string readChars()
    {
        auto p = &currents[$-1];
        const t = p.type;
        assert(t == JSONType.string || t == JSONType.null_);

        const v = t == JSONType.string ? p.value.str : null;
        popFront();
        return v;
    }

    final override const(char)[] readScopeChars()
    {
        return readChars();
    }

    final override ubyte[] readBytes(const(BinaryFormat) binaryFormat)
    {
        const s = readChars();
        return s.length ? binaryFromString!DeserializerException(s, binaryFormat) : null;
    }

    final override const(ubyte)[] readScopeBytes(const(BinaryFormat) binaryFormat)
    {
        return readBytes(binaryFormat);
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

    final override void write(byte v)
    {
        writeImpl(v);
    }

    final override void write(short v)
    {
        writeImpl(v);
    }

    final override void write(int v)
    {
        writeImpl(v);
    }

    final override void write(long v)
    {
        writeImpl(v);
    }

    final override void write(float v, const(FloatFormat) floatFormat)
    {
        writeImpl(v, floatFormat);
    }

    final override void write(double v, const(FloatFormat) floatFormat)
    {
        writeImpl(v, floatFormat);
    }

    final override void write(scope const(char)[] v)
    {
        if (v is null)
            buffer.put("null");
        else
        {
            buffer.put('"');
            escapeString(buffer, v);
            buffer.put('"');
        }
    }

    final override void write(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        if (v is null)
            buffer.put("null");
        else
        {
            buffer.put('"');
            buffer.put(binaryToString(v, binaryFormat));
            buffer.put('"');
        }
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

version (unittest)
{
package(pham.utl):

    static immutable string jsonUnitTestC2 =
        q"<{"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1},"GetSet":1,"publicStr":"C2 public string"}>";

    static immutable string jsonUnitTestAllTypes =
        q"<{"enum1":"third","bool1":true,"byte1":101,"ubyte1":0,"short1":-1003,"ushort1":3975,"int1":-382653,"uint1":3957209,"long1":-394572364,"ulong1":284659274,"float1":6394763.5,"floatNaN":"NaN","double1":-2846627456445.7651,"doubleInf":"-Infinity","string1":"test string of","charArray":"will this work?","binary1":"JRjMZSs=","intArray":[135,937,3725,3068,38465,380],"intArrayNull":[],"intInt":{"2":23456,"11":113456},"intIntNull":null,"enumEnum":{"forth":"sixth","third":"second"},"strStr":{"key1":"key1 value","key2":"key2 value","key3":null},"struct1":{"publicInt":20,"publicGetSet":1},"class1":{"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1},"GetSet":1},"class1Null":null}>";

    static immutable string jsonUnitTestStd =
        q"<{"bigInt1":"-71459266416693160362545788781600","date1":"1999-01-01","dateTime1":"1999-07-06T12:30:33","sysTime1":"0001-01-01T00:00:33.0000502Z","timeOfDay1":"12:30:33","uuid1":"8ab3060e-2cba-4f23-b74c-b52db3dbfb46"}>";

    static immutable string jsonUnitTestPham =
        q"<{"bigInt1":"-71459266416693160362545788781600","date1":"1999-01-01","dateTime1":"1999-07-06T12:30:33.0000000-04:00","time1":"12:30:33.0000000-05:00"}>";

    static immutable string jsonUnitTestDec =
        q"<{"decimalNaN":"nan","decimalInfinity":"-inf","decimal32":"-7145.0","decimal64":"714583645.4","decimal128":"294574120484.87"}>";
}

unittest // JsonSerializer
{
    Serializable serializableAggregate, serializableArray;
    Serializable serializableByName = Serializable(null, EnumFormat.name);
    Serializable serializableByIntegral = Serializable(null, EnumFormat.integral);
    FloatFormat floatFormat = FloatFormat(4, true);
    BinaryFormat binaryFormat;

    scope serializer = new JsonSerializer();
    serializer.begin();
    serializer.aggregateBegin(null, -1, serializableAggregate);
    serializer.aggregateItem(0, serializableAggregate).writeKeyId("b1").writeBool(true);
    serializer.aggregateItem(1, serializableAggregate).writeKeyId("b2").writeBool(false);
    serializer.aggregateItem(2, serializableAggregate).writeKeyId("n1").write(null);
    serializer.aggregateItem(3, serializableAggregate).writeKey("f1").write(1.5, floatFormat);
    serializer.aggregateItem(4, serializableAggregate).writeKey("d1").write(100);
    serializer.aggregateItem(5, serializableAggregate).writeKey("c1").writeChar('c');
    serializer.aggregateItem(6, serializableAggregate).writeKey("s1").write("This is a string /\\");
    serializer.aggregateItem(7, serializableAggregate).writeKey("e1"); serializer.serialize(UnitTestEnum.second, serializableByName);
    serializer.aggregateItem(8, serializableAggregate).writeKey("e2"); serializer.serialize(UnitTestEnum.forth, serializableByIntegral);
    serializer.aggregateItem(9, serializableAggregate).writeKey("bin1").write([100, 101], binaryFormat);
    serializer.aggregateItem(10, serializableAggregate).writeKey("arr1");
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
    auto c = new UnitTestC2();
    scope serializer = new JsonSerializer();
    serializer.serialize!UnitTestC2(cast(UnitTestC2)(c.setValues()));

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == jsonUnitTestC2, serializer.buffer[]);
}

unittest // JsonDeserializer.UnitTestC2
{
    scope deserializer = new JsonDeserializer(jsonUnitTestC2);
    auto c = deserializer.deserialize!UnitTestC2();
    assert(c !is null);
    c.assertValues();
}

unittest // JsonSerializer.UnitTestAllTypes
{
    auto c = new UnitTestAllTypes();
    scope serializer = new JsonSerializer();
    serializer.serialize!UnitTestAllTypes(c.setValues());

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == jsonUnitTestAllTypes, serializer.buffer[]);
}

unittest // JsonDeserializer.UnitTestAllTypes
{
    scope deserializer = new JsonDeserializer(jsonUnitTestAllTypes);
    auto c = deserializer.deserialize!UnitTestAllTypes();
    assert(c !is null);
    c.assertValues();
}

unittest // JsonSerializer.UnitTestStd
{
    import pham.utl.utl_serialization_std;

    UnitTestStd c;
    scope serializer = new JsonSerializer();
    serializer.serialize!UnitTestStd(c.setValues());

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == jsonUnitTestStd, serializer.buffer[]);
}

unittest // JsonDeserializer.UnitTestStd
{
    import pham.utl.utl_serialization_std;

    scope deserializer = new JsonDeserializer(jsonUnitTestStd);
    auto c = deserializer.deserialize!UnitTestStd();
    c.assertValues();
}

unittest // JsonSerializer.UnitTestPham
{
    import pham.utl.utl_serialization_pham;

    UnitTestPham c;
    scope serializer = new JsonSerializer();
    serializer.serialize!UnitTestPham(c.setValues());

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == jsonUnitTestPham, serializer.buffer[]);
}

unittest // JsonDeserializer.UnitTestPham
{
    import pham.utl.utl_serialization_pham;

    scope deserializer = new JsonDeserializer(jsonUnitTestPham);
    auto c = deserializer.deserialize!UnitTestPham();
    c.assertValues();
}

unittest // JsonSerializer.UnitTestDec
{
    import pham.utl.utl_serialization_dec;

    UnitTestDec c;
    scope serializer = new JsonSerializer();
    serializer.serialize!UnitTestDec(c.setValues());

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == jsonUnitTestDec, serializer.buffer[]);
}

unittest // JsonDeserializer.UnitTestDec
{
    import pham.utl.utl_serialization_dec;

    scope deserializer = new JsonDeserializer(jsonUnitTestDec);
    auto c = deserializer.deserialize!UnitTestDec();
    c.assertValues();
}