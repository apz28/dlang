/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_delegate_list;

import std.traits : ReturnType, isDelegate;

mixin template ApplyAutoRef(T, alias items)
{
static if (T.sizeof > size_t.sizeof)
{
    alias opApply = opApplyImpl!(int delegate(ref T value));
    alias opApply = opApplyImpl!(int delegate(size_t index, ref T value));

    final int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(ref T)) || is(CallBack : int delegate(size_t, ref T)))
    {
        static if (is(CallBack : int delegate(size_t, ref T)))
        {
            foreach (i, ref e; items)
            {
                if (const r = callBack(i, e))
                    return r;
            }
        }
        else
        {
            foreach (ref e; items)
            {
                if (const r = callBack(e))
                    return r;
            }
        }

        return 0;
    }
}
else
{
    alias opApply = opApplyImpl!(int delegate(T value));
    alias opApply = opApplyImpl!(int delegate(size_t index, T value));

    final int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(T)) || is(CallBack : int delegate(size_t, T)))
    {
        static if (is(CallBack : int delegate(size_t, T)))
        {
            foreach (i, e; items)
            {
                if (const r = callBack(i, e))
                    return r;
            }
        }
        else
        {
            foreach (e; items)
            {
                if (const r = callBack(e))
                    return r;
            }
        }

        return 0;
    }
}
}

mixin template ApplyReference(T, alias items)
{
    alias opApply = opApplyImpl!(int delegate(ref T value));
    alias opApply = opApplyImpl!(int delegate(size_t index, ref T value));

    final int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(ref T)) || is(CallBack : int delegate(size_t, ref T)))
    {
        static if (is(CallBack : int delegate(size_t, ref T)))
        {
            foreach (i, ref e; items)
            {
                if (const r = callBack(i, e))
                    return r;
            }
        }
        else
        {
            foreach (ref e; items)
            {
                if (const r = callBack(e))
                    return r;
            }
        }

        return 0;
    }
}

mixin template ApplyValue(T, alias items)
{
    alias opApply = opApplyImpl!(int delegate(T value));
    alias opApply = opApplyImpl!(int delegate(size_t index, T value));

    final int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(T)) || is(CallBack : int delegate(size_t, T)))
    {
        static if (is(CallBack : int delegate(size_t, T)))
        {
            foreach (i, e; items)
            {
                if (const r = callBack(i, e))
                    return r;
            }
        }
        else
        {
            foreach (e; items)
            {
                if (const r = callBack(e))
                    return r;
            }
        }

        return 0;
    }
}

template DelegateList(Args...)
{
    private alias DelegateHandler = void delegate(Args args);
    //pragma(msg, DelegateHandler.stringof);

    alias DelegateList = DelegateListOf!(DelegateHandler, Args);
}

template DelegateList(DelegateHandler, Args...)
if (isDelegate!DelegateHandler)
{
    //pragma(msg, DelegateHandler.stringof);

    alias DelegateList = DelegateListOf!(DelegateHandler, Args);
}

struct DelegateListOf(DelegateHandler, Args...)
if (isDelegate!DelegateHandler)
{
    import pham.utl.utl_array_static : StaticArray;

public:
    alias Return = ReturnType!DelegateHandler;
    //pragma(msg, Return.stringof);

public:
    @disable this(this);

    ref typeof(this) opAssign(ref typeof(this) rhs) nothrow return @safe
    {
        items.opAssign(rhs.items);
        return this;
    }

    void opOpAssign(string op)(DelegateHandler handler) nothrow pure @safe
    if (op == "~" || op == "+" || op == "-")
    {
        if (handler is null)
            return;

        static if (op == "~" || op == "+")
            items.put(handler);
        else static if (op == "-")
            items.remove(handler);
        else
            static assert(0);
    }

    Return opCall()(Args args)
    {
        switch (items.length)
        {
            // Special call to avoid duplicate delegate array (@NoGC)
            case 1:
                return items[0](args);

            // Special call to avoid duplicate delegate array (@NoGC)
            case 2:
                DelegateHandler[2] h2 = items[0..2];
                return call(h2[], args);

            // Special call to avoid duplicate delegate array (@NoGC)
            case 3:
                DelegateHandler[3] h3 = items[0..3];
                return call(h3[], args);

            // Special call to avoid duplicate delegate array (@NoGC)
            case 4:
                DelegateHandler[4] h4 = items[0..4];
                return call(h4[], args);

            default:
                // Always make a copy to avoid skip/misbehavior if handler removes
                // any from the list that means the lifetime of the caller instance
                // must be out lived while notifying
                return call(items[].dup, args);

            case 0:
                static if (is(Return == void))
                    return;
                else
                    return Return.init;
        }
    }

    bool opCast(C: bool)() const @nogc nothrow pure @safe
    {
        return items.length != 0;
    }

    /**
     * Removes all handlers from this instant
     */
    ref typeof(this) clear() nothrow return pure @safe
    {
        items.clear();
        return this;
    }

    /**
     * Appends element, handler, into end of this instant
     * Params:
     *  handler = element to be appended
     */
    ref typeof(this) put(DelegateHandler handler) nothrow pure return @safe
    {
        if (handler !is null)
            items.put(handler);
        return this;
    }

    /**
     * Removes matched element, handler, from this instant
     * Params:
     *  handler = element to be removed
     */
    ref typeof(this) remove(DelegateHandler handler) nothrow pure return @safe
    {
        if (handler !is null)
            items.remove(handler);
        return this;
    }

    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure @safe
    {
        return items.length;
    }

private:
    Return call()(scope DelegateHandler[] handlers, Args args)
    {
        static if (is(Return == void))
        {
            foreach (handler; handlers)
                handler(args);
        }
        else
        {
            Return result;
            foreach (handler; handlers)
                result = handler(args);
            return result;
        }
    }

private:
    StaticArray!(DelegateHandler, 4) items;
}


// Any below codes are private
private:

unittest // DelegateList
{
    static struct S1
    {
        int a;
        void accumulate(string name, int value) @safe
        {
            a += value;
        }
    }

    DelegateList!(string, int) list;
    assert(!list);
    assert(list.length == 0);

    auto s1 = S1(100);
    list += &s1.accumulate;
    assert(list);
    assert(list.length == 1);

    string eName;
    int eValue;
    list += (string name, int value) { eName = name; eValue = value; };
    assert(list);
    assert(list.length == 2);

    list("1", 1);
    assert(eName == "1" && eValue == 1);
    assert(s1.a == 101);

    list -= &s1.accumulate;
    assert(list);
    assert(list.length == 1);
    list("2", 2);
    assert(eName == "2" && eValue == 2);
    assert(s1.a == 101);
}

unittest // ApplyAutoRef
{
    static struct X
    {
        size_t[3] values = [1, 2, 3];

        ptrdiff_t v()
        {
            return values[0] + values[1] + values[2];
        }

        void v(int e)
        {
            values[0] += e;
            values[1] += e;
            values[2] += e;
        }
    }

    static struct FooX
    {
        mixin ApplyAutoRef!(X, values);

        X[3] values;
    }

    static struct FooSize_T
    {
        mixin ApplyAutoRef!(size_t, values);

        size_t[3] values = [1, 2, 3];
    }

    {
        int j = 0;
        int sum = 0;
        FooSize_T foo;
        foreach (e; foo)
        {
            sum += e;
            j++;
        }
        assert(sum == 6);

        j = 0;
        sum = 0;
        foreach (i, e; foo)
        {
            assert(j == i);
            sum += e;
            j++;
        }
        assert(sum == 6);
        assert(j == foo.values.length);
    }

    {
        int j = 0;
        int sum = 0;
        FooX foo;
        foreach (ref e; foo)
        {
            sum += e.v;
            e.v(1);
            assert(foo.values[j].values == [2, 3, 4]);
            j++;
        }
        assert(sum == 6*3);

        j = 0;
        sum = 0;
        foreach (i, ref e; foo)
        {
            assert(j == i);
            sum += e.v;
            e.v(1);
            assert(foo.values[j].values == [3, 4, 5]);
            j++;
        }
        assert(sum == 9*3);
        assert(j == foo.values.length);
    }
}

unittest // ApplyValue
{
    static struct Foo
    {
        mixin ApplyValue!(int, values);

        int[3] values = [1, 2, 3];
    }

    int j = 0;
    int sum = 0;
    Foo foo;
    foreach (e; foo)
    {
        sum += e;
        j++;
    }
    assert(sum == 6);

    j = 0;
    sum = 0;
    foreach (i, e; foo)
    {
        assert(j == i);
        sum += e;
        j++;
    }
    assert(sum == 6);
    assert(j == foo.values.length);
}

unittest // ApplyReference
{
    static struct Foo
    {
        mixin ApplyReference!(int, values);

        int[3] values = [1, 2, 3];
    }

    int j = 0;
    int sum = 0;
    Foo foo;
    foreach (ref e; foo)
    {
        sum += e;
        e += 1;
        j++;
    }
    assert(sum == 6);
    assert(foo.values == [2, 3, 4]);

    j = 0;
    sum = 0;
    foreach (i, ref e; foo)
    {
        assert(j == i);
        sum += e;
        e += 1;
        j++;
    }
    assert(sum == 9);
    assert(j == foo.values.length);
    assert(foo.values == [3, 4, 5]);
}
