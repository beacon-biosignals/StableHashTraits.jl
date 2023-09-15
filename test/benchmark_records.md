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

# Version 1.1

With the addition of `dfl/compiled-type-labels` we compute more quantities at compile time:

There are a number of hash quantities that are, strictly speaking,
a function of the type of objects, not their content. These hashes can be optimized
using `@generated` functions to guarantee that their hashes are computed at compile time.

```
  12×5 DataFrame
  Row │ benchmark   hash       base        trait       ratio
      │ SubStrin…   SubStrin…  String      String      Float64
─────┼──────────────────────────────────────────────────────────
    1 │ structs     crc        71.542 μs   934.042 μs  13.0559
    2 │ tuples      crc        71.500 μs   727.750 μs  10.1783
    3 │ dataframes  crc        71.416 μs   215.916 μs   3.02336
    4 │ numbers     crc        35.833 μs   106.625 μs   2.97561
    5 │ symbols     crc        536.833 μs  600.958 μs   1.11945
    6 │ strings     crc        537.125 μs  494.792 μs   0.921186
    7 │ structs     sha256     543.542 μs  2.047 ms     3.7665
    8 │ tuples      sha256     543.542 μs  1.583 ms     2.91176
    9 │ dataframes  sha256     543.583 μs  706.667 μs   1.30002
   10 │ numbers     sha256     271.375 μs  352.167 μs   1.29771
   11 │ strings     sha256     4.079 ms    1.721 ms     0.421928
   12 │ symbols     sha256     4.079 ms    1.625 ms     0.398343
```

# Version 1.2

Version 1.2 introduces `HashVersion{3}`. This reduces the number of hash collisions by
hashing the type of all primitive types. To avoid substantial slow-downs it elides these
types in cases where the struct type or element type is concrete. (so `Any[1, 2]` would
encode the type of each element but `[1, 2]` would only encode the type of the array). 

The exact cause for the slow downs here are a little unclear. It appears
to be that there are some optimizations that can be applied in 1.1 that don't
apply in the more generalized code in this version, since both HashVersion{2}
and HashVersion{3} are slower.

```
24×6 DataFrame
  Row │ version    benchmark   hash       base        trait       ratio     
      │ SubStrin…  SubStrin…   SubStrin…  String      String      Float64   
─────┼─────────────────────────────────────────────────────────────────────
    1 │ 2          structs     crc        71.792 μs   2.856 ms    39.7764
    2 │ 2          tuples      crc        71.625 μs   1.571 ms    21.9407
    3 │ 2          dataframes  crc        71.625 μs   644.916 μs   9.00406
    4 │ 2          numbers     crc        36.000 μs   319.542 μs   8.87617
    5 │ 2          symbols     crc        537.041 μs  2.353 ms     4.38173
    6 │ 2          strings     crc        536.958 μs  979.625 μs   1.8244
    7 │ 2          structs     sha256     543.209 μs  3.919 ms     7.21446
    8 │ 2          tuples      sha256     543.458 μs  2.426 ms     4.46362
    9 │ 2          dataframes  sha256     543.375 μs  1.135 ms     2.08972
   10 │ 2          numbers     sha256     271.167 μs  565.083 μs   2.08389
   11 │ 2          symbols     sha256     4.076 ms    3.373 ms     0.827646
   12 │ 2          strings     sha256     4.075 ms    2.206 ms     0.541368
   13 │ 3          structs     crc        71.709 μs   3.602 ms    50.2256
   14 │ 3          tuples      crc        71.625 μs   1.959 ms    27.3531
   15 │ 3          dataframes  crc        71.625 μs   679.625 μs   9.48866
   16 │ 3          numbers     crc        36.083 μs   336.833 μs   9.33495
   17 │ 3          symbols     crc        540.333 μs  1.277 ms     2.36328
   18 │ 3          strings     crc        537.083 μs  317.125 μs   0.590458
   19 │ 3          structs     sha256     543.167 μs  4.390 ms     8.08277
   20 │ 3          tuples      sha256     543.375 μs  2.519 ms     4.63661
   21 │ 3          dataframes  sha256     543.375 μs  1.169 ms     2.15183
   22 │ 3          numbers     sha256     271.125 μs  581.125 μs   2.14338
   23 │ 3          symbols     sha256     4.076 ms    2.309 ms     0.566409
   24 │ 3          strings     sha256     4.075 ms    1.238 ms     0.303842
```
