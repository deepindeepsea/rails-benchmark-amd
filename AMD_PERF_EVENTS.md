# AMD Zen 4/5 Performance Events Reference

## Corrected AMD-Specific Performance Monitoring Events

### ❌ **INCORRECT (Intel-specific):**
```bash
# These are Intel events - NOT supported on AMD:
LLC-loads
LLC-load-misses  
mem_load_retired.l3_miss
```

### ✅ **CORRECT AMD Events:**

## **AMD Zen 4 (M7A instances) Raw Performance Events**

### **Core Performance Events**
```bash
# Retired Instructions  
r00C0   # ex_ret_instr - Total retired instructions
r00C1   # ex_ret_ops - Total retired micro-ops  
r00C2   # ex_ret_brn - Total retired branches
r00C3   # ex_ret_brn_misp - Retired branch mispredictions

# Execution Pipeline
r0076   # ex_ret_mmx_fp_instr - Retired MMX/FP instructions
r0081   # ex_ret_ind_brn_instr - Retired indirect branch instructions  
r0087   # ex_ret_near_ret - Retired near returns
```

### **Cache Hierarchy Events**
```bash
# L1 Data Cache
r0040   # ls_dispatch.ld_dispatch - Load dispatches
r0041   # ls_dispatch.store_dispatch - Store dispatches
r0043   # ls_dispatch.ld_st_dispatch - Load+Store dispatches

# L2 Cache Access
r0064   # l2_request_g1.rd_blk_l - L2 read block requests (local)
r0065   # l2_request_g1.rd_blk_x - L2 read block requests (exclusive)
r060A   # l2_request_g2.group1 - L2 cache group 1 requests
r060B   # l2_request_g2.group2 - L2 cache group 2 requests

# L3 Cache Events  
r0004   # l3_lookup_state.all_coherent_accesses_to_l3
r001C   # l3_miss_latency - L3 cache miss latency
r001D   # l3_cache_accesses - Total L3 cache accesses
```

### **Memory and TLB Events**
```bash
# Load/Store Operations
r0029   # ls_dispatch.ld_dispatch - Loads dispatched to LS
r002A   # ls_dispatch.store_dispatch - Stores dispatched to LS  

# TLB Events
r0045   # l1_dtlb_miss - L1 data TLB misses
r0046   # l2_dtlb_miss - L2 data TLB misses  
r0047   # l1_itlb_miss - L1 instruction TLB misses
r0048   # l2_itlb_miss - L2 instruction TLB misses

# Memory Controller (UMC) Events
r0E03   # umc_mem_slot_clks - Memory controller active cycles
r0E05   # umc_cas_count_rd - Memory read CAS commands
r0E06   # umc_cas_count_wr - Memory write CAS commands
```

## **AMD Zen 5 (M8A instances) Enhanced Events**

### **Enhanced Pipeline Events**  
```bash
# Improved dispatch (up to 8 instructions per cycle)
r00C0   # ex_ret_instr - Retired instructions
r00C2   # ex_ret_brn - Retired branches (enhanced prediction)
r00C3   # ex_ret_brn_misp - Branch mispredictions (reduced)
r00C4   # ex_ret_brn_taken - Taken branches
```

### **Enhanced Cache Events**
```bash
# Improved L3 cache events
r0004   # l3_lookup_state.all_coherent_accesses_to_l3
r001E   # l3_cache_req_stat - L3 cache request status
r001F   # l3_cache_miss_req_stat - L3 cache miss requests

# Enhanced prefetcher events  
r0067   # l2_pf_hit_l2 - L2 prefetcher hits in L2
r0068   # l2_pf_miss_l2_hit_l3 - L2 prefetcher misses, L3 hits
```

### **Memory Controller Improvements (Zen 5)**
```bash
# DDR5 optimized events
r0E07   # umc_act_count - Memory activate commands  
r0E08   # umc_pre_count - Memory precharge commands
r0E09   # umc_ref_count - Memory refresh commands
```

## **Practical Usage Examples**

### **Rails JSON Serialization Analysis (Zen 4)**
```bash
# Focus on cache hierarchy for object-heavy workloads
perf stat -e cycles,instructions,r0064,r0065,r0004,r001C \
  wrk -t8 -c200 -d30s http://localhost:3000/json

# Expected patterns:
# - High r0064 (L2 reads) = object traversal  
# - High r001C (L3 misses) = memory-bound JSON encoding
# - Low r00C3/r00C2 ratio = good branch prediction
```

### **Rails Data Processing Analysis (Zen 5)**  
```bash
# Enhanced analysis for compute-heavy endpoints
perf stat -e r00C0,r00C2,r00C3,r00C4,r001E,r0067,r0068 \
  wrk -t8 -c200 -d30s http://localhost:3000/data

# Zen 5 advantages:
# - Higher r00C0/cycles ratio = better IPC
# - Lower r00C3/r00C2 ratio = superior branch prediction  
# - Higher r0067 ratio = effective prefetching
```

### **Memory Bandwidth Analysis**
```bash
# Memory controller events (both Zen 4/5)
perf stat -e r0E03,r0E05,r0E06,r0E07,r0E08 \
  wrk -t8 -c400 -d30s http://localhost:3000/data

# Key metrics:
# - r0E05+r0E06 = Total memory bandwidth usage
# - r0E07/r0E08 ratio = Memory access patterns  
# - r0E03 = Memory controller utilization
```

## **AMD vs Intel Event Mapping**

| **Intel Event** | **AMD Zen 4/5 Equivalent** | **Purpose** |
|------------------|----------------------------|-------------|
| `LLC-loads` | `r0004` (L3 accesses) | L3 cache activity |
| `LLC-load-misses` | `r001C` (L3 miss latency) | L3 cache misses |
| `mem_load_retired.l3_miss` | `r001C + r0E05` | Memory loads beyond L3 |
| `branch-loads` | `r00C2` (retired branches) | Branch operations |
| `branch-load-misses` | `r00C3` (branch mispredicts) | Branch prediction failures |

## **Performance Analysis Commands**

### **Basic AMD Analysis**
```bash
# Standard counters that work on all AMD systems
perf stat -e cycles,instructions,branches,branch-misses,\
L1-dcache-loads,L1-dcache-load-misses,L1-icache-load-misses \
  ./benchmark_optimized.sh
```

### **Advanced AMD Cache Analysis** 
```bash
# Raw AMD cache events for detailed analysis
perf stat -e r0064,r0065,r060A,r060B,r0004,r001C,r001D \
  wrk -t8 -c200 -d30s http://localhost:3000/json
```

### **AMD Memory Subsystem Analysis**
```bash
# TLB and memory controller events
perf stat -e r0045,r0046,r0047,r0048,r0E03,r0E05,r0E06 \
  wrk -t8 -c200 -d30s http://localhost:3000/data
```

## **Key Takeaways**

1. **Use AMD raw events** (r0XXX format) for detailed analysis
2. **Avoid Intel LLC events** - they don't exist on AMD  
3. **Focus on L3 lookup state** (r0004) instead of LLC-loads
4. **Use memory controller events** (r0E0X) for bandwidth analysis
5. **Zen 5 has enhanced events** for better performance insights

This provides the **correct AMD-specific performance monitoring** for accurate Rails benchmarking on M7A/M8A instances! 🚀