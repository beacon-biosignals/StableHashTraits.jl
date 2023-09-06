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

# Hash Buffering

(before making more hashes buffered)

```
18×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio      
     │ SubStrin…   SubStrin…  String      String      Float64    
─────┼───────────────────────────────────────────────────────────
   1 │ structs     crc        70.333 μs   70.529 ms   1002.79
   2 │ tuples      crc        71.542 μs   13.918 ms    194.54
   3 │ dataframes  crc        71.541 μs   1.411 ms      19.7166
   4 │ numbers     crc        35.250 μs   686.167 μs    19.4657
   5 │ symbols     crc        536.750 μs  9.583 ms      17.8537
   6 │ strings     crc        530.417 μs  6.955 ms      13.1124
   7 │ structs     fnv64      199.833 μs  55.307 ms    276.765
   8 │ tuples      fnv64      203.625 μs  10.016 ms     49.1872
   9 │ symbols     fnv64      1.499 ms    6.434 ms       4.2915
  10 │ strings     fnv64      1.499 ms    4.633 ms       3.09061
  11 │ dataframes  fnv64      199.791 μs  242.417 μs     1.21335
  12 │ numbers     fnv64      99.875 μs   105.750 μs     1.05882
  13 │ structs     sha256     533.083 μs  84.956 ms    159.368
  14 │ tuples      sha256     533.208 μs  14.725 ms     27.6152
  15 │ dataframes  sha256     533.083 μs  1.397 ms       2.62029
  16 │ numbers     sha256     271.000 μs  689.542 μs     2.54444
  17 │ symbols     sha256     3.999 ms    9.211 ms       2.30324
  18 │ strings     sha256     4.008 ms    7.505 ms       1.87284
```

(after making all hases buffered)
NOTE: while this slows thigns down for fnv in some cases, the older implementation
using `bytesof` was flowed and could lead to API bugs

```
 Row │ benchmark   hash       base        trait       ratio      
     │ SubStrin…   SubStrin…  String      String      Float64    
─────┼───────────────────────────────────────────────────────────
   1 │ structs     crc        70.250 μs   64.947 ms   924.512
   2 │ tuples      crc        71.583 μs   10.660 ms   148.915
   3 │ symbols     crc        536.875 μs  5.684 ms     10.5879
   4 │ strings     crc        531.959 μs  4.933 ms      9.27257
   5 │ dataframes  crc        71.542 μs   248.083 μs    3.46766
   6 │ numbers     crc        35.166 μs   102.916 μs    2.92658
   7 │ structs     fnv64      203.625 μs  63.412 ms   311.417
   8 │ tuples      fnv64      203.625 μs  11.275 ms    55.3734
   9 │ symbols     fnv64      1.499 ms    6.126 ms      4.08624
  10 │ strings     fnv64      1.528 ms    5.290 ms      3.46205
  11 │ dataframes  fnv64      199.875 μs  491.542 μs    2.45925
  12 │ numbers     fnv64      99.916 μs   213.708 μs    2.13888
  13 │ structs     sha256     576.000 μs  88.085 ms   152.926
  14 │ tuples      sha256     573.666 μs  17.557 ms    30.6048
  15 │ symbols     sha256     4.000 ms    11.740 ms     2.93488
  16 │ strings     sha256     4.075 ms    8.720 ms      2.13965
  17 │ dataframes  sha256     571.292 μs  367.917 μs    0.644009
  18 │ numbers     sha256     286.250 μs  158.375 μs    0.553275
```

conclusion, we don't really need fnv when we buffer; it's not really any faster 
than `crc`, so, lady da
