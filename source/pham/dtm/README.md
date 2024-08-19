What's making pham.dtm.Date, DateTime, Time differs from std.Date, std.DateTime, std.TimeOfDay, std.SysTime
1. 50% faster when to convert between those types & adding/substracting unit from them
2. They all have same size (long or 8 bytes)
3. Many format specifiers
4. Various ways to convert from string format
5. Handling day-time-saving automatically & correctly
6. Build in for sub second value