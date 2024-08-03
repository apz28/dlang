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

version(Windows)
{
    version = WindowsCreateTimerQueue;
    //version = WindowsSetTimer; // Application must have a message loop for it to work
}

alias TimerDelegate = void delegate(TimerEvent event);
alias TimerFunction = void function(TimerEvent event);

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
    void notify() nothrow
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

    static void doNotifyDlgHandler(ref TimerEvent event)
    {
        assert(event._dlgHandler !is null);
        event._dlgHandler(event);
    }

    static void doNotifyFctHandler(ref TimerEvent event)
    {
        assert(event._fctHandler !is null);
        event._fctHandler(event);
    }

    static void doNotifyNothingHandler(ref TimerEvent event)
    {}

private:
    alias DoNotify = void function(ref TimerEvent event);
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
        version(WindowsSetTimer)
            // 10=https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-settimer
            enum minResolutionInterval = dur!"msecs"(10);
        else
            enum minResolutionInterval = dur!"msecs"(1);

        this._resolutionInterval = resolutionInterval >= minResolutionInterval ? resolutionInterval : minResolutionInterval;
        this._mutex = new Mutex();
        this._engine = TimerEngine(this);
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

    final void resetNotifierElapsed() nothrow @safe
    {
        debug(debug_pham_utl_utl_timer) debug writeln("Timer.resetNotifierElapseds()");

        auto raiiMutex = RAIIMutex(_mutex);
        foreach (ref notifier; _notifiers)
            notifier.elapsed = Duration.zero;
    }

    final void notifyElapsed() nothrow
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

    final void startEngine() nothrow @safe
    {
        if (atomicExchange(&_disabled, 2) != 2)
        {
            if (!_engine.isRunning)
                _engine.start();
            atomicStore(_disabled, _engine.isRunning ? 0 : 1);
        }
    }

private:
    Mutex _mutex;
    TimerEngine _engine;
    TimerEvent[] _notifyEvents;
    TimerNotifier[] _notifiers;
    Duration _resolutionInterval;
    size_t _disabled, _inNotifyElapsed;
}


private:

struct TimerEngine
{
    import core.thread.osthread : Thread;
    version(WindowsSetTimer)
    {
        import core.sys.windows.basetsd : UINT_PTR;
        import core.sys.windows.windef : DWORD, HWND, UINT;
        import core.sys.windows.winuser : KillTimer, SetTimer;
        pragma(lib, "user32");
    }
    else version(WindowsCreateTimerQueue)
    {
        import core.sys.windows.basetsd : HANDLE;
        import core.sys.windows.winbase : CreateTimerQueue, CreateTimerQueueTimer, DeleteTimerQueue, DeleteTimerQueueTimer;
        import core.sys.windows.winnt : BOOLEAN, PVOID;
    }

public:
    this(Timer timer) nothrow @safe
    {
        this.timer = timer;
    }

    void start() nothrow @trusted
    {
        debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.start()");

        atomicStore(state, State.start);

        timer.resetNotifierElapsed();

        version(WindowsSetTimer)
        {
            auto tid = SetTimer(null, cast(UINT_PTR)(cast(void*)timer), cast(uint)timer.resolutionInterval.total!"msecs", &timerRun);
            if (tid == UINT_PTR.init)
            {
                atomicStore(state, State.initial);
                return;
            }
            
            atomicStore(timerId, tid);
        }
        else version(WindowsCreateTimerQueue)
        {
            auto hQueueTemp = CreateTimerQueue();
            if (hQueueTemp is null)
            {
                atomicStore(state, State.initial);
                return;
            }
            
            if (!CreateTimerQueueTimer(&hTimer, hQueueTemp, &timerRun, cast(void*)timer, 0, cast(uint)timer.resolutionInterval.total!"msecs", 0))
            {
                DeleteTimerQueue(hQueueTemp);
                atomicStore(state, State.initial);
                return;
            }
            
            atomicStore(hQueue, hQueueTemp);
        }
        else
        {
            auto t =  new Thread(&timerRun).start();
            atomicStore(thread, t);
            Thread.yield();
        }
    }

    void stop(const(bool) destroying) nothrow @trusted
    {
        debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.stop()");

        atomicStore(state, State.stop1);

        version(WindowsSetTimer)
        {
            auto tid = atomicExchange(&timerId, UINT_PTR.init);
            if (tid != UINT_PTR.init)
                KillTimer(null, tid);
        }
        else version(WindowsCreateTimerQueue)
        {
            auto th = atomicExchange(&hTimer, null);
            if (th !is null)
                DeleteTimerQueueTimer(hQueue, th, null);

            th = atomicExchange(&hQueue, null);
            if (th !is null)
                DeleteTimerQueue(th);
        }
        else
        {
            auto tth = atomicExchange(&thread, null);
            if (tth !is null)
            {
                Thread.yield();

                enum waitUnit = dur!"msecs"(1_000);
                auto waitFor = waitUnit * 5;
                while (waitFor > Duration.zero && atomicLoad(state) == State.stop1)
                {
                    Thread.sleep(waitUnit);
                    waitFor -= waitUnit;
                }

                tth.destroy();
            }
        }

        atomicStore(state, State.initial);
    }

    @property bool isRunning() const @nogc nothrow @safe
    {
        version(WindowsSetTimer)
            return atomicLoad(state) == State.start || atomicLoad(timerId) != UINT_PTR.init;
        else version(WindowsCreateTimerQueue)
            return atomicLoad(state) == State.start || atomicLoad(hQueue) !is null;
        else
            return atomicLoad(state) == State.start || atomicLoad(thread) !is null;
    }

private:
    enum State : size_t
    {
        initial,
        start,
        stop1,
        stop2,
    }

    State state;
    Timer timer;

private:
    void notifyElapsedIf() nothrow
    {
        if (atomicLoad(state) == State.start)
            timer.notifyElapsed();
    }

    version(WindowsSetTimer)
    {
        UINT_PTR timerId;

        extern (Windows) static void timerRun(HWND, UINT, UINT_PTR ptr, DWORD) nothrow
        {
            debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.timerRun(begin)");

            assert(ptr != 0);

            auto timer = cast(Timer)(cast(void*)ptr);
            timer._engine.notifyElapsedIf();
            timer._engine.setCompleteStopIf();

            debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.timerRun(end)");
        }
    }
    else version(WindowsCreateTimerQueue)
    {
        HANDLE hQueue;
        HANDLE hTimer;

        extern (Windows) static void timerRun(PVOID lpParam, BOOLEAN) nothrow
        {
            debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.timerRun(begin)");

            assert(lpParam !is null);

            auto timer = cast(Timer)lpParam;
            timer._engine.notifyElapsedIf();
            timer._engine.setCompleteStopIf();

            debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.timerRun(end)");
        }
    }
    else
    {
        Thread thread;

        void timerRun() nothrow
        {
            debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.timerRun(begin)");

            while (atomicLoad(state) == State.start)
            {
                Thread.sleep(timer.resolutionInterval);
                notifyElapsedIf();
            }

            setCompleteStopIf();

            debug(debug_pham_utl_utl_timer) debug writeln("TimerEngine.timerRun(end)");
        }
    }

    void setCompleteStopIf() nothrow
    {
        if (atomicLoad(state) == State.stop1)
            atomicStore(state, State.stop2);
    }
}

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

unittest
{
    import core.thread.osthread : Thread;
    import std.stdio : writeln;

    size_t eventDelegateCounter;
    void eventDelegate(TimerEvent event)
    {
        //debug writeln("eventDelegate(event.name=", event.name, ")");
        assert(event.counter != 0);
        assert(event.interval > Duration.zero);
        assert(event.name == "1");

        eventDelegateCounter++;
    }

    static __gshared size_t eventFunctionCounter;
    static void eventFunction(TimerEvent event)
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
