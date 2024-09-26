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
import std.traits : BaseClassesTuple, BaseTypeTuple, fullyQualifiedName, FunctionAttribute, functionAttributes,
    isCallable, isDelegate, isFunction, Parameters, ReturnType, Unqual;

@safe:

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


// Any below codes are private
private:

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
