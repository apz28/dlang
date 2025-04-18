/*
 * Clone from std.logger with enhancement API
 * https://github.com/dlang/phobos/blob/master/std/logger/package.d
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

/*
$(H3 Basic Logging)

Message logging is a common approach to expose runtime information of a
program. Logging should be easy, but also flexible and powerful, therefore
`D` provides a standard interface for logging.

The easiest way to create a log message is to write:
-------------
import pham.external.std.log.log_logger;

void main()
{
    log("Hello World");
}
-------------
This will print a message to the `stderr` device. The message will contain
the filename, the line number, the name of the surrounding function, the time
and the message.

More complex log call can go along the lines like:
-------------
log("Logging to the sharedLog with its default LogLevel");
logf(LogLevel.info, 5 < 6, "%s to the sharedLog with its LogLevel.info", "Logging");
info("Logging to the sharedLog with its info LogLevel");
warn(5 < 6, "Logging to the sharedLog with its LogLevel.warn if 5 is less than 6");
error("Logging to the sharedLog with its error LogLevel");
errorf("Logging %s the sharedLog %s its error LogLevel", "to", "with");
critical("Logging to the", " sharedLog with its error LogLevel");
fatal("Logging to the sharedLog with its fatal LogLevel");

auto fLogger = new FileLogger("NameOfTheLogFile");
fLogger.log("Logging to the fileLogger with its default LogLevel");
fLogger.info("Logging to the fileLogger with its default LogLevel");
fLogger.warn(5 < 6, "Logging to the fileLogger with its LogLevel.warning if 5 is less than 6");
fLogger.warnf(5 < 6, "Logging to the fileLogger with its LogLevel.warning if %s is %s than 6", 5, "less");
fLogger.critical("Logging to the fileLogger with its info LogLevel");
fLogger.log(LogLevel.trace, 5 < 6, "Logging to the fileLogger", " with its default LogLevel if 5 is less than 6");
fLogger.fatal("Logging to the fileLogger with its warning LogLevel");
-------------
Additionally, this example shows how a new `FileLogger` is created.
Individual `Logger` and the global log functions share commonly named
functions to log data.

The names of the functions are as follows:
$(UL
    $(LI `log`)
    $(LI `trace`)
    $(LI `info`)
    $(LI `warn`)
    $(LI `critical`)
    $(LI `fatal`)
)
The default `Logger` will by default log to `stderr` and has a default
`LogLevel` of `LogLevel.warn`. The default Logger can be accessed by
using the property called `sharedLog`. This property is a reference to the
current default `Logger`. This reference can be used to assign a new
default `Logger` with desired LogLevel.
-------------
sharedLog = new FileLogger("New_Default_Log_File.log");
-------------

Additional `Logger` can be created by creating a new instance of the
required `Logger`.

$(H3 Logging Fundamentals)
$(H4 LogLevel)
The `LogLevel` of a log call can be defined in two ways. The first is by
calling `log` and passing the `LogLevel` explicitly as the first argument.
The second way of setting the `LogLevel` of a
log call, is by calling either `trace`, `info`, `warn`,
`critical`, or `fatal`. The log call will then have the respective
`LogLevel`. If no `LogLevel` is defined the log call will use the
current `LogLevel` of the used `Logger`.

$(H4 Conditional Logging)
Conditional logging can be achieved be passing a `bool` as first
argument to a log function. If conditional logging is used the condition must
be `true` in order to have the log message logged.

In order to combine an explicit `LogLevel` passing with conditional
logging, the `LogLevel` has to be passed as first argument followed by the
`bool`.

$(H4 Filtering Log Messages)
Messages are logged if the `LogLevel` of the log message is greater than or
equal to the `LogLevel` of the used `Logger` and additionally if the
`LogLevel` of the log message is greater than or equal to the global `LogLevel`.
If a condition is passed into the log call, this condition must be true.

The global `LogLevel` is accessible by using `sharedLogLevel`.
To assign a `LogLevel` of a `Logger` use the `logLevel` property of
the logger.

$(H4 Printf Style Logging)
If `printf`-style logging is needed add a $(B f) to the logging call, such as
$(D myLogger.infof("Hello %s", "world");) or $(D fatalf("errno %d", 1337)).
The additional $(B f) appended to the function name enables `printf`-style
logging for all combinations of explicit `LogLevel` and conditional
logging functions and methods.

$(H4 Thread Local Redirection)
Calls to the free standing log functions are not directly forwarded to the
global `Logger` `sharedLog`. Actually, a thread local `Logger` of
type `ForwardThreadLogger` processes the log call and then, by default, forwards
the created `Logger.LogEntry` to the `sharedLog` `Logger`.
The thread local `Logger` is accessible by the `threadLog`
property. This property allows to assign user defined `Logger`. The default
`LogLevel` of the `threadLog` `Logger` is `LogLevel.trace`
and it will therefore forward all messages to the `sharedLog` `Logger`.
The `LogLevel` of the `threadLog` can be used to filter log
calls before they reach the `sharedLog` `Logger`.

$(H3 User Defined Logger)
To customize the `Logger` behavior, create a new `class` that inherits from
the `MemLogger` `class`, and implements the `writeLog` method or
abstract `Logger` and implements `beginMsg`, `commitMsg`, `endMsg` and `writeLog` methods
-------------
class MyCustomLogger : MemLogger
{
    protected final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        // log message in my custom way
    }
}

class MyCustomLogger : Logger
{
    public this(LoggerOptions options) nothrow @safe
    {
        super(options);
    }

    protected final override void beginMsg(ref Logger.LogHeader header) nothrow @safe
    {
        // log message in my custom way
    }

    protected final override void commitMsg(scope const(char)[] msg) nothrow @safe
    {
        // log message in my custom way
    }

    protected final override void endMsg(ref Logger.LogHeader header) nothrow @safe
    {
        // log message in my custom way
    }

    protected final override void writeLog(ref Logger.LogEntry payload) nothrow @safe
    {
        // log message in my custom way
    }
}

auto logger = new MyCustomLogger(LoggerOptions(LogLevel.info, "MyCustomLogger", defaultOutputPattern));
logger.log("Awesome log message with LogLevel.info");
-------------

To gain more precise control over the logging process, additionally to
overriding the `writeLog` method the methods `beginLog`,
`commitMsg` and `endMsg` can be overridden.

$(H3 Compile Time Disabling of `Logger`)
In order to disable logging at compile time, pass `DisableLogger...` as a
version argument to the `D` compiler when compiling your program code.
This will disable all logging functionality.

$(H3 Provided Logger)
By default four `Logger` implementations are given. The `FileLogger`
logs data to files. It can also be used to log to `stdout` and `stderr`
as these devices are files as well. A `Logger` that logs to `stdout` can
therefore be created by $(D new FileLogger(stdout)).
The `MultiLogger` is basically an associative array of `string`s to
`Logger`. It propagates log calls to its stored `Logger`. The
`ArrayLogger` contains an array of `Logger` and also propagates log
calls to its stored `Logger`. The `NullLogger` does not do anything. It
will never log a message and will never throw on a log call with `LogLevel`
`error`.
*/
module pham.external.std.log;

import pham.external.std.log.log_date_time_format;
public import pham.external.std.log.log_logger;
public import pham.external.std.log.log_multi_logger;
