# One Billion Row Challenge

Learn about 1BRC at [1brc.dev](https://1brc.dev/)

# Results

Execution time: **1.14** seconds.

```
CPU: Apple M4 Pro
RAM: 48 GB
MacOS: 26.6.2 (25G83)
Zig: 0.16.0
```

You can find each iteration as a branch of this repository prefixed with `N-`.

| N | Optimization              | Execution Time (s) | Speedup |
|---|---------------------------|--------------------|---------|
| - | Baseline                  | 141.597            |         |
| 0 | Zig implementation        | 27.998             | 5.057   |
| 1 | Find semicolon in reverse | 19.172             | 1.460   |
| 2 | Static allocation         | 16.044             | 1.195   |
| 3 | Custom temperature parser | 13.231             | 1.213   |
| 4 | Custom buffered reader    | 9.681              | 1.367   |
| 5 | Custom hash map           | 9.277              | 1.044   |
| 6 | Multi-threaded            | **1.140**          | 8.138   |
