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

module pham.dtm.time_zone_default;

import core.time : dur, Duration;

import pham.dtm.date : DayOfWeek, DateTime;
import pham.dtm.time_zone : AdjustmentRule, MapId, TimeZoneInfo, TimeZoneInfoMapList, TransitionTime;
import pham.dtm.tick : DateTimeZoneKind;

nothrow @safe:

TimeZoneInfoMapList getDefaultTimeZoneInfoMaps() pure
{
    auto zones = getDefaultTimeZoneInfos();
    return new TimeZoneInfoMapList(zones);
}

TimeZoneInfo[] getDefaultTimeZoneInfos() pure
{
    TimeZoneInfo[] result;
    result.reserve(141);
    TimeZoneInfo zone;

    zone = TimeZoneInfo("Afghanistan Standard Time", "(UTC+04:30) Kabul", "Afghanistan Standard Time", "Afghanistan Daylight Time", dur!"minutes"(270), false);
    result ~= zone;

    zone = TimeZoneInfo("Alaskan Standard Time", "(UTC-09:00) Alaska", "Alaskan Standard Time", "Alaskan Daylight Time", dur!"minutes"(-540), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Aleutian Standard Time", "(UTC-10:00) Aleutian Islands", "Aleutian Standard Time", "Aleutian Daylight Time", dur!"minutes"(-600), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Altai Standard Time", "(UTC+07:00) Barnaul, Gorno-Altaysk", "Altai Standard Time", "Altai Daylight Time", dur!"minutes"(420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Arab Standard Time", "(UTC+03:00) Kuwait, Riyadh", "Arab Standard Time", "Arab Daylight Time", dur!"minutes"(180), false);
    result ~= zone;

    zone = TimeZoneInfo("Arabian Standard Time", "(UTC+04:00) Abu Dhabi, Muscat", "Arabian Standard Time", "Arabian Daylight Time", dur!"minutes"(240), false);
    result ~= zone;

    zone = TimeZoneInfo("Arabic Standard Time", "(UTC+03:00) Baghdad", "Arabic Standard Time", "Arabic Daylight Time", dur!"minutes"(180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.monday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Argentina Standard Time", "(UTC-03:00) City of Buenos Aires", "Argentina Standard Time", "Argentina Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Astrakhan Standard Time", "(UTC+04:00) Astrakhan, Ulyanovsk", "Astrakhan Standard Time", "Astrakhan Daylight Time", dur!"minutes"(240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Atlantic Standard Time", "(UTC-04:00) Atlantic Time (Canada)", "Atlantic Standard Time", "Atlantic Daylight Time", dur!"minutes"(-240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("AUS Central Standard Time", "(UTC+09:30) Darwin", "AUS Central Standard Time", "AUS Central Daylight Time", dur!"minutes"(570), false);
    result ~= zone;

    zone = TimeZoneInfo("Aus Central W. Standard Time", "(UTC+08:45) Eucla", "Aus Central W. Standard Time", "Aus Central W. Daylight Time", dur!"minutes"(525), false);
    result ~= zone;

    zone = TimeZoneInfo("AUS Eastern Standard Time", "(UTC+10:00) Canberra, Melbourne, Sydney", "AUS Eastern Standard Time", "AUS Eastern Daylight Time", dur!"minutes"(600), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Azerbaijan Standard Time", "(UTC+04:00) Baku", "Azerbaijan Standard Time", "Azerbaijan Daylight Time", dur!"minutes"(240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 5, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Azores Standard Time", "(UTC-01:00) Azores", "Azores Standard Time", "Azores Daylight Time", dur!"minutes"(-60), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Bahia Standard Time", "(UTC-03:00) Salvador", "Bahia Standard Time", "Bahia Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 4, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Bangladesh Standard Time", "(UTC+06:00) Dhaka", "Bangladesh Standard Time", "Bangladesh Daylight Time", dur!"minutes"(360), true);
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 6, 3, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 12, 5, 1, DayOfWeek.thursday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Belarus Standard Time", "(UTC+03:00) Minsk", "Belarus Standard Time", "Belarus Daylight Time", dur!"minutes"(180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Bougainville Standard Time", "(UTC+11:00) Bougainville Island", "Bougainville Standard Time", "Bougainville Daylight Time", dur!"minutes"(660), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Canada Central Standard Time", "(UTC-06:00) Saskatchewan", "Canada Central Standard Time", "Canada Central Daylight Time", dur!"minutes"(-360), false);
    result ~= zone;

    zone = TimeZoneInfo("Cape Verde Standard Time", "(UTC-01:00) Cabo Verde Is.", "Cabo Verde Standard Time", "Cabo Verde Daylight Time", dur!"minutes"(-60), false);
    result ~= zone;

    zone = TimeZoneInfo("Caucasus Standard Time", "(UTC+04:00) Yerevan", "Caucasus Standard Time", "Caucasus Daylight Time", dur!"minutes"(240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Cen. Australia Standard Time", "(UTC+09:30) Adelaide", "Cen. Australia Standard Time", "Cen. Australia Daylight Time", dur!"minutes"(570), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Central America Standard Time", "(UTC-06:00) Central America", "Central America Standard Time", "Central America Daylight Time", dur!"minutes"(-360), false);
    result ~= zone;

    zone = TimeZoneInfo("Central Asia Standard Time", "(UTC+06:00) Astana", "Central Asia Standard Time", "Central Asia Daylight Time", dur!"minutes"(360), false);
    result ~= zone;

    zone = TimeZoneInfo("Central Brazilian Standard Time", "(UTC-04:00) Cuiaba", "Central Brazilian Standard Time", "Central Brazilian Daylight Time", dur!"minutes"(-240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Central Europe Standard Time", "(UTC+01:00) Belgrade, Bratislava, Budapest, Ljubljana, Prague", "Central Europe Standard Time", "Central Europe Daylight Time", dur!"minutes"(60), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Central European Standard Time", "(UTC+01:00) Sarajevo, Skopje, Warsaw, Zagreb", "Central European Standard Time", "Central European Daylight Time", dur!"minutes"(60), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Central Pacific Standard Time", "(UTC+11:00) Solomon Is., New Caledonia", "Central Pacific Standard Time", "Central Pacific Daylight Time", dur!"minutes"(660), false);
    result ~= zone;

    zone = TimeZoneInfo("Central Standard Time", "(UTC-06:00) Central Time (US & Canada)", "Central Standard Time", "Central Daylight Time", dur!"minutes"(-360), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Central Standard Time (Mexico)", "(UTC-06:00) Guadalajara, Mexico City, Monterrey", "Central Standard Time (Mexico)", "Central Daylight Time (Mexico)", dur!"minutes"(-360), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Chatham Islands Standard Time", "(UTC+12:45) Chatham Islands", "Chatham Islands Standard Time", "Chatham Islands Daylight Time", dur!"minutes"(765), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 45, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 45, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 45, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 45, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 45, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 45, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("China Standard Time", "(UTC+08:00) Beijing, Chongqing, Hong Kong, Urumqi", "China Standard Time", "China Daylight Time", dur!"minutes"(480), false);
    result ~= zone;

    zone = TimeZoneInfo("Cuba Standard Time", "(UTC-05:00) Havana", "Cuba Standard Time", "Cuba Daylight Time", dur!"minutes"(-300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2003, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2004, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Dateline Standard Time", "(UTC-12:00) International Date Line West", "Dateline Standard Time", "Dateline Daylight Time", dur!"minutes"(-720), false);
    result ~= zone;

    zone = TimeZoneInfo("E. Africa Standard Time", "(UTC+03:00) Nairobi", "E. Africa Standard Time", "E. Africa Daylight Time", dur!"minutes"(180), false);
    result ~= zone;

    zone = TimeZoneInfo("E. Australia Standard Time", "(UTC+10:00) Brisbane", "E. Australia Standard Time", "E. Australia Daylight Time", dur!"minutes"(600), false);
    result ~= zone;

    zone = TimeZoneInfo("E. Europe Standard Time", "(UTC+02:00) Chisinau", "E. Europe Standard Time", "E. Europe Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("E. South America Standard Time", "(UTC-03:00) Brasilia", "E. South America Standard Time", "E. South America Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 2, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Easter Island Standard Time", "(UTC-06:00) Easter Island", "Easter Island Standard Time", "Easter Island Daylight Time", dur!"minutes"(-360), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 8, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Eastern Standard Time", "(UTC-05:00) Eastern Time (US & Canada)", "Eastern Standard Time", "Eastern Daylight Time", dur!"minutes"(-300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Eastern Standard Time (Mexico)", "(UTC-05:00) Chetumal", "Eastern Standard Time (Mexico)", "Eastern Daylight Time (Mexico)", dur!"minutes"(-300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Egypt Standard Time", "(UTC+02:00) Cairo", "Egypt Standard Time", "Egypt Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 5, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 4, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 3, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 3, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.thursday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Ekaterinburg Standard Time", "(UTC+05:00) Ekaterinburg", "Russia TZ 4 Standard Time", "Russia TZ 4 Daylight Time", dur!"minutes"(300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Fiji Standard Time", "(UTC+12:00) Fiji", "Fiji Standard Time", "Fiji Daylight Time", dur!"minutes"(720), true);
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 4, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2021, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2022, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2022, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2023, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2023, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2024, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2025, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2025, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2026, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2026, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2027, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2027, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2028, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2028, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2029, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("FLE Standard Time", "(UTC+02:00) Helsinki, Kyiv, Riga, Sofia, Tallinn, Vilnius", "FLE Standard Time", "FLE Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Georgian Standard Time", "(UTC+04:00) Tbilisi", "Georgian Standard Time", "Georgian Daylight Time", dur!"minutes"(240), false);
    result ~= zone;

    zone = TimeZoneInfo("GMT Standard Time", "(UTC+00:00) Dublin, Edinburgh, Lisbon, London", "GMT Standard Time", "GMT Daylight Time", dur!"minutes"(0), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Greenland Standard Time", "(UTC-03:00) Greenland", "Greenland Standard Time", "Greenland Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 22, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Greenwich Standard Time", "(UTC+00:00) Monrovia, Reykjavik", "Greenwich Standard Time", "Greenwich Daylight Time", dur!"minutes"(0), false);
    result ~= zone;

    zone = TimeZoneInfo("GTB Standard Time", "(UTC+02:00) Athens, Bucharest", "GTB Standard Time", "GTB Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Haiti Standard Time", "(UTC-05:00) Haiti", "Haiti Standard Time", "Haiti Daylight Time", dur!"minutes"(-300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Hawaiian Standard Time", "(UTC-10:00) Hawaii", "Hawaiian Standard Time", "Hawaiian Daylight Time", dur!"minutes"(-600), false);
    result ~= zone;

    zone = TimeZoneInfo("India Standard Time", "(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi", "India Standard Time", "India Daylight Time", dur!"minutes"(330), false);
    result ~= zone;

    zone = TimeZoneInfo("Iran Standard Time", "(UTC+03:30) Tehran", "Iran Standard Time", "Iran Daylight Time", dur!"minutes"(210), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.monday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.wednesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.monday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.tuesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.wednesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.monday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.tuesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2021, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.tuesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2022, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2022, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.wednesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2023, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2023, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.friday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Israel Standard Time", "(UTC+02:00) Jerusalem", "Jerusalem Standard Time", "Jerusalem Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 4, 1, DayOfWeek.wednesday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 2, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 4, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2021, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2022, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2022, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2023, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Jordan Standard Time", "(UTC+02:00) Amman", "Jordan Standard Time", "Jordan Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 3, 1, DayOfWeek.friday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.friday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Kaliningrad Standard Time", "(UTC+02:00) Kaliningrad", "Russia TZ 1 Standard Time", "Russia TZ 1 Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Kamchatka Standard Time", "(UTC+12:00) Petropavlovsk-Kamchatsky - Old", "Kamchatka Standard Time", "Kamchatka Daylight Time", dur!"minutes"(720), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Korea Standard Time", "(UTC+09:00) Seoul", "Korea Standard Time", "Korea Daylight Time", dur!"minutes"(540), false);
    result ~= zone;

    zone = TimeZoneInfo("Libya Standard Time", "(UTC+02:00) Tripoli", "Libya Standard Time", "Libya Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Line Islands Standard Time", "(UTC+14:00) Kiritimati Island", "Line Islands Standard Time", "Line Islands Daylight Time", dur!"minutes"(840), false);
    result ~= zone;

    zone = TimeZoneInfo("Lord Howe Standard Time", "(UTC+10:30) Lord Howe Island", "Lord Howe Standard Time", "Lord Howe Daylight Time", dur!"minutes"(630), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Magadan Standard Time", "(UTC+11:00) Magadan", "Magadan Standard Time", "Magadan Daylight Time", dur!"minutes"(660), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(120), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Magallanes Standard Time", "(UTC-03:00) Punta Arenas", "Magallanes Standard Time", "Magallanes Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Marquesas Standard Time", "(UTC-09:30) Marquesas Islands", "Marquesas Standard Time", "Marquesas Daylight Time", dur!"minutes"(-570), false);
    result ~= zone;

    zone = TimeZoneInfo("Mauritius Standard Time", "(UTC+04:00) Port Louis", "Mauritius Standard Time", "Mauritius Daylight Time", dur!"minutes"(240), true);
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Mid-Atlantic Standard Time", "(UTC-02:00) Mid-Atlantic - Old", "Mid-Atlantic Standard Time", "Mid-Atlantic Daylight Time", dur!"minutes"(-120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Middle East Standard Time", "(UTC+02:00) Beirut", "Middle East Standard Time", "Middle East Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Montevideo Standard Time", "(UTC-03:00) Montevideo", "Montevideo Standard Time", "Montevideo Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Morocco Standard Time", "(UTC+01:00) Casablanca", "Morocco Standard Time", "Morocco Daylight Time", dur!"minutes"(0), true);
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 3, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 7, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 6, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2021, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2022, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2022, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2023, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2023, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2024, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2025, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2025, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2026, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2026, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2027, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2027, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2028, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2028, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 4, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2029, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 2, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Mountain Standard Time", "(UTC-07:00) Mountain Time (US & Canada)", "Mountain Standard Time", "Mountain Daylight Time", dur!"minutes"(-420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Mountain Standard Time (Mexico)", "(UTC-07:00) Chihuahua, La Paz, Mazatlan", "Mountain Standard Time (Mexico)", "Mountain Daylight Time (Mexico)", dur!"minutes"(-420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Myanmar Standard Time", "(UTC+06:30) Yangon (Rangoon)", "Myanmar Standard Time", "Myanmar Daylight Time", dur!"minutes"(390), false);
    result ~= zone;

    zone = TimeZoneInfo("N. Central Asia Standard Time", "(UTC+07:00) Novosibirsk", "Novosibirsk Standard Time", "Novosibirsk Daylight Time", dur!"minutes"(420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 7, 4, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Namibia Standard Time", "(UTC+02:00) Windhoek", "Namibia Standard Time", "Namibia Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Nepal Standard Time", "(UTC+05:45) Kathmandu", "Nepal Standard Time", "Nepal Daylight Time", dur!"minutes"(345), false);
    result ~= zone;

    zone = TimeZoneInfo("New Zealand Standard Time", "(UTC+12:00) Auckland, Wellington", "New Zealand Standard Time", "New Zealand Daylight Time", dur!"minutes"(720), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Newfoundland Standard Time", "(UTC-03:30) Newfoundland", "Newfoundland Standard Time", "Newfoundland Daylight Time", dur!"minutes"(-210), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 1, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Norfolk Standard Time", "(UTC+11:00) Norfolk Island", "Norfolk Standard Time", "Norfolk Daylight Time", dur!"minutes"(660), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("North Asia East Standard Time", "(UTC+08:00) Irkutsk", "Russia TZ 7 Standard Time", "Russia TZ 7 Daylight Time", dur!"minutes"(480), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("North Asia Standard Time", "(UTC+07:00) Krasnoyarsk", "Russia TZ 6 Standard Time", "Russia TZ 6 Daylight Time", dur!"minutes"(420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("North Korea Standard Time", "(UTC+09:00) Pyongyang", "North Korea Standard Time", "North Korea Daylight Time", dur!"minutes"(540), true);
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 30, 0, 0, DateTimeZoneKind.unspecified), 5, 1, 1, DayOfWeek.friday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Omsk Standard Time", "(UTC+06:00) Omsk", "Omsk Standard Time", "Omsk Daylight Time", dur!"minutes"(360), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Pacific SA Standard Time", "(UTC-04:00) Santiago", "Pacific SA Standard Time", "Pacific SA Daylight Time", dur!"minutes"(-240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 8, 2, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Pacific Standard Time", "(UTC-08:00) Pacific Time (US & Canada)", "Pacific Standard Time", "Pacific Daylight Time", dur!"minutes"(-480), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Pacific Standard Time (Mexico)", "(UTC-08:00) Baja California", "Pacific Standard Time (Mexico)", "Pacific Daylight Time (Mexico)", dur!"minutes"(-480), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Pakistan Standard Time", "(UTC+05:00) Islamabad, Karachi", "Pakistan Standard Time", "Pakistan Daylight Time", dur!"minutes"(300), true);
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 5, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.friday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 2, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Paraguay Standard Time", "(UTC-04:00) Asuncion", "Paraguay Standard Time", "Paraguay Daylight Time", dur!"minutes"(-240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 2, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 3, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Qyzylorda Standard Time", "(UTC+05:00) Qyzylorda", "Qyzylorda Standard Time", "Qyzylorda Daylight Time", dur!"minutes"(300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 3, 1, DayOfWeek.friday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Romance Standard Time", "(UTC+01:00) Brussels, Copenhagen, Madrid, Paris", "Romance Standard Time", "Romance Daylight Time", dur!"minutes"(60), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Russia Time Zone 10", "(UTC+11:00) Chokurdakh", "Russia TZ 10 Standard Time", "Russia TZ 10 Daylight Time", dur!"minutes"(660), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Russia Time Zone 11", "(UTC+12:00) Anadyr, Petropavlovsk-Kamchatsky", "Russia TZ 11 Standard Time", "Russia TZ 11 Daylight Time", dur!"minutes"(720), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Russia Time Zone 3", "(UTC+04:00) Izhevsk, Samara", "Russia TZ 3 Standard Time", "Russia TZ 3 Daylight Time", dur!"minutes"(240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Russian Standard Time", "(UTC+03:00) Moscow, St. Petersburg", "Russia TZ 2 Standard Time", "Russia TZ 2 Daylight Time", dur!"minutes"(180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("SA Eastern Standard Time", "(UTC-03:00) Cayenne, Fortaleza", "SA Eastern Standard Time", "SA Eastern Daylight Time", dur!"minutes"(-180), false);
    result ~= zone;

    zone = TimeZoneInfo("SA Pacific Standard Time", "(UTC-05:00) Bogota, Lima, Quito, Rio Branco", "SA Pacific Standard Time", "SA Pacific Daylight Time", dur!"minutes"(-300), false);
    result ~= zone;

    zone = TimeZoneInfo("SA Western Standard Time", "(UTC-04:00) Georgetown, La Paz, Manaus, San Juan", "SA Western Standard Time", "SA Western Daylight Time", dur!"minutes"(-240), false);
    result ~= zone;

    zone = TimeZoneInfo("Saint Pierre Standard Time", "(UTC-03:00) Saint Pierre and Miquelon", "Saint Pierre Standard Time", "Saint Pierre Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Sakhalin Standard Time", "(UTC+11:00) Sakhalin", "Sakhalin Standard Time", "Sakhalin Daylight Time", dur!"minutes"(660), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Samoa Standard Time", "(UTC+13:00) Samoa", "Samoa Standard Time", "Samoa Daylight Time", dur!"minutes"(780), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Sao Tome Standard Time", "(UTC+00:00) Sao Tome", "Sao Tome Standard Time", "Sao Tome Daylight Time", dur!"minutes"(0), true);
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Saratov Standard Time", "(UTC+04:00) Saratov", "Saratov Standard Time", "Saratov Daylight Time", dur!"minutes"(240), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("SE Asia Standard Time", "(UTC+07:00) Bangkok, Hanoi, Jakarta", "SE Asia Standard Time", "SE Asia Daylight Time", dur!"minutes"(420), false);
    result ~= zone;

    zone = TimeZoneInfo("Singapore Standard Time", "(UTC+08:00) Kuala Lumpur, Singapore", "Malay Peninsula Standard Time", "Malay Peninsula Daylight Time", dur!"minutes"(480), false);
    result ~= zone;

    zone = TimeZoneInfo("South Africa Standard Time", "(UTC+02:00) Harare, Pretoria", "South Africa Standard Time", "South Africa Daylight Time", dur!"minutes"(120), false);
    result ~= zone;

    zone = TimeZoneInfo("South Sudan Standard Time", "(UTC+02:00) Juba", "South Sudan Standard Time", "South Sudan Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2021, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 1, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Sri Lanka Standard Time", "(UTC+05:30) Sri Jayawardenepura", "Sri Lanka Standard Time", "Sri Lanka Daylight Time", dur!"minutes"(330), false);
    result ~= zone;

    zone = TimeZoneInfo("Sudan Standard Time", "(UTC+02:00) Khartoum", "Sudan Standard Time", "Sudan Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.tuesday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Syria Standard Time", "(UTC+02:00) Damascus", "Syria Standard Time", "Syria Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2004, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2005, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2005, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.thursday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Taipei Standard Time", "(UTC+08:00) Taipei", "Taipei Standard Time", "Taipei Daylight Time", dur!"minutes"(480), false);
    result ~= zone;

    zone = TimeZoneInfo("Tasmania Standard Time", "(UTC+10:00) Hobart", "Tasmania Standard Time", "Tasmania Daylight Time", dur!"minutes"(600), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Tocantins Standard Time", "(UTC-03:00) Araguaina", "Tocantins Standard Time", "Tocantins Daylight Time", dur!"minutes"(-180), true);
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 3, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.tuesday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 2, 3, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Tokyo Standard Time", "(UTC+09:00) Osaka, Sapporo, Tokyo", "Tokyo Standard Time", "Tokyo Daylight Time", dur!"minutes"(540), false);
    result ~= zone;

    zone = TimeZoneInfo("Tomsk Standard Time", "(UTC+07:00) Tomsk", "Tomsk Standard Time", "Tomsk Daylight Time", dur!"minutes"(420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 5, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Tonga Standard Time", "(UTC+13:00) Nuku'alofa", "Tonga Standard Time", "Tonga Daylight Time", dur!"minutes"(780), true);
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 3, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Transbaikal Standard Time", "(UTC+09:00) Chita", "Transbaikal Standard Time", "Transbaikal Daylight Time", dur!"minutes"(540), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(120), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Turkey Standard Time", "(UTC+03:00) Istanbul", "Turkey Standard Time", "Turkey Daylight Time", dur!"minutes"(180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 4, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Turks And Caicos Standard Time", "(UTC-05:00) Turks and Caicos", "Turks and Caicos Standard Time", "Turks and Caicos Daylight Time", dur!"minutes"(-300), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("Ulaanbaatar Standard Time", "(UTC+08:00) Ulaanbaatar", "Ulaanbaatar Standard Time", "Ulaanbaatar Daylight Time", dur!"minutes"(480), true);
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 4, 1, DayOfWeek.friday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("US Eastern Standard Time", "(UTC-05:00) Indiana (East)", "US Eastern Standard Time", "US Eastern Daylight Time", dur!"minutes"(-300), true);
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    result ~= zone;

    zone = TimeZoneInfo("US Mountain Standard Time", "(UTC-07:00) Arizona", "US Mountain Standard Time", "US Mountain Daylight Time", dur!"minutes"(-420), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC", "(UTC) Coordinated Universal Time", "Coordinated Universal Time", "Coordinated Universal Time", dur!"minutes"(0), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC-02", "(UTC-02:00) Coordinated Universal Time-02", "UTC-02", "UTC-02", dur!"minutes"(-120), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC-08", "(UTC-08:00) Coordinated Universal Time-08", "UTC-08", "UTC-08", dur!"minutes"(-480), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC-09", "(UTC-09:00) Coordinated Universal Time-09", "UTC-09", "UTC-09", dur!"minutes"(-540), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC-11", "(UTC-11:00) Coordinated Universal Time-11", "UTC-11", "UTC-11", dur!"minutes"(-660), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC+12", "(UTC+12:00) Coordinated Universal Time+12", "UTC+12", "UTC+12", dur!"minutes"(720), false);
    result ~= zone;

    zone = TimeZoneInfo("UTC+13", "(UTC+13:00) Coordinated Universal Time+13", "UTC+13", "UTC+13", dur!"minutes"(780), false);
    result ~= zone;

    zone = TimeZoneInfo("Venezuela Standard Time", "(UTC-04:00) Caracas", "Venezuela Standard Time", "Venezuela Daylight Time", dur!"minutes"(-240), true);
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 2, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-30), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 30, 0, 0, DateTimeZoneKind.unspecified), 5, 1, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Vladivostok Standard Time", "(UTC+10:00) Vladivostok", "Russia TZ 9 Standard Time", "Russia TZ 9 Daylight Time", dur!"minutes"(600), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Volgograd Standard Time", "(UTC+03:00) Volgograd", "Volgograd Standard Time", "Volgograd Daylight Time", dur!"minutes"(180), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(-60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.monday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("W. Australia Standard Time", "(UTC+08:00) Perth", "W. Australia Standard Time", "W. Australia Daylight Time", dur!"minutes"(480), true);
    zone.addRule(AdjustmentRule(DateTime(2006, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 12, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("W. Central Africa Standard Time", "(UTC+01:00) West Central Africa", "W. Central Africa Standard Time", "W. Central Africa Daylight Time", dur!"minutes"(60), false);
    result ~= zone;

    zone = TimeZoneInfo("W. Europe Standard Time", "(UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna", "W. Europe Standard Time", "W. Europe Daylight Time", dur!"minutes"(60), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("W. Mongolia Standard Time", "(UTC+07:00) Hovd", "W. Mongolia Standard Time", "W. Mongolia Daylight Time", dur!"minutes"(420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 4, 1, DayOfWeek.friday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("West Asia Standard Time", "(UTC+05:00) Ashgabat, Tashkent", "West Asia Standard Time", "West Asia Daylight Time", dur!"minutes"(300), false);
    result ~= zone;

    zone = TimeZoneInfo("West Bank Standard Time", "(UTC+02:00) Gaza, Hebron", "West Bank Gaza Standard Time", "West Bank Gaza Daylight Time", dur!"minutes"(120), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 9, 3, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 9, 5, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.thursday, false),
        TransitionTime(DateTime(1, 1, 1, 23, 59, 59, 999, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.thursday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.friday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.friday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2021, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2021, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2022, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2022, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2023, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2023, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2024, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2024, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2025, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2025, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2026, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2026, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 4, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2027, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2027, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2028, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2028, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2029, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2029, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 4, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2030, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(9999, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.saturday, false),
        TransitionTime(DateTime(1, 1, 1, 1, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.saturday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("West Pacific Standard Time", "(UTC+10:00) Guam, Port Moresby", "West Pacific Standard Time", "West Pacific Daylight Time", dur!"minutes"(600), false);
    result ~= zone;

    zone = TimeZoneInfo("Yakutsk Standard Time", "(UTC+09:00) Yakutsk", "Russia TZ 8 Standard Time", "Russia TZ 8 Daylight Time", dur!"minutes"(540), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 3, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 5, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.saturday, false),
        false));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(0), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 1, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.sunday, true),
        false));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        false));
    result ~= zone;

    zone = TimeZoneInfo("Yukon Standard Time", "(UTC-07:00) Yukon", "Yukon Standard Time", "Yukon Daylight Time", dur!"minutes"(-420), true);
    zone.addRule(AdjustmentRule(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2006, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 4, 1, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 10, 5, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2007, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2007, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2008, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2008, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2009, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2009, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2010, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2010, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2011, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2011, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2012, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2012, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2013, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2013, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2014, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2014, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2015, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2015, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2016, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2016, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2017, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2017, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2018, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2018, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2019, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2019, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 11, 1, 1, DayOfWeek.sunday, false),
        true));
    zone.addRule(AdjustmentRule(DateTime(2020, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), DateTime(2020, 12, 31, 0, 0, 0, 0, DateTimeZoneKind.unspecified),
        Duration.zero, dur!"minutes"(60), Duration.zero,
        TransitionTime(DateTime(1, 1, 1, 2, 0, 0, 0, DateTimeZoneKind.unspecified), 3, 2, 1, DayOfWeek.sunday, false),
        TransitionTime(DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeZoneKind.unspecified), 1, 1, 1, DayOfWeek.wednesday, false),
        false));
    result ~= zone;

    return result;
}
