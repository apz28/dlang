/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2020 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * Conversion should be found under PostgreSQL...\src\backend\utils\adt\... (_recv or _send)
*/

module pham.db.db_pgconvert;

import core.time : Duration, dur;

version (unittest) import pham.utl.utl_test;
import pham.dtm.dtm_tick : Tick;
import pham.dtm.dtm_time_zone : TimeZoneInfo;
import pham.utl.utl_array : ShortStringBuffer, ShortStringBufferSize;
import pham.db.db_convert : toDecimalSafe;
import pham.db.db_type;
import pham.db.db_pgtype;

nothrow @safe:

enum epochDate = Date(2000, 1, 1);
enum epochDateTime = DateTime(2000, 1, 1);

version (none)
enum epochDateJulian = dateToJulian(2000, 1, 1); // 2_451_545

version (none)
int32 dateToJulian(int y, int m, int d) pure
{
	if (m > 2)
	{
		m += 1;
		y += 4_800;
	}
	else
	{
		m += 13;
		y += 4_799;
	}

	const century = y / 100;
	int julian = y * 365 - 32_167;
	julian += y / 4 - century + century / 4;
	julian += 7_834 * m / 256 + d;

	return julian;
}

version (none)
void julianToDateParts(int32 jd, out int year, out int month, out int day) pure
{
    uint julian = jd + 32_044;
    uint quad = julian / 146_097;
    uint extra = (julian - quad * 146_097) * 4 + 3;
    julian += 60 + quad * 3 + extra / 146_097;
    quad = julian / 1_461;
    julian -= quad * 1_461;
    const y = julian * 4 / 1_461;
    julian = ((y != 0) ? ((julian + 305) % 365) : ((julian + 306) % 366)) + 123;

    year = (y + quad * 4) - 4_800;
    quad = julian * 2_141 / 65_536;
    day = julian - 7_834 * quad / 256;
    month = (quad + 10) % 12 + 1;
}

version (none)
void dateDecode(int32 pgDate, out int year, out int month, out int day) pure
{
    julianToDateParts(pgDate + epochDateJulian, year, month, day);
}

DbDate dateDecode(int32 pgDate) @nogc pure
{
    return epochDate.addDaysSafe(pgDate);
}

int32 dateEncode(scope const(DbDate) value) @nogc pure
{
    return value.days - epochDate.days;
}

DbDateTime dateTimeDecode(int64 pgDateTime) @nogc pure
{
    auto dt = epochDateTime.addTicksSafe(timeToDuration(pgDateTime));
    return DbDateTime(dt, 0);
}

int64 dateTimeEncode(scope const(DbDateTime) value) @nogc pure
{
	auto d = value.toDuration() - epochDateTime.toDuration();
    return durationToTime(d);
}

DbDateTime dateTimeDecodeTZ(int64 pgDateTime, int32 pgZone)
{
	auto dt = epochDateTime.addTicksSafe(timeToDuration(pgDateTime));
	if (pgZone != 0)
		dt = dt.addSecondsSafe(-pgZone);
	return DbDateTime(TimeZoneInfo.convertUtcToLocal(dt.asUTC), 0);
}

void dateTimeEncodeTZ(scope const(DbDateTime) value, out int64 pgTime, out int32 pgZone)
{
    pgZone = 0;
	if (value.kind == DateTimeZoneKind.utc)
		pgTime = dateTimeEncode(value);
	else
    {
		auto utc = value.toUTC();
		pgTime = dateTimeEncode(utc);
    }
}

D numericDecode(D)(scope const(PgOIdNumeric) pgNumeric)
if (isDecimal!D)
{
	scope (failure) assert(0, "Assume nothrow failed");

    version (TraceFunction) traceFunction(pgNumeric.traceString());

    if (pgNumeric.isNaN)
        return D.nan;

	ShortStringBuffer!char value;

    // Negative sign
    if (pgNumeric.isNeg)
        value.put('-');

    int32 d;
	int16 d1;
	int16 dig;

	// Output all digits before the decimal point?
	if (pgNumeric.weight < 0)
	{
		d = pgNumeric.weight + 1;
		value.put('0');
	}
	else
	{
		for (d = 0; d <= pgNumeric.weight; d++)
		{
			dig = (d < pgNumeric.ndigits) ? pgNumeric.digits[d] : 0;
			// In the first digit, suppress extra leading decimal zeroes
			bool putit = d > 0;
			d1 = dig / 1000;
			dig -= d1 * 1000;
			putit |= d1 > 0;
			if (putit)
				value.put(cast(char)(d1 + '0'));

			d1 = dig / 100;
			dig -= d1 * 100;
			putit |= d1 > 0;
			if (putit)
				value.put(cast(char)(d1 + '0'));

			d1 = dig / 10;
			dig -= d1 * 10;
			putit |= d1 > 0;
			if (putit)
				value.put(cast(char)(d1 + '0'));

			value.put(cast(char)(dig + '0'));
		}
	}

	/*
	 * If requested, output a decimal point and all the digits that follow it.
	 * We initially put out a multiple of PgOIdNumeric.digitPerBase digits, then truncate if
	 * needed.
	 */
	if (pgNumeric.dscale > 0)
	{
		value.put('.');
		int16 vScale = pgNumeric.dscale;
		for (int i = 0; i < pgNumeric.dscale; d++, i += PgOIdNumeric.digitPerBase)
		{
			dig = (d >= 0 && d < pgNumeric.ndigits) ? pgNumeric.digits[d] : 0;
			d1 = dig / 1000;
			dig -= d1 * 1000;
			value.put(cast(char)(d1 + '0'));
			if (--vScale == 0)
				break;

			d1 = dig / 100;
			dig -= d1 * 100;
			value.put(cast(char)(d1 + '0'));
			if (--vScale == 0)
				break;

			d1 = dig / 10;
			dig -= d1 * 10;
			value.put(cast(char)(d1 + '0'));
			if (--vScale == 0)
				break;

			value.put(cast(char)(dig + '0'));
			if (--vScale == 0)
				break;
		}
	}

    version (TraceFunction) traceFunction("value=", value[]);

	if (pgNumeric.dscale > 0)
		return D(value[], RoundingMode.banking);
	else
		return D(value[]);
}

PgOIdNumeric numericEncode(D)(scope const(D) value)
if (isDecimal!D)
{
	enum maxDigits = 6_500; // max value of Decimal128

	if (value.isNaN)
		return PgOIdNumeric.NaN;

	ShortStringBufferSize!(char, maxDigits) sBuffer;
	value.toString!(ShortStringBufferSize!(char, maxDigits), char)(sBuffer);
	auto sValue = sBuffer[];
	size_t sLength = sValue.length;
	while (sLength > 1 && sValue[sLength - 1] == '0')
		sLength--;

    PgOIdNumeric result;

	size_t sIndex = sValue[0] == '-' ? 1 : 0;
	if (sIndex)
		result.setSign(PgOIdNumeric.signNeg);

	//ubyte[] ddigits = new ubyte[]((sLength - sIndex) + PgOIdNumeric.digitPerBase * 2);
	//ddigits[] = 0; // Set all to zero
	auto ddigits = ShortStringBufferSize!(ubyte, maxDigits)(true);
	int dInd = PgOIdNumeric.digitPerBase;
	int dweight = -1;
	bool haveDP = false;

	for (; sIndex < sLength; sIndex++)
    {
		const char d = sValue[sIndex];
		if (d == '.')
			haveDP = true;
		else
        {
			ddigits[dInd++] = cast(ubyte)(d - '0');
			if (haveDP)
				result.dscale++;
			else
				dweight++;
        }
    }

	/*
	 * Okay, convert pure-decimal representation to base NBASE.  First we need
	 * to determine the converted weight and ndigits.  offset is the number of
	 * decimal zeroes to insert before the first given digit to have a
	 * correctly aligned first NBASE digit.
	 */
	if (dweight >= 0)
		result.weight = cast(int16)((dweight + 1 + PgOIdNumeric.digitPerBase - 1) / PgOIdNumeric.digitPerBase - 1);
	else
		result.weight = cast(int16)(-((-dweight - 1) / PgOIdNumeric.digitPerBase + 1));
	int offset = (result.weight + 1) * PgOIdNumeric.digitPerBase - (dweight + 1);
	dInd = dInd - PgOIdNumeric.digitPerBase;
	int ndigits = (dInd + offset + PgOIdNumeric.digitPerBase - 1) / PgOIdNumeric.digitPerBase;
	result.ndigits = cast(int16)ndigits;
	result.digits.length = ndigits;
	dInd = PgOIdNumeric.digitPerBase - offset;
	int nInd = 0;
	while (ndigits-- > 0)
	{
		result.digits[nInd++] = cast(int16)(((ddigits[dInd] * 10 + ddigits[dInd + 1]) * 10 +
											ddigits[dInd + 2]) * 10 + ddigits[dInd + 3]);
		dInd += PgOIdNumeric.digitPerBase;
	}

	/* Normalize */
	nInd = 0;
	ndigits = result.ndigits;

	// Strip leading zeroes
	while (ndigits > 0 && result.digits[nInd] == 0)
	{
		result.weight--;
		nInd++;
		ndigits--;
	}

	// Strip trailing zeroes
	while (ndigits > 0 && result.digits[ndigits - 1] == 0)
		ndigits--;

	// If it's zero, normalize the sign and weight
	if (ndigits == 0)
	{
		result.sign = 0;
		result.weight = 0;
	}

	if (nInd != 0 || result.ndigits != ndigits)
    {
		assert(nInd + ndigits <= result.digits.length);

		result.digits = result.digits[nInd..nInd + ndigits];
		result.ndigits = cast(int16)ndigits;
    }

    return result;
}

DbTime timeDecode(int64 pgTime) @nogc pure
{
    return DbTime(timeToDuration(pgTime), DateTimeZoneKind.unspecified, 0);
}

int64 timeEncode(scope const(DbTime) value) @nogc pure
{
    return durationToTime(value.toDuration());
}

DbTime timeDecodeTZ(int64 pgTime, int32 pgZone)
{
	auto dt = DateTime(DateTime.utcNow.date, Time(timeToDuration(pgTime)));
	if (pgZone != 0)
		dt = dt.addSecondsSafe(-pgZone);
	return DbTime(TimeZoneInfo.convertUtcToLocal(dt.asUTC).time, 0);
}

void timeEncodeTZ(scope const(DbTime) value, out int64 pgTime, out int32 pgZone)
{
    pgZone = 0;
	if (value.kind == DateTimeZoneKind.utc)
		pgTime = timeEncode(value);
	else
    {
		auto utc = value.toUTC();
		pgTime = timeEncode(utc);
    }
}

// value can have date part
pragma(inline, true)
int64 durationToTime(scope const(Duration) value) @nogc pure
{
	return value.total!"usecs"();
}

// pgTime can have date part
pragma(inline, true)
Duration timeToDuration(int64 pgTime) @nogc pure
{
	return dur!"usecs"(pgTime);
}


// Any below codes are private
private:

unittest // numericDecode
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.pgconvert.numericDecode");

	PgOIdNumeric n5_40 = {ndigits:2, weight:0, sign:0, dscale:2, digits:[5, 4000]};
	PgOIdNumeric n6_50 = {ndigits:2, weight:0, sign:0, dscale:2, digits:[6, 5000]};

	assert(numericDecode!Decimal64(n5_40) == toDecimalSafe!Decimal64("5.40", Decimal64.nan));
	assert(numericDecode!Decimal64(n6_50) == toDecimalSafe!Decimal64("6.50", Decimal64.nan));
}

unittest // numericEncode
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.pgconvert.numericEncode");

	// Scale=1 because Decimal.toString will truncate trailing zero
	PgOIdNumeric n5_40 = {ndigits:2, weight:0, sign:0, dscale:1, digits:[5, 4000]};
	PgOIdNumeric n6_50 = {ndigits:2, weight:0, sign:0, dscale:1, digits:[6, 5000]};

	static void traceNumeric(PgOIdNumeric pgNumeric)
    {
		version (TraceFunction)
		traceUnitTest(pgNumeric.traceString());
    }

	auto dec5_40 = toDecimalSafe!Decimal64("5.40", Decimal64.nan);
	auto num5_40 = numericEncode!Decimal64(dec5_40);
	//traceUnitTest(dec5_40.toString());
	//traceNumeric(num5_40);
	//traceNumeric(n5_40);
	assert(num5_40 == n5_40);

	auto dec6_50 = toDecimalSafe!Decimal64("6.50", Decimal64.nan);
	auto num6_50 = numericEncode!Decimal64(dec6_50);
	assert(num6_50 == n6_50);
}
