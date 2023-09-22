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
   1 │ tuples      crc        71.417 μs   2.818 ms    39.4566
   2 │ structs     crc        71.583 μs   2.673 ms    37.3401
   3 │ dataframes  crc        71.458 μs   383.708 μs   5.3697
   4 │ numbers     crc        35.959 μs   188.084 μs   5.23051
   5 │ symbols     crc        536.666 μs  1.529 ms     2.84822
   6 │ strings     crc        536.750 μs  1.302 ms     2.42509
   7 │ structs     sha256     543.167 μs  7.037 ms    12.9558
   8 │ tuples      sha256     543.209 μs  6.893 ms    12.6899
   9 │ dataframes  sha256     543.167 μs  1.154 ms     2.12419
  10 │ numbers     sha256     271.083 μs  565.834 μs   2.08731
  11 │ strings     sha256     4.076 ms    3.966 ms     0.972932
  12 │ symbols     sha256     4.075 ms    3.845 ms     0.943553
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
