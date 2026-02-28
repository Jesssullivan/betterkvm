_: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Pi 4B ethernet interface
  networking = {
    useDHCP = false;
    interfaces.end0.useDHCP = true; # Pi 4B uses "end0"
  };
}
