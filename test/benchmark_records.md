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
