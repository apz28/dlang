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

module pham.utl.utl_serialization;

import std.conv : to;
import std.meta;
import std.range : ElementType, isInputRange;
import std.traits : BaseClassesTuple, EnumMembers, fullyQualifiedName, FunctionAttribute, functionAttributes,
    isAggregateType, isDynamicArray, isFloatingPoint, isFunction, isIntegral, isSomeChar, isSomeFunction,
    isStaticArray, Parameters, ReturnType, Unqual;

@safe:

enum Condition : ubyte
{
    required,
    optional,
    ignored,
    ignoredDefault,
    ignoredNull,
}

enum CharacterCaseFormat : ubyte
{
    normal,
    upper,
    lower,
}

enum EnumFormat : ubyte
{
    name,
    integral,
}

enum BinaryDataFormat : ubyte
{
    base64,
    hex,
}

struct BinaryFormat
{
@nogc nothrow @safe:

    BinaryDataFormat dataFormat;
    CharacterCaseFormat characterCaseFormat;
}

struct FloatFormat
{
@nogc nothrow @safe:

    ubyte floatPrecision;
    bool stripTrailingZero;

    bool isFloatPrecision() const pure
    {
        return floatPrecision != ubyte.max;
    }
}

struct Serializable
{
@safe:

public:
    this(string name,
        Condition condition = Condition.required) @nogc nothrow pure
    {
        this.name = name;
        this.condition = condition;
    }

    this(string name, BinaryFormat binaryFormat,        
        Condition condition = Condition.required) @nogc nothrow pure
    {
        this.name = name;
        this.condition = condition;
        this.binaryFormat = binaryFormat;
    }

    this(string name, EnumFormat enumFormat,
        Condition condition = Condition.required) @nogc nothrow pure
    {
        this.name = name;
        this.condition = condition;
        this.enumFormat = enumFormat;
    }

    this(string name, FloatFormat floatFormat,
        Condition condition = Condition.required) @nogc nothrow pure
    {
        this.name = name;
        this.condition = condition;
        this.floatFormat = floatFormat;
    }

    string serializableName(string memberName) @nogc nothrow pure
    {
        return name.length != 0 ? name : memberName;
    }

public:
    string name;
    Condition condition;
    BinaryFormat binaryFormat;
    EnumFormat enumFormat;
    FloatFormat floatFormat = FloatFormat(ubyte.max, false);
}

template allMembers(T)
{
    static if (isAggregateType!T)
        alias allMembers = aliasSeqOf!(filterMembers([__traits(allMembers, T)]));
    else
        alias allMembers = AliasSeq!();
}

struct EnumBitSet(E)
if (is(E Base == enum) && isIntegral!Base && E.init == 0)
{
@nogc nothrow @safe:

public:
    this(E e) pure
    {
        this.values = e;
    }

    this(scope const(E)[] es) pure
    {
        foreach (const e; es)
            inc(e);
    }

    this(const(size_t) es) pure
    {
        foreach (const e; EnumMembers!E)
        {
            if ((e & es))
                inc(e);
        }
    }

    ref typeof(this) opAssign(scope const(E)[] es) pure return
    {
        this.values = E.init;
        foreach (const e; es)
            inc(e);
        return this;
    }

    ref typeof(this) opAssign(const(size_t) es) pure return
    {
        this.values = E.init;
        foreach (const e; EnumMembers!E)
        {
            if ((e & es))
                inc(e);
        }
        return this;
    }

    ref typeof(this) exc(const(E) e) pure return
    {
        values = cast(E)(values & ~e);
        return this;
    }

    ref typeof(this) inc(const(E) e) pure return
    {
        values = cast(E)(values | e);
        return this;
    }

    pragma(inline, true)
    bool isAny(const(E) e) const pure
    {
        return e != 0 && (values & e) != 0;
    }

    pragma(inline, true)
    bool isSet(const(E) e) const pure
    {
        return e != 0 && (values & e) == e;
    }

public:
    E values;
    alias values this;
}

template getGetterSetterFunctions(symbols...)
{
    static if (symbols.length == 2 && fullyQualifiedName!(symbols[0]) == fullyQualifiedName!(symbols[1]))
    {
        static if (isGetterFunction!(symbols[0]) && isSetterFunction!(symbols[1]) && is(getParamType!(symbols[1], 0) == getReturnType!(symbols[0])))
            alias getGetterSetterFunctions = AliasSeq!(symbols);
        else static if (isGetterFunction!(symbols[1]) && isSetterFunction!(symbols[0]) && is(getParamType!(symbols[0], 0) == getReturnType!(symbols[1])))
            alias getGetterSetterFunctions = AliasSeq!(symbols[1], symbols[0]);
        else
            alias getGetterSetterFunctions = AliasSeq!();
    }
    else
        alias getGetterSetterFunctions = AliasSeq!();
}

template getParamType(alias functionSymbol, size_t i)
{
    alias getParamType = Parameters!functionSymbol[i];
}

template getOverloads(alias T, string name)
{
    private alias overloads = __traits(getOverloads, T, name);
    //pragma(msg, T.stringof ~ "." ~ name ~ ".length=" ~ overloads.length.stringof);
    static if (overloads.length == 1 && __traits(isOverrideFunction, overloads[0]))
    {
        private alias bases = BaseClassesTuple!T;        
        private enum baseIndex =
        {
            static foreach (i, c; bases)
            {
                static if (__traits(compiles, __traits(getOverloads, c, name)) && __traits(getOverloads, c, name).length == 2)
                {
                    if (__ctfe)
                        return i;
                }
            }
            return -1;
        }();  
        static if (baseIndex == -1)
            alias getOverloads = overloads;
        else
            alias getOverloads = __traits(getOverloads, bases[baseIndex], name);
    }
    else
        alias getOverloads = overloads;
}

template getReturnType(alias getFunctionSymbol)
{
    static if (isPropertyFunction!getFunctionSymbol)
        alias getReturnType = typeof(getFunctionSymbol);
    else
        alias getReturnType = ReturnType!(typeof(getFunctionSymbol));
}

template getUDAs(alias symbol, alias attribute)
{    
    static if (__traits(compiles, __traits(getAttributes, symbol)))
        alias getUDAs = Filter!(isDesiredUDA!attribute, __traits(getAttributes, symbol));
    else
        alias getUDAs = AliasSeq!();
}

template getUDA(alias symbol, alias attribute)
{
    private alias allAttributes = getUDAs!(symbol, attribute);
    static if (allAttributes.length != 1)
        static assert(0, "Exactly one " ~ fullyQualifiedName!attribute ~ " attribute is allowed, got " ~ allAttributes.length.stringof ~ " for " ~ fullyQualifiedName!symbol);
    else static if (is(typeof(allAttributes[0])))
        enum getUDA = allAttributes[0];
    else
        alias getUDA = allAttributes[0];
}

template hasTypeOfSymbol(symbols...)
if (symbols.length > 1)
{
    enum bool hasTypeOfSymbol = false;
}

template hasTypeOfSymbol(alias symbol)
{
    static if (__traits(compiles, typeof(symbol)))
        enum bool hasTypeOfSymbol = true;
    else
        enum bool hasTypeOfSymbol = false;
}

template hasUDA(alias symbol, alias attribute)
{
    enum bool hasUDA = getUDAs!(symbol, attribute).length != 0;
}

template isGetterFunction(alias symbol)
{
    static if (isFunction!symbol)
        enum bool isGetterFunction = !is(ReturnType!symbol == void) && ((Parameters!symbol).length == 0);
    else
        enum bool isGetterFunction = false;
}

template isPropertyFunction(alias symbol)
{
    static if (isFunction!symbol)
        enum bool isPropertyFunction = (functionAttributes!symbol & FunctionAttribute.property) != 0;
    else
        enum bool isPropertyFunction = false;
}

template isSetterFunction(alias symbol)
{
    static if (isFunction!symbol)
        enum bool isSetterFunction = (Parameters!symbol).length == 1;
    else
        enum bool isSetterFunction = false;
}

template isSerializerMember(alias member)
{
    //pragma(msg, member.memberName ~ ", " ~ member.flags.stringof ~ ", " ~ member.attribute.condition.stringof);
    enum bool isSerializerMember = member.flags != SerializerMemberFlag.none
        && member.attribute.condition != Condition.ignored;
}

template isTemplateSymbol(symbols...)
if (symbols.length > 1)
{
    enum bool isTemplateSymbol = false;
}

template isTemplateSymbol(alias symbol)
{
    static if (__traits(compiles, __traits(isTemplate, symbol)))
        enum bool isTemplateSymbol = __traits(isTemplate, symbol);
    else
        enum bool isTemplateSymbol = false;
}

enum SerializerMemberFlag : ubyte
{
    none = 0,
    implicitUDA = 1,
    explicitUDA = 2,
    isGetSet = 4,
}

template SerializerMember(alias T, string name)
{
@safe:
    private alias member = __traits(getMember, T, name);
    private enum bool hasTypeOfMember = hasTypeOfSymbol!member;
    private enum bool isTemplateMember = isTemplateSymbol!member;
    private alias overloads = getOverloads!(T, name);
    //pragma(msg, T.stringof ~ "." ~ name ~ "." ~ overloads.length.stringof ~ "." ~ isTemplateMember.stringof ~ "." ~ hasTypeOfMember.stringof);

    /// The name of the member in the struct/class itself
    alias memberName = name;

    static if (overloads.length > 1 && getGetterSetterFunctions!(overloads).length)
    {
        private alias getterSetter = getGetterSetterFunctions!(overloads);
        alias memberGet = getterSetter[0];
        alias memberSet = getterSetter[1];

        /// Type of the member
        alias memberType = getReturnType!memberGet;

        /// Visibility level of the member
        enum SerializerScope memberScope = toSerializerScope(__traits(getVisibility, memberGet));

        /// Serializable attribute of the member
        static if (hasUDA!(memberGet, Serializable))
        {
            enum Serializable attribute = getUDA!(memberGet, Serializable);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.explicitUDA
                | SerializerMemberFlag.isGetSet;
        }
        else static if (hasUDA!(memberSet, Serializable))
        {
            enum Serializable attribute = getUDA!(memberSet, Serializable);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.explicitUDA
                | SerializerMemberFlag.isGetSet;
        }
        else
        {
            enum Serializable attribute = Serializable(name, Condition.required);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.implicitUDA
                | SerializerMemberFlag.isGetSet;
        }
    }
    // Plain field
    else static if (overloads.length == 0 && hasTypeOfMember && !isTemplateMember)
    {
        /// The reference to the field
        alias memberGet = member;
        alias memberSet = memberGet;

        /// Type of the field
        alias memberType = typeof(member);

        /// Visibility level of the field
        enum SerializerScope memberScope = toSerializerScope(__traits(getVisibility, member));

        /// Default value of the field (may or may not be `Type.init`)
        //alias memberDefault = __traits(getMember, T.init, name);
        //TODO remove pragma(msg, name ~ "." ~ typeof(memberDefault).stringof);

        /// Serializable attribute of the field
        static if (hasUDA!(member, Serializable))
        {
            enum Serializable attribute = getUDA!(member, Serializable);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.explicitUDA;
        }
        else
        {
            enum Serializable attribute = Serializable(name, Condition.required);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.implicitUDA;
        }
    }
    else static if (overloads.length == 0 || isTemplateMember)
    {
        alias memberGet = void;
        alias memberSet = void;
        alias memberType = void;
        enum SerializerScope memberScope = SerializerScope.none;
        enum Serializable attribute = Serializable(name, Condition.ignored);
        enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.none;
    }
    else
    {
        alias memberGet = overloads[0];
        alias memberSet = void;
        alias memberType = getReturnType!memberGet;
        enum SerializerScope memberScope = toSerializerScope(__traits(getVisibility, memberGet));

        /// Serializable attribute of the function
        static if (hasUDA!(memberGet, Serializable))
        {
            enum Serializable attribute = getUDA!(memberGet, Serializable);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.explicitUDA;
        }
        else
        {
            enum Serializable attribute = Serializable(name, Condition.ignored);
            enum EnumBitSet!SerializerMemberFlag flags = SerializerMemberFlag.none;
        }
    }
}

template SerializerMemberList(T)
{
public:
    //pragma(msg, "\n"); pragma(msg, T.stringof);

    static if (is(T == class) || is(T == struct))
    {
        static if (__traits(getAliasThis, T).length == 0)
        {
            alias SerializerMemberList = Filter!(isSerializerMember, staticMap!(createSerializerField, allMembers!T));
        }
        else
        {
            // Tuple of strings of aliased fields
            // As of DMD v2.100.0, only a single alias this is supported in D.
            private immutable aliasedFieldNames = __traits(getAliasThis, T);
            static assert(aliasedFieldNames.length == 1, "Multiple `alias this` are not supported");

            // Ignore alias to function
            static if (isSomeFunction!(__traits(getMember, T, aliasedFieldNames)))
            {
                alias SerializerMemberList = Filter!(isSerializerMember, staticMap!(createSerializerField, allMembers!T));
            }
            else
            {
                private immutable baseFields = Erase!(aliasedFieldNames, allMembers!T);
                static assert(baseFields.length == allMembers!(T).length - 1);
                private alias allFields = AliasSeq!(staticMap!(createSerializerField, baseFields),
                    SerializerMemberList!(typeof(__traits(getMember, T, aliasedFieldNames))));
                alias SerializerMemberList = Filter!(isSerializerMember, allFields);
            }
        }
    }
    else
    {
        alias SerializerMemberList = AliasSeq!();
    }

private:
    alias createSerializerField(string name) = SerializerMember!(T, name);
}

enum SerializerScope : ubyte
{
    none = 0,
    private_ = 1,
    protected_ = 2,
    public_ = 4,
}

struct SerializerOptions
{
@safe:

public:
    bool isReaderMember(alias member)() const nothrow
    {
        //scope (failure) assert(0);
        //import std.stdio; writeln; debug writeln(member.memberName, "=", member.memberScope, "/", this.memberScopes, ", ", member.flags, "/", this.memberFlags);

        if (!this.memberScopes.isSet(member.memberScope))
            return false;

        if (!this.memberFlags.isSet(member.flags))
            return false;

        if (member.attribute.condition == Condition.ignored)
            return false;

        return true;
    }

    bool isWriterMember(alias member)() const nothrow
    {
        //pragma(msg, member.memberName ~ ", " ~ member.memberScope.stringof ~ ", " ~ member.flags.stringof ~ ", " ~ member.attribute.condition.stringof);

        if (!this.memberScopes.isSet(member.memberScope))
            return false;

        if (!this.memberFlags.isSet(member.flags))
            return false;

        if (member.attribute.condition == Condition.ignored)
            return false;

        return true;
    }

    string[] readerMembers(T)() const nothrow
    {
        alias members = SerializerMemberList!T;
        string[] result;
        result.reserve(members.length);
        foreach (member; members)
        {
            if (!isReaderMember!member)
                continue;

            result ~= member.memberName;
        }
        return result;
    }

    string[] writerMembers(T)() const nothrow
    {
        alias members = SerializerMemberList!T;
        string[] result;
        result.reserve(members.length);
        foreach (member; members)
        {
            if (!isWriterMember!member)
                continue;

            result ~= member.memberName;
        }
        return result;
    }

public:
    EnumBitSet!SerializerScope memberScopes = SerializerScope.public_;
    EnumBitSet!SerializerMemberFlag memberFlags = SerializerMemberFlag.isGetSet
        | SerializerMemberFlag.implicitUDA
        | SerializerMemberFlag.explicitUDA;
    FloatFormat floatFormat = FloatFormat(4, true);
}

enum SerializerDataType : ubyte
{
    text,
    binary,
}

class Serializer
{
@safe:

public:
    final size_t decDepth() nothrow
    in
    {
        assert(depth > 0);
    }
    do
    {
        depth--;
        return depth;
    }

    final size_t incDepth() nothrow
    {
        depth++;
        return depth;
    }

    Serializer begin()
    {
        depth = 0;
        return this;
    }

    Serializer end()
    {
        return this;
    }

    Serializer aggregateBegin(string typeName, ptrdiff_t length)
    {
        incDepth();
        return this;
    }

    Serializer aggregateEnd(string typeName, ptrdiff_t length)
    {
        decDepth();
        return this;
    }

    Serializer aggregateItem(ptrdiff_t length)
    {
        return this;
    }

    Serializer arrayBegin(string elemTypeName, ptrdiff_t length)
    {
        incDepth();
        return this;
    }

    Serializer arrayEnd(string elemTypeName, ptrdiff_t length)
    {
        decDepth();
        return this;
    }

    Serializer arrayItem(ptrdiff_t length)
    {
        return this;
    }

    abstract void put(typeof(null) v);
    abstract void putBool(bool v); // Different name - D is not good of distinguish with byte/int
    abstract void putChar(char v); // Different name - D is not good of distinguish with byte/int
    abstract void put(byte v);
    abstract void put(short v);
    abstract void put(int v);
    abstract void put(long v);
    abstract void put(float v, const(FloatFormat) floatFormat);
    abstract void put(double v, const(FloatFormat) floatFormat);
    abstract void put(scope const(char)[] v); // String value
    abstract void put(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat); // Binary value
    abstract Serializer putKey(scope const(char)[] key);
    abstract Serializer putKeyId(scope const(char)[] key);

    @property abstract SerializerDataType dataType() const @nogc nothrow pure;

public:
    static string binaryToString(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        import std.ascii : LetterCase;
        import std.base64 : Base64;
        import std.digest : toHexString;

        final switch (binaryFormat.dataFormat)
        {
            case BinaryDataFormat.base64:
                return Base64.encode(v);
            case BinaryDataFormat.hex:
                return binaryFormat.characterCaseFormat == CharacterCaseFormat.lower 
                    ? toHexString!(LetterCase.lower)(v)
                    : binaryFormat.characterCaseFormat == CharacterCaseFormat.upper 
                        ? toHexString!(LetterCase.upper)(v)
                        : toHexString(v);
        }
    }
    
    static const(char)[] floatToString(V)(return scope char[] vBuffer, V v, const(FloatFormat) floatFormat) pure
    if (isFloatingPoint!V)
    in
    {
        assert(vBuffer.length >= 50);
    }
    do
    {
        import std.format : sformat;
        import std.math : isInfinity, isNaN, sgn;
        
        if (isNaN(v))
        {
            vBuffer[0..3] = "nan";
            return vBuffer[0..3];
        }
        
        if (isInfinity(v))
        {
            vBuffer[0..4] = sgn(v) ? "-inf" : "+inf";
            return vBuffer[0..4];
        }

        char[10] fBuffer = void;
        const fmt = floatFormat.floatPrecision >= 18 ? "%.18f" : sformat(fBuffer[], "%%.%df", floatFormat.floatPrecision);
        return floatFormat.stripTrailingZero
            ? floatStripTrailingZero(sformat(vBuffer, fmt, v))
            : sformat(vBuffer[], fmt, v);
    }

    static const(char)[] floatStripTrailingZero(return scope const(char)[] v) @nogc nothrow pure
    {
        import std.ascii : isDigit;
        
        // Start stripping all trailing zeros
        size_t len = v.length;
        while (len && v[len-1] == '0')
            len--;
            
        // End with period -> add back a zero
        if (len && !isDigit(v[len-1])) 
            len++;
            
        return v[0..len];
    }
    
    static const(char)[] intToString(V)(return scope char[] vBuffer, V v) pure
    if (isIntegral!V)
    in
    {
        assert(vBuffer.length >= 20);
    }
    do
    {
        import std.format : sformat;
        
        return sformat(vBuffer, "%d", v);
    }
    
public:
    // null
    final void serialize(typeof(null), scope ref Serializable serializable)
    {
        put(null);
    }

    // Boolean
    final void serialize(V : bool)(V v, scope ref Serializable serializable)
    if (is(V == bool) && !is(V == enum))
    {
        putBool(v);
    }

    // Char
    final void serialize(V : char)(V v, scope ref Serializable serializable)
    if (is(V == char) && !is(V == enum))
    {
        putChar(v);
    }

    // Integral
    final void serialize(V)(V v, scope ref Serializable serializable)
    if (isIntegral!V && !is(V == enum))
    {
        put(v);
    }

    // Float
    final void serialize(V)(V v, scope ref Serializable serializable)
    if (isFloatingPoint!V)
    {
        const floatFormat = serializable.floatFormat.isFloatPrecision()
            ? serializable.floatFormat
            : options.floatFormat;
        return put(v, floatFormat);
    }

    // Enum
    final void serialize(V)(V v, scope ref Serializable serializable)
    if (is(V == enum))
    {
        if (serializable.enumFormat == EnumFormat.integral)
        {
            static if (is(V Base == enum) && isIntegral!Base)
            {
                static if (Base.max <= int.max)
                    put(cast(int)v);
                else
                    put(cast(long)v);
                return;
            }
        }

        const vStr = v.to!string();
        put(vStr);
    }

    // Chars/String
    final void serialize(scope const(char)[] v, scope ref Serializable serializable)
    {
        if (v is null)
            put(null);
        else
            put(v);
    }

    // String
    final void serialize(string v, scope ref Serializable serializable)
    {
        if (v is null)
            put(null);
        else
            put(v);
    }

    // Bytes/Binary
    final void serialize(scope const(ubyte)[] v, scope ref Serializable serializable)
    {
        if (v is null)
            put(null);
        else
            put(v, serializable.binaryFormat);
    }

    // Array
    final void serialize(V)(V[] v, scope ref Serializable serializable)
    if (!isSomeChar!V && !is(V == ubyte) && !is(V == byte))
    {
        if (v is null)
        {
            put(null);
            return;
        }

        static immutable typeName = fullyQualifiedName!V;
        arrayBegin(typeName, v.length);
        scope (success)
            arrayEnd(typeName, v.length);
        foreach (i, ref e; v)
        {
            arrayItem(i);
            serialize(e, serializable);
        }
    }

    // Input range
    final void serialize(R)(R v, scope ref Serializable serializable)
    if (isInputRange!R && !isSomeChar!(ElementType!R) && !isDynamicArray!R)
    {
        static immutable typeName = fullyQualifiedName!(ElementType!R);
        size_t length;
        arrayBegin(typeName, -1);
        scope (success)
            arrayEnd(typeName, length);
        foreach (ref e; v)
        {
            arrayItem(length);
            serialize(e, serializable);
            length++;
        }
    }

    // Associative array with string key
    final void serialize(V)(auto ref V[string] v, scope ref Serializable serializable)
    {
        if (v is null)
        {
            put(null);
            return;
        }

        static immutable typeName = fullyQualifiedName!V ~ "[" ~ string.stringof ~ "]";
        size_t index;
        aggregateBegin(typeName, v.length);
        scope (success)
            aggregateEnd(typeName, v.length);
        foreach (key, ref val; v)
        {
            aggregateItem(index);
            putKey(key);
            serialize(val, serializable);
            index++;
        }
    }

    // Associative array with integral key
    final void serialize(V : const T[K], T, K)(V v, scope ref Serializable serializable)
    if (isIntegral!K && !is(K == enum))
    {
        import std.format : sformat;

        if (v is null)
        {
            put(null);
            return;
        }

        static immutable typeName = fullyQualifiedName!T ~ "[" ~ K.stringof ~ "]";
        size_t index;
        aggregateBegin(typeName, v.length);
        scope (success)
            aggregateEnd(typeName, v.length);
        char[50] keyBuffer = void;
        foreach (key, ref val; v)
        {
            auto keyStr = sformat(keyBuffer[], "%d", key);
            aggregateItem(index);
            putKeyId(keyStr);
            serialize(val, serializable);
            index++;
        }
    }

    // Associative array with enum key
    final void serialize(V : const T[K], T, K)(V v, scope ref Serializable serializable)
    if (is(K == enum))
    {
        if (v is null)
        {
            put(null);
            return;
        }

        static immutable typeName = fullyQualifiedName!T ~ "[" ~ K.stringof ~ "]";
        string keyStr;
        size_t index;
        aggregateBegin(typeName, v.length);
        scope (success)
            aggregateEnd(typeName, v.length);
        foreach (key, ref val; v)
        {
            if (serializable.enumFormat == EnumFormat.integral)
            {
                static if (is(K KBase == enum) && isIntegral!KBase)
                    keyStr = (cast(long)key).to!string();
                else
                    keyStr = key.to!string();
            }
            else
                keyStr = key.to!string();
            aggregateItem(index);
            putKeyId(keyStr);
            serialize(val, serializable);
            index++;
        }
    }

    // Aggregate (class, struct)
    final void serialize(V)(auto ref V v)
    //if (isAggregateType!V && !isInputRange!V)
    if ((is(V == class) || is(V == struct)) && !isInputRange!V)
    {
        Serializable serializable;
        serialize(v, serializable);
    }

    final void serialize(V)(auto ref V v, scope ref Serializable serializable) @trusted // opEqual
    //if (isAggregateType!V && !isInputRange!V)
    if ((is(V == class) || is(V == struct)) && !isInputRange!V)
    {
        static if (is(V == class))
        {
            if (v is null)
            {
                put(null);
                return;
            }
        }

        static if (__traits(hasMember, V, "serialize"))
        {
            /*
            static if (__traits(hasMember, V, "serializeBegin"))
                v.serializeBegin(this, serializable);
            static if (__traits(hasMember, V, "serializeEnd"))
                scope (success) v.serializeEnd(this, serializable);
            */
            v.serialize(this, serializable);
            return;
        }

        static immutable typeName = fullyQualifiedName!V;
        size_t length;
        bool hasMember;
        scope (success)
        {
            if (hasMember)
            {
                static if (__traits(hasMember, V, "serializeEnd"))
                    v.serializeEnd(this, serializable);
                aggregateEnd(typeName, length);
            }
        }
        alias members = SerializerMemberList!V;
        foreach (member; members)
        {
            if (!options.isWriterMember!member)
                continue;

            //pragma(msg, V.stringof ~ "." ~ member.memberName);

            static if (__traits(compiles, __traits(child, v, member.memberGet)))
            {            
                auto memberValue = __traits(child, v, member.memberGet);
                Serializable memberAttribute = member.attribute;

                if (memberAttribute.condition == Condition.ignoredNull)
                {
                    static if (!isStaticArray!(member.memberType) && 
                        (is(member.memberType == class) || is(member.memberType : T[], T) || is(member.memberType : const T[K], T, K)))
                    {
                        if (memberValue is null)
                            continue;
                    }
                }
                else if (memberAttribute.condition == Condition.ignoredDefault)
                {
                    if (memberValue == __traits(child, V.init, member.memberGet))
                    //if ((() @trusted => memberValue == __traits(child, V.init, member.memberGet))())
                        continue;
                }

                if (!hasMember)
                {
                    hasMember = true;
                    aggregateBegin(typeName, -1);
                    static if (__traits(hasMember, V, "serializeBegin"))
                        v.serializeBegin(this, serializable);
                }

                aggregateItem(length);
                putKey(member.attribute.serializableName(member.memberName));
                if (!serializeCustom!(member.memberType)(memberValue, memberAttribute))
                    serialize(memberValue, memberAttribute);                
                length++;
            }
        }
    }

    final void serializeAny(V)(auto ref V v, scope ref Serializable serializable)
    {
        if (!serializeCustom!V(v, serializable))
            serialize!V(v, serializable);
    }
    
    // Customized types
    final bool serializeCustom(V)(auto ref V v, scope ref Serializable attribute) @trusted // parameter address & access __gshared customSerializedTypes
    {
        alias UV = Unqual!V;
        if (auto f = fullyQualifiedName!V in customSerializedTypes)
        {
            (*f)(this, cast(UV*)&v, attribute);
            return true;
        }
        
        return false;
    }

    alias SerializeFunction = void function(Serializer serializer, scope void* value, scope ref Serializable attribute) @safe;
    
    static SerializeFunction registerSerialize(string type, SerializeFunction serialize) @trusted // access __gshared customSerializedTypes
    in
    {   
        assert(type.length > 0);
        assert(serialize !is null);
    }
    do
    {
        SerializeFunction result;
        if (auto f = type in customSerializedTypes)
            result = *f;
        customSerializedTypes[type] = serialize;
        return result;
    }
    
public:
    SerializerOptions options;
    size_t depth;
    
private:
    static __gshared SerializeFunction[string] customSerializedTypes;
}

struct StaticBuffer(T, size_t capacity)
{
nothrow @safe:

    T[capacity] data = 0; // 0=Make its struct to be zero initializer
    size_t length;
    
    T[] opSlice() @nogc return
    {
        return data[0..length];
    }
    
    pragma(inline, true)
    void put(T c) @nogc
    in
    {
        assert(length < capacity);
    }
    do
    {
        data[length++] = c;
    }
    
    void put(scope const(T)[] s) @nogc
    in
    {
        assert(length + s.length <= capacity);
    }
    do
    {
        const nl = length + s.length;
        data[length..nl] = s[0..$];
        length = nl;
    }
    
    ref typeof(this) reset() @nogc return
    {
        length = 0;
        return this;
    }
}

T asciiCaseInplace(T)(return scope T s, const(CharacterCaseFormat) characterCaseFormat) nothrow pure
if (isDynamicArray!T)
{
    import std.ascii : isLower, isUpper;
    
    final switch (characterCaseFormat)
    {
        case CharacterCaseFormat.normal: 
            return s;
        case CharacterCaseFormat.upper: 
            foreach (ref c; s)
            {
                if (isLower(c))
                    c = cast(char)(c - ('a' - 'A'));
            }
            return s;
        case CharacterCaseFormat.lower: 
            foreach (ref c; s)
            {
                if (isUpper(c))
                    c = cast(char)(c + ('a' - 'A'));
            }
            return s;
    }    
}

SerializerScope toSerializerScope(scope const(char)[] visibility) @nogc nothrow pure
{
    return visibility == "public" || visibility == "export"
        ? SerializerScope.public_
        : (visibility == "protected" || visibility == "package"
            ? SerializerScope.protected_
            : SerializerScope.private_); // visibility == "private"
}

version (unittest)
{
package(pham.utl):

    enum UnitTestEnum
    {
        first,
        second,
        third,
        forth,
        fifth,
        sixth,
    }

    static struct UnitTestS1
    {
    public:
        int publicInt;

        int publicGetSet()
        {
            return _publicGetSet;
        }

        int publicGetSet(int i)
        {
            _publicGetSet = i;
            return i;
        }

        int publicOnlyGet()
        {
            return int.min;
        }

        int publicOnlySet(int i)
        {
            return int.max;
        }
        
        ref UnitTestS1 setValues() return
        {
            _publicGetSet = 1;
            _protectedGetSet = 3;
            _privateGetSet = 5;
            publicInt = 20;
            protectedInt = 0;
            privateInt = 0;
            return this;
        }

    protected:
        int protectedInt;

        int protectedGetSet()
        {
            return _protectedGetSet;
        }

        int protectedGetSet(int i)
        {
            _protectedGetSet = i;
            return i;
        }

    private:
        int privateInt;

        int privateGetSet()
        {
            return _privateGetSet;
        }

        int privateGetSet(int i)
        {
            _privateGetSet = i;
            return i;
        }
        
        int _publicGetSet;
        int _protectedGetSet;
        int _privateGetSet;
    }

    static class UnitTestC1
    {
    public:
        @Serializable("Int")
        int publicInt;

        UnitTestS1 publicStruct;

        @Serializable("GetSet")
        int publicGetSet()
        {
            return _publicGetSet;
        }

        int publicGetSet(int i)
        {
            _publicGetSet = i;
            return i;
        }

        int publicOnlyGet()
        {
            return int.min;
        }

        int publicOnlySet(int i)
        {
            return int.max;
        }
        
        UnitTestC1 setValues()
        {
            _publicGetSet = 1;
            _protectedGetSet = 3;
            _privateGetSet = 5;
            publicInt = 30;
            publicStruct.setValues();
            protectedInt = 0;
            privateInt = 0;
            return this;
        }

    protected:
        int protectedInt;

        int protectedGetSet()
        {
            return protectedGetSet;
        }

        int protectedGetSet(int i)
        {
            protectedGetSet = i;
            return i;
        }

    private:
        int privateInt;

        int privateGetSet()
        {
            return _privateGetSet;
        }

        int privateGetSet(int i)
        {
            _privateGetSet = i;
            return i;
        }
        
        int _publicGetSet;
        int _protectedGetSet;
        int _privateGetSet;
    }

    class UnitTestC2 : UnitTestC1
    {
    public:
        string publicStr = "C2 public string";

        override int publicGetSet()
        {
            return _publicGetSet;
        }
        
        override UnitTestC2 setValues()
        {
            super.setValues();
            _publicGetSet = 11;
            publicStr = "C2 public string";
            return this;
        }
    }

    class UnitTestAllTypes
    {
    public:
        UnitTestEnum enum1;
        bool bool1;
        byte byte1;
        ubyte ubyte1;
        short short1;
        ushort ushort1;
        int int1;
        uint uint1;
        long long1;
        ulong ulong1;
        float float1;
        float floatNaN;
        double double1;
        double doubleInf;
        string string1;
        char[] charArray;
        ubyte[] binary1;
        int[] intArray;
        int[] intArrayNull;
        int[int] intInt;
        int[int] intIntNull;
        UnitTestEnum[UnitTestEnum] enumEnum;
        string[string] strStr;
        UnitTestS1 struct1;
        UnitTestC1 class1;
        UnitTestC1 class1Null;
        
        UnitTestAllTypes setValues()
        {
            enum1 = UnitTestEnum.third;
            bool1 = true;
            byte1 = 101;
            short1 = -1003;
            ushort1 = 3975;
            int1 = -382653;
            uint1 = 3957209;
            long1 = -394572364;
            ulong1 = 284659274;
            float1 = 6394763.5;
            floatNaN = float.nan;
            double1 = -2846627456445.765;
            doubleInf = double.infinity;
            string1 = "test string of";
            charArray = "will this work?".dup;
            binary1 = [37,24,204,101,43];
            intArray = [135,937,3725,3068,38465,380];
            intArrayNull = null;
            intInt[2] = 23456;
            intInt[11] = 113456;
            intIntNull = null;
            enumEnum[UnitTestEnum.third] = UnitTestEnum.second;
            enumEnum[UnitTestEnum.forth] = UnitTestEnum.sixth;
            strStr["key1"] = "key1 value";
            strStr["key2"] = "key2 value";
            strStr["key3"] = null;
            struct1.setValues();
            class1 = new UnitTestC1();
            class1.setValues();
            class1Null = null;
            return this;
        }
    }
}


private:

static immutable excludedMembers = [
    "opAssign",
    "opCast",
    "opCmp",
    "opEquals",
    "opPostMove",
    "factory",
    "Monitor",
    "toHash",
    "toString",
];

string[] filterMembers(string[] allMembers) nothrow pure
{
    string[] result;
    result.reserve(allMembers.length);

    NextLoop:
    foreach (member; allMembers)
    {
        // Build in members
        if (member.length >= 2 && (member[0..2] == "__" || member[$ - 2..$] == "__"))
            continue;

        foreach (excludedMember; excludedMembers)
        {
            if (excludedMember == member)
                continue NextLoop;
        }

        result ~= member;
    }

    return result;
}

template isDesiredUDA(alias attribute)
{
    template isDesiredUDA(alias toCheck)
    {
        static if (is(typeof(attribute)) && !__traits(isTemplate, attribute))
        {
            static if (__traits(compiles, toCheck == attribute))
                enum isDesiredUDA = toCheck == attribute;
            else
                enum isDesiredUDA = false;
        }
        else static if (is(typeof(toCheck)))
        {
            static if (__traits(isTemplate, attribute))
                enum isDesiredUDA =  isInstanceOf!(attribute, typeof(toCheck));
            else
                enum isDesiredUDA = is(typeof(toCheck) == attribute);
        }
        else static if (__traits(isTemplate, attribute))
            enum isDesiredUDA = isInstanceOf!(attribute, toCheck);
        else
            enum isDesiredUDA = is(toCheck == attribute);
    }
}

unittest // StaticBuffer
{
    StaticBuffer!(char, 10) buffer;
    buffer.put('a');
    buffer.put('C');
    assert(buffer[] == "aC");
    buffer.reset();
    buffer.put("1234567890");
    assert(buffer[] == "1234567890");
}

unittest // asciiCaseInplace
{
    char[] buffer = "1abCDefG2".dup;
    assert(asciiCaseInplace(buffer, CharacterCaseFormat.normal) == "1abCDefG2");
    assert(asciiCaseInplace(buffer, CharacterCaseFormat.upper) == "1ABCDEFG2");
    buffer = "1abCDefG2".dup;
    assert(asciiCaseInplace(buffer, CharacterCaseFormat.lower) == "1abcdefg2");
}

unittest // SerializerMemberList
{
    //import std.algorithm.iteration : map;
    import std.conv : to;

    string[] names;

    names = null;
    //pragma(msg, SerializerMemberList!UnitTestS1);
    alias s1 = SerializerMemberList!UnitTestS1;
    static assert(s1.length == 9, s1.length.stringof);
    static foreach (i; 0..s1.length)
    {
        names ~= s1[i].memberName;
    }
    assert(names == ["publicInt", "publicGetSet", "protectedInt", "protectedGetSet", "privateInt", "privateGetSet", "_publicGetSet", "_protectedGetSet", "_privateGetSet"], to!string(names));

    //const tes = s1.map(e => e.memberName);
    //import std.stdio; writeln; debug writeln("tes=", tes);

    names = null;
    //pragma(msg, SerializerMemberList!UnitTestC1);
    alias c1 = SerializerMemberList!UnitTestC1;
    static assert(c1.length == 10, c1.length.stringof);
    static foreach (i; 0..c1.length)
    {
        names ~= c1[i].memberName;
    }
    assert(names == ["publicInt", "publicStruct", "publicGetSet", "protectedInt", "protectedGetSet", "privateInt", "privateGetSet", "_publicGetSet", "_protectedGetSet", "_privateGetSet"], to!string(names));

    names = null;
    //pragma(msg, SerializerMemberList!UnitTestC2);
    alias c2 = SerializerMemberList!UnitTestC2;
    static assert(c2.length == 11, c2.length.stringof);
    static foreach (i; 0..c2.length)
    {
        names ~= c2[i].memberName;
    }
    assert(names == ["publicStr", "publicGetSet", "publicInt", "publicStruct", "protectedInt", "protectedGetSet", "privateInt", "privateGetSet", "_publicGetSet", "_protectedGetSet", "_privateGetSet"], to!string(names));
}

unittest // SerializerOptions - Default
{
    import std.conv : to;
    SerializerOptions options;

    const readerMembers = options.readerMembers!UnitTestS1();
    assert(readerMembers.length == 2, to!string(readerMembers.length) ~ "." ~ to!string(readerMembers));
    assert(readerMembers == ["publicInt", "publicGetSet"]);

    const writerMembers = options.writerMembers!UnitTestS1();
    assert(writerMembers.length == 2, to!string(writerMembers.length) ~ "." ~ to!string(writerMembers));
    assert(writerMembers == ["publicInt", "publicGetSet"]);
}

unittest // SerializerOptions - Change options
{
    import std.conv : to;
    SerializerOptions options;

    // All scopes
    options.memberScopes = SerializerScope.public_ | SerializerScope.protected_ | SerializerScope.private_;
    static immutable expectAllScopes = ["publicStr", "publicGetSet", "publicInt", "publicStruct", "protectedInt", "protectedGetSet", "privateInt", "privateGetSet", "_publicGetSet", "_protectedGetSet", "_privateGetSet"];

    const readerMembers = options.readerMembers!UnitTestC2();
    //import std.stdio; writeln; debug writeln(readerMembers); debug writeln(expectAllScopes);
    assert(readerMembers.length == 11, to!string(readerMembers.length) ~ "." ~ to!string(readerMembers));
    assert(readerMembers == expectAllScopes, to!string(readerMembers));
    const writerMembers = options.writerMembers!UnitTestC2();
    assert(writerMembers.length == 11, to!string(writerMembers.length) ~ "." ~ to!string(writerMembers));
    assert(writerMembers == expectAllScopes, to!string(writerMembers));

    // With attribute only
    options.memberScopes = SerializerScope.public_ | SerializerScope.protected_ | SerializerScope.private_;
    options.memberFlags = SerializerMemberFlag.isGetSet | SerializerMemberFlag.explicitUDA;
    static immutable expectAttributeOnly = ["publicGetSet", "publicInt"];

    const readerMembers2 = options.readerMembers!UnitTestC2();
    //import std.stdio; writeln; debug writeln(readerMembers2); debug writeln(expectAttributeOnly);
    assert(readerMembers2.length == 2, to!string(readerMembers2.length) ~ "." ~ to!string(readerMembers2));
    assert(readerMembers2 == expectAttributeOnly, to!string(readerMembers2));
    const writerMembers2 = options.writerMembers!UnitTestC2();
    assert(writerMembers2.length == 2, to!string(writerMembers2.length) ~ "." ~ to!string(writerMembers2));
    assert(writerMembers2 == expectAttributeOnly, to!string(writerMembers2));
}
