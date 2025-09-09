/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_fbservice_info;

public import core.time : Duration, dur;
import std.ascii : newline;

import pham.utl.utl_array_append : Appender;
import pham.utl.utl_enum_set : EnumSet;
import pham.db.db_convert : limitRangeTimeAsMilliSecond;
import pham.db.db_fbtype;

enum FbStatistical
{
	dataPages,
	databaseLog,
	headerPages,
	indexPages,
	systemTablesRelations,
}

enum FbTraceDatabaseEvent
{
	connections,
	transactions,
	statementPrepare,
	statementFree,
	statementStart,
	statementFinish,
	procedureStart,
	procedureFinish,
	functionStart,
	functionFinish,
	triggerStart,
	triggerFinish,
	context,
	errors,
	warnings,
	initFini,
	sweep,
	printPlan,
	explainPlan,
	printPerf,
	blrRequests,
	printBLR,
	dynRequests,
	printDYN,
}

enum FbTraceServiceEvent
{
	services,
	serviceQuery,
	errors,
	warnings,
	initFini,
}

enum FbTraceVersion : ubyte
{
	detect,
	version1,
	version2,
}

struct FbTraceDatabaseConfiguration
{
@safe:

public:
	bool enabled;
	string databaseName;
	EnumSet!FbTraceDatabaseEvent events;
	FbHandle connectionId;
	Duration timeThreshold = dur!"msecs"(500);
	int maxSQLLength = 500;
	int maxBLRLength = 500;
	int maxDYNLength = 500;
	int maxArgumentLength = 100;
	int maxArgumentsCount = 50;
	string includeFilter;
	string excludeFilter;
	string includeGdsCodes;
	string excludeGdsCodes;

	ref Appender!string buildConfiguration(return ref Appender!string result, FbTraceVersion traceVersion) const
    in
    {
        assert(traceVersion != FbTraceVersion.detect);
    }
    do
	{
		final switch (traceVersion)
		{
			case FbTraceVersion.version1:
				return buildConfiguration1(result);
			case FbTraceVersion.version2:
				return buildConfiguration2(result);
			case FbTraceVersion.detect:
				assert(0);
		}
	}

	ref Appender!string buildConfiguration1(return ref Appender!string result) const
	{
        return result.traceLineToIf()
            .traceRawTo("<database")
            .traceRegExTo(databaseName, version1Sep)
            .traceRawTo(">")
            .traceLineTo()
            .buildConfiguration(this, version1Sep, FbTraceVersion.version1)
            .traceRawTo("</database>");
	}

	ref Appender!string buildConfiguration2(return ref Appender!string result) const
	{
        return result.traceLineToIf()
            .traceRawTo("database")
            .traceRegExTo(databaseName, version2Sep)
            .traceLineTo()
            .traceRawTo("{")
            .traceLineTo()
            .buildConfiguration(this, version2Sep, FbTraceVersion.version2)
            .traceRawTo("}");
	}
}

ref Appender!string buildConfiguration(return ref Appender!string result, scope const(FbTraceDatabaseConfiguration)[] configurations, FbTraceVersion traceVersion) @safe
in
{
    assert(traceVersion != FbTraceVersion.detect);
}
do
{
    foreach (ref configuration; configurations)
        configuration.buildConfiguration(result, traceVersion);
    return result;
}

private ref Appender!string buildConfiguration(return ref Appender!string result, ref const(FbTraceDatabaseConfiguration) configuration, string sep, FbTraceVersion traceVersion) @safe
{
	result.traceBoolTo("enabled", sep, configuration.enabled)
        .traceRegExToIf("include_filter", sep, configuration.includeFilter)
        .traceRegExToIf("exclude_filter", sep, configuration.excludeFilter)
        .traceBoolTo("log_connections", sep, configuration.events.connections)
        .traceIntTo("connection_id", sep, configuration.connectionId)
        .traceBoolTo("log_transactions", sep, configuration.events.transactions)
        .traceBoolTo("log_statement_prepare", sep, configuration.events.statementPrepare)
        .traceBoolTo("log_statement_free", sep, configuration.events.statementFree)
        .traceBoolTo("log_statement_start", sep, configuration.events.statementStart)
        .traceBoolTo("log_statement_finish", sep, configuration.events.statementFinish)
        .traceBoolTo("log_procedure_start", sep, configuration.events.procedureStart)
        .traceBoolTo("log_procedure_finish", sep, configuration.events.procedureFinish)
        .traceBoolTo("log_trigger_start", sep, configuration.events.triggerStart)
        .traceBoolTo("log_trigger_finish", sep, configuration.events.triggerFinish)
        .traceBoolTo("log_context", sep, configuration.events.context)
        .traceBoolTo("log_errors", sep, configuration.events.errors)
        .traceBoolTo("log_warnings", sep, configuration.events.warnings)
        .traceBoolTo("log_initfini", sep, configuration.events.initFini)
        .traceBoolTo("log_sweep", sep, configuration.events.sweep)
        .traceBoolTo("print_plan", sep, configuration.events.printPlan)
        .traceBoolTo("print_perf", sep, configuration.events.printPerf)
        .traceBoolTo("log_blr_requests", sep, configuration.events.blrRequests)
        .traceBoolTo("print_blr", sep, configuration.events.printBLR)
        .traceBoolTo("log_dyn_requests", sep, configuration.events.dynRequests)
        .traceBoolTo("print_dyn", sep, configuration.events.printDYN)
        .traceIntTo("time_threshold", sep, configuration.timeThreshold.limitRangeTimeAsMilliSecond())
        .traceIntTo("max_sql_length", sep, configuration.maxSQLLength)
        .traceIntTo("max_blr_length", sep, configuration.maxBLRLength)
        .traceIntTo("max_dyn_length", sep, configuration.maxDYNLength)
        .traceIntTo("max_arg_length", sep, configuration.maxArgumentLength)
        .traceIntTo("max_arg_count", sep, configuration.maxArgumentsCount);

    if (traceVersion >= FbTraceVersion.version2)
    {
        result.traceStrToIf("include_gds_codes", sep, configuration.includeGdsCodes)
            .traceStrToIf("exclude_gds_codes", sep, configuration.excludeGdsCodes)
            .traceBoolTo("log_function_start", sep, configuration.events.functionStart)
            .traceBoolTo("log_function_finish", sep, configuration.events.functionFinish)
            .traceBoolTo("explain_plan", sep, configuration.events.explainPlan);
    }

    return result;
}

struct FbTraceServiceConfiguration
{
@safe:

public:
	bool enabled;
	EnumSet!FbTraceServiceEvent events;
	string includeFilter;
	string excludeFilter;
	string includeGdsCodes;
	string excludeGdsCodes;

	ref Appender!string buildConfiguration(return ref Appender!string result, FbTraceVersion traceVersion) const
    in
    {
        assert(traceVersion != FbTraceVersion.detect);
    }
    do
	{
		final switch (traceVersion)
		{
			case FbTraceVersion.version1:
				return buildConfiguration1(result);
			case FbTraceVersion.version2:
				return buildConfiguration2(result);
			case FbTraceVersion.detect:
				assert(0);
		}
	}

    // XML like format
	ref Appender!string buildConfiguration1(return ref Appender!string result) const
	{
        return result.traceLineToIf()
            .traceRawTo("<services>")
            .traceLineTo()
            .buildConfiguration(this, version1Sep, FbTraceVersion.version1)
            .traceRawTo("</services>");
	}

    // JSON like format
	ref Appender!string buildConfiguration2(return ref Appender!string result) const
	{
		return result.traceLineToIf()
            .traceRawTo("services")
            .traceLineTo()
            .traceRawTo("{")
            .traceLineTo()
            .buildConfiguration(this, version2Sep, FbTraceVersion.version2)
            .traceRawTo("}");
	}
}

private ref Appender!string buildConfiguration(return ref Appender!string result, ref const(FbTraceServiceConfiguration) configuration, string sep, FbTraceVersion traceVersion) @safe
{
	result.traceBoolTo("enabled", sep, configuration.enabled)
        .traceRegExToIf("include_filter", sep, configuration.includeFilter)
        .traceRegExToIf("exclude_filter", sep, configuration.excludeFilter)
        .traceBoolTo("log_services", sep, configuration.events.services)
        .traceBoolTo("log_service_query", sep, configuration.events.serviceQuery)
        .traceBoolTo("log_errors", sep, configuration.events.errors)
        .traceBoolTo("log_warnings", sep, configuration.events.warnings)
        .traceBoolTo("log_initfini", sep, configuration.events.initFini);

    if (traceVersion >= FbTraceVersion.version2)
    {
        result.traceStrToIf("include_gds_codes", sep, configuration.includeGdsCodes)
            .traceStrToIf("exclude_gds_codes", sep, configuration.excludeGdsCodes);
    }

    return result;
}

enum version1Sep = " ";
enum version2Sep = "=";

ref Appender!string traceBoolTo(return ref Appender!string appender, bool v) nothrow @safe
{
    appender.put(v != 0 ? "true" : "false");
    return appender;
}

ref Appender!string traceIntTo(return ref Appender!string appender, int v) @safe
{
    import std.format : sformat;

    char[50] buffer;
    appender.put(sformat(buffer[], "%d", v));
    return appender;
}

ref Appender!string traceLineTo(return ref Appender!string appender) nothrow @safe
{
    appender.put(newline);
    return appender;
}

ref Appender!string traceLineToIf(return ref Appender!string appender) nothrow @safe
{
    if (appender.length)
        appender.put(newline);
    return appender;
}

ref Appender!string traceRawTo(return ref Appender!string appender, string v) nothrow @safe
{
    appender.put(v);
    return appender;
}

ref Appender!string traceRegExTo(return ref Appender!string appender, string v,
    scope const(char)[] noneEmptyPrefix = null) @safe
{
    if (v.length == 0)
        return appender;

    if (noneEmptyPrefix.length)
        appender.put(noneEmptyPrefix);

    foreach (c; v)
    {
        // 1 backslash to 2 backslash
        if (c == '\\')
            appender.put("\\\\");
        // 1 single quote to escape single quote
        else if (c == '\'')
            appender.put("\\'");
        else
            appender.put(c);
    }
    return appender;
}

ref Appender!string traceStrTo(return ref Appender!string appender, string v,
    scope const(char)[] noneEmptyPrefix = null) nothrow @safe
{
    if (v.length == 0)
        return appender;

    if (noneEmptyPrefix.length)
        appender.put(noneEmptyPrefix);

    appender.put(v);
    return appender;
}

ref Appender!string traceBoolTo(return ref Appender!string appender, string name, string sep, bool v) nothrow @safe
{
    return appender.put(name)
        .put(sep)
        .traceBoolTo(v)
        .traceLineTo();
}

ref Appender!string traceIntTo(return ref Appender!string appender, string name, string sep, int v) @safe
{
    return appender.put(name)
        .put(sep)
        .traceIntTo(v)
        .traceLineTo();
}

ref Appender!string traceIntToIf(return ref Appender!string appender, string name, string sep, int v) @safe
{
    if (v)
    {
        return appender.put(name)
            .put(sep)
            .traceIntTo(v)
            .traceLineTo();
    }
    else
        return appender;
}

ref Appender!string traceRegExTo(return ref Appender!string appender, string name, string sep, string v) @safe
{
    return appender.put(name)
        .put(sep)
        .traceRegExTo(v)
        .traceLineTo();
}

ref Appender!string traceRegExToIf(return ref Appender!string appender, string name, string sep, string v) @safe
{
    if (v.length)
    {
        return appender.put(name)
            .put(sep)
            .traceRegExTo(v)
            .traceLineTo();
    }
    else
        return appender;
}

ref Appender!string traceStrTo(return ref Appender!string appender, string name, string sep, string v) nothrow @safe
{
    return appender.put(name)
        .put(sep)
        .traceStrTo(v)
        .traceLineTo();
}

ref Appender!string traceStrToIf(return ref Appender!string appender, string name, string sep, string v) nothrow @safe
{
    if (v.length)
    {
        return appender.put(name)
            .put(sep)
            .traceStrTo(v)
            .traceLineTo();
    }
    else
        return appender;
}
