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

module pham.var.var_coerce_pham_date_time;


// All implement after this point must be private
private:

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimeParser, DateTimePattern, tryParse;
import pham.dtm.dtm_tick : dateTimeSetting;
import pham.dtm.dtm_time : Time;
import pham.var.var_coerce;

// Support Variant.coerce Date to DateTime
bool doCoerceDateToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DateTime*)dstPtr = (*cast(Date*)srcPtr).toDateTime();
    return true;
}

// Support Variant.coerce DateTime to Date
bool doCoerceDateTimeToDate(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(Date*)dstPtr = (*cast(DateTime*)srcPtr).date;
    return true;
}

// Support Variant.coerce DateTime to Time
bool doCoerceDateTimeToTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(Time*)dstPtr = (*cast(DateTime*)srcPtr).time;
    return true;
}

// Support Variant.coerce Time to DateTime
bool doCoerceTimeToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
{
    *cast(DateTime*)dstPtr = (*cast(Time*)srcPtr).toDateTime();
    return true;
}

// Support Variant.coerce string to Date
bool doCoerceStringToDate(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
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

// Support Variant.coerce string to DateTime
bool doCoerceStringToDateTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
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

// Support Variant.coerce string to Time
bool doCoerceStringToTime(scope void* srcPtr, scope void* dstPtr) nothrow @trusted
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
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.register!(string, Date)(handler);

    handler.doCoerce = &doCoerceDateTimeToDate;
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.register!(DateTime, Date)(handler);
    ConvertHandler.register!(const(DateTime), Date)(handler);

    // DateTime
    handler.doCoerce = &doCoerceStringToDateTime;
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.register!(string, DateTime)(handler);

    handler.doCoerce = &doCoerceDateToDateTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.register!(Date, DateTime)(handler);
    ConvertHandler.register!(const(Date), DateTime)(handler);

    handler.doCoerce = &doCoerceTimeToDateTime;
    handler.flags = ConvertHandlerFlag.implicit;
    ConvertHandler.register!(Time, DateTime)(handler);
    ConvertHandler.register!(const(Time), DateTime)(handler);

    // Time
    handler.doCoerce = &doCoerceStringToTime;
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.register!(string, Time)(handler);

    handler.doCoerce = &doCoerceDateTimeToTime;
    handler.flags = ConvertHandlerFlag.none;
    ConvertHandler.register!(DateTime, Time)(handler);
    ConvertHandler.register!(const(DateTime), Time)(handler);
}

unittest // variant_coerce
{
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
