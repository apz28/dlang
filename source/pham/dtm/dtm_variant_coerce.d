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

module pham.dtm.dtm_variant_coerce;


// All implement after this point must be private
private:

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimeParser, DateTimePattern, tryParse;
import pham.dtm.dtm_tick : dateTimeSetting;
import pham.dtm.dtm_time : Time;
import pham.utl.utl_variant_coerce;

// Support Variant.coerce
bool doCoerceDateToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow
{
    const s = *cast(Date*)srcPtr;
    *cast(DateTime*)dstPtr = s.toDateTime();
    return true;
}

// Support Variant.coerce
bool doCoerceDateTimeToDate(scope void* srcPtr, scope void* dstPtr) nothrow
{
    const s = *cast(DateTime*)srcPtr;
    *cast(Date*)dstPtr = s.date;
    return true;
}

// Support Variant.coerce
bool doCoerceDateTimeToTime(scope void* srcPtr, scope void* dstPtr) nothrow
{
    const s = *cast(DateTime*)srcPtr;
    *cast(Time*)dstPtr = s.time;
    return true;
}

// Support Variant.coerce
bool doCoerceTimeToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow
{
    const s = *cast(Time*)srcPtr;
    *cast(DateTime*)dstPtr = s.toDateTime();
    return true;
}

// Support Variant.coerce
bool doCoerceStringToDate(scope void* srcPtr, scope void* dstPtr) nothrow
{
    Date d;
    auto s = *cast(string*)srcPtr;
    auto pattern = DateTimePattern.fromSetting(dateTimeSetting, dateTimeSetting.shortFormat.date);
    if (tryParse!Date(s, pattern, d) == DateTimeParser.noError)
    {
        *cast(Date*)dstPtr = d;
        return true;
    }
    else
        return false;
}

// Support Variant.coerce
bool doCoerceStringToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow
{
    DateTime dt;
    auto s = *cast(string*)srcPtr;
    auto pattern = DateTimePattern.fromSetting(dateTimeSetting, dateTimeSetting.shortFormat.dateTime);
    if (tryParse!DateTime(s, pattern, dt) == DateTimeParser.noError)
    {
        *cast(DateTime*)dstPtr = dt;
        return true;
    }
    else
        return false;
}

// Support Variant.coerce
bool doCoerceStringToTime(scope void* srcPtr, scope void* dstPtr) nothrow
{
    Time t;
    auto s = *cast(string*)srcPtr;
    auto pattern = DateTimePattern.fromSetting(dateTimeSetting, dateTimeSetting.shortFormat.time);
    if (tryParse!Time(s, pattern, t) == DateTimeParser.noError)
    {
        *cast(Time*)dstPtr = t;
        return true;
    }
    else
        return false;
}

shared static this() nothrow @safe
{
    // Support Variant.coerce
    ConvertHandler handler;
    handler.doCast = null;

    // Date
    handler.doCoerce = &doCoerceStringToDate;
    ConvertHandler.add!(string, Date)(handler);

    handler.doCoerce = &doCoerceDateTimeToDate;
    ConvertHandler.add!(DateTime, Date)(handler);

    // DateTime
    handler.doCoerce = &doCoerceStringToDateTime;
    ConvertHandler.add!(string, DateTime)(handler);

    handler.doCoerce = &doCoerceDateToDateTime;
    ConvertHandler.add!(Date, DateTime)(handler);

    handler.doCoerce = &doCoerceTimeToDateTime;
    ConvertHandler.add!(Time, DateTime)(handler);

    // Time
    handler.doCoerce = &doCoerceStringToTime;
    ConvertHandler.add!(string, Time)(handler);

    handler.doCoerce = &doCoerceDateTimeToTime;
    ConvertHandler.add!(DateTime, Time)(handler);
}

unittest
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.dtm.variant_coerce");

    Date d = Date(2000, 1, 1);
    Time t = Time(1, 0, 0, 0);
    DateTime dt = DateTime(d, t);

    Date toD;
    DateTime toDT;
    Time toT;

    ConvertHandler handler, invHandler;
    bool f;

    // Date vs DateTime
    f = ConvertHandler.find!(Date, DateTime)(handler);
    assert(f);
    assert(handler.doCoerce !is null);
    f = ConvertHandler.find!(DateTime, Date)(invHandler);
    assert(f);
    assert(invHandler.doCoerce !is null);
    f = handler.doCoerce(&d, &toDT);
    assert(f, Date.stringof ~ " to " ~ DateTime.stringof);
    assert(toDT == DateTime(d, Time.min));
    f = invHandler.doCoerce(&dt, &toD);
    assert(f, DateTime.stringof ~ " to " ~ Date.stringof);
    assert(toD == d);


    // Time vs DateTime
    f = ConvertHandler.find!(Time, DateTime)(handler);
    assert(f);
    assert(handler.doCoerce !is null);
    f = ConvertHandler.find!(DateTime, Time)(invHandler);
    assert(f);
    assert(invHandler.doCoerce !is null);
    f = handler.doCoerce(&t, &toDT);
    assert(f, Time.stringof ~ " to " ~ DateTime.stringof);
    assert(toDT == DateTime(Date.min, t));
    f = invHandler.doCoerce(&dt, &toT);
    assert(f, DateTime.stringof ~ " to " ~ Time.stringof);
    assert(toT == t);

    // Not convertable
    f = ConvertHandler.find!(Time, Date)(handler);
    assert(!f);
    f = ConvertHandler.find!(Date, Time)(handler);
    assert(!f);
}
