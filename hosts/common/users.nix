_: {
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "dialout"
    ]; # dialout for serial ports
    openssh.authorizedKeys.keys = [
      # Replace with your SSH public key(s)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1Lk/BdxtbeZcnFZG3wrqtQi40iKw11vmFlsozQmd1t Jess's Gitlab Key"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Disable root password login (SSH key only)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1Lk/BdxtbeZcnFZG3wrqtQi40iKw11vmFlsozQmd1t Jess's Gitlab Key"
  ];
}
