{ lib, pkgs, config, ... }:
with lib;
let
  # Shorter name to access final settings a 
  # user of hello.nix module HAS ACTUALLY SET.
  # cfg is a typical convention.
  cfg = config.services.data_writer;
in {

  config = {
    # https://nixos.org/manual/nixos/stable/options.html search for systemd.services.<name>. to get list of all of the options for 
    # new systemd services
    
    environment.systemPackages = [
        pkgs.busybox
        pkgs.python310
        pkgs.libqmi
      ];

    systemd.services.data_writer = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.After = [ "network.target" ];
      # https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html serviceconfig
      serviceConfig.ExecStart =
        "${pkgs.py_data_acq_pkg}/bin/runner.py ${pkgs.proto_gen_pkg}/bin ${pkgs.ht_can_pkg}";
      serviceConfig.ExecStop = "/bin/kill -SIGINT $MAINPID";
      serviceConfig.Restart = "on-failure";
    };

    systemd.services.configure-lte-modem = {
      serviceConfig = {
        Type = "oneshot";

        ExecStart =
          let
            script = pkgs.writeScript "configure-lte-modem" ''
              qmicli=${pkgs.libqmi}/bin/qmicli
              ip=${pkgs.iproute2}/bin/ip
              # wait a bit until the device is (hopefully) ready
              sleep 20;
              device="/dev/cdc-wdm0" # todo: get this from udev
              iface=$($qmicli -p -d $device --get-wwan-iface)
              # make sure the iface is down for the next step
              $ip link set $iface down
              # set to raw-ip mode
              echo "Y" > /sys/class/net/$iface/qmi/raw_ip
              # set link up
              $ip link set $iface up
              # register v4
              $qmicli -p -d $device --wds-start-network="ip-type=4,apn=internet.telekom,password=t-d1,username=telekom" --client-no-release-cid
            '';
          in

          "${pkgs.bash}/bin/bash ${script}";
      };
    };
  
    services.udev.extraRules = ''
      # lte modem
      KERNEL=="cdc-wdm[0-9]*", SUBSYSTEMS=="usb", DRIVERS=="qmi_wwan", ACTION=="add", ENV{SYSTEMD_WANTS}+="configure-lte-modem.service" TAG+="systemd"
    '';

    systemd.network = {
      networks = {
        "40-qmi-lte-modem" = {
          matchConfig = {
            Driver = "qmi_wwan";
          };

          linkConfig = {
            # the link is brought up by the configure-lte-modem unit during configuration
            ActivationPolicy = "manual";
          };

          networkConfig = {
            DHCP = "ipv4";
            LLDP = "no"; # see https://github.com/systemd/systemd/issues/20090
          };

          dhcpV4Config = {
            RouteTable = 11;
            # there's no mac on the interface, see https://github.com/systemd/systemd/issues/20090
            ClientIdentifier = "duid-only";
          };
        };
      };
    };
  };
}
