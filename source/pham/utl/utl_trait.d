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

module pham.utl.utl_trait;

import std.meta : Filter;
import std.traits : BaseClassesTuple, BaseTypeTuple, Parameters, ReturnType, Unqual,
    fullyQualifiedName, FunctionAttribute, functionAttributes,
    isCallable, isDelegate, isFunction, isIntegral;

@safe:

template ElementTypeOf(R)
{
    import std.range.primitives : ElementType;

    static if (is(R == string) || is(R == const(char)[]) || is(R == char[]))
        alias ElementTypeOf = char;
    else static if (is(R == wstring) || is(R == const(wchar)[]) || is(R == wchar[]))
        alias ElementTypeOf = wchar;
    else static if (is(R == dstring) || is(R == const(dchar)[]) || is(R == dchar[]))
        alias ElementTypeOf = dchar;
    else
        alias ElementTypeOf = Unqual!(ElementType!R);
}

template UnsignedTypeOf(T)
if (isIntegral!T)
{
    static if (T.sizeof == 4)
        alias UnsignedTypeOf = uint;
    else static if (T.sizeof == 8)
        alias UnsignedTypeOf = ulong;
    else static if (T.sizeof == 2)
        alias UnsignedTypeOf = ushort;
    else static if (T.sizeof == 1)
        alias UnsignedTypeOf = ubyte;
    else
        static assert(0, "Unsupported integeral type " ~ T.stringof);
}

template getParamType(alias functionSymbol, size_t i)
{
    alias getParamType = Parameters!functionSymbol[i];
}

template getReturnType(alias getFunctionSymbol)
{
    static if (isPropertyFunction!getFunctionSymbol)
        alias getReturnType = typeof(getFunctionSymbol);
    else
        alias getReturnType = ReturnType!(typeof(getFunctionSymbol));
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

template getUDAs(alias symbol, alias attribute)
{
    static if (__traits(compiles, __traits(getAttributes, symbol)))
        alias getUDAs = Filter!(isDesiredUDA!attribute, __traits(getAttributes, symbol));
    else
        alias getUDAs = AliasSeq!();
}

template hasCallableWithParameterTypes(T, string memberName, Args...)
if (is(T == struct) || is(T == class))
{
    static if (__traits(hasMember, T, memberName))
        enum bool hasCallableWithParameterTypes = isCallableWithParameterTypes!(__traits(getMember, T, memberName), Args);
    else
        enum bool hasCallableWithParameterTypes = false;
}

enum HasPostblit : ubyte
{
    none, // Must be first to be 0 for if (...) usage
    postBlit,
    xpostBlit,
}

template hasPostblit(T)
{
    static if (__traits(hasMember, T, "__postblit") && !__traits(isDisabled, T.__postblit))
        enum hasPostblit = HasPostblit.postBlit;
    else static if (__traits(hasMember, T, "__xpostblit") && !__traits(isDisabled, T.__xpostblit))
        enum hasPostblit = HasPostblit.xpostBlit;
    else
        enum hasPostblit = HasPostblit.none;
}

template hasUDA(alias symbol, alias attribute)
{
    enum bool hasUDA = getUDAs!(symbol, attribute).length != 0;
}

template isCallableWithParameterTypes(alias functionSymbol, Args...)
{
    private alias funcParams = Parameters!functionSymbol;

    private bool sameParameterTypes()
    {
        bool result = true;
        static foreach (i; 0..funcParams.length)
        {
            static if (!is(Args[i] : funcParams[i]))
                result = false;
        }
        return result;
    }

    static if (isCallable!functionSymbol && funcParams.length == Args.length)
        enum bool isCallableWithParameterTypes = sameParameterTypes();
    else
        enum bool isCallableWithParameterTypes = false;
}

template isDelegateWith(alias functionSymbol, ReturnT, Args...)
{
    static if (isDelegate!functionSymbol && is(ReturnType!functionSymbol : ReturnT))
        enum bool isDelegateWith = isCallableWithParameterTypes!(functionSymbol, Args);
    else
        enum bool isDelegateWith = false;
}

template isDelegateWithParameterTypes(alias functionSymbol, Args...)
{
    static if (isDelegate!functionSymbol)
        enum bool isDelegateWithParameterTypes = isCallableWithParameterTypes!(functionSymbol, Args);
    else
        enum bool isDelegateWithParameterTypes = false;
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

template isTypeOf(T, checkingT)
{
    enum bool isTypeOf = is(T == checkingT) || is(Unqual!T == checkingT);
}

/**
 * Gives the `alignof` the largest types given.
 * Default to size_t.alignof if no types given.
 */
template maxAlignment(Ts...)
{
    enum maxAlignment =
    {
        size_t result = 0;
        static foreach (t; Ts)
        {
            if (t.alignof > result)
                result = t.alignof;
        }
        return result != 0 ? result : size_t.alignof;
    }();
}

/**
 * Gives the `sizeof` the largest types given.
 */
template maxSize(Ts...)
{
    enum maxSize =
    {
        size_t result = 0;
        static foreach (t; Ts)
        {
            if (t.sizeof > result)
                result = t.sizeof;
        }
        return result != 0 ? result : size_t.sizeof;
    }();
}


// Any below codes are private
private:

unittest // ElementTypeOf
{
    static assert(is(ElementTypeOf!string == char));
    static assert(is(ElementTypeOf!(char[]) == char));

    static assert(is(ElementTypeOf!wstring == wchar));
    static assert(is(ElementTypeOf!(wchar[]) == wchar));

    static assert(is(ElementTypeOf!dstring == dchar));
    static assert(is(ElementTypeOf!(dchar[]) == dchar));
}

unittest // UnsignedTypeOf
{
    static assert(is(UnsignedTypeOf!long == ulong));
    static assert(is(UnsignedTypeOf!ulong == ulong));

    static assert(is(UnsignedTypeOf!int == uint));
    static assert(is(UnsignedTypeOf!uint == uint));

    static assert(is(UnsignedTypeOf!short == ushort));
    static assert(is(UnsignedTypeOf!ushort == ushort));

    static assert(is(UnsignedTypeOf!byte == ubyte));
    static assert(is(UnsignedTypeOf!ubyte == ubyte));
}

unittest // isTypeOf
{
    static struct S {}
    static class C {}

    static assert(isTypeOf!(int, int));
    static assert(isTypeOf!(const(int), int));
    static assert(isTypeOf!(immutable(int), int));
    static assert(isTypeOf!(shared int, int));

    static assert(isTypeOf!(S, S));
    static assert(isTypeOf!(const(S), S));
    static assert(isTypeOf!(immutable(S), S));
    static assert(isTypeOf!(shared S, S));

    static assert(isTypeOf!(C, C));
    static assert(isTypeOf!(const(C), C));
    static assert(isTypeOf!(immutable(C), C));
    static assert(isTypeOf!(shared C, C));

    static assert(isTypeOf!(string, string));
    static assert(isTypeOf!(const(string), string));
    static assert(isTypeOf!(immutable(string), string));
    static assert(isTypeOf!(shared string, string));
}

unittest // isCallableWithParameterTypes
{
    static struct Serializable
    {}

    static struct SerializableMemberOptions
    {}

    static struct Deserializer
    {}

    static struct Serializer
    {}

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

    static assert (isCallableWithParameterTypes!(deserialize, Deserializer, SerializableMemberOptions, size_t, Serializable));
    static assert (isCallableWithParameterTypes!(serialize, Serializer, SerializableMemberOptions, Serializable));

    alias deserializeMember = __traits(getMember, S, "deserialize");
    static assert (isCallableWithParameterTypes!(deserializeMember, Deserializer, SerializableMemberOptions, size_t, Serializable));
    alias serializeMember = __traits(getMember, S, "serialize");
    static assert (isCallableWithParameterTypes!(serializeMember, Serializer, SerializableMemberOptions, Serializable));
}

unittest // hasPostblit
{
    static struct N {}
    static struct P { this(this) {} }
    static struct XP { P p; }
    static struct D { @disable this(this); }
    static struct XD { D d; }
    
    static assert(!hasPostblit!N);
    static assert(hasPostblit!N == HasPostblit.none);
    static assert(hasPostblit!P);
    static assert(hasPostblit!P == HasPostblit.postBlit);
    static assert(hasPostblit!XP);
    static assert(hasPostblit!XP == HasPostblit.xpostBlit);

    static assert(!hasPostblit!D);
    static assert(hasPostblit!D == HasPostblit.none);
    static assert(!hasPostblit!XD);
    static assert(hasPostblit!XD == HasPostblit.none);
}

nothrow @safe unittest // maxAlignment
{
    static assert(maxAlignment!(int, long) == long.alignof);
    static assert(maxAlignment!(bool, byte) == 1);

    struct S { int a, b, c; }
    static assert(maxAlignment!(bool, long, S) == long.alignof);
}

nothrow @safe unittest // maxSize
{
    static assert(maxSize!(int, long) == long.sizeof);
    static assert(maxSize!(bool, byte) == 1);

    struct S { int a, b, c; }
    static assert(maxSize!(bool, long, S) == S.sizeof);
}
