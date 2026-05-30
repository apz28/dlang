/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2026 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_apply;

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


// Any below codes are private
private:

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
