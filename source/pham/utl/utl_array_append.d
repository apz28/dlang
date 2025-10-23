/*
 * Clone from std.array.Appender with enhancement API
 * https://github.com/dlang/phobos/blob/master/std/array.d
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_array_append;

import std.exception : enforce;
import std.format.spec : FormatSpec, singleSpec;
import std.format.write : formatValue;
import std.range.primitives : ElementEncodingType, ElementType, empty, front, isInputRange, isOutputRange, popFront;
import std.traits : Unqual, hasElaborateAssign,
    isAssignable, isCopyable, isDynamicArray, isMutable, isSomeChar;

import pham.utl.utl_array : arrayCalcCapacity, arrayGrow, arrayShrink;

/*
 * Clone from std.array.Appender with enhancement API
 */
struct Appender(T)
if (isDynamicArray!T)
{
    alias ET = ElementEncodingType!T;
    alias UET = Unqual!ET;

public:
    /**
     * Constructs an `Appender` with a given array. Note that this does not copy the
     * data. If the array has a larger capacity as determined by `value.capacity`,
     * it will be used by the appender. After initializing an appender on an array,
     * appending to the original array will reallocate.
     */
    this(T value) @trusted
    {
        this._data = new Data;
        this._data.values = cast(UET[])value; //trusted
        this._data.length = value.length;
        this._data.tryExtendBlock = false;
    }

    /**
     * Constructs an Appender with a given capacity elements for appending.
     */
    this(size_t capacity)
    {
        this._data = null;
        this.reserve(capacity);
    }

    alias opDollar = length;

    /**
     * Appends to the managed array.
     * See_Also: $(LREF Appender.put)
     */
    alias opOpAssign(string op : "~") = put;

    /**
     * Returns: The managed array item at index.
     */
    static if (!is(ET == void) && isCopyable!ET)
    inout(ET) opIndex(size_t index) inout nothrow @trusted
    in
    {
        assert(_data && _data.length != 0);
        assert(index < _data.length);
    }
    do
    {
        // @trusted operation: casting Unqual!ET to inout(ET)
        return cast(typeof(return))(_data.values[index]);
    }

    /**
     * Returns: The managed array.
     */
    inout(ET)[] opSlice() inout nothrow @trusted
    {
        // @trusted operation: casting Unqual!ET[] to inout(ET)[]
        return cast(typeof(return))(_data ? _data.values[0.._data.length] : null);
    }

    inout(ET)[] opSlice(size_t begin, size_t end) inout nothrow @trusted
    in
    {
        assert(begin <= end);
        assert(begin <= length);
        assert(end <= length);
    }
    do
    {
        // @trusted operation: casting Unqual!ET[] to inout(ET)[]
        return cast(typeof(return))(_data ? _data.values[begin..end] : null);
    }

    /**
     * Clears the managed array. This allows the elements of the array to be reused
     * for appending.
     */
    ref typeof(this) clear() nothrow return
    {
        if (_data && _data.length)
            _data.clear();

        return this;
    }

    /**
     * Appends `item` to the managed array. Performs encoding for
     * `char` types if `A` is a differently typed `char` array.
     *
     * Params:
     *     item = the single item to append
     */
    ref typeof(this) put(U)(auto ref U item) return
    if (canPutItem!U)
    {
        static if (isSomeChar!ET && isSomeChar!U && ET.sizeof < U.sizeof)
        {
            import std.typecons : Yes;
            import std.utf : encode;

            UET[ET.sizeof == 1 ? 4 : 2] encoded;
            const len = encode!(Yes.useReplacementDchar)(encoded, item);
            put(encoded[0..len]);
        }
        else
        {
            import core.lifetime : emplace;

            const endLength = ensureAddable(1, 1);
            auto bigData = _data.values[endLength..endLength + 1];
            () @trusted
            {
                auto unqualItem = &cast()item;
                emplace(&bigData[0], *unqualItem);
            }();
            _data.length += 1;
        }

        return this;
    }

    // Const fixing hack.
    ref typeof(this) put(R)(R items) return
    if (canPutConstRange!R)
    {
        alias p = put!(Unqual!R);
        return p(items);
    }

    /**
     * Appends an entire range to the managed array. Performs encoding for
     * `char` elements if `A` is a differently typed `char` array.
     *
     * Params:
     *     items = the range of items to append
     */
    ref typeof(this) put(R)(R items) return
    if (canPutRange!R)
    {
        // note, we disable this branch for appending one type of char to
        // another because we can't trust the length portion.
        static if (!(isSomeChar!ET && isSomeChar!(ElementType!R) && !is(immutable R == immutable ET[]))
            && is(typeof(items.length) == size_t))
        {
            const itemsLength = items.length;

            if (itemsLength == 0)
                return this;

            // optimization -- if this type is something other than a string,
            // and we are adding exactly one element, call the version for one
            // element.
            static if (!isSomeChar!ET)
            {
                if (itemsLength == 1)
                {
                    put(items.front);
                    return this;
                }
            }

            const endLength = ensureAddable(itemsLength, itemsLength);
            auto bigData = _data.values[endLength..endLength + itemsLength];

            static if (is(typeof(_data.values[] = items[]))
                && !hasElaborateAssign!UET
                && isAssignable!(UET, ElementEncodingType!R))
            {
                bigData[0..itemsLength] = items[];
                _data.length += itemsLength;
            }
            else
            {
                import core.internal.lifetime : emplaceRef;

                foreach (ref it; bigData[0..itemsLength])
                {
                    () @trusted { emplaceRef!ET(it, items.front); }();
                    _data.length += 1;
                    items.popFront();
                }
            }
        }
        else static if (isSomeChar!ET && isSomeChar!(ElementType!R)
            && !is(immutable ET == immutable ElementType!R))
        {
            import std.utf : decodeFront;

            // need to decode
            while (!items.empty)
            {
                auto c = items.decodeFront;
                put(c);
            }
        }
        else
        {
            // Generic input range
            for (; !items.empty; items.popFront())
            {
                put(items.front);
            }
        }

        return this;
    }

    /**
     * Reserve at least newCapacity elements for appending. Note that more elements
     * may be reserved than requested. If `newCapacity <= capacity`, then nothing is
     * done.
     *
     * Params:
     *     newCapacity = the capacity the `Appender` should have
     */
    ref typeof(this) reserve(size_t newCapacity) nothrow return
    {
        const currentCapacity = this.capacity;
        if (newCapacity > currentCapacity)
            ensureAddable(newCapacity - currentCapacity, 0);
        return this;
    }

    /**
     * Shrinks the managed array to the given length.
     *
     * Throws: `Exception` if newLength is greater than the managed array length.
     */
    ref typeof(this) shrinkTo(size_t newLength) return
    {
        if (newLength == 0)
            return clear();

        const currentLength = this.length;
        enforce(newLength <= currentLength, "Attempting to shrink Appender with newLength > length");

        if (_data && newLength != currentLength)
            _data.shrinkTo(newLength);

        return this;
    }

    /**
     * Gives a string in the form of `Appender!(A)(data)`.
     *
     * Params:
     *     w = A `char` accepting
     *     $(REF_ALTTEXT output range, isOutputRange, std, range, primitives).
     *     fmt = A $(REF FormatSpec, std, format) which controls how the array
     *     is formatted.
     * Returns:
     *     A `string` if `writer` is not set; `void` otherwise.
     */
    string toString()() const
    {
        import std.traits : isSomeString;

        static if (isSomeString!T)
        {
            static if (is(T: string))
                return data;
            else
                return data.idup;
        }
        else
        {
            // Different reserve lengths because each element in a
            // non-string-like array uses two extra characters for `, `.
            auto spec = singleSpec("%s");

            // Assume each element will have 9 characters
            // [abc, xyz,...]
            const cap = this.length * 9;
            auto buffer = Appender!string(cap);
            return toString(buffer, spec).data;
        }
    }

    /// ditto
    ref Writer toString(Writer)(return ref Writer writer, scope const ref FormatSpec!char fmt) const
    if (isOutputRange!(Writer, char))
    {
        formatValue(writer, data, fmt);
        return writer;
    }

    /**
     * Returns: the capacity of the array (the maximum number of elements the
     * managed array can accommodate before triggering a reallocation). If any
     * appending will reallocate, `0` will be returned.
     */
    pragma(inline, true)
    @property size_t capacity() const @nogc nothrow
    {
        return _data ? _data.capacity : 0;
    }

    @property ref typeof(this) capacity(size_t newCapacity) nothrow return
    {
        return reserve(newCapacity);
    }

    /**
     * Returns: The managed array.
     */
    @property inout(ET)[] data() inout nothrow @trusted
    {
        return this[];
    }

    /**
     * Returns: the length of the array
     */
    pragma(inline, true)
    @property size_t length() const @nogc nothrow
    {
        return _data ? _data.length : 0;
    }

private:
    template canPutItem(U)
    {
        enum bool canPutItem = is(Unqual!U : UET) || (isSomeChar!U && isSomeChar!ET);
    }

    template canPutConstRange(R)
    {
        enum bool canPutConstRange = isInputRange!(Unqual!R) && !isInputRange!R
            && canPutItem!(ElementType!R);
    }

    template canPutRange(R)
    {
        enum bool canPutRange = isInputRange!R && canPutItem!(ElementType!R);
    }

    /**
     * Ensure we can add additionalLength elements, resizing as necessary
     * Returns the current length
     */
    pragma(inline, true)
    size_t ensureAddable(const(size_t) additionalLength, const(size_t) usingLength) nothrow @safe
    in
    {
        assert(additionalLength > 0);
        assert(usingLength <= additionalLength);
    }
    do
    {
        if (!_data)
            _data = new Data;

        const len = _data.length;
        if (_data.capacity < len + additionalLength)
            arrayGrow!UET(_data.values, _data.tryExtendBlock, additionalLength, usingLength, false);
        return len;
    }

    static struct Data
    {
        UET[] values;
        size_t length;
        bool tryExtendBlock;

        void clear() nothrow @trusted
        {
            static if (isMutable!ET)
                arrayShrink!UET(values, length, tryExtendBlock, 0);
            else
            {
                values = [];
                length = 0;
                tryExtendBlock = false;
            }
        }

        void shrinkTo(const(size_t) newLength) nothrow @trusted
        in
        {
            assert(newLength < this.length);
        }
        do
        {
            static if (isMutable!ET)
                arrayShrink!UET(values, length, tryExtendBlock, newLength);
            else
            {
                values = values[0..newLength];
                this.length = newLength;
                tryExtendBlock = false;
            }
        }

        pragma(inline, true)
        @property size_t capacity() const nothrow pure @safe
        {
            return values.length;
        }
    }

    Data* _data;
}

/**
 * Convenience function that returns an $(LREF Appender) instance,
 * optionally initialized with `array`.
 */
Appender!(E[]) appender(A : E[], E)(auto ref A value)
{
    import std.traits : isStaticArray;

    static assert(!isStaticArray!A || __traits(isRef, value), "Cannot create Appender from an rvalue static array");

    return Appender!(E[])(value);
}

///dito
Appender!A appender(A)(size_t capacity = 0)
if (isDynamicArray!A)
{
    return Appender!A(capacity);
}


nothrow pure @safe unittest // Appender
{
    {
        Appender!string app;
        string b = "abcdefg";
        foreach (char c; b)
            app.put(c);
        assert(app[] == "abcdefg");
        assert(app[0] == 'a');
        assert(app[$-1] == 'g');
        assert(app.length == 7);
    }

    {
        int[] a = [1, 2];
        auto app2 = appender(a);
        assert(app2.length == 2);
        app2.put(3);
        app2.put([4, 5, 6]);
        assert(app2[] == [1, 2, 3, 4, 5, 6]);
        assert(app2[0] == 1);
        assert(app2[$-1] == 6);
        assert(app2.length == 6);
    }
}

pure @safe unittest // Appender
{
    import std.format : format;
    import std.format.spec : singleSpec;

    Appender!(int[]) app;
    app.put(1);
    app.put(2);
    app.put(3);
    assert("%s".format(app) == "%s".format([1,2,3]));

    Appender!string app2;
    auto spec = singleSpec("%s");
    app.toString(app2, spec);
    assert(app2[] == "[1, 2, 3]");

    Appender!string app3;
    spec = singleSpec("%(%04d, %)");
    app.toString(app3, spec);
    assert(app3[] == "0001, 0002, 0003");

    Appender!string app4;
    app4.put('A');
    app4.put("0123456789");
    app4.put('B');
    assert(app4.toString() == "A0123456789B");
}

// https://issues.dlang.org/show_bug.cgi?id=17251
nothrow pure @safe unittest // Appender
{
    static struct R
    {
        int front() const { return 0; }
        bool empty() const { return true; }
        void popFront() {}
    }

    auto app = appender!(R[]);
    const(R)[1] r;
    app.put(r[0]);
    app.put(r[]);
}

// https://issues.dlang.org/show_bug.cgi?id=19572
nothrow pure @safe unittest // Appender
{
    static struct Struct
    {
        int value;

        int fun() const { return 23; }
        alias this = fun;
    }

    Appender!(Struct[]) appender;
    appender.put(const(Struct)(42));
    auto result = appender[][0];
    assert(result.value != 23);
}

pure @safe unittest // Appender
{
    import std.conv : to;
    import std.utf : byCodeUnit;

    auto str = "??????";
    auto wstr = appender!wstring();
    wstr.put(str.byCodeUnit);
    assert(wstr.data == str.to!wstring);
}

// https://issues.dlang.org/show_bug.cgi?id=21256
pure @safe unittest // Appender
{
    Appender!string app1;
    app1.toString();

    Appender!(int[]) app2;
    app2.toString();
}

nothrow pure @safe unittest // Appender
{
    auto app = appender!(char[])();
    string b = "abcdefg";
    foreach (char c; b)
        app.put(c);
    assert(app[] == "abcdefg");
}

nothrow pure @safe unittest // Appender
{
    auto app = appender!(char[])();
    string b = "abcdefg";
    foreach (char c; b)
        app ~= c;
    assert(app[] == "abcdefg");
}

nothrow pure @safe unittest // Appender
{
    int[] a = [1, 2];
    auto app2 = appender(a);
    assert(app2[] == [1, 2]);
    app2.put(3);
    app2.put([ 4, 5, 6 ][]);
    assert(app2[] == [1, 2, 3, 4, 5, 6]);
    app2.put([7]);
    assert(app2[] == [1, 2, 3, 4, 5, 6, 7]);
}

nothrow pure @safe unittest // Appender
{
    auto app4 = appender([]);
    try // shrinkTo may throw
    {
        app4.shrinkTo(0);
    }
    catch (Exception) assert(0);
}

// https://issues.dlang.org/show_bug.cgi?id=5663
// https://issues.dlang.org/show_bug.cgi?id=9725
nothrow pure @safe unittest // Appender
{
    import std.exception : assertNotThrown;
    import std.meta : AliasSeq;

    static foreach (S; AliasSeq!(char[], const(char)[], string))
    {
        {
            Appender!S app5663i;
            assertNotThrown(app5663i.put("\xE3"));
            assert(app5663i[] == "\xE3");

            Appender!S app5663c;
            assertNotThrown(app5663c.put(cast(const(char)[])"\xE3"));
            assert(app5663c[] == "\xE3");

            Appender!S app5663m;
            assertNotThrown(app5663m.put("\xE3".dup));
            assert(app5663m[] == "\xE3");
        }

        // ditto for ~=
        {
            Appender!S app5663i;
            assertNotThrown(app5663i ~= "\xE3");
            assert(app5663i[] == "\xE3");

            Appender!S app5663c;
            assertNotThrown(app5663c ~= cast(const(char)[])"\xE3");
            assert(app5663c[] == "\xE3");

            Appender!S app5663m;
            assertNotThrown(app5663m ~= "\xE3".dup);
            assert(app5663m[] == "\xE3");
        }
    }
}

// https://issues.dlang.org/show_bug.cgi?id=10122
nothrow pure @safe unittest // Appender
{
    static void assertCTFEable(alias dg)()
    {
        static assert({ cast(void) dg(); return true; }());
        cast(void) dg();
    }

    static struct S10122
    {
        int val;

        @disable this();
        this(int v) @safe pure nothrow { val = v; }
    }

    assertCTFEable!(
    {
        auto w = appender!(S10122[])();
        w.put(S10122(1));
        assert(w[].length == 1 && w[][0].val == 1);
    });
}

nothrow pure @safe unittest // Appender
{
    import std.exception : assertThrown;

    int[] a = [1, 2];
    auto app2 = appender(a);
    assert(app2[] == [ 1, 2 ]);
    app2 ~= 3;
    app2 ~= [4, 5, 6][];
    assert(app2[] == [1, 2, 3, 4, 5, 6]);
    app2 ~= [7];
    assert(app2[] == [1, 2, 3, 4, 5, 6, 7]);

    app2.capacity = 5;
    assert(app2.capacity >= 5);

    try // shrinkTo may throw
    {
        app2.shrinkTo(3);
    }
    catch (Exception) assert(0);
    assert(app2[] == [1, 2, 3]);
    assertThrown(app2.shrinkTo(5));

    const app3 = app2;
    assert(app3.capacity >= 3);
    assert(app3[] == [1, 2, 3]);
}

nothrow pure @safe unittest // Appender
{
    // pre-allocate space for at least 10 elements (this avoids costly reallocations)
    auto w = appender!string(10);
    assert(w.capacity >= 10);

    w.put('a'); // single elements
    w.put("bc"); // multiple elements

    // use the append syntax
    w ~= 'd';
    w ~= "ef";

    assert(w[] == "abcdef");
}

nothrow pure @safe unittest // Appender
{
    auto w = appender!string(4);
    cast(void) w.capacity;
    cast(void) w[];
    try
    {
        wchar wc = 'a';
        dchar dc = 'a';
        w.put(wc);    // decoding may throw
        w.put(dc);    // decoding may throw
    }
    catch (Exception) assert(0);
}

nothrow pure @safe unittest // Appender
{
    auto w = appender!(int[])();
    w.capacity = 4;
    cast(void) w.capacity;
    cast(void) w[];
    w.put(10);
    w.put([10]);
    w.clear();
    try
    {
        w.shrinkTo(0);
    }
    catch (Exception) assert(0);

    static struct N
    {
        int payload;
        alias this = payload;
    }
    w.put(N(1));
    w.put([N(2)]);

    static struct S(T)
    {
        @property bool empty() { return true; }
        @property T front() { return T.init; }
        void popFront() {}
    }
    S!int r;
    w.put(r);
}

nothrow pure @safe unittest // Appender
{
    import std.range;

    //Coverage for put(Range)
    static struct S1
    {
    }
    static struct S2
    {
        void opAssign(S2){}
    }
    auto a1 = Appender!(S1[])();
    auto a2 = Appender!(S2[])();
    auto au1 = Appender!(const(S1)[])();
    a1.put(S1().repeat().take(10));
    a2.put(S2().repeat().take(10));
    auto sc1 = const(S1)();
    au1.put(sc1.repeat().take(10));
}

@system unittest // Appender
{
    import std.range;

    static struct S2
    {
        void opAssign(S2)
        {}
    }
    auto au2 = Appender!(const(S2)[])();
    auto sc2 = const(S2)();
    au2.put(sc2.repeat().take(10));
}

nothrow pure @system unittest // Appender
{
    static struct S
    {
        int* p;
    }

    auto a0 = Appender!(S[])();
    auto a1 = Appender!(const(S)[])();
    auto a2 = Appender!(immutable(S)[])();
    auto s0 = S(null);
    auto s1 = const(S)(null);
    auto s2 = immutable(S)(null);
    a1.put(s0);
    a1.put(s1);
    a1.put(s2);
    a1.put([s0]);
    a1.put([s1]);
    a1.put([s2]);
    a0.put(s0);
    static assert(!is(typeof(a0.put(a1))));
    static assert(!is(typeof(a0.put(a2))));
    a0.put([s0]);
    static assert(!is(typeof(a0.put([a1]))));
    static assert(!is(typeof(a0.put([a2]))));
    static assert(!is(typeof(a2.put(a0))));
    static assert(!is(typeof(a2.put(a1))));
    a2.put(s2);
    static assert(!is(typeof(a2.put([a0]))));
    static assert(!is(typeof(a2.put([a1]))));
    a2.put([s2]);
}

// https://issues.dlang.org/show_bug.cgi?id=9528
nothrow pure @safe unittest // Appender
{
    const(E)[] fastCopy(E)(E[] src)
    {
        auto app = appender!(const(E)[])();
        foreach (i, e; src)
            app.put(e);
        return app[];
    }

    static class C {}
    static struct S { const(C) c; }
    S[] s = [S(new C)];

    auto t = fastCopy(s); // Does not compile
    assert(t.length == 1);
}

nothrow pure @safe unittest // Appender
{
    import std.algorithm.comparison : equal;

    //New appender signature tests
    alias mutARR = int[];
    alias conARR = const(int)[];
    alias immARR = immutable(int)[];

    mutARR mut;
    conARR con;
    immARR imm;

    auto app1 = Appender!mutARR(mut);                //Always worked. Should work. Should not create a warning.
    app1.put(7);
    assert(equal(app1[], [7]));
    static assert(!is(typeof(Appender!mutARR(con)))); //Never worked.  Should not work.
    static assert(!is(typeof(Appender!mutARR(imm)))); //Never worked.  Should not work.

    auto app2 = Appender!conARR(mut); //Always worked. Should work. Should not create a warning.
    app2.put(7);
    assert(equal(app2[], [7]));
    auto app3 = Appender!conARR(con); //Didn't work.   Now works.   Should not create a warning.
    app3.put(7);
    assert(equal(app3[], [7]));
    auto app4 = Appender!conARR(imm); //Didn't work.   Now works.   Should not create a warning.
    app4.put(7);
    assert(equal(app4[], [7]));

    version(none)
    {
        auto app = Appender!immARR(mut);                //Worked. Will cease to work. Creates warning.
        static assert(!is(typeof(Appender!immARR(mut)))); //Worked. Will cease to work. Uncomment me after full deprecation.
    }

    static assert(!is(typeof(Appender!immARR(con))));   //Never worked. Should not work.
    auto app5 = Appender!immARR(imm);                  //Didn't work.  Now works. Should not create a warning.
    app5.put(7);
    assert(equal(app5[], [7]));

    //Deprecated. Please uncomment and make sure this doesn't work:
    //char[] cc;
    //static assert(!is(typeof(Appender!string(cc))));

    //This should always work:
    auto app6 = appender!string(null);
    assert(app6[] == null);
    auto app7 = appender!(const(char)[])(null);
    assert(app7[] == null);
    auto app8 = appender!(char[])(null);
    assert(app8[] == null);
}

nothrow pure @safe unittest // Appender
{
    // Test large allocations (for GC.extend)
    import std.algorithm.comparison : equal;
    import std.range;

    //cover reserve on non-initialized
    auto app = Appender!(char[])(1);
    foreach (_; 0..100_000)
        app.put('a');
    assert(equal(app[], 'a'.repeat(100_000)));
}

nothrow pure @safe unittest // Appender
{
    auto reference = new ubyte[](2048 + 1); //a number big enough to have a full page (EG: the GC extends)
    auto arr = reference.dup;
    auto app = appender(arr[0..0]);
    app.capacity = 1; //This should not trigger a call to extend
    app.put(ubyte(1)); //Don't clobber arr
    assert(reference[] == arr[]);
}

nothrow pure @safe unittest // Appender
{
    auto app = Appender!string(10);
    app.put("foo");
    const foo = app[];
    assert(foo == "foo");

    app.clear();
    app.put("foo2");
    const foo2 = app[];
    assert(foo2 == "foo2");
    assert(foo == "foo");

    try
    {
        app.shrinkTo(1);
    }
    catch (Exception) assert(0);
    const foo1 = app[];
    assert(foo1 == "f");
    assert(foo2 == "foo2");
    assert(foo == "foo");

    app.put("oo3");
    assert(app[] == "foo3");
    assert(foo1 == "f");
    assert(foo2 == "foo2");
    assert(foo == "foo");
}

nothrow pure @safe unittest // Appender
{
    static struct D //dynamic
    {
        int[] i;
        alias this = i;
    }
    static struct S //static
    {
        int[5] i;
        alias this = i;
    }
    static assert(!is(Appender!(char[5])));
    static assert(!is(Appender!D));
    static assert(!is(Appender!S));

    enum int[5] a = [];
    int[5] b;
    D d;
    S s;
    int[5] foo() { return a; }

    static assert(!is(typeof(appender(a))));
    static assert( is(typeof(appender(b))));
    static assert( is(typeof(appender(d))));
    static assert( is(typeof(appender(s))));
    static assert(!is(typeof(appender(foo()))));
}

// https://issues.dlang.org/show_bug.cgi?id=13077
@system unittest // Appender
{
    static class A {}

    // reduced case
    auto w = appender!(shared(A)[])();
    w.put(new shared A());

    // original case
    import std.range;
    InputRange!(shared A) foo()
    {
        return [new shared A].inputRangeObject;
    }
    auto res = foo.array;
    assert(res.length == 1);
}

nothrow pure @safe unittest // Appender
{
    Appender!(int[]) app;
    short[] range = [1, 2, 3];
    app.put(range);
    assert(app[] == [1, 2, 3]);
}

nothrow pure @safe unittest // Appender
{
    import std.range.primitives : put;
    import std.stdio : writeln;

    string s = "hello".idup;
    auto appS = appender(s);
    put(appS, 'w');
    s ~= 'a'; //Clobbers here?
    assert(appS[] == "hellow", appS[]);

    char[] a = "hello".dup;
    auto appA = appender(a);
    put(appA, 'w');
    a ~= 'a'; //Clobbers here?
    assert(appA[] == "hellow", appA[]);
}
