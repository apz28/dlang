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

import std.traits : hasElaborateDestructor, hasIndirections,
    isDynamicArray, isIntegral, isSomeChar, isStaticArray;

debug(debug_pham_utl_utl_array) import std.stdio : writeln;

@safe:

//private version = customArrayGCFree;

C[] arrayOfChar(C)(C c, size_t count) nothrow pure
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

/**
 * Calculates an efficient growth scheme based on the current length
 * of data, and the minimum requested length;
 * will assert if overflow
 *
 * Params:
 *   currentLength = current length/capacity
 *   additionalLength = additional count
 *   sizeOfT = size of T in bytes
 */
pragma(inline, true)
size_t arrayCalcCapacity(const(size_t) currentLength, const(size_t) additionalLength, const(size_t) sizeOfT) @nogc nothrow pure @safe
in
{
    assert(sizeOfT > 0);
}
do
{
    const increment = currentLength > 1_000
        ? (currentLength / 2)
        : (currentLength != 0 ? currentLength : (sizeOfT == 1 ? 32 : (sizeOfT == 2 ? 16 : 8)));
    const result = currentLength + (increment > additionalLength ? increment : additionalLength);

    if (result <= currentLength)
        assert(0, "The allocation size would exceed the available pointer range");

    return result;
}

/**
 * Calculates a malloc size for an array length & element size;
 * will assert if overflow
 *
 * Params:
 *   length = length of array
 *   sizeOfT = size of T in bytes
 */
pragma(inline, true)
size_t arrayMallocSize(const(size_t) length, const(size_t) sizeOfT) @nogc nothrow pure @safe
in
{
    assert(sizeOfT > 0);
}
do
{
    import core.checkedint : mulu;

    bool overflow;
    const result = mulu(length, sizeOfT, overflow);

    if (overflow)
        assert(0, "The allocation size would exceed the available pointer range");

    return result;
}

void arrayClear(T)(T[] array)
{
    static if (hasElaborateDestructor!T)
        arrayDestroy!T(array, true);
    else
        arrayZeroInit!T(array);
}

void arrayDestroy(T)(T[] array, bool zeroInit)
if (hasElaborateDestructor!T)
{
    foreach (ref e; array)
        e.__xdtor();

    if (zeroInit)
        arrayZeroInit!T(array);
}

void arrayFree(T)(ref T[] array) nothrow pure @trusted
{
    import core.memory : GC;

    if (!__ctfe && array.ptr !is null)
        GC.free(array.ptr);

    array = [];
}

pragma(inline, false)
void arrayGrow(T)(ref T[] array, ref bool tryExtendBlock, const(size_t) additionalLength, const(size_t) usingLength, bool zeroInit) nothrow pure @trusted
in
{
    assert(usingLength <= additionalLength);
}
do
{
    import core.memory : GC;
    import core.stdc.string : memcpy, memset;
    import std.traits : hasIndirections;

    const currentLength = array.length;
    const allocCapacity = arrayCalcCapacity(currentLength, additionalLength, T.sizeof);

    static auto finalAttribute() @nogc nothrow pure @safe
    {
        static if (is(T == struct) && __traits(hasMember, T, "xdtor"))
            return GC.BlkAttr.FINALIZE;
        else
            return GC.BlkAttr.NONE;
    }

    static auto scanAttribute() @nogc nothrow pure @safe
    {
        static if (is(T == void) || hasIndirections!T)
            return GC.BlkAttr.NONE;
        else
            return GC.BlkAttr.NO_SCAN;
    }

    if (__ctfe)
    {
        static if (__traits(compiles, { T[] t; t.reserve(1); t.length = 1; }))
        {
            array.reserve(allocCapacity);
            array.length = currentLength + additionalLength;
        }
        else
        {
            // Avoid restriction of @disable this()
            foreach (i; 0..additionalLength)
                array ~= T.init;
        }
        tryExtendBlock = false;
    }
    else
    {
        // Clear out previous garbage to avoid runtime pinned memory?
        static if (arrayZeroNeeded!T)
            zeroInit = true;

        const allocSize = arrayMallocSize(allocCapacity, T.sizeof);

        // Try extending the current block
        if (tryExtendBlock)
        {
            // Extend worked?
            if (const extendSize = GC.extend(array.ptr, additionalLength * T.sizeof, (allocCapacity - currentLength) * T.sizeof))
            {
                debug(debug_pham_utl_utl_array) debug writeln(__FUNCTION__, "(currentLength=", currentLength, ", allocCapacity=", allocCapacity
                    , ", allocSize=", allocSize, ", extendSize=", extendSize, ", T.sizeof=", T.sizeof, ")");

                if (zeroInit)
                {
                    const endSize = (currentLength + usingLength) * T.sizeof;
                    if (extendSize > endSize)
                        memset(array.ptr + endSize, 0, extendSize - endSize);
                }

                array = (cast(T*)array.ptr)[0..extendSize / T.sizeof];
                return;
            }
        }

        auto bi = GC.qalloc(allocSize, finalAttribute | scanAttribute);
        debug(debug_pham_utl_utl_array) debug writeln(__FUNCTION__, "(currentLength=", currentLength, ", allocCapacity=", allocCapacity
            , ", allocSize=", allocSize, ", bi.size=", bi.size, ", T.sizeof=", T.sizeof, ")");

        // Clear out previous garbage to avoid runtime pinned memory?
        if (zeroInit)
        {
            const endSize = (currentLength + usingLength) * T.sizeof;
            if (bi.size > endSize)
                memset(bi.base + endSize, 0, bi.size - endSize);
        }

        // Copy existing data to new array
        if (currentLength)
        {
            memcpy(bi.base, array.ptr, currentLength * T.sizeof);

            // Avoid double destructor
            static if (arrayZeroNeeded!T)
                arrayZeroInit!T(array[0..currentLength]);
        }

        version(customArrayGCFree) auto oldArray = array;
        array = (cast(T*)bi.base)[0..bi.size / T.sizeof];
        tryExtendBlock = true;
        version(customArrayGCFree) arrayFree!T(oldArray);
    }
}

pragma(inline, false)
void arrayShiftLeft(T)(ref T[] array, const(size_t) currentLength, const(size_t) beginIndex, const(size_t) shiftLength) @trusted
in
{
    assert(currentLength <= array.length);
    assert(beginIndex + shiftLength <= currentLength);
    assert(shiftLength != 0);
}
do
{
    import core.stdc.string : memmove;
    import std.traits : hasElaborateDestructor, Unqual;

    alias UT = Unqual!T;

    const afterLength = currentLength - beginIndex - shiftLength;

    static if (is(T == immutable) || is(T == const) || !is(T == struct))
    {
        static if (hasElaborateDestructor!T)
            arrayDestroy!T(array[beginIndex..beginIndex + shiftLength], false);

        if (afterLength)
        {
            auto p = cast(UT*)(array.ptr + beginIndex);
            memmove(p, p + shiftLength, afterLength * T.sizeof);

            static if (__traits(hasPostblit, T))
            {
                foreach (ref e; array[beginIndex..beginIndex + shiftLength])
                    e.__xpostblit();
            }
        }
    }
    else
    {
        if (afterLength)
        {
            foreach (i; 0..afterLength)
            {
                const b = beginIndex + i;
                array[b] = array[b + shiftLength];
            }

            static if (hasElaborateDestructor!T)
            {
                const b = beginIndex + shiftLength;
                arrayDestroy!T(array[b..b + afterLength], false);
            }
        }
        else
        {
            static if (hasElaborateDestructor!T)
                arrayDestroy!T(array[beginIndex..beginIndex + shiftLength], false);
        }
    }

    arrayZeroInit!T(array[currentLength-shiftLength..currentLength]);
}

pragma(inline, false)
void arrayShrink(T)(ref T[] array, ref size_t currentLength, ref bool tryExtendBlock, const(size_t) newLength) @trusted
in
{
    assert(array.length >= currentLength);
    assert(currentLength > 0);
    assert(newLength < currentLength);
}
do
{
    import core.memory : GC;
    import core.stdc.string : memcpy, memset;
    import std.traits : hasIndirections;

    if (__ctfe)
    {
        array = array[0..newLength];
        currentLength = newLength;
        tryExtendBlock = false;
    }
    else
    {
        auto blockAttribute() @nogc nothrow pure @safe
        {
            static if (hasIndirections!T || is(T == void))
                return GC.BlkAttr.NONE;
            else
                return GC.BlkAttr.NO_SCAN;
        }

        static if (arrayZeroNeeded!T)
            arrayClear!T(array[newLength..currentLength]);

        if (newLength >= 8 && newLength < currentLength / 2)
        {
            const allocSize = arrayMallocSize(newLength, T.sizeof);
            auto bi = GC.qalloc(allocSize, blockAttribute);
            static if (arrayZeroNeeded!T)
            {
                if (bi.size > allocSize)
                    memset(bi.base + allocSize, 0, bi.size - allocSize);
            }
            memcpy(bi.base, array.ptr, allocSize);
            static if (arrayZeroNeeded!T)
                arrayZeroInit(array[0..newLength]);

            version(customArrayGCFree) auto oldArray = array;
            currentLength = newLength;
            tryExtendBlock = true;
            version(customArrayGCFree) arrayFree!T(oldArray);

            return;
        }

        currentLength = newLength;
    }
}

void arrayZeroInit(T)(scope T[] array) @nogc nothrow pure @trusted
{
    import core.stdc.string : memset;

    if (__ctfe)
    {
        auto ptr = cast(void*)array.ptr;
        auto byteLength = array.length * T.sizeof;
        while (byteLength >= size_t.sizeof)
        {
            *cast(size_t*)ptr = size_t(0);
            ptr += T.sizeof;
            byteLength -= T.sizeof;
        }
        while (byteLength)
        {
            *cast(ubyte*)ptr = ubyte(0);
            byteLength--;
        }
    }
    else
        memset(array.ptr, 0, array.length * T.sizeof);
}

enum bool arrayZeroNeeded(T) = hasElaborateDestructor!T || hasIndirections!T;

ptrdiff_t indexOf(scope const(void*)[] items, scope const(void*) item) @nogc nothrow pure
{
    foreach (i, e; items)
    {
        if (e is item)
            return i;
    }
    return -1;
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

void removeAt(T)(ref T array, ref size_t length, size_t beginIndex,
    size_t removeLength = 1) nothrow
if (isStaticArray!T)
in
{
    assert(length != 0 && length <= array.length);
    assert(beginIndex + removeLength <= length);
    assert(removeLength != 0);
}
do
{
    auto arrayDyn = array[0..length];
    arrayShiftLeft(arrayDyn, length, beginIndex, removeLength);
    length -= removeLength;
}

void removeAt(T)(ref T array, size_t beginIndex,
    size_t removeLength = 1) nothrow
if (isDynamicArray!T)
in
{
    assert(array.length != 0);
    assert(beginIndex + removeLength <= array.length);
    assert(removeLength != 0);
}
do
{
    const length = array.length;
    arrayShiftLeft(array, length, beginIndex, removeLength);
    array.length = length - removeLength;
}


// Any below codes are private
private:

nothrow @safe unittest // arrayOfChar
{
    assert(arrayOfChar!char('0', 0) == []);
    assert(arrayOfChar!char('0', 1) == "0");
    assert(arrayOfChar!char('0', 10) == "0000000000");
}

unittest // indexOf.sub
{
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

unittest // indexOf.pointer
{
    auto item = cast(void*)(new Object());
    auto items = [item];
    assert(items.indexOf(item) == 0);
    assert(items.indexOf(null) == -1);
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
    da.removeAt(2);
    assert(da.length == 5);
    assert(da == [0, 1, 3, 4, 5]);
    da.removeAt(4);
    assert(da.length == 4);
    assert(da == [0, 1, 3, 4]);

    // Static array
    int[6] sa = [0, 1, 2, 3, 4, 5];
    size_t sal = sa.length;
    sa.removeAt(sal, 2);
    assert(sal == 5);
    assert(sa == [0, 1, 3, 4, 5, 0]);
    assert(sa[0..sal] == [0, 1, 3, 4, 5]);
    sa.removeAt(sal, 4);
    assert(sal == 4);
    assert(sa == [0, 1, 3, 4, 0, 0]);
    assert(sa[0..sal] == [0, 1, 3, 4]);

    char[6] sca = [0, 1, 2, 3, 4, 5];
    size_t scal = sca.length;
    sca.removeAt(scal, 2);
    assert(scal == 5);
    assert(sca == [0, 1, 3, 4, 5, 0]);
    assert(sca[0..scal] == [0, 1, 3, 4, 5]);

    wchar[6] swa = [0, 1, 2, 3, 4, 5];
    size_t swal = swa.length;
    swa.removeAt(swal, 2);
    assert(swal == 5);
    assert(swa == [0, 1, 3, 4, 5, 0]);
    assert(swa[0..swal] == [0, 1, 3, 4, 5]);
}
