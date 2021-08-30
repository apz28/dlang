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

module pham.utl.delegate_list;

import pham.utl.array : UnshrinkArray;

struct DelegateList(Args...)
{
public:
    alias DelegateHandler = void delegate(Args args);

public:
    void opOpAssign(string op)(DelegateHandler handler) nothrow pure @safe
    if (op == "~" || op == "+" || op == "-")
    {
        static if (op == "~" || op == "+")
            items.putBack(handler);
        else static if (op == "-")
            items.remove(handler);
        else
            static assert(0);
    }

    void opCall(Args args)
    {
        if (items.length != 0)
        {
            // Always make a copy to avoid skip/misbehavior if handler removes
            // any from the list that means the lifetime of the caller instance
            // must be out lived while notifying
            auto foreachItems = items.dup();
            foreach (i; foreachItems)
                i(args);
        }
    }

    bool opCast(C: bool)() const nothrow pure @safe
    {
        return length != 0;
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
    ref typeof(this) putBack(DelegateHandler handler) nothrow pure return @safe
    {
        if (handler !is null)
            items.putBack(handler);
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

    @property size_t length() const nothrow pure @safe
    {
        return items.length;
    }

private:
    UnshrinkArray!DelegateHandler items;
}


// Any below codes are private
private:

unittest // DelegateList
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.delegate_list.DelegateList");

    string eName;
    int eValue;

    static struct S1
    {
        int a;
        void accumulate(string name, int value)// nothrow
        {
            a += value;
        }
    }

    DelegateList!(string, int) list;
    assert(!list);

    auto s1 = S1(100);
    list += &s1.accumulate;
    assert(list && list.length == 1);

    list += (string name, int value) { eName = name; eValue = value; };
    assert(list && list.length == 2);

    list("1", 1);
    assert(eName == "1" && eValue == 1);
    assert(s1.a == 101);

    list -= &s1.accumulate;
    assert(list && list.length == 1);
    list("2", 2);
    assert(eName == "2" && eValue == 2);
    assert(s1.a == 101);
}
