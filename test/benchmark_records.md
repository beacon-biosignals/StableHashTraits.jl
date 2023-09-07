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

# With Buffering

In `dfl/hash-buffer` hash computations are delayed and data is stored in an intermediate
buffer and only hashed when enough data has been written to the buffer. This addresses
many of the issues when hashing low-level objects like numbers and strings. Anything
where the type of the objects is represented as a string for each value in an array
remains quite slow.

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio     
     │ SubStrin…   SubStrin…  String      String      Float64   
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        70.167 μs   51.761 ms   737.68
   2 │ tuples      crc        71.375 μs   9.623 ms    134.829
   3 │ symbols     crc        530.667 μs  5.145 ms      9.69535
   4 │ strings     crc        527.125 μs  4.413 ms      8.37159
   5 │ dataframes  crc        70.167 μs   385.792 μs    5.4982
   6 │ numbers     crc        35.208 μs   176.875 μs    5.02372
   7 │ structs     sha256     533.041 μs  55.757 ms   104.601
   8 │ tuples      sha256     532.958 μs  10.976 ms    20.5939
   9 │ dataframes  sha256     533.000 μs  993.000 μs    1.86304
  10 │ numbers     sha256     266.125 μs  487.792 μs    1.83294
  11 │ symbols     sha256     4.000 ms    6.611 ms      1.65291
  12 │ strings     sha256     4.000 ms    6.321 ms      1.58011
```

# Version 1.1:

With the addition of `dfl/compiled-type-labels` we compute more quantities at compile time:

There are a number of hash quantities that are, strictly speaking,
a function of the type of objects, not their content. These hashes can be optimized
using `@generated` functions to guarantee that their hashes are computed at compile time.

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio     
     │ SubStrin…   SubStrin…  String      String      Float64   
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        70.250 μs   1.158 ms    16.4798
   2 │ tuples      crc        70.500 μs   1.123 ms    15.9285
   3 │ numbers     crc        35.166 μs   174.833 μs   4.97165
   4 │ dataframes  crc        71.500 μs   352.917 μs   4.9359
   5 │ symbols     crc        530.541 μs  1.119 ms     2.10885
   6 │ strings     crc        527.000 μs  664.875 μs   1.26162
   7 │ structs     sha256     533.041 μs  2.907 ms     5.45361
   8 │ tuples      sha256     533.000 μs  2.176 ms     4.08255
   9 │ dataframes  sha256     533.000 μs  959.167 μs   1.79956
  10 │ numbers     sha256     266.000 μs  477.125 μs   1.7937
  11 │ symbols     sha256     3.999 ms    4.668 ms     1.16737
  12 │ strings     sha256     3.999 ms    2.224 ms     0.556134
```
