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

```
12×5 DataFrame
 Row │ benchmark   hash       base        trait       ratio     
     │ SubStrin…   SubStrin…  String      String      Float64   
─────┼──────────────────────────────────────────────────────────
   1 │ structs     crc        70.334 μs   67.829 ms   964.379
   2 │ tuples      crc        71.625 μs   11.620 ms   162.229
   3 │ symbols     crc        536.875 μs  6.492 ms     12.0917
   4 │ strings     crc        536.750 μs  5.389 ms     10.04
   5 │ dataframes  crc        71.625 μs   716.292 μs   10.0006
   6 │ numbers     crc        35.208 μs   331.875 μs    9.42612
   7 │ structs     sha256     575.125 μs  73.509 ms   127.813
   8 │ tuples      sha256     575.334 μs  13.197 ms    22.9381
   9 │ dataframes  sha256     570.375 μs  1.514 ms      2.65374
  10 │ numbers     sha256     286.208 μs  735.959 μs    2.57141
  11 │ symbols     sha256     3.999 ms    8.176 ms      2.04456
  12 │ strings     sha256     4.077 ms    6.947 ms      1.70391
```
