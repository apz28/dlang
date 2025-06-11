/*
 * Clone from std.logger with enhancement API
 * https://github.com/dlang/phobos/blob/master/std/logger/core.d
 * Copyright: Robert "burner" Schadek 2013
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: $(HTTP www.svs.informatik.uni-oldenburg.de/60865.html, Robert burner Schadek)
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.external.std.log.log_logger;

import core.atomic : atomicLoad, atomicExchange, atomicStore;
import core.sync.mutex : Mutex;
import core.thread : ThreadID;
import core.time : dur;
public import core.time : Duration;
import std.conv : emplace, to;
import std.datetime.date : DateTime;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : LocalTime, UTC;
import std.format : formattedWrite;
import std.process : thisThreadID;
import std.range.primitives : empty, ElementType, front, isInfinite, isInputRange, popFront;
import std.traits : isDynamicArray, isIntegral, isSomeChar, isSomeString, Unqual;
import std.typecons : Flag;
public import std.typecons : No, Yes;
import std.utf : encode;

debug(debug_pham_external_std_log_log_logger) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.external.std.log.log_date_time_format;


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

enum defaultGlobalLogLevel = lowestLogLevel; // No restriction
enum defaultLogLevel = LogLevel.warn;
enum defaultRequestLogLevel = LogLevel.info;

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
 * Determines if LogLevel, ll, will be able to be logged
 * Params:
 *   ll = requesting LogLevel
 *   moduleLL = module LogLevel restriction
 *   loggerLL = logger instance LogLevel restriction
 *   globalLL = global LogLevel restriction
 * Returns:
 *   false if built with version DisableLogger
 *   false if ll is LogLevel.off
 *   true if ll is equal/greater moduleLL and globalLL
 *   true if ll is equal/greater loggerLL and globalLL
 *   false otherwise
 */
pragma(inline, true)
bool isLoggingEnabled(const(LogLevel) ll, const(LogLevel) moduleLL, const(LogLevel) loggerLL) @nogc nothrow pure @safe
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", moduleLL=", moduleLL, ", loggerLL=", loggerLL, ")");

    version(DisableLogger)
        return false;
    else
    {
        return (ll != LogLevel.off) && (ll >= loggerLL || ll >= moduleLL);
    }
}

/**
 * Returns false if built with version DisableLogger, true otherwise
 */
pragma(inline, true)
bool isLoggingEnabled() @nogc nothrow pure @safe
{
    version(DisableLogger)
        return false;
    else
        return true;
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

static immutable string defaultOutputPattern = OutputPattern.date
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

    this(string moduleName, LogLevel logLevel) pure
    in
    {
        assert(moduleName.length != 0);
    }
    do
    {
        this.moduleName = moduleName;
        this.logLevel = logLevel;
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
        dispose(DisposingReason.destructor);
    }

    final void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe scope
    {
        doDispose(disposingReason);
    }

    final LogLevel logLevel(scope string moduleName,
        uint parentLevel = 1,
        const(LogLevel) notFoundLogLevel = LogLevel.off)
    {
        auto locked = LogRAIIMutex(mutex);
        if (values.length == 0 || moduleName.length == 0)
            return notFoundLogLevel;

        if (const v = moduleName in values)
            return (*v).logLevel;

        string pm = moduleName;
        while (parentLevel--)
        {
            pm = moduleParentOf(pm);
            if (pm.length == 0)
                break;

            if (const v = (pm ~ ".*") in values)
                return (*v).logLevel;
        }

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

    final ModuleLoggerOption set(ModuleLoggerOption option)
    in
    {
        assert(option.moduleName.length != 0);
    }
    do
    {
        auto locked = LogRAIIMutex(mutex);
        if (const v = option.moduleName in values)
        {
            auto result = *v;
            values[option.moduleName] = option;
            return result;
        }
        else
        {
            values[option.moduleName] = option;
            return ModuleLoggerOption.init;
        }
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

    static LogLevel logLevelModule(scope string moduleName,
        uint parentLevel = 1,
        const(LogLevel) notFoundLogLevel = LogLevel.off) @trusted
    {
        return (cast()_moduleOptions).logLevel(moduleName, notFoundLogLevel);
    }

    static ModuleLoggerOption removeModule(scope string moduleName) @trusted
    {
        return (cast()_moduleOptions).remove(moduleName);
    }

    static ModuleLoggerOption setModule(ModuleLoggerOption option) @trusted
    {
        return (cast()_moduleOptions).set(option);
    }

    static string wildPackageName(string moduleName) pure
    {
        const packageName = moduleParentOf(moduleName);
        return packageName.length != 0 ? (packageName ~ ".*") : null;
    }

protected:
    void doDispose(const(DisposingReason) disposingReason) @trusted scope
    {
        if (isDisposing(disposingReason))
        {
            values = null;

            if (mutex !is null)
            {
                if (ownMutex)
                    mutex.destroy();
                mutex = null;
            }
        }
    }

private:
    Mutex mutex;
    ModuleLoggerOption[string] values;
    bool ownMutex;
}

struct LogLocation
{
nothrow @safe:

    this(uint line, string fileName, string funcName, string moduleName) pure
    {
        this.line = line;
        this.fileName = fileName;
        this.funcName = funcName;
        this.moduleName = moduleName;
    }

    void clear() pure
    {
        line = 0;
        fileName = funcName = moduleName = null;
    }

    static LogLocation get(in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) pure
    {
        return LogLocation(line, fileName, funcName, moduleName);
    }

    string fileName; /// the filename the log function was called from
    string funcName; /// the name of the function the log function was called from
    string moduleName; /// the name of the module the log message is coming from
    uint line; /// the line number the log function was called from
}

/**
 * This function logs data.
 * In order for the data to be processed the `LogLevel` of the
 * `sharedLog` must be lesser or equal to the `defaultRequestLogLevel`.
 * Params:
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * log("Hello World", 3.1415);
 * --------------------
 */
void log(Args...)(lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        auto logger = threadLog;
        logger.log!(Args)(defaultRequestLogLevel, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This function logs data.
 * In order for the data to be processed the `LogLevel` of the
 * `sharedLog` must be lesser or equal to the `defaultRequestLogLevel`
 * and the condition passed must be `true`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * log(true, "Hello World ", 3.1415);
 * --------------------
 */
void log(Args...)(lazy bool condition, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition=", condition, ", line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        auto logger = threadLog;
        logger.log!(Args)(defaultRequestLogLevel, condition, args, line, fileName, funcName, moduleName);
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
 * --------------------
 * log(LogLevel.warn, "Hello World ", 3.1415);
 * --------------------
 */
void log(Args...)(const(LogLevel) ll, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(condition, "(ll=", ll, ", line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        threadLog.log!(Args)(ll, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This function logs data.
 * In order for the data to be processed, the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog` and
 * the condition passed must be `true`.
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  condition = The condition must be `true` for the data to be logged.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * log(LogLevel.warn, true, "Hello World ", 3.1415);
 * --------------------
 */
void log(Args...)(const(LogLevel) ll, lazy bool condition, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
{
    static if (isLoggingEnabled)
    {
        threadLog.log!(Args)(ll, condition, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the
 * `sharedLog` must be lesser or equal to the `defaultRequestLogLevel`
 * Params:
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * logf("Hello World %f", 3.1415);
 * --------------------
 */
void logf(Args...)(lazy string fmt, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        auto logger = threadLog;
        logger.logf!(Args)(defaultRequestLogLevel, fmt, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the
 * `sharedLog` must be lesser or equal to the `defaultRequestLogLevel`
 * and the condition passed must be `true`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  fmt = The `printf`-style string.
 * args = The data that should be logged.
 * Example:
--------------------
logf(true, "Hello World %f", 3.1415);
--------------------
 */
void logf(Args...)(lazy bool condition, lazy string fmt, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition=", condition, ", fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        auto logger = threadLog;
        logger.logf!(Args)(defaultRequestLogLevel, condition, fmt, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog`
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * logf(LogLevel.warn, "Hello World %f", 3.1415);
 * --------------------
 */
void logf(Args...)(const(LogLevel) ll, lazy string fmt, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        threadLog.logf!(Args)(ll, fmt, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This function logs data in a `printf`-style manner.
 * In order for the data to be processed the `LogLevel` of the log call must
 * be greater or equal to the `LogLevel` of the `sharedLog` and
 * the condition passed must be `true`.
 * Params:
 *  ll = The `LogLevel` used by this log call.
 *  condition = The condition must be `true` for the data to be logged.
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * logf(LogLevel.warn, true, "Hello World %f", 3.1415);
 * --------------------
 */
void logf(Args...)(const(LogLevel) ll, lazy bool condition, lazy string fmt, lazy Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
{
    debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", condition=", condition, ", fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

    static if (isLoggingEnabled)
    {
        threadLog.logf!(Args)(ll, condition, fmt, args, line, fileName, funcName, moduleName);
    }
}

/**
 * This template provides the global log functions with the `LogLevel`
 * is encoded in the function name.
 * The aliases following this template create the public names of these log functions.
 */
template defaultLogFunction(LogLevel ll)
{
    void defaultLogFunction(Args...)(lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            threadLog.logFunction!(ll).logImpl!(Args)(args, line, fileName, funcName, moduleName);
        }
    }

    void defaultLogFunction(Args...)(lazy bool condition, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition=", condition, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            threadLog.logFunction!(ll).logImpl!(Args)(condition, args, line, fileName, funcName, moduleName);
        }
    }
}

/**
 * This function logs data to the `stdThreadLocalLog`, optionally depending
 * on a condition.
 * In order for the resulting log message to be logged the `LogLevel` must
 * be greater or equal than the `LogLevel` of the `stdThreadLocalLog` and
 * must be greater or equal than the `LogLevel` of the `globalLogLevel`.
 * Additionally the `LogLevel` must be greater or equal than the `LogLevel`
 * of the `stdSharedLogger`.
 * If a condition is given, it must evaluate to `true`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * logTrace(1337, " is number");
 * logDebug(1337, " is number");
 * logInfo(1337, " is number");
 * logError(1337, " is number");
 * logCritical(1337, " is number");
 * logFatal(1337, " is number");
 *
 * logTrace(true, 1337, " is number");
 * logDebug(false, 1337, " is number");
 * logInfo(false, 1337, " is number");
 * logError(true, 1337, " is number");
 * logCritical(false, 1337, " is number");
 * logFatal(true, 1337, " is number");
 * --------------------
 */
alias logTrace = defaultLogFunction!(LogLevel.trace);
/// Ditto
alias logDebug = defaultLogFunction!(LogLevel.debug_);
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
 * The aliases following this template create the public names of the log functions.
 */
template defaultLogFunctionf(LogLevel ll)
{
    void defaultLogFunctionf(Args...)(lazy string fmt, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            threadLog.logFunction!(ll).logImplf!(Args)(fmt, args, line, fileName, funcName, moduleName);
        }
    }

    void defaultLogFunctionf(Args...)(lazy bool condition, lazy string fmt, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition=", condition, ", fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            threadLog.logFunction!(ll).logImplf!(Args)(condition, fmt, args, line, fileName, funcName, moduleName);
        }
    }
}

/**
 * This function logs data to the `sharedLog` in a `printf`-style manner.
 * In order for the resulting log message to be logged the `LogLevel` must
 * be greater or equal than the `LogLevel` of the `sharedLog` and
 * must be greater or equal than the `LogLevel` of the `globalLogLevel`.
 * Additionally the `LogLevel` must be greater or equal than the `LogLevel`
 * of the `stdSharedLogger`.
 * Params:
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * logTracef("is number %d", 1);
 * logDebugf_("is number %d", 2);
 * logInfof("is number %d", 3);
 * logErrorf("is number %d", 4);
 * logCriticalf("is number %d", 5);
 * logFatalf("is number %d", 6);
 * --------------------
 *
 * The second version of the function logs data to the `sharedLog` in a $(D
 * printf)-style manner.
 * In order for the resulting log message to be logged the `LogLevel` must
 * be greater or equal than the `LogLevel` of the `sharedLog` and
 * must be greater or equal than the `LogLevel` of the `globalLogLevel`.
 * Additionally the `LogLevel` must be greater or equal than the `LogLevel`
 * of the `stdSharedLogger`.
 * Params:
 *  condition = The condition must be `true` for the data to be logged.
 *  fmt = The `printf`-style string.
 *  args = The data that should be logged.
 * Example:
 * --------------------
 * logTracef(false, "is number %d", 1);
 * logDebugf_(false, "is number %d", 2);
 * logInfof(false, "is number %d", 3);
 * logErrorf(true, "is number %d", 4);
 * logCriticalf(true, "is number %d", 5);
 * logFatalf(someFunct(), "is number %d", 6);
 * --------------------
 */
alias logTracef = defaultLogFunctionf!(LogLevel.trace);
/// Ditto
alias logDebugf = defaultLogFunctionf!(LogLevel.debug_);
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
 * `commitMsg` and `endMsg` together, this option gives more flexibility.
 */
abstract class Logger
{
public:
    /**
     * Every subclass of `Logger` has to call this constructor from their
     * constructor. It sets the `LoggerOption`, and creates a fatal handler. The fatal
     * handler will throw an `Error` if a log call is made with level `LogLevel.fatal`.
     * Params:
     *  option = `LoggerOption` to use for this `Logger` instance.
     */
    this(LoggerOption option = LoggerOption.init) nothrow @safe
    {
        this._option = option;
        this._userName = currentUserName();
        this._mutex = new Mutex();
    }

    ~this() nothrow @safe
    {
        dispose(DisposingReason.destructor);
    }

    final void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe scope
    {
        doDispose(disposingReason);
    }

    /**
     * This method allows forwarding log entries from one logger to another.
     * `forwardLog` will ensure proper synchronization and then call
     * `writeLog`. This is an API for implementing your own loggers and
     * should not be called by normal user code. A notable difference from other
     * logging functions is that the `globalLogLevel` won't be evaluated again
     * since it is assumed that the caller already checked that.
     */
    void forwardLog(ref LogEntry payload) nothrow @safe
    {
        static if (isLoggingEnabled)
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

            bool isFatal = false;
            const llModuleLevel = ModuleLoggerOptions.logLevelModule(payload.header.location.moduleName);
            const llLogLevel = this.logLevel;
            if (isLoggingEnabled(payload.header.logLevel, llModuleLevel, llLogLevel))
            {
                isFatal = payload.header.logLevel == LogLevel.fatal;
                auto locked = LogRAIIMutex(_mutex);
                this.writeLog(payload);
            }
            if (isFatal)
                doFatal();
        }
    }

    pragma(inline, true)
    @property final size_t flushOutputLines() const nothrow pure @safe
    {
        return this._option.flushOutputLines;
    }

    /**
     * The `LogLevel` determines if the log call are processed or dropped
     * by the `Logger`. In order for the log call to be processed the
     * `LogLevel` of the log call must be greater or equal to the `LogLevel`
     * of the `logger`.
     * These two methods set and get the `LogLevel` of the used `Logger`.
     * Example:
     * -----------
     * auto logger = new FileLogger(stdout);
     * logger.logLevel = LogLevel.info;
     * logger.warn("Log warning message");
     * logger.trace("Tracing message is being skipped");
     * -----------
     */
    @property final LogLevel logLevel() const nothrow pure @safe
    {
        return atomicLoad(cast(shared)(this._option.logLevel));
    }

    /// Ditto
    @property final Logger logLevel(const(LogLevel) value) nothrow @safe @nogc
    {
        atomicStore(this._option.logLevel, value);
        return this;
    }

    /**
     * Name of this logger
     */
    @property final string name() nothrow @safe @nogc
    {
        auto locked = LogRAIIMutex(_mutex);
        return this._option.logName;
    }

    /// Ditto
    @property final Logger name(string value) nothrow @safe @nogc
    {
        auto locked = LogRAIIMutex(_mutex);
        this._option.logName = value;
        return this;
    }

    /**
     * Determines what log data/message and how a log message being written
     */
    @property final string outputPattern() nothrow @safe @nogc
    {
        auto locked = LogRAIIMutex(_mutex);
        return this._option.outputPattern;
    }

    /// Ditto
    @property final Logger outputPattern(string value) nothrow @safe
    {
        auto locked = LogRAIIMutex(_mutex);
        this._option.outputPattern = value;
        return this;
    }

    /**
     * A user defined context object
     */
    @property final Object userContext() nothrow pure @trusted
    {
        return cast(Object)atomicLoad(cast(shared)(this._userContext));
    }

    /// Ditto
    @property final Logger userContext(Object value) nothrow @trusted
    {
        atomicStore(this._userContext, value);
        return this;
    }

    /**
     * The current OS login name (name of the user associated with the current thread.)
     * when this logger instance was created
     */
    @property final string userName() nothrow @safe
    {
        return _userName;
    }

    /**
     * This template provides the checking for if a level is enabled for the `Logger` `class`
     * with the `LogLevel` encoded in the function name.
     * For further information see the the two functions defined inside of this template.
     * The aliases following this template create the public names of these log functions.
     */
    template isFunction(LogLevel ll)
    {
        pragma(inline, true)
        final bool isImpl(in string moduleName = __MODULE__) const nothrow @safe
        {
            LogLevel llModuleLevel = void;
            return isImpl2(llModuleLevel, moduleName);
        }

        final bool isImpl2(out LogLevel llModuleLevel, in string moduleName = __MODULE__) const nothrow @trusted
        {
            llModuleLevel = ModuleLoggerOptions.logLevelModule(moduleName);
            const llLogLevel = this.logLevel;
            return isLoggingEnabled(ll, llModuleLevel, llLogLevel);
        }
    }

    /// Ditto
    alias isTrace = isFunction!(LogLevel.trace).isImpl;
    alias isTrace2 = isFunction!(LogLevel.trace).isImpl2;
    /// Ditto
    alias isDebug = isFunction!(LogLevel.debug_).isImpl;
    alias isDebug2 = isFunction!(LogLevel.debug_).isImpl2;
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
    pragma(inline, true)
    final bool isLogLevel(const(LogLevel) ll, in string moduleName = __MODULE__) const nothrow @safe
    {
        LogLevel llModuleLevel = void;
        return isLogLevel2(ll, llModuleLevel, moduleName);
    }

    /// Ditto
    final bool isLogLevel2(const(LogLevel) ll, out LogLevel llModuleLevel, in string moduleName = __MODULE__) const nothrow @safe
    {
        final switch (ll)
        {
            case LogLevel.trace:
                return isTrace2(llModuleLevel, moduleName);
            case LogLevel.debug_:
                return isDebug2(llModuleLevel, moduleName);
            case LogLevel.info:
                return isInfo2(llModuleLevel, moduleName);
            case LogLevel.warn:
                return isWarn2(llModuleLevel, moduleName);
            case LogLevel.error:
                return isError2(llModuleLevel, moduleName);
            case LogLevel.critical:
                return isCritical2(llModuleLevel, moduleName);
            case LogLevel.fatal:
                return isFatal2(llModuleLevel, moduleName);
            case LogLevel.off:
                llModuleLevel = LogLevel.off;
                return false;
        }
    }

    /**
     * This template provides the log functions for the `Logger` `class`
     * with the `LogLevel` encoded in the function name.
     * For further information see the the two functions defined inside of this template.
     * The aliases following this template create the public names of these log functions.
     */
    template logFunction(LogLevel ll)
    {
        /**
         * This function logs function call to instant `Logger`.
         */
        final void logImpl(LogLocation location) nothrow @safe
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(line=", location.line, ", funcName=", location.funcName, ")");

            static if (isLoggingEnabled)
            {
                bool isFatal = false;
                // Special try construct for grep
                try {
                    auto currTime = currentTime();
                    if (isFunction!(ll).isImpl(location.moduleName))
                    {
                        isFatal = ll == LogLevel.fatal;
                        {
                            auto locked = LogRAIIMutex(_mutex);
                            auto header = LogHeader(ll, location, thisThreadID, currTime);
                            this.beginMsg(header);
                            this.endMsg(header);
                        }
                    }
                } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
                if (isFatal)
                    doFatal();
            }
        }

        /**
         * This function logs data to instant `Logger`.
         * In order for the resulting log message to be logged the `LogLevel`
         * must be greater or equal than the `LogLevel` of the used `Logger`
         * and must be greater or equal than the `LogLevel` of the `globalLogLevel`.
         * Params:
         *  args = The data that should be logged.
         * Example:
         * --------------------
         * auto logger = new FileLogger(stdout);
         * logger.trace(1337, " is number");
         * --------------------
         */
        final void logImpl(Args...)(lazy Args args,
            in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
        if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(line=", line, ", funcName=", funcName, ")");

            static if (isLoggingEnabled)
            {
                bool isFatal = false;
                // Special try construct for grep
                try {
                    auto currTime = currentTime();
                    if (isFunction!(ll).isImpl(moduleName))
                    {
                        isFatal = ll == LogLevel.fatal;
                        {
                            auto locked = LogRAIIMutex(_mutex);
                            auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                            this.beginMsg(header);
                            if (args.length)
                            {
                                auto writer = LogArgumentWriter(this);
                                writer.put!(Args)(header, args);
                            }
                            this.endMsg(header);
                        }
                    }
                } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
                if (isFatal)
                    doFatal();
            }
        }

        /**
         * This function logs data to the used `Logger` depending on a
         * condition.
         * In order for the resulting log message to be logged the `LogLevel` must
         * be greater or equal than the `LogLevel` of the used `Logger` and
         * must be greater or equal than the `LogLevel` of the `globalLogLevel`; additionally the
         * condition passed must be `true`.
         * Params:
         *  condition = The condition must be `true` for the data to be logged.
         *  args = The data that should be logged.
         * Example:
         * --------------------
         * auto logger = new FileLogger(stdout);
         * logger.trace(true, 1337, " is number");
         * logger.info(false, 1337, " is number");
         * --------------------
         */
        final void logImpl(Args...)(lazy bool condition, lazy Args args,
            in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition=", condition, ", line=", line, ", funcName=", funcName, ")");

            static if (isLoggingEnabled)
            {
                bool isFatal = false;
                // Special try construct for grep
                try {
                    auto currTime = currentTime();
                    if (isFunction!(ll).isImpl(moduleName) && condition)
                    {
                        isFatal = ll == LogLevel.fatal;
                        {
                            auto locked = LogRAIIMutex(_mutex);
                            auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                            this.beginMsg(header);
                            if (args.length)
                            {
                                auto writer = LogArgumentWriter(this);
                                writer.put!(Args)(header, args);
                            }
                            this.endMsg(header);
                        }
                    }
                } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
                if (isFatal)
                    doFatal();
            }
        }

        /**
         * This function logs data to the used `Logger` in a
         * `printf`-style manner.
         * In order for the resulting log message to be logged the `LogLevel` must
         * be greater or equal than the `LogLevel` of the used `Logger` and
         * must be greater or equal than the `LogLevel` of the `globalLogLevel`.
         * Params:
         *  fmt = The `printf`-style string.
         *  args = The data that should be logged.
         * Example:
         * --------------------
         * auto logger = new FileLogger(stderr);
         * logger.tracef("is number %d", 1);
         * --------------------
         */
        final void logImplf(Args...)(lazy string fmt, lazy Args args,
            in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
        if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : string)))
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

            static if (isLoggingEnabled)
            {
                bool isFatal = false;
                // Special try construct for grep
                try {
                    auto currTime = currentTime();
                    if (isFunction!(ll).isImpl(moduleName))
                    {
                        isFatal = ll == LogLevel.fatal;
                        {
                            auto locked = LogRAIIMutex(_mutex);
                            auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                            this.beginMsg(header);
                            auto writer = LogArgumentWriter(this);
                            writer.putf!(Args)(header, fmt, args);
                            this.endMsg(header);
                        }
                    }
                } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
                if (isFatal)
                    doFatal();
            }
        }

        /**
         * This function logs data to the used `Logger` in a
         * `printf`-style manner.
         * In order for the resulting log message to be logged the `LogLevel`
         * must be greater or equal than the `LogLevel` of the used `Logger`
         * and must be greater or equal than the `LogLevel` of the `globalLogLevel`; additionally
         * the passed condition must be `true`.
         * Params:
         *  condition = The condition must be `true` for the data to be logged.
         *  fmt = The `printf`-style string.
         *  args = The data that should be logged.
         * Example:
         * --------------------
         * auto logger = new FileLogger(stderr);
         * logger.tracef(true, "is number %d", 1);
         * logger.errorf(false, "is number %d", 3);
         * logger.criticalf(someFunc(), "is number %d", 4);
         * --------------------
         */
        final void logImplf(Args...)(lazy bool condition, lazy string fmt, lazy Args args,
            in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(", condition=", condition, fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

            static if (isLoggingEnabled)
            {
                bool isFatal = false;
                // Special try construct for grep
                try {
                    auto currTime = currentTime();
                    if (isFunction!(ll).isImpl(moduleName) && condition)
                    {
                        isFatal = ll == LogLevel.fatal;
                        {
                            auto locked = LogRAIIMutex(_mutex);
                            auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                            this.beginMsg(header);
                            auto writer = LogArgumentWriter(this);
                            writer.putf!(Args)(header, fmt, args);
                            this.endMsg(header);
                        }
                    }
                } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
                if (isFatal)
                    doFatal();
            }
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
     * This function logs function call to instant `Logger`.
     */
    final void log(LogLocation location) nothrow @safe
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(line=", location.line, ", funcName=", location.funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                const ll = defaultRequestLogLevel;
                if (isLogLevel(ll, location.moduleName))
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, location, thisThreadID, currTime);
                        this.beginMsg(header);
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This function logs data to the used `Logger` with the `LogLevel`
     * of the used `Logger`.
     * In order for the resulting log message to be logged the `LogLevel`
     * of the used `Logger` must be greater or equal than the `LogLevel` of the `globalLogLevel`.
     * Params:
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.log(1337, " is number");
     * --------------------
     */
    final void log(Args...)(lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                const ll = defaultRequestLogLevel;
                if (isLogLevel(ll, moduleName))
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        if (args.length)
                        {
                            auto writer = LogArgumentWriter(this);
                            writer.put!(Args)(header, args);
                        }
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This function logs data to the used `Logger` depending on a
     * explicitly passed condition with the `LogLevel` of the used
     * `Logger`.
     * In order for the resulting log message to be logged the `LogLevel`
     * of the used `Logger` must be greater or equal than the `LogLevel` of the `globalLogLevel`
     * and the condition must be `true`.
     * Params:
     *  condition = The condition must be `true` for the data to be logged.
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.log(true, 1337, " is number");
     * logger.log(false, 1337, " is number");
     * --------------------
     */
    final void log(Args...)(lazy bool condition, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition= ", condition, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                const ll = defaultRequestLogLevel;
                if (isLogLevel(ll, moduleName) && condition)
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        if (args.length)
                        {
                            auto writer = LogArgumentWriter(this);
                            writer.put!(Args)(header, args);
                        }
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This function logs data to the used `Logger` with a specific
     * `LogLevel`.
     * In order for the resulting log message to be logged the `LogLevel`
     * must be greater or equal than the `LogLevel` of the used `Logger`
     * and must be greater or equal than the `LogLevel` of the `globalLogLevel`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.log(LogLevel.trace, 1337, " is number");
     * --------------------
     */
    final void log(Args...)(const(LogLevel) ll, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool)))
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                if (isLogLevel(ll, moduleName))
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        if (args.length)
                        {
                            auto writer = LogArgumentWriter(this);
                            writer.put!(Args)(header, args);
                        }
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This method logs data with the `LogLevel` of the used `Logger`.
     * This method takes a `bool` as first argument. In order for the
     * data to be processed the `bool` must be `true` and the `LogLevel`
     * of the Logger must be greater or equal to the global `LogLevel`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  condition = The condition must be `true` for the data to be logged.
     *  args = The data that is to be logged.
     * Example:
     * --------------------
     * auto logger = new StdioLogger();
     * logger.log(LogLevel.trace, true, 1337);
     * --------------------
     */
    final void log(Args...)(const(LogLevel) ll, lazy bool condition, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", condition=", condition, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                if (isLogLevel(ll, moduleName) && condition)
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        if (args.length)
                        {
                            auto writer = LogArgumentWriter(this);
                            writer.put!(Args)(header, args);
                        }
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This method logs data to the used `Logger` with the `LogLevel`
     * of the this `Logger` in a `printf`-style manner.
     * In order for the data to be processed the `LogLevel` of the `Logger`
     * must be greater or equal to the global `LogLevel`.
     * Params:
     *  fmt = The format string used for this log call.
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.logf("%d %s", 1337, "is number");
     * --------------------
     */
    final void logf(Args...)(lazy string fmt, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(Args[0]) : bool) && !is(Unqual!(Args[0]) == LogLevel)))
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                const ll = defaultRequestLogLevel;
                if (isLogLevel(ll, moduleName))
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.putf!(Args)(header, fmt, args);
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This function logs data to the used `Logger` depending on a
     * condition with the `LogLevel` of the used `Logger` in a `printf`-style manner.
     * In order for the resulting log message to be logged the `LogLevel`
     * of the used `Logger` must be greater or equal than the `LogLevel` of the `globalLogLevel`
     * and the condition must be `true`.
     * Params:
     *  condition = The condition must be `true` for the data to be logged.
     *  fmt = The format string used for this log call.
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.logf(true ,"%d %s", 1337, "is number");
     * logger.logf(false ,"%d %s", 1337, "is number");
     * --------------------
     */
    final void logf(Args...)(lazy bool condition, lazy string fmt, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(condition=", condition, ", fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                const ll = defaultRequestLogLevel;
                if (isLogLevel(ll, moduleName) && condition)
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.putf!(Args)(header, fmt, args);
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This function logs data to the used `Logger` with a specific
     * `LogLevel` in a `printf`-style manner.
     * In order for the resulting log message to be logged the `LogLevel`
     * must be greater or equal than the `LogLevel` of the used `Logger`
     * and must be greater or equal than the `LogLevel` of the `globalLogLevel`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  fmt = The format string used for this log call.
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.logf(LogLevel.trace, "%d %s", 1337, "is number");
     * --------------------
     */
    final void logf(Args...)(const(LogLevel) ll, lazy string fmt, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", fmt=", fmt, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                if (isLogLevel(ll, moduleName))
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.putf!(Args)(header, fmt, args);
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

    /**
     * This function logs data to the used `Logger` with a specific
     * `LogLevel` and depending on a condition in a `printf`-style manner.
     * In order for the resulting log message to be logged the `LogLevel`
     * must be greater or equal than the `LogLevel` of the used `Logger`
     * and must be greater or equal than the `LogLevel` of the `globalLogLevel` and the
     * condition must be `true`.
     * Params:
     *  ll = The specific `LogLevel` used for logging the log message.
     *  condition = The condition must be `true` for the data to be logged.
     *  fmt = The format string used for this log call.
     *  args = The data that should be logged.
     * Example:
     * --------------------
     * auto logger = new FileLogger(stdout);
     * logger.logf(LogLevel.trace, true ,"%d %s", 1337, "is number");
     * --------------------
     */
    final void logf(Args...)(const(LogLevel) ll, lazy bool condition, lazy string fmt, lazy Args args,
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) nothrow
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(ll=", ll, ", condition=", condition, ", line=", line, ", funcName=", funcName, ")");

        static if (isLoggingEnabled)
        {
            bool isFatal = false;
            // Special try construct for grep
            try {
                auto currTime = currentTime();
                if (isLogLevel(ll, moduleName) && condition)
                {
                    isFatal = ll == LogLevel.fatal;
                    {
                        auto locked = LogRAIIMutex(_mutex);
                        auto header = LogHeader(ll, line, fileName, funcName, moduleName, thisThreadID, currTime);
                        this.beginMsg(header);
                        auto writer = LogArgumentWriter(this);
                        writer.putf!(Args)(header, fmt, args);
                        this.endMsg(header);
                    }
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
            if (isFatal)
                doFatal();
        }
    }

public:
    static struct LogHeader
    {
    nothrow @safe:

        this(LogLevel logLevel, LogLocation location, ThreadID threadID, SysTime timestamp) pure
        {
            this.logLevel = logLevel;
            this.location = location;
            this.threadID = threadID;
            this.timestamp = timestamp;
            this.exception = null;
        }

        this(LogLevel logLevel, uint line, string fileName, string funcName, string moduleName, ThreadID threadID, SysTime timestamp) pure
        {
            this.logLevel = logLevel;
            this.location = LogLocation(line, fileName, funcName, moduleName);
            this.threadID = threadID;
            this.timestamp = timestamp;
            this.exception = null;
        }

        LogLocation location;
        Exception exception;
        SysTime timestamp; /// the time the message was logged
        ThreadID threadID; /// thread id of the log message
        LogLevel logLevel; /// the `LogLevel` associated with the log message
    }

    /**
     * LogEntry is a aggregation combining all information associated
     * with a log message. This aggregation will be passed to the method
     * writeLog.
     */
    static struct LogEntry
    {
        Logger logger; /// A refernce to the `Logger` used to create this `LogEntry`
        LogHeader header;
        string message; /// the message of the log message
    }

protected:
    void doDispose(const(DisposingReason) disposingReason) nothrow @trusted scope
    {
        _option.logLevel = LogLevel.off;
        if (isDisposing(disposingReason))
        {
            _userName = null;
            _userContext = null;
            if (_mutex !is null)
            {
                _mutex.destroy();
                _mutex = null;
            }
        }
    }

    void doFatal() nothrow @safe
    {
        assert(0, "Fatal loglevel encountered!");
    }

    /** Signals that the log message started. */
    abstract void beginMsg(ref LogHeader header) nothrow @safe;

    /** Logs a part of the log message. */
    abstract void commitMsg(scope const(char)[] msg) nothrow @safe;

    /** Signals that the message has been written and no more calls to `commitMsg` follow. */
    abstract void endMsg(ref LogHeader header) nothrow @safe;

    /**
     * A custom logger must implement this method in order to capture log for forwardMsg call
     * Params:
     *  payload = All information associated with call to log function.
     */
    abstract void writeLog(ref LogEntry payload) nothrow @safe;

protected:
    Mutex _mutex;

private:
    Object _userContext;
    string _userName;
    LoggerOption _option;
}

/**
 * The default implementation will use an `pham.utl.utl_Appender`
 * internally to construct the message string. This means dynamic,
 * GC memory allocation.
 * A logger can avoid this allocation by
 * reimplementing `beginMsg`, `commitMsg` and `endMsg`.
 * `beginMsg` is always called first, followed by any number of calls
 * to `commitMsg` and one call to `endMsg`.
 *
 * As an example for such a custom `Logger` compare this:
 * ----------------
 * class CustomLogger : Logger
 * {
 *     this(LoggerOption option = LoggerOption.init) nothrow @safe
 *     {
 *         super(option);
 *     }
 *
 *     protected override void beginMsg(ref Logger.LogHeader header) nothrow @safe
 *     {
 *         ... logic here
 *     }
 *
 *     protected override void commitMsg(const(char)[] msg) nothrow @safe
 *     {
 *         ... logic here
 *     }
 *
 *     protected override void endMsg(ref Logger.LogHeader header) nothrow @safe
 *     {
 *         ... logic here
 *     }
 *
 *     protected override void writeLog(ref Logger.LogEntry payload) nothrow @safe
 *     {
 *         ... logic here to write actual logging info
 *     }
 * }
 * ----------------
 */
class MemLogger : Logger
{
nothrow @safe:

public:
    this(LoggerOption option = LoggerOption.init)
    {
        super(option);
    }

protected:
    override void beginMsg(ref Logger.LogHeader header)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        msgBuffer.capacity = 500;
        logEntry = Logger.LogEntry(this, header, null);
    }

    override void commitMsg(scope const(char)[] msg)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        msgBuffer.put(msg);
    }

    override void endMsg(ref Logger.LogHeader header)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        this.logEntry.header = header;
        this.logEntry.message = msgBuffer.data.idup;
        this.writeLog(logEntry);

        // Reset to release its memory
        this.logEntry = Logger.LogEntry.init;
        this.msgBuffer.clear();
    }

    override void writeLog(ref Logger.LogEntry payload)
    {}

protected:
    Appender!(char[]) msgBuffer;
    Logger.LogEntry logEntry;
}

class ConsoleLogger : MemLogger
{
    import std.stdio : File, stderr, stdout;

nothrow @safe:

public:
    this(LoggerOption option = LoggerOption.init)
    {
        super(option);
    }

protected:
    static File trustedStderr() @trusted
    {
        return stderr;
    }

    static File trustedStdout() @trusted
    {
        return stdout;
    }

    static bool isStdio(ref File file)
    {
        try {
            const fileno = file.isOpen ? file.fileno : -1;
            if (fileno == -1)
                return false;
            return fileno == trustedStderr().fileno
                || fileno == trustedStdout().fileno;
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return false; }
    }

    final override void writeLog(ref Logger.LogEntry payload)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        try {
            auto writer = LogOutputWriter(this);
            auto lockedFile = trustedStdout().lockingTextWriter();
            writer.write(lockedFile, payload);
            if (flushOutputLines && ++flushWriteLogLines >= flushOutputLines)
            {
                trustedStdout().flush();
                flushWriteLogLines = 0;
            }
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

protected:
    size_t flushWriteLogLines;
}

/// An option to create $(LREF FileLogger) directory if it is non-existent.
alias CreateFolder = Flag!"CreateFolder";

struct FileLoggerOption
{
nothrow @safe:

    static immutable string appendMode = "a";
    static immutable string overwriteMode = "w";

public:
    /**
     * file mode open for appending or writing new file, default is appending
     * a = append
     * w = write - override if existed
     */
    string openMode = appendMode;

    /**
     * Ensure log file directory existed if CreateFolder.yes
     */
    CreateFolder createFileFolder = CreateFolder.yes;
}

/**
 * This `Logger` implementation writes log messages to the associated
 * file. The name of the file has to be passed on construction time.
 */
class FileLogger : MemLogger
{
    import core.stdc.stdio : SEEK_END, SEEK_SET;
    import std.file : DirEntry, mkdirRecurse;
    import std.path : extractFileName = baseName, extractDirName = dirName, extractFileExt = extension;
    import std.stdio : File;

@safe:

public:
    /**
     * A constructor for the `FileLogger` Logger.
     * Params:
     *  fileName = The filename of the output file of the `FileLogger`. If that
     *      file can not be opened for writting, logLevel will switch to off.
     *  fileOption = default file option
     *  option = default log option
     *
     * Example:
     *  auto l1 = new FileLogger("logFile.log");
     *  auto l2 = new FileLogger("logFile.log", FileLoggerOption("w");
     *  auto l3 = new FileLogger("logFile.log", FileLoggerOption("a"), LoggerOption(defaultOutputHeaderPatterns, LogLevel.fatal));
     *  auto l3 = new FileLogger("logFolder/logFile.log", FileLoggerOption("w", CreateFolder.yes), LoggerOption(defaultOutputHeaderPatterns, LogLevel.fatal));
     */
    this(const(string) fileName,
        FileLoggerOption fileOption = FileLoggerOption.init,
        LoggerOption option = LoggerOption.init) nothrow
    {
        this.fileName(fileName);
        this._fileOwned = true;
        this._fileOption = fileOption;
        this._isStdio = false;
        if (!doOpen(fileName, fileOption))
            option.logLevel = LogLevel.off;
        super(option);
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
    this(File file,
        LoggerOption option = LoggerOption.init)
    {
        this.fileName(null);
        this._file = file;
        this._fileOwned = false;
        this._fileOption = FileLoggerOption(null, CreateFolder.no);
        this._isStdio = ConsoleLogger.isStdio(file);
        super(option);
    }

nothrow:

    ~this()
    {
        doClose();
    }

    /**
     * Return a reference to this File.
     */
    @property final File file()
    {
        return this._file;
    }

    /**
     * If the `FileLogger` was constructed with a fileName, this method
     * returns this fileName. Otherwise an empty `string` is returned.
     */
    @property final string fileName() const pure
    {
        return this._fileName;
    }

    @property final FileLoggerOption fileOption() const
    {
        return this._fileOption;
    }

    @property final bool isStdio() const pure
    {
        return this._isStdio;
    }

protected:
    final void doClose() scope
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        // Special try construct for grep
        try {
            if (_fileOwned && _file.isOpen)
                _file.close();
            _file = File.init;
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    override void doFatal()
    {
        doClose();
        super.doFatal();
    }

    final bool doOpen(const(string) fileName, const(FileLoggerOption) fileOption)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        // Special try construct for grep
        try {
            if (fileOption.createFileFolder)
            {
                auto d = extractDirName(fileName);
                mkdirRecurse(d);
            }

            this._file.open(fileName, fileOption.openMode == FileLoggerOption.overwriteMode ? "w" : "a");
            return true;
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return false; }
    }

    static string extractFileNameWithoutExt(const(string) fileName)
    {
        const ext = extractFileExt(fileName);
        return fileName[0..$-ext.length];
    }

    final ulong fileSize() @trusted
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        if (_isStdio)
            return 0;

        try {
            if (!_file.isOpen)
            {
                auto fe = DirEntry(fileName);
                return fe.size;
            }

            _file.lock();
            scope (exit)
                _file.unlock();

            const curPos = _file.tell();
            scope (exit)
                _file.seek(curPos, SEEK_SET);

            _file.seek(0, SEEK_END);
            return _file.tell();
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return 0u; }
    }

    final SysTime lastModified()
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        if (_isStdio)
            return SysTime.init;

        try {
            auto fe = DirEntry(fileName);
            return fe.timeLastModified;
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return SysTime.init; }
    }

    final override void writeLog(ref Logger.LogEntry payload)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        if (!_file.isOpen)
            return;

        try {
            auto writer = LogOutputWriter(this);
            if (_isStdio)
            {
                auto lockedFile = _file.lockingTextWriter();
                writer.write(lockedFile, payload);
            }
            else
            {
                auto sinkFile = FileOutputSink(_file);
                writer.write(sinkFile, payload);
            }
            if (flushOutputLines && ++_flushWriteLogLines >= flushOutputLines)
            {
                _file.flush();
                _flushWriteLogLines = 0;
            }
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    @property final void fileName(const(string) value)
    {
        if (value.length)
        {
            this._fileName = value;
            this._fileDir = extractDirName(value);
            this._fileBaseName = extractFileNameWithoutExt(extractFileName(value));
            this._fileExt = extractFileExt(value);
        }
        else
        {
            this._fileName = this._fileDir = this._fileBaseName = this._fileExt = null;
        }
    }

    static struct FileOutputSink
    {
    nothrow @safe:

        this(ref File file)
        {
            this.file = file;
        }

        //version(none)
        void put(scope char c) @trusted
        {
            try {
                file.write(c);
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
        }

        //version(none)
        void put(scope string s) @trusted
        {
            try {
                file.write(s);
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
        }

        void put(C)(scope C c) @trusted
        if (isSomeChar!C || is(C : const(ubyte)))
        {
            try {
                file.write(c);
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
        }

        void put(A)(scope A items) @trusted
        if ((isSomeChar!(ElementType!A) || is(ElementType!A : const(ubyte)))
            && isInputRange!A
            && !isInfinite!A)
        {
            try {
                foreach (c; items)
                {
                    file.write(c);
                }
            } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
        }

        //alias write = put;

        File file;
    }

protected:
    File _file; /// The `File` log messages are written to.
    string _fileBaseName;
    string _fileDir;
    string _fileExt;
    string _fileName; // The filename of the `File` log messages are written to.
    FileLoggerOption _fileOption;
    size_t _flushWriteLogLines;
    bool _fileOwned;
    bool _isStdio;
}

/**
 * The `NullLogger` will not process any log messages.
 * In case of a log message with `LogLevel.fatal` nothing will happen.
 * By default the `LogLevel` for `NullLogger` is `LogLevel.all`.
 */
class NullLogger : Logger
{
nothrow @safe:

public:
    this()
    {
        super(LoggerOption(lowestLogLevel, "Null", "", size_t.max));
    }

    final override void forwardLog(ref Logger.LogEntry payload)
    {}

protected:
    final override void doFatal()
    {}

    final override void beginMsg(ref Logger.LogHeader header)
    {}

    final override void commitMsg(scope const(char)[] msg)
    {}

    final override void endMsg(ref Logger.LogHeader header)
    {}

    final override void writeLog(ref Logger.LogEntry payload)
    {}
}

enum RollingFileMode : ubyte
{
    composite, /// Roll files based on both the date and size of the file
    date, /// Roll files based only on the date
    size, /// Roll files based only on the size of the file
}

enum RollingDateMode : ubyte
{
	topOfMonth, /// Roll the log each month
	topOfWeek, /// Roll the log each week
	topOfDay, /// Roll the log each day (midnight)
	topOfHour, /// Roll the log for each hour
}

struct RollingFileLoggerOption
{
nothrow @safe:

public:
    bool rollingDate() const @nogc
    {
        return fileMode == RollingFileMode.date || fileMode == RollingFileMode.composite;
    }

    bool rollingSize() const @nogc
    {
        return (fileMode == RollingFileMode.size || fileMode == RollingFileMode.composite) && (maxFileSize > 0);
    }

public:
    /**
     * the maximum size that the output file is allowed to reach
     * before being rolled over to backup files
     * Zero is no limit, default is 10MB
     */
    ulong maxFileSize = 10*1024*1024;

    /**
     * the maximum number of backup files that are kept before
     * the oldest is erased
     * Zero is no backup files, default is 52 (52 weeks per year) since dateMode=RollingDateMode.topOfWeek
     */
    uint maxRollBackupCount = 52;

    /**
     * A date point when a log file to be rolled over
     */
    RollingDateMode dateMode = RollingDateMode.topOfWeek;

    /**
     * Mode to determines when a log file to be rolled over
     */
    RollingFileMode fileMode = RollingFileMode.composite;
}

class RollingFileLogger : FileLogger
{
    import core.time : MonoTime;
    import std.algorithm.sorting : sort;
    import std.file : dirEntries, fileExists = exists, fileRemove = remove, fileRename = rename, SpanMode;
    import std.path : buildPath;
    import std.string : lastIndexOf;
    import std.uni : toLower;

nothrow @safe:

public:
    this(const string fileName,
        RollingFileLoggerOption rollingFileOption = RollingFileLoggerOption.init,
        LoggerOption option = LoggerOption.init)
    {
        this._rollingOption = rollingFileOption;
        super(fileName, FileLoggerOption(FileLoggerOption.appendMode, CreateFolder.yes), option);
        this._rollTimestamp = nextCheckTimestamp(lastModified());
        determineBackupFiles();
    }

    @property final RollingFileLoggerOption rollingOption() const
    {
        return _rollingOption;
    }

protected:
    final bool adjustFileBeforeAppend()
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        bool rolled = false;

        if (_rollingOption.rollingDate())
        {
            const n = currentTime();
            if (n >= _rollTimestamp)
            {
                _rollTimestamp = nextCheckTimestamp(n);
                renameFiles(n, 0);
                rolled = true;
            }
        }

        if (!rolled && _rollingOption.rollingSize())
        {
            const n = fileSize();
            if (n >= _rollingOption.maxFileSize)
            {
                renameFiles(SysTime.init, n);
                rolled = true;
            }
        }

        if (rolled && !doOpen(_fileName, FileLoggerOption(FileLoggerOption.overwriteMode)))
            return false;
        else
            return true;
    }

    override void beginMsg(ref Logger.LogHeader header)
    {
        if (!adjustFileBeforeAppend())
            this.logLevel = LogLevel.off;
        super.beginMsg(header);
    }

    final void deleteFile(const(string) fileName)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fileName=", fileName, ")");

        if (!fileExists(fileName))
            return;

        string deleteFileName = fileName;
        try {
            string tempFileName = fileName ~ "." ~ MonoTime.currTime().ticks.to!string() ~ ".DeletePending";
            fileRename(fileName, tempFileName);
            deleteFileName = tempFileName;
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }

        try {
            fileRemove(deleteFileName);
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    final void determineBackupFiles()
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        const backupFileNames = getBackupFileNames();
        _rollBackupCount = backupFileNames.length;
    }

    final string[] getBackupFileNames() @trusted
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        string[] result;
        result.reserve(100);

        try {
            const pattern = _fileBaseName ~ dtPattern ~ _fileExt;
            foreach (string fileName; dirEntries(_fileDir, pattern, SpanMode.shallow))
            {
                if (isBackupFile(fileName))
                {
                    version(Windows)
                        result ~= toLower(fileName);
                    else
                        result ~= fileName;
                }
            }
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }

        return result;
    }

    final ulong isBackupFile(const(string) fileName)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fileName=", fileName, ")");

        try {
            // Backup file has this pattern: baseName + "." + datePattern + extension
            const s = extractFileNameWithoutExt(fileName);
            const i = lastIndexOf(s, '.');
            const v = i >= 0 ? s[i + 1..$] : null;
            return v.length == dtLength ? LogOutputPatternParser.safeToInt!ulong(v) : 0u;
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return 0u; }
    }

    final string nextBackupFile()
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");
        scope (failure) assert(0, "Assume nothrow failed");

        const postfix = format(dtFormat, currentTime());
        return buildPath(_fileDir, _fileBaseName ~ postfix ~ _fileExt);
    }

    final SysTime nextCheckTimestamp(const(SysTime) n)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");
        scope (failure) assert(0, "Assume nothrow failed");

        SysTime result = n;
        final switch (_rollingOption.dateMode)
        {
            case RollingDateMode.topOfMonth:
                result.fracSecs = Duration.zero;
                result.second = 0;
                result.minute = 0;
                result.hour = 0;
                result.roll!"days"(1 - cast(int)result.day); // first day of month is 1
                return result.roll!"months"(1);
            case RollingDateMode.topOfWeek:
                result.fracSecs = Duration.zero;
                result.second = 0;
                result.minute = 0;
                result.hour = 0;
                return result.roll!"days"(7 - cast(int)result.dayOfWeek);
            case RollingDateMode.topOfDay:
                result.fracSecs = Duration.zero;
                result.second = 0;
                result.minute = 0;
                result.hour = 0;
                return result.roll!"days"(1);
            case RollingDateMode.topOfHour:
                result.fracSecs = Duration.zero;
                result.second = 0;
                result.minute = 0;
                return result.roll!"hours"(1);
        }
    }

    final void renameFiles(const(SysTime) t, const(ulong) s)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        doClose();

        // Any limit?
        // Check if over count limit; if so delete the oldest
        if (_rollingOption.maxRollBackupCount != 0
            && _rollBackupCount >= _rollingOption.maxRollBackupCount)
        {
            string[] backupFileNames = getBackupFileNames();
            if (backupFileNames.length >= _rollingOption.maxRollBackupCount)
            {
                size_t i;
                backupFileNames.sort();
                while (backupFileNames.length - i >= _rollingOption.maxRollBackupCount)
                {
                    deleteFile(backupFileNames[i]);
                    i++;
                }
            }
            _rollBackupCount = _rollingOption.maxRollBackupCount - 1;
        }

        const toName = nextBackupFile();
        rollFile(_fileName, toName);
        _rollBackupCount++;
    }

    final void rollFile(const(string) fromName, const(string) toName)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(fromName=", fromName, ", toName=", toName, ")");

        deleteFile(toName);
        try {
            fileRename(fromName, toName);
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

private:
    enum dtLength = 14;
    static immutable string dtFormat = ".%cyyyymmddhhnnss";
    static immutable string dtPattern = ".??????????????";

    RollingFileLoggerOption _rollingOption;
    SysTime _rollTimestamp;
    size_t _rollBackupCount;
}

struct LogArgumentWriter
{
nothrow @safe:

public:
    this(Logger logger)
    {
        this.logger = logger;
    }

    static bool getException(Arg)(ref Logger.LogHeader header, Arg arg)
    {
        alias argType = typeof(arg);
        static if (is(argType == class))
        {
            if (isException!argType())
            {
                header.exception = cast(Exception)arg;
                return true;
            }
        }
        return false;
    }

    static bool isException(T)()
    if (is(T == class))
    {
        static const exceptionTypeId = typeid(Exception);
        return typeid(T).isBaseOf(exceptionTypeId);
    }

    void put(scope const(char)[] msgText)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        logger.commitMsg(msgText);
    }

    void put(dchar msgChar)
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        char[4] buffer;
        const len = encode!(Yes.useReplacementDchar)(buffer, msgChar);
        logger.commitMsg(buffer[0..len]);
    }

    void put(Args...)(ref Logger.LogHeader header, Args args) @trusted
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        try {
            const hasException = args.length && getException(header, args[args.length - 1]);
            foreach (i, arg; args)
            {
                alias argType = typeof(arg); //Args[i];

                if (hasException && i == args.length - 1)
                    break;

                static if (!is(isSomeString!(argType)) && isDynamicArray!(argType) && is(typeof(Unqual!(argType.init[0])) == ubyte))
                {
                    auto argBytes = cast(const(ubyte)[])arg;
                    logger.commitMsg(toHexString(argBytes));
                }
                else
                    logger.commitMsg(to!string(arg)); // Need to use 'to' function to convert to avoid cycle calls vs put(char[])
            }
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    void putf(Args...)(ref Logger.LogHeader header, scope const(char)[] fmt, Args args) @trusted
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        try {
            if (args.length)
                getException(header, args[args.length - 1]);

            formattedWrite(this, fmt, args);
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    static string toHexString(scope const(ubyte)[] bytes) @trusted
    {
        import std.ascii : hexDigits = hexDigits;
        import std.exception : assumeUnique;

        auto result = new char[](bytes.length*2);
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
    enum Kind : ubyte
    {
        literal,
        pattern,
    }

public:
    size_t calPadLength(ptrdiff_t padLength, const(size_t) valueLength) const pure @nogc
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

    static LogOutputPatternElement.Kind parseElement(ref LogOutputPatternElement element)
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

protected:
    static T safeToInt(T)(scope const(char)[] s, T failedValue = T.init) pure
    {
        try {
            return s.length != 0 ? s.to!T() : failedValue;
        }
        catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return failedValue; }
    }

private:
    static bool isSameNext(string s, size_t n, char c) pure
    {
        return n < s.length && s[n] == c;
    }

    static void parseElementFormat(ref LogOutputPatternElement element)
    {
        if (element.pattern[0] != OutputPatternMarker.format)
            return;

        auto fmtBuffer = Appender!string(element.pattern.length);
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

    static void parseElementPads(ref LogOutputPatternElement element)
    {
        size_t bMarker = notSet;
        size_t i = 0;

        int getPad() nothrow @safe
        {
            scope (failure) assert(0, "Assume nothrow failed");

            auto result = safeToInt!int(element.pattern[bMarker..i]);
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

    alias format = pham.external.std.log.log_date_time_format.format;
    alias formattedWrite = pham.external.std.log.log_date_time_format.formattedWrite;
    alias pad = pham.external.std.log.log_date_time_format.pad;

@safe:

version(Windows)
    enum char dirSeparator = '\\';
else
    enum char dirSeparator = '/';

    // 4 chars for log text alignment
    static immutable string[LogLevel.max + 1] logLevelTexts = [
        "trac", "debg", "info", "warn", "erro", "crit", "fata", "????"
    ];

    static immutable string newLineLiteral = "\n";

public:
    this(Logger logger)
    {
        this.logger = logger;
    }

    static string arrayOfChar(size_t count, char c) nothrow pure
    {
        auto result = new char[](count);
        result[] = c;
        return result.idup;
    }

    static string date(const ref LogOutputPatternElement element, in SysTime value) nothrow @trusted
    {
        // Special try construct for grep
        try {
            // %s=FmtTimeSpecifier.sortableDateTime
            auto s = element.fmt.length != 0 ? format(element.fmt, value) : format("%s", value);
            return pad(element, s);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return null; }
    }

    static void date(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, in SysTime value) nothrow @trusted
    {
        // Special try construct for grep
        try {
            // %s=FmtTimeSpecifier.sortableDateTime
            ShortStringBuffer!char s;
            if (element.fmt.length)
                formattedWrite(s, element.fmt, value);
            else
                formattedWrite(s, "%s", value);
            const lp = padLeft(sink, element, s.length);
            put(sink, s[]);
            padRight(sink, element, s.length + lp);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    static string fileName(const ref LogOutputPatternElement element, string fileName) nothrow
    {
        return text(element, separatedStringPart(fileName, dirSeparator, element.detailLevel + 1));
    }

    static void fileName(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, string fileName) nothrow
    {
        text(sink, element, separatedStringPart(fileName, dirSeparator, element.detailLevel + 1));
    }

    static string funcName(const ref LogOutputPatternElement element, string funcName) nothrow
    {
        const detailLevel = element.detailLevel;
        return text(element, separatedStringPart(funcName, '.', detailLevel + 1));
    }

    static void funcName(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, string funcName) nothrow
    {
        const detailLevel = element.detailLevel;
        text(sink, element, separatedStringPart(funcName, '.', detailLevel + 1));
    }

    static string integer(I)(const ref LogOutputPatternElement element, I value) nothrow
    if (isIntegral!I)
    {
        // Special try construct for grep
        try {
            auto s = element.fmt.length != 0 ? format(element.fmt, value) : format("%s", value);
            return pad(element, s);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return null; }
    }

    static void integer(Writer, I)(auto ref Writer sink, const ref LogOutputPatternElement element, I value) nothrow
    if (isIntegral!I)
    {
        // Special try construct for grep
        try {
            ShortStringBuffer!char s;
            if (element.fmt.length)
                formattedWrite(s, element.fmt, value);
            else
                formattedWrite(s, "%s", value);
            const lp = padLeft(sink, element, s.length);
            put(sink, s[]);
            padRight(sink, element, s.length + lp);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
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
        // Special try construct for grep
        try {
            put(sink, newLineLiteral);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
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

    static size_t padLeft(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, size_t valueLength) nothrow
    {
        // Special try construct for grep
        try {
            if (const p = element.calPadLength(element.leftPad, valueLength))
            {
                size_t n = p;
                while (n--)
                    put(sink, ' ');
                return p;
            }
            else
                return 0u;
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return 0u; }
    }

    static size_t padRight(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, size_t valueLength) nothrow
    {
        // Special try construct for grep
        try {
            if (const p = element.calPadLength(element.rightPad, valueLength))
            {
                size_t n = p;
                while (n--)
                    put(sink, ' ');
                return p;
            }
            else
                return 0u;
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return 0u; }
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
        try {
            if (element.fmt.length)
                value = format(element.fmt, value);
            return pad(element, value);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return null; }
    }

    static void text(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, string value) nothrow
    {
        try {
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
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
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
        try {
            return value !is null ? text(element, value.to!string()) : text(element, null);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); return null; }
    }

    static void userContext(Writer)(auto ref Writer sink, const ref LogOutputPatternElement element, Object value) nothrow @trusted
    {
        try {
            if (value !is null)
                text(sink, element, value.to!string());
            else
                text(sink, element, null);
        } catch (Exception e) { debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(), msg=", e.msg); }
    }

    void write(Writer)(scope auto ref Writer sink, ref Logger.LogEntry payload) @trusted
    {
        auto patternParser = LogOutputPatternParser(logger.outputPattern);
        while (!patternParser.empty)
        {
            LogOutputPatternElement element = void;
            const elementKind = patternParser.next(element);
            final switch (elementKind) with (LogOutputPatternElement.Kind)
            {
                case literal:
                    sink.put(element.value);
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
                            fileName(sink, element, payload.header.location.fileName);
                            break;
                        case OutputPatternName.level:
                            logLevel(sink, element, payload.header.logLevel);
                            break;
                        case OutputPatternName.line:
                            integer(sink, element, payload.header.location.line);
                            break;
                        case OutputPatternName.logger:
                            text(sink, element, payload.logger.name);
                            break;
                        case OutputPatternName.message:
                            text(sink, element, payload.message);
                            break;
                        case OutputPatternName.method:
                            funcName(sink, element, payload.header.location.funcName);
                            break;
                        case OutputPatternName.newLine:
                            newLine(sink, element);
                            break;
                        case OutputPatternName.stacktrace:
                            /// The stack trace of the logging event The stack trace level specifier may be enclosed between braces
                            // TODO - output stack
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
                            sink.put(element.value);
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
    @disable void opAssign(typeof(this));

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
        in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__)
    {
        this.message = message;
        this.payload.logger = logger;
        this.payload.header.logLevel = LogLevel.info;
        this.payload.header.location = LogLocation(line, fileName, funcName, moduleName);
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
                payload.header.timestamp = currentTime();
                payload.logger.forwardLog(payload);
            }
            this.startedTimestamp = currentTime();
        }
    }

    ~this()
    {
        if (canLog())
            log();
    }

    version(none) // Just use this instead: xxx = LogTimming.init;
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
            payload.header.timestamp = currentTime();
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
                payload.header.timestamp = currentTime();
                payload.logger.forwardLog(payload);
            }
            startedTimestamp = currentTime();
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
    @disable this(this);
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
    this(Logger toSharedLog, Logger toThreadLog = null)
    in
    {
        assert(toSharedLog !is null);
    }
    do
    {
        const setThreadLog = toThreadLog !is null;

        this.done = false;
        this.save(setThreadLog);

        sharedLog = toSharedLog;
        sharedLogLevel = toSharedLog.logLevel;

        if (setThreadLog)
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
            if (savedThreadLog !is null)
            {
                savedThreadLog.logLevel = savedThreadLog_Level;
                threadLog = savedThreadLog;
            }

            savedSharedLog.logLevel = savedSharedLog_Level;
            sharedLog = savedSharedLog;

            sharedLogLevel = savedSharedLogLevel;

            done = true;
        }
    }

private:
    void save(const(bool) setThreadLog)
    {
        savedSharedLogLevel = sharedLogLevel;

        savedSharedLog = sharedLog;
        savedSharedLog_Level = savedSharedLog.logLevel;

        if (setThreadLog)
        {
            savedThreadLog = threadLog;
            savedThreadLog_Level = savedThreadLog.logLevel;
        }
    }

    Logger savedSharedLog, savedThreadLog;
    LogLevel savedSharedLog_Level, savedThreadLog_Level, savedSharedLogLevel;
    bool done;
}

static immutable SysTime appStartupTimestamp;

/**
 * Returns Clock.currTime as local time
 */
SysTime currentTime() nothrow @safe
{
    scope (failure) assert(0, "Assume nothrow failed");

    return Clock.currTime;
}

deprecated("No longer used - please use logLevel of logger instance")
@property LogLevel globalLogLevel() @nogc nothrow @trusted
{
    return defaultGlobalLogLevel;
}

deprecated("No longer used - please set logLevel of logger instance")
@property LogLevel globalLogLevel(LogLevel ll) nothrow @trusted
{
    return defaultGlobalLogLevel;
}

/**
 * This property sets and gets the default `Logger`.
 * `sharedLog` is only thread-safe if the the used `Logger` is thread-safe.
 * The default `Logger` is thread-safe.
 * Example:
 * -------------
 * sharedLog = new FileLogger(yourFile);
 * -------------
 * The example sets a new `FileLogger` as new `sharedLog`.
 * If at some point you want to use the original default logger again, you can
 * use $(D sharedLog = null;). This will put back the original.
 * Note:
 *  While getting and setting `sharedLog` is thread-safe, it has to be considered
 *  that the returned reference is only a current snapshot and in the following
 *  code, you must make sure no other thread reassigns to it between reading and
 *  writing `sharedLog`.
 * -------------
 * if (sharedLog !is myLogger)
 *     sharedLog = new myLogger;
 * -------------
 */
@property Logger sharedLog() nothrow @trusted
{
    // If we have set up our own logger use that
    if (auto logger = atomicLoad(_sharedLog))
        return logger;
    else
        return sharedLogImpl; // Otherwise resort to the default logger
}

/// Ditto
@property Logger sharedLog(Logger logger) nothrow @trusted
in
{
    assert(logger !is null);
}
do
{
    return atomicExchange(&_sharedLog, logger);
}

@property LogLevel sharedLogLevel() @nogc nothrow @trusted
{
    return atomicLoad(_sharedLogLevel);
}

/// Ditto
@property LogLevel sharedLogLevel(LogLevel ll) nothrow @trusted
{
    const result = atomicExchange(&_sharedLogLevel, ll);
    if (auto logger = atomicLoad(_sharedLog))
        logger.logLevel = ll;
    return result;
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
    if (auto logger = _threadForwardLog)
        return logger;
    else
        return threadForwardLogImpl; // Otherwise resort to the default logger
}

/// Ditto
@property Logger threadLog(Logger logger) nothrow @safe
in
{
    assert(logger !is null);
}
do
{
    return atomicExchange(&_threadForwardLog, logger);
}

private string osCharToString(scope const(char)[] v) nothrow
{
    import std.conv : to;
    scope (failure) assert(0, "Assume nothrow failed");

    auto result = v.to!string();
    while (result.length && result[$ - 1] <= ' ')
        result = result[0..$ - 1];
    return result;
}

private string osWCharToString(scope const(wchar)[] v) nothrow
{
    import std.conv : to;
    scope (failure) assert(0, "Assume nothrow failed");

    auto result = v.to!string();
    while (result.length && result[$ - 1] <= ' ')
        result = result[0..$ - 1];
    return result;
}

/**
 * Returns current OS login name (name of the user associated with the current thread.)
 * If the function fails, the return value is null.
 */
string currentUserName() nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winbase : GetUserNameW;

        wchar[1000] result = void;
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else version(Posix)
    {
        import core.sys.posix.unistd : getlogin_r;

        char[1000] result = '\0';
        uint len = result.length - 1;
        if (getlogin_r(&result[0], len) == 0)
            return osCharToString(result[]);
        else
            return null;
    }
    else
    {
        pragma(msg, "currentUserName() not supported");
        return null;
    }
}


private:

Logger _threadForwardLog;
__gshared Logger _sharedLog;
__gshared ModuleLoggerOptions _moduleOptions;
__gshared LogLevel _sharedLogLevel = defaultLogLevel;

class SharedLogger : FileLogger
{
    import std.stdio : File;

public:
    this(File file, LoggerOption option = defaultOption()) @safe
    {
        super(file, option);
    }

    static LoggerOption defaultOption() nothrow @safe
    {
        return LoggerOption(sharedLogLevel, "SharedLogger", defaultOutputPattern, 5);
    }
}

/*
 * This method returns the global default Logger.
 * Marked @trusted because of excessive reliance on __gshared data
 */
__gshared align(__traits(classInstanceAlignment, SharedLogger)) void[__traits(classInstanceSize, SharedLogger)] _sharedLogBuffer;
__gshared SharedLogger _sharedLogDefault;
Logger sharedLogImpl() nothrow @trusted
{
    import std.concurrency : initOnce;
    import std.stdio : stderr;
    scope (failure) assert(0, "Assume nothrow failed");

    initOnce!(_sharedLogDefault)({
        auto buffer = cast(ubyte[])_sharedLogBuffer;
        return emplace!SharedLogger(buffer, stderr, SharedLogger.defaultOption());
    }());
    return _sharedLogDefault;
}

/**
 * The `ForwardSharedLogger` will always forward anything to the sharedLog.
 * The `ForwardSharedLogger` will not throw if data is logged with $(D LogLevel.fatal).
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
        return LoggerOption(lowestLogLevel, "ForwardSharedLogger", defaultOutputPattern, 0);
    }

protected:
    final override void doFatal() nothrow @safe
    {}

    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "()");

        sharedLog.forwardLog(payload);
    }
}

/*
 * This method returns the thread local default Logger for sharedLog.
 */
align(__traits(classInstanceAlignment, ForwardSharedLogger)) void[__traits(classInstanceSize, ForwardSharedLogger)] _threadForwardLogBuffer;
ForwardSharedLogger _threadForwardLogDefault;
Logger threadForwardLogImpl() nothrow @trusted
{
    if (_threadForwardLogDefault is null)
    {
        auto buffer = cast(ubyte[])_threadForwardLogBuffer;
        _threadForwardLogDefault = emplace!ForwardSharedLogger(buffer, ForwardSharedLogger.defaultOption());
    }
    return _threadForwardLogDefault;
}

shared static this() nothrow @trusted
{
    appStartupTimestamp = currentTime();
    _moduleOptions = new ModuleLoggerOptions(null);
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
    assert(sharedLogLevel == defaultLogLevel);

    auto dl = sharedLog;
    assert(dl !is null);
    assert(dl.logLevel == defaultLogLevel, dl.logLevel.to!string());

    auto tl = threadLog;
    assert(tl !is null);
    assert(tl.logLevel == lowestLogLevel, tl.logLevel.to!string());
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
    auto timestamp = SysTime(DateTime(1, 1, 1, 1, 1, 1), dur!"msecs"(1), null);
    debug(debug_pham_external_std_log_log_logger) debug writeln(LogOutputWriter.date(datePattern, timestamp));
    assert(LogOutputWriter.date(datePattern, timestamp) == "0001-01-01T01:01:01.001000");

    // fileName
    immutable string fileName = "c:"
        ~ LogOutputWriter.dirSeparator ~ "directory"
        ~ LogOutputWriter.dirSeparator ~ "subdir"
        ~ LogOutputWriter.dirSeparator ~ "core.d";
    LogOutputPatternElement filePattern;
    assert(LogOutputWriter.fileName(filePattern, fileName) == "core.d");
    filePattern.detailLevel = 1;
    debug(debug_pham_external_std_log_log_logger) debug writeln(LogOutputWriter.fileName(filePattern, fileName));
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
    LogOutputPatternElement funcPattern;
    assert(LogOutputWriter.funcName(funcPattern, funcName) == "dot");
    funcPattern.detailLevel = 1;
    assert(LogOutputWriter.funcName(funcPattern, funcName) == "Point.dot");
    funcPattern.detailLevel = 2;
    assert(LogOutputWriter.funcName(funcPattern, funcName) == "core.Point.dot");

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

version(unittest)
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
            scope (failure) assert(0, "Assume nothrow failed");

            return "logLevel=" ~ logLevel.to!string() ~ " vs expectedLogLevel=" ~ expectedLogLevel.to!string()
                ~ ", lvl=" ~ lvl.to!string()
                ~ ", line=" ~ location.line.to!string() ~ (expectedLine != 0 ? " vs expectedline=" ~ expectedLine.to!string() : "")
                ~ ", msg=" ~ msg
                ~ ", exceptionMessage=" ~ exceptionMessage
                ;
        }

        static LoggerOption defaultOption() nothrow pure @safe
        {
            return LoggerOption(defaultUnitTestLogLevel, "TestLogger", defaultOutputPattern, 0);
        }

        final uint line() const nothrow pure @safe
        {
            return location.line;
        }

        final void reset() nothrow pure @safe
        {
            lvl = defaultUnitTestLogLevel;
            location.clear();
            msg = exceptionMessage = outputMessage = null;
        }

    protected:
        // Do not terminated testing process
        final override void doFatal() nothrow @safe
        {}

        final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
        {
            debug(debug_pham_external_std_log_log_logger) debug writeln(__FUNCTION__, "(logLevel=", payload.header.logLevel, ", funcName=", payload.header.location.funcName, ", message=", payload.message, ")");
            scope (failure) assert(0, "Assume nothrow failed");

            this.lvl = payload.header.logLevel;
            this.location = payload.header.location;
            this.msg = payload.message;
            this.exceptionMessage = payload.header.exception !is null ? payload.header.exception.msg : null;

            auto buffer = Appender!string(500);
            auto writer = LogOutputWriter(this);
            writer.write(buffer, payload);
            this.outputMessage = buffer.data;
        }

    public:
        LogLocation location;
        string msg;
        string exceptionMessage;
        string outputMessage;
        LogLevel lvl;
    }
}

version(unittest)
void testFuncNames(Logger logger) @safe
{
    static string s = "I'm here";
    logger.log(s);
}

@safe unittest // Test compilable without error
{
    sharedLog.trace("Test calling without error");
}

@safe unittest
{
    void dummy() @safe
    {
        auto tl = new TestLogger();
        Logger.LogHeader hdr;
        auto dst = LogArgumentWriter(tl);
        dst.put(hdr, "aaa", "bbb");
    }

    dummy();
}

@safe unittest
{
    auto tl1 = new TestLogger();
    testFuncNames(tl1);
    debug(debug_pham_external_std_log_log_logger) debug writeln("tl1.location.funcName=", tl1.location.funcName, ", tl1.msg=", tl1.msg);
    assert(tl1.location.funcName == "pham.external.std.log.log_logger.testFuncNames", tl1.location.funcName);
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
    assert(tl1.line == line, tl1.line.to!string() ~ " vs " ~ line.to!string());
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

    auto logRestore = LogRestore(tl1, tl1);

    log(to!string(__LINE__)); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    log(LogLevel.info, __LINE__.to!string()); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    log(true, __LINE__.to!string()); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    log(LogLevel.warn, true, __LINE__.to!string()); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));

    logTrace(__LINE__.to!string()); line = __LINE__;
    assert(tl1.line == line, tl1.debugString(line, sharedLogLevel));
}

@safe unittest
{
    import pham.external.std.log.log_multi_logger : MultiLogger;

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
    assert(l.line == lineNumber, l.line.to!string());
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

    auto logRestore = LogRestore(l, l);

    assert(sharedLog.logLevel == defaultUnitTestLogLevel);

    msg = "Another message";
    log(msg); lineNumber = __LINE__;
    assert(l.logLevel == defaultUnitTestLogLevel);
    assert(l.line == lineNumber, l.line.to!string());
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
    assert(tl.line == l, tl.line.to!string());
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
    auto logRestore = LogRestore(memS, memS);

    const levels = [LogLevel.trace, LogLevel.debug_,
        LogLevel.info, LogLevel.warn, LogLevel.error,
        LogLevel.critical, LogLevel.fatal, LogLevel.off];

    int value = 0;
    string valueS = value.to!string();
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

                const canLog = defaultRequestLogLevel >= ll && ll != LogLevel.off && gll != LogLevel.off && ll >= gll;

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
            valueS = value.to!string();
            value2S = format("%d%d", value, value);
        }
    }
}

// testing more possible log conditions
@safe unittest
{
    auto mem = new TestLogger();
    auto logRestore = LogRestore(mem, mem);

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

                    mem.location.line = 0;
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
    auto logRestore = LogRestore(tl, tl);

    logTrace("trace");
    assert(tl.msg.indexOf("trace") == -1);
}

// Issue #5
@safe unittest
{
    import std.string : indexOf;
    import pham.external.std.log.log_multi_logger : MultiLogger;

    auto logger = new MultiLogger(LoggerOption(LogLevel.error, "Multi", defaultOutputPattern, 0));
    auto tl = new TestLogger(LoggerOption(LogLevel.info, "Test", defaultOutputPattern, 0));
    logger.insertLogger("required", tl);
    auto logRestore = LogRestore(logger, logger);

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

// check that thread-local logging does not propagate to shared logger
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

    auto ignore = new IgnoredLog;
    auto logRestore = LogRestore(ignore, ignore);

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
    static immutable systemToStringMsg = "SystemToString";
    static immutable exceptionMsg = "Test exception";

    static struct SystemToString
    {
        string toString() @system
        {
            return systemToStringMsg;
        }
    }

    int line;
    auto tl = new TestLogger();

    SystemToString sts;
    tl.logf("%s", sts); line = __LINE__;
    assert(tl.msg == systemToStringMsg);
    assert(tl.line == line);
}

@safe unittest // Test with exception
{
    static immutable systemToStringMsg = "SystemToString";
    static immutable exceptionMsg = "Test exception";

    int line;
    auto tl = new TestLogger();

    try
    {
        throw new Exception(exceptionMsg);
    }
    catch (Exception ex)
    {
        tl.log(systemToStringMsg, ex); line = __LINE__;
    }
    assert(tl.msg == systemToStringMsg, tl.msg);
    assert(tl.line == line);
    assert(tl.exceptionMessage == exceptionMsg, tl.exceptionMessage);

    try
    {
        throw new Exception(exceptionMsg);
    }
    catch (Exception ex)
    {
        tl.logf("%s", systemToStringMsg, ex); line = __LINE__;
    }
    assert(tl.msg == systemToStringMsg, tl.msg);
    assert(tl.line == line);
    assert(tl.exceptionMessage == exceptionMsg, tl.exceptionMessage);
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
    import std.stdio : File, writeln;
    import std.string : indexOf;

    string fn = tempDir.buildPath("bug15517.log");
    scope (exit)
    {
        if (exists(fn))
            remove(fn);
    }

    auto ts = [ "Test log 1", "Test log 2", "Test log 3"];

    { // Scope
        auto fl = new FileLogger(fn, FileLoggerOption(FileLoggerOption.overwriteMode), LoggerOption(defaultUnitTestLogLevel, "Test", defaultOutputPattern, 0));
        scope (exit)
            fl.file.close();

        auto logRestore = LogRestore(fl, fl);

        foreach (t; ts)
        {
            log(t);
        }
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
    import std.stdio : File;
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

    auto f = new FileLogger(filename, FileLoggerOption(FileLoggerOption.overwriteMode), LoggerOption(defaultUnitTestLogLevel, "Test", defaultOutputPattern, 0));
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
    import std.stdio : File;
    import std.string : indexOf;

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    auto file = File(filename, "w");
    scope (exit)
    {
        file.close();
        remove(filename);
    }
    auto lg = new FileLogger(file);

    static immutable string notWritten = "this should not be written to file";
    static immutable string written = "this should be written to file";

    lg.logLevel = LogLevel.critical;
    lg.log(LogLevel.warn, notWritten);
    lg.log(LogLevel.critical, written);
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

    const filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    auto lg = new FileLogger(filename);
    scope (exit)
    {
        lg.doClose();
        remove(filename);
    }

    auto logRestore = LogRestore(lg, lg);
    sharedLogLevel = LogLevel.critical;
    assert(sharedLogLevel == LogLevel.critical);

    static immutable string notWritten = "this should not be written to file";
    static immutable string written = "this should be written to file";
    log(LogLevel.warn, notWritten);
    log(LogLevel.critical, written);
    lg.doClose();

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
    auto logRestore = LogRestore(l, l);

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

    const fn = deleteme ~ "-FileLogger.log";
    auto fl = new FileLogger(deleteme);
    scope (exit)
        remove(deleteme);
    auto logRestore = LogRestore(fl, fl);

    auto tempLog = threadLog;
    destroy(tempLog);
}

@safe unittest // LogOutputWriter
{
    import std.conv : to;
    import std.stdio : writeln;

    string testMessage = "message text";
    auto tl = new TestLogger();
    LogOutputPatternElement blankPattern, datePattern;
    SysTime atTimestamp;
    string atfileName, atfuncName;
    int atLine;

    datePattern.fmt = "%S";

    void setFunctionInfo(int line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__)
    {
        atfileName = fileName;
        atfuncName = funcName;
        atTimestamp = currentTime();
    }

    void callLog()
    {
        setFunctionInfo();
        tl.log(tl.logLevel, testMessage); atLine = __LINE__;
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
        ~ LogOutputWriter.funcName(blankPattern, atfuncName) ~ ": "
        ~ LogOutputWriter.text(blankPattern, testMessage)
        ~ LogOutputWriter.newLine(blankPattern);
    debug(debug_pham_external_std_log_log_logger) debug writeln(tl.outputMessage);
    debug(debug_pham_external_std_log_log_logger) debug writeln(expectedOutput);
    assert(tl.outputMessage == expectedOutput, tl.outputMessage ~ " vs " ~ expectedOutput);

    tl.outputPattern = OutputPatternMarker.terminator ~ "'%S'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator
        ~ OutputPattern.userContext
        ~ OutputPattern.timestamp;
    callLog();
    expectedOutput = LogOutputWriter.date(datePattern, atTimestamp)
        ~ LogOutputWriter.text(blankPattern, TestLoggerCustomContext.customContext)
        ~ LogOutputWriter.timestamp(blankPattern, atTimestamp);
    debug(debug_pham_external_std_log_log_logger) debug writeln(tl.outputMessage);
    debug(debug_pham_external_std_log_log_logger) debug writeln(expectedOutput);
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
            Thread.sleep(warnMsecs + dur!"msecs"(2));
    }

    int msecs()
    {
        const i = tl.msg.indexOf(',');
        return tl.msg[0..i].to!int();
    }

    timeLog();
    assert(tl.msg == "0,timeLog", msg);

    timeLog(true);
    assert(msg == "0,Begin,timeLog" && tl.msg == "0,End,timeLog", msg);

    timeLog(false, dur!"msecs"(2));
    assert(msecs() >= 3 && tl.lvl == LogLevel.warn, msg);

    timeLog(true, dur!"msecs"(2));
    assert(msg == "0,Begin,timeLog" && msecs() >= 3 && tl.lvl == LogLevel.warn, msg);

    tl.reset();
    timeLog(true, dur!"msecs"(2), false);
    assert(tl.msg.length == 0, msg);
}

unittest // ModuleLoggerOptions.wildPackageName
{
    assert(ModuleLoggerOptions.wildPackageName("pham.external.std.log.logger") == "pham.external.std.log.*");
    assert(ModuleLoggerOptions.wildPackageName("logger") == "");
    assert(ModuleLoggerOptions.wildPackageName("") == "");
}

unittest // RollingFileLogger
{
    import std.conv : to;
    import std.file : deleteme, remove;
    import std.stdio : writeln;

    string fileName = deleteme ~ "-RollingFileLoggerTest.log";
    auto option = RollingFileLoggerOption(10_000, 1, RollingDateMode.topOfHour, RollingFileMode.composite);
    auto lg = new RollingFileLogger(fileName, option);
    scope (exit)
    {
        auto bfs = lg.getBackupFileNames();
        foreach (bf; bfs)
            remove(bf);
        lg.doClose();
        remove(fileName);
    }

    foreach (i; 0..1_000)
    {
        auto s = Appender!string(2_000);
        foreach (j; 50..100)
        {
            if (j > 50)
                s.put(' ');
            s.put(to!string(j));
        }
        lg.log(LogLevel.error, s.data);
    }
    auto bf = lg.getBackupFileNames();
    assert(bf.length == 1, bf.length.to!string());
}

unittest // default LogLevel
{
    import std.conv : to;
    import std.stdio : writeln;

    static class TestLogger : MemLogger
    {
    nothrow @safe:

        string[] allMessages;

    protected:
        final override void writeLog(ref Logger.LogEntry payload)
        {
            //debug writeln("logLevel=", logLevel, ", payload.logLevel=", payload.header.logLevel);

            allMessages ~= payload.message;
        }
    }

    const saveLogLevelShare = sharedLog.logLevel;
    const saveLogLevelThread = threadLog.logLevel;
    scope (exit)
        sharedLog.logLevel = saveLogLevelShare;
    scope (exit)
        threadLog.logLevel = saveLogLevelThread;

    auto testLogger = new TestLogger();
    testLogger.logLevel = sharedLogLevel;
    auto restore = LogRestore(testLogger, null);

    //debug writeln("sharedLogLevel=", sharedLogLevel, ", testLogger.logLevel=", testLogger.logLevel, ", sharedLog.logLevel=", sharedLog.logLevel);

    // Since this is just a forward to shareLog and shareLog.logLevel is still equal to 'warn'
    // hence only capture warn, error & critical messages
    threadLog.logLevel = lowestLogLevel;
    threadLog.log("log");
    threadLog.trace("trace");
    threadLog.info("info");
    threadLog.warn("warn");
    threadLog.error("error");
    threadLog.critical("critical");
    assert(testLogger.allMessages == ["warn", "error", "critical"], testLogger.allMessages.to!string);
    testLogger.allMessages = null;

    sharedLog.logLevel = lowestLogLevel;
    sharedLog.log("log");
    sharedLog.trace("trace");
    sharedLog.info("info");
    sharedLog.warn("warn");
    sharedLog.error("error");
    sharedLog.critical("critical");
    assert(testLogger.allMessages == ["log", "trace", "info", "warn", "error", "critical"], testLogger.allMessages.to!string);

    restore.restore();
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
