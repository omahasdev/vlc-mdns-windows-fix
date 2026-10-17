"""Find the interface that Windows uses to send multicast from a socket bound
to 0.0.0.0 without IP_MULTICAST_IF (the libmicrodns case). One listener socket
joins 224.0.0.251 on each local IPv4 address. A sender socket without
IP_MULTICAST_IF sends a marker packet with multicast loopback on. The listener
that gets the loopback copy shows the send interface."""
import select
import socket
import time
import uuid

MDNS_GROUP = "224.0.0.251"
MDNS_PORT = 5353
LISTEN_SECONDS = 3
BUFFER_SIZE = 9000


def local_ipv4():
    infos = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
    return sorted({i[4][0] for i in infos}) + ["127.0.0.1"]


def listener(local_ip):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", MDNS_PORT))
    membership = socket.inet_aton(MDNS_GROUP) + socket.inet_aton(local_ip)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
    return sock


def main():
    ips = local_ipv4()
    listeners = {}
    for ip in ips:
        try:
            listeners[listener(ip)] = ip
        except OSError as err:
            print(f"cannot join on {ip}: {err}")
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sender.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sender.bind(("0.0.0.0", MDNS_PORT))
    sender.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
    marker = uuid.uuid4().bytes
    sender.sendto(marker, (MDNS_GROUP, MDNS_PORT))
    seen = {}
    deadline = time.time() + LISTEN_SECONDS
    while time.time() < deadline:
        ready, _, _ = select.select(list(listeners), [], [], 0.5)
        for sock in ready:
            data, addr = sock.recvfrom(BUFFER_SIZE)
            if data == marker:
                seen[listeners[sock]] = addr[0]
    for ip in ips:
        if ip in seen:
            print(f"listener on {ip}: got marker, source address {seen[ip]}")
        else:
            print(f"listener on {ip}: nothing")


if __name__ == "__main__":
    main()
