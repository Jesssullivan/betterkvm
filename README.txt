Hey!  This is a work in progress.

This project spawned from the need to expand remote developement to support NoneX86 initiatives.


This project converges tinyland.dev KVM hardware via a HKS1601A1U 16-port KVM; this allows us
to provide Risc-V hardware (musebooks and V300, Spacemit K1 dev boards etc), ARM boards,
x86 servers, and their debug interfaces to folks outside of the lab.

16-port machine mapping:
  1: honey           9: sdr-1
  2: bumble (ATX)   10: g2-1
  3: petting-zoo    11: g2-2
  4: xoxd-bates     12: t-deck
  5: yoga           13: tdeck-pro
  6: mbp-13         14-16: (unassigned)
  7: betsy
  8: musey


Tinyland folk
    |
    | Tailscale VPN (WireGuard)
    | mTLS admin mgmt (Nebula)
    |
+---+---------------------------------+
|   Tailscale Subnet & local DERP     |  Pi #2 (NixOS)
|   serial-console                    |  advertises <ipv4>/24
+---+---------------------------------+
    |
    | IoT Management Network (<ipv4>/24)
    |
+---+--------+----------+------+----------+
|            |          |      |          |
v            v          v      v          v
Pi #1        TESmart    Gearmo Smart     Lab
(PiKVM A3)   HKS1601A1U 16-port PDU     Machines
             KVM Switch Serial (NUT)     (16 ports)
             16-port    Hub
             + RS232
