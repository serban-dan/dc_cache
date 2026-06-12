# 32 KiB 4-Way Set-Associative Cache

## Project Description

This project is a Verilog implementation of a 32 KiB 4-way set-associative cache. It features an LRU replacement policy and a write-back/write-allocate scheme. The controller is designed to interface with a CPU and a main memory model.

## Specifications

- Cache Size: 32 KiB (256 sets x 4 ways x 8 words x 4 bytes)
- Block Size: 8 words (256 bits)
- Word Size: 32 bits
- Main Memory: 8 MiB (262,144 blocks)
- Addressing: 21-bit word-addressable
  - TAG: bits [20:11] (10 bits)
  - INDEX: bits [10:3] (8 bits)
  - OFFSET: bits [2:0] (3 bits)
- Replacement Policy: LRU with 2-bit age counters
- Write Policy: Write-back, Write-allocate

## File Structure

```

.
├── README.md
├── TEST_RESULTS.md
├── build
│   ├── cache_waves.vcd
│   └── sim_cache.vvp
├── cache_setup.gtkw                - Waveform viewer configuration
├── makefile                        - Build targets
├── src
│   ├── cache_controller.v          - Main FSM, address decoding, LRU logic
│   ├── cache_way.v                 - Single cache way SRAM
│   └── memory.v                    - Main memory simulation (8 MiB)
└── tb
    ├── generate_data.py            - Python script to generate memory data
    ├── mem_data.txt                - Binary memory data (262,144 lines)
    ├── mem_data_final.txt          - Memory dump for verification
    ├── tb_cache.v                  - Basic functional test (6 phases)
    └── tb_cache_comprehensive.v    - Stress test (7 test patterns)

```

## Building and Running

```bash
cd /home/dan/Documents/UPT/Sem_4/DC/project_cache

make cache              # Run basic functional test
make comprehensive      # Run comprehensive stress test
make clean              # Clean build artifacts
```

## Test Results

Both test suites pass successfully. See TEST_RESULTS.md for detailed results.

Basic Test (tb_cache.v):
- All 6 phases pass
- Cache fill, LRU updates, dirty bit handling, write-back verified

Comprehensive Test (tb_cache_comprehensive.v):
- All 7 test patterns pass
- 376 cache hits out of 377 reads (99.73% hit rate)
- Zero errors

## Implementation Notes

- Cache uses 2-bit age counters for LRU replacement (0 = most recent, 3 = least recent)
- Write-back occurs atomically when a dirty block is evicted
- Dirty blocks are only written back when their set position is needed for a new block
- FSM handles all miss and hit scenarios correctly
- Hit detection uses parallel 4-way tag matching
