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
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe;
    
    @property DisposingReason lastDisposingReason() const @nogc nothrow @safe;
}

struct LastDisposingReason
{
public:
    pragma(inline, true)
    bool canDispose(const(DisposingReason) disposingReason) const @nogc nothrow @safe
    {
        return this.value < DisposingReason.dispose && disposingReason >= this.value;
    }

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
    final override void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        if (!_lastDisposingReason.canDispose(disposingReason))
            return;

        _lastDisposingReason.value = disposingReason;
        doDispose(disposingReason);
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
    abstract void doDispose(const(DisposingReason) disposingReason) nothrow @safe;

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
        ~this()
        {
            dispose(DisposingReason.destructor);
        }

    protected:
        override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
        {
            stateCounter++;
            stateReason = disposingReason;
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
