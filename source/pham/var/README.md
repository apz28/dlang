What's making pham.var.Variant differs from std.Variant
1. 100% faster
2. Bug fix for struct with destructor & its' sizeof greater than Variant.sizeof
3. Allow to react to its' property instead of catching exception such as length
4. Allow to plugin your own implementation for coerce