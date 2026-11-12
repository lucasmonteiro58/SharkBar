"""Sonda somente-leitura do BlackShark V3 Pro (1532:0577)."""
import sys, time, hid

VID, PID = 0x1532, 0x0577

def frame(cmd, args=b""):
    b = bytearray(64)
    b[0] = 0x02
    b[2] = 0x60
    b[6] = 4 + len(args)
    b[9] = 0x80
    b[10] = cmd
    b[12] = len(args)
    b[13:13 + len(args)] = args
    x = 0
    for v in b[:62]:
        x ^= v
    b[62] = x
    return bytes(b)

def hx(b): return " ".join(f"{v:02x}" for v in b)

d = hid.device()
d.open(VID, PID)
d.set_nonblocking(True)
# uso: probe.py 21 2a 15:00 60:03   (cmd[:arg,arg] em hex)
cmds = sys.argv[1:] or ["21", "2a"]
for spec in cmds:
    c, _, a = spec.partition(":")
    c = int(c, 16)
    f = frame(c, bytes(int(x, 16) for x in a.split(",") if x))
    print(f">> {c:02x}: {hx(f[:16])} ... {f[62]:02x}")
    d.write(f)
    t = time.time()
    while time.time() - t < 0.6:
        r = d.read(64)
        if r:
            print(f"<< {hx(r)}")
        else:
            time.sleep(0.01)
d.close()
