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

module pham.utl.timer;

import core.sync.mutex : Mutex;
import core.thread.osthread : Thread;
public import core.time : Duration, dur;

import pham.utl.object : RAIIMutex;

alias TimerDelegate = void delegate(TimerEvent event);
alias TimerFunction = void function(TimerEvent event);

struct TimerEvent
{
public:
    this(string name, in Duration interval, TimerDelegate eventHandler) nothrow pure @safe
    in
    {
        assert(eventHandler !is null);
    }
    do
    {
        this._name = name;
        this._interval = interval;
        this._dlgHandler = eventHandler;
        this._fctHandler = null;
    }

    this(string name, in Duration interval, TimerFunction eventHandler) nothrow pure @safe
    in
    {
        assert(eventHandler !is null);
    }
    do
    {
        this._name = name;
        this._interval = interval;
        this._fctHandler = eventHandler;
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
    void notify()
    {
        try
        {
            if (_dlgHandler)
                _dlgHandler(this);
            else if (_fctHandler)
                _fctHandler(this);
            else
                assert(0);
        }
        catch (Exception)
        {}
    }

private:
    TimerDelegate _dlgHandler;
    TimerFunction _fctHandler;
    string _name;
    Duration _interval;
    size_t _counter;
}

class TimerThread : Thread
{
public:
    this(in Duration resolutionInterval) @safe
    {
        this._disabled = 0;
        this._resolutionInterval = resolutionInterval;
        super(&run);
    }

    /**
     * Add an event to timer to be notified
     */
    final void addEvent(TimerEvent event)
    {
        auto raiiMutex = RAIIMutex(_mutex);
        _notifiers ~= TimerNotifier(event);
    }

    /**
     * Temporarily disable timer
     */
    final void disable() nothrow @safe
    {
        auto raiiMutex = RAIIMutex(_mutex);
        if (++_disabled == 1)
        {
            foreach (ref notifier; _notifiers)
                notifier.elapsed = Duration.zero;
        }
    }

    /**
     * Re-enable the timer after disabled
     * The number of enable calls must match with disable calls in order to enable the timer
     * Returns:
     *  The number of disabled counter. The timer is enabled when it is zero
     */
    final size_t enable() nothrow @safe
    in
    {
        assert(_disabled != 0);
    }
    do
    {
        auto raiiMutex = RAIIMutex(_mutex);
        return (--_disabled);
    }

    /**
     * Remove all events with matching name (case sensitive) from timer
     */
    final size_t removeEvent(string name)
    {
        import std.algorithm : remove;

        size_t result;
        auto raiiMutex = RAIIMutex(_mutex);
        auto i = _notifiers.length;
        while (i != 0)
        {
            if (_notifiers[i].event.name == name)
            {
                _notifiers = _notifiers.remove(i);
                result++;
            }
            else
                i--;
        }
        return result;
    }

    /**
     * Terminate the timer and it is no longer being used
     */
    final void terminate() @nogc nothrow @trusted //@trusted=sleep
    {
        if (_terminated == 0)
        {
            _terminated++;
            sleep(sleepResolution);
        }
    }

    @property final bool enabled() const @nogc nothrow @safe
    {
        return _disabled == 0;
    }

    @property final bool isTerminated() const @nogc nothrow @safe
    {
        return _terminated != 0;
    }

    @property final Duration resolutionInterval() const @nogc nothrow pure @safe
    {
        return _resolutionInterval;
    }

private:
    final void run()
    {
        _mutex = new Mutex();
        scope (exit)
        {
            _terminated++;
            auto tempMutex = _mutex;
            _mutex = null;
            tempMutex.destroy();
        }

        while (!isTerminated)
        {
            sleepForResolutionInterval();
            if (isTerminated)
                break;

            auto elapsedEvents = getElapsedEvents();
            foreach (ref elapsedEvent; elapsedEvents)
            {
                if (isTerminated)
                    break;

                elapsedEvent.notify();
            }
        }
    }

    final TimerEvent[] getElapsedEvents() nothrow @safe
    {
        auto raiiMutex = RAIIMutex(_mutex);
        if (!enabled)
            return null;

        TimerEvent[] result;
        result.reserve(_notifiers.length);
        foreach (ref notifier; _notifiers)
        {
            if (isTerminated)
                return null;

            notifier.elapsed += _elapsed;
            if (notifier.elapsed > notifier.event.interval)
            {
                notifier.elapsed = Duration.zero;
                notifier.event._counter++;
                result ~= notifier.event;
            }
        }
        return result;
    }

    final void sleepForResolutionInterval() @nogc nothrow @trusted //@trusted=sleep
    {
        _elapsed = Duration.zero;
        while (!isTerminated && _elapsed < _resolutionInterval)
        {
            sleep(sleepResolution);
            _elapsed += sleepResolution;
        }
    }

private:
    enum sleepResolution = dur!"msecs"(2);
    Mutex _mutex;
    TimerNotifier[] _notifiers;
    size_t _disabled, _terminated;
    Duration _elapsed;
    Duration _resolutionInterval;
}


private:

struct TimerNotifier
{
nothrow @safe:

public:
    this(TimerEvent event)
    {
        this.event = event;
    }

public:
    Duration elapsed;
    TimerEvent event;
}
