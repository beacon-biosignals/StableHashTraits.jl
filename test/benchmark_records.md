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
   1 │ structs     crc        70.250 μs   49.386 ms   703.011
   2 │ symbols     crc        12.166 μs   5.328 ms    437.928
   3 │ strings     crc        12.166 μs   4.777 ms    392.686
   4 │ tuples      crc        71.417 μs   10.082 ms   141.177
   5 │ dataframes  crc        70.208 μs   290.167 μs    4.13296
   6 │ numbers     crc        35.167 μs   126.375 μs    3.59357
   7 │ structs     sha256     532.833 μs  60.885 ms   114.266
   8 │ tuples      sha256     533.000 μs  12.937 ms    24.2711
   9 │ symbols     sha256     833.208 μs  7.607 ms      9.13022
  10 │ strings     sha256     833.417 μs  6.600 ms      7.9192
  11 │ dataframes  sha256     532.833 μs  775.917 μs    1.45621
  12 │ numbers     sha256     270.916 μs  374.417 μs    1.38204
```
