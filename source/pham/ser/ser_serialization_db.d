/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.ser.ser_serialization_db;

import std.conv : to;
import std.traits : isDynamicArray, isFloatingPoint, isIntegral;

debug(pham_ser_ser_serialization_db) import std.stdio : writeln;
import pham.db.db_database : DbColumnList,
    columnNameString, parameterNameString, parameterConditionString, parameterUpdateString;
public import pham.db.db_database : DbConnection, DbCommand, DbParameter, DbParameterList, DbReader;
import pham.db.db_type : DbType;
public import pham.db.db_type : DbRecordsAffected;
import pham.db.db_value : DbRowValue, DbValue;
import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimePattern;
import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
public import pham.utl.utl_array : Appender;
import pham.var.var_coerce;
import pham.var.var_coerce_dec_decimal;
import pham.var.var_coerce_pham_date_time;
public import pham.var.var_variant : Variant;
import pham.ser.ser_serialization;
import pham.ser.ser_serialization_json; // Use for supporting hierachy - aggregated member

enum DbSerializerCommandQuery : ubyte
{
    insert,
    update,
}

enum DbSubSerializerKind : ubyte
{
    none,
    aggregate,
    array,
}

alias DbDeserializerConstructSQL = bool delegate(DbDeserializer serializer, scope const(Serializable)[] columns,
    ref Appender!string commandText, DbParameterList conditionParameters,
    scope ref Serializable attribute) @safe;

alias DbDeserializerSelectSQL = DbReader delegate(DbDeserializer serializer,
    ref Appender!string commandText, DbParameterList conditionParameters,
    scope ref Serializable attribute) @safe;

class DbDeserializer : Deserializer
{
@safe:

public:
    this(DbReader* reader) nothrow
    {
        this.reader = reader;
        this.columns = reader.columns;
    }

    this(DbConnection connection) nothrow
    {
        this.connection = connection;
    }

    // Aggregate (class, struct)
    final V select(V)(Variant[string] conditionParameters)
    if (isSerializerAggregateType!V)
    {
        auto parameters = connection.database.createParameterList();
        foreach (k, v; conditionParameters)
            parameters.add(k, DbType.unknown, v);
        return select!V(parameters);
    }

    final V select(V)(DbParameterList conditionParameters)
    if (isSerializerAggregateType!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable(V.stringof);
        return selectWith!V(conditionParameters, attribute);
    }

    final V selectWith(V)(DbParameterList conditionParameters, Serializable attribute) @trusted // this.reader = &selectReader
    if (isSerializerAggregateType!V)
    in
    {
        assert(attribute.dbName.length != 0);
    }
    do
    {
        const deserializerMembers = getDeserializerMembers!V();
        if (!constructSQL(deserializerMembers, conditionParameters, attribute))
            return V.init;

        auto selectReader = selectSQL(conditionParameters, attribute);
        if (selectReader.empty)
            return V.init;

        this.reader = &selectReader;
        this.columns = selectReader.columns;
        scope (exit)
        {
            this.columns = null;
            this.reader = null;
        }

        V v;
        begin(attribute);
        deserialize(v, attribute);
        end(attribute);
        return v;
    }

public:
    override DbDeserializer begin(scope ref Serializable attribute)
    {
        subKind = DbSubSerializerKind.none;
        subDeserializer = null;
        currentCol = 0;
        currentRow = readRowReader();
        return cast(DbDeserializer)super.begin(attribute);
    }

    override DbDeserializer end(scope ref Serializable attribute)
    {
        subKind = DbSubSerializerKind.none;
        subDeserializer = null;
        currentCol = currentRow = 0;
        return cast(DbDeserializer)super.end(attribute);
    }

    final override ptrdiff_t aggregateBegin(string typeName, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(currentCol=", currentCol, ", name=", attribute.name, ", memberDepth=", memberDepth, ")");

        if (subDeserializer is null)
        {
            const needSub = memberDepth == 1;
            super.aggregateBegin(typeName, attribute);
            if (needSub)
            {
                auto json = readChars(attribute);
                if (json.length == 0)
                    return 0;

                subKind = DbSubSerializerKind.aggregate;
                subDeserializer = new JsonDeserializer(json);
                subDeserializer.begin(attribute);
                return subDeserializer.aggregateBegin(typeName, attribute);
            }
            else
            {
                currentCol = 0;
                return currentRow;
            }
        }
        else
            return subDeserializer.aggregateBegin(typeName, attribute);
    }

    final override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(currentCol=", currentCol, ", name=", attribute.name, ", memberDepth=", memberDepth, ")");

        const isSub = subDeserializer !is null;

        if (!isSub || (memberDepth == 2 && subKind == DbSubSerializerKind.aggregate))
            super.aggregateEnd(typeName, length, attribute);

        if (isSub)
        {
            subDeserializer.aggregateEnd(typeName, length, attribute);
            if (memberDepth == 1 && subKind == DbSubSerializerKind.aggregate)
            {
                subDeserializer.end(attribute);
                subDeserializer = null;
                subKind = DbSubSerializerKind.none;
            }
        }
    }

    final override ptrdiff_t arrayBegin(string elemTypeName, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(currentCol=", currentCol, ", name=", attribute.name, ", arrayDepth=", arrayDepth, ")");

        if (subDeserializer is null)
        {
            const needSub = arrayDepth == (rootKind == RootKind.array ? 1 : 0);
            const sa = super.arrayBegin(elemTypeName, attribute);
            if (needSub)
            {
                auto json = readChars(attribute);
                if (json.length == 0)
                    return 0;

                subKind = DbSubSerializerKind.array;
                subDeserializer = new JsonDeserializer(json);
                subDeserializer.begin(attribute);
                return subDeserializer.arrayBegin(elemTypeName, attribute);
            }
            return sa;
        }
        else
            return subDeserializer.arrayBegin(elemTypeName, attribute);
    }

    final override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(currentCol=", currentCol, ", name=", attribute.name, ", arrayDepth=", arrayDepth, ")");

        const isSub = subDeserializer !is null;

        if (!isSub || (arrayDepth == (rootKind == RootKind.array ? 2 : 1) && subKind == DbSubSerializerKind.array))
            super.arrayEnd(elemTypeName, length, attribute);

        if (isSub)
        {
            subDeserializer.arrayEnd(elemTypeName, length, attribute);
            if (arrayDepth == (rootKind == RootKind.array ? 1 : 0) && subKind == DbSubSerializerKind.array)
            {
                subDeserializer.end(attribute);
                subDeserializer = null;
                subKind = DbSubSerializerKind.none;
            }
        }
    }

    final override Null readNull(scope ref Serializable attribute)
    {
        if (subDeserializer is null)
        {
            const i = popFront();
            assert(reader.isNull(i));
            return null;
        }
        else
            return subDeserializer.readNull(attribute);
    }

    final override bool readBool(scope ref Serializable attribute)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!bool()
            : subDeserializer.readBool(attribute);
    }

    final override char readChar(scope ref Serializable attribute)
    {
        const s = readChars(attribute);
        assert(s.length == 1);
        return s.length ? s[0] : '\0';
    }

    final override Date readDate(scope ref Serializable attribute)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!Date()
            : subDeserializer.readDate(attribute);
    }

    final override DateTime readDateTime(scope ref Serializable attribute)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!DateTime()
            : subDeserializer.readDateTime(attribute);
    }

    final override Time readTime(scope ref Serializable attribute)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!Time()
            : subDeserializer.readTime(attribute);
    }

    final override byte readByte(scope ref Serializable attribute)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!byte()
            : subDeserializer.readByte(attribute);
    }

    final override short readShort(scope ref Serializable attribute)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!short()
            : subDeserializer.readShort(attribute);
    }

    final override int readInt(scope ref Serializable attribute, const(DataKind) kind = DataKind.integral)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!int()
            : subDeserializer.readInt(attribute, kind);
    }

    final override long readLong(scope ref Serializable attribute, const(DataKind) kind = DataKind.integral)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!long()
            : subDeserializer.readLong(attribute, kind);
    }

    final override float readFloat(scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!float()
            : subDeserializer.readFloat(attribute, kind);
    }

    final override double readDouble(scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        return subDeserializer is null
            ? reader.getValue(popFront()).coerce!double()
            : subDeserializer.readDouble(attribute, kind);
    }

    final override string readChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        if (subDeserializer is null)
        {
            const i = popFront();
            debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(i=", i, ", name=", attribute.name, ")");
            return reader.isNull(i)
                ? null
                : reader.getValue(i).coerce!string();
        }
        else
            return subDeserializer.readChars(attribute, kind);
    }

    final override wstring readWChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto chars = readChars(attribute, kind);
        return chars.length != 0 ? chars.to!wstring : null;
    }

    final override dstring readDChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        auto chars = readChars(attribute, kind);
        return chars.length != 0 ? chars.to!dstring : null;
    }

    final override const(char)[] readScopeChars(scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        return subDeserializer is null
            ? readChars(attribute, kind)
            : subDeserializer.readScopeChars(attribute, kind);
    }

    final override ubyte[] readBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        if (subDeserializer is null)
        {
            const i = popFront();
            debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(i=", i, ", name=", attribute.name, ")");
            return reader.isNull(i)
                ? null
                : reader.getValue(i).coerce!(ubyte[])();
        }
        else
            return subDeserializer.readBytes(attribute, kind);
    }

    final override const(ubyte)[] readScopeBytes(scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        return subDeserializer is null
            ? readBytes(attribute, kind)
            : subDeserializer.readScopeBytes(attribute, kind);
    }

    final override string readKey(size_t i)
    {
        return subDeserializer is null
            ? (columns !is null ? columns[currentCol].name : null)
            : subDeserializer.readKey(i);
    }

public:
    final bool constructSQL(scope const(Serializable)[] columns, DbParameterList conditionParameters, scope ref Serializable attribute)
    {
        commandText.clear();
        commandText.capacity = 1_000;
        if (onConstructSQL !is null)
            return onConstructSQL(this, columns, commandText, conditionParameters, attribute);

        commandText.put("select ");
        if (columns.length)
        {
            foreach (i, column; columns)
            {
                if (i)
                    commandText.put(',');
                commandText.put(column.dbName);
            }
        }
        else
            commandText.put('*');
        commandText.put(" from ");
        commandText.put(attribute.dbName);
        if (conditionParameters && conditionParameters.length)
        {
            commandText.put(" where ");
            parameterConditionString(commandText, conditionParameters, true);
        }

        return true;
    }

    final DbReader selectSQL(DbParameterList conditionParameters, scope ref Serializable attribute)
    {
        return onSelectSQL !is null
            ? onSelectSQL(this, commandText, conditionParameters, attribute)
            : connection.executeReader(commandText[], conditionParameters);
    }

    final override bool hasAggregateEle(size_t i, ptrdiff_t len)
    {
        return subDeserializer is null
            ? (len > 0 && len > i && currentRow != 0)
            : subDeserializer.hasAggregateEle(i, len);
    }

    final override bool hasArrayEle(size_t i, ptrdiff_t len)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(i=", i, ", len=", len,
            ", arrayDepth=", arrayDepth, ", currentRow=", currentRow, ")");

        if (subDeserializer is null)
        {
            if (i != 0 && currentRow != 0)
            {
                currentCol = 0;
                currentRow = readRowReader();
            }

            return currentRow != 0;
        }
        else
            return subDeserializer.hasArrayEle(i, len);
    }

    pragma(inline, true)
    final size_t popFront() nothrow
    {
        return currentCol++;
    }

    final size_t readRowReader()
    {
        return reader.read() ? reader.colCount : 0u;
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    Appender!string commandText;
    DbConnection connection;
    size_t currentCol, currentRow;
    DbColumnList columns;
    DbReader* reader;
    DbDeserializerConstructSQL onConstructSQL;
    DbDeserializerSelectSQL onSelectSQL;
    JsonDeserializer subDeserializer;
    DbSubSerializerKind subKind;
}

alias DbSerializerConstructSQL = bool delegate(DbSerializer serializer,
    DbSerializerCommandQuery commandQuery, ref Appender!string commandText, DbParameterList commandParameters,
    scope ref Serializable attribute) @safe;

alias DbSerializerExecuteSQL = DbRecordsAffected delegate(DbSerializer serializer,
    DbSerializerCommandQuery commandQuery, ref Appender!string commandText, DbParameterList commandParameters,
    scope ref Serializable attribute) @safe;

class DbSerializer : Serializer
{
@safe:

public:
    this(DbConnection connection) nothrow
    {
        this.connection = connection;
    }

    // Aggregate (class, struct)
    final DbRecordsAffected insert(V)(auto ref V v)
    if (isSerializerAggregateType!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable(V.stringof);
        return insertWith!V(v, attribute);
    }

    final DbRecordsAffected insertWith(V)(auto ref V v, Serializable attribute)
    if (isSerializerAggregateType!V)
    in
    {
        assert(attribute.dbName.length != 0);
    }
    do
    {
        begin(attribute);
        serialize(v, attribute);
        end(attribute);
        const result = constructSQL(DbSerializerCommandQuery.insert, attribute)
            ? executeSQL(DbSerializerCommandQuery.insert, attribute)
            : DbRecordsAffected.init;
        commandParameters.clear();
        commandText.clear();
        return result;
    }

    // Aggregate (class, struct)
    final DbRecordsAffected update(V)(auto ref V v)
    if (isSerializerAggregateType!V)
    {
        static if (hasUDA!(V, Serializable))
            Serializable attribute = getUDA!(V, Serializable);
        else
            Serializable attribute = Serializable(V.stringof);
        return updateWith!V(v, attribute);
    }

    final DbRecordsAffected updateWith(V)(auto ref V v, Serializable attribute)
    if (isSerializerAggregateType!V)
    in
    {
        assert(attribute.dbName.length != 0);
    }
    do
    {
        begin(attribute);
        serialize(v, attribute);
        end(attribute);
        const result = constructSQL(DbSerializerCommandQuery.update, attribute)
            ? executeSQL(DbSerializerCommandQuery.update, attribute)
            : DbRecordsAffected.init;
        commandParameters.clear();
        commandText.clear();
        return result;
    }

public:
    override DbSerializer begin(scope ref Serializable attribute)
    {
        parameter = null;
        subKind = DbSubSerializerKind.none;
        subSerializer = null;
        commandTextSize = attribute.dbName.length + 10; // update ...(field, field) values(:field, :field);
        if (commandParameters is null)
            commandParameters = connection.database.createParameterList();
        else
            commandParameters.clear();
        return cast(DbSerializer)super.begin(attribute);
    }

    override DbSerializer end(scope ref Serializable attribute)
    {
        parameter = null;
        subKind = DbSubSerializerKind.none;
        subSerializer = null;
        return cast(DbSerializer)super.end(attribute);
    }

    final override void aggregateBegin(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(name=", attribute.name, ", memberDepth=", memberDepth, ")");

        if (subSerializer is null)
        {
            const needSub = memberDepth == 1;
            super.aggregateBegin(typeName, length, attribute);
            if (needSub)
            {
                subKind = DbSubSerializerKind.aggregate;
                subSerializer = new JsonSerializer();
                subSerializer.begin(attribute);
                subSerializer.aggregateBegin(typeName, length, attribute);
            }
        }
        else
            subSerializer.aggregateBegin(typeName, length, attribute);
    }

    final override void aggregateEnd(string typeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(name=", attribute.name, ", memberDepth=", memberDepth, ")");

        const isSub = subSerializer !is null;

        if (!isSub || (memberDepth == 2 && subKind == DbSubSerializerKind.aggregate))
            super.aggregateEnd(typeName, length, attribute);

        if (isSub)
        {
            subSerializer.aggregateEnd(typeName, length, attribute);
            if (memberDepth == 1 && subKind == DbSubSerializerKind.aggregate)
            {
                subSerializer.end(attribute);
                scope (exit)
                {
                    subSerializer = null;
                    subKind = DbSubSerializerKind.none;
                }

                auto json = subSerializer.buffer[];
                debug(pham_ser_ser_serialization_db) debug writeln("\t", "json=", json);
                touchParameter(DbType.json, attribute).variant = Variant(json.idup);
            }
        }
    }

    final override Serializer aggregateItem(ptrdiff_t index, scope ref Serializable attribute)
    in
    {
        assert(attribute.name.length != 0);
    }
    do
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(name=", attribute.name, ", memberDepth=", memberDepth, ", index=", index, ")");

        return subSerializer is null
            ? super.aggregateItem(index, attribute)
            : subSerializer.aggregateItem(index, attribute);
    }

    final override void arrayBegin(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(name=", attribute.name, ", arrayDepth=", arrayDepth, ")");

        if (subSerializer is null)
        {
            const needSub = arrayDepth == (rootKind == RootKind.array ? 1 : 0);
            super.arrayBegin(elemTypeName, length, attribute);
            if (needSub)
            {
                subKind = DbSubSerializerKind.array;
                subSerializer = new JsonSerializer();
                subSerializer.begin(attribute);
                subSerializer.arrayBegin(elemTypeName, length, attribute);
            }
        }
        else
            subSerializer.arrayBegin(elemTypeName, length, attribute);
    }

    final override void arrayEnd(string elemTypeName, ptrdiff_t length, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(name=", attribute.name, ", arrayDepth=", arrayDepth, ")");

        const isSub = subSerializer !is null;

        if (!isSub || (arrayDepth == (rootKind == RootKind.array ? 2 : 1) && subKind == DbSubSerializerKind.array))
            super.arrayEnd(elemTypeName, length, attribute);

        if (isSub)
        {
            subSerializer.arrayEnd(elemTypeName, length, attribute);
            if (arrayDepth == (rootKind == RootKind.array ? 1 : 0) && subKind == DbSubSerializerKind.array)
            {
                subSerializer.end(attribute);
                scope (exit)
                {
                    subSerializer = null;
                    subKind = DbSubSerializerKind.none;
                }

                auto json = subSerializer.buffer[];
                debug(pham_ser_ser_serialization_db) debug writeln("\t", "json=", json);
                touchParameter(DbType.json, attribute).variant = Variant(json.idup);
            }
        }
    }

    final override Serializer arrayItem(ptrdiff_t index, scope ref Serializable attribute)
    {
        debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(name=", attribute.name, ", arrayDepth=", arrayDepth, ", index=", index, ")");

        return subSerializer is null
            ? super.arrayItem(index, attribute)
            : subSerializer.arrayItem(index, attribute);
    }

    final override void write(Null, scope ref Serializable attribute)
    {
        if (subSerializer is null)
            touchParameter(DbType.unknown, attribute).variant = Variant(null);
        else
            subSerializer.write(null, attribute);
    }

    final override void writeBool(bool v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
            touchParameter(DbType.boolean, attribute).variant = Variant(v);
        else
            subSerializer.writeBool(v, attribute);
    }

    final override void writeChar(char v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
        {
            auto v2 = v.to!string;
            write(v2, attribute);
        }
        else
            subSerializer.writeChar(v, attribute);
    }

    final override void write(scope const(Date) v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
            touchParameter(DbType.date, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute);
    }

    final override void write(scope const(DateTime) v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
        {
            const type = v.kind == DateTimeZoneKind.utc ? DbType.timeTZ : DbType.time;
            touchParameter(type, attribute).variant = Variant(v);
        }
        else
            subSerializer.write(v, attribute);
    }

    final override void write(scope const(Time) v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
        {
            const type = v.kind == DateTimeZoneKind.utc ? DbType.timeTZ : DbType.time;
            touchParameter(type, attribute).variant = Variant(v);
        }
        else
            subSerializer.write(v, attribute);
    }

    final override void write(byte v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
            touchParameter(DbType.int8, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute);
    }

    final override void write(short v, scope ref Serializable attribute)
    {
        if (subSerializer is null)
            touchParameter(DbType.int16, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute);
    }

    final override void write(int v, scope ref Serializable attribute, const(DataKind) kind = DataKind.integral)
    {
        if (subSerializer is null)
            touchParameter(DbType.int32, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(long v, scope ref Serializable attribute, const(DataKind) kind = DataKind.integral)
    {
        if (subSerializer is null)
            touchParameter(DbType.int64, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(float v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        if (subSerializer is null)
            touchParameter(DbType.float32, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(double v, scope ref Serializable attribute, const(DataKind) kind = DataKind.decimal)
    {
        if (subSerializer is null)
            touchParameter(DbType.float64, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(scope const(char)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        if (subSerializer is null)
            touchParameter(DbType.stringVary, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(scope const(wchar)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        if (subSerializer is null)
        {
            auto v2 = v.to!string;
            write(v2, attribute, kind);
        }
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(scope const(dchar)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.character)
    {
        if (subSerializer is null)
        {
            auto v2 = v.to!string;
            write(v2, attribute, kind);
        }
        else
            subSerializer.write(v, attribute, kind);
    }

    final override void write(scope const(ubyte)[] v, scope ref Serializable attribute, const(DataKind) kind = DataKind.binary)
    {
        if (subSerializer is null)
            touchParameter(DbType.binaryVary, attribute).variant = Variant(v);
        else
            subSerializer.write(v, attribute, kind);
    }

    final override Serializer writeKey(scope ref Serializable attribute)
    {
        if (subSerializer is null)
        {
            parameter = null;
            touchParameter(DbType.unknown, attribute);
            return this;
        }
        else
            return subSerializer.writeKey(attribute);
    }

    final override Serializer writeKeyId(scope ref Serializable attribute)
    {
        if (subSerializer is null)
            return writeKey(attribute);
        else
            return subSerializer.writeKeyId(attribute);
    }

public:
    final bool constructSQL(DbSerializerCommandQuery commandQuery, scope ref Serializable attribute)
    {
        commandText.clear();
        commandText.capacity = commandTextSize;
        if (onConstructSQL !is null)
            return onConstructSQL(this, commandQuery, commandText, commandParameters, attribute);

        return commandQuery == DbSerializerCommandQuery.update
            ? constructUpdateSQL(attribute)
            : constructInsertSQL(attribute);
    }

    final bool constructInsertSQL(scope ref Serializable attribute)
    {
        commandText.put("insert into ")
            .put(attribute.dbName)
            .put('(')
            .columnNameString(commandParameters)
            .put(") values(")
            .parameterNameString(commandParameters)
            .put(')');
        return true;
    }

    final bool constructUpdateSQL(scope ref Serializable attribute)
    {
        commandText.put("update ")
            .put(attribute.dbName)
            .put(" set ")
            .parameterUpdateString(commandParameters)
            .put(" where ")
            .parameterConditionString(commandParameters);
        return true;
    }

    final DbRecordsAffected executeSQL(DbSerializerCommandQuery commandQuery, scope ref Serializable attribute)
    {
        return onExecuteSQL !is null
            ? onExecuteSQL(this, commandQuery, commandText, commandParameters, attribute)
            : connection.executeNonQuery(commandText[], commandParameters);
    }

    final DbParameter touchParameter(DbType type, scope ref Serializable attribute) nothrow
    {
        if (parameter is null)
        {
            const name = attribute.dbName;
            commandTextSize += (name.length * 2) + 5; // update ...(field, field) values(:field, :field);
            parameter = commandParameters.add(name, type);
        }
        else if (type != DbType.unknown)
            parameter.type = type;
        parameter.isKey = attribute.dbKey != DbKey.none;
        return parameter;
    }

    @property final override SerializerDataFormat dataFormat() const @nogc nothrow pure
    {
        return SerializerDataFormat.text;
    }

public:
    DbParameterList commandParameters;
    Appender!string commandText;
    size_t commandTextSize;
    DbConnection connection;
    DbParameter parameter;
    DbSerializerConstructSQL onConstructSQL;
    DbSerializerExecuteSQL onExecuteSQL;
    JsonSerializer subSerializer;
    DbSubSerializerKind subKind;
}


private:

version(UnitTestFBDatabase)
{
    import pham.db.db_database : DbConnection, DbDatabaseList;
    import pham.db.db_type;
    import pham.db.db_fbdatabase;

    DbConnection createUnitTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        DbCompressConnection compress = DbCompressConnection.disabled,
        DbIntegratedSecurityConnection integratedSecurity = DbIntegratedSecurityConnection.srp256)
    {
        auto db = DbDatabaseList.getDb(DbScheme.fb);
        auto result = db.createConnection("");
        auto csb = result.connectionStringBuilder;
        csb.databaseName = "UNIT_TEST";  // Use alias mapping name
        csb.receiveTimeout = dur!"seconds"(40);
        csb.sendTimeout = dur!"seconds"(20);
        csb.encrypt = encrypt;
        csb.compress = compress;
        csb.integratedSecurity = integratedSecurity;
        return result;
    }

    struct UnitTestCaptureSQL
    {
        string commandText;
        DbRecordsAffected commandResult;
        DbSerializerCommandQuery commandQuery;
        bool logOnly;

        DbRecordsAffected execute(DbSerializer serializer,
            DbSerializerCommandQuery commandQuery, ref Appender!string commandText, DbParameterList commandParameters,
            scope ref Serializable attribute) @safe
        {
            this.commandQuery = commandQuery;
            this.commandText = commandText[];

            debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(commandQuery=", commandQuery, ", commandText=", commandText, ")");

            this.commandResult = logOnly
                ? DbRecordsAffected.init
                : serializer.connection.executeNonQuery(this.commandText, commandParameters);
            return this.commandResult;
        }

        DbReader select(DbDeserializer serializer,
            ref Appender!string commandText, DbParameterList conditionParameters,
            scope ref Serializable attribute) @safe
        {
            this.commandText = commandText[];

            debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

            return logOnly
                ? DbReader.init
                : serializer.connection.executeReader(this.commandText, conditionParameters);
        }
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestS1
{
    import std.conv : to;

    UnitTestCaptureSQL captureSQL;
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestS1",
        "CREATE TABLE UnitTestS1(publicInt INTEGER NOT NULL PRIMARY KEY, publicGetSet INTEGER)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestS1");

    {
        auto c = UnitTestS1();
        scope serializer = new DbSerializer(connection);
        serializer.onExecuteSQL = &captureSQL.execute;

        debug(pham_ser_ser_serialization_db) debug writeln("INSERT---------begin");
        serializer.insert!UnitTestS1(c.setValues());
        debug(pham_ser_ser_serialization_db) debug writeln("insert!UnitTestS1=", captureSQL.commandQuery, ", commandText=", captureSQL.commandText,
            ", commandResult=", captureSQL.commandResult);
        debug(pham_ser_ser_serialization_db) debug writeln("INSERT---------end");
        assert(captureSQL.logOnly || captureSQL.commandResult == 1);

        debug(pham_ser_ser_serialization_db) debug writeln("UPDATE---------begin");
        serializer.update!UnitTestS1(c.setValues());
        debug(pham_ser_ser_serialization_db) debug writeln("update!UnitTestS1=", captureSQL.commandQuery, ", commandText=", captureSQL.commandText,
            ", commandResult=", captureSQL.commandResult);
        debug(pham_ser_ser_serialization_db) debug writeln("UPDATE---------end");
        assert(captureSQL.logOnly || captureSQL.commandResult >= 0); // If INSERT not in tranaction, it mays not updating any record
    }

    // One struct with manual sql reader
    {
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestS1();
        c.assertValues();
    }

    // One struct with sql select
    {
        scope deserializer = new DbDeserializer(connection);
        auto c = deserializer.select!UnitTestS1(["publicInt":Variant(20)]);
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestS1(publicInt, publicGetSet) VALUES(21, 2)");
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1 ORDER BY publicInt");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestS1[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(cast(int)i);
    }
}

version(UnitTestFBDatabase)
unittest // Sub aggregate & array
{
    import std.conv : to;

    static struct UnitTestSubS
    {
        int intVar;
        string stringVar;

        ref typeof(this) setValues() return
        {
            intVar = 101;
            stringVar = "UnitTestSubS";
            return this;
        }

        void assertValues()
        {
            assert(intVar == 101, intVar.to!string);
            assert(stringVar == "UnitTestSubS", stringVar);
        }
    }

    @Serializable(null, null, DbEntity("UnitTestSub"))
    static class UnitTestSubC
    {
        @Serializable("intVar", null, DbEntity("intVar", DbKey.primary))
        int intVar;
        string stringVar;
        bool boolVar;
        UnitTestSubS subsVar;
        long[] longArr;
        UnitTestSubS[] subsArr;
        short shortVar;

        typeof(this) setValues()
        {
            intVar = 1001;
            stringVar = "UnitTestSubC";
            boolVar = true;
            subsVar.setValues();

            longArr.length = 9;
            foreach (i; 0..longArr.length)
                longArr[i] = i+1;

            subsArr.length = 3;
            foreach (ref e; subsArr)
                e.setValues();

            shortVar = short.min;

            return this;
        }

        void assertValues()
        {
            assert(intVar == 1001, intVar.to!string);
            assert(stringVar == "UnitTestSubC", stringVar);
            assert(boolVar == true, boolVar.to!string);
            subsVar.assertValues();

            assert(longArr.length == 9, longArr.length.to!string);
            foreach (i; 0..longArr.length)
                assert(longArr[i] == i+1, i.to!string ~ ":" ~ longArr[i].to!string);

            assert(subsArr.length == 3, subsArr.length.to!string);
            foreach (ref e; subsArr)
                e.assertValues();

            assert(shortVar == short.min, shortVar.to!string);
        }
    }

    UnitTestCaptureSQL captureSQL;
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestSub", "CREATE TABLE UnitTestSub(intVar INTEGER NOT NULL PRIMARY KEY, stringVar VARCHAR(100), boolVar BOOLEAN" ~
        ", subsVar VARCHAR(1000), longArr VARCHAR(1000), subsArr VARCHAR(1000), shortVar SMALLINT)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestSub");

    {
        //captureSQL.logOnly = true;

        auto c = new UnitTestSubC();
        scope serializer = new DbSerializer(connection);
        serializer.onExecuteSQL = &captureSQL.execute;

        debug(pham_ser_ser_serialization_db) debug writeln("INSERT---------begin");
        serializer.insert!UnitTestSubC(c.setValues());
        debug(pham_ser_ser_serialization_db) debug writeln("insert!UnitTestSubC=", captureSQL.commandQuery, ", commandText=", captureSQL.commandText,
            ", commandResult=", captureSQL.commandResult);
        debug(pham_ser_ser_serialization_db) debug writeln("INSERT---------end");
        assert(captureSQL.logOnly || captureSQL.commandResult == 1);

        debug(pham_ser_ser_serialization_db) debug writeln("UPDATE---------begin");
        serializer.update!UnitTestSubC(c.setValues());
        debug(pham_ser_ser_serialization_db) debug writeln("update!UnitTestSubC=", captureSQL.commandQuery, ", commandText=", captureSQL.commandText,
            ", commandResult=", captureSQL.commandResult);
        debug(pham_ser_ser_serialization_db) debug writeln("UPDATE---------end");
        assert(captureSQL.logOnly || captureSQL.commandResult >= 0); // If INSERT not in tranaction, it mays not updating any record
    }

    // One struct with manual sql reader
    {
        auto reader = connection.executeReader("SELECT intVar, stringVar, boolVar, subsVar, longArr, subsArr, shortVar FROM UnitTestSub");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestSubC();
        c.assertValues();
    }

    // One struct with sql select
    {
        scope deserializer = new DbDeserializer(connection);
        deserializer.onSelectSQL = &captureSQL.select;
        auto c = deserializer.select!UnitTestSubC(["intVar":Variant(1001)]);
        c.assertValues();
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestAllTypesLess
{
    import std.conv : to;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestAllTypesLess",
        "CREATE TABLE UnitTestAllTypesLess(enum1 VARCHAR(20), bool1 BOOLEAN, byte1 SMALLINT" ~
        ", ubyte1 SMALLINT, short1 SMALLINT, ushort1 SMALLINT, int1 INTEGER, uint1 INTEGER" ~
        ", long1 BIGINT, ulong1 BIGINT, float1 FLOAT, double1 DOUBLE PRECISION" ~
        ", string1 VARCHAR(1000), charArray VARCHAR(1000), binary1 BLOB)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestAllTypesLess");
    connection.executeNonQuery("INSERT INTO UnitTestAllTypesLess(enum1, bool1, byte1" ~
        ", ubyte1, short1, ushort1, int1, uint1" ~
        ", long1, ulong1, float1, double1" ~
        ", string1, charArray, binary1)" ~
        " VALUES('third', true, 101" ~
        ", 0, -1003, 3975, -382653, 3957209" ~
        ", -394572364, 284659274, 6394763.5, -2846627456445.7651" ~
        ", 'test string of', 'will this work?', base64_decode('JRjMZSs='))");

    version(none)
    {
        auto c = new UnitTestAllTypesLess();
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestAllTypesLess(c.setValues());
        assert(serializer.buffer[] == jsonUnitTestAllTypes, serializer.buffer[]);
    }

    // One class
    {
        auto reader = connection.executeReader("SELECT enum1, bool1, byte1, ubyte1, short1, ushort1, int1, uint1, long1, ulong1, float1, double1, string1, charArray, binary1 FROM UnitTestAllTypesLess");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestAllTypesLess();
        assert(c !is null);
        c.assertValues();
    }

    // Array of classes
    {
        connection.executeNonQuery("INSERT INTO UnitTestAllTypesLess(enum1, bool1, byte1" ~
            ", ubyte1, short1, ushort1, int1, uint1" ~
            ", long1, ulong1, float1, double1" ~
            ", string1, charArray, binary1)" ~
            " VALUES('third', true, 102" ~
            ", 1, -1002, 3976, -382652, 3957210" ~
            ", -394572363, 284659275, 6394764.5, -2846627456444.7651" ~
            ", 'test string of', 'will this work?', base64_decode('JRjMZSs='))");
        auto reader = connection.executeReader("SELECT enum1, bool1, byte1, ubyte1, short1, ushort1, int1, uint1, long1, ulong1, float1, double1, string1, charArray, binary1 FROM UnitTestAllTypesLess ORDER BY byte1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestAllTypesLess[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
        {
            //import std.stdio : writeln; debug writeln("i=", i);
            assert(cs[i] !is null);
            cs[i].assertValuesArray(cast(int)i);
        }
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestStdBigInt
{
    import std.conv : to;
    import pham.ser.ser_std_bigint;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestStdBigInt",
        "CREATE TABLE UnitTestStdBigInt(i INTEGER, bigInt1 VARCHAR(200))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestStdBigInt");
    connection.executeNonQuery("INSERT INTO UnitTestStdBigInt(i, bigInt1) VALUES(0, '-71459266416693160362545788781600')");

    version(none)
    {
        UnitTestStdBigInt c;
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestStdBigInt(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdBigInt, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestStdBigInt");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestStdBigInt();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestStdBigInt(i, bigInt1) VALUES(1, '-71459266416693160362545788781599')");
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestStdBigInt ORDER BY i");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestStdBigInt[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(cast(int)i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestStdDateTime
{
    import std.conv : to;
    import pham.ser.ser_std_date_time;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestStdDateTime",
        "CREATE TABLE UnitTestStdDateTime(date1 DATE, dateTime1 TIMESTAMP, sysTime1 TIMESTAMP, timeOfDay1 TIME)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestStdDateTime");
    connection.executeNonQuery("INSERT INTO UnitTestStdDateTime(date1, dateTime1, sysTime1, timeOfDay1)" ~
        " VALUES('1999-01-01', '1999-07-06 12:30:33', '0001-01-01 00:00:33', '12:30:33')");

    version(none)
    {
        UnitTestStdDateTime c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdDateTime, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT date1, dateTime1, sysTime1, timeOfDay1 FROM UnitTestStdDateTime");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestStdDateTime();
        c.assertValuesArray(0);
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestStdDateTime(date1, dateTime1, sysTime1, timeOfDay1)" ~
            " VALUES('1999-01-02', '1999-07-07 12:30:33', '0001-01-02 00:00:33', '12:30:34')");
        auto reader = connection.executeReader("SELECT date1, dateTime1, sysTime1, timeOfDay1 FROM UnitTestStdDateTime ORDER BY date1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestStdDateTime[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(cast(int)i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestStdUuid
{
    import std.conv : to;
    import pham.ser.ser_std_uuid;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestStdUuid",
        "CREATE TABLE UnitTestStdUuid(uuid1 VARCHAR(36))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestStdUuid");
    connection.executeNonQuery("INSERT INTO UnitTestStdUuid(uuid1) VALUES('8ab3060e-2cba-4f23-b74c-b52db3dbfb46')");

    version(none)
    {
        UnitTestStdUuid c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestStdUuid(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdUuid, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT uuid1 FROM UnitTestStdUuid");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestStdUuid();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestStdUuid(uuid1) VALUES('8ab3060e-2cba-4f23-b74c-b52db3dbfb46')");
        auto reader = connection.executeReader("SELECT uuid1 FROM UnitTestStdUuid ORDER BY uuid1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestStdUuid[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValues();
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestPhamBigInteger
{
    import std.conv : to;
    import pham.ser.ser_pham_big_integer;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestPhamBigInteger",
        "CREATE TABLE UnitTestPhamBigInteger(i INTEGER, bigInt1 VARCHAR(200))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestPhamBigInteger");
    connection.executeNonQuery("INSERT INTO UnitTestPhamBigInteger(i, bigInt1) VALUES(0, '-71459266416693160362545788781600')");

    version(none)
    {
        UnitTestPhamBigInteger c;
        scope serializer = new DbSerializer();
        serializer.serialize!UnitTestPhamBigInteger(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestStdBigInt, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestPhamBigInteger");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestPhamBigInteger();
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestPhamBigInteger(i, bigInt1) VALUES(1, '-71459266416693160362545788781599')");
        auto reader = connection.executeReader("SELECT bigInt1 FROM UnitTestPhamBigInteger ORDER BY i");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestPhamBigInteger[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(cast(int)i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestPhamDateTime
{
    import std.conv : to;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestPhamDateTime",
        "CREATE TABLE UnitTestPhamDateTime(date1 DATE, dateTime1 TIMESTAMP, time1 TIME)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestPhamDateTime");
    connection.executeNonQuery("INSERT INTO UnitTestPhamDateTime(date1, dateTime1, time1) VALUES('1999-01-01', '1999-07-06 12:30:33', '12:30:33')");

    version(none)
    {
        UnitTestPhamDateTime c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestPhamDateTime(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestPhamDateTime, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT date1, dateTime1, time1 FROM UnitTestPhamDateTime");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestPhamDateTime();
        c.assertValuesArray(0);
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestPhamDateTime(date1, dateTime1, time1) VALUES('1999-01-02', '1999-07-07 12:30:33', '12:30:34')");
        auto reader = connection.executeReader("SELECT date1, dateTime1, time1 FROM UnitTestPhamDateTime ORDER BY date1");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestPhamDateTime[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(cast(int)i);
    }
}

version(UnitTestFBDatabase)
unittest // DbSerializer.UnitTestDecDecimal
{
    import std.conv : to;
    import pham.ser.ser_dec_decimal;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    //connection.createTableOrEmpty("CREATE TABLE UnitTestDecDecimal(decimal32 DECIMAL(7, 2), decimal64 DECIMAL(15, 2), decimal128 decfloat(34))");
    connection.createTableOrEmpty("UnitTestDecDecimal",
        "CREATE TABLE UnitTestDecDecimal(decimal32 DECIMAL(7, 2), decimal64 DECIMAL(15, 2), decimal128 DECIMAL(18, 2))");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestDecDecimal");
    connection.executeNonQuery("INSERT INTO UnitTestDecDecimal(decimal32, decimal64, decimal128) VALUES(-7145.0, 714583645.4, 294574120484.87)");

    version(none)
    {
        UnitTestDecDecimal c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestDecDecimal(c.setValues());
        //import std.stdio : writeln; debug writeln(serializer.buffer[]);
        assert(serializer.buffer[] == jsonUnitTestDecDecimal, serializer.buffer[]);
    }

    // One struct
    {
        auto reader = connection.executeReader("SELECT decimal32, decimal64, decimal128 FROM UnitTestDecDecimal");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestDecDecimal();
        c.assertValuesArray(0);
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestDecDecimal(decimal32, decimal64, decimal128) VALUES(-7144.0, 714583646.4, 294574120485.87)");
        auto reader = connection.executeReader("SELECT decimal32, decimal64, decimal128 FROM UnitTestDecDecimal ORDER BY decimal32");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestDecDecimal[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(cast(int)i);
    }
}

version(none)
unittest // DbSerializer.UnitTestCustomS1
{
    import std.conv : to;

    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestCustomS1",
        "CREATE TABLE UnitTestCustomS1(publicInt INTEGER, publicGetSet INTEGER)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestCustomS1");
    connection.executeNonQuery("INSERT INTO UnitTestCustomS1(publicInt, publicGetSet)" ~
        " VALUES(20, 1)");

    version(none)
    {
        UnitTestCustomS1 c;
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestCustomS1(c.setValues());
        jsonCustom = serializer.buffer[];
        //import std.stdio : writeln; debug writeln("\n", jsonCustom);
    }

    {
        scope deserializer = new JsonDeserializer(jsonCustom);
        auto c2 = deserializer.deserialize!UnitTestCustomS1();
        c2.assertValues();
    }
}
