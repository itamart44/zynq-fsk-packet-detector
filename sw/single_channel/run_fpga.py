import time
import numpy as np
import matplotlib.pyplot as plt
from pynq import Overlay, allocate

# -----------------------
# טעינת ה-FPGA
# -----------------------
ol = Overlay("fsk_project/design_1_wrapper.bit")
dma = ol.axi_dma_0

# -----------------------
# buffer (DMA אמיתי)
# -----------------------
buffer = allocate(shape=(64,), dtype=np.uint64)

# -----------------------
# state
# -----------------------
last_sync = 0
last_addr = -1

power0_val = 0
power1_val = 0

# -----------------------
# גרף
# -----------------------
plt.ion()
plt.figure()

power0_hist = []
power1_hist = []

# -----------------------
# loop
# -----------------------
while True:

    # -------- קבלת נתונים מה-FPGA --------
    dma.recvchannel.transfer(buffer)
    dma.recvchannel.wait()

    # -------- parsing --------
    for val in buffer:
        val = int(val)

        type_field = (val >> 32) & 0xF
        data = val & 0xFFFFFFFF

        # POWER0
        if type_field == 1:
            power0_val = np.int32(data)

        # POWER1
        elif type_field == 2:
            power1_val = np.int32(data)

            # שמירה לגרף
            power0_hist.append(power0_val)
            power1_hist.append(power1_val)

            if len(power0_hist) > 50:
                power0_hist.pop(0)
                power1_hist.pop(0)

        # -------- SYNC --------
        elif type_field == 3:
            sync = data & 1

            if sync == 1 and last_sync == 0:
                print(" SIGNAL DETECTED")

            last_sync = sync

        # -------- ADDRESS --------
        elif type_field == 4:
            addr = data & 0x7F

            if addr != last_addr:
                print(" ADDRESS:", addr)

            last_addr = addr

    # -------- גרף --------
    plt.clf()
    plt.plot(power0_hist, label="POWER F1")
    plt.plot(power1_hist, label="POWER F2")
    plt.legend()
    plt.title("Power Comparison (F1 vs F2)")
    plt.xlabel("Time")
    plt.ylabel("Power")
    plt.pause(0.01)

    time.sleep(0.05)
