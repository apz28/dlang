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
import pham.db.db_type : int32, uint32;
import pham.db.db_fbisc;
import pham.db.db_fbtype : FbHandle;

enum FbBackupFlags : int32
{
	convert = FbIsc.isc_spb_bkp_convert,
	expand = FbIsc.isc_spb_bkp_expand,
	ignoreChecksums = FbIsc.isc_spb_bkp_ignore_checksums,
	ignoreLimbo = FbIsc.isc_spb_bkp_ignore_limbo,
	metaDataOnly = FbIsc.isc_spb_bkp_metadata_only,
	noDatabaseTriggers = FbIsc.isc_spb_bkp_no_triggers,
	noGarbageCollect = FbIsc.isc_spb_bkp_no_garbage_collect,
	nonTransportable = FbIsc.isc_spb_bkp_non_transportable,
	oldDescriptions = FbIsc.isc_spb_bkp_old_descriptions,
}

enum FbBackupRestoreStatistic : ubyte
{
	pageReads,
	pageWrites,
	timeDelta,
	totalTime,
}

enum FbNBackupFlags : int32
{
    noDatabaseTriggers = FbIsc.isc_spb_nbk_no_triggers,
}

enum FbRepairFlags : int32
{
	checkDatabase = FbIsc.isc_spb_rpr_check_db,
	full = FbIsc.isc_spb_rpr_full,
	ignoreChecksum = FbIsc.isc_spb_rpr_ignore_checksum,
	killShadows = FbIsc.isc_spb_rpr_kill_shadows,
	mendDatabase = FbIsc.isc_spb_rpr_mend_db,
	sweepDatabase = FbIsc.isc_spb_rpr_sweep_db,
	validateDatabase = FbIsc.isc_spb_rpr_validate_db,
}

enum FbRestoreFlags : int32
{
	create = FbIsc.isc_spb_res_create,
	deactivateIndexes = FbIsc.isc_spb_res_deactivate_idx,
	individualCommit = FbIsc.isc_spb_res_one_at_a_time,
	metaDataOnly = FbIsc.isc_spb_res_metadata_only,
	noShadow = FbIsc.isc_spb_res_no_shadow,
	noValidity = FbIsc.isc_spb_res_no_validity,
	replace = FbIsc.isc_spb_res_replace,
	useAllSpace = FbIsc.isc_spb_res_use_all_space,
}

enum FbShutdownType : ubyte
{
	force,
	attachments,
	transactions,
}

version(none)
enum FbShutdownMode : ubyte
{
	forced,
	denyConnection,
	denyTransaction,
}

enum FbShutdownActivateMode : ubyte
{
	normal,
	full,
	multi,
	single,
}

version(none)
enum FbStatistical : ubyte
{
	databaseLog,
	dataPages,
	headerPages,
	indexPages,
	systemTablesRelations,
}

enum FbTraceDatabaseEvent : ubyte
{
	blrRequests,
	connections,
	context,
	dynRequests,
	errors,
	explainPlan,
	functionFinish,
	functionStart,
	initFini,
	printBLR,
	printDYN,
	printPerf,
	printPlan,
	procedureFinish,
	procedureStart,
	statementFinish,
	statementFree,
	statementPrepare,
	statementStart,
	sweep,
	transactions,
	triggerStart,
	triggerFinish,
	warnings,
}

enum FbTraceServiceEvent : ubyte
{
	errors,
	initFini,
	serviceQuery,
	services,
	warnings,
}

enum FbTraceVersion : ubyte
{
	detect,
	version1,
	version2,
}

struct FbBackupFile
{
	string fileName;
	uint32 length;
}

struct FbBackupConfiguration
{
    string databaseName; // If empty, it will use connection databaseName
	FbBackupFile[] backupFiles;
	string skipData;
	FbBackupFlags options;
	EnumSet!FbBackupRestoreStatistic statistics;
	uint32 factor;
    uint32 parallelWorkers;
	bool verbose;
}

struct FbNBackupConfiguration
{
    string databaseName; // If empty, it will use connection databaseName
    string backupFileName;
    FbNBackupFlags options;
    uint32 level;
    bool directIO;
}

struct FbNRestoreConfiguration
{
    string databaseName; // If empty, it will use connection databaseName
	FbBackupFile[] backupFiles;
    bool directIO;
}

struct FbRepairConfiguration
{
    string databaseName; // If empty, it will use connection databaseName
    FbRepairFlags options;
    uint32 parallelWorkers;
}

struct FbRestoreConfiguration
{
    string databaseName; // If empty, it will use connection databaseName
	FbBackupFile[] backupFiles;
    string skipData;
	FbRestoreFlags options;
    EnumSet!FbBackupRestoreStatistic statistics;
    uint32 pageBuffers;
    uint32 pageSize;
    uint32 parallelWorkers;
    bool readOnly;
	bool verbose;
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

private ref Appender!string buildConfiguration(return ref Appender!string result, ref const(FbTraceDatabaseConfiguration) configuration,
    string sep, FbTraceVersion traceVersion) @safe
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

private ref Appender!string buildConfiguration(return ref Appender!string result, ref const(FbTraceServiceConfiguration) configuration,
    string sep, FbTraceVersion traceVersion) @safe
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

ref Appender!string buildConfiguration(return ref Appender!string result, scope const(EnumSet!FbBackupRestoreStatistic) statistics) nothrow @safe
{
	if (statistics.totalTime)
		result.put("T");
	if (statistics.timeDelta)
		result.put("D");
	if (statistics.pageReads)
		result.put("R");
	if (statistics.pageWrites)
		result.put("W");

    return result;
}

string buildConfiguration(scope const(EnumSet!FbBackupRestoreStatistic) statistics) nothrow @safe
{
    Appender!string result;
    return buildConfiguration(result, statistics).data;
}

ubyte toIscCode(FbShutdownActivateMode mode) @nogc nothrow pure @safe
{
    final switch (mode)
	{
		case FbShutdownActivateMode.normal:
            return FbIsc.isc_spb_prp_sm_normal;
		case FbShutdownActivateMode.full:
            return FbIsc.isc_spb_prp_sm_full;
		case FbShutdownActivateMode.multi:
            return FbIsc.isc_spb_prp_sm_multi;
		case FbShutdownActivateMode.single:
            return FbIsc.isc_spb_prp_sm_single;
	}
}

ubyte toIscCode(FbShutdownType type) @nogc nothrow pure @safe
{
    final switch (type)
	{
		case FbShutdownType.force:
            return FbIsc.isc_spb_prp_force_shutdown;
		case FbShutdownType.attachments:
            return FbIsc.isc_spb_prp_attachments_shutdown;
		case FbShutdownType.transactions:
            return FbIsc.isc_spb_prp_transactions_shutdown;
	}
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
    import pham.utl.utl_text : simpleIntegerFmt, stringOfNumber;

    char[50] buffer = 0;
    appender.put(stringOfNumber(buffer[], v, simpleIntegerFmt()));
    return appender;
}

ref Appender!string traceIntTo(return ref Appender!string appender, long v) @safe
{
    import pham.utl.utl_text : simpleIntegerFmt, stringOfNumber;

    char[50] buffer = 0;
    appender.put(stringOfNumber(buffer[], v, simpleIntegerFmt()));
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
