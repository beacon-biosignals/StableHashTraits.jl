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
   1 │ structs     crc        71.000 μs   69.913 ms   984.69
   2 │ tuples      crc        71.625 μs   11.715 ms   163.561
   3 │ symbols     crc        536.708 μs  6.356 ms     11.8418
   4 │ dataframes  crc        71.750 μs   816.500 μs   11.3798
   5 │ numbers     crc        35.833 μs   379.458 μs   10.5896
   6 │ strings     crc        536.584 μs  5.414 ms     10.0896
   7 │ structs     sha256     576.125 μs  73.729 ms   127.973
   8 │ tuples      sha256     575.875 μs  13.202 ms    22.9253
   9 │ dataframes  sha256     575.750 μs  1.533 ms      2.6629
  10 │ numbers     sha256     286.416 μs  739.833 μs    2.58307
  11 │ symbols     sha256     4.015 ms    8.191 ms      2.03984
  12 │ strings     sha256     4.076 ms    6.872 ms      1.68624
```
