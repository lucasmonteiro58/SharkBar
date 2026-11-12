"""Escuta (somente leitura) os relatórios de status do dongle Attack Shark X6 (1d57:fa60)."""
import time, hid

paths = [d["path"] for d in hid.enumerate(0x1D57, 0xFA60)
         if d["interface_number"] == 2 or d["usage_page"] == 0x0C]
seen = set()
devs = []
for d in hid.enumerate(0x1D57, 0xFA60):
    print(f"if{d['interface_number']} up={d['usage_page']:04x} u={d['usage']:02x} {d['path']}")
for p in dict.fromkeys(d["path"] for d in hid.enumerate(0x1D57, 0xFA60)):
    try:
        h = hid.device(); h.open_path(p); h.set_nonblocking(True); devs.append((p, h))
    except Exception as e:
        print("não abriu", p, e)
end = time.time() + 6
while time.time() < end:
    for p, h in devs:
        r = h.read(64)
        if r and r[0] == 0x03:
            print(p.decode(), " ".join(f"{b:02x}" for b in r))
    time.sleep(0.01)
