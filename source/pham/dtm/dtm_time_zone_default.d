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

module pham.dtm.dtm_time_zone_default;

version = dtm_time_zone_default_code;
import pham.dtm.dtm_time_zone_map : TimeZoneInfoMapList;

nothrow @safe:

__gshared static string defaultTimeZoneDataFileName;

TimeZoneInfoMapList getDefaultTimeZoneInfoMaps() @trusted
{
    // Special try construct for grep
    try {
        version (dtm_time_zone_default_code)
        {
            import pham.dtm.dtm_time_zone_default_code;

            auto zones = getDefaultTimeZoneInfosByCode();
            return new TimeZoneInfoMapList(zones);
        }
        else
        {
            import std.file : readText;

            import pham.dtm.dtm_time_zone_default_json : getDefaultTimeZoneInfosByJson;
            import pham.dtm.dtm_time_zone_default_tzdata : getDefaultTimeZoneInfosByTZData, sameLast;

            if (sameLast(defaultTimeZoneDataFileName, ".json"))
            {
                auto json = readText(defaultTimeZoneDataFileName);
                auto zones = getDefaultTimeZoneInfosByJson(json);
                return new TimeZoneInfoMapList(zones);
            }
            else if (sameLast(defaultTimeZoneDataFileName, "tzdata")
                     || sameLast(defaultTimeZoneDataFileName, ".tzdata"))
            {
                auto tzdata = readText(defaultTimeZoneDataFileName);
                auto zones = getDefaultTimeZoneInfosByTZData(tzdata);
                return new TimeZoneInfoMapList(zones);
            }
            else
                return new TimeZoneInfoMapList(null);
        }
    } catch (Exception) return new TimeZoneInfoMapList(null);
}
