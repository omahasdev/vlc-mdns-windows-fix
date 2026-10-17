"""Copy of the libmicrodns 0.2.0 socket logic that VLC 3.0.x uses: one socket
for each local IPv4 address, each bound to 0.0.0.0:5353 with SO_REUSEADDR and
joined to 224.0.0.251 on its own interface. The same PTR query is sent from
every socket. Without --set-if no IP_MULTICAST_IF is set (exactly like
libmicrodns). With --set-if each socket sends on its own interface.
Prints which socket receives the Chromecast answer."""
import argparse
import select
import socket
import struct
import time

MDNS_GROUP = "224.0.0.251"
MDNS_PORT = 5353
SERVICE = "_googlecast._tcp.local"
QTYPE_PTR = 12
QCLASS_IN = 1
MCAST_TTL = 255
LISTEN_SECONDS = 6
BUFFER_SIZE = 9000


def build_query(name):
    header = struct.pack("!6H", 0, 0, 1, 0, 0, 0)
    qname = b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0"
    return header + qname + struct.pack("!2H", QTYPE_PTR, QCLASS_IN)


def local_ipv4():
    infos = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
    return sorted({i[4][0] for i in infos})


def open_socket(local_ip, set_if):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", MDNS_PORT))
    membership = socket.inet_aton(MDNS_GROUP) + socket.inet_aton(local_ip)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, MCAST_TTL)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
    if set_if:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(local_ip))
    return sock


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--set-if", action="store_true", help="set IP_MULTICAST_IF on each socket")
    parser.add_argument("--no-send", action="store_true", help="only listen, do not send a query")
    parser.add_argument("--seconds", type=float, default=LISTEN_SECONDS, help="listen time")
    parser.add_argument("ips", nargs="*", help="local IPv4 addresses (default: all)")
    args = parser.parse_args()
    ips = args.ips or local_ipv4()
    socks = {open_socket(ip, args.set_if): ip for ip in ips}
    query = build_query(SERVICE)
    if not args.no_send:
        for sock in socks:
            sock.sendto(query, (MDNS_GROUP, MDNS_PORT))
    answers = {ip: {} for ip in ips}
    start = time.time()
    deadline = start + args.seconds
    while time.time() < deadline:
        ready, _, _ = select.select(list(socks), [], [], 0.5)
        for sock in ready:
            data, addr = sock.recvfrom(BUFFER_SIZE)
            if b"googlecast" in data and b"fn=" in data:
                got = answers[socks[sock]]
                got.setdefault(addr[0], []).append(round(time.time() - start))
    print(f"IP_MULTICAST_IF set: {args.set_if}, query sent: {not args.no_send}, {args.seconds:.0f} s")
    for ip in ips:
        got = "; ".join(f"{src} at {t} s" for src, t in sorted(answers[ip].items())) or "no answer"
        print(f"  socket joined on {ip}: {got}")
    for sock in socks:
        sock.close()


if __name__ == "__main__":
    main()
