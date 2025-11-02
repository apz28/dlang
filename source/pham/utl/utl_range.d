/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_range;

template ElementType(R)
{
    static if (is(typeof(R.init.front.init) T))
        alias ElementType = T;
    else
        alias ElementType = void;
}

template UElementType(R)
{
    import std.traits : Unqual;

    static if (is(typeof(R.init.front.init) T))
        alias UElementType = Unqual!T;
    else
        alias UElementType = void;
}

@property bool empty(T)(auto ref scope T a) @nogc nothrow pure @safe
if (is(typeof(a.length) : size_t))
{
    return a.length == 0;
}

@property ref inout(T) front(T)(return scope inout(T)[] a) @nogc nothrow pure @safe
if (!is(T[] == void[]))
in
{
    assert(a.length, "Attempting to fetch the front of an empty array of " ~ T.stringof);
}
do
{
    return a[0];
}

void popFront(T)(scope ref inout(T)[] a) @nogc nothrow pure @safe
if (!is(T[] == void[]))
in
{
    assert(a.length, "Attempting to popFront() past the end of an array of " ~ T.stringof);
}
do
{
    a = a[1..$];
}

unittest // ElementType
{
    import std.meta : AliasSeq;

    static foreach (T; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, char, wchar, dchar))
    {
        static assert(is(ElementType!(T[]) == T));
        static assert(is(ElementType!(const(T)[]) == const(T)));
        static assert(is(ElementType!(immutable(T)[]) == immutable(T)));

        static assert(is(ElementType!(T[2]) == T));
        static assert(is(ElementType!(inout(int)[]) == inout(int)));
    }

    static assert(is(ElementType!(string) == immutable(char)));
    static assert(is(ElementType!(wstring) == immutable(wchar)));
    static assert(is(ElementType!(dstring) == immutable(dchar)));

    {
        static struct S
        {
            @disable this(this);
        }
        static assert(is(ElementType!(S[]) == S));
    }

    {
        static struct E
        {
            ushort id;
        }
        static struct R
        {
            E front()
            {
                return E.init;
            }
        }
        static assert(is(ElementType!R == E));
    }
}

unittest // UElementType
{
    import std.meta : AliasSeq;

    static foreach (T; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, char, wchar, dchar))
    {
        static assert(is(UElementType!(T[]) == T));
        static assert(is(UElementType!(const(T)[]) == T));
        static assert(is(UElementType!(immutable(T)[]) == T));

        static assert(is(UElementType!(T[2]) == T));
        static assert(is(UElementType!(inout(int)[]) == int));
    }

    static assert(is(UElementType!(string) == char));
    static assert(is(UElementType!(wstring) == wchar));
    static assert(is(UElementType!(dstring) == dchar));

    {
        static struct S
        {
            @disable this(this);
        }
        static assert(is(UElementType!(S[]) == S));
        static assert(is(UElementType!(const(S)[]) == S));
    }

    {
        static struct E
        {
            ushort id;
        }
        static struct R
        {
            E front()
            {
                return E.init;
            }
        }
        static assert(is(UElementType!R == E));
    }
}

nothrow pure @safe unittest // empty
{
    {
        int[] a = [];
        assert(a.empty);
        a = null;
        assert(a.empty);
    }

    {
        auto a = [1, 2, 3];
        assert(!a.empty);
        assert(a[3..$].empty);
    }

    {
        int[string] b;
        assert(b.empty);
        b["zero"] = 0;
        assert(!b.empty);
    }
}

nothrow pure @safe unittest // front
{
    {
        int[] a = [1, 2, 3];
        assert(a.front == 1);
    }

    {
        int[3] a = [1, 2, 3];
        assert(a.front == 1);
    }

    {
        string a = "abc";
        assert(a.front == 'a');
    }

    {
        auto a = [1, 2];
        a.front = 4;
        assert(a.front == 4);
        assert(a == [4, 2]);
    }
}

nothrow pure @safe unittest // popFront
{
    {
        auto a = [1, 2, 3];
        a.popFront();
        assert(a == [2, 3]);
        a.popFront();
        assert(a == [3]);
        a.popFront();
        assert(a == []);
    }

    {
        auto a = "abc";
        a.popFront();
        assert(a == "bc");
        a.popFront();
        assert(a == "c");
        a.popFront();
        assert(a == "");
    }
}
