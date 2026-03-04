# Multi-Channel FSK Signal Detection System
## System Algorithm Design

This document defines the algorithmic design of the system before hardware implementation.

The goal of the system is to detect FSK transmissions, extract the destination address,
and generate events that are sent to the CPU.

---

# 1. Signal Parameters

Sampling rate:

Fs = 1 MHz

Sample width:

16-bit signed

---

# 2. FSK Modulation

Binary Frequency Shift Keying (BFSK)

bit 0 → f0 = 100 kHz  
bit 1 → f1 = 120 kHz

Frequency difference:

Δf = 20 kHz

---

# 3. FFT Parameters

FFT size:

NFFT = 256

Frequency resolution:

Δf = Fs / NFFT  
Δf = 1,000,000 / 256 ≈ 3906.25 Hz

Each FFT window represents one bit:

Nb = 256 samples/bit

---

# 4. FFT Bin Selection

The bin index is calculated as:

k = round(f / Δf)

For the selected frequencies:

f0 = 100 kHz → k0 = 26  
f1 = 120 kHz → k1 = 31

Bit decision rule:

if P[k1] > P[k0] → bit = 1  
else → bit = 0

Power calculation:

P[k] = Re[k]^2 + Im[k]^2

---

# 5. Frame Structure

The transmitted frame contains:

Preamble = 16 bits  
Sync = 16 bits  
Address = 8 bits

Frame format:

| PREAMBLE | SYNC | ADDRESS |

Total frame length:

40 bits

Samples per frame:

40 × 256 = 10240 samples

---

# 6. Energy Detection

Before performing FFT, the system checks if a signal is present.

Energy calculation:

E = Σ x[n]^2

Window length:

256 samples

Noise energy is measured during calibration:

E_noise = average energy of noise windows

Detection threshold:

T_E = 3 × E_noise

Decision rule:

if E > T_E → signal present  
else → noise

---

# 7. Sync Detection

Sync detection uses correlation.

Sync length:

L = 16 bits

Correlation:

C = Σ u_b[i] · u_s[i]

Threshold:

T_C = L − 2 = 14

Detection condition:

C ≥ 14 → SYNC detected

Sync search method:

Sliding window (shift register of 16 bits)

---

# 8. Address Extraction

After Sync detection, the next 8 bits are interpreted as the destination address.

Address length:

8 bits

The event format stores the address as 16 bits for alignment.

---

# 9. Event Generation

When a valid frame is detected, an event is created.

Event fields:

channel_id  
address  
sync_score  
timestamp  
latency

---

# 10. Event Format

Each event contains 4 words (32 bits each).

Word0:
- channel_id
- address

Word1:
- sync_score

Word2:
- timestamp (FPGA clock cycles)

Word3:
- latency (FPGA clock cycles)

---

# 11. CPU Communication

Events are transferred to the CPU using:

FIFO

FIFO depth:

32 events

Each new event triggers:

Interrupt to CPU

---

# 12. Channel Configuration

The architecture is parameterized.

NUM_CHANNELS generic

Default configuration:

NUM_CHANNELS = 1

Future expansion:

NUM_CHANNELS = 4
