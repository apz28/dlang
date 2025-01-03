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

import std.conv : to;
import std.meta : AliasSeq, aliasSeqOf, Filter, NoDuplicates, staticMap;
import std.range : ElementType, isInputRange;
import std.traits : BaseClassesTuple, BaseTypeTuple, EnumMembers, fullyQualifiedName,
    isAggregateType, isCallable, isDynamicArray, isFloatingPoint, isIntegral, isSomeChar, isSomeFunction,
    isStaticArray, Unqual;
import std.uni : sicmp;

debug(pham_ser_ser_serialization) import std.stdio : writeln;
import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_enum_set : EnumSet;
import pham.utl.utl_trait;

@safe:

enum Condition : ubyte
{
    required,
    optional,
    ignored,
    ignoredDefault,
    ignoredNull,
}

enum CharacterCase : ubyte
{
    normal,
    upper,
    lower,
}

enum DataKind : ubyte
{
    binary,
    character,
    enumerate,
    integral,
    decimal,
    date,
    dateTime,
    time,
    uuid,
}

enum DbKey : ubyte
{
    none,
    index,
    foreign,
    primary,
}

enum EncodedFormat : ubyte
{
    base64,
    base16,
}

enum EnumFormat : ubyte
{
    name,
    integral,
}

struct BinaryFormat
{
@nogc nothrow @safe:

    EncodedFormat encodedFormat;
    CharacterCase characterCase;
}

struct DbEntity
{
nothrow @safe:

public:
    string name;
    DbKey dbKey;
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
        this(name, null, DbEntity.init, condition);
    }

    this(string name, string memberName,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, memberName, DbEntity.init, condition);
    }

    this(string name, DbEntity dbEntity,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, dbEntity, condition);
    }

    this(string name, string memberName, DbEntity dbEntity,
        Condition condition = Condition.required) @nogc pure
    {
        this.name = name;
        this._memberName = memberName;
        this.dbEntity = dbEntity;
        this.condition = condition;
        this.flags = EnumSet!Flag.init;
    }

    this(string name, BinaryFormat binaryFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, binaryFormat, condition);
    }

    this(string name, string memberName, BinaryFormat binaryFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, memberName, DbEntity.init, condition);
        this.binaryFormat = binaryFormat;
    }

    this(string name, EnumFormat enumFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, enumFormat, condition);
    }

    this(string name, string memberName, EnumFormat enumFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, memberName, DbEntity.init, condition);
        this.enumFormat = enumFormat;
    }

    this(string name, FloatFormat floatFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, null, floatFormat, condition);
    }

    this(string name, string memberName, FloatFormat floatFormat,
        Condition condition = Condition.required) @nogc pure
    {
        this(name, memberName, DbEntity.init, condition);
        this.floatFormat = floatFormat;
    }

    this(Serializable other, string memberName) @nogc pure
    in
    {
        assert(memberName.length != 0);
    }
    do
    {
        this(other.name.length != 0 ? other.name : memberName, memberName, other.condition);
        this.dbEntity = other.dbEntity;
        this.binaryFormat = other.binaryFormat;
        this.enumFormat = other.enumFormat;
        this.floatFormat = other.floatFormat;
        this.flags = other.flags;
    }

    pragma(inline, true)
    bool sameName(scope const(char)[] rhs, const(bool) caseSensitiveName) const @nogc
    {
        return caseSensitiveName
            ? ((name == rhs) || (hasDbName && dbEntity.name == rhs))
            : ((sicmp(name, rhs) == 0) || (hasDbName && sicmp(dbEntity.name, rhs) == 0));
    }

    pragma(inline, true)
    @property bool hasDbName() const @nogc
    {
        return dbEntity.name.length != 0;
    }

    @property DbKey dbKey() const @nogc
    {
        return dbEntity.dbKey;
    }

    @property ref Serializable dbKey(DbKey value) @nogc return
    {
        dbEntity.dbKey = value;
        return this;
    }

    // Used for table or column name
    pragma(inline, true)
    @property string dbName() const @nogc
    {
        return dbEntity.name.length ? dbEntity.name : name;
    }

    @property ref Serializable dbName(string value) @nogc return
    {
        dbEntity.name = value;
        return this;
    }

    pragma(inline, true)
    @property string memberName() const @nogc
    {
        return _memberName.length ? _memberName : name;
    }

    @property ref Serializable memberName(string value) @nogc return
    {
        this._memberName = value;
        return this;
    }

    enum Flag: ubyte
    {
        symbolId,
    }

public:
    string name;
    string _memberName;
    DbEntity dbEntity; // Used for table or column name
    Condition condition;
    BinaryFormat binaryFormat;
    EnumFormat enumFormat;
    FloatFormat floatFormat = FloatFormat(ubyte.max, false);
    EnumSet!Flag flags;
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
    this(EnumSet!SerializableMemberFlag flags, EnumSet!SerializableMemberScope scopes) @nogc pure
    {
        this.flags = flags;
        this.scopes = scopes;
    }

    bool isDeserializer(alias serializerMember)() const
    {
        //import std.stdio; writeln; debug writeln(serializerMember.memberName, "=", serializerMember.memberScope, "/", this.scopes, ", ", serializerMember.flags, "/", this.flags);

        if (serializerMember.attribute.condition == Condition.ignored)
            return false;

        if (!this.scopes.isOn(serializerMember.memberScope))
            return false;

        if (!this.flags.isAll(serializerMember.flags))
            return false;

        return true;
    }

    bool isSerializer(alias serializerMember)() const
    {
        //pragma(msg, serializerMember.memberName ~ ", " ~ serializerMember.memberScope.stringof ~ ", " ~ serializerMember.flags.stringof ~ ", " ~ serializerMember.attribute.condition.stringof);

        if (serializerMember.attribute.condition == Condition.ignored)
            return false;

        if (!this.scopes.isOn(serializerMember.memberScope))
            return false;

        if (!this.flags.isAll(serializerMember.flags))
            return false;

        return true;
    }

public:
    EnumSet!SerializableMemberFlag flags = EnumSet!SerializableMemberFlag([SerializableMemberFlag.isGetSet
        , SerializableMemberFlag.implicitUDA
        , SerializableMemberFlag.explicitUDA]);
    EnumSet!SerializableMemberScope scopes = SerializableMemberScope.public_;
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
    alias UT = Unqual!T;
    static if (is(UT == double))
        alias UnsignedFloat = ulong;
    else static if (is(UT == float))
        alias UnsignedFloat = uint;
    else
        static assert(0, "Unsupported float type: " ~ T.stringof);
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

static __gshared Dictionary!(string, IsFloatLiteral) floatLiterals;

IsFloatLiteral isFloatLiteral(scope const(char)[] text) @nogc nothrow @trusted
{
    if (auto f = text in floatLiterals)
        return *f;
    return IsFloatLiteral.none;
}

//if (isAggregateType!V && !isInputRange!V)
enum bool isSerializerAggregateType(T) = (is(T == struct) || is(T == class)) && !isInputRange!T;

template isSerializerMember(alias member)
{
    //pragma(msg, member.memberName ~ ", " ~ member.flags.stringof ~ ", " ~ member.attribute.condition.stringof);
    enum bool isSerializerMember = member.flags.isOff(SerializableMemberFlag.none)
        && member.attribute.condition != Condition.ignored;
}

version(none)
bool isDeserializerMember(T, alias member)() nothrow pure
{
    enum SerializableMemberOptions attribute = getSerializableMemberOptions!T();
    return isDeserializerMember!(attribute, member)();
}

bool isDeserializerMember(alias attribute, alias member)() nothrow pure
{
    return attribute.isDeserializer!member();
}

version(none)
bool isSerializerMember(T, alias member)() nothrow pure
{
    enum SerializableMemberOptions attribute = getSerializableMemberOptions!T();
    return isSerializerMember!(attribute, member)();
}

bool isSerializerMember(alias attribute, alias member)() nothrow pure
{
    return attribute.isSerializer!member();
}

Serializable[] getDeserializerMembers(T)() nothrow pure
{
    enum SerializableMemberOptions attributeT = getSerializableMemberOptions!T();
    return getDeserializerMembers!(T, attributeT)();
}

Serializable[] getDeserializerMembers(T, alias attributeT)() nothrow pure
{
    alias members = SerializerMemberList!T;
    Serializable[] result;
    result.reserve(members.length);
    foreach (member; members)
    {
        if (!attributeT.isDeserializer!member())
            continue;

        result ~= member.attribute;
    }
    return result;
}

Serializable[] getSerializerMembers(T)() nothrow pure
{
    enum SerializableMemberOptions attributeT = getSerializableMemberOptions!T();
    return getSerializerMembers!(T, attributeT)();
}

Serializable[] getSerializerMembers(T, alias attributeT)() nothrow pure
{
    alias members = SerializerMemberList!T;
    Serializable[] result;
    result.reserve(members.length);
    foreach (member; members)
    {
        if (!attributeT.isSerializer!member())
            continue;

        result ~= member.attribute;
    }
    return result;
}

class DSSerializerException : Exception
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

class DeserializerException : DSSerializerException
{
@safe:

public:
    this(string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorMessage, next, funcName, file, line);
    }
}

class SerializerException : DSSerializerException
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
            enum EnumSet!SerializableMemberFlag flags = EnumSet!SerializableMemberFlag(SerializableMemberFlag.explicitUDA
                , SerializableMemberFlag.isGetSet);
        }
        else static if (hasUDA!(memberSet, Serializable))
        {
            enum Serializable attribute = Serializable(getUDA!(memberSet, Serializable), memberName);
            enum EnumSet!SerializableMemberFlag flags = EnumSet!SerializableMemberFlag(SerializableMemberFlag.explicitUDA
                , SerializableMemberFlag.isGetSet);
        }
        else
        {
            enum Serializable attribute = Serializable(memberName, memberName, Condition.required);
            enum EnumSet!SerializableMemberFlag flags = EnumSet!SerializableMemberFlag(SerializableMemberFlag.implicitUDA
                , SerializableMemberFlag.isGetSet);
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
            enum EnumSet!SerializableMemberFlag flags = SerializableMemberFlag.explicitUDA;
        }
        else
        {
            enum Serializable attribute = Serializable(memberName, memberName, Condition.required);
            enum EnumSet!SerializableMemberFlag flags = SerializableMemberFlag.implicitUDA;
        }
    }
    else static if (overloads.length == 0 || isTemplateMember || !__traits(compiles, getReturnType!memberGet))
    {
        alias memberGet = void;
        alias memberSet = void;
        alias memberType = void;
        enum SerializableMemberScope memberScope = SerializableMemberScope.none;
        enum Serializable attribute = Serializable(memberName, memberName, Condition.ignored);
        enum EnumSet!SerializableMemberFlag flags = SerializableMemberFlag.none;
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
            enum EnumSet!SerializableMemberFlag flags = SerializableMemberFlag.explicitUDA;
        }
        else
        {
            enum Serializable attribute = Serializable(memberName, memberName, Condition.ignored);
            enum EnumSet!SerializableMemberFlag flags = SerializableMemberFlag.none;
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
    bool caseSensitiveName;
}

enum SerializerDataFormat : ubyte
{
    text,
    binary,
}

alias DeserializerFunction = void function(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @safe;
alias SerializerFunction = void function(Serializer serializer, scope void* value, scope ref Serializable attribute) @safe;

struct DSSerializerFunctions
{
    DeserializerFunction deserialize;
    SerializerFunction serialize;
}

abstract class DSSerializer
{
@safe:

public:
    alias Null = typeof(null);
    enum unknownLength = -1;

public:
    BinaryFormat binaryFormat(scope ref Serializable attribute) const nothrow
    {
        return attribute.binaryFormat;
    }

    FloatFormat floatFormat(scope ref Serializable attribute) const nothrow
    {
        return attribute.floatFormat.isFloatPrecision() ? attribute.floatFormat : options.floatFormat;
    }

    size_t decArrayDepth() nothrow
    in
    {
        assert(_arrayDepth > 0);
    }
    do
    {
        return --_arrayDepth;
    }

    size_t decMemberDepth() nothrow
    in
    {
        assert(_memberDepth > 0);
    }
    do
    {
        return --_memberDepth;
    }

    size_t incArrayDepth() nothrow
    {
        return ++_arrayDepth;
    }

    size_t incMemberDepth() nothrow
    {
        return ++_memberDepth;
    }

    static DSSerializerFunctions register(T)(SerializerFunction serialize, DeserializerFunction deserialize) nothrow
    in
    {
        assert(serialize !is null);
        assert(deserialize !is null);
    }
    do
    {
        return register(fullyQualifiedName!T, DSSerializerFunctions(deserialize, serialize));
    }

    static DSSerializerFunctions register(string type, SerializerFunction serialize, DeserializerFunction deserialize) nothrow
    in
    {
        assert(type.length > 0);
        assert(serialize !is null);
        assert(deserialize !is null);
    }
    do
    {
        return register(type, DSSerializerFunctions(deserialize, serialize));
    }

    static DSSerializerFunctions register(string type, DSSerializerFunctions serializers) nothrow @trusted // access __gshared customDSeserializedFunctions
    in
    {
        assert(type.length > 0);
        assert(serializers.serialize !is null);
        assert(serializers.deserialize !is null);
    }
    do
    {
        if (customDSSerializedFunctions.length == 0)
            customDSSerializedFunctions = Dictionary!(string, DSSerializerFunctions)(200, 100, DictionaryHashMix.none);

        DSSerializerFunctions result;
        if (auto f = type in customDSSerializedFunctions)
            result = *f;
        customDSSerializedFunctions[type] = serializers;

        debug(pham_ser_ser_serialization) if (customDSSerializedFunctions.maxCollision) debug writeln(__FUNCTION__, "(customDSSerializedFunctions.maxCollision=", customDSSerializedFunctions.maxCollision,
            ", customDSSerializedFunctions.collisionCount=", customDSSerializedFunctions.collisionCount, ", customDSSerializedFunctions.capacity=", customDSSerializedFunctions.capacity, ", customDSSerializedFunctions.length=", customDSSerializedFunctions.length, ")");

        return result;
    }

    pragma(inline, true)
    final bool sameName(scope const(char)[] lhs, scope const(char)[] rhs) const @nogc nothrow
    {
        return this.options.caseSensitiveName ? (lhs == rhs) : (sicmp(lhs, rhs) == 0);
    }

    pragma(inline, true)
    final bool sameName(scope ref Serializable lhs, scope const(char)[] rhs) const @nogc nothrow
    {
        return lhs.sameName(rhs, this.options.caseSensitiveName);
    }

    pragma(inline, true)
    @property final size_t arrayDepth() const @nogc nothrow
    {
        return _arrayDepth;
    }

    @property abstract SerializerDataFormat dataFormat() const @nogc nothrow pure;

    pragma(inline, true)
    @property final size_t memberDepth() const @nogc nothrow
    {
        return _memberDepth;
    }

public:
    SerializerOptions options;

    enum RootKind : ubyte
    {
        any,
        aggregate,
        array,
    }
    RootKind rootKind;

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

        final switch (binaryFormat.encodedFormat)
        {
            case EncodedFormat.base64:
                auto buffer64 = Appender!(ubyte[])(parseBase64Length(v.length));
                if (parseBase64(buffer64, v) == NumericParsedKind.ok)
                    return buffer64[];
                static if (is(ExceptionClass == void))
                    return null;
                else
                    throw new ExceptionClass("Unable to convert base64 string to binary: " ~ sampleV());
            case EncodedFormat.base16:
                auto buffer16 = Appender!(ubyte[])(parseBase16Length(v.length));
                if (parseBase16(buffer16, v) == NumericParsedKind.ok)
                    return buffer16[];
                static if (is(ExceptionClass == void))
                    return null;
                else
                    throw new ExceptionClass("Unable to convert hex string to binary: " ~ sampleV());
        }
    }

    static ref Writer binaryToString(Writer)(return ref Writer sink, scope const(ubyte)[] v, const(BinaryFormat) binaryFormat)
    {
        import std.ascii : LetterCase;
        import pham.utl.utl_numeric_parser : cvtBytesBase64, cvtBytesBase64Length, cvtBytesBase16, cvtBytesBase16Length;

        if (v.length == 0)
            return sink;

        final switch (binaryFormat.encodedFormat)
        {
            case EncodedFormat.base64:
                return cvtBytesBase64(sink, v);
            case EncodedFormat.base16:
                return binaryFormat.characterCase == CharacterCase.lower
                    ? cvtBytesBase16(sink, v, LetterCase.lower)
                    : binaryFormat.characterCase == CharacterCase.upper
                        ? cvtBytesBase16(sink, v, LetterCase.upper)
                        : cvtBytesBase16(sink, v);
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

protected:
    size_t _arrayDepth;
    size_t _memberDepth;
    static __gshared Dictionary!(string, DSSerializerFunctions) customDSSerializedFunctions;
}

class Deserializer : DSSerializer
{
@safe:

public:
    // Aggregate (class, struct)
    final V deserialize(V)()
    if (isSerializerAggregateType!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable(V.stringof);
        return deserializeWith!V(attribute);
    }

    final V deserializeWith(V)(Serializable attribute)
    if (isSerializerAggregateType!V)
    {
        rootKind = RootKind.aggregate;
        scope (exit)
            rootKind = RootKind.any;

        V v;
        begin(attribute);
        deserialize(v, attribute);
        end(attribute);
        return v;
    }

    // Array
    final V deserialize(V)()
    if (isDynamicArray!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable((ElementType!V).stringof);
        return deserializeWith!V(attribute);
    }

    final V deserializeWith(V)(Serializable attribute)
    if (isDynamicArray!V)
    {
        rootKind = RootKind.array;
        scope (exit)
            rootKind = RootKind.any;

        V v;
        begin(attribute);
        deserialize(v, attribute);
        end(attribute);
        return v;
    }

public:
    Deserializer begin(scope ref Serializable attribute)
    {
        _arrayDepth = _memberDepth = 0;
        return this;
    }

    Deserializer end(scope ref Serializable attribute)
    {
        return this;
    }

    /*
     * Returns number of members/fields of an aggregate type.
     * If unknown, returns unknownLength
     */
    ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(typeName=", typeName, ", memberDepth=", memberDepth, ")");

        incMemberDepth();
        return unknownLength;
    }

    void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decMemberDepth();
    }

    /*
     * Returns number of elements in an array.
     * If unknown, returns unknownLength
     */
    ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(elemTypeName=", elemTypeName, ", arrayDepth=", arrayDepth, ")");

        incArrayDepth();
        return unknownLength;
    }

    void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decArrayDepth();
    }

    abstract bool hasAggregateEle(size_t i, ptrdiff_t len);
    abstract bool hasArrayEle(size_t i, ptrdiff_t len);

    abstract Null readNull(scope ref Serializable attribute);
    abstract bool readBool(scope ref Serializable attribute);
    abstract char readChar(scope ref Serializable attribute);
    abstract Date readDate(scope ref Serializable attribute);
    abstract DateTime readDateTime(scope ref Serializable attribute);
    abstract Time readTime(scope ref Serializable attribute);
    abstract byte readByte(scope ref Serializable attribute);
    abstract short readShort(scope ref Serializable attribute);
    abstract int readInt(scope ref Serializable attribute, const(DataKind) kind = DataKind.integral);
    abstract long readLong(scope ref Serializable attribute, const(DataKind) kind = DataKind.integral);
    abstract float readFloat(scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal);
    abstract double readDouble(scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal);
    abstract string readChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character);
    abstract wstring readWChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character);
    abstract dstring readDChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character);
    abstract const(char)[] readScopeChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character);
    abstract ubyte[] readBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary);
    abstract const(ubyte)[] readScopeBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary);
    abstract string readKey(size_t i);

public:
    // null
    pragma(inline, true)
    final void deserialize(V : Null)(V, scope ref Serializable attribute)
    {
        readNull(attribute);
    }

    // Boolean
    pragma(inline, true)
    final void deserialize(V : bool)(ref V v, scope ref Serializable attribute)
    if (is(V == bool) && !is(V == enum))
    {
        v = readBool(attribute);
    }

    // Char
    pragma(inline, true)
    final void deserialize(V : char)(ref V v, scope ref Serializable attribute)
    if (is(V == char) && !is(V == enum))
    {
        v = readChar(attribute);
    }

    // Date
    pragma(inline, true)
    final void deserialize(ref Date v, scope ref Serializable attribute)
    {
        v = readDate(attribute);
    }

    // DateTime
    pragma(inline, true)
    final void deserialize(ref DateTime v, scope ref Serializable attribute)
    {
        v = readDateTime(attribute);
    }

    // Time
    pragma(inline, true)
    final void deserialize(ref Time v, scope ref Serializable attribute)
    {
        v = readTime(attribute);
    }

    // Integral
    pragma(inline, true)
    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (isIntegral!V && !is(V == enum))
    {
        static if (V.sizeof == 4)
            v = readInt(attribute);
        else static if (V.sizeof == 8)
            v = readLong(attribute);
        else static if (V.sizeof == 2)
            v = readShort(attribute);
        else static if (V.sizeof == 1)
            v = readByte(attribute);
        else
            static assert(0, "Unsupported integral size: " ~ V.sizeof.stringof);
    }

    // Float
    pragma(inline, true)
    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (isFloatingPoint!V)
    {
        static if (V.sizeof == 4)
            v = readFloat(attribute);
        else //static if (V.sizeof == 8)
        {
            static assert (V.sizeof == 8);
            v = readDouble(attribute);
        }
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
                    v = cast(V)readInt(attribute, DataKind.enumerate);
                else
                    v = cast(V)readLong(attribute, DataKind.enumerate);
                return;
            }
        }

        const s = readChars(attribute, DataKind.enumerate);
        v = s.to!V();
    }

    // Chars/String
    pragma(inline, true)
    final void deserialize(ref char[] v, scope ref Serializable attribute)
    {
        v = readChars(attribute).dup;
    }

    // String
    pragma(inline, true)
    final void deserialize(ref string v, scope ref Serializable attribute)
    {
        v = readChars(attribute);
    }

    // WChars/WString
    pragma(inline, true)
    final void deserialize(ref wchar[] v, scope ref Serializable attribute)
    {
        v = readWChars(attribute).dup;
    }

    // WString
    pragma(inline, true)
    final void deserialize(ref wstring v, scope ref Serializable attribute)
    {
        v = readWChars(attribute);
    }

    // DChars/DString
    pragma(inline, true)
    final void deserialize(ref dchar[] v, scope ref Serializable attribute)
    {
        v = readDChars(attribute).dup;
    }

    // WString
    pragma(inline, true)
    final void deserialize(ref dstring v, scope ref Serializable attribute)
    {
        v = readDChars(attribute);
    }

    // Bytes/Binary
    pragma(inline, true)
    final void deserialize(ref ubyte[] v, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "()");

        v = readBytes(attribute);
    }

    // Array
    final void deserialize(V)(ref V[] v, scope ref Serializable attribute)
    if (!isSomeChar!V && !is(V == ubyte) && !is(V == byte))
    {
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(V=", fullyQualifiedName!V, ")");

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
            if (v.length == length)
                v.length = length + 1;
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
            const keyStr = readKey(length);
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
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(V=", fullyQualifiedName!V, ")");

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
            const keyStr = readKey(length);
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
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(V=", fullyQualifiedName!V, ")");

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
            const keyStr = readKey(length);
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
    final void deserialize(V)(ref V v, scope ref Serializable attribute)
    if (isSerializerAggregateType!V)
    {
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(V=", fullyQualifiedName!V, ")");
        //pragma(msg, "\ndeserialize()", fullyQualifiedName!V);

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
            static if (hasCallableWithParameterTypes!(V, "dsDeserializeEnd", Deserializer, ptrdiff_t, Serializable))
                v.dsDeserializeEnd(this, deserializedLength, attribute);
        }

        static if (hasCallableWithParameterTypes!(V, "dsDeserialize", Deserializer, SerializableMemberOptions, ptrdiff_t, Serializable))
        {
            static if (hasCallableWithParameterTypes!(V, "dsDeserializeBegin", Deserializer, ptrdiff_t, Serializable))
                v.dsDeserializeBegin(this, readLength, attribute);

            deserializedLength = v.dsDeserialize(this, memberOptions, readLength, attribute);
        }
        else
        {
            enum MemberMatched : ubyte
            {
                none,
                deserialize,
                ok,
            }

            alias members = SerializerMemberList!V;
            size_t i;
            while (hasAggregateEle(i, readLength))
            {
                MemberMatched memberMatched = MemberMatched.none;
                const key = readKey(i);
                //import std.stdio : writeln; debug writeln("i=", i, ", key=", key);

                static foreach (member; members)
                {
                    if (member.attribute.sameName(key, this.options.caseSensitiveName))
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
                                static if (hasCallableWithParameterTypes!(V, "dsDeserializeBegin", Deserializer, ptrdiff_t, Serializable))
                                    v.dsDeserializeBegin(this, readLength, attribute);
                            }

                            Serializable memberAttribute = member.attribute;
                            static if (member.flags.isGetSet)
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
                    throw new DeserializerException(fullyQualifiedName!V ~ "." ~ key ~ " not found");
                else if (memberMatched == MemberMatched.deserialize)
                    throw new DeserializerException(fullyQualifiedName!V ~ "." ~ key ~ " not able to deserialize");

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

                const key = readKey();
                Serializable memberAttribute = member.attribute;
                static if (member.flags.isGetSet)
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

    pragma(inline, true)
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
        if (auto f = fullyQualifiedName!V in customDSSerializedFunctions)
        {
            (*f).deserialize(this, cast(UV*)&v, attribute);
            return true;
        }

        return false;
    }
}

class Serializer : DSSerializer
{
@safe:

public:
    // Aggregate (class, struct)
    final Serializer serialize(V)(auto ref V v)
    if (isSerializerAggregateType!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable(V.stringof);
        return serializeWith!V(v, attribute);
    }

    final Serializer serializeWith(V)(auto ref V v, Serializable attribute)
    if (isSerializerAggregateType!V)
    {
        rootKind = RootKind.aggregate;
        scope (exit)
            rootKind = RootKind.any;

        begin(attribute);
        serialize(v, attribute);
        return end(attribute);
    }

    // Array
    final Serializer serialize(V)(auto ref V v)
    if (isDynamicArray!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable((ElementType!V).stringof);
        return serializeWith!V(v, attribute);
    }

    final Serializer serializeWith(V)(auto ref V v, Serializable attribute)
    if (isDynamicArray!V)
    {
        rootKind = RootKind.array;
        scope (exit)
            rootKind = RootKind.any;

        begin(attribute);
        serialize(v, attribute);
        return end(attribute);
    }

public:
    Serializer begin(scope ref Serializable attribute)
    {
        _arrayDepth = _memberDepth = 0;
        return this;
    }

    Serializer end(scope ref Serializable attribute)
    {
        return this;
    }

    void aggregateBegin(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        incMemberDepth();
    }

    void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decMemberDepth();
    }

    Serializer aggregateItem(ptrdiff_t index, scope ref Serializable attribute)
    in
    {
        assert(attribute.name.length != 0);
    }
    do
    {
        return attribute.flags.symbolId ? writeKeyId(attribute) : writeKey(attribute);
    }

    void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        incArrayDepth();
    }

    void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        decArrayDepth();
    }

    Serializer arrayItem(ptrdiff_t index, scope ref Serializable attribute)
    {
        return this;
    }

    abstract void write(Null v, scope ref Serializable attribute);
    abstract void writeBool(bool v, scope ref Serializable attribute); // Different name - D is not good of distinguish between bool/byte|int
    abstract void writeChar(char v, scope ref Serializable attribute); // Different name - D is not good of distinguish between char/byte|int
    abstract void write(scope const(Date) v, scope ref Serializable attribute);
    abstract void write(scope const(DateTime) v, scope ref Serializable attribute);
    abstract void write(scope const(Time) v, scope ref Serializable attribute);
    abstract void write(byte v, scope ref Serializable attribute);
    abstract void write(short v, scope ref Serializable attribute);
    abstract void write(int v, scope ref Serializable attribute, const(DataKind) kind = DataKind.integral);
    abstract void write(long v, scope ref Serializable attribute, const(DataKind) kind = DataKind.integral);
    abstract void write(float v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal);
    abstract void write(double v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal);
    abstract void write(scope const(char)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character); // String value
    abstract void write(scope const(wchar)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character); // WString value
    abstract void write(scope const(dchar)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character); // DString value
    abstract void write(scope const(ubyte)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.binary); // Binary value
    abstract Serializer writeKey(scope ref Serializable attribute);
    abstract Serializer writeKeyId(scope ref Serializable attribute);

public:
    // null
    pragma(inline, true)
    final void serialize(Null, scope ref Serializable attribute)
    {
        write(null, attribute);
    }

    // Boolean
    pragma(inline, true)
    final void serialize(V : bool)(const(V) v, scope ref Serializable attribute)
    if (is(V == bool) && !is(V == enum))
    {
        writeBool(v, attribute);
    }

    // Char
    pragma(inline, true)
    final void serialize(V : char)(const(V) v, scope ref Serializable attribute)
    if (is(V == char) && !is(V == enum))
    {
        writeChar(v, attribute);
    }

    // Date
    pragma(inline, true)
    final void serialize(scope const(Date) v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // DateTime
    pragma(inline, true)
    final void serialize(scope const(DateTime) v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // Time
    pragma(inline, true)
    final void serialize(scope const(Time) v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // Integral
    pragma(inline, true)
    final void serialize(V)(const(V) v, scope ref Serializable attribute)
    if (isIntegral!V && !is(V == enum))
    {
        write(v, attribute);
    }

    // Float
    pragma(inline, true)
    final void serialize(V)(const(V) v, scope ref Serializable attribute)
    if (isFloatingPoint!V)
    {
        return write(v, attribute);
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
                    write(cast(int)v, attribute, DataKind.enumerate);
                else
                    write(cast(long)v, attribute, DataKind.enumerate);
                return;
            }
        }

        const vStr = v.to!string();
        write(vStr, attribute, DataKind.enumerate);
    }

    // Chars/String
    pragma(inline, true)
    final void serialize(scope const(char)[] v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // String
    pragma(inline, true)
    final void serialize(string v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // WChars/WString
    pragma(inline, true)
    final void serialize(scope const(wchar)[] v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // WString
    pragma(inline, true)
    final void serialize(wstring v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // DChars/DString
    pragma(inline, true)
    final void serialize(scope const(dchar)[] v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // DString
    pragma(inline, true)
    final void serialize(dstring v, scope ref Serializable attribute)
    {
        write(v, attribute);
    }

    // Bytes/Binary
    pragma(inline, true)
    final void serialize(scope const(ubyte)[] v, scope ref Serializable attribute)
    {
        write(v, attribute);
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
            arrayItem(i, attribute);
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
            arrayItem(length, attribute);
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
        memberAttribute.flags.symbolId = false;
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
        memberAttribute.flags.symbolId = true;
        foreach (key, ref val; v)
        {
            const keyStr = sformat(keyBuffer[], "%d", key);
            memberAttribute.name = keyStr.idup;
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
        memberAttribute.flags.symbolId = true;
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
    final void serialize(V)(auto ref V v, scope ref Serializable attribute) @trusted // opEqual
    if (isSerializerAggregateType!V)
    {
        debug(pham_ser_ser_serialization) debug writeln(__FUNCTION__, "(V=", V.stringof, ", name=", attribute.name, ")");

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
            static if (hasCallableWithParameterTypes!(V, "dsSerializeEnd", Serializer, size_t, Serializable))
                v.dsSerializeEnd(this, serializeredLength, attribute);
        }

        static if (hasCallableWithParameterTypes!(V, "dsSerialize", Serializer, SerializableMemberOptions, Serializable))
        {
            static if (hasCallableWithParameterTypes!(V, "dsSerializeBegin", Serializer, size_t, Serializable))
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
                    debug(pham_ser_ser_serialization) debug writeln("\t", "name=", member.attribute.name);

                    auto memberValue = __traits(child, v, member.memberGet);
                    Serializable memberAttribute = member.attribute;
                    memberAttribute.flags.symbolId = false;

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
                        static if (hasCallableWithParameterTypes!(V, "dsSerializeBegin", Serializer, size_t, Serializable))
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

    pragma(inline, true)
    final void serializeAny(V)(auto ref V v, scope ref Serializable attribute)
    {
        if (!serializeCustom!V(v, attribute))
            serialize!V(v, attribute);
    }

    // Customized types
    final bool serializeCustom(V)(auto ref V v, scope ref Serializable attribute) @trusted // parameter address & access __gshared customDSeserializedFunctions
    {
        alias UV = Unqual!V;
        if (auto f = fullyQualifiedName!V in customDSSerializedFunctions)
        {
            (*f).serialize(this, cast(UV*)&v, attribute);
            return true;
        }

        return false;
    }
}

struct StaticBuffer(T, size_t Capacity)
{
nothrow @safe:

    T[Capacity] data = 0; // 0=Make its struct to be zero initializer
    size_t length;

    T[] opSlice() @nogc return
    {
        return data[0..length];
    }

    pragma(inline, true)
    void put(T c) @nogc
    in
    {
        assert(this.length < Capacity);
    }
    do
    {
        data[length++] = c;
    }

    void put(scope const(T)[] s) @nogc
    in
    {
        assert(this.length + s.length <= Capacity);
    }
    do
    {
        const nl = this.length + s.length;
        data[this.length..nl] = s[0..$];
        this.length = nl;
    }

    ref typeof(this) reset() @nogc return
    {
        length = 0;
        return this;
    }
}

T asciiCaseInplace(T)(return scope T s, const(CharacterCase) characterCase) nothrow pure
if (isDynamicArray!T)
{
    import std.ascii : isLower, isUpper;

    final switch (characterCase)
    {
        case CharacterCase.normal:
            return s;
        case CharacterCase.upper:
            foreach (ref c; s)
            {
                if (isLower(c))
                    c = cast(char)(c - ('a' - 'A'));
            }
            return s;
        case CharacterCase.lower:
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

    @Serializable(null, null, DbEntity("UnitTestS1"))
    static struct UnitTestS1
    {
    public:
        @Serializable("publicInt", null, DbEntity("publicInt", DbKey.primary))
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
            assert(publicGetSet == 1, _publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 20, publicInt.to!string);
            assert(protectedInt == 0, protectedInt.to!string);
            assert(privateInt == 0, privateInt.to!string);
        }

        void assertValuesArray(ptrdiff_t index)
        {
            assert(publicGetSet == 1+index, publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 20+index, publicInt.to!string);
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

    class UnitTestAllTypesLess
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
        double double1;
        string string1;
        char[] charArray;
        ubyte[] binary1;

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
            double1 = -2846627456445.765;
            string1 = "test string of";
            charArray = "will this work?".dup;
            binary1 = [37,24,204,101,43];
            return this;
        }

        void assertValues()
        {
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
            assert(double1 == -2846627456445.765, double1.to!string);
            assert(string1 == "test string of", string1);
            assert(charArray == "will this work?", charArray);
            assert(binary1 == [37,24,204,101,43], binary1.to!string);
        }

        void assertValuesArray(ptrdiff_t index)
        {
            assert(enum1 == UnitTestEnum.third, enum1.to!string);
            assert(bool1 == true, bool1.to!string);
            assert(byte1 == 101+index, (byte1+index).to!string);
            assert(short1 == -1003+index, (short1+index).to!string);
            assert(ushort1 == 3975+index, (ushort1+index).to!string);
            assert(int1 == -382653+index, (int1+index).to!string);
            assert(uint1 == 3957209+index, (uint1+index).to!string);
            assert(long1 == -394572364+index, (long1+index).to!string);
            assert(ulong1 == 284659274+index, (ulong1+index).to!string);
            assert(float1 == 6394763.5+index, (float1+index).to!string);
            assert(double1 == -2846627456445.765+index, (double1+index).to!string);
            assert(string1 == "test string of", string1);
            assert(charArray == "will this work?", charArray);
            assert(binary1 == [37,24,204,101,43], binary1.to!string);
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
                const key = deserializer.readKey(i);
                if (deserializer.sameName(setMemberAttribute("s1"), key))
                    deserializer.deserialize(s1, memberAttribute);
                else if (deserializer.sameName(setMemberAttribute("ds"), key))
                    deserializer.deserialize(ds, memberAttribute);
                else if (deserializer.sameName(setMemberAttribute("ws"), key))
                    deserializer.deserialize(ws, memberAttribute);
                else if (deserializer.sameName(setMemberAttribute("c1"), key))
                    deserializer.deserialize(c1, memberAttribute);
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


// Any below codes are private
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

shared static this() nothrow @trusted
{
    floatLiterals = () nothrow
    {
        auto result = Dictionary!(string, IsFloatLiteral)(20, 15, DictionaryHashMix.murmurHash3);

        // Standard texts
        result["NaN"] = IsFloatLiteral.nan;
        result["Infinity"] = IsFloatLiteral.pinf;
        result["-Infinity"] = IsFloatLiteral.ninf;

        // Other support texts
        result["nan"] = IsFloatLiteral.nan;
        result["NAN"] = IsFloatLiteral.nan;
        result["inf"] = IsFloatLiteral.pinf;
        result["+inf"] = IsFloatLiteral.pinf;
        result["-inf"] = IsFloatLiteral.ninf;
        result["infinity"] = IsFloatLiteral.pinf;
        result["+infinity"] = IsFloatLiteral.pinf;
        result["-infinity"] = IsFloatLiteral.ninf;
        result["Infinite"] = IsFloatLiteral.pinf; // dlang.std.json
        result["-Infinite"] = IsFloatLiteral.ninf; // dlang.std.json

        debug(pham_ser_ser_serialization) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return result;
    }();
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
    assert(asciiCaseInplace(buffer, CharacterCase.normal) == "1abCDefG2");
    assert(asciiCaseInplace(buffer, CharacterCase.upper) == "1ABCDEFG2");
    buffer = "1abCDefG2".dup;
    assert(asciiCaseInplace(buffer, CharacterCase.lower) == "1abcdefg2");
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
    import std.algorithm.iteration : each;
    import std.conv : to;

    SerializableMemberOptions options;

    string[] deserializerNames;
    const deserializerMembers = getDeserializerMembers!(UnitTestS1, options)();
    deserializerMembers.each!(e => deserializerNames ~= e.memberName);
    assert(deserializerMembers.length == 2, deserializerMembers.length.to!string() ~ "." ~ deserializerNames.to!string());
    assert(deserializerNames == ["publicInt", "publicGetSet"], deserializerNames.to!string);

    string[] serializerNames;
    const serializerMembers = getSerializerMembers!(UnitTestS1, options)();
    serializerMembers.each!(e => serializerNames ~= e.memberName);
    assert(serializerMembers.length == 2, serializerMembers.length.to!string() ~ "." ~ serializerMembers.to!string());
    assert(serializerNames == ["publicInt", "publicGetSet"], serializerNames.to!string);
}

unittest // SerializableMemberOptions - Change options
{
    import std.algorithm.iteration : each;
    import std.conv : to;
    SerializableMemberOptions options;

    // All scopes
    options.scopes = [SerializableMemberScope.public_, SerializableMemberScope.protected_, SerializableMemberScope.private_];
    static immutable expectAllScopes = ["publicInt", "_publicGetSet", "publicStruct", "publicGetSet", "protectedInt",
        "_protectedGetSet", "protectedGetSet", "privateInt", "_privateGetSet", "privateGetSet", "publicStr"];

    string[] deserializerNames;
    const deserializerMembers = getDeserializerMembers!(UnitTestC2, options)();
    deserializerMembers.each!(e => deserializerNames ~= e.memberName);
    assert(deserializerMembers.length == 11, deserializerMembers.length.to!string() ~ "." ~ deserializerNames.to!string());
    assert(deserializerNames == expectAllScopes, deserializerNames.to!string());

    string[] serializerNames;
    const serializerMembers = getSerializerMembers!(UnitTestC2, options)();
    serializerMembers.each!(e => serializerNames ~= e.memberName);
    assert(serializerMembers.length == 11, serializerMembers.length.to!string() ~ "." ~ serializerNames.to!string());
    assert(serializerNames == expectAllScopes, serializerNames.to!string());

    // With attribute only
    options.scopes = [SerializableMemberScope.public_, SerializableMemberScope.protected_, SerializableMemberScope.private_];
    options.flags = [SerializableMemberFlag.isGetSet, SerializableMemberFlag.explicitUDA];
    static immutable expectAttributeOnly = ["publicInt", "publicGetSet"];

    deserializerNames = null;
    const deserializerMembers2 = getDeserializerMembers!(UnitTestC2, options)();
    deserializerMembers2.each!(e => deserializerNames ~= e.memberName);
    assert(deserializerMembers2.length == 2, deserializerMembers2.length.to!string() ~ "." ~ deserializerNames.to!string());
    assert(deserializerNames == expectAttributeOnly, deserializerNames.to!string());

    serializerNames = null;
    const serializerMembers2 = getSerializerMembers!(UnitTestC2, options)();
    serializerMembers2.each!(e => serializerNames ~= e.memberName);
    assert(serializerMembers2.length == 2, serializerMembers2.length.to!string() ~ "." ~ serializerNames.to!string());
    assert(serializerNames == expectAttributeOnly, serializerNames.to!string());
}

version(unittest)
{
package(pham.ser):

    static struct UnitTestPhamDateTime
    {
        Date date1;
        DateTime dateTime1;
        Time time1;

        ref typeof(this) setValues() return
        {
            date1 = Date(1999, 1, 1);
            dateTime1 = DateTime(1999, 7, 6, 12, 30, 33, DateTimeZoneKind.utc);
            time1 = Time(12, 30, 33, DateTimeZoneKind.utc);
            return this;
        }

        void assertValues()
        {
            assert(date1 == Date(1999, 1, 1));
            assert(dateTime1 == DateTime(1999, 7, 6, 12, 30, 33, DateTimeZoneKind.utc), dateTime1.toString());
            assert(time1 == Time(12, 30, 33, DateTimeZoneKind.utc), time1.toString());
        }

        void assertValuesArray(ptrdiff_t index)
        {
            assert(date1 == Date(1999, 1, 1).addDays(cast(int)index));
            assert(dateTime1 == DateTime(1999, 7, 6, 12, 30, 33).addDays(cast(int)index), dateTime1.toString());
            assert(time1 == Time(12, 30, 33).addSeconds(index), time1.toString());
        }
    }

    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestPhamDateTime);
}
