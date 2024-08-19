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

module pham.ser.ser_serialization_bin;

import std.bitmanip : bigEndianToNative, nativeToBigEndian;
import std.conv : to;
import std.traits : isFloatingPoint, isIntegral, Unsigned;

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_tick : TickData;
import pham.dtm.dtm_time : Time;
import pham.utl.utl_array : Appender;
import pham.utl.utl_enum_set : EnumSet;
import pham.ser.ser_serialization;

alias BinaryLengthType = long;  // so that 32 bit client can interact with 64 bit server

static immutable ubyte[4] binaryIndicator = ['P', 'H', 'A', 'M'];
static immutable ushort binaryVersion = 1;
static immutable ubyte[2] binaryBoolValues = [0, 1];

struct BinaryIntCoder
{
    enum firstBits = 6;
    enum moreBits = 7;
    enum ubyte firstByteMask = 0x3F;
    enum ubyte moreBit = 0x80;
    enum ubyte moreByteMask = 0x7F;
    enum ubyte negativeBit = 0x40;

    static V decodeFloat(V)(scope const(ubyte)[] data, ref size_t offset) @trusted
    if (isFloatingPoint!V)
    {
        alias UV = UnsignedFloat!V;
        auto vi = decodeInt!UV(data, offset);
        return *(cast(V*)&vi);
    }

    static V decodeInt(V)(scope const(ubyte)[] data, ref size_t offset) @trusted
    if (isIntegral!V)
    {
        alias UV = Unsigned!V;
        int counter = 1, shift = 0;
        ubyte lowerBits = data[offset++];
        const isNegative = (lowerBits & negativeBit) != 0;
        UV result = lowerBits & firstByteMask;
        while ((lowerBits & moreBit) != 0 && offset < data.length)
        {
            shift = counter == 1 ? firstBits : (shift + moreBits);
            lowerBits = data[offset++];
            result |= (cast(UV)(lowerBits & moreByteMask)) << shift;
            counter++;
        }
        result = isNegative ? cast(UV)~result : result;
        return *(cast(V*)&result);
    }

    static size_t encodeFloat(V, Writer)(ref Writer sink, V v) @trusted
    if (isFloatingPoint!V)
    {
        alias UV = UnsignedFloat!V;
        return encodeInt!(UV, Writer)(sink, *(cast(UV*)&v));
    }

    static size_t encodeInt(V, Writer)(ref Writer sink, V v) @trusted
    if (isIntegral!V)
    {
        alias UV = Unsigned!V;
        const isNegative = v < 0;
        auto ev = *(cast(UV*)&v);
        if (isNegative)
            ev = cast(UV)~ev;

        size_t result;

        // First 6 bits
        ubyte lowerBits = cast(ubyte)(ev & firstByteMask);
        ev >>= firstBits;
        if (ev)
            lowerBits |= moreBit;
        if (isNegative)
            lowerBits |= negativeBit;
        sink.put(lowerBits);
        result++;

        // The rest with 7 bits
        while (ev)
        {
            lowerBits = cast(ubyte)(ev & moreByteMask);
            ev >>= moreBits;
            if (ev)
                lowerBits |= moreBit;
            sink.put(lowerBits);
            result++;
        }

        return result;
    }
}

class BinaryDeserializer : Deserializer
{
@safe:

public:
    this(const(ubyte)[] data)
    {
        this.data = data;
    }

    override BinaryDeserializer begin(scope ref Serializable attribute)
    {
        offset = 0;
        version_ = 0;

        checkDataLength(binaryIndicator.length);
        if (data[0..binaryIndicator.length] != binaryIndicator)
            throw new DeserializerException("Not a binary serialization stream");
        offset += binaryIndicator.length;

        checkDataLength(ushort.sizeof);
        ubyte[ushort.sizeof] v = data[offset..offset+ushort.sizeof];
        version_ = bigEndianToNative!(ushort, ushort.sizeof)(v);
        offset += ushort.sizeof;

        return cast(BinaryDeserializer)super.begin(attribute);
    }

    override BinaryDeserializer end(scope ref Serializable attribute)
    {
        return cast(BinaryDeserializer)super.end(attribute);
    }
    
    final override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.aggregateBegin, 2);
        super.aggregateBegin(typeName, attribute);
        return readLength();
    }

    final override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.aggregateEnd, 1);
        super.aggregateEnd(typeName, length, attribute);
    }

    final override ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.arrayBegin, 2);
        super.arrayBegin(elemTypeName, attribute);
        return readLength();
    }

    final override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.arrayEnd, 1);
        super.arrayEnd(elemTypeName, length, attribute);
    }

    final override Null readNull(scope ref Serializable)
    {
        checkDataType(SerializerDataType.null_, 1);
        return null;
    }

    final override bool readBool(scope ref Serializable)
    {
        checkDataType(SerializerDataType.bool_, 2);
        return data[offset++] == binaryBoolValues[true];
    }

    final override char readChar(scope ref Serializable)
    {
        checkDataType(SerializerDataType.char_, 2);
        return cast(char)data[offset++];
    }

    final override Date readDate(scope ref Serializable)
    {
        checkDataType(SerializerDataType.date, 2);
        const days = BinaryIntCoder.decodeInt!int(data, offset);
        return Date(days);
    }

    final override DateTime readDateTime(scope ref Serializable)
    {
        static assert(TickData.data.sizeof == ulong.sizeof);

        checkDataType(SerializerDataType.dateTime, 2);
        const raw = BinaryIntCoder.decodeInt!ulong(data, offset);
        return DateTime(TickData(raw));
    }

    final override Time readTime(scope ref Serializable)
    {
        static assert(TickData.data.sizeof == ulong.sizeof);

        checkDataType(SerializerDataType.time, 2);
        const raw = BinaryIntCoder.decodeInt!ulong(data, offset);
        return Time(TickData(raw));
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
        static assert(V.sizeof <= long.sizeof);
        
        static if (V.sizeof == long.sizeof)
            static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.int8, SerializerDataType.int4, SerializerDataType.int2, SerializerDataType.int1]);
        else static if (V.sizeof == int.sizeof)
            static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.int4, SerializerDataType.int2, SerializerDataType.int1]);
        else static if (V.sizeof == short.sizeof)
            static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.int2, SerializerDataType.int1]);
        else //static if (V.sizeof == byte.sizeof)
            static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.int1]);

        return readInt!V(checkDataType(checkTypes, 2));
    }

    private final V readInt(V)(const(SerializerDataType) t)
    if (isIntegral!V)
    {
        static assert(V.sizeof <= long.sizeof);
        
        static if (V.sizeof >= long.sizeof)
        if (t == SerializerDataType.int8)
            return BinaryIntCoder.decodeInt!long(data, offset);

        static if (V.sizeof >= int.sizeof)
        if (t == SerializerDataType.int4)
            return BinaryIntCoder.decodeInt!int(data, offset);

        static if (V.sizeof >= short.sizeof)
        if (t == SerializerDataType.int2)
            return BinaryIntCoder.decodeInt!short(data, offset);

        assert(t == SerializerDataType.int1);
        return cast(byte)data[offset++];
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
        static if (V.sizeof == long.sizeof)
            static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.float8, SerializerDataType.float4, SerializerDataType.int8, SerializerDataType.int4, SerializerDataType.int2, SerializerDataType.int1]);
        else static if (V.sizeof == int.sizeof)
            static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.float4, SerializerDataType.int4, SerializerDataType.int2, SerializerDataType.int1]);
        else
            static assert(0, "Unsupport float type " ~ V.stringof);

        const t = checkDataType(checkTypes, 2);

        static if (V.sizeof == long.sizeof)
            return t == SerializerDataType.float8
                ? BinaryIntCoder.decodeFloat!double(data, offset)
                : (t == SerializerDataType.float4
                    ? BinaryIntCoder.decodeFloat!float(data, offset)
                    : cast(V)readInt!long(t));
        else static if (V.sizeof == int.sizeof)
            return t == SerializerDataType.float4
                ? BinaryIntCoder.decodeFloat!float(data, offset)
                : cast(V)readInt!int(t);
        else
            static assert(0, "Unsupport float type " ~ V.stringof);
    }

    final override string readChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto chars = readScopeChars(attribute, kind);
        return chars.length ? cast(string)chars.idup : null;
    }

    final override wstring readWChars(scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.wchars, SerializerDataType.chars, SerializerDataType.null_]);
        auto chars = cast(const(char)[])readScopeBytes(checkTypes);
        return chars.length ? chars.to!wstring : null;
    }

    final override dstring readDChars(scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.dchars, SerializerDataType.wchars, SerializerDataType.chars, SerializerDataType.null_]);
        auto chars = cast(const(char)[])readScopeBytes(checkTypes);
        return chars.length ? chars.to!dstring : null;
    }

    final override const(char)[] readScopeChars(scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.chars, SerializerDataType.null_]);
        return cast(const(char)[])readScopeBytes(checkTypes);
    }

    final override ubyte[] readBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        auto bytes = readScopeBytes(attribute, kind);
        return bytes.length ? bytes.dup : null;
    }

    final override const(ubyte)[] readScopeBytes(scope ref Serializable, const(DataKind) kind = DataKind.binary)
    {
        static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType([SerializerDataType.bytes, SerializerDataType.null_]);
        return readScopeBytes(checkTypes);
    }

    final const(ubyte)[] readScopeBytes(scope const(EnumSet!SerializerDataType) dataTypes)
    {
        const t = checkDataType(dataTypes, 2);
        if (t == SerializerDataType.null_)
            return null;

        if (const len = readLength())
        {
            checkDataLength(len);
            const beginOffset = offset;
            offset += len;
            return data[beginOffset..offset];
        }
        else
            return null;
    }

    final override string readKey(size_t)
    {
        static immutable EnumSet!SerializerDataType checkTypes = EnumSet!SerializerDataType(SerializerDataType.charsKey);
        return (cast(const(char)[])readScopeBytes(checkTypes)).idup;
    }

    final ptrdiff_t readLength()
    {
        checkDataLength(1);
        return cast(ptrdiff_t)BinaryIntCoder.decodeInt!BinaryLengthType(data, offset);
    }

public:
    pragma(inline, true)
    final void checkDataLength(const(size_t) bytes)
    {
        if (offset + bytes > data.length)
            throw new DeserializerException("EOS - expect length " ~ bytes.to!string ~ " at offset " ~ offset.to!string ~ " with size " ~ data.length.to!string);
    }

    final SerializerDataType checkDataType(const(SerializerDataType) dataType, const(size_t) bytes)
    {
        checkDataLength(bytes);

        const t = cast(SerializerDataType)data[offset];
        if (t != dataType)
            throw new DeserializerException("Expect datatype " ~ dataType.to!string ~ " but found " ~ t.to!string);
        offset++; // Skip type
        return t;
    }

    final SerializerDataType checkDataType(scope const(EnumSet!SerializerDataType) dataTypes, const(size_t) bytes)
    {
        checkDataLength(bytes);

        const t = cast(SerializerDataType)data[offset];
        if (dataTypes.isOff(t))
            throw new DeserializerException("Expect one of datatypes " ~ dataTypes.toString() ~ " but found " ~ t.to!string);
        offset++; // Skip type
        return t;
    }

    final override bool hasArrayEle(size_t i, ptrdiff_t len)
    {
        return offset < data.length && data[offset] != SerializerDataType.arrayEnd;
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len)
    {
        return offset < data.length && data[offset] != SerializerDataType.aggregateEnd;
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.binary;
    }

public:
    const(ubyte)[] data;
    size_t offset;
    ushort version_;
}

class BinarySerializer : Serializer
{
@safe:

public:
    override BinarySerializer begin(scope ref Serializable attribute)
    {
        const v = nativeToBigEndian(binaryVersion);
        buffer.clear();
        buffer.capacity = bufferCapacity;
        buffer.put(binaryIndicator[]);
        buffer.put(v[]);
        return cast(BinarySerializer)super.begin(attribute);
    }

    override BinarySerializer end(scope ref Serializable attribute)
    {
        return cast(BinarySerializer)super.end(attribute);
    }

    final override void aggregateBegin(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put(SerializerDataType.aggregateBegin);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, length);
        super.aggregateBegin(typeName, length, attribute);
    }

    final override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put(SerializerDataType.aggregateEnd);
        super.aggregateEnd(typeName, length, attribute);
    }

    final override void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put(SerializerDataType.arrayBegin);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, length);
        super.arrayBegin(elemTypeName, length, attribute);
    }

    final override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        buffer.put(SerializerDataType.arrayEnd);
        super.arrayEnd(elemTypeName, length, attribute);
    }

    final override void write(Null, scope ref Serializable)
    {
        buffer.put(SerializerDataType.null_);
    }

    final override void writeBool(bool v, scope ref Serializable)
    {
        buffer.put(SerializerDataType.bool_);
        buffer.put(binaryBoolValues[v]);
    }

    final override void writeChar(char v, scope ref Serializable)
    {
        buffer.put(SerializerDataType.char_);
        buffer.put(cast(ubyte)v);
    }

    final override void write(scope const(Date) v, scope ref Serializable)
    {
        buffer.put(SerializerDataType.date);
        BinaryIntCoder.encodeInt!int(buffer, v.days);
    }

    final override void write(scope const(DateTime) v, scope ref Serializable)
    {
        static assert(TickData.data.sizeof == ulong.sizeof);

        buffer.put(SerializerDataType.dateTime);
        BinaryIntCoder.encodeInt!ulong(buffer, v.raw.data);
    }

    final override void write(scope const(Time) v, scope ref Serializable)
    {
        static assert(TickData.data.sizeof == ulong.sizeof);

        buffer.put(SerializerDataType.time);
        BinaryIntCoder.encodeInt!ulong(buffer, v.raw.data);
    }

    final override void write(byte v, scope ref Serializable)
    {
        buffer.put(SerializerDataType.int1);
        buffer.put(cast(ubyte)v);
    }

    final override void write(short v, scope ref Serializable)
    {
        buffer.put(SerializerDataType.int2);
        BinaryIntCoder.encodeInt!short(buffer, v);
    }

    final override void write(int v, scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        buffer.put(SerializerDataType.int4);
        BinaryIntCoder.encodeInt!int(buffer, v);
    }

    final override void write(long v, scope ref Serializable, const(DataKind) kind = DataKind.integral)
    {
        buffer.put(SerializerDataType.int8);
        BinaryIntCoder.encodeInt!long(buffer, v);
    }

    final override void write(float v, scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        buffer.put(SerializerDataType.float4);
        BinaryIntCoder.encodeFloat!float(buffer, v);
    }

    final override void write(double v, scope ref Serializable, const(DataKind) kind = DataKind.decimal)
    {
        buffer.put(SerializerDataType.float8);
        BinaryIntCoder.encodeFloat!double(buffer, v);
    }

    final override void write(scope const(char)[] v, scope ref Serializable, const(DataKind) kind = DataKind.character) @trusted
    {
        const vlength = v.length;
        buffer.put(SerializerDataType.chars);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, vlength);
        if (vlength)
            buffer.put(cast(const(ubyte)[])v);
    }

    final override void write(scope const(wchar)[] v, scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        buffer.put(SerializerDataType.wchars);
        if (v.length)
        {
            auto v2 = v.to!string;
            BinaryIntCoder.encodeInt!BinaryLengthType(buffer, v2.length);
            buffer.put(cast(const(ubyte)[])v2);
        }
        else
            BinaryIntCoder.encodeInt!BinaryLengthType(buffer, 0U);
    }

    final override void write(scope const(dchar)[] v, scope ref Serializable, const(DataKind) kind = DataKind.character)
    {
        buffer.put(SerializerDataType.dchars);
        if (v.length)
        {
            auto v2 = v.to!string;
            BinaryIntCoder.encodeInt!BinaryLengthType(buffer, v2.length);
            buffer.put(cast(const(ubyte)[])v2);
        }
        else
            BinaryIntCoder.encodeInt!BinaryLengthType(buffer, 0U);
    }

    final override void write(scope const(ubyte)[] v, scope ref Serializable, const(DataKind) kind = DataKind.binary)
    {
        const vlength = v.length;
        buffer.put(SerializerDataType.bytes);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, vlength);
        if (vlength)
            buffer.put(v);
    }

    final override Serializer writeKey(scope ref Serializable attribute) @trusted
    {
        auto key = attribute.name;
        buffer.put(SerializerDataType.charsKey);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, key.length);
        if (key.length)
            buffer.put(cast(const(ubyte)[])key);
        return this;
    }

    final override Serializer writeKeyId(scope ref Serializable attribute)
    {
        return writeKey(attribute);
    }

public:
    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.binary;
    }

public:
    Appender!(ubyte[]) buffer;
    size_t bufferCapacity = 1_000 * 16;
}


private:

unittest // BinaryIntCoder.encodeInt & decodeInt
{
    import std.digest : toHexString;
    import std.stdio : writefln;

    Appender!(ubyte[]) buffer;
    size_t offset;

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeInt!short(buffer, 22_826); //debug writefln("%s", toHexString(buffer[]));
    const i2 = BinaryIntCoder.decodeInt!short(buffer[], offset); //debug writefln("%x", i2);
    assert(i2 == 22_826);

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeInt!uint(buffer, 0x0FFF1A); //debug writefln("%s", toHexString(buffer[]));
    const i4 = BinaryIntCoder.decodeInt!uint(buffer[], offset); //debug writefln("%x", i4);
    assert(i4 == 0x0FFF1A);

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeInt!long(buffer, -83_659_374_736_539L); //debug writefln("%s", toHexString(buffer[]));
    const i8 = BinaryIntCoder.decodeInt!long(buffer[], offset); //debug writefln("%s", i8);
    assert(i8 == -83_659_374_736_539L);
}

unittest // BinaryIntCoder.encodeFloat & decodeFloat
{
    import std.digest : toHexString;
    import std.stdio : writefln;

    Appender!(ubyte[]) buffer;
    size_t offset;

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeFloat!float(buffer, 1_826.22f); //debug writefln("%s", toHexString(buffer[]));
    auto f4 = BinaryIntCoder.decodeFloat!float(buffer[], offset); //debug writefln("%x", i2);
    assert(f4 == 1_826.22f);

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeFloat!float(buffer, -1_826.22f); //debug writefln("%s", toHexString(buffer[]));
    f4 = BinaryIntCoder.decodeFloat!float(buffer[], offset); //debug writefln("%x", i2);
    assert(f4 == -1_826.22f);

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeFloat!double(buffer, 9_877_631_826.22); //debug writefln("%s", toHexString(buffer[]));
    auto f8 = BinaryIntCoder.decodeFloat!double(buffer[], offset); //debug writefln("%x", i2);
    assert(f8 == 9_877_631_826.22);

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeFloat!double(buffer, -9_877_631_826.22); //debug writefln("%s", toHexString(buffer[]));
    f8 = BinaryIntCoder.decodeFloat!double(buffer[], offset); //debug writefln("%x", i2);
    assert(f8 == -9_877_631_826.22);

    offset = 0;
    buffer.clear();
    BinaryIntCoder.encodeFloat!double(buffer, -1.1); //debug writefln("%s", toHexString(buffer[]));
    f8 = BinaryIntCoder.decodeFloat!double(buffer[], offset); //debug writefln("%x", i2);
    assert(f8 == -1.1);
}

unittest // BinarySerializer.UnitTestC2
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;

    static immutable string binUnitTestC2 =
        "5048414D000116401203496E74081E120C7075626C6963537472756374164012097075626C6963496E740814120C7075626C69634765745365740801171206476574536574080112097075626C696353747211104332207075626C696320737472696E6717";

    {
        auto c = new UnitTestC2();
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestC2(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestC2, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestC2));
        auto c = deserializer.deserialize!UnitTestC2();
        assert(c !is null);
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestAllTypes
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;

    static immutable string binUnitTestAllTypes =
        "5048414D000116401205656E756D31110574686972641205626F6F6C31020112056279746531066512067562797465310600120673686F72743107EA0F12077573686F72743107873E1204696E743108FCDA2E120575696E7431089987E30312056C6F6E673109CBC9A5F8021206756C6F6E6731098AB9BC8F021206666C6F6174310C979C99AC091208666C6F61744E614E0C808080FC0F1207646F75626C65310D9FB8EFF2B790DB8485031209646F75626C65496E660D80808080808080F0FF011207737472696E6731110E7465737420737472696E67206F661209636861724172726179110F77696C6C207468697320776F726B3F120762696E6172793115052518CC652B1208696E744172726179180608870208A90E088D3A08BC2F0881D90408BC0519120C696E7441727261794E756C6C1800191206696E74496E74160212013208A0EE021202313108B0EC0D17120A696E74496E744E756C6C1600171208656E756D456E756D16021205666F727468110573697874681205746869726411067365636F6E64171206737472537472160312046B657931110A6B6579312076616C756512046B657932110A6B6579322076616C756512046B657933110017120773747275637431164012097075626C6963496E740814120C7075626C69634765745365740801171206636C6173733116401203496E74081E120C7075626C6963537472756374164012097075626C6963496E740814120C7075626C69634765745365740801171206476574536574080117120A636C617373314E756C6C16001717";

    {
        auto c = new UnitTestAllTypes();
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestAllTypes(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestAllTypes, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestAllTypes));
        auto c = deserializer.deserialize!UnitTestAllTypes();
        assert(c !is null);
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestStdBigInt
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    import pham.ser.ser_std_bigint;

    static immutable string binUnitTestStdBigInt =
        "5048414D000116401207626967496E743111212D373134353932363634313636393331363033363235343537383837383136303017";

    {
        UnitTestStdBigInt c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestStdBigInt(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestStdBigInt, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestStdBigInt));
        auto c = deserializer.deserialize!UnitTestStdBigInt();
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestStdDateTime
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    import pham.ser.ser_std_date_time;

    static immutable string binUnitTestStdDateTime =
        "5048414D0001164012056461746531039A8A5912096461746554696D65310480EAAB9BCFF0CAC011120873797354696D653104B6A1DBBA828080808001120A74696D654F66446179310580EA939C9B1A17";

    {
        UnitTestStdDateTime c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestStdDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestStdDateTime, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestStdDateTime));
        auto c = deserializer.deserialize!UnitTestStdDateTime();
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestStdUuid
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    import pham.ser.ser_std_uuid;

    static immutable string binUnitTestStdUuid =
        "5048414D000116401205757569643115108AB3060E2CBA4F23B74CB52DB3DBFB4617";

    {
        UnitTestStdUuid c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestStdUuid(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestStdUuid, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestStdUuid));
        auto c = deserializer.deserialize!UnitTestStdUuid();
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestPhamBigInteger
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    import pham.ser.ser_pham_big_integer;

    static immutable string binUnitTestPhamBigInteger =
        "5048414D000116401207626967496E7431150EE07B47572A79980A9C3BA80E7AFC17";

    {
        UnitTestPhamBigInteger c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestPhamBigInteger(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestPhamBigInteger, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestPhamBigInteger));
        auto c = deserializer.deserialize!UnitTestPhamBigInteger();
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestPhamDateTime
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;

    static immutable string binUnitTestPhamDateTime =
        "5048414D0001164012056461746531039A8A5912096461746554696D65310480EAAB9BCFF0CAC09101120574696D65310580EA939C9B9A8080800117";

    {
        UnitTestPhamDateTime c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestPhamDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestPhamDateTime, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestPhamDateTime));
        auto c = deserializer.deserialize!UnitTestPhamDateTime();
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestDecDecimal
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    import pham.ser.ser_dec_decimal;

    static immutable string binUnitTestDecDecimal =
        "5048414D00011640120A646563696D616C4E614E15047C000000120F646563696D616C496E66696E6974791504F80000001209646563696D616C33321504B2801BE91209646563696D616C3634150831800010A3401C7C120A646563696D616C3132381510303C00000000000000001ACA9694C66717";

    {
        UnitTestDecDecimal c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestDecDecimal(c.setValues());
        //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestDecDecimal, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestDecDecimal));
        auto c = deserializer.deserialize!UnitTestDecDecimal();
        c.assertValues();
    }
}

unittest // BinarySerializer.UnitTestCustomS1
{
    import std.digest : toHexString;
    import pham.utl.utl_object : bytesToHexs;

    const(ubyte)[] binCustom;

    {
        UnitTestCustomS1 c;
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestCustomS1(c.setValues());
        binCustom = serializer.buffer[];
        //import std.stdio : writeln; debug writeln(bytesToHexs(binCustom));
        assert(bytesToHexs(serializer.buffer[]) == toHexString(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(binCustom);
        auto c2 = deserializer.deserialize!UnitTestCustomS1();
        c2.assertValues();
    }
}
