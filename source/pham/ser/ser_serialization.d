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

module pham.ser.ser_serialization;

import std.array : Appender, appender;
import std.conv : to;
import std.meta : AliasSeq, aliasSeqOf, Filter, NoDuplicates, staticMap;
import std.range : ElementType, isInputRange;
import std.traits : BaseClassesTuple, BaseTypeTuple, EnumMembers, fullyQualifiedName, FunctionAttribute, functionAttributes,
    isAggregateType, isCallable, isDynamicArray, isFloatingPoint, isFunction, isIntegral, isSomeChar, isSomeFunction,
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
    base16,
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
nothrow @safe:

public:
    this(string name,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, condition);
    }

    this(string name, string memberName,
        Condition condition = Condition.required) @nogc pure
    {
        this.name = name;
        this.memberName = memberName;
        this.condition = condition;
    }

    this(string name, BinaryFormat binaryFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, binaryFormat, condition);
    }

    this(string name, string memberName, BinaryFormat binaryFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this.name = name;
        this.memberName = memberName;
        this.binaryFormat = binaryFormat;
        this.condition = condition;
    }

    this(string name, EnumFormat enumFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, enumFormat, condition);
    }

    this(string name, string memberName, EnumFormat enumFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this.name = name;
        this.memberName = memberName;
        this.enumFormat = enumFormat;
        this.condition = condition;
    }

    this(string name, FloatFormat floatFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, floatFormat, condition);
    }

    this(string name, string memberName, FloatFormat floatFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this.name = name;
        this.memberName = memberName;
        this.floatFormat = floatFormat;
        this.condition = condition;
    }

    this(Serializable other, string memberName) @nogc pure
    in
    {
        assert(memberName.length != 0);
    }
    do
    {
        this.name = other.name.length ? other.name : memberName;
        this.memberName = memberName;
        this.condition = other.condition;
        this.binaryFormat = other.binaryFormat;
        this.enumFormat = other.enumFormat;
        this.floatFormat = other.floatFormat;
    }

public:
    string name;
    string memberName;
    Condition condition;
    BinaryFormat binaryFormat;
    EnumFormat enumFormat;
    FloatFormat floatFormat = FloatFormat(ubyte.max, false);
    bool symbolName;
}

enum SerializableMemberFlag : ubyte
{
    none = 0,
    explicitUDA = 1,
    implicitUDA = 2,
    isGetSet = 4,
}

enum SerializableMemberScope : ubyte
{
    none = 0,
    private_ = 1,
    protected_ = 2,
    public_ = 4,
}

struct SerializableMemberOptions
{
nothrow @safe:

public:
    this(EnumBitSet!SerializableMemberFlag flags, EnumBitSet!SerializableMemberScope scopes) @nogc pure
    {
        this.flags = flags;
        this.scopes = scopes;
    }

    bool isDeserializer(alias serializerMember)() const
    {
        //scope (failure) assert(0);
        //import std.stdio; writeln; debug writeln(serializerMember.memberName, "=", serializerMember.memberScope, "/", this.scopes, ", ", serializerMember.flags, "/", this.flags);

        if (serializerMember.attribute.condition == Condition.ignored)
            return false;

        if (!this.scopes.isSet(serializerMember.memberScope))
            return false;

        if (!this.flags.isSet(serializerMember.flags))
            return false;

        return true;
    }

    bool isSerializer(alias serializerMember)() const
    {
        //pragma(msg, serializerMember.memberName ~ ", " ~ serializerMember.memberScope.stringof ~ ", " ~ serializerMember.flags.stringof ~ ", " ~ serializerMember.attribute.condition.stringof);

        if (serializerMember.attribute.condition == Condition.ignored)
            return false;

        if (!this.scopes.isSet(serializerMember.memberScope))
            return false;

        if (!this.flags.isSet(serializerMember.flags))
            return false;

        return true;
    }

public:
    EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.isGetSet
        | SerializableMemberFlag.implicitUDA
        | SerializableMemberFlag.explicitUDA;
    EnumBitSet!SerializableMemberScope scopes = SerializableMemberScope.public_;
}

SerializableMemberOptions getSerializableMemberOptions(T)() nothrow pure
{
    static if (hasUDA!(T, SerializableMemberOptions))
        return getUDA!(T, SerializableMemberOptions);
    else
        return SerializableMemberOptions.init;
}

template allMembers(T)
{
    static if (isSerializerAggregateType!T)
    {
        static if (is(T == struct))
            alias allMembers = aliasSeqOf!(filterMembers([__traits(allMembers, T)]));
        else
            alias allMembers = allClassMembers!T;
    }
    else
        alias allMembers = AliasSeq!();
}

// Returns members of a class with base-class members in front
template allClassMembers(T)
if (is(T == class))
{
    //pragma(msg, T.stringof);

    // Root Object type
    static if (is(T == Object))
        alias allClassMembers = AliasSeq!();
    // Root Object as parent
    else static if (is(BaseTypeTuple!T[0] == Object))
        alias allClassMembers = aliasSeqOf!(filterMembers([__traits(allMembers, T)]));
    // Not a class
    else static if (!is(BaseTypeTuple!T[0] == Object) && !is(BaseTypeTuple!T[0] == class))
        alias allClassMembers = AliasSeq!();
    // Derived class - based members must be first
    else
        alias allClassMembers = NoDuplicates!(allClassMembers!(BaseTypeTuple!T[0]), aliasSeqOf!(filterMembers([__traits(derivedMembers, T)])));
}

template UnsignedFloat(T)
if (isFloatingPoint!T)
{
    static if (is(T == float))
        alias UnsignedFloat = uint;
    else static if (is(T == double))
        alias UnsignedFloat = ulong;
    else
        static assert(0, "Unsupported float type: " ~ T.stringof);
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

bool isExcludedBuildinMember(const(string) memberName) @nogc nothrow pure
{
    // Build in members
    if (memberName.length >= 2 && (memberName[0..2] == "__" || memberName[$-2..$] == "__"))
        return true;

    foreach (const excludedMember; excludedBuildinMembers)
    {
        if (excludedMember == memberName)
            return true;
    }

    return false;
}

enum IsFloatLiteral : ubyte
{
    none,
    nan,
    pinf,
    ninf,
}

struct FloatLiteral
{
    string text;
    IsFloatLiteral kind;
}

static immutable FloatLiteral[13] floatLiterals = [
    // Standard texts first
    FloatLiteral("NaN", IsFloatLiteral.nan),
    FloatLiteral("Infinity", IsFloatLiteral.pinf),
    FloatLiteral("-Infinity", IsFloatLiteral.ninf),
    // Other support texts
    FloatLiteral("nan", IsFloatLiteral.nan),
    FloatLiteral("NAN", IsFloatLiteral.nan),
    FloatLiteral("inf", IsFloatLiteral.pinf),
    FloatLiteral("+inf", IsFloatLiteral.pinf),
    FloatLiteral("-inf", IsFloatLiteral.ninf),
    FloatLiteral("infinity", IsFloatLiteral.pinf),
    FloatLiteral("+infinity", IsFloatLiteral.pinf),
    FloatLiteral("-infinity", IsFloatLiteral.ninf),
    FloatLiteral("Infinite", IsFloatLiteral.pinf), // dlang.std.json
    FloatLiteral("-Infinite", IsFloatLiteral.ninf), // dlang.std.json
];

IsFloatLiteral isFloatLiteral(scope const(char)[] text) @nogc nothrow pure
{
    foreach(ref f; floatLiterals)
    {
        if (f.text == text)
            return f.kind;
    }
    return IsFloatLiteral.none;
}

template isCallableWithTypes(alias func, Args...)
{
    private alias funcParams = Parameters!func;
    private bool sameParamTypes()
    {
        bool result = true;
        static foreach (i; 0..funcParams.length)
        {
            static if (!is(Args[i] : funcParams[i]))
                result = false;
        }
        return result;
    }
    static if (isCallable!func && funcParams.length == Args.length)
        enum bool isCallableWithTypes = sameParamTypes();
    else
        enum bool isCallableWithTypes = false;
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

//if (isAggregateType!V && !isInputRange!V)
enum bool isSerializerAggregateType(T) = (is(T == struct) || is(T == class)) && !isInputRange!T;

template hasCallableWithTypes(T, string memberName, Args...)
if (isSerializerAggregateType!T)
{
    static if (__traits(hasMember, T, memberName))
        enum bool hasCallableWithTypes = isCallableWithTypes!(__traits(getMember, T, memberName), Args);
    else
        enum bool hasCallableWithTypes = false;
}

template isSerializerMember(alias member)
{
    //pragma(msg, member.memberName ~ ", " ~ member.flags.stringof ~ ", " ~ member.attribute.condition.stringof);
    enum bool isSerializerMember = member.flags != SerializableMemberFlag.none
        && member.attribute.condition != Condition.ignored;
}

bool isDeserializerMember(T, alias member)() nothrow pure
{
    enum SerializableMemberOptions attribute = getSerializableMemberOptions!T();
    return isDeserializerMember!(attribute, member)();
}

bool isDeserializerMember(alias attribute, alias member)() nothrow pure
{
    return attribute.isDeserializer!member();
}

bool isSerializerMember(T, alias member)() nothrow pure
{
    enum SerializableMemberOptions attribute = getSerializableMemberOptions!T();
    return isSerializerMember!(attribute, member)();
}

bool isSerializerMember(alias attribute, alias member)() nothrow pure
{
    return attribute.isSerializer!member();
}

string[] getDeserializerMembers(T)() nothrow pure
{
    enum SerializableMemberOptions attribute = getSerializableMemberOptions!T();
    return getDeserializerMembers!(T, attribute)();
}

string[] getDeserializerMembers(T, alias attribute)() nothrow pure
{
    alias members = SerializerMemberList!T;
    string[] result;
    result.reserve(members.length);
    foreach (member; members)
    {
        if (!attribute.isDeserializer!member())
            continue;

        result ~= member.memberName;
    }
    return result;
}

string[] getSerializerMembers(T)() nothrow pure
{
    enum SerializableMemberOptions attribute = getSerializableMemberOptions!T();
    return getSerializerMembers!(T, attribute)();
}

string[] getSerializerMembers(T, alias attribute)() nothrow pure
{
    alias members = SerializerMemberList!T;
    string[] result;
    result.reserve(members.length);
    foreach (member; members)
    {
        if (!attribute.isSerializer!member())
            continue;

        result ~= member.memberName;
    }
    return result;
}

class DSerializerException : Exception
{
@safe:

public:
    this(string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorMessage, file, line, next);
        this.funcName = funcName;
    }

public:
    string funcName;
}

class DeserializerException : DSerializerException
{
@safe:

public:
    this(string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorMessage, next, funcName, file, line);
    }
}

class SerializerException : DSerializerException
{
@safe:

public:
    this(string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorMessage, next, funcName, file, line);
    }
}

template SerializerMember(alias T, string name)
{
@safe:
    private alias member = __traits(getMember, T, name);
    private enum bool hasTypeOfMember = name.length ? hasTypeOfSymbol!member : false;
    private enum bool isTemplateMember = name.length ? isTemplateSymbol!member : false;
    private alias overloads = getOverloads!(T, name);
    //pragma(msg, T.stringof ~ "." ~ name ~ "." ~ overloads.length.stringof ~ "." ~ isTemplateMember.stringof ~ "." ~ hasTypeOfMember.stringof);

    /// The name of the member in the struct/class itself
    alias memberName = name;
    enum isNull = name.length == 0;

    static if (overloads.length > 1 && getGetterSetterFunctions!(overloads).length)
    {
        private alias getterSetter = getGetterSetterFunctions!(overloads);
        alias memberGet = getterSetter[0];
        alias memberSet = getterSetter[1];

        /// Type of the member
        alias memberType = getReturnType!memberGet;

        /// Visibility level of the member
        enum SerializableMemberScope memberScope = toSerializableMemberScope(__traits(getVisibility, memberGet));

        /// Serializable attribute of the member
        static if (hasUDA!(memberGet, Serializable))
        {
            enum Serializable attribute = Serializable(getUDA!(memberGet, Serializable), memberName);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.explicitUDA
                | SerializableMemberFlag.isGetSet;
        }
        else static if (hasUDA!(memberSet, Serializable))
        {
            enum Serializable attribute = Serializable(getUDA!(memberSet, Serializable), memberName);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.explicitUDA
                | SerializableMemberFlag.isGetSet;
        }
        else
        {
            enum Serializable attribute = Serializable(memberName, Condition.required);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.implicitUDA
                | SerializableMemberFlag.isGetSet;
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
        enum SerializableMemberScope memberScope = toSerializableMemberScope(__traits(getVisibility, member));

        /// Default value of the field (may or may not be `Type.init`)
        //alias memberDefault = __traits(getMember, T.init, name);
        //pragma(msg, name ~ "." ~ typeof(memberDefault).stringof);

        /// Serializable attribute of the field
        static if (hasUDA!(member, Serializable))
        {
            enum Serializable attribute = Serializable(getUDA!(member, Serializable), memberName);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.explicitUDA;
        }
        else
        {
            enum Serializable attribute = Serializable(memberName, Condition.required);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.implicitUDA;
        }
    }
    else static if (overloads.length == 0 || isTemplateMember || !__traits(compiles, getReturnType!memberGet))
    {
        alias memberGet = void;
        alias memberSet = void;
        alias memberType = void;
        enum SerializableMemberScope memberScope = SerializableMemberScope.none;
        enum Serializable attribute = Serializable(memberName, Condition.ignored);
        enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.none;
    }
    else
    {
        alias memberGet = overloads[0];
        alias memberSet = void;
        alias memberType = getReturnType!memberGet;
        enum SerializableMemberScope memberScope = toSerializableMemberScope(__traits(getVisibility, memberGet));

        /// Serializable attribute of the function
        static if (hasUDA!(memberGet, Serializable))
        {
            enum Serializable attribute = Serializable(getUDA!(memberGet, Serializable), memberName);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.explicitUDA;
        }
        else
        {
            enum Serializable attribute = Serializable(memberName, Condition.ignored);
            enum EnumBitSet!SerializableMemberFlag flags = SerializableMemberFlag.none;
        }
    }
}

template SerializerMemberList(T)
{
public:
    //pragma(msg, "\nSerializerMemberList()", fullyQualifiedName!T);

    static if (isSerializerAggregateType!T)
    {
        private enum aliasedThisNames = __traits(getAliasThis, T);

        static if (aliasedThisNames.length == 0)
        {
            alias SerializerMemberList = Filter!(isSerializerMember, staticMap!(createSerializerField, allMembers!T));
        }
        else static if (aliasedThisNames.length == 1)
        {
            private enum aliasedThisMembers = __traits(getMember, T, aliasedThisNames);

            // Ignore alias to function
            static if (isSomeFunction!(aliasedThisMembers))
            {
                alias SerializerMemberList = Filter!(isSerializerMember, staticMap!(createSerializerField, allMembers!T));
            }
            else
            {
                private enum baseFields = Erase!(aliasedThisNames, allMembers!T);
                static assert(baseFields.length == allMembers!(T).length - 1);
                private alias allFields = AliasSeq!(staticMap!(createSerializerField, baseFields), SerializerMemberList!(typeof(aliasedThisMembers)));
                alias SerializerMemberList = Filter!(isSerializerMember, allFields);
            }
        }
        else
        {
            alias SerializerMemberList = AliasSeq!();
        }
    }
    else
    {
        alias SerializerMemberList = AliasSeq!();
    }

private:
    alias createSerializerField(string name) = SerializerMember!(T, name);
}

struct SerializerOptions
{
@safe:

public:
    FloatFormat floatFormat = FloatFormat(4, true);
    string floatNaN = "NaN";
    string floatNegInf = "-Infinity";
    string floatPosInf = "+Infinity";
}

enum SerializerDataFormat : ubyte
{
    text,
    binary,
}

enum SerializerDataType : ubyte
{
    unknown,
    null_,
    bool_,
    int1,
    int2,
    int4,
    int8,
    int16_Reserved,
    int32_Reserved,
    float4,
    float8,
    float16_Reserved,
    float32_Reserved,
    char_,
    chars,
    charsKey,
    wchars,
    dchars,
    bytes,
    aggregateBegin,
    aggregateEnd,
    arrayBegin,
    arrayEnd,
}

pragma(inline, true)
bool isNullableDataType(const(SerializerDataType) dataType) @nogc nothrow pure @safe
{
    return dataType == SerializerDataType.null_
        || dataType == SerializerDataType.chars
        || dataType == SerializerDataType.wchars
        || dataType == SerializerDataType.dchars
        || dataType == SerializerDataType.bytes;
}

alias DeserializerFunction = void function(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @safe;
alias SerializerFunction = void function(Serializer serializer, scope void* value, scope ref Serializable attribute) @safe;

struct DSeserializerFunctions
{
    DeserializerFunction deserialize;
    SerializerFunction serialize;
}

class DSeserializer
{
@safe:

public:
    alias Null = typeof(null);
    enum unknownLength = -1;

public:
    size_t decDepth() nothrow
    in
    {
        assert(_depth > 0);
    }
    do
    {
        return --_depth;
    }

    size_t incDepth() nothrow
    {
        return ++_depth;
    }

    static DSeserializerFunctions register(T)(SerializerFunction serialize, DeserializerFunction deserialize) nothrow
    in
    {
        assert(serialize !is null);
        assert(deserialize !is null);
    }
    do
    {
        return register(fullyQualifiedName!T, DSeserializerFunctions(deserialize, serialize));
    }

    static DSeserializerFunctions register(string type, SerializerFunction serialize, DeserializerFunction deserialize) nothrow
    in
    {
        assert(type.length > 0);
        assert(serialize !is null);
        assert(deserialize !is null);
    }
    do
    {
        return register(type, DSeserializerFunctions(deserialize, serialize));
    }

    static DSeserializerFunctions register(string type, DSeserializerFunctions dserializes) nothrow @trusted // access __gshared customDSeserializedFunctions
    in
    {
        assert(type.length > 0);
        assert(dserializes.serialize !is null);
        assert(dserializes.deserialize !is null);
    }
    do
    {
        DSeserializerFunctions result;
        if (auto f = type in customDSeserializedFunctions)
            result = *f;
        customDSeserializedFunctions[type] = dserializes;
        return result;
    }

    bool sameName(scope const(char)[] s1, scope const(char)[] s2) const @nogc nothrow
    {
        return s1 == s2;
    }

    pragma(inline, true)
    @property final size_t depth() const @nogc nothrow
    {
        return _depth;
    }

    @property abstract SerializerDataFormat dataFormat() const @nogc nothrow pure;

public:
    SerializerOptions options;

public:
    static ubyte[] binaryFromString(ExceptionClass)(scope const(char)[] v, const(BinaryFormat) binaryFormat)
    {
        import pham.utl.utl_numeric_parser : NumericParsedKind, parseBase64, parseBase64Length, parseBase16, parseBase16Length;

        string sampleV()
        {
            if (v.length == 0)
                return null;
            else if (v.length > 30)
                return v[0..30].idup ~ " ...";
            else
                return v.idup;
        }

        if (v.length == 0)
            return null;

        Appender!(ubyte[]) buffer;
        final switch (binaryFormat.dataFormat)
        {
            case BinaryDataFormat.base64:
                buffer.reserve(parseBase64Length(v.length));
                if (parseBase64(buffer, v) == NumericParsedKind.ok)
                    return buffer[];
                static if (is(ExceptionClass == void))
                    return null;
                else
                    throw new ExceptionClass("Unable to convert base64 string to binary: " ~ sampleV());
            case BinaryDataFormat.base16:
                buffer.reserve(parseBase16Length(v.length));
                if (parseBase16(buffer, v) == NumericParsedKind.ok)
                    return buffer[];
                static if (is(ExceptionClass == void))
                    return null;
                else
                    throw new ExceptionClass("Unable to convert hex string to binary: " ~ sampleV());
        }
    }

    static string binaryToString(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        import std.ascii : LetterCase;
        import pham.utl.utl_numeric_parser : cvtBytesBase64, cvtBytesBase64Length, cvtBytesBase16, cvtBytesBase16Length;

        if (v.length == 0)
            return null;

        Appender!string buffer;
        final switch (binaryFormat.dataFormat)
        {
            case BinaryDataFormat.base64:
                buffer.reserve(cvtBytesBase64Length(v.length, false, 0));
                return cvtBytesBase64(buffer, v)[];
            case BinaryDataFormat.base16:
                buffer.reserve(cvtBytesBase16Length(v.length, false, 0));
                return binaryFormat.characterCaseFormat == CharacterCaseFormat.lower
                    ? cvtBytesBase16(buffer, v, LetterCase.lower)[]
                    : binaryFormat.characterCaseFormat == CharacterCaseFormat.upper
                        ? cvtBytesBase16(buffer, v, LetterCase.upper)[]
                        : cvtBytesBase16(buffer, v)[];
        }
    }

    final const(char)[] floatToString(V)(return scope char[] vBuffer, V v, const(FloatFormat) floatFormat) pure
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
            return floatLiteralNaN(vBuffer, true);

        if (isInfinity(v))
            return floatLiteralInfinity(vBuffer, sgn(v) != 0, true);

        char[10] fmtBuffer = void;
        const fmt = floatFormat.floatPrecision >= 18 ? "%.18f" : sformat(fmtBuffer[], "%%.%df", floatFormat.floatPrecision);
        return floatFormat.stripTrailingZero
            ? floatStripTrailingZero(sformat(vBuffer, fmt, v))
            : sformat(vBuffer[], fmt, v);
    }

    const(char)[] floatLiteral(return scope char[] vBuffer, scope const(char)[] literal, const(bool) floatConversion) @nogc nothrow pure
    {
        vBuffer[0..literal.length] = literal;
        return vBuffer[0..literal.length];
    }

    final const(char)[] floatLiteralInfinity(return scope char[] vBuffer, const(bool) isNeg, const(bool) floatConversion) @nogc nothrow pure
    {
        return floatLiteral(vBuffer, isNeg ? options.floatNegInf : options.floatPosInf, floatConversion);
    }

    final const(char)[] floatLiteralNaN(return scope char[] vBuffer, const(bool) floatConversion) @nogc nothrow pure
    {
        return floatLiteral(vBuffer, options.floatNaN, floatConversion);
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

protected:
    size_t _depth;
    static __gshared DSeserializerFunctions[string] customDSeserializedFunctions;
}

class Deserializer : DSeserializer
{
@safe:

public:
    Deserializer begin()
    {
        _depth = 0;
        return this;
    }

    Deserializer end()
    {
        return this;
    }

    /*
     * Returns number of members/fields of an aggregate type.
     * If unknown, returns -1
     */
    ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        incDepth();
        return unknownLength;
    }

    void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decDepth();
    }

    /*
     * Returns number of elements in an array.
     * If unknown, returns -1
     */
    ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        incDepth();
        return unknownLength;
    }

    void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decDepth();
    }

    abstract bool empty() nothrow;
    abstract SerializerDataType frontDataType() nothrow;
    abstract bool hasAggregateEle(size_t i, ptrdiff_t len) nothrow;
    abstract bool hasArrayEle(size_t i, ptrdiff_t len) nothrow;

    abstract Null readNull();
    abstract bool readBool();
    abstract char readChar();
    abstract byte readByte();
    abstract short readShort();
    abstract int readInt();
    abstract long readLong();
    abstract float readFloat(const(FloatFormat) floatFormat);
    abstract double readDouble(const(FloatFormat) floatFormat);
    abstract string readChars();
    abstract wstring readWChars();
    abstract dstring readDChars();
    abstract const(char)[] readScopeChars();
    abstract ubyte[] readBytes(const(BinaryFormat) binaryFormat);
    abstract const(ubyte)[] readScopeBytes(const(BinaryFormat) binaryFormat);
    abstract string readKey();
    abstract ptrdiff_t readLength();

public:
    // null
    final void deserialize(V : Null)(V, scope ref Serializable attribute)
    {
        readNull();
    }

    // Boolean
    final void deserialize(V : bool)(ref V v, scope ref Serializable attribute)
    if (is(V == bool) && !is(V == enum))
    {
        v = readBool();
    }

    // Char
    final void deserialize(V : char)(ref V v, scope ref Serializable attribute)
    if (is(V == char) && !is(V == enum))
    {
        v = readChar();
    }

    // Integral
    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (isIntegral!V && !is(V == enum))
    {
        static if (V.sizeof == 4)
            v = readInt();
        else static if (V.sizeof == 8)
            v = readLong();
        else static if (V.sizeof == 2)
            v = readShort();
        else static if (V.sizeof == 1)
            v = readByte();
        else
            static assert(0, "Unsupported integral size: " ~ V.sizeof.stringof);
    }

    // Float
    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (isFloatingPoint!V)
    {
        const floatFormat = attribute.floatFormat.isFloatPrecision()
            ? attribute.floatFormat
            : options.floatFormat;
        static if (V.sizeof == 4)
            v = readFloat(floatFormat);
        else //static if (V.sizeof == 8)
            v = readDouble(floatFormat);
    }

    // Enum
    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (is(V == enum))
    {
        if (attribute.enumFormat == EnumFormat.integral)
        {
            static if (is(V Base == enum) && isIntegral!Base)
            {
                static if (Base.max <= int.max)
                    v = cast(V)readInt();
                else
                    v = cast(V)readLong();
                return;
            }
        }

        const s = readChars();
        v = s.to!V();
    }

    // Chars/String
    final void deserialize(ref char[] v, scope ref Serializable attribute)
    {
        v = readChars().dup;
    }

    // String
    final void deserialize(ref string v, scope ref Serializable attribute)
    {
        v = readChars();
    }

    // WChars/WString
    final void deserialize(ref wchar[] v, scope ref Serializable attribute)
    {
        v = readWChars().dup;
    }

    // WString
    final void deserialize(ref wstring v, scope ref Serializable attribute)
    {
        v = readWChars();
    }

    // DChars/DString
    final void deserialize(ref dchar[] v, scope ref Serializable attribute)
    {
        v = readDChars().dup;
    }

    // WString
    final void deserialize(ref dstring v, scope ref Serializable attribute)
    {
        v = readDChars();
    }

    // Bytes/Binary
    final void deserialize(ref ubyte[] v, scope ref Serializable attribute)
    {
        //import std.stdio : writeln; debug writeln("ubyte[].");
        v = readBytes(attribute.binaryFormat);
    }

    // Array
    final void deserialize(V)(ref V[] v, scope ref Serializable attribute)
    if (!isSomeChar!V && !is(V == ubyte) && !is(V == byte))
    {
        //import std.stdio : writeln; debug writeln(fullyQualifiedName!V, ".", len);

        static immutable elemTypeName = fullyQualifiedName!V;
        size_t length;
        const readLength = arrayBegin(elemTypeName, attribute);
        scope (success)
            arrayEnd(elemTypeName, length, attribute);

        if (readLength == 0)
        {
            v = null;
            return;
        }

        if (readLength > 0 && v.length < readLength)
            v.length = readLength;

        while (hasArrayEle(length, readLength))
        {
            if (length == v.length)
                v.length = length+1;
            deserialize(v[length], attribute);
            length++;
        }
    }

    // Associative array with string key
    final void deserialize(V)(ref V[string] v, scope ref Serializable attribute)
    {
        //import std.stdio : writeln; debug writeln(fullyQualifiedName!V, ".", len);

        static immutable typeName = fullyQualifiedName!(V[string]);
        size_t length;
        const readLength = aggregateBegin(typeName, attribute);
        scope (success)
            aggregateEnd(typeName, length, attribute);

        if (readLength == 0)
        {
            v = null;
            return;
        }

        Serializable memberAttribute = attribute;
        while (hasAggregateEle(length, readLength))
        {
            const keyStr = readKey();
            memberAttribute.name = keyStr;
            V e;
            deserialize(e, memberAttribute);
            v[keyStr] = e;
            length++;
        }
    }

    // Associative array with integral key
    final void deserialize(V : T[K], T, K)(ref V v, scope ref Serializable attribute)
    if (isIntegral!K && !is(K == enum))
    {
        //import std.stdio : writeln; debug writeln(fullyQualifiedName!V, ".", len);

        static immutable typeName = fullyQualifiedName!V;
        size_t length;
        const readLength = aggregateBegin(typeName, attribute);
        scope (success)
            aggregateEnd(typeName, length, attribute);

        if (readLength == 0)
        {
            v = null;
            return;
        }

        Serializable memberAttribute = attribute;
        while (hasAggregateEle(length, readLength))
        {
            const keyStr = readKey();
            const key = keyStr.to!K();
            memberAttribute.name = keyStr;
            T e;
            deserialize(e, memberAttribute);
            v[key] = e;
            length++;
        }
    }

    // Associative array with enum key
    final void deserialize(V : T[K], T, K)(ref V v, scope ref Serializable attribute)
    if (is(K == enum))
    {
        //import std.stdio : writeln; debug writeln(fullyQualifiedName!V, ".", len);

        static immutable typeName = fullyQualifiedName!V;
        size_t length;
        const readLength = aggregateBegin(typeName, attribute);
        scope (success)
            aggregateEnd(typeName, length, attribute);

        if (readLength == 0)
        {
            v = null;
            return;
        }

        Serializable memberAttribute = attribute;
        while (hasAggregateEle(length, readLength))
        {
            const keyStr = readKey();
            K key;
            if (memberAttribute.enumFormat == EnumFormat.integral)
            {
                static if (is(K KBase == enum) && isIntegral!KBase)
                    key = cast(K)(keyStr.to!long());
                else
                    key = keyStr.to!K();
            }
            else
                key = keyStr.to!K();

            memberAttribute.name = keyStr;
            T e;
            deserialize(e, memberAttribute);
            v[key] = e;
            length++;
        }
    }

    // Aggregate (class, struct)
    final V deserialize(V)()
    if (isSerializerAggregateType!V)
    {
        V v;
        Serializable attribute;
        begin();
        deserialize(v, attribute);
        end();
        return v;
    }

    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (isSerializerAggregateType!V)
    {
        //pragma(msg, "\ndeserialize()", fullyQualifiedName!V);
        //import std.stdio : writeln; debug writeln(fullyQualifiedName!V);
        static immutable typeName = fullyQualifiedName!V;
        enum SerializableMemberOptions memberOptions = getSerializableMemberOptions!V();
        ptrdiff_t deserializedLength;
        const readLength = aggregateBegin(typeName, attribute);
        scope (success)
            aggregateEnd(typeName, deserializedLength, attribute);

        if (readLength == 0)
        {
            static if (is(V == class))
                v = null;
            else
                v = V.init;
            return;
        }

        static if (is(V == class))
        {
            if (v is null)
                v = new V();
        }

        scope (success)
        {
            static if (hasCallableWithTypes!(V, "dsDeserializeEnd", Deserializer, ptrdiff_t, Serializable))
                v.dsDeserializeEnd(this, deserializedLength, attribute);
        }

        static if (hasCallableWithTypes!(V, "dsDeserialize", Deserializer, SerializableMemberOptions, ptrdiff_t, Serializable))
        {
            static if (hasCallableWithTypes!(V, "dsDeserializeBegin", Deserializer, ptrdiff_t, Serializable))
                v.dsDeserializeBegin(this, readLength, attribute);

            deserializedLength = v.dsDeserialize(this, memberOptions, readLength, attribute);
        }
        else
        {
            enum MemberMatched {none, deserialize, ok }
            alias members = SerializerMemberList!V;
            size_t i;
            while (hasAggregateEle(i, readLength))
            {
                MemberMatched memberMatched = MemberMatched.none;
                const memberName = readKey();
                //import std.stdio : writeln; debug writeln("i=", i, ", memberName=", memberName);

                static foreach (member; members)
                {
                    if (this.sameName(member.attribute.name, memberName))
                    {
                        //import std.stdio : writeln; debug writeln(V.stringof, "[", typeof(member.memberSet).stringof, ".", member.memberType.stringof, "] v.", member.memberName, ".", member.attribute.name, " vs ", memberName);
                        //pragma(msg, V.stringof ~ "." ~ member.memberName);
                        //pragma(msg, __traits(compiles, __traits(child, v, member.memberSet)));
                        //pragma(msg, __traits(compiles, mixin("v." ~ member.memberName ~ " = member.memberType.init")));
                        //pragma(msg, isCallable!(member.memberSet));

                        static if (__traits(compiles, __traits(child, v, member.memberSet))
                            && (__traits(compiles, mixin("v." ~ member.memberName ~ " = member.memberType.init"))
                                || isCallable!(member.memberSet)))
                        {
                            //import std.stdio : writeln; debug writeln("matched");

                            memberMatched = MemberMatched.ok;

                            if (deserializedLength++ == 0)
                            {
                                static if (hasCallableWithTypes!(V, "dsDeserializeBegin", Deserializer, ptrdiff_t, Serializable))
                                    v.dsDeserializeBegin(this, readLength, attribute);
                            }

                            Serializable memberAttribute = member.attribute;
                            static if (member.flags.isSet(SerializableMemberFlag.isGetSet))
                            {
                                member.memberType memberValue;
                                if (!deserializeCustom!(member.memberType)(memberValue, memberAttribute))
                                {
                                    memberMatched = MemberMatched.deserialize;
                                    static if (__traits(compiles, deserialize(memberValue, memberAttribute)))
                                    {
                                        deserialize(memberValue, memberAttribute);
                                        memberMatched = MemberMatched.ok;
                                    }
                                }
                                //mixin("v." ~ member.memberName) = memberValue;  // Overload issue if only overwrite only one (getter/setter)
                                __traits(child, v, member.memberSet)(memberValue);
                            }
                            else
                            {
                                //pragma(msg, "deserialize()", fullyQualifiedName!(member.memberType), " ", member.memberName);
                                if (!deserializeCustom!(member.memberType)(__traits(child, v, member.memberSet), memberAttribute))
                                {
                                    memberMatched = MemberMatched.deserialize;
                                    static if (__traits(compiles, deserialize(__traits(child, v, member.memberSet), memberAttribute)))
                                    {
                                        deserialize(__traits(child, v, member.memberSet), memberAttribute);
                                        memberMatched = MemberMatched.ok;
                                    }
                                }
                            }
                        }
                    }
                }

                if (memberMatched == MemberMatched.none)
                    throw new DeserializerException(fullyQualifiedName!V ~ "." ~ memberName ~ " not found");
                else if (memberMatched == MemberMatched.deserialize)
                    throw new DeserializerException(fullyQualifiedName!V ~ "." ~ memberName ~ " not able to deserialize");

                i++;
            }
        }

        version(none)
        foreach (member; members)
        {
            if (!isDeserializerMember!(memberOptions, member)())
                continue;

            //pragma(msg, V.stringof ~ "." ~ member.memberName ~ "." ~ member.attribute.name);

            static if (__traits(compiles, __traits(child, v, member.memberSet))
                && __traits(compiles, mixin("v." ~ member.memberName) = member.memberType.init))
            {
                //import std.stdio : writeln; debug writeln(V.stringof, ".", member.memberName, ".", member.attribute.name);

                if (!hasAggregateEle(i, readLength))
                    break;

                if (memberSet++ == 0)
                {
                    static if (__traits(hasMember, V, "deserializeBegin"))
                        v.deserializeBegin(this, readLength, attribute);
                }

                const memberName = readKey();
                Serializable memberAttribute = member.attribute;
                static if (member.flags.isSet(SerializableMemberFlag.isGetSet))
                {
                    member.memberType memberValue;
                    if (!deserializeCustom!(member.memberType)(memberValue, memberAttribute))
                    {
                        deserialize(memberValue, memberAttribute);
                    }
                    mixin("v." ~ member.memberName) = memberValue;
                }
                else
                {
                    if (!deserializeCustom!(member.memberType)(__traits(child, v, member.memberSet), memberAttribute))
                    {
                        deserialize(__traits(child, v, member.memberSet), memberAttribute);
                    }
                }

                i++;
            }
        }
    }

    final void deserializeAny(V)(ref V v, scope ref Serializable attribute)
    {
        if (!deserializeCustom!V(v, attribute))
            deserialize!V(v, attribute);
    }

    // Customized types
    final bool deserializeCustom(V)(ref V v, scope ref Serializable attribute) @trusted // parameter address & access __gshared customDSeserializedFunctions
    {
        //pragma(msg, "deserializeCustom()", fullyQualifiedName!V);
        alias UV = Unqual!V;
        if (auto f = fullyQualifiedName!V in customDSeserializedFunctions)
        {
            (*f).deserialize(this, cast(UV*)&v, attribute);
            return true;
        }

        return false;
    }
}

class Serializer : DSeserializer
{
@safe:

public:
    Serializer begin()
    {
        _depth = 0;
        return this;
    }

    Serializer end()
    {
        return this;
    }

    void aggregateBegin(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        incDepth();
    }

    void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decDepth();
    }

    Serializer aggregateItem(ptrdiff_t index, scope ref Serializable attribute)
    in
    {
        assert(attribute.name.length != 0);
    }
    do
    {
        if (attribute.symbolName)
            writeKeyId(attribute.name);
        else
            writeKey(attribute.name);
        return this;
    }

    void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        incDepth();
    }

    void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decDepth();
    }

    Serializer arrayItem(ptrdiff_t index)
    {
        return this;
    }

    abstract void write(Null v);
    abstract void writeBool(bool v); // Different name - D is not good of distinguish between bool/byte|int
    abstract void writeChar(char v); // Different name - D is not good of distinguish between char/byte|int
    abstract void write(byte v);
    abstract void write(short v);
    abstract void write(int v);
    abstract void write(long v);
    abstract void write(float v, const(FloatFormat) floatFormat);
    abstract void write(double v, const(FloatFormat) floatFormat);
    abstract void write(scope const(char)[] v); // String value
    abstract void write(scope const(wchar)[] v); // WString value
    abstract void write(scope const(dchar)[] v); // DString value
    abstract void write(scope const(ubyte)[] v, const(BinaryFormat) binaryFormat); // Binary value
    abstract Serializer writeKey(scope const(char)[] key);
    abstract Serializer writeKeyId(scope const(char)[] key);

public:
    // null
    final void serialize(Null, scope ref Serializable attribute)
    {
        write(null);
    }

    // Boolean
    final void serialize(V : bool)(const(V) v, scope ref Serializable attribute)
    if (is(V == bool) && !is(V == enum))
    {
        writeBool(v);
    }

    // Char
    final void serialize(V : char)(const(V) v, scope ref Serializable attribute)
    if (is(V == char) && !is(V == enum))
    {
        writeChar(v);
    }

    // Integral
    final void serialize(V)(const(V) v, scope ref Serializable attribute)
    if (isIntegral!V && !is(V == enum))
    {
        write(v);
    }

    // Float
    final void serialize(V)(const(V) v, scope ref Serializable attribute)
    if (isFloatingPoint!V)
    {
        const floatFormat = attribute.floatFormat.isFloatPrecision()
            ? attribute.floatFormat
            : options.floatFormat;
        return write(v, floatFormat);
    }

    // Enum
    final void serialize(V)(V v, scope ref Serializable attribute)
    if (is(V == enum))
    {
        if (attribute.enumFormat == EnumFormat.integral)
        {
            static if (is(V Base == enum) && isIntegral!Base)
            {
                static if (Base.max <= int.max)
                    write(cast(int)v);
                else
                    write(cast(long)v);
                return;
            }
        }

        const vStr = v.to!string();
        write(vStr);
    }

    // Chars/String
    final void serialize(scope const(char)[] v, scope ref Serializable attribute)
    {
        write(v);
    }

    // String
    final void serialize(string v, scope ref Serializable attribute)
    {
        write(v);
    }

    // WChars/WString
    final void serialize(scope const(wchar)[] v, scope ref Serializable attribute)
    {
        write(v);
    }

    // WString
    final void serialize(wstring v, scope ref Serializable attribute)
    {
        write(v);
    }

    // DChars/DString
    final void serialize(scope const(dchar)[] v, scope ref Serializable attribute)
    {
        write(v);
    }

    // DString
    final void serialize(dstring v, scope ref Serializable attribute)
    {
        write(v);
    }

    // Bytes/Binary
    final void serialize(scope const(ubyte)[] v, scope ref Serializable attribute)
    {
        write(v, attribute.binaryFormat);
    }

    // Array
    final void serialize(V)(V[] v, scope ref Serializable attribute)
    if (!isSomeChar!V && !is(V == ubyte) && !is(V == byte))
    {
        static immutable elemTypeName = fullyQualifiedName!V;
        arrayBegin(elemTypeName, v.length, attribute);
        scope (success)
            arrayEnd(elemTypeName, v.length, attribute);

        foreach (i, ref e; v)
        {
            arrayItem(i);
            serialize(e, attribute);
        }
    }

    // Input range
    final void serialize(R)(R v, scope ref Serializable attribute)
    if (isInputRange!R && !isSomeChar!(ElementType!R) && !isDynamicArray!R)
    {
        static immutable typeName = fullyQualifiedName!(ElementType!R);
        size_t length;
        arrayBegin(typeName, -1, attribute);
        scope (success)
            arrayEnd(typeName, length, attribute);

        foreach (ref e; v)
        {
            arrayItem(length);
            serialize(e, attribute);
            length++;
        }
    }

    // Associative array with string key
    final void serialize(V)(V[string] v, scope ref Serializable attribute)
    {
        static immutable typeName = fullyQualifiedName!(V[string]);
        const length = v.length;
        aggregateBegin(typeName, length, attribute);
        scope (success)
            aggregateEnd(typeName, length, attribute);

        if (length == 0)
            return;

        size_t index;
        Serializable memberAttribute = attribute;
        memberAttribute.symbolName = false;
        foreach (key, ref val; v)
        {
            memberAttribute.name = key;
            aggregateItem(index, memberAttribute);
            serialize(val, memberAttribute);
            index++;
        }
    }

    // Associative array with integral key
    final void serialize(V : const T[K], T, K)(V v, scope ref Serializable attribute) @trusted
    if (isIntegral!K && !is(K == enum))
    {
        import std.format : sformat;

        static immutable typeName = fullyQualifiedName!T ~ "[" ~ K.stringof ~ "]";
        const length = v.length;
        aggregateBegin(typeName, length, attribute);
        scope (success)
            aggregateEnd(typeName, length, attribute);

        if (length == 0)
            return;

        size_t index;
        char[50] keyBuffer = void;
        Serializable memberAttribute = attribute;
        memberAttribute.symbolName = true;
        foreach (key, ref val; v)
        {
            const keyStr = sformat(keyBuffer[], "%d", key);
            memberAttribute.name = cast(string)keyStr;
            aggregateItem(index, memberAttribute);
            serialize(val, memberAttribute);
            index++;
        }
    }

    // Associative array with enum key
    final void serialize(V : const T[K], T, K)(V v, scope ref Serializable attribute)
    if (is(K == enum))
    {
        static immutable typeName = fullyQualifiedName!T ~ "[" ~ (fullyQualifiedName!K).stringof ~ "]";
        const length = v.length;
        aggregateBegin(typeName, length, attribute);
        scope (success)
            aggregateEnd(typeName, length, attribute);

        if (length == 0)
            return;

        string keyStr;
        size_t index;
        Serializable memberAttribute = attribute;
        memberAttribute.symbolName = true;
        foreach (key, ref val; v)
        {
            if (memberAttribute.enumFormat == EnumFormat.integral)
            {
                static if (is(K KBase == enum) && isIntegral!KBase)
                    keyStr = (cast(long)key).to!string();
                else
                    keyStr = key.to!string();
            }
            else
                keyStr = key.to!string();
            memberAttribute.name = keyStr;
            aggregateItem(index, memberAttribute);
            serialize(val, memberAttribute);
            index++;
        }
    }

    // Aggregate (class, struct)
    final void serialize(V)(auto ref V v)
    if (isSerializerAggregateType!V)
    {
        Serializable attribute;
        begin();
        serialize(v, attribute);
        end();
    }

    final void serialize(V)(auto ref V v, scope ref Serializable attribute) @trusted // opEqual
    if (isSerializerAggregateType!V)
    {
        bool vIsNull() nothrow @safe
        {
            static if (is(V == class))
                return v is null;
            else
                return false;
        }

        ptrdiff_t serializeredLength;
        static immutable typeName = fullyQualifiedName!V;
        alias members = SerializerMemberList!V;
        enum SerializableMemberOptions memberOptions = getSerializableMemberOptions!V();
        aggregateBegin(typeName, vIsNull() ? 0 : unknownLength, attribute);
        scope (success)
            aggregateEnd(typeName, serializeredLength, attribute);

        if (vIsNull())
            return;

        scope (success)
        {
            static if (hasCallableWithTypes!(V, "dsSerializeEnd", Serializer, size_t, Serializable))
                v.dsSerializeEnd(this, serializeredLength, attribute);
        }

        static if (hasCallableWithTypes!(V, "dsSerialize", Serializer, SerializableMemberOptions, Serializable))
        {
            static if (hasCallableWithTypes!(V, "dsSerializeBegin", Serializer, size_t, Serializable))
                v.dsSerializeBegin(this, members.length, attribute);

            serializeredLength = v.dsSerialize(this, memberOptions, attribute);
        }
        else
        {
            foreach (member; members)
            {
                if (!isSerializerMember!(memberOptions, member)())
                    continue;

                //pragma(msg, V.stringof ~ "." ~ member.memberName ~ "." ~ member.attribute.name);

                static if (__traits(compiles, __traits(child, v, member.memberGet)))
                {
                    //import std.stdio : writeln; debug writeln(V.stringof, ".", member.memberName, ".", member.attribute.name);

                    auto memberValue = __traits(child, v, member.memberGet);
                    Serializable memberAttribute = member.attribute;
                    memberAttribute.symbolName = false;

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
                        //if ((() @trusted => memberValue == __traits(child, V.init, member.memberGet))())
                        if (memberValue == __traits(child, V.init, member.memberGet))
                            continue;
                    }

                    // First member?
                    if (serializeredLength == 0)
                    {
                        static if (hasCallableWithTypes!(V, "dsSerializeBegin", Serializer, size_t, Serializable))
                            v.dsSerializeBegin(this, members.length, attribute);
                    }

                    aggregateItem(serializeredLength, memberAttribute);
                    if (!serializeCustom!(member.memberType)(memberValue, memberAttribute))
                        serialize(memberValue, memberAttribute);
                    serializeredLength++;
                }
            }
        }
    }

    final void serializeAny(V)(auto ref V v, scope ref Serializable attribute)
    {
        if (!serializeCustom!V(v, attribute))
            serialize!V(v, attribute);
    }

    // Customized types
    final bool serializeCustom(V)(auto ref V v, scope ref Serializable attribute) @trusted // parameter address & access __gshared customDSeserializedFunctions
    {
        alias UV = Unqual!V;
        if (auto f = fullyQualifiedName!V in customDSeserializedFunctions)
        {
            (*f).serialize(this, cast(UV*)&v, attribute);
            return true;
        }

        return false;
    }
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

SerializableMemberScope toSerializableMemberScope(scope const(char)[] visibility) @nogc nothrow pure
{
    return visibility == "public" || visibility == "export"
        ? SerializableMemberScope.public_
        : (visibility == "protected" || visibility == "package"
            ? SerializableMemberScope.protected_
            : SerializableMemberScope.private_); // visibility == "private"
}

version(unittest)
{
package(pham.ser):

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
        private int _publicGetSet;

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

        ref typeof(this) setValues() return
        {
            _publicGetSet = 1;
            publicInt = 20;
            return this;
        }

        void assertValues()
        {
            assert(_publicGetSet == 1, _publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 20, publicInt.to!string);
            assert(protectedInt == 0, protectedInt.to!string);
            assert(privateInt == 0, privateInt.to!string);
        }

    protected:
        int protectedInt = 0;
        int _protectedGetSet = 3;

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
        int privateInt = 0;
        int _privateGetSet = 5;

        int privateGetSet()
        {
            return _privateGetSet;
        }

        int privateGetSet(int i)
        {
            _privateGetSet = i;
            return i;
        }
    }

    static class UnitTestC1
    {
    public:
        @Serializable("Int")
        int publicInt;

        private int _publicGetSet;
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
            publicInt = 30;
            publicStruct.setValues();
            return this;
        }

        void assertValues()
        {
            assert(_publicGetSet == 1, _publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 30, publicInt.to!string);
            publicStruct.assertValues();
            assert(protectedInt == 0, protectedInt.to!string);
            assert(privateInt == 0, privateInt.to!string);
        }

    protected:
        int protectedInt = 0;
        int _protectedGetSet = 3;

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
        int privateInt = 0;
        int _privateGetSet = 5;

        int privateGetSet()
        {
            return _privateGetSet;
        }

        int privateGetSet(int i)
        {
            _privateGetSet = i;
            return i;
        }
    }

    class UnitTestC2 : UnitTestC1
    {
    public:
        string publicStr;

        override int publicGetSet()
        {
            return _publicGetSet;
        }

        override UnitTestC2 setValues()
        {
            super.setValues();
            publicStr = "C2 public string";
            return this;
        }

        override void assertValues()
        {
            super.assertValues();
            assert(publicStr == "C2 public string", publicStr);
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

        typeof(this) setValues()
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

        void assertValues()
        {
            import std.math : isInfinity, isNaN;

            assert(enum1 == UnitTestEnum.third, enum1.to!string);
            assert(bool1 == true, bool1.to!string);
            assert(byte1 == 101, byte1.to!string);
            assert(short1 == -1003, short1.to!string);
            assert(ushort1 == 3975, ushort1.to!string);
            assert(int1 == -382653, int1.to!string);
            assert(uint1 == 3957209, uint1.to!string);
            assert(long1 == -394572364, long1.to!string);
            assert(ulong1 == 284659274, ulong1.to!string);
            assert(float1 == 6394763.5, float1.to!string);
            assert(floatNaN.isNaN, floatNaN.to!string);
            assert(double1 == -2846627456445.765, double1.to!string);
            assert(doubleInf.isInfinity, doubleInf.to!string);
            assert(string1 == "test string of", string1);
            assert(charArray == "will this work?", charArray);
            assert(binary1 == [37,24,204,101,43], binary1.to!string);
            assert(intArray == [135,937,3725,3068,38465,380], intArray.to!string);
            assert(intArrayNull is null);
            assert(intInt[2] == 23456, intInt[2].to!string);
            assert(intInt[11] == 113456, intInt[11].to!string);
            assert(intIntNull is null);
            assert(enumEnum[UnitTestEnum.third] == UnitTestEnum.second, enumEnum[UnitTestEnum.third].to!string);
            assert(enumEnum[UnitTestEnum.forth] == UnitTestEnum.sixth, enumEnum[UnitTestEnum.forth].to!string);
            assert(strStr["key1"] == "key1 value", strStr["key1"]);
            assert(strStr["key2"] == "key2 value", strStr["key2"]);
            assert(strStr["key3"] is null, strStr["key3"]);
            struct1.assertValues();
            assert(class1 !is null);
            class1.assertValues();
            assert(class1Null is null);
        }
    }

    static uint serializerCounter, deserializerCounter;
    static struct UnitTestCustomS1
    {
    public:
        UnitTestS1 s1;
        dstring ds;
        int iSkip;
        wstring ws;
        char c1;

        ref typeof(this) setValues() return @safe
        {
            serializerCounter = deserializerCounter = 0;

            s1.setValues();
            ds = "d string"d;
            iSkip = 0;
            ws = "w string"w;
            c1 = 'U';
            return this;
        }

        void assertValues() @safe
        {
            s1.assertValues();
            assert(ds == "d string"d);
            assert(iSkip == 0);
            assert(ws == "w string"w);
            assert(c1 == 'U');
            assert(deserializerCounter == 3);
            assert(serializerCounter == 3);
        }

        /**
         * Returns number of members being deserialized
         */
        ptrdiff_t dsDeserialize(Deserializer deserializer, SerializableMemberOptions memberOptions, ptrdiff_t readLength, scope ref Serializable attribute) @safe
        {
            Serializable memberAttribute;
            ref Serializable setMemberAttribute(string name)
            {
                memberAttribute.name = name;
                memberAttribute.memberName = name;
                return memberAttribute;
            }

            // std.json does not maintain members order, so must check by name
            size_t i;
            while (deserializer.hasAggregateEle(i, readLength))
            {
                const n = deserializer.readKey();
                if (deserializer.sameName(n, "s1"))
                    deserializer.deserialize(s1, setMemberAttribute(n));
                else if (deserializer.sameName(n, "ds"))
                    deserializer.deserialize(ds, setMemberAttribute(n));
                else if (deserializer.sameName(n, "ws"))
                    deserializer.deserialize(ws, setMemberAttribute(n));
                else if (deserializer.sameName(n, "c1"))
                    deserializer.deserialize(c1, setMemberAttribute(n));
                else
                    assert(0);
                i++;
            }
            assert(i == 4);
            return i;
        }

        void dsDeserializeBegin(Deserializer deserializer, ptrdiff_t readLength, scope ref Serializable attribute) @safe
        {
            deserializerCounter = 1;
        }

        void dsDeserializeEnd(Deserializer deserializer, ptrdiff_t deserializedLength, scope ref Serializable attribute) @safe
        {
            deserializerCounter |= 2;
        }

        /**
         * Returns number of members being serialized
         */
        ptrdiff_t dsSerialize(Serializer serializer, SerializableMemberOptions memberOptions, scope ref Serializable attribute) @safe
        {
            Serializable memberAttribute;
            ref Serializable setMemberAttribute(string name)
            {
                memberAttribute.name = name;
                memberAttribute.memberName = name;
                return memberAttribute;
            }

            serializer.aggregateItem(0, setMemberAttribute("s1")).serialize(s1, memberAttribute);
            serializer.aggregateItem(1, setMemberAttribute("ds")).serialize(ds, memberAttribute);
            serializer.aggregateItem(2, setMemberAttribute("ws")).serialize(ws, memberAttribute);
            serializer.aggregateItem(3, setMemberAttribute("c1")).serialize(c1, memberAttribute);

            return 4;
        }

        void dsSerializeBegin(Serializer serializer, ptrdiff_t memberLength, scope ref Serializable attribute) @safe
        {
            serializerCounter = 1;
        }

        void dsSerializeEnd(Serializer serializer, ptrdiff_t serializeredLength, scope ref Serializable attribute) @safe
        {
            serializerCounter |= 2;
        }
    }
}

private:

static immutable excludedBuildinMembers = [
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

    foreach (member; allMembers)
    {
        if (!isExcludedBuildinMember(member))
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

unittest // isCallableWithTypes
{
    static struct S
    {
        ptrdiff_t deserialize(Deserializer deserializer, SerializableMemberOptions memberOptions, ptrdiff_t readLength, scope ref Serializable attribute) @safe
        {
            return 0;
        }

        ptrdiff_t serialize(Serializer serializer, SerializableMemberOptions memberOptions, scope ref Serializable attribute) @safe
        {
            return 1;
        }
    }

    ptrdiff_t deserialize(Deserializer deserializer, SerializableMemberOptions memberOptions, ptrdiff_t readLength, scope ref Serializable attribute) @safe
    {
        return 0;
    }

    ptrdiff_t serialize(Serializer serializer, SerializableMemberOptions memberOptions, scope ref Serializable attribute) @safe
    {
        return 1;
    }

    static assert (isCallableWithTypes!(deserialize, Deserializer, SerializableMemberOptions, size_t, Serializable));
    static assert (isCallableWithTypes!(serialize, Serializer, SerializableMemberOptions, Serializable));

    alias deserializeMember = __traits(getMember, S, "deserialize");
    static assert (isCallableWithTypes!(deserializeMember, Deserializer, SerializableMemberOptions, size_t, Serializable));
    alias serializeMember = __traits(getMember, S, "serialize");
    static assert (isCallableWithTypes!(serializeMember, Serializer, SerializableMemberOptions, Serializable));
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
    assert(names == ["publicInt", "_publicGetSet", "publicGetSet", "protectedInt", "_protectedGetSet", "protectedGetSet", "privateInt", "_privateGetSet", "privateGetSet"], names.to!string());

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
    assert(names == ["publicInt", "_publicGetSet", "publicStruct", "publicGetSet", "protectedInt", "_protectedGetSet", "protectedGetSet", "privateInt", "_privateGetSet", "privateGetSet"], names.to!string());

    names = null;
    //pragma(msg, SerializerMemberList!UnitTestC2);
    alias c2 = SerializerMemberList!UnitTestC2;
    static assert(c2.length == 11, c2.length.stringof);
    static foreach (i; 0..c2.length)
    {
        names ~= c2[i].memberName;
    }
    assert(names == ["publicInt", "_publicGetSet", "publicStruct", "publicGetSet", "protectedInt", "_protectedGetSet", "protectedGetSet", "privateInt", "_privateGetSet", "privateGetSet", "publicStr"], names.to!string());
}

unittest // SerializableMemberOptions - Default
{
    import std.conv : to;

    SerializableMemberOptions options;

    const deserializerMembers = getDeserializerMembers!(UnitTestS1, options)();
    assert(deserializerMembers.length == 2, deserializerMembers.length.to!string() ~ "." ~ deserializerMembers.to!string());
    assert(deserializerMembers == ["publicInt", "publicGetSet"]);

    const serializerMembers = getSerializerMembers!(UnitTestS1, options)();
    assert(serializerMembers.length == 2, serializerMembers.length.to!string() ~ "." ~ serializerMembers.to!string());
    assert(serializerMembers == ["publicInt", "publicGetSet"]);
}

unittest // SerializableMemberOptions - Change options
{
    import std.conv : to;
    SerializableMemberOptions options;

    // All scopes
    options.scopes = SerializableMemberScope.public_ | SerializableMemberScope.protected_ | SerializableMemberScope.private_;
    static immutable expectAllScopes = ["publicInt", "_publicGetSet", "publicStruct", "publicGetSet", "protectedInt", "_protectedGetSet", "protectedGetSet", "privateInt", "_privateGetSet", "privateGetSet", "publicStr"];

    const deserializerMembers = getDeserializerMembers!(UnitTestC2, options)();
    //import std.stdio; writeln; debug writeln(deserializerMembers); debug writeln(expectAllScopes);
    assert(deserializerMembers.length == 11, deserializerMembers.length.to!string() ~ "." ~ deserializerMembers.to!string());
    assert(deserializerMembers == expectAllScopes, deserializerMembers.to!string());
    const serializerMembers = getSerializerMembers!(UnitTestC2, options)();
    assert(serializerMembers.length == 11, serializerMembers.length.to!string() ~ "." ~ serializerMembers.to!string());
    assert(serializerMembers == expectAllScopes, serializerMembers.to!string());

    // With attribute only
    options.scopes = SerializableMemberScope.public_ | SerializableMemberScope.protected_ | SerializableMemberScope.private_;
    options.flags = SerializableMemberFlag.isGetSet | SerializableMemberFlag.explicitUDA;
    static immutable expectAttributeOnly = ["publicInt", "publicGetSet"];

    const deserializerMembers2 = getDeserializerMembers!(UnitTestC2, options)();
    //import std.stdio; writeln; debug writeln(deserializerMembers2); debug writeln(expectAttributeOnly);
    assert(deserializerMembers2.length == 2, deserializerMembers2.length.to!string() ~ "." ~ deserializerMembers2.to!string());
    assert(deserializerMembers2 == expectAttributeOnly, deserializerMembers2.to!string());
    const serializerMembers2 = getSerializerMembers!(UnitTestC2, options)();
    assert(serializerMembers2.length == 2, serializerMembers2.length.to!string() ~ "." ~ serializerMembers2.to!string());
    assert(serializerMembers2 == expectAttributeOnly, serializerMembers2.to!string());
}
