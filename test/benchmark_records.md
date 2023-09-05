# Benchmark Records

A record of benchmarks from various versions of `stable_hash`

# Version 1.0

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio      
     │ SubStrin…   SubStrin…  String      String      Float64    
─────┼───────────────────────────────────────────────────────────
   1 │ structs     crc        78.667 μs   125.481 ms  1595.09
   2 │ tuples      crc        79.250 μs   31.102 ms    392.453
   3 │ dataframes  crc        79.417 μs   6.382 ms      80.3635
   4 │ numbers     crc        39.875 μs   3.102 ms      77.7842
   5 │ symbols     crc        597.166 μs  21.122 ms     35.3705
   6 │ strings     crc        597.625 μs  13.749 ms     23.0063
   7 │ structs     sha256     545.916 μs  190.883 ms   349.656
   8 │ tuples      sha256     545.917 μs  47.118 ms     86.3101
   9 │ dataframes  sha256     547.500 μs  11.283 ms     20.6081
  10 │ numbers     sha256     271.708 μs  5.433 ms      19.9951
  11 │ symbols     sha256     4.086 ms    32.191 ms      7.87788
  12 │ strings     sha256     4.085 ms    21.856 ms      5.34987
```

# Hash APi Refactoring (`dfl/refactor-hash-api`)

Introduces some modest performance improvements, but this refactoring
is mainly to pave the way for larger performance imporvements in future PRs.

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio      
     │ SubStrin…   SubStrin…  String      String      Float64    
─────┼───────────────────────────────────────────────────────────
   1 │ structs     crc        78.541 μs   91.125 ms   1160.23
   2 │ tuples      crc        79.542 μs   22.047 ms    277.18
   3 │ dataframes  crc        79.375 μs   3.996 ms      50.3462
   4 │ numbers     crc        39.750 μs   1.957 ms      49.2254
   5 │ symbols     crc        598.334 μs  12.765 ms     21.3347
   6 │ strings     crc        601.458 μs  9.549 ms      15.8757
   7 │ structs     sha256     545.167 μs  181.623 ms   333.152
   8 │ tuples      sha256     545.042 μs  45.179 ms     82.8901
   9 │ dataframes  sha256     544.750 μs  10.383 ms     19.0596
  10 │ numbers     sha256     271.667 μs  5.130 ms      18.8846
  11 │ symbols     sha256     4.033 ms    30.873 ms      7.65412
  12 │ strings     sha256     4.086 ms    19.308 ms      4.72488
```
