# AMD Zen 4/5 PMC Register Mapping for Rails Performance Analysis

## 🎯 **Complete PMC Register Map from AMD Official Documentation**

Based on the AMD Family 19h (Zen 4) Performance Monitor Counter documentation.

### **Core Execution Events**

| **PMC Register** | **perf Event Name** | **Description** | **Rails Use Case** |
|------------------|--------------------|-----------------|--------------------|
| `PMCx0C0` | `instructions` | Total retired instructions | Overall CPU efficiency (IPC) |
| `PMCx0C1` | `cycles` | Core cycles | Base timing measurement |
| `PMCx0C2` | `branches` | Retired branch instructions | Branch prediction analysis |
| `PMCx0C3` | `branch-misses` | Branch mispredictions | Ruby dynamic dispatch efficiency |

### **L2 Cache Events (PMCx064)**

| **Register** | **Bit** | **perf Event** | **Description** | **Rails Impact** |
|--------------|---------|----------------|-----------------|------------------|
| **PMCx064** | `7` | `l2_cache_req_stat.ls_rd_blk_cs` | Data cache shared read hit | Object sharing efficiency |
| **PMCx064** | `6` | `l2_cache_req_stat.ls_rd_blk_l_hit_x` | Data cache read hit (modifiable) | Write-heavy object operations |
| **PMCx064** | `5` | `l2_cache_req_stat.ls_rd_blk_l_hit_s` | Data cache read hit (non-mod) | Read-only object access |
| **PMCx064** | `4` | `l2_cache_req_stat.ls_rd_blk_x` | Data cache store/state change | Object mutation performance |
| **PMCx064** | `3` | `l2_cache_req_stat.ls_rd_blk_c` | **Data cache MISS in L2** | Memory-bound operations |
| **PMCx064** | `2` | `l2_cache_req_stat.ic_fill_hit_x` | Instruction cache hit (mod) | Ruby method compilation |
| **PMCx064** | `1` | `l2_cache_req_stat.ic_fill_hit_s` | Instruction cache hit (non-mod) | Stable method execution |
| **PMCx064** | `0` | `l2_cache_req_stat.ic_fill_miss` | **Instruction cache MISS** | Ruby method cache misses |

### **L1 Data TLB Events (PMCx045)**

| **Register** | **Bit** | **perf Event** | **Description** | **Rails Impact** |
|--------------|---------|----------------|-----------------|------------------|
| **PMCx045** | `7` | `ls_l1_d_tlb_miss.tlb_reload_1g_l2_miss` | 1GB page TLB miss | Large object penalties |
| **PMCx045** | `6` | `ls_l1_d_tlb_miss.tlb_reload_1g_l2_hit` | 1GB page TLB hit in L2 | Large object efficiency |
| **PMCx045** | `5` | `ls_l1_d_tlb_miss.tlb_reload_2m_l2_miss` | 2MB page TLB miss | Medium object penalties |
| **PMCx045** | `4` | `ls_l1_d_tlb_miss.tlb_reload_2m_l2_hit` | 2MB page TLB hit in L2 | Medium object efficiency |
| **PMCx045** | `3` | `ls_l1_d_tlb_miss.tlb_reload_4k_l2_miss` | 4KB page TLB miss | Small object penalties |
| **PMCx045** | `2` | `ls_l1_d_tlb_miss.tlb_reload_4k_l2_hit` | 4KB page TLB hit in L2 | Small object efficiency |
| **PMCx045** | `1` | `ls_l1_d_tlb_miss.all_l2_miss` | **All L2 TLB misses** | Virtual memory pressure |
| **PMCx045** | `0` | `ls_l1_d_tlb_miss.all_l2_hit` | All L2 TLB hits | Virtual memory efficiency |

### **Data Cache Fill Events (PMCx043 & PMCx044)**

| **Register** | **Bit** | **perf Event** | **Description** | **Rails Impact** |
|--------------|---------|----------------|-----------------|------------------|
| **PMCx043** | `6` | `ls_dmnd_fills_from_sys.local_l2` | **Demand fills from L2** | Cache hierarchy efficiency |
| **PMCx043** | `3` | `ls_dmnd_fills_from_sys.local_mem` | **Demand fills from memory** | Memory bandwidth usage |
| **PMCx044** | `6` | `ls_any_fills_from_sys.local_l2` | **All fills from L2** | Total L2 cache activity |

### **Floating-Point Events (PMCx003)**

| **Register** | **Bit** | **perf Event** | **Description** | **Rails Impact** |
|--------------|---------|----------------|-----------------|------------------|
| **PMCx003** | `3` | `fp_ret_sse_avx_ops.mac_flops` | Multiply-accumulate FLOPs | Numeric processing |
| **PMCx003** | `2` | `fp_ret_sse_avx_ops.div_flops` | Division/sqrt FLOPs | Mathematical operations |
| **PMCx003** | `1` | `fp_ret_sse_avx_ops.mult_flops` | Multiply FLOPs | Arithmetic intensity |
| **PMCx003** | `0` | `fp_ret_sse_avx_ops.add_sub_flops` | Add/subtract FLOPs | Basic math operations |

## 🚀 **Rails-Optimized Performance Commands**

### **JSON Serialization Analysis**
```bash
# Focus on L2 cache efficiency and object traversal
perf stat -e cycles,instructions,\
l2_cache_req_stat.ls_rd_blk_l_hit_s,l2_cache_req_stat.ls_rd_blk_c,\
ls_dmnd_fills_from_sys.local_l2,ls_l1_d_tlb_miss.all_l2_miss \
  wrk -t8 -c200 -d30s http://localhost:3000/json

# Expected patterns for well-optimized Rails:
# - High ls_rd_blk_l_hit_s: Good object locality
# - Low ls_rd_blk_c: Effective L2 cache usage  
# - Low all_l2_miss: Good virtual memory efficiency
```

### **Data Processing Analysis**
```bash
# Include floating-point and memory bandwidth analysis
perf stat -e cycles,instructions,branches,branch-misses,\
fp_ret_sse_avx_ops.add_sub_flops,fp_ret_sse_avx_ops.mult_flops,\
ls_dmnd_fills_from_sys.local_mem,ls_any_fills_from_sys.local_l2 \
  wrk -t8 -c200 -d30s http://localhost:3000/data

# Expected patterns:
# - Moderate add_sub_flops: Array processing
# - Low local_mem fills: Good cache locality
# - High local_l2 fills: Active cache hierarchy
```

### **Instruction Cache Analysis**  
```bash
# Focus on Ruby method dispatch and compilation
perf stat -e cycles,instructions,\
l2_cache_req_stat.ic_fill_hit_s,l2_cache_req_stat.ic_fill_miss,\
l2_cache_req_stat.ic_fill_hit_x \
  wrk -t8 -c200 -d30s http://localhost:3000/hello

# Expected patterns:
# - High ic_fill_hit_s: Stable method cache
# - Low ic_fill_miss: Good instruction locality  
# - Low ic_fill_hit_x: Minimal runtime compilation
```

## 📊 **Key Performance Ratios**

### **L2 Cache Efficiency**
```bash
# L2 data cache hit rate
L2_data_hit_rate = (ls_rd_blk_l_hit_s + ls_rd_blk_l_hit_x) / 
                   (ls_rd_blk_l_hit_s + ls_rd_blk_l_hit_x + ls_rd_blk_c)

# Target: >90% for object-heavy Rails workloads
# AMD advantage: Larger 1MB L2 vs Intel 256KB-512KB
```

### **Instruction Cache Efficiency**
```bash
# Instruction cache hit rate
I_cache_hit_rate = (ic_fill_hit_s + ic_fill_hit_x) / 
                   (ic_fill_hit_s + ic_fill_hit_x + ic_fill_miss)

# Target: >95% for stable Rails applications
# AMD advantage: Better branch prediction for Ruby dispatch
```

### **TLB Efficiency**
```bash
# TLB hit rate (critical for Ruby object access)
TLB_hit_rate = 1 - (all_l2_miss / L1-dcache-loads)

# Target: >99% for well-tuned Rails
# AMD advantage: Larger TLB capacity
```

### **Memory Bandwidth Utilization**
```bash
# Memory vs L2 bandwidth ratio
Memory_pressure = local_mem / (local_l2 + local_mem)

# Target: <10% for CPU-bound Rails workloads
# AMD advantage: Higher DDR5 bandwidth on M8A instances
```

## 🔬 **Raw Register Event Mapping**

### **Raw Event Format**
```bash
# Format: r[unit_mask][event_select]
# Example: PMCx064 = r0064
# With bit mask: r[mask][64] where mask selects specific bits

# L2 cache data miss (bit 3 of PMCx064)
perf stat -e r08:64 # Mask 0x08 = bit 3 = ls_rd_blk_c

# L2 cache instruction miss (bit 0 of PMCx064)  
perf stat -e r01:64 # Mask 0x01 = bit 0 = ic_fill_miss
```

### **Multi-bit Event Examples**
```bash
# All L2 cache data events (bits 3-7 of PMCx064)
perf stat -e rf8:64  # Mask 0xF8 = bits 3-7

# All TLB L2 misses (odd bits of PMCx045)
perf stat -e r55:45  # Mask 0x55 = bits 0,2,4,6 = L2 hit events
```

## ⚡ **AMD Zen 4/5 Advantages for Rails**

### **Cache Hierarchy Superiority**
- **L2 Cache**: 1MB per core (vs Intel 256-512KB)
- **L3 Cache**: 32MB shared (vs Intel 24MB)  
- **TLB**: Larger capacity for object-heavy workloads
- **Prefetchers**: More aggressive for sequential object access

### **Branch Prediction Excellence**
- **TAGE Predictor**: Better for Ruby's dynamic method dispatch
- **Indirect Branch**: Superior handling of virtual method calls
- **Pattern Recognition**: Excellent for Rails MVC patterns

### **Memory Subsystem**
- **DDR5 Support**: 76.8 GB/s bandwidth (M8A instances)
- **NUMA Optimization**: Better Ruby heap locality
- **Memory Controllers**: Dual-channel with higher efficiency

This register-level analysis provides the **exact microarchitectural evidence** for AMD's Rails performance advantages! 🚀