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

module pham.utl.array;

import std.algorithm.mutation : swapAt;
import std.range.primitives : ElementType;
import std.traits : isDynamicArray, isIntegral, isStaticArray, lvalueOf;

version (profile) import pham.utl.test : PerfFunction;

nothrow:

C[] arrayOfChar(C)(C c, size_t count) @safe
if (is(C == char) || is(C == byte) || is(C == ubyte))
{
    if (count)
    {
        auto result = new C[count];
        result[] = c;
        return result;
    }
    else
        return null;
}

void removeAt(T)(ref T array, size_t index) pure
if (isDynamicArray!T)
in
{
    assert(array.length > 0);
    assert(index < array.length);
}
do
{
    //if (GC.inFinalizer())
    //    return;

    // Move all items after index to the left
    if (array.length > 1)
    {
        while (index < array.length - 1)
        {
            array[index] = array[index + 1];
            ++index;
        }
    }

    // Shrink the array length
    // It will set the array[index] to default value when length is reduced
    array.length = array.length - 1;
}

void removeAt(T)(ref T array, size_t index, ref size_t length) pure
if (isStaticArray!T)
in
{
    assert(length > 0 && length <= array.length);
    assert(index < length);
}
do
{
    //if (GC.inFinalizer())
    //    return;

    // Safety check
    if (length > array.length)
        length = array.length;

    // Move all items after index to the left
    if (length > 1)
    {
        while (index < length - 1)
        {
            array[index] = array[index + 1];
            ++index;
        }
    }

    // Reset the value at array[index]
    static if (is(typeof(lvalueOf!T[0]) == char))
        array[index] = char.init;
    else
        array[index] = ElementType!T.init;
    --length;
}

struct IndexedArray(T, ushort StaticSize)
{
//nothrow:

public:
    this(size_t capacity) nothrow pure @safe
    {
        if (capacity > StaticSize)
            _dynamicItems.reserve(capacity);
    }

    this()(inout(T)[] values) nothrow
    {
        const valueLength = values.length;
        this(valueLength);
        if (valueLength)
        {
            if (useStatic(valueLength))
            {
                _staticLength = valueLength;
                _staticItems[0..valueLength] = values[0..valueLength];
            }
            else
            {
                _dynamicItems.length = valueLength;
                _dynamicItems[0..valueLength] = values[0..valueLength];
            }
        }
    }

    ref typeof(this) opAssign()(inout(T)[] values) nothrow return
    {
        const valueLength = values.length;
        clear(valueLength);
        if (valueLength)
        {
            if (useStatic(valueLength))
            {
                _staticLength = valueLength;
                _staticItems[0..valueLength] = values[0..valueLength];
            }
            else
            {
                _dynamicItems.length = valueLength;
                _dynamicItems[0..valueLength] = values[0..valueLength];
            }
        }
        return this;
    }

    ref typeof(this) opOpAssign(string op)(T item) nothrow return
    if (op == "~" || op == "+" || op == "-")
    {
        static if (op == "~" || op == "+")
            putBack(item);
        else static if (op == "-")
            remove(item);
        else
            static assert(0);
        return this;
    }

    size_t opDollar() const @nogc nothrow pure
    {
        return length;
    }

    bool opCast(B: bool)() const nothrow pure
    {
        return !empty;
    }

    /** Returns range interface
    */
    inout(T)[] opIndex() inout nothrow pure return
    {
        const len = length;
        return len != 0 ? (useStatic ? _staticItems[0..len] : _dynamicItems) : [];
    }

    T opIndex(const(size_t) index) nothrow
    in
    {
        assert(index < length);
    }
    do
    {
        return useStatic ? _staticItems[index] : _dynamicItems[index];
    }

    ref typeof(this) opIndexAssign(T item, const(size_t) index) nothrow return
    {
        const atLength = index + 1;
        if (!useStatic(atLength) || !useStatic)
        {
            switchToDynamicItems(atLength, atLength > length);
            _dynamicItems[index] = item;
        }
        else
        {
            assert(useStatic(atLength));
            _staticItems[index] = item;
            if (_staticLength < atLength)
                _staticLength = atLength;
        }
        assert(atLength <= length);
        return this;
    }

    static if (isIntegral!T)
    ref typeof(this) opIndexOpAssign(string op)(T item, const(size_t) index) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    in
    {
        assert(index < length);
    }
    do
    {
        if (useStatic)
            mixin("_staticItems[index] " ~ op ~ "= item;");
        else
            mixin("_dynamicItems[index] " ~ op ~ "= item;");
        return this;
    }

    /** Returns range interface
    */
    inout(T)[] opSlice(const(size_t) beginIndex, const(size_t) endIndex) inout nothrow pure return
    in
    {
        assert(beginIndex <= endIndex);
    }
    do
    {
        const len = length;
        if (beginIndex >= len)
            return [];

        return endIndex > len
            ? (useStatic ? _staticItems[beginIndex..len] : _dynamicItems[beginIndex..len])
            : (useStatic ? _staticItems[beginIndex..endIndex] : _dynamicItems[beginIndex..endIndex]);
    }

    ref typeof(this) clear(const(size_t) capacity = 0) nothrow pure return
    {
        if (_staticLength)
        {
            _staticItems[0.._staticLength] = T.init;
            _staticLength = 0;
        }

        if (capacity > StaticSize)
        {
            _dynamicItems.length = 0;
            _dynamicItems.reserve(capacity);
        }
        else
            _dynamicItems = null;

        return this;
    }

    T[] dup() nothrow
    {
        return this[].dup;
    }

    ref typeof(this) fill(T item, const(size_t) beginIndex = 0) nothrow return
    in
    {
        assert(beginIndex < length);
    }
    do
    {
        if (useStatic)
            _staticItems[beginIndex..length] = item;
        else
            _dynamicItems[beginIndex..length] = item;
        return this;
    }

    ptrdiff_t indexOf(in T item) @trusted
    {
        if (length == 0)
            return -1;

        auto items = this[];
        foreach (i; 0..items.length)
        {
            if (items[i] == item)
                return i;
        }
        return -1;
    }

    pragma(inline, true)
    T* ptr(const(size_t) index) nothrow pure return
    in
    {
        assert(index < length);
    }
    do
    {
        return useStatic ? &_staticItems[index] : &_dynamicItems[index];
    }

    alias put = putBack;

    ref typeof(this) put()(inout(T)[] items, const(size_t) beginIndex) nothrow return
    {
        const atLength = beginIndex + items.length;
        if (!useStatic(atLength) || !useStatic)
        {
            switchToDynamicItems(atLength, atLength > length);
            _dynamicItems[beginIndex..beginIndex + items.length] = items[0..items.length];
        }
        else
        {
            assert(useStatic(atLength));
            _staticItems[beginIndex..beginIndex + items.length] = items[0..items.length];
            if (_staticLength < atLength)
                _staticLength = atLength;
        }
        assert(atLength <= length);
        return this;
    }

    T putBack(T item) nothrow
    {
        const newLength = length + 1;
        if (!useStatic(newLength) || !useStatic)
        {
            switchToDynamicItems(newLength, true);
            _dynamicItems[newLength - 1] = item;
        }
        else
        {
            assert(useStatic(newLength));
            _staticItems[_staticLength++] = item;
        }
        assert(length == newLength);

        return item;
    }

    T remove(in T item)
    {
        const i = indexOf(item);
        if (i >= 0)
            return doRemove(i);
        else
            return T.init;
    }

    T removeAt(const(size_t) index) nothrow
    {
        if (index < length)
            return doRemove(index);
        else
            return T.init;
    }

    ref typeof(this) reverse() @nogc nothrow pure
    {
        if (const len = length)
        {
            const last = len - 1;
            const steps = len / 2;
            if (useStatic)
            {
                for (size_t i = 0; i < steps; i++)
                    _staticItems.swapAt(i, last - i);
            }
            else
            {
                for (size_t i = 0; i < steps; i++)
                    _dynamicItems.swapAt(i, last - i);
            }
        }
        return this;
    }

    pragma (inline, true)
    @property bool empty() const @nogc nothrow pure
    {
        return length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure
    {
        return useStatic ? _staticLength : _dynamicItems.length;
    }

    @property size_t length(const(size_t) newLength) nothrow pure
    {
        if (length != newLength)
        {
            if (useStatic(newLength) && useStatic)
                _staticLength = newLength;
            else
                switchToDynamicItems(newLength, true);
        }
        return newLength;
    }

    pragma(inline, true)
    @property static size_t staticSize() @nogc nothrow pure
    {
        return StaticSize;
    }

    pragma (inline, true)
    @property bool useStatic() const @nogc nothrow pure
    {
        assert(_dynamicItems.ptr !is null || useStatic(_staticLength));

        return _dynamicItems.ptr is null;
    }

    pragma (inline, true)
    @property bool useStatic(const(size_t) checkLength) const @nogc nothrow pure
    {
        return checkLength <= StaticSize;
    }

private:
    T doRemove(const(size_t) index) nothrow @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        if (useStatic)
        {
            auto res = _staticItems[index];
            .removeAt(_staticItems, index, _staticLength);
            return res;
        }
        else
        {
            auto res = _dynamicItems[index];
            .removeAt(_dynamicItems, index);
            return res;
        }
    }

    void switchToDynamicItems(const(size_t) newLength, bool mustSet) nothrow pure @trusted
    {
        if (useStatic)
        {
            const setLength = mustSet ? newLength : _staticLength;
            const copyLength = _staticLength > setLength ? setLength : _staticLength;
            _dynamicItems.reserve(setLength + (setLength / 2));

            _dynamicItems.length = setLength;
            _dynamicItems[0..copyLength] = _staticItems[0..copyLength];

            _staticLength = 0;
            _staticItems[] = T.init;
        }
        else
        {
            if (newLength > _dynamicItems.capacity)
                _dynamicItems.reserve(newLength + (newLength / 2));
            if (mustSet || _dynamicItems.length < newLength)
                _dynamicItems.length = newLength;
        }
    }

private:
    size_t _staticLength;
    T[] _dynamicItems;
    T[StaticSize] _staticItems;
}


// Any below codes are private
private:

nothrow @safe unittest // array.arrayOfChar
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.array.arrayOfChar");

    assert(arrayOfChar!char('0', 0) == []);
    assert(arrayOfChar!char('0', 1) == "0");
    assert(arrayOfChar!char('0', 10) == "0000000000");
}

nothrow @safe unittest // array.IndexedArray
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.array.IndexedArray");

    auto a = IndexedArray!(int, 2)(0);

    // Check initial state
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
    assert(a.useStatic);

    // Append element
    a.putBack(1);
    assert(!a.empty);
    assert(a.length == 1);
    assert(a.indexOf(1) == 0);
    assert(a[0] == 1);
    assert(a.useStatic);

    // Append second element
    a += 2;
    assert(a.length == 2);
    assert(a.indexOf(2) == 1);
    assert(a[1] == 2);
    assert(a.useStatic);

    // Append element & remove
    a += 10;
    assert(a.length == 3);
    assert(a.indexOf(10) == 2);
    assert(a[2] == 10);
    assert(!a.useStatic);

    a -= 10;
    assert(a.indexOf(10) == -1);
    assert(a.length == 2);
    assert(a.indexOf(2) == 1);
    assert(a[1] == 2);
    assert(!a.useStatic);

    // Check duplicate
    assert(a.dup == [1, 2]);

    // Set new element at index (which is at the end for this case)
    a[2] = 3;
    assert(a.length == 3);
    assert(a.indexOf(3) == 2);
    assert(a[2] == 3);

    // Replace element at index
    a[1] = -1;
    assert(a.length == 3);
    assert(a.indexOf(-1) == 1);
    assert(a[1] == -1);

    // Check duplicate
    assert(a.dup == [1, -1, 3]);

    // Remove element
    auto r = a.remove(-1);
    assert(r == -1);
    assert(a.length == 2);
    assert(a.indexOf(-1) == -1);
    assert(!a.useStatic);

    // Remove element at
    r = a.removeAt(0);
    assert(r == 1);
    assert(a.length == 1);
    assert(a.indexOf(1) == -1);
    assert(a[0] == 3);
    assert(!a.useStatic);

    // Clear all elements
    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
    assert(a.useStatic);

    a[0] = 1;
    assert(!a.empty);
    assert(a.length == 1);
    assert(a.useStatic);

    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
    assert(a.useStatic);

    a.putBack(1);
    a.fill(10);
    assert(a.length == 1);
    assert(a[0] == 10);
}

nothrow unittest // IndexedArray.reverse
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.array.IndexedArray.reverse");

    auto a = IndexedArray!(int, 3)(0);

    a.clear().put([1, 2], 0);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5], 0);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}
