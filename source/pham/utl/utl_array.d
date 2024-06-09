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

module pham.utl.utl_array;

import std.range.primitives : ElementType;
import std.traits : isDynamicArray, isIntegral, isSomeChar, isStaticArray, lvalueOf;

debug(pham_utl_utl_array) import std.stdio : writeln;
import pham.utl.utl_disposable : DisposingReason;

nothrow @safe:


C[] arrayOfChar(C)(C c, size_t count)
if (is(C == char) || is(C == byte) || is(C == ubyte))
{
    if (count)
    {
        auto result = new C[](count);
        result[] = c;
        return result;
    }
    else
        return null;
}

ptrdiff_t indexOf(T)(scope const(T)[] items, const(T) item) @trusted
{
    //scope (failure) assert(0, "Assume nothrow failed");
    
    foreach (i; 0..items.length)
    {
        if (items[i] == item)
            return i;
    }
    return -1;
}

ptrdiff_t indexOf(T)(scope const(T)[] item, scope const(T)[] subItem) @nogc pure
if (isSomeChar!T)
{
    const subLength = subItem.length;
    if (subLength == 0 || subLength > item.length)
        return -1;
        
    const first = subItem[0];
    
    foreach (i; 0..item.length - (subLength - 1))
    {
        if (item[i] != first)
            continue;
        
        bool found = true;
        foreach (j; 1..subLength)
        {
            if (item[i + j] != subItem[j])
            {
                found = false;
                break;
            }
        }
        
        if (found)
            return i;
    }
    return -1;
}

void inplaceMoveToLeft(ref ubyte[] data, size_t fromIndex, size_t toIndex, size_t nBytes) pure @trusted
in
{
    assert(nBytes > 0);
    assert(toIndex < fromIndex);
    assert(toIndex + nBytes <= data.length);
    assert(fromIndex + nBytes <= data.length);
}
do
{
    import core.stdc.string : memmove;

    memmove(data.ptr + toIndex, data.ptr + fromIndex, nBytes);
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
    // Move all items after index to the left
    const lengthLess = array.length - 1;
    if (lengthLess > 0)
    {
        while (index < lengthLess)
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
    // Move all items after index to the left
    const lengthLess = length - 1;
    if (lengthLess > 0)
    {
        while (index < lengthLess)
        {
            array[index] = array[index + 1];
            ++index;
        }
    }

    // Reset the value at array[index]
    static if (is(typeof(lvalueOf!T[0]) == char))
        array[index] = char.init;
    else static if (is(typeof(lvalueOf!T[0]) == wchar))
        array[index] = wchar.init;
    else
        array[index] = ElementType!T.init;
        
    length = lengthLess;
}

struct IndexedArray(T, ushort StaticSize)
{
public:
    this(size_t capacity) nothrow pure @safe
    {
        if (capacity > StaticSize)
            _dynamicItems.reserve(capacity);
    }

    this()(scope inout(T)[] values) nothrow
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

    /** Returns range interface
    */
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
        return length == 0 ? -1 : .indexOf(this[], item);
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

    ref typeof(this) put()(scope inout(T)[] items, const(size_t) beginIndex) nothrow return
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
        import std.algorithm.mutation : swapAt;
        
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

struct ShortStringBufferSize(T, ushort StaticSize)
if (StaticSize > 0 && (isSomeChar!T || isIntegral!T))
{
@safe:

public:
    this(this) nothrow pure
    {
        _longData = _longData.dup;
    }

    this(bool shortLength) nothrow pure
    {
        if (shortLength)
            this._length = StaticSize;
    }

    this(const(ushort) shortLength) nothrow pure
    {
        if (shortLength)
        {
            this._length = shortLength;
            if (shortLength > StaticSize)
                this._longData.length = shortLength;
        }
    }

    this(scope const(T)[] values) nothrow pure
    {
        setData(values);
    }

    ref typeof(this) opAssign(scope const(T)[] values) nothrow return
    {
        setData(values);
        return this;
    }

    ref typeof(this) opOpAssign(string op)(T c) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(c);
    }

    ref typeof(this) opOpAssign(string op)(scope const(T)[] s) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(s);
    }

    static if (isIntegral!T)
    ref typeof(this) opOpAssign(string op)(scope const(T)[] rhs) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    {
        const len = _length > rhs.length ? rhs.length : _length;
        if (useShortSize)
        {
            foreach (i; 0..len)
                mixin("_shortData[i] " ~ op ~ "= rhs[i];");

            static if (op == "&")
            if (len < _length)
                _shortData[len.._length] = 0;
        }
        else
        {
            foreach (i; 0..len)
                mixin("_longData[i] " ~ op ~ "= rhs[i];");

            static if (op == "&")
            if (len < _length)
                _longData[len.._length] = 0;
        }
        return this;
    }

    size_t opDollar() const @nogc nothrow pure
    {
        return _length;
    }

    bool opEquals(scope const(typeof(this)) rhs) const @nogc nothrow pure
    {
        scope const rhsd = rhs.useShortSize ? rhs._shortData[0..rhs._length] : rhs._longData[0..rhs._length];
        return useShortSize ? (_shortData[0.._length] == rhsd) : (_longData[0.._length] == rhsd);
    }

    bool opEquals(scope const(T)[] rhs) const @nogc nothrow pure
    {
        return useShortSize ? (_shortData[0.._length] == rhs) : (_longData[0.._length] == rhs);
    }

    inout(T)[] opIndex() inout nothrow pure return
    {
        return useShortSize ? _shortData[0.._length] : _longData[0.._length];
    }

    T opIndex(const(size_t) index) const @nogc nothrow pure
    in
    {
        assert(index < length);
    }
    do
    {
        return useShortSize ? _shortData[index] : _longData[index];
    }

    inout(T)[] opSlice(const(size_t) beginIndex, const(size_t) endIndex) inout nothrow pure return
    in
    {
        assert(beginIndex <= endIndex);
    }
    do
    {
        if (beginIndex >= _length)
            return [];
        else
            return endIndex > _length
                ? (useShortSize ? _shortData[beginIndex.._length] : _longData[beginIndex.._length])
                : (useShortSize ? _shortData[beginIndex..endIndex] : _longData[beginIndex..endIndex]);
    }

    ref typeof(this) opIndexAssign(T c, const(size_t) index) @nogc nothrow return
    in
    {
        assert(index < length);
    }
    do
    {
        if (useShortSize)
            _shortData[index] = c;
        else
            _longData[index] = c;
        return this;
    }

    static if (isIntegral!T)
    ref typeof(this) opIndexOpAssign(string op)(T c, const(size_t) index) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    in
    {
        assert(index < length);
    }
    do
    {
        if (useShortSize)
            mixin("_shortData[index] " ~ op ~ "= c;");
        else
            mixin("_longData[index] " ~ op ~ "= c;");
        return this;
    }

    ref typeof(this) chopFront(const(size_t) chopLength) nothrow pure return
    {
        if (chopLength >= _length)
            return clear();

        const newLength = _length - chopLength;
                
        //import std.stdio : writeln; debug writeln("_length=", _length, ", chopLength=", chopLength, ", newLength=", newLength, ", StaticSize=", StaticSize, ", _shortData.length=", _shortData.length);
        
        if (useShortSize)
        {
            foreach (i; 0..newLength)
                _shortData[i] = _shortData[i + chopLength];
        }
        else
        {
            // Switch from long to short?
            if (useShortSize(newLength))
                _shortData[0..newLength] = _longData[chopLength.._length];
            else
            {
                foreach (i; 0..newLength)
                    _longData[i] = _longData[i + chopLength];
            }
        }
        
        _length = newLength;
        return this;
    }

    ref typeof(this) chopTail(const(size_t) chopLength) nothrow pure return
    {
        if (chopLength >= _length)
            return clear();

        const newLength = _length - chopLength;

        //import std.stdio : writeln; debug writeln("_length=", _length, ", chopLength=", chopLength, ", newLength=", newLength, ", StaticSize=", StaticSize, ", _shortData.length=", _shortData.length);
        
        // Switch from long to short?
        if (!useShortSize && useShortSize(newLength))
            _shortData[0..newLength] = _longData[0..newLength];
            
        _length = newLength;
        return this;
    }

    ref typeof(this) clear(const(bool) shortLength = false) nothrow pure return
    {
        if (shortLength)
        {
            _shortData[] = 0;
            _longData[] = 0;
        }
        _length = shortLength ? StaticSize : 0;
        return this;
    }

    T[] consume() nothrow pure
    {
        T[] result = _length != 0
            ? (useShortSize ? _shortData[0.._length].dup : _longData[0.._length])
            : [];

        _shortData[] = 0;
        _longData = null;
        _length = 0;

        return result;
    }

    immutable(T)[] consumeUnique() nothrow pure @trusted
    {
        T[] result = _length != 0
            ? (useShortSize ? _shortData[0.._length].dup : _longData[0.._length])
            : [];

        _shortData[] = 0;
        _longData = null;
        _length = 0;

        return cast(immutable(T)[])(result);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        _shortData[] = 0;
        _longData[] = 0;
        _longData = null;
        _length = 0;
    }

    inout(T)[] left(size_t len) inout nothrow pure return
    {
        if (len >= _length)
            return opIndex();
        else
            return opIndex()[0..len];
    }

    ref typeof(this) removeFront(const(T) removingValue) nothrow pure return
    {
        while (_length && opIndex(0) == removingValue)
            chopFront(1);
        return this;
    }

    ref typeof(this) removeTail(const(T) removingValue) nothrow pure return
    {
        while (_length && opIndex(_length - 1) == removingValue)
            chopTail(1);
        return this;
    }

    ref typeof(this) put(T c) nothrow pure return
    {
         const newLength = _length + 1;
        // Still in short?
        if (useShortSize(newLength))
            _shortData[_length++] = c;
        else
        {
            if (useShortSize)
                switchToLongData(1);
            else if (_longData.length < newLength)
                _longData.length = alignAddtionalLength(newLength);
            _longData[_length++] = c;
        }
        return this;
    }

    ref typeof(this) put(scope const(T)[] s) nothrow pure return
    {
        if (!s.length)
            return this;

        const newLength = _length + s.length;
        // Still in short?
        if (useShortSize(newLength))
        {
            _shortData[_length..newLength] = s[0..$];
        }
        else
        {
            if (useShortSize)
                switchToLongData(s.length);
            else if (_longData.length < newLength)
                _longData.length = alignAddtionalLength(newLength);
            _longData[_length..newLength] = s[0..$];
        }
        _length = newLength;
        return this;
    }

    static if (is(T == char))
    ref typeof(this) put(dchar c) nothrow pure return
    {
        import std.typecons : Yes;
        import std.utf : encode, UseReplacementDchar;

        char[4] buffer;
        const len = encode!(Yes.useReplacementDchar)(buffer, c);
        return put(buffer[0..len]);
    }

    ref typeof(this) reverse() @nogc nothrow pure
    {
        import std.algorithm.mutation : swapAt;

        const len = length;
        if (len > 1)
        {
            const last = len - 1;
            const steps = len / 2;
            if (useShortSize)
            {
                foreach (i; 0..steps)
                    _shortData.swapAt(i, last - i);
            }
            else
            {
                foreach (i; 0..steps)
                    _longData.swapAt(i, last - i);
            }
        }
        return this;
    }

    inout(T)[] right(size_t len) inout nothrow pure return
    {
        if (len >= _length)
            return opIndex();
        else
            return opIndex()[_length - len.._length];
    }

    static if (isSomeChar!T)
    immutable(T)[] toString() const nothrow pure
    {
        return _length != 0
            ? (useShortSize ? _shortData[0.._length].idup : _longData[0.._length].idup)
            : [];
    }

    static if (isSomeChar!T)
    ref Writer toString(Writer)(return ref Writer sink) const pure
    {
        if (_length)
            put(sink, opIndex());
        return sink;
    }

    pragma (inline, true)
    @property bool empty() const @nogc nothrow pure
    {
        return _length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure
    {
        return _length;
    }

    pragma(inline, true)
    @property static size_t shortSize() @nogc nothrow pure
    {
        return StaticSize;
    }

    pragma (inline, true)
    @property bool useShortSize() const @nogc nothrow pure
    {
        return _length <= StaticSize;
    }

    pragma(inline, true)
    @property bool useShortSize(const(size_t) checkLength) const @nogc nothrow pure
    {
        return checkLength <= StaticSize;
    }

private:
    pragma(inline, true)
    size_t alignAddtionalLength(const(size_t) additionalLength) @nogc nothrow pure
    {
        if (additionalLength <= overReservedLength)
            return overReservedLength;
        else
            return ((additionalLength + overReservedLength - 1) / overReservedLength) * overReservedLength;
    }

    void setData(scope const(T)[] values) nothrow pure
    {
        _length = values.length;
        if (_length)
        {
            if (useShortSize)
            {
                _shortData[0.._length] = values[0.._length];
            }
            else
            {
                if (_longData.length < _length)
                    _longData.length = _length;
                _longData[0.._length] = values[0.._length];
            }
        }
    }

    void switchToLongData(const(size_t) additionalLength) nothrow pure
    {
        const capacity = alignAddtionalLength(_length + additionalLength);
        if (_longData.length < capacity)
            _longData.length = capacity;
        if (_length)
            _longData[0.._length] = _shortData[0.._length];
    }

private:
    enum overReservedLength = 1_000u;
    size_t _length;
    T[] _longData;
    T[StaticSize] _shortData = 0;
}

template ShortStringBuffer(T)
if (isSomeChar!T || isIntegral!T)
{
    private enum overheadSize = ShortStringBufferSize!(T, 1u).sizeof;
    alias ShortStringBuffer = ShortStringBufferSize!(T, 256u - overheadSize);
}


// Any below codes are private
private:

nothrow @safe unittest // arrayOfChar
{
    assert(arrayOfChar!char('0', 0) == []);
    assert(arrayOfChar!char('0', 1) == "0");
    assert(arrayOfChar!char('0', 10) == "0000000000");
}

unittest // indexOf
{
    //debug(pham_utl_utl_array) debug writeln(__MODULE__ ~ ".indexOf - begin");
    
    assert("abcxyz".indexOf('c') == 2);
    assert("abcxyz".indexOf('C') == -1);

    assert("abcxyz".indexOf("cx") == 2);
    assert("abcxyz".indexOf("ab") == 0);
    assert("abcxyz".indexOf("yz") == 4);
    assert("abcxyz".indexOf("cx12") == -1);
    assert("abcxyz".indexOf("abcxyz1") == -1);
    assert("".indexOf("") == -1);
    assert("abcxyz".indexOf("") == -1);
    
    //debug(pham_utl_utl_array) debug writeln(__MODULE__ ~ ".indexOf - end");
}

nothrow @safe unittest // inplaceMoveToLeft
{
    auto bytes = cast(ubyte[])"1234567890".dup;
    inplaceMoveToLeft(bytes, 5, 0, 5);
    assert(bytes == "6789067890");
}

unittest // removeAt
{
    // Dynamic array
    auto da = [0, 1, 2, 3, 4, 5];
    removeAt(da, 2);
    assert(da.length == 5);
    assert(da == [0, 1, 3, 4, 5]);
    removeAt(da, 4);
    assert(da.length == 4);
    assert(da == [0, 1, 3, 4]);
    
    // Static array
    int[6] sa = [0, 1, 2, 3, 4, 5];
    size_t sal = 6;
    removeAt(sa, 2, sal);
    assert(sal == 5);
    assert(sa == [0, 1, 3, 4, 5, 0]);
    assert(sa[0..sal] == [0, 1, 3, 4, 5]);
    removeAt(sa, 4, sal);
    assert(sal == 4);
    assert(sa == [0, 1, 3, 4, 0, 0]);
    assert(sa[0..sal] == [0, 1, 3, 4]);
    
    char[6] sca = [0, 1, 2, 3, 4, 5];
    size_t scal = 6;
    removeAt(sca, 2, scal);
    assert(scal == 5);
    assert(sca == [0, 1, 3, 4, 5, char.init]);
    assert(sca[0..scal] == [0, 1, 3, 4, 5]);
    
    wchar[6] swa = [0, 1, 2, 3, 4, 5];
    size_t swal = 6;
    removeAt(swa, 2, swal);
    assert(swal == 5);
    assert(swa == [0, 1, 3, 4, 5, wchar.init]);
    assert(swa[0..swal] == [0, 1, 3, 4, 5]);
}

nothrow @safe unittest // IndexedArray
{
    alias IndexedArray2 = IndexedArray!(int, 2);
    auto a = IndexedArray2(0);

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
    
    a = IndexedArray2(3);
    a.putBack(1);
    a.putBack(2);
    a.putBack(3);
    assert(a.length == 3);
    assert(!a.useStatic);
    assert(a[0] == 1);
    assert(a[1] == 2);
    assert(a[2] == 3);
    
    a = [1, 2, 3];
    assert(a[3..4] == []);
    assert(a[0..2] == [1, 2]);
    assert(a[] == IndexedArray2([1, 2, 3])[]);
    a.fill(10);
    assert(a[0..9] == [10, 10, 10]);
    a.clear();
    assert(a.empty);
    assert(a.length == 0);
}

nothrow unittest // IndexedArray.reverse
{
    auto a = IndexedArray!(int, 3)(0);

    a.clear().put([1, 2], 0);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5], 0);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}

@safe unittest // ShortStringBufferSize
{
    alias TestBuffer5 = ShortStringBufferSize!(char, 5);
    TestBuffer5 s;
    
    assert(s.length == 0);
    s.put('1');
    assert(s.length == 1);
    s.put("234");
    assert(s.length == 4);
    assert(s.toString() == "1234");
    assert(s[] == "1234");
    s.clear();
    assert(s.length == 0);
    s.put("abc");
    assert(s.length == 3);
    assert(s.toString() == "abc");
    assert(s[] == "abc");
    assert(s.left(1) == "a");
    assert(s.left(10) == "abc");
    assert(s.right(2) == "bc");
    assert(s.right(10) == "abc");
    s.put("defghijklmnopqrstuvxywz");
    assert(s.length == 26);
    assert(s.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s[] == "abcdefghijklmnopqrstuvxywz");
    assert(s.left(5) == "abcde");
    assert(s.left(20) == "abcdefghijklmnopqrst");
    assert(s.right(5) == "vxywz");
    assert(s.right(20) == "ghijklmnopqrstuvxywz");

    TestBuffer5 s2;
    s2 ~= s[];
    assert(s2.length == 26);
    assert(s2.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s2[] == "abcdefghijklmnopqrstuvxywz");
    
    s = s2;
    assert(s == s2);
}

@safe unittest // ShortStringBufferSize
{
    alias TestBuffer5 = ShortStringBufferSize!(char, 5);
    TestBuffer5 s;
    
    assert(TestBuffer5(true).length == TestBuffer5(5).length);
    assert(TestBuffer5("123") == "123");
    assert(TestBuffer5("123") != "234");
    assert(TestBuffer5("123456") == "123456");
    assert(TestBuffer5("123456") == TestBuffer5("123456"));
    assert(TestBuffer5("123456") != TestBuffer5("345678"));
    
    // Over short length
    s = "12345678";
    assert(s[] == "12345678");
    assert(s[2] == '3');
    assert(s[10..20] == []);
    s[2] = '?';
    assert(s == "12?45678");
    s.chopTail(1);
    assert(s == "12?4567");
    s.chopFront(1);
    assert(s == "2?4567");
    s.chopTail(2);
    assert(s == "2?45");
    s.chopFront(100);
    assert(s.length == 0);

    s = "123456";
    assert(s.consume() == "123456");
    assert(s.length == 0);

    s = "123456";
    assert(s.consumeUnique() == "123456");
    assert(s.length == 0);

    s = "123456";
    s.dispose();
    assert(s.length == 0);

    s = "123456";
    assert(s.removeFront('1') == "23456");
    assert(s.removeTail('5') == "23456");
    assert(s.removeTail('6') == "2345");
    
    // Within short length
    s = "123";
    assert(s[] == "123");
    assert(s[2] == '3');
    assert(s[7..10] == []);
    s[2] = '?';
    assert(s == "12?");
    s.chopTail(1);
    assert(s == "12");
    s.chopFront(1);
    assert(s == "2");
    s.chopTail(100);
    assert(s.length == 0);    

    s = "123";
    assert(s.consume() == "123");
    assert(s.length == 0);

    s = "123";
    assert(s.consumeUnique() == "123");
    assert(s.length == 0);

    s = "123";
    s.dispose();
    assert(s.length == 0);

    s = "123";
    assert(s.removeFront('1') == "23");
    assert(s.removeTail('2') == "23");
    assert(s.removeTail('3') == "2");
}

nothrow @safe unittest // ShortStringBufferSize.reverse
{
    ShortStringBufferSize!(int, 3) a;

    a.clear().put([1, 2]);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5]);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}
