# https://nixos.wiki/wiki/Printing
#
# tips:
#
# find printer device URIs:
#   lpinfo -v
# 
# check whether CUPS knows a driver/printer model:
#   lpinfo -m | grep -i -E 'officejet.*3830|3830'
#
# Use the CUPS web UI and pick the model there (it often exposes more options than KDE):
#   http://localhost:631 → Administration → Add Printer
#
# test IPP printing:
#   TEST="$(nix eval --raw nixpkgs#cups.outPath)/share/cups/ipptool/get-printer-attributes.test"
#   ipptool -tv ipp://192.168.178.78:631/ipp/print "$TEST"
#
#   or more like mDNS output:
#
#   ipptool -tv ipp://192.168.178.78:631/ipp/print "$TEST" \
#     | grep -E "printer-name|printer-make-and-model|printer-uri-supported|ipp-versions-supported|document-format-supported"



{ pkgs, lib, ... }:

{
    services.printing.enable = true;

    # view with: journalctl --follow --unit=cups
    services.printing.logLevel = "debug";

    # service discovery (for e.g. printing)
    services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
    };

    services.printing.drivers = lib.singleton (pkgs.linkFarm "drivers" [
    { 
        name = "share/cups/model/okib430.ppd";
        path = ../drivers/OKB430_a.ppd;
    }
    ])
    ++ [
        pkgs.hplip # Drivers for HP printers
    ];

    # issue with systemd.ensure-printers.service failing: https://github.com/NixOS/nixpkgs/issues/78535
    hardware.printers.ensurePrinters = [
    {
        name        = "OKI_B430_Arbeitszimmer";
        description = "OKI_B430_Arbeitszimmer";
        location    = "Eppisburg Arbeitszimmer";
        deviceUri   = "lpd://192.168.178.77/queue";
        model       = "okib430.ppd";
        ppdOptions = {
            PageSize = "A4";
            Duplex = "DuplexNoTumble";  # Enables double-sided printing with long edge binding
        };
    }
    {
        name        = "HP_OfficeJet_3830";
        description = "HP_OfficeJet_3830";
        location    = "Eppisburg";
        deviceUri   = "ipp://192.168.178.78/ipp/print";
        # From `lpinfo -m`:
        model       = "HP/hp-officejet_3830_series.ppd.gz";
        ppdOptions = {
            PageSize = "A4";
        };
    }
    ];
}
