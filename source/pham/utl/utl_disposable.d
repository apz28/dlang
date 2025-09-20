/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_disposable;

public import pham.utl.utl_result : ResultCode;

/**
 * Reason to call dispose
 */
enum DisposingReason : ubyte
{
    none,
    other,
    dispose,
    destructor,
}

pragma(inline, true)
bool isDisposing(const(DisposingReason) disposingReason) @nogc nothrow pure @safe
{
    return disposingReason >= DisposingReason.dispose;
}

/**
 * Generic interface to implement disposable class
 * Sample object implementation of this interface, `DisposableObject`
 */
interface IDisposable
{
    /**
     * The actual function to dispose object
     * Params:
     *   disposingReason = indicate a reason to dispose
     */
    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe;

    @property DisposingReason lastDisposingReason() const @nogc nothrow @safe;
}

struct LastDisposingReason
{
@nogc nothrow @safe:

public:
    ref typeof(this) opAssign(const(DisposingReason) disposingReason) return
    {
        this.value = disposingReason;
        return this;
    }

    pragma(inline, true)
    bool canDispose(const(DisposingReason) disposingReason) const
    {
        return canDispose(disposingReason, this.value);
    }

    pragma(inline, true)
    static bool canDispose(const(DisposingReason) disposingReason, const(DisposingReason) lastDisposingReason) pure
    {
       return disposingReason != DisposingReason.none && disposingReason > lastDisposingReason;
    }

public:
    DisposingReason value;
}

/**
 * An abstract class to implement `IDisposable` interface
 */
abstract class DisposableObject : IDisposable
{
public:
    /**
     * Implement IDisposable.dispose
     * Will do nothing if called more than one
     */
    final override int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        // Check to avoid multiple dispose calls
        if (!_lastDisposingReason.canDispose(disposingReason))
            return ResultCode.ok;
        
        _lastDisposingReason.value = disposingReason;
        return doDispose(disposingReason);
    }

    pragma(inline, true)
    @property final override DisposingReason lastDisposingReason() const @nogc nothrow @safe
    {
        return _lastDisposingReason.value;
    }

protected:
    /**
     * Abstract function of this class to perform disposing logic
     */
    abstract int doDispose(const(DisposingReason) disposingReason) nothrow @safe;

private:
    LastDisposingReason _lastDisposingReason;
}


private:

unittest // DisposableObject
{
    static int stateCounter;
    static DisposingReason stateReason;

    static class TestDisposableObject : DisposableObject
    {
    public:
        ~this() nothrow
        {
            doDispose(DisposingReason.destructor);
        }

    protected:
        final override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
        {
            stateCounter++;
            stateReason = disposingReason;
            return ResultCode.ok;
        }
    }

    auto c = new TestDisposableObject();
    c.dispose();
    assert(stateCounter == 1);
    assert(stateReason == DisposingReason.dispose);
    c.dispose(); // Do nothing if call second time (or subsequece dispose calls)
    assert(stateCounter == 1);
    assert(stateReason == DisposingReason.dispose);

    stateCounter = 0;
    stateReason = DisposingReason.none;
    c = new TestDisposableObject();
    destroy(c);
    assert(stateCounter == 1);
    assert(stateReason == DisposingReason.destructor);
}
