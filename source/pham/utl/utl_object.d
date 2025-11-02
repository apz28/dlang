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

module pham.utl.utl_object;

import std.math : isPowerOf2;
import std.traits : fullyQualifiedName;

static import pham.utl.utl_text;
static import pham.utl.utl_version;


/**
 * Roundups and returns value, `n`, to the power of 2 modular value, `powerOf2AlignmentSize`
 * Params:
 *   n = value to be roundup
 *   powerOf2AlignmentSize = power of 2 modular value
 * Returns:
 *   roundup value
 */
pragma(inline, true)
size_t alignRoundup(const(size_t) n, const(size_t) powerOf2AlignmentSize) @nogc nothrow pure @safe
in
{
    assert(powerOf2AlignmentSize > 1);
    assert(isPowerOf2(powerOf2AlignmentSize));
}
do
{
    return (n + powerOf2AlignmentSize - 1) & ~(powerOf2AlignmentSize - 1);
}

/**
 * Convert object to equivalent value in pointer type
 */
pragma(inline, true)
void* asPointer(const(Object) object) @nogc nothrow pure @safe
{
    return cast(void*)object;
}

/**
 * Convert object to equivalent value in integral type
 */
pragma(inline, true)
size_t asSizeT(const(Object) object) @nogc nothrow pure @safe
{
    return cast(size_t)(cast(void*)object);
}

/**
 * Convert pointer to equivalent value in integral type
 */
pragma(inline, true)
size_t asSizeT(const(void*) pointer) @nogc nothrow pure @safe
{
    return cast(size_t)pointer;
}

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.className))
alias className = pham.utl.utl_text.className;

/**
 * Checks and returns `value` within `min` and `max` inclusive
 * Params:
 *   value = a value to be checked
 *   min = inclusive minimum value
 *   max = inclusive maximum value
 * Returns:
 *   `min` if `value` is less than `min`
 *   `max` if `value` is greater than `max`
 *   otherwise `value`
 */
pragma(inline, true)
T limitRangeValue(T)(T value, T min, T max) nothrow pure @safe
{
    static if (__traits(compiles, T.init < T.init && T.init > T.init))
    {
        return value < min ? min : (value > max ? max : value);
    }
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
}

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.pad))
alias pad = pham.utl.utl_text.pad;

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.padRight))
alias padRight = pham.utl.utl_text.padRight;

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.shortClassName))
alias shortClassName = pham.utl.utl_text.shortClassName;

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.shortTypeName))
alias shortTypeName = pham.utl.utl_text.shortTypeName;

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.simpleFloatFmt))
alias simpleFloatFmt = pham.utl.utl_text.simpleFloatFmt;

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.simpleIntegerFmt))
alias simpleIntegerFmt = pham.utl.utl_text.simpleIntegerFmt;

/**
 * Initialize parameter `v` if `v` is null in thread safe manner using pass-in 'initiate' function
 * Params:
 *   v = variable to be initialized to object T if it is null
 *   initiate = a function that returns the newly created object as of T
 * Returns:
 *   parameter `v`
 */
T singleton(T)(ref T v, T function() nothrow @safe initiate) nothrow @trusted //@trusted=cast(T)null
if (is(T == class))
{
    import core.atomic : cas;
    import std.traits : hasElaborateDestructor;

    if (v is null)
    {
        auto n = initiate();
        if (!cas(&v, cast(T)null, n))
        {
            static if (hasElaborateDestructor!T)
                n.__xdtor();
        }
    }

    return v;
}

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_text.stringOfChar))
alias stringOfChar = pham.utl.utl_text.stringOfChar;

/**
 * Boxer type to have indicator that its' value has been set or not-set regardless of if the setting value
 * is a default one
 */
struct InitializedValue(T)
{
    import std.traits : isArray, isAssociativeArray, isPointer;

nothrow @safe:

public:
    this(T value)
    {
        this._value = value;
        this._inited = true;
    }

    ref typeof(this) opAssign(T)(T value) return
    {
        this._value = value;
        this._inited = true;
        return this;
    }

    C opCast(C: bool)() const @nogc pure
    {
        if (_inited)
        {
            static if (isPointer!T || is(T == class))
                return _value !is null;
            else static if (isArray!T || isAssociativeArray!T)
                return _value.length != 0;
            else
                return true;
        }
        else
            return false;
    }

    /**
     * Resets this instance to initial state
     */
    ref typeof(this) reset() return
    {
        if (_inited)
        {
            _value = T.init;
            _inited = false;
        }
        return this;
    }


    /**
     * Indicates if value had been set or not-set
     */
    @property bool inited() const @nogc pure
    {
        return _inited;
    }

    /**
     * Returns current holding value
     */
    @property inout(T) value() inout pure
    {
        return _value;
    }

    alias this = value;

private:
    T _value;
    bool _inited;
}

/**
 * Wrapper for Mutex to handle locking & unlocking automatically using
 * Resource Acquisition Is Initialization or RAII technique
 */
struct RAIIMutex
{
    import core.atomic : atomicFetchAdd, atomicFetchSub, atomicLoad;
    import core.sync.mutex : Mutex;

@nogc nothrow @safe:

public:
    @disable this();
    @disable this(this);
    @disable void opAssign(typeof(this));

    /**
     * Get holding of `mutex` and call `lock` function
     */
    this(Mutex mutex)
    {
        this._lockedCounter = 0;
        this._mutex = mutex;
        lock();
    }

    /**
     * Release holding of `mutex` and call `unlock` function if is `isLocked`
     */
    ~this()
    {
        if (isLocked)
            unlock();
        _mutex = null;
    }

    /**
     * Increase `lockedCounter` and call `mutex.lock_nothrow` if `lockedCounter` = 1
     * You must call its corresponding `unlock` to release the mutex
     */
    void lock()
    {
        if (_mutex is null)
        {
            assert(_lockedCounter == 0);
            return;
        }

        if (atomicFetchAdd(_lockedCounter, 1) == 0)
            _mutex.lock_nothrow();
    }

    /**
     * Decrease `lockedCounter` and call `mutex.unlock_nothrow` if `lockedCounter` = 0
     */
    void unlock()
    {
        if (_mutex is null)
        {
            assert(_lockedCounter == 0);
            return;
        }

        if (atomicFetchSub(_lockedCounter, 1) == 1)
            _mutex.unlock_nothrow();
    }

    /**
     * Returns true if `lockedCounter` is greater than zero
     */
    pragma(inline, true)
    @property bool isLocked() const pure
    {
        return atomicLoad(_lockedCounter) > 0;
    }

    /**
     * Returns counter of function `lock` had been called
     */
    @property int lockedCounter() const pure
    {
        return atomicLoad(_lockedCounter);
    }

private:
    Mutex _mutex;
    int _lockedCounter;
}

deprecated("please use " ~ fullyQualifiedName!(pham.utl.utl_version.VersionString))
alias VersionString = pham.utl.utl_version.VersionString;


// Any below codes are private
private:

version(unittest)
{
    class TestClassName
    {
        string testFN() nothrow @safe
        {
            return __FUNCTION__;
        }
    }

    class TestClassTemplate(T) {}

    struct TestStructName
    {
        string testFN() nothrow @safe
        {
            return __FUNCTION__;
        }
    }

    string testFN() nothrow @safe
    {
        return __FUNCTION__;
    }
}

unittest // alignRoundup
{
    assert(alignRoundup(0, 4) == 0);
    assert(alignRoundup(1, 4) == 4);
    assert(alignRoundup(4, 4) == 4);

    assert(alignRoundup(1, 16) == 16);
    assert(alignRoundup(15, 16) == 16);
    assert(alignRoundup(16, 16) == 16);
}

nothrow @safe unittest // limitRangeValue
{
    assert(limitRangeValue(0, 0, 101) == 0);
    assert(limitRangeValue(101, 0, 101) == 101);
    assert(limitRangeValue(1, 0, 101) == 1);
    assert(limitRangeValue(-1, 0, 101) == 0);
    assert(limitRangeValue(102, 0, 101) == 101);
}

unittest // singleton
{
    static class A {}

    static A createA() pure @safe
    {
        return new A;
    }

    A a;
    assert(a is null);
    assert(singleton(a, &createA) !is null);
}

unittest // InitializedValue
{
    InitializedValue!int n;
    assert(!n);
    assert(!n.inited);

    n = 0;
    assert(n);
    assert(n.inited);
    assert(n == 0);

    InitializedValue!TestClassName c;
    assert(!c);
    assert(!c.inited);

    c = null;
    assert(!c);
    assert(c.inited);

    c = new TestClassName();
    assert(c);
    assert(c.inited);
    assert(c !is null);
}

unittest // RAIIMutex
{
    import core.sync.mutex : Mutex;

    auto mutex = new Mutex();

    {
        auto locker = RAIIMutex(mutex);
        assert(locker.isLocked);
        assert(locker.lockedCounter == 1);

        locker.lock();
        assert(locker.isLocked);
        assert(locker.lockedCounter == 2);

        locker.unlock();
        assert(locker.isLocked);
        assert(locker.lockedCounter == 1);
    }

    destroy(mutex);
}

nothrow @safe unittest // asPointer
{
    Object object = new Object();
    assert(object.asPointer is cast(void*)object);
}

nothrow @safe unittest // asSizeT
{
    Object object = new Object();
    assert(object.asSizeT() != 0);

    void* pointer = object.asPointer();
    assert(pointer.asSizeT() == object.asSizeT());
}
