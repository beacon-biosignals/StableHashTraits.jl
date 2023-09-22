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
