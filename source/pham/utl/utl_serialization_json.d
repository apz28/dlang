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
import std.traits : isDynamicArray, isFloatingPoint, isIntegral;
import pham.utl.utl_serialization;

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

    final override Serializer aggregateBegin(string typeName, ptrdiff_t length)
    {
        buffer.put('{');
        return super.aggregateBegin(typeName, length);
    }

    final override Serializer aggregateEnd(string typeName, ptrdiff_t length)
    {
        buffer.put('}');
        return super.aggregateEnd(typeName, length);
    }

    final override Serializer aggregateItem(ptrdiff_t length)
    {
        if (length)
            buffer.put(',');
        return super.aggregateItem(length);
    }
    
    final override Serializer arrayBegin(string elemTypeName, ptrdiff_t length)
    {
        buffer.put('[');
        return super.arrayBegin(elemTypeName, length);
    }

    final override Serializer arrayEnd(string elemTypeName, ptrdiff_t length)
    {
        buffer.put(']');
        return super.arrayEnd(elemTypeName, length);
    }

    final override Serializer arrayItem(ptrdiff_t length)
    {
        if (length)
            buffer.put(',');
        return super.arrayItem(length);
    }

    final override void put(typeof(null))
    {
        buffer.put("null");
    }

    static immutable string[2] boolValues = ["false", "true"];
    final override void putBool(bool v)
    {
        buffer.put(boolValues[v]);
    }

    final override void putChar(char v)
    {
        char[1] s = [v];
        put(s[]);
    }
    
    final override void put(byte v)
    {
        putIntImpl(v);
    }

    final override void put(short v)
    {
        putIntImpl(v);
    }

    final override void put(int v)
    {
        putIntImpl(v);
    }

    final override void put(long v)
    {
        putIntImpl(v);
    }
    
    final override void put(float v, const(FloatFormat) floatFormat)
    {
        putFloatImpl(v, floatFormat);
    }

    final override void put(double v, const(FloatFormat) floatFormat)
    {
        putFloatImpl(v, floatFormat);
    }

    final override void put(scope const(char)[] v)
    {
        buffer.put('"');
        escapeString(buffer, v);
        buffer.put('"');
    }

    final override void put(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        buffer.put('"');
        buffer.put(binaryToString(v, binaryFormat));
        buffer.put('"');
    }

    final override Serializer putKey(scope const(char)[] key)
    {
        buffer.put('"');
        escapeString(buffer, key);
        buffer.put('"');
        buffer.put(':');
        return this;
    }

    final override Serializer putKeyId(scope const(char)[] key)
    {
        buffer.put('"');
        buffer.put(key);
        buffer.put('"');
        buffer.put(':');
        return this;
    }

    @property final override SerializerDataType dataType() const @nogc nothrow pure
    {
        return SerializerDataType.text;
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

    final void putIntImpl(V)(V v)
    if (isIntegral!V)
    {
        char[50] vBuffer = void;
        buffer.put(intToString(vBuffer[], v));
    }

    final void putFloatImpl(V)(V v, const(FloatFormat) floatFormat)
    if (isFloatingPoint!V)
    {
        char[80] vBuffer = void;
        buffer.put(floatToString(vBuffer[], v, floatFormat));
    }

public:
    Appender!string buffer;
    size_t bufferCapacity = 4_000 * 4;
}

unittest // JsonSerializer
{
    enum E { e1, e2, e3 }
    Serializable serializableByName = Serializable(null, EnumFormat.name);
    Serializable serializableByIntegral = Serializable(null, EnumFormat.integral);
    FloatFormat floatFormat = FloatFormat(4, true);
    BinaryFormat binaryFormat;

    scope serializer = new JsonSerializer();
    serializer.begin();
    serializer.aggregateBegin(null, -1);
    serializer.aggregateItem(0).putKeyId("b1").putBool(true);
    serializer.aggregateItem(1).putKeyId("b2").putBool(false);
    serializer.aggregateItem(2).putKeyId("n1").put(null);
    serializer.aggregateItem(3).putKey("f1").put(1.5, floatFormat);
    serializer.aggregateItem(4).putKey("d1").put(100);
    serializer.aggregateItem(5).putKey("c1").putChar('c');
    serializer.aggregateItem(6).putKey("s1").put("This is a string /\\");
    serializer.aggregateItem(7).putKey("e1"); serializer.serialize(E.e1, serializableByName);
    serializer.aggregateItem(8).putKey("e2"); serializer.serialize(E.e2, serializableByIntegral);
    serializer.aggregateItem(9).putKey("bin1").put([100, 101], binaryFormat);
    serializer.aggregateItem(10).putKey("arr1");
    serializer.arrayBegin(null, 2);
    serializer.arrayItem(0).put(200);
    serializer.arrayItem(1).put(201);
    serializer.arrayEnd(null, 2);
    serializer.aggregateEnd(null, 11);
    serializer.end();

    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == q"<{"b1":true,"b2":false,"n1":null,"f1":1.5,"d1":100,"c1":"c","s1":"This is a string \/\\","e1":"e1","e2":1,"bin1":"ZGU=","arr1":[200,201]}>", serializer.buffer[]);
}

unittest // JsonSerializer
{
    auto c = new UnitTestC2();
    scope serializer = new JsonSerializer();
    serializer.begin();
    serializer.serialize!UnitTestC2(cast(UnitTestC2)(c.setValues()));
    serializer.end();
    
    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == q"<{"publicStr":"C2 public string","GetSet":11,"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1}}>", serializer.buffer[]);
}

unittest // JsonSerializer
{
    auto c = new UnitTestAllTypes();
    scope serializer = new JsonSerializer();
    serializer.begin();
    serializer.serialize!UnitTestAllTypes(c.setValues());
    serializer.end();
    
    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == q"<{"enum1":"third","bool1":true,"byte1":101,"ubyte1":0,"short1":-1003,"ushort1":3975,"int1":-382653,"uint1":3957209,"long1":-394572364,"ulong1":284659274,"float1":6394763.5,"floatNaN":nan,"double1":-2846627456445.7651,"doubleInf":-inf,"string1":"test string of","charArray":"will this work?","binary1":"JRjMZSs=","intArray":[135,937,3725,3068,38465,380],"intArrayNull":null,"intInt":{"2":23456,"11":113456},"intIntNull":null,"enumEnum":{"forth":"sixth","third":"second"},"strStr":{"key1":"key1 value","key2":"key2 value","key3":null},"struct1":{"publicInt":20,"publicGetSet":1},"class1":{"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1},"GetSet":1},"class1Null":null}>", serializer.buffer[]);
}

unittest // JsonSerializer
{
    import pham.utl.utl_serialization_std;
    
    UnitTestStd c;
    scope serializer = new JsonSerializer();
    serializer.begin();
    serializer.serialize!UnitTestStd(c.setValues());
    serializer.end();
    
    //import std.stdio : writeln; debug writeln(serializer.buffer[]);
    assert(serializer.buffer[] == q"<{"bigInt1":"-71459266416693160362545788781600","sysTime1":"0001-01-01T00:00:33.0000502Z","uuid1":"8ab3060e-2cba-4f23-b74c-b52db3dbfb46"}>", serializer.buffer[]);
}