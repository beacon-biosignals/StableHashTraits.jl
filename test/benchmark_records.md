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
 Row │ benchmark   hash       base        trait       ratio     
     │ SubStrin…   SubStrin…  String      String      Float64   
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        70.250 μs   51.331 ms   730.684
   2 │ tuples      crc        70.292 μs   10.081 ms   143.412
   3 │ symbols     crc        529.958 μs  5.575 ms     10.52
   4 │ strings     crc        527.083 μs  4.766 ms      9.04135
   5 │ dataframes  crc        70.125 μs   287.125 μs    4.09447
   6 │ numbers     crc        35.375 μs   127.417 μs    3.60189
   7 │ structs     sha256     532.792 μs  60.647 ms   113.828
   8 │ tuples      sha256     532.958 μs  12.681 ms    23.7928
   9 │ symbols     sha256     3.999 ms    7.591 ms      1.89818
  10 │ strings     sha256     3.999 ms    6.579 ms      1.64511
  11 │ dataframes  sha256     532.917 μs  777.083 μs    1.45817
  12 │ numbers     sha256     265.875 μs  367.625 μs    1.3827
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
  ```
