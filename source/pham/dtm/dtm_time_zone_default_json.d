/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.dtm.dtm_time_zone_default_json;

import core.time : dur, Duration;
import std.array : split;
import std.json : JSONValue, parseJSON;
import std.uni : sicmp;

import pham.utl.utl_result : ResultIf;
import pham.dtm.dtm_date : DayOfWeek, DateTime;
import pham.dtm.dtm_date_time_parse;
import pham.dtm.dtm_tick : DateTimeZoneKind, ErrorOp, Tick, toDayOfWeekUS;
import pham.dtm.dtm_time_zone : AdjustmentRule, TimeZoneInfo, TransitionTime, ZoneOffset;

nothrow @safe:

TimeZoneInfo[] getDefaultTimeZoneInfosByJson(string jsonText) @trusted
{
    if (jsonText.length == 0)
        return null;

    // Special try construct for grep
    try {
        TimeZoneInfo[] result;
        result.reserve(200);

        auto js = parseJSON(jsonText);
        auto jsZones = js["zones"].array;
        foreach (ref jsZone; jsZones)
        {
            auto zone = toZone(jsZone);
            if (zone)
                result ~= zone;
        }

        return result;
    } catch (Exception) return null;
}


private:

ResultIf!DateTime toDateTime(string v)
// 1-1-1T0:0:0.0?unspecified
{
    auto vs = v.split("?");
    if (vs.length != 2)
        return ResultIf!DateTime.error(1, "Missing splitter '?'");

    auto pattern = DateTimePattern.usShortDateTime;
    pattern.dateSeparator = '-';
    pattern.timeSeparator = ':';
    pattern.patternText = "yyyy/mm/ddThh:nn:ss.zzzzzz";
    DateTime datetime;
    if (tryParse!DateTime(vs[0], pattern, datetime) != DateTimeParser.noError)
        return ResultIf!DateTime.error(1, "Invalid datetime: " ~ vs[0]);

    const kind = toKind(vs[1]);

    return kind
        ? ResultIf!DateTime.ok(datetime.asKind(kind))
        : ResultIf!DateTime.error(1, "Invalid datetime kind: " ~ vs[1]);
}

ResultIf!Duration toDeltaMinutes(long v) pure
{
    import std.conv : to;
    
    // + Tick.minutesPerHour in case of daylight saving
    enum int limit = Tick.minutesPerDay + Tick.minutesPerHour;

    const ti = toInt(v);
    return ti && ti >= -limit && ti <= limit
        ? ResultIf!Duration.ok(dur!"minutes"(ti))
        : ResultIf!Duration.error(1, "Minute delta is out of bound: " ~ v.to!string());
}

ResultIf!int toInt(long v) pure
{
    import std.conv : to;
    
    if (v < int.min || v > int.max)
        return ResultIf!int.error(1, "Integer is out of bound: " ~ v.to!string());
    else
        return ResultIf!int.ok(cast(int)v);
}

ResultIf!DateTimeZoneKind toKind(string v) pure
{
    if (v == "unspecified")
        return ResultIf!DateTimeZoneKind.ok(DateTimeZoneKind.unspecified);
    else if (v == "utc")
        return ResultIf!DateTimeZoneKind.ok(DateTimeZoneKind.utc);
    else if (v == "local")
        return ResultIf!DateTimeZoneKind.ok(DateTimeZoneKind.local);
    else
        return ResultIf!DateTimeZoneKind.error(1, "Invalid datetime kind: " ~ v);
}

ResultIf!AdjustmentRule toRule(ref JSONValue v) @trusted
{
    // Special try construct for grep
    try {
        const db = toDateTime(v["dateBegin"].str);
        const de = toDateTime(v["dateEnd"].str);
        const bdelta = ZoneOffset(toDeltaMinutes(v["baseUtcOffsetDelta"].integer));
        const ddelta = ZoneOffset(toDeltaMinutes(v["daylightDelta"].integer));
        const sdelta = ZoneOffset(toDeltaMinutes(v["standardDelta"].integer));
        const tb = toTransition(v["daylightTransitionBegin"].object);
        const te = toTransition(v["daylightTransitionEnd"].object);
        const nt = v["noDaylightTransitions"].boolean;

        return db && de && bdelta.isValid() == ErrorOp.none && ddelta.isValid() == ErrorOp.none && sdelta.isValid() == ErrorOp.none && tb && te
            ? ResultIf!AdjustmentRule.ok(AdjustmentRule(db, de, bdelta, ddelta, sdelta, tb, te, nt))
            : ResultIf!AdjustmentRule.error(1, "Invalid datetime rule");
    } catch (Exception) return ResultIf!AdjustmentRule.error(1, "Invalid datetime rule");
}

ResultIf!TransitionTime toTransition(ref JSONValue[string] v)
{
    // Special try construct for grep
    try {
        const tod = toDateTime(v["timeOfDay"].str);
        const m = toInt(v["month"].integer);
        const w = toInt(v["week"].integer);
        const d = toInt(v["day"].integer);
        const dow = toDayOfWeekUS(v["dayOfWeek"].str);
        const fixed = v["isFixedDateRule"].boolean;

        return tod && m && w && d && dow
            ? ResultIf!TransitionTime.ok(TransitionTime(tod, m, w, d, dow, fixed))
            : ResultIf!TransitionTime.error(1, "Invalid datetime transition");
    } catch (Exception) return ResultIf!TransitionTime.error(1, "Invalid datetime transition");
}

ResultIf!TimeZoneInfo toZone(ref JSONValue v) @trusted
{
    // Special try construct for grep
    try {
        const id = v["id"].str;
        const displayName = v["displayName"].str;
        const standardName = v["standardName"].str;
        const daylightName = v["daylightName"].str;
        const baseUtcOffset = ZoneOffset(toDeltaMinutes(v["baseUtcOffset"].integer));
        const supportsDaylightSavingTime = v["supportsDaylightSavingTime"].boolean;

        if (id.length == 0 || !baseUtcOffset)
            return ResultIf!TimeZoneInfo.error(1, "Invalid datetime transition");

        auto result = TimeZoneInfo(id, displayName, standardName, daylightName,
            baseUtcOffset, supportsDaylightSavingTime);

        auto jsRules = v["adjustmentRules"].array;
        foreach (ref jsRule; jsRules)
        {
            auto rule = toRule(jsRule);
            if (!rule)
                return ResultIf!TimeZoneInfo.error(1, "Invalid datetime transition rule");

           result.addRule(rule.value);
        }

        return ResultIf!TimeZoneInfo.ok(result);
    } catch (Exception) return ResultIf!TimeZoneInfo.error(1, "Invalid datetime transition");
}

unittest // toInt
{
    assert(toInt(0).value == 0);
    assert(toInt(1).value == 1);
    assert(toInt(int.min).value == int.min);
    assert(toInt(int.max).value == int.max);

    assert(!toInt(long.min));
    assert(!toInt(long.max));
}

unittest // toDeltaMinutes
{
    assert(toDeltaMinutes(0).value == dur!"minutes"(0));
    assert(toDeltaMinutes(1).value == dur!"minutes"(1));
    assert(toDeltaMinutes(-Tick.minutesPerDay).value == dur!"minutes"(-Tick.minutesPerDay));
    assert(toDeltaMinutes(Tick.minutesPerDay).value == dur!"minutes"(Tick.minutesPerDay));

    assert(!toDeltaMinutes(long.min));
    assert(!toDeltaMinutes(long.max));
}

unittest // toKind
{
    assert(toKind("unspecified").value == DateTimeZoneKind.unspecified);
    assert(toKind("local").value == DateTimeZoneKind.local);
    assert(toKind("utc").value == DateTimeZoneKind.utc);

    assert(!toKind("xyz"));
}

unittest // toDateTime
{
    assert(toDateTime("0001-01-01T00:00:00.0000?unspecified").value == DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(toDateTime("2006-12-31T00:00:00.0000?unspecified").value == DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified));
}

unittest // getDefaultTimeZoneInfosByJson
{
    static immutable string json = q"JSON
{
  "zones": [
    {
      "id": "Afghanistan Standard Time",
      "displayName": "(UTC\u002B04:30) Kabul",
      "standardName": "Afghanistan Standard Time",
      "daylightName": "Afghanistan Daylight Time",
      "baseUtcOffset": 270,
      "supportsDaylightSavingTime": false,
      "adjustmentRules": []
    },
    {
      "id": "Alaskan Standard Time",
      "displayName": "(UTC-09:00) Alaska",
      "standardName": "Alaskan Standard Time",
      "daylightName": "Alaskan Daylight Time",
      "baseUtcOffset": -540,
      "supportsDaylightSavingTime": true,
      "adjustmentRules": [
        {
          "dateBegin": "0001-01-01T00:00:00.0000?unspecified",
          "dateEnd": "2006-12-31T00:00:00.0000?unspecified",
          "baseUtcOffsetDelta": 0,
          "daylightDelta": 60,
          "standardDelta": 0,
          "daylightTransitionBegin": {
            "timeOfDay": "0001-01-01T02:00:00.0000?unspecified",
            "month": 4,
            "week": 1,
            "day": 1,
            "dayOfWeek": "sunday",
            "isFixedDateRule": false
          },
          "daylightTransitionEnd": {
            "timeOfDay": "0001-01-01T02:00:00.0000?unspecified",
            "month": 10,
            "week": 5,
            "day": 1,
            "dayOfWeek": "sunday",
            "isFixedDateRule": false
          },
          "noDaylightTransitions": true
        },
        {
          "dateBegin": "2007-01-01T00:00:00.0000?unspecified",
          "dateEnd": "9999-12-31T00:00:00.0000?unspecified",
          "baseUtcOffsetDelta": 0,
          "daylightDelta": 60,
          "standardDelta": 0,
          "daylightTransitionBegin": {
            "timeOfDay": "0001-01-01T02:00:00.0000?unspecified",
            "month": 3,
            "week": 2,
            "day": 1,
            "dayOfWeek": "sunday",
            "isFixedDateRule": false
          },
          "daylightTransitionEnd": {
            "timeOfDay": "0001-01-01T02:00:00.0000?unspecified",
            "month": 11,
            "week": 1,
            "day": 1,
            "dayOfWeek": "sunday",
            "isFixedDateRule": false
          },
          "noDaylightTransitions": true
        }
      ]
    }
  ]
}
JSON";

    auto r = getDefaultTimeZoneInfosByJson(json);
    assert(r.length == 2);

    assert(r[0].id == "Afghanistan Standard Time");
    assert(r[0].daylightName == "Afghanistan Daylight Time");
    assert(r[0].displayName == "(UTC\u002B04:30) Kabul");
    assert(r[0].standardName == "Afghanistan Standard Time");
    assert(r[0].baseUtcOffset.toMinutes() == 270);
    assert(r[0].supportsDaylightSavingTime == false);
    assert(r[0].adjustmentRules.length == 0);

    assert(r[1].id == "Alaskan Standard Time");
    assert(r[1].daylightName == "Alaskan Daylight Time");
    assert(r[1].displayName == "(UTC-09:00) Alaska");
    assert(r[1].standardName == "Alaskan Standard Time");
    assert(r[1].baseUtcOffset.toMinutes() == -540);
    assert(r[1].supportsDaylightSavingTime == true);
    assert(r[1].adjustmentRules.length == 2);
    assert(r[1].adjustmentRules[0].dateBegin == DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[0].dateEnd == DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[0].baseUtcOffsetDelta.toMinutes() == 0);
    assert(r[1].adjustmentRules[0].daylightDelta.toMinutes() == 60);
    assert(r[1].adjustmentRules[0].standardDelta.toMinutes() == 0);
    assert(r[1].adjustmentRules[0].daylightTransitionBegin.day == 1);
    assert(r[1].adjustmentRules[0].daylightTransitionBegin.dayOfWeek == DayOfWeek.sunday);
    assert(r[1].adjustmentRules[0].daylightTransitionBegin.isFixedDateRule == false);
    assert(r[1].adjustmentRules[0].daylightTransitionBegin.month == 4);
    assert(r[1].adjustmentRules[0].daylightTransitionBegin.timeOfDay == DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[0].daylightTransitionBegin.week == 1);
    assert(r[1].adjustmentRules[0].daylightTransitionEnd.day == 1);
    assert(r[1].adjustmentRules[0].daylightTransitionEnd.dayOfWeek == DayOfWeek.sunday);
    assert(r[1].adjustmentRules[0].daylightTransitionEnd.isFixedDateRule == false);
    assert(r[1].adjustmentRules[0].daylightTransitionEnd.month == 10);
    assert(r[1].adjustmentRules[0].daylightTransitionEnd.timeOfDay == DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[0].daylightTransitionEnd.week == 5);
    assert(r[1].adjustmentRules[0].noDaylightTransitions == true);
    assert(r[1].adjustmentRules[1].dateBegin == DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[1].dateEnd == DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[1].baseUtcOffsetDelta.toMinutes() == 0);
    assert(r[1].adjustmentRules[1].daylightDelta.toMinutes() == 60);
    assert(r[1].adjustmentRules[1].standardDelta.toMinutes() == 0);
    assert(r[1].adjustmentRules[1].daylightTransitionBegin.day == 1);
    assert(r[1].adjustmentRules[1].daylightTransitionBegin.dayOfWeek == DayOfWeek.sunday);
    assert(r[1].adjustmentRules[1].daylightTransitionBegin.isFixedDateRule == false);
    assert(r[1].adjustmentRules[1].daylightTransitionBegin.month == 3);
    assert(r[1].adjustmentRules[1].daylightTransitionBegin.timeOfDay == DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[1].daylightTransitionBegin.week == 2);
    assert(r[1].adjustmentRules[1].daylightTransitionEnd.day == 1);
    assert(r[1].adjustmentRules[1].daylightTransitionEnd.dayOfWeek == DayOfWeek.sunday);
    assert(r[1].adjustmentRules[1].daylightTransitionEnd.isFixedDateRule == false);
    assert(r[1].adjustmentRules[1].daylightTransitionEnd.month == 11);
    assert(r[1].adjustmentRules[1].daylightTransitionEnd.timeOfDay == DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified));
    assert(r[1].adjustmentRules[1].daylightTransitionEnd.week == 1);
    assert(r[1].adjustmentRules[0].noDaylightTransitions == true);
}
