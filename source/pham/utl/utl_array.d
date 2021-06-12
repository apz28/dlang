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

import std.range.primitives : ElementType;
import std.traits : isDynamicArray, isStaticArray, lvalueOf;

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

struct IndexedArray(T, ushort staticSize)
{
nothrow:

public:
    this(size_t capacity) pure @safe
    {
        if (capacity > staticSize)
            _dynamicItems.reserve(capacity);
    }

    this(inout(T)[] values)
    {
        const valueLength = values.length;
        this(valueLength);
        if (valueLength)
        {
            if (valueLength <= staticSize)
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

    ref typeof(this) opOpAssign(string op)(T item) return
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

    bool opCast(B: bool)() const nothrow pure
    {
        return !empty;
    }

    /** Returns range interface
    */
    T[] opSlice() return
    {
        const len = length;
        return len != 0 ? (useStatic() ? _staticItems[0..len] : _dynamicItems) : null;
    }

    T opIndex(size_t index)
    in
    {
        assert(index < length);
    }
    do
    {
        return useStatic() ? _staticItems[index] : _dynamicItems[index];
    }

    ref typeof(this) opIndexAssign(T item, size_t index) return
    {
        const atLength = index + 1;
        if (atLength > staticSize || !useStatic())
        {
            switchToDynamicItems(atLength, false);
            _dynamicItems[index] = item;
        }
        else
        {
            _staticItems[index] = item;
            if (_staticLength < atLength)
                _staticLength = atLength;
            assert(_staticLength <= staticSize);
        }
        assert(atLength <= length);
        return this;
    }

    ref typeof(this) opIndexAssign(inout(T)[] items, size_t startIndex) return
    {
        const atLength = startIndex + items.length;
        if (atLength > staticSize || !useStatic())
        {
            switchToDynamicItems(atLength, false);
            _dynamicItems[startIndex..startIndex + items.length] = items[0..items.length];
        }
        else
        {
            _staticItems[startIndex..startIndex + items.length] = items[0..items.length];
            if (_staticLength < atLength)
                _staticLength = atLength;
            assert(_staticLength <= staticSize);
        }
        assert(atLength <= length);
        return this;
    }

    /** Returns range interface
    */
    T[] opSlice(size_t begin = 0, size_t end = size_t.max) pure return
    in
    {
        assert(begin < end);
        assert(begin < length);
    }
    do
    {
        const len = length;
        if (end > len)
            end = len;

        return end - begin > 0 ? (useStatic() ? _staticItems[begin..end] : _dynamicItems[begin..end]) : null;
    }

    ref typeof(this) clear(size_t capacity = 0) pure return
    {
        assert(_staticLength <= staticSize);

        if (_staticLength)
        {
            _staticItems[0.._staticLength] = T.init;
            _staticLength = 0;
        }

        if (capacity > staticSize)
        {
            _dynamicItems.length = 0;
            _dynamicItems.reserve(capacity);
        }
        else
            _dynamicItems = null;
        return this;
    }

    T[] dup()
    {
        return this[].dup;
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

    alias put = putBack;

    T putBack(T item)
    {
        const newLength = length + 1;
        if (newLength > staticSize || !useStatic())
        {
            switchToDynamicItems(newLength, true);
            _dynamicItems[newLength - 1] = item;
        }
        else
        {
            _staticItems[_staticLength++] = item;
            assert(_staticLength <= staticSize);
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

    T removeAt(size_t index)
    {
        if (index < length)
            return doRemove(index);
        else
            return T.init;
    }

    T* ptr(size_t startIndex = 0) return
    in
    {
        assert(startIndex < length);
    }
    do
    {
        return useStatic() ? &_staticItems[startIndex] : &_dynamicItems[startIndex];
    }

    ref typeof(this) fill(T item, size_t startIndex = 0) return
    in
    {
        assert(startIndex < length);
    }
    do
    {
        if (useStatic())
            _staticItems[startIndex..length] = item;
        else
            _dynamicItems[startIndex..length] = item;
        return this;
    }

    pragma (inline, true)
    bool useStatic() const nothrow
    {
        return _dynamicItems.ptr is null;
    }

    @property bool empty() const nothrow pure
    {
        return length == 0;
    }

    @property size_t length() const nothrow pure
    {
        return useStatic() ? _staticLength : _dynamicItems.length;
    }

    @property size_t length(size_t newLength)
    {
        if (length != newLength)
        {
            if (newLength <= staticSize && useStatic())
                _staticLength = newLength;
            else
                switchToDynamicItems(newLength, true);
        }
        return newLength;
    }

private:
    T doRemove(size_t index) @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        if (useStatic())
        {
            assert(_staticLength > 0 && _staticLength <= staticSize);
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

    void switchToDynamicItems(size_t newLength, bool mustSet) pure @trusted
    {
        if (useStatic())
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
    T[] _dynamicItems;
    T[staticSize] _staticItems;
    size_t _staticLength;
}

struct UnshrinkArray(T)
{
nothrow:

public:
    this(size_t capacity) @safe
    {
        if (capacity)
            _items.reserve(capacity);
    }

    ref typeof(this) opOpAssign(string op)(T item) return
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

    bool opCast(B: bool)() const pure
    {
        return !empty;
    }

    /**
     * Returns range interface
     */
    T[] opSlice() return
    {
        return _items;
    }

    T opIndex(size_t index)
    in
    {
        assert(index < _items.length);
    }
    do
    {
        return _items[index];
    }

    ref typeof(this) opIndexAssign(T item, size_t index) return
    in
    {
        assert(index < _items.length);
    }
    do
    {
        _items[index] = item;
        return this;
    }

    ref typeof(this) clear() pure return @trusted
    {
        _items.length = 0;
        return this;
    }

    T[] dup()
    {
        if (_items.length)
            return _items.dup;
        else
            return null;
    }

    ptrdiff_t indexOf(scope const T item) @trusted
    {
        version (profile) auto p = PerfFunction.create();

        foreach (i; 0.._items.length)
        {
            static if (is(T == class))
            {
                if (_items[i] is item)
                    return i;
            }
            else
            {
                if (_items[i] == item)
                    return i;
            }
        }

        return -1;
    }

    T putBack(T item)
    {
        _items ~= item;
        return item;
    }

    T remove(scope const T item)
    {
        const i = indexOf(item);
        if (i >= 0)
            return doRemove(i);
        else
            return T.init;
    }

    T removeAt(size_t index)
    {
        if (index < length)
            return doRemove(index);
        else
            return T.init;
    }

    @property bool empty() const pure @safe
    {
        return length == 0;
    }

    @property size_t length() const pure @safe
    {
        return _items.length;
    }

private:
    T doRemove(size_t index) @trusted
    in
    {
        assert(_items.length > 0);
        assert(index < _items.length);
    }
    do
    {
        auto res = _items[index];
        .removeAt(_items, index);
        return res;
    }

private:
    T[] _items;
}


// Any below codes are private
private:


nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest("unittest utl.array.arrayOfChar");

    assert(arrayOfChar!char('0', 0) == []);
    assert(arrayOfChar!char('0', 1) == "0");
    assert(arrayOfChar!char('0', 10) == "0000000000");
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest("unittest utl.array.IndexedArray");

    auto a = IndexedArray!(int, 2)(0);

    // Check initial state
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
    assert(a.useStatic());

    // Append element
    a.putBack(1);
    assert(!a.empty);
    assert(a.length == 1);
    assert(a.indexOf(1) == 0);
    assert(a[0] == 1);
    assert(a.useStatic());

    // Append second element
    a += 2;
    assert(a.length == 2);
    assert(a.indexOf(2) == 1);
    assert(a[1] == 2);
    assert(a.useStatic());

    // Append element & remove
    a += 10;
    assert(a.length == 3);
    assert(a.indexOf(10) == 2);
    assert(a[2] == 10);
    assert(!a.useStatic());

    a -= 10;
    assert(a.indexOf(10) == -1);
    assert(a.length == 2);
    assert(a.indexOf(2) == 1);
    assert(a[1] == 2);
    assert(!a.useStatic());

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
    assert(!a.useStatic());

    // Remove element at
    r = a.removeAt(0);
    assert(r == 1);
    assert(a.length == 1);
    assert(a.indexOf(1) == -1);
    assert(a[0] == 3);
    assert(!a.useStatic());

    // Clear all elements
    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
    assert(a.useStatic());

    a[0] = 1;
    assert(!a.empty);
    assert(a.length == 1);
    assert(a.useStatic());

    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
    assert(a.useStatic());

    a.putBack(1);
    a.fill(10);
    assert(a.length == 1);
    assert(a[0] == 10);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest("unittest utl.array.UnshrinkArray");

    auto a = UnshrinkArray!int(0);

    // Check initial state
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);

    // Append element
    a.putBack(1);
    assert(!a.empty);
    assert(a.length == 1);
    assert(a.indexOf(1) == 0);
    assert(a[0] == 1);

    // Append element
    a += 2;
    assert(a.length == 2);
    assert(a.indexOf(2) == 1);
    assert(a[1] == 2);

    // Append element & remove
    a += 10;
    assert(a.length == 3);
    assert(a.indexOf(10) == 2);
    assert(a[2] == 10);

    a -= 10;
    assert(a.indexOf(10) == -1);
    assert(a.length == 2);
    assert(a.indexOf(2) == 1);
    assert(a[1] == 2);

    // Check duplicate
    assert(a.dup == [1, 2]);

    // Append element
    a ~= 3;
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

    // Remove element at
    r = a.removeAt(0);
    assert(r == 1);
    assert(a.length == 1);
    assert(a.indexOf(1) == -1);
    assert(a[0] == 3);

    // Clear all elements
    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);
}
