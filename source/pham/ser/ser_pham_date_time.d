/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.ser.ser_pham_date_time;

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimePattern, dateTimeParse = parse;
import pham.dtm.dtm_tick : TickData;
import pham.dtm.dtm_time : Time;
import pham.ser.ser_serialization : Deserializer, DSeserializer, DeserializerException, Serializable, Serializer,
    SerializerDataFormat, StaticBuffer;

@safe:

void deserialize(Deserializer deserializer, scope ref Date value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto isop = DateTimePattern.iso8601Date();
            auto text = deserializer.readScopeChars();
            value = dateTimeParse!(Date, DeserializerException)(text, isop);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readInt();
            value = Date(binary);
            return;
    }
}

void serialize(Serializer serializer, scope ref Date value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            StaticBuffer!(char, 50) buffer;
            serializer.write(value.toString(buffer, "%U")[]); // %U=utcSortableDateTimeZ
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.days);
            return;
    }
}

void deserialize(Deserializer deserializer, scope ref DateTime value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto isop = DateTimePattern.iso8601DateTime();
            auto text = deserializer.readScopeChars();
            value = dateTimeParse!(DateTime, DeserializerException)(text, isop);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readLong();
            value = DateTime(binary);
            return;
    }
}

void serialize(Serializer serializer, scope ref DateTime value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            StaticBuffer!(char, 50) buffer;
            serializer.write(value.toString(buffer, "%U")[]); // %U=utcSortableDateTimeZ
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.sticks);
            return;
    }
}

void deserialize(Deserializer deserializer, scope ref Time value, scope ref Serializable attribute)
{
    final switch (deserializer.dataFormat)
    {
        case SerializerDataFormat.text:
            auto isop = DateTimePattern.iso8601Time();
            auto text = deserializer.readScopeChars();
            value = dateTimeParse!(Time, DeserializerException)(text, isop);
            return;
        case SerializerDataFormat.binary:
            auto binary = deserializer.readLong();
            value = Time(binary);
            return;
    }
}

void serialize(Serializer serializer, scope ref Time value, scope ref Serializable attribute)
{
    final switch (serializer.dataFormat)
    {
        case SerializerDataFormat.text:
            StaticBuffer!(char, 50) buffer;
            serializer.write(value.toString(buffer, "%U")[]); // %U=utcSortableDateTimeZ
            return;
        case SerializerDataFormat.binary:
            serializer.write(value.sticks);
            return;
    }
}


version(unittest)
{
package(pham.ser):

    static struct UnitTestPhamDateTime
    {
        Date date1;
        DateTime dateTime1;
        Time time1;

        ref typeof(this) setValues() return
        {
            date1 = Date(1999, 1, 1);
            dateTime1 = DateTime(1999, 7, 6, 12, 30, 33);
            time1 = Time(12, 30, 33);
            return this;
        }
        
        void assertValues()
        {
            assert(date1 == Date(1999, 1, 1));
            assert(dateTime1 == DateTime(1999, 7, 6, 12, 30, 33), dateTime1.toString());
            assert(time1 == Time(12, 30, 33) || time1 == Time(13, 30, 33), time1.toString()); // Time(13, 30, 33) for US DTS
        }
    }
    
    //import pham.ser.ser_serialization : SerializerMemberList;
    //pragma(msg, SerializerMemberList!UnitTestPhamDateTime);
}


private:

shared static this() nothrow @safe
{
    DSeserializer.register!Date(&serializeDate, &deserializeDate);
    DSeserializer.register!DateTime(&serializeDateTime, &deserializeDateTime);
    DSeserializer.register!Time(&serializeTime, &deserializeTime);
}

void deserializeDate(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(Date*)value), attribute);
}

void serializeDate(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(Date*)value), attribute);
}

void deserializeDateTime(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(DateTime*)value), attribute);
}

void serializeDateTime(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(DateTime*)value), attribute);
}

void deserializeTime(Deserializer deserializer, scope void* value, scope ref Serializable attribute) @trusted
{
    deserialize(deserializer, *(cast(Time*)value), attribute);
}

void serializeTime(Serializer serializer, scope void* value, scope ref Serializable attribute) @trusted
{
    serialize(serializer, *(cast(Time*)value), attribute);
}
