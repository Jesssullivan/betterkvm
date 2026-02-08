Hey!  This is a work in progress.

This project spawned from the need to expand remove developement to support NoneX86 initiatives.


This project converges tinyland.dev KVM hardware via a HKS801-M24 KVM; this allows us to provide
Risc-V hardware (musebooks and V300, Spacemit K1 dev boards etc) and their debug interfaces to folks outside of the lab.


Tinyland folk
    |
    | Tailscale VPN (WireGuard)
    | mTLS admin mgmt (Nebula)
    |
+---+---------------------------------+
|   Tailscale Subnet & local DERP     |  Pi #2 (NixOS)
|   serial-console                    |  advertises <ipv4>//24
+---+---------------------------------+
    |
    | IoT Management Network (<ipv4>/24)
    |
+---+--------+----------+------+----------+
|            |          |      |          |
v            v          v      v          v
Pi #1        TESmart    Gearmo Smart     Lab
(PiKVM)      HKS801-M24 8-port PDU      Machines
             KVM Switch Serial (NUT)
             8-port     Hub
