/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_timer;

import core.atomic : atomicExchange, atomicFetchAdd, atomicFetchSub, atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
public import core.time : Duration, dur;

debug(debug_pham_utl_utl_timer) import std.stdio : writeln;
import pham.utl.utl_object : RAIIMutex;
version(Posix)
{
    import pham.utl.utl_timer_engine_posix;
}
else version(Windows)
{
    import pham.utl.utl_timer_engine_windows;
}
else
{
    static assert(0, "Unsupported system for " ~ __MODULE__);
}

alias TimerDelegate = void delegate(TimerEvent event) @safe;
alias TimerFunction = void function(TimerEvent event) @safe;

struct TimerEvent
{
public:
    this(string name, Duration interval, TimerDelegate eventHandler) nothrow pure @safe
    in
    {
        assert(eventHandler !is null);
    }
    do
    {
        this._name = name;
        this._interval = interval;
        this._dlgHandler = eventHandler;
        this._doHandler = &doNotifyDlgHandler;
        this._fctHandler = null;
    }

    this(string name, Duration interval, TimerFunction eventHandler) nothrow pure @safe
    in
    {
        assert(eventHandler !is null);
    }
    do
    {
        this._name = name;
        this._interval = interval;
        this._fctHandler = eventHandler;
        this._doHandler = &doNotifyFctHandler;
        this._dlgHandler = null;
    }

    /**
     * How many times the event being called
     */
    @property size_t counter() const nothrow pure @safe
    {
        return _counter;
    }

    /**
     * The interval between elapsed events passed in constructor
     */
    @property Duration interval() const nothrow pure @safe
    {
        return _interval;
    }

    /**
     * Name of the event passed in constructor
     */
    @property string name() const nothrow pure @safe
    {
        return _name;
    }

public:
    /**
     * User defined variables to be used by caller
     */
    Object context;
    size_t tag;

private:
    void notify() nothrow @safe
    {
        debug(debug_pham_utl_utl_timer) debug writeln("TimerEvent.notify(name=", name, ", counter=", counter, ")");

        assert(_doHandler !is null);

        try
        {
            _doHandler(this);
        }
        catch (Exception)
        {}
    }

    static void doNotifyDlgHandler(ref TimerEvent event) @safe
    {
        assert(event._dlgHandler !is null);
        event._dlgHandler(event);
    }

    static void doNotifyFctHandler(ref TimerEvent event) @safe
    {
        assert(event._fctHandler !is null);
        event._fctHandler(event);
    }

    static void doNotifyNothingHandler(ref TimerEvent event) @safe
    {}

private:
    alias DoNotify = void function(ref TimerEvent event) @safe;
    DoNotify _doHandler;
    TimerDelegate _dlgHandler;
    TimerFunction _fctHandler;
    string _name;
    Duration _interval;
    size_t _counter;
}

class Timer
{
public:
    this(Duration resolutionInterval = dur!"msecs"(10)) nothrow @safe
    {
        this._resolutionInterval = resolutionInterval >= minResolutionInterval ? resolutionInterval : minResolutionInterval;
        this._mutex = new Mutex();
        this._engine = TimerEngine(&notifyElapsed, null);
    }

    ~this() nothrow @trusted
    {
        _engine.stop(true);

        if (_mutex !is null)
        {
            _mutex.destroy();
            _mutex = null;
        }
    }

    /**
     * Add an event to timer to be notified
     */
    final void addEvent(TimerEvent event) nothrow @safe
    {
        if (atomicLoad(_disabled) == 0)
            startEngine();

        auto raiiMutex = RAIIMutex(_mutex);
        _notifiers ~= TimerNotifier(event);
    }

    /**
     * Remove all events with matching name (case sensitive) from timer
     */
    final size_t removeEvent(scope const(char)[] name) nothrow @safe
    {
        import std.algorithm : remove;

        size_t result;
        auto raiiMutex = RAIIMutex(_mutex);
        auto i = _notifiers.length;
        while (i != 0)
        {
            i--;
            if (_notifiers[i].event.name == name)
            {
                _notifiers = _notifiers.remove(i);
                result++;
            }
        }
        return result;
    }

    /**
     * Controls whether the timer generates events periodically.
     * Use 'enabled' to enable or disable the timer. If 'enabled' is true, the timer responds normally.
     * If 'enabled' is false, the timer does not generate events.
     * The default is true.
     */
    @property final bool enabled() const @nogc nothrow @safe
    {
        return atomicLoad(_disabled) == 0;
    }

    @property final typeof(this) enabled(bool state) nothrow @safe
    {
        if (state)
        {
            startEngine();
        }
        else
        {
            if (atomicExchange(&_disabled, 3) != 3)
            {
                _engine.stop(false);
                atomicStore(_disabled, 1);
            }
        }

        return this;
    }

    @property final Duration resolutionInterval() const @nogc nothrow pure @safe
    {
        return _resolutionInterval;
    }

package(pham.utl):
    final void notifyElapsed(void* data) nothrow @safe
    {
        const canNotifyElapsed = atomicFetchAdd(_inNotifyElapsed, 1) == 0;
        scope (exit)
            atomicFetchSub(_inNotifyElapsed, 1);

        if (!canNotifyElapsed)
            return;

        debug(debug_pham_utl_utl_timer) debug writeln("Timer.notifyElapsed(canProcess=", canProcess(), ")");

        if (!canProcess())
            return;

        auto elapsedEvents = getElapsedEvents();
        if (!canProcess())
            return;

        foreach (ref elapsedEvent; elapsedEvents)
        {
            elapsedEvent.notify();
            if (!canProcess())
                return;
        }
    }
    
    final void resetNotifierElapsed() nothrow @safe
    {
        debug(debug_pham_utl_utl_timer) debug writeln("Timer.resetNotifierElapseds()");

        auto raiiMutex = RAIIMutex(_mutex);
        foreach (ref notifier; _notifiers)
            notifier.elapsed = Duration.zero;
    }
    
protected:
    final bool canProcess() const nothrow @safe
    {
        return enabled && _engine.isRunning;
    }

    final TimerEvent[] getElapsedEvents() nothrow @safe
    {
        debug(debug_pham_utl_utl_timer) debug writeln("Timer.getElapsedEvents()");

        auto raiiMutex = RAIIMutex(_mutex);

        if (_notifyEvents.length < _notifiers.length)
            _notifyEvents.length = _notifiers.length;

        size_t resultCount;
        foreach (ref notifier; _notifiers)
        {
            notifier.elapsed += _resolutionInterval;

            debug(debug_pham_utl_utl_timer) debug writeln("Timer.getElapsedEvents(elapsed=", notifier.elapsed,
                ", event.name=", notifier.event.name, ", event.interval=", notifier.event.interval, ")");

            if (notifier.elapsed >= notifier.event.interval)
                _notifyEvents[resultCount++] = notifier.nextElapsed();
        }

        debug(debug_pham_utl_utl_timer) debug writeln("Timer.getElapsedEvents(resultCount=", resultCount, ")");

        return _notifyEvents[0..resultCount];
    }

    final void startEngine() nothrow @safe
    {
        if (atomicExchange(&_disabled, 2) != 2)
        {
            if (!_engine.isRunning)
            {
                resetNotifierElapsed();
                _engine.start(_resolutionInterval);
            }
            atomicStore(_disabled, _engine.isRunning ? 0 : 1);
        }
    }

package(pham.utl):
    TimerEngine _engine;

private:
    Mutex _mutex;
    TimerEvent[] _notifyEvents;
    TimerNotifier[] _notifiers;
    Duration _resolutionInterval;
    size_t _disabled, _inNotifyElapsed;
}

package(pham.utl)
struct TimerNotifier
{
nothrow @safe:

public:
    this(TimerEvent event)
    {
        this.event = event;
    }

    TimerEvent nextElapsed()
    {
        elapsed = Duration.zero;
        event._counter++;
        return event;
    }

public:
    Duration elapsed;
    TimerEvent event;
}


private:

unittest
{
    import core.thread.osthread : Thread;
    import std.stdio : writeln;

    size_t eventDelegateCounter;
    void eventDelegate(TimerEvent event) @safe
    {
        //debug writeln("eventDelegate(event.name=", event.name, ")");
        assert(event.counter != 0);
        assert(event.interval > Duration.zero);
        assert(event.name == "1");

        eventDelegateCounter++;
    }

    static __gshared size_t eventFunctionCounter;
    static void eventFunction(TimerEvent event) @trusted
    {
        //debug writeln("eventFunction(event.name=", event.name, ")");
        assert(event.counter != 0);
        assert(event.interval > Duration.zero);
        assert(event.name == "2");

        eventFunctionCounter++;
    }

    auto timer = new Timer();

    eventDelegateCounter = 0;
    eventFunctionCounter = 0;

    timer.addEvent(TimerEvent("1", dur!"msecs"(200), &eventDelegate));
    timer.addEvent(TimerEvent("2", dur!"msecs"(200), &eventFunction));

    //debug writeln("Thread.sleep1");
    Thread.sleep(dur!"msecs"(1_000));

    //debug writeln("timer.removeEvent");
    const r = timer.removeEvent("2");
    assert(r == 1);

    //debug writeln("Thread.sleep2");
    Thread.sleep(dur!"msecs"(1_000));

    //debug writeln("timer.disable");
    timer.enabled = false;

    //debug writeln("timer.terminate");
    timer.destroy();

    assert(eventDelegateCounter != 0);
    assert(eventFunctionCounter != 0);
}
