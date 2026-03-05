# FPGA Architecture Design
## Multi-Channel FSK Signal Detection System

This document describes the FPGA architecture used to detect FSK transmissions,
extract packet addresses, and report events to the CPU.

The FPGA performs real-time signal processing while the CPU manages the system
and reads the detected events.

---

# System Overview

The FPGA processes incoming samples using a DSP pipeline.

Signal flow:

Samples  
→ Energy Detection  
→ Sample Buffer  
→ FFT  
→ Frequency Detection  
→ Bitstream Generation  
→ Sync Detection  
→ Address Extraction  
→ Event Generation  
→ FIFO  
→ CPU Interface

---

# FPGA Block Diagram
