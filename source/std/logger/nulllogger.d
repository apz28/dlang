// Written in the D programming language.
/**
Source: $(PHOBOSSRC std/experimental/logger/nulllogger.d)
*/
module std.logger.nulllogger;

import std.logger.core;

/** The `NullLogger` will not process any log messages.

In case of a log message with `LogLevel.fatal` nothing will happen.
*/
class NullLogger : Logger
{
    /** The default constructor for the `NullLogger`.

    Independent of the parameter this Logger will never log a message.

    Params:
      lv = The `LogLevel` for the `NullLogger`. By default the `LogLevel`
      for `NullLogger` is `LogLevel.all`.
    */
    this(const LogLevel lv = LogLevel.all) nothrow @safe
    {
        super(lv);
        this.fatalHandler = delegate() {};
    }

    final override void forwardMsg(ref LogEntry payload) nothrow @safe
    {}

    protected final override void writeLogMsg(ref LogEntry payload) nothrow @safe
    {}
}

///
@safe unittest
{
    import std.logger.core : LogLevel;

    auto nl1 = new NullLogger(LogLevel.all);
    nl1.info("You will never read this.");
    nl1.fatal("You will never read this, either and it will not throw");
}
