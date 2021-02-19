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
module std.logger.core;

import core.atomic : atomicLoad, atomicStore,  MemoryOrder;
import core.sync.mutex : Mutex;
import core.thread : ThreadID;
import core.time : Duration, msecs;
public import std.ascii : newline;
import std.conv : to;
import std.datetime.date : DateTime;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : LocalTime, UTC;
import std.format : formattedWrite;
import std.process : thisThreadID;
import std.range.primitives;
import std.stdio : File;
import std.traits;
import std.typecons : Flag;

version (DebugLogger) import std.stdio : writeln;

string eValue(E)(E value) nothrow pure
if (is(E Base == enum))
{
    return cast(string)value;
}

/**
 * There are eight usable logging level. These level are $(I all), $(I trace),
 * $(I info), $(I warn), $(I error), $(I critical), $(I fatal), and $(I off).
 */
enum LogLevel : ubyte
{
    all = 1, /** Lowest possible assignable `LogLevel`. */
    trace = 32, /** `LogLevel` for tracing the execution of the program. */
    info = 64, /** This level is used to display information about the program. */
    warn = 96, /** warnings about the program should be displayed with this level. */
    error = 128, /** Information about errors should be logged with this level.*/
    critical = 160, /** Messages that inform about critical errors should be logged with this level. */
    fatal = 192,   /** Log messages that describe fatal errors should use this level. */
    off = ubyte.max /** Highest possible `LogLevel`. */
}

enum defaultLogLevel = LogLevel.warn;
enum defaultSharedLogLevel = LogLevel.all;

/**
 * This template evaluates if the passed `LogLevel` is active.
 * The previously described version statements are used to decide if the
 * `LogLevel` is active. The version statements only influence the compile
 * unit they are used with, therefore this function can only disable logging this
 * specific compile unit.
 */
template isLoggingActiveAt(LogLevel ll)
{
    version (DisableLogger)
    {
        enum isLoggingActiveAt = false;
    }
    else
    {
        static if (ll == LogLevel.trace)
        {
            version (DisableLoggerTrace) enum isLoggingActiveAt = false;
        }
        else static if (ll == LogLevel.info)
        {
            version (DisableLoggerInfo) enum isLoggingActiveAt = false;
        }
        else static if (ll == LogLevel.warn)
        {
            version (DisableLoggerWarn) enum isLoggingActiveAt = false;
        }
        else static if (ll == LogLevel.error)
        {
            version (DisableLoggerError) enum isLoggingActiveAt = false;
        }
        else static if (ll == LogLevel.critical)
        {
            version (DisableLoggerCritical) enum isLoggingActiveAt = false;
        }
        else static if (ll == LogLevel.fatal)
        {
            version (DisableLoggerFatal) enum isLoggingActiveAt = false;
        }

        // If `isLoggingActiveAt` didn't get defined above to false,
        // we default it to true.
        static if (!is(typeof(isLoggingActiveAt) == bool))
        {
            enum isLoggingActiveAt = true;
        }
    }
}

/// This compile-time flag is `true` if logging is not statically disabled.
enum isLoggingActive = isLoggingActiveAt!(LogLevel.all);

/**
 * This functions is used at runtime to determine if a `LogLevel` is
 * active. The same previously defined version statements are used to disable
 * certain levels. Again the version statements are associated with a compile
 * unit and can therefore not disable logging in other compile units.
 * bool isLoggingEnabled(LogLevel ll) nothrow @nogc pure @safe
 */
bool isLoggingEnabled(const LogLevel ll, const LogLevel loggerLL, const LogLevel globalLL) @nogc nothrow pure @safe
{
    version (DebugLogger) debug writeln("ll=", ll, ", loggerLL=", loggerLL, ", globalLL=", globalLL);

    switch (ll)
    {
        case LogLevel.trace:
            version (DisableLoggerTrace) return false;
            else break;
        case LogLevel.info:
            version (DisableLoggerInfo) return false;
            else break;
        case LogLevel.warn:
            version (DisableLoggerWarn) return false;
            else break;
        case LogLevel.error:
            version (DisableLoggerError) return false;
            else break;
        case LogLevel.critical:
            version (DisableLoggerCritical) return false;
            else break;
        case LogLevel.fatal:
            version (DisableLoggerFatal) return false;
            else break;
        default: break;
    }

    return ll >= loggerLL && ll >= globalLL
        && ll != LogLevel.off && loggerLL != LogLevel.off && globalLL != LogLevel.off;
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
 * parent module. Then the moduleLogLevel is `LogLevel.all`.
 */
template moduleLogLevel(string moduleName)
if (!moduleName.length)
{
    // default
    enum moduleLogLevel = LogLevel.all;
}

/// ditto
template moduleLogLevel(string moduleName)
if (moduleName.length)
{
    import std.string : format;

    mixin(q{
        static if (__traits(compiles, {import %1$s : logLevel;}))
        {
            import %1$s : logLevel;
            static assert(is(typeof(logLevel) : LogLevel), "Expect 'logLevel' to be of Type 'LogLevel'.");
            // don't enforce enum here
            alias moduleLogLevel = logLevel;
        }
        else
            // use logLevel of package or default
            alias moduleLogLevel = moduleLogLevel!(parentOf(moduleName));
    }.format(moduleName ~ "_loggerconfig"));
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

struct LoggerOptions
{
    LogLevel logLevel = defaultLogLevel;
    string name;
    string outputPattern = defaultOutputPattern;
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
void log(string moduleName = __MODULE__, A...)(lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool) && !is(Unqual!(A[0]) == LogLevel)))
{
    version (DebugLogger) debug writeln("args.line=", line);

    static if (isLoggingActive)
    {
        auto logger = threadLog;
        logger.log!(moduleName, A)(logger.logLevel, args, ex, line, fileName, funcName, prettyFuncName);
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
void log(string moduleName = __MODULE__, A...)(lazy bool condition, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("condition.args.line=", line);

    static if (isLoggingActive)
    {
        auto logger = threadLog;
        logger.log!(moduleName, A)(logger.logLevel, condition, args, ex, line, fileName, funcName, prettyFuncName);
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
void log(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool)))
{
    version (DebugLogger) debug writeln("ll.args.line=", line);

    static if (isLoggingActive)
    {
        if (ll >= moduleLogLevel!moduleName)
        {
            threadLog.log!(moduleName, A)(ll, args, ex, line, fileName, funcName, prettyFuncName);
        }
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
void log(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy bool condition, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    static if (isLoggingActive)
    {
        if (ll >= moduleLogLevel!moduleName)
        {
            threadLog.log!(moduleName, A)(ll, condition, args, ex, line, fileName, funcName, prettyFuncName);
        }
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
void logf(string moduleName = __MODULE__, A...)(lazy string fmt, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool) && !is(Unqual!(A[0]) == LogLevel)))
{
    version (DebugLogger) debug writeln("fmt.args.line=", line);

    static if (isLoggingActive)
    {
        auto logger = threadLog;
        logger.logf!(moduleName, A)(logger.logLevel, fmt, args, ex, line, fileName, funcName, prettyFuncName);
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
void logf(string moduleName = __MODULE__, A...)(lazy bool condition, lazy string fmt, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("condition.fmt.args.line=", line);

    static if (isLoggingActive)
    {
        auto logger = threadLog;
        logger.logf!(moduleName, A)(logger.logLevel, condition, fmt, args, ex, line, fileName, funcName, prettyFuncName);
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
void logf(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy string fmt, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("ll.fmt.args.line=", line);

    static if (isLoggingActive)
    {
        if (ll >= moduleLogLevel!moduleName)
        {
            threadLog.logf!(moduleName, A)(ll, fmt, args, ex, line, fileName, funcName, prettyFuncName);
        }
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
void logf(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy bool condition, lazy string fmt, lazy A args, Exception ex = null,
    in int line = __LINE__, in string fileName = __FILE__,
    in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
{
    version (DebugLogger) debug writeln("ll.condition.fmt.args.line=", line);

    static if (isLoggingActive)
    {
        if (ll >= moduleLogLevel!moduleName)
        {
            threadLog.logf!(moduleName, A)(ll, condition, fmt, args, ex, line, fileName, funcName, prettyFuncName);
        }
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
    void defaultLogFunction(string moduleName = __MODULE__, A...)(lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool)))
    {
        version (DebugLogger) debug writeln("defaultLogFunction.args.line=", line);

        static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
        {
            threadLog.logFunction!(ll).logImpl!(moduleName, A)(args, ex, line, fileName, funcName, prettyFuncName);
        }
    }

    void defaultLogFunction(string moduleName = __MODULE__, A...)(lazy bool condition, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("defaultLogFunction.condition.args.line=", line);

        static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
        {
            threadLog.logFunction!(ll).logImpl!(moduleName, A)(condition, args, ex, line, fileName, funcName, prettyFuncName);
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
trace(1337, "is number");
info(1337, "is number");
error(1337, "is number");
critical(1337, "is number");
fatal(1337, "is number");
trace(true, 1337, "is number");
info(false, 1337, "is number");
error(true, 1337, "is number");
critical(false, 1337, "is number");
fatal(true, 1337, "is number");
--------------------
 */
alias trace = defaultLogFunction!(LogLevel.trace);
/// Ditto
alias info = defaultLogFunction!(LogLevel.info);
/// Ditto
alias warn = defaultLogFunction!(LogLevel.warn);
/// Ditto
alias error = defaultLogFunction!(LogLevel.error);
/// Ditto
alias critical = defaultLogFunction!(LogLevel.critical);
/// Ditto
alias fatal = defaultLogFunction!(LogLevel.fatal);

/**
 * This template provides the global `printf`-style log functions with
 * the `LogLevel` is encoded in the function name.
 * The aliases following this template create the public names of the log
 * functions.
 */
template defaultLogFunctionf(LogLevel ll)
{
    void defaultLogFunctionf(string moduleName = __MODULE__, A...)(lazy string fmt, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool)))
    {
        version (DebugLogger) debug writeln("defaultLogFunctionf.fmt.args.line=", line);

        static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
        {
            threadLog.logFunction!(ll).logImplf!(moduleName, A)(fmt, args, ex, line, fileName, funcName, prettyFuncName);
        }
    }

    void defaultLogFunctionf(string moduleName = __MODULE__, A...)(lazy bool condition, lazy string fmt, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("defaultLogFunctionf.condition.fmt.args.line=", line);

        static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
        {
            threadLog.logFunction!(ll).logImplf!(moduleName, A)(condition, fmt, args, ex, line, fileName, funcName, prettyFuncName);
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
tracef("is number %d", 1);
infof("is number %d", 2);
errorf("is number %d", 3);
criticalf("is number %d", 4);
fatalf("is number %d", 5);
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
tracef(false, "is number %d", 1);
infof(false, "is number %d", 2);
errorf(true, "is number %d", 3);
criticalf(true, "is number %d", 4);
fatalf(someFunct(), "is number %d", 5);
--------------------
 */
alias tracef = defaultLogFunctionf!(LogLevel.trace);
/// Ditto
alias infof = defaultLogFunctionf!(LogLevel.info);
/// Ditto
alias warnf = defaultLogFunctionf!(LogLevel.warn);
/// Ditto
alias errorf = defaultLogFunctionf!(LogLevel.error);
/// Ditto
alias criticalf = defaultLogFunctionf!(LogLevel.critical);
/// Ditto
alias fatalf = defaultLogFunctionf!(LogLevel.fatal);

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
     * constructor. It sets the `LoggerOptions`, and creates a fatal handler. The fatal
     * handler will throw an `Error` if a log call is made with level
     * `LogLevel.fatal`.
     * Params:
     *  options = `LoggerOptions` to use for this `Logger` instance.
     */
    this(LoggerOptions options = LoggerOptions.init) nothrow @safe
    {
        this.options = options;
        this.userName_ = currentUserName();
        this.mutex = new Mutex();
    }

    /**
     * This method allows forwarding log entries from one logger to another.
     * `forwardMsg` will ensure proper synchronization and then call
     * `writeLogMsg`. This is an API for implementing your own loggers and
     * should not be called by normal user code. A notable difference from other
     * logging functions is that the `sharedLogLevel` won't be evaluated again
     * since it is assumed that the caller already checked that.
     */
    void forwardLog(ref LogEntry payload) nothrow @safe
    {
        static if (isLoggingActive)
        try
        {
            synchronized (mutex)
            {
                if (isLoggingEnabled(payload.header.logLevel, this.options.logLevel, sharedLogLevel))
                {
                    this.writeLog(payload);
                }
            }
        }
        catch (Exception)
        {}
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
        return sharedLoad(cast(shared)(this.options.logLevel));
    }

    /// Ditto
    @property final Logger logLevel(const LogLevel value) nothrow @safe @nogc
    {
        sharedStore(cast(shared)(this.options.logLevel), value);
        return this;
    }

    @property final string name() nothrow @safe @nogc
    {
        scope (failure) assert(0);
        synchronized (mutex) return this.options.name;
    }

    @property final Logger name(string value) nothrow @safe @nogc
    {
        scope (failure) assert(0);
        synchronized (mutex) this.options.name = value;
        return this;
    }

    @property final string outputPattern() nothrow @safe @nogc
    {
        scope (failure) assert(0);
        synchronized (mutex) return this.options.outputPattern;
    }

    @property final Logger outputPattern(string value) nothrow @safe
    {
        scope (failure) assert(0);
        synchronized (mutex) this.options.outputPattern = value;
        return this;
    }

    @property final Object userContext() nothrow pure @trusted
    {
        return cast(Object)sharedLoad(cast(shared)(this.userContext_));
    }

    @property final Logger userContext(Object value) nothrow @trusted
    {
        sharedStore(cast(shared)(this.userContext_), cast(shared)value);
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
        final bool isImpl(string moduleName = __MODULE__)() nothrow @safe
        {
            static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
            {
                return isLoggingEnabled(ll, this.logLevel, sharedLogLevel);
            }
            else
            {
                return false;
            }
        }
    }

    /// Ditto
    alias isTrace = isFunction!(LogLevel.trace).isImpl;
    /// Ditto
    alias isInfo = isFunction!(LogLevel.info).isImpl;
    /// Ditto
    alias isWarn = isFunction!(LogLevel.warn).isImpl;
    /// Ditto
    alias isError = isFunction!(LogLevel.error).isImpl;
    /// Ditto
    alias isCritical = isFunction!(LogLevel.critical).isImpl;
    /// Ditto
    alias isFatal = isFunction!(LogLevel.fatal).isImpl;
    /// Ditto
    final bool isLogLevel(const LogLevel ll) nothrow @safe
    {
        final switch (ll)
        {
            case LogLevel.all: return isInfo();
            case LogLevel.trace: return isTrace();
            case LogLevel.info: return isInfo();
            case LogLevel.warn: return isWarn();
            case LogLevel.error: return isError();
            case LogLevel.critical: return isCritical();
            case LogLevel.fatal: return isFatal();
            case LogLevel.off: return false;
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
        final void logImpl(string moduleName = __MODULE__, A...)(lazy A args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool)))
        {
            version (DebugLogger) debug writeln("logFunction.args.line=", line);

            static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
            try
            {
                if (isFunction!(ll).isImpl()) synchronized (mutex)
                {
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.put!(A)(args);
                    this.endMsg();
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
        final void logImpl(string moduleName = __MODULE__, A...)(lazy bool condition, lazy A args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        {
            version (DebugLogger) debug writeln("logFunction.condition.args.line=", line);

            static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
            try
            {
                if (isFunction!(ll).isImpl() && condition) synchronized (mutex)
                {
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.put!(A)(args);
                    this.endMsg();
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
        final void logImplf(string moduleName = __MODULE__, A...)(lazy string fmt, lazy A args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : string)))
        {
            version (DebugLogger) debug writeln("logFunction.args.line=", line);

            static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
            try
            {
                if (isFunction!(ll).isImpl()) synchronized (mutex)
                {
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.putf(fmt, args);
                    this.endMsg();
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
        final void logImplf(string moduleName = __MODULE__, A...)(lazy bool condition, lazy string fmt, lazy A args, Exception ex = null,
            in int line = __LINE__, in string fileName = __FILE__,
            in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
        {
            version (DebugLogger) debug writeln("logFunction.condition.fmt.args.line=", line);

            static if (isLoggingActiveAt!ll && ll >= moduleLogLevel!moduleName)
            try
            {
                if (isFunction!(ll).isImpl() && condition) synchronized (mutex)
                {
                    auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                    this.beginMsg(header);
                    auto writer = LogArgumentWriter(this);
                    writer.putf(fmt, args);
                    this.endMsg();
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
    final void log(string moduleName = __MODULE__, A...)(lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool) && !is(Unqual!(A[0]) == LogLevel)))
    {
        version (DebugLogger) debug writeln("logger.args.line=", line);

        static if (isLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel(ll)) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.put!(A)(args);
                this.endMsg();
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
    final void log(string moduleName = __MODULE__, A...)(lazy bool condition, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("logger.condition.args.line=", line);

        static if (isLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel(ll) && condition) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.put!(A)(args);
                this.endMsg();
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
    final void log(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool)))
    {
        version (DebugLogger) debug writeln("logger.ll.args.line=", line);

        static if (isLoggingActive)
        try
        {
            if (ll >= moduleLogLevel!moduleName && isLogLevel(ll)) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.put!(A)(args);
                this.endMsg();
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
    final void log(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy bool condition, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("logger.ll.condition.args.line=", line);

        static if (isLoggingActive)
        try
        {
            if (ll >= moduleLogLevel!moduleName && isLogLevel(ll) && condition) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.put!(A)(args);
                this.endMsg();
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
    final void logf(string moduleName = __MODULE__, A...)(lazy string fmt, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    if (args.length == 0 || (args.length > 0 && !is(Unqual!(A[0]) : bool) && !is(Unqual!(A[0]) == LogLevel)))
    {
        version (DebugLogger) debug writeln("logger.fmt.args.line=", line);

        static if (isLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel(ll)) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.putf!(A)(fmt, args);
                this.endMsg();
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
    final void logf(string moduleName = __MODULE__, A...)(lazy bool condition, lazy string fmt, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("logger.condition.fmt.args.line=", line);

        static if (isLoggingActive)
        try
        {
            const ll = this.logLevel;
            if (isLogLevel(ll) && condition) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.putf!(A)(fmt, args);
                this.endMsg();
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
    final void logf(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy string fmt, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("logger.ll.fmt.args.line=", line);

        static if (isLoggingActive)
        try
        {
            if (ll >= moduleLogLevel!moduleName && isLogLevel(ll)) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.putf!(A)(fmt, args);
                this.endMsg();
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
    final void logf(string moduleName = __MODULE__, A...)(const LogLevel ll, lazy bool condition, lazy string fmt, lazy A args, Exception ex = null,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__) nothrow
    {
        version (DebugLogger) debug writeln("logger.ll.condition.fmt.args.line=", line);

        static if (isLoggingActive)
        try
        {
            if (ll >= moduleLogLevel!moduleName && isLogLevel(ll) && condition) synchronized (mutex)
            {
                auto header = LogHeader(ll, line, fileName, funcName, prettyFuncName, moduleName, thisThreadID, Clock.currTime, ex);
                this.beginMsg(header);
                auto writer = LogArgumentWriter(this);
                writer.putf!(A)(fmt, args);
                this.endMsg();
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
    LoggerOptions options;
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
    this(LoggerOptions options = LoggerOptions.init) nothrow @safe
    {
        super(options);
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
import std.array : Appender;

public:
    this(LoggerOptions options = LoggerOptions.init) nothrow @safe
    {
        super(options);
    }

protected:
    override void beginMsg(ref Logger.LogHeader header) nothrow @safe
    {
        static if (isLoggingActive)
        {
            msgBuffer = Appender!string();
            msgBuffer.reserve(1000);
            logEntry = Logger.LogEntry(this, header, null);
        }
    }

    override void commitMsg(scope const(char)[] msg) nothrow @safe
    {
        static if (isLoggingActive)
        {
            msgBuffer.put(msg);
        }
    }

    override void endMsg() nothrow @safe
    {
        static if (isLoggingActive)
        {
            this.logEntry.message = msgBuffer.data;
            this.writeLog(logEntry);
            // Reset to release its memory
            this.logEntry = Logger.LogEntry.init;
            this.msgBuffer = Appender!string();
        }
    }

    override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {}

protected:
    Appender!string msgBuffer;
    Logger.LogEntry logEntry;
}

/// An option to create $(LREF FileLogger) directory if it is non-existent.
alias CreateFolder = Flag!"CreateFolder";

/**
 * This `Logger` implementation writes log messages to the associated
 * file. The name of the file has to be passed on construction time.
 */
class FileLogger : MemLogger
{
import std.file : exists, mkdirRecurse;
import std.path : dirName;

public:
    /**
     * A constructor for the `FileLogger` Logger.
     * Params:
     *  fileName = The filename of the output file of the `FileLogger`. If that
     *      file can not be opened for writting, logLevel will switch to off.
     *  openMode = file mode open for appending or writing new file, default is appending
     *  options = default log options
     *  createFileFolder = if yes and fileName contains a folder name, this
     *      folder will be created.
     *
     * Example:
     *  auto l1 = new FileLogger("logFile.log");
     *  auto l2 = new FileLogger("logFile.log", "w");
     *  auto l3 = new FileLogger("logFile.log", "a", LoggerOptions(defaultOutputHeaderPatterns, LogLevel.fatal));
     *  auto l3 = new FileLogger("logFolder/logFile.log", "a", LoggerOptions(defaultOutputHeaderPatterns, LogLevel.fatal), CreateFolder.yes);
     */
    this(const string fileName, string openMode = "a",
        LoggerOptions options = LoggerOptions.init,
        CreateFolder createFileFolder = CreateFolder.yes) nothrow @safe
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
            options.logLevel = LogLevel.off;
        }

        super(options);
        this.fileName_ = fileName;
    }

    /**
     * A constructor for the `FileLogger` Logger that takes a reference to a `File`.
     * The `File` passed must be open for all the log call to the
     * `FileLogger`. If the `File` gets closed, using the `FileLogger`
     * for logging will result in undefined behaviour.
     * Params:
     *  file = The file used for logging.
     *  options = default log options
     * Example:
     *  auto file = File("logFile.log", "w");
     *  auto l1 = new FileLogger(file);
     *  auto l2 = new FileLogger(file, LoggerOptions(defaultOutputHeaderPatterns, LogLevel.fatal));
     */
    this(File file, LoggerOptions options = LoggerOptions.init) @safe
    {
        super(options);
        this.file_ = file;
    }

    ~this() nothrow @safe
    {
        try
        {
            file_ = File.init;
            fileName_ = null;
        }
        catch (Exception)
        {}
    }

    /**
     * If the `FileLogger` is managing the `File` it logs to, this
     * method will return a reference to this File.
     */
    @property final File file() nothrow @safe
    {
        return this.file_;
    }

    /**
     * If the `FileLogger` was constructed with a fileName, this method
     * returns this fileName. Otherwise an empty `string` is returned.
     */
    @property final string fileName() nothrow pure @safe
    {
        return this.fileName_;
    }

protected:
    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        try
        {
            auto writer = LogOutputWriter(this);
            writer.write(this.file_.lockingTextWriter(), payload);
            this.file_.flush();
        }
        catch (Exception e)
        {
            version (DebugLogger) debug writeln(e.msg);
        }
    }

protected:
    /** The `File` log messages are written to. */
    File file_;

    /** The filename of the `File` log messages are written to. */
    string fileName_;
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
        super(LoggerOptions(LogLevel.all, "Null", ""));
    }

    final override void forwardLog(ref Logger.LogEntry payload) nothrow @safe
    {}

protected:
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
import std.typecons : Yes;
import std.utf : encode;

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
        logger.commitMsg(buffer[0 .. len]);
    }

    void put(A...)(A args) @trusted
    {
        version (DebugLogger) debug writeln("put...");

        try
        {
            foreach (arg; args)
            {
                logger.commitMsg(to!string(arg)); // Need to use 'to' function to convert to avoid cycle calls vs put(char[])
            }
        }
        catch (Exception e)
        {
            version (DebugLogger) debug writeln(e.msg);
        }
    }

    void putf(A...)(scope const(char)[] fmt, A args) @trusted
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
    void resetPattern()
    {
        fmt = pattern = null;
        detailLevel = maxWidth = leftPad = rightPad = 0;
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
    uint maxWidth;
    int rightPad;
    Kind kind;
}

struct LogOutputPatternParser
{
import std.array : Appender;

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
                    element.maxWidth = getPad();
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
import std.algorithm.comparison : max, min;
import std.array : Appender, split;
import std.format : format;
import std.string : lastIndexOf;

import pham.utl.fmttime : formatDateTime;
import pham.utl.utlobject : pad, stringOfChar;

@safe:

version (Windows)
    enum char dirSeparator = '\\';
else
    enum char dirSeparator = '/';

    enum usePrettyFuncNameDetailLevel = 4;

public:
    this(Logger logger)
    {
        this.logger = logger;
    }

    void write(Writer)(auto ref Writer writer, ref Logger.LogEntry payload) @trusted
    {
        auto patternParser = LogOutputPatternParser(logger.outputPattern);
        while (!patternParser.empty)
        {
            LogOutputPatternElement element = void;
            final switch (patternParser.next(element)) with (LogOutputPatternElement.Kind)
            {
                case literal:
                    writer.put(element.value);
                    break;
                case pattern:
                    // Try matching a support pattern
                    string patternValue = null;
                    switch (element.pattern)
                    {
                        case OutputPatternName.userContext:
                            patternValue = userContext(element, payload.logger.userContext);
                            break;
                        case OutputPatternName.date:
                            patternValue = date(element, payload.header.timestamp);
                            break;
                        case OutputPatternName.filename:
                            patternValue = fileName(element, payload.header.fileName);
                            break;
                        case OutputPatternName.level:
                            patternValue = logLevel(element, payload.header.logLevel);
                            break;
                        case OutputPatternName.line:
                            patternValue = integer(element, payload.header.line);
                            break;
                        case OutputPatternName.logger:
                            patternValue = text(element, payload.logger.name);
                            break;
                        case OutputPatternName.message:
                            patternValue = text(element, payload.message);
                            break;
                        case OutputPatternName.method:
                            patternValue = funcName(element, payload.header.funcName, payload.header.prettyFuncName);
                            break;
                        case OutputPatternName.newLine:
                            patternValue = newLine(element);
                            break;
                        case OutputPatternName.stacktrace:
                            /// The stack trace of the logging event The stack trace level specifier may be enclosed between braces
                            //TODO
                            break;
                        case OutputPatternName.timestamp:
                            patternValue = timestamp(element, payload.header.timestamp);
                            break;
                        case OutputPatternName.thread:
                            patternValue = integer(element, payload.header.threadID);
                            break;
                        case OutputPatternName.username:
                            patternValue = text(element, payload.logger.userName);
                            break;
                        // Not matching any pattern, output as is
                        default:
                            writer.put(element.value);
                            break;
                    }
                    if (patternValue.length)
                        writer.put(patternValue);
                    break;
            }
        }
    }

    static string pad(const ref LogOutputPatternElement pattern, string value) nothrow @safe
    {
        // Truncate
        if (pattern.maxWidth > 0 && value.length > pattern.maxWidth)
        {
            return pattern.leftPad > 0 || pattern.rightPad == 0
                ? value[$ - pattern.maxWidth..$] // Get ending value if left pad
                : value[0..pattern.maxWidth]; // Get beginning value if right pad
        }

        if (pattern.leftPad > 0)
        {
            const p = pattern.maxWidth > 0 ? min(pattern.leftPad, pattern.maxWidth) : pattern.leftPad;
            value = pad(value, p, ' ');
        }

        // Right pad
        if (pattern.rightPad > 0)
        {
            const p = pattern.maxWidth > 0 ? min(pattern.rightPad, pattern.maxWidth) : pattern.rightPad;
            value = pad(value, -p, ' ');
        }

        return value;
    }

    // Wrapper of standard split to return null if exception (for nothrow requirement)
    static string[] safeSplit(string value, char separator) nothrow pure @safe
    {
        try
        {
            return value.split(separator);
        }
        catch(Exception)
        {
            return null;
        }
    }

    static string date(const ref LogOutputPatternElement pattern, in SysTime timestamp) nothrow @trusted
    {
        try
        {
            auto s = pattern.fmt.length != 0
                ? formatDateTime(pattern.fmt, timestamp)
                : formatDateTime("%s", timestamp); // %s=FmtTimeSpecifier.sortableDateTime
            return pad(pattern, s);
        }
        catch (Exception)
        {
            return null;
        }
    }

    static string fileName(const ref LogOutputPatternElement pattern, string fileName) nothrow @safe
    {
        try
        {
            string namePart(size_t count) nothrow @safe
            {
                string result = null;
                auto parts = safeSplit(fileName, dirSeparator);
                auto length = parts.length;
                while (count > 0 && length > 0)
                {
                    count--;
                    length--;
                    if (result.length == 0)
                        result = parts[length];
                    else
                        result = parts[length] ~ dirSeparator ~ result;
                }
                return result;
            }

            auto name = namePart(pattern.detailLevel + 1);
            if (pattern.fmt.length)
                name = format(pattern.fmt, name);
            return pad(pattern, name);
        }
        catch (Exception)
        {
            return null;
        }
    }

    static string funcName(const ref LogOutputPatternElement pattern, string funcName, string prettyFuncName) nothrow @safe
    {
        try
        {
            string namePart(size_t count) nothrow @safe
            {
                string result = null;
                auto parts = safeSplit(funcName, '.');
                auto length = parts.length;
                while (count > 0 && length > 0)
                {
                    count--;
                    length--;
                    if (result.length == 0)
                        result = parts[length];
                    else
                        result = parts[length] ~ '.' ~ result;
                }
                return result;
            }

            const detailLevel = pattern.detailLevel;
            auto name = detailLevel >= usePrettyFuncNameDetailLevel ? prettyFuncName : namePart(detailLevel + 1);
            if (pattern.fmt.length)
                name = format(pattern.fmt, name);
            return pad(pattern, name);
        }
        catch (Exception)
        {
            return null;
        }
    }

    static string integer(const ref LogOutputPatternElement pattern, int value) nothrow @safe
    {
        try
        {
            auto s = pattern.fmt.length != 0 ? format(pattern.fmt, value) : to!string(value);
            return pad(pattern, s);
        }
        catch (Exception)
        {
            return null;
        }

    }

    static string integer(const ref LogOutputPatternElement pattern, long value) nothrow @safe
    {
        try
        {
            auto s = pattern.fmt.length != 0 ? format(pattern.fmt, value) : to!string(value);
            return pad(pattern, s);
        }
        catch (Exception)
        {
            return null;
        }

    }

    static string logLevel(const ref LogOutputPatternElement pattern, LogLevel logLevel) nothrow @safe
    {
        try
        {
            return text(pattern, to!string(logLevel));
        }
        catch (Exception)
        {
            return null;
        }
    }

    static string newLine(const ref LogOutputPatternElement pattern) nothrow @safe
    {
        return newline;
    }

    static string text(const ref LogOutputPatternElement pattern, string value) nothrow @safe
    {
        try
        {
            if (pattern.fmt.length)
                value = format(pattern.fmt, value);
            return pad(pattern, value);
        }
        catch (Exception)
        {
            return null;
        }
    }

    static string timestamp(const ref LogOutputPatternElement pattern, in SysTime timestamp) nothrow
    {
        return integer(pattern, (timestamp - appStartupTimestamp).total!"msecs");
    }

    static string userContext(const ref LogOutputPatternElement pattern, Object object) nothrow @trusted
    {
        try
        {
            return object !is null ? text(pattern, to!string(object)) : text(pattern, null);
        }
        catch (Exception)
        {
            return null;
        }
    }

private:
    Logger logger;
}

struct LogTimming
{
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
    this(Logger logger,
        bool logBeginEnd = false,
        int warnMsecs = 0,
        in int line = __LINE__, in string fileName = __FILE__,
        in string funcName = __FUNCTION__, in string prettyFuncName = __PRETTY_FUNCTION__,
        in string moduleName = __MODULE__)
    {
        payload.logger = logger;
        payload.header.logLevel = LogLevel.info;
        payload.header.line = line;
        payload.header.fileName = fileName;
        payload.header.funcName = funcName;
        payload.header.prettyFuncName = prettyFuncName;
        payload.header.moduleName = moduleName;
        payload.header.threadID = thisThreadID;
        this.logBeginEnd = logBeginEnd;
        this.warnMsecs = warnMsecs;
        this.done = false;
        if (payload.logger !is null)
        {
            if (logBeginEnd)
            {
                payload.message = "0";
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
            const msecs = (payload.header.timestamp - startedTimestamp).total!"msecs";
            payload.header.logLevel = warnMsecs > 0 && msecs >= warnMsecs ? LogLevel.warn : LogLevel.info;
            payload.message = to!string(msecs);
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
                payload.message = "0";
                payload.header.logLevel = LogLevel.info;
                payload.header.timestamp = currTime();
                payload.logger.forwardLog(payload);
            }
            startedTimestamp = currTime();
        }
    }

private:
    Logger.LogEntry payload;
    SysTime startedTimestamp;
    int warnMsecs;
    bool done;
    bool logBeginEnd;
}

immutable SysTime appStartupTimestamp;

pragma(inline, true)
SysTime currTime() nothrow @safe
{
    scope (failure) assert(0);

    return Clock.currTime;
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
    if (auto logger = sharedLoad(sharedLog_))
        return cast(Logger)logger;
    else
        return sharedLogImpl; // Otherwise resort to the default logger
}

/// Ditto
@property void sharedLog(Logger logger) nothrow @trusted
{
    sharedStore(sharedLog_, cast(shared)logger);
}

/**
 * This methods get and set the global `LogLevel`.
 * Every log message with a `LogLevel` lower as the global `LogLevel`
 * will be discarded before it reaches `writeLogMessage` method of any `Logger`.
 */
@property LogLevel sharedLogLevel() @nogc nothrow @safe
{
    /*
    Implementation note:
    For any public logging call, the global log level shall only be queried once on
    entry. Otherwise when another threads changes the level, we would work with
    different levels at different spots in the code.
    */
    return sharedLoad(sharedLogLevel_);
}

/// Ditto
@property void sharedLogLevel(LogLevel ll) nothrow @safe
{
    sharedStore(sharedLogLevel_, ll);
    if (sharedLog_ !is null)
        sharedLog.logLevel = ll;
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
auto sharedLoad(T)(ref shared T value) nothrow @safe
{
    return atomicLoad!(MemoryOrder.acq)(value);
}

/// Thread safe to write value to a variable
void sharedStore(T)(ref shared T dst, shared T src) nothrow @safe
{
    atomicStore!(MemoryOrder.rel)(dst, src);
}

private:

class SharedLogger : FileLogger
{
public:
    this(File file, LoggerOptions options = defaultOptions()) @safe
    {
        super(file, options);
    }

    static LoggerOptions defaultOptions() nothrow @safe
    {
        return LoggerOptions(sharedLogLevel, "Shared", defaultOutputPattern);
    }
}

shared Logger sharedLog_;
__gshared SharedLogger sharedLogDefault_;
shared LogLevel sharedLogLevel_ = defaultSharedLogLevel;

/*
 This method returns the global default Logger.
 Marked @trusted because of excessive reliance on __gshared data
 */
@property Logger sharedLogImpl() nothrow @trusted
{
    import std.concurrency : initOnce;
    import std.conv : emplace;
    import std.stdio : stderr;

    scope (failure) assert(0);

    __gshared align(SharedLogger.alignof) void[__traits(classInstanceSize, SharedLogger)] _buffer;
    initOnce!sharedLogDefault_({
        auto buffer = cast(ubyte[]) _buffer;
        return emplace!SharedLogger(buffer, stderr, SharedLogger.defaultOptions());
    }());
    return sharedLogDefault_;
}

/**
 * The `ForwardThreadLogger` will always forward anything to the sharedLog.
 * The `ForwardThreadLogger` will not throw if data is logged with $(D
 * LogLevel.fatal).
 */
class ForwardThreadLogger : MemLogger
{
public:
    this(LoggerOptions options = defaultOptions()) nothrow @safe
    {
        super(options);
    }

    static LoggerOptions defaultOptions() nothrow pure @safe
    {
        return LoggerOptions(defaultSharedLogLevel, "Forward", defaultOutputPattern);
    }

protected:
    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        sharedLog.forwardLog(payload);
    }
}

/**
 * This `LogLevel` is unqiue to every thread.
 * The thread local `Logger` will use this `LogLevel` to filter log calls
 * every same way as presented earlier.
 */
Logger threadLog_;
ForwardThreadLogger threadLogDefault_;

/*
 This method returns the thread local default Logger.
 */
@property Logger threadLogImpl() nothrow @trusted
{
    import std.conv : emplace;

    static align(ForwardThreadLogger.alignof) void[__traits(classInstanceSize, ForwardThreadLogger)] _buffer;
    if (threadLogDefault_ is null)
    {
        auto buffer = cast(ubyte[]) _buffer;
        threadLogDefault_ = emplace!ForwardThreadLogger(buffer, ForwardThreadLogger.defaultOptions());
    }
    return threadLogDefault_;
}

string parentOf(string mod) nothrow @safe
{
    foreach_reverse (i, c; mod)
    {
        if (c == '.')
            return mod[0 .. i];
    }
    return null;
}

shared static this()
{
    appStartupTimestamp = currTime();
}

///
@safe unittest // moduleLogLevel
{
    static assert(moduleLogLevel!"" == LogLevel.all);
}

///
@system unittest // moduleLogLevel
{
    static assert(moduleLogLevel!"not.amodule.path" == LogLevel.all);
}

@safe unittest // sharedLogLevel
{
    LogLevel ll = sharedLogLevel;
    sharedLogLevel = LogLevel.fatal;
    assert(sharedLogLevel == LogLevel.fatal);
    sharedLogLevel = ll;
}

///
@safe unittest // create NullLogger
{
    auto nl1 = new NullLogger();
    nl1.info("You will never read this.");
    nl1.fatal("You will never read this, either and it will not throw");
}

///
@safe unittest // create ForwardThreadLogger
{
    auto nl1 = new ForwardThreadLogger();
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
        ~ OutputPatternMarker.terminator ~ "2l3r20m'mm/dd/yyyy'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator
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
    assert(element.pattern == OutputPatternName.date && element.value == OutputPatternMarker.terminator ~ "2l3r20m'mm/dd/yyyy'" ~ OutputPatternName.date ~ OutputPatternMarker.terminator);
    assert(element.leftPad == 2);
    assert(element.rightPad == 3);
    assert(element.maxWidth == 20);
    assert(element.fmt == "mm/dd/yyyy");

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.literal);
    assert(element.value == " - some literal in between - " && element.pattern.length == 0);

    assert(!parser.empty);
    kind = parser.next(element);
    assert(kind == LogOutputPatternElement.Kind.pattern);
    assert(element.pattern == OutputPatternName.filename && element.value == OutputPatternMarker.terminator ~ "50m" ~ OutputPatternName.filename ~ OutputPatternMarker.terminator);
    assert(element.maxWidth == 50);

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
    padPattern.maxWidth = 20;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890aB") == "345678901234567890aB"); // truncate from beginning
    padPattern.rightPad = 2;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890aB") == "12345678901234567890"); // truncate from ending
    padPattern.leftPad = 2;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890aB") == "345678901234567890aB");
    padPattern.maxWidth = padPattern.leftPad = padPattern.rightPad = 0;
    padPattern.leftPad = 22;
    assert(LogOutputWriter.pad(padPattern, "12345678901234567890") == "  12345678901234567890");
    padPattern.maxWidth = padPattern.leftPad = padPattern.rightPad = 0;
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
package class TestLoggerCustomContext
{
    override string toString() nothrow @safe
    {
        return customContext;
    }

    static immutable customContext = "Additional context";
}

version (unittest)
package class TestLogger : MemLogger
{
import std.array : Appender;
import std.conv : to;

public:
    this(LoggerOptions options = defaultOptions()) nothrow @safe
    {
        super(options);
        this.userContext = new TestLoggerCustomContext();
    }

    final string debugString(int expectedLine) nothrow @safe
    {
        scope (failure) assert(0);

        return "lvl=" ~ to!string(lvl) ~ ", line=" ~ to!string(line)
            ~ " vs expectedline=" ~ to!string(expectedLine)
            ~ ", msg=" ~ msg;
    }

    static LoggerOptions defaultOptions() nothrow pure @safe
    {
        return LoggerOptions(LogLevel.all, "Test", defaultOutputPattern);
    }

    final void reset() nothrow pure @safe
    {
        lvl = LogLevel.all;
        line = 0;
        file = func = outputMessage = prettyFunc = msg = null;
    }

protected:
    final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        scope (failure) assert(0);

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

version (unittest)
void testFuncNames(Logger logger) @safe
{
    string s = "I'm here";
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
    assert(tl1.func == "std.logger.core.testFuncNames", tl1.func);
    assert(tl1.prettyFunc == "void std.logger.core.testFuncNames(Logger logger) @safe", tl1.prettyFunc);
    assert(tl1.msg == "I'm here", tl1.msg);
}

@safe unittest
{
    import std.conv : to;

    auto tl1 = new TestLogger();
    tl1.log("");
    assert(tl1.line == __LINE__ - 1);
    tl1.log(true, "");
    assert(tl1.line == __LINE__ - 1);
    tl1.log(false, "");
    assert(tl1.line == __LINE__ - 3);
    tl1.log(LogLevel.info, "");
    assert(tl1.line == __LINE__ - 1);
    tl1.log(LogLevel.off, "");
    assert(tl1.line == __LINE__ - 3);
    tl1.log(LogLevel.info, true, "");
    assert(tl1.line == __LINE__ - 1);
    tl1.log(LogLevel.info, false, "");
    assert(tl1.line == __LINE__ - 3);

    auto oldunspecificLogger = sharedLog;
    scope(exit) {
        sharedLog = oldunspecificLogger;
    }

    sharedLog = tl1;

    log(to!string(__LINE__));
    assert(tl1.line == __LINE__ - 1, tl1.debugString(__LINE__ - 1));

    log(LogLevel.info, to!string(__LINE__));
    assert(tl1.line == __LINE__ - 1, tl1.debugString(__LINE__ - 1));

    log(true, to!string(__LINE__));
    assert(tl1.line == __LINE__ - 1, tl1.debugString(__LINE__ - 1));

    log(LogLevel.warn, true, to!string(__LINE__));
    assert(tl1.line == __LINE__ - 1, tl1.debugString(__LINE__ - 1));

    trace(to!string(__LINE__));
    assert(tl1.line == __LINE__ - 1, tl1.debugString(__LINE__ - 1));
}

@safe unittest
{
    import std.logger.multilogger : MultiLogger;

    auto tl1 = new TestLogger();
    auto tl2 = new TestLogger();

    auto ml = new MultiLogger();
    ml.insertLogger("one", tl1);
    ml.insertLogger("two", tl2);

    string msg = "Hello Logger World";
    ml.log(msg);
    int lineNumber = __LINE__ - 1;
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
    l.log(msg);
    int lineNumber = __LINE__ - 1;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    l.log(true, msg);
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg, l.msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    l.log(false, msg);
    assert(l.msg == msg);
    assert(l.line == lineNumber, to!string(l.line));
    assert(l.logLevel == LogLevel.all);

    msg = "%s Another message";
    l.logf(msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    l.logf(true, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    l.logf(false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    l.logf(LogLevel.fatal, false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    auto oldunspecificLogger = sharedLog;
    sharedLog = l;
    scope(exit)
    {
        sharedLog = oldunspecificLogger;
    }

    assert(sharedLog.logLevel == LogLevel.all);

    msg = "Another message";
    log(msg);
    lineNumber = __LINE__ - 1;
    assert(l.logLevel == LogLevel.all);
    assert(l.line == lineNumber, to!string(l.line));
    assert(l.msg == msg, l.msg);

    log(true, msg);
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    log(false, msg);
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    msg = "%s Another message";
    logf(msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    logf(true, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    logf(false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);

    logf(LogLevel.fatal, false, msg, "Yet");
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.all);
}

@safe unittest
{
    import std.conv : to;

    auto tl = new TestLogger();
    int l = __LINE__;
    tl.info("a");
    assert(tl.line == l+1);
    assert(tl.msg == "a");
    assert(tl.logLevel == LogLevel.all);
    l = __LINE__;
    tl.trace("b");
    assert(tl.msg == "b", tl.msg);
    assert(tl.line == l+1, to!string(tl.line));
}

// testing possible log conditions
@safe unittest
{
    import std.conv : to;
    import std.format : format;
    import std.string : indexOf;

    auto oldsharedLog = sharedLog;
    auto oldSharedLogLevel = sharedLogLevel;
    auto oldThreadLogLevel = threadLog.logLevel;

    auto mem = new TestLogger();
    auto memS = new TestLogger();
    sharedLog = memS;
    scope(exit)
    {
        sharedLog = oldsharedLog;
        sharedLogLevel = oldSharedLogLevel;
        threadLog.logLevel = oldThreadLogLevel;
    }

    auto levels = [cast(LogLevel) LogLevel.all, LogLevel.trace,
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

                    mem.log(ll2, valueS); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS), mem.debugString(__LINE__));
                    mem.log(ll2, valueS, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == value2S));
                    mem.log(ll2, value); assert(!canLog || (mem.line == __LINE__ && mem.msg == valueS), mem.debugString(__LINE__));
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

    auto oldSharedLog = sharedLog;
    auto oldSharedLogLevel = sharedLogLevel;
    auto oldThreadLogLevel = threadLog.logLevel;

    threadLog.logLevel = LogLevel.all;
    sharedLog = mem;
    scope(exit)
    {
        sharedLog = oldSharedLog;
        sharedLogLevel = oldSharedLogLevel;
        threadLog.logLevel = oldThreadLogLevel;
    }

    foreach (gll; [cast(LogLevel) LogLevel.all, LogLevel.trace,
            LogLevel.info, LogLevel.warn, LogLevel.error,
            LogLevel.critical, LogLevel.fatal, LogLevel.off])
    {
        sharedLogLevel = gll;
        foreach (ll; [cast(LogLevel) LogLevel.all, LogLevel.trace,
                LogLevel.info, LogLevel.warn, LogLevel.error,
                LogLevel.critical, LogLevel.fatal, LogLevel.off])
        {
            mem.logLevel = ll;
            foreach (tll; [cast(LogLevel) LogLevel.all, LogLevel.trace,
                    LogLevel.info, LogLevel.warn, LogLevel.error,
                    LogLevel.critical, LogLevel.fatal, LogLevel.off])
            {
                threadLog.logLevel = tll;
                foreach (cond; [true, false])
                {
                    assert(sharedLogLevel == gll);
                    assert(mem.logLevel == ll);

                    bool gllVSll = LogLevel.trace >= sharedLogLevel;
                    bool llVSgll = ll >= sharedLogLevel;
                    bool lVSll = LogLevel.trace >= ll;
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

                    trace(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.trace(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    trace(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.tracef("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    tracef("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.tracef(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    tracef(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = ll >= sharedLogLevel;
                    lVSll = LogLevel.info >= ll;
                    lVSgll = LogLevel.info >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll &&
                        lVSgll && cond;

                    mem.info(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    info(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.info(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    info(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.infof("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    infof("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.infof(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    infof(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = ll >= sharedLogLevel;
                    lVSll = LogLevel.warn >= ll;
                    lVSgll = LogLevel.warn >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll &&
                        lVSgll && cond;

                    mem.warn(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    warn(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.warn(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    warn(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.warnf("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    warnf("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.warnf(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    warnf(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = ll >= sharedLogLevel;
                    lVSll = LogLevel.critical >= ll;
                    lVSgll = LogLevel.critical >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll &&
                        lVSgll && cond;

                    mem.critical(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    critical(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.critical(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    critical(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.criticalf("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    criticalf("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.criticalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    criticalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    llVSgll = ll >= sharedLogLevel;
                    lVSll = LogLevel.fatal >= ll;
                    lVSgll = LogLevel.fatal >= tll;
                    test = llVSgll && gllVSll && lVSll && gllOff && llOff && cond;
                    testG = gllOff && llOff && tllOff && tllVSll && tllVSgll &&
                        lVSgll && cond;

                    mem.fatal(__LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    fatal(__LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.fatal(cond, __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    fatal(cond, __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.fatalf("%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    fatalf("%d", __LINE__); line = __LINE__;
                    assert(testG ? mem.line == line : true); line = -1;

                    mem.fatalf(cond, "%d", __LINE__); line = __LINE__;
                    assert(test ? mem.line == line : true); line = -1;

                    fatalf(cond, "%d", __LINE__); line = __LINE__;
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

    auto oldunspecificLogger = sharedLog;

    auto tl = new TestLogger(LoggerOptions(LogLevel.info, "Test", defaultOutputPattern));
    sharedLog = tl;
    scope(exit)
        sharedLog = oldunspecificLogger;

    trace("trace");
    assert(tl.msg.indexOf("trace") == -1);
}

// Issue #5
@safe unittest
{
    import std.logger.multilogger : MultiLogger;
    import std.string : indexOf;

    auto logger = new MultiLogger(LoggerOptions(LogLevel.error, "Multi", defaultOutputPattern));
    auto tl = new TestLogger(LoggerOptions(LogLevel.info, "Test", defaultOutputPattern));
    logger.insertLogger("required", tl);

    auto oldSharedLog = sharedLog;
    auto oldSharedLogLevel = sharedLogLevel;
    auto oldThreadLogLevel = threadLog.logLevel;

    sharedLog = logger;
    threadLog.logLevel = LogLevel.all;
    scope(exit)
    {
        sharedLog = oldSharedLog;
        sharedLogLevel = oldSharedLogLevel;
        threadLog.logLevel = oldThreadLogLevel;
    }

    trace("trace");
    assert(tl.msg.indexOf("trace") == -1);
    info("info");
    assert(tl.msg.indexOf("info") == -1);
    error("error");
    assert(tl.msg.indexOf("error") == 0);
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
            super(LoggerOptions(LogLevel.trace, "Test", defaultOutputPattern));
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
            super(LoggerOptions(LogLevel.trace, "Ignore", defaultOutputPattern));
        }

    protected:
        final override void writeLog(ref LogEntry payload) nothrow @safe
        {
            assert(false);
        }
    }

    auto oldSharedLog = sharedLog;
    sharedLog = new IgnoredLog;
    scope(exit)
    {
        sharedLog = oldSharedLog;
    }

    Thread[] spawned;

    foreach (i; 0 .. 4)
    {
        spawned ~= new Thread({
            threadLog = new TestLog;
            trace("zzzzzzzzzz");
        });
        spawned[$-1].start();
    }

    foreach (t; spawned)
        t.join();

    assert(atomicOp!"=="(logged_count, 4));
}

@safe unittest
{
    auto dl = cast(SharedLogger) sharedLog;
    assert(dl !is null);
    assert(dl.logLevel == defaultSharedLogLevel);
    assert(sharedLogLevel == defaultSharedLogLevel);

    auto tl = cast(ForwardThreadLogger) threadLog;
    assert(tl !is null);
    assert(tl.logLevel == defaultSharedLogLevel);
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

    auto fl = new FileLogger(fn, "w", LoggerOptions(LogLevel.all, "Test", defaultOutputPattern));
    scope (exit)
        fl.file.close();

    auto oldShared = sharedLog;
    sharedLog = fl;
    scope (exit)
        sharedLog = oldShared;

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

    scope(exit)
    {
        remove(filename);
    }

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

    auto f = new FileLogger(filename, "w", LoggerOptions(LogLevel.all, "Test", defaultOutputPattern));
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
    scope(exit)
        remove(filename);

    auto oldunspecificLogger = sharedLog;
    auto oldunspecificLogLevel = sharedLogLevel;
    sharedLog = l;
    sharedLogLevel = LogLevel.critical;
    scope(exit)
    {
        sharedLog = oldunspecificLogger;
        sharedLogLevel = oldunspecificLogLevel;
    }

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
    auto oldunspecificLogger = sharedLog;
    auto oldunspecificLogLevel = oldunspecificLogger.logLevel;
    scope(exit)
    {
        remove(filename);
        sharedLog = oldunspecificLogger;
        sharedLog.logLevel = oldunspecificLogLevel;
    }

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    auto l = new FileLogger(filename);
    sharedLog = l;
    sharedLog.logLevel = LogLevel.critical;

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
    auto oldThreadLog = threadLog;
    threadLog = new FileLogger(deleteme ~ "-someFile.log");
    scope(exit)
    {
        remove(deleteme ~ "-someFile.log");
        threadLog = oldThreadLog;
    }

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
    LogOutputPatternElement blankPattern;
    SysTime atTimestamp;
    string atfileName, atfuncName, atprettyFuncName;
    int atLine;

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

    callLog();
    auto expectedOutput = LogOutputWriter.date(blankPattern, atTimestamp)
        ~ " [" ~ LogOutputWriter.logLevel(blankPattern, tl.logLevel) ~ "] "
        ~ LogOutputWriter.fileName(blankPattern, atfileName) ~ "."
        ~ LogOutputWriter.integer(blankPattern, atLine) ~ "."
        ~ LogOutputWriter.funcName(blankPattern, atfuncName, atprettyFuncName) ~ ": "
        ~ LogOutputWriter.text(blankPattern, testMessage)
        ~ LogOutputWriter.newLine(blankPattern);
    version (DebugLogger) debug writeln(tl.outputMessage);
    version (DebugLogger) debug writeln(expectedOutput);
    assert(tl.outputMessage == expectedOutput, tl.outputMessage ~ " vs " ~ expectedOutput);

    tl.outputPattern = OutputPattern.date ~ OutputPattern.userContext ~ OutputPattern.timestamp;
    callLog();
    expectedOutput = LogOutputWriter.date(blankPattern, atTimestamp)
        ~ LogOutputWriter.text(blankPattern, TestLoggerCustomContext.customContext)
        ~ LogOutputWriter.timestamp(blankPattern, atTimestamp);
    version (DebugLogger) debug writeln(tl.outputMessage);
    version (DebugLogger) debug writeln(expectedOutput);
    assert(tl.outputMessage == expectedOutput, tl.outputMessage ~ " vs " ~ expectedOutput);
}

unittest // LogTimming
{
    import core.Thread;
    import std.conv : to;
    import std.stdio : writeln;

    auto tl = new TestLogger();

    void timeLog(bool logBeginEnd = false, int warnMsecs = 0, bool logIt = true) nothrow
    {
        auto timing = logIt ? LogTimming(tl, logBeginEnd, warnMsecs) : LogTimming.init;
        if (warnMsecs > 0)
            Thread.sleep(msecs(warnMsecs + 1));
    }

    timeLog(); assert(tl.msg == "0");
    timeLog(true); assert(tl.msg == "0");
    timeLog(false, 2); assert(to!int(tl.msg) >= 3);
    timeLog(true, 2); assert(to!int(tl.msg) >= 3);
    tl.reset(); timeLog(true, 2, false); assert(tl.msg.length == 0);
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
