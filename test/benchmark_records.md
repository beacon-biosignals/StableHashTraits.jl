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
   1 │ structs     crc        70.334 μs   57.265 ms   814.193
   2 │ tuples      crc        71.625 μs   10.640 ms   148.551
   3 │ dataframes  crc        71.541 μs   589.375 μs    8.23828
   4 │ symbols     crc        781.166 μs  6.235 ms      7.98128
   5 │ numbers     crc        35.958 μs   282.583 μs    7.8587
   6 │ strings     crc        775.916 μs  5.038 ms      6.49356
   7 │ structs     sha256     575.083 μs  67.766 ms   117.836
   8 │ tuples      sha256     575.042 μs  13.383 ms    23.273
   9 │ symbols     sha256     1.588 ms    8.491 ms      5.34789
  10 │ strings     sha256     1.624 ms    6.798 ms      4.18542
  11 │ dataframes  sha256     574.958 μs  1.092 ms      1.89883
  12 │ numbers     sha256     286.666 μs  528.500 μs    1.84361
```
