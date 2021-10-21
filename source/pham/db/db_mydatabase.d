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

module pham.db.mydatabase;

import std.array : Appender;
import std.conv : text, to;
import std.exception : assumeWontThrow;
import std.system : Endian;

import pham.external.std.log.logger : Logger, LogTimming;
version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.db.object;
import pham.db.message;
import pham.db.exception;
import pham.db.util;
import pham.db.type;
import pham.db.buffer;
//import pham.db.buffer_filter;
//import pham.db.buffer_filter_cipher;
import pham.db.value;
import pham.db.database;
import pham.db.skdatabase;
import pham.db.myoid;
//import pham.db.mytype;
import pham.db.myexception;
import pham.db.mybuffer;
//import pham.db.myprotocol;

version (none)
class MyCommand : SkCommand
{
public:
    this(SkConnection connection, string name = null) nothrow @safe
    {
        super(connection, name);
    }

    this(SkConnection connection, DbTransaction transaction, string name = null) nothrow @safe
    {
        super(connection, transaction, name);
    }

    final override DbRowValue fetch(bool isScalar) @safe
    {
        version (TraceFunction) dgFunctionTrace();
        version (profile) debug auto p = PerfFunction.create();

        checkActive();

		if (isStoredProcedure)
            return fetchedRows ? fetchedRows.dequeue() : DbRowValue(0);

        if (fetchedRows.empty && !allRowsFetched && isSelectCommandType())
            doFetch(isScalar);

        return fetchedRows ? fetchedRows.dequeue() : DbRowValue(0);
    }

protected:
    override void prepareExecute(DbCommandExecuteType type) @safe
    {
        super.prepareExecute(type);
        fetchedRows.clear();
    }

    abstract void doFetch(bool isScalar) @safe;

protected:
	DbRowValueQueue fetchedRows;
}

class MyConnection : SkConnection
{
public:
    this(MyDatabase database) nothrow @safe
    {
        super(database);
    }

    this(MyDatabase database, string connectionString) nothrow @safe
    {
        super(database, connectionString);
    }

    this(MyDatabase database, MyConnectionStringBuilder connectionStringBuilder) nothrow @safe
    in
    {
        assert(connectionStringBuilder !is null);
        assert(connectionStringBuilder.scheme == scheme);
    }
    do
    {
        super(database, connectionStringBuilder);
    }

    /* Properties */

    @property final MyConnectionStringBuilder myConnectionStringBuilder() nothrow pure @safe
    {
        return cast(MyConnectionStringBuilder)connectionStringBuilder;
    }

    @property final override DbIdentitier scheme() const nothrow pure @safe
    {
        return DbIdentitier(DbScheme.my);
    }

package(pham.db):

protected:
    final override void doCancelCommand() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        //todo
    }

    final override void doOpen() @safe
    {
        version (TraceFunction) dgFunctionTrace();
        //todo
    }

    final override string getServerVersion() @safe
    {
        return null; //todo
    }

protected:

private:
}

class MyConnectionStringBuilder : SkConnectionStringBuilder
{
public:
    this(string connectionString) nothrow @safe
    {
        super(connectionString);
    }

    final override const(string[]) parameterNames() const nothrow @safe
    {
        return null; // todo
    }

    @property final override DbIdentitier scheme() const nothrow pure @safe
    {
        return DbIdentitier(DbScheme.my);
    }

protected:
}

class MyDatabase : DbDatabase
{
nothrow @safe:

public:
    this()
    {
        this._name = DbIdentitier(DbScheme.my);
    }

    override DbCommand createCommand(DbConnection connection, string name = null)
    in
    {
        assert ((cast(MyConnection)connection) !is null);
    }
    do
    {
        return null; //todo
        //return new MyCommand(cast(MyConnection)connection, name);
    }

    override DbCommand createCommand(DbConnection connection, DbTransaction transaction, string name = null)
    in
    {
        assert ((cast(MyConnection)connection) !is null);
        //assert ((cast(MyTransaction)transaction) !is null);
    }
    do
    {
        return null; //todo
        //return new MyCommand(cast(MyConnection)connection, cast(MyTransaction)transaction, name);
    }

    override DbConnection createConnection(string connectionString)
    {
        auto result = new MyConnection(this, connectionString);
        result.logger = this.logger;
        return result;
    }

    override DbConnection createConnection(DbConnectionStringBuilder connectionStringBuilder)
    in
    {
        assert(connectionStringBuilder !is null);
        assert(cast(MyConnectionStringBuilder)connectionStringBuilder !is null);
    }
    do
    {
        auto result = new MyConnection(this, cast(MyConnectionStringBuilder)connectionStringBuilder);
        result.logger = this.logger;
        return result;
    }

    override DbConnectionStringBuilder createConnectionStringBuilder(string connectionString)
    {
        return new MyConnectionStringBuilder(connectionString);
    }

    override DbField createField(DbCommand command, DbIdentitier name)
    in
    {
        //assert ((cast(MyCommand)command) !is null);
    }
    do
    {
        return null; //todo
        //return new MyField(cast(MyCommand)command, name);
    }

    override DbFieldList createFieldList(DbCommand command)
    in
    {
        //assert (cast(MyCommand)command !is null);
    }
    do
    {
        return null; //todo
        //return new MyFieldList(cast(MyCommand)command);
    }

    override DbParameter createParameter(DbIdentitier name)
    {
        return null; //todo
        //return new MyParameter(this, name);
    }

    override DbParameterList createParameterList()
    {
        return null; //todo
        //return new MyParameterList(this);
    }

    override DbTransaction createTransaction(DbConnection connection, DbIsolationLevel isolationLevel, bool defaultTransaction)
    in
    {
        assert ((cast(MyConnection)connection) !is null);
    }
    do
    {
        return null; //todo
        //return new MyTransaction(cast(MyConnection)connection, isolationLevel);
    }
}


// Any below codes are private
private:
