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
    ];
}
