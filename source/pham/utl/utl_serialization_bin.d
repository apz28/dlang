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

module pham.utl.utl_serialization_bin;

import std.array : Appender, appender;
import std.bitmanip : bigEndianToNative, nativeToBigEndian;
import std.traits : isFloatingPoint, isIntegral, Unsigned;
import pham.utl.utl_serialization;

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

    override Deserializer begin()
    {
        offset = 0;
        version_ = 0;

        checkDataType(SerializerDataType.unknown, binaryIndicator.length);
        if (data[0..binaryIndicator.length] != binaryIndicator)
            throw new DeserializerException("Not a binary data stream");
        offset += binaryIndicator.length;

        checkDataType(SerializerDataType.unknown, ushort.sizeof);
        ubyte[ushort.sizeof] v = data[offset..offset+ushort.sizeof];
        version_ = bigEndianToNative!(ushort, ushort.sizeof)(v);
        offset += ushort.sizeof;

        return super.begin();
    }

    override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.aggregateBegin, 2);
        super.aggregateBegin(typeName, attribute);
        return readLength();
    }

    override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.aggregateEnd, 1);
        super.aggregateEnd(typeName, length, attribute);
    }

    override ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.arrayBegin, 2);
        super.arrayBegin(elemTypeName, attribute);
        return readLength();
    }

    override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        checkDataType(SerializerDataType.arrayEnd, 1);
        super.arrayEnd(elemTypeName, length, attribute);
    }

    final override Null readNull()
    {
        checkDataType(SerializerDataType.null_, 1);
        return null;
    }

    final override bool readBool()
    {
        checkDataType(SerializerDataType.bool_, 2);
        return data[offset++] == binaryBoolValues[true];
    }

    final override char readChar()
    {
        checkDataType(SerializerDataType.char_, 2);
        return cast(char)data[offset++];
    }

    final override byte readByte()
    {
        checkDataType(SerializerDataType.int1, 2);
        return cast(byte)data[offset++];
    }

    final override short readShort()
    {
        checkDataType(SerializerDataType.int2, 2);
        return BinaryIntCoder.decodeInt!short(data, offset);
    }

    final override int readInt()
    {
        checkDataType(SerializerDataType.int4, 2);
        return BinaryIntCoder.decodeInt!int(data, offset);
    }

    final override long readLong()
    {
        checkDataType(SerializerDataType.int8, 2);
        return BinaryIntCoder.decodeInt!long(data, offset);
    }

    final override float readFloat(const(FloatFormat) floatFormat)
    {
        checkDataType(SerializerDataType.float4, 2);
        return BinaryIntCoder.decodeFloat!float(data, offset);
    }

    final override double readDouble(const(FloatFormat) floatFormat)
    {
        checkDataType(SerializerDataType.float8, 2);
        return BinaryIntCoder.decodeFloat!double(data, offset);
    }

    final override string readChars() @trusted
    {
        return cast(string)readScopeChars().idup;
    }

    final override const(char)[] readScopeChars() @trusted
    {
        const t = checkDataType(SerializerDataType.chars, 2);
        if (t == SerializerDataType.null_)
            return null;
            
        if (const len = readLength())
        {
            checkDataType(SerializerDataType.unknown, len);
            const cOffset = offset;
            offset += len;
            return cast(const(char)[])data[cOffset..offset];
        }
        else
            return null;
    }

    final override ubyte[] readBytes(const(BinaryFormat) binaryFormat)
    {
        return readScopeBytes(binaryFormat).dup;
    }

    final override const(ubyte)[] readScopeBytes(const(BinaryFormat) binaryFormat)
    {
        const t = checkDataType(SerializerDataType.bytes, 2);
        if (t == SerializerDataType.null_)
            return null;
            
        if (const len = readLength())
        {
            checkDataType(SerializerDataType.unknown, len);
            const cOffset = offset;
            offset += len;
            return data[cOffset..offset];
        }
        else
            return null;
    }

    final override string readKey() @trusted
    {
        checkDataType(SerializerDataType.charsKey, 2);
        if (const len = readLength())
        {
            checkDataType(SerializerDataType.unknown, len);
            const cOffset = offset;
            offset += len;
            return cast(string)data[cOffset..offset].idup;
        }
        else
            return null;
    }

    final override ptrdiff_t readLength()
    {
        checkDataType(SerializerDataType.unknown, 1);
        return cast(ptrdiff_t)BinaryIntCoder.decodeInt!BinaryLengthType(data, offset);
    }

public:
    final SerializerDataType checkDataType(const(SerializerDataType) dataType, const(size_t) bytes)
    {
        import std.conv : to;
        
        if (offset + bytes > data.length)
            throw new DeserializerException("EOS - expect length " ~ bytes.to!string ~ " at offset " ~ offset.to!string ~ " with size " ~ data.length.to!string);
            
        if (dataType != SerializerDataType.unknown)
        {
            const t = cast(SerializerDataType)data[offset];
            if (!(t == dataType || (t == SerializerDataType.null_ && !isNullableDataType(dataType))))
                throw new DeserializerException("Expect datatype " ~ dataType.to!string ~ " but found " ~ t.to!string);
            offset++;
            return t;
        }
        
        return SerializerDataType.unknown;
    }

    final override bool empty() nothrow
    {
        return offset >= data.length;
    }

    final override SerializerDataType frontDataType() nothrow
    in
    {
        assert(!empty());
    }
    do
    {
        return cast(SerializerDataType)data[offset];
    }

    final override bool hasArrayEle(size_t i, ptrdiff_t len) nothrow
    {
        return offset < data.length && data[offset] != SerializerDataType.arrayEnd;
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len) nothrow
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
    override Serializer begin()
    {
        const v = nativeToBigEndian(binaryVersion);
        buffer = appender!(ubyte[])();
        buffer.reserve(bufferCapacity);
        buffer.put(binaryIndicator[]);
        buffer.put(v[]);
        return super.begin();
    }

    override void aggregateBegin(string typeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        buffer.put(SerializerDataType.aggregateBegin);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, length);
        super.aggregateBegin(typeName, length, serializable);
    }

    override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        buffer.put(SerializerDataType.aggregateEnd);
        super.aggregateEnd(typeName, length, serializable);
    }

    override void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        buffer.put(SerializerDataType.arrayBegin);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, length);
        super.arrayBegin(elemTypeName, length, serializable);
    }

    override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable serializable)
    {
        buffer.put(SerializerDataType.arrayEnd);
        super.arrayEnd(elemTypeName, length, serializable);
    }

    final override void write(Null)
    {
        buffer.put(SerializerDataType.null_);
    }

    final override void writeBool(bool v)
    {
        buffer.put(SerializerDataType.bool_);
        buffer.put(binaryBoolValues[v]);
    }

    final override void writeChar(char v)
    {
        buffer.put(SerializerDataType.char_);
        buffer.put(cast(ubyte)v);
    }

    final override void write(byte v)
    {
        buffer.put(SerializerDataType.int1);
        buffer.put(cast(ubyte)v);
    }

    final override void write(short v)
    {
        buffer.put(SerializerDataType.int2);
        BinaryIntCoder.encodeInt!short(buffer, v);
    }

    final override void write(int v)
    {
        buffer.put(SerializerDataType.int4);
        BinaryIntCoder.encodeInt!int(buffer, v);
    }

    final override void write(long v)
    {
        buffer.put(SerializerDataType.int8);
        BinaryIntCoder.encodeInt!long(buffer, v);
    }

    final override void write(float v, const(FloatFormat) floatFormat)
    {
        buffer.put(SerializerDataType.float4);
        BinaryIntCoder.encodeFloat!float(buffer, v);
    }

    final override void write(double v, const(FloatFormat) floatFormat)
    {
        buffer.put(SerializerDataType.float8);
        BinaryIntCoder.encodeFloat!double(buffer, v);
    }

    final override void write(scope const(char)[] v) @trusted
    {
        buffer.put(SerializerDataType.chars);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, v.length);
        if (v.length)
            buffer.put(cast(ubyte[])v);
    }

    final override void write(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        buffer.put(SerializerDataType.bytes);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, v.length);
        if (v.length)
            buffer.put(v);
    }

    final override Serializer writeKey(scope const(char)[] key) @trusted
    {
        buffer.put(SerializerDataType.charsKey);
        BinaryIntCoder.encodeInt!BinaryLengthType(buffer, key.length);
        if (key.length)
            buffer.put(cast(ubyte[])key);
        return this;
    }

    final override Serializer writeKeyId(scope const(char)[] key)
    {
        return writeKey(key);
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

version (unittest)
{
package(pham.utl):

    static immutable string binUnitTestC2 =
        "5048414D000111400F03496E74051E0F0C7075626C696353747275637411400F097075626C6963496E7405140F0C7075626C69634765745365740501120F0647657453657405010F097075626C69635374720E104332207075626C696320737472696E6712";

    static immutable string binUnitTestAllTypes =
        "5048414D000111400F05656E756D310E0574686972640F05626F6F6C3102010F05627974653103650F0675627974653103000F0673686F72743104EA0F0F077573686F72743104873E0F04696E743105FCDA2E0F0575696E7431059987E3030F056C6F6E673106CBC9A5F8020F06756C6F6E6731068AB9BC8F020F06666C6F61743109979C99AC090F08666C6F61744E614E09808080FC0F0F07646F75626C65310A9FB8EFF2B790DB8485030F09646F75626C65496E660A80808080808080F0FF010F07737472696E67310E0E7465737420737472696E67206F660F096368617241727261790E0F77696C6C207468697320776F726B3F0F0762696E6172793110052518CC652B0F08696E744172726179130605870205A90E058D3A05BC2F0581D90405BC05140F0C696E7441727261794E756C6C1300140F06696E74496E7411020F013205A0EE020F02313105B0EC0D120F0A696E74496E744E756C6C1100120F08656E756D456E756D11020F05666F7274680E0573697874680F0574686972640E067365636F6E64120F0673747253747211030F046B6579310E0A6B6579312076616C75650F046B6579320E0A6B6579322076616C75650F046B6579330E00120F077374727563743111400F097075626C6963496E7405140F0C7075626C69634765745365740501120F06636C6173733111400F03496E74051E0F0C7075626C696353747275637411400F097075626C6963496E7405140F0C7075626C69634765745365740501120F064765745365740501120F0A636C617373314E756C6C11001212";

    static immutable string binUnitTestStd =
        "5048414D000111400F07626967496E74310E212D37313435393236363431363639333136303336323534353738383738313630300F0564617465310E0A313939392D30312D30310F096461746554696D65310E13313939392D30372D30365431323A33303A33330F0873797354696D653106B6A1DBBA020F0A74696D654F66446179310E0831323A33303A33330F05757569643110108AB3060E2CBA4F23B74CB52DB3DBFB4612";

    static immutable string binUnitTestPham =
        "5048414D000111400F07626967496E7431100EE07B47572A79980A9C3BA80E7AFC0F056461746531059A8A590F096461746554696D65310680EAAB9BCFF0CAC0110F0574696D65310680EA939C9B1A12";

    static immutable string binUnitTestDec =
        "5048414D000111400F0A646563696D616C4E614E10047C0000000F0F646563696D616C496E66696E6974791004F80000000F09646563696D616C33321004B2801BE90F09646563696D616C3634100831800010A3401C7C0F0A646563696D616C3132381010303C00000000000000001ACA9694C66712";
}

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
    import pham.utl.utl_object : bytesToHexs;

    auto c = new UnitTestC2();
    scope serializer = new BinarySerializer();
    serializer.serialize!UnitTestC2(cast(UnitTestC2)(c.setValues()));

    //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
    assert(bytesToHexs(serializer.buffer[]) == binUnitTestC2, bytesToHexs(serializer.buffer[]));
}

unittest // BinaryDeserializer.UnitTestC2
{
    import pham.utl.utl_object : bytesFromHexs;

    scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestC2));
    auto c = deserializer.deserialize!UnitTestC2();
    assert(c !is null);
    c.assertValues();
}

unittest // BinarySerializer.UnitTestAllTypes
{
    import pham.utl.utl_object : bytesToHexs;

    auto c = new UnitTestAllTypes();
    scope serializer = new BinarySerializer();
    serializer.serialize!UnitTestAllTypes(c.setValues());

    //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
    assert(bytesToHexs(serializer.buffer[]) == binUnitTestAllTypes, bytesToHexs(serializer.buffer[]));
}

unittest // BinaryDeserializer.UnitTestAllTypes
{
    import pham.utl.utl_object : bytesFromHexs;

    scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestAllTypes));
    auto c = deserializer.deserialize!UnitTestAllTypes();
    assert(c !is null);
    c.assertValues();
}

unittest // BinarySerializer.UnitTestStd
{
    import pham.utl.utl_object : bytesToHexs;
    import pham.utl.utl_serialization_std;

    UnitTestStd c;
    scope serializer = new BinarySerializer();
    serializer.serialize!UnitTestStd(c.setValues());

    //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
    assert(bytesToHexs(serializer.buffer[]) == binUnitTestStd, bytesToHexs(serializer.buffer[]));
}

unittest // BinaryDeserializer.UnitTestStd
{
    import pham.utl.utl_object : bytesFromHexs;
    import pham.utl.utl_serialization_std;

    scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestStd));
    auto c = deserializer.deserialize!UnitTestStd();
    c.assertValues();
}

unittest // BinarySerializer.UnitTestPham
{
    import pham.utl.utl_object : bytesToHexs;
    import pham.utl.utl_serialization_pham;

    UnitTestPham c;
    scope serializer = new BinarySerializer();
    serializer.serialize!UnitTestPham(c.setValues());

    //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
    assert(bytesToHexs(serializer.buffer[]) == binUnitTestPham, bytesToHexs(serializer.buffer[]));
}

unittest // BinaryDeserializer.UnitTestPham
{
    import pham.utl.utl_object : bytesFromHexs;
    import pham.utl.utl_serialization_pham;

    scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestPham));
    auto c = deserializer.deserialize!UnitTestPham();
    c.assertValues();
}

unittest // BinarySerializer.UnitTestDec
{
    import pham.utl.utl_object : bytesToHexs;
    import pham.utl.utl_serialization_dec;

    UnitTestDec c;
    scope serializer = new BinarySerializer();
    serializer.serialize!UnitTestDec(c.setValues());

    //import std.stdio : writeln; debug writeln(bytesToHexs(serializer.buffer[]));
    assert(bytesToHexs(serializer.buffer[]) == binUnitTestDec, bytesToHexs(serializer.buffer[]));
}

unittest // BinaryDeserializer.UnitTestDec
{
    import pham.utl.utl_object : bytesFromHexs;
    import pham.utl.utl_serialization_dec;

    scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestDec));
    auto c = deserializer.deserialize!UnitTestDec();
    c.assertValues();
}