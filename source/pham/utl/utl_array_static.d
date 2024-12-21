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

module pham.utl.utl_array_static;

import std.traits : isIntegral, isSomeChar;

debug(debug_pham_utl_utl_array_static) import std.stdio : writeln;
import pham.utl.utl_array : arrayClear, arrayDestroy, arrayGrow, arrayShiftLeft, arrayShrink,
    arrayZeroInit, arrayZeroNeeded;
import pham.utl.utl_disposable : DisposingReason;

struct StaticArray(T, ushort StaticSize)
if (StaticSize != 0)
{
    import std.traits : hasElaborateDestructor;

public:
    /**
     * A copy constructor of StaticArray
     */
    this(ref typeof(this) other) nothrow
    {
        if (const otherLength = other.length)
        {
            reserveImpl(otherLength, otherLength, false);
            this._items[0..otherLength] = other._items[0..otherLength];
            this._length = otherLength;
        }
    }

    /**
     * Constructs a StaticArray with a given items.
     * Params:
     *  items = array of elements for appending.
     */
    this()(scope inout(T)[] items) nothrow
    {
        opAssign(items);
    }

    /**
     * Constructs a StaticArray with a given capacity elements for appending.
     * Avoid reallocate memory while populating the StaticArray instant
     * Params:
     *  capacity = reserved number of elements for appending.
     */
    this(size_t capacity) nothrow pure @safe
    {
        if (capacity > StaticSize)
            reserve(capacity, 0, false);
    }

    /**
     * Supports build-in foreach operator
     */
    alias opApply = opApplyImpl!(int delegate(T));
    alias opApply = opApplyImpl!(int delegate(size_t, T));

    int opApplyImpl(CallBack)(scope CallBack callBack)
    if (is(CallBack : int delegate(T)) || is(CallBack : int delegate(ref T))
        || is(CallBack : int delegate(size_t, T)) || is(CallBack : int delegate(size_t, ref T)))
    {
        debug(debug_pham_utl_utl_array_static) if (!__ctfe) debug writeln(__FUNCTION__, "()");

        static if (is(CallBack : int delegate(T)) || is(CallBack : int delegate(ref T)))
        {
            foreach (ref e; _items[0.._length])
            {
                if (const r = callBack(e))
                    return r;
            }
        }
		else
        {
            foreach (i; 0.._length)
            {
                if (const r = callBack(i, _items[i]))
                    return r;
            }
        }

        return 0;
    }

    /**
     * Reset this StaticArray instant from an other StaticArray
     * Params:
     *  rhs = source data from an other StaticArray
     */
    ref typeof(this) opAssign(ref typeof(this) rhs) nothrow return
    {
        clear();
        this._tryExtendBlock = false;
        this._staticItems = rhs._staticItems;
        this._length = rhs._length;
        this._items = rhs._length <= StaticSize ? this._staticItems[] : rhs._items;
        return this;
    }

    /**
     * Reset this StaticArray with a given rhs.
     * Params:
     *  rhs = source array data for copying
     */
    ref typeof(this) opAssign()(scope inout(T)[] rhs) nothrow return
    {
        const newLength = rhs.length;
        if (newLength)
        {
            this.length = newLength;
            this._items[0..newLength] = rhs[0..newLength];
        }
        else
            clear();
        return this;
    }

    /**
     * Append or remove a given item; append operators '~', '+', removing operator '-'
     * Params:
     *  item = an element to be appended or removed
     */
    ref typeof(this) opOpAssign(string op)(auto ref T item) nothrow return
    if (op == "~" || op == "+" || op == "-")
    {
        static if (op == "~" || op == "+")
            put(item);
        else static if (op == "-")
            remove(item);
        else
            static assert(0);
        return this;
    }

    bool opCast(B: bool)() const nothrow
    {
        return !empty;
    }

    alias opDollar = length;

    /**
     * Returns range interface
     */
    inout(T)[] opIndex() inout nothrow return
    {
        debug(debug_pham_utl_utl_array_static) if (!__ctfe) debug writeln(__FUNCTION__, "()");

        return _items[0.._length];
    }

    /**
     * Returns the item at given index
     */
    inout(T) opIndex(size_t index) inout nothrow
    in
    {
        assert(index < length);
    }
    do
    {
        return cast(typeof(return))(_items[index]);
    }

    /**
     * Replace the item at given index
     * Params:
     *  rhs = a source item
     *  index = the index of item to be replaced
     */
    ref typeof(this) opIndexAssign()(auto ref inout(T) rhs, size_t index) nothrow return
    in
    {
        assert(index < length);
    }
    do
    {
        this._items[index] = rhs;
        return this;
    }

    /**
     * Replace the items at beginning index
     * Params:
     *  rhs = a source array of items
     *  beginIndex = the beginning index of items to be replaced
     */
    ref typeof(this) opIndexAssign(scope inout(T)[] rhs, size_t beginIndex) nothrow return
    in
    {
        assert(beginIndex < length);
        assert(beginIndex + rhs.length <= length);
    }
    do
    {
        this._items[beginIndex..beginIndex + rhs.length] = rhs[0..$];
        return this;
    }

    void opPostMove(const ref typeof(this) old) @nogc nothrow @safe
    {
        if (_length <= StaticSize && !staticUsed)
            setStaticReference();
    }

    /**
     * Returns range interface.
     * if beginRange is greater/equal with this StaticArray length, an empty range is returned
     * Params:
     *  beginRange = starting index of element range
     *  endRange = exclusive index of element range
     */
    inout(T)[] opSlice(size_t beginRange, size_t endRange) inout nothrow return
    in
    {
        assert(beginRange < endRange);
    }
    do
    {
        const len = length;
        if (beginRange >= len)
            return [];

        return endRange > len
            ? _items[beginRange..len]
            : _items[beginRange..endRange];
    }

    /**
     * Removes all elements from the StaticArray.
     * This allows the elements of the array to be reused for appending
     */
    ref typeof(this) clear() nothrow return
    {
        if (_length)
        {
            arrayClear(_items[0.._length]);
            _length = 0;
        }
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        if (_length)
            arrayClear!T(_items[0.._length]);
        arrayZeroInit(_staticItems[]);
        _items = [];
        _length = 0;
        _tryExtendBlock = false;
    }

    /**
     * Ensures StaticArray has minimum minLength
     * Params:
     *  minLength = minimum length
     */
    ref typeof(this) expand(size_t minLength) nothrow return
    {
        if (_length < minLength)
            changeLength(minLength);
        return this;
    }

    /**
     * Fills StaticArray with same value, item, starting at beginIndex
     * Params:
     *  item = the value to be used for filling
     *  beginIndex = the from index to the end
     */
    ref typeof(this) fill()(auto ref T item, size_t beginIndex = 0) nothrow return
    in
    {
        assert(beginIndex < length);
    }
    do
    {
        this._items[beginIndex..this._length] = item;
        return this;
    }

    /**
     * Returns the index of item.
     * If item is not found/existed, -1 is returned
     */
    ptrdiff_t indexOf(in T item) @trusted
    {
        import pham.utl.utl_array : indexOfImp = indexOf;

        return length ? indexOfImp(this[], item) : -1;
    }

    /**
     * Returns the pointer at index element
     */
    pragma(inline, true)
    T* ptr(size_t index) nothrow return
    in
    {
        assert(index < length);
    }
    do
    {
        return &_items[index];
    }

    version(none)
    ref typeof(this) put()(size_t index, auto ref inout(T) item) nothrow return
    {
        const reqLength = index + 1;
        if (reqLength > _length)
            reserve(1, 1, true);
        this._items[index] = item;
        if (_length < reqLength)
            _length = reqLength;
        return this;
    }

    version(none)
    ref typeof(this) put()(size_t beginIndex, scope inout(T)[] items) nothrow return
    {
        if (const len = items.length)
        {
            const reqLength = beginIndex + len;
            if (reqLength > this._length)
            {
                const addLen = reqLength - _length;
                reserve(addLen, addLen, true);
            }
            this._items[beginIndex..reqLength] = items[0..len];
            if (_length < reqLength)
                _length = reqLength;
        }
        return this;
    }

    /**
     * Appending the item to this StaticArray
     * Params:
     *  item = a single item to be appended
     */
    ref typeof(this) put()(auto ref inout(T) item) nothrow return
    {
        import core.internal.lifetime : emplaceRef;

        reserve(1, 1, false);
        if (is(T == struct))
        {
            () @trusted
            {
                auto unqualItem = &cast()item;
                emplaceRef(this._items[_length], *unqualItem);
                _length++;
            }();
        }
        else
        {
            this._items[_length++] = item;
        }
        return this;
    }

    /**
     * Appending the items to this StaticArray
     * Params:
     *  items = an array of items to be appended
     */
    ref typeof(this) put()(scope inout(T)[] items) nothrow return
    {
        import core.internal.lifetime : emplaceRef;

        if (const len = items.length)
        {
            reserve(len, len, false);
            if (is(T == struct))
            {
                foreach (i; 0..len)
                {
                    () @trusted
                    {
                        auto unqualItem = &cast()items[i];
                        emplaceRef(this._items[_length], *unqualItem);
                        _length++;
                    }();
                }
            }
            else
            {
                const newLength = _length + len;
                this._items[_length..newLength] = items[0..len];
                _length = newLength;
            }
        }
        return this;
    }

    /**
     * Removes the item from this StaticArray.
     * If the item is not found/existed, a default value is returned
     */
    T remove(in T item)
    {
        return removeAt(indexOf(item));
    }

    /**
     * Removes the item at index from this StaticArray.
     * If index is out of range, a default value is returned
     */
    T removeAt(size_t index) nothrow
    {
        if (index < _length)
        {
            auto result = _items[index];
            arrayShiftLeft!T(_items, _length, index, 1);
            changeLength(_length - 1);
            return result;
        }
        else
            return T.init;
    }

    /**
     * Reverses items inplace using swap, the front item became last and last became first
     */
    ref typeof(this) reverse() @nogc nothrow return @trusted
    {
        import std.algorithm : swapE = swap;

        const len = _length;
        if (len > 1)
        {
            const last = len - 1;
            const steps = len / 2;
            for (size_t i = 0; i < steps; i++)
                swapE(_items[i], _items[last - i]);
        }
        return this;
    }

    /**
     * Exchanges this StaticArray elements with other StaticArray elements
     */
    ref typeof(this) swap(ref typeof(this) other) @nogc nothrow return
    {
        if (this._items.ptr is other._items.ptr)
            return this;

        const thisLength = this._length;
        const otherLength = other._length;
        T[StaticSize] staticTemp = void;

        if (this.staticUsed && other.staticUsed)
        {
            moveTo(this._staticItems, staticTemp, thisLength);

            moveTo(other._staticItems, this._staticItems, otherLength);
            this._length = otherLength;

            moveTo(staticTemp, other._staticItems, thisLength);
            other._length = thisLength;

            return this;
        }

        if (this.staticUsed && !other.staticUsed)
        {
            moveTo(this._staticItems, staticTemp, thisLength);

            this._length = otherLength;
            this._items = other._items;
            this._tryExtendBlock = other._tryExtendBlock;

            moveTo(staticTemp, other._staticItems, thisLength);
            other._length = thisLength;
            other._items = other._staticItems[];
            other._tryExtendBlock = false;

            return this;
        }

        if (!this.staticUsed && other.staticUsed)
        {
            moveTo(other._staticItems, staticTemp, otherLength);

            other._length = thisLength;
            other._items = this._items;
            other._tryExtendBlock = this._tryExtendBlock;

            moveTo(staticTemp, this._staticItems, otherLength);
            this._length = otherLength;
            this._items = this._staticItems[];
            this._tryExtendBlock = false;

            return this;
        }

        // Both big dynamic size
        auto thisItems = this._items;
        auto thisTryExtendBlock = this._tryExtendBlock;

        this._items = other._items;
        this._length = otherLength;
        this._tryExtendBlock = other._tryExtendBlock;

        other._items = thisItems;
        other._length = thisLength;
        other._tryExtendBlock = thisTryExtendBlock;

        return this;
    }

    /**
     * Returns true if this StaticArray has length = 0
     */
    pragma(inline, true)
    @property bool empty() const @nogc nothrow
    {
        return _length == 0;
    }

    /**
     * Returns current length of this StaticArray
     */
    pragma(inline, true)
    @property size_t length() const @nogc nothrow
    {
        return _length;
    }

    /**
     * Set this StaticArray length to newLength
     * Params:
     *  newLength = the length of this StaticArray will have
     */
    @property ref typeof(this) length(size_t newLength) nothrow return @safe
    {
        if (_length != newLength)
            changeLength(newLength);
        return this;
    }

    /**
     * Returns the stack size of this StaticArray type
     */
    pragma(inline, true)
    @property enum size_t staticSize = StaticSize;

    /**
     * Returns true if this StaticArray is using stack storage
     */
    pragma(inline, true)
    @property bool staticUsed() const @nogc nothrow
    {
        return _items.ptr is _staticItems.ptr;
    }

private:
    pragma(inline, false)
    void changeLength(const(size_t) newLength) nothrow
    in
    {
        assert(_length != newLength);
    }
    do
    {
        // Expand
        if (newLength > _length)
            reserve(newLength - _length, 0, true);
        // Shrink
        else
        {
            // Switch to static?
            if (newLength <= StaticSize)
            {
                arrayClear!T(_items[newLength.._length]);

                if (!staticUsed)
                    switchToStatic(newLength);
            }
            else
                arrayShrink!T(_items, _length, _tryExtendBlock, newLength);
        }
        _length = newLength;
    }

    pragma(inline, true)
    void reserve(const(size_t) additionalLength, const(size_t) usingLength, bool zeroInit) nothrow
    {
        debug(debug_pham_utl_utl_array_static) if (!__ctfe) debug writeln(__FUNCTION__, "(_length=", _length,
            ", _items.length=", _items.length, ", additionalLength=", additionalLength, ")");

        if (_length + additionalLength > _items.length)
            reserveImpl(additionalLength, usingLength, zeroInit);
    }

    pragma(inline, false);
    void reserveImpl(const(size_t) additionalLength, const(size_t) usingLength, bool zeroInit) nothrow
    {
        if (_length + additionalLength <= StaticSize)
        {
            if (_items.length == 0)
                setStaticReference();
            return;
        }

        arrayGrow!T(_items, _tryExtendBlock, additionalLength, usingLength, zeroInit);
    }

    void switchToStatic(const(size_t) newLength) nothrow
    {
        moveTo(_items, _staticItems, newLength);
        setStaticReference();
    }

    static void moveTo(T[] sources, ref T[StaticSize] destinations, const(size_t) length) nothrow @trusted
    in
    {
        assert(length <= sources.length);
        assert(length <= destinations.length);
    }
    do
    {
        import core.internal.traits : hasElaborateMove;
        import core.lifetime : moveEmplace;
        import core.stdc.string : memcpy;

        static if (hasElaborateMove!T)
        {
            foreach (i; 0..length)
                moveEmplace(sources[i], destinations[i]);
        }
        else
        {
            memcpy(destinations.ptr, sources.ptr, length * T.sizeof);
        }

        static if (arrayZeroNeeded!T)
            arrayZeroInit!T(sources[0..length]);
    }

    static void moveTo(ref T[StaticSize] sources, ref T[StaticSize] destinations, const(size_t) length) nothrow @trusted
    in
    {
        assert(length <= sources.length);
        assert(length <= destinations.length);
    }
    do
    {
        import core.internal.traits : hasElaborateMove;
        import core.lifetime : moveEmplace;
        import core.stdc.string : memcpy;

        static if (hasElaborateMove!T)
        {
            foreach (i; 0..length)
                moveEmplace(sources[i], destinations[i]);
        }
        else
        {
            memcpy(destinations.ptr, sources.ptr, length * T.sizeof);
        }

        static if (arrayZeroNeeded!T)
            arrayZeroInit!T(sources[]); // Make sure all are zero
    }

    pragma(inline, true)
    void setStaticReference() @nogc nothrow pure @safe
    {
        _items = _staticItems[];
        _tryExtendBlock = false;
    }

private:
    size_t _length;
    T[] _items;
    T[StaticSize] _staticItems;
    bool _tryExtendBlock;
}

struct StaticStringBuffer(T, ushort StaticSize)
if (StaticSize != 0 && (isSomeChar!T || isIntegral!T))
{
@safe:

public:
    /**
     * A copy constructor of StaticStringBuffer
     */
    this(ref typeof(this) rhs) nothrow pure
    {
        if (const rhsLength = rhs.length)
        {
            reserveImpl(rhsLength, rhsLength, false);
            this._items[0..rhsLength] = rhs._items[0..rhsLength];
            this._length = rhsLength;
        }
    }

    /**
     * Constructs a StaticStringBuffer with a given items.
     * Params:
     *  items = array of elements for appending.
     */
    this(scope const(T)[] items) nothrow pure
    {
        opAssign(items);
    }

    /**
     * Constructs a StaticStringBuffer with a given capacity elements for appending.
     * Avoid reallocate memory while populating the StaticStringBuffer instant
     * Params:
     *  capacity = reserved number of elements for appending.
     */
    this(const(size_t) capacity) nothrow pure
    {
        if (capacity > StaticSize)
            reserve(capacity, 0, false);
    }

    /**
     * Reset this StaticStringBuffer instant from an other StaticStringBuffer
     * Params:
     *  rhs = source data from an other StaticStringBuffer
     */
    ref typeof(this) opAssign(ref typeof(this) rhs) nothrow return
    {
        clear();
        this._tryExtendBlock = false;
        this._staticItems = rhs._staticItems;
        this._length = rhs._length;
        this._items = rhs._length <= StaticSize ? this._staticItems[] : rhs._items;
        return this;
    }

    /**
     * Reset this StaticStringBuffer with a given rhs.
     * Params:
     *  rhs = source array data for copying
     */
    ref typeof(this) opAssign(scope const(T)[] rhs) nothrow return
    {
        const newLength = rhs.length;
        this.length = newLength;
        if (newLength)
            this._items[0..newLength] = rhs[0..newLength];
        return this;
    }

    /**
     * Append a given item; append operators '~', '+'
     * Also see 'put'
     * Params:
     *  item = an element to be appended
     */
    ref typeof(this) opOpAssign(string op)(T item) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(item);
    }

    /**
     * Append given array of itema; append operators '~', '+'
     * Also see 'put'
     * Params:
     *  items = array of elements to be appended
     */
    ref typeof(this) opOpAssign(string op)(scope const(T)[] items) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(items);
    }

    /**
     * Applies inplace logical operators of this StaticStringBuffer with rhs elements
     * if the array element type is an integral
     * Params:
     *  rhs = an integral array of elements to applied logical operator with
     */
    static if (isIntegral!T)
    ref typeof(this) opOpAssign(string op)(scope const(T)[] rhs) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    {
        const len = _length > rhs.length ? rhs.length : _length;

        foreach (i; 0..len)
            mixin("this._items[i] " ~ op ~ "= rhs[i];");

        static if (op == "&")
        if (len < _length)
            this._items[len.._length] = 0;

        return this;
    }

    alias opDollar = length;

    /**
     * Returns true if this StaticStringBuffer has same length & content with rhs StaticStringBuffer
     * Params:
     *  rhs = other StaticStringBuffer to be checked for equality
     */
    bool opEquals(const ref typeof(this) rhs) const @nogc nothrow pure
    {
        return this._length == rhs._length && this._items[0.._length] == rhs._items[0..rhs._length];
    }

    /**
     * Returns true if this StaticStringBuffer has same length & content with rhs array
     * Params:
     *  rhs = array of elements to be checked for equality
     */
    bool opEquals(scope const(T)[] rhs) const @nogc nothrow pure
    {
        return this._length == rhs.length && this._items[0.._length] == rhs;
    }

    /**
     * Returns range interface
     */
    inout(T)[] opIndex() inout nothrow pure return
    {
        return _items[0.._length];
    }

    /**
     * Returns the item at given index
     */
    T opIndex(size_t index) const @nogc nothrow pure
    in
    {
        assert(index < length);
    }
    do
    {
        return _items[index];
    }

    /**
     * Replace the item at given index
     * Params:
     *  rhs = a source item
     *  index = the index of item to be replaced
     */
    ref typeof(this) opIndexAssign(T rhs, size_t index) @nogc nothrow return
    in
    {
        assert(index < length);
    }
    do
    {
        this._items[index] = rhs;
        return this;
    }

    /**
     * Replace the items at beginning index
     * Params:
     *  rhs = a source array of items
     *  beginIndex = the beginning index of items to be replaced
     */
    ref typeof(this) opIndexAssign(scope const(T)[] rhs, size_t beginning) nothrow return
    in
    {
        assert(beginning < length);
        assert(beginning + rhs.length <= length);
    }
    do
    {
        this._items[beginning..beginning + rhs.length] = rhs[0..$];
        return this;
    }

    /**
     * Applies inplace logical operators of this StaticStringBuffer with rhs element
     * if the array element type is an integral
     * Params:
     *  rhs = an integral element to applied logical operator with
     *  index = the index of element to be applied to
     */
    static if (isIntegral!T)
    ref typeof(this) opIndexOpAssign(string op)(T rhs, size_t index) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    in
    {
        assert(index < length);
    }
    do
    {
        mixin("this._items[index] " ~ op ~ "= rhs;");
        return this;
    }

    void opPostMove(const ref typeof(this) old) @nogc nothrow @safe
    {
        if (_length <= StaticSize && !staticUsed)
            setStaticReference();
    }

    /**
     * Returns range interface
     * if beginRange is greater/equal with this StaticStringBuffer length, an empty range is returned
     * Params:
     *  beginRange = starting index of element range
     *  endRange = exclusive index of element range
     */
    inout(T)[] opSlice(size_t beginRange, size_t endRange) inout nothrow pure return
    in
    {
        assert(beginRange < endRange);
    }
    do
    {
        if (endRange >= _length)
            return [];
        else
            return endRange > _length
                ? _items[beginRange.._length]
                : _items[beginRange..endRange];
    }

    ref typeof(this) chopFront(size_t chopLength) nothrow pure return
    {
        if (_length > chopLength)
        {
            arrayShiftLeft(_items, _length, 0, chopLength);
            changeLength(_length - chopLength);
            return this;
        }
        else
            return clear();
    }

    ref typeof(this) chopTail(size_t chopLength) nothrow pure return
    {
        const newLength = chopLength < _length ? _length - chopLength : 0;
        if (newLength != _length)
            changeLength(newLength);
        return this;
    }

    /**
     * Removes all elements from the StaticStringBuffer.
     * This allows the elements of the array to be reused for appending
     */
    ref typeof(this) clear() nothrow pure return
    {
        _items = [];
        _length = 0;
        return this;
    }

    T[] consume() nothrow pure
    {
        auto result = _items[0.._length].dup;
        _items = [];
        _length = 0;
        _tryExtendBlock = false;
        return result;
    }

    immutable(T)[] consumeUnique() nothrow pure
    {
        auto result = _items[0.._length].idup;
        _items = [];
        _length = 0;
        _tryExtendBlock = false;
        return result;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        if (_length)
            _items[0.._length] = 0;
        _staticItems[] = 0;
        _items = [];
        _length = 0;
        _tryExtendBlock = false;
    }

    /**
     * Ensures StaticStringBuffer has minimum minLength
     * Params:
     *  minLength = minimum length
     */
    ref typeof(this) expand(size_t minLength) nothrow return
    {
        if (_length < minLength)
            changeLength(minLength);
        return this;
    }

    inout(T)[] left(size_t len) inout nothrow pure return
    {
        return len >= _length
            ? opIndex()
            : opIndex()[0..len];
    }

    /**
     * Appending the item to this StaticStringBuffer
     * Params:
     *  item = a single item to be appended
     */
    ref typeof(this) put(T item) nothrow pure return
    {
        reserve(1, 1, false);
        this._items[_length++] = item;
        return this;
    }

    /**
     * Appending the items to this StaticStringBuffer
     * Params:
     *  items = an array of items to be appended
     */
    ref typeof(this) put(scope const(T)[] items) nothrow pure return
    {
        if (const len = items.length)
        {
            reserve(len, len, false);
            const newLength = this._length + len;
            this._items[this._length..newLength] = items[0..len];
            this._length = newLength;
        }
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

    ref typeof(this) removeFront(const(T) removingItem) nothrow pure return
    {
        while (_length && _items[0] == removingItem)
            chopFront(1);
        return this;
    }

    ref typeof(this) removeTail(const(T) removingItem) nothrow pure return
    {
        while (_length && _items[_length - 1] == removingItem)
            chopTail(1);
        return this;
    }

    /**
     * Reverses items inplace using swap, the front item became last and last became first
     */
    ref typeof(this) reverse() @nogc nothrow pure
    {
        import std.algorithm.mutation : swap;

        const len = length;
        if (len > 1)
        {
            const last = len - 1;
            const steps = len / 2;
            foreach (i; 0..steps)
                swap(_items[i], _items[last - i]);
        }
        return this;
    }

    inout(T)[] right(size_t len) inout nothrow pure return
    {
        return len >= _length
            ? opIndex()
            : opIndex()[_length - len.._length];
    }

    /**
     * Exchanges this StaticStringBuffer elements with other StaticStringBuffer elements
     */
    ref typeof(this) swap(ref typeof(this) other) @nogc nothrow return @trusted
    {
        if (this._items.ptr is other._items.ptr)
            return this;

        const thisLength = this._length;
        const otherLength = other._length;
        T[StaticSize] staticCopy = void;

        if (this.staticUsed && other.staticUsed)
        {
            staticCopy = this._staticItems;

            this._staticItems = other._staticItems;
            this._length = otherLength;

            other._staticItems = staticCopy;
            other._length = thisLength;

            return this;
        }

        if (this.staticUsed && !other.staticUsed)
        {
            staticCopy = this._staticItems;

            this._staticItems[] = 0;
            this._length = otherLength;
            this._items = other._items;
            this._tryExtendBlock = other._tryExtendBlock;

            other._staticItems = staticCopy;
            other._length = thisLength;
            other._items = other._staticItems[];
            other._tryExtendBlock = false;

            return this;
        }

        if (!this.staticUsed && other.staticUsed)
        {
            staticCopy = other._staticItems;

            other._staticItems[] = 0;
            other._length = thisLength;
            other._items = this._items;
            other._tryExtendBlock = this._tryExtendBlock;

            this._staticItems = staticCopy;
            this._length = otherLength;
            this._items = this._staticItems[];
            this._tryExtendBlock = false;

            return this;
        }

        // Both big dynamic size
        auto thisItems = this._items;
        auto thisTryExtendBlock = this._tryExtendBlock;

        this._items = other._items;
        this._length = otherLength;
        this._tryExtendBlock = other._tryExtendBlock;

        other._items = thisItems;
        other._length = thisLength;
        other._tryExtendBlock = thisTryExtendBlock;

        return this;
    }

    static if (isSomeChar!T)
    immutable(T)[] toString() const nothrow pure
    {
        return _length != 0
            ? _items[0.._length].idup
            : [];
    }

    static if (isSomeChar!T)
    ref Writer toString(Writer)(return ref Writer sink) const pure
    {
        if (_length)
            put(sink, opIndex());
        return sink;
    }

    /**
     * Returns true if this StaticStringBuffer has length = 0
     */
    pragma(inline, true)
    @property bool empty() const @nogc nothrow pure
    {
        return _length == 0;
    }

    /**
     * Returns current length of this StaticStringBuffer
     */
    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure
    {
        return _length;
    }

    /**
     * Set this StaticStringBuffer length to newLength
     * Params:
     *  newLength = the length of this StaticStringBuffer will have
     */
    @property size_t length(size_t newLength) nothrow
    {
        if (_length != newLength)
            changeLength(newLength);
        return _length;
    }

    /**
     * Returns the stack size of this StaticStringBuffer type
     */
    pragma(inline, true)
    @property enum size_t staticSize = StaticSize;

    /**
     * Returns true if this StaticStringBuffer is using stack storage
     */
    pragma(inline, true)
    @property bool staticUsed() const @nogc nothrow
    {
        return _items.ptr is _staticItems.ptr;
    }

private:
    pragma(inline, false);
    void changeLength(const(size_t) newLength) nothrow
    in
    {
        assert(_length != newLength);
    }
    do
    {
        // Expand
        if (newLength > _length)
            reserve(newLength - _length, 0, true);
        // Shrink
        else
        {
            // Switch to static?
            if (newLength <= StaticSize)
            {
                if (!staticUsed)
                    switchToStatic(newLength);
            }
            else
                arrayShrink!T(_items, _length, _tryExtendBlock, newLength);
        }
        _length = newLength;
    }

    pragma(inline, true)
    void reserve(const(size_t) additionalLength, const(size_t) usingLength, bool zeroInit) nothrow
    {
        debug(debug_pham_utl_utl_array_static) if (!__ctfe) debug writeln(__FUNCTION__, "(_length=", _length, ", _items.length=", _items.length, ", additionalLength=", additionalLength, ")");

        if (_length + additionalLength > _items.length)
            reserveImpl(additionalLength, usingLength, zeroInit);
    }

    pragma(inline, false);
    void reserveImpl(const(size_t) additionalLength, const(size_t) usingLength, bool zeroInit) nothrow
    {
        if (_length + additionalLength <= StaticSize)
        {
            if (_items.length == 0)
                setStaticReference();
            return;
        }

        arrayGrow!T(_items, _tryExtendBlock, additionalLength, usingLength, zeroInit);
    }

    void switchToStatic(const(size_t) newLength) nothrow
    {
        _staticItems[0..newLength] = _items[0..newLength];
        setStaticReference();
    }

    pragma(inline, true)
    void setStaticReference() @nogc nothrow pure @safe
    {
        _items = _staticItems[];
        _tryExtendBlock = false;
    }

private:
    size_t _length;
    T[] _items;
    T[StaticSize] _staticItems = 0;
    bool _tryExtendBlock;
}

template ShortStringBuffer(T)
if (isSomeChar!T || isIntegral!T)
{
    private enum overheadSize = StaticStringBuffer!(T, 1u).sizeof;
    alias ShortStringBuffer = StaticStringBuffer!(T, 256u - overheadSize);
}


nothrow @safe unittest // StaticArray
{
    alias IndexedArray2 = StaticArray!(int, 2);
    auto a = IndexedArray2(0);

    // Check initial state
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);

    // Append element
    a.put(1);
    assert(!a.empty);
    assert(a.length == 1);
    assert(a.indexOf(1) == 0);
    assert(a[0] == 1);

    // Append second element
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
    assert(a[].dup == [1, 2]);

    // Set new element at index (which is at the end for this case)
    a.expand(3)[2] = 3;
    assert(a.length == 3);
    assert(a.indexOf(3) == 2);
    assert(a[2] == 3);

    // Replace element at index
    a[1] = -1;
    assert(a.length == 3);
    assert(a.indexOf(-1) == 1);
    assert(a[1] == -1);

    // Check duplicate
    assert(a[].dup == [1, -1, 3]);

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

    a.expand(1)[0] = 1;
    assert(!a.empty);
    assert(a.length == 1);

    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    assert(a.remove(1) == 0);
    assert(a.removeAt(1) == 0);

    a.put(1);
    a.fill(10);
    assert(a.length == 1);
    assert(a[0] == 10);

    a.clear();
    a.put(1);
    a.put(2);
    a.put(3);
    assert(a.length == 3);
    assert(a[0] == 1);
    assert(a[1] == 2);
    assert(a[2] == 3);

    a = [1, 2, 3];
    assert(a[3..4] == []);
    assert(a[0..2] == [1, 2]);
    assert(a[] == [1, 2, 3]);
    a.fill(10);
    assert(a[0..9] == [10, 10, 10]);

    a.clear();
    assert(a.empty);
    assert(a.length == 0);
    foreach (i; 0..2000)
        a.put(i);
    assert(a.length == 2000);
    assert(a[0] == 0);
    assert(a[a.length - 1] == 1999);
}

nothrow unittest // StaticArray.reverse
{
    auto a = StaticArray!(int, 3)(0);

    a.clear().put([1, 2]);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5]);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}

@safe unittest // StaticStringBuffer
{
    alias TestBuffer5 = StaticStringBuffer!(char, 5);
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

    s = s2[];
    assert(s == s2);
}

@safe unittest // StaticStringBuffer
{
    alias TestBuffer5 = StaticStringBuffer!(char, 5);
    TestBuffer5 s, s2;

    assert(s.opAssign("123") == "123");
    assert(s.opAssign("123") != "234");
    assert(s.opAssign("123456") == "123456");
    assert(s.opAssign("123456") == s2.opAssign("123456"));
    assert(s.opAssign("123456") != s2.opAssign("345678"));

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

nothrow @safe unittest // StaticStringBuffer.reverse
{
    StaticStringBuffer!(int, 3) a;

    a.clear().put([1, 2]);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5]);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}
