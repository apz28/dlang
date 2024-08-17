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

import std.range.primitives : ElementEncodingType, ElementType,
    isInputRange, isOutputRange;
import std.traits : hasElaborateAssign, hasIndirections,
    isAssignable, isCopyable, isDynamicArray, isIntegral, isMutable, isSomeChar, isSomeString, isStaticArray,
    lvalueOf, Unqual;

debug(debug_pham_utl_utl_array) import std.stdio : writeln;
import pham.utl.utl_disposable : DisposingReason;

@safe:


C[] arrayOfChar(C)(C c, size_t count) nothrow
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

ptrdiff_t indexOf(T)(scope const(T)[] items, const(T) item) nothrow @trusted
{
    //scope (failure) assert(0, "Assume nothrow failed");

    foreach (i; 0..items.length)
    {
        if (items[i] == item)
            return i;
    }
    return -1;
}

ptrdiff_t indexOf(T)(scope const(T)[] item, scope const(T)[] subItem) @nogc nothrow pure
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

void inplaceMoveToLeft(ref ubyte[] data, size_t fromIndex, size_t toIndex, size_t nBytes) nothrow pure @trusted
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

void removeAt(T)(ref T array, size_t index) nothrow pure
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

void removeAt(T)(ref T array, size_t index, ref size_t length) nothrow pure
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

struct Appender(A)
if (isDynamicArray!A)
{
    import std.exception : enforce;
    import std.format.spec : FormatSpec, singleSpec;
    import std.range.primitives : empty, front, popFront;

    alias T = ElementEncodingType!A;
    alias UT = Unqual!T;

public:
    /**
     * Constructs an `Appender` with a given array. Note that this does not copy the
     * data. If the array has a larger capacity as determined by `value.capacity`,
     * it will be used by the appender. After initializing an appender on an array,
     * appending to the original array will reallocate.
     */
    this(A value) @trusted
    {
        this._data = new Data;
        this._data.value = cast(UT[])value; //trusted
        this._data.capacity = value.length;
        this._data.tryExtendBlock = false;
    }

    /**
     * Constructs an `Appender` with a given capacity elements for appending.
     */
    this(size_t capacity)
    {
        this._data = null;
        this.reserve(capacity);
    }
    
    /**
     * Appends to the managed array.
     * See_Also: $(LREF Appender.put)
     */
    alias opOpAssign(string op : "~") = put;

    alias opDollar = length;

    /**
     * Returns: The managed array item at index.
     */
    static if (!is(T == void) && isCopyable!T)
    inout(T) opIndex(size_t index) inout nothrow @trusted
    in
    {
        assert(_data && _data.length != 0);
    }
    do
    {
        // @trusted operation: casting Unqual!T to inout(T)
        return cast(typeof(return))(_data.value[index]);
    }

    /**
     * Returns: The managed array.
     */
    inout(T)[] opSlice() inout nothrow @trusted
    {
        // @trusted operation: casting Unqual!T[] to inout(T)[]
        return cast(typeof(return))(_data ? _data.value : null);
    }

    /**
     * Clears the managed array. This allows the elements of the array to be reused
     * for appending.
     */
    ref typeof(this) clear() nothrow pure return
    {
        if (_data)
        {
            if (__ctfe)
                _data = null;
            else
            {
                _data.value = _data.value[0..0];

                // only allow overwriting data on non-immutable and non-const data
                static if (!isMutable!T)
                {
                    _data.capacity = 0;
                    _data.tryExtendBlock = false;
                }
            }
        }

        return this;
    }

    /**
     * Appends `item` to the managed array. Performs encoding for
     * `char` types if `A` is a differently typed `char` array.
     *
     * Params:
     *     item = the single item to append
     */
    ref typeof(this) put(U)(U item) return
    if (canPutItem!U)
    {
        static if (isSomeChar!T && isSomeChar!U && T.sizeof < U.sizeof)
        {
            // may throwable operation: std.utf.encode
            // must do some transcoding around here
            import std.utf : encode;

            UT[T.sizeof == 1 ? 4 : 2] encoded;
            const len = encode(encoded, item);
            put(encoded[0..len]);
        }
        else
        {
            import core.lifetime : emplace;

            const len = ensureAddable(1);
            auto bigData = (() @trusted => _data.value.ptr[0..len + 1])();
            auto unqualItem = (() @trusted => &cast()item)();
            (() @trusted => emplace(&bigData[len], *unqualItem))();

            // We do this at the end, in case of exceptions
            _data.value = bigData;
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
        static if (!(isSomeChar!T && isSomeChar!(ElementType!R) && !is(immutable R == immutable T[]))
            && is(typeof(items.length) == size_t))
        {
            const itemsLength = items.length;
            
            if (itemsLength == 0)
                return this;
                
            // optimization -- if this type is something other than a string,
            // and we are adding exactly one element, call the version for one
            // element.
            static if (!isSomeChar!T)
            {
                if (itemsLength == 1)
                {
                    put(items.front);
                    return this;
                }
            }
            
            // make sure we have enough space, then add the items
            auto bigDataFun(const(size_t) extra)
            {
                const len = ensureAddable(extra);
                return (() @trusted => _data.value.ptr[0..len + extra])();
            }

            auto bigData = bigDataFun(itemsLength);
            const newLen = bigData.length;
            const len = this.length;

            static if (is(typeof(_data.value[] = items[]))
                && !hasElaborateAssign!UT
                && isAssignable!(UT, ElementEncodingType!R))
            {
                bigData[len..newLen] = items[];
            }
            else
            {
                import core.internal.lifetime : emplaceRef;

                foreach (ref it; bigData[len..newLen])
                {
                    emplaceRef!T(it, items.front);
                    items.popFront();
                }
            }

            // We do this at the end, in case of exceptions
            _data.value = bigData;
        }
        else static if (isSomeChar!T && isSomeChar!(ElementType!R)
            && !is(immutable T == immutable ElementType!R))
        {
            // need to decode and encode
            import std.utf : decodeFront;

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
            ensureAddable(newCapacity - currentCapacity);
        return this;
    }

    /**
     * Shrinks the managed array to the given length.
     *
     * Throws: `Exception` if newLength is greater than the managed array length.
     */
    ref typeof(this) shrinkTo(size_t newLength) pure return
    {
        if (newLength == 0)
            return clear();

        const currentLength = this.length;
        enforce(newLength <= currentLength, "Attempting to shrink Appender with newLength > length");

        if (_data && newLength != currentLength)
        {
            static if (isMutable!T)
                _data.value = _data.value[0..newLength];
            else
            {
                if (__ctfe)
                    _data.value = _data.value[0..newLength].dup;
                else
                    _data.value = _data.value[0..newLength];

                // only allow overwriting data on non-immutable and non-const data
                _data.capacity = newLength;
                _data.tryExtendBlock = false;
            }
        }

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
        auto spec = singleSpec("%s");

        // different reserve lengths because each element in a
        // non-string-like array uses two extra characters for `, `.
        static if (isSomeString!A)
        {
            const cap = this.length + 25;
        }
        else
        {
            // Multiplying by three is a very conservative estimate of
            // length, as it assumes each element is only one char
            const cap = (this.length * 3) + 25;
        }
        auto buffer = Appender!string(cap);
        return toString(buffer, spec).data;
    }

    /// ditto
    ref Writer toString(Writer)(return ref Writer writer, scope const ref FormatSpec!char fmt) const
    if (isOutputRange!(Writer, char))
    {
        import std.format.write : formatValue;
        import std.range.primitives : formatPut = put;

        formatPut(writer, Unqual!(typeof(this)).stringof);
        formatPut(writer, '(');
        formatValue(writer, data, fmt);
        formatPut(writer, ')');

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
    @property inout(T)[] data() inout nothrow @trusted
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
    import core.checkedint : mulu;
    import core.memory : GC;
    import core.stdc.string : memcpy;

    template blockAttribute(U)
    {
        static if (hasIndirections!(U) || is(U == void))
        {
            enum blockAttribute = 0;
        }
        else
        {
            enum blockAttribute = GC.BlkAttr.NO_SCAN;
        }
    }

    template canPutItem(U)
    {
        enum bool canPutItem =
            is(Unqual!U : UT)
            || (isSomeChar!U && isSomeChar!T);
    }

    template canPutConstRange(R)
    {
        enum bool canPutConstRange =
            isInputRange!(Unqual!R)
            && canPutItem!(ElementType!R)
            && !isInputRange!R;
    }

    template canPutRange(R)
    {
        enum bool canPutRange =
            isInputRange!R
            && canPutItem!(ElementType!R);
    }

    /**
     * Calculates an efficient growth scheme based on the old capacity
     * of data, and the minimum requested capacity.
     *
     * Params:
     *   TSizeOf = The size of T in bytes
     *   curLen = The current length
     *   reqLen = The length as requested by the user
     */
    static size_t calCapacity(const(size_t) sizeOfT, const(size_t) curCapacity, const(size_t) reqLen) @nogc nothrow pure @safe
    {
        import core.bitop : bsr;
        import std.algorithm.comparison : max, min;

        if (curCapacity == 0)
            return max(reqLen, 8);

        // limit to doubling the length, we don't want to grow too much
        const ulong mult = min(100 + 1000UL / (bsr(curCapacity * sizeOfT) + 1), 200);
        const sugCapacity = cast(size_t)((curCapacity * mult + 99) / 100);
        return max(reqLen, sugCapacity);
    }

    /**
     * ensure we can add nElems elements, resizing as necessary
     * Returns the current length
     */
    pragma(inline, true)
    size_t ensureAddable(const(size_t) nElems)
    in
    {
        assert(nElems > 0);
    }
    do
    {
        if (!_data)
            _data = new Data;

        const len = _data.length;
        const reqLen = len + nElems;
        return _data.capacity >= reqLen ? len : ensureAddableImpl(nElems, reqLen);
    }
    
    size_t ensureAddableImpl(const(size_t) nElems, const(size_t) reqLen)
    in
    {
        assert(nElems > 0);
        assert(reqLen >= nElems);
        assert(_data !is null);
    }
    do
    {        
        const len = _data.length;
        
        // need to increase capacity
        if (__ctfe)
        {
            static if (__traits(compiles, new UT[1]))
            {
                _data.value.length = reqLen;
            }
            else
            {
                // avoid restriction of @disable this()
                const cap = _data.capacity;
                _data.value = _data.value[0..cap];
                foreach (i; cap..reqLen)
                    _data.value ~= UT.init;
            }
            _data.value = _data.value[0..len];
            _data.capacity = reqLen;
            return _data.length;
        }
        else
        {
            // Time to reallocate.
            // We need to almost duplicate what's in druntime, except we
            // have better access to the capacity field.
            const newLen = calCapacity(T.sizeof, _data.capacity, reqLen);

            // first, try extending the current block
            if (_data.tryExtendBlock)
            {
                const u = (() @trusted => GC.extend(_data.value.ptr, nElems * T.sizeof, (newLen - len) * T.sizeof))();
                if (u)
                {
                    // extend worked, update the capacity
                    _data.capacity = u / T.sizeof;
                    return _data.value.length;
                }
            }

            // didn't work, must reallocate
            bool overflow;
            const nBytes = mulu(newLen, T.sizeof, overflow);
            if (overflow)
                assert(0, "the reallocation would exceed the available pointer range");

            auto bi = (() @trusted => GC.qalloc(nBytes, blockAttribute!T))();
            _data.capacity = bi.size / T.sizeof;

            if (len)
                () @trusted { memcpy(bi.base, _data.value.ptr, len * T.sizeof); }();
            _data.value = (() @trusted => (cast(UT*)bi.base)[0..len])();
            _data.tryExtendBlock = true;
            return _data.length;
            // leave the old data, for safety reasons
        }
    }

    struct Data
    {
        size_t capacity;
        UT[] value;
        bool tryExtendBlock;

        pragma(inline, true)
        @property size_t length() const nothrow @safe
        {
            return value.length;
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
    static assert(!isStaticArray!A || __traits(isRef, value), "Cannot create Appender from an rvalue static array");

    return Appender!(E[])(value);
}

///dito
Appender!A appender(A)(size_t capacity = 0)
if (isDynamicArray!A)
{
    return Appender!A(capacity);
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

    alias opApply = opApplyImpl!(int delegate(T));
    alias opApply = opApplyImpl!(int delegate(size_t, T));

    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(T)) || is(CallBack : int delegate(size_t, T)))
    {
        debug(debug_pham_utl_utl_array) if (!__ctfe) debug writeln(__FUNCTION__, "()");

        auto list = useStatic ? _staticItems[0..length] : _dynamicItems;
        static if (is(CallBack : int delegate(T)))
        {
            foreach (ref e; list)
            {
                const r = callBack(e);
                if (r)
                    return r;
            }
        }
		else
        {
            foreach (i; 0..list.length)
            {
                const r = callBack(i, list[i]);
                if (r)
                    return r;
            }
        }
        return 0;
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

    size_t opDollar() const @nogc nothrow
    {
        return length;
    }

    bool opCast(B: bool)() const nothrow
    {
        return !empty;
    }

    /** Returns range interface
    */
    inout(T)[] opIndex() inout nothrow return
    {
        debug(debug_pham_utl_utl_array) if (!__ctfe) debug writeln(__FUNCTION__, "()");

        return useStatic ? _staticItems[0..length] : _dynamicItems;
    }

    /** Returns range interface
    */
    T opIndex(size_t index) nothrow
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
    ref typeof(this) opIndexOpAssign(string op)(T item, const(size_t) index) @nogc nothrow
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
    inout(T)[] opSlice(const(size_t) beginIndex, const(size_t) endIndex) inout nothrow return
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

    ref typeof(this) clear(const(size_t) capacity = 0) nothrow return
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
    T* ptr(const(size_t) index) nothrow return
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
        return i >= 0 ? doRemove(i) : T.init;
    }

    T removeAt(const(size_t) index) nothrow
    {
        return index < length ? doRemove(index) : T.init;
    }

    ref typeof(this) reverse() @nogc nothrow
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

    pragma(inline, true)
    @property bool empty() const @nogc nothrow
    {
        return length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc nothrow
    {
        return useStatic ? _staticLength : _dynamicItems.length;
    }

    @property size_t length(const(size_t) newLength) nothrow
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

    pragma(inline, true)
    @property bool useStatic() const @nogc nothrow
    {
        assert(_dynamicItems.ptr !is null || useStatic(_staticLength));

        return _dynamicItems.ptr is null;
    }

    pragma(inline, true)
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
        debug(debug_pham_utl_utl_array) debug writeln(__FUNCTION__, "()");

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

    void switchToDynamicItems(const(size_t) newLength, bool mustSet) nothrow @trusted
    {
        debug(debug_pham_utl_utl_array) debug writeln(__FUNCTION__, "()");

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
        this(shortLength ? StaticSize : cast(ushort)0);
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

    pragma(inline, true)
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

    pragma(inline, true)
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
    //debug(debug_pham_utl_utl_array) debug writeln(__MODULE__ ~ ".indexOf - begin");

    assert("abcxyz".indexOf('c') == 2);
    assert("abcxyz".indexOf('C') == -1);

    assert("abcxyz".indexOf("cx") == 2);
    assert("abcxyz".indexOf("ab") == 0);
    assert("abcxyz".indexOf("yz") == 4);
    assert("abcxyz".indexOf("cx12") == -1);
    assert("abcxyz".indexOf("abcxyz1") == -1);
    assert("".indexOf("") == -1);
    assert("abcxyz".indexOf("") == -1);

    //debug(debug_pham_utl_utl_array) debug writeln(__MODULE__ ~ ".indexOf - end");
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
    assert("%s".format(app) == "Appender!(int[])(%s)".format([1,2,3]));

    Appender!string app2;
    auto spec = singleSpec("%s");
    app.toString(app2, spec);
    assert(app2[] == "Appender!(int[])([1, 2, 3])");

    Appender!string app3;
    spec = singleSpec("%(%04d, %)");
    app.toString(app3, spec);
    assert(app3[] == "Appender!(int[])(0001, 0002, 0003)");
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
        alias fun this;
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

    auto str = "ウェブサイト";
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

    struct N
    {
        int payload;
        alias payload this;
    }
    w.put(N(1));
    w.put([N(2)]);

    struct S(T)
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
    struct S1
    {
    }
    struct S2
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

pure @system unittest // Appender
{
    import std.range;

    struct S2
    {
        void opAssign(S2){}
    }
    auto au2 = Appender!(const(S2)[])();
    auto sc2 = const(S2)();
    au2.put(sc2.repeat().take(10));
}

nothrow pure @system unittest // Appender
{
    struct S
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

    //{auto app = Appender!immARR(mut);}                //Worked. Will cease to work. Creates warning.
    //static assert(!is(typeof(Appender!immARR(mut)))); //Worked. Will cease to work. Uncomment me after full deprecation.
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
        alias i this;
    }
    static struct S //static
    {
        int[5] i;
        alias i this;
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
