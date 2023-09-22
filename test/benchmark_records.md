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
   1 │ structs     crc        70.209 μs   45.612 ms   649.661
   2 │ tuples      crc        71.541 μs   9.342 ms    130.587
   3 │ symbols     crc        537.709 μs  5.041 ms      9.37566
   4 │ strings     crc        528.042 μs  4.452 ms      8.43162
   5 │ dataframes  crc        70.334 μs   271.250 μs    3.8566
   6 │ numbers     crc        35.167 μs   118.209 μs    3.36136
   7 │ structs     sha256     539.083 μs  55.572 ms   103.086
   8 │ tuples      sha256     533.458 μs  11.919 ms    22.343
   9 │ symbols     sha256     4.002 ms    7.135 ms      1.78307
  10 │ strings     sha256     4.005 ms    6.227 ms      1.55495
  11 │ dataframes  sha256     533.375 μs  761.291 μs    1.42731
  12 │ numbers     sha256     271.208 μs  367.042 μs    1.35336
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
   1 │ structs     crc        70.250 μs   1.097 ms    15.6145
   2 │ tuples      crc        71.500 μs   913.875 μs  12.7815
   3 │ numbers     crc        35.166 μs   120.917 μs   3.43846
   4 │ dataframes  crc        71.416 μs   241.209 μs   3.37752
   5 │ symbols     crc        536.833 μs  690.000 μs   1.28532
   6 │ strings     crc        526.875 μs  607.167 μs   1.15239
   7 │ structs     sha256     533.125 μs  3.104 ms     5.82306
   8 │ tuples      sha256     533.167 μs  2.636 ms     4.94365
   9 │ dataframes  sha256     533.500 μs  727.708 μs   1.36403
  10 │ numbers     sha256     271.000 μs  365.458 μs   1.34855
  11 │ symbols     sha256     4.000 ms    2.311 ms     0.577854
  12 │ strings     sha256     4.075 ms    2.269 ms     0.556884

# Version 1.2

Version 1.2 introduces `HashVersion{3}`. This reduces the number of hash collisions by
hashing the type of all primitive types. To avoid substantial slow-downs it elides these
types in cases where the struct type or element type is concrete. (so `Any[1, 2]` would
encode the type of each element but `[1, 2]` would only encode the type of the array). 

```
28×6 DataFrame
 Row │ version    benchmark   hash       base        trait       ratio     
     │ SubStrin…  SubStrin…   SubStrin…  String      String      Float64   
─────┼─────────────────────────────────────────────────────────────────────
   1 │ 2          structs     crc        71.750 μs   956.167 μs  13.3264
   2 │ 2          tuples      crc        70.917 μs   739.292 μs  10.4248
   3 │ 2          dataframes  crc        71.833 μs   261.209 μs   3.63634
   4 │ 2          vnumbers    crc        35.250 μs   127.084 μs   3.60522
   5 │ 2          numbers     crc        36.042 μs   129.417 μs   3.59073
   6 │ 2          symbols     crc        526.792 μs  551.541 μs   1.04698
   7 │ 2          strings     crc        536.958 μs  491.167 μs   0.914721
   8 │ 2          structs     sha256     543.166 μs  2.056 ms     3.78468
   9 │ 2          tuples      sha256     543.166 μs  1.607 ms     2.95866
  10 │ 2          dataframes  sha256     533.000 μs  740.458 μs   1.38923
  11 │ 2          vnumbers    sha256     271.666 μs  375.500 μs   1.38221
  12 │ 2          numbers     sha256     271.041 μs  374.042 μs   1.38002
  13 │ 2          symbols     sha256     4.021 ms    1.788 ms     0.444611
  14 │ 2          strings     sha256     4.140 ms    1.748 ms     0.422212
  15 │ 3          structs     crc        72.958 μs   1.027 ms    14.0806
  16 │ 3          tuples      crc        71.792 μs   618.125 μs   8.60994
  17 │ 3          symbols     crc        537.000 μs  2.133 ms     3.97183
  18 │ 3          dataframes  crc        70.833 μs   259.000 μs   3.65649
  19 │ 3          vnumbers    crc        35.375 μs   128.917 μs   3.6443
  20 │ 3          numbers     crc        35.250 μs   126.959 μs   3.60167
  21 │ 3          strings     crc        536.959 μs  158.791 μs   0.295723
  22 │ 3          structs     sha256     543.083 μs  1.806 ms     3.32561
  23 │ 3          tuples      sha256     546.083 μs  1.157 ms     2.11941
  24 │ 3          vnumbers    sha256     271.041 μs  376.958 μs   1.39078
  25 │ 3          dataframes  sha256     543.208 μs  753.834 μs   1.38774
  26 │ 3          numbers     sha256     271.083 μs  374.000 μs   1.37965
  27 │ 3          symbols     sha256     4.074 ms    3.558 ms     0.87343
  28 │ 3          strings     sha256     4.139 ms    1.086 ms     0.262367
```
