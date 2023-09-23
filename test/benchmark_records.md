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
   1 │ structs     crc        70.208 μs   48.835 ms   695.579
   2 │ tuples      crc        70.125 μs   9.967 ms    142.128
   3 │ symbols     crc        526.625 μs  5.401 ms     10.2566
   4 │ strings     crc        526.875 μs  4.812 ms      9.13302
   5 │ dataframes  crc        70.125 μs   293.958 μs    4.19191
   6 │ numbers     crc        35.167 μs   130.958 μs    3.72389
   7 │ structs     sha256     532.750 μs  58.138 ms   109.129
   8 │ tuples      sha256     532.791 μs  12.497 ms    23.4549
   9 │ symbols     sha256     3.999 ms    7.662 ms      1.91611
  10 │ strings     sha256     3.999 ms    6.481 ms      1.6207
  11 │ dataframes  sha256     532.833 μs  783.875 μs    1.47115
  12 │ numbers     sha256     265.833 μs  372.500 μs    1.40126
  ```
