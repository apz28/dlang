/**
 * Source: $(PHOBOSSRC std/experimental/logger/multilogger.d)
 *
 * Significant Modification Authors: An Pham
 * Distributed under the Boost Software License, Version 1.0.
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module pham.external.std.log.multi_logger;

import pham.external.std.log.logger;

/**
 * This Element is stored inside the `MultiLogger` and associates a
 * `Logger` to a `string`.
 */
struct MultiLoggerEntry
{
    string name; /// The name if the `Logger`
    Logger logger; /// The stored `Logger`
}

/**
 * MultiLogger logs to multiple `Logger`. The `Logger`s are stored in an
 * `Logger[]` in their order of insertion.
 * Every data logged to this `MultiLogger` will be distributed to all the $(D
 * Logger)s inserted into it. This `MultiLogger` implementation can
 * hold multiple `Logger`s with the same name. If the method `removeLogger`
 * is used to remove a `Logger` only the first occurrence with that name will
 * be removed.
 */
class MultiLogger : MemLogger
{
public:
    this(LoggerOption option = defaultOption()) nothrow @safe
    {
        super(option);
    }

    static LoggerOption defaultOption() nothrow pure @safe
    {
        return LoggerOption(lowestLogLevel, "MultiLogger", defaultOutputPattern, 0);
    }

    /**
     * This method inserts a new Logger into the `MultiLogger`.
     * Params:
     *  name = The name of the `Logger` to insert.
     *  newLogger = The `Logger` to insert.
     */
    void insertLogger(string name, Logger newLogger) nothrow @safe
    {
        try
        {
            synchronized (mutex)
            {
                this.loggerEntries ~= MultiLoggerEntry(name, newLogger);
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This method removes a Logger from the `MultiLogger`.
     * Params:
     *  toRemove = The name of the `Logger` to remove. If the `Logger`
     *      is not found `null` will be returned. Only the first occurrence of
     *      a `Logger` with the given name will be removed.
     *  all = indicate to remove all logger with matched name, toRemove
     * Returns:
     *  The removed `Logger`.
     */
    Logger removeLogger(scope const(char)[] toRemove, const(bool) all = true) nothrow @safe
    {
        import std.algorithm : remove;

        Logger firstRemoved;
        try
        {
            synchronized (mutex)
            {
                for (size_t i = 0; i < this.loggerEntries.length; i++)
                {
                    if (this.loggerEntries[i].name == toRemove)
                    {
                        if (firstRemoved is null)
                            firstRemoved = this.loggerEntries[i].logger;
                        this.loggerEntries = this.loggerEntries.remove(i);
                        if (!all)
                            break;
                    }
                }
            }
        }
        catch (Exception)
        {}

        return firstRemoved;
    }

protected:
    final override void doFatal() nothrow @safe
    {}

    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        foreach (ref loggerEntry; this.loggerEntries)
        {
            /*
            We don't perform any checks here to avoid race conditions.
            Instead the child will check on its own if its log level matches
            and assume LogLevel.all for the globalLogLevel (since we already
            know the message passes this test).
            */
            loggerEntry.logger.forwardLog(payload);
        }
    }

protected:
    /**
     * This member holds all `Logger`s stored in the `MultiLogger`.
     * When inheriting from `MultiLogger` this member can be used to gain
     * access to the stored `Logger`.
     */
    MultiLoggerEntry[] loggerEntries;
}


private:

@safe unittest
{
    import std.exception : assertThrown;

    auto a = new MultiLogger;
    auto n0 = new NullLogger();
    auto n1 = new NullLogger();
    a.insertLogger("zero", n0);
    a.insertLogger("one", n1);

    auto n0_1 = a.removeLogger("zero");
    assert(n0_1 is n0);
    auto n = a.removeLogger("zero");
    assert(n is null);

    auto n1_1 = a.removeLogger("one");
    assert(n1_1 is n1);
    n = a.removeLogger("one");
    assert(n is null);
}

@safe unittest
{
    auto a = new MultiLogger;
    auto n0 = new TestLogger;
    auto n1 = new TestLogger;
    a.insertLogger("zero", n0);
    a.insertLogger("one", n1);

    a.log("Hello TestLogger"); int line = __LINE__;
    assert(n0.msg == "Hello TestLogger");
    assert(n0.line == line);
    assert(n1.msg == "Hello TestLogger");
    assert(n1.line == line);
}

// Issue #16
@system unittest
{
    import std.file : deleteme, remove;
    import std.stdio : File;
    import std.string : indexOf;

    string logName = deleteme ~ __FUNCTION__ ~ ".log";
    auto logFileOutput = File(logName, "w");
    scope (exit)
    {
        logFileOutput.close();
        remove(logName);
    }
    auto traceLog = new FileLogger(logFileOutput, LoggerOption(defaultUnitTestLogLevel, "TestTrace", defaultOutputPattern, 0));
    auto infoLog = new TestLogger(LoggerOption(LogLevel.info, "TestInfo", defaultOutputPattern, 0));

    auto root = new MultiLogger();
    root.insertLogger("fileLogger", traceLog);
    root.insertLogger("stdoutLogger", infoLog);

    string tMsg = "A trace message";
    root.trace(tMsg);
    int line1 = __LINE__;
    assert(infoLog.line != line1);
    assert(infoLog.msg != tMsg);

    string iMsg = "A info message";
    root.info(iMsg);
    int line2 = __LINE__ - 1;
    assert(infoLog.line == line2);
    assert(infoLog.msg == iMsg, infoLog.msg ~ ":" ~ iMsg);

    logFileOutput.close();
    logFileOutput = File(logName, "r");
    assert(logFileOutput.isOpen);
    assert(!logFileOutput.eof);

    auto line = logFileOutput.readln();
    assert(line.indexOf(tMsg) != -1, line ~ ":" ~ tMsg);
    assert(!logFileOutput.eof);
    line = logFileOutput.readln();
    assert(line.indexOf(iMsg) != -1, line ~ ":" ~ tMsg);
}
