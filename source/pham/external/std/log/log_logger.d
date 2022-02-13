/*
 *
 * Source: $(PHOBOSSRC std/experimental/logger/core.d)
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Copyright Robert, An Pham
 *
 * Copyright Copyright Robert "burner" Schadek 2013, $(HTTP www.svs.informatik.uni-oldenburg.de/60865.html
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/
module pham.external.std.log.logger;

import core.atomic : atomicLoad, atomicStore,  MemoryOrder;
import core.sync.mutex : Mutex;
import core.thread : ThreadID;
public import core.time : Duration, dur, msecs;
import std.array : Appender;
import std.conv : emplace, to;
import std.datetime.date : DateTime;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : LocalTime, UTC;
import std.format : formattedWrite;
import std.process : thisThreadID;
import std.range.primitives : empty, front, popFront;
import std.stdio : File;
import std.traits : isDynamicArray, isIntegral, isSomeString, Unqual;
import std.typecons : Flag, Yes;
import std.utf : encode;

version (DebugLogger) import std.stdio : writeln;
import pham.external.std.log.date_time_format;


/**
 * There are eight usable logging level. These level are $(I trace), $(I debug_),
 * $(I info), $(I warn), $(I error), $(I critical), $(I fatal), and $(I off).
 */
enum LogLevel : ubyte
{
    trace = 0, /** `LogLevel` for tracing the execution of the program. */
    debug_,
    info,      /** This level is used to display information about the program. */
    warn,      /** warnings about the program should be displayed with this level. */
    error,     /** Information about errors should be logged with this level.*/
    critical,  /** Messages that inform about critical errors should be logged with this level. */
    fatal,     /** Log messages that describe fatal errors should use this level. */
    off        /** Highest possible `LogLevel`. */
}

enum highestLogLevel = LogLevel.fatal;
enum lowestLogLevel = LogLevel.trace;
enum offLogLevel = LogLevel.off;

enum defaultLogLevel = LogLevel.warn;
enum defaultSharedLogLevel = LogLevel.warn;
enum defaultStaticLogLevel = LogLevel.trace;

ptrdiff_t lastModuleSeparatorIndex(string moduleName) @nogc nothrow pure @safe
{
    ptrdiff_t last = cast(ptrdiff_t)moduleName.length - 1;
    while (last >= 0 && moduleName[last] != '.')
        last--;
    return last;
}

string moduleParentOf(string moduleName) @nogc nothrow pure @safe
{
    const i = moduleName.lastModuleSeparatorIndex();
    return i > 0 ? moduleName[0..i] : null;
}

/**
 * This template returns the `LogLevel` named "logLevel" of type $(D
 * LogLevel) defined in a user defined module where the filename has the
 * suffix "_loggerconfig.d". This `LogLevel` sets the minimal `LogLevel`
 * of the module.
 * A minimal `LogLevel` can be defined on a per module basis.
 * In order to define a module `LogLevel` a file with a modulename
 * "MODULENAME_loggerconfig" must be found. If no such module exists and the
 * module is a nested module, it is checked if there exists a
 * "PARENT_MODULE_loggerconfig" module with such a symbol.
 * If this module exists and it contains a `LogLevel` called logLevel this $(D
 * LogLevel) will be used. This parent lookup is continued until there is no
 * parent module. Then the moduleLogLevel is `LogLevel.trace`.
 */
template moduleLogLevel(string moduleName)
{
    import std.string : format;

    static if (moduleName.length == 0)
    {
        enum moduleLogLevel = defaultStaticLogLevel;
    }
    else
    {
        mixin(q{
            // don't enforce enum here
            static if (__traits(compiles, {import %1$s : logLevel;}))
            {
                import %1$s : logLevel;
                static assert(is(typeof(logLevel) : LogLevel), "Expect 'logLevel' to be of type 'LogLevel'.");
                alias moduleLogLevel = logLevel;
            }
            // use logLevel of package or default
            else
                alias moduleLogLevel = moduleLogLevel!(moduleName.moduleParentOf());
        }.format(moduleName ~ "_loggerconfig"));
    }
}

/**
 * This template evaluates if the passed `LogLevel` is active.
 * The previously described version statements are used to decide if the
 * `LogLevel` is active. The version statements only influence the compile
 * unit they are used with, therefore this function can only disable logging this
 * specific compile unit.
 */
template isLoggingActive(LogLevel ll)
{
    version (DisableLogger)
    {
        enum isLoggingActive = false;
    }
    else
    {
        static if (ll == LogLevel.trace)
        {
            version (DisableLoggerTrace) enum isLoggingActive = false;
        }
        static if (ll == LogLevel.debug_)
        {
            version (DisableLoggerDebug_) enum isLoggingActive = false;
        }
        else static if (ll == LogLevel.info)
        {
            version (DisableLoggerInfo) enum isLoggingActive = false;
        }
        else static if (ll == LogLevel.warn)
        {
            version (DisableLoggerWarn) enum isLoggingActive = false;
        }
        else static if (ll == LogLevel.error)
        {
            version (DisableLoggerError) enum isLoggingActive = false;
        }
        else static if (ll == LogLevel.critical)
        {
            version (DisableLoggerCritical) enum isLoggingActive = false;
        }
        else static if (ll == LogLevel.fatal)
        {
            version (DisableLoggerFatal) enum isLoggingActive = false;
        }

        // If `isLoggingActive` didn't get defined above to false,
        // we default it to true.
        static if (!is(typeof(isLoggingActive) == bool))
        {
            enum isLoggingActive = true;
        }
    }
}

/// This compile-time flag is `true` if logging is not statically disabled.
enum isStaticLoggingActive = isLoggingActive!(defaultStaticLogLevel);

template isStaticModuleLoggingActive(LogLevel ll, string moduleName)
{
    enum isStaticModuleLoggingActive = isLoggingActive!ll && ll >= moduleLogLevel!moduleName;
}

/**
 * This functions is used at runtime to determine if a `LogLevel` is
 * active. The same previously defined version statements are used to disable
 * certain levels. Again the version statements are associated with a compile
 * unit and can therefore not disable logging in other compile units.
 */
pragma(inline, true)
bool isLoggingEnabled(const(LogLevel) ll, const(LogLevel) moduleLL, const(LogLevel) loggerLL, const(LogLevel) globalLL) @nogc nothrow pure @safe
{
    version (DebugLogger) debug writeln("isLoggingEnabled().ll=", ll, ", moduleLL=", moduleLL, ", loggerLL=", loggerLL, ", globalLL=", globalLL);

    static if (!isStaticLoggingActive)
    {
        return false;
    }
    else
    {
        version (DisableLogger)
            return false;
        else
        {
            version (DisableLoggerTrace)
            if (ll == LogLevel.trace)
                return false;

            version (DisableLoggerDebug_)
            if (ll == LogLevel.debug_)
                return false;

            version (DisableLoggerInfo)
            if (ll == LogLevel.info)
                return false;

            version (DisableLoggerWarn)
            if (ll == LogLevel.warn)
                return false;

            version (DisableLoggerError)
            if (ll == LogLevel.error)
                return false;

            version (DisableLoggerCritical)
            if (ll == LogLevel.critical)
                return false;

            version (DisableLoggerFatal)
            if (ll == LogLevel.fatal)
                return false;

            return ll != LogLevel.off
                && ((ll >= loggerLL && ll >= globalLL) || (ll >= moduleLL && ll >= globalLL));
        }
    }
}

enum OutputPatternMarker : char
{
    detailLevel = 'd',
    format = '\'',
    maxLength = 'm',
    padLeft = 'l', // Lower case L
    padRight = 'r',
    terminator = '%',
}

// Name must start with capital letter to reserve lower case for other use
enum OutputPatternName : string
{
    date = "Date", /// The date of the logging event in the local time zone
    filename = "File", /// The file name where the logging request was issued
    level = "Level", /// The level of the logging event
    line = "Line", /// The line number from where the logging request was issued
    logger = "Logger", /// The logger or logger-name of the logging event
    message = "Message", /// The application supplied message associated with the logging event
    method = "Method", /// The function name where the logging request was issued
    newLine = "NewLine", /// The platform dependent line separator character "\n" or characters "\r\n".
    stacktrace = "Stacktrace", /// The stack trace of the logging event The stack trace level specifier may be enclosed between braces
    timestamp = "Timestamp", /// The number of milliseconds elapsed since the start of the application until the creation of the logging event
    thread = "Thread", /// The name or thread-id of the thread that generated the logging event
    username = "Username", /// The OS-Identity for the currently active user
    userContext = "Context", /// The application supplied context information associated with the logger
}

enum OutputPattern : string
{
    date = OutputPatternMarker.terminator ~ OutputPatternName.date ~ OutputPatternMarker.terminator,
    filename = OutputPatternMarker.terminator ~ OutputPatternName.filename ~ OutputPatternMarker.terminator,
    level = OutputPatternMarker.terminator ~ OutputPatternName.level ~ OutputPatternMarker.terminator,
    line = OutputPatternMarker.terminator ~ OutputPatternName.line ~ OutputPatternMarker.terminator,
    logger = OutputPatternMarker.terminator ~ OutputPatternName.logger ~ OutputPatternMarker.terminator,
    message = OutputPatternMarker.terminator ~ OutputPatternName.message ~ OutputPatternMarker.terminator,
    method = OutputPatternMarker.terminator ~ OutputPatternName.method ~ OutputPatternMarker.terminator,
    newLine = OutputPatternMarker.terminator ~ OutputPatternName.newLine ~ OutputPatternMarker.terminator,
    stacktrace = OutputPatternMarker.terminator ~ OutputPatternName.stacktrace ~ OutputPatternMarker.terminator,
    timestamp = OutputPatternMarker.terminator ~ OutputPatternName.timestamp ~ OutputPatternMarker.terminator,
    thread = OutputPatternMarker.terminator ~ OutputPatternName.thread ~ OutputPatternMarker.terminator,
    username = OutputPatternMarker.terminator ~ OutputPatternName.username ~ OutputPatternMarker.terminator,
    userContext = OutputPatternMarker.terminator ~ OutputPatternName.userContext ~ OutputPatternMarker.terminator,
}

immutable string defaultOutputPattern = OutputPattern.date
    ~ " [" ~ OutputPattern.level ~ "] "
    ~ OutputPattern.filename ~ "."
    ~ OutputPattern.line ~ "."
    ~ OutputPattern.method ~ ": "
    ~ OutputPattern.message
    ~ OutputPattern.newLine;

struct LoggerOption
{
@nogc nothrow @safe:

    this(LogLevel logLevel, string logName, string outputPattern, size_t flushOutputLines) pure
    {
        this.logLevel = logLevel;
        this.logName = logName;
        this.outputPattern = outputPattern;
        this.flushOutputLines = flushOutputLines;
    }

    string logName;
    string outputPattern = defaultOutputPattern;
    size_t flushOutputLines;
    LogLevel logLevel = defaultLogLevel;
}

struct ModuleLoggerOption
{
@nogc nothrow @safe:

    this(LogLevel logLevel, string moduleName) pure
    {
        this.logLevel = logLevel;
        this.moduleName = moduleName;
    }

    string moduleName;
    LogLevel logLevel = defaultLogLevel;
}

class ModuleLoggerOptions
{
nothrow @safe:

public:
    this(Mutex mutex)
    out
    {
        assert(this.mutex !is null);
    }
    do
    {
        this.ownMutex = mutex is null;
        this.mutex = this.ownMutex ? (new Mutex()) : mutex;
    }

    ~this()
    {
        doDispose(false);
    }

    final void dispose()
    {
        doDispose(true);
    }

    final LogLevel logLevel(scope string moduleName, const(LogLevel) notFoundLogLevel) @nogc
    {
        auto locked = LogRAIIMutex(mutex);
        if (values.length == 0)
            return notFoundLogLevel;
        else if (const v = moduleName in values)
            return (*v).logLevel;
        else
            return notFoundLogLevel;
    }

    final ModuleLoggerOption remove(scope string moduleName)
    {
        auto locked = LogRAIIMutex(mutex);
        if (const v = moduleName in values)
        {
            auto result = *v;
            values.remove(moduleName);
            return result;
        }
        else
            return ModuleLoggerOption.init;
    }

    final void remove(scope string[] moduleNames)
    {
        auto locked = LogRAIIMutex(mutex);
        foreach (moduleName; moduleNames)
            values.remove(moduleName);
    }

    final void set(ModuleLoggerOption option)
    in
    {
        assert(option.moduleName.length != 0);
    }
    do
    {
        auto locked = LogRAIIMutex(mutex);
        values[option.moduleName] = option;
    }

    final void set(ModuleLoggerOption[] options)
    {
        auto locked = LogRAIIMutex(mutex);
        foreach (ref option; options)
        {
            assert(option.moduleName.length != 0);
            values[option.moduleName] = option;
        }
    }

    static ModuleLoggerOption removeModule(scope string moduleName) @trusted
    {
        return (cast()moduleOptions_).remove(moduleName);
    }

    static void setModule(ModuleLoggerOption option) @trusted
    {
        (cast()moduleOptions_).set(option);
    }

protected:
    void doDispose(bool disposing) @trusted
    {
        if (disposing)
            values = null;

        if (mutex !is null)
        {
            if (ownMutex)
                mutex.destroy();
            mutex = null;
        }
    }

private:
    Mutex mutex;
    ModuleLoggerOption[string] values;
    bool ownMutex;
}

/**
 * This function logs data.
 * In order for the data to be processed the `LogLevel` of the
 * `sharedLog` must be greater or equal to the `defaultLogLevel`.
 * Params:
 *  args = The data that should be logged.
 * Example:
--------------------
log("Hello World", 3.1415);
--------------------
 */
void log(string moduleName = __MODULE__, Args...)(lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
{
    version (DebugLogger) debug writeln("args.line=", line);

    static if (isStaticLoggingActive)
    {
        auto logger = threadLog;
        logger.log!(moduleName, Args)(logger.logLevel, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data.
 * In order for the data to be processed the `LogLevel` of the
 * `sharedLog` must be greater or equal to the `defaultLogLevel`
 * add the condition passed must be `true`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  args = The data that should be logged.
 * Example:
--------------------
log(true, "Hello World", 3.1415);
--------------------
 */
void log(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("condition.args.line=", line);

    static if (isStaticLoggingActive)
    {
        auto logger = threadLog;
        logger.log!(moduleName, Args)(logger.logLevel, condition, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog`.
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  args = The data that should be logged.
 * Example:
--------------------
log(LogLevel.warn, "Hello World", 3.1415);
--------------------
*/
void log(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
{
    version (DebugLogger) debug writeln("ll.args.line=", line);

    static if (isStaticLoggingActive)
    {
        threadLog.log!(moduleName, Args)(ll, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data.
 * In order for the data to be processed, the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog` and the
 * `defaultLogLevel`; additionally the condition passed must be `true`.
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  condition = The condition must be `true` for the data to be logged.
 *  args = The data that should be logged.
 * Example:
--------------------
log(LogLevel.warn, true, "Hello World", 3.1415);
--------------------
 */
void log(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy bool condition, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    static if (isStaticLoggingActive)
    {
        threadLog.log!(moduleName, Args)(ll, condition, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `defaultLogLevel`.
 * Params:
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
--------------------
logf("Hello World %f", 3.1415);
--------------------
 */
void logf(string moduleName = __MODULE__, Args...)(lazy string fmt, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
{
    version (DebugLogger) debug writeln("fmt.args.line=", line);

    static if (isStaticLoggingActive)
    {
        auto logger = threadLog;
        logger.logf!(moduleName, Args)(logger.logLevel, fmt, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `defaultLogLevel` additionally the condition
 * passed must be `true`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  fmt = The `printf`-style string.
 * args = The data that should be logged.
 * Example:
--------------------
logf(true, "Hello World %f", 3.1415);
--------------------
 */
void logf(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy string fmt, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("condition.fmt.args.line=", line);

    static if (isStaticLoggingActive)
    {
        auto logger = threadLog;
        logger.logf!(moduleName, Args)(logger.logLevel, condition, fmt, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog` and the
 * `defaultLogLevel`.
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
--------------------
logf(LogLevel.warn, "Hello World %f", 3.1415);
--------------------
 */
void logf(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy string fmt, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("ll.fmt.args.line=", line);

    static if (isStaticLoggingActive)
    {
        threadLog.logf!(moduleName, Args)(ll, fmt, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog` and the
 * `defaultLogLevel` additionally the condition passed must be `true`.
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  condition = The condition must be `true` for the data to be logged.
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
--------------------
logf(LogLevel.warn, true, "Hello World %f", 3.1415);
--------------------
 */
void logf(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy bool condition, lazy string fmt, lazy Args args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("ll.condition.fmt.args.line=", line);

    static if (isStaticLoggingActive)
    {
        threadLog.logf!(moduleName, Args)(ll, condition, fmt, args, ex, line, fileName, funcName, prettyFuncName);
    }
}

/**
 * This template provides the global log functions with the `LogLevel`
 * is encoded in the function name.
 * The aliases following this template create the public names of these log
 * functions.
 */
template defaultLogFunction(LogLevel ll)
{
    void defaultLogFunction(string moduleName = __MODULE__, Args...)(lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
    {
        version (DebugLogger) debug writeln("defaultLogFunction.args.line=", line);

        static if (isStaticModuleLoggingActive!(ll, moduleName))
        {
            threadLog.logFunction!(ll).logImpl!(moduleName, Args)(args, ex, line, fileName, funcName, prettyFuncName);
        }
    }

    void defaultLogFunction(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("defaultLogFunction.condition.args.line=", line);

        static if (isStaticModuleLoggingActive!(ll, moduleName))
        {
            threadLog.logFunction!(ll).logImpl!(moduleName, Args)(condition, args, ex, line, fileName, funcName, prettyFuncName);
        }
    }
}

/**
 * This function logs data to the `stdThreadLocalLog`, optionally depending
 * on a condition.
 * In order for the resulting log message to be logged the `LogLevel` must
 * be greater or equal than the `LogLevel` of the `stdThreadLocalLog` and
 * must be greater or equal than the global `LogLevel`.
 * Additionally the `LogLevel` must be greater or equal than the `LogLevel`
 * of the `stdSharedLogger`.
 * If a condition is given, it must evaluate to `true`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  args = The data that should be logged.
 * Example:
--------------------
logTrace(1337, "is number");
logDebug_(1337, "is number");
logInfo(1337, "is number");
logError(1337, "is number");
logCritical(1337, "is number");
logFatal(1337, "is number");

logTrace(true, 1337, "is number");
logDebug_(false, 1337, "is number");
logInfo(false, 1337, "is number");
logError(true, 1337, "is number");
logCritical(false, 1337, "is number");
logFatal(true, 1337, "is number");
--------------------
 */
alias logTrace = defaultLogFunction!(LogLevel.trace);
/// Ditto
alias logDebug_ = defaultLogFunction!(LogLevel.debug_);
/// Ditto
alias logInfo = defaultLogFunction!(LogLevel.info);
/// Ditto
alias logWarn = defaultLogFunction!(LogLevel.warn);
/// Ditto
alias logError = defaultLogFunction!(LogLevel.error);
/// Ditto
alias logCritical = defaultLogFunction!(LogLevel.critical);
/// Ditto
alias logFatal = defaultLogFunction!(LogLevel.fatal);

/**
 * This template provides the global `printf`-style log functions with
 * the `LogLevel` is encoded in the function name.
 * The aliases following this template create the public names of the log
 * functions.
 */
template defaultLogFunctionf(LogLevel ll)
{
    void defaultLogFunctionf(string moduleName = __MODULE__, Args...)(lazy string fmt, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
    {
        version (DebugLogger) debug writeln("defaultLogFunctionf.fmt.args.line=", line);

        static if (isStaticModuleLoggingActive!(ll, moduleName))
        {
            threadLog.logFunction!(ll).logImplf!(moduleName, Args)(fmt, args, ex, line, fileName, funcName, prettyFuncName);
        }
    }

    void defaultLogFunctionf(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy string fmt, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("defaultLogFunctionf.condition.fmt.args.line=", line);

        static if (isStaticModuleLoggingActive!(ll, moduleName))
        {
            threadLog.logFunction!(ll).logImplf!(moduleName, Args)(condition, fmt, args, ex, line, fileName, funcName, prettyFuncName);
        }
    }
}

/**
 * This function logs data to the `sharedLog` in a `printf`-style manner.
 * In order for the resulting log message to be logged the `LogLevel` must
 * be greater or equal than the `LogLevel` of the `sharedLog` and
 * must be greater or equal than the global `LogLevel`.
 * Additionally the `LogLevel` must be greater or equal than the `LogLevel`
 * of the `stdSharedLogger`.
 * Params:
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
--------------------
logTracef("is number %d", 1);
logDebugf_("is number %d", 2);
logInfof("is number %d", 3);
logErrorf("is number %d", 4);
logCriticalf("is number %d", 5);
logFatalf("is number %d", 6);
--------------------
 *
 * The second version of the function logs data to the `sharedLog` in a $(D
 * printf)-style manner.
 * In order for the resulting log message to be logged the `LogLevel` must
 * be greater or equal than the `LogLevel` of the `sharedLog` and
 * must be greater or equal than the global `LogLevel`.
 * Additionally the `LogLevel` must be greater or equal than the `LogLevel`
 * of the `stdSharedLogger`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
--------------------
logTracef(false, "is number %d", 1);
logDebugf_(false, "is number %d", 2);
logInfof(false, "is number %d", 3);
logErrorf(true, "is number %d", 4);
logCriticalf(true, "is number %d", 5);
logFatalf(someFunct(), "is number %d", 6);
--------------------
 */
alias logTracef = defaultLogFunctionf!(LogLevel.trace);
/// Ditto
alias logDebugf_ = defaultLogFunctionf!(LogLevel.debug_);
/// Ditto
alias logInfof = defaultLogFunctionf!(LogLevel.info);
/// Ditto
alias logWarnf = defaultLogFunctionf!(LogLevel.warn);
/// Ditto
alias logErrorf = defaultLogFunctionf!(LogLevel.error);
/// Ditto
alias logCriticalf = defaultLogFunctionf!(LogLevel.critical);
/// Ditto
alias logFatalf = defaultLogFunctionf!(LogLevel.fatal);

/**
 * This class is the base of every logger. In order to create a new kind of
 * logger a deriving class needs to implement the `writeLog` method. By
 * default this is not thread-safe.
 * It is also possible to `override` the three methods `beginMsg`,
 * `commitMsg` and `endMsg` together, this option gives more
 * flexibility.
 */
abstract class Logger
{
public:
    /**
     * Every subclass of `Logger` has to call this constructor from their
     * constructor. It sets the `LoggerOption`, and creates a fatal handler. The fatal
     * handler will throw an `Error` if a log call is made with level
     * `LogLevel.fatal`.
     * Params:
     *  option = `LoggerOption` to use for this `Logger` instance.
     */
    this(LoggerOption option = LoggerOption.init) nothrow @safe
    {
        this.option = option;
        this.userName_ = currentUserName();
        this.mutex = new Mutex();
    }

    ~this() nothrow @safe
    {
        doDispose(false);
    }

    final void dispose()
    {
        doDispose(true);
    }

    /**
     * This method allows forwarding log entries from one logger to another.
     * `forwardMsg` will ensure proper synchronization and then call
     * `writeLogMsg`. This is an API for implementing your own loggers and
     * should not be called by normal user code. A notable difference from other
     * logging functions is that the `globalLogLevel` won't be evaluated again
     * since it is assumed that the caller already checked that.
     */
    void forwardLog(ref LogEntry payload) nothrow @trusted
    {
        static if (isStaticLoggingActive)
        try
        {
            version (DebugLogger) debug writeln("Logger.forwardLog()");

            bool wasLog = false;
            const llGlobalLogLevel = globalLogLevel;
            const llLogLevel = this.logLevel;
            const llModuleLogLevel = (cast()moduleOptions_).logLevel(payload.header.moduleName, LogLevel.off);
            if (isLoggingEnabled(payload.header.logLevel, llModuleLogLevel, llLogLevel, llGlobalLogLevel))
            {
                auto locked = LogRAIIMutex(mutex);
                this.writeLog(payload);
                wasLog = true;
            }
            if (wasLog && payload.header.logLevel == LogLevel.fatal)
                doFatal();
        }
        catch (Exception)
        {}
    }

    pragma(inline, true)
    @property final size_t flushOutputLines() const nothrow pure @safe
    {
        return this.option.flushOutputLines;
    }

    /**
     * The `LogLevel` determines if the log call are processed or dropped
     * by the `Logger`. In order for the log call to be processed the
     * `LogLevel` of the log call must be greater or equal to the `LogLevel`
     * of the `logger`.
     * These two methods set and get the `LogLevel` of the used `Logger`.
     * Example:
    -----------
    auto f = new FileLogger(stdout);
    f.logLevel = LogLevel.info;
    assert(f.logLevel == LogLevel.info);
    -----------
     */
    @property final LogLevel logLevel() const nothrow pure @safe
    {
        return threadSafeLoad(cast(shared)(this.option.logLevel));
    }

    /// Ditto
    @property final Logger logLevel(const(LogLevel) value) nothrow @safe @nogc
    {
        threadSafeStore(cast(shared)(this.option.logLevel), value);
        return this;
    }

    @property final string name() nothrow @safe @nogc
    {
        auto locked = LogRAIIMutex(mutex);
        return this.option.logName;
    }

    @property final Logger name(string value) nothrow @safe @nogc
    {
        auto locked = LogRAIIMutex(mutex);
        this.option.logName = value;
        return this;
    }

    @property final string outputPattern() nothrow @safe @nogc
    {
        auto locked = LogRAIIMutex(mutex);
        return this.option.outputPattern;
    }

    @property final Logger outputPattern(string value) nothrow @safe
    {
        auto locked = LogRAIIMutex(mutex);
        this.option.outputPattern = value;
        return this;
    }

    @property final Object userContext() nothrow pure @trusted
    {
        return cast(Object)threadSafeLoad(cast(shared)(this.userContext_));
    }

    @property final Logger userContext(Object value) nothrow @trusted
    {
        threadSafeStore(cast(shared)(this.userContext_), cast(shared)value);
        return this;
    }

    @property final string userName() nothrow @safe
    {
        return userName_;
    }

    /**
     * This template provides the checking for if a level is enabled for the `Logger` `class`
     * with the `LogLevel` encoded in the function name.
     * For further information see the the two functions defined inside of this
     * template.
     * The aliases following this template create the public names of these log
     * functions.
     */
    template isFunction(LogLevel ll)
    {
        final bool isImpl(string moduleName = __MODULE__)() const nothrow
        {
            LogLevel llModuleLogLevel = void;
            return isImpl2!(moduleName)(llModuleLogLevel);
        }

        final bool isImpl2(string moduleName = __MODULE__)(out LogLevel llModuleLogLevel) const nothrow @trusted
        {
            static if (isStaticModuleLoggingActive!(ll, moduleName))
            {
                const llGlobalLogLevel = globalLogLevel;
                const llLogLevel = this.logLevel;
                llModuleLogLevel = (cast()moduleOptions_).logLevel(moduleName, LogLevel.off);
                return isLoggingEnabled(ll, llModuleLogLevel, llLogLevel, llGlobalLogLevel);
            }
            else
            {
                llModuleLogLevel = LogLevel.off;
                return false;
            }
        }
    }

    /// Ditto
    alias isTrace = isFunction!(LogLevel.trace).isImpl;
    alias isTrace2 = isFunction!(LogLevel.trace).isImpl2;
    /// Ditto
    alias isDebug_ = isFunction!(LogLevel.debug_).isImpl;
    alias isDebug2_ = isFunction!(LogLevel.debug_).isImpl2;
    /// Ditto
    alias isInfo = isFunction!(LogLevel.info).isImpl;
    alias isInfo2 = isFunction!(LogLevel.info).isImpl2;
    /// Ditto
    alias isWarn = isFunction!(LogLevel.warn).isImpl;
    alias isWarn2 = isFunction!(LogLevel.warn).isImpl2;
    /// Ditto
    alias isError = isFunction!(LogLevel.error).isImpl;
    alias isError2 = isFunction!(LogLevel.error).isImpl2;
    /// Ditto
    alias isCritical = isFunction!(LogLevel.critical).isImpl;
    alias isCritical2 = isFunction!(LogLevel.critical).isImpl2;
    /// Ditto
    alias isFatal = isFunction!(LogLevel.fatal).isImpl;
    alias isFatal2 = isFunction!(LogLevel.fatal).isImpl2;

    /// Ditto
    final bool isLogLevel(string moduleName = __MODULE__)(const(LogLevel) ll) const nothrow @safe
    {
        LogLevel llModuleLogLevel = void;
        return isLogLevel2!(moduleName)(ll, llModuleLogLevel);
    }

    final bool isLogLevel2(string moduleName = __MODULE__)(const(LogLevel) ll, out LogLevel llModuleLogLevel) const nothrow @trusted
    {
        final switch (ll)
        {
            case LogLevel.trace:
                return isTrace2!(moduleName)(llModuleLogLevel);
            case LogLevel.debug_:
                return isDebug2_!(moduleName)(llModuleLogLevel);
            case LogLevel.info:
                return isInfo2!(moduleName)(llModuleLogLevel);
            case LogLevel.warn:
                return isWarn2!(moduleName)(llModuleLogLevel);
            case LogLevel.error:
                return isError2!(moduleName)(llModuleLogLevel);
            case LogLevel.critical:
                return isCritical2!(moduleName)(llModuleLogLevel);
            case LogLevel.fatal:
                return isFatal2!(moduleName)(llModuleLogLevel);
            case LogLevel.off:
                llModuleLogLevel = LogLevel.off;
                return false;
        }
    }

    /**
     * This template provides the log functions for the `Logger` `class`
     * with the `LogLevel` encoded in the function name.
     * For further information see the the two functions defined inside of this
     * template.
     * The aliases following this template create the public names of these log
     * functions.
     */
    template logFunction(LogLevel ll)
    {
        /**
         * This function logs data to the used `Logger`.
         * In order for the resulting log message to be logged the `LogLevel`
         * must be greater or equal than the `LogLevel` of the used `Logger`
         * and must be greater or equal than the global `LogLevel`.
         * Params:
         *  args = The data that should be logged.
         * Example:
        --------------------
        auto s = new FileLogger(stdout);
        s.trace(1337, "is number");
        s.info(1337, "is number");
        s.error(1337, "is number");
        s.critical(1337, "is number");
        s.fatal(1337, "is number");
        --------------------
         */
        final void logImpl(string moduleName = __MODULE__, Args...)(lazy Args args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
        {
            version (DebugLogger) debug writeln("Logger.logImpl().line=", line, ", funcName=", funcName);

            static if (isStaticModuleLoggingActive!(ll, moduleName))
            try
            {
                if (isFunction!(ll).isImpl!(moduleName)())
                {
                    auto currTime = Clock.currTime;
                    {
                        auto locked = LogRAIIMutex(mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.put!(Args)(args);
                        this.endMsg();
                    }
                    if (ll == LogLevel.fatal)
                        doFatal();
                }
            }
            catch (Exception)
            {}
        }

        /**
         * This function logs data to the used `Logger` depending on a
         * condition.
         * In order for the resulting log message to be logged the `LogLevel` must
         * be greater or equal than the `LogLevel` of the used `Logger` and
         * must be greater or equal than the global `LogLevel` additionally the
         * condition passed must be `true`.
         * Params:
         *  condition = The condition must be `true` for the data to be logged.
         *  args = The data that should be logged.
         * Example:
        --------------------
        auto s = new FileLogger(stdout);
        s.trace(true, 1337, "is number");
        s.info(false, 1337, "is number");
        s.error(true, 1337, "is number");
        s.critical(false, 1337, "is number");
        s.fatal(true, 1337, "is number");
        --------------------
         */
        final void logImpl(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy Args args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        {
            version (DebugLogger) debug writeln("logFunction.condition.args.line=", line);

            static if (isStaticModuleLoggingActive!(ll, moduleName))
            try
            {
                if (isFunction!(ll).isImpl!(moduleName)() && condition)
                {
                    auto currTime = Clock.currTime;
                    {
                        auto locked = LogRAIIMutex(mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.put!(Args)(args);
                        this.endMsg();
                    }
                    if (ll == LogLevel.fatal)
                        doFatal();
                }
            }
            catch (Exception)
            {}
        }

        /**
         * This function logs data to the used `Logger` in a
         * `printf`-style manner.
         * In order for the resulting log message to be logged the `LogLevel` must
         * be greater or equal than the `LogLevel` of the used `Logger` and
         * must be greater or equal than the global `LogLevel`.
         * Params:
         *  fmt = The `printf`-style string.
         *  args = The data that should be logged.
         * Example:
        --------------------
        auto s = new FileLogger(stderr);
        s.tracef("is number %d", 1);
        s.infof("is number %d", 2);
        s.errorf("is number %d", 3);
        s.criticalf("is number %d", 4);
        s.fatalf("is number %d", 5);
        --------------------
         */
        final void logImplf(string moduleName = __MODULE__, Args...)(lazy string fmt, lazy Args args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : string)))
        {
            version (DebugLogger) debug writeln("logFunction.args.line=", line);

            static if (isStaticModuleLoggingActive!(ll, moduleName))
            try
            {
                if (isFunction!(ll).isImpl!(moduleName)())
                {
                    auto currTime = Clock.currTime;
                    {
                        auto locked = LogRAIIMutex(mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.putf(fmt, args);
                        this.endMsg();
                    }
                    if (ll == LogLevel.fatal)
                        doFatal();
                }
            }
            catch (Exception)
            {}
        }

        /**
         * This function logs data to the used `Logger` in a
         * `printf`-style manner.
         * In order for the resulting log message to be logged the `LogLevel`
         * must be greater or equal than the `LogLevel` of the used `Logger`
         * and must be greater or equal than the global `LogLevel` additionally
         * the passed condition must be `true`.
         * Params:
         *  condition = The condition must be `true` for the data to be logged.
         *  fmt = The `printf`-style string.
         *  args = The data that should be logged.
         * Example:
        --------------------
        auto s = new FileLogger(stderr);
        s.tracef(true, "is number %d", 1);
        s.infof(true, "is number %d", 2);
        s.errorf(false, "is number %d", 3);
        s.criticalf(someFunc(), "is number %d", 4);
        s.fatalf(true, "is number %d", 5);
        --------------------
         */
        final void logImplf(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy string fmt, lazy Args args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        {
            version (DebugLogger) debug writeln("logFunction.condition.fmt.args.line=", line);

            static if (isStaticModuleLoggingActive!(ll, moduleName))
            try
            {
                if (isFunction!(ll).isImpl!(moduleName)() && condition)
                {
                    auto currTime = Clock.currTime;
                    {
                        auto locked = LogRAIIMutex(mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.putf(fmt, args);
                        this.endMsg();
                    }
                    if (ll == LogLevel.fatal)
                        doFatal();
                }
            }
            catch (Exception)
            {}
        }
    }

    /// Ditto
    alias trace = logFunction!(LogLevel.trace).logImpl;
    /// Ditto
    alias tracef = logFunction!(LogLevel.trace).logImplf;

    /// Ditto
    alias debug_ = logFunction!(LogLevel.debug_).logImpl;
    /// Ditto
    alias debugf_ = logFunction!(LogLevel.debug_).logImplf;

    /// Ditto
    alias info = logFunction!(LogLevel.info).logImpl;
    /// Ditto
    alias infof = logFunction!(LogLevel.info).logImplf;

    /// Ditto
    alias warn = logFunction!(LogLevel.warn).logImpl;
    /// Ditto
    alias warnf = logFunction!(LogLevel.warn).logImplf;

    /// Ditto
    alias error = logFunction!(LogLevel.error).logImpl;
    /// Ditto
    alias errorf = logFunction!(LogLevel.error).logImplf;

    /// Ditto
    alias critical = logFunction!(LogLevel.critical).logImpl;
    /// Ditto
    alias criticalf = logFunction!(LogLevel.critical).logImplf;

    /// Ditto
    alias fatal = logFunction!(LogLevel.fatal).logImpl;
    /// Ditto
    alias fatalf = logFunction!(LogLevel.fatal).logImplf;

    /**
     * This function logs data to the used `Logger` with the `LogLevel`
     * of the used `Logger`.
     * In order for the resulting log message to be logged the `LogLevel`
     * of the used `Logger` must be greater or equal than the global
     * `LogLevel`.
     * Params:
     *  args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.log(1337, "is number");
    s.log(info, 1337, "is number");
    s.log(1337, "is number");
    s.log(1337, "is number");
    s.log(1337, "is number");
    --------------------
     */
    final void log(string moduleName = __MODULE__, Args...)(lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
    {
        version (DebugLogger) debug writeln("Logger.log().line=", line, ", funcName=", funcName);

        static if (isStaticLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel!(moduleName)(ll))
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.put!(Args)(args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This function logs data to the used `Logger` depending on a
     * explicitly passed condition with the `LogLevel` of the used
     * `Logger`.
     * In order for the resulting log message to be logged the `LogLevel`
     * of the used `Logger` must be greater or equal than the global
     * `LogLevel` and the condition must be `true`.
     * Params:
     *  condition = The condition must be `true` for the data to be logged.
     *  args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.log(true, 1337, "is number");
    s.log(true, 1337, "is number");
    s.log(true, 1337, "is number");
    s.log(false, 1337, "is number");
    s.log(false, 1337, "is number");
    --------------------
     */
    final void log(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("Logger.log().line=", line, ", funcName=", funcName);

        static if (isStaticLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel!(moduleName)(ll) && condition)
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.put!(Args)(args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This function logs data to the used `Logger` with a specific
     * `LogLevel`.
     * In order for the resulting log message to be logged the `LogLevel`
     * must be greater or equal than the `LogLevel` of the used `Logger`
     * and must be greater or equal than the global `LogLevel`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.log(LogLevel.trace, 1337, "is number");
    s.log(LogLevel.info, 1337, "is number");
    s.log(LogLevel.warn, 1337, "is number");
    s.log(LogLevel.error, 1337, "is number");
    s.log(LogLevel.fatal, 1337, "is number");
    --------------------
     */
    final void log(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
    {
        version (DebugLogger) debug writeln("Logger.log().line=", line, ", funcName=", funcName, ", ll=", ll);

        static if (isStaticLoggingActive)
        try
        {
            if (isLogLevel!(moduleName)(ll))
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.put!(Args)(args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This method logs data with the `LogLevel` of the used `Logger`.
     * This method takes a `bool` as first argument. In order for the
     * data to be processed the `bool` must be `true` and the `LogLevel`
     * of the Logger must be greater or equal to the global `LogLevel`.
     * Params:
     *  args = The data that should be logged.
     *  condition = The condition must be `true` for the data to be logged.
     *  args = The data that is to be logged.
     * Returns:
     *  The logger used by the logging function as reference.
     * Example:
    --------------------
    auto l = new StdioLogger();
    l.log(1337);
    --------------------
     */
    final void log(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy bool condition, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("Logger.log().line=", line, ", funcName=", funcName, ", ll=", ll);

        static if (isStaticLoggingActive)
        try
        {
            if (isLogLevel!(moduleName)(ll) && condition)
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.put!(Args)(args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This method logs data to the used `Logger` with the `LogLevel`
     * of the this `Logger` in a `printf`-style manner.
     * In order for the data to be processed the `LogLevel` of the `Logger`
     * must be greater or equal to the global `LogLevel`.
     * Params:
     *  fmt = The format string used for this log call.
     * args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.logf("%d %s", 1337, "is number");
    s.logf("%d %s", 1337, "is number");
    s.logf("%d %s", 1337, "is number");
    s.logf("%d %s", 1337, "is number");
    s.logf("%d %s", 1337, "is number");
    --------------------
     */
    final void logf(string moduleName = __MODULE__, Args...)(lazy string fmt, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
    {
        version (DebugLogger) debug writeln("Logger.logf().line=", line, ", funcName=", funcName);

        static if (isStaticLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel!(moduleName)(ll))
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.putf!(Args)(fmt, args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This function logs data to the used `Logger` depending on a
     * condition with the `LogLevel` of the used `Logger` in a
     * `printf`-style manner.
     * In order for the resulting log message to be logged the `LogLevel`
     * of the used `Logger` must be greater or equal than the global
     * `LogLevel` and the condition must be `true`.
     * Params:
     *  condition = The condition must be `true` for the data to be logged.
     *  fmt = The format string used for this log call.
     *  args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.logf(true ,"%d %s", 1337, "is number");
    s.logf(true ,"%d %s", 1337, "is number");
    s.logf(true ,"%d %s", 1337, "is number");
    s.logf(false ,"%d %s", 1337, "is number");
    s.logf(true ,"%d %s", 1337, "is number");
    --------------------
     */
    final void logf(string moduleName = __MODULE__, Args...)(lazy bool condition, lazy string fmt, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("Logger.logf().line=", line, ", funcName=", funcName);

        static if (isStaticLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel!(moduleName)(ll) && condition)
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.putf!(Args)(fmt, args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This function logs data to the used `Logger` with a specific
     * `LogLevel` in a `printf`-style manner.
     * In order for the resulting log message to be logged the `LogLevel`
     * must be greater or equal than the `LogLevel` of the used `Logger`
     * and must be greater or equal than the global `LogLevel`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  fmt = The format string used for this log call.
     * args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.logf(LogLevel.trace, "%d %s", 1337, "is number");
    s.logf(LogLevel.info, "%d %s", 1337, "is number");
    s.logf(LogLevel.warn, "%d %s", 1337, "is number");
    s.logf(LogLevel.error, "%d %s", 1337, "is number");
    s.logf(LogLevel.fatal, "%d %s", 1337, "is number");
    --------------------
     */
    final void logf(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy string fmt, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("Logger.logf().line=", line, ", funcName=", funcName, ", ll=", ll);

        static if (isStaticLoggingActive)
        try
        {
            if (isLogLevel!(moduleName)(ll))
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.putf!(Args)(fmt, args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

    /**
     * This function logs data to the used `Logger` with a specific
     * `LogLevel` and depending on a condition in a `printf`-style manner.
     * In order for the resulting log message to be logged the `LogLevel`
     * must be greater or equal than the `LogLevel` of the used `Logger`
     * and must be greater or equal than the global `LogLevel` and the
     * condition must be `true`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  condition = The condition must be `true` for the data to be logged.
     *  fmt = The format string used for this log call.
     *  args = The data that should be logged.
     * Example:
    --------------------
    auto s = new FileLogger(stdout);
    s.logf(LogLevel.trace, true ,"%d %s", 1337, "is number");
    s.logf(LogLevel.info, true ,"%d %s", 1337, "is number");
    s.logf(LogLevel.warn, true ,"%d %s", 1337, "is number");
    s.logf(LogLevel.error, false ,"%d %s", 1337, "is number");
    s.logf(LogLevel.fatal, true ,"%d %s", 1337, "is number");
    --------------------
     */
    final void logf(string moduleName = __MODULE__, Args...)(const(LogLevel) ll, lazy bool condition, lazy string fmt, lazy Args args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("Logger.logf().line=", line, ", funcName=", funcName, ", ll=", ll);

        static if (isStaticLoggingActive)
        try
        {
            if (isLogLevel!(moduleName)(ll) && condition)
            {
                auto currTime = Clock.currTime;
                {
                    auto locked = LogRAIIMutex(mutex);
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.putf!(Args)(fmt, args);
                    this.endMsg();
                }
                if (ll == LogLevel.fatal)
                    doFatal();
            }
        }
        catch (Exception)
        {}
    }

public:
    static struct LogHeader
    {
        LogLevel logLevel; /// the `LogLevel` associated with the log message
        int line; /// the line number the log function was called from
        string fileName; /// the filename the log function was called from
        string funcName; /// the name of the function the log function was called from
        string prettyFuncName; /// the pretty formatted name of the function the log function was called from
        string moduleName; /// the name of the module the log message is coming from
        ThreadID threadID; /// thread id of the log message
        SysTime timestamp; /// the time the message was logged
        Exception exception;
    }

    /**
     * LogEntry is a aggregation combining all information associated
     * with a log message. This aggregation will be passed to the method
     * writeLogMsg.
     */
    static struct LogEntry
    {
        Logger logger; /// A refernce to the `Logger` used to create this `LogEntry`
        LogHeader header;
        string message; /// the message of the log message
    }

protected:
    void doDispose(bool disposing) nothrow @trusted
    {
        option.logLevel = LogLevel.off;
        if (disposing)
        {
            userName_ = null;
            userContext_ = null;
        }
        if (mutex !is null)
        {
            mutex.destroy();
            mutex = null;
        }
    }

    void doFatal() nothrow @safe
    {
        assert(0);
    }

    /** Signals that the log message started. */
    abstract void beginMsg(ref LogHeader header) nothrow @safe;

    /** Logs a part of the log message. */
    abstract void commitMsg(scope const(char)[] msg) nothrow @safe;

    /** Signals that the message has been written and no more calls to `logMsgPart` follow. */
    abstract void endMsg() nothrow @safe;

    /**
     * A custom logger must implement this method in order to capture log for forwardMsg call
     * Params:
     *  payload = All information associated with call to log function.
     */
    abstract void writeLog(ref LogEntry payload) nothrow @safe;

protected:
    Mutex mutex;

private:
    Object userContext_;
    string userName_;
    LoggerOption option;
}

/**
 * The default implementation will use an `std.array.appender`
 * internally to construct the message string. This means dynamic,
 * GC memory allocation.
 * A logger can avoid this allocation by
 * reimplementing `beginMsg`, `logMsgPart` and `endMsg`.
 * `beginMsg` is always called first, followed by any number of calls
 * to `logMsgPart` and one call to `endMsg`.
 *
 * As an example for such a custom `Logger` compare this:
----------------
class CustomLogger : Logger
{
    this(LoggerOption option = LoggerOption.init) nothrow @safe
    {
        super(option);
    }

    protected override void beginMsg(ref Logger.LogHeader header) nothrow @safe
    {
        ... logic here
    }

    protected override void commitMsg(const(char)[] msg) nothrow @safe
    {
        ... logic here
    }

    protected override void endMsg() nothrow @safe
    {
        ... logic here
    }

    protected override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        this.beginMsg(payload.header);
        this.commitMsg(payload.msg);
        this.endMsg();
    }
}
----------------
 */
class MemLogger : Logger
{
@safe:

public:
    this(LoggerOption option = LoggerOption.init) nothrow
    {
        super(option);
    }

protected:
    override void beginMsg(ref Logger.LogHeader header) nothrow
    {
        version (DebugLogger) debug writeln("MemLogger.beginMsg()");

        static if (isStaticLoggingActive)
        {
            msgBuffer = Appender!string();
            msgBuffer.reserve(1000);
            logEntry = Logger.LogEntry(this, header, null);
        }
    }

    override void commitMsg(scope const(char)[] msg) nothrow
    {
        version (DebugLogger) debug writeln("MemLogger.commitMsg()");

        static if (isStaticLoggingActive)
        {
            msgBuffer.put(msg);
        }
    }

    override void endMsg() nothrow
    {
        version (DebugLogger) debug writeln("MemLogger.endMsg()");

        static if (isStaticLoggingActive)
        {
            this.logEntry.message = msgBuffer.data;
            this.writeLog(logEntry);
            // Reset to release its memory
            this.logEntry = Logger.LogEntry.init;
            this.msgBuffer = Appender!string();
        }
    }

    override void writeLog(ref Logger.LogEntry payload) nothrow
    {}

protected:
    Appender!string msgBuffer;
    Logger.LogEntry logEntry;
}

/// An option to create $(LREF FileLogger) directory if it is non-existent.
alias CreateFolder = Flag!"CreateFolder";

class ConsoleLogger : MemLogger
{
import std.stdio : stdout;

@safe:

public:
    this(LoggerOption option = LoggerOption.init) nothrow
    {
        super(option);
    }

protected:
    File trustedStdout() @trusted
    {
        return stdout;
    }

    final override void writeLog(ref Logger.LogEntry payload) nothrow
    {
        version (DebugLogger) debug writeln("ConsoleLogger.writeLog()");

        try
        {
            auto writer = LogOutputWriter(this);
            writer.write(trustedStdout().lockingTextWriter(), payload);
            if (flushWriteLogLines++ >= flushOutputLines)
            {
                trustedStdout().flush();
                flushWriteLogLines = 0;
            }
        }
        catch (Exception e)
        {
            version (DebugLogger) debug writeln(e.msg);
        }
    }

protected:
    size_t flushWriteLogLines;
}

/**
 * This `Logger` implementation writes log messages to the associated
 * file. The name of the file has to be passed on construction time.
 */
class FileLogger : MemLogger
{
import std.file : exists, mkdirRecurse;
import std.path : dirName;

@safe:

public:
    /**
     * A constructor for the `FileLogger` Logger.
     * Params:
     *  fileName = The filename of the output file of the `FileLogger`. If that
     *      file can not be opened for writting, logLevel will switch to off.
     *  openMode = file mode open for appending or writing new file, default is appending
     *  option = default log option
     *  createFileFolder = if yes and fileName contains a folder name, this
     *      folder will be created.
     *
     * Example:
     *  auto l1 = new FileLogger("logFile.log");
     *  auto l2 = new FileLogger("logFile.log", "w");
     *  auto l3 = new FileLogger("logFile.log", "a", LoggerOption(defaultOutputHeaderPatterns, LogLevel.fatal));
     *  auto l3 = new FileLogger("logFolder/logFile.log", "a", LoggerOption(defaultOutputHeaderPatterns, LogLevel.fatal), CreateFolder.yes);
     */
    this(const string fileName, string openMode = "a",
        LoggerOption option = LoggerOption.init,
        CreateFolder createFileFolder = CreateFolder.yes) nothrow
    {
        try
        {
            if (createFileFolder)
            {
                auto d = dirName(fileName);
                mkdirRecurse(d);
            }

            this.file_.open(fileName, openMode == "w" ? openMode : "a");
        }
        catch (Exception)
        {
            option.logLevel = LogLevel.off;
        }

        super(option);
        this.fileName_ = fileName;
        this.fileOpened_ = true;
    }

    /**
     * A constructor for the `FileLogger` Logger that takes a reference to a `File`.
     * The `File` passed must be open for all the log call to the
     * `FileLogger`. If the `File` gets closed, using the `FileLogger`
     * for logging will result in undefined behaviour.
     * Params:
     *  file = The file used for logging.
     *  option = default log option
     * Example:
     *  auto file = File("logFile.log", "w");
     *  auto l1 = new FileLogger(file);
     *  auto l2 = new FileLogger(file, LoggerOption(defaultOutputHeaderPatterns, LogLevel.fatal));
     */
    this(File file, LoggerOption option = LoggerOption.init)
    {
        super(option);
        this.file_ = file;
        this.fileOpened_ = false;
    }

    ~this() nothrow
    {
        try
        {
            if (fileOpened_ && file_.isOpen)
                file_.close();
            file_ = File.init;
            fileName_ = null;
            fileOpened_ = false;
        }
        catch (Exception)
        {}
    }

    /**
     * If the `FileLogger` is managing the `File` it logs to, this
     * method will return a reference to this File.
     */
    @property final File file() nothrow
    {
        return this.file_;
    }

    /**
     * If the `FileLogger` was constructed with a fileName, this method
     * returns this fileName. Otherwise an empty `string` is returned.
     */
    @property final string fileName() const nothrow pure
    {
        return this.fileName_;
    }

protected:
    final override void writeLog(ref Logger.LogEntry payload) nothrow
    {
        version (DebugLogger) debug writeln("FileLogger.writeLog()");

        try
        {
            auto writer = LogOutputWriter(this);
            writer.write(file_.lockingTextWriter(), payload);
            if (flushWriteLogLines++ >= flushOutputLines)
            {
                file_.flush();
                flushWriteLogLines = 0;
            }
        }
        catch (Exception e)
        {
            version (DebugLogger) debug writeln(e.msg);
        }
    }

protected:
    File file_; /// The `File` log messages are written to.
    string fileName_; // The filename of the `File` log messages are written to.
    size_t flushWriteLogLines;
    bool fileOpened_;
}

/**
 * The `NullLogger` will not process any log messages.
 * In case of a log message with `LogLevel.fatal` nothing will happen.
 * By default the `LogLevel` for `NullLogger` is `LogLevel.all`.
 */
class NullLogger : Logger
{
public:
    this() nothrow @safe
    {
        super(LoggerOption(lowestLogLevel, "Null", "", size_t.max));
    }

    final override void forwardLog(ref Logger.LogEntry payload) nothrow @safe
    {}

protected:
    final override void doFatal() nothrow @safe
    {}

    final override void beginMsg(ref Logger.LogHeader header) nothrow @safe
    {}

    final override void endMsg() nothrow @safe
    {}

    final override void commitMsg(scope const(char)[] msg) nothrow @safe
    {}

    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {}
}

struct LogArgumentWriter
{
nothrow @safe:

public:
    this(Logger logger)
    {
        this.logger = logger;
    }

    void put(scope const(char)[] msgText)
    {
        version (DebugLogger) debug writeln("put.char[]");

        logger.commitMsg(msgText);
    }

    void put(dchar msgChar)
    {
        version (DebugLogger) debug writeln("put.dchar");

        char[4] buffer;
        const len = encode!(Yes.useReplacementDchar)(buffer, msgChar);
        logger.commitMsg(buffer[0..len]);
    }

    void put(Args...)(Args args) @trusted
    {
        version (DebugLogger) debug writeln("put...");

        try
        {
            foreach (arg; args)
            {
                alias argType = typeof(arg); //Args[i];
                static if (!is(isSomeString!(argType)) && isDynamicArray!(argType) && is(typeof(Unqual!(argType.init[0])) == ubyte))
                {
                    auto argBytes = cast(const(ubyte)[])arg;
                    logger.commitMsg(toHexString(argBytes));
                }
                else
                    logger.commitMsg(to!string(arg)); // Need to use 'to' function to convert to avoid cycle calls vs put(char[])
            }
        }
        catch (Exception e)
        {
            version (DebugLogger) debug writeln(e.msg);
        }
    }

    void putf(Args...)(scope const(char)[] fmt, Args args) @trusted
    {
        version (DebugLogger) debug writeln("putf...");

        try
        {
            formattedWrite(this, fmt, args);
        }
        catch (Exception e)
        {
            version (DebugLogger) debug writeln(e.msg);
        }
    }

    static string toHexString(scope const(ubyte)[] bytes) @trusted
    {
        import std.ascii : hexDigits = hexDigits;
        import std.exception : assumeUnique;

        auto result = new char[bytes.length*2];
        size_t i;
        foreach (b; bytes)
        {
            result[i++] = hexDigits[b >> 4];
            result[i++] = hexDigits[b & 0xF];
        }
        return assumeUnique(result);
    }

private:
    Logger logger;
}

struct LogOutputPatternElement
{
nothrow @safe:

public:
    enum Kind : byte
    {
        literal,
        pattern
    }

public:
    uint calPadLength(int padLength, const(size_t) valueLength) const pure @nogc
    {
        if (padLength <= 0)
            return 0u;

        if (maxLength > 0 && padLength > maxLength)
            padLength = maxLength;

        return padLength > valueLength ? padLength - valueLength : 0u;
    }

    pragma(inline, true)
    bool isTruncateLeft() const pure @nogc
    {
        return leftPad > 0;
    }

    pragma(inline, true)
    bool isTruncateLength(size_t valueLength) const pure @nogc
    {
        return maxLength > 0 && valueLength > maxLength;
    }

    void resetPattern()
    {
        fmt = pattern = null;
        detailLevel = maxLength = leftPad = rightPad = 0;
        // Must leave value & kind members alone
    }

    void setAsLiteral()
    {
        resetPattern();
        kind = Kind.literal;
    }

public:
    string fmt;
    string pattern;
    string value;
    uint detailLevel;
    int leftPad;
    int maxLength;
    int rightPad;
    Kind kind;
}

struct LogOutputPatternParser
{
nothrow @safe:

public:
    this(string outputPattern)
    {
        this.outputPattern_ = outputPattern;
    }

    LogOutputPatternElement.Kind next(out LogOutputPatternElement element)
    in
    {
        assert(!empty);
    }
    do
    {
        element.resetPattern();
        bool inFormat = false;
        size_t bMarker = notSet;
        size_t i = 0;
        while (i < outputPattern_.length)
        {
            const c = outputPattern_[i];

            if (bMarker != notSet && c == OutputPatternMarker.format)
            {
                if (!inFormat)
                    inFormat = true;
                // Escape ' - two consecutive chars ''
                else if (isSameNext(outputPattern_, i + 1, c))
                    i++;
                else
                    inFormat = false;
                i++;
                continue;
            }

            if (c == OutputPatternMarker.terminator)
            {
                if (bMarker == notSet)
                {
                    // Any leading literal?
                    if (i > 0)
                    {
                        element.value = outputPattern_[0..i];
                        element.kind = LogOutputPatternElement.Kind.literal;
                        outputPattern_ = outputPattern_[i..$];
                        return element.kind;
                    }

                    bMarker = i;
                }
                // Escape % - two consecutive chars %%
                else if (i == bMarker + 1)
                {
                    element.value = null;
                    element.value ~= c;
                    element.kind = LogOutputPatternElement.Kind.literal;
                    outputPattern_ = outputPattern_[i + 1..$];
                    return element.kind;
                }
                else if (!inFormat)
                {
                    element.value = outputPattern_[0..i + 1]; // Inclusive markers
                    element.kind = LogOutputPatternElement.Kind.pattern;
                    outputPattern_ = outputPattern_[i + 1..$];
                    return parseElement(element);
                }
            }
            i++;
        }

        // Not found any marker or only one marker
        element.value = outputPattern_;
        element.kind = LogOutputPatternElement.Kind.literal;
        outputPattern_ = null;
        return element.kind;
    }

    static LogOutputPatternElement.Kind parseElement(ref LogOutputPatternElement element) nothrow @safe
    in
    {
        assert(element.kind == LogOutputPatternElement.Kind.pattern);
        assert(element.value.length > 2);
        assert(element.value[0] == OutputPatternMarker.terminator && element.value[$ - 1] == OutputPatternMarker.terminator);
    }
    do
    {
        element.pattern = element.value[1..$ - 1];
        if (element.pattern.length)
            parseElementPads(element);
        if (element.pattern.length)
            parseElementFormat(element);
        // Invalid?
        if (element.pattern.length == 0)
            element.setAsLiteral();
        return element.kind;
    }

    @property bool empty() const pure
    {
        return outputPattern_.length == 0;
    }

private:
    static bool isSameNext(string s, size_t n, char c) nothrow pure @safe
    {
        return n < s.length && s[n] == c;
    }

    static void parseElementFormat(ref LogOutputPatternElement element) nothrow @safe
    {
        if (element.pattern[0] != OutputPatternMarker.format)
            return;

        Appender!string fmtBuffer;
        fmtBuffer.reserve(element.pattern.length);
        size_t i = 1;
        while (i < element.pattern.length)
        {
            const c = element.pattern[i];
            if (c == OutputPatternMarker.format)
            {
                // Escape ' - two consecutive chars ''
                if (isSameNext(element.pattern, i + 1, c))
                {
                    fmtBuffer.put(c);
                    i += 2;
                }
                else
                {
                    element.fmt = fmtBuffer.data;
                    element.pattern = element.pattern[i + 1..$];
                    return;
                }
            }
            else
            {
                fmtBuffer.put(c);
                i++;
            }
        }

        // Invalid format
        element.setAsLiteral();
    }

    static void parseElementPads(ref LogOutputPatternElement element) nothrow @safe
    {
        size_t bMarker = notSet;
        size_t i = 0;

        int getPad() nothrow @safe
        {
            scope (failure) assert(0);

            auto result = to!int(element.pattern[bMarker..i]);
            element.pattern = element.pattern[i + 1..$];
            bMarker = notSet;
            i = 0;
            return result;
        }

        while (i < element.pattern.length)
        {
            switch (element.pattern[i])
            {
                case '0': .. case '9':
                    if (bMarker == notSet)
                        bMarker = i;
                    i++;
                    break;
                case OutputPatternMarker.detailLevel:
                    // Invalid?
                    if (bMarker == notSet)
                    {
                        element.setAsLiteral();
                        return;
                    }
                    element.detailLevel = getPad();
                    break;
                case OutputPatternMarker.maxLength:
                    // Invalid?
                    if (bMarker == notSet)
                    {
                        element.setAsLiteral();
                        return;
                    }
                    element.maxLength = getPad();
                    break;
                case OutputPatternMarker.padLeft:
                    // Invalid?
                    if (bMarker == notSet)
                    {
                        element.setAsLiteral();
                        return;
                    }
                    element.leftPad = getPad();
                    break;
                case OutputPatternMarker.padRight:
                    // Invalid?
                    if (bMarker == notSet)
                    {
                        element.setAsLiteral();
                        return;
                    }
                    element.rightPad = getPad();
                    break;
                default:
                    i = size_t.max; // done
                    break;
            }
        }
    }

private:
    enum notSet = size_t.max;

    string outputPattern_;
}

struct LogOutputWriter
{
import std.range.primitives : put;
import std.algorithm.comparison : max, min;
import std.format : format, formattedWrite;

alias format = pham.external.std.log.date_time_format.format;
alias formattedWrite = pham.external.std.log.date_time_format.formattedWrite;
alias pad = pham.external.std.log.date_time_format.pad;

@safe:

version (Windows)
    enum char dirSeparator = '\\';
else
    enum char dirSeparator = '/';

    // 5 chars for log text alignment
    static immutable string[LogLevel.max + 1] logLevelTexts = [
        "trace", "debug", "info ", "warn ", "error", "criti", "fatal", "off  "
    ];

    static immutable string newLineLiteral = "\n";

    enum usePrettyFuncNameDetailLevel = 4;

public:
    this(Logger logger)
    {
        this.logger = logger;
    }

    static string arrayOfChar(size_t count, char c) nothrow pure
    {
        auto result = new char[count];
        result[] = c;
        return result.idup;
    }

    static string date(const ref LogOutputPatternElement element, in SysTime value) nothrow @trusted
    {
        scope (failure) return null;
        // %s=FmtTimeSpecifier.sortableDateTime
        auto s = element.fmt.length != 0 ? format(element.fmt, value) : format("%s", value);
        return pad(element, s);
    }

    static void date(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, in SysTime value) nothrow @trusted
    {
        scope (failure) return;
        // %s=FmtTimeSpecifier.sortableDateTime
        ShortStringBuffer!char s;
        if (element.fmt.length)
            formattedWrite(s, element.fmt, value);
        else
            formattedWrite(s, "%s", value);
        const lp = padLeft(sink, element, s.length);
        put(sink, s[]);
        padRight(sink, element, s.length + lp);
    }

    static string fileName(const ref LogOutputPatternElement element, string fileName) nothrow
    {
        return text(element, separatedStringPart(fileName, dirSeparator, element.detailLevel + 1));
    }

    static void fileName(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, string fileName) nothrow
    {
        text(sink, element, separatedStringPart(fileName, dirSeparator, element.detailLevel + 1));
    }

    static string funcName(const ref LogOutputPatternElement element, string funcName, string prettyFuncName) nothrow
    {
        const detailLevel = element.detailLevel;
        return text(element, detailLevel >= usePrettyFuncNameDetailLevel ? prettyFuncName : separatedStringPart(funcName, '.', detailLevel + 1));
    }

    static void funcName(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, string funcName, string prettyFuncName) nothrow
    {
        const detailLevel = element.detailLevel;
        text(sink, element, detailLevel >= usePrettyFuncNameDetailLevel ? prettyFuncName : separatedStringPart(funcName, '.', detailLevel + 1));
    }

    static string integer(I)(const ref LogOutputPatternElement element, I value) nothrow
    if (isIntegral!I)
    {
        scope (failure) return null;
        auto s = element.fmt.length != 0 ? format(element.fmt, value) : format("%s", value);
        return pad(element, s);
    }

    static void integer(Writer, I)(auto ref Writer sink, const ref LogOutputPatternElement element, I value) nothrow
    if (isIntegral!I)
    {
        scope (failure) return;
        ShortStringBuffer!char s;
        if (element.fmt.length)
            formattedWrite(s, element.fmt, value);
        else
            formattedWrite(s, "%s", value);
        const lp = padLeft(sink, element, s.length);
        put(sink, s[]);
        padRight(sink, element, s.length + lp);
    }

    static string logLevel(const ref LogOutputPatternElement element, LogLevel value) nothrow
    {
        return text(element, logLevelTexts[value]);
    }

    static void logLevel(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, LogLevel value) nothrow
    {
        text(sink, element, logLevelTexts[value]);
    }

    static string newLine(const ref LogOutputPatternElement element) nothrow
    {
        return newLineLiteral;
    }

    static void newLine(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element) nothrow
    {
        scope (failure) return;
        put(sink, newLineLiteral);
    }

    static string pad(const ref LogOutputPatternElement element, string value) nothrow
    {
        // No pad - Truncate
        if (element.isTruncateLength(value.length))
        {
            return element.isTruncateLeft()
                ? value[($ - element.maxLength)..$] // Get ending value if left pad
                : value[0..element.maxLength]; // Get beginning value if right pad
        }

        if (const p = element.calPadLength(element.leftPad, value.length))
            value = arrayOfChar(p, ' ') ~ value;

        if (const p = element.calPadLength(element.rightPad, value.length))
            value = value ~ arrayOfChar(p, ' ');

        return value;
    }

    static uint padLeft(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, size_t valueLength) nothrow
    {
        scope (failure) return 0u;
        if (const p = element.calPadLength(element.leftPad, valueLength))
        {
            uint n = p;
            while (n--)
                put(sink, ' ');
            return p;
        }
        else
            return 0u;
    }

    static uint padRight(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, size_t valueLength) nothrow
    {
        scope (failure) return 0u;
        if (const p = element.calPadLength(element.rightPad, valueLength))
        {
            uint n = p;
            while (n--)
                put(sink, ' ');
            return p;
        }
        else
            return 0u;
    }

    static string separatedStringPart(string separatedString, char separator, size_t count) nothrow pure @safe
    {
        if (count == 0)
            return null;

        size_t separatedStringLength = separatedString.length;
        while (separatedStringLength)
        {
            separatedStringLength--;
            if (separatedString[separatedStringLength] == separator)
            {
                if (--count == 0)
                    return separatedString[(separatedStringLength + 1)..$];
            }
        }
        return separatedString;
    }

    static string text(const ref LogOutputPatternElement element, string value) nothrow
    {
        scope (failure) return null;
        if (element.fmt.length)
            value = format(element.fmt, value);
        return pad(element, value);
    }

    static void text(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, string value) nothrow
    {
        scope (failure) return;
        if (element.fmt.length)
        {
            ShortStringBuffer!char s;
            formattedWrite(sink, element.fmt, value);
            const lp = padLeft(sink, element, s.length);
            put(sink, s[]);
            padRight(sink, element, s.length + lp);
        }
        else
        {
            const lp = padLeft(sink, element, value.length);
            put(sink, value);
            padRight(sink, element, value.length + lp);
        }
    }

    static string timestamp(const ref LogOutputPatternElement element, in SysTime value) nothrow
    {
        return integer(element, (value - appStartupTimestamp).total!"msecs");
    }

    static void timestamp(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, in SysTime value) nothrow
    {
        integer(sink, element, (value - appStartupTimestamp).total!"msecs");
    }

    static string userContext(const ref LogOutputPatternElement element, Object value) nothrow @trusted
    {
        scope (failure) return null;
        return value !is null ? text(element, to!string(value)) : text(element, null);
    }

    static void userContext(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, Object value) nothrow @trusted
    {
        scope (failure) return;
        if (value !is null)
            text(sink, element, to!string(value));
        else
            text(sink, element, null);
    }

    void write(Writer)(auto scope ref Writer sink, ref Logger.LogEntry payload) @trusted
    {
        auto patternParser = LogOutputPatternParser(logger.outputPattern);
        while (!patternParser.empty)
        {
            LogOutputPatternElement element = void;
            const elementKind = patternParser.next(element);
            final switch (elementKind) with (LogOutputPatternElement.Kind)
            {
                case literal:
                    put(sink, element.value);
                    break;
                case pattern:
                    // Try matching a support pattern
                    switch (element.pattern)
                    {
                        case OutputPatternName.userContext:
                            userContext(sink, element, payload.logger.userContext);
                            break;
                        case OutputPatternName.date:
                            date(sink, element, payload.header.timestamp);
                            break;
                        case OutputPatternName.filename:
                            fileName(sink, element, payload.header.fileName);
                            break;
                        case OutputPatternName.level:
                            logLevel(sink, element, payload.header.logLevel);
                            break;
                        case OutputPatternName.line:
                            integer(sink, element, payload.header.line);
                            break;
                        case OutputPatternName.logger:
                            text(sink, element, payload.logger.name);
                            break;
                        case OutputPatternName.message:
                            text(sink, element, payload.message);
                            break;
                        case OutputPatternName.method:
                            funcName(sink, element, payload.header.funcName, payload.header.prettyFuncName);
                            break;
                        case OutputPatternName.newLine:
                            newLine(sink, element);
                            break;
                        case OutputPatternName.stacktrace:
                            /// The stack trace of the logging event The stack trace level specifier may be enclosed between braces
                            //TODO
                            break;
                        case OutputPatternName.timestamp:
                            timestamp(sink, element, payload.header.timestamp);
                            break;
                        case OutputPatternName.thread:
                            integer(sink, element, payload.header.threadID);
                            break;
                        case OutputPatternName.username:
                            text(sink, element, payload.logger.userName);
                            break;
                        // Not matching any pattern, output as is
                        default:
                            put(sink, element.value);
                            break;
                    }
                    break;
            }
        }
    }

private:
    Logger logger;
}

struct LogTimming
{
import std.conv : text;

nothrow @safe:

public:
    @disable this(this);

    /**
     * Params:
     *  logger = Logger where logging message being written to
     *  logBeginEnd = if true, immediately write a log with message = "0"
     *  warnMsecs = Change log to warn when > 0 and at time of writing log with
     *      elapsed time in millisecond greater than this parameter value
     */
    this(Logger logger, string message,
        bool logBeginEnd = false,
        Duration warnMsecs = Duration.zero,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__,
        in string moduleName = __MODULE__)
    {
        this.message = message;
        this.payload.logger = logger;
        this.payload.header.logLevel = LogLevel.info;
        this.payload.header.line = line;
        this.payload.header.fileName = fileName;
        this.payload.header.funcName = funcName;
        this.payload.header.prettyFuncName = prettyFuncName;
        this.payload.header.moduleName = moduleName;
        this.payload.header.threadID = thisThreadID;
        this.logBeginEnd = logBeginEnd;
        this.warnMsecs = warnMsecs;
        this.done = false;
        if (this.payload.logger !is null)
        {
            if (logBeginEnd)
            {
                payload.message = logMessage(0, true);
                payload.header.logLevel = LogLevel.info;
                payload.header.timestamp = currTime();
                payload.logger.forwardLog(payload);
            }
            this.startedTimestamp = currTime();
        }
    }

    ~this()
    {
        if (canLog())
            log();
    }

    version (none) // Just use this instead: xxx = LogTimming.init;
    static typeof(this) opCall()
    {
        return LogTimming(null, false, 0, 0, null, null, null, null);
    }

    bool canLog()
    {
        return !done && payload.logger !is null;
    }

    void log()
    {
        if (payload.logger !is null)
        {
            payload.header.timestamp = currTime();
            const elapsed = payload.header.timestamp - startedTimestamp;
            payload.header.logLevel = warnMsecs > Duration.zero && elapsed >= warnMsecs ? LogLevel.warn : LogLevel.info;
            payload.message = logMessage(elapsed.total!"msecs", false);
            payload.logger.forwardLog(payload);
        }
        done = true;
    }

    void logAndReset()
    {
        log();
        done = false;
        if (payload.logger !is null)
        {
            if (logBeginEnd)
            {
                payload.message = logMessage(0, true);
                payload.header.logLevel = LogLevel.info;
                payload.header.timestamp = currTime();
                payload.logger.forwardLog(payload);
            }
            startedTimestamp = currTime();
        }
    }

private:
    string logMessage(const(ulong) msecs, bool beginLog)
    {
        if (logBeginEnd)
        {
            const preMessage = beginLog ? "Begin" : "End";
            return text(to!string(msecs), ",", preMessage, ",", message);
        }
        else
            return text(to!string(msecs), ",", message);
    }

private:
    Logger.LogEntry payload;
    string message;
    SysTime startedTimestamp;
    Duration warnMsecs;
    bool done;
    bool logBeginEnd;
}

struct LogRAIIMutex
{
@nogc nothrow @safe:

public:
    @disable this();
    @disable this(ref typeof(this));
    @disable void opAssign(typeof(this));

    this(Mutex mutex)
    {
        this._locked = 0;
        this._mutex = mutex;
        lock();
    }

    ~this()
    {
        if (_locked > 0)
            unlock();
        _mutex = null;
    }

    void lock()
    {
        if (_locked++ == 0 && _mutex !is null)
            _mutex.lock_nothrow();
    }

    void unlock()
    in
    {
        assert(_locked > 0);
    }
    do
    {
        if (--_locked == 0 && _mutex !is null)
            _mutex.unlock_nothrow();
    }

    @property int locked() const pure
    {
        return _locked;
    }

private:
    Mutex _mutex;
    int _locked;
}

struct LogRestore
{
nothrow @safe:

public:
    this(Logger toSharedLog)
    in
    {
        assert(toSharedLog !is null);
    }
    do
    {
        this(toSharedLog, toSharedLog);
    }

    this(Logger toSharedLog, Logger toThreadLog)
    in
    {
        assert(toSharedLog !is null);
        assert(toThreadLog !is null);
    }
    do
    {
        this.done = false;
        this.save();

        sharedLog = toSharedLog;
        sharedLogLevel = toSharedLog.logLevel;

        threadLog = toThreadLog;
    }

    ~this()
    {
        if (!done)
            restore();
    }

    void restore()
    {
        if (!done)
        {
            savedThreadLog.logLevel = savedThreadLog_Level;
            threadLog = savedThreadLog;

            savedSharedLog.logLevel = savedSharedLog_Level;
            sharedLog = savedSharedLog;

            sharedLogLevel = savedSharedLogLevel;

            done = true;
        }
    }

private:
    void save()
    {
        savedSharedLogLevel = sharedLogLevel;

        savedSharedLog = sharedLog;
        savedSharedLog_Level = savedSharedLog.logLevel;

        savedThreadLog = threadLog;
        savedThreadLog_Level = savedThreadLog.logLevel;
    }

    Logger savedSharedLog, savedThreadLog;
    LogLevel savedSharedLog_Level, savedThreadLog_Level, savedSharedLogLevel;
    bool done;
}

immutable SysTime appStartupTimestamp;

SysTime currTime() nothrow @safe
{
    scope (failure) assert(0);

    return Clock.currTime;
}

/**
 * This methods get and set the global `LogLevel`.
 * Every log message with a `LogLevel` lower as the global `LogLevel`
 * will be discarded before it reaches `writeLogMessage` method of any `Logger`.
 */
@property LogLevel globalLogLevel() @nogc nothrow @safe
{
    /*
    Implementation note:
    For any public logging call, the global log level shall only be queried once on
    entry. Otherwise when another threads changes the level, we would work with
    different levels at different spots in the code.
    */
    return threadSafeLoad(globalLogLevel_);
}

/// Ditto
@property void globalLogLevel(LogLevel ll) nothrow @safe
{
    threadSafeStore(globalLogLevel_, ll);
}

/**
 * This property sets and gets the default `Logger`.
 * `sharedLog` is only thread-safe if the the used `Logger` is thread-safe.
 * The default `Logger` is thread-safe.
 * Example:
-------------
sharedLog = new FileLogger(yourFile);
-------------
 * The example sets a new `FileLogger` as new `sharedLog`.
 * If at some point you want to use the original default logger again, you can
 * use $(D sharedLog = null;). This will put back the original.
 * Note:
 *  While getting and setting `sharedLog` is thread-safe, it has to be considered
 *  that the returned reference is only a current snapshot and in the following
 *  code, you must make sure no other thread reassigns to it between reading and
 *  writing `sharedLog`.
-------------
if (sharedLog !is myLogger)
    sharedLog = new myLogger;
-------------
 */
@property Logger sharedLog() nothrow @trusted
{
    // If we have set up our own logger use that
    if (auto logger = threadSafeLoad(sharedLog_))
        return cast(Logger)logger;
    else
        return sharedLogImpl; // Otherwise resort to the default logger
}

/// Ditto
@property void sharedLog(Logger logger) nothrow @trusted
{
    threadSafeStore(sharedLog_, cast(shared)logger);
}

@property LogLevel sharedLogLevel() @nogc nothrow @safe
{
    return threadSafeLoad(sharedLogLevel_);
}

/// Ditto
@property void sharedLogLevel(LogLevel ll) nothrow @safe
{
    threadSafeStore(sharedLogLevel_, ll);
    if (auto logger = sharedLog)
        logger.logLevel = ll;
}

/**
 * This function returns a thread unique `Logger`, that by default
 * propergates all data logged to it to the `sharedLog`.
 * These properties can be used to set and get this `Logger`. Every
 * modification to this `Logger` will only be visible in the thread the
 * modification has been done from.
 * This `Logger` is called by the free standing log functions. This allows to
 * create thread local redirections and still use the free standing log
 * functions.
 */
@property Logger threadLog() nothrow @safe
{
    // If we have set up our own logger use that
    if (auto logger = threadLog_)
        return logger;
    else
        return threadLogImpl; // Otherwise resort to the default logger
}

/// Ditto
@property void threadLog(Logger logger) nothrow @safe
{
    threadLog_ = logger;
}

string currentUserName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetUserNameW;
        import std.exception : assumeWontThrow;

        wchar[256] result = void;
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return assumeWontThrow(to!string(result[0..len]));
        else
            return "";
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : getlogin_r;
        import std.exception : assumeWontThrow;

        char[256] result = void;
        uint len = result.length - 1;
        if (getlogin_r(&result[0], len) == 0)
            return assumeWontThrow(to!string(&result[0]));
        else
            return "";
    }
    else
    {
        pragma(msg, "currentUserName() not supported");
        return "";
    }
}

/// Thread safe to read value from a variable
auto threadSafeLoad(T)(ref shared T value) nothrow @safe
{
    return atomicLoad!(MemoryOrder.acq)(value);
}

/// Thread safe to write value to a variable
void threadSafeStore(T)(ref shared T dst, shared T src) nothrow @safe
{
    atomicStore!(MemoryOrder.rel)(dst, src);
}


private:

Logger threadLog_;
shared ModuleLoggerOptions moduleOptions_;
shared Logger sharedLog_;
shared LogLevel sharedLogLevel_ = defaultSharedLogLevel;
shared LogLevel globalLogLevel_ = lowestLogLevel;

class SharedLogger : FileLogger
{
public:
    this(File file, LoggerOption option = defaultOption()) @safe
    {
        super(file, option);
    }

    static LoggerOption defaultOption() nothrow @safe
    {
        return LoggerOption(defaultLogLevel, "SharedLogger", defaultOutputPattern, 5);
    }
}

/*
 * This method returns the global default Logger.
 * Marked @trusted because of excessive reliance on __gshared data
 */
__gshared SharedLogger sharedLogDefault_;
__gshared align(SharedLogger.alignof) void[__traits(classInstanceSize, SharedLogger)] sharedLogBuffer_;
@property Logger sharedLogImpl() nothrow @trusted
{
    import std.concurrency : initOnce;
    import std.stdio : stderr;

    scope (failure) assert(0);

    initOnce!(sharedLogDefault_)({
        auto buffer = cast(ubyte[])sharedLogBuffer_;
        return emplace!SharedLogger(buffer, stderr, SharedLogger.defaultOption());
    }());
    return sharedLogDefault_;
}

/**
 * The `ForwardSharedLogger` will always forward anything to the sharedLog.
 * The `ForwardSharedLogger` will not throw if data is logged with $(D
 * LogLevel.fatal).
 */
class ForwardSharedLogger : MemLogger
{
public:
    this(LoggerOption option = defaultOption()) nothrow @safe
    {
        super(option);
    }

    static LoggerOption defaultOption() nothrow @safe
    {
        return LoggerOption(sharedLogLevel, "ForwardSharedLogger", defaultOutputPattern, 0);
    }

protected:
    final override void doFatal() nothrow @safe
    {}

    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        version (DebugLogger) debug writeln("ForwardSharedLogger.writeLog()");

        sharedLog.forwardLog(payload);
    }
}

/*
 * This method returns the thread local default Logger for sharedLog.
 */
ForwardSharedLogger threadLogDefault_;
align(ForwardSharedLogger.alignof) void[__traits(classInstanceSize, ForwardSharedLogger)] threadLogBuffer_;
@property Logger threadLogImpl() nothrow @trusted
{
    if (threadLogDefault_ is null)
    {
        auto buffer = cast(ubyte[])threadLogBuffer_;
        threadLogDefault_ = emplace!ForwardSharedLogger(buffer, ForwardSharedLogger.defaultOption());
    }
    return threadLogDefault_;
}

shared static this()
{
    appStartupTimestamp = currTime();
    moduleOptions_ = cast(shared)(new ModuleLoggerOptions(null));
}

unittest // lastModuleSeparatorIndex
{
    assert("".lastModuleSeparatorIndex() == -1);
    assert("noPackage".lastModuleSeparatorIndex() == -1);
    assert("package.module".lastModuleSeparatorIndex() == 7);
}

unittest // moduleParentOf
{
    assert("".moduleParentOf().length == 0);
    assert("noPackage".moduleParentOf().length == 0);
    assert(".noPackage".moduleParentOf().length == 0);
    assert("package.module".moduleParentOf() == "package");
    assert("package1.package2.module".moduleParentOf() == "package1.package2");
}

///
@safe unittest // moduleLogLevel
{
    static assert(moduleLogLevel!"" == defaultStaticLogLevel);
}

///
@system unittest // moduleLogLevel
{
    static assert(moduleLogLevel!"not.amodule.path" == defaultStaticLogLevel);
}

@safe unittest // sharedLogLevel
{
    LogLevel ll = sharedLogLevel;
    scope (exit)
        sharedLogLevel = ll;

    sharedLogLevel = LogLevel.fatal;
    assert(sharedLogLevel == LogLevel.fatal);
}

@safe unittest
{
    assert(sharedLogLevel == defaultSharedLogLevel);

    auto dl = sharedLog;
    assert(dl !is null);
    assert(dl.logLevel == defaultLogLevel, to!string(dl.logLevel));

    auto tl = threadLog;
    assert(tl !is null);
    assert(tl.logLevel == defaultLogLevel, to!string(tl.logLevel));
}

@safe unittest // create NullLogger
{
    auto nl1 = new NullLogger();
    nl1.info("You will never read this.");
    nl1.fatal("You will never read this, either and it will not throw");
}

@safe unittest // create ForwardSharedLogger
{
    auto nl1 = new ForwardSharedLogger();
}

@safe unittest // LogOutputPatternParser
{
    import std.stdio : writeln;

    LogOutputPatternElement element;
    LogOutputPatternElement.Kind kind;

    // Default cases
    auto parser = LogOutputPatternParser(defaultOutputPattern);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.date && element.value == OutputPattern.date);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == " [" && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.level && element.value == OutputPattern.level);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == "] " && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.filename && element.value == OutputPattern.filename);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == "." && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.line && element.value == OutputPattern.line);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == "." && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.method && element.value == OutputPattern.method);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == ": " && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.message && element.value == OutputPattern.message);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.newLine && element.value == OutputPattern.newLine);

    assert(parser.empty);

    // Complex cases
    // enum outputPatternDetailLevelMarker = 'd';
    // enum outputPatternFormatMarker = '\'';
    // enum outputPatternMaxLengthMarker = 'm';
    // enum outputPatternPadLeftMarker = 'l'; // Lower case L
    // enum outputPatternPadRightMarker = 'r';
    auto complexPattern = "begin literal - "
        ~ OutputPatternMarker.terminator ~ "2l3r20m'%cmm/%cdd/%cyyyy'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator
        ~ " - some literal in between - "
        ~ OutputPatternMarker.terminator ~ "50m" ~ OutputPatternName.filename ~ OutputPatternMarker.terminator
        ~ OutputPatternMarker.terminator ~ "'2'' %s ''2'" ~ OutputPatternName.method ~ OutputPatternMarker.terminator
        ~ " - end literal";
    parser = LogOutputPatternParser(complexPattern);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == "begin literal - " && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.date && element.value == OutputPatternMarker.terminator ~ "2l3r20m'%cmm/%cdd/%cyyyy'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator);
    assert(element.leftPad == 2);
    assert(element.rightPad == 3);
    assert(element.maxLength == 20);
    assert(element.fmt == "%cmm/%cdd/%cyyyy");

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == " - some literal in between - " && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.filename && element.value == OutputPatternMarker.terminator ~ "50m" ~ OutputPatternName.filename ~ OutputPatternMarker.terminator);
    assert(element.maxLength == 50);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.method && element.value == OutputPatternMarker.terminator ~ "'2'' %s ''2'" ~ OutputPatternName.method ~ OutputPatternMarker.terminator);
    assert(element.fmt == "2' %s '2");

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == " - end literal" && element.pattern.length == 0);

    assert(parser.empty);
}

@safe unittest // LogOutputWriter.Functions
{
    import std.stdio : writeln;

    // pad
    LogOutputPatternElement padPattern;
    padPattern.maxLength = 20;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890aB") == "12345678901234567890"); // truncate from ending - default
    padPattern.rightPad = 2;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890aB") == "12345678901234567890"); // truncate from ending
    padPattern.leftPad = 2;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890aB") == "345678901234567890aB");
    padPattern.maxLength = padPattern.leftPad = padPattern.rightPad = 0;
    padPattern.leftPad = 22;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890") == "  12345678901234567890");
    padPattern.maxLength = padPattern.leftPad = padPattern.rightPad = 0;
    padPattern.rightPad = 22;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890") == "12345678901234567890  ");

    // date
    LogOutputPatternElement datePattern;
    auto timestamp = SysTime(DateTime(1, 1, 1, 1, 1, 1), msecs(1), null);
    version (DebugLogger) debug writeln(LogOutputWriter.date(datePattern, timestamp));
    assert(LogOutputWriter.date(datePattern, timestamp) == "0001-01-01T01:01:01.001000");

    // fileName
    immutable string fileName = "c:"
        ~ LogOutputWriter.dirSeparator ~ "directory"
        ~ LogOutputWriter.dirSeparator ~ "subdir"
        ~ LogOutputWriter.dirSeparator ~ "core.d";
    LogOutputPatternElement filePattern;
    assert(LogOutputWriter.fileName(filePattern, fileName) == "core.d");
    filePattern.detailLevel = 1;
    version (DebugLogger) debug writeln(LogOutputWriter.fileName(filePattern, fileName));
    assert(LogOutputWriter.fileName(filePattern, fileName) == "subdir"
           ~ LogOutputWriter.dirSeparator ~ "core.d");
    filePattern.detailLevel = 2;
    assert(LogOutputWriter.fileName(filePattern, fileName) == "directory"
           ~ LogOutputWriter.dirSeparator ~ "subdir"
           ~ LogOutputWriter.dirSeparator ~ "core.d");
    filePattern.detailLevel = 100;
    assert(LogOutputWriter.fileName(filePattern, fileName) == fileName);

    // funcName
    immutable string funcName = "core.Point.dot";
    immutable string prettyFuncName = "double core.Point.dot(Point rhs)";
    LogOutputPatternElement funcPattern;
    assert(LogOutputWriter.funcName(funcPattern, funcName, prettyFuncName) == "dot");
    funcPattern.detailLevel = 1;
    assert(LogOutputWriter.funcName(funcPattern, funcName, prettyFuncName) == "Point.dot");
    funcPattern.detailLevel = 2;
    assert(LogOutputWriter.funcName(funcPattern, funcName, prettyFuncName) == "core.Point.dot");
    funcPattern.detailLevel = LogOutputWriter.usePrettyFuncNameDetailLevel; // Any number >= LogOutputPatternElement.usePrettyFuncNameDetailLevel
    assert(LogOutputWriter.funcName(funcPattern, funcName, prettyFuncName) == prettyFuncName);

    // integer
    LogOutputPatternElement intPattern;
    assert(LogOutputWriter.integer(intPattern, 1) == "1");
    intPattern.fmt = "%,d";
    intPattern.leftPad = 6;
    assert(LogOutputWriter.integer(intPattern, 1_000) == " 1,000");

    // text
    LogOutputPatternElement textPattern;
    assert(LogOutputWriter.text(textPattern, "a") == "a");
    textPattern.fmt = "Happy %s!";
    textPattern.rightPad = 15;
    assert(LogOutputWriter.text(textPattern, "Tet") == "Happy Tet!     ");

    // userContext
    auto context = new TestLoggerCustomContext();
    LogOutputPatternElement contextPattern;
    assert(LogOutputWriter.userContext(contextPattern, context) == TestLoggerCustomContext.customContext);
    assert(LogOutputWriter.userContext(contextPattern, null).length == 0);
}

version (unittest)
package(pham.external.std.log)
{
    enum defaultUnitTestLogLevel = lowestLogLevel;

    class TestLoggerCustomContext
    {
        override string toString() nothrow @safe
        {
            return customContext;
        }

        static immutable customContext = "Additional context";
    }

    class TestLogger : MemLogger
    {
    public:
        this(LoggerOption option = defaultOption()) nothrow @safe
        {
            super(option);
            this.userContext = new TestLoggerCustomContext();
        }

        final string debugString(int expectedLine, LogLevel expectedLogLevel) nothrow @safe
        {
            scope (failure) assert(0);

            return "logLevel=" ~ to!string(logLevel) ~ " vs expectedLogLevel=" ~ to!string(expectedLogLevel)
                ~ ", lvl=" ~ to!string(lvl)
                ~ ", line=" ~ to!string(line) ~ (expectedLine != 0 ? " vs expectedline=" ~ to!string(expectedLine) : "")
                ~ ", msg=" ~ msg;
        }

        static LoggerOption defaultOption() nothrow pure @safe
        {
            return LoggerOption(defaultUnitTestLogLevel, "TestLogger", defaultOutputPattern, 0);
        }

        final void reset() nothrow pure @safe
        {
            lvl = defaultUnitTestLogLevel;
            line = 0;
            file = func = outputMessage = prettyFunc = msg = null;
        }

    protected:
        // Do not terminated testing process
        final override void doFatal() nothrow @safe
        {}

        final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
        {
            scope (failure) assert(0);

            version (DebugLogger) debug writeln("TestLogger.writeLog().payload.header.logLevel=", payload.header.logLevel, ", funcName=", payload.header.funcName, ", message=", payload.message);

            this.lvl = payload.header.logLevel;
            this.line = payload.header.line;
            this.file = payload.header.fileName;
            this.func = payload.header.funcName;
            this.prettyFunc = payload.header.prettyFuncName;
            this.msg = payload.message;

            auto buffer = Appender!string();
            buffer.reserve(500);
            auto writer = LogOutputWriter(this);
            writer.write(buffer, payload);
            this.outputMessage = buffer.data;
        }

    public:
        LogLevel lvl;
        int line;
        string file;
        string func;
        string outputMessage;
        string prettyFunc;
        string msg;
    }
}

version (unittest)
void testFuncNames(Logger logger) @safe
{
    static string s = "I'm here";
    logger.log(s);
}

@safe unittest
{
    void dummy() @safe
    {
        auto tl = new TestLogger();
        auto dst = LogArgumentWriter(tl);
        dst.put("aaa", "bbb");
    }

    dummy();
}

@safe unittest
{
    auto tl1 = new TestLogger();
    testFuncNames(tl1);
    version (DebugLogger) debug writeln("tl1.func=", tl1.func, ", tl1.prettyFunc=", tl1.prettyFunc, ", tl1.msg=", tl1.msg);
    assert(tl1.func == "pham.external.std.log.logger.testFuncNames", tl1.func);
    assert(tl1.prettyFunc == "void pham.external.std.log.logger.testFuncNames(Logger logger) @safe", tl1.prettyFunc);
    assert(tl1.msg == "I'm here", tl1.msg);
}

@safe unittest
{
    import std.conv : to;

    int line;
    auto tl1 = new TestLogger();
    tl1.log(""); line = __LINE__;
    assert(tl1.line == line);
    tl1.log(true, ""); line = __LINE__;
    assert(tl1.line == line);
    tl1.log(false, "");
    assert(tl1.line == line);
    tl1.log(LogLevel.info, ""); line = __LINE__;
    assert(tl1.line == line);
    tl1.log(LogLevel.off, "");
    assert(tl1.line == line);
    tl1.log(LogLevel.info, true, ""); line = __LINE__;
    assert(tl1.line == line);
    tl1.log(LogLevel.info, false, "");
    assert(tl1.line == line);

    auto logRestore = LogRestore(tl1);

    log(to!string(__LINE__)); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    log(LogLevel.info, to!string(__LINE__)); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    log(true, to!string(__LINE__)); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    log(LogLevel.warn, true, to!string(__LINE__)); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    logTrace(to!string(__LINE__)); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));
}

@safe unittest
{
    import pham.external.std.log.multi_logger : MultiLogger;

    auto tl1 = new TestLogger();
    auto tl2 = new TestLogger();

    auto ml = new MultiLogger();
    ml.insertLogger("one", tl1);
    ml.insertLogger("two", tl2);

    string msg = "Hello Logger World";
    ml.log(msg); int lineNumber = __LINE__;
    assert(tl1.msg == msg);
    assert(tl1.line == lineNumber);
    assert(tl2.msg == msg);
    assert(tl2.line == lineNumber);

    ml.removeLogger("one");
    ml.removeLogger("two");
    auto n = ml.removeLogger("one");
    assert(n is null);
}

@safe unittest
{
    import std.conv : to;
    import std.format : format;

    auto l = new TestLogger();
    string msg = "Hello Logger World";
    l.log(msg); int lineNumber = __LINE__;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    l.log(true, msg); lineNumber = __LINE__;
    assert(l.msg == msg, l.msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    l.log(false, msg);
    assert(l.msg == msg);
    assert(l.line == lineNumber, to!string(l.line));
    assert(l.logLevel == defaultUnitTestLogLevel);

    msg = "%s Another message";
    l.logf(msg, "Yet"); lineNumber = __LINE__;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    l.logf(true, msg, "Yet"); lineNumber = __LINE__;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    l.logf(false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    l.logf(LogLevel.critical, false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    auto logRestore = LogRestore(l);

    assert(sharedLog.logLevel == defaultUnitTestLogLevel);

    msg = "Another message";
    log(msg); lineNumber = __LINE__;
    assert(l.logLevel == defaultUnitTestLogLevel);
    assert(l.line == lineNumber, to!string(l.line));
    assert(l.msg == msg, l.msg);

    log(true, msg); lineNumber = __LINE__;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    log(false, msg);
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    msg = "%s Another message";
    logf(msg, "Yet"); lineNumber = __LINE__;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    logf(true, msg, "Yet"); lineNumber = __LINE__;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    logf(false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);

    logf(LogLevel.critical, false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == defaultUnitTestLogLevel);
}

@safe unittest
{
    import std.conv : to;

    auto tl = new TestLogger();

    tl.info("a"); int l = __LINE__;
    assert(tl.line == l);
    assert(tl.msg == "a");
    assert(tl.logLevel == defaultUnitTestLogLevel);

    tl.trace("b"); l = __LINE__;
    assert(tl.msg == "b", tl.msg);
    assert(tl.line == l, to!string(tl.line));
}

// testing possible log conditions
@safe unittest
{
    import std.conv : to;
    import std.format : format;
    import std.string : indexOf;
    import std.conv : to;

    auto mem = new TestLogger();
    auto memS = new TestLogger();
    auto logRestore = LogRestore(memS);

    const levels = [LogLevel.trace, LogLevel.debug_,
        LogLevel.info, LogLevel.warn, LogLevel.error,
        LogLevel.critical, LogLevel.fatal, LogLevel.off];

    int value = 0;
    string valueS = to!string(value);
    string value2S = format("%d%d", value, value);
    foreach (gll; levels)
    {
        sharedLogLevel = gll;
        foreach (ll; levels)
        {
            mem.logLevel = ll;
            threadLog.logLevel = ll;
            foreach (cond; [true, false])
            {
                // Tests with logLevel parameter
                foreach (ll2; levels)
                {
                    const canLog = ll2 != LogLevel.off && ll != LogLevel.off && gll != LogLevel.off && ll2 >= ll && ll >= gll;

                    mem.log(ll2, valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS), mem.debugString(__LINE__, ll));
                    mem.log(ll2, valueS, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));
                    mem.log(ll2, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS), mem.debugString(__LINE__, ll));
                    mem.log(ll2, value, valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));

                    // Same 4 tests with condition parameter
                    mem.log(ll2, cond, valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                    mem.log(ll2, cond, valueS, value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));
                    mem.log(ll2, cond, value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                    mem.log(ll2, cond, value, valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));

                    // Same 8 tests for format functions
                    mem.logf(ll2, "%s", valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS));
                    mem.logf(ll2, "%s%d", valueS, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));
                    mem.logf(ll2, "%d", value); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS));
                    mem.logf(ll2, "%d%s", value, valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));

                    mem.logf(ll2, cond, "%s", valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                    mem.logf(ll2, cond, "%s%d", valueS, value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));
                    mem.logf(ll2, cond, "%d", value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                    mem.logf(ll2, cond, "%d%s", value, valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));

                    // Same 16 tests for sharedLog/threadLog functions
                    log(ll2, valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    log(ll2, valueS, value); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));
                    log(ll2, value); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    log(ll2, value, valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));

                    log(ll2, cond, valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    log(ll2, cond, valueS, value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));
                    log(ll2, cond, value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    log(ll2, cond, value, valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));

                    logf(ll2, "%s", valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    logf(ll2, "%s%d", valueS, value); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));
                    logf(ll2, "%d", value); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    logf(ll2, "%d%s", value, valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));

                    logf(ll2, cond, "%s", valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    logf(ll2, cond, "%s%d", valueS, value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));
                    logf(ll2, cond, "%d", value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                    logf(ll2, cond, "%d%s", value, valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));
                }

                const canLog = ll != LogLevel.off && gll != LogLevel.off && ll >= gll;

                mem.log(valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.log(valueS, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));
                mem.log(value); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.log(value, valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));

                mem.log(cond, valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.log(cond, valueS, value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));
                mem.log(cond, value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.log(cond, value, valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));

                mem.logf("%s", valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.logf("%s%d", valueS, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));
                mem.logf("%d", value); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.logf("%d%s", value, valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));

                mem.logf(cond, "%s", valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.logf(cond, "%s%d", valueS, value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));
                mem.logf(cond, "%d", value); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == valueS));
                mem.logf(cond, "%d%s", value, valueS); assert(!cond || !canLog || (mem.line == __LINE__ && mem.msg == value2S));

                log(valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                log(valueS, value); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));
                log(value); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                log(value, valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));

                log(cond, valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                log(cond, valueS, value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));
                log(cond, value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                log(cond, value, valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));

                logf("%s", valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                logf("%s%d", valueS, value); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));
                logf("%d", value); assert(!canLog || (memS.line == __LINE__ && memS.msg == valueS));
                logf("%d%s", value, valueS); assert(!canLog || (memS.line == __LINE__ && memS.msg == value2S));

                logf(cond, "%s", valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                logf(cond, "%s%d", valueS, value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));
                logf(cond, "%d", value); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == valueS));
                logf(cond, "%d%s", value, valueS); assert(!cond || !canLog || (memS.line == __LINE__ && memS.msg == value2S));
            }

            value++;
            valueS = to!string(value);
            value2S = format("%d%d", value, value);
        }
    }
}

// testing more possible log conditions
@safe unittest
{
    auto mem = new TestLogger();
    auto logRestore = LogRestore(mem);

    const levels = [LogLevel.trace, LogLevel.debug_,
        LogLevel.info, LogLevel.warn, LogLevel.error,
        LogLevel.critical, LogLevel.fatal, LogLevel.off];

    foreach (gll; levels)
    {
        sharedLogLevel = gll;
        foreach (ll; levels)
        {
            mem.logLevel = ll;
            foreach (tll; levels)
            {
                threadLog.logLevel = tll;
                foreach (cond; [true, false])
                {
                    assert(sharedLogLevel == gll);
                    assert(mem.logLevel == tll, mem.debugString(0, tll));

                    bool gllVSll = LogLevel.trace >= sharedLogLevel;
                    bool llVSgll = tll >= sharedLogLevel;
                    bool lVSll = LogLevel.trace >= tll;
                    bool gllOff = sharedLogLevel != LogLevel.off;
                    bool llOff = mem.logLevel != LogLevel.off;
                    bool tllOff = threadLog.logLevel != LogLevel.off;
                    bool tllVSll = tll >= ll;
                    bool tllVSgll = tll >= gll;
                    bool lVSgll = LogLevel.trace >= tll;

                    bool test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    bool testG = gllOff && llOff && tllOff && lVSgll && tllVSll && tllVSgll && cond;

                    mem.line = -1;
                    /*
                    writefln("gll(%3u) ll(%3u) cond(%b) test(%b)",
                        gll, ll, cond, test);
                    writefln("%b %b %b %b %b %b test2(%b)", llVSgll, gllVSll, lVSll,
                        gllOff, llOff, cond, test2);
                    */

                    mem.trace(__LINE__); int line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logTrace(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.trace(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logTrace(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.tracef("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logTracef("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.tracef(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logTracef(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = tll >= sharedLogLevel;
                    lVSll = LogLevel.info >= tll;
                    lVSgll = LogLevel.info >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll && lVSgll && cond;

                    mem.info(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logInfo(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.info(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logInfo(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.infof("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logInfof("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.infof(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logInfof(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = tll >= sharedLogLevel;
                    lVSll = LogLevel.warn >= tll;
                    lVSgll = LogLevel.warn >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll && lVSgll && cond;

                    mem.warn(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logWarn(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.warn(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logWarn(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.warnf("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logWarnf("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.warnf(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logWarnf(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = tll >= sharedLogLevel;
                    lVSll = LogLevel.critical >= tll;
                    lVSgll = LogLevel.critical >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll && lVSgll && cond;

                    mem.critical(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logCritical(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.critical(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logCritical(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.criticalf("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logCriticalf("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.criticalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logCriticalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = tll >= sharedLogLevel;
                    lVSll = LogLevel.fatal >= tll;
                    lVSgll = LogLevel.fatal >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll && lVSgll && cond;

                    mem.fatal(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logFatal(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.fatal(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logFatal(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.fatalf("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logFatalf("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.fatalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    logFatalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;
                }
            }
        }
    }
}

// Issue #5
@safe unittest
{
    import std.string : indexOf;

    auto tl = new TestLogger(LoggerOption(LogLevel.info, "Test", defaultOutputPattern, 0));
    auto logRestore = LogRestore(tl);

    logTrace("trace");
    assert(tl.msg.indexOf("trace") == -1);
}

// Issue #5
@safe unittest
{
    import std.string : indexOf;
    import pham.external.std.log.multi_logger : MultiLogger;

    auto logger = new MultiLogger(LoggerOption(LogLevel.error, "Multi", defaultOutputPattern, 0));
    auto tl = new TestLogger(LoggerOption(LogLevel.info, "Test", defaultOutputPattern, 0));
    logger.insertLogger("required", tl);
    auto logRestore = LogRestore(logger);

    logTrace("trace");
    assert(tl.msg.indexOf("trace") == -1, tl.msg);

    logInfo("info");
    assert(tl.msg.indexOf("info") == -1, tl.msg);

    logError("error");
    assert(tl.msg.indexOf("error") == 0, tl.msg);
}

// log objects with non-safe toString
@system unittest
{
    struct Test
    {
        string toString() const @system
        {
            return "test";
        }
    }

    auto tl = new TestLogger();
    tl.info(Test.init);
    assert(tl.msg == "test");
}

// check that thread-local logging does not propagate
// to shared logger
@system unittest
{
    import core.atomic, core.thread, std.concurrency;

    static shared logged_count = 0;

    static class TestLog : MemLogger
    {
    public:
        this()
        {
            super(LoggerOption(LogLevel.trace, "Test", defaultOutputPattern, 0));
            this.tid = thisThreadID;
        }

    protected:
        final override void writeLog(ref LogEntry payload) nothrow @safe
        {
            assert(this.tid == thisThreadID);
            atomicOp!"+="(logged_count, 1);
        }

    public:
        ThreadID tid;
    }

    static class IgnoredLog : MemLogger
    {
    public:
        this() nothrow
        {
            super(LoggerOption(LogLevel.trace, "Ignore", defaultOutputPattern, size_t.max));
        }

    protected:
        final override void writeLog(ref LogEntry payload) nothrow @safe
        {
            assert(false);
        }
    }

    auto logRestore = LogRestore(new IgnoredLog);

    Thread[] spawned;
    foreach (i; 0 .. 4)
    {
        spawned ~= new Thread({
            threadLog = new TestLog;
            logTrace("zzzzzzzzzz");
        });
        spawned[$-1].start();
    }
    foreach (t; spawned)
        t.join();
    assert(atomicOp!"=="(logged_count, 4));
}

// https://issues.dlang.org/show_bug.cgi?id=14940
@safe unittest
{
    import std.typecons : Nullable;

    Nullable!int a = 1;
    auto l = new TestLogger();
    l.infof("log: %s", a);
    assert(l.msg == "log: 1");
}

// Ensure @system toString methods work
@system unittest
{
    static immutable SystemToStringMsg = "SystemToString";

    static struct SystemToString
    {
        string toString() @system
        {
            return SystemToStringMsg;
        }
    }

    auto tl = new TestLogger();

    SystemToString sts;
    tl.logf("%s", sts);
    assert(tl.msg == SystemToStringMsg);
}

// https://issues.dlang.org/show_bug.cgi?id=17328
@safe unittest
{
    import std.format : format;

    ubyte[] data = [0];
    string s = format("%(%02x%)", data); // format 00
    assert(s == "00");

    auto tl = new TestLogger();

    tl.infof("%(%02x%)", data);    // infof    000

    size_t i;
    string fs = tl.msg;
    for (; i < s.length; ++i)
    {
        assert(s[s.length - 1 - i] == fs[fs.length - 1 - i], fs);
    }
    assert(fs.length == 2);
}

// https://issues.dlang.org/show_bug.cgi?id=15954
@safe unittest
{
    import std.conv : to;

    auto tl = new TestLogger();
    tl.log("123456789".to!wstring);
    assert(tl.msg == "123456789");
}

// https://issues.dlang.org/show_bug.cgi?id=16256
@safe unittest
{
    import std.conv : to;

    auto tl = new TestLogger();
    tl.log("123456789"d);
    assert(tl.msg == "123456789");
}

// https://issues.dlang.org/show_bug.cgi?id=15517
@system unittest
{
    import std.file : exists, remove, tempDir;
    import std.path : buildPath;
    import std.stdio : File;
    import std.string : indexOf;

    string fn = tempDir.buildPath("bug15517.log");
    scope (exit)
    {
        if (exists(fn))
            remove(fn);
    }

    auto fl = new FileLogger(fn, "w", LoggerOption(defaultUnitTestLogLevel, "Test", defaultOutputPattern, 0));
    scope (exit)
        fl.file.close();

    auto logRestore = LogRestore(fl);

    auto ts = [ "Test log 1", "Test log 2", "Test log 3"];
    foreach (t; ts)
    {
        log(t);
    }

    auto f = File(fn);
    auto byLine = f.byLine();
    assert(!byLine.empty);
    size_t idx;
    foreach (it; byLine)
    {
        assert(it.indexOf(ts[idx]) != -1, it);
        ++idx;
    }
}

@system unittest
{
    import std.array : empty;
    import std.file : deleteme, remove;
    import std.string : indexOf;

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    auto l = new FileLogger(filename);
    scope (exit)
        remove(filename);

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    l.logLevel = LogLevel.critical;
    l.log(LogLevel.warn, notWritten);
    l.log(LogLevel.critical, written);
    destroy(l);

    auto file = File(filename, "r");
    string readLine = file.readln();
    assert(readLine.indexOf(written) != -1, readLine);
    readLine = file.readln();
    assert(readLine.indexOf(notWritten) == -1, readLine);
}

@safe unittest
{
    import std.file : rmdirRecurse, exists, deleteme;
    import std.path : dirName;

    const string tmpFolder = dirName(deleteme);
    const string filepath = tmpFolder ~ "/bug15771/minas/oops/";
    const string filename = filepath ~ "output.txt";
    assert(!exists(filepath));

    auto f = new FileLogger(filename, "w", LoggerOption(defaultUnitTestLogLevel, "Test", defaultOutputPattern, 0));
    scope(exit) () @trusted
    {
        f.file.close();
        rmdirRecurse(tmpFolder ~ "/bug15771");
    }();

    f.log("Hello World!");
    assert(exists(filepath));
}

@system unittest
{
    import std.array : empty;
    import std.file : deleteme, remove;
    import std.string : indexOf;

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    auto file = File(filename, "w");
    scope (exit)
    {
        file.close();
        remove(filename);
    }
    auto l = new FileLogger(file);

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    l.logLevel = LogLevel.critical;
    l.log(LogLevel.warn, notWritten);
    l.log(LogLevel.critical, written);
    file.close();

    file = File(filename, "r");
    string readLine = file.readln();
    assert(readLine.indexOf(written) != -1, readLine);
    readLine = file.readln();
    assert(readLine.indexOf(notWritten) == -1, readLine);
}

@system unittest // default logger
{
    import std.file : deleteme, exists, remove;
    import std.stdio : File;
    import std.string : indexOf;

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    FileLogger l = new FileLogger(filename);
    scope (exit)
        remove(filename);

    auto logRestore = LogRestore(l);
    sharedLogLevel = LogLevel.critical;

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    assert(sharedLogLevel == LogLevel.critical);

    log(LogLevel.warn, notWritten);
    log(LogLevel.critical, written);

    l.file.close();

    auto file = File(filename, "r");
    scope (exit)
        file.close();
    assert(!file.eof);
    string readLine = file.readln();
    assert(readLine.indexOf(written) != -1, readLine);
    assert(readLine.indexOf(notWritten) == -1, readLine);
}

@system unittest
{
    import std.file : deleteme, remove;
    import std.stdio : File;
    import std.string : indexOf;
    import std.range.primitives;

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    auto l = new FileLogger(filename);
    scope (exit)
        remove(filename);
    l.logLevel = LogLevel.critical;
    auto logRestore = LogRestore(l);

    log(LogLevel.error, false, notWritten);
    log(LogLevel.critical, true, written);
    destroy(l);

    auto file = File(filename, "r");
    scope (exit)
        file.close();
    auto readLine = file.readln();
    assert(!readLine.empty, readLine);
    assert(readLine.indexOf(written) != -1);
    assert(readLine.indexOf(notWritten) == -1);
}

/// Ditto
@system unittest
{
    import std.file : deleteme, remove;

    auto fl = new FileLogger(deleteme ~ "-someFile.log");
    scope(exit)
        remove(deleteme ~ "-someFile.log");
    auto logRestore = LogRestore(fl, fl);

    auto tempLog = threadLog;
    destroy(tempLog);
}

@safe unittest // LogOutputWriter
{
    import std.array : Appender;
    import std.conv : to;
    import std.stdio : writeln;

    string testMessage = "message text";
    auto tl = new TestLogger();
    LogOutputPatternElement blankPattern, datePattern;
    SysTime atTimestamp;
    string atfileName, atfuncName, atprettyFuncName;
    int atLine;

    datePattern.fmt = "%S";

    void setFunctionInfo(in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__)
    {
        atfileName = fileName;
        atfuncName = funcName;
        atprettyFuncName = prettyFuncName;
        atTimestamp = Clock.currTime;
    }

    void callLog()
    {
        setFunctionInfo();
        tl.log(testMessage); atLine = __LINE__;
    }

    tl.outputPattern = OutputPatternMarker.terminator ~ "'%S'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator
        ~ " [" ~ OutputPattern.level ~ "] "
        ~ OutputPattern.filename ~ "."
        ~ OutputPattern.line ~ "."
        ~ OutputPattern.method ~ ": "
        ~ OutputPattern.message
        ~ OutputPattern.newLine;
    callLog();
    auto expectedOutput = LogOutputWriter.date(datePattern, atTimestamp)
        ~ " [" ~ LogOutputWriter.logLevel(blankPattern, tl.logLevel) ~ "] "
        ~ LogOutputWriter.fileName(blankPattern, atfileName) ~ "."
        ~ LogOutputWriter.integer(blankPattern, atLine) ~ "."
        ~ LogOutputWriter.funcName(blankPattern, atfuncName, atprettyFuncName) ~ ": "
        ~ LogOutputWriter.text(blankPattern, testMessage)
        ~ LogOutputWriter.newLine(blankPattern);
    version (DebugLogger) debug writeln(tl.outputMessage);
    version (DebugLogger) debug writeln(expectedOutput);
    assert(tl.outputMessage == expectedOutput, tl.outputMessage ~ " vs " ~ expectedOutput);

    tl.outputPattern = OutputPatternMarker.terminator ~ "'%S'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator
        ~ OutputPattern.userContext
        ~ OutputPattern.timestamp;
    callLog();
    expectedOutput = LogOutputWriter.date(datePattern, atTimestamp)
        ~ LogOutputWriter.text(blankPattern, TestLoggerCustomContext.customContext)
        ~ LogOutputWriter.timestamp(blankPattern, atTimestamp);
    version (DebugLogger) debug writeln(tl.outputMessage);
    version (DebugLogger) debug writeln(expectedOutput);
    assert(tl.outputMessage == expectedOutput, tl.outputMessage ~ " vs " ~ expectedOutput);
}

unittest // LogTimming
{
    import core.thread : Thread;
    import std.conv : to;
    import std.stdio : writeln;
    import std.string : indexOf;

    auto tl = new TestLogger();
    string msg;
    void timeLog(bool logBeginEnd = false, Duration warnMsecs = Duration.zero, bool logIt = true) nothrow
    {
        auto timing = logIt ? LogTimming(tl, "timeLog", logBeginEnd, warnMsecs) : LogTimming.init;
        msg = tl.msg;
        if (warnMsecs > Duration.zero)
            Thread.sleep(warnMsecs + dur!"msecs"(1));
    }

    int msecs()
    {
        const i = tl.msg.indexOf(',');
        return to!int(tl.msg[0..i]);
    }

    timeLog();
    assert(tl.msg == "0,timeLog");

    timeLog(true);
    assert(msg == "0,Begin,timeLog" && tl.msg == "0,End,timeLog", msg);

    timeLog(false, dur!"msecs"(2));
    assert(msecs() >= 3 && tl.lvl == LogLevel.warn);

    timeLog(true, dur!"msecs"(2));
    assert(msg == "0,Begin,timeLog" && msecs() >= 3 && tl.lvl == LogLevel.warn, msg);

    tl.reset();
    timeLog(true, dur!"msecs"(2), false);
    assert(tl.msg.length == 0);
}

/* Sample D predefined variable
onlineapp.d;

struct Point
{
    // __FILE__=onlineapp.d,
    // __FUNCTION__=onlineapp.Point.dot
    // __PRETTY_FUNCTION__=double onlineapp.Point.dot(Point rhs)
    double dot(Point rhs)
    {
        logIt();
        return 0.0;
    }
}

// __FILE__=onlineapp.d
// __FUNCTION__=onlineapp.foo
// __PRETTY_FUNCTION__=void onlineapp.foo(Point rhs)
void foo(Point rhs)
{
   logIt();
}

void main()
{
    Point p1, p2;
    p1.dot(p2);
    foo(p2);
}
*/
