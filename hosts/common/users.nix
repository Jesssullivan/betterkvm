_: {
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "dialout" ]; # dialout for serial ports
    openssh.authorizedKeys.keys = [
      # Replace with your SSH public key(s)
      "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_KEY admin@workstation"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Disable root password login (SSH key only)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_KEY admin@workstation"
  ];
}
